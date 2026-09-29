extends Node

const MainScene := preload("res://scenes/main.tscn")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const FIXED_SEED := 20260929


class LifecycleRecorder:
	extends RefCounted

	var run_started_count: int = 0
	var room_started_count: int = 0
	var room_cleared_ids: Array[StringName] = []
	var reward_selected_count: int = 0
	var run_ended_count: int = 0
	var run_started_payloads: Array[Dictionary] = []
	var reward_payloads: Array[Dictionary] = []
	var terminal_payloads: Array[Dictionary] = []
	var event_ids: Array[String] = []

	func record_run_started(run_id: String, snapshot: Dictionary) -> void:
		run_started_count += 1
		run_started_payloads.append(snapshot.duplicate(true))
		_record_event(&"run_started", run_id, "", int(snapshot.get("revision", -1)))
		snapshot["phase"] = 999
		(snapshot.get("config", {}) as Dictionary)["character_id"] = "forged"

	func record_room_started(run_id: String, room_id: StringName, revision: int) -> void:
		room_started_count += 1
		_record_event(&"room_started", run_id, str(room_id), revision)

	func record_room_cleared(run_id: String, room_id: StringName, revision: int) -> void:
		room_cleared_ids.append(room_id)
		_record_event(&"room_cleared", run_id, str(room_id), revision)

	func record_reward_selected(run_id: String, definition: Dictionary, revision: int) -> void:
		reward_selected_count += 1
		reward_payloads.append(definition.duplicate(true))
		_record_event(&"reward_selected", run_id, str(definition.get("id", "")), revision)
		definition["id"] = "forged"

	func record_run_ended(run_id: String, result: Dictionary, revision: int) -> void:
		run_ended_count += 1
		terminal_payloads.append(result.duplicate(true))
		_record_event(&"run_ended", run_id, str(result.get("result", "")), revision)
		result["result"] = "forged"

	func duplicate_event_ids() -> Array[String]:
		var counts: Dictionary = {}
		for event_id: String in event_ids:
			counts[event_id] = int(counts.get(event_id, 0)) + 1
		var duplicates: Array[String] = []
		for event_id: String in counts:
			if int(counts[event_id]) > 1:
				duplicates.append(event_id)
		duplicates.sort()
		return duplicates

	func _record_event(
		kind: StringName,
		run_id: String,
		subject_id: String,
		revision: int
	) -> void:
		event_ids.append("%s|%s|%s|%d" % [str(kind), run_id, subject_id, revision])


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
	_test_storage_root = _isolated_storage_root()
	GameState.save_path = _test_storage_root.path_join("legacy.json")
	GameState.reset_persistent_data(true)

	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var host := main.get_node_or_null("RunRuntimeHost")
	var room := main.get_node_or_null("CombatRoom01")
	var recorder := LifecycleRecorder.new()
	if host == null or room == null:
		suite.assert_true(false, "main provides lifecycle runtime fixtures")
		await _cleanup(main, recorder)
		suite.finish(get_tree())
		return

	_connect_recorder(recorder)
	room.set("spawn_warning_duration", 0.0)
	room.visible = true
	room.process_mode = Node.PROCESS_MODE_INHERIT

	var invalid_config := _config()
	invalid_config["schema_version"] = 2
	var failed_start = host.call("start_run", invalid_config)
	suite.assert_true(not failed_start.ok, "invalid config rejects the start command")
	_assert_counts(suite, recorder, [0, 0, 0, 0, 0], "failed start publishes no lifecycle facts")

	var started = host.call("start_run", _config())
	suite.assert_true(started.ok, "valid run starts")
	_assert_counts(suite, recorder, [1, 1, 0, 0, 0], "successful start publishes run and room entry once")
	var start_snapshot: Dictionary = host.call("runtime_snapshot")
	suite.assert_true(str(start_snapshot.get("run_id", "")).begins_with("run-%d-" % FIXED_SEED), "run start exposes the authoritative run id")
	suite.assert_equal(int(start_snapshot.get("phase", -1)), RunPhaseScript.Value.COMBAT_ACTIVE, "published snapshot mutation cannot alter authority")
	suite.assert_equal(str(start_snapshot.get("config", {}).get("character_id", "")), "wanderer", "nested published snapshot data is isolated")

	var active_runtime: Node = host.get("_room_runtime")
	var duplicate_entry = active_runtime.call("begin_current_room")
	suite.assert_true(not duplicate_entry.ok, "active room rejects duplicate entry")
	suite.assert_equal(recorder.room_started_count, 1, "rejected duplicate entry publishes no room-start fact")

	var panel := host.get_node("ChoiceLayer/ChoicePanelV2") as Control
	var runner := room.get_node("EncounterRunner")
	for room_number: int in range(1, 5):
		await _wait_for_room_phase(host, RunPhaseScript.Value.COMBAT_ACTIVE)
		var room_definition: Dictionary = (host.call("room_plan") as Array)[room_number - 1]
		await _play_authored_waves(room)
		var offer_snapshot: Dictionary = host.call("runtime_snapshot")
		var offer: Dictionary = offer_snapshot.get("open_offer", {})
		suite.assert_true(not offer.is_empty(), "room %d opens an authoritative offer" % room_number)
		suite.assert_equal(recorder.room_cleared_ids.size(), room_number, "room %d publishes one clear fact" % room_number)

		runner.encounter_completed.emit(StringName(str(room_definition.get("encounter_id", ""))))
		suite.assert_equal(recorder.room_cleared_ids.size(), room_number, "duplicate room %d completion publishes no fact" % room_number)

		var option: Dictionary = offer.get("options", [])[0]
		var offer_id := str(offer.get("offer_id", ""))
		var option_id := str(option.get("option_id", ""))
		var offer_revision := int(offer.get("revision", -1))
		if room_number == 1:
			var revision_before_stale := int((host.call("runtime_snapshot") as Dictionary).get("revision", -1))
			host.call("_on_option_chosen", offer_id, option_id, offer_revision + 1)
			suite.assert_equal(recorder.reward_selected_count, 0, "stale selection publishes no reward fact")
			suite.assert_equal(int((host.call("runtime_snapshot") as Dictionary).get("revision", -1)), revision_before_stale, "stale selection preserves revision")

		var buttons := _option_buttons(panel)
		suite.assert_true(not buttons.is_empty(), "room %d renders a selectable option" % room_number)
		if buttons.is_empty():
			continue
		buttons[0].pressed.emit()
		suite.assert_equal(recorder.reward_selected_count, room_number, "room %d publishes one selected reward" % room_number)
		host.call("_on_option_chosen", offer_id, option_id, offer_revision)
		suite.assert_equal(recorder.reward_selected_count, room_number, "duplicate room %d selection publishes no fact" % room_number)

	await _wait_for_room_phase(host, RunPhaseScript.Value.BOSS_ACTIVE)
	var boss_definition: Dictionary = (host.call("room_plan") as Array)[4]
	var spawned_bosses := await _wait_for_spawned_enemies(room)
	await _defeat_spawned_enemies(spawned_bosses)
	var final_snapshot: Dictionary = host.call("runtime_snapshot")
	suite.assert_equal(int(final_snapshot.get("phase", -1)), RunPhaseScript.Value.VICTORY, "boss completion reaches victory")

	runner.encounter_completed.emit(StringName(str(boss_definition.get("encounter_id", ""))))
	var facade: RefCounted = host.get("_facade")
	var duplicate_terminal = facade.call("boss_defeated", {"result": "victory"})
	suite.assert_true(not duplicate_terminal.ok, "duplicate terminal command is rejected")

	suite.assert_equal(recorder.run_started_count, 1, "run starts once")
	suite.assert_equal(recorder.room_started_count, 5, "five rooms start once each")
	suite.assert_equal(recorder.room_cleared_ids.size(), 5, "five rooms clear once each")
	suite.assert_equal(recorder.reward_selected_count, 4, "four successful offers publish once")
	suite.assert_equal(recorder.run_ended_count, 1, "run ends once")
	suite.assert_equal(recorder.duplicate_event_ids(), [], "lifecycle event ids are unique")
	suite.assert_equal(str(final_snapshot.get("result", {}).get("result", "")), "victory", "terminal payload mutation cannot alter authority")
	if not recorder.terminal_payloads.is_empty():
		suite.assert_equal(str(recorder.terminal_payloads[0].get("result", "")), "floor_cleared", "terminal fact uses the public outcome vocabulary")

	await _cleanup(main, recorder)
	suite.finish(get_tree())


