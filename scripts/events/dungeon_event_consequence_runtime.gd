class_name DungeonEventConsequenceRuntime
extends RefCounted

const DungeonEventDefinitionScript := preload(
	"res://scripts/dungeon/dungeon_event_definition.gd"
)
const SCHEMA_ID := "planewalker.dungeon_event_consequence_runtime"
const TICKET_SCHEMA_ID := "dungeon_event_consequence_ticket_v1"
const RECEIPT_SCHEMA_ID := "dungeon_event_consequence_receipt_v1"
const PARTICIPANT_KEYS: Array[String] = [
	"resource", "health", "economy", "modifier", "route", "event_state",
]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id", "schema_version", "completed_transaction_ids", "publications",
	"integrity_failure", "participant_snapshots", "revision",
]
const PUBLICATION_FIELDS: Array[String] = [
	"transaction_id", "phase", "result_key", "pending_kind",
]
const INTEGRITY_FIELDS: Array[String] = ["transaction_id", "stage", "code"]
const CONTEXT_FIELDS: Array[String] = ["event_ticket", "result_key"]
const TICKET_FIELDS: Array[String] = [
	"schema_id", "owner_instance_id", "transaction_id", "consequences", "context",
	"participant_tickets", "before", "pending_reward", "pending_encounter", "fingerprint",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_id", "owner_instance_id", "transaction_id", "ticket_fingerprint",
	"participant_receipts", "event_rollback", "before", "after", "fingerprint",
]

var _configured := false
var _resource: Object
var _health: Object
var _economy: Object
var _modifier: Object
var _route: Object
var _event_state: Object
var _completed_transaction_ids: Array[String] = []
var _publications: Array[Dictionary] = []
var _integrity_failure: Dictionary = {}
var _revision := 0
var _committed_rollback_receipt: Dictionary = {}
var _capability_secret := ""


func configure(
	resource: Object,
	health: Object,
	economy: Object,
	modifier: Object,
	route: Object,
	event_state: Object
) -> bool:
	if (
		not _participant_valid(resource, [&"snapshot", &"can_restore_snapshot", &"restore_snapshot", &"prepare_delta", &"commit_delta", &"rollback_delta"])
		or not _participant_valid(health, [&"snapshot", &"can_restore_snapshot", &"restore_snapshot", &"prepare_delta", &"commit_delta", &"rollback_delta"])
		or not _participant_valid(economy, [&"snapshot", &"can_restore_snapshot", &"restore_snapshot", &"prepare_transaction", &"commit_transaction", &"rollback_transaction"])
		or not _participant_valid(modifier, [&"snapshot", &"can_restore_snapshot", &"restore_snapshot", &"prepare_operations", &"commit_operations", &"rollback_operations"])
		or not _participant_valid(route, [&"snapshot", &"can_restore_snapshot", &"restore_snapshot", &"prepare_operations", &"commit_operations", &"rollback_operations"])
		or not _participant_valid(event_state, [&"snapshot", &"can_restore_snapshot", &"restore_snapshot", &"mark_pending_reward", &"mark_pending_encounter", &"resolve_option", &"rollback_transaction"])
	):
		return false
	_resource = resource
	_health = health
	_economy = economy
	_modifier = modifier
	_route = route
	_event_state = event_state
	_completed_transaction_ids.clear()
	_publications.clear()
	_integrity_failure.clear()
	_revision = 0
	_committed_rollback_receipt.clear()
	_capability_secret = _new_capability_secret()
	_configured = true
	var current := snapshot()
	if current.is_empty() or not can_restore_snapshot(current):
		_configured = false
		return false
	return true


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": 1,
		"completed_transaction_ids": _completed_transaction_ids.duplicate(),
		"publications": _publications.duplicate(true),
		"integrity_failure": _integrity_failure.duplicate(true),
		"participant_snapshots": _participant_snapshots(),
		"revision": _revision,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	return _configured and not _normalize_snapshot(value).is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	var normalized := _normalize_snapshot(value)
	if normalized.is_empty():
		return false
	var before := snapshot()
	if not _restore_participants(normalized["participant_snapshots"] as Dictionary):
		_restore_participants(before["participant_snapshots"] as Dictionary)
		return false
	_apply_internal_snapshot(normalized)
	_committed_rollback_receipt.clear()
	_capability_secret = _new_capability_secret()
	if snapshot() != normalized:
		_restore_participants(before["participant_snapshots"] as Dictionary)
		_apply_internal_snapshot(before)
		return false
	return true


