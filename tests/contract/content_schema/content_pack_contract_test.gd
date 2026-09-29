extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const CONTRACT_PATH := "res://docs/contracts/content-pack-v2.md"
const PACK_SCHEMA_PATH := "res://data/schemas/content_pack_v2.schema.json"
const ENTRY_SCHEMA_PATH := "res://data/schemas/content_entry_v2.schema.json"
const VALID_PACK_PATH := "res://tests/fixtures/content_packs/valid_base/pack.json"
const VALID_ENTRY_PATH := "res://tests/fixtures/content_packs/valid_base/content/items.json"
const HOSTILE_PACK_PATH := "res://tests/fixtures/content_packs/invalid_script/pack.json"
const HOSTILE_ENTRY_PATH := "res://tests/fixtures/content_packs/invalid_script/content/items.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_contract_document(suite)
	_test_pack_schema(suite)
	_test_entry_schema(suite)
	_test_pack_fixtures(suite)
	suite.finish(get_tree())


func _test_contract_document(suite) -> void:
	var text := _read_text(CONTRACT_PATH, suite)
	if text.is_empty():
		return
	for required_term: String in [
		"dependency cycle",
		"integrity hash",
		"optional pack isolation",
		"arbitrary script",
		"localization source",
		"asset manifest",
		"entitlement tag",
		"deterministic activation",
	]:
		suite.assert_true(
			text.to_lower().contains(required_term),
			"content pack contract defines %s" % required_term
		)


func _test_pack_schema(suite) -> void:
	var schema: Dictionary = _read_json(PACK_SCHEMA_PATH, suite)
	if schema.is_empty():
		return
	suite.assert_equal(schema.get("$id"), "planewalker://schemas/content-pack/2.0.0", "pack schema id is stable")
	suite.assert_equal(schema.get("additionalProperties"), false, "pack envelope rejects unknown fields")
	_assert_required_fields(
		suite,
		schema,
		[
			"pack_id", "pack_version", "schema_version", "game_version_range",
			"dependencies", "load_order", "content_manifest", "localization_sources",
			"asset_manifest", "integrity_hashes", "entitlement_tag",
		],
		"pack schema"
	)
	var properties: Dictionary = schema.get("properties", {})
	suite.assert_equal(properties.get("pack_id", {}).get("pattern"), "^[a-z0-9][a-z0-9_.-]{0,63}$", "pack id blocks unsafe paths")
	suite.assert_equal(properties.get("schema_version", {}).get("const"), 2, "pack schema version is explicit")
	suite.assert_equal(properties.get("dependencies", {}).get("type"), "array", "pack dependencies are ordered records")
	suite.assert_equal(properties.get("integrity_hashes", {}).get("additionalProperties", {}).get("pattern"), "^[a-f0-9]{64}$", "integrity digests are sha256 hex")


func _test_entry_schema(suite) -> void:
	var schema: Dictionary = _read_json(ENTRY_SCHEMA_PATH, suite)
	if schema.is_empty():
		return
	suite.assert_equal(schema.get("$id"), "planewalker://schemas/content-entry/2.0.0", "entry schema id is stable")
	suite.assert_equal(schema.get("additionalProperties"), false, "entry rejects executable or unknown fields")
	_assert_required_fields(
		suite,
		schema,
		[
			"id", "category", "availability", "name_key", "description_key",
			"tags", "compatibility", "effects",
		],
		"entry schema"
	)
	var properties: Dictionary = schema.get("properties", {})
	suite.assert_equal(properties.get("id", {}).get("pattern"), "^[a-z0-9][a-z0-9_.-]{0,63}$", "entry id blocks unsafe paths")
	suite.assert_equal(properties.get("effects", {}).get("additionalProperties", {}).get("type"), ["number", "integer", "boolean", "string"], "effects contain JSON scalar values only")
	suite.assert_true(not properties.has("script_path"), "entry schema exposes no script path")
	suite.assert_true(not properties.has("script"), "entry schema exposes no executable script field")


func _test_pack_fixtures(suite) -> void:
	var valid_pack: Dictionary = _read_json(VALID_PACK_PATH, suite)
	var valid_entries_value: Variant = _read_json(VALID_ENTRY_PATH, suite)
	var hostile_pack: Dictionary = _read_json(HOSTILE_PACK_PATH, suite)
	var hostile_entries_value: Variant = _read_json(HOSTILE_ENTRY_PATH, suite)
	var valid_entries: Array = valid_entries_value if valid_entries_value is Array else []
	var hostile_entries: Array = hostile_entries_value if hostile_entries_value is Array else []
	if valid_pack.is_empty() or valid_entries.is_empty() or hostile_pack.is_empty() or hostile_entries.is_empty():
		return
	suite.assert_equal(valid_pack.get("pack_id"), "fixture_base", "valid fixture has a stable pack id")
	suite.assert_equal(valid_pack.get("schema_version"), 2, "valid fixture uses schema v2")
	suite.assert_equal(valid_entries[0].get("id"), "fixture_chronal_edge", "valid fixture has deterministic content")
	suite.assert_equal(hostile_pack.get("pack_id"), "fixture_invalid_script", "hostile fixture remains identifiable")
	suite.assert_true(hostile_entries[0].has("script_path"), "hostile fixture exercises arbitrary script rejection")


func _assert_required_fields(suite, schema: Dictionary, expected: Array, label: String) -> void:
	var required: Array = schema.get("required", [])
	for field: Variant in expected:
		suite.assert_true(required.has(field), "%s requires %s" % [label, str(field)])


func _read_json(path: String, suite) -> Variant:
	var text := _read_text(path, suite)
	if text.is_empty():
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	suite.assert_equal(parse_error, OK, "%s contains valid JSON" % path)
	if parse_error != OK:
		return {}
	return parser.data


func _read_text(path: String, suite) -> String:
	suite.assert_true(FileAccess.file_exists(path), "%s exists" % path)
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "%s can be opened" % path)
	if file == null:
		return ""
	return file.get_as_text()
