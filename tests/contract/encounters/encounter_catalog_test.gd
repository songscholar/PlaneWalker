extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const EncounterCatalogScript := preload("res://scripts/dungeon/encounter_catalog.gd")

const CATALOG_PATH := "res://data/encounters/m1_encounters.json"
const FIXED_SEED := 20260928


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_authoritative_catalog(suite)
	_test_deterministic_resolution(suite)
	_test_invalid_references_are_rejected(suite)
	suite.finish(get_tree())


func _test_authoritative_catalog(suite) -> void:
	var catalog = EncounterCatalogScript.new()
	var report = catalog.load_path(CATALOG_PATH)
	suite.assert_true(not report.has_blocking_errors(), "M1 encounter catalog validates")
	suite.assert_equal(catalog.plan_id(), "m1.encounters.v1", "catalog exposes a stable plan id")

	var rooms: Array[Dictionary] = catalog.room_definitions(FIXED_SEED)
	suite.assert_equal(rooms.size(), 5, "catalog defines exactly five M1 rooms")
	suite.assert_equal(
		rooms.map(func(room: Dictionary): return room["encounter_id"]),
		["m1_room_01", "m1_room_02", "m1_room_03", "m1_room_04_elite", "m1_room_05_boss"],
		"every room has one unique authored encounter"
	)
	for room_index: int in range(3):
		suite.assert_equal(rooms[room_index]["type"], "combat", "room %d is a normal encounter" % (room_index + 1))
	suite.assert_equal(rooms[3]["type"], "elite", "room four is the authored elite encounter")
	suite.assert_equal(rooms[4]["type"], "boss", "room five is the authored boss encounter")

	var elite := catalog.encounter_definition("m1_room_04_elite", FIXED_SEED, 4)
	var elite_spawns := _all_spawns(elite)
	suite.assert_equal(elite_spawns.size(), 1, "elite room contains exactly one actor")
	suite.assert_equal(elite_spawns[0]["enemy_id"], "tank", "elite room actor is a Tank")
	suite.assert_equal(elite_spawns[0]["mechanism_ids"], ["overload_pulse"], "elite Tank declares overload pulse")

	var boss := catalog.encounter_definition("m1_room_05_boss", FIXED_SEED, 5)
	var boss_spawns := _all_spawns(boss)
	suite.assert_equal(boss_spawns.size(), 1, "boss room contains exactly one authored actor")
	suite.assert_equal(boss_spawns[0]["enemy_id"], "chrono_warden", "room five actor is Chrono Warden")

	rooms[0]["type"] = "changed"
	elite["waves"][0]["spawns"][0]["enemy_id"] = "changed"
	suite.assert_equal(catalog.room_definitions(FIXED_SEED)[0]["type"], "combat", "room definitions are deep copies")
	suite.assert_equal(
		catalog.encounter_definition("m1_room_04_elite", FIXED_SEED, 4)["waves"][0]["spawns"][0]["enemy_id"],
		"tank",
		"encounter definitions are deep copies"
	)


func _test_deterministic_resolution(suite) -> void:
	var catalog = EncounterCatalogScript.new()
	catalog.load_path(CATALOG_PATH)
	var first: Array[Dictionary] = catalog.room_definitions(FIXED_SEED)
	var second: Array[Dictionary] = catalog.room_definitions(FIXED_SEED)
	suite.assert_equal(second, first, "same catalog version and seed reproduce the room plan")
	for room: Dictionary in first:
		var room_number := int(room["room_number"])
		var encounter_id := str(room["encounter_id"])
		suite.assert_equal(
			catalog.encounter_definition(encounter_id, FIXED_SEED, room_number),
			catalog.encounter_definition(encounter_id, FIXED_SEED, room_number),
			"room %d reproduces enemy and slot choices" % room_number
		)


func _test_invalid_references_are_rejected(suite) -> void:
	var cases: Array[Dictionary] = [
		{"label": "duplicate encounter id", "mutation": "duplicate_encounter"},
		{"label": "missing encounter id", "mutation": "missing_encounter"},
		{"label": "unknown enemy id", "mutation": "unknown_enemy"},
		{"label": "unknown spawn slot id", "mutation": "unknown_slot"},
		{"label": "unknown mechanism id", "mutation": "unknown_mechanism"},
	]
	for case: Dictionary in cases:
		var data := _valid_minimal_data()
		_apply_mutation(data, str(case["mutation"]))
		var catalog = EncounterCatalogScript.new()
		var report = catalog.load_data(data, "test:%s" % str(case["mutation"]))
		suite.assert_true(report.has_blocking_errors(), "%s is rejected" % str(case["label"]))


func _valid_minimal_data() -> Dictionary:
	var rooms: Array[Dictionary] = []
	var encounters: Array[Dictionary] = []
	for room_number: int in range(1, 6):
		var encounter_id := "test_room_%02d" % room_number
		var room_type := "combat"
		var enemy_id := "chaser"
		var mechanism_ids: Array[String] = []
		if room_number == 4:
			room_type = "elite"
			enemy_id = "tank"
			mechanism_ids = ["overload_pulse"]
		elif room_number == 5:
			room_type = "boss"
			enemy_id = "chrono_warden"
		rooms.append({
			"room_number": room_number,
			"type": room_type,
			"reward_kind": "none" if room_number == 5 else "starter",
			"encounter_id": encounter_id,
		})
		encounters.append({
			"id": encounter_id,
			"target_seconds_min": 10,
			"target_seconds_max": 20,
			"waves": [{
				"id": "%s_wave_01" % encounter_id,
				"delay_seconds": 0.0,
				"telegraph_seconds": 0.0,
				"spawns": [{
					"id": "%s_spawn_01" % encounter_id,
					"enemy_id": enemy_id,
					"spawn_slot_id": "boss" if room_number == 5 else "slot_a",
					"mechanism_ids": mechanism_ids,
				}],
			}],
		})
	return {
		"schema_version": 1,
		"plan_id": "test.encounters.v1",
		"mechanism_ids": ["overload_pulse"],
		"enemy_definitions": [
			{"id": "chaser", "scene": "res://scenes/enemies/enemy_chaser.tscn", "allowed_mechanism_ids": []},
			{"id": "tank", "scene": "res://scenes/enemies/enemy_tank.tscn", "allowed_mechanism_ids": ["overload_pulse"]},
			{"id": "chrono_warden", "scene": "res://scenes/enemies/boss_chrono_warden.tscn", "allowed_mechanism_ids": []},
		],
		"spawn_slots": [
			{"id": "slot_a", "node_path": "SpawnPoints/SpawnPoint1"},
			{"id": "boss", "node_path": "BossSpawnPoint"},
		],
		"rooms": rooms,
		"encounters": encounters,
	}


func _apply_mutation(data: Dictionary, mutation: String) -> void:
	match mutation:
		"duplicate_encounter":
			data["encounters"].append(data["encounters"][0].duplicate(true))
		"missing_encounter":
			data["rooms"][0]["encounter_id"] = "missing"
		"unknown_enemy":
			data["encounters"][0]["waves"][0]["spawns"][0]["enemy_id"] = "missing"
		"unknown_slot":
			data["encounters"][0]["waves"][0]["spawns"][0]["spawn_slot_id"] = "missing"
		"unknown_mechanism":
			data["encounters"][3]["waves"][0]["spawns"][0]["mechanism_ids"] = ["missing"]


func _all_spawns(encounter: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for wave: Dictionary in encounter.get("waves", []):
		for spawn: Dictionary in wave.get("spawns", []):
			result.append(spawn)
	return result
