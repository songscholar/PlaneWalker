class_name EconomyProfile
extends RefCounted

const ROOT_FIELDS: Array[String] = [
	"category", "id", "schema_version", "name_key", "description_key", "availability",
	"floor_income_budgets", "base_prices", "rarity_multipliers", "floor_multipliers",
	"reroll_surcharge", "sell_ratio", "curse_cleanse_cost", "healing_cost", "gold_caps",
	"overflow_decay", "pity_bounds", "inventory_sizes",
]
const FLOOR_BUDGET_FIELDS: Array[String] = [
	"floor_index", "earned_min", "earned_max", "spend_min", "spend_max",
	"remainder_min", "remainder_max",
]
const BASE_PRICE_FIELDS: Array[String] = [
	"common_reward", "uncommon_reward", "rare_reward", "legendary_reward", "healing",
	"curse_cleanse", "reroll", "weapon_upgrade", "route_reveal",
]
const RARITY_FIELDS: Array[String] = ["common", "uncommon", "rare", "legendary", "unique"]
const REROLL_FIELDS: Array[String] = ["base_price", "increment", "maximum_rerolls"]
const PITY_FIELDS: Array[String] = ["rare_offer_min", "rare_offer_max"]
const INVENTORY_FIELDS: Array[String] = ["standard_min", "standard_max", "premium_min", "premium_max"]
const AVAILABILITY: Array[String] = ["LAUNCH", "EXPANSION"]

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
	var fields_error := _exact_fields_error(source, ROOT_FIELDS, "economy")
	if not fields_error.is_empty():
		return fields_error
	if typeof(source["category"]) != TYPE_STRING or str(source["category"]) != "economy_profile":
		return _failure("category", "unsupported")
	if typeof(source["id"]) != TYPE_STRING or str(source["id"]) != "launch_economy_v1":
		return _failure("id", "unsupported")
	if not _is_integer_in_range(source["schema_version"], 1, 1):
		return _failure("schema_version", "unsupported")
	for field: String in ["name_key", "description_key"]:
		if not _valid_localization_key(source[field]):
			return _failure(field, "invalid")
	var availability_result := _normalize_availability(source["availability"])
	if not bool(availability_result.get("ok", false)):
		return availability_result
	var budgets_result := _normalize_floor_budgets(source["floor_income_budgets"])
	if not bool(budgets_result.get("ok", false)):
		return budgets_result
	var prices_result := _normalize_integer_map(source["base_prices"], BASE_PRICE_FIELDS, "base_prices", 0, 1000000)
	if not bool(prices_result.get("ok", false)):
		return prices_result
	var rarity_result := _normalize_positive_number_map(
		source["rarity_multipliers"], RARITY_FIELDS, "rarity_multipliers"
	)
	if not bool(rarity_result.get("ok", false)):
		return rarity_result
	var floor_multiplier_result := _normalize_number_array(
		source["floor_multipliers"], "floor_multipliers", 5, true, false
	)
	if not bool(floor_multiplier_result.get("ok", false)):
		return floor_multiplier_result
	var reroll_result := _normalize_reroll(source["reroll_surcharge"])
	if not bool(reroll_result.get("ok", false)):
		return reroll_result
	if not _is_ratio(source["sell_ratio"], false):
		return _failure("sell_ratio", "out_of_range")
	for field: String in ["curse_cleanse_cost", "healing_cost"]:
		if not _is_integer_in_range(source[field], 0, 1000000):
			return _failure(field, "out_of_range")
	var caps_result := _normalize_number_array(source["gold_caps"], "gold_caps", 5, true, true)
	if not bool(caps_result.get("ok", false)):
		return caps_result
	var gold_caps: Array = caps_result["values"]
	for index: int in range(1, gold_caps.size()):
		if int(gold_caps[index]) < int(gold_caps[index - 1]):
			return _failure("gold_caps[%d]" % index, "must_not_decrease")
	if not _is_ratio(source["overflow_decay"], true):
		return _failure("overflow_decay", "out_of_range")
	var pity_result := _normalize_pity(source["pity_bounds"])
	if not bool(pity_result.get("ok", false)):
		return pity_result
	var inventory_result := _normalize_inventory_sizes(source["inventory_sizes"])
	if not bool(inventory_result.get("ok", false)):
		return inventory_result

	return {
		"ok": true,
		"definition": {
			"category": "economy_profile",
			"id": "launch_economy_v1",
			"schema_version": 1,
			"name_key": str(source["name_key"]),
			"description_key": str(source["description_key"]),
			"availability": AVAILABILITY.duplicate(),
			"floor_income_budgets": (budgets_result["values"] as Array).duplicate(true),
			"base_prices": (prices_result["value"] as Dictionary).duplicate(),
			"rarity_multipliers": (rarity_result["value"] as Dictionary).duplicate(),
			"floor_multipliers": (floor_multiplier_result["values"] as Array).duplicate(),
			"reroll_surcharge": (reroll_result["value"] as Dictionary).duplicate(),
			"sell_ratio": float(source["sell_ratio"]),
			"curse_cleanse_cost": int(source["curse_cleanse_cost"]),
			"healing_cost": int(source["healing_cost"]),
			"gold_caps": gold_caps.duplicate(),
			"overflow_decay": float(source["overflow_decay"]),
			"pity_bounds": (pity_result["value"] as Dictionary).duplicate(),
			"inventory_sizes": (inventory_result["value"] as Dictionary).duplicate(),
		},
	}


