class_name FloorRuleRuntime
extends RefCounted

const SeedServiceScript := preload("res://scripts/core/seed_service.gd")

const SNAPSHOT_SCHEMA_VERSION := 1
const MAX_RUNTIME_FRAME := 216_000
const MAX_FRAME_ADVANCE := 3_600
const PHASES: Array[String] = ["idle", "warning", "active", "recovery", "completed"]
const EFFECT_KINDS: Array[String] = ["damage", "modifier"]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"rule_id",
	"configured",
	"room_id",
	"room_seed",
	"zones",
	"safe_zone_ids",
	"runtime_frame",
	"phase",
	"cycle_index",
	"active_zone_id",
	"revision",
	"reduced_motion",
	"hit_flash_enabled",
]

var _rule_id: StringName = &""
var _definition: Dictionary = {}
var _configured: bool = false
var _room_id: String = ""
var _room_seed: int = 0
var _zones: Array[Dictionary] = []
var _safe_zone_ids: Array[String] = []
var _runtime_frame: int = -1
var _phase: String = "idle"
var _cycle_index: int = -1
var _active_zone_id: String = ""
var _revision: int = 0
var _reduced_motion: bool = false
var _hit_flash_enabled: bool = true
var _effect_authority: Variant = null


func configure(source: Dictionary, effect_authority: Variant = null) -> Dictionary:
	if _rule_id == &"" or not _definition_is_valid(_definition):
		return _failure(&"FLOOR_RULE_DEFINITION_INVALID", "rule_id", "not_defined")
	var normalized := _normalized_configuration(source)
	if not bool(normalized.get("ok", false)):
		return normalized
	var authority_value: Variant = effect_authority
	if authority_value == null and source.has("effect_authority"):
		authority_value = source["effect_authority"]
	if not _authority_is_valid(authority_value):
		return _failure(&"FLOOR_RULE_AUTHORITY_INVALID", "effect_authority", "invalid")
	_room_id = str(normalized["room_id"])
	_room_seed = int(normalized["room_seed"])
	_zones = _typed_dictionary_array(normalized["zones"] as Array)
	_safe_zone_ids = _typed_string_array(normalized["safe_zone_ids"] as Array)
	_reduced_motion = bool(normalized["reduced_motion"])
	_hit_flash_enabled = bool(normalized["hit_flash_enabled"])
	_effect_authority = authority_value
	_runtime_frame = -1
	_phase = "idle"
	_cycle_index = -1
	_active_zone_id = ""
	_revision = 0
	_configured = true
	return {"ok": true, "code": &"OK", "snapshot": snapshot(), "facts": [], "presentation": []}


func advance_frame(runtime_frame: int, context: Dictionary = {}) -> Dictionary:
	if not _configured:
		return _failure(&"FLOOR_RULE_NOT_CONFIGURED", "runtime_frame", "not_configured")
	if runtime_frame < 0 or runtime_frame > MAX_RUNTIME_FRAME:
		return _failure(&"FLOOR_RULE_FRAME_INVALID", "runtime_frame", "out_of_range")
	if runtime_frame <= _runtime_frame:
		return _failure(&"FLOOR_RULE_FRAME_INVALID", "runtime_frame", "not_monotonic")
	if runtime_frame - _runtime_frame > MAX_FRAME_ADVANCE:
		return _failure(&"FLOOR_RULE_FRAME_INVALID", "runtime_frame", "advance_too_large")
	if not _advance_context_is_valid(context):
		return _failure(&"FLOOR_RULE_CONTEXT_INVALID", "context", "invalid")

	var facts: Array[Dictionary] = []
	var presentation: Array[Dictionary] = []
	var final_state: Dictionary = {}
	for frame: int in range(_runtime_frame + 1, runtime_frame + 1):
		var state := _state_for_frame(frame)
		var previous_state := _state_for_frame(frame - 1)
		if str(state["phase"]) != str(previous_state["phase"]):
			presentation.append(_presentation_fact(frame, state))
			if str(previous_state["phase"]) == "active":
				var cleanup := _cleanup_fact(frame, previous_state)
				if not cleanup.is_empty():
					facts.append(cleanup)
		if str(state["phase"]) == "active" and _effect_is_due(frame, state):
			facts.append(_effect_fact(frame, state, context))
		final_state = state
	var valid_facts := _validated_facts(facts)
	if valid_facts.size() != facts.size():
		return _failure(&"FLOOR_RULE_FACT_INVALID", "facts", "runtime_generated_invalid_fact")
	if not valid_facts.is_empty() and not _commit_effects(valid_facts):
		return _failure(&"FLOOR_RULE_EFFECT_REJECTED", "effect_authority", "commit_rejected")

	_runtime_frame = runtime_frame
	_phase = str(final_state.get("phase", "completed"))
	_cycle_index = int(final_state.get("cycle_index", int(_definition["cycle_count"])))
	_active_zone_id = str(final_state.get("zone_id", ""))
	_revision += 1
	return {
		"ok": true,
		"code": &"OK",
		"runtime_frame": runtime_frame,
		"phase": _phase,
		"facts": valid_facts,
		"presentation": presentation,
		"snapshot": snapshot(),
	}


func snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"rule_id": str(_rule_id),
		"configured": _configured,
		"room_id": _room_id,
		"room_seed": _room_seed,
		"zones": _zones.duplicate(true),
		"safe_zone_ids": _safe_zone_ids.duplicate(),
		"runtime_frame": _runtime_frame,
		"phase": _phase,
		"cycle_index": _cycle_index,
		"active_zone_id": _active_zone_id,
		"revision": _revision,
		"reduced_motion": _reduced_motion,
		"hit_flash_enabled": _hit_flash_enabled,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != SNAPSHOT_SCHEMA_VERSION
		or typeof(value["rule_id"]) != TYPE_STRING
		or str(value["rule_id"]) != str(_rule_id)
		or typeof(value["configured"]) != TYPE_BOOL
		or typeof(value["room_id"]) != TYPE_STRING
		or typeof(value["room_seed"]) != TYPE_INT
		or not value["zones"] is Array
		or not value["safe_zone_ids"] is Array
		or typeof(value["runtime_frame"]) != TYPE_INT
		or typeof(value["phase"]) != TYPE_STRING
		or typeof(value["cycle_index"]) != TYPE_INT
		or typeof(value["active_zone_id"]) != TYPE_STRING
		or typeof(value["revision"]) != TYPE_INT
		or typeof(value["reduced_motion"]) != TYPE_BOOL
		or typeof(value["hit_flash_enabled"]) != TYPE_BOOL
	):
		return false
	if not bool(value["configured"]):
		return _is_canonical_empty_snapshot(value)
	if (
		str(value["room_id"]).is_empty()
		or int(value["runtime_frame"]) < -1
		or int(value["runtime_frame"]) > MAX_RUNTIME_FRAME
		or not PHASES.has(str(value["phase"]))
		or int(value["revision"]) < 0
	):
		return false
	var normalized := _normalized_configuration({
		"room_id": value["room_id"],
		"room_seed": value["room_seed"],
		"zones": value["zones"],
		"safe_zone_ids": value["safe_zone_ids"],
		"reduced_motion": value["reduced_motion"],
		"hit_flash_enabled": value["hit_flash_enabled"],
	})
	if not bool(normalized.get("ok", false)):
		return false
	if _configured and (
		str(value["room_id"]) != _room_id
		or int(value["room_seed"]) != _room_seed
		or value["zones"] != _zones
		or value["safe_zone_ids"] != _safe_zone_ids
	):
		return false
	var expected_state := _state_for_snapshot(
		int(value["runtime_frame"]),
		int(value["room_seed"]),
		_typed_dictionary_array(value["zones"] as Array),
		_typed_string_array(value["safe_zone_ids"] as Array),
		str(value["room_id"])
	)
	return (
		str(value["phase"]) == str(expected_state["phase"])
		and int(value["cycle_index"]) == int(expected_state["cycle_index"])
		and str(value["active_zone_id"]) == str(expected_state["zone_id"])
	)


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_configured = bool(value["configured"])
	_room_id = str(value["room_id"])
	_room_seed = int(value["room_seed"])
	_zones = _typed_dictionary_array(value["zones"] as Array)
	_safe_zone_ids = _typed_string_array(value["safe_zone_ids"] as Array)
	_runtime_frame = int(value["runtime_frame"])
	_phase = str(value["phase"])
	_cycle_index = int(value["cycle_index"])
	_active_zone_id = str(value["active_zone_id"])
	_revision = int(value["revision"])
	_reduced_motion = bool(value["reduced_motion"])
	_hit_flash_enabled = bool(value["hit_flash_enabled"])
	return true


