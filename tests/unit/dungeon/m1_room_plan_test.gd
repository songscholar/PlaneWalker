extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const EncounterCatalogScript := preload("res://scripts/dungeon/encounter_catalog.gd")
const M1RoomPlanScript := preload("res://scripts/dungeon/m1_room_plan.gd")
const RunDirectorScript := preload("res://scripts/dungeon/run_director.gd")

const EXPECTED := [
	{"room_number": 1, "type": "combat", "reward_kind": "starter", "encounter_id": "m1_room_01", "plan_id": "m1.encounters.v1", "target_seconds_min": 45, "target_seconds_max": 70},
	{"room_number": 2, "type": "combat", "reward_kind": "reinforcement", "encounter_id": "m1_room_02", "plan_id": "m1.encounters.v1", "target_seconds_min": 60, "target_seconds_max": 85},
	{"room_number": 3, "type": "combat", "reward_kind": "talent", "encounter_id": "m1_room_03", "plan_id": "m1.encounters.v1", "target_seconds_min": 70, "target_seconds_max": 100},
	{"room_number": 4, "type": "elite", "reward_kind": "contract", "encounter_id": "m1_room_04_elite", "plan_id": "m1.encounters.v1", "target_seconds_min": 90, "target_seconds_max": 125},
	{"room_number": 5, "type": "boss", "reward_kind": "none", "encounter_id": "m1_room_05_boss", "plan_id": "m1.encounters.v1", "target_seconds_min": 120, "target_seconds_max": 170},
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var catalog = EncounterCatalogScript.new()
	var report = catalog.load_path()
	suite.assert_true(not report.has_blocking_errors(), "room plan catalog loads")
	var definitions: Array[Dictionary] = M1RoomPlanScript.definitions(catalog, 20260928)
	suite.assert_equal(definitions, EXPECTED, "M1 room definitions are exact")
	suite.assert_equal(definitions.size(), 5, "M1 has exactly five rooms")
	suite.assert_true(definitions.all(func(room): return room["type"] != "event"), "M1 has no event room")
	suite.assert_equal(definitions[3]["type"], "elite", "room four is elite")
	suite.assert_equal(definitions[3]["reward_kind"], "contract", "room four grants a contract")
	suite.assert_equal(definitions[4]["type"], "boss", "room five is boss")
	suite.assert_equal(definitions[4]["reward_kind"], "none", "boss has no post-fight reward")

	definitions[0]["type"] = "changed"
	suite.assert_equal(M1RoomPlanScript.definitions(catalog, 20260928)[0]["type"], "combat", "room plan returns deep copies")

	var director = RunDirectorScript.new()
	director.configure_from_definitions(M1RoomPlanScript.definitions(catalog, 20260928))
	for room_number: int in range(1, 6):
		suite.assert_equal(
			director.room_definition_for(room_number),
			EXPECTED[room_number - 1],
			"director retains room %d definition" % room_number
		)
	var director_definition: Dictionary = director.room_definition_for(1)
	director_definition["type"] = "changed"
	suite.assert_equal(director.room_type_for(1), "combat", "director getters do not expose mutable definitions")
	suite.assert_equal(director.encounter_id_for(4), "m1_room_04_elite", "director exposes the authored encounter id")
	suite.assert_equal(director.room_count(), 5, "director retains the authored room count")
	director.free()

	var legacy_director = RunDirectorScript.new()
	legacy_director.configure_fixed_sequence(5, [2], [3], [4])
	suite.assert_equal(legacy_director.room_type_for(2), "event", "legacy event configuration remains supported")
	suite.assert_equal(legacy_director.room_type_for(3), "elite", "legacy elite configuration remains supported")
	suite.assert_true(legacy_director.should_offer_curse(4), "legacy curse configuration remains supported")
	legacy_director.free()
	suite.finish(get_tree())
