class_name DungeonEventRuntime
extends RefCounted

const DungeonEventDefinitionScript := preload(
	"res://scripts/dungeon/dungeon_event_definition.gd"
)
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")

const SCHEMA_ID := "planewalker.dungeon_event_runtime"
const SCHEMA_VERSION := 1
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id", "schema_version", "active_node_key", "active_event_id",
	"encounter_success_by_transaction",
	"emitted_fact_ids", "pending_facts", "publication_ledger", "publication_digest",
	"consequence_runtime",
]
const FACT_FIELDS: Array[String] = ["fact_id", "payload"]
const LEDGER_FIELDS: Array[String] = ["chain_hash", "fact_id", "payload", "status"]
const PUBLICATION_STATE_FIELDS: Array[String] = [
	"emitted_fact_ids", "pending_facts", "encounter_success_by_transaction",
	"publication_ledger", "publication_digest",
]
const ROOM_FIELDS: Array[String] = [
	"floor_id", "floor_index", "node_id", "primary_event_id",
]
const PROVIDER_FIELDS: Array[String] = [
	"global_revision", "requirements", "selection",
]
const VIEW_FIELDS: Array[String] = [
	"phase", "event_id", "name_key", "description_key", "prompt_key", "options",
	"revision", "result_key", "pending_kind",
]
const OPTION_VIEW_FIELDS: Array[String] = [
	"id", "label_key", "eligible", "disabled_reason_key", "outcome_visibility",
	"visible_preview",
]
const PREVIEW_CATEGORIES := {
	"resource_delta": "EVENT_PREVIEW_RESOURCE",
	"health_delta": "EVENT_PREVIEW_HEALTH",
	"reward_draft": "EVENT_PREVIEW_REWARD",
	"curse_add": "EVENT_PREVIEW_CURSE",
	"curse_remove": "EVENT_PREVIEW_CURSE",
	"temporary_modifier": "EVENT_PREVIEW_MODIFIER",
	"map_reveal": "EVENT_PREVIEW_ROUTE",
	"route_skip": "EVENT_PREVIEW_ROUTE",
	"encounter_start": "EVENT_PREVIEW_ENCOUNTER",
	"narrative_flag": "EVENT_PREVIEW_NARRATIVE",
}

var _configured := false
var _definitions: Array[Dictionary] = []
var _definitions_by_id: Dictionary = {}
var _selector: Object
var _event_state: Object
var _requirements: Object
var _consequences: Object
var _context_provider: Callable
var _state_sink: Callable
var _fact_sink: Callable
var _active_node_key := ""
var _active_event_id := ""
var _emitted_fact_ids: Array[String] = []
var _pending_facts: Array[Dictionary] = []
var _encounter_success_by_transaction: Dictionary = {}
var _publication_key := ""
var _fact_delivery_in_progress := false


func configure(
	event_definitions: Array,
	selector: Object,
	event_state: Object,
	requirement_service: Object,
	consequence_runtime: Object,
	context_provider: Callable,
	state_sink: Callable,
	fact_sink: Callable,
	publication_secret: String
) -> bool:
	if _fact_delivery_in_progress:
		return false
	if (
		not _has_methods(selector, [&"select"])
		or not _has_methods(event_state, [
			&"snapshot", &"can_restore_snapshot", &"restore_snapshot", &"assign_event",
			&"reserve_option", &"resolve_option", &"dismiss_result", &"rollback_transaction",
		])
		or not _has_methods(requirement_service, [&"evaluate"])
		or not _has_methods(consequence_runtime, [
			&"snapshot", &"can_restore_snapshot", &"restore_snapshot",
			&"prepare_consequences", &"commit_consequences", &"rollback_consequences",
		])
		or not context_provider.is_valid()
		or not state_sink.is_valid()
		or not fact_sink.is_valid()
		or publication_secret.length() < 32
		or publication_secret.length() > 256
	):
		return false
	var normalized_definitions: Array[Dictionary] = []
	var definitions_by_id: Dictionary = {}
	for value: Variant in event_definitions:
		if not value is Dictionary:
			return false
		var definition = DungeonEventDefinitionScript.new()
		var configured: Dictionary = definition.configure(value as Dictionary)
		if not bool(configured.get("ok", false)):
			return false
		var normalized: Dictionary = configured.get("definition", {})
		var event_id := str(normalized.get("id", ""))
		if event_id.is_empty() or definitions_by_id.has(event_id):
			return false
		normalized_definitions.append(normalized.duplicate(true))
		definitions_by_id[event_id] = normalized.duplicate(true)
	if normalized_definitions.is_empty():
		return false
	_selector = selector
	_event_state = event_state
	_requirements = requirement_service
	_consequences = consequence_runtime
	_context_provider = context_provider
	_state_sink = state_sink
	_fact_sink = fact_sink
	_definitions = normalized_definitions
	_definitions_by_id = definitions_by_id
	_active_node_key = ""
	_active_event_id = ""
	_emitted_fact_ids.clear()
	_pending_facts.clear()
	_encounter_success_by_transaction.clear()
	_configured = true
	var event_snapshot := _dictionary(_event_state.call("snapshot"))
	var consequence_snapshot := _dictionary(_consequences.call("snapshot"))
	if event_snapshot.is_empty() or consequence_snapshot.is_empty():
		_configured = false
		return false
	var content_fingerprint := str(event_snapshot.get("content_fingerprint", ""))
	if content_fingerprint.is_empty():
		_configured = false
		return false
	_publication_key = _sha256_text(
		"dungeon_event_publication_v1|%s|%s" % [content_fingerprint, publication_secret]
	)
	return true


