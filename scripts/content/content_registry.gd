class_name ContentRegistry
extends RefCounted

const ValidationReportScript := preload("res://scripts/content/content_validation_report.gd")
const VALID_AVAILABILITY: Array[String] = ["M1", "NEXT"]
const VALID_CATEGORIES: Array[String] = ["item", "blessing", "talent", "curse"]
const OVERRIDABLE_FIELDS: Array[String] = ["archetype", "role", "rarity", "kind"]

var _definitions: Dictionary = {}


func load_manifest(path: String):
	_definitions.clear()
	var report = ValidationReportScript.new()
	var parsed = _parse_json_file(path, report, true)
	if parsed == null:
		return report
	if typeof(parsed) != TYPE_DICTIONARY:
		report.add_error("Content manifest root must be a dictionary", {"path": path}, true)
		return report
	if not _schema_version_is_supported(parsed.get("schema_version")):
		report.add_error("Unsupported content manifest schema", {"path": path}, true)
		return report
	var sources: Variant = parsed.get("sources")
	if typeof(sources) != TYPE_ARRAY:
		report.add_error("Content manifest sources must be an array", {"path": path}, true)
		return report

	for source_value: Variant in sources:
		if typeof(source_value) != TYPE_DICTIONARY:
			report.add_error("Content manifest source must be a dictionary", {"path": path}, true)
			continue
		var source: Dictionary = source_value
		if not _manifest_source_is_valid(source, path, report):
			continue
		var source_path: String = source["path"]
		var category := StringName(source["category"])
		var default_availability := StringName(source.get("default_availability", "NEXT"))
		var m1_ids_value: Variant = source.get("m1_ids", [])
		var overrides_value: Variant = source.get("overrides", {})
		load_entries(source_path, category, default_availability, m1_ids_value, report, overrides_value)
	return report


func load_entries(
	path: String,
	category: StringName,
	default_availability: StringName,
	m1_ids: Array = [],
	report = null,
	overrides: Dictionary = {}
):
	var active_report = report if report != null else ValidationReportScript.new()
	var source_is_m1 := str(default_availability) == "M1" or not m1_ids.is_empty()
	if not VALID_CATEGORIES.has(str(category)) or not VALID_AVAILABILITY.has(str(default_availability)):
		active_report.add_error(
			"Content source arguments are invalid",
			{"path": path, "category": str(category), "default_availability": str(default_availability)},
			true
		)
		return active_report
	if not _id_list_is_valid(m1_ids):
		active_report.add_error("Content source M1 ids are invalid", {"path": path, "m1_ids": m1_ids}, true)
		return active_report
	var override_error := _override_error(overrides)
	if not override_error.is_empty():
		override_error["path"] = path
		active_report.add_error("Content source overrides are invalid", override_error, true)
		overrides = {}
	var parsed = _parse_json_file(path, active_report, source_is_m1)
	if parsed == null:
		return active_report
	if typeof(parsed) != TYPE_ARRAY:
		active_report.add_error(
			"Content source root must be an array",
			{"path": path, "category": str(category)},
			source_is_m1
		)
		return active_report

	var source_ids: Dictionary = {}
	for index: int in range(parsed.size()):
		var entry_value: Variant = parsed[index]
		var entry: Dictionary = entry_value if typeof(entry_value) == TYPE_DICTIONARY else {}
		var entry_id := str(entry.get("id", ""))
		if not entry_id.is_empty():
			source_ids[entry_id] = true
		var blocking := source_is_m1 or m1_ids.has(entry_id)
		var invalid_field := _first_invalid_field(entry_value)
		if not invalid_field.is_empty():
			active_report.add_error(
				"Content entry is missing a required field",
				{"path": path, "index": index, "id": entry_id, "field": invalid_field},
				blocking
			)
			continue

		var normalized := _normalize_entry(entry, category, default_availability, m1_ids, overrides)
		if _definitions.has(entry_id):
			var existing: Dictionary = _definitions[entry_id]
			var duplicate_blocks: bool = blocking or existing.get("availability", []).has("M1")
			active_report.add_error(
				"Duplicate content id",
				{"path": path, "index": index, "id": entry_id},
				duplicate_blocks
			)
			continue

		_definitions[entry_id] = normalized
		active_report.loaded_count += 1
		active_report.add_warning(
			"Legacy display fields normalized",
			{"path": path, "id": entry_id, "fields": ["name", "description"]}
		)
		if overrides.has(entry_id):
			active_report.add_warning(
				"Milestone content override applied",
					{"path": path, "id": entry_id, "override": overrides[entry_id]}
				)

	_validate_declared_m1_ids(path, category, m1_ids, source_ids, active_report)
	for override_id: Variant in overrides.keys():
		if not source_ids.has(str(override_id)):
			active_report.add_error(
				"Content override id was not found in source",
				{"path": path, "id": str(override_id)},
				true
			)
	return active_report


func get_content(content_id: StringName) -> Dictionary:
	var definition: Dictionary = _definitions.get(str(content_id), {})
	return definition.duplicate(true)


func get_by_category(category: StringName, availability: StringName = &"") -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for definition: Dictionary in _sorted_definitions():
		if str(definition.get("category", "")) != str(category):
			continue
		if not str(availability).is_empty() and not definition.get("availability", []).has(str(availability)):
			continue
		matches.append(definition.duplicate(true))
	return matches


func all_content() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for definition: Dictionary in _sorted_definitions():
		values.append(definition.duplicate(true))
	return values


