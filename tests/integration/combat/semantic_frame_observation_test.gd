extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Actions := preload("res://tests/support/p15_action_fixtures.gd")
const BossDefinition := preload("res://scripts/enemies/launch/boss_definition.gd")
const EnemyDefinition := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Semantics := preload("res://scripts/enemies/launch/launch_semantic_effect_authority.gd")
const Registry := preload("res://scripts/combat/hostile_threat_registry.gd")


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


class HistoricalActor extends Node2D:
	var full_snapshot_calls := 0

	func launch_runtime_snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return {"runtime": {"runtime_frame": 17}}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	for row: Dictionary in Content.read_catalog("bosses.json"):
		await _check_actor(suite, row, true)
	for id: String in ["shattered_sentinel", "rift_watcher"]:
		await _check_actor(suite, Content.enemy(id), false)
	var historical := HistoricalActor.new()
	suite.assert_equal(Semantics._native_observation_frame(historical), 17, "historical Actor without boundary retains original full observation")
	suite.assert_equal(historical.full_snapshot_calls, 1, "historical method fallback takes one complete Actor snapshot")
	historical.free()
	suite.finish(get_tree())


func _check_actor(suite: RefCounted, row: Dictionary, boss: bool) -> void:
	var parser: RefCounted = BossDefinition.new() if boss else EnemyDefinition.new()
	suite.assert_true(parser.configure(row).ok, "semantic frame fixture parses actual content " + row.id)
	var definition: Dictionary = parser.runtime_projection()
	var identity := Actions.identity()
	identity.seed = 42
	var path := "res://data/content_packs/base/assets/bosses/launch/boss_%s.tscn" if boss else "res://data/content_packs/base/assets/enemies/launch/enemy_%s.tscn"
	var scene := load(path % row.id) as PackedScene
	var actor := scene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "semantic frame uses actual configured actor " + row.id)
	var initial: Dictionary = actor.launch_runtime_snapshot().runtime
	var runtime: RefCounted = CountingBoss.new() if boss else CountingEnemy.new()
	if boss:
		var origin: Vector2 = actor.call("_native_arena_origin")
		suite.assert_true(runtime.configure_arena_origin({"x": origin.x, "y": origin.y}, {"x": actor.global_position.x, "y": actor.global_position.y}), "counted Boss keeps physical arena origin " + row.id)
	suite.assert_true(runtime.configure(definition, identity).ok and runtime.restore_snapshot(initial), "counted runtime restores complete content state " + row.id)
	actor.set("_launch_runtime", runtime)
	var authority := Semantics.new()
	suite.assert_true(authority.configure("run-p15"), "semantic authority uses actual run identity " + row.id)
	var root := Node2D.new()
	add_child(root)
	suite.assert_true(authority.configure_native_root(root), "semantic authority binds native projection root " + row.id)
	var actor_before := var_to_bytes(actor.launch_runtime_snapshot())
	var semantic_before := var_to_bytes(authority.snapshot())
	var observation := Actions.context(1)
	observation.source_position = {"x": actor.global_position.x, "y": actor.global_position.y}
	observation.target_position = {"x": actor.global_position.x + 180.0, "y": actor.global_position.y}
	var prepared: Dictionary = actor.prepare_launch_frame(1, observation)
	suite.assert_true(prepared.ok, "real actor prepares semantic frame " + row.id)
	if not prepared.ok:
		actor.queue_free()
		root.queue_free()
		await get_tree().process_frame
		return
	var source := str(actor.hostile_source_id)
	var context := {"run_id": "run-p15", "runtime_frame": 1, "threat_registry": Registry.new(), "actors": {source: actor}, "targets": {}}
	var semantic: Dictionary = authority.prepare_effects([{ "hostile_source_id": source, "batch": prepared.batch }], context)
	suite.assert_true(semantic.ok, "authentic sealed batch prepares semantic ticket " + row.id)
	if not semantic.ok:
		actor.rollback_launch_frame(prepared.ticket)
		actor.queue_free()
		root.queue_free()
		await get_tree().process_frame
		return
	var ticket: Dictionary = semantic.ticket
	if row.id == "shattered_sentinel":
		suite.assert_true(ticket.observations[source].position != ticket.observations[source].prepared_position, "actual moving sentinel distinguishes original and prepared positions")
	_check_observation(suite, authority, actor, runtime, ticket.observations, 1, not boss, true, "before commit " + row.id)
	suite.assert_equal(var_to_bytes(authority.snapshot()), semantic_before, "semantic preparation keeps full before bytes " + row.id)
	suite.assert_true(actor.commit_launch_frame(prepared.ticket), "real actor commits its observed frame " + row.id)
	_check_observation(suite, authority, actor, runtime, ticket.observations, 1, not boss, true, "after actor commit " + row.id)
	var shifted: Dictionary = ticket.observations.duplicate(true)
	shifted[source].prepared_position += Vector2(0.25, 0.0)
	_check_observation(suite, authority, actor, runtime, shifted, 1, not boss, false, "prepared position mismatch " + row.id)
	shifted = ticket.observations.duplicate(true)
	shifted[source].position = actor.global_position
	shifted[source].prepared_position = actor.global_position + Vector2(0.25, 0.0)
	_check_observation(suite, authority, actor, runtime, shifted, 2, not boss, true, "different frame uses original position " + row.id)
	var actor_committed := var_to_bytes(actor.launch_runtime_snapshot())
	var position := actor.global_position
	actor.global_position += Vector2(0.125, 0.0)
	suite.assert_true(not authority.can_commit(ticket), "body position drift refuses semantic commit " + row.id)
	actor.global_position = position
	var health: Node = actor.get_node("HealthComponent")
	var hp: float = health.current_hp
	health.current_hp = hp - 1.0
	suite.assert_true(not authority.can_commit(ticket), "Health drift refuses semantic commit " + row.id)
	health.current_hp = hp
	var forged: Dictionary = ticket.duplicate(true)
	forged.after.runtime_frame = 2
	suite.assert_true(not authority.can_commit(forged) and not authority.commit(forged), "ticket drift refuses semantic commit " + row.id)
	suite.assert_equal(authority.get("_pending"), ticket, "drift refusal preserves exact ticket identity " + row.id)
	suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), actor_committed, "restored drift leaves all Actor bytes unchanged " + row.id)
	suite.assert_true(authority.can_commit(ticket), "restored live observations safely retry " + row.id)
	suite.assert_true(authority.commit(ticket), "authentic semantic ticket commits " + row.id)
	suite.assert_true(authority.can_publish(ticket), "authentic semantic candidate remains publishable " + row.id)
	suite.assert_true(authority.rollback(ticket), "semantic rollback retains its complete compensation " + row.id)
	suite.assert_true(actor.rollback_launch_frame(prepared.ticket), "actual Actor rollback restores its original state " + row.id)
	suite.assert_equal(var_to_bytes(authority.snapshot()), semantic_before, "semantic rollback returns full original bytes " + row.id)
	suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), actor_before, "Actor rollback returns full original bytes " + row.id)
	actor.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _check_observation(suite: RefCounted, authority: RefCounted, actor: Node2D, runtime: RefCounted, records: Dictionary, frame: int, cold_fallback: bool, expected: bool, label: String) -> void:
	var original := _original_observations_match(records, frame)
	suite.assert_equal(original, expected, "original full observation decision " + label)
	var actor_before := var_to_bytes(actor.launch_runtime_snapshot())
	var transaction_before := var_to_bytes(actor.call("_actor_state"))
	var health_before := var_to_bytes(actor.get_node("HealthComponent").runtime_state_snapshot())
	var authority_before := var_to_bytes(authority.snapshot())
	var pending_before: Dictionary = authority.get("_pending").duplicate(true)
	runtime.full_snapshot_calls = 0
	var current: bool = authority.call("_observations_match", records, frame)
	var copies: int = runtime.full_snapshot_calls
	suite.assert_equal(current, original, "narrow observation retains original decision " + label)
	suite.assert_equal(copies, 1 if cold_fallback else 0, "semantic frame avoids complete Boss observation copies " + label)
	suite.assert_equal(var_to_bytes(actor.launch_runtime_snapshot()), actor_before, "observation leaves complete Actor bytes unchanged " + label)
	suite.assert_equal(var_to_bytes(actor.call("_actor_state")), transaction_before, "observation leaves full Actor transaction bytes unchanged " + label)
	suite.assert_equal(var_to_bytes(actor.get_node("HealthComponent").runtime_state_snapshot()), health_before, "observation leaves all Health bytes unchanged " + label)
	suite.assert_equal(var_to_bytes(authority.snapshot()), authority_before, "observation leaves complete semantic bytes unchanged " + label)
	suite.assert_equal(authority.get("_pending"), pending_before, "observation preserves Node-bearing ticket identity " + label)


static func _original_observations_match(records: Dictionary, frame: int) -> bool:
	for record: Dictionary in records.values():
		if not is_instance_valid(record.target) or record.target.is_queued_for_deletion() or record.target.get_node("HealthComponent").runtime_state_snapshot() != record.health:
			return false
		var expected: Vector2 = record.prepared_position if Semantics._native_actor(record.target) and int(record.target.launch_runtime_snapshot().runtime.runtime_frame) == frame else record.position
		if record.target.global_position != expected:
			return false
	return true
