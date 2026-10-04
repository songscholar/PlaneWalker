extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var capture := OS.get_cmdline_user_args().has("--share-screenshots")
	for locale: String in ["en", "zh_CN"]:
		for scale: float in [1.0, 1.5]:
			GameState.persistent.settings.locale = locale
			GameState.persistent.settings.text_scale = scale
			for size: Vector2i in RESOLUTIONS:
				var viewport := SubViewport.new()
				viewport.size = size
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var main := Main.instantiate()
				viewport.add_child(main)
				var hub: Node = main.get_node_or_null("HubFlowCoordinator")
				suite.assert_true(hub != null, "real Main configures native build-sharing view")
				if hub != null:
					suite.assert_true(hub.travel("hub_craft").ok and hub.open_function("meditation").ok, "real meditation opens for rendering")
					var service: RefCounted = GameState.profile_runtime_service()
					if service.snapshot().build_library.is_empty():
						var selected: Dictionary = hub.view_state().loadout.selected
						var build := {"id": "visual-source", "name": "Chronicles of Collapse", "character_id": selected.character_id, "weapon_id": selected.weapon_id, "time_abilities": selected.enabled_time_skills.duplicate()}
						suite.assert_true(service.execute({"command_id": "visual-source", "kind": "build_save", "build": build}, service.snapshot().revision).ok, "rendered export uses a physically saved build")
						hub.refresh()
					var state: Dictionary = hub.view_state()
					var exported: Dictionary = hub.submit_command({"epoch": state.epoch, "function_id": "meditation", "operation": "build_export", "payload": {"build_id": service.snapshot().build_library[0].id}}, state.revision)
					suite.assert_true(exported.ok, "real export delivers code before capture")
					await get_tree().process_frame
					await get_tree().process_frame
					var panel: Control = hub.panel_view()
					var field: LineEdit = panel.find_child("ShareCode", true, false)
					suite.assert_true(field != null and not field.text.is_empty(), "rendered sharing code is present")
					suite.assert_true(panel.scroll.get_global_rect().encloses(field.get_global_rect()), "exported share field is fully visible after native focus scrolling")
					for control: Control in panel.find_children("*", "Control", true, false):
						if not control.is_visible_in_tree() or control.get_parent() is ScrollContainer:
							continue
						if control is Button or control is LineEdit or control is Label:
							suite.assert_true(control.get_combined_minimum_size().x <= control.size.x + 1 and control.get_combined_minimum_size().y <= control.size.y + 1, "localized sharing control fits its container " + str([locale, scale, size, control.name]))
					if capture:
						await RenderingServer.frame_post_draw
						var pixels := viewport.get_texture().get_image()
						suite.assert_true(pixels != null and not pixels.is_empty(), "native sharing produces actual pixels")
						if pixels != null and not pixels.is_empty():
							var colors: Dictionary = {}
							for y: int in range(0, pixels.get_height(), 8):
								for x: int in range(0, pixels.get_width(), 8):
									colors[pixels.get_pixel(x, y).to_rgba32()] = true
									if colors.size() > 16:
										break
								if colors.size() > 16:
									break
							suite.assert_true(colors.size() > 8, "native sharing screenshot is nonblank")
							var output := "res://build/p20a-sharing-screenshots/%s-%s-%dx%d.png" % [locale, str(scale), size.x, size.y]
							DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
							suite.assert_equal(pixels.save_png(output), OK, "native sharing raster retained")
				viewport.queue_free()
				await get_tree().process_frame
				await get_tree().process_frame
	suite.finish(get_tree())