func prepare_consequences(
	transaction_id: String,
	consequences: Array,
	context: Dictionary
) -> Dictionary:
	var availability := _availability_error(transaction_id)
	if not availability.is_empty():
		return availability
	if not _exact_fields(context, CONTEXT_FIELDS):
		return _failure(&"INVALID_CONTEXT")
	if not context.get("event_ticket") is Dictionary or typeof(context.get("result_key")) != TYPE_STRING:
		return _failure(&"INVALID_CONTEXT")
	var event_ticket := context["event_ticket"] as Dictionary
	if (
		str(event_ticket.get("transaction_id", "")) != transaction_id
		or str(context["result_key"]).is_empty()
		or str(context["result_key"]) != str(event_ticket.get("outcome_key", ""))
	):
		return _failure(&"INVALID_CONTEXT")
	var event_snapshot := _dictionary(_event_state.call("snapshot"))
	if event_snapshot.is_empty() or event_snapshot.get("pending_transaction", {}) != event_ticket:
		return _failure(&"EVENT_TICKET_STALE")
	var normalized := _normalize_consequences(consequences)
	if normalized.is_empty():
		return _failure(&"INVALID_CONSEQUENCE")
	var partitioned := _partition(normalized)
	if not bool(partitioned.get("ok", false)):
		return _failure(&"INVALID_CONSEQUENCE", partitioned.get("context", {}))
	var before := snapshot()
	var participant_tickets := {
		"resource": {}, "health": {}, "economy": {}, "modifier": {}, "route": {},
	}
	var unsigned := {
		"schema_id": TICKET_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"consequences": normalized,
		"context": context.duplicate(true),
		"participant_tickets": participant_tickets,
		"before": before,
		"pending_reward": (partitioned["reward"] as Dictionary).duplicate(true),
		"pending_encounter": (partitioned["encounter"] as Dictionary).duplicate(true),
	}
	var ticket := unsigned.duplicate(true)
	ticket["fingerprint"] = _digest(unsigned)
	return _success({"ticket": ticket})


func commit_consequences(ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _integrity_failure.is_empty():
		return _failure(&"INTEGRITY_TERMINAL", _integrity_failure)
	if not _valid_ticket(ticket):
		return _failure(&"TICKET_INVALID")
	var transaction_id := str(ticket["transaction_id"])
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"ALREADY_COMMITTED")
	var before := ticket["before"] as Dictionary
	if snapshot() != before:
		return _failure(&"PARTICIPANT_STALE")
	var committed: Array[Dictionary] = []
	for participant: String in ["health", "resource", "economy", "route", "modifier"]:
		var prepared := _prepare_participant(participant, ticket)
		if str(prepared.get("code", "")) == "SKIPPED":
			continue
		if not bool(prepared.get("ok", false)):
			return _commit_failure(transaction_id, participant, prepared, committed, {}, before)
		var participant_ticket := _nested_dictionary(prepared, "ticket")
		if participant_ticket.is_empty():
			return _commit_failure(transaction_id, participant, _failure(&"MISSING_TICKET"), committed, {}, before)
		var result := _commit_participant(participant, participant_ticket)
		if not bool(result.get("ok", false)):
			var aborted := _abort_current_prepare(participant, participant_ticket)
			return _commit_failure(transaction_id, participant, result, committed, {}, before, aborted)
		var receipt := _nested_dictionary(result, "receipt")
		if receipt.is_empty():
			return _commit_failure(transaction_id, participant, _failure(&"MISSING_RECEIPT"), committed, {}, before)
		committed.append({"participant": participant, "receipt": receipt})
	var event_ticket := (ticket["context"] as Dictionary)["event_ticket"] as Dictionary
	var event_result: Dictionary
	var phase := "resolved"
	var pending_kind := ""
	if not (ticket["pending_reward"] as Dictionary).is_empty():
		phase = "pending_reward"
		pending_kind = "reward"
		var reward := ticket["pending_reward"] as Dictionary
		event_result = _dictionary(_event_state.call("mark_pending_reward", event_ticket.duplicate(true), {
			"continuation_id": _continuation_id(transaction_id, "reward"),
			"pool_id": str(reward["pool_id"]),
			"count": int(reward["count"]),
		}))
	elif not (ticket["pending_encounter"] as Dictionary).is_empty():
		phase = "pending_encounter"
		pending_kind = "encounter"
		var encounter := ticket["pending_encounter"] as Dictionary
		event_result = _dictionary(_event_state.call("mark_pending_encounter", event_ticket.duplicate(true), {
			"continuation_id": _continuation_id(transaction_id, "encounter"),
			"encounter_id": str(encounter["encounter_id"]),
		}))
	else:
		var modifier_snapshot := _dictionary(_modifier.call("snapshot"))
		event_result = _dictionary(_event_state.call("resolve_option", event_ticket.duplicate(true), {
			"result_key": str((ticket["context"] as Dictionary)["result_key"]),
			"narrative_flags": (modifier_snapshot.get("narrative_flags", {}) as Dictionary).duplicate(true),
			"temporary_modifiers": (modifier_snapshot.get("temporary_modifiers", []) as Array).duplicate(true),
		}))
	if not bool(event_result.get("ok", false)):
		return _commit_failure(transaction_id, "event_state", event_result, committed, event_ticket, before)
	var event_rollback: Dictionary = event_ticket.duplicate(true)
	if event_result.get("receipt") is Dictionary:
		event_rollback = (event_result["receipt"] as Dictionary).duplicate(true)
	_completed_transaction_ids.append(transaction_id)
	_completed_transaction_ids.sort()
	_publications.append({
		"transaction_id": transaction_id,
		"phase": phase,
		"result_key": str((ticket["context"] as Dictionary)["result_key"]),
		"pending_kind": pending_kind,
	})
	_publications.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["transaction_id"]) < str(right["transaction_id"])
	)
	_revision += 1
	var after := snapshot()
	var unsigned_receipt := {
		"schema_id": RECEIPT_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"ticket_fingerprint": str(ticket["fingerprint"]),
		"participant_receipts": committed.duplicate(true),
		"event_rollback": event_rollback,
		"before": before.duplicate(true),
		"after": after.duplicate(true),
	}
	var receipt := unsigned_receipt.duplicate(true)
	receipt["fingerprint"] = _digest(unsigned_receipt)
	_committed_rollback_receipt = receipt.duplicate(true)
	return _success({"receipt": receipt, "publication": _publications[-1].duplicate(true)})


