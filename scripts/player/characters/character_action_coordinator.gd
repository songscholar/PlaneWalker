class_name CharacterActionCoordinator
extends RefCounted

const CharacterActionContractScript := preload(
	"res://scripts/player/characters/character_action_contract.gd"
)
const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")

var _runtime: RefCounted
var _publication_bus: Node = EventBus
var _last_runtime_frame: int = -1
var _revision: int = 0
var _prepared_frame: int = -1
var _prepared_runtime_before: Dictionary = {}
var _prepared_runtime_after: Dictionary = {}
var _prepared_result: Dictionary = {}
var _generation: int = 1
var _next_token: int = 1
var _current_token: int = 0
var _committed_plan: Dictionary = {}
var _action_revision: int = 0
var _mastery_claims: Dictionary = {}
var _next_mastery_ticket_id: int = 1
var _prepared_mastery_ticket: Dictionary = {}
var _prepared_mastery_runtime_before: Dictionary = {}
var _prepared_mastery_runtime_after: Dictionary = {}

const ACTION_SNAPSHOT_SCHEMA_VERSION := 2
const ACTION_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"generation",
	"next_token",
	"current_token",
	"committed_plan",
	"mastery_claims",
	"revision",
]
const MASTERY_FACT_FIELDS: Array[String] = [
	"weapon_id",
	"mastery_family",
	"mastery_id",
	"action_id",
	"generation",
	"action_token",
	"target_id",
	"context",
]
const MASTERY_TICKET_SCHEMA_VERSION := 1
const MASTERY_IDS_BY_FAMILY := {
	"sword": [
		&"sword_perfect_guard",
		&"sword_counter_confirmed",
		&"sword_charged_commitment",
	],
	"bow": [
		&"bow_full_charge_weakpoint",
		&"bow_full_charge_penetration",
	],
	"gun": [
		&"gun_perfect_reload",
		&"gun_magazine_finisher",
	],
	"staff": [
		&"staff_ordered_combination",
		&"staff_controlled_zone",
	],
	"gauntlets": [
		&"gauntlets_dodge_counter",
		&"gauntlets_combo_threshold",
		&"gauntlets_chain_finisher",
	],
}


func configure(runtime: Variant, publication_bus: Node = null) -> bool:
	if _prepared_frame >= 0 or _mastery_prepare_active():
		return false
	var validation: Dictionary = CharacterActionContractScript.validate_runtime(runtime)
	if not bool(validation.get("ok", false)):
		return false
	if _runtime == runtime:
		return true
	if _runtime != null:
		return false
	_runtime = runtime as RefCounted
	_publication_bus = publication_bus if publication_bus != null else EventBus
	_revision += 1
	return true


func set_generation_floor(generation_floor: int) -> bool:
	if (
		generation_floor <= 0
		or _prepared_frame >= 0
		or _mastery_prepare_active()
		or _current_token != 0
	):
		return false
	if generation_floor > _generation:
		_generation = generation_floor
		_action_revision += 1
	return true


func set_next_token_floor(next_token_floor: int) -> bool:
	if (
		next_token_floor <= 0
		or _prepared_frame >= 0
		or _mastery_prepare_active()
		or _current_token != 0
	):
		return false
	if next_token_floor > _next_token:
		_next_token = next_token_floor
		_action_revision += 1
	return true


func generation() -> int:
	return _generation


func current_token() -> int:
	return _current_token


func next_token() -> int:
	return _next_token


func owns_action(generation_value: int, token: int) -> bool:
	return (
		generation_value == _generation
		and token > 0
		and token == _current_token
		and not _committed_plan.is_empty()
	)


func has_uncommitted_action() -> bool:
	var state := _character_action_cancellation_state()
	return (
		not state.is_empty()
		and bool(state.get("active", false))
		and not bool(state.get("committed", false))
	)


func cancel_uncommitted_action(reason: Variant) -> bool:
	if _prepared_frame >= 0 or _mastery_prepare_active():
		return false
	var validation: Dictionary = CharacterActionContractScript.validate_reset_reason(reason)
	if not bool(validation.get("ok", false)):
		return false
	var state := _character_action_cancellation_state()
	if state.is_empty():
		return false
	if not bool(state["active"]) or bool(state["committed"]):
		return true
	if _runtime == null or not _runtime.has_method("cancel_uncommitted_action"):
		return false
	var runtime_before := _runtime_snapshot()
	if runtime_before.is_empty():
		return false
	var normalized_reason := StringName(str(
		(validation.get("context", {}) as Dictionary).get("reason", &"")
	))
	var cancelled_value: Variant = _runtime.call(
		"cancel_uncommitted_action",
		normalized_reason
	)
	if (
		not cancelled_value is Dictionary
		or typeof((cancelled_value as Dictionary).get("ok")) != TYPE_BOOL
		or not bool((cancelled_value as Dictionary).get("ok", false))
		or typeof((cancelled_value as Dictionary).get("cancelled")) != TYPE_BOOL
		or not bool((cancelled_value as Dictionary).get("cancelled", false))
	):
		_restore_runtime_exact(runtime_before)
		return false
	var after := _character_action_cancellation_state()
	if after.is_empty() or bool(after["active"]):
		_restore_runtime_exact(runtime_before)
		return false
	_current_token = 0
	_committed_plan.clear()
	_action_revision += 1
	return true


