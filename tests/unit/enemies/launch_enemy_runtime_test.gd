extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")
var suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/enemies/launch/launch_enemy_runtime.gd")
	suite.assert_true(implementation != null, "P15 native sentinel domain runtime exists")
	if implementation != null:
		_test_sentinel_action_and_retreat(implementation)
		_test_stop_and_strict_checkpoint(implementation)
	suite.finish(get_tree())


static func definition() -> Dictionary:
	return {"id": "shattered_sentinel", "actor_kind": "enemy", "runtime_kind": "shattered_sentinel", "max_hp": 80.0, "defense": 0.0, "move_speed": 64.0, "actions": [Fixtures.action()]}


func _runtime(implementation: Script) -> RefCounted:
	var runtime: RefCounted = implementation.new()
	var identity := Fixtures.identity()
	identity["seed"] = 42
	suite.assert_true(runtime.configure(definition(), identity).ok, "sentinel runtime configures")
	return runtime


func _test_sentinel_action_and_retreat(implementation: Script) -> void:
	var runtime := _runtime(implementation)
	var unsupported := definition()
	unsupported.runtime_kind = "inert_generic_enemy"
	var rejected: RefCounted = implementation.new()
	var identity := Fixtures.identity()
	identity["seed"] = 42
	suite.assert_true(not rejected.configure(unsupported, identity).ok, "unsupported native mechanism rejects")
	suite.assert_true(runtime.request_action("shattered_sentinel.shield_sweep", Fixtures.context()).ok, "production runtime requests sweep")
	var hits: Array = []
	for frame: int in range(1, 39):
		var result: Dictionary = runtime.advance_frame(frame, Fixtures.context(frame))
		suite.assert_true(result.ok, "sentinel accepts sequential frame")
		hits.append_array(result.hit_facts)
	suite.assert_equal(hits.size(), 1, "paired sweep is one logical damage hit")
	suite.assert_equal(hits[0].attack_generation, 7, "sweep retains committed generation")
	suite.assert_equal(runtime.snapshot().mechanism_state.retreat_remaining_frames, 48, "sentinel begins bounded retreat after active sweep")
	var travelled := 0.0
	for frame: int in range(39, 87):
		var motion: Dictionary = runtime.motion_for_frame(frame, Fixtures.context(frame))
		suite.assert_true(motion.ok, "sentinel creates deterministic retreat motion")
		travelled += Vector2(motion.displacement.x, motion.displacement.y).length()
		runtime.advance_frame(frame, Fixtures.context(frame))
	suite.assert_true(is_equal_approx(travelled, 19.0), "retreat spans exactly nineteen pixels over forty-eight frames")
	suite.assert_equal(runtime.snapshot().mechanism_state.retreat_remaining_frames, 0, "retreat ends once")
	var before: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.advance_frame(86, Fixtures.context(86)).ok, "repeat frame rejects")
	suite.assert_equal(runtime.snapshot(), before, "repeat frame emits no domain mutation")


func _test_stop_and_strict_checkpoint(implementation: Script) -> void:
	var runtime := _runtime(implementation)
	runtime.request_action("shattered_sentinel.shield_sweep", Fixtures.context())
	suite.assert_true(runtime.add_control_source("stop:a", "stop", 3, 1.0), "sentinel receives fixed-frame Stop")
	for frame: int in range(1, 4):
		var result: Dictionary = runtime.advance_frame(frame, Fixtures.context(frame))
		suite.assert_true(result.action_paused and result.hit_facts.is_empty(), "Stop holds warning and emits no hit")
		suite.assert_equal(result.threat_extensions.size(), 2, "Stop extends both sweep primitives")
	var before: Dictionary = runtime.snapshot()
	var restored := _runtime(implementation)
	suite.assert_true(restored.restore_snapshot(before), "sentinel checkpoint restores")
	var corrupted := before.duplicate(true)
	corrupted.mechanism_state.retreat_remaining_frames = 49
	suite.assert_true(not restored.restore_snapshot(corrupted), "malformed mechanism checkpoint rejects")
	suite.assert_equal(restored.snapshot(), before, "malformed restore preserves checkpoint")
	for frame: int in range(4, 35):
		suite.assert_equal(restored.advance_frame(frame, Fixtures.context(frame)), runtime.advance_frame(frame, Fixtures.context(frame)), "restored sentinel produces same facts")
	suite.assert_true(runtime.cancel(&"room_exit").ok, "sentinel terminal cleanup accepted")
	suite.assert_true(not runtime.advance_frame(35, Fixtures.context(35)).ok, "cancelled sentinel cannot advance")
