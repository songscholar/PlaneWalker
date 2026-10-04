extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_encounter_fixtures.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	var implementation = load("res://scripts/dungeon/launch_encounter_runtime.gd")
	suite.assert_true(implementation != null, "fixed-frame Launch encounter runtime exists")
	if implementation == null:
		suite.finish(get_tree())
		return
	_test_waves_and_pending_work(suite, implementation)
	_test_corruption_and_replay(suite, implementation)
	_test_failed_spawns_and_cancellation(suite, implementation)
	_test_pending_queue_contract(suite, implementation)
	suite.finish(get_tree())


func _configured(suite: RefCounted, implementation: Script) -> RefCounted:
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure(Fixtures.encounter(), Fixtures.identity()).ok, "Launch encounter configures")
	return runtime


func _spawn_first_wave(suite: RefCounted, runtime: RefCounted) -> void:
	var first: Dictionary = runtime.advance_frame(1, {})
	suite.assert_equal(first.wave_started, {"wave_index": 0, "wave_id": "sentinel_line_wave_1"}, "first accepted frame commits first wave")
	suite.assert_equal(first.spawn_warnings.size(), 2, "wave warns every declared actor once")
	suite.assert_equal(first.spawn_requests, [], "warning start does not spawn")
	for frame: int in range(2, 31):
		var outcome: Dictionary = runtime.advance_frame(frame, {})
		suite.assert_equal(outcome.spawn_requests, [], "warning has no premature spawn")
		suite.assert_equal(outcome.spawn_warnings, [], "warning does not republish")
	var spawn_frame: Dictionary = runtime.advance_frame(31, {})
	suite.assert_equal(spawn_frame.spawn_requests.size(), 2, "first active spawn edge is frame 31")
	suite.assert_true(runtime.register_spawned("spawn_1", "hostile:sentinel-1"), "first spawn receipt binds stable source")
	suite.assert_true(runtime.register_spawned("spawn_2", "hostile:sentinel-2"), "second spawn receipt binds stable source")
	suite.assert_true(not runtime.register_spawned("spawn_1", "hostile:sentinel-1"), "spawn receipt never counts twice")
	suite.assert_equal(runtime.alive_count(), 2, "two counted actors are alive")


func _test_waves_and_pending_work(suite: RefCounted, implementation: Script) -> void:
	var runtime := _configured(suite, implementation)
	_spawn_first_wave(suite, runtime)
	suite.assert_true(runtime.set_life_state("hostile:sentinel-1", "DORMANT"), "nonterminal life is accepted")
	suite.assert_equal(runtime.alive_count(), 2, "dormant actor remains counted")
	suite.assert_true(not runtime.notify_entity_defeated("hostile:sentinel-1", "death-1"), "dormancy cannot masquerade as final death")
	suite.assert_true(runtime.set_life_state("hostile:sentinel-1", "ALIVE"), "reformed actor returns alive")
	suite.assert_true(runtime.reserve_pending_work("death-pool", "zone", "hostile:sentinel-1"), "warned death pool reserves pending room work")
	suite.assert_true(runtime.notify_entity_defeated("hostile:sentinel-1", "death-1"), "final death consumes counted actor")
	suite.assert_true(not runtime.notify_entity_defeated("hostile:sentinel-1", "death-1"), "duplicate final death is rejected")
	suite.assert_true(not runtime.notify_entity_defeated("hostile:sentinel-2", "death-1"), "receipt cannot bind two actors")
	suite.assert_true(runtime.notify_entity_defeated("hostile:sentinel-2", "death-2"), "second final death accepts unique receipt")
	suite.assert_equal(runtime.alive_count(), 0, "counted actors are cleared")
	suite.assert_true(not runtime.can_complete(), "remaining death pool forbids room completion")
	suite.assert_equal(runtime.advance_frame(32, {}).wave_started, {}, "pending pool forbids next wave")
	suite.assert_true(runtime.retire_pending_work("death-pool"), "pool retirement settles pending work")
	var second_wave: Dictionary = runtime.advance_frame(33, {})
	suite.assert_equal(second_wave.wave_started.wave_index, 1, "second wave begins after pending work settles")
	for frame: int in range(34, 39):
		suite.assert_equal(runtime.advance_frame(frame, {}).spawn_warnings, [], "six-frame wave delay is preserved")
	suite.assert_equal(runtime.advance_frame(39, {}).spawn_warnings.size(), 1, "warning begins after six-frame delay")
	for frame: int in range(40, 69):
		suite.assert_equal(runtime.advance_frame(frame, {}).spawn_requests, [], "second warning remains complete")
	suite.assert_equal(runtime.advance_frame(69, {}).spawn_requests.size(), 1, "second wave spawns at exact delayed edge")
	suite.assert_true(not runtime.can_complete(), "unacknowledged spawn forbids completion")
	suite.assert_true(runtime.register_spawned("spawn_3", "hostile:sentinel-3"), "last wave spawn acknowledges")
	suite.assert_true(runtime.notify_entity_defeated("hostile:sentinel-3", "death-3"), "last actor finalizes")
	var completion: Dictionary = runtime.advance_frame(70, {})
	suite.assert_equal(completion.encounter_completed, "encounter_profile_ruins_adapter_v1.sentinel_line", "completion publishes once on accepted frame")
	suite.assert_true(runtime.can_complete(), "complete state reports completion")
	var terminal: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.advance_frame(71, {}).ok, "post-terminal frame rejects")
	suite.assert_equal(runtime.snapshot(), terminal, "post-terminal rejection is pure")


