extends Node

const ConsequenceRuntimeScript := preload(
	"res://scripts/events/dungeon_event_consequence_runtime.gd"
)
const DungeonEventRuntimeScript := preload("res://scripts/events/dungeon_event_runtime.gd")
const DungeonEventDefinitionScript := preload("res://scripts/dungeon/dungeon_event_definition.gd")
const DungeonEventRunStateScript := preload("res://scripts/events/dungeon_event_run_state.gd")
const DungeonEventSelectorScript := preload("res://scripts/events/dungeon_event_selector.gd")
const EventHealthAuthorityScript := preload("res://scripts/events/event_health_authority.gd")
const EventModifierAuthorityScript := preload("res://scripts/events/event_modifier_authority.gd")
const EventRequirementServiceScript := preload("res://scripts/events/event_requirement_service.gd")
const EventResourceAuthorityScript := preload("res://scripts/events/event_resource_authority.gd")
const EventRouteAuthorityScript := preload("res://scripts/events/event_route_authority.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const MerchantRunStateScript := preload("res://scripts/economy/merchant_run_state.gd")
const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")
const RunEconomyStateScript := preload("res://scripts/economy/run_economy_state.gd")
const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")
const SaveFileOpsScript := preload("res://scripts/save/save_file_ops.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_FIXTURE_PATH := "res://tests/fixtures/save/profile_v3.json"
const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"
const ECONOMY_PATH := "res://data/content_packs/base/content/economy_profiles.json"
const EVENT_PATH := "res://data/content_packs/base/content/dungeon_events.json"

var _global_revision := 10
var _provider_context: Dictionary = {}
var _published_fact_ids: Dictionary = {}
var _definitions: Array[Dictionary] = []
var _content_fingerprint := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	for value: Variant in _read_json_array(EVENT_PATH):
		var normalized: Dictionary = DungeonEventDefinitionScript.new().configure(value)
		assert(bool(normalized.get("ok", false)))
		_definitions.append(normalized["definition"])
	_definitions.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["id"]) < str(right["id"])
	)
	_content_fingerprint = _digest_canonical({"events": _definitions})
	var profile_fixture := _read_json(PROFILE_FIXTURE_PATH)
	var plan := _event_floor_plan()
	suite.assert_true(not profile_fixture.is_empty(), "event Save profile fixture loads")
	suite.assert_true(not plan.is_empty(), "event Save fixture reaches an event room")
	if profile_fixture.is_empty() or plan.is_empty():
		suite.finish(get_tree())
		return

	var snapshots: Dictionary = {}
	for phase: String in [
		"open", "reserved", "pending_reward", "pending_encounter", "resolved", "dismissed",
	]:
		var active_run := _active_run_for_phase(phase, plan)
		snapshots[phase] = active_run.duplicate(true)
		_assert_save_round_trip(suite, profile_fixture, active_run, phase)

	_test_cross_domain_drift(suite, profile_fixture, snapshots["resolved"] as Dictionary)
	_test_runtime_tampering(suite, profile_fixture, snapshots)
	_test_nested_runtime_contracts(suite, profile_fixture, snapshots["resolved"] as Dictionary)
	_test_cleared_event_requires_history(suite, profile_fixture, snapshots["dismissed"] as Dictionary)
	_test_route_skip_event_history(suite, profile_fixture)
	_test_authored_assignments(suite, profile_fixture, plan)
	_test_assignment_policy_and_floor_bounds(suite, profile_fixture, plan)
	_test_assignment_floor_authority(suite, profile_fixture, plan)
	_test_content_update_preserves_historical_event_save(suite, profile_fixture, plan)
	suite.finish(get_tree())


func _test_content_update_preserves_historical_event_save(
	suite, profile_fixture: Dictionary, plan: Dictionary
) -> void:
	var current_definitions := _definitions.duplicate(true)
	var current_fingerprint := _content_fingerprint
	var historical_definitions := _definitions.duplicate(true)
	historical_definitions[0]["name_key"] = "EVENT_HISTORICAL_NAME"
	_definitions = historical_definitions
	_content_fingerprint = _digest_canonical({"events": historical_definitions})
	var historical_run := _active_run_for_phase("resolved", plan)
	_definitions = current_definitions
	_content_fingerprint = current_fingerprint

	var current_content := (profile_fixture["content_snapshot"] as Dictionary).duplicate(true)
	var historical_content := current_content.duplicate(true)
	historical_content["packs"][0]["fingerprint_sha256"] = _digest_canonical(historical_definitions)
	historical_content["aggregate_sha256"] = SaveEnvelopeScript.content_snapshot_digest(
		historical_content["packs"]
	)
	var historical_document := profile_fixture.duplicate(true)
	historical_document["sequence"] = 80
	historical_document["saved_at_utc"] = "2026-10-02T08:08:00Z"
	historical_document["content_snapshot"] = historical_content
	historical_document["payload"]["active_run_state"] = historical_run
	historical_document = JSON.parse_string(JSON.stringify(historical_document, "", true, true))
	_resign(historical_document)
	var strict_validation = SaveEnvelopeScript.validate(historical_document, &"profile", "slot_1", "base")
	suite.assert_equal(
		strict_validation.code,
		&"CORRUPT", "direct envelope validation remains strict against current event content"
	)
	suite.assert_equal(strict_validation.metadata.get("field"), "payload.active_run_state.dungeon_event_runtime", "historical fixture reaches event validation after valid envelope integrity")
	var rejected_create = SaveEnvelopeScript.create_profile(
		"slot_1", "base", 80, "0.4.0-dev",
		"2026-10-02T08:00:00Z", "2026-10-02T08:08:00Z",
		historical_content, {"active_run_state": historical_run}
	)
	suite.assert_equal(rejected_create.code, &"INVALID_ARGUMENT", "new writes cannot seal obsolete event definitions")

	var test_base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if test_base.is_empty():
		test_base = OS.get_temp_dir().path_join("planewalker-tests")
	var test_root := test_base.path_join("event_content_update_%d" % Time.get_ticks_usec())
	var profile_directory := test_root.path_join("profiles/slot_1/base")
	var primary_path := profile_directory.path_join("primary.json")
	var backup_path := profile_directory.path_join("backup_1.json")
	var service = SaveServiceScript.new()
	var configured = service.configure(test_root, "0.4.0-dev", current_content)
	suite.assert_true(configured.ok, "updated-content SaveService configures")
	if not configured.ok:
		return
	var files = SaveFileOpsScript.new()
	var backup = SaveEnvelopeScript.create_profile(
		"slot_1", "base", 79, "0.4.0-dev",
		"2026-10-02T08:00:00Z", "2026-10-02T08:07:00Z",
		current_content, {"value": "older_compatible_backup"}
	)
	suite.assert_true(backup.ok, "content-update test creates a compatible older backup")
	if not backup.ok:
		return
	var historical_bytes := JSON.stringify(historical_document, "", true, true)
	suite.assert_true(files.write_utf8(primary_path, historical_bytes).ok, "historical event primary writes")
	suite.assert_true(files.write_utf8(backup_path, JSON.stringify(backup.payload, "", true, true)).ok, "compatible event backup writes")
	var inspected = service.inspect_profile("slot_1", "base")
	suite.assert_equal(inspected.code, &"CONTENT_MISMATCH", "inspection detects changed content before interpreting historical events")
	var loaded = service.load_profile("slot_1", "base")
	suite.assert_equal(loaded.code, &"CONTENT_MISMATCH", "content update refuses event restore without backup recovery")
	suite.assert_equal(loaded.metadata.get("actual_aggregate"), historical_content["aggregate_sha256"], "content mismatch identifies the historical pack")
	suite.assert_true(files.read_utf8(primary_path).payload == historical_bytes, "content update preserves historical primary bytes")
	suite.assert_true(not DirAccess.dir_exists_absolute(profile_directory.path_join("quarantine")), "content update never quarantines the historical event save")

	var matching_document := historical_document.duplicate(true)
	matching_document["content_snapshot"] = current_content.duplicate(true)
	_resign(matching_document)
	suite.assert_true(files.write_utf8(primary_path, JSON.stringify(matching_document, "", true, true)).ok, "matching-content corruption fixture writes")
	var corrupted = service.inspect_profile("slot_1", "base")
	suite.assert_equal(corrupted.code, &"CORRUPT", "matching content still deeply validates the event authority")
	suite.assert_equal(corrupted.metadata.get("field"), "payload.active_run_state.dungeon_event_runtime", "matching-content corruption identifies the event boundary")
	var recovered = service.load_profile("slot_1", "base")
	suite.assert_equal(recovered.code, &"RECOVERED", "matching-content event corruption retains normal backup recovery")
	suite.assert_equal(recovered.payload.get("value"), "older_compatible_backup", "event corruption recovers the compatible backup")
	suite.assert_true(files.remove_tree(test_root).ok, "content-update test removes its temporary scope")


