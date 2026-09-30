class_name WeaponActionCoordinator
extends RefCounted

signal weapon_action_committed(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	context: Dictionary
)
signal weapon_runtime_event(event: Dictionary)

const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")
const WeaponResourceTransactionScript := preload("res://scripts/combat/weapons/weapon_resource_transaction.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
const GAMEPLAY_REWIND_SNAPSHOT_SCHEMA_VERSION := 1
const FRAME_EVENT_PUBLICATION_SCHEMA_VERSION := 1
const PHASE_READY := &"READY"

var _runtime: RefCounted
var _resource_transaction: RefCounted
var _weapon_id: StringName = &""
var _phase: StringName = PHASE_READY
var _phase_index: int = -1
var _phase_frame: int = 0
var _frame: int = 0
var _generation: int = 1
var _token: int = 0
var _next_token: int = 1
var _plan: Dictionary = {}
var _action_context: Dictionary = {}
var _buffered_submission: Dictionary = {}
var _hold_intent_id: StringName = &""
var _hold_runtime_snapshot: Dictionary = {}
var _hold_live_context: Dictionary = {}
var _frame_event_buffer_active: bool = false
var _frame_event_buffer: Array[Dictionary] = []
var _frame_event_commit_fault_for_test: bool = false
var _next_frame_event_buffer_id: int = 1
var _active_frame_event_buffer_id: int = 0
var _next_frame_event_publication_id: int = 1
var _prepared_frame_event_publication: Dictionary = {}
var _finalized_frame_event_publication: Dictionary = {}
var _frame_event_publication_in_progress: bool = false
var _post_publication_frame_events: Array[Dictionary] = []


func configure(runtime: RefCounted, resource_transaction: RefCounted = null) -> bool:
	if runtime == null or not _runtime_has_contract(runtime):
		return false
	var runtime_weapon_id := StringName(str(runtime.call("weapon_id")))
	if runtime_weapon_id == &"":
		return false
	var next_transaction := resource_transaction
	if next_transaction == null:
		next_transaction = WeaponResourceTransactionScript.new()
		if not bool(next_transaction.call(
			"configure",
			runtime_weapon_id,
			PackedStringArray(),
			{}
		)):
			return false
	if not _resource_transaction_has_contract(next_transaction):
		return false
	if _runtime != null:
		cancel(&"runtime_reconfigured")
	_runtime = runtime
	_resource_transaction = next_transaction
	_weapon_id = runtime_weapon_id
	return true


func set_next_token_floor(next_token_floor: int) -> bool:
	if next_token_floor <= 0 or _phase != PHASE_READY or _token != 0:
		return false
	_next_token = maxi(_next_token, next_token_floor)
	return true


func submit_intent(intent: Dictionary, context: Dictionary) -> Dictionary:
	var intent_validation: Dictionary = WeaponActionContractScript.validate_intent(intent)
	if not bool(intent_validation.get("ok", false)):
		return intent_validation
	var context_validation := _validate_submission_context(context)
	if not bool(context_validation.get("ok", false)):
		return context_validation
	if _runtime == null:
		return WeaponActionContractScript.failure(WeaponActionContractScript.CODE_NOT_CONFIGURED)
	var edge := StringName(str(intent.get("edge", "")))
	if edge in [&"held", &"released"]:
		return _submit_hold_edge(intent, context)
	if _phase != PHASE_READY:
		var live_submission := _submit_live_intent(intent, context)
		if bool(live_submission.get("handled", false)):
			var live_result: Variant = live_submission.get("result", {})
			return (
				(live_result as Dictionary).duplicate(true)
				if live_result is Dictionary
				else WeaponActionContractScript.failure(
					WeaponActionContractScript.CODE_COMMIT_FAILED,
					{"reason": "live_intent_result_type"}
				)
			)

	if _phase != PHASE_READY and not _recovery_cancel_is_open():
		var busy_plan_result := _plan_busy_submission(intent, context)
		if not bool(busy_plan_result.get("ok", false)):
			var failure_value: Variant = busy_plan_result.get("failure", {})
			return (
				(failure_value as Dictionary).duplicate(true)
				if failure_value is Dictionary
				else WeaponActionContractScript.failure(
					WeaponActionContractScript.CODE_RUNTIME_REJECTED,
					{"reason": "busy_plan_failure_type"}
				)
			)
		var live_input_phase := StringName(str(busy_plan_result.get("live_input_phase", "")))
		if live_input_phase != &"":
			return WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_RUNTIME_REJECTED,
				{
					"reason": "live_input_buffer_forbidden",
					"phase": str(live_input_phase),
				}
			)
		var buffer_frames := int(intent.get(
			"buffer_frames",
			WeaponActionContractScript.DEFAULT_BUFFER_FRAMES
		))
		_buffered_submission = {
			"intent": intent.duplicate(true),
			"context": context.duplicate(true),
			"expires_at_frame": _frame + buffer_frames,
		}
		return WeaponActionContractScript.success(
			WeaponActionContractScript.CODE_BUFFERED,
			{"expires_at_frame": _frame + buffer_frames}
		)

	return _commit_intent(intent, context, _phase != PHASE_READY)


func advance_frame(consume_buffered: bool = true) -> bool:
	if _resource_transaction != null:
		_resource_transaction.call("advance_frame")
	_frame += 1
	if not _advance_runtime_tick():
		return false
	_prune_expired_buffer()
	if _phase == PHASE_READY:
		if consume_buffered:
			_consume_buffered_submission()
		return true

	_phase_frame += 1
	var phase_data := _current_phase_data()
	if phase_data.is_empty():
		cancel(&"invalid_phase_state")
		return false
	if not _emit_action_frame_events():
		return false
	if _phase == &"HOLD":
		if _phase_frame >= int(phase_data["duration_frames"]):
			_release_hold(true)
		return true
	if _phase_frame >= int(phase_data["duration_frames"]):
		_advance_phase(consume_buffered)
	if consume_buffered and _phase != PHASE_READY and _recovery_cancel_is_open():
		_consume_buffered_submission()
	return true


func begin_frame_event_buffer() -> bool:
	if (
		_frame_event_buffer_active
		or not _prepared_frame_event_publication.is_empty()
		or not _finalized_frame_event_publication.is_empty()
		or _frame_event_publication_in_progress
	):
		return false
	_frame_event_buffer.clear()
	_frame_event_buffer_active = true
	_active_frame_event_buffer_id = _next_frame_event_buffer_id
	_next_frame_event_buffer_id += 1
	return true


func frame_event_buffer_is_active() -> bool:
	return _frame_event_buffer_active


func can_commit_frame_event_buffer() -> bool:
	return (
		_frame_event_buffer_active
		and _active_frame_event_buffer_id > 0
		and _finalized_frame_event_publication.is_empty()
		and not _frame_event_publication_in_progress
		and not _frame_event_commit_fault_for_test
	)


func prepare_frame_event_publication() -> Dictionary:
	if not can_commit_frame_event_buffer():
		return {}
	if not _prepared_frame_event_publication.is_empty():
		return _prepared_frame_event_publication.duplicate(true)
	var publication := {
		"schema_version": FRAME_EVENT_PUBLICATION_SCHEMA_VERSION,
		"publication_id": _next_frame_event_publication_id,
		"owner_instance_id": get_instance_id(),
		"buffer_id": _active_frame_event_buffer_id,
		"events": _frame_event_buffer.duplicate(true),
	}
	_next_frame_event_publication_id += 1
	publication["fingerprint"] = _frame_event_publication_fingerprint(publication)
	_prepared_frame_event_publication = publication.duplicate(true)
	return publication.duplicate(true)


func finalize_frame_event_publication(publication: Dictionary) -> bool:
	if (
		not _frame_event_buffer_active
		or _active_frame_event_buffer_id <= 0
		or not _finalized_frame_event_publication.is_empty()
		or _frame_event_publication_in_progress
		or not _frame_event_publication_matches(publication)
		or _frame_event_buffer != publication.get("events", [])
	):
		return false
	_frame_event_buffer.clear()
	_frame_event_buffer_active = false
	_active_frame_event_buffer_id = 0
	_finalized_frame_event_publication = _prepared_frame_event_publication.duplicate(true)
	_prepared_frame_event_publication.clear()
	return true


func discard_finalized_frame_event_publication(publication: Dictionary) -> bool:
	if (
		_frame_event_publication_in_progress
		or not _finalized_frame_event_publication_matches(publication)
	):
		return false
	_finalized_frame_event_publication.clear()
	return true


