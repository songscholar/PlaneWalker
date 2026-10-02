class_name MerchantServiceRouter
extends RefCounted

const ShopPriceServiceScript := preload("res://scripts/economy/shop_price_service.gd")

const SNAPSHOT_SCHEMA_ID := "planewalker.merchant_service_router"
const SNAPSHOT_SCHEMA_VERSION := 1
const TICKET_SCHEMA_ID := "merchant_service_router_ticket_v1"
const RECEIPT_SCHEMA_ID := "merchant_service_router_receipt_v1"
const AUTHORITY_KEYS: Array[String] = [
	"heal", "health_trade", "reward_mutation", "visibility", "weapon_upgrade",
]
const SERVICE_AUTHORITY_KEYS := {
	"heal": "heal",
	"weapon_upgrade": "weapon_upgrade",
	"health_trade": "health_trade",
	"cleanse_curse": "reward_mutation",
	"sell_reward": "reward_mutation",
	"route_reveal": "visibility",
}
const GOLD_SERVICES: Array[String] = [
	"heal", "weapon_upgrade", "cleanse_curse", "route_reveal",
]
const TRANSACTION_ID_PATTERN := "^[a-z0-9][a-z0-9_.:-]{0,95}$"

var _configured := false
var _merchant: Dictionary = {}
var _profile: Dictionary = {}
var _floor_number := 0
var _inventory: Object
var _floor_plan: Dictionary = {}
var _authorities: Dictionary = {}
var _completed_transaction_ids: Dictionary = {}
var _pending_tickets: Dictionary = {}


func configure(
	merchant: Dictionary,
	profile: Dictionary,
	floor_number: int,
	inventory: Object,
	floor_plan: Dictionary,
	authorities: Dictionary
) -> Dictionary:
	var merchant_id := str(merchant.get("id", ""))
	var services_value: Variant = merchant.get("services")
	if merchant_id.is_empty() or not services_value is Array or floor_number < 1 or floor_number > 5:
		return _failure(&"CONFIGURATION_INVALID")
	if inventory == null or not is_instance_valid(inventory) or not inventory.has_method("snapshot"):
		return _failure(&"INVENTORY_INVALID")
	var services: Array[String] = []
	for service_value: Variant in services_value:
		var service := str(service_value)
		if SERVICE_AUTHORITY_KEYS.has(service) and not services.has(service):
			services.append(service)
	for service: String in services:
		var authority_key := str(SERVICE_AUTHORITY_KEYS[service])
		if not authorities.has(authority_key) or not _valid_authority(authority_key, authorities[authority_key]):
			return _failure(&"AUTHORITY_INVALID", {
				"service_id": service,
				"authority": authority_key,
			})
	_merchant = merchant.duplicate(true)
	_profile = profile.duplicate(true)
	_floor_number = floor_number
	_inventory = inventory
	_floor_plan = floor_plan.duplicate(true)
	_authorities.clear()
	for authority_key: String in AUTHORITY_KEYS:
		if authorities.has(authority_key):
			_authorities[authority_key] = authorities[authority_key]
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
	if not _valid_transaction_id(transaction_id) or str(service_id).is_empty():
		return _failure(&"INVALID_ARGUMENT")
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"ALREADY_CONSUMED", {"transaction_id": transaction_id})
	if _pending_tickets.has(transaction_id):
		return _failure(&"TRANSACTION_PENDING", {"transaction_id": transaction_id})
	var service := str(service_id)
	if not SERVICE_AUTHORITY_KEYS.has(service) or not (_merchant.get("services", []) as Array).has(service):
		return _failure(&"SERVICE_NOT_OFFERED", {"service_id": service})
	var authority_key := str(SERVICE_AUTHORITY_KEYS[service])
	var authority: Object = _authorities.get(authority_key)
	var delegated := _prepare_delegate(
		authority_key, authority, transaction_id, service, target_id
	)
	if not bool(delegated.get("ok", false)):
		return _forward_failure(delegated, &"SERVICE_PREPARE_FAILED")
	var delegate_ticket := _dictionary(delegated.get("ticket"))
	if delegate_ticket.is_empty():
		return _failure(&"SERVICE_TICKET_INVALID")
	var cost := _resolve_cost(service, delegate_ticket)
	if not bool(cost.get("ok", false)):
		_rollback_delegate(authority_key, authority, delegate_ticket)
		return cost
	var unsigned := {
		"schema_id": TICKET_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"service_id": service,
		"target_id": target_id,
		"authority_key": authority_key,
		"cost_kind": str(cost["cost_kind"]),
		"amount": int(cost["amount"]),
		"price": int(cost["amount"]),
		"economy_delta": int(cost["economy_delta"]),
		"offer_id": str(delegate_ticket.get("offer_id", "")),
		"reward_id": str(delegate_ticket.get("reward_id", target_id if service in ["cleanse_curse", "sell_reward"] else "")),
		"delegate_ticket": delegate_ticket.duplicate(true),
	}
	var ticket := unsigned.duplicate(true)
	ticket["fingerprint"] = _digest(unsigned)
	_pending_tickets[transaction_id] = ticket.duplicate(true)
	return _success({"ticket": ticket.duplicate(true)})


