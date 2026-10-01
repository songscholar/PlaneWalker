class_name WandererCharacterRuntime
extends "res://scripts/player/characters/character_runtime.gd"

const CharacterPayloadExecutionScript := preload(
	"res://scripts/combat/character_payload_execution.gd"
)
const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")

const CHARACTER_ID := &"wanderer"
const PROFILE_ID := "wanderer_launch_v1"
const STRATEGY_SNAPSHOT_SCHEMA_VERSION := 1
const STRATEGY_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"runtime_kind",
	"configured",
	"last_runtime_frame",
	"revision",
	"resource_value",
	"run_id",
	"run_revision",
	"owner_character_generation",
	"path_progress",
	"room_id",
	"room_revision",
	"first_mark_claimed",
	"cleared_room_claims",
	"mastery_claims",
	"wayfarer_until_frame",
	"wayfarer_source_token",
	"authorized_rift_generation",
	"rift_progress_claims",
	"forgiveness_descriptor",
	"forgiveness_expires_frame",
	"skill_cooldown_until_frame",
	"skill_action",
	"anchor_active",
	"anchor_generation",
	"anchor_position",
	"anchor_expires_frame",
	"anchor_damage_total",
	"anchor_run_id",
	"banked_room_completions",
]

var _run_id: StringName = &""
var _run_revision: int = 0
var _owner_character_generation: int = 1
var _path_progress: int = 0
var _room_id: StringName = &""
var _room_revision: int = 0
var _first_mark_claimed: bool = false
var _cleared_room_claims: Array[String] = []
var _mastery_claims: Array[String] = []
var _wayfarer_until_frame: int = -1
var _wayfarer_source_token: int = 0
var _authorized_rift_generation: int = 0
var _rift_progress_claims: Array[int] = []
var _forgiveness_descriptor: Dictionary = {}
var _forgiveness_expires_frame: int = -1
var _skill_cooldown_until_frame: int = -1
var _skill_action: Dictionary = {}
var _anchor_active: bool = false
var _anchor_generation: int = 0
var _anchor_position: Vector2 = Vector2.ZERO
var _anchor_expires_frame: int = -1
var _anchor_damage_total: float = 0.0
var _anchor_run_id: StringName = &""
var _banked_room_completions: int = 0


func _init() -> void:
	_runtime_kind = &"wanderer"


func configure(owner: Node, profile: Variant, talents: PackedStringArray) -> bool:
	if profile == null or not profile is RefCounted or not profile.has_method("snapshot"):
		return false
	var profile_value: Variant = profile.call("snapshot")
	if (
		not profile_value is Dictionary
		or str((profile_value as Dictionary).get("character_id", "")) != str(CHARACTER_ID)
		or str((profile_value as Dictionary).get("runtime_kind", "")) != "wanderer"
		or str(((profile_value as Dictionary).get("character_skill", {}) as Dictionary).get("handler_id", "")) != "waypoint_recall"
	):
		return false
	if not super.configure(owner, profile, talents):
		return false
	_reset_strategy_state()
	_revision = 0
	return true


func reset_runtime_state(_reason: StringName) -> void:
	if not _configured:
		return
	super.reset_runtime_state(_reason)
	_reset_strategy_state()


func advance_frame(context: Dictionary) -> Array[Dictionary]:
	if not _valid_next_frame(context):
		return []
	var runtime_frame := int(context["runtime_frame"])
	super.advance_frame(context)
	var events: Array[Dictionary] = []

	if _wayfarer_until_frame >= 0 and runtime_frame >= _wayfarer_until_frame:
		_wayfarer_until_frame = -1
		_wayfarer_source_token = 0
		events.append(_event(&"wayfarer_window_expired", runtime_frame, 0, {}))
	if _forgiveness_expires_frame >= 0 and runtime_frame >= _forgiveness_expires_frame:
		_forgiveness_descriptor.clear()
		_forgiveness_expires_frame = -1
		events.append(_event(&"weapon_forgiveness_expired", runtime_frame, 0, {}))
	if _anchor_active and runtime_frame >= _anchor_expires_frame:
		var expired_generation := _anchor_generation
		var cooldown_start := _anchor_expires_frame
		_clear_anchor()
		_skill_cooldown_until_frame = cooldown_start + _skill_cooldown_frames()
		events.append(_event(
			&"waypoint_anchor_expired",
			cooldown_start,
			0,
			{"anchor_generation": expired_generation}
		))
		events.append(_cooldown_event(cooldown_start, _skill_cooldown_frames(), &"anchor_expired"))

	if not _skill_action.is_empty():
		var committed := bool(_skill_action.get("committed", false))
		var commit_frame := int(_skill_action.get("commit_frame", -1))
		if not committed and runtime_frame >= commit_frame:
			events.append_array(_commit_waypoint_action(commit_frame))
		if (
			not _skill_action.is_empty()
			and bool(_skill_action.get("committed", false))
			and runtime_frame >= int(_skill_action.get("recovery_until_frame", -1))
		):
			var token := int(_skill_action.get("token", 0))
			var completion_frame := int(_skill_action.get("recovery_until_frame", runtime_frame))
			_skill_action.clear()
			events.append(_event(&"character_skill_completed", completion_frame, token, {
				"skill_id": &"waypoint_recall",
			}))
	return events


