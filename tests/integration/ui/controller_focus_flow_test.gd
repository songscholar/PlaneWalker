extends Node

const FixturesScript := preload("res://scripts/ui/fixtures/selection_offer_fixtures.gd")
const MainScene := preload("res://scenes/main.tscn")
const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class AcceptingCandidatePlayer:
	extends Node

	func configure_loadout(_config: Dictionary) -> bool:
		return true


class PartialFailureRuntime:
	extends Node

	signal room_started(room_id: StringName, revision: int)
	signal room_cleared(room_id: StringName, revision: int)
	signal terminal_committed(context: Dictionary, revision: int)
	signal runtime_failed(context: Dictionary)

	func begin_current_room() -> Variant:
		return CommandResultScript.failure(&"INVALID_PHASE", 2, {"operation": "begin_current_room"})


class PartialFailureFacade:
	extends RefCounted

	var config: Dictionary = {}
	var run_id := ""
	var revision := 0
	var phase := RunPhaseScript.Value.HUB
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

	func create_room_runtime(_runner: Node) -> Node:
		return PartialFailureRuntime.new()

	func encounter_catalog() -> RefCounted:
		return catalog

	func player_died(_context: Dictionary) -> Variant:
		revision += 1
		phase = RunPhaseScript.Value.DEFEAT
		return CommandResultScript.success(revision)

	func advance_time(_delta_seconds: float) -> Variant:
		return CommandResultScript.failure(&"TERMINAL_STATE", revision)


class PartialFailureRoomController:
	extends Node

	var runner := Node.new()

	func _init() -> void:
		add_child(runner)

	func encounter_runner() -> Node:
		return runner

	func configure_authored_runtime(_runtime: Node, _catalog: RefCounted) -> bool:
		return true


