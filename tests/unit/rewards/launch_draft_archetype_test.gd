extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const DraftServiceScript := preload("res://scripts/rewards/draft_service.gd")
const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")
const ArchetypeProfileScript := preload("res://scripts/progression/archetype_profile.gd")

const FIXTURE_PATH := "res://tests/fixtures/content/draft_entries.json"
const CANONICAL_SEED_FIRST := 20260901
const CANONICAL_SEED_LAST := 20260930


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
			if str(entry.get("category", "")) != str(category):
				continue
			if not str(availability).is_empty() and not entry.get("availability", []).has(str(availability)):
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

	func remove_entry(content_id: String) -> void:
		entries = entries.filter(
			func(entry: Dictionary) -> bool:
				return str(entry.get("id", "")) != content_id
		)

	func set_all_profile_availability(milestones: Array[String]) -> void:
		for entry: Dictionary in entries:
			if str(entry.get("category", "")) == "archetype_profile":
				entry["availability"] = milestones.duplicate()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_fixture_coverage(suite)
	_test_launch_starter_seeds(suite)
	_test_launch_reinforcement_routes(suite)
	_test_invalid_milestone_and_dominant(suite)
	_test_unavailable_profiles(suite)
	_test_insufficient_route_coverage(suite)
	_test_owned_content_exhaustion(suite)
	_test_cached_offer_identity(suite)
	suite.finish(get_tree())


func _test_fixture_coverage(suite) -> void:
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	var profiles := registry.get_archetype_profiles(&"LAUNCH")
	var profile_ids: Array[String] = []
	for profile: Dictionary in profiles:
		profile_ids.append(str(profile.get("archetype_id", "")))
	suite.assert_equal(profile_ids, ArchetypeProfileScript.ARCHETYPE_IDS, "fixture exposes the exact ordered Launch taxonomy")
	for archetype: String in ArchetypeProfileScript.ARCHETYPE_IDS:
		var launch_entries: Array[Dictionary] = []
		for category: StringName in [&"item", &"blessing", &"curse"]:
			launch_entries.append_array(registry.get_by_category(category, &"LAUNCH"))
		var route: Array[Dictionary] = launch_entries.filter(
			func(entry: Dictionary) -> bool:
				return str(entry.get("archetype", "")) == archetype
		)
		suite.assert_equal(
			route.filter(func(entry: Dictionary) -> bool: return str(entry.get("role", "")) == "starter").size(),
			3,
			"%s fixture has three starters" % archetype
		)
		suite.assert_equal(
			route.filter(func(entry: Dictionary) -> bool: return str(entry.get("role", "")) == "payoff").size(),
			2,
			"%s fixture has two payoffs" % archetype
		)
		suite.assert_equal(
			route.filter(func(entry: Dictionary) -> bool: return str(entry.get("role", "")) == "risk").size(),
			1,
			"%s fixture has one risk" % archetype
		)


func _test_launch_starter_seeds(suite) -> void:
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	var service = DraftServiceScript.new()
	var observed: Dictionary = {}
	for seed_value: int in range(CANONICAL_SEED_FIRST, CANONICAL_SEED_LAST + 1):
		var state := _state(seed_value, 1, "LAUNCH")
		var result = service.create_offer(registry, state, _starter_room())
		suite.assert_true(result.ok, "Launch starter seed %d succeeds" % seed_value)
		if not result.ok:
			continue
		var offer: Dictionary = result.context["offer"]
		suite.assert_true(SelectionOfferScript.validate(offer).ok, "Launch starter seed %d validates" % seed_value)
		suite.assert_equal(offer.get("options", []).size(), 3, "Launch choice load remains three")
		var definitions := _definitions(service, offer)
		suite.assert_equal(definitions.size(), 3, "Launch starter seed %d resolves three definitions" % seed_value)
		for definition: Dictionary in definitions:
			var archetype := str(definition.get("archetype", ""))
			suite.assert_true(ArchetypeProfileScript.ARCHETYPE_IDS.has(archetype), "Launch starter uses an authoritative archetype")
			suite.assert_equal(definition.get("role"), "starter", "Launch starter room only offers starters")
			suite.assert_true(definition.get("availability", []).has("LAUNCH"), "Launch starter never leaks an M1-only definition")
			observed[archetype] = true
		var repeated = service.create_offer(registry, state, _starter_room())
		suite.assert_true(repeated.ok, "repeated Launch starter seed %d succeeds" % seed_value)
		if repeated.ok:
			suite.assert_equal(repeated.context["offer"], offer, "Launch starter seed %d is deterministic" % seed_value)
	var observed_ids: Array[String] = []
	for archetype: String in ArchetypeProfileScript.ARCHETYPE_IDS:
		if observed.has(archetype):
			observed_ids.append(archetype)
	suite.assert_equal(observed_ids, ArchetypeProfileScript.ARCHETYPE_IDS, "thirty canonical seeds expose all eight starter routes")


