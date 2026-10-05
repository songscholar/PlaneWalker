extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const RUNNER_PATH := "res://tests/support/p15_native_boss_matrix_runner.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(FileAccess.file_exists(RUNNER_PATH), "750 actual native Boss/loadout cases require an executable production scene runner")
	if FileAccess.file_exists(RUNNER_PATH):
		var script: Script = load(RUNNER_PATH)
		var runner: RefCounted = script.new()
		await runner.run(self, suite)
	suite.finish(get_tree())