var _restart_requested := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	get_window().size = Vector2i(640, 360)
	await _assert_terminal_candidate_fallback(suite)
	var main := MainScene.instantiate()
	add_child(main)
	await _frames(3)

	var start_button := main.get_node("StartMenu/Panel/Margin/VBox/StartButton") as Button
	var candidate_button := main.get_node("StartMenu/Panel/Margin/VBox/CandidateButton") as Button
	var launch_button := main.get_node("StartMenu/Panel/Margin/VBox/LaunchButton") as Button
	var candidate_panel := main.get_node("CandidateLabLayer/CandidateLoadoutPanel") as Control
	var launch_panel := main.get_node("LaunchLoadoutLayer/LaunchLoadoutPanel") as Control
	suite.assert_equal(get_viewport().gui_get_focus_owner(), start_button, "start flow enters on Quick Start")
	_send_action(&"ui_down")
	await _frames(2)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), candidate_button, "start flow reaches Candidate Lab")
	_send_action(&"ui_accept")
	await _frames(3)
	suite.assert_true(candidate_panel.visible, "controller opens Candidate Lab")
	var candidate_buttons: Array[Button] = [
		candidate_panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/BowButton") as Button,
		candidate_panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/RiftButton") as Button,
		candidate_panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/AccelerateButton") as Button,
		candidate_panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/BackButton") as Button,
	]
	suite.assert_equal(get_viewport().gui_get_focus_owner(), candidate_buttons[0], "candidate flow enters on Bow")
	_send_action(&"interact")
	await _frames(2)
	suite.assert_true(main.get_node("StartMenu").visible, "interact cannot bypass Candidate Lab into Quick Start")
	suite.assert_true(candidate_panel.visible, "interact leaves Candidate Lab open")
	suite.assert_true(not main.get_node("CombatRoom01").visible, "interact does not start hidden M1 combat")
	main.call("_start_candidate_run", {
		"schema_version": 1,
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "unknown_candidate",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
	})
	await _frames(3)
	suite.assert_true(candidate_panel.visible, "rejected candidate start leaves the panel open")
	suite.assert_true(main.get_node("StartMenu").visible, "rejected candidate start preserves the start menu")
	suite.assert_true(not main.get_node("CombatRoom01").visible, "rejected candidate start restores hidden combat")
	suite.assert_equal(
		(candidate_panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/StatusLabel") as Label).text,
		tr("UI_CANDIDATE_START_REJECTED"),
		"rejected candidate start shows the localized error"
	)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), candidate_buttons[0], "rejected candidate start restores usable preset focus")
	for index: int in range(1, candidate_buttons.size()):
		_send_action(&"ui_down")
		await _frames(2)
		suite.assert_equal(get_viewport().gui_get_focus_owner(), candidate_buttons[index], "candidate focus reaches option %d" % (index + 1))
	_send_action(&"ui_down")
	await _frames(2)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), candidate_buttons[0], "candidate focus wraps from Back to Bow")
	_send_action(&"ui_cancel")
	await _frames(3)
	suite.assert_true(not candidate_panel.visible, "candidate cancel closes the panel")
	suite.assert_equal(get_viewport().gui_get_focus_owner(), candidate_button, "candidate cancel restores Candidate Lab focus")
	_send_action(&"ui_down")
	await _frames(2)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), launch_button, "start flow reaches Launch Loadout after Candidate Lab")
	_send_action(&"ui_accept")
	await _frames(3)
	suite.assert_true(launch_panel.visible, "controller opens Launch Loadout")
	suite.assert_equal(
		get_viewport().gui_get_focus_owner(),
		launch_panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/WeaponOption"),
		"Launch flow enters on the weapon selector"
	)
	_send_action(&"interact")
	await _frames(2)
	suite.assert_true(launch_panel.visible, "interact cannot bypass Launch Loadout into Quick Start")
	suite.assert_true(main.get_node("StartMenu").visible, "Launch modal preserves Start until a loadout is confirmed")
	_send_action(&"ui_cancel")
	await _frames(3)
	suite.assert_true(not launch_panel.visible, "Launch cancel closes the panel")
	suite.assert_equal(get_viewport().gui_get_focus_owner(), launch_button, "Launch cancel restores Launch button focus")
	var language_button := main.get("_lang_button") as Button
	_send_action(&"ui_down")
	await _frames(2)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), language_button, "start flow reaches Language after Launch Loadout")
	_send_action(&"ui_down")
	await _frames(2)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), start_button, "start focus ring wraps Language to Quick Start")
	_send_action(&"ui_down")
	await _frames(2)
	_send_action(&"ui_accept")
	await _frames(3)
	suite.assert_true(candidate_panel.visible, "Candidate Lab can reopen after focus restoration")
	_send_action(&"ui_accept")
	await _frames(4)
	suite.assert_true(not candidate_panel.visible, "successful candidate start closes the candidate panel")
	suite.assert_true(not main.get_node("StartMenu").visible, "successful candidate start closes Start")
	suite.assert_true(main.get_node("CombatRoom01").visible, "successful candidate start enters combat")
	var candidate_snapshot: Dictionary = main.get_node("RunRuntimeHost").call("runtime_snapshot")
	var candidate_config: Dictionary = candidate_snapshot.get("config", {})
	suite.assert_equal(candidate_config.get("milestone"), "NEXT", "candidate start uses milestone NEXT")
	suite.assert_equal(candidate_config.get("character_id"), "wanderer", "candidate start uses Wanderer")
	suite.assert_equal(candidate_config.get("weapon_id"), "bow", "Bow candidate reaches the runtime host")
	suite.assert_equal(candidate_config.get("enabled_time_skills"), ["stop", "rewind"], "Bow candidate keeps its frozen time pair")
	suite.assert_true(candidate_config.has("seed"), "Main supplies the candidate seed")
	suite.assert_true(candidate_config.has("accessibility_assists"), "Main supplies candidate accessibility assists")
	await get_tree().create_timer(0.5, true, false, true).timeout
	main.queue_free()
	await _frames(4)

	main = MainScene.instantiate()
	add_child(main)
	await _frames(3)
	start_button = main.get_node("StartMenu/Panel/Margin/VBox/StartButton") as Button
	suite.assert_equal(get_viewport().gui_get_focus_owner(), start_button, "fresh start flow still enters on Quick Start")
	_send_action(&"ui_accept")
	await _frames(4)
	suite.assert_true(not main.get_node("StartMenu").visible, "ui_accept starts the run from Start")
	suite.assert_true(main.get_node("CombatRoom01").visible, "starting by controller enters the run")
	# Let the first encounter's real 0.45-second telegraph complete before this
	# test later disposes Main; cancelling its awaited timer mid-flight leaks it.
	await get_tree().create_timer(0.5, true, false, true).timeout

	var choice_panel := main.get_node("RunRuntimeHost/ChoiceLayer/ChoicePanelV2") as Control
	var offer := FixturesScript.load_fixture("res://tests/fixtures/ui/choice_item_three.json")
	suite.assert_true(choice_panel.call("render", offer).ok, "choice fixture opens")
	await _frames(3)
	var options_container := choice_panel.get_node("SafeArea/Center/PanelRoot/Content/OptionsContainer")
	var choice_buttons: Array[Button] = []
	for child: Node in options_container.get_children():
		if child is Button:
			choice_buttons.append(child as Button)
	var first_choice := choice_buttons[0]
	suite.assert_equal(get_viewport().gui_get_focus_owner(), first_choice, "choice flow focuses the first option")
	for index: int in range(1, choice_buttons.size()):
		_send_action(&"ui_right")
		await _frames(2)
		suite.assert_equal(
			get_viewport().gui_get_focus_owner(),
			choice_buttons[index],
			"ui_right reaches choice %d" % (index + 1)
		)
	_send_action(&"ui_right")
	await _frames(2)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), first_choice, "choice focus ring wraps to the first option")

	var pause_menu := main.get_node("PauseMenu")
	_send_action(&"pause")
	await _frames(3)
	var resume_button := main.get_node("PauseMenu/Panel/Margin/VBox/ResumeButton") as Button
	suite.assert_true(get_tree().paused, "pause input pauses the active run")
	suite.assert_true(pause_menu.visible, "pause input opens the pause modal")
	suite.assert_equal(get_viewport().gui_get_focus_owner(), resume_button, "pause modal focuses Resume")
	_send_action(&"ui_cancel")
	await _frames(3)
	suite.assert_true(not get_tree().paused, "pause cancel resumes the active run")
	suite.assert_true(not pause_menu.visible, "pause cancel closes the pause modal")
	suite.assert_equal(get_viewport().gui_get_focus_owner(), first_choice, "closing pause restores the active choice")

	choice_panel.call("show_rejection", "CHOICE_REJECTED_RETRY")
	first_choice.release_focus()
	await get_tree().process_frame
	choice_panel.call("show_rejection", "CHOICE_REJECTED_RETRY")
	await _frames(3)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), first_choice, "choice rejection recovers the first enabled option")

	_send_action(&"pause")
	await _frames(3)
	_send_action(&"ui_down")
	await _frames(2)
	var settings_button := main.get_node("PauseMenu/Panel/Margin/VBox/SettingsButton") as Button
	suite.assert_equal(get_viewport().gui_get_focus_owner(), settings_button, "controller reaches Settings")
	_send_action(&"ui_down")
	await _frames(2)
	var remap_button := main.get_node("PauseMenu/Panel/Margin/VBox/RemapButton") as Button
	suite.assert_equal(get_viewport().gui_get_focus_owner(), remap_button, "controller reaches Remap")
	_send_action(&"ui_accept")
	await _frames(3)
	var remap_panel := main.get_node("InputRemapLayer/InputRemapPanel") as Control
	suite.assert_true(remap_panel.visible, "pause opens the input remap panel")
	var first_binding := remap_panel.get_node("SafeArea/PanelRoot/Layout/Scroll/Rows").get_child(0).get_node("KeyboardMouseBinding") as Button
	suite.assert_equal(get_viewport().gui_get_focus_owner(), first_binding, "remap modal focuses the first binding")
	_send_action(&"ui_cancel")
	await _frames(3)
	suite.assert_true(get_tree().paused, "closing remap with cancel keeps the run paused")
	suite.assert_true(not remap_panel.visible, "cancel closes only the remap modal")
	suite.assert_equal(get_viewport().gui_get_focus_owner(), remap_button, "closing remap restores the Remap button")

	_send_action(&"ui_up")
	await _frames(2)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), settings_button, "controller returns to Settings")
	_send_action(&"ui_accept")
	await _frames(3)
	var settings_panel := main.get_node("AccessibilitySettingsLayer/AccessibilitySettingsPanel") as Control
	suite.assert_true(settings_panel.visible, "pause opens the accessibility settings panel")
	var first_setting := settings_panel.call("get_setting_control", "master_volume") as Control
	suite.assert_equal(get_viewport().gui_get_focus_owner(), first_setting, "settings modal focuses the first control")
	_send_action(&"ui_cancel")
	await _frames(3)
	suite.assert_true(get_tree().paused, "closing settings with cancel keeps the run paused")
	suite.assert_true(not settings_panel.visible, "cancel closes only the settings modal")
	suite.assert_equal(get_viewport().gui_get_focus_owner(), settings_button, "closing settings restores the Settings button")
	_send_action(&"ui_cancel")
	await _frames(3)
	suite.assert_true(not get_tree().paused, "closing the pause layer resumes after child modals")
	suite.assert_equal(get_viewport().gui_get_focus_owner(), first_choice, "nested modal flow restores the active choice")

	var config: Dictionary = main.call("_build_run_config")
	var assists: Dictionary = config.get("accessibility_assists", {})
	suite.assert_equal(assists.get("damage_received_multiplier"), GameState.get_setting("damage_received_multiplier", 1.0), "run config records damage assist")
	suite.assert_equal(assists.get("enemy_telegraph_scale"), GameState.get_setting("enemy_telegraph_scale", 1.0), "run config records telegraph assist")

	EventBus.run_ended.emit("controller-focus-test", {
		"result": "death",
		"current_room": 1,
		"rooms_cleared": 0,
		"kills": 0,
		"run_time": 1.0,
		"rewards": [],
		"blessings": [],
		"talent_choices": [],
		"curses": [],
	}, 1)
	await _frames(3)
	var restart_button := main.get_node("RunEndOverlay/Panel/Margin/VBox/RestartButton") as Button
	suite.assert_equal(get_viewport().gui_get_focus_owner(), restart_button, "result modal focuses Restart")
	var run_end_overlay := main.get_node("RunEndOverlay")
	var production_restart := Callable(run_end_overlay, "_restart_run")
	suite.assert_true(
		restart_button.pressed.is_connected(production_restart),
		"result controller action is wired to the production restart path"
	)
	# Reloading the current scene would reload this test harness recursively. Replace
	# only that boundary after proving the production handler is connected, then use
	# the real controller event and recreate Main to verify the destination state.
	restart_button.pressed.disconnect(production_restart)
	restart_button.pressed.connect(_on_test_restart_requested, CONNECT_ONE_SHOT)
	_send_action(&"ui_accept")
	await _frames(3)
	suite.assert_true(_restart_requested, "result ui_accept reaches the restart boundary")
	main.queue_free()
	await _frames(4)
	var restarted_main := MainScene.instantiate()
	add_child(restarted_main)
	await _frames(3)
	var restarted_start := restarted_main.get_node("StartMenu/Panel/Margin/VBox/StartButton") as Button
	suite.assert_true(restarted_main.get_node("StartMenu").visible, "result restart returns the flow to Start")
	suite.assert_equal(get_viewport().gui_get_focus_owner(), restarted_start, "result restart restores Start focus")
	restarted_main.queue_free()
	await _frames(4)
	suite.finish(get_tree())


