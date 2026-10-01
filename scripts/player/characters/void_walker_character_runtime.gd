class_name VoidWalkerCharacterRuntime
extends "res://scripts/player/characters/character_runtime.gd"

const CharacterPayloadExecutionScript := preload(
	"res://scripts/combat/character_payload_execution.gd"
)
const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")

const CHARACTER_ID := &"void_walker"
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
	"next_corruption_frame",
	"corruption_pause_through_frame",
	"authorized_rift_generation",
	"authorized_rift_center",
	"authorized_rift_radius",
	"rift_conversion_claims",
	"skill_cooldown_until_frame",
	"skill_action",
	"next_payload_generation",
]

var _run_id: StringName = &""
var _run_revision: int = 0
var _owner_character_generation: int = 1
var _mastery_claims: Array[String] = []
var _next_corruption_frame: int = -1
var _corruption_pause_through_frame: int = -1
var _authorized_rift_generation: int = 0
var _authorized_rift_center: Vector2 = Vector2.ZERO
var _authorized_rift_radius: float = 0.0
var _rift_conversion_claims: Array[int] = []
var _skill_cooldown_until_frame: int = -1
var _skill_action: Dictionary = {}
var _next_payload_generation: int = 1


func _init() -> void:
	_runtime_kind = &"void_walker"


