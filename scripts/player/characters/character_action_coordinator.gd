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
