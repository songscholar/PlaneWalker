extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const GameStateScript := preload("res://autoload/game_state.gd")
const InputStoreScript := preload("res://scripts/input/input_profile_store.gd")
const BindingCodecScript := preload("res://scripts/input/input_binding_codec.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var original_user := OS.get_environment("PLANEWALKER_USER_DATA_DIR")
	var original_test := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	var base := original_test.path_join("runtime_user_data_%d" % Time.get_ticks_usec())
	var user_root := base.path_join("portable")
	var fallback_root := base.path_join("test_fallback")
	OS.set_environment("PLANEWALKER_USER_DATA_DIR", user_root)
	OS.set_environment("PLANEWALKER_TEST_DATA_DIR", fallback_root)
	var state := GameStateScript.new()
	state.call("_ready")
	_suite.assert_equal(state.get("save_path"), user_root.path_join("plane_walker_save.json"), "portable environment owns default GameState save path")
	if str(state.get("save_path")).begins_with(user_root + "/"):
		_suite.assert_true(bool(state.call("save_persistent")), "GameState writes the isolated versioned save")
	_suite.assert_true(FileAccess.file_exists(user_root.path_join("plane_walker/save/global/settings/primary.json")), "settings stay inside portable data root")
	var store := InputStoreScript.new()
	store.configure()
	_suite.assert_true(store.primary_path().begins_with(user_root + "/"), "default input profile uses portable root")
	if store.primary_path().begins_with(user_root + "/"):
		_suite.assert_true(bool(store.save(_default_profile()).get("ok", false)), "input profile saves in isolated root")
		_suite.assert_true(FileAccess.file_exists(store.primary_path()), "physical input file exists in isolated root")
	_suite.assert_true(not DirAccess.dir_exists_absolute(fallback_root), "primary runtime environment takes precedence over test fallback")
	state.free()
	OS.unset_environment("PLANEWALKER_USER_DATA_DIR")
	state = GameStateScript.new()
	state.call("_ready")
	_suite.assert_equal(state.get("save_path"), fallback_root.path_join("plane_walker_save.json"), "test environment provides default save fallback")
	store.configure()
	_suite.assert_true(store.primary_path().begins_with(fallback_root + "/"), "test environment provides default input fallback")
	state.free()
	var explicit_root := base.path_join("explicit")
	state = GameStateScript.new()
	state.set("save_path", explicit_root.path_join("custom-save.json"))
	state.call("_ready")
	_suite.assert_equal(state.get("save_path"), explicit_root.path_join("custom-save.json"), "explicit save path is preserved")
	store.configure(explicit_root)
	_suite.assert_equal(store.primary_path(), explicit_root.path_join(InputStoreScript.PRIMARY_FILE), "explicit input root is preserved")
	state.free()
	OS.set_environment("PLANEWALKER_USER_DATA_DIR", "relative/invalid")
	state = GameStateScript.new()
	state.call("_ready")
	_suite.assert_equal(state.get("save_path"), "", "invalid environment leaves persistence unconfigured")
	if str(state.get("save_path")).is_empty():
		_suite.assert_true(not bool(state.call("save_persistent")), "invalid environment rejects persistence without falling back to personal save")
	store.configure()
	if not store.primary_path().begins_with(ProjectSettings.globalize_path("user://")):
		_suite.assert_true(not bool(store.save(_default_profile()).get("ok", false)), "invalid environment rejects input persistence")
	state.free()
	_restore_environment("PLANEWALKER_USER_DATA_DIR", original_user)
	_restore_environment("PLANEWALKER_TEST_DATA_DIR", original_test)
	_suite.finish(get_tree())


func _restore_environment(key: String, value: String) -> void:
	if value.is_empty():
		OS.unset_environment(key)
	else:
		OS.set_environment(key, value)


func _default_profile() -> Dictionary:
	var bindings := {}
	for action: StringName in InputStoreScript.profile_actions():
		var families := {"keyboard_mouse": [], "controller": []}
		for event: InputEvent in InputMap.action_get_events(action):
			var record := BindingCodecScript.encode(event)
			if not record.is_empty():
				(families[BindingCodecScript.binding_family(record)] as Array).append(record)
		bindings[str(action)] = families
	return {"schema_version": InputStoreScript.SCHEMA_VERSION, "bindings": bindings}
