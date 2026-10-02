class_name EventRouteAuthority
extends RefCounted

const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const SCHEMA_ID := "planewalker.event_route_authority"
const TICKET_SCHEMA_ID := "event_route_ticket_v1"
const RECEIPT_SCHEMA_ID := "event_route_receipt_v1"
const RESTRICTED_ROOM_TYPES: Array[String] = ["boss", "rest", "shop"]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id", "schema_version", "plan", "completed_transaction_ids", "revision",
]
const PLAN_FIELDS: Array[String] = [
	"schema_version", "generator_version", "run_seed", "floor_id", "floor_index",
	"entry_node_id", "boss_node_id", "current_node_id", "nodes", "edges",
	"selected_edge_ids", "visited_node_ids", "abandoned_node_ids",
	"generation_digest", "revision",
]
const NODE_FIELDS: Array[String] = [
	"id", "layer", "room_type", "template_id", "encounter_id", "event_id",
	"merchant_id", "reward_policy_id", "seed_channel_suffix", "revealed",
	"visited", "cleared",
]
const EDGE_FIELDS: Array[String] = [
	"id", "source_node_id", "destination_node_id", "choice_order", "locked",
	"route_summary_facts",
]
const TICKET_FIELDS: Array[String] = [
	"schema_id", "owner_instance_id", "transaction_id", "operations",
	"expected_revision", "before", "after", "route_facts", "fingerprint",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_id", "owner_instance_id", "transaction_id", "ticket_fingerprint",
	"before", "after", "route_facts", "fingerprint",
]

var _configured := false
var _plan: Dictionary = {}
var _generation_digest := ""
var _completed_transaction_ids: Array[String] = []
var _revision := 0
var _committed_rollback_receipt: Dictionary = {}
var _capability_secret := ""


func configure(plan: Dictionary) -> bool:
	_generation_digest = ""
	var normalized_plan := _normalize_plan(plan)
	if normalized_plan.is_empty():
		return false
	_plan = normalized_plan
	_generation_digest = str(normalized_plan["generation_digest"])
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
		"plan": _plan.duplicate(true),
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
	var candidate_plan := _plan.duplicate(true)
	var route_facts: Array[Dictionary] = []
	for operation: Dictionary in normalized_operations:
		var arguments := operation["arguments"] as Dictionary
		match str(operation["operation"]):
			"map_reveal":
				var reveal_fact := _apply_map_reveal(candidate_plan, int(arguments["depth"]))
				route_facts.append(reveal_fact)
			"route_skip":
				var path_result := _skip_path(candidate_plan, int(arguments["rooms"]), true)
				if not bool(path_result.get("ok", false)):
					var raw_path := _skip_path(candidate_plan, int(arguments["rooms"]), false)
					return _failure(
						&"ROUTE_RESTRICTED" if bool(raw_path.get("ok", false)) else &"ROUTE_DEPTH_INSUFFICIENT"
					)
				var skip_fact := _apply_route_skip(candidate_plan, path_result["edges"] as Array)
				route_facts.append(skip_fact)
	var normalized_candidate := _normalize_plan(candidate_plan)
	if normalized_candidate.is_empty():
		return _failure(&"ROUTE_CANDIDATE_INVALID")
	var after := before.duplicate(true)
	after["plan"] = normalized_candidate
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
		"route_facts": route_facts,
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
	return _success({"receipt": receipt, "route_facts": (ticket["route_facts"] as Array).duplicate(true)})


func rollback_operations(receipt: Dictionary) -> Dictionary:
	if not _valid_receipt(receipt) or receipt != _committed_rollback_receipt or snapshot() != receipt["after"]:
		return _failure(&"TRANSACTION_STALE")
	_apply_snapshot(receipt["before"] as Dictionary)
	_committed_rollback_receipt.clear()
	return _success({"transaction_id": str(receipt["transaction_id"]), "rolled_back": true})


