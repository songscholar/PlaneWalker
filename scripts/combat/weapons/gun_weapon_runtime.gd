class_name GunWeaponRuntime
extends "res://scripts/combat/weapons/weapon_runtime.gd"

const SeedServiceScript := preload("res://scripts/core/seed_service.gd")
const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
const PROFILE_ID := "gun_launch_v1"
const PROFILE_VERSION := 1
const WEAPON_ID := &"gun"
const MASTERY_IDS: Array[StringName] = [
	&"gun_perfect_reload",
	&"gun_magazine_finisher",
]
const PRIMARY_HOLD_ACTION_ID := &"normal_fire"
const NORMAL_ACTION_ID := &"normal_fire"
const AIMED_ACTION_ID := &"aimed_fire"
const SHOTGUN_ACTION_ID := &"shotgun_fire"
const RELOAD_ACTION_ID := &"reload"
const TIME_LOAD_ACTION_ID := &"time_load"
const ULTIMATE_ACTION_ID := &"void_penetration"
const BASE_MAGAZINE := 6
const OVERFILL_MAGAZINE := 7
const PRIMARY_AIMED_THRESHOLD_FRAMES := 18
const PRIMARY_HOLD_MAXIMUM_FRAMES := 600
const ULTIMATE_HOLD_FRAMES := 60
const TIME_LOAD_DURATION_FRAMES := 300
const TIME_LOAD_COOLDOWN_FRAMES := 360
const ULTIMATE_COOLDOWN_FRAMES := 720
const TIME_LOAD_TIMING_MULTIPLIER := 0.60
const TIME_LOAD_TIME_DAMAGE_RATIO := 0.15
const PERFECT_RELOAD_RECOVERY_FRAMES := 4
const RELEASE_ACTION_FINGERPRINTS := {
	"normal_fire": "gun-launch-v1:normal-fire:v1",
	"aimed_fire": "gun-launch-v1:aimed-fire:v1",
	"void_penetration": "gun-launch-v1:void-penetration:v1",
}

