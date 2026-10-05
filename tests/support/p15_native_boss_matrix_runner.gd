extends RefCounted

const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Catalog := preload("res://scripts/modes/boss_rush_catalog.gd")
const Builder := preload("res://scripts/modes/native_boss_arena_builder.gd")
const World := preload("res://scripts/replay/player_replay_world.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Save := preload("res://scripts/save/save_service.gd")
const CHARACTERS := ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]
const WEAPONS := ["sword", "bow", "gun", "staff", "gauntlets"]
const TIME_PAIRS := [["stop", "rewind"], ["stop", "rift"], ["stop", "accelerate"], ["rewind", "rift"], ["rewind", "accelerate"], ["rift", "accelerate"]]
const CASE_COUNT := 750
const MAX_CASE_FRAMES := 16000
const SURVIVAL_SOURCE := &"p15_matrix_survival_fixture"

var _host: Node
var _suite: RefCounted
var _registry: RefCounted
var _catalog: RefCounted
var _binding: Dictionary


func run(host: Node, suite: RefCounted) -> Dictionary:
	_host = host
	_suite = suite
	_registry = Registry.new()
	var loaded: RefCounted = _registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	_suite.assert_true(not loaded.has_blocking_errors(), "750 matrix loads the actual authoritative Launch Base Pack")
	_catalog = Catalog.new()
	_suite.assert_true(_catalog.configure(_registry), "750 matrix resolves all five actual native Boss definitions and rooms")
	if loaded.has_blocking_errors() or _catalog.stage(0).is_empty():
		return {}
	_binding = Content.snapshot(_registry)
	var start := int(OS.get_environment("PLANEWALKER_MATRIX_START"))
	var count := int(OS.get_environment("PLANEWALKER_MATRIX_COUNT")) if not OS.get_environment("PLANEWALKER_MATRIX_COUNT").is_empty() else 1
	_suite.assert_true(start >= 0 and count > 0 and start + count <= CASE_COUNT, "native matrix range is bounded by750 canonical cases")
	if start < 0 or count < 1 or start + count > CASE_COUNT:
		return {}
	var old_ticks := Engine.physics_ticks_per_second
	var old_fps := Engine.max_fps
	var old_scale := Engine.time_scale
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	var clock := {"physics_ticks_per_second": Engine.physics_ticks_per_second, "time_scale": Engine.time_scale}
	var rows: Array[Dictionary] = []
	for index: int in range(start, start + count):
		_suite.assert_true(Engine.physics_ticks_per_second == 60 and Engine.time_scale == 1.0, "every native case retains the production60Hz physical clock")
		var row := await _run_case(_identity(index))
		rows.append(row)
		_suite.assert_true(row.failures.is_empty(), "native matrix " + str(row.identity) + ": " + str(row.failures))
		print("P15_NATIVE_CASE ", index + 1, "/750 ", row.identity.key, " frames=", row.frames, " hp=", row.final_hp, " failures=", row.failures.size())
		if not row.failures.is_empty():
			break
	Engine.physics_ticks_per_second = old_ticks
	Engine.max_fps = old_fps
	Engine.time_scale = old_scale
	var report := {"schema_version": 3, "report_kind": "actual_native_boss_loadout_matrix", "synthetic": false, "human_playtests": 0, "unassisted_victory": false, "survival_fixture": str(SURVIVAL_SOURCE), "difficulty": "normal", "clock": clock, "content_snapshot": _binding, "expected_production_case_count": CASE_COUNT, "production_case_count": rows.size(), "range_start": start, "requested_case_count": count, "complete": start == 0 and rows.size() == CASE_COUNT and rows.all(func(row: Dictionary): return row.failures.is_empty()), "cases": rows}
	var output := OS.get_environment("PLANEWALKER_MATRIX_OUTPUT")
	if output.is_empty():
		output = "res://build/p15-native-boss-matrix.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	_suite.assert_true(file != null, "native matrix retains its actual versioned JSON report")
	if file != null:
		file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	_suite.assert_equal(rows.size(), count, "native matrix executes every requested actual case without substituting fixtures")
	return report


static func _identity(index: int) -> Dictionary:
	var boss_index := index % 5
	var pair_index := (index / 5) % 6
	var weapon_index := (index / 30) % 5
	var character_index := index / 150
	var key := "%s|%s|%s+%s|%s" % [CHARACTERS[character_index], WEAPONS[weapon_index], TIME_PAIRS[pair_index][0], TIME_PAIRS[pair_index][1], Catalog.BOSSES[boss_index]]
	return {"index": index, "key": key, "character_id": CHARACTERS[character_index], "weapon_id": WEAPONS[weapon_index], "time_abilities": TIME_PAIRS[pair_index].duplicate(), "boss_id": Catalog.BOSSES[boss_index], "boss_index": boss_index, "seed": 20261005 + index}


