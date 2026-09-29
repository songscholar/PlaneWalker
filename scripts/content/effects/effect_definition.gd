class_name EffectDefinition
extends RefCounted

const ID_PATTERN := "^[a-z][a-z0-9_]{0,63}$"
const VALUE_TYPES: Array[String] = ["boolean", "integer", "number"]
const STACK_RULES: Array[String] = ["add", "maximum", "multiply", "replace", "set_true", "trigger"]
const CONTENT_CATEGORIES: Array[String] = ["blessing", "curse", "item", "talent"]
const REQUIRED_FIELDS: Array[String] = [
	"effect_id",
	"value_type",
	"minimum",
	"maximum",
	"stack_rule",
	"allowed_categories",
]

var effect_id: String = ""
var value_type: String = ""
var minimum: Variant = null
var maximum: Variant = null
var stack_rule: String = ""
var allowed_categories: Array[String] = []


func configure(source: Dictionary) -> Dictionary:
	for field: String in REQUIRED_FIELDS:
		if not source.has(field):
			return _failure(field, "missing")
	for field_value: Variant in source.keys():
		var field := str(field_value)
		if not REQUIRED_FIELDS.has(field):
			return _failure(field, "unknown")

	var source_id: Variant = source["effect_id"]
	if typeof(source_id) != TYPE_STRING or not _matches(ID_PATTERN, str(source_id)):
		return _failure("effect_id", "invalid")
	var source_value_type: Variant = source["value_type"]
	if typeof(source_value_type) != TYPE_STRING or not VALUE_TYPES.has(str(source_value_type)):
		return _failure("value_type", "unsupported")
	var source_stack_rule: Variant = source["stack_rule"]
	if typeof(source_stack_rule) != TYPE_STRING or not STACK_RULES.has(str(source_stack_rule)):
		return _failure("stack_rule", "unsupported")

	var categories_result := _normalize_categories(source["allowed_categories"])
	if not bool(categories_result.get("ok", false)):
		return categories_result
	var bounds_result := _validate_bounds(
		str(source_value_type),
		source["minimum"],
		source["maximum"]
	)
	if not bool(bounds_result.get("ok", false)):
		return bounds_result

	effect_id = str(source_id)
	value_type = str(source_value_type)
	minimum = source["minimum"]
	maximum = source["maximum"]
	stack_rule = str(source_stack_rule)
	allowed_categories = categories_result["categories"]
	return {"ok": true, "context": {}}


func allows_category(category: String) -> bool:
	return allowed_categories.has(category)


func value_error(value: Variant) -> String:
	match value_type:
		"boolean":
			if typeof(value) != TYPE_BOOL:
				return "expected_boolean"
		"integer":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
				return "expected_integer"
			var numeric := float(value)
			if not is_finite(numeric):
				return "non_finite"
			if numeric != floorf(numeric):
				return "expected_integer"
			if numeric < float(minimum) or numeric > float(maximum):
				return "out_of_range"
		"number":
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
				return "expected_number"
			var numeric := float(value)
			if not is_finite(numeric):
				return "non_finite"
			if numeric < float(minimum) or numeric > float(maximum):
				return "out_of_range"
		_:
			return "unsupported_value_type"
	return ""


func normalize_value(value: Variant) -> Variant:
	match value_type:
		"boolean":
			return bool(value)
		"integer":
			return int(value)
		"number":
			return float(value)
	return null


func snapshot() -> Dictionary:
	return {
		"effect_id": effect_id,
		"value_type": value_type,
		"minimum": minimum,
		"maximum": maximum,
		"stack_rule": stack_rule,
		"allowed_categories": allowed_categories.duplicate(),
	}


static func _validate_bounds(type_id: String, minimum_value: Variant, maximum_value: Variant) -> Dictionary:
	if type_id == "boolean":
		if minimum_value != null or maximum_value != null:
			return _failure("minimum", "boolean_bounds_must_be_null")
		return {"ok": true, "context": {}}
	if typeof(minimum_value) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("minimum", "expected_number")
	if typeof(maximum_value) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure("maximum", "expected_number")
	var normalized_minimum := float(minimum_value)
	var normalized_maximum := float(maximum_value)
	if not is_finite(normalized_minimum) or not is_finite(normalized_maximum):
		return _failure("minimum", "non_finite_bound")
	if normalized_minimum > normalized_maximum:
		return _failure("minimum", "inverted_bounds")
	if type_id == "integer" and (
		normalized_minimum != floorf(normalized_minimum)
		or normalized_maximum != floorf(normalized_maximum)
	):
		return _failure("minimum", "integer_bounds_required")
	return {"ok": true, "context": {}}


static func _normalize_categories(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).is_empty():
		return _failure("allowed_categories", "expected_non_empty_array")
	var seen: Dictionary = {}
	var categories: Array[String] = []
	for category_value: Variant in value:
		if typeof(category_value) != TYPE_STRING:
			return _failure("allowed_categories", "expected_string")
		var category := str(category_value)
		if not CONTENT_CATEGORIES.has(category):
			return _failure("allowed_categories", "unknown_category")
		if seen.has(category):
			return _failure("allowed_categories", "duplicate_category")
		seen[category] = true
		categories.append(category)
	categories.sort()
	return {"ok": true, "categories": categories, "context": {}}


static func _matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func _failure(field: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"definition": null,
		"context": {"field": field, "reason": reason},
	}