func _normalize_availability(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).size() != AVAILABILITY.size():
		return _failure("availability", "exact_launch_expansion_required")
	for index: int in range(AVAILABILITY.size()):
		if typeof((value as Array)[index]) != TYPE_STRING or str((value as Array)[index]) != AVAILABILITY[index]:
			return _failure("availability[%d]" % index, "exact_launch_expansion_required")
	return {"ok": true, "context": {}}


func _normalize_floor_budgets(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).size() != 5:
		return _failure("floor_income_budgets", "expected_five")
	var values: Array[Dictionary] = []
	for index: int in range(5):
		var budget_value: Variant = (value as Array)[index]
		if not budget_value is Dictionary:
			return _failure("floor_income_budgets[%d]" % index, "expected_dictionary")
		var budget: Dictionary = budget_value
		var fields_error := _exact_fields_error(budget, FLOOR_BUDGET_FIELDS, "floor_income_budgets[%d]" % index)
		if not fields_error.is_empty():
			return fields_error
		if not _is_integer_in_range(budget["floor_index"], index + 1, index + 1):
			return _failure("floor_income_budgets[%d].floor_index" % index, "order_mismatch")
		for field: String in FLOOR_BUDGET_FIELDS.slice(1):
			if not _is_integer_in_range(budget[field], 0, 1000000):
				return _failure("floor_income_budgets[%d].%s" % [index, field], "out_of_range")
		for pair: Array in [
			["earned_min", "earned_max"],
			["spend_min", "spend_max"],
			["remainder_min", "remainder_max"],
		]:
			if int(budget[pair[0]]) > int(budget[pair[1]]):
				return _failure("floor_income_budgets[%d].%s" % [index, pair[0]], "greater_than_max")
		var normalized := {"floor_index": index + 1}
		for field: String in FLOOR_BUDGET_FIELDS.slice(1):
			normalized[field] = int(budget[field])
		values.append(normalized)
	return {"ok": true, "values": values, "context": {}}


func _normalize_integer_map(
	value: Variant,
	fields: Array[String],
	path: String,
	minimum: int,
	maximum: int
) -> Dictionary:
	if not value is Dictionary:
		return _failure(path, "expected_dictionary")
	var fields_error := _exact_fields_error(value as Dictionary, fields, path)
	if not fields_error.is_empty():
		return fields_error
	var normalized: Dictionary = {}
	for field: String in fields:
		if not _is_integer_in_range((value as Dictionary)[field], minimum, maximum):
			return _failure("%s.%s" % [path, field], "out_of_range")
		normalized[field] = int((value as Dictionary)[field])
	return {"ok": true, "value": normalized, "context": {}}


