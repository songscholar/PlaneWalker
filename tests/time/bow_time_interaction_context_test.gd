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
	await _test_rift_context_tracks_live_spatial_generations()
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
	time_manager.time_stop_cost = 0.0
	time_manager.time_stop_cooldown = 0.0
	time_manager.time_stop_duration = 0.2
	_suite.assert_true(player.try_action(&"time_slot_1"), "Stop commits for the weapon context fixture")
	var stop_generation := 0
	if player.has_method("weapon_time_interaction_context"):
		var stopped: Dictionary = player.call("weapon_time_interaction_context")
		_suite.assert_true(bool(stopped.get("stop_active", false)), "weapon context reports active Stop")
		stop_generation = int(stopped.get("stop_generation", 0))
		_suite.assert_true(stop_generation > 0, "active Stop exposes a positive source generation")
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
	var stopped_reset: Dictionary = player.call("weapon_time_interaction_context")
	_suite.assert_true(not bool(stopped_reset.get("stop_active", true)), "ending Stop clears its active context")
	_suite.assert_equal(int(stopped_reset.get("stop_generation", -1)), 0, "ending Stop exposes no live source generation")
	_advance_time_cast(player)
	_suite.assert_true(player.try_action(&"time_slot_1"), "Stop can reactivate after its prior lifecycle ends")
	var stopped_again: Dictionary = player.call("weapon_time_interaction_context")
	_suite.assert_true(
		int(stopped_again.get("stop_generation", 0)) > stop_generation,
		"reactivated Stop advances its source generation monotonically"
	)
	player.cancel_active_time_effects(&"test_reset")
	await _free_player(player)

	player = await _spawn_player(["accelerate", "rewind"])
	time_manager = player.get_node("TimeManager")
	time_manager.time_accelerate_cost = 0.0
	time_manager.time_accelerate_cooldown = 0.0
	_suite.assert_true(player.try_action(&"time_slot_1"), "Accelerate commits for the weapon context fixture")
	var accelerate_generation := 0
	if player.has_method("weapon_time_interaction_context"):
		var accelerated: Dictionary = player.call("weapon_time_interaction_context")
		_suite.assert_true(bool(accelerated.get("accelerate_active", false)), "weapon context reports active Accelerate")
		accelerate_generation = int(accelerated.get("accelerate_generation", 0))
		_suite.assert_true(accelerate_generation > 0, "active Accelerate exposes a positive source generation")
	player.cancel_active_time_effects(&"test_reset")
	var accelerated_reset: Dictionary = player.call("weapon_time_interaction_context")
	_suite.assert_true(not bool(accelerated_reset.get("accelerate_active", true)), "ending Accelerate clears its active context")
	_suite.assert_equal(int(accelerated_reset.get("accelerate_generation", -1)), 0, "ending Accelerate exposes no live source generation")
	_advance_time_cast(player)
	_suite.assert_true(player.try_action(&"time_slot_1"), "Accelerate can reactivate after its prior lifecycle ends")
	var accelerated_again: Dictionary = player.call("weapon_time_interaction_context")
	_suite.assert_true(
		int(accelerated_again.get("accelerate_generation", 0)) > accelerate_generation,
		"reactivated Accelerate advances its source generation monotonically"
	)
	player.cancel_active_time_effects(&"test_reset")
	await _free_player(player)


