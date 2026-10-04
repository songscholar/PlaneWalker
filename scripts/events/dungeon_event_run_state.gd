class_name DungeonEventRunState
extends RefCounted

const SCHEMA_ID := "planewalker.dungeon_event_state"
const SCHEMA_VERSION := 1
const TRANSACTION_SCHEMA_ID := "dungeon_event_transaction_v1"
const RECEIPT_SCHEMA_ID := "dungeon_event_receipt_v1"
const MAX_REVISION := 2147483647
const FINGERPRINT_PATTERN := "^[0-9a-f]{64}$"
const STABLE_ID_PATTERN := "^[a-z0-9][a-z0-9_.-]{0,95}$"
const TRANSACTION_ID_PATTERN := "^[a-z0-9][a-z0-9_.:-]{0,95}$"
const LOCALIZATION_KEY_PATTERN := "^[A-Z][A-Z0-9_]{1,127}$"
const REPEAT_POLICIES: Array[String] = ["once_per_run", "once_per_floor", "repeatable"]
const PHASES: Array[String] = [
	"open", "reserved", "pending_reward", "pending_encounter", "resolved", "dismissed",
]
const ROOT_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"content_fingerprint",
	"selected_event_by_node",
	"seen_run_event_ids",
	"seen_floor_event_keys",
	"resolved_outcomes",
	"pending_transaction",
	"pending_reward",
	"pending_encounter",
	"completed_transaction_ids",
	"narrative_flags",
	"temporary_modifiers",
	"revision",
]
const ASSIGNMENT_INPUT_FIELDS: Array[String] = [
	"floor_id", "floor_index", "node_id", "event_id", "repeat_policy",
]
const ASSIGNMENT_FIELDS: Array[String] = [
	"floor_id", "floor_index", "node_id", "event_id", "repeat_policy", "phase",
	"option_id", "outcome_id", "outcome_key", "result_key", "transaction_id",
]
const TRANSACTION_FIELDS: Array[String] = [
	"schema_id", "transaction_id", "node_key", "event_id", "option_id", "outcome_id",
	"outcome_key", "expected_revision", "before",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_id", "transaction_id", "ticket", "before", "after",
]
const REWARD_FIELDS: Array[String] = [
	"transaction_id", "node_key", "event_id", "continuation_id", "pool_id", "count",
]
const REWARD_INPUT_FIELDS: Array[String] = ["continuation_id", "pool_id", "count"]
const ENCOUNTER_FIELDS: Array[String] = [
	"transaction_id", "node_key", "event_id", "continuation_id", "encounter_id",
]
const ENCOUNTER_INPUT_FIELDS: Array[String] = ["continuation_id", "encounter_id"]
const RESOLUTION_FIELDS: Array[String] = [
	"result_key", "narrative_flags", "temporary_modifiers",
]
const OUTCOME_FIELDS: Array[String] = [
	"transaction_id", "node_key", "event_id", "option_id", "outcome_id", "outcome_key",
	"result_key", "revision", "dismissed",
]
const MODIFIER_FIELDS: Array[String] = [
	"modifier_id", "duration_rooms", "magnitude", "source_transaction_id",
]

var _configured: bool = false
var _content_fingerprint: String = ""
var _selected_event_by_node: Dictionary = {}
var _seen_run_event_ids: Array[String] = []
var _seen_floor_event_keys: Array[String] = []
var _resolved_outcomes: Array[Dictionary] = []
var _pending_transaction: Dictionary = {}
var _pending_reward: Dictionary = {}
var _pending_encounter: Dictionary = {}
var _completed_transaction_ids: Array[String] = []
var _narrative_flags: Dictionary = {}
var _temporary_modifiers: Array[Dictionary] = []
var _revision: int = 0
var _committed_rollback_receipt: Dictionary = {}


func configure(content_fingerprint: Variant) -> Dictionary:
	if not _matches(FINGERPRINT_PATTERN, content_fingerprint):
		return _failure(&"CONTENT_FINGERPRINT_INVALID")
	_configured = true
	_content_fingerprint = str(content_fingerprint)
	_selected_event_by_node.clear()
	_seen_run_event_ids.clear()
	_seen_floor_event_keys.clear()
	_resolved_outcomes.clear()
	_pending_transaction.clear()
	_pending_reward.clear()
	_pending_encounter.clear()
	_completed_transaction_ids.clear()
	_narrative_flags.clear()
	_temporary_modifiers.clear()
	_revision = 0
	_committed_rollback_receipt.clear()
	return _success({"snapshot": snapshot()})


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"content_fingerprint": _content_fingerprint,
		"selected_event_by_node": _selected_event_by_node.duplicate(true),
		"seen_run_event_ids": _seen_run_event_ids.duplicate(),
		"seen_floor_event_keys": _seen_floor_event_keys.duplicate(),
		"resolved_outcomes": _resolved_outcomes.duplicate(true),
		"pending_transaction": _pending_transaction.duplicate(true),
		"pending_reward": _pending_reward.duplicate(true),
		"pending_encounter": _pending_encounter.duplicate(true),
		"completed_transaction_ids": _completed_transaction_ids.duplicate(),
		"narrative_flags": _narrative_flags.duplicate(true),
		"temporary_modifiers": _temporary_modifiers.duplicate(true),
		"revision": _revision,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if not _configured:
		return false
	return not _normalize_snapshot(value, true).is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	if not _configured:
		return false
	var normalized := _normalize_snapshot(value, true)
	if normalized.is_empty():
		return false
	_apply_snapshot(normalized)
	_committed_rollback_receipt.clear()
	return snapshot() == normalized


