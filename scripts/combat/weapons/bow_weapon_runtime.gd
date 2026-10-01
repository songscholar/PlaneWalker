class_name BowWeaponRuntime
extends "res://scripts/combat/weapons/weapon_runtime.gd"

const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")

const SNAPSHOT_SCHEMA_VERSION := 2
const PROFILE_ID := "bow_candidate_v1"
const WEAPON_ID := &"bow"
const MASTERY_IDS: Array[StringName] = [
	&"bow_full_charge_weakpoint",
	&"bow_full_charge_penetration",
]
const ACTION_ID := &"candidate_draw"
const RESOURCE_ID := &"charge"
const REWARD_ID := &"full_charge_energy"
const MINIMUM_CHARGE_FRAMES := 9
const MAXIMUM_CHARGE_FRAMES := 54
const CANDIDATE_COOLDOWN_FRAMES := 21
const FULL_CHARGE_RATIO := 0.98
const FULL_CHARGE_PIERCE := 1
const FULL_CHARGE_ENERGY := 6.0
const LAUNCH_PROFILE_ID := "bow_launch_v1"
const LAUNCH_PRIMARY_ACTION_ID := &"precision_draw"
const LAUNCH_FULL_CHARGE_FRAMES := 48
const LAUNCH_AUTO_RELEASE_FRAMES := 228
const LAUNCH_NORMAL_MOVE_MULTIPLIER := 0.40
const LAUNCH_FULL_MOVE_MULTIPLIER := 0.20
const FROZEN_LAUNCH_RUNTIME_DIGEST := "be695e379ae6ac4c670eacc37436141f935c1333cf1b927db525714c78815bd5"
const LAUNCH_RUNTIME_AUTHORITY_FIELDS: Array[String] = [
	"profile_version",
	"weapon_id",
	"runtime_kind",
	"actions",
	"resources",
	"capabilities",
	"payloads",
	"cues",
	"time_interactions",
	"boss_interactions",
]
const LAUNCH_ACTION_IDS := {
	"weapon_primary": "precision_draw",
	"weapon_secondary": "scatter_shot",
	"weapon_utility": "focus_step",
	"weapon_skill": "temporal_arrow",
	"weapon_ultimate": "starfall_arrow_rain",
}
const LAUNCH_PAYLOAD_IDS := {
	"precision_draw": "bow_launch_arrow",
	"scatter_shot": "bow_scatter",
	"focus_step": "bow_focus_step",
	"temporal_arrow": "bow_temporal_arrow",
	"starfall_arrow_rain": "bow_starfall",
}
const LAUNCH_ACTION_CONTRACTS := {
	"scatter_shot": {
		"semantic_action": "weapon_secondary",
		"activation_mode": "press",
		"windup_frames": 10,
		"active_frames": 3,
		"recovery_frames": 18,
		"cooldown_frames": 120,
		"resource_costs": {},
	},
	"focus_step": {
		"semantic_action": "weapon_utility",
		"activation_mode": "press",
		"windup_frames": 2,
		"active_frames": 4,
		"recovery_frames": 8,
		"cooldown_frames": 0,
		"resource_costs": {},
	},
	"temporal_arrow": {
		"semantic_action": "weapon_skill",
		"activation_mode": "press",
		"windup_frames": 12,
		"active_frames": 2,
		"recovery_frames": 16,
		"cooldown_frames": 300,
		"resource_costs": {"time_energy": 30.0},
	},
	"starfall_arrow_rain": {
		"semantic_action": "weapon_ultimate",
		"activation_mode": "release",
		"windup_frames": 20,
		"active_frames": 90,
		"recovery_frames": 25,
		"cooldown_frames": 900,
		"resource_costs": {"time_energy": 70.0},
	},
}
const LAUNCH_PRIMARY_TIERS: Array[Dictionary] = [
	{
		"tier_id": "quick",
		"minimum_frames": 0,
		"maximum_frames_exclusive": 15,
		"windup_frames": 6,
		"active_frames": 2,
		"recovery_frames": 10,
		"cancel_from_frame": 1,
		"damage_multiplier": 0.8,
		"speed_cells_per_second": 20.0,
		"range_cells": 12.0,
		"pierce": 0,
		"hit_width_cells": 0.3,
		"knockback_cells": 0.0,
		"critical_chance_bonus": 0.0,
	},
	{
		"tier_id": "power",
		"minimum_frames": 15,
		"maximum_frames_exclusive": 30,
		"windup_frames": 4,
		"active_frames": 2,
		"recovery_frames": 14,
		"cancel_from_frame": 2,
		"damage_multiplier": 1.8,
		"speed_cells_per_second": 24.0,
		"range_cells": 16.0,
		"pierce": 1,
		"hit_width_cells": 0.4,
		"knockback_cells": 1.0,
		"critical_chance_bonus": 0.0,
	},
	{
		"tier_id": "piercing",
		"minimum_frames": 30,
		"maximum_frames_exclusive": 48,
		"windup_frames": 4,
		"active_frames": 2,
		"recovery_frames": 16,
		"cancel_from_frame": 2,
		"damage_multiplier": 2.8,
		"speed_cells_per_second": 28.0,
		"range_cells": 20.0,
		"pierce": 3,
		"hit_width_cells": 0.5,
		"knockback_cells": 1.5,
		"critical_chance_bonus": 0.15,
	},
	{
		"tier_id": "full",
		"minimum_frames": 48,
		"maximum_frames_exclusive": 229,
		"windup_frames": 4,
		"active_frames": 2,
		"recovery_frames": 20,
		"cancel_from_frame": 2,
		"damage_multiplier": 4.5,
		"speed_cells_per_second": 32.0,
		"range_cells": 25.0,
		"pierce": -1,
		"hit_width_cells": 0.6,
		"knockback_cells": 2.0,
		"critical_chance_bonus": 0.25,
	},
]
const FROZEN_LAUNCH_CAPABILITIES: Array[String] = [
	"weapon.attack_speed",
	"weapon.charge_rate",
	"weapon.damage",
	"weapon.full_charge_damage",
	"weapon.pierce",
	"weapon.status_duration",
]
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
	&"runtime_snapshot",
	&"can_restore_runtime_snapshot",
	&"restore_runtime_snapshot",
	&"cancel_for_gameplay_rewind",
	&"restore_gameplay_rewind_snapshot_for_rollback",
	&"gameplay_rewind_committed_payload_guard",
]
const REQUIRED_LAUNCH_ADAPTER_METHODS: Array[StringName] = [
	&"begin_profile_action",
	&"release_profile_action",
	&"is_profile_action_active",
	&"cancel_profile_action",
	&"finish_profile_action",
	&"advance_profile_action_frames",
	&"reset_runtime_state",
	&"runtime_snapshot",
	&"can_restore_runtime_snapshot",
	&"restore_runtime_snapshot",
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
	"character_attack_scale",
	"crit_chance",
	"crit_multiplier",
]

var _owner: Node
var _adapter: Node
var _modifier_state: RefCounted
var _profile_snapshot: Dictionary = {}
var _action: Dictionary = {}
var _payload: Dictionary = {}
var _cue: Dictionary = {}
var _capabilities: PackedStringArray = PackedStringArray()
var _launch_actions_by_id: Dictionary = {}
var _launch_payloads_by_id: Dictionary = {}
var _launch_cues_by_id: Dictionary = {}
var _launch_time_interactions: Dictionary = {}
var _launch_boss_interactions: Dictionary = {}
var _committed_launch_definition: Dictionary = {}
var _live_launch_time_context: Dictionary = {}

var _active_token: int = 0
var _active_phase: StringName = &"READY"
var _active_plan: Dictionary = {}
var _modifier_snapshot: Dictionary = {}
var _reward_eligible_tokens: Array[int] = []
var _reward_claimed_tokens: Array[int] = []


func weapon_id() -> StringName:
	return WEAPON_ID


func mastery_ids() -> Array[StringName]:
	return MASTERY_IDS.duplicate()


func configure(owner: Node, profile: Variant, modifiers: Variant) -> bool:
	if owner == null or not is_instance_valid(owner):
		return false
	if not profile is RefCounted or not (profile as RefCounted).has_method("snapshot"):
		return false
	if not modifiers is RefCounted or not _has_methods(modifiers as RefCounted, REQUIRED_MODIFIER_METHODS):
		return false

	var profile_value: Variant = (profile as RefCounted).call("snapshot")
	if not profile_value is Dictionary:
		return false
	var next_profile := (profile_value as Dictionary).duplicate(true)
	if (
		str(next_profile.get("weapon_id", "")) != str(WEAPON_ID)
		or int(next_profile.get("profile_version", 0)) != 1
	):
		return false
	var profile_id := str(next_profile.get("id", ""))
	if profile_id not in [PROFILE_ID, LAUNCH_PROFILE_ID]:
		return false

	var adapter := owner.get_node_or_null("BowWeapon")
	var required_adapter_methods := (
		REQUIRED_LAUNCH_ADAPTER_METHODS
		if profile_id == LAUNCH_PROFILE_ID
		else REQUIRED_ADAPTER_METHODS
	)
	if adapter == null or not _has_methods(adapter, required_adapter_methods):
		return false
	var adapter_values := _adapter_values(adapter)
	if adapter_values.is_empty():
		return false
	var frozen_value: Variant = (modifiers as RefCounted).call("freeze_for_action")
	if not frozen_value is Dictionary or not _variant_numbers_are_finite(frozen_value):
		return false

	if profile_id == LAUNCH_PROFILE_ID:
		var launch_indexes := _index_launch_profile(next_profile)
		if not bool(launch_indexes.get("ok", false)):
			return false
		if not _matches_frozen_launch_profile(next_profile, launch_indexes):
			return false
		_owner = owner
		_adapter = adapter
		_modifier_state = modifiers as RefCounted
		_profile_snapshot = next_profile
		_action.clear()
		_payload.clear()
		_cue.clear()
		_launch_actions_by_id = (launch_indexes["actions"] as Dictionary).duplicate(true)
		_launch_payloads_by_id = (launch_indexes["payloads"] as Dictionary).duplicate(true)
		_launch_cues_by_id = (launch_indexes["cues"] as Dictionary).duplicate(true)
		_launch_time_interactions = (next_profile.get("time_interactions", {}) as Dictionary).duplicate(true)
		_launch_boss_interactions = (next_profile.get("boss_interactions", {}) as Dictionary).duplicate(true)
		_capabilities = PackedStringArray(next_profile.get("capabilities", []))
		reset_runtime_state(&"configured")
		return true

	var indexed := _index_candidate_profile(next_profile)
	if not bool(indexed.get("ok", false)):
		return false
	if not _matches_frozen_candidate_profile(next_profile, indexed):
		return false
	_owner = owner
	_adapter = adapter
	_modifier_state = modifiers as RefCounted
	_profile_snapshot = next_profile
	_action = (indexed["action"] as Dictionary).duplicate(true)
	_payload = (indexed["payload"] as Dictionary).duplicate(true)
	_cue = (indexed["cue"] as Dictionary).duplicate(true)
	_launch_actions_by_id.clear()
	_launch_payloads_by_id.clear()
	_launch_cues_by_id.clear()
	_launch_time_interactions.clear()
	_launch_boss_interactions.clear()
	_capabilities = PackedStringArray(next_profile.get("capabilities", []))
	reset_runtime_state(&"configured")
	return true


