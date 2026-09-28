class_name SelectionOfferFixtures
extends RefCounted

const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")


static func load_fixture(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Selection offer fixture does not exist: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Selection offer fixture could not be opened: %s" % path)
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error(
			"Selection offer fixture JSON parse failed at line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
		return {}
	var value: Variant = json.data
	if typeof(value) != TYPE_DICTIONARY:
		push_error("Selection offer fixture root must be a dictionary: %s" % path)
		return {}
	var offer := (value as Dictionary).duplicate(true)
	_normalize_json_integer(offer, "schema_version")
	_normalize_json_integer(offer, "revision")
	var validation = SelectionOfferScript.validate(offer)
	if not validation.ok:
		push_error("Selection offer fixture validation failed: %s" % str(validation.context))
		return {}
	return SelectionOfferScript.copy_of(offer)


static func _normalize_json_integer(value: Dictionary, field: String) -> void:
	var numeric: Variant = value.get(field)
	if typeof(numeric) != TYPE_FLOAT:
		return
	var float_value := float(numeric)
	if is_finite(float_value) and is_equal_approx(float_value, roundf(float_value)):
		value[field] = int(float_value)
