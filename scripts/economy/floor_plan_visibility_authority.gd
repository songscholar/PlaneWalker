class_name FloorPlanVisibilityAuthority
extends RefCounted

const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")

const SNAPSHOT_SCHEMA_ID := "planewalker.floor_plan_visibility"
const SNAPSHOT_SCHEMA_VERSION := 1
const TICKET_SCHEMA_ID := "floor_plan_visibility_ticket_v1"
const RECEIPT_SCHEMA_ID := "floor_plan_visibility_receipt_v1"
const SNAPSHOT_FIELDS: Array[String] = [
	"completed_transaction_ids", "floor_plan", "schema_id", "schema_version",
]
const FLOOR_PLAN_FIELDS: Array[String] = [
	"abandoned_node_ids", "boss_node_id", "current_node_id", "edges",
	"entry_node_id", "floor_id", "floor_index", "generation_digest",
	"generator_version", "nodes", "revision", "run_seed", "schema_version",
	"selected_edge_ids", "visited_node_ids",
]
const NODE_FIELDS: Array[String] = [
	"cleared", "encounter_id", "event_id", "id", "layer", "merchant_id",
	"revealed", "reward_policy_id", "room_type", "seed_channel_suffix",
	"template_id", "visited",
]
const EDGE_FIELDS: Array[String] = [
	"choice_order", "destination_node_id", "id", "locked",
	"route_summary_facts", "source_node_id",
]
const TICKET_FIELDS: Array[String] = [
	"after", "before", "fingerprint", "owner_instance_id", "schema_id",
	"target_node_ids", "transaction_id",
]
const RECEIPT_FIELDS: Array[String] = [
	"after", "before", "fingerprint", "owner_instance_id", "schema_id",
	"target_node_ids", "ticket_fingerprint", "transaction_id",
]

var _configured: bool = false
var _floor_plan: Dictionary = {}
var _configured_state_signature: Dictionary = {}
var _completed_transaction_ids: Dictionary = {}
var _pending_ticket: Dictionary = {}


func configure(floor_plan_snapshot: Dictionary) -> Dictionary:
	if not _valid_floor_plan(floor_plan_snapshot):
		return _failure(&"FLOOR_PLAN_INVALID")
	_configured = true
	_floor_plan = floor_plan_snapshot.duplicate(true)
	_configured_state_signature = _state_signature(floor_plan_snapshot)
	_completed_transaction_ids.clear()
	_pending_ticket.clear()
	return _success({"snapshot": snapshot()})


func floor_plan_snapshot() -> Dictionary:
	return _floor_plan.duplicate(true) if _configured else {}


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
		"floor_plan": floor_plan_snapshot(),
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
		or not value["floor_plan"] is Dictionary
		or not value["completed_transaction_ids"] is Array
	):
		return false
	var candidate_plan := value["floor_plan"] as Dictionary
	if (
		not _valid_floor_plan(candidate_plan)
		or _state_signature(candidate_plan) != _configured_state_signature
	):
		return false
	var completed_ids := value["completed_transaction_ids"] as Array
	var normalized_ids: Array[String] = []
	var seen: Dictionary = {}
	for transaction_id_value: Variant in completed_ids:
		if typeof(transaction_id_value) != TYPE_STRING:
			return false
		var transaction_id := str(transaction_id_value)
		if not _valid_transaction_id(transaction_id) or seen.has(transaction_id):
			return false
		seen[transaction_id] = true
		normalized_ids.append(transaction_id)
	var sorted_ids := normalized_ids.duplicate()
	sorted_ids.sort()
	return normalized_ids == sorted_ids


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	var restored_ids: Dictionary = {}
	for transaction_id_value: Variant in value["completed_transaction_ids"]:
		restored_ids[str(transaction_id_value)] = true
	_floor_plan = (value["floor_plan"] as Dictionary).duplicate(true)
	_completed_transaction_ids = restored_ids
	_pending_ticket.clear()
	return snapshot() == value


