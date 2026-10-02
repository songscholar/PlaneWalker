class_name RunEconomyState
extends RefCounted

const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")

const SCHEMA_ID := "planewalker.run_economy"
const SCHEMA_VERSION := 1
const TICKET_SCHEMA_ID := "run_economy_transaction_v1"
const RECEIPT_SCHEMA_ID := "run_economy_receipt_v1"
const MAX_TRANSACTION_AMOUNT := 1000000
const MAX_BALANCE := 2147483647
const STABLE_ID_PATTERN := "^[a-z0-9][a-z0-9_:-]{0,95}$"
const OPERATIONS: Array[String] = [
	"gold_delta",
	"gold_purchase",
	"gold_reroll",
	"gold_service",
	"gold_decay",
]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"profile_id",
	"initial_gold",
	"balance",
	"revision",
	"ledger",
	"settled_floor_indices",
]
const LEDGER_FIELDS: Array[String] = [
	"transaction_id",
	"operation",
	"amount",
	"revision",
]
const TICKET_FIELDS: Array[String] = [
	"schema_id",
	"transaction_id",
	"operation",
	"amount",
	"expected_revision",
	"before_balance",
	"after_balance",
	"context",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_id",
	"transaction_id",
	"operation",
	"amount",
	"revision",
	"before_balance",
	"after_balance",
	"context",
	"ledger_entry",
	"before",
	"after",
]

var _configured: bool = false
var _profile: Dictionary = {}
var _initial_gold: int = 0
var _balance: int = 0
var _revision: int = 0
var _ledger: Array[Dictionary] = []
var _transaction_ids: Dictionary = {}
var _settled_floor_indices: Array[int] = []
var _pending_ticket: Dictionary = {}


func configure(profile: Dictionary, initial_gold: int = 0) -> Dictionary:
	if not _pending_ticket.is_empty():
		return _failure(&"TRANSACTION_PENDING", {"transaction_id": str(_pending_ticket.get("transaction_id", ""))})
	if initial_gold < 0 or initial_gold > MAX_BALANCE:
		return _failure(&"INVALID_ARGUMENT", {"field": "initial_gold"})
	var parser: RefCounted = EconomyProfileScript.new()
	var normalized_result: Dictionary = parser.call("configure", profile.duplicate(true))
	if not bool(normalized_result.get("ok", false)):
		return _failure(
			&"INVALID_ARGUMENT",
			{"field": "profile", "validation": normalized_result.duplicate(true)}
		)
	var normalized_profile: Dictionary = parser.call("snapshot")
	_configured = true
	_profile = normalized_profile.duplicate(true)
	_initial_gold = initial_gold
	_balance = initial_gold
	_revision = 0
	_ledger.clear()
	_transaction_ids.clear()
	_settled_floor_indices.clear()
	_pending_ticket.clear()
	return _success({"snapshot": snapshot()})


func balance() -> int:
	return _balance if _configured else 0


func revision() -> int:
	return _revision if _configured else 0


func ledger() -> Array[Dictionary]:
	return _ledger.duplicate(true)


func has_pending_transaction() -> bool:
	return not _pending_ticket.is_empty()


func prepare_transaction(
	transaction_id: String,
	delta: int,
	expected_revision: int,
	context: Dictionary = {}
) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _pending_ticket.is_empty():
		return _failure(
			&"TRANSACTION_PENDING",
			{"transaction_id": str(_pending_ticket.get("transaction_id", ""))}
		)
	if expected_revision != _revision:
		return _failure(
			&"STALE_REVISION",
			{"expected_revision": expected_revision, "actual_revision": _revision}
		)
	if not _valid_transaction_id(transaction_id):
		return _failure(&"INVALID_ARGUMENT", {"field": "transaction_id"})
	if _transaction_ids.has(transaction_id):
		return _failure(&"DUPLICATE_TRANSACTION", {"transaction_id": transaction_id})
	if delta == 0 or absi(delta) > MAX_TRANSACTION_AMOUNT:
		return _failure(&"INVALID_ARGUMENT", {"field": "delta"})
	var operation := str(context.get("operation", "gold_delta"))
	if not OPERATIONS.has(operation):
		return _failure(&"INVALID_ARGUMENT", {"field": "context.operation"})
	if operation != "gold_delta" and delta >= 0:
		return _failure(
			&"INVALID_ARGUMENT",
			{"field": "delta", "reason": "operation_requires_cost"}
		)
	var after_balance := _balance + delta
	if after_balance < 0:
		return _failure(
			&"INSUFFICIENT_GOLD",
			{"balance": _balance, "required": -delta}
		)
	if after_balance > MAX_BALANCE:
		return _failure(&"INVALID_ARGUMENT", {"field": "delta", "reason": "balance_overflow"})
	var canonical_context := context.duplicate(true)
	canonical_context["operation"] = operation
	if operation == "gold_decay":
		var floor_index_result := _floor_index_from_context(canonical_context)
		if not bool(floor_index_result.get("ok", false)):
			return floor_index_result
		var floor_index := int(floor_index_result["floor_index"])
		if _settled_floor_indices.has(floor_index):
			return _failure(&"DUPLICATE_TRANSACTION", {"floor_index": floor_index})
	var ticket := {
		"schema_id": TICKET_SCHEMA_ID,
		"transaction_id": transaction_id,
		"operation": operation,
		"amount": delta,
		"expected_revision": _revision,
		"before_balance": _balance,
		"after_balance": after_balance,
		"context": canonical_context,
	}
	_pending_ticket = ticket.duplicate(true)
	return _success({"ticket": ticket.duplicate(true)})


