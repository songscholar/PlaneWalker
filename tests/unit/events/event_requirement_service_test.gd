extends Node

const EventRequirementServiceScript := preload(
	"res://scripts/events/event_requirement_service.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_all_requirement_operations(suite)
	_test_failures_are_stable_and_non_mutating(suite)
	_test_invalid_inputs_fail_closed(suite)
	suite.finish(get_tree())


func _test_all_requirement_operations(suite) -> void:
	var service = EventRequirementServiceScript.new()
	var requirements: Array = [
		{"operation": "resource_min", "arguments": {"resource": "time_shard", "amount": 2}},
		{"operation": "health_min", "arguments": {"amount": 30.0}},
		{"operation": "health_max_ratio", "arguments": {"ratio": 0.5}},
		{"operation": "gold_min", "arguments": {"amount": 100}},
		{"operation": "has_reward_tag", "arguments": {"tag": "arcane"}},
		{"operation": "lacks_curse", "arguments": {"curse_id": "curse_absent"}},
		{"operation": "narrative_flag", "arguments": {"flag": "met_archivist", "value": true}},
		{"operation": "floor_index_min", "arguments": {"value": 3}},
	]
	var evaluated: Dictionary = service.evaluate(requirements, _context())
	suite.assert_true(bool(evaluated.get("ok", false)), "all authored requirement operations evaluate")
	suite.assert_true(bool(evaluated.get("eligible", false)), "eligible context passes all requirements")
	suite.assert_equal(evaluated.get("failures"), [], "eligible context has no failure facts")
	suite.assert_equal(
		(evaluated.get("facts", []) as Array).size(),
		requirements.size(),
		"every requirement emits one deterministic fact"
	)


func _test_failures_are_stable_and_non_mutating(suite) -> void:
	var service = EventRequirementServiceScript.new()
	var requirements: Array = [
		{"operation": "resource_min", "arguments": {"resource": "time_shard", "amount": 3}},
		{"operation": "health_min", "arguments": {"amount": 50.0}},
		{"operation": "health_max_ratio", "arguments": {"ratio": 0.3}},
		{"operation": "gold_min", "arguments": {"amount": 101}},
		{"operation": "has_reward_tag", "arguments": {"tag": "void"}},
		{"operation": "lacks_curse", "arguments": {"curse_id": "curse_owned"}},
		{"operation": "narrative_flag", "arguments": {"flag": "met_archivist", "value": false}},
		{"operation": "floor_index_min", "arguments": {"value": 4}},
	]
	var context := _context()
	var before := context.duplicate(true)
	var first: Dictionary = service.evaluate(requirements, context)
	var second: Dictionary = service.evaluate(requirements, context)
	suite.assert_true(bool(first.get("ok", false)), "ineligible requirements still evaluate successfully")
	suite.assert_true(not bool(first.get("eligible", true)), "failed requirements disable the option")
	suite.assert_equal((first.get("failures", []) as Array).size(), 8, "all failures remain visible in source order")
	suite.assert_equal(first, second, "repeated evaluation is byte-identical")
	suite.assert_equal(context, before, "requirement evaluation never mutates context")


func _test_invalid_inputs_fail_closed(suite) -> void:
	var service = EventRequirementServiceScript.new()
	var cases: Array[Dictionary] = [
		{"label": "unknown operation", "requirements": [{"operation": "script", "arguments": {"value": 1}}]},
		{"label": "missing arguments", "requirements": [{"operation": "gold_min"}]},
		{"label": "negative minimum", "requirements": [{"operation": "gold_min", "arguments": {"amount": -1}}]},
		{"label": "invalid ratio", "requirements": [{"operation": "health_max_ratio", "arguments": {"ratio": 1.1}}]},
	]
	for case: Dictionary in cases:
		var result: Dictionary = service.evaluate(case["requirements"] as Array, _context())
		suite.assert_true(not bool(result.get("ok", true)), "%s fails closed" % str(case["label"]))
		suite.assert_equal(result.get("code"), &"INVALID_REQUIREMENT", "%s returns typed failure" % str(case["label"]))


func _context() -> Dictionary:
	return {
		"resources": {"time_shard": 2},
		"health": {"current": 40.0, "maximum": 100.0},
		"gold": 100,
		"reward_tags": ["arcane", "time"],
		"curse_ids": ["curse_owned"],
		"narrative_flags": {"met_archivist": true},
		"floor_index": 3,
	}
