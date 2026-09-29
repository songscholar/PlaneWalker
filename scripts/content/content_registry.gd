class_name ContentRegistry
extends RefCounted

const ValidationReportScript := preload("res://scripts/content/content_validation_report.gd")
const ContentPackDescriptorScript := preload("res://scripts/content/content_pack_descriptor.gd")
const ContentPackResolverScript := preload("res://scripts/content/content_pack_resolver.gd")
const EffectHandlerCatalogScript := preload("res://scripts/content/effects/effect_handler_catalog.gd")

const VALID_AVAILABILITY: Array[String] = ["M1", "CURRENT", "NEXT", "LAUNCH", "EXPANSION"]
const VALID_CATEGORIES: Array[String] = [
	"character",
	"weapon",
	"time_ability",
	"item",
	"blessing",
	"curse",
	"talent",
	"enemy",
	"encounter",
	"room",
	"event",
	"merchant",
	"boss",
	"narrative",
	"cosmetic",
	"challenge",
]
const OVERRIDABLE_FIELDS: Array[String] = ["archetype", "role", "rarity", "kind"]
const CONTENT_ID_PATTERN := "^[a-z0-9][a-z0-9_.-]{0,63}$"
const LOCALIZATION_KEY_PATTERN := "^[A-Z][A-Z0-9_]{1,127}$"
const V2_REQUIRED_FIELDS: Array[String] = [
	"id",
	"category",
	"availability",
	"name_key",
	"description_key",
	"tags",
	"compatibility",
	"effects",
]
const V2_ALLOWED_FIELDS: Array[String] = [
	"id",
	"category",
	"availability",
	"name_key",
	"description_key",
	"tags",
	"compatibility",
	"effects",
	"kind",
	"archetype",
	"role",
	"rarity",
	"icon_id",
	"references",
]
const COMPATIBILITY_FIELDS: Array[String] = [
	"character_ids",
	"weapon_ids",
	"time_ability_ids",
	"archetype_ids",
	"modes",
]

var _definitions: Dictionary = {}
var _active_packs: Array[Dictionary] = []


