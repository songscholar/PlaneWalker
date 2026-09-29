class_name BowWeaponRuntime
extends "res://scripts/combat/weapons/weapon_runtime.gd"

const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
const PROFILE_ID := "bow_candidate_v1"
const WEAPON_ID := &"bow"
const ACTION_ID := &"candidate_draw"
const RESOURCE_ID := &"charge"
const REWARD_ID := &"full_charge_energy"
const MINIMUM_CHARGE_FRAMES := 9
const MAXIMUM_CHARGE_FRAMES := 54
const CANDIDATE_COOLDOWN_FRAMES := 21
const FULL_CHARGE_RATIO := 0.98
const FULL_CHARGE_PIERCE := 1
const FULL_CHARGE_ENERGY := 6.0
const FROZEN_ACTION := {
	"action_id": "candidate_draw",
	"semantic_action": "weapon_primary",
	"activation_mode": "release",
	"hold_threshold_frames": MINIMUM_CHARGE_FRAMES,
	"maximum_hold_frames": MAXIMUM_CHARGE_FRAMES,
	"windup_frames": 1,
	"active_frames": 1,
	"recovery_frames": CANDIDATE_COOLDOWN_FRAMES,
	"cancel_from_frame": null,
	"buffer_frames": 8,
	"movement_multiplier": 1.0,
	"payload_id": "bow_candidate_arrow",
	"cue_id": "bow_candidate_release",
}
const FROZEN_RESOURCE := {
	"resource_id": "charge",
	"minimum": 0.0,
	"maximum": 54.0,
	"initial": 0.0,
	"regen_per_second": 0.0,
}
const FROZEN_PAYLOAD := {
	"payload_id": "bow_candidate_arrow",
	"kind": "projectile",
	"parameters": {
		"damage_multiplier": 0.75,
		"maximum_damage_multiplier": 1.75,
		"speed": 440.0,
		"maximum_speed": 680.0,
		"full_charge_ratio": FULL_CHARGE_RATIO,
		"full_charge_energy": FULL_CHARGE_ENERGY,
	},
}
const FROZEN_CUE := {
	"cue_id": "bow_candidate_release",
	"animation_id": "bow_release",
	"vfx_id": "bow_arrow_trail",
	"audio_id": "bow_release",
	"camera_id": "impact_light",
}
const FROZEN_CAPABILITIES: Array[String] = [
	"weapon.attack_speed",
	"weapon.charge_rate",
	"weapon.damage",
	"weapon.full_charge_damage",
	"weapon.pierce",
]
const REQUIRED_ADAPTER_METHODS: Array[StringName] = [
	&"begin_profile_shot",
	&"release_profile_shot",
	&"is_profile_action_active",
	&"cancel_profile_shot",
	&"finish_profile_shot",
	&"reset_runtime_state",
]
const REQUIRED_MODIFIER_METHODS: Array[StringName] = [
	&"apply",
	&"freeze_for_action",
	&"snapshot",
	&"reset",
]
const ADAPTER_NUMERIC_FIELDS: Array[String] = [
	"base_attack",
	"attack_speed",
]

var _owner: Node
var _adapter: Node
var _modifier_state: RefCounted
var _profile_snapshot: Dictionary = {}
var _action: Dictionary = {}
var _payload: Dictionary = {}
var _cue: Dictionary = {}
var _capabilities: PackedStringArray = PackedStringArray()

var _active_token: int = 0
var _active_phase: StringName = &"READY"
var _active_plan: Dictionary = {}
var _modifier_snapshot: Dictionary = {}
var _reward_eligible_tokens: Array[int] = []
var _reward_claimed_tokens: Array[int] = []


func weapon_id() -> StringName:
	return WEAPON_ID


func configure(owner: Node, profile: Variant, modifiers: Variant) -> bool:
	if owner == null or not is_instance_valid(owner):
		return false
	if not profile is RefCounted or not (profile as RefCounted).has_method("snapshot"):
		return false
	if not modifiers is RefCounted or not _has_methods(modifiers as RefCounted, REQUIRED_MODIFIER_METHODS):
		return false

	var adapter := owner.get_node_or_null("BowWeapon")
	if adapter == null or not _has_methods(adapter, REQUIRED_ADAPTER_METHODS):
		return false
	var adapter_values := _adapter_values(adapter)
	if adapter_values.is_empty():
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

	var indexed := _index_candidate_profile(next_profile)
	if not bool(indexed.get("ok", false)):
		return false
	if not _matches_frozen_candidate_profile(next_profile, indexed):
		return false
	var frozen_value: Variant = (modifiers as RefCounted).call("freeze_for_action")
	if not frozen_value is Dictionary or not _variant_numbers_are_finite(frozen_value):
		return false

	_owner = owner
	_adapter = adapter
	_modifier_state = modifiers as RefCounted
	_profile_snapshot = next_profile
	_action = (indexed["action"] as Dictionary).duplicate(true)
	_payload = (indexed["payload"] as Dictionary).duplicate(true)
	_cue = (indexed["cue"] as Dictionary).duplicate(true)
	_capabilities = PackedStringArray(next_profile.get("capabilities", []))
	reset_runtime_state(&"configured")
	return true


func capabilities() -> PackedStringArray:
	return _capabilities.duplicate()


