extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var a = SeedServiceScript.derive_seed(123, &"draft", 1, 2, 3)
	var b = SeedServiceScript.derive_seed(123, &"draft", 1, 2, 3)
	suite.assert_equal(a, b, "same seed inputs are deterministic")
	suite.assert_true(a != SeedServiceScript.derive_seed(123, &"combat", 1, 2, 3), "channels are isolated")
	suite.assert_true(a != SeedServiceScript.derive_seed(123, &"draft", 1, 2, 4), "roll indexes are isolated")
	suite.assert_true(a != SeedServiceScript.derive_seed(123, &"draft", 2, 2, 3), "floor indexes are isolated")
	suite.assert_true(a != SeedServiceScript.derive_seed(123, &"draft", 1, 3, 3), "room indexes are isolated")
	suite.assert_equal(
		SeedServiceScript.make_rng(123, &"draft", 1, 2, 3).randi(),
		SeedServiceScript.make_rng(123, &"draft", 1, 2, 3).randi(),
		"derived RNG streams reproduce"
	)
	suite.assert_equal(
		SeedServiceScript.derive_seed(-123, &"draft", 1, 2, 3),
		SeedServiceScript.derive_seed(-123, &"draft", 1, 2, 3),
		"negative run seeds are deterministic"
	)
	suite.finish(get_tree())
