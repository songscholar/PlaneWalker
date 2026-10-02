extends Node

const MerchantInventoryServiceScript := preload(
	"res://scripts/economy/merchant_inventory_service.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const MERCHANTS_PATH := "res://data/content_packs/base/content/merchants.json"
const ECONOMY_PATH := "res://data/content_packs/base/content/economy_profiles.json"
const REWARD_PATHS: Array[String] = [
	"res://data/content_packs/base/content/items.json",
	"res://data/content_packs/base/content/blessings.json",
	"res://data/content_packs/base/content/curses.json",
]
const EXPECTED_MERCHANT_IDS: Array[String] = [
	"merchant_wayfarer",
	"merchant_chronomancer",
	"merchant_forgekeeper",
	"merchant_void_broker",
	"merchant_echo_archivist",
]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"merchant_id",
	"node_id",
	"floor_index",
	"reroll_count",
	"revision",
	"offers",
]
const OFFER_FIELDS: Array[String] = [
	"category", "offer_id", "price", "rarity", "reward_id", "sold",
]


class PriceProbe extends RefCounted:
	var calls: Array[Dictionary] = []
	var rejected_reward_id: String = ""

	func reward_price(
		profile: Dictionary,
		definition: Dictionary,
		floor_index: int,
		reroll_count: int
	) -> Dictionary:
		calls.append({
			"profile_id": str(profile.get("id", "")),
			"reward_id": str(definition.get("id", "")),
			"floor_index": floor_index,
			"reroll_count": reroll_count,
		})
		if str(definition.get("id", "")) == rejected_reward_id:
			return {
				"ok": false,
				"code": &"PRICE_REJECTED",
				"context": {"reward_id": rejected_reward_id},
			}
		return {
			"ok": true,
			"code": &"OK",
			"price": expected_price(definition, floor_index, reroll_count),
			"context": {},
		}

	func expected_price(
		definition: Dictionary,
		floor_index: int,
		reroll_count: int
	) -> int:
		var base_by_rarity := {
			"common": 50,
			"uncommon": 80,
			"rare": 120,
			"legendary": 220,
			"unique": 220,
		}
		return int(base_by_rarity.get(str(definition.get("rarity", "")), 0)) \
			+ floor_index * 10 \
			+ reroll_count * 3


func _ready() -> void:
	var suite = TestSuiteScript.new()
	var merchants := _read_dictionary_array(MERCHANTS_PATH)
	var economy_profiles := _read_dictionary_array(ECONOMY_PATH)
	var rewards := _reward_catalog()
	suite.assert_equal(
		_merchants_ids(merchants),
		EXPECTED_MERCHANT_IDS,
		"authoritative fixture exposes all five merchants in order"
	)
	suite.assert_equal(economy_profiles.size(), 1, "fixture exposes one economy profile")
	suite.assert_true(rewards.size() >= 100, "fixture exposes the Launch reward catalog")
	if merchants.size() == 5 and economy_profiles.size() == 1 and rewards.size() >= 100:
		_test_all_five_merchants(suite, merchants, economy_profiles[0], rewards)
		_test_compatibility_filter(suite, merchants[0], economy_profiles[0], rewards)
		_test_purchase_transaction_and_sold_state(
			suite, merchants[0], economy_profiles[0], rewards
		)
		_test_reroll_transaction_and_reopen(
			suite, merchants[0], economy_profiles[0], rewards
		)
		_test_snapshot_restore_and_atomic_rejection(
			suite, merchants[0], economy_profiles[0], rewards
		)
	suite.finish(get_tree())