func plan_intent(intent: Dictionary, context: Dictionary) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if StringName(str(intent.get("id", ""))) != &"weapon_primary":
		return _failure(&"UNSUPPORTED_INTENT")
	var direction_result := _normalized_direction(context.get("aim_direction"))
	if not bool(direction_result.get("ok", false)):
		return _failure(&"INVALID_AIM_DIRECTION")
	var modifier_value: Variant = _modifier_state.call("freeze_for_action")
	if not modifier_value is Dictionary or not _variant_numbers_are_finite(modifier_value):
		return _failure(&"INVALID_MODIFIER_SNAPSHOT")
	var frozen_modifiers := (modifier_value as Dictionary).duplicate(true)
	var adapter_snapshot := _adapter_values(_adapter)
	if adapter_snapshot.is_empty():
		return _failure(&"INVALID_ADAPTER_STATE")
	var edge := StringName(str(intent.get("edge", "")))
	if edge == &"pressed":
		var skeleton := _build_hold_skeleton(
			direction_result["direction"],
			adapter_snapshot,
			frozen_modifiers
		)
		var skeleton_validation: Dictionary = WeaponActionContractScript.validate_plan(skeleton, WEAPON_ID)
		if not bool(skeleton_validation.get("ok", false)):
			return skeleton_validation
		return {
			"ok": true,
			"code": &"OK",
			"plan": skeleton.duplicate(true),
			"context": {
				"hold_integration": "coordinator_same_token_press_hold_release",
			},
		}
	if edge != &"released":
		return _failure(&"UNSUPPORTED_EDGE")
	if typeof(intent.get("held_frames")) != TYPE_INT or int(intent["held_frames"]) < 0:
		return _failure(&"INVALID_HELD_FRAMES")
	return _build_final_plan_result(
		int(intent["held_frames"]),
		direction_result["direction"],
		adapter_snapshot,
		frozen_modifiers
	)


func commit_action(plan: Dictionary, token: int) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if token <= 0:
		return _failure(&"INVALID_TOKEN")
	if _active_token > 0 or bool(_adapter.call("is_profile_action_active")):
		return _failure(&"ACTION_IN_PROGRESS")
	var is_hold_skeleton := _is_hold_skeleton(plan)
	var validation := (
		_validate_hold_skeleton(plan)
		if is_hold_skeleton
		else _validate_final_plan(plan)
	)
	if not bool(validation.get("ok", false)):
		return validation
	if is_hold_skeleton:
		_active_token = token
		_active_phase = &"HOLD"
		_active_plan = plan.duplicate(true)
		_modifier_snapshot = (plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true)
		return {
			"ok": true,
			"code": &"OK",
			"context": {
				"action_id": str(ACTION_ID),
				"minimum_hold_frames": MINIMUM_CHARGE_FRAMES,
				"maximum_hold_frames": MAXIMUM_CHARGE_FRAMES,
			},
		}

	var staged := _stage_profile_shot(plan, token)
	if not bool(staged.get("ok", false)):
		return staged

	_active_token = token
	_active_phase = &"WINDUP"
	_active_plan = plan.duplicate(true)
	_modifier_snapshot = (plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true)
	return {
		"ok": true,
		"code": &"OK",
		"context": {
			"action_id": str(ACTION_ID),
			"held_frames": int((_active_plan["hold"] as Dictionary)["raw_frames"]),
			"charge_ratio": float((_active_plan["hold"] as Dictionary)["charge_ratio"]),
			"full_charge": bool(_payload_parameters_from_plan(_active_plan).get("full_charge", false)),
		},
	}


func release_hold(plan: Dictionary, token: int, held_frames: int) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if (
		token <= 0
		or token != _active_token
		or _active_phase != &"HOLD"
		or plan != _active_plan
		or not _is_hold_skeleton(plan)
	):
		return _failure(&"STALE_HOLD_RELEASE")
	if held_frames < MINIMUM_CHARGE_FRAMES:
		return _failure(&"UNDERCHARGED", {
			"held_frames": held_frames,
			"minimum_frames": MINIMUM_CHARGE_FRAMES,
		})
	var direction_result := _normalized_direction(plan.get("aim_direction_snapshot"))
	if not bool(direction_result.get("ok", false)):
		return _failure(&"INVALID_AIM_DIRECTION")
	var finalized_result := _build_final_plan_result(
		held_frames,
		direction_result["direction"],
		(plan["adapter_snapshot"] as Dictionary).duplicate(true),
		(plan["modifier_snapshot"] as Dictionary).duplicate(true)
	)
	if not bool(finalized_result.get("ok", false)):
		return finalized_result
	var finalized_plan: Dictionary = finalized_result["plan"]
	var finalized_validation := _validate_final_plan(finalized_plan)
	if not bool(finalized_validation.get("ok", false)):
		return finalized_validation
	var staged := _stage_profile_shot(finalized_plan, token)
	if not bool(staged.get("ok", false)):
		return staged

	_active_plan = finalized_plan.duplicate(true)
	_active_phase = &"WINDUP"
	_modifier_snapshot = (finalized_plan["modifier_snapshot"] as Dictionary).duplicate(true)
	return {
		"ok": true,
		"code": &"OK",
		"finalized_plan": finalized_plan.duplicate(true),
		"context": (finalized_result.get("context", {}) as Dictionary).duplicate(true),
	}


