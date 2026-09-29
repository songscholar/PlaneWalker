class_name SwordWeaponRuntime
extends "res://scripts/combat/weapons/weapon_runtime.gd"

const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
const PROFILE_ID := "sword_m1_v1"
const WEAPON_ID := &"sword"
const COMBO_ACTION_IDS: Array[StringName] = [&"light_1", &"light_2", &"light_3"]
const HEAVY_ACTION_ID := &"heavy"
const COMBO_RESET_FRAMES := 48
const FROZEN_M1_ACTIONS := {
	"light_1": {
		"action_id": "light_1",
		"semantic_action": "weapon_primary",
		"activation_mode": "press",
		"windup_frames": 6,
		"active_frames": 5,
		"recovery_frames": 11,
		"cancel_from_frame": 6,
		"buffer_frames": 12,
		"movement_multiplier": 0.55,
		"payload_id": "sword_light_1_hitbox",
		"cue_id": "sword_light_1_active",
		"animation_id": "sword_light_1",
		"vfx_id": "sword_light_arc",
		"audio_id": "sword_swing",
		"camera_id": "impact_light",
		"damage_multiplier": 0.8,
		"knockback": 120.0,
		"tags": ["weapon:sword"],
		"timing_seconds": {"windup": 0.10, "active": 0.08, "recovery": 0.18, "cancel": 0.10},
	},
	"light_2": {
		"action_id": "light_2",
		"semantic_action": "weapon_primary",
		"activation_mode": "press",
		"windup_frames": 8,
		"active_frames": 5,
		"recovery_frames": 12,
		"cancel_from_frame": 6,
		"buffer_frames": 12,
		"movement_multiplier": 0.55,
		"payload_id": "sword_light_2_hitbox",
		"cue_id": "sword_light_2_active",
		"animation_id": "sword_light_2",
		"vfx_id": "sword_light_arc",
		"audio_id": "sword_swing",
		"camera_id": "impact_light",
		"damage_multiplier": 1.0,
		"knockback": 120.0,
		"tags": ["weapon:sword"],
		"timing_seconds": {"windup": 0.12, "active": 0.08, "recovery": 0.20, "cancel": 0.10},
	},
	"light_3": {
		"action_id": "light_3",
		"semantic_action": "weapon_primary",
		"activation_mode": "press",
		"windup_frames": 10,
		"active_frames": 6,
		"recovery_frames": 17,
		"cancel_from_frame": 6,
		"buffer_frames": 12,
		"movement_multiplier": 0.55,
		"payload_id": "sword_light_3_hitbox",
		"cue_id": "sword_light_3_active",
		"animation_id": "sword_light_3",
		"vfx_id": "sword_finisher_arc",
		"audio_id": "sword_finisher",
		"camera_id": "impact_medium",
		"damage_multiplier": 1.3,
		"knockback": 120.0,
		"tags": ["attack:finisher", "weapon:sword"],
		"timing_seconds": {"windup": 0.16, "active": 0.10, "recovery": 0.28, "cancel": 0.10},
	},
	"heavy": {
		"action_id": "heavy",
		"semantic_action": "weapon_secondary",
		"activation_mode": "press",
		"windup_frames": 21,
		"active_frames": 8,
		"recovery_frames": 27,
		"cancel_from_frame": 15,
		"buffer_frames": 12,
		"movement_multiplier": 0.2,
		"payload_id": "sword_heavy_hitbox",
		"cue_id": "sword_heavy_active",
		"animation_id": "sword_heavy",
		"vfx_id": "sword_heavy_arc",
		"audio_id": "sword_heavy",
		"camera_id": "impact_heavy",
		"damage_multiplier": 2.0,
		"knockback": 260.0,
		"tags": ["attack:heavy", "weapon:sword"],
		"timing_seconds": {"windup": 0.35, "active": 0.12, "recovery": 0.45, "cancel": 0.24},
	},
}
const REQUIRED_ADAPTER_METHODS: Array[StringName] = [
	&"begin_profile_attack",
	&"is_attacking",
	&"enter_profile_active_phase",
	&"leave_active_phase",
	&"finish_attack",
	&"cancel_attack",
	&"reset_combo",
]
const REQUIRED_MODIFIER_METHODS: Array[StringName] = [
	&"apply",
	&"freeze_for_action",
	&"snapshot",
	&"reset",
]
const LEGACY_REWARD_FIELDS: Array[String] = [
	"combo_finisher_multiplier_bonus",
	"heavy_damage_multiplier_bonus",
	"heavy_execute_multiplier_bonus",
	"heavy_execute_threshold",
	"low_hp_damage_multiplier_bonus",
	"low_hp_threshold",
]

