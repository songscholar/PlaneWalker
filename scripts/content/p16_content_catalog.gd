class_name P16ContentCatalog
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Forge := preload("res://scripts/progression/forge_runtime.gd")
const Narrative := preload("res://scripts/narrative/narrative_catalog.gd")
const Tutorial := preload("res://scripts/onboarding/tutorial_catalog.gd")
const Hub := preload("res://scripts/content/hub_district_definition.gd")
const COUNTS := {"meta_node": 42, "hub_district": 3, "forge_definition": 20, "narrative_definition": 57, "narrative_source_definition": 13, "tutorial_definition": 34}
const SOURCE_FIELDS := ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "effects", "source_kind", "sequence", "source_receipt_id", "floor_id", "location_id", "requirements", "text_key", "consumption_scope"]


static func parse_entry(source: Dictionary) -> Dictionary:
	var fields: Array = []
	match source.get("category"):
		"meta_node":
			fields = Factory.META_FIELDS
		"hub_district":
			return Hub.new().configure(source)
		"forge_definition":
			fields = Forge.COMMON_FIELDS + {"weapon": Forge.WEAPON_FIELDS, "enchantment": Forge.ENCHANT_FIELDS}.get(source.get("definition_kind"), [])
		"narrative_definition":
			fields = Narrative.COMMON_FIELDS + Narrative.KIND_FIELDS.get(source.get("definition_kind"), [])
		"tutorial_definition":
			fields = Tutorial.COMMON_FIELDS + Tutorial.KIND_FIELDS.get(source.get("definition_kind"), [])
		"narrative_source_definition":
			fields = SOURCE_FIELDS
	if fields.is_empty() or not Catalog.exact_fields(source, fields) or not Catalog.bounded_int(source.schema_version, 1, 1) or not Catalog.stable_id(source.id) or source.availability != ["LAUNCH", "EXPANSION"] or not source.compatibility is Dictionary or not source.compatibility.is_empty() or not source.effects is Dictionary or not source.effects.is_empty():
		return _failure("entry", str(source.get("id", "")))
	var tags: Array = ["launch", "narrative"] if source.category == "narrative_source_definition" else ["launch", "hub"]
	if source.tags != tags:
		return _failure("tags", source.id)
	return {"ok": true, "code": &"OK", "definition": source.duplicate(true), "context": {}}


static func validate_complete(definitions: Array[Dictionary]) -> Dictionary:
	var by_category: Dictionary = {}
	var by_id: Dictionary = {}
	var present := false
	for row: Dictionary in definitions:
		var authored := row.duplicate(true)
		authored.erase("pack_id")
		authored.erase("pack_version")
		if not by_category.has(row.category):
			by_category[row.category] = []
		by_category[row.category].append(authored)
		by_id[row.id] = authored
		present = present or COUNTS.has(row.category)
	if not present:
		return {"ok": true, "code": &"OK", "context": {}}
	for category: String in COUNTS:
		if by_category.get(category, []).size() != COUNTS[category]:
			return _failure("count", category)
	var built := Factory.from_catalogs({"meta_nodes": by_category.meta_node, "items": by_category.get("item", []), "forge_definitions": by_category.forge_definition, "narrative_definitions": by_category.narrative_definition, "tutorial_definitions": by_category.tutorial_definition, "archetype_profiles": by_category.get("archetype_profile", [])})
	if not built.ok:
		return built
	var meta: RefCounted = built.context.catalog
	for result: Dictionary in [Forge.new().configure(by_category.forge_definition, meta), Narrative.new().configure(by_category.narrative_definition, meta, by_category.narrative_source_definition), Tutorial.new().configure(by_category.tutorial_definition, meta)]:
		if not result.ok:
			return result
	var npcs: Dictionary = {}
	for row: Dictionary in by_category.narrative_definition:
		if row.definition_kind == "npc":
			npcs[row.npc_id] = row
		if row.has("floor_id") and not _reference(by_id, row.floor_id, "floor_definition"):
			return _failure("floor_id", row.id)
		if row.definition_kind == "ending" and not _reference(by_id, row.resolved_boss_id, "boss_definition"):
			return _failure("resolved_boss_id", row.id)
	for row: Dictionary in by_category.narrative_source_definition:
		if not _reference(by_id, row.floor_id, "floor_definition"):
			return _failure("floor_id", row.id)
	for row: Dictionary in by_category.hub_district:
		for function: Dictionary in row.functions:
			if not npcs.has(function.npc_id):
				return _failure("npc_id", row.id)
	for npc: Dictionary in npcs.values():
		if not _reference(by_id, npc.district_id, "hub_district"):
			return _failure("district_id", npc.id)
	return {"ok": true, "code": &"OK", "context": {}}


static func _reference(by_id: Dictionary, id: String, category: String) -> bool:
	return by_id.has(id) and by_id[id].category == category and by_id[id].availability.has("LAUNCH") and by_id[id].availability.has("EXPANSION")


static func _failure(field: String, id: String) -> Dictionary:
	return {"ok": false, "code": &"P16_CONTENT_INVALID", "context": {"field": field, "id": id}}