func load_packs(
	pack_specs: Array,
	game_version: String,
	execution_mode: StringName = &"M1"
):
	_definitions.clear()
	_active_packs.clear()
	var report = ValidationReportScript.new()
	var mode := str(execution_mode)
	if game_version.is_empty() or not VALID_AVAILABILITY.has(mode):
		report.add_error(
			"Content pack activation arguments are invalid",
			{"game_version": game_version, "execution_mode": mode},
			true
		)
		return report
	if pack_specs.is_empty():
		report.add_error("At least one content pack is required", {}, true)
		return report

	var descriptors: Array[Dictionary] = []
	var isolated_ids: Dictionary = {}
	for index: int in range(pack_specs.size()):
		var spec_result := _normalize_pack_spec(pack_specs[index], index)
		if not bool(spec_result.get("ok", false)):
			report.add_error(
				"Content pack specification is invalid",
				spec_result.get("context", {}),
				bool(spec_result.get("required", index == 0))
			)
			continue
		var required_pack := bool(spec_result["required"])
		var descriptor_result: Dictionary = ContentPackDescriptorScript.load_path(
			str(spec_result["path"]),
			required_pack
		)
		if not bool(descriptor_result.get("ok", false)):
			var descriptor_context: Dictionary = descriptor_result.get("context", {}).duplicate(true)
			descriptor_context["code"] = str(descriptor_result.get("code", &"INVALID_PACK"))
			report.add_error("Content pack descriptor failed", descriptor_context, required_pack)
			var failed_pack_id := str(spec_result.get("pack_id", ""))
			if not required_pack and not failed_pack_id.is_empty():
				isolated_ids[failed_pack_id] = true
			continue
		descriptors.append((descriptor_result["descriptor"] as Dictionary).duplicate(true))

	if report.has_blocking_errors():
		report.set_activation_summary(0, _sorted_string_keys(isolated_ids), {}, {})
		return report
	var resolution = ContentPackResolverScript.new().resolve(descriptors, game_version)
	report.merge(resolution)
	for pack_id: Variant in resolution.get_meta("isolated_pack_ids", []):
		isolated_ids[str(pack_id)] = true
	if report.has_blocking_errors():
		report.loaded_count = 0
		report.set_activation_summary(0, _sorted_string_keys(isolated_ids), {}, {})
		return report

	var effect_catalog = EffectHandlerCatalogScript.new()
	var effect_report = effect_catalog.load_report()
	report.merge(effect_report)
	if report.has_blocking_errors():
		report.loaded_count = 0
		report.set_activation_summary(0, _sorted_string_keys(isolated_ids), {}, {})
		return report

	var localization_keys: Dictionary = {}
	var active_descriptors: Array = resolution.get_meta("active_descriptors", [])
	for descriptor_value: Variant in active_descriptors:
		if not descriptor_value is Dictionary:
			continue
		var descriptor: Dictionary = descriptor_value
		var pack_id := str(descriptor.get("pack_id", ""))
		if isolated_ids.has(pack_id):
			continue
		var blocking := bool(descriptor.get("required_pack", false))
		var unavailable_dependency := _first_isolated_dependency(descriptor, isolated_ids)
		if not unavailable_dependency.is_empty():
			report.add_error(
				"Content pack dependency was isolated during activation",
				{"pack_id": pack_id, "dependency_id": unavailable_dependency},
				blocking
			)
			isolated_ids[pack_id] = true
			continue
		var localization_result := _load_pack_localization_keys(descriptor)
		if not bool(localization_result.get("ok", false)):
			report.add_error(
				"Content pack localization failed",
				localization_result.get("context", {}),
				blocking
			)
			isolated_ids[pack_id] = true
			continue
		var candidate_localization_keys: Dictionary = localization_keys.duplicate(true)
		for key_value: Variant in (localization_result.get("keys", {}) as Dictionary).keys():
			candidate_localization_keys[str(key_value)] = true

		var definitions_result := _load_pack_definitions(
			descriptor,
			effect_catalog,
			candidate_localization_keys
		)
		if not bool(definitions_result.get("ok", false)):
			for error_value: Variant in definitions_result.get("errors", []):
				var error: Dictionary = error_value
				report.add_error(
					str(error.get("message", "Content pack entry failed validation")),
					error.get("context", {}),
					blocking
				)
			isolated_ids[pack_id] = true
			continue
		var pack_definitions: Array[Dictionary] = definitions_result["definitions"]
		var duplicate_id := ""
		for definition: Dictionary in pack_definitions:
			var content_id := str(definition["id"])
			if _definitions.has(content_id):
				duplicate_id = content_id
				break
		if not duplicate_id.is_empty():
			report.add_error(
				"Duplicate content id across packs",
				{"pack_id": pack_id, "content_id": duplicate_id},
				blocking
			)
			isolated_ids[pack_id] = true
			continue
		var available_ids := _known_content_ids(pack_definitions)
		var reference_error := _first_reference_error(pack_definitions, available_ids)
		if not reference_error.is_empty():
			reference_error["pack_id"] = pack_id
			report.add_error("Content reference is unavailable", reference_error, blocking)
			isolated_ids[pack_id] = true
			continue
		for definition: Dictionary in pack_definitions:
			_definitions[str(definition["id"])] = definition.duplicate(true)
		localization_keys = candidate_localization_keys
		_active_packs.append(descriptor.duplicate(true))

	if report.has_blocking_errors():
		_definitions.clear()
		_active_packs.clear()
		report.loaded_count = 0
		report.set_activation_summary(0, _sorted_string_keys(isolated_ids), {}, {})
		return report

	report.loaded_count = _definitions.size()
	var category_counts := _category_counts()
	report.set_activation_summary(
		_active_packs.size(),
		_sorted_string_keys(isolated_ids),
		category_counts,
		{
			"activation_order": _active_pack_ids(),
			"execution_mode": mode,
			"game_version": game_version,
		}
	)
	return report


