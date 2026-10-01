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


static func actionable_room_types() -> Array[String]:
	var values: Array[String] = []
	values.assign(ACTIONABLE_ROOM_TYPES)
	return values


static func policy_id_for(room_type: String) -> String:
	return str(POLICY_ID_BY_ROOM_TYPE.get(room_type, ""))


static func matches(room_type: String, policy_id: String) -> bool:
	var expected := policy_id_for(room_type)
	return not expected.is_empty() and policy_id == expected
