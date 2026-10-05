extends "res://tests/integration/ui/main_authored_challenges_test.gd"

const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var screenshots := OS.get_cmdline_user_args().has("--authored-challenge-screenshots")
	for locale: String in ["en", "zh_CN"]:
		for scale: float in [1.0, 1.5]:
			GameState.persistent.settings.locale = locale
			GameState.persistent.settings.text_scale = scale
			for size: Vector2i in RESOLUTIONS:
				_seed_main_profile("authored-visual-%s-%.1f-%dx%d" % [locale, scale, size.x, size.y])
				var viewport := SubViewport.new()
				viewport.size = size
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var main := MainScene.instantiate()
				viewport.add_child(main)
				await get_tree().process_frame
				var hub: Node = main.get_node("HubFlowCoordinator")
				_suite.assert_true(hub.travel("hub_council").ok and hub.open_function("gateway").ok, "actual authored gateway opens across supported native visual combinations")
				_authored_action(hub.panel_view(), "authored_challenges").pressed.emit()
				var coordinator: Node = main.get_node("AuthoredChallengeCoordinator")
				await _capture_authored(coordinator, viewport, "menu", locale, scale, screenshots)
				_suite.assert_true(coordinator.panel().selector.has_focus(), "actual authored five-set selector receives native initial focus")
				_authored_action(coordinator.panel(), "start").pressed.emit()
				await _frames(5)
				var flow: Node = coordinator.runtime()
				_suite.assert_true(flow.is_active() and not coordinator.panel().visible, "authored visual QA enters actual fixed-Build Boss arena")
				await _capture_authored(coordinator, viewport, "combat", locale, scale, screenshots)
				var pause := InputEventJoypadButton.new()
				pause.button_index = JOY_BUTTON_START
				pause.pressed = true
				main._unhandled_input(pause)
				_suite.assert_true(coordinator.panel().visible and flow.is_paused(), "actual Main controller pause exposes authored commands")
				var frozen: Dictionary = flow.snapshot()
				await _capture_authored(coordinator, viewport, "pause", locale, scale, screenshots)
				_suite.assert_equal(flow.snapshot(), frozen, "native authored visual pause preserves accepted-frame objective metrics")
				_authored_action(coordinator.panel(), "resume").pressed.emit()
				await _kill_boss(flow)
				_suite.assert_equal(flow.snapshot().active.status, "STAGE_CLEAR", "actual native Boss clear exposes authored next-stage panel")
				await _capture_authored(coordinator, viewport, "stage-clear", locale, scale, screenshots)
				for _stage: int in range(2):
					_authored_action(coordinator.panel(), "next").pressed.emit()
					await _kill_boss(flow)
				_suite.assert_true(flow.preview().best.sword_timer.status == "VICTORY" and coordinator.panel().visible, "actual authored terminal renders saved fresh best and history")
				await _capture_authored(coordinator, viewport, "victory", locale, scale, screenshots)
				_suite.assert_true(coordinator.return_to_hub().ok and hub.is_hub_visible(), "native authored visual workflow returns actual Main to Hub")
				viewport.queue_free()
				await get_tree().process_frame
				await get_tree().process_frame
	_suite.finish(get_tree())


func _capture_authored(coordinator: Node, viewport: SubViewport, id: String, locale: String, scale: float, screenshots: bool) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport.size))
	if coordinator.panel().visible:
		for action: Control in coordinator.panel().action_controls():
			_suite.assert_true(bounds.encloses(action.get_global_rect()), "actual authored command stays visible without content scrolling " + str([id, locale, scale, viewport.size, action.get_meta("action_id", "back")]))
		_suite.assert_true(bounds.encloses(coordinator.panel().selector.get_global_rect()), "authored selector stays inside native viewport")
		if id == "pause":
			_suite.assert_equal(coordinator.panel().back_button.text, tr("UI_AUTHORED_SAVE_RETURN"), "active authored return identifies durable practice continuation")
		if id == "stage-clear":
			_suite.assert_equal(_authored_action(coordinator.panel(), "next").text, tr("UI_MODE_NEXT_BOSS"), "actual authored next-Boss command uses registered bilingual text")
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
		_suite.assert_true(bounds.encloses(control.get_global_rect()), "native authored chrome stays inside viewport " + str([id, locale, scale, viewport.size, control.name]))
		if control is Button or control is Label:
			_suite.assert_true(control.get_combined_minimum_size().x <= control.size.x + 1 and control.get_combined_minimum_size().y <= control.size.y + 1, "translated authored chrome fits " + str([id, locale, scale, viewport.size, control.name]))
			_suite.assert_true(not control.text.begins_with("UI_"), "actual authored chrome does not expose an untranslated key")
	if not screenshots:
		return
	if id == "combat":
		var player: Node = coordinator.runtime().current_player()
		for frame: int in range(30):
			if player.get_node_or_null("PixelProxyActor/ProductionActorAtlas") != null:
				break
			await get_tree().physics_frame
		var atlas := player.get_node_or_null("PixelProxyActor/ProductionActorAtlas") as Sprite2D
		_suite.assert_true(atlas != null and atlas.texture != null and atlas.is_visible_in_tree(), "authored native screenshot loads actual production character bitmap")
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	_suite.assert_true(pixels != null and not pixels.is_empty(), "authored native canvas renders nonempty bitmap")
	if pixels == null or pixels.is_empty():
		return
	var colors := {}
	for x: int in range(0, pixels.get_width(), 8):
		for y: int in range(0, pixels.get_height(), 8):
			colors[pixels.get_pixel(x, y).to_html()] = true
	_suite.assert_true(colors.size() > 3, "authored native screenshot includes visible controls or geometry")
	DirAccess.make_dir_recursive_absolute("res://build/p21c-authored-screenshots")
	_suite.assert_equal(pixels.save_png("res://build/p21c-authored-screenshots/%s-%s-%.1f-%dx%d.png" % [id, locale, scale, viewport.size.x, viewport.size.y]), OK, "actual native authored screenshot is retained")
