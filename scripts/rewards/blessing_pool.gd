class_name BlessingPool
extends RefCounted

const RewardPoolScript := preload("res://scripts/rewards/reward_pool.gd")


static func roll_options(
	count: int,
	seed_value: int,
	room_index: int,
	owned_ids: Array = []
) -> Array[Dictionary]:
	return RewardPoolScript._roll(
		all_blessings(), count, seed_value, room_index, owned_ids, "blessing"
	)


static func all_blessings() -> Array[Dictionary]:
	return RewardPoolScript._definitions(&"blessing")
