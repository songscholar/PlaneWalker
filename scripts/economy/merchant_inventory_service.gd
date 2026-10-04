class_name MerchantInventoryService
extends RefCounted

const SeedServiceScript := preload("res://scripts/core/seed_service.gd")
const MerchantDefinitionScript := preload("res://scripts/dungeon/merchant_definition.gd")
const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")
const ShopPriceServiceScript := preload("res://scripts/economy/shop_price_service.gd")
const RewardCompatibilityScript := preload("res://scripts/rewards/reward_compatibility.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
const TRANSACTION_SCHEMA_VERSION := 1
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
	"offer_id", "reward_id", "category", "rarity", "price", "sold",
]
const TICKET_FIELDS: Array[String] = [
	"schema_version",
	"owner_instance_id",
	"kind",
	"transaction_id",
	"price",
	"offer",
	"before_snapshot",
	"after_snapshot",
	"fingerprint",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_version",
	"owner_instance_id",
	"kind",
	"transaction_id",
	"price",
	"offer",
	"before_snapshot",
	"after_snapshot",
	"ticket_fingerprint",
	"fingerprint",
]
const CONTENT_CATEGORIES: Array[String] = ["item", "blessing", "curse"]
const RARITIES: Array[String] = ["common", "uncommon", "rare", "legendary", "unique"]
const TRANSACTION_KINDS: Array[String] = ["purchase", "reroll"]

var _configured: bool = false
var _run_seed: int = 0
var _merchant: Dictionary = {}
var _economy_profile: Dictionary = {}
var _floor_index: int = 0
var _node_id: String = ""
var _reward_definitions: Array[Dictionary] = []
var _definitions_by_id: Dictionary = {}
var _compatibility_context: Dictionary = {}
var _price_quote: Callable
var _price_quote_owner: Variant = null
var _snapshot: Dictionary = {}


func configure(
	run_seed: int,
	merchant: Dictionary,
	economy_profile: Dictionary,
	floor_index: int,
	node_id: StringName,
	reward_definitions: Array,
	compatibility_context: Dictionary,
	price_quote: Callable
) -> Dictionary:
	var merchant_parser = MerchantDefinitionScript.new()
	var merchant_result: Dictionary = merchant_parser.configure(merchant)
	if not bool(merchant_result.get("ok", false)):
		return _failure(&"MERCHANT_INVENTORY_MERCHANT_INVALID", merchant_result.get("context", {}))
	var economy_parser = EconomyProfileScript.new()
	var economy_result: Dictionary = economy_parser.configure(economy_profile)
	if not bool(economy_result.get("ok", false)):
		return _failure(&"MERCHANT_INVENTORY_ECONOMY_INVALID", economy_result.get("context", {}))
	var normalized_merchant := (merchant_result["definition"] as Dictionary).duplicate(true)
	var normalized_economy := (economy_result["definition"] as Dictionary).duplicate(true)
	var normalized_node_id := str(node_id).strip_edges()
	if (
		floor_index < int(normalized_merchant["floor_min"])
		or floor_index > int(normalized_merchant["floor_max"])
		or floor_index < 1
		or floor_index > 5
	):
		return _failure(&"MERCHANT_INVENTORY_FLOOR_INVALID", {"floor_index": floor_index})
	if not _valid_id(normalized_node_id):
		return _failure(&"MERCHANT_INVENTORY_NODE_INVALID", {"node_id": normalized_node_id})
	if not price_quote.is_valid():
		return _failure(&"MERCHANT_INVENTORY_PRICE_AUTHORITY_INVALID")
	var context_result := _normalized_compatibility_context(compatibility_context)
	if not bool(context_result.get("ok", false)):
		return context_result
	var definitions_result := _normalized_reward_definitions(reward_definitions)
	if not bool(definitions_result.get("ok", false)):
		return definitions_result
	var normalized_definitions := _dictionary_array(definitions_result["definitions"])
	var normalized_context := (context_result["context"] as Dictionary).duplicate(true)
	var eligible := _eligible_definitions_for(
		normalized_merchant,
		normalized_definitions,
		normalized_context
	)
	var minimum := int((normalized_merchant["inventory_rules"] as Dictionary)["offer_count_min"])
	if eligible.size() < minimum:
		return _failure(&"MERCHANT_INVENTORY_CONTENT_UNAVAILABLE", {
			"merchant_id": str(normalized_merchant["id"]),
			"eligible_count": eligible.size(),
			"required_count": minimum,
		})

	var definitions_by_id: Dictionary = {}
	for definition: Dictionary in normalized_definitions:
		definitions_by_id[str(definition["id"])] = definition.duplicate(true)
	_run_seed = run_seed
	_merchant = normalized_merchant
	_economy_profile = normalized_economy
	_floor_index = floor_index
	_node_id = normalized_node_id
	_reward_definitions = normalized_definitions
	_definitions_by_id = definitions_by_id
	_compatibility_context = normalized_context
	_price_quote = price_quote
	_price_quote_owner = price_quote.get_object()
	_snapshot.clear()
	_configured = true
	return _success({
		"merchant_id": str(_merchant["id"]),
		"node_id": _node_id,
		"floor_index": _floor_index,
	})