func commit_service(ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _valid_ticket(ticket):
		return _failure(&"TICKET_INVALID")
	var transaction_id := str(ticket["transaction_id"])
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"ALREADY_CONSUMED")
	if not _pending_tickets.has(transaction_id) or _pending_tickets[transaction_id] != ticket:
		return _failure(&"TICKET_STALE")
	var authority_key := str(ticket["authority_key"])
	var authority: Object = _authorities.get(authority_key)
	var committed := _commit_delegate(
		authority_key, authority, ticket["delegate_ticket"] as Dictionary
	)
	if not bool(committed.get("ok", false)):
		return _forward_failure(committed, &"SERVICE_COMMIT_FAILED")
	var delegate_receipt := _dictionary(committed.get("receipt"))
	if delegate_receipt.is_empty():
		return _failure(&"SERVICE_RECEIPT_INVALID")
	_completed_transaction_ids[transaction_id] = true
	_pending_tickets.erase(transaction_id)
	var unsigned := {
		"schema_id": RECEIPT_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"service_id": str(ticket["service_id"]),
		"target_id": str(ticket["target_id"]),
		"authority_key": authority_key,
		"cost_kind": str(ticket["cost_kind"]),
		"amount": int(ticket["amount"]),
		"price": int(ticket["price"]),
		"economy_delta": int(ticket["economy_delta"]),
		"offer_id": str(ticket["offer_id"]),
		"reward_id": str(ticket["reward_id"]),
		"ticket_fingerprint": str(ticket["fingerprint"]),
		"delegate_receipt": delegate_receipt.duplicate(true),
	}
	var receipt := unsigned.duplicate(true)
	receipt["fingerprint"] = _digest(unsigned)
	return _success({"receipt": receipt.duplicate(true)})


