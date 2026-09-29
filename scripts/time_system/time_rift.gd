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
var _source_id: StringName


func _init() -> void:
	_source_id = StringName("time_rift_%d" % get_instance_id())


func _ready() -> void:
	add_to_group("time_rifts")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_configure_shape()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	_remaining_duration = maxf(0.0, duration)
	call_deferred("_apply_overlapping_targets")


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
	_apply_target(body)


func _on_area_entered(area: Area2D) -> void:
	_apply_target(area)


func _apply_overlapping_targets() -> void:
	if _finished:
		return
	for body: Node in get_overlapping_bodies():
		_apply_target(body)
	for area: Area2D in get_overlapping_areas():
		_apply_target(area)
	for body: Node in get_tree().get_nodes_in_group("enemies"):
		if body is Node2D and global_position.distance_to(body.global_position) <= radius:
			_apply_target(body)


func _apply_target(target: Node) -> void:
	if _finished:
		return
	if not target.has_method("apply_time_rift"):
		return
	if _affected.has(target):
		return
	target.apply_time_rift(_source_id, slow_multiplier)
	_affected.append(target)


func _on_body_exited(body: Node) -> void:
	_clear_target(body)


func _on_area_exited(area: Area2D) -> void:
	_clear_target(area)


func _expire() -> void:
	_finish(true)


func cancel(publish_end_event: bool = true) -> void:
	_finish(publish_end_event)


func _finish(publish_end_event: bool) -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	for target: Node in _affected.duplicate():
		_clear_target(target)
	if publish_end_event:
		EventBus.time_skill_ended.emit(&"time_rift", {})
	queue_free()


func _clear_target(target: Node) -> void:
	if not _affected.has(target):
		return
	_affected.erase(target)
	if is_instance_valid(target) and target.has_method("clear_time_rift"):
		target.clear_time_rift(_source_id)
