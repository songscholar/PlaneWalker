class_name LaunchEliteAffixCue
extends Node2D

var _phase := "READY"
var _high_contrast := false
var _visual_scale := 1.0


func project_nullified(phase: String, high_contrast: bool, visual_scale: float) -> void:
	_phase = phase
	_high_contrast = high_contrast
	_visual_scale = clampf(visual_scale, 1.0, 1.5)
	scale = Vector2.ONE * _visual_scale
	visible = phase != "TERMINAL"
	queue_redraw()


func get_snapshot() -> Dictionary:
	return {"affix_id": "nullified", "phase": _phase, "high_contrast": _high_contrast, "visual_scale": _visual_scale, "visible": visible}


func _draw() -> void:
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