func open_event(room_context: Dictionary, runtime_context: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if _fact_delivery_in_progress:
		return _failure(&"PUBLICATION_IN_PROGRESS")
	if not runtime_context is Dictionary:
		return _failure(&"INVALID_CONTEXT")
	var flushed := flush_pending_facts()
	if not bool(flushed.get("ok", false)):
		return flushed
	var room := _normalize_room_context(room_context)
	if room.is_empty():
		return _failure(&"INVALID_ROOM_CONTEXT")
	var provider := _provider_context()
	if provider.is_empty():
		return _failure(&"INVALID_CONTEXT")
	var node_key := "%s:%s" % [room["floor_id"], room["node_id"]]
	var state_before := _dictionary(_event_state.call("snapshot"))
	var assignments := state_before.get("selected_event_by_node", {}) as Dictionary
	if assignments.has(node_key):
		var existing := assignments[node_key] as Dictionary
		var existing_event_id := str(existing.get("event_id", ""))
		if not _definitions_by_id.has(existing_event_id):
			return _failure(&"EVENT_DEFINITION_NOT_FOUND", {"event_id": existing_event_id})
		_active_node_key = node_key
		_active_event_id = existing_event_id
		return _success({"view_state": view_state()})

	var selection_context := (provider["selection"] as Dictionary).duplicate(true)
	selection_context["floor_id"] = room["floor_id"]
	selection_context["floor_index"] = room["floor_index"]
	selection_context["node_id"] = room["node_id"]
	selection_context["primary_event_id"] = room["primary_event_id"]
	selection_context["seen_run_event_ids"] = (
		state_before.get("seen_run_event_ids", []) as Array
	).duplicate()
	selection_context["seen_floor_event_keys"] = (
		state_before.get("seen_floor_event_keys", []) as Array
	).duplicate()
	var selected := _dictionary(_selector.call(
		"select", _definitions.duplicate(true), selection_context
	))
	if not bool(selected.get("ok", false)):
		return selected
	var event_id := str(selected.get("event_id", ""))
	if not _definitions_by_id.has(event_id):
		return _failure(&"EVENT_DEFINITION_NOT_FOUND", {"event_id": event_id})
	var definition := _definitions_by_id[event_id] as Dictionary
	var consequence_before := _dictionary(_consequences.call("snapshot"))
	var active_node_before := _active_node_key
	var active_event_before := _active_event_id
	var publication_before := _publication_state()
	var assigned := _dictionary(_event_state.call("assign_event", {
		"floor_id": room["floor_id"],
		"floor_index": room["floor_index"],
		"node_id": room["node_id"],
		"event_id": event_id,
		"repeat_policy": str(definition["repeat_policy"]),
	}, int(state_before.get("revision", -1))))
	if not bool(assigned.get("ok", false)):
		return assigned
	_active_node_key = node_key
	_active_event_id = event_id
	var fact_id := "event_opened:%s:%s" % [node_key, event_id]
	_queue_fact({
		"fact_id": fact_id,
		"payload": {
			"kind": "event_opened",
			"event_id": event_id,
			"node_key": node_key,
		},
	})
	var persisted := _persist_event_state(
		"open_event",
		{},
		int(provider["global_revision"])
	)
	if not bool(persisted.get("ok", false)):
		_consequences.call("restore_snapshot", consequence_before)
		_active_node_key = active_node_before
		_active_event_id = active_event_before
		_apply_publication_state(publication_before)
		return persisted
	flushed = flush_pending_facts()
	if not bool(flushed.get("ok", false)):
		return flushed
	return _success({"view_state": view_state()})


func view_state() -> Dictionary:
	var provider := _provider_context()
	var revision := int(provider.get("global_revision", -1)) if not provider.is_empty() else -1
	if not _configured or _active_node_key.is_empty() or _active_event_id.is_empty():
		return _empty_view(revision)
	var definition_value: Variant = _definitions_by_id.get(_active_event_id, {})
	if not definition_value is Dictionary:
		return _empty_view(revision)
	var event_snapshot := _dictionary(_event_state.call("snapshot"))
	var assignments := event_snapshot.get("selected_event_by_node", {}) as Dictionary
	if not assignments.has(_active_node_key):
		return _empty_view(revision)
	var assignment := assignments[_active_node_key] as Dictionary
	var definition := definition_value as Dictionary
	var requirement_context: Dictionary = (
		(provider.get("requirements", {}) as Dictionary).duplicate(true)
		if not provider.is_empty()
		else {}
	)
	var options: Array[Dictionary] = []
	for value: Variant in definition.get("options", []):
		if value is Dictionary:
			options.append(_option_view(value as Dictionary, requirement_context))
	var phase := str(assignment.get("phase", ""))
	var pending_kind := ""
	if phase == "pending_reward":
		pending_kind = "reward"
	elif phase == "pending_encounter":
		pending_kind = "encounter"
	return {
		"phase": phase,
		"event_id": _active_event_id,
		"name_key": str(definition.get("name_key", "")),
		"description_key": str(definition.get("description_key", "")),
		"prompt_key": str(definition.get("prompt_key", "")),
		"options": options,
		"revision": revision,
		"result_key": str(assignment.get("result_key", "")),
		"pending_kind": pending_kind,
	}


func choose_option(option_id: StringName, expected_revision: int) -> Dictionary:
	var begun := _begin_command(expected_revision)
	if not bool(begun.get("ok", false)):
		return begun
	var command_revision := int(begun["current_revision"])
	var definition := _definitions_by_id[_active_event_id] as Dictionary
	var option := _option_by_id(definition, str(option_id))
	if option.is_empty():
		return _failure(&"OPTION_NOT_FOUND", {"option_id": str(option_id)})
	var event_snapshot := _dictionary(_event_state.call("snapshot"))
	var assignment := _active_assignment(event_snapshot)
	if str(assignment.get("phase", "")) != "open":
		return _failure(&"EVENT_NOT_OPEN", {"phase": str(assignment.get("phase", ""))})
	var provider := _provider_context()
	if provider.is_empty():
		return _failure(&"INVALID_CONTEXT")
	var evaluated := _dictionary(_requirements.call(
		"evaluate",
		(option.get("requirements", []) as Array).duplicate(true),
		(provider["requirements"] as Dictionary).duplicate(true)
	))
	if not bool(evaluated.get("ok", false)):
		return _failure(&"REQUIREMENT_EVALUATION_FAILED")
	if not bool(evaluated.get("eligible", false)):
		return _failure(&"OPTION_INELIGIBLE", {
			"disabled_reason_key": _disabled_reason(evaluated),
		})
	var outcome := _select_outcome(
		option,
		definition,
		provider["selection"] as Dictionary,
		str(assignment.get("node_id", ""))
	)
	if outcome.is_empty():
		return _failure(&"OUTCOME_NOT_AVAILABLE")
	var transaction_id := "event_tx_v1:%s:%d" % [
		_active_event_id,
		int(event_snapshot.get("revision", 0)),
	]
	var consequence_before := _dictionary(_consequences.call("snapshot"))
	var reserved := _dictionary(_event_state.call(
		"reserve_option",
		_active_node_key,
		transaction_id,
		str(option["id"]),
		str(outcome["id"]),
		str(outcome["outcome_key"]),
		int(event_snapshot.get("revision", -1))
	))
	if not bool(reserved.get("ok", false)):
		return reserved
	var event_ticket := reserved.get("ticket", {}) as Dictionary
	var prepared := _dictionary(_consequences.call(
		"prepare_consequences",
		transaction_id,
		(outcome.get("consequences", []) as Array).duplicate(true),
		{
			"event_ticket": event_ticket.duplicate(true),
			"result_key": str(outcome["outcome_key"]),
		}
	))
	if not bool(prepared.get("ok", false)):
		_event_state.call("rollback_transaction", event_ticket)
		return prepared
	var committed := _dictionary(_consequences.call(
		"commit_consequences", (prepared.get("ticket", {}) as Dictionary).duplicate(true)
	))
	if not bool(committed.get("ok", false)):
		_event_state.call("rollback_transaction", event_ticket)
		return committed
	var receipt := committed.get("receipt", {}) as Dictionary
	var publication_before := _publication_state()
	var publication := committed.get("publication", {}) as Dictionary
	var fact_id := "event_committed:%s" % transaction_id
	_queue_fact({
		"fact_id": fact_id,
		"payload": {
			"kind": "event_committed",
			"event_id": _active_event_id,
			"node_key": _active_node_key,
			"phase": str(publication.get("phase", "")),
			"pending_kind": str(publication.get("pending_kind", "")),
			"result_key": str(publication.get("result_key", "")),
		},
	})
	var persisted := _persist_event_state(
		"choose_option",
		{"option_id": str(option_id)},
		command_revision
	)
	if not bool(persisted.get("ok", false)):
		var rolled_back := _dictionary(_consequences.call(
			"rollback_consequences", receipt.duplicate(true)
		))
		_apply_publication_state(publication_before)
		if not bool(rolled_back.get("ok", false)):
			return _failure(&"INTEGRITY_TERMINAL", {"cause": persisted})
		return persisted
	var flushed := flush_pending_facts()
	if not bool(flushed.get("ok", false)):
		return flushed
	return _success({"view_state": view_state()})


func complete_reward(
	continuation_id: String,
	result: Dictionary,
	expected_revision: int
) -> Dictionary:
	return _complete_continuation(
		"reward", continuation_id, result, true, expected_revision
	)


func complete_encounter(
	continuation_id: String,
	success: bool,
	context: Dictionary,
	expected_revision: int
) -> Dictionary:
	var payload := context.duplicate(true)
	payload["success"] = success
	return _complete_continuation(
		"encounter", continuation_id, payload, success, expected_revision
	)


func dismiss_result(expected_revision: int) -> Dictionary:
	var begun := _begin_command(expected_revision)
	if not bool(begun.get("ok", false)):
		return begun
	var command_revision := int(begun["current_revision"])
	var consequence_before := _dictionary(_consequences.call("snapshot"))
	var publication_before := _publication_state()
	var event_snapshot := _dictionary(_event_state.call("snapshot"))
	var assignment := _active_assignment(event_snapshot)
	if str(assignment.get("phase", "")) != "resolved":
		return _failure(&"RESULT_NOT_RESOLVED", {"phase": str(assignment.get("phase", ""))})
	var dismissed := _dictionary(_event_state.call(
		"dismiss_result", _active_node_key, int(event_snapshot.get("revision", -1))
	))
	if not bool(dismissed.get("ok", false)):
		return dismissed
	var transaction_id := str(assignment.get("transaction_id", ""))
	var fact_id := "event_dismissed:%s" % transaction_id
	_queue_fact({
		"fact_id": fact_id,
		"payload": {
			"kind": "event_dismissed",
			"event_id": _active_event_id,
			"node_key": _active_node_key,
			"result_key": str(assignment.get("result_key", "")),
		},
	})
	var persisted := _persist_event_state("dismiss_result", {}, command_revision)
	if not bool(persisted.get("ok", false)):
		_consequences.call("restore_snapshot", consequence_before)
		_apply_publication_state(publication_before)
		return persisted
	var flushed := flush_pending_facts()
	if not bool(flushed.get("ok", false)):
		return flushed
	return _success({"view_state": view_state()})


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	var publication := _publication_state()
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"active_node_key": _active_node_key,
		"active_event_id": _active_event_id,
		"encounter_success_by_transaction": publication["encounter_success_by_transaction"],
		"emitted_fact_ids": publication["emitted_fact_ids"],
		"pending_facts": publication["pending_facts"],
		"publication_ledger": publication["publication_ledger"],
		"publication_digest": publication["publication_digest"],
		"consequence_runtime": _dictionary(_consequences.call("snapshot")),
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	return _configured and not _normalize_snapshot(value).is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	if _fact_delivery_in_progress:
		return false
	var normalized := _normalize_snapshot(value)
	if normalized.is_empty():
		return false
	var before := snapshot()
	if not bool(_consequences.call(
		"restore_snapshot", (normalized["consequence_runtime"] as Dictionary).duplicate(true)
	)):
		return false
	_active_node_key = str(normalized["active_node_key"])
	_active_event_id = str(normalized["active_event_id"])
	_emitted_fact_ids = _string_array(normalized["emitted_fact_ids"])
	_pending_facts = _fact_array(normalized["pending_facts"])
	_encounter_success_by_transaction = (
		normalized["encounter_success_by_transaction"] as Dictionary
	).duplicate(true)
	if snapshot() != normalized:
		_consequences.call("restore_snapshot", before["consequence_runtime"])
		_active_node_key = str(before["active_node_key"])
		_active_event_id = str(before["active_event_id"])
		_emitted_fact_ids = _string_array(before["emitted_fact_ids"])
		_pending_facts = _fact_array(before["pending_facts"])
		_encounter_success_by_transaction = (
			before["encounter_success_by_transaction"] as Dictionary
		).duplicate(true)
		return false
	return true


func _complete_continuation(
	kind: String,
	continuation_id: String,
	payload: Dictionary,
	success: bool,
	expected_revision: int
) -> Dictionary:
	var begun := _begin_command(expected_revision)
	if not bool(begun.get("ok", false)):
		return begun
	var command_revision := int(begun["current_revision"])
	var event_snapshot := _dictionary(_event_state.call("snapshot"))
	var pending_field := "pending_reward" if kind == "reward" else "pending_encounter"
	var pending := event_snapshot.get(pending_field, {}) as Dictionary
	if pending.is_empty():
		return _failure(
			&"PENDING_REWARD_NOT_FOUND" if kind == "reward" else &"PENDING_ENCOUNTER_NOT_FOUND"
		)
	if str(pending.get("continuation_id", "")) != continuation_id:
		return _failure(&"CONTINUATION_MISMATCH")
	var assignment := _active_assignment(event_snapshot)
	var expected_phase := "pending_reward" if kind == "reward" else "pending_encounter"
	if str(assignment.get("phase", "")) != expected_phase:
		return _failure(&"CONTINUATION_STATE_INVALID")
	var consequence_before := _dictionary(_consequences.call("snapshot"))
	var publication_before := _publication_state()
	var participant_snapshots := consequence_before.get("participant_snapshots", {}) as Dictionary
	var modifier_snapshot := participant_snapshots.get("modifier", {}) as Dictionary
	var resolved := _dictionary(_event_state.call(
		"resolve_option",
		(event_snapshot.get("pending_transaction", {}) as Dictionary).duplicate(true),
		{
			"result_key": str(assignment.get("outcome_key", "")),
			"narrative_flags": (
				modifier_snapshot.get("narrative_flags", {}) as Dictionary
			).duplicate(true),
			"temporary_modifiers": (
				modifier_snapshot.get("temporary_modifiers", []) as Array
			).duplicate(true),
		}
	))
	if not bool(resolved.get("ok", false)):
		return resolved
	var transaction_id := str(assignment.get("transaction_id", ""))
	if kind == "encounter":
		_encounter_success_by_transaction[transaction_id] = success
	var fact_id := "event_%s_completed:%s" % [kind, transaction_id]
	_queue_fact({
		"fact_id": fact_id,
		"payload": {
			"kind": "event_%s_completed" % kind,
			"event_id": _active_event_id,
			"node_key": _active_node_key,
			"result_key": str(assignment.get("outcome_key", "")),
			"success": success,
		},
	})
	var persisted := _persist_event_state(
		"complete_%s" % kind,
		{"result": payload.duplicate(true), "success": success},
		command_revision
	)
	if not bool(persisted.get("ok", false)):
		_consequences.call("restore_snapshot", consequence_before)
		_apply_publication_state(publication_before)
		return persisted
	var flushed := flush_pending_facts()
	if not bool(flushed.get("ok", false)):
		return flushed
	return _success({"view_state": view_state()})


func _begin_command(expected_revision: int) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if _fact_delivery_in_progress:
		return _failure(&"PUBLICATION_IN_PROGRESS")
	if _active_node_key.is_empty() or _active_event_id.is_empty():
		return _failure(&"EVENT_NOT_OPEN")
	var provider := _provider_context()
	if provider.is_empty():
		return _failure(&"INVALID_CONTEXT")
	var current_revision := int(provider["global_revision"])
	if expected_revision != current_revision:
		return _failure(&"STALE_REVISION", {
			"expected_revision": expected_revision,
			"actual_revision": current_revision,
		})
	var flushed := flush_pending_facts()
	if not bool(flushed.get("ok", false)):
		return flushed
	var refreshed := _provider_context()
	if refreshed.is_empty():
		return _failure(&"INVALID_CONTEXT")
	return _success({"current_revision": int(refreshed["global_revision"])})


func flush_pending_facts() -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if _fact_delivery_in_progress:
		return _failure(&"PUBLICATION_IN_PROGRESS")
	_fact_delivery_in_progress = true
	var result := _flush_pending_facts_inner()
	_fact_delivery_in_progress = false
	return result


func _flush_pending_facts_inner() -> Dictionary:
	var flushed_count := 0
	while not _pending_facts.is_empty():
		var fact := _pending_facts[0].duplicate(true)
		var fact_id := str(fact["fact_id"])
		var delivered: Variant = _fact_sink.call(
			fact_id, (fact["payload"] as Dictionary).duplicate(true)
		)
		if typeof(delivered) != TYPE_BOOL or not bool(delivered):
			return _publication_pending_failure(
				&"FACT_SINK_FAILED", {"fact_id": fact_id}
			)
		var candidate := _publication_state()
		var candidate_pending := candidate["pending_facts"] as Array
		candidate_pending.remove_at(0)
		var candidate_emitted := candidate["emitted_fact_ids"] as Array
		if not candidate_emitted.has(fact_id):
			candidate_emitted.append(fact_id)
			candidate_emitted.sort()
		candidate = _sealed_publication_state(
			candidate_emitted,
			candidate_pending,
			candidate["encounter_success_by_transaction"] as Dictionary,
			_dictionary(_consequences.call("snapshot"))
		)
		var provider := _provider_context()
		if provider.is_empty():
			return _publication_pending_failure(
				&"INVALID_CONTEXT", {"fact_id": fact_id}
			)
		var acknowledged := _persist_candidate(
			"ack_event_fact",
			{"fact_id": fact_id},
			int(provider["global_revision"]),
			candidate
		)
		if not bool(acknowledged.get("ok", false)):
			return _publication_pending_failure(
				StringName(str(acknowledged.get("code", "STATE_SINK_FAILED"))),
				{"fact_id": fact_id, "cause": acknowledged.duplicate(true)}
			)
		_apply_publication_state(candidate)
		flushed_count += 1
	return _success({"flushed_count": flushed_count})


func _persist_event_state(
	operation: String,
	payload: Dictionary,
	expected_revision: int
) -> Dictionary:
	return _persist_candidate(
		operation, payload, expected_revision, _publication_state()
	)


func _persist_candidate(
	operation: String,
	payload: Dictionary,
	expected_revision: int,
	publication_state: Dictionary
) -> Dictionary:
	var command := {
		"operation": operation,
		"event_state": _dictionary(_event_state.call("snapshot")),
		"publication_state": publication_state.duplicate(true),
		"payload": payload.duplicate(true),
	}
	var result_value: Variant = _state_sink.call(command, expected_revision)
	if not result_value is Dictionary:
		return _failure(&"STATE_SINK_FAILED")
	var result := result_value as Dictionary
	if not bool(result.get("ok", false)):
		return result.duplicate(true)
	if typeof(result.get("new_revision")) != TYPE_INT:
		return _failure(&"STATE_SINK_FAILED")
	return result.duplicate(true)


func _publication_state() -> Dictionary:
	return _sealed_publication_state(
		_emitted_fact_ids,
		_pending_facts,
		_encounter_success_by_transaction,
		_dictionary(_consequences.call("snapshot"))
	)


func _apply_publication_state(value: Dictionary) -> void:
	if not _exact_fields(value, PUBLICATION_STATE_FIELDS):
		return
	_emitted_fact_ids = _string_array(value.get("emitted_fact_ids", []))
	_pending_facts = _fact_array(value.get("pending_facts", []))
	_encounter_success_by_transaction = (
		value.get("encounter_success_by_transaction", {}) as Dictionary
	).duplicate(true)


func _queue_fact(fact: Dictionary) -> void:
	var fact_id := str(fact.get("fact_id", ""))
	if fact_id.is_empty() or _emitted_fact_ids.has(fact_id):
		return
	for pending: Dictionary in _pending_facts:
		if str(pending.get("fact_id", "")) == fact_id:
			return
	var payload := _canonical_fact_payload(
		fact_id,
		_dictionary(_consequences.call("snapshot")),
		_encounter_success_by_transaction
	)
	if payload.is_empty():
		return
	_pending_facts.append({"fact_id": fact_id, "payload": payload})
	_pending_facts.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["fact_id"]) < str(right["fact_id"])
	)