func rollback_consequences(receipt: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _integrity_failure.is_empty():
		return _failure(&"INTEGRITY_TERMINAL", _integrity_failure)
	if not _valid_receipt(receipt) or receipt != _committed_rollback_receipt or snapshot() != receipt["after"]:
		return _failure(&"RECEIPT_STALE")
	var transaction_id := str(receipt["transaction_id"])
	var before := receipt["before"] as Dictionary
	var event_rollback := receipt["event_rollback"] as Dictionary
	var ok := bool(_dictionary(_event_state.call("rollback_transaction", event_rollback.duplicate(true))).get("ok", false))
	var participant_receipts := receipt["participant_receipts"] as Array
	for index: int in range(participant_receipts.size() - 1, -1, -1):
		var entry := participant_receipts[index] as Dictionary
		var result := _rollback_participant(str(entry["participant"]), entry["receipt"] as Dictionary)
		ok = bool(result.get("ok", false)) and ok
	if not ok or not _restore_participants(before["participant_snapshots"] as Dictionary):
		_set_integrity_failure(transaction_id, "explicit_rollback", &"COMPENSATION_FAILED")
		return _failure(&"INTEGRITY_TERMINAL", _integrity_failure)
	_apply_internal_snapshot(before)
	_committed_rollback_receipt.clear()
	if snapshot() != before:
		_set_integrity_failure(transaction_id, "explicit_rollback_verify", &"BYTE_RESTORE_FAILED")
		return _failure(&"INTEGRITY_TERMINAL", _integrity_failure)
	return _success({"transaction_id": transaction_id, "rolled_back": true})


func _commit_failure(
	transaction_id: String,
	stage: String,
	cause: Dictionary,
	committed: Array[Dictionary],
	event_rollback: Dictionary,
	before: Dictionary,
	current_abort_ok: bool = true
) -> Dictionary:
	var compensated := current_abort_ok
	if not event_rollback.is_empty():
		compensated = bool(_dictionary(_event_state.call("rollback_transaction", event_rollback.duplicate(true))).get("ok", false))
	for index: int in range(committed.size() - 1, -1, -1):
		var entry := committed[index]
		var result := _rollback_participant(str(entry["participant"]), entry["receipt"] as Dictionary)
		compensated = bool(result.get("ok", false)) and compensated
	var restored := _restore_participants(before["participant_snapshots"] as Dictionary)
	compensated = compensated and restored and snapshot() == before
	if not compensated:
		_set_integrity_failure(transaction_id, stage, &"COMPENSATION_FAILED")
		return _failure(&"INTEGRITY_TERMINAL", {"stage": stage, "cause": cause, "integrity": _integrity_failure})
	return _failure(&"PARTICIPANT_COMMIT_FAILED", {"participant": stage, "cause": cause})


func _commit_participant(participant: String, ticket: Dictionary) -> Dictionary:
	match participant:
		"health": return _dictionary(_health.call("commit_delta", ticket.duplicate(true)))
		"resource": return _dictionary(_resource.call("commit_delta", ticket.duplicate(true)))
		"economy": return _dictionary(_economy.call("commit_transaction", ticket.duplicate(true)))
		"route": return _dictionary(_route.call("commit_operations", ticket.duplicate(true)))
		"modifier": return _dictionary(_modifier.call("commit_operations", ticket.duplicate(true)))
	return _failure(&"UNKNOWN_PARTICIPANT")


func _prepare_participant(participant: String, ticket: Dictionary) -> Dictionary:
	var partitioned := _partition(ticket["consequences"] as Array[Dictionary])
	if not bool(partitioned.get("ok", false)):
		return _failure(&"INVALID_CONSEQUENCE")
	var transaction_id := str(ticket["transaction_id"])
	var participant_snapshots := (ticket["before"] as Dictionary)["participant_snapshots"] as Dictionary
	match participant:
		"health":
			if (partitioned["health"] as Array).is_empty():
				return {"ok": true, "code": &"SKIPPED", "context": {}}
			var operation := (partitioned["health"] as Array)[0] as Dictionary
			var arguments := operation["arguments"] as Dictionary
			return _dictionary(_health.call(
				"prepare_delta", transaction_id, float(arguments["amount"]),
				bool(arguments["nonlethal"]), int((participant_snapshots["health"] as Dictionary)["revision"])
			))
		"resource":
			if (partitioned["resource"] as Array).is_empty():
				return {"ok": true, "code": &"SKIPPED", "context": {}}
			var operation := (partitioned["resource"] as Array)[0] as Dictionary
			var arguments := operation["arguments"] as Dictionary
			return _dictionary(_resource.call(
				"prepare_delta", transaction_id, StringName(arguments["resource"]),
				int(arguments["amount"]), int((participant_snapshots["resource"] as Dictionary)["revision"])
			))
		"economy":
			if (partitioned["economy"] as Array).is_empty():
				return {"ok": true, "code": &"SKIPPED", "context": {}}
			var operation := (partitioned["economy"] as Array)[0] as Dictionary
			var arguments := operation["arguments"] as Dictionary
			return _dictionary(_economy.call(
				"prepare_transaction", transaction_id, int(arguments["amount"]),
				int((participant_snapshots["economy"] as Dictionary)["revision"]),
				{"operation": "gold_delta", "source_id": "dungeon_event"}
			))
		"route":
			if (partitioned["route"] as Array).is_empty():
				return {"ok": true, "code": &"SKIPPED", "context": {}}
			return _dictionary(_route.call(
				"prepare_operations", transaction_id, (partitioned["route"] as Array).duplicate(true),
				int((participant_snapshots["route"] as Dictionary)["revision"])
			))
		"modifier":
			if (partitioned["modifier"] as Array).is_empty():
				return {"ok": true, "code": &"SKIPPED", "context": {}}
			return _dictionary(_modifier.call(
				"prepare_operations", transaction_id, (partitioned["modifier"] as Array).duplicate(true),
				int((participant_snapshots["modifier"] as Dictionary)["revision"])
			))
	return _failure(&"UNKNOWN_PARTICIPANT")


func _abort_current_prepare(participant: String, ticket: Dictionary) -> bool:
	if participant != "economy":
		return true
	return bool(_dictionary(_economy.call("rollback_transaction", ticket.duplicate(true))).get("ok", false))


func _rollback_participant(participant: String, receipt: Dictionary) -> Dictionary:
	match participant:
		"health": return _dictionary(_health.call("rollback_delta", receipt.duplicate(true)))
		"resource": return _dictionary(_resource.call("rollback_delta", receipt.duplicate(true)))
		"economy": return _dictionary(_economy.call("rollback_transaction", receipt.duplicate(true)))
		"route": return _dictionary(_route.call("rollback_operations", receipt.duplicate(true)))
		"modifier": return _dictionary(_modifier.call("rollback_operations", receipt.duplicate(true)))
	return _failure(&"UNKNOWN_PARTICIPANT")


func _normalize_consequences(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Variant in value:
		if not entry is Dictionary or not _exact_fields(entry as Dictionary, ["operation", "arguments"]):
			return []
		var operation := str((entry as Dictionary).get("operation", ""))
		var arguments_value: Variant = (entry as Dictionary).get("arguments")
		if not DungeonEventDefinitionScript.CONSEQUENCE_OPERATIONS.has(operation) or not arguments_value is Dictionary:
			return []
		var arguments := arguments_value as Dictionary
		if not _valid_arguments(operation, arguments):
			return []
		result.append({"operation": operation, "arguments": arguments.duplicate(true)})
	return result


func _valid_arguments(operation: String, arguments: Dictionary) -> bool:
	match operation:
		"resource_delta":
			return _exact_fields(arguments, ["resource", "amount"]) and typeof(arguments.get("resource")) == TYPE_STRING and DungeonEventDefinitionScript.RESOURCE_IDS.has(str(arguments["resource"])) and typeof(arguments.get("amount")) == TYPE_INT and int(arguments["amount"]) != 0 and absi(int(arguments["amount"])) <= 9999
		"health_delta":
			return _exact_fields(arguments, ["amount", "nonlethal"]) and typeof(arguments.get("amount")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(arguments["amount"])) and not is_zero_approx(float(arguments["amount"])) and absf(float(arguments["amount"])) <= 9999.0 and typeof(arguments.get("nonlethal")) == TYPE_BOOL
		"reward_draft":
			return _exact_fields(arguments, ["pool_id", "count"]) and typeof(arguments.get("pool_id")) == TYPE_STRING and DungeonEventDefinitionScript.REWARD_POOL_IDS.has(str(arguments["pool_id"])) and typeof(arguments.get("count")) == TYPE_INT and int(arguments["count"]) >= 1 and int(arguments["count"]) <= 3
		"curse_add", "curse_remove":
			return _exact_fields(arguments, ["curse_id"]) and typeof(arguments.get("curse_id")) == TYPE_STRING and DungeonEventDefinitionScript.CURSE_IDS.has(str(arguments["curse_id"]))
		"temporary_modifier":
			return _exact_fields(arguments, ["modifier_id", "duration_rooms", "magnitude"]) and typeof(arguments.get("modifier_id")) == TYPE_STRING and DungeonEventDefinitionScript.MODIFIER_IDS.has(str(arguments["modifier_id"])) and typeof(arguments.get("duration_rooms")) == TYPE_INT and int(arguments["duration_rooms"]) >= 1 and int(arguments["duration_rooms"]) <= 5 and typeof(arguments.get("magnitude")) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(arguments["magnitude"])) and float(arguments["magnitude"]) > 0.0 and float(arguments["magnitude"]) <= 10.0
		"map_reveal":
			return _exact_fields(arguments, ["depth"]) and typeof(arguments.get("depth")) == TYPE_INT and int(arguments["depth"]) >= 1 and int(arguments["depth"]) <= 5
		"encounter_start":
			return _exact_fields(arguments, ["encounter_id"]) and typeof(arguments.get("encounter_id")) == TYPE_STRING and DungeonEventDefinitionScript.ENCOUNTER_ADAPTER_IDS.has(str(arguments["encounter_id"]))
		"route_skip":
			return _exact_fields(arguments, ["rooms"]) and typeof(arguments.get("rooms")) == TYPE_INT and int(arguments["rooms"]) >= 1 and int(arguments["rooms"]) <= 2
		"narrative_flag":
			return _exact_fields(arguments, ["flag", "value"]) and typeof(arguments.get("flag")) == TYPE_STRING and _valid_id(str(arguments["flag"])) and typeof(arguments.get("value")) == TYPE_BOOL
	return false


func _partition(consequences: Array[Dictionary]) -> Dictionary:
	var result := {
		"ok": true, "resource": [], "health": [], "economy": [], "modifier": [], "route": [],
		"reward": {}, "encounter": {}, "context": {},
	}
	for consequence: Dictionary in consequences:
		var operation := str(consequence["operation"])
		match operation:
			"resource_delta":
				var resource_id := str((consequence["arguments"] as Dictionary)["resource"])
				if resource_id == "gold":
					(result["economy"] as Array).append(consequence)
				else:
					(result["resource"] as Array).append(consequence)
			"health_delta": (result["health"] as Array).append(consequence)
			"curse_add", "curse_remove", "temporary_modifier", "narrative_flag": (result["modifier"] as Array).append(consequence)
			"map_reveal", "route_skip": (result["route"] as Array).append(consequence)
			"reward_draft":
				if not (result["reward"] as Dictionary).is_empty():
					return {"ok": false, "context": {"reason": "duplicate_reward"}}
				result["reward"] = (consequence["arguments"] as Dictionary).duplicate(true)
			"encounter_start":
				if not (result["encounter"] as Dictionary).is_empty():
					return {"ok": false, "context": {"reason": "duplicate_encounter"}}
				result["encounter"] = (consequence["arguments"] as Dictionary).duplicate(true)
	if (result["resource"] as Array).size() > 1 or (result["economy"] as Array).size() > 1 or (result["health"] as Array).size() > 1:
		return {"ok": false, "context": {"reason": "duplicate_scalar_authority"}}
	if not (result["reward"] as Dictionary).is_empty() and not (result["encounter"] as Dictionary).is_empty():
		return {"ok": false, "context": {"reason": "multiple_pending_kinds"}}
	return result


func _normalize_snapshot(value: Dictionary) -> Dictionary:
	if not _exact_fields(value, SNAPSHOT_FIELDS):
		return {}
	if (
		str(value.get("schema_id", "")) != SCHEMA_ID
		or typeof(value.get("schema_version")) != TYPE_INT
		or int(value["schema_version"]) != 1
		or not value.get("completed_transaction_ids") is Array
		or not value.get("publications") is Array
		or not value.get("integrity_failure") is Dictionary
		or not value.get("participant_snapshots") is Dictionary
		or typeof(value.get("revision")) != TYPE_INT
		or int(value["revision"]) < 0
	):
		return {}
	var completed := _normalize_ids(value["completed_transaction_ids"] as Array)
	if completed.size() != int(value["revision"]):
		return {}
	var publications := _normalize_publications(value["publications"] as Array, completed)
	if publications.size() != completed.size():
		return {}
	var integrity := value["integrity_failure"] as Dictionary
	if not integrity.is_empty() and (not _exact_fields(integrity, INTEGRITY_FIELDS) or not _valid_id(str(integrity.get("transaction_id", "")))):
		return {}
	var participants := value["participant_snapshots"] as Dictionary
	if not _exact_fields(participants, PARTICIPANT_KEYS) or not _participants_can_restore(participants):
		return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": 1,
		"completed_transaction_ids": completed,
		"publications": publications,
		"integrity_failure": integrity.duplicate(true),
		"participant_snapshots": participants.duplicate(true),
		"revision": int(value["revision"]),
	}


