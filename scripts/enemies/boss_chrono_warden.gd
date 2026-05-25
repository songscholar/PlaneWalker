extends "res://scripts/enemies/enemy_base.gd"
class_name BossChronoWarden

@export var projectile_scene: PackedScene
@export var radial_projectile_count: int = 8
@export var exposed_defense_penalty: float = 3.0

var _base_defense: float = 0.0
var _pattern_timer: float = 0.0
var _exposed: bool = false


func _ready() -> void:
	max_hp = 420.0
	attack = 16.0
	defense = 3.0
	move_speed = 78.0
	attack_range = 54.0
	attack_cooldown = 1.1
	_base_defense = defense
	super()
	add_to_group("bosses")


func _tick_ai(delta: float) -> void:
	_pattern_timer = maxf(0.0, _pattern_timer - delta)
	if global_position.distance_to(target.global_position) > attack_range:
		_move_toward_target(0.7)
	else:
		velocity = _knockback_velocity
		move_and_slide()
		_try_melee_attack()
	if _pattern_timer <= 0.0:
		_pattern_timer = 2.4 if not _exposed else 3.2
		_fire_radial_burst()


func _fire_radial_burst() -> void:
	if projectile_scene == null:
		return
	for index: int in range(radial_projectile_count):
		var angle := TAU * float(index) / float(radial_projectile_count)
		var projectile := projectile_scene.instantiate()
		projectile.global_position = global_position + Vector2.RIGHT.rotated(angle) * 34.0
		projectile.direction = Vector2.RIGHT.rotated(angle)
		projectile.damage = attack * 0.65
		get_parent().add_child(projectile)


func _restore_visual_color() -> void:
	if _exposed:
		visual.color = Color(0.3, 0.85, 1.0)
	else:
		visual.color = Color(0.95, 0.15, 0.35)


func apply_time_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	_time_stopped = true
	_set_exposed(true)
	await get_tree().create_timer(duration).timeout
	_time_stopped = false
	_set_exposed(false)


func _set_exposed(value: bool) -> void:
	_exposed = value
	health.defense = maxf(0.0, _base_defense - exposed_defense_penalty) if _exposed else _base_defense
	_restore_visual_color()