func _assert_save_round_trip(
	suite,
	profile_fixture: Dictionary,
	active_run: Dictionary,
	phase: String
) -> void:
	var created = SaveEnvelopeScript.create_profile(
		"slot_1",
		"base",
		70,
		"0.4.0-dev",
		"2026-10-02T08:00:00Z",
		"2026-10-02T08:05:00Z",
		profile_fixture.get("content_snapshot", {}),
		{"active_run_state": active_run}
	)
	suite.assert_true(created.ok, "%s event snapshot seals: %s" % [phase, str(created.to_dictionary())])
	if not created.ok:
		return
	var parsed: Variant = JSON.parse_string(JSON.stringify(created.payload, "", true, true))
	var validated = SaveEnvelopeScript.validate(parsed, &"profile", "slot_1", "base")
	suite.assert_true(
		validated.ok,
		"%s event snapshot validates after JSON round trip: %s"
		% [phase, str(validated.to_dictionary())]
	)
	if validated.ok:
		suite.assert_equal(
			validated.payload.get("payload", {}).get("active_run_state", {}),
			active_run,
			"%s event snapshot round trips byte-equivalent values" % phase
		)
	var test_base := OS.get_environment("PLANEWALKER_TEST_DATA_DIR")
	if test_base.is_empty():
		test_base = OS.get_temp_dir().path_join("planewalker-tests")
	var test_root := test_base.path_join("event_phase_%s_%d" % [phase, Time.get_ticks_usec()])
	var service = SaveServiceScript.new()
	var configured = service.configure(
		test_root, "0.4.0-dev", profile_fixture.get("content_snapshot", {})
	)
	suite.assert_true(configured.ok, "%s event SaveService configures" % phase)
	if not configured.ok:
		return
	var saved = service.save_profile("slot_1", "base", {"active_run_state": active_run})
	suite.assert_true(saved.ok, "%s event snapshot writes through the production SaveService" % phase)
	var loaded = service.load_profile("slot_1", "base")
	suite.assert_equal(loaded.code, &"OK", "%s event snapshot loads without recovery" % phase)
	if loaded.ok:
		suite.assert_equal(loaded.payload.get("active_run_state", {}), active_run, "%s event phase survives physical JSON I/O" % phase)
	suite.assert_true(SaveFileOpsScript.new().remove_tree(test_root).ok, "%s event round trip removes its temporary scope" % phase)


func _test_cross_domain_drift(
	suite,
	profile_fixture: Dictionary,
	active_run: Dictionary
) -> void:
	var created = SaveEnvelopeScript.create_profile(
		"slot_1", "base", 71, "0.4.0-dev",
		"2026-10-02T08:00:00Z", "2026-10-02T08:06:00Z",
		profile_fixture.get("content_snapshot", {}),
		{"active_run_state": active_run}
	)
	suite.assert_true(created.ok, "canonical event drift fixture seals")
	if not created.ok:
		return
	var mutations: Array[Dictionary] = [
		{
			"label": "active event identity drift",
			"mutate": func(run: Dictionary):
				run["dungeon_event_runtime"]["active_event_id"] = "event_forged",
		},
		{
			"label": "economy participant drift",
			"mutate": func(run: Dictionary):
				var participants := _participants(run)
				participants["economy"] = _economy_with_delta(
					participants["economy"] as Dictionary, "save_drift_gold", 1
				),
		},
		{
			"label": "route participant drift",
			"mutate": func(run: Dictionary):
				var participants := _participants(run)
				participants["route"] = _revealed_route_snapshot(
					participants["route"] as Dictionary
				),
		},
		{
			"label": "resource participant drift",
			"mutate": func(run: Dictionary):
				var participants := _participants(run)
				participants["resource"] = _resource_with_delta(
					participants["resource"] as Dictionary
				),
		},
		{
			"label": "health participant drift",
			"mutate": func(run: Dictionary):
				var participants := _participants(run)
				participants["health"] = _health_with_delta(
					participants["health"] as Dictionary
				),
		},
		{
			"label": "Build curse drift",
			"mutate": func(run: Dictionary):
				var participants := _participants(run)
				var modifier := (participants["modifier"] as Dictionary).duplicate(true)
				modifier["curse_ids"] = ["curse_fickle_time"]
				participants["modifier"] = modifier,
		},
		{
			"label": "event modifier flag drift",
			"mutate": func(run: Dictionary):
				var participants := _participants(run)
				var modifier := (participants["modifier"] as Dictionary).duplicate(true)
				modifier["narrative_flags"] = {"forged_flag": true}
				participants["modifier"] = modifier,
		},
	]
	for mutation: Dictionary in mutations:
		var candidate: Dictionary = created.payload.duplicate(true)
		candidate["payload"]["active_run_state"] = active_run.duplicate(true)
		var run := candidate["payload"]["active_run_state"] as Dictionary
		(mutation["mutate"] as Callable).call(run)
		_resign(candidate)
		var result = SaveEnvelopeScript.validate(candidate, &"profile", "slot_1", "base")
		suite.assert_equal(result.code, &"CORRUPT", "%s fails closed" % mutation["label"])
		suite.assert_equal(
			result.metadata.get("field"),
			"payload.active_run_state.dungeon_event_runtime",
			"%s identifies the event authority boundary" % mutation["label"]
		)


