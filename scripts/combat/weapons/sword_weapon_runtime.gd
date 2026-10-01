class_name SwordWeaponRuntime
extends "res://scripts/combat/weapons/weapon_runtime.gd"

const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
const PROFILE_ID := "sword_m1_v1"
const LAUNCH_PROFILE_ID := "sword_launch_v1"
const WEAPON_ID := &"sword"
const COMBO_ACTION_IDS: Array[StringName] = [&"light_1", &"light_2", &"light_3"]
const HEAVY_ACTION_ID := &"heavy"
const COMBO_RESET_FRAMES := 48
const LAUNCH_PRIMARY_HOLD_ACTION_ID := &"sword_primary_charge"
const LAUNCH_PRIMARY_ACTION_IDS: Array[StringName] = [&"light_chain", &"charged_slash"]
const LAUNCH_PRIMARY_CHARGE_FRAMES := 30
const LAUNCH_PRIMARY_MAXIMUM_HOLD_FRAMES := 600
const LAUNCH_ULTIMATE_ACTION_ID := &"primordial_edge"
const LAUNCH_ULTIMATE_HOLD_FRAMES := 60
const LAUNCH_COMBO_RESET_FRAMES := 48
const LAUNCH_RESOURCE_IDS: Array[StringName] = [&"guard", &"intent"]
const LAUNCH_ACTION_IDS: Array[StringName] = [
	&"light_chain",
	&"charged_slash",
	&"guard",
	&"counter",
	&"temporal_judgment",
	&"primordial_edge",
]
const LAUNCH_SEMANTIC_ACTION_IDS := {
	"weapon_secondary": "guard",
	"weapon_utility": "counter",
	"weapon_skill": "temporal_judgment",
}
const LAUNCH_RELEASE_ACTION_FINGERPRINTS := {
	"light_chain": "sword_launch:primary:light_chain:v1",
	"charged_slash": "sword_launch:primary:charged_slash:v1",
	"primordial_edge": "sword_launch:ultimate:primordial_edge:v1",
}
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
	&"cancel_for_gameplay_rewind",
	&"restore_gameplay_rewind_snapshot_for_rollback",
	&"gameplay_rewind_committed_payload_guard",
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
const CHARACTER_STATS_FIELDS: Array[String] = [
	"base_attack", "character_attack_scale", "attack_speed", "crit_chance", "crit_multiplier",
]
const LEGACY_REWARD_CAPABILITIES := {
	"weapon.combo_finisher_damage": {"field": "combo_finisher_multiplier_bonus", "base_value": 0.0},
	"weapon.heavy_damage": {"field": "heavy_damage_multiplier_bonus", "base_value": 0.0},
	"weapon.heavy_execute_damage": {"field": "heavy_execute_multiplier_bonus", "base_value": 0.0},
	"weapon.heavy_execute_threshold": {"field": "heavy_execute_threshold", "base_value": 0.3},
	"weapon.low_hp_damage": {"field": "low_hp_damage_multiplier_bonus", "base_value": 0.0},
}

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
var _resource_definitions: Dictionary = {}
var _resources: Dictionary = {}
var _resource_regen_frame_accumulators: Dictionary = {}
var _launch_combo_timeout_remaining: int = 0
var _last_runtime_frame: int = 0


func weapon_id() -> StringName:
	return WEAPON_ID


func bind_adapter(adapter: Node) -> bool:
	if _owner != null:
		return adapter == _adapter
	if (
		adapter == null
		or not is_instance_valid(adapter)
		or not _has_methods(adapter, REQUIRED_ADAPTER_METHODS)
		or _character_stats_snapshot(adapter).is_empty()
	):
		return false
	_adapter = adapter
	return true


func configure(owner: Node, profile: Variant, modifiers: Variant) -> bool:
	if owner == null or not is_instance_valid(owner):
		return false
	if not profile is RefCounted or not (profile as RefCounted).has_method("snapshot"):
		return false
	if not modifiers is RefCounted or not _has_methods(modifiers as RefCounted, REQUIRED_MODIFIER_METHODS):
		return false

	if _adapter == null or not is_instance_valid(_adapter) or not _has_methods(_adapter, REQUIRED_ADAPTER_METHODS):
		return false
	var profile_value: Variant = (profile as RefCounted).call("snapshot")
	if not profile_value is Dictionary:
		return false
	var next_profile := (profile_value as Dictionary).duplicate(true)
	var profile_id := str(next_profile.get("id", ""))
	if (
		profile_id not in [PROFILE_ID, LAUNCH_PROFILE_ID]
		or str(next_profile.get("weapon_id", "")) != str(WEAPON_ID)
		or str(next_profile.get("runtime_kind", "")) != str(WEAPON_ID)
		or int(next_profile.get("profile_version", 0)) != 1
	):
		return false

	var indexes := _build_profile_indexes(
		next_profile,
		LAUNCH_ACTION_IDS if profile_id == LAUNCH_PROFILE_ID else COMBO_ACTION_IDS + [HEAVY_ACTION_ID]
	)
	if not bool(indexes.get("ok", false)):
		return false
	if profile_id == PROFILE_ID and not _matches_frozen_m1_profile(indexes):
		return false
	if profile_id == LAUNCH_PROFILE_ID and not _matches_launch_profile(next_profile, indexes):
		return false
	var next_capabilities := PackedStringArray(next_profile.get("capabilities", []))
	var frozen_value: Variant = (modifiers as RefCounted).call("freeze_for_action")
	if not frozen_value is Dictionary or not _dictionary_numbers_are_finite(frozen_value as Dictionary):
		return false
	var next_resource_definitions := _build_resource_definitions(next_profile)
	if profile_id == LAUNCH_PROFILE_ID and next_resource_definitions.size() != LAUNCH_RESOURCE_IDS.size():
		return false

	_owner = owner
	_modifier_state = modifiers as RefCounted
	_profile_snapshot = next_profile
	_actions_by_id = (indexes["actions"] as Dictionary).duplicate(true)
	_payloads_by_id = (indexes["payloads"] as Dictionary).duplicate(true)
	_cues_by_id = (indexes["cues"] as Dictionary).duplicate(true)
	_capabilities = next_capabilities
	_resource_definitions = next_resource_definitions
	reset_runtime_state(&"configured")
	_sync_legacy_reward_capabilities()
	return true


func capabilities() -> PackedStringArray:
	return _capabilities.duplicate()


func plan_intent(intent: Dictionary, _context: Dictionary) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if _is_launch_profile():
		return _plan_launch_intent(intent)
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
	var character_stats := _character_stats_snapshot(_adapter)
	if character_stats.is_empty():
		return _failure(&"INVALID_CHARACTER_STATS")
	var timing_multiplier := _timing_multiplier(frozen_modifiers, character_stats)
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
		"cooldown_frames": int(action.get("cooldown_frames", 0)),
		"resource_costs": (action.get("resource_costs", {}) as Dictionary).duplicate(true),
		"modifier_snapshot": frozen_modifiers,
		"base_attack_snapshot": float(_adapter.get("base_attack")),
		"character_stats_snapshot": character_stats.duplicate(true),
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
	_freeze_character_stats_into_plan(plan, character_stats)
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
	if _is_launch_profile():
		return _commit_launch_action(plan, token)

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


