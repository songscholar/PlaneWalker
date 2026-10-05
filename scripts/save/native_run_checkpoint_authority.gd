class_name NativeRunCheckpointAuthority
extends RefCounted

const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Player := preload("res://scripts/player/player_controller.gd")
const Runtime := preload("res://scripts/dungeon/room_runtime.gd")
const Controller := preload("res://scripts/dungeon/room_controller.gd")
const SceneHost := preload("res://scripts/dungeon/room_scene_host.gd")
const RoomContract := preload("res://scripts/dungeon/room_scene_contract.gd")
const Seed := preload("res://scripts/core/seed_service.gd")
const Scene := preload("res://scripts/dungeon/launch_room_scene.gd")
const NativeDriver := preload("res://scripts/dungeon/native_launch_encounter_driver.gd")
const SCENE_BINDING_FIELDS := ["node_id", "content_id", "room_type", "floor_id", "palette_id", "environment_rule_id", "room_seed", "binding_generation", "reduced_motion", "hit_flash_enabled"]
const FIELDS := ["schema_version", "run_id", "run_revision", "run_digest", "launch_receipt", "player_codec", "floor_effect_state", "room_state", "scene_binding", "publication_state", "digest"]
const V2_FIELDS := ["schema_version", "run_id", "run_revision", "run_digest", "launch_receipt", "player_codec", "encounter_codec", "floor_effect_state", "room_state", "scene_binding", "publication_state", "digest"]
const PUBLICATION_FIELDS := ["route_ids", "floor_start_ids", "floor_completion_ids", "floor_rule_frame_origin", "player_process_mode", "controller_process_mode", "selection_safety", "dungeon_selection"]
const LIVE_PHASES := [Phase.Value.ROOM_ACTIVE, Phase.Value.COMBAT_ACTIVE, Phase.Value.BOSS_ACTIVE]
const SAFE_PHASES := [Phase.Value.RUN_PREPARING, Phase.Value.ROOM_ENTERING, Phase.Value.ROOM_ACTIVE, Phase.Value.COMBAT_ACTIVE, Phase.Value.BOSS_ACTIVE, Phase.Value.ROOM_RESOLVING, Phase.Value.SELECTION_ACTIVE, Phase.Value.ROOM_TRANSITION, Phase.Value.VICTORY, Phase.Value.DEFEAT]


