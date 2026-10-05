extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Flow := preload("res://scripts/modes/native_boss_rush_flow.gd")
const REQUEST := {"character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"], "seed": 20261005, "accessibility_assists": {"damage_received_multiplier": 1.0, "enemy_telegraph_scale": 1.0}}

var _suite: RefCounted
var _registry: RefCounted


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	await _test_checkpoint()
	await _test_faults()
	await _test_stale_writer()
	await _test_interleaved_writer()
	await _test_content_binding()
	_suite.finish(get_tree())


func _fixture(case_id: String) -> Dictionary:
	var root := Paths.resolve_default("user://p21a-checkpoint/" + case_id, "p21a-checkpoint/" + case_id)
	var storage := Save.new()
	storage.configure(root.path_join("profiles"), "test-p21a", Content.snapshot(_registry))
	var catalog: RefCounted = Factory.from_registry(_registry).context.catalog
	var service := Service.new()
	service.configure(catalog, storage, "rush_owner", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	return {"root": root, "service": service, "storage": storage}


func _flow(fixture: Dictionary) -> Node2D:
	var value := Flow.new()
	add_child(value)
	_suite.assert_true(value.configure(_registry, fixture.service, fixture.root.path_join("modes")).ok, "physical mode flow binds " + fixture.root)
	return value


func _frames(count: int) -> void:
	for _frame: int in range(count):
		await get_tree().physics_frame


func _dispose(value: Node) -> void:
	value.close()
	value.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _kill_boss(value: Node) -> void:
	await _frames(4)
	value.current_boss().health.lose_health(100000, value.current_player())
	await get_tree().process_frame
	await get_tree().process_frame


func _test_checkpoint() -> void:
	var fixture := _fixture("continuation")
	var flow := _flow(fixture)
	_suite.assert_true(flow.start(REQUEST).ok, "checkpoint begins real native challenge")
	await _kill_boss(flow)
	_suite.assert_true(flow.snapshot().status == "STAGE_CLEAR" and flow.next_stage().ok, "completed first Boss advances to actual second arena")
	await _frames(5)
	flow.set_paused(true)
	var paused: Dictionary = flow.snapshot()
	await _frames(5)
	_suite.assert_equal(flow.snapshot(), paused, "paused native stage cannot accrue challenge timer or receipts")
	_suite.assert_true(flow.save_and_return().ok, "explicit save and return physically preserves attempted frames")
	await _dispose(flow)
	flow = _flow(fixture)
	_suite.assert_equal(flow.snapshot(), paused, "fresh flow physically reloads completed receipts and elapsed attempts")
	_suite.assert_true(flow.continue_session().ok, "cold mode continues from saved uncompleted arena entrance")
	_suite.assert_true(flow.snapshot().continued and flow.snapshot().stage_index == 1 and flow.snapshot().completed_stages.size() == 1, "continued category never replays earned Boss stages")
	_suite.assert_equal(flow.current_player().health.current_hp, flow.current_player().health.max_hp, "continued arena uses documented full-health stage preset")
	await _frames(3)
	flow.current_player().health.lose_health(100000)
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_true(flow.snapshot().status == "DEFEAT", "real Player death durably ends continued challenge")
	await _dispose(flow)
	flow = _flow(fixture)
	_suite.assert_true(flow.snapshot().status == "DEFEAT" and not flow.continue_session().ok, "fresh flow reloads terminal defeat and refuses continuation")
	await _dispose(flow)


func _test_faults() -> void:
	for point: StringName in [&"before_primary_promote", &"after_primary_promote"]:
		var fixture := _fixture(str(point))
		var flow := _flow(fixture)
		flow.set_fault_injector(func(at: StringName): return at == point)
		var launched: Dictionary = flow.start(REQUEST)
		if point == &"before_primary_promote":
			_suite.assert_true(not launched.ok and not flow.is_active() and flow.has_pending_save() and flow.snapshot().status == "IDLE", "unpromoted launch never publishes playable state")
			flow.set_fault_injector(Callable())
			_suite.assert_true(flow.retry_save().ok and flow.is_active(), "launch retry physically saves before creating combat")
		else:
			_suite.assert_true(launched.ok and flow.is_active() and not flow.has_pending_save(), "post-promotion launch is accepted only after physical candidate equality")
		flow.set_fault_injector(func(at: StringName): return at == point)
		await _kill_boss(flow)
		if point == &"before_primary_promote":
			_suite.assert_true(flow.has_pending_save() and flow.snapshot().completed_stages.is_empty() and not flow.next_stage().ok, "failed terminal save freezes real dead Boss before advancement")
			flow.set_fault_injector(Callable())
			_suite.assert_true(flow.retry_save().ok, "terminal retry persists authenticated receipt exactly once")
		_suite.assert_true(flow.snapshot().status == "STAGE_CLEAR" and flow.snapshot().completed_stages.size() == 1, "promoted terminal contains one earned receipt")
		flow.set_fault_injector(Callable())
		_suite.assert_true(flow.save_and_return().ok, "fault-recovered summary returns")
		await _dispose(flow)
		flow = _flow(fixture)
		_suite.assert_true(flow.snapshot().completed_stages.size() == 1 and flow.continue_session().ok and flow.snapshot().stage_index == 1, "physical terminal recovery advances completed arena once")
		await _dispose(flow)


func _test_stale_writer() -> void:
	var fixture := _fixture("stale")
	var first := _flow(fixture)
	var stale := _flow(fixture)
	_suite.assert_true(first.start(REQUEST).ok, "first independent native flow durably launches")
	var before: Dictionary = stale.snapshot()
	var changed := REQUEST.duplicate(true)
	changed.seed += 1
	var refused: Dictionary = stale.start(changed)
	_suite.assert_true(not refused.ok and refused.code == &"CHALLENGE_STALE_PRIMARY" and not stale.is_active(), "stale separately loaded writer cannot overwrite newer physical mode state")
	_suite.assert_equal(stale.snapshot(), before, "stale refusal leaves its local session unchanged")
	_suite.assert_true(stale.has_pending_save() and stale.reload_saved_session().ok and stale.snapshot().request.seed == REQUEST.seed and not stale.has_pending_save(), "stale pending command is recoverable through physical checkpoint reload")
	await _dispose(first)
	await _dispose(stale)
	var reloaded := _flow(fixture)
	_suite.assert_equal(reloaded.snapshot().request.seed, REQUEST.seed, "newer physical request survives stale writer refusal")
	await _dispose(reloaded)


func _test_interleaved_writer() -> void:
	var fixture := _fixture("interleaved")
	var first := _flow(fixture)
	var second := _flow(fixture)
	var competitor := REQUEST.duplicate(true)
	competitor.seed += 9
	first.set_fault_injector(func(at: StringName):
		if at == &"before_primary_promote":
			_suite.assert_true(second.start(competitor).ok, "separate writer interleaves one physical promotion")
		return false
	)
	var refused: Dictionary = first.start(REQUEST)
	_suite.assert_true(not refused.ok and refused.code == &"CHALLENGE_STALE_PRIMARY" and not first.is_active(), "promotion preimage refuses interleaved competing session")
	first.set_fault_injector(Callable())
	await _dispose(second)
	_suite.assert_true(first.reload_saved_session().ok and first.snapshot().request.seed == competitor.seed, "interleaved winner survives physical recovery")
	await _dispose(first)


func _test_content_binding() -> void:
	var fixture := _fixture("content-drift")
	var drift: Dictionary = Content.snapshot(_registry)
	drift.packs[0].fingerprint_sha256 = "f".repeat(64)
	drift.aggregate_sha256 = preload("res://scripts/save/save_envelope.gd").content_snapshot_digest(drift.packs)
	fixture.storage.configure(fixture.root.path_join("profiles"), "test-p21a", drift)
	var flow := Flow.new()
	add_child(flow)
	_suite.assert_true(not flow.configure(_registry, fixture.service, fixture.root.path_join("modes")).ok, "registry and Profile storage content identities must match before challenge construction")
	await _dispose(flow)
