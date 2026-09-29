extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")

const GAME_VERSION := "0.4.0-dev"
const PROFILE_ID := "slot_1"
const SAVE_DOMAIN := "base"

var _test_root: String = ""
var _clock_tick: int = 0
var _fault_target: StringName = &""
var _fault_root: String = ""
var _reentrant_service: RefCounted
var _reentrant_result: RefCounted
var _reentrant_attempted: bool = false
var _observed_fault_points: Array[StringName] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_root = _unique_test_root()
	_remove_tree(_test_root)

	_test_first_save_and_settings_isolation(suite)
	_test_profile_and_domain_isolation(suite)
	_test_three_save_backup_order(suite)
	_test_all_fault_points_are_stable(suite)
	_test_pending_corruption_fails_before_promotion(suite)
	_test_fault_before_promotion_preserves_primary_and_pending_recovers(suite)
	_test_primary_corruption_recovers_from_backup_one(suite)
	_test_backup_two_recovery_and_all_corrupt_result(suite)
	_test_forward_version_refuses_backup_fallback(suite)
	_test_content_mismatch_refuses_backup_fallback(suite)
	_test_write_reentry_returns_busy(suite)
	_test_path_traversal_is_rejected(suite)

	_remove_tree(_test_root)
	suite.finish(get_tree())


func _test_first_save_and_settings_isolation(suite) -> void:
	var service = _new_service("first_save", _content_snapshot("1"), suite)
	var first = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"runs_completed": 1})
	suite.assert_true(first.ok, "first profile save succeeds")
	suite.assert_equal(first.metadata.get("sequence"), 0, "first profile sequence starts at zero")
	suite.assert_true(FileAccess.file_exists(_profile_path("first_save", "primary.json")), "first save creates primary")
	suite.assert_true(not FileAccess.file_exists(_profile_path("first_save", "backup_1.json")), "first save does not invent backup one")

	var loaded = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_true(loaded.ok, "first profile loads")
	suite.assert_equal(loaded.payload, {"runs_completed": 1.0}, "profile payload round trips through canonical JSON")

	var settings_payload := _settings_payload("en", 0.65)
	var settings_saved = service.save_settings(settings_payload)
	suite.assert_true(settings_saved.ok, "global settings save succeeds")
	suite.assert_equal(service.load_settings().payload, settings_payload, "global settings round trip independently")

	var reset = service.reset_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_true(reset.ok, "profile reset succeeds")
	suite.assert_equal(service.load_profile(PROFILE_ID, SAVE_DOMAIN).code, &"NOT_FOUND", "reset removes only requested profile")
	suite.assert_equal(service.load_settings().payload, settings_payload, "profile reset preserves global settings")

	service.save_settings(_settings_payload("zh_CN", 0.5))
	_write_text(_case_root("first_save").path_join("global/settings/primary.json"), "settings-corrupt")
	var recovered_settings = service.load_settings()
	suite.assert_equal(recovered_settings.code, &"RECOVERED", "global settings use the same recovery policy")
	suite.assert_equal(recovered_settings.source_kind, &"backup_1", "global settings recover from their own backup")
	suite.assert_equal(recovered_settings.payload, settings_payload, "global settings backup retains previous preferences")


func _test_profile_and_domain_isolation(suite) -> void:
	var service = _new_service("scope_isolation", _content_snapshot("d"), suite)
	service.save_profile("slot_1", "base", {"scope": "slot-one-base"})
	service.save_profile("slot_2", "base", {"scope": "slot-two-base"})
	service.save_profile("slot_1", "modded", {"scope": "slot-one-modded"})

	suite.assert_equal(service.load_profile("slot_1", "base").payload.get("scope"), "slot-one-base", "base profile remains isolated")
	suite.assert_equal(service.load_profile("slot_2", "base").payload.get("scope"), "slot-two-base", "second profile remains isolated")
	suite.assert_equal(service.load_profile("slot_1", "modded").payload.get("scope"), "slot-one-modded", "mod domain remains isolated")
	service.reset_profile("slot_1", "modded")
	suite.assert_equal(service.load_profile("slot_1", "modded").code, &"NOT_FOUND", "reset removes only one domain")
	suite.assert_equal(service.load_profile("slot_1", "base").payload.get("scope"), "slot-one-base", "domain reset preserves base save")


