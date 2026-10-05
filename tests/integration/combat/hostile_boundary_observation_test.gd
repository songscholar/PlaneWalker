extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const BridgeFixture := preload("res://tests/integration/combat/hostile_frame_bridge_test.gd")
const EnemyFixture := preload("res://tests/unit/enemies/launch_enemy_runtime_test.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const EnemyScene := preload("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn")


class CountingBoss extends "res://scripts/enemies/launch/launch_boss_runtime.gd":
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return super.snapshot()


class CountingEnemy extends "res://scripts/enemies/launch/launch_enemy_runtime.gd":
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return super.snapshot()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var probe := CountingBoss.new()
	var scene := load("res://data/content_packs/base/assets/bosses/launch/boss_ruin_king.tscn") as PackedScene
	var actor_probe := scene.instantiate()
	var available: bool = probe.has_method("native_run_id") and actor_probe.has_method("native_frame_boundary")
	actor_probe.free()
	suite.assert_true(available, "native actor boundary observation preserves live authority without a complete frame snapshot")
	if not available:
		suite.finish(get_tree())
		return
	for row: Dictionary in Content.read_catalog("bosses.json"):
		await _check_boss(suite, row)
	await _check_cold_fallback(suite)
	suite.finish(get_tree())


func _player() -> Node2D:
	var player := PlayerScene.instantiate() as Node2D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	player.configure_run(&"run-p15")
	return player


func _check_boss(suite: RefCounted, row: Dictionary) -> void:
	var parser := Definition.new()
	suite.assert_true(parser.configure(row).ok, "boundary observation uses authored Boss " + row.id)
	var definition := parser.runtime_projection()
	var identity := Actions.identity()
	identity.seed = 42
	var player := _player()
	var scene := load("res://data/content_packs/base/assets/bosses/launch/boss_%s.tscn" % row.id) as PackedScene
	var actor := scene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "actual Boss configures boundary authority")
	var initial: Dictionary = actor.launch_runtime_snapshot().runtime
	var runtime := CountingBoss.new()
	var origin: Vector2 = actor.call("_native_arena_origin")
	suite.assert_true(runtime.configure_arena_origin({"x": origin.x, "y": origin.y}, {"x": actor.global_position.x, "y": actor.global_position.y}), "counted Boss retains actual arena configuration")
	suite.assert_true(runtime.configure(definition, identity).ok and runtime.restore_snapshot(initial), "counted authority restores exact native Boss state")
	actor.set("_launch_runtime", runtime)
	_check_boundary(suite, actor, runtime, "configured " + row.id)
	var bridge := Bridge.new()
	runtime.full_snapshot_calls = 0
	suite.assert_true(bridge.configure(player, Registry.new(), [actor], BridgeFixture.EffectDouble.new()), "Bridge binds actual counted Boss")
	suite.assert_equal(runtime.full_snapshot_calls, 0, "configuration and readiness observe only native boundary fields")
	suite.assert_true(bridge.is_ready_for_frame(1), "current actual native clock is ready")
	suite.assert_equal(runtime.full_snapshot_calls, 0, "repeated readiness never captures the complete Boss")
	var before: Dictionary = actor.launch_runtime_snapshot()
	runtime.full_snapshot_calls = 0
	var ticket: Dictionary = bridge.begin_frame(1)
	suite.assert_true(not ticket.is_empty(), "actual frame begins with authoritative compensation")
	suite.assert_equal(runtime.full_snapshot_calls, 1, "frame start keeps exactly one complete transaction checkpoint")
	suite.assert_true(bridge.rollback_frame(ticket), "ordinary frame-start rollback still validates and restores")
	suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), var_to_bytes(before), "rollback retains every complete typed Actor field")
	suite.assert_true(runtime.advance_frame(1, Actions.context(1), false).ok, "owned Boss clock really advances independently")
	_check_boundary(suite, actor, runtime, "advanced " + row.id)
	runtime.full_snapshot_calls = 0
	suite.assert_true(not bridge.is_ready_for_frame(1), "a changed live clock cannot reuse prior readiness")
	suite.assert_equal(runtime.full_snapshot_calls, 0, "stale clock refusal still needs no complete observation")
	suite.assert_true(runtime.restore_snapshot(initial), "original full boundary rolls back after clock mutation")
	suite.assert_true(bridge.is_ready_for_frame(1), "restored actual clock becomes ready")
	suite.assert_true(runtime.cancel(&"boundary_test").ok, "owned Boss really reaches terminal state")
	_check_boundary(suite, actor, runtime, "terminal " + row.id)
	runtime.full_snapshot_calls = 0
	suite.assert_true(bridge.is_ready_for_frame(1) and bridge.retire_actor(str(actor.hostile_source_id)), "current terminal observation preserves retirement behavior")
	suite.assert_equal(runtime.full_snapshot_calls, 0, "terminal readiness and retirement use narrow current authority")
	suite.assert_true(runtime.restore_snapshot(initial), "terminal mutation remains historically restorable")
	suite.assert_true(bridge.register_actor(actor), "restored authentic actor registers again")
	var foreign := identity.duplicate(true)
	foreign.run_id = "run-foreign"
	suite.assert_true(runtime.configure(definition, foreign).ok, "actual domain authority changes its run identity")
	_check_boundary(suite, actor, runtime, "reconfigured " + row.id)
	runtime.full_snapshot_calls = 0
	suite.assert_true(not bridge.is_ready_for_frame(1), "foreign live run identity cannot reuse cached Actor configuration")
	suite.assert_equal(runtime.full_snapshot_calls, 0, "foreign run refusal uses actual narrow domain identity")
	suite.assert_true(runtime.configure(definition, identity).ok and runtime.restore_snapshot(initial), "authentic configuration and complete state safely restore")
	suite.assert_true(bridge.is_ready_for_frame(1), "original authentic runtime safely retries")
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame


func _check_boundary(suite: RefCounted, actor: Node2D, runtime: RefCounted, label: String) -> void:
	var complete: Dictionary = runtime.snapshot()
	var before := var_to_bytes(complete)
	var expected := {"run_id": str(complete.identity.run_id), "runtime_frame": int(complete.runtime_frame), "terminal": bool(complete.terminal)}
	var boundary: Dictionary = actor.call("native_frame_boundary")
	suite.assert_equal(var_to_bytes(boundary), var_to_bytes(expected), "narrow boundary retains exact observed types: " + label)
	boundary.run_id = "caller-mutation"
	boundary.runtime_frame = 999
	boundary.terminal = not boundary.terminal
	suite.assert_equal(var_to_bytes(runtime.snapshot()), before, "mutable boundary output cannot change live authority: " + label)


func _check_cold_fallback(suite: RefCounted) -> void:
	var actor := EnemyScene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var identity := Actions.identity()
	identity.seed = 42
	var definition: Dictionary = EnemyFixture.definition()
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "ordinary enemy configures unchanged cold boundary")
	var initial: Dictionary = actor.launch_runtime_snapshot().runtime
	var runtime := CountingEnemy.new()
	suite.assert_true(runtime.configure(definition, identity).ok and runtime.restore_snapshot(initial), "foreign-query runtime retains full cold configuration")
	actor.set("_launch_runtime", runtime)
	var complete: Dictionary = runtime.snapshot()
	var expected := {"run_id": str(complete.identity.run_id), "runtime_frame": int(complete.runtime_frame), "terminal": bool(complete.terminal)}
	runtime.full_snapshot_calls = 0
	suite.assert_equal(var_to_bytes(actor.call("native_frame_boundary")), var_to_bytes(expected), "missing native runtime queries preserve full-snapshot fallback")
	suite.assert_equal(runtime.full_snapshot_calls, 1, "cold fallback takes one original complete domain snapshot")
	actor.queue_free()
	await get_tree().process_frame