func _assert_terminal_candidate_fallback(suite) -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await _frames(3)
	var host := main.get_node("RunRuntimeHost")
	var candidate_button := main.get_node("StartMenu/Panel/Margin/VBox/CandidateButton") as Button
	var candidate_panel := main.get_node("CandidateLabLayer/CandidateLoadoutPanel") as Control
	var real_room_controller: Node = host.get("_room_controller")
	var real_player: Node = host.get("_player")
	var failing_facade := PartialFailureFacade.new()
	var accepting_player := AcceptingCandidatePlayer.new()
	var failing_controller := PartialFailureRoomController.new()
	host.set("_facade", failing_facade)
	host.set("_active_run_id", "")
	host.set("_player", accepting_player)
	host.set("_room_controller", failing_controller)
	candidate_panel.call("open_panel", candidate_button)
	await _frames(2)
	main.call("_start_candidate_run", {
		"schema_version": 1,
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
	})
	await _frames(2)
	suite.assert_true(candidate_panel.visible, "partial candidate failure leaves Candidate Lab open")
	suite.assert_true(
		RunPhaseScript.is_terminal(int((host.call("runtime_snapshot") as Dictionary).get("phase", -1))),
		"partial candidate failure leaves the host terminal"
	)
	host.set("_room_controller", real_room_controller)
	host.set("_player", real_player)
	accepting_player.free()
	failing_controller.free()
	candidate_panel.call("close_panel")
	await _frames(2)
	suite.assert_true(main.get_node("StartMenu").visible, "closing failed Candidate Lab returns to Start")

	var previous_current_scene := get_tree().current_scene
	get_tree().current_scene = null
	var interact := InputEventAction.new()
	interact.action = &"interact"
	interact.pressed = true
	main.call("_unhandled_input", interact)
	get_tree().current_scene = previous_current_scene
	await _frames(4)
	var snapshot: Dictionary = host.call("runtime_snapshot")
	var config: Dictionary = snapshot.get("config", {})
	suite.assert_equal(config.get("milestone"), "M1", "one interact starts the M1 Quick Start after terminal candidate failure")
	suite.assert_equal(config.get("character_id"), "wanderer", "terminal candidate fallback keeps Quick Start Wanderer")
	suite.assert_equal(config.get("weapon_id"), "sword", "terminal candidate fallback keeps Quick Start Sword")
	suite.assert_equal(config.get("enabled_time_skills"), ["stop", "rewind"], "terminal candidate fallback keeps Stop plus Rewind")
	suite.assert_true(not main.get_node("StartMenu").visible, "single fallback interact hides Start")
	suite.assert_true(main.get_node("CombatRoom01").visible, "single fallback interact enters combat")
	if main.get_node("CombatRoom01").visible:
		await get_tree().create_timer(0.5, true, false, true).timeout
	main.queue_free()
	await _frames(4)


func _frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _send_action(action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)


func _on_test_restart_requested() -> void:
	_restart_requested = true
