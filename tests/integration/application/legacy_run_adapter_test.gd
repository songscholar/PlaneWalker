extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const CommandResultScript := preload("res://scripts/application/command_result.gd")
const LegacyRunAdapterScript := preload("res://scripts/application/legacy_run_adapter.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")

const VALID_MANIFEST := "res://data/content_manifest.json"
const INVALID_MANIFEST := "res://tests/fixtures/content/missing-manifest.json"
const TEST_SAVE_PATH := "/tmp/planewalker_wave3a_adapter_test_save.json"


class FakePlayer:
	extends Node

	var applied_definitions: Array[Dictionary] = []

	func apply_reward(definition: Dictionary) -> void:
		applied_definitions.append(definition.duplicate(true))


class RewardSignalCounter:
	extends RefCounted

	var count: int = 0
	var payloads: Array[Dictionary] = []

	func record(payload: Dictionary) -> void:
		count += 1
		payloads.append(payload.duplicate(true))


class TransitionRejectingFacade:
	extends RefCounted

	var run_id: String
	var definition: Dictionary
	var revision: int

	func _init(p_run_id: String, p_definition: Dictionary, p_revision: int) -> void:
		run_id = p_run_id
		definition = p_definition.duplicate(true)
		revision = p_revision

	func snapshot() -> Dictionary:
		return {
			"run_id": run_id,
			"phase": RunPhaseScript.Value.SELECTION_ACTIVE,
			"revision": revision,
		}

	func submit_selection(_offer_id: String, _option_id: String, _offer_revision: int):
		return CommandResultScript.success(revision + 1, {"definition": definition.duplicate(true)})

	func complete_transition():
		return CommandResultScript.failure(&"INVALID_PHASE", revision + 1)


var _original_save_path: String


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_original_save_path = GameState.save_path
	GameState.save_path = TEST_SAVE_PATH
	await _test_fail_safe_activation(suite)
	await _test_full_selection_flow(suite)
	await _test_accepted_contract_projection(suite)
	await _test_transition_failure_has_no_legacy_side_effects(suite)
	await _test_terminal_guards(suite)
	await _test_selection_phase_death_sync(suite)
	await _test_pause_overlay(suite)
	GameState.save_path = _original_save_path
	DirAccess.remove_absolute(TEST_SAVE_PATH)
	suite.finish(get_tree())


func _test_fail_safe_activation(suite) -> void:
	_reset_legacy_state()
	var disabled_fixture: Dictionary = await _create_fixture(false, VALID_MANIFEST)
	var disabled_adapter: Node = disabled_fixture["adapter"]
	suite.assert_true(not disabled_adapter._active, "default-off adapter remains inactive")
	suite.assert_equal(_choice_layer_count(disabled_adapter), 0, "default-off adapter creates no choice layer")
	suite.assert_equal(_legacy_view_count(disabled_fixture["room"]), 3, "default-off adapter keeps legacy selections")
	EventBus.room_started.emit(&"ignored_room")
	EventBus.room_cleared.emit(&"ignored_room")
	suite.assert_true(disabled_adapter._facade == null, "default-off adapter ignores lifecycle signals")
	await _destroy_fixture(disabled_fixture)

	_reset_legacy_state()
	var invalid_fixture: Dictionary = await _create_fixture(true, INVALID_MANIFEST)
	var invalid_adapter: Node = invalid_fixture["adapter"]
	suite.assert_true(not invalid_adapter._active, "invalid manifest leaves adapter inactive")
	suite.assert_equal(_choice_layer_count(invalid_adapter), 0, "invalid manifest creates no choice layer")
	suite.assert_equal(_legacy_view_count(invalid_fixture["room"]), 3, "invalid manifest keeps legacy selections")
	await _destroy_fixture(invalid_fixture)

	_reset_legacy_state()
	var valid_fixture: Dictionary = await _create_fixture(true, VALID_MANIFEST)
	var valid_adapter: Node = valid_fixture["adapter"]
	suite.assert_true(valid_adapter._active, "valid manifest activates adapter")
	suite.assert_equal(_choice_layer_count(valid_adapter), 1, "valid manifest creates one choice layer")
	suite.assert_true(_choice_panel(valid_adapter) != null, "valid manifest creates one choice panel")
	suite.assert_equal(_legacy_view_count(valid_fixture["room"]), 0, "valid manifest frees all legacy selections")
	await _destroy_fixture(valid_fixture)