func _test_all_five_merchants(
	suite,
	merchants: Array[Dictionary],
	economy_profile: Dictionary,
	rewards: Array[Dictionary]
) -> void:
	for merchant: Dictionary in merchants:
		var price_probe := PriceProbe.new()
		var service = MerchantInventoryServiceScript.new()
		var node_id := "node_%s" % str(merchant["id"])
		var configured: Dictionary = service.configure(
			20261002,
			merchant,
			economy_profile,
			5,
			StringName(node_id),
			rewards,
			_full_compatibility_context(),
			Callable(price_probe, "reward_price")
		)
		suite.assert_true(configured.get("ok", false), "%s configures" % merchant["id"])
		var generated: Dictionary = service.generate()
		suite.assert_true(generated.get("ok", false), "%s inventory generates" % merchant["id"])
		if not bool(generated.get("ok", false)):
			continue
		var snapshot: Dictionary = generated["snapshot"]
		_assert_snapshot_shape(suite, snapshot, "%s snapshot" % merchant["id"])
		var rules := merchant["inventory_rules"] as Dictionary
		var offers := _dictionary_array(snapshot["offers"])
		suite.assert_true(
			offers.size() >= int(rules["offer_count_min"])
			and offers.size() <= int(rules["offer_count_max"]),
			"%s offer count stays inside merchant bounds" % merchant["id"]
		)
		var seen_reward_ids: Dictionary = {}
		var seen_offer_ids: Dictionary = {}
		for offer: Dictionary in offers:
			var reward := _definition_by_id(rewards, str(offer["reward_id"]))
			suite.assert_true(not reward.is_empty(), "%s offer resolves its reward" % merchant["id"])
			if reward.is_empty():
				continue
			suite.assert_true(
				(rules["content_categories"] as Array).has(str(reward["category"])),
				"%s filters reward category" % merchant["id"]
			)
			suite.assert_true(
				_required_tags_match(rules["required_tags"] as Array, reward),
				"%s filters required tags" % merchant["id"]
			)
			suite.assert_true(
				float((rules["rarity_weights"] as Dictionary).get(str(reward["rarity"]), 0.0)) > 0.0,
				"%s filters zero-weight rarity" % merchant["id"]
			)
			suite.assert_true(
				_definition_matches_context(reward, _full_compatibility_context()),
				"%s filters incompatible rewards" % merchant["id"]
			)
			suite.assert_true(not seen_reward_ids.has(offer["reward_id"]), "%s has no duplicate rewards" % merchant["id"])
			suite.assert_true(not seen_offer_ids.has(offer["offer_id"]), "%s has stable unique offer IDs" % merchant["id"])
			seen_reward_ids[offer["reward_id"]] = true
			seen_offer_ids[offer["offer_id"]] = true
			suite.assert_true(
				str(offer["offer_id"]).contains(str(merchant["id"]))
				and str(offer["offer_id"]).contains(node_id)
				and str(offer["offer_id"]).contains("r00"),
				"%s offer identity binds merchant, node, and reroll" % merchant["id"]
			)
			suite.assert_equal(
				offer["price"],
				price_probe.expected_price(reward, 5, 0),
				"%s stores the injected price quote" % merchant["id"]
			)
			suite.assert_equal(offer["sold"], false, "%s new offer starts unsold" % merchant["id"])
		suite.assert_equal(
			generated.get("context", {}).get("seed_channel"),
			"merchant_inventory_v1:%s:%s:0" % [merchant["id"], node_id],
			"%s reports the exact isolated SeedService channel" % merchant["id"]
		)
		var reopen: Dictionary = service.open_inventory()
		suite.assert_true(reopen.get("ok", false), "%s inventory reopens" % merchant["id"])
		suite.assert_equal(reopen.get("snapshot"), snapshot, "%s reopen uses stored state" % merchant["id"])
		var twin = MerchantInventoryServiceScript.new()
		suite.assert_true(bool(twin.configure(
			20261002, merchant, economy_profile, 5, StringName(node_id), rewards,
			_full_compatibility_context(), Callable(PriceProbe.new(), "reward_price")
		).get("ok", false)), "%s deterministic twin configures" % merchant["id"])
		suite.assert_equal(
			twin.generate().get("snapshot"),
			snapshot,
			"%s repeated generation is byte-identical" % merchant["id"]
		)


