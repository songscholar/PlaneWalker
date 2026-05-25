class_name DamageCalculator
extends RefCounted


static func calculate(damage_info: DamageInfo, defense: float = 0.0) -> float:
	var final_amount := damage_info.amount
	if damage_info.can_crit and damage_info.crit_chance > 0.0 and randf() < damage_info.crit_chance:
		final_amount *= damage_info.crit_multiplier
	final_amount -= defense
	return maxf(1.0, final_amount)
