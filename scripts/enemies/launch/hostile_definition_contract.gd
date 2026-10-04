class_name HostileDefinitionContract
extends RefCounted

const Action := preload("res://scripts/enemies/launch/hostile_action_contract.gd")


static func common(source: Dictionary, category: String, ids: Array) -> Dictionary:
	if typeof(source.get("category")) != TYPE_STRING or source.category != category:
		return failure("category", "unsupported")
	if not Action.integer_in_range(source.get("schema_version"), 1, 1):
		return failure("schema_version", "unsupported")
	if typeof(source.get("id")) != TYPE_STRING or not ids.has(source.id):
		return failure("id", "unsupported")
	for field: String in ["name_key", "description_key"]:
		if not localization_key(source.get(field)):
			return failure(field, "invalid_key")
	if not source.get("availability") is Array or source.availability != ["LAUNCH", "EXPANSION"]:
		return failure("availability", "exact_launch_expansion_required")
	var tags := string_list(source.get("tags"), [], 1, 8, "tags")
	if not tags.ok:
		return tags
	var references := string_list(source.get("references"), [], 0, 32, "references")
	if not references.ok:
		return references
	var result := source.duplicate(true)
	result.schema_version = 1
	result.tags = tags.value
	result.references = references.value
	return {"ok": true, "definition": result, "context": {}}


static func numeric_fields(source: Dictionary, rules: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for field: String in rules:
		var rule: Array = rules[field]
		var value: Variant = source.get(field)
		if rule[2]:
			if not Action.integer_in_range(value, int(rule[0]), int(rule[1])):
				return failure(field, "invalid_integer")
			result[field] = int(value)
		else:
			if not Action.number_in_range(value, float(rule[0]), float(rule[1])):
				return failure(field, "invalid_number")
			result[field] = float(value)
	return {"ok": true, "value": result}


static func mechanisms(value: Variant, rules: Dictionary) -> Dictionary:
	if not value is Dictionary or not Action.exact_fields(value, rules.keys()):
		return failure("mechanisms", "exact_fields_required")
	var result: Dictionary = {}
	for field: String in rules:
		var rule: Variant = rules[field]
		if typeof(rule) == TYPE_BOOL:
			if typeof(value[field]) != TYPE_BOOL or value[field] != rule:
				return failure("mechanisms." + field, "invalid_boolean")
			result[field] = value[field]
		elif rule is Array and not rule.is_empty() and typeof(rule[0]) == TYPE_STRING:
			if not value[field] is Array or value[field] != rule:
				return failure("mechanisms." + field, "invalid_ids")
			result[field] = rule.duplicate()
		else:
			var normalized := numeric_fields(value, {field: rule})
			if not normalized.ok:
				return failure("mechanisms." + field, str(normalized.context.reason))
			result[field] = normalized.value[field]
	return {"ok": true, "value": result}


static func string_list(value: Variant, allowed: Array, minimum: int, maximum: int, field: String) -> Dictionary:
	if not value is Array or value.size() < minimum or value.size() > maximum:
		return failure(field, "invalid_array")
	var result: Array[String] = []
	for candidate: Variant in value:
		if not Action.valid_id(candidate) or result.has(candidate) or (not allowed.is_empty() and not allowed.has(candidate)):
			return failure(field, "invalid_or_duplicate_id")
		result.append(candidate)
	result.sort()
	return {"ok": true, "value": result}


static func actions(value: Variant, actor_kind: String, prefix: String, warning_floor: int, seen: Dictionary) -> Dictionary:
	if not value is Array or value.is_empty() or value.size() > 16:
		return failure("actions", "invalid_array")
	var result: Array[Dictionary] = []
	for row: Variant in value:
		if not row is Dictionary:
			return failure("actions", "expected_dictionary")
		var normalized := Action.create(row, actor_kind)
		if not normalized.ok:
			return normalized
		var action: Dictionary = normalized.definition
		if not str(action.id).begins_with(prefix) or seen.has(action.id):
			return failure("actions.id", "foreign_or_duplicate")
		if action.warning_frames < warning_floor:
			return failure("actions.warning_frames", "below_floor")
		seen[action.id] = true
		result.append(action)
	return {"ok": true, "value": result}


static func localization_key(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() < 2 or value.length() > 128:
		return false
	if value.unicode_at(0) < 65 or value.unicode_at(0) > 90:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not (code >= 65 and code <= 90) and not (code >= 48 and code <= 57) and code != 95:
			return false
	return true


static func failure(field: String, reason: String) -> Dictionary:
	return {"ok": false, "code": &"HOSTILE_DEFINITION_INVALID", "context": {"field": field, "reason": reason}}