func _test_compatibility_filter(
	suite,
	merchant: Dictionary,
	economy_profile: Dictionary,
	rewards: Array[Dictionary]
) -> void:
	var context := {
		"archetype_ids": ["freeze_burst"],
		"weapon_ids": ["sword"],
	}
	var service = MerchantInventoryServiceScript.new()
	var price_probe := PriceProbe.new()
	var configured: Dictionary = service.configure(
		9911, merchant, economy_profile, 3, &"compatibility_node", rewards, context,
		Callable(price_probe, "reward_price")
	)
	suite.assert_true(configured.get("ok", false), "compatibility fixture configures")
	var generated: Dictionary = service.generate()
	suite.assert_true(generated.get("ok", false), "compatibility fixture generates")
	for offer: Dictionary in _dictionary_array(generated.get("snapshot", {}).get("offers", [])):
		var reward := _definition_by_id(rewards, str(offer["reward_id"]))
		suite.assert_true(
			_definition_matches_context(reward, context),
			"generated offer satisfies every declared compatibility dimension"
		)


func _test_purchase_transaction_and_sold_state(
	suite,
	merchant: Dictionary,
	economy_profile: Dictionary,
	rewards: Array[Dictionary]
) -> void:
	var service = _generated_service(merchant, economy_profile, rewards, 3301, &"purchase_node")
	var before: Dictionary = service.snapshot()
	var offer_id := str((before["offers"] as Array)[0]["offer_id"])
	var prepared: Dictionary = service.prepare_purchase(
		"purchase-1", before, offer_id, int(before["revision"])
	)
	suite.assert_true(prepared.get("ok", false), "purchase prepares")
	suite.assert_equal(prepared.get("transaction_id"), "purchase-1", "purchase exposes transaction ID")
	suite.assert_equal(service.snapshot(), before, "purchase prepare is observation-only")
	var ticket := prepared.get("ticket", {}) as Dictionary
	var ticket_offer := ticket.get("offer", {}) as Dictionary
	suite.assert_equal(prepared.get("price"), ticket_offer.get("price"), "purchase exposes quoted price")
	suite.assert_equal(ticket.get("transaction_id"), "purchase-1", "purchase ticket binds transaction ID")
	suite.assert_equal(
		(ticket_offer.get("definition", {}) as Dictionary).get("id"),
		ticket_offer.get("reward_id"),
		"purchase ticket carries the authoritative reward definition"
	)
	var after := ticket.get("after_snapshot", {}) as Dictionary
	suite.assert_equal(after.get("revision"), int(before["revision"]) + 1, "purchase preview advances revision")
	suite.assert_true(_offer_sold(after, offer_id), "purchase preview marks exactly one offer sold")
	var committed: Dictionary = service.commit_purchase(ticket)
	suite.assert_true(committed.get("ok", false), "purchase commits")
	suite.assert_equal(
		committed.get("receipt", {}).get("transaction_id"),
		"purchase-1",
		"purchase receipt preserves transaction ID"
	)
	suite.assert_equal(service.snapshot(), after, "purchase commit installs preview")
	var rolled_back: Dictionary = service.rollback_purchase(committed.get("receipt", {}))
	suite.assert_true(rolled_back.get("ok", false), "committed purchase rolls back")
	suite.assert_equal(service.snapshot(), before, "purchase rollback restores exact before snapshot")
	var replayed: Dictionary = service.prepare_purchase(
		"purchase-2", service.snapshot(), offer_id, int(service.snapshot()["revision"])
	)
	var recommitted: Dictionary = service.commit_purchase(replayed.get("ticket", {}))
	suite.assert_true(recommitted.get("ok", false), "purchase recommits after compensation")
	suite.assert_true(_offer_sold(service.open_inventory().get("snapshot", {}), offer_id), "sold state persists on reopen")
	var repeated: Dictionary = service.prepare_purchase(
		"purchase-3", service.snapshot(), offer_id, int(service.snapshot()["revision"])
	)
	suite.assert_true(not repeated.get("ok", false), "already-sold offer rejects atomically")


