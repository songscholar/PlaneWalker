extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const WraithScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_ruins_wraith.tscn")
const StriderScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_stone_shell_strider.tscn")
const RoomScene := preload("res://data/content_packs/base/assets/rooms/launch/room_combat_open_field.tscn")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Damage := preload("res://scripts/combat/damage_info.gd")
var suite: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var actor := WraithScene.instantiate()
	suite.assert_true(actor.has_method("configure_launch_room_motion"), "Wraith requires a validated native room-motion boundary before crossing obstacles")
	var implemented: bool = actor.has_method("configure_launch_room_motion")
	actor.free()
	if implemented:
		await _test_native_wall_and_transaction()
		await _test_outer_corners()
	suite.finish(get_tree())


func _template() -> Dictionary:
	var values: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/room_templates.json"))
	for value: Dictionary in values:
		if value.id == "room_combat_open_field":
			return value.duplicate(true)
	return {}


func _room() -> Node2D:
	var room := RoomScene.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	room.position = Vector2(1000, 400)
	var collision := room.get_node("CameraBounds/CollisionShape2D") as CollisionShape2D
	collision.shape = collision.shape.duplicate()
	return room


func _actor(scene: PackedScene, id: String, position: Vector2) -> Node2D:
	var actor := scene.instantiate() as Node2D
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	actor.global_position = position
	var parser := Enemy.new()
	suite.assert_true(parser.configure(Content.enemy(id)).ok, "room-motion actor reads the real enemy definition")
	var identity := Actions.identity()
	identity["seed"] = 42
	suite.assert_true(actor.configure_launch_definition(parser.runtime_projection(), identity).ok, "room-motion actor consumes authored native geometry")
	var radius: float = Content.enemy(id).collision_radius_px
	suite.assert_equal(actor.get_node("CollisionShape2D").shape.radius, radius, "native body radius matches the authored enemy")
	suite.assert_equal(actor.get_node("Hurtbox/CollisionShape2D").shape.radius, radius, "native target radius matches the authored enemy")
	return actor


func _context(frame: int, position: Vector2, target: Vector2) -> Dictionary:
	var result := Actions.context(frame)
	result.source_position = {"x": position.x, "y": position.y}
	result.target_position = {"x": target.x, "y": target.y}
	return result


func _advance(actor: Node2D, frame: int, target: Vector2) -> Dictionary:
	var result: Dictionary = actor.prepare_launch_frame(frame, _context(frame, actor.global_position, target))
	suite.assert_true(result.ok, "bounded native motion prepares sequentially")
	if result.ok:
		suite.assert_true(actor.commit_launch_frame(result.ticket), "bounded native motion commits its transform")
		suite.assert_true(actor.publish_launch_frame(result.ticket), "bounded native motion retires its frame ticket")
	return result


func _assert_publication_refused(actor: Node2D, ticket: Dictionary, label: String) -> void:
	var allowed: bool = actor.can_publish_launch_frame(ticket)
	suite.assert_true(not allowed, label)
	if not allowed:
		suite.assert_true(not actor.publish_launch_frame(ticket), "refused publication retains the committed native frame ticket")