const REQUIRED_ADAPTER_METHODS: Array[StringName] = [
	&"begin_profile_action",
	&"release_profile_action",
	&"is_profile_action_active",
	&"cancel_profile_action",
	&"finish_profile_action",
	&"reset_runtime_state",
	&"runtime_snapshot",
	&"can_restore_runtime_snapshot",
	&"restore_runtime_snapshot",
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
const CHARACTER_STATS_FIELDS: Array[String] = [
	"base_attack", "character_attack_scale", "attack_speed", "crit_chance", "crit_multiplier",
]
const FROZEN_CAPABILITIES: Array[String] = [
	"weapon.ammo_capacity",
	"weapon.attack_speed",
	"weapon.damage",
	"weapon.reload_window",
	"weapon.status_duration",
]
const FROZEN_PROFILE_METADATA := {
	"category": "weapon_runtime_profile",
	"availability": ["LAUNCH", "EXPANSION"],
	"name_key": "WEAPON_GUN_NAME",
	"description_key": "WEAPON_GUN_DESC",
	"tags": ["ammunition", "burst_cycle", "reload"],
	"compatibility": {"weapon_ids": ["gun"]},
	"effects": {},
	"references": ["gun"],
}
const FROZEN_ACTIONS := {
	"normal_fire": {
		"action_id": "normal_fire", "semantic_action": "weapon_primary", "activation_mode": "release",
		"hold_threshold_frames": 0, "maximum_hold_frames": 17, "windup_frames": 3,
		"active_frames": 1, "recovery_frames": 8, "cancel_from_frame": 5, "buffer_frames": 8,
		"movement_multiplier": 0.8, "resource_costs": {"ammo": 1.0},
		"payload_id": "gun_normal_bullet", "cue_id": "gun_normal_fire", "cooldown_frames": 0,
	},
	"aimed_fire": {
		"action_id": "aimed_fire", "semantic_action": "weapon_primary", "activation_mode": "release",
		"hold_threshold_frames": 18, "windup_frames": 8, "active_frames": 1,
		"recovery_frames": 12, "cancel_from_frame": 10, "buffer_frames": 8,
		"movement_multiplier": 0.45, "resource_costs": {"ammo": 1.0},
		"payload_id": "gun_aimed_bullet", "cue_id": "gun_aimed_fire", "cooldown_frames": 0,
	},
	"shotgun_fire": {
		"action_id": "shotgun_fire", "semantic_action": "weapon_secondary", "activation_mode": "press",
		"windup_frames": 8, "active_frames": 2, "recovery_frames": 20,
		"cancel_from_frame": 14, "buffer_frames": 8, "movement_multiplier": 0.55,
		"resource_costs": {"ammo": 2.0}, "payload_id": "gun_shotgun_pellets",
		"cue_id": "gun_shotgun_fire", "cooldown_frames": 0,
	},
	"reload": {
		"action_id": "reload", "semantic_action": "weapon_utility", "activation_mode": "confirm",
		"windup_frames": 8, "active_frames": 32, "recovery_frames": 8,
		"cancel_from_frame": 8, "buffer_frames": 8, "movement_multiplier": 0.65,
		"resource_costs": {}, "payload_id": "gun_reload_transaction",
		"cue_id": "gun_reload_start", "cooldown_frames": 0,
	},
	"time_load": {
		"action_id": "time_load", "semantic_action": "weapon_skill", "activation_mode": "press",
		"windup_frames": 8, "active_frames": 1, "recovery_frames": 4,
		"cancel_from_frame": 2, "buffer_frames": 8, "movement_multiplier": 0.5,
		"resource_costs": {"time_energy": 25.0}, "payload_id": "gun_time_load_buff",
		"cue_id": "gun_time_load", "cooldown_frames": 360,
	},
	"void_penetration": {
		"action_id": "void_penetration", "semantic_action": "weapon_ultimate", "activation_mode": "release",
		"hold_threshold_frames": 60, "windup_frames": 18, "active_frames": 3,
		"recovery_frames": 25, "cancel_from_frame": null, "buffer_frames": 8,
		"movement_multiplier": 0.0, "resource_costs": {"time_energy": 65.0},
		"payload_id": "gun_void_round", "cue_id": "gun_void_penetration", "cooldown_frames": 720,
	},
}
const FROZEN_PAYLOADS := {
	"gun_normal_bullet": {
		"payload_id": "gun_normal_bullet", "kind": "projectile",
		"parameters": {"damage_multiplier": 1.0, "speed_tiles_per_second": 40.0, "maximum_range_tiles": 15.0, "pierce": 0, "hit_width_tiles": 0.2, "knockback_tiles": 0.3},
	},
	"gun_aimed_bullet": {
		"payload_id": "gun_aimed_bullet", "kind": "projectile",
		"parameters": {"damage_multiplier": 2.5, "critical_chance_bonus": 0.2, "speed_tiles_per_second": 50.0, "maximum_range_tiles": 20.0, "pierce": 1, "hit_width_tiles": 0.3, "knockback_tiles": 1.5},
	},
	"gun_shotgun_pellets": {
		"payload_id": "gun_shotgun_pellets", "kind": "multi_projectile",
		"parameters": {"damage_multiplier": 0.7, "count": 8, "spread_degrees": 45.0, "speed_tiles_per_second": 25.0, "maximum_range_tiles": 5.0, "hit_width_tiles": 0.2, "pierce": 0, "knockback_tiles": 0.5, "close_range_multi_hit_tiles": 1.5, "target_deduplication": "per_pellet"},
	},
	"gun_reload_transaction": {
		"payload_id": "gun_reload_transaction", "kind": "resource_action",
		"parameters": {"total_frames": 48, "initial_locked_frames": 8, "dash_cancel_start_frame": 8, "dash_cancel_end_frame_exclusive": 40, "final_locked_start_frame": 40, "perfect_start_frame": 28, "perfect_end_frame": 36, "normal_fill": 6, "perfect_fill": 7, "perfect_recovery_frames": 4},
	},
	"gun_time_load_buff": {
		"payload_id": "gun_time_load_buff", "kind": "buff",
		"parameters": {"duration_frames": 300, "action_frame_multiplier": 0.6, "speed_multiplier": 1.4, "time_damage_multiplier": 0.15, "ammo_cost_multiplier": 0.0, "active_refill": 6, "cancel_from_total_frame": 10},
	},
	"gun_void_round": {
		"payload_id": "gun_void_round", "kind": "projectile",
		"parameters": {
			"damage_multiplier": 15.0, "void_damage_ratio": 0.6, "time_damage_ratio": 0.4,
			"speed_tiles_per_second": 60.0, "maximum_range_tiles": 30.0, "hit_width_tiles": 1.5,
			"unlimited_pierce": true, "cast_invulnerability": true,
			"penetration_explosion": {"radius_tiles": 1.5, "damage_multiplier": 0.3, "damage_type": "void"},
			"vulnerability": {"duration_frames": 180, "damage_taken_bonus": 0.15},
			"trail": {"duration_frames": 300, "width_tiles": 1.0, "tick_interval_frames": 30, "damage_multiplier": 0.1, "damage_type": "void"},
			"trail_duration_frames": 300,
			"time_load_damage_multiplier": 1.3, "time_load_explosion_radius_multiplier": 1.5,
		},
	},
}
const FROZEN_TIME_INTERACTIONS := {
	"stop": {"interaction_id": "gun_aimed_time_burst", "type": "projectile_modifier", "parameters": {"requires_action": "aimed_fire", "explosion_radius_tiles": 2.0, "explosion_damage_multiplier": 1.0, "damage_type": "time", "stop_extension_frames": 30, "extension_once_per_action_token": true}},
	"rewind": {"interaction_id": "gun_rewind_free_shot", "type": "next_action_modifier", "parameters": {"window_frames": 120, "ammo_free": true, "damage_multiplier": 1.5, "one_shot_claim": true}},
	"accelerate": {"interaction_id": "gun_recovery_speed", "type": "future_timing_modifier", "parameters": {"recovery_delta_frames": -4, "ammo_cost_multiplier": 0.5, "rounding": "ceil"}},
	"rift": {"interaction_id": "gun_rift_trail", "type": "projectile_trail", "parameters": {"duration_frames": 90, "width_tiles": 1.0, "tick_interval_frames": 30, "damage_multiplier": 0.2, "damage_type": "time", "spatial_policy": "projectile_path_intersection"}},
}
const FROZEN_BOSS_INTERACTION := {
	"conversion_id": "gun_weakpoint_pressure",
	"type": "poise_conversion",
	"parameters": {"interrupt_active_attack": false, "active_attack_policy": "preserve_committed", "allowed_phases": ["RECOVERY", "EXPOSED"], "control_conversion": "poise_contribution", "poise_multiplier": 1.1, "target_deduplication": true},
}

var _owner: Node
var _adapter: Node
var _modifier_state: RefCounted
var _profile_snapshot: Dictionary = {}
var _actions_by_id: Dictionary = {}
var _payloads_by_id: Dictionary = {}
var _cues_by_id: Dictionary = {}
var _capabilities: PackedStringArray = PackedStringArray()

var _ammo: int = BASE_MAGAZINE
var _time_load_source: StringName = &""
var _time_load_remaining_frames: int = 0
var _last_runtime_frame: int = -1
var _claimed_rewind_generations: Array[int] = []

var _active_token: int = 0
var _active_phase: StringName = &"READY"
var _active_plan: Dictionary = {}
var _modifier_snapshot: Dictionary = {}
var _committed_definition: Dictionary = {}
var _live_hold_context: Dictionary = {}
var _reload_confirmed: bool = false
var _reload_perfect: bool = false
var _reload_frame: int = -1


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
	var adapter := owner.get_node_or_null("GunWeapon")
	if adapter == null or not _has_methods(adapter, REQUIRED_ADAPTER_METHODS):
		return false
	if not _adapter_numbers_are_valid(adapter):
		return false

	var profile_value: Variant = (profile as RefCounted).call("snapshot")
	if not profile_value is Dictionary:
		return false
	var next_profile := (profile_value as Dictionary).duplicate(true)
	var indexes := _build_profile_indexes(next_profile)
	if not bool(indexes.get("ok", false)) or not _matches_frozen_profile(next_profile, indexes):
		return false
	var frozen_modifiers: Variant = (modifiers as RefCounted).call("freeze_for_action")
	if not frozen_modifiers is Dictionary or not _variant_numbers_are_finite(frozen_modifiers):
		return false

	_owner = owner
	_adapter = adapter
	_modifier_state = modifiers as RefCounted
	_profile_snapshot = next_profile
	_actions_by_id = (indexes["actions"] as Dictionary).duplicate(true)
	_payloads_by_id = (indexes["payloads"] as Dictionary).duplicate(true)
	_cues_by_id = (indexes["cues"] as Dictionary).duplicate(true)
	_capabilities = PackedStringArray(next_profile["capabilities"])
	reset_runtime_state(&"configured")
	return true


func capabilities() -> PackedStringArray:
	return _capabilities.duplicate()


func plan_intent(intent: Dictionary, context: Dictionary) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	var edge := StringName(str(intent.get("edge", "")))
	var semantic := StringName(str(intent.get("id", "")))
	match semantic:
		&"weapon_primary":
			if _ammo <= 0:
				if edge not in [&"pressed", &"released"]:
					return _failure(&"UNSUPPORTED_EDGE")
				return _build_reload_plan(context, true)
			if edge == &"pressed":
				return _build_hold_skeleton(PRIMARY_HOLD_ACTION_ID, semantic, context, 0, PRIMARY_HOLD_MAXIMUM_FRAMES, {})
			if edge == &"released":
				return _build_primary_plan(int(intent.get("held_frames", 0)), context)
		&"weapon_secondary":
			if edge != &"pressed":
				return _failure(&"UNSUPPORTED_EDGE")
			return _build_projectile_plan(SHOTGUN_ACTION_ID, context)
		&"weapon_utility":
			if edge != &"pressed":
				return _failure(&"UNSUPPORTED_EDGE")
			return _build_reload_plan(context, false)
		&"weapon_skill":
			if edge != &"pressed":
				return _failure(&"UNSUPPORTED_EDGE")
			return _build_time_load_plan(context)
		&"weapon_ultimate":
			if edge == &"pressed":
				return _build_hold_skeleton(
					ULTIMATE_ACTION_ID,
					semantic,
					context,
					ULTIMATE_HOLD_FRAMES,
					ULTIMATE_HOLD_FRAMES,
					{"time_energy": 65.0}
				)
			if edge == &"released":
				var held_frames := int(intent.get("held_frames", 0))
				if held_frames < ULTIMATE_HOLD_FRAMES:
					return _failure(&"UNDERCHARGED", {"held_frames": held_frames, "minimum_frames": ULTIMATE_HOLD_FRAMES})
				return _build_projectile_plan(ULTIMATE_ACTION_ID, context)
	return _failure(&"UNSUPPORTED_INTENT")


func commit_action(plan: Dictionary, token: int) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if token <= 0:
		return _failure(&"INVALID_TOKEN")
	if _active_token > 0 or bool(_adapter.call("is_profile_action_active")):
		return _failure(&"ACTION_IN_PROGRESS")
	var validation := _validate_commit_plan(plan)
	if not bool(validation.get("ok", false)):
		return validation
	if _is_hold_skeleton(plan):
		_active_token = token
		_active_phase = &"HOLD"
		_active_plan = plan.duplicate(true)
		_modifier_snapshot = (plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true)
		_live_hold_context = (plan.get("frozen_context", {}) as Dictionary).duplicate(true)
		return {"ok": true, "code": &"OK", "context": {"action_id": str(plan["action_id"])}}
	return _stage_and_commit(plan, token)


func release_hold(plan: Dictionary, token: int, held_frames: int) -> Dictionary:
	if not _matches_active_action(plan, token) or _active_phase != &"HOLD" or not _is_hold_skeleton(plan):
		return _failure(&"STALE_HOLD_RELEASE")
	var context := (plan.get("frozen_context", {}) as Dictionary).duplicate(true)
	if not _live_hold_context.is_empty():
		context = _live_hold_context.duplicate(true)
	var built: Dictionary
	if StringName(str(plan.get("action_id", ""))) == PRIMARY_HOLD_ACTION_ID:
		built = _build_primary_plan(held_frames, context)
	elif StringName(str(plan.get("action_id", ""))) == ULTIMATE_ACTION_ID:
		if held_frames < ULTIMATE_HOLD_FRAMES:
			return _failure(&"UNDERCHARGED", {"held_frames": held_frames, "minimum_frames": ULTIMATE_HOLD_FRAMES})
		built = _build_projectile_plan(ULTIMATE_ACTION_ID, context)
	else:
		return _failure(&"STALE_HOLD_RELEASE")
	if not bool(built.get("ok", false)):
		return built
	var finalized_plan: Dictionary = built["plan"]
	var finalized_action_id := str(finalized_plan.get("action_id", ""))
	var fingerprint := str((plan.get("release_action_fingerprints", {}) as Dictionary).get(finalized_action_id, ""))
	if fingerprint.is_empty():
		return _failure(&"RELEASE_ACTION_FINGERPRINT_MISSING", {"action_id": finalized_action_id})
	finalized_plan["release_action_fingerprint"] = fingerprint
	var staged := _stage_definition(finalized_plan, token)
	if not bool(staged.get("ok", false)):
		return staged
	_apply_committed_mutations(finalized_plan)
	_active_plan = finalized_plan.duplicate(true)
	_active_phase = &"WINDUP"
	_modifier_snapshot = (finalized_plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true)
	_live_hold_context.clear()
	return {
		"ok": true,
		"code": &"OK",
		"finalized_plan": finalized_plan.duplicate(true),
		"context": {"action_id": finalized_action_id},
	}


func update_hold_context(plan: Dictionary, token: int, context: Dictionary) -> bool:
	if not _matches_active_action(plan, token) or _active_phase != &"HOLD":
		return false
	var normalized := _normalized_context(context)
	if not bool(normalized.get("ok", false)):
		return false
	var character_stats: Variant = (plan.get("frozen_context", {}) as Dictionary).get(
		"character_stats",
		{}
	)
	if not _valid_character_stats_snapshot(character_stats):
		return false
	var live_context := (normalized["context"] as Dictionary).duplicate(true)
	live_context["character_stats"] = (character_stats as Dictionary).duplicate(true)
	_live_hold_context = live_context
	return true


func on_phase_enter(plan: Dictionary, phase: StringName, token: int) -> Array[Dictionary]:
	if not _matches_active_action(plan, token):
		return []
	var action_id := _resolved_action_id(plan)
	match phase:
		&"HOLD":
			return []
		&"WINDUP":
			if _active_phase != &"WINDUP":
				return []
			if action_id in ["reload", "time_load"]:
				return [_cue_event(plan, token)]
		&"RESOURCE_ACTION":
			if action_id == "reload" and _active_phase == &"WINDUP":
				_active_phase = &"RESOURCE_ACTION"
			return []
		&"ACTIVE":
			if _active_phase not in [&"WINDUP", &"RECOVERY"]:
				return []
			if not bool(_adapter.call("release_profile_action")):
				return [{"type": "phase_failed", "reason": "payload_activation_failed"}]
			_active_phase = &"ACTIVE"
			return [
				{
					"type": "payload_released", "weapon_id": str(WEAPON_ID), "action_id": action_id,
					"descriptor_id": str((plan.get("payloads", [{}]) as Array)[0].get("descriptor_id", "")),
					"token": token,
					"payload_descriptors": (_committed_definition.get("payload_descriptors", []) as Array).duplicate(true),
					"time_interactions": (_committed_definition.get("time_interactions", []) as Array).duplicate(true),
					"boss_conversion": (_committed_definition.get("boss_conversion", {}) as Dictionary).duplicate(true),
				},
				_cue_event(plan, token),
			]
		&"RECOVERY":
			if _active_phase in [&"WINDUP", &"ACTIVE", &"RESOURCE_ACTION"]:
				_active_phase = &"RECOVERY"
	return []


func on_action_frame(plan: Dictionary, phase: StringName, token: int, phase_frame: int) -> Array[Dictionary]:
	if not _matches_active_action(plan, token) or _resolved_action_id(plan) != "reload":
		return []
	match phase:
		&"WINDUP":
			_reload_frame = phase_frame
		&"RESOURCE_ACTION":
			_reload_frame = 8 + phase_frame
		&"RECOVERY":
			_reload_frame = 40 + phase_frame
	return []


func handle_live_intent(
	plan: Dictionary,
	token: int,
	phase: StringName,
	phase_frame: int,
	intent: Dictionary,
	_context: Dictionary
) -> Dictionary:
	if (
		not _matches_active_action(plan, token)
		or _resolved_action_id(plan) != "reload"
		or StringName(str(intent.get("id", ""))) != &"weapon_utility"
		or StringName(str(intent.get("edge", ""))) != &"pressed"
	):
		return {"handled": false}
	if phase != &"RESOURCE_ACTION" or phase_frame < 0 or phase_frame >= 32:
		return {"handled": true, "ok": false, "code": &"RELOAD_CONFIRM_OUTSIDE_RESOURCE_ACTION", "context": {}}
	var authoritative_frame := 8 + phase_frame
	_reload_frame = authoritative_frame
	var confirmed := _confirm_reload_authoritative(authoritative_frame)
	if not bool(confirmed.get("ok", false)):
		confirmed["handled"] = true
		return confirmed
	var result := {
		"handled": true,
		"ok": true,
		"code": &"OK",
		"replacement_phases": [],
		"context": {"perfect_reload": bool(confirmed.get("perfect", false)), "reload_frame": authoritative_frame},
	}
	if bool(confirmed.get("perfect", false)):
		var replacement_phases := [{
			"phase": "RECOVERY",
			"duration_frames": PERFECT_RELOAD_RECOVERY_FRAMES,
			"movement_multiplier": float((_actions_by_id["reload"] as Dictionary)["movement_multiplier"]),
		}]
		result["replacement_phases"] = replacement_phases
		var finalized_plan := plan.duplicate(true)
		finalized_plan["phases"] = [
			((plan["phases"] as Array)[0] as Dictionary).duplicate(true),
			replacement_phases[0].duplicate(true),
		]
		_active_plan = finalized_plan
	return result


func _confirm_reload_authoritative(reload_frame: int) -> Dictionary:
	if _reload_confirmed:
		return _failure(&"RELOAD_ALREADY_CONFIRMED")
	_reload_confirmed = true
	_reload_frame = reload_frame
	var window := reload_window(reload_frame)
	if not bool(window.get("perfect_confirm", false)):
		return {"ok": true, "code": &"OK", "perfect": false, "context": window}
	_reload_perfect = true
	_ammo = OVERFILL_MAGAZINE
	_activate_time_load(&"perfect_reload")
	return {
		"ok": true,
		"code": &"OK",
		"perfect": true,
		"context": window,
	}


func reload_window(frame: int) -> Dictionary:
	if frame < 0:
		return {"segment": "invalid", "dash_cancellable": false, "perfect_confirm": false, "complete": false}
	if frame < 8:
		return {"segment": "locked_open", "dash_cancellable": false, "perfect_confirm": false, "complete": false}
	if frame < 28:
		return {"segment": "dash_cancel", "dash_cancellable": true, "perfect_confirm": false, "complete": false}
	if frame < 36:
		return {"segment": "perfect", "dash_cancellable": true, "perfect_confirm": true, "complete": false}
	if frame < 40:
		return {"segment": "dash_cancel", "dash_cancellable": true, "perfect_confirm": false, "complete": false}
	if frame < 48:
		return {"segment": "locked_complete", "dash_cancellable": false, "perfect_confirm": false, "complete": false}
	return {"segment": "complete", "dash_cancellable": false, "perfect_confirm": false, "complete": true}


func advance_runtime_frame(coordinator_frame: int) -> Array[Dictionary]:
	if coordinator_frame < 0 or coordinator_frame <= _last_runtime_frame:
		return []
	var elapsed := 1 if _last_runtime_frame < 0 else coordinator_frame - _last_runtime_frame
	_last_runtime_frame = coordinator_frame
	_time_load_remaining_frames = maxi(0, _time_load_remaining_frames - elapsed)
	if _time_load_remaining_frames == 0:
		_time_load_source = &""
	return []


func cancel_action(token: int, _reason: StringName) -> void:
	if token <= 0 or token != _active_token:
		return
	_adapter.call("cancel_profile_action")
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
	if not _is_configured() or not _valid_restore_snapshot(runtime_snapshot):
		return false
	var payload_guard := gameplay_rewind_committed_payload_guard()
	if not payload_guard.get("adapter") is Dictionary:
		return false
	var adapter_snapshot := runtime_snapshot["adapter_snapshot"] as Dictionary
	var before := snapshot()
	var adapter_target := _gameplay_rewind_adapter_target(
		adapter_snapshot,
		payload_guard["adapter"] as Dictionary
	)
	if not bool(_adapter.call("restore_gameplay_rewind_snapshot_for_rollback", adapter_target)):
		return false
	_active_token = int(runtime_snapshot["active_token"])
	_active_phase = StringName(str(runtime_snapshot["active_phase"]))
	_active_plan = (runtime_snapshot["active_plan"] as Dictionary).duplicate(true)
	_modifier_snapshot = (runtime_snapshot["modifier_snapshot"] as Dictionary).duplicate(true)
	_committed_definition = (runtime_snapshot["committed_definition"] as Dictionary).duplicate(true)
	_live_hold_context = (runtime_snapshot["live_hold_context"] as Dictionary).duplicate(true)
	_reload_confirmed = bool(runtime_snapshot["reload_confirmed"])
	_reload_perfect = bool(runtime_snapshot["reload_perfect"])
	_reload_frame = int(runtime_snapshot["reload_frame"])
	if snapshot() == runtime_snapshot:
		return true
	_adapter.call(
		"restore_gameplay_rewind_snapshot_for_rollback",
		_gameplay_rewind_adapter_target(
			before["adapter_snapshot"] as Dictionary,
			payload_guard["adapter"] as Dictionary
		)
	)
	_apply_snapshot_fields(before)
	return false


func _gameplay_rewind_adapter_target(
	adapter_snapshot: Dictionary,
	committed_payload_guard: Dictionary
) -> Dictionary:
	return {
		"profile_action": (adapter_snapshot["profile_action"] as Dictionary).duplicate(true),
		"profile_action_released": bool(adapter_snapshot["profile_action_released"]),
		"prepared_projectiles": (adapter_snapshot["prepared_projectiles"] as Array).duplicate(true),
		"action_claims_by_token": (adapter_snapshot["action_claims_by_token"] as Dictionary).duplicate(true),
		"committed_payload_guard": committed_payload_guard.duplicate(true),
	}


func gameplay_rewind_committed_payload_guard() -> Dictionary:
	var adapter_value: Variant = _adapter.call("gameplay_rewind_committed_payload_guard")
	return {
		"adapter": (adapter_value as Dictionary).duplicate(true) if adapter_value is Dictionary else {},
		"ammo": _ammo,
		"time_load_source": str(_time_load_source),
		"time_load_remaining_frames": _time_load_remaining_frames,
		"last_runtime_frame": _last_runtime_frame,
		"claimed_rewind_generations": _claimed_rewind_generations.duplicate(),
	}


func finish_action(token: int) -> void:
	if token <= 0 or token != _active_token:
		return
	if _resolved_action_id(_active_plan) == "reload" and not _reload_perfect:
		_ammo = BASE_MAGAZINE
	_adapter.call("finish_profile_action")
	_clear_active_action()


func apply_modifier(effect_id: StringName, value: Variant) -> bool:
	if _modifier_state == null or not _capabilities.has(str(effect_id)):
		return false
	return bool(_modifier_state.call("apply", effect_id, value))


func reset_runtime_state(_reason: StringName) -> void:
	if _adapter != null:
		_adapter.call("cancel_profile_action")
		_adapter.call("reset_runtime_state")
	_ammo = BASE_MAGAZINE
	_time_load_source = &""
	_time_load_remaining_frames = 0
	_last_runtime_frame = -1
	_claimed_rewind_generations.clear()
	_clear_active_action()


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
		"ammo": _ammo,
		"time_load_source": str(_time_load_source),
		"time_load_remaining_frames": _time_load_remaining_frames,
		"last_runtime_frame": _last_runtime_frame,
		"claimed_rewind_generations": _claimed_rewind_generations.duplicate(),
		"active_token": _active_token,
		"active_phase": str(_active_phase),
		"active_plan": _active_plan.duplicate(true),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
		"committed_definition": _committed_definition.duplicate(true),
		"live_hold_context": _live_hold_context.duplicate(true),
		"reload_confirmed": _reload_confirmed,
		"reload_perfect": _reload_perfect,
		"reload_frame": _reload_frame,
		"adapter_active": bool(_adapter.call("is_profile_action_active")) if _adapter != null else false,
		"adapter_snapshot": adapter_snapshot,
	}


