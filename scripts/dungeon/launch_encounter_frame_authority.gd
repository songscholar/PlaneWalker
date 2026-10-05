class_name LaunchEncounterFrameAuthority
extends RefCounted

const Encounter := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const SNAPSHOT_FIELDS := ["schema_version", "run_id", "runtime_frame", "encounter"]
const TICKET_FIELDS := ["ticket_id", "runtime_frame", "before", "after", "effect_ticket", "transition", "result"]

signal encounter_frame_observed(result: Dictionary)

var _encounter: RefCounted
var _effects: RefCounted
var _identity: Dictionary = {}
var _digest := ""
var _last_frame := -1
var _next_ticket := 1
var _pending: Dictionary = {}
var _detached: Dictionary = {}
var _committed := false
var _publishing := false


func configure(encounter: RefCounted, effects: RefCounted) -> bool:
	if _encounter != null or not encounter is Encounter or not effects is Effects:
		return false
	var state: Dictionary = encounter.snapshot()
	var payload: Dictionary = effects.work_snapshot()
	if state.is_empty() or payload.is_empty() or not encounter.is_active() or state.identity.run_id != payload.run_id or state.last_runtime_frame != payload.runtime_frame or not _ledger_contains_work(state, payload):
		return false
	_encounter = encounter
	_effects = effects
	_identity = state.identity.duplicate(true)
	_digest = state.encounter_digest
	_last_frame = payload.runtime_frame
	return true


func snapshot() -> Dictionary:
	return {"schema_version": 1, "run_id": _identity.run_id, "runtime_frame": _last_frame, "encounter": _encounter.snapshot()} if _encounter != null else {}


func owns_effects(effects: RefCounted, run_id: String) -> bool:
	return _effects == effects and _identity.get("run_id", "") == run_id


func is_ready_for_frame(frame: int) -> bool:
	if _encounter == null or not _pending.is_empty() or not _detached.is_empty() or _publishing or frame != _last_frame + 1:
		return false
	var state: Dictionary = _encounter.snapshot()
	var payload: Dictionary = _effects.work_snapshot()
	if state.is_empty() or payload.is_empty():
		return false
	return state.identity == _identity and state.encounter_digest == _digest and state.status in Encounter.LIVE_STATUSES + ["COMPLETE"] and (state.last_runtime_frame == _last_frame or (state.status == "COMPLETE" and state.last_runtime_frame <= _last_frame)) and payload.run_id == _identity.run_id and payload.runtime_frame == _last_frame


func launch_transaction_snapshot() -> Dictionary:
	return snapshot() if _pending.is_empty() and _detached.is_empty() and not _publishing else {}


func can_restore_launch_transaction_snapshot(value: Dictionary) -> bool:
	return _encounter != null and Contract.exact_fields(value, SNAPSHOT_FIELDS) and typeof(value.schema_version) == TYPE_INT and value.schema_version == 1 and value.run_id == _identity.run_id and Contract.integer_in_range(value.runtime_frame, int(_identity.runtime_frame), Encounter.MAX_FRAME) and value.encounter is Dictionary and _encounter.can_restore_snapshot(value.encounter) and (value.encounter.last_runtime_frame == value.runtime_frame or (value.encounter.status == "COMPLETE" and value.encounter.last_runtime_frame <= value.runtime_frame))


func restore_launch_transaction_snapshot(value: Dictionary) -> bool:
	if not _pending.is_empty() or not _detached.is_empty() or _publishing or not can_restore_launch_transaction_snapshot(value) or not _encounter.restore_snapshot(value.encounter):
		return false
	_last_frame = value.runtime_frame
	return true


