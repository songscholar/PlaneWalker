extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ShopPriceServiceScript := preload("res://scripts/economy/shop_price_service.gd")

const PROFILE_PATH := "res://data/content_packs/base/content/economy_profiles.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_profile_validation(suite)
	_test_all_floor_multipliers(suite)
	_test_all_rarity_multipliers(suite)
	_test_reward_base_price_mapping(suite)
	_test_reward_reroll_surcharge(suite)
	_test_service_prices(suite)
	_test_reroll_prices(suite)
	_test_sell_prices(suite)
	_test_integer_ceiling_and_bounds(suite)
	_test_invalid_arguments_fail_closed(suite)
	_test_determinism_and_profile_isolation(suite)
	suite.finish(get_tree())


func _test_profile_validation(suite) -> void:
	var service = ShopPriceServiceScript.new()
	var invalid_profile := _profile()
	invalid_profile["id"] = "forged_profile"
	var rejected: Dictionary = service.reward_price(invalid_profile, {"rarity": "common"}, 1, 0)
	suite.assert_equal(rejected.get("code"), &"ECONOMY_PROFILE_INVALID", "unknown profile id is rejected")
	suite.assert_equal(rejected.get("price"), null, "rejected profile never leaks a price")
	var rejected_sell: Dictionary = service.sell_price(
		invalid_profile,
		{"category": "blessing", "rarity": "common"}
	)
	suite.assert_equal(rejected_sell.get("code"), &"ECONOMY_PROFILE_INVALID", "sell quote rejects an invalid profile")
	suite.assert_equal(rejected_sell.get("price"), null, "rejected sell profile never leaks a price")


func _test_all_floor_multipliers(suite) -> void:
	var service = ShopPriceServiceScript.new()
	var profile := _profile()
	var expected: Array[int] = [50, 58, 65, 73, 80]
	for floor_index: int in range(1, 6):
		var quote: Dictionary = service.reward_price(profile, {"rarity": "common"}, floor_index, 0)
		suite.assert_true(bool(quote.get("ok", false)), "floor %d reward quote succeeds" % floor_index)
		suite.assert_equal(quote.get("price"), expected[floor_index - 1], "floor %d multiplier rounds upward" % floor_index)


func _test_all_rarity_multipliers(suite) -> void:
	var service = ShopPriceServiceScript.new()
	var profile := _profile()
	var expected := {
		"common": 50,
		"uncommon": 63,
		"rare": 80,
		"legendary": 120,
		"unique": 150,
	}
	for rarity: String in expected:
		var definition := {"rarity": rarity, "base_price_id": "common_reward"}
		var quote: Dictionary = service.reward_price(profile, definition, 1, 0)
		suite.assert_true(bool(quote.get("ok", false)), "%s rarity quote succeeds" % rarity)
		suite.assert_equal(quote.get("price"), expected[rarity], "%s rarity multiplier is applied" % rarity)


func _test_reward_base_price_mapping(suite) -> void:
	var service = ShopPriceServiceScript.new()
	var profile := _profile()
	var expected := {
		"common": 50,
		"uncommon": 100,
		"rare": 192,
		"legendary": 528,
		"unique": 660,
	}
	for rarity: String in expected:
		var quote: Dictionary = service.reward_price(profile, {"rarity": rarity}, 1, 0)
		suite.assert_equal(quote.get("price"), expected[rarity], "%s resolves its authoritative reward base" % rarity)
	var explicit_key: Dictionary = service.reward_price(
		profile, {"rarity": "rare", "base_price_id": "uncommon_reward"}, 2, 0
	)
	suite.assert_equal(explicit_key.get("price"), 148, "explicit reward base key supports authored offer overrides")
	var explicit_value: Dictionary = service.reward_price(
		profile, {"rarity": "uncommon", "base_price": 33}, 1, 0
	)
	suite.assert_equal(explicit_value.get("price"), 42, "explicit authored base price rounds upward")


func _test_reward_reroll_surcharge(suite) -> void:
	var service = ShopPriceServiceScript.new()
	var profile := _profile()
	var expected: Array[int] = [50, 60, 70, 80, 90]
	for reroll_count: int in range(5):
		var quote: Dictionary = service.reward_price(profile, {"rarity": "common"}, 1, reroll_count)
		suite.assert_equal(quote.get("price"), expected[reroll_count], "reward reroll %d applies twenty-percent step" % reroll_count)


