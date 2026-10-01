extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const InputActionContractScript := preload("res://scripts/input/input_action_contract.gd")
const InputBindingCodecScript := preload("res://scripts/input/input_binding_codec.gd")
const InputProfileStoreScript := preload("res://scripts/input/input_profile_store.gd")

var _suite
var _test_root: String


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_root = _unique_test_root()
	var store = InputProfileStoreScript.new()
	store.configure(_test_root)

	var profile_a := _default_profile()
	var first_save: Dictionary = store.save(profile_a)
	_suite.assert_true(bool(first_save.get("ok", false)), "valid profile saves: %s" % first_save)
	_suite.assert_true(not FileAccess.file_exists(store.pending_path()), "pending file is removed after first save")
	var first_load: Dictionary = store.load()
	_suite.assert_equal(first_load.get("profile", {}), profile_a, "saved profile loads exactly")
	_suite.assert_equal(first_load.get("source", ""), "primary", "valid primary is preferred")

	var profile_b := profile_a.duplicate(true)
	profile_b["bindings"]["weapon_primary"]["controller"] = [{
		"type": "joypad_button",
		"button_index": JOY_BUTTON_Y,
	}]
	profile_b["bindings"]["weapon_secondary"]["controller"] = [{
		"type": "joypad_button",
		"button_index": JOY_BUTTON_X,
	}]
	var second_save: Dictionary = store.save(profile_b)
	_suite.assert_true(bool(second_save.get("ok", false)), "second valid profile saves")
	_suite.assert_equal(store.load().get("profile", {}), profile_b, "new primary becomes authoritative")
	_suite.assert_true(FileAccess.file_exists(store.backup_path()), "verified previous primary becomes backup")

	_write_text(store.primary_path(), "{")
	var recovered: Dictionary = store.load()
	_suite.assert_true(bool(recovered.get("ok", false)), "corrupt primary recovers")
	_suite.assert_equal(recovered.get("code", ""), "RECOVERED", "recovery is explicit")
	_suite.assert_equal(recovered.get("source", ""), "backup_4", "schema-four backup is recovery source")
	_suite.assert_equal(recovered.get("profile", {}), profile_a, "recovery returns last verified backup")
	_suite.assert_equal(InputProfileStoreScript.SCHEMA_VERSION, 4, "input profiles advance exactly to schema four")
	_suite.assert_equal(InputProfileStoreScript.profile_actions().size(), 16, "schema four has one active-item action")
	_suite.assert_true(InputProfileStoreScript.profile_actions().has(&"active_item"), "schema four owns active_item")

	_test_invalid_profiles_preserve_primary(store, profile_b)
	_test_recovery_order_across_all_supported_schemas()
	_suite.finish(get_tree())


func _test_invalid_profiles_preserve_primary(store, valid_profile: Dictionary) -> void:
	var restore: Dictionary = store.save(valid_profile)
	_suite.assert_true(bool(restore.get("ok", false)), "valid primary restores before rejection cases")
	var invalid_profiles: Array[Dictionary] = []

	var forward := valid_profile.duplicate(true)
	forward["schema_version"] = 5
	invalid_profiles.append(forward)

	var unknown_action := valid_profile.duplicate(true)
	unknown_action["bindings"]["debug_action"] = unknown_action["bindings"]["weapon_primary"].duplicate(true)
	invalid_profiles.append(unknown_action)

	var missing_family := valid_profile.duplicate(true)
	missing_family["bindings"]["weapon_primary"].erase("controller")
	invalid_profiles.append(missing_family)

	var duplicate_binding := valid_profile.duplicate(true)
	duplicate_binding["bindings"]["weapon_secondary"]["controller"] = duplicate_binding["bindings"]["weapon_primary"]["controller"].duplicate(true)
	invalid_profiles.append(duplicate_binding)

	var wrong_family := valid_profile.duplicate(true)
	wrong_family["bindings"]["weapon_primary"]["controller"] = [{
		"type": "mouse_button",
		"button_index": MOUSE_BUTTON_LEFT,
	}]
	invalid_profiles.append(wrong_family)

	for invalid_profile: Dictionary in invalid_profiles:
		var rejected: Dictionary = store.save(invalid_profile)
		_suite.assert_true(not bool(rejected.get("ok", true)), "invalid profile is rejected")
		_suite.assert_equal(store.load().get("profile", {}), valid_profile, "rejection preserves verified primary")
		_suite.assert_true(not FileAccess.file_exists(store.pending_path()), "rejection leaves no pending file")


