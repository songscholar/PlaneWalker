extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/character_runtime_profiles.json"
const GAME_VERSION := "0.4.0-dev"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_valid_real_pack(suite)
	_test_frozen_v2_compatibility_forms(suite)
	var cases: Array[Dictionary] = [
		_case("empty_compatibility", func(definitions: Array): _profile(definitions)["compatibility"]["character_ids"] = []),
		_case("typo_compatibility", func(definitions: Array): _profile(definitions)["compatibility"]["character_ids"] = ["time_guardain"]),
		_case("unsupported_mode", func(definitions: Array): _profile(definitions)["compatibility"]["modes"] = ["normal"]),
		_case("compatibility_availability", func(definitions: Array): _mutate_compatibility_availability(definitions)),
		_case("generic_compatibility_unknown", func(definitions: Array): _by_id(definitions, "fixture_event")["compatibility"]["weapon_ids"] = ["missing_weapon"]),
		_case("generic_compatibility_category", func(definitions: Array): _by_id(definitions, "fixture_event")["compatibility"]["weapon_ids"] = ["time_guardian"]),
		_case("generic_compatibility_availability", func(definitions: Array): _by_id(definitions, "fixture_weapon")["availability"] = ["LAUNCH"]),
		_case("character_category", func(definitions: Array): _by_id(definitions, "time_guardian")["category"] = "weapon"),
		_case("character_availability", func(definitions: Array): _by_id(definitions, "time_guardian")["availability"] = ["LAUNCH"]),
		_case("character_backref", func(definitions: Array): _by_id(definitions, "time_guardian")["references"] = []),
		_case("weapon_reference_category", func(definitions: Array): _by_id(definitions, "sword")["category"] = "event"),
		_case("weapon_reference_availability", func(definitions: Array): _by_id(definitions, "sword")["availability"] = ["LAUNCH"]),
		_case("time_reference_category", func(definitions: Array): _by_id(definitions, "stop")["category"] = "event"),
		_case("time_reference_availability", func(definitions: Array): _by_id(definitions, "stop")["availability"] = ["LAUNCH"]),
		_case("talent_category", func(definitions: Array): _by_id(definitions, "widened_guard")["category"] = "item"),
		_case("talent_availability", func(definitions: Array): _by_id(definitions, "widened_guard")["availability"] = ["LAUNCH"]),
		_case("talent_character_scope_missing", func(definitions: Array): _by_id(definitions, "widened_guard")["compatibility"] = {}),
		_case("talent_character_scope_mismatch", func(definitions: Array): _by_id(definitions, "widened_guard")["compatibility"] = {"character_ids": ["wanderer"]}),
		_case("talent_character_scope_overscoped", func(definitions: Array): _overscope_talent_compatibility(definitions)),
		_case("missing_talent", func(definitions: Array): definitions.erase(_by_id(definitions, "widened_guard"))),
		_case("category_specific_field", func(definitions: Array): _by_id(definitions, "sword")["base_stats"] = {}),
	]
	for index: int in range(cases.size()):
		var invalid_case: Dictionary = cases[index]
		var definitions := _valid_definitions()
		var mutate: Callable = invalid_case["mutate"]
		mutate.call(definitions)
		var registry = ContentRegistryScript.new()
		var report = registry.load_packs(
			[{
				"path": _write_pack("invalid_%02d_%s" % [index, invalid_case["label"]], definitions),
				"required": true,
			}],
			GAME_VERSION,
			&"LAUNCH"
		)
		suite.assert_true(report.has_blocking_errors(), "%s fails during real pack ingestion" % invalid_case["label"])
		suite.assert_true(registry.all_content().is_empty(), "%s exposes no partial definitions" % invalid_case["label"])
	_test_wanderer_talent_milestone_coverage(suite)
	suite.finish(get_tree())


func _test_valid_real_pack(suite) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": _write_pack("valid", _valid_definitions()), "required": true}],
		GAME_VERSION,
		&"LAUNCH"
	)
	suite.assert_true(not report.has_blocking_errors(), "valid temporary character pack activates: %s" % str(report.blocking_errors))
	suite.assert_equal(report.loaded_count, 16, "valid temporary pack loads its complete closed graph")
	suite.assert_equal(
		registry.resolve_character_runtime_profile(&"time_guardian", &"LAUNCH").get("id"),
		"time_guardian_launch_v1",
		"valid temporary pack resolves its character profile"
	)