func action_snapshot() -> Dictionary:
	return {
		"schema_version": ACTION_SNAPSHOT_SCHEMA_VERSION,
		"generation": _generation,
		"next_token": _next_token,
		"current_token": _current_token,
		"committed_plan": _committed_plan.duplicate(true),
		"mastery_claims": _mastery_claims_snapshot(),
		"revision": _action_revision,
	}


func restore_action_snapshot(value: Dictionary) -> bool:
	if not can_restore_action_snapshot(value):
		return false
	_generation = int(value["generation"])
	_next_token = int(value["next_token"])
	_current_token = int(value["current_token"])
	_committed_plan = (value["committed_plan"] as Dictionary).duplicate(true)
	_mastery_claims = _mastery_claim_map(value["mastery_claims"] as Array)
	_action_revision = int(value["revision"])
	return action_snapshot() == value


func can_restore_action_snapshot(value: Dictionary) -> bool:
	return not _mastery_prepare_active() and _valid_action_snapshot(value)


func try_character_skill(intent: Variant, context: Variant) -> Dictionary:
	if _mastery_prepare_active():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "prepared_mastery_active"}
		)
	if not intent is Dictionary or not context is Dictionary:
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_INVALID_CONTEXT,
			{"reason": "type"}
		)
	if _runtime == null:
		return CharacterActionContractScript.failure(CharacterActionContractScript.CODE_NO_RUNTIME)
	var runtime_before := _runtime_snapshot()
	if runtime_before.is_empty():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "snapshot_type"}
		)
	var planned_value: Variant = _runtime.call(
		"plan_character_skill",
		(intent as Dictionary).duplicate(true),
		(context as Dictionary).duplicate(true)
	)
	if (
		not planned_value is Dictionary
		or typeof((planned_value as Dictionary).get("ok")) != TYPE_BOOL
		or not bool((planned_value as Dictionary).get("ok", false))
		or not (planned_value as Dictionary).get("plan") is Dictionary
	):
		return _rollback_runtime_rejection(runtime_before, "plan_rejected")
	var committed_plan := (
		((planned_value as Dictionary)["plan"] as Dictionary).duplicate(true)
	)
	var committed_token := _next_token
	var commit_value: Variant = _runtime.call(
		"commit_character_skill",
		committed_plan.duplicate(true),
		committed_token
	)
	if (
		not commit_value is Dictionary
		or typeof((commit_value as Dictionary).get("ok")) != TYPE_BOOL
		or not bool((commit_value as Dictionary).get("ok", false))
	):
		return _rollback_runtime_rejection(runtime_before, "commit_rejected")
	var runtime_context_value: Variant = (commit_value as Dictionary).get("context", {})
	if not runtime_context_value is Dictionary:
		return _rollback_runtime_rejection(runtime_before, "commit_context_type")
	var events_value: Variant = (commit_value as Dictionary).get("events", [])
	var events_validation := CharacterActionContractScript.validate_runtime_events(events_value)
	if not bool(events_validation.get("ok", false)):
		return _rollback_runtime_rejection(runtime_before, "commit_events_type")

	_current_token = committed_token
	_next_token += 1
	_committed_plan = committed_plan.duplicate(true)
	_action_revision += 1
	var result_context := (runtime_context_value as Dictionary).duplicate(true)
	result_context["token"] = committed_token
	result_context["generation"] = _generation
	result_context["plan"] = committed_plan.duplicate(true)
	return CharacterActionContractScript.success(
		CharacterActionContractScript.CODE_OK,
		events_validation.get("events", []) as Array,
		result_context
	)


func before_damage(context: Dictionary) -> Dictionary:
	return _call_decision_hook(&"before_damage", context)


func after_damage(context: Dictionary) -> Dictionary:
	return _call_event_hook(&"after_damage", context)


func on_weapon_action_committed(context: Dictionary) -> Dictionary:
	return _call_event_hook(&"on_weapon_action_committed", context)


func on_weapon_mastery_confirmed(context: Dictionary) -> Dictionary:
	return _call_event_hook(&"on_weapon_mastery_confirmed", context)