func _test_runtime_tampering(suite, profile_fixture: Dictionary, snapshots: Dictionary) -> void:
	var mutations: Array[Dictionary] = [
		{"label": "publication digest", "mutate": func(run: Dictionary):
			run["dungeon_event_runtime"]["publication_digest"] = "0".repeat(64)},
		{"label": "publication chain", "mutate": func(run: Dictionary):
			run["dungeon_event_runtime"]["publication_ledger"][0]["chain_hash"] = "0".repeat(64)},
		{"label": "publication payload", "mutate": func(run: Dictionary):
			run["dungeon_event_runtime"]["publication_ledger"][0]["payload"]["event_id"] = "event_forged"},
		{"label": "removed publications", "mutate": func(run: Dictionary):
			run["dungeon_event_runtime"]["emitted_fact_ids"] = []
			run["dungeon_event_runtime"]["publication_ledger"] = []},
		{"label": "forged encounter result", "mutate": func(run: Dictionary):
			run["dungeon_event_runtime"]["encounter_success_by_transaction"] = {"forged": true}},
		{"label": "unknown runtime field", "mutate": func(run: Dictionary):
			run["dungeon_event_runtime"]["unknown"] = true},
		{"label": "seen event projection", "mutate": func(run: Dictionary):
			run["seen_event_ids"] = []},
		{"label": "runtime removed from event run", "mutate": func(run: Dictionary):
			run["dungeon_event_runtime"] = {}},
		{"label": "runtime and seen projection removed together", "mutate": func(run: Dictionary):
			run["dungeon_event_runtime"] = {}
			run["seen_event_ids"] = []},
		{"label": "fractional resource", "mutate": func(run: Dictionary):
			_participants(run)["resource"]["resources"]["time_shard"] = 2.5},
		{"label": "missing active identity", "mutate": func(run: Dictionary):
			run["dungeon_event_runtime"]["active_node_key"] = ""
			run["dungeon_event_runtime"]["active_event_id"] = ""},
	]
	for phase: String in snapshots.keys():
		for mutation: Dictionary in mutations:
			var candidate := profile_fixture.duplicate(true)
			candidate["payload"]["active_run_state"] = snapshots[phase].duplicate(true)
			(mutation["mutate"] as Callable).call(candidate["payload"]["active_run_state"])
			_resign(candidate)
			var result = SaveEnvelopeScript.validate(candidate, &"profile", "slot_1", "base")
			suite.assert_equal(result.code, &"CORRUPT", "%s rejects %s" % [phase, mutation["label"]])


func _test_nested_runtime_contracts(suite, profile_fixture: Dictionary, source_run: Dictionary) -> void:
	var mutations: Array[Dictionary] = [
		{"label": "unknown consequence field", "mutate": func(run: Dictionary):
			run["dungeon_event_runtime"]["consequence_runtime"]["unknown"] = true},
		{"label": "unknown participant", "mutate": func(run: Dictionary):
			_participants(run)["unknown"] = {}},
		{"label": "duplicate state transaction", "mutate": func(run: Dictionary):
			var ids := _participants(run)["event_state"]["completed_transaction_ids"] as Array
			ids.append(ids[0])},
		{"label": "duplicate consequence transaction", "mutate": func(run: Dictionary):
			var ids := run["dungeon_event_runtime"]["consequence_runtime"]["completed_transaction_ids"] as Array
			ids.append(ids[0])},
		{"label": "duplicate consequence publication", "mutate": func(run: Dictionary):
			var facts := run["dungeon_event_runtime"]["consequence_runtime"]["publications"] as Array
			facts.append(facts[0].duplicate(true))},
		{"label": "duplicate emitted fact", "mutate": func(run: Dictionary):
			var ids := run["dungeon_event_runtime"]["emitted_fact_ids"] as Array
			ids.append(ids[0])},
		{"label": "duplicate publication ledger fact", "mutate": func(run: Dictionary):
			var facts := run["dungeon_event_runtime"]["publication_ledger"] as Array
			facts.append(facts[0].duplicate(true))},
	]
	for participant: String in ["resource", "health", "economy", "modifier", "route", "event_state"]:
		mutations.append({
			"label": "unknown %s field" % participant,
			"mutate": func(run: Dictionary): _participants(run)[participant]["unknown"] = true,
		})
	for mutation: Dictionary in mutations:
		var candidate := profile_fixture.duplicate(true)
		candidate["payload"]["active_run_state"] = source_run.duplicate(true)
		(mutation["mutate"] as Callable).call(candidate["payload"]["active_run_state"])
		_resign(candidate)
		var before := JSON.stringify(candidate, "", true, true)
		var result = SaveEnvelopeScript.validate(candidate, &"profile", "slot_1", "base")
		suite.assert_equal(result.code, &"CORRUPT", "nested Save contract rejects %s" % mutation["label"])
		suite.assert_equal(JSON.stringify(candidate, "", true, true), before, "nested rejection preserves source bytes")


