class_name GauntletsWeaponRuntime
extends "res://scripts/combat/weapons/weapon_runtime.gd"

const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")
const WeaponForgivenessScript := preload("res://scripts/combat/weapons/weapon_forgiveness.gd")
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")
const GauntletsComboStateScript := preload("res://scripts/combat/weapons/gauntlets_combo_state.gd")

const SNAPSHOT_SCHEMA_VERSION := 2
const PROFILE_ID := "gauntlets_launch_v1"
const PROFILE_VERSION := 1
const PROFILE_FINGERPRINT := "63b6a21a7ea03cd1d63ba93307eac84320a1bf9b3b430d9943cfea0f2b32cdd9"
const WEAPON_ID := &"gauntlets"
const MASTERY_IDS: Array[StringName] = [
	&"gauntlets_dodge_counter",
	&"gauntlets_combo_threshold",
	&"gauntlets_chain_finisher",
]
const PRIMARY_HOLD_ACTION_ID := &"gauntlets_primary_charge"
const CHARGED_HEAVY_ACTION_ID := &"charged_heavy"
const DODGE_COUNTER_ACTION_ID := &"dodge_counter"
const SKILL_ACTION_ID := &"space_time_shatter"
const ULTIMATE_ACTION_ID := &"primordial_collapse_punch"
const PRIMARY_CHARGE_FRAMES := 30
const PRIMARY_MAXIMUM_HOLD_FRAMES := 600
const ULTIMATE_HOLD_FRAMES := 60
const COUNTER_WINDOW_LAST_FRAME := 8
const MAX_TRACKED_ACTIONS := 256
const MAX_TRACKED_GENERATIONS := 256
const HIGH_COMBO_THRESHOLD := 30
const RUNTIME_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version", "configured", "profile_id", "profile_version", "combo_state", "chain_step",
	"combo_count", "combo_remaining_frames", "last_runtime_frame", "stop_extensions_by_generation",
	"accelerate_hits_by_generation", "claimed_rewind_generations", "claimed_rewind_generation_floor",
	"action_ledgers", "action_token_floor", "aura_source_generation", "active_token", "active_phase",
	"active_plan", "modifier_snapshot", "committed_definition", "live_hold_context", "adapter_active",
	"adapter",
]
const FROZEN_CAPABILITIES: Array[String] = [
	"weapon.attack_speed", "weapon.combo_timeout", "weapon.damage", "weapon.status_duration",
]
const PRIMARY_ACTION_IDS: Array[StringName] = [
	&"punch_1", &"punch_2", &"punch_3", &"punch_4", &"punch_5",
]
const RELEASE_ACTION_FINGERPRINTS := {
	"punch_1": "gauntlets_primary:punch_1:v1",
	"punch_2": "gauntlets_primary:punch_2:v1",
	"punch_3": "gauntlets_primary:punch_3:v1",
	"punch_4": "gauntlets_primary:punch_4:v1",
	"punch_5": "gauntlets_primary:punch_5:v1",
	"charged_heavy": "gauntlets_primary:charged_heavy:v1",
	"primordial_collapse_punch": "gauntlets_ultimate:primordial_collapse_punch:v1",
}
const REQUIRED_ADAPTER_METHODS: Array[StringName] = [
	&"configure_result_sink", &"begin_profile_action", &"release_profile_action",
	&"is_profile_action_active", &"cancel_profile_action", &"finish_profile_action",
	&"reset_runtime_state", &"set_combo_slow_aura", &"runtime_snapshot",
	&"can_restore_runtime_snapshot", &"restore_runtime_snapshot",
	&"cancel_for_gameplay_rewind", &"restore_gameplay_rewind_snapshot_for_rollback",
	&"gameplay_rewind_committed_payload_guard",
]
const REQUIRED_MODIFIER_METHODS: Array[StringName] = [
	&"apply", &"freeze_for_action", &"snapshot", &"reset",
]
const CHARACTER_STATS_FIELDS: Array[String] = [
	"base_attack", "character_attack_scale", "attack_speed", "crit_chance", "crit_multiplier",
]

var _owner: Node
var _adapter: Node
var _adapter_bound: bool = false
var _modifier_state: RefCounted
var _profile_snapshot: Dictionary = {}
var _actions_by_id: Dictionary = {}
var _payloads_by_id: Dictionary = {}
var _cues_by_id: Dictionary = {}
var _capabilities := PackedStringArray()
var _combo_state: RefCounted = GauntletsComboStateScript.new()
var _last_runtime_frame: int = -1
var _stop_extensions_by_generation: Dictionary = {}
var _accelerate_hits_by_generation: Dictionary = {}
var _claimed_rewind_generations: Array[int] = []
var _claimed_rewind_generation_floor: int = 0
var _action_ledgers: Dictionary = {}
var _action_token_floor: int = 0
var _retired_action_token_floor: int = 0
var _aura_source_generation: int = 0
var _active_token: int = 0
var _active_phase: StringName = &"READY"
var _active_plan: Dictionary = {}
var _modifier_snapshot: Dictionary = {}
var _committed_definition: Dictionary = {}
var _live_hold_context: Dictionary = {}


func weapon_id() -> StringName:
	return WEAPON_ID


func mastery_ids() -> Array[StringName]:
	return MASTERY_IDS.duplicate()


func configure(owner: Node, profile: Variant, modifiers: Variant) -> bool:
	return _configure(owner, profile, modifiers, true)


func configure_detached(owner: Node, profile: Variant, modifiers: Variant) -> bool:
	return _configure(owner, profile, modifiers, false)


func activate_adapter() -> bool:
	if not _configuration_ready():
		return false
	if _adapter_bound:
		return true
	if not bool(_adapter.call("configure_result_sink", self)):
		return false
	_adapter_bound = true
	reset_runtime_state(&"configured")
	return true


func _configure(owner: Node, profile: Variant, modifiers: Variant, bind_adapter: bool) -> bool:
	if owner == null or not is_instance_valid(owner):
		return false
	if not profile is RefCounted or not (profile as RefCounted).has_method("snapshot"):
		return false
	if not modifiers is RefCounted or not _has_methods(modifiers as RefCounted, REQUIRED_MODIFIER_METHODS):
		return false
	var adapter := owner.get_node_or_null("GauntletsWeapon")
	if adapter == null or not _has_methods(adapter, REQUIRED_ADAPTER_METHODS) or not _adapter_numbers_are_valid(adapter):
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
	_adapter_bound = false
	_reset_runtime_domain_state(&"configured")
	if bind_adapter and not activate_adapter():
		_clear_configuration()
		return false
	return true


func capabilities() -> PackedStringArray:
	return _capabilities.duplicate()


func plan_intent(intent: Dictionary, context: Dictionary) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	var semantic := StringName(str(intent.get("id", "")))
	var edge := StringName(str(intent.get("edge", "")))
	match semantic:
		&"weapon_primary":
			if edge == &"pressed":
				return _build_action_plan(DODGE_COUNTER_ACTION_ID, context) if _counter_window_is_open(context) else _build_primary_hold_plan(context)
			if edge == &"released":
				return _build_primary_release_plan(int(intent.get("held_frames", 0)), context)
		&"weapon_skill":
			if edge == &"pressed":
				return _build_action_plan(SKILL_ACTION_ID, context)
		&"weapon_ultimate":
			if edge == &"pressed":
				return _build_ultimate_hold_plan(context)
			if edge == &"released":
				if int(intent.get("held_frames", 0)) < ULTIMATE_HOLD_FRAMES:
					return _failure(&"UNDERCHARGED", {"held_frames": int(intent.get("held_frames", 0)), "minimum_frames": ULTIMATE_HOLD_FRAMES})
				return _build_action_plan(ULTIMATE_ACTION_ID, context)
	return _failure(&"UNSUPPORTED_INTENT")


