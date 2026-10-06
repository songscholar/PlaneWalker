extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await _frames()
	var library: Node = main.get_node("ReplayLibrary")
	var replay_panel: Control = main.get_node("ReplayLibraryLayer/ReplayLibraryPanel")
	suite.assert_true(replay_panel.open().ok, "real replay router opens empty library")
	suite.assert_true(replay_panel.find_child("ReplayPicture", true, false) == null, "empty state does not invent a playback viewport")
	var recording := await Fixture.record(self, main.runtime_host.content_registry(), suite, "ui-finish-recording", 509)
	var stored: Dictionary = library.store(recording)
	suite.assert_true(stored.ok, "authentic recorded Player enters archive")
	await _frames()
	suite.assert_true(replay_panel.find_child("RecordingArtwork", true, false) != null, "recording rows display authentic character artwork")
	suite.assert_true(library.select(stored.context.id).ok and library.seek(3).ok, "real replay viewport restores recorded frame")
	await _frames()
	suite.assert_true(replay_panel.find_child("ReplayPicture", true, false) != null, "selected recording retains real world texture")
	var timeline := replay_panel.find_child("ReplayTimeline", true, false) as HSlider
	var controls := replay_panel.find_child("ReplayControls", true, false) as Control
	suite.assert_true(timeline != null and controls != null, "native timeline and reachable playback controls exist")
	if timeline != null:
		suite.assert_equal(int(timeline.value), 3, "timeline displays accepted frame index")
	for id: String in ["play", "import", "export", "remove"]:
		var tool := _action(replay_panel, id)
		suite.assert_true(tool != null and tool.icon != null and not tool.tooltip_text.is_empty(), "replay tool has bitmap and accessible name " + id)
	await _matrix(suite, replay_panel, "replay")
	replay_panel.close_panel()
	await _frames()
	var platform: Control = main.get_node("PlatformLayer/PlatformPanel")
	suite.assert_true(platform.open().ok, "actual offline provider opens native platform page")
	suite.assert_true(platform.find_child("PlatformSections", true, false) is TabBar, "platform sections use native persistent tabs")
	suite.assert_true(platform.find_child("PlatformStatusArtwork", true, false) != null, "platform discloses actual capability state with artwork")
	suite.assert_equal(platform.view_state().model.status, "OFFLINE", "offline page never invents account success")
	for section: String in ["storage", "community", "content", "sharing", "account"]:
		suite.assert_true(platform.select_section(section).ok, "offline navigation remains reachable " + section)
	await _matrix(suite, platform, "platform")
	platform.close_panel()
	await _frames()
	var content: Control = main.get_node("ContentManagementLayer/ContentManagementPanel")
	suite.assert_true(main.open_content_management().ok, "production router opens content management above hub presentation")
	var state := {"run_id": "content-manager", "revision": 7, "epoch": 7, "locked": false, "activation": {"save_domain": "base", "activation_order": ["base"]}, "entitlements": {}, "diagnostics": [{"pack_id": "broken_prism", "code": "CONTENT_UNAVAILABLE"}], "installed": [{"pack_id": "local_prism", "pack_version": "1.0.0", "enabled": false, "owned": true}]}
	suite.assert_true(content.render(state).ok, "installed and quarantined package facts render")
	await _frames()
	suite.assert_true(content.find_child("ContentPackArtwork", true, false) != null, "package rows expose actual pack artwork")
	suite.assert_true(content.find_child("ContentDiagnostic", true, false) != null, "quarantine diagnosis has a distinct visible row")
	suite.assert_true(content.find_child("ContentCommands", true, false) != null, "package commands stay outside detail scrolling")
	suite.assert_equal(content.view_state(), state, "presentation preserves exact pack and diagnostic facts")
	await _matrix(suite, content, "content")
	content.close_panel()
	main.queue_free()
	await _frames()
	suite.finish(get_tree())


func _action(panel: Control, id: String) -> Button:
	for control: Control in panel.action_controls():
		if str(control.get_meta("action_id", "")) == id:
			return control as Button
	return null


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _matrix(suite: RefCounted, panel: Control, id: String) -> void:
	var locale_before := TranslationServer.get_locale()
	var scale_before: Variant = GameState.get_setting("text_scale", 1.0)
	var size_before: Vector2i = get_viewport().size
	for locale: String in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		for scale: float in [1.0, 1.5]:
			GameState.set_setting("text_scale", scale)
			for resolution: Vector2i in RESOLUTIONS:
				get_viewport().size = resolution
				for runtime: Node in get_tree().get_nodes_in_group("accessibility_runtime"):
					runtime.apply_to_tree(panel)
				await _frames()
				var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
				suite.assert_true(bounds.encloses(panel.panel_root.get_global_rect()), "surface shell fits " + str([id, locale, scale, resolution]))
				for control: Control in panel.find_children("*", "Control", true, false):
					if not control.is_visible_in_tree() or _inside_scroll(control, panel):
						continue
					suite.assert_true(bounds.encloses(control.get_global_rect()), "surface command stays visible " + str([id, locale, scale, resolution, control.name]))
					if control is Button or control is Label:
						suite.assert_true(control.get_combined_minimum_size().x <= control.size.x + 1 and control.get_combined_minimum_size().y <= control.size.y + 1, "surface text fits " + str([id, locale, scale, resolution, control.name]))
				await _capture(suite, panel, "%s-%s-%s-%dx%d" % [id, locale, scale, resolution.x, resolution.y])
	get_viewport().size = size_before
	TranslationServer.set_locale(locale_before)
	GameState.set_setting("text_scale", scale_before)
	await _frames()


func _inside_scroll(control: Control, panel: Control) -> bool:
	var parent := control.get_parent()
	while parent != null and parent != panel:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false


func _capture(suite: RefCounted, panel: Control, id: String) -> void:
	if not OS.get_cmdline_user_args().has("--surface-finish-screenshots"):
		return
	await RenderingServer.frame_post_draw
	var pixels := get_viewport().get_texture().get_image()
	suite.assert_true(pixels != null and not pixels.is_empty(), "native surface renders real pixels " + id)
	if pixels == null or pixels.is_empty():
		return
	var output := "res://build/ui-product-surfaces-screenshots/" + id + ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	suite.assert_equal(pixels.save_png(output), OK, "surface screenshot is retained " + id)
	suite.assert_true(panel.panel_root.get_global_rect().encloses(panel.back_button.get_global_rect()), "surface keeps return command visible " + id)
