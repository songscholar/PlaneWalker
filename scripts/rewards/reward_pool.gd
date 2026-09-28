class_name RewardPool
extends RefCounted

const DataLoader := preload("res://scripts/rewards/reward_data_loader.gd")
const DATA_PATH := "res://data/items/mvp_items.json"

const REWARDS: Array[Dictionary] = [
	{
		"id": "sword_edge",
		"name": "SWORD_EDGE_NAME",
		"kind": "weapon",
		"description": "SWORD_EDGE_DESC",
		"effects": {"attack_multiplier": 1.18},
	},
	{
		"id": "quickened_blade",
		"name": "QUICKENED_BLADE_NAME",
		"kind": "weapon",
		"description": "QUICKENED_BLADE_DESC",
		"effects": {"attack_speed_multiplier": 1.15},
	},
	{
		"id": "chronal_battery",
		"name": "CHRONAL_BATTERY_NAME",
		"kind": "time",
		"description": "CHRONAL_BATTERY_DESC",
		"effects": {"time_energy_max_bonus": 25.0, "time_energy_restore": 25.0},
	},
	{
		"id": "rift_current",
		"name": "RIFT_CURRENT_NAME",
		"kind": "time",
		"description": "RIFT_CURRENT_DESC",
		"effects": {"time_energy_regen_bonus": 1.25},
	},
	{
		"id": "rewind_salve",
		"name": "REWIND_SALVE_NAME",
		"kind": "survival",
		"description": "REWIND_SALVE_DESC",
		"effects": {"max_hp_bonus": 20.0, "heal": 35.0},
	},
	{
		"id": "tempered_guard",
		"name": "TEMPERED_GUARD_NAME",
		"kind": "survival",
		"description": "TEMPERED_GUARD_DESC",
		"effects": {"defense_bonus": 2.0, "invulnerable_duration": 1.0},
	},
	{
		"id": "frozen_burst",
		"name": "FROZEN_BURST_NAME",
		"kind": "time",
		"archetype": "time_stop_burst",
		"role": "starter",
		"description": "FROZEN_BURST_DESC",
		"effects": {"time_stop_duration_bonus": 0.75, "time_stop_cost_multiplier": 0.9},
	},
	{
		"id": "rewind_echo",
		"name": "REWIND_ECHO_NAME",
		"kind": "time",
		"archetype": "rewind_echo",
		"role": "starter",
		"description": "REWIND_ECHO_DESC",
		"effects": {"rewind_heal": 28.0},
	},
	{
		"id": "accelerated_combo",
		"name": "ACCELERATED_COMBO_NAME",
		"kind": "weapon",
		"archetype": "accelerated_combo",
		"role": "starter",
		"description": "ACCELERATED_COMBO_DESC",
		"effects": {"attack_speed_multiplier": 1.08, "combo_finisher_multiplier_bonus": 0.35},
	},
	{
		"id": "cleaving_moment",
		"name": "CLEAVING_MOMENT_NAME",
		"kind": "weapon",
		"archetype": "heavy_cleave",
		"role": "starter",
		"description": "CLEAVING_MOMENT_DESC",
		"effects": {"heavy_damage_multiplier_bonus": 0.4},
	},
	{
		"id": "rift_engine",
		"name": "RIFT_ENGINE_NAME",
		"kind": "time",
		"archetype": "rift_control",
		"role": "starter",
		"description": "RIFT_ENGINE_DESC",
		"effects": {"time_energy_max_bonus": 20.0, "time_energy_regen_bonus": 0.8},
	},
	{
		"id": "void_brink",
		"name": "VOID_BRINK_NAME",
		"kind": "risk",
		"archetype": "low_hp_void",
		"role": "starter",
		"description": "VOID_BRINK_DESC",
		"effects": {"low_hp_damage_multiplier_bonus": 0.45},
	},
	{
		"id": "evasive_guard_route",
		"name": "EVASIVE_GUARD_ROUTE_NAME",
		"kind": "survival",
		"archetype": "evasive_guard",
		"role": "starter",
		"description": "EVASIVE_GUARD_ROUTE_DESC",
		"effects": {"defense_bonus": 3.0, "dash_invulnerable_bonus": 0.08},
	},
	{
		"id": "tempo_barrage",
		"name": "TEMPO_BARRAGE_NAME",
		"kind": "weapon",
		"archetype": "barrage_tempo",
		"role": "starter",
		"description": "TEMPO_BARRAGE_DESC",
		"effects": {"attack_speed_multiplier": 1.1, "time_energy_max_bonus": 15.0},
	},
	{
		"id": "piercing_draw",
		"name": "PIERCING_DRAW_NAME",
		"kind": "weapon",
		"archetype": "piercing_draw",
		"role": "starter",
		"description": "PIERCING_DRAW_DESC",
		"effects": {"bow_charge_rate_bonus": 0.25, "bow_pierce_bonus": 1},
	},
	{
		"id": "focused_draw",
		"name": "FOCUSED_DRAW_NAME",
		"kind": "weapon",
		"archetype": "piercing_draw",
		"role": "payoff",
		"description": "FOCUSED_DRAW_DESC",
		"effects": {"bow_charge_rate_bonus": 0.15, "bow_full_charge_damage_multiplier_bonus": 0.35},
	},
	{
		"id": "rift_snare",
		"name": "RIFT_SNARE_NAME",
		"kind": "time",
		"archetype": "rift_control",
		"role": "payoff",
		"description": "RIFT_SNARE_DESC",
		"effects": {
			"time_rift_duration_bonus": 1.0,
			"time_rift_radius_bonus": 22.0,
			"time_rift_slow_bonus": 0.12,
		},
	},
	{
		"id": "rift_conductor",
		"name": "RIFT_CONDUCTOR_NAME",
		"kind": "time",
		"archetype": "rift_control",
		"role": "payoff",
		"description": "RIFT_CONDUCTOR_DESC",
		"effects": {"time_rift_cost_multiplier": 0.85, "time_energy_regen_bonus": 0.6},
	},
	{
		"id": "accelerant_window",
		"name": "ACCELERANT_WINDOW_NAME",
		"kind": "time",
		"archetype": "accelerated_combo",
		"role": "payoff",
		"description": "ACCELERANT_WINDOW_DESC",
		"effects": {
			"time_accelerate_duration_bonus": 0.8,
			"time_accelerate_multiplier_bonus": 0.2,
		},
	},
	{
		"id": "efficient_overdrive",
		"name": "EFFICIENT_OVERDRIVE_NAME",
		"kind": "time",
		"archetype": "accelerated_combo",
		"role": "payoff",
		"description": "EFFICIENT_OVERDRIVE_DESC",
		"effects": {"time_accelerate_cost_multiplier": 0.85, "attack_speed_multiplier": 1.06},
	},
]

