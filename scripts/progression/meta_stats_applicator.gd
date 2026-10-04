class_name MetaStatsApplicator
extends RefCounted

const CharacterProfile := preload("res://scripts/player/characters/character_runtime_profile.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const StatsResource := preload("res://scripts/core/stats.gd")
const STAT_FIELDS := {"max_hp": "max_hp", "attack": "attack", "defense": "defense", "speed": "move_speed", "attack_speed": "attack_speed"}


static func prepare(character_profile: Dictionary, character_bonuses: Dictionary, weapon_id: String, projection: Dictionary, catalog: RefCounted) -> Dictionary:
	var parsed: RefCounted = CharacterProfile.from_definition(character_profile)
	if parsed == null:
		return _failure(&"CHARACTER_PROFILE_INVALID")
	if not MetaProjection.validate_combined(projection, character_bonuses, weapon_id, catalog):
		return _failure(&"PERMANENT_COMBINATION_INVALID")
	# Always derive from the authored base. Run talents and rewards keep their own application order.
	var totals: Dictionary = parsed.base_stats.duplicate(true)
	for stat: String in STAT_FIELDS:
		var field: String = STAT_FIELDS[stat]
		totals[field] = float(totals[field]) * (1.0 + float(character_bonuses.get(stat, 0.0))) * (1.0 + float(projection.stat_bonuses[stat]))
	totals["attack"] *= 1.0 + float(projection.forge_attack_bonuses[weapon_id])
	var validated := StatsResource.new()
	if not validated.apply_profile(totals):
		return _failure(&"STATS_INVALID")
	return {
		"ok": true, "code": &"OK",
		"context": {
			"stats": validated.snapshot(),
			"entrance_healing": float(projection.stat_bonuses.entrance_healing),
			"void_reduction": float(projection.stat_bonuses.void_reduction),
		},
	}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
