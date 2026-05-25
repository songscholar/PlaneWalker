class_name ItemEffect
extends RefCounted


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
	if effects.has("combo_finisher_multiplier_bonus"):
		player.sword_weapon.combo_finisher_multiplier_bonus += float(effects["combo_finisher_multiplier_bonus"])
	if effects.has("heavy_damage_multiplier_bonus"):
		player.sword_weapon.heavy_damage_multiplier_bonus += float(effects["heavy_damage_multiplier_bonus"])
	if effects.has("heavy_execute_multiplier_bonus"):
		player.sword_weapon.heavy_execute_multiplier_bonus += float(effects["heavy_execute_multiplier_bonus"])
	if effects.has("heavy_execute_threshold"):
		player.sword_weapon.heavy_execute_threshold = float(effects["heavy_execute_threshold"])
	if effects.has("low_hp_damage_multiplier_bonus"):
		player.sword_weapon.low_hp_damage_multiplier_bonus += float(effects["low_hp_damage_multiplier_bonus"])
	if effects.has("bow_charge_rate_bonus"):
		player.bow_weapon.charge_rate_bonus += float(effects["bow_charge_rate_bonus"])
	if effects.has("bow_full_charge_damage_multiplier_bonus"):
		player.bow_weapon.full_charge_damage_multiplier_bonus += float(effects["bow_full_charge_damage_multiplier_bonus"])
	if effects.has("bow_pierce_bonus"):
		player.bow_weapon.pierce_bonus += int(effects["bow_pierce_bonus"])
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
