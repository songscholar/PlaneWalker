class_name StaffWeaponRuntime
extends "res://scripts/combat/weapons/weapon_runtime.gd"

const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")

const SNAPSHOT_SCHEMA_VERSION := 2
const PROFILE_ID := "staff_launch_v1"
const PROFILE_VERSION := 1
const PROFILE_FINGERPRINT := "9126a54f29a730d47b736bff1aafcf2198abb1ff6ef1d736f0c80cdbf4692b6c"
const WEAPON_ID := &"staff"
const PRIMARY_HOLD_ACTION_ID := &"staff_primary_charge"
const ARCANE_ACTION_ID := &"arcane_bolt"
const CHARGED_ACTION_ID := &"charged_element"
const UTILITY_ACTION_ID := &"element_cycle"
const SKILL_ACTION_ID := &"planar_collapse"
const ULTIMATE_ACTION_ID := &"primordial_wrath"
const MANA_RESOURCE_ID := &"mana"
const MANA_MINIMUM := 0.0
const MANA_MAXIMUM := 100.0
const MANA_INITIAL := 100.0
const MANA_REGEN_PER_SECOND := 3.0
const FRAMES_PER_SECOND := 60.0
const PRIMARY_CHARGE_FRAMES := 30
const ACCELERATED_CHARGE_FRAMES := 15
const PRIMARY_MAXIMUM_HOLD_FRAMES := 600
const ULTIMATE_HOLD_FRAMES := 60
const COMBO_WINDOW_FRAMES := 300
const MANA_RETURN_RATIO := 0.02
const MANA_RETURN_CAP_PER_OUTCOME := 5.0
const MAX_TRACKED_CAST_LEDGERS := 256
const MAX_CLAIMED_REWIND_GENERATIONS := 256
const ADAPTER_ONLY_REPLAY_DESCRIPTOR_IDS: Array[String] = [
	"staff_arcane_bolt",
	"staff_planar_collapse",
	"staff_primordial_wrath",
]
const RUNTIME_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version", "configured", "profile_id", "profile_version", "mana", "current_element",
	"combo_element", "combo_remaining_frames", "combo_source_context", "pending_combo",
	"pending_combos", "last_runtime_frame", "claimed_rewind_generations",
	"claimed_rewind_generation_floor", "cast_ledgers", "mana_return_by_outcome", "active_token",
	"active_phase", "active_plan", "modifier_snapshot", "committed_definition", "live_hold_context",
	"adapter_active", "adapter_snapshot",
]
const ELEMENT_SEQUENCE: Array[String] = ["fire", "ice", "lightning"]
const FROZEN_CAPABILITIES: Array[String] = [
	"weapon.attack_speed",
	"weapon.charge_rate",
	"weapon.damage",
	"weapon.mana_max",
	"weapon.status_duration",
]
const RELEASE_ACTION_FINGERPRINTS := {
	"arcane_bolt": "staff_primary:arcane_bolt:v1",
	"charged_element": "staff_primary:charged_element:v1",
	"primordial_wrath": "staff_ultimate:primordial_wrath:v1",
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

var _owner: Node
var _adapter: Node
var _modifier_state: RefCounted
var _profile_snapshot: Dictionary = {}
var _actions_by_id: Dictionary = {}
var _payloads_by_id: Dictionary = {}
var _cues_by_id: Dictionary = {}
var _combinations_by_pair: Dictionary = {}
var _element_definitions: Dictionary = {}
var _capabilities: PackedStringArray = PackedStringArray()

var _mana: float = MANA_INITIAL
var _current_element: StringName = &"fire"
var _combo_element: StringName = &""
var _combo_remaining_frames: int = 0
var _combo_source_context: Dictionary = {}
var _pending_combos: Dictionary = {}
var _last_runtime_frame: int = -1
var _claimed_rewind_generations: Array[int] = []
var _claimed_rewind_generation_floor: int = 0
var _cast_ledgers: Dictionary = {}
var _mana_return_by_outcome: Dictionary = {}

var _active_token: int = 0
var _active_phase: StringName = &"READY"
var _active_plan: Dictionary = {}
var _modifier_snapshot: Dictionary = {}
var _committed_definition: Dictionary = {}
var _live_hold_context: Dictionary = {}


func weapon_id() -> StringName:
	return WEAPON_ID


func configure(owner: Node, profile: Variant, modifiers: Variant) -> bool:
	if owner == null or not is_instance_valid(owner):
		return false
	if not profile is RefCounted or not (profile as RefCounted).has_method("snapshot"):
		return false
	if not modifiers is RefCounted or not _has_methods(modifiers as RefCounted, REQUIRED_MODIFIER_METHODS):
		return false
	var adapter := owner.get_node_or_null("StaffWeapon")
	if adapter == null or not _has_methods(adapter, REQUIRED_ADAPTER_METHODS):
		return false
	if not _adapter_numbers_are_valid(adapter):
		return false

	var profile_value: Variant = (profile as RefCounted).call("snapshot")
	if not profile_value is Dictionary:
		return false
	var next_profile := (profile_value as Dictionary).duplicate(true)
	var indexes := _build_profile_indexes(next_profile)
	if not bool(indexes.get("ok", false)) or not _matches_frozen_profile(next_profile):
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
	_combinations_by_pair = (indexes["combinations"] as Dictionary).duplicate(true)
	_element_definitions = (indexes["elements"] as Dictionary).duplicate(true)
	_capabilities = PackedStringArray(next_profile["capabilities"])
	reset_runtime_state(&"configured")
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
				return _build_primary_hold_plan(context)
			if edge == &"released":
				return _build_primary_release_plan(int(intent.get("held_frames", 0)), context)
		&"weapon_utility":
			if edge == &"pressed":
				return _build_action_plan(UTILITY_ACTION_ID, context)
		&"weapon_skill":
			if edge == &"pressed":
				return _build_action_plan(SKILL_ACTION_ID, context)
		&"weapon_ultimate":
			if edge == &"pressed":
				return _build_ultimate_hold_plan(context)
			if edge == &"released":
				if int(intent.get("held_frames", 0)) < ULTIMATE_HOLD_FRAMES:
					return _failure(&"UNDERCHARGED", {
						"held_frames": int(intent.get("held_frames", 0)),
						"minimum_frames": ULTIMATE_HOLD_FRAMES,
					})
				return _build_action_plan(ULTIMATE_ACTION_ID, context)
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
		built = _build_primary_release_plan(held_frames, context)
	elif StringName(str(plan.get("action_id", ""))) == ULTIMATE_ACTION_ID:
		if held_frames < ULTIMATE_HOLD_FRAMES:
			return _failure(&"UNDERCHARGED", {
				"held_frames": held_frames,
				"minimum_frames": ULTIMATE_HOLD_FRAMES,
			})
		built = _build_action_plan(ULTIMATE_ACTION_ID, context)
	else:
		return _failure(&"STALE_HOLD_RELEASE")
	if not bool(built.get("ok", false)):
		return built
	var finalized_plan := (built["plan"] as Dictionary).duplicate(true)
	var action_id := str(finalized_plan.get("action_id", ""))
	var fingerprint := str((plan.get("release_action_fingerprints", {}) as Dictionary).get(action_id, ""))
	if fingerprint.is_empty():
		return _failure(&"RELEASE_ACTION_FINGERPRINT_MISSING", {"action_id": action_id})
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
		"context": {"action_id": action_id},
	}


func update_hold_context(plan: Dictionary, token: int, context: Dictionary) -> bool:
	if not _matches_active_action(plan, token) or _active_phase != &"HOLD":
		return false
	var normalized := _normalized_context(context)
	if not bool(normalized.get("ok", false)):
		return false
	_live_hold_context = (normalized["context"] as Dictionary).duplicate(true)
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
			return [
				{
					"type": "payload_released",
					"weapon_id": str(WEAPON_ID),
					"action_id": _resolved_action_id(plan),
					"token": token,
					"payload_descriptors": (_committed_definition.get("payload_descriptors", []) as Array).duplicate(true),
					"time_interactions": (_committed_definition.get("time_interactions", []) as Array).duplicate(true),
					"boss_conversion": (_committed_definition.get("boss_conversion", {}) as Dictionary).duplicate(true),
				},
				_cue_event(plan, token),
			]
		&"RECOVERY":
			if _active_phase in [&"WINDUP", &"ACTIVE"]:
				_active_phase = &"RECOVERY"
	return []


func on_action_frame(_plan: Dictionary, _phase: StringName, _token: int, _phase_frame: int) -> Array[Dictionary]:
	return []


