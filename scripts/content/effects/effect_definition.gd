class_name EffectDefinition
extends RefCounted

const ID_PATTERN := "^[a-z][a-z0-9_]{0,63}$"
const VALUE_TYPES: Array[String] = ["boolean", "integer", "number"]
const STACK_RULES: Array[String] = ["add", "maximum", "multiply", "replace", "set_true", "trigger"]
const RUNTIME_DOMAINS: Array[String] = [
	"stats", "health", "time", "weapon", "character", "trigger",
]
const CONTENT_CATEGORIES: Array[String] = ["blessing", "curse", "item", "talent"]
const WEAPON_CAPABILITY_PATTERN := "^weapon\\.[a-z][a-z0-9_]{0,63}$"
const WEAPON_CAPABILITY_STACK_RULES: Array[String] = ["add", "maximum", "multiply", "replace"]
const WEAPON_CAPABILITY_FIELDS: Array[String] = ["weapon_id", "capability", "base_value"]
const REQUIRED_FIELDS: Array[String] = [
	"effect_id",
	"value_type",
	"minimum",
	"maximum",
	"stack_rule",
	"allowed_categories",
	"runtime_domain",
]
const OPTIONAL_FIELDS: Array[String] = ["weapon_capabilities"]

var effect_id: String = ""
var value_type: String = ""
var minimum: Variant = null
var maximum: Variant = null
var stack_rule: String = ""
var allowed_categories: Array[String] = []
var runtime_domain: String = ""
var weapon_capabilities: Array[Dictionary] = []


func configure(source: Dictionary) -> Dictionary:
	for field: String in REQUIRED_FIELDS:
		if not source.has(field):
			return _failure(field, "missing")
	for field_value: Variant in source.keys():
		var field := str(field_value)
		if not REQUIRED_FIELDS.has(field) and not OPTIONAL_FIELDS.has(field):
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
	var source_runtime_domain: Variant = source["runtime_domain"]
	if (
		typeof(source_runtime_domain) != TYPE_STRING
		or not RUNTIME_DOMAINS.has(str(source_runtime_domain))
	):
		return _failure("runtime_domain", "unsupported")

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
	var weapon_capabilities_result := _normalize_weapon_capabilities(
		source.get("weapon_capabilities", []),
		str(source_value_type),
		str(source_stack_rule)
	)
	if not bool(weapon_capabilities_result.get("ok", false)):
		return weapon_capabilities_result

	effect_id = str(source_id)
	value_type = str(source_value_type)
	minimum = source["minimum"]
	maximum = source["maximum"]
	stack_rule = str(source_stack_rule)
	allowed_categories = categories_result["categories"]
	runtime_domain = str(source_runtime_domain)
	weapon_capabilities.clear()
	for mapping_value: Variant in weapon_capabilities_result["weapon_capabilities"]:
		weapon_capabilities.append((mapping_value as Dictionary).duplicate(true))
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
	var result := {
		"effect_id": effect_id,
		"value_type": value_type,
		"minimum": minimum,
		"maximum": maximum,
		"stack_rule": stack_rule,
		"allowed_categories": allowed_categories.duplicate(),
		"runtime_domain": runtime_domain,
	}
	if not weapon_capabilities.is_empty():
		result["weapon_capabilities"] = weapon_capabilities.duplicate(true)
	return result


func weapon_capability_snapshot() -> Array[Dictionary]:
	return weapon_capabilities.duplicate(true)


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


static func _normalize_weapon_capabilities(
	value: Variant,
	value_type_id: String,
	stack_rule_id: String
) -> Dictionary:
	if not value is Array:
		return _failure("weapon_capabilities", "expected_array")
	if (value as Array).is_empty():
		return {"ok": true, "weapon_capabilities": [], "context": {}}
	if value_type_id not in ["integer", "number"]:
		return _failure("weapon_capabilities", "numeric_effect_required")
	if not WEAPON_CAPABILITY_STACK_RULES.has(stack_rule_id):
		return _failure("weapon_capabilities", "unsupported_stack_rule")
	var seen_weapons: Dictionary = {}
	var mappings: Array[Dictionary] = []
	for mapping_value: Variant in value:
		if not mapping_value is Dictionary:
			return _failure("weapon_capabilities", "entry_type")
		var mapping: Dictionary = mapping_value
		if not _has_exact_fields(mapping, WEAPON_CAPABILITY_FIELDS):
			return _failure("weapon_capabilities", "entry_fields")
		if typeof(mapping["weapon_id"]) != TYPE_STRING or not _matches(ID_PATTERN, str(mapping["weapon_id"])):
			return _failure("weapon_capabilities.weapon_id", "invalid")
		var weapon_id := str(mapping["weapon_id"])
		if seen_weapons.has(weapon_id):
			return _failure("weapon_capabilities.weapon_id", "duplicate")
		if typeof(mapping["capability"]) != TYPE_STRING or not _matches(
			WEAPON_CAPABILITY_PATTERN,
			str(mapping["capability"])
		):
			return _failure("weapon_capabilities.capability", "invalid")
		if typeof(mapping["base_value"]) not in [TYPE_INT, TYPE_FLOAT]:
			return _failure("weapon_capabilities.base_value", "expected_number")
		var base_value := float(mapping["base_value"])
		if not is_finite(base_value):
			return _failure("weapon_capabilities.base_value", "non_finite")
		seen_weapons[weapon_id] = true
		mappings.append({
			"weapon_id": weapon_id,
			"capability": str(mapping["capability"]),
			"base_value": base_value,
		})
	mappings.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return str(left["weapon_id"]) < str(right["weapon_id"])
	)
	return {"ok": true, "weapon_capabilities": mappings, "context": {}}


static func _matches(pattern: String, value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null


static func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _failure(field: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"definition": null,
		"context": {"field": field, "reason": reason},
	}
