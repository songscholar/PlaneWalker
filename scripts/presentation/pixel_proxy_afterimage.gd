class_name PixelProxyAfterimage
extends Node2D

var _role: String = "generic"
var _primary := Color(0.4, 0.9, 1.0, 0.5)
var _accent := Color(0.9, 1.0, 1.0, 0.7)
var _footprint := Vector2i(20, 24)
var _lifetime: float = 0.22
var _remaining: float = 0.22


func configure(
	role: String,
	primary: Color,
	accent: Color,
	footprint: Vector2i,
	lifetime: float = 0.22
) -> void:
	_role = role
	_primary = primary
	_accent = accent
	_footprint = footprint
	_lifetime = maxf(0.05, lifetime)
	_remaining = _lifetime
	queue_redraw()


func _process(delta: float) -> void:
	_remaining = maxf(0.0, _remaining - delta)
	var progress := 1.0 - _remaining / _lifetime
	modulate.a = 1.0 - progress
	position.y = roundf(progress * 4.0)
	queue_redraw()
	if _remaining <= 0.0:
		queue_free()


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
