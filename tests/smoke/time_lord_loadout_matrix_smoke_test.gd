extends Node

const MatrixRunnerScript := preload("res://tests/smoke/character_weapon_time_matrix_runner.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	await MatrixRunnerScript.new().run(self, suite, &"time_lord")
	suite.finish(get_tree())
