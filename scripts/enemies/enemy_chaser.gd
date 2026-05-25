extends "res://scripts/enemies/enemy_base.gd"
class_name EnemyChaser


func _tick_ai(_delta: float) -> void:
	_move_toward_target()
	_try_melee_attack()


func _restore_visual_color() -> void:
	visual.color = Color(0.9, 0.28, 0.28)
