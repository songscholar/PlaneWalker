extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const M1RoomPlanScript := preload("res://scripts/dungeon/m1_room_plan.gd")
const RunDirectorScript := preload("res://scripts/dungeon/run_director.gd")

const EXPECTED := [
	{"room_number": 1, "type": "combat", "reward_kind": "starter", "target_seconds_min": 45, "target_seconds_max": 70},
	{"room_number": 2, "type": "combat", "reward_kind": "reinforcement", "target_seconds_min": 60, "target_seconds_max": 85},
	{"room_number": 3, "type": "combat", "reward_kind": "talent", "target_seconds_min": 70, "target_seconds_max": 100},
	{"room_number": 4, "type": "elite", "reward_kind": "contract", "target_seconds_min": 90, "target_seconds_max": 125},
	{"room_number": 5, "type": "boss", "reward_kind": "none", "target_seconds_min": 120, "target_seconds_max": 170},
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var definitions: Array[Dictionary] = M1RoomPlanScript.definitions()
	suite.assert_equal(definitions, EXPECTED, "M1 room definitions are exact")
	suite.assert_equal(definitions.size(), 5, "M1 has exactly five rooms")
	suite.assert_true(definitions.all(func(room): return room["type"] != "event"), "M1 has no event room")
	suite.assert_equal(definitions[3]["type"], "elite", "room four is elite")
	suite.assert_equal(definitions[3]["reward_kind"], "contract", "room four grants a contract")
	suite.assert_equal(definitions[4]["type"], "boss", "room five is boss")
	suite.assert_equal(definitions[4]["reward_kind"], "none", "boss has no post-fight reward")

	definitions[0]["type"] = "changed"
	suite.assert_equal(M1RoomPlanScript.definitions()[0]["type"], "combat", "room plan returns deep copies")

	var director = RunDirectorScript.new()
	director.configure_from_definitions(M1RoomPlanScript.definitions())
	for room_number: int in range(1, 6):
		suite.assert_equal(
			director.room_definition_for(room_number),
			EXPECTED[room_number - 1],
			"director retains room %d definition" % room_number
		)
	var director_definition: Dictionary = director.room_definition_for(1)
	director_definition["type"] = "changed"
	suite.assert_equal(director.room_type_for(1), "combat", "director getters do not expose mutable definitions")
	director.free()

	var legacy_director = RunDirectorScript.new()
	legacy_director.configure_fixed_sequence(5, [2], [3], [4])
	suite.assert_equal(legacy_director.room_type_for(2), "event", "legacy event configuration remains supported")
	suite.assert_equal(legacy_director.room_type_for(3), "elite", "legacy elite configuration remains supported")
	suite.assert_true(legacy_director.should_offer_curse(4), "legacy curse configuration remains supported")
	legacy_director.free()
	suite.finish(get_tree())
