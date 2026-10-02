class_name MerchantServiceAuthority
extends RefCounted

const MerchantDefinitionScript := preload("res://scripts/dungeon/merchant_definition.gd")
const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")
const ShopPriceServiceScript := preload("res://scripts/economy/shop_price_service.gd")

const SNAPSHOT_SCHEMA_ID := "planewalker.merchant_service_authority"
const SNAPSHOT_SCHEMA_VERSION := 1
const TICKET_SCHEMA_ID := "merchant_service_ticket_v1"
const RECEIPT_SCHEMA_ID := "merchant_service_receipt_v1"
const HEAL_MAX_HP_RATIO := 0.30
const TRANSACTION_ID_PATTERN := "^[a-z0-9][a-z0-9_:-]{0,95}$"
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"merchant_id",
	"profile_id",
	"floor_number",
	"completed_transaction_ids",
]
const TICKET_FIELDS: Array[String] = [
	"schema_id",
	"owner_instance_id",
	"transaction_id",
	"service_id",
	"target_id",
	"merchant_id",
	"floor_number",
	"cost_kind",
	"price",
	"heal_amount",
	"reward_plan",
	"fingerprint",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_id",
	"owner_instance_id",
	"transaction_id",
	"service_id",
	"target_id",
	"cost_kind",
	"price",
	"heal_amount",
	"ticket_fingerprint",
	"reward_receipt",
	"before_snapshot",
	"after_snapshot",
	"fingerprint",
]

var _configured: bool = false
var _merchant: Dictionary = {}
var _profile: Dictionary = {}
var _floor_number: int = 0
var _player: Object
var _reward_runtime: Object
var _completed_transaction_ids: Dictionary = {}
var _pending_tickets: Dictionary = {}


func configure(
	merchant: Dictionary,
	profile: Dictionary,
	floor_number: int,
	player: Object,
	reward_runtime: Object
) -> Dictionary:
	var merchant_parser = MerchantDefinitionScript.new()
	var merchant_result: Dictionary = merchant_parser.configure(merchant.duplicate(true))
	if not bool(merchant_result.get("ok", false)):
		return _failure(&"MERCHANT_INVALID", merchant_result.get("context", {}))
	var profile_parser = EconomyProfileScript.new()
	var profile_result: Dictionary = profile_parser.configure(profile.duplicate(true))
	if not bool(profile_result.get("ok", false)):
		return _failure(&"PROFILE_INVALID", profile_result.get("context", {}))
	var normalized_merchant: Dictionary = merchant_parser.snapshot()
	var normalized_profile: Dictionary = profile_parser.snapshot()
	if (
		floor_number < 1
		or floor_number > 5
		or floor_number < int(normalized_merchant["floor_min"])
		or floor_number > int(normalized_merchant["floor_max"])
	):
		return _failure(&"FLOOR_INVALID", {"floor_number": floor_number})
	if str(normalized_merchant["economy_profile_id"]) != str(normalized_profile["id"]):
		return _failure(&"PROFILE_MISMATCH")
	if not _valid_player(player):
		return _failure(&"PLAYER_INVALID")
	if not _valid_reward_runtime(reward_runtime):
		return _failure(&"REWARD_RUNTIME_INVALID")

	_merchant = normalized_merchant.duplicate(true)
	_profile = normalized_profile.duplicate(true)
	_floor_number = floor_number
	_player = player
	_reward_runtime = reward_runtime
	_completed_transaction_ids.clear()
	_pending_tickets.clear()
	_configured = true
	return _success({"snapshot": snapshot()})