var _owner: Node
var _adapter: Node
var _modifier_state: RefCounted
var _profile_snapshot: Dictionary = {}
var _actions_by_id: Dictionary = {}
var _payloads_by_id: Dictionary = {}
var _cues_by_id: Dictionary = {}
var _capabilities: PackedStringArray = PackedStringArray()

var _combo_step: int = 0
var _active_token: int = 0
var _active_phase: StringName = &"READY"
var _active_plan: Dictionary = {}
var _modifier_snapshot: Dictionary = {}


func weapon_id() -> StringName:
	return WEAPON_ID


func configure(owner: Node, profile: Variant, modifiers: Variant) -> bool:
	if owner == null or not is_instance_valid(owner):
		return false
	if not profile is RefCounted or not (profile as RefCounted).has_method("snapshot"):
		return false
	if not modifiers is RefCounted or not _has_methods(modifiers as RefCounted, REQUIRED_MODIFIER_METHODS):
		return false

	var adapter := owner.get_node_or_null("SwordWeapon")
	if adapter == null or not _has_methods(adapter, REQUIRED_ADAPTER_METHODS):
		return false
	var profile_value: Variant = (profile as RefCounted).call("snapshot")
	if not profile_value is Dictionary:
		return false
	var next_profile := (profile_value as Dictionary).duplicate(true)
	if (
		str(next_profile.get("id", "")) != PROFILE_ID
		or str(next_profile.get("weapon_id", "")) != str(WEAPON_ID)
		or int(next_profile.get("profile_version", 0)) != 1
	):
		return false

	var indexes := _build_profile_indexes(next_profile)
	if not bool(indexes.get("ok", false)):
		return false
	if not _matches_frozen_m1_profile(indexes):
		return false
	var next_capabilities := PackedStringArray(next_profile.get("capabilities", []))
	var frozen_value: Variant = (modifiers as RefCounted).call("freeze_for_action")
	if not frozen_value is Dictionary or not _dictionary_numbers_are_finite(frozen_value as Dictionary):
		return false

	_owner = owner
	_adapter = adapter
	_modifier_state = modifiers as RefCounted
	_profile_snapshot = next_profile
	_actions_by_id = (indexes["actions"] as Dictionary).duplicate(true)
	_payloads_by_id = (indexes["payloads"] as Dictionary).duplicate(true)
	_cues_by_id = (indexes["cues"] as Dictionary).duplicate(true)
	_capabilities = next_capabilities
	reset_runtime_state(&"configured")
	return true


func capabilities() -> PackedStringArray:
	return _capabilities.duplicate()


