extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Registry := preload("res://scripts/content/content_registry.gd")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var source := Main.instantiate()
	var menu := source.get_node("PauseMenu") as CanvasLayer
	source.remove_child(menu)
	source.free()
	add_child(menu)
	suite.assert_true(menu.has_method("configure_build_inspection"), "production pause owns a read-only build inspection entry")
	if not menu.has_method("configure_build_inspection"):
		menu.queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui/hud_boss.json"))
	state.build.dominant_archetype = "freeze_burst"
	state.build.archetype_scores = {"freeze_burst": 3, "rewind_echo": 1, "accelerated_combo": 0}
	var snapshot := state.duplicate(true)
	suite.assert_true(menu.call("configure_build_inspection", registry, state).ok, "pause accepts the current read-only equipment projection")
	var capture := OS.get_cmdline_user_args().has("--pause-finish-screenshots")
	for locale: String in ["zh_CN", "en"]:
		for scale: float in [1.0, 1.5]:
			GameState.persistent.settings.locale = locale
			GameState.persistent.settings.text_scale = scale
			TranslationServer.set_locale(locale)
			var accessibility := Accessibility.new()
			add_child(accessibility)
			accessibility.apply_to_tree(menu)
			for resolution: Vector2i in RESOLUTIONS:
				get_window().size = resolution
				menu.call("show_pause")
				await _frames(3)
				var bounds := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
				var panel := menu.get_node("Panel") as Control
				suite.assert_true(bounds.encloses(panel.get_global_rect()), "pause preserves safe-area bounds at supported text scales")
				for button: Button in panel.find_children("*", "Button", true, false):
					suite.assert_true(panel.get_global_rect().encloses(button.get_global_rect()), "every pause action fits its bounded shell")
				var build_button: Button = menu.get("build_button")
				suite.assert_true(build_button != null and not build_button.disabled, "accepted run exposes build inspection")
				if capture:
					await RenderingServer.frame_post_draw
					var pixels := get_viewport().get_texture().get_image()
					if pixels != null and not pixels.is_empty():
						var output := "res://build/ui-finish-pause-screenshots/pause-%s-%s-%dx%d.png" % [locale, scale, resolution.x, resolution.y]
						DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
						suite.assert_equal(pixels.save_png(output), OK, "pause screenshot retained")
				build_button.grab_focus()
				build_button.pressed.emit()
				await _frames(3)
				var inspector := menu.get_node_or_null("BuildInspector") as Control
				suite.assert_true(inspector != null and inspector.visible, "pause action opens the current build")
				suite.assert_true(not panel.visible, "inspection occupies the pause surface")
				if inspector != null:
					suite.assert_equal(inspector.call("view_state"), snapshot, "inspection uses the exact accepted snapshot")
					inspector.get("back_button").pressed.emit()
					await _frames(2)
					suite.assert_true(panel.visible and not inspector.visible, "return restores the pause actions")
					suite.assert_equal(get_viewport().gui_get_focus_owner(), build_button, "return restores the build-entry focus")
				menu.call("hide_pause")
			accessibility.queue_free()
			await _frames(1)
	suite.assert_equal(state, snapshot, "pause presentation never changes run data")
	menu.queue_free()
	await _frames(1)
	suite.finish(get_tree())


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