func _normalize_publications(value: Array, completed: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not entry is Dictionary or not _exact_fields(entry as Dictionary, PUBLICATION_FIELDS):
			return []
		var publication := entry as Dictionary
		var transaction_id := str(publication.get("transaction_id", ""))
		var phase := str(publication.get("phase", ""))
		var pending_kind := str(publication.get("pending_kind", ""))
		if (
			typeof(publication.get("transaction_id")) != TYPE_STRING
			or not completed.has(transaction_id)
			or seen.has(transaction_id)
			or typeof(publication.get("phase")) != TYPE_STRING
			or phase not in ["resolved", "pending_reward", "pending_encounter"]
			or typeof(publication.get("result_key")) != TYPE_STRING
			or not _valid_result_key(str(publication["result_key"]))
			or typeof(publication.get("pending_kind")) != TYPE_STRING
			or (phase == "resolved" and not pending_kind.is_empty())
			or (phase == "pending_reward" and pending_kind != "reward")
			or (phase == "pending_encounter" and pending_kind != "encounter")
		):
			return []
		seen[transaction_id] = true
		result.append(publication.duplicate(true))
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["transaction_id"]) < str(right["transaction_id"])
	)
	var publication_ids: Array[String] = []
	for publication: Dictionary in result:
		publication_ids.append(str(publication["transaction_id"]))
	if publication_ids != completed:
		return []
	return result