func commit_action(plan: Dictionary, token: int) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if token <= 0 or token <= _effective_action_token_floor():
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
	var action_id := StringName(str(plan.get("action_id", "")))
	var built: Dictionary
	if action_id == PRIMARY_HOLD_ACTION_ID:
		built = _build_primary_release_plan(held_frames, context)
	elif action_id == ULTIMATE_ACTION_ID:
		if held_frames < ULTIMATE_HOLD_FRAMES:
			return _failure(&"UNDERCHARGED", {"held_frames": held_frames, "minimum_frames": ULTIMATE_HOLD_FRAMES})
		built = _build_action_plan(ULTIMATE_ACTION_ID, context)
	else:
		return _failure(&"STALE_HOLD_RELEASE")
	if not bool(built.get("ok", false)):
		return built
	var finalized_plan := (built["plan"] as Dictionary).duplicate(true)
	var resolved_action_id := str(finalized_plan.get("action_id", ""))
	var fingerprint := str((plan.get("release_action_fingerprints", {}) as Dictionary).get(resolved_action_id, ""))
	if fingerprint.is_empty():
		return _failure(&"RELEASE_ACTION_FINGERPRINT_MISSING", {"action_id": resolved_action_id})
	finalized_plan["release_action_fingerprint"] = fingerprint
	var staged := _stage_definition(finalized_plan, token)
	if not bool(staged.get("ok", false)):
		return staged
	_apply_committed_mutations(finalized_plan, token)
	_active_plan = finalized_plan.duplicate(true)
	_active_phase = &"WINDUP"
	_modifier_snapshot = (finalized_plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true)
	_live_hold_context.clear()
	return {
		"ok": true,
		"code": &"OK",
		"finalized_plan": finalized_plan.duplicate(true),
		"context": WeaponForgivenessScript.merge_consumption_context(
			{"action_id": resolved_action_id}, finalized_plan, WEAPON_ID
		),
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
	match phase:
		&"HOLD":
			return []
		&"WINDUP":
			if _active_phase != &"WINDUP":
				return []
		&"ACTIVE":
			if _active_phase not in [&"WINDUP", &"RECOVERY"]:
				return []
			if not bool(_adapter.call("release_profile_action")):
				return [{"type": "phase_failed", "reason": "payload_activation_failed"}]
			_active_phase = &"ACTIVE"
			return [{
				"type": "payload_released", "weapon_id": str(WEAPON_ID),
				"action_id": _resolved_action_id(plan), "token": token,
				"payload_descriptors": (_committed_definition.get("payload_descriptors", []) as Array).duplicate(true),
				"time_interactions": (_committed_definition.get("time_interactions", []) as Array).duplicate(true),
				"boss_conversion": (_committed_definition.get("boss_conversion", {}) as Dictionary).duplicate(true),
			}, _cue_event(plan, token)]
		&"RECOVERY":
			if _active_phase in [&"WINDUP", &"ACTIVE"]:
				_active_phase = &"RECOVERY"
	return []


func on_action_frame(_plan: Dictionary, _phase: StringName, _token: int, _phase_frame: int) -> Array[Dictionary]:
	return []


func handle_payload_result(token: int, generation: int, result: Dictionary) -> Dictionary:
	if token <= 0 or generation != token or token <= _effective_action_token_floor():
		return _failure(&"STALE_GENERATION")
	var token_key := str(token)
	if not _action_ledgers.has(token_key):
		return _failure(&"STALE_TOKEN")
	var target_value: Variant = result.get("target_id")
	var outcome_value: Variant = result.get("outcome_id")
	var damage_value: Variant = result.get("damage", 0.0)
	if typeof(target_value) != TYPE_INT or int(target_value) <= 0:
		return _failure(&"INVALID_TARGET")
	if typeof(outcome_value) not in [TYPE_STRING, TYPE_STRING_NAME] or str(outcome_value).is_empty():
		return _failure(&"INVALID_OUTCOME")
	if typeof(damage_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(damage_value)) or float(damage_value) < 0.0:
		return _failure(&"INVALID_DAMAGE")
	if not bool(result.get("hit_confirmed", result.get("hit", false))):
		return {"ok": true, "code": &"OK", "combo_gain": 0, "energy_return": 0, "stop_extension_frames": 0, "echo_descriptor": {}, "context": {}}
	var ledger := (_action_ledgers[token_key] as Dictionary).duplicate(true)
	var is_echo := bool(result.get("is_echo", false))
	var combo_eligible := bool(ledger.get("combo_eligible", false)) and not is_echo
	if result.has("combo_eligible"):
		combo_eligible = combo_eligible and bool(result["combo_eligible"])
	var combo_result: Dictionary = _combo_state.call(
		"record_hit", token, generation, int(target_value),
		int(ledger.get("combo_gain", 0)), combo_eligible,
		int(ledger.get("combo_timeout_frames", 120))
	)
	if combo_eligible and not bool(combo_result.get("ok", false)):
		return combo_result
	var tier := (ledger.get("combo_tier_snapshot", {}) as Dictionary).duplicate(true)
	var energy_eligible := not is_echo and bool(ledger.get("energy_eligible", false))
	if result.has("energy_eligible"):
		energy_eligible = energy_eligible and bool(result["energy_eligible"])
	var energy_return := int(tier.get("energy_return", 0)) if energy_eligible else 0
	if energy_return > 0:
		_restore_time_energy(float(energy_return))
	var stop_eligible := not is_echo and bool(ledger.get("stop_extension_eligible", false))
	if result.has("stop_extension_eligible"):
		stop_eligible = stop_eligible and bool(result["stop_extension_eligible"])
	var stop_extension := (
		_apply_stop_extension(token, generation, int(ledger.get("stop_generation", 0)))
		if stop_eligible
		else 0
	)
	var accelerate_eligible := not is_echo and bool(ledger.get("accelerate_eligible", false)) and not bool(result.get("recursive_echo", false))
	var echo_descriptor := _advance_accelerate(int(ledger.get("accelerate_generation", 0)), ledger) if accelerate_eligible else {}
	ledger["last_outcome_id"] = str(outcome_value)
	ledger["last_target_id"] = int(target_value)
	_action_ledgers[token_key] = ledger
	_update_combo_aura(generation)
	return {
		"ok": true, "code": &"OK", "combo_gain": int(combo_result.get("combo_gain", 0)),
		"energy_return": energy_return, "stop_extension_frames": stop_extension,
		"echo_descriptor": echo_descriptor, "tier": _combo_state.call("tier_snapshot"), "context": {},
	}


func project_payload_result_replay_transition(
	runtime_snapshot: Dictionary,
	token: int,
	generation: int,
	result: Dictionary
) -> Dictionary:
	if not _valid_payload_replay_projection_snapshot(runtime_snapshot):
		return _failure(&"INVALID_RUNTIME_SNAPSHOT")
	var action_token_floor := int(runtime_snapshot.get("action_token_floor", 0))
	if token <= 0 or generation != token or token <= action_token_floor:
		return _failure(&"STALE_GENERATION")
	var token_key := str(token)
	var source_ledgers := runtime_snapshot.get("action_ledgers", {}) as Dictionary
	if not source_ledgers.has(token_key) or not source_ledgers[token_key] is Dictionary:
		return _failure(&"STALE_TOKEN")
	var target_value: Variant = result.get("target_id")
	var outcome_value: Variant = result.get("outcome_id")
	var damage_value: Variant = result.get("damage", 0.0)
	if typeof(target_value) != TYPE_INT or int(target_value) <= 0:
		return _failure(&"INVALID_TARGET")
	if typeof(outcome_value) not in [TYPE_STRING, TYPE_STRING_NAME] or str(outcome_value).is_empty():
		return _failure(&"INVALID_OUTCOME")
	if (
		typeof(damage_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(damage_value))
		or float(damage_value) < 0.0
	):
		return _failure(&"INVALID_DAMAGE")

	var projected_combo: RefCounted = GauntletsComboStateScript.new()
	if not bool(projected_combo.call(
		"restore_snapshot",
		(runtime_snapshot.get("combo_state", {}) as Dictionary).duplicate(true)
	)):
		return _failure(&"INVALID_RUNTIME_SNAPSHOT")
	var expected_snapshot := runtime_snapshot.duplicate(true)
	if not bool(result.get("hit_confirmed", result.get("hit", false))):
		return _payload_replay_projection_success(
			expected_snapshot,
			0,
			0,
			0,
			{},
			projected_combo.call("tier_snapshot") as Dictionary
		)

	var ledger := (source_ledgers[token_key] as Dictionary).duplicate(true)
	var is_echo := bool(result.get("is_echo", false))
	var combo_eligible := bool(ledger.get("combo_eligible", false)) and not is_echo
	if result.has("combo_eligible"):
		combo_eligible = combo_eligible and bool(result["combo_eligible"])
	var combo_result: Dictionary = projected_combo.call(
		"record_hit",
		token,
		generation,
		int(target_value),
		int(ledger.get("combo_gain", 0)),
		combo_eligible,
		int(ledger.get("combo_timeout_frames", 120))
	)
	if combo_eligible and not bool(combo_result.get("ok", false)):
		return _failure(StringName(str(combo_result.get("code", "INVALID_HIT"))))

	var frozen_tier := (ledger.get("combo_tier_snapshot", {}) as Dictionary).duplicate(true)
	var energy_eligible := not is_echo and bool(ledger.get("energy_eligible", false))
	if result.has("energy_eligible"):
		energy_eligible = energy_eligible and bool(result["energy_eligible"])
	var energy_return := int(frozen_tier.get("energy_return", 0)) if energy_eligible else 0

	var stop_eligible := not is_echo and bool(ledger.get("stop_extension_eligible", false))
	if result.has("stop_extension_eligible"):
		stop_eligible = stop_eligible and bool(result["stop_extension_eligible"])
	var stop_extension := 0
	if stop_eligible:
		var stop_generation := int(ledger.get("stop_generation", 0))
		if stop_generation > 0:
			var stop_key := str(stop_generation)
			var projected_stop_ledgers := (
				expected_snapshot.get("stop_extensions_by_generation", {}) as Dictionary
			).duplicate(true)
			var current_stop_extension := int(projected_stop_ledgers.get(stop_key, 0))
			stop_extension = mini(5, maxi(0, 30 - current_stop_extension))
			if stop_extension > 0:
				projected_stop_ledgers[stop_key] = current_stop_extension + stop_extension
				_prune_generation_dictionary(projected_stop_ledgers)
				expected_snapshot["stop_extensions_by_generation"] = projected_stop_ledgers

	var accelerate_eligible := (
		not is_echo
		and bool(ledger.get("accelerate_eligible", false))
		and not bool(result.get("recursive_echo", false))
	)
	var echo_descriptor: Dictionary = {}
	if accelerate_eligible:
		var accelerate_generation := int(ledger.get("accelerate_generation", 0))
		if accelerate_generation > 0:
			var accelerate_key := str(accelerate_generation)
			var projected_accelerate_ledgers := (
				expected_snapshot.get("accelerate_hits_by_generation", {}) as Dictionary
			).duplicate(true)
			var hit_count := int(projected_accelerate_ledgers.get(accelerate_key, 0)) + 1
			projected_accelerate_ledgers[accelerate_key] = hit_count
			_prune_generation_dictionary(projected_accelerate_ledgers)
			expected_snapshot["accelerate_hits_by_generation"] = projected_accelerate_ledgers
			if hit_count % 3 == 0:
				echo_descriptor = _accelerate_echo_descriptor(ledger)

	ledger["last_outcome_id"] = str(outcome_value)
	ledger["last_target_id"] = int(target_value)
	var projected_action_ledgers := source_ledgers.duplicate(true)
	projected_action_ledgers[token_key] = ledger
	expected_snapshot["action_ledgers"] = projected_action_ledgers

	var combo_snapshot := (projected_combo.call("snapshot") as Dictionary).duplicate(true)
	expected_snapshot["combo_state"] = combo_snapshot
	expected_snapshot["chain_step"] = int(combo_snapshot.get("chain_step", 0))
	expected_snapshot["combo_count"] = int(combo_snapshot.get("combo_count", 0))
	expected_snapshot["combo_remaining_frames"] = int(
		combo_snapshot.get("combo_timeout_frames_remaining", 0)
	)
	var tier := (projected_combo.call("tier_snapshot") as Dictionary).duplicate(true)
	if bool((tier.get("slow_aura", {}) as Dictionary).get("enabled", false)):
		expected_snapshot["aura_source_generation"] = generation
	elif int(expected_snapshot.get("aura_source_generation", 0)) > 0:
		expected_snapshot["aura_source_generation"] = 0

	return _payload_replay_projection_success(
		expected_snapshot,
		int(combo_result.get("combo_gain", 0)),
		energy_return,
		stop_extension,
		echo_descriptor,
		tier
	)


func _valid_payload_replay_projection_snapshot(value: Dictionary) -> bool:
	return (
		_has_exact_fields(value, RUNTIME_SNAPSHOT_FIELDS)
		and int(value.get("schema_version", -1)) == SNAPSHOT_SCHEMA_VERSION
		and bool(value.get("configured", false))
		and str(value.get("profile_id", "")) == PROFILE_ID
		and int(value.get("profile_version", 0)) == PROFILE_VERSION
		and value.get("combo_state") is Dictionary
		and value.get("stop_extensions_by_generation") is Dictionary
		and value.get("accelerate_hits_by_generation") is Dictionary
		and value.get("action_ledgers") is Dictionary
		and typeof(value.get("action_token_floor")) == TYPE_INT
		and int(value.get("action_token_floor", -1)) >= 0
		and _variant_numbers_are_finite(value)
	)


func _payload_replay_projection_success(
	expected_snapshot: Dictionary,
	combo_gain: int,
	energy_return: int,
	stop_extension_frames: int,
	echo_descriptor: Dictionary,
	tier: Dictionary
) -> Dictionary:
	return {
		"ok": true,
		"code": &"OK",
		"runtime_snapshot": expected_snapshot.duplicate(true),
		"context": {
			"combo_gain": combo_gain,
			"energy_return": energy_return,
			"stop_extension_frames": stop_extension_frames,
			"echo_descriptor": echo_descriptor.duplicate(true),
			"tier": tier.duplicate(true),
		},
	}


func advance_runtime_frame(coordinator_frame: int) -> Array[Dictionary]:
	if coordinator_frame < 0 or coordinator_frame <= _last_runtime_frame:
		return []
	var elapsed := 1 if _last_runtime_frame < 0 else coordinator_frame - _last_runtime_frame
	_last_runtime_frame = coordinator_frame
	if bool(_combo_state.call("advance_frames", elapsed)):
		_update_combo_aura(_aura_source_generation)
	return []


func on_dash_completed() -> void:
	_combo_state.call("notify_dash_completed")


func on_player_damaged(damage_amount: float = 1.0) -> void:
	if bool(_combo_state.call("notify_real_damage", damage_amount)):
		_update_combo_aura(_aura_source_generation)


func reset_combo() -> void:
	_combo_state.call("reset_combo", &"external_reset")
	_update_combo_aura(_aura_source_generation)


func cancel_action(token: int, _reason: StringName) -> void:
	if token > 0 and token == _active_token:
		_adapter.call("cancel_profile_action")
		_retire_action_token(token)
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
	var adapter_snapshot := runtime_snapshot["adapter"] as Dictionary
	var adapter_target := {
		"profile_action": (adapter_snapshot["profile_action"] as Dictionary).duplicate(true),
		"profile_action_released": bool(adapter_snapshot["profile_action_released"]),
		"prepared_payloads": (adapter_snapshot["prepared_payloads"] as Array).duplicate(true),
		"committed_payload_guard": gameplay_rewind_committed_payload_guard()["adapter"],
	}
	var before := snapshot()
	if not bool(_adapter.call("restore_gameplay_rewind_snapshot_for_rollback", adapter_target)):
		return false
	_active_token = int(runtime_snapshot["active_token"])
	_active_phase = StringName(str(runtime_snapshot["active_phase"]))
	_active_plan = (runtime_snapshot["active_plan"] as Dictionary).duplicate(true)
	_modifier_snapshot = (runtime_snapshot["modifier_snapshot"] as Dictionary).duplicate(true)
	_committed_definition = (runtime_snapshot["committed_definition"] as Dictionary).duplicate(true)
	_live_hold_context = (runtime_snapshot["live_hold_context"] as Dictionary).duplicate(true)
	if snapshot() == runtime_snapshot:
		return true
	_active_token = int(before["active_token"])
	_active_phase = StringName(str(before["active_phase"]))
	_active_plan = (before["active_plan"] as Dictionary).duplicate(true)
	_modifier_snapshot = (before["modifier_snapshot"] as Dictionary).duplicate(true)
	_committed_definition = (before["committed_definition"] as Dictionary).duplicate(true)
	_live_hold_context = (before["live_hold_context"] as Dictionary).duplicate(true)
	return false


func gameplay_rewind_committed_payload_guard() -> Dictionary:
	var adapter_value: Variant = _adapter.call("gameplay_rewind_committed_payload_guard")
	return {
		"adapter": (adapter_value as Dictionary).duplicate(true) if adapter_value is Dictionary else {},
		"combo_state": (_combo_state.call("snapshot") as Dictionary).duplicate(true),
		"last_runtime_frame": _last_runtime_frame,
		"stop_extensions_by_generation": _stop_extensions_by_generation.duplicate(true),
		"accelerate_hits_by_generation": _accelerate_hits_by_generation.duplicate(true),
		"claimed_rewind_generations": _claimed_rewind_generations.duplicate(),
		"claimed_rewind_generation_floor": _claimed_rewind_generation_floor,
		"action_ledgers": _action_ledgers.duplicate(true),
		"action_token_floor": _action_token_floor,
		"retired_action_token_floor": _retired_action_token_floor,
		"aura_source_generation": _aura_source_generation,
	}


func finish_action(token: int) -> void:
	if token > 0 and token == _active_token:
		_adapter.call("finish_profile_action")
		_retire_action_token(token)
		_clear_active_action()


func apply_modifier(effect_id: StringName, value: Variant) -> bool:
	return _modifier_state != null and _capabilities.has(str(effect_id)) and bool(_modifier_state.call("apply", effect_id, value))


func reset_runtime_state(_reason: StringName) -> void:
	if _adapter_bound and _adapter != null:
		_adapter.call("cancel_profile_action")
		_adapter.call("reset_runtime_state")
	_reset_runtime_domain_state(_reason)


func _reset_runtime_domain_state(_reason: StringName) -> void:
	_combo_state.call("reset", _reason)
	_last_runtime_frame = -1
	_stop_extensions_by_generation.clear()
	_accelerate_hits_by_generation.clear()
	_claimed_rewind_generations.clear()
	_claimed_rewind_generation_floor = 0
	_action_ledgers.clear()
	_action_token_floor = 0
	_retired_action_token_floor = 0
	_aura_source_generation = 0
	_clear_active_action()


func snapshot() -> Dictionary:
	var combo_snapshot := (_combo_state.call("snapshot") as Dictionary).duplicate(true)
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION, "configured": _is_configured(),
		"profile_id": str(_profile_snapshot.get("id", "")), "profile_version": int(_profile_snapshot.get("profile_version", 0)),
		"combo_state": combo_snapshot,
		"chain_step": int(combo_snapshot.get("chain_step", 0)),
		"combo_count": int(combo_snapshot.get("combo_count", 0)),
		"combo_remaining_frames": int(combo_snapshot.get("combo_timeout_frames_remaining", 0)),
		"last_runtime_frame": _last_runtime_frame,
		"stop_extensions_by_generation": _stop_extensions_by_generation.duplicate(true),
		"accelerate_hits_by_generation": _accelerate_hits_by_generation.duplicate(true),
		"claimed_rewind_generations": _claimed_rewind_generations.duplicate(),
		"claimed_rewind_generation_floor": _claimed_rewind_generation_floor,
		"action_ledgers": _action_ledgers.duplicate(true), "action_token_floor": _action_token_floor,
		"aura_source_generation": _aura_source_generation,
		"active_token": _active_token, "active_phase": str(_active_phase),
		"active_plan": _active_plan.duplicate(true), "modifier_snapshot": _modifier_snapshot.duplicate(true),
		"committed_definition": _committed_definition.duplicate(true), "live_hold_context": _live_hold_context.duplicate(true),
		"adapter_active": bool(_adapter.call("is_profile_action_active")) if _adapter != null else false,
		"adapter": (_adapter.call("runtime_snapshot") as Dictionary).duplicate(true) if _adapter != null else {},
	}


