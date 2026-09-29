extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_rewind_window_is_generation_safe_and_single_claim()
	await _test_stop_and_accelerate_are_exposed_without_private_reads()
	_suite.finish(get_tree())


func _test_rewind_window_is_generation_safe_and_single_claim() -> void:
	var player := await _spawn_player()
	var recorder: Node = player.get_node("RewindRecorder")
	player.global_position = Vector2(24.0, 36.0)
	recorder.call("_record_snapshot")
	player.global_position = Vector2(160.0, 120.0)
	_suite.assert_true(player.try_action(&"time_slot_2"), "Rewind commits for the Bow interaction fixture")
	_suite.assert_true(
		player.has_method("weapon_time_interaction_context"),
		"Player exposes immutable weapon time context"
	)
	if not player.has_method("weapon_time_interaction_context"):
		await _free_player(player)
		return
	var context: Dictionary = player.call("weapon_time_interaction_context")
	_suite.assert_true(bool(context.get("rewind_echo_available", false)), "Rewind opens the two-second Bow echo window")
	var generation := int(context.get("rewind_echo_generation", 0))
	_suite.assert_true(generation > 0, "Rewind echo window carries a positive generation")
	_suite.assert_true(
		player.has_method("claim_weapon_time_interaction"),
		"Player exposes generation-safe interaction claims"
	)
	if player.has_method("claim_weapon_time_interaction"):
		_suite.assert_true(
			bool(player.call("claim_weapon_time_interaction", &"bow_rewind_echo", generation)),
			"the active Rewind generation can be claimed once"
		)
		_suite.assert_true(
			not bool(player.call("claim_weapon_time_interaction", &"bow_rewind_echo", generation)),
			"the same Rewind generation cannot create duplicate echo volleys"
		)
		_suite.assert_true(
			not bool(player.call("claim_weapon_time_interaction", &"bow_rewind_echo", generation - 1)),
			"stale Rewind generations fail closed"
		)
	context = player.call("weapon_time_interaction_context")
	_suite.assert_true(not bool(context.get("rewind_echo_available", true)), "claiming closes the Rewind echo window")
	await _free_player(player)


func _test_stop_and_accelerate_are_exposed_without_private_reads() -> void:
	var player := await _spawn_player()
	var time_manager: Node = player.get_node("TimeManager")
	time_manager.time_stop_duration = 0.2
	_suite.assert_true(player.try_action(&"time_slot_1"), "Stop commits for the weapon context fixture")
	if player.has_method("weapon_time_interaction_context"):
		var stopped: Dictionary = player.call("weapon_time_interaction_context")
		_suite.assert_true(bool(stopped.get("stop_active", false)), "weapon context reports active Stop")
		var remaining_before := int(stopped.get("stop_remaining_frames", 0))
		_suite.assert_true(player.has_method("extend_weapon_time_stop"), "Player exposes bounded Stop extension for Bow hits")
		if player.has_method("extend_weapon_time_stop"):
			_suite.assert_true(
				bool(player.call("extend_weapon_time_stop", 701, 60)),
				"one full-charge Bow action extends active Stop once"
			)
			_suite.assert_true(
				not bool(player.call("extend_weapon_time_stop", 701, 60)),
				"multi-hit reuse of the same action token cannot extend Stop twice"
			)
			var extended: Dictionary = player.call("weapon_time_interaction_context")
			_suite.assert_equal(
				int(extended.get("stop_remaining_frames", 0)),
				remaining_before + 60,
				"Stop extension is capped to the declared sixty frames"
			)
			_suite.assert_true(
				not bool(player.call("extend_weapon_time_stop", 702, 60)),
				"one Stop activation cannot accumulate unbounded extensions across action tokens"
			)
	player.cancel_active_time_effects(&"test_reset")
	await _free_player(player)

	player = await _spawn_player(["accelerate", "rewind"])
	_suite.assert_true(player.try_action(&"time_slot_1"), "Accelerate commits for the weapon context fixture")
	if player.has_method("weapon_time_interaction_context"):
		var accelerated: Dictionary = player.call("weapon_time_interaction_context")
		_suite.assert_true(bool(accelerated.get("accelerate_active", false)), "weapon context reports active Accelerate")
	player.cancel_active_time_effects(&"test_reset")
	await _free_player(player)


func _spawn_player(time_abilities: Array = ["stop", "rewind"]) -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	_suite.assert_true(player.configure_loadout({
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": time_abilities.duplicate(true),
		"difficulty": "normal",
		"seed": 20260929,
	}), "time interaction fixture configures")
	return player


func _free_player(player: Node) -> void:
	await get_tree().create_timer(0.65).timeout
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
