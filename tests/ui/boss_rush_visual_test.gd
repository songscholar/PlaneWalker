extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var screenshots := OS.get_cmdline_user_args().has("--boss-rush-screenshots")
	for locale: String in ["en", "zh_CN"]:
		for scale: float in [1.0, 1.5]:
			GameState.persistent.settings.locale = locale
			GameState.persistent.settings.text_scale = scale
			for size: Vector2i in RESOLUTIONS:
				var viewport := SubViewport.new()
				viewport.size = size
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var main := Main.instantiate()
				viewport.add_child(main)
				var hub: Node = main.get_node("HubFlowCoordinator")
				suite.assert_true(hub.travel("hub_council").ok and hub.open_function("gateway").ok, "native mode gateway opens for visual QA")
				_action(hub.panel_view(), "boss_rush").pressed.emit()
				var coordinator: Node = main.get_node("BossRushCoordinator")
				await _capture(suite, coordinator, viewport, "menu", locale, scale, screenshots)
				var start := _action(coordinator.panel(), "start")
				suite.assert_true(start.has_focus(), "native mode command receives controller focus")
				start.pressed.emit()
				for _frame: int in range(5):
					await get_tree().physics_frame
				var flow: Node = coordinator.runtime()
				suite.assert_true(flow.is_active() and not coordinator.panel().visible, "visual mode enters actual combat")
				await _capture(suite, coordinator, viewport, "combat", locale, scale, screenshots)
				var pause := InputEventJoypadButton.new()
				pause.button_index = JOY_BUTTON_START
				pause.pressed = true
				suite.assert_true(coordinator.handle_input(pause) and coordinator.panel().visible, "bound pause action opens focusable mode controls")
				var before: Dictionary = flow.snapshot()
				await _capture(suite, coordinator, viewport, "pause", locale, scale, screenshots)
				suite.assert_equal(flow.snapshot(), before, "native paused visual state never accrues combat frames")
				_action(coordinator.panel(), "resume").pressed.emit()
				for index: int in range(5):
					for _frame: int in range(3):
						await get_tree().physics_frame
					flow.current_boss().health.lose_health(100000, flow.current_player())
					await get_tree().process_frame
					await get_tree().process_frame
					if index < 4:
						_action(coordinator.panel(), "next").pressed.emit()
				suite.assert_true(flow.snapshot().status == "VICTORY" and coordinator.panel().visible, "actual native five-stage victory projects mode summary")
				await _capture(suite, coordinator, viewport, "victory", locale, scale, screenshots)
				suite.assert_true(coordinator.return_to_hub().ok and hub.is_hub_visible(), "native result returns to usable Hub")
				viewport.queue_free()
				await get_tree().process_frame
				await get_tree().process_frame
	suite.finish(get_tree())


func _action(panel: Control, id: String) -> Button:
	for control: Control in panel.action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null


func _capture(suite: RefCounted, coordinator: Node, viewport: SubViewport, id: String, locale: String, scale: float, screenshots: bool) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport.size))
	for control: Control in coordinator.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree() or control is ScrollContainer:
			continue
		var parent := control.get_parent()
		var scroll_child := false
		while parent != null and parent != coordinator:
			scroll_child = scroll_child or parent is ScrollContainer
			parent = parent.get_parent()
		if scroll_child:
			continue
		suite.assert_true(bounds.encloses(control.get_global_rect()), "mode chrome stays within viewport " + str([id, locale, scale, viewport.size, control.name]))
		if control is Button or control is Label:
			suite.assert_true(control.get_combined_minimum_size().x <= control.size.x + 1 and control.get_combined_minimum_size().y <= control.size.y + 1, "localized mode chrome fits " + str([id, locale, scale, viewport.size, control.name]))
	if not screenshots:
		return
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	suite.assert_true(pixels != null and not pixels.is_empty(), "native challenge renders real raster")
	if pixels == null or pixels.is_empty():
		return
	var colors: Dictionary = {}
	for y: int in range(0, pixels.get_height(), 4):
		for x: int in range(0, pixels.get_width(), 4):
			colors[pixels.get_pixel(x, y).to_rgba32()] = true
			if colors.size() > 16: break
		if colors.size() > 16: break
	suite.assert_true(colors.size() > 8, "native challenge screenshot is nonblank")
	var path := "res://build/p21a-boss-rush-screenshots/%s-%s-%s-%dx%d.png" % [id, locale, str(scale), viewport.size.x, viewport.size.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	suite.assert_equal(pixels.save_png(path), OK, "native mode raster retained")