func prepare_weapon_mastery(fact: Variant) -> Dictionary:
	if not _prepared_mastery_ticket.is_empty():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "prepared_mastery_active"}
		)
	if _prepared_frame >= 0:
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "prepared_frame_active"}
		)
	var normalized := _normalized_mastery_fact(fact)
	if normalized.is_empty():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_INVALID_CONTEXT,
			{"reason": "mastery_fact"}
		)
	var claim_key := _mastery_claim_key(
		int(normalized["generation"]),
		int(normalized["action_token"]),
		StringName(normalized["mastery_family"])
	)
	if _mastery_claims.has(claim_key):
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "mastery_claimed"}
		)
	if _runtime == null:
		return CharacterActionContractScript.failure(CharacterActionContractScript.CODE_NO_RUNTIME)
	var runtime_before := _runtime_snapshot()
	if runtime_before.is_empty():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "snapshot_type"}
		)
	var events_value: Variant = _runtime.call(
		"on_weapon_mastery_confirmed",
		normalized.duplicate(true)
	)
	var events_validation := CharacterActionContractScript.validate_runtime_events(events_value)
	if not bool(events_validation.get("ok", false)):
		return _rollback_runtime_rejection(runtime_before, "on_weapon_mastery_confirmed_result")
	var runtime_after := _runtime_snapshot()
	if runtime_after.is_empty():
		return _rollback_runtime_rejection(runtime_before, "mastery_staged_snapshot_type")
	var ticket := {
		"schema_version": MASTERY_TICKET_SCHEMA_VERSION,
		"ticket_id": _next_mastery_ticket_id,
		"coordinator_generation": _generation,
		"coordinator_revision": _revision,
		"action_revision": _action_revision,
		"claim_key": claim_key,
		"fact": normalized.duplicate(true),
	}
	_next_mastery_ticket_id += 1
	_prepared_mastery_ticket = ticket.duplicate(true)
	_prepared_mastery_runtime_before = runtime_before.duplicate(true)
	_prepared_mastery_runtime_after = runtime_after.duplicate(true)
	return CharacterActionContractScript.success(
		CharacterActionContractScript.CODE_OK,
		events_validation.get("events", []) as Array,
		{"ticket": ticket.duplicate(true)}
	)


func settle_prepared_weapon_mastery(ticket: Variant, observation_sink: Callable = Callable()) -> Dictionary:
	if not _mastery_ticket_matches(ticket):
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_INVALID_CONTEXT,
			{"reason": "mastery_ticket"}
		)
	var canonical_ticket := _prepared_mastery_ticket.duplicate(true)
	var claim_key := str(canonical_ticket["claim_key"])
	if (
		_generation != int(canonical_ticket["coordinator_generation"])
		or _revision != int(canonical_ticket["coordinator_revision"])
		or _action_revision != int(canonical_ticket["action_revision"])
	):
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "prepared_action_drift"}
		)
	if _mastery_claims.has(claim_key):
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "prepared_claim_drift"}
		)
	if not _runtime_snapshot_matches(_prepared_mastery_runtime_after):
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "prepared_runtime_drift"}
		)
	var normalized := (canonical_ticket["fact"] as Dictionary).duplicate(true)
	_mastery_claims[claim_key] = normalized.duplicate(true)
	_action_revision += 1
	_clear_prepared_mastery()
	if observation_sink.is_valid():
		observation_sink.call(normalized.duplicate(true))
	else:
		_publish_weapon_mastery(normalized)
	return CharacterActionContractScript.success(
		CharacterActionContractScript.CODE_OK,
		[],
		{"fact": normalized.duplicate(true)}
	)


func abort_prepared_weapon_mastery(ticket: Variant) -> Dictionary:
	if not _mastery_ticket_matches(ticket):
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_INVALID_CONTEXT,
			{"reason": "mastery_ticket"}
		)
	if not _restore_runtime_exact(_prepared_mastery_runtime_before):
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_ROLLBACK_FAILED,
			{"reason": "prepared_mastery_abort_rollback_failed"}
		)
	_clear_prepared_mastery()
	return CharacterActionContractScript.success()


func confirm_weapon_mastery(fact: Variant) -> bool:
	var prepared := prepare_weapon_mastery(fact)
	if not bool(prepared.get("ok", false)):
		return false
	var ticket_value: Variant = (prepared.get("context", {}) as Dictionary).get("ticket", {})
	if not ticket_value is Dictionary:
		return false
	var ticket := (ticket_value as Dictionary).duplicate(true)
	if not (prepared.get("events", []) as Array).is_empty():
		abort_prepared_weapon_mastery(ticket)
		return false
	var settled := settle_prepared_weapon_mastery(ticket)
	if bool(settled.get("ok", false)):
		return true
	abort_prepared_weapon_mastery(ticket)
	return false


func _publish_weapon_mastery(normalized: Dictionary) -> void:
	_publication_bus.weapon_mastery_confirmed.emit(
		StringName(normalized["weapon_id"]),
		StringName(normalized["mastery_family"]),
		StringName(normalized["mastery_id"]),
		StringName(normalized["action_id"]),
		int(normalized["action_token"]),
		int(normalized["generation"]),
		int(normalized["target_id"]),
		(normalized["context"] as Dictionary).duplicate(true)
	)


