extends "res://scripts/progression/profile_runtime_service.gd"

const Endless := preload("res://scripts/modes/endless_session.gd")

var mode_session: Dictionary = {}
var mode_owner := ""
var _expected_primary: Dictionary = {}


func configure_mode(catalog: RefCounted, storage: RefCounted, profile_id: String, owner: String, initial: Dictionary, fingerprint: String) -> Dictionary:
	var result := configure(catalog, storage, profile_id, "endless", {"meta_profile_state": initial})
	if not result.ok:
		return result
	var primary = storage.inspect_profile(profile_id, "endless")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _failure(primary.code)
	var session: Variant = payload().get("endless_session", Endless.empty(fingerprint))
	if not Endless.valid(session, owner) or session.mode_fingerprint != fingerprint:
		return _failure(&"ENDLESS_SAVE_INVALID")
	mode_owner = owner
	mode_session = Endless.normalized(session)
	_expected_primary = primary.payload.duplicate(true) if primary.ok else {}
	return _success({})


func retire_cycle() -> Dictionary:
	if _busy or not Endless.valid(mode_session, mode_owner):
		return _failure(&"ENDLESS_SAVE_INVALID")
	var candidate := snapshot()
	candidate.active_launch_receipt = {}
	candidate.revision += 1
	var prepared: Dictionary = _profile.prepare_candidate(candidate)
	if not prepared.ok:
		return prepared
	return _persist_ticket(prepared.context.ticket, {"active_run_state": {}, "reward_effect_state": {}, "native_run_checkpoint": {}, "pending_meta_run_projection": {}, "pending_run_config": {}})


func save_mode_session() -> Dictionary:
	var candidate := snapshot()
	candidate.revision += 1
	var prepared: Dictionary = _profile.prepare_candidate(candidate)
	return _persist_ticket(prepared.context.ticket) if prepared.ok else prepared


func _persist_ticket(ticket: Dictionary, payload_changes: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = _profile.candidate_snapshot(ticket)
	if candidate.is_empty() or _busy or not Endless.valid(mode_session, mode_owner):
		return _failure(&"TICKET_INVALID")
	_busy = true
	var primary = _save.inspect_profile(_profile_id, _save_domain)
	if (not primary.ok and primary.code != &"NOT_FOUND") or (_expected_primary.is_empty() and primary.code != &"NOT_FOUND") or (not _expected_primary.is_empty() and (not primary.ok or not _json_equal(primary.payload, _expected_primary))):
		return _discard_failure(ticket, &"ENDLESS_STALE_PRIMARY")
	var next := _payload.duplicate(true)
	for key: String in payload_changes:
		next[key] = payload_changes[key].duplicate(true)
	next["meta_profile_state"] = candidate.duplicate(true)
	next["endless_session"] = mode_session.duplicate(true)
	for field: String in MIRROR_FIELDS:
		next[field] = _copy(candidate[field])
	next = _with_runtime_defaults(next)
	var written = _save.save_profile_compare_exchange(_profile_id, _save_domain, next, _expected_primary)
	var actual = _save.inspect_profile(_profile_id, _save_domain)
	if written.metadata.get("reason") == "expected_primary_stale":
		return _discard_failure(ticket, &"ENDLESS_STALE_PRIMARY")
	if not actual.ok or not _json_equal(actual.payload.payload, next):
		return _discard_failure(ticket, written.code if not written.ok else &"ENDLESS_SAVE_INVALID")
	var committed: Dictionary = _profile.commit_candidate(ticket)
	_busy = false
	if not committed.ok:
		return _failure(&"INTEGRITY_FAILURE")
	_payload = next
	_expected_primary = actual.payload.duplicate(true)
	return _success({"snapshot": snapshot(), "reconciled_committed_write": not written.ok})
