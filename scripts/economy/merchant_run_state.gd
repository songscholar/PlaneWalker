class_name MerchantRunState
extends RefCounted

const SCHEMA_ID := "planewalker.merchant_state"
const SCHEMA_VERSION := 1
const MAX_REVISION := 2147483647
const MAX_AMOUNT := 1000000
const FINGERPRINT_PATTERN := "^[0-9a-f]{64}$"
const STABLE_ID_PATTERN := "^[a-z0-9][a-z0-9_.-]{0,95}$"
const TRANSACTION_ID_PATTERN := "^[a-z0-9][a-z0-9_.:-]{0,95}$"
const TRANSACTION_KINDS: Array[String] = ["purchase", "reroll", "service"]
const COST_KINDS: Array[String] = ["gold", "health", "time_shard", "forge_essence", "reward"]
const ROOT_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"content_fingerprint",
	"nodes",
	"pending_transaction",
]
const NODE_FIELDS: Array[String] = [
	"floor_id",
	"floor_index",
	"node_id",
	"merchant_id",
	"inventory",
	"runtime",
	"service",
	"visibility",
	"transactions",
]
const TRANSACTION_FIELDS: Array[String] = [
	"sequence",
	"transaction_id",
	"kind",
	"offer_id",
	"reward_id",
	"service_id",
	"cost_kind",
	"amount",
	"economy_revision",
	"inventory_revision",
]

var _configured: bool = false
var _content_fingerprint: String = ""
var _nodes: Array[Dictionary] = []


func configure(content_fingerprint: Variant) -> Dictionary:
	if not _matches(FINGERPRINT_PATTERN, content_fingerprint):
		return _failure(&"CONTENT_FINGERPRINT_INVALID")
	_configured = true
	_content_fingerprint = str(content_fingerprint)
	_nodes.clear()
	return _success({"snapshot": snapshot()})


func upsert_node(node: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	var normalized := _normalize_node(node)
	if normalized.is_empty():
		return _failure(&"NODE_INVALID")
	var node_key := _node_key(normalized)
	var candidate: Array[Dictionary] = _nodes.duplicate(true)
	var replaced := false
	for index: int in range(candidate.size()):
		if _node_key(candidate[index]) != node_key:
			continue
		if (
			int(candidate[index]["floor_index"]) != int(normalized["floor_index"])
			or str(candidate[index]["merchant_id"]) != str(normalized["merchant_id"])
		):
			return _failure(&"NODE_IDENTITY_MISMATCH", {"node_key": node_key})
		if candidate[index]["transactions"] != normalized["transactions"]:
			return _failure(&"TRANSACTION_HISTORY_INVALID", {"node_key": node_key})
		candidate[index] = normalized.duplicate(true)
		replaced = true
		break
	if not replaced:
		if not (normalized["transactions"] as Array).is_empty():
			return _failure(&"TRANSACTION_HISTORY_INVALID", {"node_key": node_key})
		candidate.append(normalized.duplicate(true))
	_sort_nodes(candidate)
	if not _validate_nodes(candidate):
		return _failure(&"NODE_INVALID", {"node_key": node_key})
	_nodes = candidate
	return _success({"node_key": node_key, "node": normalized.duplicate(true)})


func record_transaction(node_key: String, transaction: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	var node_index := _find_node_index(node_key)
	if node_index < 0:
		return _failure(&"NODE_NOT_FOUND", {"node_key": node_key})
	var normalized := _normalize_transaction(transaction)
	if normalized.is_empty():
		return _failure(&"TRANSACTION_INVALID")
	var facts := _all_transactions(_nodes)
	var expected_sequence := facts.size() + 1
	if int(normalized["sequence"]) != expected_sequence:
		return _failure(
			&"SEQUENCE_INVALID",
			{"expected_sequence": expected_sequence, "actual_sequence": int(normalized["sequence"])},
		)
	var transaction_id := str(normalized["transaction_id"])
	for fact: Dictionary in facts:
		if str(fact["transaction_id"]) == transaction_id:
			return _failure(&"DUPLICATE_TRANSACTION", {"transaction_id": transaction_id})

	var candidate: Array[Dictionary] = _nodes.duplicate(true)
	var transactions := candidate[node_index]["transactions"] as Array
	transactions.append(normalized.duplicate(true))
	candidate[node_index]["transactions"] = transactions
	if not _validate_nodes(candidate):
		return _failure(&"TRANSACTION_INVALID")
	_nodes = candidate
	return _success({
		"node_key": node_key,
		"transaction": normalized.duplicate(true),
		"sequence": expected_sequence,
	})


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"content_fingerprint": _content_fingerprint,
		"nodes": _nodes.duplicate(true),
		"pending_transaction": {},
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if not _configured:
		return false
	return not _normalize_snapshot(value).is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	if not _configured:
		return false
	var normalized := _normalize_snapshot(value)
	if normalized.is_empty():
		return false
	var nodes: Array[Dictionary] = []
	for node_value: Variant in normalized["nodes"]:
		nodes.append((node_value as Dictionary).duplicate(true))
	_nodes = nodes
	return snapshot() == normalized


func node_state(node_key: String) -> Dictionary:
	var node_index := _find_node_index(node_key)
	if node_index < 0:
		return {}
	return _nodes[node_index].duplicate(true)


func _normalize_snapshot(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, ROOT_FIELDS):
		return {}
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != SCHEMA_ID
		or typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != SCHEMA_VERSION
		or typeof(value["content_fingerprint"]) != TYPE_STRING
		or str(value["content_fingerprint"]) != _content_fingerprint
		or not value["nodes"] is Array
		or not value["pending_transaction"] is Dictionary
		or not (value["pending_transaction"] as Dictionary).is_empty()
	):
		return {}

	var normalized_nodes: Array[Dictionary] = []
	for node_value: Variant in value["nodes"]:
		if not node_value is Dictionary:
			return {}
		var normalized_node := _normalize_node(node_value as Dictionary)
		if normalized_node.is_empty():
			return {}
		normalized_nodes.append(normalized_node)
	if not _validate_nodes(normalized_nodes):
		return {}
	var sorted_nodes := normalized_nodes.duplicate(true)
	_sort_nodes(sorted_nodes)
	if sorted_nodes != normalized_nodes:
		return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"content_fingerprint": _content_fingerprint,
		"nodes": normalized_nodes.duplicate(true),
		"pending_transaction": {},
	}


