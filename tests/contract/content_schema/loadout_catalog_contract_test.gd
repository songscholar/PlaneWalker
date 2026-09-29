extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")

const BASE_PACK_PATH := "res://data/content_packs/base/pack.json"
const ALL_MILESTONES := ["M1", "CURRENT", "NEXT", "LAUNCH", "EXPANSION"]
const LAUNCH_MILESTONES := ["LAUNCH", "EXPANSION"]
const CANDIDATE_MILESTONES := ["NEXT", "LAUNCH", "EXPANSION"]
const EXPECTED_CHARACTERS := [
	"primordial_knight", "time_guardian", "time_lord", "void_walker", "wanderer",
]
const EXPECTED_WEAPONS := ["bow", "gauntlets", "gun", "staff", "sword"]
const EXPECTED_TIME_ABILITIES := ["accelerate", "rewind", "rift", "stop"]
const EXPECTED_WEAPON_PROFILES := [
	"bow_candidate_v1", "bow_launch_v1", "gauntlets_launch_v1", "gun_launch_v1",
	"staff_launch_v1", "sword_launch_v1", "sword_m1_v1",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": BASE_PACK_PATH, "required": true}],
		"0.4.0-dev",
		&"M1"
	)
	suite.assert_true(
		not report.has_blocking_errors(),
		"base pack loadout catalog activates: %s" % str(report.blocking_errors)
	)
	_assert_catalog(suite, registry)
	_assert_availability_boundaries(suite, registry)
	_assert_returned_definitions_are_deep_copies(suite, registry)
	suite.finish(get_tree())


func _assert_catalog(suite, registry: RefCounted) -> void:
	suite.assert_equal(
		_ids(registry.get_by_category(&"character")),
		EXPECTED_CHARACTERS,
		"five characters are canonical"
	)
	suite.assert_equal(
		_ids(registry.get_by_category(&"weapon")),
		EXPECTED_WEAPONS,
		"five weapons are canonical"
	)
	suite.assert_equal(
		_ids(registry.get_by_category(&"time_ability")),
		EXPECTED_TIME_ABILITIES,
		"four time abilities are canonical"
	)
	suite.assert_equal(
		_ids(registry.get_by_category(&"weapon_runtime_profile")),
		EXPECTED_WEAPON_PROFILES,
		"seven milestone-aware weapon runtime profiles are canonical"
	)


func _assert_availability_boundaries(suite, registry: RefCounted) -> void:
	_assert_availability(suite, registry, "wanderer", ALL_MILESTONES)
	for character_id: String in ["primordial_knight", "time_guardian", "time_lord", "void_walker"]:
		_assert_availability(suite, registry, character_id, LAUNCH_MILESTONES)

	_assert_availability(suite, registry, "sword", ALL_MILESTONES)
	_assert_availability(suite, registry, "bow", CANDIDATE_MILESTONES)
	for weapon_id: String in ["gauntlets", "gun", "staff"]:
		_assert_availability(suite, registry, weapon_id, LAUNCH_MILESTONES)

	for time_ability_id: String in ["rewind", "stop"]:
		_assert_availability(suite, registry, time_ability_id, ALL_MILESTONES)
	for time_ability_id: String in ["accelerate", "rift"]:
		_assert_availability(suite, registry, time_ability_id, CANDIDATE_MILESTONES)

	suite.assert_true(
		registry.get_content(&"sword").get("availability", []).has("M1"),
		"Sword remains M1"
	)
	suite.assert_true(
		not registry.get_content(&"bow").get("availability", []).has("M1"),
		"Bow does not leak into M1"
	)
	suite.assert_true(
		not registry.get_content(&"rift").get("availability", []).has("M1"),
		"Rift does not leak into M1"
	)
	suite.assert_true(
		not registry.get_content(&"accelerate").get("availability", []).has("M1"),
		"Accelerate does not leak into M1"
	)


func _assert_returned_definitions_are_deep_copies(suite, registry: RefCounted) -> void:
	var character_definitions: Array[Dictionary] = registry.get_by_category(&"character")
	if not character_definitions.is_empty():
		var character_id := str(character_definitions[0].get("id", ""))
		character_definitions[0]["availability"].clear()
		character_definitions[0]["tags"].append("forged-tag")
		var fresh_character: Dictionary = registry.get_content(StringName(character_id))
		suite.assert_true(
			not fresh_character.get("availability", []).is_empty(),
			"category query returns definitions with deep-copied availability"
		)
		suite.assert_true(
			not fresh_character.get("tags", []).has("forged-tag"),
			"category query returns definitions with deep-copied tags"
		)

	var sword: Dictionary = registry.get_content(&"sword")
	if not sword.is_empty():
		sword["availability"].clear()
		sword["compatibility"]["forged"] = ["mutation"]
		var fresh_sword: Dictionary = registry.get_content(&"sword")
		suite.assert_equal(
			_sorted_strings(fresh_sword.get("availability", [])),
			_sorted_strings(ALL_MILESTONES),
			"single definition query returns deep-copied availability"
		)
		suite.assert_true(
			not fresh_sword.get("compatibility", {}).has("forged"),
			"single definition query returns deep-copied compatibility"
		)


func _assert_availability(suite, registry: RefCounted, content_id: String, expected: Array) -> void:
	var definition: Dictionary = registry.get_content(StringName(content_id))
	suite.assert_equal(
		_sorted_strings(definition.get("availability", [])),
		_sorted_strings(expected),
		"%s availability matches its release boundary" % content_id
	)


func _ids(definitions: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for definition: Dictionary in definitions:
		ids.append(str(definition.get("id", "")))
	ids.sort()
	return ids


func _sorted_strings(values: Array) -> Array[String]:
	var sorted_values: Array[String] = []
	for value: Variant in values:
		sorted_values.append(str(value))
	sorted_values.sort()
	return sorted_values
