extends "res://scripts/enemies/enemy_base.gd"
class_name EnemyShooter

@export var projectile_scene: PackedScene
@export var preferred_distance: float = 220.0


func _init() -> void:
	attack_windup = 0.60
	attack_recovery = 0.45


func _ready() -> void:
	max_hp = 45.0
	attack = 8.0
	move_speed = 90.0
	attack_range = 420.0
	attack_cooldown = 1.4
	super()


func _tick_ai(_delta: float) -> void:
	var distance := global_position.distance_to(target.global_position)
	if distance < preferred_distance * 0.75:
		var away := target.global_position.direction_to(global_position)
		velocity = away * _current_move_speed() + _knockback_velocity
		move_and_slide()
	elif distance > preferred_distance * 1.25:
		_move_toward_target(0.75)
	else:
		velocity = _knockback_velocity
		move_and_slide()
	_try_shoot()


func _try_shoot() -> void:
	if projectile_scene == null:
		return
	_try_begin_primary_attack()


func _resolve_primary_attack() -> void:
	if projectile_scene == null:
		return
	var projectile := projectile_scene.instantiate()
	projectile.global_position = global_position
	projectile.direction = _committed_attack_direction
	projectile.damage = attack
	var projectile_parent := get_tree().current_scene
	if projectile_parent == null:
		projectile_parent = get_parent()
	projectile_parent.add_child(projectile)


func _restore_visual_color() -> void:
	if _is_elite:
		visual.color = Color(1.0, 0.86, 0.22)
		return
	visual.color = Color(0.95, 0.62, 0.2)
