extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Binding := preload("res://scripts/content/content_snapshot_provider.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const Library := preload("res://scripts/replay/player_replay_library.gd")
const PANEL_PATH := "res://scripts/replay/player_replay_library_panel.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(PANEL_PATH), "native replay library panel must exist")
	if not ResourceLoader.exists(PANEL_PATH):
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var library := Library.new()
	add_child(library)
	suite.assert_true(library.configure(OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("panel_library"), "0.4.0-dev", Binding.snapshot(registry), "slot_1", "base").ok, "panel has a physical archive")
	var panel: Control = load(PANEL_PATH).new()
	add_child(panel)
	suite.assert_true(panel.configure(library).ok and panel.open().ok, "native panel opens with empty archive")
	suite.assert_true(panel.rows_container.get_node_or_null("EmptyLibrary") != null, "empty archive displays expected state")
	var replay := await Fixture.record(self, registry, suite, "panel-recording", 444)
	var stored: Dictionary = library.store(replay)
	suite.assert_true(stored.ok, "actual recording appears in the open panel")
	var selector: OptionButton = panel.rows_container.find_child("RecordingSelector", true, false)
	var retired_selector: Callable = selector.item_selected.get_connections()[0].callable
	suite.assert_true(selector != null and selector.item_count == 2, "native selector includes recording and neutral prompt")
	if selector != null:
		selector.select(1)
		selector.item_selected.emit(1)
		suite.assert_equal(library.snapshot().selected_id, stored.context.id, "native selection admits viewer")
	var slider: HSlider = panel.rows_container.find_child("ReplayTimeline", true, false)
	suite.assert_true(slider != null, "viewer exposes a seek control")
	if slider != null:
		slider.value = 3
		suite.assert_equal(library.snapshot().cursor, 3, "native seek control restores recorded frame")
	var selected_player := library.current_player()
	retired_selector.call(1)
	suite.assert_true(library.current_player() == selected_player and library.snapshot().cursor == 3, "retired selector callback cannot replace the current viewer")
	var speed: OptionButton = panel.rows_container.find_child("PlaybackSpeed", true, false)
	var retired_speed: Callable = speed.item_selected.get_connections()[0].callable
	var retired_seek: Callable = slider.value_changed.get_connections()[0].callable
	speed.select(2)
	speed.item_selected.emit(2)
	suite.assert_equal(library.snapshot().speed, 2.0, "native speed selector controls accepted timeline speed")
	var visual_path := OS.get_environment("PLANEWALKER_REPLAY_VISUAL_OUTPUT")
	if not visual_path.is_empty():
		await _capture_visuals(panel, library, suite, visual_path)
	var stale_player := library.current_player()
	var retired: Callable
	for action: Control in panel.action_controls():
		if action.get_meta("action_id", "") == "remove":
			retired = action.pressed.get_connections()[0].callable
		if action.get_meta("action_id", "") == "play":
			action.pressed.emit()
	suite.assert_true(library.snapshot().playing, "native play command starts timeline")
	library.set_playing(false)
	panel.close_panel()
	suite.assert_true(not panel.visible and library.current_player() == null and not library.snapshot().playing, "close disposes private Player and stops playback")
	if retired.is_valid():
		retired.call()
	suite.assert_equal(library.rows().size(), 1, "retired hidden control cannot remove recording")
	await get_tree().process_frame
	suite.assert_true(not is_instance_valid(stale_player), "closed viewport releases actual viewing actor")
	suite.assert_true(panel.open().ok, "library reopens with retained recording")
	suite.assert_true(FocusCoordinator.active_scope() == panel, "native reopening restores controller scope")
	await get_tree().process_frame
	selector = panel.rows_container.find_child("RecordingSelector", true, false)
	selector.grab_focus()
	await _send_button(JOY_BUTTON_DPAD_RIGHT)
	suite.assert_equal(library.snapshot().selected_id, stored.context.id, "physical D-pad selects retained recording")
	if library.snapshot().selected_id.is_empty():
		library.select(stored.context.id)
	await get_tree().process_frame
	retired_speed.call(0)
	retired_seek.call(4.0)
	suite.assert_true(library.snapshot().speed == 2.0 and library.snapshot().cursor == 0, "retired playback controls cannot mutate the reopened viewer")
	speed = panel.rows_container.find_child("PlaybackSpeed", true, false)
	speed.grab_focus()
	await _send_button(JOY_BUTTON_DPAD_LEFT)
	suite.assert_equal(library.snapshot().speed, 1.0, "physical D-pad changes playback speed")
	slider = panel.rows_container.find_child("ReplayTimeline", true, false)
	slider.grab_focus()
	await _send_button(JOY_BUTTON_DPAD_RIGHT)
	suite.assert_equal(library.snapshot().cursor, 1, "physical D-pad seeks an archived frame")
	await _send_button(JOY_BUTTON_DPAD_DOWN)
	suite.assert_true(get_viewport().gui_get_focus_owner() != slider, "physical D-pad moves focus between native controls")
	for action: Control in panel.action_controls():
		if action.get_meta("action_id", "") == "remove":
			action.grab_focus()
			await _send_button(JOY_BUTTON_A)
			break
	suite.assert_true(panel.get_node("ReplayDeleteDialog").visible and library.rows().size() == 1, "native delete requires confirmation before physical mutation")
	await _send_button(JOY_BUTTON_B)
	suite.assert_true(panel.visible and not panel.get_node("ReplayDeleteDialog").visible and library.rows().size() == 1, "physical B cancels deletion while keeping the viewer")
	panel.get_node("ReplayDeleteDialog").confirmed.emit()
	suite.assert_equal(library.rows().size(), 1, "retired canceled confirmation cannot remove the physical recording")
	for action: Control in panel.action_controls():
		if action.get_meta("action_id", "") == "remove":
			action.grab_focus()
			await _send_button(JOY_BUTTON_A)
			break
	panel.get_node("ReplayDeleteDialog").get_ok_button().grab_focus()
	await _send_button(JOY_BUTTON_A)
	suite.assert_equal(library.rows(), [], "native confirmation removes the actual physical recording")
	panel.close_panel()
	panel.queue_free()
	library.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _send_button(index: int) -> void:
	var pressed := InputEventJoypadButton.new()
	pressed.button_index = index
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await get_tree().process_frame
	await get_tree().process_frame
	var released := InputEventJoypadButton.new()
	released.button_index = index
	Input.parse_input_event(released)
	await get_tree().process_frame
	await get_tree().process_frame


func _capture_visuals(panel: Control, library: Node, suite: RefCounted, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(resolution)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		suite.assert_true(image != null and image.save_png(path.path_join("library-%dx%d.png" % [resolution.x, resolution.y])) == OK, "actual replay panel screenshot exports")
		suite.assert_true(panel.get_global_rect().encloses(panel.panel_root.get_global_rect()), "native library panel fits its supported viewport")
	var world_image: Image = library.current_world().get_texture().get_image()
	var colors: Dictionary = {}
	var center: Vector2i = library.current_world().size / 2
	for x: int in range(center.x - 25, center.x + 25):
		for y: int in range(center.y - 25, center.y + 25):
			colors[world_image.get_pixel(x, y).to_rgba32()] = true
	suite.assert_true(colors.size() > 3, "actual isolated native character renders nonblank pixels")
	suite.assert_true(world_image.save_png(path.path_join("isolated-player.png")) == OK, "native isolated viewport evidence exports")
