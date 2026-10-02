extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")

const GAME_VERSION := "0.4.0-dev"

var _suite
var _test_root: String = ""
var _original_save_path: String = ""
var _original_persistent: Dictionary = {}
var _setting_signal_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_original_save_path = GameState.save_path
	_original_persistent = GameState.persistent.duplicate(true)
	_test_root = _unique_test_root()
	_remove_tree(_test_root)

	_test_legacy_import_is_one_time_and_preserves_source()
	_test_defaults_and_active_run_round_trip()
	_test_settings_and_profile_statistics_round_trip()
	_test_v1_profile_loads_through_production_migration()
	_test_v2_profile_loads_through_production_migration()
	_test_failed_load_preserves_authoritative_memory()
	_test_profile_and_domain_isolation()
	_test_old_callers_and_failed_setting_signal_behavior()

	GameState.save_path = _original_save_path
	GameState.persistent = _original_persistent.duplicate(true)
	_remove_tree(_test_root)
	_suite.finish(get_tree())


func _test_legacy_import_is_one_time_and_preserves_source() -> void:
	var legacy_path := _begin_case("legacy_import")
	var fixture_bytes := _read_text("res://tests/fixtures/save/legacy_v0.json")
	_write_text(legacy_path, fixture_bytes)
	GameState.persistent = {"sentinel": "before-import"}

	_suite.assert_true(GameState.load_persistent(), "legacy document imports through the compatibility API")
	_suite.assert_equal(GameState.persistent.get("runs_completed"), 5.0, "legacy profile statistics migrate")
	_suite.assert_equal(GameState.get_setting("locale"), "en", "legacy settings migrate to global settings")
	_suite.assert_equal(_read_text(legacy_path), fixture_bytes, "legacy source bytes remain preserved after import")
	_suite.assert_true(FileAccess.file_exists(_profile_primary_path(legacy_path)), "legacy import creates the versioned profile")
	_suite.assert_true(FileAccess.file_exists(_settings_primary_path(legacy_path)), "legacy import creates global settings")

	var changed_legacy := JSON.stringify({
		"version": 1,
		"persistent": {
			"runs_completed": 99,
			"settings": {"locale": "zh_CN"},
		},
	}, "", true, true)
	_write_text(legacy_path, changed_legacy)
	GameState.persistent = {}
	_suite.assert_true(GameState.load_persistent(), "versioned profile reload succeeds after legacy import")
	_suite.assert_equal(GameState.persistent.get("runs_completed"), 5.0, "valid profile prevents repeated legacy import")
	_suite.assert_equal(GameState.get_setting("locale"), "en", "valid global settings prevent legacy overwrite")


func _test_defaults_and_active_run_round_trip() -> void:
	_begin_case("active_run_round_trip")
	_suite.assert_equal(GameState.persistent.get("active_run_state"), {}, "GameState defaults expose the no-active-run sentinel")
	var active_run := _m1_active_run()
	GameState.persistent["active_run_state"] = active_run
	_suite.assert_true(GameState.save_persistent(), "GameState persists a complete active RunState snapshot")
	GameState.persistent = {"sentinel": "before-active-run-load"}
	_suite.assert_true(GameState.load_persistent(), "GameState reloads the active RunState snapshot")
	_suite.assert_equal(GameState.persistent.get("active_run_state"), active_run, "GameState active run round trips losslessly")


func _test_settings_and_profile_statistics_round_trip() -> void:
	_begin_case("round_trip")
	_suite.assert_true(GameState.set_setting("master_volume", 0.4), "old setting caller receives successful persistence")
	_suite.assert_true(GameState.set_setting("master_muted", true), "mute setting persists globally")
	GameState.persistent["runs_completed"] = 7
	GameState.persistent["victories"] = 2
	GameState.persistent["best_rooms_cleared"] = 5
	GameState.persistent["last_run_summary"] = {"result": "floor_cleared", "kills": 8}
	_suite.assert_true(GameState.save_persistent(), "profile statistics save through compatibility API")

	GameState.persistent = {"sentinel": "replace-on-success"}
	_suite.assert_true(GameState.load_persistent(), "versioned profile and settings load together")
	_suite.assert_equal(GameState.persistent.get("runs_completed"), 7.0, "run count round trips")
	_suite.assert_equal(GameState.persistent.get("victories"), 2.0, "victory count round trips")
	_suite.assert_equal(GameState.persistent.get("last_run_summary", {}).get("kills"), 8.0, "run summary round trips")
	_suite.assert_equal(GameState.get_setting("master_volume"), 0.4, "global volume round trips")
	_suite.assert_equal(GameState.get_setting("master_muted"), true, "global mute round trips")

	GameState.persistent["runs_completed"] = 8
	GameState.persistent["settings"]["locale"] = "fr"
	_suite.assert_true(not GameState.save_persistent(), "invalid settings fail before replacing the profile primary")
	GameState.persistent = {"sentinel": "reload-previous-primary"}
	_suite.assert_true(GameState.load_persistent(), "previous profile remains loadable after failed save")
	_suite.assert_equal(GameState.persistent.get("runs_completed"), 7.0, "failed save preserves the previous profile primary")


