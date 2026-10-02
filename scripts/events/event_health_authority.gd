class_name EventHealthAuthority
extends RefCounted

const SCHEMA_ID := "planewalker.event_health_authority"
const TICKET_SCHEMA_ID := "event_health_ticket_v1"
const RECEIPT_SCHEMA_ID := "event_health_receipt_v1"
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id", "schema_version", "current", "maximum",
	"completed_transaction_ids", "revision",
]
const TICKET_FIELDS: Array[String] = [
	"schema_id", "owner_instance_id", "transaction_id", "amount", "nonlethal",
	"expected_revision", "before", "after", "fingerprint",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_id", "owner_instance_id", "transaction_id", "ticket_fingerprint",
	"before", "after", "fingerprint",
]

var _configured := false
var _current := 0.0
var _maximum := 0.0
var _completed_transaction_ids: Array[String] = []
var _revision := 0
var _committed_rollback_receipt: Dictionary = {}
var _capability_secret := ""


func configure(current: float, maximum: float) -> bool:
	if not is_finite(current) or not is_finite(maximum) or maximum <= 0.0 or current < 0.0 or current > maximum:
		return false
	_current = current
	_maximum = maximum
	_completed_transaction_ids.clear()
	_revision = 0
	_committed_rollback_receipt.clear()
	_capability_secret = _new_capability_secret()
	_configured = true
	return true


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": 1,
		"current": _current,
		"maximum": _maximum,
		"completed_transaction_ids": _completed_transaction_ids.duplicate(),
		"revision": _revision,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	return _configured and not _normalize_snapshot(value).is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	var normalized := _normalize_snapshot(value)
	if normalized.is_empty():
		return false
	_apply_snapshot(normalized)
	_committed_rollback_receipt.clear()
	_capability_secret = _new_capability_secret()
	return snapshot() == normalized


func prepare_delta(
	transaction_id: String,
	amount: float,
	nonlethal: bool,
	expected_revision: int
) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _valid_id(transaction_id) or not is_finite(amount) or is_zero_approx(amount):
		return _failure(&"INVALID_ARGUMENT")
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"ALREADY_CONSUMED")
	if expected_revision != _revision:
		return _failure(&"STALE_REVISION", {"actual_revision": _revision})
	var target := minf(_maximum, _current + amount)
	if amount < 0.0 and nonlethal and target < 1.0:
		return _failure(&"NONLETHAL_VIOLATION")
	if target < 0.0:
		return _failure(&"HEALTH_UNDERFLOW")
	var before := snapshot()
	var after := before.duplicate(true)
	after["current"] = target
	(after["completed_transaction_ids"] as Array).append(transaction_id)
	(after["completed_transaction_ids"] as Array).sort()
	after["revision"] = _revision + 1
	var unsigned := {
		"schema_id": TICKET_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"amount": amount,
		"nonlethal": nonlethal,
		"expected_revision": expected_revision,
		"before": before,
		"after": after,
	}
	var ticket := unsigned.duplicate(true)
	ticket["fingerprint"] = _digest(unsigned)
	return _success({"ticket": ticket})


func commit_delta(ticket: Dictionary) -> Dictionary:
	if not _valid_ticket(ticket):
		return _failure(&"TICKET_INVALID")
	if _completed_transaction_ids.has(str(ticket["transaction_id"])):
		return _failure(&"ALREADY_CONSUMED")
	if snapshot() != ticket["before"]:
		return _failure(&"TRANSACTION_STALE")
	_apply_snapshot(ticket["after"] as Dictionary)
	var receipt := _receipt(ticket)
	_committed_rollback_receipt = receipt.duplicate(true)
	return _success({"receipt": receipt})


func rollback_delta(receipt: Dictionary) -> Dictionary:
	if not _valid_receipt(receipt) or receipt != _committed_rollback_receipt or snapshot() != receipt["after"]:
		return _failure(&"TRANSACTION_STALE")
	_apply_snapshot(receipt["before"] as Dictionary)
	_committed_rollback_receipt.clear()
	return _success({"transaction_id": str(receipt["transaction_id"]), "rolled_back": true})


