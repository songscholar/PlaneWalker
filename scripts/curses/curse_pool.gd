class_name CursePool
extends RefCounted

const DataLoader := preload("res://scripts/rewards/reward_data_loader.gd")
const DATA_PATH := "res://data/curses/mvp_curses.json"

const CURSES: Array[Dictionary] = [
	{
		"id": "glass_tempo",
		"name": "GLASS_TEMPO_NAME",
		"risk": "survival",
		"description": "GLASS_TEMPO_DESC",
		"effects": {"attack_speed_multiplier": 1.25, "max_hp_multiplier": 0.78},
	},
	{
		"id": "blood_rewind",
		"name": "BLOOD_REWIND_NAME",
		"risk": "time_skill",
		"description": "BLOOD_REWIND_DESC",
		"effects": {"rewind_heal": 45.0, "rewind_self_damage": 18.0},
	},
	{
		"id": "starving_clock",
		"name": "STARVING_CLOCK_NAME",
		"risk": "economy",
		"description": "STARVING_CLOCK_DESC",
		"effects": {"time_energy_max_bonus": 40.0, "time_energy_regen_multiplier": 0.5},
	},
	{
		"id": "overclocked_stasis",
		"name": "OVERCLOCKED_STASIS_NAME",
		"risk": "time_skill",
		"description": "OVERCLOCKED_STASIS_DESC",
		"effects": {"time_stop_duration_bonus": 1.2, "time_stop_self_damage": 12.0},
	},
	{
		"id": "brittle_vitality",
		"name": "BRITTLE_VITALITY_NAME",
		"risk": "healing",
		"description": "BRITTLE_VITALITY_DESC",
		"effects": {"attack_multiplier": 1.25, "healing_multiplier": 0.5},
	},
	{
		"id": "narrow_escape",
		"name": "NARROW_ESCAPE_NAME",
		"risk": "positioning",
		"description": "NARROW_ESCAPE_DESC",
		"effects": {"dash_invulnerable_bonus": 0.15, "defense_bonus": -2.0},
	},
]


static func roll_options(count: int, seed_value: int, room_index: int, owned_ids: Array = []) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("curse:%s:%s" % [seed_value, room_index])
	var candidates := all_curses()
	_shuffle_with_rng(candidates, rng)

	var options: Array[Dictionary] = []
	for curse: Dictionary in candidates:
		if owned_ids.has(curse.get("id", "")):
			continue
		options.append(curse.duplicate(true))
		if options.size() >= count:
			break
	return options


static func all_curses() -> Array[Dictionary]:
	return DataLoader.load_array(DATA_PATH, CURSES)


static func _shuffle_with_rng(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var previous: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = previous