func _test_reroll_transaction_and_reopen(
	suite,
	merchant: Dictionary,
	economy_profile: Dictionary,
	rewards: Array[Dictionary]
) -> void:
	var service = _generated_service(merchant, economy_profile, rewards, 4401, &"reroll_node")
	var before: Dictionary = service.snapshot()
	var prepared: Dictionary = service.prepare_reroll(
		"reroll-1", before, int(before["revision"])
	)
	suite.assert_true(prepared.get("ok", false), "reroll prepares")
	var expected_reroll_price := int((economy_profile["reroll_surcharge"] as Dictionary)["base_price"])
	suite.assert_equal(prepared.get("transaction_id"), "reroll-1", "reroll exposes transaction ID")
	suite.assert_equal(prepared.get("price"), expected_reroll_price, "reroll exposes current price")
	suite.assert_equal(service.snapshot(), before, "reroll prepare is observation-only")
	var ticket := prepared.get("ticket", {}) as Dictionary
	suite.assert_equal(ticket.get("transaction_id"), "reroll-1", "reroll ticket binds transaction ID")
	suite.assert_equal(ticket.get("price"), expected_reroll_price, "reroll ticket binds current price")
	suite.assert_equal(
		prepared.get("context", {}).get("transaction_id"),
		"reroll-1",
		"reroll context exposes transaction ID"
	)
	suite.assert_equal(
		prepared.get("context", {}).get("price"),
		expected_reroll_price,
		"reroll context exposes authoritative price"
	)
	var after := ticket.get("after_snapshot", {}) as Dictionary
	suite.assert_equal(after.get("reroll_count"), 1, "reroll preview advances reroll count")
	suite.assert_equal(after.get("revision"), int(before["revision"]) + 1, "reroll preview advances revision")
	suite.assert_true(_all_offers_unsold(after), "reroll creates an unsold inventory")
	suite.assert_equal(
		prepared.get("context", {}).get("seed_channel"),
		"merchant_inventory_v1:%s:reroll_node:1" % merchant["id"],
		"reroll uses the exact isolated channel"
	)
	var committed: Dictionary = service.commit_reroll(ticket)
	suite.assert_true(committed.get("ok", false), "reroll commits")
	suite.assert_equal(
		committed.get("receipt", {}).get("price"),
		expected_reroll_price,
		"reroll receipt preserves charged price"
	)
	suite.assert_equal(service.open_inventory().get("snapshot"), after, "reroll reopen uses committed state")
	var rolled_back: Dictionary = service.rollback_reroll(committed.get("receipt", {}))
	suite.assert_true(rolled_back.get("ok", false), "committed reroll rolls back")
	suite.assert_equal(service.snapshot(), before, "reroll rollback restores exact before snapshot")
	var prepared_again: Dictionary = service.prepare_reroll(
		"reroll-2", service.snapshot(), int(service.snapshot()["revision"])
	)
	suite.assert_equal(
		prepared_again.get("ticket", {}).get("after_snapshot"),
		after,
		"same seed, node, and reroll count regenerate byte-identical inventory"
	)
	suite.assert_true(
		service.commit_reroll(prepared_again.get("ticket", {})).get("ok", false),
		"deterministic reroll recommits"
	)


