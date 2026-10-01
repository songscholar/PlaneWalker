extends Node

const DamageCalculatorScript := preload("res://scripts/combat/damage_calculator.gd")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_seeded_critical_is_repeatable()
	_test_frozen_critical_outcome_bypasses_rolls()
	_test_seeded_context_isolated_by_roll_index()
	_test_invalid_seeded_context_fails_closed()
	_test_source_has_no_global_randomness()
	_suite.finish(get_tree())


func _test_seeded_critical_is_repeatable() -> void:
	var info = _critical_fixture()
	var context := {"seed": 4127, "channel": &"damage_critical", "roll_index": 0}
	var first := DamageCalculatorScript.calculate(info, 0.0, context)
	var second := DamageCalculatorScript.calculate(info, 0.0, context)
	_suite.assert_close(first, second, "seeded critical calculation is byte-stable")


func _test_frozen_critical_outcome_bypasses_rolls() -> void:
	var info = _critical_fixture()
	_suite.assert_close(
		DamageCalculatorScript.calculate(info, 0.0, {"critical_outcome": true}),
		150.0,
		"frozen critical hit applies the committed multiplier"
	)
	_suite.assert_close(
		DamageCalculatorScript.calculate(info, 0.0, {"critical_outcome": false}),
		100.0,
		"frozen non-critical result preserves base damage"
	)


func _test_seeded_context_isolated_by_roll_index() -> void:
	var info = _critical_fixture()
	var first := DamageCalculatorScript.deterministic_critical_roll(
		info,
		{"seed": 99, "channel": &"damage_critical", "roll_index": 0}
	)
	var second := DamageCalculatorScript.deterministic_critical_roll(
		info,
		{"seed": 99, "channel": &"damage_critical", "roll_index": 1}
	)
	_suite.assert_true(first >= 0.0 and first < 1.0, "first seeded roll is normalized")
	_suite.assert_true(second >= 0.0 and second < 1.0, "second seeded roll is normalized")
	_suite.assert_true(not is_equal_approx(first, second), "roll index isolates deterministic outcomes")


func _test_invalid_seeded_context_fails_closed() -> void:
	var info = _critical_fixture()
	var invalid := {"seed": 99, "channel": &"", "roll_index": 0}
	_suite.assert_close(
		DamageCalculatorScript.calculate(info, 0.0, invalid),
		100.0,
		"invalid explicit critical context cannot create a critical hit"
	)


func _test_source_has_no_global_randomness() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/combat/damage_calculator.gd")
	_suite.assert_true(not source.contains("randf("), "damage calculator does not use global randf")
	_suite.assert_true(not source.contains("randi("), "damage calculator does not use global randi")


func _critical_fixture():
	return DamageInfoScript.from_plan({
		"run_id": &"run-critical",
		"target_id": &"target-critical",
		"hostile_source_id": &"source-critical",
		"attack_generation": 4,
		"hit_index": 2,
		"action_token": 17,
		"amount": 100.0,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"source": null,
		"attacker": null,
		"can_crit": true,
		"crit_chance": 0.25,
		"crit_multiplier": 1.5,
		"knockback": Vector2.ZERO,
		"tags": ["character_scaled"],
		"source_generation": 7,
		"control_effect": {},
	})
