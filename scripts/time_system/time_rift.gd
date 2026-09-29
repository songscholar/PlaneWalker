class_name TimeRift
extends Area2D

@export var duration: float = 4.0
@export var radius: float = 92.0
@export var slow_multiplier: float = 0.45

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visual: Polygon2D = $Visual

var _affected: Array[Node] = []
var _remaining_duration: float = 0.0
var _finished: bool = false


func _ready() -> void:
	add_to_group("time_rifts")
	_configure_shape()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_remaining_duration = maxf(0.0, duration)
	call_deferred("_apply_overlapping_bodies")


func _process(delta: float) -> void:
	if _finished:
		return
	_remaining_duration = maxf(0.0, _remaining_duration - delta)
	if _remaining_duration <= 0.0:
		_expire()


func _configure_shape() -> void:
	var circle := CircleShape2D.new()
	circle.radius = radius
	collision_shape.shape = circle

	var points: PackedVector2Array = []
	var segments := 40
	for index: int in range(segments):
		var angle := TAU * float(index) / float(segments)
		points.append(Vector2.RIGHT.rotated(angle) * radius)
	visual.polygon = points


func _on_body_entered(body: Node) -> void:
	_apply_body(body)


func _apply_overlapping_bodies() -> void:
	if _finished:
		return
	for body: Node in get_overlapping_bodies():
		_apply_body(body)
	for body: Node in get_tree().get_nodes_in_group("enemies"):
		if body is Node2D and global_position.distance_to(body.global_position) <= radius:
			_apply_body(body)


func _apply_body(body: Node) -> void:
	if _finished:
		return
	if not body.has_method("apply_time_rift"):
		return
	if _affected.has(body):
		return
	body.apply_time_rift(slow_multiplier)
	_affected.append(body)


func _on_body_exited(body: Node) -> void:
	_clear_body(body)


func _expire() -> void:
	_finish(true)


func cancel(publish_end_event: bool = false) -> void:
	_finish(publish_end_event)


func _finish(publish_end_event: bool) -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	for body: Node in _affected.duplicate():
		_clear_body(body)
	if publish_end_event:
		EventBus.time_skill_ended.emit(&"time_rift", {})
	queue_free()


func _clear_body(body: Node) -> void:
	if _affected.has(body):
		_affected.erase(body)
	if is_instance_valid(body) and body.has_method("clear_time_rift"):
		body.clear_time_rift()
