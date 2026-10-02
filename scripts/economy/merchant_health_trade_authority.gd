class_name MerchantHealthTradeAuthority
extends RefCounted

const MerchantDefinitionScript := preload("res://scripts/dungeon/merchant_definition.gd")

const SNAPSHOT_SCHEMA_ID := "planewalker.merchant_health_trade_authority"
const SNAPSHOT_SCHEMA_VERSION := 1
const TICKET_SCHEMA_ID := "merchant_health_trade_ticket_v1"
const RECEIPT_SCHEMA_ID := "merchant_health_trade_receipt_v1"
const HEALTH_COST_RATIO := 0.30
const ELIGIBLE_RARITIES: Array[String] = ["rare", "legendary", "unique"]
const TRANSACTION_ID_PATTERN := "^[a-z0-9][a-z0-9_:-]{0,95}$"
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"merchant_id",
	"completed_transaction_ids",
]
const TICKET_FIELDS: Array[String] = [
	"schema_id",
	"owner_instance_id",
	"merchant_id",
	"transaction_id",
	"offer_id",
	"reward_id",
	"rarity",
	"cost_kind",
	"health_cost",
	"before_player_snapshot",
	"after_cost_snapshot",
	"health_ticket",
	"reward_definition",
	"reward_plan",
	"inventory_ticket",
	"fingerprint",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_id",
	"owner_instance_id",
	"merchant_id",
	"transaction_id",
	"offer_id",
	"reward_id",
	"rarity",
	"cost_kind",
	"health_cost",
	"ticket_fingerprint",
	"health_receipt",
	"reward_receipt",
	"inventory_receipt",
	"before_player_snapshot",
	"after_player_snapshot",
	"before_inventory_snapshot",
	"after_inventory_snapshot",
	"before_authority_snapshot",
	"after_authority_snapshot",
	"fingerprint",
]
const REQUIRED_PLAYER_METHODS: Array[StringName] = [
	&"reward_effect_snapshot",
	&"can_restore_reward_effect_snapshot",
	&"restore_reward_effect_snapshot",
	&"prepare_nonlethal_health_cost",
	&"commit_nonlethal_health_cost",
	&"rollback_nonlethal_health_cost",
]
const REQUIRED_REWARD_METHODS: Array[StringName] = [
	&"prepare",
	&"commit",
	&"rollback",
]
const REQUIRED_INVENTORY_METHODS: Array[StringName] = [
	&"open_inventory",
	&"snapshot",
	&"can_restore_snapshot",
	&"restore_snapshot",
	&"prepare_purchase",
	&"commit_purchase",
	&"rollback_purchase",
]

var _configured: bool = false
var _merchant: Dictionary = {}
var _player: Object
var _reward_runtime: Object
var _inventory: Object
var _completed_transaction_ids: Dictionary = {}
var _pending_tickets: Dictionary = {}


func configure(
	merchant: Dictionary,
	player: Object,
	reward_runtime: Object,
	inventory: Object
) -> Dictionary:
	var parser = MerchantDefinitionScript.new()
	var merchant_result: Dictionary = parser.configure(merchant.duplicate(true))
	if not bool(merchant_result.get("ok", false)):
		return _failure(&"MERCHANT_INVALID", merchant_result.get("context", {}))
	var normalized := parser.snapshot()
	if not (normalized["services"] as Array).has("health_trade"):
		return _failure(&"SERVICE_NOT_OFFERED")
	if not (normalized["accepted_costs"] as Array).has("health"):
		return _failure(&"COST_NOT_ACCEPTED", {"cost_kind": "health"})
	if not _has_methods(player, REQUIRED_PLAYER_METHODS):
		return _failure(&"PLAYER_INVALID")
	if not _has_methods(reward_runtime, REQUIRED_REWARD_METHODS):
		return _failure(&"REWARD_RUNTIME_INVALID")
	if not _has_methods(inventory, REQUIRED_INVENTORY_METHODS):
		return _failure(&"INVENTORY_INVALID")
	var inventory_result := _dictionary(inventory.call("open_inventory"))
	if not bool(inventory_result.get("ok", false)):
		return _failure(&"INVENTORY_UNAVAILABLE", {"cause": inventory_result})
	var inventory_snapshot := _nested_dictionary(inventory_result, "snapshot")
	if inventory_snapshot.is_empty() or not bool(inventory.call(
		"can_restore_snapshot", inventory_snapshot.duplicate(true)
	)):
		return _failure(&"INVENTORY_INVALID")
	var player_snapshot := _player_snapshot(player)
	if player_snapshot.is_empty() or not bool(player.call(
		"can_restore_reward_effect_snapshot", player_snapshot.duplicate(true)
	)):
		return _failure(&"PLAYER_INVALID")

	_merchant = normalized.duplicate(true)
	_player = player
	_reward_runtime = reward_runtime
	_inventory = inventory
	_completed_transaction_ids.clear()
	_pending_tickets.clear()
	_configured = true
	return _success({"snapshot": snapshot()})