func generate() -> Dictionary:
	if not _configured:
		return _failure(&"MERCHANT_INVENTORY_NOT_CONFIGURED")
	if not _snapshot.is_empty():
		return _success({
			"snapshot": snapshot(),
			"context": {"seed_channel": _seed_channel(int(_snapshot["reroll_count"]))},
		})
	var generated := _generated_snapshot(0, 1)
	if not bool(generated.get("ok", false)):
		return generated
	_snapshot = (generated["snapshot"] as Dictionary).duplicate(true)
	return _success({
		"snapshot": snapshot(),
		"context": {"seed_channel": str(generated["seed_channel"])},
	})


func open_inventory() -> Dictionary:
	if not _configured:
		return _failure(&"MERCHANT_INVENTORY_NOT_CONFIGURED")
	if _snapshot.is_empty():
		return _failure(&"MERCHANT_INVENTORY_NOT_GENERATED")
	return _success({
		"snapshot": snapshot(),
		"context": {"seed_channel": _seed_channel(int(_snapshot["reroll_count"]))},
	})


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func can_restore_snapshot(value: Dictionary) -> bool:
	if not _configured or not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != SNAPSHOT_SCHEMA_VERSION
		or typeof(value["merchant_id"]) != TYPE_STRING
		or str(value["merchant_id"]) != str(_merchant["id"])
		or typeof(value["node_id"]) != TYPE_STRING
		or str(value["node_id"]) != _node_id
		or typeof(value["floor_index"]) != TYPE_INT
		or int(value["floor_index"]) != _floor_index
		or typeof(value["reroll_count"]) != TYPE_INT
		or int(value["reroll_count"]) < 0
		or int(value["reroll_count"]) > _maximum_rerolls()
		or typeof(value["revision"]) != TYPE_INT
		or int(value["revision"]) < int(value["reroll_count"]) + 1
		or not value["offers"] is Array
	):
		return false
	var offers := _dictionary_array(value["offers"])
	if offers.size() != (value["offers"] as Array).size():
		return false
	var seen_offer_ids: Dictionary = {}
	var seen_reward_ids: Dictionary = {}
	for offer: Dictionary in offers:
		if not _valid_offer(offer):
			return false
		if seen_offer_ids.has(str(offer["offer_id"])) or seen_reward_ids.has(str(offer["reward_id"])):
			return false
		seen_offer_ids[str(offer["offer_id"])] = true
		seen_reward_ids[str(offer["reward_id"])] = true
	var generated := _generated_snapshot(int(value["reroll_count"]), int(value["revision"]))
	if not bool(generated.get("ok", false)):
		return false
	var expected := generated["snapshot"] as Dictionary
	var expected_offers := _dictionary_array(expected["offers"])
	if expected_offers.size() != offers.size():
		return false
	for index: int in range(offers.size()):
		var actual_offer := offers[index].duplicate(true)
		var expected_offer := expected_offers[index].duplicate(true)
		actual_offer["sold"] = false
		expected_offer["sold"] = false
		if actual_offer != expected_offer:
			return false
	return true


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_snapshot = value.duplicate(true)
	return snapshot() == value