func rollback_service(receipt_or_ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if _valid_ticket(receipt_or_ticket):
		var pending_id := str(receipt_or_ticket["transaction_id"])
		if not _pending_tickets.has(pending_id) or _pending_tickets[pending_id] != receipt_or_ticket:
			return _failure(&"TICKET_STALE")
		var authority_key := str(receipt_or_ticket["authority_key"])
		var rolled_back := _rollback_delegate(
			authority_key,
			_authorities.get(authority_key),
			receipt_or_ticket["delegate_ticket"] as Dictionary
		)
		if not bool(rolled_back.get("ok", false)):
			return _forward_failure(rolled_back, &"SERVICE_ROLLBACK_FAILED")
		_pending_tickets.erase(pending_id)
		return _success({"transaction_id": pending_id, "rolled_back": "pending"})
	if not _valid_receipt(receipt_or_ticket):
		return _failure(&"RECEIPT_INVALID")
	var transaction_id := str(receipt_or_ticket["transaction_id"])
	if not _completed_transaction_ids.has(transaction_id):
		return _failure(&"RECEIPT_STALE")
	var authority_key := str(receipt_or_ticket["authority_key"])
	var rolled_back := _rollback_delegate(
		authority_key,
		_authorities.get(authority_key),
		receipt_or_ticket["delegate_receipt"] as Dictionary
	)
	if not bool(rolled_back.get("ok", false)):
		return _forward_failure(rolled_back, &"SERVICE_ROLLBACK_FAILED")
	_completed_transaction_ids.erase(transaction_id)
	return _success({"transaction_id": transaction_id, "rolled_back": "committed"})


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	var completed: Array[String] = []
	for transaction_id_value: Variant in _completed_transaction_ids.keys():
		completed.append(str(transaction_id_value))
	completed.sort()
	var authority_snapshots: Dictionary = {}
	for authority_key: String in AUTHORITY_KEYS:
		if _authorities.has(authority_key):
			authority_snapshots[authority_key] = _dictionary(
				(_authorities[authority_key] as Object).call("snapshot")
			)
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"merchant_id": str(_merchant.get("id", "")),
		"completed_transaction_ids": completed,
		"authorities": authority_snapshots,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if not _configured or _sorted_keys(value) != [
		"authorities", "completed_transaction_ids", "merchant_id", "schema_id", "schema_version",
	]:
		return false
	if (
		typeof(value.get("schema_id")) != TYPE_STRING
		or str(value["schema_id"]) != SNAPSHOT_SCHEMA_ID
		or typeof(value.get("schema_version")) != TYPE_INT
		or int(value["schema_version"]) != SNAPSHOT_SCHEMA_VERSION
		or typeof(value.get("merchant_id")) != TYPE_STRING
		or str(value["merchant_id"]) != str(_merchant.get("id", ""))
		or not value.get("completed_transaction_ids") is Array
		or not value.get("authorities") is Dictionary
	):
		return false
	var ids: Array[String] = []
	for id_value: Variant in value["completed_transaction_ids"] as Array:
		if typeof(id_value) != TYPE_STRING or not _valid_transaction_id(str(id_value)) or ids.has(str(id_value)):
			return false
		ids.append(str(id_value))
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	if ids != sorted_ids:
		return false
	var snapshots := value["authorities"] as Dictionary
	if _sorted_keys(snapshots) != _sorted_keys(_authorities):
		return false
	for authority_key: String in _sorted_keys(_authorities):
		var authority: Object = _authorities[authority_key]
		if (
			not snapshots[authority_key] is Dictionary
			or not bool(authority.call(
				"can_restore_snapshot", (snapshots[authority_key] as Dictionary).duplicate(true)
			))
		):
			return false
	return true


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value) or not _pending_tickets.is_empty():
		return false
	var before := snapshot()
	var snapshots := value["authorities"] as Dictionary
	var restored_keys: Array[String] = []
	for authority_key: String in _sorted_keys(_authorities):
		var authority: Object = _authorities[authority_key]
		if not bool(authority.call(
			"restore_snapshot", (snapshots[authority_key] as Dictionary).duplicate(true)
		)):
			_restore_authority_snapshots(before["authorities"] as Dictionary, restored_keys)
			return false
		restored_keys.append(authority_key)
	_completed_transaction_ids.clear()
	for transaction_id_value: Variant in value["completed_transaction_ids"] as Array:
		_completed_transaction_ids[str(transaction_id_value)] = true
	_pending_tickets.clear()
	return snapshot() == value


func visibility_snapshot() -> Dictionary:
	if not _configured or not _authorities.has("visibility"):
		return {}
	var authority: Object = _authorities["visibility"]
	return _dictionary(authority.call("floor_plan_snapshot"))


func authority(authority_key: String) -> Object:
	return _authorities.get(authority_key) as Object if _authorities.has(authority_key) else null


func replace_authority(authority_key: String, value: Object) -> bool:
	if (
		not _configured
		or not _pending_tickets.is_empty()
		or not _authorities.has(authority_key)
		or not _valid_authority(authority_key, value)
	):
		return false
	_authorities[authority_key] = value
	return true


func _prepare_delegate(
	authority_key: String,
	authority: Object,
	transaction_id: String,
	service_id: String,
	target_id: String
) -> Dictionary:
	match authority_key:
		"heal":
			return _dictionary(authority.call(
				"prepare_service", transaction_id, StringName(service_id), target_id
			))
		"weapon_upgrade":
			return _dictionary(authority.call("prepare_upgrade", transaction_id))
		"health_trade":
			var inventory_snapshot := _dictionary(_inventory.call("snapshot"))
			return _dictionary(authority.call(
				"prepare_trade",
				transaction_id,
				target_id,
				int(inventory_snapshot.get("revision", -1))
			))
		"visibility":
			return _dictionary(authority.call(
				"prepare_reveal", transaction_id, authority.call("floor_plan_snapshot")
			))
		"reward_mutation":
			return _dictionary(authority.call(
				"prepare_remove",
				transaction_id,
				target_id,
				["curse"] if service_id == "cleanse_curse" else ["item", "blessing"]
			))
	return _failure(&"SERVICE_UNSUPPORTED")


