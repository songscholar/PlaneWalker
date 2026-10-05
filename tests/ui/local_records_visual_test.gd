extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Fixture := preload("res://tests/integration/save/local_run_records_test.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var capture := OS.get_cmdline_user_args().has("--records-screenshots")
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
				suite.assert_true(hub != null, "real Main creates native local record view")
				if hub != null:
					var service: RefCounted = GameState.profile_runtime_service()
					if service.snapshot().last_settlement_receipt.is_empty():
						var fixture := Fixture.new()
						fixture._settle(suite, service, 98765, true)
						fixture.free()
						suite.assert_true(main._sync_local_records().ok, "visual record originates from physical settlement authentication")
					hub.refresh()
					suite.assert_true(hub.travel("hub_rift").ok and hub.open_function("mirror").ok, "native mirror opens for raster capture")
					_action(hub, "provider_refresh:leaderboard").pressed.emit()
					await get_tree().process_frame
					await get_tree().process_frame
					await get_tree().process_frame
					await get_tree().process_frame
					var panel: Control = hub.panel_view()
					var visible_record := false
					for row: Control in panel.rows_container.get_children():
						if row.get_meta("provider_record", "") == "leaderboard":
							visible_record = panel.scroll.get_global_rect().encloses(row.get_global_rect())
							break
					suite.assert_true(visible_record, "actual refreshed result remains visible in native scroll region " + str([locale, scale, size, panel.scroll.scroll_vertical]))
					var row_present := false
					for row: Dictionary in hub.view_state().providers:
						row_present = row_present or row.id == "leaderboard" and row.available and not row.entries.is_empty()
					suite.assert_true(row_present, "native mirror has authenticated record before capture")
					for control: Control in panel.find_children("*", "Control", true, false):
						if not control.is_visible_in_tree() or control.get_parent() is ScrollContainer:
							continue
						if control is Button or control is Label:
							suite.assert_true(control.get_combined_minimum_size().x <= control.size.x + 1 and control.get_combined_minimum_size().y <= control.size.y + 1, "localized record control fits container " + str([locale, scale, size, control.name]))
					if capture:
						await RenderingServer.frame_post_draw
						var pixels := viewport.get_texture().get_image()
						suite.assert_true(pixels != null and not pixels.is_empty(), "native records render actual raster")
						if pixels != null and not pixels.is_empty():
							var colors: Dictionary = {}
							for y: int in range(0, pixels.get_height(), 8):
								for x: int in range(0, pixels.get_width(), 8):
									colors[pixels.get_pixel(x, y).to_rgba32()] = true
									if colors.size() > 16: break
								if colors.size() > 16: break
							suite.assert_true(colors.size() > 8, "native local-record screenshot is nonblank")
							var output := "res://build/p20b-records-screenshots/%s-%s-%dx%d.png" % [locale, str(scale), size.x, size.y]
							DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
							suite.assert_equal(pixels.save_png(output), OK, "native local-record raster retained")
				viewport.queue_free()
				await get_tree().process_frame
				await get_tree().process_frame
	suite.finish(get_tree())


func _action(hub: Node, id: String) -> Button:
	for control: Control in hub.panel_view().action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null