func prepare_service(
	transaction_id: String,
	service_id: StringName,
	target_id: String = ""
) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _valid_transaction_id(transaction_id):
		return _failure(&"TRANSACTION_INVALID", {"transaction_id": transaction_id})
	if _completed_transaction_ids.has(transaction_id) or _pending_tickets.has(transaction_id):
		return _failure(&"DUPLICATE_TRANSACTION", {"transaction_id": transaction_id})
	var normalized_service := str(service_id)
	if normalized_service != "heal":
		return _failure(&"SERVICE_UNSUPPORTED", {"service_id": normalized_service})
	if not (_merchant["services"] as Array).has(normalized_service):
		return _failure(&"SERVICE_NOT_OFFERED", {"service_id": normalized_service})
	if not (_merchant["accepted_costs"] as Array).has("gold"):
		return _failure(&"COST_NOT_ACCEPTED", {"cost_kind": "gold"})
	var normalized_target := target_id.strip_edges()
	if not normalized_target.is_empty() and normalized_target != "player":
		return _failure(&"TARGET_INVALID", {"target_id": target_id})

	var player_snapshot_value: Variant = _player.call("reward_effect_snapshot")
	if not player_snapshot_value is Dictionary:
		return _failure(&"PLAYER_SNAPSHOT_INVALID")
	var player_snapshot := (player_snapshot_value as Dictionary).duplicate(true)
	var health_result := _authoritative_health(player_snapshot)
	if not bool(health_result.get("ok", false)):
		return health_result
	var current_hp := float(health_result["current_hp"])
	var max_hp := float(health_result["max_hp"])
	if current_hp >= max_hp:
		return _failure(&"HEAL_NOT_NEEDED")
	var heal_amount := max_hp * HEAL_MAX_HP_RATIO
	if not is_finite(heal_amount) or heal_amount <= 0.0:
		return _failure(&"PLAYER_SNAPSHOT_INVALID", {"field": "health.max_hp"})

	var price_result: Dictionary = ShopPriceServiceScript.new().service_price(
		_profile.duplicate(true),
		&"heal",
		_floor_number
	)
	if not bool(price_result.get("ok", false)):
		return _failure(&"PRICE_UNAVAILABLE", {"cause": price_result.duplicate(true)})
	var definition := {
		"id": "merchant_heal:%s:%s" % [str(_merchant["id"]), transaction_id],
		"category": "item",
		"effects": {"heal": heal_amount},
	}
	var reward_prepare_value: Variant = _reward_runtime.call(
		"prepare",
		definition.duplicate(true),
		player_snapshot.duplicate(true)
	)
	if not reward_prepare_value is Dictionary:
		return _failure(&"REWARD_PREPARE_FAILED", {"reason": "invalid_result"})
	var reward_prepare := (reward_prepare_value as Dictionary).duplicate(true)
	if not bool(reward_prepare.get("ok", false)):
		return _failure(&"REWARD_PREPARE_FAILED", {"cause": reward_prepare})
	var reward_plan_value: Variant = reward_prepare.get("plan")
	if not reward_plan_value is Dictionary or (reward_plan_value as Dictionary).is_empty():
		return _failure(&"REWARD_PREPARE_FAILED", {"reason": "missing_plan"})

	var unsigned_ticket := {
		"schema_id": TICKET_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"service_id": "heal",
		"target_id": "player",
		"merchant_id": str(_merchant["id"]),
		"floor_number": _floor_number,
		"cost_kind": "gold",
		"price": int(price_result["price"]),
		"heal_amount": heal_amount,
		"reward_plan": (reward_plan_value as Dictionary).duplicate(true),
	}
	var ticket := unsigned_ticket.duplicate(true)
	ticket["fingerprint"] = _digest(unsigned_ticket)
	_pending_tickets[transaction_id] = ticket.duplicate(true)
	return _success({"ticket": ticket.duplicate(true)})


func commit_service(ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _valid_ticket(ticket):
		return _failure(&"TICKET_INVALID")
	var transaction_id := str(ticket["transaction_id"])
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"DUPLICATE_TRANSACTION", {"transaction_id": transaction_id})
	if not _pending_tickets.has(transaction_id) or _pending_tickets[transaction_id] != ticket:
		return _failure(&"TICKET_STALE")
	var before := snapshot()
	var reward_commit_value: Variant = _reward_runtime.call(
		"commit",
		(ticket["reward_plan"] as Dictionary).duplicate(true),
		_player
	)
	if not reward_commit_value is Dictionary:
		return _failure(&"REWARD_COMMIT_FAILED", {"reason": "invalid_result"})
	var reward_commit := (reward_commit_value as Dictionary).duplicate(true)
	if not bool(reward_commit.get("ok", false)):
		return _failure(&"REWARD_COMMIT_FAILED", {"cause": reward_commit})
	var reward_receipt_value: Variant = reward_commit.get("receipt")
	if not reward_receipt_value is Dictionary or (reward_receipt_value as Dictionary).is_empty():
		return _failure(&"INTEGRITY_FAILURE", {"reason": "missing_reward_receipt"})

	_completed_transaction_ids[transaction_id] = true
	_pending_tickets.erase(transaction_id)
	var after := snapshot()
	var unsigned_receipt := {
		"schema_id": RECEIPT_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"service_id": "heal",
		"target_id": "player",
		"cost_kind": "gold",
		"price": int(ticket["price"]),
		"heal_amount": float(ticket["heal_amount"]),
		"ticket_fingerprint": str(ticket["fingerprint"]),
		"reward_receipt": (reward_receipt_value as Dictionary).duplicate(true),
		"before_snapshot": before.duplicate(true),
		"after_snapshot": after.duplicate(true),
	}
	var receipt := unsigned_receipt.duplicate(true)
	receipt["fingerprint"] = _digest(unsigned_receipt)
	return _success({"receipt": receipt.duplicate(true)})


