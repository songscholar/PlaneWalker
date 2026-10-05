extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Content := preload("res://tests/support/p15_hostile_fixtures.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Boss := preload("res://scripts/enemies/launch/launch_boss_runtime.gd")
const AuxFixture := preload("res://tests/unit/enemies/void_auxiliary_runtime_test.gd")
const Scene := preload("res://data/content_packs/base/assets/bosses/launch/boss_void_throne.tscn")
var suite: RefCounted
var definition: Dictionary
var identity := {"run_id": "run-void", "hostile_source_id": "void-owner", "next_generation_floor": 7, "runtime_frame": 0, "seed": 42}


class CountingArena extends "res://scripts/enemies/launch/void_arena_runtime.gd":
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return super.snapshot()


class CountingAuxiliary extends "res://scripts/enemies/launch/void_auxiliary_runtime.gd":
	var full_snapshot_calls := 0

	func snapshot() -> Dictionary:
		full_snapshot_calls += 1
		return super.snapshot()


class ColdQueries extends RefCounted:
	var arena: Dictionary
	var auxiliary: Dictionary
	var arena_calls := 0
	var auxiliary_calls := 0

	func void_arena_snapshot() -> Dictionary:
		arena_calls += 1
		return arena.duplicate(true)

	func void_auxiliary_snapshot() -> Dictionary:
		auxiliary_calls += 1
		return auxiliary.duplicate(true)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var arena := CountingArena.new()
	var boss := Boss.new()
	var actor := Scene.instantiate()
	var available: bool = arena.has_method("native_geometry_snapshot") and boss.has_method("native_void_arena_geometry_snapshot") and boss.has_method("native_void_active_pickups") and actor.has_method("native_void_arena_geometry_snapshot")
	actor.free()
	suite.assert_true(available, "native Void geometry and pickup queries avoid complete domain histories")
	if not available:
		suite.finish(get_tree())
		return
	suite.assert_equal(boss.call("native_void_arena_geometry_snapshot"), {}, "unconfigured Boss preserves empty arena observation")
	suite.assert_equal(boss.call("native_void_active_pickups"), [], "unconfigured Boss preserves empty active pickups")
	var parser := Definition.new()
	suite.assert_true(parser.configure(Content.boss("void_throne")).ok, "queries use the authored Void definition")
	definition = parser.runtime_projection()
	_check_arena()
	await _check_actor()
	suite.finish(get_tree())


func _check_arena() -> void:
	var arena := CountingArena.new()
	suite.assert_equal(arena.call("native_geometry_snapshot"), {}, "unconfigured arena keeps an empty geometry query")
	suite.assert_true(arena.configure(definition, identity).ok and arena.bind_origin({"x": 11.0, "y": -7.0}), "real arena binds a nonzero actual origin")
	var initial: Dictionary = arena.snapshot()
	_assert_arena(arena, "configured")
	suite.assert_true(arena.accept_damage_fact(_damage("pillar", "void_cover_pillar:0", 0, 80.0)).ok, "authentic pillar damage changes geometry state")
	_assert_arena(arena, "damaged")
	suite.assert_true(arena.accept_phase(2, 0).ok, "real phase transition retires pillars and starts cores")
	_assert_arena(arena, "phase transition")
	for slot: int in range(4):
		suite.assert_true(arena.accept_damage_fact(_damage("core-%d" % slot, "void_plane_core:1:%d" % slot, 0, 100.0)).ok, "real core break retains full event authority")
	for frame: int in range(1, 601):
		suite.assert_true(arena.advance_frame(frame), "arena advances through second-round regeneration")
	_assert_arena(arena, "second round")
	arena.retire()
	_assert_arena(arena, "terminal")
	suite.assert_true(arena.restore_snapshot(initial), "historical complete state remains authoritative for restore")
	_assert_arena(arena, "historical rollback")
	suite.assert_true(arena.bind_origin({"x": -19.0, "y": 23.0}), "restored initial authority can bind a changed origin")
	_assert_arena(arena, "changed origin")


func _assert_arena(arena: RefCounted, label: String) -> void:
	var full: Dictionary = arena.snapshot()
	var before := var_to_bytes(full)
	var expected := {"arena_origin": full.arena_origin, "terminal": full.terminal, "pillars": full.pillars, "cores": full.cores}
	arena.full_snapshot_calls = 0
	var actual: Dictionary = arena.call("native_geometry_snapshot")
	suite.assert_equal(var_to_bytes(actual), var_to_bytes(expected), "geometry keeps every original typed physical field: " + label)
	suite.assert_equal(arena.full_snapshot_calls, 0, "geometry avoids complete history capture: " + label)
	actual.arena_origin.x += 1.0
	actual.terminal = not actual.terminal
	actual.pillars[0].position.x += 1.0
	actual.pillars[0].current_hp = -1.0
	if not actual.cores.is_empty():
		actual.cores[0].id = "caller-mutated"
	actual.pillars.clear()
	suite.assert_equal(var_to_bytes(arena.snapshot()), before, "all mutable geometry descendants remain detached: " + label)


func _check_actor() -> void:
	var actor := Scene.instantiate() as Node2D
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(actor)
	suite.assert_true(actor.configure_launch_definition(definition, identity).ok, "actual authored Void actor configures")
	var runtime: RefCounted = actor.get("_launch_runtime")
	var origin: Vector2 = actor.call("_native_arena_origin")
	var arena := CountingArena.new()
	var auxiliary := CountingAuxiliary.new()
	suite.assert_true(arena.configure(definition, identity).ok and arena.bind_origin({"x": origin.x, "y": origin.y}) and arena.restore_snapshot(runtime.void_arena_snapshot()), "counted arena retains actual complete authority")
	suite.assert_true(auxiliary.configure(definition, identity).ok and auxiliary.bind_origin({"x": origin.x, "y": origin.y}) and auxiliary.restore_snapshot(runtime.void_auxiliary_snapshot()), "counted auxiliary retains actual complete authority")
	runtime.set("_void_arena", arena)
	runtime.set("_void_auxiliary", auxiliary)
	var initial_arena: Dictionary = arena.snapshot()
	var initial_auxiliary: Dictionary = auxiliary.snapshot()
	_assert_actor(actor, runtime, arena, auxiliary, "configured")
	var fixture := AuxFixture.new()
	fixture.definition = definition
	suite.assert_true(auxiliary.reserve_cast(fixture.call("_cast", "voidking_shard_projection", 7, 0)).ok, "real auxiliary cast creates native pickups")
	fixture.free()
	_assert_actor(actor, runtime, arena, auxiliary, "active pickups")
	var spawned_auxiliary: Dictionary = auxiliary.snapshot()
	var holder := actor.get_node("VoidAuxiliaryPickups")
	var pickup := holder.get_child(0)
	var shape: CollisionShape2D = pickup.get("_shape")
	shape.shape.radius += 1.0
	suite.assert_true(not actor.call("_native_geometry_matches_definition"), "narrow query retains physical pickup shape refusal")
	shape.shape.radius -= 1.0
	var pillar := actor.get_node("VoidArenaConstructs").get_child(0)
	pillar.position.x += 1.0
	suite.assert_true(not actor.call("_native_geometry_matches_definition"), "narrow query retains actual construct transform refusal")
	pillar.position.x -= 1.0
	var active: Array = auxiliary.active_pickups()
	var receipt := {"fact_id": "pickup", "run_id": identity.run_id, "owner_source_id": identity.hostile_source_id, "pickup_id": active[0].id, "target_id": "player", "runtime_frame": 0, "energy_before": 98.0, "energy_after": 100.0, "maximum": 100.0, "revision_before": 1, "revision_after": 2}
	suite.assert_true(auxiliary.consume_pickup(receipt).ok, "authentic resource receipt consumes one real pickup")
	_assert_actor(actor, runtime, arena, auxiliary, "consumed pickup")
	for frame: int in range(1, 181):
		suite.assert_true(auxiliary.advance_frame(frame), "real pickup lifetime advances")
	_assert_actor(actor, runtime, arena, auxiliary, "expired pickups")
	suite.assert_true(auxiliary.restore_snapshot(spawned_auxiliary), "complete auxiliary history rolls back live pickups before retirement")
	suite.assert_true(auxiliary.accept_phase(1, 0).ok, "phase retirement preserves existing pickup semantics")
	_assert_actor(actor, runtime, arena, auxiliary, "phase retirement")
	auxiliary.retire()
	arena.retire()
	_assert_actor(actor, runtime, arena, auxiliary, "terminal domains")
	suite.assert_true(arena.restore_snapshot(initial_arena) and auxiliary.restore_snapshot(initial_auxiliary), "both actual domains restore complete historical state")
	_assert_actor(actor, runtime, arena, auxiliary, "historical restore")
	var cold := ColdQueries.new()
	cold.arena = arena.snapshot()
	cold.auxiliary = spawned_auxiliary
	actor.set("_launch_runtime", cold)
	suite.assert_equal(var_to_bytes(actor.call("native_void_arena_geometry_snapshot")), var_to_bytes(cold.arena), "query-less arena runtime retains original complete fallback")
	suite.assert_equal(var_to_bytes(actor.call("_active_void_pickups")), var_to_bytes(cold.auxiliary.pickups), "query-less auxiliary retains original active pickup projection")
	suite.assert_true(cold.arena_calls == 1 and cold.auxiliary_calls == 1, "cold fallbacks each take one original complete observation")
	actor.set("_launch_runtime", runtime)
	actor.queue_free()
	await get_tree().process_frame


func _assert_actor(actor: Node2D, runtime: RefCounted, arena: RefCounted, auxiliary: RefCounted, label: String) -> void:
	var full: Dictionary = arena.snapshot()
	var expected := {"arena_origin": full.arena_origin, "terminal": full.terminal, "pillars": full.pillars, "cores": full.cores}
	var aux_full: Dictionary = auxiliary.snapshot()
	var expected_pickups: Array = [] if aux_full.terminal else aux_full.pickups.filter(func(row: Dictionary): return not row.used and not row.retired and int(aux_full.runtime_frame) < int(row.through_frame))
	arena.full_snapshot_calls = 0
	auxiliary.full_snapshot_calls = 0
	var geometry: Dictionary = actor.call("native_void_arena_geometry_snapshot")
	var pickups: Array = actor.call("_active_void_pickups")
	suite.assert_equal(var_to_bytes(geometry), var_to_bytes(expected), "actual geometry keeps typed original projection: " + label)
	suite.assert_equal(var_to_bytes(pickups), var_to_bytes(expected_pickups), "actual pickups keep original filtering and order: " + label)
	actor.call("_refresh_native_void")
	suite.assert_true(actor.call("_native_geometry_matches_definition"), "every actual physical construct and pickup still validates: " + label)
	suite.assert_true(arena.full_snapshot_calls == 0 and auxiliary.full_snapshot_calls == 0, "native query, refresh and physical checks avoid full histories: " + label)
	geometry.arena_origin.x += 1.0
	geometry.pillars[0].id = "caller-mutated"
	if not pickups.is_empty():
		pickups[0].position.x += 1.0
		pickups.clear()
	suite.assert_equal(var_to_bytes(arena.snapshot()), var_to_bytes(full), "actual arena query mutation is isolated: " + label)
	suite.assert_equal(var_to_bytes(auxiliary.snapshot()), var_to_bytes(aux_full), "actual active pickup mutation is isolated: " + label)
	arena.full_snapshot_calls = 0
	auxiliary.full_snapshot_calls = 0
	suite.assert_equal(var_to_bytes(actor.native_void_arena_snapshot()), var_to_bytes(full), "public full arena snapshot retains all events: " + label)
	suite.assert_equal(var_to_bytes(actor.native_void_auxiliary_snapshot()), var_to_bytes(aux_full), "public full auxiliary snapshot retains all receipts: " + label)
	suite.assert_true(arena.full_snapshot_calls == 1 and auxiliary.full_snapshot_calls == 1, "public full observations retain original complete captures: " + label)
	suite.assert_equal(var_to_bytes(runtime.call("native_void_active_pickups")), var_to_bytes(expected_pickups), "Boss wrapper retains existing active pickup authority: " + label)


func _damage(id: String, construct: String, frame: int, amount: float) -> Dictionary:
	return {"fact_id": id, "run_id": identity.run_id, "owner_source_id": identity.hostile_source_id, "construct_id": construct, "runtime_frame": frame, "amount": amount}
