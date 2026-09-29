class_name InputBindingCodec
extends RefCounted

const KEY_FIELDS: Array[String] = ["physical_keycode", "type"]
const BUTTON_FIELDS: Array[String] = ["button_index", "type"]
const AXIS_FIELDS: Array[String] = ["axis", "direction", "type"]


static func encode(event: InputEvent) -> Dictionary:
	if event == null or event.device != -1:
		return {}
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		var record := {"type": "key", "physical_keycode": code}
		return record if _is_valid_record(record) else {}
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		var record := {"type": "mouse_button", "button_index": mouse_button.button_index}
		return record if _is_valid_record(record) else {}
	if event is InputEventJoypadButton:
		var joy_button := event as InputEventJoypadButton
		var record := {"type": "joypad_button", "button_index": joy_button.button_index}
		return record if _is_valid_record(record) else {}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if is_zero_approx(motion.axis_value):
			return {}
		var record := {
			"type": "joypad_axis",
			"axis": motion.axis,
			"direction": -1 if motion.axis_value < 0.0 else 1,
		}
		return record if _is_valid_record(record) else {}
	return {}


static func decode(record: Dictionary) -> InputEvent:
	if not _is_valid_record(record):
		return null
	match str(record["type"]):
		"key":
			var key := InputEventKey.new()
			key.device = -1
			key.physical_keycode = int(record["physical_keycode"])
			return key
		"mouse_button":
			var mouse_button := InputEventMouseButton.new()
			mouse_button.device = -1
			mouse_button.button_index = int(record["button_index"])
			return mouse_button
		"joypad_button":
			var joy_button := InputEventJoypadButton.new()
			joy_button.device = -1
			joy_button.button_index = int(record["button_index"])
			return joy_button
		"joypad_axis":
			var motion := InputEventJoypadMotion.new()
			motion.device = -1
			motion.axis = int(record["axis"])
			motion.axis_value = float(int(record["direction"]))
			return motion
	return null


static func canonical_id(record: Dictionary) -> String:
	if not _is_valid_record(record):
		return ""
	match str(record["type"]):
		"key":
			return "key:%d" % int(record["physical_keycode"])
		"mouse_button":
			return "mouse_button:%d" % int(record["button_index"])
		"joypad_button":
			return "joypad_button:%d" % int(record["button_index"])
		"joypad_axis":
			return "joypad_axis:%d:%d" % [int(record["axis"]), int(record["direction"])]
	return ""


static func binding_family(record: Dictionary) -> String:
	if not _is_valid_record(record):
		return ""
	return "controller" if str(record["type"]).begins_with("joypad_") else "keyboard_mouse"


static func _is_valid_record(record: Dictionary) -> bool:
	if typeof(record.get("type")) != TYPE_STRING:
		return false
	match str(record["type"]):
		"key":
			return (
				_has_exact_fields(record, KEY_FIELDS)
				and typeof(record.get("physical_keycode")) == TYPE_INT
				and int(record["physical_keycode"]) > 0
			)
		"mouse_button":
			return (
				_has_exact_fields(record, BUTTON_FIELDS)
				and typeof(record.get("button_index")) == TYPE_INT
				and int(record["button_index"]) > 0
				and int(record["button_index"]) <= 9
			)
		"joypad_button":
			return (
				_has_exact_fields(record, BUTTON_FIELDS)
				and typeof(record.get("button_index")) == TYPE_INT
				and int(record["button_index"]) >= 0
				and int(record["button_index"]) <= 23
			)
		"joypad_axis":
			return (
				_has_exact_fields(record, AXIS_FIELDS)
				and typeof(record.get("axis")) == TYPE_INT
				and int(record["axis"]) >= 0
				and int(record["axis"]) <= 7
				and typeof(record.get("direction")) == TYPE_INT
				and int(record["direction"]) in [-1, 1]
			)
	return false


static func _has_exact_fields(record: Dictionary, expected_fields: Array[String]) -> bool:
	if record.size() != expected_fields.size():
		return false
	for field: String in expected_fields:
		if not record.has(field):
			return false
	return true
