class_name LaunchHostilePayloadProjection
extends CharacterBody2D

const RiftReceiver := preload("res://scripts/enemies/launch/launch_payload_rift_receiver.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")

var payload_id := ""
var _authority: WeakRef
var _definition: Dictionary = {}
var _sprite: Sprite2D
var _shape: CollisionShape2D


func configure_payload(authority: RefCounted, id: String, definition: Dictionary) -> bool:
	if _authority != null or authority == null or id.is_empty():
		return false
	_authority = weakref(authority)
	payload_id = id
	_definition = definition.duplicate(true)
	name = id
	collision_layer = 0
	collision_mask = 3 if definition.kind == "projectile" else 0
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	set_physics_process(false)
	var circle := CircleShape2D.new()
	circle.radius = float(definition.radius)
	_shape = CollisionShape2D.new()
	_shape.name = "CollisionShape2D"
	_shape.shape = circle
	_shape.disabled = definition.kind != "projectile"
	add_child(_shape)
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = load("res://data/content_packs/base/assets/enemies/launch/%s.png" % ("acid_projectile" if definition.kind == "projectile" else "acid_pool"))
	if _sprite.texture == null:
		return false
	_sprite.hframes = 4
	if definition.kind == "projectile":
		_sprite.rotation = Vector2(definition.direction.x, definition.direction.y).angle()
	else:
		_sprite.scale = Vector2.ONE * float(definition.radius) / 13.0
	add_child(_sprite)
	var receiver := RiftReceiver.new()
	receiver.name = "RiftReceiver"
	receiver.collision_layer = 1
	receiver.collision_mask = 0
	receiver.monitoring = false
	var receiver_shape := CollisionShape2D.new()
	receiver_shape.name = "CollisionShape2D"
	receiver_shape.shape = circle.duplicate()
	receiver.add_child(receiver_shape)
	add_child(receiver)
	return true


func project_record(record: Dictionary, frame: int) -> bool:
	if not native_projection_is_ready():
		return false
	var point: Dictionary = record.position if _definition.kind == "projectile" else _definition.position
	global_position = Vector2(float(point.x), float(point.y))
	visible = record.phase != "PENDING"
	collision_mask = 3 if _definition.kind == "projectile" and visible else 0
	_sprite.frame = (frame / 6) % 4
	_sprite.modulate = Color(1.0, 0.95, 0.45, 0.65 if frame % 12 < 6 else 1.0) if record.phase == "WARNING" else Color.WHITE
	if visible:
		get_node("RiftReceiver").collision_layer = 1
		add_to_group("time_stoppable")
		add_to_group("launch_hostile_payloads")
	else:
		deactivate()
	return true


func deactivate() -> void:
	visible = false
	collision_mask = 0
	remove_from_group("time_stoppable")
	remove_from_group("launch_hostile_payloads")
	var receiver := get_node_or_null("RiftReceiver") as Area2D
	if receiver != null:
		receiver.collision_layer = 0


func native_definition_matches(definition: Dictionary) -> bool:
	if not native_projection_is_ready() or definition != _definition or not _shape.shape is CircleShape2D or not _shape.transform.is_equal_approx(Transform2D.IDENTITY) or _shape.disabled != (definition.kind != "projectile") or not is_equal_approx(_shape.shape.radius, float(definition.radius)):
		return false
	var receiver := get_node_or_null("RiftReceiver") as Area2D
	var receiver_shape := get_node_or_null("RiftReceiver/CollisionShape2D") as CollisionShape2D
	if not receiver.transform.is_equal_approx(Transform2D.IDENTITY) or receiver.collision_layer != (1 if visible else 0) or receiver.collision_mask != 0 or receiver.monitoring or not receiver.monitorable or not receiver_shape.shape is CircleShape2D or receiver_shape.disabled or not receiver_shape.transform.is_equal_approx(Transform2D.IDENTITY) or not is_equal_approx(receiver_shape.shape.radius, float(definition.radius)):
		return false
	return collision_layer == 0 and collision_mask == (3 if definition.kind == "projectile" and visible else 0) and global_scale.is_equal_approx(Vector2.ONE) and is_zero_approx(global_rotation) and _sprite.visible and _sprite.texture != null and _sprite.hframes == 4 and is_in_group("time_stoppable") == visible and is_in_group("launch_hostile_payloads") == visible


func native_projection_is_ready() -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(_shape) or not is_instance_valid(_sprite) or _shape.get_parent() != self or _sprite.get_parent() != self or not _shape.is_inside_tree() or not _sprite.is_inside_tree():
		return false
	var receiver := get_node_or_null("RiftReceiver") as Area2D
	var receiver_shape := get_node_or_null("RiftReceiver/CollisionShape2D") as CollisionShape2D
	return is_instance_valid(receiver) and is_instance_valid(receiver_shape) and receiver.is_inside_tree() and receiver_shape.is_inside_tree() and receiver.get_parent() == self and receiver_shape.get_parent() == receiver


func apply_time_stop(duration: float) -> void:
	var authority := _owner()
	if authority != null:
		apply_time_stop_source(StringName("payload-stop-%d" % int(authority.snapshot().runtime_frame)), duration)


func apply_time_stop_source(source_id: StringName, duration: float) -> void:
	var authority := _owner()
	if authority != null and is_finite(duration) and duration > 0.0:
		authority.add_control_source(payload_id, str(source_id), "stop", mini(Contract.MAX_FRAME, ceili(duration * 60.0)), 1.0)


func clear_time_stop_source(source_id: StringName) -> void:
	var authority := _owner()
	if authority != null:
		authority.clear_control_source(payload_id, str(source_id))


func apply_time_rift(source_id: StringName, multiplier: float) -> void:
	var authority := _owner()
	if authority != null:
		authority.add_control_source(payload_id, str(source_id), "rift", Contract.MAX_FRAME, multiplier)


func clear_time_rift(source_id: StringName) -> void:
	clear_time_stop_source(source_id)


func is_time_stopped() -> bool:
	var authority := _owner()
	return authority != null and bool(authority.payload_modifiers(payload_id).get("action_paused", false))


func _owner() -> RefCounted:
	return _authority.get_ref() if _authority != null else null