func assign_event(assignment: Dictionary, expected_revision: int) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if expected_revision != _revision:
		return _stale_revision(expected_revision)
	if not _pending_transaction.is_empty():
		return _failure(
			&"TRANSACTION_PENDING",
			{"transaction_id": str(_pending_transaction.get("transaction_id", ""))},
		)
	var normalized := _normalize_assignment_input(assignment)
	if normalized.is_empty():
		return _failure(&"ASSIGNMENT_INVALID")
	var node_key := _node_key(normalized)
	if _selected_event_by_node.has(node_key):
		return _failure(&"DUPLICATE_ASSIGNMENT", {"node_key": node_key})
	var event_id := str(normalized["event_id"])
	var repeat_policy := str(normalized["repeat_policy"])
	var floor_key := _floor_event_key(normalized)
	if repeat_policy == "once_per_run" and _seen_run_event_ids.has(event_id):
		return _failure(&"REPEAT_POLICY_BLOCKED", {"event_id": event_id, "policy": repeat_policy})
	if repeat_policy == "once_per_floor" and _seen_floor_event_keys.has(floor_key):
		return _failure(
			&"REPEAT_POLICY_BLOCKED",
			{"event_id": event_id, "floor_id": str(normalized["floor_id"]), "policy": repeat_policy},
		)
	for existing_value: Variant in _selected_event_by_node.values():
		var existing := existing_value as Dictionary
		if str(existing["event_id"]) == event_id and str(existing["repeat_policy"]) != repeat_policy:
			return _failure(&"REPEAT_POLICY_MISMATCH", {"event_id": event_id})

	var stored := normalized.duplicate(true)
	_committed_rollback_receipt.clear()
	stored["phase"] = "open"
	stored["option_id"] = ""
	stored["outcome_id"] = ""
	stored["outcome_key"] = ""
	stored["result_key"] = ""
	stored["transaction_id"] = ""
	_selected_event_by_node[node_key] = stored
	_sort_assignment_dictionary()
	if not _seen_run_event_ids.has(event_id):
		_seen_run_event_ids.append(event_id)
		_seen_run_event_ids.sort()
	if not _seen_floor_event_keys.has(floor_key):
		_seen_floor_event_keys.append(floor_key)
		_seen_floor_event_keys.sort()
	_revision += 1
	return _success({
		"node_key": node_key,
		"assignment": stored.duplicate(true),
		"revision": _revision,
	})


func reserve_option(
	node_key: String,
	transaction_id: String,
	option_id: String,
	outcome_id: String,
	outcome_key: String,
	expected_revision: int
) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if expected_revision != _revision:
		return _stale_revision(expected_revision)
	if not _pending_transaction.is_empty():
		return _failure(
			&"TRANSACTION_PENDING",
			{"transaction_id": str(_pending_transaction.get("transaction_id", ""))},
		)
	if not _valid_node_key(node_key) or not _selected_event_by_node.has(node_key):
		return _failure(&"EVENT_NOT_FOUND", {"node_key": node_key})
	if (
		not _matches(TRANSACTION_ID_PATTERN, transaction_id)
		or not _matches(STABLE_ID_PATTERN, option_id)
		or not _matches(STABLE_ID_PATTERN, outcome_id)
		or not _matches(LOCALIZATION_KEY_PATTERN, outcome_key)
	):
		return _failure(&"RESERVATION_INVALID")
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"DUPLICATE_TRANSACTION", {"transaction_id": transaction_id})
	var assignment := (_selected_event_by_node[node_key] as Dictionary).duplicate(true)
	if str(assignment["phase"]) != "open":
		return _failure(&"EVENT_NOT_OPEN", {"node_key": node_key, "phase": assignment["phase"]})

	var before := snapshot()
	_committed_rollback_receipt.clear()
	var ticket := {
		"schema_id": TRANSACTION_SCHEMA_ID,
		"transaction_id": transaction_id,
		"node_key": node_key,
		"event_id": str(assignment["event_id"]),
		"option_id": option_id,
		"outcome_id": outcome_id,
		"outcome_key": outcome_key,
		"expected_revision": expected_revision,
		"before": before.duplicate(true),
	}
	assignment["phase"] = "reserved"
	assignment["option_id"] = option_id
	assignment["outcome_id"] = outcome_id
	assignment["outcome_key"] = outcome_key
	assignment["transaction_id"] = transaction_id
	_selected_event_by_node[node_key] = assignment
	_pending_transaction = ticket.duplicate(true)
	_revision += 1
	return _success({"ticket": ticket.duplicate(true), "revision": _revision})


func mark_pending_reward(ticket: Dictionary, pending: Dictionary) -> Dictionary:
	var ticket_error := _active_ticket_error(ticket, ["reserved"])
	if not ticket_error.is_empty():
		return ticket_error
	var normalized := _normalize_reward_input(pending)
	if normalized.is_empty():
		return _failure(&"PENDING_REWARD_INVALID")
	var node_key := str(_pending_transaction["node_key"])
	_committed_rollback_receipt.clear()
	var assignment := (_selected_event_by_node[node_key] as Dictionary).duplicate(true)
	assignment["phase"] = "pending_reward"
	_selected_event_by_node[node_key] = assignment
	_pending_reward = {
		"transaction_id": str(_pending_transaction["transaction_id"]),
		"node_key": node_key,
		"event_id": str(_pending_transaction["event_id"]),
		"continuation_id": str(normalized["continuation_id"]),
		"pool_id": str(normalized["pool_id"]),
		"count": int(normalized["count"]),
	}
	_pending_encounter.clear()
	return _success({"pending_reward": _pending_reward.duplicate(true), "revision": _revision})


