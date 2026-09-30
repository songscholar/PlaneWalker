extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	suite.assert_true(parsed is Array, "weapon profile catalog parses for Gauntlets contract")
	if parsed is Array:
		var gauntlets := _entry(parsed, "id", "gauntlets_launch_v1")
		_test_identity_and_action_inputs(suite, gauntlets)
		_test_action_timing_and_cancel_boundaries(suite, gauntlets)
		_test_combo_and_interaction_contract(suite, gauntlets)
	suite.finish(get_tree())


func _test_identity_and_action_inputs(suite, gauntlets: Dictionary) -> void:
	suite.assert_equal(gauntlets.get("availability"), ["LAUNCH", "EXPANSION"], "Gauntlets remains Launch/Expansion isolated")
	var actions: Array = gauntlets.get("actions", [])
	for action_id: String in ["punch_1", "punch_2", "punch_3", "punch_4", "punch_5"]:
		var punch := _entry(actions, "action_id", action_id)
		suite.assert_equal(str(punch.get("semantic_action", "")), "weapon_primary", "%s uses Primary" % action_id)
		suite.assert_equal(str(punch.get("activation_mode", "")), "press", "%s begins from the Primary press" % action_id)
	var heavy := _entry(actions, "action_id", "charged_heavy")
	suite.assert_equal(str(heavy.get("semantic_action", "")), "weapon_primary", "charged heavy shares Primary with the punch chain")
	suite.assert_equal(str(heavy.get("activation_mode", "")), "release", "charged heavy commits on Primary release")
	suite.assert_equal(int(heavy.get("hold_threshold_frames", -1)), 30, "charged heavy requires thirty held frames")
	var counter := _entry(actions, "action_id", "dodge_counter")
	suite.assert_equal(str(counter.get("semantic_action", "")), "weapon_primary", "Dodge Counter uses the attack input after Dash")
	suite.assert_equal(str(counter.get("activation_mode", "")), "press", "Dodge Counter is selected from the Primary press context")
	var ultimate := _entry(actions, "action_id", "primordial_collapse_punch")
	suite.assert_equal(int(ultimate.get("hold_threshold_frames", -1)), 60, "Primordial Collapse requires sixty held frames")


func _test_action_timing_and_cancel_boundaries(suite, gauntlets: Dictionary) -> void:
	var actions: Array = gauntlets.get("actions", [])
	var cases: Array[Dictionary] = [
		{"id": "punch_1", "frames": [3, 3, 5], "cancel_total": 7},
		{"id": "punch_2", "frames": [2, 3, 5], "cancel_total": 7},
		{"id": "punch_3", "frames": [3, 4, 6], "cancel_total": 9},
		{"id": "punch_4", "frames": [3, 4, 6], "cancel_total": 9},
		{"id": "punch_5", "frames": [5, 6, 14], "cancel_total": 14},
		{"id": "charged_heavy", "frames": [6, 5, 16], "cancel_total": 14},
		{"id": "dodge_counter", "frames": [2, 5, 8], "cancel_total": 10},
		{"id": "space_time_shatter", "frames": [5, 8, 12], "cancel_total": 16},
	]
	for case: Dictionary in cases:
		var action := _entry(actions, "action_id", str(case["id"]))
		var frames: Array = case["frames"]
		suite.assert_equal(int(action.get("windup_frames", -1)), int(frames[0]), "%s windup is authoritative" % str(case["id"]))
		suite.assert_equal(int(action.get("active_frames", -1)), int(frames[1]), "%s active frames are authoritative" % str(case["id"]))
		suite.assert_equal(int(action.get("recovery_frames", -1)), int(frames[2]), "%s recovery is authoritative" % str(case["id"]))
		var cancel_total := int(frames[0]) + int(frames[1]) + int(action.get("cancel_from_frame", -1))
		suite.assert_equal(cancel_total, int(case["cancel_total"]), "%s opens cancel on the combat-design total frame" % str(case["id"]))
	var ultimate := _entry(actions, "action_id", "primordial_collapse_punch")
	suite.assert_equal(ultimate.get("cancel_from_frame"), null, "Primordial Collapse cannot be cancelled")


func _test_combo_and_interaction_contract(suite, gauntlets: Dictionary) -> void:
	var resources: Array = gauntlets.get("resources", [])
	var chain := _entry(resources, "resource_id", "chain_step")
	var combo := _entry(resources, "resource_id", "combo")
	suite.assert_close(float(chain.get("minimum", -1.0)), 0.0, "chain begins at zero")
	suite.assert_close(float(chain.get("maximum", -1.0)), 4.0, "chain has five zero-based steps")
	suite.assert_close(float(combo.get("maximum", -1.0)), 999.0, "Combo authority is bounded")
	var interactions: Dictionary = gauntlets.get("time_interactions", {})
	suite.assert_equal(int(interactions.get("stop", {}).get("parameters", {}).get("maximum_bonus_frames", -1)), 30, "Stop extension is capped at thirty frames")
	suite.assert_equal(int(interactions.get("rewind", {}).get("parameters", {}).get("window_frames", -1)), 120, "Rewind Counter window lasts two seconds")
	suite.assert_equal(int(interactions.get("accelerate", {}).get("parameters", {}).get("hit_interval", -1)), 3, "Accelerate echoes every third eligible hit")
	suite.assert_close(float(interactions.get("rift", {}).get("parameters", {}).get("cost_multiplier", -1.0)), 0.7, "Rift reduces the high-Combo skill cost by thirty percent")


func _entry(entries: Variant, key: String, expected: String) -> Dictionary:
	if not entries is Array:
		return {}
	for value: Variant in entries as Array:
		if value is Dictionary and str((value as Dictionary).get(key, "")) == expected:
			return (value as Dictionary).duplicate(true)
	return {}
