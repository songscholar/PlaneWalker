class_name ActiveItemHandlers
extends RefCounted

const CODE_OK := &"OK"
const CODE_INVALID_CONTEXT := &"INVALID_CONTEXT"
const CODE_UNKNOWN_HANDLER := &"UNKNOWN_HANDLER"
const CODE_INSUFFICIENT_RESOURCE := &"INSUFFICIENT_RESOURCE"

const PAYLOAD_FAMILY_BY_HANDLER := {
	"absolute_zero": "area_weakpoint_exposure",
	"paradox_beacon": "rewind_echo",
	"gravity_snare": "gravity_field",
	"redline_injector": "self_speed_window",
	"blood_price": "self_damage_window",
	"aegis_reversal": "counter_window",
	"railshot": "next_projectile_override",
	"army_of_yesterday": "echo_summon_window",
}


static func build_plan(
	definition: Dictionary,
	context: Dictionary,
	token: int,
	generation: int
) -> Dictionary:
	var handler_id := str(definition.get("active_handler_id", ""))
	if not PAYLOAD_FAMILY_BY_HANDLER.has(handler_id):
		return _failure(CODE_UNKNOWN_HANDLER, {"handler_id": handler_id})
	if token <= 0 or generation <= 0:
		return _failure(CODE_INVALID_CONTEXT, {"field": "token_or_generation"})
	var context_result := _normalize_context(context)
	if not bool(context_result.get("ok", false)):
		return context_result
	var normalized_context: Dictionary = context_result["context"]
	var parameters_value: Variant = definition.get("active_parameters", {})
	if not parameters_value is Dictionary:
		return _failure(CODE_INVALID_CONTEXT, {"field": "active_parameters"})
	var parameters: Dictionary = (parameters_value as Dictionary).duplicate(true)
	var resource_result := _resource_claims(handler_id, parameters, normalized_context)
	if not bool(resource_result.get("ok", false)):
		return resource_result
	var resource_claims: Dictionary = resource_result.get("resource_claims", {})
	var payload_descriptor := _payload_descriptor(handler_id, parameters)
	var duration_frames := _duration_frames(handler_id, parameters)
	var runtime_frame := int(normalized_context["runtime_frame"])
	var handler_state: Dictionary = {
		"payload_family": str(payload_descriptor["family"]),
		"activated_at_frame": runtime_frame,
		"expires_at_frame": runtime_frame + duration_frames if duration_frames > 0 else -1,
		"awaiting_consumption": handler_id == "railshot",
	}
	var plan: Dictionary = {
		"content_id": str(definition.get("id", "")),
		"handler_id": handler_id,
		"archetype": str(definition.get("archetype", "")),
		"token": token,
		"generation": generation,
		"runtime_frame": runtime_frame,
		"cooldown_frames": int(definition.get("cooldown_frames", 0)),
		"parameters": parameters,
		"activation_context": normalized_context,
		"resource_claims": resource_claims,
		"payload_descriptor": payload_descriptor,
		"boss_conversion": _boss_conversion(handler_id, parameters),
		"handler_state": handler_state,
	}
	plan["digest"] = _digest(plan)
	return {"ok": true, "code": CODE_OK, "plan": plan, "context": {}}


static func validate_plan(definition: Dictionary, plan: Dictionary) -> Dictionary:
	if typeof(plan.get("token")) != TYPE_INT or typeof(plan.get("generation")) != TYPE_INT:
		return _failure(CODE_INVALID_CONTEXT, {"field": "token_or_generation"})
	var activation_context_value: Variant = plan.get("activation_context", {})
	if not activation_context_value is Dictionary:
		return _failure(CODE_INVALID_CONTEXT, {"field": "activation_context"})
	var rebuilt := build_plan(
		definition,
		activation_context_value as Dictionary,
		int(plan["token"]),
		int(plan["generation"])
	)
	if not bool(rebuilt.get("ok", false)):
		return rebuilt
	return {
		"ok": rebuilt.get("plan", {}) == plan,
		"code": CODE_OK if rebuilt.get("plan", {}) == plan else &"PLAN_TAMPERED",
		"context": {},
	}


static func _normalize_context(context: Dictionary) -> Dictionary:
	if typeof(context.get("runtime_frame")) != TYPE_INT or int(context.get("runtime_frame", -1)) < 0:
		return _failure(CODE_INVALID_CONTEXT, {"field": "runtime_frame"})
	var normalized := {
		"runtime_frame": int(context["runtime_frame"]),
		"is_boss_target": bool(context.get("is_boss_target", false)),
	}
	for field: String in ["energy_current", "health_current", "health_maximum"]:
		var value: Variant = context.get(field, 0.0)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
			return _failure(CODE_INVALID_CONTEXT, {"field": field})
		normalized[field] = float(value)
	if float(normalized["health_current"]) > float(normalized["health_maximum"]):
		return _failure(CODE_INVALID_CONTEXT, {"field": "health_current"})
	return {"ok": true, "code": CODE_OK, "context": normalized}