func publish_prepared_frame_events() -> void:
	if _finalized_frame_event_publication.is_empty() or _frame_event_publication_in_progress:
		return
	var events: Array = (
		_finalized_frame_event_publication.get("events", []) as Array
	).duplicate(true)
	_finalized_frame_event_publication.clear()
	_frame_event_publication_in_progress = true
	_flush_frame_event_entries(events)
	while not _post_publication_frame_events.is_empty():
		var deferred: Array = _post_publication_frame_events.duplicate(true)
		_post_publication_frame_events.clear()
		_flush_frame_event_entries(deferred)
	_frame_event_publication_in_progress = false


func commit_frame_event_buffer() -> bool:
	var publication := prepare_frame_event_publication()
	if publication.is_empty() or not finalize_frame_event_publication(publication):
		return false
	publish_prepared_frame_events()
	return true


func rollback_frame_event_buffer() -> bool:
	if not _frame_event_buffer_active:
		return false
	_frame_event_buffer.clear()
	_frame_event_buffer_active = false
	_active_frame_event_buffer_id = 0
	_prepared_frame_event_publication.clear()
	return true


func _frame_event_publication_matches(publication: Dictionary) -> bool:
	if (
		_prepared_frame_event_publication.is_empty()
		or publication.size() != 6
		or typeof(publication.get("schema_version")) != TYPE_INT
		or int(publication.get("schema_version", -1))
		!= FRAME_EVENT_PUBLICATION_SCHEMA_VERSION
		or typeof(publication.get("publication_id")) != TYPE_INT
		or int(publication.get("publication_id", 0)) <= 0
		or typeof(publication.get("owner_instance_id")) != TYPE_INT
		or int(publication.get("owner_instance_id", 0)) != get_instance_id()
		or typeof(publication.get("buffer_id")) != TYPE_INT
		or int(publication.get("buffer_id", 0)) != _active_frame_event_buffer_id
		or not publication.get("events") is Array
		or typeof(publication.get("fingerprint")) != TYPE_STRING
		or str(publication.get("fingerprint", ""))
		!= _frame_event_publication_fingerprint(publication)
	):
		return false
	return publication == _prepared_frame_event_publication


func _finalized_frame_event_publication_matches(publication: Dictionary) -> bool:
	if (
		_finalized_frame_event_publication.is_empty()
		or publication.size() != 6
		or typeof(publication.get("schema_version")) != TYPE_INT
		or int(publication.get("schema_version", -1))
		!= FRAME_EVENT_PUBLICATION_SCHEMA_VERSION
		or typeof(publication.get("publication_id")) != TYPE_INT
		or int(publication.get("publication_id", 0)) <= 0
		or typeof(publication.get("owner_instance_id")) != TYPE_INT
		or int(publication.get("owner_instance_id", 0)) != get_instance_id()
		or typeof(publication.get("buffer_id")) != TYPE_INT
		or int(publication.get("buffer_id", 0)) <= 0
		or not publication.get("events") is Array
		or typeof(publication.get("fingerprint")) != TYPE_STRING
		or str(publication.get("fingerprint", ""))
		!= _frame_event_publication_fingerprint(publication)
	):
		return false
	return publication == _finalized_frame_event_publication


func _frame_event_publication_fingerprint(publication: Dictionary) -> String:
	var signed := publication.duplicate(true)
	signed.erase("fingerprint")
	return var_to_bytes(signed).hex_encode().sha256_text()


func _flush_frame_event_entries(entries: Array) -> void:
	for entry_value: Variant in entries:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		match StringName(str(entry.get("type", ""))):
			&"runtime_event":
				weapon_runtime_event.emit(
					(entry.get("event", {}) as Dictionary).duplicate(true)
				)
			&"action_committed":
				weapon_action_committed.emit(
					StringName(str(entry.get("weapon_id", ""))),
					StringName(str(entry.get("action_id", ""))),
					int(entry.get("token", 0)),
					(entry.get("context", {}) as Dictionary).duplicate(true)
				)


func consume_buffered_intent() -> bool:
	if _buffered_submission.is_empty():
		return false
	if _phase != PHASE_READY and not _recovery_cancel_is_open():
		return false
	var token_before := _token
	var generation_before := _generation
	_consume_buffered_submission()
	return _token != token_before or _generation != generation_before


func cancel(reason: StringName = &"cancelled") -> void:
	var restore_uncommitted_hold := _phase == &"HOLD" and not _hold_runtime_snapshot.is_empty()
	var hold_runtime_snapshot := _hold_runtime_snapshot.duplicate(true)
	if _runtime != null and _token > 0:
		_runtime.call("cancel_action", _token, reason)
	if restore_uncommitted_hold and _runtime != null:
		if not _restore_runtime_snapshot_strict(hold_runtime_snapshot):
			_runtime.call("reset_runtime_state", &"hold_cancel_rollback_failed")
	_generation += 1
	_buffered_submission.clear()
	_clear_action_state()


func reset_runtime_state(reason: StringName = &"reset") -> void:
	var generation_before := _generation
	var had_active_token := _token > 0
	cancel(reason)
	if not had_active_token:
		_generation = generation_before
	_frame = 0
	if _runtime != null:
		_runtime.call("reset_runtime_state", reason)
	if _resource_transaction != null:
		_resource_transaction.call("reset_runtime_state")


func restore_rewind_safe_state(reason: StringName = &"rewind_restore") -> void:
	cancel_for_gameplay_rewind(reason)


func cancel_for_gameplay_rewind(reason: StringName = &"gameplay_rewind") -> bool:
	if _runtime == null or _resource_transaction == null:
		return false
	var before := gameplay_rewind_snapshot()
	if before.is_empty():
		return false
	var hold_snapshot := (
		_hold_runtime_snapshot.duplicate(true)
		if _phase == &"HOLD" and not _hold_runtime_snapshot.is_empty()
		else {}
	)
	var cancelled_value: Variant = _runtime.call(
		"cancel_for_gameplay_rewind",
		_token,
		reason,
		hold_snapshot
	)
	if typeof(cancelled_value) != TYPE_BOOL or not bool(cancelled_value):
		if not _restore_gameplay_runtime_after_failed_cancel(before):
			_force_restore_fail_closed(&"gameplay_rewind_cancel_rollback_failed", before, before)
		return false
	if (
		_gameplay_rewind_payload_guard() != before["committed_payload_guard"]
		or _resource_transaction.call("snapshot") != before["resource_transaction"]
	):
		if not _restore_gameplay_runtime_after_failed_cancel(before):
			_force_restore_fail_closed(&"gameplay_rewind_guard_rollback_failed", before, before)
		return false
	_generation += 1
	_buffered_submission.clear()
	_clear_action_state()
	if _resource_transaction != null:
		_resource_transaction.call("rewind_safe_reset")
	return (
		_gameplay_rewind_payload_guard() == before["committed_payload_guard"]
		and _resource_transaction.call("snapshot") == before["resource_transaction"]
	)


func gameplay_rewind_snapshot() -> Dictionary:
	if _runtime == null or _resource_transaction == null:
		return {}
	var full := snapshot()
	var gameplay_runtime_value: Variant = _runtime.call("gameplay_rewind_snapshot")
	var payload_guard := _gameplay_rewind_payload_guard()
	if not gameplay_runtime_value is Dictionary:
		return {}
	full["gameplay_rewind_schema_version"] = GAMEPLAY_REWIND_SNAPSHOT_SCHEMA_VERSION
	full["gameplay_runtime"] = (gameplay_runtime_value as Dictionary).duplicate(true)
	full["committed_payload_guard"] = payload_guard
	return full


