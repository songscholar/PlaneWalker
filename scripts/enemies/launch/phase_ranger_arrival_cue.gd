class_name PhaseRangerArrivalCue
extends Sprite2D

const ARTWORK_PATH := "res://assets/production/enemy_mechanisms/phase_arrival.png"
var _projection := {}


func configure() -> void:
	top_level = true
	texture = load(ARTWORK_PATH) as Texture2D
	hframes = 4
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func present(runtime: Dictionary, origin: Vector2) -> void:
	_projection = _visual_projection(runtime)
	var state: Dictionary = runtime.mechanism_state.phase_shift
	visible = not runtime.terminal and state.enabled and state.phase in ["DEPARTURE", "ARRIVAL"]
	global_position = _position(state, origin)
	frame = (int(runtime.runtime_frame) / 8) % 4


func native_geometry_matches(runtime: Dictionary, origin: Vector2) -> bool:
	var state: Dictionary = runtime.mechanism_state.phase_shift
	var live: bool = not runtime.terminal and state.enabled and state.phase in ["DEPARTURE", "ARRIVAL"]
	return is_inside_tree() and not is_queued_for_deletion() and top_level and _projection == _visual_projection(runtime) and visible == live and texture != null and texture.resource_path == ARTWORK_PATH and hframes == 4 and vframes == 1 and frame == (int(runtime.runtime_frame) / 8) % 4 and (not live or global_position == _position(state, origin)) and global_transform.x == Vector2.RIGHT and global_transform.y == Vector2.DOWN and texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and modulate == Color.WHITE and self_modulate == Color.WHITE


func _visual_projection(runtime: Dictionary) -> Dictionary:
	return {"runtime_frame": runtime.runtime_frame, "terminal": runtime.terminal, "phase_shift": runtime.mechanism_state.phase_shift.duplicate(true)}


func _position(state: Dictionary, origin: Vector2) -> Vector2:
	if state.enabled and state.phase in ["DEPARTURE", "ARRIVAL"] and not state.reservations.is_empty():
		var landing: Dictionary = state.reservations.back().landing
		return Vector2(float(landing.x), float(landing.y))
	return origin