static func capture(host: Node) -> Dictionary:
	if not _native_host(host) or not host.is_inside_tree():
		return failure(&"NATIVE_BINDING_INVALID")
	var parts: Dictionary = host.native_checkpoint_participants()
	var player: Variant = parts.get("player")
	var controller: Variant = parts.get("controller")
	var runtime: Variant = parts.get("runtime")
	var scene_host: Variant = parts.get("scene_host")
	var service: Variant = parts.get("profile")
	if not player is Player or not is_instance_valid(player) or not player.is_inside_tree() or not controller is Controller or not runtime is Runtime or not service is RefCounted or not service.has_method("snapshot") or bool(parts.get("busy", true)):
		return failure(&"NATIVE_BINDING_INVALID")
	var run: Dictionary = host.runtime_snapshot()
	var room: Dictionary = runtime.snapshot()
	var runner: Node = controller.encounter_runner()
	var native: Dictionary = runner.native_cold_snapshot() if runner.is_active() else {}
	if not safe_run(run, not native.is_empty()):
		return failure(&"CHECKPOINT_UNSAFE", "phase_%d" % int(run.get("phase", -1)))
	if not inactive_room(room) and not live_room(room, native):
		return {"ok": false, "code": &"CHECKPOINT_UNSAFE", "context": {"stage": "room", "room": room}}
	var enemies: Node = controller.get_node_or_null("Enemies")
	var native_count := 0
	if enemies != null:
		for enemy: Node in enemies.get_children():
			if not enemy.is_queued_for_deletion() and not runner.owns_retired_native_actor(enemy):
				native_count += 1
	if enemies == null or native_count != native.get("actors", {}).size():
		return failure(&"CHECKPOINT_UNSAFE", "live_hostiles")
	var replay: Dictionary = player.full_player_replay_snapshot()
	if replay.is_empty() or not Replay.validate_full_player_snapshot(replay, replay.get("identity", {})).ok or str(replay.identity.run_id) != str(run.run_id):
		return failure(&"NATIVE_CHECKPOINT_INVALID", "player")
	var encoded := Replay.encode_replay_json(replay)
	if not encoded.ok:
		return encoded
	var encounter_codec := ""
	if not native.is_empty():
		var encoded_encounter := Replay.encode_replay_json(native)
		if not encoded_encounter.ok:
			return failure(&"CHECKPOINT_UNSAFE", "native_codec")
		encounter_codec = encoded_encounter.json
	var launch: Dictionary = service.call("_launch_for_run", run)
	if launch.is_empty():
		return failure(&"NATIVE_CHECKPOINT_INVALID", "launch")
	var binding: Dictionary = {}
	var target: Dictionary = parts.facade.current_room_restore_target()
	if not target.is_empty():
		if not scene_host is SceneHost or scene_host.active_room() == null:
			return failure(&"NATIVE_CHECKPOINT_INVALID", "scene")
		var native_scene: Node = scene_host.active_room()
		binding = native_scene.binding_snapshot()
		var details: Dictionary = binding.get("binding", {})
		if not scene_binding_matches(binding, target) or not RoomContract.validate(native_scene, target.template).ok or details.get("floor_id") != run.floor_plan.floor_id:
			return failure(&"NATIVE_CHECKPOINT_INVALID", "scene_binding")
	elif scene_host is SceneHost and scene_host.active_room() != null:
		return failure(&"NATIVE_CHECKPOINT_INVALID", "unexpected_scene")
	var checkpoint := {
		"schema_version": 2,
		"run_id": run.run_id,
		"run_revision": int(run.revision),
		"run_digest": canonical(run).sha256_text(),
		"launch_receipt": launch.duplicate(true),
		"player_codec": encoded.json,
		"encounter_codec": encounter_codec,
		"floor_effect_state": player.floor_rule_effect_snapshot(),
		"room_state": room.duplicate(true),
		"scene_binding": binding,
		"publication_state": parts.publication.duplicate(true),
	}
	checkpoint["digest"] = canonical(checkpoint).sha256_text()
	var valid := validate(checkpoint, run, player.reward_effect_snapshot())
	if not valid.ok:
		return valid
	return {"ok": true, "code": &"OK", "context": {"checkpoint": checkpoint, "run": run, "reward": player.reward_effect_snapshot()}}


