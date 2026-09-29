extends Node

const PLAYER_LOADOUT_RUNTIME_PATH := "res://scripts/player/player_loadout_runtime.gd"
const PlayerScene := preload("res://scenes/player/player.tscn")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_component_contract()
	await _test_m1_equipment_isolation()
	await _test_successful_reconfigure_resets_runtime_state()
	await _test_invalid_reconfigure_preserves_runtime_state()
	await _test_reconfigure_revives_dead_player()
	_suite.finish(get_tree())


func _test_component_contract() -> void:
	var runtime_script: Script = load(PLAYER_LOADOUT_RUNTIME_PATH)
	_suite.assert_true(runtime_script != null, "player loadout runtime script exists")
	if runtime_script == null:
		return

	var runtime = runtime_script.new()
	var source := _config("sword", ["stop", "rewind"])
	source["weapon_profile"] = _weapon_profile("sword_m1_v1", "sword")
	_suite.assert_true(bool(runtime.call("configure", source)), "valid loadout configures the component")
	_suite.assert_equal(str(runtime.call("weapon_id")), "sword", "component stores the equipped weapon")
	_suite.assert_true(runtime.has_method("weapon_profile_id"), "component exposes the equipped profile identity")
	_suite.assert_true(runtime.has_method("weapon_profile_snapshot"), "component exposes an isolated profile snapshot")
	if runtime.has_method("weapon_profile_id"):
		_suite.assert_equal(str(runtime.call("weapon_profile_id")), "sword_m1_v1", "component stores the equipped weapon profile")
	_suite.assert_equal(_string_ids(runtime.call("time_ability_ids")), ["stop", "rewind"], "component stores exactly two abilities")
	_suite.assert_true(bool(runtime.call("has_weapon", &"sword")), "component answers equipped weapon queries")
	_suite.assert_true(not bool(runtime.call("has_weapon", &"bow")), "component rejects unequipped weapon queries")
	_suite.assert_true(bool(runtime.call("has_time_ability", &"stop")), "component answers first equipped ability")
	_suite.assert_true(bool(runtime.call("has_time_ability", &"rewind")), "component answers second equipped ability")
	_suite.assert_true(not bool(runtime.call("has_time_ability", &"rift")), "component rejects unequipped ability queries")

	source["weapon_id"] = "bow"
	(source["enabled_time_skills"] as Array)[0] = "rift"
	(source["weapon_profile"] as Dictionary)["id"] = "forged_profile"
	_suite.assert_equal(str(runtime.call("weapon_id")), "sword", "component is isolated from caller weapon mutation")
	_suite.assert_equal(_string_ids(runtime.call("time_ability_ids")), ["stop", "rewind"], "component deep-copies caller ability arrays")
	if runtime.has_method("weapon_profile_id"):
		_suite.assert_equal(str(runtime.call("weapon_profile_id")), "sword_m1_v1", "component deep-copies the caller weapon profile")

	var returned_ids: Array = runtime.call("time_ability_ids")
	returned_ids[0] = "accelerate"
	returned_ids.append("rift")
	_suite.assert_equal(_string_ids(runtime.call("time_ability_ids")), ["stop", "rewind"], "ability query returns an isolated copy")
	if runtime.has_method("weapon_profile_snapshot"):
		var returned_profile: Dictionary = runtime.call("weapon_profile_snapshot")
		returned_profile["id"] = "forged_profile"
		_suite.assert_equal(str(runtime.call("weapon_profile_id")), "sword_m1_v1", "profile query returns an isolated copy")

	var invalid_configs: Array[Dictionary] = []
	invalid_configs.append(_config("sword", ["stop"]))
	invalid_configs.append(_config("sword", ["stop", "rewind", "rift"]))
	invalid_configs.append(_config("sword", ["stop", "stop"]))
	var mismatched_profile := _config("sword", ["stop", "rewind"])
	mismatched_profile["weapon_profile"] = _weapon_profile("bow_candidate_v1", "bow")
	invalid_configs.append(mismatched_profile)
	for invalid: Dictionary in invalid_configs:
		_suite.assert_true(not bool(runtime.call("configure", invalid)), "component rejects malformed two-ability loadout")
		_suite.assert_equal(str(runtime.call("weapon_id")), "sword", "failed configure preserves the prior weapon")
		_suite.assert_equal(_string_ids(runtime.call("time_ability_ids")), ["stop", "rewind"], "failed configure preserves the prior abilities atomically")
		if runtime.has_method("weapon_profile_id"):
			_suite.assert_equal(str(runtime.call("weapon_profile_id")), "sword_m1_v1", "failed configure preserves the prior profile atomically")
	runtime.free()


