class_name RewardPolicyProtocol
extends RefCounted

const ACTIONABLE_ROOM_TYPES: Array[String] = [
	"combat", "elite", "treasure", "shop", "event", "boss", "rest",
]
const POLICY_ID_BY_ROOM_TYPE := {
	"combat": "reward_policy_combat_v1",
	"elite": "reward_policy_elite_v1",
	"treasure": "reward_policy_treasure_v1",
	"shop": "reward_policy_shop_v1",
	"event": "reward_policy_event_v1",
	"boss": "reward_policy_boss_v1",
	"rest": "reward_policy_rest_v1",
}
const GOLD_BY_ROOM_TYPE := {
	"combat": [30, 38, 45, 55, 58],
	"elite": [50, 60, 75, 90, 90],
	"treasure": [40, 50, 60, 70, 75],
	"boss": [60, 75, 95, 115, 100],
}


static func gold_for(room_type: String, floor_index: int) -> int:
	if floor_index < 0 or floor_index >= 5:
		return 0
	return int(GOLD_BY_ROOM_TYPE[room_type][floor_index]) if GOLD_BY_ROOM_TYPE.has(room_type) else 0


static func actionable_room_types() -> Array[String]:
	var values: Array[String] = []
	values.assign(ACTIONABLE_ROOM_TYPES)
	return values


static func policy_id_for(room_type: String) -> String:
	return str(POLICY_ID_BY_ROOM_TYPE.get(room_type, ""))


static func matches(room_type: String, policy_id: String) -> bool:
	var expected := policy_id_for(room_type)
	return not expected.is_empty() and policy_id == expected
