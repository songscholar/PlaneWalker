extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const EffectHandlerCatalogScript := preload("res://scripts/content/effects/effect_handler_catalog.gd")

const SOURCE_PATHS: Array[String] = [
	"res://data/items/mvp_items.json",
	"res://data/blessings/mvp_blessings.json",
	"res://data/curses/mvp_curses.json",
	"res://data/talents/mvp_talents.json",
]
const SOURCE_CATEGORIES := {
	"res://data/items/mvp_items.json": "item",
	"res://data/blessings/mvp_blessings.json": "blessing",
	"res://data/curses/mvp_curses.json": "curse",
	"res://data/talents/mvp_talents.json": "talent",
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var catalog = EffectHandlerCatalogScript.new()
	_test_catalog_covers_current_effects(suite, catalog)
	_test_known_effects_and_context(suite, catalog)
	_test_script_like_and_unknown_ids(suite, catalog)
	_test_scalar_types_and_numeric_bounds(suite, catalog)
	_test_deterministic_normalization(suite, catalog)
	_test_snapshot_isolation(suite, catalog)
	_test_missing_catalog_fails_closed(suite)
	suite.finish(get_tree())


func _test_catalog_covers_current_effects(suite, catalog) -> void:
	var load_report = catalog.load_report()
	suite.assert_true(not load_report.has_blocking_errors(), "tracked effect catalog loads")
	var expected_ids := _current_effect_ids(suite)
	var snapshot: Array[Dictionary] = catalog.snapshot()
	var actual_ids: Array[String] = []
	var required_fields: Array[String] = [
		"effect_id",
		"value_type",
		"minimum",
		"maximum",
		"stack_rule",
		"allowed_categories",
	]
	for row: Dictionary in snapshot:
		actual_ids.append(str(row.get("effect_id", "")))
		for field: String in required_fields:
			suite.assert_true(row.has(field), "catalog row %s contains %s" % [row.get("effect_id", ""), field])
	suite.assert_equal(actual_ids, expected_ids, "catalog covers exactly the current M1 effect ids")
	suite.assert_equal(actual_ids.size(), 40, "current M1 content exposes forty effect ids")
	for path: String in SOURCE_PATHS:
		var entries := _read_content_entries(path, suite)
		for entry: Dictionary in entries:
			var effects: Dictionary = entry.get("effects", {})
			var report = catalog.validate_effects(effects, {"category": SOURCE_CATEGORIES[path]})
			suite.assert_true(
				not report.has_blocking_errors(),
				"current content %s in %s validates" % [entry.get("id", ""), SOURCE_CATEGORIES[path]]
			)
			if not effects.is_empty():
				suite.assert_true(
					not catalog.normalize_effects(effects).is_empty(),
					"current content %s normalizes" % entry.get("id", "")
				)


func _test_known_effects_and_context(suite, catalog) -> void:
	var item_report = catalog.validate_effects(
		{"heal": 20.0, "attack_multiplier": 1.18},
		{"category": "item"}
	)
	suite.assert_true(not item_report.has_blocking_errors(), "known item effects validate")

	var blessing_report = catalog.validate_effects(
		{"time_stop_weakpoint_damage_bonus": 0.35, "time_stop_weakpoint_duration": 3.0},
		{"category": "blessing"}
	)
	suite.assert_true(not blessing_report.has_blocking_errors(), "known blessing effects validate")

	var wrong_category = catalog.validate_effects({"bow_pierce_bonus": 1}, {"category": "curse"})
	suite.assert_true(wrong_category.has_blocking_errors(), "effect category compatibility fails closed")

	var missing_category = catalog.validate_effects({"heal": 20.0}, {})
	suite.assert_true(missing_category.has_blocking_errors(), "missing content category fails closed")


func _test_script_like_and_unknown_ids(suite, catalog) -> void:
	for effect_id: String in [
		"res://arbitrary.gd",
		"folder/effect",
		"folder\\effect",
		"../attack_multiplier",
		"arbitrary.gd",
		"unknown_effect",
	]:
		var report = catalog.validate_effects({effect_id: 1.0}, {"category": "item"})
		suite.assert_true(report.has_blocking_errors(), "unsafe or unknown effect id %s is rejected" % effect_id)

	var non_string_id = catalog.validate_effects({42: 1.0}, {"category": "item"})
	suite.assert_true(non_string_id.has_blocking_errors(), "non-string effect id is rejected")


func _test_scalar_types_and_numeric_bounds(suite, catalog) -> void:
	suite.assert_true(
		catalog.validate_effects({"rewind_echo_enabled": true}, {"category": "item"}).blocking_errors.is_empty(),
		"boolean effect accepts bool"
	)
	suite.assert_true(
		catalog.validate_effects({"rewind_echo_enabled": 1}, {"category": "item"}).has_blocking_errors(),
		"boolean effect rejects number"
	)
	suite.assert_true(
		catalog.validate_effects({"attack_multiplier": "1.18"}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects string"
	)
	suite.assert_true(
		catalog.validate_effects({"attack_multiplier": {}}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects dictionaries"
	)
	suite.assert_true(
		catalog.validate_effects({"bow_pierce_bonus": 1.5}, {"category": "item"}).has_blocking_errors(),
		"integer effect rejects fractional values"
	)
	suite.assert_true(
		catalog.validate_effects({"bow_pierce_bonus": 2.0}, {"category": "item"}).blocking_errors.is_empty(),
		"integer effect accepts integral JSON numbers"
	)
	suite.assert_true(
		catalog.validate_effects({"attack_multiplier": NAN}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects NaN"
	)
	suite.assert_true(
		catalog.validate_effects({"attack_multiplier": INF}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects infinity"
	)
	suite.assert_true(
		catalog.validate_effects({"attack_multiplier": 5.01}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects values above its maximum"
	)
	suite.assert_true(
		catalog.validate_effects({"max_hp_bonus": -1.0}, {"category": "item"}).has_blocking_errors(),
		"number effect rejects values below its minimum"
	)
	suite.assert_true(
		catalog.validate_effects({"defense_bonus": -2.0}, {"category": "curse"}).blocking_errors.is_empty(),
		"signed defense bonus preserves the current curse"
	)


func _test_deterministic_normalization(suite, catalog) -> void:
	var source := {
		"rewind_echo_enabled": true,
		"bow_pierce_bonus": 2.0,
		"attack_multiplier": 1,
	}
	var normalized: Dictionary = catalog.normalize_effects(source)
	suite.assert_equal(
		normalized.keys(),
		["attack_multiplier", "bow_pierce_bonus", "rewind_echo_enabled"],
		"normalized effect ids are sorted"
	)
	suite.assert_true(typeof(normalized["attack_multiplier"]) == TYPE_FLOAT, "number effects normalize to float")
	suite.assert_true(typeof(normalized["bow_pierce_bonus"]) == TYPE_INT, "integer effects normalize to int")
	suite.assert_true(typeof(normalized["rewind_echo_enabled"]) == TYPE_BOOL, "boolean effects remain bool")

	normalized["attack_multiplier"] = 4.0
	var repeated: Dictionary = catalog.normalize_effects(source)
	suite.assert_close(float(repeated["attack_multiplier"]), 1.0, "normalized dictionaries are isolated")
	suite.assert_true(catalog.normalize_effects({"unknown_effect": 1.0}).is_empty(), "invalid normalization fails closed")


func _test_snapshot_isolation(suite, catalog) -> void:
	var first: Array[Dictionary] = catalog.snapshot()
	var second: Array[Dictionary] = catalog.snapshot()
	suite.assert_true(not first.is_empty(), "catalog snapshot is populated")
	if first.is_empty() or second.is_empty():
		return
	first[0]["effect_id"] = "mutated"
	(first[1]["allowed_categories"] as Array).append("mutated")
	suite.assert_true(str(second[0]["effect_id"]) != "mutated", "snapshot rows are deep copied")
	suite.assert_true(not (second[1]["allowed_categories"] as Array).has("mutated"), "snapshot category arrays are isolated")
	suite.assert_equal(catalog.snapshot(), second, "snapshot mutation cannot change catalog authority")


func _test_missing_catalog_fails_closed(suite) -> void:
	var missing = EffectHandlerCatalogScript.new("res://tests/fixtures/content/does_not_exist_effect_catalog.json")
	suite.assert_true(missing.load_report().has_blocking_errors(), "missing catalog reports a blocking error")
	suite.assert_true(
		missing.validate_effects({"attack_multiplier": 1.0}, {"category": "item"}).has_blocking_errors(),
		"validation cannot proceed without a trusted catalog"
	)
	suite.assert_true(missing.normalize_effects({"attack_multiplier": 1.0}).is_empty(), "missing catalog normalization fails closed")


func _current_effect_ids(suite) -> Array[String]:
	var ids: Dictionary = {}
	for path: String in SOURCE_PATHS:
		for entry: Dictionary in _read_content_entries(path, suite):
			var effects: Dictionary = entry.get("effects", {})
			for effect_id_value: Variant in effects.keys():
				ids[str(effect_id_value)] = true
	var result: Array[String] = []
	for effect_id_value: Variant in ids.keys():
		result.append(str(effect_id_value))
	result.sort()
	return result


func _read_content_entries(path: String, suite) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "current content source %s opens" % path)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	suite.assert_true(parsed is Array, "current content source %s is an array" % path)
	if not parsed is Array:
		return []
	var entries: Array[Dictionary] = []
	for entry_value: Variant in parsed:
		if entry_value is Dictionary:
			entries.append((entry_value as Dictionary).duplicate(true))
	return entries
