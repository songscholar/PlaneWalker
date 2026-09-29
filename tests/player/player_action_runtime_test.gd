extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_attack_definitions_and_active_hitbox()
	await _test_active_dash_buffer_and_recovery_cancel()
	await _test_time_actions_use_the_action_owner()
	await _test_hitstun_and_dead_are_exclusive()
	await _test_candidate_actions_remain_inactive_in_m1()
	await _test_ui_snapshot_uses_equipped_time_slots()
	_suite.finish(get_tree())


func _test_attack_definitions_and_active_hitbox() -> void:
	var player := await _spawn_player()
	var sword: Node = player.get_node("SwordWeapon")
	var hitbox: Area2D = sword.get_node("Hitbox")
	var light: Dictionary = sword.attack_definition(false)
	var heavy: Dictionary = sword.attack_definition(true)

	_suite.assert_equal(light["windup_frames"], 6, "light opener has six windup frames at base speed")
	_suite.assert_equal(light["active_frames"], 5, "light opener has five active frames at base speed")
	_suite.assert_equal(light["recovery_frames"], 11, "light opener has eleven recovery frames at base speed")
	_suite.assert_close(light["movement_multiplier"], 0.55, "light attack preserves partial movement")
	_suite.assert_equal(heavy["windup_frames"], 21, "heavy attack has twenty-one windup frames")
	_suite.assert_equal(heavy["active_frames"], 8, "heavy attack has eight active frames")
	_suite.assert_equal(heavy["recovery_frames"], 27, "heavy attack has twenty-seven recovery frames")
	_suite.assert_close(heavy["movement_multiplier"], 0.2, "heavy attack strongly limits movement")

	_suite.assert_true(player.try_action(&"attack"), "free player commits a light attack")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.ATTACK_WINDUP, "attack begins in windup")
	_suite.assert_true(not hitbox.is_active(), "hitbox stays closed during windup")
	_suite.assert_close(player.get_action_movement_multiplier(), 0.55, "controller exposes committed light movement multiplier")
	_advance(player, light["windup_frames"] - 1)
	_suite.assert_true(not hitbox.is_active(), "hitbox remains closed before the final windup frame")
	player.advance_action_frame()
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.ATTACK_ACTIVE, "controller advances windup into active")
	_suite.assert_true(hitbox.is_active(), "hitbox opens exactly in active")
	_advance(player, light["active_frames"])
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.ATTACK_RECOVERY, "controller advances active into recovery")
	_suite.assert_true(not hitbox.is_active(), "hitbox closes before recovery")

	player.cancel_transient_actions()
	_suite.assert_true(player.try_action(&"heavy_attack"), "free player commits a heavy attack")
	_suite.assert_close(player.get_action_movement_multiplier(), 0.2, "controller exposes committed heavy movement multiplier")
	player.cancel_transient_actions()
	await _free_player(player)


func _test_active_dash_buffer_and_recovery_cancel() -> void:
	var player := await _spawn_player()
	var sword: Node = player.get_node("SwordWeapon")
	var definition: Dictionary = sword.attack_definition(false)
	player.try_action(&"attack")
	_advance(player, definition["windup_frames"])

	_suite.assert_true(player.try_action(&"dash"), "dash input is buffered during attack active")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.ATTACK_ACTIVE, "buffered dash does not skip active")
	_suite.assert_true(player.action_state.has_buffered_input(&"dash"), "action owner retains active-stage dash buffer")
	_advance(player, definition["active_frames"])
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.ATTACK_RECOVERY, "attack reaches recovery before dash")
	_advance(player, definition["recovery_cancel_frame"] - 1)
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.ATTACK_RECOVERY, "dash waits until recovery cancel frame")
	player.advance_action_frame()
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.DASH, "buffered dash owns the action clock when cancel opens")
	_suite.assert_true(not sword.is_attacking(), "recovery cancel closes the abandoned sword action")
	_suite.assert_true(player.get_action_movement_multiplier() > 1.0, "dash action uses dash movement rather than attack movement")
	await _free_player(player)


func _test_time_actions_use_the_action_owner() -> void:
	var stop_player := await _spawn_player()
	var stop_manager: Node = stop_player.get_node("TimeManager")
	stop_manager.time_stop_duration = 0.01
	var energy_before_stop: float = stop_manager.energy
	_suite.assert_true(stop_player.try_action(&"time_stop"), "time stop commits through the player action owner")
	_suite.assert_equal(stop_player.action_state.current_state, PlayerActionStateScript.State.TIME_CAST, "time stop occupies time-cast state")
	_suite.assert_true(stop_manager.energy < energy_before_stop, "committed time stop spends energy")
	await _free_player(stop_player)

	var rewind_player := await _spawn_player()
	var rewind_manager: Node = rewind_player.get_node("TimeManager")
	var recorder: Node = rewind_player.get_node("RewindRecorder")
	rewind_player.global_position = Vector2(24.0, 48.0)
	recorder._record_snapshot()
	rewind_player.global_position = Vector2(240.0, 180.0)
	_suite.assert_true(rewind_player.try_action(&"time_rewind"), "rewind commits through the player action owner")
	_suite.assert_equal(rewind_player.global_position, Vector2(24.0, 48.0), "rewind still restores the recorded position")
	_suite.assert_equal(rewind_player.action_state.current_state, PlayerActionStateScript.State.FREE, "rewind restores only a safe free action state")
	await _free_player(rewind_player)


