class_name BossTimeCrack
extends Area2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

@export var arm_delay: float = 1.15
@export var radius: float = 54.0
@export var damage: float = 18.0

var _time_stopped: bool = false
var _timer: float = 0.0
var _exploded: bool = false
var _visual: Polygon2D


func _ready() -> void:
	add_to_group("time_stoppable")
	add_to_group("boss_hazards")
	monitoring = false
	_timer = arm_delay
	_build_shape()


func _process(delta: float) -> void:
	if _exploded or _time_stopped:
		return
	_timer -= delta
	if _visual != null:
		_visual.modulate.a = clampf(1.0 - (_timer / maxf(arm_delay, 0.001)), 0.25, 1.0)
	if _timer <= 0.0:
		_explode()


func apply_time_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	_time_stopped = true
	await get_tree().create_timer(duration).timeout
	_time_stopped = false


func has_exploded() -> bool:
	return _exploded


func remaining_time() -> float:
	return _timer


func _build_shape() -> void:
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision.shape = shape
	add_child(collision)

	_visual = Polygon2D.new()
	var points := PackedVector2Array()
	for index: int in range(12):
		var point_radius := radius if index % 2 == 0 else radius * 0.72
		points.append(Vector2.RIGHT.rotated(TAU * float(index) / 12.0) * point_radius)
	_visual.polygon = points
	_visual.color = Color(0.35, 0.75, 1.0, 0.35)
	add_child(_visual)


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	monitoring = true
	if _visual != null:
		_visual.color = Color(0.7, 0.95, 1.0, 0.95)
	for player: Node in get_tree().get_nodes_in_group("player"):
		if player is Node2D and player.global_position.distance_to(global_position) <= radius:
			var health := player.get_node_or_null("HealthComponent")
			if health != null:
				var damage_info := DamageInfoScript.new(damage, DamageInfoScript.DamageType.TIME, self, self)
				damage_info.tags = ["boss:time_crack", "time:hazard"]
				health.take_damage(damage_info)
	await get_tree().create_timer(0.18).timeout
	if is_inside_tree():
		queue_free()
