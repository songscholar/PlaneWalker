extends "res://tests/integration/ui/main_daily_boss_test.gd"

const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]
const PAGES := {
	"gateway": ["hub_council", "GatewayLoadout"],
	"council": ["hub_council", "CouncilBranches"],
	"archive": ["hub_council", "CollectionGrid"],
	"forge": ["hub_craft", "ForgeWeapons"],
	"meditation": ["hub_craft", "SavedBuilds"],
	"training": ["hub_craft", "TrainingLesson"],
	"gallery": ["hub_rift", "CollectionGrid"],
	"mirror": ["hub_rift", "CollectionGrid"],
	"merchant": ["hub_rift", "ProviderRecords"],
}


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var capture := OS.get_cmdline_user_args().has("--hub-finish-screenshots")
	for locale: String in ["zh_CN", "en"]:
		for scale: float in [1.0, 1.5]:
			GameState.persistent.settings.locale = locale
			GameState.persistent.settings.text_scale = scale
			for resolution: Vector2i in RESOLUTIONS:
				_seed_main_profile("hub-finish-%s-%s-%s" % [locale, scale, resolution])
				var viewport := SubViewport.new()
				viewport.size = resolution
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var main := Main.instantiate()
				viewport.add_child(main)
				var hub: Node = main.get_node("HubFlowCoordinator")
				for id: String in PAGES:
					_suite.assert_true(hub.travel(PAGES[id][0]).ok and hub.open_function(id).ok, "authored Hub page opens: " + id)
					await _frames(3)
					var panel: Control = hub.panel_view()
					var snapshot: Dictionary = hub.view_state().duplicate(true)
					_suite.assert_true(panel.find_child(PAGES[id][1], true, false) != null, "Hub uses the dedicated " + id + " layout")
					var artwork_count := 0
					for artwork: TextureRect in panel.find_children("*", "TextureRect", true, false):
						if artwork.texture == null or not artwork.get_meta("production_ui_art", false):
							continue
						artwork_count += 1
						_suite.assert_equal(artwork.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "Hub artwork retains nearest sampling")
					_suite.assert_true(artwork_count > 0, "Hub page consumes loaded production artwork: " + id)
					if id == "gateway":
						_suite.assert_true(artwork_count >= 9, "Gateway shows all five character portraits and the equipped kit")
					if id == "forge":
						_suite.assert_true(artwork_count >= 5, "Forge shows all five authored weapon images")
					_suite.assert_equal(hub.view_state(), snapshot, "Hub presentation keeps its accepted domain state immutable")
					var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
					_suite.assert_true(bounds.encloses(panel.panel_root.get_global_rect()), "Hub shell fits supported canvas " + str([id, locale, scale, resolution]))
					_suite.assert_true(panel.panel_root.size.x <= 616, "Hub modal keeps readable bounded columns on wide canvases")
					_suite.assert_true(bounds.encloses(panel.back_button.get_global_rect()), "Hub return command remains inside supported canvas")
					if capture:
						await RenderingServer.frame_post_draw
						var pixels := viewport.get_texture().get_image()
						_suite.assert_true(pixels != null and not pixels.is_empty(), "dedicated Hub page renders actual pixels")
						if pixels != null and not pixels.is_empty():
							var output := "res://build/ui-finish-hub-screenshots/%s-%s-%s-%dx%d.png" % [id, locale, scale, resolution.x, resolution.y]
							DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
							_suite.assert_equal(pixels.save_png(output), OK, "dedicated Hub page capture retained")
					hub.close_panel()
				viewport.queue_free()
				await _frames(3)
	_suite.finish(get_tree())