func _normalize_node(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, NODE_FIELDS):
		return {}
	if (
		not _matches(STABLE_ID_PATTERN, value["floor_id"])
		or typeof(value["floor_index"]) != TYPE_INT
		or int(value["floor_index"]) < 0
		or int(value["floor_index"]) > 4
		or not _matches(STABLE_ID_PATTERN, value["node_id"])
		or not _matches(STABLE_ID_PATTERN, value["merchant_id"])
		or not value["inventory"] is Dictionary
		or not value["runtime"] is Dictionary
		or not value["service"] is Dictionary
		or not value["visibility"] is Dictionary
		or not value["transactions"] is Array
	):
		return {}
	for domain: String in ["inventory", "runtime", "service", "visibility"]:
		if not _is_safe_value(value[domain]):
			return {}

	var normalized_transactions: Array[Dictionary] = []
	var previous_sequence := 0
	for transaction_value: Variant in value["transactions"]:
		if not transaction_value is Dictionary:
			return {}
		var normalized_transaction := _normalize_transaction(transaction_value as Dictionary)
		if normalized_transaction.is_empty():
			return {}
		var sequence := int(normalized_transaction["sequence"])
		if sequence <= previous_sequence:
			return {}
		previous_sequence = sequence
		normalized_transactions.append(normalized_transaction)
	return {
		"floor_id": str(value["floor_id"]),
		"floor_index": int(value["floor_index"]),
		"node_id": str(value["node_id"]),
		"merchant_id": str(value["merchant_id"]),
		"inventory": (value["inventory"] as Dictionary).duplicate(true),
		"runtime": (value["runtime"] as Dictionary).duplicate(true),
		"service": (value["service"] as Dictionary).duplicate(true),
		"visibility": (value["visibility"] as Dictionary).duplicate(true),
		"transactions": normalized_transactions.duplicate(true),
	}


