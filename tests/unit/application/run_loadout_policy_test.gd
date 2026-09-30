extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")

const BASE_PACK_PATH := "res://data/content_packs/base/pack.json"
const GAME_VERSION := "0.4.0-dev"
const RUN_LOADOUT_POLICY_PATH := "res://scripts/application/run_loadout_policy.gd"

var _registry: RefCounted
var _policy: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_registry = ContentRegistryScript.new()
	var report = _registry.load_packs(
		[{"path": BASE_PACK_PATH, "required": true}],
		GAME_VERSION,
		&"M1"
	)
	suite.assert_true(
		not report.has_blocking_errors(),
		"loadout policy fixture activates: %s" % str(report.blocking_errors)
	)
	if not ResourceLoader.exists(RUN_LOADOUT_POLICY_PATH):
		suite.assert_true(false, "RunLoadoutPolicy production boundary exists")
		suite.finish(get_tree())
		return
	var policy_script: Script = load(RUN_LOADOUT_POLICY_PATH)
	_policy = policy_script.new()
	_test_exactly_two_distinct_abilities(suite)
	_test_m1_default(suite)
	_test_unknown_ids(suite)
	_test_wrong_categories(suite)
	_test_milestone_availability(suite)
	_test_next_candidate_presets(suite)
	_test_launch_weapon_time_matrix(suite)
	_test_launch_character_weapon_time_matrix(suite)
	_test_result_definitions_are_deep_copies(suite)
	suite.finish(get_tree())


func _test_exactly_two_distinct_abilities(suite) -> void:
	var one := _config()
	one["enabled_time_skills"] = ["stop"]
	suite.assert_equal(
		RunConfigScript.validate(one).code,
		&"INVALID_ARGUMENT",
		"one time ability is rejected structurally"
	)
	var duplicate := _config()
	duplicate["enabled_time_skills"] = ["stop", "stop"]
	suite.assert_equal(
		RunConfigScript.validate(duplicate).code,
		&"INVALID_ARGUMENT",
		"duplicate time abilities are rejected structurally"
	)


func _test_m1_default(suite) -> void:
	var result = _policy.validate(_config(), _registry)
	suite.assert_true(result.ok, "M1 default loadout validates")
	if not result.ok:
		return
	var loadout: Dictionary = result.context.get("loadout", {})
	suite.assert_equal(str(loadout.get("character", {}).get("id", "")), "wanderer", "M1 default resolves Wanderer")
	suite.assert_equal(str(loadout.get("character_profile", {}).get("id", "")), "wanderer_m1_v1", "M1 default resolves the frozen Wanderer profile")
	suite.assert_equal(str(loadout.get("weapon", {}).get("id", "")), "sword", "M1 default resolves Sword")
	suite.assert_equal(str(loadout.get("weapon_profile", {}).get("id", "")), "sword_m1_v1", "M1 default resolves the frozen Sword profile")
	suite.assert_equal(_definition_ids(loadout.get("time_abilities", [])), ["stop", "rewind"], "M1 default resolves Stop and Rewind in slot order")


func _test_unknown_ids(suite) -> void:
	var cases: Array[Dictionary] = [
		{"field": "character_id", "value": "missing_character", "label": "unknown character"},
		{"field": "weapon_id", "value": "missing_weapon", "label": "unknown weapon"},
		{"field": "enabled_time_skills", "value": ["stop", "missing_ability"], "label": "unknown time ability"},
	]
	for case: Dictionary in cases:
		var config := _config()
		config[str(case["field"])] = case["value"]
		var result = _policy.validate(config, _registry)
		suite.assert_equal(result.code, &"CONTENT_NOT_AVAILABLE", "%s is rejected" % str(case["label"]))


