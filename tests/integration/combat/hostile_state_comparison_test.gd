extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const EnemyFixture := preload("res://tests/unit/enemies/launch_enemy_runtime_test.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")
const BridgeFixture := preload("res://tests/integration/combat/hostile_frame_bridge_test.gd")
var suite: RefCounted


class CountingBoss extends "res://scripts/enemies/launch/launch_boss_runtime.gd":
	var comparison_calls := 0
	var snapshot_calls := 0

	func snapshot() -> Dictionary:
		snapshot_calls += 1
		return super.snapshot()

	func matches_snapshot(value: Dictionary) -> bool:
		comparison_calls += 1
		return super.matches_snapshot(value)


class CountingEnemy extends "res://scripts/enemies/launch/launch_enemy_runtime.gd":
	var snapshot_calls := 0

	func snapshot() -> Dictionary:
		snapshot_calls += 1
		return super.snapshot()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	for row: Dictionary in Content.read_catalog("bosses.json"):
		await _check_boss(row)
	await _check_fallback()
	suite.finish(get_tree())


func _check_boss(row: Dictionary) -> void:
	var parser := Definition.new()
	suite.assert_true(parser.configure(row).ok, "comparison uses authored Boss " + row.id)
	var definition := parser.runtime_projection()
	var identity := Actions.identity()
	identity.seed = 42
	var scene := load("res://data/content_packs/base/assets/bosses/launch/boss_%s.tscn" % row.id) as PackedScene
	var actor := scene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "real Boss configures Actor comparison")
	var initial: Dictionary = actor.launch_runtime_snapshot().runtime
	var runtime := CountingBoss.new()
	var origin: Vector2 = actor.call("_native_arena_origin")
	suite.assert_true(runtime.configure_arena_origin({"x": origin.x, "y": origin.y}, {"x": actor.global_position.x, "y": actor.global_position.y}) and runtime.configure(definition, identity).ok and runtime.restore_snapshot(initial), "counted real Boss retains complete authority")
	actor.set("_launch_runtime", runtime)
	actor.set_meta("planewalker_replay_external_fact_claims", {"retained": true})
	var before: Dictionary = actor._actor_state()
	if actor.has_method("_actor_state_matches"):
		_check_parity(actor, before, "configured " + row.id)
		for field: String in before:
			var missing := before.duplicate(true)
			missing.erase(field)
			_check_parity(actor, missing, "missing " + field)
		var extra := before.duplicate(true)
		extra["unknown"] = true
		_check_parity(actor, extra, "unknown Actor field")
		var stale := before.duplicate(true)
		stale.runtime.mechanism_state.phase_index = 99
		_check_parity(actor, stale, "stale nested Boss mechanism")
		stale = before.duplicate(true)
		stale.weapon_metadata.planewalker_replay_external_fact_claims.retained = false
		_check_parity(actor, stale, "mutated nested native metadata")
		stale = before.duplicate(true)
		stale.action_credit = 0
		_check_parity(actor, stale, "original equivalent integer and float equality")
		stale = before.duplicate(true)
		stale.position.x += 1.0
		_check_parity(actor, stale, "stale native position")
	var context := Actions.context(1)
	context.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
	context.target_position = {"x": actor.global_position.x + 100.0, "y": actor.global_position.y}
	var prepared: Dictionary = actor.prepare_launch_frame(1, context)
	suite.assert_true(prepared.ok, "real Boss prepares authoritative candidate " + row.id)
	if prepared.ok:
		runtime.comparison_calls = 0
		suite.assert_true(actor.can_commit_launch_frame(prepared.ticket) and actor.can_commit_launch_frame(prepared.ticket), "repeated complete candidate admission preserves original acceptance")
		suite.assert_equal(runtime.comparison_calls, 2, "two commit guards compare owned current Boss state without full observation copies")
		var original: Dictionary = runtime.snapshot()
		suite.assert_true(runtime.add_control_source("comparison-live-change", "stop", 2, 1.0), "real authority changes between candidate preparation and commit")
		suite.assert_true(not actor.can_commit_launch_frame(prepared.ticket), "changed live controls refuse an otherwise authentic ticket")
		suite.assert_true(runtime.restore_snapshot(original), "full restore retains historical compensation")
		actor.global_position.x += 1.0
		suite.assert_true(not actor.can_commit_launch_frame(prepared.ticket), "changed physical body refuses authentic candidate")
		actor.global_position.x -= 1.0
		suite.assert_true(actor.commit_launch_frame(prepared.ticket), "restored authentic candidate commits")
		suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "committed candidate rolls back through original full validation")
		suite.assert_equal(var_to_bytes(actor._actor_state()), var_to_bytes(before), "all Actor fields and typed history restore exactly")
		var player := PlayerScene.instantiate() as Node2D
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
		add_child(player)
		player.configure_run(&"run-p15")
		var bridge := Bridge.new()
		suite.assert_true(bridge.configure(player, Registry.new(), [actor], BridgeFixture.EffectDouble.new()), "real Bridge binds comparison authority")
		var frame_ticket := bridge.begin_frame(1)
		suite.assert_true(not frame_ticket.is_empty() and bridge.prepare_frame(frame_ticket), "complete native frame prepares through the real Bridge")
		var publication := bridge.prepare_frame_publication(frame_ticket)
		suite.assert_true(not publication.is_empty() and bridge.finalize_frame_publication(publication), "complete native frame detaches real publication")
		runtime.snapshot_calls = 0
		suite.assert_true(bridge.seal_frame_publication(publication), "real frame seals with original full compensation checks")
		suite.assert_equal(runtime.snapshot_calls, 0, "sealing reads live terminal state without a complete Boss observation")
		bridge.publish_prepared_frame()
		suite.assert_true(bridge.is_ready_for_frame(2), "ordinary native continuation follows the sealed boundary")
		player.queue_free()
	actor.queue_free()
	await get_tree().process_frame


