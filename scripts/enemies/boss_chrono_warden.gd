extends "res://scripts/enemies/enemy_base.gd"
class_name BossChronoWarden

@export var projectile_scene: PackedScene
@export var radial_projectile_count: int = 8
@export var exposed_defense_penalty: float = 3.0

var _base_defense: float = 0.0
var _pattern_timer: float = 0.0
var _exposed: bool = false
var _phase: int = 1
var _aimed_burst_next: bool = false


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
	health.damaged.connect(_on_boss_damaged)


func _tick_ai(delta: float) -> void:
	_update_phase()
	_pattern_timer = maxf(0.0, _pattern_timer - delta)
	if global_position.distance_to(target.global_position) > attack_range:
		_move_toward_target(0.7)
	else:
		velocity = _knockback_velocity
		move_and_slide()
		_try_melee_attack()
	if _pattern_timer <= 0.0:
		_pattern_timer = _pattern_interval()
		if _phase >= 2 and _aimed_burst_next:
			_fire_aimed_burst()
		else:
			_fire_radial_burst()
		_aimed_burst_next = not _aimed_burst_next


func _update_phase() -> void:
	var hp_ratio: float = health.current_hp / maxf(1.0, health.max_hp)
	var next_phase := 1
	if hp_ratio <= 0.25:
		next_phase = 3
	elif hp_ratio <= 0.55:
		next_phase = 2
	if next_phase == _phase:
		return
	_phase = next_phase
	radial_projectile_count = 10 if _phase == 2 else 12
	move_speed = 92.0 if _phase == 2 else 108.0
	_restore_visual_color()


func _pattern_interval() -> float:
	if _exposed:
		return 3.0
	if _phase == 3:
		return 1.55
	if _phase == 2:
		return 1.9
	return 2.4


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


func _fire_aimed_burst() -> void:
	if projectile_scene == null or target == null:
		return
	var base_direction := global_position.direction_to(target.global_position)
	var spread := 0.18 if _phase == 2 else 0.28
	var shot_count := 3 if _phase == 2 else 5
	for index: int in range(shot_count):
		var centered_index := float(index) - float(shot_count - 1) * 0.5
		var projectile := projectile_scene.instantiate()
		projectile.global_position = global_position + base_direction * 34.0
		projectile.direction = base_direction.rotated(centered_index * spread)
		projectile.speed = 230.0 if _phase == 2 else 260.0
		projectile.damage = attack * 0.7
		get_parent().add_child(projectile)


func _restore_visual_color() -> void:
	if _exposed:
		visual.color = Color(0.3, 0.85, 1.0)
	elif _phase == 3:
		visual.color = Color(1.0, 0.1, 0.55)
	elif _phase == 2:
		visual.color = Color(1.0, 0.35, 0.25)
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


func _on_boss_damaged(_amount: float, _current_hp: float) -> void:
	_update_phase()
