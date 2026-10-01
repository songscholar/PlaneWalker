class_name FloorDefinition
extends RefCounted

const ROOT_FIELDS: Array[String] = [
	"category", "id", "schema_version", "name_key", "description_key", "availability",
	"order", "route_room_min", "route_room_max", "graph_node_min", "graph_node_max",
	"allowed_room_types", "required_room_budgets", "environment_rule_id",
	"encounter_profile_id", "economy_profile_id", "merchant_ids", "event_ids",
	"palette_id", "music_cue_id", "boss_room_template_id", "boss_encounter_id",
]
const BUDGET_FIELDS: Array[String] = [
	"shop_or_treasure_min", "shop_min", "treasure_min", "event_min", "rest_min", "boss_count",
]
const AVAILABILITY: Array[String] = ["LAUNCH", "EXPANSION"]
const ROOM_TYPES: Array[String] = ["combat", "elite", "treasure", "shop", "event", "boss", "rest"]
const FLOOR_IDS: Array[String] = [
	"floor_ruins_of_remnant", "floor_void_forest", "floor_time_rift",
	"floor_plane_forge", "floor_throne_of_void",
]
const ENVIRONMENT_RULE_IDS: Array[String] = [
	"rule_crumbling_ground", "rule_void_spores", "rule_temporal_distortion",
	"rule_forge_vents", "rule_collapsing_plane",
]
const ENCOUNTER_PROFILE_IDS: Array[String] = [
	"encounter_profile_ruins_adapter_v1", "encounter_profile_forest_adapter_v1",
	"encounter_profile_rift_adapter_v1", "encounter_profile_forge_adapter_v1",
	"encounter_profile_throne_adapter_v1",
]
const BOSS_ROOM_TEMPLATE_IDS: Array[String] = [
	"room_boss_ruin_king", "room_boss_forest_heart", "room_boss_time_sovereign",
	"room_boss_forge_colossus", "room_boss_void_throne",
]
const BOSS_ENCOUNTER_IDS: Array[String] = [
	"boss_encounter_ruin_king_adapter_v1", "boss_encounter_forest_heart_adapter_v1",
	"boss_encounter_time_sovereign_adapter_v1", "boss_encounter_forge_colossus_adapter_v1",
	"boss_encounter_void_throne_adapter_v1",
]
const PALETTE_IDS: Array[String] = [
	"palette_ruins_of_remnant", "palette_void_forest", "palette_time_rift",
	"palette_plane_forge", "palette_throne_of_void",
]
const MUSIC_CUE_IDS: Array[String] = [
	"music_ruins_of_remnant", "music_void_forest", "music_time_rift",
	"music_plane_forge", "music_throne_of_void",
]
const MERCHANT_IDS: Array[String] = [
	"merchant_wayfarer", "merchant_chronomancer", "merchant_forgekeeper",
	"merchant_void_broker", "merchant_echo_archivist",
]
const EVENT_IDS: Array[String] = [
	"event_chronal_altar", "event_trapped_traveler", "event_cursed_pool",
	"event_smiths_legacy", "event_memory_mirror", "event_planar_merchant",
	"event_void_rift", "event_sleeping_guardian", "event_twisted_well",
	"event_soul_contract", "event_time_paradox", "event_sacrificial_altar",
	"event_lost_journal", "event_rift_garden", "event_final_choice",
	"event_void_whispers", "event_perfect_rewind", "event_old_reunion",
]
const FLOOR_CONTRACTS := {
	"floor_ruins_of_remnant": {
		"route_rooms": 6,
		"graph_nodes": 9,
		"allowed_room_types": ["combat", "elite", "treasure", "shop", "event", "boss", "rest"],
		"required_room_budgets": {"shop_or_treasure_min": 1, "shop_min": 0, "treasure_min": 0, "event_min": 1, "rest_min": 1, "boss_count": 1},
	},
	"floor_void_forest": {
		"route_rooms": 7,
		"graph_nodes": 10,
		"allowed_room_types": ["combat", "elite", "treasure", "shop", "event", "boss", "rest"],
		"required_room_budgets": {"shop_or_treasure_min": 1, "shop_min": 0, "treasure_min": 0, "event_min": 1, "rest_min": 1, "boss_count": 1},
	},
	"floor_time_rift": {
		"route_rooms": 8,
		"graph_nodes": 12,
		"allowed_room_types": ["combat", "elite", "treasure", "shop", "event", "boss", "rest"],
		"required_room_budgets": {"shop_or_treasure_min": 1, "shop_min": 0, "treasure_min": 0, "event_min": 2, "rest_min": 1, "boss_count": 1},
	},
	"floor_plane_forge": {
		"route_rooms": 9,
		"graph_nodes": 14,
		"allowed_room_types": ["combat", "elite", "treasure", "shop", "event", "boss", "rest"],
		"required_room_budgets": {"shop_or_treasure_min": 0, "shop_min": 1, "treasure_min": 1, "event_min": 1, "rest_min": 1, "boss_count": 1},
	},
	"floor_throne_of_void": {
		"route_rooms": 7,
		"graph_nodes": 9,
		"allowed_room_types": ["combat", "elite", "treasure", "shop", "event", "boss"],
		"required_room_budgets": {"shop_or_treasure_min": 1, "shop_min": 0, "treasure_min": 0, "event_min": 1, "rest_min": 0, "boss_count": 1},
	},
}

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
	var fields_error := _exact_fields_error(source, ROOT_FIELDS, "floor")
	if not fields_error.is_empty():
		return fields_error
	if typeof(source["category"]) != TYPE_STRING or str(source["category"]) != "floor_definition":
		return _failure("category", "unsupported")
	if not _is_integer_in_range(source["schema_version"], 1, 1):
		return _failure("schema_version", "unsupported")
	var floor_id := str(source["id"]) if typeof(source["id"]) == TYPE_STRING else ""
	if not FLOOR_IDS.has(floor_id):
		return _failure("id", "unsupported")
	var floor_index := FLOOR_IDS.find(floor_id)
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
	if not _is_integer_in_range(source["order"], 1, FLOOR_IDS.size()):
		return _failure("order", "out_of_range")
	if int(source["order"]) != floor_index + 1:
		return _failure("order", "floor_identity_mismatch")
	for field: String in ["route_room_min", "route_room_max"]:
		if not _is_integer_in_range(source[field], 6, 9):
			return _failure(field, "out_of_range")
	if int(source["route_room_min"]) > int(source["route_room_max"]):
		return _failure("route_room_min", "greater_than_max")
	for field: String in ["graph_node_min", "graph_node_max"]:
		if not _is_integer_in_range(source[field], 9, 14):
			return _failure(field, "out_of_range")
	if int(source["graph_node_min"]) > int(source["graph_node_max"]):
		return _failure("graph_node_min", "greater_than_max")
	if int(source["graph_node_min"]) < int(source["route_room_min"]) + 1:
		return _failure("graph_node_min", "below_route_capacity")
	var room_types_result := _normalize_string_list(
		source["allowed_room_types"], ROOM_TYPES, false, "allowed_room_types"
	)
	if not bool(room_types_result.get("ok", false)):
		return room_types_result
	if (room_types_result["values"] as Array).size() < 6:
		return _failure("allowed_room_types", "insufficient_coverage")
	if not (room_types_result["values"] as Array).has("boss"):
		return _failure("allowed_room_types", "boss_required")
	var budget_result := _normalize_budgets(source["required_room_budgets"])
	if not bool(budget_result.get("ok", false)):
		return budget_result
	if (
		int((budget_result["value"] as Dictionary)["rest_min"]) > 0
		and not (room_types_result["values"] as Array).has("rest")
	):
		return _failure("required_room_budgets.rest_min", "room_type_unavailable")
	var floor_contract: Dictionary = FLOOR_CONTRACTS[floor_id]
	if (
		int(source["route_room_min"]) != int(floor_contract["route_rooms"])
		or int(source["route_room_max"]) != int(floor_contract["route_rooms"])
	):
		return _failure("route_room_min", "floor_contract_mismatch")
	if (
		int(source["graph_node_min"]) != int(floor_contract["graph_nodes"])
		or int(source["graph_node_max"]) != int(floor_contract["graph_nodes"])
	):
		return _failure("graph_node_min", "floor_contract_mismatch")
	if (room_types_result["values"] as Array) != (floor_contract["allowed_room_types"] as Array):
		return _failure("allowed_room_types", "floor_contract_mismatch")
	if (budget_result["value"] as Dictionary) != (floor_contract["required_room_budgets"] as Dictionary):
		return _failure("required_room_budgets", "floor_contract_mismatch")
	for identity_case: Dictionary in [
		{"field": "environment_rule_id", "values": ENVIRONMENT_RULE_IDS},
		{"field": "encounter_profile_id", "values": ENCOUNTER_PROFILE_IDS},
		{"field": "boss_room_template_id", "values": BOSS_ROOM_TEMPLATE_IDS},
		{"field": "boss_encounter_id", "values": BOSS_ENCOUNTER_IDS},
		{"field": "palette_id", "values": PALETTE_IDS},
		{"field": "music_cue_id", "values": MUSIC_CUE_IDS},
	]:
		var field := str(identity_case["field"])
		if typeof(source[field]) != TYPE_STRING:
			return _failure(field, "expected_string")
		var values: Array = identity_case["values"]
		if values.find(str(source[field])) != floor_index:
			return _failure(field, "floor_identity_mismatch")
	if typeof(source["economy_profile_id"]) != TYPE_STRING or str(source["economy_profile_id"]) != "launch_economy_v1":
		return _failure("economy_profile_id", "unsupported")
	var merchant_result := _normalize_string_list(source["merchant_ids"], MERCHANT_IDS, false, "merchant_ids")
	if not bool(merchant_result.get("ok", false)):
		return merchant_result
	var event_result := _normalize_string_list(source["event_ids"], EVENT_IDS, false, "event_ids")
	if not bool(event_result.get("ok", false)):
		return event_result
	return {
		"ok": true,
		"definition": {
			"category": "floor_definition",
			"id": floor_id,
			"schema_version": 1,
			"name_key": str(source["name_key"]),
			"description_key": str(source["description_key"]),
			"availability": (availability_result["values"] as Array).duplicate(),
			"order": int(source["order"]),
			"route_room_min": int(source["route_room_min"]),
			"route_room_max": int(source["route_room_max"]),
			"graph_node_min": int(source["graph_node_min"]),
			"graph_node_max": int(source["graph_node_max"]),
			"allowed_room_types": (room_types_result["values"] as Array).duplicate(),
			"required_room_budgets": (budget_result["value"] as Dictionary).duplicate(true),
			"environment_rule_id": str(source["environment_rule_id"]),
			"encounter_profile_id": str(source["encounter_profile_id"]),
			"economy_profile_id": "launch_economy_v1",
			"merchant_ids": (merchant_result["values"] as Array).duplicate(),
			"event_ids": (event_result["values"] as Array).duplicate(),
			"palette_id": str(source["palette_id"]),
			"music_cue_id": str(source["music_cue_id"]),
			"boss_room_template_id": str(source["boss_room_template_id"]),
			"boss_encounter_id": str(source["boss_encounter_id"]),
		},
	}


