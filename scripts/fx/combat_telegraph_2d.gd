class_name CombatTelegraph2D
extends Node2D

const HostileTelegraphFactScript := preload("res://scripts/combat/hostile_telegraph_fact.gd")
const DEFAULT_FILL_COLOR := Color(1.0, 0.24, 0.18, 0.18)
const DEFAULT_OUTLINE_COLOR := Color(1.0, 0.64, 0.28, 0.92)
const HIGH_CONTRAST_BACKGROUND := Color("101216")
const HIGH_CONTRAST_FOREGROUND := Color("f7fbff")
const HIGH_CONTRAST_ACCENT := Color("ffd166")

@export var fill_color := DEFAULT_FILL_COLOR
@export var outline_color := DEFAULT_OUTLINE_COLOR
@export var outline_width: float = 2.0

var _action_id: String = ""
var _shape: String = ""
var _origin_global := Vector2.ZERO
var _aim_direction := Vector2.RIGHT
var _target_global := Vector2.ZERO
var _summon_slots_global: Array[Vector2] = []
var _base_radius: float = 0.0
var _base_length: float = 0.0
var _radius: float = 0.0
var _length: float = 0.0
var _remaining: float = 0.0
var _visual_scale: float = 1.0
var _high_contrast_danger: bool = false
var _hostile_source_id: StringName = &""
var _attack_generation: int = 0
var _active_from_frame: int = 0
var _active_through_frame: int = 0


func _ready() -> void:
	top_level = true
	visible = false
	set_accessibility_options(
		bool(GameState.get_setting("high_contrast_danger", false)),
		float(GameState.get_setting("enemy_telegraph_scale", 1.0))
	)


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
	_clear_fact_identity()
	_action_id = action_id
	_shape = shape
	_origin_global = origin_global
	_aim_direction = aim_direction.normalized() if not aim_direction.is_zero_approx() else Vector2.RIGHT
	_target_global = target_global
	_summon_slots_global = summon_slots_global.duplicate()
	_base_radius = maxf(0.0, radius)
	_base_length = maxf(0.0, length)
	_rescale_geometry()
	_remaining = maxf(0.0, duration) * _visual_scale
	global_position = _origin_global
	visible = true
	queue_redraw()


func project_fact(value: Variant) -> bool:
	var fact: Dictionary = HostileTelegraphFactScript.create(value)
	if fact.is_empty():
		return false
	show_telegraph(
		"%s#%d" % [str(fact["hostile_source_id"]), int(fact["attack_generation"])],
		str(fact["shape"]),
		fact["origin"] as Vector2,
		fact["aim_direction"] as Vector2,
		fact["target_point"] as Vector2,
		_typed_vector_array(fact["summon_slots"] as Array),
		float(fact["radius"]),
		float(fact["length"]),
		float(int(fact["active_through_frame"]) - int(fact["active_from_frame"]) + 1) / 60.0
	)
	_hostile_source_id = StringName(str(fact["hostile_source_id"]))
	_attack_generation = int(fact["attack_generation"])
	_active_from_frame = int(fact["active_from_frame"])
	_active_through_frame = int(fact["active_through_frame"])
	return true


func set_remaining_time(value: float) -> void:
	_remaining = maxf(0.0, value) * _visual_scale
	queue_redraw()


func set_accessibility_options(high_contrast: bool, visual_scale: float) -> void:
	_high_contrast_danger = high_contrast
	_visual_scale = clampf(visual_scale, 1.0, 1.5)
	_rescale_geometry()
	fill_color = Color(HIGH_CONTRAST_BACKGROUND, 0.52) if high_contrast else DEFAULT_FILL_COLOR
	outline_color = HIGH_CONTRAST_ACCENT if high_contrast else DEFAULT_OUTLINE_COLOR
	queue_redraw()


func set_accessibility_visual_scale(visual_scale: float) -> void:
	set_accessibility_options(_high_contrast_danger, visual_scale)


func _rescale_geometry() -> void:
	_radius = _base_radius * _visual_scale
	_length = _base_length * _visual_scale


func update_origin_global(origin_global: Vector2) -> void:
	_origin_global = origin_global
	global_position = _origin_global
	queue_redraw()


func clear_telegraph() -> void:
	visible = false
	_remaining = 0.0
	_clear_fact_identity()
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
		"visual_radius": _radius,
		"visual_length": _length,
		"hostile_source_id": _hostile_source_id,
		"attack_generation": _attack_generation,
		"active_from_frame": _active_from_frame,
		"active_through_frame": _active_through_frame,
		"remaining": _remaining,
		"visible": visible,
		"visual_scale": _visual_scale,
		"high_contrast_danger": _high_contrast_danger,
		"danger_background": HIGH_CONTRAST_BACKGROUND if _high_contrast_danger else fill_color,
		"danger_foreground": HIGH_CONTRAST_FOREGROUND if _high_contrast_danger else outline_color,
		"danger_accent": HIGH_CONTRAST_ACCENT if _high_contrast_danger else outline_color,
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
			_draw_high_contrast_inner_ring(Vector2.ZERO, _radius)
		"line":
			_draw_line_proxy()
		"rift":
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
	if _high_contrast_danger:
		draw_polyline(points, HIGH_CONTRAST_FOREGROUND, 1.0, true)


func _draw_circle_proxy(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, fill_color)
	draw_arc(center, radius, 0.0, TAU, 48, outline_color, outline_width, true)
	_draw_high_contrast_inner_ring(center, radius)


func _draw_line_proxy() -> void:
	var normal := _aim_direction.orthogonal() * maxf(5.0, _radius)
	var endpoint := _aim_direction * _length
	var polygon := PackedVector2Array([normal, endpoint + normal, endpoint - normal, -normal])
	draw_colored_polygon(polygon, fill_color)
	draw_polyline(PackedVector2Array([normal, endpoint + normal, endpoint - normal, -normal, normal]), outline_color, outline_width, true)
	if _high_contrast_danger:
		draw_line(Vector2.ZERO, endpoint, HIGH_CONTRAST_FOREGROUND, 1.0, true)


func _draw_high_contrast_inner_ring(center: Vector2, radius: float) -> void:
	if not _high_contrast_danger:
		return
	draw_arc(center, maxf(1.0, radius - 4.0), 0.0, TAU, 48, HIGH_CONTRAST_FOREGROUND, 1.0, true)


func _clear_fact_identity() -> void:
	_hostile_source_id = &""
	_attack_generation = 0
	_active_from_frame = 0
	_active_through_frame = 0


func _typed_vector_array(values: Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for value: Variant in values:
		result.append(value as Vector2)
	return result
