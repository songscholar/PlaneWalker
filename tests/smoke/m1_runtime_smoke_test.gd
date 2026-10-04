extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const MainScene := preload("res://scenes/main.tscn")

const FIXED_SEED := 20260929


class RewardSignalCounter:
	extends RefCounted

	var count: int = 0
	var payloads: Array[Dictionary] = []

	func record(_run_id: String, payload: Dictionary, _revision: int) -> void:
		count += 1
		payloads.append(payload.duplicate(true))


class RunResultSignalCounter:
	extends RefCounted

	var count: int = 0
	var payloads: Array[Dictionary] = []

	func record(_run_id: String, payload: Dictionary, _revision: int) -> void:
		count += 1
		payloads.append(payload.duplicate(true))


var _original_save_path: String
var _original_persistent: Dictionary
var _test_storage_root: String


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_original_save_path = GameState.save_path
	_original_persistent = GameState.persistent.duplicate(true)
	_test_storage_root = _isolated_storage_root("m1_runtime_smoke")
	GameState.save_path = _test_storage_root.path_join("legacy.json")
	GameState.reset_persistent_data(true)

	var main: Node = MainScene.instantiate()
	var room: Node = main.get_node("CombatRoom01")
	suite.assert_equal(_legacy_gameplay_view_count(room), 0, "main scene contains no legacy HUD or selections")
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var quick_start_config: Dictionary = main.call("_build_run_config")
	suite.assert_equal(quick_start_config.get("milestone"), "LAUNCH", "production Quick Start selects the complete Launch run")
	suite.assert_equal(quick_start_config.get("character_id"), "wanderer", "Quick Start remains Wanderer")
	suite.assert_equal(quick_start_config.get("weapon_id"), "sword", "Quick Start remains Sword")
	suite.assert_equal(quick_start_config.get("enabled_time_skills"), ["stop", "rewind"], "Quick Start remains Stop plus Rewind")
	suite.assert_true(not main.get_node("CandidateLabLayer/CandidateLoadoutPanel").visible, "candidate route starts isolated from M1")

	var host: Node = main.get_node_or_null("RunRuntimeHost")
	if host == null:
		suite.assert_true(false, "main scene provides RunRuntimeHost")
		await _cleanup(main, null, null)
		suite.finish(get_tree())
		return

	suite.assert_true(main.get_node_or_null("RuntimeV2Adapter") == null, "main scene contains no legacy runtime adapter")
	suite.assert_true(main.get_node_or_null("LegacyRunAdapter") == null, "main scene contains no legacy adapter node")
	suite.assert_equal(host.process_mode, Node.PROCESS_MODE_ALWAYS, "runtime host stays active while paused")
	suite.assert_equal(
		int((host.call("runtime_snapshot") as Dictionary).get("phase", -1)),
		RunPhaseScript.Value.HUB,
		"runtime host boots into the authoritative hub"
	)
	suite.assert_equal(_legacy_gameplay_view_count(room), 0, "runtime boot keeps legacy gameplay UI absent")
	var camera := room.get_node_or_null("PixelCanvasCamera") as Camera2D
	suite.assert_true(camera != null and camera.enabled, "M1 runtime keeps the pixel-canvas camera active")
	if camera != null:
		suite.assert_equal(camera.position, Vector2(640.0, 360.0), "M1 runtime centers the 1280x720 greybox")
		suite.assert_equal(camera.zoom, Vector2(0.5, 0.5), "M1 runtime renders the greybox at half zoom")

	var panel := host.get_node_or_null("ChoiceLayer/ChoicePanelV2") as Control
	suite.assert_true(panel != null, "runtime host creates the unified choice panel")
	if panel == null:
		await _cleanup(main, null, null)
		suite.finish(get_tree())
		return

	var reward_counter := RewardSignalCounter.new()
	var result_counter := RunResultSignalCounter.new()
	var profile_before: Dictionary = GameState.profile_runtime_service().snapshot()
	var persistent_before: Dictionary = GameState.persistent.duplicate(true)
	EventBus.reward_selected.connect(reward_counter.record)
	EventBus.run_ended.connect(result_counter.record)
	room.set("spawn_warning_duration", 0.0)
	room.visible = true
	room.process_mode = Node.PROCESS_MODE_INHERIT
	var started = host.call("start_run", {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": FIXED_SEED,
	})
	suite.assert_true(started.ok, "host starts the fixed-seed M1 run")

	_assert_authored_runtime(suite, room, host)
	var started_snapshot: Dictionary = host.call("runtime_snapshot")
	suite.assert_equal(started_snapshot["phase"], RunPhaseScript.Value.COMBAT_ACTIVE, "fixed-seed run enters room one")
	suite.assert_equal(started_snapshot["run_seed"], FIXED_SEED, "authoritative runtime uses the fixed seed")

	var expected_reward_kinds: Array[String] = ["starter", "reinforcement", "talent", "contract"]
	var expected_encounter_ids: Array[String] = ["m1_room_01", "m1_room_02", "m1_room_03", "m1_room_04_elite"]
	var expected_waves: Array = [
		[["chaser"]],
		[["chaser", "shooter"]],
		[["chaser", "shooter"], ["tank"]],
		[["tank"]],
	]
	for room_number: int in range(1, 5):
		await _wait_for_room_phase(host, RunPhaseScript.Value.COMBAT_ACTIVE)
		var active_snapshot: Dictionary = host.call("runtime_snapshot")
		suite.assert_equal(active_snapshot["current_room"], room_number, "authoritative runtime enters room %d" % room_number)
		var room_definition: Dictionary = (host.call("room_plan") as Array)[room_number - 1]
		suite.assert_equal(
			str(room_definition.get("reward_kind", "")),
			expected_reward_kinds[room_number - 1],
			"room %d opens the expected reward kind" % room_number
		)
		suite.assert_equal(
			str(room_definition.get("encounter_id", "")),
			expected_encounter_ids[room_number - 1],
			"room %d uses the authored encounter id" % room_number
		)
		suite.assert_equal(active_snapshot["phase"], RunPhaseScript.Value.COMBAT_ACTIVE, "room %d enters combat" % room_number)

		await _play_authored_waves(suite, room, expected_waves[room_number - 1], room_number)
		var offer_snapshot: Dictionary = host.call("runtime_snapshot")
		var offer: Dictionary = offer_snapshot["open_offer"]
		suite.assert_true(not offer.is_empty(), "room %d opens one offer" % room_number)
		suite.assert_true(panel.visible, "room %d shows the unified panel" % room_number)
		var buttons := _option_buttons(panel)
		suite.assert_true(not buttons.is_empty(), "room %d renders a valid option" % room_number)
		if buttons.is_empty():
			continue
		buttons[0].pressed.emit()
		suite.assert_equal(reward_counter.count, room_number, "room %d emits one compatibility reward fact" % room_number)
		suite.assert_true(not panel.visible, "room %d closes the unified panel after selection" % room_number)
		suite.assert_equal(
			int((host.call("runtime_snapshot") as Dictionary).get("current_room", 0)),
			room_number + 1,
			"room %d selection advances the authoritative runtime" % room_number
		)

	await _wait_for_room_phase(host, RunPhaseScript.Value.BOSS_ACTIVE)
	var boss_snapshot: Dictionary = host.call("runtime_snapshot")
	suite.assert_equal(boss_snapshot["current_room"], 5, "authoritative runtime enters the boss room")
	suite.assert_equal(boss_snapshot["phase"], RunPhaseScript.Value.BOSS_ACTIVE, "room five enters boss phase")
	suite.assert_true(boss_snapshot["open_offer"].is_empty(), "boss room starts without an offer")
	suite.assert_equal((host.call("room_plan") as Array)[4]["encounter_id"], "m1_room_05_boss", "room five uses the boss encounter id")

	var spawned_bosses := await _wait_for_spawned_enemies(room)
	suite.assert_equal(spawned_bosses.size(), 1, "boss room spawns one boss actor")
	if not spawned_bosses.is_empty():
		suite.assert_equal(spawned_bosses[0].get_meta("encounter_enemy_id", ""), "chrono_warden", "boss spawn identity comes from the catalog")
	await _defeat_spawned_enemies(spawned_bosses)
	var final_snapshot: Dictionary = host.call("runtime_snapshot")
	suite.assert_equal(final_snapshot["phase"], RunPhaseScript.Value.VICTORY, "boss defeat enters victory")
	suite.assert_true(final_snapshot["open_offer"].is_empty(), "boss victory opens no offer")
	suite.assert_equal(reward_counter.count, 4, "five-room run emits exactly four compatibility reward facts")
	suite.assert_equal(final_snapshot["current_room"], 5, "authoritative snapshot finishes on room five")
	suite.assert_equal(final_snapshot["consumed_offer_ids"].size(), 4, "authoritative snapshot consumes four offers")
	var build: Dictionary = final_snapshot["build"]
	suite.assert_true(_selected_count(build) > 0, "authoritative snapshot contains a non-empty build")
	suite.assert_equal(result_counter.count, 1, "boss victory emits one terminal result")
	if not result_counter.payloads.is_empty():
		var emitted_result: Dictionary = result_counter.payloads[0]
		suite.assert_equal(emitted_result.get("result", ""), "floor_cleared", "victory event exposes the persisted result vocabulary")
		suite.assert_equal(emitted_result.get("current_room", 0), 5, "victory event records the final room")
		suite.assert_equal(_summary_selected_count(emitted_result), _selected_count(build), "victory event build agrees with the authoritative snapshot")
	suite.assert_equal(GameState.profile_runtime_service().snapshot(), profile_before, "explicit M1 laboratory combat cannot settle an unissued production launch")
	suite.assert_equal(GameState.persistent, persistent_before, "M1 terminal facts preserve the canonical production Profile mirror")

	await _cleanup(main, reward_counter, result_counter)
	suite.finish(get_tree())


