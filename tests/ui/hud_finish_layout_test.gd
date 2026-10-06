extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Hud := preload("res://scenes/ui/combat_hud_v2.tscn")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var capture := OS.get_cmdline_user_args().has("--hud-finish-screenshots")
	for locale: String in ["zh_CN", "en"]:
		for scale: float in [1.0, 1.5]:
			GameState.persistent.settings.locale = locale
			GameState.persistent.settings.text_scale = scale
			TranslationServer.set_locale(locale)
			var accessibility := Accessibility.new()
			add_child(accessibility)
			for resolution: Vector2i in RESOLUTIONS:
				var viewport := SubViewport.new()
				viewport.size = resolution
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var hud := Hud.instantiate()
				viewport.add_child(hud)
				accessibility.apply_to_tree(hud)
				for id: String in ["combat", "low_hp", "boss"]:
					var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui/hud_%s.json" % id))
					state.run_id = "hud-finish-" + id
					state.build.dominant_archetype = "freeze_burst"
					state.build.archetype_scores = {"freeze_burst": 3, "rewind_echo": 0, "accelerated_combo": 0}
					var snapshot := state.duplicate(true)
					suite.assert_true(hud.render(state).ok, "finished HUD renders accepted " + id + " projection")
					await get_tree().process_frame
					await get_tree().process_frame
					suite.assert_equal(state, snapshot, "graphical HUD does not mutate its domain projection")
					var layout: Control = hud.get_node("HudRoot/SafeArea/HudLayout")
					var player: Control = layout.get_node("PlayerPanel")
					if state.character_state is Dictionary and int(state.character_state.cooldown_current) > 0:
						var counter := layout.get_node("CharacterPanel/CharacterSlot/SlotCounter") as Label
						suite.assert_equal(counter.text, "%.1f" % (float(state.character_state.cooldown_current) / 60.0), "character slot exposes remaining cooldown seconds during combat")
					suite.assert_true(player.size.x <= 220 and player.size.y <= 46, "vitals keep their compact lower-edge footprint")
					suite.assert_true(hud.boss_panel.size.x <= 344 and hud.boss_panel.size.y <= 34, "Boss strip keeps the upper combat viewport clear")
					var artwork_count := 0
					for artwork: TextureRect in hud.find_children("*", "TextureRect", true, false):
						if artwork.is_visible_in_tree() and artwork.texture != null and artwork.get_meta("production_ui_art", false):
							artwork_count += 1
							suite.assert_equal(artwork.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "HUD bitmap slots preserve nearest sampling")
					suite.assert_true(artwork_count >= 4, "HUD displays recognizable character, weapon and two time-slot artwork")
					var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
					for control: Control in layout.get_children():
						if control.is_visible_in_tree():
							suite.assert_true(bounds.encloses(control.get_global_rect()), "graphical HUD stays inside canvas: " + str([id, locale, scale, resolution, control.name]))
					if capture:
						await RenderingServer.frame_post_draw
						var pixels := viewport.get_texture().get_image()
						suite.assert_true(pixels != null and not pixels.is_empty(), "native finished HUD renders actual pixels")
						if pixels != null and not pixels.is_empty():
							var output := "res://build/ui-finish-hud-screenshots/%s-%s-%s-%dx%d.png" % [id, locale, scale, resolution.x, resolution.y]
							DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
							suite.assert_equal(pixels.save_png(output), OK, "finished HUD capture retained")
				viewport.queue_free()
				await get_tree().process_frame
			accessibility.queue_free()
			await get_tree().process_frame
	suite.finish(get_tree())