func _publication_pending_failure(code: StringName, context: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"committed": true,
		"pending_publication": true,
		"context": context.duplicate(true),
	}


func _sealed_publication_state(
	emitted_value: Array,
	pending_value: Array,
	encounter_success_value: Dictionary,
	consequence_snapshot: Dictionary
) -> Dictionary:
	var emitted := _string_array(emitted_value)
	if emitted.size() != emitted_value.size():
		return {}
	emitted.sort()
	var pending := _fact_array(pending_value)
	if pending.size() != pending_value.size():
		return {}
	pending.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["fact_id"]) < str(right["fact_id"])
	)
	var status_by_id: Dictionary = {}
	for fact_id: String in emitted:
		if status_by_id.has(fact_id):
			return {}
		status_by_id[fact_id] = "emitted"
	for fact: Dictionary in pending:
		var fact_id := str(fact["fact_id"])
		if status_by_id.has(fact_id):
			return {}
		var canonical_payload := _canonical_fact_payload(
			fact_id, consequence_snapshot, encounter_success_value
		)
		if canonical_payload.is_empty() or canonical_payload != fact["payload"]:
			return {}
		status_by_id[fact_id] = "pending"
	var ordered_ids: Array[String] = []
	for fact_id_value: Variant in status_by_id.keys():
		ordered_ids.append(str(fact_id_value))
	ordered_ids.sort()
	var ledger: Array[Dictionary] = []
	var previous_hash := _sha256_text("%s|publication_root" % _publication_key)
	for fact_id: String in ordered_ids:
		var payload := _canonical_fact_payload(
			fact_id, consequence_snapshot, encounter_success_value
		)
		if payload.is_empty():
			return {}
		var unsigned := {
			"fact_id": fact_id,
			"payload": payload,
			"status": str(status_by_id[fact_id]),
		}
		var chain_hash := _sha256_text("%s|%s|%s" % [
			_publication_key,
			previous_hash,
			JSON.stringify(_canonical_value(unsigned)),
		])
		ledger.append({
			"chain_hash": chain_hash,
			"fact_id": fact_id,
			"payload": payload,
			"status": str(status_by_id[fact_id]),
		})
		previous_hash = chain_hash
	return {
		"emitted_fact_ids": emitted,
		"pending_facts": pending,
		"encounter_success_by_transaction": encounter_success_value.duplicate(true),
		"publication_ledger": ledger,
		"publication_digest": previous_hash,
	}


