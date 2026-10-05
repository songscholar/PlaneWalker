class_name LaunchHoundSigil
extends Node2D

const HurtboxBase := preload("res://scripts/enemies/launch/launch_boss_construct.gd")
const ARTWORK_PATH := "res://assets/production/enemy_mechanisms/hound_sigil.png"
var _owner: Node2D
var _hurtbox: Area2D
var _shape: CollisionShape2D
var _sprite: Sprite2D
var _projection := {}


func configure(actor: Node2D) -> void:
	_owner = actor
	_hurtbox = HurtboxBase.ConstructHurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	_hurtbox.collision_mask = 0
	_hurtbox.monitoring = false
	_shape = CollisionShape2D.new()
	_shape.name = "CollisionShape2D"
	_shape.shape = CircleShape2D.new()
	_shape.shape.radius = 12.0
	_hurtbox.add_child(_shape)
	add_child(_hurtbox)
	_sprite = Sprite2D.new()
	_sprite.texture = load(ARTWORK_PATH) as Texture2D
	_sprite.hframes = 4
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	set_meta("stable_target_key", stable_entity_key())
	set_meta("stable_target_id", 1073741824 + (stable_entity_key().sha256_text().substr(0, 8).hex_to_int() & 1073741823))


func stable_entity_key() -> String:
	return str(_owner.hostile_source_id) + "/dormant-sigil" if is_instance_valid(_owner) else ""


func receive_hit(info: RefCounted) -> float:
	return _owner.receive_native_hound_sigil_hit(info) if is_instance_valid(_owner) else 0.0


func native_weapon_target_is_active() -> bool:
	return is_instance_valid(_owner) and not _projection.is_empty() and not _projection.terminal and int(_projection.mechanism_state.dormancy_remaining_frames) > 0 and _hurtbox.collision_layer == 4


func present(state: Dictionary) -> void:
	_projection = state.duplicate(true)
	var live: bool = not state.terminal and int(state.mechanism_state.dormancy_remaining_frames) > 0
	visible = live
	_hurtbox.collision_layer = 4 if live else 0
	_sprite.frame = (int(state.runtime_frame) / 8) % 4
	_sprite.modulate = Color.WHITE if float(state.mechanism_state.sigil_hp) > 6.0 else Color(1.0, 0.65, 0.45)


func native_geometry_matches(state: Dictionary) -> bool:
	var live: bool = not state.terminal and int(state.mechanism_state.dormancy_remaining_frames) > 0
	return is_inside_tree() and get_parent() == _owner and not is_queued_for_deletion() and get_child_count() == 2 and _projection == state and transform == Transform2D.IDENTITY and visible == live and _hurtbox.collision_layer == (4 if live else 0) and _hurtbox.collision_mask == 0 and not _hurtbox.monitoring and _hurtbox.transform == Transform2D.IDENTITY and _shape.transform == Transform2D.IDENTITY and not _shape.disabled and _shape.shape is CircleShape2D and _shape.shape.radius == 12.0 and _sprite.texture != null and _sprite.texture.resource_path == ARTWORK_PATH and _sprite.hframes == 4 and _sprite.frame == (int(state.runtime_frame) / 8) % 4 and _sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and _sprite.transform == Transform2D.IDENTITY