func plan_character_skill(intent: Dictionary, context: Dictionary) -> Dictionary:
	if (
		not _configured
		or not _skill_action.is_empty()
		or not _valid_skill_intent(intent, &"pressed")
		or not _valid_live_context(context)
		or not bool(context.get("alive", false))
		or typeof(context.get("position")) != TYPE_VECTOR2
		or not _finite_vector(context["position"] as Vector2)
	):
		return {"ok": false, "code": "invalid_context"}
	var runtime_frame := int(context["runtime_frame"])
	if _skill_cooldown_until_frame >= 0 and runtime_frame < _skill_cooldown_until_frame:
		return {"ok": false, "code": "cooldown_active"}
	var energy: Variant = context.get("time_energy")
	if not _finite_number(energy) or float(energy) < _skill_energy_cost():
		return {"ok": false, "code": "insufficient_energy"}
	var action_mode := &"recall" if _anchor_active else &"place"
	return {
		"ok": true,
		"code": "planned",
		"plan": {
			"skill_id": &"waypoint_recall",
			"action_mode": action_mode,
			"runtime_frame": runtime_frame,
			"commit_frame": runtime_frame + _skill_parameter_int("windup_frames"),
			"run_id": StringName(context["run_id"]),
			"run_revision": int(context["run_revision"]),
			"owner_character_generation": int(context["owner_character_generation"]),
			"position": context["position"],
			"energy_cost": _skill_energy_cost(),
			"anchor_generation": _anchor_generation,
			"strategy_revision": _revision,
		},
	}


func commit_character_skill(plan: Dictionary, token: int) -> Dictionary:
	if not _valid_skill_plan(plan) or token <= 0:
		return {"ok": false, "code": "invalid_plan"}
	if not _bind_run(
		StringName(plan["run_id"]),
		int(plan["run_revision"]),
		int(plan["owner_character_generation"])
	):
		return {"ok": false, "code": "stale_run"}
	_skill_action = plan.duplicate(true)
	_skill_action["token"] = token
	_skill_action["committed"] = false
	_skill_action["recovery_until_frame"] = -1
	_revision += 1
	return {
		"ok": true,
		"code": "accepted",
		"events": [],
		"context": {
			"skill_id": &"waypoint_recall",
			"action_mode": plan["action_mode"],
			"commit_frame": int(plan["commit_frame"]),
		},
	}


func character_action_cancellation_state() -> Dictionary:
	return {
		"active": not _skill_action.is_empty(),
		"committed": bool(_skill_action.get("committed", false)),
	}


func cancel_uncommitted_action(_reason: StringName) -> Dictionary:
	if _skill_action.is_empty():
		return {"ok": true, "cancelled": false}
	if bool(_skill_action.get("committed", false)):
		return {"ok": true, "cancelled": false}
	_skill_action.clear()
	_revision += 1
	return {"ok": true, "cancelled": true}


func before_time_skill(time_context: Dictionary) -> Dictionary:
	if not _valid_time_context(time_context):
		return {"ok": false, "decision": {}}
	var cost := 1 if int(_resource_value) > 0 else 0
	var decision := CharacterPayloadExecutionScript.decision(
		&"wanderer_time_conversion",
		CHARACTER_ID,
		int(time_context["runtime_frame"]),
		int(time_context["token"]),
		int(time_context["generation"]),
		{
			"ability_id": StringName(time_context["ability_id"]),
			"path_mark_cost": cost,
			"strategy_revision": _revision,
			"run_id": StringName(time_context["run_id"]),
			"run_revision": int(time_context["run_revision"]),
		}
	)
	return {"ok": not decision.is_empty(), "decision": decision}


func after_time_skill(time_context: Dictionary) -> Array[Dictionary]:
	if not _valid_time_context(time_context):
		return []
	var decision_value: Variant = time_context.get("character_decision")
	if not CharacterPayloadExecutionScript.is_decision(decision_value):
		return []
	var decision := decision_value as Dictionary
	var parameters := decision.get("parameters", {}) as Dictionary
	if (
		StringName(str(decision.get("decision_id", ""))) != &"wanderer_time_conversion"
		or int(decision.get("runtime_frame", -1)) != int(time_context["runtime_frame"])
		or int(decision.get("token", -1)) != int(time_context["token"])
		or int(decision.get("generation", -1)) != int(time_context["generation"])
		or int(parameters.get("strategy_revision", -1)) != _revision
		or StringName(str(parameters.get("ability_id", ""))) != StringName(time_context["ability_id"])
		or not _bind_run(
			StringName(time_context["run_id"]),
			int(time_context["run_revision"]),
			int(time_context.get("owner_character_generation", _owner_character_generation))
		)
	):
		return []
	var cost := int(parameters.get("path_mark_cost", 0))
	if cost != 1 or int(_resource_value) < 1:
		return []
	_resource_value = int(_resource_value) - 1
	var runtime_frame := int(time_context["runtime_frame"])
	var ability_id := StringName(time_context["ability_id"])
	var window_frames := _passive_parameter_int("wayfarer_window_frames")
	if ability_id == &"stop":
		window_frames += int(((_profile_snapshot.get("time_interactions", {}) as Dictionary).get(
			"stop", {}
		) as Dictionary).get("parameters", {}).get("window_bonus_frames", 0))
	_wayfarer_until_frame = runtime_frame + window_frames
	_wayfarer_source_token = int(time_context["token"])
	if ability_id == &"rift":
		var rift_generation_value: Variant = time_context.get("rift_generation", 0)
		if typeof(rift_generation_value) == TYPE_INT and int(rift_generation_value) > 0:
			_authorized_rift_generation = int(rift_generation_value)
	_revision += 1
	return [
		_resource_event(runtime_frame, int(time_context["token"]), &"time_skill_committed"),
		_event(&"wayfarer_window_opened", runtime_frame, int(time_context["token"]), {
			"ability_id": ability_id,
			"active_until_frame": _wayfarer_until_frame,
			"duration_frames": window_frames,
		}),
	]