func prepare_purchase(
	transaction_id: String,
	state_snapshot: Dictionary,
	offer_id: String,
	expected_revision: int
) -> Dictionary:
	var validation := _validate_transaction_request(
		"purchase", transaction_id, state_snapshot, expected_revision
	)
	if not bool(validation.get("ok", false)):
		return validation
	var after := state_snapshot.duplicate(true)
	var found := false
	var purchased_offer: Dictionary = {}
	var offers := after["offers"] as Array
	for index: int in range(offers.size()):
		var offer_value: Variant = offers[index]
		if not offer_value is Dictionary:
			return _failure(&"MERCHANT_INVENTORY_STATE_INVALID")
		var offer := (offer_value as Dictionary).duplicate(true)
		if str(offer.get("offer_id", "")) != offer_id:
			continue
		if bool(offer.get("sold", false)):
			return _failure(&"MERCHANT_INVENTORY_OFFER_SOLD", {"offer_id": offer_id})
		offer["sold"] = true
		offers[index] = offer
		purchased_offer = offer.duplicate(true)
		found = true
		break
	if not found:
		return _failure(&"MERCHANT_INVENTORY_OFFER_NOT_FOUND", {"offer_id": offer_id})
	after["revision"] = expected_revision + 1
	after["offers"] = offers
	var definition := (_definitions_by_id[str(purchased_offer["reward_id"])] as Dictionary).duplicate(true)
	var offer_payload := purchased_offer.duplicate(true)
	offer_payload["definition"] = definition
	return _prepared_result(
		_transaction_ticket(
			"purchase",
			transaction_id,
			state_snapshot,
			after,
			int(purchased_offer["price"]),
			offer_payload
		),
		{}
	)


func commit_purchase(ticket: Dictionary) -> Dictionary:
	return _commit_transaction(ticket, "purchase")


func rollback_purchase(receipt_or_ticket: Dictionary) -> Dictionary:
	return _rollback_transaction(receipt_or_ticket, "purchase")


func prepare_reroll(
	transaction_id: String,
	state_snapshot: Dictionary,
	expected_revision: int
) -> Dictionary:
	var validation := _validate_transaction_request(
		"reroll", transaction_id, state_snapshot, expected_revision
	)
	if not bool(validation.get("ok", false)):
		return validation
	var next_reroll_count := int(state_snapshot["reroll_count"]) + 1
	if next_reroll_count > _maximum_rerolls():
		return _failure(&"MERCHANT_INVENTORY_REROLL_LIMIT", {
			"reroll_count": int(state_snapshot["reroll_count"]),
			"maximum_rerolls": _maximum_rerolls(),
		})
	var generated := _generated_snapshot(next_reroll_count, expected_revision + 1)
	if not bool(generated.get("ok", false)):
		return generated
	var reroll_quote: Dictionary = ShopPriceServiceScript.new().reroll_price(
		_economy_profile.duplicate(true), int(state_snapshot["reroll_count"])
	)
	if not bool(reroll_quote.get("ok", false)):
		return _failure(&"MERCHANT_INVENTORY_PRICE_REJECTED", {
			"price_code": str(reroll_quote.get("code", "")),
		})
	var after := (generated["snapshot"] as Dictionary).duplicate(true)
	return _prepared_result(
		_transaction_ticket(
			"reroll",
			transaction_id,
			state_snapshot,
			after,
			int(reroll_quote["price"]),
			{}
		),
		{"seed_channel": str(generated["seed_channel"])}
	)


func commit_reroll(ticket: Dictionary) -> Dictionary:
	return _commit_transaction(ticket, "reroll")


func rollback_reroll(receipt_or_ticket: Dictionary) -> Dictionary:
	return _rollback_transaction(receipt_or_ticket, "reroll")


