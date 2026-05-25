class_name SpawnWarning
extends Node2D

@export var duration: float = 0.45
@export var radius: float = 24.0

@onready var visual: Polygon2D = $Visual


func _ready() -> void:
	var points := PackedVector2Array()
	for index: int in range(16):
		points.append(Vector2.RIGHT.rotated(TAU * float(index) / 16.0) * radius)
	visual.polygon = points
	visual.modulate = Color(1.0, 0.35, 0.2, 0.25)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual, "scale", Vector2(0.35, 0.35), duration).from(Vector2(1.25, 1.25))
	tween.tween_property(visual, "modulate:a", 0.85, duration)
	tween.finished.connect(queue_free)
