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
	profile_b["bindings"]["attack"]["controller"] = [{
		"type": "joypad_button",
		"button_index": JOY_BUTTON_Y,
	}]
	profile_b["bindings"]["heavy_attack"]["controller"] = [{
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
	_suite.assert_equal(recovered.get("source", ""), "backup_1", "backup is recovery source")
	_suite.assert_equal(recovered.get("profile", {}), profile_a, "recovery returns last verified backup")

	_test_invalid_profiles_preserve_primary(store, profile_b)
	_suite.finish(get_tree())


func _test_invalid_profiles_preserve_primary(store, valid_profile: Dictionary) -> void:
	var restore: Dictionary = store.save(valid_profile)
	_suite.assert_true(bool(restore.get("ok", false)), "valid primary restores before rejection cases")
	var invalid_profiles: Array[Dictionary] = []

	var forward := valid_profile.duplicate(true)
	forward["schema_version"] = 2
	invalid_profiles.append(forward)

	var unknown_action := valid_profile.duplicate(true)
	unknown_action["bindings"]["debug_action"] = unknown_action["bindings"]["attack"].duplicate(true)
	invalid_profiles.append(unknown_action)

	var missing_family := valid_profile.duplicate(true)
	missing_family["bindings"]["attack"].erase("controller")
	invalid_profiles.append(missing_family)

	var duplicate_binding := valid_profile.duplicate(true)
	duplicate_binding["bindings"]["heavy_attack"]["controller"] = duplicate_binding["bindings"]["attack"]["controller"].duplicate(true)
	invalid_profiles.append(duplicate_binding)

	var wrong_family := valid_profile.duplicate(true)
	wrong_family["bindings"]["attack"]["controller"] = [{
		"type": "mouse_button",
		"button_index": MOUSE_BUTTON_LEFT,
	}]
	invalid_profiles.append(wrong_family)

	for invalid_profile: Dictionary in invalid_profiles:
		var rejected: Dictionary = store.save(invalid_profile)
		_suite.assert_true(not bool(rejected.get("ok", true)), "invalid profile is rejected")
		_suite.assert_equal(store.load().get("profile", {}), valid_profile, "rejection preserves verified primary")
		_suite.assert_true(not FileAccess.file_exists(store.pending_path()), "rejection leaves no pending file")


func _default_profile() -> Dictionary:
	var bindings := {}
	for action: StringName in InputActionContractScript.required_actions():
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
