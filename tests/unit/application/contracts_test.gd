extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")
const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_command_result(suite)
	_test_run_phase(suite)
	_test_run_config(suite)
	_test_selection_offer(suite)
	suite.finish(get_tree())


func _test_command_result(suite) -> void:
	var success = CommandResultScript.success(4, {"offer_id": "run:1:item:4"})
	suite.assert_true(success.ok, "success result is accepted")
	suite.assert_equal(success.code, &"OK", "success code is stable")
	suite.assert_equal(success.new_revision, 4, "success revision is retained")
	suite.assert_equal(success.context["offer_id"], "run:1:item:4", "success context is retained")

	var terminal = CommandResultScript.failure(&"TERMINAL_STATE", 9)
	suite.assert_true(not terminal.ok, "failure result is rejected")
	suite.assert_equal(terminal.code, &"TERMINAL_STATE", "failure code is retained")
	suite.assert_equal(terminal.new_revision, 9, "failure revision is retained")

	var unknown = CommandResultScript.failure(&"NOT_A_STANDARD_CODE", 3)
	suite.assert_true(not unknown.ok, "unknown code remains a failure")
	suite.assert_equal(unknown.code, &"INVALID_ARGUMENT", "unknown standard code is rejected")


func _test_run_phase(suite) -> void:
	suite.assert_true(RunPhaseScript.is_terminal(RunPhaseScript.Value.VICTORY), "victory is terminal")
	suite.assert_true(RunPhaseScript.is_terminal(RunPhaseScript.Value.DEFEAT), "defeat is terminal")
	suite.assert_true(not RunPhaseScript.is_terminal(RunPhaseScript.Value.COMBAT_ACTIVE), "combat is not terminal")


func _test_run_config(suite) -> void:
	var config := {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 123456,
	}
	suite.assert_true(RunConfigScript.validate(config).ok, "M1 config validates")
	var mutable_input := config.duplicate(true)
	var normalized: Dictionary = RunConfigScript.normalized(mutable_input)
	suite.assert_equal(normalized["seed"], 123456, "seed is normalized")
	mutable_input["enabled_time_skills"].append("rift")
	suite.assert_equal(normalized["enabled_time_skills"], ["stop", "rewind"], "normalized config is isolated from caller arrays")
	suite.assert_equal(normalized["accessibility_assists"], {
		"damage_received_multiplier": 1.0,
		"enemy_telegraph_scale": 1.0,
	}, "accessibility assists default to neutral values")

	var defaults: Dictionary = RunConfigScript.normalized({})
	suite.assert_equal(defaults["milestone"], "M1", "milestone default is stable")
	suite.assert_equal(defaults["enabled_time_skills"], ["stop", "rewind"], "time skill defaults are stable")

	var one_skill := config.duplicate(true)
	one_skill["enabled_time_skills"] = ["stop"]
	var one_skill_result = RunConfigScript.validate(one_skill)
	suite.assert_equal(one_skill_result.code, &"INVALID_ARGUMENT", "one time ability is rejected")
	suite.assert_equal(one_skill_result.context.get("field", ""), "enabled_time_skills", "one time ability reports its field")

	var three_skills := config.duplicate(true)
	three_skills["enabled_time_skills"] = ["stop", "rewind", "rift"]
	var three_skills_result = RunConfigScript.validate(three_skills)
	suite.assert_equal(three_skills_result.code, &"INVALID_ARGUMENT", "three time abilities are rejected")
	suite.assert_equal(three_skills_result.context.get("field", ""), "enabled_time_skills", "three time abilities report their field")

	var duplicate_skills := config.duplicate(true)
	duplicate_skills["enabled_time_skills"] = ["stop", "stop"]
	var duplicate_skills_result = RunConfigScript.validate(duplicate_skills)
	suite.assert_equal(duplicate_skills_result.code, &"INVALID_ARGUMENT", "duplicate time abilities are rejected")
	suite.assert_equal(duplicate_skills_result.context.get("field", ""), "enabled_time_skills", "duplicate time abilities report their field")

	var unsupported := config.duplicate(true)
	unsupported["schema_version"] = 2
	suite.assert_equal(RunConfigScript.validate(unsupported).code, &"INVALID_ARGUMENT", "unsupported config schema is rejected")

	var empty_character := config.duplicate(true)
	empty_character["character_id"] = ""
	suite.assert_equal(RunConfigScript.validate(empty_character).code, &"INVALID_ARGUMENT", "empty character id is rejected")

	var empty_weapon := config.duplicate(true)
	empty_weapon["weapon_id"] = ""
	suite.assert_equal(RunConfigScript.validate(empty_weapon).code, &"INVALID_ARGUMENT", "empty weapon id is rejected")

	var valid_assists := config.duplicate(true)
	valid_assists["accessibility_assists"] = {
		"damage_received_multiplier": 0.6,
		"enemy_telegraph_scale": 1.5,
	}
	suite.assert_true(RunConfigScript.validate(valid_assists).ok, "declared accessibility assists validate")
	var invalid_assists := valid_assists.duplicate(true)
	invalid_assists["accessibility_assists"]["damage_received_multiplier"] = 0.5
	suite.assert_equal(RunConfigScript.validate(invalid_assists).code, &"INVALID_ARGUMENT", "undeclared damage assist is rejected")