func _test_snapshot_restore_and_atomic_rejection(
	suite,
	merchant: Dictionary,
	economy_profile: Dictionary,
	rewards: Array[Dictionary]
) -> void:
	var service = _generated_service(merchant, economy_profile, rewards, 5501, &"restore_node")
	var canonical: Dictionary = service.snapshot()
	var restored = MerchantInventoryServiceScript.new()
	var price_probe := PriceProbe.new()
	suite.assert_true(bool(restored.configure(
		5501, merchant, economy_profile, 5, &"restore_node", rewards,
		_full_compatibility_context(), Callable(price_probe, "reward_price")
	).get("ok", false)), "restore service configures")
	suite.assert_true(restored.restore_snapshot(canonical), "canonical inventory snapshot restores")
	suite.assert_equal(restored.snapshot(), canonical, "restored inventory is byte-identical")
	for mutation: Dictionary in [
		{"label": "forged price", "apply": func(value: Dictionary): value["offers"][0]["price"] += 1},
		{"label": "duplicate reward", "apply": func(value: Dictionary): value["offers"][1]["reward_id"] = value["offers"][0]["reward_id"]},
		{"label": "stale revision", "apply": func(value: Dictionary): value["revision"] = 0},
	]:
		var corrupted := canonical.duplicate(true)
		(mutation["apply"] as Callable).call(corrupted)
		var before: Dictionary = restored.snapshot()
		suite.assert_true(
			not restored.restore_snapshot(corrupted),
			"%s snapshot rejects" % mutation["label"]
		)
		suite.assert_equal(restored.snapshot(), before, "%s rejection is atomic" % mutation["label"])

	var invalid_merchant := merchant.duplicate(true)
	invalid_merchant["id"] = "merchant_unknown"
	var before_invalid_config: Dictionary = service.snapshot()
	var invalid_config: Dictionary = service.configure(
		5501, invalid_merchant, economy_profile, 5, &"restore_node", rewards,
		_full_compatibility_context(), Callable(PriceProbe.new(), "reward_price")
	)
	suite.assert_true(not invalid_config.get("ok", false), "invalid reconfigure rejects")
	suite.assert_equal(service.snapshot(), before_invalid_config, "invalid reconfigure preserves inventory")

	var unknown_offer: Dictionary = service.prepare_purchase(
		"bad-purchase", service.snapshot(), "missing", int(service.snapshot()["revision"])
	)
	suite.assert_true(not unknown_offer.get("ok", false), "unknown purchase offer rejects")
	suite.assert_equal(service.snapshot(), before_invalid_config, "unknown purchase preserves inventory")
	var stale_reroll: Dictionary = service.prepare_reroll(
		"bad-reroll", service.snapshot(), int(service.snapshot()["revision"]) + 1
	)
	suite.assert_true(not stale_reroll.get("ok", false), "stale reroll rejects")
	suite.assert_equal(service.snapshot(), before_invalid_config, "stale reroll preserves inventory")
	var incompatible_transaction_id: Dictionary = service.prepare_reroll(
		"Bad-Reroll", service.snapshot(), int(service.snapshot()["revision"])
	)
	suite.assert_true(
		not incompatible_transaction_id.get("ok", false),
		"transaction ID outside RunEconomyState format rejects"
	)
	suite.assert_equal(
		service.snapshot(),
		before_invalid_config,
		"invalid transaction ID preserves inventory"
	)

	var valid_prepare: Dictionary = service.prepare_reroll(
		"tampered-reroll", service.snapshot(), int(service.snapshot()["revision"])
	)
	var tampered_ticket := (valid_prepare.get("ticket", {}) as Dictionary).duplicate(true)
	tampered_ticket["transaction_id"] = "forged"
	suite.assert_true(not service.commit_reroll(tampered_ticket).get("ok", false), "tampered ticket rejects")
	suite.assert_equal(service.snapshot(), before_invalid_config, "tampered commit preserves inventory")

	var purchase_prepare: Dictionary = service.prepare_purchase(
		"forged_transition", service.snapshot(),
		str((service.snapshot()["offers"] as Array)[0]["offer_id"]),
		int(service.snapshot()["revision"])
	)
	var forged_transition := (purchase_prepare.get("ticket", {}) as Dictionary).duplicate(true)
	var forged_after := (forged_transition["after_snapshot"] as Dictionary).duplicate(true)
	if (forged_after["offers"] as Array).size() > 1:
		((forged_after["offers"] as Array)[1] as Dictionary)["sold"] = true
	forged_transition["after_snapshot"] = forged_after
	forged_transition["fingerprint"] = _fingerprint_without(forged_transition, "fingerprint")
	suite.assert_true(
		not service.commit_purchase(forged_transition).get("ok", false),
		"rehashed ticket cannot sell more than the requested offer"
	)
	suite.assert_equal(service.snapshot(), before_invalid_config, "forged transition preserves inventory")


