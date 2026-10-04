extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Host := preload("res://scripts/hub/hub_scene_host.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var original_locale := TranslationServer.get_locale()
	var original_scale: Variant = GameState.get_setting("text_scale", 1.0)
	var screenshots := OS.get_cmdline_user_args().has("--hub-screenshots")
	var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string(Host.DEFINITIONS_PATH))
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		for text_scale: float in [1.0, 1.5]:
			GameState.persistent.settings.text_scale = text_scale
			for resolution: Vector2i in RESOLUTIONS:
				var viewport := SubViewport.new()
				viewport.size = resolution
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var host := Host.new()
				var scale_factor := minf(float(resolution.x) / 640, float(resolution.y) / 360)
				host.scale = Vector2.ONE * scale_factor
				host.position = (Vector2(resolution) - Vector2(640, 360) * scale_factor) / 2
				viewport.add_child(host)
				for definition: Dictionary in definitions:
					suite.assert_true(host.install_district(definition).ok, "authored district installs for visual QA")
					await get_tree().process_frame
					await get_tree().process_frame
					for label: Label in host.find_children("NameLabel", "Label", true, false):
						suite.assert_true(label.get_minimum_size().x <= label.size.x and label.get_minimum_size().y <= label.size.y, "localized NPC text fits at " + str([locale, text_scale, resolution]))
						var rect := label.get_global_rect()
						suite.assert_true(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(rect), "NPC text remains inside the supported viewport")
					if screenshots:
						await RenderingServer.frame_post_draw
						var pixels := viewport.get_texture().get_image()
						suite.assert_true(pixels != null and not pixels.is_empty(), "native Hub produces actual rendered pixels")
						if pixels != null and not pixels.is_empty():
							var colors: Dictionary = {}
							for y: int in range(0, 360, 12):
								for x: int in range(0, 640, 12):
									var point := host.position + Vector2(x, y) * scale_factor
									colors[pixels.get_pixelv(Vector2i(point)).to_rgba32()] = true
							suite.assert_true(colors.size() > 16, "raster background, portraits, and names render as a nonblank native scene")
							var output := "res://build/p16-hub-screenshots/%s-%s-%s-%dx%d.png" % [definition.id, locale, str(text_scale), resolution.x, resolution.y]
							DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
							suite.assert_equal(pixels.save_png(output), OK, "native Hub screenshot retained")
				viewport.queue_free()
				await get_tree().process_frame
	TranslationServer.set_locale(original_locale)
	GameState.persistent.settings.text_scale = original_scale
	suite.finish(get_tree())