func capabilities() -> PackedStringArray:
	return _capabilities.duplicate()


func plan_intent(intent: Dictionary, context: Dictionary) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if _is_launch_profile():
		return _plan_launch_intent(intent, context)
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
	if _is_launch_profile():
		return _commit_launch_action(plan, token)
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
	if _is_launch_profile():
		return _release_launch_hold(plan, token, held_frames)
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


func update_hold_context(plan: Dictionary, token: int, context: Dictionary) -> bool:
	if not _matches_active_action(plan, token) or _active_phase != &"HOLD":
		return false
	if not _is_launch_profile():
		return true
	var normalized := _normalize_launch_time_context(context.get("time_interactions", {}))
	if not bool(normalized.get("ok", false)):
		return false
	var latest: Dictionary = normalized["context"]
	var press_context: Dictionary = plan.get("time_interactions_snapshot", {})
	# Charge timing is coordinator-owned and frozen when HOLD begins. Dynamic
	# hit-time interactions are refreshed through the same action token.
	latest["accelerate_active"] = bool(press_context.get("accelerate_active", false))
	_live_launch_time_context = latest.duplicate(true)
	return true


func on_phase_enter(plan: Dictionary, phase: StringName, token: int) -> Array[Dictionary]:
	if not _matches_active_action(plan, token):
		return []
	if _is_launch_profile():
		return _on_launch_phase_enter(phase, token)
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


func on_action_frame(
	plan: Dictionary,
	phase: StringName,
	token: int,
	_phase_frame: int
) -> Array[Dictionary]:
	if not _matches_active_action(plan, token):
		return []
	if (
		not _is_launch_profile()
		or phase != &"ACTIVE"
		or str(plan.get("action_id", "")) != "starfall_arrow_rain"
	):
		return []
	_adapter.call("advance_profile_action_frames", 1)
	return []


func advance_runtime_frame(_coordinator_frame: int) -> Array[Dictionary]:
	if (
		_active_token == 0
		and _is_launch_profile()
		and bool(_adapter.call("has_committed_starfall_schedule"))
	):
		_adapter.call("advance_profile_action_frames", 1)
	return []


func cancel_action(token: int, _reason: StringName) -> void:
	if token <= 0 or token != _active_token:
		return
	if _is_launch_profile():
		_adapter.call("cancel_profile_action")
	else:
		_adapter.call("cancel_profile_shot")
	_clear_active_action()


func cancel_for_gameplay_rewind(
	token: int,
	_reason: StringName,
	_hold_runtime_snapshot: Dictionary = {}
) -> bool:
	if token > 0 and token != _active_token:
		return false
	var guard := gameplay_rewind_committed_payload_guard()
	if not bool(_adapter.call("cancel_for_gameplay_rewind")):
		return false
	_clear_active_action()
	return gameplay_rewind_committed_payload_guard() == guard


func gameplay_rewind_snapshot() -> Dictionary:
	return snapshot()


func restore_gameplay_rewind_snapshot_for_rollback(runtime_snapshot: Dictionary) -> bool:
	if (
		not _is_configured()
		or not _runtime_snapshot_has_exact_fields(runtime_snapshot)
		or int(runtime_snapshot.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION
		or str(runtime_snapshot.get("profile_id", "")) != str(_profile_snapshot.get("id", ""))
		or int(runtime_snapshot.get("profile_version", 0))
			!= int(_profile_snapshot.get("profile_version", 0))
		or typeof(runtime_snapshot.get("active_token")) != TYPE_INT
		or not runtime_snapshot.get("active_plan") is Dictionary
		or not runtime_snapshot.get("modifier_snapshot") is Dictionary
		or not runtime_snapshot.get("adapter_snapshot") is Dictionary
	):
		return false
	var adapter_target := _bow_gameplay_adapter_snapshot(runtime_snapshot)
	if adapter_target.is_empty():
		return false
	var before := snapshot()
	if not bool(_adapter.call("restore_gameplay_rewind_snapshot_for_rollback", adapter_target)):
		return false
	_apply_snapshot_fields(runtime_snapshot)
	if snapshot() == runtime_snapshot:
		return true
	_adapter.call(
		"restore_gameplay_rewind_snapshot_for_rollback",
		_bow_gameplay_adapter_snapshot(before)
	)
	_apply_snapshot_fields(before)
	return false


func gameplay_rewind_committed_payload_guard() -> Dictionary:
	var adapter_value: Variant = _adapter.call("gameplay_rewind_committed_payload_guard")
	return {
		"adapter": (adapter_value as Dictionary).duplicate(true) if adapter_value is Dictionary else {},
		"reward_eligible_tokens": _reward_eligible_tokens.duplicate(),
		"reward_claimed_tokens": _reward_claimed_tokens.duplicate(),
	}


func _bow_gameplay_adapter_snapshot(runtime_snapshot: Dictionary) -> Dictionary:
	var adapter_value: Variant = runtime_snapshot.get("adapter_snapshot", {})
	if not adapter_value is Dictionary:
		return {}
	var adapter := adapter_value as Dictionary
	return {
		"profile_shot": (adapter.get("profile_shot", {}) as Dictionary).duplicate(true),
		"profile_shot_released": bool(adapter.get("profile_shot_released", false)),
		"profile_action": (adapter.get("profile_action", {}) as Dictionary).duplicate(true),
		"profile_action_released": bool(adapter.get("profile_action_released", false)),
		"shared_claims": (adapter.get("shared_claims", {}) as Dictionary).duplicate(true),
		"committed_payload_guard": gameplay_rewind_committed_payload_guard()["adapter"],
	}


func finish_action(token: int) -> void:
	if token <= 0 or token != _active_token:
		return
	if _is_launch_profile():
		_adapter.call("finish_profile_action")
	else:
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
	var adapter_snapshot: Dictionary = {}
	if _adapter != null:
		var adapter_value: Variant = _adapter.call("runtime_snapshot")
		if adapter_value is Dictionary:
			adapter_snapshot = (adapter_value as Dictionary).duplicate(true)
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"configured": _is_configured(),
		"profile_id": str(_profile_snapshot.get("id", "")),
		"profile_version": int(_profile_snapshot.get("profile_version", 0)),
		"active_token": _active_token,
		"active_phase": str(_active_phase),
		"active_plan": _active_plan.duplicate(true),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
		"committed_launch_definition": _committed_launch_definition.duplicate(true),
		"live_launch_time_context": _live_launch_time_context.duplicate(true),
		"adapter_active": bool(_adapter.call("is_profile_action_active")) if _adapter != null else false,
		"adapter_snapshot": adapter_snapshot,
		"reward_eligible_tokens": _reward_eligible_tokens.duplicate(),
		"reward_claimed_tokens": _reward_claimed_tokens.duplicate(),
	}


func restore_snapshot(runtime_snapshot: Dictionary) -> bool:
	if not _is_configured():
		return false
	if _is_launch_profile():
		return _restore_launch_snapshot(runtime_snapshot)
	if not _valid_restore_snapshot(runtime_snapshot):
		return false
	return _restore_snapshot_atomic(runtime_snapshot)


func _restore_snapshot_atomic(runtime_snapshot: Dictionary) -> bool:
	var current := snapshot()
	if current == runtime_snapshot:
		return true
	if not bool(_adapter.call("restore_runtime_snapshot", runtime_snapshot["adapter_snapshot"])):
		var adapter_after_value: Variant = _adapter.call("runtime_snapshot")
		if not adapter_after_value is Dictionary or (adapter_after_value as Dictionary) != current["adapter_snapshot"]:
			reset_runtime_state(&"adapter_restore_failed_closed")
		return false
	_apply_snapshot_fields(runtime_snapshot)
	if snapshot() == runtime_snapshot:
		return true
	var rollback_ok := bool(_adapter.call("restore_runtime_snapshot", current["adapter_snapshot"]))
	_apply_snapshot_fields(current)
	if rollback_ok and snapshot() == current:
		return false
	reset_runtime_state(&"restore_rollback_failed")
	return false