func _test_service_prices(suite) -> void:
	var service = ShopPriceServiceScript.new()
	var profile := _profile()
	var floor_one := {
		"heal": 40,
		"cleanse_curse": 100,
		"weapon_upgrade": 120,
		"route_reveal": 60,
	}
	for service_id: String in floor_one:
		var quote: Dictionary = service.service_price(profile, StringName(service_id), 1)
		suite.assert_true(bool(quote.get("ok", false)), "%s service quote succeeds" % service_id)
		suite.assert_equal(quote.get("price"), floor_one[service_id], "%s uses profile base price" % service_id)
	suite.assert_equal(service.service_price(profile, &"heal", 5).get("price"), 64, "service price applies floor five multiplier")
	suite.assert_equal(service.service_price(profile, &"reroll", 1).get("code"), &"PRICE_SERVICE_REQUIRES_COUNT", "reroll requires explicit count")
	suite.assert_equal(service.service_price(profile, &"purchase_reward", 1).get("code"), &"PRICE_SERVICE_REQUIRES_REWARD", "reward purchase requires definition")


func _test_reroll_prices(suite) -> void:
	var service = ShopPriceServiceScript.new()
	var profile := _profile()
	var expected: Array[int] = [40, 60, 80, 100, 120]
	for reroll_count: int in range(5):
		var quote: Dictionary = service.reroll_price(profile, reroll_count)
		suite.assert_true(bool(quote.get("ok", false)), "reroll %d quote succeeds" % reroll_count)
		suite.assert_equal(quote.get("price"), expected[reroll_count], "reroll %d grows monotonically" % reroll_count)


func _test_sell_prices(suite) -> void:
	var service = ShopPriceServiceScript.new()
	var profile := _profile()
	var expected := {
		"common": 20,
		"uncommon": 40,
		"rare": 76,
		"legendary": 211,
		"unique": 264,
	}
	for rarity: String in expected:
		var quote: Dictionary = service.sell_price(
			profile,
			{"category": "blessing", "rarity": rarity}
		)
		suite.assert_true(bool(quote.get("ok", false)), "%s blessing sell quote succeeds" % rarity)
		suite.assert_equal(quote.get("price"), expected[rarity], "%s sell quote floors intrinsic value" % rarity)
		suite.assert_equal(quote.get("kind"), "sell_reward", "sell quote identifies its transaction kind")
		suite.assert_true(not quote.has("floor_index"), "sell quote does not expose a floor dependency")
		suite.assert_true(not quote.has("reroll_count"), "sell quote does not expose a reroll dependency")
	var explicit_key: Dictionary = service.sell_price(
		profile,
		{"category": "item", "item_mode": "passive", "rarity": "rare", "base_price_id": "uncommon_reward"}
	)
	suite.assert_equal(explicit_key.get("price"), 51, "sell quote accepts an authoritative reward base key")
	var explicit_value: Dictionary = service.sell_price(
		profile,
		{"category": "item", "item_mode": "passive", "rarity": "uncommon", "base_price": 33}
	)
	suite.assert_equal(explicit_value.get("price"), 16, "sell quote floors an authored fractional value")
	suite.assert_equal(
		service.sell_price(
			profile,
			{"category": "item", "item_mode": "passive", "rarity": "common", "base_price": 0}
		).get("price"),
		1,
		"sell quote retains the minimum price of one"
	)
	var floor_independent := profile.duplicate(true)
	floor_independent["floor_multipliers"] = [9.0, 8.0, 7.0, 6.0, 5.0]
	suite.assert_equal(
		service.sell_price(floor_independent, {"category": "blessing", "rarity": "common"}).get("price"),
		20,
		"sell quote ignores floor multipliers to prevent cross-floor arbitrage"
	)


func _test_integer_ceiling_and_bounds(suite) -> void:
	suite.assert_equal(ShopPriceServiceScript.price(1, 1.15, 1.25, 0, 0.0), 2, "fractional prices round upward")
	suite.assert_equal(ShopPriceServiceScript.price(0, 1.0, 1.0, 0, 0.0), 1, "zero authored price retains minimum one")
	suite.assert_equal(ShopPriceServiceScript.price(50, 1.0, 1.0, 4, 0.2), 90, "maximum reroll surcharge remains exact")
	suite.assert_equal(ShopPriceServiceScript.price(-1, 1.0, 1.0, 0, 0.0), -1, "negative base fails closed")
	suite.assert_equal(ShopPriceServiceScript.price(1, 0.0, 1.0, 0, 0.0), -1, "non-positive floor multiplier fails closed")
	suite.assert_equal(ShopPriceServiceScript.price(1, 1.0, 0.0, 0, 0.0), -1, "non-positive rarity multiplier fails closed")
	suite.assert_equal(ShopPriceServiceScript.price(1, 1.0, 1.0, -1, 0.0), -1, "negative reroll count fails closed")
	suite.assert_equal(ShopPriceServiceScript.price(1, 1.0, 1.0, 0, -0.1), -1, "negative reroll step fails closed")