func _test_corruption_and_replay(suite: RefCounted, implementation: Script) -> void:
	var runtime := _configured(suite, implementation)
	_spawn_first_wave(suite, runtime)
	var checkpoint: Dictionary = runtime.snapshot()
	var replay := _configured(suite, implementation)
	suite.assert_true(replay.restore_snapshot(checkpoint), "mid-combat encounter snapshot restores")
	for source_id: String in ["hostile:sentinel-1", "hostile:sentinel-2"]:
		runtime.notify_entity_defeated(source_id, "defeat:" + source_id)
		replay.notify_entity_defeated(source_id, "defeat:" + source_id)
	for frame: int in range(32, 45):
		suite.assert_equal(replay.advance_frame(frame, {}), runtime.advance_frame(frame, {}), "restored encounter emits identical facts")
		suite.assert_equal(replay.snapshot(), runtime.snapshot(), "restored encounter retains identical state")
	for field: String in checkpoint:
		var missing := checkpoint.duplicate(true)
		missing.erase(field)
		suite.assert_true(not replay.can_restore_snapshot(missing), "encounter restore requires " + field)
	for field: String in ["wave_index", "last_runtime_frame", "spawn_frame"]:
		var corrupt := checkpoint.duplicate(true)
		corrupt[field] = true
		suite.assert_true(not replay.can_restore_snapshot(corrupt), "Boolean cannot supply " + field)
	var corrupt := checkpoint.duplicate(true)
	corrupt.roster["hostile:sentinel-2"].spawn_id = "spawn_1"
	suite.assert_true(not replay.can_restore_snapshot(corrupt), "duplicate spawn binding rejects")
	corrupt = checkpoint.duplicate(true)
	corrupt.pending_spawns["spawn_1"] = Fixtures.spawn("spawn_1")
	suite.assert_true(not replay.can_restore_snapshot(corrupt), "pending/alive overlap rejects")
	var wrong_phase := checkpoint.duplicate(true)
	wrong_phase.status = "READY"
	suite.assert_true(not replay.can_restore_snapshot(wrong_phase), "started wave cannot restore as READY")
	var before: Dictionary = replay.snapshot()
	suite.assert_true(not replay.restore_snapshot(corrupt), "corrupt restore rejects")
	suite.assert_equal(replay.snapshot(), before, "corrupt restore is pure")
	suite.assert_true(not replay.advance_frame(int(before.last_runtime_frame), {}).ok, "duplicate encounter frame rejects")
	suite.assert_equal(replay.snapshot(), before, "duplicate frame is pure")
	suite.assert_true(not replay.advance_frame(int(before.last_runtime_frame) + 1, {"untrusted": self}).ok, "external object observation rejects")
	suite.assert_equal(replay.snapshot(), before, "invalid observation is pure")
	var during_delay: Dictionary = runtime.snapshot()
	during_delay.defeat_ledger["hostile:premature"] = {"spawn_id": "spawn_3", "enemy_id": "shattered_sentinel", "receipt_id": "premature-death", "frame": during_delay.last_runtime_frame}
	suite.assert_true(not runtime.can_restore_snapshot(during_delay), "unspawned current-wave enemy cannot have a final death")


func _test_failed_spawns_and_cancellation(suite: RefCounted, implementation: Script) -> void:
	var runtime := _configured(suite, implementation)
	_spawn_first_wave(suite, runtime)
	for index: int in range(12):
		suite.assert_true(runtime.reserve_pending_work("zone:%d" % index, "zone", "hostile:sentinel-1"), "zone budget admits declared capacity")
	var before: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.reserve_pending_work("zone:overflow", "zone", "hostile:sentinel-1"), "zone budget rejects overflow")
	suite.assert_equal(runtime.snapshot(), before, "budget rejection is pure")
	suite.assert_true(not runtime.reserve_pending_work("unknown-owner", "construct", "foreign"), "unbound work owner rejects")
	var cancelled: Dictionary = runtime.cancel(&"room_exit")
	suite.assert_equal(cancelled.retired_sources.size(), 2, "cancellation retires every live source")
	suite.assert_equal(cancelled.retired_work_ids.size(), 12, "cancellation retires every reserved payload")
	suite.assert_true(not runtime.advance_frame(32, {}).ok, "cancelled encounter cannot advance")