func _test_full_selection_flow(suite) -> void:
	_reset_legacy_state()
	var fixture: Dictionary = await _create_fixture(true, VALID_MANIFEST)
	var adapter: Node = fixture["adapter"]
	var player: FakePlayer = fixture["player"]
	var panel: Control = _choice_panel(adapter)
	var reward_counter := RewardSignalCounter.new()
	EventBus.reward_selected.connect(reward_counter.record)

	_start_legacy_run(20260929)
	_enter_room(1)
	var snapshot: Dictionary = adapter._facade.snapshot()
	suite.assert_equal(snapshot["phase"], RunPhaseScript.Value.COMBAT_ACTIVE, "room start enters authoritative combat")

	var projectile := Node.new()
	projectile.add_to_group("time_stoppable")
	fixture["host"].add_child(projectile)
	var boss_hazard := Node.new()
	boss_hazard.add_to_group("boss_hazards")
	fixture["host"].add_child(boss_hazard)
	var surviving_enemy := Node.new()
	surviving_enemy.add_to_group("time_stoppable")
	surviving_enemy.add_to_group("enemies")
	fixture["host"].add_child(surviving_enemy)
	_clear_room(1)
	snapshot = adapter._facade.snapshot()
	var first_offer: Dictionary = snapshot["open_offer"]
	suite.assert_equal(first_offer["category"], "item", "room one opens starter item offer")
	suite.assert_true(panel.visible, "room clear opens unified choice panel")
	suite.assert_equal(player.process_mode, Node.PROCESS_MODE_DISABLED, "selection disables player processing")
	suite.assert_equal(_option_buttons(panel).size(), 3, "unified panel renders three choices")
	suite.assert_true(projectile.is_queued_for_deletion(), "selection clears time-stoppable projectiles")
	suite.assert_true(boss_hazard.is_queued_for_deletion(), "selection clears boss hazards")
	suite.assert_true(not surviving_enemy.is_queued_for_deletion(), "selection safety does not delete enemy actors")

	var first_option_id := str(first_offer["options"][0]["option_id"])
	_option_buttons(panel)[0].pressed.emit()
	suite.assert_equal(player.applied_definitions.size(), 1, "valid click applies player effects once")
	suite.assert_equal(GameState.current_run.get("inventory", []).size(), 1, "valid item mirrors to GameState once")
	suite.assert_equal(GameState.current_run.get("rewards", []).size(), 1, "valid item records one compatibility reward")
	suite.assert_equal(reward_counter.count, 1, "valid click emits one room-advance signal")
	suite.assert_true(not panel.visible, "valid click closes the panel")
	suite.assert_equal(player.process_mode, Node.PROCESS_MODE_INHERIT, "valid click restores player processing")
	snapshot = adapter._facade.snapshot()
	suite.assert_equal(snapshot["phase"], RunPhaseScript.Value.ROOM_ENTERING, "valid click completes transition")
	suite.assert_equal(snapshot["current_room"], 2, "valid click advances authoritative room")

	panel.option_chosen.emit(str(first_offer["offer_id"]), first_option_id, int(first_offer["revision"]))
	suite.assert_equal(player.applied_definitions.size(), 1, "replayed intent does not reapply effects")
	suite.assert_equal(GameState.current_run.get("inventory", []).size(), 1, "replayed intent does not duplicate legacy build")
	suite.assert_equal(reward_counter.count, 1, "replayed intent does not advance the room twice")

	_enter_room(2)
	_clear_room(2)
	var second_offer: Dictionary = adapter._facade.snapshot()["open_offer"]
	panel.option_chosen.emit("forged-offer", str(second_offer["options"][0]["option_id"]), int(second_offer["revision"]))
	_assert_rejected_offer_stays_open(suite, adapter, panel, second_offer, "forged offer id")
	panel.option_chosen.emit(str(second_offer["offer_id"]), str(second_offer["options"][0]["option_id"]), int(second_offer["revision"]) + 1)
	_assert_rejected_offer_stays_open(suite, adapter, panel, second_offer, "stale revision")
	panel.option_chosen.emit(str(second_offer["offer_id"]), "missing-option", int(second_offer["revision"]))
	_assert_rejected_offer_stays_open(suite, adapter, panel, second_offer, "forged option")
	_option_buttons(panel)[0].pressed.emit()
	suite.assert_equal(reward_counter.count, 2, "room two commits once after rejected intents")

	_enter_room(3)
	_clear_room(3)
	var third_offer: Dictionary = adapter._facade.snapshot()["open_offer"]
	suite.assert_equal(third_offer["category"], "talent", "room three opens talent offer")
	_option_buttons(panel)[0].pressed.emit()
	suite.assert_equal(GameState.current_run.get("talents", []).size(), 1, "talent mirrors to GameState once")

	_enter_room(4)
	_clear_room(4)
	var contract_offer: Dictionary = adapter._facade.snapshot()["open_offer"]
	suite.assert_equal(contract_offer["category"], "contract", "room four opens risk contract")
	var decline_id := _find_option_id(contract_offer, "decline_contract")
	var applied_before_decline := player.applied_definitions.size()
	var curses_before_decline: int = GameState.current_run.get("active_curses", []).size()
	panel.option_chosen.emit(str(contract_offer["offer_id"]), decline_id, int(contract_offer["revision"]))
	suite.assert_equal(player.applied_definitions.size(), applied_before_decline, "decline contract applies no player effect")
	suite.assert_equal(GameState.current_run.get("active_curses", []).size(), curses_before_decline, "decline contract records no curse")
	suite.assert_equal(reward_counter.count, 4, "decline still emits the single room-advance fact")

	_enter_room(5)
	snapshot = adapter._facade.snapshot()
	suite.assert_equal(snapshot["phase"], RunPhaseScript.Value.BOSS_ACTIVE, "room five enters boss phase")
	var reward_count_before_boss := reward_counter.count
	_clear_room(5)
	snapshot = adapter._facade.snapshot()
	suite.assert_equal(snapshot["phase"], RunPhaseScript.Value.VICTORY, "boss clear enters victory directly")
	suite.assert_true(snapshot["open_offer"].is_empty(), "boss victory opens no offer")
	suite.assert_equal(reward_counter.count, reward_count_before_boss, "boss clear emits no reward-selected fact")
	suite.assert_equal(GameState.phase, GameState.GamePhase.RUN_END, "boss victory mirrors legacy run end")

	if EventBus.reward_selected.is_connected(reward_counter.record):
		EventBus.reward_selected.disconnect(reward_counter.record)
	await _destroy_fixture(fixture)


