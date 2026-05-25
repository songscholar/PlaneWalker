class_name EnemyBase
extends CharacterBody2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

@export var max_hp: float = 60.0
@export var attack: float = 10.0
@export var defense: float = 0.0
@export var move_speed: float = 120.0
@export var attack_range: float = 36.0
@export var attack_cooldown: float = 1.0

@onready var health: Node = $HealthComponent
@onready var visual: Polygon2D = $Visual

var target: Node2D
var _attack_cooldown_remaining: float = 0.0
var _time_stopped: bool = false
var _knockback_velocity: Vector2 = Vector2.ZERO

const KNOCKBACK_DECAY := 10.0


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("time_stoppable")
	health.max_hp = max_hp
	health.defense = defense
	health.current_hp = max_hp
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	target = get_tree().get_first_node_in_group("player") as Node2D


func _physics_process(delta: float) -> void:
	if not health.is_alive():
		return
	if _time_stopped:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * _knockback_velocity.length() * delta)
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node2D
	if target == null:
		return
	_tick_ai(delta)


func _tick_ai(_delta: float) -> void:
	pass


func _move_toward_target(speed_multiplier: float = 1.0) -> void:
	var direction := global_position.direction_to(target.global_position)
	velocity = direction * move_speed * speed_multiplier + _knockback_velocity
	move_and_slide()


func _try_melee_attack() -> void:
	if _attack_cooldown_remaining > 0.0:
		return
	if global_position.distance_to(target.global_position) > attack_range:
		return
	if not target.has_node("HealthComponent"):
		return

	_attack_cooldown_remaining = attack_cooldown
	var damage_info := DamageInfoScript.new(attack, DamageInfoScript.DamageType.PHYSICAL, self, self)
	damage_info.tags = ["enemy:melee"]
	damage_info.knockback = global_position.direction_to(target.global_position) * 180.0
	target.get_node("HealthComponent").take_damage(damage_info)


func _on_damaged(_amount: float, _current_hp: float) -> void:
	visual.color = Color(1.0, 0.45, 0.35)
	await get_tree().create_timer(0.08).timeout
	if health.is_alive():
		_restore_visual_color()


func _on_died(_killer: Variant) -> void:
	remove_from_group("enemies")
	visual.color = Color(0.25, 0.25, 0.28)
	set_physics_process(false)
	await get_tree().create_timer(0.2).timeout
	queue_free()


func _restore_visual_color() -> void:
	visual.color = Color(0.9, 0.35, 0.3)


func apply_knockback(knockback: Vector2) -> void:
	_knockback_velocity += knockback


func apply_time_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	_time_stopped = true
	await get_tree().create_timer(duration).timeout
	_time_stopped = false
