class_name MerchantDefinition
extends RefCounted

const ROOT_FIELDS: Array[String] = [
	"category", "id", "schema_version", "name_key", "description_key", "availability",
	"floor_min", "floor_max", "portrait_id", "pixel_proxy_id", "shop_room_template_ids",
	"inventory_rules", "services", "accepted_costs", "economy_profile_id", "intro_key",
	"farewell_key",
]
const INVENTORY_FIELDS: Array[String] = [
	"offer_count_min", "offer_count_max", "rarity_weights", "content_categories",
	"required_tags", "allow_duplicates",
]
const RARITY_FIELDS: Array[String] = ["common", "uncommon", "rare", "legendary", "unique"]
const AVAILABILITY: Array[String] = ["LAUNCH", "EXPANSION"]
const MERCHANT_IDS: Array[String] = [
	"merchant_wayfarer", "merchant_chronomancer", "merchant_forgekeeper",
	"merchant_void_broker", "merchant_echo_archivist",
]
const SHOP_ROOM_TEMPLATE_IDS: Array[String] = [
	"room_shop_wayfarer_tent", "room_shop_chrono_emporium",
]
const CONTENT_CATEGORIES: Array[String] = ["item", "blessing", "curse"]
const SERVICES: Array[String] = [
	"purchase_reward", "heal", "cleanse_curse", "reroll", "weapon_upgrade",
	"health_trade", "route_reveal", "sell_reward",
]
const ACCEPTED_COSTS: Array[String] = ["gold", "health", "time_shard", "forge_essence", "reward"]

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
	var fields_error := _exact_fields_error(source, ROOT_FIELDS, "merchant")
	if not fields_error.is_empty():
		return fields_error
	if typeof(source["category"]) != TYPE_STRING or str(source["category"]) != "merchant_definition":
		return _failure("category", "unsupported")
	if not _is_integer_in_range(source["schema_version"], 1, 1):
		return _failure("schema_version", "unsupported")
	if typeof(source["id"]) != TYPE_STRING or not MERCHANT_IDS.has(str(source["id"])):
		return _failure("id", "unsupported")
	for field: String in ["name_key", "description_key", "intro_key", "farewell_key"]:
		if not _valid_localization_key(source[field]):
			return _failure(field, "invalid")
	var availability_result := _normalize_string_list(
		source["availability"], AVAILABILITY, false, "availability"
	)
	if not bool(availability_result.get("ok", false)):
		return availability_result
	if (availability_result["values"] as Array) != AVAILABILITY:
		return _failure("availability", "exact_launch_expansion_required")
	for field: String in ["floor_min", "floor_max"]:
		if not _is_integer_in_range(source[field], 1, 5):
			return _failure(field, "out_of_range")
	if int(source["floor_min"]) > int(source["floor_max"]):
		return _failure("floor_min", "greater_than_max")
	for field: String in ["portrait_id", "pixel_proxy_id"]:
		if not _valid_id(source[field]):
			return _failure(field, "invalid")
	var room_result := _normalize_string_list(
		source["shop_room_template_ids"], SHOP_ROOM_TEMPLATE_IDS, false, "shop_room_template_ids"
	)
	if not bool(room_result.get("ok", false)):
		return room_result
	var inventory_result := _normalize_inventory_rules(source["inventory_rules"])
	if not bool(inventory_result.get("ok", false)):
		return inventory_result
	var services_result := _normalize_string_list(source["services"], SERVICES, false, "services")
	if not bool(services_result.get("ok", false)):
		return services_result
	if not (services_result["values"] as Array).has("purchase_reward"):
		return _failure("services", "purchase_reward_required")
	var costs_result := _normalize_string_list(
		source["accepted_costs"], ACCEPTED_COSTS, false, "accepted_costs"
	)
	if not bool(costs_result.get("ok", false)):
		return costs_result
	if typeof(source["economy_profile_id"]) != TYPE_STRING or str(source["economy_profile_id"]) != "launch_economy_v1":
		return _failure("economy_profile_id", "unsupported")

	return {
		"ok": true,
		"definition": {
			"category": "merchant_definition",
			"id": str(source["id"]),
			"schema_version": 1,
			"name_key": str(source["name_key"]),
			"description_key": str(source["description_key"]),
			"availability": (availability_result["values"] as Array).duplicate(),
			"floor_min": int(source["floor_min"]),
			"floor_max": int(source["floor_max"]),
			"portrait_id": str(source["portrait_id"]),
			"pixel_proxy_id": str(source["pixel_proxy_id"]),
			"shop_room_template_ids": (room_result["values"] as Array).duplicate(),
			"inventory_rules": (inventory_result["value"] as Dictionary).duplicate(true),
			"services": (services_result["values"] as Array).duplicate(),
			"accepted_costs": (costs_result["values"] as Array).duplicate(),
			"economy_profile_id": "launch_economy_v1",
			"intro_key": str(source["intro_key"]),
			"farewell_key": str(source["farewell_key"]),
		},
	}