func prepare_trade(
	transaction_id: String,
	offer_id: String,
	expected_inventory_revision: int
) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _valid_transaction_id(transaction_id):
		return _failure(&"TRANSACTION_INVALID")
	if _completed_transaction_ids.has(transaction_id) or _pending_tickets.has(transaction_id):
		return _failure(&"DUPLICATE_TRANSACTION")
	var opened := _dictionary(_inventory.call("open_inventory"))
	if not bool(opened.get("ok", false)):
		return _failure(&"INVENTORY_UNAVAILABLE", {"cause": opened})
	var inventory_snapshot := _nested_dictionary(opened, "snapshot")
	if inventory_snapshot.is_empty():
		return _failure(&"INVENTORY_STATE_INVALID")
	if (
		typeof(inventory_snapshot.get("revision")) != TYPE_INT
		or int(inventory_snapshot["revision"]) != expected_inventory_revision
	):
		return _failure(&"STALE_REVISION", {
			"received_revision": expected_inventory_revision,
			"last_revision": int(inventory_snapshot.get("revision", -1)),
		})
	var offer_result := _authoritative_offer(inventory_snapshot, offer_id)
	if not bool(offer_result.get("ok", false)):
		return offer_result
	var authoritative_offer := offer_result["offer"] as Dictionary

	var before_player := _player_snapshot(_player)
	var health_result := _authoritative_health(before_player)
	if not bool(health_result.get("ok", false)):
		return health_result
	var current_hp := float(health_result["current_hp"])
	var health_cost := ceili(current_hp * HEALTH_COST_RATIO)
	if health_cost <= 0 or current_hp - float(health_cost) < 1.0:
		return _failure(&"HEALTH_COST_LETHAL", {
			"current_hp": current_hp,
			"health_cost": health_cost,
		})

	var inventory_prepared := _dictionary(_inventory.call(
		"prepare_purchase",
		transaction_id,
		inventory_snapshot.duplicate(true),
		offer_id,
		expected_inventory_revision
	))
	if not bool(inventory_prepared.get("ok", false)):
		return _failure(&"INVENTORY_PREPARE_FAILED", {"cause": inventory_prepared})
	var inventory_ticket := _nested_dictionary(inventory_prepared, "ticket")
	var inventory_offer := _nested_dictionary(inventory_ticket, "offer")
	var reward_definition := _nested_dictionary(inventory_offer, "definition")
	if not _inventory_ticket_matches_offer(
		inventory_ticket, inventory_offer, reward_definition, authoritative_offer, transaction_id
	):
		_rollback_inventory(inventory_ticket)
		return _failure(&"INVENTORY_TICKET_INVALID")

	var health_prepared := _dictionary(_player.call(
		"prepare_nonlethal_health_cost",
		transaction_id,
		health_cost,
		before_player.duplicate(true)
	))
	if not bool(health_prepared.get("ok", false)):
		_rollback_inventory(inventory_ticket)
		return _failure(&"HEALTH_PREPARE_FAILED", {"cause": health_prepared})
	var health_ticket := _nested_dictionary(health_prepared, "ticket")
	var after_cost := _expected_after_cost(before_player, health_cost)
	if not _valid_health_ticket(
		health_ticket, transaction_id, health_cost, before_player, after_cost
	):
		_player.call("rollback_nonlethal_health_cost", health_ticket.duplicate(true))
		_rollback_inventory(inventory_ticket)
		return _failure(&"HEALTH_TICKET_INVALID")

	var reward_prepared := _dictionary(_reward_runtime.call(
		"prepare", reward_definition.duplicate(true), after_cost.duplicate(true)
	))
	if not bool(reward_prepared.get("ok", false)):
		_player.call("rollback_nonlethal_health_cost", health_ticket.duplicate(true))
		_rollback_inventory(inventory_ticket)
		return _failure(&"REWARD_PREPARE_FAILED", {"cause": reward_prepared})
	var reward_plan := _nested_dictionary(reward_prepared, "plan")
	if reward_plan.is_empty():
		_player.call("rollback_nonlethal_health_cost", health_ticket.duplicate(true))
		_rollback_inventory(inventory_ticket)
		return _failure(&"REWARD_PLAN_INVALID")

	var unsigned_ticket := {
		"schema_id": TICKET_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"merchant_id": str(_merchant["id"]),
		"transaction_id": transaction_id,
		"offer_id": offer_id,
		"reward_id": str(authoritative_offer["reward_id"]),
		"rarity": str(authoritative_offer["rarity"]),
		"cost_kind": "health",
		"health_cost": health_cost,
		"before_player_snapshot": before_player.duplicate(true),
		"after_cost_snapshot": after_cost.duplicate(true),
		"health_ticket": health_ticket.duplicate(true),
		"reward_definition": reward_definition.duplicate(true),
		"reward_plan": reward_plan.duplicate(true),
		"inventory_ticket": inventory_ticket.duplicate(true),
	}
	var ticket := unsigned_ticket.duplicate(true)
	ticket["fingerprint"] = _digest(unsigned_ticket)
	_pending_tickets[transaction_id] = ticket.duplicate(true)
	return _success({"ticket": ticket.duplicate(true)})


