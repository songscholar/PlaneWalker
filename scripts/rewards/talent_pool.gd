class_name TalentPool
extends RefCounted

const DataLoader := preload("res://scripts/rewards/reward_data_loader.gd")
const DATA_PATH := "res://data/talents/mvp_talents.json"

const TALENTS: Array[Dictionary] = [
	{
		"id": "tal_ruin_execute",
		"name": "TAL_RUIN_EXECUTE_NAME",
		"category": "talent",
		"kind": "ruin",
		"archetype": "heavy_cleave",
		"role": "route",
		"description": "TAL_RUIN_EXECUTE_DESC",
		"effects": {"heavy_execute_multiplier_bonus": 0.5, "heavy_execute_threshold": 0.3},
	},
	{
		"id": "tal_steel_recover",
		"name": "TAL_STEEL_RECOVER_NAME",
		"category": "talent",
		"kind": "steel",
		"archetype": "evasive_guard",
		"role": "route",
		"description": "TAL_STEEL_RECOVER_DESC",
		"effects": {"max_hp_bonus": 20.0, "heal": 20.0},
	},
	{
		"id": "tal_eternity_reserve",
		"name": "TAL_ETERNITY_RESERVE_NAME",
		"category": "talent",
		"kind": "eternity",
		"archetype": "rift_control",
		"role": "route",
		"description": "TAL_ETERNITY_RESERVE_DESC",
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
