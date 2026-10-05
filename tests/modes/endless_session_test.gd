extends Node

const Suite := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	var suite := Suite.new()
	var path := "res://scripts/modes/endless_session.gd"
	suite.assert_true(ResourceLoader.exists(path), "Endless requires closed cycle state and deterministic budgets")
	if not ResourceLoader.exists(path):
		suite.finish(get_tree())
		return
	var mode: Script = load(path)
	var empty: Dictionary = mode.empty("f".repeat(64))
	suite.assert_true(mode.valid(empty, "owner"), "exact idle endless session validates")
	var unknown := empty.duplicate(true)
	unknown["foreign"] = true
	suite.assert_true(not mode.valid(unknown, "owner"), "foreign session fields refuse")
	suite.assert_equal(mode.cycle_seed(20261005, 1), mode.cycle_seed(20261005, 1), "cycle RNG repeats exactly")
	suite.assert_true(mode.cycle_seed(20261005, 1) != mode.cycle_seed(20261005, 0), "cycle channels vary deterministic layouts")
	suite.assert_equal(mode.scaling(0), {"hp_multiplier": 1.0, "damage_multiplier": 1.0}, "first native cycle preserves authored difficulty")
	suite.assert_equal(mode.scaling(31), {"hp_multiplier": 3.0, "damage_multiplier": 2.0}, "last cycle respects health/damage ceilings")
	suite.assert_equal(mode.scaling(100000), mode.scaling(31), "long Endless play continues with saturated bounded scaling")
	suite.assert_true(mode.scaling(-1).is_empty(), "negative cycles refuse")
	suite.finish(get_tree())