func _test_m1_equipment_isolation() -> void:
	var player := await _spawn_player()

	_suite.assert_true(player.has_method("configure_loadout"), "player exposes authoritative loadout activation")
	var loadout := player.get_node_or_null("PlayerLoadoutRuntime")
	_suite.assert_true(loadout != null, "player scene owns a loadout runtime component")
	if not player.has_method("configure_loadout") or loadout == null:
		await _free_player(player)
		return

	var config := _config("sword", ["stop", "rewind"])
	_suite.assert_true(bool(player.call("configure_loadout", config)), "M1 loadout applies to the player")
	config["weapon_id"] = "bow"
	(config["enabled_time_skills"] as Array)[0] = "rift"
	_suite.assert_equal(str(loadout.call("weapon_id")), "sword", "player loadout is isolated from caller weapon mutation")
	_suite.assert_equal(_string_ids(loadout.call("time_ability_ids")), ["stop", "rewind"], "player loadout is isolated from caller ability mutation")

	_suite.assert_true(bool(player.call("try_action", &"attack")), "equipped Sword commits")
	player.call("cancel_transient_actions")
	_suite.assert_true(not bool(player.call("try_action", &"ranged_attack")), "unequipped Bow is rejected")
	_suite.assert_true(not bool(player.call("try_action", &"time_rift")), "unequipped Rift is rejected")
	_suite.assert_true(not bool(player.call("try_action", &"time_accelerate")), "unequipped Accelerate is rejected")
	_suite.assert_true(
		not bool(player.get_node("BowWeapon").call("is_profile_action_active")),
		"rejected Bow input stages no profile payload"
	)

	var time_manager: Node = player.get_node("TimeManager")
	time_manager.set("time_stop_duration", 0.01)
	_suite.assert_true(bool(player.call("try_action", &"time_stop")), "equipped Stop commits")
	player.call("cancel_transient_actions")
	var recorder: Node = player.get_node("RewindRecorder")
	recorder.call("_record_snapshot")
	_suite.assert_true(bool(player.call("try_action", &"time_rewind")), "equipped Rewind commits")

	player.call("cancel_transient_actions")
	_suite.assert_true(bool(player.call("configure_loadout", _config("bow", ["stop", "rift"]))), "candidate Bow loadout applies")
	_suite.assert_true(not bool(player.call("try_action", &"attack")), "unequipped Sword is rejected")
	_suite.assert_true(bool(player.call("try_action", &"ranged_attack")), "equipped Bow starts charging")
	_suite.assert_equal(
		player.weapon_presentation_snapshot().get("phase"),
		"HOLD",
		"equipped Bow charge is owned by the shared coordinator"
	)
	_suite.assert_true(not bool(player.call("try_action", &"time_rewind")), "unequipped Rewind is rejected")
	time_manager.time_rift_duration = 0.01
	_suite.assert_true(bool(player.call("try_action", &"time_rift")), "equipped Rift commits through the shared action owner")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.TIME_CAST, "equipped Rift owns the time-cast state")
	await _free_player(player)


