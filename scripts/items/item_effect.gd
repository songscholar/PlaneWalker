class_name ItemEffect
extends RefCounted

const LEGACY_WEAPON_EFFECT_IDS := [
	&"combo_finisher_multiplier_bonus",
	&"heavy_damage_multiplier_bonus",
	&"heavy_execute_multiplier_bonus",
	&"heavy_execute_threshold",
	&"low_hp_damage_multiplier_bonus",
	&"bow_charge_rate_bonus",
	&"bow_full_charge_damage_multiplier_bonus",
	&"bow_pierce_bonus",
]


static func apply_to_player(player: Node, effects: Dictionary) -> void:
	if player == null or effects.is_empty():
		return

	if effects.has("attack_multiplier"):
		player.stats.attack *= float(effects["attack_multiplier"])
	if effects.has("attack_speed_multiplier"):
		player.stats.attack_speed *= float(effects["attack_speed_multiplier"])
	if effects.has("max_hp_bonus"):
		player.stats.max_hp += float(effects["max_hp_bonus"])
	if effects.has("max_hp_multiplier"):
		player.stats.max_hp *= float(effects["max_hp_multiplier"])
	if effects.has("defense_bonus"):
		player.stats.defense += float(effects["defense_bonus"])
	if effects.has("time_energy_max_bonus"):
		player.stats.time_energy_max += float(effects["time_energy_max_bonus"])
	if effects.has("time_energy_regen_bonus"):
		player.stats.time_energy_regen += float(effects["time_energy_regen_bonus"])
	if effects.has("time_energy_regen_multiplier"):
		player.stats.time_energy_regen *= float(effects["time_energy_regen_multiplier"])
	if effects.has("time_stop_duration_bonus"):
		player.time_manager.time_stop_duration_bonus += float(effects["time_stop_duration_bonus"])
	if effects.has("time_stop_cost_multiplier"):
		player.time_manager.time_stop_cost_multiplier *= float(effects["time_stop_cost_multiplier"])
	if effects.has("time_stop_weakpoint_damage_bonus"):
		player.time_manager.time_stop_weakpoint_damage_bonus += float(effects["time_stop_weakpoint_damage_bonus"])
	if effects.has("time_stop_weakpoint_duration"):
		player.time_manager.time_stop_weakpoint_duration = maxf(player.time_manager.time_stop_weakpoint_duration, float(effects["time_stop_weakpoint_duration"]))
	if effects.has("time_stop_self_damage"):
		player.time_manager.time_stop_self_damage += float(effects["time_stop_self_damage"])
	if effects.has("rewind_cost_multiplier"):
		player.time_manager.rewind_cost_multiplier *= float(effects["rewind_cost_multiplier"])
	if effects.has("rewind_heal"):
		player.time_manager.rewind_heal += float(effects["rewind_heal"])
	if effects.has("rewind_echo_enabled"):
		player.time_manager.rewind_echo_enabled = bool(effects["rewind_echo_enabled"])
	if effects.has("rewind_path_hit_multiplier"):
		player.time_manager.rewind_path_hit_multiplier = maxf(player.time_manager.rewind_path_hit_multiplier, float(effects["rewind_path_hit_multiplier"]))
	if effects.has("rewind_self_damage"):
		player.time_manager.rewind_self_damage += float(effects["rewind_self_damage"])
	if effects.has("time_rift_cost_multiplier"):
		player.time_manager.time_rift_cost_multiplier *= float(effects["time_rift_cost_multiplier"])
	if effects.has("time_rift_duration_bonus"):
		player.time_manager.time_rift_duration_bonus += float(effects["time_rift_duration_bonus"])
	if effects.has("time_rift_radius_bonus"):
		player.time_manager.time_rift_radius_bonus += float(effects["time_rift_radius_bonus"])
	if effects.has("time_rift_slow_bonus"):
		player.time_manager.time_rift_slow_bonus += float(effects["time_rift_slow_bonus"])
	if effects.has("time_accelerate_cost_multiplier"):
		player.time_manager.time_accelerate_cost_multiplier *= float(effects["time_accelerate_cost_multiplier"])
	if effects.has("time_accelerate_duration_bonus"):
		player.time_manager.time_accelerate_duration_bonus += float(effects["time_accelerate_duration_bonus"])
	if effects.has("time_accelerate_multiplier_bonus"):
		player.time_manager.time_accelerate_multiplier_bonus += float(effects["time_accelerate_multiplier_bonus"])
	if effects.has("low_energy_regen_multiplier"):
		player.time_manager.low_energy_regen_multiplier = maxf(player.time_manager.low_energy_regen_multiplier, float(effects["low_energy_regen_multiplier"]))
	if effects.has("low_energy_threshold"):
		player.time_manager.low_energy_threshold = maxf(player.time_manager.low_energy_threshold, float(effects["low_energy_threshold"]))
	_apply_weapon_effects(player, effects)
	if effects.has("dash_invulnerable_bonus"):
		player._dash_invulnerable_bonus += float(effects["dash_invulnerable_bonus"])
	if effects.has("healing_multiplier"):
		player.health.healing_multiplier *= float(effects["healing_multiplier"])

	player._apply_stats_to_components(false)

	if effects.has("heal"):
		player.health.heal(float(effects["heal"]))
	if effects.has("time_energy_restore"):
		player.time_manager.restore_energy(float(effects["time_energy_restore"]))
	if effects.has("invulnerable_duration"):
		player.health.apply_invulnerability(float(effects["invulnerable_duration"]))


static func _apply_weapon_effects(player: Node, effects: Dictionary) -> void:
	if not player.has_method("apply_weapon_effect"):
		return
	for effect_id: StringName in LEGACY_WEAPON_EFFECT_IDS:
		if effects.has(effect_id):
			player.call("apply_weapon_effect", effect_id, effects[effect_id])