func mark_pending_encounter(ticket: Dictionary, pending: Dictionary) -> Dictionary:
	var ticket_error := _active_ticket_error(ticket, ["reserved"])
	if not ticket_error.is_empty():
		return ticket_error
	var normalized := _normalize_encounter_input(pending)
	if normalized.is_empty():
		return _failure(&"PENDING_ENCOUNTER_INVALID")
	var node_key := str(_pending_transaction["node_key"])
	_committed_rollback_receipt.clear()
	var assignment := (_selected_event_by_node[node_key] as Dictionary).duplicate(true)
	assignment["phase"] = "pending_encounter"
	_selected_event_by_node[node_key] = assignment
	_pending_encounter = {
		"transaction_id": str(_pending_transaction["transaction_id"]),
		"node_key": node_key,
		"event_id": str(_pending_transaction["event_id"]),
		"continuation_id": str(normalized["continuation_id"]),
		"encounter_id": str(normalized["encounter_id"]),
	}
	_pending_reward.clear()
	return _success({"pending_encounter": _pending_encounter.duplicate(true), "revision": _revision})


func synchronize_pending_modifiers(ticket: Dictionary, flags: Dictionary, modifiers: Array) -> bool:
	if not _active_ticket_error(ticket, ["pending_reward", "pending_encounter"]).is_empty():
		return false
	var normalized := _normalize_resolution({"result_key": _pending_transaction["outcome_key"], "narrative_flags": flags, "temporary_modifiers": modifiers}, str(_pending_transaction["transaction_id"]))
	if normalized.is_empty():
		return false
	_narrative_flags = normalized["narrative_flags"].duplicate(true)
	_temporary_modifiers.assign(normalized["temporary_modifiers"])
	return true


func resolve_option(ticket: Dictionary, resolution: Dictionary) -> Dictionary:
	var ticket_error := _active_ticket_error(
		ticket, ["reserved", "pending_reward", "pending_encounter"]
	)
	if not ticket_error.is_empty():
		return ticket_error
	var normalized := _normalize_resolution(resolution, str(_pending_transaction["transaction_id"]))
	if normalized.is_empty():
		return _failure(&"RESOLUTION_INVALID")
	if str(normalized["result_key"]) != str(_pending_transaction["outcome_key"]):
		return _failure(&"RESOLUTION_TAMPERED", {"field": "result_key"})

	var node_key := str(_pending_transaction["node_key"])
	var transaction_id := str(_pending_transaction["transaction_id"])
	var before := (_pending_transaction["before"] as Dictionary).duplicate(true)
	_committed_rollback_receipt.clear()
	var assignment := (_selected_event_by_node[node_key] as Dictionary).duplicate(true)
	assignment["phase"] = "resolved"
	assignment["result_key"] = str(normalized["result_key"])
	_selected_event_by_node[node_key] = assignment
	_revision += 1
	var outcome := {
		"transaction_id": transaction_id,
		"node_key": node_key,
		"event_id": str(_pending_transaction["event_id"]),
		"option_id": str(_pending_transaction["option_id"]),
		"outcome_id": str(_pending_transaction["outcome_id"]),
		"outcome_key": str(_pending_transaction["outcome_key"]),
		"result_key": str(normalized["result_key"]),
		"revision": _revision,
		"dismissed": false,
	}
	_resolved_outcomes.append(outcome)
	_sort_outcomes(_resolved_outcomes)
	_completed_transaction_ids.append(transaction_id)
	_completed_transaction_ids.sort()
	_narrative_flags = (normalized["narrative_flags"] as Dictionary).duplicate(true)
	_temporary_modifiers.clear()
	for modifier_value: Variant in normalized["temporary_modifiers"]:
		_temporary_modifiers.append((modifier_value as Dictionary).duplicate(true))
	_pending_transaction.clear()
	_pending_reward.clear()
	_pending_encounter.clear()
	var after := snapshot()
	var receipt := {
		"schema_id": RECEIPT_SCHEMA_ID,
		"transaction_id": transaction_id,
		"ticket": ticket.duplicate(true),
		"before": before.duplicate(true),
		"after": after.duplicate(true),
	}
	_committed_rollback_receipt = receipt.duplicate(true)
	return _success({
		"receipt": receipt,
		"outcome": outcome.duplicate(true),
		"revision": _revision,
	})


func dismiss_result(node_key: String, expected_revision: int) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if expected_revision != _revision:
		return _stale_revision(expected_revision)
	if not _pending_transaction.is_empty():
		return _failure(&"TRANSACTION_PENDING")
	if not _valid_node_key(node_key) or not _selected_event_by_node.has(node_key):
		return _failure(&"EVENT_NOT_FOUND", {"node_key": node_key})
	var assignment := (_selected_event_by_node[node_key] as Dictionary).duplicate(true)
	if str(assignment["phase"]) != "resolved":
		return _failure(&"RESULT_NOT_RESOLVED", {"node_key": node_key, "phase": assignment["phase"]})
	var transaction_id := str(assignment["transaction_id"])
	var outcome_index := _outcome_index(transaction_id)
	if outcome_index < 0:
		return _failure(&"INTEGRITY_FAILURE", {"transaction_id": transaction_id})
	_committed_rollback_receipt.clear()
	assignment["phase"] = "dismissed"
	_selected_event_by_node[node_key] = assignment
	var outcome := _resolved_outcomes[outcome_index].duplicate(true)
	outcome["dismissed"] = true
	_resolved_outcomes[outcome_index] = outcome
	_revision += 1
	return _success({"node_key": node_key, "result": outcome.duplicate(true), "revision": _revision})