func restore_snapshot(runtime_snapshot: Dictionary) -> bool:
	if not _is_configured() or not _valid_restore_snapshot(runtime_snapshot):
		return false
	var previous := snapshot()
	if previous == runtime_snapshot:
		return true
	if not _apply_restore_snapshot(runtime_snapshot):
		if not _apply_restore_snapshot(previous):
			reset_runtime_state(&"snapshot_restore_rollback_failure")
		return false
	if snapshot() != runtime_snapshot:
		if not _apply_restore_snapshot(previous):
			reset_runtime_state(&"snapshot_restore_mismatch_rollback_failure")
		return false
	return true


func _apply_restore_snapshot(runtime_snapshot: Dictionary) -> bool:
	var staged_combo: RefCounted = GauntletsComboStateScript.new()
	if not bool(staged_combo.call("restore_snapshot", runtime_snapshot["combo_state"])):
		return false
	if not bool(_adapter.call(
		"restore_runtime_snapshot",
		(runtime_snapshot["adapter"] as Dictionary).duplicate(true)
	)):
		return false
	var target_aura_source_generation := int(runtime_snapshot["aura_source_generation"])
	var aura_transition := _transition_combo_aura(
		_aura_source_generation,
		target_aura_source_generation
	)
	if not bool(aura_transition.get("ok", false)):
		return false
	_aura_source_generation = target_aura_source_generation
	if not bool(_combo_state.call("restore_snapshot", runtime_snapshot["combo_state"])):
		return false
	_clear_active_action()
	_last_runtime_frame = int(runtime_snapshot["last_runtime_frame"])
	_stop_extensions_by_generation = (runtime_snapshot["stop_extensions_by_generation"] as Dictionary).duplicate(true)
	_accelerate_hits_by_generation = (runtime_snapshot["accelerate_hits_by_generation"] as Dictionary).duplicate(true)
	_claimed_rewind_generations = _int_array(runtime_snapshot["claimed_rewind_generations"])
	_claimed_rewind_generation_floor = int(runtime_snapshot["claimed_rewind_generation_floor"])
	_action_ledgers = (runtime_snapshot["action_ledgers"] as Dictionary).duplicate(true)
	_action_token_floor = int(runtime_snapshot["action_token_floor"])
	_active_token = int(runtime_snapshot["active_token"])
	_active_phase = StringName(str(runtime_snapshot["active_phase"]))
	_active_plan = (runtime_snapshot["active_plan"] as Dictionary).duplicate(true)
	_modifier_snapshot = (runtime_snapshot["modifier_snapshot"] as Dictionary).duplicate(true)
	_committed_definition = (runtime_snapshot["committed_definition"] as Dictionary).duplicate(true)
	_live_hold_context = (runtime_snapshot["live_hold_context"] as Dictionary).duplicate(true)
	return true