func _connect_recorder(recorder: LifecycleRecorder) -> void:
	EventBus.run_started.connect(recorder.record_run_started)
	EventBus.room_started.connect(recorder.record_room_started)
	EventBus.room_cleared.connect(recorder.record_room_cleared)
	EventBus.reward_selected.connect(recorder.record_reward_selected)
	EventBus.run_ended.connect(recorder.record_run_ended)


func _disconnect_recorder(recorder: LifecycleRecorder) -> void:
	if EventBus.run_started.is_connected(recorder.record_run_started):
		EventBus.run_started.disconnect(recorder.record_run_started)
	if EventBus.room_started.is_connected(recorder.record_room_started):
		EventBus.room_started.disconnect(recorder.record_room_started)
	if EventBus.room_cleared.is_connected(recorder.record_room_cleared):
		EventBus.room_cleared.disconnect(recorder.record_room_cleared)
	if EventBus.reward_selected.is_connected(recorder.record_reward_selected):
		EventBus.reward_selected.disconnect(recorder.record_reward_selected)
	if EventBus.run_ended.is_connected(recorder.record_run_ended):
		EventBus.run_ended.disconnect(recorder.record_run_ended)


func _assert_counts(suite, recorder: LifecycleRecorder, expected: Array, label: String) -> void:
	suite.assert_equal(
		[
			recorder.run_started_count,
			recorder.room_started_count,
			recorder.room_cleared_ids.size(),
			recorder.reward_selected_count,
			recorder.run_ended_count,
		],
		expected,
		label
	)


