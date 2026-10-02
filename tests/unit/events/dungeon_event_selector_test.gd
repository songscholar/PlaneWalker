extends Node

const DungeonEventSelectorScript := preload(
	"res://scripts/events/dungeon_event_selector.gd"
)
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const EVENTS_PATH := "res://data/content_packs/base/content/dungeon_events.json"
const EXPECTED_EVENT_IDS: Array[String] = [
	"event_chronal_altar",
	"event_trapped_traveler",
	"event_cursed_pool",
	"event_smiths_legacy",
	"event_memory_mirror",
	"event_planar_merchant",
	"event_void_rift",
	"event_sleeping_guardian",
	"event_twisted_well",
	"event_soul_contract",
	"event_time_paradox",
	"event_sacrificial_altar",
	"event_lost_journal",
	"event_rift_garden",
	"event_final_choice",
	"event_void_whispers",
	"event_perfect_rewind",
	"event_old_reunion",
]
const SPECIAL_PRIORITY: Array[String] = [
	"event_void_whispers",
	"event_perfect_rewind",
	"event_old_reunion",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var definitions := _read_events()
	suite.assert_equal(_event_ids(definitions), EXPECTED_EVENT_IDS, "fixture exposes exact event catalog")
	if definitions.size() == EXPECTED_EVENT_IDS.size():
		_test_all_authored_events_have_eligible_and_ineligible_states(suite, definitions)
		_test_runtime_floor_index_contract(suite, definitions)
		_test_floor_and_availability_filters(suite, definitions)
		_test_repeat_policies(suite, definitions)
		_test_all_eight_predicates(suite)
		_test_nested_authorities_ignore_stale_aliases(suite)
		_test_special_priority(suite, definitions)
		_test_weighted_regular_selection(suite)
		_test_primary_candidate_ordering(suite)
		_test_byte_equality_and_channel_isolation(suite)
		_test_no_eligible_event_and_input_immutability(suite, definitions)
	suite.finish(get_tree())


func _test_all_authored_events_have_eligible_and_ineligible_states(
	suite,
	definitions: Array[Dictionary]
) -> void:
	var selector = DungeonEventSelectorScript.new()
	for definition: Dictionary in definitions:
		var event_id := str(definition["id"])
		var eligible_context := _eligible_context(definition)
		var eligible: Dictionary = selector.select([definition], eligible_context)
		suite.assert_true(bool(eligible.get("ok", false)), "%s has an eligible authored state" % event_id)
		suite.assert_equal(eligible.get("event_id"), event_id, "%s selects itself when solely eligible" % event_id)
		suite.assert_equal(eligible.get("eligible_ids"), [event_id], "%s appears in eligible facts" % event_id)

		var ineligible_context := eligible_context.duplicate(true)
		ineligible_context["floor_index"] = -1
		var ineligible: Dictionary = selector.select([definition], ineligible_context)
		suite.assert_true(not bool(ineligible.get("ok", true)), "%s has an ineligible authored state" % event_id)
		suite.assert_equal(ineligible.get("code"), &"NO_ELIGIBLE_EVENT", "%s rejects outside floor bounds" % event_id)


func _test_runtime_floor_index_contract(suite, definitions: Array[Dictionary]) -> void:
	var selector = DungeonEventSelectorScript.new()
	var first_floor := _definition_by_id(definitions, "event_chronal_altar")
	var first_context := _eligible_context(first_floor)
	first_context["floor_index"] = 0
	suite.assert_equal(
		selector.select([first_floor], first_context).get("event_id"),
		"event_chronal_altar",
		"runtime floor index zero maps to authored floor one"
	)

	var final_choice := _definition_by_id(definitions, "event_final_choice")
	var final_context := _eligible_context(final_choice)
	final_context["floor_index"] = 4
	suite.assert_equal(
		selector.select([final_choice], final_context).get("event_id"),
		"event_final_choice",
		"runtime floor index four maps to authored floor five"
	)

	for invalid_index: int in [-1, 5]:
		var invalid_context := first_context.duplicate(true)
		invalid_context["floor_index"] = invalid_index
		suite.assert_equal(
			selector.select([first_floor], invalid_context).get("code"),
			&"NO_ELIGIBLE_EVENT",
			"runtime floor index %d is rejected" % invalid_index
		)

	var weighted: Array[Dictionary] = [
		_synthetic_event("event_floor_seed_a", "repeatable", "always", false, 7),
		_synthetic_event("event_floor_seed_b", "repeatable", "always", false, 11),
	]
	var seed_context := _base_context()
	seed_context["floor_index"] = 0
	var seeded: Dictionary = selector.select(weighted, seed_context)
	suite.assert_equal(
		seeded.get("roll"),
		_expected_roll(seed_context, 18),
		"selection seed derivation keeps the zero-based runtime floor index"
	)


func _test_floor_and_availability_filters(suite, definitions: Array[Dictionary]) -> void:
	var selector = DungeonEventSelectorScript.new()
	var definition := _definition_by_id(definitions, "event_memory_mirror")
	var context := _eligible_context(definition)
	context["floor_index"] = int(definition["floor_min"]) - 2
	suite.assert_equal(
		selector.select([definition], context).get("code"),
		&"NO_ELIGIBLE_EVENT",
		"floor minimum is inclusive and rejects the prior floor"
	)
	context["floor_index"] = int(definition["floor_max"])
	suite.assert_equal(
		selector.select([definition], context).get("code"),
		&"NO_ELIGIBLE_EVENT",
		"floor maximum is inclusive and rejects the following floor"
	)
	context = _eligible_context(definition)
	context["availability"] = "CURRENT"
	suite.assert_equal(
		selector.select([definition], context).get("code"),
		&"NO_ELIGIBLE_EVENT",
		"availability must contain the active milestone"
	)


func _test_repeat_policies(suite, definitions: Array[Dictionary]) -> void:
	var selector = DungeonEventSelectorScript.new()
	var once_run := _definition_by_id(definitions, "event_chronal_altar")
	var run_context := _eligible_context(once_run)
	run_context["seen_run_event_ids"] = [str(once_run["id"])]
	suite.assert_equal(
		selector.select([once_run], run_context).get("code"),
		&"NO_ELIGIBLE_EVENT",
		"once-per-run event rejects a seen run identity"
	)

	var once_floor := _definition_by_id(definitions, "event_planar_merchant")
	var floor_context := _eligible_context(once_floor)
	var floor_key := "%s:%s" % [floor_context["floor_id"], once_floor["id"]]
	floor_context["seen_floor_event_keys"] = [floor_key]
	suite.assert_equal(
		selector.select([once_floor], floor_context).get("code"),
		&"NO_ELIGIBLE_EVENT",
		"once-per-floor event rejects the current floor key"
	)
	floor_context["floor_id"] = "floor_other"
	suite.assert_true(
		bool(selector.select([once_floor], floor_context).get("ok", false)),
		"once-per-floor event remains eligible on a different floor"
	)

	var repeatable := _synthetic_event("event_repeatable_probe", "repeatable", "always", false, 1)
	var repeat_context := _base_context()
	repeat_context["seen_run_event_ids"] = [str(repeatable["id"])]
	repeat_context["seen_floor_event_keys"] = [
		"%s:%s" % [repeat_context["floor_id"], repeatable["id"]]
	]
	suite.assert_true(
		bool(selector.select([repeatable], repeat_context).get("ok", false)),
		"repeatable event ignores both repeat histories"
	)


func _test_all_eight_predicates(suite) -> void:
	var selector = DungeonEventSelectorScript.new()
	var cases: Array[Dictionary] = [
		{"predicate": "always", "eligible": {}, "ineligible": null},
		{
			"predicate": "low_health",
			"eligible": {"health": {"current": 30.0, "maximum": 100.0}},
			"ineligible": {"health": {"current": 31.0, "maximum": 100.0}},
		},
		{
			"predicate": "has_curse",
			"eligible": {"build": {"curse_ids": ["curse_probe"]}},
			"ineligible": {"build": {"curse_ids": []}},
		},
		{
			"predicate": "no_curse",
			"eligible": {"build": {"curse_ids": []}},
			"ineligible": {"build": {"curse_ids": ["curse_probe"]}},
		},
		{"predicate": "rich", "eligible": {"economy": {"gold": 200}}, "ineligible": {"economy": {"gold": 199}}},
		{"predicate": "poor", "eligible": {"economy": {"gold": 50}}, "ineligible": {"economy": {"gold": 51}}},
		{
			"predicate": "perfect_rewind_available",
			"eligible": {"meta": {"perfect_rewind_available": true, "old_reunion_eligible": false}},
			"ineligible": {"meta": {"perfect_rewind_available": false, "old_reunion_eligible": false}},
		},
		{
			"predicate": "old_reunion_eligible",
			"eligible": {"meta": {"perfect_rewind_available": false, "old_reunion_eligible": true}},
			"ineligible": {"meta": {"perfect_rewind_available": false, "old_reunion_eligible": false}},
		},
	]
	for index: int in range(cases.size()):
		var case := cases[index]
		var predicate_id := str(case["predicate"])
		var definition := _synthetic_event(
			"event_predicate_%02d" % index, "repeatable", predicate_id, false, 1
		)
		var eligible_context := _merged_context(_base_context(), case["eligible"] as Dictionary)
		var eligible: Dictionary = selector.select([definition], eligible_context)
		suite.assert_true(bool(eligible.get("ok", false)), "%s predicate accepts its boundary fixture" % predicate_id)
		var predicate_facts := eligible.get("predicate_facts", {}) as Dictionary
		suite.assert_equal(
			(predicate_facts.get(str(definition["id"]), {}) as Dictionary).get("eligible"),
			true,
			"%s reports its positive predicate fact" % predicate_id
		)
		if case["ineligible"] == null:
			continue
		var ineligible_context := _merged_context(_base_context(), case["ineligible"] as Dictionary)
		var ineligible: Dictionary = selector.select([definition], ineligible_context)
		suite.assert_equal(
			ineligible.get("code"),
			&"NO_ELIGIBLE_EVENT",
			"%s predicate rejects the adjacent negative fixture" % predicate_id
		)
		predicate_facts = ineligible.get("predicate_facts", {}) as Dictionary
		suite.assert_equal(
			(predicate_facts.get(str(definition["id"]), {}) as Dictionary).get("eligible"),
			false,
			"%s reports its negative predicate fact" % predicate_id
		)


func _test_nested_authorities_ignore_stale_aliases(suite) -> void:
	var selector = DungeonEventSelectorScript.new()
	var rich := _synthetic_event("event_nested_rich", "repeatable", "rich", false, 1)
	var rich_context := _base_context()
	rich_context["economy"] = {"gold": 200}
	rich_context["gold"] = 0
	suite.assert_true(
		bool(selector.select([rich], rich_context).get("ok", false)),
		"nested economy authority wins over a stale top-level gold alias"
	)

	var no_curse := _synthetic_event("event_nested_no_curse", "repeatable", "no_curse", false, 1)
	var build_context := _base_context()
	build_context["build"] = {"curse_ids": []}
	build_context["curse_ids"] = ["curse_stale_alias"]
	suite.assert_true(
		bool(selector.select([no_curse], build_context).get("ok", false)),
		"nested build authority wins over a stale top-level curse alias"
	)


func _test_special_priority(suite, definitions: Array[Dictionary]) -> void:
	var selector = DungeonEventSelectorScript.new()
	var specials: Array[Dictionary] = []
	for event_id: String in SPECIAL_PRIORITY:
		specials.append(_definition_by_id(definitions, event_id))
	var context := _base_context()
	context["floor_index"] = 3
	context["build"] = {"curse_ids": ["curse_probe"]}
	context["meta"] = {
		"perfect_rewind_available": true,
		"old_reunion_eligible": true,
	}
	var first: Dictionary = selector.select(specials.duplicate(true), context)
	suite.assert_equal(first.get("event_id"), SPECIAL_PRIORITY[0], "void whispers owns first special priority")
	context["seen_run_event_ids"] = [SPECIAL_PRIORITY[0]]
	var second: Dictionary = selector.select(specials.duplicate(true), context)
	suite.assert_equal(second.get("event_id"), SPECIAL_PRIORITY[1], "perfect rewind owns second special priority")
	context["seen_run_event_ids"] = [SPECIAL_PRIORITY[0], SPECIAL_PRIORITY[1]]
	var third: Dictionary = selector.select(specials.duplicate(true), context)
	suite.assert_equal(third.get("event_id"), SPECIAL_PRIORITY[2], "old reunion owns third special priority")


func _test_weighted_regular_selection(suite) -> void:
	var selector = DungeonEventSelectorScript.new()
	var low := _synthetic_event("event_weight_low", "repeatable", "always", false, 1)
	var high := _synthetic_event("event_weight_high", "repeatable", "always", false, 99)
	var definitions: Array[Dictionary] = [low, high]
	var counts := {"event_weight_low": 0, "event_weight_high": 0}
	for run_seed: int in range(1, 129):
		var context := _base_context()
		context["run_seed"] = run_seed
		var selected: Dictionary = selector.select(definitions, context)
		var event_id := str(selected.get("event_id", ""))
		if counts.has(event_id):
			counts[event_id] = int(counts[event_id]) + 1
		suite.assert_true(
		int(counts["event_weight_high"]) > int(counts["event_weight_low"]),
		"stable weighted roll materially favors the 99-weight event"
	)


func _test_primary_candidate_ordering(suite) -> void:
	var selector = DungeonEventSelectorScript.new()
	var a := _synthetic_event("event_order_a", "repeatable", "always", false, 7)
	var b := _synthetic_event("event_order_b", "repeatable", "always", false, 11)
	var c := _synthetic_event("event_order_c", "repeatable", "always", false, 13)
	var context := _base_context()
	context["primary_event_id"] = "event_order_b"
	var result: Dictionary = selector.select([c, a, b], context)
	suite.assert_equal(
		result.get("eligible_ids"),
		["event_order_b", "event_order_a", "event_order_c"],
		"eligible regular pool puts the valid primary candidate first then sorts stable IDs"
	)
	var expected_roll := _expected_roll(context, 31)
	suite.assert_equal(result.get("roll"), expected_roll, "weighted selection exposes the exact stable roll")
	var expected_id := (
		"event_order_b" if expected_roll < 11
		else "event_order_a" if expected_roll < 18
		else "event_order_c"
	)
	suite.assert_equal(result.get("event_id"), expected_id, "weighted selection consumes primary-first weights")


func _test_byte_equality_and_channel_isolation(suite) -> void:
	var selector = DungeonEventSelectorScript.new()
	var definitions: Array[Dictionary] = [
		_synthetic_event("event_isolation_a", "repeatable", "always", false, 17),
		_synthetic_event("event_isolation_b", "repeatable", "always", false, 20),
	]
	var context := _base_context()
	var first: Dictionary = selector.select(definitions, context)
	var repeated: Dictionary = selector.select(definitions, context)
	var reordered: Dictionary = selector.select([definitions[1], definitions[0]], context)
	suite.assert_equal(first, repeated, "same facts produce byte-equal dictionaries")
	suite.assert_equal(JSON.stringify(first), JSON.stringify(repeated), "serialized selection is byte-identical")
	suite.assert_equal(
		JSON.stringify(reordered),
		JSON.stringify(first),
		"definition input order cannot change serialized selection bytes"
	)
	suite.assert_equal(
		first.get("channel"),
		"event_selection_v1:%s:%s" % [context["floor_id"], context["node_id"]],
		"selection exposes its isolated floor/node channel"
	)

	var node_isolated := _find_isolated_roll(selector, definitions, context, "node_id", "node_variant_")
	var floor_isolated := _find_isolated_roll(selector, definitions, context, "floor_id", "floor_variant_")
	var seed_isolated := _find_isolated_roll(selector, definitions, context, "run_seed", "")
	suite.assert_true(node_isolated, "node identity changes the isolated roll stream")
	suite.assert_true(floor_isolated, "floor identity changes the isolated roll stream")
	suite.assert_true(seed_isolated, "run seed changes the isolated roll stream")


func _test_no_eligible_event_and_input_immutability(
	suite,
	definitions: Array[Dictionary]
) -> void:
	var selector = DungeonEventSelectorScript.new()
	var context := _base_context()
	context["floor_index"] = -1
	var definitions_before := definitions.duplicate(true)
	var context_before := context.duplicate(true)
	var result: Dictionary = selector.select(definitions, context)
	suite.assert_equal(result.get("code"), &"NO_ELIGIBLE_EVENT", "empty eligible pool fails closed")
	suite.assert_equal(result.get("eligible_ids"), [], "empty eligible pool reports no IDs")
	suite.assert_equal(definitions, definitions_before, "selection never mutates definitions")
	suite.assert_equal(context, context_before, "selection never mutates context")


func _eligible_context(definition: Dictionary) -> Dictionary:
	var context := _base_context()
	context["floor_index"] = int(definition["floor_min"]) - 1
	context["primary_event_id"] = str(definition["id"])
	match str(definition["trigger_predicate_id"]):
		"low_health":
			context["health"] = {"current": 30.0, "maximum": 100.0}
		"has_curse":
			context["build"] = {"curse_ids": ["curse_probe"]}
		"no_curse":
			context["build"] = {"curse_ids": []}
		"rich":
			context["economy"] = {"gold": 200}
		"poor":
			context["economy"] = {"gold": 50}
		"perfect_rewind_available":
			context["meta"]["perfect_rewind_available"] = true
		"old_reunion_eligible":
			context["meta"]["old_reunion_eligible"] = true
	return context


func _base_context() -> Dictionary:
	return {
		"run_seed": 20261002,
		"floor_id": "floor_time_rift",
		"floor_index": 3,
		"node_id": "layer_03_a",
		"availability": "LAUNCH",
		"primary_event_id": "",
		"seen_run_event_ids": [],
		"seen_floor_event_keys": [],
		"health": {"current": 100.0, "maximum": 100.0},
		"economy": {"gold": 100},
		"build": {"curse_ids": []},
		"reward_tags": [],
		"resources": {},
		"narrative_flags": {},
		"meta": {
			"perfect_rewind_available": false,
			"old_reunion_eligible": false,
		},
	}


func _synthetic_event(
	event_id: String,
	repeat_policy: String,
	predicate_id: String,
	special: bool,
	weight: int
) -> Dictionary:
	return {
		"id": event_id,
		"availability": ["LAUNCH", "EXPANSION"],
		"special": special,
		"floor_min": 1,
		"floor_max": 5,
		"weight": weight,
		"repeat_policy": repeat_policy,
		"trigger_predicate_id": predicate_id,
	}


func _merged_context(base: Dictionary, patch: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for key: Variant in patch:
		merged[key] = patch[key]
	return merged


func _expected_roll(context: Dictionary, total_weight: int) -> int:
	var channel := "event_selection_v1:%s:%s" % [context["floor_id"], context["node_id"]]
	return posmod(
		SeedServiceScript.derive_seed(
			int(context["run_seed"]),
			StringName(channel),
			int(context["floor_index"]),
			0,
			0
		),
		total_weight
	)


func _find_isolated_roll(
	selector,
	definitions: Array[Dictionary],
	base_context: Dictionary,
	field: String,
	prefix: String
) -> bool:
	var base_roll := int(selector.select(definitions, base_context).get("roll", -1))
	for index: int in range(1, 65):
		var alternate := base_context.duplicate(true)
		alternate[field] = index if field == "run_seed" else "%s%d" % [prefix, index]
		var result: Dictionary = selector.select(definitions, alternate)
		if int(result.get("roll", -1)) != base_roll:
			return true
	return false


func _read_events() -> Array[Dictionary]:
	var file := FileAccess.open(EVENTS_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return []
	var definitions: Array[Dictionary] = []
	for value: Variant in parsed:
		if value is Dictionary:
			definitions.append((value as Dictionary).duplicate(true))
	return definitions


func _event_ids(definitions: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for definition: Dictionary in definitions:
		ids.append(str(definition.get("id", "")))
	return ids


func _definition_by_id(definitions: Array[Dictionary], event_id: String) -> Dictionary:
	for definition: Dictionary in definitions:
		if str(definition.get("id", "")) == event_id:
			return definition.duplicate(true)
	return {}