func plan_intent(intent: Dictionary, _context: Dictionary) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if str(intent.get("edge", "")) != "pressed":
		return _failure(&"UNSUPPORTED_EDGE")

	var semantic_id := StringName(str(intent.get("id", "")))
	var action_id: StringName
	var heavy := false
	match semantic_id:
		&"weapon_primary":
			action_id = COMBO_ACTION_IDS[_combo_step]
		&"weapon_secondary":
			action_id = HEAVY_ACTION_ID
			heavy = true
		_:
			return _failure(&"UNSUPPORTED_INTENT")

	var action: Dictionary = _copy_indexed(_actions_by_id, action_id)
	if action.is_empty():
		return _failure(&"ACTION_NOT_FOUND", {"action_id": str(action_id)})
	var payload_id := StringName(str(action.get("payload_id", "")))
	var payload: Dictionary = _copy_indexed(_payloads_by_id, payload_id)
	if payload.is_empty():
		return _failure(&"PAYLOAD_NOT_FOUND", {"payload_id": str(payload_id)})
	var cue_id := StringName(str(action.get("cue_id", "")))
	var cue: Dictionary = _copy_indexed(_cues_by_id, cue_id)
	if cue.is_empty():
		return _failure(&"CUE_NOT_FOUND", {"cue_id": str(cue_id)})

	var modifier_value: Variant = _modifier_state.call("freeze_for_action")
	if not modifier_value is Dictionary or not _dictionary_numbers_are_finite(modifier_value as Dictionary):
		return _failure(&"INVALID_MODIFIER_SNAPSHOT")
	var frozen_modifiers := (modifier_value as Dictionary).duplicate(true)
	var timing_multiplier := _timing_multiplier(frozen_modifiers)
	var recovery_frames := _scaled_action_frames(action_id, &"recovery", timing_multiplier)
	var cancel_from_frame := mini(
		_scaled_action_frames(action_id, &"cancel", timing_multiplier),
		recovery_frames - 1
	)
	var plan := {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(action_id),
		"profile_id": str(_profile_snapshot["id"]),
		"profile_version": int(_profile_snapshot["profile_version"]),
		"semantic_action": str(semantic_id),
		"heavy": heavy,
		"combo_step_before": _combo_step,
		"combo_reset_frames": COMBO_RESET_FRAMES,
		"buffer_frames": int(action.get("buffer_frames", 12)),
		"modifier_snapshot": frozen_modifiers,
		"base_attack_snapshot": float(_adapter.get("base_attack")),
		"legacy_reward_snapshot": _legacy_reward_snapshot(),
		"cue": cue,
		"phases": [
			{
				"phase": "WINDUP",
				"duration_frames": _scaled_action_frames(action_id, &"windup", timing_multiplier),
				"movement_multiplier": float(action.get("movement_multiplier", 1.0)),
			},
			{
				"phase": "ACTIVE",
				"duration_frames": _scaled_action_frames(action_id, &"active", timing_multiplier),
				"movement_multiplier": float(action.get("movement_multiplier", 1.0)),
			},
			{
				"phase": "RECOVERY",
				"duration_frames": recovery_frames,
				"cancel_from_frame": cancel_from_frame,
				"movement_multiplier": float(action.get("movement_multiplier", 1.0)),
			},
		],
		"payloads": [{
			"descriptor_id": str(payload_id),
			"kind": str(payload.get("kind", "")),
			"parameters": (payload.get("parameters", {}) as Dictionary).duplicate(true),
		}],
	}
	var validation: Dictionary = WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	if not bool(validation.get("ok", false)):
		return validation
	return {"ok": true, "code": &"OK", "plan": plan.duplicate(true), "context": {}}


func commit_action(plan: Dictionary, token: int) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if token <= 0:
		return _failure(&"INVALID_TOKEN")
	if _active_token > 0 or bool(_adapter.call("is_attacking")):
		return _failure(&"ACTION_IN_PROGRESS")
	var validation := _validate_commit_plan(plan)
	if not bool(validation.get("ok", false)):
		return validation

	var adapter_before := _adapter_snapshot()
	_adapter.set("_combo_index", _combo_step)
	var profile_attack := _profile_attack_definition(plan)
	if profile_attack.is_empty():
		return _failure(&"PAYLOAD_PROFILE_INVALID")
	var committed_value: Variant = _adapter.call("begin_profile_attack", profile_attack.duplicate(true))
	if not committed_value is Dictionary or (committed_value as Dictionary).is_empty():
		_restore_adapter_snapshot(adapter_before)
		return _failure(&"PAYLOAD_CONSTRUCTION_FAILED")
	var committed := committed_value as Dictionary
	if not _adapter_definition_matches_plan(committed, plan):
		_restore_adapter_snapshot(adapter_before)
		return _failure(&"PAYLOAD_PROFILE_MISMATCH")

	_active_token = token
	_active_phase = &"WINDUP"
	_active_plan = plan.duplicate(true)
	_modifier_snapshot = (plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true)
	if not bool(plan.get("heavy", false)):
		_combo_step = (_combo_step + 1) % COMBO_ACTION_IDS.size()
	return {
		"ok": true,
		"code": &"OK",
		"context": {
			"action_id": str(_active_plan["action_id"]),
			"combo_step": _combo_step,
		},
	}