func _test_accepted_contract_projection(suite) -> void:
	_reset_legacy_state()
	var fixture: Dictionary = await _create_fixture(true, VALID_MANIFEST)
	var adapter: Node = fixture["adapter"]
	var player: FakePlayer = fixture["player"]
	var panel: Control = _choice_panel(adapter)
	var reward_counter := RewardSignalCounter.new()
	EventBus.reward_selected.connect(reward_counter.record)

	_start_legacy_run(20261002)
	for room_number: int in range(1, 4):
		_enter_room(room_number)
		_clear_room(room_number)
		_option_buttons(panel)[0].pressed.emit()

	_enter_room(4)
	_clear_room(4)
	var contract_offer: Dictionary = adapter._facade.snapshot()["open_offer"]
	var curse_option_id := ""
	for option: Dictionary in contract_offer.get("options", []):
		if str(option.get("option_id", "")) != "decline_contract":
			curse_option_id = str(option["option_id"])
			break
	suite.assert_true(not curse_option_id.is_empty(), "contract offer exposes an accepted-risk option")
	var applied_before := player.applied_definitions.size()
	panel.option_chosen.emit(
		str(contract_offer["offer_id"]),
		curse_option_id,
		int(contract_offer["revision"])
	)
	suite.assert_equal(player.applied_definitions.size(), applied_before + 1, "accepted contract applies generic player effects once")
	suite.assert_equal(GameState.current_run.get("active_curses", []).size(), 1, "accepted contract mirrors one active curse")
	suite.assert_equal(GameState.current_run.get("curses", []).size(), 1, "accepted contract records one curse definition")
	suite.assert_equal(reward_counter.count, 4, "accepted contract emits one room-advance fact")

	panel.option_chosen.emit(
		str(contract_offer["offer_id"]),
		curse_option_id,
		int(contract_offer["revision"])
	)
	suite.assert_equal(player.applied_definitions.size(), applied_before + 1, "replayed contract intent does not reapply effects")
	suite.assert_equal(GameState.current_run.get("active_curses", []).size(), 1, "replayed contract intent does not duplicate curse")
	suite.assert_equal(reward_counter.count, 4, "replayed contract intent does not advance twice")

	if EventBus.reward_selected.is_connected(reward_counter.record):
		EventBus.reward_selected.disconnect(reward_counter.record)
	await _destroy_fixture(fixture)