func _spawn(identity: Dictionary) -> Dictionary:
	var viewport := World.new()
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	_host.add_child(viewport)
	var stage := Node2D.new()
	stage.process_mode = Node.PROCESS_MODE_ALWAYS
	viewport.add_child(stage)
	var request := {"character_id": identity.character_id, "weapon_id": identity.weapon_id, "time_abilities": identity.time_abilities.duplicate(), "seed": identity.seed, "accessibility_assists": {"damage_received_multiplier": 1.0, "enemy_telegraph_scale": 1.0}}
	var built := Builder.build(stage, _registry, _catalog.stage(int(identity.boss_index)), request, "p15-native-matrix-%d" % identity.index, "matrix", "p15-native-matrix")
	built["viewport"] = viewport
	built["stage"] = stage
	if not built.ok:
		return built
	built.player.set_physics_process(false)
	built.boss.set_physics_process(false)
	built.player.get_node("TimeManager").set_process(false)
	built.player.get_node("RewindRecorder").set_process(false)
	built.player.health.acquire_invulnerability_source(SURVIVAL_SOURCE)
	built.player.global_position = built.boss.global_position + Vector2(42.0, 0.0)
	return built


func _run_case(identity: Dictionary) -> Dictionary:
	var row := {"identity": identity.duplicate(true), "frames": 0, "final_hp": -1.0, "failures": [], "damage_trace": [], "physical_contacts": [], "weapon_actions": [], "boss_actions": {}, "phase_damage": {}, "time_casts": [], "positive_time": [], "death_receipts": [], "checkpoint_digest": ""}
	var world := _spawn(identity)
	if not world.ok:
		row.failures.append("actual native construction: " + str(world))
		await _dispose(world)
		return row
	var player: Node2D = world.player
	var boss: Node2D = world.boss
	row["_observed_hp"] = float(boss.health.current_hp)
	row["_published_losses"] = []
	boss.health.damaged.connect(func(_amount: float, hp: float):
		row._published_losses.append(maxf(0.0, float(row._observed_hp) - hp))
		row._observed_hp = hp
	)
	boss.health.healed.connect(func(_amount: float, hp: float): row._observed_hp = hp)
	player.get_node("SwordWeapon/Hitbox").area_entered.connect(func(area: Area2D):
		if row.physical_contacts.size() < 8:
			var hitbox: Node = player.get_node("SwordWeapon/Hitbox")
			var info: RefCounted = hitbox.get("_active_damage_info")
			row.physical_contacts.append({"area": str(boss.get_path_to(area)) if boss.is_ancestor_of(area) else str(area.name), "frame": int(player.priority_arbitration_snapshot().frame), "active": hitbox.is_active(), "info": {"run_id": str(info.run_id), "target_id": str(info.target_id), "attacker_is_player": info.attacker == player, "native_authentication": boss._authenticates_native_body_damage(info)} if info != null else {}})
	)
	world.viewport.event_bus().hit_confirmed.connect(func(info: RefCounted, target: Node, amount: float):
		if target != boss or info.attacker != player or amount <= 0.0:
			return
		var phase := str(row.get("observed_phase", 0))
		var observation: Dictionary = boss.health.published_damage_observation_context(info)
		var published_loss := float(row._published_losses.pop_front()) if not row._published_losses.is_empty() else 0.0
		var loss := float(observation.hp_before) - float(observation.hp_after) if observation.has("hp_before") and observation.has("hp_after") else published_loss
		row.phase_damage[phase] = float(row.phase_damage.get(phase, 0.0)) + loss
		row.damage_trace.append({"run_id": str(player.current_run_id()), "target_id": str(boss.hostile_source_id), "raw_run_id": str(info.run_id), "raw_target_id": str(info.target_id), "native_authenticated": player.authenticates_native_damage_run(info, boss, player.current_run_id()), "frame": int(player.priority_arbitration_snapshot().frame), "phase_index": int(phase), "amount": amount, "actual_loss": loss, "source_id": str(info.hostile_source_id), "attack_generation": int(info.attack_generation), "damage_type": int(info.damage_type), "hit_index": int(info.hit_index), "tags": info.tags.duplicate(), "accelerated": player.is_time_accelerated()})
		if player.is_time_accelerated() and not row.positive_time.has("accelerated_physical_hit"):
			row.positive_time.append("accelerated_physical_hit")
	)
	player.weapon_action_coordinator.weapon_action_committed.connect(func(weapon: StringName, action: StringName, _token: int, _context: Dictionary):
		if str(weapon) == identity.weapon_id:
			row.weapon_actions.append(str(action))
	)
	player.get_node("TimeManager").native_ability_committed.connect(func(receipt: Dictionary):
		row.time_casts.append(receipt.duplicate(true))
		row["time_effect_receipts"] = row.get("time_effect_receipts", [])
		row.time_effect_receipts.append({"ability_id": receipt.ability_id, "frame": int(player.priority_arbitration_snapshot().frame), "accelerated": player.is_time_accelerated(), "remaining": float(player.time_manager.replay_snapshot().get("accelerate_remaining", 0.0))})
	)
	boss.hostile_final_death.connect(func(source: StringName, receipt: String): row.death_receipts.append({"source_id": str(source), "receipt": receipt}))
	await _host.get_tree().physics_frame
	await _host.get_tree().physics_frame
	var cast_index := 0
	var press_frame := -1
	var released := true
	var release_frames := 1
	var last_hit_frame := 0
	var damage_count := 0
	for frame: int in range(1, MAX_CASE_FRAMES + 1):
		if not is_instance_valid(boss) or boss.health.dead:
			break
		var state: Dictionary = boss.launch_runtime_snapshot().runtime
		if player.is_time_accelerated() and frame % 30 == 0:
			row["acceleration_window"] = row.get("acceleration_window", [])
			if row.acceleration_window.size() < 12:
				row.acceleration_window.append({"frame": frame, "player_state": player.action_state.current_state, "weapon_phase": str(player.weapon_action_coordinator.phase_name()), "remaining": float(player.time_manager.replay_snapshot().get("accelerate_remaining", 0.0)), "distance": player.global_position.distance_to(boss.global_position)})
		row.observed_phase = int(state.mechanism_state.phase_index)
		if not str(state.action.action_id).is_empty():
			row.boss_actions[state.action.action_id] = int(row.boss_actions.get(state.action.action_id, 0)) + 1
		if not state.mechanism_state.stop_claims.is_empty() and not row.positive_time.has("boss_stop_conversion"):
			row.positive_time.append("boss_stop_conversion")
		if boss.is_time_rifted() and not row.positive_time.has("boss_rift_slow"):
			row.positive_time.append("boss_rift_slow")
		var direction := player.global_position.direction_to(boss.global_position)
		var distance := player.global_position.distance_to(boss.global_position)
		var movement := direction if distance > 44.0 else -direction if distance < 34.0 else Vector2.ZERO
		if cast_index < 2 and frame >= 4 + cast_index * 90 and player.action_state.current_state == 0 and player.weapon_action_coordinator.phase_name() == &"READY":
			var ability: String = identity.time_abilities[cast_index]
			if ability == "rewind":
				player.rewind_recorder._record_snapshot()
			if not player.try_action(StringName("time_" + ability)):
				row.failures.append("authentic equipped time ability refused: " + ability)
				break
			cast_index += 1
		elif player.weapon_action_coordinator.phase_name() == &"READY" and player.action_state.current_state == 0:
			if player.try_action(&"weapon_primary"):
				press_frame = frame
				released = false
				release_frames = 40 if identity.weapon_id in ["sword", "bow", "gun"] else 1
				if identity.weapon_id == "sword" and player.is_time_accelerated():
					release_frames = 1
				if identity.weapon_id == "staff" and float(player.weapon_action_coordinator.get("_runtime").snapshot().mana) >= 20.0:
					release_frames = 45
		if not released and frame - press_frame >= release_frames:
			player.call("_submit_weapon_intent", &"weapon_primary", &"released")
			released = true
		if not player.advance_action_frame({"aim": direction, "movement": movement}):
			row.failures.append("actual Player/hostile fixed frame refused at%d" % frame)
			if world.bridge.has_method("frame_rejection_snapshot"):
				row["original_frame_rejection"] = world.bridge.frame_rejection_snapshot()
			row["refused_frame_state"] = {"boss": boss.launch_runtime_snapshot().runtime, "player_frame": int(player.priority_arbitration_snapshot().frame), "player_weapon": player.weapon_action_coordinator.snapshot(), "work": world.effects.work_snapshot(), "threats": world.bridge.get("_registry").snapshot()}
			row["refused_frame_diagnostic"] = preload("res://tests/support/native_frame_failure_probe.gd").inspect(player, {str(boss.hostile_source_id): boss}, world.effects, world.bridge.get("_registry"))
			break
		row.frames = frame
		await _host.get_tree().physics_frame
		if frame % 250 == 0:
			print("P15_NATIVE_PROGRESS ", identity.index + 1, "/750 ", identity.key, " frame=", frame, " hp=", boss.health.current_hp, " physical_hits=", row.damage_trace.size())
		if row.damage_trace.size() > damage_count:
			damage_count = row.damage_trace.size()
			last_hit_frame = frame
		if row.checkpoint_digest.is_empty() and not row.damage_trace.is_empty() and not boss.health.dead:
			var checkpoint := await _checkpoint(world, identity, {"aim": direction, "movement": movement})
			if not checkpoint.ok:
				row.failures.append("physical mid-action native checkpoint: " + str(checkpoint))
				break
			row.checkpoint_digest = checkpoint.digest
		if frame - last_hit_frame > 1600:
			row.failures.append("production weapon made no Boss body progress for1600 accepted frames")
			row["final_geometry"] = {"player": str(player.global_position), "boss": str(boss.global_position), "watch": boss.native_watch_snapshot() if identity.boss_id == "time_sovereign" else {}}
			break
	if is_instance_valid(boss):
		row.final_hp = float(boss.health.current_hp)
		var terminal: Dictionary = boss.launch_runtime_snapshot().runtime
		if not terminal.terminal or not boss.health.dead:
			row.failures.append("normal production weapon did not reach authenticated terminal death")
		for phase_index: int in range(_catalog.stage(int(identity.boss_index)).runtime_definition.phases.size()):
			if float(row.phase_damage.get(str(phase_index), 0.0)) <= 0.0:
				row.failures.append("no actual weapon damage in authored HP phase%d" % phase_index)
		if row.time_casts.size() != 2:
			row.failures.append("both equipped actual TimeManager receipts were not committed")
		if row.positive_time.is_empty():
			row.failures.append("no positive actual time interaction")
		var source := str(boss.hostile_source_id)
		var expected := "hostile_defeat:%s" % (str(player.current_run_id()) + "|" + source).sha256_text().substr(0, 40)
		if row.death_receipts != [{"source_id": source, "receipt": expected}]:
			row.failures.append("final physical weapon death did not publish exactly one canonical receipt")
		if terminal.terminal:
			if not player.advance_action_frame():
				row.failures.append("terminal native cleanup frame refused")
			await _host.get_tree().physics_frame
			if not world.effects.work_snapshot().records.is_empty() or not world.effects.native_summon_actors().is_empty() or not world.bridge.get("_registry").snapshot().is_empty():
				row.failures.append("native terminal death retained owned pending work, bodies or threats")
				row["terminal_retained"] = {"work": world.effects.work_snapshot(), "children": world.effects.native_summon_actors().keys(), "threats": world.bridge.get("_registry").snapshot()}
			if not terminal.control.sources.is_empty() or not terminal.conversion.claims.is_empty() or not terminal.conversion.weapon_sources.is_empty():
				row.failures.append("native terminal death retained controls or positive conversion claims")
			for construct: Node in _constructs(boss):
				if construct is CollisionObject2D and int(construct.collision_layer) != 0:
					row.failures.append("terminal construct retains live collision: " + str(construct.name))
	row.frames = int(player.priority_arbitration_snapshot().frame)
	row.erase("observed_phase")
	row.erase("_observed_hp")
	row.erase("_published_losses")
	await _dispose(world)
	return row


