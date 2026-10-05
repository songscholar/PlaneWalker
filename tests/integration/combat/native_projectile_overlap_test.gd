extends "res://tests/integration/combat/native_summon_lifecycle_test.gd"


func _run() -> void:
	suite = Suite.new()
	for offset: Vector2 in [Vector2(0, 10), Vector2(0, -10), Vector2(-10, 0), Vector2(10, 0)]:
		await _moving_target_overlap(offset)
	suite.finish(get_tree())


func _moving_target_overlap(offset: Vector2) -> void:
	var f := await _fixture("rift_weaver")
	f.player.global_position = Vector2(400, 180)
	suite.assert_true(_start(f, "rift_weaver.distortion_bolt"), "actual Rift Weaver commits the authored projectile warning")
	for _frame: int in range(25):
		suite.assert_true(_step(f), "authored projectile warning accepts each native frame")
	var nodes: Array[Node2D] = f.effects.native_payload_nodes()
	suite.assert_equal(nodes.size(), 1, "actual first active frame creates one native projectile")
	if nodes.is_empty():
		await _dispose(f)
		return
	f.player.global_position = nodes[0].global_position + offset
	f.player.health.release_invulnerability_source(&"summon-matrix")
	f.player.health.defense = 0.0
	await get_tree().physics_frame
	var before: Dictionary = f.effects.snapshot()
	var actor_before: Dictionary = f.actors[0].launch_runtime_snapshot()
	var hp_before: float = f.player.health.current_hp
	var health_before: Dictionary = f.player.health.transaction_snapshot()
	var ticket: Dictionary = f.bridge.begin_frame(26)
	var prepared: bool = not ticket.is_empty() and f.bridge.prepare_frame(ticket)
	suite.assert_true(prepared, "Player moving into a live projectile accepts physical overlap contact " + str(offset))
	if prepared:
		suite.assert_equal(f.player.health.current_hp, hp_before - 15.0, "authored elite overlap contact settles actual Player Health")
		suite.assert_true(f.effects.payload_snapshot().projectiles.is_empty(), "physical overlap consumes the bounded projectile exactly once")
		suite.assert_true(f.bridge.rollback_frame(ticket), "late overlap refusal compensates native contact")
		suite.assert_true(f.player.health.restore_transaction_snapshot(health_before), "outer Player transaction compensates rejected overlap Health")
		suite.assert_equal(f.effects.snapshot(), before, "rejected overlap restores the exact live flight and claims")
		suite.assert_equal(f.actors[0].launch_runtime_snapshot(), actor_before, "rejected overlap restores the exact owner clock")
		suite.assert_true(_step(f), "same physical overlap retries once without freezing the room")
		suite.assert_equal(f.player.health.current_hp, hp_before - 15.0, "accepted overlap retry settles one actual authored elite hit")
		suite.assert_true(_step(f) and f.player.health.current_hp == hp_before - 15.0, "consumed overlap projectile cannot hit again on the following frame")
	else:
		if not ticket.is_empty():
			f.bridge.rollback_frame(ticket)
		f.player.health.restore_transaction_snapshot(health_before)
	await _dispose(f)
