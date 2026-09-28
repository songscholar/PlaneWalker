extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const MainScene := preload("res://scenes/main.tscn")

const FIXED_SEED := 20260929
const TEST_SAVE_PATH := "/tmp/planewalker_wave3a_m1_runtime_smoke_save.json"


class RewardSignalCounter:
	extends RefCounted

	var count: int = 0
	var payloads: Array[Dictionary] = []

	func record(payload: Dictionary) -> void:
		count += 1
		payloads.append(payload.duplicate(true))


var _original_save_path: String
var _original_persistent: Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_original_save_path = GameState.save_path
	_original_persistent = GameState.persistent.duplicate(true)
	GameState.save_path = TEST_SAVE_PATH
	_reset_legacy_state()

	var main: Node = MainScene.instantiate()
	var room: Node = main.get_node("CombatRoom01")
	suite.assert_equal(_legacy_view_count(room), 3, "main scene contains legacy selections before adapter boot")
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var adapter: Node = main.get_node_or_null("RuntimeV2Adapter")
	if adapter == null:
		suite.assert_true(false, "main scene provides RuntimeV2Adapter")
		await _cleanup(main, null)
		suite.finish(get_tree())
		return

	suite.assert_true(bool(adapter.get("enabled")), "runtime adapter is enabled")
	suite.assert_equal(adapter.process_mode, Node.PROCESS_MODE_ALWAYS, "runtime adapter stays active while paused")
	suite.assert_true(bool(adapter.get("_active")), "runtime adapter boots successfully")
	suite.assert_true(adapter.get("_facade") != null, "runtime adapter owns an authoritative facade")
	suite.assert_equal(_legacy_view_count(room), 0, "successful adapter boot removes legacy selections")
	_assert_room_overrides(suite, room)

	var panel := adapter.get_node_or_null("ChoiceLayer/ChoicePanelV2") as Control
	suite.assert_true(panel != null, "runtime adapter creates the unified choice panel")
	if panel == null:
		await _cleanup(main, null)
		suite.finish(get_tree())
		return

	var reward_counter := RewardSignalCounter.new()
	EventBus.reward_selected.connect(reward_counter.record)
	room.set("spawn_warning_duration", 0.0)
	room.visible = true
	room.process_mode = Node.PROCESS_MODE_INHERIT
	GameState.start_run({
		"character_id": "wanderer",
		"weapon_id": "sword",
		"difficulty": "normal",
		"seed": FIXED_SEED,
	})

	var facade: RefCounted = adapter.get("_facade")
	var started_snapshot: Dictionary = facade.call("snapshot")
	suite.assert_equal(started_snapshot["phase"], RunPhaseScript.Value.ROOM_ENTERING, "fixed-seed run prepares room one")
	suite.assert_equal(started_snapshot["run_seed"], FIXED_SEED, "authoritative runtime uses the fixed seed")
	room.call("begin_run")

	var expected_reward_kinds: Array[String] = ["starter", "reinforcement", "talent", "contract"]
	for room_number: int in range(1, 5):
		await _wait_for_room_phase(facade, RunPhaseScript.Value.COMBAT_ACTIVE)
		suite.assert_equal(GameState.current_room, room_number, "room controller naturally enters room %d" % room_number)
		var room_definition: Dictionary = facade.call("current_room_definition")
		suite.assert_equal(
			str(room_definition.get("reward_kind", "")),
			expected_reward_kinds[room_number - 1],
			"room %d opens the expected reward kind" % room_number
		)
		var active_snapshot: Dictionary = facade.call("snapshot")
		suite.assert_equal(active_snapshot["phase"], RunPhaseScript.Value.COMBAT_ACTIVE, "room %d enters combat" % room_number)

		var spawned_enemies := await _wait_for_spawned_enemies(room)
		suite.assert_true(not spawned_enemies.is_empty(), "room %d spawns combat enemies" % room_number)
		await _defeat_spawned_enemies(spawned_enemies)
		var offer_snapshot: Dictionary = facade.call("snapshot")
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
		suite.assert_equal(GameState.current_room, room_number + 1, "room %d selection advances the legacy room controller" % room_number)

	await _wait_for_room_phase(facade, RunPhaseScript.Value.BOSS_ACTIVE)
	suite.assert_equal(GameState.current_room, 5, "room controller naturally enters the boss room")
	var boss_snapshot: Dictionary = facade.call("snapshot")
	suite.assert_equal(boss_snapshot["phase"], RunPhaseScript.Value.BOSS_ACTIVE, "room five enters boss phase")
	suite.assert_true(boss_snapshot["open_offer"].is_empty(), "boss room starts without an offer")

	var spawned_bosses := await _wait_for_spawned_enemies(room)
	suite.assert_equal(spawned_bosses.size(), 1, "boss room spawns one boss actor")
	await _defeat_spawned_enemies(spawned_bosses)
	var final_snapshot: Dictionary = facade.call("snapshot")
	suite.assert_equal(final_snapshot["phase"], RunPhaseScript.Value.VICTORY, "boss defeat enters victory")
	suite.assert_true(final_snapshot["open_offer"].is_empty(), "boss victory opens no offer")
	suite.assert_equal(reward_counter.count, 4, "five-room run emits exactly four compatibility reward facts")
	suite.assert_equal(final_snapshot["current_room"], 5, "authoritative snapshot finishes on room five")
	suite.assert_equal(final_snapshot["consumed_offer_ids"].size(), 4, "authoritative snapshot consumes four offers")
	var build: Dictionary = final_snapshot["build"]
	suite.assert_true(_selected_count(build) > 0, "authoritative snapshot contains a non-empty build")
	_assert_build_counts_agree(suite, build)

	await _cleanup(main, reward_counter)
	suite.finish(get_tree())