func before_time_skill(context: Dictionary) -> Dictionary:
	return _call_decision_hook(&"before_time_skill", context)


func after_time_skill(context: Dictionary) -> Dictionary:
	return _call_event_hook(&"after_time_skill", context)


func on_room_started(context: Dictionary) -> Dictionary:
	return _call_event_hook(&"on_room_started", context)


func on_room_cleared(context: Dictionary) -> Dictionary:
	return _call_event_hook(&"on_room_cleared", context)


func on_run_terminal(context: Dictionary) -> Dictionary:
	if _mastery_prepare_active():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "prepared_mastery_active"}
		)
	if _runtime == null:
		return CharacterActionContractScript.failure(CharacterActionContractScript.CODE_NO_RUNTIME)
	var runtime_before := _runtime_snapshot()
	if runtime_before.is_empty():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "snapshot_type"}
		)
	var value: Variant = _runtime.call("on_run_terminal", context.duplicate(true))
	if (
		not value is Dictionary
		or typeof((value as Dictionary).get("ok")) != TYPE_BOOL
		or not bool((value as Dictionary).get("ok", false))
		or not (value as Dictionary).get("summary", {}) is Dictionary
	):
		return _rollback_runtime_rejection(runtime_before, "terminal_result")
	return CharacterActionContractScript.success(
		CharacterActionContractScript.CODE_OK,
		[],
		{"summary": ((value as Dictionary).get("summary", {}) as Dictionary).duplicate(true)}
	)


func advance_frame(runtime_frame: Variant, context: Variant = {}) -> Dictionary:
	var prepared := prepare_frame_advance(runtime_frame, context)
	if not bool(prepared.get("ok", false)):
		return prepared
	return commit_prepared_frame()


func prepare_frame_advance(runtime_frame: Variant, context: Variant = {}) -> Dictionary:
	if _prepared_frame >= 0 or _mastery_prepare_active():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{
				"reason": (
					"prepared_mastery_active"
					if _mastery_prepare_active()
					else "prepared_frame_active"
				),
			}
		)
	var validation: Dictionary = CharacterActionContractScript.validate_advance(
		runtime_frame,
		_last_runtime_frame,
		context
	)
	if not bool(validation.get("ok", false)):
		return validation
	var accepted_frame := int(runtime_frame)
	if _runtime == null:
		_prepared_frame = accepted_frame
		_prepared_result = CharacterActionContractScript.success(
			CharacterActionContractScript.CODE_NO_RUNTIME,
			[],
			{"runtime_frame": accepted_frame}
		)
		return _prepared_result.duplicate(true)

	var runtime_before_value: Variant = _runtime.call("snapshot")
	if not runtime_before_value is Dictionary:
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "snapshot_type"}
		)
	var runtime_before := (runtime_before_value as Dictionary).duplicate(true)
	var runtime_context := (context as Dictionary).duplicate(true)
	runtime_context["runtime_frame"] = accepted_frame
	var events_value: Variant = _runtime.call("advance_frame", runtime_context)
	var events_validation: Dictionary = CharacterActionContractScript.validate_runtime_events(
		events_value
	)
	if not bool(events_validation.get("ok", false)):
		if not _restore_runtime_exact(runtime_before):
			return CharacterActionContractScript.failure(
				CharacterActionContractScript.CODE_ROLLBACK_FAILED,
				{"reason": "advance_rejection_rollback_failed"}
			)
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			(events_validation.get("context", {}) as Dictionary).duplicate(true)
		)
	var runtime_after_value: Variant = _runtime.call("snapshot")
	if not runtime_after_value is Dictionary:
		if not _restore_runtime_exact(runtime_before):
			return CharacterActionContractScript.failure(
				CharacterActionContractScript.CODE_ROLLBACK_FAILED,
				{"reason": "staged_snapshot_rollback_failed"}
			)
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "staged_snapshot_type"}
		)

	_prepared_frame = accepted_frame
	_prepared_runtime_before = runtime_before
	_prepared_runtime_after = (runtime_after_value as Dictionary).duplicate(true)
	_prepared_result = CharacterActionContractScript.success(
		CharacterActionContractScript.CODE_OK,
		events_validation.get("events", []) as Array,
		{"runtime_frame": accepted_frame}
	)
	return _prepared_result.duplicate(true)


func commit_prepared_frame() -> Dictionary:
	if _prepared_frame < 0 or _prepared_result.is_empty():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_INVALID_FRAME,
			{"reason": "no_prepared_frame"}
		)
	if _runtime != null and not _runtime_snapshot_matches(_prepared_runtime_after):
		if not _restore_runtime_exact(_prepared_runtime_before):
			return CharacterActionContractScript.failure(
				CharacterActionContractScript.CODE_ROLLBACK_FAILED,
				{"reason": "prepared_runtime_drift_rollback_failed"}
			)
		_clear_prepared_frame()
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "prepared_runtime_drift"}
		)
	var committed_result := _prepared_result.duplicate(true)
	_last_runtime_frame = _prepared_frame
	_revision += 1
	_clear_prepared_frame()
	return committed_result