func on_weapon_mastery_confirmed(mastery_context: Dictionary) -> Array[Dictionary]:
	var normalized := _normalized_mastery(mastery_context)
	if normalized.is_empty():
		return []
	var claim_key := "%d:%d:%s" % [
		int(normalized["generation"]),
		int(normalized["action_token"]),
		str(normalized["mastery_family"]),
	]
	if _mastery_claims.has(claim_key):
		return []
	_mastery_claims.append(claim_key)
	_mastery_claims.sort()
	var context := normalized["context"] as Dictionary
	var runtime_frame := int(context["runtime_frame"])
	var token := int(normalized["action_token"])
	var events: Array[Dictionary] = []

	if _wayfarer_until_frame >= 0 and runtime_frame < _wayfarer_until_frame:
		_wayfarer_until_frame = -1
		_wayfarer_source_token = 0
		var maximum_hp := float(context.get("maximum_hp", 0.0))
		var heal_amount := maximum_hp * _passive_parameter_float("wayfarer_heal_ratio")
		var forgiveness := _forgiveness_for_weapon(StringName(normalized["weapon_id"]))
		_forgiveness_descriptor = forgiveness.duplicate(true)
		_forgiveness_expires_frame = runtime_frame + _passive_parameter_int(
			"forgiveness_expiry_frames"
		)
		events.append(_event(&"time_energy_restore_requested", runtime_frame, token, {
			"amount": float(_passive_parameter_int("wayfarer_energy_restore")),
			"reason": &"wayfarer_window",
		}))
		events.append(_event(&"health_restore_requested", runtime_frame, token, {
			"amount": heal_amount,
			"cap_kind": &"missing_hp",
			"reason": &"wayfarer_window",
		}))
		events.append(_event(&"weapon_forgiveness_granted", runtime_frame, token, forgiveness))
		events.append(_event(&"character_conversion_resolved", runtime_frame, token, {
			"conversion_id": &"wanderer_wayfarer",
			"mastery_family": normalized["mastery_family"],
		}))
		_revision += 1
		return events

	var progress_gain := 1
	var rift_generation_value: Variant = context.get("rift_generation", 0)
	if (
		typeof(rift_generation_value) == TYPE_INT
		and int(rift_generation_value) > 0
		and int(rift_generation_value) == _authorized_rift_generation
		and not _rift_progress_claims.has(int(rift_generation_value))
	):
		_rift_progress_claims.append(int(rift_generation_value))
		_rift_progress_claims.sort()
		progress_gain += int((((_profile_snapshot.get("time_interactions", {}) as Dictionary).get(
			"rift", {}
		) as Dictionary).get("parameters", {}) as Dictionary).get("progress_bonus", 0))

	var granted_mark := false
	if not _first_mark_claimed and not _room_id.is_empty():
		_first_mark_claimed = true
		_path_progress = 0
		granted_mark = _grant_mark()
	else:
		var threshold := _passive_parameter_int("progress_threshold")
		if bool(context.get("accelerate_active", false)):
			threshold = int((((_profile_snapshot.get("time_interactions", {}) as Dictionary).get(
				"accelerate", {}
			) as Dictionary).get("parameters", {}) as Dictionary).get("progress_threshold", threshold))
		_path_progress += progress_gain
		if _path_progress >= threshold:
			_path_progress = 0
			granted_mark = _grant_mark()
	if granted_mark:
		events.append(_resource_event(runtime_frame, token, &"weapon_mastery"))
	events.append(_event(&"path_progress_changed", runtime_frame, token, {
		"current": _path_progress,
		"threshold": _passive_parameter_int("progress_threshold"),
	}))
	_revision += 1
	return events


func on_weapon_action_committed(action_context: Dictionary) -> Array[Dictionary]:
	if _forgiveness_descriptor.is_empty() or not bool(action_context.get("consume_forgiveness", false)):
		return []
	var weapon_id := StringName(str(action_context.get("weapon_id", "")))
	if weapon_id != StringName(str(_forgiveness_descriptor.get("weapon_id", ""))):
		return []
	var runtime_frame_value: Variant = action_context.get("runtime_frame")
	if typeof(runtime_frame_value) != TYPE_INT or int(runtime_frame_value) != _last_runtime_frame:
		return []
	var token := int(action_context.get("action_token", 0))
	_forgiveness_descriptor.clear()
	_forgiveness_expires_frame = -1
	_revision += 1
	return [_event(&"weapon_forgiveness_consumed", _last_runtime_frame, token, {
		"weapon_id": weapon_id,
	})]