func _cold(world: Dictionary) -> Dictionary:
	var bind := func(node: Node) -> Dictionary:
		if node == world.player:
			return {"kind": "player", "run_id": str(world.player.current_run_id())}
		if world.player.is_ancestor_of(node):
			var path := str(world.player.get_path_to(node))
			if not path.contains("@") and not path.contains(".."):
				return {"kind": "player_path", "run_id": str(world.player.current_run_id()), "path": path}
		return {}
	var children := {}
	for source: String in world.effects.native_summon_actors():
		children[source] = world.effects.native_summon_actors()[source].native_cold_snapshot(bind)
	return {"player": world.player.full_player_replay_snapshot(), "actor": world.boss.native_cold_snapshot(bind), "children": children, "effects": world.effects.launch_transaction_snapshot(), "threats": world.bridge.get("_registry").snapshot()}


func _checkpoint(world: Dictionary, identity: Dictionary, next_intents: Dictionary) -> Dictionary:
	var state := _cold(world)
	var encoded := Replay.encode_replay_json(state)
	if not encoded.ok or state.actor.is_empty():
		return {"ok": false, "reason": "typed_native_capture", "codec_ok": encoded.ok, "actor_empty": state.actor.is_empty()}
	var directory := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("p15-native-matrix")
	if directory.is_relative_path():
		directory = "user://p15-native-matrix"
	var slot := "matrix_%d" % identity.index
	var storage := Save.new()
	var configured = storage.configure(directory, "test-p15-native-matrix", _binding)
	if not configured.ok or not storage.save_profile(slot, "base", {"codec": encoded.json}).ok:
		return {"ok": false, "reason": "physical_save"}
	var fresh := Save.new()
	fresh.configure(directory, "test-p15-native-matrix", _binding)
	var recovered = fresh.inspect_profile(slot, "base")
	var decoded := Replay.decode_replay_json(recovered.payload.payload.codec) if recovered.ok else {"ok": false}
	if not decoded.ok or decoded.replay != state:
		return {"ok": false, "reason": "physical_decode"}
	var twin := _spawn(identity)
	if not twin.ok:
		await _dispose(twin)
		return {"ok": false, "reason": "fresh_native_construction"}
	twin.player.configure_hostile_frame_participant(null)
	var resolve := func(binding: Dictionary) -> Node:
		if binding == {"kind": "player", "run_id": str(twin.player.current_run_id())}:
			return twin.player
		if binding.get("kind") == "player_path" and binding.get("run_id") == str(twin.player.current_run_id()) and binding.size() == 3 and binding.get("path") is String and not binding.path.is_empty() and not binding.path.begins_with("/") and not binding.path.contains("..") and not binding.path.contains("@"):
			return twin.player.get_node_or_null(binding.path)
		return null
	var steps := {}
	steps.actor = twin.boss.restore_native_cold_snapshot(state.actor, resolve)
	steps.player = twin.player.restore_full_player_replay_snapshot(state.player)
	var restored: bool = steps.player and steps.actor
	var actors := {str(twin.boss.hostile_source_id): twin.boss}
	restored = restored and twin.effects.bind_native_targets(actors, {"player:1": twin.player}) and twin.effects.restore_native_summon_snapshot(state.effects.summons)
	if restored:
		for source: String in state.children:
			restored = twin.effects.native_summon_actors()[source].restore_native_cold_snapshot(state.children[source], resolve) and restored
		restored = twin.effects.restore_launch_transaction_snapshot(state.effects) and twin.bridge.configure(twin.player, twin.bridge.get("_registry"), actors.values(), twin.effects) and twin.bridge.call("_restore_registry", state.threats) and twin.player.configure_hostile_frame_participant(twin.bridge) and restored
	if not restored or _cold(twin) != state:
		var failed := {"ok": false, "reason": "fresh_native_restore", "restored": restored, "steps": steps, "player_normalized": not twin.player._validated_full_player_replay_snapshot(state.player).is_empty(), "player_preflight": twin.player._can_install_full_player_replay_snapshot(state.player)}
		failed["player_difference"] = _differences(state.player, twin.player.full_player_replay_snapshot())
		failed["actor_difference"] = _differences(state.actor, _cold(twin).actor)
		failed["effects_difference"] = _differences(state.effects, twin.effects.launch_transaction_snapshot())
		await _dispose(twin)
		return failed
	await _host.get_tree().physics_frame
	await _host.get_tree().physics_frame
	var continued: bool = world.player.advance_action_frame(next_intents) and twin.player.advance_action_frame(next_intents)
	await _host.get_tree().physics_frame
	var same: bool = continued and _cold(world) == _cold(twin)
	await _dispose(twin)
	return {"ok": same, "reason": "exact_original_next_frame" if not same else "", "digest": encoded.json.sha256_text()}


static func _differences(expected: Dictionary, actual: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in expected:
		if actual.get(key) != expected[key]:
			result.append(str(key))
	return result


static func _constructs(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in root.get_children():
		if child is CollisionObject2D:
			result.append(child)
		result.append_array(_constructs(child))
	return result


func _dispose(world: Dictionary) -> void:
	if world.get("ok", false):
		world.player.configure_hostile_frame_participant(null)
		world.player.cancel_transient_actions()
		world.effects.dispose_native_effects()
	if is_instance_valid(world.get("viewport")):
		world.viewport.queue_free()
	await _host.get_tree().process_frame
	await _host.get_tree().process_frame