func restore_snapshot(runtime_snapshot: Dictionary) -> bool:
	if not _is_configured() or not _valid_restore_snapshot(runtime_snapshot):
		return false
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
	var adapter_rollback_ok := bool(_adapter.call("restore_runtime_snapshot", current["adapter_snapshot"]))
	_apply_snapshot_fields(current)
	if adapter_rollback_ok and snapshot() == current:
		return false
	reset_runtime_state(&"restore_rollback_failed")
	return false


func _apply_snapshot_fields(runtime_snapshot: Dictionary) -> void:
	_ammo = int(runtime_snapshot["ammo"])
	_time_load_source = StringName(str(runtime_snapshot["time_load_source"]))
	_time_load_remaining_frames = int(runtime_snapshot["time_load_remaining_frames"])
	_last_runtime_frame = int(runtime_snapshot["last_runtime_frame"])
	_claimed_rewind_generations = _int_array(runtime_snapshot["claimed_rewind_generations"])
	_active_token = int(runtime_snapshot["active_token"])
	_active_phase = StringName(str(runtime_snapshot["active_phase"]))
	_active_plan = (runtime_snapshot["active_plan"] as Dictionary).duplicate(true)
	_modifier_snapshot = (runtime_snapshot["modifier_snapshot"] as Dictionary).duplicate(true)
	_committed_definition = (runtime_snapshot["committed_definition"] as Dictionary).duplicate(true)
	_live_hold_context = (runtime_snapshot["live_hold_context"] as Dictionary).duplicate(true)
	_reload_confirmed = bool(runtime_snapshot["reload_confirmed"])
	_reload_perfect = bool(runtime_snapshot["reload_perfect"])
	_reload_frame = int(runtime_snapshot["reload_frame"])


