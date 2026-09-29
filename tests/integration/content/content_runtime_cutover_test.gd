extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunRuntimeFacadeScript := preload("res://scripts/application/run_runtime_facade.gd")
const RewardPoolScript := preload("res://scripts/rewards/reward_pool.gd")
const BlessingPoolScript := preload("res://scripts/rewards/blessing_pool.gd")
const CursePoolScript := preload("res://scripts/curses/curse_pool.gd")
const TalentPoolScript := preload("res://scripts/rewards/talent_pool.gd")

const BASE_PACK_PATH := "res://data/content_packs/base/pack.json"
const INVALID_PACK_PATH := "res://tests/fixtures/content/packs/missing/pack.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_boot_boundary(suite)
	_test_registry_is_runtime_source(suite)
	_test_compatibility_pools_are_registry_backed(suite)
	_test_legacy_definition_sources_are_retired(suite)
	suite.finish(get_tree())


func _test_boot_boundary(suite) -> void:
	var invalid_facade = RunRuntimeFacadeScript.new()
	var invalid_result = invalid_facade.boot(INVALID_PACK_PATH)
	suite.assert_true(not invalid_result.ok, "runtime boot rejects an unavailable required pack")
	suite.assert_equal(invalid_result.code, &"CONTENT_NOT_AVAILABLE", "required pack failure uses a stable code")

	var facade = RunRuntimeFacadeScript.new()
	var result = facade.boot(BASE_PACK_PATH)
	suite.assert_true(result.ok, "runtime boot activates the required base pack")
	if not result.ok:
		return
	var registry: RefCounted = facade.content_registry()
	var frozen_burst: Dictionary = registry.call("get_content", &"frozen_burst")
	suite.assert_equal(frozen_burst.get("pack_id"), "base", "runtime definitions retain base-pack ownership")
	suite.assert_equal(frozen_burst.get("pack_version"), "0.4.0-dev", "runtime definitions retain pack version")


func _test_registry_is_runtime_source(suite) -> void:
	var facade = RunRuntimeFacadeScript.new()
	var booted = facade.boot(BASE_PACK_PATH)
	if not booted.ok:
		suite.assert_true(false, "runtime registry is available for canonical offer verification")
		return
	var started = facade.start_run({
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["time_stop", "time_rewind"],
		"difficulty": "normal",
		"seed": 20260929,
	}, "content-cutover")
	suite.assert_true(started.ok, "runtime starts from the activated pack")
	if not started.ok:
		return
	var room_started = facade.enter_current_room()
	suite.assert_true(room_started.ok, "room one begins before creating a draft")
	var offer_result = facade.complete_current_room()
	suite.assert_true(offer_result.ok, "room completion creates a canonical draft")
	if not offer_result.ok:
		return
	var offer: Dictionary = offer_result.context.get("offer", {})
	var option_id := StringName(str(offer.get("options", [])[0].get("option_id", "")))
	var selected = facade.submit_selection(str(offer.get("offer_id", "")), option_id, int(offer.get("revision", -1)))
	suite.assert_true(selected.ok, "canonical registry option can be selected")
	if not selected.ok:
		return
	var canonical: Dictionary = facade.content_registry().call("get_content", option_id)
	suite.assert_equal(selected.context.get("definition", {}), canonical, "selection returns the exact canonical registry definition")


func _test_compatibility_pools_are_registry_backed(suite) -> void:
	var groups: Array[Array] = [
		RewardPoolScript.all_rewards(),
		BlessingPoolScript.all_blessings(),
		CursePoolScript.all_curses(),
		TalentPoolScript.all_talents(),
	]
	for definitions: Array in groups:
		suite.assert_true(not definitions.is_empty(), "compatibility pool exposes activated definitions")
		suite.assert_true(definitions.all(func(definition): return definition.get("pack_id") == "base"), "compatibility definitions come from the base pack")


func _test_legacy_definition_sources_are_retired(suite) -> void:
	var source_paths: Array[String] = [
		"res://scripts/rewards/reward_pool.gd",
		"res://scripts/rewards/blessing_pool.gd",
		"res://scripts/rewards/talent_pool.gd",
		"res://scripts/curses/curse_pool.gd",
	]
	for path: String in source_paths:
		var file := FileAccess.open(path, FileAccess.READ)
		var source := file.get_as_text() if file != null else ""
		suite.assert_true(not source.contains("const REWARDS"), "%s contains no reward definition array" % path)
		suite.assert_true(not source.contains("const BLESSINGS"), "%s contains no blessing definition array" % path)
		suite.assert_true(not source.contains("const TALENTS"), "%s contains no talent definition array" % path)
		suite.assert_true(not source.contains("const CURSES"), "%s contains no curse definition array" % path)
		suite.assert_true(not source.contains("RewardDataLoader"), "%s contains no legacy loader reference" % path)
	suite.assert_true(not FileAccess.file_exists("res://scripts/rewards/reward_data_loader.gd"), "legacy reward data loader is removed")