func _test_rift_context_tracks_live_spatial_generations() -> void:
	var player := await _spawn_player(["rift", "rewind"])
	var time_manager: Node = player.get_node("TimeManager")
	time_manager.time_rift_cost = 0.0
	time_manager.time_rift_cooldown = 0.0
	time_manager.time_rift_duration = 10.0
	time_manager.time_rift_radius = 104.0
	player.global_position = Vector2(64.0, 32.0)

	_suite.assert_true(player.try_action(&"time_slot_1"), "Rift commits for the weapon context fixture")
	var first: Dictionary = player.call("weapon_time_interaction_context")
	var first_generation := int(first.get("rift_generation", 0))
	_suite.assert_true(bool(first.get("rift_active", false)), "weapon context reports active Rift")
	_suite.assert_true(first_generation > 0, "active Rift exposes a positive source generation")
	var first_descriptors: Array = first.get("active_rifts", [])
	_suite.assert_equal(first_descriptors.size(), 1, "one active Rift exposes one spatial descriptor")
	if first_descriptors.size() == 1:
		var first_descriptor := first_descriptors[0] as Dictionary
		_suite.assert_equal(int(first_descriptor.get("generation", 0)), first_generation, "Rift descriptor matches the active generation")
		_suite.assert_equal(first_descriptor.get("center"), Vector2(64.0, 32.0), "Rift descriptor exposes its committed center")
		_suite.assert_close(float(first_descriptor.get("radius", 0.0)), 104.0, "Rift descriptor exposes its committed radius")
	var first_rift: Node = (time_manager.get("_active_rifts") as Array)[0]

	_advance_time_cast(player)
	player.global_position = Vector2(192.0, 96.0)
	_suite.assert_true(player.try_action(&"time_slot_1"), "a second Rift can overlap the first")
	var second: Dictionary = player.call("weapon_time_interaction_context")
	var second_generation := int(second.get("rift_generation", 0))
	_suite.assert_true(second_generation > first_generation, "new Rift advances its source generation monotonically")
	var overlapping: Array = second.get("active_rifts", [])
	_suite.assert_equal(overlapping.size(), 2, "overlapping Rifts expose both descriptors")
	if overlapping.size() == 2:
		_suite.assert_equal(int((overlapping[0] as Dictionary).get("generation", 0)), first_generation, "Rift descriptors sort by generation")
		_suite.assert_equal(int((overlapping[1] as Dictionary).get("generation", 0)), second_generation, "newest Rift descriptor sorts last")
		_suite.assert_equal((overlapping[1] as Dictionary).get("center"), Vector2(192.0, 96.0), "each Rift descriptor keeps its own center")
	var active_rifts: Array = time_manager.get("_active_rifts") as Array
	var second_rift: Node = active_rifts[active_rifts.size() - 1]
	second_rift.call("cancel", false)

	var fallback: Dictionary = player.call("weapon_time_interaction_context")
	_suite.assert_true(bool(fallback.get("rift_active", false)), "ending the newest Rift preserves an older live source")
	_suite.assert_equal(int(fallback.get("rift_generation", 0)), first_generation, "Rift generation falls back to the remaining source")
	_suite.assert_equal((fallback.get("active_rifts", []) as Array).size(), 1, "ending one Rift removes only its descriptor")

	first_rift.call("_process", 11.0)
	var expired: Dictionary = player.call("weapon_time_interaction_context")
	_suite.assert_true(not bool(expired.get("rift_active", true)), "expired Rifts clear the active context")
	_suite.assert_equal(int(expired.get("rift_generation", -1)), 0, "expired Rifts expose no live generation")
	_suite.assert_equal((expired.get("active_rifts", []) as Array).size(), 0, "expired Rifts remove every descriptor")

	_advance_time_cast(player)
	_suite.assert_true(player.try_action(&"time_slot_1"), "Rift can reactivate after every prior source expires")
	var reactivated: Dictionary = player.call("weapon_time_interaction_context")
	_suite.assert_true(int(reactivated.get("rift_generation", 0)) > second_generation, "reactivated Rift advances beyond prior generations")
	time_manager.reset_runtime_state()
	var reset_context: Dictionary = player.call("weapon_time_interaction_context")
	_suite.assert_true(not bool(reset_context.get("rift_active", true)), "runtime reset clears active Rift context")
	_suite.assert_equal(int(reset_context.get("rift_generation", -1)), 0, "runtime reset clears the live Rift generation")
	_suite.assert_equal((reset_context.get("active_rifts", []) as Array).size(), 0, "runtime reset clears every Rift descriptor")
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


func _advance_time_cast(player: Node) -> void:
	for _frame: int in range(12):
		player.advance_action_frame()
