extends RefCounted


static func encounter() -> Dictionary:
	return {
		"id": "encounter_profile_ruins_adapter_v1.sentinel_line",
		"floor_id": "floor_ruins_of_remnant", "recipe_id": "sentinel_line", "room_type": "combat",
		"waves": [
			{"id": "sentinel_line_wave_1", "delay_frames": 0, "warning_frames": 30, "spawns": [spawn("spawn_1"), spawn("spawn_2")]},
			{"id": "sentinel_line_wave_2", "delay_frames": 6, "warning_frames": 30, "spawns": [spawn("spawn_3")]},
		],
	}


static func spawn(spawn_id: String) -> Dictionary:
	return {"id": spawn_id, "enemy_id": "shattered_sentinel", "spawn_slot_id": "enemy_wave_primary", "spawn_offset": {"x": 0.0, "y": 0.0}, "elite": false, "affix_ids": [], "mechanism_ids": []}


static func identity() -> Dictionary:
	return {"run_id": "run-p15", "room_id": "node-ruins-1", "runtime_frame": 0, "encounter_generation": 3}