func _test_cleared_event_requires_history(
	suite, profile_fixture: Dictionary, source_run: Dictionary
) -> void:
	var run := source_run.duplicate(true)
	var plan := _with_current_node_cleared(run["floor_plan"] as Dictionary)
	run["floor_plan"] = plan
	var fixture := _runtime_fixture(plan, "reward", str(run["run_id"]))
	var runtime: RefCounted = fixture["runtime"]
	var empty_runtime: Dictionary = runtime.call("snapshot")
	suite.assert_true(runtime.call("can_restore_snapshot", empty_runtime), "erased-history fixture retains restorable real authorities")
	run["dungeon_event_runtime"] = empty_runtime
	run["seen_event_ids"] = []
	var participants := _participants(run)
	run["run_economy"] = participants["economy"].duplicate(true)
	run["resources"] = {
		"resource": participants["resource"].duplicate(true),
		"health": participants["health"].duplicate(true),
	}
	var candidate := profile_fixture.duplicate(true)
	candidate["payload"]["active_run_state"] = run
	_resign(candidate)
	var result = SaveEnvelopeScript.validate(candidate, &"profile", "slot_1", "base")
	suite.assert_equal(result.code, &"CORRUPT", "initialized empty runtime cannot erase a cleared event's assignment history")
	suite.assert_equal(result.metadata.get("field"), "payload.active_run_state.dungeon_event_runtime", "erased history identifies the event authority boundary")
	suite.assert_equal(result.metadata.get("reason"), "missing_cleared_event_history", "cleared event rejection identifies the missing history")
	var created = SaveEnvelopeScript.create_profile(
		"slot_1", "base", 75, "0.4.0-dev",
		"2026-10-02T08:00:00Z", "2026-10-02T08:07:00Z",
		profile_fixture["content_snapshot"], {"active_run_state": run}
	)
	suite.assert_equal(created.code, &"INVALID_ARGUMENT", "new Save writes also require cleared event history")


func _test_route_skip_event_history(suite, profile_fixture: Dictionary) -> void:
	for event_position: int in [1, 2]:
		var fixture := _route_skip_event_fixture(event_position)
		suite.assert_true(not fixture.is_empty(), "Save route-skip fixture reaches event destination %s" % event_position)
		if fixture.is_empty():
			continue
		var run := _active_run_for_phase(
			"open", fixture["source_plan"], {"definition_id": "event_void_rift"}
		)
		var runtime := fixture["runtime"] as Dictionary
		var participants := _participants_from_runtime(runtime)
		var plan := (participants["route"]["plan"] as Dictionary).duplicate(true)
		run["dungeon_event_runtime"] = runtime.duplicate(true)
		run["floor_plan"] = plan
		run["current_room"] = (plan["selected_edge_ids"] as Array).size()
		run["run_economy"] = participants["economy"].duplicate(true)
		run["resources"] = {
			"resource": participants["resource"].duplicate(true),
			"health": participants["health"].duplicate(true),
		}
		run["seen_event_ids"] = participants["event_state"]["seen_run_event_ids"].duplicate()
		_assert_save_round_trip(suite, profile_fixture, run, "route skip with an event at destination %s" % event_position)
		if event_position == 1:
			continue
		plan = _with_current_node_cleared(plan)
		run["floor_plan"] = plan
		_participants(run)["route"]["plan"] = plan.duplicate(true)
		var candidate := profile_fixture.duplicate(true)
		candidate["payload"]["active_run_state"] = run
		_resign(candidate)
		var result = SaveEnvelopeScript.validate(candidate, &"profile", "slot_1", "base")
		suite.assert_equal(result.code, &"CORRUPT", "route skip cannot exempt its cleared landing event from history")
		suite.assert_equal(result.metadata.get("reason"), "missing_cleared_event_history", "landing event remains an independent history boundary")


func _route_skip_event_fixture(event_position: int) -> Dictionary:
	var floors := _read_json_array(FLOOR_PATH)
	var templates := _read_json_array(TEMPLATE_PATH)
	for seed_value: int in range(1, 65):
		var generated: Dictionary = FloorPlanGeneratorScript.new().generate(seed_value, floors[2], templates)
		if not bool(generated.get("ok", false)):
			continue
		var model = FloorPlanScript.new()
		if not bool(model.configure(generated["plan"], floors[2], templates).get("ok", false)):
			continue
		while model.snapshot()["current_node_id"] != model.snapshot()["boss_node_id"]:
			var source_plan: Dictionary = model.snapshot()
			var choices: Array[Dictionary] = []
			for edge: Dictionary in source_plan["edges"]:
				if str(edge["source_node_id"]) == str(source_plan["current_node_id"]) and not bool(edge["locked"]):
					choices.append(edge)
			choices.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
				return int(left["choice_order"]) < int(right["choice_order"])
			)
			if choices.is_empty() or not bool(model.select_edge(StringName(str(choices[0]["id"])), model.revision()).get("ok", false)):
				break
			source_plan = model.snapshot()
			source_plan = _with_current_node_cleared(source_plan)
			var node := _node_by_id(source_plan, str(source_plan["current_node_id"]))
			if str(node["room_type"]) != "event":
				if not bool(model.configure(source_plan, floors[2], templates).get("ok", false)):
					break
				continue
			var route = EventRouteAuthorityScript.new()
			if not route.configure(source_plan):
				break
			var preview: Dictionary = route.prepare_operations(
				"save_route_skip_probe", [{"operation": "route_skip", "arguments": {"rooms": 2}}], 0
			)
			if not bool(preview.get("ok", false)):
				break
			var preview_plan := preview["ticket"]["after"]["plan"] as Dictionary
			var route_node_ids := preview_plan["visited_node_ids"] as Array
			var destination := _node_by_id(preview_plan, str(route_node_ids[route_node_ids.size() - 3 + event_position]))
			if str(destination["room_type"]) != "event":
				break
			var fixture := _runtime_fixture(
				source_plan, "immediate", "run-event-save-open", {"definition_id": "event_void_rift"}
			)
			var runtime: RefCounted = fixture["runtime"]
			if not bool(runtime.call("open_event", {
				"floor_id": str(source_plan["floor_id"]), "floor_index": int(source_plan["floor_index"]),
				"node_id": str(node["id"]), "primary_event_id": str(node["event_id"]),
			}, {}).get("ok", false)):
				return {}
			if not bool(runtime.call("choose_option", &"commit", _global_revision).get("ok", false)):
				return {}
			if not bool(runtime.call("dismiss_result", _global_revision).get("ok", false)):
				return {}
			return {"source_plan": source_plan, "runtime": runtime.call("snapshot")}
	return {}


