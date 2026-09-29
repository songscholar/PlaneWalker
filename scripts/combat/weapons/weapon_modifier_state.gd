class_name WeaponModifierState
extends RefCounted

const CAPABILITY_PATTERN := "^weapon\\.[a-z][a-z0-9_]{0,63}$"
const BOUND_FIELDS: Array[String] = ["minimum", "maximum"]

var _capabilities: Dictionary = {}
var _bounds: Dictionary = {}
var _values: Dictionary = {}


func configure(capabilities: PackedStringArray, bounds: Dictionary) -> bool:
	var next_capabilities: Dictionary = {}
	for capability_value: String in capabilities:
		var capability := StringName(capability_value)
		if capability == &"" or next_capabilities.has(capability) or not _matches_capability(capability_value):
			return false
		next_capabilities[capability] = true

	if bounds.size() != next_capabilities.size():
		return false
	var next_bounds: Dictionary = {}
	for capability_value: Variant in bounds.keys():
		if typeof(capability_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var capability := StringName(str(capability_value))
		if not next_capabilities.has(capability):
			return false
		var normalized_bounds := _normalized_bounds(bounds[capability_value])
		if normalized_bounds.is_empty():
			return false
		next_bounds[capability] = normalized_bounds

	_capabilities = next_capabilities
	_bounds = next_bounds
	_values.clear()
	return true


func apply(capability: StringName, value: Variant) -> bool:
	if not _capabilities.has(capability) or typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	if not is_finite(numeric):
		return false
	var capability_bounds: Dictionary = _bounds.get(capability, {})
	if capability_bounds.is_empty():
		return false
	if numeric < float(capability_bounds["minimum"]) or numeric > float(capability_bounds["maximum"]):
		return false
	_values[str(capability)] = numeric
	return true


func snapshot() -> Dictionary:
	return _values.duplicate(true)


func freeze_for_action() -> Dictionary:
	return _values.duplicate(true)


func reset() -> void:
	_values.clear()


func _normalized_bounds(value: Variant) -> Dictionary:
	if not value is Dictionary or not _has_exact_fields(value as Dictionary, BOUND_FIELDS):
		return {}
	var source: Dictionary = value
	if typeof(source["minimum"]) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	if typeof(source["maximum"]) not in [TYPE_INT, TYPE_FLOAT]:
		return {}
	var minimum := float(source["minimum"])
	var maximum := float(source["maximum"])
	if not is_finite(minimum) or not is_finite(maximum) or minimum > maximum:
		return {}
	return {
		"minimum": minimum,
		"maximum": maximum,
	}


func _matches_capability(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(CAPABILITY_PATTERN) == OK and regex.search(value) != null


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true