func rollback_service(receipt_or_ticket: Dictionary) -> Dictionary:
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
	var transaction_id := str(receipt_or_ticket["transaction_id"])
	if snapshot() != receipt_or_ticket["after_snapshot"]:
		return _failure(&"RECEIPT_STALE")
	var reward_rollback_value: Variant = _reward_runtime.call(
		"rollback",
		(receipt_or_ticket["reward_receipt"] as Dictionary).duplicate(true),
		_player
	)
	if not reward_rollback_value is Dictionary:
		return _failure(&"REWARD_ROLLBACK_FAILED", {"reason": "invalid_result"})
	var reward_rollback := (reward_rollback_value as Dictionary).duplicate(true)
	if not bool(reward_rollback.get("ok", false)):
		return _failure(&"REWARD_ROLLBACK_FAILED", {"cause": reward_rollback})
	var before := receipt_or_ticket["before_snapshot"] as Dictionary
	if not can_restore_snapshot(before) or not restore_snapshot(before):
		return _failure(&"INTEGRITY_FAILURE", {"reason": "service_state_restore"})
	return _success({"transaction_id": transaction_id, "rolled_back": "committed"})


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
		"profile_id": str(_profile["id"]),
		"floor_number": _floor_number,
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
		or typeof(value["profile_id"]) != TYPE_STRING
		or str(value["profile_id"]) != str(_profile["id"])
		or typeof(value["floor_number"]) != TYPE_INT
		or int(value["floor_number"]) != _floor_number
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


func _authoritative_health(player_snapshot: Dictionary) -> Dictionary:
	var health_value: Variant = player_snapshot.get("health")
	if not health_value is Dictionary:
		return _failure(&"PLAYER_SNAPSHOT_INVALID", {"field": "health"})
	var health := health_value as Dictionary
	var current_value: Variant = health.get("current_hp")
	var max_value: Variant = health.get("max_hp")
	if (
		typeof(current_value) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(max_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(current_value))
		or not is_finite(float(max_value))
		or float(max_value) <= 0.0
		or float(current_value) < 0.0
		or float(current_value) > float(max_value)
		or bool(health.get("dead", false))
	):
		return _failure(&"PLAYER_SNAPSHOT_INVALID", {"field": "health"})
	return {
		"ok": true,
		"current_hp": float(current_value),
		"max_hp": float(max_value),
	}


