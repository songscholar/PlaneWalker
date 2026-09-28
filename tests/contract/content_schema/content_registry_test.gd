extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_project_manifest(suite)
	_test_fixture_manifest(suite)
	_test_file_and_root_errors(suite)
	_test_manifest_validation(suite)
	_test_m1_source_failures_are_blocking(suite)
	_test_m1_declarations_are_complete(suite)
	_test_override_validation(suite)
	_test_duplicate_ids(suite)
	_test_required_fields(suite)
	_test_next_content_isolation(suite)
	suite.finish(get_tree())


func _test_project_manifest(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_manifest("res://data/content_manifest.json")
	suite.assert_true(not report.has_blocking_errors(), "project manifest loads M1 content")
	suite.assert_true(report.loaded_count > 0, "project manifest reports loaded definitions")

	var frozen_burst: Dictionary = registry.get_content(&"frozen_burst")
	suite.assert_equal(frozen_burst["name_key"], "FROZEN_BURST_NAME", "legacy name normalizes")
	suite.assert_equal(frozen_burst["description_key"], "FROZEN_BURST_DESC", "legacy description normalizes")
	suite.assert_true(frozen_burst["availability"].has("M1"), "M1 item is enabled")

	suite.assert_true(registry.get_content(&"piercing_draw")["availability"].has("NEXT"), "bow content is preserved as next")
	suite.assert_true(registry.get_content(&"rift_snare")["availability"].has("NEXT"), "rift content is preserved as next")
	var m1_items: Array[Dictionary] = registry.get_by_category(&"item", &"M1")
	suite.assert_true(m1_items.all(func(entry): return not str(entry["id"]).contains("piercing")), "M1 item query excludes bow route")
	var m1_talents: Array[Dictionary] = registry.get_by_category(&"talent", &"M1")
	suite.assert_equal(m1_talents.size(), 3, "real M1 talent pool supports three choices")
	suite.assert_true(m1_talents.all(func(entry): return str(entry["archetype"]) != "rift_control"), "M1 talent pool excludes rift route")
	suite.assert_equal(registry.get_content(&"tal_eternity_reserve")["role"], "utility", "manifest override makes eternity reserve generic")

	var copied: Dictionary = registry.get_content(&"frozen_burst")
	copied["effects"]["time_stop_duration_bonus"] = 999.0
	suite.assert_close(
		float(registry.get_content(&"frozen_burst")["effects"]["time_stop_duration_bonus"]),
		0.75,
		"content getter returns deep copies"
	)

	var all_content: Array[Dictionary] = registry.all_content()
	var ids: Dictionary = {}
	for entry: Dictionary in all_content:
		ids[str(entry["id"])] = true
	suite.assert_equal(ids.size(), all_content.size(), "project registry ids are globally unique")


func _test_fixture_manifest(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_manifest("res://tests/fixtures/content/test_manifest.json")
	suite.assert_true(not report.has_blocking_errors(), "fixture manifest loads")
	suite.assert_equal(report.loaded_count, 2, "fixture manifest counts loaded definitions")
	suite.assert_true(registry.get_content(&"fixture_starter")["availability"].has("M1"), "fixture M1 id is enabled")
	suite.assert_true(registry.get_content(&"fixture_utility")["availability"].has("NEXT"), "fixture default remains next")


func _test_file_and_root_errors(suite) -> void:
	var missing_registry = ContentRegistryScript.new()
	var missing_report = missing_registry.load_entries(
		"res://tests/fixtures/content/does_not_exist.json",
		&"item",
		&"M1",
		[]
	)
	suite.assert_true(missing_report.has_blocking_errors(), "missing M1 source is blocking")

	var malformed_registry = ContentRegistryScript.new()
	var malformed_report = malformed_registry.load_entries(
		"res://tests/fixtures/content/test_manifest.json",
		&"item",
		&"M1",
		[]
	)
	suite.assert_true(malformed_report.has_blocking_errors(), "non-array source root is blocking")


func _test_manifest_validation(suite) -> void:
	var schema_registry = ContentRegistryScript.new()
	var schema_report = schema_registry.load_manifest(
		"res://tests/fixtures/content/invalid_manifest_schema.json"
	)
	suite.assert_true(schema_report.has_blocking_errors(), "fractional manifest schema is rejected")

	var source_registry = ContentRegistryScript.new()
	var source_report = source_registry.load_manifest(
		"res://tests/fixtures/content/invalid_manifest_source.json"
	)
	suite.assert_true(source_report.has_blocking_errors(), "manifest source fields require strict types")
	suite.assert_true(source_registry.all_content().is_empty(), "invalid manifest source is not loaded")

	var category_registry = ContentRegistryScript.new()
	var category_report = category_registry.load_entries(
		"res://tests/fixtures/content/valid_items.json",
		&"itme",
		&"NEXT",
		["fixture_starter"]
	)
	suite.assert_true(category_report.has_blocking_errors(), "unknown content category is rejected")
	suite.assert_true(category_registry.all_content().is_empty(), "misspelled category is not indexed")


func _test_m1_source_failures_are_blocking(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/does_not_exist.json",
		&"item",
		&"NEXT",
		["required_m1_entry"]
	)
	suite.assert_true(report.has_blocking_errors(), "missing NEXT source with declared M1 ids is blocking")


func _test_m1_declarations_are_complete(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/valid_items.json",
		&"item",
		&"NEXT",
		["fixture_starter", "ghost_m1_entry"]
	)
	suite.assert_true(report.has_blocking_errors(), "missing manifest M1 id blocks startup")
	suite.assert_true(registry.get_content(&"ghost_m1_entry").is_empty(), "missing M1 id is not synthesized")


func _test_override_validation(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/valid_items.json",
		&"item",
		&"NEXT",
		["fixture_starter"],
		null,
		{"fixture_starter": {"role": false}}
	)
	suite.assert_true(report.has_blocking_errors(), "non-string milestone override is rejected")
	suite.assert_equal(
		registry.get_content(&"fixture_starter").get("role", ""),
		"starter",
		"invalid override does not coerce garbage into content"
	)


func _test_duplicate_ids(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/duplicate_ids.json",
		&"item",
		&"M1",
		[]
	)
	suite.assert_true(report.has_blocking_errors(), "duplicate M1 ids are blocking")
	suite.assert_equal(registry.all_content().size(), 1, "duplicate definition is omitted")


func _test_required_fields(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/missing_required_field.json",
		&"item",
		&"M1",
		[]
	)
	suite.assert_true(report.has_blocking_errors(), "missing M1 fields are blocking")
	suite.assert_equal(report.blocking_errors.size(), 4, "all required field failures are reported")
	suite.assert_true(registry.all_content().is_empty(), "invalid M1 definitions are omitted")


func _test_next_content_isolation(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_entries(
		"res://tests/fixtures/content/missing_required_field.json",
		&"item",
		&"NEXT",
		[]
	)
	suite.assert_true(not report.has_blocking_errors(), "invalid next content does not block M1")
	suite.assert_equal(report.isolated_errors.size(), 4, "invalid next content is isolated")
	suite.assert_true(registry.all_content().is_empty(), "isolated next definitions are not indexed")