func on_phase_enter(plan: Dictionary, phase: StringName, token: int) -> Array[Dictionary]:
	if not _matches_active_action(plan, token):
		return []
	match phase:
		&"HOLD":
			if _active_phase != &"HOLD":
				return []
		&"WINDUP":
			if _active_phase != &"WINDUP":
				return []
		&"ACTIVE":
			if _active_phase != &"WINDUP":
				return []
			if not bool(_adapter.call("release_profile_shot")):
				return [{"type": "phase_failed", "reason": "payload_activation_failed"}]
			_active_phase = &"ACTIVE"
			var parameters := _payload_parameters_from_plan(_active_plan)
			if bool(parameters.get("full_charge", false)) and float(parameters.get("time_energy_restore", 0.0)) > 0.0:
				_append_unique_sorted(_reward_eligible_tokens, token)
			return [
				{
					"type": "payload_released",
					"weapon_id": str(WEAPON_ID),
					"action_id": str(ACTION_ID),
					"descriptor_id": str((_active_plan["payloads"] as Array)[0]["descriptor_id"]),
					"token": token,
					"payload": _profile_shot_definition(_active_plan, token),
				},
				{
					"type": "cue_requested",
					"weapon_id": str(WEAPON_ID),
					"action_id": str(ACTION_ID),
					"cue": (_active_plan["cue"] as Dictionary).duplicate(true),
					"token": token,
				},
			]
		&"RECOVERY":
			if _active_phase not in [&"WINDUP", &"ACTIVE"]:
				return []
			_active_phase = &"RECOVERY"
	return []


func cancel_action(token: int, _reason: StringName) -> void:
	if token <= 0 or token != _active_token:
		return
	_adapter.call("cancel_profile_shot")
	_clear_active_action()


func finish_action(token: int) -> void:
	if token <= 0 or token != _active_token:
		return
	_adapter.call("finish_profile_shot")
	_clear_active_action()


func apply_modifier(effect_id: StringName, value: Variant) -> bool:
	if _modifier_state == null or not _capabilities.has(str(effect_id)):
		return false
	return bool(_modifier_state.call("apply", effect_id, value))


func claim_action_reward(token: int, reward_id: StringName) -> Dictionary:
	if reward_id != REWARD_ID:
		return _failure(&"UNSUPPORTED_REWARD", {"reward_id": str(reward_id)})
	if token <= 0 or not _reward_eligible_tokens.has(token):
		return _failure(&"REWARD_NOT_ELIGIBLE", {"token": token})
	if _reward_claimed_tokens.has(token):
		return _failure(&"REWARD_ALREADY_CLAIMED", {"token": token})
	_append_unique_sorted(_reward_claimed_tokens, token)
	return {
		"ok": true,
		"code": &"OK",
		"reward_id": REWARD_ID,
		"token": token,
		"amount": FULL_CHARGE_ENERGY,
	}


func reset_runtime_state(_reason: StringName) -> void:
	if _adapter != null:
		_adapter.call("reset_runtime_state")
	_clear_active_action()
	_reward_eligible_tokens.clear()
	_reward_claimed_tokens.clear()


func snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"configured": _is_configured(),
		"profile_id": str(_profile_snapshot.get("id", "")),
		"profile_version": int(_profile_snapshot.get("profile_version", 0)),
		"active_token": _active_token,
		"active_phase": str(_active_phase),
		"active_plan": _active_plan.duplicate(true),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
		"adapter_active": bool(_adapter.call("is_profile_action_active")) if _adapter != null else false,
		"reward_eligible_tokens": _reward_eligible_tokens.duplicate(),
		"reward_claimed_tokens": _reward_claimed_tokens.duplicate(),
	}


func restore_snapshot(runtime_snapshot: Dictionary) -> bool:
	if not _is_configured() or not _valid_restore_snapshot(runtime_snapshot):
		return false
	_adapter.call("cancel_profile_shot")
	_clear_active_action()
	_active_token = int(runtime_snapshot["active_token"])
	_active_phase = StringName(str(runtime_snapshot["active_phase"]))
	_active_plan = (runtime_snapshot["active_plan"] as Dictionary).duplicate(true)
	_modifier_snapshot = (runtime_snapshot["modifier_snapshot"] as Dictionary).duplicate(true)
	_reward_eligible_tokens = _int_array(runtime_snapshot["reward_eligible_tokens"])
	_reward_claimed_tokens = _int_array(runtime_snapshot["reward_claimed_tokens"])
	return true


func presentation_snapshot() -> Dictionary:
	var parameters := _payload_parameters_from_plan(_active_plan)
	var hold_value: Variant = _active_plan.get("hold", {})
	var hold := (hold_value as Dictionary).duplicate(true) if hold_value is Dictionary else {}
	var facing := Vector2.RIGHT
	if _adapter is Node2D:
		facing = Vector2.RIGHT.rotated((_adapter as Node2D).global_rotation)
	return {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(_active_plan.get("action_id", "")),
		"phase": str(_active_phase),
		"token": _active_token,
		"charge_frames": float(hold.get("effective_frames", 0.0)),
		"maximum_charge_frames": MAXIMUM_CHARGE_FRAMES,
		"charge_ratio": float(hold.get("charge_ratio", 0.0)),
		"full_charge": bool(parameters.get("full_charge", false)),
		"cooldown_frames": _profile_cooldown_frames(),
		"facing": facing,
		"cue_id": str((_active_plan.get("cue", {}) as Dictionary).get("cue_id", "")),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
	}


