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


func take_damage(damage_info: RefCounted) -> float:
	if dead or invulnerable:
		return 0.0

	var owner_entity := get_parent()
	EventBus.damage_about_to_apply.emit(damage_info, owner_entity)
	EventBus.publish(EventBus.DAMAGE_ABOUT_TO_APPLY, {
		"damage_info": damage_info,
		"target": owner_entity,
	})

	var final_amount: float = DamageCalculatorScript.calculate(damage_info, defense)
	current_hp = maxf(0.0, current_hp - final_amount)
	damaged.emit(final_amount, current_hp)
	EventBus.damage_applied.emit(damage_info, owner_entity, final_amount)
	EventBus.publish(EventBus.DAMAGE_APPLIED, {
		"damage_info": damage_info,
		"target": owner_entity,
		"final_amount": final_amount,
	})

	if current_hp <= 0.0:
		_die(damage_info.attacker)
	return final_amount


func heal(amount: float) -> float:
	if dead:
		return 0.0
	var previous_hp := current_hp
	current_hp = minf(max_hp, current_hp + amount)
	var healed_amount := current_hp - previous_hp
	if healed_amount > 0.0:
		healed.emit(healed_amount, current_hp)
	return healed_amount


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
	died.emit(killer)
	EventBus.entity_died.emit(get_parent(), killer)
	EventBus.publish(EventBus.ENTITY_DIED, {
		"entity": get_parent(),
		"killer": killer,
	})