func _with_current_node_cleared(plan: Dictionary) -> Dictionary:
	var result := plan.duplicate(true)
	for node: Dictionary in result["nodes"]:
		if str(node["id"]) == str(result["current_node_id"]):
			node["cleared"] = true
	return result


func _test_authored_assignments(suite, profile_fixture: Dictionary, plan: Dictionary) -> void:
	var mutations: Array[Dictionary] = [
		{"event_id": "event_unauthored"},
		{"option_id": "option_unauthored"},
		{"outcome_id": "outcome_unauthored"},
		{"outcome_key": "EVENT_UNAUTHORED_OUTCOME"},
	]
	for phase: String in ["reserved", "pending_reward", "pending_encounter", "resolved", "dismissed"]:
		for mutation: Dictionary in mutations:
			var active_run := _active_run_for_phase(phase, plan, mutation)
			_assert_unauthored_assignment_rejected(
				suite, profile_fixture, active_run, "%s/%s" % [phase, str(mutation.keys()[0])]
			)

	var inactive_baseline := _active_run_for_phase("dismissed", plan, {}, true)
	_assert_save_round_trip(suite, profile_fixture, inactive_baseline, "authored inactive assignment")
	for mutation: Dictionary in mutations:
		var active_run := _active_run_for_phase("dismissed", plan, mutation, true)
		suite.assert_equal(
			active_run["dungeon_event_runtime"]["active_event_id"], "event_chronal_altar",
			"inactive corruption preserves a valid active event"
		)
		_assert_unauthored_assignment_rejected(
			suite, profile_fixture, active_run, "inactive/%s" % str(mutation.keys()[0])
		)


func _assert_unauthored_assignment_rejected(
	suite, profile_fixture: Dictionary, active_run: Dictionary, label: String
) -> void:
	suite.assert_true(not active_run.is_empty(), "%s builds a real runtime snapshot" % label)
	if active_run.is_empty():
		return
	var candidate := profile_fixture.duplicate(true)
	candidate["payload"]["active_run_state"] = active_run.duplicate(true)
	_resign(candidate)
	var result = SaveEnvelopeScript.validate(candidate, &"profile", "slot_1", "base")
	suite.assert_equal(result.code, &"CORRUPT", "%s rejects a re-signed unauthored assignment" % label)
	suite.assert_equal(
		result.metadata.get("field"), "payload.active_run_state.dungeon_event_runtime",
		"%s identifies the event authority boundary" % label
	)
	suite.assert_equal(
		result.metadata.get("reason"), "authored_assignment_invalid",
		"%s fails at the authored-content check" % label
	)
	var created = SaveEnvelopeScript.create_profile(
		"slot_1", "base", 72, "0.4.0-dev",
		"2026-10-02T08:00:00Z", "2026-10-02T08:07:00Z",
		profile_fixture.get("content_snapshot", {}), {"active_run_state": active_run}
	)
	suite.assert_equal(created.code, &"INVALID_ARGUMENT", "%s cannot create an unauthored save" % label)


func _test_assignment_policy_and_floor_bounds(
	suite, profile_fixture: Dictionary, plan: Dictionary
) -> void:
	var last_floor_plan := _event_floor_plan(4)
	suite.assert_true(not last_floor_plan.is_empty(), "floor-bound fixture reaches the final floor event")
	if last_floor_plan.is_empty():
		return
	for phase: String in [
		"open", "reserved", "pending_reward", "pending_encounter", "resolved", "dismissed",
	]:
		var valid_boundary_plan := last_floor_plan
		var valid_boundary_definition := {"definition_id": "event_final_choice"}
		if phase == "pending_encounter":
			valid_boundary_plan = _event_floor_plan(3)
			valid_boundary_definition["definition_id"] = "event_sleeping_guardian"
		_assert_save_round_trip(
			suite, profile_fixture,
			_active_run_for_phase(phase, valid_boundary_plan, valid_boundary_definition),
			"%s/authored floor boundary" % phase
		)
		_assert_unauthored_assignment_rejected(
			suite, profile_fixture,
			_active_run_for_phase(phase, plan, {"repeat_policy": "repeatable"}),
			"%s/authored repeat policy" % phase
		)
		var upper_override := {"floor_max": 5}
		if phase in ["open", "reserved"]:
			upper_override["definition_id"] = "event_trapped_traveler"
		_assert_unauthored_assignment_rejected(
			suite, profile_fixture,
			_active_run_for_phase(phase, last_floor_plan, upper_override),
			"%s/authored maximum floor" % phase
		)
		if phase != "pending_encounter":
			var lower_override := {"definition_id": "event_final_choice", "floor_min": 1}
			if phase in ["open", "reserved"]:
				lower_override["definition_id"] = "event_memory_mirror"
			_assert_unauthored_assignment_rejected(
				suite, profile_fixture, _active_run_for_phase(phase, plan, lower_override),
				"%s/authored minimum floor" % phase
			)
	_assert_unauthored_assignment_rejected(
		suite, profile_fixture,
		_active_run_for_phase("dismissed", plan, {"repeat_policy": "repeatable"}, true),
		"historical/authored repeat policy"
	)
	_assert_unauthored_assignment_rejected(
		suite, profile_fixture,
		_active_run_for_phase(
			"dismissed", plan, {"definition_id": "event_final_choice", "floor_min": 1}, true
		),
		"historical/authored minimum floor"
	)


func _test_assignment_floor_authority(
	suite, profile_fixture: Dictionary, plan: Dictionary
) -> void:
	_assert_save_round_trip(
		suite, profile_fixture, _active_run_for_phase("resolved", plan, {}, true),
		"historical/resolved event with a current-floor active assignment"
	)
	for phase: String in ["open", "reserved", "pending_reward", "pending_encounter"]:
		_assert_unauthored_assignment_rejected(
			suite, profile_fixture,
			_active_run_for_phase(phase, plan, {"advance_floor_only": true}, true),
			"historical/incomplete %s phase" % phase
		)
	for invalid_node: String in ["entry", "boss", "missing_node"]:
		_assert_unauthored_assignment_rejected(
			suite, profile_fixture,
			_active_run_for_phase("dismissed", plan, {"node_id": invalid_node}, true),
			"historical/non-event node %s" % invalid_node
		)
	for mutation: Dictionary in [
		{"floor_id": "floor_unauthored"},
		{"floor_id": "floor_time_rift", "floor_index": 0},
		{"floor_id": "floor_time_rift", "floor_index": 2},
	]:
		_assert_unauthored_assignment_rejected(
			suite, profile_fixture, _active_run_for_phase("dismissed", plan, mutation, true),
			"historical/invalid floor identity %s" % str(mutation)
		)
	var tested_unvisited_branch := false
	for node: Dictionary in plan["nodes"]:
		if str(node["room_type"]) == "event" and not bool(node["visited"]):
			tested_unvisited_branch = true
			_assert_unauthored_assignment_rejected(
				suite, profile_fixture,
				_active_run_for_phase("dismissed", plan, {
					"node_id": str(node["id"]), "same_floor_inactive": true,
				}, true),
				"current/unvisited event branch"
			)
			break
	suite.assert_true(tested_unvisited_branch, "node-authority test covers a real unvisited event branch")


