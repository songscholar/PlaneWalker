class_name LaunchVoidArenaConstruct
extends "res://scripts/enemies/launch/launch_boss_construct.gd"

static var _textures: Dictionary = {}


static func artwork(kind: String) -> Texture2D:
	if not _textures.has(kind):
		_textures[kind] = load("res://assets/production/constructs/void_%s.png" % kind)
	return _textures[kind]


func configure(boss: Node2D, id: String) -> void:
	super.configure(boss, id)
	_sprite.texture = artwork("core" if id.begins_with("void_plane_core:") else "pillar")
	_sprite.position = Vector2(0, -8)


func receive_hit(damage_info: RefCounted) -> float:
	return float(_boss.receive_native_void_construct_hit(_id, damage_info)) if is_instance_valid(_boss) else 0.0


func present(value: Dictionary, origin: Vector2, terminal: bool) -> void:
	_projection = value.duplicate(true)
	global_position = origin + Vector2(float(value.position.x), float(value.position.y))
	_body_shape.shape.radius = float(value.radius_px)
	_hurt_shape.shape.radius = float(value.radius_px)
	var live: bool = not value.broken and not value.get("debris", false) and not terminal
	collision_layer = 1 if live else 0
	_hurtbox.collision_layer = 4 if live else 0
	_sprite.frame = 2 if value.broken or value.get("debris", false) else (1 if float(value.current_hp) <= float(value.max_hp) * 0.5 else 0)
	visible = not terminal


func native_geometry_matches(value: Dictionary, origin: Vector2, terminal: bool) -> bool:
	var live: bool = not value.broken and not value.get("debris", false) and not terminal
	var expected_frame := 2 if value.broken or value.get("debris", false) else (1 if float(value.current_hp) <= float(value.max_hp) * 0.5 else 0)
	var kind := "core" if str(value.recipe_id) == "void_plane_core" else "pillar"
	return is_inside_tree() and get_child_count() == 3 and get_parent() == _boss.get_node("VoidArenaConstructs") and top_level and _id == value.id and _projection == value and global_transform == Transform2D(0.0, origin + Vector2(float(value.position.x), float(value.position.y))) and visible == (not terminal) and modulate == Color.WHITE and self_modulate == Color.WHITE and _body_shape.transform == Transform2D.IDENTITY and _hurtbox.transform == Transform2D.IDENTITY and _hurt_shape.transform == Transform2D.IDENTITY and not _body_shape.disabled and not _hurt_shape.disabled and _body_shape.shape is CircleShape2D and _hurt_shape.shape is CircleShape2D and _body_shape.shape.radius == value.radius_px and _hurt_shape.shape.radius == value.radius_px and collision_layer == (1 if live else 0) and collision_mask == 0 and _hurtbox.collision_layer == (4 if live else 0) and _hurtbox.collision_mask == 0 and not _hurtbox.monitoring and _sprite.texture == artwork(kind) and _sprite.hframes == 3 and _sprite.vframes == 1 and _sprite.frame == expected_frame and _sprite.transform == Transform2D(0.0, Vector2(0, -8)) and _sprite.visible and _sprite.centered and not _sprite.region_enabled and not _sprite.flip_h and not _sprite.flip_v and _sprite.modulate == Color.WHITE and _sprite.self_modulate == Color.WHITE