func _apply_snapshot_fields(runtime_snapshot: Dictionary) -> void:
	_active_token = int(runtime_snapshot["active_token"])
	_active_phase = StringName(str(runtime_snapshot["active_phase"]))
	_active_plan = (runtime_snapshot["active_plan"] as Dictionary).duplicate(true)
	_modifier_snapshot = (runtime_snapshot["modifier_snapshot"] as Dictionary).duplicate(true)
	_committed_launch_definition = (runtime_snapshot["committed_launch_definition"] as Dictionary).duplicate(true)
	_live_launch_time_context = (runtime_snapshot["live_launch_time_context"] as Dictionary).duplicate(true)
	_reward_eligible_tokens = _int_array(runtime_snapshot["reward_eligible_tokens"])
	_reward_claimed_tokens = _int_array(runtime_snapshot["reward_claimed_tokens"])


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
		"maximum_charge_frames": LAUNCH_FULL_CHARGE_FRAMES if _is_launch_profile() else MAXIMUM_CHARGE_FRAMES,
		"charge_ratio": float(hold.get("charge_ratio", 0.0)),
		"full_charge": bool(parameters.get("full_charge", false)),
		"cooldown_frames": int(_active_plan.get("cooldown_frames", 0)) if _is_launch_profile() else _profile_cooldown_frames(),
		"facing": facing,
		"cue_id": str((_active_plan.get("cue", {}) as Dictionary).get("cue_id", "")),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
	}


func _plan_launch_intent(intent: Dictionary, context: Dictionary) -> Dictionary:
	var semantic_id := str(intent.get("id", ""))
	var action_id := str(LAUNCH_ACTION_IDS.get(semantic_id, ""))
	if action_id.is_empty():
		return _failure(&"UNSUPPORTED_INTENT")
	var direction_result := _normalized_direction(context.get("aim_direction"))
	if not bool(direction_result.get("ok", false)):
		return _failure(&"INVALID_AIM_DIRECTION")
	var run_seed_value: Variant = context.get("run_seed", 0)
	if typeof(run_seed_value) != TYPE_INT:
		return _failure(&"INVALID_RUN_SEED")
	var target_point: Variant = context.get("target_point", direction_result["direction"] * 256.0)
	if not target_point is Vector2 or not _variant_numbers_are_finite(target_point):
		return _failure(&"INVALID_TARGET_POINT")
	var modifier_value: Variant = _modifier_state.call("freeze_for_action")
	if not modifier_value is Dictionary or not _variant_numbers_are_finite(modifier_value):
		return _failure(&"INVALID_MODIFIER_SNAPSHOT")
	var adapter_snapshot := _adapter_values(_adapter)
	if adapter_snapshot.is_empty():
		return _failure(&"INVALID_ADAPTER_STATE")
	var time_result := _normalize_launch_time_context(context.get("time_interactions", {}))
	if not bool(time_result.get("ok", false)):
		return time_result
	var frozen_context := {
		"direction": direction_result["direction"],
		"target_point": target_point,
		"run_seed": int(run_seed_value),
		"adapter_snapshot": adapter_snapshot,
		"modifier_snapshot": (modifier_value as Dictionary).duplicate(true),
		"time_interactions": (time_result["context"] as Dictionary).duplicate(true),
	}
	var edge := StringName(str(intent.get("edge", "")))
	if action_id == str(LAUNCH_PRIMARY_ACTION_ID):
		if edge == &"pressed":
			var skeleton := _build_launch_hold_skeleton(frozen_context)
			var skeleton_validation := _validate_launch_plan(skeleton)
			if not bool(skeleton_validation.get("ok", false)):
				return skeleton_validation
			return {
				"ok": true,
				"code": &"OK",
				"plan": skeleton.duplicate(true),
				"context": {"hold_integration": "coordinator_same_token_press_hold_release"},
			}
		if edge != &"released":
			return _failure(&"UNSUPPORTED_EDGE")
		if typeof(intent.get("held_frames")) != TYPE_INT or int(intent["held_frames"]) < 0:
			return _failure(&"INVALID_HELD_FRAMES")
		return _build_launch_primary_plan(int(intent["held_frames"]), frozen_context)
	if action_id == "starfall_arrow_rain":
		if edge == &"pressed":
			var skeleton := _build_launch_starfall_hold_skeleton(frozen_context)
			var skeleton_validation := _validate_launch_plan(skeleton)
			if not bool(skeleton_validation.get("ok", false)):
				return skeleton_validation
			return {
				"ok": true,
				"code": &"OK",
				"plan": skeleton.duplicate(true),
				"context": {"hold_integration": "coordinator_same_token_press_hold_release"},
			}
		if edge != &"released":
			return _failure(&"UNSUPPORTED_EDGE")
		if (
			typeof(intent.get("held_frames")) != TYPE_INT
			or int(intent["held_frames"]) < 60
		):
			return _failure(&"UNDERCHARGED", {"minimum_frames": 60})
		return _build_launch_press_plan(action_id, frozen_context)
	if edge != &"pressed":
		return _failure(&"UNSUPPORTED_EDGE")
	return _build_launch_press_plan(action_id, frozen_context)


func _build_launch_starfall_hold_skeleton(frozen_context: Dictionary) -> Dictionary:
	var action: Dictionary = _launch_actions_by_id["starfall_arrow_rain"]
	var plan := _launch_plan_base("starfall_arrow_rain", frozen_context)
	plan["phases"] = [
		{
			"phase": "HOLD",
			"duration_frames": 60,
			"minimum_hold_frames": 60,
			"charge_complete_frames": 60,
			"hold_progress_multiplier": 1.0,
			"movement_start_multiplier": float(action["movement_multiplier"]),
			"movement_multiplier": float(action["movement_multiplier"]),
		},
		{"phase": "WINDUP", "duration_frames": 20, "movement_multiplier": float(action["movement_multiplier"])},
		{"phase": "ACTIVE", "duration_frames": 90, "movement_multiplier": float(action["movement_multiplier"])},
		{"phase": "RECOVERY", "duration_frames": 25, "movement_multiplier": float(action["movement_multiplier"])},
	]
	return plan


func _build_launch_hold_skeleton(frozen_context: Dictionary) -> Dictionary:
	var action: Dictionary = _launch_actions_by_id[str(LAUNCH_PRIMARY_ACTION_ID)]
	var charge_multiplier := _launch_charge_multiplier(
		frozen_context["adapter_snapshot"],
		frozen_context["modifier_snapshot"],
		frozen_context["time_interactions"]
	)
	var full_charge_raw_frames := ceili(float(LAUNCH_FULL_CHARGE_FRAMES) / maxf(charge_multiplier, 0.001))
	var hold_duration := full_charge_raw_frames + (LAUNCH_AUTO_RELEASE_FRAMES - LAUNCH_FULL_CHARGE_FRAMES)
	var plan := {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(LAUNCH_PRIMARY_ACTION_ID),
		"profile_id": LAUNCH_PROFILE_ID,
		"profile_version": int(_profile_snapshot["profile_version"]),
		"semantic_action": "weapon_primary",
		"activation_mode": "release",
		"buffer_frames": int(action.get("buffer_frames", 8)),
		"cooldown_frames": int(action.get("cooldown_frames", 0)),
		"resource_costs": (action.get("resource_costs", {}) as Dictionary).duplicate(true),
		"aim_direction_snapshot": frozen_context["direction"],
		"target_point_snapshot": frozen_context["target_point"],
		"run_seed": frozen_context["run_seed"],
		"modifier_snapshot": (frozen_context["modifier_snapshot"] as Dictionary).duplicate(true),
		"adapter_snapshot": (frozen_context["adapter_snapshot"] as Dictionary).duplicate(true),
		"time_interactions_snapshot": (frozen_context["time_interactions"] as Dictionary).duplicate(true),
		"cue": (_launch_cues_by_id[str(action["cue_id"])] as Dictionary).duplicate(true),
		"phases": [
			{
				"phase": "HOLD",
				"duration_frames": hold_duration,
				"minimum_hold_frames": 0,
				"charge_complete_frames": LAUNCH_FULL_CHARGE_FRAMES,
				"hold_progress_multiplier": charge_multiplier,
				"movement_start_multiplier": LAUNCH_NORMAL_MOVE_MULTIPLIER,
				"movement_multiplier": LAUNCH_FULL_MOVE_MULTIPLIER,
			},
			{
				"phase": "WINDUP",
				"duration_frames": int(action["windup_frames"]),
				"movement_multiplier": float(action["movement_multiplier"]),
			},
			{
				"phase": "ACTIVE",
				"duration_frames": int(action["active_frames"]),
				"movement_multiplier": float(action["movement_multiplier"]),
			},
			{
				"phase": "RECOVERY",
				"duration_frames": int(action["recovery_frames"]),
				"cancel_from_frame": int(action["cancel_from_frame"]),
				"movement_multiplier": float(action["movement_multiplier"]),
			},
		],
		"payloads": [],
	}
	_freeze_character_stats_into_plan(plan, frozen_context["adapter_snapshot"])
	return plan