func after_damage(damage_context: Dictionary) -> Array[Dictionary]:
	if not _anchor_active or not _context_matches_run(damage_context):
		return []
	if (
		typeof(damage_context.get("runtime_frame")) != TYPE_INT
		or int(damage_context["runtime_frame"]) != _last_runtime_frame
		or StringName(str(damage_context.get("source_kind", ""))) != &"enemy"
		or typeof(damage_context.get("prevented")) != TYPE_BOOL
		or bool(damage_context["prevented"])
		or typeof(damage_context.get("irreversible")) != TYPE_BOOL
		or bool(damage_context["irreversible"])
		or not _finite_number(damage_context.get("finalized_damage"))
		or float(damage_context["finalized_damage"]) <= 0.0
	):
		return []
	_anchor_damage_total += float(damage_context["finalized_damage"])
	_revision += 1
	return []


func on_room_started(room_context: Dictionary) -> Array[Dictionary]:
	if not _valid_room_context(room_context):
		return []
	var run_id := StringName(room_context["run_id"])
	var run_revision := int(room_context["run_revision"])
	if not _bind_run(run_id, run_revision, int(room_context.get(
		"owner_character_generation", _owner_character_generation
	))):
		return []
	var room_id := StringName(room_context["room_id"])
	var room_revision := int(room_context["room_revision"])
	if room_id == _room_id and room_revision <= _room_revision:
		return []
	_room_id = room_id
	_room_revision = room_revision
	_first_mark_claimed = false
	_revision += 1
	return [_event(&"room_path_started", max(_last_runtime_frame, 0), 0, {
		"room_id": room_id,
		"room_revision": room_revision,
	})]


func on_room_cleared(room_context: Dictionary) -> Array[Dictionary]:
	if (
		not _valid_room_context(room_context)
		or not _context_matches_run(room_context)
		or StringName(room_context["room_id"]) != _room_id
		or int(room_context["room_revision"]) != _room_revision
	):
		return []
	var claim_key := "%s:%d" % [str(_room_id), _room_revision]
	if _cleared_room_claims.has(claim_key):
		return []
	_cleared_room_claims.append(claim_key)
	_cleared_room_claims.sort()
	_banked_room_completions += 1
	var heal_amount := int(_resource_value) * _passive_parameter_int("room_clear_heal_per_mark")
	_revision += 1
	var events: Array[Dictionary] = [
		_event(&"room_completion_banked", max(_last_runtime_frame, 0), 0, {
			"room_id": _room_id,
			"room_revision": _room_revision,
			"banked_room_completions": _banked_room_completions,
		}),
	]
	if heal_amount > 0:
		events.append(_event(&"health_restore_requested", max(_last_runtime_frame, 0), 0, {
			"amount": float(heal_amount),
			"cap_kind": &"missing_hp",
			"reason": &"room_clear_path_marks",
		}))
	return events


func on_run_terminal(run_context: Dictionary) -> Dictionary:
	if not _context_matches_run(run_context):
		return {"ok": false, "summary": {}}
	return {
		"ok": true,
		"summary": {
			"memory_fragment": _banked_room_completions,
			"banked_room_completions": _banked_room_completions,
		},
	}