func _build_hold_skeleton(
	direction: Vector2,
	adapter_snapshot: Dictionary,
	modifier_snapshot: Dictionary
) -> Dictionary:
	var timing_multiplier := _timing_multiplier(adapter_snapshot, modifier_snapshot)
	return {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(ACTION_ID),
		"profile_id": str(_profile_snapshot["id"]),
		"profile_version": int(_profile_snapshot["profile_version"]),
		"semantic_action": "weapon_primary",
		"activation_mode": "release",
		"buffer_frames": int(_action.get("buffer_frames", 8)),
		"cooldown_frames": _profile_cooldown_frames(),
		"aim_direction_snapshot": direction,
		"modifier_snapshot": modifier_snapshot.duplicate(true),
		"adapter_snapshot": adapter_snapshot.duplicate(true),
		"cue": _cue.duplicate(true),
		"phases": [
			{
				"phase": "HOLD",
				"duration_frames": MAXIMUM_CHARGE_FRAMES,
				"minimum_hold_frames": MINIMUM_CHARGE_FRAMES,
				"movement_multiplier": float(_action["movement_multiplier"]),
			},
			{
				"phase": "WINDUP",
				"duration_frames": _scaled_frames(int(_action["windup_frames"]), timing_multiplier),
				"movement_multiplier": float(_action["movement_multiplier"]),
			},
			{
				"phase": "ACTIVE",
				"duration_frames": _scaled_frames(int(_action["active_frames"]), timing_multiplier),
				"movement_multiplier": float(_action["movement_multiplier"]),
			},
			{
				"phase": "RECOVERY",
				"duration_frames": _scaled_frames(_profile_cooldown_frames(), timing_multiplier),
				"movement_multiplier": float(_action["movement_multiplier"]),
			},
		],
		"payloads": [],
	}


func _build_final_plan_result(
	raw_frames: int,
	direction: Vector2,
	adapter_snapshot: Dictionary,
	modifier_snapshot: Dictionary
) -> Dictionary:
	if raw_frames < 0:
		return _failure(&"INVALID_HELD_FRAMES")
	if not _valid_frozen_adapter_values(adapter_snapshot) or not _variant_numbers_are_finite(modifier_snapshot):
		return _failure(&"INVALID_FROZEN_STATE")
	var direction_result := _normalized_direction(direction)
	if not bool(direction_result.get("ok", false)):
		return _failure(&"INVALID_AIM_DIRECTION")
	var charge_multiplier := _charge_multiplier(adapter_snapshot, modifier_snapshot)
	var effective_frames := clampf(float(raw_frames) * charge_multiplier, 0.0, float(MAXIMUM_CHARGE_FRAMES))
	if effective_frames < float(MINIMUM_CHARGE_FRAMES):
		return _failure(&"UNDERCHARGED", {
			"held_frames": raw_frames,
			"effective_frames": effective_frames,
			"minimum_frames": MINIMUM_CHARGE_FRAMES,
		})
	var charge_ratio := clampf(effective_frames / float(MAXIMUM_CHARGE_FRAMES), 0.0, 1.0)
	var full_charge := charge_ratio >= FULL_CHARGE_RATIO
	var timing_multiplier := _timing_multiplier(adapter_snapshot, modifier_snapshot)
	var parameters := _payload_parameters(
		adapter_snapshot,
		modifier_snapshot,
		charge_ratio,
		full_charge,
		direction_result["direction"]
	)
	if parameters.is_empty():
		return _failure(&"PAYLOAD_PROFILE_INVALID")
	var plan := {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(ACTION_ID),
		"profile_id": str(_profile_snapshot["id"]),
		"profile_version": int(_profile_snapshot["profile_version"]),
		"semantic_action": "weapon_primary",
		"activation_mode": "release",
		"buffer_frames": int(_action.get("buffer_frames", 8)),
		"cooldown_frames": _profile_cooldown_frames(),
		"hold": {
			"resource_id": str(RESOURCE_ID),
			"raw_frames": raw_frames,
			"effective_frames": effective_frames,
			"minimum_frames": MINIMUM_CHARGE_FRAMES,
			"maximum_frames": MAXIMUM_CHARGE_FRAMES,
			"charge_ratio": charge_ratio,
			"full_charge_ratio": FULL_CHARGE_RATIO,
		},
		"modifier_snapshot": modifier_snapshot.duplicate(true),
		"adapter_snapshot": adapter_snapshot.duplicate(true),
		"cue": _cue.duplicate(true),
		"phases": [
			{
				"phase": "WINDUP",
				"duration_frames": _scaled_frames(int(_action["windup_frames"]), timing_multiplier),
				"movement_multiplier": float(_action["movement_multiplier"]),
			},
			{
				"phase": "ACTIVE",
				"duration_frames": _scaled_frames(int(_action["active_frames"]), timing_multiplier),
				"movement_multiplier": float(_action["movement_multiplier"]),
			},
			{
				"phase": "RECOVERY",
				"duration_frames": _scaled_frames(_profile_cooldown_frames(), timing_multiplier),
				"movement_multiplier": float(_action["movement_multiplier"]),
			},
		],
		"payloads": [{
			"descriptor_id": str(_payload["payload_id"]),
			"kind": str(_payload["kind"]),
			"parameters": parameters,
		}],
	}
	var validation: Dictionary = WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	if not bool(validation.get("ok", false)):
		return validation
	return {
		"ok": true,
		"code": &"OK",
		"plan": plan.duplicate(true),
		"context": {
			"held_frames": raw_frames,
			"effective_frames": effective_frames,
			"charge_ratio": charge_ratio,
			"full_charge": full_charge,
			"hold_integration": "coordinator_same_token_press_hold_release",
		},
	}