func on_phase_enter(plan: Dictionary, phase: StringName, token: int) -> Array[Dictionary]:
	if not _matches_active_action(plan, token):
		return []
	match phase:
		&"WINDUP":
			if _active_phase != &"WINDUP":
				return []
		&"ACTIVE":
			if _active_phase != &"WINDUP":
				return []
			if not _activate_payload():
				return [{"type": "phase_failed", "reason": "payload_activation_failed"}]
			_active_phase = &"ACTIVE"
			return [
				{
					"type": "payload_released",
					"weapon_id": str(WEAPON_ID),
					"action_id": str(_active_plan["action_id"]),
					"descriptor_id": str((_active_plan["payloads"] as Array)[0]["descriptor_id"]),
					"token": token,
				},
				{
					"type": "cue_requested",
					"weapon_id": str(WEAPON_ID),
					"action_id": str(_active_plan["action_id"]),
					"cue": (_active_plan["cue"] as Dictionary).duplicate(true),
					"token": token,
				},
			]
		&"RECOVERY":
			if _active_phase not in [&"WINDUP", &"ACTIVE"]:
				return []
			_adapter.call("leave_active_phase")
			_active_phase = &"RECOVERY"
	return []


func cancel_action(token: int, _reason: StringName) -> void:
	if token <= 0 or token != _active_token:
		return
	_adapter.call("cancel_attack")
	_clear_active_action()


func finish_action(token: int) -> void:
	if token <= 0 or token != _active_token:
		return
	_adapter.call("finish_attack")
	_clear_active_action()


func apply_modifier(effect_id: StringName, value: Variant) -> bool:
	if _modifier_state == null or not _capabilities.has(str(effect_id)):
		return false
	return bool(_modifier_state.call("apply", effect_id, value))


func reset_combo() -> void:
	_combo_step = 0
	if _adapter != null:
		_adapter.call("reset_combo")


func combo_step() -> int:
	return _combo_step


func reset_runtime_state(_reason: StringName) -> void:
	if _adapter != null:
		_adapter.call("cancel_attack")
		_adapter.call("reset_combo")
	_combo_step = 0
	_clear_active_action()


func snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"configured": _is_configured(),
		"profile_id": str(_profile_snapshot.get("id", "")),
		"profile_version": int(_profile_snapshot.get("profile_version", 0)),
		"combo_step": _combo_step,
		"active_token": _active_token,
		"active_phase": str(_active_phase),
		"active_plan": _active_plan.duplicate(true),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
		"adapter": _adapter_snapshot(),
	}


func restore_snapshot(runtime_snapshot: Dictionary) -> bool:
	if not _is_configured() or not _valid_restore_snapshot(runtime_snapshot):
		return false
	var next_adapter: Dictionary = runtime_snapshot["adapter"]
	_combo_step = int(runtime_snapshot["combo_step"])
	_clear_active_action()
	_restore_adapter_snapshot({
		"combo_index": int(next_adapter["combo_index"]),
		"attacking": false,
		"active": false,
		"current_attack": {},
	})
	return true


func presentation_snapshot() -> Dictionary:
	var facing := Vector2.RIGHT
	if _adapter is Node2D:
		facing = Vector2.RIGHT.rotated((_adapter as Node2D).global_rotation)
	return {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(_active_plan.get("action_id", "")),
		"phase": str(_active_phase),
		"combo_step": _combo_step,
		"combo_reset_frames": COMBO_RESET_FRAMES,
		"token": _active_token,
		"facing": facing,
		"cue_id": str((_active_plan.get("cue", {}) as Dictionary).get("cue_id", "")),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
	}


func _validate_commit_plan(plan: Dictionary) -> Dictionary:
	var contract_result: Dictionary = WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	if not bool(contract_result.get("ok", false)):
		return contract_result
	if (
		str(plan.get("profile_id", "")) != str(_profile_snapshot.get("id", ""))
		or int(plan.get("profile_version", 0)) != int(_profile_snapshot.get("profile_version", 0))
	):
		return _failure(&"PROFILE_MISMATCH")
	if int(plan.get("combo_step_before", -1)) != _combo_step:
		return _failure(&"STALE_COMBO_PLAN")
	var expected_action := (
		HEAVY_ACTION_ID
		if bool(plan.get("heavy", false))
		else COMBO_ACTION_IDS[_combo_step]
	)
	if StringName(str(plan.get("action_id", ""))) != expected_action:
		return _failure(&"ACTION_ID_MISMATCH")
	if not plan.get("modifier_snapshot", {}) is Dictionary:
		return _failure(&"INVALID_MODIFIER_SNAPSHOT")
	return {"ok": true, "code": &"OK", "context": {}}


func _adapter_definition_matches_plan(definition: Dictionary, plan: Dictionary) -> bool:
	return definition == _profile_attack_definition(plan)


