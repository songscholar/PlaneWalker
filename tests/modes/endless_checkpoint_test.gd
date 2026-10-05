extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Flow := preload("res://scripts/modes/native_endless_flow.gd")
const REQUEST := {"character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"], "seed": 20261005, "accessibility_assists": {"damage_received_multiplier": 1.0, "enemy_telegraph_scale": 1.0}}
var _suite: RefCounted
var _registry: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _fixture(id: String) -> Dictionary:
	var root := Paths.resolve_default("user://p21d-checkpoint/" + id, "p21d-checkpoint/" + id)
	var save := Save.new()
	save.configure(root.path_join("profiles"), "test-p21d", Content.snapshot(_registry))
	var catalog: RefCounted = Factory.from_registry(_registry).context.catalog
	var service := Service.new()
	service.configure(catalog, save, "endless_owner", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	return {"root": root, "service": service}


func _flow(fixture: Dictionary) -> Node2D:
	var flow := Flow.new()
	add_child(flow)
	_suite.assert_true(flow.configure(_registry, fixture.service, fixture.root.path_join("modes")).ok, "actual private Endless save configured")
	return flow


func _dispose(flow: Node) -> void:
	flow.close()
	flow.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	for point: StringName in [&"before_primary_promote", &"after_primary_promote"]:
		var fixture := _fixture(str(point))
		var flow := _flow(fixture)
		flow.set_fault_injector(func(at: StringName): return at == point)
		var started: Dictionary = flow.start(REQUEST)
		if point == &"before_primary_promote":
			_suite.assert_true(not started.ok and flow.has_pending_save() and not flow.is_active() and flow.snapshot().status == "IDLE", "unpromoted Endless start never publishes combat")
			flow.set_fault_injector(Callable())
			_suite.assert_true(flow.retry_save().ok and flow.is_active(), "Endless start retry saves once before real native play")
		else:
			_suite.assert_true(started.ok and flow.is_active() and not flow.has_pending_save(), "promoted Endless start reconciles exact physical payload")
		flow.set_fault_injector(Callable())
		await get_tree().physics_frame
		flow.set_paused(true)
		var paused: Dictionary = flow.snapshot()
		await get_tree().physics_frame
		_suite.assert_equal(flow.snapshot(), paused, "Endless pause freezes accepted timing and mode state")
		flow.set_fault_injector(func(at: StringName): return at == point)
		var returned: Dictionary = flow.save_and_return()
		if point == &"before_primary_promote":
			_suite.assert_true(not returned.ok and flow.has_pending_save() and flow.is_paused(), "unpromoted return freezes native dungeon and retains retry")
			flow.set_fault_injector(Callable())
			_suite.assert_true(flow.retry_save().ok and not flow.is_active(), "save-and-return retry completes actual physical checkpoint")
		else:
			_suite.assert_true(returned.ok and not flow.is_active(), "promoted return closes only after exact physical equality")
		await _dispose(flow)
		flow = _flow(fixture)
		_suite.assert_true(flow.snapshot().status == "ACTIVE" and flow.continue_session().ok, "fresh Endless continues saved production dungeon")
		await _dispose(flow)
	var fixture := _fixture("stale")
	var first := _flow(fixture)
	var second := _flow(fixture)
	_suite.assert_true(first.start(REQUEST).ok, "first Endless CAS publishes native winner")
	var loser: Dictionary = second.start(REQUEST)
	_suite.assert_true(not loser.ok and loser.code == &"ENDLESS_STALE_PRIMARY" and not second.is_active(), "identical stale writer cannot publish a second native attempt")
	_suite.assert_true(second.reload_saved_session().ok and second.snapshot().status == "ACTIVE", "stale writer reloads actual physical winner")
	await _dispose(first)
	await _dispose(second)
	for interrupted_write: int in [3, 4]:
		var interrupted_fixture := _fixture("interrupted_%d" % interrupted_write)
		var interrupted := _flow(interrupted_fixture)
		interrupted.set_process(false)
		var writes := [0]
		interrupted.set_fault_injector(func(at: StringName):
			if at == &"before_primary_promote":
				writes[0] += 1
				return writes[0] == interrupted_write
			return false)
		_suite.assert_true(not interrupted.start(REQUEST).ok, "startup interruption is retained at atomic write %d" % interrupted_write)
		await _dispose(interrupted)
		interrupted = _flow(interrupted_fixture)
		var recovered: Dictionary = interrupted.continue_session()
		_suite.assert_true(recovered.ok and interrupted.is_active(), "physical startup interruption cold retry publishes a complete native checkpoint at write %d: %s" % [interrupted_write, recovered])
		await _dispose(interrupted)
	_suite.finish(get_tree())
