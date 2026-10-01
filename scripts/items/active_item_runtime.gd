class_name ActiveItemRuntime
extends RefCounted

const ActiveItemDefinitionScript := preload("res://scripts/items/active_item_definition.gd")
const ActiveItemHandlersScript := preload("res://scripts/items/active_item_handlers.gd")

const SNAPSHOT_SCHEMA_VERSION := 1

const CODE_OK := &"OK"
const CODE_NOT_CONFIGURED := &"NOT_CONFIGURED"
const CODE_INVALID_CONTEXT := &"INVALID_CONTEXT"
const CODE_COOLDOWN_ACTIVE := &"COOLDOWN_ACTIVE"
const CODE_PLAN_TAMPERED := &"PLAN_TAMPERED"
const CODE_STALE_TOKEN := &"STALE_TOKEN"
const CODE_STALE_GENERATION := &"STALE_GENERATION"
const CODE_ALREADY_COMMITTED := &"ALREADY_COMMITTED"
const CODE_TOKEN_REUSED := &"TOKEN_REUSED"

var _configured: bool = false
var _definition: Dictionary = {}
var _generation: int = 0
var _next_token: int = 1
var _current_frame: int = -1
var _cooldown_end_frame: int = -1
var _handler_state: Dictionary = {}
var _committed_receipts: Dictionary = {}


func configure(definition: Dictionary) -> bool:
	var parsed = ActiveItemDefinitionScript.new()
	var configured_result: Dictionary = parsed.configure(definition.duplicate(true))
	if not bool(configured_result.get("ok", false)):
		return false
	var next_definition: Dictionary = parsed.snapshot()
	if next_definition.get("id", "") == "":
		return false
	_definition = next_definition
	_configured = true
	_generation += 1
	_next_token = 1
	_current_frame = -1
	_cooldown_end_frame = -1
	_handler_state.clear()
	_committed_receipts.clear()
	return true