func presentation_snapshot() -> Dictionary:
	var facing := Vector2.RIGHT
	if _adapter is Node2D:
		facing = Vector2.RIGHT.rotated((_adapter as Node2D).global_rotation)
	return {
		"weapon_id": str(WEAPON_ID),
		"action_id": _resolved_action_id(_active_plan),
		"phase": str(_active_phase),
		"token": _active_token,
		"ammo": _ammo,
		"ammo_maximum": OVERFILL_MAGAZINE if _ammo > BASE_MAGAZINE else BASE_MAGAZINE,
		"reload_frame": _reload_frame,
		"reload_window": reload_window(_reload_frame),
		"time_load_source": str(_time_load_source),
		"time_load_remaining_frames": _time_load_remaining_frames,
		"facing": facing,
		"cue_id": str((_active_plan.get("cue", {}) as Dictionary).get("cue_id", "")),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
	}


func _build_primary_plan(held_frames: int, context: Dictionary) -> Dictionary:
	var action_id := NORMAL_ACTION_ID if held_frames < PRIMARY_AIMED_THRESHOLD_FRAMES else AIMED_ACTION_ID
	return _build_projectile_plan(action_id, context)


func _build_projectile_plan(action_id: StringName, context: Dictionary) -> Dictionary:
	var action := _copy_indexed(_actions_by_id, action_id)
	if action.is_empty():
		return _failure(&"ACTION_NOT_FOUND", {"action_id": str(action_id)})
	var payload_id := StringName(str(action.get("payload_id", "")))
	var payload := _copy_indexed(_payloads_by_id, payload_id)
	var cue := _copy_indexed(_cues_by_id, StringName(str(action.get("cue_id", ""))))
	if payload.is_empty() or cue.is_empty():
		return _failure(&"PROFILE_REFERENCE_MISSING")
	var normalized := _normalized_context(context)
	if not bool(normalized.get("ok", false)):
		return normalized
	var frozen_context: Dictionary = normalized["context"]
	var modifiers := _frozen_modifiers()
	if not bool(modifiers.get("ok", false)):
		return modifiers
	var frozen_modifiers: Dictionary = modifiers["modifiers"]
	var time_context: Dictionary = frozen_context["time_interactions"]
	var time_load_active := _time_load_remaining_frames > 0
	var timing_scale := _modifier_timing_scale(
		frozen_modifiers,
		frozen_context["character_stats"]
	)
	if time_load_active:
		timing_scale *= TIME_LOAD_TIMING_MULTIPLIER

	var base_ammo_cost := int(ceili(float((action.get("resource_costs", {}) as Dictionary).get("ammo", 0.0))))
	var ammo_cost := base_ammo_cost
	var rewind_generation := int(time_context.get("rewind_generation", 0))
	var rewind_available := (
		bool(time_context.get("rewind_shot_available", false))
		and rewind_generation > 0
		and not _claimed_rewind_generations.has(rewind_generation)
	)
	if rewind_available or time_load_active:
		ammo_cost = 0
	elif bool(time_context.get("accelerate_active", false)):
		ammo_cost = int(ceili(float(ammo_cost) * 0.5))
	if ammo_cost > _ammo:
		return _failure(&"INSUFFICIENT_AMMO", {"required": ammo_cost, "available": _ammo})

	var parameters := (payload.get("parameters", {}) as Dictionary).duplicate(true)
	var damage_modifier := float(frozen_modifiers.get("weapon.damage", 1.0))
	if parameters.has("damage_multiplier"):
		var damage_multiplier := float(parameters["damage_multiplier"])
		if rewind_available:
			damage_multiplier *= 1.5
		if action_id == ULTIMATE_ACTION_ID and time_load_active:
			damage_multiplier *= 1.3
		parameters["damage_multiplier"] = damage_multiplier
		parameters["resolved_damage_multiplier"] = damage_multiplier * damage_modifier
	if time_load_active and action_id in [NORMAL_ACTION_ID, AIMED_ACTION_ID, SHOTGUN_ACTION_ID]:
		parameters["time_damage_ratio"] = TIME_LOAD_TIME_DAMAGE_RATIO
	if action_id == ULTIMATE_ACTION_ID and time_load_active:
		var explosion := (parameters.get("penetration_explosion", {}) as Dictionary).duplicate(true)
		explosion["radius_tiles"] = (
			float(explosion.get("radius_tiles", 0.0))
			* float(parameters.get("time_load_explosion_radius_multiplier", 1.0))
		)
		parameters["penetration_explosion"] = explosion

	var windup := _scaled_frames(int(action["windup_frames"]), timing_scale)
	var active := int(action["active_frames"])
	var recovery := _scaled_frames(int(action["recovery_frames"]), timing_scale)
	if bool(time_context.get("accelerate_active", false)):
		recovery = maxi(1, recovery - 4)
	var cancel_value: Variant = action.get("cancel_from_frame")
	var total_cancel := windup + active if cancel_value == null else int(cancel_value)
	var recovery_phase := {
		"phase": "RECOVERY",
		"duration_frames": recovery,
		"movement_multiplier": float(action["movement_multiplier"]),
	}
	if cancel_value != null:
		recovery_phase["cancel_from_frame"] = clampi(
			total_cancel - int(action["windup_frames"]) - int(action["active_frames"]),
			0,
			recovery - 1
		)
	var resource_costs := (action.get("resource_costs", {}) as Dictionary).duplicate(true)
	resource_costs.erase("ammo")
	var plan := {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(action_id),
		"profile_id": PROFILE_ID,
		"profile_version": PROFILE_VERSION,
		"semantic_action": str(action["semantic_action"]),
		"activation_mode": str(action["activation_mode"]),
		"buffer_frames": int(action["buffer_frames"]),
		"cooldown_frames": int(action.get("cooldown_frames", 0)),
		"resource_costs": resource_costs,
		"ammo_cost": ammo_cost,
		"base_ammo_cost": base_ammo_cost,
		"cancel_total_frame": total_cancel,
		"run_seed": int(frozen_context["run_seed"]),
		"aim_direction_snapshot": frozen_context["aim_direction"],
		"modifier_snapshot": frozen_modifiers,
		"frozen_context": frozen_context,
		"rewind_generation_claim": rewind_generation if rewind_available else 0,
		"time_load_active": time_load_active,
		"phases": [
			{"phase": "WINDUP", "duration_frames": windup, "movement_multiplier": float(action["movement_multiplier"])},
			{"phase": "ACTIVE", "duration_frames": active, "movement_multiplier": float(action["movement_multiplier"])},
			recovery_phase,
		],
		"payloads": [{"descriptor_id": str(payload_id), "kind": str(payload["kind"]), "parameters": parameters}],
		"cue": cue,
		"time_interactions": _time_interaction_descriptors(action_id, time_context, rewind_available),
		"boss_conversion": _boss_conversion(),
		"invulnerable_during_cast": action_id == ULTIMATE_ACTION_ID,
	}
	_freeze_character_stats_into_plan(plan, frozen_context["character_stats"])
	var validation := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	if not bool(validation.get("ok", false)):
		return validation
	return {"ok": true, "code": &"OK", "plan": plan, "context": {}}


