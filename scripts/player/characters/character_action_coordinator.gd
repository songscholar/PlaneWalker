class_name CharacterActionCoordinator
extends RefCounted

const CharacterActionContractScript := preload(
	"res://scripts/player/characters/character_action_contract.gd"
)

var _runtime: RefCounted
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

const ACTION_SNAPSHOT_SCHEMA_VERSION := 1
const ACTION_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"generation",
	"next_token",
	"current_token",
	"committed_plan",
	"revision",
]


func configure(runtime: Variant) -> bool:
	if _prepared_frame >= 0:
		return false
	var validation: Dictionary = CharacterActionContractScript.validate_runtime(runtime)
	if not bool(validation.get("ok", false)):
		return false
	if _runtime == runtime:
		return true
	if _runtime != null:
		return false
	_runtime = runtime as RefCounted
	_revision += 1
	return true


func set_generation_floor(generation_floor: int) -> bool:
	if generation_floor <= 0 or _prepared_frame >= 0 or _current_token != 0:
		return false
	if generation_floor > _generation:
		_generation = generation_floor
		_action_revision += 1
	return true


func set_next_token_floor(next_token_floor: int) -> bool:
	if next_token_floor <= 0 or _prepared_frame >= 0 or _current_token != 0:
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


func action_snapshot() -> Dictionary:
	return {
		"schema_version": ACTION_SNAPSHOT_SCHEMA_VERSION,
		"generation": _generation,
		"next_token": _next_token,
		"current_token": _current_token,
		"committed_plan": _committed_plan.duplicate(true),
		"revision": _action_revision,
	}


func restore_action_snapshot(value: Dictionary) -> bool:
	if not _valid_action_snapshot(value):
		return false
	_generation = int(value["generation"])
	_next_token = int(value["next_token"])
	_current_token = int(value["current_token"])
	_committed_plan = (value["committed_plan"] as Dictionary).duplicate(true)
	_action_revision = int(value["revision"])
	return action_snapshot() == value


func try_character_skill(intent: Variant, context: Variant) -> Dictionary:
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


func before_time_skill(context: Dictionary) -> Dictionary:
	return _call_decision_hook(&"before_time_skill", context)


func after_time_skill(context: Dictionary) -> Dictionary:
	return _call_event_hook(&"after_time_skill", context)


func on_room_started(context: Dictionary) -> Dictionary:
	return _call_event_hook(&"on_room_started", context)


func on_room_cleared(context: Dictionary) -> Dictionary:
	return _call_event_hook(&"on_room_cleared", context)


func on_run_terminal(context: Dictionary) -> Dictionary:
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
	if _prepared_frame >= 0:
		return CharacterActionContractScript.failure(
			CharacterActionContractScript.CODE_RUNTIME_REJECTED,
			{"reason": "prepared_frame_active"}
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
	if _prepared_frame >= 0:
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
	if _prepared_frame >= 0:
		return false
	var validated := _validated_snapshot(value)
	if validated.is_empty() or bool(validated["runtime_configured"]) != (_runtime != null):
		return false
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
	if _prepared_frame >= 0:
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
	if _runtime != null or _prepared_frame >= 0 or runtime_frame < -1:
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
		or typeof(value["revision"]) != TYPE_INT
		or int(value["revision"]) < 0
	):
		return false
	return (
		int(value["current_token"]) > 0
		or (value["committed_plan"] as Dictionary).is_empty()
	)


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