func _apply_map_reveal(plan: Dictionary, depth: int) -> Dictionary:
	var outgoing := _outgoing(plan)
	var frontier: Array[Dictionary] = [{"node_id": str(plan["current_node_id"]), "distance": 0}]
	var revealed: Array[String] = []
	var visited: Dictionary = {}
	while not frontier.is_empty():
		var cursor := frontier.pop_front() as Dictionary
		var node_id := str(cursor["node_id"])
		var distance := int(cursor["distance"])
		if visited.has(node_id) or distance > depth:
			continue
		visited[node_id] = true
		if distance > 0:
			var node := _node(plan, node_id)
			node["revealed"] = true
			revealed.append(node_id)
		if distance == depth:
			continue
		for edge_value: Variant in outgoing.get(node_id, []):
			var edge := edge_value as Dictionary
			if not bool(edge["locked"]):
				frontier.append({"node_id": str(edge["destination_node_id"]), "distance": distance + 1})
	revealed.sort()
	return {"operation": "map_reveal", "revealed_node_ids": revealed, "depth": depth}


func _skip_path(plan: Dictionary, rooms: int, enforce_restrictions: bool) -> Dictionary:
	return _walk_path(
		str(plan["current_node_id"]), rooms, _outgoing(plan), _nodes_by_id(plan), enforce_restrictions
	)


func _walk_path(
	node_id: String,
	remaining: int,
	outgoing: Dictionary,
	nodes_by_id: Dictionary,
	enforce_restrictions: bool
) -> Dictionary:
	if remaining == 0:
		return {"ok": true, "edges": []}
	var candidates: Array = (outgoing.get(node_id, []) as Array).duplicate(true)
	candidates.sort_custom(func(left: Variant, right: Variant) -> bool:
		var left_edge := left as Dictionary
		var right_edge := right as Dictionary
		var left_order := int(left_edge["choice_order"])
		var right_order := int(right_edge["choice_order"])
		return left_order < right_order if left_order != right_order else str(left_edge["id"]) < str(right_edge["id"])
	)
	for edge_value: Variant in candidates:
		var edge := edge_value as Dictionary
		if bool(edge["locked"]):
			continue
		var destination_id := str(edge["destination_node_id"])
		var destination := nodes_by_id.get(destination_id, {}) as Dictionary
		if destination.is_empty():
			continue
		if enforce_restrictions and RESTRICTED_ROOM_TYPES.has(str(destination["room_type"])):
			continue
		var tail := _walk_path(destination_id, remaining - 1, outgoing, nodes_by_id, enforce_restrictions)
		if bool(tail.get("ok", false)):
			var edges: Array = [edge.duplicate(true)]
			edges.append_array((tail["edges"] as Array).duplicate(true))
			return {"ok": true, "edges": edges}
	return {"ok": false, "edges": []}


func _apply_route_skip(plan: Dictionary, edges: Array) -> Dictionary:
	var landed_node_id := str(plan["current_node_id"])
	var skipped_node_ids: Array[String] = []
	var selected_edge_ids := plan["selected_edge_ids"] as Array
	var visited_node_ids := plan["visited_node_ids"] as Array
	for index: int in range(edges.size()):
		var edge := edges[index] as Dictionary
		var edge_id := str(edge["id"])
		landed_node_id = str(edge["destination_node_id"])
		if not selected_edge_ids.has(edge_id):
			selected_edge_ids.append(edge_id)
		if not visited_node_ids.has(landed_node_id):
			visited_node_ids.append(landed_node_id)
		var node := _node(plan, landed_node_id)
		node["revealed"] = true
		node["visited"] = true
		if index < edges.size() - 1:
			node["cleared"] = true
			skipped_node_ids.append(landed_node_id)
	plan["current_node_id"] = landed_node_id
	plan["abandoned_node_ids"] = _abandoned_nodes(plan)
	plan["revision"] = int(plan["revision"]) + edges.size()
	return {
		"operation": "route_skip",
		"selected_edge_ids": edges.map(func(value: Variant) -> String: return str((value as Dictionary)["id"])),
		"skipped_node_ids": skipped_node_ids,
		"landed_node_id": landed_node_id,
	}


