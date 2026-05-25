class_name EnemyTank
extends EnemyBase


func _ready() -> void:
	max_hp = 150.0
	attack = 18.0
	defense = 2.0
	move_speed = 70.0
	attack_range = 44.0
	attack_cooldown = 1.35
	super()


func _tick_ai(_delta: float) -> void:
	_move_toward_target()
	_try_melee_attack()


func _restore_visual_color() -> void:
	visual.color = Color(0.75, 0.35, 0.95)
