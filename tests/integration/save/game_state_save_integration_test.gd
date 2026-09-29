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
	_test_settings_and_profile_statistics_round_trip()
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

	var blocked_parent := _case_root("blocked_setting").path_join("not-a-directory")
	_write_text(blocked_parent, "block directory creation")
	GameState.save_path = blocked_parent.path_join("legacy.json")
	GameState.persistent = GameState._default_persistent_data()
	_setting_signal_count = 0
	if not GameState.setting_changed.is_connected(_on_setting_changed):
		GameState.setting_changed.connect(_on_setting_changed)
	var saved: Variant = GameState.set_setting("master_volume", 0.2)
	if GameState.setting_changed.is_connected(_on_setting_changed):
		GameState.setting_changed.disconnect(_on_setting_changed)
	_suite.assert_equal(saved, false, "failed setting write is reported")
	_suite.assert_equal(GameState.get_setting("master_volume"), 0.2, "failed setting write keeps the in-memory authoritative value")
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
