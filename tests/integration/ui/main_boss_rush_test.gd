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
	var coordinator: Node = main.get_node_or_null("BossRushCoordinator")
	suite.assert_true(coordinator != null, "actual Main exposes a usable native Boss Rush coordinator")
	if coordinator == null:
		main.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var hub: Node = main.get_node("HubFlowCoordinator")
	suite.assert_true(hub.travel("hub_council").ok and hub.open_function("gateway").ok, "actual authored gateway opens in the council district")
	var launch: Button
	for action: Control in hub.panel_view().action_controls():
		if action.get_meta("action_id", "") == "boss_rush":
			launch = action as Button
	suite.assert_true(launch != null, "native gateway has a real Boss Rush command")
	if launch == null:
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	launch.pressed.emit()
	await get_tree().process_frame
	suite.assert_true(coordinator.is_open() and not hub.is_hub_visible(), "actual gateway opens the mode surface")
	var start: Button = coordinator.panel().action_controls()[0]
	var retired: Callable = start.pressed.get_connections()[0].callable
	start.pressed.emit()
	await get_tree().process_frame
	var flow: Node = coordinator.runtime()
	var playing: bool = flow.is_active() and flow.current_player() != null and not coordinator.panel().visible
	suite.assert_true(playing, "actual start control enters native combat: " + str([flow.snapshot(), flow.get("_native_failure"), coordinator.panel().error_label.text, coordinator.is_open()]))
	if not playing:
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var launch_id: String = flow.snapshot().run_id
	retired.call()
	suite.assert_equal(flow.snapshot().run_id, launch_id, "retired native start control cannot restart an active challenge")
	for _frame: int in range(3):
		await get_tree().physics_frame
	var pause := InputEventJoypadButton.new()
	pause.button_index = JOY_BUTTON_START
	pause.pressed = true
	suite.assert_true(coordinator.handle_input(pause) and coordinator.panel().visible, "actual mapped controller Start pauses native mode")
	var paused: Dictionary = flow.snapshot()
	for _frame: int in range(3):
		await get_tree().physics_frame
	suite.assert_equal(flow.snapshot(), paused, "controller pause freezes authoritative timer")
	suite.assert_true(coordinator.panel().action_controls()[0].has_focus(), "controller pause restores an actionable native focus")
	coordinator.panel().action_controls()[0].pressed.emit()
	flow.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
	flow.current_player().health.lose_health(100000)
	await get_tree().process_frame
	await get_tree().process_frame
	suite.assert_true(flow.has_pending_save() and coordinator.panel().visible and not coordinator.return_to_hub().ok, "actual death save fault exposes retry and prevents losing pending result")
	flow.set_fault_injector(Callable())
	coordinator.panel().action_controls()[0].pressed.emit()
	suite.assert_true(not flow.has_pending_save() and flow.snapshot().status == "DEFEAT" and coordinator.panel().visible, "actual retry control commits saved mode death summary")
	suite.assert_true(coordinator.return_to_hub().ok, "mode summary returns through real Hub workflow")
	suite.assert_true(hub.is_hub_visible() and not coordinator.is_open(), "mode exit restores actual Hub interaction")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
