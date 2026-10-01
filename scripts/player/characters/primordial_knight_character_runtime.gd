class_name PrimordialKnightCharacterRuntime
extends "res://scripts/player/characters/character_runtime.gd"

const CharacterPayloadExecutionScript := preload(
	"res://scripts/combat/character_payload_execution.gd"
)
const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")

const CHARACTER_ID := &"primordial_knight"
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
	"mastery_claims",
	"commitment_claims",
	"instability_claims",
	"skill_cooldown_until_frame",
	"skill_action",
	"armor_windows",
	"pending_echoes",
	"authorized_rift_generation",
	"authorized_rift_center",
	"rift_anchor_claims",
	"next_payload_generation",
]

var _run_id: StringName = &""
var _run_revision: int = 0
var _owner_character_generation: int = 1
var _mastery_claims: Array[String] = []
var _commitment_claims: Array[String] = []
var _instability_claims: Array[String] = []
var _skill_cooldown_until_frame: int = -1
var _skill_action: Dictionary = {}
var _armor_windows: Array[Dictionary] = []
var _pending_echoes: Array[Dictionary] = []
var _authorized_rift_generation: int = 0
var _authorized_rift_center: Vector2 = Vector2.ZERO
var _rift_anchor_claims: Array[int] = []
var _next_payload_generation: int = 1


func _init() -> void:
	_runtime_kind = &"primordial_knight"


func configure(owner: Node, profile: Variant, talents: PackedStringArray) -> bool:
	if profile == null or not profile is RefCounted or not profile.has_method("snapshot"):
		return false
	var profile_value: Variant = profile.call("snapshot")
	if (
		not profile_value is Dictionary
		or str((profile_value as Dictionary).get("character_id", "")) != str(CHARACTER_ID)
		or str((profile_value as Dictionary).get("runtime_kind", "")) != "primordial_knight"
		or str(((profile_value as Dictionary).get("character_skill", {}) as Dictionary).get("handler_id", "")) != "realm_cleave"
	):
		return false
	if not super.configure(owner, profile, talents):
		return false
	_reset_strategy_state()
	_revision = 0
	return true


func reset_runtime_state(reason: StringName) -> void:
	if not _configured:
		return
	super.reset_runtime_state(reason)
	_reset_strategy_state()


func advance_frame(context: Dictionary) -> Array[Dictionary]:
	if not _valid_next_frame(context):
		return []
	var runtime_frame := int(context["runtime_frame"])
	super.advance_frame(context)
	var events: Array[Dictionary] = []
	_prune_armor_windows(runtime_frame)

	if not _skill_action.is_empty():
		var commit_frame := int(_skill_action.get("commit_frame", -1))
		if not bool(_skill_action.get("committed", false)) and runtime_frame >= commit_frame:
			events.append_array(_commit_realm_cleave(commit_frame))
		if (
			not _skill_action.is_empty()
			and bool(_skill_action.get("committed", false))
			and runtime_frame >= int(_skill_action.get("recovery_until_frame", -1))
		):
			var token := int(_skill_action.get("token", 0))
			var completion_frame := int(_skill_action.get("recovery_until_frame", runtime_frame))
			_skill_action.clear()
			_revision += 1
			events.append(_event(&"character_skill_completed", completion_frame, token, {
				"skill_id": &"realm_cleave",
			}))

	var remaining: Array[Dictionary] = []
	for pending: Dictionary in _pending_echoes:
		if runtime_frame >= int(pending.get("release_frame", -1)):
			events.append(_event(&"world_payload_requested", int(pending["release_frame"]), int(pending["source_token"]), {
				"descriptor": (pending["descriptor"] as Dictionary).duplicate(true),
			}))
			events.append(_event(&"planar_echo_released", int(pending["release_frame"]), int(pending["source_token"]), {
				"weapon_id": StringName(pending["weapon_id"]),
				"action_id": StringName(pending["action_id"]),
			}))
			_revision += 1
		else:
			remaining.append(pending.duplicate(true))
	_pending_echoes = remaining
	return events


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
	var before := int(_resource_value)
	_resource_value = mini(before + 1, _resource_maximum())
	_revision += 1
	if int(_resource_value) == before:
		return []
	return [_resource_event(_last_runtime_frame, int(normalized["action_token"]), &"weapon_mastery")]


