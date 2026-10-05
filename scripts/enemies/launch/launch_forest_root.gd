class_name LaunchForestRoot
extends "res://scripts/enemies/launch/launch_boss_construct.gd"

const ROOT_ART := "res://assets/production/constructs/forest_root.png"
static var _root_artwork: Texture2D


static func root_texture() -> Texture2D:
	if _root_artwork == null:
		_root_artwork = load(ROOT_ART) as Texture2D
	return _root_artwork


func configure(boss: Node2D, id: String) -> void:
	super.configure(boss, id)
	_sprite.texture = root_texture()
	_sprite.position = Vector2.ZERO


func present(value: Dictionary, origin: Vector2, terminal: bool) -> void:
	_projection = value.duplicate(true)
	global_position = origin + Vector2(float(value.position.x), float(value.position.y))
	_body_shape.shape.radius = 12.0
	_hurt_shape.shape.radius = 12.0
	var live: bool = not value.broken and not value.retired and not terminal
	collision_layer = 1 if live else 0
	_hurtbox.collision_layer = 4 if live else 0
	_sprite.frame = 2 if value.broken or value.retired else (1 if float(value.current_hp) <= 50.0 else 0)
	visible = not terminal


func native_geometry_matches(value: Dictionary, origin: Vector2, terminal: bool) -> bool:
	var live: bool = not value.broken and not value.retired and not terminal
	var expected_frame := 2 if value.broken or value.retired else (1 if float(value.current_hp) <= 50.0 else 0)
	return is_inside_tree() and get_child_count() == 3 and get_parent() == _boss.get_node("ArenaConstructs") and top_level and _projection == value and global_transform == Transform2D(0.0, origin + Vector2(float(value.position.x), float(value.position.y))) and visible == (not terminal) and modulate == Color.WHITE and self_modulate == Color.WHITE and _body_shape.transform == Transform2D.IDENTITY and _hurtbox.transform == Transform2D.IDENTITY and _hurt_shape.transform == Transform2D.IDENTITY and not _body_shape.disabled and not _hurt_shape.disabled and _body_shape.shape is CircleShape2D and _hurt_shape.shape is CircleShape2D and _body_shape.shape.radius == 12.0 and _hurt_shape.shape.radius == 12.0 and collision_layer == (1 if live else 0) and collision_mask == 0 and _hurtbox.collision_layer == (4 if live else 0) and _hurtbox.collision_mask == 0 and not _hurtbox.monitoring and _sprite.texture == root_texture() and _sprite.hframes == 3 and _sprite.vframes == 1 and _sprite.frame == expected_frame and _sprite.transform == Transform2D.IDENTITY and _sprite.visible and _sprite.centered and not _sprite.region_enabled and not _sprite.flip_h and not _sprite.flip_v and _sprite.offset == Vector2.ZERO and _sprite.modulate == Color.WHITE and _sprite.self_modulate == Color.WHITE
