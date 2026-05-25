class_name DamageInfo
extends RefCounted

enum DamageType { PHYSICAL, TIME, VOID, FIRE, ICE, LIGHTNING }

var amount: float = 0.0
var damage_type: DamageType = DamageType.PHYSICAL
var source: Node
var attacker: Node
var can_crit: bool = true
var crit_chance: float = 0.0
var crit_multiplier: float = 1.5
var knockback: Vector2 = Vector2.ZERO
var tags: Array[String] = []


func _init(
	p_amount: float = 0.0,
	p_damage_type: DamageType = DamageType.PHYSICAL,
	p_source: Node = null,
	p_attacker: Node = null
) -> void:
	amount = p_amount
	damage_type = p_damage_type
	source = p_source
	attacker = p_attacker


func copy_for_source(new_source: Node) -> DamageInfo:
	var copied := DamageInfo.new(amount, damage_type, new_source, attacker)
	copied.can_crit = can_crit
	copied.crit_chance = crit_chance
	copied.crit_multiplier = crit_multiplier
	copied.knockback = knockback
	copied.tags = tags.duplicate()
	return copied
