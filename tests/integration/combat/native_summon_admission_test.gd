extends "res://tests/integration/combat/native_summon_lifecycle_test.gd"


func _run() -> void:
	suite = Suite.new()
	for id: String in ["time_sovereign", "forest_caller"]:
		for origin: Vector2 in [Vector2(26, 180), Vector2(614, 180), Vector2(320, 26), Vector2(320, 334)]:
			await _border_warning(id, origin, id == "time_sovereign")
		await _blocked_warning(id)
	suite.finish(get_tree())


func _border_warning(id: String, origin: Vector2, should_decline: bool) -> void:
	var f := await _fixture(id)
	if id == "time_sovereign":
		_unlock_boss(f)
	var actor: Node2D = f.actors[0]
	actor.global_position = origin
	if id == "time_sovereign":
		actor._refresh_native_arena()
	f.player.global_position = origin + (Vector2(40, 0) if origin.x < 100 else Vector2(-40, 0) if origin.x > 540 else Vector2(0, 40) if origin.y < 100 else Vector2(0, -40))
	var action := "traitor_timeline_split" if id == "time_sovereign" else "forest_caller.great_call"
	suite.assert_true(_start(f, action), "authored native summon fixture commits frozen slots before admission")
	var before: Dictionary = actor.launch_runtime_snapshot()
	var threats: Array = f.registry.snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(int(f.frame) + 1)
	var prepared: bool = not ticket.is_empty() and f.bridge.prepare_frame(ticket)
	suite.assert_true(prepared, "authored border summon accepts the fixed frame " + id + str(origin))
	if prepared:
		suite.assert_equal(actor.launch_runtime_snapshot().runtime.action.phase, "IDLE" if should_decline else "WARNING", "only invalid frozen summon slots decline during warning " + id + str(origin))
		suite.assert_true(f.effects.summon_snapshot().rows.is_empty(), "declined warning reserves no invalid child or pending work")
		suite.assert_true(f.bridge.rollback_frame(ticket), "late sibling refusal compensates the summon warning decline")
		suite.assert_equal(actor.launch_runtime_snapshot(), before, "warning decline rollback retains exact action and frozen original geometry")
		suite.assert_equal(f.registry.snapshot(), threats, "warning decline rollback restores original telegraph generations")
		suite.assert_true(_step(f), "same frozen border warning retries once")
		suite.assert_true(f.effects.summon_snapshot().rows.is_empty() and f.registry.snapshot().is_empty() == should_decline, "only declined warning retires frozen threat facts without relocating a landing")
	elif not ticket.is_empty():
		f.bridge.rollback_frame(ticket)
	await _dispose(f)


func _blocked_warning(id: String) -> void:
	var f := await _fixture(id)
	if id == "time_sovereign":
		_unlock_boss(f)
	f.player.global_position = Vector2(360, 180)
	var obstacle := StaticBody2D.new()
	obstacle.position = Vector2(256, 180) if id == "time_sovereign" else Vector2(320, 180)
	obstacle.collision_layer = 1
	obstacle.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	collision.shape = shape
	obstacle.add_child(collision)
	add_child(obstacle)
	await get_tree().physics_frame
	suite.assert_true(_start(f, "traitor_timeline_split" if id == "time_sovereign" else "forest_caller.great_call") and _step(f), "static blocked summon warning still accepts its owned frame " + id)
	suite.assert_true(f.actors[0].launch_runtime_snapshot().runtime.action.phase == "IDLE" and f.effects.summon_snapshot().rows.is_empty(), "a static obstruction declines frozen spawn geometry before warning work")
	obstacle.queue_free()
	await _dispose(f)