func _test_three_save_backup_order(suite) -> void:
	var service = _new_service("backup_order", _content_snapshot("2"), suite)
	for value: int in [1, 2, 3]:
		var result = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": value})
		suite.assert_true(result.ok, "profile save %d succeeds" % value)

	var primary := _read_json(_profile_path("backup_order", "primary.json"), suite)
	var backup_one := _read_json(_profile_path("backup_order", "backup_1.json"), suite)
	var backup_two := _read_json(_profile_path("backup_order", "backup_2.json"), suite)
	suite.assert_equal(primary.get("sequence"), 2.0, "third save is primary sequence two")
	suite.assert_equal(primary.get("payload", {}).get("value"), 3.0, "primary contains newest payload")
	suite.assert_equal(backup_one.get("sequence"), 1.0, "backup one contains previous sequence")
	suite.assert_equal(backup_one.get("payload", {}).get("value"), 2.0, "backup one contains second payload")
	suite.assert_equal(backup_two.get("sequence"), 0.0, "backup two contains oldest retained sequence")
	suite.assert_equal(backup_two.get("payload", {}).get("value"), 1.0, "backup two contains first payload")

	_write_text(_profile_path("backup_order", "backup_2.json"), "corrupt-oldest-backup")
	suite.assert_true(service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": 4}).ok, "save proceeds after quarantining corrupt backup two")
	suite.assert_true(_quarantine_contains("backup_order", "corrupt-oldest-backup"), "corrupt rotation destination is preserved")
	suite.assert_equal(_read_json(_profile_path("backup_order", "backup_2.json"), suite).get("payload", {}).get("value"), 2.0, "verified backup one replaces quarantined backup two")


func _test_all_fault_points_are_stable(suite) -> void:
	_observed_fault_points.clear()
	var service = _new_service("fault_points", _content_snapshot("e"), suite, Callable(self, "_record_fault"))
	var saved = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": 1})
	suite.assert_true(saved.ok, "fault observation save succeeds")
	suite.assert_equal(_observed_fault_points, [
		&"after_pending_write",
		&"after_pending_verify",
		&"after_backup_2",
		&"after_backup_1",
		&"before_primary_promote",
		&"after_primary_promote",
	], "fault injector receives every stable transaction point in order")


func _test_pending_corruption_fails_before_promotion(suite) -> void:
	_fault_root = _case_root("pending_corruption")
	var service = _new_service("pending_corruption", _content_snapshot("3"), suite, Callable(self, "_corrupt_pending_fault"))
	var result = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": 1})
	suite.assert_true(not result.ok, "corrupt pending transaction fails")
	suite.assert_true(result.code in [&"CORRUPT", &"IO_ERROR"], "corrupt pending returns a structured persistence failure")
	suite.assert_true(not FileAccess.file_exists(_profile_path("pending_corruption", "primary.json")), "corrupt pending is never promoted")


func _test_fault_before_promotion_preserves_primary_and_pending_recovers(suite) -> void:
	var service = _new_service("pending_recovery", _content_snapshot("4"), suite)
	suite.assert_true(service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "old"}).ok, "recovery fixture primary saves")

	_fault_target = &"before_primary_promote"
	service.set_fault_injector(Callable(self, "_targeted_fault"))
	var failed = service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "pending"})
	suite.assert_true(not failed.ok, "injected pre-promotion fault fails the transaction")
	suite.assert_equal(_read_json(_profile_path("pending_recovery", "primary.json"), suite).get("payload", {}).get("value"), "old", "pre-promotion fault preserves old primary")
	suite.assert_equal(_read_json(_profile_path("pending_recovery", "pending.tmp"), suite).get("payload", {}).get("value"), "pending", "verified pending remains recoverable")

	service.set_fault_injector(Callable())
	_write_text(_profile_path("pending_recovery", "primary.json"), "primary-corrupt")
	var recovered = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_true(recovered.ok, "corrupt primary recovers")
	suite.assert_equal(recovered.code, &"RECOVERED", "pending recovery is reported")
	suite.assert_equal(recovered.source_kind, &"pending", "pending is first recovery candidate")
	suite.assert_equal(recovered.payload.get("value"), "pending", "pending payload is restored")
	suite.assert_true(_quarantine_contains("pending_recovery", "primary-corrupt"), "corrupt primary bytes are quarantined exactly")


