class_name HubDistrictDefinition
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const FIELDS := ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "effects", "district_id", "scene_path", "arrival", "functions", "repair_stage_milestones"]
const FUNCTIONS := {"hub_council": ["council", "archive", "gateway"], "hub_craft": ["training", "forge", "meditation"], "hub_rift": ["merchant", "gallery", "mirror"]}
var _definition: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	_definition.clear()
	if not Catalog.exact_fields(source, FIELDS) or source.category != "hub_district" or not source.district_id is String or source.district_id not in FUNCTIONS or source.id != source.district_id or not Catalog.bounded_int(source.schema_version, 1, 1):
		return _failure("root")
	if source.availability != ["LAUNCH", "EXPANSION"] or source.tags != ["launch", "hub"] or not source.compatibility is Dictionary or not source.compatibility.is_empty() or not source.effects is Dictionary or not source.effects.is_empty():
		return _failure("metadata")
	if source.scene_path != "res://scenes/hub/%s.tscn" % source.id or not FileAccess.file_exists(source.scene_path) or not _position(source.arrival):
		return _failure("scene_path")
	if not source.functions is Array or source.functions.size() != 3:
		return _failure("functions")
	var seen: Array = []
	for row: Variant in source.functions:
		if not Catalog.exact_fields(row, ["id", "npc_id", "position", "panel_id"]) or row.id not in FUNCTIONS[source.id] or seen.has(row.id) or row.npc_id not in Catalog.NPC_IDS or not _position(row.position) or row.panel_id != "hub_%s_panel" % str(row.id):
			return _failure("functions")
		seen.append(row.id)
	if not source.repair_stage_milestones is Array or source.repair_stage_milestones.size() != 4:
		return _failure("repair_stage_milestones")
	for index: int in range(4):
		var row: Variant = source.repair_stage_milestones[index]
		if not Catalog.exact_fields(row, ["stage", "completed_floor_count"]) or not Catalog.bounded_int(row.stage, index, index) or not Catalog.bounded_int(row.completed_floor_count, [0, 1, 3, 5][index], [0, 1, 3, 5][index]):
			return _failure("repair_stage_milestones")
	_definition = source.duplicate(true)
	return {"ok": true, "code": &"OK", "definition": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _definition.duplicate(true)


static func _position(value: Variant) -> bool:
	return Catalog.exact_fields(value, ["x", "y"]) and Catalog.finite_number(value.x, 0, 1280) and Catalog.finite_number(value.y, 0, 720)


static func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"HUB_DISTRICT_INVALID", "context": {"field": field}}