func _generated_snapshot(reroll_count: int, revision: int) -> Dictionary:
	var channel := _seed_channel(reroll_count)
	var rng := SeedServiceScript.make_rng(_run_seed, StringName(channel))
	var eligible := _eligible_definitions()
	var rules := _merchant["inventory_rules"] as Dictionary
	var minimum := int(rules["offer_count_min"])
	var maximum := mini(int(rules["offer_count_max"]), eligible.size())
	if eligible.size() < minimum or maximum < minimum:
		return _failure(&"MERCHANT_INVENTORY_CONTENT_UNAVAILABLE", {
			"merchant_id": str(_merchant["id"]),
			"eligible_count": eligible.size(),
			"required_count": minimum,
		})
	var offer_count := rng.randi_range(minimum, maximum)
	var remaining := _dictionary_array(eligible)
	var selected: Array[Dictionary] = []
	for _offer_index: int in range(offer_count):
		var rarity := _weighted_available_rarity(remaining, rules["rarity_weights"], rng)
		if rarity.is_empty():
			return _failure(&"MERCHANT_INVENTORY_CONTENT_UNAVAILABLE", {"reason": "rarity"})
		var candidates: Array[Dictionary] = []
		for definition: Dictionary in remaining:
			if str(definition["rarity"]) == rarity:
				candidates.append(definition)
		if candidates.is_empty():
			return _failure(&"MERCHANT_INVENTORY_CONTENT_UNAVAILABLE", {"rarity": rarity})
		var selected_definition := candidates[rng.randi_range(0, candidates.size() - 1)].duplicate(true)
		selected.append(selected_definition)
		for index: int in range(remaining.size() - 1, -1, -1):
			if str(remaining[index]["id"]) == str(selected_definition["id"]):
				remaining.remove_at(index)
				break

	var offers: Array[Dictionary] = []
	for index: int in range(selected.size()):
		var definition := selected[index]
		var quote_value: Variant = _price_quote.call(
			_economy_profile.duplicate(true),
			definition.duplicate(true),
			_floor_index,
			reroll_count
		)
		if not quote_value is Dictionary:
			return _failure(&"MERCHANT_INVENTORY_PRICE_REJECTED", {"reward_id": str(definition["id"])})
		var quote := quote_value as Dictionary
		if (
			not bool(quote.get("ok", false))
			or typeof(quote.get("price")) != TYPE_INT
			or int(quote.get("price", 0)) <= 0
		):
			return _failure(&"MERCHANT_INVENTORY_PRICE_REJECTED", {
				"reward_id": str(definition["id"]),
				"price_code": str(quote.get("code", "")),
			})
		offers.append({
			"offer_id": "%s:%s:r%02d:o%02d:%s" % [
				str(_merchant["id"]), _node_id, reroll_count, index, str(definition["id"]),
			],
			"reward_id": str(definition["id"]),
			"category": str(definition["category"]),
			"rarity": str(definition["rarity"]),
			"price": int(quote["price"]),
			"sold": false,
		})
	return {
		"ok": true,
		"snapshot": {
			"schema_version": SNAPSHOT_SCHEMA_VERSION,
			"merchant_id": str(_merchant["id"]),
			"node_id": _node_id,
			"floor_index": _floor_index,
			"reroll_count": reroll_count,
			"revision": revision,
			"offers": offers,
		},
		"seed_channel": channel,
	}


func _eligible_definitions() -> Array[Dictionary]:
	return _eligible_definitions_for(_merchant, _reward_definitions, _compatibility_context)


func _eligible_definitions_for(
	merchant: Dictionary,
	definitions: Array[Dictionary],
	compatibility_context: Dictionary
) -> Array[Dictionary]:
	var rules := merchant["inventory_rules"] as Dictionary
	var categories: Array = rules["content_categories"]
	var required_tags: Array = rules["required_tags"]
	var rarity_weights := rules["rarity_weights"] as Dictionary
	var eligible: Array[Dictionary] = []
	for definition: Dictionary in definitions:
		if (
			not (definition["availability"] as Array).has("LAUNCH")
			or not categories.has(str(definition["category"]))
			or float(rarity_weights.get(str(definition["rarity"]), 0.0)) <= 0.0
			or not _required_tags_match(required_tags, definition)
			or not _definition_matches_context(definition, compatibility_context)
		):
			continue
		eligible.append(definition.duplicate(true))
	eligible.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["id"]) < str(right["id"])
	)
	return eligible