func _test_pending_queue_contract(suite: RefCounted, implementation: Script) -> void:
	var runtime := _configured(suite, implementation)
	_spawn_first_wave(suite, runtime)
	suite.assert_true(runtime.has_method("activate_pending_work"), "room ledger distinguishes queued work from active budget reservations")
	if not runtime.has_method("activate_pending_work"):
		return
	for index: int in range(32):
		suite.assert_true(runtime.reserve_pending_work("projectile-%d" % index, "projectile", "hostile:sentinel-1"), "room ledger reserves each active projectile slot")
	suite.assert_true(runtime.call("reserve_pending_work", "projectile-queued", "projectile", "hostile:sentinel-1", "PENDING"), "full projectile budget retains queued authoritative work")
	var full: Dictionary = runtime.snapshot()
	var overfull_legacy := full.duplicate(true)
	overfull_legacy.schema_version = 1
	for row: Dictionary in overfull_legacy.pending_work.values():
		row.erase("phase")
	suite.assert_true(not runtime.can_restore_snapshot(overfull_legacy), "legacy migration cannot disguise queued overflow as an active budget")
	suite.assert_equal(full.schema_version, 2, "queued-work checkpoint has an explicit new schema version")
	suite.assert_true(not runtime.activate_pending_work("projectile-queued"), "queued projectile cannot bypass the full active budget")
	suite.assert_equal(runtime.snapshot(), full, "failed promotion leaves queued identity and budget unchanged")
	suite.assert_true(runtime.retire_pending_work("projectile-0") and runtime.activate_pending_work("projectile-queued"), "one retired active slot admits the existing queued identity")
	suite.assert_equal(runtime.snapshot().pending_work["projectile-queued"].phase, "ACTIVE", "promotion keeps the same room-work lineage")
	var malformed: Dictionary = runtime.snapshot()
	malformed.pending_work["projectile-queued"].phase = "WARNING"
	suite.assert_true(not runtime.can_restore_snapshot(malformed), "room ledger rejects unknown reservation phases")
	var legacy: Dictionary = runtime.snapshot()
	legacy.schema_version = 1
	for row: Dictionary in legacy.pending_work.values():
		row.erase("phase")
	suite.assert_true(runtime.restore_snapshot(legacy), "legacy active-only native checkpoints migrate without losing budgets")
	suite.assert_equal(runtime.snapshot().schema_version, 2, "legacy checkpoint normalizes to the new work schema")
	for row: Dictionary in runtime.snapshot().pending_work.values():
		suite.assert_equal(row.phase, "ACTIVE", "legacy work remains active after migration")
	for id: String in runtime.snapshot().pending_work.keys():
		runtime.retire_pending_work(id)
	runtime.notify_entity_defeated("hostile:sentinel-1", "queue-death-1")
	runtime.notify_entity_defeated("hostile:sentinel-2", "queue-death-2")
	suite.assert_true(runtime.call("reserve_pending_work", "queued-after-death", "zone", "hostile:sentinel-1", "PENDING"), "dead parent retains its queued payload lineage")
	suite.assert_equal(runtime.advance_frame(32).wave_started, {}, "queued payload forbids next wave even with no active body or zone")
	var queued: Dictionary = runtime.snapshot()
	for index: int in range(255):
		suite.assert_true(runtime.call("reserve_pending_work", "queued-%d" % index, "zone", "hostile:sentinel-1", "PENDING"), "queued room work obeys a finite retained reservation cap")
	var capacity: Dictionary = runtime.snapshot()
	suite.assert_true(not runtime.call("reserve_pending_work", "queued-overflow", "zone", "hostile:sentinel-1", "PENDING"), "full retained room queue rejects further work")
	suite.assert_equal(runtime.snapshot(), capacity, "queue capacity rejection retains all existing identities")
	suite.assert_true(runtime.restore_snapshot(queued) and runtime.retire_pending_work("queued-after-death"), "queued final retirement restores and settles its exact identity")
	suite.assert_equal(runtime.advance_frame(33).wave_started.wave_index, 1, "next wave begins only after queued work also retires")
	runtime = _configured(suite, implementation)
	for frame: int in range(1, 32):
		runtime.advance_frame(frame, {})
	suite.assert_true(runtime.reject_spawn("spawn_1", &"NO_REACHABLE_POSITION"), "spawn rejection enters typed failure")
	suite.assert_equal(runtime.snapshot().status, "FAILED", "rejected spawn cannot silently clear room")
	suite.assert_true(not runtime.can_complete(), "failed encounter never reports completion")
