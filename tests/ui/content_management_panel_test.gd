extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const PanelScript := preload("res://scripts/ui/content_management_panel.gd")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]
var _requests: Array = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var locale_before := TranslationServer.get_locale()
	var scale_before: Variant = GameState.get_setting("text_scale", 1.0)
	var previous := Button.new()
	add_child(previous)
	previous.grab_focus()
	var accessibility := Accessibility.new()
	add_child(accessibility)
	var panel := PanelScript.new()
	add_child(panel)
	panel.command_requested.connect(func(operation: String, payload: Dictionary, revision: int): _requests.append([operation, payload, revision]))
	await _layout()
	var state := _state()
	suite.assert_true(panel.render(state).ok, "native package state renders")
	await _layout()
	suite.assert_equal(FocusCoordinator.active_scope(), panel, "native packages own controller focus")
	var toggle := _action(panel, "enable:local_prism")
	toggle.pressed.emit()
	toggle.pressed.emit()
	suite.assert_equal(_requests, [["set_enabled", {"ids": ["local_prism"]}, 7]], "binary activation submits exact selection once at its displayed revision")
	suite.assert_equal(panel.view_state(), state, "pending activation does not change authoritative view state")
	var rejected := state.duplicate(true)
	rejected.revision += 1
	rejected.epoch = rejected.revision
	suite.assert_true(panel.render(rejected).ok, "Main refresh restores saved selection after a refused command")
	panel.show_rejection("UI_CONTENT_REJECTED")
	suite.assert_true(not _action(panel, "enable:local_prism").button_pressed, "refused checkbox returns to authoritative disabled state")
	toggle.pressed.emit()
	suite.assert_equal(_requests.size(), 1, "retired controls cannot submit against a refreshed state")
	var bad := rejected.duplicate(true)
	bad.installed[0].erase("owned")
	suite.assert_true(not panel.render(bad).ok and panel.view_state() == rejected, "malformed package rows refuse without changing native presentation")
	bad = rejected.duplicate(true)
	bad.activation.erase("activation_order")
	suite.assert_true(not panel.render(bad).ok and panel.view_state() == rejected, "missing activation identity refuses without a runtime error")
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		for scale: float in [1.0, 1.5]:
			GameState.set_setting("text_scale", scale)
			for resolution: Vector2i in RESOLUTIONS:
				get_viewport().size = resolution
				accessibility.apply_to_tree(panel)
				await _layout()
				var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
				suite.assert_true(bounds.encloses(panel.panel_root.get_global_rect()), "localized package panel fits supported viewport")
				suite.assert_true(panel.panel_root.get_global_rect().position.x >= 15.9 and panel.panel_root.get_global_rect().end.y <= resolution.y - 15.9, "native package safe area is retained")
				suite.assert_true(not panel.title_label.text.begins_with("UI_"), "package title resolves bilingual localization")
				suite.assert_equal(panel.title_label.get_theme_font_size("font_size"), roundi(16 * scale), "visual matrix applies the actual accessibility font scale")
				for control: Control in panel.action_controls():
					suite.assert_true(control.get_combined_minimum_size().x <= control.size.x + 1 and control.get_combined_minimum_size().y <= control.size.y + 1, "long package identifiers and localized commands fit without overlap")
				suite.assert_true(get_viewport().gui_get_focus_owner() != null, "locale and text scale retain reachable controller focus")
				await _capture(suite, "content-%s-%dx%d-%d" % [locale, resolution.x, resolution.y, int(scale * 100)])
	await _controller(suite, panel)
	var locked := rejected.duplicate(true)
	locked.revision += 1
	locked.epoch = locked.revision
	locked.locked = true
	suite.assert_true(panel.render(locked).ok, "native active adventure presents locked package management")
	await _layout()
	for control: Button in panel.action_controls():
		suite.assert_true(control.disabled, "active adventure disables package mutations")
	suite.assert_equal(get_viewport().gui_get_focus_owner(), panel.back_button, "locked native panel retains a controller exit")
	panel.close_panel()
	await _layout()
	suite.assert_equal(get_viewport().gui_get_focus_owner(), previous, "native package close restores previous controller focus")
	TranslationServer.set_locale(locale_before)
	GameState.set_setting("text_scale", scale_before)
	panel.queue_free()
	previous.queue_free()
	accessibility.queue_free()
	await _layout()
	suite.finish(get_tree())


func _state() -> Dictionary:
	return {"run_id": "content-manager", "revision": 7, "epoch": 7, "locked": false, "activation": {"save_domain": "base", "activation_order": ["base"]}, "entitlements": {}, "diagnostics": [{"pack_id": "unavailable_content", "code": "CONTENT_UNAVAILABLE"}], "installed": [{"pack_id": "local_prism", "pack_version": "1.0.0", "enabled": false, "owned": true}, {"pack_id": "a_very_long_original_local_package_identifier_for_layout_testing", "pack_version": "1.0.0", "enabled": false, "owned": true}, {"pack_id": "owned_content_unavailable", "pack_version": "2.0.0", "enabled": false, "owned": false}]}


func _action(panel: Control, id: String) -> Button:
	for control: Control in panel.action_controls():
		if control.get_meta("action_id", "") == id:
			return control as Button
	return null


func _layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _controller(suite, panel: Control) -> void:
	var controls: Array = panel.action_controls().filter(func(control: Button): return not control.disabled)
	controls.append(panel.back_button)
	controls[0].grab_focus()
	for index: int in range(controls.size()):
		suite.assert_equal(get_viewport().gui_get_focus_owner(), controls[index], "controller reaches every available package command")
		for pressed: bool in [true, false]:
			var event := InputEventAction.new()
			event.action = &"ui_down"
			event.pressed = pressed
			Input.parse_input_event(event)
			await _layout()
	suite.assert_equal(get_viewport().gui_get_focus_owner(), controls[0], "native package controller traversal wraps in its active scope")


func _capture(suite, id: String) -> void:
	var directory := OS.get_environment("PLANEWALKER_CONTENT_CAPTURE_DIR")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var pixels := get_viewport().get_texture().get_image()
	suite.assert_true(pixels != null and not pixels.is_empty(), "native content panel renders actual pixels")
	if pixels == null or pixels.is_empty():
		return
	var colors: Dictionary = {}
	for y: int in range(0, pixels.get_height(), 8):
		for x: int in range(0, pixels.get_width(), 8):
			colors[pixels.get_pixel(x, y).to_rgba32()] = true
	suite.assert_true(colors.size() > 8, "native content screenshot is nonblank")
	suite.assert_equal(pixels.save_png(directory.path_join(id + ".png")), OK, "native content screenshot is retained")