func commit_trade(ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _valid_ticket(ticket):
		return _failure(&"TICKET_INVALID")
	var transaction_id := str(ticket["transaction_id"])
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"DUPLICATE_TRANSACTION")
	if not _pending_tickets.has(transaction_id) or _pending_tickets[transaction_id] != ticket:
		return _failure(&"TICKET_STALE")
	var before_authority := snapshot()
	var before_player := (ticket["before_player_snapshot"] as Dictionary).duplicate(true)
	var inventory_ticket := ticket["inventory_ticket"] as Dictionary
	var before_inventory := (inventory_ticket["before_snapshot"] as Dictionary).duplicate(true)
	if _player_snapshot(_player) != before_player or _inventory_snapshot() != before_inventory:
		return _failure(&"PARTICIPANT_STALE")

	var health_commit := _dictionary(_player.call(
		"commit_nonlethal_health_cost", (ticket["health_ticket"] as Dictionary).duplicate(true)
	))
	if not bool(health_commit.get("ok", false)):
		_player.call(
			"rollback_nonlethal_health_cost",
			(ticket["health_ticket"] as Dictionary).duplicate(true)
		)
		var restored := _restore_player(before_player)
		return _failure(
			&"HEALTH_COMMIT_FAILED" if restored else &"ROLLBACK_FAILED",
			{"cause": health_commit}
		)
	var health_receipt := _nested_dictionary(health_commit, "receipt")
	if health_receipt.is_empty():
		_restore_player(before_player)
		return _failure(&"ROLLBACK_FAILED", {"reason": "missing_health_receipt"})

	var reward_commit := _dictionary(_reward_runtime.call(
		"commit", (ticket["reward_plan"] as Dictionary).duplicate(true), _player
	))
	if not bool(reward_commit.get("ok", false)):
		_player.call("rollback_nonlethal_health_cost", health_receipt.duplicate(true))
		var restored := _restore_player(before_player)
		return _failure(
			&"REWARD_COMMIT_FAILED" if restored else &"ROLLBACK_FAILED",
			{"cause": reward_commit}
		)
	var reward_receipt := _nested_dictionary(reward_commit, "receipt")
	if reward_receipt.is_empty():
		_restore_player(before_player)
		return _failure(&"ROLLBACK_FAILED", {"reason": "missing_reward_receipt"})

	var inventory_commit := _dictionary(_inventory.call(
		"commit_purchase", inventory_ticket.duplicate(true)
	))
	if not bool(inventory_commit.get("ok", false)):
		_rollback_inventory(inventory_ticket)
		_reward_runtime.call("rollback", reward_receipt.duplicate(true), _player)
		_player.call("rollback_nonlethal_health_cost", health_receipt.duplicate(true))
		var inventory_restored := _restore_inventory(before_inventory)
		var player_restored := _restore_player(before_player)
		return _failure(
			&"INVENTORY_COMMIT_FAILED" if inventory_restored and player_restored else &"ROLLBACK_FAILED",
			{"cause": inventory_commit}
		)
	var inventory_receipt := _nested_dictionary(inventory_commit, "receipt")
	if inventory_receipt.is_empty():
		_rollback_inventory(inventory_ticket)
		_reward_runtime.call("rollback", reward_receipt.duplicate(true), _player)
		_player.call("rollback_nonlethal_health_cost", health_receipt.duplicate(true))
		_restore_inventory(before_inventory)
		_restore_player(before_player)
		return _failure(&"ROLLBACK_FAILED", {"reason": "missing_inventory_receipt"})

	_completed_transaction_ids[transaction_id] = true
	_pending_tickets.erase(transaction_id)
	var after_authority := snapshot()
	var after_player := _player_snapshot(_player)
	var after_inventory := _inventory_snapshot()
	var unsigned_receipt := {
		"schema_id": RECEIPT_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"merchant_id": str(_merchant["id"]),
		"transaction_id": transaction_id,
		"offer_id": str(ticket["offer_id"]),
		"reward_id": str(ticket["reward_id"]),
		"rarity": str(ticket["rarity"]),
		"cost_kind": "health",
		"health_cost": int(ticket["health_cost"]),
		"ticket_fingerprint": str(ticket["fingerprint"]),
		"health_receipt": health_receipt.duplicate(true),
		"reward_receipt": reward_receipt.duplicate(true),
		"inventory_receipt": inventory_receipt.duplicate(true),
		"before_player_snapshot": before_player.duplicate(true),
		"after_player_snapshot": after_player.duplicate(true),
		"before_inventory_snapshot": before_inventory.duplicate(true),
		"after_inventory_snapshot": after_inventory.duplicate(true),
		"before_authority_snapshot": before_authority.duplicate(true),
		"after_authority_snapshot": after_authority.duplicate(true),
	}
	var receipt := unsigned_receipt.duplicate(true)
	receipt["fingerprint"] = _digest(unsigned_receipt)
	return _success({"receipt": receipt.duplicate(true)})