func release_hold(plan: Dictionary, token: int, held_frames: int) -> Dictionary:
	if not _is_launch_profile():
		return _failure(&"UNSUPPORTED_INTENT")
	if (
		not _matches_active_action(plan, token)
		or _active_phase != &"HOLD"
		or not _is_hold_skeleton(plan)
		or held_frames < 0
	):
		return _failure(&"STALE_HOLD_RELEASE")
	var hold_action_id := StringName(str(plan.get("action_id", "")))
	var action_id: StringName
	if hold_action_id == LAUNCH_PRIMARY_HOLD_ACTION_ID:
		action_id = (
			&"charged_slash"
			if held_frames >= LAUNCH_PRIMARY_CHARGE_FRAMES
			else &"light_chain"
		)
	elif hold_action_id == LAUNCH_ULTIMATE_ACTION_ID:
		if held_frames < LAUNCH_ULTIMATE_HOLD_FRAMES:
			return _failure(&"UNDERCHARGED", {
				"held_frames": held_frames,
				"minimum_frames": LAUNCH_ULTIMATE_HOLD_FRAMES,
			})
		action_id = LAUNCH_ULTIMATE_ACTION_ID
	else:
		return _failure(&"STALE_HOLD_RELEASE")

	var built := _build_launch_action_plan(
		action_id,
		(plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true),
		float(plan.get("base_attack_snapshot", 0.0)),
		(plan.get("legacy_reward_snapshot", {}) as Dictionary).duplicate(true),
		-1,
		(plan.get("character_stats_snapshot", {}) as Dictionary).duplicate(true)
	)
	if not bool(built.get("ok", false)):
		return built
	var finalized_plan := (built["plan"] as Dictionary).duplicate(true)
	var fingerprint := str(
		(plan.get("release_action_fingerprints", {}) as Dictionary).get(str(action_id), "")
	)
	if fingerprint.is_empty():
		return _failure(&"RELEASE_ACTION_FINGERPRINT_MISSING", {"action_id": str(action_id)})
	finalized_plan["release_action_fingerprint"] = fingerprint
	var staged := _stage_launch_action(finalized_plan, token)
	if not bool(staged.get("ok", false)):
		return staged
	_active_plan = finalized_plan.duplicate(true)
	_active_phase = &"WINDUP"
	_modifier_snapshot = (finalized_plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true)
	return {
		"ok": true,
		"code": &"OK",
		"finalized_plan": finalized_plan.duplicate(true),
		"context": {"action_id": str(action_id), "held_frames": held_frames},
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
			if _is_launch_profile() and str(_active_plan.get("action_id", "")) == "light_chain":
				_combo_step = (_combo_step + 1) % COMBO_ACTION_IDS.size()
				_launch_combo_timeout_remaining = LAUNCH_COMBO_RESET_FRAMES if _combo_step != 0 else 0
			var payload_descriptors := (_active_plan.get("payloads", []) as Array).duplicate(true)
			var payload_kind := ""
			if not payload_descriptors.is_empty() and payload_descriptors[0] is Dictionary:
				payload_kind = str((payload_descriptors[0] as Dictionary).get("kind", ""))
			return [
				{
					"type": "payload_released",
					"weapon_id": str(WEAPON_ID),
					"action_id": str(_active_plan["action_id"]),
					"descriptor_id": str((_active_plan["payloads"] as Array)[0]["descriptor_id"]),
					"payload_kind": payload_kind,
					"payload_descriptors": payload_descriptors,
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
		or not _valid_restore_snapshot(runtime_snapshot)
	):
		return false
	var before := snapshot()
	var adapter_snapshot := (runtime_snapshot["adapter"] as Dictionary).duplicate(true)
	if not bool(_adapter.call(
		"restore_gameplay_rewind_snapshot_for_rollback",
		{
			"profile": adapter_snapshot,
			"committed_payload_guard": gameplay_rewind_committed_payload_guard(),
		}
	)):
		return false
	_active_token = int(runtime_snapshot["active_token"])
	_active_phase = StringName(str(runtime_snapshot["active_phase"]))
	_active_plan = (runtime_snapshot["active_plan"] as Dictionary).duplicate(true)
	_modifier_snapshot = (runtime_snapshot["modifier_snapshot"] as Dictionary).duplicate(true)
	if snapshot() == runtime_snapshot:
		return true
	_adapter.call(
		"restore_gameplay_rewind_snapshot_for_rollback",
		{
			"profile": (before["adapter"] as Dictionary).duplicate(true),
			"committed_payload_guard": gameplay_rewind_committed_payload_guard(),
		}
	)
	_active_token = int(before["active_token"])
	_active_phase = StringName(str(before["active_phase"]))
	_active_plan = (before["active_plan"] as Dictionary).duplicate(true)
	_modifier_snapshot = (before["modifier_snapshot"] as Dictionary).duplicate(true)
	return false


func gameplay_rewind_committed_payload_guard() -> Dictionary:
	var value: Variant = _adapter.call("gameplay_rewind_committed_payload_guard")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func finish_action(token: int) -> void:
	if token <= 0 or token != _active_token:
		return
	_adapter.call("finish_attack")
	_clear_active_action()


func apply_modifier(effect_id: StringName, value: Variant) -> bool:
	if _modifier_state == null or not _capabilities.has(str(effect_id)):
		return false
	var applied := bool(_modifier_state.call("apply", effect_id, value))
	if applied:
		_sync_legacy_reward_capabilities()
	return applied


func reset_combo() -> void:
	_combo_step = 0
	_launch_combo_timeout_remaining = 0
	if _adapter != null:
		_adapter.call("reset_combo")


func combo_step() -> int:
	return _combo_step


func advance_runtime_frame(coordinator_frame: int) -> Array[Dictionary]:
	if not _is_launch_profile() or coordinator_frame <= _last_runtime_frame:
		return []
	var frame_count := coordinator_frame - _last_runtime_frame
	_last_runtime_frame = coordinator_frame
	if _adapter.has_method("advance_launch_state"):
		_adapter.call("advance_launch_state", frame_count)
	_sync_launch_adapter_effects()
	_regenerate_launch_resources(frame_count)
	if _active_token == 0 and _combo_step != 0 and _launch_combo_timeout_remaining > 0:
		_launch_combo_timeout_remaining = maxi(0, _launch_combo_timeout_remaining - frame_count)
		if _launch_combo_timeout_remaining == 0:
			reset_combo()
	return []


func reset_runtime_state(_reason: StringName) -> void:
	if _adapter != null:
		if _adapter.has_method("reset_runtime_state"):
			_adapter.call("reset_runtime_state")
		else:
			_adapter.call("cancel_attack")
			_adapter.call("reset_combo")
	_combo_step = 0
	_launch_combo_timeout_remaining = 0
	_last_runtime_frame = 0
	if _is_launch_profile():
		_reset_launch_resources()
	else:
		_resources.clear()
		_resource_regen_frame_accumulators.clear()
	_clear_active_action()


func snapshot() -> Dictionary:
	_sync_launch_adapter_effects()
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"configured": _is_configured(),
		"profile_id": str(_profile_snapshot.get("id", "")),
		"profile_version": int(_profile_snapshot.get("profile_version", 0)),
		"combo_step": _combo_step,
		"launch_combo_step": _combo_step if _is_launch_profile() else 0,
		"combo_timeout_remaining": _launch_combo_timeout_remaining,
		"last_runtime_frame": _last_runtime_frame,
		"resources": _resource_snapshot(),
		"resource_regen_frame_accumulators": _resource_regen_frame_accumulators.duplicate(true),
		"active_token": _active_token,
		"active_phase": str(_active_phase),
		"active_plan": _active_plan.duplicate(true),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
		"adapter": _adapter_snapshot(),
		"launch_adapter": (
			_adapter.call("launch_runtime_snapshot")
			if _is_launch_profile() and _adapter.has_method("launch_runtime_snapshot")
			else {}
		),
	}


func restore_snapshot(runtime_snapshot: Dictionary) -> bool:
	if not _is_configured() or not _valid_restore_snapshot(runtime_snapshot):
		return false
	var previous := snapshot()
	if not _apply_restore_snapshot(runtime_snapshot):
		if not _apply_restore_snapshot(previous):
			reset_runtime_state(&"restore_rollback_failed")
		return false
	if snapshot() != runtime_snapshot:
		if not _apply_restore_snapshot(previous):
			reset_runtime_state(&"restore_mismatch_rollback_failed")
		return false
	return true


func validate_coordinator_snapshot(coordinator_snapshot: Dictionary) -> bool:
	if (
		typeof(coordinator_snapshot.get("token")) != TYPE_INT
		or typeof(coordinator_snapshot.get("generation")) != TYPE_INT
		or not coordinator_snapshot.get("runtime") is Dictionary
	):
		return false
	var token := int(coordinator_snapshot["token"])
	var generation := int(coordinator_snapshot["generation"])
	var runtime_snapshot: Dictionary = coordinator_snapshot["runtime"]
	if int(runtime_snapshot.get("active_token", -1)) != token:
		return false
	var adapter_value: Variant = runtime_snapshot.get("adapter")
	if not adapter_value is Dictionary:
		return false
	var adapter: Dictionary = adapter_value
	var damage_token := int(adapter.get("damage_action_token", 0))
	var damage_generation := int(adapter.get("damage_attack_generation", 0))
	if (damage_token == 0) != (damage_generation == 0):
		return false
	if damage_token > 0 and (damage_token != token or damage_generation != generation):
		return false
	return true


func _apply_restore_snapshot(runtime_snapshot: Dictionary) -> bool:
	var next_adapter: Dictionary = runtime_snapshot["adapter"]
	var launch_adapter: Dictionary = runtime_snapshot.get("launch_adapter", {})
	if (
		_adapter.has_method("can_restore_profile_runtime_snapshot")
		and not bool(_adapter.call("can_restore_profile_runtime_snapshot", next_adapter.duplicate(true)))
	):
		return false
	if (
		_is_launch_profile()
		and _adapter.has_method("can_restore_launch_runtime_snapshot")
		and not bool(_adapter.call("can_restore_launch_runtime_snapshot", launch_adapter.duplicate(true)))
	):
		return false
	var live_base_attack := float(_adapter.get("base_attack"))
	var live_rewards := _legacy_reward_snapshot()
	var active_plan: Dictionary = runtime_snapshot["active_plan"]
	var modifier_snapshot: Dictionary = runtime_snapshot["modifier_snapshot"]
	if bool(next_adapter.get("attacking", false)):
		_adapter.set(
			"base_attack",
			float(active_plan.get("base_attack_snapshot", live_base_attack))
			* float(modifier_snapshot.get("weapon.damage", 1.0))
		)
		_apply_legacy_reward_snapshot(active_plan.get("legacy_reward_snapshot", {}))
	var adapter_restored := (
		bool(_adapter.call("restore_profile_runtime_snapshot", next_adapter.duplicate(true)))
		if _adapter.has_method("restore_profile_runtime_snapshot")
		else false
	)
	_adapter.set("base_attack", live_base_attack)
	_apply_legacy_reward_snapshot(live_rewards)
	if not adapter_restored:
		return false
	if _is_launch_profile() and _adapter.has_method("restore_launch_runtime_snapshot"):
		if not bool(_adapter.call("restore_launch_runtime_snapshot", launch_adapter.duplicate(true))):
			return false
	_combo_step = int(runtime_snapshot["combo_step"])
	_launch_combo_timeout_remaining = int(runtime_snapshot.get("combo_timeout_remaining", 0))
	_last_runtime_frame = int(runtime_snapshot.get("last_runtime_frame", 0))
	_resources = _resource_values_from_snapshot(runtime_snapshot.get("resources", {}))
	_resource_regen_frame_accumulators = (
		(runtime_snapshot.get("resource_regen_frame_accumulators", {}) as Dictionary).duplicate(true)
	)
	_active_token = int(runtime_snapshot["active_token"])
	_active_phase = StringName(str(runtime_snapshot["active_phase"]))
	_active_plan = active_plan.duplicate(true)
	_modifier_snapshot = modifier_snapshot.duplicate(true)
	return true


func presentation_snapshot() -> Dictionary:
	_sync_launch_adapter_effects()
	var facing := Vector2.RIGHT
	if _adapter is Node2D:
		facing = Vector2.RIGHT.rotated((_adapter as Node2D).global_rotation)
	return {
		"weapon_id": str(WEAPON_ID),
		"profile_id": str(_profile_snapshot.get("id", "")),
		"profile_version": int(_profile_snapshot.get("profile_version", 0)),
		"action_id": str(_active_plan.get("action_id", "")),
		"phase": str(_active_phase),
		"combo_step": _combo_step,
		"combo_reset_frames": COMBO_RESET_FRAMES,
		"combo_timeout_remaining": _launch_combo_timeout_remaining,
		"resources": _resource_snapshot(),
		"token": _active_token,
		"facing": facing,
		"cue_id": str((_active_plan.get("cue", {}) as Dictionary).get("cue_id", "")),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
		"launch_mechanics": (
			_adapter.call("launch_runtime_snapshot")
			if _is_launch_profile() and _adapter.has_method("launch_runtime_snapshot")
			else {}
		),
	}


func _plan_launch_intent(intent: Dictionary) -> Dictionary:
	_sync_launch_adapter_effects()
	var semantic := StringName(str(intent.get("id", "")))
	var edge := StringName(str(intent.get("edge", "")))
	if semantic == &"weapon_primary":
		if edge == &"pressed":
			return _build_launch_hold_plan(
				LAUNCH_PRIMARY_HOLD_ACTION_ID,
				semantic,
				0,
				LAUNCH_PRIMARY_MAXIMUM_HOLD_FRAMES,
				LAUNCH_PRIMARY_CHARGE_FRAMES,
				LAUNCH_PRIMARY_ACTION_IDS,
				{}
			)
		if edge == &"released":
			if typeof(intent.get("held_frames")) != TYPE_INT or int(intent["held_frames"]) < 0:
				return _failure(&"INVALID_HELD_FRAMES")
			return _build_launch_action_plan(
				&"charged_slash" if int(intent["held_frames"]) >= LAUNCH_PRIMARY_CHARGE_FRAMES else &"light_chain"
			)
		return _failure(&"UNSUPPORTED_EDGE")
	if semantic == &"weapon_ultimate":
		if edge == &"pressed":
			var ultimate_action: Dictionary = _actions_by_id.get(str(LAUNCH_ULTIMATE_ACTION_ID), {})
			return _build_launch_hold_plan(
				LAUNCH_ULTIMATE_ACTION_ID,
				semantic,
				LAUNCH_ULTIMATE_HOLD_FRAMES,
				LAUNCH_ULTIMATE_HOLD_FRAMES,
				LAUNCH_ULTIMATE_HOLD_FRAMES,
				[LAUNCH_ULTIMATE_ACTION_ID],
				(ultimate_action.get("resource_costs", {}) as Dictionary).duplicate(true)
			)
		if edge == &"released":
			if typeof(intent.get("held_frames")) != TYPE_INT or int(intent["held_frames"]) < LAUNCH_ULTIMATE_HOLD_FRAMES:
				return _failure(&"UNDERCHARGED", {
					"held_frames": int(intent.get("held_frames", 0)),
					"minimum_frames": LAUNCH_ULTIMATE_HOLD_FRAMES,
				})
			return _build_launch_action_plan(LAUNCH_ULTIMATE_ACTION_ID)
		return _failure(&"UNSUPPORTED_EDGE")
	if edge != &"pressed":
		return _failure(&"UNSUPPORTED_EDGE")
	var action_id := StringName(str(LAUNCH_SEMANTIC_ACTION_IDS.get(str(semantic), "")))
	if action_id == &"":
		return _failure(&"UNSUPPORTED_INTENT")
	var action: Dictionary = _actions_by_id.get(str(action_id), {})
	var availability := _validate_owned_resource_costs(action.get("resource_costs", {}))
	if not bool(availability.get("ok", false)):
		return availability
	return _build_launch_action_plan(action_id)


func _build_launch_hold_plan(
	action_id: StringName,
	semantic: StringName,
	minimum_frames: int,
	maximum_frames: int,
	charge_complete_frames: int,
	allowed_release_ids: Array[StringName],
	resource_costs: Dictionary
) -> Dictionary:
	var modifiers_result := _frozen_modifier_snapshot()
	if not bool(modifiers_result.get("ok", false)):
		return modifiers_result
	var character_stats := _character_stats_snapshot(_adapter)
	if character_stats.is_empty():
		return _failure(&"INVALID_CHARACTER_STATS")
	var fingerprints: Dictionary = {}
	var allowed_ids: Array[String] = []
	for release_id: StringName in allowed_release_ids:
		var fingerprint := str(LAUNCH_RELEASE_ACTION_FINGERPRINTS.get(str(release_id), ""))
		if fingerprint.is_empty():
			return _failure(&"RELEASE_ACTION_FINGERPRINT_MISSING", {"action_id": str(release_id)})
		allowed_ids.append(str(release_id))
		fingerprints[str(release_id)] = fingerprint
	var plan := {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(action_id),
		"profile_id": LAUNCH_PROFILE_ID,
		"profile_version": 1,
		"semantic_action": str(semantic),
		"activation_mode": "release",
		"buffer_frames": 8,
		"cooldown_frames": 0,
		"resource_costs": resource_costs.duplicate(true),
		"modifier_snapshot": (modifiers_result["modifiers"] as Dictionary).duplicate(true),
		"base_attack_snapshot": float(_adapter.get("base_attack")),
		"character_stats_snapshot": character_stats.duplicate(true),
		"legacy_reward_snapshot": _legacy_reward_snapshot(),
		"phases": [{
			"phase": "HOLD",
			"duration_frames": maximum_frames,
			"minimum_hold_frames": minimum_frames,
			"charge_complete_frames": charge_complete_frames,
			"movement_multiplier": 0.2 if action_id == LAUNCH_PRIMARY_HOLD_ACTION_ID else 0.0,
		}],
		"payloads": [],
		"cue": {},
		"allowed_release_action_ids": allowed_ids,
		"release_action_fingerprints": fingerprints,
	}
	_freeze_character_stats_into_plan(plan, character_stats)
	var validation: Dictionary = WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	return {"ok": true, "code": &"OK", "plan": plan, "context": {}} if bool(validation.get("ok", false)) else validation


func _build_launch_action_plan(
	action_id: StringName,
	frozen_modifiers: Dictionary = {},
	base_attack_snapshot: float = -1.0,
	legacy_reward_snapshot: Dictionary = {},
	combo_step_override: int = -1,
	character_stats_snapshot: Dictionary = {}
) -> Dictionary:
	var action: Dictionary = _copy_indexed(_actions_by_id, action_id)
	if action.is_empty():
		return _failure(&"ACTION_NOT_FOUND", {"action_id": str(action_id)})
	var payload: Dictionary = _copy_indexed(
		_payloads_by_id,
		StringName(str(action.get("payload_id", "")))
	)
	var cue: Dictionary = _copy_indexed(_cues_by_id, StringName(str(action.get("cue_id", ""))))
	if payload.is_empty() or cue.is_empty():
		return _failure(&"PAYLOAD_PROFILE_INVALID")
	var modifiers := frozen_modifiers.duplicate(true)
	if modifiers.is_empty():
		var modifiers_result := _frozen_modifier_snapshot()
		if not bool(modifiers_result.get("ok", false)):
			return modifiers_result
		modifiers = (modifiers_result["modifiers"] as Dictionary).duplicate(true)
	var character_stats := character_stats_snapshot.duplicate(true)
	if character_stats.is_empty():
		character_stats = _character_stats_snapshot(_adapter)
	if not _valid_character_stats_snapshot(character_stats):
		return _failure(&"INVALID_CHARACTER_STATS")
	var timing_multiplier := _timing_multiplier(modifiers, character_stats)
	var recovery_frames := _scaled_frames(action.get("recovery_frames", 0), timing_multiplier)
	var recovery_phase := {
		"phase": "RECOVERY",
		"duration_frames": recovery_frames,
		"movement_multiplier": float(action.get("movement_multiplier", 1.0)),
	}
	var cancel_value: Variant = action.get("cancel_from_frame")
	if typeof(cancel_value) == TYPE_INT:
		recovery_phase["cancel_from_frame"] = mini(
			_scaled_frames(cancel_value, timing_multiplier),
			recovery_frames - 1
		)
	var plan := {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(action_id),
		"profile_id": LAUNCH_PROFILE_ID,
		"profile_version": 1,
		"semantic_action": str(action.get("semantic_action", "")),
		"activation_mode": str(action.get("activation_mode", "")),
		"buffer_frames": int(action.get("buffer_frames", 8)),
		"cooldown_frames": int(action.get("cooldown_frames", 0)),
		"resource_costs": (action.get("resource_costs", {}) as Dictionary).duplicate(true),
		"modifier_snapshot": modifiers,
		"base_attack_snapshot": (
			base_attack_snapshot
			if base_attack_snapshot >= 0.0
			else float(_adapter.get("base_attack"))
		),
		"character_stats_snapshot": character_stats.duplicate(true),
		"legacy_reward_snapshot": (
			legacy_reward_snapshot.duplicate(true)
			if not legacy_reward_snapshot.is_empty()
			else _legacy_reward_snapshot()
		),
		"phases": [
			{
				"phase": "WINDUP",
				"duration_frames": _scaled_frames(action.get("windup_frames", 0), timing_multiplier),
				"movement_multiplier": float(action.get("movement_multiplier", 1.0)),
			},
			{
				"phase": "ACTIVE",
				"duration_frames": _scaled_frames(action.get("active_frames", 0), timing_multiplier),
				"movement_multiplier": float(action.get("movement_multiplier", 1.0)),
			},
			recovery_phase,
		],
		"payloads": [{
			"descriptor_id": str(payload.get("payload_id", "")),
			"kind": str(payload.get("kind", "")),
			"parameters": (payload.get("parameters", {}) as Dictionary).duplicate(true),
		}],
		"cue": cue.duplicate(true),
	}
	_freeze_character_stats_into_plan(plan, character_stats)
	if action_id == &"light_chain":
		plan["combo_step_before"] = combo_step_override if combo_step_override >= 0 else _combo_step
		plan["combo_reset_frames"] = LAUNCH_COMBO_RESET_FRAMES
	var validation: Dictionary = WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	return {"ok": true, "code": &"OK", "plan": plan, "context": {}} if bool(validation.get("ok", false)) else validation


func _frozen_modifier_snapshot() -> Dictionary:
	var value: Variant = _modifier_state.call("freeze_for_action")
	if not value is Dictionary or not _dictionary_numbers_are_finite(value):
		return _failure(&"INVALID_MODIFIER_SNAPSHOT")
	return {"ok": true, "code": &"OK", "modifiers": (value as Dictionary).duplicate(true)}


func _commit_launch_action(plan: Dictionary, token: int) -> Dictionary:
	_sync_launch_adapter_effects()
	var resource_before := _resources.duplicate(true)
	var spend_result := _spend_owned_resource_costs(plan.get("resource_costs", {}))
	if not bool(spend_result.get("ok", false)):
		return spend_result
	if _is_hold_skeleton(plan):
		_active_token = token
		_active_phase = &"HOLD"
		_active_plan = plan.duplicate(true)
		_modifier_snapshot = (plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true)
		return {"ok": true, "code": &"OK", "context": {"action_id": str(plan["action_id"])}}
	var staged := _stage_launch_action(plan, token)
	if not bool(staged.get("ok", false)):
		_resources = resource_before
		return staged
	_active_token = token
	_active_phase = &"WINDUP"
	_active_plan = plan.duplicate(true)
	_modifier_snapshot = (plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true)
	return {"ok": true, "code": &"OK", "context": {"action_id": str(plan["action_id"])}}


func _stage_launch_action(plan: Dictionary, _token: int) -> Dictionary:
	var adapter_before := _adapter_snapshot()
	var profile_attack := _profile_attack_definition(plan)
	if profile_attack.is_empty():
		return _failure(&"PAYLOAD_PROFILE_INVALID")
	var committed_value: Variant = _adapter.call("begin_profile_attack", profile_attack.duplicate(true))
	if not committed_value is Dictionary or (committed_value as Dictionary).is_empty():
		_restore_adapter_snapshot(adapter_before)
		return _failure(&"PAYLOAD_CONSTRUCTION_FAILED")
	if not _adapter_definition_matches_plan(committed_value as Dictionary, plan):
		_restore_adapter_snapshot(adapter_before)
		return _failure(&"PAYLOAD_PROFILE_MISMATCH")
	return {"ok": true, "code": &"OK", "context": {}}


func _launch_hold_plan_matches_profile(plan: Dictionary) -> bool:
	if (
		int(plan.get("buffer_frames", -1)) != 8
		or int(plan.get("cooldown_frames", -1)) != 0
		or str(plan.get("activation_mode", "")) != "release"
		or not plan.get("modifier_snapshot") is Dictionary
		or not _dictionary_numbers_are_finite(plan.get("modifier_snapshot"))
		or typeof(plan.get("base_attack_snapshot")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(plan.get("base_attack_snapshot", NAN)))
		or not _valid_character_stats_snapshot(plan.get("character_stats_snapshot", {}))
		or not plan.get("legacy_reward_snapshot") is Dictionary
		or not _dictionary_numbers_are_finite(plan.get("legacy_reward_snapshot"))
		or not (plan.get("payloads", []) as Array).is_empty()
		or not (plan.get("cue", {}) as Dictionary).is_empty()
	):
		return false
	var phases_value: Variant = plan.get("phases", [])
	if not phases_value is Array or (phases_value as Array).size() != 1:
		return false
	var phase: Dictionary = (phases_value as Array)[0]
	var action_id := StringName(str(plan.get("action_id", "")))
	var expected_allowed: Array[String] = []
	var expected_fingerprints: Dictionary = {}
	var expected_resource_costs: Dictionary = {}
	var expected_semantic := ""
	var expected_minimum := 0
	var expected_maximum := 0
	var expected_charge_complete := 0
	var expected_movement := 0.0
	if action_id == LAUNCH_PRIMARY_HOLD_ACTION_ID:
		expected_allowed = ["light_chain", "charged_slash"]
		expected_fingerprints = {
			"light_chain": LAUNCH_RELEASE_ACTION_FINGERPRINTS["light_chain"],
			"charged_slash": LAUNCH_RELEASE_ACTION_FINGERPRINTS["charged_slash"],
		}
		expected_semantic = "weapon_primary"
		expected_minimum = 0
		expected_maximum = LAUNCH_PRIMARY_MAXIMUM_HOLD_FRAMES
		expected_charge_complete = LAUNCH_PRIMARY_CHARGE_FRAMES
		expected_movement = 0.2
	elif action_id == LAUNCH_ULTIMATE_ACTION_ID:
		expected_allowed = ["primordial_edge"]
		expected_fingerprints = {
			"primordial_edge": LAUNCH_RELEASE_ACTION_FINGERPRINTS["primordial_edge"],
		}
		expected_resource_costs = ((_actions_by_id["primordial_edge"] as Dictionary).get("resource_costs", {}) as Dictionary).duplicate(true)
		expected_semantic = "weapon_ultimate"
		expected_minimum = LAUNCH_ULTIMATE_HOLD_FRAMES
		expected_maximum = LAUNCH_ULTIMATE_HOLD_FRAMES
		expected_charge_complete = LAUNCH_ULTIMATE_HOLD_FRAMES
		expected_movement = 0.0
	else:
		return false
	return (
		str(plan.get("semantic_action", "")) == expected_semantic
		and plan.get("resource_costs", {}) == expected_resource_costs
		and plan.get("allowed_release_action_ids", []) == expected_allowed
		and plan.get("release_action_fingerprints", {}) == expected_fingerprints
		and str(phase.get("phase", "")) == "HOLD"
		and int(phase.get("duration_frames", -1)) == expected_maximum
		and int(phase.get("minimum_hold_frames", -1)) == expected_minimum
		and int(phase.get("charge_complete_frames", -1)) == expected_charge_complete
		and _number_matches_exactly(phase.get("movement_multiplier"), expected_movement)
	)


func _launch_final_plan_matches_profile(plan: Dictionary, action_id: StringName) -> bool:
	if (
		not plan.get("modifier_snapshot") is Dictionary
		or not _dictionary_numbers_are_finite(plan.get("modifier_snapshot"))
		or typeof(plan.get("base_attack_snapshot")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(plan.get("base_attack_snapshot", NAN)))
		or not _valid_character_stats_snapshot(plan.get("character_stats_snapshot", {}))
		or not plan.get("legacy_reward_snapshot") is Dictionary
		or not _dictionary_numbers_are_finite(plan.get("legacy_reward_snapshot"))
	):
		return false
	var expected_result := _build_launch_action_plan(
		action_id,
		(plan["modifier_snapshot"] as Dictionary).duplicate(true),
		float(plan["base_attack_snapshot"]),
		(plan["legacy_reward_snapshot"] as Dictionary).duplicate(true),
		int(plan.get("combo_step_before", -1)) if action_id == &"light_chain" else -1,
		(plan["character_stats_snapshot"] as Dictionary).duplicate(true)
	)
	if not bool(expected_result.get("ok", false)):
		return false
	var comparable := plan.duplicate(true)
	comparable.erase("release_action_fingerprint")
	return comparable == (expected_result["plan"] as Dictionary)


func _m1_plan_matches_profile(plan: Dictionary, action_id: StringName) -> bool:
	var character_stats_value: Variant = plan.get("character_stats_snapshot", {})
	if not _valid_character_stats_snapshot(character_stats_value):
		return false
	var character_stats := character_stats_value as Dictionary
	if not _number_matches_exactly(
		plan.get("base_attack_snapshot"),
		character_stats.get("base_attack")
	):
		return false
	var modifier_value: Variant = plan.get("modifier_snapshot", {})
	if (
		not modifier_value is Dictionary
		or not _dictionary_numbers_are_finite(modifier_value as Dictionary)
	):
		return false
	var legacy_rewards_value: Variant = plan.get("legacy_reward_snapshot", {})
	if (
		not legacy_rewards_value is Dictionary
		or not _dictionary_numbers_are_finite(legacy_rewards_value as Dictionary)
	):
		return false
	var legacy_rewards := (legacy_rewards_value as Dictionary).duplicate(true)

	var action := _copy_indexed(_actions_by_id, action_id)
	if action.is_empty():
		return false
	var payload_id := StringName(str(action.get("payload_id", "")))
	var payload := _copy_indexed(_payloads_by_id, payload_id)
	var cue := _copy_indexed(
		_cues_by_id,
		StringName(str(action.get("cue_id", "")))
	)
	if payload.is_empty() or cue.is_empty():
		return false
	var frozen_modifiers := (modifier_value as Dictionary).duplicate(true)
	var timing_multiplier := _timing_multiplier(frozen_modifiers, character_stats)
	var recovery_frames := _scaled_action_frames(
		action_id,
		&"recovery",
		timing_multiplier
	)
	var expected := {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(action_id),
		"profile_id": str(_profile_snapshot["id"]),
		"profile_version": int(_profile_snapshot["profile_version"]),
		"semantic_action": "weapon_secondary" if action_id == HEAVY_ACTION_ID else "weapon_primary",
		"heavy": action_id == HEAVY_ACTION_ID,
		"combo_step_before": _combo_step,
		"combo_reset_frames": COMBO_RESET_FRAMES,
		"buffer_frames": int(action.get("buffer_frames", 12)),
		"cooldown_frames": int(action.get("cooldown_frames", 0)),
		"resource_costs": (action.get("resource_costs", {}) as Dictionary).duplicate(true),
		"modifier_snapshot": frozen_modifiers,
		"base_attack_snapshot": float(character_stats["base_attack"]),
		"character_stats_snapshot": character_stats.duplicate(true),
		"legacy_reward_snapshot": legacy_rewards,
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
				"cancel_from_frame": mini(
					_scaled_action_frames(action_id, &"cancel", timing_multiplier),
					recovery_frames - 1
				),
				"movement_multiplier": float(action.get("movement_multiplier", 1.0)),
			},
		],
		"payloads": [{
			"descriptor_id": str(payload_id),
			"kind": str(payload.get("kind", "")),
			"parameters": (payload.get("parameters", {}) as Dictionary).duplicate(true),
		}],
	}
	_freeze_character_stats_into_plan(expected, character_stats)
	return plan == expected