func restore_gameplay_rewind_snapshot_for_rollback(value: Dictionary) -> bool:
	if (
		_runtime == null
		or _resource_transaction == null
		or not _validate_gameplay_rewind_snapshot(value)
		or _gameplay_rewind_payload_guard() != value["committed_payload_guard"]
		or _resource_transaction.call("snapshot") != value["resource_transaction"]
	):
		return false
	var before := gameplay_rewind_snapshot()
	if before.is_empty():
		return false
	var restored_value: Variant = _runtime.call(
		"restore_gameplay_rewind_snapshot_for_rollback",
		(value["gameplay_runtime"] as Dictionary).duplicate(true)
	)
	if typeof(restored_value) != TYPE_BOOL or not bool(restored_value):
		if not _restore_gameplay_runtime_after_failed_cancel(before):
			_force_restore_fail_closed(&"gameplay_rewind_restore_rollback_failed", before, value)
		return false
	_install_snapshot_state(value)
	if gameplay_rewind_snapshot() == value:
		return true
	var runtime_rollback_value: Variant = _runtime.call(
		"restore_gameplay_rewind_snapshot_for_rollback",
		(before["gameplay_runtime"] as Dictionary).duplicate(true)
	)
	if typeof(runtime_rollback_value) == TYPE_BOOL and bool(runtime_rollback_value):
		_install_snapshot_state(before)
		if gameplay_rewind_snapshot() == before:
			return false
	_force_restore_fail_closed(&"gameplay_rewind_verification_rollback_failed", before, value)
	return false


func phase_name() -> StringName:
	return _phase


func current_token() -> int:
	return _token


func generation() -> int:
	return _generation


func is_action_token_current(token: int, action_generation: int) -> bool:
	return (
		token > 0
		and _token == token
		and _generation == action_generation
		and _phase != PHASE_READY
	)


func movement_multiplier() -> float:
	var phase_data := _current_phase_data()
	if phase_data.is_empty():
		return 1.0
	if _phase == &"HOLD":
		return float(_hold_progress(phase_data).get("movement_multiplier", 1.0))
	return float(phase_data.get("movement_multiplier", 1.0))


func cooldown_remaining(action_id: StringName) -> int:
	if _resource_transaction == null:
		return 0
	return int(_resource_transaction.call("cooldown_remaining", action_id))


func recovery_cancel_is_open() -> bool:
	return _recovery_cancel_is_open()


func update_live_context(context: Dictionary) -> bool:
	if _phase != &"HOLD" or _runtime == null or _token <= 0:
		return false
	var validation := _validate_submission_context(context)
	if not bool(validation.get("ok", false)):
		return false
	if _runtime.has_method("update_hold_context"):
		var updated_value: Variant = _runtime.call(
			"update_hold_context",
			_plan.duplicate(true),
			_token,
			context.duplicate(true)
		)
		if typeof(updated_value) != TYPE_BOOL or not bool(updated_value):
			return false
	_hold_live_context = context.duplicate(true)
	return true


func snapshot() -> Dictionary:
	var runtime_snapshot: Dictionary = {}
	if _runtime != null:
		var runtime_value: Variant = _runtime.call("snapshot")
		if runtime_value is Dictionary:
			runtime_snapshot = (runtime_value as Dictionary).duplicate(true)
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"weapon_id": str(_weapon_id),
		"frame": _frame,
		"generation": _generation,
		"next_token": _next_token,
		"token": _token,
		"phase": str(_phase),
		"phase_index": _phase_index,
		"phase_frame": _phase_frame,
		"plan": _plan.duplicate(true),
		"action_context": _action_context.duplicate(true),
		"buffered_submission": _buffered_submission.duplicate(true),
		"hold_intent_id": str(_hold_intent_id),
		"hold_runtime_snapshot": _hold_runtime_snapshot.duplicate(true),
		"hold_live_context": _hold_live_context.duplicate(true),
		"runtime": runtime_snapshot,
		"resource_transaction": (
			(_resource_transaction.call("snapshot") as Dictionary).duplicate(true)
			if _resource_transaction != null
			else {}
		),
	}


func restore_safe(safe_snapshot: Dictionary) -> bool:
	if _runtime == null or not _validate_safe_snapshot(safe_snapshot):
		return false

	var runtime_before_value: Variant = _runtime.call("snapshot")
	if not runtime_before_value is Dictionary:
		return false
	var runtime_before := (runtime_before_value as Dictionary).duplicate(true)
	var target_runtime := (safe_snapshot["runtime"] as Dictionary).duplicate(true)
	if (
		not bool(_runtime.call("restore_snapshot", target_runtime))
		or not _runtime_snapshot_matches(target_runtime)
	):
		if not _restore_runtime_snapshot_strict(runtime_before):
			_force_restore_fail_closed(
				&"safe_restore_rollback_failed",
				{"generation": _generation, "next_token": _next_token, "frame": _frame},
				safe_snapshot
			)
		return false

	var previous_generation := _generation
	_frame = int(safe_snapshot["frame"])
	_next_token = maxi(_next_token, int(safe_snapshot["next_token"]))
	_generation = maxi(previous_generation, int(safe_snapshot["generation"])) + 1
	_buffered_submission.clear()
	_clear_action_state()
	return true


func restore_snapshot(value: Dictionary) -> bool:
	return _restore_snapshot_internal(value, true)


func restore_snapshot_for_rollback(value: Dictionary) -> bool:
	return _restore_snapshot_internal(value, false)


func _restore_snapshot_internal(value: Dictionary, enforce_monotonicity: bool) -> bool:
	if (
		_runtime == null
		or _resource_transaction == null
		or not _validate_runtime_snapshot(value)
		or (enforce_monotonicity and not _snapshot_token_transition_is_monotonic(value))
	):
		return false

	var before := snapshot()
	var runtime_before := (before["runtime"] as Dictionary).duplicate(true)
	var resource_before := (before["resource_transaction"] as Dictionary).duplicate(true)
	if not bool(_runtime.call("restore_snapshot", (value["runtime"] as Dictionary).duplicate(true))):
		if not _restore_runtime_snapshot_strict(runtime_before):
			_force_restore_fail_closed(&"runtime_target_rollback_failed", before, value)
		return false
	if not bool(_resource_transaction.call(
		"restore_snapshot",
		(value["resource_transaction"] as Dictionary).duplicate(true)
	)):
		var resource_rollback_ok := true
		if not _resource_snapshot_matches(resource_before):
			resource_rollback_ok = _restore_resource_snapshot_strict(resource_before)
		var runtime_rollback_ok := _restore_runtime_snapshot_strict(runtime_before)
		if not resource_rollback_ok or not runtime_rollback_ok:
			_force_restore_fail_closed(&"resource_target_rollback_failed", before, value)
		return false

	_install_snapshot_state(value)
	if snapshot() != value:
		var resource_rollback_ok := _restore_resource_snapshot_strict(resource_before)
		var runtime_rollback_ok := _restore_runtime_snapshot_strict(runtime_before)
		if resource_rollback_ok and runtime_rollback_ok:
			_install_snapshot_state(before)
			if snapshot() == before:
				return false
		_force_restore_fail_closed(&"snapshot_verification_rollback_failed", before, value)
		return false
	return true


func presentation_snapshot(cooldown_action_id: StringName = &"") -> Dictionary:
	var runtime_presentation: Dictionary = {}
	if _runtime != null:
		var runtime_value: Variant = _runtime.call("presentation_snapshot")
		if runtime_value is Dictionary:
			runtime_presentation = (runtime_value as Dictionary).duplicate(true)
	var cooldown_ledger: Dictionary = {}
	if _resource_transaction != null:
		var resource_snapshot_value: Variant = _resource_transaction.call("snapshot")
		if resource_snapshot_value is Dictionary:
			var cooldowns_value: Variant = (resource_snapshot_value as Dictionary).get("cooldowns", {})
			if cooldowns_value is Dictionary:
				cooldown_ledger = (cooldowns_value as Dictionary).duplicate(true)
	var active_action_id := StringName(str(_plan.get("action_id", "")))
	var queried_cooldown_action_id := (
		cooldown_action_id
		if cooldown_action_id != &""
		else active_action_id
	)
	var phase_data := _current_phase_data()
	var result := {
		"weapon_id": str(_weapon_id),
		"action_id": str(active_action_id),
		"phase": str(_phase),
		"phase_frame": _phase_frame,
		"phase_duration_frames": int(phase_data.get("duration_frames", 0)),
		"cancel_from_frame": int(phase_data.get("cancel_from_frame", -1)),
		"movement_multiplier": movement_multiplier(),
		"hold_frames": _phase_frame if _phase == &"HOLD" else 0,
		"minimum_hold_frames": int(phase_data.get("minimum_hold_frames", 0)) if _phase == &"HOLD" else 0,
		"maximum_hold_frames": int(phase_data.get("duration_frames", 0)) if _phase == &"HOLD" else 0,
		"token": _token,
		"generation": _generation,
		"runtime": runtime_presentation,
		"cooldown_action_id": str(queried_cooldown_action_id),
		"cooldown_remaining_frames": cooldown_remaining(queried_cooldown_action_id),
		"cooldown_ledger": cooldown_ledger,
	}
	if _phase == &"HOLD":
		var hold_progress := _hold_progress(phase_data)
		for field: String in [
			"hold_frames",
			"effective_hold_frames",
			"minimum_hold_frames",
			"charge_complete_frames",
			"maximum_hold_frames",
			"charge_ratio",
			"movement_multiplier",
		]:
			result[field] = hold_progress[field]
	else:
		for field: String in [
			"charge_frames",
			"maximum_charge_frames",
			"charge_ratio",
			"full_charge",
			"facing",
			"cue_id",
		]:
			if runtime_presentation.has(field):
				result[field] = runtime_presentation[field]
	return result


