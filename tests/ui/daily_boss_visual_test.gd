extends "res://tests/integration/ui/main_daily_boss_test.gd"

const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720)]


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var screenshots := OS.get_cmdline_user_args().has("--daily-boss-screenshots")
	for locale: String in ["en", "zh_CN"]:
		for scale: float in [1.0, 1.5]:
			GameState.persistent.settings.locale = locale
			GameState.persistent.settings.text_scale = scale
			for size: Vector2i in RESOLUTIONS:
				_seed_main_profile("visual-%s-%.1f-%dx%d" % [locale, scale, size.x, size.y])
				var viewport := SubViewport.new()
				viewport.size = size
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var main := Main.instantiate()
				viewport.add_child(main)
				var hub: Node = main.get_node("HubFlowCoordinator")
				_suite.assert_true(hub.travel("hub_council").ok and hub.open_function("gateway").ok, "actual daily gateway opens across supported visual combinations")
				_daily_action(hub.panel_view(), "daily_boss").pressed.emit()
				var coordinator: Node = main.get_node("DailyBossCoordinator")
				await _capture_daily(coordinator, viewport, "menu", locale, scale, screenshots)
				var start := _daily_action(coordinator.panel(), "start")
				_suite.assert_true(start.has_focus() and not start.disabled, "actual daily Start is focused and unlocked for earned Profile")
				start.pressed.emit()
				await _frames(5)
				var flow: Node = coordinator.runtime()
				_suite.assert_true(flow.is_active() and not coordinator.panel().visible, "daily visual QA enters actual fixed native Boss")
				await _capture_daily(coordinator, viewport, "combat", locale, scale, screenshots)
				var pause := InputEventJoypadButton.new()
				pause.button_index = JOY_BUTTON_START
				pause.pressed = true
				_suite.assert_true(coordinator.handle_input(pause) and coordinator.panel().visible, "mapped controller pause exposes actual daily controls")
				var frozen: Dictionary = flow.snapshot()
				await _capture_daily(coordinator, viewport, "pause", locale, scale, screenshots)
				_suite.assert_equal(flow.snapshot(), frozen, "visual daily pause preserves authoritative frame count")
				_daily_action(coordinator.panel(), "resume").pressed.emit()
				await _frames(3)
				flow.current_boss().health.lose_health(100000, flow.current_player())
				await get_tree().process_frame
				await get_tree().process_frame
				_suite.assert_true(flow.preview().best.status == "VICTORY" and coordinator.panel().visible, "actual daily Boss terminal renders independent result")
				await _capture_daily(coordinator, viewport, "victory", locale, scale, screenshots)
				_suite.assert_true(coordinator.return_to_hub().ok and hub.is_hub_visible(), "actual daily visual flow returns to Hub")
				viewport.queue_free()
				await get_tree().process_frame
				await get_tree().process_frame
	_suite.finish(get_tree())


func _capture_daily(coordinator: Node, viewport: SubViewport, id: String, locale: String, scale: float, screenshots: bool) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport.size))
	if coordinator.panel().visible:
		for action: Control in coordinator.panel().action_controls():
			_suite.assert_true(bounds.encloses(action.get_global_rect()), "actual daily action remains visible without calendar scrolling " + str([id, locale, scale, viewport.size, action.get_meta("action_id", "back")]))
		if id == "pause":
			_suite.assert_equal(coordinator.panel().back_button.text, tr("UI_DAILY_ABANDON_RETURN"), "active daily return explicitly identifies the consumed attempt")
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
		_suite.assert_true(bounds.encloses(control.get_global_rect()), "native daily chrome remains within viewport " + str([id, locale, scale, viewport.size, control.name]))
		if control is Button or control is Label:
			_suite.assert_true(control.get_combined_minimum_size().x <= control.size.x + 1 and control.get_combined_minimum_size().y <= control.size.y + 1, "translated daily chrome fits " + str([id, locale, scale, viewport.size, control.name]))
	if not screenshots:
		return
	if id == "combat":
		var player: Node = coordinator.runtime().current_player()
		for frame: int in range(30):
			if player.get_node_or_null("PixelProxyActor/ProductionActorAtlas") != null:
				break
			await get_tree().physics_frame
		var atlas := player.get_node_or_null("PixelProxyActor/ProductionActorAtlas") as Sprite2D
		_suite.assert_true(atlas != null and atlas.texture != null and atlas.is_visible_in_tree(), "daily native screenshot includes the actual loaded production character atlas")
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	_suite.assert_true(pixels != null and not pixels.is_empty(), "actual daily native canvas renders a nonempty bitmap")
	if pixels == null or pixels.is_empty():
		return
	var colors := {}
	for x: int in range(0, pixels.get_width(), 8):
		for y: int in range(0, pixels.get_height(), 8):
			colors[pixels.get_pixel(x, y).to_html()] = true
	_suite.assert_true(colors.size() > 3, "daily screenshot contains visible native geometry or controls")
	DirAccess.make_dir_recursive_absolute("res://build/p21b-daily-screenshots")
	_suite.assert_equal(pixels.save_png("res://build/p21b-daily-screenshots/%s-%s-%.1f-%dx%d.png" % [id, locale, scale, viewport.size.x, viewport.size.y]), OK, "actual native daily screenshot is retained")
