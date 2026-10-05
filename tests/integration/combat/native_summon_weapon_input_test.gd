extends "res://tests/integration/combat/native_summon_lifecycle_test.gd"

const NativeDriver := preload("res://scripts/dungeon/native_launch_encounter_driver.gd")
const Encounter := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")


func _run() -> void:
	suite = Suite.new()
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		if not OS.get_environment("PLANEWALKER_SUMMON_WEAPON_CASE").is_empty() and OS.get_environment("PLANEWALKER_SUMMON_WEAPON_CASE") != weapon:
			continue
		await _normal_weapon(weapon)
		await _normal_repeated_weapon(weapon)
	for id: String in ["ruins_wraith", "void_spore"]:
		if not OS.get_environment("PLANEWALKER_SUMMON_WEAPON_CASE").is_empty() and OS.get_environment("PLANEWALKER_SUMMON_WEAPON_CASE") != id:
			continue
		await _normal_terminal_split(id)
	if OS.get_environment("PLANEWALKER_SUMMON_WEAPON_CASE") in ["", "legacy_sword"]:
		await _historical_sword_identity()
	suite.finish(get_tree())


func _normal_weapon(weapon: String) -> void:
	var f := await _fixture("void_hunter")
	f.player.process_mode = Node.PROCESS_MODE_INHERIT
	f.player.set_physics_process(false)
	f.player.get_node("TimeManager").set_process(false)
	f.player.get_node("RewindRecorder").set_process(false)
	suite.assert_true(f.player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": f.player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}) and f.player.configure_hostile_frame_participant(f.bridge), "normal " + weapon + " binds actual Player and shared child frame authority")
	_start(f, "void_hunter.hunter_echo")
	for _frame: int in range(35):
		suite.assert_true(f.player.advance_action_frame(), "normal weapon fixture accepts authored echo birth")
	var children: Dictionary = f.effects.native_summon_actors()
	if children.size() != 1:
		suite.assert_true(false, "normal weapon requires one actual authenticated child")
		await _dispose(f)
		return
	var child: Node2D = children.values()[0]
	var source := str(child.hostile_source_id)
	var reward_eligible: bool = child.get_meta("reward_eligible")
	var health: Node = child.get_node("HealthComponent")
	var hp := float(health.current_hp)
	var observations: Array[float] = []
	health.damaged.connect(func(amount: float, _hp: float): observations.append(amount))
	f.actors[0].get("_launch_runtime").add_control_source("normal-weapon-isolation", "stop", 600, 1.0)
	child.get("_launch_runtime").add_control_source("normal-weapon-isolation", "stop", 600, 1.0)
	f.player.global_position = child.global_position - Vector2(42, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}) and f.player.try_action(&"weapon_primary"), "normal " + weapon + " input attacks actual summon Hurtbox")
	for frame: int in range(120):
		if frame == 40:
			f.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
		suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}), "normal " + weapon + " child collision frame accepts")
		await get_tree().physics_frame
	suite.assert_true(not observations.is_empty() and (not is_instance_valid(health) or health.current_hp < hp), "normal " + weapon + " producer physically damages authentic summon body")
	if is_instance_valid(health) and not health.dead:
		suite.assert_close(health.current_hp, child.launch_runtime_snapshot().runtime.mechanism_state.hp_after, "normal " + weapon + " preserves exact native child HP")
	else:
		suite.assert_true(not f.effects.native_summon_actors().has(source), "normal " + weapon + " lethal retires child lease and budget")
	suite.assert_true(f.effects.summon_snapshot().rows.size() == 1 and not reward_eligible, "normal " + weapon + " child collision creates no recursive child or reward")
	f.player.cancel_transient_actions()
	await _dispose(f)