func reset() -> void:
	_configured = false
	_room_id = ""
	_room_seed = 0
	_zones.clear()
	_safe_zone_ids.clear()
	_runtime_frame = -1
	_phase = "idle"
	_cycle_index = -1
	_active_zone_id = ""
	_revision = 0
	_reduced_motion = false
	_hit_flash_enabled = true
	_effect_authority = null


func rule_id() -> StringName:
	return _rule_id


func _define_rule(rule_id_value: StringName, definition: Dictionary) -> void:
	_rule_id = rule_id_value
	_definition = definition.duplicate(true)


func _normalized_configuration(source: Dictionary) -> Dictionary:
	for field: String in ["room_id", "room_seed", "zones", "safe_zone_ids"]:
		if not source.has(field):
			return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", field, "missing")
	if typeof(source["room_id"]) != TYPE_STRING or str(source["room_id"]).is_empty():
		return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "room_id", "invalid")
	if typeof(source["room_seed"]) != TYPE_INT:
		return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "room_seed", "invalid")
	var zones_result := _normalize_zones(source["zones"])
	if not bool(zones_result.get("ok", false)):
		return zones_result
	var safe_result := _normalize_safe_zone_ids(source["safe_zone_ids"], zones_result["zones"])
	if not bool(safe_result.get("ok", false)):
		return safe_result
	var reduced_motion_value: Variant = source.get("reduced_motion", false)
	var hit_flash_value: Variant = source.get("hit_flash_enabled", true)
	if typeof(reduced_motion_value) != TYPE_BOOL:
		return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "reduced_motion", "invalid")
	if typeof(hit_flash_value) != TYPE_BOOL:
		return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "hit_flash_enabled", "invalid")
	return {
		"ok": true,
		"code": &"OK",
		"room_id": str(source["room_id"]),
		"room_seed": int(source["room_seed"]),
		"zones": (zones_result["zones"] as Array).duplicate(true),
		"safe_zone_ids": (safe_result["safe_zone_ids"] as Array).duplicate(),
		"reduced_motion": bool(reduced_motion_value),
		"hit_flash_enabled": bool(hit_flash_value),
	}


func _normalize_zones(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).is_empty():
		return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "zones", "expected_non_empty_array")
	var zones: Array[Dictionary] = []
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var zone_value: Variant = (value as Array)[index]
		if not zone_value is Dictionary:
			return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "zones[%d]" % index, "invalid")
		var zone := zone_value as Dictionary
		if not _has_exact_fields(zone, ["id", "bounds"]):
			return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "zones[%d]" % index, "fields")
		var zone_id := str(zone.get("id", ""))
		if zone_id.is_empty() or seen.has(zone_id):
			return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "zones[%d].id" % index, "invalid_or_duplicate")
		if not zone["bounds"] is Dictionary:
			return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "zones[%d].bounds" % index, "invalid")
		var bounds := zone["bounds"] as Dictionary
		if not _has_exact_fields(bounds, ["x", "y", "width", "height"]):
			return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "zones[%d].bounds" % index, "fields")
		for field: String in ["x", "y", "width", "height"]:
			if typeof(bounds[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(bounds[field])):
				return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "zones[%d].bounds.%s" % [index, field], "invalid")
		var rect := Rect2(
			float(bounds["x"]), float(bounds["y"]),
			float(bounds["width"]), float(bounds["height"])
		)
		if (
			rect.size.x <= 0.0
			or rect.size.y <= 0.0
			or rect.position.x < 0.0
			or rect.position.y < 0.0
			or rect.end.x > 640.0
			or rect.end.y > 360.0
		):
			return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "zones[%d].bounds" % index, "outside_design_canvas")
		seen[zone_id] = true
		zones.append({
			"id": zone_id,
			"bounds": {
				"x": float(bounds["x"]), "y": float(bounds["y"]),
				"width": float(bounds["width"]), "height": float(bounds["height"]),
			},
		})
	return {"ok": true, "zones": zones}


