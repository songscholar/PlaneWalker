class_name ActiveItemDefinition
extends RefCounted

const ArchetypeProfileScript := preload("res://scripts/progression/archetype_profile.gd")

const HANDLER_IDS: Array[String] = [
	"absolute_zero",
	"paradox_beacon",
	"gravity_snare",
	"redline_injector",
	"blood_price",
	"aegis_reversal",
	"railshot",
	"army_of_yesterday",
]
const ACTIVE_FIELDS: Array[String] = [
	"active_handler_id", "cooldown_frames", "active_parameters",
]
const EXACT_IDENTITY_BY_ID := {
	"absolute_zero_device": {
		"active_handler_id": "absolute_zero",
		"archetype": "freeze_burst",
	},
	"paradox_beacon": {
		"active_handler_id": "paradox_beacon",
		"archetype": "rewind_echo",
	},
	"gravity_snare_device": {
		"active_handler_id": "gravity_snare",
		"archetype": "rift_trap",
	},
	"redline_injector": {
		"active_handler_id": "redline_injector",
		"archetype": "accelerated_combo",
	},
	"blood_price_relic": {
		"active_handler_id": "blood_price",
		"archetype": "low_hp_void",
	},
	"aegis_reversal": {
		"active_handler_id": "aegis_reversal",
		"archetype": "perfect_guard",
	},
	"railshot_module": {
		"active_handler_id": "railshot",
		"archetype": "piercing_barrage",
	},
	"army_of_yesterday": {
		"active_handler_id": "army_of_yesterday",
		"archetype": "echo_legion",
	},
}
const PARAMETER_CONTRACTS := {
	"absolute_zero": {
		"radius": {"type": "number", "minimum": 32.0, "maximum": 512.0},
		"duration_frames": {"type": "integer", "minimum": 1.0, "maximum": 600.0},
		"weakpoint_bonus": {"type": "number", "minimum": 0.0, "maximum": 3.0},
		"energy_cost": {"type": "number", "minimum": 0.0, "maximum": 100.0},
	},
	"paradox_beacon": {
		"rewind_frames": {"type": "integer", "minimum": 1.0, "maximum": 600.0},
		"echo_damage_multiplier": {"type": "number", "minimum": 0.0, "maximum": 3.0},
		"energy_cost": {"type": "number", "minimum": 0.0, "maximum": 100.0},
	},
	"gravity_snare": {
		"radius": {"type": "number", "minimum": 32.0, "maximum": 512.0},
		"duration_frames": {"type": "integer", "minimum": 1.0, "maximum": 600.0},
		"slow_ratio": {"type": "number", "minimum": 0.0, "maximum": 0.9},
		"energy_cost": {"type": "number", "minimum": 0.0, "maximum": 100.0},
	},
	"redline_injector": {
		"duration_frames": {"type": "integer", "minimum": 1.0, "maximum": 600.0},
		"speed_multiplier": {"type": "number", "minimum": 1.0, "maximum": 3.0},
		"health_cost_ratio": {"type": "number", "minimum": 0.0, "maximum": 0.5},
	},
	"blood_price": {
		"duration_frames": {"type": "integer", "minimum": 1.0, "maximum": 600.0},
		"damage_multiplier": {"type": "number", "minimum": 1.0, "maximum": 5.0},
		"health_cost_ratio": {"type": "number", "minimum": 0.0, "maximum": 0.5},
	},
	"aegis_reversal": {
		"duration_frames": {"type": "integer", "minimum": 1.0, "maximum": 600.0},
		"counter_multiplier": {"type": "number", "minimum": 0.0, "maximum": 5.0},
		"energy_cost": {"type": "number", "minimum": 0.0, "maximum": 100.0},
	},
	"railshot": {
		"pierce_bonus": {"type": "integer", "minimum": 1.0, "maximum": 20.0},
		"damage_multiplier": {"type": "number", "minimum": 1.0, "maximum": 5.0},
		"ammo_refund": {"type": "integer", "minimum": 0.0, "maximum": 20.0},
	},
	"army_of_yesterday": {
		"echo_count": {"type": "integer", "minimum": 1.0, "maximum": 8.0},
		"duration_frames": {"type": "integer", "minimum": 1.0, "maximum": 600.0},
		"echo_damage_multiplier": {"type": "number", "minimum": 0.0, "maximum": 2.0},
		"energy_cost": {"type": "number", "minimum": 0.0, "maximum": 100.0},
	},
}

