extends Node

const MainScene := preload("res://scenes/main.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WEAPON_IDS: Array[String] = ["sword", "bow", "gun", "staff", "gauntlets"]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var original_window_size := get_window().size
	get_window().size = Vector2i(640, 360)
	await _test_rejected_launch(suite)
	await _test_real_device_launch(suite)
	for weapon_index: int in range(WEAPON_IDS.size()):
		await _test_launch_weapon(suite, weapon_index, WEAPON_IDS[weapon_index])
	get_window().size = original_window_size
	suite.finish(get_tree())


func _test_rejected_launch(suite) -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await _frames(3)
	var launch_button := main.get_node("StartMenu/Panel/Margin/VBox/LaunchButton") as Button
	var panel := main.get_node("LaunchLoadoutLayer/LaunchLoadoutPanel") as Control
	var weapon_option := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/WeaponOption") as OptionButton
	var status_label := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/StatusLabel") as Label

	launch_button.pressed.emit()
	await _frames(3)
	main.call("_start_launch_run", {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "unknown_launch_weapon",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
	})
	await _frames(4)

	suite.assert_true(panel.visible, "rejected Launch start keeps the loadout panel open")
	suite.assert_true(main.get_node("StartMenu").visible, "rejected Launch start preserves the start menu")
	suite.assert_true(not main.get_node("CombatRoom01").visible, "rejected Launch start restores hidden combat")
	suite.assert_equal(
		main.get_node("CombatRoom01").process_mode,
		Node.PROCESS_MODE_DISABLED,
		"rejected Launch start disables combat processing"
	)
	suite.assert_equal(status_label.text, tr("UI_LAUNCH_START_REJECTED"), "rejected Launch start shows the localized error")
	suite.assert_equal(get_viewport().gui_get_focus_owner(), weapon_option, "rejected Launch start restores weapon focus")

	panel.call("close_panel")
	main.queue_free()
	await _frames(4)


func _test_real_device_launch(suite) -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await _frames(3)
	var launch_button := main.get_node("StartMenu/Panel/Margin/VBox/LaunchButton") as Button
	var panel := main.get_node("LaunchLoadoutLayer/LaunchLoadoutPanel") as Control
	var weapon_option := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/WeaponOption") as OptionButton
	var time_pair_option := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/TimePairOption") as OptionButton
	var start_button := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/StartButton") as Button

	_send_key(KEY_DOWN)
	await _frames(2)
	_send_key(KEY_DOWN)
	await _frames(2)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), launch_button, "real keyboard events reach Launch Loadout")
	_send_mouse_click(launch_button)
	await _frames(3)
	suite.assert_true(panel.visible, "real mouse events open Launch Loadout")
	suite.assert_equal(get_viewport().gui_get_focus_owner(), weapon_option, "mouse-opened Launch flow focuses the weapon selector")

	_send_joy_button(JOY_BUTTON_DPAD_RIGHT)
	await _frames(2)
	suite.assert_equal(weapon_option.selected, 1, "real controller input changes the weapon OptionButton")
	_send_joy_button(JOY_BUTTON_DPAD_DOWN)
	await _frames(2)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), time_pair_option, "real controller input reaches the time-pair OptionButton")
	_send_joy_button(JOY_BUTTON_DPAD_RIGHT)
	await _frames(2)
	_send_joy_button(JOY_BUTTON_DPAD_RIGHT)
	await _frames(2)
	suite.assert_equal(time_pair_option.selected, 2, "real controller input changes the time-pair OptionButton")
	_send_joy_button(JOY_BUTTON_DPAD_DOWN)
	await _frames(2)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), start_button, "real controller input reaches Start Launch Run")
	_send_joy_button(JOY_BUTTON_A)
	await _frames(5)

	suite.assert_true(not panel.visible, "real controller confirmation closes the Launch panel")
	suite.assert_true(not main.get_node("StartMenu").visible, "real controller confirmation closes Start")
	suite.assert_true(main.get_node("CombatRoom01").visible, "real controller confirmation starts combat")
	var snapshot: Dictionary = main.get_node("RunRuntimeHost").call("runtime_snapshot")
	var config: Dictionary = snapshot.get("config", {})
	suite.assert_equal(config.get("weapon_id"), "bow", "real controller weapon selection reaches the runtime host")
	suite.assert_equal(
		config.get("enabled_time_skills"),
		["stop", "accelerate"],
		"real controller time-pair selection reaches the runtime host"
	)

	if main.get_node("CombatRoom01").visible:
		await get_tree().create_timer(0.5, true, false, true).timeout
	main.queue_free()
	await _frames(4)