func on_weapon_action_committed(action_context: Dictionary) -> Array[Dictionary]:
	if (
		int(_resource_value) < _reservation_cost()
		or not _valid_live_context(action_context)
		or not _context_matches_run(action_context)
		or bool(action_context.get("is_echo", false))
		or bool(action_context.get("recursive_echo", false))
		or typeof(action_context.get("action_token")) != TYPE_INT
		or int(action_context["action_token"]) <= 0
		or typeof(action_context.get("generation")) != TYPE_INT
		or int(action_context["generation"]) <= 0
		or not _valid_segment(action_context.get("weapon_id"))
		or not _valid_segment(action_context.get("action_id"))
		or not action_context.get("plan") is Dictionary
		or typeof(action_context.get("position")) != TYPE_VECTOR2
		or not _finite_vector(action_context["position"] as Vector2)
	):
		return []
	var weapon_id := StringName(action_context["weapon_id"])
	var action_id := StringName(action_context["action_id"])
	var commitment_claim := "%d:%d" % [
		int(action_context["generation"]),
		int(action_context["action_token"]),
	]
	if _commitment_claims.has(commitment_claim):
		return []
	if not _is_commitment_action(weapon_id, action_id, action_context):
		return []
	var plan := action_context["plan"] as Dictionary
	if StringName(str(plan.get("weapon_id", ""))) != weapon_id or StringName(str(plan.get("action_id", ""))) != action_id:
		return []
	var approved_payloads := _approved_payloads(plan)
	if approved_payloads.is_empty():
		return []
	var durations := _phase_durations(plan)
	if durations.is_empty():
		return []
	var release_frame := _last_runtime_frame + int(durations["windup"]) + int(durations["active"]) + int(durations["recovery"])
	var armor_until_frame := _last_runtime_frame + int(durations["windup"])
	if _selected_talent_ids.has("resonant_plate"):
		armor_until_frame = _last_runtime_frame + int(durations["windup"]) + int(durations["active"]) + 12
	var origin := action_context["position"] as Vector2
	var area_scale := 1.0
	var rift_generation := int(action_context.get("rift_generation", 0))
	if (
		rift_generation > 0
		and rift_generation == _authorized_rift_generation
		and typeof(action_context.get("rift_center")) == TYPE_VECTOR2
		and _finite_vector(action_context["rift_center"] as Vector2)
		and not _rift_anchor_claims.has(rift_generation)
	):
		origin = action_context["rift_center"] as Vector2
		area_scale = 1.25
	var descriptor := _planar_echo_descriptor(
		int(action_context["action_token"]),
		origin,
		weapon_id,
		action_id,
		approved_payloads,
		area_scale,
		rift_generation if area_scale > 1.0 else 0
	)
	if descriptor.is_empty():
		return []

	_resource_value = int(_resource_value) - _reservation_cost()
	_armor_windows.append({
		"source_kind": &"resonance_commitment",
		"source_token": int(action_context["action_token"]),
		"active_from_frame": _last_runtime_frame,
		"active_through_frame": armor_until_frame - 1,
		"damage_reduction": _passive_parameter_float("armor_reduction"),
	})
	_pending_echoes.append({
		"source_token": int(action_context["action_token"]),
		"weapon_id": weapon_id,
		"action_id": action_id,
		"release_frame": release_frame,
		"descriptor": descriptor,
	})
	_commitment_claims.append(commitment_claim)
	_commitment_claims.sort()
	if area_scale > 1.0:
		_rift_anchor_claims.append(rift_generation)
		_rift_anchor_claims.sort()
	_revision += 1
	return [
		_resource_event(_last_runtime_frame, int(action_context["action_token"]), &"commitment_reserved"),
		_event(&"resonance_armor_installed", _last_runtime_frame, int(action_context["action_token"]), {
			"active_through_frame": armor_until_frame - 1,
			"damage_reduction": _passive_parameter_float("armor_reduction"),
		}),
		_event(&"planar_echo_scheduled", _last_runtime_frame, int(action_context["action_token"]), {
			"release_frame": release_frame,
			"payload_id": descriptor["payload_id"],
			"world_owned": true,
		}),
	]