func _build_launch_primary_plan(
	raw_frames: int,
	frozen_context: Dictionary,
	validate_plan: bool = true
) -> Dictionary:
	var action: Dictionary = _launch_actions_by_id[str(LAUNCH_PRIMARY_ACTION_ID)]
	var charge_multiplier := _launch_charge_multiplier(
		frozen_context["adapter_snapshot"],
		frozen_context["modifier_snapshot"],
		frozen_context["time_interactions"]
	)
	var effective_frames := clampf(
		float(raw_frames) * charge_multiplier,
		0.0,
		float(LAUNCH_FULL_CHARGE_FRAMES)
	)
	var tier := _launch_charge_tier(effective_frames)
	if tier.is_empty():
		return _failure(&"CHARGE_TIER_NOT_FOUND")
	var recovery_frames := int(tier["recovery_frames"])
	if (
		str(tier["tier_id"]) == "quick"
		and bool((frozen_context["time_interactions"] as Dictionary).get("accelerate_active", false))
	):
		recovery_frames = maxi(1, recovery_frames - 6)
	var modifier_snapshot: Dictionary = frozen_context["modifier_snapshot"]
	var full_charge := str(tier["tier_id"]) == "full"
	var damage_multiplier := float(tier["damage_multiplier"])
	var total_damage_multiplier := (
		damage_multiplier
		* float(modifier_snapshot.get("weapon.damage", 1.0))
		* (float(modifier_snapshot.get("weapon.full_charge_damage", 1.0)) if full_charge else 1.0)
	)
	var generic_pierce := roundi(float(modifier_snapshot.get("weapon.pierce", 0.0)))
	var pierce := -1 if full_charge else int(tier["pierce"]) + generic_pierce
	var parameters := {
		"direction": frozen_context["direction"],
		"charge_tier": str(tier["tier_id"]),
		"raw_hold_frames": raw_frames,
		"effective_hold_frames": effective_frames,
		"full_charge": full_charge,
		"base_attack": float((frozen_context["adapter_snapshot"] as Dictionary)["base_attack"]),
		"damage_multiplier": damage_multiplier,
		"resolved_damage_multiplier": total_damage_multiplier,
		"damage": float((frozen_context["adapter_snapshot"] as Dictionary)["base_attack"]) * total_damage_multiplier,
		"speed_cells_per_second": float(tier["speed_cells_per_second"]),
		"range_cells": float(tier["range_cells"]),
		"pierce": pierce,
		"pierce_mode": "unlimited" if full_charge else "bounded",
		"hit_width_cells": float(tier["hit_width_cells"]),
		"knockback_cells": float(tier["knockback_cells"]),
		"critical_chance_bonus": float(tier["critical_chance_bonus"]),
		"physical_damage_ratio": 0.5 if full_charge else 1.0,
		"time_damage_ratio": 0.5 if full_charge else 0.0,
		"target_deduplication": "per_action_token",
		"weakpoint_eligible": full_charge,
		"tags": ["weapon:bow", "attack:%s" % str(tier["tier_id"])],
	}
	_freeze_character_stats_into_parameters(parameters, frozen_context["adapter_snapshot"])
	if str(tier["tier_id"]) == "piercing":
		parameters["time_mark_chance"] = 0.15
		parameters["time_mark_duration_frames"] = 180
	var plan := _launch_plan_base(str(LAUNCH_PRIMARY_ACTION_ID), frozen_context)
	plan["hold"] = {
		"resource_id": str(RESOURCE_ID),
		"raw_frames": raw_frames,
		"effective_frames": effective_frames,
		"minimum_frames": 0,
		"maximum_frames": LAUNCH_AUTO_RELEASE_FRAMES,
		"charge_ratio": effective_frames / float(LAUNCH_FULL_CHARGE_FRAMES),
		"full_charge_frames": LAUNCH_FULL_CHARGE_FRAMES,
	}
	plan["phases"] = [
		{"phase": "WINDUP", "duration_frames": int(tier["windup_frames"]), "movement_multiplier": float(action["movement_multiplier"])},
		{"phase": "ACTIVE", "duration_frames": int(tier["active_frames"]), "movement_multiplier": float(action["movement_multiplier"])},
		{
			"phase": "RECOVERY",
			"duration_frames": recovery_frames,
			"cancel_from_frame": mini(int(tier["cancel_from_frame"]), recovery_frames - 1),
			"movement_multiplier": float(action["movement_multiplier"]),
		},
	]
	plan["payloads"] = [{
		"descriptor_id": str(LAUNCH_PAYLOAD_IDS[str(LAUNCH_PRIMARY_ACTION_ID)]),
		"kind": "projectile",
		"parameters": parameters,
	}]
	if validate_plan:
		var validation := _validate_launch_plan(plan)
		if not bool(validation.get("ok", false)):
			return validation
	return {
		"ok": true,
		"code": &"OK",
		"plan": plan.duplicate(true),
		"context": {
			"held_frames": raw_frames,
			"effective_frames": effective_frames,
			"charge_tier": str(tier["tier_id"]),
			"full_charge": full_charge,
			"hold_integration": "coordinator_same_token_press_hold_release",
		},
	}


func _build_launch_press_plan(
	action_id: String,
	frozen_context: Dictionary,
	validate_plan: bool = true
) -> Dictionary:
	var action_value: Variant = _launch_actions_by_id.get(action_id)
	if not action_value is Dictionary:
		return _failure(&"ACTION_NOT_FOUND", {"action_id": action_id})
	var action: Dictionary = action_value
	var payload_parameters := _launch_press_payload_parameters(action_id, frozen_context)
	if payload_parameters.is_empty():
		return _failure(&"PAYLOAD_PROFILE_INVALID", {"action_id": action_id})
	_freeze_character_stats_into_parameters(payload_parameters, frozen_context["adapter_snapshot"])
	var plan := _launch_plan_base(action_id, frozen_context)
	var recovery_phase := {
		"phase": "RECOVERY",
		"duration_frames": int(action["recovery_frames"]),
		"movement_multiplier": float(action["movement_multiplier"]),
	}
	if action.get("cancel_from_frame") != null:
		recovery_phase["cancel_from_frame"] = mini(
			int(action["cancel_from_frame"]),
			int(action["recovery_frames"]) - 1
		)
	plan["phases"] = [
		{"phase": "WINDUP", "duration_frames": int(action["windup_frames"]), "movement_multiplier": float(action["movement_multiplier"])},
		{"phase": "ACTIVE", "duration_frames": int(action["active_frames"]), "movement_multiplier": float(action["movement_multiplier"])},
		recovery_phase,
	]
	var payload: Dictionary = _launch_payloads_by_id[str(action["payload_id"])]
	plan["payloads"] = [{
		"descriptor_id": str(payload["payload_id"]),
		"kind": str(payload["kind"]),
		"parameters": payload_parameters,
	}]
	if validate_plan:
		var validation := _validate_launch_plan(plan)
		if not bool(validation.get("ok", false)):
			return validation
	return {"ok": true, "code": &"OK", "plan": plan.duplicate(true), "context": {}}


func _launch_plan_base(action_id: String, frozen_context: Dictionary) -> Dictionary:
	var action: Dictionary = _launch_actions_by_id[action_id]
	var plan := {
		"weapon_id": str(WEAPON_ID),
		"action_id": action_id,
		"profile_id": LAUNCH_PROFILE_ID,
		"profile_version": int(_profile_snapshot["profile_version"]),
		"semantic_action": str(action["semantic_action"]),
		"activation_mode": str(action["activation_mode"]),
		"buffer_frames": int(action["buffer_frames"]),
		"cooldown_frames": int(action.get("cooldown_frames", 0)),
		"resource_costs": (action.get("resource_costs", {}) as Dictionary).duplicate(true),
		"aim_direction_snapshot": frozen_context["direction"],
		"target_point_snapshot": frozen_context["target_point"],
		"run_seed": frozen_context["run_seed"],
		"modifier_snapshot": (frozen_context["modifier_snapshot"] as Dictionary).duplicate(true),
		"adapter_snapshot": (frozen_context["adapter_snapshot"] as Dictionary).duplicate(true),
		"time_interactions_snapshot": (frozen_context["time_interactions"] as Dictionary).duplicate(true),
		"cue": (_launch_cues_by_id[str(action["cue_id"])] as Dictionary).duplicate(true),
		"phases": [],
		"payloads": [],
	}
	_freeze_character_stats_into_plan(plan, frozen_context["adapter_snapshot"])
	return plan


func _launch_press_payload_parameters(action_id: String, frozen_context: Dictionary) -> Dictionary:
	var direction: Vector2 = frozen_context["direction"]
	var modifier_snapshot: Dictionary = frozen_context["modifier_snapshot"]
	var damage_modifier := float(modifier_snapshot.get("weapon.damage", 1.0))
	match action_id:
		"scatter_shot":
			return {
				"direction": direction,
				"count": 5,
				"damage_multiplier": 0.6,
				"resolved_damage_multiplier": 0.6 * damage_modifier,
				"spread_degrees": 30.0,
				"speed_cells_per_second": 18.0,
				"range_cells": 8.0,
				"hit_width_cells": 0.3,
				"target_deduplication": "per_projectile_per_action_token",
			}
		"focus_step":
			return {
				"direction": -direction,
				"distance_pixels": 96.0,
				"collision_mode": "swept",
				"invulnerable": false,
				"invulnerability_frames": 0,
			}
		"temporal_arrow":
			return {
				"direction": direction,
				"damage_multiplier": 5.0,
				"resolved_damage_multiplier": 5.0 * damage_modifier,
				"physical_damage_ratio": 0.0,
				"time_damage_ratio": 1.0,
				"speed_cells_per_second": 10.0,
				"range_cells": 20.0,
				"pierce": -1,
				"pierce_mode": "unlimited",
				"hit_width_cells": 1.0,
				"trail": {
					"duration_frames": 300,
					"width_cells": 0.8,
					"tick_interval_frames": 30,
					"tick_damage_multiplier": 0.2,
					"slow_ratio": 0.3,
				},
				"first_hit_control": {
					"ordinary_freeze_frames": 90,
					"boss_slow_ratio": 0.7,
					"boss_slow_frames": 48,
				},
				"target_deduplication": "per_action_token",
			}
		"starfall_arrow_rain":
			return {
				"target_point": frozen_context["target_point"],
				"wave_count": 10,
				"wave_interval_frames": 9,
				"arrows_per_wave": 3,
				"total_arrows": 30,
				"arrow_damage_multiplier": 1.2,
				"resolved_arrow_damage_multiplier": 1.2 * damage_modifier,
				"physical_damage_ratio": 0.4,
				"time_damage_ratio": 0.6,
				"radius_cells": 4.0,
				"target_distance_cells": 8.0,
				"maximum_offset_cells": 1.5,
				"invulnerable": true,
				"slow_ratio": 0.4,
				"time_erosion": {"stack_interval_frames": 30, "time_damage_taken_per_stack": 0.03, "maximum_stacks": 10},
				"target_deduplication": "per_arrow_per_action_token",
			}
	return {}


