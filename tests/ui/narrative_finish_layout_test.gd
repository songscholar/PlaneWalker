extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Runtime := preload("res://scripts/narrative/narrative_runtime.gd")
const Model := preload("res://scripts/narrative/narrative_view_model.gd")
const NarrativePanel := preload("res://scripts/ui/narrative_panel_view.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	suite.assert_true(not registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH").has_blocking_errors(), "narrative presentation uses complete shipping localization")
	var entries: Array = registry.get_catalog_entries(&"narrative_definition", &"LAUNCH")
	var sources: Array = registry.get_catalog_entries(&"narrative_source_definition", &"LAUNCH")
	var catalog := Fixtures.catalog()
	var profile := Fixtures.profile(catalog, false)
	var runtime := Runtime.new()
	suite.assert_true(runtime.configure(entries, sources, catalog).ok, "narrative fixtures use the production runtime and canonical content")
	var model := Model.new()
	var cases: Dictionary = {}
	for definition: Dictionary in entries:
		if definition.definition_kind == "npc":
			var dialogue: Dictionary = runtime.dialogue_view(profile, definition.npc_id)
			cases["dialogue_" + str(definition.npc_id)] = model.dialogue(profile, "finish-" + str(definition.id), definition, dialogue.context).context.view_state
		elif definition.id == "choice_nemesis_1":
			cases.choice = model.choice(profile, "finish-choice", definition).context.view_state
		elif definition.id == "ending_shattered_freedom":
			cases.credits = model.credits(profile, "finish-credits", definition).context.view_state
	cases.story = model.story(profile, "finish-story", str(sources[0].id), str(sources[0].text_key)).context.view_state
	cases.locked_endings = model.endings(profile, "finish-locked-endings", runtime.ending_view(profile).context).context.view_state
	var discovered := profile.duplicate(true)
	for definition: Dictionary in entries:
		if definition.definition_kind == "ending":
			discovered.narrative_state.endings.append(definition.ending_id)
	discovered.narrative_state.endings.sort()
	cases.gallery_endings = model.endings(discovered, "finish-gallery-endings", runtime.ending_view(discovered).context).context.view_state
	var capture := OS.get_cmdline_user_args().has("--narrative-finish-screenshots")
	var probe := OS.get_environment("PLANEWALKER_UI_RED_PROBE") == "1"
	for locale: String in (["zh_CN"] if probe else ["zh_CN", "en"]):
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
				var panel := NarrativePanel.new()
				viewport.add_child(panel)
				for case_id: String in cases:
					var state: Dictionary = cases[case_id]
					var before := state.duplicate(true)
					suite.assert_true(panel.render(state).ok, "finished native narrative accepts " + case_id)
					await _frames(3)
					suite.assert_equal(state, before, "narrative composition preserves the entire projection")
					if state.mode == "dialogue" or state.mode == "choice":
						var portrait := panel.find_child("NarrativePortrait", true, false) as TextureRect
						var npc_id := str(state.subject_id) if state.mode == "dialogue" else "nemesis"
						suite.assert_true(portrait != null and portrait.texture == Art.icon(&"npc_portraits", StringName(npc_id)), "dialogue and choice use their exact canonical NPC portrait")
					elif state.mode == "credits":
						var ending := panel.find_child("EndingArtwork", true, false) as TextureRect
						suite.assert_true(ending != null and ending.texture == Art.icon(&"ending_art", StringName(state.subject_id)), "credits preserve the selected ending identity")
					elif state.mode == "ending":
						for row: Dictionary in state.rows:
							var ending := panel.find_child("EndingArtwork_" + str(row.choice_id), true, false) as TextureRect
							var expected := Art.icon(&"room_types", &"unknown") if row.name_key == "UI_NARRATIVE_NEEDS" else Art.icon(&"ending_art", StringName(row.choice_id))
							suite.assert_true(ending != null and ending.texture == expected, "ending artwork cannot reveal unprojected story knowledge")
					var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
					suite.assert_true(bounds.encloses(panel.panel_root.get_global_rect()), "narrative shell stays bounded: " + str([case_id, locale, scale, resolution]))
					suite.assert_true(panel.scroll.focus_mode == Control.FOCUS_ALL, "narrative remains readable using controller scrolling")
					if case_id == "locked_endings" and resolution == Vector2i(640, 360):
						panel.scroll.grab_focus()
						var down := InputEventAction.new()
						down.action = &"ui_down"
						down.pressed = true
						viewport.push_input(down)
						await _frames(2)
						suite.assert_true(panel.scroll.scroll_vertical > 0, "locked ending knowledge remains readable through native focus input")
						panel.scroll.scroll_vertical = 0
						await _frames(2)
					if capture and case_id in ["dialogue_phia", "choice", "story", "credits", "gallery_endings", "locked_endings"]:
						await RenderingServer.frame_post_draw
						var pixels := viewport.get_texture().get_image()
						suite.assert_true(pixels != null and not pixels.is_empty(), "narrative has native rendered pixels")
						if pixels != null and not pixels.is_empty():
							var output := "res://build/ui-finish-narrative-screenshots/%s-%s-%s-%dx%d.png" % [case_id, locale, scale, resolution.x, resolution.y]
							DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
							suite.assert_equal(pixels.save_png(output), OK, "native narrative screenshot is retained")
					panel.close_panel()
				viewport.queue_free()
				await _frames(2)
			accessibility.queue_free()
			await _frames(2)
	suite.finish(get_tree())


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