func _valid_ticket(value: Dictionary) -> bool:
	if not _exact_fields(value, TICKET_FIELDS):
		return false
	var unsigned := value.duplicate(true)
	unsigned.erase("fingerprint")
	return (
		str(value.get("schema_id", "")) == TICKET_SCHEMA_ID
		and int(value.get("owner_instance_id", 0)) == get_instance_id()
		and str(value.get("fingerprint", "")) == _digest(unsigned)
		and value.get("participant_tickets") is Dictionary
		and _exact_fields(value["participant_tickets"] as Dictionary, ["resource", "health", "economy", "modifier", "route"])
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
		and value.get("participant_receipts") is Array
		and value.get("event_rollback") is Dictionary
	)


func _participant_snapshots() -> Dictionary:
	return {
		"resource": _dictionary(_resource.call("snapshot")),
		"health": _dictionary(_health.call("snapshot")),
		"economy": _dictionary(_economy.call("snapshot")),
		"modifier": _dictionary(_modifier.call("snapshot")),
		"route": _dictionary(_route.call("snapshot")),
		"event_state": _dictionary(_event_state.call("snapshot")),
	}


func _participants_can_restore(value: Dictionary) -> bool:
	return (
		bool(_resource.call("can_restore_snapshot", (value["resource"] as Dictionary).duplicate(true)))
		and bool(_health.call("can_restore_snapshot", (value["health"] as Dictionary).duplicate(true)))
		and bool(_economy.call("can_restore_snapshot", (value["economy"] as Dictionary).duplicate(true)))
		and bool(_modifier.call("can_restore_snapshot", (value["modifier"] as Dictionary).duplicate(true)))
		and bool(_route.call("can_restore_snapshot", (value["route"] as Dictionary).duplicate(true)))
		and bool(_event_state.call("can_restore_snapshot", (value["event_state"] as Dictionary).duplicate(true)))
	)


