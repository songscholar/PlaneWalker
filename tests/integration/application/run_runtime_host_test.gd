extends Node

const MainScene := preload("res://scenes/main.tscn")
const EnemyChaserScene := preload("res://scenes/enemies/enemy_chaser.tscn")
const EnemyProjectileScene := preload("res://scenes/enemies/enemy_projectile.tscn")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class LoadoutSpy:
	extends Node

	var configure_run_calls: int = 0
	var configure_calls: int = 0
	var received_run_ids: Array[String] = []
	var received_configs: Array[Dictionary] = []
	var call_order: Array[String] = []

	func configure_run(run_id: StringName) -> bool:
		configure_run_calls += 1
		received_run_ids.append(str(run_id))
		call_order.append("configure_run")
		return true

	func configure_loadout(config: Dictionary) -> bool:
		configure_calls += 1
		received_configs.append(config)
		call_order.append("configure_loadout")
		return true


class RoomProcessProbe:
	extends Node

	var ticks: int = 0

	func _process(_delta: float) -> void:
		ticks += 1


class TerminalFacade:
	extends RefCounted

	var state: Dictionary = {}

	func snapshot() -> Dictionary:
		return state.duplicate(true)

	func advance_time(_delta: float) -> Variant:
		return null


class TerminalOrderRecorder:
	extends RefCounted

	var events: Array[String] = []

	func record_time_end(skill_id: StringName, _context: Dictionary) -> void:
		events.append("end:%s" % str(skill_id))

	func record_run_end(_run_id: String, _result: Dictionary, _revision: int) -> void:
		events.append("run_ended")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	await _assert_main_gameplay_pause_boundary(suite)
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
	suite.assert_equal(loadout_spy.configure_run_calls, 1, "host injects one authoritative run id per run")
	suite.assert_equal(loadout_spy.configure_calls, 1, "host applies the accepted loadout exactly once per run")
	suite.assert_equal(loadout_spy.call_order, ["configure_run", "configure_loadout"], "host installs run identity before loadout reset signals")
	if not loadout_spy.received_run_ids.is_empty():
		suite.assert_equal(loadout_spy.received_run_ids[0], str(snapshot.get("run_id", "")), "host injects the facade-authoritative run id")
	if not loadout_spy.received_configs.is_empty():
		var player_config: Dictionary = loadout_spy.received_configs[0]
		suite.assert_equal(str(player_config.get("weapon_id", "")), str(snapshot.get("config", {}).get("weapon_id", "")), "host applies the authoritative weapon id")
		suite.assert_equal(player_config.get("enabled_time_skills", []), snapshot.get("config", {}).get("enabled_time_skills", []), "host applies the authoritative time loadout")
		suite.assert_equal(str(player_config.get("weapon_profile", {}).get("id", "")), "sword_m1_v1", "host forwards the policy-accepted weapon profile")
	caller_config["weapon_id"] = "bow"
	(caller_config["enabled_time_skills"] as Array)[0] = "rift"
	if not loadout_spy.received_configs.is_empty():
		suite.assert_equal(str(loadout_spy.received_configs[0].get("weapon_id", "")), "sword", "caller weapon mutation cannot alter Player input")
		suite.assert_equal(loadout_spy.received_configs[0].get("enabled_time_skills", []), ["stop", "rewind"], "caller ability mutation cannot alter Player input")
		loadout_spy.received_configs[0]["weapon_id"] = "forged"
		(loadout_spy.received_configs[0]["enabled_time_skills"] as Array).append("forged")
		(loadout_spy.received_configs[0]["weapon_profile"] as Dictionary)["id"] = "forged_profile"
		var authoritative_loadout: Dictionary = host.get("_facade").call("active_loadout")
		suite.assert_equal(str(authoritative_loadout.get("weapon_profile", {}).get("id", "")), "sword_m1_v1", "Player profile mutation cannot alter facade authority")
	var isolated_snapshot: Dictionary = host.call("runtime_snapshot")
	suite.assert_equal(str(isolated_snapshot.get("config", {}).get("weapon_id", "")), "sword", "Player input mutation cannot alter authority")
	suite.assert_equal(isolated_snapshot.get("config", {}).get("enabled_time_skills", []), ["stop", "rewind"], "nested Player input mutation cannot alter authority")
	host.set("_player", actual_player)
	loadout_spy.free()

	var actual_started = host.call("start_run", _config())
	suite.assert_true(actual_started.ok, "host starts a run through the real Player authority path")
	var actual_snapshot: Dictionary = host.call("runtime_snapshot")
	var actual_run_id := str(actual_snapshot.get("run_id", ""))
	var actual_health: Node = actual_player.get_node("HealthComponent")
	var actual_rewind: Node = actual_player.get_node("RewindRecorder")
	suite.assert_equal(str(actual_player.current_run_id()), actual_run_id, "Player receives the host run id")
	suite.assert_equal(str(actual_health.irreversible_ledger_snapshot().get("run_id", "")), actual_run_id, "Health ledger receives the host run id")
	suite.assert_equal(str(actual_rewind.current_run_id()), actual_run_id, "Rewind receives the host run id")
	actual_health.current_hp = actual_health.max_hp
	var actual_loss: RefCounted = actual_health.lose_health_irreversible(
		7.0,
		&"host_run_fixture",
		901,
		11,
		StringName(actual_run_id)
	)
	suite.assert_true(actual_loss != null and not actual_loss.is_prevented(), "real run records an irreversible claim before rollover")
	actual_rewind.call("_record_snapshot")
	suite.assert_true(actual_rewind.has_snapshot(), "real run owns rewind history before rollover")

	var replacement_started = host.call("start_run", _config())
	suite.assert_true(replacement_started.ok, "host starts a replacement run through the real Player")
	var replacement_snapshot: Dictionary = host.call("runtime_snapshot")
	var replacement_run_id := str(replacement_snapshot.get("run_id", ""))
	suite.assert_true(replacement_run_id != actual_run_id, "replacement run receives a distinct identity")
	suite.assert_equal(str(actual_player.current_run_id()), replacement_run_id, "Player advances to the replacement run id")
	suite.assert_equal(str(actual_health.irreversible_ledger_snapshot().get("run_id", "")), replacement_run_id, "Health ledger advances to the replacement run id")
	suite.assert_equal(str(actual_rewind.current_run_id()), replacement_run_id, "Rewind advances to the replacement run id")
	suite.assert_equal(
		actual_health.hp_loss_state(),
		{"irreversible_hp_loss_total": 0.0, "revision": 0},
		"replacement run starts with an empty irreversible ledger"
	)
	suite.assert_true(not actual_rewind.has_snapshot(), "replacement run invalidates prior-run rewind history")

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
	_assert_terminal_time_cleanup_order(suite, main, host, actual_player)

	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _assert_main_gameplay_pause_boundary(suite) -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var room: Node = main.get_node("CombatRoom01")
	room.set("spawn_warning_duration", 0.0)
	main.call("_start_new_run")
	await get_tree().process_frame
	await get_tree().process_frame
	_suite_process_mode_assertions(suite, room)

	var player: Node2D = room.get_node("Player") as Node2D
	var enemy := EnemyChaserScene.instantiate()
	var projectile := EnemyProjectileScene.instantiate()
	var probe := RoomProcessProbe.new()
	room.get_node("Enemies").add_child(enemy)
	room.add_child(projectile)
	room.add_child(probe)
	enemy.global_position = player.global_position + Vector2(300.0, 0.0)
	enemy.target = player
	enemy.attack_range = 0.0
	projectile.global_position = Vector2(300.0, 140.0)
	projectile.direction = Vector2.RIGHT
	projectile.speed = 180.0
	projectile.arm_time = 0.0
	projectile.lifetime = 5.0
	await get_tree().create_timer(0.05).timeout

	get_tree().paused = true
	var enemy_position_before: Vector2 = enemy.global_position
	var projectile_position_before: Vector2 = projectile.global_position
	var probe_ticks_before := probe.ticks
	await get_tree().create_timer(0.10, true).timeout
	suite.assert_equal(enemy.global_position, enemy_position_before, "paused Main freezes the real enemy")
	suite.assert_equal(projectile.global_position, projectile_position_before, "paused Main freezes the real projectile")
	suite.assert_equal(probe.ticks, probe_ticks_before, "paused Main freezes ordinary room children")

	get_tree().paused = false
	await get_tree().create_timer(0.10).timeout
	suite.assert_true(enemy.global_position != enemy_position_before, "resumed Main advances the real enemy")
	suite.assert_true(projectile.global_position != projectile_position_before, "resumed Main advances the real projectile")
	suite.assert_true(probe.ticks > probe_ticks_before, "resumed Main advances ordinary room children")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _suite_process_mode_assertions(suite, room: Node) -> void:
	suite.assert_equal(room.process_mode, Node.PROCESS_MODE_PAUSABLE, "active Main keeps CombatRoom01 pausable")


