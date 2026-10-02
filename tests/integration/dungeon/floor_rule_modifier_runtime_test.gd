extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


class RewindProbe:
	extends Node

	func has_snapshot() -> bool:
		return true

	func prepare_rewind_transaction(_pre_return_position: Variant = null) -> Dictionary:
		return {"ticket": 1}

	func commit_rewind_transaction(_ticket: Dictionary) -> bool:
		return true

	func rollback_rewind_transaction(_ticket: Dictionary) -> bool:
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_floor_rule_modifier_apply_remove_and_restore()
	await _test_floor_rule_time_cost_multiplier_affects_all_abilities()
	_suite.finish(get_tree())


func _test_floor_rule_modifier_apply_remove_and_restore() -> void:
	var player := await _spawn_player()
	_suite.assert_true(
		player.has_method("floor_rule_effect_snapshot"),
		"Player exposes a transient floor-rule effect snapshot"
	)
	_suite.assert_true(
		player.has_method("apply_floor_rule_modifier"),
		"Player exposes authoritative floor-rule modifier application"
	)
	_suite.assert_true(
		player.has_method("restore_floor_rule_effect_snapshot"),
		"Player exposes atomic floor-rule modifier restoration"
	)
	if not (
		player.has_method("floor_rule_effect_snapshot")
		and player.has_method("apply_floor_rule_modifier")
		and player.has_method("restore_floor_rule_effect_snapshot")
	):
		await _free_player(player)
		return

	var initial: Dictionary = player.call("floor_rule_effect_snapshot")
	_suite.assert_true(not initial.is_empty(), "floor-rule snapshot is complete")
	_suite.assert_true(player.call(
		"apply_floor_rule_modifier",
		&"floor_rule_v1:temporal:room_a",
		&"temporal_distortion",
		&"apply",
		{"movement_multiplier": 0.85, "time_cost_multiplier": 1.15}
	), "temporal distortion modifier applies")
	_suite.assert_close(
		player.get_action_movement_multiplier(),
		0.85,
		"temporal distortion slows player movement"
	)
	var manager: Node = player.get_node("TimeManager")
	_suite.assert_close(
		float(manager.call("floor_rule_cost_multiplier")),
		1.15,
		"temporal distortion increases all time costs"
	)

	var temporal_snapshot: Dictionary = player.call("floor_rule_effect_snapshot")
	_suite.assert_true(player.call(
		"apply_floor_rule_modifier",
		&"floor_rule_v1:collapse:room_a",
		&"collapsing_plane_zone_lock",
		&"apply",
		{"zone_locked": true, "safe_area_required": true}
	), "collapsing-plane zone lock applies")
	_suite.assert_close(
		player.get_action_movement_multiplier(),
		0.0,
		"zone lock blocks movement while active"
	)
	_suite.assert_true(player.call(
		"apply_floor_rule_modifier",
		&"floor_rule_v1:collapse:room_a",
		&"collapsing_plane_zone_lock",
		&"remove",
		{}
	), "collapsing-plane zone lock removes")
	_suite.assert_equal(
		player.call("floor_rule_effect_snapshot"),
		temporal_snapshot,
		"removing one source preserves unrelated floor-rule modifiers exactly"
	)

	var malformed := temporal_snapshot.duplicate(true)
	malformed["modifiers"] = {"broken": {"movement_multiplier": -1.0}}
	_suite.assert_true(
		not bool(player.call("restore_floor_rule_effect_snapshot", malformed)),
		"malformed floor-rule restore is rejected"
	)
	_suite.assert_equal(
		player.call("floor_rule_effect_snapshot"),
		temporal_snapshot,
		"malformed restore rejection preserves the exact modifier snapshot"
	)
	_suite.assert_true(
		player.call("restore_floor_rule_effect_snapshot", initial),
		"initial floor-rule modifier snapshot restores"
	)
	_suite.assert_close(player.get_action_movement_multiplier(), 1.0, "restore clears movement modifier")
	_suite.assert_close(float(manager.call("floor_rule_cost_multiplier")), 1.0, "restore clears time-cost modifier")
	await _free_player(player)