func _normal_terminal_split(id: String) -> void:
	var f := await _fixture(id)
	var owner: Node2D = f.actors[0]
	owner.process_mode = Node.PROCESS_MODE_INHERIT
	owner.set_process(false)
	owner.set_physics_process(false)
	var source := str(owner.hostile_source_id)
	f.player.process_mode = Node.PROCESS_MODE_INHERIT
	f.player.set_physics_process(false)
	f.player.get_node("TimeManager").set_process(false)
	f.player.get_node("RewindRecorder").set_process(false)
	suite.assert_true(f.player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "weapon_profile": f.player._weapon_profile_catalog_definition(&"sword_launch_v1"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}) and f.player.configure_hostile_frame_participant(f.bridge), "actual Sword terminal fixture binds native Player authority")
	suite.assert_true(owner.get("_launch_runtime").add_control_source("terminal-weapon-isolation", "stop", 1200, 1.0), "terminal weapon isolation remains valid through repeated native attacks")
	var floor_id := "floor_ruins_of_remnant" if id == "ruins_wraith" else "floor_void_forest"
	var profile := "encounter_profile_ruins_adapter_v1" if id == "ruins_wraith" else "encounter_profile_forest_adapter_v1"
	var definition := {"id": profile + ".terminal_fixture", "floor_id": floor_id, "recipe_id": "terminal_fixture", "room_type": "elite", "waves": [{"id": "terminal_wave", "delay_frames": 0, "warning_frames": 30, "spawns": [{"id": "terminal_spawn", "enemy_id": id, "spawn_slot_id": "elite_primary", "spawn_offset": {"x": 0.0, "y": 0.0}, "elite": true, "affix_ids": ["frenzy"], "mechanism_ids": []}]}]}
	var encounter := Encounter.new()
	suite.assert_true(encounter.configure(definition, {"run_id": "run-summon-lifecycle", "room_id": "terminal-room", "runtime_frame": 0, "encounter_generation": 1}).ok, "terminal fixture uses real native Encounter ledger")
	for frame: int in range(1, 32):
		suite.assert_true(encounter.advance_frame(frame).ok and f.player.advance_action_frame(), "terminal fixture aligns real Player and Encounter accepted clocks")
	suite.assert_true(encounter.register_spawned("terminal_spawn", source), "terminal fixture registers its actual principal source")
	var driver := NativeDriver.new()
	driver.set("_player", f.player)
	driver.set("_bridge", f.bridge)
	driver.set("_effects", f.effects)
	driver.set("_encounter", encounter)
	driver.set("_definition", definition)
	driver.set("_actors", {source: owner})
	owner.hostile_final_death.connect(func(dead_source: StringName, receipt: String):
		driver._on_actor_final_death(dead_source, receipt)
		if not f.bridge.frame_transaction_is_active():
			f.bridge.retire_actor(str(dead_source))
	)
	for _attack: int in range(8):
		if not driver.get("_actors").has(source):
			break
		f.player.global_position = owner.global_position - Vector2(42, 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var frame := int(f.player.priority_arbitration_snapshot().frame) + 1
		suite.assert_true(encounter.advance_frame(frame).ok and f.player.advance_action_frame({"aim": Vector2.RIGHT}) and f.player.try_action(&"weapon_primary") and f.player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "normal Sword input attacks real terminal principal " + id)
		for action_frame: int in range(120):
			frame = int(f.player.priority_arbitration_snapshot().frame) + 1
			suite.assert_true(encounter.advance_frame(frame).ok and f.player.advance_action_frame({"aim": Vector2.RIGHT}), "actual terminal Sword collision frame accepts")
			await get_tree().physics_frame
			if not driver.get("_actors").has(source):
				break
	f.player.cancel_transient_actions()
	suite.assert_true(driver.get("_failure").is_empty() and not driver.get("_actors").has(source) and f.effects.summon_snapshot().rows.size() == 2, "actual native Driver retains two split children after normal physical Sword principal death " + id)
	suite.assert_true(encounter.snapshot().defeat_ledger.has(source) and encounter.snapshot().pending_work.size() == 2, "actual Driver authenticates principal receipt and preserves split encounter work")
	f.player.global_position = Vector2(500, 220)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for _warning: int in range(int(Content.action(id + (".spirit_split" if id == "ruins_wraith" else ".spore_split")).warning_frames) + 1):
		var frame := int(f.player.priority_arbitration_snapshot().frame) + 1
		suite.assert_true(encounter.advance_frame(frame).ok and f.player.advance_action_frame(), "real terminal children complete the full visible warning")
		await get_tree().physics_frame
	suite.assert_equal(f.effects.native_summon_actors().size(), 2, "normal Sword terminal split creates two actual unrewarded child bodies " + id)
	driver.free()
	await _dispose(f)


func _normal_repeated_weapon(weapon: String) -> void:
	var f := await _fixture("forge_titan")
	var owner: Node2D = f.actors[0]
	owner.process_mode = Node.PROCESS_MODE_INHERIT
	owner.set_process(false)
	owner.set_physics_process(false)
	f.player.process_mode = Node.PROCESS_MODE_INHERIT
	f.player.set_physics_process(false)
	f.player.get_node("TimeManager").set_process(false)
	f.player.get_node("RewindRecorder").set_process(false)
	suite.assert_true(f.player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": weapon, "weapon_profile": f.player._weapon_profile_catalog_definition(StringName(weapon + "_launch_v1")), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}) and f.player.configure_hostile_frame_participant(f.bridge), "repeated " + weapon + " input binds native elite body")
	suite.assert_true(owner.get("_launch_runtime").add_control_source("repeated-input-isolation", "stop", 600, 1.0), "repeated input isolates hostile action selection")
	var health: Node = owner.get_node("HealthComponent")
	var generations: Array[int] = []
	for _attack: int in range(2):
		var hp: float = health.current_hp
		f.player.global_position = owner.global_position - Vector2(42, 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}) and f.player.try_action(&"weapon_primary"), "repeated " + weapon + " accepts a distinct normal primary input")
		if weapon == "sword":
			suite.assert_true(f.player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "normal repeated Sword commits its authored light attack")
			generations.append(int(f.player.weapon_damage_action_identity().get("attack_generation", 0)))
		for frame: int in range(120):
			if frame == 40 and weapon != "sword":
				f.player.call("_submit_weapon_intent", &"weapon_primary", &"released")
			suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}), "repeated " + weapon + " completes actual native collision frame")
			await get_tree().physics_frame
		suite.assert_true(health.current_hp < hp and not health.dead, "each distinct normal " + weapon + " action physically settles new elite damage")
		suite.assert_close(health.current_hp, owner.launch_runtime_snapshot().runtime.mechanism_state.hp_after, "repeated native weapon preserves exact Health/domain HP agreement")
	if weapon == "sword":
		suite.assert_true(generations.size() == 2 and generations[0] > 0 and generations[1] > generations[0], "separate completed Sword inputs carry distinct monotonic damage generations")
	f.player.cancel_transient_actions()
	await _dispose(f)


