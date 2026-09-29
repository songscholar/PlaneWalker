class_name EffectHandlerCatalog
extends RefCounted

const EffectDefinitionScript := preload("res://scripts/content/effects/effect_definition.gd")
const ValidationReportScript := preload("res://scripts/content/content_validation_report.gd")
const DEFAULT_CATALOG_PATH := "res://data/content/effect_catalog.json"

var _definitions: Dictionary = {}
var _load_errors: Array[Dictionary] = []
var _loaded_count: int = 0


func _init(catalog_path: String = DEFAULT_CATALOG_PATH) -> void:
	_load_catalog(catalog_path)


func load_report():
	var report = ValidationReportScript.new()
	for error: Dictionary in _load_errors:
		report.add_error(
			str(error.get("message", "Effect catalog failed to load")),
			error.get("context", {}),
			true
		)
	report.loaded_count = _loaded_count
	return report


func validate_effects(effects: Variant, context: Dictionary):
	var report = load_report()
	if report.has_blocking_errors():
		return report
	if not effects is Dictionary:
		report.add_error("Effects must be a dictionary", {"value_type": typeof(effects)}, true)
		return report
	var category_value: Variant = context.get("category")
	if typeof(category_value) != TYPE_STRING or not EffectDefinitionScript.CONTENT_CATEGORIES.has(str(category_value)):
		report.add_error("Effect validation requires a known content category", {"category": category_value}, true)
		return report
	var category := str(category_value)
	var sorted_keys: Array = (effects as Dictionary).keys()
	sorted_keys.sort_custom(func(left: Variant, right: Variant) -> bool: return str(left) < str(right))
	var valid_count := 0
	for effect_id_value: Variant in sorted_keys:
		if typeof(effect_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			report.add_error("Effect id must be a string", {"effect_id": effect_id_value}, true)
			continue
		var effect_id := str(effect_id_value)
		if _is_script_like(effect_id):
			report.add_error("Script-like effect id is forbidden", {"effect_id": effect_id}, true)
			continue
		if not _definitions.has(effect_id):
			report.add_error("Unknown effect id", {"effect_id": effect_id}, true)
			continue
		var definition = _definitions[effect_id]
		if not definition.allows_category(category):
			report.add_error(
				"Effect is not allowed for this content category",
				{"effect_id": effect_id, "category": category},
				true
			)
			continue
		var error: String = definition.value_error((effects as Dictionary)[effect_id_value])
		if not error.is_empty():
			report.add_error(
				"Effect value is invalid",
				{"effect_id": effect_id, "reason": error},
				true
			)
			continue
		valid_count += 1
	report.loaded_count = valid_count
	return report


func normalize_effects(effects: Variant) -> Dictionary:
	if not _load_errors.is_empty() or not effects is Dictionary:
		return {}
	var effect_ids: Array[String] = []
	var source_keys: Dictionary = {}
	for effect_id_value: Variant in (effects as Dictionary).keys():
		if typeof(effect_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return {}
		var effect_id := str(effect_id_value)
		if _is_script_like(effect_id) or not _definitions.has(effect_id) or source_keys.has(effect_id):
			return {}
		var definition = _definitions[effect_id]
		if not definition.value_error((effects as Dictionary)[effect_id_value]).is_empty():
			return {}
		effect_ids.append(effect_id)
		source_keys[effect_id] = effect_id_value
	effect_ids.sort()
	var normalized: Dictionary = {}
	for effect_id: String in effect_ids:
		var definition = _definitions[effect_id]
		normalized[effect_id] = definition.normalize_value((effects as Dictionary)[source_keys[effect_id]])
	return normalized


func snapshot() -> Array[Dictionary]:
	var effect_ids: Array[String] = []
	for effect_id_value: Variant in _definitions.keys():
		effect_ids.append(str(effect_id_value))
	effect_ids.sort()
	var result: Array[Dictionary] = []
	for effect_id: String in effect_ids:
		result.append((_definitions[effect_id].snapshot() as Dictionary).duplicate(true))
	return result


func _load_catalog(path: String) -> void:
	_definitions.clear()
	_load_errors.clear()
	_loaded_count = 0
	if not FileAccess.file_exists(path):
		_add_load_error("Effect catalog file does not exist", {"path": path})
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_add_load_error("Effect catalog file cannot be opened", {"path": path})
		return
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		_add_load_error(
			"Effect catalog contains invalid JSON",
			{"path": path, "line": parser.get_error_line(), "message": parser.get_error_message()}
		)
		return
	if not parser.data is Array:
		_add_load_error("Effect catalog root must be an array", {"path": path})
		return
	for row_index: int in range((parser.data as Array).size()):
		var row_value: Variant = (parser.data as Array)[row_index]
		if not row_value is Dictionary:
			_add_load_error("Effect catalog row must be a dictionary", {"path": path, "row": row_index})
			continue
		var definition = EffectDefinitionScript.new()
		var parsed: Dictionary = definition.configure(row_value as Dictionary)
		if not bool(parsed.get("ok", false)):
			var error_context: Dictionary = parsed.get("context", {}).duplicate(true)
			error_context["path"] = path
			error_context["row"] = row_index
			_add_load_error("Effect catalog row is invalid", error_context)
			continue
		if _definitions.has(definition.effect_id):
			_add_load_error("Effect catalog contains a duplicate id", {"path": path, "row": row_index, "effect_id": definition.effect_id})
			continue
		_definitions[definition.effect_id] = definition
	if not _load_errors.is_empty():
		_definitions.clear()
		return
	_loaded_count = _definitions.size()


func _add_load_error(message: String, context: Dictionary) -> void:
	_load_errors.append({"message": message, "context": context.duplicate(true)})


func _is_script_like(effect_id: String) -> bool:
	var lowered := effect_id.to_lower()
	return (
		effect_id.contains("/")
		or effect_id.contains("\\")
		or effect_id.contains("..")
		or lowered.contains(".gd")
	)