func _test_launch_reinforcement_routes(suite) -> void:
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	for index: int in range(ArchetypeProfileScript.ARCHETYPE_IDS.size()):
		var archetype: String = ArchetypeProfileScript.ARCHETYPE_IDS[index]
		var service = DraftServiceScript.new()
		var state := _state(CANONICAL_SEED_FIRST + index, 2, "LAUNCH")
		state["build"]["dominant_archetype"] = archetype
		var result = service.create_offer(registry, state, _reinforcement_room())
		suite.assert_true(result.ok, "%s Launch reinforcement succeeds" % archetype)
		if not result.ok:
			continue
		var offer: Dictionary = result.context["offer"]
		suite.assert_equal(offer.get("options", []).size(), 3, "%s reinforcement remains bounded" % archetype)
		var definitions := _definitions(service, offer)
		suite.assert_true(
			definitions.all(func(entry: Dictionary) -> bool: return entry.get("availability", []).has("LAUNCH")),
			"%s reinforcement never leaks another milestone" % archetype
		)
		suite.assert_equal(
			definitions.filter(
				func(entry: Dictionary) -> bool: return str(entry.get("role", "")) == "payoff" and str(entry.get("archetype", "")) == archetype
			).size(),
			1,
			"%s reinforcement contains one dominant payoff" % archetype
		)
		suite.assert_equal(
			definitions.filter(
				func(entry: Dictionary) -> bool: return str(entry.get("role", "")) == "starter" and str(entry.get("archetype", "")) != archetype
			).size(),
			1,
			"%s reinforcement contains one pivot starter" % archetype
		)
		suite.assert_equal(
			definitions.filter(
				func(entry: Dictionary) -> bool: return str(entry.get("role", "")) == "utility" or str(entry.get("archetype", "")).is_empty()
			).size(),
			1,
			"%s reinforcement contains one utility or safety option" % archetype
		)


func _test_invalid_milestone_and_dominant(suite) -> void:
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	var unknown_milestone = DraftServiceScript.new().create_offer(
		registry,
		_state(20261001, 1, "BETA"),
		_starter_room()
	)
	suite.assert_true(not unknown_milestone.ok, "unknown draft milestone fails closed")
	suite.assert_equal(unknown_milestone.code, &"INVALID_ARGUMENT", "unknown milestone uses invalid argument")
	suite.assert_equal(unknown_milestone.context.get("field"), "milestone", "unknown milestone identifies its field")

	var unknown_state := _state(20261002, 2, "LAUNCH")
	unknown_state["build"]["dominant_archetype"] = "heavy_cleave"
	var unknown_dominant = DraftServiceScript.new().create_offer(
		registry,
		unknown_state,
		_reinforcement_room()
	)
	suite.assert_true(not unknown_dominant.ok, "unknown dominant archetype fails closed")
	suite.assert_equal(unknown_dominant.code, &"INVALID_ARGUMENT", "unknown dominant archetype uses invalid argument")
	suite.assert_equal(
		unknown_dominant.context.get("field"),
		"dominant_archetype",
		"unknown dominant archetype identifies its field"
	)


func _test_unavailable_profiles(suite) -> void:
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	registry.set_all_profile_availability(["EXPANSION"])
	var service = DraftServiceScript.new()
	var result = service.create_offer(registry, _state(20261003, 1, "LAUNCH"), _starter_room())
	suite.assert_true(not result.ok, "Launch draft fails when no profile is available")
	suite.assert_equal(result.code, &"CONTENT_NOT_AVAILABLE", "unavailable profiles use the content error")
	suite.assert_equal(_offer_cache_size(service), 0, "unavailable profiles cannot create a cached offer")


