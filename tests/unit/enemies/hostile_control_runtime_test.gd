extends Node

const Suite := preload("res://tests/support/test_suite.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/enemies/launch/hostile_control_runtime.gd")
	suite.assert_true(implementation != null, "P15 fixed-frame hostile control runtime exists")
	if implementation != null:
		_test_source_lifetimes(implementation)
		_test_strict_restore_and_terminal_frames(implementation)
	suite.finish(get_tree())


func _configured(implementation: Script) -> RefCounted:
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure({"run_id": "run-p15", "hostile_source_id": "sentinel:a", "runtime_frame": 0}).ok, "control accepts stable identity")
	return runtime


func _test_source_lifetimes(implementation: Script) -> void:
	var runtime := _configured(implementation)
	suite.assert_true(runtime.add_source("stop:a", "stop", 3, 1.0), "Stop source installed")
	suite.assert_true(runtime.add_source("stop:b", "stop", 5, 1.0), "overlapping Stop source installed")
	suite.assert_true(not runtime.add_source("stop:a", "stop", 30, 1.0), "duplicate source cannot reset lifetime")
	suite.assert_true(runtime.add_source("rift:a", "rift", 4, 0.70), "Rift source installed")
	suite.assert_true(runtime.add_source("rift:b", "rift", 2, 0.20), "Rift clamps authored multiplier to floor")
	suite.assert_true(runtime.add_source("weak:a", "weakpoint", 2, 0.30), "weakpoint source installed")
	suite.assert_true(runtime.add_source("vulnerable:a", "vulnerability", 3, 0.40), "vulnerability installed")
	suite.assert_true(runtime.add_source("vulnerable:b", "vulnerability", 5, 0.25), "independent vulnerability installed")
	for frame: int in range(1, 3):
		var result: Dictionary = runtime.advance_frame(frame)
		suite.assert_true(result.ok and result.action_paused, "Stop pauses accepted action frame %d" % frame)
		suite.assert_equal(result.movement_multiplier, 0.40, "strongest Rift retains movement floor")
		suite.assert_equal(result.weakpoint_bonus, 0.30, "weakpoint has fixed accepted-frame lifetime")
	var third: Dictionary = runtime.advance_frame(3)
	suite.assert_equal(third.movement_multiplier, 0.70, "short Rift expires before next accepted frame")
	suite.assert_equal(third.weakpoint_bonus, 0.0, "weakpoint expires without wall-clock timer")
	suite.assert_equal(third.damage_taken_multiplier, 1.65, "different vulnerability sources combine")
	var fourth: Dictionary = runtime.advance_frame(4)
	suite.assert_true(fourth.action_paused, "second Stop remains after first expires")
	suite.assert_equal(fourth.damage_taken_multiplier, 1.25, "first vulnerability expires independently")
	runtime.advance_frame(5)
	var sixth: Dictionary = runtime.advance_frame(6)
	suite.assert_true(not sixth.action_paused, "last Stop expires on accepted clock")
	suite.assert_equal(sixth.movement_multiplier, 1.0, "Rift clears at fixed expiry")
	suite.assert_equal(sixth.damage_taken_multiplier, 1.0, "vulnerability clears at fixed expiry")


func _test_strict_restore_and_terminal_frames(implementation: Script) -> void:
	var runtime := _configured(implementation)
	runtime.add_source("stop:a", "stop", 3, 1.0)
	runtime.advance_frame(1)
	var before: Dictionary = runtime.snapshot()
	for bad_frame: int in [1, 0, 3]:
		suite.assert_true(not runtime.advance_frame(bad_frame).ok, "nonsequential control frame rejects")
		suite.assert_equal(runtime.snapshot(), before, "frame rejection preserves state")
	for field: String in ["unknown", "runtime_frame", "identity", "sources"]:
		var corrupted := before.duplicate(true)
		match field:
			"unknown": corrupted[field] = true
			"runtime_frame": corrupted[field] = -1
			"identity": corrupted[field].hostile_source_id = "sentinel:foreign"
			"sources": corrupted[field][0].expires_through_frame = 0
		suite.assert_true(not runtime.restore_snapshot(corrupted), "invalid control snapshot rejects %s" % field)
		suite.assert_equal(runtime.snapshot(), before, "invalid restore does not mutate")
	var restored := _configured(implementation)
	suite.assert_true(restored.restore_snapshot(JSON.parse_string(JSON.stringify(before))), "JSON checkpoint restores")
	suite.assert_equal(restored.advance_frame(2), runtime.advance_frame(2), "restored controls advance identically")
	suite.assert_true(runtime.cancel(&"room_exit"), "terminal cleanup accepted")
	suite.assert_equal(runtime.snapshot().sources, [], "terminal cleanup removes all sources")
	var terminal: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.advance_frame(3).ok, "terminal frame rejects")
	suite.assert_true(not runtime.add_source("late", "stop", 1, 1.0), "terminal source insertion rejects")
	suite.assert_equal(runtime.snapshot(), terminal, "terminal rejection preserves state")