func prepare_reveal(transaction_id: String, floor_plan_snapshot: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _pending_ticket.is_empty():
		return _failure(
			&"TRANSACTION_PENDING",
			{"transaction_id": str(_pending_ticket.get("transaction_id", ""))}
		)
	if not _valid_transaction_id(transaction_id):
		return _failure(&"INVALID_ARGUMENT", {"field": "transaction_id"})
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"DUPLICATE_TRANSACTION", {"transaction_id": transaction_id})
	if floor_plan_snapshot != _floor_plan:
		return _failure(&"STALE_FLOOR_PLAN")

	var target_node_ids := _hidden_target_node_ids(floor_plan_snapshot)
	if target_node_ids.is_empty():
		return _failure(&"NO_HIDDEN_TARGET")
	var before := floor_plan_snapshot.duplicate(true)
	var after := before.duplicate(true)
	for node_value: Variant in after["nodes"]:
		var node := node_value as Dictionary
		if target_node_ids.has(str(node["id"])):
			node["revealed"] = true
	if not _valid_reveal_transition(before, after, target_node_ids):
		return _failure(&"INTEGRITY_FAILURE")
	var ticket := {
		"schema_id": TICKET_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"target_node_ids": target_node_ids.duplicate(),
		"before": before.duplicate(true),
		"after": after.duplicate(true),
	}
	ticket["fingerprint"] = _fingerprint(ticket)
	_pending_ticket = ticket.duplicate(true)
	return _success({
		"before": before.duplicate(true),
		"after": after.duplicate(true),
		"ticket": ticket.duplicate(true),
	})