func _test_insufficient_route_coverage(suite) -> void:
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	registry.remove_entry("echo_legion_starter_3")
	var service = DraftServiceScript.new()
	var result = service.create_offer(registry, _state(20261004, 1, "LAUNCH"), _starter_room())
	suite.assert_true(not result.ok, "Launch draft fails when one route misses its declared starter coverage")
	suite.assert_equal(result.code, &"CONTENT_NOT_AVAILABLE", "insufficient route coverage uses the content error")
	suite.assert_equal(_offer_cache_size(service), 0, "coverage failure cannot create a cached offer")


func _test_owned_content_exhaustion(suite) -> void:
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	var owned_starters: Array[String] = []
	for entry: Dictionary in registry.get_by_category(&"item"):
		if str(entry.get("role", "")) == "starter":
			owned_starters.append(str(entry.get("id", "")))
	var state := _state(20261005, 1, "LAUNCH")
	state["build"]["items"] = owned_starters
	var service = DraftServiceScript.new()
	var result = service.create_offer(registry, state, _starter_room())
	suite.assert_true(not result.ok, "owned-content exhaustion fails closed")
	suite.assert_equal(result.code, &"CONTENT_NOT_AVAILABLE", "owned-content exhaustion uses the content error")
	suite.assert_equal(_offer_cache_size(service), 0, "owned-content exhaustion cannot create a cached offer")


func _test_cached_offer_identity(suite) -> void:
	var registry = FixtureRegistry.new(FIXTURE_PATH)
	var service = DraftServiceScript.new()
	var launch_state := _state(20261006, 1, "LAUNCH", "cache-identity-run")
	var created = service.create_offer(registry, launch_state, _starter_room())
	suite.assert_true(created.ok, "canonical Launch offer exists before cache identity test")
	if not created.ok:
		return
	var launch_offer: Dictionary = created.context["offer"]
	var m1_state := _state(20261006, 1, "M1", "cache-identity-run")
	var mismatch = service.create_offer(registry, m1_state, _starter_room())
	suite.assert_true(not mismatch.ok, "same offer id cannot reuse a cache record from another milestone")
	suite.assert_equal(mismatch.code, &"INVALID_ARGUMENT", "cache identity mismatch uses invalid argument")
	suite.assert_equal(mismatch.context.get("field"), "offer_identity", "cache mismatch identifies canonical identity")
	suite.assert_equal(_offer_cache_size(service), 1, "cache mismatch preserves the original canonical record")
	var first_option := StringName(str(launch_offer["options"][0]["option_id"]))
	suite.assert_true(service.resolve_option(launch_offer, first_option).ok, "cache mismatch cannot corrupt original resolution")
	var repeated = service.create_offer(registry, launch_state, _starter_room())
	suite.assert_true(repeated.ok, "canonical Launch identity remains reusable")
	if repeated.ok:
		suite.assert_equal(repeated.context["offer"], launch_offer, "canonical Launch cache remains unchanged")


func _state(
	seed_value: int,
	room_index: int,
	milestone: String,
	run_id: String = ""
) -> Dictionary:
	return {
		"run_id": run_id if not run_id.is_empty() else "launch-%s-%d" % [milestone.to_lower(), seed_value],
		"revision": room_index,
		"run_seed": seed_value,
		"current_room": room_index,
		"config": {"milestone": milestone},
		"build": {
			"items": [],
			"blessings": [],
			"curses": [],
			"talents": [],
			"dominant_archetype": "freeze_burst",
		},
	}


func _starter_room() -> Dictionary:
	return {"room_number": 1, "reward_kind": "starter"}


func _reinforcement_room() -> Dictionary:
	return {"room_number": 2, "reward_kind": "reinforcement"}


func _definitions(service, offer: Dictionary) -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for option: Dictionary in offer.get("options", []):
		var resolved = service.resolve_option(offer, StringName(str(option.get("option_id", ""))))
		if resolved.ok:
			definitions.append((resolved.context["definition"] as Dictionary).duplicate(true))
	return definitions


func _offer_cache_size(service) -> int:
	var records: Variant = service.get("_offer_records")
	return (records as Dictionary).size() if records is Dictionary else -1
