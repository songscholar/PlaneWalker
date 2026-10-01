class_name DamageCalculator
extends RefCounted


static func calculate(
	damage_info: RefCounted,
	defense: float = 0.0,
	critical_context: Dictionary = {}
) -> float:
	return apply_flat_defense(
		critical_amount(damage_info, float(damage_info.amount), critical_context),
		defense
	)


static func critical_amount(
	damage_info: RefCounted,
	amount: float,
	critical_context: Dictionary = {}
) -> float:
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	if (
		damage_info.can_crit
		and damage_info.crit_chance > 0.0
		and deterministic_critical_roll(damage_info, critical_context) < damage_info.crit_chance
	):
		return amount * damage_info.crit_multiplier
	return amount


static func deterministic_critical_roll(
	damage_info: RefCounted,
	critical_context: Dictionary = {}
) -> float:
	if damage_info == null:
		return 1.0
	var material: Array[Variant] = []
	if not critical_context.is_empty():
		if critical_context.has("critical_outcome"):
			if (
				critical_context.size() != 1
				or typeof(critical_context["critical_outcome"]) != TYPE_BOOL
			):
				return 1.0
			return 0.0 if bool(critical_context["critical_outcome"]) else 1.0
		if not _valid_seeded_context(critical_context):
			return 1.0
		material.append_array([
			int(critical_context["seed"]),
			str(critical_context["channel"]),
			int(critical_context["roll_index"]),
		])
	material.append_array([
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
	])
	var digest := JSON.stringify(material, "", false).sha256_text()
	return float(digest.substr(0, 8).hex_to_int()) / 4294967296.0


static func _valid_seeded_context(value: Dictionary) -> bool:
	if value.size() != 3:
		return false
	for field: String in ["seed", "channel", "roll_index"]:
		if not value.has(field):
			return false
	if typeof(value["seed"]) != TYPE_INT:
		return false
	if typeof(value["channel"]) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var channel := str(value["channel"]).strip_edges()
	if channel.is_empty() or channel.length() > 64:
		return false
	return typeof(value["roll_index"]) == TYPE_INT and int(value["roll_index"]) >= 0


static func apply_flat_defense(amount: float, defense: float = 0.0) -> float:
	if not is_finite(amount) or amount <= 0.0:
		return 1.0
	var safe_defense := maxf(0.0, defense) if is_finite(defense) else 0.0
	return maxf(1.0, amount - safe_defense)