func _normalize_positive_number_map(value: Variant, fields: Array[String], path: String) -> Dictionary:
	if not value is Dictionary:
		return _failure(path, "expected_dictionary")
	var fields_error := _exact_fields_error(value as Dictionary, fields, path)
	if not fields_error.is_empty():
		return fields_error
	var normalized: Dictionary = {}
	for field: String in fields:
		var entry: Variant = (value as Dictionary)[field]
		if not _is_finite_number(entry) or float(entry) <= 0.0:
			return _failure("%s.%s" % [path, field], "expected_positive_number")
		normalized[field] = float(entry)
	return {"ok": true, "value": normalized, "context": {}}


func _normalize_number_array(
	value: Variant,
	path: String,
	exact_size: int,
	positive: bool,
	integer_only: bool
) -> Dictionary:
	if not value is Array or (value as Array).size() != exact_size:
		return _failure(path, "unexpected_count")
	var values: Array = []
	for index: int in range(exact_size):
		var entry: Variant = (value as Array)[index]
		if integer_only:
			if not _is_integer_in_range(entry, 1 if positive else 0, 1000000):
				return _failure("%s[%d]" % [path, index], "out_of_range")
			values.append(int(entry))
		else:
			if not _is_finite_number(entry) or (positive and float(entry) <= 0.0):
				return _failure("%s[%d]" % [path, index], "out_of_range")
			values.append(float(entry))
	return {"ok": true, "values": values, "context": {}}


func _normalize_reroll(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("reroll_surcharge", "expected_dictionary")
	var fields_error := _exact_fields_error(value as Dictionary, REROLL_FIELDS, "reroll_surcharge")
	if not fields_error.is_empty():
		return fields_error
	if not _is_integer_in_range((value as Dictionary)["base_price"], 0, 1000000):
		return _failure("reroll_surcharge.base_price", "out_of_range")
	if not _is_integer_in_range((value as Dictionary)["increment"], 1, 1000000):
		return _failure("reroll_surcharge.increment", "out_of_range")
	if not _is_integer_in_range((value as Dictionary)["maximum_rerolls"], 1, 10):
		return _failure("reroll_surcharge.maximum_rerolls", "out_of_range")
	return {
		"ok": true,
		"value": {
			"base_price": int((value as Dictionary)["base_price"]),
			"increment": int((value as Dictionary)["increment"]),
			"maximum_rerolls": int((value as Dictionary)["maximum_rerolls"]),
		},
		"context": {},
	}


func _normalize_pity(value: Variant) -> Dictionary:
	var result := _normalize_integer_map(value, PITY_FIELDS, "pity_bounds", 1, 1000)
	if not bool(result.get("ok", false)):
		return result
	var normalized: Dictionary = result["value"]
	if int(normalized["rare_offer_min"]) > int(normalized["rare_offer_max"]):
		return _failure("pity_bounds.rare_offer_min", "greater_than_max")
	return result


func _normalize_inventory_sizes(value: Variant) -> Dictionary:
	var result := _normalize_integer_map(value, INVENTORY_FIELDS, "inventory_sizes", 1, 8)
	if not bool(result.get("ok", false)):
		return result
	var normalized: Dictionary = result["value"]
	if int(normalized["standard_min"]) > int(normalized["standard_max"]):
		return _failure("inventory_sizes.standard_min", "greater_than_max")
	if int(normalized["premium_min"]) > int(normalized["premium_max"]):
		return _failure("inventory_sizes.premium_min", "greater_than_max")
	return result


func _exact_fields_error(value: Dictionary, fields: Array[String], path: String) -> Dictionary:
	for field: String in fields:
		if not value.has(field):
			return _failure("%s.%s" % [path, field], "missing")
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not fields.has(str(key)):
			return _failure("%s.%s" % [path, str(key)], "unknown")
	return {}


func _valid_localization_key(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile("^[A-Z][A-Z0-9_]{1,127}$") == OK and regex.search(str(value)) != null


func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == floorf(numeric) and numeric >= minimum and numeric <= maximum


func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _is_ratio(value: Variant, allow_zero: bool) -> bool:
	if not _is_finite_number(value):
		return false
	var numeric := float(value)
	return numeric <= 1.0 and (numeric >= 0.0 if allow_zero else numeric > 0.0)


func _failure(field: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"code": &"ECONOMY_PROFILE_INVALID",
		"definition": {},
		"context": {"field": field, "reason": reason},
	}
