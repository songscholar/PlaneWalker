extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")

const ACTION_SHAPES := {
	"MELEE": "cone",
	"SLAM": "circle",
	"RADIAL": "ring",
	"AIMED": "line",
	"SUMMON": "summon_slots",
	"TIME_CRACK": "target_circle",
}

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_action_definitions_are_complete_and_readable()
	for action_name: String in ACTION_SHAPES.keys():
		await _test_action_contract(action_name)
	await _test_time_stop_extends_each_committed_phase()
	_suite.finish(get_tree())


func _test_action_definitions_are_complete_and_readable() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	if not boss.has_method("get_action_definitions_for_test"):
		_suite.assert_true(false, "boss exposes its authoritative action definitions")
		await _cleanup_subject(subject)
		return
	var definitions: Dictionary = boss.get_action_definitions_for_test()
	_suite.assert_equal(definitions.size(), ACTION_SHAPES.size(), "the authoritative table defines exactly six boss actions")
	for action_name: String in ACTION_SHAPES.keys():
		_suite.assert_true(definitions.has(action_name), "%s has an authoritative definition" % action_name)
		if not definitions.has(action_name):
			continue
		var definition: Dictionary = definitions[action_name]
		_suite.assert_equal(str(definition.get("id", "")), action_name, "%s keeps a stable action ID" % action_name)
		_suite.assert_true(float(definition.get("windup", 0.0)) > 0.0, "%s has positive windup" % action_name)
		_suite.assert_true(float(definition.get("recovery", 0.0)) > 0.0, "%s has positive recovery" % action_name)
		_suite.assert_equal(str(definition.get("shape", "")), ACTION_SHAPES[action_name], "%s uses its distinct telegraph shape" % action_name)
	await _cleanup_subject(subject)


func _test_action_contract(action_name: String) -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	var player: Node2D = subject["player"]
	var health: Node = subject["health"]
	if not _has_test_contract(boss):
		await _cleanup_subject(subject)
		return

	var damage_count := [0]
	health.damaged.connect(func(_amount: float, _current_hp: float) -> void: damage_count[0] += 1)
	boss._attack_cooldown_remaining = 0.0
	var effects_before := _effect_count(action_name, subject, damage_count[0])
	_suite.assert_true(boss.force_action_for_test(action_name), "%s enters windup" % action_name)
	var definition: Dictionary = boss.get_action_definitions_for_test()[action_name]
	var windup := float(definition["windup"])
	var recovery := float(definition["recovery"])
	var telegraph: Dictionary = boss.get_active_telegraph_snapshot_for_test()
	var committed: Dictionary = boss.get_committed_action_snapshot_for_test()

	_suite.assert_equal(telegraph.get("action_id", ""), action_name, "%s telegraph exposes the stable action ID" % action_name)
	_suite.assert_equal(telegraph.get("shape", ""), ACTION_SHAPES[action_name], "%s telegraph exposes its proxy shape" % action_name)
	_suite.assert_true(bool(telegraph.get("visible", false)), "%s telegraph is visible during windup" % action_name)
	_suite.assert_close(float(telegraph.get("remaining", 0.0)), windup, "%s telegraph uses the action clock" % action_name, 0.001)

	var locked_direction: Vector2 = committed.get("aim_direction", Vector2.ZERO)
	var locked_target: Vector2 = committed.get("target_point", Vector2.ZERO)
	var locked_slots: Array = committed.get("summon_slots", [])
	if action_name in ["AIMED", "TIME_CRACK", "SUMMON"]:
		player.global_position = Vector2(-24.0, 96.0)
		var after_move: Dictionary = boss.get_committed_action_snapshot_for_test()
		_suite.assert_equal(after_move.get("aim_direction", Vector2.ZERO), locked_direction, "%s keeps its committed aim direction" % action_name)
		_suite.assert_equal(after_move.get("target_point", Vector2.ZERO), locked_target, "%s keeps its committed target point" % action_name)
		_suite.assert_equal(after_move.get("summon_slots", []), locked_slots, "%s keeps its committed summon slots" % action_name)

	boss.advance_action_for_test(windup * 0.5)
	_suite.assert_equal(_effect_count(action_name, subject, damage_count[0]), effects_before, "%s resolves no effect during windup" % action_name)
	_suite.assert_equal(boss.get_action_resolution_count_for_test(action_name), 0, "%s has no early resolution callback" % action_name)
	boss.advance_action_for_test(windup * 0.5 + 0.001)
	var recovery_snapshot: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_equal(recovery_snapshot["action"], action_name, "%s stays committed through recovery" % action_name)
	_suite.assert_equal(recovery_snapshot["phase"], "RECOVERY", "%s enters recovery after one resolution" % action_name)
	_suite.assert_equal(boss.get_action_resolution_count_for_test(action_name), 1, "%s resolves exactly once at the windup boundary" % action_name)
	_suite.assert_true(_effect_count(action_name, subject, damage_count[0]) > effects_before, "%s produces its gameplay effect at the boundary" % action_name)
	_suite.assert_true(not bool(boss.get_active_telegraph_snapshot_for_test().get("visible", true)), "%s clears its telegraph before recovery" % action_name)
	_assert_committed_output(action_name, subject, locked_direction, locked_target, locked_slots)

	_suite.assert_true(not boss.force_action_for_test("SLAM"), "%s recovery blocks replacement actions" % action_name)
	boss.advance_action_for_test(recovery + 0.001)
	var completed: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_equal(completed["action"], "NONE", "%s returns to idle after recovery" % action_name)
	_suite.assert_equal(completed["phase"], "IDLE", "%s clears the shared phase after recovery" % action_name)
	boss.advance_action_for_test(10.0)
	_suite.assert_equal(boss.get_action_resolution_count_for_test(action_name), 1, "%s cannot resolve twice after completion" % action_name)
	await _cleanup_subject(subject)


