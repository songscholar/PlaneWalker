class_name HealthComponent
extends Node

const DamageCalculatorScript := preload("res://scripts/combat/damage_calculator.gd")

signal damaged(amount: float, current_hp: float)
signal healed(amount: float, current_hp: float)
signal died(killer: Variant)

@export var max_hp: float = 100.0
@export var defense: float = 0.0
@export var starts_full: bool = true

var current_hp: float = 0.0
var invulnerable: bool = false
var dead: bool = false
var healing_multiplier: float = 1.0


func _ready() -> void:
	if starts_full:
		current_hp = max_hp
	else:
		current_hp = clampf(current_hp, 0.0, max_hp)


func configure_from_stats(stats: Resource) -> void:
	max_hp = stats.max_hp
	defense = stats.defense
	current_hp = max_hp
	dead = false


func apply_stat_totals(stats: Resource) -> void:
	var previous_max_hp := max_hp
	max_hp = stats.max_hp
	defense = stats.defense
	if max_hp > previous_max_hp:
		current_hp += max_hp - previous_max_hp
	current_hp = clampf(current_hp, 0.0, max_hp)


func take_damage(damage_info: RefCounted) -> float:
	if dead or invulnerable:
		return 0.0

	var owner_entity := get_parent()
	EventBus.damage_about_to_apply.emit(damage_info, owner_entity)
	EventBus.publish(EventBus.DAMAGE_ABOUT_TO_APPLY, {
		"damage_info": damage_info,
		"target": owner_entity,
	})

	var original_amount: float = damage_info.amount
	damage_info.amount = _apply_target_damage_modifiers(damage_info)
	var final_amount: float = DamageCalculatorScript.calculate(damage_info, defense)
	damage_info.amount = original_amount
	current_hp = maxf(0.0, current_hp - final_amount)
	damaged.emit(final_amount, current_hp)
	if final_amount > 0.0:
		_apply_hit_reaction(damage_info, final_amount)
	EventBus.damage_applied.emit(damage_info, owner_entity, final_amount)
	EventBus.publish(EventBus.DAMAGE_APPLIED, {
		"damage_info": damage_info,
		"target": owner_entity,
		"final_amount": final_amount,
	})

	if current_hp <= 0.0:
		_die(damage_info.attacker)
	return final_amount


func _apply_hit_reaction(damage_info: RefCounted, final_amount: float) -> void:
	var owner_entity := get_parent()
	EventBus.hit_confirmed.emit(damage_info, owner_entity, final_amount)
	EventBus.publish(EventBus.HIT_CONFIRMED, {
		"damage_info": damage_info,
		"target": owner_entity,
		"final_amount": final_amount,
	})
	if damage_info.knockback.length_squared() > 0.0 and owner_entity.has_method("apply_knockback"):
		owner_entity.apply_knockback(damage_info.knockback)
	if damage_info.tags.has("weapon:sword"):
		CombatFeedback.request_hit_pause()


func heal(amount: float) -> float:
	if dead:
		return 0.0
	var previous_hp := current_hp
	current_hp = minf(max_hp, current_hp + amount * healing_multiplier)
	var healed_amount := current_hp - previous_hp
	if healed_amount > 0.0:
		healed.emit(healed_amount, current_hp)
	return healed_amount


func lose_health(amount: float, source: Variant = null) -> float:
	if dead or amount <= 0.0:
		return 0.0
	var final_amount := minf(current_hp, amount)
	current_hp = maxf(0.0, current_hp - final_amount)
	damaged.emit(final_amount, current_hp)
	if current_hp <= 0.0:
		_die(source)
	return final_amount


func _apply_target_damage_modifiers(damage_info: RefCounted) -> float:
	var amount: float = damage_info.amount
	var owner_entity := get_parent()
	if owner_entity.has_method("get_weakpoint_damage_bonus"):
		var weakpoint_bonus: float = owner_entity.get_weakpoint_damage_bonus(damage_info)
		if weakpoint_bonus > 0.0:
			amount *= 1.0 + weakpoint_bonus
	if damage_info.tags.has("talent:ruin_execute") and _hp_ratio() <= _heavy_execute_threshold(damage_info):
		amount *= 1.0 + _heavy_execute_bonus(damage_info)
	return amount


func _hp_ratio() -> float:
	return current_hp / maxf(1.0, max_hp)


func _heavy_execute_bonus(damage_info: RefCounted) -> float:
	if damage_info.source != null:
		return float(damage_info.source.get("heavy_execute_multiplier_bonus"))
	return 0.0


func _heavy_execute_threshold(damage_info: RefCounted) -> float:
	if damage_info.source != null:
		return float(damage_info.source.get("heavy_execute_threshold"))
	return 0.3


func apply_invulnerability(duration: float) -> void:
	if duration <= 0.0:
		return
	invulnerable = true
	await get_tree().create_timer(duration).timeout
	invulnerable = false


func is_alive() -> bool:
	return not dead


func _die(killer: Variant) -> void:
	if dead:
		return
	dead = true
	EventBus.entity_died.emit(get_parent(), killer)
	EventBus.publish(EventBus.ENTITY_DIED, {
		"entity": get_parent(),
		"killer": killer,
	})
	died.emit(killer)