func _active_run_for_phase(
	phase: String, source_plan: Dictionary,
	definition_overrides: Dictionary = {}, inactive: bool = false
) -> Dictionary:
	var plan := source_plan.duplicate(true)
	var event_kind := "encounter" if phase == "pending_encounter" else "reward"
	if phase in ["open", "reserved"]:
		event_kind = "immediate"
	var run_id := "run-event-save-%s" % phase
	var fixture := _runtime_fixture(plan, event_kind, run_id, definition_overrides, inactive)
	var runtime: RefCounted = fixture["runtime"]
	var event_state: RefCounted = fixture["event_state"]
	var definition := fixture["definition"] as Dictionary
	var node := _node_by_id(plan, str(plan["current_node_id"]))
	if definition_overrides.has("node_id"):
		node["id"] = str(definition_overrides["node_id"])
	var assignment_floor_id := str(definition_overrides.get("floor_id", plan["floor_id"]))
	var assignment_floor_index := int(definition_overrides.get("floor_index", plan["floor_index"]))
	var opened: Dictionary = runtime.call("open_event", {
		"floor_id": assignment_floor_id,
		"floor_index": assignment_floor_index,
		"node_id": str(node["id"]),
		"primary_event_id": str(node["event_id"]),
	}, {})
	assert(bool(opened.get("ok", false)))

	if phase == "reserved":
		var event_snapshot: Dictionary = event_state.call("snapshot")
		var node_key := "%s:%s" % [assignment_floor_id, str(node["id"])]
		var option := (definition["options"] as Array)[0] as Dictionary
		var outcome := (option["outcomes"] as Array)[0] as Dictionary
		var reserved: Dictionary = event_state.call(
			"reserve_option",
			node_key,
			"event_tx_v1:%s:%d" % [str(definition["id"]), int(event_snapshot["revision"])],
			str(option["id"]),
			str(outcome["id"]),
			str(outcome["outcome_key"]),
			int(event_snapshot["revision"])
		)
		assert(bool(reserved.get("ok", false)))
	elif phase not in ["open"]:
		var option_id := StringName(str(definition["options"][0]["id"]))
		assert(bool(runtime.call("choose_option", option_id, _global_revision).get("ok", false)))
		if phase in ["resolved", "dismissed"]:
			var pending := _event_state_snapshot(runtime.call("snapshot"))
			var continuation_id := str((pending["pending_reward"] as Dictionary)["continuation_id"])
			assert(bool(runtime.call(
				"complete_reward", continuation_id, {"reward_id": "item_fixture"}, _global_revision
			).get("ok", false)))
			if phase == "dismissed":
				assert(bool(runtime.call("dismiss_result", _global_revision).get("ok", false)))
	if inactive:
		if not bool(definition_overrides.get("same_floor_inactive", false)):
			plan = _event_floor_plan(int(plan["floor_index"]) + 1)
			assert(not plan.is_empty())
			assert((fixture["route"] as RefCounted).call("configure", plan))
		_provider_context["selection"]["economy"]["gold"] = 200
		_provider_context["selection"]["floor_id"] = str(plan["floor_id"])
		_provider_context["selection"]["floor_index"] = int(plan["floor_index"])
		_provider_context["requirements"]["floor_index"] = int(plan["floor_index"])
		if not bool(definition_overrides.get("advance_floor_only", false)):
			var active_node := _node_by_id(plan, str(plan["current_node_id"]))
			var reopened: Dictionary = runtime.call("open_event", {
				"floor_id": str(plan["floor_id"]), "floor_index": int(plan["floor_index"]),
				"node_id": str(active_node["id"]), "primary_event_id": "event_chronal_altar",
			}, {})
			assert(bool(reopened.get("ok", false)))

	var runtime_snapshot: Dictionary = runtime.call("snapshot")
	if definition_overrides.has("event_id"):
		var original_route := _participants_from_runtime(runtime_snapshot)["route"] as Dictionary
		runtime_snapshot = _replace_event_identity(
			runtime_snapshot, str(definition["id"]), str(definition_overrides["event_id"])
		)
		_participants_from_runtime(runtime_snapshot)["route"] = original_route.duplicate(true)
		# Keep the inner seal valid so rejection must bind assignments to authored content.
		var publication: Dictionary = runtime.call(
			"_sealed_publication_state", runtime_snapshot["emitted_fact_ids"],
			runtime_snapshot["pending_facts"], runtime_snapshot["encounter_success_by_transaction"],
			runtime_snapshot["consequence_runtime"]
		)
		assert(not publication.is_empty())
		runtime_snapshot.merge(publication, true)
	assert(event_state.call("can_restore_snapshot", _event_state_snapshot(runtime_snapshot)))
	var participants := _participants_from_runtime(runtime_snapshot)
	var merchant = MerchantRunStateScript.new()
	assert(bool(merchant.configure(_content_fingerprint).get("ok", false)))
	var build := RunBuildStateScript.new().to_dictionary()
	var completed_floor_ids: Array[String] = []
	for floor_index: int in range(int(plan["floor_index"])):
		completed_floor_ids.append(SaveEnvelopeScript.FLOOR_IDS[floor_index])
	return {
		"schema_version": 1,
		"run_id": run_id,
		"revision": _global_revision,
		"phase": 11,
		"suspended": false,
		"run_seed": int(plan["run_seed"]),
		"current_floor": int(plan["floor_index"]) + 1,
		"current_room": (plan["selected_edge_ids"] as Array).size(),
		"room_total": _plan_room_total(plan),
		"run_time_ms": 0,
		"resources": {
			"resource": (participants["resource"] as Dictionary).duplicate(true),
			"health": (participants["health"] as Dictionary).duplicate(true),
		},
		"stats": {"kills": 0},
		"events": [],
		"build": build,
		"open_offer": {},
		"consumed_offer_ids": [],
		"result": {},
		"config": {"milestone": "LAUNCH"},
		"current_floor_index": int(plan["floor_index"]),
		"floor_plan": plan.duplicate(true),
		"completed_floor_ids": completed_floor_ids,
		"run_economy": (participants["economy"] as Dictionary).duplicate(true),
		"seen_event_ids": (
			(participants["event_state"] as Dictionary)["seen_run_event_ids"] as Array
		).duplicate(),
		"dungeon_event_runtime": runtime_snapshot,
		"merchant_state": merchant.snapshot(),
		"floor_rule_state": {},
	}


