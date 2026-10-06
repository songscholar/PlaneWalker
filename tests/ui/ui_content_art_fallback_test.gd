extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")


func _ready() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	suite.assert_true(not registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH").has_blocking_errors(), "fallback checks authenticated canonical art alongside shipping content")
	var unknown := Art.icon(&"controls", &"content") as AtlasTexture
	suite.assert_true(unknown != null, "missing-art fallback is a committed authenticated glyph")
	for category: String in ["item", "blessing", "curse", "talent"]:
		var definition: Dictionary = registry.get_by_category(StringName(category), &"LAUNCH")[0]
		var canonical := Art.content(str(definition.id), category)
		suite.assert_true(canonical != null and canonical != unknown, "known content preserves its exact authored icon")
	for category: String in ["item", ""]:
		var fallback := Art.content("local_mod_clockwork_shell", category) as AtlasTexture
		suite.assert_true(fallback != null, "data-only Mod content uses a recognizable glyph instead of a blank image")
		if fallback != null:
			suite.assert_true(fallback.atlas == unknown.atlas and fallback.region == unknown.region, "missing content uses authenticated neutral package art")
			suite.assert_equal(fallback.get_meta("requested_content_id", ""), "local_mod_clockwork_shell", "fallback retains the original requested content identity")
			suite.assert_equal(fallback.get_meta("requested_category", "missing"), category, "fallback retains the requested category without changing canonical art metadata")
	suite.assert_true(not unknown.has_meta("requested_content_id"), "one Mod fallback cannot mutate the shared generic content glyph")
	suite.assert_equal(Art.content(""), null, "an unequipped content slot stays empty")
	suite.finish(get_tree())