func _commit_launch_action(plan: Dictionary, token: int) -> Dictionary:
	var validation := _validate_launch_plan(plan)
	if not bool(validation.get("ok", false)):
		return validation
	if _is_hold_skeleton(plan):
		_active_token = token
		_active_phase = &"HOLD"
		_active_plan = plan.duplicate(true)
		_modifier_snapshot = (plan["modifier_snapshot"] as Dictionary).duplicate(true)
		_live_launch_time_context = (plan["time_interactions_snapshot"] as Dictionary).duplicate(true)
		_committed_launch_definition.clear()
		return {
			"ok": true,
			"code": &"OK",
			"context": {
				"action_id": str(plan["action_id"]),
				"minimum_hold_frames": int(((plan["phases"] as Array)[0] as Dictionary).get("minimum_hold_frames", 0)),
				"maximum_hold_frames": int(((plan["phases"] as Array)[0] as Dictionary).get("duration_frames", 0)),
			},
		}
	var staged := _stage_launch_action(plan, token)
	if not bool(staged.get("ok", false)):
		return staged
	_active_token = token
	_active_phase = &"WINDUP"
	_active_plan = plan.duplicate(true)
	_modifier_snapshot = (plan["modifier_snapshot"] as Dictionary).duplicate(true)
	return {
		"ok": true,
		"code": &"OK",
		"context": {
			"action_id": str(plan["action_id"]),
			"payload_descriptor_count": (_committed_launch_definition["payload_descriptors"] as Array).size(),
		},
	}


func _release_launch_hold(plan: Dictionary, token: int, held_frames: int) -> Dictionary:
	if (
		token <= 0
		or token != _active_token
		or _active_phase != &"HOLD"
		or plan != _active_plan
		or not _is_hold_skeleton(plan)
	):
		return _failure(&"STALE_HOLD_RELEASE")
	var validation := _validate_launch_plan(plan)
	if not bool(validation.get("ok", false)):
		return validation
	var frozen_context := _launch_frozen_context_from_plan(plan)
	if not _live_launch_time_context.is_empty():
		frozen_context["time_interactions"] = _live_launch_time_context.duplicate(true)
	var finalized_result: Dictionary
	if str(plan.get("action_id", "")) == str(LAUNCH_PRIMARY_ACTION_ID):
		finalized_result = _build_launch_primary_plan(held_frames, frozen_context)
	elif str(plan.get("action_id", "")) == "starfall_arrow_rain":
		if held_frames < 60:
			return _failure(&"UNDERCHARGED", {"held_frames": held_frames, "minimum_frames": 60})
		finalized_result = _build_launch_press_plan("starfall_arrow_rain", frozen_context)
	else:
		return _failure(&"STALE_HOLD_RELEASE")
	if not bool(finalized_result.get("ok", false)):
		return finalized_result
	var finalized_plan: Dictionary = finalized_result["plan"]
	var staged := _stage_launch_action(finalized_plan, token)
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


