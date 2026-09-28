extends "res://scripts/enemies/enemy_base.gd"
class_name EnemyTank


func _init() -> void:
	attack_windup = 0.75
	attack_recovery = 0.80


func _ready() -> void:
	max_hp = 150.0
	attack = 18.0
	defense = 2.0
	move_speed = 70.0
	attack_range = 44.0
	attack_cooldown = 1.35
	super()


func _tick_ai(_delta: float) -> void:
	if global_position.distance_to(target.global_position) <= attack_range:
		_try_begin_primary_attack()
		return
	_move_toward_target()


func _restore_visual_color() -> void:
	if _is_elite:
		visual.color = Color(1.0, 0.86, 0.22)
		return
	visual.color = Color(0.75, 0.35, 0.95)
