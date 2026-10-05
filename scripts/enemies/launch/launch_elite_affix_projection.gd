class_name LaunchEliteAffixProjection
extends RefCounted

const Definition := preload("res://scripts/enemies/launch/elite_affix_definition.gd")
const Rules := preload("res://scripts/enemies/launch/elite_affix_rules.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")

var _rows: Array = []
var _floor := 0
var _configuration: Dictionary = {}


func configure(rows: Array, floor_index: int) -> Dictionary:
	if not _rows.is_empty() or not Contract.integer_in_range(floor_index, 1, 5) or rows.is_empty() or rows.size() > 2:
		return {"ok": false}
	var parsed: Array = []
	var seen: Array = []
	for row: Variant in rows:
		if not row is Dictionary:
			return {"ok": false}
		var accepted := Definition.new().configure(row)
		if not accepted.ok or seen.has(accepted.definition.id) or floor_index < int(accepted.definition.minimum_floor):
			return {"ok": false}
		seen.append(accepted.definition.id)
		parsed.append(accepted.definition)
	parsed.sort_custom(func(left: Dictionary, right: Dictionary): return left.id < right.id)
	_rows = parsed
	_floor = floor_index
	return {"ok": true}


func project(definition: Dictionary) -> Dictionary:
	var ids: Array = _rows.map(func(row: Dictionary): return str(row.id))
	if _rows.is_empty() or definition.get("actor_kind") != "elite" or not Rules.legal_for(str(definition.get("id", "")), _floor, ids):
		return {"ok": false}
	ids.sort()
	var configuration := {"ids": ids, "floor_index": _floor, "pending_ids": [], "damage_taken_multiplier": 1.0, "knockback_resistance": 0.0}
	var projected := definition.duplicate(true)
	for row: Dictionary in _rows:
		var parameters: Dictionary = row.parameters
		match row.id:
			"frenzy":
				projected.move_speed *= float(parameters.speed_multiplier)
				for action: Dictionary in projected.actions:
					for hit: Dictionary in action.hit_schedule:
						hit.damage *= float(parameters.damage_multiplier)
				configuration.damage_taken_multiplier *= float(parameters.damage_taken_multiplier)
			"fortified":
				projected.max_hp *= float(parameters.hp_multiplier)
				projected.move_speed *= float(parameters.speed_multiplier)
				configuration.knockback_resistance = minf(float(parameters.knockback_resistance_cap), float(configuration.knockback_resistance) + float(parameters.knockback_resistance_bonus))
			_:
				configuration.pending_ids.append(row.id)
	configuration.pending_ids.sort()
	projected["affix_signature"] = JSON.stringify({"rows": _rows, "floor_index": _floor}, "", true, true).sha256_text()
	_configuration = configuration
	return {"ok": true, "definition": projected, "configuration": snapshot()}


func snapshot() -> Dictionary:
	return _configuration.duplicate(true)