func rollback_transaction(receipt_or_ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _pending_transaction.is_empty():
		if receipt_or_ticket != _pending_transaction:
			return _failure(&"TRANSACTION_STALE")
		var before_value: Variant = _pending_transaction.get("before", {})
		if not before_value is Dictionary:
			return _failure(&"INTEGRITY_FAILURE")
		var normalized_before := _normalize_snapshot(before_value as Dictionary, false)
		if normalized_before.is_empty():
			return _failure(&"INTEGRITY_FAILURE")
		var transaction_id := str(_pending_transaction["transaction_id"])
		_apply_snapshot(normalized_before)
		_committed_rollback_receipt.clear()
		return _success({"transaction_id": transaction_id, "rolled_back": "pending"})
	if receipt_or_ticket != _committed_rollback_receipt:
		return _failure(&"TRANSACTION_NOT_FOUND")
	if not _valid_receipt(receipt_or_ticket):
		return _failure(&"TRANSACTION_NOT_FOUND")
	if snapshot() != receipt_or_ticket["after"]:
		return _failure(&"TRANSACTION_STALE")
	var before := _normalize_snapshot(receipt_or_ticket["before"], false)
	if before.is_empty():
		return _failure(&"INTEGRITY_FAILURE")
	var transaction_id := str(receipt_or_ticket["transaction_id"])
	_apply_snapshot(before)
	_committed_rollback_receipt.clear()
	return _success({"transaction_id": transaction_id, "rolled_back": "committed"})


func _normalize_snapshot(value: Dictionary, allow_pending: bool) -> Dictionary:
	if not _has_exact_fields(value, ROOT_FIELDS):
		return {}
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != SCHEMA_ID
		or typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != SCHEMA_VERSION
		or typeof(value["content_fingerprint"]) != TYPE_STRING
		or str(value["content_fingerprint"]) != _content_fingerprint
		or not value["selected_event_by_node"] is Dictionary
		or not value["seen_run_event_ids"] is Array
		or not value["seen_floor_event_keys"] is Array
		or not value["resolved_outcomes"] is Array
		or not value["pending_transaction"] is Dictionary
		or not value["pending_reward"] is Dictionary
		or not value["pending_encounter"] is Dictionary
		or not value["completed_transaction_ids"] is Array
		or not value["narrative_flags"] is Dictionary
		or not value["temporary_modifiers"] is Array
		or not _integer_in_range(value["revision"], 0, MAX_REVISION)
	):
		return {}

	var assignments := _normalize_assignments(value["selected_event_by_node"] as Dictionary)
	if assignments.is_empty() and not (value["selected_event_by_node"] as Dictionary).is_empty():
		return {}
	var seen_run := _normalize_sorted_ids(value["seen_run_event_ids"], STABLE_ID_PATTERN)
	var seen_floor := _normalize_sorted_ids(value["seen_floor_event_keys"], TRANSACTION_ID_PATTERN)
	var completed := _normalize_sorted_ids(value["completed_transaction_ids"], TRANSACTION_ID_PATTERN)
	if (
		(seen_run.is_empty() and not (value["seen_run_event_ids"] as Array).is_empty())
		or (seen_floor.is_empty() and not (value["seen_floor_event_keys"] as Array).is_empty())
		or (completed.is_empty() and not (value["completed_transaction_ids"] as Array).is_empty())
	):
		return {}
	var derived_histories := _derived_histories(assignments)
	if seen_run != derived_histories["seen_run_event_ids"] or seen_floor != derived_histories["seen_floor_event_keys"]:
		return {}

	var outcomes := _normalize_outcomes(value["resolved_outcomes"] as Array, assignments)
	if outcomes.is_empty() and not (value["resolved_outcomes"] as Array).is_empty():
		return {}
	var outcome_ids: Array[String] = []
	var dismissed_count := 0
	for outcome: Dictionary in outcomes:
		if int(outcome["revision"]) > int(value["revision"]):
			return {}
		outcome_ids.append(str(outcome["transaction_id"]))
		if bool(outcome["dismissed"]):
			dismissed_count += 1
	outcome_ids.sort()
	if completed != outcome_ids:
		return {}

	var flags := _normalize_flags(value["narrative_flags"] as Dictionary)
	if flags.is_empty() and not (value["narrative_flags"] as Dictionary).is_empty():
		return {}
	var modifiers := _normalize_modifiers(value["temporary_modifiers"] as Array, completed, str(value.get("pending_transaction", {}).get("transaction_id", "")))
	if modifiers.is_empty() and not (value["temporary_modifiers"] as Array).is_empty():
		return {}

	var pending_transaction: Dictionary = {}
	var pending_reward: Dictionary = {}
	var pending_encounter: Dictionary = {}
	if not (value["pending_transaction"] as Dictionary).is_empty():
		if not allow_pending:
			return {}
		pending_transaction = _normalize_pending_transaction(
			value["pending_transaction"] as Dictionary, assignments, int(value["revision"]), completed
		)
		if pending_transaction.is_empty():
			return {}
		pending_reward = _normalize_pending_reward(value["pending_reward"] as Dictionary, pending_transaction)
		pending_encounter = _normalize_pending_encounter(
			value["pending_encounter"] as Dictionary, pending_transaction
		)
		var phase := str((assignments[str(pending_transaction["node_key"])] as Dictionary)["phase"])
		if phase == "reserved":
			if not pending_reward.is_empty() or not pending_encounter.is_empty():
				return {}
		elif phase == "pending_reward":
			if pending_reward.is_empty() or not pending_encounter.is_empty():
				return {}
		elif phase == "pending_encounter":
			if pending_encounter.is_empty() or not pending_reward.is_empty():
				return {}
		else:
			return {}
	else:
		if not (value["pending_reward"] as Dictionary).is_empty() or not (value["pending_encounter"] as Dictionary).is_empty():
			return {}
		for assignment_value: Variant in assignments.values():
			if str((assignment_value as Dictionary)["phase"]) in ["reserved", "pending_reward", "pending_encounter"]:
				return {}
	var exact_revision := assignments.size() + outcomes.size() * 2 + dismissed_count
	if not pending_transaction.is_empty():
		exact_revision += 1
	if int(value["revision"]) != exact_revision:
		return {}

	return {
		"schema_id": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"content_fingerprint": _content_fingerprint,
		"selected_event_by_node": assignments.duplicate(true),
		"seen_run_event_ids": seen_run.duplicate(),
		"seen_floor_event_keys": seen_floor.duplicate(),
		"resolved_outcomes": outcomes.duplicate(true),
		"pending_transaction": pending_transaction.duplicate(true),
		"pending_reward": pending_reward.duplicate(true),
		"pending_encounter": pending_encounter.duplicate(true),
		"completed_transaction_ids": completed.duplicate(),
		"narrative_flags": flags.duplicate(true),
		"temporary_modifiers": modifiers.duplicate(true),
		"revision": int(value["revision"]),
	}