func _play_authored_waves(room: Node) -> void:
	while true:
		var spawned_enemies := await _wait_for_spawned_enemies(room)
		if spawned_enemies.is_empty():
			return
		await _defeat_spawned_enemies(spawned_enemies)
		if not bool((room.get_node("EncounterRunner").call("snapshot") as Dictionary).get("active", false)):
			return


func _wait_for_room_phase(host: Node, expected_phase: int) -> void:
	for _frame: int in range(60):
		if int((host.call("runtime_snapshot") as Dictionary).get("phase", -1)) == expected_phase:
			return
		await get_tree().process_frame


func _wait_for_spawned_enemies(room: Node) -> Array[Node]:
	var enemies_root := room.get_node("Enemies")
	for _frame: int in range(60):
		var children: Array[Node] = []
		for child: Node in enemies_root.get_children():
			if not child.is_queued_for_deletion():
				children.append(child)
		if not children.is_empty():
			return children
		var runner_snapshot: Dictionary = room.get_node("EncounterRunner").call("snapshot")
		if not bool(runner_snapshot.get("active", false)):
			return []
		await get_tree().process_frame
	return []


func _defeat_spawned_enemies(enemies: Array[Node]) -> void:
	for enemy: Node in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		EventBus.entity_died.emit(enemy, null)
		enemy.queue_free()
	await get_tree().process_frame


func _option_buttons(panel: Control) -> Array[Button]:
	var buttons: Array[Button] = []
	var container := panel.get_node("SafeArea/Center/PanelRoot/Content/OptionsContainer")
	for child: Node in container.get_children():
		if child is Button:
			buttons.append(child as Button)
	return buttons


func _config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["time_stop", "time_rewind"],
		"difficulty": "normal",
		"seed": FIXED_SEED,
	}


func _cleanup(main: Node, recorder: LifecycleRecorder) -> void:
	get_tree().paused = false
	_disconnect_recorder(recorder)
	if main != null and is_instance_valid(main):
		main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.reset_persistent_data(true)
	GameState.save_path = _original_save_path
	GameState.persistent = _original_persistent.duplicate(true)
	_remove_tree(_test_storage_root)


func _isolated_storage_root() -> String:
	var base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if base.is_empty():
		base = OS.get_temp_dir().path_join("planewalker-tests")
	return base.path_join("run_lifecycle_publication_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])


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
