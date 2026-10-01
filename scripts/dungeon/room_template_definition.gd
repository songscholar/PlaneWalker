class_name RoomTemplateDefinition
extends RefCounted

const ROOT_FIELDS: Array[String] = [
	"category", "id", "schema_version", "name_key", "description_key", "availability",
	"room_type", "scene_path", "floor_ids", "door_anchors", "camera_bounds",
	"spawn_anchors", "interaction_anchors", "supported_environment_rule_ids",
	"accessibility_safe_hazard_zones", "thumbnail_id", "icon_id",
]
const POSITION_FIELDS: Array[String] = ["x", "y"]
const BOUNDS_FIELDS: Array[String] = ["x", "y", "width", "height"]
const DOOR_FIELDS: Array[String] = ["id", "direction", "position"]
const ANCHOR_FIELDS: Array[String] = ["id", "kind", "position"]
const ZONE_FIELDS: Array[String] = ["id", "bounds"]
const AVAILABILITY: Array[String] = ["LAUNCH", "EXPANSION"]
const ROOM_TYPES: Array[String] = ["combat", "elite", "treasure", "shop", "event", "boss", "rest"]
const ROOM_IDS: Array[String] = [
	"room_combat_pillared_hall", "room_combat_split_chambers", "room_combat_open_field",
	"room_combat_l_corner", "room_combat_crossroads", "room_combat_high_ground",
	"room_combat_void_grove", "room_combat_ring", "room_combat_bridge",
	"room_combat_clockwork", "room_elite_arena", "room_elite_guard_corridor",
	"room_elite_altar_defense", "room_elite_trap_arena", "room_elite_twin_hall",
	"room_treasure_vault", "room_treasure_wishing_pool", "room_treasure_chronovault",
	"room_shop_wayfarer_tent", "room_shop_chrono_emporium", "room_event_shrine",
	"room_event_crossroads", "room_event_mirror_hall", "room_boss_ruin_king",
	"room_boss_forest_heart", "room_boss_time_sovereign", "room_boss_forge_colossus",
	"room_boss_void_throne", "room_rest_campfire", "room_rest_sanctuary",
]
const ROOM_IDS_BY_TYPE := {
	"combat": [
		"room_combat_pillared_hall", "room_combat_split_chambers", "room_combat_open_field",
		"room_combat_l_corner", "room_combat_crossroads", "room_combat_high_ground",
		"room_combat_void_grove", "room_combat_ring", "room_combat_bridge", "room_combat_clockwork",
	],
	"elite": [
		"room_elite_arena", "room_elite_guard_corridor", "room_elite_altar_defense",
		"room_elite_trap_arena", "room_elite_twin_hall",
	],
	"treasure": ["room_treasure_vault", "room_treasure_wishing_pool", "room_treasure_chronovault"],
	"shop": ["room_shop_wayfarer_tent", "room_shop_chrono_emporium"],
	"event": ["room_event_shrine", "room_event_crossroads", "room_event_mirror_hall"],
	"boss": [
		"room_boss_ruin_king", "room_boss_forest_heart", "room_boss_time_sovereign",
		"room_boss_forge_colossus", "room_boss_void_throne",
	],
	"rest": ["room_rest_campfire", "room_rest_sanctuary"],
}
const FLOOR_IDS: Array[String] = [
	"floor_ruins_of_remnant", "floor_void_forest", "floor_time_rift",
	"floor_plane_forge", "floor_throne_of_void",
]
const ENVIRONMENT_RULE_IDS: Array[String] = [
	"rule_crumbling_ground", "rule_void_spores", "rule_temporal_distortion",
	"rule_forge_vents", "rule_collapsing_plane",
]
const DOOR_DIRECTIONS: Array[String] = ["north", "east", "south", "west"]
const SPAWN_KINDS: Array[String] = ["player", "enemy", "elite", "boss"]
const INTERACTION_KINDS: Array[String] = ["treasure", "shop", "event", "rest", "exit"]
const SCENE_PREFIX := "res://data/content_packs/base/assets/rooms/launch/"