func _test_failed_load_preserves_authoritative_memory() -> void:
	var legacy_path := _begin_case("failed_load")
	GameState.persistent["runs_completed"] = 3
	_suite.assert_true(GameState.save_persistent(), "failure fixture saves")
	_write_text(_profile_primary_path(legacy_path), "corrupt-primary")
	var authoritative := {
		"runs_completed": 42,
		"settings": {"master_volume": 0.25},
		"sentinel": {"nested": true},
	}
	GameState.persistent = authoritative.duplicate(true)

	_suite.assert_true(not GameState.load_persistent(), "unrecoverable profile load reports failure")
	_suite.assert_equal(GameState.persistent, authoritative, "failed load does not replace authoritative in-memory data")


func _test_v1_profile_loads_through_production_migration() -> void:
	var legacy_path := _begin_case("v1_production_migration")
	GameState.persistent["runs_completed"] = 6
	_suite.assert_true(GameState.save_persistent(), "GameState writes the v2 migration fixture")
	var profile_path := _profile_primary_path(legacy_path)
	var legacy_profile := _read_json(profile_path)
	legacy_profile["schema_version"] = 1
	(legacy_profile.get("payload", {}) as Dictionary).erase("active_item_state")
	(legacy_profile.get("payload", {}) as Dictionary).erase("reward_effect_state")
	_resign(legacy_profile)
	_write_text(profile_path, JSON.stringify(legacy_profile, "", true, true))

	GameState.persistent = {"sentinel": "before-v1-load"}
	_suite.assert_true(GameState.load_persistent(), "GameState production load migrates schema v1")
	_suite.assert_equal(GameState.persistent.get("runs_completed"), 6.0, "v1 progress survives GameState load")
	_suite.assert_equal(
		GameState.persistent.get("active_item_state"),
		_empty_active_item_state(),
		"GameState receives explicit active-item migration state"
	)
	_suite.assert_equal(
		GameState.persistent.get("reward_effect_state"),
		{},
		"GameState receives explicit reward-effect migration state"
	)
	_suite.assert_equal(GameState.persistent.get("active_run_state"), {}, "v1 migration reaches the v3 active-run default")
	_suite.assert_equal(_read_json(profile_path).get("schema_version"), 3.0, "v1 profile rewrites as schema v3")


func _test_v2_profile_loads_through_production_migration() -> void:
	var legacy_path := _begin_case("v2_production_migration")
	GameState.persistent["runs_completed"] = 8
	_suite.assert_true(GameState.save_persistent(), "GameState writes the v3 migration fixture")
	var profile_path := _profile_primary_path(legacy_path)
	var legacy_profile := _read_json(profile_path)
	legacy_profile["schema_version"] = 2
	(legacy_profile.get("payload", {}) as Dictionary).erase("active_run_state")
	_resign(legacy_profile)
	_write_text(profile_path, JSON.stringify(legacy_profile, "", true, true))
	GameState.persistent = {"sentinel": "before-v2-load"}
	_suite.assert_true(GameState.load_persistent(), "GameState production load migrates schema v2")
	_suite.assert_equal(GameState.persistent.get("runs_completed"), 8.0, "v2 progress survives GameState load")
	_suite.assert_equal(GameState.persistent.get("active_run_state"), {}, "v2 migration installs the no-active-run sentinel")
	_suite.assert_equal(_read_json(profile_path).get("schema_version"), 3.0, "v2 profile rewrites as schema v3")


func _test_profile_and_domain_isolation() -> void:
	var legacy_path := _begin_case("scope_isolation")
	GameState.persistent["runs_completed"] = 11
	_suite.assert_true(GameState.save_persistent(), "base slot fixture saves")

	var service = SaveServiceScript.new()
	var configured = service.configure(_service_root(legacy_path), GAME_VERSION, _base_content_snapshot())
	_suite.assert_true(configured.ok, "auxiliary isolation service configures")
	_suite.assert_true(service.save_profile("slot_2", "base", {"runs_completed": 22}).ok, "second profile saves")
	_suite.assert_true(service.save_profile("slot_1", "modded", {"runs_completed": 33}).ok, "mod domain saves")

	GameState.persistent = {"runs_completed": -1}
	_suite.assert_true(GameState.load_persistent(), "GameState reloads its fixed base scope")
	_suite.assert_equal(GameState.persistent.get("runs_completed"), 11.0, "GameState cannot cross into another profile or domain")
	_suite.assert_equal(service.load_profile("slot_2", "base").payload.get("runs_completed"), 22.0, "second profile remains isolated")
	_suite.assert_equal(service.load_profile("slot_1", "modded").payload.get("runs_completed"), 33.0, "mod domain remains isolated")