var _id: String = ""
var _archetype: String = ""
var _handler_id: String = ""
var _cooldown_frames: int = 0
var _parameters: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	_id = ""
	_archetype = ""
	_handler_id = ""
	_cooldown_frames = 0
	_parameters.clear()
	if str(source.get("category", "")) != "item":
		return _failure("category", "value")
	if str(source.get("item_mode", "")) != "active":
		return _failure("item_mode", "value")
	for field: String in ACTIVE_FIELDS:
		if not source.has(field):
			return _failure(field, "missing")
	var content_id := str(source.get("id", ""))
	if not _valid_id(content_id):
		return _failure("id", "invalid")
	var archetype := str(source.get("archetype", ""))
	if not ArchetypeProfileScript.ARCHETYPE_IDS.has(archetype):
		return _failure("archetype", "unknown")
	if str(source.get("role", "")) != "risk":
		return _failure("role", "active_requires_risk")
	var tags_value: Variant = source.get("tags", [])
	if (
		not tags_value is Array
		or not (tags_value as Array).has("active")
		or not (tags_value as Array).has("risk")
		or not (tags_value as Array).has(archetype)
	):
		return _failure("tags", "active_contract")
	var compatibility_value: Variant = source.get("compatibility", {})
	if not compatibility_value is Dictionary:
		return _failure("compatibility", "type")
	var compatibility: Dictionary = compatibility_value
	if compatibility.get("archetype_ids", []) != [archetype]:
		return _failure("compatibility.archetype_ids", "exact_route_required")
	var handler_id_value: Variant = source["active_handler_id"]
	if typeof(handler_id_value) != TYPE_STRING or not HANDLER_IDS.has(str(handler_id_value)):
		return _failure("active_handler_id", "unsupported")
	var exact_identity_value: Variant = EXACT_IDENTITY_BY_ID.get(content_id)
	if not exact_identity_value is Dictionary:
		return _failure("id", "unsupported_active_item")
	var exact_identity: Dictionary = exact_identity_value
	if str(exact_identity["archetype"]) != archetype:
		return _failure("archetype", "active_identity_mismatch")
	if str(exact_identity["active_handler_id"]) != str(handler_id_value):
		return _failure("active_handler_id", "active_identity_mismatch")
	var cooldown_value: Variant = source["cooldown_frames"]
	if (
		typeof(cooldown_value) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(cooldown_value))
		or float(cooldown_value) != floorf(float(cooldown_value))
		or int(cooldown_value) < 1
		or int(cooldown_value) > 3600
	):
		return _failure("cooldown_frames", "out_of_range")
	var parameters_result := _normalize_parameters(str(handler_id_value), source["active_parameters"])
	if not bool(parameters_result.get("ok", false)):
		return parameters_result

	_id = content_id
	_archetype = archetype
	_handler_id = str(handler_id_value)
	_cooldown_frames = int(cooldown_value)
	_parameters = parameters_result["parameters"]
	return {"ok": true, "context": {}}


func snapshot() -> Dictionary:
	return {
		"id": _id,
		"archetype": _archetype,
		"active_handler_id": _handler_id,
		"cooldown_frames": _cooldown_frames,
		"active_parameters": _parameters.duplicate(true),
	}


func _normalize_parameters(handler_id: String, value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("active_parameters", "type")
	var contract: Dictionary = PARAMETER_CONTRACTS.get(handler_id, {})
	var parameters: Dictionary = value
	if parameters.size() != contract.size():
		return _failure("active_parameters", "fields")
	var normalized: Dictionary = {}
	for parameter_id_value: Variant in contract.keys():
		var parameter_id := str(parameter_id_value)
		if not parameters.has(parameter_id):
			return _failure("active_parameters.%s" % parameter_id, "missing")
		var definition: Dictionary = contract[parameter_id_value]
		var parameter_value: Variant = parameters[parameter_id]
		if typeof(parameter_value) not in [TYPE_INT, TYPE_FLOAT]:
			return _failure("active_parameters.%s" % parameter_id, "expected_number")
		var numeric := float(parameter_value)
		if not is_finite(numeric):
			return _failure("active_parameters.%s" % parameter_id, "non_finite")
		if str(definition["type"]) == "integer" and numeric != floorf(numeric):
			return _failure("active_parameters.%s" % parameter_id, "expected_integer")
		if numeric < float(definition["minimum"]) or numeric > float(definition["maximum"]):
			return _failure("active_parameters.%s" % parameter_id, "out_of_range")
		normalized[parameter_id] = int(numeric) if str(definition["type"]) == "integer" else numeric
	for parameter_id_value: Variant in parameters.keys():
		if typeof(parameter_id_value) != TYPE_STRING or not contract.has(str(parameter_id_value)):
			return _failure("active_parameters", "unknown_field")
	return {"ok": true, "parameters": normalized, "context": {}}


func _valid_id(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile("^[a-z0-9][a-z0-9_.-]{0,63}$") == OK and regex.search(value) != null


func _failure(field: String, reason: String) -> Dictionary:
	return {"ok": false, "context": {"field": field, "reason": reason}}
