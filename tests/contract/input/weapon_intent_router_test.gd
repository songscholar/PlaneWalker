extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponIntentRouterScript := preload("res://scripts/input/weapon_intent_router.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_legacy_profile_migration()
	_test_migration_rejects_ambiguous_or_invalid_profiles()
	_test_schema_two_profiles_are_isolated()
	_test_hold_and_toggle_modes_emit_equivalent_edges()
	_test_edge_validation_fails_closed()
	_suite.finish(get_tree())


func _test_legacy_profile_migration() -> void:
	var router = WeaponIntentRouterScript.new()
	var legacy := {
		"schema_version": 1,
		"bindings": {
			"attack": {
				"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_J}],
				"controller": [{"type": "joypad_button", "button_index": JOY_BUTTON_X}],
			},
			"ranged_attack": {
				"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_X}],
				"controller": [{"type": "joypad_button", "button_index": JOY_BUTTON_Y}],
			},
			"heavy_attack": {
				"keyboard_mouse": [{"type": "mouse_button", "button_index": MOUSE_BUTTON_RIGHT}],
				"controller": [{"type": "joypad_button", "button_index": JOY_BUTTON_B}],
			},
			"dash": [{"type": "key", "physical_keycode": KEY_SPACE}],
			"time_stop": [{"type": "key", "physical_keycode": KEY_Q}],
		},
	}
	var original := legacy.duplicate(true)
	var migrated: Dictionary = router.migrate_profile(legacy)

	_suite.assert_equal(migrated.get("schema_version"), 2, "legacy profile advances exactly one schema version")
	_suite.assert_equal(
		migrated.get("bindings", {}).get("weapon_primary", []),
		{
			"keyboard_mouse": [
				{"type": "key", "physical_keycode": KEY_J},
				{"type": "key", "physical_keycode": KEY_X},
			],
			"controller": [
				{"type": "joypad_button", "button_index": JOY_BUTTON_X},
				{"type": "joypad_button", "button_index": JOY_BUTTON_Y},
			],
		},
		"legacy attack bindings merge into semantic primary without loss"
	)
	_suite.assert_equal(
		migrated.get("bindings", {}).get("weapon_secondary", []),
		{
			"keyboard_mouse": [{"type": "mouse_button", "button_index": MOUSE_BUTTON_RIGHT}],
			"controller": [{"type": "joypad_button", "button_index": JOY_BUTTON_B}],
		},
		"legacy heavy attack becomes semantic secondary"
	)
	_suite.assert_equal(
		migrated.get("bindings", {}).get("dash", []),
		legacy["bindings"]["dash"],
		"non-weapon bindings survive migration"
	)
	_suite.assert_equal(
		migrated.get("bindings", {}).get("time_stop", []),
		legacy["bindings"]["time_stop"],
		"fixed time bindings remain available to the one-version compatibility adapter"
	)
	_suite.assert_true(not migrated.get("bindings", {}).has("attack"), "legacy attack key is retired in the migrated copy")
	_suite.assert_true(not migrated.get("bindings", {}).has("heavy_attack"), "legacy heavy key is retired in the migrated copy")
	_suite.assert_true(not migrated.get("bindings", {}).has("ranged_attack"), "legacy ranged key is retired in the migrated copy")

	(migrated["bindings"]["weapon_primary"]["keyboard_mouse"] as Array)[0]["physical_keycode"] = KEY_K
	_suite.assert_equal(legacy, original, "migration never mutates the persisted source profile")


func _test_migration_rejects_ambiguous_or_invalid_profiles() -> void:
	var router = WeaponIntentRouterScript.new()
	var invalid_profiles: Array[Dictionary] = [
		{},
		{"schema_version": 3, "bindings": {}},
		{"schema_version": 1, "bindings": []},
		{"schema_version": 1, "bindings": {"attack": "KEY_J"}},
		{
			"schema_version": 1,
			"bindings": {
				"attack": [KEY_J],
				"weapon_primary": [KEY_K],
			},
		},
	]
	for profile: Dictionary in invalid_profiles:
		_suite.assert_equal(router.migrate_profile(profile), {}, "invalid or ambiguous migration fails closed: %s" % profile)


func _test_schema_two_profiles_are_isolated() -> void:
	var router = WeaponIntentRouterScript.new()
	var current := {
		"schema_version": 2,
		"bindings": {
			"weapon_primary": {
				"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_J}],
				"controller": [{"type": "joypad_button", "button_index": JOY_BUTTON_X}],
			},
		},
	}
	var migrated: Dictionary = router.migrate_profile(current)
	_suite.assert_equal(migrated, current, "current profiles pass through without semantic drift")
	(migrated["bindings"]["weapon_primary"]["keyboard_mouse"] as Array)[0]["physical_keycode"] = KEY_K
	_suite.assert_equal(
		current["bindings"]["weapon_primary"]["keyboard_mouse"][0]["physical_keycode"],
		KEY_J,
		"current profile pass-through is a deep copy"
	)


func _test_hold_and_toggle_modes_emit_equivalent_edges() -> void:
	var hold_router = WeaponIntentRouterScript.new()
	var hold_edges := [
		hold_router.normalize_edge(&"attack", &"pressed", 0, &"hold"),
		hold_router.normalize_edge(&"attack", &"held", 18, &"hold"),
		hold_router.normalize_edge(&"attack", &"released", 18, &"hold"),
	]

	var toggle_router = WeaponIntentRouterScript.new()
	var toggle_edges := [
		toggle_router.normalize_edge(&"weapon_primary", &"pressed", 0, &"toggle"),
		toggle_router.normalize_edge(&"weapon_primary", &"held", 18, &"toggle"),
	]
	_suite.assert_equal(
		toggle_router.normalize_edge(&"weapon_primary", &"released", 18, &"toggle"),
		{},
		"physical release is silent while toggle mode remains active"
	)
	toggle_edges.append(toggle_router.normalize_edge(&"weapon_primary", &"pressed", 0, &"toggle"))

	_suite.assert_equal(toggle_edges, hold_edges, "hold and toggle normalize to the same semantic edge sequence")
	_suite.assert_equal(hold_edges[0], {"id": &"weapon_primary", "edge": &"pressed", "held_frames": 0}, "legacy attack normalizes to semantic primary")
	_suite.assert_equal(hold_edges[2].get("held_frames"), 18, "release preserves the authoritative held-frame count")


func _test_edge_validation_fails_closed() -> void:
	var router = WeaponIntentRouterScript.new()
	var rejected := [
		router.normalize_edge(&"debug_action", &"pressed", 0, &"hold"),
		router.normalize_edge(&"weapon_primary", &"unknown", 0, &"hold"),
		router.normalize_edge(&"weapon_primary", &"pressed", -1, &"hold"),
		router.normalize_edge(&"weapon_primary", &"pressed", 0, &"auto"),
	]
	for result: Dictionary in rejected:
		_suite.assert_equal(result, {}, "invalid edge input produces no semantic intent")

	_suite.assert_equal(
		router.normalize_edge(&"weapon_primary", &"pressed", 0, &"toggle"),
		{"id": &"weapon_primary", "edge": &"pressed", "held_frames": 0},
		"rejected inputs do not corrupt later toggle state"
	)