func _abandoned_nodes(plan: Dictionary) -> Array[String]:
	var reachable: Dictionary = {}
	var pending: Array[String] = [str(plan["current_node_id"])]
	var outgoing := _outgoing(plan)
	while not pending.is_empty():
		var node_id: String = pending.pop_front()
		if reachable.has(node_id):
			continue
		reachable[node_id] = true
		for edge_value: Variant in outgoing.get(node_id, []):
			var edge := edge_value as Dictionary
			if not bool(edge["locked"]):
				pending.append(str(edge["destination_node_id"]))
	var result: Array[String] = []
	for node_value: Variant in plan["nodes"]:
		var node := node_value as Dictionary
		var node_id := str(node["id"])
		if not reachable.has(node_id) and not (plan["visited_node_ids"] as Array).has(node_id):
			result.append(node_id)
	return result


func _normalize_operations(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not entry is Dictionary or not _exact_fields(entry as Dictionary, ["operation", "arguments"]):
			return []
		var operation := str((entry as Dictionary).get("operation", ""))
		var arguments_value: Variant = (entry as Dictionary).get("arguments")
		if seen.has(operation) or not arguments_value is Dictionary:
			return []
		seen[operation] = true
		var arguments := arguments_value as Dictionary
		match operation:
			"map_reveal":
				if not _exact_fields(arguments, ["depth"]) or typeof(arguments.get("depth")) != TYPE_INT or int(arguments["depth"]) < 1 or int(arguments["depth"]) > 5:
					return []
			"route_skip":
				if not _exact_fields(arguments, ["rooms"]) or typeof(arguments.get("rooms")) != TYPE_INT or int(arguments["rooms"]) < 1 or int(arguments["rooms"]) > 2:
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
		or not value.get("plan") is Dictionary
		or not value.get("completed_transaction_ids") is Array
		or typeof(value.get("revision")) != TYPE_INT
		or int(value["revision"]) < 0
	):
		return {}
	var plan := _normalize_plan(value["plan"] as Dictionary)
	if plan.is_empty():
		return {}
	var completed := _normalize_ids(value["completed_transaction_ids"] as Array)
	if completed.size() != int(value["revision"]):
		return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": 1,
		"plan": plan,
		"completed_transaction_ids": completed,
		"revision": int(value["revision"]),
	}


func _normalize_plan(value: Dictionary) -> Dictionary:
	if not _exact_fields(value, PLAN_FIELDS):
		return {}
	if (
		typeof(value.get("schema_version")) != TYPE_INT
		or int(value["schema_version"]) != 1
		or str(value.get("generator_version", "")) != "floor_plan_v1"
		or typeof(value.get("run_seed")) != TYPE_INT
		or not _valid_id(str(value.get("floor_id", "")))
		or typeof(value.get("floor_index")) != TYPE_INT
		or not value.get("nodes") is Array
		or not value.get("edges") is Array
		or not value.get("selected_edge_ids") is Array
		or not value.get("visited_node_ids") is Array
		or not value.get("abandoned_node_ids") is Array
		or typeof(value.get("revision")) != TYPE_INT
		or int(value["revision"]) < 0
	):
		return {}
	var nodes_by_id: Dictionary = {}
	for node_value: Variant in value["nodes"]:
		if not node_value is Dictionary or not _exact_fields(node_value as Dictionary, NODE_FIELDS):
			return {}
		var node := node_value as Dictionary
		var node_id := str(node.get("id", ""))
		if (
			not _valid_id(node_id)
			or nodes_by_id.has(node_id)
			or typeof(node.get("layer")) != TYPE_INT
			or int(node["layer"]) < 0
			or typeof(node.get("room_type")) != TYPE_STRING
			or typeof(node.get("revealed")) != TYPE_BOOL
			or typeof(node.get("visited")) != TYPE_BOOL
			or typeof(node.get("cleared")) != TYPE_BOOL
		):
			return {}
		nodes_by_id[node_id] = node
	if not nodes_by_id.has(str(value.get("current_node_id", ""))):
		return {}
	var edge_ids: Dictionary = {}
	for edge_value: Variant in value["edges"]:
		if not edge_value is Dictionary or not _exact_fields(edge_value as Dictionary, EDGE_FIELDS):
			return {}
		var edge := edge_value as Dictionary
		var edge_id := str(edge.get("id", ""))
		if (
			not _valid_id(edge_id)
			or edge_ids.has(edge_id)
			or not nodes_by_id.has(str(edge.get("source_node_id", "")))
			or not nodes_by_id.has(str(edge.get("destination_node_id", "")))
			or typeof(edge.get("choice_order")) != TYPE_INT
			or int(edge["choice_order"]) < 0
			or typeof(edge.get("locked")) != TYPE_BOOL
			or not edge.get("route_summary_facts") is Dictionary
		):
			return {}
		edge_ids[edge_id] = true
	for field: String in ["selected_edge_ids", "visited_node_ids", "abandoned_node_ids"]:
		var ids := _normalize_ids(value[field] as Array)
		if ids.is_empty() and not (value[field] as Array).is_empty():
			return {}
		var authority := edge_ids if field == "selected_edge_ids" else nodes_by_id
		for entry: String in ids:
			if not authority.has(entry):
				return {}
	if not _canonical_state_valid(value, nodes_by_id, edge_ids):
		return {}
	var generation_digest := str(value.get("generation_digest", ""))
	if generation_digest != FloorPlanScript.compute_generation_digest(value):
		return {}
	if not _generation_digest.is_empty() and generation_digest != _generation_digest:
		return {}
	return value.duplicate(true)