static func validate(checkpoint: Dictionary, run: Dictionary, reward: Dictionary) -> Dictionary:
	var version: Variant = checkpoint.get("schema_version")
	if not integral(version) or int(version) not in [1, 2] or not exact_fields(checkpoint, FIELDS if int(version) == 1 else V2_FIELDS):
		return failure(&"NATIVE_CHECKPOINT_INVALID", "fields")
	var native: Dictionary = {}
	if int(version) == 2:
		if not checkpoint.encounter_codec is String:
			return failure(&"NATIVE_CHECKPOINT_INVALID", "encounter_codec")
		if not checkpoint.encounter_codec.is_empty():
			var decoded_native := Replay.decode_replay_json(checkpoint.encounter_codec)
			if not decoded_native.ok:
				return failure(&"NATIVE_CHECKPOINT_INVALID", "encounter_codec")
			native = decoded_native.replay
	if not safe_run(run, not native.is_empty()) or checkpoint.run_id != run.get("run_id") or not integral(checkpoint.run_revision) or int(checkpoint.run_revision) != int(run.get("revision", -1)) or checkpoint.run_digest != canonical(run).sha256_text():
		return failure(&"NATIVE_CHECKPOINT_INVALID", "run")
	var unsigned := checkpoint.duplicate(true)
	unsigned.erase("digest")
	if checkpoint.digest != canonical(unsigned).sha256_text() or not checkpoint.launch_receipt is Dictionary or checkpoint.launch_receipt.get("run_id") != run.run_id or checkpoint.launch_receipt.get("projection_digest") != run.get("resources", {}).get("meta_run_projection", {}).get("projection_digest") or not checkpoint.room_state is Dictionary or (not inactive_room(checkpoint.room_state) if native.is_empty() else not live_room(checkpoint.room_state, native)) or not checkpoint.scene_binding is Dictionary or not valid_scene_binding(checkpoint.scene_binding) or not checkpoint.publication_state is Dictionary:
		return failure(&"NATIVE_CHECKPOINT_INVALID", "binding")
	if not scene_binding_matches_run(checkpoint.scene_binding, run, checkpoint.room_state):
		return failure(&"NATIVE_CHECKPOINT_INVALID", "scene_identity")
	var publication: Dictionary = checkpoint.publication_state
	if not exact_fields(publication, PUBLICATION_FIELDS):
		return failure(&"NATIVE_CHECKPOINT_INVALID", "publication")
	for field: String in ["route_ids", "floor_start_ids", "floor_completion_ids"]:
		if not publication[field] is Dictionary or publication[field].size() > 1024:
			return failure(&"NATIVE_CHECKPOINT_INVALID", "publication")
		for id: Variant in publication[field]:
			if not id is String or not id.begins_with(str(run.run_id) + ":") or publication[field][id] != true:
				return failure(&"NATIVE_CHECKPOINT_INVALID", "publication")
	for field: String in ["player_process_mode", "controller_process_mode"]:
		if not integral(publication[field]) or int(publication[field]) < 0 or int(publication[field]) > Node.PROCESS_MODE_DISABLED:
			return failure(&"NATIVE_CHECKPOINT_INVALID", "process_mode")
	if not integral(publication.floor_rule_frame_origin) or int(publication.floor_rule_frame_origin) < -1 or not publication.selection_safety is bool or not publication.dungeon_selection is bool or not checkpoint.player_codec is String:
		return failure(&"NATIVE_CHECKPOINT_INVALID", "publication")
	if not checkpoint.floor_effect_state is Dictionary or not exact_fields(checkpoint.floor_effect_state, ["schema_version", "modifiers"]) or checkpoint.floor_effect_state.schema_version != 1 or not checkpoint.floor_effect_state.modifiers is Dictionary:
		return failure(&"NATIVE_CHECKPOINT_INVALID", "floor_effects")
	var decoded := Replay.decode_replay_json(checkpoint.player_codec)
	if not decoded.ok:
		return failure(&"NATIVE_CHECKPOINT_INVALID", "codec")
	var replay: Dictionary = decoded.replay
	if not Replay.validate_full_player_snapshot(replay, replay.get("identity", {})).ok or replay.get("identity", {}).get("run_id") != run.run_id or not json_equal(replay.get("reward_effect_state"), reward):
		return failure(&"NATIVE_CHECKPOINT_INVALID", "replay")
	if not native.is_empty() and (int(run.phase) not in LIVE_PHASES or native.get("run_seed") != run.run_seed or not NativeDriver.validate_cold_snapshot(native, str(run.run_id), str(checkpoint.room_state.room_id), int(replay.frame))):
		return failure(&"NATIVE_CHECKPOINT_INVALID", "native_encounter")
	return {"ok": true, "code": &"OK", "context": {"replay": replay.duplicate(true), "native": native.duplicate(true)}}


static func valid_scene_binding(binding: Dictionary) -> bool:
	if binding.is_empty():
		return true
	if not exact_fields(binding, ["bound", "active", "binding"]) or binding.bound != true or binding.active != true or not binding.binding is Dictionary or not exact_fields(binding.binding, SCENE_BINDING_FIELDS):
		return false
	var details: Dictionary = binding.binding
	for field: String in ["node_id", "content_id", "room_type", "floor_id", "palette_id", "environment_rule_id"]:
		if not details[field] is String or details[field].is_empty():
			return false
	return integral(details.room_seed) and integral(details.binding_generation) and int(details.binding_generation) > 0 and details.reduced_motion is bool and details.hit_flash_enabled is bool


static func scene_binding_matches(binding: Dictionary, target: Dictionary) -> bool:
	if target.is_empty():
		return binding.is_empty()
	if binding.is_empty() or not valid_scene_binding(binding):
		return false
	var details: Dictionary = binding.binding
	var context: Dictionary = target.scene_context
	return details.node_id == target.node_id and details.content_id == target.template_id and details.room_type == target.room_type and details.floor_id == context.floor_id and details.palette_id == context.palette_id and details.environment_rule_id == context.environment_rule_id and int(details.room_seed) == int(context.room_seed)


