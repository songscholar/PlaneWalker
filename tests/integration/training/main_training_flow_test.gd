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
	var training: Node = main.get_node_or_null("TrainingFlow")
	suite.assert_true(training != null, "production Main owns the actual native training arena")
	if training == null:
		await _dispose(main)
		suite.finish(get_tree())
		return
	var service: RefCounted = GameState.profile_runtime_service()
	var before: Dictionary = service.snapshot()
	var hub: Node = main.get_node("HubFlowCoordinator")
	suite.assert_true(hub.travel("hub_craft").ok and hub.open_function("training").ok, "actual Hub training destination opens")
	_action(hub.panel_view(), "tutorial").pressed.emit()
	var tutorial: Node = main.get_node("TutorialFlow")
	suite.assert_true(tutorial.review_panel().visible, "actual review exposes authored task selection")
	var task: Button = _action(tutorial.review_panel(), "training:T-05")
	suite.assert_true(task != null and not task.disabled, "actual review exposes Boss conversion practice")
	if task != null and not task.disabled:
		task.pressed.emit()
		suite.assert_true(training.is_training_active() and not hub.is_hub_visible(), "task request opens actual training and retires Hub presentation")
		suite.assert_true(not tutorial.review_panel().visible, "review does not cover the arena")
		suite.assert_true(training.training_player() != main.get_node("CombatRoom01/Player"), "training owns a separate sandbox Player")
		suite.assert_true(service.snapshot().active_launch_receipt.is_empty(), "training cannot consume a launch receipt")
		suite.assert_equal(service.snapshot(), before, "opening an uncompleted arena cannot grant rewards or revise the Profile")
		var pause := InputEventAction.new()
		pause.action = "pause"
		pause.pressed = true
		main._unhandled_input(pause)
		suite.assert_true(not get_tree().paused, "training does not invoke the dungeon pause lifecycle")
		suite.assert_true(training.close().ok, "actual training closes its native participants")
		suite.assert_true(hub.is_hub_visible(), "training exit returns to the same Hub")
		suite.assert_equal(service.snapshot().launch_sequence, before.launch_sequence, "returning from training creates no normal run")
		suite.assert_true(not main._start_hub_training(&"T-01", int(before.revision) - 1), "stale review revision cannot open a new practice")
	await _dispose(main)
	suite.finish(get_tree())


func _dispose(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _action(panel: Control, id: String) -> Button:
	for control: Control in panel.action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null