func load_manifest(path: String):
	_definitions.clear()
	_active_packs.clear()
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


func active_packs() -> Array[Dictionary]:
	return _active_packs.duplicate(true)


func get_by_tag(tag: StringName, availability: StringName = &"") -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for definition: Dictionary in _sorted_definitions():
		if not definition.get("tags", []).has(str(tag)):
			continue
		if not str(availability).is_empty() and not definition.get("availability", []).has(str(availability)):
			continue
		matches.append(definition.duplicate(true))
	return matches


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


func _normalize_pack_spec(value: Variant, index: int) -> Dictionary:
	if typeof(value) == TYPE_STRING:
		var path := str(value)
		if path.is_empty():
			return {"ok": false, "required": index == 0, "context": {"index": index, "field": "path"}}
		return {"ok": true, "path": path, "required": index == 0}
	if not value is Dictionary:
		return {"ok": false, "required": index == 0, "context": {"index": index, "field": "spec"}}
	var spec: Dictionary = value
	if typeof(spec.get("path")) != TYPE_STRING or str(spec.get("path")).is_empty():
		return {"ok": false, "required": bool(spec.get("required", index == 0)), "context": {"index": index, "field": "path"}}
	if spec.has("required") and typeof(spec["required"]) != TYPE_BOOL:
		return {"ok": false, "required": index == 0, "context": {"index": index, "field": "required"}}
	return {
		"ok": true,
		"path": str(spec["path"]),
		"required": bool(spec.get("required", index == 0)),
		"pack_id": str(spec.get("pack_id", "")),
	}


func _load_pack_localization_keys(descriptor: Dictionary) -> Dictionary:
	var keys: Dictionary = {}
	var root_path := str(descriptor.get("root_path", ""))
	var pack_id := str(descriptor.get("pack_id", ""))
	for relative_path_value: Variant in descriptor.get("localization_sources", []):
		var relative_path := str(relative_path_value)
		var source_path := root_path.path_join(relative_path)
		var file := FileAccess.open(source_path, FileAccess.READ)
		if file == null:
			return {
				"ok": false,
				"keys": {},
				"context": {"pack_id": pack_id, "path": source_path, "reason": "open_failed"},
			}
		var lines := file.get_as_text().split("\n", false)
		if lines.is_empty() or str(lines[0]).strip_edges().to_lower() != "keys,en,zh_cn":
			return {
				"ok": false,
				"keys": {},
				"context": {"pack_id": pack_id, "path": source_path, "reason": "header"},
			}
		for line_index: int in range(1, lines.size()):
			var line := str(lines[line_index]).strip_edges()
			if line.is_empty():
				continue
			var key := line.get_slice(",", 0).strip_edges().trim_prefix("\"").trim_suffix("\"")
			if not _matches(LOCALIZATION_KEY_PATTERN, key) or keys.has(key):
				return {
					"ok": false,
					"keys": {},
					"context": {
						"pack_id": pack_id,
						"path": source_path,
						"line": line_index + 1,
						"key": key,
						"reason": "invalid_or_duplicate_key",
					},
				}
			keys[key] = true
	return {"ok": true, "keys": keys, "context": {}}