func _commit_intent(intent: Dictionary, context: Dictionary, replacing_action: bool) -> Dictionary:
	var context_validation := _validate_submission_context(context)
	if not bool(context_validation.get("ok", false)):
		return context_validation
	var planned_value: Variant = _runtime.call(
		"plan_intent",
		intent.duplicate(true),
		context.duplicate(true)
	)
	if not planned_value is Dictionary:
		return WeaponActionContractScript.failure(
			WeaponActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "plan_result_type"}
		)
	var planned := planned_value as Dictionary
	if not bool(planned.get("ok", false)):
		return _runtime_failure(planned, WeaponActionContractScript.CODE_RUNTIME_REJECTED)
	var plan_value: Variant = planned.get("plan")
	if not plan_value is Dictionary:
		return WeaponActionContractScript.failure(
			WeaponActionContractScript.CODE_INVALID_PLAN,
			{"field": "plan", "reason": "type"}
		)
	var committed_plan := (plan_value as Dictionary).duplicate(true)
	var plan_validation: Dictionary = WeaponActionContractScript.validate_plan(committed_plan, _weapon_id)
	if not bool(plan_validation.get("ok", false)):
		return plan_validation
	var starts_with_hold := _plan_starts_with_hold(committed_plan)
	var next_action_token := _next_token
	var resource_ticket: Dictionary = {}
	var prepared: Dictionary = _resource_transaction.call(
		"prepare",
		committed_plan.duplicate(true),
		next_action_token
	)
	if not bool(prepared.get("ok", false)):
		return _resource_failure(prepared)
	if not starts_with_hold:
		resource_ticket = (prepared.get("ticket", {}) as Dictionary).duplicate(true)

	var runtime_before_value: Variant = _runtime.call("snapshot")
	if not runtime_before_value is Dictionary:
		return WeaponActionContractScript.failure(
			WeaponActionContractScript.CODE_COMMIT_FAILED,
			{"reason": "runtime_snapshot_type"}
		)
	var runtime_before := (runtime_before_value as Dictionary).duplicate(true)
	var replaced_token := _token
	if replacing_action and replaced_token > 0:
		_runtime.call("cancel_action", replaced_token, &"replaced_at_cancel_window")
	var hold_runtime_before: Dictionary = {}
	if starts_with_hold:
		var hold_runtime_before_value: Variant = _runtime.call("snapshot")
		if not hold_runtime_before_value is Dictionary:
			if not _restore_runtime_snapshot_strict(runtime_before):
				_force_runtime_safe_reset(&"hold_snapshot_rollback_failed")
				return WeaponActionContractScript.failure(
					WeaponActionContractScript.CODE_COMMIT_FAILED,
					{"reason": "rollback_failed"}
				)
			return WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_COMMIT_FAILED,
				{"reason": "hold_runtime_snapshot_type"}
			)
		hold_runtime_before = (hold_runtime_before_value as Dictionary).duplicate(true)

	var commit_value: Variant = _runtime.call(
		"commit_action",
		committed_plan.duplicate(true),
		next_action_token
	)
	if not commit_value is Dictionary or not bool((commit_value as Dictionary).get("ok", false)):
		if not _restore_runtime_snapshot_strict(runtime_before):
			_force_runtime_safe_reset(&"commit_rollback_failed")
			return WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_COMMIT_FAILED,
				{"reason": "rollback_failed"}
			)
		if commit_value is Dictionary:
			return _runtime_failure(commit_value as Dictionary, WeaponActionContractScript.CODE_COMMIT_FAILED)
		return WeaponActionContractScript.failure(
			WeaponActionContractScript.CODE_COMMIT_FAILED,
			{"reason": "commit_result_type"}
		)

	var resource_context: Dictionary = {}
	if not starts_with_hold:
		var resource_commit: Dictionary = _resource_transaction.call(
			"commit",
			resource_ticket.duplicate(true)
		)
		if not bool(resource_commit.get("ok", false)):
			if not _restore_runtime_snapshot_strict(runtime_before):
				_force_runtime_safe_reset(&"resource_commit_rollback_failed")
				return WeaponActionContractScript.failure(
					WeaponActionContractScript.CODE_COMMIT_FAILED,
					{"reason": "rollback_failed"}
				)
			return _resource_failure(resource_commit)
		resource_context = (resource_commit.get("context", {}) as Dictionary).duplicate(true)

	if replacing_action:
		_generation += 1
	_plan = committed_plan
	_action_context = context.duplicate(true)
	_token = next_action_token
	_next_token += 1
	_phase_index = 0
	_phase_frame = 0
	_phase = StringName(str(_current_phase_data().get("phase", "")))
	_hold_intent_id = StringName(str(intent.get("id", ""))) if _phase == &"HOLD" else &""
	_hold_runtime_snapshot = hold_runtime_before.duplicate(true) if starts_with_hold else {}
	_hold_live_context = context.duplicate(true) if starts_with_hold else {}
	_buffered_submission.clear()

	var committed_token := _token
	var committed_generation := _generation
	var commit_context_value: Variant = (commit_value as Dictionary).get("context", {})
	var commit_context: Dictionary = (
		(commit_context_value as Dictionary).duplicate(true)
		if commit_context_value is Dictionary
		else {}
	)
	if not starts_with_hold:
		_action_context = _committed_context(
			_action_context,
			_plan,
			_token,
			_generation,
			{},
			resource_context
		)
		_publish_weapon_action_committed(
			_weapon_id,
			StringName(str(_plan["action_id"])),
			_token,
			_action_context.duplicate(true)
		)
	_enter_current_phase()
	return {
		"ok": true,
		"code": WeaponActionContractScript.CODE_OK,
		"token": committed_token,
		"generation": committed_generation,
		"context": commit_context,
	}


func _submit_hold_edge(intent: Dictionary, context: Dictionary) -> Dictionary:
	var intent_id := StringName(str(intent.get("id", "")))
	if _phase != &"HOLD" or _token <= 0 or intent_id != _hold_intent_id:
		return WeaponActionContractScript.failure(
			WeaponActionContractScript.CODE_STALE_HOLD_EDGE,
			{
				"intent_id": str(intent_id),
				"phase": str(_phase),
			}
		)
	if StringName(str(intent.get("edge", ""))) == &"held":
		if not update_live_context(context):
			return WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_RUNTIME_REJECTED,
				{"reason": "hold_context_rejected"}
			)
		return {
			"ok": true,
			"code": WeaponActionContractScript.CODE_HOLDING,
			"token": _token,
			"generation": _generation,
			"held_frames": _phase_frame,
			"context": {},
		}
	if not update_live_context(context):
		return WeaponActionContractScript.failure(
			WeaponActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "hold_context_rejected"}
		)
	return _release_hold(false)


