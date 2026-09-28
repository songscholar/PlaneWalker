class_name PixelProxyAfterimage
extends Node2D

var _role: String = "generic"
var _primary := Color(0.4, 0.9, 1.0, 0.5)
var _accent := Color(0.9, 1.0, 1.0, 0.7)
var _footprint := Vector2i(20, 24)
var _lifetime: float = 0.22
var _remaining: float = 0.22
var _origin_global_position := Vector2.ZERO
var _action_scale := Vector2.ONE
var _canvas_inverse_scale := Vector2.ONE
var _world_pixel_unit := Vector2.ONE


func configure(
	role: String,
	primary: Color,
	accent: Color,
	footprint: Vector2i,
	action_scale: Vector2,
	canvas_inverse_scale: Vector2,
	world_pixel_unit: Vector2,
	lifetime: float = 0.22
) -> void:
	_role = role
	_primary = primary
	_accent = accent
	_footprint = footprint
	_action_scale = action_scale
	_canvas_inverse_scale = canvas_inverse_scale
	_world_pixel_unit = world_pixel_unit
	_lifetime = maxf(0.05, lifetime)
	_remaining = _lifetime
	_origin_global_position = global_position
	scale = _action_scale * _canvas_inverse_scale
	queue_redraw()


func _process(delta: float) -> void:
	_remaining = maxf(0.0, _remaining - delta)
	var progress := 1.0 - _remaining / _lifetime
	modulate.a = 1.0 - progress
	var drift := Vector2(0.0, progress * 4.0) * _canvas_inverse_scale
	global_position = Vector2(
		snappedf(_origin_global_position.x + drift.x, _world_pixel_unit.x),
		snappedf(_origin_global_position.y + drift.y, _world_pixel_unit.y)
	)
	queue_redraw()
	if _remaining <= 0.0:
		queue_free()


func get_snapshot_for_test() -> Dictionary:
	return {
		"action_scale": _action_scale,
		"canvas_inverse_scale": _canvas_inverse_scale,
		"world_pixel_unit": _world_pixel_unit,
		"screen_footprint": Vector2(_footprint) * _action_scale,
		"pixel_snapped": is_equal_approx(fmod(absf(global_position.x), _world_pixel_unit.x), 0.0)
			and is_equal_approx(fmod(absf(global_position.y), _world_pixel_unit.y), 0.0),
	}


func _draw() -> void:
	var width := float(_footprint.x)
	var height := float(_footprint.y)
	var rect := Rect2(Vector2(-width * 0.5, -height * 0.5), Vector2(width, height))
	if _role == "player":
		draw_rect(Rect2(rect.position + Vector2(4, 2), rect.size - Vector2(8, 4)), _primary, true)
		draw_rect(Rect2(Vector2(-4, -height * 0.5 - 4), Vector2(8, 8)), _accent, true)
	elif _role == "boss":
		draw_rect(rect, _primary, true)
		draw_rect(Rect2(Vector2(-4, -4), Vector2(8, 8)), _accent, true)
	else:
		draw_colored_polygon(
			PackedVector2Array([
				Vector2(width * 0.5, 0),
				Vector2(0, -height * 0.5),
				Vector2(-width * 0.5, 0),
				Vector2(0, height * 0.5),
			]),
			_primary
		)
		draw_rect(Rect2(Vector2(-2, -2), Vector2(4, 4)), _accent, true)