func _canonical_fact_payload(
	fact_id: String,
	consequence_snapshot: Dictionary,
	encounter_success_by_transaction: Dictionary
) -> Dictionary:
	var participants := consequence_snapshot.get("participant_snapshots", {}) as Dictionary
	var event_snapshot := participants.get("event_state", {}) as Dictionary
	var assignments := event_snapshot.get("selected_event_by_node", {}) as Dictionary
	if fact_id.begins_with("event_opened:"):
		for node_key_value: Variant in assignments.keys():
			var node_key := str(node_key_value)
			var assignment := assignments[node_key_value] as Dictionary
			var event_id := str(assignment.get("event_id", ""))
			if fact_id == "event_opened:%s:%s" % [node_key, event_id]:
				return {
					"kind": "event_opened",
					"event_id": event_id,
					"node_key": node_key,
				}
		return {}
	var separator_index := fact_id.find(":")
	if separator_index < 0 or separator_index >= fact_id.length() - 1:
		return {}
	var transaction_id := fact_id.substr(separator_index + 1)
	var assignment_entry := _assignment_for_transaction(assignments, transaction_id)
	if assignment_entry.is_empty():
		return {}
	var node_key := str(assignment_entry["node_key"])
	var assignment := assignment_entry["assignment"] as Dictionary
	var event_id := str(assignment.get("event_id", ""))
	var publication := _publication_for_transaction(consequence_snapshot, transaction_id)
	if fact_id.begins_with("event_committed:") and not publication.is_empty():
		return {
			"kind": "event_committed",
			"event_id": event_id,
			"node_key": node_key,
			"phase": str(publication.get("phase", "")),
			"pending_kind": str(publication.get("pending_kind", "")),
			"result_key": str(publication.get("result_key", "")),
		}
	if fact_id.begins_with("event_reward_completed:"):
		if str(publication.get("pending_kind", "")) != "reward":
			return {}
		return {
			"kind": "event_reward_completed",
			"event_id": event_id,
			"node_key": node_key,
			"result_key": str(assignment.get("outcome_key", "")),
		}
	if fact_id.begins_with("event_encounter_completed:"):
		if (
			str(publication.get("pending_kind", "")) != "encounter"
			or not encounter_success_by_transaction.has(transaction_id)
			or typeof(encounter_success_by_transaction[transaction_id]) != TYPE_BOOL
		):
			return {}
		return {
			"kind": "event_encounter_completed",
			"event_id": event_id,
			"node_key": node_key,
			"result_key": str(assignment.get("outcome_key", "")),
			"success": bool(encounter_success_by_transaction[transaction_id]),
		}
	if fact_id.begins_with("event_dismissed:") and str(assignment.get("phase", "")) == "dismissed":
		return {
			"kind": "event_dismissed",
			"event_id": event_id,
			"node_key": node_key,
			"result_key": str(assignment.get("result_key", "")),
		}
	return {}


