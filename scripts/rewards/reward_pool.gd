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
	{
		"id": "frozen_burst",
		"name": "Frozen Burst",
		"kind": "time",
		"archetype": "time_stop_burst",
		"role": "starter",
		"description": "Time Stop lasts 0.75 seconds longer and costs 10% less energy.",
		"effects": {"time_stop_duration_bonus": 0.75, "time_stop_cost_multiplier": 0.9},
	},
	{
		"id": "rewind_echo",
		"name": "Rewind Echo",
		"kind": "time",
		"archetype": "rewind_echo",
		"role": "starter",
		"description": "Rewind heals 28 HP after returning to an older position.",
		"effects": {"rewind_heal": 28.0},
	},
	{
		"id": "accelerated_combo",
		"name": "Accelerated Combo",
		"kind": "weapon",
		"archetype": "accelerated_combo",
		"role": "starter",
		"description": "Sword attacks are 8% faster and combo finishers deal 35% more damage.",
		"effects": {"attack_speed_multiplier": 1.08, "combo_finisher_multiplier_bonus": 0.35},
	},
	{
		"id": "cleaving_moment",
		"name": "Cleaving Moment",
		"kind": "weapon",
		"archetype": "heavy_cleave",
		"role": "starter",
		"description": "Heavy sword attacks deal 40% more damage.",
		"effects": {"heavy_damage_multiplier_bonus": 0.4},
	},
	{
		"id": "rift_engine",
		"name": "Rift Engine",
		"kind": "time",
		"archetype": "rift_control",
		"role": "starter",
		"description": "Gain 20 maximum time energy and regenerate 0.8 more energy each second.",
		"effects": {"time_energy_max_bonus": 20.0, "time_energy_regen_bonus": 0.8},
	},
	{
		"id": "void_brink",
		"name": "Void Brink",
		"kind": "risk",
		"archetype": "low_hp_void",
		"role": "starter",
		"description": "When below 35% HP, sword attacks deal 45% more damage.",
		"effects": {"low_hp_damage_multiplier_bonus": 0.45},
	},
	{
		"id": "evasive_guard_route",
		"name": "Evasive Guard Route",
		"kind": "survival",
		"archetype": "evasive_guard",
		"role": "starter",
		"description": "Gain 3 defense and extend dash invulnerability by 0.08 seconds.",
		"effects": {"defense_bonus": 3.0, "dash_invulnerable_bonus": 0.08},
	},
	{
		"id": "tempo_barrage",
		"name": "Tempo Barrage",
		"kind": "weapon",
		"archetype": "barrage_tempo",
		"role": "starter",
		"description": "Sword attacks are 10% faster and gain 15 maximum time energy.",
		"effects": {"attack_speed_multiplier": 1.1, "time_energy_max_bonus": 15.0},
	},
]

const ARCHETYPE_LABELS := {
	"time_stop_burst": "Time Stop Burst",
	"rewind_echo": "Rewind Echo",
	"accelerated_combo": "Accelerated Combo",
	"heavy_cleave": "Heavy Cleave",
	"rift_control": "Rift Control",
	"low_hp_void": "Low HP Void",
	"evasive_guard": "Evasive Guard",
	"barrage_tempo": "Barrage Tempo",
}

const ROLE_LABELS := {
	"starter": "Starter",
	"payoff": "Payoff",
	"risk": "Risk",
}


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


static func get_archetype_label(archetype: String) -> String:
	return str(ARCHETYPE_LABELS.get(archetype, archetype.capitalize()))


static func get_role_label(role: String) -> String:
	return str(ROLE_LABELS.get(role, role.capitalize()))


static func get_reward_route_label(reward_data: Dictionary) -> String:
	var archetype := str(reward_data.get("archetype", ""))
	var role := str(reward_data.get("role", ""))
	if archetype.is_empty() and role.is_empty():
		return str(reward_data.get("kind", "reward")).capitalize()
	if role.is_empty():
		return get_archetype_label(archetype)
	if archetype.is_empty():
		return get_role_label(role)
	return "%s - %s" % [get_role_label(role), get_archetype_label(archetype)]