func rollback_trade(receipt_or_ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if _valid_ticket(receipt_or_ticket):
		var pending_id := str(receipt_or_ticket["transaction_id"])
		if (
			not _pending_tickets.has(pending_id)
			or _pending_tickets[pending_id] != receipt_or_ticket
		):
			return _failure(&"TICKET_STALE")
		_pending_tickets.erase(pending_id)
		return _success({"transaction_id": pending_id, "rolled_back": "pending"})
	if not _valid_receipt(receipt_or_ticket):
		return _failure(&"RECEIPT_INVALID")
	if (
		snapshot() != receipt_or_ticket["after_authority_snapshot"]
		or _player_snapshot(_player) != receipt_or_ticket["after_player_snapshot"]
		or _inventory_snapshot() != receipt_or_ticket["after_inventory_snapshot"]
	):
		return _failure(&"RECEIPT_STALE")
	var inventory_result := _dictionary(_inventory.call(
		"rollback_purchase",
		(receipt_or_ticket["inventory_receipt"] as Dictionary).duplicate(true)
	))
	var reward_result := _dictionary(_reward_runtime.call(
		"rollback",
		(receipt_or_ticket["reward_receipt"] as Dictionary).duplicate(true),
		_player
	))
	var health_result := _dictionary(_player.call(
		"rollback_nonlethal_health_cost",
		(receipt_or_ticket["health_receipt"] as Dictionary).duplicate(true)
	))
	var inventory_restored := _restore_inventory(
		receipt_or_ticket["before_inventory_snapshot"] as Dictionary
	)
	var player_restored := _restore_player(
		receipt_or_ticket["before_player_snapshot"] as Dictionary
	)
	if not inventory_restored or not player_restored:
		return _failure(&"ROLLBACK_FAILED", {
			"inventory": inventory_result,
			"reward": reward_result,
			"health": health_result,
		})
	var before_authority := receipt_or_ticket["before_authority_snapshot"] as Dictionary
	if not restore_snapshot(before_authority):
		return _failure(&"ROLLBACK_FAILED", {"reason": "authority_restore"})
	return _success({
		"transaction_id": str(receipt_or_ticket["transaction_id"]),
		"rolled_back": "committed",
	})


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	var completed_ids: Array[String] = []
	for transaction_id_value: Variant in _completed_transaction_ids.keys():
		completed_ids.append(str(transaction_id_value))
	completed_ids.sort()
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"merchant_id": str(_merchant["id"]),
		"completed_transaction_ids": completed_ids,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if not _configured or not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return false
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != SNAPSHOT_SCHEMA_ID
		or typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != SNAPSHOT_SCHEMA_VERSION
		or typeof(value["merchant_id"]) != TYPE_STRING
		or str(value["merchant_id"]) != str(_merchant["id"])
		or not value["completed_transaction_ids"] is Array
	):
		return false
	var normalized: Array[String] = []
	var seen: Dictionary = {}
	for transaction_id_value: Variant in value["completed_transaction_ids"] as Array:
		if typeof(transaction_id_value) != TYPE_STRING:
			return false
		var transaction_id := str(transaction_id_value)
		if not _valid_transaction_id(transaction_id) or seen.has(transaction_id):
			return false
		seen[transaction_id] = true
		normalized.append(transaction_id)
	var sorted := normalized.duplicate()
	sorted.sort()
	return normalized == sorted


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	var restored: Dictionary = {}
	for transaction_id_value: Variant in value["completed_transaction_ids"] as Array:
		restored[str(transaction_id_value)] = true
	_completed_transaction_ids = restored
	_pending_tickets.clear()
	return snapshot() == value