func _release_hold(automatic: bool) -> Dictionary:
	if _runtime == null or _phase != &"HOLD" or _token <= 0:
		return WeaponActionContractScript.failure(WeaponActionContractScript.CODE_STALE_HOLD_EDGE)
	var phase_data := _current_phase_data()
	var maximum_hold_frames := int(phase_data.get("duration_frames", 0))
	var minimum_hold_frames := int(phase_data.get("minimum_hold_frames", 0))
	var held_frames := mini(_phase_frame, maximum_hold_frames)
	var released_token := _token
	var released_generation := _generation
	if held_frames < minimum_hold_frames:
		cancel(&"hold_below_minimum")
		return WeaponActionContractScript.failure(
			WeaponActionContractScript.CODE_HOLD_TOO_SHORT,
			{
				"held_frames": held_frames,
				"minimum_hold_frames": minimum_hold_frames,
				"automatic": automatic,
			}
		)

	var runtime_before_value: Variant = _runtime.call("snapshot")
	if not runtime_before_value is Dictionary:
		cancel(&"hold_release_snapshot_type")
		return WeaponActionContractScript.failure(
			WeaponActionContractScript.CODE_COMMIT_FAILED,
			{"reason": "runtime_snapshot_type"}
		)
	var runtime_before := (runtime_before_value as Dictionary).duplicate(true)
	var release_value: Variant = _runtime.call(
		"release_hold",
		_plan.duplicate(true),
		_token,
		held_frames
	)
	if not release_value is Dictionary or not bool((release_value as Dictionary).get("ok", false)):
		var failure_result := (
			_runtime_failure(release_value as Dictionary, WeaponActionContractScript.CODE_COMMIT_FAILED)
			if release_value is Dictionary
			else WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_COMMIT_FAILED,
				{"reason": "hold_release_result_type"}
			)
		)
		return _rollback_and_cancel_hold_release(runtime_before, failure_result)

	var finalized_value: Variant = (release_value as Dictionary).get("finalized_plan")
	if not finalized_value is Dictionary:
		return _rollback_and_cancel_hold_release(
			runtime_before,
			WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_INVALID_PLAN,
				{"field": "finalized_plan", "reason": "type"}
			)
		)
	var finalized_plan := (finalized_value as Dictionary).duplicate(true)
	finalized_plan.erase("allowed_release_action_ids")
	finalized_plan.erase("release_action_fingerprints")
	var finalized_validation: Dictionary = WeaponActionContractScript.validate_plan(
		finalized_plan,
		_weapon_id
	)
	if not bool(finalized_validation.get("ok", false)):
		return _rollback_and_cancel_hold_release(runtime_before, finalized_validation)
	var identity_validation := _validate_finalized_hold_identity(finalized_plan)
	if not bool(identity_validation.get("ok", false)):
		return _rollback_and_cancel_hold_release(runtime_before, identity_validation)
	var finalized_phases: Array = finalized_plan.get("phases", [])
	var finalized_phase_names: Array[StringName] = []
	for phase_value: Variant in finalized_phases:
		finalized_phase_names.append(StringName(str((phase_value as Dictionary).get("phase", ""))))
	if finalized_phase_names != [&"WINDUP", &"ACTIVE", &"RECOVERY"]:
		return _rollback_and_cancel_hold_release(
			runtime_before,
			WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_INVALID_PLAN,
				{"field": "phases", "reason": "invalid_hold_finalized_sequence"}
			)
		)
	var prepared: Dictionary = _resource_transaction.call(
		"prepare",
		finalized_plan.duplicate(true),
		_token
	)
	if not bool(prepared.get("ok", false)):
		return _rollback_and_cancel_hold_release(runtime_before, _resource_failure(prepared))
	var resource_commit: Dictionary = _resource_transaction.call(
		"commit",
		(prepared.get("ticket", {}) as Dictionary).duplicate(true)
	)
	if not bool(resource_commit.get("ok", false)):
		return _rollback_and_cancel_hold_release(runtime_before, _resource_failure(resource_commit))

	_plan = finalized_plan
	_phase = PHASE_READY
	_phase_index = -1
	_phase_frame = 0
	_hold_intent_id = &""
	if not _hold_live_context.is_empty():
		_action_context = _hold_live_context.duplicate(true)
	_hold_live_context.clear()
	_phase_index = 0
	_phase = StringName(str(_current_phase_data().get("phase", "")))
	var release_context_value: Variant = (release_value as Dictionary).get("context", {})
	var release_context := (
		(release_context_value as Dictionary).duplicate(true)
		if release_context_value is Dictionary
		else {}
	)
	_action_context = _committed_context(
		_action_context,
		_plan,
		released_token,
		released_generation,
		release_context,
		(resource_commit.get("context", {}) as Dictionary).duplicate(true)
	)
	_hold_runtime_snapshot.clear()
	_publish_weapon_action_committed(
		_weapon_id,
		StringName(str(_plan["action_id"])),
		released_token,
		_action_context.duplicate(true)
	)
	_enter_current_phase()
	return {
		"ok": true,
		"code": WeaponActionContractScript.CODE_HOLD_RELEASED,
		"token": released_token,
		"generation": released_generation,
		"held_frames": held_frames,
		"automatic": automatic,
		"context": release_context,
	}


func _validate_finalized_hold_identity(finalized_plan: Dictionary) -> Dictionary:
	for field: String in ["weapon_id", "profile_id", "profile_version"]:
		var finalized_value: Variant = finalized_plan.get(field)
		var skeleton_value: Variant = _plan.get(field)
		if typeof(finalized_value) != typeof(skeleton_value) or finalized_value != skeleton_value:
			return WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_INVALID_PLAN,
				{"field": field, "reason": "hold_identity_mismatch"}
			)
	var allowed_value: Variant = _plan.get("allowed_release_action_ids", [])
	var fingerprints_value: Variant = _plan.get("release_action_fingerprints", {})
	if allowed_value is Array and not (allowed_value as Array).is_empty():
		var finalized_action_id := str(finalized_plan.get("action_id", ""))
		if not (allowed_value as Array).has(finalized_action_id):
			return WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_INVALID_PLAN,
				{"field": "action_id", "reason": "undeclared_hold_release_variant"}
			)
		var expected_fingerprint := str((fingerprints_value as Dictionary).get(
			finalized_action_id,
			""
		)) if fingerprints_value is Dictionary else ""
		if (
			expected_fingerprint.is_empty()
			or str(finalized_plan.get("release_action_fingerprint", "")) != expected_fingerprint
		):
			return WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_INVALID_PLAN,
				{"field": "release_action_fingerprint", "reason": "hold_identity_mismatch"}
			)
		return WeaponActionContractScript.success()
	if finalized_plan.has("release_action_fingerprint"):
		return WeaponActionContractScript.failure(
			WeaponActionContractScript.CODE_INVALID_PLAN,
			{"field": "release_action_fingerprint", "reason": "unexpected_hold_variant"}
		)
	for field: String in ["action_id", "cooldown_frames", "resource_costs"]:
		var finalized_value: Variant = finalized_plan.get(field)
		var skeleton_value: Variant = _plan.get(field)
		if typeof(finalized_value) != typeof(skeleton_value) or finalized_value != skeleton_value:
			return WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_INVALID_PLAN,
				{"field": field, "reason": "hold_identity_mismatch"}
			)
	return WeaponActionContractScript.success()


func _rollback_and_cancel_hold_release(
	runtime_before: Dictionary,
	failure_result: Dictionary
) -> Dictionary:
	if not _restore_runtime_snapshot_strict(runtime_before):
		_force_runtime_safe_reset(&"hold_release_rollback_failed")
		return WeaponActionContractScript.failure(
			WeaponActionContractScript.CODE_COMMIT_FAILED,
			{"reason": "rollback_failed"}
		)
	cancel(&"hold_release_failed")
	return failure_result


func _advance_phase(consume_buffered: bool) -> void:
	var phases: Array = _plan.get("phases", [])
	if _phase_index + 1 < phases.size():
		_phase_index += 1
		_phase_frame = 0
		_phase = StringName(str(_current_phase_data().get("phase", "")))
		_enter_current_phase()
		return

	var finished_token := _token
	_runtime.call("finish_action", finished_token)
	_clear_action_state()
	if consume_buffered:
		_consume_buffered_submission()


func _enter_current_phase() -> void:
	if _runtime == null or _token <= 0 or _phase == PHASE_READY:
		return
	var events_value: Variant = _runtime.call(
		"on_phase_enter",
		_plan.duplicate(true),
		_phase,
		_token
	)
	if not events_value is Array:
		cancel(&"phase_event_result_type")
		return
	for event_value: Variant in events_value as Array:
		if not event_value is Dictionary:
			cancel(&"phase_event_type")
			return
		var event := (event_value as Dictionary).duplicate(true)
		if str(event.get("type", "")) == "phase_failed":
			cancel(StringName(str(event.get("reason", "phase_failed"))))
			return
		_publish_weapon_runtime_event(event)