func prepare_frame(effect_ticket: Dictionary) -> Dictionary:
	var transition: Dictionary = _effects.prepared_work_transition(effect_ticket) if _effects != null else {}
	if transition.is_empty() or not is_ready_for_frame(int(transition.after.runtime_frame)) or transition.before != _effects.work_snapshot():
		return _failure("unsealed_effect_transition")
	var before := snapshot()
	var previous: Dictionary = transition.before.records
	var current: Dictionary = transition.after.records
	if not _ledger_contains_work(before.encounter, transition.before):
		return _failure("stale_payload_ledger")
	var preview := Encounter.new()
	if not preview.configure(_encounter.configured_encounter(), _identity).ok or not preview.restore_snapshot(before.encounter):
		return _failure("encounter_checkpoint")
	for id: String in previous:
		if not preview.retire_pending_work(id):
			return _failure("payload_retirement")
	var ids := current.keys()
	ids.sort()
	for id: String in ids:
		var work: Dictionary = current[id]
		if not preview.reserve_pending_work(id, work.kind, work.owner_source_id, work.phase):
			return _failure("payload_budget_or_owner")
	var frame: int = transition.after.runtime_frame
	var result: Dictionary
	if preview.can_complete():
		if not current.is_empty():
			return _failure("completed_payloads")
		result = {"ok": true, "runtime_frame": frame, "wave_started": {}, "spawn_warnings": [], "spawn_requests": [], "encounter_completed": ""}
	else:
		result = preview.advance_frame(frame)
		if not result.ok:
			return _failure("encounter_frame")
	var after := before.duplicate(true)
	after.runtime_frame = frame
	after.encounter = preview.snapshot()
	var ticket := {"ticket_id": _next_ticket, "runtime_frame": frame, "before": before, "after": after, "effect_ticket": effect_ticket.duplicate(true), "transition": transition, "result": result}
	_next_ticket += 1
	_pending = ticket.duplicate(true)
	_committed = false
	return {"ok": true, "ticket": ticket.duplicate(true)}


func can_commit(ticket: Dictionary) -> bool:
	return _matches(ticket) and not _committed and snapshot() == ticket.before and _effects.prepared_work_transition(ticket.effect_ticket) == ticket.transition and _effects.work_snapshot() in [ticket.transition.before, ticket.transition.after]


func commit(ticket: Dictionary) -> bool:
	if not can_commit(ticket) or _effects.work_snapshot() != ticket.transition.after or not _encounter.restore_snapshot(ticket.after.encounter):
		return false
	_last_frame = ticket.runtime_frame
	_committed = true
	return true


func rollback(ticket: Dictionary) -> bool:
	if not _matches(ticket) or not _encounter.restore_snapshot(ticket.before.encounter):
		return false
	_last_frame = ticket.before.runtime_frame
	_pending.clear()
	_committed = false
	return true


func can_publish(ticket: Dictionary) -> bool:
	return _matches(ticket) and _committed and snapshot() == ticket.after and _effects.work_snapshot() == ticket.transition.after


func publish_frame_observations(ticket: Dictionary) -> bool:
	if _publishing or _detached.is_empty() or _detached.ticket != ticket:
		return false
	var result: Dictionary = _detached.result.duplicate(true)
	_detached.clear()
	_publishing = true
	encounter_frame_observed.emit(result)
	_publishing = false
	return true


func seal_frame_publication(ticket: Dictionary) -> bool:
	if not can_publish(ticket) or not _detached.is_empty():
		return false
	# Published Health callbacks may now authenticate deaths and remove roster rows.
	_detached = {"ticket": ticket.duplicate(true), "result": ticket.result.duplicate(true)}
	_pending.clear()
	_committed = false
	return true


func _matches(ticket: Dictionary) -> bool:
	return not _publishing and Contract.exact_fields(ticket, TICKET_FIELDS) and not _pending.is_empty() and ticket == _pending


static func _ledger_contains_work(state: Dictionary, payload: Dictionary) -> bool:
	var expected: Dictionary = payload.records
	for id: String in state.pending_work:
		if (id.begins_with("payload-") or id.begins_with("semantic_") or id.begins_with("debris_")) and not expected.has(id):
			return false
	for id: String in expected:
		if state.pending_work.get(id, {}) != expected[id]:
			return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "code": &"HOSTILE_ENCOUNTER_FRAME_INVALID", "context": {"reason": reason}}
