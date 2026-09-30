class_name DamageCalculator
extends RefCounted


static func calculate(damage_info: RefCounted, defense: float = 0.0) -> float:
	return apply_flat_defense(critical_amount(damage_info, float(damage_info.amount)), defense)


static func critical_amount(damage_info: RefCounted, amount: float) -> float:
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	if (
		damage_info.can_crit
		and damage_info.crit_chance > 0.0
		and deterministic_critical_roll(damage_info) < damage_info.crit_chance
	):
		return amount * damage_info.crit_multiplier
	return amount


static func deterministic_critical_roll(damage_info: RefCounted) -> float:
	if damage_info == null:
		return 1.0
	var material: Array[Variant] = [
		str(damage_info.run_id),
		str(damage_info.target_id),
		str(damage_info.hostile_source_id),
		int(damage_info.attack_generation),
		int(damage_info.source_generation),
		int(damage_info.action_token),
		int(damage_info.hit_index),
		float(damage_info.amount),
		int(damage_info.damage_type),
		damage_info.tags,
	]
	var digest := JSON.stringify(material, "", false).sha256_text()
	return float(digest.substr(0, 8).hex_to_int()) / 4294967296.0


static func apply_flat_defense(amount: float, defense: float = 0.0) -> float:
	if not is_finite(amount) or amount <= 0.0:
		return 1.0
	var safe_defense := maxf(0.0, defense) if is_finite(defense) else 0.0
	return maxf(1.0, amount - safe_defense)
