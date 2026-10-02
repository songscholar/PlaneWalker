class_name MerchantWeaponUpgradeAuthority
extends RefCounted

const MerchantDefinitionScript := preload("res://scripts/dungeon/merchant_definition.gd")
const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")
const ShopPriceServiceScript := preload("res://scripts/economy/shop_price_service.gd")

const SNAPSHOT_SCHEMA_ID := "planewalker.merchant_weapon_upgrade_authority"
const SNAPSHOT_SCHEMA_VERSION := 1
const TICKET_SCHEMA_ID := "merchant_weapon_upgrade_ticket_v1"
const RECEIPT_SCHEMA_ID := "merchant_weapon_upgrade_receipt_v1"
const SERVICE_ID := "weapon_upgrade"
const COST_KIND := "gold"
const CAPABILITY := "weapon.damage"
const LEVEL_MULTIPLIER := 1.10
const MAX_LEVEL := 3
const TRANSACTION_ID_PATTERN := "^[a-z0-9][a-z0-9_:-]{0,95}$"
const WEAPON_IDS: Array[String] = ["sword", "bow", "gun", "staff", "gauntlets"]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"merchant_id",
	"profile_id",
	"floor_number",
	"weapon_id",
	"level",
	"completed_transaction_ids",
]
const TICKET_FIELDS: Array[String] = [
	"schema_id",
	"owner_instance_id",
	"transaction_id",
	"service_id",
	"merchant_id",
	"profile_id",
	"floor_number",
	"weapon_id",
	"cost_kind",
	"price",
	"capability",
	"value",
	"current_level",
	"next_level",
	"player_snapshot",
	"fingerprint",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_id",
	"owner_instance_id",
	"transaction_id",
	"service_id",
	"weapon_id",
	"cost_kind",
	"price",
	"capability",
	"value",
	"previous_level",
	"level",
	"ticket_fingerprint",
	"before_player_snapshot",
	"after_player_snapshot",
	"before_authority_snapshot",
	"after_authority_snapshot",
	"fingerprint",
]

var _configured: bool = false
var _merchant: Dictionary = {}
var _profile: Dictionary = {}
var _floor_number: int = 0
var _weapon_id: String = ""
var _level: int = 0
var _player: Object
var _completed_transaction_ids: Dictionary = {}
var _pending_tickets: Dictionary = {}