func _normalize_assignments(value: Dictionary) -> Dictionary:
	var keys: Array[String] = []
	for key_value: Variant in value.keys():
		if typeof(key_value) != TYPE_STRING or not _valid_node_key(str(key_value)):
			return {}
		keys.append(str(key_value))
	keys.sort()
	var normalized: Dictionary = {}
	var floor_indices: Dictionary = {}
	var floor_ids: Dictionary = {}
	var event_policies: Dictionary = {}
	var once_run_counts: Dictionary = {}
	var once_floor_counts: Dictionary = {}
	for key: String in keys:
		var entry_value: Variant = value[key]
		if not entry_value is Dictionary:
			return {}
		var entry := _normalize_assignment(entry_value as Dictionary)
		if entry.is_empty() or _node_key(entry) != key:
			return {}
		var floor_id := str(entry["floor_id"])
		var floor_index := int(entry["floor_index"])
		if floor_indices.has(floor_id) and int(floor_indices[floor_id]) != floor_index:
			return {}
		if floor_ids.has(floor_index) and str(floor_ids[floor_index]) != floor_id:
			return {}
		floor_indices[floor_id] = floor_index
		floor_ids[floor_index] = floor_id
		var event_id := str(entry["event_id"])
		var policy := str(entry["repeat_policy"])
		if event_policies.has(event_id) and str(event_policies[event_id]) != policy:
			return {}
		event_policies[event_id] = policy
		if policy == "once_per_run":
			once_run_counts[event_id] = int(once_run_counts.get(event_id, 0)) + 1
			if int(once_run_counts[event_id]) > 1:
				return {}
		elif policy == "once_per_floor":
			var floor_key := _floor_event_key(entry)
			once_floor_counts[floor_key] = int(once_floor_counts.get(floor_key, 0)) + 1
			if int(once_floor_counts[floor_key]) > 1:
				return {}
		normalized[key] = entry
	return normalized


func _normalize_assignment_input(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, ASSIGNMENT_INPUT_FIELDS):
		return {}
	if (
		not _matches(STABLE_ID_PATTERN, value["floor_id"])
		or not _integer_in_range(value["floor_index"], 0, 4)
		or not _matches(STABLE_ID_PATTERN, value["node_id"])
		or not _matches(STABLE_ID_PATTERN, value["event_id"])
		or typeof(value["repeat_policy"]) != TYPE_STRING
		or not REPEAT_POLICIES.has(str(value["repeat_policy"]))
	):
		return {}
	return {
		"floor_id": str(value["floor_id"]),
		"floor_index": int(value["floor_index"]),
		"node_id": str(value["node_id"]),
		"event_id": str(value["event_id"]),
		"repeat_policy": str(value["repeat_policy"]),
	}


func _normalize_assignment(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, ASSIGNMENT_FIELDS):
		return {}
	var base := {
		"floor_id": value.get("floor_id"),
		"floor_index": value.get("floor_index"),
		"node_id": value.get("node_id"),
		"event_id": value.get("event_id"),
		"repeat_policy": value.get("repeat_policy"),
	}
	var normalized_base := _normalize_assignment_input(base)
	if normalized_base.is_empty() or typeof(value["phase"]) != TYPE_STRING or not PHASES.has(str(value["phase"])):
		return {}
	for field: String in ["option_id", "outcome_id", "outcome_key", "result_key", "transaction_id"]:
		if typeof(value[field]) != TYPE_STRING:
			return {}
	var phase := str(value["phase"])
	var option_id := str(value["option_id"])
	var outcome_id := str(value["outcome_id"])
	var outcome_key := str(value["outcome_key"])
	var result_key := str(value["result_key"])
	var transaction_id := str(value["transaction_id"])
	if phase == "open":
		if not option_id.is_empty() or not outcome_id.is_empty() or not outcome_key.is_empty() or not result_key.is_empty() or not transaction_id.is_empty():
			return {}
	else:
		if (
			not _matches(STABLE_ID_PATTERN, option_id)
			or not _matches(STABLE_ID_PATTERN, outcome_id)
			or not _matches(LOCALIZATION_KEY_PATTERN, outcome_key)
			or not _matches(TRANSACTION_ID_PATTERN, transaction_id)
		):
			return {}
		if phase in ["resolved", "dismissed"]:
			if not _matches(LOCALIZATION_KEY_PATTERN, result_key):
				return {}
		elif not result_key.is_empty():
			return {}
	normalized_base["phase"] = phase
	normalized_base["option_id"] = option_id
	normalized_base["outcome_id"] = outcome_id
	normalized_base["outcome_key"] = outcome_key
	normalized_base["result_key"] = result_key
	normalized_base["transaction_id"] = transaction_id
	return normalized_base