func _load_pack_definitions(
	descriptor: Dictionary,
	effect_catalog,
	localization_keys: Dictionary
) -> Dictionary:
	var definitions: Array[Dictionary] = []
	var errors: Array[Dictionary] = []
	var pack_ids: Dictionary = {}
	var root_path := str(descriptor.get("root_path", ""))
	var pack_id := str(descriptor.get("pack_id", ""))
	var pack_version := str(descriptor.get("pack_version", ""))
	for relative_path_value: Variant in descriptor.get("content_manifest", []):
		var relative_path := str(relative_path_value)
		var source_path := root_path.path_join(relative_path)
		var file := FileAccess.open(source_path, FileAccess.READ)
		if file == null:
			errors.append({
				"message": "Content pack source could not be opened",
				"context": {"pack_id": pack_id, "path": source_path},
			})
			continue
		var parser := JSON.new()
		var parse_error := parser.parse(file.get_as_text())
		if parse_error != OK or not parser.data is Array:
			errors.append({
				"message": "Content pack source must contain a valid JSON array",
				"context": {
					"pack_id": pack_id,
					"path": source_path,
					"line": parser.get_error_line(),
					"parse_error": parse_error,
				},
			})
			continue
		for index: int in range((parser.data as Array).size()):
			var entry_value: Variant = (parser.data as Array)[index]
			var entry_error := _v2_entry_error(entry_value, effect_catalog, localization_keys)
			if not entry_error.is_empty():
				entry_error["pack_id"] = pack_id
				entry_error["path"] = source_path
				entry_error["index"] = index
				errors.append({"message": "Content pack entry failed validation", "context": entry_error})
				continue
			var entry: Dictionary = entry_value
			var content_id := str(entry["id"])
			if pack_ids.has(content_id):
				errors.append({
					"message": "Duplicate content id inside pack",
					"context": {"pack_id": pack_id, "path": source_path, "index": index, "content_id": content_id},
				})
				continue
			pack_ids[content_id] = true
			var normalized := entry.duplicate(true)
			var availability: Array = normalized["availability"]
			availability.sort()
			normalized["availability"] = availability
			var tags: Array = normalized["tags"]
			tags.sort()
			normalized["tags"] = tags
			var compatibility: Dictionary = normalized["compatibility"]
			for compatibility_field: Variant in compatibility.keys():
				var values: Array = compatibility[compatibility_field]
				values.sort()
				compatibility[compatibility_field] = values
			normalized["compatibility"] = compatibility
			normalized["effects"] = effect_catalog.normalize_effects(normalized["effects"])
			normalized["kind"] = str(normalized.get("kind", ""))
			normalized["archetype"] = str(normalized.get("archetype", ""))
			normalized["role"] = str(normalized.get("role", "utility"))
			normalized["rarity"] = str(normalized.get("rarity", "common"))
			normalized["icon_id"] = str(normalized.get("icon_id", "content_%s" % content_id))
			var references: Array = normalized.get("references", [])
			references.sort()
			normalized["references"] = references
			normalized["pack_id"] = pack_id
			normalized["pack_version"] = pack_version
			definitions.append(normalized)
	if not errors.is_empty():
		return {"ok": false, "definitions": [], "errors": errors}
	definitions.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return str(left["id"]) < str(right["id"])
	)
	return {"ok": true, "definitions": definitions, "errors": []}


func _v2_entry_error(
	entry_value: Variant,
	effect_catalog,
	localization_keys: Dictionary
) -> Dictionary:
	if not entry_value is Dictionary:
		return {"field": "entry", "reason": "type"}
	var entry: Dictionary = entry_value
	for field: String in V2_REQUIRED_FIELDS:
		if not entry.has(field):
			return {"field": field, "reason": "missing"}
	for field_value: Variant in entry.keys():
		var field := str(field_value)
		if not V2_ALLOWED_FIELDS.has(field):
			return {"field": field, "reason": "unknown"}
	if not _matches(CONTENT_ID_PATTERN, entry["id"]):
		return {"field": "id", "reason": "value"}
	if typeof(entry["category"]) != TYPE_STRING or not VALID_CATEGORIES.has(str(entry["category"])):
		return {"field": "category", "reason": "value"}
	var availability_error := _id_array_error(entry["availability"], VALID_AVAILABILITY, false, false)
	if not availability_error.is_empty():
		return {"field": "availability", "reason": availability_error}
	for field: String in ["name_key", "description_key"]:
		if not _matches(LOCALIZATION_KEY_PATTERN, entry[field]):
			return {"field": field, "reason": "value"}
		if not localization_keys.has(str(entry[field])):
			return {"field": field, "reason": "missing_localization", "key": entry[field]}
	var tags_error := _id_array_error(entry["tags"], [], true)
	if not tags_error.is_empty():
		return {"field": "tags", "reason": tags_error}
	if not entry["compatibility"] is Dictionary:
		return {"field": "compatibility", "reason": "type"}
	for field_value: Variant in (entry["compatibility"] as Dictionary).keys():
		var field := str(field_value)
		if not COMPATIBILITY_FIELDS.has(field):
			return {"field": "compatibility.%s" % field, "reason": "unknown"}
		var compatibility_error := _id_array_error((entry["compatibility"] as Dictionary)[field_value], [], true)
		if not compatibility_error.is_empty():
			return {"field": "compatibility.%s" % field, "reason": compatibility_error}
	var effect_report = effect_catalog.validate_effects(
		entry["effects"],
		{"category": str(entry["category"])}
	)
	if effect_report.has_blocking_errors():
		return {"field": "effects", "reason": "invalid", "errors": effect_report.blocking_errors.duplicate(true)}
	for field: String in ["kind", "archetype", "role"]:
		if entry.has(field) and not _optional_identifier_is_valid(entry[field]):
			return {"field": field, "reason": "value"}
	if entry.has("rarity") and str(entry["rarity"]) not in ["common", "uncommon", "rare", "legendary", "unique"]:
		return {"field": "rarity", "reason": "value"}
	if entry.has("icon_id") and not _matches(CONTENT_ID_PATTERN, entry["icon_id"]):
		return {"field": "icon_id", "reason": "value"}
	if entry.has("references"):
		var reference_error := _id_array_error(entry["references"], [], true)
		if not reference_error.is_empty():
			return {"field": "references", "reason": reference_error}
	return {}