func _assignment_for_transaction(assignments: Dictionary, transaction_id: String) -> Dictionary:
	for node_key_value: Variant in assignments.keys():
		var assignment := assignments[node_key_value] as Dictionary
		if str(assignment.get("transaction_id", "")) == transaction_id:
			return {
				"node_key": str(node_key_value),
				"assignment": assignment.duplicate(true),
			}
	return {}


func _publication_for_transaction(
	consequence_snapshot: Dictionary,
	transaction_id: String
) -> Dictionary:
	for value: Variant in consequence_snapshot.get("publications", []):
		if value is Dictionary and str((value as Dictionary).get("transaction_id", "")) == transaction_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _canonical_value(value: Variant) -> Variant:
	if value is Dictionary:
		var source := value as Dictionary
		var keys: Array[String] = []
		for key_value: Variant in source.keys():
			keys.append(str(key_value))
		keys.sort()
		var normalized: Dictionary = {}
		for key: String in keys:
			normalized[key] = _canonical_value(source[key])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for entry: Variant in (value as Array):
			normalized_array.append(_canonical_value(entry))
		return normalized_array
	return value


func _sha256_text(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


func _provider_context() -> Dictionary:
	if not _configured or not _context_provider.is_valid():
		return {}
	var value: Variant = _context_provider.call()
	if not value is Dictionary:
		return {}
	var context := value as Dictionary
	if not _exact_fields(context, PROVIDER_FIELDS):
		return {}
	if (
		typeof(context["global_revision"]) != TYPE_INT
		or int(context["global_revision"]) < 0
		or not context["selection"] is Dictionary
		or not context["requirements"] is Dictionary
	):
		return {}
	return context.duplicate(true)


func _option_view(option: Dictionary, requirement_context: Dictionary) -> Dictionary:
	var evaluated := _dictionary(_requirements.call(
		"evaluate",
		(option.get("requirements", []) as Array).duplicate(true),
		requirement_context.duplicate(true)
	))
	var eligible := bool(evaluated.get("ok", false)) and bool(evaluated.get("eligible", false))
	var reason := ""
	if not bool(evaluated.get("ok", false)):
		reason = "EVENT_REQUIREMENT_INVALID"
	elif not eligible:
		reason = _disabled_reason(evaluated)
	return {
		"id": str(option.get("id", "")),
		"label_key": str(option.get("label_key", "")),
		"eligible": eligible,
		"disabled_reason_key": reason,
		"outcome_visibility": str(option.get("outcome_visibility", "")),
		"visible_preview": _visible_preview(option),
	}


func _visible_preview(option: Dictionary) -> Array[String]:
	var visibility := str(option.get("outcome_visibility", ""))
	if visibility == "hidden_until_commit":
		return []
	var preview: Array[String] = []
	for outcome_value: Variant in option.get("outcomes", []):
		if not outcome_value is Dictionary:
			continue
		var outcome := outcome_value as Dictionary
		if visibility == "preview_exact":
			var result_key := str(outcome.get("outcome_key", ""))
			if not result_key.is_empty() and not preview.has(result_key):
				preview.append(result_key)
			continue
		for consequence_value: Variant in outcome.get("consequences", []):
			if not consequence_value is Dictionary:
				continue
			var operation := str((consequence_value as Dictionary).get("operation", ""))
			var category := str(PREVIEW_CATEGORIES.get(operation, ""))
			if not category.is_empty() and not preview.has(category):
				preview.append(category)
	preview.sort()
	return preview


func _select_outcome(
	option: Dictionary,
	definition: Dictionary,
	selection_context: Dictionary,
	node_id: String
) -> Dictionary:
	var outcomes: Array = option.get("outcomes", [])
	var total_weight := 0
	for value: Variant in outcomes:
		if value is Dictionary:
			total_weight += int((value as Dictionary).get("weight", 0))
	if total_weight <= 0:
		return {}
	var channel := "%s:%s:%s" % [
		str(definition.get("outcome_channel", "event_outcome_v1")),
		str(definition.get("id", "")),
		node_id,
	]
	var roll := posmod(SeedServiceScript.derive_seed(
		int(selection_context.get("run_seed", 0)),
		StringName(channel),
		int(selection_context.get("floor_index", 0)),
		0,
		0
	), total_weight)
	var cursor := 0
	for value: Variant in outcomes:
		if not value is Dictionary:
			continue
		var outcome := value as Dictionary
		cursor += int(outcome.get("weight", 0))
		if roll < cursor:
			return outcome.duplicate(true)
	return {}


func _normalize_snapshot(value: Dictionary) -> Dictionary:
	if not _exact_fields(value, SNAPSHOT_FIELDS):
		return {}
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != SCHEMA_ID
		or typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != SCHEMA_VERSION
		or typeof(value["active_node_key"]) != TYPE_STRING
		or typeof(value["active_event_id"]) != TYPE_STRING
		or not value["encounter_success_by_transaction"] is Dictionary
		or not value["emitted_fact_ids"] is Array
		or not value["pending_facts"] is Array
		or not value["publication_ledger"] is Array
		or typeof(value["publication_digest"]) != TYPE_STRING
		or not value["consequence_runtime"] is Dictionary
	):
		return {}
	var node_key := str(value["active_node_key"])
	var event_id := str(value["active_event_id"])
	if node_key.is_empty() != event_id.is_empty():
		return {}
	if not event_id.is_empty() and not _definitions_by_id.has(event_id):
		return {}
	var fact_ids := _string_array(value["emitted_fact_ids"])
	if fact_ids.size() != (value["emitted_fact_ids"] as Array).size():
		return {}
	var sorted_ids := fact_ids.duplicate()
	sorted_ids.sort()
	if sorted_ids != fact_ids:
		return {}
	if not bool(_consequences.call(
		"can_restore_snapshot", value["consequence_runtime"] as Dictionary
	)):
		return {}
	var consequence_snapshot := value["consequence_runtime"] as Dictionary
	if not _valid_digest(str(value["publication_digest"])):
		return {}
	for entry_value: Variant in (value["publication_ledger"] as Array):
		if not entry_value is Dictionary:
			return {}
		var entry := entry_value as Dictionary
		if (
			not _exact_fields(entry, LEDGER_FIELDS)
			or not _valid_fact_id(str(entry.get("fact_id", "")))
			or not entry.get("payload") is Dictionary
			or str(entry.get("status", "")) not in ["pending", "emitted"]
			or not _valid_digest(str(entry.get("chain_hash", "")))
		):
			return {}
	var allowed_fact_ids := _allowed_fact_ids(consequence_snapshot)
	var encounter_success := (
		value["encounter_success_by_transaction"] as Dictionary
	).duplicate(true)
	var required_encounter_transactions: Array[String] = []
	for allowed_fact_id_value: Variant in allowed_fact_ids.keys():
		var allowed_fact_id := str(allowed_fact_id_value)
		if allowed_fact_id.begins_with("event_encounter_completed:"):
			required_encounter_transactions.append(
				allowed_fact_id.substr(allowed_fact_id.find(":") + 1)
			)
	required_encounter_transactions.sort()
	var actual_encounter_transactions: Array[String] = []
	for transaction_value: Variant in encounter_success.keys():
		if (
			typeof(transaction_value) != TYPE_STRING
			or typeof(encounter_success[transaction_value]) != TYPE_BOOL
		):
			return {}
		actual_encounter_transactions.append(str(transaction_value))
	actual_encounter_transactions.sort()
	if actual_encounter_transactions != required_encounter_transactions:
		return {}
	for fact_id: String in fact_ids:
		if not _valid_fact_id(fact_id) or not allowed_fact_ids.has(fact_id):
			return {}
	var pending_facts := _fact_array(value["pending_facts"])
	if pending_facts.size() != (value["pending_facts"] as Array).size():
		return {}
	var previous_fact_id := ""
	for fact: Dictionary in pending_facts:
		var pending_fact_id := str(fact["fact_id"])
		if (
			not _valid_fact_id(pending_fact_id)
			or not allowed_fact_ids.has(pending_fact_id)
			or fact_ids.has(pending_fact_id)
			or (not previous_fact_id.is_empty() and pending_fact_id <= previous_fact_id)
		):
			return {}
		var payload := fact["payload"] as Dictionary
		if str(payload.get("kind", "")) != pending_fact_id.get_slice(":", 0):
			return {}
		previous_fact_id = pending_fact_id
	var recorded_fact_ids := fact_ids.duplicate()
	for fact: Dictionary in pending_facts:
		recorded_fact_ids.append(str(fact["fact_id"]))
	recorded_fact_ids.sort()
	var required_fact_ids: Array[String] = []
	for fact_id_value: Variant in allowed_fact_ids.keys():
		required_fact_ids.append(str(fact_id_value))
	required_fact_ids.sort()
	if recorded_fact_ids != required_fact_ids:
		return {}
	var sealed := _sealed_publication_state(
		fact_ids,
		pending_facts,
		encounter_success,
		consequence_snapshot
	)
	if (
		sealed.is_empty()
		or value["publication_ledger"] != sealed["publication_ledger"]
		or str(value["publication_digest"]) != str(sealed["publication_digest"])
	):
		return {}
	var participants := consequence_snapshot.get("participant_snapshots", {}) as Dictionary
	var event_snapshot := participants.get("event_state", {}) as Dictionary
	var assignments := event_snapshot.get("selected_event_by_node", {}) as Dictionary
	if not node_key.is_empty():
		if not assignments.has(node_key):
			return {}
		if str((assignments[node_key] as Dictionary).get("event_id", "")) != event_id:
			return {}
	return {
		"schema_id": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"active_node_key": node_key,
		"active_event_id": event_id,
		"encounter_success_by_transaction": encounter_success,
		"emitted_fact_ids": fact_ids,
		"pending_facts": pending_facts,
		"publication_ledger": (sealed["publication_ledger"] as Array).duplicate(true),
		"publication_digest": str(sealed["publication_digest"]),
		"consequence_runtime": consequence_snapshot.duplicate(true),
	}


