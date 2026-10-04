extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var locale_before := TranslationServer.get_locale()
	var scale_before: Variant = GameState.get_setting("text_scale", 1.0)
	var locale_setting_before: Variant = GameState.get_setting("locale", "zh_CN")
	var screenshots := OS.get_cmdline_user_args().has("--hub-screenshots")
	for locale: String in ["zh_CN", "en"]:
		GameState.persistent.settings.locale = locale
		for text_scale: float in [1.0, 1.5]:
			GameState.persistent.settings.text_scale = text_scale
			for resolution: Vector2i in RESOLUTIONS:
				var viewport := SubViewport.new()
				viewport.size = resolution
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var main := Main.instantiate()
				viewport.add_child(main)
				var hub: Node = main.get_node_or_null("HubFlowCoordinator")
				suite.assert_true(hub != null, "actual Main configures the native Hub for visual QA")
				if hub != null:
					for district: String in ["hub_council", "hub_craft", "hub_rift"]:
						suite.assert_true(hub.travel(district).ok, "native district travels during visual QA")
						await _capture(suite, hub, viewport, "scene-" + district, locale, text_scale, screenshots)
						for row: Dictionary in hub.view_state().functions:
							suite.assert_true(hub.open_function(str(row.id)).ok, "actual function panel opens during visual QA")
							await _capture(suite, hub, viewport, str(row.id), locale, text_scale, screenshots)
							hub.close_panel()
				viewport.queue_free()
				await get_tree().process_frame
				await get_tree().process_frame
	TranslationServer.set_locale(locale_before)
	GameState.persistent.settings.text_scale = scale_before
	GameState.persistent.settings.locale = locale_setting_before
	suite.finish(get_tree())


func _capture(suite: RefCounted, hub: Node, viewport: SubViewport, id: String, locale: String, text_scale: float, screenshots: bool) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var background: Sprite2D = hub.scene_host().find_child("Background", true, false)
	var factor := minf(float(viewport.size.x) / 640.0, float(viewport.size.y) / 360.0)
	var transform := background.get_global_transform_with_canvas()
	suite.assert_true(transform.x.is_equal_approx(Vector2(factor, 0)) and transform.y.is_equal_approx(Vector2(0, factor)), "actual Hub raster keeps its full scale independently of the combat camera")
	suite.assert_true(transform.origin.is_equal_approx((Vector2(viewport.size) - Vector2(640, 360) * factor) / 2), "actual Hub raster remains centered across viewport sizes")
	for control: Control in hub.find_children("*", "Control", true, false):
		if not control.is_visible_in_tree():
			continue
		if control is ScrollContainer or control.get_parent() is ScrollContainer:
			continue
		var scroll: Node = control.get_parent()
		var in_scroll := false
		while scroll != null and scroll != hub:
			in_scroll = in_scroll or scroll is ScrollContainer
			scroll = scroll.get_parent()
		if in_scroll:
			continue
		suite.assert_true(bounds.encloses(control.get_global_rect()), "native chrome stays inside viewport: " + str([id, locale, text_scale, viewport.size, control.name]))
		if control is Label or control is Button or control is LineEdit:
			suite.assert_true(control.get_combined_minimum_size().x <= control.size.x + 1 and control.get_combined_minimum_size().y <= control.size.y + 1, "native localized chrome fits: " + str([id, locale, text_scale, viewport.size, control.name]))
	if not screenshots:
		return
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	suite.assert_true(pixels != null and not pixels.is_empty(), "native Main produces rendered pixels")
	if pixels == null or pixels.is_empty():
		return
	var colors: Dictionary = {}
	for y: int in range(0, viewport.size.y, 4):
		for x: int in range(0, viewport.size.x, 4):
			colors[pixels.get_pixel(x, y).to_rgba32()] = true
			if colors.size() > 16:
				break
		if colors.size() > 16:
			break
	suite.assert_true(colors.size() > 8, "native Hub/panel renders a nonblank image: " + str([id, locale, text_scale, viewport.size, colors.size()]))
	var output := "res://build/p16-main-hub-screenshots/%s-%s-%s-%dx%d.png" % [id, locale, str(text_scale), viewport.size.x, viewport.size.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	suite.assert_equal(pixels.save_png(output), OK, "native production Hub screenshot retained")
