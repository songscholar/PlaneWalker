class_name WeaponActionContract
extends RefCounted

const CODE_OK := &"OK"
const CODE_BUFFERED := &"BUFFERED"
const CODE_INVALID_INTENT := &"INVALID_INTENT"
const CODE_INVALID_PLAN := &"INVALID_PLAN"
const CODE_NOT_CONFIGURED := &"NOT_CONFIGURED"
const CODE_RUNTIME_REJECTED := &"RUNTIME_REJECTED"
const CODE_COMMIT_FAILED := &"COMMIT_FAILED"

const DEFAULT_BUFFER_FRAMES := 8
const MAX_BUFFER_FRAMES := 600
const MAX_PHASE_FRAMES := 216000

const VALID_INTENT_IDS: Array[StringName] = [
	&"weapon_primary",
	&"weapon_secondary",
	&"weapon_utility",
	&"weapon_skill",
	&"weapon_ultimate",
]
const VALID_INTENT_EDGES: Array[StringName] = [
	&"pressed",
	&"released",
	&"held",
]
const VALID_ACTION_PHASES: Array[StringName] = [
	&"HOLD",
	&"WINDUP",
	&"ACTIVE",
	&"RECOVERY",
	&"RESOURCE_ACTION",
	&"CHANNEL",
]


static func success(code: StringName = CODE_OK, context: Dictionary = {}) -> Dictionary:
	return {
		"ok": true,
		"code": code,
		"context": context.duplicate(true),
	}


static func failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"context": context.duplicate(true),
	}


