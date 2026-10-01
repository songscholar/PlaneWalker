extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponIntentRouterScript := preload("res://scripts/input/weapon_intent_router.gd")

const V2_FIXTURE := "res://tests/fixtures/input/input_profile_v2.json"

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_v2_fixture_migrates_without_record_drift()
	_test_collisions_use_deterministic_fallbacks()
	_test_exhausted_keyboard_family_rejects_without_mutation()
	_test_exhausted_controller_family_rejects_without_mutation()
	_suite.finish(get_tree())


func _test_v2_fixture_migrates_without_record_drift() -> void:
	var source := _load_v2_fixture()
	var original := source.duplicate(true)
	var bindings_before: Dictionary = source["bindings"].duplicate(true)
	var migrated: Dictionary = WeaponIntentRouterScript.new().migrate_profile(source)

	_suite.assert_equal(migrated.get("schema_version"), 3, "schema two advances exactly to schema three")
	_suite.assert_equal(
		migrated.get("bindings", {}).get("character_skill", {}),
		{
			"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_C}],
			"controller": [{"type": "joypad_button", "button_index": 8}],
		},
		"fresh schema-three migration uses C and right-stick click"
	)
	for action_value: Variant in bindings_before.keys():
		_suite.assert_equal(
			migrated.get("bindings", {}).get(action_value),
			bindings_before[action_value],
			"schema-two records survive byte-for-byte for %s" % action_value
		)
	_suite.assert_equal(source, original, "successful migration never mutates the schema-two source")


func _test_collisions_use_deterministic_fallbacks() -> void:
	var source := _load_v2_fixture()
	source["bindings"]["weapon_utility"]["keyboard_mouse"] = [
		{"type": "key", "physical_keycode": KEY_C},
	]
	source["bindings"]["weapon_ultimate"]["controller"] = [
		{"type": "joypad_button", "button_index": 8},
	]
	var migrated: Dictionary = WeaponIntentRouterScript.new().migrate_profile(source)
	_suite.assert_equal(
		migrated.get("bindings", {}).get("character_skill", {}).get("keyboard_mouse", []),
		[{"type": "key", "physical_keycode": KEY_SPACE}],
		"occupied C falls back to the lowest free printable physical keycode"
	)
	_suite.assert_equal(
		migrated.get("bindings", {}).get("character_skill", {}).get("controller", []),
		[{"type": "joypad_button", "button_index": 7}],
		"occupied button 8 falls back through 0..31 in ascending order"
	)


func _test_exhausted_keyboard_family_rejects_without_mutation() -> void:
	var source := _load_v2_fixture()
	var actions: Array = source["bindings"].keys()
	for action_value: Variant in actions:
		source["bindings"][action_value]["keyboard_mouse"] = []
	var action_index := 0
	for keycode: int in range(KEY_SPACE, KEY_ASCIITILDE + 1):
		var action_value: Variant = actions[action_index % actions.size()]
		source["bindings"][action_value]["keyboard_mouse"].append({
			"type": "key",
			"physical_keycode": keycode,
		})
		action_index += 1
	var original := source.duplicate(true)
	var rejected: Dictionary = WeaponIntentRouterScript.new().migrate_profile(source)
	_suite.assert_equal(rejected.get("code", ""), "NO_REACHABLE_CHARACTER_SKILL", "keyboard exhaustion rejects migration")
	_suite.assert_equal(source, original, "keyboard exhaustion leaves the verified v2 source untouched")
	_suite.assert_true(not rejected.get("bindings", {}).has("character_skill"), "failed migration never exposes a partial character binding")


func _test_exhausted_controller_family_rejects_without_mutation() -> void:
	var source := _load_v2_fixture()
	var actions: Array = source["bindings"].keys()
	for action_value: Variant in actions:
		source["bindings"][action_value]["controller"] = []
	for button_index: int in range(32):
		var action_value: Variant = actions[button_index % actions.size()]
		source["bindings"][action_value]["controller"].append({
			"type": "joypad_button",
			"button_index": button_index,
		})
	var original := source.duplicate(true)
	var rejected: Dictionary = WeaponIntentRouterScript.new().migrate_profile(source)
	_suite.assert_equal(rejected.get("code", ""), "NO_REACHABLE_CHARACTER_SKILL", "controller exhaustion rejects migration")
	_suite.assert_equal(source, original, "controller exhaustion leaves the verified v2 source untouched")
	_suite.assert_true(not rejected.get("bindings", {}).has("character_skill"), "controller exhaustion cannot partially promote schema three")


func _load_v2_fixture() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(V2_FIXTURE))
	_suite.assert_true(value is Dictionary, "checked-in schema-two fixture parses")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}
