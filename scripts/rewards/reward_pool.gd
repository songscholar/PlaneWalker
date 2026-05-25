class_name RewardPool
extends RefCounted

const REWARDS: Array[Dictionary] = [
	{
		"id": "sword_edge",
		"name": "Sword Edge",
		"kind": "weapon",
		"description": "Sword attacks deal 18% more damage.",
		"effects": {"attack_multiplier": 1.18},
	},
	{
		"id": "quickened_blade",
		"name": "Quickened Blade",
		"kind": "weapon",
		"description": "Sword attack timings are 15% faster.",
		"effects": {"attack_speed_multiplier": 1.15},
	},
	{
		"id": "chronal_battery",
		"name": "Chronal Battery",
		"kind": "time",
		"description": "Gain 25 maximum time energy and refill that amount.",
		"effects": {"time_energy_max_bonus": 25.0, "time_energy_restore": 25.0},
	},
	{
		"id": "rift_current",
		"name": "Rift Current",
		"kind": "time",
		"description": "Time energy regenerates 1.25 faster each second.",
		"effects": {"time_energy_regen_bonus": 1.25},
	},
	{
		"id": "rewind_salve",
		"name": "Rewind Salve",
		"kind": "survival",
		"description": "Heal 35 now and increase maximum HP by 20.",
		"effects": {"max_hp_bonus": 20.0, "heal": 35.0},
	},
	{
		"id": "tempered_guard",
		"name": "Tempered Guard",
		"kind": "survival",
		"description": "Gain 2 defense and a short invulnerable window.",
		"effects": {"defense_bonus": 2.0, "invulnerable_duration": 1.0},
	},
]


static func roll_options(count: int, seed_value: int, room_index: int, owned_ids: Array = []) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%s" % [seed_value, room_index])
	var candidates := REWARDS.duplicate(true)
	_shuffle_with_rng(candidates, rng)

	var options: Array[Dictionary] = []
	for reward: Dictionary in candidates:
		if owned_ids.has(reward.get("id", "")):
			continue
		options.append(reward.duplicate(true))
		if options.size() >= count:
			break

	if options.size() < count:
		for reward: Dictionary in candidates:
			options.append(reward.duplicate(true))
			if options.size() >= count:
				break
	return options


static func _shuffle_with_rng(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var previous: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = previous