func _check_parity(actor: Node2D, value: Dictionary, label: String) -> void:
	var before := var_to_bytes(actor._actor_state())
	var expected: bool = actor._actor_state() == value
	var runtime: RefCounted = actor.get("_launch_runtime")
	runtime.snapshot_calls = 0
	suite.assert_equal(actor.call("_actor_state_matches", value), expected, "current-state comparison preserves old complete equality: " + label)
	suite.assert_equal(runtime.snapshot_calls, 0, "complete Actor comparison takes no full Boss observations: " + label)
	suite.assert_equal(var_to_bytes(actor._actor_state()), before, "comparison cannot change native state: " + label)


func _check_fallback() -> void:
	var scene := load("res://data/content_packs/base/assets/enemies/launch/enemy_shattered_sentinel.tscn") as PackedScene
	var actor := scene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var identity := Actions.identity()
	identity.seed = 42
	var definition: Dictionary = EnemyFixture.definition()
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "ordinary enemy retains original configuration")
	var initial: Dictionary = actor.launch_runtime_snapshot().runtime
	var runtime := CountingEnemy.new()
	suite.assert_true(runtime.configure(definition, identity).ok and runtime.restore_snapshot(initial), "query-less counted enemy retains exact native state")
	actor.set("_launch_runtime", runtime)
	var before: Dictionary = actor._actor_state()
	if actor.has_method("_actor_state_matches"):
		runtime.snapshot_calls = 0
		suite.assert_true(actor.call("_actor_state_matches", before), "query-less runtime retains old complete equality fallback")
		suite.assert_equal(runtime.snapshot_calls, 1, "fallback captures the original complete enemy once")
		var stale := before.duplicate(true)
		stale.position.x += 1.0
		suite.assert_true(not actor.call("_actor_state_matches", stale), "fallback still refuses stale physical state")
	actor.queue_free()
	await get_tree().process_frame