func _parse_json_file(path: String, report, blocking: bool):
	if not FileAccess.file_exists(path):
		report.add_error("Content file does not exist", {"path": path}, blocking)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		report.add_error("Content file could not be opened", {"path": path}, blocking)
		return null
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		report.add_error(
			"Content file contains invalid JSON",
			{"path": path, "line": json.get_error_line(), "message": json.get_error_message()},
			blocking
		)
		return null
	return json.data


func _first_invalid_field(entry_value: Variant) -> String:
	if typeof(entry_value) != TYPE_DICTIONARY:
		return "entry"
	var entry: Dictionary = entry_value
	for field: String in ["id", "name", "description"]:
		if typeof(entry.get(field)) != TYPE_STRING or str(entry.get(field)).is_empty():
			return field
	if typeof(entry.get("effects")) != TYPE_DICTIONARY:
		return "effects"
	return ""


func _normalize_entry(
	entry: Dictionary,
	category: StringName,
	default_availability: StringName,
	m1_ids: Array,
	overrides: Dictionary
) -> Dictionary:
	var entry_id := str(entry["id"])
	var availability := "M1" if str(default_availability) == "M1" or m1_ids.has(entry_id) else str(default_availability)
	var normalized := {
		"schema_version": 1,
		"id": entry_id,
		"category": str(category),
		"availability": [availability],
		"name_key": str(entry["name"]),
		"description_key": str(entry["description"]),
		"kind": str(entry.get("kind", "")),
		"archetype": str(entry.get("archetype", "")),
		"role": str(entry.get("role", "utility")),
		"rarity": str(entry.get("rarity", "common")),
		"effects": (entry["effects"] as Dictionary).duplicate(true),
	}
	var entry_overrides: Variant = overrides.get(entry_id, {})
	if typeof(entry_overrides) == TYPE_DICTIONARY:
		for field: String in ["archetype", "role", "rarity", "kind"]:
			if entry_overrides.has(field):
				normalized[field] = str(entry_overrides[field])
	return normalized


func _schema_version_is_supported(value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric_value := float(value)
	return is_finite(numeric_value) and numeric_value == 1.0


func _manifest_source_is_valid(source: Dictionary, path: String, report) -> bool:
	for field: String in ["path", "category", "default_availability"]:
		if typeof(source.get(field)) != TYPE_STRING or str(source.get(field)).is_empty():
			report.add_error(
				"Content manifest source field is invalid",
				{"path": path, "field": field, "source": source},
				true
			)
			return false
	if not VALID_AVAILABILITY.has(str(source["default_availability"])):
		report.add_error(
			"Content manifest availability is invalid",
			{"path": path, "value": source["default_availability"]},
			true
		)
		return false
	if not VALID_CATEGORIES.has(str(source["category"])):
		report.add_error(
			"Content manifest category is invalid",
			{"path": path, "value": source["category"]},
			true
		)
		return false
	var m1_ids: Variant = source.get("m1_ids", [])
	if typeof(m1_ids) != TYPE_ARRAY or not _id_list_is_valid(m1_ids):
		report.add_error("Content manifest M1 ids are invalid", {"path": path, "source": source}, true)
		return false
	var overrides: Variant = source.get("overrides", {})
	if typeof(overrides) != TYPE_DICTIONARY:
		report.add_error("Content manifest overrides must be a dictionary", {"path": path}, true)
		return false
	var override_error := _override_error(overrides)
	if not override_error.is_empty():
		override_error["path"] = path
		report.add_error("Content manifest override is invalid", override_error, true)
		return false
	return true


func _id_list_is_valid(values: Array) -> bool:
	var seen: Dictionary = {}
	for value: Variant in values:
		if typeof(value) != TYPE_STRING or str(value).is_empty() or seen.has(str(value)):
			return false
		seen[str(value)] = true
	return true


func _override_error(overrides: Dictionary) -> Dictionary:
	for entry_id: Variant in overrides.keys():
		if typeof(entry_id) != TYPE_STRING or str(entry_id).is_empty():
			return {"id": str(entry_id), "field": "id"}
		var entry_override: Variant = overrides[entry_id]
		if typeof(entry_override) != TYPE_DICTIONARY:
			return {"id": str(entry_id), "field": "override"}
		for field_value: Variant in (entry_override as Dictionary).keys():
			var field := str(field_value)
			var value: Variant = (entry_override as Dictionary)[field_value]
			if typeof(field_value) != TYPE_STRING or not OVERRIDABLE_FIELDS.has(field):
				return {"id": str(entry_id), "field": field}
			if typeof(value) != TYPE_STRING or (field != "archetype" and str(value).is_empty()):
				return {"id": str(entry_id), "field": field, "value": value}
	return {}


func _validate_declared_m1_ids(
	path: String,
	category: StringName,
	m1_ids: Array,
	source_ids: Dictionary,
	report
) -> void:
	for content_id_value: Variant in m1_ids:
		var content_id := str(content_id_value)
		if not source_ids.has(content_id):
			report.add_error(
				"Declared M1 content id was not found in source",
				{"path": path, "id": content_id},
				true
			)
			continue
		var definition: Variant = _definitions.get(content_id)
		if (
			typeof(definition) != TYPE_DICTIONARY
			or str((definition as Dictionary).get("category", "")) != str(category)
			or not (definition as Dictionary).get("availability", []).has("M1")
		):
			report.add_error(
				"Declared M1 content id failed to load",
				{"path": path, "id": content_id, "category": str(category)},
				true
			)


func _sorted_definitions() -> Array[Dictionary]:
	var ids: Array = _definitions.keys()
	ids.sort()
	var sorted: Array[Dictionary] = []
	for content_id: Variant in ids:
		sorted.append(_definitions[content_id])
	return sorted