func _normalize_room_context(value: Dictionary) -> Dictionary:
	if not _exact_fields(value, ROOM_FIELDS):
		return {}
	if (
		not _valid_id(value["floor_id"])
		or typeof(value["floor_index"]) != TYPE_INT
		or int(value["floor_index"]) < 0
		or int(value["floor_index"]) > 4
		or not _valid_id(value["node_id"])
		or not _valid_id(value["primary_event_id"])
	):
		return {}
	return {
		"floor_id": str(value["floor_id"]),
		"floor_index": int(value["floor_index"]),
		"node_id": str(value["node_id"]),
		"primary_event_id": str(value["primary_event_id"]),
	}


func _active_assignment(event_snapshot: Dictionary) -> Dictionary:
	var assignments := event_snapshot.get("selected_event_by_node", {}) as Dictionary
	if not assignments.has(_active_node_key):
		return {}
	return (assignments[_active_node_key] as Dictionary).duplicate(true)


func _option_by_id(definition: Dictionary, option_id: String) -> Dictionary:
	for value: Variant in definition.get("options", []):
		if value is Dictionary and str((value as Dictionary).get("id", "")) == option_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _disabled_reason(evaluated: Dictionary) -> String:
	var failures: Array = evaluated.get("failures", [])
	if failures.is_empty() or not failures[0] is Dictionary:
		return "EVENT_REQUIREMENT_UNMET"
	return str((failures[0] as Dictionary).get("reason_code", "EVENT_REQUIREMENT_UNMET"))