func _resolve_cost(service_id: String, delegate_ticket: Dictionary) -> Dictionary:
	if service_id in ["heal", "weapon_upgrade"]:
		if (
			str(delegate_ticket.get("cost_kind", "")) != "gold"
			or typeof(delegate_ticket.get("price")) != TYPE_INT
			or int(delegate_ticket["price"]) <= 0
		):
			return _failure(&"SERVICE_TICKET_INVALID")
		return _success({
			"cost_kind": "gold",
			"amount": int(delegate_ticket["price"]),
			"economy_delta": -int(delegate_ticket["price"]),
		})
	if service_id == "health_trade":
		if (
			str(delegate_ticket.get("cost_kind", "")) != "health"
			or typeof(delegate_ticket.get("health_cost")) != TYPE_INT
			or int(delegate_ticket["health_cost"]) <= 0
		):
			return _failure(&"SERVICE_TICKET_INVALID")
		return _success({
			"cost_kind": "health",
			"amount": int(delegate_ticket["health_cost"]),
			"economy_delta": 0,
		})
	if service_id in ["cleanse_curse", "route_reveal"]:
		var priced: Dictionary = ShopPriceServiceScript.new().service_price(
			_profile.duplicate(true), StringName(service_id), _floor_number
		)
		if not bool(priced.get("ok", false)):
			return _failure(&"PRICE_UNAVAILABLE", {"cause": priced})
		return _success({
			"cost_kind": "gold",
			"amount": int(priced["price"]),
			"economy_delta": -int(priced["price"]),
		})
	if service_id == "sell_reward":
		var definition := _definition_from_ticket(delegate_ticket)
		if definition.is_empty():
			return _failure(&"SERVICE_TICKET_INVALID")
		var sell_price: Dictionary = ShopPriceServiceScript.new().sell_price(
			_profile.duplicate(true), definition
		)
		if not bool(sell_price.get("ok", false)):
			return _failure(&"PRICE_UNAVAILABLE", {"cause": sell_price})
		return _success({
			"cost_kind": "reward",
			"amount": int(sell_price["price"]),
			"economy_delta": int(sell_price["price"]),
		})
	return _failure(&"SERVICE_UNSUPPORTED")


func _definition_from_ticket(ticket: Dictionary) -> Dictionary:
	var reward_id := str(ticket.get("reward_id", ""))
	for definition_value: Variant in ticket.get("before_ledger", []):
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == reward_id:
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _commit_delegate(authority_key: String, authority: Object, ticket: Dictionary) -> Dictionary:
	match authority_key:
		"heal":
			return _dictionary(authority.call("commit_service", ticket.duplicate(true)))
		"weapon_upgrade":
			return _dictionary(authority.call("commit_upgrade", ticket.duplicate(true)))
		"health_trade":
			return _dictionary(authority.call("commit_trade", ticket.duplicate(true)))
		"visibility":
			return _dictionary(authority.call("commit_reveal", ticket.duplicate(true)))
		"reward_mutation":
			return _dictionary(authority.call("commit_remove", ticket.duplicate(true)))
	return _failure(&"SERVICE_UNSUPPORTED")


func _rollback_delegate(authority_key: String, authority: Object, value: Dictionary) -> Dictionary:
	match authority_key:
		"heal":
			return _dictionary(authority.call("rollback_service", value.duplicate(true)))
		"weapon_upgrade":
			return _dictionary(authority.call("rollback_upgrade", value.duplicate(true)))
		"health_trade":
			return _dictionary(authority.call("rollback_trade", value.duplicate(true)))
		"visibility":
			return _dictionary(authority.call("rollback_reveal", value.duplicate(true)))
		"reward_mutation":
			return _dictionary(authority.call("rollback_remove", value.duplicate(true)))
	return _failure(&"SERVICE_UNSUPPORTED")


func _valid_authority(authority_key: String, value: Variant) -> bool:
	if not value is Object or value == null or not is_instance_valid(value):
		return false
	var methods: Array[StringName] = [&"snapshot", &"can_restore_snapshot", &"restore_snapshot"]
	match authority_key:
		"heal":
			methods.append_array([&"prepare_service", &"commit_service", &"rollback_service"])
		"weapon_upgrade":
			methods.append_array([&"prepare_upgrade", &"commit_upgrade", &"rollback_upgrade"])
		"health_trade":
			methods.append_array([&"prepare_trade", &"commit_trade", &"rollback_trade"])
		"visibility":
			methods.append_array([&"prepare_reveal", &"commit_reveal", &"rollback_reveal", &"floor_plan_snapshot"])
		"reward_mutation":
			methods.append_array([&"prepare_remove", &"commit_remove", &"rollback_remove"])
		_:
			return false
	for method_name: StringName in methods:
		if not (value as Object).has_method(method_name):
			return false
	return true


