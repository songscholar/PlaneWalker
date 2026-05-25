class_name BlessingPool
extends RefCounted

const BLESSINGS: Array[Dictionary] = [
	{
		"id": "bls_stop_weakpoint",
		"name": "Stasis Weakpoint",
		"category": "blessing",
		"kind": "time",
		"archetype": "time_stop_burst",
		"role": "payoff",
		"description": "Enemies touched by Time Stop take 35% more heavy or finisher sword damage for 3 seconds.",
		"effects": {"time_stop_weakpoint_damage_bonus": 0.35, "time_stop_weakpoint_duration": 3.0},
	},
	{
		"id": "bls_rewind_path",
		"name": "Rewind Pathmark",
		"category": "blessing",
		"kind": "time",
		"archetype": "rewind_echo",
		"role": "payoff",
		"description": "Rewind costs 10% less and heals 18 HP after returning.",
		"effects": {"rewind_cost_multiplier": 0.9, "rewind_heal": 18.0},
	},
	{
		"id": "bls_sword_tempo",
		"name": "Sword Tempo Loop",
		"category": "blessing",
		"kind": "weapon",
		"archetype": "accelerated_combo",
		"role": "payoff",
		"description": "Sword attacks are 8% faster and combo finishers deal 20% more damage.",
		"effects": {"attack_speed_multiplier": 1.08, "combo_finisher_multiplier_bonus": 0.2},
	},
	{
		"id": "bls_survive_thread",
		"name": "Survival Thread",
		"category": "blessing",
		"kind": "survival",
		"archetype": "evasive_guard",
		"role": "payoff",
		"description": "Gain 20 maximum HP, 15 maximum time energy, and a short invulnerable window.",
		"effects": {"max_hp_bonus": 20.0, "time_energy_max_bonus": 15.0, "invulnerable_duration": 0.8},
	},
]


static func roll_options(count: int, seed_value: int, room_index: int, owned_ids: Array = []) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("blessing:%s:%s" % [seed_value, room_index])
	var candidates := BLESSINGS.duplicate(true)
	_shuffle_with_rng(candidates, rng)

	var options: Array[Dictionary] = []
	for blessing: Dictionary in candidates:
		if owned_ids.has(blessing.get("id", "")):
			continue
		options.append(blessing.duplicate(true))
		if options.size() >= count:
			break
	return options


static func _shuffle_with_rng(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var previous: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = previous
