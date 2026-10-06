extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Model := preload("res://scripts/onboarding/tutorial_view_model.gd")
const Remap := preload("res://scripts/input/input_remap_service.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")
const TutorialScene := preload("res://scenes/ui/tutorial_panel.tscn")
const HintScene := preload("res://scenes/ui/tutorial_hint_presenter.tscn")
const TrainingView := preload("res://scripts/training/training_panel_view.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	suite.assert_true(not registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH").has_blocking_errors(), "onboarding uses shipping content and translations")
	var remap := Remap.new()
	remap.configure(OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("onboarding-remap"))
	suite.assert_true(remap.load_or_defaults().ok, "onboarding uses saved binding projection")
	var catalog := Fixtures.catalog()
	var profile := Fixtures.profile(catalog)
	var entries: Array = registry.get_catalog_entries(&"tutorial_definition", &"LAUNCH")
	var model := Model.new()
	suite.assert_true(model.configure(entries, catalog, remap).ok, "onboarding projects exact authored requirements")
	var projected: Dictionary = model.project(profile, "onboarding-profile", "controller", "rift")
	suite.assert_true(projected.ok, "fresh profile projects tutorial")
	var state: Dictionary = projected.context.view_state
	var instant: Dictionary = entries.filter(func(row: Dictionary) -> bool: return row.definition_kind == "hint" and row.style == "instant")[0]
	var hint_state: Dictionary = model.project_hint(instant, state.revision, "onboarding-run", "controller", "rift").context.view_state
	var screenshot := OS.get_cmdline_user_args().has("--onboarding-finish-screenshots")
	var probe := OS.get_environment("PLANEWALKER_UI_RED_PROBE") == "1"
	for locale: String in (["en"] if probe else ["zh_CN", "en"]):
		for scale: float in ([1.5] if probe else [1.0, 1.5]):
			GameState.persistent.settings.locale = locale
			GameState.persistent.settings.text_scale = scale
			TranslationServer.set_locale(locale)
			var accessibility := Accessibility.new()
			add_child(accessibility)
			for resolution: Vector2i in ([Vector2i(640, 360)] if probe else RESOLUTIONS):
				var viewport := SubViewport.new()
				viewport.size = resolution
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var previous := Button.new()
				viewport.add_child(previous)
				previous.grab_focus()
				var tutorial: Control = TutorialScene.instantiate()
				viewport.add_child(tutorial)
				suite.assert_true(tutorial.render(state).ok, "finished tutorial accepts exact projected state")
				accessibility.apply_to_tree(tutorial)
				await _frames(4)
				var root: Control = tutorial.get("panel_root")
				var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
				suite.assert_true(bounds.encloses(root.get_global_rect()) and root.size.x <= 616 and root.size.y <= 560, "onboarding shell preserves bounds: " + str([locale, scale, resolution]))
				var progress := tutorial.find_child("SelectedLessonMeter", true, false) as ProgressBar
				suite.assert_true(progress != null, "selected lesson exposes actual requirement progress graphically")
				if progress != null:
					var expected := Vector2.ZERO
					for row: Dictionary in state.lessons[0].requirements:
						expected += Vector2(row.current, row.count)
					suite.assert_equal(Vector2(progress.value, progress.max_value), expected, "lesson progress is derived solely from canonical counters")
				suite.assert_true((tutorial.get("back_button") as Button).icon != null, "tutorial footer has authenticated close artwork")
				if screenshot:
					await _capture(viewport, "tutorial", locale, scale, resolution, suite)
				tutorial.close_panel()
				tutorial.queue_free()
				await _frames(2)
				previous.grab_focus()
				var hint: Control = HintScene.instantiate()
				viewport.add_child(hint)
				hint.set_physics_process(false)
				suite.assert_true(hint.render_saved_hint(hint_state).ok, "finished hint retains persisted authored contract")
				accessibility.apply_to_tree(hint)
				await _frames(4)
				suite.assert_true((hint.get("hint_panel") as Control).get_theme_stylebox("panel") is StyleBoxTexture, "hints use the authored pixel frame")
				var close := hint.get("close_button") as Button
				suite.assert_true(close.icon != null and close.text.is_empty() and close.focus_mode == Control.FOCUS_NONE, "hint dismissal is an icon and preserves gameplay focus")
				suite.assert_true(viewport.gui_get_focus_owner() == previous, "hint does not steal gameplay focus")
				suite.assert_true(bounds.encloses((hint.get("hint_panel") as Control).get_global_rect()), "enlarged localized hint remains bounded")
				if screenshot:
					await _capture(viewport, "hint", locale, scale, resolution, suite)
				hint.queue_free()
				await _frames(2)
				var training := TrainingView.new()
				viewport.add_child(training)
				suite.assert_true(training.configure(registry), "training selectors use every launch loadout identity")
				var selected := {"task_id": "T-01", "seed": 42, "character_id": "void_walker", "weapon_id": "gauntlets", "time_abilities": ["stop", "accelerate"]}
				training.select_request(selected)
				accessibility.apply_to_tree(training)
				await _frames(4)
				suite.assert_true(training.theme != null, "training uses the shared production typography and controls")
				for field: String in ["character_id", "weapon_id", "time_abilities"]:
					var option := training.selector(field)
					for index: int in range(option.item_count):
						suite.assert_true(option.get_item_icon(index) != null, "every loadout option has actual canonical art: " + field)
						if field in ["character_id", "weapon_id"]:
							var id := str(option.get_item_metadata(index))
							var expected := Art.actor(id) if field == "character_id" else Art.icon(&"weapons", StringName(id))
							suite.assert_equal(option.get_item_icon(index), expected, "training art retains every exact loadout identity")
						suite.assert_true(bounds.encloses(option.get_global_rect()), "training controls preserve usable play area")
				TranslationServer.set_locale("en" if locale == "zh_CN" else "zh_CN")
				await _frames(2)
				suite.assert_equal(training.selected_request(), selected, "locale redraw preserves the exact selected training request")
				TranslationServer.set_locale(locale)
				await _frames(2)
				if screenshot:
					await _capture(viewport, "training-controls", locale, scale, resolution, suite)
				training.queue_free()
				previous.queue_free()
				viewport.queue_free()
				await _frames(2)
			accessibility.queue_free()
			await _frames(2)
	suite.finish(get_tree())


func _capture(viewport: SubViewport, kind: String, locale: String, scale: float, resolution: Vector2i, suite: RefCounted) -> void:
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	if pixels == null or pixels.is_empty():
		suite.assert_true(false, "onboarding retained actual native pixels")
		return
	var output := "res://build/ui-finish-onboarding-screenshots/%s-%s-%s-%dx%d.png" % [kind, locale, scale, resolution.x, resolution.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	suite.assert_equal(pixels.save_png(output), OK, "onboarding native screenshot is retained")


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