func _build_reload_plan(context: Dictionary, empty_primary_trigger: bool) -> Dictionary:
	if not empty_primary_trigger and _ammo >= BASE_MAGAZINE:
		return _failure(&"MAGAZINE_FULL")
	var action := _copy_indexed(_actions_by_id, RELOAD_ACTION_ID)
	var payload := _copy_indexed(_payloads_by_id, StringName(str(action.get("payload_id", ""))))
	var cue := _copy_indexed(_cues_by_id, StringName(str(action.get("cue_id", ""))))
	var normalized := _normalized_context(context)
	if action.is_empty() or payload.is_empty() or cue.is_empty() or not bool(normalized.get("ok", false)):
		return _failure(&"PROFILE_REFERENCE_MISSING") if action.is_empty() or payload.is_empty() or cue.is_empty() else normalized
	var modifiers := _frozen_modifiers()
	if not bool(modifiers.get("ok", false)):
		return modifiers
	var frozen_context: Dictionary = normalized["context"]
	var plan := {
		"weapon_id": str(WEAPON_ID), "action_id": str(RELOAD_ACTION_ID),
		"profile_id": PROFILE_ID, "profile_version": PROFILE_VERSION,
		"semantic_action": "weapon_utility", "activation_mode": "confirm",
		"buffer_frames": int(action["buffer_frames"]), "cooldown_frames": 0,
		"resource_costs": {}, "ammo_cost": 0, "base_ammo_cost": 0,
		"empty_primary_trigger": empty_primary_trigger,
		"run_seed": int(frozen_context["run_seed"]), "aim_direction_snapshot": frozen_context["aim_direction"],
		"modifier_snapshot": (modifiers["modifiers"] as Dictionary).duplicate(true), "frozen_context": frozen_context,
		"phases": [
			{"phase": "WINDUP", "duration_frames": 8, "movement_multiplier": float(action["movement_multiplier"])},
			{"phase": "RESOURCE_ACTION", "duration_frames": 32, "cancel_from_frame": 0, "movement_multiplier": float(action["movement_multiplier"])},
			{"phase": "RECOVERY", "duration_frames": 8, "movement_multiplier": float(action["movement_multiplier"])},
		],
		"payloads": [{"descriptor_id": str(payload["payload_id"]), "kind": str(payload["kind"]), "parameters": (payload["parameters"] as Dictionary).duplicate(true)}],
		"cue": cue, "time_interactions": [], "boss_conversion": _boss_conversion(),
	}
	_freeze_character_stats_into_plan(plan, frozen_context["character_stats"])
	var validation := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	return {"ok": true, "code": &"OK", "plan": plan, "context": {}} if bool(validation.get("ok", false)) else validation


func _build_time_load_plan(context: Dictionary) -> Dictionary:
	var action := _copy_indexed(_actions_by_id, TIME_LOAD_ACTION_ID)
	var payload := _copy_indexed(_payloads_by_id, StringName(str(action.get("payload_id", ""))))
	var cue := _copy_indexed(_cues_by_id, StringName(str(action.get("cue_id", ""))))
	var normalized := _normalized_context(context)
	if action.is_empty() or payload.is_empty() or cue.is_empty() or not bool(normalized.get("ok", false)):
		return _failure(&"PROFILE_REFERENCE_MISSING") if action.is_empty() or payload.is_empty() or cue.is_empty() else normalized
	var modifiers := _frozen_modifiers()
	if not bool(modifiers.get("ok", false)):
		return modifiers
	var frozen_context: Dictionary = normalized["context"]
	var plan := {
		"weapon_id": str(WEAPON_ID), "action_id": str(TIME_LOAD_ACTION_ID),
		"profile_id": PROFILE_ID, "profile_version": PROFILE_VERSION,
		"semantic_action": "weapon_skill", "activation_mode": "press",
		"buffer_frames": int(action["buffer_frames"]), "cooldown_frames": TIME_LOAD_COOLDOWN_FRAMES,
		"resource_costs": {"time_energy": 25.0}, "ammo_cost": 0, "base_ammo_cost": 0,
		"run_seed": int(frozen_context["run_seed"]), "aim_direction_snapshot": frozen_context["aim_direction"],
		"modifier_snapshot": (modifiers["modifiers"] as Dictionary).duplicate(true), "frozen_context": frozen_context,
		"phases": [
			{"phase": "WINDUP", "duration_frames": 8, "movement_multiplier": float(action["movement_multiplier"])},
			{"phase": "RECOVERY", "duration_frames": 4, "movement_multiplier": float(action["movement_multiplier"])},
		],
		"payloads": [{"descriptor_id": str(payload["payload_id"]), "kind": str(payload["kind"]), "parameters": (payload["parameters"] as Dictionary).duplicate(true)}],
		"cue": cue, "time_interactions": [], "boss_conversion": _boss_conversion(),
	}
	_freeze_character_stats_into_plan(plan, frozen_context["character_stats"])
	var validation := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	return {"ok": true, "code": &"OK", "plan": plan, "context": {}} if bool(validation.get("ok", false)) else validation


func _build_hold_skeleton(
	action_id: StringName,
	semantic_action: StringName,
	context: Dictionary,
	minimum_frames: int,
	maximum_frames: int,
	resource_costs: Dictionary
) -> Dictionary:
	var normalized := _normalized_context(context)
	if not bool(normalized.get("ok", false)):
		return normalized
	var modifiers := _frozen_modifiers()
	if not bool(modifiers.get("ok", false)):
		return modifiers
	var plan := {
		"weapon_id": str(WEAPON_ID), "action_id": str(action_id),
		"profile_id": PROFILE_ID, "profile_version": PROFILE_VERSION,
		"semantic_action": str(semantic_action), "activation_mode": "release",
		"buffer_frames": 8,
		"cooldown_frames": ULTIMATE_COOLDOWN_FRAMES if action_id == ULTIMATE_ACTION_ID else 0,
		"resource_costs": resource_costs.duplicate(true),
		"ammo_cost": 0, "base_ammo_cost": 0,
		"run_seed": int((normalized["context"] as Dictionary)["run_seed"]),
		"aim_direction_snapshot": (normalized["context"] as Dictionary)["aim_direction"],
		"modifier_snapshot": (modifiers["modifiers"] as Dictionary).duplicate(true),
		"frozen_context": (normalized["context"] as Dictionary).duplicate(true),
		"phases": [{
			"phase": "HOLD", "duration_frames": maximum_frames,
			"minimum_hold_frames": minimum_frames,
			"charge_complete_frames": PRIMARY_AIMED_THRESHOLD_FRAMES if action_id == PRIMARY_HOLD_ACTION_ID else maximum_frames,
			"movement_multiplier": 0.45 if action_id == PRIMARY_HOLD_ACTION_ID else 0.0,
			"movement_start_multiplier": 0.8 if action_id == PRIMARY_HOLD_ACTION_ID else 0.0,
		}],
		"payloads": [], "cue": {}, "time_interactions": [], "boss_conversion": _boss_conversion(),
	}
	_freeze_character_stats_into_plan(
		plan,
		(normalized["context"] as Dictionary)["character_stats"]
	)
	if action_id == PRIMARY_HOLD_ACTION_ID:
		plan["allowed_release_action_ids"] = [str(NORMAL_ACTION_ID), str(AIMED_ACTION_ID)]
		plan["release_action_fingerprints"] = {
			str(NORMAL_ACTION_ID): RELEASE_ACTION_FINGERPRINTS[str(NORMAL_ACTION_ID)],
			str(AIMED_ACTION_ID): RELEASE_ACTION_FINGERPRINTS[str(AIMED_ACTION_ID)],
		}
	else:
		plan["allowed_release_action_ids"] = [str(ULTIMATE_ACTION_ID)]
		plan["release_action_fingerprints"] = {
			str(ULTIMATE_ACTION_ID): RELEASE_ACTION_FINGERPRINTS[str(ULTIMATE_ACTION_ID)],
		}
	var validation := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	return {"ok": true, "code": &"OK", "plan": plan, "context": {}} if bool(validation.get("ok", false)) else validation


