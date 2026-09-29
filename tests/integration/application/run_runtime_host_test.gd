extends Node

const MainScene := preload("res://scenes/main.tscn")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var host := main.get_node_or_null("RunRuntimeHost")
	suite.assert_true(host != null, "main provides RunRuntimeHost")
	suite.assert_true(main.get_node_or_null("RuntimeV2Adapter") == null, "main has no legacy adapter node")
	if host == null:
		main.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return

	suite.assert_equal(host.process_mode, Node.PROCESS_MODE_ALWAYS, "runtime host remains active while paused")
	main.get_node("CombatRoom01").set("spawn_warning_duration", 0.0)
	var started = host.call("start_run", _config())
	suite.assert_true(started.ok, "host starts one run")
	var snapshot: Dictionary = host.call("runtime_snapshot")
	suite.assert_true(not str(snapshot.get("run_id", "")).is_empty(), "host exposes authoritative run id")
	suite.assert_equal(int(snapshot.get("phase", -1)), RunPhaseScript.Value.COMBAT_ACTIVE, "host begins the first room")
	suite.assert_equal(host.call("room_plan").size(), 5, "host owns the five-room plan")
	suite.assert_true(host.call("encounter_catalog") != null, "host exposes the shared encounter catalog")
	var room := main.get_node("CombatRoom01")
	suite.assert_true(room.get("_room_runtime") != null, "room controller receives the host-owned RoomRuntime")

	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["time_stop", "time_rewind"],
		"difficulty": "normal",
		"seed": 20260929,
	}
