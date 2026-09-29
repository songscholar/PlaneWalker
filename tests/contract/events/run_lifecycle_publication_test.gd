extends Node

const MainScene := preload("res://scenes/main.tscn")
const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const FIXED_SEED := 20260929


class WeaponProfileFixture:
	extends RefCounted

	const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"

	static func m1_sword() -> Dictionary:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
		assert(parsed is Array, "weapon runtime profile catalog must contain an array")
		for definition_value: Variant in parsed as Array:
			if (
				definition_value is Dictionary
				and str((definition_value as Dictionary).get("id", "")) == "sword_m1_v1"
			):
				return (definition_value as Dictionary).duplicate(true)
		assert(false, "weapon runtime profile catalog must contain sword_m1_v1")
		return {}


class RejectingLoadoutPlayer:
	extends Node

	var configure_calls: int = 0

	func configure_loadout(_config: Dictionary) -> bool:
		configure_calls += 1
		return false


class AcceptingLoadoutPlayer:
	extends Node

	var configure_calls: int = 0

	func configure_loadout(_config: Dictionary) -> bool:
		configure_calls += 1
		return true


class FailingInitialRoomRuntime:
	extends Node

	signal room_started(room_id: StringName, revision: int)
	signal room_cleared(room_id: StringName, revision: int)
	signal terminal_committed(context: Dictionary, revision: int)
	signal runtime_failed(context: Dictionary)

	func begin_current_room() -> Variant:
		return CommandResultScript.failure(
			&"INVALID_PHASE",
			2,
			{"operation": "begin_current_room"}
		)


class FailingInitialRoomFacade:
	extends RefCounted

	var config: Dictionary = {}
	var run_id: String = ""
	var revision: int = 0
	var phase: int = RunPhaseScript.Value.HUB
	var player_died_calls: int = 0
	var catalog := RefCounted.new()

	func start_run(accepted_config: Dictionary, accepted_run_id: String) -> Variant:
		config = accepted_config.duplicate(true)
		run_id = accepted_run_id
		revision = 1
		phase = RunPhaseScript.Value.ROOM_TRANSITION
		return CommandResultScript.success(revision)

	func snapshot() -> Dictionary:
		return {
			"run_id": run_id,
			"revision": revision,
			"phase": phase,
			"config": config.duplicate(true),
		}

	func active_loadout() -> Dictionary:
		return {"weapon_profile": WeaponProfileFixture.m1_sword()}

	func create_room_runtime(_runner: Node) -> Node:
		return FailingInitialRoomRuntime.new()

	func encounter_catalog() -> RefCounted:
		return catalog

	func player_died(_context: Dictionary) -> Variant:
		player_died_calls += 1
		revision += 1
		phase = RunPhaseScript.Value.DEFEAT
		return CommandResultScript.success(revision)

	func advance_time(_delta_seconds: float) -> Variant:
		return CommandResultScript.failure(&"TERMINAL_STATE", revision)


class FailingInitialRoomController:
	extends Node

	var runner := Node.new()

	func _init() -> void:
		add_child(runner)

	func encounter_runner() -> Node:
		return runner

	func configure_authored_runtime(_runtime: Node, _catalog: RefCounted) -> bool:
		return true


class SynchronousInitialRoomRuntime:
	extends Node

	signal room_started(room_id: StringName, revision: int)
	signal room_cleared(room_id: StringName, revision: int)
	signal terminal_committed(context: Dictionary, revision: int)
	signal runtime_failed(context: Dictionary)

	var facade: RefCounted
	var mode: StringName = &"clear"

	func begin_current_room() -> Variant:
		facade.call("mark_room_started")
		var entered_revision := int((facade.call("snapshot") as Dictionary).get("revision", 0))
		room_started.emit(&"room_event_01", entered_revision)
		if mode == &"clear":
			facade.call("mark_room_cleared")
			var cleared_revision := int((facade.call("snapshot") as Dictionary).get("revision", 0))
			room_cleared.emit(&"room_event_01", cleared_revision)
		else:
			runtime_failed.emit({
				"result": "runtime_error",
				"runtime_error_code": "SYNCHRONOUS_INITIAL_FAILURE",
				"room_id": "room_event_01",
			})
		return CommandResultScript.success(entered_revision)