func _normalize_budgets(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("required_room_budgets", "expected_dictionary")
	var fields_error := _exact_fields_error(value as Dictionary, BUDGET_FIELDS, "required_room_budgets")
	if not fields_error.is_empty():
		return fields_error
	var normalized: Dictionary = {}
	var ranges := {
		"shop_or_treasure_min": Vector2i(0, 1),
		"shop_min": Vector2i(0, 1),
		"treasure_min": Vector2i(0, 1),
		"event_min": Vector2i(1, 2),
		"rest_min": Vector2i(0, 1),
		"boss_count": Vector2i(1, 1),
	}
	for field: String in BUDGET_FIELDS:
		var allowed_range: Vector2i = ranges[field]
		if not _is_integer_in_range((value as Dictionary)[field], allowed_range.x, allowed_range.y):
			return _failure("required_room_budgets.%s" % field, "out_of_range")
		normalized[field] = int((value as Dictionary)[field])
	if int(normalized["boss_count"]) != 1:
		return _failure("required_room_budgets.boss_count", "expected_one")
	return {"ok": true, "value": normalized, "context": {}}


func _normalize_string_list(value: Variant, allowed: Array[String], allow_empty: bool, field: String) -> Dictionary:
	if not value is Array or (not allow_empty and (value as Array).is_empty()):
		return _failure(field, "expected_non_empty_array")
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


func _normalize_id_list(value: Variant, allow_empty: bool, field: String) -> Dictionary:
	if not value is Array or (not allow_empty and (value as Array).is_empty()):
		return _failure(field, "expected_non_empty_array")
	var normalized: Array[String] = []
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry: Variant = (value as Array)[index]
		if not _valid_id(entry):
			return _failure("%s[%d]" % [field, index], "invalid")
		var text := str(entry)
		if seen.has(text):
			return _failure("%s[%d]" % [field, index], "duplicate")
		seen[text] = true
		normalized.append(text)
	return {"ok": true, "values": normalized, "context": {}}


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


func _failure(field: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"code": &"FLOOR_DEFINITION_INVALID",
		"definition": {},
		"context": {"field": field, "reason": reason},
	}