func _test_recovery_order_across_all_supported_schemas() -> void:
	var store = InputProfileStoreScript.new()
	store.configure(_unique_test_root())
	DirAccess.make_dir_recursive_absolute(store.primary_path().get_base_dir())
	var current := _default_profile()
	var schema_three := _schema_three_profile(current)
	var schema_two := _normalize_integral_numbers(_schema_two_fixture()) as Dictionary
	var legacy := _legacy_profile()
	_write_text(store.legacy_backup_path(), JSON.stringify(legacy))
	_write_text(store.legacy_primary_path(), JSON.stringify(legacy))
	_write_text(store.schema_two_backup_path(), JSON.stringify(schema_two))
	_write_text(store.schema_two_primary_path(), JSON.stringify(schema_two))
	_write_text(store.schema_three_backup_path(), JSON.stringify(schema_three))
	_write_text(store.schema_three_primary_path(), JSON.stringify(schema_three))
	_write_text(store.backup_path(), JSON.stringify(current))
	_write_text(store.primary_path(), JSON.stringify(current))

	var current_primary: Dictionary = store.load()
	_suite.assert_equal(current_primary.get("source", ""), "primary", "verified v4 primary wins the recovery chain")

	_write_text(store.primary_path(), "{")
	var current_backup: Dictionary = store.load()
	_suite.assert_equal(current_backup.get("source", ""), "backup_4", "verified v4 backup follows corrupt v4 primary")
	_suite.assert_equal(current_backup.get("code", ""), "RECOVERED", "v4 backup recovery is explicit")

	_write_text(store.backup_path(), "{")
	var schema_three_primary: Dictionary = store.load()
	_suite.assert_equal(schema_three_primary.get("source", ""), "schema_three_primary", "verified v3 primary follows both v4 candidates")
	_suite.assert_equal(schema_three_primary.get("code", ""), "MIGRATION_REQUIRED", "v3 primary requires promotion")
	_suite.assert_equal(schema_three_primary.get("profile", {}), schema_three, "v3 primary returns without mutation")

	_write_text(store.schema_three_primary_path(), "{")
	var schema_three_backup: Dictionary = store.load()
	_suite.assert_equal(schema_three_backup.get("source", ""), "schema_three_backup", "verified v3 backup follows corrupt v3 primary")
	_suite.assert_equal(schema_three_backup.get("code", ""), "RECOVERED_MIGRATION_REQUIRED", "v3 backup keeps recovery provenance")

	_write_text(store.schema_three_backup_path(), "{")
	var schema_two_primary: Dictionary = store.load()
	_suite.assert_equal(schema_two_primary.get("source", ""), "schema_two_primary", "verified v2 primary follows v4/v3 candidates")
	_suite.assert_equal(schema_two_primary.get("code", ""), "MIGRATION_REQUIRED", "v2 primary requires promotion")
	_suite.assert_equal(schema_two_primary.get("profile", {}), schema_two, "v2 primary returns without mutation")

	_write_text(store.schema_two_primary_path(), "{")
	var schema_two_backup: Dictionary = store.load()
	_suite.assert_equal(schema_two_backup.get("source", ""), "schema_two_backup", "verified v2 backup follows corrupt v2 primary")
	_suite.assert_equal(schema_two_backup.get("code", ""), "RECOVERED_MIGRATION_REQUIRED", "v2 backup keeps recovery provenance")

	_write_text(store.schema_two_backup_path(), "{")
	var legacy_primary: Dictionary = store.load()
	_suite.assert_equal(legacy_primary.get("source", ""), "legacy_primary", "verified v1 primary follows all v3/v2 candidates")
	_suite.assert_equal(legacy_primary.get("code", ""), "MIGRATION_REQUIRED", "v1 primary requires chained migration")

	_write_text(store.legacy_primary_path(), "{")
	var legacy_backup: Dictionary = store.load()
	_suite.assert_true(bool(legacy_backup.get("ok", false)), "legacy backup remains the final migration rollback point")
	_suite.assert_equal(legacy_backup.get("code", ""), "RECOVERED_MIGRATION_REQUIRED", "legacy backup recovery is explicit")
	_suite.assert_equal(legacy_backup.get("source", ""), "legacy_backup", "legacy backup is last in the recovery chain")


func _default_profile() -> Dictionary:
	var bindings := {}
	for action: StringName in InputProfileStoreScript.profile_actions():
		var families := {
			"keyboard_mouse": [],
			"controller": [],
		}
		for event: InputEvent in InputMap.action_get_events(action):
			var record: Dictionary = InputBindingCodecScript.encode(event)
			if record.is_empty():
				continue
			var family := InputBindingCodecScript.binding_family(record)
			(families[family] as Array).append(record)
		bindings[str(action)] = families
	return {
		"schema_version": 4,
		"bindings": bindings,
	}


func _schema_three_profile(current: Dictionary) -> Dictionary:
	var schema_three := current.duplicate(true)
	schema_three["schema_version"] = 3
	schema_three["bindings"].erase("active_item")
	return schema_three


func _schema_two_fixture() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/input/input_profile_v2.json"
	))
	_suite.assert_true(value is Dictionary, "checked-in schema-two profile parses")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _normalize_integral_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized := {}
		for key: Variant in (value as Dictionary).keys():
			normalized[key] = _normalize_integral_numbers((value as Dictionary)[key])
		return normalized
	if value is Array:
		var normalized: Array = []
		for item: Variant in value as Array:
			normalized.append(_normalize_integral_numbers(item))
		return normalized
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), floorf(float(value))):
		return int(value)
	return value


func _legacy_profile() -> Dictionary:
	var bindings := {}
	for action: StringName in InputActionContractScript.legacy_profile_actions():
		var families := {
			"keyboard_mouse": [],
			"controller": [],
		}
		for event: InputEvent in InputMap.action_get_events(action):
			var record: Dictionary = InputBindingCodecScript.encode(event)
			if record.is_empty():
				continue
			var family := InputBindingCodecScript.binding_family(record)
			(families[family] as Array).append(record)
		bindings[str(action)] = families
	return {
		"schema_version": 1,
		"bindings": bindings,
	}


func _write_text(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_suite.assert_true(file != null, "test fixture opens for write: %s" % path)
	if file == null:
		return
	file.store_string(contents)
	file.close()


func _unique_test_root() -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("input_profile_store_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
