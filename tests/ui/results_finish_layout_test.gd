extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const MainScene := preload("res://scenes/main.tscn")
const Registry := preload("res://scripts/content/content_registry.gd")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	suite.assert_true(not registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH").has_blocking_errors(), "results use canonical content and shipping localization")
	var result := {"result": "death", "current_room": 5, "rooms_cleared": 4, "kills": 127, "run_time": 1234.0, "floor": 3, "rewards": [], "blessings": [], "talent_choices": [], "curses": []}
	for pair: Array in [["rewards", "item"], ["blessings", "blessing"], ["talent_choices", "talent"], ["curses", "curse"]]:
		var pool: Array = registry.get_by_category(StringName(pair[1]), &"LAUNCH")
		for index in range(mini(6, pool.size())):
			result[pair[0]].append(pool[index].duplicate(true))
	var before := result.duplicate(true)
	var capture := OS.get_cmdline_user_args().has("--results-finish-screenshots")
	var probe := OS.get_environment("PLANEWALKER_UI_RED_PROBE") == "1"
	for locale: String in (["zh_CN"] if probe else ["zh_CN", "en"]):
		for scale: float in ([1.5] if probe else [1.0, 1.5]):
			GameState.persistent.settings.locale = locale
			GameState.persistent.settings.text_scale = scale
			TranslationServer.set_locale(locale)
			var accessibility := Accessibility.new()
			add_child(accessibility)
			for resolution: Vector2i in ([Vector2i(640, 360)] if probe else RESOLUTIONS):
				get_window().size = resolution
				var source := MainScene.instantiate()
				var overlay := source.get_node("RunEndOverlay") as CanvasLayer
				source.remove_child(overlay)
				source.free()
				add_child(overlay)
				overlay.call("configure_profile_return", true)
				for outcome: String in ["death", "victory", "save_retry"]:
					var displayed := result.duplicate(true)
					if outcome == "victory":
						displayed.result = "victory"
					if outcome == "save_retry":
						overlay.call("show_victory_save_retry")
					else:
						overlay.call("_on_run_ended", "result-finish-" + outcome, displayed, 1)
					accessibility.apply_to_tree(overlay)
					await _frames(3)
					var root := overlay.get_node("Panel") as Control
					var bounds := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
					suite.assert_true(bounds.encloses(root.get_global_rect()), "result shell is bounded: " + str([outcome, locale, scale, resolution]))
					suite.assert_true(root.get_global_rect().encloses(overlay.get("restart_button").get_global_rect()), "result action stays outside readable history scroll")
					var scroll := overlay.find_child("ResultScroll", true, false) as ScrollContainer
					suite.assert_true(scroll != null and scroll.focus_mode == Control.FOCUS_ALL, "results expose controller-readable graphical history")
					if outcome != "save_retry":
						for pool: String in ["rewards", "blessings", "talent_choices", "curses"]:
							for definition: Dictionary in displayed[pool]:
								var image := overlay.find_child("ResultContent_" + str(definition.id), true, false) as TextureRect
								suite.assert_true(image != null and image.texture == Art.content(str(definition.id), str(definition.category)), "results bind exact canonical acquired-content art")
					if capture:
						await RenderingServer.frame_post_draw
						var pixels := get_viewport().get_texture().get_image()
						if pixels != null and not pixels.is_empty():
							var output := "res://build/ui-finish-results-screenshots/%s-%s-%s-%dx%d.png" % [outcome, locale, scale, resolution.x, resolution.y]
							DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
							suite.assert_equal(pixels.save_png(output), OK, "native result screenshot is retained")
					var return_button := overlay.get("restart_button") as Button
					var button_identity := return_button.get_instance_id()
					if outcome == "death":
						overlay.call("show_save_pending")
					TranslationServer.set_locale("en" if locale == "zh_CN" else "zh_CN")
					await _frames(2)
					suite.assert_equal(return_button.get_instance_id(), button_identity, "language refresh retains the terminal command identity")
					if outcome in ["death", "save_retry"]:
						suite.assert_equal(return_button.text, tr("UI_RETRY"), "language refresh retains the physical settlement retry command")
					TranslationServer.set_locale(locale)
					await _frames(2)
					overlay.call("hide_overlay")
				overlay.queue_free()
				await _frames(2)
			accessibility.queue_free()
			await _frames(2)
	suite.assert_equal(result, before, "results do not mutate terminal rewards or statistics")
	suite.finish(get_tree())


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