func _on_launch_phase_enter(phase: StringName, token: int) -> Array[Dictionary]:
	match phase:
		&"HOLD":
			if _active_phase != &"HOLD":
				return []
		&"WINDUP":
			if _active_phase != &"WINDUP":
				return []
		&"ACTIVE":
			if _active_phase != &"WINDUP" or _committed_launch_definition.is_empty():
				return []
			if not bool(_adapter.call("release_profile_action")):
				return [{"type": "phase_failed", "reason": "payload_activation_failed"}]
			_active_phase = &"ACTIVE"
			return [
				{
					"type": "payload_released",
					"weapon_id": str(WEAPON_ID),
					"action_id": str(_active_plan["action_id"]),
					"descriptor_id": str(((_active_plan["payloads"] as Array)[0] as Dictionary)["descriptor_id"]),
					"token": token,
					"payload_descriptors": (_committed_launch_definition["payload_descriptors"] as Array).duplicate(true),
					"time_interactions": (_committed_launch_definition["time_interactions"] as Array).duplicate(true),
					"boss_conversion": (_committed_launch_definition["boss_conversion"] as Dictionary).duplicate(true),
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
			_active_phase = &"RECOVERY"
	return []


func _stage_launch_action(plan: Dictionary, token: int) -> Dictionary:
	var definition := _launch_action_definition(plan, token)
	if definition.is_empty():
		return _failure(&"PAYLOAD_PROFILE_INVALID")
	var committed_value: Variant = _adapter.call("begin_profile_action", definition.duplicate(true))
	if not committed_value is Dictionary or (committed_value as Dictionary).is_empty():
		_adapter.call("cancel_profile_action")
		return _failure(&"PAYLOAD_CONSTRUCTION_FAILED")
	if (committed_value as Dictionary) != definition:
		_adapter.call("cancel_profile_action")
		return _failure(&"PAYLOAD_PROFILE_MISMATCH")
	_committed_launch_definition = definition.duplicate(true)
	return {"ok": true, "code": &"OK", "context": {}}


func _launch_action_definition(plan: Dictionary, token: int) -> Dictionary:
	if token <= 0:
		return {}
	var descriptors := _materialize_launch_payloads(plan, token)
	if descriptors.is_empty():
		return {}
	return {
		"token": token,
		"profile_id": LAUNCH_PROFILE_ID,
		"weapon_id": str(WEAPON_ID),
		"action_id": str(plan["action_id"]),
		"semantic_action": str(plan["semantic_action"]),
		"aim_direction": plan["aim_direction_snapshot"],
		"target_point": plan["target_point_snapshot"],
		"payload_descriptors": descriptors,
		"time_interactions": _launch_time_descriptors(plan, token, descriptors),
		"boss_conversion": _launch_boss_conversion(plan),
		"character_attack_scale": float(plan.get("character_attack_scale", 0.0)),
		"attack_speed": float(plan.get("attack_speed", 0.0)),
		"crit_chance": float(plan.get("crit_chance", -1.0)),
		"crit_multiplier": float(plan.get("crit_multiplier", 0.0)),
	}


func _materialize_launch_payloads(plan: Dictionary, token: int) -> Array[Dictionary]:
	var payload_value: Variant = (plan.get("payloads", []) as Array)[0] if not (plan.get("payloads", []) as Array).is_empty() else null
	if not payload_value is Dictionary:
		return []
	var payload: Dictionary = payload_value
	var payload_id := StringName(str(payload["descriptor_id"]))
	var action_id := StringName(str(plan["action_id"]))
	var run_seed := int(plan["run_seed"])
	var parameters: Dictionary = payload["parameters"]
	var result: Array[Dictionary] = []
	if str(action_id) == "scatter_shot":
		var direction: Vector2 = parameters["direction"]
		for index: int in range(5):
			var angle_degrees := -30.0 + 15.0 * float(index)
			var arrow_parameters := parameters.duplicate(true)
			arrow_parameters["direction"] = direction.rotated(deg_to_rad(angle_degrees))
			arrow_parameters["angle_degrees"] = angle_degrees
			result.append(_seeded_descriptor(payload_id, &"projectile", arrow_parameters, run_seed, action_id, token, index))
		return result
	if str(action_id) == "starfall_arrow_rain":
		var schedule_parameters := parameters.duplicate(true)
		var arrows: Array[Dictionary] = []
		for index: int in range(30):
			var seed := SeedServiceScript.derive_weapon_action_seed(run_seed, StringName(LAUNCH_PROFILE_ID), action_id, payload_id, token, index)
			arrows.append({
				"wave_index": index / 3,
				"arrow_index": index % 3,
				"outcome_index": index,
				"seed": seed,
				"maximum_offset_cells": 1.5,
			})
		schedule_parameters["arrows"] = arrows
		result.append(_seeded_descriptor(payload_id, &"zone_schedule", schedule_parameters, run_seed, action_id, token, 0))
		return result
	result.append(_seeded_descriptor(payload_id, StringName(str(payload["kind"])), parameters, run_seed, action_id, token, 0))
	return result


func _seeded_descriptor(
	payload_id: StringName,
	kind: StringName,
	parameters: Dictionary,
	run_seed: int,
	action_id: StringName,
	token: int,
	outcome_index: int
) -> Dictionary:
	return {
		"descriptor_id": str(payload_id),
		"kind": str(kind),
		"outcome_index": outcome_index,
		"seed": SeedServiceScript.derive_weapon_action_seed(
			run_seed,
			StringName(LAUNCH_PROFILE_ID),
			action_id,
			payload_id,
			token,
			outcome_index
		),
		"parameters": parameters.duplicate(true),
	}


func _launch_time_descriptors(
	plan: Dictionary,
	token: int,
	payload_descriptors: Array[Dictionary]
) -> Array[Dictionary]:
	var context: Dictionary = plan["time_interactions_snapshot"]
	var action_id := str(plan["action_id"])
	var parameters := _payload_parameters_from_plan(plan)
	var full_charge := bool(parameters.get("full_charge", false))
	var descriptors: Array[Dictionary] = []
	if bool(context.get("stop_active", false)) and full_charge:
		descriptors.append({
			"id": "stop",
			"effect": "full_charge_explosion",
			"interaction_id": "bow_stopped_target_burst",
			"trigger": "full_charge_hit",
			"explosion_radius_cells": 2.5,
			"explosion_damage_multiplier": 2.0,
			"damage_multiplier": 2.0,
			"damage_type": "time",
			"stop_extension_frames": 60,
			"extension_once_per_action_token": true,
		})
	if bool(context.get("rewind_echo_available", false)) and action_id != "focus_step":
		var phantom_descriptors: Array[Dictionary] = []
		var first_phantom_outcome := _maximum_descriptor_outcome_index(payload_descriptors) + 1
		for index: int in range(3):
			phantom_descriptors.append({
				"outcome_index": first_phantom_outcome + index,
				"seed": SeedServiceScript.derive_weapon_action_seed(
					int(plan["run_seed"]),
					StringName(LAUNCH_PROFILE_ID),
					StringName(action_id),
					&"bow_rewind_phantom",
					token,
					index
				),
				"angle_offset_degrees": [-15.0, 0.0, 15.0][index],
			})
		descriptors.append({
			"id": "rewind",
			"effect": "phantom_arrows",
			"interaction_id": "bow_echo_arrows",
			"rewind_echo_generation": int(context.get("rewind_echo_generation", 0)),
			"phantom_count": 3,
			"count": 3,
			"damage_multiplier": 0.5,
			"damage_type": "time",
			"angle_offsets_degrees": [-15.0, 0.0, 15.0],
			"angle_step_degrees": 15.0,
			"phantom_descriptors": phantom_descriptors,
		})
	if bool(context.get("accelerate_active", false)):
		descriptors.append({
			"id": "accelerate",
			"effect": "rapid_fire",
			"interaction_id": "bow_charge_speed",
			"active": true,
			"charge_rate_multiplier": 2.0,
			"quick_recovery_reduction_frames": 6,
			"applies_to_future_plan": true,
		})
	if bool(context.get("rift_active", false)) and full_charge:
		descriptors.append({
			"id": "rift",
			"effect": "penetration_detonation",
			"interaction_id": "bow_rift_penetration",
			"trigger": "full_charge_hit_in_rift",
			"pierce_mode": "unlimited",
			"detonation_radius_multiplier": 1.5,
			"detonation_damage_multiplier": 1.5,
			"damage_multiplier": 1.5,
			"damage_type": "time",
		})
	return descriptors


func _maximum_descriptor_outcome_index(descriptors: Array[Dictionary]) -> int:
	var maximum := -1
	for descriptor: Dictionary in descriptors:
		maximum = maxi(maximum, int(descriptor.get("outcome_index", -1)))
	return maximum


func _launch_boss_conversion(plan: Dictionary) -> Dictionary:
	return {
		"target_id": "chrono_warden",
		"conversion_id": "bow_chrono_warden_control_conversion",
		"active_attack_policy": "preserve_committed",
		"preserve_committed_active_attack": true,
		"apply_window": "recovery_or_exposed",
		"allowed_phases": ["RECOVERY", "EXPOSED"],
		"control_conversion": "poise_and_exposure",
		"poise_multiplier": 1.15,
		"recovery_extension_frames": 12,
		"exposure_frames": 30,
		"poise_damage": 15.0,
	}


func _validate_launch_plan(plan: Dictionary) -> Dictionary:
	var contract_result := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	if not bool(contract_result.get("ok", false)):
		return contract_result
	if str(plan.get("profile_id", "")) != LAUNCH_PROFILE_ID or int(plan.get("profile_version", 0)) != 1:
		return _failure(&"PROFILE_MISMATCH")
	var action_id := str(plan.get("action_id", ""))
	var action_value: Variant = _launch_actions_by_id.get(action_id)
	if not action_value is Dictionary:
		return _failure(&"ACTION_ID_MISMATCH")
	var action: Dictionary = action_value
	if (
		str(plan.get("semantic_action", "")) != str(action["semantic_action"])
		or str(plan.get("activation_mode", "")) != str(action["activation_mode"])
		or int(plan.get("buffer_frames", -1)) != int(action["buffer_frames"])
		or int(plan.get("cooldown_frames", -1)) != int(action.get("cooldown_frames", 0))
		or plan.get("resource_costs", {}) != action.get("resource_costs", {})
	):
		return _failure(&"ACTION_PROFILE_MISMATCH")
	for field: String in [
		"aim_direction_snapshot",
		"target_point_snapshot",
		"run_seed",
		"modifier_snapshot",
		"adapter_snapshot",
		"time_interactions_snapshot",
		"cue",
	]:
		if not plan.has(field):
			return _failure(&"PLAN_SNAPSHOT_MISSING", {"field": field})
	if typeof(plan["run_seed"]) != TYPE_INT or not _variant_numbers_are_finite(plan):
		return _failure(&"INVALID_PLAN_SNAPSHOT")
	var expected: Dictionary
	var frozen_context := _launch_frozen_context_from_plan(plan)
	if _is_hold_skeleton(plan):
		expected = (
			_build_launch_starfall_hold_skeleton(frozen_context)
			if action_id == "starfall_arrow_rain"
			else _build_launch_hold_skeleton(frozen_context)
		)
	elif action_id == str(LAUNCH_PRIMARY_ACTION_ID):
		if not plan.get("hold") is Dictionary or typeof((plan["hold"] as Dictionary).get("raw_frames")) != TYPE_INT:
			return _failure(&"INVALID_HOLD_SNAPSHOT")
		var rebuilt := _build_launch_primary_plan_unvalidated(int((plan["hold"] as Dictionary)["raw_frames"]), frozen_context)
		if rebuilt.is_empty():
			return _failure(&"INVALID_HOLD_SNAPSHOT")
		expected = rebuilt
	else:
		expected = _build_launch_press_plan_unvalidated(action_id, frozen_context)
	if expected.is_empty() or plan != expected:
		return _failure(&"LAUNCH_PLAN_MISMATCH")
	return {"ok": true, "code": &"OK", "context": {}}


func _build_launch_primary_plan_unvalidated(raw_frames: int, frozen_context: Dictionary) -> Dictionary:
	var built := _build_launch_primary_plan(raw_frames, frozen_context, false)
	return (built.get("plan", {}) as Dictionary).duplicate(true) if bool(built.get("ok", false)) else {}


func _build_launch_press_plan_unvalidated(action_id: String, frozen_context: Dictionary) -> Dictionary:
	var built := _build_launch_press_plan(action_id, frozen_context, false)
	return (built.get("plan", {}) as Dictionary).duplicate(true) if bool(built.get("ok", false)) else {}


func _launch_frozen_context_from_plan(plan: Dictionary) -> Dictionary:
	return {
		"direction": plan["aim_direction_snapshot"],
		"target_point": plan["target_point_snapshot"],
		"run_seed": plan["run_seed"],
		"modifier_snapshot": (plan["modifier_snapshot"] as Dictionary).duplicate(true),
		"adapter_snapshot": (plan["adapter_snapshot"] as Dictionary).duplicate(true),
		"time_interactions": (plan["time_interactions_snapshot"] as Dictionary).duplicate(true),
	}


func _normalize_launch_time_context(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure(&"INVALID_TIME_CONTEXT")
	var source: Dictionary = value
	var result := {
		"stop_active": false,
		"rewind_echo_available": false,
		"rewind_echo_generation": 0,
		"accelerate_active": false,
		"rift_active": false,
	}
	for field: String in ["stop_active", "rewind_echo_available", "accelerate_active", "rift_active"]:
		if source.has(field) and typeof(source[field]) != TYPE_BOOL:
			return _failure(&"INVALID_TIME_CONTEXT", {"field": field})
		result[field] = bool(source.get(field, false))
	if (
		source.has("rewind_echo_generation")
		and (
			typeof(source["rewind_echo_generation"]) != TYPE_INT
			or int(source["rewind_echo_generation"]) < 0
		)
	):
		return _failure(&"INVALID_TIME_CONTEXT", {"field": "rewind_echo_generation"})
	result["rewind_echo_generation"] = int(source.get("rewind_echo_generation", 0))
	return {"ok": true, "code": &"OK", "context": result}


func _launch_charge_multiplier(
	adapter_snapshot: Dictionary,
	modifier_snapshot: Dictionary,
	time_context: Dictionary
) -> float:
	var multiplier := _charge_multiplier(adapter_snapshot, modifier_snapshot)
	if bool(time_context.get("accelerate_active", false)):
		multiplier *= 2.0
	return maxf(multiplier, 0.001)


func _launch_charge_tier(effective_frames: float) -> Dictionary:
	var frame_value := floori(effective_frames)
	for tier: Dictionary in LAUNCH_PRIMARY_TIERS:
		if (
			frame_value >= int(tier["minimum_frames"])
			and frame_value < int(tier["maximum_frames_exclusive"])
		):
			return tier.duplicate(true)
	return LAUNCH_PRIMARY_TIERS.back().duplicate(true)


func _restore_launch_snapshot(runtime_snapshot: Dictionary) -> bool:
	if not _valid_launch_restore_snapshot(runtime_snapshot):
		return false
	return _restore_snapshot_atomic(runtime_snapshot)


func _valid_launch_restore_snapshot(value: Dictionary) -> bool:
	if (
		not _runtime_snapshot_has_exact_fields(value)
		or int(value.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION
		or not bool(value.get("configured", false))
		or str(value.get("profile_id", "")) != LAUNCH_PROFILE_ID
		or int(value.get("profile_version", 0)) != 1
		or typeof(value.get("active_token")) != TYPE_INT
		or int(value["active_token"]) < 0
		or not value.get("active_plan") is Dictionary
		or not value.get("modifier_snapshot") is Dictionary
		or not value.get("committed_launch_definition") is Dictionary
		or not value.get("live_launch_time_context") is Dictionary
		or typeof(value.get("adapter_active")) != TYPE_BOOL
		or not value.get("adapter_snapshot") is Dictionary
	):
		return false
	var adapter_snapshot := value["adapter_snapshot"] as Dictionary
	if not bool(_adapter.call("can_restore_runtime_snapshot", adapter_snapshot)):
		return false
	var active_token := int(value["active_token"])
	var active_phase := str(value.get("active_phase", ""))
	if active_token == 0:
		if (
			active_phase != "READY"
			or bool(value["adapter_active"])
			or str(adapter_snapshot.get("phase_state", "")) != "idle"
			or not (value["active_plan"] as Dictionary).is_empty()
			or not (value["modifier_snapshot"] as Dictionary).is_empty()
			or not (value["committed_launch_definition"] as Dictionary).is_empty()
			or not (value["live_launch_time_context"] as Dictionary).is_empty()
		):
			return false
	else:
		var live_context: Dictionary = value["live_launch_time_context"]
		var normalized_live := _normalize_launch_time_context(live_context)
		if (
			active_phase not in ["HOLD", "WINDUP", "ACTIVE", "RECOVERY"]
			or not bool(_validate_launch_plan(value["active_plan"]).get("ok", false))
			or value["modifier_snapshot"] != (value["active_plan"] as Dictionary).get("modifier_snapshot", {})
			or not bool(normalized_live.get("ok", false))
			or normalized_live.get("context", {}) != live_context
			or bool(live_context.get("accelerate_active", false)) != bool(
				(value["active_plan"] as Dictionary).get("time_interactions_snapshot", {}).get(
					"accelerate_active",
					false
				)
			)
		):
			return false
		var committed := value["committed_launch_definition"] as Dictionary
		if active_phase == "HOLD":
			if bool(value["adapter_active"]) or str(adapter_snapshot.get("phase_state", "")) != "idle" or not committed.is_empty():
				return false
		else:
			var expected_state := "action_prepared" if active_phase == "WINDUP" else "action_released"
			if (
				not bool(value["adapter_active"])
				or str(adapter_snapshot.get("phase_state", "")) != expected_state
				or committed.is_empty()
				or int(committed.get("token", 0)) != active_token
				or adapter_snapshot.get("profile_action", {}) != committed
			):
				return false
	if (
		not _valid_token_array(value.get("reward_eligible_tokens"))
		or not _valid_token_array(value.get("reward_claimed_tokens"))
		or not _variant_numbers_are_finite(value)
	):
		return false
	var eligible := _int_array(value["reward_eligible_tokens"])
	for token: int in _int_array(value["reward_claimed_tokens"]):
		if not eligible.has(token):
			return false
	return true


func _build_hold_skeleton(
	direction: Vector2,
	adapter_snapshot: Dictionary,
	modifier_snapshot: Dictionary
) -> Dictionary:
	var timing_multiplier := _timing_multiplier(adapter_snapshot, modifier_snapshot)
	var charge_multiplier := _charge_multiplier(adapter_snapshot, modifier_snapshot)
	var plan := {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(ACTION_ID),
		"profile_id": str(_profile_snapshot["id"]),
		"profile_version": int(_profile_snapshot["profile_version"]),
		"semantic_action": "weapon_primary",
		"activation_mode": "release",
		"buffer_frames": int(_action.get("buffer_frames", 8)),
		"cooldown_frames": _profile_cooldown_frames(),
		"resource_costs": (_action.get("resource_costs", {}) as Dictionary).duplicate(true),
		"aim_direction_snapshot": direction,
		"modifier_snapshot": modifier_snapshot.duplicate(true),
		"adapter_snapshot": adapter_snapshot.duplicate(true),
		"cue": _cue.duplicate(true),
		"phases": [
			{
				"phase": "HOLD",
				"duration_frames": MAXIMUM_CHARGE_FRAMES,
				"minimum_hold_frames": MINIMUM_CHARGE_FRAMES,
				"charge_complete_frames": MAXIMUM_CHARGE_FRAMES,
				"hold_progress_multiplier": charge_multiplier,
				"movement_start_multiplier": float(_action["movement_multiplier"]),
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
	_freeze_character_stats_into_plan(plan, adapter_snapshot)
	return plan


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
		"resource_costs": (_action.get("resource_costs", {}) as Dictionary).duplicate(true),
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
	_freeze_character_stats_into_plan(plan, adapter_snapshot)
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
		or plan.get("resource_costs", {}) != _action.get("resource_costs", {})
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
		"character_attack_scale": float(plan.get("character_attack_scale", 0.0)),
		"attack_speed": float(plan.get("attack_speed", 0.0)),
		"crit_chance": float(plan.get("crit_chance", -1.0)),
		"crit_multiplier": float(plan.get("crit_multiplier", 0.0)),
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
		"character_attack_scale": float(adapter_snapshot["character_attack_scale"]),
		"attack_speed": float(adapter_snapshot["attack_speed"]),
		"crit_chance": float(adapter_snapshot["crit_chance"]),
		"crit_multiplier": float(adapter_snapshot["crit_multiplier"]),
	}


func _payload_parameters_from_plan(plan: Dictionary) -> Dictionary:
	var payloads_value: Variant = plan.get("payloads", [])
	if not payloads_value is Array or (payloads_value as Array).size() != 1:
		return {}
	var payload_value: Variant = (payloads_value as Array)[0]
	if not payload_value is Dictionary:
		return {}
	var payload: Dictionary = payload_value
	if str(plan.get("profile_id", "")) == LAUNCH_PROFILE_ID:
		if str(payload.get("descriptor_id", "")).is_empty() or not payload.get("parameters") is Dictionary:
			return {}
		return (payload["parameters"] as Dictionary).duplicate(true)
	if (
		str(payload.get("descriptor_id", "")) != str(FROZEN_PAYLOAD["payload_id"])
		or str(payload.get("kind", "")) != str(FROZEN_PAYLOAD["kind"])
		or not payload.get("parameters") is Dictionary
	):
		return {}
	return (payload["parameters"] as Dictionary).duplicate(true)


func _index_launch_profile(profile: Dictionary) -> Dictionary:
	var actions: Dictionary = {}
	for action_value: Variant in profile.get("actions", []):
		if not action_value is Dictionary:
			return {"ok": false}
		var action: Dictionary = action_value
		var action_id := str(action.get("action_id", ""))
		if action_id.is_empty() or actions.has(action_id):
			return {"ok": false}
		actions[action_id] = action.duplicate(true)
	var payloads: Dictionary = {}
	for payload_value: Variant in profile.get("payloads", []):
		if not payload_value is Dictionary:
			return {"ok": false}
		var payload: Dictionary = payload_value
		var payload_id := str(payload.get("payload_id", ""))
		if payload_id.is_empty() or payloads.has(payload_id):
			return {"ok": false}
		payloads[payload_id] = payload.duplicate(true)
	var cues: Dictionary = {}
	for cue_value: Variant in profile.get("cues", []):
		if not cue_value is Dictionary:
			return {"ok": false}
		var cue: Dictionary = cue_value
		var cue_id := str(cue.get("cue_id", ""))
		if cue_id.is_empty() or cues.has(cue_id):
			return {"ok": false}
		cues[cue_id] = cue.duplicate(true)
	if actions.size() != LAUNCH_ACTION_IDS.size() or payloads.size() != LAUNCH_PAYLOAD_IDS.size() or cues.size() != LAUNCH_ACTION_IDS.size():
		return {"ok": false}
	for action_id_value: Variant in LAUNCH_PAYLOAD_IDS.keys():
		var action_id := str(action_id_value)
		if not actions.has(action_id):
			return {"ok": false}
		var action: Dictionary = actions[action_id]
		if (
			str(action.get("payload_id", "")) != str(LAUNCH_PAYLOAD_IDS[action_id])
			or not payloads.has(str(action.get("payload_id", "")))
			or not cues.has(str(action.get("cue_id", "")))
		):
			return {"ok": false}
	return {"ok": true, "actions": actions, "payloads": payloads, "cues": cues}


func _matches_frozen_launch_profile(profile: Dictionary, indexes: Dictionary) -> bool:
	if _launch_runtime_authority_digest(profile) != FROZEN_LAUNCH_RUNTIME_DIGEST:
		return false
	if not _same_string_set(profile.get("capabilities", []), FROZEN_LAUNCH_CAPABILITIES):
		return false
	var actions: Dictionary = indexes["actions"]
	var primary: Dictionary = actions.get(str(LAUNCH_PRIMARY_ACTION_ID), {})
	if (
		str(primary.get("semantic_action", "")) != "weapon_primary"
		or str(primary.get("activation_mode", "")) != "release"
		or not _integer_matches_exactly(primary.get("hold_threshold_frames"), 0)
		or not _integer_matches_exactly(primary.get("maximum_hold_frames"), LAUNCH_AUTO_RELEASE_FRAMES)
		or not _integer_matches_exactly(primary.get("cooldown_frames"), 0)
		or not _integer_matches_exactly(primary.get("windup_frames"), 4)
		or not _integer_matches_exactly(primary.get("active_frames"), 2)
		or not _integer_matches_exactly(primary.get("recovery_frames"), 20)
		or not _integer_matches_exactly(primary.get("cancel_from_frame"), 2)
		or not _number_matches_exactly(primary.get("movement_multiplier"), LAUNCH_NORMAL_MOVE_MULTIPLIER)
		or str(primary.get("payload_id", "")) != "bow_launch_arrow"
		or str(primary.get("cue_id", "")) != "bow_launch_release"
		or not primary.get("resource_costs") is Dictionary
		or not (primary["resource_costs"] as Dictionary).is_empty()
	):
		return false
	for action_id_value: Variant in LAUNCH_ACTION_CONTRACTS.keys():
		var action_id := str(action_id_value)
		var expected: Dictionary = LAUNCH_ACTION_CONTRACTS[action_id]
		var action_value: Variant = actions.get(action_id)
		if not action_value is Dictionary:
			return false
		var action: Dictionary = action_value
		for field: String in ["semantic_action", "activation_mode"]:
			if str(action.get(field, "")) != str(expected[field]):
				return false
		for field: String in ["windup_frames", "active_frames", "recovery_frames", "cooldown_frames"]:
			if not _integer_matches_exactly(action.get(field), int(expected[field])):
				return false
		if action.get("resource_costs", {}) != expected["resource_costs"]:
			return false
	var payloads: Dictionary = indexes["payloads"]
	if not _matches_launch_primary_payload(payloads.get("bow_launch_arrow", {})):
		return false
	if not _matches_launch_payload_numbers(payloads.get("bow_scatter", {}), {
		"damage_multiplier": 0.6,
		"count": 5.0,
		"spread_degrees": 30.0,
	}):
		return false
	var focus: Dictionary = payloads.get("bow_focus_step", {})
	var focus_parameters: Dictionary = focus.get("parameters", {})
	if (
		str(focus.get("kind", "")) != "movement"
		or not _number_matches_exactly(focus_parameters.get("distance"), 96.0)
		or str(focus_parameters.get("direction", "")) != "opposite_aim"
		or str(focus_parameters.get("collision_mode", "")) != "swept"
		or not _integer_matches_exactly(focus_parameters.get("invulnerability_frames"), 0)
	):
		return false
	var temporal: Dictionary = payloads.get("bow_temporal_arrow", {})
	var temporal_parameters: Dictionary = temporal.get("parameters", {})
	if (
		str(temporal.get("kind", "")) != "projectile_trail"
		or not _number_matches_exactly(temporal_parameters.get("damage_multiplier"), 5.0)
		or str(temporal_parameters.get("damage_type", "")) != "time"
		or not bool(temporal_parameters.get("unlimited_pierce", false))
		or not _integer_matches_exactly(temporal_parameters.get("trail_duration_frames"), 300)
		or not _integer_matches_exactly(temporal_parameters.get("trail_tick_interval_frames"), 30)
	):
		return false
	var starfall: Dictionary = payloads.get("bow_starfall", {})
	var starfall_parameters: Dictionary = starfall.get("parameters", {})
	if (
		str(starfall.get("kind", "")) != "seeded_zone_sequence"
		or not _integer_matches_exactly(starfall_parameters.get("wave_count"), 10)
		or not _integer_matches_exactly(starfall_parameters.get("wave_interval_frames"), 9)
		or not _integer_matches_exactly(starfall_parameters.get("arrows_per_wave"), 3)
	):
		return false
	return _matches_launch_interactions(profile)


func _launch_runtime_authority_digest(profile: Dictionary) -> String:
	var projection: Dictionary = {}
	for field: String in LAUNCH_RUNTIME_AUTHORITY_FIELDS:
		if not profile.has(field):
			return ""
		projection[field] = profile[field]
	return JSON.stringify(projection, "", true, true).sha256_text()


func _matches_launch_primary_payload(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var payload: Dictionary = value
	var parameters_value: Variant = payload.get("parameters", {})
	if str(payload.get("kind", "")) != "projectile" or not parameters_value is Dictionary:
		return false
	var parameters: Dictionary = parameters_value
	if (
		not _integer_matches_exactly(parameters.get("full_charge_frames"), LAUNCH_FULL_CHARGE_FRAMES)
		or not _integer_matches_exactly(parameters.get("auto_release_frames"), LAUNCH_AUTO_RELEASE_FRAMES)
		or not _number_matches_exactly(parameters.get("charge_movement_multiplier"), LAUNCH_NORMAL_MOVE_MULTIPLIER)
		or not _number_matches_exactly(parameters.get("full_charge_movement_multiplier"), LAUNCH_FULL_MOVE_MULTIPLIER)
		or not parameters.get("charge_tiers") is Array
		or (parameters["charge_tiers"] as Array).size() != 4
	):
		return false
	for index: int in range(LAUNCH_PRIMARY_TIERS.size()):
		var tier_value: Variant = (parameters["charge_tiers"] as Array)[index]
		if not tier_value is Dictionary:
			return false
		var actual: Dictionary = tier_value
		var expected: Dictionary = LAUNCH_PRIMARY_TIERS[index]
		if (
			str(actual.get("tier_id", "")) != str(expected["tier_id"])
			or not _integer_matches_exactly(actual.get("minimum_frames"), int(expected["minimum_frames"]))
			or not _integer_matches_exactly(actual.get("maximum_frames"), int(expected["maximum_frames_exclusive"]) - 1)
			or not _integer_matches_exactly(actual.get("windup_frames"), int(expected["windup_frames"]))
			or not _integer_matches_exactly(actual.get("active_frames"), int(expected["active_frames"]))
			or not _integer_matches_exactly(actual.get("recovery_frames"), int(expected["recovery_frames"]))
			or not _number_matches_exactly(actual.get("damage_multiplier"), float(expected["damage_multiplier"]))
		):
			return false
	return true


func _matches_launch_payload_numbers(value: Variant, expected: Dictionary) -> bool:
	if not value is Dictionary or not (value as Dictionary).get("parameters") is Dictionary:
		return false
	var parameters: Dictionary = (value as Dictionary)["parameters"]
	for field: String in expected.keys():
		if not _number_matches_exactly(parameters.get(field), float(expected[field])):
			return false
	return true


func _matches_launch_interactions(profile: Dictionary) -> bool:
	var interactions_value: Variant = profile.get("time_interactions", {})
	var boss_value: Variant = profile.get("boss_interactions", {})
	if not interactions_value is Dictionary or not boss_value is Dictionary:
		return false
	var interactions: Dictionary = interactions_value
	var expected_ids := {
		"stop": "bow_stopped_target_burst",
		"rewind": "bow_echo_arrows",
		"accelerate": "bow_charge_speed",
		"rift": "bow_rift_penetration",
	}
	for key: String in expected_ids.keys():
		var interaction_value: Variant = interactions.get(key)
		if not interaction_value is Dictionary or str((interaction_value as Dictionary).get("interaction_id", "")) != str(expected_ids[key]):
			return false
	var boss: Dictionary = (boss_value as Dictionary).get("chrono_warden", {})
	var boss_parameters: Dictionary = boss.get("parameters", {})
	return (
		str(boss.get("type", "")) == "recovery_exposure_poise_conversion"
		and not bool(boss_parameters.get("interrupt_active_attack", true))
		and boss_parameters.get("conversion_outcomes", []) == ["recovery_extension", "exposure_extension", "poise_damage"]
	)


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
		and float(value["character_attack_scale"]) > 0.0
		and float(value["crit_chance"]) >= 0.0
		and float(value["crit_chance"]) <= 1.0
		and float(value["crit_multiplier"]) >= 1.0
	)


func _freeze_character_stats_into_plan(plan: Dictionary, adapter_snapshot: Dictionary) -> void:
	for field: String in ["character_attack_scale", "attack_speed", "crit_chance", "crit_multiplier"]:
		plan[field] = float(adapter_snapshot[field])
	var payloads: Array = plan.get("payloads", [])
	for payload_value: Variant in payloads:
		if payload_value is Dictionary and (payload_value as Dictionary).get("parameters") is Dictionary:
			_freeze_character_stats_into_parameters(
				(payload_value as Dictionary)["parameters"],
				adapter_snapshot
			)


func _freeze_character_stats_into_parameters(
	parameters: Dictionary,
	adapter_snapshot: Dictionary
) -> void:
	parameters["base_attack"] = float(adapter_snapshot["base_attack"])
	for field: String in ["character_attack_scale", "attack_speed", "crit_chance", "crit_multiplier"]:
		parameters[field] = float(adapter_snapshot[field])


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
	if not _runtime_snapshot_has_exact_fields(value):
		return false
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
	if (
		not value.get("committed_launch_definition") is Dictionary
		or not (value["committed_launch_definition"] as Dictionary).is_empty()
		or not value.get("live_launch_time_context") is Dictionary
		or not (value["live_launch_time_context"] as Dictionary).is_empty()
	):
		return false
	if typeof(value.get("adapter_active")) != TYPE_BOOL or not value.get("adapter_snapshot") is Dictionary:
		return false
	var adapter_snapshot := value["adapter_snapshot"] as Dictionary
	if not bool(_adapter.call("can_restore_runtime_snapshot", adapter_snapshot)):
		return false
	var active_token := int(value["active_token"])
	var active_phase := str(value.get("active_phase", ""))
	var active_plan: Dictionary = value["active_plan"]
	var modifier_snapshot: Dictionary = value["modifier_snapshot"]
	if active_token == 0:
		if active_phase != "READY" or bool(value["adapter_active"]) or str(adapter_snapshot.get("phase_state", "")) != "idle" or not active_plan.is_empty() or not modifier_snapshot.is_empty():
			return false
	else:
		if active_phase not in ["HOLD", "WINDUP", "ACTIVE", "RECOVERY"] or active_plan.is_empty():
			return false
		if active_phase == "HOLD":
			if bool(value["adapter_active"]) or str(adapter_snapshot.get("phase_state", "")) != "idle" or not bool(_validate_hold_skeleton(active_plan).get("ok", false)):
				return false
		else:
			var expected_state := "shot_prepared" if active_phase == "WINDUP" else "shot_released"
			var expected_shot := _profile_shot_definition(active_plan, active_token)
			if (
				not bool(value["adapter_active"])
				or str(adapter_snapshot.get("phase_state", "")) != expected_state
				or expected_shot.is_empty()
				or adapter_snapshot.get("profile_shot", {}) != expected_shot
			):
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


func _runtime_snapshot_has_exact_fields(value: Dictionary) -> bool:
	var fields: Array[String] = [
		"schema_version", "configured", "profile_id", "profile_version", "active_token",
		"active_phase", "active_plan", "modifier_snapshot", "committed_launch_definition",
		"live_launch_time_context", "adapter_active", "adapter_snapshot",
		"reward_eligible_tokens", "reward_claimed_tokens",
	]
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


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
	_committed_launch_definition.clear()
	_live_launch_time_context.clear()


func _is_configured() -> bool:
	return (
		_owner != null
		and is_instance_valid(_owner)
		and _adapter != null
		and is_instance_valid(_adapter)
		and _modifier_state != null
		and not _profile_snapshot.is_empty()
	)


func _is_launch_profile() -> bool:
	return str(_profile_snapshot.get("id", "")) == LAUNCH_PROFILE_ID


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
