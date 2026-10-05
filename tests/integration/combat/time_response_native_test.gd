extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const BossScene := preload("res://data/content_packs/base/assets/bosses/launch/boss_time_sovereign.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const RoomScene := preload("res://data/content_packs/base/assets/rooms/launch/room_boss_time_sovereign.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Catalog := preload("res://scripts/content/content_registry.gd")
const Snapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const PAIRS := [["stop", "rewind"], ["stop", "rift"], ["stop", "accelerate"], ["rewind", "rift"], ["rewind", "accelerate"], ["rift", "accelerate"]]
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var selected := OS.get_environment("PLANEWALKER_TIME_RESPONSE_CASE")
	if not selected.is_empty():
		await _native_response(selected)
		if selected == "accelerate":
			await _accelerate_expiry()
		suite.finish(get_tree())
		return
	for phase: int in [0, 1]:
		for pair: Array in PAIRS:
			await _pair(phase, pair)
	for ability: String in ["stop", "rewind", "accelerate", "rift"]:
		await _native_response(ability)
	await _accelerate_expiry()
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		await _normal_weapon(weapon)
	await _rewind_arrival("clear")
	await _rewind_arrival("wall")
	await _rewind_arrival("moving_player")
	suite.finish(get_tree())


func _fixture(pair: Array, phase: int = 0, weapon: String = "sword") -> Dictionary:
	var room := RoomScene.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var template := {}
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json")):
		if row.id == "room_boss_time_sovereign":
			template = row
	var actor := BossScene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.global_position = Vector2(320, 180)
	var parser := Definition.new()
	parser.configure(Content.boss("time_sovereign"))
	var configured: Dictionary = actor.configure_launch_definition(parser.runtime_projection(), {"run_id": "run-time-response", "hostile_source_id": "time-response-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42})
	var motion: Dictionary = actor.configure_launch_room_motion(room, template)
	suite.assert_true(configured.ok and motion.ok, "native Time Boss binds real room and canonical domain: " + str(configured.get("context", {})) + " " + str(motion))
	actor.health.defense = 0.0
	var player := PlayerScene.instantiate() as Node2D
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.get_node("RewindEchoRuntime").set_process(false)
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.get_node("RewindEchoRuntime").set_process(false)
	suite.assert_true(player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": pair, "difficulty": "normal", "seed": 42}) and player.configure_run(&"run-time-response"), "native Player binds actual paid time pair and weapon " + str(pair))
	player.global_position = Vector2(360, 180)
	player.time_manager.rewind_echo_enabled = true
	player.health.acquire_invulnerability_source(&"time-response-fixture")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	suite.assert_true(effects.configure("run-time-response") and effects.configure_native_payloads(root) and effects.configure_native_summon_room(room, template), "native Time response owns real effects and payloadroom")
	var registry := Registry.new()
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects) and player.configure_hostile_frame_participant(bridge), "paid Player and Boss share one rollback authority")
	var receipts: Array = []
	player.time_manager.native_ability_committed.connect(func(receipt: Dictionary): receipts.append(receipt.duplicate(true)))
	var f := {"player": player, "actor": actor, "room": room, "root": root, "effects": effects, "registry": registry, "bridge": bridge, "frame": 0, "receipts": receipts, "definition": parser.runtime_projection(), "template": template}
	if phase == 1:
		suite.assert_true(actor.get_node("WatchHurtbox").receive_hit(_hit(player, 101, 1000.0)) > 0.0, "actual accepted body damage enters phase2")
	await _frames(f, 60)
	player.global_position = Vector2(420, 180)
	return f


func _frames(f: Dictionary, through: int, intents: Dictionary = {}) -> bool:
	for frame: int in range(int(f.frame) + 1, through + 1):
		var accepted: bool = f.player.advance_action_frame(intents)
		suite.assert_true(accepted, "paid native Time response frame%d accepts" % frame)
		if not accepted:
			var checkpoint: Dictionary = f.actor.launch_transaction_snapshot()
			var position: Vector2 = f.actor.global_position
			var target: Vector2 = f.player.global_position
			var prepared: Dictionary = f.actor.prepare_launch_frame(frame, {"runtime_frame": frame, "source_position": {"x": position.x, "y": position.y}, "target_position": {"x": target.x, "y": target.y}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": f.bridge._player_target_id()})
			var effect: Dictionary = f.effects.prepare_effects([{"hostile_source_id": "time-response-owner", "batch": prepared.batch}], {"run_id": "run-time-response", "runtime_frame": frame, "actors": {"time-response-owner": f.actor}, "targets": {f.bridge._player_target_id(): f.player}, "threat_registry": f.registry}) if prepared.ok else {}
			print("TIME_RESPONSE_FRAME_DIAGNOSTIC ", frame, " actor=", prepared.get("context", {}), " effects=", effect.get("context", {}))
			if effect.get("ok", false):
				f.effects.rollback(effect.ticket)
			if prepared.ok:
				f.actor.rollback_launch_frame(prepared.ticket)
			f.actor.restore_launch_transaction_snapshot(checkpoint)
			return false
		f.frame = frame
	return true


func _cast(f: Dictionary, slot: int) -> bool:
	var before: float = f.player.time_manager.energy
	var count: int = f.receipts.size()
	var intents := {"time_slot_%d" % slot: {"edge": &"pressed"}}
	var accepted := await _frames(f, int(f.frame) + 1, intents)
	suite.assert_true(accepted and f.receipts.size() == count + 1 and f.player.time_manager.energy < before, "real time-slot input pays resources and delivers one authentic receipt")
	return accepted and f.receipts.size() == count + 1


func _wait_response(f: Dictionary, ability: String) -> bool:
	for _frame: int in range(600):
		var state: Dictionary = f.actor._launch_runtime.snapshot()
		if state.action.action_id == "traitor.counter_" + ability and state.action.phase == "WARNING":
			return true
		if not await _frames(f, int(f.frame) + 1):
			return false
	suite.assert_true(false, "authentic response must enter a full warning: " + ability)
	return false


func _pair(phase: int, pair: Array) -> void:
	var f := await _fixture(pair, phase)
	var paid := await _cast(f, 1)
	if paid:
		_assert_paid_benefit(f, str(pair[0]))
		await _frames(f, int(f.frame) + 16)
		suite.assert_true(await _cast(f, 2), "both slots in each real equipped pair pay and commit")
		_assert_paid_benefit(f, str(pair[1]))
	if paid and await _wait_response(f, str(pair[0])):
		var state: Dictionary = f.actor._launch_runtime.snapshot()
		suite.assert_equal(state.time_response.active.receipt.ability_id, pair[0], "all six paid pairs reach a native response in both phases")
		suite.assert_equal(state.time_response.cooldown_until_frame - state.time_response.active.start_frame, 900 if phase == 0 else 600, "native response uses exact phase sharedcooldown")
		if pair[0] == "stop":
			suite.assert_true(state.time_response.active.start_frame >= f.receipts[0].runtime_frame + 72, "native Stop retains full response delay")
		elif pair[0] == "rewind":
			suite.assert_equal(state.action.committed_target, f.receipts[0].endpoint, "native Rewind response freezes actual restored Player endpoint")
			var echo: Node = f.player.get_node("RewindEchoRuntime")
			suite.assert_true(echo.is_echo_active(), "authentic paid Rewind retains its actual committed echo")
			f.actor.global_position = Vector2(410, 180)
			echo._apply_pulse()
			suite.assert_true(f.actor._launch_runtime.snapshot().time_response.last_rewind.echo_claimed and f.actor._launch_runtime.is_exposed(), "actual echo crossing watch gives this real time pair a positive conversion")
		else:
			while f.actor._launch_runtime.snapshot().time_response.active.activation_frame < 0:
				if not await _frames(f, int(f.frame) + 1):
					break
			var activation: int = f.actor._launch_runtime.snapshot().time_response.active.activation_frame
			if activation >= 0:
				await _frames(f, activation + 30)
				suite.assert_true(f.actor._launch_runtime.snapshot().time_response.active.recovery_granted, "actual Rift response gives this real time pair a positive recovery conversion")
	await _dispose(f)


func _assert_paid_benefit(f: Dictionary, ability: String) -> void:
	match ability:
		"stop":
			suite.assert_true(f.player.time_manager.replay_snapshot().stop_active and f.actor._launch_runtime.is_exposed(), "paid Stop grants its original warning and positive exposure")
		"accelerate":
			suite.assert_true(f.player.is_time_accelerated(), "paid Accelerate keeps its actual Player speed benefit")
		"rift":
			suite.assert_true(f.player.world_payload_authority.replay_snapshot().descriptors.size() > 0, "paid Rift retains its actual complete world payload")
		"rewind":
			suite.assert_equal(f.receipts.back().endpoint, {"x": f.player.global_position.x, "y": f.player.global_position.y}, "paid Rewind restores actual Player endpoint before delivery")


func _native_response(ability: String) -> void:
	var f := await _fixture([ability, "rewind" if ability != "rewind" else "stop"])
	var forged := {"id": "invented", "run_id": "run-time-response", "ability_id": ability}
	var initial: Dictionary = f.actor.launch_runtime_snapshot()
	f.player.time_manager.native_ability_committed.emit(forged)
	suite.assert_equal(f.actor.launch_runtime_snapshot(), initial, "public signal emission cannot invent a paid response")
	var player_before: Dictionary = f.player.full_player_replay_snapshot()
	var effects_before: Dictionary = f.effects.snapshot()
	f.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	var next: int = f.frame + 1
	suite.assert_true(not f.player.advance_action_frame({"time_slot_1": {"edge": &"pressed"}}), "late World refusal rejects paid native " + ability)
	suite.assert_equal(f.actor.launch_runtime_snapshot(), initial, "late refusal restores Boss response watermark and queue")
	suite.assert_equal(f.player.full_player_replay_snapshot(), player_before, "late refusal restores complete paid Player state")
	suite.assert_equal(f.effects.snapshot(), effects_before, "late refusal restores source-owned native work")
	f.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	f.receipts.clear()
	if not await _cast(f, 1):
		await _dispose(f)
		return
	suite.assert_equal(f.frame, next, "same paid transaction retries at identical frame")
	var accepted: Dictionary = f.actor.launch_runtime_snapshot()
	f.player.time_manager.native_ability_committed.emit(f.receipts[0])
	suite.assert_equal(f.actor.launch_runtime_snapshot(), accepted, "copied genuine receipt cannot be replayed outside producer delivery")
	if not await _wait_response(f, ability):
		await _dispose(f)
		return
	await _capture(f, ability + "-warning")
	await _cold(f, ability + "-warning")
	if ability == "stop":
		var watch: Area2D = f.actor.get_node("WatchHurtbox")
		watch.receive_hit(_hit(f.player, 201, 20.0))
		var hit := _hit(f.player, 202, 20.0)
		suite.assert_true(watch.receive_hit(hit) > 0.0, "actual Stop watch loses enough accepted HP")
		suite.assert_equal(watch.receive_hit(hit), 0.0, "duplicate physical watch hit is spent once")
		suite.assert_true(f.actor._launch_runtime.snapshot().time_response.active.cancelled and f.actor._launch_runtime.is_exposed(), "actual watch cancels Stop and grants positive punishment")
		await _cold(f, "stop-cancelled")
	else:
		var start: int = f.actor._launch_runtime.snapshot().action.commit_frame
		while f.actor._launch_runtime.snapshot().time_response.active.activation_frame < 0 and f.frame < start + 300:
			if not await _frames(f, int(f.frame) + 1):
				break
		suite.assert_true(f.actor._launch_runtime.snapshot().time_response.active.activation_frame >= start + 45, "native response retains full45framewarning")
		await _capture(f, ability + "-active")
		await _cold(f, ability + "-active")
		if ability == "accelerate":
			var watch: Area2D = f.actor.get_node("WatchHurtbox")
			for token: int in range(301, 307):
				suite.assert_true(watch.receive_hit(_hit(f.player, token, 1.0)) > 0.0, "six distinct accelerated actual body identities settle")
			suite.assert_true(f.actor._launch_runtime.snapshot().time_response.active.shattered, "actual accelerated hits shatter the finite slowfield")
			var shatter_actor: Dictionary = f.actor.launch_runtime_snapshot()
			var shatter_effects: Dictionary = f.effects.snapshot()
			var shatter_player: Dictionary = f.player.full_player_replay_snapshot()
			f.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
			suite.assert_true(not f.player.advance_action_frame(), "late World refusal rolls back native field retirement")
			suite.assert_equal(f.actor.launch_runtime_snapshot(), shatter_actor, "rejected field retirement preserves accepted watch conversion")
			suite.assert_equal(f.effects.snapshot(), shatter_effects, "rejected field retirement restores complete slowfield and modifiers")
			suite.assert_equal(f.player.full_player_replay_snapshot(), shatter_player, "rejected field retirement preserves exact paid Player")
			f.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
			await _frames(f, int(f.frame) + 1)
			suite.assert_true(f.effects.semantic_snapshot().zones.filter(func(row: Dictionary): return row.action_id == "traitor.counter_accelerate").is_empty(), "shattered field retires native zone and modifiers on acceptedframe")
			await _cold(f, "accelerate-shattered")
		elif ability == "rift":
			var activation: int = f.actor._launch_runtime.snapshot().time_response.active.activation_frame
			await _frames(f, activation + 30)
			suite.assert_equal(f.actor._launch_runtime.snapshot().mechanism_state.delay_remaining_frames, 45, "actual delayed Rift pulse grants45extra recovery")
			suite.assert_true(f.player.world_payload_authority.replay_snapshot().descriptors.size() > 0, "response pulse preserves full paid Player Rift")
		elif ability == "rewind":
			var echo: Node = f.player.get_node("RewindEchoRuntime")
			f.actor.global_position = Vector2(410, 180)
			echo._apply_pulse()
			suite.assert_true(f.actor._launch_runtime.snapshot().time_response.last_rewind.echo_claimed and f.actor._launch_runtime.is_exposed(), "actual committed echo grants30framewatchwindow")
			await _cold(f, "rewind-echo")
	await _dispose(f)


func _accelerate_expiry() -> void:
	var f := await _fixture(["accelerate", "stop"])
	if not await _cast(f, 1) or not await _wait_response(f, "accelerate"):
		await _dispose(f)
		return
	while f.actor._launch_runtime.snapshot().time_response.active.activation_frame < 0:
		if not await _frames(f, int(f.frame) + 1):
			await _dispose(f)
			return
	var zones: Array = f.effects.semantic_snapshot().zones.filter(func(row: Dictionary): return row.action_id == "traitor.counter_accelerate")
	suite.assert_equal(zones.size(), 1, "actual paid Accelerate creates one bounded native slowfield")
	if zones.size() != 1:
		await _dispose(f)
		return
	var zone: Dictionary = zones[0]
	f.player.global_position = Vector2(float(zone.geometry.origin.x), float(zone.geometry.origin.y))
	await _frames(f, int(f.frame) + 1)
	suite.assert_close(f.player._floor_rule_movement_multiplier(), 0.7, "actual counterfield applies its authored Player slowdown")
	f.player.global_position = Vector2(500, 260)
	await _frames(f, int(f.frame) + 1)
	suite.assert_close(f.player._floor_rule_movement_multiplier(), 1.0, "leaving the counterfield restores paid Accelerate's positive outside benefit")
	f.player.global_position = Vector2(float(zone.geometry.origin.x), float(zone.geometry.origin.y))
	await _frames(f, int(zone.expires_frame))
	suite.assert_true(f.effects.semantic_snapshot().zones.any(func(row: Dictionary): return row.id == zone.id), "native counterfield stays live on its last120thframe")
	await _cold(f, "accelerate-last-live")
	await _frames(f, int(zone.expires_frame) + 1)
	suite.assert_true(not f.effects.semantic_snapshot().zones.any(func(row: Dictionary): return row.id == zone.id), "native counterfield retires exactly after120frames")
	suite.assert_close(f.player._floor_rule_movement_multiplier(), 1.0, "expired counterfield removes its actual Player modifier")
	await _cold(f, "accelerate-expired")
	await _dispose(f)


func _normal_weapon(weapon: String) -> void:
	var f := await _fixture(["accelerate", "stop"], 0, weapon)
	if not await _cast(f, 1) or not await _wait_response(f, "accelerate"):
		await _dispose(f)
		return
	f.actor._launch_runtime.add_control_source("native-weapon-watch-isolation", "rift", 180, 0.7)
	f.player.global_position = f.actor.global_position - Vector2(42, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp: float = f.actor.health.current_hp
	await _frames(f, int(f.frame) + 1, {"aim": Vector2.RIGHT})
	suite.assert_true(f.player.try_action(&"weapon_primary"), "normal " + weapon + " input targets real native watch")
	if weapon == "sword":
		f.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
	for offset: int in range(90):
		if offset == 40 and weapon != "sword":
			f.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
		await _frames(f, int(f.frame) + 1, {"aim": Vector2.RIGHT})
		await get_tree().physics_frame
	suite.assert_true(f.actor.health.current_hp < hp and f.actor._launch_runtime.snapshot().mechanism_state.damage_claims.size() > 0, "normal " + weapon + " producer physically damages one accepted watch body")
	f.player.cancel_transient_actions()
	await _dispose(f)


func _rewind_arrival(kind: String) -> void:
	var f := await _fixture(["rewind", "stop"])
	if not await _cast(f, 1) or not await _wait_response(f, "rewind"):
		await _dispose(f)
		return
	var action: Dictionary = f.actor._launch_runtime.snapshot().action
	var destination := Vector2(float(action.committed_geometry[0].origin.x), float(action.committed_geometry[0].origin.y))
	var endpoint: Dictionary = f.receipts[0].endpoint
	suite.assert_equal(destination, Vector2(float(endpoint.x), float(endpoint.y)) - Vector2(48, 0), "Rewind arrival locks actual Player facing independently of Boss approach")
	var blocker := StaticBody2D.new()
	blocker.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(32, 80)
	shape.shape = rectangle
	blocker.add_child(shape)
	add_child(blocker)
	blocker.global_position = destination if kind == "wall" else Vector2(900, 500)
	if kind == "moving_player":
		f.player.global_position = destination
	else:
		f.player.global_position = Vector2(480, 240)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var before: Vector2
	while f.actor._launch_runtime.snapshot().time_response.active.activation_frame < 0:
		before = f.actor.global_position
		if not await _frames(f, int(f.frame) + 1):
			break
	suite.assert_equal(f.actor.global_position, destination if kind == "clear" else before, "native rewind arrival obeys actual obstacle and movingPlayer separation: " + kind)
	blocker.queue_free()
	await _dispose(f)


func _cold(f: Dictionary, label: String) -> void:
	var aggregate := {"actor": f.actor.native_cold_snapshot(func(_source: Node): return {}), "effects": f.effects.snapshot(), "registry": f.registry.snapshot()}
	var encoded := Replay.encode_replay_json(aggregate)
	var catalog := Catalog.new()
	catalog.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var directory := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("native-time-response")
	if OS.get_environment("PLANEWALKER_TEST_DATA_DIR").is_empty():
		directory = ProjectSettings.globalize_path("res://build/test-data/native-time-response")
	var save := Save.new()
	save.configure(directory, "native-time-response", Snapshot.snapshot(catalog))
	suite.assert_true(encoded.ok and save.save_profile("time", label, {"codec": encoded.json}).ok, "physical SaveService writes active response " + label)
	var fresh := Save.new()
	fresh.configure(directory, "native-time-response", Snapshot.snapshot(catalog))
	var recovered: Variant = fresh.inspect_profile("time", label)
	suite.assert_true(recovered.ok, "fresh SaveService physically reads response " + label)
	if not recovered.ok:
		return
	var decoded: Dictionary = Replay.decode_replay_json(recovered.payload.payload.codec).replay
	suite.assert_equal(decoded, aggregate, "physical typed codec preserves new integer fields exactly")
	var world := SubViewport.new()
	world.world_2d = World2D.new()
	add_child(world)
	var room := RoomScene.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(room)
	var actor := BossScene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(actor)
	actor.configure_launch_definition(f.definition, decoded.actor.identity)
	actor.global_position = Vector2(float(decoded.actor.actor.position.x), float(decoded.actor.actor.position.y))
	suite.assert_true(actor.configure_launch_room_motion(room, f.template).ok, "fresh native response binds same authoritative room")
	suite.assert_true(actor.restore_native_cold_snapshot(decoded.actor, func(_binding: Dictionary): return null), "fresh native Actor reconstructs paid ledger and positive responsewindow")
	suite.assert_true(actor.native_cold_snapshot(func(_source: Node): return {}) == decoded.actor, "fresh native response preserves complete cold projection")
	var context := {"runtime_frame": int(f.frame) + 1, "source_position": {"x": actor.global_position.x, "y": actor.global_position.y}, "target_position": {"x": f.player.global_position.x, "y": f.player.global_position.y}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": f.bridge._player_target_id()}
	var first: Dictionary = actor.prepare_launch_frame(int(f.frame) + 1, context)
	var second: Dictionary = f.actor.prepare_launch_frame(int(f.frame) + 1, context)
	suite.assert_true(first.ok and second.ok and first.batch == second.batch and first.ticket.after.runtime == second.ticket.after.runtime, "fresh native paid response has identical nextframefacts")
	if first.ok:
		actor.rollback_launch_frame(first.ticket)
	if second.ok:
		f.actor.rollback_launch_frame(second.ticket)
	world.queue_free()
	await get_tree().process_frame


func _hit(player: Node2D, token: int, amount: float) -> RefCounted:
	return Damage.from_plan({"run_id": "run-time-response", "target_id": "pending_target", "hostile_source_id": "player:time-response-probe", "attack_generation": token, "hit_index": 0, "action_token": token, "amount": amount, "damage_type": Damage.DamageType.PHYSICAL, "source": player, "attacker": player, "can_crit": false, "tags": []})


func _capture(f: Dictionary, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	f.actor.project_runtime_snapshot(f.actor.launch_runtime_snapshot())
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(2560, 1080)]:
		get_window().size = resolution
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		var holder := f.actor.get_node("LaunchTelegraphs") as Node2D
		suite.assert_equal(holder.get_child_count(), f.actor._launch_runtime.snapshot().action.committed_geometry.size(), "native Time response renders every committed primitive " + label)
		var cues: Array[Node2D] = [holder]
		for node: Node2D in f.effects.native_semantic_nodes():
			if node.get("_record").get("action_id", "") == "traitor.counter_accelerate":
				cues.append(node)
		for node: Node2D in cues:
			node.hide()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var hidden := get_viewport().get_texture().get_image()
		for node: Node2D in cues:
			node.show()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		pixels = get_viewport().get_texture().get_image()
		var cue_pixels := 0
		for y: int in range(80, 280):
			for x: int in range(160, 520):
				var sample := Vector2i(Vector2(x, y) * Vector2(pixels.get_size()) / Vector2(640, 360))
				if pixels.get_pixelv(sample).to_rgba32() != hidden.get_pixelv(sample).to_rgba32():
					cue_pixels += 1
		suite.assert_true(cue_pixels >= 16, "native Time warning or active field changes actual raster at every resolution " + label)
		var colors := {}
		for y: int in range(150, 210):
			for x: int in range(280, 420):
				colors[pixels.get_pixelv(Vector2i(Vector2(x, y) * Vector2(pixels.get_size()) / Vector2(640, 360))).to_rgba32()] = true
		suite.assert_true(colors.size() >= 8, "actual native Time response renders nonblank raster " + label)
		var output := "res://build/visual-evidence/native-time-response/%s-%dx%d.png" % [label, resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
		suite.assert_equal(pixels.save_png(output), OK, "actual Time response screenshot retains")


func _dispose(f: Dictionary) -> void:
	f.player.cancel_transient_actions()
	suite.assert_true(f.effects.dispose_native_effects(), "native Time response disposes all source-owned effects")
	for key: String in ["actor", "room", "player", "root"]:
		f[key].queue_free()
	await get_tree().process_frame