func _test_time_stop_extends_each_committed_phase() -> void:
	for action_name: String in ACTION_SHAPES.keys():
		var subject: Dictionary = await _spawn_subject()
		var boss: Node = subject["boss"]
		if not _has_test_contract(boss):
			await _cleanup_subject(subject)
			return
		boss._attack_cooldown_remaining = 0.0
		_suite.assert_true(boss.force_action_for_test(action_name), "%s starts for time-stop coverage" % action_name)
		var before_windup: Dictionary = boss.get_boss_ui_snapshot()
		boss.apply_time_stop(0.4)
		var delayed_windup: Dictionary = boss.get_boss_ui_snapshot()
		_suite.assert_equal(delayed_windup["action"], action_name, "%s windup time stop preserves the action" % action_name)
		_suite.assert_equal(delayed_windup["phase"], "WINDUP", "%s windup time stop preserves the phase" % action_name)
		_suite.assert_true(float(delayed_windup["remaining"]) > float(before_windup["remaining"]), "%s windup time stop extends only the active clock" % action_name)

		boss.advance_action_for_test(float(delayed_windup["remaining"]) + 0.001)
		var before_recovery: Dictionary = boss.get_boss_ui_snapshot()
		boss.apply_time_stop(0.4)
		var delayed_recovery: Dictionary = boss.get_boss_ui_snapshot()
		_suite.assert_equal(delayed_recovery["action"], action_name, "%s recovery time stop preserves the action" % action_name)
		_suite.assert_equal(delayed_recovery["phase"], "RECOVERY", "%s recovery time stop preserves the phase" % action_name)
		_suite.assert_true(float(delayed_recovery["remaining"]) > float(before_recovery["remaining"]), "%s recovery time stop extends the active clock" % action_name)
		_suite.assert_equal(boss.get_action_resolution_count_for_test(action_name), 1, "%s time stop creates no duplicate resolution" % action_name)
		await _cleanup_subject(subject)


func _has_test_contract(boss: Node) -> bool:
	var complete := (
		boss.has_method("force_action_for_test")
		and boss.has_method("get_action_definitions_for_test")
		and boss.has_method("get_active_telegraph_snapshot_for_test")
		and boss.has_method("get_committed_action_snapshot_for_test")
		and boss.has_method("get_action_resolution_count_for_test")
		and boss.has_method("advance_action_for_test")
	)
	_suite.assert_true(complete, "boss exposes the deterministic Wave 4B action test contract")
	return complete


func _assert_committed_output(action_name: String, subject: Dictionary, locked_direction: Vector2, locked_target: Vector2, locked_slots: Array) -> void:
	var boss: Node = subject["boss"]
	match action_name:
		"AIMED":
			var projectiles := _hostile_projectiles(boss)
			_suite.assert_true(not projectiles.is_empty(), "aimed burst spawns committed projectiles")
			if not projectiles.is_empty():
				var middle: Node = projectiles[projectiles.size() / 2]
				_suite.assert_true(middle.direction.normalized().dot(locked_direction.normalized()) > 0.999, "aimed burst uses the direction captured at action start")
		"SUMMON":
			var positions := _summoned_fragment_positions(boss)
			_suite.assert_equal(positions.size(), locked_slots.size(), "summon creates each committed slot exactly once")
			for slot: Vector2 in locked_slots:
				_suite.assert_true(_contains_close_point(positions, slot), "summon resolves at its captured slot")
		"TIME_CRACK":
			var hazards := get_tree().get_nodes_in_group("boss_hazards")
			_suite.assert_true(not hazards.is_empty(), "time crack creates its committed hazard")
			if not hazards.is_empty():
				_suite.assert_true((hazards.back() as Node2D).global_position.distance_to(locked_target) < 0.01, "time crack resolves at the target point captured at action start")


func _effect_count(action_name: String, subject: Dictionary, damage_count: int) -> int:
	match action_name:
		"MELEE", "SLAM":
			return damage_count
		"RADIAL", "AIMED":
			return _hostile_projectiles(subject["boss"]).size()
		"SUMMON":
			return _summoned_fragment_positions(subject["boss"]).size()
		"TIME_CRACK":
			return get_tree().get_nodes_in_group("boss_hazards").size()
	return 0


func _hostile_projectiles(boss: Node) -> Array[Node]:
	var result: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group("time_stoppable"):
		if node != boss and node.get_script() != null and str(node.get_script().resource_path).ends_with("enemy_projectile.gd"):
			result.append(node)
	return result


func _summoned_fragment_positions(boss: Node) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node != boss and node is Node2D and str(node.get_script().resource_path).ends_with("enemy_chaser.gd"):
			result.append((node as Node2D).global_position)
	return result


func _contains_close_point(points: Array[Vector2], expected: Vector2) -> bool:
	for point: Vector2 in points:
		if point.distance_to(expected) < 0.01:
			return true
	return false


func _spawn_subject() -> Dictionary:
	var host := Node2D.new()
	add_child(host)
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	host.add_child(player)
	player.global_position = Vector2(48.0, 0.0)

	var boss := BossScene.instantiate()
	boss.set_physics_process(false)
	host.add_child(boss)
	boss.set_physics_process(false)
	boss.global_position = Vector2.ZERO
	boss.move_speed = 0.0
	boss._phase = 3
	boss._pattern_timer = 99.0
	boss._attack_cooldown_remaining = 99.0
	await get_tree().process_frame
	return {
		"host": host,
		"player": player,
		"boss": boss,
		"health": player.get_node("HealthComponent"),
	}


func _cleanup_subject(subject: Dictionary) -> void:
	var host: Node = subject["host"]
	if is_instance_valid(host):
		host.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