func _validate_commit_plan(plan: Dictionary) -> Dictionary:
	var contract_result: Dictionary = WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	if not bool(contract_result.get("ok", false)):
		return contract_result
	if (
		str(plan.get("profile_id", "")) != str(_profile_snapshot.get("id", ""))
		or int(plan.get("profile_version", 0)) != int(_profile_snapshot.get("profile_version", 0))
	):
		return _failure(&"PROFILE_MISMATCH")
	if _is_launch_profile():
		if _is_hold_skeleton(plan):
			if not _launch_hold_plan_matches_profile(plan):
				return _failure(&"ACTION_PROFILE_MISMATCH")
			return {"ok": true, "code": &"OK", "context": {}}
		var action_id := StringName(str(plan.get("action_id", "")))
		if action_id not in LAUNCH_ACTION_IDS:
			return _failure(&"ACTION_ID_MISMATCH")
		if not _launch_final_plan_matches_profile(plan, action_id):
			return _failure(&"ACTION_PROFILE_MISMATCH")
		return {"ok": true, "code": &"OK", "context": {}}
	if int(plan.get("combo_step_before", -1)) != _combo_step:
		return _failure(&"STALE_COMBO_PLAN")
	var expected_action := (
		HEAVY_ACTION_ID
		if bool(plan.get("heavy", false))
		else COMBO_ACTION_IDS[_combo_step]
	)
	if StringName(str(plan.get("action_id", ""))) != expected_action:
		return _failure(&"ACTION_ID_MISMATCH")
	if not _m1_plan_matches_profile(plan, expected_action):
		return _failure(&"ACTION_PROFILE_MISMATCH")
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