func _valid_ticket(ticket: Dictionary) -> bool:
	if not _has_exact_fields(ticket, TICKET_FIELDS):
		return false
	if (
		typeof(ticket["schema_id"]) != TYPE_STRING
		or str(ticket["schema_id"]) != TICKET_SCHEMA_ID
		or typeof(ticket["owner_instance_id"]) != TYPE_INT
		or int(ticket["owner_instance_id"]) != get_instance_id()
		or typeof(ticket["transaction_id"]) != TYPE_STRING
		or not _valid_transaction_id(str(ticket["transaction_id"]))
		or typeof(ticket["service_id"]) != TYPE_STRING
		or str(ticket["service_id"]) != "heal"
		or typeof(ticket["target_id"]) != TYPE_STRING
		or str(ticket["target_id"]) != "player"
		or typeof(ticket["merchant_id"]) != TYPE_STRING
		or str(ticket["merchant_id"]) != str(_merchant["id"])
		or typeof(ticket["floor_number"]) != TYPE_INT
		or int(ticket["floor_number"]) != _floor_number
		or typeof(ticket["cost_kind"]) != TYPE_STRING
		or str(ticket["cost_kind"]) != "gold"
		or typeof(ticket["price"]) != TYPE_INT
		or int(ticket["price"]) <= 0
		or typeof(ticket["heal_amount"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(ticket["heal_amount"]))
		or float(ticket["heal_amount"]) <= 0.0
		or not ticket["reward_plan"] is Dictionary
		or (ticket["reward_plan"] as Dictionary).is_empty()
		or typeof(ticket["fingerprint"]) != TYPE_STRING
	):
		return false
	var unsigned := ticket.duplicate(true)
	unsigned.erase("fingerprint")
	return str(ticket["fingerprint"]) == _digest(unsigned)


func _valid_receipt(receipt: Dictionary) -> bool:
	if not _has_exact_fields(receipt, RECEIPT_FIELDS):
		return false
	if (
		typeof(receipt["schema_id"]) != TYPE_STRING
		or str(receipt["schema_id"]) != RECEIPT_SCHEMA_ID
		or typeof(receipt["owner_instance_id"]) != TYPE_INT
		or int(receipt["owner_instance_id"]) != get_instance_id()
		or typeof(receipt["transaction_id"]) != TYPE_STRING
		or not _valid_transaction_id(str(receipt["transaction_id"]))
		or typeof(receipt["service_id"]) != TYPE_STRING
		or str(receipt["service_id"]) != "heal"
		or typeof(receipt["target_id"]) != TYPE_STRING
		or str(receipt["target_id"]) != "player"
		or typeof(receipt["cost_kind"]) != TYPE_STRING
		or str(receipt["cost_kind"]) != "gold"
		or typeof(receipt["price"]) != TYPE_INT
		or int(receipt["price"]) <= 0
		or typeof(receipt["heal_amount"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(receipt["heal_amount"]))
		or float(receipt["heal_amount"]) <= 0.0
		or typeof(receipt["ticket_fingerprint"]) != TYPE_STRING
		or str(receipt["ticket_fingerprint"]).is_empty()
		or not receipt["reward_receipt"] is Dictionary
		or (receipt["reward_receipt"] as Dictionary).is_empty()
		or not receipt["before_snapshot"] is Dictionary
		or not receipt["after_snapshot"] is Dictionary
		or not can_restore_snapshot(receipt["before_snapshot"] as Dictionary)
		or not can_restore_snapshot(receipt["after_snapshot"] as Dictionary)
		or not (receipt["after_snapshot"] as Dictionary)["completed_transaction_ids"].has(
			str(receipt["transaction_id"])
		)
		or typeof(receipt["fingerprint"]) != TYPE_STRING
	):
		return false
	var unsigned := receipt.duplicate(true)
	unsigned.erase("fingerprint")
	return str(receipt["fingerprint"]) == _digest(unsigned)


func _valid_player(player: Object) -> bool:
	return (
		player != null
		and is_instance_valid(player)
		and player.has_method("reward_effect_snapshot")
		and player.has_method("restore_reward_effect_snapshot")
		and player.has_method("reward_effect_apply_operation")
	)


func _valid_reward_runtime(reward_runtime: Object) -> bool:
	return (
		reward_runtime != null
		and is_instance_valid(reward_runtime)
		and reward_runtime.has_method("prepare")
		and reward_runtime.has_method("commit")
		and reward_runtime.has_method("rollback")
	)


func _valid_transaction_id(value: String) -> bool:
	var expression := RegEx.new()
	return expression.compile(TRANSACTION_ID_PATTERN) == OK and expression.search(value) != null


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _digest(value: Variant) -> String:
	return var_to_bytes(_canonicalize(value)).hex_encode().sha256_text()


func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source := value as Dictionary
		var keys: Array[String] = []
		var source_keys: Dictionary = {}
		for key_value: Variant in source.keys():
			var key := str(key_value)
			keys.append(key)
			source_keys[key] = key_value
		keys.sort()
		var normalized: Dictionary = {}
		for key: String in keys:
			normalized[key] = _canonicalize(source[source_keys[key]])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for entry: Variant in value as Array:
			normalized_array.append(_canonicalize(entry))
		return normalized_array
	if typeof(value) == TYPE_STRING_NAME:
		return str(value)
	return value


func _success(context: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": &"OK", "context": context.duplicate(true)}
	for key_value: Variant in context.keys():
		var value: Variant = context[key_value]
		result[str(key_value)] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