func _activate_payload() -> bool:
	var live_base_attack := float(_adapter.get("base_attack"))
	var live_rewards := _legacy_reward_snapshot()
	var damage_multiplier := float(_modifier_snapshot.get("weapon.damage", 1.0))
	_adapter.set("base_attack", float(_active_plan.get("base_attack_snapshot", live_base_attack)) * damage_multiplier)
	_apply_legacy_reward_snapshot(_active_plan.get("legacy_reward_snapshot", {}))
	var profile_attack := _profile_attack_definition(_active_plan)
	var activated := (
		not profile_attack.is_empty()
		and bool(_adapter.call("enter_profile_active_phase", profile_attack.duplicate(true)))
	)
	_adapter.set("base_attack", live_base_attack)
	_apply_legacy_reward_snapshot(live_rewards)
	return activated


func _build_profile_indexes(profile: Dictionary) -> Dictionary:
	var actions: Dictionary = {}
	for action_value: Variant in profile.get("actions", []):
		if not action_value is Dictionary:
			return {"ok": false}
		var action: Dictionary = action_value
		var action_id := str(action.get("action_id", ""))
		if action_id.is_empty() or actions.has(action_id):
			return {"ok": false}
		actions[action_id] = action.duplicate(true)
	for required_action: StringName in COMBO_ACTION_IDS + [HEAVY_ACTION_ID]:
		if not actions.has(str(required_action)):
			return {"ok": false}

	var payloads: Dictionary = {}
	for payload_value: Variant in profile.get("payloads", []):
		if not payload_value is Dictionary:
			return {"ok": false}
		var payload: Dictionary = payload_value
		payloads[str(payload.get("payload_id", ""))] = payload.duplicate(true)
	var cues: Dictionary = {}
	for cue_value: Variant in profile.get("cues", []):
		if not cue_value is Dictionary:
			return {"ok": false}
		var cue: Dictionary = cue_value
		cues[str(cue.get("cue_id", ""))] = cue.duplicate(true)

	for action_value: Variant in actions.values():
		var action: Dictionary = action_value
		if not payloads.has(str(action.get("payload_id", ""))):
			return {"ok": false}
		if not cues.has(str(action.get("cue_id", ""))):
			return {"ok": false}
	return {"ok": true, "actions": actions, "payloads": payloads, "cues": cues}


func _matches_frozen_m1_profile(indexes: Dictionary) -> bool:
	var actions: Dictionary = indexes.get("actions", {})
	var payloads: Dictionary = indexes.get("payloads", {})
	var cues: Dictionary = indexes.get("cues", {})
	if (
		actions.size() != FROZEN_M1_ACTIONS.size()
		or payloads.size() != FROZEN_M1_ACTIONS.size()
		or cues.size() != FROZEN_M1_ACTIONS.size()
	):
		return false

	for action_id_value: Variant in FROZEN_M1_ACTIONS.keys():
		var action_id := str(action_id_value)
		var expected: Dictionary = FROZEN_M1_ACTIONS[action_id]
		var action_value: Variant = actions.get(action_id)
		if not action_value is Dictionary:
			return false
		var action: Dictionary = action_value
		if not _matches_frozen_action(action, expected):
			return false

		var payload_id := str(expected["payload_id"])
		var payload_value: Variant = payloads.get(payload_id)
		if not payload_value is Dictionary:
			return false
		var payload: Dictionary = payload_value
		if not _matches_frozen_payload(payload, expected):
			return false

		var cue_id := str(expected["cue_id"])
		var cue_value: Variant = cues.get(cue_id)
		if not cue_value is Dictionary or not _matches_frozen_cue(cue_value as Dictionary, expected):
			return false
	return true