func _runtime_fixture(
	plan: Dictionary, kind: String, run_id: String,
	definition_overrides: Dictionary = {}, inactive: bool = false
) -> Dictionary:
	_global_revision = 10
	_published_fact_ids.clear()
	var definition := _event_definition(kind, str(definition_overrides.get("definition_id", "")))
	for field: String in definition_overrides:
		match field:
			"option_id": definition["options"][0]["id"] = definition_overrides[field]
			"outcome_id": definition["options"][0]["outcomes"][0]["id"] = definition_overrides[field]
			"outcome_key": definition["options"][0]["outcomes"][0]["outcome_key"] = definition_overrides[field]
			"repeat_policy", "floor_max": definition[field] = definition_overrides[field]
			"floor_min":
				definition[field] = definition_overrides[field]
				for option: Dictionary in definition["options"]:
					for requirement: Dictionary in option["requirements"]:
						if str(requirement["operation"]) == "floor_index_min":
							requirement["arguments"]["value"] = definition_overrides[field]
	var runtime_definitions: Array[Dictionary] = [definition]
	if inactive and not bool(definition_overrides.get("advance_floor_only", false)):
		var next_definition := _event_definition("immediate")
		next_definition["trigger_predicate_id"] = "rich"
		runtime_definitions.append(next_definition)
	var node := _node_by_id(plan, str(plan["current_node_id"]))
	_provider_context = {
		"global_revision": _global_revision,
		"selection": {
			"run_seed": int(plan["run_seed"]),
			"availability": "LAUNCH",
			"floor_id": str(plan["floor_id"]),
			"floor_index": int(plan["floor_index"]),
			"node_id": str(node["id"]),
			"primary_event_id": str(node["event_id"]),
			"health": {"current": 80.0, "maximum": 100.0},
			"economy": {"gold": 100},
			"build": {"curse_ids": []},
			"resources": {"time_shard": 2, "forge_essence": 1},
			"flags": {},
			"meta": {"perfect_rewind_available": false, "old_reunion_eligible": false},
			"seen_run_event_ids": [],
			"seen_floor_event_keys": [],
		},
		"requirements": {
			"resources": {"time_shard": 2, "forge_essence": 1},
			"health": {"current": 80.0, "maximum": 100.0},
			"gold": 100,
			"reward_tags": [],
			"curse_ids": [],
			"narrative_flags": {},
			"floor_index": int(plan["floor_index"]),
		},
	}
	var resource = EventResourceAuthorityScript.new()
	assert(resource.configure({"time_shard": 2, "forge_essence": 1}))
	var health = EventHealthAuthorityScript.new()
	assert(health.configure(80.0, 100.0))
	var economy = RunEconomyStateScript.new()
	assert(bool(economy.configure(_economy_profile(), 100).get("ok", false)))
	var modifier = EventModifierAuthorityScript.new()
	assert(modifier.configure([], {}, []))
	var route = EventRouteAuthorityScript.new()
	assert(route.configure(plan))
	var event_state = DungeonEventRunStateScript.new()
	assert(bool(event_state.configure(_content_fingerprint).get("ok", false)))
	var consequence = ConsequenceRuntimeScript.new()
	assert(consequence.configure(resource, health, economy, modifier, route, event_state))
	var runtime = DungeonEventRuntimeScript.new()
	assert(runtime.configure(
		runtime_definitions, DungeonEventSelectorScript.new(), event_state,
		EventRequirementServiceScript.new(), consequence,
		Callable(self, "_provide_context"), Callable(self, "_commit_state"),
		Callable(self, "_publish_fact"), _digest_canonical({
			"schema": "event_publication_secret_v1",
			"content_fingerprint": _content_fingerprint,
			"run_id": run_id,
			"run_seed": int(plan["run_seed"]),
		})
	))
	return {"runtime": runtime, "event_state": event_state, "definition": definition, "route": route}


func _replace_event_identity(value: Variant, source: String, replacement: String) -> Variant:
	if value is Dictionary:
		var result := {}
		for key: Variant in value:
			result[key] = _replace_event_identity(value[key], source, replacement)
		return result
	if value is Array:
		var result: Array = []
		for child: Variant in value:
			result.append(_replace_event_identity(child, source, replacement))
		return result
	if typeof(value) == TYPE_STRING:
		var text := str(value)
		if text == source or text.ends_with(":" + source):
			return text.trim_suffix(source) + replacement
	return value


func _event_definition(kind: String, definition_id: String = "") -> Dictionary:
	var id := "event_chronal_altar"
	if kind == "reward":
		id = "event_trapped_traveler"
	elif kind == "encounter":
		id = "event_sleeping_guardian"
	if not definition_id.is_empty():
		id = definition_id
	for definition: Dictionary in _definitions:
		if str(definition["id"]) == id:
			return definition.duplicate(true)
	return {}


func _digest_canonical(value: Variant) -> String:
	return var_to_bytes(_canonical_value(value)).hex_encode().sha256_text()


func _canonical_value(value: Variant) -> Variant:
	if value is Dictionary:
		var normalized: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key: Variant in keys:
			normalized[key] = _canonical_value(value[key])
		return normalized
	if value is Array:
		var normalized: Array = []
		for child: Variant in value:
			normalized.append(_canonical_value(child))
		return normalized
	return value


func _provide_context() -> Dictionary:
	_provider_context["global_revision"] = _global_revision
	return _provider_context.duplicate(true)


func _commit_state(_command: Dictionary, expected_revision: int) -> Dictionary:
	if expected_revision != _global_revision:
		return {"ok": false, "code": &"STALE_REVISION", "new_revision": _global_revision, "context": {}}
	_global_revision += 1
	_provider_context["global_revision"] = _global_revision
	return {"ok": true, "code": &"OK", "new_revision": _global_revision, "context": {}}


func _publish_fact(fact_id: String, _payload: Dictionary) -> bool:
	_published_fact_ids[fact_id] = true
	return true