func _restore_participants(value: Dictionary) -> bool:
	var ok := true
	for key: String in ["event_state", "modifier", "route", "economy", "resource", "health"]:
		var participant := _participant(key)
		var restored := bool(participant.call("restore_snapshot", (value[key] as Dictionary).duplicate(true)))
		ok = restored and ok
	return ok


func _participant(key: String) -> Object:
	match key:
		"resource": return _resource
		"health": return _health
		"economy": return _economy
		"modifier": return _modifier
		"route": return _route
		"event_state": return _event_state
	return null


func _apply_internal_snapshot(value: Dictionary) -> void:
	_completed_transaction_ids.clear()
	for entry: Variant in value["completed_transaction_ids"]:
		_completed_transaction_ids.append(str(entry))
	_publications.clear()
	for entry: Variant in value["publications"]:
		_publications.append((entry as Dictionary).duplicate(true))
	_integrity_failure = (value["integrity_failure"] as Dictionary).duplicate(true)
	_revision = int(value["revision"])


func _set_integrity_failure(transaction_id: String, stage: String, code: StringName) -> void:
	_integrity_failure = {"transaction_id": transaction_id, "stage": stage, "code": str(code)}


func _availability_error(transaction_id: String) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _integrity_failure.is_empty():
		return _failure(&"INTEGRITY_TERMINAL", _integrity_failure)
	if not _valid_id(transaction_id):
		return _failure(&"INVALID_TRANSACTION")
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"ALREADY_COMMITTED")
	return {}


func _participant_valid(value: Object, methods: Array[StringName]) -> bool:
	if value == null:
		return false
	for method: StringName in methods:
		if not value.has_method(method):
			return false
	return true


func _continuation_id(transaction_id: String, kind: String) -> String:
	return "continuation:%s:%s" % [transaction_id, kind]


func _normalize_ids(value: Array) -> Array[String]:
	var result: Array[String] = []
	for entry: Variant in value:
		if typeof(entry) != TYPE_STRING or not _valid_id(str(entry)) or result.has(str(entry)):
			return []
		result.append(str(entry))
	var sorted := result.duplicate()
	sorted.sort()
	return result if result == sorted else []


func _nested_dictionary(value: Dictionary, key: String) -> Dictionary:
	return (value.get(key, {}) as Dictionary).duplicate(true) if value.get(key) is Dictionary else {}


func _dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


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


func _valid_result_key(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile("^[A-Z][A-Z0-9_]{1,127}$") == OK and regex.search(value) != null


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