func _test_successful_reconfigure_resets_runtime_state() -> void:
	var player := await _spawn_player()
	var time_manager: Node = player.get_node("TimeManager")

	_suite.assert_true(player.configure_loadout(_config("bow", ["stop", "rift"])), "dirty-state setup equips Bow")
	_suite.assert_true(player.try_action(&"ranged_attack"), "dirty-state setup begins Bow charge")
	var bow_hold: Dictionary = player.weapon_presentation_snapshot()
	player.set("_dash_cooldown_remaining", 2.0)
	player.action_state.buffer_input(&"attack", 30)
	player.apply_knockback(Vector2(90.0, -30.0))
	player.velocity = Vector2(120.0, 40.0)
	time_manager.time_rift_duration = 10.0
	time_manager.time_accelerate_duration = 0.1
	_suite.assert_true(time_manager.try_time_rift(Vector2.ZERO), "dirty-state setup creates Rift")
	_suite.assert_true(time_manager.try_time_accelerate(), "dirty-state setup enables acceleration")
	time_manager.set("_cooldowns", {
		&"time_stop": 3.0,
		&"time_rewind": 4.0,
		&"time_rift": 5.0,
		&"time_accelerate": 6.0,
	})
	_suite.assert_equal(bow_hold.get("phase"), "HOLD", "coordinator Bow charge exists before successful reconfigure")
	_suite.assert_true(int(bow_hold.get("token", 0)) > 0, "coordinator Bow charge owns a token before reconfigure")
	_suite.assert_equal(
		bow_hold.get("runtime", {}).get("cooldown_frames"),
		21,
		"Bow candidate exposes its Profile-authoritative cooldown"
	)
	_suite.assert_true(player.is_time_accelerated(), "acceleration exists before successful reconfigure")
	_suite.assert_true(not get_tree().get_nodes_in_group("time_rifts").is_empty(), "Rift exists before successful reconfigure")

	_suite.assert_true(player.configure_loadout(_config("sword", ["stop", "rewind"])), "valid reconfigure succeeds")
	await get_tree().process_frame
	var reconfigured_weapon: Dictionary = player.weapon_presentation_snapshot()
	_suite.assert_equal(reconfigured_weapon.get("weapon_id"), "sword", "successful reconfigure replaces Bow authority")
	_suite.assert_equal(reconfigured_weapon.get("phase"), "READY", "successful reconfigure clears Bow HOLD")
	_suite.assert_equal(int(reconfigured_weapon.get("token", -1)), 0, "successful reconfigure invalidates Bow token")
	_suite.assert_close(time_manager.energy, time_manager.max_energy, "successful reconfigure restores time energy")
	for skill_id: StringName in [&"time_stop", &"time_rewind", &"time_rift", &"time_accelerate"]:
		_suite.assert_close(time_manager.get_cooldown(skill_id), 0.0, "successful reconfigure clears %s cooldown" % skill_id)
	_suite.assert_true(get_tree().get_nodes_in_group("time_rifts").is_empty(), "successful reconfigure removes active Rifts")
	_suite.assert_true(not player.is_time_accelerated(), "successful reconfigure clears acceleration")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.FREE, "successful reconfigure resets the action state")
	_suite.assert_true(not player.action_state.has_buffered_input(&"attack"), "successful reconfigure clears buffered actions")
	_suite.assert_close(float(player.get("_dash_cooldown_remaining")), 0.0, "successful reconfigure clears dash cooldown")
	_suite.assert_equal(player.get("_dash_velocity"), Vector2.ZERO, "successful reconfigure clears dash velocity")
	_suite.assert_equal(player.get("_knockback_velocity"), Vector2.ZERO, "successful reconfigure clears knockback")
	_suite.assert_equal(player.velocity, Vector2.ZERO, "successful reconfigure clears body velocity")
	await _free_player(player)