func _test_terminal_guards(suite) -> void:
	_reset_legacy_state()
	var fixture: Dictionary = await _create_fixture(true, VALID_MANIFEST)
	var adapter: Node = fixture["adapter"]
	var player: FakePlayer = fixture["player"]
	var panel: Control = _choice_panel(adapter)
	var reward_counter := RewardSignalCounter.new()
	EventBus.reward_selected.connect(reward_counter.record)

	_start_legacy_run(20260930)
	_enter_room(1)
	GameState.fail_run("test")
	var snapshot: Dictionary = adapter._facade.snapshot()
	suite.assert_equal(snapshot["phase"], RunPhaseScript.Value.DEFEAT, "legacy death enters authoritative defeat")
	var revision_after_death := int(snapshot["revision"])
	_clear_room(1)
	panel.option_chosen.emit("late-offer", "late-option", revision_after_death)
	snapshot = adapter._facade.snapshot()
	suite.assert_equal(snapshot["phase"], RunPhaseScript.Value.DEFEAT, "late callbacks cannot leave defeat")
	suite.assert_equal(snapshot["revision"], revision_after_death, "late callbacks do not advance terminal revision")
	suite.assert_equal(player.applied_definitions.size(), 0, "late callbacks apply no player effects")
	suite.assert_equal(reward_counter.count, 0, "late callbacks emit no room-advance fact")
	suite.assert_true(not panel.visible, "terminal run keeps choice panel closed")

	if EventBus.reward_selected.is_connected(reward_counter.record):
		EventBus.reward_selected.disconnect(reward_counter.record)
	await _destroy_fixture(fixture)


func _test_transition_failure_has_no_legacy_side_effects(suite) -> void:
	_reset_legacy_state()
	var fixture: Dictionary = await _create_fixture(true, VALID_MANIFEST)
	var adapter: Node = fixture["adapter"]
	var player: FakePlayer = fixture["player"]
	var panel: Control = _choice_panel(adapter)
	var reward_counter := RewardSignalCounter.new()
	EventBus.reward_selected.connect(reward_counter.record)

	_start_legacy_run(20261004)
	_enter_room(1)
	_clear_room(1)
	var actual_snapshot: Dictionary = adapter._facade.snapshot()
	var offer: Dictionary = actual_snapshot["open_offer"]
	var definition := {
		"id": str(offer["options"][0]["content_id"]),
		"category": "item",
		"effects": {},
	}
	adapter._facade = TransitionRejectingFacade.new(
		str(actual_snapshot["run_id"]),
		definition,
		int(actual_snapshot["revision"])
	)
	panel.option_chosen.emit(
		str(offer["offer_id"]),
		str(offer["options"][0]["option_id"]),
		int(offer["revision"])
	)
	suite.assert_equal(player.applied_definitions.size(), 0, "transition rejection applies no player effect")
	suite.assert_true(GameState.current_run.get("inventory", []).is_empty(), "transition rejection mirrors no legacy reward")
	suite.assert_equal(reward_counter.count, 0, "transition rejection emits no room-advance fact")
	suite.assert_true(panel.visible, "transition rejection keeps the choice panel visible")
	suite.assert_equal(player.process_mode, Node.PROCESS_MODE_DISABLED, "transition rejection keeps selection safety active")

	if EventBus.reward_selected.is_connected(reward_counter.record):
		EventBus.reward_selected.disconnect(reward_counter.record)
	await _destroy_fixture(fixture)


func _test_pause_overlay(suite) -> void:
	_reset_legacy_state()
	var fixture: Dictionary = await _create_fixture(true, VALID_MANIFEST)
	var adapter: Node = fixture["adapter"]
	_start_legacy_run(20261001)
	_enter_room(1)
	var before: Dictionary = adapter._facade.snapshot()

	get_tree().paused = true
	await get_tree().process_frame
	var paused: Dictionary = adapter._facade.snapshot()
	suite.assert_true(paused["suspended"], "tree pause suspends authoritative runtime")
	suite.assert_equal(paused["phase"], before["phase"], "pause preserves authoritative phase")

	get_tree().paused = false
	await get_tree().process_frame
	var resumed: Dictionary = adapter._facade.snapshot()
	suite.assert_true(not resumed["suspended"], "tree resume clears authoritative suspension")
	suite.assert_equal(resumed["phase"], before["phase"], "resume preserves authoritative phase")
	await _destroy_fixture(fixture)