func presentation_snapshot() -> Dictionary:
	var combo := (_combo_state.call("snapshot") as Dictionary).duplicate(true)
	var tier := (_combo_state.call("tier_snapshot") as Dictionary).duplicate(true)
	return {
		"weapon_id": str(WEAPON_ID), "profile_id": PROFILE_ID, "profile_version": PROFILE_VERSION,
		"meter_kind": "combo", "meter_current": int(combo.get("combo_count", 0)), "meter_max": HIGH_COMBO_THRESHOLD,
		"status_id": str(tier.get("tier_id", "none")), "status_stacks": int(combo.get("combo_count", 0)),
		"status_remaining": int(combo.get("combo_timeout_frames_remaining", 0)),
		"secondary_id": "chain_step", "secondary_value": int(combo.get("chain_step", 0)),
		"chain_step": int(combo.get("chain_step", 0)),
		"combo_count": int(combo.get("combo_count", 0)),
		"combo_timeout_frames": int(combo.get("combo_timeout_frames_remaining", 0)),
		"combo_remaining_frames": int(combo.get("combo_timeout_frames_remaining", 0)),
		"counter_ready": _resolved_action_id(_active_plan) == str(DODGE_COUNTER_ACTION_ID),
		"combo_tier": tier, "next_chain_action_id": str(_combo_state.call("peek_primary_action_id")),
		"aura_active": bool((tier.get("slow_aura", {}) as Dictionary).get("enabled", false)),
		"facing": (_active_plan.get("aim_direction_snapshot", Vector2.RIGHT) as Vector2),
	}


func _build_primary_hold_plan(context: Dictionary) -> Dictionary:
	var allowed: Array[String] = []
	var fingerprints: Dictionary = {}
	for action_id: StringName in PRIMARY_ACTION_IDS:
		allowed.append(str(action_id))
		fingerprints[str(action_id)] = RELEASE_ACTION_FINGERPRINTS[str(action_id)]
	allowed.append(str(CHARGED_HEAVY_ACTION_ID))
	fingerprints[str(CHARGED_HEAVY_ACTION_ID)] = RELEASE_ACTION_FINGERPRINTS[str(CHARGED_HEAVY_ACTION_ID)]
	return _build_hold_skeleton(
		PRIMARY_HOLD_ACTION_ID, &"weapon_primary", context, 0,
		PRIMARY_MAXIMUM_HOLD_FRAMES, PRIMARY_CHARGE_FRAMES, allowed, fingerprints, 0.5
	)


func _build_ultimate_hold_plan(context: Dictionary) -> Dictionary:
	return _build_hold_skeleton(
		ULTIMATE_ACTION_ID, &"weapon_ultimate", context, ULTIMATE_HOLD_FRAMES,
		ULTIMATE_HOLD_FRAMES, ULTIMATE_HOLD_FRAMES, [str(ULTIMATE_ACTION_ID)],
		{str(ULTIMATE_ACTION_ID): RELEASE_ACTION_FINGERPRINTS[str(ULTIMATE_ACTION_ID)]},
		0.0, {"time_energy": 55.0}
	)


func _build_hold_skeleton(
	action_id: StringName,
	semantic_action: StringName,
	context: Dictionary,
	minimum_frames: int,
	maximum_frames: int,
	charge_complete_frames: int,
	allowed_release_action_ids: Array[String],
	release_action_fingerprints: Dictionary,
	movement_multiplier: float,
	resource_costs: Dictionary = {}
) -> Dictionary:
	var normalized := _normalized_context(context)
	if not bool(normalized.get("ok", false)):
		return normalized
	var modifiers := _frozen_modifiers()
	if not bool(modifiers.get("ok", false)):
		return modifiers
	var frozen_context := (normalized["context"] as Dictionary).duplicate(true)
	var plan := {
		"weapon_id": str(WEAPON_ID), "action_id": str(action_id),
		"profile_id": PROFILE_ID, "profile_version": PROFILE_VERSION,
		"semantic_action": str(semantic_action), "activation_mode": "release",
		"buffer_frames": 8, "cooldown_frames": 0,
		"resource_costs": resource_costs.duplicate(true),
		"run_seed": int(frozen_context["run_seed"]),
		"aim_direction_snapshot": frozen_context["aim_direction"],
		"modifier_snapshot": (modifiers["modifiers"] as Dictionary).duplicate(true),
		"frozen_context": frozen_context,
		"phases": [{
			"phase": "HOLD", "duration_frames": maximum_frames,
			"minimum_hold_frames": minimum_frames,
			"charge_complete_frames": charge_complete_frames,
			"movement_multiplier": movement_multiplier,
		}],
		"payloads": [], "cue": {}, "time_interactions": [],
		"boss_conversion": _boss_conversion(),
		"allowed_release_action_ids": allowed_release_action_ids.duplicate(),
		"release_action_fingerprints": release_action_fingerprints.duplicate(true),
	}
	_freeze_character_stats_into_plan(plan, frozen_context["character_stats"])
	WeaponForgivenessScript.attach_to_plan(
		plan, frozen_context.get("character_forgiveness", {})
	)
	var validation := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	return {"ok": true, "code": &"OK", "plan": plan, "context": {}} if bool(validation.get("ok", false)) else validation


func _build_primary_release_plan(held_frames: int, context: Dictionary) -> Dictionary:
	if held_frames < 0:
		return _failure(&"INVALID_HOLD_FRAMES")
	if held_frames >= PRIMARY_CHARGE_FRAMES:
		return _build_action_plan(CHARGED_HEAVY_ACTION_ID, context)
	return _build_action_plan(StringName(_combo_state.call("peek_primary_action_id")), context)


func _build_action_plan(action_id: StringName, context: Dictionary) -> Dictionary:
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
	var modifiers := _frozen_modifiers()
	if not bool(modifiers.get("ok", false)):
		return modifiers
	var frozen_context := (normalized["context"] as Dictionary).duplicate(true)
	var frozen_modifiers := (modifiers["modifiers"] as Dictionary).duplicate(true)
	var tier := (_combo_state.call("tier_snapshot") as Dictionary).duplicate(true)
	var time_context := (frozen_context.get("time_interactions", {}) as Dictionary).duplicate(true)
	var rewind_generation := int(time_context.get("rewind_generation", time_context.get("rewind_echo_generation", 0)))
	var rewind_requested := (
		action_id == DODGE_COUNTER_ACTION_ID
		and bool(time_context.get("rewind_counter_available", time_context.get("rewind_echo_available", false)))
		and rewind_generation > 0
	)
	var rewind_available := (
		rewind_requested
		and int(time_context.get("rewind_remaining_frames", 120)) > 0
		and rewind_generation > _claimed_rewind_generation_floor
		and not _claimed_rewind_generations.has(rewind_generation)
	)
	if rewind_requested and not rewind_available:
		return _failure(&"STALE_REWIND_GENERATION")
	var high_combo := int(tier.get("minimum_combo", 0)) >= HIGH_COMBO_THRESHOLD
	var intersecting_rifts := _intersecting_active_rifts(action_id, frozen_context, time_context)
	var rift_active := (
		high_combo
		and bool(time_context.get("rift_active", false))
		and not intersecting_rifts.is_empty()
	)
	var rift_source_generation := (
		int(intersecting_rifts[0].get("generation", 0))
		if rift_active
		else 0
	)
	var interaction_context := time_context.duplicate(true)
	interaction_context["active_rifts"] = intersecting_rifts.duplicate(true)
	interaction_context["rift_generation"] = rift_source_generation
	var combo_timeout_frames := clampi(
		roundi(120.0 * float(frozen_modifiers.get("weapon.combo_timeout", 1.0))),
		1, GauntletsComboStateScript.MAX_COMBO_TIMEOUT_FRAMES
	)
	var forgiveness := (
		frozen_context.get("character_forgiveness", {}) as Dictionary
	).duplicate(true)
	var status_duration_multiplier := maxf(0.0, float(frozen_modifiers.get("weapon.status_duration", 1.0)))
	var parameters := (payload.get("parameters", {}) as Dictionary).duplicate(true)
	var damage_multiplier := float(parameters.get("damage_multiplier", 0.0))
	if rewind_available:
		damage_multiplier *= 2.0
	if action_id == ULTIMATE_ACTION_ID and int(tier.get("minimum_combo", 0)) >= 20:
		damage_multiplier *= 1.3
	parameters["damage_multiplier"] = damage_multiplier
	parameters["resolved_damage_multiplier"] = damage_multiplier * float(frozen_modifiers.get("weapon.damage", 1.0))
	parameters["critical_chance_bonus"] = float(tier.get("critical_chance_bonus", 0.0))
	parameters["time_damage_ratio"] = float(tier.get("time_damage_ratio", 0.0)) if PRIMARY_ACTION_IDS.has(action_id) else 0.0
	parameters["energy_return"] = int(tier.get("energy_return", 0))
	parameters["combo_eligible"] = int(parameters.get("combo_gain", 0)) > 0
	if bool(parameters["combo_eligible"]) and not forgiveness.is_empty():
		combo_timeout_frames = mini(
			WeaponForgivenessScript.descriptor_int(
				forgiveness, WEAPON_ID, "combo_cap_frames", combo_timeout_frames
			),
			combo_timeout_frames + WeaponForgivenessScript.descriptor_int(
				forgiveness, WEAPON_ID, "combo_extension_frames", 0
			)
		)
	parameters["energy_eligible"] = int(tier.get("energy_return", 0)) > 0
	parameters["stop_extension_eligible"] = bool(time_context.get("stop_active", false))
	parameters["stop_extension_frames"] = 5 if bool(time_context.get("stop_active", false)) else 0
	parameters["recursive_echo"] = false
	parameters["is_echo"] = false
	parameters["active_frames"] = int(action.get("active_frames", 1))
	if action_id == &"punch_5":
		parameters["knockback_tiles"] = 1.5
		parameters["displacement_tiles"] = 1.5
		if int(tier.get("minimum_combo", 0)) >= 15:
			parameters["time_damage_ratio"] = 0.5
	if action_id == CHARGED_HEAVY_ACTION_ID:
		parameters["knockback_tiles"] = 3.0
		parameters["zone"] = _zone_parameters(
			"charged_heavy_shockwave", 1.5, 1, 1, 0.2,
			{"physical": 1.0}, 1.0, status_duration_multiplier, rift_active
		)
	if action_id == DODGE_COUNTER_ACTION_ID:
		parameters["critical_chance_bonus"] = float(parameters["critical_chance_bonus"]) + 0.25
		parameters["knockback_tiles"] = 1.5
		if rewind_available:
			parameters["zone"] = _zone_parameters(
				"rewind_counter_shockwave", 2.0, 1, 1, 0.8,
				{"time": 1.0}, 1.0, status_duration_multiplier, rift_active
			)
	if action_id == SKILL_ACTION_ID:
		parameters["damage_type_split"] = {"physical": 0.5, "time": 0.5}
		var skill_radius := 2.5 if int(tier.get("minimum_combo", 0)) >= 10 else 2.0
		var skill_duration := 300 if int(tier.get("minimum_combo", 0)) >= 20 else 180
		parameters["knockback_tiles"] = 2.5
		parameters["zone"] = _zone_parameters(
			"space_time_shatter", skill_radius, skill_duration, 30, 0.15,
			{"time": 1.0}, 0.6, status_duration_multiplier, rift_active
		)
	if action_id == ULTIMATE_ACTION_ID:
		parameters["damage_type_split"] = {"physical": 0.3, "time": 0.4, "void": 0.3}
		parameters["shared_damage_claim"] = true
		parameters["knockback_tiles"] = 3.0
		parameters["launch"] = 2.0
		parameters["displacement_tiles"] = 3.0
		parameters["zone"] = _zone_parameters(
			"primordial_collapse", 3.0, 300, 30, 0.1,
			{"time": 0.5, "void": 0.5}, 0.7,
			status_duration_multiplier, rift_active
		)
	if rift_active:
		parameters["rift_context"] = {
			"source_generation": rift_source_generation,
			"spatial_policy": "zone_intersection",
			"effect_multiplier": 1.5,
			"active_rifts": intersecting_rifts.duplicate(true),
		}
		if parameters.get("zone", {}) is Dictionary:
			(parameters["zone"] as Dictionary)["rift_source_generation"] = rift_source_generation
	var timing_scale := 1.0 / maxf(
		0.01,
		float((frozen_context["character_stats"] as Dictionary)["attack_speed"])
		* float(frozen_modifiers.get("weapon.attack_speed", 1.0))
		* float(tier.get("attack_speed_multiplier", 1.0))
	)
	var windup := _scaled_frames(int(action["windup_frames"]), timing_scale)
	var active := int(action["active_frames"])
	var recovery := _scaled_frames(int(action["recovery_frames"]), timing_scale)
	var recovery_phase := {
		"phase": "RECOVERY", "duration_frames": recovery,
		"movement_multiplier": float(action["movement_multiplier"]),
	}
	var cancel_value: Variant = action.get("cancel_from_frame")
	if cancel_value != null:
		recovery_phase["cancel_from_frame"] = clampi(
			int(cancel_value), 0, recovery - 1
		)
	var resource_costs := (action.get("resource_costs", {}) as Dictionary).duplicate(true)
	if rift_active and resource_costs.has("time_energy"):
		resource_costs["time_energy"] = float(resource_costs["time_energy"]) * 0.7
	var plan_payloads: Array[Dictionary] = [{
		"descriptor_id": str(payload_id),
		"kind": str(payload["kind"]),
		"parameters": parameters,
	}]
	if action_id == ULTIMATE_ACTION_ID:
		plan_payloads.append({
			"descriptor_id": "gauntlets_primordial_collapse_wave",
			"kind": "shockwave",
			"parameters": {
				"damage_multiplier": damage_multiplier,
				"resolved_damage_multiplier": damage_multiplier * float(frozen_modifiers.get("weapon.damage", 1.0)),
				"damage_type_split": {"physical": 0.3, "time": 0.4, "void": 0.3},
				"shape": "arc", "range_tiles": 4.0, "arc_degrees": 120.0,
				"knockback_tiles": 3.0, "combo_gain": 0,
				"shared_damage_claim": true,
				"combo_eligible": false, "energy_eligible": false,
				"stop_extension_eligible": false, "recursive_echo": false,
				"is_echo": false, "active_frames": int(action.get("active_frames", 10)),
			},
		})
	var plan := {
		"weapon_id": str(WEAPON_ID), "action_id": str(action_id),
		"profile_id": PROFILE_ID, "profile_version": PROFILE_VERSION,
		"semantic_action": str(action["semantic_action"]),
		"activation_mode": str(action["activation_mode"]),
		"buffer_frames": int(action["buffer_frames"]),
		"cooldown_frames": int(action.get("cooldown_frames", 0)),
		"resource_costs": resource_costs,
		"run_seed": int(frozen_context["run_seed"]),
		"aim_direction_snapshot": frozen_context["aim_direction"],
		"modifier_snapshot": frozen_modifiers, "frozen_context": frozen_context,
		"combo_tier_snapshot": tier,
		"combo_timeout_frames": combo_timeout_frames,
		"status_duration_multiplier": status_duration_multiplier,
		"rewind_generation_claim": rewind_generation if rewind_available else 0,
		"phases": [
			{"phase": "WINDUP", "duration_frames": windup, "movement_multiplier": float(action["movement_multiplier"])},
			{"phase": "ACTIVE", "duration_frames": active, "movement_multiplier": float(action["movement_multiplier"])},
			recovery_phase,
		],
		"payloads": plan_payloads,
		"cue": cue,
		"time_interactions": _time_interaction_descriptors(action_id, interaction_context, rewind_available, rift_active),
		"boss_conversion": _boss_conversion(),
		"invulnerable_during_cast": action_id in [DODGE_COUNTER_ACTION_ID, ULTIMATE_ACTION_ID],
	}
	_freeze_character_stats_into_plan(plan, frozen_context["character_stats"])
	if bool(parameters.get("combo_eligible", false)):
		WeaponForgivenessScript.attach_to_plan(plan, forgiveness)
	var validation := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	return {"ok": true, "code": &"OK", "plan": plan, "context": {}} if bool(validation.get("ok", false)) else validation


