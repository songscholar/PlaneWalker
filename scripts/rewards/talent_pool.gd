class_name TalentPool
extends RefCounted

const RewardPoolScript := preload("res://scripts/rewards/reward_pool.gd")


static func roll_options(
	count: int,
	seed_value: int,
	room_index: int,
	owned_ids: Array = []
) -> Array[Dictionary]:
	return RewardPoolScript._roll(
		all_talents(), count, seed_value, room_index, owned_ids, "talent"
	)


static func all_talents() -> Array[Dictionary]:
	return RewardPoolScript._definitions(&"talent")
