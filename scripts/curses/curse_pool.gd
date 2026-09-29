class_name CursePool
extends RefCounted

const RewardPoolScript := preload("res://scripts/rewards/reward_pool.gd")


static func roll_options(
	count: int,
	seed_value: int,
	room_index: int,
	owned_ids: Array = []
) -> Array[Dictionary]:
	return RewardPoolScript._roll(
		all_curses(), count, seed_value, room_index, owned_ids, "curse"
	)


static func all_curses() -> Array[Dictionary]:
	return RewardPoolScript._definitions(&"curse")