const ARCHETYPE_LABELS := {
	"time_stop_burst": "ARCHETYPE_TIME_STOP_BURST",
	"rewind_echo": "ARCHETYPE_REWIND_ECHO",
	"accelerated_combo": "ARCHETYPE_ACCELERATED_COMBO",
	"heavy_cleave": "ARCHETYPE_HEAVY_CLEAVE",
	"rift_control": "ARCHETYPE_RIFT_CONTROL",
	"low_hp_void": "ARCHETYPE_LOW_HP_VOID",
	"evasive_guard": "ARCHETYPE_EVASIVE_GUARD",
	"barrage_tempo": "ARCHETYPE_BARRAGE_TEMPO",
	"piercing_draw": "ARCHETYPE_PIERCING_DRAW",
}

const ROLE_LABELS := {
	"starter": "ROLE_STARTER",
	"payoff": "ROLE_PAYOFF",
	"risk": "ROLE_RISK",
}


static func roll_options(count: int, seed_value: int, room_index: int, owned_ids: Array = []) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%s" % [seed_value, room_index])
	var candidates := all_rewards()
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


static func all_rewards() -> Array[Dictionary]:
	return DataLoader.load_array(DATA_PATH, REWARDS)


static func _shuffle_with_rng(values: Array, rng: RandomNumberGenerator) -> void:
	for index: int in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var previous: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = previous


static func get_archetype_label(archetype: String) -> String:
	var key := str(ARCHETYPE_LABELS.get(archetype, "ARCHETYPE_" + archetype.to_upper()))
	return TranslationServer.translate(key)


static func get_role_label(role: String) -> String:
	var key := str(ROLE_LABELS.get(role, "ROLE_" + role.to_upper()))
	return TranslationServer.translate(key)


static func get_reward_route_label(reward_data: Dictionary) -> String:
	var archetype := str(reward_data.get("archetype", ""))
	var role := str(reward_data.get("role", ""))
	if archetype.is_empty() and role.is_empty():
		var kind := str(reward_data.get("kind", ""))
		if kind.is_empty():
			return TranslationServer.translate("UI_FALLBACK_REWARD")
		return TranslationServer.translate("KIND_" + kind.to_upper())
	if role.is_empty():
		return get_archetype_label(archetype)
	if archetype.is_empty():
		return get_role_label(role)
	return "%s - %s" % [get_role_label(role), get_archetype_label(archetype)]
