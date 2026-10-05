extends "res://tests/integration/combat/void_arena_native_test.gd"

const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")


func _run() -> void:
	suite = Suite.new()
	await _step(false)
	await _step(true)
	suite.finish(get_tree())


func _step(blocked: bool) -> void:
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := _boss(room)
	actor.global_position = Vector2(320, 180)
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-void-arena")
	player.global_position = Vector2(380, 180)
	player.health.acquire_invulnerability_source(&"step-fixture")
	var obstacle := StaticBody2D.new()
	if blocked:
		obstacle.position = Vector2(340, 180)
		obstacle.collision_layer = 1
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(8, 8)
		shape.shape = box
		obstacle.add_child(shape)
		add_child(obstacle)
	else:
		obstacle.free()
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-void-arena", 0)
	effects.configure_native_payloads(root)
	var bridge := Bridge.new()
	var registry := Registry.new()
	suite.assert_true(bridge.configure(player, registry, [actor], effects), "actual Step uses native frame effects and roomcollisions")
	var context := {"runtime_frame": 0, "source_position": {"x": 320.0, "y": 180.0}, "target_position": {"x": 380.0, "y": 180.0}, "facing_direction": {"x": 1.0, "y": 0.0}, "target_id": bridge._player_target_id()}
	var requested: Dictionary = actor._launch_runtime.request_action("voidking_void_step", context)
	suite.assert_true(requested.ok, "actual Step seals the oldtarget landing")
	for fact: Dictionary in requested.threat_facts:
		suite.assert_true(registry.register_fact(Actions.native_threat_fact(fact)), "fixture publishes the same real Step warning as normal Boss selection")
	await get_tree().physics_frame
	await get_tree().physics_frame
	for frame: int in range(1, 30):
		var ticket: Dictionary = bridge.begin_frame(frame)
		suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual Step warning frame%daccepts" % frame)
		suite.assert_equal(actor.global_position, Vector2(320, 180), "actual Step remains still during30frame warning")
	var before: Dictionary = actor.launch_runtime_snapshot()
	var ticket: Dictionary = bridge.begin_frame(30)
	suite.assert_true(bridge.prepare_frame(ticket), "actual Step landing or collisionrefusal prepares")
	suite.assert_equal(actor.global_position, Vector2(320, 180) if blocked else Vector2(340, 180), "actual Step respects real destination collisionclearance")
	suite.assert_true(bridge.rollback_frame(ticket), "late World refusal compensates actual Step relocation")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "Step refusal restores exact position and unclaimed followup")
	ticket = bridge.begin_frame(30)
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "actual Step retries the identical acceptedframe")
	var auxiliary: Dictionary = actor._launch_runtime.void_auxiliary_snapshot()
	suite.assert_true(auxiliary.landings.size() == 1 and auxiliary.landings[0].landed == not blocked, "native Step retains actual landing receipt")
	if not blocked:
		suite.assert_true(actor.launch_runtime_snapshot().runtime.action.action_id == "voidking_scepter_strike" and actor.launch_runtime_snapshot().runtime.action.phase == "WARNING", "native Step starts independentlywarned real scepter action")
		for frame: int in range(31, 58):
			ticket = bridge.begin_frame(frame)
			suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "native Step followup warning acceptsframe%d" % frame)
			suite.assert_equal(player.health.current_hp, player.health.max_hp, "native Step grants no hidden damage before full28warning")
	else:
		suite.assert_equal(auxiliary.landings[0].followup_generation, 0, "blocked Step cannot issue its followup")
	var cold: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	suite.assert_true(actor.can_restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "actual Step is retained in strict native coldaggregate")
	var world := SubViewport.new()
	world.world_2d = World2D.new()
	add_child(world)
	var fresh_room := Room.instantiate() as Node2D
	fresh_room.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(fresh_room)
	var twin := _boss(fresh_room)
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "fresh native Boss reconstructs actual Step receipt")
	suite.assert_equal(twin._launch_runtime.void_auxiliary_snapshot(), actor._launch_runtime.void_auxiliary_snapshot(), "fresh native Step retains followup claims exactly")
	world.queue_free()
	effects.dispose_native_effects()
	if blocked:
		obstacle.queue_free()
	actor.queue_free()
	player.queue_free()
	root.queue_free()
	room.queue_free()
	await get_tree().process_frame