func _normalize_pending_transaction(
	value: Dictionary,
	assignments: Dictionary,
	current_revision: int,
	completed: Array[String]
) -> Dictionary:
	if not _has_exact_fields(value, TRANSACTION_FIELDS):
		return {}
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != TRANSACTION_SCHEMA_ID
		or not _matches(TRANSACTION_ID_PATTERN, value["transaction_id"])
		or completed.has(str(value["transaction_id"]))
		or not _valid_node_key(str(value["node_key"]))
		or not assignments.has(str(value["node_key"]))
		or not _matches(STABLE_ID_PATTERN, value["event_id"])
		or not _matches(STABLE_ID_PATTERN, value["option_id"])
		or not _matches(STABLE_ID_PATTERN, value["outcome_id"])
		or not _matches(LOCALIZATION_KEY_PATTERN, value["outcome_key"])
		or not _integer_in_range(value["expected_revision"], 0, MAX_REVISION)
		or int(value["expected_revision"]) + 1 != current_revision
		or not value["before"] is Dictionary
	):
		return {}
	var before := _normalize_snapshot(value["before"] as Dictionary, false)
	if before.is_empty() or int(before["revision"]) != int(value["expected_revision"]):
		return {}
	var node_key := str(value["node_key"])
	var current_assignment := assignments[node_key] as Dictionary
	if (
		str(current_assignment["event_id"]) != str(value["event_id"])
		or str(current_assignment["option_id"]) != str(value["option_id"])
		or str(current_assignment["outcome_id"]) != str(value["outcome_id"])
		or str(current_assignment["outcome_key"]) != str(value["outcome_key"])
		or str(current_assignment["transaction_id"]) != str(value["transaction_id"])
	):
		return {}
	var before_assignments := before["selected_event_by_node"] as Dictionary
	if not before_assignments.has(node_key):
		return {}
	var before_assignment := before_assignments[node_key] as Dictionary
	if str(before_assignment["phase"]) != "open" or str(before_assignment["event_id"]) != str(value["event_id"]):
		return {}
	return {
		"schema_id": TRANSACTION_SCHEMA_ID,
		"transaction_id": str(value["transaction_id"]),
		"node_key": node_key,
		"event_id": str(value["event_id"]),
		"option_id": str(value["option_id"]),
		"outcome_id": str(value["outcome_id"]),
		"outcome_key": str(value["outcome_key"]),
		"expected_revision": int(value["expected_revision"]),
		"before": before.duplicate(true),
	}


func _normalize_reward_input(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, REWARD_INPUT_FIELDS):
		return {}
	if (
		not _matches(TRANSACTION_ID_PATTERN, value["continuation_id"])
		or not _matches(STABLE_ID_PATTERN, value["pool_id"])
		or not _integer_in_range(value["count"], 1, 16)
	):
		return {}
	return {
		"continuation_id": str(value["continuation_id"]),
		"pool_id": str(value["pool_id"]),
		"count": int(value["count"]),
	}


func _normalize_pending_reward(value: Dictionary, ticket: Dictionary) -> Dictionary:
	if value.is_empty():
		return {}
	if not _has_exact_fields(value, REWARD_FIELDS):
		return {}
	var input := {
		"continuation_id": value.get("continuation_id"),
		"pool_id": value.get("pool_id"),
		"count": value.get("count"),
	}
	var normalized := _normalize_reward_input(input)
	if normalized.is_empty() or not _pending_identity_matches(value, ticket):
		return {}
	return {
		"transaction_id": str(ticket["transaction_id"]),
		"node_key": str(ticket["node_key"]),
		"event_id": str(ticket["event_id"]),
		"continuation_id": str(normalized["continuation_id"]),
		"pool_id": str(normalized["pool_id"]),
		"count": int(normalized["count"]),
	}


func _normalize_encounter_input(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, ENCOUNTER_INPUT_FIELDS):
		return {}
	if (
		not _matches(TRANSACTION_ID_PATTERN, value["continuation_id"])
		or not _matches(STABLE_ID_PATTERN, value["encounter_id"])
	):
		return {}
	return {
		"continuation_id": str(value["continuation_id"]),
		"encounter_id": str(value["encounter_id"]),
	}


func _normalize_pending_encounter(value: Dictionary, ticket: Dictionary) -> Dictionary:
	if value.is_empty():
		return {}
	if not _has_exact_fields(value, ENCOUNTER_FIELDS):
		return {}
	var input := {
		"continuation_id": value.get("continuation_id"),
		"encounter_id": value.get("encounter_id"),
	}
	var normalized := _normalize_encounter_input(input)
	if normalized.is_empty() or not _pending_identity_matches(value, ticket):
		return {}
	return {
		"transaction_id": str(ticket["transaction_id"]),
		"node_key": str(ticket["node_key"]),
		"event_id": str(ticket["event_id"]),
		"continuation_id": str(normalized["continuation_id"]),
		"encounter_id": str(normalized["encounter_id"]),
	}


func _normalize_resolution(value: Dictionary, current_transaction_id: String) -> Dictionary:
	if not _has_exact_fields(value, RESOLUTION_FIELDS):
		return {}
	if not _matches(LOCALIZATION_KEY_PATTERN, value["result_key"]) or not value["narrative_flags"] is Dictionary or not value["temporary_modifiers"] is Array:
		return {}
	var flags := _normalize_flags(value["narrative_flags"] as Dictionary)
	if flags.is_empty() and not (value["narrative_flags"] as Dictionary).is_empty():
		return {}
	var allowed_sources := _completed_transaction_ids.duplicate()
	allowed_sources.append(current_transaction_id)
	allowed_sources.sort()
	var modifiers := _normalize_modifiers(
		value["temporary_modifiers"] as Array, allowed_sources, current_transaction_id
	)
	if modifiers.is_empty() and not (value["temporary_modifiers"] as Array).is_empty():
		return {}
	return {
		"result_key": str(value["result_key"]),
		"narrative_flags": flags.duplicate(true),
		"temporary_modifiers": modifiers.duplicate(true),
	}