func _assert_authored_runtime(suite, room: Node, host: Node) -> void:
	suite.assert_true(bool(room.get("_authored_runtime_enabled")), "M1 room controller enables authored encounters")
	var runtime_value: Variant = room.get("_room_runtime")
	suite.assert_true(runtime_value is Node, "M1 room controller receives the authoritative RoomRuntime")
	if runtime_value is Node:
		var runtime_snapshot: Dictionary = (runtime_value as Node).call("snapshot")
		suite.assert_true(bool(runtime_snapshot.get("configured", false)), "M1 RoomRuntime is configured")
	suite.assert_equal(host.call("room_plan").size(), 5, "host owns the shared five-room plan")
	suite.assert_true(room.get("_encounter_catalog") == host.call("encounter_catalog"), "room controller and host share one catalog instance")


func _play_authored_waves(suite, room: Node, expected_waves: Array, room_number: int) -> void:
	for wave_index: int in range(expected_waves.size()):
		var spawned_enemies := await _wait_for_spawned_enemies(room)
		var expected_ids: Array = expected_waves[wave_index]
		suite.assert_equal(spawned_enemies.size(), expected_ids.size(), "room %d wave %d spawns the authored actor count" % [room_number, wave_index + 1])
		var actual_ids: Array[String] = []
		for enemy: Node in spawned_enemies:
			actual_ids.append(str(enemy.get_meta("encounter_enemy_id", "")))
		suite.assert_equal(actual_ids, expected_ids, "room %d wave %d spawns authored enemy identities" % [room_number, wave_index + 1])
		if room_number == 4 and not spawned_enemies.is_empty():
			suite.assert_equal(spawned_enemies[0].get_meta("encounter_mechanism_ids", []), ["overload_pulse"], "room four carries the overload pulse mechanism")
			suite.assert_true(spawned_enemies[0].is_in_group("elite_enemies"), "room four activates the Tank elite runtime")
		await _defeat_spawned_enemies(spawned_enemies)