func _test_invalid_arguments_fail_closed(suite) -> void:
	var service = ShopPriceServiceScript.new()
	var profile := _profile()
	for floor_index: int in [0, 6]:
		suite.assert_equal(service.reward_price(profile, {"rarity": "common"}, floor_index, 0).get("code"), &"PRICE_FLOOR_INVALID", "floor %d fails closed" % floor_index)
		suite.assert_equal(service.service_price(profile, &"heal", floor_index).get("code"), &"PRICE_FLOOR_INVALID", "service floor %d fails closed" % floor_index)
	for rarity: String in ["", "epic", "COMMON"]:
		suite.assert_equal(service.reward_price(profile, {"rarity": rarity}, 1, 0).get("code"), &"PRICE_RARITY_INVALID", "rarity %s fails closed" % rarity)
	for count: int in [-1, 5]:
		suite.assert_equal(service.reward_price(profile, {"rarity": "common"}, 1, count).get("code"), &"PRICE_REROLL_COUNT_INVALID", "reward count %d fails closed" % count)
		suite.assert_equal(service.reroll_price(profile, count).get("code"), &"PRICE_REROLL_COUNT_INVALID", "reroll count %d fails closed" % count)
	suite.assert_equal(service.reward_price(profile, {"rarity": "common", "base_price_id": "healing"}, 1, 0).get("code"), &"PRICE_REWARD_BASE_INVALID", "service base key cannot masquerade as reward")
	suite.assert_equal(service.reward_price(profile, {"rarity": "common", "base_price": -1}, 1, 0).get("code"), &"PRICE_REWARD_BASE_INVALID", "negative authored base price fails closed")
	suite.assert_equal(service.service_price(profile, &"health_trade", 1).get("code"), &"PRICE_SERVICE_NOT_GOLD", "health trade is explicitly non-gold")
	suite.assert_equal(service.service_price(profile, &"sell_reward", 1).get("code"), &"PRICE_SERVICE_NOT_GOLD", "selling is explicitly a credit")
	suite.assert_equal(service.service_price(profile, &"unknown", 1).get("code"), &"PRICE_SERVICE_INVALID", "unknown service fails closed")
	for category: Variant in [null, 7, "", "curse", "talent", "weapon"]:
		suite.assert_equal(
			service.sell_price(profile, {"category": category, "rarity": "common"}).get("code"),
			&"PRICE_SELL_CATEGORY_INVALID",
			"sell category %s fails closed" % str(category)
		)
	suite.assert_equal(
		service.sell_price(profile, {"category": "item", "item_mode": "active", "rarity": "rare"}).get("code"),
		&"PRICE_SELL_ACTIVE_ITEM_FORBIDDEN",
		"active items cannot be sold"
	)
	for item_mode: Variant in [null, 7, "", "unknown"]:
		suite.assert_equal(
			service.sell_price(profile, {"category": "item", "item_mode": item_mode, "rarity": "common"}).get("code"),
			&"PRICE_SELL_ITEM_MODE_INVALID",
			"item mode %s fails closed" % str(item_mode)
		)
	for rarity: Variant in [null, 7, "", "epic", "COMMON"]:
		suite.assert_equal(
			service.sell_price(profile, {"category": "blessing", "rarity": rarity}).get("code"),
			&"PRICE_RARITY_INVALID",
			"sell rarity %s fails closed" % str(rarity)
		)
	suite.assert_equal(
		service.sell_price(profile, {"category": "blessing", "rarity": "common", "base_price": -1}).get("code"),
		&"PRICE_REWARD_BASE_INVALID",
		"sell quote rejects a negative authored base"
	)


func _test_determinism_and_profile_isolation(suite) -> void:
	var service = ShopPriceServiceScript.new()
	var source := _profile()
	var pristine := source.duplicate(true)
	var definition := {"rarity": "rare", "base_price_id": "uncommon_reward"}
	var first: Dictionary = service.reward_price(source, definition, 4, 2)
	var second: Dictionary = service.reward_price(source, definition, 4, 2)
	suite.assert_equal(first, second, "identical inputs return identical quote facts")
	suite.assert_equal(source, pristine, "pricing never mutates the caller profile")
	suite.assert_equal(definition, {"rarity": "rare", "base_price_id": "uncommon_reward"}, "pricing never mutates the caller definition")
	var sell_definition := {"category": "item", "item_mode": "passive", "rarity": "rare"}
	var pristine_sell_definition := sell_definition.duplicate(true)
	var first_sell: Dictionary = service.sell_price(source, sell_definition)
	var second_sell: Dictionary = service.sell_price(source, sell_definition)
	suite.assert_equal(first_sell, second_sell, "identical sell inputs return identical quote facts")
	suite.assert_equal(sell_definition, pristine_sell_definition, "sell pricing never mutates the caller definition")


func _profile() -> Dictionary:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		push_error("Unable to open %s" % PROFILE_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array or (parsed as Array).size() != 1:
		push_error("Expected exactly one Launch economy profile")
		return {}
	return ((parsed as Array)[0] as Dictionary).duplicate(true)