func _test_frozen_v2_compatibility_forms(suite) -> void:
	var cases: Array[Dictionary] = [
		{"label": "empty_character_ids", "compatibility": {"character_ids": []}},
		{"label": "empty_weapon_ids", "compatibility": {"weapon_ids": []}},
		{"label": "empty_time_ability_ids", "compatibility": {"time_ability_ids": []}},
		{"label": "archetype_ids", "compatibility": {"archetype_ids": ["legacy_archetype"]}},
		{"label": "modes", "compatibility": {"modes": ["normal"]}},
	]
	for index: int in range(cases.size()):
		var definitions := _valid_definitions()
		_by_id(definitions, "fixture_event")["compatibility"] = cases[index]["compatibility"]
		var registry = ContentRegistryScript.new()
		var report = registry.load_packs(
			[{
				"path": _write_pack("valid_v2_compatibility_%02d_%s" % [index, cases[index]["label"]], definitions),
				"required": true,
			}],
			GAME_VERSION,
			&"LAUNCH"
		)
		suite.assert_true(
			not report.has_blocking_errors(),
			"frozen v2 compatibility form %s remains loadable: %s" % [cases[index]["label"], str(report.blocking_errors)]
		)
		suite.assert_equal(registry.all_content().size(), 16, "%s activates the complete fixture graph" % cases[index]["label"])


func _valid_definitions() -> Array:
	var profile := _base_guardian_profile()
	profile["name_key"] = "TEST_NAME"
	profile["description_key"] = "TEST_DESC"
	var definitions: Array = [
		_identity("time_guardian", "character", ["LAUNCH", "EXPANSION"], ["time_guardian_launch_v1"]),
	]
	for weapon_id: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		definitions.append(_identity(weapon_id, "weapon", ["LAUNCH", "EXPANSION"], []))
	for ability_id: String in ["stop", "rewind", "rift", "accelerate"]:
		definitions.append(_identity(ability_id, "time_ability", ["LAUNCH", "EXPANSION"], []))
	definitions.append(_identity("fixture_weapon", "weapon", ["LAUNCH", "EXPANSION"], []))
	var fixture_event := _identity("fixture_event", "event", ["LAUNCH", "EXPANSION"], [])
	fixture_event["compatibility"] = {"weapon_ids": ["fixture_weapon"]}
	definitions.append(fixture_event)
	for talent_id: String in ["widened_guard", "fortress_core", "temporal_rebuke"]:
		var talent := _identity(talent_id, "talent", ["LAUNCH", "EXPANSION"], [])
		talent["compatibility"] = {"character_ids": ["time_guardian"]}
		talent["kind"] = "time_guardian"
		talent["archetype"] = ""
		talent["role"] = "route"
		talent["rarity"] = "common"
		talent["icon_id"] = "content_%s" % talent_id
		definitions.append(talent)
	definitions.append(profile)
	return definitions


func _overscope_talent_compatibility(definitions: Array) -> void:
	definitions.append(_identity("wanderer", "character", ["LAUNCH", "EXPANSION"], []))
	_by_id(definitions, "widened_guard")["compatibility"] = {
		"character_ids": ["time_guardian", "wanderer"],
	}


func _test_wanderer_talent_milestone_coverage(suite) -> void:
	var valid_registry = ContentRegistryScript.new()
	var valid_report = valid_registry.load_packs(
		[{"path": _write_pack("valid_wanderer_talent_milestones", _valid_wanderer_m1_definitions()), "required": true}],
		GAME_VERSION,
		&"M1"
	)
	suite.assert_true(
		not valid_report.has_blocking_errors(),
		"Wanderer talent milestone fixture activates: %s" % str(valid_report.blocking_errors)
	)
	var definitions := _valid_wanderer_m1_definitions()
	_by_id(definitions, "tal_eternity_reserve")["availability"] = ["M1", "NEXT", "LAUNCH", "EXPANSION"]
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": _write_pack("invalid_wanderer_talent_current", definitions), "required": true}],
		GAME_VERSION,
		&"M1"
	)
	suite.assert_true(report.has_blocking_errors(), "Wanderer talent missing CURRENT fails during real pack ingestion")
	suite.assert_true(registry.all_content().is_empty(), "Wanderer talent milestone failure exposes no partial definitions")