func _normalize_safe_zone_ids(value: Variant, zones: Array) -> Dictionary:
	if not value is Array or (value as Array).is_empty():
		return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "safe_zone_ids", "expected_non_empty_array")
	var available: Dictionary = {}
	for zone_value: Variant in zones:
		available[str((zone_value as Dictionary)["id"])] = true
	var safe_ids: Array[String] = []
	for index: int in range((value as Array).size()):
		if typeof((value as Array)[index]) != TYPE_STRING:
			return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "safe_zone_ids[%d]" % index, "invalid")
		var zone_id := str((value as Array)[index])
		if not available.has(zone_id) or safe_ids.has(zone_id):
			return _failure(&"FLOOR_RULE_CONFIGURATION_INVALID", "safe_zone_ids[%d]" % index, "unknown_or_duplicate")
		safe_ids.append(zone_id)
	if safe_ids.size() >= zones.size():
		return _failure(
			&"FLOOR_RULE_CONFIGURATION_INVALID",
			"safe_zone_ids",
			"at_least_one_hazard_zone_required"
		)
	return {"ok": true, "safe_zone_ids": safe_ids}


func _state_for_frame(frame: int) -> Dictionary:
	return _state_for_snapshot(frame, _room_seed, _zones, _safe_zone_ids, _room_id)


func _state_for_snapshot(
	frame: int,
	room_seed: int,
	zones: Array[Dictionary],
	safe_zone_ids: Array[String],
	room_id: String
) -> Dictionary:
	if frame < 0:
		return {"phase": "idle", "cycle_index": -1, "zone_id": ""}
	var cycle_span := int(_definition["warning_frames"]) + int(_definition["active_frames"]) + int(_definition["recovery_frames"])
	var cycle_index := frame / cycle_span
	if cycle_index >= int(_definition["cycle_count"]):
		return {
			"phase": "completed",
			"cycle_index": int(_definition["cycle_count"]),
			"zone_id": "",
		}
	var local_frame := frame % cycle_span
	var phase := "warning"
	if local_frame >= int(_definition["warning_frames"]) + int(_definition["active_frames"]):
		phase = "recovery"
	elif local_frame >= int(_definition["warning_frames"]):
		phase = "active"
	var zone_id := _selected_zone_id(room_seed, zones, safe_zone_ids, cycle_index, room_id)
	return {
		"phase": phase,
		"cycle_index": cycle_index,
		"zone_id": zone_id,
		"local_frame": local_frame,
	}


func _selected_zone_id(
	room_seed: int,
	zones: Array[Dictionary],
	safe_zone_ids: Array[String],
	cycle_index: int,
	room_id: String
) -> String:
	if zones.is_empty() or cycle_index < 0:
		return ""
	var hazard_zones: Array[Dictionary] = []
	for zone: Dictionary in zones:
		if not safe_zone_ids.has(str(zone["id"])):
			hazard_zones.append(zone)
	if hazard_zones.is_empty():
		return ""
	var seed := SeedServiceScript.derive_seed(
		room_seed,
		StringName("floor_rule_v1:%s:%s" % [str(_rule_id), room_id]),
		0,
		0,
		cycle_index
	)
	var index := posmod(seed, hazard_zones.size())
	return str(hazard_zones[index]["id"])


func _effect_is_due(frame: int, state: Dictionary) -> bool:
	var local_active_frame := int(state["local_frame"]) - int(_definition["warning_frames"])
	return local_active_frame >= 0 and local_active_frame % int(_definition["effect_interval_frames"]) == 0