func commit_reveal(ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if _pending_ticket.is_empty():
		return _failure(&"TRANSACTION_NOT_FOUND")
	if not _valid_ticket(ticket) or ticket != _pending_ticket:
		return _failure(&"TRANSACTION_STALE")
	var before := ticket["before"] as Dictionary
	var after := ticket["after"] as Dictionary
	var target_node_ids := _string_array(ticket["target_node_ids"])
	if _floor_plan != before or not _valid_reveal_transition(before, after, target_node_ids):
		return _failure(&"TRANSACTION_STALE")

	_floor_plan = after.duplicate(true)
	var transaction_id := str(ticket["transaction_id"])
	_completed_transaction_ids[transaction_id] = true
	_pending_ticket.clear()
	var receipt := {
		"schema_id": RECEIPT_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"target_node_ids": target_node_ids.duplicate(),
		"before": before.duplicate(true),
		"after": after.duplicate(true),
		"ticket_fingerprint": str(ticket["fingerprint"]),
	}
	receipt["fingerprint"] = _fingerprint(receipt)
	return _success({
		"receipt": receipt.duplicate(true),
		"floor_plan": floor_plan_snapshot(),
	})


func rollback_reveal(receipt_or_ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _pending_ticket.is_empty():
		if not _valid_ticket(receipt_or_ticket) or receipt_or_ticket != _pending_ticket:
			return _failure(&"TRANSACTION_STALE")
		var pending_transaction_id := str(_pending_ticket["transaction_id"])
		_pending_ticket.clear()
		return _success({
			"transaction_id": pending_transaction_id,
			"rolled_back": "pending",
		})
	if not _valid_receipt(receipt_or_ticket):
		return _failure(&"TRANSACTION_NOT_FOUND")
	var transaction_id := str(receipt_or_ticket["transaction_id"])
	var before := receipt_or_ticket["before"] as Dictionary
	var after := receipt_or_ticket["after"] as Dictionary
	if not _completed_transaction_ids.has(transaction_id) or _floor_plan != after:
		return _failure(&"TRANSACTION_STALE")
	var target_node_ids := _string_array(receipt_or_ticket["target_node_ids"])
	if not _valid_reveal_transition(before, after, target_node_ids):
		return _failure(&"TRANSACTION_STALE")
	_floor_plan = before.duplicate(true)
	_completed_transaction_ids.erase(transaction_id)
	return _success({
		"transaction_id": transaction_id,
		"rolled_back": "committed",
		"floor_plan": floor_plan_snapshot(),
	})


func _hidden_target_node_ids(plan: Dictionary) -> Array[String]:
	var current_node_id := str(plan["current_node_id"])
	var excluded: Dictionary = {}
	for node_id_value: Variant in plan["visited_node_ids"]:
		excluded[str(node_id_value)] = true
	for node_id_value: Variant in plan["abandoned_node_ids"]:
		excluded[str(node_id_value)] = true
	var candidate_ids: Array[String] = []
	for edge_value: Variant in plan["edges"]:
		var edge := edge_value as Dictionary
		var destination_id := str(edge["destination_node_id"])
		if (
			str(edge["source_node_id"]) == current_node_id
			and not excluded.has(destination_id)
			and not candidate_ids.has(destination_id)
		):
			candidate_ids.append(destination_id)
	candidate_ids.sort()
	var targets: Array[String] = []
	for edge_value: Variant in plan["edges"]:
		var edge := edge_value as Dictionary
		var target_id := str(edge["destination_node_id"])
		if (
			candidate_ids.has(str(edge["source_node_id"]))
			and not excluded.has(target_id)
			and not targets.has(target_id)
		):
			var node := _node_by_id(plan, target_id)
			if not node.is_empty() and not bool(node["revealed"]):
				targets.append(target_id)
	targets.sort()
	return targets


func _valid_reveal_transition(
	before: Dictionary,
	after: Dictionary,
	target_node_ids: Array[String]
) -> bool:
	if (
		target_node_ids.is_empty()
		or not _valid_floor_plan(before)
		or not _valid_floor_plan(after)
		or _state_signature(before) != _state_signature(after)
		or _hidden_target_node_ids(before) != target_node_ids
	):
		return false
	var target_set: Dictionary = {}
	for target_node_id: String in target_node_ids:
		if target_set.has(target_node_id):
			return false
		target_set[target_node_id] = true
	var sorted_targets := target_node_ids.duplicate()
	sorted_targets.sort()
	if sorted_targets != target_node_ids:
		return false
	for before_value: Variant in before["nodes"]:
		var before_node := before_value as Dictionary
		var node_id := str(before_node["id"])
		var after_node := _node_by_id(after, node_id)
		if after_node.is_empty():
			return false
		for field_value: Variant in before_node.keys():
			var field := str(field_value)
			if field == "revealed" and target_set.has(node_id):
				if bool(before_node[field]) or not bool(after_node.get(field, false)):
					return false
			elif after_node.get(field) != before_node[field]:
				return false
	return true


func _valid_ticket(value: Dictionary) -> bool:
	if not _has_exact_fields(value, TICKET_FIELDS):
		return false
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != TICKET_SCHEMA_ID
		or typeof(value["owner_instance_id"]) != TYPE_INT
		or int(value["owner_instance_id"]) != get_instance_id()
		or typeof(value["transaction_id"]) != TYPE_STRING
		or not _valid_transaction_id(str(value["transaction_id"]))
		or not value["target_node_ids"] is Array
		or not value["before"] is Dictionary
		or not value["after"] is Dictionary
		or typeof(value["fingerprint"]) != TYPE_STRING
	):
		return false
	var unsigned := value.duplicate(true)
	var supplied_fingerprint := str(unsigned["fingerprint"])
	unsigned.erase("fingerprint")
	return supplied_fingerprint == _fingerprint(unsigned)


func _valid_receipt(value: Dictionary) -> bool:
	if not _has_exact_fields(value, RECEIPT_FIELDS):
		return false
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != RECEIPT_SCHEMA_ID
		or typeof(value["owner_instance_id"]) != TYPE_INT
		or int(value["owner_instance_id"]) != get_instance_id()
		or typeof(value["transaction_id"]) != TYPE_STRING
		or not _valid_transaction_id(str(value["transaction_id"]))
		or not value["target_node_ids"] is Array
		or not value["before"] is Dictionary
		or not value["after"] is Dictionary
		or typeof(value["ticket_fingerprint"]) != TYPE_STRING
		or str(value["ticket_fingerprint"]).is_empty()
		or typeof(value["fingerprint"]) != TYPE_STRING
	):
		return false
	var unsigned := value.duplicate(true)
	var supplied_fingerprint := str(unsigned["fingerprint"])
	unsigned.erase("fingerprint")
	return supplied_fingerprint == _fingerprint(unsigned)


