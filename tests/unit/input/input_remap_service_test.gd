extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const InputActionContractScript := preload("res://scripts/input/input_action_contract.gd")
const InputProfileStoreScript := preload("res://scripts/input/input_profile_store.gd")
const InputRemapServiceScript := preload("res://scripts/input/input_remap_service.gd")

class FailingStore:
	extends RefCounted

	var validator

	func _init(profile_validator) -> void:
		validator = profile_validator

	func validate_profile(profile: Dictionary) -> Dictionary:
		return validator.validate_profile(profile)

	func save(_profile: Dictionary) -> Dictionary:
		return {"ok": false, "code": "IO_ERROR", "details": {"injected": true}}

	func load() -> Dictionary:
		return {"ok": false, "code": "NOT_FOUND"}


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
	_assert_default_controller_grammar("defaults load")

	var swap_result: Dictionary = service.remap(&"attack", &"controller", _joy_button(JOY_BUTTON_Y))
	_suite.assert_true(bool(swap_result.get("ok", false)), "controller binding remaps")
	_suite.assert_equal(_controller_buttons(&"attack"), [JOY_BUTTON_Y], "attack receives Y")
	_suite.assert_equal(_controller_buttons(&"heavy_attack"), [JOY_BUTTON_X], "conflicting heavy attack receives displaced X")
	_suite.assert_true(_changed_actions.has(&"attack"), "primary remapped action emits change")
	_suite.assert_true(_changed_actions.has(&"heavy_attack"), "swapped owner emits change")
	_suite.assert_equal(InputActionContractScript.missing_required_bindings(), [], "swap preserves reachability")

	var persisted_service = InputRemapServiceScript.new()
	persisted_service.configure(root)
	var persisted: Dictionary = persisted_service.load_or_defaults()
	_suite.assert_true(bool(persisted.get("ok", false)), "persisted profile reloads")
	_suite.assert_equal(_controller_buttons(&"attack"), [JOY_BUTTON_Y], "reloaded attack keeps remap")
	_suite.assert_equal(_controller_buttons(&"heavy_attack"), [JOY_BUTTON_X], "reloaded heavy attack keeps swap")
	var reset_attack: Dictionary = persisted_service.reset_action(&"attack")
	_suite.assert_true(bool(reset_attack.get("ok", false)), "single action reset succeeds")
	_suite.assert_equal(_controller_buttons(&"attack"), [JOY_BUTTON_X], "single action reset restores attack")
	_suite.assert_equal(_controller_buttons(&"heavy_attack"), [JOY_BUTTON_Y], "single action reset returns displaced binding")
	var restore_swap: Dictionary = persisted_service.remap(&"attack", &"controller", _joy_button(JOY_BUTTON_Y))
	_suite.assert_true(bool(restore_swap.get("ok", false)), "swap can be reapplied after single reset")

	var before_low_axis := persisted_service.snapshot_profile()
	var low_axis_result: Dictionary = persisted_service.remap(&"ranged_attack", &"controller", _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 0.5))
	_suite.assert_equal(low_axis_result.get("code", ""), "AXIS_BELOW_CAPTURE_THRESHOLD", "low analog noise is rejected")
	_suite.assert_equal(persisted_service.snapshot_profile(), before_low_axis, "low analog noise cannot mutate bindings")

	var steal_pause: Dictionary = persisted_service.remap(&"attack", &"controller", _joy_button(JOY_BUTTON_START))
	_suite.assert_equal(steal_pause.get("code", ""), "PROTECTED_PAUSE_BINDING", "last Start binding cannot leave pause")
	var replace_pause: Dictionary = persisted_service.remap(&"pause", &"controller", _joy_button(JOY_BUTTON_A))
	_suite.assert_equal(replace_pause.get("code", ""), "PROTECTED_PAUSE_BINDING", "pause cannot replace its only controller binding")
	_suite.assert_equal(_controller_buttons(&"pause"), [JOY_BUTTON_START], "pause remains reachable with Start")

	var validation_store = InputProfileStoreScript.new()
	validation_store.configure(_unique_test_root())
	var failing_service = InputRemapServiceScript.new()
	failing_service.configure("", FailingStore.new(validation_store))
	var before_failure := failing_service.snapshot_profile()
	var failed_save: Dictionary = failing_service.remap(&"attack", &"controller", _joy_button(JOY_BUTTON_BACK))
	_suite.assert_equal(failed_save.get("code", ""), "IO_ERROR", "persistence failure is returned")
	_suite.assert_equal(failing_service.snapshot_profile(), before_failure, "persistence failure rolls runtime bindings back")

	var labels: Dictionary = persisted_service.binding_labels(&"attack")
	_suite.assert_true(not (labels.get("keyboard_mouse", []) as Array).is_empty(), "keyboard binding label is available")
	_suite.assert_true(not (labels.get("controller", []) as Array).is_empty(), "controller binding label is available")

	var reset_result: Dictionary = persisted_service.reset_all()
	_suite.assert_true(bool(reset_result.get("ok", false)), "reset all persists defaults")
	_assert_default_controller_grammar("reset all")
	_suite.assert_equal(InputActionContractScript.missing_required_bindings(), [], "reset keeps every action reachable")
	_suite.finish(get_tree())


func _assert_default_controller_grammar(label: String) -> void:
	var expected := {
		&"move_up": ["axis:1:-1", "button:11"],
		&"move_down": ["axis:1:1", "button:12"],
		&"move_left": ["axis:0:-1", "button:13"],
		&"move_right": ["axis:0:1", "button:14"],
		&"attack": ["button:2"],
		&"heavy_attack": ["button:3"],
		&"ranged_attack": ["axis:5:1"],
		&"dash": ["button:1"],
		&"time_stop": ["button:9"],
		&"time_rewind": ["button:10"],
		&"time_rift": ["axis:4:1"],
		&"time_accelerate": ["button:8"],
		&"interact": ["button:0"],
		&"pause": ["button:6"],
	}
	for action: StringName in expected:
		_suite.assert_equal(
			InputActionContractScript.controller_binding_ids(action),
			expected[action],
			"%s restores %s" % [label, action]
		)


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