func _stage_and_commit(plan: Dictionary, token: int) -> Dictionary:
	var staged := _stage_definition(plan, token)
	if not bool(staged.get("ok", false)):
		return staged
	_apply_committed_mutations(plan)
	_active_token = token
	_active_phase = StringName(str(((plan["phases"] as Array)[0] as Dictionary)["phase"]))
	_active_plan = plan.duplicate(true)
	_modifier_snapshot = (plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true)
	return {"ok": true, "code": &"OK", "context": {"action_id": _resolved_action_id(plan)}}


func _stage_definition(plan: Dictionary, token: int) -> Dictionary:
	var definition := _action_definition(plan, token)
	if definition.is_empty():
		return _failure(&"PAYLOAD_PROFILE_INVALID")
	var committed_value: Variant = _adapter.call("begin_profile_action", definition.duplicate(true))
	if not committed_value is Dictionary or (committed_value as Dictionary).is_empty():
		_adapter.call("cancel_profile_action")
		return _failure(&"PAYLOAD_CONSTRUCTION_FAILED")
	if (committed_value as Dictionary) != definition:
		_adapter.call("cancel_profile_action")
		return _failure(&"PAYLOAD_PROFILE_MISMATCH")
	_committed_definition = definition.duplicate(true)
	return {"ok": true, "code": &"OK", "context": {}}


func _action_definition(plan: Dictionary, token: int) -> Dictionary:
	if token <= 0:
		return {}
	var descriptors := _materialize_payloads(plan, token)
	if descriptors.is_empty():
		return {}
	var character_stats := ((plan.get("frozen_context", {}) as Dictionary).get(
		"character_stats",
		{}
	) as Dictionary)
	if not _valid_character_stats_snapshot(character_stats):
		return {}
	return {
		"token": token, "profile_id": PROFILE_ID, "weapon_id": str(WEAPON_ID),
		"action_id": _resolved_action_id(plan), "semantic_action": str(plan.get("semantic_action", "")),
		"aim_direction": plan.get("aim_direction_snapshot", Vector2.RIGHT),
		"base_attack": float(character_stats["base_attack"]),
		"character_attack_scale": float(character_stats["character_attack_scale"]),
		"attack_speed": float(character_stats["attack_speed"]),
		"crit_chance": float(character_stats["crit_chance"]),
		"crit_multiplier": float(character_stats["crit_multiplier"]),
		"payload_descriptors": descriptors,
		"time_interactions": (plan.get("time_interactions", []) as Array).duplicate(true),
		"boss_conversion": (plan.get("boss_conversion", {}) as Dictionary).duplicate(true),
		"invulnerable_during_cast": bool(plan.get("invulnerable_during_cast", false)),
	}


func _materialize_payloads(plan: Dictionary, token: int) -> Array[Dictionary]:
	var payloads: Array = plan.get("payloads", [])
	if payloads.is_empty() or not payloads[0] is Dictionary:
		return []
	var payload: Dictionary = payloads[0]
	var payload_id := StringName(str(payload.get("descriptor_id", "")))
	var parameters := (payload.get("parameters", {}) as Dictionary).duplicate(true)
	var action_id := StringName(_resolved_action_id(plan))
	var run_seed := int(plan.get("run_seed", 0))
	var result: Array[Dictionary] = []
	if action_id == SHOTGUN_ACTION_ID:
		var count := int(parameters.get("count", 0))
		var spread := float(parameters.get("spread_degrees", 0.0))
		for index: int in range(count):
			var angle := lerpf(-spread, spread, float(index) / float(maxi(1, count - 1)))
			var pellet_parameters := parameters.duplicate(true)
			pellet_parameters["direction"] = (plan.get("aim_direction_snapshot", Vector2.RIGHT) as Vector2).rotated(deg_to_rad(angle))
			pellet_parameters["angle_degrees"] = angle
			result.append(_seeded_descriptor(payload_id, &"projectile", pellet_parameters, run_seed, action_id, token, index, "per_pellet"))
		return result
	parameters["direction"] = plan.get("aim_direction_snapshot", Vector2.RIGHT)
	result.append(_seeded_descriptor(payload_id, StringName(str(payload.get("kind", ""))), parameters, run_seed, action_id, token, 0, "per_action_token"))
	return result


func _seeded_descriptor(
	payload_id: StringName,
	kind: StringName,
	parameters: Dictionary,
	run_seed: int,
	action_id: StringName,
	token: int,
	outcome_index: int,
	deduplication: String
) -> Dictionary:
	return {
		"descriptor_id": str(payload_id), "kind": str(kind), "token": token,
		"outcome_index": outcome_index,
		"seed": SeedServiceScript.derive_weapon_action_seed(run_seed, StringName(PROFILE_ID), action_id, payload_id, token, outcome_index),
		"target_deduplication": deduplication,
		"parameters": parameters.duplicate(true),
	}


func _apply_committed_mutations(plan: Dictionary) -> void:
	_ammo = maxi(0, _ammo - int(plan.get("ammo_cost", 0)))
	var rewind_generation := int(plan.get("rewind_generation_claim", 0))
	if rewind_generation > 0 and not _claimed_rewind_generations.has(rewind_generation):
		_claimed_rewind_generations.append(rewind_generation)
		_claimed_rewind_generations.sort()
	match _resolved_action_id(plan):
		"reload":
			_reload_confirmed = false
			_reload_perfect = false
			_reload_frame = 0
		"time_load":
			_activate_time_load(&"active")


func _activate_time_load(source: StringName) -> void:
	_time_load_source = source
	_time_load_remaining_frames = TIME_LOAD_DURATION_FRAMES
	if source == &"active":
		_ammo = BASE_MAGAZINE


