class_name TalentPool
extends RefCounted

const DataLoader := preload("res://scripts/rewards/reward_data_loader.gd")
const DATA_PATH := "res://data/talents/mvp_talents.json"

const TALENTS: Array[Dictionary] = [
	{
		"id": "tal_ruin_execute",
		"name": "Ruin Execute",
		"category": "talent",
		"kind": "ruin",
		"archetype": "heavy_cleave",
		"role": "route",
		"description": "Heavy sword attacks deal 50% more damage to enemies below 30% HP.",
		"effects": {"heavy_execute_multiplier_bonus": 0.5, "heavy_execute_threshold": 0.3},
	},
	{
		"id": "tal_steel_recover",
		"name": "Steel Recovery",
		"category": "talent",
		"kind": "steel",
		"archetype": "evasive_guard",
		"role": "route",
		"description": "Gain 20 maximum HP and heal 20 immediately.",
		"effects": {"max_hp_bonus": 20.0, "heal": 20.0},
	},
	{
		"id": "tal_eternity_reserve",
		"name": "Eternity Reserve",
		"category": "talent",
		"kind": "eternity",
		"archetype": "rift_control",
		"role": "route",
		"description": "When time energy is below 30, regeneration is doubled.",
		"effects": {"low_energy_regen_multiplier": 2.0, "low_energy_threshold": 30.0},
	},
]


static func roll_options(count: int, seed_value: int, room_index: int, owned_ids: Array = []) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("talent:%s:%s" % [seed_value, room_index])
	var candidates := all_talents()
	_shuffle_with_rng(candidates, rng)

	var options: Array[Dictionary] = []
	for talent: Dictionary in candidates:
		if owned_ids.has(talent.get("id", "")):
			continue
		options.append(talent.duplicate(true))
		if options.size() >= count:
			break
	return options


static func all_talents() -> Array[Dictionary]:
	return DataLoader.load_array(DATA_PATH, TALENTS)


static func _shuffle_with_rng(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var previous: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = previous
