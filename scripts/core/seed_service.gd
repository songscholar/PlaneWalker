class_name SeedService
extends RefCounted


static func derive_seed(
	run_seed: int,
	channel: StringName,
	floor_index: int = 0,
	room_index: int = 0,
	roll_index: int = 0
) -> int:
	var stable_key := "%s|%s|%s|%s|%s" % [
		run_seed,
		str(channel),
		floor_index,
		room_index,
		roll_index,
	]
	return int(stable_key.hash())


static func make_rng(
	run_seed: int,
	channel: StringName,
	floor_index: int = 0,
	room_index: int = 0,
	roll_index: int = 0
) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = derive_seed(run_seed, channel, floor_index, room_index, roll_index)
	return rng
