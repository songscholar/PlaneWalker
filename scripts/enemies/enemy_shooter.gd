extends "res://scripts/enemies/enemy_base.gd"
class_name EnemyShooter

@export var projectile_scene: PackedScene
@export var preferred_distance: float = 220.0


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
		velocity = away * move_speed
		move_and_slide()
	elif distance > preferred_distance * 1.25:
		_move_toward_target(0.75)
	else:
		velocity = Vector2.ZERO
		move_and_slide()
	_try_shoot()


func _try_shoot() -> void:
	if _attack_cooldown_remaining > 0.0 or projectile_scene == null:
		return
	_attack_cooldown_remaining = attack_cooldown
	var projectile := projectile_scene.instantiate()
	projectile.global_position = global_position
	projectile.direction = global_position.direction_to(target.global_position)
	projectile.damage = attack
	get_tree().current_scene.add_child(projectile)


func _restore_visual_color() -> void:
	visual.color = Color(0.95, 0.62, 0.2)