func _test_primary_corruption_recovers_from_backup_one(suite) -> void:
	var service = _new_service("backup_one_recovery", _content_snapshot("5"), suite)
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": 1})
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": 2})
	_write_text(_profile_path("backup_one_recovery", "primary.json"), "{bad-json")

	var inspected = service.inspect_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(inspected.code, &"CORRUPT", "inspection reports corruption without recovery")
	suite.assert_true(FileAccess.file_exists(_profile_path("backup_one_recovery", "primary.json")), "inspection is non-destructive")

	var recovered = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(recovered.code, &"RECOVERED", "backup one recovery is reported")
	suite.assert_equal(recovered.source_kind, &"backup_1", "backup one is selected after absent pending")
	suite.assert_equal(recovered.payload.get("value"), 1.0, "backup one payload is restored")
	suite.assert_true(SaveEnvelopeScript.validate(_read_json(_profile_path("backup_one_recovery", "primary.json"), suite), &"profile", PROFILE_ID, SAVE_DOMAIN).ok, "repaired primary is verified")


func _test_backup_two_recovery_and_all_corrupt_result(suite) -> void:
	var service = _new_service("backup_two_recovery", _content_snapshot("6"), suite)
	for value: int in [1, 2, 3]:
		service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": value})
	_write_text(_profile_path("backup_two_recovery", "primary.json"), "broken-primary")
	_write_text(_profile_path("backup_two_recovery", "backup_1.json"), "broken-backup-one")

	var recovered = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(recovered.code, &"RECOVERED", "backup two recovery is reported")
	suite.assert_equal(recovered.source_kind, &"backup_2", "backup two is final recovery candidate")
	suite.assert_equal(recovered.payload.get("value"), 1.0, "backup two payload is restored")
	suite.assert_true(_quarantine_file_count("backup_two_recovery") >= 2, "each corrupt candidate is quarantined")

	var all_corrupt = _new_service("all_corrupt", _content_snapshot("7"), suite)
	for value: int in [1, 2, 3]:
		all_corrupt.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": value})
	for file_name: String in ["primary.json", "backup_1.json", "backup_2.json"]:
		_write_text(_profile_path("all_corrupt", file_name), "corrupt-%s" % file_name)
	var failed = all_corrupt.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(failed.code, &"CORRUPT", "all corrupt candidates fail closed")
	suite.assert_true(_quarantine_file_count("all_corrupt") >= 3, "all corrupt candidates are preserved in quarantine")


func _test_forward_version_refuses_backup_fallback(suite) -> void:
	var service = _new_service("forward_refusal", _content_snapshot("8"), suite)
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "backup"})
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "primary"})
	var future := _read_json(_profile_path("forward_refusal", "primary.json"), suite)
	future["schema_version"] = 2
	_write_text(_profile_path("forward_refusal", "primary.json"), JSON.stringify(future, "", true, true))

	var result = service.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(result.code, &"FORWARD_VERSION", "future primary is refused explicitly")
	suite.assert_true(FileAccess.file_exists(_profile_path("forward_refusal", "primary.json")), "future primary is not quarantined")
	suite.assert_equal(_quarantine_file_count("forward_refusal"), 0, "future primary never triggers backup rollback")


func _test_content_mismatch_refuses_backup_fallback(suite) -> void:
	var service = _new_service("content_refusal", _content_snapshot("9"), suite)
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "backup"})
	service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "primary"})
	var incompatible = _new_service("content_refusal", _content_snapshot("a"), suite)

	var result = incompatible.load_profile(PROFILE_ID, SAVE_DOMAIN)
	suite.assert_equal(result.code, &"CONTENT_MISMATCH", "incompatible content snapshot is refused")
	suite.assert_equal(result.metadata.get("actual_aggregate"), _content_snapshot("9").get("aggregate_sha256"), "mismatch reports stored aggregate")
	suite.assert_equal(_quarantine_file_count("content_refusal"), 0, "content mismatch never triggers backup rollback")


func _test_write_reentry_returns_busy(suite) -> void:
	_reentrant_service = _new_service("write_reentry", _content_snapshot("b"), suite, Callable(self, "_reentrant_fault"))
	_reentrant_result = null
	_reentrant_attempted = false
	var outer = _reentrant_service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "outer"})
	suite.assert_true(outer.ok, "outer write succeeds after reentry probe")
	suite.assert_true(_reentrant_result != null, "fault callback attempted a nested write")
	if _reentrant_result != null:
		suite.assert_equal(_reentrant_result.code, &"BUSY", "nested write is rejected as busy")
	suite.assert_equal(_reentrant_service.load_profile(PROFILE_ID, SAVE_DOMAIN).payload.get("value"), "outer", "busy nested write cannot replace outer payload")