func _generated_service(
	merchant: Dictionary,
	economy_profile: Dictionary,
	rewards: Array[Dictionary],
	run_seed: int,
	node_id: StringName
):
	var service = MerchantInventoryServiceScript.new()
	var price_probe := PriceProbe.new()
	var configured: Dictionary = service.configure(
		run_seed, merchant, economy_profile, 5, node_id, rewards,
		_full_compatibility_context(), Callable(price_probe, "reward_price")
	)
	if not bool(configured.get("ok", false)):
		return service
	service.generate()
	return service


func _assert_snapshot_shape(suite, snapshot: Dictionary, label: String) -> void:
	for field: String in SNAPSHOT_FIELDS:
		suite.assert_true(snapshot.has(field), "%s has %s" % [label, field])
	for offer: Dictionary in _dictionary_array(snapshot.get("offers", [])):
		suite.assert_equal(_sorted_keys(offer), OFFER_FIELDS, "%s offer has exact fields" % label)


func _offer_sold(snapshot: Dictionary, offer_id: String) -> bool:
	for offer: Dictionary in _dictionary_array(snapshot.get("offers", [])):
		if str(offer.get("offer_id", "")) == offer_id:
			return bool(offer.get("sold", false))
	return false


func _all_offers_unsold(snapshot: Dictionary) -> bool:
	var offers := _dictionary_array(snapshot.get("offers", []))
	if offers.is_empty():
		return false
	for offer: Dictionary in offers:
		if bool(offer.get("sold", true)):
			return false
	return true


func _definition_by_id(definitions: Array[Dictionary], content_id: String) -> Dictionary:
	for definition: Dictionary in definitions:
		if str(definition.get("id", "")) == content_id:
			return definition
	return {}


func _required_tags_match(required_tags: Array, definition: Dictionary) -> bool:
	var tags: Array = definition.get("tags", [])
	for required_value: Variant in required_tags:
		var required := str(required_value)
		if required == "launch":
			if not (definition.get("availability", []) as Array).has("LAUNCH"):
				return false
			continue
		var matched := false
		for tag_value: Variant in tags:
			var tag := str(tag_value)
			if tag == required or tag.split("_").has(required):
				matched = true
				break
		if not matched:
			return false
	return true


func _definition_matches_context(definition: Dictionary, context: Dictionary) -> bool:
	var compatibility := definition.get("compatibility", {}) as Dictionary
	for key_value: Variant in compatibility.keys():
		var key := str(key_value)
		var allowed := compatibility[key] as Array
		if allowed.is_empty():
			continue
		var selected: Array = context.get(key, [])
		var matched := false
		for selected_value: Variant in selected:
			if allowed.has(str(selected_value)):
				matched = true
				break
		if not matched:
			return false
	return true


func _full_compatibility_context() -> Dictionary:
	return {
		"archetype_ids": [
			"freeze_burst", "rewind_echo", "rift_trap", "accelerated_combo",
			"low_hp_void", "perfect_guard", "piercing_barrage", "echo_legion",
		],
		"weapon_ids": ["sword", "bow", "gun", "staff", "gauntlets"],
	}


func _reward_catalog() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for path: String in REWARD_PATHS:
		values.append_array(_read_dictionary_array(path))
	return values


func _read_dictionary_array(path: String) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return _dictionary_array(parsed)


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	if not value is Array:
		return values
	for entry: Variant in value as Array:
		if entry is Dictionary:
			values.append((entry as Dictionary).duplicate(true))
	return values


func _merchants_ids(merchants: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for merchant: Dictionary in merchants:
		ids.append(str(merchant.get("id", "")))
	return ids


func _sorted_keys(value: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key_value: Variant in value.keys():
		keys.append(str(key_value))
	keys.sort()
	return keys


func _fingerprint_without(value: Dictionary, field: String) -> String:
	var payload := value.duplicate(true)
	payload.erase(field)
	return JSON.stringify(payload).sha256_text()