func _stage_profile_shot(plan: Dictionary, token: int) -> Dictionary:
	var shot_definition := _profile_shot_definition(plan, token)
	if shot_definition.is_empty():
		return _failure(&"PAYLOAD_PROFILE_INVALID")
	var committed_value: Variant = _adapter.call("begin_profile_shot", shot_definition.duplicate(true))
	if not committed_value is Dictionary or (committed_value as Dictionary).is_empty():
		_adapter.call("cancel_profile_shot")
		return _failure(&"PAYLOAD_CONSTRUCTION_FAILED")
	if (committed_value as Dictionary) != shot_definition:
		_adapter.call("cancel_profile_shot")
		return _failure(&"PAYLOAD_PROFILE_MISMATCH")
	return {"ok": true, "code": &"OK", "context": {}}


func _is_hold_skeleton(plan: Dictionary) -> bool:
	var phases_value: Variant = plan.get("phases", [])
	return (
		phases_value is Array
		and not (phases_value as Array).is_empty()
		and (phases_value as Array)[0] is Dictionary
		and str(((phases_value as Array)[0] as Dictionary).get("phase", "")) == "HOLD"
	)


func _validate_hold_skeleton(plan: Dictionary) -> Dictionary:
	var contract_result: Dictionary = WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	if not bool(contract_result.get("ok", false)):
		return contract_result
	if (
		str(plan.get("profile_id", "")) != PROFILE_ID
		or int(plan.get("profile_version", 0)) != 1
		or StringName(str(plan.get("action_id", ""))) != ACTION_ID
		or str(plan.get("semantic_action", "")) != "weapon_primary"
		or str(plan.get("activation_mode", "")) != "release"
	):
		return _failure(&"ACTION_PROFILE_MISMATCH")
	if not plan.get("modifier_snapshot") is Dictionary or not plan.get("adapter_snapshot") is Dictionary:
		return _failure(&"INVALID_FROZEN_STATE")
	var direction_result := _normalized_direction(plan.get("aim_direction_snapshot"))
	if not bool(direction_result.get("ok", false)):
		return _failure(&"INVALID_AIM_DIRECTION")
	var expected := _build_hold_skeleton(
		direction_result["direction"],
		plan["adapter_snapshot"],
		plan["modifier_snapshot"]
	)
	if plan != expected:
		return _failure(&"HOLD_SKELETON_MISMATCH")
	return {"ok": true, "code": &"OK", "context": {}}


