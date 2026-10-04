class_name MetaCatalogFactory
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const CONTENT_ROOT := "res://data/content_packs/base/content/"
const LEGACY_REFERENCES := "res://data/content/meta_legacy_references.json"
const META_FIELDS := ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "effects", "node_id", "branch", "cost", "prerequisites", "meta_effects"]


static func load_base() -> Dictionary:
	var catalogs: Dictionary = {}
	for file: String in ["meta_nodes", "items", "forge_definitions", "narrative_definitions", "tutorial_definitions", "archetype_profiles"]:
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_ROOT + file + ".json"))
		if not value is Array or value.is_empty():
			return _failure(&"CONTENT_UNAVAILABLE", {"catalog": file})
		catalogs[file] = value
	return from_catalogs(catalogs)


static func from_registry(registry: RefCounted, availability: StringName = &"LAUNCH") -> Dictionary:
	if registry == null or not registry.has_method("get_catalog_entries") or availability not in [&"LAUNCH", &"EXPANSION"]:
		return _failure(&"REGISTRY_UNAVAILABLE")
	var catalogs: Dictionary = {}
	for file: String in ["meta_nodes", "items", "forge_definitions", "narrative_definitions", "tutorial_definitions", "archetype_profiles"]:
		var category: String = {"meta_nodes": "meta_node", "items": "item", "forge_definitions": "forge_definition", "narrative_definitions": "narrative_definition", "tutorial_definitions": "tutorial_definition", "archetype_profiles": "archetype_profile"}[file]
		var entries: Variant = registry.call("get_catalog_entries", StringName(category), availability)
		if not entries is Array or entries.is_empty():
			return _failure(&"CONTENT_UNAVAILABLE", {"catalog": file})
		catalogs[file] = entries
	return from_catalogs(catalogs)


static func from_profile_registry(registry: RefCounted, profile: Dictionary) -> Dictionary:
	for availability: StringName in [&"LAUNCH", &"EXPANSION"]:
		var built := from_registry(registry, availability)
		if built.ok and profile.get("catalog_fingerprint") == built.context.catalog.fingerprint():
			return built
	return _failure(&"PROFILE_CONTENT_MISMATCH")


static func from_catalogs(catalogs: Dictionary) -> Dictionary:
	if not Catalog.exact_fields(catalogs, ["meta_nodes", "items", "forge_definitions", "narrative_definitions", "tutorial_definitions", "archetype_profiles"]):
		return _failure(&"CATALOG_SHAPE_INVALID")
	var projected: Array = []
	for row: Variant in catalogs.meta_nodes:
		if not Catalog.exact_fields(row, META_FIELDS) or row.category != "meta_node" or row.schema_version != 1 or not row.node_id is String or row.id != "meta_%s" % row.node_id.to_lower().replace("-", "_") or not row.effects is Dictionary or not row.effects.is_empty():
			return _failure(&"META_DEFINITION_INVALID")
		projected.append({"id": row.node_id, "branch": row.branch, "cost": row.cost, "prerequisites": row.prerequisites, "effects": row.meta_effects})
	var references: Dictionary = {}
	for category: String in Catalog.REFERENCE_CATEGORIES:
		references[category] = []
	var legacy: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_REFERENCES))
	if not Catalog.exact_fields(legacy, ["schema_id", "schema_version", "achievement", "cosmetic"]) or legacy.schema_id != "planewalker.meta_legacy_references" or not Catalog.bounded_int(legacy.schema_version, 1, 1):
		return _failure(&"LEGACY_REFERENCES_INVALID")
	for category: String in ["achievement", "cosmetic"]:
		if not legacy[category] is Array:
			return _failure(&"LEGACY_REFERENCES_INVALID")
		for id: Variant in legacy[category]:
			if not _add_reference(references, category, id):
				return _failure(&"LEGACY_REFERENCES_INVALID")
	for row: Variant in catalogs.items:
		if not row is Dictionary or row.get("category") != "item" or not _add_reference(references, "item", row.get("id")):
			return _failure(&"CONTENT_REFERENCE_INVALID")
	for row: Variant in catalogs.archetype_profiles:
		if not row is Dictionary or not _add_reference(references, "archetype", row.get("archetype_id")):
			return _failure(&"CONTENT_REFERENCE_INVALID")
	for row: Variant in catalogs.forge_definitions:
		if not row is Dictionary:
			return _failure(&"CONTENT_REFERENCE_INVALID")
		if row.get("definition_kind") == "enchantment" and not _add_reference(references, "enchantment", row.get("enchantment_id")):
			return _failure(&"CONTENT_REFERENCE_INVALID")
	for row: Variant in catalogs.tutorial_definitions:
		if not row is Dictionary:
			return _failure(&"CONTENT_REFERENCE_INVALID")
		var pair: Array = {"lesson": ["tutorial_lesson", "lesson_id"], "hint": ["tutorial_hint", "hint_id"], "training_task": ["training_task", "task_id"]}.get(row.get("definition_kind"), [])
		if not pair.is_empty() and not _add_reference(references, pair[0], row.get(pair[1])):
			return _failure(&"CONTENT_REFERENCE_INVALID")
	for row: Variant in catalogs.narrative_definitions:
		if not row is Dictionary:
			return _failure(&"CONTENT_REFERENCE_INVALID")
		var pair: Array = {"artifact": ["artifact", "artifact_id"], "environment_record": ["environment_record", "record_id"], "ending": ["ending", "ending_id"]}.get(row.get("definition_kind"), [])
		if not pair.is_empty() and not _add_reference(references, pair[0], row.get(pair[1])):
			return _failure(&"CONTENT_REFERENCE_INVALID")
		_collect_flags(row, references.narrative_flag)
	for category: String in references:
		references[category].sort()
	var catalog = Catalog.new()
	var configured: Dictionary = catalog.configure(projected, references)
	if not configured.ok:
		return configured
	return {"ok": true, "code": &"OK", "context": {"catalog": catalog, "references": references.duplicate(true)}}


static func _add_reference(references: Dictionary, category: String, id: Variant) -> bool:
	if not Catalog.stable_id(id) or references[category].has(id):
		return false
	references[category].append(id)
	return true


static func _collect_flags(value: Variant, flags: Array) -> void:
	if value is Array:
		for child: Variant in value:
			_collect_flags(child, flags)
	elif value is Dictionary:
		for key: String in value:
			var child: Variant = value[key]
			if key in ["resolution_flag", "completion_flag"] and Catalog.stable_id(child) and not flags.has(child):
				flags.append(child)
			elif key == "flags" and child is Array:
				for flag: Variant in child:
					if Catalog.stable_id(flag) and not flags.has(flag):
						flags.append(flag)
			else:
				_collect_flags(child, flags)


static func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context}
