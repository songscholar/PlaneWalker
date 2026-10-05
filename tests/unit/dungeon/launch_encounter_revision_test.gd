extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Catalog := preload("res://scripts/dungeon/launch_encounter_catalog.gd")
const Config := preload("res://scripts/application/run_config.gd")
const Fixtures := preload("res://tests/support/p15_catalog_fixtures.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var path := "res://data/content_packs/base/content/launch_encounters.json"
	suite.assert_equal(FileAccess.get_file_as_string(path).sha256_text(), "7a6399afe43c21a8e221dfd9c8fd1daafb2a7c7a559b3da0b6c60281cea53e40", "historical forty-recipe authority remains byte-identical")
	var catalog := Catalog.new()
	suite.assert_true(catalog.configure_authored().ok, "revision catalog configures actual authored content")
	suite.assert_true(catalog.has_method("resolve_for_revision"), "explicit persisted revision can select additive elite content")
	suite.assert_true(FileAccess.file_exists("res://data/content_packs/base/content/launch_encounter_extensions.json"), "natural elite Wraith and Spore require a separate authored additive catalog")
	var current := Config.normalized({"milestone": "LAUNCH", "launch_encounter_revision": 2})
	suite.assert_equal(current.get("launch_encounter_revision", 0), 2, "Run config preserves explicit authored encounter revision")
	suite.assert_true(not Config.normalized({"milestone": "LAUNCH"}).has("launch_encounter_revision"), "historical missing revision remains absent rather than inventing current content")
	for invalid: Variant in [0, 3, true, 2.0, "2"]:
		suite.assert_true(not Config.validate({"milestone": "LAUNCH", "launch_encounter_revision": invalid}).ok, "unsupported or untyped encounter revision refuses")
	if not catalog.has_method("resolve_for_revision"):
		suite.finish(get_tree())
		return
	for floor_index: int in range(5):
		for seed: int in range(128):
			for room_type: String in ["combat", "elite"]:
				var old: Dictionary = catalog.resolve_for_node(Ids.PROFILE_IDS[floor_index], seed, "layer_04_a", room_type)
				var restored: Dictionary = catalog.call("resolve_for_revision", Ids.PROFILE_IDS[floor_index], seed, "layer_04_a", room_type, "", 1)
				suite.assert_equal(restored, old, "revision 1 preserves every historical seed and room definition")
				if floor_index > 1 or room_type == "combat":
					suite.assert_equal(catalog.call("resolve_for_revision", Ids.PROFILE_IDS[floor_index], seed, "layer_04_a", room_type, "", 2), old, "revision 2 preserves every unaffected floor and ordinary recipe stream")
	for floor_index: int in range(2):
		var found := false
		var species := "ruins_wraith" if floor_index == 0 else "void_spore"
		for seed: int in range(128):
			for template_id: String in ["room_elite_arena", "room_elite_trap_arena", "room_elite_guard_corridor", "room_elite_twin_hall", "room_elite_altar_defense"]:
				var recipe: Dictionary = catalog.call("resolve_for_revision", Ids.PROFILE_IDS[floor_index], seed, "layer_04_a", "elite", template_id, 2)
				if recipe.is_empty():
					continue
				for wave: Dictionary in recipe.waves:
					for spawn: Dictionary in wave.spawns:
						found = found or spawn.elite and spawn.enemy_id == species
					suite.assert_equal(catalog.encounter_definition(recipe.id), recipe, "additive selected recipe resolves to its exact durable authored definition")
		suite.assert_true(found, "ordinary seeded native selection naturally reaches elite " + species)
	suite.assert_equal(catalog.call("resolve_for_revision", Ids.PROFILE_IDS[0], 1, "layer_04_a", "elite", "", 3), {}, "unknown selection revision refuses")
	var historical_registry := Fixtures.registry()
	historical_registry.rows.erase("launch_encounter_extension")
	suite.assert_true(catalog.configure(historical_registry).ok, "original complete catalog remains executable without additive content")
	suite.assert_equal(catalog.snapshot().recipe_count, 40, "historical content exposes exactly the original forty recipes")
	suite.assert_equal(catalog.call("resolve_for_revision", Ids.PROFILE_IDS[0], 1, "layer_04_a", "elite", "", 2), {}, "revision 2 cannot silently fall back when its authored extension is absent")
	suite.finish(get_tree())