func _test_wrong_categories(suite) -> void:
	var cases: Array[Dictionary] = [
		{"field": "character_id", "value": "sword", "label": "weapon used as character"},
		{"field": "weapon_id", "value": "wanderer", "label": "character used as weapon"},
		{"field": "enabled_time_skills", "value": ["stop", "sword"], "label": "weapon used as time ability"},
	]
	for case: Dictionary in cases:
		var config := _config()
		config[str(case["field"])] = case["value"]
		var result = _policy.validate(config, _registry)
		suite.assert_equal(result.code, &"CONTENT_NOT_AVAILABLE", "%s is rejected" % str(case["label"]))


func _test_milestone_availability(suite) -> void:
	var unavailable_cases: Array[Dictionary] = [
		{"weapon_id": "bow", "skills": ["stop", "rewind"], "label": "M1 Bow"},
		{"weapon_id": "sword", "skills": ["stop", "rift"], "label": "M1 Rift"},
		{"weapon_id": "sword", "skills": ["stop", "accelerate"], "label": "M1 Accelerate"},
	]
	for case: Dictionary in unavailable_cases:
		var config := _config(str(case["weapon_id"]), case["skills"])
		var result = _policy.validate(config, _registry)
		suite.assert_equal(result.code, &"CONTENT_NOT_AVAILABLE", "%s is unavailable" % str(case["label"]))


func _test_next_candidate_presets(suite) -> void:
	var candidate_presets: Array[Dictionary] = [
		{"weapon_id": "bow", "skills": ["stop", "rewind"], "label": "Bow candidate"},
		{"weapon_id": "sword", "skills": ["stop", "rift"], "label": "Rift candidate"},
		{"weapon_id": "sword", "skills": ["stop", "accelerate"], "label": "Accelerate candidate"},
	]
	for preset: Dictionary in candidate_presets:
		var config := _config(str(preset["weapon_id"]), preset["skills"], "NEXT")
		var result = _policy.validate(config, _registry)
		suite.assert_true(result.ok, "%s validates in NEXT" % str(preset["label"]))
		if not result.ok:
			continue
		var loadout: Dictionary = result.context.get("loadout", {})
		suite.assert_equal(str(loadout.get("weapon", {}).get("id", "")), preset["weapon_id"], "%s resolves its weapon" % str(preset["label"]))
		var expected_profile := "bow_candidate_v1" if str(preset["weapon_id"]) == "bow" else "sword_launch_v1"
		suite.assert_equal(str(loadout.get("weapon_profile", {}).get("id", "")), expected_profile, "%s resolves its milestone profile" % str(preset["label"]))
		suite.assert_equal(_definition_ids(loadout.get("time_abilities", [])), preset["skills"], "%s resolves both ability slots" % str(preset["label"]))


func _test_launch_weapon_time_matrix(suite) -> void:
	var weapons: Array[String] = ["sword", "bow", "gun", "staff", "gauntlets"]
	var time_pairs: Array[Array] = [
		["stop", "rewind"],
		["stop", "rift"],
		["stop", "accelerate"],
		["rewind", "rift"],
		["rewind", "accelerate"],
		["rift", "accelerate"],
	]
	for weapon_id: String in weapons:
		for pair: Array in time_pairs:
			var label := "%s / %s" % [weapon_id, "+".join(pair)]
			var result = _policy.validate(_config(weapon_id, pair, "LAUNCH"), _registry)
			suite.assert_true(result.ok, "%s validates through the player-facing Launch matrix" % label)
			if not result.ok:
				continue
			var loadout: Dictionary = result.context.get("loadout", {})
			suite.assert_equal(str(loadout.get("weapon", {}).get("id", "")), weapon_id, "%s resolves its weapon" % label)
			suite.assert_equal(_definition_ids(loadout.get("time_abilities", [])), pair, "%s preserves its ordered time pair" % label)
			suite.assert_true(
				not str(loadout.get("weapon_profile", {}).get("id", "")).is_empty(),
				"%s resolves one authoritative runtime Profile" % label
			)


