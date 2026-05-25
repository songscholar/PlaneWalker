class_name BowWeapon
extends Node2D

const ArrowScene := preload("res://scenes/combat/player_arrow.tscn")

@export var owner_path: NodePath
@export var base_attack: float = 30.0
@export var attack_speed: float = 1.0
@export var min_charge_time: float = 0.15
@export var full_charge_time: float = 0.9
@export var cooldown: float = 0.35
@export var full_charge_time_restore: float = 6.0

@onready var owner_player: Node2D = get_node(owner_path)

var _charging: bool = false
var _charge_time: float = 0.0
var _cooldown_remaining: float = 0.0
var charge_rate_bonus: float = 0.0
var full_charge_damage_multiplier_bonus: float = 0.0
var pierce_bonus: int = 0


func _process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if _charging:
		_charge_time += delta * maxf(0.2, attack_speed) * (1.0 + charge_rate_bonus)


func start_charge() -> bool:
	if _charging or _cooldown_remaining > 0.0:
		return false
	_charging = true
	_charge_time = 0.0
	return true


func release_charge(direction: Vector2) -> bool:
	if not _charging:
		return false
	_charging = false
	if _charge_time < min_charge_time:
		_charge_time = 0.0
		_cooldown_remaining = cooldown * 0.35
		return false

	var charge_ratio := get_charge_ratio()
	_fire_arrow(direction, charge_ratio)
	_charge_time = 0.0
	_cooldown_remaining = cooldown / maxf(0.2, attack_speed)
	return true


func is_charging() -> bool:
	return _charging


func get_cooldown_remaining() -> float:
	return _cooldown_remaining


func get_charge_ratio() -> float:
	return clampf(_charge_time / full_charge_time, 0.0, 1.0)


func _fire_arrow(direction: Vector2, charge_ratio: float) -> void:
	var shot_direction := direction.normalized()
	if shot_direction.length_squared() <= 0.001:
		shot_direction = Vector2.RIGHT.rotated(global_rotation)
	var arrow := ArrowScene.instantiate()
	arrow.global_position = global_position + shot_direction * 28.0
	arrow.direction = shot_direction
	var full_charge_multiplier := 1.0 + full_charge_damage_multiplier_bonus if charge_ratio >= 0.98 else 1.0
	arrow.damage = base_attack * lerpf(0.75, 1.75, charge_ratio) * full_charge_multiplier
	arrow.speed = lerpf(440.0, 680.0, charge_ratio)
	arrow.pierce = (1 if charge_ratio >= 0.98 else 0) + pierce_bonus
	arrow.full_charge = charge_ratio >= 0.98
	arrow.time_energy_restore = full_charge_time_restore if arrow.full_charge else 0.0
	arrow.source = self
	arrow.owner_entity = owner_player
	get_tree().current_scene.add_child(arrow)
	EventBus.player_attacked.emit(&"bow")
	EventBus.publish(EventBus.PLAYER_ATTACKED, {"weapon_id": "bow", "charge": charge_ratio})