var _snapshot: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	_snapshot.clear()
	var normalized_result := _normalize(source)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result
	_snapshot = (normalized_result["definition"] as Dictionary).duplicate(true)
	return {"ok": true, "definition": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _normalize(source: Dictionary) -> Dictionary:
	var fields_error := _exact_fields_error(source, ROOT_FIELDS, "room")
	if not fields_error.is_empty():
		return fields_error
	if typeof(source["category"]) != TYPE_STRING or str(source["category"]) != "room_template":
		return _failure("category", "unsupported")
	if not _is_integer_in_range(source["schema_version"], 1, 1):
		return _failure("schema_version", "unsupported")
	if typeof(source["id"]) != TYPE_STRING or not ROOM_IDS.has(str(source["id"])):
		return _failure("id", "unsupported")
	var room_id := str(source["id"])
	if not _valid_localization_key(source["name_key"]):
		return _failure("name_key", "invalid")
	if not _valid_localization_key(source["description_key"]):
		return _failure("description_key", "invalid")
	var availability_result := _normalize_string_list(
		source["availability"], AVAILABILITY, false, "availability"
	)
	if not bool(availability_result.get("ok", false)):
		return availability_result
	if (availability_result["values"] as Array) != AVAILABILITY:
		return _failure("availability", "exact_launch_expansion_required")
	if typeof(source["room_type"]) != TYPE_STRING or not ROOM_TYPES.has(str(source["room_type"])):
		return _failure("room_type", "unsupported")
	var room_type := str(source["room_type"])
	if not (ROOM_IDS_BY_TYPE[room_type] as Array).has(room_id):
		return _failure("room_type", "room_identity_mismatch")
	if typeof(source["scene_path"]) != TYPE_STRING:
		return _failure("scene_path", "expected_string")
	var scene_path := str(source["scene_path"])
	if not scene_path.begins_with(SCENE_PREFIX) or not scene_path.ends_with(".tscn"):
		return _failure("scene_path", "outside_launch_room_boundary")
	if scene_path.contains("..") or scene_path.trim_prefix(SCENE_PREFIX).contains("/"):
		return _failure("scene_path", "nested_or_traversal_path")
	var floor_result := _normalize_string_list(source["floor_ids"], FLOOR_IDS, false, "floor_ids")
	if not bool(floor_result.get("ok", false)):
		return floor_result
	var door_result := _normalize_doors(source["door_anchors"])
	if not bool(door_result.get("ok", false)):
		return door_result
	var camera_result := _normalize_bounds(source["camera_bounds"], "camera_bounds")
	if not bool(camera_result.get("ok", false)):
		return camera_result
	var spawn_result := _normalize_anchors(
		source["spawn_anchors"], SPAWN_KINDS, false, "spawn_anchors"
	)
	if not bool(spawn_result.get("ok", false)):
		return spawn_result
	var player_spawn_count := 0
	for anchor: Dictionary in spawn_result["values"]:
		if str(anchor["kind"]) == "player":
			player_spawn_count += 1
	if player_spawn_count != 1:
		return _failure("spawn_anchors", "exactly_one_player_required")
	var interaction_result := _normalize_anchors(
		source["interaction_anchors"], INTERACTION_KINDS, true, "interaction_anchors"
	)
	if not bool(interaction_result.get("ok", false)):
		return interaction_result
	var rule_result := _normalize_string_list(
		source["supported_environment_rule_ids"],
		ENVIRONMENT_RULE_IDS,
		false,
		"supported_environment_rule_ids"
	)
	if not bool(rule_result.get("ok", false)):
		return rule_result
	var expected_rules: Array[String] = []
	for floor_id_value: Variant in floor_result["values"]:
		var floor_index := FLOOR_IDS.find(str(floor_id_value))
		expected_rules.append(ENVIRONMENT_RULE_IDS[floor_index])
	var actual_rules: Array = (rule_result["values"] as Array).duplicate()
	expected_rules.sort()
	actual_rules.sort()
	if actual_rules != expected_rules:
		return _failure("supported_environment_rule_ids", "floor_rule_mismatch")
	var zone_result := _normalize_zones(source["accessibility_safe_hazard_zones"])
	if not bool(zone_result.get("ok", false)):
		return zone_result
	for field: String in ["thumbnail_id", "icon_id"]:
		if not _valid_id(source[field]):
			return _failure(field, "invalid")

	return {
		"ok": true,
		"definition": {
			"category": "room_template",
			"id": room_id,
			"schema_version": 1,
			"name_key": str(source["name_key"]),
			"description_key": str(source["description_key"]),
			"availability": (availability_result["values"] as Array).duplicate(),
			"room_type": room_type,
			"scene_path": scene_path,
			"floor_ids": (floor_result["values"] as Array).duplicate(),
			"door_anchors": (door_result["values"] as Array).duplicate(true),
			"camera_bounds": (camera_result["value"] as Dictionary).duplicate(true),
			"spawn_anchors": (spawn_result["values"] as Array).duplicate(true),
			"interaction_anchors": (interaction_result["values"] as Array).duplicate(true),
			"supported_environment_rule_ids": (rule_result["values"] as Array).duplicate(),
			"accessibility_safe_hazard_zones": (zone_result["values"] as Array).duplicate(true),
			"thumbnail_id": str(source["thumbnail_id"]),
			"icon_id": str(source["icon_id"]),
		},
	}


func _normalize_doors(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).size() < 2:
		return _failure("door_anchors", "expected_two_or_more")
	var values: Array[Dictionary] = []
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry: Variant = (value as Array)[index]
		if not entry is Dictionary:
			return _failure("door_anchors[%d]" % index, "expected_dictionary")
		var fields_error := _exact_fields_error(entry as Dictionary, DOOR_FIELDS, "door_anchors[%d]" % index)
		if not fields_error.is_empty():
			return fields_error
		var anchor_id := _claim_id((entry as Dictionary)["id"], seen, "door_anchors", index)
		if anchor_id.is_empty():
			return _failure("door_anchors[%d].id" % index, "invalid_or_duplicate")
		if typeof((entry as Dictionary)["direction"]) != TYPE_STRING or not DOOR_DIRECTIONS.has(str((entry as Dictionary)["direction"])):
			return _failure("door_anchors[%d].direction" % index, "unsupported")
		var position_result := _normalize_position((entry as Dictionary)["position"], "door_anchors[%d].position" % index)
		if not bool(position_result.get("ok", false)):
			return position_result
		values.append({
			"id": anchor_id,
			"direction": str((entry as Dictionary)["direction"]),
			"position": (position_result["value"] as Dictionary).duplicate(),
		})
	return {"ok": true, "values": values, "context": {}}


func _normalize_anchors(value: Variant, allowed_kinds: Array[String], allow_empty: bool, field: String) -> Dictionary:
	if not value is Array or (not allow_empty and (value as Array).is_empty()):
		return _failure(field, "expected_array")
	var values: Array[Dictionary] = []
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry: Variant = (value as Array)[index]
		if not entry is Dictionary:
			return _failure("%s[%d]" % [field, index], "expected_dictionary")
		var fields_error := _exact_fields_error(entry as Dictionary, ANCHOR_FIELDS, "%s[%d]" % [field, index])
		if not fields_error.is_empty():
			return fields_error
		var anchor_id := _claim_id((entry as Dictionary)["id"], seen, field, index)
		if anchor_id.is_empty():
			return _failure("%s[%d].id" % [field, index], "invalid_or_duplicate")
		if typeof((entry as Dictionary)["kind"]) != TYPE_STRING or not allowed_kinds.has(str((entry as Dictionary)["kind"])):
			return _failure("%s[%d].kind" % [field, index], "unsupported")
		var position_result := _normalize_position((entry as Dictionary)["position"], "%s[%d].position" % [field, index])
		if not bool(position_result.get("ok", false)):
			return position_result
		values.append({
			"id": anchor_id,
			"kind": str((entry as Dictionary)["kind"]),
			"position": (position_result["value"] as Dictionary).duplicate(),
		})
	return {"ok": true, "values": values, "context": {}}


func _normalize_zones(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).is_empty():
		return _failure("accessibility_safe_hazard_zones", "expected_non_empty_array")
	var values: Array[Dictionary] = []
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry: Variant = (value as Array)[index]
		if not entry is Dictionary:
			return _failure("accessibility_safe_hazard_zones[%d]" % index, "expected_dictionary")
		var fields_error := _exact_fields_error(entry as Dictionary, ZONE_FIELDS, "accessibility_safe_hazard_zones[%d]" % index)
		if not fields_error.is_empty():
			return fields_error
		var zone_id := _claim_id((entry as Dictionary)["id"], seen, "accessibility_safe_hazard_zones", index)
		if zone_id.is_empty():
			return _failure("accessibility_safe_hazard_zones[%d].id" % index, "invalid_or_duplicate")
		var bounds_result := _normalize_bounds((entry as Dictionary)["bounds"], "accessibility_safe_hazard_zones[%d].bounds" % index)
		if not bool(bounds_result.get("ok", false)):
			return bounds_result
		values.append({"id": zone_id, "bounds": (bounds_result["value"] as Dictionary).duplicate()})
	return {"ok": true, "values": values, "context": {}}


func _normalize_position(value: Variant, field: String) -> Dictionary:
	if not value is Dictionary:
		return _failure(field, "expected_dictionary")
	var fields_error := _exact_fields_error(value as Dictionary, POSITION_FIELDS, field)
	if not fields_error.is_empty():
		return fields_error
	var normalized: Dictionary = {}
	for coordinate: String in POSITION_FIELDS:
		if not _is_finite_number((value as Dictionary)[coordinate]):
			return _failure("%s.%s" % [field, coordinate], "expected_finite_number")
		normalized[coordinate] = float((value as Dictionary)[coordinate])
	return {"ok": true, "value": normalized, "context": {}}


func _normalize_bounds(value: Variant, field: String) -> Dictionary:
	if not value is Dictionary:
		return _failure(field, "expected_dictionary")
	var fields_error := _exact_fields_error(value as Dictionary, BOUNDS_FIELDS, field)
	if not fields_error.is_empty():
		return fields_error
	var normalized: Dictionary = {}
	for coordinate: String in BOUNDS_FIELDS:
		if not _is_finite_number((value as Dictionary)[coordinate]):
			return _failure("%s.%s" % [field, coordinate], "expected_finite_number")
		normalized[coordinate] = float((value as Dictionary)[coordinate])
	if float(normalized["width"]) <= 0.0 or float(normalized["height"]) <= 0.0:
		return _failure(field, "non_positive_size")
	return {"ok": true, "value": normalized, "context": {}}


func _normalize_string_list(value: Variant, allowed: Array[String], allow_empty: bool, field: String) -> Dictionary:
	if not value is Array or (not allow_empty and (value as Array).is_empty()):
		return _failure(field, "expected_array")
	var normalized: Array[String] = []
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry: Variant = (value as Array)[index]
		if typeof(entry) != TYPE_STRING or not allowed.has(str(entry)):
			return _failure("%s[%d]" % [field, index], "unsupported")
		if seen.has(str(entry)):
			return _failure("%s[%d]" % [field, index], "duplicate")
		seen[str(entry)] = true
		normalized.append(str(entry))
	return {"ok": true, "values": normalized, "context": {}}


func _claim_id(value: Variant, seen: Dictionary, _field: String, _index: int) -> String:
	if not _valid_id(value):
		return ""
	var text := str(value)
	if seen.has(text):
		return ""
	seen[text] = true
	return text


func _exact_fields_error(value: Dictionary, fields: Array[String], path: String) -> Dictionary:
	for field: String in fields:
		if not value.has(field):
			return _failure("%s.%s" % [path, field], "missing")
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not fields.has(str(key)):
			return _failure("%s.%s" % [path, str(key)], "unknown")
	return {}


func _valid_id(value: Variant) -> bool:
	return _matches("^[a-z][a-z0-9_]{0,95}$", value)


func _valid_localization_key(value: Variant) -> bool:
	return _matches("^[A-Z][A-Z0-9_]{1,127}$", value)


func _matches(pattern: String, value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(str(value)) != null


func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == floorf(numeric) and numeric >= minimum and numeric <= maximum


func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _failure(field: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"code": &"ROOM_TEMPLATE_INVALID",
		"definition": {},
		"context": {"field": field, "reason": reason},
	}
