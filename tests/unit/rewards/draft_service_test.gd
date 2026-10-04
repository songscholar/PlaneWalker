extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const DraftServiceScript := preload("res://scripts/rewards/draft_service.gd")
const M1RoomPlanScript := preload("res://scripts/dungeon/m1_room_plan.gd")
const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")

const FIXTURE_PATH := "res://tests/fixtures/content/draft_entries.json"


class FixtureRegistry:
	extends RefCounted

	var entries: Array[Dictionary] = []

	func _init(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.READ)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		for value: Variant in parsed:
			entries.append((value as Dictionary).duplicate(true))

	func get_by_category(category: StringName, availability: StringName = &"") -> Array[Dictionary]:
		var matches: Array[Dictionary] = []
		for entry: Dictionary in entries:
			if str(entry["category"]) != str(category):
				continue
			if not str(availability).is_empty() and not entry["availability"].has(str(availability)):
				continue
			matches.append(entry.duplicate(true))
		return matches

	func get_archetype_profiles(availability: StringName = &"") -> Array[Dictionary]:
		return get_by_category(&"archetype_profile", availability)

	func get_archetype_profile(archetype_id: StringName) -> Dictionary:
		for entry: Dictionary in entries:
			if str(entry.get("category", "")) != "archetype_profile":
				continue
			if str(entry.get("archetype_id", "")) == str(archetype_id):
				return entry.duplicate(true)
		return {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	var service = DraftServiceScript.new()
	var rooms: Array[Dictionary] = M1RoomPlanScript.definitions()
	_test_starter_offer(suite, service, registry, rooms[0])
	_test_reinforcement_offer(suite, service, registry, rooms[1])
	_test_talent_offer(suite, service, registry, rooms[2])
	_test_real_talent_offer(suite, rooms[2])
	_test_launch_talent_offer_character_scope(suite, rooms[2])
	_test_real_m1_pool_build_compatibility(suite, rooms)
	_test_compatible_milestone_candidate_domains(suite)
	_test_contract_offer(suite, service, registry, rooms[3])
	_test_no_boss_reward(suite, service, registry, rooms[4])
	_test_resolution(suite, service, registry, rooms[0])
	_test_canonical_offer_is_not_overwritten(suite, rooms[0])
	_test_forged_offer_identity_is_rejected(suite, rooms[3])
	_test_offer_cache_lifecycle(suite, rooms[0])
	suite.finish(get_tree())


func _test_starter_offer(suite, service, registry, room: Dictionary) -> void:
	var first = service.create_offer(registry, _state(123, 1), room)
	var second = service.create_offer(registry, _state(123, 1), room)
	suite.assert_true(first.ok, "room one starter offer succeeds")
	suite.assert_equal(_option_ids(first.context["offer"]), _option_ids(second.context["offer"]), "same draft inputs are deterministic")
	var offer: Dictionary = first.context["offer"]
	suite.assert_true(SelectionOfferScript.validate(offer).ok, "starter offer satisfies selection contract")
	suite.assert_equal(offer["category"], "item", "starter offer uses item category")
	suite.assert_equal(offer["options"].size(), 3, "starter offer has three options")
	var archetypes := _option_archetypes(service, offer)
	archetypes.sort()
	suite.assert_equal(archetypes, ["accelerated_combo", "freeze_burst", "rewind_echo"], "starter offer covers all three routes")
	suite.assert_true(not _option_ids(offer).has("bow_next"), "NEXT definitions never appear")

	for seed_value: int in range(1000):
		var seeded = service.create_offer(registry, _state(seed_value, 1), room)
		suite.assert_true(seeded.ok, "starter seed %d succeeds" % seed_value)
		var seeded_routes := _option_archetypes(service, seeded.context["offer"])
		seeded_routes.sort()
		suite.assert_equal(seeded_routes, ["accelerated_combo", "freeze_burst", "rewind_echo"], "starter seed %d covers valid routes" % seed_value)


func _test_reinforcement_offer(suite, service, registry, room: Dictionary) -> void:
	var state := _state(456, 2)
	state["build"]["dominant_archetype"] = "freeze_burst"
	state["build"]["items"] = ["utility_guard"]
	var result = service.create_offer(registry, state, room)
	suite.assert_true(result.ok, "reinforcement offer succeeds")
	var offer: Dictionary = result.context["offer"]
	suite.assert_true(SelectionOfferScript.validate(offer).ok, "reinforcement offer satisfies selection contract")
	suite.assert_equal(offer["options"].size(), 3, "reinforcement offer has three options")
	var definitions := _definitions(service, offer)
	suite.assert_equal(definitions.filter(func(entry): return entry["role"] == "payoff" and entry["archetype"] == "freeze_burst").size(), 1, "reinforcement includes dominant payoff")
	suite.assert_equal(definitions.filter(func(entry): return entry["role"] == "starter" and entry["archetype"] != "freeze_burst").size(), 1, "reinforcement includes alternative starter")
	suite.assert_equal(definitions.filter(func(entry): return entry["role"] == "utility").size(), 1, "reinforcement includes utility")
	suite.assert_true(not _option_ids(offer).has("utility_guard"), "owned definitions never appear")


func _test_talent_offer(suite, service, registry, room: Dictionary) -> void:
	var result = service.create_offer(registry, _state(789, 3), room)
	suite.assert_true(result.ok, "talent offer succeeds")
	if not result.ok:
		return
	var offer: Dictionary = result.context["offer"]
	suite.assert_true(SelectionOfferScript.validate(offer).ok, "talent offer satisfies selection contract")
	suite.assert_equal(offer["category"], "talent", "talent offer category is stable")
	suite.assert_equal(offer["options"].size(), 3, "talent offer has three options")
	suite.assert_true(_definitions(service, offer).all(func(entry): return entry["category"] == "talent"), "room three only returns talents")


func _test_real_talent_offer(suite, room: Dictionary) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_manifest("res://data/content_manifest.json")
	suite.assert_true(not report.has_blocking_errors(), "real registry loads for talent drafting")
	var service = DraftServiceScript.new()
	var result = service.create_offer(registry, _state(790, 3), room)
	suite.assert_true(result.ok, "real M1 talent pool creates three choices")
	if not result.ok:
		return
	var definitions := _definitions(service, result.context["offer"])
	suite.assert_equal(definitions.size(), 3, "real talent offer has three definitions")
	for definition: Dictionary in definitions:
		var archetype := str(definition["archetype"])
		suite.assert_true(
			archetype.is_empty() or DraftServiceScript.M1_ARCHETYPES.has(archetype),
			"real talent offer stays inside the M1 archetype domain"
		)


func _test_launch_talent_offer_character_scope(suite, room: Dictionary) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": "res://data/content_packs/base/pack.json", "required": true}],
		"0.4.0-dev",
		&"LAUNCH"
	)
	suite.assert_true(not report.has_blocking_errors(), "real Base Pack loads for Launch talent drafting")
	if report.has_blocking_errors():
		return
	for character_id: String in [
		"wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord",
	]:
		var state := _state(900 + character_id.length(), 3)
		state["config"] = {
			"milestone": "LAUNCH", "character_id": character_id, "weapon_id": "sword",
			"enabled_time_skills": ["stop", "rewind"], "mode": "normal",
		}
		var service = DraftServiceScript.new()
		var result = service.create_offer(registry, state, room)
		suite.assert_true(result.ok, "%s receives a Launch talent offer" % character_id)
		if not result.ok:
			continue
		var definitions := _definitions(service, result.context["offer"])
		suite.assert_equal(definitions.size(), 3, "%s receives exactly its three talents" % character_id)
		for definition: Dictionary in definitions:
			suite.assert_equal(
				definition.get("compatibility", {}).get("character_ids", []),
				[character_id],
				"%s offer excludes cross-character talents" % character_id
			)
	var bow_state := _state(919, 3)
	bow_state["config"] = {
		"milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"], "mode": "normal",
	}
	var bow_service = DraftServiceScript.new()
	var bow_result = bow_service.create_offer(registry, bow_state, room)
	suite.assert_true(bow_result.ok, "Bow receives remaining compatible Wanderer talents")
	if bow_result.ok:
		suite.assert_equal(_definitions(bow_service, bow_result.context["offer"]).size(), 2, "Bow excludes Sword-only execution talent")
		suite.assert_true(not _option_ids(bow_result.context["offer"]).has("tal_ruin_execute"), "unsupported execution effect stays filtered")


