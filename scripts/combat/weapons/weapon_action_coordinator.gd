class_name WeaponActionCoordinator
extends RefCounted

signal weapon_action_committed(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	context: Dictionary
)

const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
const PHASE_READY := &"READY"

var _runtime: RefCounted
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


func configure(runtime: RefCounted) -> bool:
	if runtime == null or not _runtime_has_contract(runtime):
		return false
	var runtime_weapon_id := StringName(str(runtime.call("weapon_id")))
	if runtime_weapon_id == &"":
		return false
	if _runtime != null:
		cancel(&"runtime_reconfigured")
	_runtime = runtime
	_weapon_id = runtime_weapon_id
	return true


func submit_intent(intent: Dictionary, context: Dictionary) -> Dictionary:
	var intent_validation: Dictionary = WeaponActionContractScript.validate_intent(intent)
	if not bool(intent_validation.get("ok", false)):
		return intent_validation
	if _runtime == null:
		return WeaponActionContractScript.failure(WeaponActionContractScript.CODE_NOT_CONFIGURED)

	if _phase != PHASE_READY and not _recovery_cancel_is_open():
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


func advance_frame() -> void:
	_frame += 1
	_prune_expired_buffer()
	if _phase == PHASE_READY:
		_consume_buffered_submission()
		return

	_phase_frame += 1
	var phase_data := _current_phase_data()
	if phase_data.is_empty():
		cancel(&"invalid_phase_state")
		return
	if _phase_frame >= int(phase_data["duration_frames"]):
		_advance_phase()
	if _phase != PHASE_READY and _recovery_cancel_is_open():
		_consume_buffered_submission()


func cancel(reason: StringName = &"cancelled") -> void:
	if _runtime != null and _token > 0:
		_runtime.call("cancel_action", _token, reason)
	_generation += 1
	_buffered_submission.clear()
	_clear_action_state()


func reset_runtime_state(reason: StringName = &"reset") -> void:
	cancel(reason)
	if _runtime != null:
		_runtime.call("reset_runtime_state", reason)


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
	return float(phase_data.get("movement_multiplier", 1.0))


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
		"runtime": runtime_snapshot,
	}


func restore_safe(safe_snapshot: Dictionary) -> bool:
	if _runtime == null or not _validate_safe_snapshot(safe_snapshot):
		return false

	var runtime_before_value: Variant = _runtime.call("snapshot")
	if not runtime_before_value is Dictionary:
		return false
	var runtime_before := (runtime_before_value as Dictionary).duplicate(true)
	var target_runtime := (safe_snapshot["runtime"] as Dictionary).duplicate(true)
	if not bool(_runtime.call("restore_snapshot", target_runtime)):
		_runtime.call("restore_snapshot", runtime_before)
		return false

	var previous_generation := _generation
	_frame = int(safe_snapshot["frame"])
	_next_token = maxi(_next_token, int(safe_snapshot["next_token"]))
	_generation = maxi(previous_generation, int(safe_snapshot["generation"])) + 1
	_buffered_submission.clear()
	_clear_action_state()
	return true


func presentation_snapshot() -> Dictionary:
	var runtime_presentation: Dictionary = {}
	if _runtime != null:
		var runtime_value: Variant = _runtime.call("presentation_snapshot")
		if runtime_value is Dictionary:
			runtime_presentation = (runtime_value as Dictionary).duplicate(true)
	var phase_data := _current_phase_data()
	return {
		"weapon_id": str(_weapon_id),
		"action_id": str(_plan.get("action_id", "")),
		"phase": str(_phase),
		"phase_frame": _phase_frame,
		"phase_duration_frames": int(phase_data.get("duration_frames", 0)),
		"movement_multiplier": movement_multiplier(),
		"token": _token,
		"generation": _generation,
		"runtime": runtime_presentation,
	}


func _commit_intent(intent: Dictionary, context: Dictionary, replacing_action: bool) -> Dictionary:
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

	var next_action_token := _next_token
	var commit_value: Variant = _runtime.call(
		"commit_action",
		committed_plan.duplicate(true),
		next_action_token
	)
	if not commit_value is Dictionary or not bool((commit_value as Dictionary).get("ok", false)):
		_runtime.call("restore_snapshot", runtime_before)
		if commit_value is Dictionary:
			return _runtime_failure(commit_value as Dictionary, WeaponActionContractScript.CODE_COMMIT_FAILED)
		return WeaponActionContractScript.failure(
			WeaponActionContractScript.CODE_COMMIT_FAILED,
			{"reason": "commit_result_type"}
		)

	if replacing_action:
		_generation += 1
	_plan = committed_plan
	_action_context = context.duplicate(true)
	_token = next_action_token
	_next_token += 1
	_phase_index = 0
	_phase_frame = 0
	_phase = StringName(str(_current_phase_data().get("phase", "")))
	_buffered_submission.clear()

	weapon_action_committed.emit(
		_weapon_id,
		StringName(str(_plan["action_id"])),
		_token,
		_action_context.duplicate(true)
	)
	_enter_current_phase()
	return {
		"ok": true,
		"code": WeaponActionContractScript.CODE_OK,
		"token": _token,
		"generation": _generation,
		"context": (commit_value as Dictionary).get("context", {}).duplicate(true),
	}


func _advance_phase() -> void:
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
	_consume_buffered_submission()


func _enter_current_phase() -> void:
	if _runtime == null or _token <= 0 or _phase == PHASE_READY:
		return
	_runtime.call(
		"on_phase_enter",
		_plan.duplicate(true),
		_phase,
		_token
	)


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
	if _phase != &"RECOVERY":
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


func _clear_action_state() -> void:
	_phase = PHASE_READY
	_phase_index = -1
	_phase_frame = 0
	_token = 0
	_plan.clear()
	_action_context.clear()


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
	return safe_snapshot.get("runtime") is Dictionary


func _runtime_failure(runtime_result: Dictionary, fallback_code: StringName) -> Dictionary:
	var code_value: Variant = runtime_result.get("code", fallback_code)
	var code := StringName(str(code_value)) if not str(code_value).is_empty() else fallback_code
	var context_value: Variant = runtime_result.get("context", {})
	var context := (context_value as Dictionary).duplicate(true) if context_value is Dictionary else {}
	return WeaponActionContractScript.failure(code, context)


func _runtime_has_contract(runtime: RefCounted) -> bool:
	for method_name: StringName in [
		&"weapon_id",
		&"configure",
		&"capabilities",
		&"plan_intent",
		&"commit_action",
		&"on_phase_enter",
		&"cancel_action",
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
