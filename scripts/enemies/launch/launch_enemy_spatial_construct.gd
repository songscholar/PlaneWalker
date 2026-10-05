class_name LaunchEnemySpatialConstruct
extends StaticBody2D

class SpatialHurtbox extends Area2D:
	func receive_hit(info: RefCounted) -> float:
		return get_parent().receive_hit(info)

	func stable_entity_key() -> String:
		return get_parent().stable_entity_key()

var _authority: WeakRef
var _id := ""
var _record := {}
var _body_shape: CollisionShape2D
var _hurtbox: Area2D
var _hurt_shape: CollisionShape2D
var _sprite: Sprite2D
var _second: Sprite2D


func configure(authority: RefCounted, id: String) -> void:
	_authority = weakref(authority)
	_id = id
	top_level = true
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	collision_mask = 0
	_body_shape = CollisionShape2D.new()
	_body_shape.name = "CollisionShape2D"
	_body_shape.shape = RectangleShape2D.new()
	add_child(_body_shape)
	_hurtbox = SpatialHurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.collision_mask = 0
	_hurtbox.monitoring = false
	_hurt_shape = CollisionShape2D.new()
	_hurt_shape.name = "CollisionShape2D"
	_hurt_shape.shape = RectangleShape2D.new()
	_hurtbox.add_child(_hurt_shape)
	add_child(_hurtbox)
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.hframes = 4
	add_child(_sprite)
	_second = Sprite2D.new()
	_second.name = "SecondPortal"
	_second.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_second.hframes = 4
	add_child(_second)
	set_meta("stable_target_key", id)
	set_meta("stable_target_id", 1073741824 + (id.sha256_text().substr(0, 8).hex_to_int() & 1073741823))


func stable_entity_key() -> String:
	return _id


func receive_hit(info: RefCounted) -> float:
	var authority: RefCounted = _authority.get_ref()
	return float(authority.receive_spatial_hit(_id, info)) if authority != null else 0.0


func native_construct_snapshot() -> Dictionary:
	return _record.duplicate(true)


func present(row: Dictionary, frame: int) -> bool:
	_record = row.duplicate(true)
	var fact: Dictionary = row.geometry[0]
	var origin := Vector2(float(fact.origin.x), float(fact.origin.y))
	var direction := Vector2(float(fact.aim_direction.x), float(fact.aim_direction.y))
	var portal: bool = row.kind == "portal"
	global_position = origin if portal else origin + direction * float(fact.length) * 0.5
	global_rotation = 0.0 if portal else direction.angle()
	var size := Vector2(32, 32) if portal else Vector2(float(fact.length), float(fact.radius) * 2.0)
	_body_shape.shape.size = size
	_hurt_shape.shape.size = size
	visible = row.phase in ["WARNING", "ACTIVE", "COLLAPSE"]
	collision_layer = 1 if row.kind == "wall" and row.phase == "ACTIVE" else 0
	_hurtbox.collision_layer = 4 if row.kind in ["wall", "link"] and row.phase == "ACTIVE" else 0
	var asset := "bramble_wall" if row.kind == "wall" and row.definition_id == "bramble_mage" else ("web_wall" if row.kind == "wall" else "web_link")
	if portal:
		asset = "portal_enemy" if row.parameters.team_rule == "enemy_only" else "portal_both"
	_sprite.texture = load("res://assets/production/enemy_spatial/%s.png" % asset) as Texture2D
	if _sprite.texture == null:
		return false
	_sprite.scale = Vector2.ONE if portal else Vector2(size.x / 64.0, size.y / 16.0)
	_sprite.frame = 0 if row.phase in ["WARNING", "COLLAPSE"] else 1 + (frame / 8) % 3
	_sprite.modulate = Color(1.0, 0.95, 0.55, 0.8) if row.phase in ["WARNING", "COLLAPSE"] else Color.WHITE
	_second.texture = _sprite.texture
	_second.scale = Vector2.ONE
	_second.frame = _sprite.frame
	_second.modulate = _sprite.modulate
	_second.visible = portal
	_second.position = Vector2(float(row.geometry[1].origin.x), float(row.geometry[1].origin.y)) - origin if portal else Vector2.ZERO
	return true


func deactivate() -> void:
	visible = false
	collision_layer = 0
	_hurtbox.collision_layer = 0


func matches_record(row: Dictionary, frame: int) -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or get_child_count() != 4 or _record != row or _id != row.id or not top_level or modulate != Color.WHITE or self_modulate != Color.WHITE:
		return false
	var portal: bool = row.kind == "portal"
	var fact: Dictionary = row.geometry[0]
	var origin := Vector2(float(fact.origin.x), float(fact.origin.y))
	var direction := Vector2(float(fact.aim_direction.x), float(fact.aim_direction.y))
	var position_expected := origin if portal else origin + direction * float(fact.length) * 0.5
	var transform_expected := Transform2D(0.0 if portal else direction.angle(), position_expected)
	var size := Vector2(32, 32) if portal else Vector2(float(fact.length), float(fact.radius) * 2.0)
	var active: bool = row.phase == "ACTIVE"
	var color := Color(1.0, 0.95, 0.55, 0.8) if row.phase in ["WARNING", "COLLAPSE"] else Color.WHITE
	var atlas_frame: int = 0 if row.phase in ["WARNING", "COLLAPSE"] else 1 + (frame / 8) % 3
	var asset := "bramble_wall" if row.kind == "wall" and row.definition_id == "bramble_mage" else ("web_wall" if row.kind == "wall" else "web_link")
	if portal:
		asset = "portal_enemy" if row.parameters.team_rule == "enemy_only" else "portal_both"
	if not global_transform.is_equal_approx(transform_expected) or visible != (row.phase in ["WARNING", "ACTIVE", "COLLAPSE"]) or collision_layer != (1 if active and row.kind == "wall" else 0) or collision_mask != 0 or _hurtbox.collision_layer != (4 if active and row.kind in ["wall", "link"] else 0) or _hurtbox.collision_mask != 0 or _hurtbox.monitoring or _hurtbox.transform != Transform2D.IDENTITY:
		return false
	if _body_shape.transform != Transform2D.IDENTITY or _hurt_shape.transform != Transform2D.IDENTITY or _body_shape.disabled or _hurt_shape.disabled or not _body_shape.shape is RectangleShape2D or not _hurt_shape.shape is RectangleShape2D or _body_shape.shape.size != size or _hurt_shape.shape.size != size:
		return false
	if not _sprite.visible or _sprite.texture == null or _sprite.texture.resource_path != "res://assets/production/enemy_spatial/%s.png" % asset or _sprite.hframes != 4 or _sprite.frame != atlas_frame or _sprite.modulate != color or _sprite.position != Vector2.ZERO or _sprite.scale != (Vector2.ONE if portal else Vector2(size.x / 64.0, size.y / 16.0)):
		return false
	return _second.visible == portal and _second.position == (Vector2(float(row.geometry[1].origin.x), float(row.geometry[1].origin.y)) - origin if portal else Vector2.ZERO) and _second.texture == _sprite.texture and _second.frame == atlas_frame and _second.modulate == color
