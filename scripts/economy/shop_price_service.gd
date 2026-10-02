class_name ShopPriceService
extends RefCounted

const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")

const MAX_SAFE_PRICE := 9_007_199_254_740_991
const RARITIES: Array[String] = ["common", "uncommon", "rare", "legendary", "unique"]
const REWARD_BASE_PRICE_IDS: Array[String] = [
	"common_reward",
	"uncommon_reward",
	"rare_reward",
	"legendary_reward",
]
const REWARD_BASE_BY_RARITY := {
	"common": "common_reward",
	"uncommon": "uncommon_reward",
	"rare": "rare_reward",
	"legendary": "legendary_reward",
	"unique": "legendary_reward",
}
const SERVICE_BASE_PRICE_IDS := {
	"heal": "healing",
	"cleanse_curse": "curse_cleanse",
	"weapon_upgrade": "weapon_upgrade",
	"route_reveal": "route_reveal",
}
const NON_GOLD_SERVICES: Array[String] = ["health_trade", "sell_reward"]


static func price(
	base_price: int,
	floor_multiplier: float,
	rarity_multiplier: float,
	reroll_count: int,
	reroll_step: float
) -> int:
	if (
		base_price < 0
		or not is_finite(floor_multiplier)
		or floor_multiplier <= 0.0
		or not is_finite(rarity_multiplier)
		or rarity_multiplier <= 0.0
		or reroll_count < 0
		or not is_finite(reroll_step)
		or reroll_step < 0.0
	):
		return -1
	var surcharge := 1.0 + float(reroll_count) * reroll_step
	var calculated := float(base_price) * floor_multiplier * rarity_multiplier * surcharge
	if not is_finite(calculated) or calculated < 0.0 or calculated > float(MAX_SAFE_PRICE):
		return -1
	return maxi(1, ceili(calculated))


func reward_price(
	profile: Dictionary,
	definition: Dictionary,
	floor_index: int,
	reroll_count: int
) -> Dictionary:
	var profile_result := _validated_profile(profile)
	if not bool(profile_result.get("ok", false)):
		return profile_result
	var normalized: Dictionary = profile_result["profile"]
	var floor_result := _floor_multiplier(normalized, floor_index)
	if not bool(floor_result.get("ok", false)):
		return floor_result
	var rarity_value: Variant = definition.get("rarity")
	if typeof(rarity_value) != TYPE_STRING or not RARITIES.has(str(rarity_value)):
		return _failure(&"PRICE_RARITY_INVALID", {"rarity": str(rarity_value)})
	var rarity := str(rarity_value)
	var count_result := _validated_reroll_count(normalized, reroll_count)
	if not bool(count_result.get("ok", false)):
		return count_result
	var base_result := _reward_base_price(normalized, definition, rarity)
	if not bool(base_result.get("ok", false)):
		return base_result
	var reroll: Dictionary = normalized["reroll_surcharge"]
	var reroll_step := float(reroll["increment"]) / 100.0
	var resolved_price := price(
		int(base_result["base_price"]),
		float(floor_result["floor_multiplier"]),
		float((normalized["rarity_multipliers"] as Dictionary)[rarity]),
		reroll_count,
		reroll_step
	)
	if resolved_price < 0:
		return _failure(&"PRICE_CALCULATION_INVALID", {"kind": "reward"})
	return _success(resolved_price, {
		"kind": "reward",
		"profile_id": str(normalized["id"]),
		"floor_index": floor_index,
		"rarity": rarity,
		"base_price_id": str(base_result["base_price_id"]),
		"base_price": int(base_result["base_price"]),
		"reroll_count": reroll_count,
	})


func sell_price(profile: Dictionary, definition: Dictionary) -> Dictionary:
	var profile_result := _validated_profile(profile)
	if not bool(profile_result.get("ok", false)):
		return profile_result
	var normalized: Dictionary = profile_result["profile"]
	var category_value: Variant = definition.get("category")
	if typeof(category_value) != TYPE_STRING or not ["item", "blessing"].has(str(category_value)):
		return _failure(&"PRICE_SELL_CATEGORY_INVALID", {"category": str(category_value)})
	var category := str(category_value)
	if category == "item":
		var item_mode_value: Variant = definition.get("item_mode")
		if typeof(item_mode_value) != TYPE_STRING:
			return _failure(&"PRICE_SELL_ITEM_MODE_INVALID", {"item_mode": str(item_mode_value)})
		var item_mode := str(item_mode_value)
		if item_mode == "active":
			return _failure(&"PRICE_SELL_ACTIVE_ITEM_FORBIDDEN")
		if item_mode != "passive":
			return _failure(&"PRICE_SELL_ITEM_MODE_INVALID", {"item_mode": item_mode})
	var rarity_value: Variant = definition.get("rarity")
	if typeof(rarity_value) != TYPE_STRING or not RARITIES.has(str(rarity_value)):
		return _failure(&"PRICE_RARITY_INVALID", {"rarity": str(rarity_value)})
	var rarity := str(rarity_value)
	var base_result := _reward_base_price(normalized, definition, rarity)
	if not bool(base_result.get("ok", false)):
		return base_result
	var rarity_multiplier := float((normalized["rarity_multipliers"] as Dictionary)[rarity])
	var sell_ratio := float(normalized["sell_ratio"])
	var calculated := float(base_result["base_price"]) * rarity_multiplier * sell_ratio
	if not is_finite(calculated) or calculated < 0.0 or calculated > float(MAX_SAFE_PRICE):
		return _failure(&"PRICE_CALCULATION_INVALID", {"kind": "sell_reward"})
	return _success(maxi(1, floori(calculated)), {
		"kind": "sell_reward",
		"profile_id": str(normalized["id"]),
		"category": category,
		"rarity": rarity,
		"base_price_id": str(base_result["base_price_id"]),
		"base_price": int(base_result["base_price"]),
		"rarity_multiplier": rarity_multiplier,
		"sell_ratio": sell_ratio,
	})


