extends "res://tools/p15/native_performance_probe.gd"


func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	suite = Suite.new()
	var registry := Registry.new()
	var loaded: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	_check(not loaded.has_blocking_errors(), "authoritative lifecycle content loads")
	var content := Content.snapshot(registry)
	var catalog: RefCounted = Factory.from_registry(registry).context.catalog
	var save := Save.new()
	_check(save.configure(GameState.save_path.get_base_dir().path_join("plane_walker/save"), "0.4.0-dev", content).ok and save.enable_meta_profile(catalog).ok and save.save_profile("slot_1", "base", {"meta_profile_state": Fixtures.profile(catalog)}).ok, "physical lifecycle Profile fixture persists")
	main = Main.instantiate()
	add_child(main)
	player = main.get_node("CombatRoom01/Player")
	host = main.get_node("RunRuntimeHost")
	var initial: Dictionary = player.full_player_replay_snapshot()
	_check(not initial.is_empty(), "real Main exposes complete initial Player state")
	_check(not player.can_process() and not player.time_manager.can_process() and not player.rewind_recorder.can_process(), "inactive CombatRoom suspends Player and authoritative clocks before the first yield")
	await get_tree().process_frame
	_assert_snapshot(initial, "first Hub yield cannot advance hidden Player")
	OS.set_environment("PLANEWALKER_PERFORMANCE_HUB_FRAMES", "12")
	await _hub()
	_check(report.hub.visited_functions == 9 and report.hub.frames == 12, "real Hub visits all nine functions and twelve scheduler frames")
	_assert_snapshot(initial, "real Hub navigation preserves every Player state byte")
	for waits: int in [12, 120]:
		await _wait_physics(waits)
		_assert_snapshot(initial, "Hub preserves every Player state byte after %d physics frames" % waits)
	_check(main._launch_run({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "accelerate"], "difficulty": "normal", "seed": 4}, false, true), "real Main launches the authored Run")
	var choices: Array = host.route_choices()
	var selected: Dictionary = {}
	for candidate: Dictionary in choices:
		if candidate.room_type in ["combat", "elite"]:
			selected = candidate
			break
	_check(not selected.is_empty(), "authored initial route includes a real encounter")
	if not selected.is_empty():
		_check(host.select_route(StringName(selected.edge_id), int(host.runtime_snapshot().revision)).ok, "production route activates a real encounter")
		main.get_node("DungeonFlow").refresh(true)
		main.get_node("NarrativeFlow").close()
		host.set_dungeon_selection_safety(false)
		_check(player.can_process(), "activated CombatRoom resumes ordinary Player physics")
		await _assert_automatic_advance("native encounter accepts automatic Player frames")
		var active_mode: Node.ProcessMode = player.process_mode
		host.set_dungeon_selection_safety(true)
		_check(not player.can_process(), "route selection suspends the physical Player")
		var selection: Dictionary = player.full_player_replay_snapshot()
		await _wait_physics(12)
		_assert_snapshot(selection, "route selection preserves the complete Player state")
		host.set_dungeon_selection_safety(false)
		_check(player.process_mode == active_mode and player.can_process(), "selection closure restores the active Player processing mode")
		await _assert_automatic_advance("selection closure resumes ordinary Player physics")
		main._pause_run()
		_check(get_tree().paused and not player.can_process(), "production pause suspends the active Player")
		var paused: Dictionary = player.full_player_replay_snapshot()
		await _wait_physics(12)
		_assert_snapshot(paused, "production pause preserves the complete Player state")
		main._resume_run()
		_check(not get_tree().paused and player.can_process(), "production resume restores active Player processing")
		await _assert_automatic_advance("production resume accepts ordinary Player frames")
	get_tree().paused = false
	await _dispose()
	suite.finish(get_tree())


func _assert_snapshot(expected: Dictionary, message: String) -> void:
	_check(var_to_bytes(player.full_player_replay_snapshot()) == var_to_bytes(expected), message)


func _wait_physics(frames: int) -> void:
	for _frame: int in range(frames):
		await get_tree().physics_frame
		await get_tree().process_frame


func _assert_automatic_advance(message: String) -> void:
	var before := int(player.priority_arbitration_snapshot().frame)
	await _wait_physics(3)
	_check(int(player.priority_arbitration_snapshot().frame) > before, message)
