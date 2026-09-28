class_name CombatTelegraph2D
extends Node2D

@export var fill_color := Color(1.0, 0.24, 0.18, 0.18)
@export var outline_color := Color(1.0, 0.64, 0.28, 0.92)
@export var outline_width: float = 2.0

var _action_id: String = ""
var _shape: String = ""
var _origin_global := Vector2.ZERO
var _aim_direction := Vector2.RIGHT
var _target_global := Vector2.ZERO
var _summon_slots_global: Array[Vector2] = []
var _radius: float = 0.0
var _length: float = 0.0
var _remaining: float = 0.0


func _ready() -> void:
	top_level = true
	visible = false


func show_telegraph(
	action_id: String,
	shape: String,
	origin_global: Vector2,
	aim_direction: Vector2,
	target_global: Vector2,
	summon_slots_global: Array[Vector2],
	radius: float,
	length: float,
	duration: float
) -> void:
	_action_id = action_id
	_shape = shape
	_origin_global = origin_global
	_aim_direction = aim_direction.normalized() if not aim_direction.is_zero_approx() else Vector2.RIGHT
	_target_global = target_global
	_summon_slots_global = summon_slots_global.duplicate()
	_radius = maxf(0.0, radius)
	_length = maxf(0.0, length)
	_remaining = maxf(0.0, duration)
	global_position = _origin_global
	visible = true
	queue_redraw()


func set_remaining_time(value: float) -> void:
	_remaining = maxf(0.0, value)
	queue_redraw()


func update_origin_global(origin_global: Vector2) -> void:
	_origin_global = origin_global
	global_position = _origin_global
	queue_redraw()


func clear_telegraph() -> void:
	visible = false
	_remaining = 0.0
	queue_redraw()


func get_snapshot() -> Dictionary:
	return {
		"action_id": _action_id,
		"shape": _shape,
		"origin": _origin_global,
		"aim_direction": _aim_direction,
		"target_point": _target_global,
		"summon_slots": _summon_slots_global.duplicate(),
		"radius": _radius,
		"length": _length,
		"remaining": _remaining,
		"visible": visible,
	}


func _draw() -> void:
	if not visible:
		return
	match _shape:
		"cone":
			_draw_cone()
		"circle":
			_draw_circle_proxy(Vector2.ZERO, _radius)
		"ring":
			draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 48, outline_color, outline_width, true)
			draw_arc(Vector2.ZERO, maxf(1.0, _radius - 8.0), 0.0, TAU, 48, fill_color, 8.0, true)
		"line":
			_draw_line_proxy()
		"summon_slots":
			for slot_global: Vector2 in _summon_slots_global:
				_draw_circle_proxy(slot_global - _origin_global, maxf(8.0, _radius))
		"target_circle":
			_draw_circle_proxy(_target_global - _origin_global, _radius)


func _draw_cone() -> void:
	var points := PackedVector2Array([Vector2.ZERO])
	var start_angle := _aim_direction.angle() - 0.55
	for index: int in range(13):
		points.append(Vector2.RIGHT.rotated(start_angle + 1.1 * float(index) / 12.0) * _length)
	draw_colored_polygon(points, fill_color)
	draw_polyline(points, outline_color, outline_width, true)
	draw_line(points[points.size() - 1], Vector2.ZERO, outline_color, outline_width, true)


func _draw_circle_proxy(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, fill_color)
	draw_arc(center, radius, 0.0, TAU, 48, outline_color, outline_width, true)


func _draw_line_proxy() -> void:
	var normal := _aim_direction.orthogonal() * maxf(5.0, _radius)
	var endpoint := _aim_direction * _length
	var polygon := PackedVector2Array([normal, endpoint + normal, endpoint - normal, -normal])
	draw_colored_polygon(polygon, fill_color)
	draw_polyline(PackedVector2Array([normal, endpoint + normal, endpoint - normal, -normal, normal]), outline_color, outline_width, true)