func commit_transaction(ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if _pending_ticket.is_empty():
		return _failure(&"TRANSACTION_NOT_FOUND")
	if not _ticket_matches(ticket, _pending_ticket):
		return _failure(&"TRANSACTION_STALE")
	if (
		int(_pending_ticket["expected_revision"]) != _revision
		or int(_pending_ticket["before_balance"]) != _balance
	):
		return _failure(&"TRANSACTION_STALE")

	var before := snapshot()
	var transaction_id := str(_pending_ticket["transaction_id"])
	var operation := str(_pending_ticket["operation"])
	var amount := int(_pending_ticket["amount"])
	var transaction_context := (_pending_ticket["context"] as Dictionary).duplicate(true)
	_balance = int(_pending_ticket["after_balance"])
	_revision += 1
	var entry := {
		"transaction_id": transaction_id,
		"operation": operation,
		"amount": amount,
		"revision": _revision,
	}
	_ledger.append(entry.duplicate(true))
	_transaction_ids[transaction_id] = true
	if operation == "gold_decay":
		var floor_index := int(transaction_context["floor_index"])
		_settled_floor_indices.append(floor_index)
		_settled_floor_indices.sort()
	_pending_ticket.clear()
	var after := snapshot()
	var receipt := {
		"schema_id": RECEIPT_SCHEMA_ID,
		"transaction_id": transaction_id,
		"operation": operation,
		"amount": amount,
		"revision": _revision,
		"before_balance": int(before["balance"]),
		"after_balance": _balance,
		"context": transaction_context,
		"ledger_entry": entry.duplicate(true),
		"before": before.duplicate(true),
		"after": after.duplicate(true),
	}
	return _success({"receipt": receipt.duplicate(true), "ledger_entry": entry.duplicate(true)})


func rollback_transaction(receipt_or_ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _pending_ticket.is_empty():
		if not _ticket_matches(receipt_or_ticket, _pending_ticket):
			return _failure(&"TRANSACTION_STALE")
		var transaction_id := str(_pending_ticket["transaction_id"])
		_pending_ticket.clear()
		return _success({"transaction_id": transaction_id, "rolled_back": "pending"})
	if not _valid_receipt_shape(receipt_or_ticket):
		return _failure(&"TRANSACTION_NOT_FOUND")
	var after: Dictionary = receipt_or_ticket["after"]
	var before: Dictionary = receipt_or_ticket["before"]
	var ledger_entry: Dictionary = receipt_or_ticket["ledger_entry"]
	if snapshot() != after:
		return _failure(&"TRANSACTION_STALE")
	if _ledger.is_empty() or _ledger.back() != ledger_entry:
		return _failure(&"TRANSACTION_STALE")
	if not can_restore_snapshot(before):
		return _failure(&"INTEGRITY_FAILURE")
	var transaction_id := str(receipt_or_ticket["transaction_id"])
	if not restore_snapshot(before):
		return _failure(&"INTEGRITY_FAILURE")
	return _success({"transaction_id": transaction_id, "rolled_back": "committed"})


func apply_floor_transition(
	floor_index: int,
	expected_revision: int,
	transaction_id: String = ""
) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if expected_revision != _revision:
		return _failure(
			&"STALE_REVISION",
			{"expected_revision": expected_revision, "actual_revision": _revision}
		)
	if floor_index < 0 or floor_index >= 5:
		return _failure(&"INVALID_ARGUMENT", {"field": "floor_index"})
	if _settled_floor_indices.has(floor_index):
		return _failure(&"DUPLICATE_TRANSACTION", {"floor_index": floor_index})
	var caps: Array = _profile.get("gold_caps", [])
	if caps.size() != 5:
		return _failure(&"INTEGRITY_FAILURE", {"field": "profile.gold_caps"})
	var gold_cap := int(caps[floor_index])
	var overflow := maxi(0, _balance - gold_cap)
	var decay_ratio := float(_profile.get("overflow_decay", 0.0))
	var retained_overflow := int(floor(float(overflow) * decay_ratio))
	var target_balance := gold_cap + retained_overflow if overflow > 0 else _balance
	var decayed_gold := _balance - target_balance
	if decayed_gold <= 0:
		var resolved_transaction_id := transaction_id
		if resolved_transaction_id.is_empty():
			resolved_transaction_id = "tx_floor_%d_settlement" % (floor_index + 1)
		if not _valid_transaction_id(resolved_transaction_id):
			return _failure(&"INVALID_ARGUMENT", {"field": "transaction_id"})
		if _transaction_ids.has(resolved_transaction_id):
			return _failure(
				&"DUPLICATE_TRANSACTION", {"transaction_id": resolved_transaction_id}
			)
		var before := snapshot()
		_revision += 1
		var entry := {
			"transaction_id": resolved_transaction_id,
			"operation": "gold_decay",
			"amount": 0,
			"revision": _revision,
		}
		_ledger.append(entry.duplicate(true))
		_transaction_ids[resolved_transaction_id] = true
		_settled_floor_indices.append(floor_index)
		_settled_floor_indices.sort()
		var after := snapshot()
		var receipt := {
			"schema_id": RECEIPT_SCHEMA_ID,
			"transaction_id": resolved_transaction_id,
			"operation": "gold_decay",
			"amount": 0,
			"revision": _revision,
			"before_balance": int(before["balance"]),
			"after_balance": _balance,
			"context": {
				"operation": "gold_decay",
				"floor_index": floor_index,
				"gold_cap": gold_cap,
				"overflow_decay": decay_ratio,
			},
			"ledger_entry": entry.duplicate(true),
			"before": before.duplicate(true),
			"after": after.duplicate(true),
		}
		return _success({
			"receipt": receipt,
			"ledger_entry": entry.duplicate(true),
			"context": {
				"floor_index": floor_index,
				"gold_cap": gold_cap,
				"decayed_gold": 0,
				"balance": _balance,
			},
		})
	var resolved_transaction_id := transaction_id
	if resolved_transaction_id.is_empty():
		resolved_transaction_id = "tx_floor_%d_decay" % (floor_index + 1)
	var prepared := prepare_transaction(
		resolved_transaction_id,
		-decayed_gold,
		expected_revision,
		{
			"operation": "gold_decay",
			"floor_index": floor_index,
			"gold_cap": gold_cap,
			"overflow_decay": decay_ratio,
		}
	)
	if not bool(prepared.get("ok", false)):
		return prepared
	var committed := commit_transaction(prepared.get("ticket", {}))
	if not bool(committed.get("ok", false)):
		rollback_transaction(prepared.get("ticket", {}))
		return committed
	committed["context"] = {
		"floor_index": floor_index,
		"gold_cap": gold_cap,
		"decayed_gold": decayed_gold,
		"balance": _balance,
	}
	return committed


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"profile_id": str(_profile.get("id", "")),
		"initial_gold": _initial_gold,
		"balance": _balance,
		"revision": _revision,
		"ledger": _ledger.duplicate(true),
		"settled_floor_indices": _settled_floor_indices.duplicate(),
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if not _configured or not _pending_ticket.is_empty():
		return false
	return not _normalize_snapshot(value).is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	if not _configured or not _pending_ticket.is_empty():
		return false
	var normalized := _normalize_snapshot(value)
	if normalized.is_empty():
		return false
	_initial_gold = int(normalized["initial_gold"])
	_balance = int(normalized["balance"])
	_revision = int(normalized["revision"])
	_ledger.clear()
	for entry_value: Variant in normalized["ledger"]:
		_ledger.append((entry_value as Dictionary).duplicate(true))
	_settled_floor_indices.clear()
	for floor_value: Variant in normalized["settled_floor_indices"]:
		_settled_floor_indices.append(int(floor_value))
	_transaction_ids.clear()
	for entry: Dictionary in _ledger:
		_transaction_ids[str(entry["transaction_id"])] = true
	return snapshot() == normalized


func _normalize_snapshot(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return {}
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != SCHEMA_ID
		or not _integer_in_range(value["schema_version"], SCHEMA_VERSION, SCHEMA_VERSION)
		or typeof(value["profile_id"]) != TYPE_STRING
		or str(value["profile_id"]) != str(_profile.get("id", ""))
		or not _integer_in_range(value["initial_gold"], 0, MAX_BALANCE)
		or not _integer_in_range(value["balance"], 0, MAX_BALANCE)
		or not _integer_in_range(value["revision"], 0, MAX_BALANCE)
		or not value["ledger"] is Array
		or not value["settled_floor_indices"] is Array
	):
		return {}

	var normalized_ledger: Array[Dictionary] = []
	var ids: Dictionary = {}
	var computed_balance := int(value["initial_gold"])
	var decay_entries := 0
	var decay_records: Array[Dictionary] = []
	var ledger_values: Array = value["ledger"]
	for index: int in range(ledger_values.size()):
		var entry_value: Variant = ledger_values[index]
		if not entry_value is Dictionary:
			return {}
		var entry: Dictionary = entry_value
		if not _has_exact_fields(entry, LEDGER_FIELDS):
			return {}
		var transaction_id := str(entry.get("transaction_id", ""))
		var operation := str(entry.get("operation", ""))
		if (
			typeof(entry.get("transaction_id")) != TYPE_STRING
			or not _valid_transaction_id(transaction_id)
			or ids.has(transaction_id)
			or typeof(entry.get("operation")) != TYPE_STRING
			or not OPERATIONS.has(operation)
			or not _integer_in_range(entry.get("amount"), -MAX_TRANSACTION_AMOUNT, MAX_TRANSACTION_AMOUNT)
			or not _integer_in_range(entry.get("revision"), index + 1, index + 1)
		):
			return {}
		var amount := int(entry["amount"])
		if (
			(operation == "gold_delta" and amount == 0)
			or (operation in ["gold_purchase", "gold_reroll", "gold_service"] and amount >= 0)
			or (operation == "gold_decay" and amount > 0)
		):
			return {}
		var before_entry_balance := computed_balance
		computed_balance += amount
		if computed_balance < 0 or computed_balance > MAX_BALANCE:
			return {}
		if operation == "gold_decay":
			decay_entries += 1
			decay_records.append({
				"before_balance": before_entry_balance,
				"amount": int(entry["amount"]),
			})
		ids[transaction_id] = true
		normalized_ledger.append({
			"transaction_id": transaction_id,
			"operation": operation,
			"amount": int(entry["amount"]),
			"revision": int(entry["revision"]),
		})
	if int(value["revision"]) != normalized_ledger.size():
		return {}
	if int(value["balance"]) != computed_balance:
		return {}

	var normalized_floors: Array[int] = []
	for floor_value: Variant in value["settled_floor_indices"]:
		if not _integer_in_range(floor_value, 0, 4):
			return {}
		var floor_index := int(floor_value)
		if normalized_floors.has(floor_index):
			return {}
		normalized_floors.append(floor_index)
	var sorted_floors := normalized_floors.duplicate()
	sorted_floors.sort()
	if sorted_floors != normalized_floors or normalized_floors.size() != decay_entries:
		return {}
	var caps: Array = _profile.get("gold_caps", [])
	var decay_ratio := float(_profile.get("overflow_decay", -1.0))
	if caps.size() != 5 or decay_ratio < 0.0 or decay_ratio > 1.0:
		return {}
	for index: int in range(decay_records.size()):
		var floor_index := normalized_floors[index]
		var before_balance := int(decay_records[index]["before_balance"])
		var gold_cap := int(caps[floor_index])
		var overflow := maxi(0, before_balance - gold_cap)
		var target_balance := (
			gold_cap + int(floor(float(overflow) * decay_ratio))
			if overflow > 0
			else before_balance
		)
		var expected_amount := target_balance - before_balance
		if expected_amount > 0 or int(decay_records[index]["amount"]) != expected_amount:
			return {}

	return {
		"schema_id": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"profile_id": str(_profile.get("id", "")),
		"initial_gold": int(value["initial_gold"]),
		"balance": int(value["balance"]),
		"revision": int(value["revision"]),
		"ledger": normalized_ledger.duplicate(true),
		"settled_floor_indices": normalized_floors.duplicate(),
	}


func _valid_receipt_shape(value: Dictionary) -> bool:
	if not _has_exact_fields(value, RECEIPT_FIELDS):
		return false
	if not (
		typeof(value["schema_id"]) == TYPE_STRING
		and str(value["schema_id"]) == RECEIPT_SCHEMA_ID
		and typeof(value["transaction_id"]) == TYPE_STRING
		and _valid_transaction_id(str(value["transaction_id"]))
		and typeof(value["operation"]) == TYPE_STRING
		and OPERATIONS.has(str(value["operation"]))
		and _integer_in_range(value["amount"], -MAX_TRANSACTION_AMOUNT, MAX_TRANSACTION_AMOUNT)
		and _integer_in_range(value["revision"], 1, MAX_BALANCE)
		and _integer_in_range(value["before_balance"], 0, MAX_BALANCE)
		and _integer_in_range(value["after_balance"], 0, MAX_BALANCE)
		and value["context"] is Dictionary
		and value["ledger_entry"] is Dictionary
		and value["before"] is Dictionary
		and value["after"] is Dictionary
		and str(value["transaction_id"]) == str((value["ledger_entry"] as Dictionary).get("transaction_id", ""))
		and str(value["operation"]) == str((value["ledger_entry"] as Dictionary).get("operation", ""))
		and int(value["amount"]) == int((value["ledger_entry"] as Dictionary).get("amount", 0))
		and int(value["revision"]) == int((value["ledger_entry"] as Dictionary).get("revision", 0))
		and int(value["before_balance"]) == int((value["before"] as Dictionary).get("balance", -1))
		and int(value["after_balance"]) == int((value["after"] as Dictionary).get("balance", -1))
	):
		return false
	var operation := str(value["operation"])
	var amount := int(value["amount"])
	if (
		(operation == "gold_delta" and amount == 0)
		or (operation in ["gold_purchase", "gold_reroll", "gold_service"] and amount >= 0)
		or (operation == "gold_decay" and amount > 0)
	):
		return false
	return _receipt_transition_is_valid(value)


func _receipt_transition_is_valid(receipt: Dictionary) -> bool:
	var before: Dictionary = receipt["before"]
	var after: Dictionary = receipt["after"]
	var normalized_before := _normalize_snapshot(before)
	var normalized_after := _normalize_snapshot(after)
	if normalized_before.is_empty() or normalized_after.is_empty():
		return false
	if normalized_before != before or normalized_after != after:
		return false
	if (
		str(before["profile_id"]) != str(after["profile_id"])
		or int(before["initial_gold"]) != int(after["initial_gold"])
		or int(before["revision"]) + 1 != int(after["revision"])
		or int(after["revision"]) != int(receipt["revision"])
		or int(before["balance"]) + int(receipt["amount"]) != int(after["balance"])
	):
		return false
	var before_ledger: Array = before["ledger"]
	var after_ledger: Array = after["ledger"]
	if after_ledger.size() != before_ledger.size() + 1:
		return false
	for index: int in range(before_ledger.size()):
		if before_ledger[index] != after_ledger[index]:
			return false
	if after_ledger.back() != receipt["ledger_entry"]:
		return false
	var before_floors: Array = before["settled_floor_indices"]
	var after_floors: Array = after["settled_floor_indices"]
	if str(receipt["operation"]) != "gold_decay":
		return before_floors == after_floors
	var context: Dictionary = receipt["context"]
	if not context.has("floor_index") or not _integer_in_range(context["floor_index"], 0, 4):
		return false
	var expected_floors := before_floors.duplicate()
	var floor_index := int(context["floor_index"])
	if expected_floors.has(floor_index):
		return false
	expected_floors.append(floor_index)
	expected_floors.sort()
	return after_floors == expected_floors


func _ticket_matches(value: Dictionary, expected: Dictionary) -> bool:
	return _has_exact_fields(value, TICKET_FIELDS) and value == expected


func _floor_index_from_context(context: Dictionary) -> Dictionary:
	if not context.has("floor_index") or not _integer_in_range(context["floor_index"], 0, 4):
		return _failure(&"INVALID_ARGUMENT", {"field": "context.floor_index"})
	return {"ok": true, "floor_index": int(context["floor_index"])}


func _valid_transaction_id(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(STABLE_ID_PATTERN) == OK and regex.search(value) != null


func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= maximum
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	var number := float(value)
	return number == floorf(number) and number >= float(minimum) and number <= float(maximum)


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	for key: Variant in value.keys():
		if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME] or not fields.has(str(key)):
			return false
	return true


func _success(payload: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": &"OK"}
	for key: Variant in payload.keys():
		result[key] = payload[key]
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
