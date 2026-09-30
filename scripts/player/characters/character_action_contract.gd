class_name CharacterActionContract
extends RefCounted

const CODE_OK := &"OK"
const CODE_NO_RUNTIME := &"NO_RUNTIME"
const CODE_INVALID_RUNTIME := &"INVALID_RUNTIME"
const CODE_INVALID_FRAME := &"INVALID_FRAME"
const CODE_FRAME_NOT_MONOTONIC := &"FRAME_NOT_MONOTONIC"
const CODE_INVALID_CONTEXT := &"INVALID_CONTEXT"
const CODE_INVALID_EVENTS := &"INVALID_EVENTS"
const CODE_RUNTIME_REJECTED := &"RUNTIME_REJECTED"
const CODE_ROLLBACK_FAILED := &"ROLLBACK_FAILED"
const CODE_INVALID_SNAPSHOT := &"INVALID_SNAPSHOT"
const CODE_INVALID_RESET_REASON := &"INVALID_RESET_REASON"

const SNAPSHOT_SCHEMA_VERSION := 1
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"last_runtime_frame",
	"revision",
	"runtime_configured",
	"runtime",
]
const REQUIRED_RUNTIME_METHODS: Array[StringName] = [
	&"advance_frame",
	&"snapshot",
	&"can_restore_snapshot",
	&"restore_snapshot",
	&"reset_runtime_state",
]


static func success(
	code: StringName = CODE_OK,
	events: Array = [],
	context: Dictionary = {}
) -> Dictionary:
	return {
		"ok": true,
		"code": code,
		"events": events.duplicate(true),
		"context": context.duplicate(true),
	}


static func failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"events": [],
		"context": context.duplicate(true),
	}


static func validate_runtime(runtime: Variant) -> Dictionary:
	if runtime == null or not runtime is RefCounted:
		return failure(CODE_INVALID_RUNTIME, {"reason": "type"})
	for method_name: StringName in REQUIRED_RUNTIME_METHODS:
		if not runtime.has_method(method_name):
			return failure(CODE_INVALID_RUNTIME, {
				"reason": "missing_method",
				"method": str(method_name),
			})
	var snapshot_value: Variant = runtime.call("snapshot")
	if not snapshot_value is Dictionary:
		return failure(CODE_INVALID_RUNTIME, {"reason": "snapshot_type"})
	return success()


static func validate_advance(
	runtime_frame: Variant,
	last_runtime_frame: int,
	context: Variant
) -> Dictionary:
	if typeof(runtime_frame) != TYPE_INT or int(runtime_frame) < 0:
		return failure(CODE_INVALID_FRAME, {"runtime_frame": runtime_frame})
	if int(runtime_frame) <= last_runtime_frame:
		return failure(CODE_FRAME_NOT_MONOTONIC, {
			"runtime_frame": int(runtime_frame),
			"last_runtime_frame": last_runtime_frame,
		})
	if not context is Dictionary:
		return failure(CODE_INVALID_CONTEXT, {"reason": "type"})
	if (context as Dictionary).has("runtime_frame"):
		return failure(CODE_INVALID_CONTEXT, {
			"field": "runtime_frame",
			"reason": "reserved",
		})
	return success()


static func validate_runtime_events(value: Variant) -> Dictionary:
	if not value is Array:
		return failure(CODE_INVALID_EVENTS, {"reason": "type"})
	var events: Array[Dictionary] = []
	for event_index: int in range((value as Array).size()):
		var event_value: Variant = (value as Array)[event_index]
		if not event_value is Dictionary:
			return failure(CODE_INVALID_EVENTS, {
				"reason": "event_type",
				"index": event_index,
			})
		events.append((event_value as Dictionary).duplicate(true))
	return success(CODE_OK, events)


static func validate_reset_reason(reason: Variant) -> Dictionary:
	if typeof(reason) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return failure(CODE_INVALID_RESET_REASON, {"reason": "type"})
	var normalized := str(reason).strip_edges()
	if normalized.is_empty():
		return failure(CODE_INVALID_RESET_REASON, {"reason": "empty"})
	return success(CODE_OK, [], {"reason": StringName(normalized)})


static func has_exact_snapshot_fields(value: Dictionary) -> bool:
	if value.size() != SNAPSHOT_FIELDS.size():
		return false
	for field: String in SNAPSHOT_FIELDS:
		if not value.has(field):
			return false
	for key: Variant in value.keys():
		if (
			typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME]
			or not SNAPSHOT_FIELDS.has(str(key))
		):
			return false
	return true