func rollback_prepared_frame() -> bool:
	if _prepared_frame < 0:
		return true
	if _runtime != null and not _restore_runtime_exact(_prepared_runtime_before):
		return false
	_clear_prepared_frame()
	return true


func snapshot() -> Dictionary:
	var runtime_snapshot: Dictionary = {}
	if _runtime != null:
		var runtime_value: Variant = _runtime.call("snapshot")
		if runtime_value is Dictionary:
			runtime_snapshot = (runtime_value as Dictionary).duplicate(true)
	return {
		"schema_version": CharacterActionContractScript.SNAPSHOT_SCHEMA_VERSION,
		"last_runtime_frame": _last_runtime_frame,
		"revision": _revision,
		"runtime_configured": _runtime != null,
		"runtime": runtime_snapshot,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if _prepared_frame >= 0 or _mastery_prepare_active():
		return false
	var validated := _validated_snapshot(value)
	if validated.is_empty():
		return false
	if bool(validated["runtime_configured"]) != (_runtime != null):
		return false
	if int(validated["revision"]) > _revision:
		return false
	if int(validated["last_runtime_frame"]) > _last_runtime_frame:
		return false
	if _runtime == null:
		return true
	var accepted_value: Variant = _runtime.call(
		"can_restore_snapshot",
		(validated["runtime"] as Dictionary).duplicate(true)
	)
	return typeof(accepted_value) == TYPE_BOOL and bool(accepted_value)


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	var validated := _validated_snapshot(value)
	var before_frame := _last_runtime_frame
	var before_revision := _revision
	var runtime_before: Dictionary = {}
	if _runtime != null:
		var before_value: Variant = _runtime.call("snapshot")
		if not before_value is Dictionary:
			return false
		runtime_before = (before_value as Dictionary).duplicate(true)
		var restored_value: Variant = _runtime.call(
			"restore_snapshot",
			(validated["runtime"] as Dictionary).duplicate(true)
		)
		if typeof(restored_value) != TYPE_BOOL or not bool(restored_value):
			if not _restore_runtime_exact(runtime_before):
				push_error("CharacterActionCoordinator runtime restore rollback failed")
			return false
		if not _runtime_snapshot_matches(validated["runtime"] as Dictionary):
			_restore_runtime_exact(runtime_before)
			return false

	_last_runtime_frame = int(validated["last_runtime_frame"])
	_revision = int(validated["revision"])
	if snapshot() == validated:
		return true

	_last_runtime_frame = before_frame
	_revision = before_revision
	if _runtime != null:
		_restore_runtime_exact(runtime_before)
	return false


func restore_replay_snapshot(value: Dictionary) -> bool:
	if not can_restore_replay_snapshot(value):
		return false
	var validated := _validated_snapshot(value)
	var before := snapshot()
	if _runtime != null:
		var restored_value: Variant = _runtime.call(
			"restore_snapshot",
			(validated["runtime"] as Dictionary).duplicate(true)
		)
		if typeof(restored_value) != TYPE_BOOL or not bool(restored_value):
			return false
	_last_runtime_frame = int(validated["last_runtime_frame"])
	_revision = int(validated["revision"])
	if snapshot() == validated:
		return true
	_restore_replay_snapshot_unchecked(before)
	return false


func can_restore_replay_snapshot(value: Dictionary) -> bool:
	if _prepared_frame >= 0 or _mastery_prepare_active():
		return false
	var validated := _validated_snapshot(value)
	if validated.is_empty() or bool(validated["runtime_configured"]) != (_runtime != null):
		return false
	if _runtime == null:
		return true
	var accepted: Variant = _runtime.call(
		"can_restore_snapshot",
		(validated["runtime"] as Dictionary).duplicate(true)
	)
	return typeof(accepted) == TYPE_BOOL and bool(accepted)


func _restore_replay_snapshot_unchecked(value: Dictionary) -> bool:
	if _runtime != null:
		var restored_value: Variant = _runtime.call(
			"restore_snapshot",
			(value.get("runtime", {}) as Dictionary).duplicate(true)
		)
		if typeof(restored_value) != TYPE_BOOL or not bool(restored_value):
			return false
	_last_runtime_frame = int(value.get("last_runtime_frame", _last_runtime_frame))
	_revision = int(value.get("revision", _revision))
	return snapshot() == value


func reset_runtime_state(reason: Variant = &"reset") -> bool:
	if _prepared_frame >= 0 or _mastery_prepare_active():
		return false
	var validation: Dictionary = CharacterActionContractScript.validate_reset_reason(reason)
	if not bool(validation.get("ok", false)):
		return false
	var normalized_reason := StringName(str(
		(validation.get("context", {}) as Dictionary).get("reason", &"")
	))
	if _runtime == null:
		if _last_runtime_frame != -1:
			_last_runtime_frame = -1
			_revision += 1
		_reset_action_authority()
		return true

	var runtime_before_value: Variant = _runtime.call("snapshot")
	if not runtime_before_value is Dictionary:
		return false
	var runtime_before := (runtime_before_value as Dictionary).duplicate(true)
	_runtime.call("reset_runtime_state", normalized_reason)
	var runtime_after_value: Variant = _runtime.call("snapshot")
	if not runtime_after_value is Dictionary:
		_restore_runtime_exact(runtime_before)
		return false
	_last_runtime_frame = -1
	_revision += 1
	_reset_action_authority()
	return true


func runtime_frame() -> int:
	return _last_runtime_frame


func revision() -> int:
	return _revision


func is_configured() -> bool:
	return _runtime != null


func reanchor_unconfigured_runtime_frame(runtime_frame: int) -> bool:
	if (
		_runtime != null
		or _prepared_frame >= 0
		or _mastery_prepare_active()
		or runtime_frame < -1
	):
		return false
	if _last_runtime_frame == runtime_frame:
		return true
	_last_runtime_frame = runtime_frame
	_revision += 1
	return true


func can_reanchor_replay_neutral_runtime_frame(runtime_frame: int) -> bool:
	return (
		_runtime != null
		and _prepared_frame < 0
		and not _mastery_prepare_active()
		and _current_token == 0
		and _committed_plan.is_empty()
		and runtime_frame >= 0
		and _runtime.has_method("can_reanchor_replay_neutral_frame")
		and bool(_runtime.call("can_reanchor_replay_neutral_frame", runtime_frame))
	)


func reanchor_replay_neutral_runtime_frame(runtime_frame: int) -> bool:
	if not can_reanchor_replay_neutral_runtime_frame(runtime_frame):
		return false
	if not bool(_runtime.call("reanchor_replay_neutral_frame", runtime_frame)):
		return false
	_last_runtime_frame = runtime_frame
	_revision += 1
	return true


func _clear_prepared_frame() -> void:
	_prepared_frame = -1
	_prepared_runtime_before.clear()
	_prepared_runtime_after.clear()
	_prepared_result.clear()


func _mastery_ticket_matches(ticket: Variant) -> bool:
	return (
		ticket is Dictionary
		and not _prepared_mastery_ticket.is_empty()
		and ticket == _prepared_mastery_ticket
	)


func _mastery_prepare_active() -> bool:
	return not _prepared_mastery_ticket.is_empty()


func _clear_prepared_mastery() -> void:
	_prepared_mastery_ticket.clear()
	_prepared_mastery_runtime_before.clear()
	_prepared_mastery_runtime_after.clear()


func _restore_runtime_exact(value: Dictionary) -> bool:
	if _runtime == null:
		return false
	var accepted_value: Variant = _runtime.call(
		"can_restore_snapshot",
		value.duplicate(true)
	)
	if typeof(accepted_value) != TYPE_BOOL or not bool(accepted_value):
		return false
	var restored_value: Variant = _runtime.call("restore_snapshot", value.duplicate(true))
	return (
		typeof(restored_value) == TYPE_BOOL
		and bool(restored_value)
		and _runtime_snapshot_matches(value)
	)


func _runtime_snapshot_matches(value: Dictionary) -> bool:
	if _runtime == null:
		return false
	var current_value: Variant = _runtime.call("snapshot")
	return current_value is Dictionary and current_value == value


func _runtime_snapshot() -> Dictionary:
	if _runtime == null:
		return {}
	var value: Variant = _runtime.call("snapshot")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _character_action_cancellation_state() -> Dictionary:
	if _runtime == null or not _runtime.has_method("character_action_cancellation_state"):
		return {"active": false, "committed": false}
	var value: Variant = _runtime.call("character_action_cancellation_state")
	if not value is Dictionary:
		return {}
	var state := value as Dictionary
	if (
		state.size() != 2
		or not state.has("active")
		or not state.has("committed")
		or typeof(state["active"]) != TYPE_BOOL
		or typeof(state["committed"]) != TYPE_BOOL
		or (bool(state["committed"]) and not bool(state["active"]))
	):
		return {}
	return {
		"active": bool(state["active"]),
		"committed": bool(state["committed"]),
	}


func _rollback_runtime_rejection(runtime_before: Dictionary, reason: String) -> Dictionary:
	if not _restore_runtime_exact(runtime_before):
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_ROLLBACK_FAILED,
			{"reason": "%s_rollback_failed" % reason}
		)
	return CharacterActionContractScript.failure(
		CharacterActionContractScript.CODE_RUNTIME_REJECTED,
		{"reason": reason}
	)