func _valid_floor_plan(plan: Dictionary) -> bool:
	if not _has_exact_fields(plan, FLOOR_PLAN_FIELDS):
		return false
	if (
		typeof(plan["schema_version"]) != TYPE_INT
		or int(plan["schema_version"]) != FloorPlanScript.SCHEMA_VERSION
		or typeof(plan["generator_version"]) != TYPE_STRING
		or str(plan["generator_version"]) != FloorPlanScript.GENERATOR_VERSION
		or typeof(plan["run_seed"]) != TYPE_INT
		or typeof(plan["floor_id"]) != TYPE_STRING
		or str(plan["floor_id"]).is_empty()
		or typeof(plan["floor_index"]) != TYPE_INT
		or int(plan["floor_index"]) < 0
		or int(plan["floor_index"]) >= 5
		or typeof(plan["entry_node_id"]) != TYPE_STRING
		or typeof(plan["boss_node_id"]) != TYPE_STRING
		or typeof(plan["current_node_id"]) != TYPE_STRING
		or typeof(plan["generation_digest"]) != TYPE_STRING
		or str(plan["generation_digest"]).length() != 64
		or typeof(plan["revision"]) != TYPE_INT
		or int(plan["revision"]) < 0
	):
		return false
	for field: String in [
		"nodes", "edges", "selected_edge_ids", "visited_node_ids", "abandoned_node_ids",
	]:
		if not plan[field] is Array:
			return false
	if str(plan["generation_digest"]) != FloorPlanScript.compute_generation_digest(plan):
		return false
	var nodes_by_id: Dictionary = {}
	for node_value: Variant in plan["nodes"]:
		if not node_value is Dictionary:
			return false
		var node := node_value as Dictionary
		if (
			not _has_exact_fields(node, NODE_FIELDS)
			or typeof(node["id"]) != TYPE_STRING
			or str(node["id"]).is_empty()
			or nodes_by_id.has(str(node["id"]))
			or typeof(node["layer"]) != TYPE_INT
			or typeof(node["revealed"]) != TYPE_BOOL
			or typeof(node["visited"]) != TYPE_BOOL
			or typeof(node["cleared"]) != TYPE_BOOL
		):
			return false
		nodes_by_id[str(node["id"])] = node
	if (
		not nodes_by_id.has(str(plan["entry_node_id"]))
		or not nodes_by_id.has(str(plan["boss_node_id"]))
		or not nodes_by_id.has(str(plan["current_node_id"]))
	):
		return false
	var edge_ids: Dictionary = {}
	for edge_value: Variant in plan["edges"]:
		if not edge_value is Dictionary:
			return false
		var edge := edge_value as Dictionary
		if (
			not _has_exact_fields(edge, EDGE_FIELDS)
			or typeof(edge["id"]) != TYPE_STRING
			or str(edge["id"]).is_empty()
			or edge_ids.has(str(edge["id"]))
			or typeof(edge["source_node_id"]) != TYPE_STRING
			or typeof(edge["destination_node_id"]) != TYPE_STRING
			or not nodes_by_id.has(str(edge["source_node_id"]))
			or not nodes_by_id.has(str(edge["destination_node_id"]))
		):
			return false
		edge_ids[str(edge["id"])] = true
	for visited_id_value: Variant in plan["visited_node_ids"]:
		if typeof(visited_id_value) != TYPE_STRING or not nodes_by_id.has(str(visited_id_value)):
			return false
		var visited_node := nodes_by_id[str(visited_id_value)] as Dictionary
		if not bool(visited_node["visited"]) or not bool(visited_node["revealed"]):
			return false
	for abandoned_id_value: Variant in plan["abandoned_node_ids"]:
		if (
			typeof(abandoned_id_value) != TYPE_STRING
			or not nodes_by_id.has(str(abandoned_id_value))
			or (plan["visited_node_ids"] as Array).has(str(abandoned_id_value))
		):
			return false
	return true


func _state_signature(plan: Dictionary) -> Dictionary:
	var signature := plan.duplicate(true)
	for node_value: Variant in signature.get("nodes", []):
		if node_value is Dictionary:
			(node_value as Dictionary)["revealed"] = false
	return signature


func _node_by_id(plan: Dictionary, node_id: String) -> Dictionary:
	for node_value: Variant in plan.get("nodes", []):
		if node_value is Dictionary and str((node_value as Dictionary).get("id", "")) == node_id:
			return node_value as Dictionary
	return {}


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value:
		if typeof(item) != TYPE_STRING:
			return []
		result.append(str(item))
	return result


func _valid_transaction_id(value: String) -> bool:
	if value.is_empty() or value.length() > 96:
		return false
	for character: String in value:
		if not (
			character >= "a" and character <= "z"
			or character >= "0" and character <= "9"
			or character in ["_", ":", "-"]
		):
			return false
	return true


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	var keys: Array[String] = []
	for key_value: Variant in value.keys():
		keys.append(str(key_value))
	keys.sort()
	return keys == fields


func _fingerprint(value: Dictionary) -> String:
	var serialized := JSON.stringify(value, "", true, true)
	return serialized.sha256_text() if not serialized.is_empty() else ""


func _success(payload: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": &"OK", "context": {}}
	for key: Variant in payload.keys():
		result[key] = payload[key]
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
