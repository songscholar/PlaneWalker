extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	suite.assert_true(true, "true values pass")
	suite.assert_equal({"value": 3}, {"value": 3}, "dictionaries compare by value")
	suite.assert_close(0.3001, 0.3, "floats compare within tolerance", 0.001)
	var non_finite_suite = TestSuiteScript.new()
	non_finite_suite.assert_close(NAN, 0.0, "NaN must fail")
	non_finite_suite.assert_close(INF, INF, "infinity must fail")
	suite.assert_equal(non_finite_suite.failures.size(), 2, "non-finite numbers are rejected")
	suite.finish(get_tree())
