class_name EventTemporaryModifierLayer
extends RefCounted

const EventsScript := preload("res://scripts/dungeon/dungeon_event_definition.gd")
const FIELDS := ["modifier_id", "magnitude", "source_transaction_id"]
const ATTACK_IDS := ["weapon_temper", "past_strength", "paradox_echo", "void_bargain_power", "heroic_assault"]
const GUARD_IDS := ["chronal_grace", "void_bargain_guard", "heroic_guard"]

var _modifiers: Array[Dictionary] = []
var _attack_multiplier := 1.0
var _damage_taken_multiplier := 1.0
var _energy_regen_multiplier := 1.0


func replace_projection(value: Array) -> bool:
	if value.size() > EventsScript.MODIFIER_IDS.size():
		return false
	var modifiers: Array[Dictionary] = []
	var ids: Dictionary = {}
	var sources: Dictionary = {}
	var attack := 1.0
	var guard := 1.0
	var regen := 1.0
	for entry: Variant in value:
		if not entry is Dictionary or entry.size() != FIELDS.size():
			return false
		for field: String in FIELDS:
			if not entry.has(field):
				return false
		if typeof(entry["modifier_id"]) != TYPE_STRING or not EventsScript.MODIFIER_IDS.has(entry["modifier_id"]):
			return false
		if typeof(entry["magnitude"]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(entry["magnitude"])) or float(entry["magnitude"]) <= 0.0 or float(entry["magnitude"]) > 10.0:
			return false
		if typeof(entry["source_transaction_id"]) != TYPE_STRING or not _valid_source(entry["source_transaction_id"]):
			return false
		var id: String = entry["modifier_id"]
		var source: String = entry["source_transaction_id"]
		if ids.has(id) or sources.has(source):
			return false
		ids[id] = true
		sources[source] = true
		var magnitude := float(entry["magnitude"])
		modifiers.append({"modifier_id": id, "magnitude": magnitude, "source_transaction_id": source})
		if ATTACK_IDS.has(id):
			attack *= magnitude
		elif GUARD_IDS.has(id):
			guard /= magnitude
		else:
			regen *= magnitude
	if not is_finite(attack) or attack <= 0.0 or not is_finite(guard) or guard <= 0.0 or not is_finite(regen) or regen <= 0.0:
		return false
	modifiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["modifier_id"] < b["modifier_id"])
	_modifiers = modifiers
	_attack_multiplier = attack
	_damage_taken_multiplier = guard
	_energy_regen_multiplier = regen
	return true


func snapshot() -> Array[Dictionary]:
	return _modifiers.duplicate(true)


func attack_multiplier() -> float:
	return _attack_multiplier


func damage_taken_multiplier() -> float:
	return _damage_taken_multiplier


func energy_regen_multiplier() -> float:
	return _energy_regen_multiplier


func _valid_source(value: String) -> bool:
	var regex := RegEx.new()
	return regex.compile("^[a-z0-9][a-z0-9_.:-]{0,95}$") == OK and regex.search(value) != null
