extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Scene := preload("res://scenes/ui/choice_panel_v2.tscn")
const Registry := preload("res://scripts/content/content_registry.gd")
const Draft := preload("res://scripts/rewards/draft_service.gd")
const Accessibility := preload("res://scripts/accessibility/accessibility_runtime.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var capture := OS.get_cmdline_user_args().has("--choice-finish-screenshots")
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
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
				var panel := Scene.instantiate() as Control
				viewport.add_child(panel)
				for kind: String in ["starter", "reinforcement", "talent", "contract"]:
					var draft := Draft.new()
					var generated = draft.create_offer(registry, _run_snapshot(kind), {"room_number": 1, "reward_kind": kind})
					suite.assert_true(generated.ok, "native choice data comes from the authentic deterministic draft service")
					if not generated.ok:
						continue
					var offer: Dictionary = generated.context.offer
					var snapshot := offer.duplicate(true)
					suite.assert_true(panel.call("render", offer).ok, "finished choice accepts validated " + kind + " offer")
					await _frames(3)
					suite.assert_equal(offer, snapshot, "choice artwork never mutates offer data")
					var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
					var root: Control = panel.get("panel_root")
					suite.assert_true(tr(offer.title_key) != offer.title_key, "actual choice title is localized")
					suite.assert_true(bounds.encloses(root.get_global_rect()), "choice stays inside supported canvas: " + str([kind, locale, scale, resolution]))
					for button: Button in panel.get("options_container").get_children():
						var artwork := button.find_child("ChoiceArtwork", true, false) as TextureRect
						suite.assert_true(artwork != null and artwork.texture != null, "each option has authentic content or decline artwork")
						if artwork != null:
							suite.assert_equal(artwork.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "choice artwork retains nearest sampling")
						var scroll := button.find_child("DetailsScroll", true, false) as ScrollContainer
						suite.assert_true(scroll != null, "each choice has independently readable detail content")
						if scroll != null:
							suite.assert_true(button.get_global_rect().encloses(scroll.get_global_rect()), "details scroll is bounded by its stable card")
							var before := scroll.scroll_vertical
							var action := InputEventAction.new()
							action.action = &"ui_down"
							action.pressed = true
							button.gui_input.emit(action)
							if scroll.get_v_scroll_bar().max_value > scroll.size.y:
								suite.assert_true(scroll.scroll_vertical > before, "controller can read lower choice details without submitting")
							scroll.scroll_vertical = 0
						var meta := button.find_child("MetaLabel", true, false) as Label
						var option_id := str(button.get_meta("option_id"))
						for option: Dictionary in snapshot.options:
							if option.option_id == option_id:
								suite.assert_true(meta != null and meta.text.contains(tr("RARITY_" + str(option.rarity).to_upper())), "choice rarity uses canonical localization")
								for key: String in [option.name_key, option.description_key, option.archetype_key, option.role_key]:
									suite.assert_true(tr(key) != key, "authentic option text has a complete locale mapping: " + key)
					if capture:
						await _frames(2)
						await RenderingServer.frame_post_draw
						var pixels := viewport.get_texture().get_image()
						suite.assert_true(pixels != null and not pixels.is_empty(), "choice produces native raster output")
						if pixels != null and not pixels.is_empty():
							var output := "res://build/ui-finish-choice-screenshots/%s-%s-%s-%dx%d.png" % [kind, locale, scale, resolution.x, resolution.y]
							DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
							suite.assert_equal(pixels.save_png(output), OK, "choice screenshot retained")
					panel.call("close_panel")
				panel.queue_free()
				await _frames(1)
				viewport.queue_free()
				await _frames(1)
			accessibility.queue_free()
			await _frames(1)
	suite.finish(get_tree())


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame


func _run_snapshot(kind: String) -> Dictionary:
	return {
		"run_id": "ui-choice-finish-" + kind,
		"revision": 7,
		"run_seed": 20261006,
		"current_room": 1,
		"config": {"milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"]},
		"build": {"items": [], "blessings": [], "curses": [], "talents": [], "dominant_archetype": "freeze_burst"},
	}
