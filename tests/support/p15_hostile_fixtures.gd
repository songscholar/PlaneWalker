extends RefCounted


static func enemy(enemy_id: String = "shattered_sentinel") -> Dictionary:
	return _definition("enemies.json", enemy_id)


static func boss(boss_id: String = "ruin_king") -> Dictionary:
	return _definition("bosses.json", boss_id)


static func affix(affix_id: String = "frenzy") -> Dictionary:
	return _definition("elite_affixes.json", affix_id)


static func action(action_id: String = "shattered_sentinel.shield_sweep") -> Dictionary:
	for name: String in ["enemies.json", "bosses.json"]:
		for row: Dictionary in read_catalog(name):
			for collection: String in ["actions", "elite_actions", "time_responses"]:
				for candidate: Dictionary in row.get(collection, []):
					if candidate.id == action_id:
						return candidate.duplicate(true)
	return {}


static func context(frame: int, source_id: String = "hostile:test-a") -> Dictionary:
	return {
		"runtime_frame": frame, "run_id": "run-p15", "floor_id": "floor_ruins_of_remnant",
		"node_id": "layer_01_a", "encounter_id": "sentinel_line", "hostile_source_id": source_id,
		"source_position": {"x": 100.0, "y": 100.0}, "target_position": {"x": 120.0, "y": 100.0},
		"facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1", "player_hp": 100.0,
		"room_bounds": {"x": 0.0, "y": 0.0, "width": 640.0, "height": 360.0},
		"time_sources": [], "actor_observations": [],
	}


static func read_catalog(relative_name: String) -> Array:
	if relative_name not in ["enemies.json", "bosses.json", "elite_affixes.json", "summons.json", "launch_encounters.json"]:
		return []
	var path := "res://data/content_packs/base/content/" + relative_name
	if not FileAccess.file_exists(path):
		return []
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value.duplicate(true) if value is Array else []


static func _definition(relative_name: String, id: String) -> Dictionary:
	for row: Dictionary in read_catalog(relative_name):
		if row.id == id:
			return row.duplicate(true)
	return {}