class SynchronousInitialRoomFacade:
	extends RefCounted

	var mode: StringName = &"clear"
	var config: Dictionary = {}
	var run_id: String = ""
	var revision: int = 0
	var phase: int = RunPhaseScript.Value.HUB
	var open_offer: Dictionary = {}
	var player_died_calls: int = 0
	var catalog := RefCounted.new()

	func start_run(accepted_config: Dictionary, accepted_run_id: String) -> Variant:
		config = accepted_config.duplicate(true)
		run_id = accepted_run_id
		revision = 1
		phase = RunPhaseScript.Value.ROOM_TRANSITION
		open_offer.clear()
		return CommandResultScript.success(revision)

	func snapshot() -> Dictionary:
		return {
			"run_id": run_id,
			"revision": revision,
			"phase": phase,
			"config": config.duplicate(true),
			"open_offer": open_offer.duplicate(true),
		}

	func active_loadout() -> Dictionary:
		return {"weapon_profile": WeaponProfileFixture.m1_sword()}

	func create_room_runtime(_runner: Node) -> Node:
		var runtime := SynchronousInitialRoomRuntime.new()
		runtime.facade = self
		runtime.mode = mode
		return runtime

	func encounter_catalog() -> RefCounted:
		return catalog

	func mark_room_started() -> void:
		revision = 2
		phase = RunPhaseScript.Value.COMBAT_ACTIVE

	func mark_room_cleared() -> void:
		revision = 3
		phase = RunPhaseScript.Value.SELECTION_ACTIVE
		open_offer = {
			"schema_version": 1,
			"offer_id": "%s:room_event_01:item:3" % run_id,
			"revision": revision,
			"category": "item",
			"title_key": "UI_CHOOSE_REWARD",
			"can_skip": false,
			"options": [{
				"option_id": "frozen_burst",
				"content_id": "frozen_burst",
				"name_key": "FROZEN_BURST_NAME",
				"description_key": "FROZEN_BURST_DESC",
				"archetype_key": "ARCHETYPE_TIME_STOP_BURST",
				"role_key": "ROLE_STARTER",
				"rarity": "common",
				"icon_id": "content_frozen_burst",
				"effect_summary_keys": [],
			}],
		}

	func player_died(_context: Dictionary) -> Variant:
		player_died_calls += 1
		revision += 1
		phase = RunPhaseScript.Value.DEFEAT
		return CommandResultScript.success(revision)

	func advance_time(_delta_seconds: float) -> Variant:
		return CommandResultScript.success(revision)


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
	await _assert_loadout_failure_is_silent(suite)
	await _assert_first_room_failure_is_silent(suite)
	await _assert_synchronous_first_room_clear_is_ordered(suite)
	await _assert_synchronous_runtime_failure_is_silent(suite)

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
	suite.assert_true(
		started.ok,
		"valid run starts: code=%s context=%s" % [str(started.code), str(started.context)]
	)
	if not started.ok:
		await _cleanup(main, recorder)
		suite.finish(get_tree())
		return
	_assert_counts(suite, recorder, [1, 1, 0, 0, 0], "successful start publishes run and room entry once")
	suite.assert_true(recorder.event_ids.size() >= 2, "successful start records run and first-room facts")
	if recorder.event_ids.size() >= 2:
		suite.assert_true(recorder.event_ids[0].begins_with("run_started|"), "run_started is the first lifecycle fact")
		suite.assert_true(recorder.event_ids[1].begins_with("room_started|"), "first room_started follows run_started")
	if not recorder.run_started_payloads.is_empty():
		suite.assert_equal(
			int(recorder.run_started_payloads[0].get("phase", -1)),
			RunPhaseScript.Value.COMBAT_ACTIVE,
			"run_started publishes the initialized combat snapshot"
		)
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


