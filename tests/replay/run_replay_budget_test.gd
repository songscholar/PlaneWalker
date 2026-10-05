extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Store := preload("res://scripts/replay/run_replay_stream_store.gd")
const PROBE := "res://tools/replay/run_replay_budget_probe.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(PROBE), "retained whole-run budget probe must exist")
	if not ResourceLoader.exists(PROBE):
		suite.finish(get_tree())
		return
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 4}
	suite.assert_true(main._launch_run(config, false, true), "budget samples come from actual production Main")
	var host: Node = main.get_node("RunRuntimeHost")
	var player: Node = main.get_node("CombatRoom01/Player")
	var recorder: Node = main.get_node("NativeRunReplayRecorder")
	main.set_process(false)
	host.set_process(false)
	main.get_node("DungeonFlow").set_process(false)
	main.get_node("TutorialFlow").set_process(false)
	main.get_node("NarrativeFlow").set_physics_process(false)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	for route: Dictionary in host.route_choices():
		if route.room_type == "combat":
			suite.assert_true(host.select_route(StringName(route.edge_id), int(host.runtime_snapshot().revision)).ok, "budget samples include actual native hostiles")
			break
	host.set_dungeon_selection_safety(false)
	player.health.acquire_invulnerability_source(&"budget_fixture")
	var samples: Array[Dictionary] = []
	for frame: int in range(120):
		suite.assert_true(player.advance_action_frame({"movement": Vector2.ZERO, "aim": Vector2.RIGHT}), "actual sample frame commits")
		await get_tree().physics_frame
		samples.append(recorder.latest_observation())
	suite.assert_true(not samples[-1].native.actors.is_empty(), "sample includes production Actor state")
	suite.assert_true(recorder.finish("INTERRUPTED").ok, "native sample remains honestly incomplete")
	var identity: Dictionary = GameState.profile_runtime_service().local_record_storage_identity()
	var storage := Store.new()
	suite.assert_true(storage.configure(recorder.storage_root().path_join("synthetic_budget"), "0.4.0-dev", identity.content_snapshot, identity.profile_id, identity.save_domain).ok, "synthetic budget uses an independent physical store")
	var count := 360
	var configured_count := OS.get_environment("PLANEWALKER_REPLAY_BUDGET_OBSERVATIONS")
	if not configured_count.is_empty():
		count = int(configured_count)
	var probe: RefCounted = load(PROBE).new()
	var before: Dictionary = GameState.profile_runtime_service().snapshot()
	var result: Dictionary = probe.run(storage, samples, count)
	suite.assert_true(result.ok, "complete synthetic storage count fits declared budgets: " + str(result))
	if result.ok:
		suite.assert_equal(result.context.report.observations, count, "retained report counts all requested observations")
		suite.assert_equal(result.context.report.classification, "synthetic_repeated_native_samples", "report distinguishes storage simulation from gameplay")
		suite.assert_equal(storage.rows()[0].status, "INTERRUPTED", "synthetic tape cannot claim complete gameplay")
		var report_path := OS.get_environment("PLANEWALKER_REPLAY_BUDGET_REPORT")
		if not report_path.is_empty():
			DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
			var file := FileAccess.open(report_path, FileAccess.WRITE)
			suite.assert_true(file != null, "budget report path opens")
			if file != null:
				file.store_string(JSON.stringify(result.context.report, "\t"))
				file.close()
		print("REPLAY_BUDGET ", JSON.stringify(result.context.report))
	suite.assert_equal(GameState.profile_runtime_service().snapshot(), before, "storage simulation preserves actual gameplay Profile")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	suite.finish(get_tree())