func _validate_final_plan(plan: Dictionary) -> Dictionary:
	var contract_result: Dictionary = WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	if not bool(contract_result.get("ok", false)):
		return contract_result
	if (
		str(plan.get("profile_id", "")) != PROFILE_ID
		or int(plan.get("profile_version", 0)) != 1
	):
		return _failure(&"PROFILE_MISMATCH")
	if (
		StringName(str(plan.get("action_id", ""))) != ACTION_ID
		or str(plan.get("semantic_action", "")) != "weapon_primary"
		or str(plan.get("activation_mode", "")) != "release"
		or int(plan.get("buffer_frames", -1)) != int(FROZEN_ACTION["buffer_frames"])
		or int(plan.get("cooldown_frames", -1)) != _profile_cooldown_frames()
	):
		return _failure(&"ACTION_PROFILE_MISMATCH")
	if not plan.get("hold") is Dictionary:
		return _failure(&"INVALID_HOLD_SNAPSHOT")
	if not plan.get("modifier_snapshot") is Dictionary:
		return _failure(&"INVALID_MODIFIER_SNAPSHOT")
	if not plan.get("adapter_snapshot") is Dictionary:
		return _failure(&"INVALID_ADAPTER_SNAPSHOT")
	if not plan.get("cue") is Dictionary or (plan["cue"] as Dictionary) != _cue:
		return _failure(&"CUE_PROFILE_MISMATCH")

	var hold: Dictionary = plan["hold"]
	var adapter_snapshot: Dictionary = plan["adapter_snapshot"]
	var modifier_snapshot: Dictionary = plan["modifier_snapshot"]
	if not _valid_frozen_adapter_values(adapter_snapshot) or not _variant_numbers_are_finite(modifier_snapshot):
		return _failure(&"INVALID_FROZEN_STATE")
	if (
		str(hold.get("resource_id", "")) != str(RESOURCE_ID)
		or typeof(hold.get("raw_frames")) != TYPE_INT
		or int(hold["raw_frames"]) < 0
		or int(hold.get("minimum_frames", -1)) != MINIMUM_CHARGE_FRAMES
		or int(hold.get("maximum_frames", -1)) != MAXIMUM_CHARGE_FRAMES
		or not _number_matches_exactly(hold.get("full_charge_ratio"), FULL_CHARGE_RATIO)
	):
		return _failure(&"INVALID_HOLD_SNAPSHOT")
	var expected_effective := clampf(
		float(int(hold["raw_frames"])) * _charge_multiplier(adapter_snapshot, modifier_snapshot),
		0.0,
		float(MAXIMUM_CHARGE_FRAMES)
	)
	if expected_effective < float(MINIMUM_CHARGE_FRAMES):
		return _failure(&"UNDERCHARGED")
	var expected_ratio := expected_effective / float(MAXIMUM_CHARGE_FRAMES)
	if (
		not _number_matches_exactly(hold.get("effective_frames"), expected_effective)
		or not _number_matches_exactly(hold.get("charge_ratio"), expected_ratio)
	):
		return _failure(&"HOLD_SNAPSHOT_MISMATCH")

	var direction_value: Variant = _payload_parameters_from_plan(plan).get("direction")
	var direction_result := _normalized_direction(direction_value)
	if not bool(direction_result.get("ok", false)) or direction_result["direction"] != direction_value:
		return _failure(&"INVALID_AIM_DIRECTION")
	var expected_parameters := _payload_parameters(
		adapter_snapshot,
		modifier_snapshot,
		expected_ratio,
		expected_ratio >= FULL_CHARGE_RATIO,
		direction_value
	)
	if expected_parameters.is_empty() or _payload_parameters_from_plan(plan) != expected_parameters:
		return _failure(&"PAYLOAD_PROFILE_MISMATCH")

	var timing_multiplier := _timing_multiplier(adapter_snapshot, modifier_snapshot)
	var expected_phases := [
		{
			"phase": "WINDUP",
			"duration_frames": _scaled_frames(int(FROZEN_ACTION["windup_frames"]), timing_multiplier),
			"movement_multiplier": float(FROZEN_ACTION["movement_multiplier"]),
		},
		{
			"phase": "ACTIVE",
			"duration_frames": _scaled_frames(int(FROZEN_ACTION["active_frames"]), timing_multiplier),
			"movement_multiplier": float(FROZEN_ACTION["movement_multiplier"]),
		},
		{
			"phase": "RECOVERY",
			"duration_frames": _scaled_frames(_profile_cooldown_frames(), timing_multiplier),
			"movement_multiplier": float(FROZEN_ACTION["movement_multiplier"]),
		},
	]
	if plan.get("phases") != expected_phases:
		return _failure(&"PHASE_PROFILE_MISMATCH")
	return {"ok": true, "code": &"OK", "context": {}}


func _profile_shot_definition(plan: Dictionary, token: int) -> Dictionary:
	if token <= 0:
		return {}
	var parameters := _payload_parameters_from_plan(plan)
	if parameters.is_empty():
		return {}
	return {
		"token": token,
		"source_action_id": str(ACTION_ID),
		"direction": parameters.get("direction", Vector2.ZERO),
		"base_attack": float(parameters.get("base_attack", 0.0)),
		"damage_multiplier": float(parameters.get("damage_multiplier", 0.0)),
		"damage": float(parameters.get("damage", 0.0)),
		"speed": float(parameters.get("speed", 0.0)),
		"pierce": int(parameters.get("pierce", 0)),
		"full_charge": bool(parameters.get("full_charge", false)),
		"time_energy_restore": float(parameters.get("time_energy_restore", 0.0)),
		"energy_reward_id": str(REWARD_ID),
		"energy_reward_once_per_action": bool(parameters.get("energy_reward_once_per_action", true)),
		"tags": (parameters.get("tags", []) as Array).duplicate(),
	}


func _payload_parameters(
	adapter_snapshot: Dictionary,
	modifier_snapshot: Dictionary,
	charge_ratio: float,
	full_charge: bool,
	direction: Vector2
) -> Dictionary:
	var profile_parameters_value: Variant = _payload.get("parameters", {})
	if not profile_parameters_value is Dictionary:
		return {}
	var profile_parameters: Dictionary = profile_parameters_value
	var minimum_damage := float(profile_parameters.get("damage_multiplier", NAN))
	var maximum_damage := float(profile_parameters.get("maximum_damage_multiplier", NAN))
	var minimum_speed := float(profile_parameters.get("speed", NAN))
	var maximum_speed := float(profile_parameters.get("maximum_speed", NAN))
	if not _variant_numbers_are_finite([
		minimum_damage,
		maximum_damage,
		minimum_speed,
		maximum_speed,
		charge_ratio,
	]):
		return {}
	var damage_multiplier := lerpf(minimum_damage, maximum_damage, charge_ratio)
	var full_charge_multiplier := (
		float(modifier_snapshot.get("weapon.full_charge_damage", 1.0))
		if full_charge
		else 1.0
	)
	var generic_damage_multiplier := float(modifier_snapshot.get("weapon.damage", 1.0))
	var generic_pierce := roundi(float(modifier_snapshot.get("weapon.pierce", 0.0)))
	var tags: Array[String] = ["weapon:bow"]
	if full_charge:
		tags.append("attack:full_charge")
	return {
		"direction": direction,
		"base_attack": float(adapter_snapshot["base_attack"]),
		"damage_multiplier": damage_multiplier,
		"damage": float(adapter_snapshot["base_attack"]) * damage_multiplier * full_charge_multiplier * generic_damage_multiplier,
		"speed": lerpf(minimum_speed, maximum_speed, charge_ratio),
		"pierce": generic_pierce + (FULL_CHARGE_PIERCE if full_charge else 0),
		"full_charge": full_charge,
		"time_energy_restore": FULL_CHARGE_ENERGY if full_charge else 0.0,
		"energy_reward_once_per_action": true,
		"tags": tags,
	}


