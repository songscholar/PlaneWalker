extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const SOURCE := "res://scripts/progression/cosmetic_catalog.gd"


func _ready() -> void:
	var suite := Suite.new()
	if not ResourceLoader.exists(SOURCE):
		suite.assert_true(false, "free cosmetic catalog exposes actual authored unlock routes and raster identity")
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "actual Base pack validates cosmetic definitions and asset provenance")
	var catalog: RefCounted = load(SOURCE).new()
	suite.assert_true(catalog.configure(registry.get_catalog_entries(&"cosmetic_definition", &"LAUNCH")).ok, "actual cosmetic catalog configures")
	var state := Profile.new()
	state.configure(Factory.load_base().context.catalog)
	var profile: Dictionary = state.snapshot()
	suite.assert_equal(catalog.ids().size(), 15, "five launch characters each have three free appearances")
	for character: String in ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]:
		suite.assert_equal(catalog.for_character(character).size(), 3, "character appearance collection is complete")
	var initial: Dictionary = catalog.empty_collection()
	suite.assert_true(catalog.validate_collection(initial, profile), "old missing collection defaults are valid")
	suite.assert_equal(catalog.unlock_status("wanderer.default", profile).code, &"OK", "owned character original appearance is free")
	suite.assert_equal(catalog.unlock_status("wanderer.return", profile).code, &"COSMETIC_RETURN_REQUIRED", "first-return route cannot be caller fabricated")
	suite.assert_equal(catalog.unlock_status("time_lord.default", profile).code, &"COSMETIC_CHARACTER_LOCKED", "locked character appearance refuses")
	profile.statistics.finished_runs = 1
	profile.statistics.deaths = 1
	suite.assert_true(catalog.unlock_status("wanderer.return", profile).ok, "durable first return unlocks memorial appearance")
	suite.assert_true(not catalog.unlock_status("wanderer.victory", profile).ok, "death cannot unlock victory appearance")
	var forged := initial.duplicate(true)
	forged.claimed_ids = ["wanderer.victory"]
	suite.assert_true(not catalog.validate_collection(forged, profile), "physical collection refuses locked claims")
	forged = initial.duplicate(true)
	forged.equipped_by_character.wanderer = "time_lord.default"
	suite.assert_true(not catalog.validate_collection(forged, profile), "equipment cannot borrow another character appearance")
	var rows: Array = registry.get_catalog_entries(&"cosmetic_definition", &"LAUNCH")
	rows[0].effects = {"attack": 1}
	suite.assert_true(not load(SOURCE).new().configure(rows).ok, "cosmetic definitions cannot grant combat effects")
	suite.finish(get_tree())