func _allowed_fact_ids(consequence_snapshot: Dictionary) -> Dictionary:
	var allowed: Dictionary = {}
	var participants := consequence_snapshot.get("participant_snapshots", {}) as Dictionary
	var event_snapshot := participants.get("event_state", {}) as Dictionary
	var assignments := event_snapshot.get("selected_event_by_node", {}) as Dictionary
	var publications_by_transaction: Dictionary = {}
	for value: Variant in consequence_snapshot.get("publications", []):
		if value is Dictionary:
			var publication := value as Dictionary
			publications_by_transaction[str(publication.get("transaction_id", ""))] = publication
	for node_key_value: Variant in assignments.keys():
		var node_key := str(node_key_value)
		var assignment := assignments[node_key_value] as Dictionary
		var event_id := str(assignment.get("event_id", ""))
		allowed["event_opened:%s:%s" % [node_key, event_id]] = true
		var transaction_id := str(assignment.get("transaction_id", ""))
		if transaction_id.is_empty() or not publications_by_transaction.has(transaction_id):
			continue
		allowed["event_committed:%s" % transaction_id] = true
		var publication := publications_by_transaction[transaction_id] as Dictionary
		var phase := str(assignment.get("phase", ""))
		var pending_kind := str(publication.get("pending_kind", ""))
		if phase in ["resolved", "dismissed"]:
			if pending_kind == "reward":
				allowed["event_reward_completed:%s" % transaction_id] = true
			elif pending_kind == "encounter":
				allowed["event_encounter_completed:%s" % transaction_id] = true
		if phase == "dismissed":
			allowed["event_dismissed:%s" % transaction_id] = true
	return allowed


