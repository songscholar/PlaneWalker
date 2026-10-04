extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")


func _ready() -> void:
	var suite := Suite.new()
	var implementation := load("res://scripts/progression/build_library.gd") as Script
	suite.assert_true(implementation != null, "authoritative BuildLibrary exists")
	if implementation != null:
		var catalog := Fixtures.catalog()
		var runtime: RefCounted = implementation.new()
		suite.assert_true(runtime.configure(catalog), "build library configures")
		var profile := Fixtures.profile(catalog)
		suite.assert_true(not runtime.resolve({}, "loadout").ok, "empty profile resolve refuses without script error")
		var time_ids := ["stop", "rewind", "accelerate", "rift"]
		var combinations := 0
		for character_id: String in profile.unlocked_characters:
			for weapon_id: String in profile.unlocked_weapons:
				for first: int in range(4):
					for second: int in range(first + 1, 4):
						var build := {"id": "loadout", "name": "Practice", "character_id": character_id, "weapon_id": weapon_id, "time_abilities": [time_ids[first], time_ids[second]]}
						var before := profile.duplicate(true)
						var command := {"command_id": "save-" + str(combinations), "kind": "build_save", "build": build}
						var result: Dictionary = runtime.prepare_command(profile, command, profile.revision)
						suite.assert_true(result.ok, "each of 150 canonical loadouts stores")
						if result.ok:
							suite.assert_equal(profile, before, "build preparation isolates caller")
							profile = result.context.candidate
							suite.assert_equal(profile.build_library.size(), 1, "same build ID replaces one slot")
							suite.assert_true(runtime.resolve(profile, "loadout").ok, "saved canonical build resolves")
						combinations += 1
		suite.assert_equal(combinations, 150, "complete 150-loadout matrix exercised")
		for index: int in range(31):
			var build: Dictionary = profile.build_library[0].duplicate(true)
			build.id = "preset-" + str(index)
			var result: Dictionary = runtime.prepare_command(profile, {"command_id": "slot-" + str(index), "kind": "build_save", "build": build}, profile.revision)
			suite.assert_true(result.ok, "up to thirty-two slots save")
			if result.ok:
				profile = result.context.candidate
		var extra: Dictionary = profile.build_library[0].duplicate(true)
		extra.id = "overflow"
		suite.assert_true(not runtime.prepare_command(profile, {"command_id": "overflow", "kind": "build_save", "build": extra}, profile.revision).ok, "thirty-third slot refuses")
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(profile))
		suite.assert_equal(runtime.resolve(parsed, "loadout"), runtime.resolve(profile, "loadout"), "JSON restores legal loadout")
		var removed: Dictionary = runtime.prepare_command(profile, {"command_id": "remove", "kind": "build_remove", "build_id": "loadout"}, profile.revision)
		suite.assert_true(removed.ok, "build removes through candidate")
		if removed.ok:
			suite.assert_equal(removed.context.candidate.build_library.size(), 31, "remove frees exactly one slot")
			suite.assert_true(not runtime.resolve(removed.context.candidate, "loadout").ok, "deleted ID never resolves")
		var locked := Fixtures.profile(catalog, false)
		var build := {"id": "locked", "name": "Locked", "character_id": "time_lord", "weapon_id": "staff", "time_abilities": ["stop", "rift"]}
		suite.assert_true(not runtime.prepare_command(locked, {"command_id": "locked", "kind": "build_save", "build": build}, 0).ok, "production selection enforces character and weapon unlocks")
		build.character_id = "wanderer"
		build.weapon_id = "sword"
		build.time_abilities = ["stop", "stop"]
		suite.assert_true(not runtime.prepare_command(locked, {"command_id": "invalid", "kind": "build_save", "build": build}, 0).ok, "duplicate time pair refuses")
		build.time_abilities = ["stop", "unknown"]
		suite.assert_true(not runtime.prepare_command(locked, {"command_id": "unknown", "kind": "build_save", "build": build}, 0).ok, "unknown time ID refuses")
	suite.finish(get_tree())