func _test_native_wall_and_transaction() -> void:
	var room := _room()
	var actor := _actor(WraithScene, "ruins_wraith", Vector2(1100, 500))
	var template := _template()
	var malformed := template.duplicate(true)
	malformed.id = "room_combat_crossroads"
	suite.assert_true(not actor.configure_launch_room_motion(room, malformed).ok, "foreign template cannot authorize obstacle passthrough")
	suite.assert_equal(actor.launch_room_motion_snapshot(), {}, "rejected room binding preserves unconfigured native motion")
	suite.assert_true(actor.configure_launch_room_motion(room, template).ok, "actual translated room installs its validated global boundary")
	var motion: Dictionary = actor.launch_room_motion_snapshot()
	suite.assert_equal(motion.bounds, {"x": 1000.0, "y": 400.0, "width": 640.0, "height": 360.0}, "room boundary uses the actual translated CameraBounds")
	suite.assert_equal(motion.collision_radius_px, 8.0, "Wraith centre margin uses its authored eight-pixel radius")
	var checkpoint: Dictionary = actor.launch_transaction_snapshot()
	var foreign := checkpoint.duplicate(true)
	foreign.actor.room_motion.bounds.width = 641.0
	suite.assert_true(not actor.can_restore_launch_transaction_snapshot(foreign), "foreign room bounds cannot splice into an otherwise real actor checkpoint")
	foreign = checkpoint.duplicate(true)
	foreign.actor.position.x = 1640.0
	suite.assert_true(not actor.can_restore_launch_transaction_snapshot(foreign), "checkpoint restore cannot place the actor across its body-radius margin")
	var before: Dictionary = actor.launch_runtime_snapshot()
	var prepared: Dictionary = actor.prepare_launch_frame(1, _context(1, actor.global_position, Vector2(2000, 500)))
	suite.assert_true(prepared.ok, "room-bounded Wraith prepares its first pursuit frame")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "room-bounded preparation cannot move live domain or native body")
	suite.assert_true(actor.commit_launch_frame(prepared.ticket), "room-bounded pursuit commits predicted movement")
	suite.assert_true(actor.rollback_launch_frame(prepared.ticket) and actor.restore_launch_transaction_snapshot(checkpoint), "rejected room-bounded movement restores exact native and Health state")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "room-bounded rollback restores the full original snapshot")
	var retried: Dictionary = _advance(actor, 1, Vector2(2000, 500))
	suite.assert_equal(retried.ticket.after, prepared.ticket.after, "the same room-bounded frame produces the same candidate on retry")
	suite.assert_equal(actor.collision_mask, 1, "passthrough does not mutate the body's ordinary collision mask")
	room.position.x += 1.0
	var accepted: Dictionary = actor.launch_runtime_snapshot()
	suite.assert_true(not actor.prepare_launch_frame(2, _context(2, actor.global_position, Vector2(2000, 500))).ok, "moving a configured room rejects the stale global boundary")
	suite.assert_equal(actor.launch_runtime_snapshot(), accepted, "moved-room rejection preserves native state")
	room.position.x -= 1.0
	var invalid_mask := _actor(WraithScene, "ruins_wraith", Vector2(1100, 500))
	invalid_mask.collision_mask = 0
	suite.assert_true(not invalid_mask.configure_launch_room_motion(room, template).ok, "room installation requires a native collision policy covering world bodies")
	invalid_mask.queue_free()
	actor.scale = Vector2(2, 2)
	suite.assert_true(not actor.prepare_launch_frame(2, _context(2, actor.global_position, Vector2(2000, 500))).ok, "scaled actor cannot bypass its authored body-radius boundary")
	actor.scale = Vector2.ONE
	var camera_shape := room.get_node("CameraBounds/CollisionShape2D").shape as RectangleShape2D
	var camera_size := camera_shape.size
	camera_shape.size.x += 1.0
	suite.assert_true(not actor.prepare_launch_frame(2, _context(2, actor.global_position, Vector2(2000, 500))).ok, "changed physical CameraBounds reject the sealed room boundary")
	camera_shape.size = camera_size
	actor.get_node("CollisionShape2D").shape.radius = 7.0
	suite.assert_true(not actor.prepare_launch_frame(2, _context(2, actor.global_position, Vector2(2000, 500))).ok, "changed native body radius cannot bypass the sealed room boundary")
	actor.get_node("CollisionShape2D").shape.radius = 8.0
	actor.collision_mask = 0
	var mask_result: Dictionary = actor.prepare_launch_frame(2, _context(2, actor.global_position, Vector2(2000, 500)))
	suite.assert_true(not mask_result.ok, "changed collision mask cannot bypass the configured native collision policy")
	actor.collision_mask = 1
	if mask_result.ok:
		actor.rollback_launch_frame(mask_result.ticket)
	actor.collision_layer = 2
	var layer_result: Dictionary = actor.prepare_launch_frame(2, _context(2, actor.global_position, Vector2(2000, 500)))
	suite.assert_true(not layer_result.ok, "changed collision layer rejects the sealed room-motion configuration")
	actor.collision_layer = 4
	if layer_result.ok:
		actor.rollback_launch_frame(layer_result.ticket)
	suite.assert_true(not actor.configure_launch_room_motion(room, template).ok, "accepted motion cannot rebind a replacement room boundary")
	var late_checkpoint: Dictionary = actor.launch_transaction_snapshot()
	var late: Dictionary = actor.prepare_launch_frame(2, _context(2, actor.global_position, Vector2(2000, 500)))
	suite.assert_true(late.ok and actor.commit_launch_frame(late.ticket), "room-bounded native frame stages before its final publication guard")
	var health := actor.get_node("HealthComponent")
	var signal_ticket: Dictionary = health.begin_frame_signal_transaction(2)
	health.take_damage(Damage.from_plan({"run_id": "run-p15", "target_id": "hostile:test-a", "hostile_source_id": "player:1", "attack_generation": 10, "hit_index": 0, "action_token": 10, "amount": 1.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": [], "can_crit": false}))
	suite.assert_true(actor.can_publish_launch_frame(late.ticket), "legitimate same-frame Health and species facts do not invalidate the independent room boundary")
	camera_shape.size.x += 1.0
	_assert_publication_refused(actor, late.ticket, "late physical CameraBounds mutation cannot publish an accepted frame")
	camera_shape.size = camera_size
	room.position.x += 1.0
	_assert_publication_refused(actor, late.ticket, "late room transform mutation cannot retire the committed frame ticket")
	room.position.x -= 1.0
	var late_position := actor.global_position
	actor.global_position.x = 1640.0
	_assert_publication_refused(actor, late.ticket, "late out-of-bounds body displacement cannot publish the frame")
	actor.global_position = late_position
	actor.collision_mask = 0
	_assert_publication_refused(actor, late.ticket, "late collision mask mutation cannot publish the native frame")
	actor.collision_mask = 1
	suite.assert_true(actor.rollback_launch_frame(late.ticket) and health.rollback_frame_signal_transaction(signal_ticket) and actor.restore_launch_transaction_snapshot(late_checkpoint), "restoring external geometry allows rejection compensation to retire the same frame ticket and Health")
	suite.assert_equal(actor.launch_runtime_snapshot(), accepted, "late publication refusal restores the prior accepted actor state")
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4, 64)
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	wall.global_position = Vector2(1120, 500)
	var unbound := _actor(WraithScene, "ruins_wraith", Vector2(1100, 500))
	var strider := _actor(StriderScene, "stone_shell_strider", Vector2(1100, 500))
	suite.assert_true(strider.configure_launch_room_motion(room, template).ok, "ordinary species also installs the outer-room guard")
	await get_tree().physics_frame
	for frame: int in range(2, 45):
		_advance(actor, frame, Vector2(2000, 500))
	for frame: int in range(1, 45):
		_advance(unbound, frame, Vector2(2000, 500))
		_advance(strider, frame, Vector2(2000, 500))
	suite.assert_true(actor.global_position.x > 1140.0, "configured Wraith crosses a real internal wall")
	suite.assert_true(unbound.global_position.x < 1110.0, "unconfigured Wraith keeps native collision until valid room bounds exist")
	suite.assert_true(strider.global_position.x < 1110.0, "configured Strider still collides with the real internal wall")
	room.position.x += 1.0
	var rejected := _actor(WraithScene, "ruins_wraith", Vector2(1001, 500))
	suite.assert_true(not rejected.configure_launch_room_motion(room, template).ok, "room installation refuses a body crossing the inset outer margin")
	rejected.queue_free()
	room.position.x -= 1.0
	actor.queue_free()
	unbound.queue_free()
	strider.queue_free()
	wall.queue_free()
	room.queue_free()
	await get_tree().process_frame


func _test_outer_corners() -> void:
	var room := _room()
	for direction: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var corner := Vector2(1000 if direction.x < 0 else 1640, 400 if direction.y < 0 else 760)
		var actor := _actor(WraithScene, "ruins_wraith", corner - direction * 24.0)
		suite.assert_true(actor.configure_launch_room_motion(room, _template()).ok, "corner actor installs the validated room boundary")
		for frame: int in range(1, 46):
			_advance(actor, frame, corner + direction * 1000.0)
		suite.assert_equal(actor.global_position, corner - direction * 8.0, "every outer corner retains the exact authored body-radius margin")
		actor.queue_free()
	room.queue_free()
	await get_tree().process_frame