func _fact_array(value: Variant) -> Array[Dictionary]:
	var facts: Array[Dictionary] = []
	if not value is Array:
		return facts
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not entry is Dictionary:
			return []
		var fact := entry as Dictionary
		if not _exact_fields(fact, FACT_FIELDS):
			return []
		var fact_id := str(fact.get("fact_id", ""))
		if not _valid_fact_id(fact_id) or seen.has(fact_id) or not fact.get("payload") is Dictionary:
			return []
		seen[fact_id] = true
		facts.append({
			"fact_id": fact_id,
			"payload": (fact["payload"] as Dictionary).duplicate(true),
		})
	return facts


func _valid_fact_id(value: String) -> bool:
	if value.is_empty() or value.length() > 320:
		return false
	var regex := RegEx.new()
	return (
		regex.compile(
			"^event_(opened|committed|reward_completed|encounter_completed|dismissed):[a-z0-9_.:-]{1,300}$"
		) == OK
		and regex.search(value) != null
	)


func _valid_digest(value: String) -> bool:
	if value.length() != 64:
		return false
	var regex := RegEx.new()
	return regex.compile("^[0-9a-f]{64}$") == OK and regex.search(value) != null


func _empty_view(revision: int) -> Dictionary:
	return {
		"phase": "unassigned",
		"event_id": "",
		"name_key": "",
		"description_key": "",
		"prompt_key": "",
		"options": [],
		"revision": revision,
		"result_key": "",
		"pending_kind": "",
	}


func _has_methods(value: Object, methods: Array[StringName]) -> bool:
	if value == null:
		return false
	for method: StringName in methods:
		if not value.has_method(method):
			return false
	return true


func _exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	var seen: Dictionary = {}
	for entry: Variant in value:
		if typeof(entry) != TYPE_STRING or str(entry).is_empty() or seen.has(str(entry)):
			return []
		seen[str(entry)] = true
		result.append(str(entry))
	return result


func _valid_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).is_empty() or str(value).length() > 96:
		return false
	var regex := RegEx.new()
	return regex.compile("^[a-z0-9][a-z0-9_.-]{0,95}$") == OK and regex.search(str(value)) != null


func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": &"OK", "context": {}}
	for key: Variant in extra.keys():
		result[key] = extra[key]
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"context": context.duplicate(true),
	}