func _weighted_available_rarity(
	definitions: Array[Dictionary],
	rarity_weights_value: Variant,
	rng: RandomNumberGenerator
) -> String:
	if not rarity_weights_value is Dictionary:
		return ""
	var rarity_weights := rarity_weights_value as Dictionary
	var available: Dictionary = {}
	for definition: Dictionary in definitions:
		available[str(definition["rarity"])] = true
	var weighted: Array[Dictionary] = []
	var total := 0.0
	for rarity: String in RARITIES:
		var weight := float(rarity_weights.get(rarity, 0.0))
		if not available.has(rarity) or weight <= 0.0:
			continue
		total += weight
		weighted.append({"rarity": rarity, "upper": total})
	if weighted.is_empty() or total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for entry: Dictionary in weighted:
		if roll < float(entry["upper"]):
			return str(entry["rarity"])
	return str(weighted[-1]["rarity"])


func _validate_transaction_request(
	kind: String,
	transaction_id: String,
	state_snapshot: Dictionary,
	expected_revision: int
) -> Dictionary:
	if not _configured or _snapshot.is_empty():
		return _failure(&"MERCHANT_INVENTORY_NOT_GENERATED")
	if not TRANSACTION_KINDS.has(kind) or not _valid_transaction_id(transaction_id):
		return _failure(&"MERCHANT_INVENTORY_TRANSACTION_INVALID", {"transaction_id": transaction_id})
	if state_snapshot != _snapshot or not can_restore_snapshot(state_snapshot):
		return _failure(&"MERCHANT_INVENTORY_STATE_STALE")
	if expected_revision != int(_snapshot["revision"]):
		return _failure(&"STALE_REVISION", {
			"received_revision": expected_revision,
			"last_revision": int(_snapshot["revision"]),
		})
	return _success()


func _transaction_ticket(
	kind: String,
	transaction_id: String,
	before_snapshot: Dictionary,
	after_snapshot: Dictionary,
	price: int,
	offer: Dictionary
) -> Dictionary:
	var ticket := {
		"schema_version": TRANSACTION_SCHEMA_VERSION,
		"owner_instance_id": get_instance_id(),
		"kind": kind,
		"transaction_id": transaction_id,
		"price": price,
		"offer": offer.duplicate(true),
		"before_snapshot": before_snapshot.duplicate(true),
		"after_snapshot": after_snapshot.duplicate(true),
	}
	ticket["fingerprint"] = _fingerprint(ticket)
	return ticket


func _prepared_result(ticket: Dictionary, context: Dictionary) -> Dictionary:
	var prepared_context := context.duplicate(true)
	prepared_context["transaction_id"] = str(ticket["transaction_id"])
	prepared_context["price"] = int(ticket["price"])
	return _success({
		"transaction_id": str(ticket["transaction_id"]),
		"price": int(ticket["price"]),
		"ticket": ticket.duplicate(true),
		"context": prepared_context,
	})


func _commit_transaction(ticket: Dictionary, expected_kind: String) -> Dictionary:
	if not _valid_ticket(ticket, expected_kind):
		return _failure(&"MERCHANT_INVENTORY_TICKET_INVALID")
	var before := ticket["before_snapshot"] as Dictionary
	var after := ticket["after_snapshot"] as Dictionary
	if _snapshot == after:
		return _success({"snapshot": snapshot(), "receipt": _receipt_for_ticket(ticket)})
	if _snapshot != before:
		return _failure(&"MERCHANT_INVENTORY_STATE_STALE")
	if not can_restore_snapshot(after):
		return _failure(&"MERCHANT_INVENTORY_TICKET_INVALID", {"field": "after_snapshot"})
	_snapshot = after.duplicate(true)
	return _success({"snapshot": snapshot(), "receipt": _receipt_for_ticket(ticket)})


func _rollback_transaction(receipt_or_ticket: Dictionary, expected_kind: String) -> Dictionary:
	var before: Dictionary = {}
	var after: Dictionary = {}
	if _valid_ticket(receipt_or_ticket, expected_kind):
		before = (receipt_or_ticket["before_snapshot"] as Dictionary).duplicate(true)
		after = (receipt_or_ticket["after_snapshot"] as Dictionary).duplicate(true)
	elif _valid_receipt(receipt_or_ticket, expected_kind):
		before = (receipt_or_ticket["before_snapshot"] as Dictionary).duplicate(true)
		after = (receipt_or_ticket["after_snapshot"] as Dictionary).duplicate(true)
	else:
		return _failure(&"MERCHANT_INVENTORY_RECEIPT_INVALID")
	if _snapshot == before:
		return _success({"snapshot": snapshot(), "context": {"rolled_back": false}})
	if _snapshot != after or not can_restore_snapshot(before):
		return _failure(&"MERCHANT_INVENTORY_STATE_STALE")
	_snapshot = before.duplicate(true)
	return _success({"snapshot": snapshot(), "context": {"rolled_back": true}})