func _normalize_snapshot(value: Dictionary) -> Dictionary:
	if not _exact_fields(value, SNAPSHOT_FIELDS):
		return {}
	var current_value: Variant = value.get("current")
	var maximum_value: Variant = value.get("maximum")
	if (
		str(value.get("schema_id", "")) != SCHEMA_ID
		or typeof(value.get("schema_version")) != TYPE_INT
		or int(value["schema_version"]) != 1
		or typeof(current_value) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(maximum_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(current_value))
		or not is_finite(float(maximum_value))
		or float(maximum_value) <= 0.0
		or float(current_value) < 0.0
		or float(current_value) > float(maximum_value)
		or not value.get("completed_transaction_ids") is Array
		or typeof(value.get("revision")) != TYPE_INT
		or int(value["revision"]) < 0
	):
		return {}
	if not is_equal_approx(float(maximum_value), _maximum):
		return {}
	var completed := _normalize_ids(value["completed_transaction_ids"] as Array)
	if completed.size() != int(value["revision"]):
		return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": 1,
		"current": float(current_value),
		"maximum": float(maximum_value),
		"completed_transaction_ids": completed,
		"revision": int(value["revision"]),
	}


func _receipt(ticket: Dictionary) -> Dictionary:
	var unsigned := {
		"schema_id": RECEIPT_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": str(ticket["transaction_id"]),
		"ticket_fingerprint": str(ticket["fingerprint"]),
		"before": (ticket["before"] as Dictionary).duplicate(true),
		"after": (ticket["after"] as Dictionary).duplicate(true),
	}
	var receipt := unsigned.duplicate(true)
	receipt["fingerprint"] = _digest(unsigned)
	return receipt


func _valid_ticket(value: Dictionary) -> bool:
	if not _exact_fields(value, TICKET_FIELDS):
		return false
	var unsigned := value.duplicate(true)
	unsigned.erase("fingerprint")
	return (
		str(value.get("schema_id", "")) == TICKET_SCHEMA_ID
		and int(value.get("owner_instance_id", 0)) == get_instance_id()
		and str(value.get("fingerprint", "")) == _digest(unsigned)
		and value.get("before") is Dictionary
		and value.get("after") is Dictionary
		and not _normalize_snapshot(value["before"] as Dictionary).is_empty()
		and not _normalize_snapshot(value["after"] as Dictionary).is_empty()
	)


func _valid_receipt(value: Dictionary) -> bool:
	if not _exact_fields(value, RECEIPT_FIELDS):
		return false
	var unsigned := value.duplicate(true)
	unsigned.erase("fingerprint")
	return (
		str(value.get("schema_id", "")) == RECEIPT_SCHEMA_ID
		and int(value.get("owner_instance_id", 0)) == get_instance_id()
		and str(value.get("fingerprint", "")) == _digest(unsigned)
		and value.get("before") is Dictionary
		and value.get("after") is Dictionary
		and not _normalize_snapshot(value["before"] as Dictionary).is_empty()
		and not _normalize_snapshot(value["after"] as Dictionary).is_empty()
	)


func _apply_snapshot(value: Dictionary) -> void:
	_current = float(value["current"])
	_maximum = float(value["maximum"])
	_completed_transaction_ids.clear()
	for entry: Variant in value["completed_transaction_ids"]:
		_completed_transaction_ids.append(str(entry))
	_revision = int(value["revision"])


func _normalize_ids(value: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in value:
		if typeof(entry) != TYPE_STRING or not _valid_id(str(entry)) or result.has(str(entry)):
			return []
		result.append(str(entry))
	var sorted := result.duplicate()
	sorted.sort()
	return result if result == sorted else []


func _exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	var keys: Array[String] = []
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING:
			return false
		keys.append(str(key))
	keys.sort()
	var expected := fields.duplicate()
	expected.sort()
	return keys == expected


func _valid_id(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile("^[a-z0-9][a-z0-9_.:-]{0,95}$") == OK and regex.search(value) != null


func _digest(value: Dictionary) -> String:
	return JSON.stringify({"payload": value, "secret": _capability_secret}, "", true, true).sha256_text()


func _new_capability_secret() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()


func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": &"OK", "context": {}}
	result.merge(extra, true)
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
