extends "res://tests/unit/enemies/projectile_scalar_distance_test.gd"

const PayloadAuthority := preload("res://scripts/enemies/launch/launch_hostile_payload_authority.gd")
const NativePlayer := preload("res://scenes/player/player.tscn")


func _run() -> void:
	suite = Suite.new()
	await _native_diagonal_distance()
	suite.finish(get_tree())


func _native_diagonal_distance() -> void:
	var hit := _rounded_diagonal_hit()
	var domain := PayloadRuntime.new()
	domain.configure("run-p15", int(hit.runtime_frame))
	suite.assert_true(domain.reserve_projectile(hit, BOUNDS, {}).ok, "native scalar fixture reserves a legal diagonal from the authored action")
	var root := Node2D.new()
	add_child(root)
	var player := NativePlayer.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-p15")
	player.global_position = Vector2(550, 50)
	var authority := PayloadAuthority.new()
	suite.assert_true(authority.configure("run-p15", int(hit.runtime_frame)) and authority.configure_native_root(root) and authority.restore_transaction_snapshot(domain.snapshot()), "cold accepted diagonal projects into one actual native projectile")
	await get_tree().physics_frame
	var first := int(hit.runtime_frame)
	for offset: int in range(1, 121):
		var before := authority.snapshot()
		var body: Node2D = authority.native_nodes()[0]
		var before_position := body.global_position
		var context := {"run_id": "run-p15", "runtime_frame": first + offset, "threat_registry": null, "actors": {}, "targets": {"player:1": player}}
		var prepared := authority.prepare_payloads([], context)
		suite.assert_true(prepared.ok, "actual native diagonal prepares each authored flight frame")
		if not prepared.ok:
			break
		if offset == 93:
			player.global_position += Vector2(1, 0)
			suite.assert_true(not authority.can_commit(prepared.ticket), "late target movement still invalidates the exact sealed geometry")
			player.global_position -= Vector2(1, 0)
		var accepted := authority.can_commit(prepared.ticket) and authority.commit(prepared.ticket)
		suite.assert_true(accepted, "rounded diagonal stays admissible in the actual native projection at offset %d" % offset)
		if not accepted:
			authority.rollback(prepared.ticket)
			break
		if offset == 93:
			var candidate := authority.snapshot()
			var candidate_position := body.global_position
			suite.assert_true(authority.rollback(prepared.ticket), "late refusal compensates the diagonal native transaction")
			suite.assert_equal(authority.snapshot(), before, "rollback restores every diagonal domain field")
			suite.assert_equal(body.global_position, before_position, "rollback restores the exact actual projectile position")
			prepared = authority.prepare_payloads([], context)
			suite.assert_true(prepared.ok and authority.can_commit(prepared.ticket) and authority.commit(prepared.ticket), "same diagonal frame retries once with the original sealed geometry")
			suite.assert_equal(authority.snapshot(), candidate, "retry restores the exact candidate state and claims")
			suite.assert_equal(body.global_position, candidate_position, "retry reproduces the exact actual projectile position")
		suite.assert_true(authority.can_publish(prepared.ticket) and authority.publish(prepared.ticket), "actual native diagonal publishes every complete transaction")
	suite.assert_true(authority.snapshot().projectiles.is_empty() and authority.native_nodes().is_empty(), "actual native flight retires at the authored finite lifetime")
	player.queue_free()
	root.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
