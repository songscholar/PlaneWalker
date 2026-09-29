extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_capabilities_fail_closed()
	_test_values_must_be_finite_and_bounded()
	_test_invalid_configuration_is_rejected_atomically()
	_test_freeze_for_action_returns_an_isolated_snapshot()
	_suite.finish(get_tree())


func _test_capabilities_fail_closed() -> void:
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(
		modifiers.configure(
			PackedStringArray(["weapon.damage"]),
			{"weapon.damage": {"minimum": 0.0, "maximum": 4.0}}
		),
		"declared modifier capability configures"
	)
	_suite.assert_true(not modifiers.apply(&"weapon.ammo_capacity", 2.0), "unsupported capability is rejected")
	_suite.assert_equal(modifiers.snapshot(), {}, "unsupported capability cannot mutate state")
	_suite.assert_true(not modifiers.apply(&"", 1.0), "empty capability is rejected")
	_suite.assert_true(not modifiers.apply(&"weapon.damage", "fast"), "non-numeric modifier is rejected")


func _test_values_must_be_finite_and_bounded() -> void:
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(
		modifiers.configure(
			PackedStringArray(["weapon.damage", "weapon.ammo_capacity"]),
			{
				"weapon.damage": {"minimum": 0.25, "maximum": 3.0},
				"weapon.ammo_capacity": {"minimum": 0.0, "maximum": 20.0},
			}
		),
		"bounded capabilities configure"
	)
	_suite.assert_true(modifiers.apply(&"weapon.damage", 1.25), "in-range finite modifier applies")
	_suite.assert_equal(modifiers.snapshot(), {"weapon.damage": 1.25}, "accepted value is visible in the snapshot")

	for invalid_value: Variant in [NAN, INF, -INF, 0.24, 3.01]:
		_suite.assert_true(not modifiers.apply(&"weapon.damage", invalid_value), "invalid modifier is rejected: %s" % invalid_value)
		_suite.assert_equal(modifiers.snapshot(), {"weapon.damage": 1.25}, "rejection preserves the last valid modifier")

	_suite.assert_true(modifiers.apply(&"weapon.damage", 0.25), "inclusive minimum is accepted")
	_suite.assert_true(modifiers.apply(&"weapon.damage", 3.0), "inclusive maximum is accepted")


func _test_invalid_configuration_is_rejected_atomically() -> void:
	var invalid_configurations := [
		{
			"capabilities": PackedStringArray(["weapon.damage", "weapon.damage"]),
			"bounds": {"weapon.damage": {"minimum": 0.0, "maximum": 2.0}},
		},
		{
			"capabilities": PackedStringArray(["weapon.damage"]),
			"bounds": {},
		},
		{
			"capabilities": PackedStringArray(["weapon.damage"]),
			"bounds": {"weapon.damage": {"minimum": 2.0, "maximum": 1.0}},
		},
		{
			"capabilities": PackedStringArray(["weapon.damage"]),
			"bounds": {"weapon.damage": {"minimum": 0.0, "maximum": INF}},
		},
		{
			"capabilities": PackedStringArray(["weapon.damage"]),
			"bounds": {
				"weapon.damage": {"minimum": 0.0, "maximum": 2.0},
				"weapon.pierce": {"minimum": 0.0, "maximum": 8.0},
			},
		},
	]
	for configuration: Dictionary in invalid_configurations:
		var modifiers = WeaponModifierStateScript.new()
		_suite.assert_true(
			not modifiers.configure(configuration["capabilities"], configuration["bounds"]),
			"invalid capability bounds fail configuration: %s" % configuration
		)
		_suite.assert_equal(modifiers.snapshot(), {}, "failed configuration exposes no partial state")


func _test_freeze_for_action_returns_an_isolated_snapshot() -> void:
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(
		modifiers.configure(
			PackedStringArray(["weapon.damage", "weapon.status_duration"]),
			{
				"weapon.damage": {"minimum": 0.0, "maximum": 4.0},
				"weapon.status_duration": {"minimum": 0.0, "maximum": 10.0},
			}
		),
		"freeze fixture configures"
	)
	_suite.assert_true(modifiers.apply(&"weapon.damage", 1.5), "freeze fixture stores damage")
	_suite.assert_true(modifiers.apply(&"weapon.status_duration", 2.0), "freeze fixture stores duration")

	var frozen: Dictionary = modifiers.freeze_for_action()
	_suite.assert_equal(
		frozen,
		{"weapon.damage": 1.5, "weapon.status_duration": 2.0},
		"freeze captures the complete action modifier state"
	)
	_suite.assert_true(modifiers.apply(&"weapon.damage", 2.0), "live modifier can change after action freeze")
	_suite.assert_equal(frozen.get("weapon.damage"), 1.5, "frozen action state does not observe later live changes")

	frozen["weapon.status_duration"] = 9.0
	_suite.assert_equal(
		modifiers.snapshot().get("weapon.status_duration"),
		2.0,
		"mutating the returned freeze cannot mutate live state"
	)
