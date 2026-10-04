extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	var implementation = load("res://scripts/enemies/launch/hostile_action_contract.gd")
	suite.assert_true(implementation != null, "closed hostile action contract exists")
	if implementation == null:
		suite.finish(get_tree())
		return
	var valid: Dictionary = implementation.create(Fixtures.action(), "enemy")
	suite.assert_true(valid.get("ok", false), "authored paired-cone action accepts")
	if valid.get("ok", false):
		valid.definition.geometry[0].radius = 999.0
		suite.assert_equal(implementation.create(Fixtures.action(), "enemy").definition.geometry[0].radius, 29.0, "normalized actions are deeply isolated")
	for field: String in Fixtures.action():
		var missing := Fixtures.action()
		missing.erase(field)
		_assert_reject(suite, implementation, missing, "missing " + field)
	var unknown := Fixtures.action()
	unknown["script"] = "res://arbitrary.gd"
	_assert_reject(suite, implementation, unknown, "unknown root field")
	for field: String in ["warning_frames", "active_frames", "recovery_frames", "idle_frames", "cooldown_frames", "weight", "max_consecutive", "distance_min_px", "distance_max_px"]:
		var invalid := Fixtures.action()
		invalid[field] = true
		_assert_reject(suite, implementation, invalid, "Boolean cannot supply " + field)
	var fractional := Fixtures.action()
	fractional.warning_frames = 30.5
	_assert_reject(suite, implementation, fractional, "fractional frame rejects")
	var integral_json := Fixtures.action()
	integral_json.warning_frames = 30.0
	suite.assert_true(implementation.create(integral_json, "enemy").ok, "integral JSON numbers normalize to frames")
	var too_fast := Fixtures.action()
	too_fast.warning_frames = 22
	_assert_reject(suite, implementation, too_fast, "enemy minimum warning")
	too_fast = Fixtures.action()
	too_fast.recovery_frames = 14
	_assert_reject(suite, implementation, too_fast, "damaging enemy minimum recovery")
	var boss := Fixtures.action()
	boss.warning_frames = 25
	boss.recovery_frames = 20
	suite.assert_true(implementation.create(boss, "boss").ok, "final Boss warning floor accepts")
	boss.warning_frames = 24
	suite.assert_true(not implementation.create(boss, "boss").ok, "Boss warning floor rejects")
	var invalid_handler := Fixtures.action()
	var guardian_wall := Fixtures.action()
	guardian_wall.id = "guardian_stone_wall"
	guardian_wall.handler_id = "wall"
	guardian_wall.parameters = {"hit_points": 150.0, "lifetime_frames": 480, "gap_px": 48.0}
	suite.assert_true(implementation.create(guardian_wall, "boss").ok, "Guardian declared 150 HP wall passes closed action contract")
	guardian_wall.parameters.hit_points = 151.0
	suite.assert_true(not implementation.create(guardian_wall, "boss").ok, "Guardian wall rejects HP beyond authored bound")
	invalid_handler.handler_id = "eval_script"
	_assert_reject(suite, implementation, invalid_handler, "unsupported handler rejects")
	var invalid_parameters := Fixtures.action()
	invalid_parameters.parameters.script = "res://arbitrary.gd"
	_assert_reject(suite, implementation, invalid_parameters, "exact handler parameters")
	invalid_parameters = Fixtures.action()
	invalid_parameters.parameters.knockback_px = INF
	_assert_reject(suite, implementation, invalid_parameters, "nonfinite handler value")
	var invalid_geometry := Fixtures.action()
	invalid_geometry.geometry[0].radius = NAN
	_assert_reject(suite, implementation, invalid_geometry, "nonfinite geometry")
	invalid_geometry = Fixtures.action()
	invalid_geometry.geometry[0].origin_offset.z = 0
	_assert_reject(suite, implementation, invalid_geometry, "exact geometry vector")
	invalid_geometry = Fixtures.action()
	invalid_geometry.geometry[0].shape = "script_shape"
	_assert_reject(suite, implementation, invalid_geometry, "unsupported shape")
	var outside := Fixtures.action()
	outside.hit_schedule[0].offset_frame = outside.active_frames
	_assert_reject(suite, implementation, outside, "hit cannot occur after active interval")
	var duplicate := Fixtures.action()
	duplicate.hit_schedule.append(duplicate.hit_schedule[0].duplicate(true))
	_assert_reject(suite, implementation, duplicate, "duplicate hit index rejects")
	var reversed := Fixtures.action()
	reversed.distance_min_px = 30.0
	_assert_reject(suite, implementation, reversed, "reversed selection range")
	var empty_geometry := Fixtures.action()
	empty_geometry.geometry = []
	_assert_reject(suite, implementation, empty_geometry, "damaging action requires committed geometry")
	var blink := Fixtures.action()
	blink.handler_id = "blink"
	blink.parameters = {"travel_px": 48, "transit_frames": 8, "landing_warning_frames": 30}
	blink.hit_schedule[0].hit_index = blink.geometry.size()
	_assert_reject(suite, implementation, blink, "blink hit index must name its own frozen landing lane")
	suite.assert_equal(implementation.handler_ids().size(), 15, "closed fifteen handler families")
	suite.finish(get_tree())


func _assert_reject(suite: RefCounted, implementation: Script, value: Dictionary, label: String) -> void:
	var result: Dictionary = implementation.create(value, "enemy")
	suite.assert_true(not result.get("ok", false), label)
	suite.assert_true(result.get("context", {}) is Dictionary, label + " has typed context")
	suite.assert_true(not result.has("definition"), label + " has no usable partial definition")
