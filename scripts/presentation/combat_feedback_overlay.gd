class_name CombatFeedbackOverlay
extends Control

const STOP_ACCENT := Color(0.2, 0.92, 1.0, 1.0)
const REWIND_ACCENT := Color(0.42, 0.38, 1.0, 1.0)
const DANGER_ACCENT := Color(1.0, 0.18, 0.1, 1.0)
const HIGH_CONTRAST_BACKGROUND := Color("101216")
const HIGH_CONTRAST_FOREGROUND := Color("f7fbff")
const HIGH_CONTRAST_ACCENT := Color("ffd166")

var _mode: String = "none"
var _pattern: String = "none"
var _accent := Color.TRANSPARENT
var _effect_remaining: float = 0.0
var _effect_duration: float = 0.0
var _hit_remaining: float = 0.0
var _hit_duration: float = 0.0
var _hit_is_player: bool = false
var _low_health_ratio: float = 1.0
var _clock: float = 0.0
var _hit_flash_enabled: bool = true
var _reduced_motion: bool = false
var _high_contrast_danger: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	if _effect_remaining > 0.0:
		_effect_remaining = maxf(0.0, _effect_remaining - delta)
		if _effect_remaining <= 0.0:
			_mode = "none"
			_pattern = "none"
			_accent = Color.TRANSPARENT
	if _hit_remaining > 0.0:
		_hit_remaining = maxf(0.0, _hit_remaining - delta)
	queue_redraw()


func show_hit(target_is_player: bool, duration: float = 0.16) -> void:
	if not _hit_flash_enabled:
		return
	_hit_is_player = target_is_player
	_hit_duration = maxf(0.05, duration)
	_hit_remaining = _hit_duration
	queue_redraw()


func show_time_skill(skill_id: StringName, duration: float = 0.48) -> void:
	_effect_duration = maxf(0.1, duration)
	_effect_remaining = _effect_duration
	match skill_id:
		&"time_stop":
			_mode = "time_stop"
			_pattern = "scan_bands"
			_accent = STOP_ACCENT
		&"time_rewind":
			_mode = "time_rewind"
			_pattern = "reverse_chevrons"
			_accent = REWIND_ACCENT
		_:
			_mode = str(skill_id)
			_pattern = "time_ring"
			_accent = STOP_ACCENT
	queue_redraw()


func finish_time_skill(skill_id: StringName) -> void:
	if _mode != str(skill_id):
		return
	_effect_remaining = minf(_effect_remaining, 0.18)
	_effect_duration = maxf(_effect_duration, 0.18)


func set_low_health_ratio(ratio: float) -> void:
	_low_health_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()


func clear_feedback() -> void:
	_mode = "none"
	_pattern = "none"
	_accent = Color.TRANSPARENT
	_effect_remaining = 0.0
	_effect_duration = 0.0
	_hit_remaining = 0.0
	_hit_duration = 0.0
	_hit_is_player = false
	_low_health_ratio = 1.0
	queue_redraw()


func set_feedback_options(hit_flash_enabled: bool, reduced_motion: bool) -> void:
	_hit_flash_enabled = hit_flash_enabled
	_reduced_motion = reduced_motion
	if not _hit_flash_enabled:
		_hit_remaining = 0.0
		_hit_duration = 0.0
	queue_redraw()


func set_danger_accessibility(high_contrast: bool) -> void:
	_high_contrast_danger = high_contrast
	queue_redraw()


func get_snapshot_for_test() -> Dictionary:
	return {
		"mode": _mode,
		"pattern": _pattern,
		"accent": _accent,
		"effect_remaining": _effect_remaining,
		"hit_active": _hit_remaining > 0.0,
		"low_health_ratio": _low_health_ratio,
		"high_contrast_danger": _high_contrast_danger,
		"danger_background": HIGH_CONTRAST_BACKGROUND if _high_contrast_danger else Color(0.08, 0.0, 0.0),
		"danger_foreground": HIGH_CONTRAST_FOREGROUND if _high_contrast_danger else DANGER_ACCENT,
		"danger_accent": HIGH_CONTRAST_ACCENT if _high_contrast_danger else DANGER_ACCENT,
		"danger_pattern": "hard_border_pulse",
	}


