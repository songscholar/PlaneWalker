extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Phase := preload("res://scripts/application/run_phase.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 4}
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	suite.assert_true(main._launch_run(config, false, true), "actual Main opens a continuous native recording")
	await _enter_native_room(main, suite)
	var recorder: Node = main.get_node("NativeRunReplayRecorder")
	var before: Dictionary = recorder.snapshot()
	suite.assert_true(not recorder.finish("COMPLETE").ok and recorder.snapshot() == before, "live run cannot be explicitly labeled complete")
	var player: Node = main.get_node("CombatRoom01/Player")
	player.health.lose_health(100000)
	suite.assert_equal(main.get_node("RunRuntimeHost").runtime_snapshot().phase, Phase.Value.DEFEAT, "real Health death publishes the native terminal state")
	suite.assert_true(recorder.observe_transition().ok, "actual terminal publication finalizes the automatic recording")
	var rows: Array = recorder.store().rows()
	suite.assert_true(rows.size() == 1 and rows[0].status == "COMPLETE" and not recorder.snapshot().active, "uninterrupted native recording retains explicit complete status")
	var recorded: Dictionary = recorder.store().read(str(rows[0].id), int(rows[0].observation_count) - 1)
	suite.assert_true(recorded.ok and recorded.context.observation.kind == "terminal" and recorded.context.observation.run.phase == Phase.Value.DEFEAT and recorded.context.observation.player.health_state.dead, "durable terminal tape includes actual Run and Player death")
	var settled: Dictionary = main.retry_terminal_settlement()
	suite.assert_true(settled.ok, "actual terminal settlement completes: " + str(settled.code) + " " + str(settled.context))
	suite.assert_true(main.return_to_hub(), "actual completed death flow returns through normal Hub settlement")
	suite.assert_true(main._launch_run(config, false, true), "next native launch can record independently after actual terminal state")
	await _enter_native_room(main, suite)
	suite.assert_true(main.checkpoint_current_run().ok, "interrupted segment retains its actual live combat checkpoint")
	suite.assert_true(recorder.finish("INTERRUPTED").ok, "explicit interruption flushes the live launch without claiming completion")
	await _dispose(main)
	GameState.set("_profile_runtime", null)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	suite.assert_true(main._launch_run(config, false, true), "cold Main resumes the physical live launch: " + str(main.get("_last_launch_rejection")) + " " + str(main.get("_profile_error")))
	_freeze(main)
	recorder = main.get_node("NativeRunReplayRecorder")
	suite.assert_true(recorder.snapshot().active and not recorder.snapshot().complete_eligible and recorder.latest_observation().kind == "resume", "resumed segment explicitly excludes an entire-run completion claim")
	main.get_node("CombatRoom01/Player").health.lose_health(100000)
	suite.assert_true(recorder.observe_transition().ok, "actual resumed terminal publication retains a durable segment")
	rows = recorder.store().rows()
	suite.assert_true(rows.size() == 3 and rows[-1].status == "INTERRUPTED", "a resumed segment remains incomplete even after actual death")
	await _dispose(main)
	suite.finish(get_tree())


func _enter_native_room(main: Node, suite: RefCounted) -> void:
	var host: Node = main.get_node("RunRuntimeHost")
	var choices: Array = host.route_choices()
	var selected: Dictionary = choices[0]
	for choice: Dictionary in choices:
		if choice.room_type == "combat":
			selected = choice
			break
	suite.assert_true(host.select_route(StringName(selected.edge_id), int(host.runtime_snapshot().revision)).ok, "terminal fixture enters an actual native combat room")
	host.set_dungeon_selection_safety(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_freeze(main)


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


func _dispose(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