func snapshot() -> Dictionary:
	return {
		"schema_version": STRATEGY_SNAPSHOT_SCHEMA_VERSION,
		"runtime_kind": str(_runtime_kind),
		"configured": _configured,
		"last_runtime_frame": _last_runtime_frame,
		"revision": _revision,
		"resource_value": int(_resource_value),
		"run_id": str(_run_id),
		"run_revision": _run_revision,
		"owner_character_generation": _owner_character_generation,
		"path_progress": _path_progress,
		"room_id": str(_room_id),
		"room_revision": _room_revision,
		"first_mark_claimed": _first_mark_claimed,
		"cleared_room_claims": _cleared_room_claims.duplicate(),
		"mastery_claims": _mastery_claims.duplicate(),
		"wayfarer_until_frame": _wayfarer_until_frame,
		"wayfarer_source_token": _wayfarer_source_token,
		"authorized_rift_generation": _authorized_rift_generation,
		"rift_progress_claims": _rift_progress_claims.duplicate(),
		"forgiveness_descriptor": _forgiveness_descriptor.duplicate(true),
		"forgiveness_expires_frame": _forgiveness_expires_frame,
		"skill_cooldown_until_frame": _skill_cooldown_until_frame,
		"skill_action": _skill_action.duplicate(true),
		"anchor_active": _anchor_active,
		"anchor_generation": _anchor_generation,
		"anchor_position": _anchor_position,
		"anchor_expires_frame": _anchor_expires_frame,
		"anchor_damage_total": _anchor_damage_total,
		"anchor_run_id": str(_anchor_run_id),
		"banked_room_completions": _banked_room_completions,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	return not _validated_snapshot(value).is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	var normalized := _validated_snapshot(value)
	if normalized.is_empty():
		return false
	_install_snapshot(normalized)
	return snapshot() == normalized


func restore_gameplay_rewind_snapshot(value: Dictionary) -> bool:
	return not _validated_snapshot(value).is_empty()


func presentation_snapshot() -> Dictionary:
	return {
		"runtime_kind": str(_runtime_kind),
		"resource_value": int(_resource_value),
		"path_progress": _path_progress,
		"wayfarer_active": _wayfarer_until_frame > _last_runtime_frame,
		"wayfarer_until_frame": _wayfarer_until_frame,
		"anchor_active": _anchor_active,
		"anchor_expires_frame": _anchor_expires_frame,
		"skill_cooldown_until_frame": _skill_cooldown_until_frame,
	}


func can_reanchor_replay_neutral_frame(runtime_frame: int) -> bool:
	return (
		super.can_reanchor_replay_neutral_frame(runtime_frame)
		and _run_id == &""
		and _path_progress == 0
		and _room_id == &""
		and _cleared_room_claims.is_empty()
		and _mastery_claims.is_empty()
		and _wayfarer_until_frame == -1
		and _forgiveness_descriptor.is_empty()
		and _skill_action.is_empty()
		and not _anchor_active
		and _banked_room_completions == 0
	)


func _commit_waypoint_action(commit_frame: int) -> Array[Dictionary]:
	var token := int(_skill_action.get("token", 0))
	var action_mode := StringName(str(_skill_action.get("action_mode", "")))
	var events: Array[Dictionary] = []
	if action_mode == &"recall" and (
		not _anchor_active
		or int(_skill_action.get("anchor_generation", -1)) != _anchor_generation
		or _anchor_run_id != _run_id
	):
		_skill_action.clear()
		_revision += 1
		return [_event(&"waypoint_recall_failed", commit_frame, token, {
			"reason": &"stale_anchor",
		})]

	events.append(_event(&"time_energy_spend_requested", commit_frame, token, {
		"amount": float(_skill_action.get("energy_cost", _skill_energy_cost())),
		"reason": &"waypoint_recall",
	}))
	if action_mode == &"place":
		_anchor_generation += 1
		_anchor_active = true
		_anchor_position = _skill_action["position"] as Vector2
		_anchor_expires_frame = commit_frame + _skill_parameter_int("anchor_frames")
		_anchor_damage_total = 0.0
		_anchor_run_id = _run_id
		events.append(_event(&"waypoint_anchor_placed", commit_frame, token, {
			"anchor_generation": _anchor_generation,
			"position": _anchor_position,
			"expires_frame": _anchor_expires_frame,
		}))
	else:
		var target_position := _anchor_position
		var heal_amount := _anchor_damage_total * _skill_parameter_float("healing_ratio")
		var used_generation := _anchor_generation
		_clear_anchor()
		_skill_cooldown_until_frame = commit_frame + _skill_cooldown_frames()
		events.append(_event(&"waypoint_recall_requested", commit_frame, token, {
			"anchor_generation": used_generation,
			"target_position": target_position,
			"heal_amount": heal_amount,
			"cap_kind": &"missing_hp",
		}))
		events.append(_cooldown_event(commit_frame, _skill_cooldown_frames(), &"anchor_used"))
	_skill_action["committed"] = true
	_skill_action["recovery_until_frame"] = commit_frame + _skill_parameter_int("recovery_frames")
	events.append(_event(&"character_skill_committed", commit_frame, token, {
		"skill_id": &"waypoint_recall",
		"action_mode": action_mode,
	}))
	_revision += 1
	return events


func _valid_skill_plan(plan: Dictionary) -> bool:
	return (
		_configured
		and _skill_action.is_empty()
		and str(plan.get("skill_id", "")) == "waypoint_recall"
		and StringName(str(plan.get("action_mode", ""))) in [&"place", &"recall"]
		and typeof(plan.get("runtime_frame")) == TYPE_INT
		and int(plan["runtime_frame"]) == _last_runtime_frame
		and typeof(plan.get("commit_frame")) == TYPE_INT
		and int(plan["commit_frame"]) == _last_runtime_frame + _skill_parameter_int("windup_frames")
		and _valid_segment(plan.get("run_id"))
		and typeof(plan.get("run_revision")) == TYPE_INT
		and int(plan["run_revision"]) > 0
		and typeof(plan.get("owner_character_generation")) == TYPE_INT
		and int(plan["owner_character_generation"]) > 0
		and typeof(plan.get("position")) == TYPE_VECTOR2
		and _finite_vector(plan["position"] as Vector2)
		and _finite_number(plan.get("energy_cost"))
		and float(plan["energy_cost"]) == _skill_energy_cost()
		and typeof(plan.get("anchor_generation")) == TYPE_INT
		and int(plan["anchor_generation"]) == _anchor_generation
		and typeof(plan.get("strategy_revision")) == TYPE_INT
		and int(plan["strategy_revision"]) == _revision
		and (
			(StringName(plan["action_mode"]) == &"place" and not _anchor_active)
			or (StringName(plan["action_mode"]) == &"recall" and _anchor_active)
		)
	)


func _normalized_mastery(value: Dictionary) -> Dictionary:
	if (
		not _configured
		or typeof(value.get("generation")) != TYPE_INT
		or int(value["generation"]) <= 0
		or typeof(value.get("action_token")) != TYPE_INT
		or int(value["action_token"]) <= 0
		or not _valid_segment(value.get("weapon_id"))
		or not _valid_segment(value.get("mastery_family"))
		or StringName(value["weapon_id"]) != StringName(value["mastery_family"])
		or not value.get("context") is Dictionary
	):
		return {}
	var context := value["context"] as Dictionary
	if not _valid_live_context(context) or not _context_matches_run(context):
		return {}
	var maximum_hp: Variant = context.get("maximum_hp", 0.0)
	if not _finite_number(maximum_hp) or float(maximum_hp) <= 0.0:
		return {}
	return {
		"weapon_id": StringName(value["weapon_id"]),
		"mastery_family": StringName(value["mastery_family"]),
		"generation": int(value["generation"]),
		"action_token": int(value["action_token"]),
		"context": context.duplicate(true),
	}


func _valid_time_context(value: Dictionary) -> bool:
	return (
		_valid_live_context(value)
		and StringName(str(value.get("ability_id", ""))) in [&"stop", &"rewind", &"accelerate", &"rift"]
		and typeof(value.get("token")) == TYPE_INT
		and int(value["token"]) > 0
		and typeof(value.get("generation")) == TYPE_INT
		and int(value["generation"]) > 0
	)


func _valid_live_context(value: Dictionary) -> bool:
	return (
		typeof(value.get("runtime_frame")) == TYPE_INT
		and int(value["runtime_frame"]) == _last_runtime_frame
		and _valid_segment(value.get("run_id"))
		and typeof(value.get("run_revision")) == TYPE_INT
		and int(value["run_revision"]) > 0
		and typeof(value.get("owner_character_generation", _owner_character_generation)) == TYPE_INT
		and int(value.get("owner_character_generation", _owner_character_generation)) > 0
		and (
			_run_id == &""
			or (
				StringName(value["run_id"]) == _run_id
				and int(value["run_revision"]) == _run_revision
			)
		)
	)


func _valid_room_context(value: Dictionary) -> bool:
	return (
		_valid_segment(value.get("run_id"))
		and typeof(value.get("run_revision")) == TYPE_INT
		and int(value["run_revision"]) > 0
		and _valid_segment(value.get("room_id"))
		and typeof(value.get("room_revision")) == TYPE_INT
		and int(value["room_revision"]) > 0
	)


func _valid_skill_intent(intent: Dictionary, edge: StringName) -> bool:
	return (
		StringName(str(intent.get("id", ""))) == &"character_skill"
		and StringName(str(intent.get("edge", ""))) == edge
		and typeof(intent.get("held_frames")) == TYPE_INT
		and int(intent["held_frames"]) >= 0
	)


func _bind_run(run_id: StringName, run_revision: int, owner_generation: int) -> bool:
	if run_id == &"" or run_revision <= 0 or owner_generation <= 0:
		return false
	if _run_id == &"":
		_run_id = run_id
		_run_revision = run_revision
		_owner_character_generation = owner_generation
		return true
	return (
		run_id == _run_id
		and run_revision == _run_revision
		and owner_generation == _owner_character_generation
	)


func _context_matches_run(value: Dictionary) -> bool:
	return (
		_run_id != &""
		and _valid_segment(value.get("run_id"))
		and StringName(value["run_id"]) == _run_id
		and typeof(value.get("run_revision")) == TYPE_INT
		and int(value["run_revision"]) == _run_revision
	)


func _grant_mark() -> bool:
	var resource := _profile_snapshot.get("resource", {}) as Dictionary
	var maximum := int(resource.get("maximum", 0))
	if int(_resource_value) >= maximum:
		return false
	_resource_value = mini(int(_resource_value) + 1, maximum)
	return true


func _forgiveness_for_weapon(weapon_id: StringName) -> Dictionary:
	var value := {
		"weapon_id": weapon_id,
		"expires_after_frames": _passive_parameter_int("forgiveness_expiry_frames"),
	}
	match weapon_id:
		&"sword":
			value["recovery_reduction_frames"] = _passive_parameter_int("sword_recovery_reduction_frames")
			value["minimum_recovery_frames"] = 1
		&"bow":
			value["full_charge_frames"] = _passive_parameter_int("bow_full_charge_frames")
		&"gun":
			value["perfect_start_frame"] = _passive_parameter_int("gun_reload_perfect_start")
			value["perfect_end_frame"] = _passive_parameter_int("gun_reload_perfect_end")
		&"staff":
			value["window_extension_frames"] = _passive_parameter_int("staff_window_extension_frames")
			value["window_cap_frames"] = _passive_parameter_int("staff_window_cap_frames")
		&"gauntlets":
			value["combo_extension_frames"] = _passive_parameter_int("gauntlets_combo_extension_frames")
			value["combo_cap_frames"] = _passive_parameter_int("gauntlets_combo_cap_frames")
	return value


func _resource_event(frame: int, token: int, reason: StringName) -> Dictionary:
	var resource := _profile_snapshot.get("resource", {}) as Dictionary
	return _event(&"character_resource_changed", frame, token, {
		"resource_id": &"path_marks",
		"current": int(_resource_value),
		"maximum": int(resource.get("maximum", 5)),
		"reason": reason,
	})


func _cooldown_event(frame: int, duration: int, reason: StringName) -> Dictionary:
	return _event(&"character_cooldown_started", frame, 0, {
		"skill_id": &"waypoint_recall",
		"duration_frames": duration,
		"ready_frame": frame + duration,
		"reason": reason,
	})


func _event(event_id: StringName, frame: int, token: int, context: Dictionary) -> Dictionary:
	return CharacterPayloadExecutionScript.event(
		event_id,
		CHARACTER_ID,
		maxi(frame, 0),
		maxi(token, 0),
		maxi(_owner_character_generation, 1),
		context
	)


func _passive_parameter_int(key: String) -> int:
	return int((((_profile_snapshot.get("passive", {}) as Dictionary).get(
		"parameters", {}
	) as Dictionary).get(key, 0)))


func _passive_parameter_float(key: String) -> float:
	return float((((_profile_snapshot.get("passive", {}) as Dictionary).get(
		"parameters", {}
	) as Dictionary).get(key, 0.0)))


func _skill_parameter_int(key: String) -> int:
	return int((((_profile_snapshot.get("character_skill", {}) as Dictionary).get(
		"parameters", {}
	) as Dictionary).get(key, 0)))


func _skill_parameter_float(key: String) -> float:
	return float((((_profile_snapshot.get("character_skill", {}) as Dictionary).get(
		"parameters", {}
	) as Dictionary).get(key, 0.0)))


func _skill_energy_cost() -> float:
	return float((_profile_snapshot.get("character_skill", {}) as Dictionary).get("energy_cost", 0.0))


func _skill_cooldown_frames() -> int:
	return int((_profile_snapshot.get("character_skill", {}) as Dictionary).get("cooldown_frames", 0))


func _clear_anchor() -> void:
	_anchor_active = false
	_anchor_position = Vector2.ZERO
	_anchor_expires_frame = -1
	_anchor_damage_total = 0.0
	_anchor_run_id = &""


func _reset_strategy_state() -> void:
	_run_id = &""
	_run_revision = 0
	_owner_character_generation = 1
	_path_progress = 0
	_room_id = &""
	_room_revision = 0
	_first_mark_claimed = false
	_cleared_room_claims.clear()
	_mastery_claims.clear()
	_wayfarer_until_frame = -1
	_wayfarer_source_token = 0
	_authorized_rift_generation = 0
	_rift_progress_claims.clear()
	_forgiveness_descriptor.clear()
	_forgiveness_expires_frame = -1
	_skill_cooldown_until_frame = -1
	_skill_action.clear()
	_anchor_active = false
	_anchor_generation = 0
	_anchor_position = Vector2.ZERO
	_anchor_expires_frame = -1
	_anchor_damage_total = 0.0
	_anchor_run_id = &""
	_banked_room_completions = 0


func _valid_next_frame(context: Dictionary) -> bool:
	return (
		_configured
		and typeof(context.get("runtime_frame")) == TYPE_INT
		and int(context["runtime_frame"]) >= 0
		and int(context["runtime_frame"]) > _last_runtime_frame
	)


func _validated_snapshot(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, STRATEGY_SNAPSHOT_FIELDS):
		return {}
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != STRATEGY_SNAPSHOT_SCHEMA_VERSION
		or str(value["runtime_kind"]) != "wanderer"
		or typeof(value["configured"]) != TYPE_BOOL
		or bool(value["configured"]) != _configured
		or typeof(value["last_runtime_frame"]) != TYPE_INT
		or int(value["last_runtime_frame"]) < -1
		or typeof(value["revision"]) != TYPE_INT
		or int(value["revision"]) < 0
		or typeof(value["resource_value"]) != TYPE_INT
		or not _resource_value_in_profile_range(int(value["resource_value"]))
		or typeof(value["run_id"]) != TYPE_STRING
		or typeof(value["run_revision"]) != TYPE_INT
		or int(value["run_revision"]) < 0
		or typeof(value["owner_character_generation"]) != TYPE_INT
		or int(value["owner_character_generation"]) <= 0
		or typeof(value["path_progress"]) != TYPE_INT
		or int(value["path_progress"]) < 0
		or int(value["path_progress"]) >= _passive_parameter_int("progress_threshold")
		or typeof(value["room_id"]) != TYPE_STRING
		or typeof(value["room_revision"]) != TYPE_INT
		or int(value["room_revision"]) < 0
		or typeof(value["first_mark_claimed"]) != TYPE_BOOL
		or not _valid_sorted_strings(value["cleared_room_claims"])
		or not _valid_sorted_strings(value["mastery_claims"])
		or typeof(value["wayfarer_until_frame"]) != TYPE_INT
		or int(value["wayfarer_until_frame"]) < -1
		or typeof(value["wayfarer_source_token"]) != TYPE_INT
		or int(value["wayfarer_source_token"]) < 0
		or typeof(value["authorized_rift_generation"]) != TYPE_INT
		or int(value["authorized_rift_generation"]) < 0
		or not _valid_sorted_positive_ints(value["rift_progress_claims"])
		or not value["forgiveness_descriptor"] is Dictionary
		or not ReplaySafeValueScript.is_supported(value["forgiveness_descriptor"])
		or typeof(value["forgiveness_expires_frame"]) != TYPE_INT
		or int(value["forgiveness_expires_frame"]) < -1
		or typeof(value["skill_cooldown_until_frame"]) != TYPE_INT
		or int(value["skill_cooldown_until_frame"]) < -1
		or not value["skill_action"] is Dictionary
		or not ReplaySafeValueScript.is_supported(value["skill_action"])
		or typeof(value["anchor_active"]) != TYPE_BOOL
		or typeof(value["anchor_generation"]) != TYPE_INT
		or int(value["anchor_generation"]) < 0
		or typeof(value["anchor_position"]) != TYPE_VECTOR2
		or not _finite_vector(value["anchor_position"] as Vector2)
		or typeof(value["anchor_expires_frame"]) != TYPE_INT
		or int(value["anchor_expires_frame"]) < -1
		or not _finite_number(value["anchor_damage_total"])
		or float(value["anchor_damage_total"]) < 0.0
		or typeof(value["anchor_run_id"]) != TYPE_STRING
		or typeof(value["banked_room_completions"]) != TYPE_INT
		or int(value["banked_room_completions"]) < 0
	):
		return {}
	if (
		(str(value["run_id"]).is_empty()) != (int(value["run_revision"]) == 0)
		or (str(value["room_id"]).is_empty()) != (int(value["room_revision"]) == 0)
		or (bool(value["anchor_active"]) and (
			int(value["anchor_generation"]) <= 0
			or int(value["anchor_expires_frame"]) < 0
			or str(value["anchor_run_id"]).is_empty()
		))
		or (not bool(value["anchor_active"]) and (
			int(value["anchor_expires_frame"]) != -1
			or float(value["anchor_damage_total"]) != 0.0
			or not str(value["anchor_run_id"]).is_empty()
		))
		or ((value["forgiveness_descriptor"] as Dictionary).is_empty()) != (int(value["forgiveness_expires_frame"]) == -1)
	):
		return {}
	return value.duplicate(true)