func _normalize_inventory_rules(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("inventory_rules", "expected_dictionary")
	var fields_error := _exact_fields_error(value as Dictionary, INVENTORY_FIELDS, "inventory_rules")
	if not fields_error.is_empty():
		return fields_error
	for field: String in ["offer_count_min", "offer_count_max"]:
		if not _is_integer_in_range((value as Dictionary)[field], 1, 8):
			return _failure("inventory_rules.%s" % field, "out_of_range")
	if int((value as Dictionary)["offer_count_min"]) > int((value as Dictionary)["offer_count_max"]):
		return _failure("inventory_rules.offer_count_min", "greater_than_max")
	var rarity_result := _normalize_rarity_weights((value as Dictionary)["rarity_weights"])
	if not bool(rarity_result.get("ok", false)):
		return rarity_result
	var categories_result := _normalize_string_list(
		(value as Dictionary)["content_categories"],
		CONTENT_CATEGORIES,
		false,
		"inventory_rules.content_categories"
	)
	if not bool(categories_result.get("ok", false)):
		return categories_result
	var tags_result := _normalize_id_list(
		(value as Dictionary)["required_tags"], true, "inventory_rules.required_tags"
	)
	if not bool(tags_result.get("ok", false)):
		return tags_result
	if typeof((value as Dictionary)["allow_duplicates"]) != TYPE_BOOL or bool((value as Dictionary)["allow_duplicates"]):
		return _failure("inventory_rules.allow_duplicates", "must_be_false")
	return {
		"ok": true,
		"value": {
			"offer_count_min": int((value as Dictionary)["offer_count_min"]),
			"offer_count_max": int((value as Dictionary)["offer_count_max"]),
			"rarity_weights": (rarity_result["value"] as Dictionary).duplicate(),
			"content_categories": (categories_result["values"] as Array).duplicate(),
			"required_tags": (tags_result["values"] as Array).duplicate(),
			"allow_duplicates": false,
		},
		"context": {},
	}


func _normalize_rarity_weights(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("inventory_rules.rarity_weights", "expected_dictionary")
	var fields_error := _exact_fields_error(value as Dictionary, RARITY_FIELDS, "inventory_rules.rarity_weights")
	if not fields_error.is_empty():
		return fields_error
	var normalized: Dictionary = {}
	var total := 0.0
	for field: String in RARITY_FIELDS:
		var weight: Variant = (value as Dictionary)[field]
		if not _is_finite_number(weight) or float(weight) < 0.0 or float(weight) > 1.0:
			return _failure("inventory_rules.rarity_weights.%s" % field, "out_of_range")
		normalized[field] = float(weight)
		total += float(weight)
	if absf(total - 1.0) > 0.0001:
		return _failure("inventory_rules.rarity_weights", "must_sum_to_one")
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


func _normalize_id_list(value: Variant, allow_empty: bool, field: String) -> Dictionary:
	if not value is Array or (not allow_empty and (value as Array).is_empty()):
		return _failure(field, "expected_array")
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


func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _failure(field: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"code": &"MERCHANT_DEFINITION_INVALID",
		"definition": {},
		"context": {"field": field, "reason": reason},
	}