func _stage_and_commit(plan: Dictionary, token: int) -> Dictionary:
	var staged := _stage_definition(plan, token)
	if not bool(staged.get("ok", false)):
		return staged
	_apply_committed_mutations(plan, token)
	_active_token = token
	_active_phase = StringName(str(((plan["phases"] as Array)[0] as Dictionary)["phase"]))
	_active_plan = plan.duplicate(true)
	_modifier_snapshot = (plan.get("modifier_snapshot", {}) as Dictionary).duplicate(true)
	return {
		"ok": true,
		"code": &"OK",
		"context": WeaponForgivenessScript.merge_consumption_context(
			{"action_id": _resolved_action_id(plan)}, plan, WEAPON_ID
		),
	}


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
		"token": token, "generation": token, "profile_id": PROFILE_ID,
		"weapon_id": str(WEAPON_ID), "action_id": _resolved_action_id(plan),
		"semantic_action": str(plan.get("semantic_action", "")),
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
	var payloads: Variant = plan.get("payloads", [])
	if not payloads is Array or (payloads as Array).is_empty():
		return []
	var action_id := StringName(_resolved_action_id(plan))
	var result: Array[Dictionary] = []
	for outcome_index: int in range((payloads as Array).size()):
		var payload_value: Variant = (payloads as Array)[outcome_index]
		if not payload_value is Dictionary:
			return []
		var payload := payload_value as Dictionary
		var payload_id := StringName(str(payload.get("descriptor_id", "")))
		var parameters := (payload.get("parameters", {}) as Dictionary).duplicate(true)
		parameters["direction"] = plan.get("aim_direction_snapshot", Vector2.RIGHT)
		result.append({
			"descriptor_id": str(payload_id), "kind": str(payload.get("kind", "")),
			"token": token, "generation": token, "outcome_index": outcome_index,
			"seed": SeedServiceScript.derive_weapon_action_seed(
				int(plan.get("run_seed", 0)), StringName(PROFILE_ID), action_id,
				payload_id, token, outcome_index
			),
			"target_deduplication": "per_action_target", "parameters": parameters,
		})
	return result


func _apply_committed_mutations(plan: Dictionary, token: int) -> void:
	var envelope := WeaponForgivenessScript.envelope_from_plan(plan, WEAPON_ID)
	if not envelope.is_empty():
		_combo_state.call(
			"extend_active_timeout",
			WeaponForgivenessScript.descriptor_int(
				envelope, WEAPON_ID, "combo_extension_frames", 0
			),
			WeaponForgivenessScript.descriptor_int(
				envelope, WEAPON_ID, "combo_cap_frames", 120
			)
		)
	var action_id := StringName(_resolved_action_id(plan))
	if PRIMARY_ACTION_IDS.has(action_id):
		_combo_state.call("commit_primary_action", action_id, token)
	var rewind_generation := int(plan.get("rewind_generation_claim", 0))
	if rewind_generation > 0:
		_append_bounded_generation(_claimed_rewind_generations, rewind_generation)
	_action_ledgers[str(token)] = _action_ledger(plan, token)
	_prune_action_ledgers()


func _action_ledger(plan: Dictionary, token: int) -> Dictionary:
	var action_id := StringName(_resolved_action_id(plan))
	var parameters := _payload_parameters(plan)
	var time_context := ((plan.get("frozen_context", {}) as Dictionary).get("time_interactions", {}) as Dictionary).duplicate(true)
	return {
		"generation": token, "action_id": str(action_id),
		"combo_gain": int(parameters.get("combo_gain", 0)),
		"combo_eligible": int(parameters.get("combo_gain", 0)) > 0,
		"energy_eligible": int(parameters.get("energy_return", 0)) > 0,
		"stop_extension_eligible": bool(time_context.get("stop_active", false)),
		"stop_generation": int(time_context.get("stop_generation", 0)),
		"accelerate_eligible": PRIMARY_ACTION_IDS.has(action_id) and bool(time_context.get("accelerate_active", false)),
		"accelerate_generation": int(time_context.get("accelerate_generation", 0)),
		"damage_multiplier": float(parameters.get("damage_multiplier", 0.0)),
		"combo_timeout_frames": int(plan.get("combo_timeout_frames", 120)),
		"combo_tier_snapshot": (plan.get("combo_tier_snapshot", {}) as Dictionary).duplicate(true),
		"run_seed": int(plan.get("run_seed", 0)),
		"payload_id": str(((plan.get("payloads", []) as Array)[0] as Dictionary).get("descriptor_id", "")),
	}


func _apply_stop_extension(
	action_token: int,
	payload_generation: int,
	stop_generation: int
) -> int:
	if (
		action_token <= 0
		or payload_generation != action_token
		or stop_generation <= 0
		or _owner == null
		or not is_instance_valid(_owner)
		or not _owner.has_method("extend_weapon_time_stop_for_payload_result")
	):
		return 0
	var key := str(stop_generation)
	var current := int(_stop_extensions_by_generation.get(key, 0))
	var granted := mini(5, maxi(0, 30 - current))
	if granted <= 0:
		return 0
	if not bool(_owner.call(
		"extend_weapon_time_stop_for_payload_result",
		action_token,
		payload_generation,
		granted
	)):
		return 0
	_stop_extensions_by_generation[key] = current + granted
	_prune_generation_dictionary(_stop_extensions_by_generation)
	return granted


