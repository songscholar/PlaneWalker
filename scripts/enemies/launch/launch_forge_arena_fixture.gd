class_name LaunchForgeArenaFixture
extends Area2D

var _boss: Node2D
var _kind := ""
var _projection: Dictionary = {}
var _shape: CollisionShape2D
var _sprite: Sprite2D
var _artwork: Texture2D


func configure(boss: Node2D, kind: String) -> void:
	_boss = boss
	_kind = kind
	top_level = true
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	_shape = CollisionShape2D.new()
	_shape.shape = CircleShape2D.new()
	add_child(_shape)
	_artwork = load("res://assets/production/constructs/forge_%s.png" % kind) as Texture2D
	_sprite = Sprite2D.new()
	_sprite.texture = _artwork
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func present(value: Dictionary, origin: Vector2, terminal: bool) -> void:
	_projection = value.duplicate(true)
	global_position = origin + Vector2(float(value.position.x), float(value.position.y))
	_shape.shape.radius = float(value.radius_px)
	visible = not terminal


func native_geometry_matches(value: Dictionary, origin: Vector2, terminal: bool) -> bool:
	return get_parent() == _boss.get_node("ForgeFixtures") and is_inside_tree() and top_level and _projection == value and global_position == origin + Vector2(float(value.position.x), float(value.position.y)) and global_transform.x == Vector2.RIGHT and global_transform.y == Vector2.DOWN and modulate == Color.WHITE and self_modulate == Color.WHITE and visible == (not terminal) and collision_layer == 0 and collision_mask == 0 and not monitoring and not monitorable and _shape.get_parent() == self and not _shape.disabled and _shape.transform == Transform2D.IDENTITY and _shape.shape is CircleShape2D and _shape.shape.radius == float(value.radius_px) and _sprite.get_parent() == self and _sprite.is_inside_tree() and _sprite.visible and _sprite.texture == _artwork and _sprite.texture != null and _sprite.hframes == 1 and _sprite.vframes == 1 and _sprite.frame == 0 and _sprite.transform == Transform2D.IDENTITY and _sprite.centered and _sprite.offset == Vector2.ZERO and not _sprite.region_enabled and not _sprite.flip_h and not _sprite.flip_v and _sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and _sprite.modulate == Color.WHITE and _sprite.self_modulate == Color.WHITE