func _assert_terminal_time_cleanup_order(suite, main: Node, host: Node, player: Node) -> void:
	var main_run_end := Callable(main, "_on_run_ended")
	if EventBus.run_ended.is_connected(main_run_end):
		EventBus.run_ended.disconnect(main_run_end)
	var recorder := TerminalOrderRecorder.new()
	EventBus.time_skill_ended.connect(recorder.record_time_end)
	EventBus.run_ended.connect(recorder.record_run_end)
	var facade := TerminalFacade.new()

	_activate_terminal_time_effects(suite, player)
	facade.state = _terminal_snapshot("terminal-order-victory", RunPhaseScript.Value.VICTORY, "victory")
	host.set("_facade", facade)
	host.set("_active_run_id", "terminal-order-victory")
	host.set("_published_run_id", "terminal-order-victory")
	host.set("_ended_run_id", "")
	host.call("_on_terminal_committed", {"result": "victory"}, 10)
	_assert_terminal_order(suite, recorder.events, "terminal_committed")
	var victory_events := recorder.events.duplicate()
	host.call("_on_terminal_committed", {"result": "victory"}, 10)
	suite.assert_equal(recorder.events, victory_events, "duplicate terminal commit adds no cleanup or run facts")
	player.cancel_active_time_effects(&"test_cleanup")

	recorder.events.clear()
	player.reset_runtime_state()
	_activate_terminal_time_effects(suite, player)
	facade.state = _terminal_snapshot("terminal-order-failure", RunPhaseScript.Value.DEFEAT, "runtime_error")
	host.set("_active_run_id", "terminal-order-failure")
	host.set("_published_run_id", "terminal-order-failure")
	host.set("_ended_run_id", "")
	host.call("_on_runtime_failed", {"result": "runtime_error"})
	_assert_terminal_order(suite, recorder.events, "runtime_failed")
	var failure_events := recorder.events.duplicate()
	host.call("_on_runtime_failed", {"result": "runtime_error"})
	suite.assert_equal(recorder.events, failure_events, "duplicate runtime failure adds no cleanup or run facts")
	player.cancel_active_time_effects(&"test_cleanup")

	if EventBus.time_skill_ended.is_connected(recorder.record_time_end):
		EventBus.time_skill_ended.disconnect(recorder.record_time_end)
	if EventBus.run_ended.is_connected(recorder.record_run_end):
		EventBus.run_ended.disconnect(recorder.record_run_end)


