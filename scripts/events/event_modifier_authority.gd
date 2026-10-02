class_name EventModifierAuthority
extends RefCounted

const DungeonEventDefinitionScript := preload(
	"res://scripts/dungeon/dungeon_event_definition.gd"
)
const SCHEMA_ID := "planewalker.event_modifier_authority"
const TICKET_SCHEMA_ID := "event_modifier_ticket_v1"
const RECEIPT_SCHEMA_ID := "event_modifier_receipt_v1"
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id", "schema_version", "curse_ids", "narrative_flags",
	"temporary_modifiers", "completed_transaction_ids", "revision",
]
const MODIFIER_FIELDS: Array[String] = [
	"modifier_id", "duration_rooms", "magnitude", "source_transaction_id",
]
const TICKET_FIELDS: Array[String] = [
	"schema_id", "owner_instance_id", "transaction_id", "operations",
	"expected_revision", "before", "after", "fingerprint",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_id", "owner_instance_id", "transaction_id", "ticket_fingerprint",
	"before", "after", "fingerprint",
]

var _configured := false
var _curse_ids: Array[String] = []
var _narrative_flags: Dictionary = {}
var _temporary_modifiers: Array[Dictionary] = []
var _completed_transaction_ids: Array[String] = []
var _revision := 0
var _committed_rollback_receipt: Dictionary = {}
var _capability_secret := ""


func configure(
	curse_ids: Array,
	narrative_flags: Dictionary,
	temporary_modifiers: Array
) -> bool:
	var candidate := {
		"schema_id": SCHEMA_ID,
		"schema_version": 1,
		"curse_ids": curse_ids.duplicate(),
		"narrative_flags": narrative_flags.duplicate(true),
		"temporary_modifiers": temporary_modifiers.duplicate(true),
		"completed_transaction_ids": [],
		"revision": 0,
	}
	_configured = true
	var normalized := _normalize_snapshot(candidate)
	if normalized.is_empty():
		_configured = false
		return false
	_apply_snapshot(normalized)
	_committed_rollback_receipt.clear()
	_capability_secret = _new_capability_secret()
	return true


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": 1,
		"curse_ids": _curse_ids.duplicate(),
		"narrative_flags": _narrative_flags.duplicate(true),
		"temporary_modifiers": _temporary_modifiers.duplicate(true),
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


func prepare_operations(
	transaction_id: String,
	operations: Array,
	expected_revision: int
) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _valid_id(transaction_id) or operations.is_empty():
		return _failure(&"INVALID_ARGUMENT")
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"ALREADY_CONSUMED")
	if expected_revision != _revision:
		return _failure(&"STALE_REVISION", {"actual_revision": _revision})
	var normalized_operations := _normalize_operations(operations)
	if normalized_operations.is_empty():
		return _failure(&"INVALID_OPERATION")
	var before := snapshot()
	var after := before.duplicate(true)
	for operation: Dictionary in normalized_operations:
		var arguments := operation["arguments"] as Dictionary
		match str(operation["operation"]):
			"curse_add":
				var add_id := str(arguments["curse_id"])
				if (after["curse_ids"] as Array).has(add_id):
					return _failure(&"CURSE_ALREADY_PRESENT", {"curse_id": add_id})
				(after["curse_ids"] as Array).append(add_id)
				(after["curse_ids"] as Array).sort()
			"curse_remove":
				var remove_id := str(arguments["curse_id"])
				if not (after["curse_ids"] as Array).has(remove_id):
					return _failure(&"CURSE_NOT_PRESENT", {"curse_id": remove_id})
				(after["curse_ids"] as Array).erase(remove_id)
			"narrative_flag":
				(after["narrative_flags"] as Dictionary)[str(arguments["flag"])] = bool(arguments["value"])
			"temporary_modifier":
				var modifier_id := str(arguments["modifier_id"])
				for existing_value: Variant in after["temporary_modifiers"]:
					if str((existing_value as Dictionary)["modifier_id"]) == modifier_id:
						return _failure(&"MODIFIER_ALREADY_PRESENT", {"modifier_id": modifier_id})
				(after["temporary_modifiers"] as Array).append({
					"modifier_id": modifier_id,
					"duration_rooms": int(arguments["duration_rooms"]),
					"magnitude": float(arguments["magnitude"]),
					"source_transaction_id": transaction_id,
				})
	_sort_modifiers(after["temporary_modifiers"] as Array)
	(after["completed_transaction_ids"] as Array).append(transaction_id)
	(after["completed_transaction_ids"] as Array).sort()
	after["revision"] = _revision + 1
	var unsigned := {
		"schema_id": TICKET_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"operations": normalized_operations,
		"expected_revision": expected_revision,
		"before": before,
		"after": after,
	}
	var ticket := unsigned.duplicate(true)
	ticket["fingerprint"] = _digest(unsigned)
	return _success({"ticket": ticket})


func commit_operations(ticket: Dictionary) -> Dictionary:
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


func rollback_operations(receipt: Dictionary) -> Dictionary:
	if not _valid_receipt(receipt) or receipt != _committed_rollback_receipt or snapshot() != receipt["after"]:
		return _failure(&"TRANSACTION_STALE")
	_apply_snapshot(receipt["before"] as Dictionary)
	_committed_rollback_receipt.clear()
	return _success({"transaction_id": str(receipt["transaction_id"]), "rolled_back": true})