func _id_array_error(
	value: Variant,
	allowed_values: Array,
	allow_empty: bool,
	require_identifier: bool = true
) -> String:
	if not value is Array:
		return "type"
	if not allow_empty and (value as Array).is_empty():
		return "empty"
	var seen: Dictionary = {}
	for id_value: Variant in value:
		if typeof(id_value) != TYPE_STRING:
			return "entry_type"
		var content_id := str(id_value)
		if require_identifier and not _matches(CONTENT_ID_PATTERN, content_id):
			return "entry_value"
		if not allowed_values.is_empty() and not allowed_values.has(content_id):
			return "entry_unknown"
		if seen.has(content_id):
			return "duplicate"
		seen[content_id] = true
	return ""


func _optional_identifier_is_valid(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and (str(value).is_empty() or _matches(CONTENT_ID_PATTERN, value))


func _matches(pattern: String, value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(str(value)) != null


func _known_content_ids(pack_definitions: Array[Dictionary]) -> Dictionary:
	var ids: Dictionary = {}
	for content_id: Variant in _definitions.keys():
		ids[str(content_id)] = true
	for definition: Dictionary in pack_definitions:
		ids[str(definition["id"])] = true
	return ids


func _first_reference_error(
	pack_definitions: Array[Dictionary],
	available_ids: Dictionary
) -> Dictionary:
	for definition: Dictionary in pack_definitions:
		for reference_value: Variant in definition.get("references", []):
			var reference_id := str(reference_value)
			if not available_ids.has(reference_id):
				return {"content_id": str(definition["id"]), "reference_id": reference_id}
	return {}


func _first_isolated_dependency(descriptor: Dictionary, isolated_ids: Dictionary) -> String:
	for dependency_value: Variant in descriptor.get("dependencies", []):
		if not dependency_value is Dictionary:
			continue
		var dependency: Dictionary = dependency_value
		if bool(dependency.get("required", true)) and isolated_ids.has(str(dependency.get("pack_id", ""))):
			return str(dependency.get("pack_id", ""))
	return ""


func _category_counts() -> Dictionary:
	var counts: Dictionary = {}
	for definition: Dictionary in _definitions.values():
		var category := str(definition.get("category", ""))
		counts[category] = int(counts.get(category, 0)) + 1
	return counts


func _active_pack_ids() -> Array[String]:
	var ids: Array[String] = []
	for descriptor: Dictionary in _active_packs:
		ids.append(str(descriptor.get("pack_id", "")))
	return ids


func _sorted_string_keys(values: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values.keys():
		result.append(str(value))
	result.sort()
	return result