func _draw() -> void:
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	if _low_health_ratio <= 0.3:
		_draw_low_health_border(viewport_size)
	if _effect_remaining > 0.0:
		var alpha := clampf(_effect_remaining / maxf(0.01, _effect_duration), 0.0, 1.0)
		if _mode == "time_stop":
			_draw_stop_pattern(viewport_size, alpha)
		elif _mode == "time_rewind":
			_draw_rewind_pattern(viewport_size, alpha)
		else:
			_draw_time_ring(viewport_size, alpha)
	if _hit_remaining > 0.0:
		_draw_hit_border(viewport_size)


func _draw_low_health_border(viewport_size: Vector2) -> void:
	var pulse := 0.11 if _reduced_motion else 0.08 + (sin(_clock * 10.0) * 0.5 + 0.5) * 0.07
	if _high_contrast_danger:
		_draw_hard_border(viewport_size, Color(HIGH_CONTRAST_BACKGROUND, 0.92), 14.0)
		_draw_hard_border(viewport_size, Color(HIGH_CONTRAST_FOREGROUND, 0.82), 10.0)
		_draw_hard_border(viewport_size, Color(HIGH_CONTRAST_ACCENT, 0.55 + pulse), 6.0)
		return
	var color := Color(DANGER_ACCENT.r, DANGER_ACCENT.g, DANGER_ACCENT.b, pulse)
	_draw_hard_border(viewport_size, color, 10.0)


func _draw_hit_border(viewport_size: Vector2) -> void:
	var progress := _hit_remaining / maxf(0.01, _hit_duration)
	if _hit_is_player and _high_contrast_danger:
		_draw_hard_border(viewport_size, Color(HIGH_CONTRAST_BACKGROUND, progress * 0.9), 12.0)
		_draw_hard_border(viewport_size, Color(HIGH_CONTRAST_ACCENT, progress * 0.78), 7.0)
		return
	var base := DANGER_ACCENT if _hit_is_player else Color(0.78, 0.96, 1.0)
	var color := Color(base.r, base.g, base.b, progress * (0.36 if _hit_is_player else 0.20))
	_draw_hard_border(viewport_size, color, 8.0 if _hit_is_player else 4.0)


func _draw_stop_pattern(viewport_size: Vector2, alpha: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.04, 0.22, 0.28, alpha * 0.08), true)
	var band_offset := 0 if _reduced_motion else int(_clock * 24.0) % 16
	for y: int in range(-16 + band_offset, int(viewport_size.y) + 16, 16):
		draw_rect(Rect2(0, y, viewport_size.x, 2), Color(STOP_ACCENT.r, STOP_ACCENT.g, STOP_ACCENT.b, alpha * 0.15), true)
	_draw_hard_border(viewport_size, Color(STOP_ACCENT.r, STOP_ACCENT.g, STOP_ACCENT.b, alpha * 0.25), 4.0)


func _draw_rewind_pattern(viewport_size: Vector2, alpha: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.08, 0.04, 0.24, alpha * 0.09), true)
	var center := viewport_size * 0.5
	for index: int in range(5):
		var x := center.x + float(index - 2) * 42.0
		var points := PackedVector2Array([
			Vector2(x + 18, center.y - 18),
			Vector2(x, center.y),
			Vector2(x + 18, center.y + 18),
		])
		draw_polyline(points, Color(REWIND_ACCENT.r, REWIND_ACCENT.g, REWIND_ACCENT.b, alpha * 0.45), 4.0, false)
	_draw_hard_border(viewport_size, Color(REWIND_ACCENT.r, REWIND_ACCENT.g, REWIND_ACCENT.b, alpha * 0.24), 4.0)


func _draw_time_ring(viewport_size: Vector2, alpha: float) -> void:
	draw_arc(viewport_size * 0.5, 56.0, 0.0, TAU, 24, Color(_accent.r, _accent.g, _accent.b, alpha * 0.5), 4.0, false)


func _draw_hard_border(viewport_size: Vector2, color: Color, thickness: float) -> void:
	draw_rect(Rect2(0, 0, viewport_size.x, thickness), color, true)
	draw_rect(Rect2(0, viewport_size.y - thickness, viewport_size.x, thickness), color, true)
	draw_rect(Rect2(0, 0, thickness, viewport_size.y), color, true)
	draw_rect(Rect2(viewport_size.x - thickness, 0, thickness, viewport_size.y), color, true)
