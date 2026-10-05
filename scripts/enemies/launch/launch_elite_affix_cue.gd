class_name LaunchEliteAffixCue
extends Node2D

var _phase := "READY"
var _high_contrast := false
var _visual_scale := 1.0
var _affix_id := "nullified"
var _shield_fraction := 1.0
var _teleport_offset := Vector2.ZERO


func project_nullified(phase: String, high_contrast: bool, visual_scale: float) -> void:
	_affix_id = "nullified"
	_phase = phase
	_high_contrast = high_contrast
	_visual_scale = clampf(visual_scale, 1.0, 1.5)
	scale = Vector2.ONE * _visual_scale
	visible = phase != "TERMINAL"
	queue_redraw()


func project_shielded(phase: String, fraction: float, high_contrast: bool, visual_scale: float) -> void:
	_affix_id = "shielded"
	_phase = phase
	_shield_fraction = clampf(fraction, 0.0, 1.0)
	_high_contrast = high_contrast
	_visual_scale = clampf(visual_scale, 1.0, 1.5)
	scale = Vector2.ONE * _visual_scale
	visible = phase != "TERMINAL"
	queue_redraw()


func project_teleporting(phase: String, landing_offset: Vector2, high_contrast: bool, visual_scale: float) -> void:
	_affix_id = "teleporting"
	_phase = phase
	_teleport_offset = landing_offset
	_high_contrast = high_contrast
	_visual_scale = clampf(visual_scale, 1.0, 1.5)
	scale = Vector2.ONE * _visual_scale
	visible = phase != "TERMINAL"
	queue_redraw()


func get_snapshot() -> Dictionary:
	return {"affix_id": _affix_id, "phase": _phase, "high_contrast": _high_contrast, "visual_scale": _visual_scale, "visible": visible}


func _draw() -> void:
	if _affix_id == "teleporting":
		_draw_teleport()
		return
	if _affix_id == "shielded":
		_draw_shield()
		return
	var ink := Color.WHITE if _high_contrast else Color(0.62, 0.86, 0.92)
	if _phase == "DELAY":
		ink = Color(0.55, 0.95, 1.0) if not _high_contrast else Color.WHITE
	elif _phase == "EXPOSED":
		ink = Color(1.0, 0.71, 0.28) if not _high_contrast else Color(1.0, 0.94, 0.15)
	var fragments: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-7, -2), Vector2(-7, -6), Vector2(-4, -9), Vector2(-1, -9)]),
		PackedVector2Array([Vector2(3, -8), Vector2(7, -4), Vector2(7, 0)]),
		PackedVector2Array([Vector2(5, 4), Vector2(2, 7), Vector2(-3, 7), Vector2(-6, 4)]),
	]
	for fragment: PackedVector2Array in fragments:
		draw_polyline(fragment, Color(0.08, 0.08, 0.1), 4.0)
		draw_polyline(fragment, ink, 2.0)
	var hands := PackedVector2Array([Vector2(0, -5), Vector2(0, 0), Vector2(4, 0)])
	if _phase == "DELAY":
		hands = PackedVector2Array([Vector2(-4, 0), Vector2(0, 0), Vector2(4, 0)])
	elif _phase == "EXPOSED":
		hands = PackedVector2Array([Vector2(-3, 3), Vector2(0, 0), Vector2(3, 3)])
	draw_polyline(hands, Color(0.08, 0.08, 0.1), 4.0)
	draw_polyline(hands, ink, 2.0)
	if _phase == "EXPOSED":
		for side: float in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([Vector2(10 * side, -3), Vector2(14 * side, 0), Vector2(10 * side, 3)]), ink)


func _draw_shield() -> void:
	var ink := Color(1.0, 0.94, 0.15) if _high_contrast else Color(1.0, 0.78, 0.27)
	var contour := PackedVector2Array([Vector2(-7, -8), Vector2(7, -8), Vector2(7, 1), Vector2(4, 6), Vector2(0, 9), Vector2(-4, 6), Vector2(-7, 1), Vector2(-7, -8)])
	if _phase == "BROKEN":
		for side: float in [-1.0, 1.0]:
			var fragment := PackedVector2Array([Vector2(side * 3, -8), Vector2(side * 8, -8), Vector2(side * 8, 1), Vector2(side * 4, 7)])
			draw_polyline(fragment, Color(0.08, 0.08, 0.1), 4.0)
			draw_polyline(fragment, ink, 2.0)
		var crack := PackedVector2Array([Vector2(0, -7), Vector2(-2, -2), Vector2(2, 1), Vector2(0, 7)])
		draw_polyline(crack, Color(0.08, 0.08, 0.1), 4.0)
		draw_polyline(crack, ink, 2.0)
	else:
		draw_polyline(contour, Color(0.08, 0.08, 0.1), 4.0)
		draw_polyline(contour, ink, 2.0)
		draw_rect(Rect2(-4, -4, 8 * _shield_fraction, 3), ink)


func _draw_teleport() -> void:
	var ink := Color.WHITE if _high_contrast else Color(0.35, 0.95, 0.82)
	if _phase == "ARRIVAL" and not _high_contrast:
		ink = Color(1.0, 0.52, 0.77)
	for side: float in [-1.0, 1.0]:
		var arrow := PackedVector2Array([Vector2(-7 * side, -4 * side), Vector2(7 * side, -4 * side), Vector2(3 * side, -8 * side), Vector2(7 * side, -4 * side), Vector2(3 * side, 0)])
		draw_polyline(arrow, Color(0.08, 0.08, 0.1), 4.0)
		draw_polyline(arrow, ink, 2.0)
	if _phase in ["DEPARTURE", "ARRIVAL"]:
		var centre := _teleport_offset / _visual_scale
		draw_arc(centre, 15.0, 0, TAU, 24, Color(0.08, 0.08, 0.1), 5.0)
		draw_arc(centre, 15.0, 0, TAU, 24, ink, 2.0)
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(centre + direction * 18.0, centre + direction * 23.0, ink, 2.0)