func _test_selection_offer(suite) -> void:
	var offer := _valid_offer()
	suite.assert_true(SelectionOfferScript.validate(offer).ok, "valid offer passes")
	var copied = SelectionOfferScript.copy_of(offer)
	copied["options"][0]["option_id"] = "changed"
	suite.assert_equal(offer["options"][0]["option_id"], "frozen_burst", "offer copy is isolated")

	var unsupported := offer.duplicate(true)
	unsupported["schema_version"] = 2
	suite.assert_equal(SelectionOfferScript.validate(unsupported).code, &"INVALID_ARGUMENT", "unsupported offer schema is rejected")

	var empty_offer_id := offer.duplicate(true)
	empty_offer_id["offer_id"] = ""
	suite.assert_equal(SelectionOfferScript.validate(empty_offer_id).code, &"INVALID_ARGUMENT", "empty offer id is rejected")

	var negative_revision := offer.duplicate(true)
	negative_revision["revision"] = -1
	suite.assert_equal(SelectionOfferScript.validate(negative_revision).code, &"INVALID_ARGUMENT", "negative revision is rejected")

	var no_options := offer.duplicate(true)
	no_options["options"] = []
	suite.assert_equal(SelectionOfferScript.validate(no_options).code, &"INVALID_ARGUMENT", "empty options are rejected")

	var duplicate_options := offer.duplicate(true)
	duplicate_options["options"].append(duplicate_options["options"][0].duplicate(true))
	suite.assert_equal(SelectionOfferScript.validate(duplicate_options).code, &"INVALID_ARGUMENT", "duplicate option ids are rejected")

	var missing_name_key := offer.duplicate(true)
	missing_name_key["options"][0].erase("name_key")
	suite.assert_equal(SelectionOfferScript.validate(missing_name_key).code, &"INVALID_ARGUMENT", "missing option localization key is rejected")

	var empty_content_id := offer.duplicate(true)
	empty_content_id["options"][0]["content_id"] = ""
	suite.assert_equal(SelectionOfferScript.validate(empty_content_id).code, &"INVALID_ARGUMENT", "empty content id is rejected")


func _valid_offer() -> Dictionary:
	return {
		"schema_version": 1,
		"offer_id": "run-1:room-01:item:1",
		"revision": 1,
		"category": "item",
		"title_key": "UI_CHOOSE_REWARD",
		"can_skip": false,
		"options": [{
			"option_id": "frozen_burst",
			"content_id": "frozen_burst",
			"name_key": "FROZEN_BURST_NAME",
			"description_key": "FROZEN_BURST_DESC",
			"archetype_key": "ARCHETYPE_TIME_STOP_BURST",
			"role_key": "ROLE_STARTER",
			"rarity": "common",
			"icon_id": "item_frozen_burst",
			"effect_summary_keys": ["EFFECT_TIME_STOP_DURATION"],
		}],
	}