func _historical_sword_identity() -> void:
	var f := await _sword_identity_fixture()
	for _cancel: int in range(4):
		f.player.weapon_action_coordinator.cancel(&"historical_cancellation")
	f.player.global_position = Vector2(500, 220)
	suite.assert_true(f.player.try_action(&"weapon_primary") and f.player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "cancellation-heavy historical fixture accepts an actual light Sword input")
	var legacy_windup: Dictionary = f.player.weapon_action_coordinator.snapshot()
	legacy_windup.runtime.adapter.current_attack.erase("damage_identity_revision")
	suite.assert_true(f.player.weapon_action_coordinator.restore_snapshot_for_rollback(legacy_windup), "explicit historical WINDUP restores without inventing a producer revision")
	suite.assert_equal(f.player.weapon_action_coordinator.snapshot(), legacy_windup, "historical WINDUP migration keeps the original frozen attack exact")
	for _frame: int in range(80):
		if f.player.get_node("SwordWeapon/Hitbox").is_active():
			break
		suite.assert_true(f.player.advance_action_frame({"aim": Vector2.RIGHT}), "historical Sword reaches ACTIVE through the shared native frame")
	var legacy: Dictionary = f.player.weapon_action_coordinator.snapshot()
	var legacy_generation := int(legacy.generation)
	suite.assert_true(legacy_generation > int(legacy.token), "historical cancellation epoch is ahead of the action token")
	suite.assert_equal(int(legacy.runtime.adapter.damage_attack_generation), legacy_generation, "restored historical WINDUP emits its original epoch when it becomes ACTIVE")
	legacy.runtime.adapter.current_attack.erase("damage_identity_revision")
	legacy.runtime.adapter.damage_attack_generation = legacy_generation
	suite.assert_true(f.player.weapon_action_coordinator.restore_snapshot_for_rollback(legacy), "explicit pre-revision active Sword restores its original epoch identity")
	var old_damage: RefCounted = f.player.get_node("SwordWeapon/Hitbox").get("_active_damage_info")
	if old_damage == null:
		suite.assert_true(false, "historical fixture requires the original active immutable damage")
		await _dispose(f)
		return
	suite.assert_equal(str(old_damage.hostile_source_id), "player_sword", "historical Sword retains its original producer namespace")
	suite.assert_true(f.actors[0].get_node("Hurtbox").receive_hit(old_damage) > 0.0, "historical immutable cast records a genuine native body receipt")
	var state := {"player": f.player.full_player_replay_snapshot(), "actor": f.actors[0].native_cold_snapshot(func(_node: Node): return {}), "effects": f.effects.launch_transaction_snapshot()}
	var encoded: Dictionary = Replay.encode_replay_json(state)
	var decoded: Dictionary = Replay.decode_replay_json(encoded.json)
	suite.assert_true(encoded.ok and decoded.ok and decoded.replay == state, "typed cold codec retains historical player, body receipt and frame authority exactly")
	var cold := await _sword_identity_fixture()
	suite.assert_true(cold.actors[0].restore_native_cold_snapshot(decoded.replay.actor, func(_binding: Dictionary): return null) and cold.effects.restore_launch_transaction_snapshot(decoded.replay.effects) and cold.player.restore_full_player_replay_snapshot(decoded.replay.player) and cold.bridge.configure(cold.player, cold.registry, cold.actors, cold.effects), "fresh native scene reconstructs cancellation-heavy historical active Sword and spent receipt")
	var restored: RefCounted = cold.player.get_node("SwordWeapon/Hitbox").get("_active_damage_info")
	var body_before: Dictionary = cold.actors[0].native_cold_snapshot(func(_node: Node): return {})
	suite.assert_true(restored != null and cold.actors[0].get_node("Hurtbox").receive_hit(restored) == 0.0, "cold historical cast refuses its already-spent immutable identity")
	suite.assert_equal(cold.actors[0].native_cold_snapshot(func(_node: Node): return {}), body_before, "historical spent refusal leaves exact native HP and claims unchanged")
	for _frame: int in range(120):
		suite.assert_true(cold.player.advance_action_frame({"aim": Vector2.RIGHT}), "restored historical cast completes its original phases")
	var health: Node = cold.actors[0].get_node("HealthComponent")
	for action_token: int in range(2, legacy_generation + 1):
		cold.player.global_position = cold.actors[0].global_position - Vector2(42, 0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var hp: float = health.current_hp
		suite.assert_true(cold.player.try_action(&"weapon_primary") and cold.player.call("_submit_weapon_intent", &"weapon_primary", &"released"), "cold historical continuation accepts actual new Sword input %d" % action_token)
		suite.assert_equal(int(cold.player.weapon_action_coordinator.current_token()), action_token, "cold continuation uses the next authentic action token")
		suite.assert_equal(int(cold.player.weapon_action_coordinator.snapshot().runtime.adapter.current_attack.damage_identity_revision), 2, "new input after historical recovery declares the current producer revision")
		for _frame: int in range(120):
			suite.assert_true(cold.player.advance_action_frame({"aim": Vector2.RIGHT}), "cold continuation completes actual native Sword collision")
			await get_tree().physics_frame
		suite.assert_true(health.current_hp < hp and not health.dead, "new Sword input settles despite an opaque historical epoch receipt %d" % action_token)
		suite.assert_close(health.current_hp, cold.actors[0].launch_runtime_snapshot().runtime.mechanism_state.hp_after, "cold Sword continuation preserves exact Health/domain agreement")
	cold.player.cancel_transient_actions()
	f.player.cancel_transient_actions()
	await _dispose(cold)
	await _dispose(f)


func _sword_identity_fixture() -> Dictionary:
	var f := await _fixture("forge_titan")
	f.actors[0].process_mode = Node.PROCESS_MODE_INHERIT
	f.actors[0].set_process(false)
	f.actors[0].set_physics_process(false)
	f.player.process_mode = Node.PROCESS_MODE_INHERIT
	f.player.set_physics_process(false)
	f.player.get_node("TimeManager").set_process(false)
	f.player.get_node("RewindRecorder").set_process(false)
	suite.assert_true(f.player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "weapon_profile": f.player._weapon_profile_catalog_definition(&"sword_launch_v1"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}) and f.player.configure_hostile_frame_participant(f.bridge), "Sword identity cold fixture binds genuine native Player and body")
	suite.assert_true(f.actors[0].get("_launch_runtime").add_control_source("identity-cold-isolation", "stop", 1200, 1.0), "cold identity test isolates native hostile action selection")
	return f