func _normalize_flags(value: Dictionary) -> Dictionary:
	var keys: Array[String] = []
	for key_value: Variant in value.keys():
		if typeof(key_value) != TYPE_STRING or not _matches(STABLE_ID_PATTERN, key_value) or typeof(value[key_value]) != TYPE_BOOL:
			return {}
		keys.append(str(key_value))
	keys.sort()
	var normalized: Dictionary = {}
	for key: String in keys:
		normalized[key] = bool(value[key])
	return normalized


func _normalize_modifiers(
	value: Array,
	allowed_transaction_ids: Array[String],
	current_transaction_id: String
) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	var identities: Dictionary = {}
	for entry_value: Variant in value:
		if not entry_value is Dictionary:
			return []
		var entry := entry_value as Dictionary
		if not _has_exact_fields(entry, MODIFIER_FIELDS):
			return []
		if (
			not _matches(STABLE_ID_PATTERN, entry["modifier_id"])
			or not _integer_in_range(entry["duration_rooms"], 1, 999)
			or not _finite_in_range(entry["magnitude"], -100.0, 100.0)
			or is_zero_approx(float(entry["magnitude"]))
			or not _matches(TRANSACTION_ID_PATTERN, entry["source_transaction_id"])
			or (not allowed_transaction_ids.has(str(entry["source_transaction_id"])) and str(entry["source_transaction_id"]) != current_transaction_id)
		):
			return []
		var identity := "%s:%s" % [str(entry["modifier_id"]), str(entry["source_transaction_id"])]
		if identities.has(identity):
			return []
		identities[identity] = true
		normalized.append({
			"modifier_id": str(entry["modifier_id"]),
			"duration_rooms": int(entry["duration_rooms"]),
			"magnitude": float(entry["magnitude"]),
			"source_transaction_id": str(entry["source_transaction_id"]),
		})
	normalized.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_id := "%s:%s" % [left["modifier_id"], left["source_transaction_id"]]
			var right_id := "%s:%s" % [right["modifier_id"], right["source_transaction_id"]]
			return left_id < right_id
	)
	return normalized


func _normalize_outcomes(value: Array, assignments: Dictionary) -> Array[Dictionary]:
	var normalized: Array[Dictionary] = []
	var transaction_ids: Dictionary = {}
	for entry_value: Variant in value:
		if not entry_value is Dictionary:
			return []
		var entry := entry_value as Dictionary
		if (
			not _has_exact_fields(entry, OUTCOME_FIELDS)
			or not _matches(TRANSACTION_ID_PATTERN, entry["transaction_id"])
			or transaction_ids.has(str(entry["transaction_id"]))
			or not _valid_node_key(str(entry["node_key"]))
			or not assignments.has(str(entry["node_key"]))
			or not _matches(STABLE_ID_PATTERN, entry["event_id"])
			or not _matches(STABLE_ID_PATTERN, entry["option_id"])
			or not _matches(STABLE_ID_PATTERN, entry["outcome_id"])
			or not _matches(LOCALIZATION_KEY_PATTERN, entry["outcome_key"])
			or not _matches(LOCALIZATION_KEY_PATTERN, entry["result_key"])
			or not _integer_in_range(entry["revision"], 1, MAX_REVISION)
			or typeof(entry["dismissed"]) != TYPE_BOOL
		):
			return []
		var assignment := assignments[str(entry["node_key"])] as Dictionary
		var expected_phase := "dismissed" if bool(entry["dismissed"]) else "resolved"
		if (
			str(assignment["phase"]) != expected_phase
			or str(assignment["event_id"]) != str(entry["event_id"])
			or str(assignment["option_id"]) != str(entry["option_id"])
			or str(assignment["outcome_id"]) != str(entry["outcome_id"])
			or str(assignment["outcome_key"]) != str(entry["outcome_key"])
			or str(assignment["result_key"]) != str(entry["result_key"])
			or str(assignment["transaction_id"]) != str(entry["transaction_id"])
		):
			return []
		transaction_ids[str(entry["transaction_id"])] = true
		normalized.append({
			"transaction_id": str(entry["transaction_id"]),
			"node_key": str(entry["node_key"]),
			"event_id": str(entry["event_id"]),
			"option_id": str(entry["option_id"]),
			"outcome_id": str(entry["outcome_id"]),
			"outcome_key": str(entry["outcome_key"]),
			"result_key": str(entry["result_key"]),
			"revision": int(entry["revision"]),
			"dismissed": bool(entry["dismissed"]),
		})
	var sorted := normalized.duplicate(true)
	_sort_outcomes(sorted)
	if sorted != normalized:
		return []
	return normalized


func _active_ticket_error(ticket: Dictionary, allowed_phases: Array[String]) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if _pending_transaction.is_empty():
		return _failure(&"TRANSACTION_NOT_FOUND")
	if ticket != _pending_transaction:
		return _failure(&"TRANSACTION_STALE")
	var node_key := str(_pending_transaction["node_key"])
	if not _selected_event_by_node.has(node_key):
		return _failure(&"INTEGRITY_FAILURE")
	var phase := str((_selected_event_by_node[node_key] as Dictionary)["phase"])
	if not allowed_phases.has(phase):
		return _failure(&"INVALID_PHASE", {"phase": phase})
	return {}


