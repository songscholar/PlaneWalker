extends "res://tests/integration/combat/native_summon_lifecycle_test.gd"


func _run() -> void:
	suite = Suite.new()
	for displacement: Vector2 in [Vector2(5, 0), Vector2(-5, 0), Vector2(0, 5), Vector2(0, -5)]:
		await _same_frame_target(displacement)
	await _wall_order(324.0, 338.0, false)
	await _wall_order(326.0, 334.0, true)
	suite.finish(get_tree())


func _same_frame_target(displacement: Vector2) -> void:
	var f := await _fixture("void_archer")
	f.player.global_position = Vector2(400, 180)
	suite.assert_true(_start(f, "void_archer.void_arrow"), "actual Archer owns the native warning")
	for _frame: int in range(25):
		suite.assert_true(_step(f), "actual warning accepts the full native clock")
	var nodes: Array[Node2D] = f.effects.native_payload_nodes()
	suite.assert_equal(nodes.size(), 1, "same-frame target owns one real projectile")
	if nodes.is_empty():
		await _dispose(f)
		return
	f.player.global_position = nodes[0].global_position + Vector2(18, 0)
	await get_tree().physics_frame
	f.player.move_and_collide(displacement)
	var server_transform: Transform2D = PhysicsServer2D.body_get_state(f.player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
	suite.assert_true(not server_transform.origin.is_equal_approx(f.player.global_position), "fixture reproduces Godot's deferred same-frame body transform")
	f.player.health.release_invulnerability_source(&"summon-matrix")
	f.player.health.defense = 0.0
	var before: Dictionary = f.effects.snapshot()
	var actor_before: Dictionary = f.actors[0].launch_runtime_snapshot()
	var health_before: Dictionary = f.player.health.transaction_snapshot()
	var hp_before: float = f.player.health.current_hp
	var should_hit := displacement.x < 5.0
	var expected_damage: float = f.effects.payload_snapshot().projectiles[0].definition.damage if should_hit else 0.0
	var ticket: Dictionary = f.bridge.begin_frame(26)
	var prepared: bool = not ticket.is_empty() and f.bridge.prepare_frame(ticket)
	suite.assert_true(prepared, "actual same-frame moved target accepts the native projectile query: " + str(f.bridge.frame_rejection_snapshot()))
	if prepared:
		server_transform = PhysicsServer2D.body_get_state(f.player.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
		suite.assert_true(not server_transform.origin.is_equal_approx(f.player.global_position), "native shape query preserves the engine's deferred kinematic state")
		suite.assert_equal(f.player.health.current_hp, hp_before - expected_damage, "same-frame physical hit or miss uses actual current target geometry")
		suite.assert_equal(f.effects.payload_snapshot().projectiles.is_empty(), should_hit, "moving-away projectile remains live while actual contact consumes it")
	if not ticket.is_empty():
		suite.assert_true(f.bridge.rollback_frame(ticket), "same-frame target rejection compensates the original frame")
		suite.assert_true(f.player.health.restore_transaction_snapshot(health_before), "same-frame rejected contact compensates actual Player Health")
		suite.assert_equal(f.effects.snapshot(), before, "same-frame rollback retains exact actual projectile state")
		suite.assert_equal(f.actors[0].launch_runtime_snapshot(), actor_before, "same-frame rollback retains exact native owner state")
	if prepared:
		suite.assert_true(_step(f), "same-frame actual target retries the original native frame")
		suite.assert_equal(f.player.health.current_hp, hp_before - expected_damage, "accepted same-frame retry publishes one real hit or no false hit")
	await _dispose(f)


func _wall_order(wall_x: float, target_x: float, should_hit: bool) -> void:
	var f := await _fixture("void_archer")
	f.player.global_position = Vector2(400, 180)
	suite.assert_true(_start(f, "void_archer.void_arrow"), "ordered contact fixture owns the native warning")
	for _frame: int in range(25):
		suite.assert_true(_step(f), "ordered contact fixture advances actual projectile warning")
	var wall := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(1, 64)
	collider.shape = shape
	wall.add_child(collider)
	add_child(wall)
	wall.global_position = Vector2(wall_x, 180)
	await get_tree().physics_frame
	f.player.global_position = Vector2(target_x, 180)
	f.player.health.release_invulnerability_source(&"summon-matrix")
	f.player.health.defense = 0.0
	var hp_before: float = f.player.health.current_hp
	var damage: float = f.effects.payload_snapshot().projectiles[0].definition.damage if should_hit else 0.0
	suite.assert_true(_step(f), "current target and wall contact ordering accepts actual native frame")
	suite.assert_equal(f.player.health.current_hp, hp_before - damage, "earliest actual shape contact respects wall and target order")
	suite.assert_true(f.effects.payload_snapshot().projectiles.is_empty(), "ordered physical contact retires the native projectile once")
	wall.queue_free()
	await _dispose(f)
