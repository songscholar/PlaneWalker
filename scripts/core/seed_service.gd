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


static func derive_node_seed(
	run_seed: int,
	floor_id: StringName,
	node_id: StringName,
	channel: StringName,
	roll_index: int = 0
) -> int:
	var node_channel := StringName("floor_plan_v1:%s:%s:%s" % [
		str(floor_id),
		str(node_id),
		str(channel),
	])
	return derive_seed(run_seed, node_channel, 0, 0, roll_index)


static func derive_weapon_action_seed(
	run_seed: int,
	profile_id: StringName,
	action_id: StringName,
	payload_id: StringName,
	action_token: int,
	outcome_index: int
) -> int:
	var channel := StringName("weapon_action_v1:%s:%s:%s:%d" % [
		str(profile_id),
		str(action_id),
		str(payload_id),
		action_token,
	])
	return derive_seed(run_seed, channel, 0, 0, outcome_index)
