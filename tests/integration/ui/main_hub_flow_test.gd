extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var hub: Node = main.get_node_or_null("HubFlowCoordinator")
	suite.assert_true(hub != null, "production Main must show the actual native Hub coordinator")
	if hub == null or hub.view_state().is_empty():
		suite.assert_true(hub != null and not hub.view_state().is_empty(), "native Hub requires an authoritative validated state")
		main.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	suite.assert_true(hub.is_hub_visible(), "fresh production first screen is the playable Hub")
	suite.assert_true(not main.get_node("StartMenu").visible, "compatibility entry does not cover the production Hub")
	Input.parse_input_event(_controller(JOY_BUTTON_BACK, true))
	await get_tree().process_frame
	Input.parse_input_event(_controller(JOY_BUTTON_BACK, false))
	suite.assert_equal(FocusCoordinator.active_scope(), hub, "physical controller Back enters the native Hub toolbar")
	Input.parse_input_event(_controller(JOY_BUTTON_B, true))
	await get_tree().process_frame
	Input.parse_input_event(_controller(JOY_BUTTON_B, false))
	suite.assert_true(FocusCoordinator.active_scope() == null, "physical controller cancel returns to Hub movement")
	var service: RefCounted = GameState.profile_runtime_service()
	var initial: Dictionary = service.snapshot()
	for district: String in ["hub_council", "hub_craft", "hub_rift"]:
		var traveled = hub.travel(district)
		suite.assert_true(traveled.ok, "native travel installs authored district " + district)
		suite.assert_equal(hub.scene_host().get_child_count(), 1, "only one district remains loaded")
		var state: Dictionary = hub.view_state()
		for row: Dictionary in state.functions:
			if row.district_id != district:
				continue
			var opened = hub.open_function(str(row.id))
			suite.assert_true(opened.ok, "actual function opens " + str(row.id))
			suite.assert_true(hub.panel_view().visible, "native function panel is visible")
			suite.assert_equal(hub.panel_view().view_state().panel_id, row.panel_id, "native panel matches authoritative function")
			hub.close_panel()
	suite.assert_equal(service.snapshot(), initial, "navigation through nine functions does not write Profile state")
	suite.assert_true(hub.travel("hub_craft").ok and hub.open_function("training").ok, "native training destination exposes real lessons")
	for control: Control in hub.panel_view().action_controls():
		if str(control.get_meta("action_id", "")) == "tutorial":
			control.pressed.emit()
			break
	var tutorial: Node = main.get_node_or_null("TutorialFlow")
	suite.assert_true(tutorial != null and tutorial.review_panel().visible, "actual training entry opens the owned native lesson panel")
	if tutorial != null:
		tutorial.close()
	suite.assert_equal(service.snapshot(), initial, "lesson review does not grant currency or mark actions complete")
	var gateway = hub.travel("hub_council")
	suite.assert_true(gateway.ok and hub.open_function("gateway").ok, "actual gateway opens owned launch selection")
	var launch: Button
	for control: Control in hub.panel_view().action_controls():
		if str(control.get_meta("action_id", "")) == "launch":
			launch = control as Button
	suite.assert_true(launch != null and not launch.disabled, "gateway exposes an available owned launch command")
	if launch != null:
		var retired_callback: Callable = launch.pressed.get_connections()[0].callable
		launch.pressed.emit()
		retired_callback.call()
		await get_tree().process_frame
		suite.assert_true(not hub.is_hub_visible(), "successful native launch retires Hub presentation")
		suite.assert_equal(service.snapshot().launch_sequence, 1, "actual gateway starts exactly one durable launch")
		suite.assert_equal(service.snapshot().launch_sequence, 1, "retired gateway command cannot launch twice")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _controller(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	return event
