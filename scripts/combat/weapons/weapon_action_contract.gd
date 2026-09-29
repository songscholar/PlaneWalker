class_name WeaponActionContract
extends RefCounted

const CODE_OK := &"OK"
const CODE_BUFFERED := &"BUFFERED"
const CODE_HOLDING := &"HOLDING"
const CODE_HOLD_RELEASED := &"HOLD_RELEASED"
const CODE_HOLD_TOO_SHORT := &"HOLD_TOO_SHORT"
const CODE_STALE_HOLD_EDGE := &"STALE_HOLD_EDGE"
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
	var metadata_result := _validate_plan_metadata(plan)
	if not bool(metadata_result.get("ok", false)):
		return metadata_result

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
	var first_phase: Dictionary = (phases_value as Array)[0]
	if (
		StringName(str(first_phase.get("phase", ""))) == &"HOLD"
		and (phases_value as Array).size() < 2
		and not _has_declared_release_variants(plan)
	):
		return failure(CODE_INVALID_PLAN, {"field": "phases", "reason": "hold_requires_release_phase"})

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
		if phase_name not in [&"RECOVERY", &"RESOURCE_ACTION"]:
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

	const HOLD_ONLY_FIELDS: Array[String] = [
		"minimum_hold_frames",
		"charge_complete_frames",
		"hold_progress_multiplier",
		"movement_start_multiplier",
	]
	if phase_name == &"HOLD":
		if phase_index != 0:
			return failure(CODE_INVALID_PLAN, {
				"field": "phases.phase",
				"index": phase_index,
				"reason": "hold_must_be_first",
			})
		var minimum_value: Variant = phase.get("minimum_hold_frames")
		if (
			typeof(minimum_value) != TYPE_INT
			or int(minimum_value) < 0
			or int(minimum_value) > int(duration_value)
		):
			return failure(CODE_INVALID_PLAN, {
				"field": "phases.minimum_hold_frames",
				"index": phase_index,
				"reason": "outside_hold_duration",
			})
		if phase.has("charge_complete_frames"):
			var charge_complete_value: Variant = phase["charge_complete_frames"]
			if (
				typeof(charge_complete_value) != TYPE_INT
				or int(charge_complete_value) <= 0
				or int(charge_complete_value) < int(minimum_value)
				or int(charge_complete_value) > int(duration_value)
			):
				return failure(CODE_INVALID_PLAN, {
					"field": "phases.charge_complete_frames",
					"index": phase_index,
					"reason": "outside_hold_duration",
				})
		for multiplier_field: String in ["hold_progress_multiplier", "movement_start_multiplier"]:
			if not phase.has(multiplier_field):
				continue
			var multiplier_value: Variant = phase[multiplier_field]
			if (
				typeof(multiplier_value) not in [TYPE_INT, TYPE_FLOAT]
				or not is_finite(float(multiplier_value))
				or float(multiplier_value) < 0.0
			):
				return failure(CODE_INVALID_PLAN, {
					"field": "phases.%s" % multiplier_field,
					"index": phase_index,
					"reason": "value",
				})
	else:
		for hold_field: String in HOLD_ONLY_FIELDS:
			if phase.has(hold_field):
				return failure(CODE_INVALID_PLAN, {
					"field": "phases.%s" % hold_field,
					"index": phase_index,
					"reason": "phase",
				})
	return success()