func _valid_receipt(value: Dictionary) -> bool:
	if not _has_exact_fields(value, RECEIPT_FIELDS):
		return false
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != RECEIPT_SCHEMA_ID
		or not _matches(TRANSACTION_ID_PATTERN, value["transaction_id"])
		or not value["ticket"] is Dictionary
		or not value["before"] is Dictionary
		or not value["after"] is Dictionary
	):
		return false
	var ticket := value["ticket"] as Dictionary
	if not _has_exact_fields(ticket, TRANSACTION_FIELDS):
		return false
	if (
		str(ticket.get("transaction_id", "")) != str(value["transaction_id"])
		or ticket.get("before", {}) != value["before"]
		or _normalize_snapshot(value["before"], false).is_empty()
		or _normalize_snapshot(value["after"], false).is_empty()
	):
		return false
	var after := value["after"] as Dictionary
	if not (after["completed_transaction_ids"] as Array).has(str(value["transaction_id"])):
		return false
	for outcome_value: Variant in after["resolved_outcomes"]:
		var outcome := outcome_value as Dictionary
		if str(outcome["transaction_id"]) == str(value["transaction_id"]):
			return (
				str(outcome["node_key"]) == str(ticket["node_key"])
				and str(outcome["event_id"]) == str(ticket["event_id"])
				and str(outcome["option_id"]) == str(ticket["option_id"])
				and str(outcome["outcome_id"]) == str(ticket["outcome_id"])
				and str(outcome["outcome_key"]) == str(ticket["outcome_key"])
			)
	return false


func _pending_identity_matches(value: Dictionary, ticket: Dictionary) -> bool:
	return (
		typeof(value.get("transaction_id")) == TYPE_STRING
		and str(value["transaction_id"]) == str(ticket["transaction_id"])
		and typeof(value.get("node_key")) == TYPE_STRING
		and str(value["node_key"]) == str(ticket["node_key"])
		and typeof(value.get("event_id")) == TYPE_STRING
		and str(value["event_id"]) == str(ticket["event_id"])
	)


func _derived_histories(assignments: Dictionary) -> Dictionary:
	var seen_run: Array[String] = []
	var seen_floor: Array[String] = []
	for assignment_value: Variant in assignments.values():
		var assignment := assignment_value as Dictionary
		var event_id := str(assignment["event_id"])
		var floor_key := _floor_event_key(assignment)
		if not seen_run.has(event_id):
			seen_run.append(event_id)
		if not seen_floor.has(floor_key):
			seen_floor.append(floor_key)
	seen_run.sort()
	seen_floor.sort()
	return {"seen_run_event_ids": seen_run, "seen_floor_event_keys": seen_floor}


func _normalize_sorted_ids(value: Variant, pattern: String) -> Array[String]:
	if not value is Array:
		return []
	var normalized: Array[String] = []
	for entry: Variant in value as Array:
		if not _matches(pattern, entry) or normalized.has(str(entry)):
			return []
		normalized.append(str(entry))
	var sorted := normalized.duplicate()
	sorted.sort()
	if sorted != normalized:
		return []
	return normalized


func _apply_snapshot(value: Dictionary) -> void:
	_selected_event_by_node = (value["selected_event_by_node"] as Dictionary).duplicate(true)
	_seen_run_event_ids.clear()
	for entry: Variant in value["seen_run_event_ids"]:
		_seen_run_event_ids.append(str(entry))
	_seen_floor_event_keys.clear()
	for entry: Variant in value["seen_floor_event_keys"]:
		_seen_floor_event_keys.append(str(entry))
	_resolved_outcomes.clear()
	for entry: Variant in value["resolved_outcomes"]:
		_resolved_outcomes.append((entry as Dictionary).duplicate(true))
	_pending_transaction = (value["pending_transaction"] as Dictionary).duplicate(true)
	_pending_reward = (value["pending_reward"] as Dictionary).duplicate(true)
	_pending_encounter = (value["pending_encounter"] as Dictionary).duplicate(true)
	_completed_transaction_ids.clear()
	for entry: Variant in value["completed_transaction_ids"]:
		_completed_transaction_ids.append(str(entry))
	_narrative_flags = (value["narrative_flags"] as Dictionary).duplicate(true)
	_temporary_modifiers.clear()
	for entry: Variant in value["temporary_modifiers"]:
		_temporary_modifiers.append((entry as Dictionary).duplicate(true))
	_revision = int(value["revision"])


func _sort_assignment_dictionary() -> void:
	var keys: Array[String] = []
	for key: Variant in _selected_event_by_node.keys():
		keys.append(str(key))
	keys.sort()
	var sorted: Dictionary = {}
	for key: String in keys:
		sorted[key] = (_selected_event_by_node[key] as Dictionary).duplicate(true)
	_selected_event_by_node = sorted


func _sort_outcomes(outcomes: Array[Dictionary]) -> void:
	outcomes.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return str(left["transaction_id"]) < str(right["transaction_id"])
	)


func _outcome_index(transaction_id: String) -> int:
	for index: int in range(_resolved_outcomes.size()):
		if str(_resolved_outcomes[index]["transaction_id"]) == transaction_id:
			return index
	return -1


func _node_key(value: Dictionary) -> String:
	return "%s:%s" % [str(value.get("floor_id", "")), str(value.get("node_id", ""))]


func _floor_event_key(value: Dictionary) -> String:
	return "%s:%s" % [str(value.get("floor_id", "")), str(value.get("event_id", ""))]


func _valid_node_key(value: String) -> bool:
	if value.count(":") != 1:
		return false
	var parts := value.split(":", false, 1)
	return parts.size() == 2 and _matches(STABLE_ID_PATTERN, parts[0]) and _matches(STABLE_ID_PATTERN, parts[1])


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


func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum


func _finite_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) >= minimum
		and float(value) <= maximum
	)


func _stale_revision(expected_revision: int) -> Dictionary:
	return _failure(
		&"STALE_REVISION",
		{"expected_revision": expected_revision, "actual_revision": _revision},
	)


func _success(payload: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": &"OK"}
	for key: Variant in payload.keys():
		result[key] = payload[key]
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
