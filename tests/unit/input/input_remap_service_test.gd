extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const InputActionContractScript := preload("res://scripts/input/input_action_contract.gd")
const InputBindingCodecScript := preload("res://scripts/input/input_binding_codec.gd")
const InputProfileStoreScript := preload("res://scripts/input/input_profile_store.gd")
const InputRemapServiceScript := preload("res://scripts/input/input_remap_service.gd")

class FailingStore:
	extends RefCounted

	var validator
	var loaded: Dictionary

	func _init(profile_validator, load_result: Dictionary = {"ok": false, "code": "NOT_FOUND"}) -> void:
		validator = profile_validator
		loaded = load_result.duplicate(true)

	func validate_profile(profile: Dictionary) -> Dictionary:
		return validator.validate_profile(profile)

	func validate_schema_two_profile(profile: Dictionary) -> Dictionary:
		return validator.validate_schema_two_profile(profile)

	func save(_profile: Dictionary) -> Dictionary:
		return {"ok": false, "code": "IO_ERROR", "details": {"injected": true}}

	func load() -> Dictionary:
		return loaded.duplicate(true)


var _suite
var _changed_actions: Array[StringName] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	var root := _unique_test_root()
	var service = InputRemapServiceScript.new()
	service.configure(root)
	service.bindings_changed.connect(_on_bindings_changed)

	var initial: Dictionary = service.load_or_defaults()
	_suite.assert_true(bool(initial.get("ok", false)), "missing profile creates verified defaults")
	_suite.assert_equal(initial.get("code", ""), "DEFAULTS_CREATED", "default creation is explicit")
	_suite.assert_equal(initial.get("profile", {}).get("schema_version"), 3, "new defaults persist semantic schema three")
	_suite.assert_equal(
		service.remappable_actions(),
		[
			&"move_up", &"move_down", &"move_left", &"move_right",
			&"weapon_primary", &"weapon_secondary", &"weapon_utility", &"weapon_skill",
			&"weapon_ultimate", &"time_slot_1", &"time_slot_2", &"character_skill",
			&"dash", &"interact", &"pause",
		],
		"remap data source exposes movement and semantic runtime slots only"
	)
	_assert_default_controller_grammar("defaults load")

	var swap_result: Dictionary = service.remap(&"weapon_primary", &"controller", _joy_button(JOY_BUTTON_Y))
	_suite.assert_true(bool(swap_result.get("ok", false)), "controller binding remaps")
	_suite.assert_equal(_controller_buttons(&"weapon_primary"), [JOY_BUTTON_Y], "primary receives Y")
	_suite.assert_equal(_controller_buttons(&"weapon_secondary"), [JOY_BUTTON_X], "conflicting secondary receives displaced X")
	_suite.assert_true(_changed_actions.has(&"weapon_primary"), "primary remapped action emits change")
	_suite.assert_true(_changed_actions.has(&"weapon_secondary"), "swapped owner emits change")
	_assert_profile_actions_reachable("swap")

	var persisted_service = InputRemapServiceScript.new()
	persisted_service.configure(root)
	var persisted: Dictionary = persisted_service.load_or_defaults()
	_suite.assert_true(bool(persisted.get("ok", false)), "persisted profile reloads")
	_suite.assert_equal(_controller_buttons(&"weapon_primary"), [JOY_BUTTON_Y], "reloaded primary keeps remap")
	_suite.assert_equal(_controller_buttons(&"weapon_secondary"), [JOY_BUTTON_X], "reloaded secondary keeps swap")
	var reset_attack: Dictionary = persisted_service.reset_action(&"weapon_primary")
	_suite.assert_true(bool(reset_attack.get("ok", false)), "single action reset succeeds")
	_suite.assert_equal(_controller_buttons(&"weapon_primary"), [JOY_BUTTON_X], "single action reset restores primary")
	_suite.assert_equal(_controller_buttons(&"weapon_secondary"), [JOY_BUTTON_Y], "single action reset returns displaced binding")
	var restore_swap: Dictionary = persisted_service.remap(&"weapon_primary", &"controller", _joy_button(JOY_BUTTON_Y))
	_suite.assert_true(bool(restore_swap.get("ok", false)), "swap can be reapplied after single reset")

	var before_low_axis := persisted_service.snapshot_profile()
	var low_axis_result: Dictionary = persisted_service.remap(&"weapon_utility", &"controller", _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 0.5))
	_suite.assert_equal(low_axis_result.get("code", ""), "AXIS_BELOW_CAPTURE_THRESHOLD", "low analog noise is rejected")
	_suite.assert_equal(persisted_service.snapshot_profile(), before_low_axis, "low analog noise cannot mutate bindings")

	var steal_pause: Dictionary = persisted_service.remap(&"weapon_primary", &"controller", _joy_button(JOY_BUTTON_START))
	_suite.assert_equal(steal_pause.get("code", ""), "PROTECTED_PAUSE_BINDING", "last Start binding cannot leave pause")
	var replace_pause: Dictionary = persisted_service.remap(&"pause", &"controller", _joy_button(JOY_BUTTON_A))
	_suite.assert_equal(replace_pause.get("code", ""), "PROTECTED_PAUSE_BINDING", "pause cannot replace its only controller binding")
	_suite.assert_equal(_controller_buttons(&"pause"), [JOY_BUTTON_START], "pause remains reachable with Start")

	var validation_store = InputProfileStoreScript.new()
	validation_store.configure(_unique_test_root())
	var failing_service = InputRemapServiceScript.new()
	failing_service.configure("", FailingStore.new(validation_store))
	var before_failure := failing_service.snapshot_profile()
	var failed_save: Dictionary = failing_service.remap(&"weapon_primary", &"controller", _joy_button(JOY_BUTTON_BACK))
	_suite.assert_equal(failed_save.get("code", ""), "IO_ERROR", "persistence failure is returned")
	_suite.assert_equal(failing_service.snapshot_profile(), before_failure, "persistence failure rolls runtime bindings back")

	var labels: Dictionary = persisted_service.binding_labels(&"weapon_primary")
	_suite.assert_true(not (labels.get("keyboard_mouse", []) as Array).is_empty(), "keyboard binding label is available")
	_suite.assert_true(not (labels.get("controller", []) as Array).is_empty(), "controller binding label is available")

	var reset_result: Dictionary = persisted_service.reset_all()
	_suite.assert_true(bool(reset_result.get("ok", false)), "reset all persists defaults")
	_assert_default_controller_grammar("reset all")
	_assert_profile_actions_reachable("reset all")
	_test_legacy_primary_and_backup_migrate_atomically()
	_test_schema_two_primary_migrates_atomically()
	_test_exhausted_schema_two_migration_preserves_source()
	_test_failed_legacy_migration_rolls_runtime_back(validation_store)
	_suite.finish(get_tree())


