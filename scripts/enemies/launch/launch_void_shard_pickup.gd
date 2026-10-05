class_name LaunchVoidShardPickup
extends Area2D

const Construct := preload("res://scripts/enemies/launch/launch_void_arena_construct.gd")
var _boss: Node2D
var _projection: Dictionary = {}
var _shape: CollisionShape2D
var _sprite: Sprite2D


func configure(boss: Node2D) -> void:
	_boss = boss
	top_level = true
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	_shape = CollisionShape2D.new()
	_shape.shape = CircleShape2D.new()
	add_child(_shape)
	_sprite = Sprite2D.new()
	_sprite.texture = Construct.artwork("core")
	_sprite.hframes = 3
	_sprite.scale = Vector2(0.5, 0.5)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func present(value: Dictionary) -> void:
	_projection = value.duplicate(true)
	global_position = Vector2(float(value.position.x), float(value.position.y))
	_shape.shape.radius = float(value.radius_px)
	set_meta("stable_pickup_key", str(_boss.hostile_source_id) + "/" + str(value.id))


func native_geometry_matches(value: Dictionary) -> bool:
	return is_inside_tree() and _projection == value and get_parent() == _boss.get_node("VoidAuxiliaryPickups") and get_child_count() == 2 and top_level and global_transform == Transform2D(0.0, Vector2(float(value.position.x), float(value.position.y))) and visible and modulate == Color.WHITE and self_modulate == Color.WHITE and not monitoring and not monitorable and collision_layer == 0 and collision_mask == 0 and _shape.transform == Transform2D.IDENTITY and not _shape.disabled and _shape.shape is CircleShape2D and _shape.shape.radius == value.radius_px and _sprite.visible and _sprite.texture == Construct.artwork("core") and _sprite.hframes == 3 and _sprite.vframes == 1 and _sprite.frame == 0 and _sprite.transform == Transform2D(0.0, Vector2(0.5, 0.5), 0.0, Vector2.ZERO) and _sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and _sprite.centered and not _sprite.region_enabled and not _sprite.flip_h and not _sprite.flip_v and _sprite.modulate == Color.WHITE and _sprite.self_modulate == Color.WHITE
