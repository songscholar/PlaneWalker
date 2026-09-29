extends Node

const MainScene := preload("res://scenes/main.tscn")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class LoadoutSpy:
	extends Node

	var configure_calls: int = 0
	var received_configs: Array[Dictionary] = []

	func configure_loadout(config: Dictionary) -> bool:
		configure_calls += 1
		received_configs.append(config)
		return true


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
	var actual_player: Node = host.get("_player")
	var loadout_spy := LoadoutSpy.new()
	host.set("_player", loadout_spy)
	var caller_config := _config()
	var started = host.call("start_run", caller_config)
	suite.assert_true(started.ok, "host starts one run")
	var snapshot: Dictionary = host.call("runtime_snapshot")
	suite.assert_equal(loadout_spy.configure_calls, 1, "host applies the accepted loadout exactly once per run")
	if not loadout_spy.received_configs.is_empty():
		suite.assert_equal(loadout_spy.received_configs[0], snapshot.get("config", {}), "host applies authoritative snapshot config")
	caller_config["weapon_id"] = "bow"
	(caller_config["enabled_time_skills"] as Array)[0] = "rift"
	if not loadout_spy.received_configs.is_empty():
		suite.assert_equal(str(loadout_spy.received_configs[0].get("weapon_id", "")), "sword", "caller weapon mutation cannot alter Player input")
		suite.assert_equal(loadout_spy.received_configs[0].get("enabled_time_skills", []), ["stop", "rewind"], "caller ability mutation cannot alter Player input")
		loadout_spy.received_configs[0]["weapon_id"] = "forged"
		(loadout_spy.received_configs[0]["enabled_time_skills"] as Array).append("forged")
	var isolated_snapshot: Dictionary = host.call("runtime_snapshot")
	suite.assert_equal(str(isolated_snapshot.get("config", {}).get("weapon_id", "")), "sword", "Player input mutation cannot alter authority")
	suite.assert_equal(isolated_snapshot.get("config", {}).get("enabled_time_skills", []), ["stop", "rewind"], "nested Player input mutation cannot alter authority")
	host.set("_player", actual_player)
	loadout_spy.free()
	suite.assert_true(not str(snapshot.get("run_id", "")).is_empty(), "host exposes authoritative run id")
	suite.assert_equal(int(snapshot.get("phase", -1)), RunPhaseScript.Value.COMBAT_ACTIVE, "host begins the first room")
	suite.assert_equal(host.call("room_plan").size(), 5, "host owns the five-room plan")
	suite.assert_true(host.call("encounter_catalog") != null, "host exposes the shared encounter catalog")
	var room := main.get_node("CombatRoom01")
	suite.assert_true(room.get("_room_runtime") != null, "room controller receives the host-owned RoomRuntime")

	var before_tick: Dictionary = host.call("runtime_snapshot")
	host.call("_process", 1.25)
	var after_tick: Dictionary = host.call("runtime_snapshot")
	suite.assert_equal(
		int(after_tick.get("run_time_ms", 0)) - int(before_tick.get("run_time_ms", 0)),
		1250,
		"host process advances the authoritative run clock"
	)
	var projector: RefCounted = host.get("_projector")
	var view_state: Dictionary = projector.call("latest_view_state")
	suite.assert_equal(
		int(view_state.get("run_time_ms", -1)),
		int(after_tick.get("run_time_ms", 0)),
		"HUD projection reads the authoritative snapshot clock"
	)

	suite.assert_true(host.call("pause_run").ok, "host pauses the active run")
	var paused_time_ms := int((host.call("runtime_snapshot") as Dictionary).get("run_time_ms", 0))
	host.call("_process", 0.5)
	suite.assert_equal(
		int((host.call("runtime_snapshot") as Dictionary).get("run_time_ms", 0)),
		paused_time_ms,
		"paused host process does not advance the authoritative run clock"
	)
	suite.assert_true(host.call("resume_run").ok, "host resumes after the clock assertion")

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
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
	}