func _assert_default_controller_grammar(label: String) -> void:
	var expected := {
		&"move_up": ["axis:1:-1", "button:11"],
		&"move_down": ["axis:1:1", "button:12"],
		&"move_left": ["axis:0:-1", "button:13"],
		&"move_right": ["axis:0:1", "button:14"],
		&"weapon_primary": ["button:2"],
		&"weapon_secondary": ["button:3"],
		&"weapon_utility": ["button:4"],
		&"weapon_skill": ["button:5"],
		&"weapon_ultimate": ["button:7"],
		&"dash": ["button:1"],
		&"time_slot_1": ["button:9"],
		&"time_slot_2": ["button:10"],
		&"character_skill": ["button:8"],
		&"interact": ["button:0"],
		&"pause": ["button:6"],
	}
	for action: StringName in expected:
		_suite.assert_equal(
			InputActionContractScript.controller_binding_ids(action),
			expected[action],
			"%s restores %s" % [label, action]
		)


func _assert_profile_actions_reachable(label: String) -> void:
	for action: StringName in InputProfileStoreScript.profile_actions():
		var families: Dictionary = InputActionContractScript.binding_families(action)
		_suite.assert_true(
			bool(families.get("keyboard_mouse", false)),
			"%s keeps %s keyboard/mouse reachable" % [label, action]
		)
		_suite.assert_true(
			bool(families.get("controller", false)),
			"%s keeps %s controller reachable" % [label, action]
		)