func _normalize_operations(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Variant in value:
		if not entry is Dictionary or not _exact_fields(entry as Dictionary, ["operation", "arguments"]):
			return []
		var operation := str((entry as Dictionary).get("operation", ""))
		var arguments_value: Variant = (entry as Dictionary).get("arguments")
		if not arguments_value is Dictionary:
			return []
		var arguments := arguments_value as Dictionary
		match operation:
			"curse_add", "curse_remove":
				if (
					not _exact_fields(arguments, ["curse_id"])
					or typeof(arguments.get("curse_id")) != TYPE_STRING
					or not DungeonEventDefinitionScript.CURSE_IDS.has(str(arguments["curse_id"]))
				):
					return []
			"narrative_flag":
				if (
					not _exact_fields(arguments, ["flag", "value"])
					or typeof(arguments.get("flag")) != TYPE_STRING
					or not _valid_id(str(arguments["flag"]))
					or typeof(arguments.get("value")) != TYPE_BOOL
				):
					return []
			"temporary_modifier":
				if (
					not _exact_fields(arguments, ["modifier_id", "duration_rooms", "magnitude"])
					or typeof(arguments.get("modifier_id")) != TYPE_STRING
					or not DungeonEventDefinitionScript.MODIFIER_IDS.has(str(arguments["modifier_id"]))
					or typeof(arguments.get("duration_rooms")) != TYPE_INT
					or int(arguments["duration_rooms"]) < 1
					or int(arguments["duration_rooms"]) > 5
					or typeof(arguments.get("magnitude")) not in [TYPE_INT, TYPE_FLOAT]
					or not is_finite(float(arguments["magnitude"]))
					or float(arguments["magnitude"]) <= 0.0
					or float(arguments["magnitude"]) > 10.0
				):
					return []
			_:
				return []
		result.append({"operation": operation, "arguments": arguments.duplicate(true)})
	return result


func _normalize_snapshot(value: Dictionary) -> Dictionary:
	if not _exact_fields(value, SNAPSHOT_FIELDS):
		return {}
	if (
		str(value.get("schema_id", "")) != SCHEMA_ID
		or typeof(value.get("schema_version")) != TYPE_INT
		or int(value["schema_version"]) != 1
		or not value.get("curse_ids") is Array
		or not value.get("narrative_flags") is Dictionary
		or not value.get("temporary_modifiers") is Array
		or not value.get("completed_transaction_ids") is Array
		or typeof(value.get("revision")) != TYPE_INT
		or int(value["revision"]) < 0
	):
		return {}
	var curses := _normalize_supported_ids(value["curse_ids"] as Array, DungeonEventDefinitionScript.CURSE_IDS)
	if curses.is_empty() and not (value["curse_ids"] as Array).is_empty():
		return {}
	var flags: Dictionary = {}
	for key: Variant in (value["narrative_flags"] as Dictionary).keys():
		if typeof(key) != TYPE_STRING or not _valid_id(str(key)) or typeof((value["narrative_flags"] as Dictionary)[key]) != TYPE_BOOL:
			return {}
		flags[str(key)] = bool((value["narrative_flags"] as Dictionary)[key])
	var modifiers := _normalize_modifiers(value["temporary_modifiers"] as Array)
	if modifiers.is_empty() and not (value["temporary_modifiers"] as Array).is_empty():
		return {}
	var completed := _normalize_ids(value["completed_transaction_ids"] as Array)
	if completed.size() != int(value["revision"]):
		return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": 1,
		"curse_ids": curses,
		"narrative_flags": flags,
		"temporary_modifiers": modifiers,
		"completed_transaction_ids": completed,
		"revision": int(value["revision"]),
	}


func _normalize_modifiers(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not entry is Dictionary or not _exact_fields(entry as Dictionary, MODIFIER_FIELDS):
			return []
		var modifier := entry as Dictionary
		var modifier_id := str(modifier.get("modifier_id", ""))
		if (
			not DungeonEventDefinitionScript.MODIFIER_IDS.has(modifier_id)
			or seen.has(modifier_id)
			or typeof(modifier.get("duration_rooms")) != TYPE_INT
			or int(modifier["duration_rooms"]) < 1
			or int(modifier["duration_rooms"]) > 5
			or typeof(modifier.get("magnitude")) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(modifier["magnitude"]))
			or float(modifier["magnitude"]) <= 0.0
			or not _valid_id(str(modifier.get("source_transaction_id", "")))
		):
			return []
		seen[modifier_id] = true
		result.append({
			"modifier_id": modifier_id,
			"duration_rooms": int(modifier["duration_rooms"]),
			"magnitude": float(modifier["magnitude"]),
			"source_transaction_id": str(modifier["source_transaction_id"]),
		})
	_sort_modifiers(result)
	return result


func _normalize_supported_ids(value: Array, supported: Array[String]) -> Array[String]:
	var result := _normalize_ids(value)
	for entry: String in result:
		if not supported.has(entry):
			return []
	return result


func _normalize_ids(value: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in value:
		if typeof(entry) != TYPE_STRING or not _valid_id(str(entry)) or result.has(str(entry)):
			return []
		result.append(str(entry))
	var sorted := result.duplicate()
	sorted.sort()
	return result if result == sorted else []


func _sort_modifiers(value: Array) -> void:
	value.sort_custom(func(left: Variant, right: Variant) -> bool:
		return str((left as Dictionary)["modifier_id"]) < str((right as Dictionary)["modifier_id"])
	)


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
	_curse_ids.clear()
	for entry: Variant in value["curse_ids"]:
		_curse_ids.append(str(entry))
	_narrative_flags = (value["narrative_flags"] as Dictionary).duplicate(true)
	_temporary_modifiers.clear()
	for entry: Variant in value["temporary_modifiers"]:
		_temporary_modifiers.append((entry as Dictionary).duplicate(true))
	_completed_transaction_ids.clear()
	for entry: Variant in value["completed_transaction_ids"]:
		_completed_transaction_ids.append(str(entry))
	_revision = int(value["revision"])


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
