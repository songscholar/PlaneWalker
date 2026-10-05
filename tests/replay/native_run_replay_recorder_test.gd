extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Store := preload("res://scripts/replay/run_replay_stream_store.gd")
const RECORDER_PATH := "res://scripts/replay/native_run_replay_recorder.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(RECORDER_PATH), "automatic native whole-run recorder must exist")
	if not ResourceLoader.exists(RECORDER_PATH):
		suite.finish(get_tree())
		return
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var recorder: Node = main.get_node_or_null("NativeRunReplayRecorder")
	suite.assert_true(recorder != null, "actual Main installs the automatic production recorder")
	if recorder == null:
		main.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 4}
	suite.assert_true(main._launch_run(config, false, true), "actual Main starts the automatically recorded run")
	var host: Node = main.get_node("RunRuntimeHost")
	var player: Node2D = main.get_node("CombatRoom01/Player")
	_freeze(main)
	var initial: Dictionary = recorder.snapshot()
	suite.assert_true(initial.active and initial.observation_count == 1, "actual launch captures its complete initial observation")
	var choices: Array = host.route_choices()
	var selected: Dictionary = choices[0]
	for choice: Dictionary in choices:
		if choice.room_type == "combat":
			selected = choice
			break
	suite.assert_true(host.select_route(StringName(selected.edge_id), int(host.runtime_snapshot().revision)).ok, "actual production route streams the recorded native room")
	host.set_dungeon_selection_safety(false)
	player.health.acquire_invulnerability_source(&"recording_fixture")
	suite.assert_true(recorder.observe_transition().ok, "accepted native room boundary is recorded automatically")
	var native_seen := false
	var observed_before: int = int(recorder.snapshot().observation_count)
	recorder.store().set_fault_injector(func(point: StringName):
		if point == &"before_primary_promote":
			OS.delay_msec(250)
		return false
	)
	for index: int in range(125):
		var frame_started := Time.get_ticks_usec()
		suite.assert_true(player.advance_action_frame({"movement": Vector2.ZERO, "aim": Vector2.RIGHT}), "actual accepted production Player frame records %d" % index)
		if (observed_before + index + 1) % 120 == 0:
			suite.assert_true(float(Time.get_ticks_usec() - frame_started) / 1000.0 < 100.0, "slow physical chunk writes never run on the accepted gameplay frame")
			suite.assert_true(recorder.snapshot().get("pending_write", false), "automatic capture has an explicit bounded background write")
		var current: Dictionary = recorder.latest_observation()
		native_seen = native_seen or not current.get("native", {}).get("actors", {}).is_empty()
		await get_tree().physics_frame
	suite.assert_true(native_seen, "automatic tape contains actual native hostile actors without fixture-authored snapshots")
	suite.assert_equal(recorder.snapshot().observation_count, observed_before + 125, "every actual accepted frame produces exactly one observation")
	var last: Dictionary = recorder.latest_observation()
	suite.assert_true(var_to_bytes(last.player) == var_to_bytes(player.full_player_replay_snapshot()), "automatic latest Player observation is byte-exact native state")
	suite.assert_equal(last.run, host.runtime_snapshot(), "automatic observation captures authoritative route and economy")
	var profile_before: Dictionary = GameState.profile_runtime_service().snapshot()
	suite.assert_true(recorder.flush().ok, "actual accepted native observations flush into physical immutable chunks")
	var identity: Dictionary = GameState.profile_runtime_service().local_record_storage_identity()
	var retained := Store.new()
	suite.assert_true(retained.configure(recorder.storage_root(), "0.4.0-dev", identity.content_snapshot, identity.profile_id, identity.save_domain).ok, "fresh physical store reloads automatic recording")
	var record_id: String = recorder.snapshot().id
	var read: Dictionary = retained.read(record_id, int(last.sequence))
	suite.assert_true(read.ok and var_to_bytes(read.context.observation) == var_to_bytes(last), "physical automatic native observation survives exact random seek")
	suite.assert_equal(GameState.profile_runtime_service().snapshot(), profile_before, "recording persistence leaves gameplay Profile unchanged")
	recorder.store().set_fault_injector(Callable())
	var before: Dictionary = recorder.snapshot()
	suite.assert_true(not player.advance_action_frame({"movement": Vector2(INF, 0)}), "malformed production intent is rejected")
	suite.assert_equal(recorder.snapshot(), before, "rejected native frame adds no recording observation")
	recorder.store().set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	suite.assert_true(player.advance_action_frame(), "storage failure cannot prevent accepted gameplay")
	suite.assert_true(not recorder.flush().ok and not recorder.snapshot().active, "failed recording is explicit without altering gameplay")
	recorder.store().set_fault_injector(Callable())
	suite.assert_true(player.advance_action_frame(), "gameplay continues after recording failure")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	suite.finish(get_tree())


func _freeze(main: Node) -> void:
	main.set_process(false)
	main.get_node("RunRuntimeHost").set_process(false)
	main.get_node("DungeonFlow").set_process(false)
	main.get_node("TutorialFlow").set_process(false)
	main.get_node("NarrativeFlow").set_physics_process(false)
	var player: Node = main.get_node("CombatRoom01/Player")
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