func _test_legacy_primary_and_backup_migrate_atomically() -> void:
	var legacy := _legacy_profile_from_project_settings()
	var root := _unique_test_root()
	var store = InputProfileStoreScript.new()
	store.configure(root)
	DirAccess.make_dir_recursive_absolute(root)
	_write_text(store.legacy_primary_path(), JSON.stringify(legacy))

	var service = InputRemapServiceScript.new()
	service.configure(root)
	var migrated: Dictionary = service.load_or_defaults()
	_suite.assert_true(bool(migrated.get("ok", false)), "legacy primary migrates through the production load chain")
	_suite.assert_equal(migrated.get("code", ""), "MIGRATED", "legacy primary migration is explicit")
	_suite.assert_equal(migrated.get("profile", {}).get("schema_version"), 3, "migration persists schema three")
	_suite.assert_equal(
		_controller_binding_ids(&"weapon_primary"),
		["button:2", "axis:5:1"],
		"attack then ranged controller bindings merge into semantic primary"
	)
	_suite.assert_equal(
		_controller_binding_ids(&"time_slot_1"),
		["button:9", "axis:4:1"],
		"stop then rift controller bindings merge into time slot one"
	)
	_suite.assert_equal(
		_controller_binding_ids(&"time_slot_2"),
		["button:10", "button:8"],
		"rewind then accelerate controller bindings merge into time slot two"
	)
	_suite.assert_equal(
		_controller_binding_ids(&"character_skill"),
		["button:15"],
		"schema one reaches schema three through a complete schema-two profile before collision selection"
	)
	for legacy_action: StringName in [
		&"attack", &"heavy_attack", &"ranged_attack",
		&"time_stop", &"time_rewind", &"time_rift", &"time_accelerate",
	]:
		_suite.assert_equal(
			InputMap.action_get_events(legacy_action),
			[],
			"schema two deactivates legacy runtime binding %s" % legacy_action
		)
	var persisted: Dictionary = store.load()
	_suite.assert_equal(persisted.get("source", ""), "primary", "migrated schema three becomes authoritative")
	_suite.assert_equal(persisted.get("profile", {}), migrated.get("profile", {}), "persisted chained migration matches applied profile")
	_suite.assert_true(FileAccess.file_exists(store.legacy_primary_path()), "legacy primary remains as a rollback point")

	var backup_root := _unique_test_root()
	var backup_store = InputProfileStoreScript.new()
	backup_store.configure(backup_root)
	DirAccess.make_dir_recursive_absolute(backup_root)
	_write_text(backup_store.legacy_primary_path(), "{")
	_write_text(backup_store.legacy_backup_path(), JSON.stringify(legacy))
	var backup_service = InputRemapServiceScript.new()
	backup_service.configure(backup_root)
	var recovered: Dictionary = backup_service.load_or_defaults()
	_suite.assert_true(bool(recovered.get("ok", false)), "legacy backup can recover and migrate")
	_suite.assert_equal(recovered.get("code", ""), "RECOVERED_MIGRATED", "backup migration preserves recovery provenance")
	_suite.assert_equal(recovered.get("source", ""), "legacy_backup", "backup migration reports its source")


func _test_schema_two_primary_migrates_atomically() -> void:
	var root := _unique_test_root()
	var store = InputProfileStoreScript.new()
	store.configure(root)
	DirAccess.make_dir_recursive_absolute(root)
	var source := _schema_two_fixture()
	_write_text(store.schema_two_primary_path(), JSON.stringify(source))

	var service = InputRemapServiceScript.new()
	service.configure(root)
	var migrated: Dictionary = service.load_or_defaults()
	_suite.assert_true(bool(migrated.get("ok", false)), "schema-two primary migrates through the production load chain")
	_suite.assert_equal(migrated.get("code", ""), "MIGRATED", "schema-two promotion is explicit")
	_suite.assert_equal(migrated.get("source", ""), "schema_two_primary", "schema-two provenance is retained")
	_suite.assert_equal(migrated.get("profile", {}).get("schema_version"), 3, "schema-two promotion persists schema three")
	_suite.assert_equal(
		migrated.get("profile", {}).get("bindings", {}).get("character_skill", {}),
		{
			"keyboard_mouse": [{"type": "key", "physical_keycode": KEY_C}],
			"controller": [{"type": "joypad_button", "button_index": 8}],
		},
		"schema-two promotion adds the fresh character binding"
	)
	for action_value: Variant in source["bindings"].keys():
		_suite.assert_equal(
			migrated["profile"]["bindings"][action_value],
			source["bindings"][action_value],
			"schema-two promotion preserves %s binding records" % action_value
		)
	_suite.assert_true(FileAccess.file_exists(store.primary_path()), "successful promotion creates the v3 primary")
	_suite.assert_true(FileAccess.file_exists(store.schema_two_primary_path()), "successful promotion preserves the verified v2 rollback source")