func _test_launch_weapon(suite, weapon_index: int, weapon_id: String) -> void:

	var main := MainScene.instantiate()
	add_child(main)
	await _frames(3)
	var launch_button := main.get_node("StartMenu/Panel/Margin/VBox/LaunchButton") as Button
	var panel := main.get_node("LaunchLoadoutLayer/LaunchLoadoutPanel") as Control
	var weapon_option := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/WeaponOption") as OptionButton
	var time_pair_option := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/TimePairOption") as OptionButton
	var start_button := panel.get_node("SafeArea/Center/PanelRoot/Margin/Layout/StartButton") as Button

	launch_button.pressed.emit()
	await _frames(3)
	suite.assert_true(panel.visible, "%s: Launch button opens the formal player loadout entry" % weapon_id)
	suite.assert_equal(get_viewport().gui_get_focus_owner(), weapon_option, "%s: Launch entry is controller-focused" % weapon_id)
	weapon_option.select(weapon_index)
	time_pair_option.select(5)
	panel.call("refresh_selection")
	start_button.pressed.emit()
	await _frames(5)

	suite.assert_true(not panel.visible, "%s: accepted Launch selection closes the loadout panel" % weapon_id)
	suite.assert_true(not main.get_node("StartMenu").visible, "%s: accepted Launch selection closes Start" % weapon_id)
	suite.assert_true(main.get_node("CombatRoom01").visible, "%s: accepted Launch selection enters real combat" % weapon_id)
	var host: Node = main.get_node("RunRuntimeHost")
	var snapshot: Dictionary = host.call("runtime_snapshot")
	var config: Dictionary = snapshot.get("config", {})
	suite.assert_equal(config.get("milestone"), "LAUNCH", "%s: formal loadout entry starts Launch content" % weapon_id)
	suite.assert_equal(config.get("character_id"), "wanderer", "%s: formal loadout entry uses the implemented actor" % weapon_id)
	suite.assert_equal(config.get("weapon_id"), weapon_id, "%s is selectable from the player menu" % weapon_id)
	suite.assert_equal(config.get("enabled_time_skills"), ["rift", "accelerate"], "%s: all legal time pairs can reach the runtime host" % weapon_id)
	suite.assert_true(config.has("seed"), "%s: Main supplies the Launch seed" % weapon_id)
	suite.assert_true(config.has("accessibility_assists"), "%s: Main supplies Launch accessibility assists" % weapon_id)
	var player := main.get_node("CombatRoom01/Player")
	var presentation: Dictionary = player.call("weapon_presentation_snapshot")
	suite.assert_equal(presentation.get("weapon_id"), weapon_id, "%s: the selected weapon is active in the real Player" % weapon_id)

	if main.get_node("CombatRoom01").visible:
		await get_tree().create_timer(0.5, true, false, true).timeout
	main.queue_free()
	await _frames(4)


func _frames(count: int) -> void:
	for _index: int in range(count):
		await get_tree().process_frame


func _send_key(keycode: Key) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = keycode
	pressed.pressed = true
	Input.parse_input_event(pressed)
	var released := InputEventKey.new()
	released.keycode = keycode
	released.pressed = false
	Input.parse_input_event(released)


func _send_mouse_click(control: Control) -> void:
	var center := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	Input.parse_input_event(motion)
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.button_mask = MOUSE_BUTTON_MASK_LEFT
	pressed.position = center
	pressed.global_position = center
	pressed.pressed = true
	Input.parse_input_event(pressed)
	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = center
	released.global_position = center
	released.pressed = false
	Input.parse_input_event(released)


func _send_joy_button(button_index: JoyButton) -> void:
	var pressed := InputEventJoypadButton.new()
	pressed.button_index = button_index
	pressed.pressed = true
	Input.parse_input_event(pressed)
	var released := InputEventJoypadButton.new()
	released.button_index = button_index
	released.pressed = false
	Input.parse_input_event(released)
