extends "res://tests/replay/native_run_replay_recorder_test.gd"


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 4}
	suite.assert_true(main._launch_run(config, false, true), "bounded queue uses actual native Main")
	_freeze(main)
	var host: Node = main.get_node("RunRuntimeHost")
	var player: Node = main.get_node("CombatRoom01/Player")
	var recorder: Node = main.get_node("NativeRunReplayRecorder")
	for route: Dictionary in host.route_choices():
		if route.room_type == "combat":
			suite.assert_true(host.select_route(StringName(route.edge_id), int(host.runtime_snapshot().revision)).ok, "bounded queue enters an actual encounter")
			break
	host.set_dungeon_selection_safety(false)
	player.health.acquire_invulnerability_source(&"backpressure_fixture")
	suite.assert_true(recorder.observe_transition().ok, "native transition precedes blocked write")
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var first_write: Array[bool] = [true]
	recorder.store().set_fault_injector(func(point: StringName):
		if point == &"before_primary_promote" and first_write[0]:
			first_write[0] = false
			entered.post()
			release.wait()
		return false
	)
	for _frame: int in range(118):
		suite.assert_true(player.advance_action_frame(), "native frame reaches the first background batch")
		await get_tree().physics_frame
	var blocked := false
	for _poll: int in range(600):
		if entered.try_wait():
			blocked = true
			break
		await get_tree().process_frame
	suite.assert_true(blocked and recorder.snapshot().pending_write, "worker reaches the physical promotion gate")
	var rejected: Array[StringName] = []
	recorder.rejected.connect(func(code: StringName): rejected.append(code))
	for _frame: int in range(121):
		suite.assert_true(player.advance_action_frame(), "gameplay continues while recording disk is blocked")
		await get_tree().physics_frame
	var state: Dictionary = recorder.snapshot()
	suite.assert_true(not state.active and state.failure == &"RUN_REPLAY_RECORDER_CAPACITY", "excess backlog stops recording explicitly without blocking combat")
	suite.assert_true(state.buffered_count <= 120 and state.pending_write_count <= 120 and state.observation_count <= 240, "blocked writer has a strict two-chunk memory bound")
	suite.assert_equal(rejected, [&"RUN_REPLAY_RECORDER_CAPACITY"], "backpressure publishes one recording failure")
	release.post()
	# Join through the normal recorder shutdown path, including pending failure status.
	var storage: RefCounted = recorder.store()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_equal(storage.rows()[0].status, "FAILED", "retirement joins physical work and classifies the partial tape")
	suite.assert_equal(storage.rows()[0].observation_count, 120, "only the accepted physical batch is retained")
	var probe: GDScript = load("res://tools/p15/native_performance_probe.gd")
	suite.assert_true(probe.has_method("retained_recording_status"), "performance evidence must derive actual retained recording status")
	if probe.has_method("retained_recording_status"):
		suite.assert_equal(probe.retained_recording_status(storage, str(state.id)), "FAILED", "failed native tape cannot be reported as an ordinary interruption")
	suite.finish(get_tree())
