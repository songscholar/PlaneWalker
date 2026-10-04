extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const FixturesScript := preload("res://tests/ui/p14_panel_fixtures.gd")
const SCENES := {
	"map": "res://scenes/ui/dungeon_map_panel.tscn",
	"route": "res://scenes/ui/route_choice_panel.tscn",
	"merchant": "res://scenes/ui/merchant_panel.tscn",
	"event": "res://scenes/ui/dungeon_event_panel.tscn",
	"room": "res://scenes/ui/room_interaction_panel.tscn",
	"transition": "res://scenes/ui/floor_transition_panel.tscn",
}
const RESOLUTIONS: Array[Vector2i] = [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]

var _suite: RefCounted
var _fixture_translations: Array[Translation] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	for locale: String in ["zh", "en"]:
		var translation := Translation.new()
		translation.locale = locale
		translation.add_message("P14_TEST_LONG_TEXT", "A long narrative description that must wrap and remain fully readable when the current run presents detailed effects, a costly trade, conditional weapon compatibility, and a demanding consequence.")
		TranslationServer.add_translation(translation)
		_fixture_translations.append(translation)
	var original_locale := TranslationServer.get_locale()
	var screenshots := OS.get_cmdline_user_args().has("--panel-screenshots")
	for locale: String in ["zh", "en"]:
		TranslationServer.set_locale(locale)
		for resolution: Vector2i in RESOLUTIONS:
			for kind: String in SCENES:
				var viewport := SubViewport.new()
				viewport.size = resolution
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(viewport)
				var packed := load(SCENES[kind]) as PackedScene
				var panel := packed.instantiate() as Control
				viewport.add_child(panel)
				await get_tree().process_frame
				var state := FixturesScript.for_kind(kind)
				if kind == "merchant":
					state["offers"][0]["description_key"] = "P14_TEST_LONG_TEXT"
				if kind == "event":
					state["description_key"] = "P14_TEST_LONG_TEXT"
				var rendered: RefCounted = panel.call("render", state)
				_suite.assert_true(rendered.ok, "%s validates at %s/%s: %s" % [kind, locale, resolution, str(rendered.context)])
				if not rendered.ok:
					viewport.queue_free()
					await get_tree().process_frame
					continue
				await get_tree().process_frame
				await get_tree().process_frame
				var panel_root: Control = panel.get("panel_root")
				var rectangle := panel_root.get_global_rect()
				_suite.assert_true(rectangle.position.x >= 15.9 and rectangle.position.y >= 15.9, "panel preserves the upper safe area")
				_suite.assert_true(rectangle.end.x <= resolution.x - 15.9 and rectangle.end.y <= resolution.y - 15.9, "panel fits its supported resolution")
				var scroll: ScrollContainer = panel.get("scroll")
				_suite.assert_true(scroll.size.x > 0 and scroll.size.y > 0, "scroll retains usable content space")
				for label: Node in panel.find_children("*", "Label", true, false):
					_suite.assert_true((label as Label).size.x <= panel_root.size.x, "wrapped content cannot widen the panel")
				if screenshots:
					await RenderingServer.frame_post_draw
					var image := viewport.get_texture().get_image()
					_suite.assert_true(image != null and not image.is_empty(), "rendered panel pixels are available")
					if image != null and not image.is_empty():
						var output := "res://build/p14-ui-screenshots/%s-%s-%dx%d.png" % [kind, locale, resolution.x, resolution.y]
						DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
						_suite.assert_equal(image.save_png(output), OK, "panel screenshot is retained")
				panel.call("close_panel")
				viewport.queue_free()
				await get_tree().process_frame
				await get_tree().process_frame
	TranslationServer.set_locale(original_locale)
	for translation: Translation in _fixture_translations:
		TranslationServer.remove_translation(translation)
	_fixture_translations.clear()
	_suite.finish(get_tree())
