extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const CharacterRuntimeProfileScript := preload("res://scripts/player/characters/character_runtime_profile.gd")

const SCHEMA_PATH := "res://data/schemas/character_runtime_profile_v1.schema.json"
const CATALOG_PATH := "res://data/content_packs/base/content/character_runtime_profiles.json"
const EXPECTED_IDS := [
	"primordial_knight_launch_v1",
	"time_guardian_launch_v1",
	"time_lord_launch_v1",
	"void_walker_launch_v1",
	"wanderer_launch_v1",
	"wanderer_m1_v1",
]
const EXPECTED_NUMBERS := {
	"wanderer_m1_v1": [200.0, 30.0, 0.0, 220.0, 1.0, 0.05, 1.5, 100.0, 2.0, 17.0, 27.0, 520.0, 12.0],
	"wanderer_launch_v1": [200.0, 30.0, 0.0, 220.0, 1.0, 0.05, 1.5, 100.0, 2.0, 17.0, 27.0, 520.0, 12.0],
	"time_guardian_launch_v1": [240.0, 27.0, 10.0, 190.0, 0.9, 0.04, 1.5, 120.0, 2.0, 18.0, 30.0, 500.0, 12.0],
	"void_walker_launch_v1": [160.0, 32.0, 0.0, 235.0, 1.05, 0.08, 1.6, 90.0, 2.0, 15.0, 24.0, 560.0, 11.0],
	"primordial_knight_launch_v1": [230.0, 31.0, 8.0, 200.0, 0.9, 0.05, 1.55, 110.0, 2.0, 18.0, 30.0, 490.0, 10.0],
	"time_lord_launch_v1": [175.0, 24.0, 2.0, 205.0, 0.95, 0.05, 1.5, 160.0, 4.0, 16.0, 27.0, 520.0, 12.0],
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_schema(suite)
	var definitions := _catalog(suite)
	if definitions.size() == 6:
		_test_catalog(suite, definitions)
		_test_exact_mechanic_parameters(suite, definitions)
		_test_closed_handler_parameters(suite, definitions)
		_test_fail_closed_and_deep_copy(suite, definitions)
	suite.finish(get_tree())


func _test_schema(suite) -> void:
	var schema_value: Variant = _read_json(SCHEMA_PATH, suite)
	if not schema_value is Dictionary:
		return
	var schema: Dictionary = schema_value
	suite.assert_equal(
		schema.get("$id"),
		"planewalker://schemas/character-runtime-profile/1.0.0",
		"character runtime profile schema id is stable"
	)
	suite.assert_equal(schema.get("additionalProperties"), false, "character profile root is closed")
	for field: String in CharacterRuntimeProfileScript.REQUIRED_FIELDS:
		suite.assert_true(schema.get("required", []).has(field), "schema requires %s" % field)
	var properties: Dictionary = schema.get("properties", {})
	suite.assert_equal(
		properties.get("category", {}).get("const"),
		"character_runtime_profile",
		"character profile category is closed"
	)
	suite.assert_equal(
		properties.get("effects", {}).get("maxProperties"),
		0,
		"character profiles cannot embed arbitrary effects"
	)
	var mastery: Dictionary = schema.get("$defs", {}).get("weapon_mastery", {})
	for weapon_id: String in CharacterRuntimeProfileScript.WEAPON_IDS:
		suite.assert_true(mastery.get("properties", {}).has(weapon_id), "schema supports %s mastery" % weapon_id)
	var interactions: Dictionary = schema.get("$defs", {}).get("time_interactions", {})
	for ability_id: String in CharacterRuntimeProfileScript.TIME_ABILITY_IDS:
		suite.assert_true(interactions.get("required", []).has(ability_id), "schema requires %s conversion" % ability_id)
	var time_handler_ids: Array = schema.get("$defs", {}).get("time_interaction", {}).get("properties", {}).get("handler_id", {}).get("enum", [])
	for handler_id: String in CharacterRuntimeProfileScript.TIME_HANDLERS:
		suite.assert_true(time_handler_ids.has(handler_id), "schema closes time handler %s" % handler_id)
	var talent_ids: Array = properties.get("talent_ids", {}).get("items", {}).get("enum", [])
	for talent_id: String in CharacterRuntimeProfileScript.TALENT_IDS:
		suite.assert_true(talent_ids.has(talent_id), "schema closes talent id %s" % talent_id)
	var parameter_branches: Array = schema.get("$defs", {}).get("parameter_value", {}).get("oneOf", [])
	var parameter_types: Array[String] = []
	for branch_value: Variant in parameter_branches:
		if branch_value is Dictionary and (branch_value as Dictionary).has("type"):
			parameter_types.append(str((branch_value as Dictionary)["type"]))
	suite.assert_true(parameter_types.has("number"), "schema accepts the single JSON numeric branch")
	suite.assert_true(not parameter_types.has("integer"), "schema avoids overlapping number/integer oneOf branches")


func _test_catalog(suite, definitions: Array[Dictionary]) -> void:
	var ids: Array[String] = []
	for definition: Dictionary in definitions:
		ids.append(str(definition.get("id", "")))
		var parser = CharacterRuntimeProfileScript.new()
		var result: Dictionary = parser.configure(definition)
		suite.assert_true(
			bool(result.get("ok", false)),
			"%s parses: %s" % [str(definition.get("id", "")), str(result.get("context", {}))]
		)
		if not bool(result.get("ok", false)):
			continue
		var snapshot := parser.snapshot()
		var expected: Array = EXPECTED_NUMBERS[str(definition["id"])]
		var stats: Dictionary = snapshot.get("base_stats", {})
		var mobility: Dictionary = snapshot.get("mobility", {})
		suite.assert_equal(snapshot.get("character_id"), definition.get("character_id"), "character identity is retained")
		var actual := [
			stats.get("max_hp"), stats.get("attack"), stats.get("defense"), stats.get("move_speed"),
			stats.get("attack_speed"), stats.get("crit_chance"), stats.get("crit_multiplier"),
			stats.get("time_energy_max"), stats.get("time_energy_regen"),
			mobility.get("dash_duration_frames"), mobility.get("dash_cooldown_frames"),
			mobility.get("dash_speed"), mobility.get("dash_invulnerable_frames"),
		]
		suite.assert_equal(actual, expected, "%s retains every exact stat and mobility baseline" % definition["id"])
		suite.assert_equal(mobility.get("dash_cost_kind"), "none", "dash cost kind is explicit")
		suite.assert_equal(mobility.get("dash_cost"), 0, "dash cost is explicit")
		var expected_mastery_count := 2 if definition["id"] == "wanderer_m1_v1" else 5
		suite.assert_equal(snapshot.get("weapon_mastery", {}).size(), expected_mastery_count, "profile covers only its certified weapon surface")
		suite.assert_equal(snapshot.get("time_interactions", {}).size(), 4, "all four time abilities are covered")
	ids.sort()
	suite.assert_equal(ids, EXPECTED_IDS, "exactly six milestone-aware character profiles exist")

	var m1 := _by_id(definitions, "wanderer_m1_v1")
	suite.assert_equal(m1.get("availability"), ["M1", "CURRENT", "NEXT"], "M1 Wanderer remains M1/CURRENT/NEXT")
	suite.assert_equal(m1.get("character_skill", {}).get("handler_id"), "none", "M1 Wanderer has no Launch skill handler")
	for profile_id: String in EXPECTED_IDS:
		if profile_id == "wanderer_m1_v1":
			continue
		suite.assert_equal(
			_by_id(definitions, profile_id).get("availability"),
			["LAUNCH", "EXPANSION"],
			"%s remains Launch/Expansion-only" % profile_id
		)


func _test_exact_mechanic_parameters(suite, definitions: Array[Dictionary]) -> void:
	var wanderer := _by_id(definitions, "wanderer_launch_v1")
	suite.assert_equal(wanderer["character_skill"]["parameters"]["windup_frames"], 6.0, "Waypoint Recall windup is exact")
	suite.assert_equal(wanderer["character_skill"]["parameters"]["recovery_frames"], 12.0, "Waypoint Recall recovery is exact")
	suite.assert_equal(wanderer["passive"]["parameters"]["wayfarer_energy_restore"], 6.0, "Wayfarer restore is exact")
	suite.assert_equal(wanderer["passive"]["parameters"]["bow_full_charge_frames"], 44.0, "Wanderer Bow forgiveness is exact")

	var guardian := _by_id(definitions, "time_guardian_launch_v1")
	suite.assert_equal(guardian["character_skill"]["parameters"]["perfect_last_frame"], 8.0, "Guardian perfect window is exact")
	suite.assert_equal(guardian["character_skill"]["parameters"]["normal_last_frame"], 23.0, "Guardian normal window is exact")
	suite.assert_equal(guardian["character_skill"]["cooldown_frames"], 240.0, "Guardian ordinary cooldown is exact")
	suite.assert_equal(guardian["character_skill"]["parameters"]["fortress_cooldown_frames"], 600.0, "Fortress cooldown is exact")

	var void_walker := _by_id(definitions, "void_walker_launch_v1")
	suite.assert_equal(void_walker["character_skill"]["cooldown_frames"], 480.0, "Void Devour cooldown is exact")
	suite.assert_equal(void_walker["character_skill"]["parameters"]["windup_frames"], 24.0, "Void Devour windup is exact")
	suite.assert_equal(void_walker["character_skill"]["parameters"]["heal_ratio"], 0.15, "Void Devour healing ratio is exact")
	suite.assert_equal(void_walker["passive"]["parameters"]["corruption_tick_frames"], 30.0, "Void corruption cadence is exact")

	var knight := _by_id(definitions, "primordial_knight_launch_v1")
	suite.assert_equal(knight["character_skill"]["cooldown_frames"], 540.0, "Realm Cleave cooldown is exact")
	suite.assert_equal(knight["character_skill"]["parameters"]["windup_frames"], 36.0, "Realm Cleave windup is exact")
	suite.assert_equal(knight["weapon_mastery"]["gun"]["parameters"]["minimum_hold_frames"], 18.0, "Knight Gun commitment is exact")
	suite.assert_equal(knight["character_skill"]["parameters"]["instability_frames"], 480.0, "Realm Cleave instability is exact")

	var time_lord := _by_id(definitions, "time_lord_launch_v1")
	suite.assert_equal(time_lord["passive"]["parameters"]["page_rate_cap_frames"], 60.0, "Codex Page rate cap is exact")
	suite.assert_equal(time_lord["character_skill"]["cooldown_frames"], 120.0, "Codex Infusion cooldown is exact")
	suite.assert_equal(time_lord["character_skill"]["parameters"]["dominion_cooldown_frames"], 480.0, "Time Dominion cooldown is exact")
	var stop_pair: Dictionary = time_lord["time_interactions"]["stop"]["parameters"]
	suite.assert_equal(stop_pair["rewind_zone_radius"], 96.0, "Stop/Rewind base zone radius is exact")
	suite.assert_equal(stop_pair["rewind_dominion_zone_radius"], 128.0, "Stop/Rewind Dominion radius is exact")
	suite.assert_equal(stop_pair["accelerate_recovery_multiplier"], 0.8, "Stop/Accelerate base recovery is exact")
	suite.assert_equal(stop_pair["accelerate_dominion_recovery_multiplier"], 0.65, "Stop/Accelerate Dominion recovery is exact")
	var rewind_pair: Dictionary = time_lord["time_interactions"]["rewind"]["parameters"]
	suite.assert_equal(rewind_pair["rift_pulse_multiplier"], 1.25, "Rewind/Rift base pulse is exact")
	suite.assert_equal(rewind_pair["rift_dominion_pulse_multiplier"], 1.75, "Rewind/Rift Dominion pulse is exact")
	suite.assert_equal(rewind_pair["accelerate_dominion_echo_multiplier"], 1.1, "Rewind/Accelerate Dominion echo is exact")


func _test_closed_handler_parameters(suite, definitions: Array[Dictionary]) -> void:
	var cases: Array[Dictionary] = [
		_profile_case("wanderer_launch_v1", "Wanderer passive missing key", func(value: Dictionary): value["passive"]["parameters"].erase("progress_threshold")),
		_profile_case("wanderer_launch_v1", "Wanderer skill extra key", func(value: Dictionary): value["character_skill"]["parameters"]["payload_id"] = "hidden"),
		_profile_case("wanderer_launch_v1", "Wanderer mastery hidden payload", func(value: Dictionary): value["weapon_mastery"]["sword"]["parameters"]["payload_id"] = "hidden"),
		_profile_case("time_guardian_launch_v1", "Guardian passive wrong value", func(value: Dictionary): value["passive"]["parameters"]["damage_reduction"] = 0.5),
		_profile_case("time_guardian_launch_v1", "Guardian skill missing key", func(value: Dictionary): value["character_skill"]["parameters"].erase("ward_cost")),
		_profile_case("time_guardian_launch_v1", "Guardian time extra key", func(value: Dictionary): value["time_interactions"]["stop"]["parameters"]["extension_frames"] = 30),
		_profile_case("void_walker_launch_v1", "Void passive wrong type", func(value: Dictionary): value["passive"]["parameters"]["pause"] = true),
		_profile_case("void_walker_launch_v1", "Void skill wrong exact number", func(value: Dictionary): value["character_skill"]["parameters"]["heal_ratio"] = 0.16),
		_profile_case("primordial_knight_launch_v1", "Knight mastery missing key", func(value: Dictionary): value["weapon_mastery"]["gun"]["parameters"].erase("minimum_hold_frames")),
		_profile_case("primordial_knight_launch_v1", "Knight mastery wrong action", func(value: Dictionary): value["weapon_mastery"]["sword"]["parameters"]["commitment_action"] = "ultimate"),
		_profile_case("time_lord_launch_v1", "Time Lord passive missing key", func(value: Dictionary): value["passive"]["parameters"].erase("page_rate_cap_frames")),
		_profile_case("time_lord_launch_v1", "Time Lord skill extra key", func(value: Dictionary): value["character_skill"]["parameters"]["free_cast"] = true),
		_profile_case("time_lord_launch_v1", "Time Lord pair missing key", func(value: Dictionary): value["time_interactions"]["stop"]["parameters"].erase("rewind_zone_radius")),
	]
	for invalid_case: Dictionary in cases:
		var candidate := _by_id(definitions, str(invalid_case["profile_id"]))
		var mutate: Callable = invalid_case["mutate"]
		mutate.call(candidate)
		var result: Dictionary = CharacterRuntimeProfileScript.new().configure(candidate)
		suite.assert_true(not bool(result.get("ok", false)), "%s fails closed" % invalid_case["label"])

	var m1_cases: Array[Dictionary] = [
		_case("M1 resource maximum", func(value: Dictionary): value["resource"]["maximum"] = 1),
		_case("M1 skill cooldown", func(value: Dictionary): value["character_skill"]["cooldown_frames"] = 1),
		_case("M1 passive hidden payload", func(value: Dictionary): value["passive"]["parameters"]["payload_id"] = "hidden"),
		_case("M1 skill hidden payload", func(value: Dictionary): value["character_skill"]["parameters"]["payload_id"] = "hidden"),
		_case("M1 mastery hidden payload", func(value: Dictionary): value["weapon_mastery"]["sword"]["parameters"]["payload_id"] = "hidden"),
		_case("M1 time hidden payload", func(value: Dictionary): value["time_interactions"]["stop"]["parameters"]["payload_id"] = "hidden"),
		_case("M1 capability widening", func(value: Dictionary): value["capabilities"].append("character.path_marks")),
		_case("M1 talent widening", func(value: Dictionary): value["talent_ids"] = ["widened_guard", "fortress_core", "temporal_rebuke"]),
	]
	for invalid_case: Dictionary in m1_cases:
		var candidate := _by_id(definitions, "wanderer_m1_v1")
		var mutate: Callable = invalid_case["mutate"]
		mutate.call(candidate)
		var result: Dictionary = CharacterRuntimeProfileScript.new().configure(candidate)
		suite.assert_true(not bool(result.get("ok", false)), "%s fails closed" % invalid_case["label"])


func _test_fail_closed_and_deep_copy(suite, definitions: Array[Dictionary]) -> void:
	var source := _by_id(definitions, "wanderer_launch_v1")
	var parser = CharacterRuntimeProfileScript.new()
	var accepted: Dictionary = parser.configure(source)
	suite.assert_true(bool(accepted.get("ok", false)), "fail-closed fixture configures")
	var accepted_snapshot := parser.snapshot()
	suite.assert_equal(str(parser.profile_id), "wanderer_launch_v1", "typed profile identity is projected")
	suite.assert_equal(str(parser.character_id), "wanderer", "typed character identity is projected")
	suite.assert_equal(parser.base_stats.get("attack"), 30.0, "typed base stats are projected")

	var cases: Array[Dictionary] = [
		_case("unknown root field", func(value: Dictionary): value["script_path"] = "res://hostile.gd"),
		_case("unknown runtime", func(value: Dictionary): value["runtime_kind"] = "hostile"),
		_case("unsupported profile version", func(value: Dictionary): value["profile_version"] = 2),
		_case("non-finite stat", func(value: Dictionary): value["base_stats"]["attack"] = INF),
		_case("unknown passive handler", func(value: Dictionary): value["passive"]["handler_id"] = "hostile"),
		_case("unknown skill handler", func(value: Dictionary): value["character_skill"]["handler_id"] = "hostile"),
		_case("unknown mastery handler", func(value: Dictionary): value["weapon_mastery"]["sword"]["handler_id"] = "hostile"),
		_case("unknown time handler", func(value: Dictionary): value["time_interactions"]["stop"]["handler_id"] = "hostile"),
		_case("unknown talent", func(value: Dictionary): value["talent_ids"] = ["unknown_talent"]),
		_case("cross-character talent", func(value: Dictionary): value["talent_ids"] = ["widened_guard", "fortress_core", "temporal_rebuke"]),
		_case("missing weapon coverage", func(value: Dictionary): value["weapon_mastery"].erase("bow")),
		_case("missing time coverage", func(value: Dictionary): value["time_interactions"].erase("rift")),
		_case("unknown weapon reference", func(value: Dictionary): value["references"][1] = "unknown_weapon"),
		_case("Launch profile in M1", func(value: Dictionary): value["availability"] = ["M1", "LAUNCH", "EXPANSION"]),
	]
	for invalid_case: Dictionary in cases:
		var candidate := source.duplicate(true)
		var mutate: Callable = invalid_case["mutate"]
		mutate.call(candidate)
		var result: Dictionary = parser.configure(candidate)
		suite.assert_true(not bool(result.get("ok", false)), "%s fails closed" % invalid_case["label"])
		suite.assert_equal(parser.snapshot(), accepted_snapshot, "%s preserves accepted state" % invalid_case["label"])
		suite.assert_equal(parser.base_stats.get("attack"), 30.0, "%s preserves typed projected state" % invalid_case["label"])

	source["base_stats"]["attack"] = 999
	accepted_snapshot["resource"]["maximum"] = 999
	suite.assert_equal(parser.snapshot().get("base_stats", {}).get("attack"), 30, "parser isolates caller mutations")
	suite.assert_equal(parser.snapshot().get("resource", {}).get("maximum"), 5, "snapshot isolates nested mutations")
	suite.assert_true(CharacterRuntimeProfileScript.from_definition(_by_id(definitions, "time_lord_launch_v1")) != null, "static strict constructor accepts valid data")
	var invalid_static := _by_id(definitions, "time_lord_launch_v1")
	invalid_static["talent_ids"] = ["missing"]
	suite.assert_true(CharacterRuntimeProfileScript.from_definition(invalid_static) == null, "static strict constructor rejects invalid data")
	var widened_m1 := _by_id(definitions, "wanderer_m1_v1")
	widened_m1["character_skill"] = _by_id(definitions, "wanderer_launch_v1")["character_skill"].duplicate(true)
	suite.assert_true(CharacterRuntimeProfileScript.from_definition(widened_m1) == null, "M1 compatibility profile rejects Launch character skill exposure")


func _catalog(suite) -> Array[Dictionary]:
	var value: Variant = _read_json(CATALOG_PATH, suite)
	var definitions: Array[Dictionary] = []
	if value is Array:
		for definition_value: Variant in value:
			if definition_value is Dictionary:
				definitions.append((definition_value as Dictionary).duplicate(true))
	suite.assert_equal(definitions.size(), 6, "character profile catalog contains six definitions")
	return definitions


func _by_id(definitions: Array[Dictionary], profile_id: String) -> Dictionary:
	for definition: Dictionary in definitions:
		if str(definition.get("id", "")) == profile_id:
			return definition.duplicate(true)
	return {}


func _case(label: String, mutate: Callable) -> Dictionary:
	return {"label": label, "mutate": mutate}


func _profile_case(profile_id: String, label: String, mutate: Callable) -> Dictionary:
	return {"profile_id": profile_id, "label": label, "mutate": mutate}


func _read_json(path: String, suite) -> Variant:
	suite.assert_true(FileAccess.file_exists(path), "%s exists" % path)
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "%s opens" % path)
	if file == null:
		return null
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	suite.assert_equal(parse_error, OK, "%s contains valid JSON" % path)
	return parser.data if parse_error == OK else null