func _effect_fact(frame: int, state: Dictionary, context: Dictionary) -> Dictionary:
	var fact := {
		"fact_type": str(_definition["effect_kind"]),
		"rule_id": str(_rule_id),
		"room_id": _room_id,
		"runtime_frame": frame,
		"cycle_index": int(state["cycle_index"]),
		"zone_id": str(state["zone_id"]),
		"source_kind": "floor_rule",
		"source_id": "%s:%s" % [str(_rule_id), _room_id],
		"payload": {},
	}
	if str(_definition["effect_kind"]) == "damage":
		fact["payload"] = {
			"amount": float(_definition["damage_amount"]),
			"damage_type": str(_definition["damage_type"]),
			"target_scope": "player_in_zone",
			"nonlethal": true,
			"minimum_remaining_hp": 1.0,
		}
	else:
		fact["payload"] = {
			"modifier_id": str(_definition["modifier_id"]),
			"target_scope": "player_in_zone",
			"duration_frames": int(_definition["active_frames"]),
			"values": (_definition["modifier_values"] as Dictionary).duplicate(true),
			"operation": "apply",
		}
	if context.has("target_ids"):
		fact["payload"]["target_ids"] = (context["target_ids"] as Array).duplicate()
	return fact


func _cleanup_fact(frame: int, state: Dictionary) -> Dictionary:
	if str(_definition["effect_kind"]) != "modifier":
		return {}
	return {
		"fact_type": "modifier",
		"rule_id": str(_rule_id),
		"room_id": _room_id,
		"runtime_frame": frame,
		"cycle_index": int(state["cycle_index"]),
		"zone_id": str(state["zone_id"]),
		"source_kind": "floor_rule",
		"source_id": "%s:%s" % [str(_rule_id), _room_id],
		"payload": {
			"modifier_id": str(_definition["modifier_id"]),
			"target_scope": "player_in_zone",
			"duration_frames": 0,
			"values": {},
			"operation": "remove",
		},
	}


func _presentation_fact(frame: int, state: Dictionary) -> Dictionary:
	var phase := str(state["phase"])
	return {
		"fact_type": "floor_rule_presentation",
		"rule_id": str(_rule_id),
		"room_id": _room_id,
		"runtime_frame": frame,
		"cycle_index": int(state["cycle_index"]),
		"zone_id": str(state["zone_id"]),
		"phase": phase,
		"cue_id": str(_definition["presentation_cue_id"]),
		"visual_mode": "static_outline" if _reduced_motion else "animated",
		"flash_enabled": _hit_flash_enabled and not _reduced_motion,
		"subtitle_required": phase in ["warning", "active"],
	}


func _validated_facts(values: Array[Dictionary]) -> Array[Dictionary]:
	var facts: Array[Dictionary] = []
	for value: Dictionary in values:
		if not _fact_is_valid(value):
			return []
		facts.append(value.duplicate(true))
	return facts


func _fact_is_valid(fact: Dictionary) -> bool:
	for field: String in [
		"fact_type", "rule_id", "room_id", "runtime_frame", "cycle_index", "zone_id",
		"source_kind", "source_id", "payload",
	]:
		if not fact.has(field):
			return false
	if (
		typeof(fact["fact_type"]) != TYPE_STRING
		or not EFFECT_KINDS.has(str(fact["fact_type"]))
		or str(fact["rule_id"]) != str(_rule_id)
		or str(fact["room_id"]) != _room_id
		or typeof(fact["runtime_frame"]) != TYPE_INT
		or int(fact["runtime_frame"]) < 0
		or typeof(fact["cycle_index"]) != TYPE_INT
		or str(fact["source_kind"]) != "floor_rule"
		or typeof(fact["payload"]) != TYPE_DICTIONARY
	):
		return false
	if str(fact["fact_type"]) == "damage":
		var payload := fact["payload"] as Dictionary
		return (
			typeof(payload.get("amount")) in [TYPE_INT, TYPE_FLOAT]
			and float(payload["amount"]) > 0.0
			and float(payload["amount"]) <= 12.0
			and bool(payload.get("nonlethal", false))
			and float(payload.get("minimum_remaining_hp", 0.0)) >= 1.0
		)
	var modifier_payload := fact["payload"] as Dictionary
	return (
		typeof(modifier_payload.get("modifier_id")) == TYPE_STRING
		and not str(modifier_payload["modifier_id"]).is_empty()
		and str(modifier_payload.get("operation", "")) in ["apply", "remove"]
		and typeof(modifier_payload.get("duration_frames")) == TYPE_INT
		and int(modifier_payload["duration_frames"]) >= 0
		and modifier_payload.get("values") is Dictionary
	)


