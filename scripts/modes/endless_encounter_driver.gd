extends "res://scripts/dungeon/native_launch_encounter_driver.gd"

const Endless := preload("res://scripts/modes/endless_session.gd")
var cycle_index := 0


func _actor_runtime_projection(definition: Dictionary, spawn: Dictionary) -> Dictionary:
	var scale := Endless.scaling(cycle_index)
	var projection := super._actor_runtime_projection(definition, spawn)
	if scale.is_empty() or projection.is_empty():
		return {}
	if definition.get("category") == "boss_definition":
		var scaled := Boss.difficulty_projection(projection, float(scale.hp_multiplier), float(scale.damage_multiplier))
		return scaled.definition if scaled.ok else {}
	projection.max_hp *= float(scale.hp_multiplier)
	for action: Dictionary in projection.actions:
		for hit: Dictionary in action.hit_schedule:
			hit.damage *= float(scale.damage_multiplier)
	return projection