static func validate_intent(intent: Dictionary) -> Dictionary:
	var intent_id_value: Variant = intent.get("id")
	var edge_value: Variant = intent.get("edge")
	if typeof(intent_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return failure(CODE_INVALID_INTENT, {"field": "id", "reason": "type"})
	if typeof(edge_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return failure(CODE_INVALID_INTENT, {"field": "edge", "reason": "type"})

	var intent_id := StringName(str(intent_id_value))
	var edge := StringName(str(edge_value))
	if not VALID_INTENT_IDS.has(intent_id):
		return failure(CODE_INVALID_INTENT, {"field": "id", "reason": "value"})
	if not VALID_INTENT_EDGES.has(edge):
		return failure(CODE_INVALID_INTENT, {"field": "edge", "reason": "value"})

	if intent.has("held_frames"):
		if typeof(intent["held_frames"]) != TYPE_INT or int(intent["held_frames"]) < 0:
			return failure(CODE_INVALID_INTENT, {"field": "held_frames", "reason": "value"})
	if intent.has("buffer_frames"):
		if (
			typeof(intent["buffer_frames"]) != TYPE_INT
			or int(intent["buffer_frames"]) <= 0
			or int(intent["buffer_frames"]) > MAX_BUFFER_FRAMES
		):
			return failure(CODE_INVALID_INTENT, {"field": "buffer_frames", "reason": "value"})
	if intent.has("token") or intent.has("generation"):
		return failure(CODE_INVALID_INTENT, {"field": "token", "reason": "reserved"})
	return success()


static func validate_plan(plan: Dictionary, expected_weapon_id: StringName = &"") -> Dictionary:
	if plan.has("token") or plan.has("generation"):
		return failure(CODE_INVALID_PLAN, {"field": "token", "reason": "reserved"})
	if not _variant_numbers_are_finite(plan):
		return failure(CODE_INVALID_PLAN, {"field": "plan", "reason": "non_finite"})

	var weapon_value: Variant = plan.get("weapon_id")
	var action_value: Variant = plan.get("action_id")
	if typeof(weapon_value) not in [TYPE_STRING, TYPE_STRING_NAME] or str(weapon_value).is_empty():
		return failure(CODE_INVALID_PLAN, {"field": "weapon_id", "reason": "value"})
	if typeof(action_value) not in [TYPE_STRING, TYPE_STRING_NAME] or str(action_value).is_empty():
		return failure(CODE_INVALID_PLAN, {"field": "action_id", "reason": "value"})
	if expected_weapon_id != &"" and StringName(str(weapon_value)) != expected_weapon_id:
		return failure(CODE_INVALID_PLAN, {
			"field": "weapon_id",
			"reason": "mismatch",
			"expected": str(expected_weapon_id),
		})

	var phases_value: Variant = plan.get("phases")
	if not phases_value is Array or (phases_value as Array).is_empty():
		return failure(CODE_INVALID_PLAN, {"field": "phases", "reason": "value"})
	for phase_index: int in range((phases_value as Array).size()):
		var phase_value: Variant = (phases_value as Array)[phase_index]
		if not phase_value is Dictionary:
			return failure(CODE_INVALID_PLAN, {"field": "phases", "index": phase_index, "reason": "type"})
		var phase_result := _validate_phase(phase_value as Dictionary, phase_index)
		if not bool(phase_result.get("ok", false)):
			return phase_result

	var payloads_value: Variant = plan.get("payloads", [])
	if not payloads_value is Array:
		return failure(CODE_INVALID_PLAN, {"field": "payloads", "reason": "type"})
	for payload_index: int in range((payloads_value as Array).size()):
		var payload_value: Variant = (payloads_value as Array)[payload_index]
		if not payload_value is Dictionary:
			return failure(CODE_INVALID_PLAN, {"field": "payloads", "index": payload_index, "reason": "type"})
		var descriptor_value: Variant = (payload_value as Dictionary).get("descriptor_id")
		if typeof(descriptor_value) not in [TYPE_STRING, TYPE_STRING_NAME] or str(descriptor_value).is_empty():
			return failure(CODE_INVALID_PLAN, {
				"field": "payloads.descriptor_id",
				"index": payload_index,
				"reason": "value",
			})
		if not _variant_numbers_are_finite(payload_value):
			return failure(CODE_INVALID_PLAN, {
				"field": "payloads",
				"index": payload_index,
				"reason": "non_finite",
			})
	return success()


static func _validate_phase(phase: Dictionary, phase_index: int) -> Dictionary:
	var phase_name_value: Variant = phase.get("phase")
	if typeof(phase_name_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return failure(CODE_INVALID_PLAN, {"field": "phases.phase", "index": phase_index, "reason": "type"})
	var phase_name := StringName(str(phase_name_value))
	if not VALID_ACTION_PHASES.has(phase_name):
		return failure(CODE_INVALID_PLAN, {"field": "phases.phase", "index": phase_index, "reason": "value"})

	var duration_value: Variant = phase.get("duration_frames")
	if (
		typeof(duration_value) != TYPE_INT
		or int(duration_value) <= 0
		or int(duration_value) > MAX_PHASE_FRAMES
	):
		return failure(CODE_INVALID_PLAN, {"field": "phases.duration_frames", "index": phase_index, "reason": "value"})

	if phase.has("movement_multiplier"):
		var movement_value: Variant = phase["movement_multiplier"]
		if (
			typeof(movement_value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(movement_value))
			or float(movement_value) < 0.0
		):
			return failure(CODE_INVALID_PLAN, {
				"field": "phases.movement_multiplier",
				"index": phase_index,
				"reason": "value",
			})

	if phase.has("cancel_from_frame"):
		var cancel_value: Variant = phase["cancel_from_frame"]
		if phase_name != &"RECOVERY":
			return failure(CODE_INVALID_PLAN, {
				"field": "phases.cancel_from_frame",
				"index": phase_index,
				"reason": "phase",
			})
		if (
			typeof(cancel_value) != TYPE_INT
			or int(cancel_value) < 0
			or int(cancel_value) >= int(duration_value)
		):
			return failure(CODE_INVALID_PLAN, {
				"field": "phases.cancel_from_frame",
				"index": phase_index,
				"reason": "half_open_boundary",
			})
	return success()


static func _variant_numbers_are_finite(value: Variant) -> bool:
	match typeof(value):
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for child: Variant in value as Array:
				if not _variant_numbers_are_finite(child):
					return false
		TYPE_DICTIONARY:
			for child: Variant in (value as Dictionary).values():
				if not _variant_numbers_are_finite(child):
					return false
	return true