func _matches_frozen_action(action: Dictionary, expected: Dictionary) -> bool:
	const EXACT_ACTION_FIELDS: Array[String] = [
		"action_id",
		"semantic_action",
		"activation_mode",
		"windup_frames",
		"active_frames",
		"recovery_frames",
		"cancel_from_frame",
		"buffer_frames",
		"cooldown_frames",
		"movement_multiplier",
		"resource_costs",
		"payload_id",
		"cue_id",
	]
	if action.size() != EXACT_ACTION_FIELDS.size():
		return false
	for field: String in EXACT_ACTION_FIELDS:
		if not action.has(field):
			return false
	if (
		str(action["action_id"]) != str(expected["action_id"])
		or str(action["semantic_action"]) != str(expected["semantic_action"])
		or str(action["activation_mode"]) != str(expected["activation_mode"])
		or str(action["payload_id"]) != str(expected["payload_id"])
		or str(action["cue_id"]) != str(expected["cue_id"])
	):
		return false
	if not action["resource_costs"] is Dictionary or not (action["resource_costs"] as Dictionary).is_empty():
		return false
	for frame_field: String in [
		"windup_frames",
		"active_frames",
		"recovery_frames",
		"cancel_from_frame",
		"buffer_frames",
	]:
		if not _integer_matches_exactly(action[frame_field], int(expected[frame_field])):
			return false
	if not _integer_matches_exactly(action["cooldown_frames"], 0):
		return false
	return _number_matches_exactly(action["movement_multiplier"], float(expected["movement_multiplier"]))


func _matches_frozen_payload(payload: Dictionary, expected: Dictionary) -> bool:
	if (
		payload.size() != 3
		or str(payload.get("payload_id", "")) != str(expected["payload_id"])
		or str(payload.get("kind", "")) != "hitbox"
		or not payload.get("parameters") is Dictionary
	):
		return false
	var parameters: Dictionary = payload["parameters"]
	if (
		parameters.size() != 3
		or not parameters.has("damage_multiplier")
		or not parameters.has("knockback")
		or not parameters.has("tags")
	):
		return false
	return (
		_number_matches_exactly(parameters["damage_multiplier"], float(expected["damage_multiplier"]))
		and _number_matches_exactly(parameters["knockback"], float(expected["knockback"]))
		and _same_string_set(parameters["tags"], expected["tags"])
	)


func _matches_frozen_cue(cue: Dictionary, expected: Dictionary) -> bool:
	const CUE_FIELDS: Array[String] = ["cue_id", "animation_id", "vfx_id", "audio_id", "camera_id"]
	if cue.size() != CUE_FIELDS.size():
		return false
	for field: String in CUE_FIELDS:
		if str(cue.get(field, "")) != str(expected.get(field, "")):
			return false
	return true


func _valid_restore_snapshot(value: Dictionary) -> bool:
	if int(value.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return false
	if typeof(value.get("configured")) != TYPE_BOOL or not bool(value["configured"]):
		return false
	if str(value.get("profile_id", "")) != str(_profile_snapshot.get("id", "")):
		return false
	if int(value.get("profile_version", 0)) != int(_profile_snapshot.get("profile_version", 0)):
		return false
	if typeof(value.get("combo_step")) != TYPE_INT or int(value["combo_step"]) not in range(COMBO_ACTION_IDS.size()):
		return false
	if typeof(value.get("active_token")) != TYPE_INT or int(value["active_token"]) != 0:
		return false
	if str(value.get("active_phase", "")) != "READY":
		return false
	if not value.get("active_plan") is Dictionary or not value.get("modifier_snapshot") is Dictionary:
		return false
	if not (value["active_plan"] as Dictionary).is_empty() or not (value["modifier_snapshot"] as Dictionary).is_empty():
		return false
	if not value.get("adapter") is Dictionary:
		return false
	var adapter: Dictionary = value["adapter"]
	if (
		typeof(adapter.get("combo_index")) != TYPE_INT
		or int(adapter["combo_index"]) != int(value["combo_step"])
		or typeof(adapter.get("attacking")) != TYPE_BOOL
		or bool(adapter["attacking"])
		or typeof(adapter.get("active")) != TYPE_BOOL
		or bool(adapter["active"])
		or not adapter.get("current_attack") is Dictionary
		or not (adapter["current_attack"] as Dictionary).is_empty()
	):
		return false
	return _dictionary_numbers_are_finite(value)


func _adapter_snapshot() -> Dictionary:
	if _adapter == null:
		return {}
	return {
		"combo_index": int(_adapter.get("_combo_index")),
		"attacking": bool(_adapter.get("_attacking")),
		"active": bool(_adapter.get("_active")),
		"current_attack": (_adapter.get("_current_attack") as Dictionary).duplicate(true),
	}


func _restore_adapter_snapshot(adapter_snapshot: Dictionary) -> void:
	_adapter.call("cancel_attack")
	_adapter.set("_combo_index", int(adapter_snapshot.get("combo_index", 0)))
	_adapter.set("_attacking", bool(adapter_snapshot.get("attacking", false)))
	_adapter.set("_active", false)
	_adapter.set("_current_attack", (adapter_snapshot.get("current_attack", {}) as Dictionary).duplicate(true))


func _legacy_reward_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for field: String in LEGACY_REWARD_FIELDS:
		var value: Variant = _adapter.get(field)
		if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)):
			result[field] = float(value)
	return result