func _assert_loadout_failure_is_silent(suite) -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var host := main.get_node_or_null("RunRuntimeHost")
	var room := main.get_node_or_null("CombatRoom01")
	var recorder := LifecycleRecorder.new()
	var rejecting_player := RejectingLoadoutPlayer.new()
	_connect_recorder(recorder)
	if host == null or room == null:
		suite.assert_true(false, "main provides loadout-failure fixtures")
	else:
		room.set("spawn_warning_duration", 0.0)
		host.set("_player", rejecting_player)
		var failed = host.call("start_run", _config())
		suite.assert_true(not failed.ok, "player loadout rejection fails the run start")
		suite.assert_equal(failed.code, &"LOADOUT_APPLY_FAILED", "loadout rejection uses the stable failure code")
		suite.assert_equal(rejecting_player.configure_calls, 1, "failed loadout is attempted exactly once")
		_assert_counts(suite, recorder, [0, 0, 0, 0, 0], "loadout failure publishes no lifecycle facts")
		suite.assert_equal(recorder.event_ids, [], "loadout failure has no hidden lifecycle ordering")
	_disconnect_recorder(recorder)
	main.queue_free()
	rejecting_player.free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_first_room_failure_is_silent(suite) -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var host := main.get_node_or_null("RunRuntimeHost")
	var recorder := LifecycleRecorder.new()
	var player := AcceptingLoadoutPlayer.new()
	var facade := FailingInitialRoomFacade.new()
	var room_controller := FailingInitialRoomController.new()
	_connect_recorder(recorder)
	if host == null:
		suite.assert_true(false, "main provides first-room failure fixture")
	else:
		host.set("_facade", facade)
		host.set("_active_run_id", "")
		host.set("_player", player)
		host.set("_room_controller", room_controller)
		var failed = host.call("start_run", _config())
		suite.assert_true(not failed.ok, "first-room rejection fails the run start")
		suite.assert_equal(failed.code, &"INVALID_PHASE", "first-room rejection preserves its stable code")
		suite.assert_equal(player.configure_calls, 1, "first-room failure applies the loadout once")
		suite.assert_equal(facade.player_died_calls, 1, "first-room failure terminates authority once")
		suite.assert_true(host.get("_room_runtime") == null, "first-room failure disposes the runtime")
		_assert_counts(suite, recorder, [0, 0, 0, 0, 0], "first-room failure publishes no lifecycle facts")
		suite.assert_equal(recorder.event_ids, [], "first-room failure has no hidden lifecycle ordering")
	_disconnect_recorder(recorder)
	main.queue_free()
	player.free()
	room_controller.free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_synchronous_first_room_clear_is_ordered(suite) -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var host := main.get_node_or_null("RunRuntimeHost")
	var recorder := LifecycleRecorder.new()
	var player := AcceptingLoadoutPlayer.new()
	var facade := SynchronousInitialRoomFacade.new()
	var room_controller := FailingInitialRoomController.new()
	_connect_recorder(recorder)
	if host == null:
		suite.assert_true(false, "main provides synchronous clear fixture")
	else:
		host.set("_facade", facade)
		host.set("_active_run_id", "")
		host.set("_player", player)
		host.set("_room_controller", room_controller)
		var started = host.call("start_run", _config())
		suite.assert_true(started.ok, "synchronous event room initializes successfully")
		_assert_counts(suite, recorder, [1, 1, 1, 0, 0], "synchronous clear publishes each lifecycle fact once")
		suite.assert_equal(recorder.event_ids.size(), 3, "synchronous clear records three ordered facts")
		if recorder.event_ids.size() == 3:
			suite.assert_true(recorder.event_ids[0].begins_with("run_started|"), "synchronous clear starts with run_started")
			suite.assert_true(recorder.event_ids[1].begins_with("room_started|"), "synchronous clear publishes room_started second")
			suite.assert_true(recorder.event_ids[2].begins_with("room_cleared|"), "synchronous clear publishes room_cleared third")
		var snapshot: Dictionary = host.call("runtime_snapshot")
		suite.assert_equal(int(snapshot.get("phase", -1)), RunPhaseScript.Value.SELECTION_ACTIVE, "synchronous clear retains selection authority")
		suite.assert_true(not (snapshot.get("open_offer", {}) as Dictionary).is_empty(), "synchronous clear retains the authoritative offer")
		var panel := host.call("choice_panel") as Control
		suite.assert_true(panel != null and panel.visible, "synchronous clear opens the choice panel")
		suite.assert_equal(facade.player_died_calls, 0, "synchronous clear does not terminate authority")
		host.set("_active", false)
	_disconnect_recorder(recorder)
	main.queue_free()
	player.free()
	room_controller.free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_synchronous_runtime_failure_is_silent(suite) -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var host := main.get_node_or_null("RunRuntimeHost")
	var recorder := LifecycleRecorder.new()
	var player := AcceptingLoadoutPlayer.new()
	var facade := SynchronousInitialRoomFacade.new()
	facade.mode = &"runtime_failure"
	var room_controller := FailingInitialRoomController.new()
	_connect_recorder(recorder)
	if host == null:
		suite.assert_true(false, "main provides synchronous runtime-failure fixture")
	else:
		host.set("_facade", facade)
		host.set("_active_run_id", "")
		host.set("_player", player)
		host.set("_room_controller", room_controller)
		var failed = host.call("start_run", _config())
		suite.assert_true(not failed.ok, "synchronous runtime failure rejects run start")
		suite.assert_equal(failed.code, &"AUTHORED_RUNTIME_CONFIGURATION_FAILED", "synchronous runtime failure uses the stable host code")
		suite.assert_equal(player.configure_calls, 1, "synchronous runtime failure applies the loadout once")
		suite.assert_equal(facade.player_died_calls, 1, "synchronous runtime failure terminates authority once")
		suite.assert_true(host.get("_room_runtime") == null, "synchronous runtime failure disposes the runtime")
		_assert_counts(suite, recorder, [0, 0, 0, 0, 0], "synchronous runtime failure publishes no lifecycle facts")
		suite.assert_equal(recorder.event_ids, [], "synchronous runtime failure has no hidden lifecycle ordering")
		host.set("_active", false)
	_disconnect_recorder(recorder)
	main.queue_free()
	player.free()
	room_controller.free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame


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


func _config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
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