func plan_activate(context: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(CODE_NOT_CONFIGURED)
	if typeof(context.get("runtime_frame")) != TYPE_INT:
		return _failure(CODE_INVALID_CONTEXT, {"field": "runtime_frame"})
	var runtime_frame := int(context["runtime_frame"])
	if runtime_frame < maxi(0, _current_frame):
		return _failure(CODE_INVALID_CONTEXT, {"field": "runtime_frame", "reason": "stale"})
	var remaining := _cooldown_remaining_at(runtime_frame)
	if remaining > 0:
		return _failure(CODE_COOLDOWN_ACTIVE, {"remaining_frames": remaining})
	return ActiveItemHandlersScript.build_plan(
		_definition,
		context.duplicate(true),
		_next_token,
		_generation
	)


func commit_activate(plan: Dictionary, token: int) -> Dictionary:
	if not _configured:
		return _failure(CODE_NOT_CONFIGURED)
	if typeof(plan.get("generation")) != TYPE_INT or int(plan.get("generation", 0)) != _generation:
		return _failure(CODE_STALE_GENERATION, {
			"expected_generation": _generation,
			"actual_generation": int(plan.get("generation", 0)),
		})
	if typeof(plan.get("token")) != TYPE_INT or token != int(plan.get("token", 0)):
		return _failure(CODE_STALE_TOKEN, {"expected_token": int(plan.get("token", 0)), "actual_token": token})
	var token_key := str(token)
	if _committed_receipts.has(token_key):
		var committed: Dictionary = _committed_receipts[token_key]
		if committed.get("plan", {}) != plan:
			return _failure(CODE_TOKEN_REUSED, {"token": token})
		var duplicate_result: Dictionary = (committed.get("result", {}) as Dictionary).duplicate(true)
		duplicate_result["code"] = CODE_ALREADY_COMMITTED
		return duplicate_result
	if token != _next_token:
		return _failure(CODE_STALE_TOKEN, {"expected_token": _next_token, "actual_token": token})
	var validation: Dictionary = ActiveItemHandlersScript.validate_plan(_definition, plan)
	if not bool(validation.get("ok", false)):
		return _failure(CODE_PLAN_TAMPERED)
	var runtime_frame := int(plan["runtime_frame"])
	if runtime_frame < maxi(0, _current_frame):
		return _failure(CODE_INVALID_CONTEXT, {"field": "runtime_frame", "reason": "stale"})
	var remaining := _cooldown_remaining_at(runtime_frame)
	if remaining > 0:
		return _failure(CODE_COOLDOWN_ACTIVE, {"remaining_frames": remaining})

	_current_frame = runtime_frame
	_cooldown_end_frame = runtime_frame + int(plan["cooldown_frames"])
	_handler_state = (plan.get("handler_state", {}) as Dictionary).duplicate(true)
	_next_token += 1
	var result := {
		"ok": true,
		"code": CODE_OK,
		"token": token,
		"generation": _generation,
		"cooldown_remaining_frames": cooldown_remaining(),
		"resource_claims": (plan.get("resource_claims", {}) as Dictionary).duplicate(true),
		"payload_descriptor": (plan.get("payload_descriptor", {}) as Dictionary).duplicate(true),
		"boss_conversion": (plan.get("boss_conversion", {}) as Dictionary).duplicate(true),
		"context": {},
	}
	_committed_receipts[token_key] = {
		"plan": plan.duplicate(true),
		"result": result.duplicate(true),
	}
	return result


func advance_frame(context: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not _configured or typeof(context.get("runtime_frame")) != TYPE_INT:
		return events
	var runtime_frame := int(context["runtime_frame"])
	if runtime_frame <= _current_frame:
		return events
	var previous_frame := _current_frame
	_current_frame = runtime_frame
	var expires_at := int(_handler_state.get("expires_at_frame", -1))
	if expires_at >= 0 and previous_frame < expires_at and runtime_frame >= expires_at:
		events.append({
			"type": "active_item_effect_ended",
			"content_id": str(_definition.get("id", "")),
			"handler_id": str(_definition.get("active_handler_id", "")),
			"runtime_frame": runtime_frame,
		})
		_handler_state.clear()
	if _cooldown_end_frame >= 0 and previous_frame < _cooldown_end_frame and runtime_frame >= _cooldown_end_frame:
		events.append({
			"type": "active_item_ready",
			"content_id": str(_definition.get("id", "")),
			"handler_id": str(_definition.get("active_handler_id", "")),
			"runtime_frame": runtime_frame,
		})
		_cooldown_end_frame = -1
	return events


func cooldown_remaining() -> int:
	return _cooldown_remaining_at(_current_frame)


func snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"configured": _configured,
		"definition": _definition.duplicate(true),
		"generation": _generation,
		"next_token": _next_token,
		"current_frame": _current_frame,
		"cooldown_end_frame": _cooldown_end_frame,
		"handler_state": _handler_state.duplicate(true),
		"committed_receipts": _committed_receipts.duplicate(true),
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if (
		value.size() != 9
		or value.get("schema_version") != SNAPSHOT_SCHEMA_VERSION
		or typeof(value.get("configured")) != TYPE_BOOL
		or not value.get("definition") is Dictionary
		or typeof(value.get("generation")) != TYPE_INT
		or int(value.get("generation", -1)) < 0
		or typeof(value.get("next_token")) != TYPE_INT
		or int(value.get("next_token", 0)) < 1
		or typeof(value.get("current_frame")) != TYPE_INT
		or int(value.get("current_frame", -2)) < -1
		or typeof(value.get("cooldown_end_frame")) != TYPE_INT
		or int(value.get("cooldown_end_frame", -2)) < -1
		or not value.get("handler_state") is Dictionary
		or not value.get("committed_receipts") is Dictionary
	):
		return false
	var configured := bool(value["configured"])
	var definition: Dictionary = value["definition"]
	if configured:
		var parsed = ActiveItemDefinitionScript.new()
		var source := _definition_source_from_snapshot(definition)
		if source.is_empty() or not bool(parsed.configure(source).get("ok", false)):
			return false
		if parsed.snapshot() != definition or int(value["generation"]) < 1:
			return false
	else:
		if not definition.is_empty() or int(value["generation"]) != 0:
			return false
	var current_frame := int(value["current_frame"])
	var cooldown_end := int(value["cooldown_end_frame"])
	if cooldown_end >= 0 and (current_frame < 0 or cooldown_end <= current_frame):
		return false
	var receipts: Dictionary = value["committed_receipts"]
	for token_key_value: Variant in receipts.keys():
		if typeof(token_key_value) != TYPE_STRING or not str(token_key_value).is_valid_int():
			return false
		var receipt_value: Variant = receipts[token_key_value]
		if not receipt_value is Dictionary:
			return false
		var receipt: Dictionary = receipt_value
		if not receipt.get("plan") is Dictionary or not receipt.get("result") is Dictionary:
			return false
		var plan: Dictionary = receipt["plan"]
		var result: Dictionary = receipt["result"]
		var receipt_token := int(str(token_key_value))
		if (
			int(plan.get("token", 0)) != receipt_token
			or receipt_token >= int(value["next_token"])
			or int(plan.get("generation", 0)) != int(value["generation"])
			or not bool(ActiveItemHandlersScript.validate_plan(definition, plan).get("ok", false))
			or not bool(result.get("ok", false))
			or int(result.get("token", 0)) != receipt_token
			or int(result.get("generation", 0)) != int(value["generation"])
		):
			return false
	return true


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_configured = bool(value["configured"])
	_definition = (value["definition"] as Dictionary).duplicate(true)
	_generation = int(value["generation"])
	_next_token = int(value["next_token"])
	_current_frame = int(value["current_frame"])
	_cooldown_end_frame = int(value["cooldown_end_frame"])
	_handler_state = (value["handler_state"] as Dictionary).duplicate(true)
	_committed_receipts = (value["committed_receipts"] as Dictionary).duplicate(true)
	return snapshot() == value


func reset_runtime_state(_reason: StringName) -> void:
	if not _configured:
		return
	_generation += 1
	_next_token = 1
	_current_frame = -1
	_cooldown_end_frame = -1
	_handler_state.clear()
	_committed_receipts.clear()


func _cooldown_remaining_at(runtime_frame: int) -> int:
	if _cooldown_end_frame < 0:
		return 0
	return maxi(0, _cooldown_end_frame - runtime_frame)


func _definition_source_from_snapshot(value: Dictionary) -> Dictionary:
	if value.size() != 5 or not value.get("active_parameters") is Dictionary:
		return {}
	var archetype := str(value.get("archetype", ""))
	return {
		"id": str(value.get("id", "")),
		"category": "item",
		"availability": ["LAUNCH", "EXPANSION"],
		"name_key": "RESTORE_NAME",
		"description_key": "RESTORE_DESC",
		"tags": ["active", "risk", archetype],
		"compatibility": {"archetype_ids": [archetype]},
		"effects": {},
		"kind": "time",
		"archetype": archetype,
		"role": "risk",
		"rarity": "rare",
		"icon_id": "content_%s" % str(value.get("id", "")),
		"item_mode": "active",
		"active_handler_id": str(value.get("active_handler_id", "")),
		"cooldown_frames": int(value.get("cooldown_frames", 0)),
		"active_parameters": (value.get("active_parameters", {}) as Dictionary).duplicate(true),
	}


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