func _time_interaction_descriptors(
	action_id: StringName,
	time_context: Dictionary,
	rewind_available: bool
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if bool(time_context.get("stop_active", false)) and action_id == AIMED_ACTION_ID:
		var stop := (FROZEN_TIME_INTERACTIONS["stop"]["parameters"] as Dictionary).duplicate(true)
		stop["id"] = "stop"
		stop["interaction_id"] = "gun_aimed_time_burst"
		stop["extension_once_per_action_token"] = true
		result.append(stop)
	if rewind_available:
		var rewind := (FROZEN_TIME_INTERACTIONS["rewind"]["parameters"] as Dictionary).duplicate(true)
		rewind["id"] = "rewind"
		rewind["interaction_id"] = "gun_rewind_free_shot"
		rewind["rewind_generation"] = int(time_context.get("rewind_generation", 0))
		result.append(rewind)
	if bool(time_context.get("accelerate_active", false)):
		var accelerate := (FROZEN_TIME_INTERACTIONS["accelerate"]["parameters"] as Dictionary).duplicate(true)
		accelerate["id"] = "accelerate"
		accelerate["interaction_id"] = "gun_recovery_speed"
		result.append(accelerate)
	if bool(time_context.get("rift_active", false)):
		var rift := (FROZEN_TIME_INTERACTIONS["rift"]["parameters"] as Dictionary).duplicate(true)
		rift["id"] = "rift"
		rift["interaction_id"] = "gun_rift_trail"
		result.append(rift)
	return result


func _boss_conversion() -> Dictionary:
	return {
		"target_id": "chrono_warden",
		"conversion_id": "gun_weakpoint_pressure",
		"active_attack_policy": "preserve_committed",
		"preserve_committed_active_attack": true,
		"allowed_phases": ["RECOVERY", "EXPOSED"],
		"control_conversion": "poise_contribution",
		"poise_multiplier": 1.1,
		"target_deduplication": true,
	}


func _validate_commit_plan(plan: Dictionary) -> Dictionary:
	var contract_result := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	if not bool(contract_result.get("ok", false)):
		return contract_result
	if not _plan_character_stats_match(plan):
		return _failure(&"INVALID_CHARACTER_STATS")
	if str(plan.get("profile_id", "")) != PROFILE_ID or int(plan.get("profile_version", 0)) != PROFILE_VERSION:
		return _failure(&"PROFILE_MISMATCH")
	if not plan.get("modifier_snapshot", {}) is Dictionary or not _variant_numbers_are_finite(plan["modifier_snapshot"]):
		return _failure(&"INVALID_MODIFIER_SNAPSHOT")
	if _is_hold_skeleton(plan):
		if StringName(str(plan.get("action_id", ""))) not in [PRIMARY_HOLD_ACTION_ID, ULTIMATE_ACTION_ID]:
			return _failure(&"ACTION_ID_MISMATCH")
		return {"ok": true, "code": &"OK", "context": {}}
	var action_id := StringName(_resolved_action_id(plan))
	if not _actions_by_id.has(str(action_id)):
		return _failure(&"ACTION_ID_MISMATCH")
	var ammo_cost_value: Variant = plan.get("ammo_cost")
	if typeof(ammo_cost_value) != TYPE_INT or int(ammo_cost_value) < 0 or int(ammo_cost_value) > _ammo:
		return _failure(&"INSUFFICIENT_AMMO", {"required": int(ammo_cost_value), "available": _ammo})
	var rewind_generation := int(plan.get("rewind_generation_claim", 0))
	if rewind_generation > 0 and _claimed_rewind_generations.has(rewind_generation):
		return _failure(&"STALE_REWIND_GENERATION")
	return {"ok": true, "code": &"OK", "context": {}}


func _normalized_context(value: Dictionary) -> Dictionary:
	var run_seed_value: Variant = value.get("run_seed")
	var direction_value: Variant = value.get("aim_direction")
	var time_value: Variant = value.get("time_interactions", {})
	if typeof(run_seed_value) != TYPE_INT:
		return _failure(&"INVALID_CONTEXT", {"field": "run_seed"})
	if not direction_value is Vector2:
		return _failure(&"INVALID_CONTEXT", {"field": "aim_direction"})
	var direction: Vector2 = direction_value
	if not is_finite(direction.x) or not is_finite(direction.y) or direction.is_zero_approx():
		return _failure(&"INVALID_CONTEXT", {"field": "aim_direction"})
	if not time_value is Dictionary or not _variant_numbers_are_finite(time_value):
		return _failure(&"INVALID_CONTEXT", {"field": "time_interactions"})
	var time_context := (time_value as Dictionary).duplicate(true)
	for boolean_field: String in [
		"stop_active",
		"rewind_echo_available",
		"rewind_shot_available",
		"accelerate_active",
		"rift_active",
	]:
		if time_context.has(boolean_field) and typeof(time_context[boolean_field]) != TYPE_BOOL:
			return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.%s" % boolean_field})
	for generation_field: String in ["rewind_echo_generation", "rewind_generation"]:
		if time_context.has(generation_field):
			if typeof(time_context[generation_field]) != TYPE_INT or int(time_context[generation_field]) < 0:
				return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.%s" % generation_field})
	if (
		time_context.has("rewind_echo_available")
		and time_context.has("rewind_shot_available")
		and bool(time_context["rewind_echo_available"]) != bool(time_context["rewind_shot_available"])
	):
		return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.rewind_available_conflict"})
	if (
		time_context.has("rewind_echo_generation")
		and time_context.has("rewind_generation")
		and int(time_context["rewind_echo_generation"]) != int(time_context["rewind_generation"])
	):
		return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.rewind_generation_conflict"})
	if time_context.has("rewind_echo_available"):
		time_context["rewind_shot_available"] = bool(time_context["rewind_echo_available"])
		time_context.erase("rewind_echo_available")
	if time_context.has("rewind_echo_generation"):
		time_context["rewind_generation"] = int(time_context["rewind_echo_generation"])
		time_context.erase("rewind_echo_generation")
	var character_stats_value: Variant = value.get("character_stats", {})
	var character_stats := (
		(character_stats_value as Dictionary).duplicate(true)
		if character_stats_value is Dictionary and not (character_stats_value as Dictionary).is_empty()
		else _character_stats_snapshot(_adapter)
	)
	if not _valid_character_stats_snapshot(character_stats):
		return _failure(&"INVALID_CONTEXT", {"field": "character_stats"})
	return {
		"ok": true,
		"code": &"OK",
		"context": {
			"run_seed": int(run_seed_value),
			"aim_direction": direction.normalized(),
			"time_interactions": time_context,
			"character_stats": character_stats,
		},
	}


func _frozen_modifiers() -> Dictionary:
	var value: Variant = _modifier_state.call("freeze_for_action")
	if not value is Dictionary or not _variant_numbers_are_finite(value):
		return _failure(&"INVALID_MODIFIER_SNAPSHOT")
	return {"ok": true, "code": &"OK", "modifiers": (value as Dictionary).duplicate(true)}


func _modifier_timing_scale(modifiers: Dictionary, character_stats: Dictionary) -> float:
	var attack_speed := (
		float(character_stats["attack_speed"])
		* float(modifiers.get("weapon.attack_speed", 1.0))
	)
	return 1.0 / maxf(0.01, attack_speed)


func _scaled_frames(frames: int, scale: float) -> int:
	return maxi(1, ceili(float(frames) * scale))


func _cue_event(plan: Dictionary, token: int) -> Dictionary:
	return {
		"type": "cue_requested",
		"weapon_id": str(WEAPON_ID),
		"action_id": _resolved_action_id(plan),
		"cue": (plan.get("cue", {}) as Dictionary).duplicate(true),
		"token": token,
	}


func _matches_frozen_profile(profile: Dictionary, indexes: Dictionary) -> bool:
	if (
		str(profile.get("id", "")) != PROFILE_ID
		or str(profile.get("weapon_id", "")) != str(WEAPON_ID)
		or str(profile.get("runtime_kind", "")) != str(WEAPON_ID)
		or int(profile.get("profile_version", 0)) != PROFILE_VERSION
		or not _same_string_set(profile.get("capabilities", []), FROZEN_CAPABILITIES)
	):
		return false
	for field: String in FROZEN_PROFILE_METADATA:
		if not _frozen_equal(profile.get(field), FROZEN_PROFILE_METADATA[field]):
			return false
	var resources_value: Variant = profile.get("resources")
	if not resources_value is Array or (resources_value as Array).size() != 1:
		return false
	var expected_resource := {"resource_id": "ammo", "minimum": 0.0, "maximum": 7.0, "initial": 6.0, "regen_per_second": 0.0}
	if not _frozen_equal((resources_value as Array)[0], expected_resource):
		return false
	var actions: Dictionary = indexes["actions"]
	var payloads: Dictionary = indexes["payloads"]
	var cues: Dictionary = indexes["cues"]
	if actions.size() != FROZEN_ACTIONS.size() or payloads.size() != FROZEN_PAYLOADS.size() or cues.size() != 6:
		return false
	for action_id: String in FROZEN_ACTIONS:
		if not _frozen_equal(actions.get(action_id, {}), FROZEN_ACTIONS[action_id]):
			return false
	for payload_id: String in FROZEN_PAYLOADS:
		if not _frozen_equal(payloads.get(payload_id, {}), FROZEN_PAYLOADS[payload_id]):
			return false
	if not _matches_frozen_cues(cues):
		return false
	if not _frozen_equal(profile.get("time_interactions", {}), FROZEN_TIME_INTERACTIONS):
		return false
	var boss_value: Variant = profile.get("boss_interactions", {})
	if not boss_value is Dictionary or (boss_value as Dictionary).size() != 1:
		return false
	return _frozen_equal((boss_value as Dictionary).get("chrono_warden", {}), FROZEN_BOSS_INTERACTION)


func _matches_frozen_cues(cues: Dictionary) -> bool:
	var expected := {
		"gun_normal_fire": {"cue_id": "gun_normal_fire", "animation_id": "gun_fire", "vfx_id": "gun_muzzle", "audio_id": "gun_fire", "camera_id": "impact_light"},
		"gun_aimed_fire": {"cue_id": "gun_aimed_fire", "animation_id": "gun_aimed_fire", "vfx_id": "gun_aimed_tracer", "audio_id": "gun_aimed_fire", "camera_id": "impact_medium"},
		"gun_shotgun_fire": {"cue_id": "gun_shotgun_fire", "animation_id": "gun_shotgun", "vfx_id": "gun_shotgun_flash", "audio_id": "gun_shotgun", "camera_id": "impact_heavy"},
		"gun_reload_start": {"cue_id": "gun_reload_start", "animation_id": "gun_reload", "vfx_id": "gun_reload_marker", "audio_id": "gun_reload", "camera_id": "resource_action"},
		"gun_time_load": {"cue_id": "gun_time_load", "animation_id": "gun_time_load", "vfx_id": "gun_time_load_tint", "audio_id": "gun_time_load", "camera_id": "impact_medium"},
		"gun_void_penetration": {"cue_id": "gun_void_penetration", "animation_id": "gun_ultimate", "vfx_id": "gun_void_tracer", "audio_id": "gun_ultimate", "camera_id": "impact_ultimate"},
	}
	return _frozen_equal(cues, expected)


func _frozen_equal(actual: Variant, expected: Variant) -> bool:
	if actual is Dictionary and expected is Dictionary:
		var actual_dictionary := actual as Dictionary
		var expected_dictionary := expected as Dictionary
		if actual_dictionary.size() != expected_dictionary.size():
			return false
		for key: Variant in expected_dictionary:
			if not actual_dictionary.has(key) or not _frozen_equal(actual_dictionary[key], expected_dictionary[key]):
				return false
		return true
	if actual is Array and expected is Array:
		var actual_array := actual as Array
		var expected_array := expected as Array
		if actual_array.size() != expected_array.size():
			return false
		for index: int in range(expected_array.size()):
			if not _frozen_equal(actual_array[index], expected_array[index]):
				return false
		return true
	if typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		return float(actual) == float(expected)
	return typeof(actual) == typeof(expected) and actual == expected


func _build_profile_indexes(profile: Dictionary) -> Dictionary:
	var result := {"actions": {}, "payloads": {}, "cues": {}}
	for section: String in ["actions", "payloads", "cues"]:
		var values: Variant = profile.get(section)
		if not values is Array:
			return {"ok": false}
		var id_field := "action_id" if section == "actions" else ("payload_id" if section == "payloads" else "cue_id")
		for value: Variant in values as Array:
			if not value is Dictionary:
				return {"ok": false}
			var identity := str((value as Dictionary).get(id_field, ""))
			if identity.is_empty() or (result[section] as Dictionary).has(identity):
				return {"ok": false}
			(result[section] as Dictionary)[identity] = (value as Dictionary).duplicate(true)
	result["ok"] = true
	return result


func _valid_restore_snapshot(value: Dictionary) -> bool:
	if (
		not _runtime_snapshot_has_exact_fields(value)
		or int(value.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION
		or not bool(value.get("configured", false))
		or str(value.get("profile_id", "")) != PROFILE_ID
		or int(value.get("profile_version", 0)) != PROFILE_VERSION
		or typeof(value.get("ammo")) != TYPE_INT
		or int(value["ammo"]) < 0
		or int(value["ammo"]) > OVERFILL_MAGAZINE
		or typeof(value.get("time_load_source")) != TYPE_STRING
		or str(value["time_load_source"]) not in ["", "active", "perfect_reload"]
		or typeof(value.get("time_load_remaining_frames")) != TYPE_INT
		or int(value["time_load_remaining_frames"]) < 0
		or int(value["time_load_remaining_frames"]) > TIME_LOAD_DURATION_FRAMES
		or typeof(value.get("last_runtime_frame")) != TYPE_INT
		or int(value["last_runtime_frame"]) < -1
		or not _valid_generation_array(value.get("claimed_rewind_generations"))
		or typeof(value.get("active_token")) != TYPE_INT
		or int(value["active_token"]) < 0
		or not value.get("active_plan") is Dictionary
		or not value.get("modifier_snapshot") is Dictionary
		or not value.get("committed_definition") is Dictionary
		or not value.get("live_hold_context") is Dictionary
		or typeof(value.get("reload_confirmed")) != TYPE_BOOL
		or typeof(value.get("reload_perfect")) != TYPE_BOOL
		or typeof(value.get("reload_frame")) != TYPE_INT
		or typeof(value.get("adapter_active")) != TYPE_BOOL
		or not value.get("adapter_snapshot") is Dictionary
		or not _variant_numbers_are_finite(value)
	):
		return false
	var adapter_snapshot := value["adapter_snapshot"] as Dictionary
	var adapter_action_value: Variant = adapter_snapshot.get("profile_action", {})
	if not adapter_action_value is Dictionary:
		return false
	var adapter_action := adapter_action_value as Dictionary
	if (
		not bool(_adapter.call("can_restore_runtime_snapshot", adapter_snapshot))
		or bool(value["adapter_active"]) != (not adapter_action.is_empty())
	):
		return false
	if int(value["time_load_remaining_frames"]) == 0 and str(value["time_load_source"]) != "":
		return false
	if int(value["time_load_remaining_frames"]) > 0 and str(value["time_load_source"]) == "":
		return false
	var active_token := int(value["active_token"])
	if active_token == 0:
		return (
			str(value.get("active_phase", "")) == "READY"
			and not bool(value["adapter_active"])
			and str(adapter_snapshot.get("phase_state", "")) == "idle"
			and (value["active_plan"] as Dictionary).is_empty()
			and (value["modifier_snapshot"] as Dictionary).is_empty()
			and (value["committed_definition"] as Dictionary).is_empty()
			and (value["live_hold_context"] as Dictionary).is_empty()
		)
	if str(value.get("active_phase", "")) == "HOLD":
		return (
			not bool(value["adapter_active"])
			and str(adapter_snapshot.get("phase_state", "")) == "idle"
			and _is_hold_skeleton(value["active_plan"])
			and (value["committed_definition"] as Dictionary).is_empty()
		)
	var active_plan := value["active_plan"] as Dictionary
	var committed_definition := value["committed_definition"] as Dictionary
	var active_phase := str(value.get("active_phase", ""))
	var action_id := str(active_plan.get("action_id", ""))
	var expected_adapter_phase := "prepared"
	if action_id != "reload" and active_phase in ["ACTIVE", "RECOVERY"]:
		expected_adapter_phase = "released"
	if (
		active_phase not in ["WINDUP", "ACTIVE", "RESOURCE_ACTION", "RECOVERY"]
		or (active_phase == "RESOURCE_ACTION" and action_id != "reload")
	):
		return false
	return (
		bool(value["adapter_active"])
		and str(adapter_snapshot.get("phase_state", "")) == expected_adapter_phase
		and not committed_definition.is_empty()
		and int(committed_definition.get("token", 0)) == active_token
		and committed_definition == adapter_action
		and bool(WeaponActionContractScript.validate_plan(active_plan, WEAPON_ID).get("ok", false))
	)


func _runtime_snapshot_has_exact_fields(value: Dictionary) -> bool:
	var fields: Array[String] = [
		"schema_version", "configured", "profile_id", "profile_version", "ammo",
		"time_load_source", "time_load_remaining_frames", "last_runtime_frame",
		"claimed_rewind_generations", "active_token", "active_phase", "active_plan",
		"modifier_snapshot", "committed_definition", "live_hold_context", "reload_confirmed",
		"reload_perfect", "reload_frame", "adapter_active", "adapter_snapshot",
	]
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _valid_generation_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var previous := -1
	for child: Variant in value as Array:
		if typeof(child) != TYPE_INT or int(child) <= previous or int(child) <= 0:
			return false
		previous = int(child)
	return true


func _int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is Array:
		for child: Variant in value as Array:
			result.append(int(child))
	return result


func _is_hold_skeleton(plan: Dictionary) -> bool:
	var phases_value: Variant = plan.get("phases", [])
	return (
		phases_value is Array
		and not (phases_value as Array).is_empty()
		and (phases_value as Array)[0] is Dictionary
		and StringName(str(((phases_value as Array)[0] as Dictionary).get("phase", ""))) == &"HOLD"
	)


func _resolved_action_id(plan: Dictionary) -> String:
	return str(plan.get("action_id", ""))


func _matches_active_action(plan: Dictionary, token: int) -> bool:
	return token > 0 and token == _active_token and plan == _active_plan


func _clear_active_action() -> void:
	_active_token = 0
	_active_phase = &"READY"
	_active_plan.clear()
	_modifier_snapshot.clear()
	_committed_definition.clear()
	_live_hold_context.clear()
	_reload_confirmed = false
	_reload_perfect = false
	_reload_frame = -1


func _copy_indexed(index: Dictionary, identity: StringName) -> Dictionary:
	var value: Variant = index.get(str(identity))
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _is_configured() -> bool:
	return (
		_owner != null
		and is_instance_valid(_owner)
		and _adapter != null
		and is_instance_valid(_adapter)
		and _modifier_state != null
		and not _profile_snapshot.is_empty()
	)


func _adapter_numbers_are_valid(adapter: Node) -> bool:
	return not _character_stats_snapshot(adapter).is_empty()


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
	for payload_value: Variant in plan.get("payloads", []):
		if not payload_value is Dictionary or not (payload_value as Dictionary).get("parameters") is Dictionary:
			continue
		var parameters := (payload_value as Dictionary)["parameters"] as Dictionary
		for field: String in CHARACTER_STATS_FIELDS:
			parameters[field] = float(stats[field])


func _plan_character_stats_match(plan: Dictionary) -> bool:
	var stats_value: Variant = (plan.get("frozen_context", {}) as Dictionary).get("character_stats", {})
	if not _valid_character_stats_snapshot(stats_value):
		return false
	var stats := stats_value as Dictionary
	for field: String in CHARACTER_STATS_FIELDS.slice(1):
		if typeof(plan.get(field)) not in [TYPE_INT, TYPE_FLOAT] or float(plan[field]) != float(stats[field]):
			return false
	for payload_value: Variant in plan.get("payloads", []):
		if not payload_value is Dictionary or not (payload_value as Dictionary).get("parameters") is Dictionary:
			return false
		var parameters := (payload_value as Dictionary)["parameters"] as Dictionary
		for field: String in CHARACTER_STATS_FIELDS:
			if typeof(parameters.get(field)) not in [TYPE_INT, TYPE_FLOAT] or float(parameters[field]) != float(stats[field]):
				return false
	return true


func _has_methods(value: Object, methods: Array[StringName]) -> bool:
	for method_name: StringName in methods:
		if not value.has_method(method_name):
			return false
	return true


func _same_string_set(left: Variant, right: Variant) -> bool:
	if not left is Array and not left is PackedStringArray:
		return false
	if not right is Array and not right is PackedStringArray:
		return false
	var left_strings: Array[String] = []
	var right_strings: Array[String] = []
	for value: Variant in left:
		left_strings.append(str(value))
	for value: Variant in right:
		right_strings.append(str(value))
	left_strings.sort()
	right_strings.sort()
	return left_strings == right_strings


func _variant_numbers_are_finite(value: Variant) -> bool:
	match typeof(value):
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_VECTOR2:
			var vector: Vector2 = value
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
	return {"ok": false, "code": code, "context": context.duplicate(true)}