func _valid_wanderer_m1_definitions() -> Array:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	var profile: Dictionary = {}
	if value is Array:
		for definition_value: Variant in value:
			if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == "wanderer_m1_v1":
				profile = (definition_value as Dictionary).duplicate(true)
				break
	profile["name_key"] = "TEST_NAME"
	profile["description_key"] = "TEST_DESC"
	var definitions: Array = [
		_identity("wanderer", "character", ["M1", "CURRENT", "NEXT", "LAUNCH", "EXPANSION"], ["wanderer_m1_v1"]),
		_identity("sword", "weapon", ["M1", "CURRENT", "NEXT"], []),
		_identity("bow", "weapon", ["NEXT"], []),
		_identity("stop", "time_ability", ["M1", "CURRENT", "NEXT"], []),
		_identity("rewind", "time_ability", ["M1", "CURRENT", "NEXT"], []),
		_identity("accelerate", "time_ability", ["NEXT"], []),
		_identity("rift", "time_ability", ["NEXT"], []),
	]
	for talent_id: String in ["tal_eternity_reserve", "tal_ruin_execute", "tal_steel_recover"]:
		var talent := _identity(talent_id, "talent", ["M1", "CURRENT", "NEXT", "LAUNCH", "EXPANSION"], [])
		talent["compatibility"] = {"character_ids": ["wanderer"]}
		talent["kind"] = "wanderer"
		talent["archetype"] = ""
		talent["role"] = "route"
		talent["rarity"] = "common"
		talent["icon_id"] = "content_%s" % talent_id
		definitions.append(talent)
	definitions.append(profile)
	return definitions


func _identity(
	content_id: String,
	category: String,
	availability: Array,
	references: Array
) -> Dictionary:
	var definition := {
		"id": content_id,
		"category": category,
		"availability": availability.duplicate(),
		"name_key": "TEST_NAME",
		"description_key": "TEST_DESC",
		"tags": ["fixture"],
		"compatibility": {},
		"effects": {},
	}
	if not references.is_empty():
		definition["references"] = references.duplicate()
	return definition


func _base_guardian_profile() -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	if not value is Array:
		return {}
	for definition_value: Variant in value:
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == "time_guardian_launch_v1":
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _profile(definitions: Array) -> Dictionary:
	return _by_id(definitions, "time_guardian_launch_v1")


func _mutate_compatibility_availability(definitions: Array) -> void:
	_profile(definitions)["compatibility"]["weapon_ids"] = ["sword"]
	_by_id(definitions, "sword")["availability"] = ["LAUNCH"]


func _by_id(definitions: Array, content_id: String) -> Dictionary:
	for definition_value: Variant in definitions:
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == content_id:
			return definition_value as Dictionary
	return {}


func _write_pack(label: String, definitions: Array) -> String:
	var root := "user://p12_character_ingestion/%s" % label
	var absolute_root := ProjectSettings.globalize_path(root)
	DirAccess.make_dir_recursive_absolute(absolute_root.path_join("content"))
	DirAccess.make_dir_recursive_absolute(absolute_root.path_join("localization"))
	var content_text := JSON.stringify(definitions, "\t")
	var localization_text := "keys,en,zh_cn\n\"TEST_NAME\",\"Test\",\"测试\"\n\"TEST_DESC\",\"Test content.\",\"测试内容。\"\n"
	_write_text(root.path_join("content/all.json"), content_text)
	_write_text(root.path_join("localization/translations.csv"), localization_text)
	var pack := {
		"pack_id": "p12_%s" % label,
		"pack_version": "1.0.0",
		"schema_version": 2,
		"game_version_range": ">=0.4.0-dev <1.0.0",
		"dependencies": [],
		"load_order": 0,
		"content_manifest": ["content/all.json"],
		"localization_sources": ["localization/translations.csv"],
		"asset_manifest": [],
		"integrity_hashes": {
			"content/all.json": _sha256(content_text.to_utf8_buffer()),
			"localization/translations.csv": _sha256(localization_text.to_utf8_buffer()),
		},
		"entitlement_tag": "",
	}
	_write_text(root.path_join("pack.json"), JSON.stringify(pack, "\t"))
	return root.path_join("pack.json")


func _write_text(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(value)


func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


func _case(label: String, mutate: Callable) -> Dictionary:
	return {"label": label, "mutate": mutate}
