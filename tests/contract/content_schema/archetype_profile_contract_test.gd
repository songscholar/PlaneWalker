extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ArchetypeProfileScript := preload("res://scripts/progression/archetype_profile.gd")

const SCHEMA_PATH := "res://data/schemas/archetype_profile_v1.schema.json"
const CATALOG_PATH := "res://data/content_packs/base/content/archetype_profiles.json"
const EXPECTED_BOSS_CONVERSIONS := {
	"freeze_burst": "boss_weakpoint_exposure",
	"rewind_echo": "boss_rewind_path_strike",
	"rift_trap": "boss_projectile_window",
	"accelerated_combo": "boss_combo_break",
	"low_hp_void": "boss_execute_warning",
	"perfect_guard": "boss_counter_window",
	"piercing_barrage": "boss_weakpoint_ammo_refund",
	"echo_legion": "boss_facing_lure",
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_schema(suite)
	var definitions := _catalog(suite)
	if definitions.size() == 8:
		_test_catalog(suite, definitions)
		_test_parser_fail_closed(suite, definitions)
		_test_snapshot_isolation(suite, definitions)
	suite.finish(get_tree())


func _test_schema(suite) -> void:
	var schema_value: Variant = _read_json(SCHEMA_PATH, suite)
	if not schema_value is Dictionary:
		return
	var schema: Dictionary = schema_value
	suite.assert_equal(
		schema.get("$id"),
		"planewalker://schemas/archetype-profile/1.0.0",
		"archetype profile schema id is stable"
	)
	suite.assert_equal(schema.get("additionalProperties"), false, "archetype profile root is closed")
	for field: String in ArchetypeProfileScript.REQUIRED_FIELDS:
		suite.assert_true(schema.get("required", []).has(field), "schema requires %s" % field)
	var properties: Dictionary = schema.get("properties", {})
	suite.assert_equal(
		properties.get("category", {}).get("const"),
		"archetype_profile",
		"archetype category is closed"
	)
	suite.assert_equal(properties.get("effects", {}).get("maxProperties"), 0, "profiles cannot execute effects")
	suite.assert_equal(properties.get("starter_min", {}).get("const"), 3, "starter coverage is exact")
	suite.assert_equal(properties.get("payoff_min", {}).get("const"), 2, "payoff coverage is exact")
	suite.assert_equal(properties.get("risk_min", {}).get("const"), 1, "risk coverage is exact")


func _test_catalog(suite, definitions: Array[Dictionary]) -> void:
	var ids: Array[String] = []
	for definition: Dictionary in definitions:
		var parser = ArchetypeProfileScript.new()
		var result: Dictionary = parser.configure(definition)
		suite.assert_true(
			bool(result.get("ok", false)),
			"%s parses: %s" % [str(definition.get("archetype_id", "")), str(result.get("context", {}))]
		)
		if not bool(result.get("ok", false)):
			continue
		var snapshot := parser.snapshot()
		var archetype_id := str(snapshot.get("archetype_id", ""))
		ids.append(archetype_id)
		suite.assert_equal(snapshot.get("profile_version"), 1, "profile version is exact")
		suite.assert_equal(snapshot.get("availability"), ["LAUNCH", "EXPANSION"], "availability is closed")
		suite.assert_equal(snapshot.get("starter_min"), 3, "starter minimum is exact")
		suite.assert_equal(snapshot.get("payoff_min"), 2, "payoff minimum is exact")
		suite.assert_equal(snapshot.get("risk_min"), 1, "risk minimum is exact")
		suite.assert_equal(
			snapshot.get("boss_conversion_id"),
			EXPECTED_BOSS_CONVERSIONS[archetype_id],
			"Boss response conversion is exact"
		)
		suite.assert_true((snapshot.get("mechanic_tags", []) as Array).size() >= 4, "mechanic tags are useful")
	suite.assert_equal(ids, ArchetypeProfileScript.ARCHETYPE_IDS, "exact ordered eight-archetype taxonomy exists")


func _test_parser_fail_closed(suite, definitions: Array[Dictionary]) -> void:
	var cases: Array[Dictionary] = [
		_case("unknown id", func(value): value["archetype_id"] = "heavy_cleave"),
		_case("wrong version", func(value): value["profile_version"] = 2),
		_case("M1 widening", func(value): value["availability"] = ["M1"]),
		_case("missing starter", func(value): value.erase("starter_min")),
		_case("wrong payoff", func(value): value["payoff_min"] = 1),
		_case("duplicate tag", func(value): value["mechanic_tags"].append(value["mechanic_tags"][0])),
		_case("wrong conversion", func(value): value["boss_conversion_id"] = "boss_hard_freeze"),
		_case("hidden effect", func(value): value["effects"] = {"attack_multiplier": 2.0}),
		_case("unknown root", func(value): value["script_path"] = "res://hostile.gd"),
	]
	for invalid_case: Dictionary in cases:
		var value: Dictionary = definitions[0].duplicate(true)
		var mutate: Callable = invalid_case["mutate"]
		mutate.call(value)
		var result: Dictionary = ArchetypeProfileScript.new().configure(value)
		suite.assert_true(not bool(result.get("ok", false)), "%s fails closed" % invalid_case["label"])


func _test_snapshot_isolation(suite, definitions: Array[Dictionary]) -> void:
	var parser = ArchetypeProfileScript.new()
	var source: Dictionary = definitions[0].duplicate(true)
	suite.assert_true(bool(parser.configure(source).get("ok", false)), "isolation fixture configures")
	var first := parser.snapshot()
	(first["mechanic_tags"] as Array).append("forged")
	first["boss_conversion_id"] = "forged"
	source["mechanic_tags"].clear()
	var second := parser.snapshot()
	suite.assert_true(not (second["mechanic_tags"] as Array).has("forged"), "snapshot tags are isolated")
	suite.assert_equal(second["boss_conversion_id"], "boss_weakpoint_exposure", "snapshot scalar is isolated")
	suite.assert_true(not (second["mechanic_tags"] as Array).is_empty(), "source mutation cannot change parser state")


func _case(label: String, mutate: Callable) -> Dictionary:
	return {"label": label, "mutate": mutate}


func _catalog(suite) -> Array[Dictionary]:
	var value: Variant = _read_json(CATALOG_PATH, suite)
	if not value is Array:
		return []
	var result: Array[Dictionary] = []
	for row: Variant in value:
		if row is Dictionary:
			result.append((row as Dictionary).duplicate(true))
	return result


func _read_json(path: String, suite) -> Variant:
	suite.assert_true(FileAccess.file_exists(path), "%s exists" % path)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "%s can be opened" % path)
	if file == null:
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	suite.assert_equal(error, OK, "%s contains valid JSON" % path)
	return parser.data if error == OK else {}
