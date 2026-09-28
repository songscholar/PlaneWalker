class_name M1RoomPlan
extends RefCounted

const ROOM_DEFINITIONS: Array[Dictionary] = [
	{"room_number": 1, "type": "combat", "reward_kind": "starter", "target_seconds_min": 45, "target_seconds_max": 70},
	{"room_number": 2, "type": "combat", "reward_kind": "reinforcement", "target_seconds_min": 60, "target_seconds_max": 85},
	{"room_number": 3, "type": "combat", "reward_kind": "talent", "target_seconds_min": 70, "target_seconds_max": 100},
	{"room_number": 4, "type": "elite", "reward_kind": "contract", "target_seconds_min": 90, "target_seconds_max": 125},
	{"room_number": 5, "type": "boss", "reward_kind": "none", "target_seconds_min": 120, "target_seconds_max": 170},
]


static func definitions() -> Array[Dictionary]:
	return ROOM_DEFINITIONS.duplicate(true)
