class_name BlessingPool
extends RefCounted

const DataLoader := preload("res://scripts/rewards/reward_data_loader.gd")
const DATA_PATH := "res://data/blessings/mvp_blessings.json"

const BLESSINGS: Array[Dictionary] = [
	{
		"id": "bls_stop_weakpoint",
		"name": "BLS_STOP_WEAKPOINT_NAME",
		"category": "blessing",
		"kind": "time",
		"archetype": "time_stop_burst",
		"role": "payoff",
		"description": "BLS_STOP_WEAKPOINT_DESC",
		"effects": {"time_stop_weakpoint_damage_bonus": 0.35, "time_stop_weakpoint_duration": 3.0},
	},
	{
		"id": "bls_rewind_path",
		"name": "BLS_REWIND_PATH_NAME",
		"category": "blessing",
		"kind": "time",
		"archetype": "rewind_echo",
		"role": "payoff",
		"description": "BLS_REWIND_PATH_DESC",
		"effects": {"rewind_cost_multiplier": 0.9, "rewind_heal": 18.0},
	},
	{
		"id": "bls_sword_tempo",
		"name": "BLS_SWORD_TEMPO_NAME",
		"category": "blessing",
		"kind": "weapon",
		"archetype": "accelerated_combo",
		"role": "payoff",
		"description": "BLS_SWORD_TEMPO_DESC",
		"effects": {"attack_speed_multiplier": 1.08, "combo_finisher_multiplier_bonus": 0.2},
	},
	{
		"id": "bls_survive_thread",
		"name": "BLS_SURVIVE_THREAD_NAME",
		"category": "blessing",
		"kind": "survival",
		"archetype": "evasive_guard",
		"role": "payoff",
		"description": "BLS_SURVIVE_THREAD_DESC",
		"effects": {"max_hp_bonus": 20.0, "time_energy_max_bonus": 15.0, "invulnerable_duration": 0.8},
	},
]


static func roll_options(count: int, seed_value: int, room_index: int, owned_ids: Array = []) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("blessing:%s:%s" % [seed_value, room_index])
	var candidates := all_blessings()
	_shuffle_with_rng(candidates, rng)

	var options: Array[Dictionary] = []
	for blessing: Dictionary in candidates:
		if owned_ids.has(blessing.get("id", "")):
			continue
		options.append(blessing.duplicate(true))
		if options.size() >= count:
			break
	return options


static func all_blessings() -> Array[Dictionary]:
	return DataLoader.load_array(DATA_PATH, BLESSINGS)


static func _shuffle_with_rng(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var previous: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = previous