func _canonical_state_valid(
	plan: Dictionary,
	nodes_by_id: Dictionary,
	edge_ids: Dictionary
) -> bool:
	var edges_by_id: Dictionary = {}
	for edge_value: Variant in plan["edges"]:
		var edge := edge_value as Dictionary
		edges_by_id[str(edge["id"])] = edge
	var cursor := str(plan["entry_node_id"])
	var expected_visited: Array[String] = [cursor]
	for selected_value: Variant in plan["selected_edge_ids"]:
		var selected_id := str(selected_value)
		if not edge_ids.has(selected_id):
			return false
		var edge := edges_by_id[selected_id] as Dictionary
		if (
			bool(edge["locked"])
			or str(edge["source_node_id"]) != cursor
			or (plan["abandoned_node_ids"] as Array).has(str(edge["source_node_id"]))
			or (plan["abandoned_node_ids"] as Array).has(str(edge["destination_node_id"]))
		):
			return false
		cursor = str(edge["destination_node_id"])
		expected_visited.append(cursor)
	if (
		cursor != str(plan["current_node_id"])
		or (plan["visited_node_ids"] as Array) != expected_visited
		or int(plan["revision"]) != (plan["selected_edge_ids"] as Array).size()
		or (plan["abandoned_node_ids"] as Array) != _abandoned_nodes(plan)
	):
		return false
	for node_id_value: Variant in nodes_by_id.keys():
		var node_id := str(node_id_value)
		var node := nodes_by_id[node_id] as Dictionary
		var expected_visit := expected_visited.has(node_id)
		if bool(node["visited"]) != expected_visit:
			return false
		if expected_visit and not bool(node["revealed"]):
			return false
		if node_id == str(plan["entry_node_id"]):
			continue
		if not expected_visit and bool(node["cleared"]):
			return false
		if expected_visit and node_id != cursor and not bool(node["cleared"]):
			return false
	return true


func _outgoing(plan: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for edge_value: Variant in plan["edges"]:
		var edge := edge_value as Dictionary
		var source := str(edge["source_node_id"])
		if not result.has(source):
			result[source] = []
		(result[source] as Array).append(edge.duplicate(true))
	return result


func _nodes_by_id(plan: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for node_value: Variant in plan["nodes"]:
		var node := node_value as Dictionary
		result[str(node["id"])] = node
	return result


func _node(plan: Dictionary, node_id: String) -> Dictionary:
	for node_value: Variant in plan["nodes"]:
		var node := node_value as Dictionary
		if str(node["id"]) == node_id:
			return node
	return {}


func _normalize_ids(value: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in value:
		if typeof(entry) != TYPE_STRING or not _valid_id(str(entry)) or result.has(str(entry)):
			return []
		result.append(str(entry))
	return result


func _receipt(ticket: Dictionary) -> Dictionary:
	var unsigned := {
		"schema_id": RECEIPT_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": str(ticket["transaction_id"]),
		"ticket_fingerprint": str(ticket["fingerprint"]),
		"before": (ticket["before"] as Dictionary).duplicate(true),
		"after": (ticket["after"] as Dictionary).duplicate(true),
		"route_facts": (ticket["route_facts"] as Array).duplicate(true),
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
	_plan = (value["plan"] as Dictionary).duplicate(true)
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