func _activate_terminal_time_effects(suite, player: Node) -> void:
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 0.0
	manager.time_stop_duration = 10.0
	manager.time_rift_duration = 10.0
	manager.time_accelerate_duration = 10.0
	manager.energy = manager.max_energy
	suite.assert_true(manager.try_time_stop(), "terminal fixture starts Stop")
	suite.assert_true(manager.try_time_rift(player.global_position), "terminal fixture starts Rift")
	suite.assert_true(manager.try_time_accelerate(), "terminal fixture starts Accelerate")


func _terminal_snapshot(run_id: String, phase: int, outcome: String) -> Dictionary:
	return {
		"run_id": run_id,
		"revision": 10,
		"phase": phase,
		"current_room": 5,
		"result": {"result": outcome},
		"stats": {},
		"build": {},
	}


func _assert_terminal_order(suite, events: Array[String], label: String) -> void:
	suite.assert_equal(events.size(), 4, "%s publishes three time ends plus run_ended" % label)
	var run_end_index := events.find("run_ended")
	suite.assert_true(run_end_index >= 0, "%s publishes run_ended" % label)
	for skill_id: String in ["time_stop", "time_rift", "time_accelerate"]:
		var event_name := "end:%s" % skill_id
		suite.assert_equal(events.count(event_name), 1, "%s ends %s exactly once" % [label, skill_id])
		var end_index := events.find(event_name)
		suite.assert_true(end_index >= 0 and end_index < run_end_index, "%s ends %s before run_ended" % [label, skill_id])


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