func _zone_parameters(
	mode: String,
	radius_tiles: float,
	duration_frames: int,
	tick_interval_frames: int,
	damage_multiplier: float,
	damage_type_split: Dictionary,
	move_speed_multiplier: float,
	status_duration_multiplier: float,
	rift_empowered: bool
) -> Dictionary:
	var duration_scale := status_duration_multiplier
	if mode in ["charged_heavy_shockwave", "rewind_counter_shockwave"]:
		duration_scale = 1.0
	var effect_scale := 1.5 if rift_empowered else 1.0
	var duration := maxi(1, roundi(float(duration_frames) * duration_scale * effect_scale))
	return {
		"mode": mode,
		"radius_tiles": radius_tiles * effect_scale,
		"duration_frames": duration,
		"tick_interval_frames": mini(duration, maxi(1, tick_interval_frames)),
		"damage_multiplier": damage_multiplier,
		"damage_type_split": damage_type_split.duplicate(true),
		"move_speed_multiplier": move_speed_multiplier,
		"rift_effect_multiplier": effect_scale,
	}


func _intersecting_active_rifts(
	action_id: StringName,
	frozen_context: Dictionary,
	time_context: Dictionary
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var rifts_value: Variant = time_context.get("active_rifts", [])
	if not rifts_value is Array or (rifts_value as Array).is_empty():
		return result
	var rift_generation := int(time_context.get("rift_generation", 0))
	if rift_generation <= 0:
		return result
	var origin := Vector2.ZERO
	if _owner is Node2D:
		origin = (_owner as Node2D).global_position
	var direction := frozen_context.get("aim_direction", Vector2.RIGHT) as Vector2
	var geometry := _action_geometry(action_id)
	var endpoint := origin + direction.normalized() * float(geometry["range_pixels"])
	var half_width := float(geometry["half_width_pixels"])
	for value: Variant in rifts_value as Array:
		if not value is Dictionary:
			continue
		var descriptor := value as Dictionary
		if int(descriptor.get("generation", 0)) != rift_generation:
			continue
		var center_value: Variant = descriptor.get("center")
		var radius_value: Variant = descriptor.get("radius")
		if not center_value is Vector2 or typeof(radius_value) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		if _distance_to_segment(center_value as Vector2, origin, endpoint) <= float(radius_value) + half_width:
			result.append((descriptor as Dictionary).duplicate(true))
	return result


func _action_geometry(action_id: StringName) -> Dictionary:
	match action_id:
		&"punch_1", &"punch_2":
			return {"range_pixels": 96.0, "half_width_pixels": 32.0}
		&"punch_3", &"punch_4":
			return {"range_pixels": 115.2, "half_width_pixels": 115.2}
		&"punch_5":
			return {"range_pixels": 128.0, "half_width_pixels": 38.4}
		&"charged_heavy":
			return {"range_pixels": 160.0, "half_width_pixels": 48.0}
		&"dodge_counter":
			return {"range_pixels": 128.0, "half_width_pixels": 128.0}
		&"space_time_shatter":
			return {"range_pixels": 192.0, "half_width_pixels": 64.0}
		&"primordial_collapse_punch":
			return {"range_pixels": 320.0, "half_width_pixels": 96.0}
	return {"range_pixels": 0.0, "half_width_pixels": 0.0}


func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(start)
	var projection := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * projection)


func _restore_time_energy(amount: float) -> void:
	if amount <= 0.0 or _owner == null or not is_instance_valid(_owner):
		return
	var time_manager := _owner.get_node_or_null("TimeManager")
	if time_manager != null and time_manager.has_method("restore_energy"):
		time_manager.call("restore_energy", amount)
	elif _owner.has_method("restore_weapon_time_energy"):
		_owner.call("restore_weapon_time_energy", amount)


func _advance_accelerate(generation: int, ledger: Dictionary) -> Dictionary:
	if generation <= 0:
		return {}
	var key := str(generation)
	var hit_count := int(_accelerate_hits_by_generation.get(key, 0)) + 1
	_accelerate_hits_by_generation[key] = hit_count
	_prune_generation_dictionary(_accelerate_hits_by_generation)
	if hit_count % 3 != 0:
		return {}
	return _accelerate_echo_descriptor(ledger)


func _accelerate_echo_descriptor(ledger: Dictionary) -> Dictionary:
	var payload_id := StringName(str(ledger.get("payload_id", "")))
	var action_id := StringName(str(ledger.get("action_id", "")))
	var multiplier := float(ledger.get("damage_multiplier", 0.0)) * 0.5
	return {
		"descriptor_id": "%s_echo" % str(payload_id), "kind": "hitbox",
		"outcome_index": 1,
		"seed": SeedServiceScript.derive_weapon_action_seed(
			int(ledger.get("run_seed", 0)), StringName(PROFILE_ID), action_id,
			payload_id, int(ledger.get("generation", 0)), 1
		),
		"target_deduplication": "per_action_target",
		"parameters": {
			"damage_multiplier": multiplier, "resolved_damage_multiplier": multiplier,
			"combo_gain": 0, "energy_return": 0, "stop_extension_frames": 0,
			"combo_eligible": false, "energy_eligible": false,
			"stop_extension_eligible": false, "recursive_echo": false,
			"is_echo": true, "active_frames": 1,
		},
	}


func _time_interaction_descriptors(
	action_id: StringName,
	time_context: Dictionary,
	rewind_available: bool,
	rift_active: bool
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if bool(time_context.get("stop_active", false)):
		result.append({
			"id": "stop", "interaction_id": "gauntlets_stop_extension",
			"per_hit_frames": 5, "maximum_bonus_frames": 30,
			"source_generation": int(time_context.get("stop_generation", 0)),
		})
	if rewind_available:
		result.append({
			"id": "rewind", "interaction_id": "gauntlets_rewind_counter",
			"damage_multiplier": 2.0,
			"rewind_generation": int(time_context.get("rewind_generation", time_context.get("rewind_echo_generation", 0))),
		})
	if PRIMARY_ACTION_IDS.has(action_id) and bool(time_context.get("accelerate_active", false)):
		result.append({
			"id": "accelerate", "interaction_id": "gauntlets_third_hit_echo",
			"hit_interval": 3, "damage_multiplier": 0.5,
			"source_generation": int(time_context.get("accelerate_generation", 0)),
		})
	if rift_active:
		result.append({
			"id": "rift", "interaction_id": "gauntlets_rift_control",
			"effect_multiplier": 1.5, "cost_multiplier": 0.7,
			"source_generation": int(time_context.get("rift_generation", 0)),
			"spatial_policy": "zone_intersection",
			"active_rifts": (time_context.get("active_rifts", []) as Array).duplicate(true),
		})
	return result


func _boss_conversion() -> Dictionary:
	return {
		"target_id": "chrono_warden", "conversion_id": "gauntlets_poised_launch",
		"active_attack_policy": "preserve_committed",
		"preserve_committed_active_attack": true,
		"allowed_phases": ["RECOVERY", "EXPOSED"],
		"control_conversion": "poise_contribution", "poise_multiplier": 1.4,
		"airborne": false, "target_deduplication": true,
	}


func _validate_commit_plan(plan: Dictionary) -> Dictionary:
	var contract := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	if not bool(contract.get("ok", false)):
		return contract
	if not WeaponForgivenessScript.plan_envelope_is_valid(plan, WEAPON_ID):
		return _failure(&"INVALID_FORGIVENESS_FINGERPRINT")
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
	var base_combo_timeout := clampi(
		roundi(120.0 * float((plan.get("modifier_snapshot", {}) as Dictionary).get(
			"weapon.combo_timeout", 1.0
		))),
		1,
		GauntletsComboStateScript.MAX_COMBO_TIMEOUT_FRAMES
	)
	var expected_combo_timeout := base_combo_timeout
	var forgiveness_envelope := WeaponForgivenessScript.envelope_from_plan(plan, WEAPON_ID)
	if not forgiveness_envelope.is_empty():
		expected_combo_timeout = mini(
			WeaponForgivenessScript.descriptor_int(
				forgiveness_envelope, WEAPON_ID, "combo_cap_frames", base_combo_timeout
			),
			base_combo_timeout + WeaponForgivenessScript.descriptor_int(
				forgiveness_envelope, WEAPON_ID, "combo_extension_frames", 0
			)
		)
	if int(plan.get("combo_timeout_frames", 0)) != expected_combo_timeout:
		return _failure(&"COMBO_TIMEOUT_MISMATCH")
	if PRIMARY_ACTION_IDS.has(action_id) and action_id != StringName(_combo_state.call("peek_primary_action_id")):
		return _failure(&"STALE_CHAIN_PLAN")
	var rewind_generation := int(plan.get("rewind_generation_claim", 0))
	if rewind_generation > 0 and (
		rewind_generation <= _claimed_rewind_generation_floor
		or _claimed_rewind_generations.has(rewind_generation)
	):
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
	var direction := direction_value as Vector2
	if not is_finite(direction.x) or not is_finite(direction.y) or direction.is_zero_approx():
		return _failure(&"INVALID_CONTEXT", {"field": "aim_direction"})
	if not time_value is Dictionary or not _variant_numbers_are_finite(time_value):
		return _failure(&"INVALID_CONTEXT", {"field": "time_interactions"})
	var time_context := (time_value as Dictionary).duplicate(true)
	var active_rifts_value: Variant = time_context.get("active_rifts", [])
	if not active_rifts_value is Array:
		return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.active_rifts"})
	var normalized_rifts: Array[Dictionary] = []
	var seen_rift_generations: Dictionary = {}
	for descriptor_value: Variant in active_rifts_value as Array:
		if not descriptor_value is Dictionary:
			return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.active_rifts"})
		var descriptor := descriptor_value as Dictionary
		var generation_value: Variant = descriptor.get("generation")
		var center_value: Variant = descriptor.get("center")
		var radius_value: Variant = descriptor.get("radius")
		if (
			typeof(generation_value) != TYPE_INT
			or int(generation_value) <= 0
			or seen_rift_generations.has(int(generation_value))
			or not center_value is Vector2
			or not is_finite((center_value as Vector2).x)
			or not is_finite((center_value as Vector2).y)
			or typeof(radius_value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(radius_value))
			or float(radius_value) <= 0.0
		):
			return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.active_rifts"})
		seen_rift_generations[int(generation_value)] = true
		normalized_rifts.append({
			"generation": int(generation_value),
			"center": center_value as Vector2,
			"radius": float(radius_value),
		})
	normalized_rifts.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left["generation"]) < int(right["generation"])
	)
	time_context["active_rifts"] = normalized_rifts
	for boolean_field: String in [
		"stop_active", "rewind_counter_available", "rewind_echo_available",
		"accelerate_active", "rift_active",
	]:
		if time_context.has(boolean_field) and typeof(time_context[boolean_field]) != TYPE_BOOL:
			return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.%s" % boolean_field})
	for generation_field: String in [
		"stop_generation", "rewind_generation", "rewind_echo_generation",
		"accelerate_generation", "rift_generation",
	]:
		if time_context.has(generation_field) and (
			typeof(time_context[generation_field]) != TYPE_INT
			or int(time_context[generation_field]) < 0
		):
			return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.%s" % generation_field})
	if bool(time_context.get("rift_active", false)):
		var rift_generation_value: Variant = time_context.get("rift_generation")
		if (
			typeof(rift_generation_value) != TYPE_INT
			or int(rift_generation_value) <= 0
			or not seen_rift_generations.has(int(rift_generation_value))
		):
			return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.rift_generation"})
	var character_stats_value: Variant = value.get("character_stats", {})
	var character_stats := (
		(character_stats_value as Dictionary).duplicate(true)
		if character_stats_value is Dictionary and not (character_stats_value as Dictionary).is_empty()
		else _character_stats_snapshot(_adapter)
	)
	if not _valid_character_stats_snapshot(character_stats):
		return _failure(&"INVALID_CONTEXT", {"field": "character_stats"})
	var forgiveness_envelope: Dictionary = {}
	if value.has("character_forgiveness"):
		var forgiveness_value: Variant = value.get("character_forgiveness")
		if (
			forgiveness_value is Dictionary
			and WeaponForgivenessScript.is_valid_envelope(
				forgiveness_value as Dictionary, WEAPON_ID
			)
		):
			forgiveness_envelope = (forgiveness_value as Dictionary).duplicate(true)
		else:
			var forgiveness_result := WeaponForgivenessScript.freeze_from_context(value, WEAPON_ID)
			if not bool(forgiveness_result.get("ok", false)):
				return _failure(&"INVALID_FORGIVENESS_DESCRIPTOR")
			forgiveness_envelope = (
				forgiveness_result.get("envelope", {}) as Dictionary
			).duplicate(true)
	var normalized_context := {
		"run_seed": int(run_seed_value), "aim_direction": direction.normalized(),
		"dash_completion_token": int(value.get("dash_completion_token", 0)),
		"frames_since_dash_completion": int(value.get("frames_since_dash_completion", -1)),
		"dash_direction": value.get("dash_direction", direction.normalized()),
		"player_generation": int(value.get("player_generation", 0)),
		"time_interactions": time_context,
		"character_stats": character_stats,
	}
	if not forgiveness_envelope.is_empty():
		normalized_context["character_forgiveness"] = forgiveness_envelope
	return {
		"ok": true, "code": &"OK",
		"context": normalized_context,
	}


