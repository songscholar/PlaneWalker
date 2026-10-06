extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/ui/p14_panel_fixtures.gd")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]
const PANELS := {"map": "dungeon_map", "route": "route_choice", "merchant": "merchant", "event": "dungeon_event", "room": "room_interaction", "transition": "floor_transition"}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var capture := OS.get_cmdline_user_args().has("--dungeon-finish-screenshots")
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
				for kind: String in PANELS:
					var packed := load("res://scenes/ui/%s_panel.tscn" % PANELS[kind]) as PackedScene
					var panel := packed.instantiate() as Control
					viewport.add_child(panel)
					var state := Fixtures.for_kind(kind)
					var snapshot := state.duplicate(true)
					suite.assert_true(panel.call("render", state).ok, "finished dungeon view accepts its " + kind + " projection")
					await get_tree().process_frame
					await get_tree().process_frame
					await get_tree().process_frame
					suite.assert_equal(state, snapshot, "dungeon artwork never mutates domain projections")
					var artwork_count := 0
					for artwork: TextureRect in panel.find_children("*", "TextureRect", true, false):
						if artwork.texture != null and artwork.get_meta("production_ui_art", false):
							artwork_count += 1
					for button: Button in panel.find_children("*", "Button", true, false):
						if button.icon != null:
							artwork_count += 1
					suite.assert_true(artwork_count > 0, "dungeon view consumes recognizable production artwork: " + kind)
					if kind == "map":
						for node: Dictionary in snapshot.nodes:
							var button: Button = panel.find_child("MapNode_" + str(node.id), true, false)
							suite.assert_true(button != null and button.icon != null, "every projected room knowledge state has a graphical node")
							if button != null:
								suite.assert_equal(button.get_meta("room_type", ""), node.room_type, "map glyph identity comes only from the validated knowledge projection")
								suite.assert_equal(button.icon, Art.icon(&"room_types", StringName(node.room_type)), "unknown room artwork cannot reveal a concealed room type")
					if kind == "event":
						var event_art := panel.find_child("EventArtwork", true, false) as TextureRect
						suite.assert_true(event_art != null and event_art.texture == Art.icon(&"event_art", StringName(snapshot.event_id)), "event composition uses its exact authored event identity")
					var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
					var root: Control = panel.get("panel_root")
					var back: Control = panel.get("back_button")
					suite.assert_true(bounds.encloses(root.get_global_rect()), "dungeon shell stays inside supported canvas " + str([kind, locale, scale, resolution]))
					suite.assert_true(bounds.encloses(back.get_global_rect()), "dungeon footer remains reachable")
					if capture:
						await RenderingServer.frame_post_draw
						var pixels := viewport.get_texture().get_image()
						suite.assert_true(pixels != null and not pixels.is_empty(), "native dungeon view renders real pixels")
						if pixels != null and not pixels.is_empty():
							var output := "res://build/ui-finish-dungeon-screenshots/%s-%s-%s-%dx%d.png" % [kind, locale, scale, resolution.x, resolution.y]
							DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
							suite.assert_equal(pixels.save_png(output), OK, "finished dungeon capture retained")
					panel.call("close_panel")
					panel.queue_free()
					await get_tree().process_frame
				viewport.queue_free()
				await get_tree().process_frame
			accessibility.queue_free()
			await get_tree().process_frame
	suite.finish(get_tree())