func _receipt_for_ticket(ticket: Dictionary) -> Dictionary:
	var receipt := {
		"schema_version": TRANSACTION_SCHEMA_VERSION,
		"owner_instance_id": get_instance_id(),
		"kind": str(ticket["kind"]),
		"transaction_id": str(ticket["transaction_id"]),
		"price": int(ticket["price"]),
		"offer": (ticket["offer"] as Dictionary).duplicate(true),
		"before_snapshot": (ticket["before_snapshot"] as Dictionary).duplicate(true),
		"after_snapshot": (ticket["after_snapshot"] as Dictionary).duplicate(true),
		"ticket_fingerprint": str(ticket["fingerprint"]),
	}
	receipt["fingerprint"] = _fingerprint(receipt)
	return receipt


func _valid_ticket(ticket: Dictionary, expected_kind: String) -> bool:
	return (
		_has_exact_fields(ticket, TICKET_FIELDS)
		and typeof(ticket["schema_version"]) == TYPE_INT
		and int(ticket["schema_version"]) == TRANSACTION_SCHEMA_VERSION
		and typeof(ticket["owner_instance_id"]) == TYPE_INT
		and int(ticket["owner_instance_id"]) == get_instance_id()
		and typeof(ticket["kind"]) == TYPE_STRING
		and str(ticket["kind"]) == expected_kind
		and typeof(ticket["transaction_id"]) == TYPE_STRING
		and _valid_transaction_id(str(ticket["transaction_id"]))
		and typeof(ticket["price"]) == TYPE_INT
		and int(ticket["price"]) > 0
		and ticket["offer"] is Dictionary
		and _valid_transaction_offer(ticket["offer"] as Dictionary, expected_kind)
		and ticket["before_snapshot"] is Dictionary
		and ticket["after_snapshot"] is Dictionary
		and typeof(ticket["fingerprint"]) == TYPE_STRING
		and str(ticket["fingerprint"]) == _fingerprint_without(ticket, "fingerprint")
		and _ticket_transition_is_valid(ticket, expected_kind)
	)


func _valid_receipt(receipt: Dictionary, expected_kind: String) -> bool:
	if not (
		_has_exact_fields(receipt, RECEIPT_FIELDS)
		and typeof(receipt["schema_version"]) == TYPE_INT
		and int(receipt["schema_version"]) == TRANSACTION_SCHEMA_VERSION
		and typeof(receipt["owner_instance_id"]) == TYPE_INT
		and int(receipt["owner_instance_id"]) == get_instance_id()
		and typeof(receipt["kind"]) == TYPE_STRING
		and str(receipt["kind"]) == expected_kind
		and typeof(receipt["transaction_id"]) == TYPE_STRING
		and _valid_transaction_id(str(receipt["transaction_id"]))
		and typeof(receipt["price"]) == TYPE_INT
		and int(receipt["price"]) > 0
		and receipt["offer"] is Dictionary
		and _valid_transaction_offer(receipt["offer"] as Dictionary, expected_kind)
		and receipt["before_snapshot"] is Dictionary
		and receipt["after_snapshot"] is Dictionary
		and typeof(receipt["ticket_fingerprint"]) == TYPE_STRING
		and typeof(receipt["fingerprint"]) == TYPE_STRING
		and str(receipt["fingerprint"]) == _fingerprint_without(receipt, "fingerprint")
	):
		return false
	var reconstructed_ticket := {
		"schema_version": int(receipt["schema_version"]),
		"owner_instance_id": int(receipt["owner_instance_id"]),
		"kind": str(receipt["kind"]),
		"transaction_id": str(receipt["transaction_id"]),
		"price": int(receipt["price"]),
		"offer": (receipt["offer"] as Dictionary).duplicate(true),
		"before_snapshot": (receipt["before_snapshot"] as Dictionary).duplicate(true),
		"after_snapshot": (receipt["after_snapshot"] as Dictionary).duplicate(true),
	}
	reconstructed_ticket["fingerprint"] = _fingerprint(reconstructed_ticket)
	return (
		str(receipt["ticket_fingerprint"]) == str(reconstructed_ticket["fingerprint"])
		and _ticket_transition_is_valid(reconstructed_ticket, expected_kind)
	)


