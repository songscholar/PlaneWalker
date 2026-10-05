class_name LaunchSemanticZoneProjection
extends Node2D

const StormPattern := preload("res://scripts/enemies/launch/launch_storm_pattern.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Telegraph := preload("res://scripts/fx/combat_telegraph_2d.gd")

var _record: Dictionary = {}
var _sprite: Sprite2D
var _exact_telegraph: Node2D
var _presentation: Dictionary = {}
var _frame := 0


func project_record(record: Dictionary, frame: int) -> bool:
	if not is_inside_tree() or is_queued_for_deletion():
		return false
	if _uses_exact_geometry(record):
		return _project_exact_geometry(record, frame)
	if is_instance_valid(_exact_telegraph):
		_exact_telegraph.visible = false
	clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.hframes = 4
		add_child(_sprite)
	_sprite.visible = true
	_presentation = StormPattern.project(record.storm_pattern, int(record.active_frame), frame) if record.has("storm_pattern") else {}
	var texture_type: String = "physical" if bool(_presentation.get("fast", false)) else str(record.damage_type)
	var texture := load("res://assets/production/hostile_effects/%s_pool.png" % texture_type) as Texture2D
	if texture == null:
		return false
	_record = record.duplicate(true)
	_frame = frame
	name = record.id
	global_position = Vector2(float(record.geometry.origin.x), float(record.geometry.origin.y))
	_sprite.texture = texture
	_sprite.frame = (frame / 6) % 4
	var radius := maxf(1.0, float(record.geometry.radius))
	if record.geometry.shape in ["line", "rift", "cone"]:
		_sprite.position = Vector2(float(record.geometry.length) / 2.0, 0.0)
		_sprite.scale = Vector2(maxf(1.0, float(record.geometry.length)) / 26.0, radius / 13.0)
		rotation = Vector2(float(record.geometry.aim_direction.x), float(record.geometry.aim_direction.y)).angle()
	else:
		_sprite.position = Vector2.ZERO
		_sprite.scale = Vector2.ONE * radius / 13.0
		rotation = 0.0
	_sprite.modulate = Color(1.0, 0.95, 0.45, 0.65 if frame % 12 < 6 else 1.0) if record.phase == "WARNING" or bool(_presentation.get("swap_warning", false)) else Color.WHITE
	visible = record.phase != "PENDING"
	return true


func matches_record(record: Dictionary) -> bool:
	if _uses_exact_geometry(record):
		return _matches_exact_geometry(record)
	if not (is_inside_tree() and not is_queued_for_deletion() and record == _record and visible and global_position == Vector2(float(record.geometry.origin.x), float(record.geometry.origin.y)) and is_instance_valid(_sprite) and _sprite.get_parent() == self and _sprite.texture != null and _sprite.visible and _sprite.hframes == 4):
		return false
	if not record.has("storm_pattern"):
		return true
	var expected := StormPattern.project(record.storm_pattern, int(record.active_frame), _frame)
	var texture_type: String = "physical" if bool(expected.fast) else str(record.damage_type)
	var color := Color(1.0, 0.95, 0.45, 0.65 if _frame % 12 < 6 else 1.0) if record.phase == "WARNING" or bool(expected.swap_warning) else Color.WHITE
	return _presentation == expected and _sprite.texture.resource_path == "res://assets/production/hostile_effects/%s_pool.png" % texture_type and _sprite.frame == (_frame / 6) % 4 and _sprite.modulate == color


func presentation_snapshot() -> Dictionary:
	return _presentation.duplicate(true)


func _uses_exact_geometry(record: Dictionary) -> bool:
	return record.get("action_id", "") in ["voidking_void_end", "voidking_enrage_zero"] and record.geometry.shape == "line" and record.geometry.radius == 90.0 and record.geometry.length == 640.0


func _exact_fact(record: Dictionary) -> Dictionary:
	var fact: Dictionary = record.geometry.duplicate(true)
	fact.active_from_frame = int(record.active_frame)
	fact.active_through_frame = int(record.expires_frame)
	return Actions.native_threat_fact(fact)


func _project_exact_geometry(record: Dictionary, frame: int) -> bool:
	if _exact_telegraph == null:
		_exact_telegraph = Telegraph.new()
		_exact_telegraph.name = "CommittedGeometry"
		add_child(_exact_telegraph)
		_exact_telegraph.top_level = false
		_exact_telegraph.set_process(false)
	if is_instance_valid(_sprite):
		_sprite.visible = false
	_record = record.duplicate(true)
	_presentation = {}
	_frame = frame
	name = record.id
	global_position = Vector2(float(record.geometry.origin.x), float(record.geometry.origin.y))
	rotation = 0.0
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_exact_telegraph.set_accessibility_options(bool(GameState.get_setting("high_contrast_danger", false)), float(GameState.get_setting("enemy_telegraph_scale", 1.0)))
	if not _exact_telegraph.project_fact(_exact_fact(record), str(record.id)):
		return false
	visible = record.phase != "PENDING"
	queue_redraw()
	return true


func _matches_exact_geometry(record: Dictionary) -> bool:
	if not (is_inside_tree() and not is_queued_for_deletion() and record == _record and visible and global_position == Vector2(float(record.geometry.origin.x), float(record.geometry.origin.y)) and is_instance_valid(_exact_telegraph) and _exact_telegraph.get_parent() == self and _exact_telegraph.visible and not _exact_telegraph.is_processing()):
		return false
	var actual: Dictionary = _exact_telegraph.get_snapshot()
	var expected := _exact_fact(record)
	for field: String in ["hostile_source_id", "attack_generation", "shape", "origin", "aim_direction", "target_point", "summon_slots", "active_from_frame", "active_through_frame"]:
		if actual[field] != expected[field]:
			return false
	var scale_value := clampf(float(GameState.get_setting("enemy_telegraph_scale", 1.0)), 1.0, 1.5)
	return actual.action_id == record.id and actual.radius == expected.radius * scale_value and actual.length == expected.length * scale_value and actual.high_contrast_danger == bool(GameState.get_setting("high_contrast_danger", false)) and (not is_instance_valid(_sprite) or not _sprite.visible)


func _draw() -> void:
	if not _record.is_empty() and _uses_exact_geometry(_record):
		var bottom := float(_record.geometry.aim_direction.x) < 0.0
		draw_rect(Rect2(Vector2(-640, -270) if bottom else Vector2(0, -90), Vector2(640, 360)), Color.WHITE)
