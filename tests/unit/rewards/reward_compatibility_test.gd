extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const CompatibilityScript := preload("res://scripts/rewards/reward_compatibility.gd")


func _ready() -> void:
	var suite = TestSuiteScript.new()
	var sword := CompatibilityScript.context_for({"weapon_id": "sword"})
	var bow := CompatibilityScript.context_for({"weapon_id": "bow"})
	var bow_only := {"effects": {"bow_charge_rate_bonus": 0.2}}
	suite.assert_true(not CompatibilityScript.matches(bow_only, sword), "implicit bow effect rejects sword")
	suite.assert_true(CompatibilityScript.matches(bow_only, bow), "implicit bow effect allows bow")
	var sword_only := {"effects": {"heavy_damage_multiplier_bonus": 0.2}}
	suite.assert_true(CompatibilityScript.matches(sword_only, sword), "sword heavy effect allows sword")
	suite.assert_true(not CompatibilityScript.matches(sword_only, bow), "sword heavy effect rejects bow")
	var mixed := {"effects": {"bow_charge_rate_bonus": 0.2, "heavy_damage_multiplier_bonus": 0.2}}
	suite.assert_true(not CompatibilityScript.matches(mixed, sword), "every weapon effect must support selected weapon")
	suite.assert_true(not CompatibilityScript.matches(mixed, bow), "mixed incompatible effects fail closed")
	for weapon_id: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		var context := CompatibilityScript.context_for({"weapon_id": weapon_id})
		suite.assert_true(CompatibilityScript.matches({"effects": {"attack_multiplier": 1.1}}, context), "%s supports universal damage effect" % weapon_id)
		suite.assert_true(CompatibilityScript.matches({"effects": {"defense_bonus": 2.0}}, context), "%s supports player effect" % weapon_id)
	suite.assert_true(not CompatibilityScript.matches({"compatibility": {"weapon_ids": ["sword"]}, "effects": {"defense_bonus": 2.0}}, bow), "authored constraints remain binding")
	suite.assert_true(not CompatibilityScript.matches(bow_only, {}), "weapon effect requires a selected weapon")
	suite.assert_true(not CompatibilityScript.matches({"effects": {"unregistered_effect": 1}}, sword), "unknown effect fails closed")
	suite.finish(get_tree())
