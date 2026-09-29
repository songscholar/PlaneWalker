class_name SwordWeaponRuntime
extends "res://scripts/combat/weapons/weapon_runtime.gd"

const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
const PROFILE_ID := "sword_m1_v1"
const WEAPON_ID := &"sword"
const COMBO_ACTION_IDS: Array[StringName] = [&"light_1", &"light_2", &"light_3"]
const HEAVY_ACTION_ID := &"heavy"
const COMBO_RESET_FRAMES := 48
const REQUIRED_ADAPTER_METHODS: Array[StringName] = [
	&"attack_definition",
	&"begin_attack",
	&"is_attacking",
	&"enter_active_phase",
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
		or int(next_profile.get("profile_version", 0)) <= 0
	):
		return false

	var indexes := _build_profile_indexes(next_profile)
	if not bool(indexes.get("ok", false)):
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
	var legacy_definition_value: Variant = _adapter.call("attack_definition", heavy)
	if not legacy_definition_value is Dictionary or (legacy_definition_value as Dictionary).is_empty():
		return _failure(&"ADAPTER_DEFINITION_UNAVAILABLE")
	var legacy_definition := (legacy_definition_value as Dictionary).duplicate(true)
	var timing_multiplier := _timing_multiplier(frozen_modifiers)
	var recovery_frames := _scaled_frames(legacy_definition.get("recovery_frames", 0), timing_multiplier)
	var cancel_from_frame := mini(
		_scaled_frames(legacy_definition.get("recovery_cancel_frame", 0), timing_multiplier),
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
				"duration_frames": _scaled_frames(legacy_definition.get("windup_frames", 0), timing_multiplier),
				"movement_multiplier": float(action.get("movement_multiplier", 1.0)),
			},
			{
				"phase": "ACTIVE",
				"duration_frames": _scaled_frames(legacy_definition.get("active_frames", 0), timing_multiplier),
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
	var committed_value: Variant = _adapter.call("begin_attack", bool(plan.get("heavy", false)))
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
			if _active_phase != &"WINDUP" or not _activate_payload():
				return []
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
					"cue_id": str((_active_plan["cue"] as Dictionary).get("cue_id", "")),
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
	if bool(next_adapter.get("active", false)):
		return false
	_combo_step = int(runtime_snapshot["combo_step"])
	_active_token = int(runtime_snapshot["active_token"])
	_active_phase = StringName(str(runtime_snapshot["active_phase"]))
	_active_plan = (runtime_snapshot["active_plan"] as Dictionary).duplicate(true)
	_modifier_snapshot = (runtime_snapshot["modifier_snapshot"] as Dictionary).duplicate(true)
	_restore_adapter_snapshot(next_adapter)
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
	var payloads: Array = plan.get("payloads", [])
	if payloads.size() != 1 or not payloads[0] is Dictionary:
		return false
	var parameters: Dictionary = (payloads[0] as Dictionary).get("parameters", {})
	return (
		bool(definition.get("heavy", false)) == bool(plan.get("heavy", false))
		and bool(definition.get("finisher", false)) == parameters.get("tags", []).has("attack:finisher")
		and is_equal_approx(
			float(definition.get("multiplier", 0.0)),
			float(parameters.get("damage_multiplier", 0.0))
		)
	)


func _activate_payload() -> bool:
	var live_base_attack := float(_adapter.get("base_attack"))
	var live_rewards := _legacy_reward_snapshot()
	var damage_multiplier := float(_modifier_snapshot.get("weapon.damage", 1.0))
	_adapter.set("base_attack", float(_active_plan.get("base_attack_snapshot", live_base_attack)) * damage_multiplier)
	_apply_legacy_reward_snapshot(_active_plan.get("legacy_reward_snapshot", {}))
	var activated := bool(_adapter.call("enter_active_phase"))
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


func _valid_restore_snapshot(value: Dictionary) -> bool:
	if int(value.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return false
	if str(value.get("profile_id", "")) != str(_profile_snapshot.get("id", "")):
		return false
	if int(value.get("profile_version", 0)) != int(_profile_snapshot.get("profile_version", 0)):
		return false
	if typeof(value.get("combo_step")) != TYPE_INT or int(value["combo_step"]) not in range(COMBO_ACTION_IDS.size()):
		return false
	if typeof(value.get("active_token")) != TYPE_INT or int(value["active_token"]) < 0:
		return false
	if str(value.get("active_phase", "")) not in ["READY", "WINDUP", "RECOVERY"]:
		return false
	if not value.get("active_plan") is Dictionary or not value.get("modifier_snapshot") is Dictionary:
		return false
	if not value.get("adapter") is Dictionary:
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
	return maxf(0.2, float(modifiers.get("weapon.attack_speed", 1.0)))


func _scaled_frames(value: Variant, timing_multiplier: float) -> int:
	return maxi(1, ceili(float(value) / maxf(0.2, timing_multiplier)))


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


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