func _install_snapshot(value: Dictionary) -> void:
	_last_runtime_frame = int(value["last_runtime_frame"])
	_revision = int(value["revision"])
	_resource_value = int(value["resource_value"])
	_run_id = StringName(value["run_id"])
	_run_revision = int(value["run_revision"])
	_owner_character_generation = int(value["owner_character_generation"])
	_path_progress = int(value["path_progress"])
	_room_id = StringName(value["room_id"])
	_room_revision = int(value["room_revision"])
	_first_mark_claimed = bool(value["first_mark_claimed"])
	_cleared_room_claims.assign(value["cleared_room_claims"])
	_mastery_claims.assign(value["mastery_claims"])
	_wayfarer_until_frame = int(value["wayfarer_until_frame"])
	_wayfarer_source_token = int(value["wayfarer_source_token"])
	_authorized_rift_generation = int(value["authorized_rift_generation"])
	_rift_progress_claims.assign(value["rift_progress_claims"])
	_forgiveness_descriptor = (value["forgiveness_descriptor"] as Dictionary).duplicate(true)
	_forgiveness_expires_frame = int(value["forgiveness_expires_frame"])
	_skill_cooldown_until_frame = int(value["skill_cooldown_until_frame"])
	_skill_action = (value["skill_action"] as Dictionary).duplicate(true)
	_anchor_active = bool(value["anchor_active"])
	_anchor_generation = int(value["anchor_generation"])
	_anchor_position = value["anchor_position"] as Vector2
	_anchor_expires_frame = int(value["anchor_expires_frame"])
	_anchor_damage_total = float(value["anchor_damage_total"])
	_anchor_run_id = StringName(value["anchor_run_id"])
	_banked_room_completions = int(value["banked_room_completions"])


static func _valid_sorted_strings(value: Variant) -> bool:
	if not value is Array:
		return false
	var normalized: Array[String] = []
	for entry: Variant in value as Array:
		if typeof(entry) != TYPE_STRING or str(entry).is_empty() or normalized.has(str(entry)):
			return false
		normalized.append(str(entry))
	var sorted := normalized.duplicate()
	sorted.sort()
	return normalized == sorted


static func _valid_sorted_positive_ints(value: Variant) -> bool:
	if not value is Array:
		return false
	var normalized: Array[int] = []
	for entry: Variant in value as Array:
		if typeof(entry) != TYPE_INT or int(entry) <= 0 or normalized.has(int(entry)):
			return false
		normalized.append(int(entry))
	var sorted := normalized.duplicate()
	sorted.sort()
	return normalized == sorted


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


static func _valid_segment(value: Variant) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var text := str(value)
	return not text.is_empty() and text == text.strip_edges() and not text.contains(":")
