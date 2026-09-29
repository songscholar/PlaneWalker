extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponIntentRouterScript := preload("res://scripts/input/weapon_intent_router.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_legacy_profile_migration()
	_test_legacy_time_bindings_merge_in_stable_slot_order()
	_test_migration_rejects_ambiguous_or_invalid_profiles()
	_test_schema_two_profiles_are_isolated()
	_test_hold_and_toggle_modes_emit_equivalent_edges()
	_test_press_mode_is_stateless()
	_test_reset_action_and_reset_all_clear_latches()
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
		"time_stop": {
			"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_Q}],
			"controller": [{"type": "joypad_button", "button_index": JOY_BUTTON_LEFT_SHOULDER}],
		},
		"time_rewind": {
			"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_E}],
			"controller": [{"type": "joypad_button", "button_index": JOY_BUTTON_RIGHT_SHOULDER}],
		},
		"time_rift": {
			"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_R}],
			"controller": [{"type": "joypad_axis", "axis": JOY_AXIS_TRIGGER_LEFT, "direction": 1}],
		},
		"time_accelerate": {
			"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_F}],
			"controller": [{"type": "joypad_button", "button_index": JOY_BUTTON_BACK}],
		},
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
		migrated.get("bindings", {}).get("time_slot_1", []),
		{
			"keyboard_mouse": [
				{"type": "key", "physical_keycode": KEY_Q},
				{"type": "key", "physical_keycode": KEY_R},
			],
			"controller": [
				{"type": "joypad_button", "button_index": JOY_BUTTON_LEFT_SHOULDER},
				{"type": "joypad_axis", "axis": JOY_AXIS_TRIGGER_LEFT, "direction": 1},
			],
		},
		"legacy stop then rift bindings merge into slot one without loss"
	)
	_suite.assert_equal(
		migrated.get("bindings", {}).get("time_slot_2", []),
		{
			"keyboard_mouse": [
				{"type": "key", "physical_keycode": KEY_E},
				{"type": "key", "physical_keycode": KEY_F},
			],
			"controller": [
				{"type": "joypad_button", "button_index": JOY_BUTTON_RIGHT_SHOULDER},
				{"type": "joypad_button", "button_index": JOY_BUTTON_BACK},
			],
		},
		"legacy rewind then accelerate bindings merge into slot two without loss"
	)
	_suite.assert_true(not migrated.get("bindings", {}).has("attack"), "legacy attack key is retired in the migrated copy")
	_suite.assert_true(not migrated.get("bindings", {}).has("heavy_attack"), "legacy heavy key is retired in the migrated copy")
	_suite.assert_true(not migrated.get("bindings", {}).has("ranged_attack"), "legacy ranged key is retired in the migrated copy")
	for legacy_time_action: String in ["time_stop", "time_rewind", "time_rift", "time_accelerate"]:
		_suite.assert_true(
			not migrated.get("bindings", {}).has(legacy_time_action),
			"legacy fixed time key is retired after slot migration: %s" % legacy_time_action
		)

	(migrated["bindings"]["weapon_primary"]["keyboard_mouse"] as Array)[0]["physical_keycode"] = KEY_K
	_suite.assert_equal(legacy, original, "migration never mutates the persisted source profile")


func _test_legacy_time_bindings_merge_in_stable_slot_order() -> void:
	var router = WeaponIntentRouterScript.new()
	var duplicate_q := {"type": "key", "physical_keycode": KEY_Q}
	var migrated: Dictionary = router.migrate_profile({
		"schema_version": 1,
		"bindings": {
			"time_stop": {"keyboard_mouse": [duplicate_q], "controller": []},
			"time_rewind": {"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_E}], "controller": []},
			"time_rift": {"keyboard_mouse": [duplicate_q], "controller": []},
			"time_accelerate": {"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_F}], "controller": []},
		},
	})
	_suite.assert_equal(
		migrated.get("bindings", {}).get("time_slot_1", {}).get("keyboard_mouse", []),
		[duplicate_q],
		"slot one deduplicates after applying stop then rift order"
	)
	_suite.assert_equal(
		migrated.get("bindings", {}).get("time_slot_2", {}).get("keyboard_mouse", []),
		[
			{"type": "key", "physical_keycode": KEY_E},
			{"type": "key", "physical_keycode": KEY_F},
		],
		"slot two keeps rewind then accelerate order"
	)


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


func _test_press_mode_is_stateless() -> void:
	var router = WeaponIntentRouterScript.new()
	var first_press: Dictionary = router.normalize_edge(
		&"weapon_secondary",
		&"pressed",
		0,
		&"press"
	)
	_suite.assert_equal(
		first_press,
		{"id": &"weapon_secondary", "edge": &"pressed", "held_frames": 0},
		"press mode emits the semantic pressed edge"
	)
	_suite.assert_equal(
		router.normalize_edge(&"weapon_secondary", &"held", 12, &"press"),
		{},
		"press mode ignores held edges"
	)
	_suite.assert_equal(
		router.normalize_edge(&"weapon_secondary", &"released", 12, &"press"),
		{},
		"press mode keeps physical release silent"
	)
	_suite.assert_equal(
		router.normalize_edge(&"heavy_attack", &"pressed", 99, &"press"),
		{"id": &"weapon_secondary", "edge": &"pressed", "held_frames": 0},
		"a later legacy alias press remains stateless and normalizes to the same semantic slot"
	)


func _test_reset_action_and_reset_all_clear_latches() -> void:
	var router = WeaponIntentRouterScript.new()
	_suite.assert_equal(
		router.normalize_edge(&"attack", &"pressed", 0, &"toggle"),
		{"id": &"weapon_primary", "edge": &"pressed", "held_frames": 0},
		"legacy primary begins a toggle latch"
	)
	_suite.assert_true(
		router.reset_action(&"attack"),
		"reset_action accepts a legacy alias and clears its semantic latch"
	)
	_suite.assert_equal(
		router.normalize_edge(&"weapon_primary", &"pressed", 0, &"toggle"),
		{"id": &"weapon_primary", "edge": &"pressed", "held_frames": 0},
		"a cancelled toggle starts fresh after reset_action"
	)
	_suite.assert_true(
		not router.reset_action(&"debug_action"),
		"reset_action fails closed for unknown actions"
	)

	router.normalize_edge(&"weapon_secondary", &"pressed", 0, &"toggle")
	router.reset_all()
	_suite.assert_equal(
		router.normalize_edge(&"weapon_primary", &"pressed", 0, &"toggle"),
		{"id": &"weapon_primary", "edge": &"pressed", "held_frames": 0},
		"reset_all clears the primary latch"
	)
	_suite.assert_equal(
		router.normalize_edge(&"weapon_secondary", &"pressed", 0, &"toggle"),
		{"id": &"weapon_secondary", "edge": &"pressed", "held_frames": 0},
		"reset_all clears every other semantic latch"
	)


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