func before_damage(damage_context: Dictionary) -> Dictionary:
	if (
		not _valid_live_context(damage_context)
		or not _context_matches_run(damage_context)
		or not _positive_finite_number(damage_context.get("original_amount"))
		or not damage_context.get("tags") is Array
	):
		return {"ok": false, "decision": {}}
	var tags: Array[String] = []
	for tag_value: Variant in damage_context["tags"] as Array:
		if typeof(tag_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return {"ok": false, "decision": {}}
		tags.append(str(tag_value))
	var bypass := StringName(str(damage_context.get("source_kind", ""))) != &"enemy"
	for bypass_tag: String in ["true_damage", "self_cost", "corruption", "terminal", "unguardable"]:
		bypass = bypass or tags.has(bypass_tag)
	var reduction := 0.0
	var source_kind := &"none"
	if not bypass:
		for window: Dictionary in _armor_windows:
			if _last_runtime_frame >= int(window["active_from_frame"]) and _last_runtime_frame <= int(window["active_through_frame"]):
				var candidate := float(window["damage_reduction"])
				if candidate > reduction:
					reduction = candidate
					source_kind = StringName(window["source_kind"])
	var decision := {
		"decision_id": &"primordial_knight_armor",
		"character_id": CHARACTER_ID,
		"runtime_frame": _last_runtime_frame,
		"character_revision": _revision,
		"armor_source": source_kind,
		"bypassed": bypass,
		"damage_reduction": reduction,
		"combined_multiplier": 1.0 - reduction,
		"run_id": _run_id,
		"run_revision": _run_revision,
	}
	return {"ok": true, "decision": decision}


func after_damage(damage_context: Dictionary) -> Array[Dictionary]:
	if (
		_skill_action.is_empty()
		or not bool(_skill_action.get("committed", false))
		or int(_skill_action.get("resonance_stacks", 0)) != _resource_maximum()
		or not _context_matches_run(damage_context)
		or typeof(damage_context.get("runtime_frame")) != TYPE_INT
		or int(damage_context["runtime_frame"]) != _last_runtime_frame
		or typeof(damage_context.get("applied")) != TYPE_BOOL
		or not bool(damage_context["applied"])
		or bool(damage_context.get("prevented", false))
		or StringName(str(damage_context.get("source_kind", ""))) != &"character_payload"
		or StringName(str(damage_context.get("payload_family", ""))) != &"realm_cleave"
		or int(damage_context.get("source_token", 0)) != int(_skill_action.get("token", -1))
		or typeof(damage_context.get("target_id")) != TYPE_INT
		or int(damage_context["target_id"]) <= 0
		or not _positive_finite_number(damage_context.get("finalized_damage"))
	):
		return []
	var token := int(_skill_action["token"])
	var target_id := int(damage_context["target_id"])
	var claim_key := "%d:%d" % [token, target_id]
	if _instability_claims.has(claim_key):
		return []
	_instability_claims.append(claim_key)
	_instability_claims.sort()
	_revision += 1
	return [_event(&"planar_instability_requested", _last_runtime_frame, token, {
		"target_id": target_id,
		"claim_key": claim_key,
		"duration_frames": _instability_frames(),
		"approved_damage_bonus": _skill_parameter_float("instability_bonus"),
		"non_recursive": true,
	})]


func plan_character_skill(intent: Dictionary, context: Dictionary) -> Dictionary:
	if (
		not _configured
		or not _skill_action.is_empty()
		or not _valid_skill_intent(intent)
		or not _valid_live_context(context)
		or not bool(context.get("alive", false))
		or not _positive_finite_number(context.get("attack"))
		or not _finite_number(context.get("time_energy"))
		or float(context["time_energy"]) < _skill_energy_cost()
		or typeof(context.get("position")) != TYPE_VECTOR2
		or not _finite_vector(context["position"] as Vector2)
	):
		return {"ok": false, "code": "invalid_context"}
	var runtime_frame := int(context["runtime_frame"])
	if _skill_cooldown_until_frame >= 0 and runtime_frame < _skill_cooldown_until_frame:
		return {"ok": false, "code": "cooldown_active"}
	return {
		"ok": true,
		"code": "planned",
		"plan": {
			"skill_id": &"realm_cleave",
			"runtime_frame": runtime_frame,
			"commit_frame": runtime_frame + _skill_parameter_int("windup_frames"),
			"run_id": StringName(context["run_id"]),
			"run_revision": int(context["run_revision"]),
			"owner_character_generation": int(context.get("owner_character_generation", _owner_character_generation)),
			"position": context["position"],
			"attack": float(context["attack"]),
			"energy_cost": _skill_energy_cost(),
			"resonance_stacks": int(_resource_value),
			"strategy_revision": _revision,
		},
	}


func commit_character_skill(plan: Dictionary, token: int) -> Dictionary:
	if token <= 0 or not _valid_skill_plan(plan):
		return {"ok": false, "code": "invalid_plan"}
	if not _bind_run(StringName(plan["run_id"]), int(plan["run_revision"]), int(plan["owner_character_generation"])):
		return {"ok": false, "code": "stale_run"}
	_skill_action = plan.duplicate(true)
	_skill_action["token"] = token
	_skill_action["committed"] = false
	_skill_action["recovery_until_frame"] = -1
	var armor_through_frame := int(plan["commit_frame"]) - 1
	if _armor_recovery_extension_frames() > 0:
		armor_through_frame = (
			int(plan["commit_frame"])
			+ _skill_parameter_int("active_frames")
			+ _armor_recovery_extension_frames()
			- 1
		)
	_armor_windows.append({
		"source_kind": &"realm_cleave",
		"source_token": token,
		"active_from_frame": int(plan["runtime_frame"]),
		"active_through_frame": armor_through_frame,
		"damage_reduction": _skill_parameter_float("armor_reduction"),
	})
	_revision += 1
	return {
		"ok": true,
		"code": "accepted",
		"events": [_event(&"realm_cleave_armor_installed", int(plan["runtime_frame"]), token, {
			"active_through_frame": armor_through_frame,
			"damage_reduction": _skill_parameter_float("armor_reduction"),
		})],
		"context": {"skill_id": &"realm_cleave", "commit_frame": int(plan["commit_frame"])},
	}


func character_action_cancellation_state() -> Dictionary:
	return {
		"active": not _skill_action.is_empty(),
		"committed": bool(_skill_action.get("committed", false)),
	}


func cancel_uncommitted_action(_reason: StringName) -> Dictionary:
	if _skill_action.is_empty() or bool(_skill_action.get("committed", false)):
		return {"ok": true, "cancelled": false}
	var token := int(_skill_action.get("token", 0))
	_skill_action.clear()
	_remove_armor_source(&"realm_cleave", token)
	_revision += 1
	return {"ok": true, "cancelled": true}


func before_time_skill(time_context: Dictionary) -> Dictionary:
	if not _valid_time_context(time_context):
		return {"ok": false, "decision": {}}
	var ability_id := StringName(time_context["ability_id"])
	var parameters := {
		"ability_id": ability_id,
		"strategy_revision": _revision,
		"run_id": StringName(time_context["run_id"]),
		"run_revision": int(time_context["run_revision"]),
	}
	for key: String in ["stop_until_frame", "shorten_echo_frames", "rift_generation", "rift_center"]:
		if time_context.has(key):
			parameters[key] = time_context[key]
	var decision := CharacterPayloadExecutionScript.decision(
		&"primordial_knight_time_conversion",
		CHARACTER_ID,
		int(time_context["runtime_frame"]),
		int(time_context["token"]),
		int(time_context["generation"]),
		parameters
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
		StringName(str(decision.get("decision_id", ""))) != &"primordial_knight_time_conversion"
		or int(decision.get("runtime_frame", -1)) != int(time_context["runtime_frame"])
		or int(decision.get("token", -1)) != int(time_context["token"])
		or int(decision.get("generation", -1)) != int(time_context["generation"])
		or int(parameters.get("strategy_revision", -1)) != _revision
		or StringName(str(parameters.get("ability_id", ""))) != StringName(time_context["ability_id"])
		or not _bind_run(StringName(time_context["run_id"]), int(time_context["run_revision"]), int(time_context.get("owner_character_generation", _owner_character_generation)))
	):
		return []
	var ability_id := StringName(time_context["ability_id"])
	if ability_id == &"stop":
		var stop_end := int(time_context.get("stop_until_frame", parameters.get("stop_until_frame", -1)))
		if stop_end >= _last_runtime_frame:
			for pending: Dictionary in _pending_echoes:
				pending["release_frame"] = stop_end
	elif ability_id == &"accelerate":
		var shorten := maxi(1, int(time_context.get("shorten_echo_frames", parameters.get("shorten_echo_frames", 1))))
		for pending: Dictionary in _pending_echoes:
			pending["release_frame"] = maxi(_last_runtime_frame + 1, int(pending["release_frame"]) - shorten)
	elif ability_id == &"rift":
		var generation_value: Variant = time_context.get("rift_generation", parameters.get("rift_generation", 0))
		var center_value: Variant = time_context.get("rift_center", parameters.get("rift_center"))
		if typeof(generation_value) != TYPE_INT or int(generation_value) <= 0 or typeof(center_value) != TYPE_VECTOR2 or not _finite_vector(center_value as Vector2):
			return []
		_authorized_rift_generation = int(generation_value)
		_authorized_rift_center = center_value as Vector2
	_revision += 1
	return [_event(&"primordial_time_conversion_committed", _last_runtime_frame, int(time_context["token"]), {
		"ability_id": ability_id,
		"preserves_world_echo": ability_id == &"rewind",
		"pending_echo_count": _pending_echoes.size(),
		"authorized_rift_generation": _authorized_rift_generation,
	})]


func on_room_started(room_context: Dictionary) -> Array[Dictionary]:
	if not _valid_room_context(room_context):
		return []
	var was_unbound := _run_id == &""
	if not _bind_run(StringName(room_context["run_id"]), int(room_context["run_revision"]), int(room_context.get("owner_character_generation", 1))):
		return []
	if not was_unbound:
		return []
	_revision += 1
	return [_event(&"primordial_room_started", maxi(_last_runtime_frame, 0), 0, {
		"room_id": StringName(room_context["room_id"]),
		"room_revision": int(room_context["room_revision"]),
	})]


func on_run_terminal(run_context: Dictionary) -> Dictionary:
	if not _context_matches_run(run_context):
		return {"ok": false, "summary": {}}
	return {"ok": true, "summary": {
		"resonance": int(_resource_value),
		"pending_world_echoes": _pending_echoes.size(),
	}}


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
		"mastery_claims": _mastery_claims.duplicate(),
		"commitment_claims": _commitment_claims.duplicate(),
		"instability_claims": _instability_claims.duplicate(),
		"skill_cooldown_until_frame": _skill_cooldown_until_frame,
		"skill_action": _skill_action.duplicate(true),
		"armor_windows": _armor_windows.duplicate(true),
		"pending_echoes": _pending_echoes.duplicate(true),
		"authorized_rift_generation": _authorized_rift_generation,
		"authorized_rift_center": _authorized_rift_center,
		"rift_anchor_claims": _rift_anchor_claims.duplicate(),
		"next_payload_generation": _next_payload_generation,
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
	# Rewind deliberately validates but does not install: consumed Resonance and
	# already committed world-owned echo descriptors remain authoritative.
	return not _validated_snapshot(value).is_empty()


func presentation_snapshot() -> Dictionary:
	return {
		"runtime_kind": str(_runtime_kind),
		"resource_value": int(_resource_value),
		"armor_active": _active_armor_reduction(_last_runtime_frame) > 0.0,
		"armor_reduction": _active_armor_reduction(_last_runtime_frame),
		"armor_recovery_extension_frames": _armor_recovery_extension_frames(),
		"pending_echo_count": _pending_echoes.size(),
		"echo_multiplier": _echo_multiplier(),
		"instability_frames": _instability_frames(),
		"skill_cooldown_until_frame": _skill_cooldown_until_frame,
	}


func _commit_realm_cleave(commit_frame: int) -> Array[Dictionary]:
	var token := int(_skill_action.get("token", 0))
	var stacks := int(_skill_action.get("resonance_stacks", 0))
	if stacks < 0 or stacks > int(_resource_value):
		_remove_armor_source(&"realm_cleave", token)
		_skill_action.clear()
		_revision += 1
		return [_event(&"realm_cleave_failed", commit_frame, token, {"reason": &"stale_resonance"})]
	var damage_multiplier := _skill_parameter_float("base_multiplier") + _skill_parameter_float("stack_multiplier") * float(stacks)
	var parameters := {
		"damage": float(_skill_action["attack"]) * damage_multiplier,
		"damage_multiplier": damage_multiplier,
		"damage_type": &"physical",
		"consumed_resonance": stacks,
		"boss_control_conversion": &"poise_exposure",
		"instability_frames": _instability_frames() if stacks == _resource_maximum() else 0,
		"instability_bonus": _skill_parameter_float("instability_bonus") if stacks == _resource_maximum() else 0.0,
	}
	var descriptor := CharacterPayloadExecutionScript.world_payload_descriptor(
		_run_id,
		_owner_character_generation,
		&"realm_cleave",
		token,
		_next_payload_generation,
		&"realm_cleave_execution",
		Transform2D(0.0, _skill_action["position"] as Vector2),
		{
			"shape": &"circle",
			"center": _skill_action["position"],
			"radius_tiles": _skill_parameter_int("radius_tiles"),
			"radius": float(_skill_parameter_int("radius_tiles") * 32),
		},
		1,
		[],
		["character_owned", "no_mastery", "no_resource", "non_recursive", "world_owned"],
		parameters
	)
	if descriptor.is_empty():
		_remove_armor_source(&"realm_cleave", token)
		_skill_action.clear()
		_revision += 1
		return [_event(&"realm_cleave_failed", commit_frame, token, {"reason": &"payload_construction"})]
	_next_payload_generation += 1
	_resource_value = int(_resource_value) - stacks
	_skill_action["committed"] = true
	_skill_action["recovery_until_frame"] = commit_frame + _skill_parameter_int("active_frames") + _skill_parameter_int("recovery_frames")
	_skill_cooldown_until_frame = commit_frame + _skill_cooldown_frames()
	_revision += 1
	return [
		_resource_event(commit_frame, token, &"realm_cleave"),
		_event(&"time_energy_spend_requested", commit_frame, token, {
			"amount": float(_skill_action["energy_cost"]),
			"reason": &"realm_cleave",
		}),
		_event(&"world_payload_requested", commit_frame, token, {"descriptor": descriptor}),
		_cooldown_event(commit_frame, _skill_cooldown_frames(), &"realm_cleave_committed"),
		_event(&"character_skill_committed", commit_frame, token, {
			"skill_id": &"realm_cleave",
			"consumed_resonance": stacks,
		}),
	]


func _planar_echo_descriptor(
	source_token: int,
	origin: Vector2,
	weapon_id: StringName,
	action_id: StringName,
	approved_payloads: Array[Dictionary],
	area_scale: float,
	rift_generation: int
) -> Dictionary:
	var multiplier := _echo_multiplier()
	var descriptor := CharacterPayloadExecutionScript.world_payload_descriptor(
		_run_id,
		_owner_character_generation,
		&"planar_echo",
		source_token,
		_next_payload_generation,
		&"planar_echo_execution",
		Transform2D(0.0, origin),
		{
			"shape": &"approved_weapon_payload",
			"origin": origin,
			"area_scale": area_scale,
			"length_scale": area_scale,
		},
		1,
		[],
		["character_echo", "no_character_facts", "no_mastery", "no_resource", "non_recursive", "world_owned"],
		{
			"weapon_id": weapon_id,
			"action_id": action_id,
			"original_action_token": source_token,
			"damage_multiplier": multiplier,
			"approved_payloads": approved_payloads.duplicate(true),
			"rift_generation": rift_generation,
		}
	)
	if not descriptor.is_empty():
		_next_payload_generation += 1
	return descriptor


func _approved_payloads(plan: Dictionary) -> Array[Dictionary]:
	var source_value: Variant = plan.get("payload_descriptors", plan.get("approved_payload_descriptors", plan.get("payloads", [])))
	if not source_value is Array or (source_value as Array).is_empty():
		return []
	var result: Array[Dictionary] = []
	for payload_value: Variant in source_value as Array:
		if not payload_value is Dictionary:
			return []
		var payload := payload_value as Dictionary
		if not _valid_segment(payload.get("descriptor_id")) or not ReplaySafeValueScript.is_supported(payload):
			return []
		result.append(payload.duplicate(true))
	return result


func _phase_durations(plan: Dictionary) -> Dictionary:
	var phases_value: Variant = plan.get("phases")
	if not phases_value is Array:
		return {}
	var result := {"windup": 0, "active": 0, "recovery": 0}
	for phase_value: Variant in phases_value as Array:
		if not phase_value is Dictionary:
			return {}
		var phase := phase_value as Dictionary
		if typeof(phase.get("duration_frames")) != TYPE_INT or int(phase["duration_frames"]) <= 0:
			return {}
		match StringName(str(phase.get("phase", ""))):
			&"WINDUP": result["windup"] = int(result["windup"]) + int(phase["duration_frames"])
			&"ACTIVE": result["active"] = int(result["active"]) + int(phase["duration_frames"])
			&"RECOVERY": result["recovery"] = int(result["recovery"]) + int(phase["duration_frames"])
	if int(result["windup"]) <= 0 or int(result["active"]) <= 0 or int(result["recovery"]) <= 0:
		return {}
	return result


func _is_commitment_action(weapon_id: StringName, action_id: StringName, context: Dictionary) -> bool:
	var mastery := ((_profile_snapshot.get("weapon_mastery", {}) as Dictionary).get(str(weapon_id), {}) as Dictionary)
	if str(mastery.get("handler_id", "")) != "primordial_knight_mastery":
		return false
	var parameters := mastery.get("parameters", {}) as Dictionary
	if StringName(str(parameters.get("commitment_action", ""))) != action_id:
		return false
	if bool(parameters.get("requires_full_charge", false)):
		return bool(context.get("full_charge", false)) or str(context.get("charge_tier", "")) == "full"
	var minimum := int(parameters.get("minimum_hold_frames", 0))
	return typeof(context.get("held_frames")) == TYPE_INT and int(context["held_frames"]) >= minimum


func _normalized_mastery(value: Dictionary) -> Dictionary:
	if (
		typeof(value.get("generation")) != TYPE_INT
		or int(value["generation"]) <= 0
		or typeof(value.get("action_token")) != TYPE_INT
		or int(value["action_token"]) <= 0
		or not _valid_segment(value.get("weapon_id"))
		or StringName(value["weapon_id"]) != StringName(str(value.get("mastery_family", "")))
		or not value.get("context") is Dictionary
	):
		return {}
	var context := value["context"] as Dictionary
	if not _valid_live_context(context) or not _context_matches_run(context):
		return {}
	return {
		"generation": int(value["generation"]),
		"action_token": int(value["action_token"]),
		"mastery_family": StringName(value["mastery_family"]),
	}


func _valid_skill_plan(plan: Dictionary) -> bool:
	return (
		_configured
		and _skill_action.is_empty()
		and str(plan.get("skill_id", "")) == "realm_cleave"
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
		and _positive_finite_number(plan.get("attack"))
		and _finite_number(plan.get("energy_cost"))
		and float(plan["energy_cost"]) == _skill_energy_cost()
		and typeof(plan.get("resonance_stacks")) == TYPE_INT
		and int(plan["resonance_stacks"]) == int(_resource_value)
		and typeof(plan.get("strategy_revision")) == TYPE_INT
		and int(plan["strategy_revision"]) == _revision
	)


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
		and (_run_id == &"" or (StringName(value["run_id"]) == _run_id and int(value["run_revision"]) == _run_revision))
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


func _valid_skill_intent(intent: Dictionary) -> bool:
	return (
		StringName(str(intent.get("id", ""))) == &"character_skill"
		and StringName(str(intent.get("edge", ""))) == &"pressed"
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
	return run_id == _run_id and run_revision == _run_revision and owner_generation == _owner_character_generation


func _context_matches_run(value: Dictionary) -> bool:
	return (
		_run_id != &""
		and _valid_segment(value.get("run_id"))
		and StringName(value["run_id"]) == _run_id
		and typeof(value.get("run_revision")) == TYPE_INT
		and int(value["run_revision"]) == _run_revision
	)


func _prune_armor_windows(runtime_frame: int) -> void:
	var remaining: Array[Dictionary] = []
	for window: Dictionary in _armor_windows:
		if runtime_frame <= int(window.get("active_through_frame", -1)):
			remaining.append(window.duplicate(true))
	_armor_windows = remaining


func _remove_armor_source(source_kind: StringName, source_token: int) -> void:
	var remaining: Array[Dictionary] = []
	for window: Dictionary in _armor_windows:
		if StringName(window.get("source_kind", &"")) != source_kind or int(window.get("source_token", 0)) != source_token:
			remaining.append(window.duplicate(true))
	_armor_windows = remaining


func _active_armor_reduction(frame: int) -> float:
	var result := 0.0
	for window: Dictionary in _armor_windows:
		if frame >= int(window.get("active_from_frame", 0)) and frame <= int(window.get("active_through_frame", -1)):
			result = maxf(result, float(window.get("damage_reduction", 0.0)))
	return result


func _resource_event(frame: int, token: int, reason: StringName) -> Dictionary:
	return _event(&"character_resource_changed", frame, token, {
		"resource_id": &"resonance",
		"current": int(_resource_value),
		"maximum": _resource_maximum(),
		"reason": reason,
	})


func _cooldown_event(frame: int, duration: int, reason: StringName) -> Dictionary:
	return _event(&"character_cooldown_started", frame, 0, {
		"skill_id": &"realm_cleave",
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


func _resource_maximum() -> int:
	return int((_profile_snapshot.get("resource", {}) as Dictionary).get("maximum", 3))


func _reservation_cost() -> int:
	return _passive_parameter_int("reservation_cost")


func _echo_multiplier() -> float:
	return 1.0 if _selected_talent_ids.has("echo_forge") else _passive_parameter_float("echo_multiplier")


func _armor_recovery_extension_frames() -> int:
	return 12 if _selected_talent_ids.has("resonant_plate") else 0


func _instability_frames() -> int:
	return 600 if _selected_talent_ids.has("realm_collapse") else _skill_parameter_int("instability_frames")


func _passive_parameter_int(key: String) -> int:
	return int((((_profile_snapshot.get("passive", {}) as Dictionary).get("parameters", {}) as Dictionary).get(key, 0)))


func _passive_parameter_float(key: String) -> float:
	return float((((_profile_snapshot.get("passive", {}) as Dictionary).get("parameters", {}) as Dictionary).get(key, 0.0)))


func _skill_parameter_int(key: String) -> int:
	return int((((_profile_snapshot.get("character_skill", {}) as Dictionary).get("parameters", {}) as Dictionary).get(key, 0)))


func _skill_parameter_float(key: String) -> float:
	return float((((_profile_snapshot.get("character_skill", {}) as Dictionary).get("parameters", {}) as Dictionary).get(key, 0.0)))


func _skill_energy_cost() -> float:
	return float((_profile_snapshot.get("character_skill", {}) as Dictionary).get("energy_cost", 0.0))


func _skill_cooldown_frames() -> int:
	return int((_profile_snapshot.get("character_skill", {}) as Dictionary).get("cooldown_frames", 0))


func _reset_strategy_state() -> void:
	_run_id = &""
	_run_revision = 0
	_owner_character_generation = 1
	_mastery_claims.clear()
	_commitment_claims.clear()
	_instability_claims.clear()
	_skill_cooldown_until_frame = -1
	_skill_action.clear()
	_armor_windows.clear()
	_pending_echoes.clear()
	_authorized_rift_generation = 0
	_authorized_rift_center = Vector2.ZERO
	_rift_anchor_claims.clear()
	_next_payload_generation = 1


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
		or str(value["runtime_kind"]) != "primordial_knight"
		or typeof(value["configured"]) != TYPE_BOOL
		or bool(value["configured"]) != _configured
		or typeof(value["last_runtime_frame"]) != TYPE_INT
		or int(value["last_runtime_frame"]) < -1
		or typeof(value["revision"]) != TYPE_INT
		or int(value["revision"]) < 0
		or typeof(value["resource_value"]) != TYPE_INT
		or int(value["resource_value"]) < 0
		or int(value["resource_value"]) > _resource_maximum()
		or typeof(value["run_id"]) != TYPE_STRING
		or typeof(value["run_revision"]) != TYPE_INT
		or int(value["run_revision"]) < 0
		or typeof(value["owner_character_generation"]) != TYPE_INT
		or int(value["owner_character_generation"]) <= 0
		or not _valid_sorted_strings(value["mastery_claims"])
		or not _valid_sorted_strings(value["commitment_claims"])
		or not _valid_sorted_strings(value["instability_claims"])
		or typeof(value["skill_cooldown_until_frame"]) != TYPE_INT
		or int(value["skill_cooldown_until_frame"]) < -1
		or not value["skill_action"] is Dictionary
		or not value["armor_windows"] is Array
		or not value["pending_echoes"] is Array
		or not ReplaySafeValueScript.is_supported(value["skill_action"])
		or not _valid_armor_windows(value["armor_windows"])
		or not _valid_pending_echoes(value["pending_echoes"])
		or typeof(value["authorized_rift_generation"]) != TYPE_INT
		or int(value["authorized_rift_generation"]) < 0
		or typeof(value["authorized_rift_center"]) != TYPE_VECTOR2
		or not _finite_vector(value["authorized_rift_center"] as Vector2)
		or not _valid_sorted_positive_ints(value["rift_anchor_claims"])
		or typeof(value["next_payload_generation"]) != TYPE_INT
		or int(value["next_payload_generation"]) <= 0
	):
		return {}
	return value.duplicate(true)


func _valid_armor_windows(value: Variant) -> bool:
	if not value is Array:
		return false
	for window_value: Variant in value as Array:
		if not window_value is Dictionary:
			return false
		var window := window_value as Dictionary
		if (
			not _has_exact_fields(window, [
				"source_kind", "source_token", "active_from_frame",
				"active_through_frame", "damage_reduction",
			])
			or not _valid_segment(window.get("source_kind"))
			or typeof(window.get("source_token")) != TYPE_INT
			or int(window["source_token"]) <= 0
			or typeof(window.get("active_from_frame")) != TYPE_INT
			or int(window["active_from_frame"]) < 0
			or typeof(window.get("active_through_frame")) != TYPE_INT
			or int(window["active_through_frame"]) < int(window["active_from_frame"])
			or not _finite_number(window.get("damage_reduction"))
			or float(window["damage_reduction"]) <= 0.0
			or float(window["damage_reduction"]) >= 1.0
		):
			return false
	return true


func _valid_pending_echoes(value: Variant) -> bool:
	if not value is Array:
		return false
	for pending_value: Variant in value as Array:
		if not pending_value is Dictionary:
			return false
		var pending := pending_value as Dictionary
		if (
			not _has_exact_fields(pending, [
				"source_token", "weapon_id", "action_id", "release_frame", "descriptor",
			])
			or typeof(pending.get("source_token")) != TYPE_INT
			or int(pending["source_token"]) <= 0
			or not _valid_segment(pending.get("weapon_id"))
			or not _valid_segment(pending.get("action_id"))
			or typeof(pending.get("release_frame")) != TYPE_INT
			or int(pending["release_frame"]) < 0
			or not CharacterPayloadExecutionScript.is_world_payload_descriptor(pending.get("descriptor"))
		):
			return false
	return true


func _install_snapshot(value: Dictionary) -> void:
	_last_runtime_frame = int(value["last_runtime_frame"])
	_revision = int(value["revision"])
	_resource_value = int(value["resource_value"])
	_run_id = StringName(value["run_id"])
	_run_revision = int(value["run_revision"])
	_owner_character_generation = int(value["owner_character_generation"])
	_mastery_claims.assign(value["mastery_claims"])
	_commitment_claims.assign(value["commitment_claims"])
	_instability_claims.assign(value["instability_claims"])
	_skill_cooldown_until_frame = int(value["skill_cooldown_until_frame"])
	_skill_action = (value["skill_action"] as Dictionary).duplicate(true)
	_armor_windows.assign((value["armor_windows"] as Array).duplicate(true))
	_pending_echoes.assign((value["pending_echoes"] as Array).duplicate(true))
	_authorized_rift_generation = int(value["authorized_rift_generation"])
	_authorized_rift_center = value["authorized_rift_center"] as Vector2
	_rift_anchor_claims.assign(value["rift_anchor_claims"])
	_next_payload_generation = int(value["next_payload_generation"])


static func _valid_sorted_strings(value: Variant) -> bool:
	if not value is Array:
		return false
	var previous := ""
	for entry: Variant in value as Array:
		if typeof(entry) != TYPE_STRING or str(entry).is_empty() or (not previous.is_empty() and str(entry) <= previous):
			return false
		previous = str(entry)
	return true


static func _valid_sorted_positive_ints(value: Variant) -> bool:
	if not value is Array:
		return false
	var previous := 0
	for entry: Variant in value as Array:
		if typeof(entry) != TYPE_INT or int(entry) <= previous:
			return false
		previous = int(entry)
	return true


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _positive_finite_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) > 0.0


static func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


static func _valid_segment(value: Variant) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var text := str(value)
	return not text.is_empty() and text == text.strip_edges() and not text.contains(":")