func _selected_count(build: Dictionary) -> int:
	var count := 0
	for field: String in ["items", "blessings", "curses", "talents"]:
		count += build.get(field, []).size()
	return count


func _summary_selected_count(summary: Dictionary) -> int:
	return (
		summary.get("rewards", []).size()
		+ summary.get("blessings", []).size()
		+ summary.get("curses", []).size()
		+ summary.get("talent_choices", []).size()
	)


func _wait_for_room_phase(host: Node, expected_phase: int) -> void:
	for _frame: int in range(30):
		if int((host.call("runtime_snapshot") as Dictionary).get("phase", -1)) == expected_phase:
			return
		await get_tree().process_frame


func _wait_for_spawned_enemies(room: Node) -> Array[Node]:
	var enemies_root := room.get_node("Enemies")
	for _frame: int in range(30):
		var children: Array[Node] = []
		for child: Node in enemies_root.get_children():
			if not child.is_queued_for_deletion():
				children.append(child)
		if not children.is_empty():
			return children
		await get_tree().process_frame
	return []


func _defeat_spawned_enemies(enemies: Array[Node]) -> void:
	for enemy: Node in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		var room := enemy.get_parent().get_parent()
		var runtime: Node = room.get("_room_runtime")
		if runtime != null:
			runtime.call("report_entity_died", enemy)
		enemy.queue_free()
	await get_tree().process_frame


func _option_buttons(panel: Control) -> Array[Button]:
	var buttons: Array[Button] = []
	var container := panel.get_node("SafeArea/Center/PanelRoot/Content/OptionsContainer")
	for child: Node in container.get_children():
		if child is Button:
			buttons.append(child as Button)
	return buttons


func _legacy_gameplay_view_count(room: Node) -> int:
	var count := 0
	for view_name: String in ["CombatHUD", "RewardSelection", "CurseSelection", "EventSelection"]:
		if room.get_node_or_null(view_name) != null:
			count += 1
	return count


func _cleanup(
	main: Node,
	reward_counter: RewardSignalCounter,
	result_counter: RunResultSignalCounter
) -> void:
	get_tree().paused = false
	if reward_counter != null and EventBus.reward_selected.is_connected(reward_counter.record):
		EventBus.reward_selected.disconnect(reward_counter.record)
	if result_counter != null and EventBus.run_ended.is_connected(result_counter.record):
		EventBus.run_ended.disconnect(result_counter.record)
	if main != null and is_instance_valid(main):
		main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	GameState.reset_persistent_data(true)
	GameState.save_path = _original_save_path
	GameState.persistent = _original_persistent.duplicate(true)
	_remove_tree(_test_storage_root)


func _isolated_storage_root(test_name: String) -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("%s_%d_%d" % [test_name, OS.get_process_id(), Time.get_ticks_usec()])


func _remove_tree(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			_remove_tree(path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)