func _commit_effects(facts: Array[Dictionary]) -> bool:
	if facts.is_empty():
		return true
	if _effect_authority is Callable:
		return bool((_effect_authority as Callable).call(facts.duplicate(true)))
	if _effect_authority is Object:
		var authority := _effect_authority as Object
		if authority.has_method("commit_floor_rule_effects"):
			return bool(authority.call("commit_floor_rule_effects", facts.duplicate(true)))
		if facts.size() == 1 and authority.has_method("commit_floor_rule_effect"):
			return bool(authority.call("commit_floor_rule_effect", facts[0].duplicate(true)))
	return false


func _authority_is_valid(authority: Variant) -> bool:
	if authority is Callable:
		return (authority as Callable).is_valid()
	return (
		authority is Object
		and (
			(authority as Object).has_method("commit_floor_rule_effects")
			or (authority as Object).has_method("commit_floor_rule_effect")
		)
	)


func _advance_context_is_valid(context: Dictionary) -> bool:
	if not context.has("target_ids"):
		return true
	if not context["target_ids"] is Array:
		return false
	var seen: Dictionary = {}
	for target_value: Variant in context["target_ids"] as Array:
		if typeof(target_value) != TYPE_STRING or str(target_value).is_empty() or seen.has(str(target_value)):
			return false
		seen[str(target_value)] = true
	return true


func _definition_is_valid(value: Dictionary) -> bool:
	for field: String in [
		"warning_frames", "active_frames", "recovery_frames", "cycle_count",
		"effect_interval_frames", "effect_kind", "presentation_cue_id",
	]:
		if not value.has(field):
			return false
	for field: String in [
		"warning_frames", "active_frames", "recovery_frames", "cycle_count",
		"effect_interval_frames",
	]:
		if typeof(value[field]) != TYPE_INT or int(value[field]) <= 0:
			return false
	if not EFFECT_KINDS.has(str(value["effect_kind"])):
		return false
	if str(value["presentation_cue_id"]).is_empty():
		return false
	if str(value["effect_kind"]) == "damage":
		return (
			typeof(value.get("damage_amount")) in [TYPE_INT, TYPE_FLOAT]
			and float(value["damage_amount"]) > 0.0
			and float(value["damage_amount"]) <= 12.0
			and typeof(value.get("damage_type")) == TYPE_STRING
			and not str(value["damage_type"]).is_empty()
		)
	return (
		typeof(value.get("modifier_id")) == TYPE_STRING
		and not str(value["modifier_id"]).is_empty()
		and value.get("modifier_values") is Dictionary
	)


func _is_canonical_empty_snapshot(value: Dictionary) -> bool:
	return (
		str(value["room_id"]).is_empty()
		and int(value["room_seed"]) == 0
		and (value["zones"] as Array).is_empty()
		and (value["safe_zone_ids"] as Array).is_empty()
		and int(value["runtime_frame"]) == -1
		and str(value["phase"]) == "idle"
		and int(value["cycle_index"]) == -1
		and str(value["active_zone_id"]).is_empty()
		and int(value["revision"]) == 0
		and not bool(value["reduced_motion"])
		and bool(value["hit_flash_enabled"])
	)


func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_value: Variant in fields:
		if not value.has(str(field_value)):
			return false
	return true


func _typed_dictionary_array(values: Array) -> Array[Dictionary]:
	var typed: Array[Dictionary] = []
	for value: Variant in values:
		typed.append((value as Dictionary).duplicate(true))
	return typed


func _typed_string_array(values: Array) -> Array[String]:
	var typed: Array[String] = []
	for value: Variant in values:
		typed.append(str(value))
	return typed


func _failure(code: StringName, field: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"context": {"field": field, "reason": reason},
		"facts": [],
		"presentation": [],
	}