func _call_decision_hook(method_name: StringName, context: Dictionary) -> Dictionary:
	if _mastery_prepare_active():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "prepared_mastery_active"}
		)
	if _runtime == null:
		return CharacterActionContractScript.failure(CharacterActionContractScript.CODE_NO_RUNTIME)
	var runtime_before := _runtime_snapshot()
	if runtime_before.is_empty():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "snapshot_type"}
		)
	var value: Variant = _runtime.call(method_name, context.duplicate(true))
	if (
		not value is Dictionary
		or typeof((value as Dictionary).get("ok")) != TYPE_BOOL
		or not bool((value as Dictionary).get("ok", false))
		or not (value as Dictionary).get("decision", {}) is Dictionary
	):
		return _rollback_runtime_rejection(runtime_before, "%s_result" % str(method_name))
	return CharacterActionContractScript.success(
		CharacterActionContractScript.CODE_OK,
		[],
		{"decision": ((value as Dictionary).get("decision", {}) as Dictionary).duplicate(true)}
	)


func _call_event_hook(method_name: StringName, context: Dictionary) -> Dictionary:
	if _mastery_prepare_active():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "prepared_mastery_active"}
		)
	if _runtime == null:
		return CharacterActionContractScript.failure(CharacterActionContractScript.CODE_NO_RUNTIME)
	var runtime_before := _runtime_snapshot()
	if runtime_before.is_empty():
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "snapshot_type"}
		)
	var value: Variant = _runtime.call(method_name, context.duplicate(true))
	var validation := CharacterActionContractScript.validate_runtime_events(value)
	if not bool(validation.get("ok", false)):
		return _rollback_runtime_rejection(runtime_before, "%s_result" % str(method_name))
	return CharacterActionContractScript.success(
		CharacterActionContractScript.CODE_OK,
		validation.get("events", []) as Array
	)