static func scene_binding_matches_run(binding: Dictionary, run: Dictionary, room: Dictionary) -> bool:
	var plan: Dictionary = run.floor_plan
	if plan.current_node_id == plan.entry_node_id:
		return binding.is_empty() and room.room_definition.is_empty() and room.room_id.is_empty()
	if binding.is_empty() or not valid_scene_binding(binding) or not Scene.FLOOR_PRESENTATION.has(plan.floor_id):
		return false
	var details: Dictionary = binding.binding
	var floor: Dictionary = Scene.FLOOR_PRESENTATION[plan.floor_id]
	return details.node_id == plan.current_node_id and details.node_id == room.room_id and details.content_id == room.room_definition.get("template_id") and details.room_type == room.room_definition.get("room_type") and details.floor_id == plan.floor_id and details.palette_id == floor.palette_id and details.environment_rule_id == floor.environment_rule_id and int(details.room_seed) == Seed.derive_node_seed(int(run.run_seed), StringName(plan.floor_id), StringName(plan.current_node_id), &"room_scene")


static func equivalent_scene_binding(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty():
		return left.is_empty() and right.is_empty()
	var expected: Dictionary = left.duplicate(true)
	var actual: Dictionary = right.duplicate(true)
	expected.binding.erase("binding_generation")
	actual.binding.erase("binding_generation")
	return json_equal(expected, actual)


static func safe_run(run: Dictionary, live_encounter: bool = false) -> bool:
	if run.is_empty() or run.get("config", {}).get("milestone") not in ["LAUNCH", "EXPANSION"] or int(run.get("phase", -1)) not in SAFE_PHASES or not run.get("floor_plan") is Dictionary or run.floor_plan.is_empty():
		return false
	if int(run.phase) not in LIVE_PHASES:
		return true
	var plan: Dictionary = run.floor_plan
	if plan.get("current_node_id") == plan.get("entry_node_id"):
		return true
	for node: Dictionary in plan.get("nodes", []):
		if node.get("id") == plan.get("current_node_id"):
			return (int(run.phase) == Phase.Value.ROOM_ACTIVE and node.get("room_type") in ["event", "shop", "treasure", "rest"]) or live_encounter and node.get("room_type") in ["combat", "elite", "boss"]
	return false


static func inactive_room(room: Dictionary) -> bool:
	if not valid_room(room):
		return false
	var runner: Dictionary = room.runner
	return runner.active == false and runner.alive_count == 0 and runner.pending_spawn_count == 0


static func live_room(room: Dictionary, native: Dictionary) -> bool:
	if native.is_empty() or not valid_room(room) or not room.room_active or room.room_terminal or not room.failure.is_empty():
		return false
	var runner: Dictionary = room.runner
	return runner.active == true and runner.failure.is_empty() and runner.encounter_id == native.get("definition", {}).get("id") and runner.alive_count == native.get("actors", {}).size() and runner.pending_spawn_count == 0 and runner.wave_index == native.get("encounter", {}).get("wave_index")


static func valid_room(room: Dictionary) -> bool:
	if not exact_fields(room, ["configured", "room_active", "room_terminal", "room_id", "room_definition", "run_seed", "event_continuation", "failure", "runner"]) or room.configured != true or not room.room_active is bool or not room.room_terminal is bool or not room.room_id is String or not room.room_definition is Dictionary or not room.event_continuation is Dictionary or not room.failure is Dictionary or not integral(room.run_seed) or not room.runner is Dictionary:
		return false
	var runner: Dictionary = room.runner
	return exact_fields(runner, ["encounter_id", "wave_index", "alive_count", "pending_spawn_count", "active", "failure"]) and runner.active is bool and integral(runner.alive_count) and runner.alive_count >= 0 and runner.alive_count <= 8 and integral(runner.pending_spawn_count) and runner.pending_spawn_count >= 0 and runner.pending_spawn_count <= 8 and integral(runner.wave_index) and int(runner.wave_index) >= -1 and runner.encounter_id is String and runner.failure is Dictionary


static func canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, true)), "", true, true)


static func json_equal(left: Variant, right: Variant) -> bool:
	return canonical(left) == canonical(right)


static func exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func integral(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value))


static func failure(code: StringName, stage: String = "") -> Dictionary:
	return {"ok": false, "code": code, "context": {"stage": stage}}


static func _native_host(host: Node) -> bool:
	if not is_instance_valid(host):
		return false
	var script: Script = host.get_script()
	while script != null:
		if script.resource_path == "res://scripts/application/run_runtime_host.gd":
			return true
		script = script.get_base_script()
	return false
