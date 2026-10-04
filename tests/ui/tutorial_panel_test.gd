extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Model := preload("res://scripts/onboarding/tutorial_view_model.gd")
const Remap := preload("res://scripts/input/input_remap_service.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")
var suite: RefCounted
var _requests: Array = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var path := "res://scenes/ui/tutorial_panel.tscn"
	var hint_path := "res://scenes/ui/tutorial_hint_presenter.tscn"
	suite.assert_true(ResourceLoader.exists(path) and ResourceLoader.exists(hint_path), "native tutorial recall and saved hint scenes exist")
	if not ResourceLoader.exists(path) or not ResourceLoader.exists(hint_path):
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	suite.assert_true(not registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH").has_blocking_errors(), "UI milestone loads actual Registry with final exact localization integrity")
	_install_translations()
	var catalog := Fixtures.catalog()
	var profile := Fixtures.profile(catalog)
	var input := Remap.new()
	input.configure()
	var model := Model.new()
	var entries: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/tutorial_definitions.json"))
	model.configure(entries, catalog, input)
	var projected: Dictionary = model.project(profile, "profile-main", "controller", "rift")
	suite.assert_true(projected.ok, "real authored tutorial state projects for native scene")
	if not projected.ok:
		suite.finish(get_tree())
		return
	var state: Dictionary = projected.context.view_state
	var original_scale := float(GameState.get_setting("text_scale", 1.0))
	var original_locale := TranslationServer.get_locale()
	get_viewport().size = Vector2i(640, 360)
	var previous := Button.new()
	add_child(previous)
	previous.grab_focus()
	var panel: Control = load(path).instantiate()
	add_child(panel)
	await get_tree().process_frame
	suite.assert_true(panel.render(state).ok, "native recall panel accepts exact projected content")
	await _layout()
	suite.assert_true(panel.visible and FocusCoordinator.active_scope() == panel, "opening recall owns explicit controller scope")
	panel.lesson_skip_requested.connect(func(id: StringName, revision: int) -> void: _requests.append(["skip", id, revision]))
	var recall: Button = _action(panel, "lesson:weapon_basics")
	suite.assert_true(recall != null, "every authored lesson offers read-only recall")
	if recall != null:
		recall.pressed.emit()
		suite.assert_equal(panel.view_state(), state, "recall cannot mutate authoritative progress or currency")
		suite.assert_true(panel.find_child("SelectedLessonText", true, false) != null, "recall shows actual authored lesson content")
	var skip: Button = _action(panel, "skip:weapon_basics")
	suite.assert_true(skip != null, "selected unfinished lesson offers explicit skip")
	if skip != null:
		skip.pressed.emit()
		skip.pressed.emit()
		suite.assert_equal(_requests, [["skip", &"weapon_basics", int(state.revision)]], "one semantic skip carries its exact Profile revision and cannot double submit")
		panel.show_rejection("UI_TUTORIAL_RETRY")
		suite.assert_true(not skip.disabled, "failed Save restores a retryable lesson command")
	var hints: CheckBox = _action(panel, "tutorial_hints")
	suite.assert_true(hints != null and hints.button_pressed, "contextual hint preference uses a real binary control")
	panel.hint_suppression_requested.connect(func(suppressed: bool, revision: int) -> void: _requests.append(["suppress", suppressed, revision]))
	if hints != null:
		hints.button_pressed = false
		hints.pressed.emit()
		suite.assert_equal(_requests[-1], ["suppress", true, int(state.revision)], "binary preference requests durable suppression rather than silently changing Profile")
		panel.show_rejection("UI_TUTORIAL_RETRY")
		suite.assert_true(hints.button_pressed, "rejected preference returns to saved authoritative value")
	var mode: OptionButton = _action(panel, "tutorial_mode")
	panel.guided_mode_requested.connect(func(enabled: bool, revision: int) -> void: _requests.append(["guided", enabled, revision]))
	mode.select(1)
	mode.item_selected.emit(1)
	suite.assert_equal(_requests[-1], ["guided", true, int(state.revision)], "guided protection requires an explicit mode command")
	suite.assert_true(not panel.view_state().guided_selected, "requesting assistance cannot silently mutate the authoritative view")
	panel.show_rejection("UI_TUTORIAL_RETRY")
	suite.assert_equal(mode.selected, 0, "rejected assistance choice restores ordinary mode")
	panel.training_requested.connect(func(id: StringName, revision: int) -> void: _requests.append(["training", id, revision]))
	var training := _action(panel, "training:T-01")
	training.pressed.emit()
	suite.assert_equal(_requests[-1], ["training", &"T-01", int(state.revision)], "training requires its own authenticated native session request")
	panel.show_rejection("UI_TUTORIAL_RETRY")
	var stale_control: Button = _action(panel, "skip:weapon_basics")
	var newer := state.duplicate(true)
	newer.revision += 1
	suite.assert_true(panel.render(newer).ok, "newer Profile state replaces the tutorial view")
	var before_count := _requests.size()
	if stale_control != null:
		stale_control.pressed.emit()
	suite.assert_equal(_requests.size(), before_count, "removed controls cannot send commands against a newer Profile")
	suite.assert_true(not panel.render(state).ok, "old Profile view cannot replace a newer tutorial revision")
	var bad := newer.duplicate(true)
	bad.private_profile = profile
	suite.assert_true(not panel.render(bad).ok and panel.view_state() == newer, "invalid view refuses without changing native presentation")
	var accessibility := Accessibility.new()
	add_child(accessibility)
	for locale: String in ["zh_CN", "en"]:
		TranslationServer.set_locale(locale)
		for scale: float in [1.0, 1.5]:
			GameState.set_setting("text_scale", scale)
			for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]:
				get_viewport().size = resolution
				accessibility.apply_to_tree(panel)
				await _layout()
				var root: Control = panel.get("panel_root")
				suite.assert_true(root.get_global_rect().position.x >= 15.9 and root.get_global_rect().end.x <= resolution.x - 15.9 and root.get_global_rect().end.y <= resolution.y - 15.9, "localized scaled tutorial keeps native safe area at " + str(resolution))
				suite.assert_true(not panel.get("title_label").text.begins_with("UI_"), "tutorial title resolves real bilingual localization")
				suite.assert_true(get_viewport().gui_get_focus_owner() != null, "locale and scale changes retain reachable controller focus")
				await _capture("tutorial-%s-%dx%d-scale-%d" % [locale, resolution.x, resolution.y, int(scale * 100.0)])
	await _exercise_controller(panel)
	panel.close_panel()
	await _layout()
	suite.assert_equal(get_viewport().gui_get_focus_owner(), previous, "closing recall restores the previous controller focus")
	var hint: Control = load(hint_path).instantiate()
	add_child(hint)
	get_viewport().size = Vector2i(640, 360)
	await get_tree().process_frame
	var instant: Dictionary = entries.filter(func(row: Dictionary) -> bool: return row.definition_kind == "hint" and row.style == "instant")[0]
	var hint_view: Dictionary = model.project_hint(instant, newer.revision, "native-run", "controller", "rift")
	suite.assert_true(hint.render_saved_hint(hint_view.context.view_state).ok, "saved actual authored hint renders through strict projection")
	hint.set_physics_process(false)
	await _layout()
	suite.assert_true(hint.visible and get_viewport().gui_get_focus_owner() == previous, "saved hint does not steal gameplay controller focus")
	await _capture("hint-en-640x360-scale-150")
	var altered: Dictionary = hint_view.context.view_state.duplicate(true)
	altered.actions.append({"semantic_action_id": "delete_profile"})
	suite.assert_true(not hint.render_saved_hint(altered).ok, "malformed saved hint cannot enter the presenter")
	get_tree().paused = true
	for index: int in range(180):
		hint.advance_display_frame()
	suite.assert_true(hint.visible, "paused gameplay cannot expire instant teaching prompts")
	get_tree().paused = false
	for index: int in range(179):
		hint.advance_display_frame()
	suite.assert_true(hint.visible, "instant hint remains visible through 179 active display frames")
	hint.advance_display_frame()
	suite.assert_true(not hint.visible, "instant hint closes at its authored 180 active frames")
	TranslationServer.set_locale(original_locale)
	GameState.set_setting("text_scale", original_scale)
	panel.queue_free()
	hint.queue_free()
	previous.queue_free()
	accessibility.queue_free()
	await _layout()
	suite.finish(get_tree())


