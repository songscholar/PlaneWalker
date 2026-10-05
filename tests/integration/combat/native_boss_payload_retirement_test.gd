extends "res://tests/integration/combat/forge_arena_native_test.gd"


func _run() -> void:
	suite = Suite.new()
	var f := await _fixture()
	f.player.global_position = f.actor.global_position + Vector2(160, 0)
	_start(f, "forge_lava_toss")
	for frame: int in range(1, 48):
		suite.assert_true(_step(f, frame), "production Forge retains its authored warning before projectile launch")
	suite.assert_equal(f.effects.payload_snapshot().projectiles.size(), 1, "terminal regression owns one actual launched Forge projectile")
	var deaths: Array[String] = []
	f.actor.hostile_final_death.connect(func(_source: StringName, receipt: String): deaths.append(receipt))
	var terminal_hit := Damage.from_plan({"run_id": "run-forge-arena", "target_id": str(f.actor.hostile_source_id), "hostile_source_id": "player:sword", "attack_generation": 801, "action_token": 801, "amount": 100000.0, "damage_type": Damage.DamageType.PHYSICAL, "tags": ["weapon:sword"], "can_crit": false, "source": f.player, "attacker": f.player})
	suite.assert_true(f.actor.health.take_damage(terminal_hit) > 0.0 and f.actor.health.dead, "authenticated explicit terminal-hit fixture finalizes actual Forge principal")
	suite.assert_equal(deaths.size(), 1, "principal publishes exactly one canonical death before cleanup")
	var terminal_state: Dictionary = f.actor._actor_state()
	suite.assert_true(f.actor._can_restore_actor_state(terminal_state), "canonical terminal body remains valid for compensated effect cleanup")
	f.actor.collision_layer = 4
	suite.assert_true(not f.actor._can_restore_actor_state(terminal_state), "terminal body cannot regain its live collision layer")
	f.actor.collision_layer = 0
	f.actor.collision_mask = 1
	suite.assert_true(not f.actor._can_restore_actor_state(terminal_state), "terminal body cannot regain its live collision mask")
	f.actor.collision_mask = 0
	var before: Dictionary = f.effects.launch_transaction_snapshot()
	var threats_before: Array = f.registry.snapshot()
	var refused: Dictionary = f.bridge.begin_frame(48)
	suite.assert_true(not refused.is_empty() and f.bridge.prepare_frame(refused), "terminal owner cleanup prepares in shared accepted-frame protocol")
	suite.assert_true(f.effects.payload_snapshot().projectiles.is_empty() and f.effects.native_payload_nodes().is_empty(), "candidate terminal frame removes actual owner projectile and physical collider")
	suite.assert_true(f.registry.snapshot().is_empty(), "candidate terminal cleanup removes owned projectile threat")
	suite.assert_true(f.bridge.rollback_frame(refused), "refused terminal payload cleanup compensates")
	suite.assert_equal(f.effects.launch_transaction_snapshot(), before, "refused cleanup restores exact payload clock, geometry and claims")
	suite.assert_equal(f.registry.snapshot(), threats_before, "refused cleanup restores exact original owned threats")
	suite.assert_equal(f.effects.native_payload_nodes().size(), 1, "refused cleanup reconstructs original physical projectile")
	suite.assert_true(_step(f, 48), "same terminal cleanup frame retries exactly once")
	suite.assert_true(f.effects.work_snapshot().records.is_empty() and f.effects.native_payload_nodes().is_empty() and f.registry.snapshot().is_empty(), "accepted terminal owner has no work, projectile collider or threat")
	suite.assert_equal(deaths.size(), 1, "payload cleanup cannot publish another principal kill")
	await _dispose(f)
	suite.finish(get_tree())