func _reset_action_authority() -> void:
	_generation += 1
	_current_token = 0
	_committed_plan.clear()
	_mastery_claims.clear()
	_action_revision += 1


func _valid_action_snapshot(value: Dictionary) -> bool:
	if value.size() != ACTION_SNAPSHOT_FIELDS.size():
		return false
	for field: String in ACTION_SNAPSHOT_FIELDS:
		if not value.has(field):
			return false
	for key: Variant in value.keys():
		if (
			typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME]
			or not ACTION_SNAPSHOT_FIELDS.has(str(key))
		):
			return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != ACTION_SNAPSHOT_SCHEMA_VERSION
		or typeof(value["generation"]) != TYPE_INT
		or int(value["generation"]) <= 0
		or typeof(value["next_token"]) != TYPE_INT
		or int(value["next_token"]) <= 0
		or typeof(value["current_token"]) != TYPE_INT
		or int(value["current_token"]) < 0
		or int(value["current_token"]) >= int(value["next_token"])
		or not value["committed_plan"] is Dictionary
		or not value["mastery_claims"] is Array
		or typeof(value["revision"]) != TYPE_INT
		or int(value["revision"]) < 0
	):
		return false
	var claims_validation := _validated_mastery_claims(
		value["mastery_claims"] as Array,
		int(value["generation"])
	)
	if not bool(claims_validation.get("ok", false)):
		return false
	return (
		int(value["current_token"]) > 0
		or (value["committed_plan"] as Dictionary).is_empty()
	)


func _normalized_mastery_fact(value: Variant, expected_generation: int = -1) -> Dictionary:
	if not value is Dictionary:
		return {}
	var fact: Dictionary = value
	if fact.size() != MASTERY_FACT_FIELDS.size():
		return {}
	for field: String in MASTERY_FACT_FIELDS:
		if not fact.has(field):
			return {}
	for key: Variant in fact.keys():
		if (
			typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME]
			or not MASTERY_FACT_FIELDS.has(str(key))
		):
			return {}
	for field: String in ["weapon_id", "mastery_family", "mastery_id", "action_id"]:
		if (
			typeof(fact[field]) not in [TYPE_STRING, TYPE_STRING_NAME]
			or str(fact[field]).strip_edges().is_empty()
		):
			return {}
	var weapon_id := StringName(str(fact["weapon_id"]).strip_edges())
	var mastery_family := StringName(str(fact["mastery_family"]).strip_edges())
	var mastery_id := StringName(str(fact["mastery_id"]).strip_edges())
	var action_id := StringName(str(fact["action_id"]).strip_edges())
	if weapon_id != mastery_family or not MASTERY_IDS_BY_FAMILY.has(str(mastery_family)):
		return {}
	var allowed_mastery_ids: Array = MASTERY_IDS_BY_FAMILY[str(mastery_family)]
	if not allowed_mastery_ids.has(mastery_id):
		return {}
	var required_generation := _generation if expected_generation < 0 else expected_generation
	if (
		typeof(fact["generation"]) != TYPE_INT
		or int(fact["generation"]) <= 0
		or int(fact["generation"]) != required_generation
		or typeof(fact["action_token"]) != TYPE_INT
		or int(fact["action_token"]) <= 0
		or typeof(fact["target_id"]) != TYPE_INT
		or int(fact["target_id"]) < 0
		or not fact["context"] is Dictionary
	):
		return {}
	var context := (fact["context"] as Dictionary).duplicate(true)
	if not _mastery_context_is_eligible(context):
		return {}
	return {
		"weapon_id": weapon_id,
		"mastery_family": mastery_family,
		"mastery_id": mastery_id,
		"action_id": action_id,
		"generation": int(fact["generation"]),
		"action_token": int(fact["action_token"]),
		"target_id": int(fact["target_id"]),
		"context": context,
	}