func _capture(name: String) -> void:
	var directory := OS.get_environment("PLANEWALKER_UI_VISUAL_DIR")
	if directory.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	var rendered: Image = get_viewport().get_texture().get_image()
	suite.assert_true(rendered != null and not rendered.is_empty(), "native tutorial screenshot has rendered pixels")
	if rendered == null or rendered.is_empty():
		return
	var colors: Dictionary = {}
	for y: int in range(0, rendered.get_height(), 8):
		for x: int in range(0, rendered.get_width(), 8):
			colors[rendered.get_pixel(x, y).to_rgba32()] = true
	suite.assert_true(colors.size() > 8, "native tutorial screenshot is nonblank")
	suite.assert_equal(rendered.save_png(directory.path_join(name + ".png")), OK, "actual native tutorial screenshot saves")


func _action(panel: Node, id: String) -> Button:
	for control: Control in panel.action_controls():
		if control.get_meta("action_id", "") == id:
			return control as Button
	return null


func _layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _exercise_controller(panel: Control) -> void:
	var controls: Array = panel.action_controls().filter(func(control: Button) -> bool: return not control.disabled)
	controls.append(panel.get("back_button"))
	controls[0].grab_focus()
	for index: int in range(controls.size()):
		suite.assert_equal(get_viewport().gui_get_focus_owner(), controls[index], "controller reaches every tutorial command in explicit order")
		var event := InputEventAction.new()
		event.action = &"ui_down"
		event.pressed = true
		Input.parse_input_event(event)
		await _layout()
		event = InputEventAction.new()
		event.action = &"ui_down"
		event.pressed = false
		Input.parse_input_event(event)
		await _layout()
	suite.assert_equal(get_viewport().gui_get_focus_owner(), controls[0], "tutorial controller traversal wraps inside active scope")


func _install_translations() -> void:
	var file := FileAccess.open("res://data/localization/translations.csv", FileAccess.READ)
	var locales := file.get_csv_line()
	for index: int in range(1, locales.size()):
		var translation := Translation.new()
		translation.locale = locales[index]
		file.seek(0)
		file.get_csv_line()
		while not file.eof_reached():
			var row := file.get_csv_line()
			if row.size() == locales.size() and not row[0].is_empty():
				translation.add_message(row[0], row[index])
		TranslationServer.add_translation(translation)