func _test_old_callers_and_failed_setting_signal_behavior() -> void:
	var legacy_path := _begin_case("old_callers")
	GameState.persistent["chronos_shards"] = 9
	_suite.assert_true(GameState.save_persistent(), "save_persistent remains a boolean compatibility call")
	GameState.persistent = {}
	_suite.assert_true(GameState.load_persistent(), "load_persistent remains a boolean compatibility call")
	_suite.assert_equal(GameState.persistent.get("chronos_shards"), 9.0, "old caller data is restored")
	GameState.reset_persistent_data(true)
	_suite.assert_equal(GameState.persistent.get("chronos_shards"), 0, "reset_persistent_data restores defaults")
	_suite.assert_true(not FileAccess.file_exists(_profile_primary_path(legacy_path)), "reset removes the compatibility profile")

	_setting_signal_count = 0
	if not GameState.setting_changed.is_connected(_on_setting_changed):
		GameState.setting_changed.connect(_on_setting_changed)
	var saved: Variant = GameState.set_setting("master_volume", 2.0)
	if GameState.setting_changed.is_connected(_on_setting_changed):
		GameState.setting_changed.disconnect(_on_setting_changed)
	_suite.assert_equal(saved, false, "failed setting write is reported")
	_suite.assert_equal(GameState.get_setting("master_volume"), 2.0, "failed setting write keeps the in-memory authoritative value")
	_suite.assert_equal(_setting_signal_count, 0, "failed setting write emits no success signal")


func _begin_case(case_name: String) -> String:
	var legacy_path := _case_root(case_name).path_join("legacy.json")
	GameState.save_path = legacy_path
	GameState.reset_persistent_data(true)
	return legacy_path


func _on_setting_changed(_setting_id: StringName, _value: Variant) -> void:
	_setting_signal_count += 1


func _base_content_snapshot() -> Dictionary:
	var packs: Array = [{
		"pack_id": "base",
		"pack_version": GAME_VERSION,
		"schema_version": 1,
		"fingerprint_sha256": "1".repeat(64),
	}]
	return {
		"aggregate_sha256": SaveEnvelopeScript.content_snapshot_digest(packs),
		"packs": packs,
	}


func _service_root(legacy_path: String) -> String:
	return legacy_path.get_base_dir().path_join("plane_walker").path_join("save")


func _profile_primary_path(legacy_path: String) -> String:
	return _service_root(legacy_path).path_join("profiles/slot_1/base/primary.json")


func _settings_primary_path(legacy_path: String) -> String:
	return _service_root(legacy_path).path_join("global/settings/primary.json")


func _unique_test_root() -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("game_state_save_%d" % Time.get_ticks_usec())


func _case_root(case_name: String) -> String:
	return _test_root.path_join(case_name)


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var contents := file.get_as_text()
	file.close()
	return contents


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_text(path))
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _resign(document: Dictionary) -> void:
	var unsigned := document.duplicate(true)
	unsigned.erase("integrity")
	unsigned = JSON.parse_string(JSON.stringify(unsigned, "", true, true))
	document["integrity"] = {
		"algorithm": "sha256",
		"digest": SaveEnvelopeScript.sha256_digest(unsigned),
	}


func _empty_active_item_state() -> Dictionary:
	return {
		"schema_version": 1,
		"configured": false,
		"definition": {},
		"generation": 0,
		"next_token": 1,
		"current_frame": -1,
		"cooldown_end_frame": -1,
		"handler_state": {},
		"committed_receipts": {},
	}


func _m1_active_run() -> Dictionary:
	return {
		"schema_version": 1,
		"run_id": "run-game-state-v3",
		"revision": 0,
		"phase": 1,
		"suspended": false,
		"run_seed": 20261001,
		"current_floor": 1,
		"current_room": 0,
		"room_total": 5,
		"run_time_ms": 0,
		"resources": {},
		"stats": {"kills": 0},
		"events": [],
		"build": {},
		"open_offer": {},
		"consumed_offer_ids": [],
		"result": {},
		"config": {"milestone": "M1"},
		"current_floor_index": -1,
		"floor_plan": {},
		"completed_floor_ids": [],
		"run_economy": {},
		"seen_event_ids": [],
		"merchant_state": {},
		"floor_rule_state": {},
	}


func _write_text(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(contents)
	file.flush()
	file.close()


func _remove_tree(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			_remove_tree(path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