func _test_real_m1_pool_build_compatibility(suite, rooms: Array[Dictionary]) -> void:
	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": "res://data/content_packs/base/pack.json", "required": true}],
		"0.4.0-dev",
		&"M1"
	)
	suite.assert_true(not report.has_blocking_errors(), "real Base Pack loads for M1 build compatibility")
	if report.has_blocking_errors():
		return
	var build_state = RunBuildStateScript.new()
	build_state.reset("M1")
	for seed_value: int in range(30):
		var service = DraftServiceScript.new()
		for room_index: int in range(4):
			var state := _state(20260901 + seed_value, room_index + 1)
			state["config"] = {"milestone": "M1"}
			state["build"]["dominant_archetype"] = "freeze_burst"
			var created = service.create_offer(registry, state, rooms[room_index])
			suite.assert_true(created.ok, "M1 seed %d room %d creates an offer" % [seed_value, room_index + 1])
			if not created.ok:
				continue
			for definition: Dictionary in _definitions(service, created.context["offer"]):
				var validation: Dictionary = build_state.validate_definition(definition)
				suite.assert_true(
					bool(validation.get("ok", false)),
					"M1 seed %d room %d definition %s fits the authoritative build domain" % [
						seed_value,
						room_index + 1,
						str(definition.get("id", "")),
					]
				)