func _counter_window_is_open(context: Dictionary) -> bool:
	var token_value: Variant = context.get("dash_completion_token", 0)
	var age_value: Variant = context.get("frames_since_dash_completion", -1)
	return (
		typeof(token_value) == TYPE_INT and int(token_value) > 0
		and typeof(age_value) == TYPE_INT and int(age_value) >= 0
		and int(age_value) <= COUNTER_WINDOW_LAST_FRAME
	)


func _frozen_modifiers() -> Dictionary:
	var value: Variant = _modifier_state.call("freeze_for_action")
	if not value is Dictionary or not _variant_numbers_are_finite(value):
		return _failure(&"INVALID_MODIFIER_SNAPSHOT")
	return {"ok": true, "code": &"OK", "modifiers": (value as Dictionary).duplicate(true)}


func _update_combo_aura(source_generation: int) -> bool:
	var tier := _combo_state.call("tier_snapshot") as Dictionary
	var enabled := bool((tier.get("slow_aura", {}) as Dictionary).get("enabled", false))
	if enabled:
		var generation := source_generation if source_generation > 0 else _aura_source_generation
		if generation <= 0:
			reset_runtime_state(&"combo_aura_source_missing")
			return false
		if not bool(_adapter.call("set_combo_slow_aura", true, generation)):
			reset_runtime_state(&"combo_aura_activation_failed")
			return false
		_aura_source_generation = generation
	elif _aura_source_generation > 0:
		if not bool(_adapter.call("set_combo_slow_aura", false, _aura_source_generation)):
			reset_runtime_state(&"combo_aura_cleanup_failed")
			return false
		_aura_source_generation = 0
	return true


func _transition_combo_aura(current_generation: int, target_generation: int) -> Dictionary:
	if current_generation == target_generation:
		return {"ok": true, "restored": true}
	if current_generation > 0:
		if not bool(_adapter.call("set_combo_slow_aura", false, current_generation)):
			return {"ok": false, "restored": true}
	if target_generation > 0:
		if not bool(_adapter.call("set_combo_slow_aura", true, target_generation)):
			var restored := (
				current_generation <= 0
				or bool(_adapter.call("set_combo_slow_aura", true, current_generation))
			)
			return {"ok": false, "restored": restored}
	return {"ok": true, "restored": true}


func _transition_adapter_action(
	current_active: bool,
	current_definition: Dictionary,
	target_active: bool,
	target_definition: Dictionary
) -> bool:
	if (
		current_active == target_active
		and (not current_active or current_definition == target_definition)
	):
		return true
	if current_active:
		_adapter.call("cancel_profile_action")
	return _install_adapter_action(target_active, target_definition)


func _install_adapter_action(active: bool, definition: Dictionary) -> bool:
	if not active:
		return true
	var restored_value: Variant = _adapter.call("begin_profile_action", definition.duplicate(true))
	if restored_value is Dictionary and (restored_value as Dictionary) == definition:
		return true
	_adapter.call("cancel_profile_action")
	return false


func _effective_action_token_floor() -> int:
	return maxi(_action_token_floor, _retired_action_token_floor)


func _retire_action_token(token: int) -> void:
	if token <= 0:
		return
	_action_ledgers.erase(str(token))
	_action_token_floor = maxi(_action_token_floor, token)
	_retired_action_token_floor = maxi(_retired_action_token_floor, token)


func _prune_action_ledgers() -> void:
	if _action_ledgers.size() <= MAX_TRACKED_ACTIONS:
		return
	var tokens: Array[int] = []
	for key: Variant in _action_ledgers.keys():
		var token := int(str(key))
		if token > 0:
			tokens.append(token)
	tokens.sort()
	while tokens.size() > MAX_TRACKED_ACTIONS:
		var removed := int(tokens.pop_front())
		_action_ledgers.erase(str(removed))
		_action_token_floor = maxi(_action_token_floor, removed)


func _append_bounded_generation(values: Array[int], generation: int) -> void:
	if generation <= 0 or values.has(generation):
		return
	values.append(generation)
	values.sort()
	while values.size() > MAX_TRACKED_GENERATIONS:
		_claimed_rewind_generation_floor = maxi(_claimed_rewind_generation_floor, int(values.pop_front()))


func _prune_generation_dictionary(values: Dictionary) -> void:
	if values.size() <= MAX_TRACKED_GENERATIONS:
		return
	var generations: Array[int] = []
	for key: Variant in values.keys():
		generations.append(int(str(key)))
	generations.sort()
	while generations.size() > MAX_TRACKED_GENERATIONS:
		values.erase(str(generations.pop_front()))