func _authoritative_offer(inventory_snapshot: Dictionary, offer_id: String) -> Dictionary:
	var offers_value: Variant = inventory_snapshot.get("offers")
	if not offers_value is Array:
		return _failure(&"INVENTORY_STATE_INVALID")
	var selected: Dictionary = {}
	var has_eligible := false
	for offer_value: Variant in offers_value as Array:
		if not offer_value is Dictionary:
			return _failure(&"INVENTORY_STATE_INVALID")
		var offer := offer_value as Dictionary
		if not bool(offer.get("sold", true)) and ELIGIBLE_RARITIES.has(str(offer.get("rarity", ""))):
			has_eligible = true
		if str(offer.get("offer_id", "")) == offer_id:
			selected = offer.duplicate(true)
	if selected.is_empty():
		return _failure(&"OFFER_NOT_FOUND", {"offer_id": offer_id})
	if bool(selected.get("sold", true)):
		return _failure(&"OFFER_SOLD", {"offer_id": offer_id})
	if not ELIGIBLE_RARITIES.has(str(selected.get("rarity", ""))):
		return _failure(&"OFFER_NOT_ELIGIBLE" if has_eligible else &"NO_ELIGIBLE_OFFER")
	return _success({"offer": selected})


func _authoritative_health(player_snapshot: Dictionary) -> Dictionary:
	var health_value: Variant = player_snapshot.get("health")
	if not health_value is Dictionary:
		return _failure(&"PLAYER_SNAPSHOT_INVALID", {"field": "health"})
	var health := health_value as Dictionary
	if (
		typeof(health.get("current_hp")) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(health.get("max_hp")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(health["current_hp"]))
		or not is_finite(float(health["max_hp"]))
		or float(health["current_hp"]) < 0.0
		or float(health["max_hp"]) <= 0.0
		or float(health["current_hp"]) > float(health["max_hp"])
	):
		return _failure(&"PLAYER_SNAPSHOT_INVALID", {"field": "health"})
	return _success({
		"current_hp": float(health["current_hp"]),
		"max_hp": float(health["max_hp"]),
	})


