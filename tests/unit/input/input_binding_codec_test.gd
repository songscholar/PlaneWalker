extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const InputBindingCodecScript := preload("res://scripts/input/input_binding_codec.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_supported_round_trips()
	_test_keycode_fallback()
	_test_invalid_records()
	_test_unsupported_events()
	_suite.finish(get_tree())


func _test_supported_round_trips() -> void:
	var records: Array[Dictionary] = [
		{"type": "key", "physical_keycode": KEY_Q},
		{"type": "mouse_button", "button_index": MOUSE_BUTTON_LEFT},
		{"type": "joypad_button", "button_index": JOY_BUTTON_X},
		{"type": "joypad_button", "button_index": 31},
		{"type": "joypad_axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "direction": 1},
		{"type": "joypad_axis", "axis": JOY_AXIS_LEFT_Y, "direction": -1},
	]
	for record: Dictionary in records:
		var decoded: InputEvent = InputBindingCodecScript.decode(record)
		_suite.assert_true(decoded != null, "supported record decodes: %s" % record)
		if decoded == null:
			continue
		_suite.assert_equal(decoded.device, -1, "decoded event accepts every device")
		_suite.assert_equal(InputBindingCodecScript.encode(decoded), record, "binding round-trips")
		_suite.assert_true(not InputBindingCodecScript.canonical_id(record).is_empty(), "binding has canonical id")

	_suite.assert_equal(
		InputBindingCodecScript.binding_family(records[0]),
		"keyboard_mouse",
		"keys belong to keyboard/mouse"
	)
	_suite.assert_equal(
		InputBindingCodecScript.binding_family(records[2]),
		"controller",
		"joypad buttons belong to controller"
	)


func _test_keycode_fallback() -> void:
	var event := InputEventKey.new()
	event.device = -1
	event.keycode = KEY_ESCAPE
	_suite.assert_equal(
		InputBindingCodecScript.encode(event),
		{"type": "key", "physical_keycode": KEY_ESCAPE},
		"project key bindings without a physical code encode deterministically"
	)


func _test_invalid_records() -> void:
	var invalid_records: Array[Dictionary] = [
		{},
		{"type": "key", "physical_keycode": 0},
		{"type": "key", "physical_keycode": KEY_Q, "device": 2},
		{"type": "mouse_button", "button_index": 0},
		{"type": "joypad_button", "button_index": -1},
		{"type": "joypad_button", "button_index": 32},
		{"type": "joypad_axis", "axis": JOY_AXIS_LEFT_X, "direction": 0},
		{"type": "joypad_axis", "axis": -1, "direction": 1},
		{"type": "unknown", "value": 1},
	]
	for record: Dictionary in invalid_records:
		_suite.assert_true(InputBindingCodecScript.decode(record) == null, "invalid record is rejected: %s" % record)
		_suite.assert_equal(InputBindingCodecScript.canonical_id(record), "", "invalid record has no canonical id")


func _test_unsupported_events() -> void:
	var gesture := InputEventMagnifyGesture.new()
	_suite.assert_equal(InputBindingCodecScript.encode(gesture), {}, "unsupported event does not serialize")
