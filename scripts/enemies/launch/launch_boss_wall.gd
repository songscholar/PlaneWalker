class_name LaunchBossWall
extends StaticBody2D

const ARTWORK_PATH := "res://assets/production/constructs/ruins_wall.png"
static var _artwork: Texture2D

class WallHurtbox extends Area2D:
	func receive_hit(damage_info: RefCounted) -> float:
		return get_parent().receive_hit(damage_info)

	func stable_entity_key() -> String:
		return get_parent().stable_entity_key()

var _boss: Node2D
var _id := ""
var _projection: Dictionary = {}
var _body_shape: CollisionShape2D
var _hurtbox: Area2D
var _hurt_shape: CollisionShape2D
var _sprite: Sprite2D


static func _artwork_texture() -> Texture2D:
	if _artwork == null:
		_artwork = load(ARTWORK_PATH) as Texture2D
	return _artwork


func configure(boss: Node2D, id: String) -> void:
	_boss = boss
	_id = id
	top_level = true
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	collision_mask = 0
	_body_shape = CollisionShape2D.new()
	_body_shape.name = "CollisionShape2D"
	_body_shape.shape = RectangleShape2D.new()
	_body_shape.shape.size = Vector2(64, 12)
	add_child(_body_shape)
	_hurtbox = WallHurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_mask = 0
	_hurtbox.monitoring = false
	add_child(_hurtbox)
	_hurt_shape = CollisionShape2D.new()
	_hurt_shape.name = "CollisionShape2D"
	_hurt_shape.shape = RectangleShape2D.new()
	_hurt_shape.shape.size = Vector2(64, 12)
	_hurtbox.add_child(_hurt_shape)
	_sprite = Sprite2D.new()
	_sprite.texture = _artwork_texture()
	_sprite.hframes = 3
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	set_meta("stable_target_key", stable_entity_key())
	set_meta("stable_target_id", 1073741824 + (stable_entity_key().sha256_text().substr(0, 8).hex_to_int() & 1073741823))


func stable_entity_key() -> String:
	return str(_boss.hostile_source_id) + "/" + _id if is_instance_valid(_boss) else ""


func receive_hit(damage_info: RefCounted) -> float:
	return float(_boss.receive_native_construct_hit(_id, damage_info)) if is_instance_valid(_boss) else 0.0


func native_construct_snapshot() -> Dictionary:
	return _projection.duplicate(true)


func present(value: Dictionary, origin: Vector2, terminal: bool) -> void:
	_projection = value.duplicate(true)
	global_position = origin + Vector2(float(value.position.x), float(value.position.y))
	global_rotation = Vector2(float(value.direction.x), float(value.direction.y)).angle()
	var live: bool = not value.broken and not value.expired and not terminal
	collision_layer = 1 if live else 0
	_hurtbox.collision_layer = 4 if live else 0
	_sprite.frame = 2 if value.broken or value.expired else (1 if value.current_hp <= 75.0 else 0)
	visible = not terminal


func native_geometry_matches(value: Dictionary, origin: Vector2, terminal: bool) -> bool:
	var live: bool = not value.broken and not value.expired and not terminal
	var direction := Vector2(float(value.direction.x), float(value.direction.y))
	var expected_frame := 2 if value.broken or value.expired else (1 if value.current_hp <= 75.0 else 0)
	if not is_inside_tree() or get_parent() != _boss.get_node("ArenaConstructs") or get_child_count() != 3 or _id != value.id or not top_level or _projection != value or global_position != origin + Vector2(float(value.position.x), float(value.position.y)) or not global_transform.x.is_equal_approx(direction) or not global_transform.y.is_equal_approx(Vector2(-direction.y, direction.x)) or visible != (not terminal) or modulate != Color.WHITE or self_modulate != Color.WHITE:
		return false
	if not _sprite.visible or _sprite.get_parent() != self or _sprite.texture == null or _sprite.texture != _artwork_texture() or _sprite.hframes != 3 or _sprite.vframes != 1 or _sprite.frame != expected_frame or not _sprite.centered or _sprite.offset != Vector2.ZERO or _sprite.region_enabled or _sprite.flip_h or _sprite.flip_v or _sprite.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST or _sprite.modulate != Color.WHITE or _sprite.self_modulate != Color.WHITE or _sprite.transform != Transform2D.IDENTITY:
		return false
	return _body_shape.transform == Transform2D.IDENTITY and _hurtbox.transform == Transform2D.IDENTITY and _hurt_shape.transform == Transform2D.IDENTITY and not _body_shape.disabled and not _hurt_shape.disabled and _body_shape.shape is RectangleShape2D and _hurt_shape.shape is RectangleShape2D and _body_shape.shape.size == Vector2(64, 12) and _hurt_shape.shape.size == Vector2(64, 12) and collision_layer == (1 if live else 0) and collision_mask == 0 and _hurtbox.collision_layer == (4 if live else 0) and _hurtbox.collision_mask == 0