func _test_compatible_milestone_candidate_domains(suite) -> void:
	var service = DraftServiceScript.new()
	for milestone: String in ["CURRENT", "NEXT"]:
		var candidates: Array[Dictionary] = []
		for archetype: String in DraftServiceScript.M1_ARCHETYPES + ["perfect_guard", "piercing_barrage"]:
			candidates.append({
				"id": "%s_%s" % [milestone.to_lower(), archetype],
				"availability": [milestone],
				"archetype": archetype,
			})
		candidates.append({
			"id": "%s_utility" % milestone.to_lower(),
			"availability": [milestone],
			"archetype": "",
		})
		var filtered: Array[Dictionary] = service.call(
			"_filter_candidates",
			candidates,
			{},
			milestone
		)
		suite.assert_equal(filtered.size(), 4, "%s keeps three M1 routes plus utility" % milestone)
		for definition: Dictionary in filtered:
			var archetype := str(definition.get("archetype", ""))
			suite.assert_true(
				archetype.is_empty() or DraftServiceScript.M1_ARCHETYPES.has(archetype),
				"%s candidate filtering rejects Launch-only archetypes" % milestone
			)


func _test_contract_offer(suite, service, registry, room: Dictionary) -> void:
	var result = service.create_offer(registry, _state(987, 4), room)
	suite.assert_true(result.ok, "contract offer succeeds")
	var offer: Dictionary = result.context["offer"]
	suite.assert_true(SelectionOfferScript.validate(offer).ok, "contract offer satisfies selection contract")
	suite.assert_equal(offer["category"], "contract", "contract offer category is stable")
	suite.assert_equal(offer["options"].size(), 3, "contract offer has two risks and decline")
	suite.assert_equal(_definitions(service, offer).filter(func(entry): return entry["category"] == "curse").size(), 2, "contract offer contains two curses")
	suite.assert_true(_option_ids(offer).has("decline_contract"), "contract offer contains safe decline")


func _test_no_boss_reward(suite, service, registry, room: Dictionary) -> void:
	var result = service.create_offer(registry, _state(999, 5), room)
	suite.assert_true(not result.ok, "boss reward is rejected")
	suite.assert_equal(result.code, &"INVALID_ARGUMENT", "boss reward uses invalid argument code")


func _test_resolution(suite, service, registry, room: Dictionary) -> void:
	var created = service.create_offer(registry, _state(321, 1), room)
	var offer: Dictionary = created.context["offer"]
	var missing = service.resolve_option(offer, &"missing")
	suite.assert_equal(missing.code, &"OPTION_NOT_FOUND", "missing option is rejected")
	var option_id := StringName(str(offer["options"][0]["option_id"]))
	suite.assert_true(not offer["options"][0].has("definition"), "public offer excludes gameplay definitions")
	var forged_offer := offer.duplicate(true)
	forged_offer["options"][0]["definition"] = {"effects": {"attack_multiplier": 999.0}}
	var resolved = service.resolve_option(offer, option_id)
	suite.assert_true(resolved.ok, "valid option resolves")
	var selected: Dictionary = resolved.context["definition"]
	var original_name := str(selected["name_key"])
	selected["name_key"] = "CHANGED"
	var forged_result = service.resolve_option(forged_offer, option_id)
	suite.assert_true(forged_result.ok, "extra UI fields do not change cached resolution")
	suite.assert_equal(forged_result.context["definition"]["name_key"], original_name, "resolved definition ignores forged UI payload")