func _normalize_transaction(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, TRANSACTION_FIELDS):
		return {}
	if (
		typeof(value["sequence"]) != TYPE_INT
		or int(value["sequence"]) < 1
		or int(value["sequence"]) > MAX_REVISION
		or not _matches(TRANSACTION_ID_PATTERN, value["transaction_id"])
		or typeof(value["kind"]) != TYPE_STRING
		or not TRANSACTION_KINDS.has(str(value["kind"]))
		or not _optional_offer_id(value["offer_id"])
		or not _optional_id(value["reward_id"])
		or not _optional_id(value["service_id"])
		or typeof(value["cost_kind"]) != TYPE_STRING
		or not COST_KINDS.has(str(value["cost_kind"]))
		or typeof(value["amount"]) != TYPE_INT
		or int(value["amount"]) < 0
		or int(value["amount"]) > MAX_AMOUNT
		or typeof(value["economy_revision"]) != TYPE_INT
		or int(value["economy_revision"]) < 0
		or int(value["economy_revision"]) > MAX_REVISION
		or typeof(value["inventory_revision"]) != TYPE_INT
		or int(value["inventory_revision"]) < 0
		or int(value["inventory_revision"]) > MAX_REVISION
	):
		return {}
	var kind := str(value["kind"])
	var offer_id := str(value["offer_id"])
	var reward_id := str(value["reward_id"])
	var service_id := str(value["service_id"])
	if kind == "purchase" and (offer_id.is_empty() or reward_id.is_empty() or not service_id.is_empty()):
		return {}
	if kind == "reroll" and (not offer_id.is_empty() or not reward_id.is_empty() or not service_id.is_empty()):
		return {}
	if kind == "service" and service_id.is_empty():
		return {}
	return {
		"sequence": int(value["sequence"]),
		"transaction_id": str(value["transaction_id"]),
		"kind": kind,
		"offer_id": offer_id,
		"reward_id": reward_id,
		"service_id": service_id,
		"cost_kind": str(value["cost_kind"]),
		"amount": int(value["amount"]),
		"economy_revision": int(value["economy_revision"]),
		"inventory_revision": int(value["inventory_revision"]),
	}


func _validate_nodes(nodes: Array[Dictionary]) -> bool:
	var node_keys: Dictionary = {}
	var transaction_ids: Dictionary = {}
	var transactions: Array[Dictionary] = []
	var floor_indices: Dictionary = {}
	var floor_ids_by_index: Dictionary = {}
	for node: Dictionary in nodes:
		var normalized := _normalize_node(node)
		if normalized.is_empty() or normalized != node:
			return false
		var node_key := _node_key(node)
		if node_keys.has(node_key):
			return false
		node_keys[node_key] = true
		var floor_id := str(node["floor_id"])
		var floor_index := int(node["floor_index"])
		if floor_indices.has(floor_id) and int(floor_indices[floor_id]) != floor_index:
			return false
		if floor_ids_by_index.has(floor_index) and str(floor_ids_by_index[floor_index]) != floor_id:
			return false
		floor_indices[floor_id] = floor_index
		floor_ids_by_index[floor_index] = floor_id
		for transaction_value: Variant in node["transactions"]:
			var transaction := transaction_value as Dictionary
			var transaction_id := str(transaction["transaction_id"])
			if transaction_ids.has(transaction_id):
				return false
			transaction_ids[transaction_id] = true
			transactions.append(transaction)
	transactions.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left["sequence"]) < int(right["sequence"])
	)
	for index: int in range(transactions.size()):
		if int(transactions[index]["sequence"]) != index + 1:
			return false
	return true


func _all_transactions(nodes: Array[Dictionary]) -> Array[Dictionary]:
	var transactions: Array[Dictionary] = []
	for node: Dictionary in nodes:
		for transaction_value: Variant in node["transactions"]:
			transactions.append((transaction_value as Dictionary).duplicate(true))
	transactions.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left["sequence"]) < int(right["sequence"])
	)
	return transactions


func _find_node_index(node_key: String) -> int:
	if node_key.count(":") != 1:
		return -1
	for index: int in range(_nodes.size()):
		if _node_key(_nodes[index]) == node_key:
			return index
	return -1


func _node_key(node: Dictionary) -> String:
	return "%s:%s" % [str(node.get("floor_id", "")), str(node.get("node_id", ""))]


func _sort_nodes(nodes: Array[Dictionary]) -> void:
	nodes.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_floor := int(left["floor_index"])
			var right_floor := int(right["floor_index"])
			if left_floor != right_floor:
				return left_floor < right_floor
			return str(left["node_id"]) < str(right["node_id"])
	)


func _optional_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and (str(value).is_empty() or _matches(STABLE_ID_PATTERN, value))


func _optional_offer_id(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_STRING
		and (str(value).is_empty() or _matches(TRANSACTION_ID_PATTERN, value))
	)


func _is_safe_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for entry: Variant in value as Array:
				if not _is_safe_value(entry):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in (value as Dictionary).keys():
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME]:
					return false
				if not _is_safe_value((value as Dictionary)[key]):
					return false
			return true
		_:
			return false


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


func _matches(pattern: String, value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(str(value)) != null


func _success(payload: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": &"OK"}
	for key: Variant in payload.keys():
		result[key] = payload[key]
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