func _test_path_traversal_is_rejected(suite) -> void:
	var service = _new_service("path_safety", _content_snapshot("c"), suite)
	suite.assert_equal(service.save_profile("../slot", SAVE_DOMAIN, {}).code, &"INVALID_ARGUMENT", "profile traversal is rejected")
	suite.assert_equal(service.save_profile(PROFILE_ID, "../mod", {}).code, &"INVALID_ARGUMENT", "domain traversal is rejected")
	suite.assert_equal(service.load_profile("/absolute", SAVE_DOMAIN).code, &"INVALID_ARGUMENT", "absolute profile id is rejected")
	suite.assert_true(not DirAccess.dir_exists_absolute(_case_root("path_safety").path_join("profiles")), "invalid ids cause no profile filesystem access")


func _new_service(case_name: String, snapshot: Dictionary, suite, fault_injector: Callable = Callable()):
	var service = SaveServiceScript.new()
	var configured = service.configure(
		_case_root(case_name),
		GAME_VERSION,
		snapshot,
		Callable(self, "_clock"),
		fault_injector
	)
	suite.assert_true(configured.ok, "%s service configures" % case_name)
	return service


func _clock() -> String:
	var minute := _clock_tick % 60
	var hour := 8 + int(_clock_tick / 60)
	_clock_tick += 1
	return "2026-09-28T%02d:%02d:00Z" % [hour, minute]


func _content_snapshot(fill_character: String) -> Dictionary:
	var packs: Array = [{
		"pack_id": "base",
		"pack_version": GAME_VERSION,
		"schema_version": 1,
		"fingerprint_sha256": fill_character.repeat(64),
	}]
	return {
		"aggregate_sha256": SaveEnvelopeScript.content_snapshot_digest(packs),
		"packs": packs,
	}


func _settings_payload(locale: String, volume: float) -> Dictionary:
	return {
		"locale": locale,
		"master_volume": volume,
		"master_muted": false,
		"camera_shake_enabled": true,
		"hit_flash_enabled": true,
		"reduced_motion": false,
	}


func _corrupt_pending_fault(point: StringName) -> bool:
	if point == &"after_pending_write":
		_write_text(_fault_root.path_join("profiles").path_join(PROFILE_ID).path_join(SAVE_DOMAIN).path_join("pending.tmp"), "{")
	return false


func _targeted_fault(point: StringName) -> bool:
	return point == _fault_target


func _reentrant_fault(point: StringName) -> bool:
	if point == &"after_pending_write" and not _reentrant_attempted:
		_reentrant_attempted = true
		_reentrant_result = _reentrant_service.save_profile(PROFILE_ID, SAVE_DOMAIN, {"value": "nested"})
	return false


func _record_fault(point: StringName) -> bool:
	_observed_fault_points.append(point)
	return false


func _unique_test_root() -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("save_service_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])


func _case_root(case_name: String) -> String:
	return _test_root.path_join(case_name)


func _profile_path(case_name: String, file_name: String) -> String:
	return _case_root(case_name).path_join("profiles").path_join(PROFILE_ID).path_join(SAVE_DOMAIN).path_join(file_name)


func _quarantine_directory(case_name: String) -> String:
	return _profile_path(case_name, "quarantine")


func _quarantine_file_count(case_name: String) -> int:
	var directory_path := _quarantine_directory(case_name)
	if not DirAccess.dir_exists_absolute(directory_path):
		return 0
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return 0
	var count := 0
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir():
			count += 1
		entry = directory.get_next()
	directory.list_dir_end()
	return count


func _quarantine_contains(case_name: String, expected_bytes: String) -> bool:
	var directory_path := _quarantine_directory(case_name)
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir():
			var file := FileAccess.open(directory_path.path_join(entry), FileAccess.READ)
			if file != null:
				var contents := file.get_as_text()
				file.close()
				if contents == expected_bytes:
					directory.list_dir_end()
					return true
		entry = directory.get_next()
	directory.list_dir_end()
	return false


func _write_text(path: String, contents: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(contents)
	file.flush()
	file.close()


func _read_json(path: String, suite) -> Dictionary:
	if not FileAccess.file_exists(path):
		suite.assert_true(false, "%s exists" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		suite.assert_true(false, "%s opens" % path)
		return {}
	var contents := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(contents)
	suite.assert_true(parsed is Dictionary, "%s parses as JSON object" % path)
	return parsed as Dictionary if parsed is Dictionary else {}


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
