class_name WeaponRuntime
extends RefCounted

const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")
const MASTERY_CONFIRMATION_FIELDS: Array[String] = [
	"confirmed",
	"hit_confirmed",
	"hit",
]


func weapon_id() -> StringName:
	return &""


func mastery_family() -> StringName:
	return weapon_id()


func mastery_ids() -> Array[StringName]:
	return []


func build_mastery_fact(
	mastery_id: StringName,
	action_id: StringName,
	generation: int,
	action_token: int,
	target_id: int,
	payload_result: Variant,
	context: Variant = {}
) -> Dictionary:
	var family := mastery_family()
	if (
		family == &""
		or not mastery_ids().has(mastery_id)
		or str(action_id).strip_edges().is_empty()
		or generation <= 0
		or action_token <= 0
		or target_id < 0
		or not payload_result is Dictionary
		or not context is Dictionary
	):
		return {}
	if (
		not _mastery_payload_is_eligible(payload_result as Dictionary)
		or not _mastery_metadata_is_eligible(context as Dictionary)
	):
		return {}
	return {
		"weapon_id": weapon_id(),
		"mastery_family": family,
		"mastery_id": mastery_id,
		"action_id": action_id,
		"generation": generation,
		"action_token": action_token,
		"target_id": target_id,
		"context": (context as Dictionary).duplicate(true),
	}


func _mastery_payload_is_eligible(payload_result: Dictionary) -> bool:
	var confirmed := false
	for field: String in MASTERY_CONFIRMATION_FIELDS:
		if not payload_result.has(field):
			continue
		if typeof(payload_result[field]) != TYPE_BOOL:
			return false
		confirmed = confirmed or bool(payload_result[field])
	if not confirmed:
		var result_type_value: Variant = payload_result.get("type", payload_result.get("result_type", &""))
		if typeof(result_type_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		confirmed = StringName(str(result_type_value)) == &"hit_confirmed"
	if not confirmed:
		return false
	if payload_result.has("ok"):
		if typeof(payload_result["ok"]) != TYPE_BOOL or not bool(payload_result["ok"]):
			return false
	return _mastery_metadata_is_eligible(payload_result)


func _mastery_metadata_is_eligible(value: Dictionary, depth: int = 0) -> bool:
	if depth > 8 or not ReplaySafeValueScript.is_supported(value):
		return false
	for flag: String in ["is_echo", "recursive_echo", "rejected"]:
		if value.has(flag):
			if typeof(value[flag]) != TYPE_BOOL or bool(value[flag]):
				return false
	if value.has("mastery_eligible"):
		if typeof(value["mastery_eligible"]) != TYPE_BOOL or not bool(value["mastery_eligible"]):
			return false
	if value.has("accepted"):
		if typeof(value["accepted"]) != TYPE_BOOL or not bool(value["accepted"]):
			return false
	if value.has("tags"):
		var tags_value: Variant = value["tags"]
		if not tags_value is Array and not tags_value is PackedStringArray:
			return false
		for tag_value: Variant in tags_value:
			if typeof(tag_value) not in [TYPE_STRING, TYPE_STRING_NAME] or str(tag_value) == "no_mastery":
				return false
	for child_value: Variant in value.values():
		if child_value is Dictionary:
			if not _mastery_metadata_is_eligible(child_value as Dictionary, depth + 1):
				return false
		elif child_value is Array:
			for nested_value: Variant in child_value:
				if nested_value is Dictionary and not _mastery_metadata_is_eligible(
					nested_value as Dictionary,
					depth + 1
				):
					return false
	return true


func configure(_owner: Node, _profile: Variant, _modifiers: Variant) -> bool:
	return false


func capabilities() -> PackedStringArray:
	return PackedStringArray()


func plan_intent(_intent: Dictionary, _context: Dictionary) -> Dictionary:
	return {"ok": false, "code": &"UNSUPPORTED_INTENT"}


func commit_action(_plan: Dictionary, _token: int) -> Dictionary:
	return {"ok": false, "code": &"UNSUPPORTED_ACTION"}


func on_phase_enter(_plan: Dictionary, _phase: StringName, _token: int) -> Array[Dictionary]:
	return []


func on_action_frame(
	_plan: Dictionary,
	_phase: StringName,
	_token: int,
	_phase_frame: int
) -> Array[Dictionary]:
	return []


func release_hold(_plan: Dictionary, _token: int, _held_frames: int) -> Dictionary:
	return {"ok": false, "code": &"UNSUPPORTED_HOLD_RELEASE", "context": {}}


func handle_live_intent(
	_plan: Dictionary,
	_token: int,
	_phase: StringName,
	_phase_frame: int,
	_intent: Dictionary,
	_context: Dictionary
) -> Dictionary:
	return {"handled": false}


func handle_payload_result(
	_token: int,
	_generation: int,
	_result: Dictionary
) -> Dictionary:
	return {"ok": false, "code": &"UNSUPPORTED_PAYLOAD_RESULT"}


func advance_runtime_frame(_coordinator_frame: int) -> Array[Dictionary]:
	return []


func cancel_action(_token: int, _reason: StringName) -> void:
	pass


func cancel_for_gameplay_rewind(
	token: int,
	reason: StringName,
	_hold_runtime_snapshot: Dictionary = {}
) -> bool:
	cancel_action(token, reason)
	return true


func gameplay_rewind_snapshot() -> Dictionary:
	return snapshot()


func restore_gameplay_rewind_snapshot_for_rollback(runtime_snapshot: Dictionary) -> bool:
	return restore_snapshot(runtime_snapshot)


func gameplay_rewind_committed_payload_guard() -> Dictionary:
	return {}


func finish_action(_token: int) -> void:
	pass


func apply_modifier(_effect_id: StringName, _value: Variant) -> bool:
	return false


func reset_runtime_state(_reason: StringName) -> void:
	pass


func snapshot() -> Dictionary:
	return {}


func restore_snapshot(_runtime_snapshot: Dictionary) -> bool:
	return false


func presentation_snapshot() -> Dictionary:
	return {}