func _test_selection_phase_death_sync(suite) -> void:
	_reset_legacy_state()
	var fixture: Dictionary = await _create_fixture(true, VALID_MANIFEST)
	var adapter: Node = fixture["adapter"]
	var player: FakePlayer = fixture["player"]
	var panel: Control = _choice_panel(adapter)
	var reward_counter := RewardSignalCounter.new()
	EventBus.reward_selected.connect(reward_counter.record)

	_start_legacy_run(20261003)
	_enter_room(1)
	_clear_room(1)
	var selection_snapshot: Dictionary = adapter._facade.snapshot()
	suite.assert_equal(selection_snapshot["phase"], RunPhaseScript.Value.SELECTION_ACTIVE, "selection death setup opens authoritative selection")
	suite.assert_true(panel.visible, "selection death setup shows the panel")
	suite.assert_equal(player.process_mode, Node.PROCESS_MODE_DISABLED, "selection death setup disables player processing")

	GameState.fail_run("selection-death")
	var terminal_snapshot: Dictionary = adapter._facade.snapshot()
	suite.assert_equal(terminal_snapshot["phase"], RunPhaseScript.Value.DEFEAT, "selection-phase legacy death enters authoritative defeat")
	suite.assert_true(terminal_snapshot["open_offer"].is_empty(), "selection-phase death closes the authoritative offer")
	suite.assert_true(not panel.visible, "selection-phase death closes the choice panel")
	suite.assert_equal(player.process_mode, Node.PROCESS_MODE_INHERIT, "selection-phase death restores player processing")
	suite.assert_equal(player.applied_definitions.size(), 0, "selection-phase death applies no reward")
	suite.assert_equal(reward_counter.count, 0, "selection-phase death advances no room")

	if EventBus.reward_selected.is_connected(reward_counter.record):
		EventBus.reward_selected.disconnect(reward_counter.record)
	await _destroy_fixture(fixture)


func _create_fixture(adapter_enabled: bool, adapter_manifest_path: String) -> Dictionary:
	var host := Node.new()
	host.name = "Fixture"
	add_child(host)

	var room := Node.new()
	room.name = "RoomController"
	host.add_child(room)
	var player := FakePlayer.new()
	player.name = "Player"
	room.add_child(player)
	for view_name: String in ["RewardSelection", "CurseSelection", "EventSelection"]:
		var legacy_view := Node.new()
		legacy_view.name = view_name
		room.add_child(legacy_view)

	var adapter = LegacyRunAdapterScript.new()
	adapter.name = "LegacyRunAdapter"
	adapter.enabled = adapter_enabled
	adapter.room_controller_path = NodePath("../RoomController")
	adapter.manifest_path = adapter_manifest_path
	host.add_child(adapter)
	await get_tree().process_frame
	await get_tree().process_frame
	return {
		"host": host,
		"room": room,
		"player": player,
		"adapter": adapter,
	}


func _destroy_fixture(fixture: Dictionary) -> void:
	get_tree().paused = false
	var host: Node = fixture.get("host")
	if host != null and is_instance_valid(host):
		host.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_reset_legacy_state()


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


func _start_legacy_run(seed_value: int) -> void:
	GameState.start_run({
		"character_id": "wanderer",
		"weapon_id": "sword",
		"difficulty": "normal",
		"seed": seed_value,
	})


func _enter_room(room_number: int) -> void:
	GameState.current_room = room_number
	EventBus.room_started.emit(StringName("combat_room_01_%02d" % room_number))


func _clear_room(room_number: int) -> void:
	EventBus.room_cleared.emit(StringName("combat_room_01_%02d" % room_number))


func _assert_rejected_offer_stays_open(
	suite,
	adapter: Node,
	panel: Control,
	expected_offer: Dictionary,
	label: String
) -> void:
	var snapshot: Dictionary = adapter._facade.snapshot()
	suite.assert_equal(snapshot["open_offer"], expected_offer, "%s keeps canonical offer open" % label)
	suite.assert_true(panel.visible, "%s keeps choice panel visible" % label)
	for button: Button in _option_buttons(panel):
		suite.assert_true(not button.disabled, "%s re-enables choice buttons" % label)


func _choice_layer_count(adapter: Node) -> int:
	return adapter.get_children().filter(func(child: Node) -> bool: return child is CanvasLayer).size()


func _choice_panel(adapter: Node) -> Control:
	return adapter.get_node_or_null("ChoiceLayer/ChoicePanelV2") as Control


func _legacy_view_count(room: Node) -> int:
	var count := 0
	for view_name: String in ["RewardSelection", "CurseSelection", "EventSelection"]:
		if room.get_node_or_null(view_name) != null:
			count += 1
	return count


func _option_buttons(panel: Control) -> Array[Button]:
	var buttons: Array[Button] = []
	var container := panel.get_node("SafeArea/Center/PanelRoot/Content/OptionsContainer")
	for child: Node in container.get_children():
		if child is Button:
			buttons.append(child as Button)
	return buttons


func _find_option_id(offer: Dictionary, expected_id: String) -> String:
	for option: Dictionary in offer.get("options", []):
		if str(option.get("option_id", "")) == expected_id:
			return expected_id
	return ""