func _assert_room_overrides(suite, room: Node) -> void:
	var no_events: Array[int] = []
	var room_four_elite: Array[int] = [4]
	var no_curse_offers: Array[int] = []
	suite.assert_equal(room.get("event_rooms"), no_events, "main scene disables legacy event rooms")
	suite.assert_equal(room.get("elite_rooms"), room_four_elite, "main scene makes room four elite")
	suite.assert_equal(room.get("curse_offer_rooms"), no_curse_offers, "main scene disables legacy curse offers")


func _assert_build_counts_agree(suite, authoritative_build: Dictionary) -> void:
	var legacy_build: Dictionary = GameState.get_build_state_snapshot()
	for field: String in ["items", "blessings", "curses", "talents"]:
		suite.assert_equal(
			legacy_build.get(field, []).size(),
			authoritative_build.get(field, []).size(),
			"GameState %s count matches the authoritative snapshot" % field
		)


func _selected_count(build: Dictionary) -> int:
	var count := 0
	for field: String in ["items", "blessings", "curses", "talents"]:
		count += build.get(field, []).size()
	return count


func _wait_for_room_phase(facade: RefCounted, expected_phase: int) -> void:
	for _frame: int in range(30):
		if int((facade.call("snapshot") as Dictionary).get("phase", -1)) == expected_phase:
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


func _legacy_view_count(room: Node) -> int:
	var count := 0
	for view_name: String in ["RewardSelection", "CurseSelection", "EventSelection"]:
		if room.get_node_or_null(view_name) != null:
			count += 1
	return count


func _cleanup(main: Node, reward_counter: RewardSignalCounter) -> void:
	get_tree().paused = false
	if reward_counter != null and EventBus.reward_selected.is_connected(reward_counter.record):
		EventBus.reward_selected.disconnect(reward_counter.record)
	if main != null and is_instance_valid(main):
		main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_reset_legacy_state()
	GameState.save_path = _original_save_path
	GameState.persistent = _original_persistent.duplicate(true)
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)


func _reset_legacy_state() -> void:
	get_tree().paused = false
	GameState.phase = GameState.GamePhase.HUB
	GameState.current_floor = 1
	GameState.current_room = 0
	GameState.run_seed = 0
	GameState.run_timer = 0.0
	GameState.current_run = {}
	GameState.last_run_result = {}
	if GameState.build_state != null:
		GameState.build_state.reset()
