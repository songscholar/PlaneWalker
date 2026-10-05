class_name LaunchBossConstruct
extends StaticBody2D

const ARTWORK_PATH := "res://assets/production/constructs/ruins_cover.png"
static var _artwork: Texture2D


static func _artwork_texture() -> Texture2D:
	if _artwork == null:
		_artwork = load(ARTWORK_PATH) as Texture2D
	return _artwork

class ConstructHurtbox extends Area2D:
	func receive_hit(damage_info: RefCounted) -> float:
		return get_parent().receive_hit(damage_info)

	func stable_entity_key() -> String:
		return get_parent().stable_entity_key()

var _boss: Node2D
var _id := ""
var _projection: Dictionary = {}
var _body_shape: CollisionShape2D
var _hurt_shape: CollisionShape2D
var _hurtbox: Area2D
var _sprite: Sprite2D


func configure(boss: Node2D, id: String) -> void:
	_boss = boss
	_id = id
	top_level = true
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	collision_mask = 0
	_body_shape = CollisionShape2D.new()
	_body_shape.name = "CollisionShape2D"
	_body_shape.shape = CircleShape2D.new()
	add_child(_body_shape)
	_hurtbox = ConstructHurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_mask = 0
	_hurtbox.monitoring = false
	add_child(_hurtbox)
	_hurt_shape = CollisionShape2D.new()
	_hurt_shape.name = "CollisionShape2D"
	_hurt_shape.shape = CircleShape2D.new()
	_hurtbox.add_child(_hurt_shape)
	_sprite = Sprite2D.new()
	_sprite.texture = _artwork_texture()
	_sprite.hframes = 3
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.position = Vector2(0.0, -8.0)
	add_child(_sprite)
	set_meta("stable_target_key", stable_entity_key())
	set_meta("stable_target_id", 1073741824 + (stable_entity_key().sha256_text().substr(0, 8).hex_to_int() & 1073741823))


func receive_hit(damage_info: RefCounted) -> float:
	return float(_boss.receive_native_construct_hit(_id, damage_info)) if is_instance_valid(_boss) else 0.0


func stable_entity_key() -> String:
	return str(_boss.hostile_source_id) + "/" + _id if is_instance_valid(_boss) else ""


func native_construct_snapshot() -> Dictionary:
	return _projection.duplicate(true)


func present(value: Dictionary, origin: Vector2, terminal: bool) -> void:
	_projection = value.duplicate(true)
	global_position = origin + Vector2(float(value.position.x), float(value.position.y))
	_body_shape.shape.radius = float(value.radius_px)
	_hurt_shape.shape.radius = float(value.radius_px)
	var live: bool = not value.broken and not terminal
	collision_layer = 1 if live else 0
	_hurtbox.collision_layer = 4 if live else 0
	_sprite.frame = 2 if value.broken else (1 if float(value.current_hp) <= float(value.max_hp) * 0.5 else 0)
	visible = not terminal


func native_geometry_matches(value: Dictionary, origin: Vector2, terminal: bool) -> bool:
	var live: bool = not value.broken and not terminal
	var expected_frame := 2 if value.broken else (1 if float(value.current_hp) <= float(value.max_hp) * 0.5 else 0)
	if not is_inside_tree() or not is_instance_valid(_sprite) or _sprite.get_parent() != self or not _sprite.is_inside_tree() or visible != (not terminal) or modulate != Color.WHITE or self_modulate != Color.WHITE:
		return false
	if not _sprite.visible or _sprite.texture == null or _sprite.texture != _artwork_texture() or _sprite.hframes != 3 or _sprite.vframes != 1 or _sprite.frame != expected_frame or not _sprite.centered or _sprite.offset != Vector2.ZERO or _sprite.region_enabled or _sprite.flip_h or _sprite.flip_v or _sprite.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST or _sprite.modulate != Color.WHITE or _sprite.self_modulate != Color.WHITE or _sprite.transform != Transform2D(0.0, Vector2(0.0, -8.0)):
		return false
	return get_parent() == _boss.get_node("ArenaConstructs") and top_level and _projection == value and global_position == origin + Vector2(float(value.position.x), float(value.position.y)) and global_transform.x == Vector2.RIGHT and global_transform.y == Vector2.DOWN and _body_shape.transform == Transform2D.IDENTITY and _hurtbox.transform == Transform2D.IDENTITY and _hurt_shape.transform == Transform2D.IDENTITY and not _body_shape.disabled and not _hurt_shape.disabled and _body_shape.shape is CircleShape2D and _hurt_shape.shape is CircleShape2D and _body_shape.shape.radius == value.radius_px and _hurt_shape.shape.radius == value.radius_px and collision_layer == (1 if live else 0) and collision_mask == 0 and _hurtbox.collision_layer == (4 if live else 0) and _hurtbox.collision_mask == 0