func _test_exhausted_schema_two_migration_preserves_source() -> void:
	var root := _unique_test_root()
	var store = InputProfileStoreScript.new()
	store.configure(root)
	DirAccess.make_dir_recursive_absolute(root)
	var source := _schema_two_fixture()
	var actions: Array = source["bindings"].keys()
	for action_value: Variant in actions:
		source["bindings"][action_value]["controller"] = []
	for button_index: int in range(32):
		var action_value: Variant = actions[button_index % actions.size()]
		source["bindings"][action_value]["controller"].append({
			"type": "joypad_button",
			"button_index": button_index,
		})
	var serialized := JSON.stringify(source)
	_write_text(store.schema_two_primary_path(), serialized)

	var service = InputRemapServiceScript.new()
	service.configure(root)
	var runtime_before := service.snapshot_profile()
	var rejected: Dictionary = service.load_or_defaults()
	_suite.assert_equal(rejected.get("code", ""), "NO_REACHABLE_CHARACTER_SKILL", "controller exhaustion rejects production promotion")
	_suite.assert_equal(service.snapshot_profile(), runtime_before, "failed promotion leaves runtime bindings untouched")
	_suite.assert_equal(FileAccess.get_file_as_string(store.schema_two_primary_path()), serialized, "failed promotion preserves the v2 source byte-for-byte")
	_suite.assert_true(not FileAccess.file_exists(store.primary_path()), "failed promotion does not create a partial v3 primary")


func _test_failed_legacy_migration_rolls_runtime_back(validation_store) -> void:
	var legacy := _legacy_profile_from_project_settings()
	_restore_legacy_runtime_defaults()
	var failing_service = InputRemapServiceScript.new()
	failing_service.configure("", FailingStore.new(validation_store, {
		"ok": true,
		"code": "MIGRATION_REQUIRED",
		"profile": legacy,
		"source": "legacy_primary",
	}))
	var before := failing_service.snapshot_profile()
	var result: Dictionary = failing_service.load_or_defaults()
	_suite.assert_equal(result.get("code", ""), "IO_ERROR", "failed migration surfaces persistence error")
	_suite.assert_equal(failing_service.snapshot_profile(), before, "failed migration restores runtime schema-three bindings")
	_suite.assert_equal(
		_controller_binding_ids(&"attack"),
		["button:2"],
		"failed migration restores the legacy runtime compatibility binding"
	)


func _legacy_profile_from_project_settings() -> Dictionary:
	var bindings := {}
	for action: StringName in InputActionContractScript.legacy_profile_actions():
		var action_setting: Dictionary = ProjectSettings.get_setting("input/%s" % action, {})
		var families := {"keyboard_mouse": [], "controller": []}
		for event_value: Variant in action_setting.get("events", []):
			if not event_value is InputEvent:
				continue
			var event := (event_value as InputEvent).duplicate(true) as InputEvent
			event.device = -1
			var record: Dictionary = InputBindingCodecScript.encode(event)
			if record.is_empty():
				continue
			var family := InputBindingCodecScript.binding_family(record)
			(families[family] as Array).append(record)
		bindings[str(action)] = families
	return {"schema_version": 1, "bindings": bindings}


func _restore_legacy_runtime_defaults() -> void:
	for action: StringName in InputActionContractScript.legacy_profile_actions():
		InputMap.action_erase_events(action)
		var action_setting: Dictionary = ProjectSettings.get_setting("input/%s" % action, {})
		for event_value: Variant in action_setting.get("events", []):
			if event_value is InputEvent:
				InputMap.action_add_event(action, (event_value as InputEvent).duplicate(true))


func _controller_binding_ids(action: StringName) -> Array[String]:
	return InputActionContractScript.controller_binding_ids(action)


func _schema_two_fixture() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://tests/fixtures/input/input_profile_v2.json"
	))
	_suite.assert_true(value is Dictionary, "checked-in schema-two fixture parses")
	return (
		_normalize_integral_numbers((value as Dictionary).duplicate(true)) as Dictionary
		if value is Dictionary
		else {}
	)


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


func _write_text(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_suite.assert_true(file != null, "migration fixture opens for write: %s" % path)
	if file == null:
		return
	file.store_string(contents)
	file.close()


func _controller_buttons(action: StringName) -> Array[int]:
	var buttons: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			buttons.append((event as InputEventJoypadButton).button_index)
	return buttons


func _joy_button(button_index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button_index
	event.pressed = true
	return event


func _joy_axis(axis: int, value: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	return event


func _on_bindings_changed(action: StringName) -> void:
	_changed_actions.append(action)


func _unique_test_root() -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("input_remap_service_%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