func service_price(profile: Dictionary, service_id: StringName, floor_index: int) -> Dictionary:
	var profile_result := _validated_profile(profile)
	if not bool(profile_result.get("ok", false)):
		return profile_result
	var normalized: Dictionary = profile_result["profile"]
	var floor_result := _floor_multiplier(normalized, floor_index)
	if not bool(floor_result.get("ok", false)):
		return floor_result
	var service := str(service_id)
	if service == "reroll":
		return _failure(&"PRICE_SERVICE_REQUIRES_COUNT", {"service_id": service})
	if service == "purchase_reward":
		return _failure(&"PRICE_SERVICE_REQUIRES_REWARD", {"service_id": service})
	if NON_GOLD_SERVICES.has(service):
		return _failure(&"PRICE_SERVICE_NOT_GOLD", {"service_id": service})
	if not SERVICE_BASE_PRICE_IDS.has(service):
		return _failure(&"PRICE_SERVICE_INVALID", {"service_id": service})
	var base_price_id := str(SERVICE_BASE_PRICE_IDS[service])
	var base_price := int((normalized["base_prices"] as Dictionary)[base_price_id])
	var resolved_price := price(
		base_price,
		float(floor_result["floor_multiplier"]),
		1.0,
		0,
		0.0
	)
	if resolved_price < 0:
		return _failure(&"PRICE_CALCULATION_INVALID", {"kind": "service", "service_id": service})
	return _success(resolved_price, {
		"kind": "service",
		"profile_id": str(normalized["id"]),
		"service_id": service,
		"floor_index": floor_index,
		"base_price_id": base_price_id,
		"base_price": base_price,
	})


func reroll_price(profile: Dictionary, reroll_count: int) -> Dictionary:
	var profile_result := _validated_profile(profile)
	if not bool(profile_result.get("ok", false)):
		return profile_result
	var normalized: Dictionary = profile_result["profile"]
	var count_result := _validated_reroll_count(normalized, reroll_count)
	if not bool(count_result.get("ok", false)):
		return count_result
	var reroll: Dictionary = normalized["reroll_surcharge"]
	var resolved_price := int(reroll["base_price"]) + reroll_count * int(reroll["increment"])
	if resolved_price < 0 or resolved_price > MAX_SAFE_PRICE:
		return _failure(&"PRICE_CALCULATION_INVALID", {"kind": "reroll"})
	return _success(maxi(1, resolved_price), {
		"kind": "reroll",
		"profile_id": str(normalized["id"]),
		"reroll_count": reroll_count,
		"maximum_rerolls": int(reroll["maximum_rerolls"]),
	})


func _validated_profile(profile: Dictionary) -> Dictionary:
	var parser = EconomyProfileScript.new()
	var parsed: Dictionary = parser.configure(profile)
	if not bool(parsed.get("ok", false)):
		return parsed
	return {"ok": true, "profile": (parsed["definition"] as Dictionary).duplicate(true)}


func _floor_multiplier(profile: Dictionary, floor_index: int) -> Dictionary:
	var floor_multipliers: Array = profile["floor_multipliers"]
	if floor_index < 1 or floor_index > floor_multipliers.size():
		return _failure(&"PRICE_FLOOR_INVALID", {"floor_index": floor_index})
	return {"ok": true, "floor_multiplier": float(floor_multipliers[floor_index - 1])}


func _validated_reroll_count(profile: Dictionary, reroll_count: int) -> Dictionary:
	var maximum := int((profile["reroll_surcharge"] as Dictionary)["maximum_rerolls"])
	if reroll_count < 0 or reroll_count > maximum:
		return _failure(&"PRICE_REROLL_COUNT_INVALID", {
			"reroll_count": reroll_count,
			"maximum_rerolls": maximum,
		})
	return {"ok": true}


func _reward_base_price(profile: Dictionary, definition: Dictionary, rarity: String) -> Dictionary:
	if definition.has("base_price") and definition.has("base_price_id"):
		return _failure(&"PRICE_REWARD_BASE_INVALID", {"reason": "ambiguous_override"})
	if definition.has("base_price"):
		var authored_value: Variant = definition["base_price"]
		if typeof(authored_value) != TYPE_INT or int(authored_value) < 0 or int(authored_value) > 1_000_000:
			return _failure(&"PRICE_REWARD_BASE_INVALID", {"reason": "invalid_base_price"})
		return {"ok": true, "base_price_id": "authored", "base_price": int(authored_value)}
	var base_price_id := str(definition.get("base_price_id", REWARD_BASE_BY_RARITY[rarity]))
	if not REWARD_BASE_PRICE_IDS.has(base_price_id):
		return _failure(&"PRICE_REWARD_BASE_INVALID", {"base_price_id": base_price_id})
	return {
		"ok": true,
		"base_price_id": base_price_id,
		"base_price": int((profile["base_prices"] as Dictionary)[base_price_id]),
	}


func _success(resolved_price: int, context: Dictionary) -> Dictionary:
	var result := {
		"ok": true,
		"code": &"OK",
		"price": resolved_price,
		"context": context.duplicate(true),
	}
	for key: Variant in context:
		result[key] = context[key]
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"context": context.duplicate(true),
	}