func _mastery_claims_snapshot() -> Array[Dictionary]:
	var claims: Array[Dictionary] = []
	var keys: Array = _mastery_claims.keys()
	keys.sort()
	for key: Variant in keys:
		var claim_value: Variant = _mastery_claims[key]
		if claim_value is Dictionary:
			claims.append((claim_value as Dictionary).duplicate(true))
	return claims


func _mastery_claim_map(claims: Array) -> Dictionary:
	var result: Dictionary = {}
	for claim_value: Variant in claims:
		var claim: Dictionary = (claim_value as Dictionary).duplicate(true)
		result[_mastery_claim_key(
			int(claim["generation"]),
			int(claim["action_token"]),
			StringName(claim["mastery_family"])
		)] = claim
	return result


func _validated_mastery_claims(claims: Array, generation: int) -> Dictionary:
	var seen: Dictionary = {}
	var ordered_keys: Array[String] = []
	for claim_value: Variant in claims:
		var normalized := _normalized_mastery_fact(claim_value, generation)
		if normalized.is_empty():
			return {"ok": false}
		var claim_key := _mastery_claim_key(
			int(normalized["generation"]),
			int(normalized["action_token"]),
			StringName(normalized["mastery_family"])
		)
		if seen.has(claim_key):
			return {"ok": false}
		seen[claim_key] = true
		ordered_keys.append(claim_key)
	var sorted_keys := ordered_keys.duplicate()
	sorted_keys.sort()
	if ordered_keys != sorted_keys:
		return {"ok": false}
	return {"ok": true}


static func _mastery_claim_key(
	generation: int,
	action_token: int,
	mastery_family: StringName
) -> String:
	return "%d:%d:%s" % [generation, action_token, str(mastery_family)]


static func _mastery_context_is_eligible(context: Dictionary, depth: int = 0) -> bool:
	if depth > 8 or not ReplaySafeValueScript.is_supported(context):
		return false
	for flag: String in ["is_echo", "recursive_echo", "rejected"]:
		if context.has(flag):
			if typeof(context[flag]) != TYPE_BOOL or bool(context[flag]):
				return false
	if context.has("mastery_eligible"):
		if typeof(context["mastery_eligible"]) != TYPE_BOOL or not bool(context["mastery_eligible"]):
			return false
	if context.has("accepted"):
		if typeof(context["accepted"]) != TYPE_BOOL or not bool(context["accepted"]):
			return false
	if context.has("tags"):
		var tags_value: Variant = context["tags"]
		if not tags_value is Array and not tags_value is PackedStringArray:
			return false
		for tag_value: Variant in tags_value:
			if typeof(tag_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return false
			if str(tag_value) == "no_mastery":
				return false
	for child_value: Variant in context.values():
		if child_value is Dictionary:
			if not _mastery_context_is_eligible(child_value as Dictionary, depth + 1):
				return false
		elif child_value is Array:
			for nested_value: Variant in child_value:
				if nested_value is Dictionary and not _mastery_context_is_eligible(
					nested_value as Dictionary,
					depth + 1
				):
					return false
	return true


static func _validated_snapshot(value: Dictionary) -> Dictionary:
	if not CharacterActionContractScript.has_exact_snapshot_fields(value):
		return {}
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != CharacterActionContractScript.SNAPSHOT_SCHEMA_VERSION
	):
		return {}
	if (
		typeof(value["last_runtime_frame"]) != TYPE_INT
		or int(value["last_runtime_frame"]) < -1
	):
		return {}
	if typeof(value["revision"]) != TYPE_INT or int(value["revision"]) < 0:
		return {}
	if typeof(value["runtime_configured"]) != TYPE_BOOL:
		return {}
	if not value["runtime"] is Dictionary:
		return {}
	if not bool(value["runtime_configured"]) and not (value["runtime"] as Dictionary).is_empty():
		return {}
	return {
		"schema_version": CharacterActionContractScript.SNAPSHOT_SCHEMA_VERSION,
		"last_runtime_frame": int(value["last_runtime_frame"]),
		"revision": int(value["revision"]),
		"runtime_configured": bool(value["runtime_configured"]),
		"runtime": (value["runtime"] as Dictionary).duplicate(true),
	}