func _payload_parameters_from_plan(plan: Dictionary) -> Dictionary:
	var payloads_value: Variant = plan.get("payloads", [])
	if not payloads_value is Array or (payloads_value as Array).size() != 1:
		return {}
	var payload_value: Variant = (payloads_value as Array)[0]
	if not payload_value is Dictionary:
		return {}
	var payload: Dictionary = payload_value
	if (
		str(payload.get("descriptor_id", "")) != str(FROZEN_PAYLOAD["payload_id"])
		or str(payload.get("kind", "")) != str(FROZEN_PAYLOAD["kind"])
		or not payload.get("parameters") is Dictionary
	):
		return {}
	return (payload["parameters"] as Dictionary).duplicate(true)


func _index_candidate_profile(profile: Dictionary) -> Dictionary:
	var actions_value: Variant = profile.get("actions", [])
	var resources_value: Variant = profile.get("resources", [])
	var payloads_value: Variant = profile.get("payloads", [])
	var cues_value: Variant = profile.get("cues", [])
	if (
		not actions_value is Array
		or (actions_value as Array).size() != 1
		or not resources_value is Array
		or (resources_value as Array).size() != 1
		or not payloads_value is Array
		or (payloads_value as Array).size() != 1
		or not cues_value is Array
		or (cues_value as Array).size() != 1
	):
		return {"ok": false}
	if (
		not (actions_value as Array)[0] is Dictionary
		or not (resources_value as Array)[0] is Dictionary
		or not (payloads_value as Array)[0] is Dictionary
		or not (cues_value as Array)[0] is Dictionary
	):
		return {"ok": false}
	return {
		"ok": true,
		"action": ((actions_value as Array)[0] as Dictionary).duplicate(true),
		"resource": ((resources_value as Array)[0] as Dictionary).duplicate(true),
		"payload": ((payloads_value as Array)[0] as Dictionary).duplicate(true),
		"cue": ((cues_value as Array)[0] as Dictionary).duplicate(true),
	}


func _matches_frozen_candidate_profile(profile: Dictionary, indexed: Dictionary) -> bool:
	if not _same_string_set(profile.get("capabilities", []), FROZEN_CAPABILITIES):
		return false
	var action: Dictionary = indexed["action"]
	for field: String in [
		"action_id",
		"semantic_action",
		"activation_mode",
		"payload_id",
		"cue_id",
	]:
		if str(action.get(field, "")) != str(FROZEN_ACTION[field]):
			return false
	for field: String in [
		"hold_threshold_frames",
		"maximum_hold_frames",
		"windup_frames",
		"active_frames",
		"recovery_frames",
		"buffer_frames",
	]:
		if not _integer_matches_exactly(action.get(field), int(FROZEN_ACTION[field])):
			return false
	if action.get("cancel_from_frame") != null:
		return false
	if not _number_matches_exactly(action.get("movement_multiplier"), float(FROZEN_ACTION["movement_multiplier"])):
		return false
	if not action.get("resource_costs") is Dictionary or not (action["resource_costs"] as Dictionary).is_empty():
		return false
	if action.has("cooldown_frames") and not _integer_matches_exactly(action["cooldown_frames"], CANDIDATE_COOLDOWN_FRAMES):
		return false

	var resource: Dictionary = indexed["resource"]
	for field: String in ["resource_id"]:
		if str(resource.get(field, "")) != str(FROZEN_RESOURCE[field]):
			return false
	for field: String in ["minimum", "maximum", "initial", "regen_per_second"]:
		if not _number_matches_exactly(resource.get(field), float(FROZEN_RESOURCE[field])):
			return false

	var payload: Dictionary = indexed["payload"]
	if (
		str(payload.get("payload_id", "")) != str(FROZEN_PAYLOAD["payload_id"])
		or str(payload.get("kind", "")) != str(FROZEN_PAYLOAD["kind"])
		or not payload.get("parameters") is Dictionary
	):
		return false
	var parameters: Dictionary = payload["parameters"]
	var frozen_parameters: Dictionary = FROZEN_PAYLOAD["parameters"]
	if parameters.size() != frozen_parameters.size():
		return false
	for field: String in frozen_parameters.keys():
		if not _number_matches_exactly(parameters.get(field), float(frozen_parameters[field])):
			return false

	return indexed["cue"] == FROZEN_CUE


func _adapter_values(adapter: Node) -> Dictionary:
	var result: Dictionary = {}
	for field: String in ADAPTER_NUMERIC_FIELDS:
		var value: Variant = adapter.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return {}
		result[field] = float(value)
	return result if _valid_frozen_adapter_values(result) else {}


