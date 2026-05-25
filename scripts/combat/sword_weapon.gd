class_name SwordWeapon
extends Node2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

@export var owner_path: NodePath
@export var base_attack: float = 30.0
@export var attack_speed: float = 1.0

@onready var hitbox: Node = $Hitbox
@onready var owner_player: Node = get_node(owner_path)

var combo_finisher_multiplier_bonus: float = 0.0
var heavy_damage_multiplier_bonus: float = 0.0
var low_hp_damage_multiplier_bonus: float = 0.0
var low_hp_threshold: float = 0.35
var _combo_index: int = 0
var _combo_reset_time: float = 0.0
var _attacking: bool = false


func _process(delta: float) -> void:
	if _combo_reset_time > 0.0:
		_combo_reset_time -= delta
		if _combo_reset_time <= 0.0:
			_combo_index = 0


func try_attack(heavy: bool = false) -> bool:
	if _attacking:
		return false
	if heavy:
		_start_attack(2.0, 0.35, 0.12, 0.45, true, false)
		return true

	var combo_data := [
		{"mult": 0.8, "windup": 0.10, "active": 0.08, "recovery": 0.18, "finisher": false},
		{"mult": 1.0, "windup": 0.12, "active": 0.08, "recovery": 0.20, "finisher": false},
		{"mult": 1.3, "windup": 0.16, "active": 0.10, "recovery": 0.28, "finisher": true},
	]
	var data: Dictionary = combo_data[_combo_index]
	_combo_index = (_combo_index + 1) % combo_data.size()
	_combo_reset_time = 0.8
	_start_attack(data["mult"], data["windup"], data["active"], data["recovery"], false, data["finisher"])
	return true


func is_attacking() -> bool:
	return _attacking


func _start_attack(multiplier: float, windup: float, active: float, recovery: float, heavy: bool, finisher: bool) -> void:
	_attacking = true
	var timing_scale := 1.0 / maxf(0.2, attack_speed)
	await get_tree().create_timer(windup * timing_scale).timeout

	var effective_multiplier := multiplier
	if heavy:
		effective_multiplier *= 1.0 + heavy_damage_multiplier_bonus
	elif finisher:
		effective_multiplier *= 1.0 + combo_finisher_multiplier_bonus
	if low_hp_damage_multiplier_bonus > 0.0 and _owner_hp_ratio() <= low_hp_threshold:
		effective_multiplier *= 1.0 + low_hp_damage_multiplier_bonus

	var damage_info := DamageInfoScript.new(base_attack * effective_multiplier, DamageInfoScript.DamageType.PHYSICAL, self, owner_player)
	damage_info.tags = ["weapon:sword"]
	if heavy:
		damage_info.knockback = Vector2.RIGHT.rotated(global_rotation) * 260.0
		damage_info.tags.append("attack:heavy")
	else:
		damage_info.knockback = Vector2.RIGHT.rotated(global_rotation) * 120.0
		if finisher:
			damage_info.tags.append("attack:finisher")
	EventBus.player_attacked.emit(&"sword")
	EventBus.publish(EventBus.PLAYER_ATTACKED, {"weapon_id": "sword"})
	hitbox.activate(damage_info, active * timing_scale)

	await get_tree().create_timer((active + recovery) * timing_scale).timeout
	_attacking = false


func _owner_hp_ratio() -> float:
	var health_component := owner_player.get_node_or_null("HealthComponent")
	if health_component == null:
		return 1.0
	return float(health_component.current_hp) / maxf(1.0, float(health_component.max_hp))