func configure(owner: Node, profile: Variant, talents: PackedStringArray) -> bool:
	if profile == null or not profile is RefCounted or not profile.has_method("snapshot"):
		return false
	var profile_value: Variant = profile.call("snapshot")
	if (
		not profile_value is Dictionary
		or str((profile_value as Dictionary).get("character_id", "")) != str(CHARACTER_ID)
		or str((profile_value as Dictionary).get("runtime_kind", "")) != "void_walker"
		or str(((profile_value as Dictionary).get("character_skill", {}) as Dictionary).get("handler_id", "")) != "void_devour"
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

	if int(_resource_value) >= _corruption_threshold():
		if _next_corruption_frame < 0:
			_next_corruption_frame = runtime_frame + _passive_parameter_int("corruption_tick_frames")
		while _next_corruption_frame >= 0 and _next_corruption_frame <= runtime_frame:
			if _next_corruption_frame <= _corruption_pause_through_frame:
				_next_corruption_frame = _corruption_pause_through_frame + _passive_parameter_int("corruption_tick_frames")
				continue
			var tick_frame := _next_corruption_frame
			_next_corruption_frame += _passive_parameter_int("corruption_tick_frames")
			events.append(_event(&"irreversible_health_loss_requested", tick_frame, tick_frame + 1, {
				"amount": float(_passive_parameter_int("corruption_tick_damage")),
				"reason": &"corruption_tick",
				"source_token": tick_frame + 1,
				"source_generation": _owner_character_generation,
				"damage_type": &"true",
				"tags": ["corruption", "no_mastery", "non_recursive"],
			}))
	else:
		_next_corruption_frame = -1

	if not _skill_action.is_empty():
		var commit_frame := int(_skill_action.get("commit_frame", -1))
		if not bool(_skill_action.get("committed", false)) and runtime_frame >= commit_frame:
			events.append_array(_commit_devour(commit_frame))
		if (
			not _skill_action.is_empty()
			and bool(_skill_action.get("committed", false))
			and runtime_frame >= int(_skill_action.get("recovery_until_frame", -1))
		):
			events.append_array(_complete_devour(int(_skill_action["recovery_until_frame"])))
	return events


func plan_character_skill(intent: Dictionary, context: Dictionary) -> Dictionary:
	if (
		not _configured
		or not _skill_action.is_empty()
		or not _valid_skill_intent(intent)
		or not _valid_live_context(context)
		or not bool(context.get("alive", false))
		or not _positive_finite_number(context.get("maximum_hp"))
		or not _positive_finite_number(context.get("current_hp"))
		or not _positive_finite_number(context.get("attack"))
		or typeof(context.get("position")) != TYPE_VECTOR2
		or not _finite_vector(context["position"] as Vector2)
		or typeof(context.get("aim_direction")) != TYPE_VECTOR2
		or not _finite_vector(context["aim_direction"] as Vector2)
		or (context["aim_direction"] as Vector2).length_squared() <= 0.000001
	):
		return {"ok": false, "code": "invalid_context"}
	var runtime_frame := int(context["runtime_frame"])
	if _skill_cooldown_until_frame >= 0 and runtime_frame < _skill_cooldown_until_frame:
		return {"ok": false, "code": "cooldown_active"}
	if not _finite_number(context.get("time_energy")) or float(context["time_energy"]) < _skill_energy_cost():
		return {"ok": false, "code": "insufficient_energy"}
	var maximum_hp := float(context["maximum_hp"])
	var health_cost := maxf(
		float(_skill_parameter_int("minimum_health_cost")),
		maximum_hp * _skill_parameter_float("health_cost_ratio")
	)
	if float(context["current_hp"]) <= health_cost:
		return {"ok": false, "code": "terminal_health_cost"}
	return {
		"ok": true,
		"code": "planned",
		"plan": {
			"skill_id": &"void_devour",
			"runtime_frame": runtime_frame,
			"commit_frame": runtime_frame + _skill_parameter_int("windup_frames"),
			"run_id": StringName(context["run_id"]),
			"run_revision": int(context["run_revision"]),
			"owner_character_generation": int(context.get("owner_character_generation", _owner_character_generation)),
			"position": context["position"],
			"aim_direction": (context["aim_direction"] as Vector2).normalized(),
			"attack": float(context["attack"]),
			"maximum_hp": maximum_hp,
			"current_hp": float(context["current_hp"]),
			"health_cost": health_cost,
			"energy_cost": _skill_energy_cost(),
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
	_skill_action["confirmed_damage"] = 0.0
	_skill_action["kill_confirmed"] = false
	_skill_action["cooldown_reset_claimed"] = false
	_revision += 1
	return {
		"ok": true,
		"code": "accepted",
		"events": [],
		"context": {
			"skill_id": &"void_devour",
			"commit_frame": int(plan["commit_frame"]),
			"health_cost": float(plan["health_cost"]),
		},
	}


func character_action_cancellation_state() -> Dictionary:
	return {
		"active": not _skill_action.is_empty(),
		"committed": bool(_skill_action.get("committed", false)),
	}


func cancel_uncommitted_action(_reason: StringName) -> Dictionary:
	if _skill_action.is_empty() or bool(_skill_action.get("committed", false)):
		return {"ok": true, "cancelled": false}
	_skill_action.clear()
	_revision += 1
	return {"ok": true, "cancelled": true}


func after_damage(damage_context: Dictionary) -> Array[Dictionary]:
	if (
		not _context_matches_run(damage_context)
		or typeof(damage_context.get("runtime_frame")) != TYPE_INT
		or int(damage_context["runtime_frame"]) != _last_runtime_frame
		or typeof(damage_context.get("applied")) != TYPE_BOOL
		or not bool(damage_context["applied"])
		or bool(damage_context.get("prevented", false))
		or not _positive_finite_number(damage_context.get("finalized_damage"))
	):
		return []
	var source_kind := StringName(str(damage_context.get("source_kind", "")))
	var amount := float(damage_context["finalized_damage"])
	if (
		not _skill_action.is_empty()
		and bool(_skill_action.get("committed", false))
		and source_kind == &"character_payload"
		and StringName(str(damage_context.get("payload_family", ""))) == &"void_devour"
		and int(damage_context.get("source_token", 0)) == int(_skill_action.get("token", -1))
	):
		_skill_action["confirmed_damage"] = float(_skill_action.get("confirmed_damage", 0.0)) + amount
		if bool(damage_context.get("target_killed", false)):
			_skill_action["kill_confirmed"] = true
		_revision += 1
		return []
	if source_kind not in [&"enemy", &"self_cost"]:
		return []
	var before := int(_resource_value)
	_resource_value = mini(_resource_maximum(), before + ceili(amount))
	if int(_resource_value) == before:
		return []
	if before < _corruption_threshold() and int(_resource_value) >= _corruption_threshold():
		_next_corruption_frame = _last_runtime_frame + _passive_parameter_int("corruption_tick_frames")
	_revision += 1
	return [_resource_event(_last_runtime_frame, int(damage_context.get("source_token", 0)), &"damage_resolved")]


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
	_revision += 1
	var context := normalized["context"] as Dictionary
	var risk := _risk_membership(context)
	if not bool(risk.get("inside", false)):
		return []
	var rift_generation := int(risk.get("rift_generation", 0))
	var additional_rift_cost := 0
	if rift_generation > 0:
		if _rift_conversion_claims.has(rift_generation):
			return []
		additional_rift_cost = int(_time_parameters(&"rift").get("additional_debt_cost", 0))
	var available_for_conversion := int(_resource_value) - additional_rift_cost
	var conversion := mini(_conversion_cap(), available_for_conversion)
	if conversion <= 0:
		return []
	var origin := context["position"] as Vector2
	var echo_radius := float(_passive_parameter_int("echo_radius"))
	if rift_generation > 0:
		echo_radius = 224.0
		origin = _authorized_rift_center
	var descriptor := _payload_descriptor(
		&"void_debt_echo",
		&"character_void_echo",
		int(normalized["action_token"]),
		origin,
		echo_radius,
		float(context["attack"]) * _passive_parameter_float("echo_multiplier"),
		{
			"conversion_amount": conversion,
			"rift_generation": rift_generation,
		}
	)
	if descriptor.is_empty():
		return []
	_resource_value = int(_resource_value) - conversion - additional_rift_cost
	if rift_generation > 0:
		_rift_conversion_claims.append(rift_generation)
		_rift_conversion_claims.sort()
	_revision += 1
	var token := int(normalized["action_token"])
	var heal_amount := minf(float(conversion), float(_passive_parameter_int("conversion_heal_cap")))
	return [
		_resource_event(_last_runtime_frame, token, &"weapon_mastery_conversion"),
		_event(&"world_payload_requested", _last_runtime_frame, token, {"descriptor": descriptor}),
		_event(&"health_restore_requested", _last_runtime_frame, token, {
			"amount": heal_amount,
			"cap_kind": &"missing_hp",
			"reason": &"void_debt_conversion",
		}),
		_event(&"character_conversion_resolved", _last_runtime_frame, token, {
			"conversion_id": &"void_debt",
			"converted_debt": conversion,
			"additional_rift_cost": additional_rift_cost,
		}),
	]


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
	for key: String in ["stop_until_frame", "rift_generation", "rift_center", "rift_radius"]:
		if time_context.has(key):
			parameters[key] = time_context[key]
	var decision := CharacterPayloadExecutionScript.decision(
		&"void_walker_time_conversion",
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
		StringName(str(decision.get("decision_id", ""))) != &"void_walker_time_conversion"
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
		var until_value: Variant = time_context.get("stop_until_frame", parameters.get("stop_until_frame", -1))
		if typeof(until_value) != TYPE_INT or int(until_value) < _last_runtime_frame:
			return []
		_corruption_pause_through_frame = maxi(_corruption_pause_through_frame, int(until_value))
	elif ability_id == &"rift":
		var generation_value: Variant = time_context.get("rift_generation", parameters.get("rift_generation", 0))
		var center_value: Variant = time_context.get("rift_center", parameters.get("rift_center"))
		var radius_value: Variant = time_context.get("rift_radius", parameters.get("rift_radius", 0.0))
		if (
			typeof(generation_value) != TYPE_INT
			or int(generation_value) <= 0
			or typeof(center_value) != TYPE_VECTOR2
			or not _finite_vector(center_value as Vector2)
			or not _positive_finite_number(radius_value)
		):
			return []
		_authorized_rift_generation = int(generation_value)
		_authorized_rift_center = center_value as Vector2
		_authorized_rift_radius = float(radius_value)
	_revision += 1
	return [_event(&"void_time_conversion_committed", _last_runtime_frame, int(time_context["token"]), {
		"ability_id": ability_id,
		"preserves_irreversible_costs": ability_id == &"rewind",
		"preserves_corruption_budget": ability_id == &"accelerate",
		"corruption_pause_through_frame": _corruption_pause_through_frame,
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
	return [_event(&"void_room_started", maxi(_last_runtime_frame, 0), 0, {
		"room_id": StringName(room_context["room_id"]),
		"room_revision": int(room_context["room_revision"]),
	})]


func on_run_terminal(run_context: Dictionary) -> Dictionary:
	if not _context_matches_run(run_context):
		return {"ok": false, "summary": {}}
	return {"ok": true, "summary": {
		"void_debt": int(_resource_value),
		"mastery_conversions": _mastery_claims.size(),
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
		"next_corruption_frame": _next_corruption_frame,
		"corruption_pause_through_frame": _corruption_pause_through_frame,
		"authorized_rift_generation": _authorized_rift_generation,
		"authorized_rift_center": _authorized_rift_center,
		"authorized_rift_radius": _authorized_rift_radius,
		"rift_conversion_claims": _rift_conversion_claims.duplicate(),
		"skill_cooldown_until_frame": _skill_cooldown_until_frame,
		"skill_action": _skill_action.duplicate(true),
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
	# Gameplay Rewind may restore eligible player state, never Void Debt, claims,
	# corruption budget, Devour costs, cooldowns, or committed payloads.
	return not _validated_snapshot(value).is_empty()


func presentation_snapshot() -> Dictionary:
	return {
		"runtime_kind": str(_runtime_kind),
		"resource_value": int(_resource_value),
		"resource_maximum": _resource_maximum(),
		"corruption_threshold": _corruption_threshold(),
		"corruption_active": int(_resource_value) >= _corruption_threshold(),
		"next_corruption_frame": _next_corruption_frame,
		"risk_radius": _risk_radius(),
		"conversion_cap": _conversion_cap(),
		"skill_cooldown_until_frame": _skill_cooldown_until_frame,
		"skill_active": not _skill_action.is_empty(),
	}


func _commit_devour(commit_frame: int) -> Array[Dictionary]:
	if _skill_action.is_empty():
		return []
	var token := int(_skill_action.get("token", 0))
	var descriptor := _payload_descriptor(
		&"void_devour",
		&"void_devour_cone",
		token,
		_skill_action["position"] as Vector2,
		0.01,
		float(_skill_action["attack"]) * _skill_parameter_float("damage_multiplier"),
		{
			"aim_direction": _skill_action["aim_direction"],
			"cone_tiles": _skill_parameter_int("cone_tiles"),
			"cone_degrees": _skill_parameter_int("cone_degrees"),
			"length": float(_skill_parameter_int("cone_tiles") * 32),
		}
	)
	if descriptor.is_empty():
		_skill_action.clear()
		_revision += 1
		return [_event(&"void_devour_failed", commit_frame, token, {"reason": &"payload_construction"})]
	_skill_action["committed"] = true
	_skill_action["recovery_until_frame"] = (
		commit_frame
		+ _skill_parameter_int("active_frames")
		+ _skill_parameter_int("recovery_frames")
	)
	_skill_cooldown_until_frame = commit_frame + _skill_cooldown_frames()
	_revision += 1
	return [
		_event(&"time_energy_spend_requested", commit_frame, token, {
			"amount": float(_skill_action["energy_cost"]),
			"reason": &"void_devour",
		}),
		_event(&"irreversible_health_loss_requested", commit_frame, token, {
			"amount": float(_skill_action["health_cost"]),
			"reason": &"void_devour_self_cost",
			"source_token": token,
			"source_generation": _owner_character_generation,
			"tags": ["no_mastery", "non_recursive", "self_cost"],
		}),
		_event(&"world_payload_requested", commit_frame, token, {"descriptor": descriptor}),
		_cooldown_event(commit_frame, _skill_cooldown_frames(), &"devour_committed"),
		_event(&"character_skill_committed", commit_frame, token, {"skill_id": &"void_devour"}),
	]


func _complete_devour(completion_frame: int) -> Array[Dictionary]:
	var token := int(_skill_action.get("token", 0))
	var confirmed_damage := float(_skill_action.get("confirmed_damage", 0.0))
	var maximum_hp := float(_skill_action.get("maximum_hp", 0.0))
	var heal_amount := minf(
		confirmed_damage * _devour_heal_ratio(),
		maximum_hp * _devour_heal_cap_ratio()
	)
	var kill_confirmed := bool(_skill_action.get("kill_confirmed", false))
	var events: Array[Dictionary] = []
	if heal_amount > 0.0:
		events.append(_event(&"health_restore_requested", completion_frame, token, {
			"amount": heal_amount,
			"cap_kind": &"missing_hp",
			"reason": &"void_devour_confirmed_damage",
			"confirmed_damage": confirmed_damage,
		}))
	if kill_confirmed and not bool(_skill_action.get("cooldown_reset_claimed", false)):
		_skill_action["cooldown_reset_claimed"] = true
		_skill_cooldown_until_frame = completion_frame
		events.append(_event(&"character_cooldown_reset_requested", completion_frame, token, {
			"skill_id": &"void_devour",
			"reason": &"kill_confirmed",
		}))
	events.append(_event(&"character_skill_completed", completion_frame, token, {
		"skill_id": &"void_devour",
	}))
	_skill_action.clear()
	_revision += 1
	return events


func _risk_membership(context: Dictionary) -> Dictionary:
	var position := context["position"] as Vector2
	var registry_value: Variant = context.get("hostile_threat_registry")
	if registry_value is RefCounted:
		var distance_value: Variant = INF
		if registry_value.has_method("nearest_hostile_distance"):
			distance_value = registry_value.call("nearest_hostile_distance", position, _last_runtime_frame)
		elif registry_value.has_method("nearest_threat_distance"):
			distance_value = registry_value.call("nearest_threat_distance", position, _last_runtime_frame)
		if _finite_number(distance_value) and float(distance_value) <= float(_risk_radius()):
			return {"inside": true, "risk_kind": &"hostile_registry", "rift_generation": 0}
	var rift_generation := int(context.get("rift_generation", 0))
	if (
		rift_generation > 0
		and rift_generation == _authorized_rift_generation
		and position.distance_to(_authorized_rift_center) <= _authorized_rift_radius
	):
		return {"inside": true, "risk_kind": &"authorized_rift", "rift_generation": rift_generation}
	return {"inside": false, "risk_kind": &"none", "rift_generation": 0}


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
	if (
		not _valid_live_context(context)
		or not _context_matches_run(context)
		or not _positive_finite_number(context.get("attack"))
		or typeof(context.get("position")) != TYPE_VECTOR2
		or not _finite_vector(context["position"] as Vector2)
	):
		return {}
	return {
		"generation": int(value["generation"]),
		"action_token": int(value["action_token"]),
		"mastery_family": StringName(value["mastery_family"]),
		"context": context.duplicate(true),
	}


func _payload_descriptor(
	payload_family: StringName,
	handler_id: StringName,
	source_token: int,
	origin: Vector2,
	radius: float,
	damage: float,
	extra_parameters: Dictionary
) -> Dictionary:
	var geometry := {"shape": &"circle", "center": origin, "radius": maxf(radius, 0.01)}
	if payload_family == &"void_devour":
		geometry = {
			"shape": &"cone",
			"origin": origin,
			"aim_direction": extra_parameters.get("aim_direction", Vector2.RIGHT),
			"length": float(extra_parameters.get("length", 256.0)),
			"degrees": float(extra_parameters.get("cone_degrees", 60)),
		}
	var parameters := {"damage": damage, "damage_type": &"void"}
	for key: Variant in extra_parameters.keys():
		parameters[key] = extra_parameters[key]
	var descriptor := CharacterPayloadExecutionScript.world_payload_descriptor(
		_run_id,
		_owner_character_generation,
		payload_family,
		source_token,
		_next_payload_generation,
		handler_id,
		Transform2D(0.0, origin),
		geometry,
		2,
		[],
		["character_owned", "no_mastery", "no_resource", "non_recursive", "world_owned"],
		parameters
	)
	if not descriptor.is_empty():
		_next_payload_generation += 1
	return descriptor


func _valid_skill_plan(plan: Dictionary) -> bool:
	return (
		_configured
		and _skill_action.is_empty()
		and str(plan.get("skill_id", "")) == "void_devour"
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
		and typeof(plan.get("aim_direction")) == TYPE_VECTOR2
		and _finite_vector(plan["aim_direction"] as Vector2)
		and _positive_finite_number(plan.get("attack"))
		and _positive_finite_number(plan.get("maximum_hp"))
		and _positive_finite_number(plan.get("current_hp"))
		and _positive_finite_number(plan.get("health_cost"))
		and float(plan["current_hp"]) > float(plan["health_cost"])
		and _finite_number(plan.get("energy_cost"))
		and float(plan["energy_cost"]) == _skill_energy_cost()
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


func _resource_event(frame: int, token: int, reason: StringName) -> Dictionary:
	return _event(&"character_resource_changed", frame, token, {
		"resource_id": &"void_debt",
		"current": int(_resource_value),
		"maximum": _resource_maximum(),
		"reason": reason,
	})


func _cooldown_event(frame: int, duration: int, reason: StringName) -> Dictionary:
	return _event(&"character_cooldown_started", frame, 0, {
		"skill_id": &"void_devour",
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
	return _talent_modifier_int(
		"debt_cap",
		int((_profile_snapshot.get("resource", {}) as Dictionary).get("maximum", 100))
	)


func _corruption_threshold() -> int:
	return _talent_modifier_int(
		"corruption_threshold",
		_passive_parameter_int("corruption_threshold")
	)


func _risk_radius() -> int:
	return _talent_modifier_int("risk_radius", _passive_parameter_int("risk_radius"))


func _conversion_cap() -> int:
	return _talent_modifier_int(
		"mastery_conversion_cap",
		_passive_parameter_int("conversion_cap")
	)


func _devour_heal_ratio() -> float:
	return _talent_modifier_float(
		"devour_heal_ratio",
		_skill_parameter_float("heal_ratio")
	)


func _devour_heal_cap_ratio() -> float:
	return _talent_modifier_float(
		"devour_heal_cap_ratio",
		_skill_parameter_float("heal_cap_ratio")
	)


func _time_parameters(ability_id: StringName) -> Dictionary:
	return (((_profile_snapshot.get("time_interactions", {}) as Dictionary).get(str(ability_id), {}) as Dictionary).get("parameters", {}) as Dictionary)


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
	_next_corruption_frame = -1
	_corruption_pause_through_frame = -1
	_authorized_rift_generation = 0
	_authorized_rift_center = Vector2.ZERO
	_authorized_rift_radius = 0.0
	_rift_conversion_claims.clear()
	_skill_cooldown_until_frame = -1
	_skill_action.clear()
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
		or str(value["runtime_kind"]) != "void_walker"
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
		or typeof(value["next_corruption_frame"]) != TYPE_INT
		or int(value["next_corruption_frame"]) < -1
		or typeof(value["corruption_pause_through_frame"]) != TYPE_INT
		or int(value["corruption_pause_through_frame"]) < -1
		or typeof(value["authorized_rift_generation"]) != TYPE_INT
		or int(value["authorized_rift_generation"]) < 0
		or typeof(value["authorized_rift_center"]) != TYPE_VECTOR2
		or not _finite_vector(value["authorized_rift_center"] as Vector2)
		or not _nonnegative_finite_number(value["authorized_rift_radius"])
		or not _valid_sorted_positive_ints(value["rift_conversion_claims"])
		or typeof(value["skill_cooldown_until_frame"]) != TYPE_INT
		or int(value["skill_cooldown_until_frame"]) < -1
		or not value["skill_action"] is Dictionary
		or not ReplaySafeValueScript.is_supported(value["skill_action"])
		or typeof(value["next_payload_generation"]) != TYPE_INT
		or int(value["next_payload_generation"]) <= 0
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
	_mastery_claims.assign(value["mastery_claims"])
	_next_corruption_frame = int(value["next_corruption_frame"])
	_corruption_pause_through_frame = int(value["corruption_pause_through_frame"])
	_authorized_rift_generation = int(value["authorized_rift_generation"])
	_authorized_rift_center = value["authorized_rift_center"] as Vector2
	_authorized_rift_radius = float(value["authorized_rift_radius"])
	_rift_conversion_claims.assign(value["rift_conversion_claims"])
	_skill_cooldown_until_frame = int(value["skill_cooldown_until_frame"])
	_skill_action = (value["skill_action"] as Dictionary).duplicate(true)
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


static func _nonnegative_finite_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) >= 0.0


static func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


static func _valid_segment(value: Variant) -> bool:
	if typeof(value) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var text := str(value)
	return not text.is_empty() and text == text.strip_edges() and not text.contains(":")
