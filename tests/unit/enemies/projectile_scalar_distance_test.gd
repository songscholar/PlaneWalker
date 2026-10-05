extends "res://tests/unit/enemies/launch_hostile_payload_runtime_test.gd"

const PayloadRuntime := preload("res://scripts/enemies/launch/launch_hostile_payload_runtime.gd")
const DIAGONAL := {"x": 0.5927259922027588, "y": 0.8054042458534241}


func _run() -> void:
	suite = Suite.new()
	_test_scalar_distance(false)
	_test_scalar_distance(true)
	suite.finish(get_tree())


func _rounded_diagonal_hit() -> Dictionary:
	var hit := _boss_hit("void_throne", "voidking_shard_projection", 2)
	hit.geometry[2].aim_direction = DIAGONAL.duplicate()
	return hit


func _test_scalar_distance(with_controls: bool) -> void:
	var hit := _rounded_diagonal_hit()
	var runtime := PayloadRuntime.new()
	suite.assert_true(runtime.configure("run-p15", int(hit.runtime_frame)), "rounded diagonal fixture configures the actual payload domain")
	var reserved := runtime.reserve_projectile(hit, BOUNDS, {})
	suite.assert_true(reserved.ok and runtime.can_restore_snapshot(runtime.snapshot()), "captured float32 normalized direction is a legal authored projectile")
	if not reserved.ok:
		return
	var first := int(hit.runtime_frame)
	var checkpoint := {}
	var moving_frames := 0
	var slowed_frames := 0
	for offset: int in range(1, 123 if with_controls else 121):
		if with_controls and offset == 25:
			suite.assert_true(runtime.add_control_source(reserved.id, "scalar-stop", "stop", 2, 1.0), "diagonal fixture accepts real bounded Stop")
		if with_controls and offset == 30:
			suite.assert_true(runtime.add_control_source(reserved.id, "scalar-rift", "rift", 4, 0.5), "diagonal fixture accepts real bounded Rift")
		var paused := with_controls and offset in [25, 26]
		moving_frames += int(not paused)
		slowed_frames += int(with_controls and offset >= 30 and offset <= 33)
		var advanced := runtime.advance_frame(first + offset, _observations())
		suite.assert_true(advanced.ok, "legal diagonal advances every sequential frame")
		var state := runtime.snapshot()
		suite.assert_true(runtime.can_restore_snapshot(state), "legal diagonal round-trips the strict cold snapshot validator at offset %d" % offset)
		if state.projectiles.is_empty():
			suite.assert_equal(moving_frames, 120, "finite projectile retires at its authored active lifetime")
			break
		var expected := (float(moving_frames) - float(slowed_frames) * 0.5) * 128.0 / 60.0
		suite.assert_true(absf(float(state.projectiles[0].travel) - expected) < 0.000000001, "travel follows the authored scalar integral independently of rounded direction")
		if offset == 70:
			checkpoint = state.duplicate(true)
		if offset == 93:
			var forged := state.duplicate(true)
			forged.projectiles[0].travel = 128.0 * float(forged.projectiles[0].age) / 60.0 + 0.001
			forged.projectiles[0].position = PayloadRuntime._trajectory_position(forged.projectiles[0].definition, float(forged.projectiles[0].travel))
			suite.assert_true(not runtime.can_restore_snapshot(forged), "trajectory-consistent forged overspeed still fails the unchanged strict bound")
			var restored := PayloadRuntime.new()
			restored.configure("run-p15", first)
			suite.assert_true(restored.restore_snapshot(checkpoint), "historical diagonal boundary restores through the full validator")
			for replay_frame: int in range(int(checkpoint.runtime_frame) + 1, first + offset + 1):
				suite.assert_true(restored.advance_frame(replay_frame, _observations()).ok, "historical diagonal replay advances deterministic native frames")
			suite.assert_equal(restored.snapshot(), state, "restored diagonal produces the exact same complete domain state")
	suite.assert_true(runtime.snapshot().projectiles.is_empty() and runtime.snapshot().zones.is_empty(), "diagonal flight leaves no fabricated persistent work")