func _test_launch_character_weapon_time_matrix(suite) -> void:
	var characters: Array[String] = [
		"wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord",
	]
	var weapons: Array[String] = ["sword", "bow", "gun", "staff", "gauntlets"]
	var time_pairs: Array[Array] = [
		["stop", "rewind"],
		["stop", "rift"],
		["stop", "accelerate"],
		["rewind", "rift"],
		["rewind", "accelerate"],
		["rift", "accelerate"],
	]
	var reversed_pairs: Array[Array] = []
	for pair: Array in time_pairs:
		reversed_pairs.append([pair[1], pair[0]])
	for milestone: String in ["LAUNCH", "EXPANSION"]:
		var accepted := 0
		var rejected_reversed := 0
		for character_id: String in characters:
			for weapon_id: String in weapons:
				for pair: Array in time_pairs:
					var config := _config(weapon_id, pair, milestone)
					config["character_id"] = character_id
					var label := "%s / %s / %s / %s" % [milestone, character_id, weapon_id, "+".join(pair)]
					var result = _policy.validate(config, _registry)
					suite.assert_true(result.ok, "%s validates through the 150-loadout policy matrix" % label)
					if not result.ok:
						continue
					var loadout: Dictionary = result.context.get("loadout", {})
					suite.assert_equal(
						str(loadout.get("character_profile", {}).get("character_id", "")),
						character_id,
						"%s resolves its authoritative character profile" % label
					)
					accepted += 1
				for pair: Array in reversed_pairs:
					var reversed_config := _config(weapon_id, pair, milestone)
					reversed_config["character_id"] = character_id
					var reversed_result = _policy.validate(reversed_config, _registry)
					suite.assert_equal(
						reversed_result.code,
						&"INVALID_ARGUMENT",
						"%s / %s / %s rejects noncanonical pair %s" % [milestone, character_id, weapon_id, "+".join(pair)]
					)
					rejected_reversed += 1
		suite.assert_equal(accepted, 150, "%s accepts exactly 150 canonical loadouts" % milestone)
		suite.assert_equal(rejected_reversed, 150, "%s rejects all 150 reversed duplicates" % milestone)


func _test_result_definitions_are_deep_copies(suite) -> void:
	var first = _policy.validate(_config(), _registry)
	suite.assert_true(first.ok, "deep-copy fixture validates")
	if not first.ok:
		return
	var loadout: Dictionary = first.context["loadout"]
	loadout["character"]["tags"].append("forged-character-tag")
	loadout["character_profile"]["base_stats"]["attack"] = 999
	loadout["weapon"]["availability"].clear()
	loadout["time_abilities"][0]["compatibility"]["forged"] = ["mutation"]

	var second = _policy.validate(_config(), _registry)
	suite.assert_true(second.ok, "fresh validation succeeds after caller mutation")
	if not second.ok:
		return
	var fresh: Dictionary = second.context["loadout"]
	suite.assert_true(not fresh["character"]["tags"].has("forged-character-tag"), "character definition is isolated")
	suite.assert_equal(fresh["character_profile"]["base_stats"]["attack"], 30.0, "character profile is isolated")
	suite.assert_true(not fresh["weapon"]["availability"].is_empty(), "weapon definition is isolated")
	suite.assert_true(not fresh["time_abilities"][0]["compatibility"].has("forged"), "time ability definition is isolated")
	suite.assert_true(not _registry.get_content(&"wanderer")["tags"].has("forged-character-tag"), "policy result cannot mutate the registry")


func _config(
	weapon_id: String = "sword",
	time_ability_ids: Array = ["stop", "rewind"],
	milestone: String = "M1"
) -> Dictionary:
	return RunConfigScript.normalized({
		"milestone": milestone,
		"character_id": "wanderer",
		"weapon_id": weapon_id,
		"enabled_time_skills": time_ability_ids.duplicate(true),
		"seed": 20260929,
	})


func _definition_ids(definitions: Array) -> Array[String]:
	var ids: Array[String] = []
	for definition: Dictionary in definitions:
		ids.append(str(definition.get("id", "")))
	return ids