func _build_resource_definitions(profile: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for definition_value: Variant in profile.get("resources", []):
		if not definition_value is Dictionary:
			return {}
		var definition: Dictionary = definition_value
		var resource_id := str(definition.get("resource_id", ""))
		if resource_id.is_empty() or result.has(resource_id):
			return {}
		var minimum := float(definition.get("minimum", NAN))
		var maximum := float(definition.get("maximum", NAN))
		var initial := float(definition.get("initial", NAN))
		var regen := float(definition.get("regen_per_second", NAN))
		if (
			not is_finite(minimum)
			or not is_finite(maximum)
			or not is_finite(initial)
			or not is_finite(regen)
			or maximum < minimum
			or initial < minimum
			or initial > maximum
			or regen < 0.0
		):
			return {}
		result[resource_id] = {
			"minimum": minimum,
			"maximum": maximum,
			"initial": initial,
			"regen_per_second": regen,
		}
	return result


func _reset_launch_resources() -> void:
	_resources.clear()
	_resource_regen_frame_accumulators.clear()
	for resource_id_value: Variant in _resource_definitions.keys():
		var resource_id := str(resource_id_value)
		var definition: Dictionary = _resource_definitions[resource_id]
		_resources[resource_id] = float(definition["initial"])
		_resource_regen_frame_accumulators[resource_id] = 0


func _resource_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for resource_id_value: Variant in _resource_definitions.keys():
		var resource_id := str(resource_id_value)
		var definition: Dictionary = _resource_definitions[resource_id]
		result[resource_id] = {
			"minimum": float(definition["minimum"]),
			"maximum": float(definition["maximum"]),
			"current": float(_resources.get(resource_id, definition["initial"])),
			"regen_per_second": float(definition["regen_per_second"]),
		}
	return result


func _resource_values_from_snapshot(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary:
		return result
	for resource_id_value: Variant in _resource_definitions.keys():
		var resource_id := str(resource_id_value)
		var state_value: Variant = (value as Dictionary).get(resource_id)
		if state_value is Dictionary:
			result[resource_id] = float((state_value as Dictionary).get("current", 0.0))
	return result


func _validate_owned_resource_costs(costs_value: Variant) -> Dictionary:
	if not costs_value is Dictionary:
		return _failure(&"INVALID_RESOURCE_COSTS")
	for resource_id: StringName in LAUNCH_RESOURCE_IDS:
		var cost_value: Variant = (costs_value as Dictionary).get(str(resource_id), 0.0)
		if typeof(cost_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(cost_value)) or float(cost_value) < 0.0:
			return _failure(&"INVALID_RESOURCE_COSTS")
		var available := float(_resources.get(str(resource_id), 0.0))
		if available < float(cost_value):
			return _failure(&"INSUFFICIENT_RESOURCE", {
				"resource_id": str(resource_id),
				"required": float(cost_value),
				"available": available,
			})
	return {"ok": true, "code": &"OK", "context": {}}


func _spend_owned_resource_costs(costs_value: Variant) -> Dictionary:
	var validation := _validate_owned_resource_costs(costs_value)
	if not bool(validation.get("ok", false)):
		return validation
	var costs: Dictionary = costs_value
	for resource_id: StringName in LAUNCH_RESOURCE_IDS:
		var cost := float(costs.get(str(resource_id), 0.0))
		if cost > 0.0:
			_resources[str(resource_id)] = float(_resources[str(resource_id)]) - cost
	return {"ok": true, "code": &"OK", "context": {}}


func _regenerate_launch_resources(frame_count: int) -> void:
	var ticks_per_second := maxi(1, Engine.physics_ticks_per_second)
	for resource_id_value: Variant in _resource_definitions.keys():
		var resource_id := str(resource_id_value)
		var definition: Dictionary = _resource_definitions[resource_id]
		var regen := float(definition["regen_per_second"])
		if regen <= 0.0 or float(_resources.get(resource_id, 0.0)) >= float(definition["maximum"]):
			continue
		var accumulated := int(_resource_regen_frame_accumulators.get(resource_id, 0)) + frame_count
		var elapsed_seconds := accumulated / ticks_per_second
		_resource_regen_frame_accumulators[resource_id] = accumulated % ticks_per_second
		if elapsed_seconds <= 0:
			continue
		_resources[resource_id] = minf(
			float(definition["maximum"]),
			float(_resources.get(resource_id, definition["initial"])) + regen * elapsed_seconds
		)


func _sync_launch_adapter_effects() -> void:
	if not _is_launch_profile() or _adapter == null or not _adapter.has_method("drain_launch_effect_events"):
		return
	var events_value: Variant = _adapter.call("drain_launch_effect_events")
	if not events_value is Array:
		return
	for event_value: Variant in events_value as Array:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		if str(event.get("type", "")) != "guard_resolved":
			continue
		var definition: Dictionary = _resource_definitions.get("intent", {})
		if definition.is_empty():
			continue
		_resources["intent"] = clampf(
			float(_resources.get("intent", definition["initial"])) + maxf(0.0, float(event.get("intent_gain", 0.0))),
			float(definition["minimum"]),
			float(definition["maximum"])
		)


func _build_profile_indexes(profile: Dictionary, required_actions: Array) -> Dictionary:
	var actions: Dictionary = {}
	for action_value: Variant in profile.get("actions", []):
		if not action_value is Dictionary:
			return {"ok": false}
		var action: Dictionary = action_value
		var action_id := str(action.get("action_id", ""))
		if action_id.is_empty() or actions.has(action_id):
			return {"ok": false}
		actions[action_id] = action.duplicate(true)
	for required_action_value: Variant in required_actions:
		if not actions.has(str(required_action_value)):
			return {"ok": false}

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

	for action_value: Variant in actions.values():
		var action: Dictionary = action_value
		if not payloads.has(str(action.get("payload_id", ""))):
			return {"ok": false}
		if not cues.has(str(action.get("cue_id", ""))):
			return {"ok": false}
	return {"ok": true, "actions": actions, "payloads": payloads, "cues": cues}


func _matches_launch_profile(profile: Dictionary, indexes: Dictionary) -> bool:
	if (
		str(profile.get("id", "")) != LAUNCH_PROFILE_ID
		or str(profile.get("weapon_id", "")) != str(WEAPON_ID)
		or str(profile.get("runtime_kind", "")) != str(WEAPON_ID)
		or int(profile.get("profile_version", 0)) != 1
		or not _same_string_set(profile.get("capabilities", []), [
			"weapon.attack_speed",
			"weapon.charge_rate",
			"weapon.combo_finisher_damage",
			"weapon.damage",
			"weapon.heavy_damage",
			"weapon.heavy_execute_damage",
			"weapon.heavy_execute_threshold",
			"weapon.low_hp_damage",
			"weapon.status_duration",
		])
	):
		return false
	var actions: Dictionary = indexes.get("actions", {})
	var payloads: Dictionary = indexes.get("payloads", {})
	var cues: Dictionary = indexes.get("cues", {})
	if (
		actions.size() != LAUNCH_ACTION_IDS.size()
		or payloads.size() != LAUNCH_ACTION_IDS.size()
		or cues.size() != LAUNCH_ACTION_IDS.size()
		or not _matches_launch_resources(profile.get("resources", []))
	):
		return false
	var contracts := {
		"light_chain": ["weapon_primary", "press", 5, 5, 10, 5, "sword_launch_light", "sword_launch_light_active"],
		"charged_slash": ["weapon_primary", "release", 4, 8, 22, 13, "sword_launch_charge", "sword_launch_charge_active"],
		"guard": ["weapon_secondary", "press", 2, 12, 8, 4, "sword_guard", "sword_guard_start"],
		"counter": ["weapon_utility", "press", 3, 6, 12, 7, "sword_counter", "sword_counter_active"],
		"temporal_judgment": ["weapon_skill", "press", 10, 8, 18, 12, "sword_skill_zone", "sword_skill_active"],
		"primordial_edge": ["weapon_ultimate", "release", 18, 12, 30, -1, "sword_ultimate_wave", "sword_ultimate_active"],
	}
	for action_id_value: Variant in contracts.keys():
		var action_id := str(action_id_value)
		var expected: Array = contracts[action_id]
		var action_value: Variant = actions.get(action_id)
		if not action_value is Dictionary:
			return false
		var action: Dictionary = action_value
		if (
			str(action.get("semantic_action", "")) != str(expected[0])
			or str(action.get("activation_mode", "")) != str(expected[1])
			or int(action.get("windup_frames", -1)) != int(expected[2])
			or int(action.get("active_frames", -1)) != int(expected[3])
			or int(action.get("recovery_frames", -1)) != int(expected[4])
			or str(action.get("payload_id", "")) != str(expected[6])
			or str(action.get("cue_id", "")) != str(expected[7])
		):
			return false
		if int(expected[5]) < 0:
			if action.get("cancel_from_frame") != null:
				return false
		elif int(action.get("cancel_from_frame", -1)) != int(expected[5]):
			return false
		if not payloads.has(str(expected[6])) or not cues.has(str(expected[7])):
			return false
	var charged: Dictionary = actions.get("charged_slash", {})
	var ultimate: Dictionary = actions.get("primordial_edge", {})
	return (
		int(charged.get("hold_threshold_frames", -1)) == LAUNCH_PRIMARY_CHARGE_FRAMES
		and int(ultimate.get("hold_threshold_frames", -1)) == LAUNCH_ULTIMATE_HOLD_FRAMES
		and _matches_launch_payloads(payloads)
	)


func _matches_launch_resources(value: Variant) -> bool:
	if not value is Array or (value as Array).size() != 2:
		return false
	var indexed: Dictionary = {}
	for resource_value: Variant in value as Array:
		if not resource_value is Dictionary:
			return false
		var resource: Dictionary = resource_value
		indexed[str(resource.get("resource_id", ""))] = resource
	if not indexed.has("guard") or not indexed.has("intent"):
		return false
	var guard: Dictionary = indexed["guard"]
	var intent: Dictionary = indexed["intent"]
	return (
		_number_matches_exactly(guard.get("minimum"), 0.0)
		and _number_matches_exactly(guard.get("maximum"), 100.0)
		and _number_matches_exactly(guard.get("initial"), 100.0)
		and _number_matches_exactly(guard.get("regen_per_second"), 8.0)
		and _number_matches_exactly(intent.get("minimum"), 0.0)
		and _number_matches_exactly(intent.get("maximum"), 100.0)
		and _number_matches_exactly(intent.get("initial"), 0.0)
		and _number_matches_exactly(intent.get("regen_per_second"), 0.0)
	)


func _matches_launch_payloads(payloads: Dictionary) -> bool:
	var guard_parameters: Dictionary = (payloads.get("sword_guard", {}) as Dictionary).get("parameters", {})
	var zone_parameters: Dictionary = (payloads.get("sword_skill_zone", {}) as Dictionary).get("parameters", {})
	var wave_parameters: Dictionary = (payloads.get("sword_ultimate_wave", {}) as Dictionary).get("parameters", {})
	return (
		_number_matches_exactly(guard_parameters.get("block_multiplier"), 0.5)
		and _integer_matches_exactly(guard_parameters.get("perfect_window_frames"), 3)
		and _number_matches_exactly(guard_parameters.get("perfect_block_multiplier"), 0.0)
		and _number_matches_exactly(guard_parameters.get("intent_per_blocked_damage"), 1.0)
		and _number_matches_exactly(guard_parameters.get("perfect_intent_bonus"), 10.0)
		and _number_matches_exactly(zone_parameters.get("damage_multiplier"), 2.8)
		and _integer_matches_exactly(zone_parameters.get("duration_frames"), 90)
		and _number_matches_exactly(zone_parameters.get("radius_pixels"), 192.0)
		and _number_matches_exactly(wave_parameters.get("damage_multiplier"), 9.0)
		and _number_matches_exactly(wave_parameters.get("knockback"), 320.0)
		and _integer_matches_exactly(wave_parameters.get("duration_frames"), 12)
		and _number_matches_exactly(wave_parameters.get("range_pixels"), 640.0)
		and _number_matches_exactly(wave_parameters.get("width_pixels"), 96.0)
		and _number_matches_exactly(wave_parameters.get("thickness_pixels"), 64.0)
	)


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
	if typeof(value.get("combo_timeout_remaining")) != TYPE_INT or int(value["combo_timeout_remaining"]) < 0:
		return false
	if typeof(value.get("last_runtime_frame")) != TYPE_INT or int(value["last_runtime_frame"]) < 0:
		return false
	if typeof(value.get("active_token")) != TYPE_INT or int(value["active_token"]) < 0:
		return false
	if not value.get("active_plan") is Dictionary or not value.get("modifier_snapshot") is Dictionary:
		return false
	if not value.get("adapter") is Dictionary:
		return false
	var adapter: Dictionary = value["adapter"]
	if (
		typeof(adapter.get("combo_index")) != TYPE_INT
		or int(adapter["combo_index"]) not in range(COMBO_ACTION_IDS.size())
		or typeof(adapter.get("attacking")) != TYPE_BOOL
		or typeof(adapter.get("active")) != TYPE_BOOL
		or not adapter.get("current_attack") is Dictionary
	):
		return false
	if _is_launch_profile():
		if (
			typeof(value.get("launch_combo_step")) != TYPE_INT
			or int(value["launch_combo_step"]) != int(value["combo_step"])
			or int(value["combo_timeout_remaining"]) > LAUNCH_COMBO_RESET_FRAMES
			or not _valid_resource_snapshot(value.get("resources"))
			or not _valid_resource_accumulators(value.get("resource_regen_frame_accumulators"))
			or not value.get("launch_adapter") is Dictionary
			or not _adapter.has_method("can_restore_launch_runtime_snapshot")
			or not bool(_adapter.call(
				"can_restore_launch_runtime_snapshot",
				(value["launch_adapter"] as Dictionary).duplicate(true)
			))
			or not _valid_launch_action_restore_state(value, adapter)
		):
			return false
	else:
		if (
			int(value["active_token"]) != 0
			or str(value.get("active_phase", "")) != "READY"
			or not (value["active_plan"] as Dictionary).is_empty()
			or not (value["modifier_snapshot"] as Dictionary).is_empty()
			or int(adapter["combo_index"]) != int(value["combo_step"])
			or bool(adapter["attacking"])
			or bool(adapter["active"])
			or not (adapter["current_attack"] as Dictionary).is_empty()
		):
			return false
	return _dictionary_numbers_are_finite(value)


func _valid_launch_action_restore_state(value: Dictionary, adapter: Dictionary) -> bool:
	var token := int(value["active_token"])
	var phase := str(value.get("active_phase", ""))
	var plan: Dictionary = value["active_plan"]
	var modifiers: Dictionary = value["modifier_snapshot"]
	var launch_adapter: Dictionary = value["launch_adapter"]
	if token == 0:
		return (
			phase == "READY"
			and plan.is_empty()
			and modifiers.is_empty()
			and not bool(adapter["attacking"])
			and not bool(adapter["active"])
			and (adapter["current_attack"] as Dictionary).is_empty()
			and not bool(launch_adapter.get("guard_active", true))
		)
	if phase == "HOLD":
		return (
			_launch_hold_plan_matches_profile(plan)
			and modifiers == plan.get("modifier_snapshot", {})
			and not bool(adapter["attacking"])
			and not bool(adapter["active"])
			and (adapter["current_attack"] as Dictionary).is_empty()
			and not bool(launch_adapter.get("guard_active", true))
		)
	if phase not in ["WINDUP", "ACTIVE", "RECOVERY"]:
		return false
	var action_id := StringName(str(plan.get("action_id", "")))
	if (
		action_id not in LAUNCH_ACTION_IDS
		or not _launch_final_plan_matches_profile(plan, action_id)
		or modifiers != plan.get("modifier_snapshot", {})
		or not bool(adapter["attacking"])
		or bool(adapter["active"]) != (phase == "ACTIVE")
		or (adapter["current_attack"] as Dictionary) != _profile_attack_definition(plan)
	):
		return false
	var guard_active := bool(launch_adapter.get("guard_active", false))
	if guard_active != (phase == "ACTIVE" and action_id == &"guard"):
		return false
	var payload_must_survive := (
		action_id == &"temporal_judgment" and phase in ["ACTIVE", "RECOVERY"]
	) or (action_id == &"primordial_edge" and phase == "ACTIVE")
	if payload_must_survive:
		var expected_kind := "zone" if action_id == &"temporal_judgment" else "wave"
		var found_payload := false
		for payload_value: Variant in launch_adapter.get("payloads", []):
			if payload_value is Dictionary and str((payload_value as Dictionary).get("kind", "")) == expected_kind:
				found_payload = true
		return found_payload
	if action_id == &"primordial_edge" and phase == "RECOVERY":
		for payload_value: Variant in launch_adapter.get("payloads", []):
			if payload_value is Dictionary and str((payload_value as Dictionary).get("kind", "")) == "wave":
				return false
	return true


func _valid_resource_snapshot(value: Variant) -> bool:
	if not value is Dictionary or (value as Dictionary).size() != _resource_definitions.size():
		return false
	for resource_id_value: Variant in _resource_definitions.keys():
		var resource_id := str(resource_id_value)
		var state_value: Variant = (value as Dictionary).get(resource_id)
		if not state_value is Dictionary:
			return false
		var state: Dictionary = state_value
		var definition: Dictionary = _resource_definitions[resource_id]
		if (
			state.size() != 4
			or not _number_matches_exactly(state.get("minimum"), float(definition["minimum"]))
			or not _number_matches_exactly(state.get("maximum"), float(definition["maximum"]))
			or not _number_matches_exactly(state.get("regen_per_second"), float(definition["regen_per_second"]))
			or typeof(state.get("current")) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(state.get("current", NAN)))
			or float(state["current"]) < float(definition["minimum"])
			or float(state["current"]) > float(definition["maximum"])
		):
			return false
	return true


func _valid_resource_accumulators(value: Variant) -> bool:
	if not value is Dictionary or (value as Dictionary).size() != _resource_definitions.size():
		return false
	var ticks_per_second := maxi(1, Engine.physics_ticks_per_second)
	for resource_id_value: Variant in _resource_definitions.keys():
		var accumulator: Variant = (value as Dictionary).get(str(resource_id_value))
		if typeof(accumulator) != TYPE_INT or int(accumulator) < 0 or int(accumulator) >= ticks_per_second:
			return false
	return true


func _adapter_snapshot() -> Dictionary:
	if _adapter == null:
		return {}
	return {
		"combo_index": int(_adapter.get("_combo_index")),
		"attacking": bool(_adapter.get("_attacking")),
		"active": bool(_adapter.get("_active")),
		"current_attack": (_adapter.get("_current_attack") as Dictionary).duplicate(true),
		"damage_attack_generation": int(_adapter.get("_active_damage_attack_generation")),
		"damage_action_token": int(_adapter.get("_active_damage_action_token")),
	}


func _restore_adapter_snapshot(adapter_snapshot: Dictionary) -> void:
	_adapter.call("cancel_attack")
	_adapter.set("_combo_index", int(adapter_snapshot.get("combo_index", 0)))
	_adapter.set("_attacking", bool(adapter_snapshot.get("attacking", false)))
	_adapter.set("_active", false)
	_adapter.set("_current_attack", (adapter_snapshot.get("current_attack", {}) as Dictionary).duplicate(true))
	_adapter.set("_active_damage_attack_generation", 0)
	_adapter.set("_active_damage_action_token", 0)


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


func _sync_legacy_reward_capabilities() -> void:
	if _adapter == null or _modifier_state == null or not _modifier_state.has_method("snapshot"):
		return
	var snapshot_value: Variant = _modifier_state.call("snapshot")
	if not snapshot_value is Dictionary:
		return
	var modifiers: Dictionary = snapshot_value
	for capability_value: Variant in LEGACY_REWARD_CAPABILITIES.keys():
		var capability := str(capability_value)
		if not _capabilities.has(capability):
			continue
		var mapping: Dictionary = LEGACY_REWARD_CAPABILITIES[capability_value]
		_adapter.set(
			str(mapping["field"]),
			float(modifiers.get(capability, mapping["base_value"]))
		)


func _timing_multiplier(modifiers: Dictionary, character_stats: Dictionary = {}) -> float:
	var adapter_speed := float(character_stats.get(
		"attack_speed",
		float(_adapter.get("attack_speed")) if _adapter != null else 1.0
	))
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
	var payload_kind := str((payload_value as Dictionary).get("kind", ""))
	var launch_profile := str(plan.get("profile_id", "")) == LAUNCH_PROFILE_ID
	var tags_value: Variant = parameters.get("tags", [])
	if not tags_value is Array:
		return {}
	if not launch_profile:
		return {
			"heavy": bool(plan.get("heavy", false)),
			"finisher": (tags_value as Array).has("attack:finisher"),
			"multiplier": float(parameters.get("damage_multiplier", 0.0)),
			"knockback": float(parameters.get("knockback", 0.0)),
			"tags": (tags_value as Array).duplicate(),
			"character_attack_scale": float(plan.get("character_attack_scale", 0.0)),
			"attack_speed": float(plan.get("attack_speed", 0.0)),
			"crit_chance": float(plan.get("crit_chance", -1.0)),
			"crit_multiplier": float(plan.get("crit_multiplier", 0.0)),
		}
	var tags: Array = (tags_value as Array).duplicate()
	for tag: String in ["weapon:sword", "action:%s" % str(plan.get("action_id", "")), "payload:%s" % payload_kind]:
		if not tags.has(tag):
			tags.append(tag)
	var damaging := payload_kind != "guard"
	var multiplier := float(parameters.get("damage_multiplier", 1.0 if damaging else 0.0))
	if damaging and multiplier <= 0.0:
		return {}
	return {
		"heavy": str(plan.get("action_id", "")) in [
			"charged_slash", "counter", "temporal_judgment", "primordial_edge",
		],
		"finisher": tags.has("attack:finisher"),
		"multiplier": multiplier,
		"knockback": float(parameters.get("knockback", 0.0)),
		"tags": tags,
		"damaging": damaging,
		"advance_combo": not launch_profile,
		"payload_kind": payload_kind,
		"payload_parameters": parameters.duplicate(true),
		"character_attack_scale": float(plan.get("character_attack_scale", 0.0)),
		"attack_speed": float(plan.get("attack_speed", 0.0)),
		"crit_chance": float(plan.get("crit_chance", -1.0)),
		"crit_multiplier": float(plan.get("crit_multiplier", 0.0)),
	}


func _character_stats_snapshot(adapter: Node) -> Dictionary:
	if adapter == null or not is_instance_valid(adapter):
		return {}
	var result: Dictionary = {}
	for field: String in CHARACTER_STATS_FIELDS:
		var value: Variant = adapter.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return {}
		result[field] = float(value)
	return result if _valid_character_stats_snapshot(result) else {}


func _valid_character_stats_snapshot(value: Variant) -> bool:
	if not value is Dictionary or (value as Dictionary).size() != CHARACTER_STATS_FIELDS.size():
		return false
	var stats := value as Dictionary
	for field: String in CHARACTER_STATS_FIELDS:
		if not stats.has(field) or typeof(stats[field]) != TYPE_FLOAT or not is_finite(float(stats[field])):
			return false
	return (
		float(stats["base_attack"]) > 0.0
		and float(stats["character_attack_scale"]) > 0.0
		and float(stats["attack_speed"]) > 0.0
		and float(stats["crit_chance"]) >= 0.0
		and float(stats["crit_chance"]) <= 1.0
		and float(stats["crit_multiplier"]) >= 1.0
	)


func _freeze_character_stats_into_plan(plan: Dictionary, stats: Dictionary) -> void:
	for field: String in CHARACTER_STATS_FIELDS.slice(1):
		plan[field] = float(stats[field])
	var payloads: Array = plan.get("payloads", [])
	for payload_value: Variant in payloads:
		if not payload_value is Dictionary or not (payload_value as Dictionary).get("parameters") is Dictionary:
			continue
		var parameters := (payload_value as Dictionary)["parameters"] as Dictionary
		for field: String in CHARACTER_STATS_FIELDS:
			parameters[field] = float(stats[field])


func _matches_active_action(plan: Dictionary, token: int) -> bool:
	return (
		token > 0
		and token == _active_token
		and str(plan.get("action_id", "")) == str(_active_plan.get("action_id", ""))
		and (not _is_launch_profile() or plan == _active_plan)
	)


func _is_hold_skeleton(plan: Dictionary) -> bool:
	var phases_value: Variant = plan.get("phases", [])
	return (
		phases_value is Array
		and not (phases_value as Array).is_empty()
		and (phases_value as Array)[0] is Dictionary
		and StringName(str(((phases_value as Array)[0] as Dictionary).get("phase", ""))) == &"HOLD"
	)


func _is_launch_profile() -> bool:
	return str(_profile_snapshot.get("id", "")) == LAUNCH_PROFILE_ID


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
		TYPE_VECTOR2:
			var vector := value as Vector2
			return is_finite(vector.x) and is_finite(vector.y)
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