func _test_invalid_reconfigure_preserves_runtime_state() -> void:
	var player := await _spawn_player()
	var time_manager: Node = player.get_node("TimeManager")
	_suite.assert_true(player.configure_loadout(_config("bow", ["stop", "rewind"])), "invalid reset setup equips Bow")
	_suite.assert_true(player.try_action(&"ranged_attack"), "invalid reset setup begins Bow charge")
	var bow_before: Dictionary = player.weapon_presentation_snapshot()
	player.set("_dash_cooldown_remaining", 2.0)
	player.action_state.buffer_input(&"attack", 30)
	player.apply_knockback(Vector2(60.0, 15.0))
	player.apply_time_acceleration(1.5, 0.1)
	time_manager.energy = 17.0
	time_manager.set("_cooldowns", {
		&"time_stop": 3.0,
		&"time_rewind": 4.0,
		&"time_rift": 5.0,
		&"time_accelerate": 6.0,
	})

	_suite.assert_true(not player.configure_loadout(_config("sword", ["stop"])), "invalid reconfigure fails")
	var bow_after: Dictionary = player.weapon_presentation_snapshot()
	_suite.assert_equal(bow_after.get("phase"), "HOLD", "invalid reconfigure preserves coordinator Bow charge")
	_suite.assert_equal(bow_after.get("token"), bow_before.get("token"), "invalid reconfigure preserves Bow token")
	_suite.assert_equal(bow_after.get("generation"), bow_before.get("generation"), "invalid reconfigure preserves Bow generation")
	_suite.assert_close(float(player.get("_dash_cooldown_remaining")), 2.0, "invalid reconfigure preserves dash cooldown")
	_suite.assert_close(time_manager.energy, 17.0, "invalid reconfigure preserves time energy")
	_suite.assert_close(time_manager.get_cooldown(&"time_rift"), 5.0, "invalid reconfigure preserves time cooldowns")
	_suite.assert_true(player.is_time_accelerated(), "invalid reconfigure preserves acceleration")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.ATTACK_WINDUP, "invalid reconfigure preserves HOLD projection")
	_suite.assert_true(player.action_state.has_buffered_input(&"attack"), "invalid reconfigure preserves buffered actions")
	_suite.assert_equal(player.get("_knockback_velocity"), Vector2(60.0, 15.0), "invalid reconfigure preserves knockback")
	_suite.assert_equal(str(player.loadout_runtime.weapon_id()), "bow", "invalid reconfigure preserves the equipped weapon")
	await _free_player(player)


func _test_reconfigure_revives_dead_player() -> void:
	var player := await _spawn_player()
	var health: Node = player.get_node("HealthComponent")
	health.lose_health(health.current_hp, &"loadout_reset_test")
	_suite.assert_true(health.dead, "dead reset setup marks health dead")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.DEAD, "dead reset setup enters terminal action state")

	_suite.assert_true(player.configure_loadout(_config("sword", ["stop", "rewind"])), "valid new-run reconfigure revives the player")
	_suite.assert_true(not health.dead, "new-run reconfigure clears dead health state")
	_suite.assert_close(health.current_hp, health.max_hp, "new-run reconfigure restores full health")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.FREE, "new-run reconfigure returns actions to free")
	_suite.assert_true(player.try_action(&"attack"), "revived player can commit the equipped weapon")
	player.cancel_transient_actions()
	await _free_player(player)


func _config(weapon_id: String, ability_ids: Array) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": weapon_id,
		"enabled_time_skills": ability_ids.duplicate(true),
		"difficulty": "normal",
		"seed": 20260929,
	}


func _weapon_profile(profile_id: String, weapon_id: String) -> Dictionary:
	return {
		"id": profile_id,
		"weapon_id": weapon_id,
		"runtime_kind": weapon_id,
		"actions": [],
		"resources": [],
		"capabilities": [],
		"payloads": [],
		"cues": [],
	}


func _string_ids(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if not values is Array:
		return result
	for value: Variant in values:
		result.append(str(value))
	return result


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	return player


func _free_player(player: Node) -> void:
	await get_tree().create_timer(0.65).timeout
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