static func _resource_claims(
	handler_id: String,
	parameters: Dictionary,
	context: Dictionary
) -> Dictionary:
	var resource_claims: Dictionary = {}
	if parameters.has("energy_cost"):
		var energy_cost := float(parameters["energy_cost"])
		if float(context["energy_current"]) < energy_cost:
			return _failure(CODE_INSUFFICIENT_RESOURCE, {
				"resource_id": "time_energy",
				"required": energy_cost,
				"available": float(context["energy_current"]),
			})
		resource_claims["time_energy"] = energy_cost
	if parameters.has("health_cost_ratio"):
		var health_cost := float(context["health_maximum"]) * float(parameters["health_cost_ratio"])
		if float(context["health_current"]) - health_cost < 1.0:
			return _failure(CODE_INSUFFICIENT_RESOURCE, {
				"resource_id": "health",
				"required": health_cost,
				"available": maxf(0.0, float(context["health_current"]) - 1.0),
			})
		resource_claims["health"] = health_cost
	if handler_id == "railshot":
		resource_claims["ammo_refund_on_hit"] = int(parameters["ammo_refund"])
	return {"ok": true, "code": CODE_OK, "resource_claims": resource_claims, "context": {}}


static func _payload_descriptor(handler_id: String, parameters: Dictionary) -> Dictionary:
	var descriptor: Dictionary = {
		"family": PAYLOAD_FAMILY_BY_HANDLER[handler_id],
		"handler_id": handler_id,
	}
	match handler_id:
		"absolute_zero":
			descriptor.merge({
				"radius": parameters["radius"],
				"duration_frames": parameters["duration_frames"],
				"weakpoint_bonus": parameters["weakpoint_bonus"],
			})
		"paradox_beacon":
			descriptor.merge({
				"rewind_frames": parameters["rewind_frames"],
				"echo_damage_multiplier": parameters["echo_damage_multiplier"],
			})
		"gravity_snare":
			descriptor.merge({
				"radius": parameters["radius"],
				"duration_frames": parameters["duration_frames"],
				"slow_ratio": parameters["slow_ratio"],
			})
		"redline_injector":
			descriptor.merge({
				"duration_frames": parameters["duration_frames"],
				"speed_multiplier": parameters["speed_multiplier"],
			})
		"blood_price":
			descriptor.merge({
				"duration_frames": parameters["duration_frames"],
				"damage_multiplier": parameters["damage_multiplier"],
			})
		"aegis_reversal":
			descriptor.merge({
				"duration_frames": parameters["duration_frames"],
				"counter_multiplier": parameters["counter_multiplier"],
			})
		"railshot":
			descriptor.merge({
				"pierce_bonus": parameters["pierce_bonus"],
				"damage_multiplier": parameters["damage_multiplier"],
				"ammo_refund": parameters["ammo_refund"],
			})
		"army_of_yesterday":
			descriptor.merge({
				"echo_count": parameters["echo_count"],
				"duration_frames": parameters["duration_frames"],
				"echo_damage_multiplier": parameters["echo_damage_multiplier"],
			})
	return descriptor


static func _boss_conversion(handler_id: String, parameters: Dictionary) -> Dictionary:
	var conversion := {
		"hard_control": false,
		"handler_id": handler_id,
	}
	match handler_id:
		"absolute_zero":
			conversion["behavior"] = "weakpoint_exposure"
			conversion["magnitude"] = parameters["weakpoint_bonus"]
		"gravity_snare":
			conversion["behavior"] = "facing_and_safety_window"
			conversion["magnitude"] = parameters["slow_ratio"]
		"paradox_beacon", "army_of_yesterday":
			conversion["behavior"] = "echo_damage_window"
			conversion["magnitude"] = parameters["echo_damage_multiplier"]
		"aegis_reversal":
			conversion["behavior"] = "counter_exposure"
			conversion["magnitude"] = parameters["counter_multiplier"]
		"redline_injector":
			conversion["behavior"] = "self_speed_window"
			conversion["magnitude"] = parameters["speed_multiplier"]
		"blood_price":
			conversion["behavior"] = "self_damage_window"
			conversion["magnitude"] = parameters["damage_multiplier"]
		"railshot":
			conversion["behavior"] = "projectile_exposure"
			conversion["magnitude"] = parameters["damage_multiplier"]
	return conversion


static func _duration_frames(handler_id: String, parameters: Dictionary) -> int:
	if parameters.has("duration_frames"):
		return int(parameters["duration_frames"])
	if handler_id == "paradox_beacon":
		return int(parameters["rewind_frames"])
	return 0


static func _digest(plan: Dictionary) -> String:
	var unsigned := plan.duplicate(true)
	unsigned.erase("digest")
	return JSON.stringify(unsigned, "", true, true).sha256_text()


static func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