func _emit_action_frame_events() -> bool:
	if _runtime == null or _token <= 0 or _phase == PHASE_READY:
		return true
	var events_value: Variant = _runtime.call(
		"on_action_frame",
		_plan.duplicate(true),
		_phase,
		_token,
		_phase_frame
	)
	if not events_value is Array:
		cancel(&"action_frame_event_result_type")
		return false
	for event_value: Variant in events_value as Array:
		if not event_value is Dictionary:
			cancel(&"action_frame_event_type")
			return false
		var event := (event_value as Dictionary).duplicate(true)
		if str(event.get("type", "")) == "phase_failed":
			cancel(StringName(str(event.get("reason", "action_frame_failed"))))
			return false
		_publish_weapon_runtime_event(event)
	return true


func _consume_buffered_submission() -> void:
	if _buffered_submission.is_empty():
		return
	if int(_buffered_submission.get("expires_at_frame", -1)) <= _frame:
		_buffered_submission.clear()
		return
	var submission := _buffered_submission.duplicate(true)
	var result := _commit_intent(
		submission.get("intent", {}),
		submission.get("context", {}),
		_phase != PHASE_READY
	)
	if bool(result.get("ok", false)) or result.get("code") != WeaponActionContractScript.CODE_BUFFERED:
		_buffered_submission.clear()


func _prune_expired_buffer() -> void:
	if (
		not _buffered_submission.is_empty()
		and int(_buffered_submission.get("expires_at_frame", -1)) <= _frame
	):
		_buffered_submission.clear()


func _recovery_cancel_is_open() -> bool:
	if _phase not in [&"RECOVERY", &"RESOURCE_ACTION"]:
		return false
	var phase_data := _current_phase_data()
	if not phase_data.has("cancel_from_frame"):
		return false
	return _phase_frame >= int(phase_data["cancel_from_frame"])


func _current_phase_data() -> Dictionary:
	var phases_value: Variant = _plan.get("phases", [])
	if not phases_value is Array:
		return {}
	var phases := phases_value as Array
	if _phase_index < 0 or _phase_index >= phases.size():
		return {}
	var phase_value: Variant = phases[_phase_index]
	return (phase_value as Dictionary).duplicate(true) if phase_value is Dictionary else {}


func _hold_progress(phase_data: Dictionary) -> Dictionary:
	var maximum_hold_frames := int(phase_data.get("duration_frames", 0))
	var charge_complete_frames := int(phase_data.get(
		"charge_complete_frames",
		maximum_hold_frames
	))
	var progress_multiplier := float(phase_data.get("hold_progress_multiplier", 1.0))
	var effective_hold_frames := minf(
		float(_phase_frame) * progress_multiplier,
		float(charge_complete_frames)
	)
	var charge_ratio := (
		clampf(effective_hold_frames / float(charge_complete_frames), 0.0, 1.0)
		if charge_complete_frames > 0
		else 0.0
	)
	var movement_end := float(phase_data.get("movement_multiplier", 1.0))
	var movement_start := float(phase_data.get("movement_start_multiplier", movement_end))
	return {
		"hold_frames": _phase_frame,
		"effective_hold_frames": effective_hold_frames,
		"minimum_hold_frames": int(phase_data.get("minimum_hold_frames", 0)),
		"charge_complete_frames": charge_complete_frames,
		"maximum_hold_frames": maximum_hold_frames,
		"charge_ratio": charge_ratio,
		"movement_multiplier": lerpf(movement_start, movement_end, charge_ratio),
	}


func _clear_action_state() -> void:
	_phase = PHASE_READY
	_phase_index = -1
	_phase_frame = 0
	_token = 0
	_plan.clear()
	_action_context.clear()
	_hold_intent_id = &""
	_hold_runtime_snapshot.clear()
	_hold_live_context.clear()


func _gameplay_rewind_payload_guard() -> Dictionary:
	if _runtime == null:
		return {}
	var value: Variant = _runtime.call("gameplay_rewind_committed_payload_guard")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func committed_payload_guard() -> Dictionary:
	return _gameplay_rewind_payload_guard()


func _validate_gameplay_rewind_snapshot(value: Dictionary) -> bool:
	return (
		int(value.get("gameplay_rewind_schema_version", -1))
			== GAMEPLAY_REWIND_SNAPSHOT_SCHEMA_VERSION
		and value.get("gameplay_runtime") is Dictionary
		and value.get("committed_payload_guard") is Dictionary
		and _validate_runtime_snapshot(value)
	)


func _restore_gameplay_runtime_after_failed_cancel(before: Dictionary) -> bool:
	if _runtime == null or not before.get("gameplay_runtime") is Dictionary:
		return false
	var restored_value: Variant = _runtime.call(
		"restore_gameplay_rewind_snapshot_for_rollback",
		(before["gameplay_runtime"] as Dictionary).duplicate(true)
	)
	return (
		typeof(restored_value) == TYPE_BOOL
		and bool(restored_value)
		and gameplay_rewind_snapshot() == before
	)


