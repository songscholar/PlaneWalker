extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Archetypes := preload("res://scripts/progression/archetype_profile.gd")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")
const SCENE_PATH := "res://scenes/ui/components/build_inspector.tscn"
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(SCENE_PATH), "pause exposes a native read-only build inspection scene")
	if not ResourceLoader.exists(SCENE_PATH):
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "inspector resolves authentic runtime content")
	var capture := OS.get_cmdline_user_args().has("--build-inspector-screenshots")
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
				var inspector := (load(SCENE_PATH) as PackedScene).instantiate() as Control
				viewport.add_child(inspector)
				suite.assert_true(inspector.call("configure", registry).ok, "inspector accepts a read-only registry")
				var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/ui/hud_boss.json"))
				state.build.archetype_scores = {}
				for id: String in Archetypes.ARCHETYPE_IDS:
					state.build.archetype_scores[id] = 3 if id == "freeze_burst" else 0
				state.build.dominant_archetype = "freeze_burst"
				state.build.curses = ["curse_brittle_pact"]
				var snapshot := state.duplicate(true)
				var definition: Dictionary = registry.get_content("frozen_burst")
				suite.assert_true(inspector.call("render_build", state).ok, "build inspection accepts validated eight-archetype snapshot")
				await _frames(3)
				suite.assert_equal(state, snapshot, "inspection never mutates domain state")
				suite.assert_equal(registry.get_content("frozen_burst"), definition, "inspection never mutates content definitions")
				for pool: String in ["items", "blessings", "curses", "talents"]:
					for id: String in state.build[pool]:
						var row := inspector.find_child("BuildContent_" + id, true, false)
						suite.assert_true(row != null, "inspection includes every current " + pool + " content identity")
						if row != null:
							var detail := row.find_child("ContentDescription", true, false) as Label
							var content: Dictionary = registry.get_content(id)
							suite.assert_true(detail != null and detail.text == tr(content.description_key), "inspection retains full canonical effect description")
				for id: String in Archetypes.ARCHETYPE_IDS:
					var score := inspector.find_child("ArchetypeScore_" + id, true, false) as Label
					suite.assert_true(score != null and score.text.contains(str(state.build.archetype_scores[id])), "inspection displays all eight authoritative archetype scores")
				var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
				suite.assert_true(bounds.encloses(inspector.get("panel_root").get_global_rect()), "inspection stays within supported canvas")
				suite.assert_true(bounds.encloses(inspector.get("back_button").get_global_rect()), "inspection always preserves its return control")
				var invalid := state.duplicate(true)
				invalid.weapon_state.meter_current = -1
				suite.assert_true(not inspector.call("render_build", invalid).ok, "invalid equipment projections are refused")
				suite.assert_equal(inspector.call("view_state"), snapshot, "failed projection retains the last accepted inspection")
				if capture:
					await RenderingServer.frame_post_draw
					var pixels := viewport.get_texture().get_image()
					suite.assert_true(pixels != null and not pixels.is_empty(), "inspection renders native pixels")
					if pixels != null and not pixels.is_empty():
						var output := "res://build/ui-finish-inspector-screenshots/build-%s-%s-%dx%d.png" % [locale, scale, resolution.x, resolution.y]
						DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
						suite.assert_equal(pixels.save_png(output), OK, "inspection screenshot retained")
				inspector.call("close_panel")
				inspector.queue_free()
				await _frames(1)
				viewport.queue_free()
				await _frames(1)
			accessibility.queue_free()
			await _frames(1)
	suite.finish(get_tree())


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
