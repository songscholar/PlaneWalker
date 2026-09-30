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
	_test_additive_values_accumulate_from_explicit_identity()
	_test_additive_rejection_is_atomic()
	_test_batch_apply_and_snapshot_restore_are_atomic()
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


func _test_additive_values_accumulate_from_explicit_identity() -> void:
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(
		modifiers.configure(
			PackedStringArray([
				"weapon.charge_rate",
				"weapon.full_charge_damage",
				"weapon.pierce",
			]),
			{
				"weapon.charge_rate": {"minimum": 0.0, "maximum": 6.0},
				"weapon.full_charge_damage": {"minimum": 0.0, "maximum": 11.0},
				"weapon.pierce": {"minimum": 0.0, "maximum": 20.0},
			}
		),
		"additive bow capability fixture configures"
	)
	_suite.assert_true(
		modifiers.apply_additive(&"weapon.charge_rate", 0.25, 1.0),
		"first charge bonus starts from the multiplicative identity"
	)
	_suite.assert_true(
		modifiers.apply_additive(&"weapon.charge_rate", 0.15, 1.0),
		"second charge bonus accumulates"
	)
	_suite.assert_true(
		modifiers.apply_additive(&"weapon.full_charge_damage", 0.35, 1.0),
		"full-charge bonus starts from the multiplicative identity"
	)
	_suite.assert_true(
		modifiers.apply_additive(&"weapon.pierce", 1, 0.0),
		"first pierce bonus starts from the additive identity"
	)
	_suite.assert_true(
		modifiers.apply_additive(&"weapon.pierce", 2, 0.0),
		"second pierce bonus accumulates"
	)
	_suite.assert_equal(
		modifiers.snapshot(),
		{
			"weapon.charge_rate": 1.4,
			"weapon.full_charge_damage": 1.35,
			"weapon.pierce": 3.0,
		},
		"additive capabilities retain legacy bow bonus semantics"
	)


func _test_additive_rejection_is_atomic() -> void:
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(
		modifiers.configure(
			PackedStringArray(["weapon.charge_rate"]),
			{"weapon.charge_rate": {"minimum": 0.0, "maximum": 2.0}}
		),
		"additive rejection fixture configures"
	)
	_suite.assert_true(
		modifiers.apply_additive(&"weapon.charge_rate", 0.25, 1.0),
		"valid additive value applies"
	)
	_suite.assert_true(
		modifiers.apply_additive(&"weapon.charge_rate", 0.75, 1.0),
		"inclusive additive upper bound is accepted"
	)
	_suite.assert_equal(
		modifiers.snapshot(),
		{"weapon.charge_rate": 2.0},
		"accepted upper bound is stored exactly"
	)
	for invalid_case: Array in [
		[&"weapon.charge_rate", NAN, 1.0],
		[&"weapon.charge_rate", 0.25, INF],
		[&"weapon.charge_rate", 0.001, 1.0],
		[&"weapon.pierce", 1.0, 0.0],
	]:
		_suite.assert_true(
			not modifiers.apply_additive(invalid_case[0], invalid_case[1], invalid_case[2]),
			"invalid additive mutation is rejected: %s" % [invalid_case]
		)
		_suite.assert_equal(
			modifiers.snapshot(),
			{"weapon.charge_rate": 2.0},
			"additive rejection preserves the last valid state"
		)


func _test_batch_apply_and_snapshot_restore_are_atomic() -> void:
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(
		modifiers.configure(
			PackedStringArray(["weapon.damage", "weapon.pierce"]),
			{
				"weapon.damage": {"minimum": 0.0, "maximum": 4.0},
				"weapon.pierce": {"minimum": 0.0, "maximum": 8.0},
			}
		),
		"batch restore fixture configures"
	)
	_suite.assert_true(modifiers.apply(&"weapon.damage", 1.25), "batch restore fixture seeds damage")
	var before: Dictionary = modifiers.snapshot()
	_suite.assert_true(
		modifiers.apply_batch({"weapon.damage": 2.0, "weapon.pierce": 3.0}),
		"valid capability batch applies atomically"
	)
	_suite.assert_equal(
		modifiers.snapshot(),
		{"weapon.damage": 2.0, "weapon.pierce": 3.0},
		"valid capability batch stores every value"
	)
	_suite.assert_true(modifiers.restore_snapshot(before), "a prior exact snapshot can be restored")
	_suite.assert_equal(modifiers.snapshot(), before, "snapshot restore removes values absent from the snapshot")

	for invalid_snapshot: Dictionary in [
		{"weapon.damage": NAN},
		{"weapon.damage": 5.0},
		{"weapon.unknown": 1.0},
	]:
		_suite.assert_true(
			not modifiers.restore_snapshot(invalid_snapshot),
			"invalid snapshot restore is rejected: %s" % invalid_snapshot
		)
		_suite.assert_equal(modifiers.snapshot(), before, "invalid restore preserves the prior state")


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
