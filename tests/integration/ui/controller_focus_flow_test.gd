extends Node

const FixturesScript := preload("res://scripts/ui/fixtures/selection_offer_fixtures.gd")
const MainScene := preload("res://scenes/main.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _restart_requested := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	get_window().size = Vector2i(640, 360)
	var main := MainScene.instantiate()
	add_child(main)
	await _frames(3)

	var start_button := main.get_node("StartMenu/Panel/Margin/VBox/StartButton") as Button
	suite.assert_equal(get_viewport().gui_get_focus_owner(), start_button, "start flow enters on Quick Start")
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