func _ticket_transition_is_valid(ticket: Dictionary, kind: String) -> bool:
	var before := ticket["before_snapshot"] as Dictionary
	var after := ticket["after_snapshot"] as Dictionary
	if not can_restore_snapshot(before) or not can_restore_snapshot(after):
		return false
	if (
		str(before["merchant_id"]) != str(after["merchant_id"])
		or str(before["node_id"]) != str(after["node_id"])
		or int(before["floor_index"]) != int(after["floor_index"])
		or int(after["revision"]) != int(before["revision"]) + 1
	):
		return false
	if kind == "purchase":
		if (
			int(after["reroll_count"]) != int(before["reroll_count"])
			or int(ticket["price"]) != int((ticket["offer"] as Dictionary).get("price", -1))
		):
			return false
		var requested_offer_id := str((ticket["offer"] as Dictionary).get("offer_id", ""))
		var changes := 0
		var before_offers := _dictionary_array(before["offers"])
		var after_offers := _dictionary_array(after["offers"])
		if before_offers.size() != after_offers.size():
			return false
		for index: int in range(before_offers.size()):
			var before_offer := before_offers[index]
			var after_offer := after_offers[index]
			var before_without_sold := before_offer.duplicate(true)
			var after_without_sold := after_offer.duplicate(true)
			before_without_sold.erase("sold")
			after_without_sold.erase("sold")
			if before_without_sold != after_without_sold:
				return false
			if bool(before_offer["sold"]) == bool(after_offer["sold"]):
				continue
			if (
				str(before_offer["offer_id"]) != requested_offer_id
				or bool(before_offer["sold"])
				or not bool(after_offer["sold"])
			):
				return false
			changes += 1
		return changes == 1
	if kind == "reroll":
		if int(after["reroll_count"]) != int(before["reroll_count"]) + 1:
			return false
		var quote := ShopPriceServiceScript.new().reroll_price(
			_economy_profile.duplicate(true), int(before["reroll_count"])
		)
		if not bool(quote.get("ok", false)) or int(quote.get("price", -1)) != int(ticket["price"]):
			return false
		for offer: Dictionary in _dictionary_array(after["offers"]):
			if bool(offer["sold"]):
				return false
		return true
	return false


func _valid_transaction_offer(offer: Dictionary, kind: String) -> bool:
	if kind == "reroll":
		return offer.is_empty()
	if kind != "purchase" or offer.size() != OFFER_FIELDS.size() + 1:
		return false
	var snapshot_offer := offer.duplicate(true)
	var definition_value: Variant = snapshot_offer.get("definition")
	snapshot_offer.erase("definition")
	if not _valid_offer(snapshot_offer) or not definition_value is Dictionary:
		return false
	var definition := definition_value as Dictionary
	return (
		_valid_reward_definition(definition)
		and str(definition["id"]) == str(snapshot_offer["reward_id"])
		and _definitions_by_id.has(str(definition["id"]))
		and definition == _definitions_by_id[str(definition["id"])]
		and bool(snapshot_offer["sold"])
	)


func _normalized_reward_definitions(value: Array) -> Dictionary:
	if value.is_empty():
		return _failure(&"MERCHANT_INVENTORY_DEFINITIONS_INVALID", {"reason": "empty"})
	var definitions: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for index: int in range(value.size()):
		var entry: Variant = value[index]
		if not entry is Dictionary:
			return _failure(&"MERCHANT_INVENTORY_DEFINITIONS_INVALID", {"index": index})
		var definition := (entry as Dictionary).duplicate(true)
		if not _valid_reward_definition(definition) or seen_ids.has(str(definition.get("id", ""))):
			return _failure(&"MERCHANT_INVENTORY_DEFINITIONS_INVALID", {"index": index})
		seen_ids[str(definition["id"])] = true
		definitions.append(definition)
	return {"ok": true, "definitions": definitions}