func _expected_after_cost(before: Dictionary, health_cost: int) -> Dictionary:
	var after := before.duplicate(true)
	var health := after["health"] as Dictionary
	health["current_hp"] = float(health["current_hp"]) - float(health_cost)
	return after


func _valid_health_ticket(
	health_ticket: Dictionary,
	transaction_id: String,
	health_cost: int,
	before: Dictionary,
	after: Dictionary
) -> bool:
	return (
		str(health_ticket.get("transaction_id", "")) == transaction_id
		and typeof(health_ticket.get("cost")) == TYPE_INT
		and int(health_ticket["cost"]) == health_cost
		and health_ticket.get("before_snapshot", {}) == before
		and health_ticket.get("after_snapshot", {}) == after
	)


func _inventory_ticket_matches_offer(
	inventory_ticket: Dictionary,
	inventory_offer: Dictionary,
	reward_definition: Dictionary,
	authoritative_offer: Dictionary,
	transaction_id: String
) -> bool:
	return (
		str(inventory_ticket.get("transaction_id", "")) == transaction_id
		and not inventory_offer.is_empty()
		and str(inventory_offer.get("offer_id", "")) == str(authoritative_offer["offer_id"])
		and str(inventory_offer.get("reward_id", "")) == str(authoritative_offer["reward_id"])
		and str(inventory_offer.get("rarity", "")) == str(authoritative_offer["rarity"])
		and bool(inventory_offer.get("sold", false))
		and not reward_definition.is_empty()
		and str(reward_definition.get("id", "")) == str(authoritative_offer["reward_id"])
		and str(reward_definition.get("rarity", "")) == str(authoritative_offer["rarity"])
		and ELIGIBLE_RARITIES.has(str(reward_definition.get("rarity", "")))
	)


func _valid_ticket(ticket: Dictionary) -> bool:
	return (
		_has_exact_fields(ticket, TICKET_FIELDS)
		and typeof(ticket["schema_id"]) == TYPE_STRING
		and str(ticket["schema_id"]) == TICKET_SCHEMA_ID
		and typeof(ticket["owner_instance_id"]) == TYPE_INT
		and int(ticket["owner_instance_id"]) == get_instance_id()
		and typeof(ticket["merchant_id"]) == TYPE_STRING
		and str(ticket["merchant_id"]) == str(_merchant.get("id", ""))
		and typeof(ticket["transaction_id"]) == TYPE_STRING
		and _valid_transaction_id(str(ticket["transaction_id"]))
		and typeof(ticket["offer_id"]) == TYPE_STRING
		and not str(ticket["offer_id"]).is_empty()
		and typeof(ticket["reward_id"]) == TYPE_STRING
		and not str(ticket["reward_id"]).is_empty()
		and typeof(ticket["rarity"]) == TYPE_STRING
		and ELIGIBLE_RARITIES.has(str(ticket["rarity"]))
		and typeof(ticket["cost_kind"]) == TYPE_STRING
		and str(ticket["cost_kind"]) == "health"
		and typeof(ticket["health_cost"]) == TYPE_INT
		and int(ticket["health_cost"]) > 0
		and ticket["before_player_snapshot"] is Dictionary
		and ticket["after_cost_snapshot"] is Dictionary
		and ticket["health_ticket"] is Dictionary
		and ticket["reward_definition"] is Dictionary
		and ticket["reward_plan"] is Dictionary
		and ticket["inventory_ticket"] is Dictionary
		and typeof(ticket["fingerprint"]) == TYPE_STRING
		and str(ticket["fingerprint"]) == _digest_without(ticket, "fingerprint")
	)


