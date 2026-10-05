class_name LaunchForestAuxiliaryConstruct
extends StaticBody2D

const Base := preload("res://scripts/enemies/launch/launch_boss_construct.gd")
var _boss: Node2D
var _kind := ""
var _projection: Dictionary = {}
var _shape: CollisionShape2D
var _hurtbox: Area2D
var _hurt_shape: CollisionShape2D
var _sprite: Sprite2D
var _texture: Texture2D


func configure(boss: Node2D, kind: String) -> void:
	_boss = boss
	_kind = kind
	top_level = true
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	collision_mask = 0
	_shape = CollisionShape2D.new()
	_shape.name = "CollisionShape2D"
	_shape.shape = RectangleShape2D.new() if kind == "wall" or kind == "erosion" else CircleShape2D.new()
	add_child(_shape)
	_hurtbox = Base.ConstructHurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_mask = 0
	_hurtbox.monitoring = false
	add_child(_hurtbox)
	_hurt_shape = CollisionShape2D.new()
	_hurt_shape.name = "CollisionShape2D"
	_hurt_shape.shape = _shape.shape.duplicate()
	_hurtbox.add_child(_hurt_shape)
	_texture = load("res://assets/production/constructs/forest_%s.png" % ("wall" if kind == "erosion" else kind)) as Texture2D
	_sprite = Sprite2D.new()
	_sprite.texture = _texture
	_sprite.hframes = 3
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)


func stable_entity_key() -> String:
	return str(_boss.hostile_source_id) + "/" + str(_projection.get("id", "")) if is_instance_valid(_boss) else ""


func receive_hit(info: RefCounted) -> float:
	return float(_boss.receive_native_forest_auxiliary_hit(str(_projection.id), info)) if _kind in ["sac", "wall"] and is_instance_valid(_boss) else 0.0


func native_construct_snapshot() -> Dictionary:
	return _projection.duplicate(true)


func present(value: Dictionary, origin: Vector2, terminal: bool) -> void:
	_projection = value.duplicate(true)
	global_position = origin + Vector2(float(value.position.x), float(value.position.y))
	global_rotation = float(value.get("rotation", 0.0))
	if _shape.shape is CircleShape2D:
		_shape.shape.radius = float(value.radius_px)
		_hurt_shape.shape.radius = float(value.radius_px)
	else:
		_shape.shape.size = Vector2(float(value.length), float(value.thickness))
		_hurt_shape.shape.size = _shape.shape.size
	var live := not terminal and not bool(value.get("broken", false)) and not bool(value.get("expired", false)) and not bool(value.get("used", false))
	collision_layer = 1 if live and _kind != "flower" else 0
	_hurtbox.collision_layer = 4 if live and _kind in ["sac", "wall"] else 0
	_sprite.frame = 2 if not live else (1 if bool(value.get("marked", false)) or float(value.get("current_hp", 100.0)) <= float(value.get("max_hp", 100.0)) * 0.5 else 0)
	_sprite.scale = Vector2(float(value.length) / 48.0, float(value.thickness) / 12.0) if _kind in ["wall", "erosion"] else Vector2.ONE
	visible = not terminal
	set_meta("stable_target_key", stable_entity_key())
	set_meta("stable_target_id", 1073741824 + (stable_entity_key().sha256_text().substr(0, 8).hex_to_int() & 1073741823))


func native_geometry_matches(value: Dictionary, origin: Vector2, terminal: bool) -> bool:
	var live := not terminal and not bool(value.get("broken", false)) and not bool(value.get("expired", false)) and not bool(value.get("used", false))
	var transform := Transform2D(float(value.get("rotation", 0.0)), origin + Vector2(float(value.position.x), float(value.position.y)))
	var shape_ok: bool = _shape.shape is CircleShape2D and _hurt_shape.shape is CircleShape2D and _shape.shape.radius == value.radius_px and _hurt_shape.shape.radius == value.radius_px if _kind in ["sac", "flower"] else _shape.shape is RectangleShape2D and _hurt_shape.shape is RectangleShape2D and _shape.shape.size == Vector2(float(value.length), float(value.thickness)) and _hurt_shape.shape.size == _shape.shape.size
	var expected_frame := 2 if not live else (1 if bool(value.get("marked", false)) or float(value.get("current_hp", 100.0)) <= float(value.get("max_hp", 100.0)) * 0.5 else 0)
	var scale_value := Vector2(float(value.length) / 48.0, float(value.thickness) / 12.0) if _kind in ["wall", "erosion"] else Vector2.ONE
	return is_inside_tree() and get_parent() == _boss.get_node("AuxiliaryConstructs") and get_child_count() == 3 and top_level and _projection == value and global_transform.is_equal_approx(transform) and visible == (not terminal) and modulate == Color.WHITE and self_modulate == Color.WHITE and shape_ok and _shape.transform == Transform2D.IDENTITY and _hurtbox.transform == Transform2D.IDENTITY and _hurt_shape.transform == Transform2D.IDENTITY and not _shape.disabled and not _hurt_shape.disabled and collision_layer == (1 if live and _kind != "flower" else 0) and collision_mask == 0 and _hurtbox.collision_layer == (4 if live and _kind in ["sac", "wall"] else 0) and _hurtbox.collision_mask == 0 and not _hurtbox.monitoring and _sprite.texture == _texture and _texture != null and _sprite.hframes == 3 and _sprite.vframes == 1 and _sprite.frame == expected_frame and _sprite.transform == Transform2D(0.0, scale_value, 0.0, Vector2.ZERO) and _sprite.visible and _sprite.modulate == Color.WHITE and _sprite.self_modulate == Color.WHITE