func _apply_legacy_reward_snapshot(rewards: Dictionary) -> void:
	for field: String in LEGACY_REWARD_FIELDS:
		if rewards.has(field):
			_adapter.set(field, float(rewards[field]))


func _timing_multiplier(modifiers: Dictionary) -> float:
	var adapter_speed := float(_adapter.get("attack_speed")) if _adapter != null else 1.0
	return maxf(0.2, adapter_speed * float(modifiers.get("weapon.attack_speed", 1.0)))


func _scaled_frames(value: Variant, timing_multiplier: float) -> int:
	return maxi(1, ceili(float(value) / maxf(0.2, timing_multiplier)))


func _scaled_action_frames(action_id: StringName, field: StringName, timing_multiplier: float) -> int:
	var frozen_value: Variant = FROZEN_M1_ACTIONS.get(str(action_id), {})
	if not frozen_value is Dictionary:
		return 0
	var seconds_value: Variant = (frozen_value as Dictionary).get("timing_seconds", {})
	if not seconds_value is Dictionary or not (seconds_value as Dictionary).has(str(field)):
		return 0
	return maxi(
		1,
		ceili(
			float((seconds_value as Dictionary)[str(field)])
			* (1.0 / maxf(0.2, timing_multiplier))
			* Engine.physics_ticks_per_second
		)
	)


func _profile_attack_definition(plan: Dictionary) -> Dictionary:
	var payloads_value: Variant = plan.get("payloads", [])
	if not payloads_value is Array or (payloads_value as Array).size() != 1:
		return {}
	var payload_value: Variant = (payloads_value as Array)[0]
	if not payload_value is Dictionary or not (payload_value as Dictionary).get("parameters") is Dictionary:
		return {}
	var parameters: Dictionary = (payload_value as Dictionary)["parameters"]
	var tags_value: Variant = parameters.get("tags", [])
	if not tags_value is Array:
		return {}
	return {
		"heavy": bool(plan.get("heavy", false)),
		"finisher": (tags_value as Array).has("attack:finisher"),
		"multiplier": float(parameters.get("damage_multiplier", 0.0)),
		"knockback": float(parameters.get("knockback", 0.0)),
		"tags": (tags_value as Array).duplicate(),
	}


func _matches_active_action(plan: Dictionary, token: int) -> bool:
	return (
		token > 0
		and token == _active_token
		and str(plan.get("action_id", "")) == str(_active_plan.get("action_id", ""))
	)


func _clear_active_action() -> void:
	_active_token = 0
	_active_phase = &"READY"
	_active_plan.clear()
	_modifier_snapshot.clear()


func _is_configured() -> bool:
	return (
		_owner != null
		and is_instance_valid(_owner)
		and _adapter != null
		and is_instance_valid(_adapter)
		and _modifier_state != null
		and not _profile_snapshot.is_empty()
	)


func _copy_indexed(index: Dictionary, id: StringName) -> Dictionary:
	var value: Variant = index.get(str(id), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _has_methods(value: Object, methods: Array[StringName]) -> bool:
	for method_name: StringName in methods:
		if not value.has_method(method_name):
			return false
	return true


func _dictionary_numbers_are_finite(value: Variant) -> bool:
	match typeof(value):
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for child: Variant in value as Array:
				if not _dictionary_numbers_are_finite(child):
					return false
		TYPE_DICTIONARY:
			for child: Variant in (value as Dictionary).values():
				if not _dictionary_numbers_are_finite(child):
					return false
	return true


func _number_matches_exactly(value: Variant, expected: float) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) == expected
	)


func _integer_matches_exactly(value: Variant, expected: int) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and int(value) == expected
	)


func _same_string_set(actual_value: Variant, expected_value: Variant) -> bool:
	if not actual_value is Array or not expected_value is Array:
		return false
	var actual: Array[String] = []
	var expected: Array[String] = []
	for value: Variant in actual_value as Array:
		actual.append(str(value))
	for value: Variant in expected_value as Array:
		expected.append(str(value))
	actual.sort()
	expected.sort()
	return actual == expected


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
