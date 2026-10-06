extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const SettingsScene := preload("res://scenes/ui/accessibility_settings_panel.tscn")
const RemapScene := preload("res://scenes/ui/input_remap_panel.tscn")
const RemapService := preload("res://scripts/input/input_remap_service.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	suite.assert_true(not registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH").has_blocking_errors(), "settings tests load complete shipping localization")
	var service := RemapService.new()
	service.configure(OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("ui-finish-remap"))
	suite.assert_true(service.load_or_defaults().ok, "remap presentation uses the production binding service")
	var bindings := service.snapshot_profile()
	var capture := OS.get_cmdline_user_args().has("--settings-finish-screenshots")
	var probe := OS.get_environment("PLANEWALKER_UI_RED_PROBE") == "1"
	for locale: String in (["en"] if probe else ["zh_CN", "en"]):
		for scale: float in ([1.5] if probe else [1.0, 1.5]):
			GameState.persistent.settings.locale = locale
			GameState.persistent.settings.text_scale = scale
			TranslationServer.set_locale(locale)
			var accessibility := Accessibility.new()
			add_child(accessibility)
			for resolution: Vector2i in ([Vector2i(640, 360)] if probe else RESOLUTIONS):
				var viewport := SubViewport.new()
				viewport.size = resolution
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				for kind: String in ["settings", "remap"]:
					var panel: Control = SettingsScene.instantiate() if kind == "settings" else RemapScene.instantiate()
					if kind == "remap":
						panel.call("configure", service)
					viewport.add_child(panel)
					panel.call("open_panel")
					accessibility.apply_to_tree(panel)
					await _frames(4)
					var root := panel.get_node("SafeArea/PanelRoot") as PanelContainer
					var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
					suite.assert_true(bounds.encloses(root.get_global_rect()), "settings shell stays bounded: " + str([kind, locale, scale, resolution]))
					suite.assert_true(root.size.x <= 616 and root.size.y <= 560, "wide settings preserve constrained paragraph and command widths")
					suite.assert_true(root.get_theme_stylebox("panel") is StyleBoxTexture, "settings and remap consume the authored pixel frame")
					var back := panel.get_node("SafeArea/PanelRoot/Layout/Footer/BackButton") as Button
					suite.assert_true(root.get_global_rect().encloses(back.get_global_rect()) and back.icon != null, "settings footer remains visible with its canonical back control")
					if kind == "settings":
						var tabs := panel.find_child("SettingsTabs", true, false) as TabBar
						suite.assert_true(tabs != null and tabs.tab_count == 5, "settings provide authored category navigation")
						if tabs != null:
							var before: Dictionary = GameState.persistent.settings.duplicate(true)
							tabs.current_tab = 4
							await _frames(2)
							suite.assert_equal(GameState.persistent.settings, before, "category browsing never mutates saved settings")
							var assist := panel.call("get_setting_control", "damage_received_multiplier") as Control
							suite.assert_true((panel.get("scroll") as ScrollContainer).get_global_rect().intersects(assist.get_global_rect()), "last category is reachable by native tab navigation")
							tabs.current_tab = 0
							await _frames(2)
						for control: Control in panel.get("_setting_controls").values():
							var row := control.get_parent() as HBoxContainer
							var label := row.get_node("SettingLabel") as Label
							suite.assert_equal(label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "setting labels wrap at enlarged text scale")
							suite.assert_true(control.get_global_rect().end.x <= root.get_global_rect().end.x - 8, "all setting controls fit horizontally")
					else:
						for pair: Array in [["KeyboardMouseDeviceArtwork", "keyboard_mouse"], ["ControllerDeviceArtwork", "controller"]]:
							var image := panel.find_child(str(pair[0]), true, false) as TextureRect
							suite.assert_true(image != null and image.texture == Art.icon(&"controls", StringName(pair[1])), "remapping headers use authenticated input device art")
						for row: HBoxContainer in panel.get_node("SafeArea/PanelRoot/Layout/Scroll/Rows").get_children():
							var reset := row.get_node("ResetActionButton") as Button
							suite.assert_true(reset.text.is_empty() and reset.icon != null, "per-action binding reset uses an authenticated tool icon")
							suite.assert_true(reset.get_global_rect().end.x <= root.get_global_rect().end.x - 8, "all binding commands fit horizontally")
					if capture:
						await _capture(viewport, "%s-%s-%s-%dx%d" % [kind, locale, scale, resolution.x, resolution.y], suite)
					if kind == "remap":
						panel.call("_start_capture", &"weapon_primary", &"controller")
						await _frames(2)
						var modal := panel.get_node("CaptureOverlay/Center/CapturePanel") as Control
						suite.assert_true(bounds.encloses(modal.get_global_rect()), "binding capture stays bounded at enlarged text scale")
						var pending: StringName = panel.get("_capture_action")
						TranslationServer.set_locale("en" if locale == "zh_CN" else "zh_CN")
						await _frames(2)
						suite.assert_equal(panel.get("_capture_action"), pending, "language refresh preserves the exact pending input capture")
						suite.assert_equal(panel.get("title_label").text, tr("UI_INPUT_REMAP"), "open remap language refresh updates title without rebuilding bindings")
						TranslationServer.set_locale(locale)
						await _frames(2)
						if capture:
							await _capture(viewport, "capture-%s-%s-%dx%d" % [locale, scale, resolution.x, resolution.y], suite)
						panel.call("_cancel_capture")
					panel.call("close_panel")
					panel.queue_free()
					await _frames(2)
				viewport.queue_free()
				await _frames(2)
			accessibility.queue_free()
			await _frames(2)
	suite.assert_equal(service.snapshot_profile(), bindings, "presentation and cancelled capture preserve all saved input bindings")
	suite.finish(get_tree())


func _capture(viewport: SubViewport, filename: String, suite: RefCounted) -> void:
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	if pixels == null or pixels.is_empty():
		suite.assert_true(false, "settings has native rendered pixels")
		return
	var output := "res://build/ui-finish-settings-screenshots/" + filename + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	suite.assert_equal(pixels.save_png(output), OK, "native settings screenshot is retained")


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
