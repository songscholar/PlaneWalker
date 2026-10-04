extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_profile_fixtures.gd")
const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")


func _ready() -> void:
	var suite = Suite.new()
	var catalog = Catalog.new()
	var entries := Fixtures.meta_entries()
	suite.assert_true(catalog.configure(entries).ok, "all 42 reconciled nodes configure")
	suite.assert_equal(catalog.ids().size(), 42, "exact legacy Meta IDs retained")
	var before: Array = catalog.snapshot()
	var shards := 0
	var imprints := 0
	for definition: Dictionary in before:
		shards += int(definition.cost.chronos_shards)
		imprints += int(definition.cost.existential_imprints)
	suite.assert_equal(shards, 661, "complete authored tree costs 661 shards")
	suite.assert_equal(imprints, 5, "L-10 has the five-imprint secondary cost")
	entries[0].cost.chronos_shards = 999
	suite.assert_equal(catalog.definition(&"W-01").cost.chronos_shards, 5, "catalog cannot alias caller content")
	var copy: Dictionary = catalog.definition(&"W-01")
	copy.effects.clear()
	suite.assert_equal(catalog.snapshot(), before, "catalog projections are defensive copies")
	suite.assert_true(catalog.definition(&"P-04").prerequisites.has("L-09"), "P-04 references the actual merchant branch")
	for mutation: String in ["missing", "cycle", "unknown", "budget", "fraction", "duplicate", "extra", "discount_fraction", "retention_approx"]:
		var bad := Fixtures.meta_entries()
		match mutation:
			"missing": bad.pop_back()
			"cycle": bad[0].prerequisites = ["W-02"]
			"unknown": bad[39].prerequisites = ["F-09"]
			"budget": bad[0].effects[0].magnitude = 0.06
			"fraction": bad[0].cost.chronos_shards = 0.5
			"duplicate": bad[0].prerequisites = ["W-02", "W-02"]
			"extra": bad[0].unreviewed_buff = true
			"discount_fraction": bad[26].effects[0].value = 0.015
			"retention_approx": bad[6].effects[0].value = 0.500001
		suite.assert_true(not catalog.configure(bad).ok, "malformed %s catalog refuses" % mutation)
		suite.assert_equal(catalog.snapshot(), before, "malformed content never replaces a valid catalog")
	var json_entries: Array = JSON.parse_string(JSON.stringify(before))
	var restored = Catalog.new()
	suite.assert_true(restored.configure(json_entries).ok, "physical JSON numeric types remain readable")
	suite.assert_equal(restored.fingerprint(), catalog.fingerprint(), "canonical content identity survives JSON")
	suite.finish(get_tree())
