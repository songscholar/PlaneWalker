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
	var endless: Node = main.get_node_or_null("EndlessCoordinator")
	var platform: Control = main.get_node_or_null("PlatformLayer/PlatformPanel")
	suite.assert_true(endless != null and platform != null, "actual Main installs Endless and offline platform controls")
	if endless == null or platform == null:
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var hub: Node = main.get_node("HubFlowCoordinator")
	var profile: Dictionary = GameState.profile_runtime_service().snapshot()
	suite.assert_true(hub.open_function("gateway").ok, "actual gateway opens mode controls")
	var entry := _action(hub.panel_view(), "endless")
	suite.assert_true(entry != null, "portal includes real Endless entry")
	if entry != null:
		var retired: Callable = entry.pressed.get_connections()[0].callable
		entry.pressed.emit()
		await get_tree().process_frame
		suite.assert_true(endless.is_open() and not hub.is_hub_visible(), "Endless owns interaction after portal selection")
		suite.assert_true(FocusCoordinator.active_scope() == endless.panel() and main.call("_content_mutation_locked"), "Endless binds content and owns controller scope")
		suite.assert_true(endless.return_to_hub().ok and hub.is_hub_visible(), "Endless menu safely returns to native Hub")
		retired.call()
		suite.assert_true(not endless.is_open(), "retired portal callback cannot reopen mode")
	suite.assert_true(hub.travel("hub_rift").ok and hub.open_function("mirror").ok, "actual mirror opens community controls")
	entry = _action(hub.panel_view(), "platform")
	suite.assert_true(entry != null, "mirror contains native offline platform entry")
	if entry != null:
		entry.pressed.emit()
		await get_tree().process_frame
		suite.assert_true(platform.visible and not hub.is_hub_visible(), "platform panel replaces Hub interaction")
		suite.assert_true(FocusCoordinator.active_scope() == platform and main.call("_content_mutation_locked"), "platform backup binds profile content and owns controller scope")
		var coordinator: RefCounted = platform.coordinator()
		var before: Dictionary = coordinator.snapshot()
		suite.assert_true(before.model.status == "OFFLINE", "missing external account exposes working offline provider")
		suite.assert_true(platform.submit_command("backup_profile", {}, int(before.revision)).ok, "actual Main Profile backs up into durable local platform store")
		var cancel := InputEventJoypadButton.new()
		cancel.button_index = JOY_BUTTON_B
		cancel.pressed = true
		Input.parse_input_event(cancel)
		await get_tree().process_frame
		cancel.pressed = false
		Input.parse_input_event(cancel)
		await get_tree().process_frame
		suite.assert_true(not platform.visible and hub.is_hub_visible() and hub.panel_view().visible, "controller cancel restores native mirror")
		suite.assert_true(FocusCoordinator.active_scope() == hub.panel_view() and not main.call("_content_mutation_locked"), "mirror regains focus and releases content lock")
	suite.assert_equal(GameState.profile_runtime_service().snapshot(), profile, "opening modes and platform backup preserve source progression")
	var visual_dir := OS.get_environment("PLANEWALKER_PRODUCT_MODES_VISUAL_OUTPUT")
	if not visual_dir.is_empty():
		main.call("_open_platform")
		DirAccess.make_dir_recursive_absolute(visual_dir)
		for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
			DisplayServer.window_set_size(resolution)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var capture := get_viewport().get_texture().get_image()
			suite.assert_true(capture.save_png(visual_dir.path_join("platform-%dx%d.png" % [resolution.x, resolution.y])) == OK, "native platform framebuffer retains supported resolution")
		platform.close_panel()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _action(panel: Control, id: String) -> Button:
	for action: Control in panel.action_controls():
		if str(action.get_meta("action_id", "")) == id:
			return action as Button
	return null
