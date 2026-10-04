class_name LaunchSemanticZoneProjection
extends Node2D

var _record: Dictionary = {}
var _sprite: Sprite2D


func project_record(record: Dictionary, frame: int) -> bool:
	if not is_inside_tree() or is_queued_for_deletion():
		return false
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite2D"
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.hframes = 4
		add_child(_sprite)
	var texture := load("res://assets/production/hostile_effects/%s_pool.png" % record.damage_type) as Texture2D
	if texture == null:
		return false
	_record = record.duplicate(true)
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
	_sprite.modulate = Color(1.0, 0.95, 0.45, 0.65 if frame % 12 < 6 else 1.0) if record.phase == "WARNING" else Color.WHITE
	visible = record.phase != "PENDING"
	return true


func matches_record(record: Dictionary) -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and record == _record and visible and global_position == Vector2(float(record.geometry.origin.x), float(record.geometry.origin.y)) and is_instance_valid(_sprite) and _sprite.get_parent() == self and _sprite.texture != null and _sprite.visible and _sprite.hframes == 4