func _validate_safe_snapshot(safe_snapshot: Dictionary) -> bool:
	if int(safe_snapshot.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return false
	if str(safe_snapshot.get("weapon_id", "")) != str(_weapon_id):
		return false
	if str(safe_snapshot.get("phase", "")) != str(PHASE_READY):
		return false
	if int(safe_snapshot.get("token", -1)) != 0:
		return false
	if int(safe_snapshot.get("frame", -1)) < 0:
		return false
	if int(safe_snapshot.get("generation", -1)) <= 0:
		return false
	if int(safe_snapshot.get("next_token", -1)) <= 0:
		return false
	if not safe_snapshot.get("plan", {}) is Dictionary or not (safe_snapshot.get("plan", {}) as Dictionary).is_empty():
		return false
	if not safe_snapshot.get("buffered_submission", {}) is Dictionary or not (safe_snapshot.get("buffered_submission", {}) as Dictionary).is_empty():
		return false
	if not str(safe_snapshot.get("hold_intent_id", "")).is_empty():
		return false
	if (
		not safe_snapshot.get("hold_runtime_snapshot", {}) is Dictionary
		or not (safe_snapshot.get("hold_runtime_snapshot", {}) as Dictionary).is_empty()
	):
		return false
	if (
		not safe_snapshot.get("hold_live_context", {}) is Dictionary
		or not (safe_snapshot.get("hold_live_context", {}) as Dictionary).is_empty()
	):
		return false
	return safe_snapshot.get("runtime") is Dictionary


func _validate_runtime_snapshot(value: Dictionary) -> bool:
	if (
		int(value.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION
		or str(value.get("weapon_id", "")) != str(_weapon_id)
		or typeof(value.get("frame")) != TYPE_INT
		or int(value.get("frame", -1)) < 0
		or typeof(value.get("generation")) != TYPE_INT
		or int(value.get("generation", 0)) <= 0
		or typeof(value.get("next_token")) != TYPE_INT
		or int(value.get("next_token", 0)) <= 0
		or typeof(value.get("token")) != TYPE_INT
		or int(value.get("token", -1)) < 0
		or typeof(value.get("phase")) != TYPE_STRING
		or typeof(value.get("phase_index")) != TYPE_INT
		or typeof(value.get("phase_frame")) != TYPE_INT
		or int(value.get("phase_frame", -1)) < 0
		or not value.get("plan") is Dictionary
		or not value.get("action_context") is Dictionary
		or not value.get("buffered_submission") is Dictionary
		or typeof(value.get("hold_intent_id")) != TYPE_STRING
		or not value.get("hold_runtime_snapshot") is Dictionary
		or not value.get("hold_live_context") is Dictionary
		or not value.get("runtime") is Dictionary
		or not value.get("resource_transaction") is Dictionary
	):
		return false
	var token := int(value["token"])
	var next_token := int(value["next_token"])
	if token > 0 and next_token <= token:
		return false
	var resource_snapshot := value["resource_transaction"] as Dictionary
	if (
		str(resource_snapshot.get("weapon_id", "")) != str(_weapon_id)
		or not resource_snapshot.get("committed_tokens") is Dictionary
	):
		return false
	if not _valid_buffered_submission(value["buffered_submission"], int(value["frame"])):
		return false
	var runtime_snapshot := value["runtime"] as Dictionary
	if runtime_snapshot.has("active_token") and int(runtime_snapshot.get("active_token", -1)) != token:
		return false
	if runtime_snapshot.has("active_phase") and str(runtime_snapshot.get("active_phase", "")) != str(value["phase"]):
		return false
	if (
		_runtime.has_method("validate_coordinator_snapshot")
		and not bool(_runtime.call(
			"validate_coordinator_snapshot",
			value.duplicate(true)
		))
	):
		return false

	var phase := StringName(str(value["phase"]))
	var plan := value["plan"] as Dictionary
	if phase == PHASE_READY:
		return (
			token == 0
			and int(value["phase_index"]) == -1
			and int(value["phase_frame"]) == 0
			and plan.is_empty()
			and (value["action_context"] as Dictionary).is_empty()
			and str(value["hold_intent_id"]).is_empty()
			and (value["hold_runtime_snapshot"] as Dictionary).is_empty()
			and (value["hold_live_context"] as Dictionary).is_empty()
		)
	if token <= 0:
		return false
	var plan_validation: Dictionary = WeaponActionContractScript.validate_plan(plan, _weapon_id)
	if not bool(plan_validation.get("ok", false)):
		return false
	var phases_value: Variant = plan.get("phases")
	if not phases_value is Array:
		return false
	var phase_index := int(value["phase_index"])
	var phases := phases_value as Array
	if phase_index < 0 or phase_index >= phases.size() or not phases[phase_index] is Dictionary:
		return false
	var phase_data := phases[phase_index] as Dictionary
	if (
		str(phase_data.get("phase", "")) != str(phase)
		or int(value["phase_frame"]) >= int(phase_data.get("duration_frames", 0))
	):
		return false
	var committed_tokens := resource_snapshot["committed_tokens"] as Dictionary
	if phase == &"HOLD":
		return (
			not str(value["hold_intent_id"]).is_empty()
			and not (value["hold_runtime_snapshot"] as Dictionary).is_empty()
			and not committed_tokens.has(token)
		)
	return (
		str(value["hold_intent_id"]).is_empty()
		and (value["hold_runtime_snapshot"] as Dictionary).is_empty()
		and (value["hold_live_context"] as Dictionary).is_empty()
		and committed_tokens.has(token)
	)


func _snapshot_token_transition_is_monotonic(value: Dictionary) -> bool:
	var target_frame := int(value["frame"])
	var target_generation := int(value["generation"])
	var target_next_token := int(value["next_token"])
	var target_token := int(value["token"])
	if (
		target_frame < _frame
		or target_generation < _generation
		or target_next_token < _next_token
	):
		return false
	if target_token <= 0:
		return true
	if _token > 0:
		if target_token < _token:
			return false
		if target_token == _token and target_generation != _generation:
			return false
		return true
	return target_token >= _next_token


func _valid_buffered_submission(value: Dictionary, snapshot_frame: int) -> bool:
	if value.is_empty():
		return true
	return (
		value.get("intent") is Dictionary
		and value.get("context") is Dictionary
		and typeof(value.get("expires_at_frame")) == TYPE_INT
		and int(value.get("expires_at_frame", -1)) > snapshot_frame
	)


func _install_snapshot_state(value: Dictionary) -> void:
	_frame = int(value["frame"])
	_generation = int(value["generation"])
	_next_token = int(value["next_token"])
	_token = int(value["token"])
	_phase = StringName(str(value["phase"]))
	_phase_index = int(value["phase_index"])
	_phase_frame = int(value["phase_frame"])
	_plan = (value["plan"] as Dictionary).duplicate(true)
	_action_context = (value["action_context"] as Dictionary).duplicate(true)
	_buffered_submission = (value["buffered_submission"] as Dictionary).duplicate(true)
	_hold_intent_id = StringName(str(value["hold_intent_id"]))
	_hold_runtime_snapshot = (value["hold_runtime_snapshot"] as Dictionary).duplicate(true)
	_hold_live_context = (value["hold_live_context"] as Dictionary).duplicate(true)


func _runtime_failure(runtime_result: Dictionary, fallback_code: StringName) -> Dictionary:
	var code_value: Variant = runtime_result.get("code", fallback_code)
	var code := StringName(str(code_value)) if not str(code_value).is_empty() else fallback_code
	var context_value: Variant = runtime_result.get("context", {})
	var context := (context_value as Dictionary).duplicate(true) if context_value is Dictionary else {}
	return WeaponActionContractScript.failure(code, context)


func _resource_failure(resource_result: Dictionary) -> Dictionary:
	var code := StringName(str(resource_result.get(
		"code",
		WeaponActionContractScript.CODE_COMMIT_FAILED
	)))
	var context_value: Variant = resource_result.get("context", {})
	var context := (
		(context_value as Dictionary).duplicate(true)
		if context_value is Dictionary
		else {}
	)
	return WeaponActionContractScript.failure(code, context)


func _plan_starts_with_hold(plan: Dictionary) -> bool:
	var phases_value: Variant = plan.get("phases", [])
	return (
		phases_value is Array
		and not (phases_value as Array).is_empty()
		and (phases_value as Array)[0] is Dictionary
		and StringName(str(((phases_value as Array)[0] as Dictionary).get("phase", ""))) == &"HOLD"
	)


func _submit_live_intent(intent: Dictionary, context: Dictionary) -> Dictionary:
	if _runtime == null or not _runtime.has_method("handle_live_intent"):
		return {"handled": false}
	var runtime_before_value: Variant = _runtime.call("snapshot")
	if not runtime_before_value is Dictionary:
		return {
			"handled": true,
			"result": WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_COMMIT_FAILED,
				{"reason": "live_intent_snapshot_type"}
			),
		}
	var runtime_before := (runtime_before_value as Dictionary).duplicate(true)
	var live_value: Variant = _runtime.call(
		"handle_live_intent",
		_plan.duplicate(true),
		_token,
		_phase,
		_phase_frame,
		intent.duplicate(true),
		context.duplicate(true)
	)
	if not live_value is Dictionary:
		return _live_intent_failure(
			runtime_before,
			WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_COMMIT_FAILED,
				{"reason": "live_intent_result_type"}
			)
		)
	var live_result := live_value as Dictionary
	if not bool(live_result.get("handled", false)):
		return {"handled": false}
	if not bool(live_result.get("ok", false)):
		return _live_intent_failure(
			runtime_before,
			_runtime_failure(live_result, WeaponActionContractScript.CODE_RUNTIME_REJECTED)
		)

	var replacement_value: Variant = live_result.get("replacement_phases", [])
	if not replacement_value is Array:
		return _live_intent_failure(
			runtime_before,
			WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_INVALID_PLAN,
				{"field": "replacement_phases", "reason": "type"}
			)
		)
	var replacement_phases := replacement_value as Array
	if not replacement_phases.is_empty():
		var current_phases_value: Variant = _plan.get("phases", [])
		if not current_phases_value is Array:
			return _live_intent_failure(
				runtime_before,
				WeaponActionContractScript.failure(
					WeaponActionContractScript.CODE_INVALID_PLAN,
					{"field": "phases", "reason": "type"}
				)
			)
		var next_phases: Array = []
		for phase_index: int in range(_phase_index):
			var prefix_phase: Variant = (current_phases_value as Array)[phase_index]
			next_phases.append(
				(prefix_phase as Dictionary).duplicate(true)
				if prefix_phase is Dictionary
				else prefix_phase
			)
		for replacement_phase: Variant in replacement_phases:
			next_phases.append(
				(replacement_phase as Dictionary).duplicate(true)
				if replacement_phase is Dictionary
				else replacement_phase
			)
		var finalized_plan := _plan.duplicate(true)
		finalized_plan["phases"] = next_phases
		var plan_validation: Dictionary = WeaponActionContractScript.validate_plan(
			finalized_plan,
			_weapon_id
		)
		if not bool(plan_validation.get("ok", false)):
			return _live_intent_failure(runtime_before, plan_validation)
		var active_token := _token
		var active_generation := _generation
		_plan = finalized_plan
		_phase_index = next_phases.size() - replacement_phases.size()
		_phase_frame = 0
		_phase = StringName(str(_current_phase_data().get("phase", "")))
		_enter_current_phase()
		if _token != active_token or _generation != active_generation or _phase == PHASE_READY:
			return {
				"handled": true,
				"result": WeaponActionContractScript.failure(
					WeaponActionContractScript.CODE_COMMIT_FAILED,
					{"reason": "live_intent_phase_entry_failed"}
				),
			}

	var context_value: Variant = live_result.get("context", {})
	var result_context := (
		(context_value as Dictionary).duplicate(true)
		if context_value is Dictionary
		else {}
	)
	return {
		"handled": true,
		"result": {
			"ok": true,
			"code": WeaponActionContractScript.CODE_OK,
			"token": _token,
			"generation": _generation,
			"context": result_context,
		},
	}