func _test_hitstun_and_dead_are_exclusive() -> void:
	var player := await _spawn_player()
	var sword: Node = player.get_node("SwordWeapon")
	player.try_action(&"attack")
	_suite.assert_true(player.apply_hitstun_frames(3), "hitstun interrupts a committed attack")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.HITSTUN, "hitstun becomes the exclusive action")
	_suite.assert_true(not sword.is_attacking(), "hitstun closes the sword action")
	_suite.assert_true(not player.try_action(&"dash"), "hitstun rejects dash input")
	_advance(player, 3)
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.FREE, "hitstun returns to free after its frames")

	var health: Node = player.get_node("HealthComponent")
	health.lose_health(health.current_hp, &"test")
	_suite.assert_equal(player.action_state.current_state, PlayerActionStateScript.State.DEAD, "death enters terminal action state")
	_suite.assert_true(not player.try_action(&"attack"), "dead player rejects attacks")
	_suite.assert_true(not player.try_action(&"time_stop"), "dead player rejects time casts")
	await _free_player(player)


func _test_candidate_actions_remain_inactive_in_m1() -> void:
	var player := await _spawn_player()
	var bow: Node = player.get_node("BowWeapon")
	var time_manager: Node = player.get_node("TimeManager")
	var energy_before: float = time_manager.energy

	_suite.assert_true(not player.try_action(&"ranged_attack"), "M1 rejects Bow without deleting its implementation")
	_suite.assert_true(not player.try_action(&"time_rift"), "M1 rejects unequipped Time Rift")
	_suite.assert_true(not player.try_action(&"time_accelerate"), "M1 rejects unequipped Time Accelerate")
	_suite.assert_true(not bow.is_profile_action_active(), "rejected Bow input stages no profile payload")
	_suite.assert_close(time_manager.energy, energy_before, "rejected candidate skills spend no energy")

	var snapshot: Dictionary = player.get_player_ui_snapshot()
	_suite.assert_close(snapshot["hp"], player.health.current_hp, "UI snapshot reads current hp")
	_suite.assert_close(snapshot["max_hp"], player.health.max_hp, "UI snapshot reads max hp")
	_suite.assert_close(snapshot["energy"], time_manager.energy, "UI snapshot reads time energy")
	_suite.assert_equal(snapshot["action_state"], "FREE", "UI snapshot publishes stable action name")
	await _free_player(player)


func _test_ui_snapshot_uses_equipped_time_slots() -> void:
	var player := await _spawn_player()
	var time_manager: Node = player.get_node("TimeManager")
	var default_snapshot: Dictionary = player.get_player_ui_snapshot()
	_suite.assert_true(not default_snapshot.has("cooldowns"), "UI snapshot removes the legacy cooldown dictionary")
	_suite.assert_equal(
		default_snapshot.get("time_slots", []),
		[
			{"ability_id": "stop", "action_id": "time_stop", "cooldown": 0.0},
			{"ability_id": "rewind", "action_id": "time_rewind", "cooldown": 0.0},
		],
		"default M1 snapshot publishes Stop/Rewind in configured order"
	)

	_suite.assert_true(
		player.configure_loadout({"weapon_id": "sword", "enabled_time_skills": ["stop", "rift"]}),
		"candidate Stop/Rift loadout configures for UI projection"
	)
	time_manager.set("_cooldowns", {
		&"time_stop": 1.25,
		&"time_rewind": 2.0,
		&"time_rift": 4.5,
		&"time_accelerate": 3.0,
	})
	var candidate_snapshot: Dictionary = player.get_player_ui_snapshot()
	_suite.assert_equal(
		candidate_snapshot.get("time_slots", []),
		[
			{"ability_id": "stop", "action_id": "time_stop", "cooldown": 1.25},
			{"ability_id": "rift", "action_id": "time_rift", "cooldown": 4.5},
		],
		"candidate snapshot publishes only equipped abilities with strict action mapping"
	)

	var exposed_slots: Variant = candidate_snapshot.get("time_slots")
	if exposed_slots is Array and (exposed_slots as Array).size() == 2:
		(exposed_slots as Array)[0]["ability_id"] = "changed"
		(exposed_slots as Array).reverse()
	var snapshot_again: Dictionary = player.get_player_ui_snapshot()
	_suite.assert_equal(
		snapshot_again.get("time_slots", []),
		[
			{"ability_id": "stop", "action_id": "time_stop", "cooldown": 1.25},
			{"ability_id": "rift", "action_id": "time_rift", "cooldown": 4.5},
		],
		"mutating a UI snapshot cannot change equipped slot identity or order"
	)

	_suite.assert_true(
		player.configure_loadout({"weapon_id": "sword", "enabled_time_skills": ["accelerate", "rewind"]}),
		"candidate Accelerate/Rewind loadout configures for UI projection"
	)
	time_manager.set("_cooldowns", {
		&"time_stop": 1.0,
		&"time_rewind": 2.5,
		&"time_rift": 3.0,
		&"time_accelerate": 6.75,
	})
	_suite.assert_equal(
		player.get_player_ui_snapshot().get("time_slots", []),
		[
			{"ability_id": "accelerate", "action_id": "time_accelerate", "cooldown": 6.75},
			{"ability_id": "rewind", "action_id": "time_rewind", "cooldown": 2.5},
		],
		"remaining canonical abilities keep their strict action mapping and configured order"
	)
	await _free_player(player)


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


func _advance(player: Node, frames: int) -> void:
	for _frame: int in range(frames):
		player.advance_action_frame()
