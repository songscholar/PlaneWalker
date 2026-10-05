class_name LaunchRuinDebris
extends StaticBody2D

const Construct := preload("res://scripts/enemies/launch/launch_boss_construct.gd")
var _authority: WeakRef
var _id := ""
var _projection: Dictionary = {}
var _shape: CollisionShape2D
var _hurtbox: Area2D
var _hurt_shape: CollisionShape2D
var _sprite: Sprite2D

class DebrisHurtbox extends Area2D:
	func receive_hit(info: RefCounted) -> float:
		return get_parent().receive_hit(info)

	func stable_entity_key() -> String:
		return get_parent().stable_entity_key()


func configure(authority: RefCounted, id: String) -> void:
	_authority = weakref(authority)
	_id = id
	top_level = true
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	collision_mask = 0
	_shape = CollisionShape2D.new()
	_shape.name = "CollisionShape2D"
	_shape.shape = CircleShape2D.new()
	_shape.shape.radius = 12.0
	add_child(_shape)
	_hurtbox = DebrisHurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.monitoring = false
	_hurtbox.collision_mask = 0
	_hurt_shape = CollisionShape2D.new()
	_hurt_shape.name = "CollisionShape2D"
	_hurt_shape.shape = _shape.shape.duplicate()
	_hurtbox.add_child(_hurt_shape)
	add_child(_hurtbox)
	_sprite = Sprite2D.new()
	_sprite.texture = Construct._artwork_texture()
	_sprite.hframes = 3
	_sprite.frame = 2
	_sprite.position = Vector2(0, -13)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	set_meta("stable_target_key", _id)
	set_meta("stable_target_id", 1073741824 + (_id.sha256_text().substr(0, 8).hex_to_int() & 1073741823))


func stable_entity_key() -> String:
	return _id


func receive_hit(info: RefCounted) -> float:
	var owner: RefCounted = _authority.get_ref()
	return float(owner.receive_debris_hit(_id, info)) if owner != null else 0.0


func native_construct_snapshot() -> Dictionary:
	var value := _projection.duplicate(true)
	if not value.is_empty():
		value["broken"] = value.phase != "ACTIVE"
	return value


func present(row: Dictionary) -> void:
	_projection = row.duplicate(true)
	global_position = Vector2(float(row.position.x), float(row.position.y))
	visible = row.phase == "ACTIVE"
	collision_layer = 1 if visible else 0
	_hurtbox.collision_layer = 4 if visible else 0


func deactivate() -> void:
	visible = false
	collision_layer = 0
	_hurtbox.collision_layer = 0


func native_geometry_matches(row: Dictionary) -> bool:
	return is_inside_tree() and get_child_count() == 3 and _projection == row and _id == row.id and top_level and global_transform == Transform2D(0.0, Vector2(float(row.position.x), float(row.position.y))) and visible == (row.phase == "ACTIVE") and collision_layer == (1 if visible else 0) and collision_mask == 0 and _hurtbox.collision_layer == (4 if visible else 0) and _hurtbox.collision_mask == 0 and not _hurtbox.monitoring and _hurtbox.transform == Transform2D.IDENTITY and _shape.transform == Transform2D.IDENTITY and _hurt_shape.transform == Transform2D.IDENTITY and not _shape.disabled and not _hurt_shape.disabled and _shape.shape is CircleShape2D and _hurt_shape.shape is CircleShape2D and _shape.shape.radius == 12.0 and _hurt_shape.shape.radius == 12.0 and _sprite.texture == Construct._artwork_texture() and _sprite.hframes == 3 and _sprite.vframes == 1 and _sprite.frame == 2 and _sprite.transform == Transform2D(0.0, Vector2(0, -13)) and _sprite.modulate == Color.WHITE and _sprite.self_modulate == Color.WHITE and modulate == Color.WHITE and self_modulate == Color.WHITE