func _valid_ticket(value: Dictionary) -> bool:
	if _sorted_keys(value) != [
		"amount", "authority_key", "cost_kind", "delegate_ticket", "economy_delta",
		"fingerprint", "offer_id", "owner_instance_id", "price", "reward_id",
		"schema_id", "service_id", "target_id", "transaction_id",
	]:
		return false
	if (
		str(value.get("schema_id", "")) != TICKET_SCHEMA_ID
		or int(value.get("owner_instance_id", -1)) != get_instance_id()
		or not _valid_transaction_id(str(value.get("transaction_id", "")))
		or not SERVICE_AUTHORITY_KEYS.has(str(value.get("service_id", "")))
		or str(value.get("authority_key", "")) != str(SERVICE_AUTHORITY_KEYS[str(value.get("service_id", ""))])
		or str(value.get("cost_kind", "")) not in ["gold", "health", "reward"]
		or typeof(value.get("amount")) != TYPE_INT
		or int(value["amount"]) <= 0
		or typeof(value.get("price")) != TYPE_INT
		or int(value["price"]) != int(value["amount"])
		or typeof(value.get("economy_delta")) != TYPE_INT
		or not value.get("delegate_ticket") is Dictionary
		or typeof(value.get("fingerprint")) != TYPE_STRING
	):
		return false
	var unsigned := value.duplicate(true)
	unsigned.erase("fingerprint")
	return str(value["fingerprint"]) == _digest(unsigned)


func _valid_receipt(value: Dictionary) -> bool:
	if _sorted_keys(value) != [
		"amount", "authority_key", "cost_kind", "delegate_receipt", "economy_delta",
		"fingerprint", "offer_id", "owner_instance_id", "price", "reward_id",
		"schema_id", "service_id", "target_id", "ticket_fingerprint", "transaction_id",
	]:
		return false
	if (
		str(value.get("schema_id", "")) != RECEIPT_SCHEMA_ID
		or int(value.get("owner_instance_id", -1)) != get_instance_id()
		or not _valid_transaction_id(str(value.get("transaction_id", "")))
		or not SERVICE_AUTHORITY_KEYS.has(str(value.get("service_id", "")))
		or str(value.get("authority_key", "")) != str(SERVICE_AUTHORITY_KEYS[str(value.get("service_id", ""))])
		or str(value.get("cost_kind", "")) not in ["gold", "health", "reward"]
		or typeof(value.get("amount")) != TYPE_INT
		or int(value["amount"]) <= 0
		or typeof(value.get("price")) != TYPE_INT
		or int(value["price"]) != int(value["amount"])
		or typeof(value.get("economy_delta")) != TYPE_INT
		or not value.get("delegate_receipt") is Dictionary
		or typeof(value.get("ticket_fingerprint")) != TYPE_STRING
		or typeof(value.get("fingerprint")) != TYPE_STRING
	):
		return false
	var unsigned := value.duplicate(true)
	unsigned.erase("fingerprint")
	return str(value["fingerprint"]) == _digest(unsigned)


func _restore_authority_snapshots(snapshots: Dictionary, keys: Array[String]) -> void:
	for authority_key: String in keys:
		if snapshots.has(authority_key):
			(_authorities[authority_key] as Object).call(
				"restore_snapshot", (snapshots[authority_key] as Dictionary).duplicate(true)
			)


func _valid_transaction_id(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(TRANSACTION_ID_PATTERN) == OK and regex.search(value) != null


func _sorted_keys(value: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key_value: Variant in value.keys():
		keys.append(str(key_value))
	keys.sort()
	return keys


func _dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _digest(value: Dictionary) -> String:
	return var_to_bytes(_canonicalize(value)).hex_encode().sha256_text()


func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source := value as Dictionary
		var keys := _sorted_keys(source)
		var normalized: Dictionary = {}
		for key: String in keys:
			normalized[key] = _canonicalize(source[key])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for entry: Variant in value as Array:
			normalized_array.append(_canonicalize(entry))
		return normalized_array
	return value


func _forward_failure(value: Dictionary, fallback: StringName) -> Dictionary:
	return _failure(
		StringName(str(value.get("code", fallback))),
		_dictionary(value.get("context", {}))
	)


func _success(values: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": &"OK"}
	for key: Variant in values:
		result[key] = values[key]
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