func _event_floor_plan(floor_index: int = 0) -> Dictionary:
	var floors := _read_json_array(FLOOR_PATH)
	var templates := _read_json_array(TEMPLATE_PATH)
	if floor_index < 0 or floor_index >= floors.size() or templates.is_empty():
		return {}
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261002, floors[floor_index], templates)
	if not bool(generated.get("ok", false)):
		return {}
	var model = FloorPlanScript.new()
	if not bool(model.configure(generated["plan"], floors[floor_index], templates).get("ok", false)):
		return {}
	var path := _path_to_room_type(model.snapshot(), "event")
	if path.is_empty():
		return {}
	for edge_value: Variant in path:
		var edge := edge_value as Dictionary
		if not bool(model.select_edge(StringName(str(edge["id"])), model.revision()).get("ok", false)):
			return {}
		var current := _node_by_id(model.snapshot(), str(model.snapshot()["current_node_id"]))
		if str(current.get("room_type", "")) == "event":
			return model.snapshot()
		var cleared := model.snapshot()
		for node_value: Variant in cleared["nodes"]:
			var node := node_value as Dictionary
			if str(node["id"]) == str(cleared["current_node_id"]):
				node["cleared"] = true
				break
		if not bool(model.configure(cleared, floors[floor_index], templates).get("ok", false)):
			return {}
	return {}


func _path_to_room_type(plan: Dictionary, room_type: String) -> Array[Dictionary]:
	var outgoing: Dictionary = {}
	for edge_value: Variant in plan.get("edges", []):
		var edge := edge_value as Dictionary
		var source := str(edge["source_node_id"])
		if not outgoing.has(source):
			outgoing[source] = []
		(outgoing[source] as Array).append(edge.duplicate(true))
	for source_value: Variant in outgoing.keys():
		(outgoing[source_value] as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return int(left["choice_order"]) < int(right["choice_order"])
		)
	var queue: Array[Dictionary] = [{"node_id": str(plan["current_node_id"]), "path": []}]
	var visited: Dictionary = {}
	while not queue.is_empty():
		var cursor := queue.pop_front() as Dictionary
		var node_id := str(cursor["node_id"])
		if visited.has(node_id):
			continue
		visited[node_id] = true
		if str(_node_by_id(plan, node_id).get("room_type", "")) == room_type:
			var result: Array[Dictionary] = []
			for edge_value: Variant in cursor["path"]:
				result.append((edge_value as Dictionary).duplicate(true))
			return result
		for edge_value: Variant in outgoing.get(node_id, []):
			var next_path := (cursor["path"] as Array).duplicate(true)
			next_path.append((edge_value as Dictionary).duplicate(true))
			queue.append({
				"node_id": str((edge_value as Dictionary)["destination_node_id"]),
				"path": next_path,
			})
	return []


func _economy_with_delta(before: Dictionary, transaction_id: String, amount: int) -> Dictionary:
	var authority = RunEconomyStateScript.new()
	assert(bool(authority.configure(_economy_profile(), int(before["initial_gold"])).get("ok", false)))
	assert(authority.restore_snapshot(before))
	var prepared: Dictionary = authority.prepare_transaction(
		transaction_id, amount, authority.revision(), {"operation": "gold_delta"}
	)
	assert(bool(prepared.get("ok", false)))
	assert(bool(authority.commit_transaction(prepared["ticket"]).get("ok", false)))
	return authority.snapshot()


func _revealed_route_snapshot(before: Dictionary) -> Dictionary:
	var authority = EventRouteAuthorityScript.new()
	assert(authority.configure(before["plan"]))
	assert(authority.restore_snapshot(before))
	var prepared: Dictionary = authority.prepare_operations(
		"save_drift_route", [{"operation": "map_reveal", "arguments": {"depth": 1}}],
		int(before["revision"])
	)
	assert(bool(prepared.get("ok", false)))
	assert(bool(authority.commit_operations(prepared["ticket"]).get("ok", false)))
	return authority.snapshot()


func _resource_with_delta(before: Dictionary) -> Dictionary:
	var authority = EventResourceAuthorityScript.new()
	assert(authority.configure((before["resources"] as Dictionary).duplicate(true)))
	assert(authority.restore_snapshot(before))
	var prepared: Dictionary = authority.prepare_delta(
		"save_drift_resource", &"time_shard", 1, int(before["revision"])
	)
	assert(bool(prepared.get("ok", false)))
	assert(bool(authority.commit_delta(prepared["ticket"]).get("ok", false)))
	return authority.snapshot()


func _health_with_delta(before: Dictionary) -> Dictionary:
	var authority = EventHealthAuthorityScript.new()
	assert(authority.configure(float(before["current"]), float(before["maximum"])))
	assert(authority.restore_snapshot(before))
	var prepared: Dictionary = authority.prepare_delta(
		"save_drift_health", -1.0, true, int(before["revision"])
	)
	assert(bool(prepared.get("ok", false)))
	assert(bool(authority.commit_delta(prepared["ticket"]).get("ok", false)))
	return authority.snapshot()


func _participants(run: Dictionary) -> Dictionary:
	return _participants_from_runtime(run["dungeon_event_runtime"] as Dictionary)


func _participants_from_runtime(runtime_snapshot: Dictionary) -> Dictionary:
	return (
		(runtime_snapshot["consequence_runtime"] as Dictionary)["participant_snapshots"]
		as Dictionary
	)


func _event_state_snapshot(runtime_snapshot: Dictionary) -> Dictionary:
	return _participants_from_runtime(runtime_snapshot)["event_state"] as Dictionary


func _node_by_id(plan: Dictionary, node_id: String) -> Dictionary:
	for value: Variant in plan.get("nodes", []):
		if value is Dictionary and str((value as Dictionary).get("id", "")) == node_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _plan_room_total(plan: Dictionary) -> int:
	return int(_node_by_id(plan, str(plan.get("boss_node_id", ""))).get("layer", 5))


func _economy_profile() -> Dictionary:
	var profiles := _read_json_array(ECONOMY_PATH)
	return (profiles[0] as Dictionary).duplicate(true) if profiles.size() == 1 else {}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _read_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Array).duplicate(true) if parsed is Array else []


func _resign(document: Dictionary) -> void:
	var unsigned := document.duplicate(true)
	unsigned.erase("integrity")
	document["integrity"] = {
		"algorithm": "sha256",
		"digest": SaveEnvelopeScript.sha256_digest(unsigned),
	}