static func _validate_plan_metadata(plan: Dictionary) -> Dictionary:
	var release_metadata_result := _validate_release_metadata(plan)
	if not bool(release_metadata_result.get("ok", false)):
		return release_metadata_result
	if plan.has("cooldown_frames"):
		var cooldown_value: Variant = plan["cooldown_frames"]
		if (
			typeof(cooldown_value) != TYPE_INT
			or int(cooldown_value) < 0
			or int(cooldown_value) > MAX_PHASE_FRAMES
		):
			return failure(CODE_INVALID_PLAN, {
				"field": "cooldown_frames",
				"reason": "value",
			})

	if plan.has("resource_costs"):
		var resource_costs_value: Variant = plan["resource_costs"]
		if not resource_costs_value is Dictionary:
			return failure(CODE_INVALID_PLAN, {
				"field": "resource_costs",
				"reason": "type",
			})
		var normalized_ids: Dictionary = {}
		for resource_id_value: Variant in (resource_costs_value as Dictionary).keys():
			if typeof(resource_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return failure(CODE_INVALID_PLAN, {
					"field": "resource_costs",
					"reason": "resource_id_type",
				})
			var resource_id := str(resource_id_value).strip_edges()
			if resource_id.is_empty() or normalized_ids.has(resource_id):
				return failure(CODE_INVALID_PLAN, {
					"field": "resource_costs",
					"reason": "resource_id_value",
				})
			normalized_ids[resource_id] = true
			var cost_value: Variant = (resource_costs_value as Dictionary)[resource_id_value]
			if (
				typeof(cost_value) not in [TYPE_INT, TYPE_FLOAT]
				or not is_finite(float(cost_value))
				or float(cost_value) < 0.0
			):
				return failure(CODE_INVALID_PLAN, {
					"field": "resource_costs.%s" % resource_id,
					"reason": "value",
				})
	return success()


static func _validate_release_metadata(plan: Dictionary) -> Dictionary:
	if plan.has("release_action_fingerprint"):
		var fingerprint_value: Variant = plan["release_action_fingerprint"]
		if (
			typeof(fingerprint_value) not in [TYPE_STRING, TYPE_STRING_NAME]
			or str(fingerprint_value).strip_edges().is_empty()
		):
			return failure(CODE_INVALID_PLAN, {
				"field": "release_action_fingerprint",
				"reason": "value",
			})

	var has_allowed_ids := plan.has("allowed_release_action_ids")
	var has_fingerprints := plan.has("release_action_fingerprints")
	if not has_allowed_ids and not has_fingerprints:
		return success()
	if not has_allowed_ids or not has_fingerprints:
		return failure(CODE_INVALID_PLAN, {
			"field": "allowed_release_action_ids",
			"reason": "paired_metadata_required",
		})
	var allowed_value: Variant = plan["allowed_release_action_ids"]
	var fingerprints_value: Variant = plan["release_action_fingerprints"]
	if not allowed_value is Array or (allowed_value as Array).is_empty():
		return failure(CODE_INVALID_PLAN, {
			"field": "allowed_release_action_ids",
			"reason": "value",
		})
	if not fingerprints_value is Dictionary:
		return failure(CODE_INVALID_PLAN, {
			"field": "release_action_fingerprints",
			"reason": "type",
		})
	var normalized_ids: Dictionary = {}
	for action_id_value: Variant in allowed_value as Array:
		if typeof(action_id_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return failure(CODE_INVALID_PLAN, {
				"field": "allowed_release_action_ids",
				"reason": "type",
			})
		var action_id := str(action_id_value).strip_edges()
		if action_id.is_empty() or normalized_ids.has(action_id):
			return failure(CODE_INVALID_PLAN, {
				"field": "allowed_release_action_ids",
				"reason": "value",
			})
		normalized_ids[action_id] = true
		var fingerprint: Variant = (fingerprints_value as Dictionary).get(action_id)
		if (
			typeof(fingerprint) not in [TYPE_STRING, TYPE_STRING_NAME]
			or str(fingerprint).strip_edges().is_empty()
		):
			return failure(CODE_INVALID_PLAN, {
				"field": "release_action_fingerprints.%s" % action_id,
				"reason": "value",
			})
	if (fingerprints_value as Dictionary).size() != normalized_ids.size():
		return failure(CODE_INVALID_PLAN, {
			"field": "release_action_fingerprints",
			"reason": "unexpected_action",
		})
	return success()


static func _has_declared_release_variants(plan: Dictionary) -> bool:
	var allowed_value: Variant = plan.get("allowed_release_action_ids", [])
	var fingerprints_value: Variant = plan.get("release_action_fingerprints", {})
	return (
		allowed_value is Array
		and not (allowed_value as Array).is_empty()
		and fingerprints_value is Dictionary
		and (fingerprints_value as Dictionary).size() == (allowed_value as Array).size()
	)


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
