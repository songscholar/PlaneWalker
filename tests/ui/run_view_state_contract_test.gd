extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")
const FixturesScript := preload("res://scripts/ui/fixtures/run_view_state_fixtures.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()

	var combat := FixturesScript.load_fixture("res://tests/fixtures/ui/hud_combat.json")
	_suite.assert_true(not combat.is_empty(), "combat fixture loads")
	_suite.assert_true(RunViewStateScript.validate(combat).ok, "combat fixture validates")

	var low_hp := FixturesScript.load_fixture("res://tests/fixtures/ui/hud_low_hp.json")
	_suite.assert_true(not low_hp.is_empty(), "low hp fixture loads")
	_suite.assert_true(RunViewStateScript.validate(low_hp).ok, "low hp fixture validates")

	var boss := FixturesScript.load_fixture("res://tests/fixtures/ui/hud_boss.json")
	_suite.assert_true(not boss.is_empty(), "boss fixture loads")
	_suite.assert_true(RunViewStateScript.validate(boss).ok, "boss fixture validates")

	_assert_invalid(combat, "schema_version", null, "missing schema version is rejected", true)
	_assert_invalid(combat, "schema_version", 99, "unsupported schema version is rejected")
	_assert_invalid(combat, "revision", -1, "negative revision is rejected")
	_assert_invalid(combat, "run_id", "", "empty run id is rejected")
	_assert_invalid(combat, "phase", "UNKNOWN", "unknown phase is rejected")

	var hp_over_max := combat.duplicate(true)
	hp_over_max["player"]["hp"] = 201.0
	_suite.assert_true(not RunViewStateScript.validate(hp_over_max).ok, "hp above maximum is rejected")

	var energy_over_max := combat.duplicate(true)
	energy_over_max["player"]["energy"] = 101.0
	_suite.assert_true(not RunViewStateScript.validate(energy_over_max).ok, "energy above maximum is rejected")

	var non_finite_hp := combat.duplicate(true)
	non_finite_hp["player"]["hp"] = NAN
	_suite.assert_true(not RunViewStateScript.validate(non_finite_hp).ok, "non-finite hp is rejected")

	var non_finite_cooldown := combat.duplicate(true)
	non_finite_cooldown["player"]["cooldowns"]["time_rewind"] = INF
	_suite.assert_true(not RunViewStateScript.validate(non_finite_cooldown).ok, "non-finite cooldown is rejected")

	var room_outside_total := combat.duplicate(true)
	room_outside_total["room"]["index"] = 6
	_suite.assert_true(not RunViewStateScript.validate(room_outside_total).ok, "room outside total is rejected")

	var invalid_build_entry := combat.duplicate(true)
	invalid_build_entry["build"]["items"] = [""]
	_suite.assert_true(not RunViewStateScript.validate(invalid_build_entry).ok, "empty build ids are rejected")

	var invalid_archetype_score := combat.duplicate(true)
	invalid_archetype_score["build"]["archetype_scores"]["time_stop_burst"] = INF
	_suite.assert_true(not RunViewStateScript.validate(invalid_archetype_score).ok, "non-finite archetype scores are rejected")

	var copied := RunViewStateScript.copy_of(boss)
	copied["build"]["items"][0] = "changed"
	copied["boss"]["hp"] = 1.0
	_suite.assert_equal(boss["build"]["items"][0], "frozen_burst", "nested arrays are isolated")
	_suite.assert_close(float(boss["boss"]["hp"]), 315.0, "nested dictionaries are isolated")

	_suite.finish(get_tree())


func _assert_invalid(base: Dictionary, key: String, value: Variant, label: String, erase_key: bool = false) -> void:
	var candidate := base.duplicate(true)
	if erase_key:
		candidate.erase(key)
	else:
		candidate[key] = value
	_suite.assert_true(not RunViewStateScript.validate(candidate).ok, label)
