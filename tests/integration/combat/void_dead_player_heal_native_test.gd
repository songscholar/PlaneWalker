extends "res://tests/integration/combat/void_arena_native_test.gd"


func _run() -> void:
	suite = Suite.new()
	var room := Room.instantiate() as Node2D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(room)
	var actor := _boss(room)
	var player := Player.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.configure_run(&"run-void-arena")
	player.global_position = Vector2(600, 160)
	player.health.current_hp = 50.0
	var alive: Dictionary = player.health.transaction_snapshot()
	player.health.lose_health(player.health.max_hp, player)
	suite.assert_true(player.health.dead and player.health.current_hp == 0.0, "actual native Player is dead before P3heal resolves")
	var root := Node2D.new()
	add_child(root)
	var effects := Effects.new()
	effects.configure("run-void-arena", 0)
	effects.configure_native_payloads(root)
	var bridge := Bridge.new()
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], effects), "dead native Player remains a valid owned healingtarget")
	var before: Dictionary = actor.launch_runtime_snapshot()
	var ticket: Dictionary = bridge.begin_frame(1)
	actor.get_node("Hurtbox").receive_hit(_damage(player, 1, 4000.0))
	suite.assert_true(bridge.prepare_frame(ticket), "actual deadP3heal settles zeroHP once")
	suite.assert_true(player.health.dead and actor.native_void_arena_snapshot().player_heal.amount == 0.0, "P3 never revives dead actual HealthComponent")
	suite.assert_true(bridge.rollback_frame(ticket), "deadP3 consumption compensates refusedWorldframe")
	suite.assert_equal(actor.launch_runtime_snapshot(), before, "refusal restores exact unconsumedP3receipt")
	ticket = bridge.begin_frame(1)
	actor.get_node("Hurtbox").receive_hit(_damage(player, 1, 4000.0))
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "same deadP3 transition retries once")
	suite.assert_true(player.health.restore_transaction_snapshot(alive), "fixture performs external Healthrevival")
	ticket = bridge.begin_frame(2)
	suite.assert_true(bridge.prepare_frame(ticket) and _publish(bridge, ticket), "externally revived Player continues acceptednativeclock")
	suite.assert_equal(player.health.current_hp, 50.0, "external revival cannot receive delayedP3heal")
	var cold: Dictionary = actor.native_cold_snapshot(func(_source: Node): return {})
	suite.assert_true(actor.can_restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "deadP3receipt remains valid at acceptedcoldboundary")
	var world := SubViewport.new()
	world.world_2d = World2D.new()
	add_child(world)
	var fresh_room := Room.instantiate() as Node2D
	fresh_room.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(fresh_room)
	var twin := _boss(fresh_room)
	suite.assert_true(twin.restore_native_cold_snapshot(cold, func(_binding: Dictionary): return null), "fresh native Void reconstructs permanentlyconsumed zeroheal")
	suite.assert_equal(twin.native_void_arena_snapshot(), actor.native_void_arena_snapshot(), "fresh native Void preserves deadhealprovenance exactly")
	world.queue_free()
	effects.dispose_native_effects()
	actor.queue_free()
	player.queue_free()
	root.queue_free()
	room.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())