func _valid_frozen_adapter_values(value: Dictionary) -> bool:
	if value.size() != ADAPTER_NUMERIC_FIELDS.size():
		return false
	for field: String in ADAPTER_NUMERIC_FIELDS:
		if not value.has(field):
			return false
		if typeof(value[field]) != TYPE_FLOAT or not is_finite(float(value[field])):
			return false
	return (
		float(value["base_attack"]) >= 0.0
		and float(value["attack_speed"]) > 0.0
	)


func _charge_multiplier(adapter_snapshot: Dictionary, modifiers: Dictionary) -> float:
	return maxf(
		0.0,
		float(adapter_snapshot["attack_speed"])
		* float(modifiers.get("weapon.attack_speed", 1.0))
		* float(modifiers.get("weapon.charge_rate", 1.0))
	)


func _timing_multiplier(adapter_snapshot: Dictionary, modifiers: Dictionary) -> float:
	return maxf(
		0.2,
		float(adapter_snapshot["attack_speed"])
		* float(modifiers.get("weapon.attack_speed", 1.0))
	)


func _scaled_frames(frames: int, timing_multiplier: float) -> int:
	return maxi(1, ceili(float(frames) / maxf(0.2, timing_multiplier)))


func _profile_cooldown_frames() -> int:
	return int(_action.get("cooldown_frames", CANDIDATE_COOLDOWN_FRAMES))


func _normalized_direction(value: Variant) -> Dictionary:
	if not value is Vector2:
		return {"ok": false}
	var direction := value as Vector2
	if not is_finite(direction.x) or not is_finite(direction.y) or direction.length_squared() <= 0.001:
		return {"ok": false}
	return {"ok": true, "direction": direction.normalized()}


func _valid_restore_snapshot(value: Dictionary) -> bool:
	if int(value.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return false
	if typeof(value.get("configured")) != TYPE_BOOL or not bool(value["configured"]):
		return false
	if str(value.get("profile_id", "")) != PROFILE_ID or int(value.get("profile_version", 0)) != 1:
		return false
	if typeof(value.get("active_token")) != TYPE_INT or int(value["active_token"]) < 0:
		return false
	if not value.get("active_plan") is Dictionary:
		return false
	if not value.get("modifier_snapshot") is Dictionary:
		return false
	if typeof(value.get("adapter_active")) != TYPE_BOOL or bool(value["adapter_active"]):
		return false
	var active_token := int(value["active_token"])
	var active_phase := str(value.get("active_phase", ""))
	var active_plan: Dictionary = value["active_plan"]
	var modifier_snapshot: Dictionary = value["modifier_snapshot"]
	if active_token == 0:
		if active_phase != "READY" or not active_plan.is_empty() or not modifier_snapshot.is_empty():
			return false
	else:
		if active_phase != "HOLD" or active_plan.is_empty():
			return false
		if not bool(_validate_hold_skeleton(active_plan).get("ok", false)):
			return false
		if modifier_snapshot != active_plan.get("modifier_snapshot", {}):
			return false
	if not _valid_token_array(value.get("reward_eligible_tokens")):
		return false
	if not _valid_token_array(value.get("reward_claimed_tokens")):
		return false
	var eligible := _int_array(value["reward_eligible_tokens"])
	for token: int in _int_array(value["reward_claimed_tokens"]):
		if not eligible.has(token):
			return false
	return _variant_numbers_are_finite(value)


func _valid_token_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for token_value: Variant in value as Array:
		if typeof(token_value) != TYPE_INT or int(token_value) <= 0 or seen.has(int(token_value)):
			return false
		seen[int(token_value)] = true
	return true


func _int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is Array:
		for child: Variant in value as Array:
			result.append(int(child))
	result.sort()
	return result


func _append_unique_sorted(values: Array[int], value: int) -> void:
	if not values.has(value):
		values.append(value)
		values.sort()


func _matches_active_action(plan: Dictionary, token: int) -> bool:
	return (
		token > 0
		and token == _active_token
		and str(plan.get("action_id", "")) == str(_active_plan.get("action_id", ""))
		and plan == _active_plan
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


func _has_methods(value: Object, methods: Array[StringName]) -> bool:
	for method_name: StringName in methods:
		if not value.has_method(method_name):
			return false
	return true


func _same_string_set(left: Variant, right: Variant) -> bool:
	if not left is Array or not right is Array:
		return false
	var left_values: Array[String] = []
	var right_values: Array[String] = []
	for value: Variant in left as Array:
		left_values.append(str(value))
	for value: Variant in right as Array:
		right_values.append(str(value))
	left_values.sort()
	right_values.sort()
	return left_values == right_values


func _integer_matches_exactly(value: Variant, expected: int) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) == float(expected)
	)


func _number_matches_exactly(value: Variant, expected: float) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) == expected
	)


func _variant_numbers_are_finite(value: Variant) -> bool:
	match typeof(value):
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_VECTOR2:
			var vector := value as Vector2
			return is_finite(vector.x) and is_finite(vector.y)
		TYPE_ARRAY:
			for child: Variant in value as Array:
				if not _variant_numbers_are_finite(child):
					return false
		TYPE_DICTIONARY:
			for child: Variant in (value as Dictionary).values():
				if not _variant_numbers_are_finite(child):
					return false
	return true


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"context": context.duplicate(true),
	}
