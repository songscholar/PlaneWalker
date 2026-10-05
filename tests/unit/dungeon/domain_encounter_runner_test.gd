extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Adapter := preload("res://tools/dungeon/domain_encounter_runner.gd")
const Catalog := preload("res://scripts/dungeon/launch_encounter_catalog.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var catalog := Catalog.new()
	suite.assert_true(catalog.configure_authored().ok, "adapter uses actual canonical authored content")
	var encounter := catalog.resolve_for_node(Ids.PROFILE_IDS[0], 20261006, "probe_room", "combat")
	suite.assert_true(not encounter.is_empty(), "canonical launch encounter exists")
	if encounter.is_empty():
		suite.finish(get_tree())
		return
	var root := Node.new()
	add_child(root)
	var runner := Adapter.new()
	add_child(runner)
	runner.configure(root, "probe_run", "probe_room")
	var warnings: Array[Dictionary] = []
	var spawns: Array[Dictionary] = []
	var completions: Array[StringName] = []
	runner.spawn_warning_requested.connect(func(spawn: Dictionary, duration: float): warnings.append({"spawn": spawn, "duration": duration, "frame": runner.snapshot().domain.last_runtime_frame}))
	runner.spawn_requested.connect(func(spawn: Dictionary): spawns.append(spawn))
	runner.encounter_completed.connect(func(id: StringName): completions.append(id))
	runner.start_encounter(encounter, 20261006, 1)
	suite.assert_true(runner.is_active(), "native recipe starts in synthetic domain adapter")
	for _index: int in range(4096):
		if not spawns.is_empty():
			break
		suite.assert_true(runner.advance_domain_frame().ok, "adapter preserves sequential core advancement")
	suite.assert_true(not warnings.is_empty() and not spawns.is_empty(), "core publishes actual warning and spawn")
	var wave: Dictionary = encounter.waves[0]
	suite.assert_equal(warnings[0].frame, 1 + int(wave.delay_frames), "canonical warning frame is retained")
	suite.assert_equal(runner.snapshot().domain.last_runtime_frame, 1 + int(wave.delay_frames) + int(wave.warning_frames), "canonical spawn delay is retained")
	for spawn: Dictionary in spawns:
		var entity := Node.new()
		root.add_child(entity)
		var before := runner.snapshot()
		var forged := spawn.duplicate(true)
		forged.enemy_id = "forged_enemy"
		suite.assert_true(not runner.register_spawned(entity, forged), "forged spawn facts refuse")
		suite.assert_equal(runner.snapshot(), before, "forged spawn leaves authoritative state unchanged")
		suite.assert_true(runner.register_spawned(entity, spawn), "canonical spawn registers through real core")
		suite.assert_true(not runner.register_spawned(entity, spawn), "duplicate registration refuses")
		suite.assert_true(runner.notify_entity_defeated(entity), "explicit domain defeat has a real core receipt")
		suite.assert_true(not runner.notify_entity_defeated(entity), "duplicate defeat refuses")
		entity.free()
	spawns.clear()
	runner.spawn_requested.connect(func(spawn: Dictionary):
		var entity := Node.new()
		root.add_child(entity)
		suite.assert_true(runner.register_spawned(entity, spawn) and runner.notify_entity_defeated(entity), "later canonical waves complete by explicit domain commands")
		entity.free())
	for _index: int in range(4096):
		if not runner.is_active():
			break
		suite.assert_true(runner.advance_domain_frame().ok, "remaining wave advances")
	suite.assert_equal(completions, [StringName(encounter.id)], "completion publishes exactly once")
	suite.assert_true(runner.snapshot().domain.completion_published, "completion is backed by the canonical core")
	suite.assert_true(not runner.advance_domain_frame().ok, "terminal advancement refuses")
	var copy := runner.snapshot()
	copy.domain.defeat_ledger.clear()
	suite.assert_true(not runner.snapshot().domain.defeat_ledger.is_empty(), "snapshot is defensive")
	runner.cancel()
	suite.assert_true(not runner.is_active() and runner.snapshot().alive_count == 0, "cancellation clears the synthetic roster")
	var failures: Array[StringName] = []
	runner.encounter_failed.connect(func(_id: StringName, code: StringName, _context: Dictionary): failures.append(code))
	runner.start_encounter({}, 20261006, 1)
	suite.assert_true(not runner.is_active() and failures == [&"DOMAIN_ENCOUNTER_CONFIGURATION_INVALID"], "malformed canonical recipe publishes failure")
	runner.free()
	var rejector := Adapter.new()
	add_child(rejector)
	rejector.configure(root, "probe_run", "probe_room")
	rejector.spawn_requested.connect(func(spawn: Dictionary): suite.assert_true(rejector.reject_spawn(spawn, &"fixture_admission_failed"), "failed spawn goes through canonical failure lifecycle"))
	rejector.start_encounter(encounter, 20261006, 1)
	for _index: int in range(4096):
		if not rejector.is_active():
			break
		rejector.advance_domain_frame()
	suite.assert_equal(rejector.snapshot().domain.status, "FAILED", "failed spawn cannot publish completion")
	suite.assert_true(not rejector.snapshot().failure.is_empty(), "failure is visible to RoomRuntime")
	rejector.free()
	root.free()
	suite.finish(get_tree())