func _test_canonical_offer_is_not_overwritten(suite, room: Dictionary) -> void:
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	var service = DraftServiceScript.new()
	var state := _state(654, 1)
	var first = service.create_offer(registry, state, room)
	suite.assert_true(first.ok, "canonical offer is created")
	var first_offer: Dictionary = first.context["offer"]
	var option_id := str(first_offer["options"][0]["option_id"])
	var first_definition: Dictionary = service.resolve_option(first_offer, StringName(option_id)).context["definition"]

	for entry: Dictionary in registry.entries:
		if str(entry["id"]) == option_id:
			entry["name_key"] = "MUTATED_AFTER_OFFER"
			entry["effects"] = {"attack_multiplier": 999.0}

	var repeated = service.create_offer(registry, state, room)
	suite.assert_true(repeated.ok, "repeated open offer request returns canonical offer")
	suite.assert_equal(repeated.context["offer"], first_offer, "same offer id cannot be overwritten")
	var repeated_definition: Dictionary = service.resolve_option(first_offer, StringName(option_id)).context["definition"]
	suite.assert_equal(repeated_definition, first_definition, "old public offer resolves to its original definition")


func _test_forged_offer_identity_is_rejected(suite, room: Dictionary) -> void:
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	var service = DraftServiceScript.new()
	var created = service.create_offer(registry, _state(777, 4), room)
	suite.assert_true(created.ok, "contract offer for identity test is created")
	var offer: Dictionary = created.context["offer"]
	var option_id := StringName(str(offer["options"][0]["option_id"]))

	var wrong_category := offer.duplicate(true)
	wrong_category["category"] = "talent"
	suite.assert_true(SelectionOfferScript.validate(wrong_category).ok, "forged category remains structurally valid")
	var category_result = service.resolve_option(wrong_category, option_id)
	suite.assert_equal(category_result.code, &"INVALID_ARGUMENT", "resolver rejects non-canonical category")

	var wrong_revision := offer.duplicate(true)
	wrong_revision["revision"] = int(offer["revision"]) + 1
	suite.assert_true(SelectionOfferScript.validate(wrong_revision).ok, "forged revision remains structurally valid")
	var revision_result = service.resolve_option(wrong_revision, option_id)
	suite.assert_equal(revision_result.code, &"STALE_REVISION", "resolver rejects non-canonical revision")


func _test_offer_cache_lifecycle(suite, room: Dictionary) -> void:
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	var service = DraftServiceScript.new()
	var state := _state(888, 1)
	var created = service.create_offer(registry, state, room)
	var offer: Dictionary = created.context["offer"]
	var offer_id := str(offer["offer_id"])
	var option_id := StringName(str(offer["options"][0]["option_id"]))
	suite.assert_true(service.close_offer(offer_id), "open offer can be closed")
	suite.assert_equal(service.resolve_option(offer, option_id).code, &"OFFER_CLOSED", "closed offer cannot resolve")
	suite.assert_equal(service.create_offer(registry, state, room).code, &"OFFER_CLOSED", "closed offer id cannot reopen")
	service.reset()
	suite.assert_true(service.create_offer(registry, state, room).ok, "run reset clears offer lifecycle state")


func _state(seed_value: int, room_index: int) -> Dictionary:
	return {
		"run_id": "run-%d" % seed_value,
		"revision": room_index,
		"run_seed": seed_value,
		"current_room": room_index,
		"build": {
			"items": [],
			"blessings": [],
			"curses": [],
			"talents": [],
			"dominant_archetype": "time_stop_burst",
		},
	}


func _option_ids(offer: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for option: Dictionary in offer["options"]:
		ids.append(str(option["option_id"]))
	return ids


func _option_archetypes(service, offer: Dictionary) -> Array[String]:
	var archetypes: Array[String] = []
	for option: Dictionary in offer["options"]:
		var resolved = service.resolve_option(offer, StringName(str(option["option_id"])))
		archetypes.append(str(resolved.context["definition"].get("archetype", "")))
	return archetypes


func _definitions(service, offer: Dictionary) -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for option: Dictionary in offer["options"]:
		var resolved = service.resolve_option(offer, StringName(str(option["option_id"])))
		definitions.append(resolved.context["definition"])
	return definitions