func configure(
	merchant: Dictionary,
	profile: Dictionary,
	floor_number: int,
	player: Object
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
	if not (normalized_merchant["services"] as Array).has(SERVICE_ID):
		return _failure(&"SERVICE_NOT_OFFERED", {"service_id": SERVICE_ID})
	if not (normalized_merchant["accepted_costs"] as Array).has(COST_KIND):
		return _failure(&"COST_NOT_ACCEPTED", {"cost_kind": COST_KIND})
	if not _valid_player(player):
		return _failure(&"PLAYER_INVALID")
	var player_snapshot_result := _read_player_snapshot(player)
	if not bool(player_snapshot_result.get("ok", false)):
		return player_snapshot_result
	var player_snapshot := player_snapshot_result["snapshot"] as Dictionary
	var weapon_id := _snapshot_weapon_id(player_snapshot)
	if weapon_id.is_empty():
		return _failure(&"PLAYER_SNAPSHOT_INVALID", {"field": "weapon_id"})

	_merchant = normalized_merchant.duplicate(true)
	_profile = normalized_profile.duplicate(true)
	_floor_number = floor_number
	_weapon_id = weapon_id
	_level = 0
	_player = player
	_completed_transaction_ids.clear()
	_pending_tickets.clear()
	_configured = true
	return _success({"snapshot": snapshot()})


func prepare(transaction_id: String) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _valid_transaction_id(transaction_id):
		return _failure(&"TRANSACTION_INVALID", {"transaction_id": transaction_id})
	if _completed_transaction_ids.has(transaction_id) or _pending_tickets.has(transaction_id):
		return _failure(&"DUPLICATE_TRANSACTION", {"transaction_id": transaction_id})
	if _level >= MAX_LEVEL:
		return _failure(&"UPGRADE_CAP_REACHED", {"level": _level, "max_level": MAX_LEVEL})
	var player_snapshot_result := _read_player_snapshot(_player)
	if not bool(player_snapshot_result.get("ok", false)):
		return player_snapshot_result
	var player_snapshot := player_snapshot_result["snapshot"] as Dictionary
	if _snapshot_weapon_id(player_snapshot) != _weapon_id:
		return _failure(&"WEAPON_STALE", {
			"expected_weapon_id": _weapon_id,
			"actual_weapon_id": _snapshot_weapon_id(player_snapshot),
		})
	var price_result: Dictionary = ShopPriceServiceScript.new().service_price(
		_profile.duplicate(true),
		StringName(SERVICE_ID),
		_floor_number
	)
	if not bool(price_result.get("ok", false)):
		return _failure(&"PRICE_UNAVAILABLE", {"cause": price_result.duplicate(true)})

	var unsigned_ticket := {
		"schema_id": TICKET_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"service_id": SERVICE_ID,
		"merchant_id": str(_merchant["id"]),
		"profile_id": str(_profile["id"]),
		"floor_number": _floor_number,
		"weapon_id": _weapon_id,
		"cost_kind": COST_KIND,
		"price": int(price_result["price"]),
		"capability": CAPABILITY,
		"value": LEVEL_MULTIPLIER,
		"current_level": _level,
		"next_level": _level + 1,
		"player_snapshot": player_snapshot.duplicate(true),
	}
	var ticket := unsigned_ticket.duplicate(true)
	ticket["fingerprint"] = _digest(unsigned_ticket)
	_pending_tickets[transaction_id] = ticket.duplicate(true)
	return _success({"ticket": ticket.duplicate(true)})


func commit(ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _valid_ticket(ticket):
		return _failure(&"TICKET_INVALID")
	var transaction_id := str(ticket["transaction_id"])
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"DUPLICATE_TRANSACTION", {"transaction_id": transaction_id})
	if not _pending_tickets.has(transaction_id) or _pending_tickets[transaction_id] != ticket:
		return _failure(&"TICKET_STALE")
	if int(ticket["current_level"]) != _level or int(ticket["next_level"]) != _level + 1:
		return _failure(&"TICKET_STALE")
	var current_player_result := _read_player_snapshot(_player)
	if not bool(current_player_result.get("ok", false)):
		return current_player_result
	var current_player := current_player_result["snapshot"] as Dictionary
	if _snapshot_weapon_id(current_player) != _weapon_id:
		return _failure(&"WEAPON_STALE", {
			"expected_weapon_id": _weapon_id,
			"actual_weapon_id": _snapshot_weapon_id(current_player),
		})
	if current_player != ticket["player_snapshot"]:
		return _failure(&"PLAYER_STATE_STALE")

	var before_player := current_player.duplicate(true)
	var before_authority := snapshot()
	var apply_result: Variant = _player.call(
		"apply_weapon_capability_effect",
		StringName(CAPABILITY),
		LEVEL_MULTIPLIER
	)
	if typeof(apply_result) != TYPE_BOOL or not bool(apply_result):
		if not bool(_player.call("restore_weapon_upgrade_snapshot", before_player.duplicate(true))):
			return _failure(&"INTEGRITY_FAILURE", {"reason": "player_restore_after_apply_failure"})
		return _failure(&"PLAYER_APPLY_FAILED")
	var after_player_result := _read_player_snapshot(_player)
	if not bool(after_player_result.get("ok", false)):
		if not bool(_player.call("restore_weapon_upgrade_snapshot", before_player.duplicate(true))):
			return _failure(&"INTEGRITY_FAILURE", {"reason": "player_restore_after_snapshot_failure"})
		return _failure(&"PLAYER_APPLY_FAILED", {"reason": "invalid_after_snapshot"})
	var after_player := after_player_result["snapshot"] as Dictionary
	if _snapshot_weapon_id(after_player) != _weapon_id or after_player == before_player:
		if not bool(_player.call("restore_weapon_upgrade_snapshot", before_player.duplicate(true))):
			return _failure(&"INTEGRITY_FAILURE", {"reason": "player_restore_after_invalid_effect"})
		return _failure(&"PLAYER_APPLY_FAILED", {"reason": "effect_not_observed"})

	_level += 1
	_completed_transaction_ids[transaction_id] = true
	_pending_tickets.erase(transaction_id)
	var after_authority := snapshot()
	var unsigned_receipt := {
		"schema_id": RECEIPT_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"service_id": SERVICE_ID,
		"weapon_id": _weapon_id,
		"cost_kind": COST_KIND,
		"price": int(ticket["price"]),
		"capability": CAPABILITY,
		"value": LEVEL_MULTIPLIER,
		"previous_level": int(ticket["current_level"]),
		"level": _level,
		"ticket_fingerprint": str(ticket["fingerprint"]),
		"before_player_snapshot": before_player.duplicate(true),
		"after_player_snapshot": after_player.duplicate(true),
		"before_authority_snapshot": before_authority.duplicate(true),
		"after_authority_snapshot": after_authority.duplicate(true),
	}
	var receipt := unsigned_receipt.duplicate(true)
	receipt["fingerprint"] = _digest(unsigned_receipt)
	return _success({"receipt": receipt.duplicate(true)})


func rollback(receipt_or_ticket: Dictionary) -> Dictionary:
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
	if snapshot() != receipt_or_ticket["after_authority_snapshot"]:
		return _failure(&"RECEIPT_STALE")
	var current_player_result := _read_player_snapshot(_player)
	if not bool(current_player_result.get("ok", false)):
		return current_player_result
	if current_player_result["snapshot"] != receipt_or_ticket["after_player_snapshot"]:
		return _failure(&"RECEIPT_STALE")
	var before_player := receipt_or_ticket["before_player_snapshot"] as Dictionary
	var after_player := receipt_or_ticket["after_player_snapshot"] as Dictionary
	if not bool(_player.call("restore_weapon_upgrade_snapshot", before_player.duplicate(true))):
		return _failure(&"PLAYER_RESTORE_FAILED")
	var before_authority := receipt_or_ticket["before_authority_snapshot"] as Dictionary
	if not restore_snapshot(before_authority):
		if not bool(_player.call("restore_weapon_upgrade_snapshot", after_player.duplicate(true))):
			return _failure(&"INTEGRITY_FAILURE", {"reason": "rollback_double_restore_failure"})
		return _failure(&"INTEGRITY_FAILURE", {"reason": "authority_restore_failure"})
	return _success({"transaction_id": transaction_id, "rolled_back": "committed"})


func prepare_upgrade(transaction_id: String) -> Dictionary:
	return prepare(transaction_id)


func commit_upgrade(ticket: Dictionary) -> Dictionary:
	return commit(ticket)


func rollback_upgrade(receipt_or_ticket: Dictionary) -> Dictionary:
	return rollback(receipt_or_ticket)


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
		"weapon_id": _weapon_id,
		"level": _level,
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
		or typeof(value["weapon_id"]) != TYPE_STRING
		or str(value["weapon_id"]) != _weapon_id
		or typeof(value["level"]) != TYPE_INT
		or int(value["level"]) < 0
		or int(value["level"]) > MAX_LEVEL
		or not value["completed_transaction_ids"] is Array
	):
		return false
	var player_snapshot_result := _read_player_snapshot(_player)
	if (
		not bool(player_snapshot_result.get("ok", false))
		or _snapshot_weapon_id(player_snapshot_result["snapshot"] as Dictionary) != _weapon_id
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
	return normalized == sorted and normalized.size() == int(value["level"])


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	var restored: Dictionary = {}
	for transaction_id_value: Variant in value["completed_transaction_ids"] as Array:
		restored[str(transaction_id_value)] = true
	_level = int(value["level"])
	_completed_transaction_ids = restored
	_pending_tickets.clear()
	return snapshot() == value


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
		or str(ticket["service_id"]) != SERVICE_ID
		or typeof(ticket["merchant_id"]) != TYPE_STRING
		or str(ticket["merchant_id"]) != str(_merchant["id"])
		or typeof(ticket["profile_id"]) != TYPE_STRING
		or str(ticket["profile_id"]) != str(_profile["id"])
		or typeof(ticket["floor_number"]) != TYPE_INT
		or int(ticket["floor_number"]) != _floor_number
		or typeof(ticket["weapon_id"]) != TYPE_STRING
		or str(ticket["weapon_id"]) != _weapon_id
		or typeof(ticket["cost_kind"]) != TYPE_STRING
		or str(ticket["cost_kind"]) != COST_KIND
		or typeof(ticket["price"]) != TYPE_INT
		or int(ticket["price"]) <= 0
		or typeof(ticket["capability"]) != TYPE_STRING
		or str(ticket["capability"]) != CAPABILITY
		or typeof(ticket["value"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_equal_approx(float(ticket["value"]), LEVEL_MULTIPLIER)
		or typeof(ticket["current_level"]) != TYPE_INT
		or int(ticket["current_level"]) < 0
		or int(ticket["current_level"]) >= MAX_LEVEL
		or typeof(ticket["next_level"]) != TYPE_INT
		or int(ticket["next_level"]) != int(ticket["current_level"]) + 1
		or not ticket["player_snapshot"] is Dictionary
		or _snapshot_weapon_id(ticket["player_snapshot"] as Dictionary) != _weapon_id
		or not bool(_player.call(
			"can_restore_weapon_upgrade_snapshot",
			(ticket["player_snapshot"] as Dictionary).duplicate(true)
		))
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
		or str(receipt["service_id"]) != SERVICE_ID
		or typeof(receipt["weapon_id"]) != TYPE_STRING
		or str(receipt["weapon_id"]) != _weapon_id
		or typeof(receipt["cost_kind"]) != TYPE_STRING
		or str(receipt["cost_kind"]) != COST_KIND
		or typeof(receipt["price"]) != TYPE_INT
		or int(receipt["price"]) <= 0
		or typeof(receipt["capability"]) != TYPE_STRING
		or str(receipt["capability"]) != CAPABILITY
		or typeof(receipt["value"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_equal_approx(float(receipt["value"]), LEVEL_MULTIPLIER)
		or typeof(receipt["previous_level"]) != TYPE_INT
		or typeof(receipt["level"]) != TYPE_INT
		or int(receipt["level"]) != int(receipt["previous_level"]) + 1
		or int(receipt["level"]) < 1
		or int(receipt["level"]) > MAX_LEVEL
		or typeof(receipt["ticket_fingerprint"]) != TYPE_STRING
		or str(receipt["ticket_fingerprint"]).is_empty()
		or not _valid_participant_snapshot(receipt["before_player_snapshot"])
		or not _valid_participant_snapshot(receipt["after_player_snapshot"])
		or not receipt["before_authority_snapshot"] is Dictionary
		or not receipt["after_authority_snapshot"] is Dictionary
		or not can_restore_snapshot(receipt["before_authority_snapshot"] as Dictionary)
		or not can_restore_snapshot(receipt["after_authority_snapshot"] as Dictionary)
		or int((receipt["before_authority_snapshot"] as Dictionary)["level"]) != int(receipt["previous_level"])
		or int((receipt["after_authority_snapshot"] as Dictionary)["level"]) != int(receipt["level"])
		or not (receipt["after_authority_snapshot"] as Dictionary)["completed_transaction_ids"].has(
			str(receipt["transaction_id"])
		)
		or typeof(receipt["fingerprint"]) != TYPE_STRING
	):
		return false
	var unsigned := receipt.duplicate(true)
	unsigned.erase("fingerprint")
	return str(receipt["fingerprint"]) == _digest(unsigned)


func _valid_participant_snapshot(value: Variant) -> bool:
	return (
		value is Dictionary
		and _snapshot_weapon_id(value as Dictionary) == _weapon_id
		and bool(_player.call(
			"can_restore_weapon_upgrade_snapshot",
			(value as Dictionary).duplicate(true)
		))
	)


func _valid_player(player: Object) -> bool:
	return (
		player != null
		and is_instance_valid(player)
		and player.has_method("weapon_upgrade_snapshot")
		and player.has_method("can_restore_weapon_upgrade_snapshot")
		and player.has_method("restore_weapon_upgrade_snapshot")
		and player.has_method("apply_weapon_capability_effect")
	)


func _read_player_snapshot(player: Object) -> Dictionary:
	var snapshot_value: Variant = player.call("weapon_upgrade_snapshot")
	if not snapshot_value is Dictionary:
		return _failure(&"PLAYER_SNAPSHOT_INVALID")
	var player_snapshot := (snapshot_value as Dictionary).duplicate(true)
	if (
		player_snapshot.is_empty()
		or _snapshot_weapon_id(player_snapshot).is_empty()
		or not bool(player.call(
			"can_restore_weapon_upgrade_snapshot",
			player_snapshot.duplicate(true)
		))
	):
		return _failure(&"PLAYER_SNAPSHOT_INVALID")
	return _success({"snapshot": player_snapshot})


func _snapshot_weapon_id(player_snapshot: Dictionary) -> String:
	var weapon_id_value: Variant = player_snapshot.get("weapon_id")
	if typeof(weapon_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return ""
	var weapon_id := str(weapon_id_value)
	return weapon_id if WEAPON_IDS.has(weapon_id) else ""


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