func _valid_receipt(receipt: Dictionary) -> bool:
	return (
		_has_exact_fields(receipt, RECEIPT_FIELDS)
		and typeof(receipt["schema_id"]) == TYPE_STRING
		and str(receipt["schema_id"]) == RECEIPT_SCHEMA_ID
		and typeof(receipt["owner_instance_id"]) == TYPE_INT
		and int(receipt["owner_instance_id"]) == get_instance_id()
		and typeof(receipt["merchant_id"]) == TYPE_STRING
		and str(receipt["merchant_id"]) == str(_merchant.get("id", ""))
		and typeof(receipt["transaction_id"]) == TYPE_STRING
		and _valid_transaction_id(str(receipt["transaction_id"]))
		and typeof(receipt["offer_id"]) == TYPE_STRING
		and typeof(receipt["reward_id"]) == TYPE_STRING
		and typeof(receipt["rarity"]) == TYPE_STRING
		and ELIGIBLE_RARITIES.has(str(receipt["rarity"]))
		and typeof(receipt["cost_kind"]) == TYPE_STRING
		and str(receipt["cost_kind"]) == "health"
		and typeof(receipt["health_cost"]) == TYPE_INT
		and int(receipt["health_cost"]) > 0
		and typeof(receipt["ticket_fingerprint"]) == TYPE_STRING
		and receipt["health_receipt"] is Dictionary
		and receipt["reward_receipt"] is Dictionary
		and receipt["inventory_receipt"] is Dictionary
		and receipt["before_player_snapshot"] is Dictionary
		and receipt["after_player_snapshot"] is Dictionary
		and receipt["before_inventory_snapshot"] is Dictionary
		and receipt["after_inventory_snapshot"] is Dictionary
		and receipt["before_authority_snapshot"] is Dictionary
		and receipt["after_authority_snapshot"] is Dictionary
		and typeof(receipt["fingerprint"]) == TYPE_STRING
		and str(receipt["fingerprint"]) == _digest_without(receipt, "fingerprint")
	)


func _restore_player(target: Dictionary) -> bool:
	if not bool(_player.call("can_restore_reward_effect_snapshot", target.duplicate(true))):
		return false
	var restored: Variant = _player.call(
		"restore_reward_effect_snapshot", target.duplicate(true)
	)
	return typeof(restored) == TYPE_BOOL and bool(restored) and _player_snapshot(_player) == target


func _restore_inventory(target: Dictionary) -> bool:
	if not bool(_inventory.call("can_restore_snapshot", target.duplicate(true))):
		return false
	var restored: Variant = _inventory.call("restore_snapshot", target.duplicate(true))
	return typeof(restored) == TYPE_BOOL and bool(restored) and _inventory_snapshot() == target


func _rollback_inventory(ticket_or_receipt: Dictionary) -> bool:
	if ticket_or_receipt.is_empty():
		return false
	var result := _dictionary(_inventory.call(
		"rollback_purchase", ticket_or_receipt.duplicate(true)
	))
	return bool(result.get("ok", false))


func _player_snapshot(player: Object) -> Dictionary:
	return _dictionary(player.call("reward_effect_snapshot"))


func _inventory_snapshot() -> Dictionary:
	return _dictionary(_inventory.call("snapshot"))


func _has_methods(value: Object, methods: Array[StringName]) -> bool:
	if value == null:
		return false
	for method: StringName in methods:
		if not value.has_method(method):
			return false
	return true


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _valid_transaction_id(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(TRANSACTION_ID_PATTERN) == OK and regex.search(value) != null


func _dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _nested_dictionary(value: Dictionary, field: String) -> Dictionary:
	return _dictionary(value.get(field))


func _digest(value: Dictionary) -> String:
	return JSON.stringify(value).sha256_text()


func _digest_without(value: Dictionary, field: String) -> String:
	var payload := value.duplicate(true)
	payload.erase(field)
	return _digest(payload)


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