func handle_payload_result(token: int, generation: int, result: Dictionary) -> Dictionary:
	var outcome_value: Variant = result.get("outcome_id")
	var element_value: Variant = result.get("element")
	var target_value: Variant = result.get("target_id")
	var terminal_value: Variant = result.get("terminal")
	var damage_value: Variant = result.get("damage", 0.0)
	var hit_value: Variant = result.get("hit", true)
	if typeof(outcome_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _failure(&"INVALID_OUTCOME")
	if typeof(element_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _failure(&"INVALID_ELEMENT")
	if typeof(target_value) != TYPE_INT:
		return _failure(&"INVALID_TARGET")
	if typeof(terminal_value) != TYPE_BOOL or typeof(hit_value) != TYPE_BOOL:
		return _failure(&"INVALID_PAYLOAD_RESULT")
	if typeof(damage_value) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure(&"INVALID_DAMAGE")
	var payload_context := _payload_combo_source_context(result)
	if not bool(payload_context.get("ok", false)):
		return payload_context
	var normalized_payload_context := (payload_context.get("context", {}) as Dictionary).duplicate(true)
	if bool(result.get("resource_only", false)):
		normalized_payload_context["resource_only"] = true
	return _payload_result_with_context(
		token,
		generation,
		StringName(str(outcome_value)),
		StringName(str(element_value)),
		int(target_value),
		bool(terminal_value),
		float(damage_value),
		bool(hit_value),
		normalized_payload_context,
		result
	)


func payload_result(
	token: int,
	generation: int,
	outcome_id: StringName,
	element: StringName,
	target_id: int,
	terminal: bool,
	damage: float = 0.0,
	hit: bool = true
) -> Dictionary:
	return _payload_result_with_context(
		token,
		generation,
		outcome_id,
		element,
		target_id,
		terminal,
		damage,
		hit,
		{}
	)


func project_replay_payload_result(
	runtime_snapshot: Dictionary,
	token: int,
	generation: int,
	result: Dictionary
) -> Dictionary:
	if not _is_configured() or not _valid_restore_snapshot(runtime_snapshot):
		return _failure(&"INVALID_RUNTIME_SNAPSHOT")
	var outcome_value: Variant = result.get("outcome_id")
	var element_value: Variant = result.get("element")
	var target_value: Variant = result.get("target_id")
	var terminal_value: Variant = result.get("terminal")
	var damage_value: Variant = result.get("damage", 0.0)
	var hit_value: Variant = result.get("hit", true)
	if typeof(outcome_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _failure(&"INVALID_OUTCOME")
	if typeof(element_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return _failure(&"INVALID_ELEMENT")
	if typeof(target_value) != TYPE_INT:
		return _failure(&"INVALID_TARGET")
	if typeof(terminal_value) != TYPE_BOOL or typeof(hit_value) != TYPE_BOOL:
		return _failure(&"INVALID_PAYLOAD_RESULT")
	if typeof(damage_value) not in [TYPE_INT, TYPE_FLOAT]:
		return _failure(&"INVALID_DAMAGE")
	var payload_context := _payload_combo_source_context(result)
	if not bool(payload_context.get("ok", false)):
		return payload_context
	var normalized_context := (payload_context.get("context", {}) as Dictionary).duplicate(true)
	if bool(result.get("resource_only", false)):
		normalized_context["resource_only"] = true
	return _project_payload_result_transition(
		runtime_snapshot,
		token,
		generation,
		StringName(str(outcome_value)),
		StringName(str(element_value)),
		int(target_value),
		bool(terminal_value),
		float(damage_value),
		bool(hit_value),
		normalized_context,
		result,
		true
	)


func _payload_result_with_context(
	token: int,
	generation: int,
	outcome_id: StringName,
	element: StringName,
	target_id: int,
	terminal: bool,
	damage: float,
	hit: bool,
	payload_context: Dictionary,
	normalized_source: Dictionary = {}
) -> Dictionary:
	var normalized_result := normalized_source.duplicate(true)
	if payload_context.has("origin_target_ids"):
		normalized_result["chain_target_ids"] = (payload_context.get("origin_target_ids", []) as Array).duplicate()
	if payload_context.has("origin_positions"):
		normalized_result["chain_origin_positions"] = (payload_context.get("origin_positions", []) as Array).duplicate()
	if bool(payload_context.get("resource_only", false)):
		normalized_result["resource_only"] = true
	normalized_result["outcome_id"] = str(outcome_id)
	normalized_result["element"] = str(element)
	normalized_result["target_id"] = target_id
	normalized_result["terminal"] = terminal
	normalized_result["damage"] = damage
	normalized_result["hit"] = hit
	var projection := _project_payload_result_transition(
		snapshot(),
		token,
		generation,
		outcome_id,
		element,
		target_id,
		terminal,
		damage,
		hit,
		payload_context,
		normalized_result,
		false
	)
	if not bool(projection.get("ok", false)):
		return projection
	_apply_snapshot_fields(projection.get("snapshot", {}) as Dictionary)
	return (projection.get("payload_result", {}) as Dictionary).duplicate(true)


func _project_payload_result_transition(
	runtime_snapshot: Dictionary,
	token: int,
	generation: int,
	outcome_id: StringName,
	element: StringName,
	target_id: int,
	terminal: bool,
	damage: float,
	hit: bool,
	payload_context: Dictionary,
	normalized_result: Dictionary,
	require_verified_snapshot: bool
) -> Dictionary:
	if token <= 0 or generation <= 0 or outcome_id == &"":
		return _failure(&"INVALID_PAYLOAD_RESULT")
	if not is_finite(damage) or damage < 0.0:
		return _failure(&"INVALID_DAMAGE")
	if hit and target_id < 0:
		return _failure(&"INVALID_TARGET")
	var resource_only := bool(payload_context.get("resource_only", false))
	if not hit and not terminal and not resource_only:
		return _failure(&"NON_TERMINAL_MISS")
	var projected := runtime_snapshot.duplicate(true)
	var cast_ledgers := (projected.get("cast_ledgers", {}) as Dictionary).duplicate(true)
	var token_key := str(token)
	if not cast_ledgers.has(token_key):
		if not _is_adapter_only_replay_payload_result(normalized_result):
			return _failure(&"STALE_TOKEN")
		return _replay_projection_success(projected, {}, 0.0, 0.0, terminal)
	var cast := (cast_ledgers[token_key] as Dictionary).duplicate(true)
	var expected_element := StringName(str(cast.get("element", "")))
	if not resource_only and (expected_element == &"" or element != expected_element):
		return _failure(&"ELEMENT_MISMATCH")
	var cast_generation := int(cast.get("generation", 0))
	if cast_generation > 0 and cast_generation != generation:
		return _failure(&"STALE_GENERATION")
	if cast_generation == 0:
		cast["generation"] = generation

	var outcomes := (cast.get("outcomes", {}) as Dictionary).duplicate(true)
	var outcome_key := "%d:%d:%s" % [token, generation, str(outcome_id)]
	var outcome := (outcomes.get(outcome_key, {
		"terminal": false,
		"targets": {},
		"mana_return": 0.0,
	}) as Dictionary).duplicate(true)
	if bool(outcome.get("terminal", false)):
		return _failure(&"OUTCOME_TERMINAL")

	var targets := (cast.get("targets", {}) as Dictionary).duplicate(true)
	var outcome_targets := (outcome.get("targets", {}) as Dictionary).duplicate(true)
	if hit and outcome_targets.has(str(target_id)):
		return _failure(&"DUPLICATE_TARGET")
	if hit:
		targets[str(target_id)] = true
		outcome_targets[str(target_id)] = true
		outcome["targets"] = outcome_targets

	var pending_combos := (projected.get("pending_combos", {}) as Dictionary).duplicate(true)
	var combo_result: Dictionary = {}
	var refunded_mana := 0.0
	if hit and not resource_only and not bool(cast.get("confirmed_hit", false)):
		cast["confirmed_hit"] = true
		var combo := (cast.get("combo", {}) as Dictionary).duplicate(true)
		var pending_combo_value: Variant = pending_combos.get(token_key, {})
		var pending_combo := (
			(pending_combo_value as Dictionary).duplicate(true)
			if pending_combo_value is Dictionary
			else {}
		)
		var pending_combo_is_live := not pending_combo.is_empty() and int(pending_combo.get("remaining_frames", 0)) > 0
		if not combo.is_empty() and pending_combo_is_live:
			combo_result = _materialized_combo_result(
				combo,
				cast.get("combo_source_context", {}) as Dictionary
			)
			pending_combos.erase(token_key)
			cast["combo"] = {}
			cast["combo_window_remaining_frames"] = 0
			cast["combo_source_context"] = {}
			projected["combo_element"] = ""
			projected["combo_remaining_frames"] = 0
			projected["combo_source_context"] = {}
		else:
			cast["combo"] = {}
			cast["combo_window_remaining_frames"] = 0
			cast["combo_source_context"] = {}
			if str(projected.get("combo_element", "")).is_empty() or int(projected.get("combo_remaining_frames", 0)) <= 0:
				projected["combo_element"] = str(element)
				projected["combo_remaining_frames"] = COMBO_WINDOW_FRAMES
				projected["combo_source_context"] = payload_context.duplicate(true)
	elif not resource_only and not hit and terminal:
		var pending_value: Variant = pending_combos.get(token_key, {})
		if pending_value is Dictionary and not (pending_value as Dictionary).is_empty():
			var pending := (pending_value as Dictionary).duplicate(true)
			if not bool(pending.get("refunded", false)):
				refunded_mana = float(pending.get("extra_mana", 0.0))
				projected["mana"] = minf(
					_mana_maximum(),
					float(projected.get("mana", 0.0)) + refunded_mana
				)
		pending_combos.erase(token_key)
		cast["combo"] = {}
		cast["combo_window_remaining_frames"] = 0
		cast["combo_source_context"] = {}

	var mana_return := 0.0
	if hit and damage > 0.0:
		var prior_return := float(outcome.get("mana_return", 0.0))
		var available_for_outcome := maxf(0.0, MANA_RETURN_CAP_PER_OUTCOME - prior_return)
		var available_for_mana := maxf(0.0, _mana_maximum() - float(projected.get("mana", 0.0)))
		mana_return = minf(damage * MANA_RETURN_RATIO, minf(available_for_outcome, available_for_mana))
		if mana_return > 0.0:
			projected["mana"] = float(projected.get("mana", 0.0)) + mana_return
			outcome["mana_return"] = prior_return + mana_return
			var mana_returns := (projected.get("mana_return_by_outcome", {}) as Dictionary).duplicate(true)
			mana_returns[outcome_key] = float(outcome["mana_return"])
			projected["mana_return_by_outcome"] = mana_returns
	if terminal:
		outcome["terminal"] = true
	outcomes[outcome_key] = outcome
	cast["targets"] = targets
	cast["outcomes"] = outcomes
	cast_ledgers[token_key] = cast
	projected["cast_ledgers"] = cast_ledgers
	projected["pending_combos"] = pending_combos
	projected["pending_combo"] = _first_pending_combo_from(pending_combos)
	if require_verified_snapshot and not _valid_restore_snapshot(projected):
		return _failure(&"INVALID_PROJECTED_RUNTIME_SNAPSHOT")
	return _replay_projection_success(
		projected,
		combo_result,
		mana_return,
		refunded_mana,
		terminal
	)


func _replay_projection_success(
	projected: Dictionary,
	combo_result: Dictionary,
	mana_return: float,
	refunded_mana: float,
	terminal: bool
) -> Dictionary:
	return {
		"ok": true,
		"code": &"OK",
		"snapshot": projected.duplicate(true),
		"payload_result": {
			"ok": true,
			"code": &"OK",
			"combo": combo_result.duplicate(true),
			"mana_return": mana_return,
			"refunded_mana": refunded_mana,
			"terminal": terminal,
			"context": {},
		},
		"context": {},
	}


func _is_adapter_only_replay_payload_result(result: Dictionary) -> bool:
	return ADAPTER_ONLY_REPLAY_DESCRIPTOR_IDS.has(str(result.get("descriptor_id", "")))


func _first_pending_combo_from(pending_combos: Dictionary) -> Dictionary:
	if pending_combos.is_empty():
		return {}
	var tokens: Array[int] = []
	for token_value: Variant in pending_combos.keys():
		var token := int(str(token_value))
		if token > 0:
			tokens.append(token)
	tokens.sort()
	if tokens.is_empty():
		return {}
	var value: Variant = pending_combos.get(str(tokens[0]), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func advance_runtime_frame(coordinator_frame: int) -> Array[Dictionary]:
	if coordinator_frame < 0 or coordinator_frame <= _last_runtime_frame:
		return []
	if _last_runtime_frame < 0:
		_last_runtime_frame = coordinator_frame
		return []
	var elapsed := coordinator_frame - _last_runtime_frame
	_last_runtime_frame = coordinator_frame
	_mana = minf(_mana_maximum(), _mana + MANA_REGEN_PER_SECOND * float(elapsed) / FRAMES_PER_SECOND)
	if _combo_remaining_frames > 0:
		_combo_remaining_frames = maxi(0, _combo_remaining_frames - elapsed)
		if _combo_remaining_frames == 0:
			_combo_element = &""
			_combo_source_context.clear()
	var expired_tokens: Array[int] = []
	for token_key_value: Variant in _pending_combos.keys():
		var token_key := str(token_key_value)
		var pending := (_pending_combos.get(token_key, {}) as Dictionary).duplicate(true)
		pending["remaining_frames"] = maxi(0, int(pending.get("remaining_frames", 0)) - elapsed)
		_pending_combos[token_key] = pending
		if int(pending.get("remaining_frames", 0)) == 0:
			expired_tokens.append(int(token_key))
	for token: int in expired_tokens:
		_refund_pending_combo(token)
	return []


func cancel_action(token: int, _reason: StringName) -> void:
	if token <= 0 or token != _active_token:
		return
	_refund_pending_combo(token)
	_erase_cast_ledger(token)
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
	var adapter_snapshot := runtime_snapshot["adapter_snapshot"] as Dictionary
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
	_apply_snapshot_fields(before)
	return false


func gameplay_rewind_committed_payload_guard() -> Dictionary:
	var adapter_value: Variant = _adapter.call("gameplay_rewind_committed_payload_guard")
	return {
		"adapter": (adapter_value as Dictionary).duplicate(true) if adapter_value is Dictionary else {},
		"mana": _mana,
		"current_element": str(_current_element),
		"combo_element": str(_combo_element),
		"combo_remaining_frames": _combo_remaining_frames,
		"combo_source_context": _combo_source_context.duplicate(true),
		"pending_combos": _pending_combos.duplicate(true),
		"last_runtime_frame": _last_runtime_frame,
		"claimed_rewind_generations": _claimed_rewind_generations.duplicate(),
		"claimed_rewind_generation_floor": _claimed_rewind_generation_floor,
		"cast_ledgers": _cast_ledgers.duplicate(true),
		"mana_return_by_outcome": _mana_return_by_outcome.duplicate(true),
	}


func finish_action(token: int) -> void:
	if token <= 0 or token != _active_token:
		return
	_adapter.call("finish_profile_action")
	_clear_active_action()


func apply_modifier(effect_id: StringName, value: Variant) -> bool:
	if _modifier_state == null or not _capabilities.has(str(effect_id)):
		return false
	var applied := bool(_modifier_state.call("apply", effect_id, value))
	if applied and effect_id == &"weapon.mana_max":
		_mana = minf(_mana, _mana_maximum())
	return applied


func reset_runtime_state(_reason: StringName) -> void:
	if _adapter != null:
		_adapter.call("cancel_profile_action")
		_adapter.call("reset_runtime_state")
	_mana = MANA_INITIAL
	_current_element = &"fire"
	_combo_element = &""
	_combo_remaining_frames = 0
	_combo_source_context.clear()
	_pending_combos.clear()
	_last_runtime_frame = -1
	_claimed_rewind_generations.clear()
	_claimed_rewind_generation_floor = 0
	_cast_ledgers.clear()
	_mana_return_by_outcome.clear()
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
		"mana": _mana,
		"current_element": str(_current_element),
		"combo_element": str(_combo_element),
		"combo_remaining_frames": _combo_remaining_frames,
		"combo_source_context": _combo_source_context.duplicate(true),
		"pending_combo": _first_pending_combo(),
		"pending_combos": _pending_combos.duplicate(true),
		"last_runtime_frame": _last_runtime_frame,
		"claimed_rewind_generations": _claimed_rewind_generations.duplicate(),
		"claimed_rewind_generation_floor": _claimed_rewind_generation_floor,
		"cast_ledgers": _cast_ledgers.duplicate(true),
		"mana_return_by_outcome": _mana_return_by_outcome.duplicate(true),
		"active_token": _active_token,
		"active_phase": str(_active_phase),
		"active_plan": _active_plan.duplicate(true),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
		"committed_definition": _committed_definition.duplicate(true),
		"live_hold_context": _live_hold_context.duplicate(true),
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
	_mana = float(runtime_snapshot["mana"])
	_current_element = StringName(str(runtime_snapshot["current_element"]))
	_combo_element = StringName(str(runtime_snapshot["combo_element"]))
	_combo_remaining_frames = int(runtime_snapshot["combo_remaining_frames"])
	_combo_source_context = (runtime_snapshot["combo_source_context"] as Dictionary).duplicate(true)
	_pending_combos = (runtime_snapshot["pending_combos"] as Dictionary).duplicate(true)
	_last_runtime_frame = int(runtime_snapshot["last_runtime_frame"])
	_claimed_rewind_generations = _int_array(runtime_snapshot["claimed_rewind_generations"])
	_claimed_rewind_generation_floor = int(runtime_snapshot["claimed_rewind_generation_floor"])
	_cast_ledgers = (runtime_snapshot["cast_ledgers"] as Dictionary).duplicate(true)
	_mana_return_by_outcome = (runtime_snapshot["mana_return_by_outcome"] as Dictionary).duplicate(true)
	_active_token = int(runtime_snapshot["active_token"])
	_active_phase = StringName(str(runtime_snapshot["active_phase"]))
	_active_plan = (runtime_snapshot["active_plan"] as Dictionary).duplicate(true)
	_modifier_snapshot = (runtime_snapshot["modifier_snapshot"] as Dictionary).duplicate(true)
	_committed_definition = (runtime_snapshot["committed_definition"] as Dictionary).duplicate(true)
	_live_hold_context = (runtime_snapshot["live_hold_context"] as Dictionary).duplicate(true)


func presentation_snapshot() -> Dictionary:
	var facing := Vector2.RIGHT
	if _adapter is Node2D:
		facing = Vector2.RIGHT.rotated((_adapter as Node2D).global_rotation)
	return {
		"weapon_id": str(WEAPON_ID),
		"action_id": _resolved_action_id(_active_plan),
		"phase": str(_active_phase),
		"token": _active_token,
		"mana": _mana,
		"mana_maximum": _mana_maximum(),
		"element": str(_current_element),
		"combo_element": str(_combo_element),
		"combo_remaining_frames": _combo_remaining_frames,
		"pending_combo": _first_pending_combo(),
		"pending_combos": _pending_combos.duplicate(true),
		"facing": facing,
		"cue_id": str((_active_plan.get("cue", {}) as Dictionary).get("cue_id", "")),
		"modifier_snapshot": _modifier_snapshot.duplicate(true),
	}


func _build_primary_hold_plan(context: Dictionary) -> Dictionary:
	var normalized := _normalized_context(context)
	if not bool(normalized.get("ok", false)):
		return normalized
	var modifiers := _frozen_modifiers()
	if not bool(modifiers.get("ok", false)):
		return modifiers
	var frozen_context: Dictionary = normalized["context"]
	var frozen_modifiers: Dictionary = modifiers["modifiers"]
	var charge_frames := _charge_frames(frozen_context["time_interactions"], frozen_modifiers)
	var plan := {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(PRIMARY_HOLD_ACTION_ID),
		"profile_id": PROFILE_ID,
		"profile_version": PROFILE_VERSION,
		"semantic_action": "weapon_primary",
		"activation_mode": "hold",
		"buffer_frames": 8,
		"cooldown_frames": 0,
		"resource_costs": {},
		"run_seed": int(frozen_context["run_seed"]),
		"aim_direction_snapshot": frozen_context["aim_direction"],
		"modifier_snapshot": frozen_modifiers,
		"frozen_context": frozen_context,
		"phases": [{
			"phase": "HOLD",
			"duration_frames": PRIMARY_MAXIMUM_HOLD_FRAMES,
			"minimum_hold_frames": 0,
			"charge_complete_frames": charge_frames,
			"movement_multiplier": 0.45,
			"movement_start_multiplier": 0.75,
		}],
		"payloads": [],
		"cue": {},
		"time_interactions": _time_interaction_descriptors(PRIMARY_HOLD_ACTION_ID, frozen_context["time_interactions"], {}, false),
		"boss_conversion": _boss_conversion(),
		"allowed_release_action_ids": [str(ARCANE_ACTION_ID), str(CHARGED_ACTION_ID)],
		"release_action_fingerprints": {
			str(ARCANE_ACTION_ID): RELEASE_ACTION_FINGERPRINTS[str(ARCANE_ACTION_ID)],
			str(CHARGED_ACTION_ID): RELEASE_ACTION_FINGERPRINTS[str(CHARGED_ACTION_ID)],
		},
	}
	var validation := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	return {"ok": true, "code": &"OK", "plan": plan, "context": {}} if bool(validation.get("ok", false)) else validation


func _build_ultimate_hold_plan(context: Dictionary) -> Dictionary:
	var normalized := _normalized_context(context)
	if not bool(normalized.get("ok", false)):
		return normalized
	var modifiers := _frozen_modifiers()
	if not bool(modifiers.get("ok", false)):
		return modifiers
	var frozen_context: Dictionary = normalized["context"]
	var plan := {
		"weapon_id": str(WEAPON_ID),
		"action_id": str(ULTIMATE_ACTION_ID),
		"profile_id": PROFILE_ID,
		"profile_version": PROFILE_VERSION,
		"semantic_action": "weapon_ultimate",
		"activation_mode": "hold",
		"buffer_frames": 8,
		"cooldown_frames": 0,
		"resource_costs": {"mana": 60.0, "time_energy": 55.0},
		"run_seed": int(frozen_context["run_seed"]),
		"aim_direction_snapshot": frozen_context["aim_direction"],
		"modifier_snapshot": (modifiers["modifiers"] as Dictionary).duplicate(true),
		"frozen_context": frozen_context,
		"phases": [{
			"phase": "HOLD",
			"duration_frames": ULTIMATE_HOLD_FRAMES,
			"minimum_hold_frames": ULTIMATE_HOLD_FRAMES,
			"charge_complete_frames": ULTIMATE_HOLD_FRAMES,
			"movement_multiplier": 0.0,
			"movement_start_multiplier": 0.0,
		}],
		"payloads": [],
		"cue": {},
		"time_interactions": [],
		"boss_conversion": _boss_conversion(),
		"allowed_release_action_ids": [str(ULTIMATE_ACTION_ID)],
		"release_action_fingerprints": {
			str(ULTIMATE_ACTION_ID): RELEASE_ACTION_FINGERPRINTS[str(ULTIMATE_ACTION_ID)],
		},
	}
	var validation := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	return {"ok": true, "code": &"OK", "plan": plan, "context": {}} if bool(validation.get("ok", false)) else validation


func _build_primary_release_plan(held_frames: int, context: Dictionary) -> Dictionary:
	var normalized := _normalized_context(context)
	if not bool(normalized.get("ok", false)):
		return normalized
	var modifiers := _frozen_modifiers()
	if not bool(modifiers.get("ok", false)):
		return modifiers
	var frozen_context: Dictionary = normalized["context"]
	var frozen_modifiers: Dictionary = modifiers["modifiers"]
	var threshold := _charge_frames(frozen_context["time_interactions"], frozen_modifiers)
	if held_frames < threshold:
		return _build_action_plan_from_frozen(ARCANE_ACTION_ID, frozen_context, frozen_modifiers)
	return _build_action_plan_from_frozen(CHARGED_ACTION_ID, frozen_context, frozen_modifiers)


func _build_action_plan(action_id: StringName, context: Dictionary) -> Dictionary:
	var normalized := _normalized_context(context)
	if not bool(normalized.get("ok", false)):
		return normalized
	var modifiers := _frozen_modifiers()
	if not bool(modifiers.get("ok", false)):
		return modifiers
	return _build_action_plan_from_frozen(
		action_id,
		normalized["context"],
		modifiers["modifiers"]
	)


func _build_action_plan_from_frozen(
	action_id: StringName,
	frozen_context: Dictionary,
	frozen_modifiers: Dictionary
) -> Dictionary:
	var action := _copy_indexed(_actions_by_id, action_id)
	if action.is_empty():
		return _failure(&"ACTION_NOT_FOUND", {"action_id": str(action_id)})
	var payload_id := StringName(str(action.get("payload_id", "")))
	var payload := _copy_indexed(_payloads_by_id, payload_id)
	var cue := _copy_indexed(_cues_by_id, StringName(str(action.get("cue_id", ""))))
	if payload.is_empty() or cue.is_empty():
		return _failure(&"PROFILE_REFERENCE_MISSING")
	var time_context := (frozen_context.get("time_interactions", {}) as Dictionary).duplicate(true)
	var rewind_generation := int(time_context.get("rewind_generation", 0))
	var rewind_available := (
		action_id == CHARGED_ACTION_ID
		and bool(time_context.get("rewind_cast_available", false))
		and rewind_generation > 0
		and rewind_generation > _claimed_rewind_generation_floor
		and not _claimed_rewind_generations.has(rewind_generation)
	)
	var accelerate_active := bool(time_context.get("accelerate_active", false))
	var combo: Dictionary = {}
	if action_id == CHARGED_ACTION_ID and _combo_remaining_frames > 0 and _combo_element != &"" and _combo_element != _current_element:
		combo = _copy_indexed(_combinations_by_pair, StringName("%s>%s" % [str(_combo_element), str(_current_element)]))
	var combo_window_remaining_frames := _combo_remaining_frames if not combo.is_empty() else 0

	var mana_cost := float((action.get("resource_costs", {}) as Dictionary).get("mana", 0.0))
	if action_id == CHARGED_ACTION_ID:
		var cast_parameters := payload.get("parameters", {}) as Dictionary
		mana_cost = float((cast_parameters.get("costs", {}) as Dictionary).get(str(_current_element), 0.0))
		if not combo.is_empty():
			mana_cost += float(combo.get("extra_mana", 0.0))
	if rewind_available:
		mana_cost = 0.0
	elif accelerate_active and action_id == CHARGED_ACTION_ID:
		mana_cost *= 0.7
	if mana_cost > _mana + 0.00001:
		return _failure(&"INSUFFICIENT_MANA", {"required": mana_cost, "available": _mana})

	var parameters := (payload.get("parameters", {}) as Dictionary).duplicate(true)
	if action_id == CHARGED_ACTION_ID:
		var element_definition := _copy_indexed(_element_definitions, _current_element)
		if element_definition.is_empty():
			return _failure(&"PROFILE_REFERENCE_MISSING", {"element": str(_current_element)})
		parameters["element"] = str(_current_element)
		parameters["element_definition"] = element_definition
		parameters["combo"] = combo.duplicate(true)
		var damage_multiplier := float(element_definition.get(
			"damage_multiplier",
			parameters.get("damage_multiplier", 1.0)
		))
		if rewind_available:
			damage_multiplier *= 1.3
		parameters["damage_multiplier"] = damage_multiplier
		parameters["resolved_damage_multiplier"] = damage_multiplier * float(frozen_modifiers.get("weapon.damage", 1.0))
	elif parameters.has("damage_multiplier"):
		parameters["resolved_damage_multiplier"] = float(parameters["damage_multiplier"]) * float(frozen_modifiers.get("weapon.damage", 1.0))

	var timing_scale := 1.0 / maxf(0.01, float(frozen_modifiers.get("weapon.attack_speed", 1.0)))
	var windup := _scaled_frames(int(action["windup_frames"]), timing_scale)
	var active := int(action["active_frames"])
	var recovery := _scaled_frames(int(action["recovery_frames"]), timing_scale)
	var recovery_phase := {
		"phase": "RECOVERY",
		"duration_frames": recovery,
		"movement_multiplier": float(action["movement_multiplier"]),
	}
	var cancel_value: Variant = action.get("cancel_from_frame")
	if cancel_value != null:
		var relative_cancel := int(cancel_value) - int(action["windup_frames"]) - int(action["active_frames"])
		recovery_phase["cancel_from_frame"] = clampi(relative_cancel, 0, recovery - 1)
	var resource_costs := (action.get("resource_costs", {}) as Dictionary).duplicate(true)
	if mana_cost > 0.0 or resource_costs.has("mana"):
		resource_costs["mana"] = mana_cost
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
		"mana_cost": mana_cost,
		"element": str(_current_element) if action_id == CHARGED_ACTION_ID else "",
		"combo": combo.duplicate(true),
		"combo_window_remaining_frames": combo_window_remaining_frames,
		"combo_source_context": _combo_source_context.duplicate(true) if not combo.is_empty() else {},
		"combo_extra_mana": _resolved_combo_extra(combo, rewind_available, accelerate_active),
		"run_seed": int(frozen_context["run_seed"]),
		"aim_direction_snapshot": frozen_context["aim_direction"],
		"modifier_snapshot": frozen_modifiers.duplicate(true),
		"frozen_context": frozen_context.duplicate(true),
		"rewind_generation_claim": rewind_generation if rewind_available else 0,
		"phases": [
			{"phase": "WINDUP", "duration_frames": windup, "movement_multiplier": float(action["movement_multiplier"])},
			{"phase": "ACTIVE", "duration_frames": active, "movement_multiplier": float(action["movement_multiplier"])},
			recovery_phase,
		],
		"payloads": [{
			"descriptor_id": str(payload_id),
			"kind": str(payload["kind"]),
			"parameters": parameters,
		}],
		"cue": cue,
		"time_interactions": _time_interaction_descriptors(action_id, time_context, combo, rewind_available),
		"boss_conversion": _boss_conversion(),
		"invulnerable_during_cast": action_id == ULTIMATE_ACTION_ID,
	}
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
	return {
		"token": token,
		"generation": token,
		"profile_id": PROFILE_ID,
		"weapon_id": str(WEAPON_ID),
		"action_id": _resolved_action_id(plan),
		"semantic_action": str(plan.get("semantic_action", "")),
		"aim_direction": plan.get("aim_direction_snapshot", Vector2.RIGHT),
		"base_attack": float(_adapter.get("base_attack")),
		"payload_descriptors": descriptors,
		"time_interactions": (plan.get("time_interactions", []) as Array).duplicate(true),
		"boss_conversion": (plan.get("boss_conversion", {}) as Dictionary).duplicate(true),
		"invulnerable_during_cast": bool(plan.get("invulnerable_during_cast", false)),
	}


func _materialize_payloads(plan: Dictionary, token: int) -> Array[Dictionary]:
	var payloads_value: Variant = plan.get("payloads", [])
	if not payloads_value is Array or (payloads_value as Array).is_empty():
		return []
	var payload_value: Variant = (payloads_value as Array)[0]
	if not payload_value is Dictionary:
		return []
	var payload := payload_value as Dictionary
	var payload_id := StringName(str(payload.get("descriptor_id", "")))
	var kind := StringName(str(payload.get("kind", "")))
	var parameters := (payload.get("parameters", {}) as Dictionary).duplicate(true)
	var run_seed := int(plan.get("run_seed", 0))
	var action_id := StringName(_resolved_action_id(plan))
	var result: Array[Dictionary] = []
	if action_id == ULTIMATE_ACTION_ID:
		var seed := SeedServiceScript.derive_weapon_action_seed(
			run_seed,
			StringName(PROFILE_ID),
			action_id,
			payload_id,
			token,
			0
		)
		result.append(_seeded_descriptor(
			payload_id,
			kind,
			parameters,
			seed,
			token,
			0,
			"per_tick_target"
		))
		return result
	var seed := SeedServiceScript.derive_weapon_action_seed(
		run_seed,
		StringName(PROFILE_ID),
		action_id,
		payload_id,
		token,
		0
	)
	parameters["direction"] = plan.get("aim_direction_snapshot", Vector2.RIGHT)
	result.append(_seeded_descriptor(
		payload_id,
		kind,
		parameters,
		seed,
		token,
		0,
		str(parameters.get("target_deduplication", "per_action_target"))
	))
	return result


func _seeded_descriptor(
	payload_id: StringName,
	kind: StringName,
	parameters: Dictionary,
	seed: int,
	token: int,
	outcome_index: int,
	deduplication: String
) -> Dictionary:
	return {
		"descriptor_id": str(payload_id),
		"kind": str(kind),
		"token": token,
		"generation": token,
		"outcome_id": "%s:%d" % [str(payload_id), outcome_index],
		"outcome_index": outcome_index,
		"seed": seed,
		"target_deduplication": deduplication,
		"parameters": parameters.duplicate(true),
	}


func _apply_committed_mutations(plan: Dictionary, token: int) -> void:
	_mana = maxf(MANA_MINIMUM, _mana - float(plan.get("mana_cost", 0.0)))
	var rewind_generation := int(plan.get("rewind_generation_claim", 0))
	if rewind_generation > 0 and not _claimed_rewind_generations.has(rewind_generation):
		_claimed_rewind_generations.append(rewind_generation)
		_claimed_rewind_generations.sort()
		while _claimed_rewind_generations.size() > MAX_CLAIMED_REWIND_GENERATIONS:
			_claimed_rewind_generation_floor = maxi(
				_claimed_rewind_generation_floor,
				_claimed_rewind_generations.pop_front()
			)
	var action_id := StringName(_resolved_action_id(plan))
	if action_id == UTILITY_ACTION_ID:
		var current_index := ELEMENT_SEQUENCE.find(str(_current_element))
		_current_element = StringName(ELEMENT_SEQUENCE[(current_index + 1) % ELEMENT_SEQUENCE.size()])
	elif action_id == CHARGED_ACTION_ID:
		var combo := (plan.get("combo", {}) as Dictionary).duplicate(true)
		var combo_window_remaining_frames := int(plan.get("combo_window_remaining_frames", 0))
		_cast_ledgers[str(token)] = {
			"action_id": str(action_id),
			"element": str(plan.get("element", "")),
			"generation": token,
			"confirmed_hit": false,
			"targets": {},
			"outcomes": {},
			"combo": combo.duplicate(true),
			"combo_window_remaining_frames": combo_window_remaining_frames,
			"combo_source_context": (plan.get("combo_source_context", {}) as Dictionary).duplicate(true),
		}
		_prune_cast_ledgers()
		var extra_mana := float(plan.get("combo_extra_mana", 0.0))
		if not combo.is_empty() and combo_window_remaining_frames > 0:
			_pending_combos[str(token)] = {
				"token": token,
				"combo": combo.duplicate(true),
				"extra_mana": extra_mana,
				"remaining_frames": combo_window_remaining_frames,
				"refunded": false,
			}


func _time_interaction_descriptors(
	action_id: StringName,
	time_context: Dictionary,
	combo: Dictionary,
	rewind_available: bool
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if action_id == SKILL_ACTION_ID and bool(time_context.get("stop_active", false)):
		result.append({
			"id": "stop",
			"interaction_id": "staff_stop_field",
			"requires_action": str(SKILL_ACTION_ID),
			"source_generation": int(time_context.get("stop_generation", 0)),
			"area_multiplier": 1.5,
			"duration_multiplier": 1.5,
			"maximum_area_multiplier": 1.5,
			"maximum_duration_multiplier": 1.5,
		})
	if action_id == CHARGED_ACTION_ID and rewind_available:
		result.append({
			"id": "rewind",
			"interaction_id": "staff_rewind_free_cast",
			"rewind_generation": int(time_context.get("rewind_generation", 0)),
			"window_frames": 120,
			"mana_free": true,
			"damage_multiplier": 1.3,
			"one_cast_claim": true,
		})
	if bool(time_context.get("accelerate_active", false)):
		result.append({
			"id": "accelerate",
			"interaction_id": "staff_fast_charge",
			"source_generation": int(time_context.get("accelerate_generation", 0)),
			"hold_threshold_frames": ACCELERATED_CHARGE_FRAMES,
			"mana_multiplier": 0.7,
		})
	if action_id == CHARGED_ACTION_ID and not combo.is_empty() and bool(time_context.get("rift_active", false)):
		result.append({
			"id": "rift",
			"interaction_id": "staff_rift_combination",
			"source_generation": int(time_context.get("rift_generation", 0)),
			"combo_id": str(combo.get("combo_id", "")),
			"area_multiplier": 1.3,
			"time_damage_multiplier": 0.5,
			"spatial_policy": "zone_intersection",
			"active_rifts": (time_context.get("active_rifts", []) as Array).duplicate(true),
		})
	return result


func _boss_conversion() -> Dictionary:
	return {
		"target_id": "chrono_warden",
		"conversion_id": "staff_control_conversion",
		"active_attack_policy": "preserve_committed",
		"preserve_committed_active_attack": true,
		"allowed_states": ["RECOVERY", "EXPOSED"],
		"interrupt_active_attack": false,
		"conversion_outcomes": ["action_delay", "exposure_extension", "poise_damage"],
		"freeze_delay_frames": 12,
		"blind_delay_frames": 8,
		"target_deduplication": true,
		"cleanup_policy": "source_generation_owned",
	}


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
	for boolean_field: String in ["stop_active", "rewind_echo_available", "rewind_cast_available", "accelerate_active", "rift_active"]:
		if time_context.has(boolean_field) and typeof(time_context[boolean_field]) != TYPE_BOOL:
			return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.%s" % boolean_field})
	for generation_field: String in ["stop_generation", "rewind_echo_generation", "rewind_generation", "accelerate_generation", "rift_generation"]:
		if time_context.has(generation_field):
			if typeof(time_context[generation_field]) != TYPE_INT or int(time_context[generation_field]) < 0:
				return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.%s" % generation_field})
	if time_context.has("rewind_echo_available"):
		if time_context.has("rewind_cast_available") and bool(time_context["rewind_cast_available"]) != bool(time_context["rewind_echo_available"]):
			return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.rewind_available_conflict"})
		time_context["rewind_cast_available"] = bool(time_context["rewind_echo_available"])
		time_context.erase("rewind_echo_available")
	if time_context.has("rewind_echo_generation"):
		if time_context.has("rewind_generation") and int(time_context["rewind_generation"]) != int(time_context["rewind_echo_generation"]):
			return _failure(&"INVALID_CONTEXT", {"field": "time_interactions.rewind_generation_conflict"})
		time_context["rewind_generation"] = int(time_context["rewind_echo_generation"])
		time_context.erase("rewind_echo_generation")
	var required_generations := {
		"stop_active": "stop_generation",
		"rewind_cast_available": "rewind_generation",
		"accelerate_active": "accelerate_generation",
		"rift_active": "rift_generation",
	}
	for active_field: String in required_generations:
		if bool(time_context.get(active_field, false)) and int(time_context.get(required_generations[active_field], 0)) <= 0:
			return _failure(&"SOURCE_GENERATION_REQUIRED", {"field": active_field})
	return {
		"ok": true,
		"code": &"OK",
		"context": {
			"run_seed": int(run_seed_value),
			"aim_direction": direction.normalized(),
			"time_interactions": time_context,
		},
	}


func _validate_commit_plan(plan: Dictionary) -> Dictionary:
	var contract_result := WeaponActionContractScript.validate_plan(plan, WEAPON_ID)
	if not bool(contract_result.get("ok", false)):
		return contract_result
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
	var mana_cost_value: Variant = plan.get("mana_cost")
	if typeof(mana_cost_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(mana_cost_value)) or float(mana_cost_value) < 0.0:
		return _failure(&"INVALID_MANA_COST")
	if float(mana_cost_value) > _mana + 0.00001:
		return _failure(&"INSUFFICIENT_MANA", {"required": float(mana_cost_value), "available": _mana})
	var rewind_generation := int(plan.get("rewind_generation_claim", 0))
	if (
		rewind_generation > 0
		and (
			rewind_generation <= _claimed_rewind_generation_floor
			or _claimed_rewind_generations.has(rewind_generation)
		)
	):
		return _failure(&"STALE_REWIND_GENERATION")
	if action_id == CHARGED_ACTION_ID:
		var element := StringName(str(plan.get("element", "")))
		if not ELEMENT_SEQUENCE.has(str(element)) or element != _current_element:
			return _failure(&"ELEMENT_MISMATCH")
		var combo := plan.get("combo", {}) as Dictionary
		var combo_window_value: Variant = plan.get("combo_window_remaining_frames")
		var combo_source_value: Variant = plan.get("combo_source_context", {})
		if typeof(combo_window_value) != TYPE_INT:
			return _failure(&"INVALID_COMBO_WINDOW")
		if not combo_source_value is Dictionary:
			return _failure(&"INVALID_COMBO_SOURCE")
		var combo_window_remaining_frames := int(combo_window_value)
		if not combo.is_empty():
			var expected_combo := _copy_indexed(_combinations_by_pair, StringName("%s>%s" % [str(_combo_element), str(_current_element)]))
			if expected_combo.is_empty() or not _frozen_equal(combo, expected_combo):
				return _failure(&"COMBO_MISMATCH")
			if (
				combo_window_remaining_frames <= 0
				or combo_window_remaining_frames > COMBO_WINDOW_FRAMES
				or combo_window_remaining_frames != _combo_remaining_frames
			):
				return _failure(&"COMBO_WINDOW_MISMATCH")
			if not _frozen_equal(combo_source_value, _combo_source_context):
				return _failure(&"COMBO_SOURCE_MISMATCH")
		elif combo_window_remaining_frames != 0 or not (combo_source_value as Dictionary).is_empty():
			return _failure(&"COMBO_WINDOW_MISMATCH")
	return {"ok": true, "code": &"OK", "context": {}}


func _frozen_modifiers() -> Dictionary:
	var value: Variant = _modifier_state.call("freeze_for_action")
	if not value is Dictionary or not _variant_numbers_are_finite(value):
		return _failure(&"INVALID_MODIFIER_SNAPSHOT")
	return {"ok": true, "code": &"OK", "modifiers": (value as Dictionary).duplicate(true)}


func _charge_frames(time_context: Dictionary, modifiers: Dictionary) -> int:
	var base_frames := ACCELERATED_CHARGE_FRAMES if bool(time_context.get("accelerate_active", false)) else PRIMARY_CHARGE_FRAMES
	var charge_rate := maxf(0.01, float(modifiers.get("weapon.charge_rate", 1.0)))
	return maxi(1, ceili(float(base_frames) / charge_rate))


func _resolved_combo_extra(combo: Dictionary, rewind_available: bool, accelerate_active: bool) -> float:
	if combo.is_empty() or rewind_available:
		return 0.0
	var extra := float(combo.get("extra_mana", 0.0))
	return extra * 0.7 if accelerate_active else extra


func _open_or_preserve_combo_window(element: StringName, source_context: Dictionary = {}) -> void:
	if _combo_element == &"" or _combo_remaining_frames <= 0:
		_combo_element = element
		_combo_remaining_frames = COMBO_WINDOW_FRAMES
		_combo_source_context = source_context.duplicate(true)


func _confirm_pending_combo(token: int) -> void:
	_pending_combos.erase(str(token))


func _refund_pending_combo(token: int) -> float:
	var token_key := str(token)
	if not _pending_combos.has(token_key):
		return 0.0
	var pending := (_pending_combos[token_key] as Dictionary).duplicate(true)
	if bool(pending.get("refunded", false)):
		return 0.0
	var refund := float(pending.get("extra_mana", 0.0))
	_mana = minf(_mana_maximum(), _mana + refund)
	_clear_cast_combo(token)
	_pending_combos.erase(token_key)
	return refund


func _pending_combo_for(token: int) -> Dictionary:
	var value: Variant = _pending_combos.get(str(token), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _first_pending_combo() -> Dictionary:
	if _pending_combos.is_empty():
		return {}
	var tokens: Array[int] = []
	for token_value: Variant in _pending_combos.keys():
		var token := int(str(token_value))
		if token > 0:
			tokens.append(token)
	tokens.sort()
	return _pending_combo_for(tokens[0]) if not tokens.is_empty() else {}


func _clear_cast_combo(token: int) -> void:
	var token_key := str(token)
	if not _cast_ledgers.has(token_key):
		return
	var cast := (_cast_ledgers[token_key] as Dictionary).duplicate(true)
	cast["combo"] = {}
	cast["combo_window_remaining_frames"] = 0
	cast["combo_source_context"] = {}
	_cast_ledgers[token_key] = cast


func _materialized_combo_result(combo: Dictionary, source_context: Dictionary) -> Dictionary:
	var result := combo.duplicate(true)
	if str(result.get("first", "")) != "lightning":
		return result
	var parameters_value: Variant = result.get("parameters", {})
	if not parameters_value is Dictionary:
		return result
	var parameters := (parameters_value as Dictionary).duplicate(true)
	parameters["origin_target_ids"] = (source_context.get("origin_target_ids", []) as Array).duplicate()
	parameters["origin_positions"] = (source_context.get("origin_positions", []) as Array).duplicate()
	result["parameters"] = parameters
	return result


func _payload_combo_source_context(result: Dictionary) -> Dictionary:
	var target_ids_value: Variant = result.get("chain_target_ids", [])
	var positions_value: Variant = result.get("chain_origin_positions", [])
	if not target_ids_value is Array or not positions_value is Array:
		return _failure(&"INVALID_COMBO_SOURCE")
	var target_ids: Array[int] = []
	var seen: Dictionary = {}
	for target_id_value: Variant in target_ids_value as Array:
		if typeof(target_id_value) != TYPE_INT or int(target_id_value) <= 0 or seen.has(int(target_id_value)):
			return _failure(&"INVALID_COMBO_SOURCE")
		seen[int(target_id_value)] = true
		target_ids.append(int(target_id_value))
	var positions: Array[Vector2] = []
	for position_value: Variant in positions_value as Array:
		if not position_value is Vector2:
			return _failure(&"INVALID_COMBO_SOURCE")
		var position := position_value as Vector2
		if not is_finite(position.x) or not is_finite(position.y):
			return _failure(&"INVALID_COMBO_SOURCE")
		positions.append(position)
	if not positions.is_empty() and positions.size() != target_ids.size():
		return _failure(&"INVALID_COMBO_SOURCE")
	return {
		"ok": true,
		"code": &"OK",
		"context": {
			"origin_target_ids": target_ids,
			"origin_positions": positions,
		},
	}


func _mana_maximum() -> float:
	if _modifier_state == null:
		return MANA_MAXIMUM
	var modifier_value: Variant = _modifier_state.call("snapshot")
	if modifier_value is Dictionary:
		return maxf(MANA_MINIMUM, float((modifier_value as Dictionary).get("weapon.mana_max", MANA_MAXIMUM)))
	return MANA_MAXIMUM


func _matches_frozen_profile(profile: Dictionary) -> bool:
	return (
		str(profile.get("id", "")) == PROFILE_ID
		and str(profile.get("weapon_id", "")) == str(WEAPON_ID)
		and str(profile.get("runtime_kind", "")) == str(WEAPON_ID)
		and int(profile.get("profile_version", 0)) == PROFILE_VERSION
		and _same_string_set(profile.get("capabilities", []), FROZEN_CAPABILITIES)
		and _profile_fingerprint(profile) == PROFILE_FINGERPRINT
	)


func _profile_fingerprint(profile: Dictionary) -> String:
	var bytes := _stable_serialize(profile).to_utf8_buffer()
	var hashing_context := HashingContext.new()
	if hashing_context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing_context.update(bytes) != OK:
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
	var result := {"actions": {}, "payloads": {}, "cues": {}, "combinations": {}, "elements": {}}
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
	var element_payload := (result["payloads"] as Dictionary).get("staff_element_cast", {}) as Dictionary
	var parameters := element_payload.get("parameters", {}) as Dictionary
	for combo_value: Variant in parameters.get("combinations", []) as Array:
		if not combo_value is Dictionary:
			return {"ok": false}
		var combo := combo_value as Dictionary
		var pair := "%s>%s" % [str(combo.get("first", "")), str(combo.get("second", ""))]
		if pair == ">" or (result["combinations"] as Dictionary).has(pair):
			return {"ok": false}
		(result["combinations"] as Dictionary)[pair] = combo.duplicate(true)
	for element_value: Variant in parameters.get("element_definitions", []) as Array:
		if not element_value is Dictionary:
			return {"ok": false}
		var element := element_value as Dictionary
		var element_id := str(element.get("element_id", ""))
		if element_id.is_empty() or (result["elements"] as Dictionary).has(element_id):
			return {"ok": false}
		(result["elements"] as Dictionary)[element_id] = element.duplicate(true)
	result["ok"] = true
	return result


func _valid_restore_snapshot(value: Dictionary) -> bool:
	if not _has_exact_fields(value, RUNTIME_SNAPSHOT_FIELDS):
		return false
	if (
		int(value.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION
		or not bool(value.get("configured", false))
		or str(value.get("profile_id", "")) != PROFILE_ID
		or int(value.get("profile_version", 0)) != PROFILE_VERSION
		or typeof(value.get("mana")) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value.get("mana", -1.0)))
		or float(value.get("mana", -1.0)) < MANA_MINIMUM
		or float(value.get("mana", -1.0)) > _mana_maximum()
		or str(value.get("current_element", "")) not in ELEMENT_SEQUENCE
		or (not str(value.get("combo_element", "")).is_empty() and str(value.get("combo_element", "")) not in ELEMENT_SEQUENCE)
		or typeof(value.get("combo_remaining_frames")) != TYPE_INT
		or int(value.get("combo_remaining_frames", -1)) < 0
		or int(value.get("combo_remaining_frames", -1)) > COMBO_WINDOW_FRAMES
		or not value.get("combo_source_context") is Dictionary
		or not value.get("pending_combo") is Dictionary
		or not value.get("pending_combos") is Dictionary
		or typeof(value.get("last_runtime_frame")) != TYPE_INT
		or int(value.get("last_runtime_frame", -2)) < -1
		or typeof(value.get("claimed_rewind_generation_floor")) != TYPE_INT
		or int(value.get("claimed_rewind_generation_floor", -1)) < 0
		or not _valid_generation_array(value.get("claimed_rewind_generations"))
		or (value.get("claimed_rewind_generations") as Array).size() > MAX_CLAIMED_REWIND_GENERATIONS
		or not value.get("cast_ledgers") is Dictionary
		or (value.get("cast_ledgers") as Dictionary).size() > MAX_TRACKED_CAST_LEDGERS
		or not value.get("mana_return_by_outcome") is Dictionary
		or typeof(value.get("active_token")) != TYPE_INT
		or int(value.get("active_token", -1)) < 0
		or not value.get("active_plan") is Dictionary
		or not value.get("modifier_snapshot") is Dictionary
		or not value.get("committed_definition") is Dictionary
		or not value.get("live_hold_context") is Dictionary
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
	if int(value["combo_remaining_frames"]) == 0 and not str(value["combo_element"]).is_empty():
		return false
	if int(value["combo_remaining_frames"]) > 0 and str(value["combo_element"]).is_empty():
		return false
	if not _valid_combo_source_context(value["combo_source_context"]):
		return false
	if not _valid_cast_ledgers(value["cast_ledgers"]):
		return false
	if not _valid_pending_combos(value["pending_combos"], value["cast_ledgers"]):
		return false
	if not _snapshot_pending_compatibility_matches(value["pending_combo"], value["pending_combos"]):
		return false
	for generation_value: Variant in value["claimed_rewind_generations"] as Array:
		if int(generation_value) <= int(value["claimed_rewind_generation_floor"]):
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
	var active_phase := str(value.get("active_phase", ""))
	var expected_adapter_phase := "prepared" if active_phase == "WINDUP" else "released"
	if active_phase not in ["WINDUP", "ACTIVE", "RECOVERY"]:
		return false
	var committed := value["committed_definition"] as Dictionary
	return (
		bool(value["adapter_active"])
		and str(adapter_snapshot.get("phase_state", "")) == expected_adapter_phase
		and not committed.is_empty()
		and int(committed.get("token", 0)) == active_token
		and committed == adapter_action
		and bool(WeaponActionContractScript.validate_plan(value["active_plan"], WEAPON_ID).get("ok", false))
	)


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _prune_cast_ledgers() -> void:
	if _cast_ledgers.size() <= MAX_TRACKED_CAST_LEDGERS:
		return
	var tokens: Array[int] = []
	for token_value: Variant in _cast_ledgers.keys():
		var token := int(str(token_value))
		if token > 0:
			tokens.append(token)
	tokens.sort()
	while tokens.size() > MAX_TRACKED_CAST_LEDGERS:
		_erase_cast_ledger(tokens.pop_front())


func _erase_cast_ledger(token: int) -> void:
	if token <= 0:
		return
	_refund_pending_combo(token)
	_cast_ledgers.erase(str(token))
	var prefix := "%d:" % token
	for outcome_key: Variant in _mana_return_by_outcome.keys():
		if str(outcome_key).begins_with(prefix):
			_mana_return_by_outcome.erase(outcome_key)


func _valid_combo_source_context(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var context := value as Dictionary
	var ids_value: Variant = context.get("origin_target_ids", [])
	var positions_value: Variant = context.get("origin_positions", [])
	if not ids_value is Array or not positions_value is Array:
		return false
	var seen: Dictionary = {}
	for id_value: Variant in ids_value as Array:
		if typeof(id_value) != TYPE_INT or int(id_value) <= 0 or seen.has(int(id_value)):
			return false
		seen[int(id_value)] = true
	for position_value: Variant in positions_value as Array:
		if not position_value is Vector2:
			return false
		var position := position_value as Vector2
		if not is_finite(position.x) or not is_finite(position.y):
			return false
	return (positions_value as Array).is_empty() or (positions_value as Array).size() == (ids_value as Array).size()


func _valid_cast_ledgers(value: Variant) -> bool:
	if not value is Dictionary or (value as Dictionary).size() > MAX_TRACKED_CAST_LEDGERS:
		return false
	for token_key_value: Variant in (value as Dictionary).keys():
		var token_key := str(token_key_value)
		var token := int(token_key)
		var cast_value: Variant = (value as Dictionary)[token_key_value]
		if token <= 0 or not cast_value is Dictionary:
			return false
		var cast := cast_value as Dictionary
		if (
			str(cast.get("action_id", "")) != str(CHARGED_ACTION_ID)
			or str(cast.get("element", "")) not in ELEMENT_SEQUENCE
			or typeof(cast.get("generation")) != TYPE_INT
			or int(cast.get("generation", 0)) != token
			or typeof(cast.get("confirmed_hit")) != TYPE_BOOL
			or not cast.get("targets", {}) is Dictionary
			or not cast.get("outcomes", {}) is Dictionary
			or not cast.get("combo", {}) is Dictionary
			or typeof(cast.get("combo_window_remaining_frames")) != TYPE_INT
			or int(cast.get("combo_window_remaining_frames", -1)) < 0
			or int(cast.get("combo_window_remaining_frames", -1)) > COMBO_WINDOW_FRAMES
			or not _valid_combo_source_context(cast.get("combo_source_context", {}))
		):
			return false
		for outcome_value: Variant in (cast.get("outcomes", {}) as Dictionary).values():
			if not outcome_value is Dictionary:
				return false
			var outcome := outcome_value as Dictionary
			if (
				typeof(outcome.get("terminal")) != TYPE_BOOL
				or not outcome.get("targets", {}) is Dictionary
				or typeof(outcome.get("mana_return")) not in [TYPE_INT, TYPE_FLOAT]
				or not is_finite(float(outcome.get("mana_return", -1.0)))
				or float(outcome.get("mana_return", -1.0)) < 0.0
				or float(outcome.get("mana_return", -1.0)) > MANA_RETURN_CAP_PER_OUTCOME
			):
				return false
	return true


func _valid_pending_combos(value: Variant, cast_ledgers_value: Variant) -> bool:
	if not value is Dictionary or not cast_ledgers_value is Dictionary:
		return false
	var pending_combos := value as Dictionary
	var cast_ledgers := cast_ledgers_value as Dictionary
	if pending_combos.size() > MAX_TRACKED_CAST_LEDGERS:
		return false
	for token_key_value: Variant in pending_combos.keys():
		var token_key := str(token_key_value)
		var token := int(token_key)
		var pending_value: Variant = pending_combos[token_key_value]
		if token <= 0 or not pending_value is Dictionary or not cast_ledgers.has(token_key):
			return false
		var pending := pending_value as Dictionary
		if (
			int(pending.get("token", 0)) != token
			or not pending.get("combo", {}) is Dictionary
			or (pending.get("combo", {}) as Dictionary).is_empty()
			or typeof(pending.get("extra_mana")) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(pending.get("extra_mana", -1.0)))
			or float(pending.get("extra_mana", -1.0)) < 0.0
			or typeof(pending.get("remaining_frames")) != TYPE_INT
			or int(pending.get("remaining_frames", 0)) <= 0
			or int(pending.get("remaining_frames", 0)) > COMBO_WINDOW_FRAMES
			or typeof(pending.get("refunded")) != TYPE_BOOL
			or bool(pending.get("refunded", true))
		):
			return false
		var cast_value: Variant = cast_ledgers[token_key]
		if not cast_value is Dictionary:
			return false
		var cast := cast_value as Dictionary
		if not _frozen_equal(cast.get("combo", {}), pending.get("combo", {})):
			return false
	return true


func _snapshot_pending_compatibility_matches(single_value: Variant, pending_value: Variant) -> bool:
	if not single_value is Dictionary or not pending_value is Dictionary:
		return false
	var pending := pending_value as Dictionary
	if pending.is_empty():
		return (single_value as Dictionary).is_empty()
	var tokens: Array[int] = []
	for token_value: Variant in pending.keys():
		var token := int(str(token_value))
		if token > 0:
			tokens.append(token)
	tokens.sort()
	if tokens.is_empty():
		return false
	return _frozen_equal(single_value, pending.get(str(tokens[0]), {}))


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
	for field: String in ["base_attack", "attack_speed"]:
		var value: Variant = adapter.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) <= 0.0:
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
