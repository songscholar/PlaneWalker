class_name TestDummy
extends Node2D

@onready var health: HealthComponent = $HealthComponent
@onready var visual: Polygon2D = $Visual


func _ready() -> void:
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)


func _on_damaged(_amount: float, _current_hp: float) -> void:
	visual.color = Color(1.0, 0.55, 0.45)
	await get_tree().create_timer(0.08).timeout
	if health.is_alive():
		visual.color = Color(0.75, 0.82, 0.92)


func _on_died(_killer: Variant) -> void:
	visual.color = Color(0.35, 0.38, 0.45)
	await get_tree().create_timer(0.2).timeout
	queue_free()