func _valid_restore_snapshot(value: Dictionary) -> bool:
	if not _has_exact_fields(value, RUNTIME_SNAPSHOT_FIELDS):
		return false
	if (
		int(value.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION
		or not bool(value.get("configured", false))
		or str(value.get("profile_id", "")) != PROFILE_ID
		or int(value.get("profile_version", 0)) != PROFILE_VERSION
		or not value.get("combo_state") is Dictionary
		or typeof(value.get("chain_step")) != TYPE_INT
		or typeof(value.get("combo_count")) != TYPE_INT
		or typeof(value.get("combo_remaining_frames")) != TYPE_INT
		or typeof(value.get("last_runtime_frame")) != TYPE_INT
		or int(value.get("last_runtime_frame", -2)) < -1
		or not value.get("stop_extensions_by_generation") is Dictionary
		or not value.get("accelerate_hits_by_generation") is Dictionary
		or not value.get("claimed_rewind_generations") is Array
		or (value.get("claimed_rewind_generations") as Array).size() > MAX_TRACKED_GENERATIONS
		or typeof(value.get("claimed_rewind_generation_floor")) != TYPE_INT
		or int(value.get("claimed_rewind_generation_floor", -1)) < 0
		or not value.get("action_ledgers") is Dictionary
		or (value.get("action_ledgers") as Dictionary).size() > MAX_TRACKED_ACTIONS
		or typeof(value.get("action_token_floor")) != TYPE_INT
		or int(value.get("action_token_floor", -1)) < 0
		or typeof(value.get("aura_source_generation")) != TYPE_INT
		or int(value.get("aura_source_generation", -1)) < 0
		or typeof(value.get("active_token")) != TYPE_INT
		or int(value.get("active_token", -1)) < 0
		or not value.get("active_plan") is Dictionary
		or not value.get("modifier_snapshot") is Dictionary
		or not value.get("committed_definition") is Dictionary
		or not value.get("live_hold_context") is Dictionary
		or typeof(value.get("adapter_active")) != TYPE_BOOL
		or not value.get("adapter") is Dictionary
		or not bool(_adapter.call(
			"can_restore_runtime_snapshot",
			(value.get("adapter", {}) as Dictionary).duplicate(true)
		))
		or not _variant_numbers_are_finite(value)
	):
		return false
	if not _valid_generation_array(value["claimed_rewind_generations"]):
		return false
	var combo_snapshot := value["combo_state"] as Dictionary
	if (
		int(value["chain_step"]) != int(combo_snapshot.get("chain_step", -1))
		or int(value["combo_count"]) != int(combo_snapshot.get("combo_count", -1))
		or int(value["combo_remaining_frames"]) != int(
			combo_snapshot.get("combo_timeout_frames_remaining", -1)
		)
	):
		return false
	var combo_count := int(combo_snapshot.get("combo_count", 0))
	var aura_source_generation := int(value["aura_source_generation"])
	if (combo_count >= HIGH_COMBO_THRESHOLD) != (aura_source_generation > 0):
		return false
	for ledger_key: Variant in (value["action_ledgers"] as Dictionary).keys():
		if not str(ledger_key).is_valid_int():
			return false
		var ledger_token := int(str(ledger_key))
		if ledger_token <= 0 or ledger_token <= _retired_action_token_floor:
			return false
	for dictionary_name: String in ["stop_extensions_by_generation", "accelerate_hits_by_generation"]:
		for key: Variant in (value[dictionary_name] as Dictionary).keys():
			if not str(key).is_valid_int() or int(str(key)) <= 0:
				return false
			var amount_value: Variant = (value[dictionary_name] as Dictionary)[key]
			if typeof(amount_value) != TYPE_INT or int(amount_value) < 0:
				return false
	var active_token := int(value["active_token"])
	var adapter_snapshot := value["adapter"] as Dictionary
	var adapter_action := adapter_snapshot.get("profile_action", {}) as Dictionary
	var adapter_released := bool(adapter_snapshot.get("profile_action_released", false))
	if bool(value["adapter_active"]) != (not adapter_action.is_empty()):
		return false
	if active_token == 0:
		return (
			str(value.get("active_phase", "")) == "READY"
			and not bool(value["adapter_active"])
			and (value["action_ledgers"] as Dictionary).is_empty()
			and (value["active_plan"] as Dictionary).is_empty()
			and (value["modifier_snapshot"] as Dictionary).is_empty()
			and (value["committed_definition"] as Dictionary).is_empty()
			and (value["live_hold_context"] as Dictionary).is_empty()
			and adapter_action.is_empty()
		)
	if str(value.get("active_phase", "")) == "HOLD":
		return (
			not bool(value["adapter_active"])
			and active_token > _effective_action_token_floor()
			and (value["action_ledgers"] as Dictionary).is_empty()
			and _is_hold_skeleton(value["active_plan"])
			and (value["committed_definition"] as Dictionary).is_empty()
			and adapter_action.is_empty()
		)
	var active_phase := str(value.get("active_phase", ""))
	if active_phase in ["WINDUP", "ACTIVE", "RECOVERY"]:
		var expected_definition := _action_definition(value["active_plan"], active_token)
		var expected_ledger := _action_ledger(value["active_plan"], active_token)
		var ledger_value: Variant = (value["action_ledgers"] as Dictionary).get(str(active_token))
		return (
			bool(value["adapter_active"])
			and active_token > int(value["action_token_floor"])
			and active_token > _retired_action_token_floor
			and (value["action_ledgers"] as Dictionary).size() == 1
			and ledger_value is Dictionary
			and _valid_restored_action_ledger(ledger_value as Dictionary, expected_ledger)
			and not (value["committed_definition"] as Dictionary).is_empty()
			and int((value["committed_definition"] as Dictionary).get("token", 0)) == active_token
			and bool(WeaponActionContractScript.validate_plan(value["active_plan"], WEAPON_ID).get("ok", false))
			and not expected_definition.is_empty()
			and expected_definition == value["committed_definition"]
			and adapter_action == value["committed_definition"]
			and adapter_released == (active_phase in ["ACTIVE", "RECOVERY"])
		)
	return false


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _valid_restored_action_ledger(value: Dictionary, expected: Dictionary) -> bool:
	if value == expected:
		return true
	if value.size() != expected.size() + 2:
		return false
	for key: Variant in expected.keys():
		if not value.has(key) or value[key] != expected[key]:
			return false
	return (
		typeof(value.get("last_outcome_id")) in [TYPE_STRING, TYPE_STRING_NAME]
		and not str(value.get("last_outcome_id", "")).is_empty()
		and typeof(value.get("last_target_id")) == TYPE_INT
		and int(value.get("last_target_id", 0)) > 0
	)


func _matches_frozen_profile(profile: Dictionary, indexes: Dictionary) -> bool:
	if (
		str(profile.get("id", "")) != PROFILE_ID
		or str(profile.get("weapon_id", "")) != str(WEAPON_ID)
		or str(profile.get("runtime_kind", "")) != str(WEAPON_ID)
		or int(profile.get("profile_version", 0)) != PROFILE_VERSION
		or not _same_string_set(profile.get("capabilities", []), FROZEN_CAPABILITIES)
		or _profile_fingerprint(profile) != PROFILE_FINGERPRINT
	):
		return false
	var expected_actions := {
		"punch_1": [3, 3, 5, 0.8, 1], "punch_2": [2, 3, 5, 0.9, 1],
		"punch_3": [3, 4, 6, 1.2, 1], "punch_4": [3, 4, 6, 1.3, 1],
		"punch_5": [5, 6, 14, 3.0, 1], "charged_heavy": [6, 5, 16, 4.0, 3],
		"dodge_counter": [2, 5, 8, 2.5, 5],
		"space_time_shatter": [5, 8, 12, 3.5, 0],
		"primordial_collapse_punch": [20, 10, 30, 12.0, 0],
	}
	var actions := indexes.get("actions", {}) as Dictionary
	var payloads := indexes.get("payloads", {}) as Dictionary
	var cues := indexes.get("cues", {}) as Dictionary
	if actions.size() != expected_actions.size() or payloads.size() != expected_actions.size() or cues.size() != expected_actions.size():
		return false
	for action_id: String in expected_actions:
		var action := actions.get(action_id, {}) as Dictionary
		var expected := expected_actions[action_id] as Array
		if (
			int(action.get("windup_frames", -1)) != int(expected[0])
			or int(action.get("active_frames", -1)) != int(expected[1])
			or int(action.get("recovery_frames", -1)) != int(expected[2])
		):
			return false
		var payload := payloads.get(str(action.get("payload_id", "")), {}) as Dictionary
		var parameters := payload.get("parameters", {}) as Dictionary
		if (
			not is_equal_approx(float(parameters.get("damage_multiplier", -1.0)), float(expected[3]))
			or int(parameters.get("combo_gain", -1)) != int(expected[4])
		):
			return false
	if not _frozen_equal(profile.get("resources", []), [
		{"resource_id": "chain_step", "minimum": 0.0, "maximum": 4.0, "initial": 0.0, "regen_per_second": 0.0},
		{"resource_id": "combo", "minimum": 0.0, "maximum": 999.0, "initial": 0.0, "regen_per_second": 0.0},
	]):
		return false
	return _frozen_equal(profile.get("time_interactions", {}), {
		"stop": {"interaction_id": "gauntlets_stop_extension", "type": "duration_extension", "parameters": {"per_hit_frames": 5, "maximum_bonus_frames": 30}},
		"rewind": {"interaction_id": "gauntlets_rewind_counter", "type": "next_action_modifier", "parameters": {"window_frames": 120, "damage_multiplier": 2.0}},
		"accelerate": {"interaction_id": "gauntlets_third_hit_echo", "type": "echo_payload", "parameters": {"hit_interval": 3, "damage_multiplier": 0.5}},
		"rift": {"interaction_id": "gauntlets_rift_control", "type": "time_context_modifier", "parameters": {"effect_multiplier": 1.5, "cost_multiplier": 0.7}},
	})


func _profile_fingerprint(profile: Dictionary) -> String:
	var hashing_context := HashingContext.new()
	if hashing_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing_context.update(_stable_serialize(profile).to_utf8_buffer()) != OK:
		return ""
	return hashing_context.finish().hex_encode()


func _stable_serialize(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "n;"
		TYPE_BOOL:
			return "b1;" if bool(value) else "b0;"
		TYPE_INT:
			return "i:%d;" % int(value)
		TYPE_FLOAT:
			return "f:%s;" % String.num(float(value), 12)
		TYPE_STRING, TYPE_STRING_NAME:
			var text := str(value)
			return "s:%d:%s;" % [text.length(), text]
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var array_result := "a["
			for child: Variant in value:
				array_result += _stable_serialize(child)
			return array_result + "]"
		TYPE_DICTIONARY:
			var keys: Array[String] = []
			for key: Variant in (value as Dictionary).keys():
				keys.append(str(key))
			keys.sort()
			var dictionary_result := "d{"
			for key: String in keys:
				dictionary_result += _stable_serialize(key)
				dictionary_result += _stable_serialize((value as Dictionary)[key])
			return dictionary_result + "}"
	return "u:%d;" % typeof(value)


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


func _payload_parameters(plan: Dictionary) -> Dictionary:
	var payloads: Variant = plan.get("payloads", [])
	if not payloads is Array or (payloads as Array).is_empty() or not (payloads as Array)[0] is Dictionary:
		return {}
	return (((payloads as Array)[0] as Dictionary).get("parameters", {}) as Dictionary).duplicate(true)


func _scaled_frames(frames: int, scale: float) -> int:
	return maxi(1, ceili(float(frames) * scale))


func _cue_event(plan: Dictionary, token: int) -> Dictionary:
	return {
		"type": "cue_requested", "weapon_id": str(WEAPON_ID),
		"action_id": _resolved_action_id(plan),
		"cue": (plan.get("cue", {}) as Dictionary).duplicate(true), "token": token,
	}


func _is_hold_skeleton(plan: Dictionary) -> bool:
	var phases: Variant = plan.get("phases", [])
	return (
		phases is Array and not (phases as Array).is_empty()
		and (phases as Array)[0] is Dictionary
		and StringName(str(((phases as Array)[0] as Dictionary).get("phase", ""))) == &"HOLD"
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


func _copy_indexed(index: Dictionary, identity: StringName) -> Dictionary:
	var value: Variant = index.get(str(identity))
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _is_configured() -> bool:
	return _adapter_bound and _configuration_ready()


func _configuration_ready() -> bool:
	return (
		_owner != null and is_instance_valid(_owner)
		and _adapter != null and is_instance_valid(_adapter)
		and _modifier_state != null and not _profile_snapshot.is_empty()
	)


func _clear_configuration() -> void:
	_adapter_bound = false
	_owner = null
	_adapter = null
	_modifier_state = null
	_profile_snapshot.clear()
	_actions_by_id.clear()
	_payloads_by_id.clear()
	_cues_by_id.clear()
	_capabilities = PackedStringArray()
	_reset_runtime_domain_state(&"configuration_failed")


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


func _frozen_equal(actual: Variant, expected: Variant) -> bool:
	if actual is Dictionary and expected is Dictionary:
		if (actual as Dictionary).size() != (expected as Dictionary).size():
			return false
		for key: Variant in expected as Dictionary:
			if not (actual as Dictionary).has(key) or not _frozen_equal((actual as Dictionary)[key], (expected as Dictionary)[key]):
				return false
		return true
	if actual is Array and expected is Array:
		if (actual as Array).size() != (expected as Array).size():
			return false
		for index: int in range((expected as Array).size()):
			if not _frozen_equal((actual as Array)[index], (expected as Array)[index]):
				return false
		return true
	if typeof(actual) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		return float(actual) == float(expected)
	return typeof(actual) == typeof(expected) and actual == expected


func _valid_generation_array(value: Variant) -> bool:
	if not value is Array:
		return false
	var previous := 0
	for child: Variant in value as Array:
		if typeof(child) != TYPE_INT or int(child) <= previous:
			return false
		previous = int(child)
	return true


func _int_array(value: Variant) -> Array[int]:
	var result: Array[int] = []
	if value is Array:
		for child: Variant in value as Array:
			result.append(int(child))
	return result


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
	return {"ok": false, "code": code, "context": context.duplicate(true)}
