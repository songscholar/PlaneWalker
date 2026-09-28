extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_idle_time_stop_invents_no_slam()
	await _test_windup_time_stop_delays_action_and_recovery()
	await _test_recovery_time_stop_extends_only_recovery()
	await _test_slam_excludes_melee_and_special_patterns()
	_suite.finish(get_tree())


func _test_idle_time_stop_invents_no_slam() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	var health: Node = subject["health"]
	var slam_count := [0]
	health.damaged.connect(func(_amount: float, _current_hp: float) -> void: slam_count[0] += 1)

	boss.apply_time_stop(0.2)
	boss.set_physics_process(true)
	await get_tree().create_timer(0.25).timeout

	var snapshot: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(snapshot["action"], "NONE", "idle time stop invents no action")
	_suite.assert_equal(snapshot["phase"], "IDLE", "idle time stop keeps the boss idle")
	_suite.assert_equal(slam_count[0], 0, "idle time stop resolves no slam")
	await _cleanup_subject(subject)


func _test_windup_time_stop_delays_action_and_recovery() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	boss.force_slam_for_test()
	var before: Dictionary = _boss_snapshot(boss)

	boss.apply_time_stop(0.2)
	var delayed: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(delayed["action"], "SLAM", "windup time stop preserves the committed slam")
	_suite.assert_equal(delayed["phase"], "WINDUP", "windup time stop keeps the current phase")
	_suite.assert_true(float(delayed["remaining"]) > float(before["remaining"]), "windup time stop delays the current action")

	boss.set_physics_process(true)
	await get_tree().create_timer(float(delayed["remaining"]) + 0.05).timeout
	var recovery: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(recovery["action"], "SLAM", "slam remains the active action through recovery")
	_suite.assert_equal(recovery["phase"], "RECOVERY", "slam enters one recovery phase")
	_suite.assert_true(float(recovery["remaining"]) >= boss.slam_recovery + 0.68, "resisted time stop adds at least 0.8 seconds of recovery opportunity")
	await _cleanup_subject(subject)


func _test_recovery_time_stop_extends_only_recovery() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	var health: Node = subject["health"]
	var slam_count := [0]
	health.damaged.connect(func(_amount: float, _current_hp: float) -> void: slam_count[0] += 1)

	boss.force_slam_for_test()
	boss.set_physics_process(true)
	await get_tree().create_timer(boss.slam_windup + 0.05).timeout
	boss.set_physics_process(false)
	var before: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(before["phase"], "RECOVERY", "test reaches slam recovery")

	boss.apply_time_stop(0.2)
	var delayed: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(delayed["action"], "SLAM", "recovery time stop preserves the current action")
	_suite.assert_equal(delayed["phase"], "RECOVERY", "recovery time stop does not create windup")
	_suite.assert_true(float(delayed["remaining"]) >= float(before["remaining"]) + 0.79, "recovery time stop extends the current recovery by at least 0.8 seconds")

	boss.set_physics_process(true)
	await get_tree().create_timer(float(delayed["remaining"]) + 0.12).timeout
	var completed: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(completed["action"], "NONE", "extended recovery completes without another slam")
	_suite.assert_equal(completed["phase"], "IDLE", "extended recovery returns to idle")
	_suite.assert_equal(slam_count[0], 1, "recovery time stop resolves no duplicate slam")
	await _cleanup_subject(subject)


func _test_slam_excludes_melee_and_special_patterns() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	var health: Node = subject["health"]
	var damage_count := [0]
	health.damaged.connect(func(_amount: float, _current_hp: float) -> void: damage_count[0] += 1)

	boss.force_slam_for_test()
	boss._attack_cooldown_remaining = 0.0
	boss._pattern_timer = 0.0
	boss._special_index = 1
	var projectile_count_before := _hostile_projectile_count(boss)
	boss.set_physics_process(true)
	await get_tree().create_timer(0.12).timeout

	var snapshot: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(snapshot["action"], "SLAM", "slam remains the sole committed action")
	_suite.assert_equal(snapshot["phase"], "WINDUP", "slam is still winding up during mutual exclusion check")
	_suite.assert_equal(damage_count[0], 0, "slam windup blocks basic melee damage")
	_suite.assert_equal(_hostile_projectile_count(boss), projectile_count_before, "slam windup blocks radial projectile patterns")
	_suite.assert_equal(boss._special_index, 1, "blocked special pattern is not consumed")
	await _cleanup_subject(subject)


func _spawn_subject() -> Dictionary:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	add_child(player)
	player.global_position = Vector2(48.0, 0.0)

	var boss := BossScene.instantiate()
	boss.set_physics_process(false)
	add_child(boss)
	boss.set_physics_process(false)
	boss.global_position = Vector2.ZERO
	boss.move_speed = 0.0
	boss._pattern_timer = 99.0
	boss._attack_cooldown_remaining = 99.0
	await get_tree().process_frame
	return {
		"player": player,
		"boss": boss,
		"health": player.get_node("HealthComponent"),
	}


func _cleanup_subject(subject: Dictionary) -> void:
	var boss: Node = subject["boss"]
	var player: Node = subject["player"]
	if is_instance_valid(boss):
		boss.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _hostile_projectile_count(boss: Node) -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("time_stoppable"):
		if node != boss and node.get_script() != null and str(node.get_script().resource_path).ends_with("enemy_projectile.gd"):
			count += 1
	return count


func _boss_snapshot(boss: Node) -> Dictionary:
	if boss.has_method("get_boss_ui_snapshot"):
		return boss.get_boss_ui_snapshot()
	_suite.assert_true(false, "boss exposes an action snapshot")
	return {
		"action": "MISSING",
		"phase": "MISSING",
		"remaining": 0.0,
	}