func _live_intent_failure(runtime_before: Dictionary, failure_result: Dictionary) -> Dictionary:
	if not _restore_runtime_snapshot_strict(runtime_before):
		_force_runtime_safe_reset(&"live_intent_rollback_failed")
		return {
			"handled": true,
			"result": WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_COMMIT_FAILED,
				{"reason": "rollback_failed"}
			),
		}
	return {"handled": true, "result": failure_result.duplicate(true)}


func _advance_runtime_tick() -> bool:
	if _runtime == null or not _runtime.has_method("advance_runtime_frame"):
		return true
	var events_value: Variant = _runtime.call("advance_runtime_frame", _frame)
	if not events_value is Array:
		_force_runtime_safe_reset(&"runtime_tick_result_type")
		return false
	for event_value: Variant in events_value as Array:
		if not event_value is Dictionary:
			_force_runtime_safe_reset(&"runtime_tick_event_type")
			return false
		var event := (event_value as Dictionary).duplicate(true)
		if str(event.get("type", "")) in ["phase_failed", "runtime_failed"]:
			_force_runtime_safe_reset(StringName(str(event.get("reason", "runtime_tick_failed"))))
			return false
		_publish_weapon_runtime_event(event)
	return true


func _publish_weapon_runtime_event(event: Dictionary) -> void:
	if _frame_event_buffer_active:
		_frame_event_buffer.append({
			"type": &"runtime_event",
			"event": event.duplicate(true),
		})
		return
	if not _finalized_frame_event_publication.is_empty() or _frame_event_publication_in_progress:
		_post_publication_frame_events.append({
			"type": &"runtime_event",
			"event": event.duplicate(true),
		})
		return
	weapon_runtime_event.emit(event.duplicate(true))


func _publish_weapon_action_committed(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	context: Dictionary
) -> void:
	if _frame_event_buffer_active:
		_frame_event_buffer.append({
			"type": &"action_committed",
			"weapon_id": weapon_id,
			"action_id": action_id,
			"token": token,
			"context": context.duplicate(true),
		})
		return
	if not _finalized_frame_event_publication.is_empty() or _frame_event_publication_in_progress:
		_post_publication_frame_events.append({
			"type": &"action_committed",
			"weapon_id": weapon_id,
			"action_id": action_id,
			"token": token,
			"context": context.duplicate(true),
		})
		return
	weapon_action_committed.emit(
		weapon_id,
		action_id,
		token,
		context.duplicate(true)
	)


func _plan_busy_submission(intent: Dictionary, context: Dictionary) -> Dictionary:
	var planned_value: Variant = _runtime.call(
		"plan_intent",
		intent.duplicate(true),
		context.duplicate(true)
	)
	if not planned_value is Dictionary:
		return {
			"ok": false,
			"failure": WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_RUNTIME_REJECTED,
				{"reason": "plan_result_type"}
			),
		}
	var planned := planned_value as Dictionary
	if not bool(planned.get("ok", false)):
		return {
			"ok": false,
			"failure": _runtime_failure(
				planned,
				WeaponActionContractScript.CODE_RUNTIME_REJECTED
			),
		}
	var plan_value: Variant = (planned_value as Dictionary).get("plan")
	if not plan_value is Dictionary:
		return {
			"ok": false,
			"failure": WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_INVALID_PLAN,
				{"field": "plan", "reason": "type"}
			),
		}
	var planned_action := (plan_value as Dictionary).duplicate(true)
	var validation: Dictionary = WeaponActionContractScript.validate_plan(planned_action, _weapon_id)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "failure": validation}
	var phases_value: Variant = (plan_value as Dictionary).get("phases", [])
	var first_phase_value: Variant = (phases_value as Array)[0]
	var first_phase := StringName(str((first_phase_value as Dictionary).get("phase", "")))
	return {
		"ok": true,
		"live_input_phase": str(first_phase) if first_phase in [&"HOLD", &"CHANNEL"] else "",
	}


func _validate_submission_context(context: Dictionary) -> Dictionary:
	for reserved_field: String in [
		"context_schema_version",
		"action_token",
		"action_generation",
		"coordinator_frame",
		"weapon_id",
		"action_id",
		"profile_id",
		"profile_version",
		"resource_transaction",
	]:
		if context.has(reserved_field):
			return WeaponActionContractScript.failure(
				WeaponActionContractScript.CODE_INVALID_INTENT,
				{"field": reserved_field, "reason": "reserved_context"}
			)
	return WeaponActionContractScript.success()


func _committed_context(
	base_context: Dictionary,
	plan: Dictionary,
	token: int,
	generation_value: int,
	extra_context: Dictionary,
	resource_context: Dictionary
) -> Dictionary:
	var context := base_context.duplicate(true)
	for key: Variant in extra_context.keys():
		context[key] = extra_context[key]
	context["context_schema_version"] = 1
	context["action_token"] = token
	context["action_generation"] = generation_value
	context["coordinator_frame"] = _frame
	context["weapon_id"] = str(_weapon_id)
	context["action_id"] = str(plan.get("action_id", ""))
	context["profile_id"] = str(plan.get("profile_id", ""))
	context["profile_version"] = int(plan.get("profile_version", 0))
	context["resource_transaction"] = resource_context.duplicate(true)
	return context


func _restore_runtime_snapshot_strict(target: Dictionary) -> bool:
	if _runtime == null or not bool(_runtime.call("restore_snapshot", target.duplicate(true))):
		return false
	return _runtime_snapshot_matches(target)


func _runtime_snapshot_matches(target: Dictionary) -> bool:
	if _runtime == null:
		return false
	var current_value: Variant = _runtime.call("snapshot")
	return current_value is Dictionary and current_value == target


func _restore_resource_snapshot_strict(target: Dictionary) -> bool:
	if (
		_resource_transaction == null
		or not bool(_resource_transaction.call("restore_snapshot", target.duplicate(true)))
	):
		return false
	return _resource_snapshot_matches(target)


func _resource_snapshot_matches(target: Dictionary) -> bool:
	if _resource_transaction == null:
		return false
	var current_value: Variant = _resource_transaction.call("snapshot")
	return current_value is Dictionary and current_value == target


func _force_restore_fail_closed(
	reason: StringName,
	before: Dictionary,
	target: Dictionary
) -> void:
	if _runtime != null:
		_runtime.call("reset_runtime_state", reason)
	if _resource_transaction != null:
		if _resource_transaction.has_method("fail_closed"):
			_resource_transaction.call("fail_closed", reason)
		else:
			_resource_transaction.call("reset_runtime_state")
	_frame = maxi(_frame, maxi(int(before.get("frame", 0)), int(target.get("frame", 0))))
	_next_token = maxi(
		_next_token,
		maxi(int(before.get("next_token", 1)), int(target.get("next_token", 1)))
	)
	_generation = maxi(
		_generation,
		maxi(int(before.get("generation", 1)), int(target.get("generation", 1)))
	) + 1
	_buffered_submission.clear()
	_clear_action_state()


func _force_runtime_safe_reset(reason: StringName) -> void:
	if _runtime != null:
		_runtime.call("reset_runtime_state", reason)
	_generation += 1
	_buffered_submission.clear()
	_clear_action_state()


func _runtime_has_contract(runtime: RefCounted) -> bool:
	for method_name: StringName in [
		&"weapon_id",
		&"configure",
		&"capabilities",
		&"plan_intent",
		&"commit_action",
		&"on_phase_enter",
		&"on_action_frame",
		&"release_hold",
		&"cancel_action",
		&"cancel_for_gameplay_rewind",
		&"gameplay_rewind_snapshot",
		&"restore_gameplay_rewind_snapshot_for_rollback",
		&"gameplay_rewind_committed_payload_guard",
		&"finish_action",
		&"apply_modifier",
		&"reset_runtime_state",
		&"snapshot",
		&"restore_snapshot",
		&"presentation_snapshot",
	]:
		if not runtime.has_method(method_name):
			return false
	return true


func _resource_transaction_has_contract(transaction: RefCounted) -> bool:
	if transaction == null:
		return false
	for method_name: StringName in [
		&"prepare",
		&"commit",
		&"advance_frame",
		&"cooldown_remaining",
		&"snapshot",
		&"restore_snapshot",
		&"fail_closed",
		&"rewind_safe_reset",
		&"reset_runtime_state",
	]:
		if not transaction.has_method(method_name):
			return false
	return true
