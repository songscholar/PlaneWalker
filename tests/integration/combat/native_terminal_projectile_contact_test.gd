extends "res://tests/integration/combat/native_summon_lifecycle_test.gd"


func _run() -> void:
	suite = Suite.new()
	for offset: Vector2 in [Vector2(0, 10), Vector2(0, -10), Vector2(-10, 0), Vector2(10, 0)]:
		await _terminal_contact(offset)
	suite.finish(get_tree())


func _terminal_contact(offset: Vector2) -> void:
	var f := await _fixture("void_archer")
	f.player.global_position = Vector2(400, 180)
	suite.assert_true(_start(f, "void_archer.void_arrow"), "actual Archer commits its authored warning")
	for _frame: int in range(25):
		suite.assert_true(_step(f), "terminal contact fixture advances the entire actual projectile warning")
	var nodes: Array[Node2D] = f.effects.native_payload_nodes()
	suite.assert_equal(nodes.size(), 1, "terminal contact fixture owns one real projectile")
	if nodes.is_empty():
		await _dispose(f)
		return
	f.player.global_position = nodes[0].global_position + offset
	f.player.health.release_invulnerability_source(&"summon-matrix")
	await get_tree().physics_frame
	var actor: Node2D = f.actors[0]
	var effects_before: Dictionary = f.effects.snapshot()
	var player_hp: float = f.player.health.current_hp
	var deaths: Array = []
	actor.hostile_final_death.connect(func(source: StringName, receipt: String): deaths.append({"source": str(source), "receipt": receipt}))
	suite.assert_true(_hit(actor, f.player, 100000.0, 801) > 0.0 and actor.health.dead and actor.launch_runtime_snapshot().runtime.terminal, "explicit authenticated lethal fixture finalizes the actual projectile owner")
	var actor_before: Dictionary = actor.launch_runtime_snapshot()
	var threats_before: Array = f.registry.snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(26)
	suite.assert_true(not ticket.is_empty(), "accepted terminal owner enters the shared contact cleanup frame")
	var prepared: bool = f.bridge.prepare_frame(ticket)
	suite.assert_true(prepared, "terminal owner retires a physically overlapping projectile without stale contact: " + str(f.bridge.frame_rejection_snapshot()))
	if prepared:
		suite.assert_true(f.effects.payload_snapshot().projectiles.is_empty() and f.effects.native_payload_nodes().is_empty(), "candidate terminal cleanup removes actual projectile and collider")
		suite.assert_equal(f.player.health.current_hp, player_hp, "retired contact cannot damage the actual Player")
		suite.assert_equal(deaths.size(), 1, "terminal cleanup cannot republish the prior authentic final death")
	suite.assert_true(f.bridge.rollback_frame(ticket), "terminal contact cleanup compensates the rejected whole frame")
	suite.assert_equal(actor.launch_runtime_snapshot(), actor_before, "terminal rollback preserves the authenticated owner terminal state")
	suite.assert_equal(f.effects.snapshot(), effects_before, "terminal rollback restores exact projectile state and claims")
	suite.assert_equal(f.registry.snapshot(), threats_before, "terminal rollback restores the exact published warning ledger")
	suite.assert_equal(f.effects.native_payload_nodes().size(), 1, "terminal rollback restores the original physical projectile")
	if prepared:
		suite.assert_true(_step(f), "the same terminal contact cleanup frame retries exactly once")
		suite.assert_equal(deaths.size(), 1, "accepted terminal contact publishes one authenticated final death")
		suite.assert_true(f.effects.work_snapshot().records.is_empty() and f.registry.snapshot().is_empty() and _step(f), "accepted cleanup leaves no owned contact work or threat and accepts the next frame")
		suite.assert_equal(f.player.health.current_hp, player_hp, "retired contact cannot damage again after accepted cleanup")
	await _dispose(f)