func _valid_reward_definition(value: Dictionary) -> bool:
	for field: String in ["id", "category", "availability", "tags", "compatibility", "rarity"]:
		if not value.has(field):
			return false
	if (
		typeof(value["id"]) != TYPE_STRING
		or not _valid_id(str(value["id"]))
		or typeof(value["category"]) != TYPE_STRING
		or not CONTENT_CATEGORIES.has(str(value["category"]))
		or not value["availability"] is Array
		or not value["tags"] is Array
		or not value["compatibility"] is Dictionary
		or typeof(value["rarity"]) != TYPE_STRING
		or not RARITIES.has(str(value["rarity"]))
	):
		return false
	if not _valid_string_array(value["availability"], false) or not _valid_string_array(value["tags"], true):
		return false
	for key_value: Variant in (value["compatibility"] as Dictionary).keys():
		if typeof(key_value) != TYPE_STRING or not _valid_id(str(key_value)):
			return false
		if not _valid_string_array((value["compatibility"] as Dictionary)[key_value], true):
			return false
	return true


func _normalized_compatibility_context(value: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for key_value: Variant in value.keys():
		if typeof(key_value) != TYPE_STRING or not _valid_id(str(key_value)):
			return _failure(&"MERCHANT_INVENTORY_COMPATIBILITY_INVALID")
		var entries: Variant = value[key_value]
		if not _valid_string_array(entries, false):
			return _failure(&"MERCHANT_INVENTORY_COMPATIBILITY_INVALID", {"field": str(key_value)})
		normalized[str(key_value)] = (entries as Array).duplicate()
	return {"ok": true, "context": normalized}


func _required_tags_match(required_tags: Array, definition: Dictionary) -> bool:
	var tags: Array = definition["tags"]
	for required_value: Variant in required_tags:
		var required := str(required_value)
		if required == "launch":
			if not (definition["availability"] as Array).has("LAUNCH"):
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
	return RewardCompatibilityScript.matches(definition, context)


func _valid_offer(value: Dictionary) -> bool:
	return (
		_has_exact_fields(value, OFFER_FIELDS)
		and typeof(value["offer_id"]) == TYPE_STRING
		and not str(value["offer_id"]).is_empty()
		and typeof(value["reward_id"]) == TYPE_STRING
		and _definitions_by_id.has(str(value["reward_id"]))
		and typeof(value["category"]) == TYPE_STRING
		and CONTENT_CATEGORIES.has(str(value["category"]))
		and typeof(value["rarity"]) == TYPE_STRING
		and RARITIES.has(str(value["rarity"]))
		and typeof(value["price"]) == TYPE_INT
		and int(value["price"]) > 0
		and typeof(value["sold"]) == TYPE_BOOL
	)


func _valid_string_array(value: Variant, allow_empty: bool) -> bool:
	if not value is Array or (not allow_empty and (value as Array).is_empty()):
		return false
	var seen: Dictionary = {}
	for entry: Variant in value as Array:
		if typeof(entry) != TYPE_STRING or str(entry).is_empty() or seen.has(str(entry)):
			return false
		seen[str(entry)] = true
	return true


func _maximum_rerolls() -> int:
	return int((_economy_profile["reroll_surcharge"] as Dictionary)["maximum_rerolls"])


func _seed_channel(reroll_count: int) -> String:
	return "merchant_inventory_v1:%s:%s:%d" % [
		str(_merchant["id"]), _node_id, reroll_count,
	]


func _valid_transaction_id(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile("^[a-z0-9][a-z0-9_:-]{0,95}$") == OK and regex.search(value) != null


func _valid_id(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile("^[a-z][a-z0-9_]{0,95}$") == OK and regex.search(value) != null


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	if not value is Array:
		return values
	for entry: Variant in value as Array:
		if entry is Dictionary:
			values.append((entry as Dictionary).duplicate(true))
	return values


func _fingerprint(value: Dictionary) -> String:
	return JSON.stringify(value).sha256_text()


func _fingerprint_without(value: Dictionary, field: String) -> String:
	var payload := value.duplicate(true)
	payload.erase(field)
	return _fingerprint(payload)


func _success(values: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": &"OK", "context": {}}
	for key_value: Variant in values.keys():
		result[key_value] = values[key_value]
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"context": context.duplicate(true),
		"snapshot": snapshot(),
	}
