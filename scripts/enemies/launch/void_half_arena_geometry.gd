class_name VoidHalfArenaGeometry
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const ACTION_IDS := ["voidking_void_end", "voidking_enrage_zero"]


static func recipe(action_id: String) -> Array:
	var result: Array = [{"shape": "line", "origin_offset": {"x": 0.0, "y": 90.0}, "aim_offset_degrees": 0.0, "radius": 90.0, "length": 640.0}]
	if action_id == "voidking_void_end":
		for x: float in [176.0, 464.0]:
			result.append({"shape": "target_circle", "origin_offset": {"x": x, "y": 270.0}, "aim_offset_degrees": 0.0, "radius": 24.0, "length": 0.0})
	return result


static func current_action(action: Dictionary) -> bool:
	return action.get("id") in ACTION_IDS and action.get("geometry") == recipe(str(action.id))


static func anchored_context(context: Dictionary, arena_origin: Dictionary, bottom: bool) -> Dictionary:
	var result := context.duplicate(true)
	var source := Vector2(float(arena_origin.x), float(arena_origin.y)) + (Vector2(640, 360) if bottom else Vector2.ZERO)
	var direction := Vector2.LEFT if bottom else Vector2.RIGHT
	result.source_position = _point(source)
	result.target_position = _point(source + direction)
	result.facing_direction = _point(direction)
	return result


static func committed_geometry(action: Dictionary, state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source := Vector2(float(state.committed_origin.x), float(state.committed_origin.y))
	var sign: float = -1.0 if float(state.committed_aim.x) < 0.0 else 1.0
	var through := int(state.commit_frame) + int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames) + int(state.paused_frames) - 1
	for index: int in range(action.geometry.size()):
		var primitive: Dictionary = action.geometry[index]
		var offset := Vector2(float(primitive.origin_offset.x), float(primitive.origin_offset.y)) * sign
		var origin := _point(source + offset)
		result.append({"hostile_source_id": state.identity.hostile_source_id, "attack_generation": state.geometry_generations[index], "shape": primitive.shape, "origin": origin, "aim_direction": {"x": sign, "y": 0.0}, "target_point": origin.duplicate(true), "summon_slots": [], "radius": primitive.radius, "length": primitive.length, "active_from_frame": state.commit_frame, "active_through_frame": through})
	return result


static func valid_geometry(value: Array, action_id: String, arena_origin: Dictionary) -> bool:
	var primitives := recipe(action_id)
	if value.size() != primitives.size() or not value[0] is Dictionary or not Contract.valid_point(value[0].get("origin")):
		return false
	var origin := Vector2(float(arena_origin.x), float(arena_origin.y))
	var first := Vector2(float(value[0].origin.x), float(value[0].origin.y))
	var bottom := first == origin + Vector2(640, 270)
	if not bottom and first != origin + Vector2(0, 90):
		return false
	var sign: float = -1.0 if bottom else 1.0
	var source := origin + (Vector2(640, 360) if bottom else Vector2.ZERO)
	for index: int in range(value.size()):
		if not value[index] is Dictionary:
			return false
		var row: Dictionary = value[index]
		var primitive: Dictionary = primitives[index]
		var point := _point(source + Vector2(float(primitive.origin_offset.x), float(primitive.origin_offset.y)) * sign)
		if row.get("shape") != primitive.shape or row.get("origin") != point or row.get("target_point") != point or row.get("aim_direction") != {"x": sign, "y": 0.0} or row.get("radius") != primitive.radius or row.get("length") != primitive.length:
			return false
	return true


static func _point(value: Vector2) -> Dictionary:
	return {"x": float(value.x), "y": float(value.y)}
