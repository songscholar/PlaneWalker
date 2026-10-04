extends RefCounted


static func action() -> Dictionary:
	return {
		"id": "shattered_sentinel.shield_sweep", "handler_id": "melee",
		"warning_frames": 30, "active_frames": 8, "recovery_frames": 25,
		"idle_frames": 15, "cooldown_frames": 150, "weight": 10,
		"max_consecutive": 1, "distance_min_px": 0.0, "distance_max_px": 29.0,
		"geometry": [
			{"shape": "cone", "origin_offset": {"x": 0.0, "y": 0.0}, "aim_offset_degrees": -45.0, "radius": 29.0, "length": 29.0},
			{"shape": "cone", "origin_offset": {"x": 0.0, "y": 0.0}, "aim_offset_degrees": 45.0, "radius": 29.0, "length": 29.0},
		],
		"hit_schedule": [{"offset_frame": 0, "hit_index": 0, "damage": 12.0, "damage_type": "physical"}],
		"parameters": {"knockback_px": 19.0}, "cue_id": "hostile_stone_sweep",
	}


static func definition() -> Dictionary:
	return {"id": "shattered_sentinel", "actor_kind": "enemy", "actions": [action()]}


static func identity() -> Dictionary:
	return {"run_id": "run-p15", "hostile_source_id": "hostile:test-a", "next_generation_floor": 7, "runtime_frame": 0}


static func context(frame: int = 0) -> Dictionary:
	return {
		"runtime_frame": frame, "source_position": {"x": 100.0, "y": 100.0},
		"target_position": {"x": 120.0, "y": 100.0},
		"facing_direction": {"x": 1.0, "y": 0.0}, "target_id": "player:1",
	}
