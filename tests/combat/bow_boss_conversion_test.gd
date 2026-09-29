extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_control_conversion_rejects_committed_windup()
	await _test_control_conversion_extends_only_recovery_and_exposure()
	await _test_rift_state_has_a_public_read_boundary()
	_suite.finish(get_tree())


func _test_control_conversion_rejects_committed_windup() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	boss.force_slam_for_test()
	_suite.assert_equal(boss.get_boss_ui_snapshot().get("action"), "SLAM", "Boss commits a slam for the Bow conversion fixture")
	boss.apply_time_rift(&"pre_exposed_windup", 0.45)
	_suite.assert_true(bool(boss.get_boss_ui_snapshot().get("exposed", false)), "fixture pre-exposes the Boss without leaving WINDUP")
	_suite.assert_equal(boss.get_boss_ui_snapshot().get("phase"), "WINDUP", "pre-exposure preserves the committed WINDUP phase")
	var before: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_true(
		not bool(boss.call(
			"apply_weapon_control_conversion",
			&"bow_temporal:windup",
			12,
			30,
			15.0
		)),
			"Bow control conversion cannot affect a committed Boss windup even when pre-exposed"
		)
	_suite.assert_equal(boss.get_boss_ui_snapshot(), before, "rejected conversion changes no Boss action state")
	boss.clear_time_rift(&"pre_exposed_windup")
	await _cleanup_subject(subject)


func _test_control_conversion_extends_only_recovery_and_exposure() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	boss.force_slam_for_test()
	_suite.assert_equal(boss.get_boss_ui_snapshot().get("action"), "SLAM", "Boss commits a slam before entering recovery")
	_suite.assert_true(boss.advance_action_for_test(boss.slam_windup + 0.01), "Boss action advances into recovery")
	var before: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_equal(before.get("phase"), "RECOVERY", "fixture reaches Boss recovery")
	_suite.assert_true(bool(boss.call(
		"apply_weapon_control_conversion",
		&"bow_temporal:recovery",
		12,
		30,
		15.0
	)), "Bow control conversion is accepted during Boss recovery")
	var converted: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_close(
		float(converted.get("remaining", 0.0)),
		float(before.get("remaining", 0.0)) + 12.0 / 60.0,
		"recovery conversion adds the declared bounded frame duration"
	)
	_suite.assert_true(bool(converted.get("exposed", false)), "recovery conversion opens a readable exposure window")
	_suite.assert_true(
		not bool(boss.call(
			"apply_weapon_control_conversion",
			&"bow_temporal:recovery",
			12,
			30,
			15.0
		)),
		"the same source cannot stack recovery or poise twice"
	)
	_suite.assert_equal(boss.get_boss_ui_snapshot(), converted, "duplicate source rejection is atomic")
	var control_before_complete: Dictionary = boss.get_weapon_control_snapshot_for_test()
	_suite.assert_true(float(control_before_complete.get("poise", 0.0)) > 0.0, "Bow conversion contributes persistent Boss poise")
	_suite.assert_true(
		boss.advance_action_for_test(float(converted.get("remaining", 0.0)) + 0.01),
		"Boss recovery completes without discarding weapon control state"
	)
	var completed: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_equal(completed.get("phase"), "IDLE", "Boss returns to idle after converted recovery")
	_suite.assert_true(bool(completed.get("exposed", false)), "declared exposure survives the action boundary until its own expiry")
	_suite.assert_close(
		float(boss.get_weapon_control_snapshot_for_test().get("poise", 0.0)),
		float(control_before_complete.get("poise", 0.0)),
		"action completion does not erase accumulated weapon poise"
	)
	await get_tree().create_timer(0.52).timeout
	_suite.assert_true(not bool(boss.get_boss_ui_snapshot().get("exposed", true)), "weapon exposure clears on its declared source lifetime")
	await _cleanup_subject(subject)


func _test_rift_state_has_a_public_read_boundary() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	_suite.assert_true(boss.has_method("is_time_rifted"), "enemies expose Rift state without private-field reads")
	if boss.has_method("is_time_rifted"):
		_suite.assert_true(not bool(boss.call("is_time_rifted")), "Boss begins outside a Rift")
		boss.apply_time_rift(&"bow_rift:test", 0.45)
		_suite.assert_true(bool(boss.call("is_time_rifted")), "Boss reports an active Rift source")
		boss.clear_time_rift(&"bow_rift:test")
		_suite.assert_true(not bool(boss.call("is_time_rifted")), "clearing the source clears public Rift state")
	await _cleanup_subject(subject)


func _spawn_subject() -> Dictionary:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
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
	return {"player": player, "boss": boss}


func _cleanup_subject(subject: Dictionary) -> void:
	for key: String in ["boss", "player"]:
		var node: Node = subject[key]
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