func _test_floor_rule_time_cost_multiplier_affects_all_abilities() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	_suite.assert_true(
		manager.has_method("set_floor_rule_cost_multiplier"),
		"TimeManager exposes the transient floor-rule cost multiplier"
	)
	_suite.assert_true(
		manager.has_method("floor_rule_cost_multiplier"),
		"TimeManager exposes the active floor-rule cost multiplier"
	)
	if not (
		manager.has_method("set_floor_rule_cost_multiplier")
		and manager.has_method("floor_rule_cost_multiplier")
	):
		await _free_player(player)
		return

	manager.time_stop_cost = 10.0
	manager.rewind_cost = 20.0
	manager.time_rift_cost = 30.0
	manager.time_accelerate_cost = 40.0
	_suite.assert_true(manager.call("set_floor_rule_cost_multiplier", 1.25), "floor-rule time cost multiplier installs")

	var stop: Dictionary = manager.call(
		"_prepare_time_action_settlement", &"stop", {}, {}, player, player.current_run_id()
	)
	var rift: Dictionary = manager.call(
		"_prepare_time_action_settlement",
		&"rift",
		{"position": Vector2.ZERO},
		{},
		player,
		player.current_run_id()
	)
	var accelerate: Dictionary = manager.call(
		"_prepare_time_action_settlement", &"accelerate", {}, {}, player, player.current_run_id()
	)
	_suite.assert_close(float(stop.get("cost", -1.0)), 12.5, "Stop prepare uses floor-rule cost")
	_suite.assert_close(float(rift.get("cost", -1.0)), 37.5, "Rift prepare uses floor-rule cost")
	_suite.assert_close(float(accelerate.get("cost", -1.0)), 50.0, "Accelerate prepare uses floor-rule cost")

	var health: Node = player.get_node("HealthComponent")
	health.call("configure_run", player.current_run_id())
	var rewind: Dictionary = manager.prepare_gameplay_rewind_settlement_context()
	_suite.assert_close(float(rewind.get("cost", -1.0)), 25.0, "Rewind settlement uses floor-rule cost")

	manager.energy = 12.49
	_suite.assert_true(not manager.can_time_stop(), "Stop live guard rejects energy below floor-rule cost")
	manager.energy = 12.5
	_suite.assert_true(manager.can_time_stop(), "Stop live guard accepts the exact floor-rule cost")
	var recorder := RewindProbe.new()
	manager.energy = 24.99
	_suite.assert_true(not manager.can_rewind(recorder), "Rewind live guard rejects energy below floor-rule cost")
	manager.energy = 25.0
	_suite.assert_true(manager.can_rewind(recorder), "Rewind live guard accepts the exact floor-rule cost")
	manager.energy = 37.49
	_suite.assert_true(not manager.can_time_rift(Vector2.ZERO), "Rift live guard rejects energy below floor-rule cost")
	manager.energy = 37.5
	_suite.assert_true(manager.can_time_rift(Vector2.ZERO), "Rift live guard accepts the exact floor-rule cost")
	manager.energy = 49.99
	_suite.assert_true(not manager.can_time_accelerate(), "Accelerate live guard rejects energy below floor-rule cost")
	manager.energy = 50.0
	_suite.assert_true(manager.can_time_accelerate(), "Accelerate live guard accepts the exact floor-rule cost")
	recorder.free()

	manager.reset_runtime_state(true)
	_suite.assert_close(float(manager.call("floor_rule_cost_multiplier")), 1.0, "runtime reset clears floor-rule cost")
	await _free_player(player)


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	player.reset_runtime_state()
	return player


func _free_player(player: Node) -> void:
	if not is_instance_valid(player):
		return
	player.reset_runtime_state()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
