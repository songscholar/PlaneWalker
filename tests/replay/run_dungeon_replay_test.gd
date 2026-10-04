extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const RunEconomyStateScript := preload("res://scripts/economy/run_economy_state.gd")
const DungeonEventRunStateScript := preload(
	"res://scripts/events/dungeon_event_run_state.gd"
)
const DungeonEventRuntimeScript := preload("res://scripts/events/dungeon_event_runtime.gd")
const DungeonEventSelectorScript := preload("res://scripts/events/dungeon_event_selector.gd")
const EventRequirementServiceScript := preload("res://scripts/events/event_requirement_service.gd")
const ConsequenceRuntimeScript := preload("res://scripts/events/dungeon_event_consequence_runtime.gd")
const EventResourceAuthorityScript := preload("res://scripts/events/event_resource_authority.gd")
const EventHealthAuthorityScript := preload("res://scripts/events/event_health_authority.gd")
const EventModifierAuthorityScript := preload("res://scripts/events/event_modifier_authority.gd")
const EventRouteAuthorityScript := preload("res://scripts/events/event_route_authority.gd")
const DungeonEventDefinitionScript := preload("res://scripts/dungeon/dungeon_event_definition.gd")
const CrumblingGroundRuleScript := preload(
	"res://scripts/dungeon/floor_rules/crumbling_ground_rule.gd"
)

const SEAL_PATH := "res://scripts/replay/run_dungeon_replay_seal.gd"
const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"
const PUBLICATION_SECRET := "task7-replay-publication-secret-0123456789abcdef0123456789abcdef"

var _event_global_revision := 10
var _event_provider_context: Dictionary = {}
var _accept_event_facts := true


class DriftRegistry:
	extends RefCounted

	var base: RefCounted
	var floors_override: Array[Dictionary] = []
	var room_overrides: Dictionary = {}
	var event_overrides: Dictionary = {}
	var packs_override: Array[Dictionary] = []

	func _init(p_base: RefCounted) -> void:
		base = p_base

	func active_packs() -> Array[Dictionary]:
		return packs_override.duplicate(true) if not packs_override.is_empty() else base.call("active_packs")

	func resolve_room_template(content_id: StringName) -> Dictionary:
		var key := str(content_id)
		return (
			(room_overrides[key] as Dictionary).duplicate(true)
			if room_overrides.has(key)
			else base.call("resolve_room_template", content_id)
		)

	func resolve_dungeon_event(content_id: StringName) -> Dictionary:
		var key := str(content_id)
		return (
			(event_overrides[key] as Dictionary).duplicate(true)
			if event_overrides.has(key)
			else base.call("resolve_dungeon_event", content_id)
		)

	func resolve_economy_profile(content_id: StringName) -> Dictionary:
		return base.call("resolve_economy_profile", content_id)

	func get_floor_definitions(availability: StringName = &"") -> Array[Dictionary]:
		if not floors_override.is_empty():
			return floors_override.duplicate(true)
		return base.call("get_floor_definitions", availability)

	func get_by_category(
		category: StringName,
		availability: StringName = &""
	) -> Array[Dictionary]:
		return base.call("get_by_category", category, availability)


class AcceptingFloorRuleEffectAuthority:
	extends RefCounted

	func commit_floor_rule_effects(_facts: Array) -> bool:
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	suite.assert_true(FileAccess.file_exists(SEAL_PATH), "dungeon Replay seal authority exists")
	var seal_script: Variant = load(SEAL_PATH) if FileAccess.file_exists(SEAL_PATH) else null
	suite.assert_true(seal_script != null, "dungeon Replay seal authority loads")
	if seal_script == null:
		suite.finish(get_tree())
		return

	var registry = ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": "res://data/content_packs/base/pack.json", "required": true}],
		"0.4.0-dev",
		&"LAUNCH"
	)
	suite.assert_true(not report.has_blocking_errors(), "dungeon Replay fixture loads Base Pack")
	if report.has_blocking_errors():
		suite.finish(get_tree())
		return

	var floors: Array = _load_json_array(FLOOR_PATH)
	var templates: Array = _load_json_array(TEMPLATE_PATH)
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261001, floors[0], templates)
	suite.assert_true(bool(generated.get("ok", false)), "dungeon Replay fixture generates a plan")
	if not bool(generated.get("ok", false)):
		suite.finish(get_tree())
		return

	var floor_plan = FloorPlanScript.new()
	suite.assert_true(
		bool(floor_plan.configure(generated["plan"], floors[0], templates).get("ok", false)),
		"dungeon Replay fixture configures FloorPlan"
	)
	var selected_event_node := false
	while floor_plan.snapshot().get("current_node_id") != floor_plan.snapshot().get("boss_node_id"):
		var before_selection: Dictionary = floor_plan.snapshot()
		var next_edge: Dictionary = _first_open_edge(before_selection)
		var selected: Dictionary = floor_plan.select_edge(
			StringName(str(next_edge.get("id", ""))), floor_plan.revision()
		)
		suite.assert_true(bool(selected.get("ok", false)), "dungeon Replay fixture advances its route")
		if not bool(selected.get("ok", false)):
			break
		var selected_node: Dictionary = _node_by_id(
			floor_plan.snapshot(), str(floor_plan.snapshot().get("current_node_id", ""))
		)
		var cleared_plan: Dictionary = floor_plan.snapshot()
		for node_value: Variant in cleared_plan.get("nodes", []):
			var node := node_value as Dictionary
			if str(node.get("id", "")) == str(cleared_plan.get("current_node_id", "")):
				node["cleared"] = true
				break
		suite.assert_true(
			bool(floor_plan.configure(cleared_plan, floors[0], templates).get("ok", false)),
			"dungeon Replay fixture seals each cleared historical room"
		)
		if str(selected_node.get("room_type", "")) == "event":
			selected_event_node = true
			break
	suite.assert_true(selected_event_node, "dungeon Replay fixture reaches an event on its route")
	var plan: Dictionary = floor_plan.snapshot()
	var route_prefix: Array = plan.get("selected_edge_ids", []).duplicate(true)
	var room_facts: Array = _room_fact_inputs_for_plan(plan)
	var run_economy: Dictionary = _run_economy_fixture(registry)
	var merchant_state: Dictionary = _merchant_state_fixture()
	suite.assert_true(not run_economy.is_empty(), "dungeon Replay economy fixture is authoritative")
	suite.assert_true(not merchant_state.is_empty(), "dungeon Replay merchant fixture is authoritative")
	suite.assert_true(
		bool(seal_script.new().call("_run_economy_is_valid", run_economy, registry)),
		"dungeon Replay economy fixture restores through its authority"
	)
	suite.assert_true(
		bool(seal_script.new().call("_merchant_state_is_valid", merchant_state)),
		"dungeon Replay merchant fixture restores through its authority"
	)
	var seal: RefCounted = seal_script.new(PUBLICATION_SECRET)
	var event_resolutions: Dictionary = _dungeon_event_runtime_for_plan(registry, plan)
	suite.assert_true(
		not event_resolutions.is_empty(),
		"dungeon Replay fixture owns a complete event runtime snapshot"
	)
	var replay_event_state := _event_state_from_runtime(event_resolutions)
	var replay_assignments := replay_event_state.get("selected_event_by_node", {}) as Dictionary
	var replay_assignment := (
		(replay_assignments.values()[0] as Dictionary)
		if not replay_assignments.is_empty()
		else {}
	)
	suite.assert_true(
		not replay_assignment.is_empty()
		and str(replay_assignment.get("event_id", ""))
		!= str(_node_by_id(plan, str(replay_assignment.get("node_id", ""))).get("event_id", "")),
		"Replay fixture proves actual selection may differ from the FloorPlan primary candidate"
	)
	var floor_transitions: Array = [
		{
			"sequence": 0,
			"from_floor_id": "",
			"to_floor_id": str(plan["floor_id"]),
			"completed_plan_digest": "",
		},
	]
	var snapshot: Dictionary = seal.call(
		"capture",
		registry,
		plan,
		route_prefix,
		room_facts,
		run_economy,
		merchant_state,
		event_resolutions,
		floor_transitions
	)
	if snapshot.is_empty():
		suite.assert_true(false, "canonical dungeon Replay snapshot captures")
		suite.finish(get_tree())
		return
	var legacy_merchant_state := _merchant_state_fixture(false)
	suite.assert_true(
		not seal.call(
			"capture", registry, plan, route_prefix, room_facts, run_economy,
			legacy_merchant_state, event_resolutions, floor_transitions
		).is_empty(),
		"Replay v3 retains the heal-only service snapshot compatibility path"
	)
	suite.assert_equal(snapshot.get("schema_id"), "planewalker.run_dungeon_replay", "seal owns schema id")
	suite.assert_equal(snapshot.get("schema_version"), 3, "seal owns schema version")
	suite.assert_equal(snapshot.get("generator_version"), "floor_plan_v1", "seal owns generator version")
	suite.assert_equal(snapshot.get("plan_digest"), plan.get("generation_digest"), "seal owns plan digest")
	suite.assert_equal(snapshot.get("route_prefix"), route_prefix, "seal owns route prefix")
	suite.assert_equal(
		(snapshot.get("room_facts", []) as Array).size(),
		room_facts.size(),
		"seal owns the complete canonical room-fact log"
	)
	suite.assert_equal(str(snapshot.get("economy_state_digest", "")).length(), 64, "seal owns full economy digest")
	suite.assert_equal(str(snapshot.get("merchant_state_digest", "")).length(), 64, "seal owns merchant-state digest")
	suite.assert_equal(
		snapshot.get("merchant_transaction_facts"),
		_merchant_transaction_facts_fixture(),
		"seal owns the globally ordered merchant transaction facts"
	)
	suite.assert_equal(str(snapshot.get("event_runtime_digest", "")).length(), 64, "seal owns full event runtime digest")
	suite.assert_equal((snapshot.get("event_assignment_facts", []) as Array).size(), 1, "seal owns actual selected-event facts")
	suite.assert_equal((snapshot.get("event_outcome_facts", []) as Array).size(), 1, "seal owns authored outcome facts")
	suite.assert_equal((snapshot.get("event_transaction_facts", []) as Array).size(), 1, "seal owns completed event transactions")
	suite.assert_equal((snapshot.get("event_receipt_facts", []) as Array).size(), 1, "seal owns committed consequence receipts")
	suite.assert_equal((snapshot.get("event_publication_facts", []) as Array).size(), 2, "seal owns complete event publication facts")
	suite.assert_equal(snapshot.get("floor_transitions"), floor_transitions, "seal owns floor transitions")
	suite.assert_equal(str(snapshot.get("snapshot_digest", "")).length(), 64, "seal authenticates historical bytes")

	var valid: Dictionary = seal.call(
		"validate", snapshot, registry, plan, run_economy, merchant_state,
		event_resolutions
	)
	suite.assert_true(bool(valid.get("ok", false)), "valid dungeon Replay seal verifies")
	suite.assert_equal(valid.get("snapshot"), snapshot, "validation returns byte-identical historical snapshot")
	_test_room_completion_history_binding(suite, seal, registry, plan, route_prefix, room_facts, run_economy, merchant_state, event_resolutions, floor_transitions)
	_test_resigned_event_fact_drift(
		suite, seal, snapshot, registry, plan, run_economy,
		merchant_state, event_resolutions
	)
	_test_event_runtime_phases(
		suite, seal, registry, plan, run_economy, merchant_state, floor_transitions
	)
	_test_event_runtime_authority_rejections(
		suite, seal, snapshot, registry, plan, run_economy,
		merchant_state, event_resolutions, floor_transitions
	)
	_test_event_route_skip_history(suite, seal, registry, floors, templates, run_economy, merchant_state)
	_test_floor_rule_replay_round_trip(
		suite, seal, registry, plan, route_prefix, room_facts,
		run_economy, merchant_state, event_resolutions, floor_transitions
	)

	var forged_plan := _resigned_plan_with_reordered_siblings(plan)
	suite.assert_true(not forged_plan.is_empty(), "forged-plan fixture can alter canonical generation bytes")
	if not forged_plan.is_empty():
		var resigned_plan_snapshot := snapshot.duplicate(true)
		resigned_plan_snapshot["plan_digest"] = str(forged_plan["generation_digest"])
		resigned_plan_snapshot["snapshot_digest"] = seal.call(
			"snapshot_digest", resigned_plan_snapshot
		)
		_assert_rejected(
			suite, seal, resigned_plan_snapshot, registry, forged_plan,
			run_economy, merchant_state, event_resolutions, &"PLAN_DIGEST_MISMATCH",
			"re-signed non-canonical plan"
		)
		suite.assert_equal(
			seal.call(
				"capture", registry, forged_plan, route_prefix, room_facts,
				run_economy, merchant_state, event_resolutions, floor_transitions
			),
			{},
			"capture rejects a self-consistent but non-canonical generated plan"
		)

	var floor_authority_drift = DriftRegistry.new(registry)
	floor_authority_drift.floors_override = registry.get_floor_definitions(&"LAUNCH")
	floor_authority_drift.floors_override[0]["boss_encounter_id"] = (
		"boss_encounter_forged_adapter_v1"
	)
	_assert_rejected(
		suite, seal, snapshot, floor_authority_drift, plan,
		run_economy, merchant_state, event_resolutions, &"PLAN_DIGEST_MISMATCH",
		"registry floor authority drift"
	)

	var deleted_room_fact := snapshot.duplicate(true)
	(deleted_room_fact["room_facts"] as Array).remove_at(
		(deleted_room_fact["room_facts"] as Array).size() - 1
	)
	deleted_room_fact["snapshot_digest"] = seal.call("snapshot_digest", deleted_room_fact)
	_assert_rejected(
		suite, seal, deleted_room_fact, registry, plan, run_economy, merchant_state, event_resolutions,
		&"ROOM_FACT_INVALID", "re-signed missing room fact"
	)

	var reordered_room_facts := snapshot.duplicate(true)
	var reordered_facts := reordered_room_facts["room_facts"] as Array
	if reordered_facts.size() >= 2:
		var first_fact: Variant = reordered_facts[0]
		reordered_facts[0] = reordered_facts[1]
		reordered_facts[1] = first_fact
		reordered_room_facts["snapshot_digest"] = seal.call(
			"snapshot_digest", reordered_room_facts
		)
		_assert_rejected(
			suite, seal, reordered_room_facts, registry, plan,
			run_economy, merchant_state, event_resolutions, &"ROOM_FACT_INVALID",
			"re-signed reordered room facts"
		)

	var replaced_room_fact := snapshot.duplicate(true)
	(replaced_room_fact["room_facts"] as Array)[0]["node_id"] = "boss"
	replaced_room_fact["snapshot_digest"] = seal.call(
		"snapshot_digest", replaced_room_fact
	)
	_assert_rejected(
		suite, seal, replaced_room_fact, registry, plan,
		run_economy, merchant_state, event_resolutions, &"ROOM_FACT_INVALID",
		"re-signed room fact outside the selected route order"
	)

	var uncleared_plan := _with_current_node_cleared(plan, false)
	_assert_rejected(
		suite, seal, snapshot, registry, uncleared_plan, run_economy, merchant_state, event_resolutions,
		&"ROOM_FACT_INVALID", "room clear fact contradicts current FloorPlan state"
	)

	var forged_transition := snapshot.duplicate(true)
	(forged_transition["floor_transitions"] as Array)[0]["to_floor_id"] = "floor_forged"
	forged_transition["snapshot_digest"] = seal.call("snapshot_digest", forged_transition)
	_assert_rejected(
		suite, seal, forged_transition, registry, plan, run_economy, merchant_state, event_resolutions,
		&"FLOOR_TRANSITION_INVALID", "re-signed fictional floor transition"
	)
	var missing_transition := snapshot.duplicate(true)
	(missing_transition["floor_transitions"] as Array).clear()
	missing_transition["snapshot_digest"] = seal.call(
		"snapshot_digest", missing_transition
	)
	_assert_rejected(
		suite, seal, missing_transition, registry, plan,
		run_economy, merchant_state, event_resolutions, &"FLOOR_TRANSITION_INVALID",
		"re-signed transition chain deletion"
	)

	_test_later_floor_transition_authority(
		suite, seal, registry, floors, templates, run_economy, merchant_state, event_resolutions
	)

	var duplicate_economy := run_economy.duplicate(true)
	duplicate_economy["ledger"].append(duplicate_economy["ledger"][0].duplicate(true))
	var duplicate_index: int = (duplicate_economy["ledger"] as Array).size() - 1
	duplicate_economy["ledger"][duplicate_index]["revision"] = 5
	duplicate_economy["revision"] = 5
	duplicate_economy["balance"] += int(
		duplicate_economy["ledger"][duplicate_index]["amount"]
	)
	var duplicate_economy_snapshot := snapshot.duplicate(true)
	duplicate_economy_snapshot["economy_state_digest"] = ReplayRecorderScript.value_digest(
		duplicate_economy
	)
	duplicate_economy_snapshot["snapshot_digest"] = seal.call(
		"snapshot_digest", duplicate_economy_snapshot
	)
	_assert_rejected(
		suite, seal, duplicate_economy_snapshot, registry, plan,
		duplicate_economy, merchant_state, event_resolutions, &"ECONOMY_STATE_INVALID",
		"duplicate economy transaction id"
	)
	var invalid_economy := run_economy.duplicate(true)
	invalid_economy["ledger"][0]["operation"] = "mint_everything"
	suite.assert_equal(
		seal.call(
			"capture", registry, plan, route_prefix, room_facts,
			invalid_economy, merchant_state, event_resolutions, floor_transitions
		),
		{},
		"capture rejects unsupported economy operations"
	)
	var extra_field_economy := run_economy.duplicate(true)
	extra_field_economy["ledger"][0]["memo"] = "forged"
	suite.assert_equal(
		seal.call(
			"capture", registry, plan, route_prefix, room_facts,
			extra_field_economy, merchant_state, event_resolutions, floor_transitions
		),
		{},
		"capture rejects economy entries outside the closed field set"
	)
	var zero_amount_economy := run_economy.duplicate(true)
	zero_amount_economy["ledger"][0]["amount"] = 0
	suite.assert_equal(
		seal.call(
			"capture", registry, plan, route_prefix, room_facts,
			zero_amount_economy, merchant_state, event_resolutions, floor_transitions
		),
		{},
		"capture rejects zero-value economy transactions"
	)
	var skipped_revision_economy := run_economy.duplicate(true)
	skipped_revision_economy["ledger"][0]["revision"] = 2
	suite.assert_equal(
		seal.call(
			"capture", registry, plan, route_prefix, room_facts,
			skipped_revision_economy, merchant_state, event_resolutions, floor_transitions
		),
		{},
		"capture rejects non-contiguous economy revisions"
	)

	var wrong_event_node := event_resolutions.duplicate(true)
	var wrong_event_state := _event_state_from_runtime(wrong_event_node)
	var wrong_assignments := wrong_event_state["selected_event_by_node"] as Dictionary
	var wrong_key := str(wrong_assignments.keys()[0])
	var wrong_assignment := (wrong_assignments[wrong_key] as Dictionary).duplicate(true)
	wrong_assignment["node_id"] = "boss"
	wrong_assignments.erase(wrong_key)
	wrong_assignments["%s:boss" % str(plan.get("floor_id", ""))] = wrong_assignment
	suite.assert_equal(
		seal.call(
			"capture", registry, plan, route_prefix, room_facts,
			run_economy, merchant_state, wrong_event_node, floor_transitions
		),
		{},
		"capture rejects event assignments outside the selected event route"
	)

	var unauthenticated := snapshot.duplicate(true)
	unauthenticated["route_prefix"] = ["forged_edge"]
	var unauthenticated_result: Dictionary = seal.call(
		"validate", unauthenticated, registry, plan, run_economy, merchant_state,
		event_resolutions
	)
	suite.assert_equal(
		unauthenticated_result.get("code"),
		&"SNAPSHOT_DIGEST_MISMATCH",
		"historical bytes authenticate before semantic normalization"
	)

	var invalid_route := snapshot.duplicate(true)
	invalid_route["route_prefix"] = ["forged_edge"]
	invalid_route["snapshot_digest"] = seal.call("snapshot_digest", invalid_route)
	_assert_rejected(
		suite, seal, invalid_route, registry, plan, run_economy, merchant_state, event_resolutions,
		&"ROUTE_PREFIX_INVALID", "invalid route prefix"
	)

	var unknown_generator := snapshot.duplicate(true)
	unknown_generator["generator_version"] = "floor_plan_v999"
	unknown_generator["snapshot_digest"] = seal.call("snapshot_digest", unknown_generator)
	_assert_rejected(
		suite, seal, unknown_generator, registry, plan, run_economy, merchant_state, event_resolutions,
		&"GENERATOR_VERSION_UNSUPPORTED", "unknown generator"
	)

	var changed_plan := plan.duplicate(true)
	changed_plan["generation_digest"] = "0".repeat(64)
	_assert_rejected(
		suite, seal, snapshot, registry, changed_plan, run_economy, merchant_state, event_resolutions,
		&"PLAN_DIGEST_MISMATCH", "plan digest drift"
	)

	var changed_economy := run_economy.duplicate(true)
	changed_economy["ledger"][0]["amount"] = 301
	changed_economy["balance"] += 1
	_assert_rejected(
		suite, seal, snapshot, registry, plan, changed_economy, merchant_state,
		event_resolutions, &"ECONOMY_STATE_DRIFT", "full economy state drift"
	)

	var sold_drift := merchant_state.duplicate(true)
	sold_drift["nodes"][0]["inventory"]["offers"][0]["sold"] = false
	_assert_rejected(
		suite, seal, snapshot, registry, plan, run_economy, sold_drift,
		event_resolutions, &"MERCHANT_SOLD_STATE_DRIFT", "merchant sold-state drift",
		"sold_offer_ids"
	)
	var reroll_drift := merchant_state.duplicate(true)
	reroll_drift["nodes"][0]["inventory"]["reroll_count"] = 2
	_assert_rejected(
		suite, seal, snapshot, registry, plan, run_economy, reroll_drift,
		event_resolutions, &"MERCHANT_REROLL_STATE_DRIFT", "merchant reroll-count drift",
		"reroll_count"
	)
	var completed_drift := merchant_state.duplicate(true)
	completed_drift["nodes"][0]["runtime"]["completed_transaction_ids"].append(
		"tx_service_9999"
	)
	_assert_rejected(
		suite, seal, snapshot, registry, plan, run_economy, completed_drift,
		event_resolutions, &"MERCHANT_COMPLETED_TRANSACTION_DRIFT",
		"merchant completed-transaction drift", "completed_transaction_ids"
	)
	var transaction_drift := merchant_state.duplicate(true)
	transaction_drift["nodes"][0]["transactions"][0]["inventory_revision"] = 9
	_assert_rejected(
		suite, seal, snapshot, registry, plan, run_economy, transaction_drift,
		event_resolutions, &"MERCHANT_TRANSACTION_DRIFT",
		"merchant ordered transaction-fact drift", "transactions"
	)
	var sell_payout_drift := merchant_state.duplicate(true)
	sell_payout_drift["nodes"][0]["transactions"][2]["amount"] = 51
	suite.assert_equal(
		seal.call(
			"capture", registry, plan, route_prefix, room_facts, run_economy,
			sell_payout_drift, event_resolutions, floor_transitions
		),
		{},
		"capture rejects sold-reward payout drift against the positive gold delta"
	)
	var forged_sell_snapshot := snapshot.duplicate(true)
	forged_sell_snapshot["merchant_state_digest"] = ReplayRecorderScript.value_digest(
		sell_payout_drift
	)
	forged_sell_snapshot["merchant_transaction_facts"] = seal.call(
		"_merchant_transaction_facts", sell_payout_drift
	)
	forged_sell_snapshot["snapshot_digest"] = seal.call(
		"snapshot_digest", forged_sell_snapshot
	)
	_assert_rejected(
		suite, seal, forged_sell_snapshot, registry, plan, run_economy,
		sell_payout_drift, event_resolutions, &"MERCHANT_ECONOMY_DRIFT",
		"re-signed sold-reward payout drift"
	)

	var event_definition_drift = DriftRegistry.new(registry)
	var event_id := str(replay_assignment.get("event_id", ""))
	var changed_event: Dictionary = registry.resolve_dungeon_event(StringName(event_id))
	changed_event["options"][0]["outcomes"][0]["consequences"] = [
		{"operation": "gold_delta", "arguments": {"amount": 999}},
	]
	event_definition_drift.event_overrides[event_id] = changed_event
	_assert_rejected(
		suite, seal, snapshot, event_definition_drift, plan,
		run_economy, merchant_state, event_resolutions, &"EVENT_ASSIGNMENT_DRIFT",
		"event consequence definition drift"
	)

	var fingerprint_drift = DriftRegistry.new(registry)
	fingerprint_drift.packs_override = registry.active_packs()
	fingerprint_drift.packs_override[0]["fingerprint_sha256"] = "0".repeat(64)
	_assert_rejected(
		suite, seal, snapshot, fingerprint_drift, plan, run_economy, merchant_state, event_resolutions,
		&"CONTENT_FINGERPRINT_MISMATCH", "content fingerprint drift"
	)

	var first_room_fact := (snapshot.get("room_facts", []) as Array)[0] as Dictionary
	var room_drift = DriftRegistry.new(registry)
	var room_id := str(first_room_fact.get("template_id", ""))
	var changed_room: Dictionary = registry.resolve_room_template(StringName(room_id))
	changed_room["description_key"] = "ROOM_DESCRIPTION_FORGED"
	room_drift.room_overrides[room_id] = changed_room
	_assert_rejected(
		suite, seal, snapshot, room_drift, plan, run_economy, merchant_state, event_resolutions,
		&"ROOM_DEFINITION_DRIFT", "room definition drift"
	)

	suite.finish(get_tree())


func _assert_rejected(
	suite,
	seal: RefCounted,
	snapshot: Dictionary,
	registry: Variant,
	plan: Dictionary,
	run_economy: Dictionary,
	merchant_state: Dictionary,
	event_resolutions: Dictionary,
	expected_code: StringName,
	label: String,
	expected_field: String = ""
) -> void:
	var result: Dictionary = seal.call(
		"validate", snapshot, registry, plan, run_economy, merchant_state,
		event_resolutions
	)
	suite.assert_equal(result.get("ok"), false, "%s fails closed" % label)
	suite.assert_equal(result.get("code"), expected_code, "%s reports stable code" % label)
	if not expected_field.is_empty():
		suite.assert_equal(
			(result.get("context", {}) as Dictionary).get("field"),
			expected_field,
			"%s locates the divergent merchant boundary" % label
		)


func _test_resigned_event_fact_drift(
	suite,
	seal: RefCounted,
	snapshot: Dictionary,
	registry: RefCounted,
	plan: Dictionary,
	run_economy: Dictionary,
	merchant_state: Dictionary,
	event_runtime: Dictionary
) -> void:
	var cases: Array[Dictionary] = [
		{
			"field": "event_assignment_facts",
			"member": "event_id",
			"value": "event_forged_selection",
			"code": &"EVENT_ASSIGNMENT_DRIFT",
			"label": "re-signed selected-event drift",
		},
		{
			"field": "event_outcome_facts",
			"member": "outcome_id",
			"value": "forged_outcome",
			"code": &"EVENT_OUTCOME_DRIFT",
			"label": "re-signed authored-outcome drift",
		},
		{
			"field": "event_transaction_facts",
			"member": "transaction_id",
			"value": "event_tx_v1:forged:999",
			"code": &"EVENT_TRANSACTION_DRIFT",
			"label": "re-signed completed-transaction drift",
		},
		{
			"field": "event_receipt_facts",
			"member": "transaction_id",
			"value": "event_tx_v1:forged:999",
			"code": &"EVENT_RECEIPT_DRIFT",
			"label": "re-signed event-receipt drift",
		},
		{
			"field": "event_publication_facts",
			"member": "fact_id",
			"value": "event_committed:event_tx_v1:forged:999",
			"code": &"EVENT_PUBLICATION_DRIFT",
			"label": "re-signed event-publication drift",
		},
		{
			"field": "event_publication_facts",
			"member": "chain_hash",
			"value": "0".repeat(64),
			"code": &"EVENT_PUBLICATION_DRIFT",
			"label": "re-signed publication authentication drift",
		},
	]
	for drift_case: Dictionary in cases:
		var forged := snapshot.duplicate(true)
		var facts := forged[drift_case["field"]] as Array
		facts[0][drift_case["member"]] = drift_case["value"]
		forged["snapshot_digest"] = seal.call("snapshot_digest", forged)
		_assert_rejected(
			suite, seal, forged, registry, plan, run_economy, merchant_state,
			event_runtime, drift_case["code"], drift_case["label"]
		)


func _test_event_runtime_phases(
	suite,
	seal: RefCounted,
	registry: RefCounted,
	plan: Dictionary,
	run_economy: Dictionary,
	merchant_state: Dictionary,
	floor_transitions: Array
) -> void:
	var active_plan := _with_current_node_cleared(plan, false)
	var room_facts := _room_fact_inputs_for_plan(active_plan)
	var snapshots: Dictionary = {}
	for phase: String in [
		"open", "reserved", "pending_reward", "pending_encounter",
		"resolved", "dismissed", "reward_completed", "encounter_completed", "pending_publication",
	]:
		var event_runtime := _dungeon_event_runtime_for_plan(registry, active_plan, phase)
		suite.assert_true(not event_runtime.is_empty(), "%s runtime fixture is authoritative" % phase)
		if event_runtime.is_empty():
			continue
		snapshots[phase] = event_runtime.duplicate(true)
		var snapshot: Dictionary = seal.call(
			"capture", registry, active_plan, active_plan["selected_edge_ids"], room_facts,
			run_economy, merchant_state, event_runtime, floor_transitions
		)
		suite.assert_true(not snapshot.is_empty(), "%s event runtime seals" % phase)
		if snapshot.is_empty():
			continue
		var validated: Dictionary = seal.call(
			"validate", snapshot, registry, active_plan, run_economy, merchant_state, event_runtime
		)
		suite.assert_true(bool(validated.get("ok", false)), "%s event runtime verifies" % phase)
		suite.assert_equal(validated.get("snapshot"), snapshot, "%s Replay values round trip" % phase)
		var completed_count := 1 if phase in [
			"resolved", "dismissed", "reward_completed", "encounter_completed", "pending_publication",
		] else 0
		suite.assert_equal(
			(snapshot["event_transaction_facts"] as Array).size(), completed_count,
			"%s seals only completed event transactions" % phase
		)
		var receipt_count := 0 if phase in ["open", "reserved"] else 1
		suite.assert_equal(
			(snapshot["event_receipt_facts"] as Array).size(), receipt_count,
			"%s seals committed consequence receipts independently from continuation completion" % phase
		)
		if phase == "pending_publication":
			suite.assert_equal((event_runtime["pending_facts"] as Array).size(), 1, "fixture retains an unacknowledged committed fact")
			var pending_publication_count := 0
			for fact: Dictionary in snapshot["event_publication_facts"]:
				if str(fact["status"]) == "pending":
					pending_publication_count += 1
			suite.assert_equal(pending_publication_count, 1, "Replay seals pending publication status")

	var pending := snapshots.get("pending_reward", {}) as Dictionary
	var reserved := _dungeon_event_runtime_for_plan(
		registry, active_plan, "reserved", "event_trapped_traveler"
	)
	var false_receipt := pending.duplicate(true)
	false_receipt["consequence_runtime"]["participant_snapshots"]["event_state"] = (
		_event_state_from_runtime(reserved).duplicate(true)
	)
	var missing_receipt := pending.duplicate(true)
	missing_receipt["consequence_runtime"]["completed_transaction_ids"] = []
	missing_receipt["consequence_runtime"]["publications"] = []
	missing_receipt["consequence_runtime"]["revision"] = 0
	missing_receipt["emitted_fact_ids"] = reserved["emitted_fact_ids"].duplicate()
	missing_receipt["publication_ledger"] = reserved["publication_ledger"].duplicate(true)
	missing_receipt["publication_digest"] = reserved["publication_digest"]
	var unknown_outcome := reserved.duplicate(true)
	var unknown_state := _event_state_from_runtime(unknown_outcome)
	var node_key := str(unknown_state["selected_event_by_node"].keys()[0])
	unknown_state["selected_event_by_node"][node_key]["outcome_id"] = "unknown_authored_outcome"
	unknown_state["pending_transaction"]["outcome_id"] = "unknown_authored_outcome"
	var mismatched_repeat := (snapshots["open"] as Dictionary).duplicate(true)
	_event_state_from_runtime(mismatched_repeat)["selected_event_by_node"][node_key]["repeat_policy"] = "repeatable"
	var wrong_schema_type := (snapshots["open"] as Dictionary).duplicate(true)
	wrong_schema_type["schema_version"] = "1"
	var wrong_encounter_type := (snapshots["open"] as Dictionary).duplicate(true)
	wrong_encounter_type["encounter_success_by_transaction"] = []
	for mutation: Dictionary in [
		{"runtime": false_receipt, "label": "reserved event with a committed consequence receipt"},
		{"runtime": missing_receipt, "label": "pending event without its committed consequence receipt"},
		{"runtime": unknown_outcome, "label": "outcome id absent from authored option outcomes"},
		{"runtime": mismatched_repeat, "label": "repeat policy differs from the authored definition"},
		{"runtime": wrong_schema_type, "label": "runtime schema version has the wrong type"},
		{"runtime": wrong_encounter_type, "label": "encounter success map has the wrong type"},
	]:
		suite.assert_true(
			(seal.call(
				"capture", registry, active_plan, active_plan["selected_edge_ids"], room_facts,
				run_economy, merchant_state, mutation["runtime"], floor_transitions
			) as Dictionary).is_empty(), "capture rejects %s" % str(mutation["label"])
		)


func _test_event_runtime_authority_rejections(
	suite,
	seal: RefCounted,
	snapshot: Dictionary,
	registry: RefCounted,
	plan: Dictionary,
	run_economy: Dictionary,
	merchant_state: Dictionary,
	event_runtime: Dictionary,
	floor_transitions: Array
) -> void:
	var mutations: Array[Dictionary] = []
	for participant: String in ["economy", "event_state", "health", "modifier", "resource", "route"]:
		for malformed: bool in [false, true]:
			var candidate := event_runtime.duplicate(true)
			var participants := candidate["consequence_runtime"]["participant_snapshots"] as Dictionary
			if malformed:
				participants[participant]["revision"] = "invalid_revision"
			else:
				participants[participant] = {}
			mutations.append({
				"runtime": candidate,
				"label": "%s %s participant" % ["malformed" if malformed else "empty", participant],
			})
	var economy_drift := event_runtime.duplicate(true)
	var economy = RunEconomyStateScript.new()
	var profile_source: Dictionary = registry.call("resolve_economy_profile", &"launch_economy_v1")
	var profile: Dictionary = {}
	for field: String in EconomyProfileScript.ROOT_FIELDS:
		profile[field] = profile_source[field]
	assert(bool(economy.configure(profile, int(run_economy["initial_gold"])).get("ok", false)))
	assert(economy.restore_snapshot(run_economy))
	var prepared: Dictionary = economy.prepare_transaction(
		"replay_economy_drift", 1, economy.revision(), {"operation": "gold_delta"}
	)
	assert(bool(prepared.get("ok", false)))
	assert(bool(economy.commit_transaction(prepared["ticket"]).get("ok", false)))
	economy_drift["consequence_runtime"]["participant_snapshots"]["economy"] = economy.snapshot()
	mutations.append({"runtime": economy_drift, "label": "restorable economy differs from seal input"})
	var route_drift := event_runtime.duplicate(true)
	var route = EventRouteAuthorityScript.new()
	assert(route.configure(_with_current_node_cleared(plan, false)))
	route_drift["consequence_runtime"]["participant_snapshots"]["route"] = route.snapshot()
	mutations.append({"runtime": route_drift, "label": "restorable route differs from seal input"})
	var projection_drift := event_runtime.duplicate(true)
	projection_drift["consequence_runtime"]["participant_snapshots"]["modifier"]["narrative_flags"] = {"forged_flag": true}
	mutations.append({"runtime": projection_drift, "label": "modifier and event flags disagree"})
	var zero_chain := event_runtime.duplicate(true)
	for entry: Dictionary in zero_chain["publication_ledger"]:
		entry["chain_hash"] = "0".repeat(64)
	zero_chain["publication_digest"] = "0".repeat(64)
	mutations.append({"runtime": zero_chain, "label": "all-zero publication chain"})
	var broken_chain := event_runtime.duplicate(true)
	broken_chain["publication_ledger"][0]["chain_hash"] = "0".repeat(64)
	mutations.append({"runtime": broken_chain, "label": "broken intermediate publication chain"})
	var wrong_identity := event_runtime.duplicate(true)
	wrong_identity["consequence_runtime"]["participant_snapshots"]["event_state"]["content_fingerprint"] = "c".repeat(64)
	mutations.append({"runtime": wrong_identity, "label": "publication content identity changed"})
	for mutation: Dictionary in mutations:
		var candidate := mutation["runtime"] as Dictionary
		suite.assert_true(
			(seal.call(
				"capture", registry, plan, plan["selected_edge_ids"], _room_fact_inputs_for_plan(plan),
			run_economy, merchant_state, candidate, floor_transitions
			) as Dictionary).is_empty(), "capture rejects %s" % str(mutation["label"])
		)
		var forged_snapshot := snapshot.duplicate(true)
		forged_snapshot["event_runtime_digest"] = ReplayRecorderScript.value_digest(candidate)
		for index: int in range((candidate["publication_ledger"] as Array).size()):
			forged_snapshot["event_publication_facts"][index]["chain_hash"] = (
				candidate["publication_ledger"][index]["chain_hash"]
			)
		forged_snapshot["snapshot_digest"] = seal.call("snapshot_digest", forged_snapshot)
		_assert_rejected(
			suite, seal, forged_snapshot, registry, plan, run_economy, merchant_state,
			candidate, &"EVENT_RUNTIME_INVALID", "re-signed validation rejects %s" % str(mutation["label"])
		)
	for secret: String in ["", "too_short", "wrong-event-publication-secret-0123456789abcdef0123456789abcdef"]:
		var wrong_key_seal: RefCounted = load(SEAL_PATH).new(secret)
		suite.assert_true((wrong_key_seal.call(
			"capture", registry, plan, plan["selected_edge_ids"], _room_fact_inputs_for_plan(plan),
			run_economy, merchant_state, event_runtime, floor_transitions
		) as Dictionary).is_empty(), "capture requires the original publication secret")
		_assert_rejected(
			suite, wrong_key_seal, snapshot, registry, plan, run_economy, merchant_state,
			event_runtime, &"EVENT_RUNTIME_INVALID", "validation rejects missing or wrong publication secret"
		)
	var empty_history := _empty_dungeon_event_runtime(registry, plan)
	suite.assert_true(
		bool(seal.call("_event_runtime_restores", registry, plan, run_economy, empty_history)),
		"erased-history fixture retains all real authorities and the original publication secret"
	)
	suite.assert_equal(
		_event_state_from_runtime(empty_history)["selected_event_by_node"], {},
		"erased-history fixture removes every event assignment"
	)
	suite.assert_true((seal.call(
		"capture", registry, plan, plan["selected_edge_ids"], _room_fact_inputs_for_plan(plan),
		run_economy, merchant_state, empty_history, floor_transitions
	) as Dictionary).is_empty(), "modern capture requires history for every cleared event node")
	var erased_modern := snapshot.duplicate(true)
	erased_modern["event_runtime_digest"] = ReplayRecorderScript.value_digest(empty_history)
	for field: String in [
		"event_assignment_facts", "event_outcome_facts", "event_transaction_facts",
		"event_receipt_facts", "event_publication_facts",
	]:
		erased_modern[field] = []
	erased_modern["snapshot_digest"] = seal.call("snapshot_digest", erased_modern)
	_assert_rejected(
		suite, seal, erased_modern, registry, plan, run_economy, merchant_state,
		empty_history, &"EVENT_RUNTIME_INVALID", "re-signed modern seal cannot erase cleared event history",
		"selected_event_by_node.missing_cleared_event"
	)
	var erased_history := snapshot.duplicate(true)
	for field: String in [
		"event_runtime_digest", "event_assignment_facts", "event_outcome_facts",
		"event_transaction_facts", "event_receipt_facts", "event_publication_facts",
	]:
		erased_history.erase(field)
	erased_history["event_resolution_digest"] = ReplayRecorderScript.value_digest([])
	erased_history["snapshot_digest"] = seal.call("snapshot_digest", erased_history)
	var erased_history_result: Dictionary = seal.call(
		"validate", erased_history, registry, plan, run_economy, merchant_state, []
	)
	suite.assert_equal(erased_history_result.get("code"), &"EVENT_RESOLUTION_INVALID", "legacy branch cannot erase cleared event history")


func _test_event_route_skip_history(
	suite,
	seal: RefCounted,
	registry: RefCounted,
	floors: Array,
	templates: Array,
	run_economy: Dictionary,
	merchant_state: Dictionary
) -> void:
	for event_position: int in [1, 2]:
		var fixture := _event_route_skip_fixture(registry, floors, templates, event_position)
		suite.assert_true(not fixture.is_empty(), "real route skip reaches event at destination %s" % event_position)
		if fixture.is_empty():
			continue
		var plan := fixture["plan"] as Dictionary
		var runtime := fixture["runtime"] as Dictionary
		var route := _route_node_ids(plan)
		var event_node_id := str(route[route.size() - 3 + event_position])
		var event_node := _node_by_id(plan, event_node_id)
		var node_key := "%s:%s" % [str(plan["floor_id"]), event_node_id]
		suite.assert_equal(event_node["room_type"], "event", "route-skip destination is an authored event room")
		suite.assert_equal(event_node["cleared"], event_position == 1, "only a skipped intermediate is automatically cleared")
		suite.assert_true(
			not (_event_state_from_runtime(runtime)["selected_event_by_node"] as Dictionary).has(node_key),
			"route-skip destination has no event assignment"
		)
		suite.assert_true(
			bool(seal.call("_event_runtime_restores", registry, plan, run_economy, runtime)),
			"route-skip runtime retains authentic participants and publication history"
		)
		var transitions := fixture["transitions"] as Array
		var snapshot: Dictionary = seal.call(
			"capture", registry, plan, plan["selected_edge_ids"], _room_fact_inputs_for_plan(plan),
			run_economy, merchant_state, runtime, transitions
		)
		suite.assert_true(not snapshot.is_empty(), "route-skip event history captures with complete room facts")
		if snapshot.is_empty():
			continue
		suite.assert_equal(
			(snapshot["room_facts"] as Array).size(), _room_fact_inputs_for_plan(plan).size(),
			"route skip preserves every entered and cleared room fact"
		)
		var validated: Dictionary = seal.call("validate", snapshot, registry, plan, run_economy, merchant_state, runtime)
		suite.assert_true(bool(validated.get("ok", false)), "authentic route-skip event history validates")
		if event_position == 1:
			var incomplete := snapshot.duplicate(true)
			incomplete["room_facts"] = (incomplete["room_facts"] as Array).filter(
				func(fact: Dictionary) -> bool: return str(fact["node_id"]) != event_node_id
			)
			for index: int in range((incomplete["room_facts"] as Array).size()):
				incomplete["room_facts"][index]["sequence"] = index
			incomplete["snapshot_digest"] = seal.call("snapshot_digest", incomplete)
			_assert_rejected(
				suite, seal, incomplete, registry, plan, run_economy, merchant_state, runtime,
				&"ROOM_FACT_INVALID", "route skip does not permit omitted intermediate room facts"
			)
			continue
		var cleared_plan := _with_current_node_cleared(plan, true)
		var cleared_runtime := runtime.duplicate(true)
		cleared_runtime["consequence_runtime"]["participant_snapshots"]["route"]["plan"] = cleared_plan
		suite.assert_true(
			bool(seal.call("_event_runtime_restores", registry, cleared_plan, run_economy, cleared_runtime)),
			"cleared landing fixture still restores every runtime authority"
		)
		suite.assert_true((seal.call(
			"capture", registry, cleared_plan, cleared_plan["selected_edge_ids"], _room_fact_inputs_for_plan(cleared_plan),
			run_economy, merchant_state, cleared_runtime, transitions
		) as Dictionary).is_empty(), "route-skip landing event still requires its own history when cleared")
		var forged := snapshot.duplicate(true)
		var cleared_fact := (forged["room_facts"] as Array).back().duplicate(true) as Dictionary
		cleared_fact["fact_type"] = "room_cleared"
		cleared_fact["sequence"] = (forged["room_facts"] as Array).size()
		(forged["room_facts"] as Array).append(cleared_fact)
		forged["event_runtime_digest"] = ReplayRecorderScript.value_digest(cleared_runtime)
		forged["snapshot_digest"] = seal.call("snapshot_digest", forged)
		_assert_rejected(
			suite, seal, forged, registry, cleared_plan, run_economy, merchant_state, cleared_runtime,
			&"EVENT_RUNTIME_INVALID", "re-signed route skip cannot erase its landing event history",
			"selected_event_by_node.missing_cleared_event"
		)


func _test_room_completion_history_binding(suite, seal: RefCounted, registry: RefCounted, plan: Dictionary, route_prefix: Array, room_facts: Array, economy: Dictionary, merchants: Dictionary, events: Dictionary, transitions: Array) -> void:
	var history: Array = []
	for node_id: String in plan["visited_node_ids"]:
		var node := _node_by_id(plan, node_id)
		if node_id == str(plan["entry_node_id"]) or not bool(node.get("cleared", false)):
			continue
		history.append({"type": "room_completed_v1", "sequence": history.size() + 1, "floor_id": plan["floor_id"], "floor_index": plan["floor_index"], "node_id": node_id})
	var captured: Dictionary = seal.call("capture", registry, plan, route_prefix, room_facts, economy, merchants, events, transitions, {}, history)
	suite.assert_true(not captured.is_empty(), "Replay captures modifier room lifetime history")
	if captured.is_empty():
		return
	var validated: Dictionary = seal.call("validate", captured, registry, plan, economy, merchants, events, {}, history)
	suite.assert_true(bool(validated.get("ok", false)), "Replay restores exact room lifetime history")
	var changed: Dictionary = seal.call("validate", captured, registry, plan, economy, merchants, events, {}, [])
	suite.assert_equal(changed.get("code"), &"ROOM_COMPLETION_HISTORY_DRIFT", "Replay refuses cleared-room history deletion")
	var downgraded := captured.duplicate(true)
	downgraded.erase("room_completion_events_digest")
	downgraded["snapshot_digest"] = seal.call("snapshot_digest", downgraded)
	var refused: Dictionary = seal.call("validate", downgraded, registry, plan, economy, merchants, events, {}, history)
	suite.assert_equal(refused.get("code"), &"ROOM_COMPLETION_HISTORY_MISSING", "Replay cannot drop the history binding while lifetime facts exist")


func _event_route_skip_fixture(
	registry: RefCounted, floors: Array, templates: Array, event_position: int
) -> Dictionary:
	for seed_value: int in range(1, 65):
		var generated: Dictionary = FloorPlanGeneratorScript.new().generate(seed_value, floors[2], templates)
		if not bool(generated.get("ok", false)):
			continue
		var floor_plan = FloorPlanScript.new()
		if not bool(floor_plan.configure(generated["plan"], floors[2], templates).get("ok", false)):
			continue
		while floor_plan.snapshot()["current_node_id"] != floor_plan.snapshot()["boss_node_id"]:
			var edge := _first_open_edge(floor_plan.snapshot())
			if not bool(floor_plan.select_edge(StringName(str(edge["id"])), floor_plan.revision()).get("ok", false)):
				break
			var plan := _with_current_node_cleared(floor_plan.snapshot(), true)
			var node := _node_by_id(plan, str(plan["current_node_id"]))
			if str(node["room_type"]) != "event":
				if not bool(floor_plan.configure(plan, floors[2], templates).get("ok", false)):
					break
				continue
			var route = EventRouteAuthorityScript.new()
			if not route.configure(plan):
				break
			var preview: Dictionary = route.prepare_operations(
				"replay_route_skip_probe", [{"operation": "route_skip", "arguments": {"rooms": 2}}], 0
			)
			if not bool(preview.get("ok", false)):
				break
			var preview_plan := preview["ticket"]["after"]["plan"] as Dictionary
			var preview_route := _route_node_ids(preview_plan)
			var destination := _node_by_id(preview_plan, preview_route[preview_route.size() - 3 + event_position])
			if str(destination["room_type"]) != "event":
				break
			var fixture := _event_runtime_fixture(registry, plan, "event_void_rift")
			if fixture.is_empty():
				return {}
			var runtime: RefCounted = fixture["runtime"]
			if not bool(runtime.call("open_event", {
				"floor_id": str(plan["floor_id"]), "floor_index": int(plan["floor_index"]),
				"node_id": str(plan["current_node_id"]), "primary_event_id": str(node["event_id"]),
			}, {}).get("ok", false)):
				return {}
			if not bool(runtime.call("choose_option", &"commit", _event_global_revision).get("ok", false)):
				return {}
			var event_runtime: Dictionary = runtime.call("snapshot")
			var transitions: Array[Dictionary] = []
			for index: int in range(3):
				var prior: Dictionary = {} if index == 0 else FloorPlanGeneratorScript.new().generate(seed_value, floors[index - 1], templates)
				transitions.append({
					"sequence": index,
					"from_floor_id": "" if index == 0 else str(floors[index - 1]["id"]),
					"to_floor_id": str(floors[index]["id"]),
					"completed_plan_digest": "" if index == 0 else str(prior["plan"]["generation_digest"]),
				})
			return {
				"plan": event_runtime["consequence_runtime"]["participant_snapshots"]["route"]["plan"],
				"runtime": event_runtime, "transitions": transitions,
			}
	return {}


func _test_floor_rule_replay_round_trip(
	suite,
	seal: RefCounted,
	registry: RefCounted,
	plan: Dictionary,
	route_prefix: Array,
	room_facts: Array,
	run_economy: Dictionary,
	merchant_state: Dictionary,
	event_resolutions: Dictionary,
	floor_transitions: Array
) -> void:
	var runtime: RefCounted = CrumblingGroundRuleScript.new()
	var configured: Dictionary = runtime.call("configure", {
		"room_id": str(plan.get("current_node_id", "")),
		"room_seed": 20261002,
		"zones": [
			{"id": "hazard_west", "bounds": {"x": 32.0, "y": 48.0, "width": 160.0, "height": 120.0}},
			{"id": "safe_core", "bounds": {"x": 224.0, "y": 96.0, "width": 192.0, "height": 168.0}},
		],
		"safe_zone_ids": ["safe_core"],
		"reduced_motion": false,
		"hit_flash_enabled": true,
	}, AcceptingFloorRuleEffectAuthority.new())
	suite.assert_true(bool(configured.get("ok", false)), "Replay floor-rule fixture configures")
	var advanced: Dictionary = runtime.call("advance_frame", 0)
	suite.assert_true(bool(advanced.get("ok", false)), "Replay floor-rule fixture advances")
	var floor_rule_state: Dictionary = runtime.call("snapshot")
	var sealed: Dictionary = seal.call(
		"capture", registry, plan, route_prefix, room_facts,
		run_economy, merchant_state, event_resolutions, floor_transitions,
		floor_rule_state
	)
	suite.assert_true(not sealed.is_empty(), "dungeon Replay seals floor-rule state")
	var valid: Dictionary = seal.call(
		"validate", sealed, registry, plan, run_economy, merchant_state,
		event_resolutions,
		floor_rule_state
	)
	suite.assert_true(bool(valid.get("ok", false)), "sealed floor-rule state validates")
	var drifted := floor_rule_state.duplicate(true)
	drifted["runtime_frame"] = int(drifted["runtime_frame"]) + 1
	var rejected: Dictionary = seal.call(
		"validate", sealed, registry, plan, run_economy, merchant_state,
		event_resolutions,
		drifted
	)
	suite.assert_equal(rejected.get("code"), &"FLOOR_RULE_STATE_DRIFT", "Replay rejects floor-rule frame drift")


func _test_later_floor_transition_authority(
	suite,
	seal: RefCounted,
	registry: RefCounted,
	floors: Array,
	templates: Array,
	run_economy: Dictionary,
	merchant_state: Dictionary,
	prior_event_runtime: Dictionary
) -> void:
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(
		20261001, floors[1], templates
	)
	suite.assert_true(bool(generated.get("ok", false)), "later-floor Replay fixture generates")
	if not bool(generated.get("ok", false)):
		return
	var prior: Dictionary = FloorPlanGeneratorScript.new().generate(
		20261001, floors[0], templates
	)
	if not bool(prior.get("ok", false)):
		suite.assert_true(false, "later-floor prior plan generates")
		return
	var later_plan: Dictionary = generated["plan"]
	var empty_event_runtime := _empty_dungeon_event_runtime(registry, later_plan)
	var transitions: Array = [
		{
			"sequence": 0,
			"from_floor_id": "",
			"to_floor_id": str(floors[0]["id"]),
			"completed_plan_digest": "",
		},
		{
			"sequence": 1,
			"from_floor_id": str(floors[0]["id"]),
			"to_floor_id": str(floors[1]["id"]),
			"completed_plan_digest": str(prior["plan"]["generation_digest"]),
		},
	]
	var later_snapshot: Dictionary = seal.call(
		"capture", registry, later_plan, [], [], run_economy, merchant_state,
		empty_event_runtime, transitions
	)
	suite.assert_true(not later_snapshot.is_empty(), "later-floor canonical transition chain captures")
	if later_snapshot.is_empty():
		return
	var valid: Dictionary = seal.call(
		"validate", later_snapshot, registry, later_plan, run_economy,
		merchant_state, empty_event_runtime
	)
	suite.assert_true(bool(valid.get("ok", false)), "later-floor canonical transition chain validates")
	_test_legacy_empty_event_history(
		suite, later_snapshot, registry, later_plan, run_economy,
		merchant_state, empty_event_runtime, transitions
	)
	var historical_runtime := prior_event_runtime.duplicate(true)
	var current_route = EventRouteAuthorityScript.new()
	suite.assert_true(current_route.configure(later_plan), "later-floor route authority configures")
	historical_runtime["consequence_runtime"]["participant_snapshots"]["route"] = current_route.snapshot()
	historical_runtime["active_node_key"] = ""
	historical_runtime["active_event_id"] = ""
	var historical_snapshot: Dictionary = seal.call(
		"capture", registry, later_plan, [], [], run_economy, merchant_state,
		historical_runtime, transitions
	)
	suite.assert_true(not historical_snapshot.is_empty(), "later floor retains authoritative prior-floor event history")
	if not historical_snapshot.is_empty():
		var historical_valid: Dictionary = seal.call(
			"validate", historical_snapshot, registry, later_plan, run_economy,
			merchant_state, historical_runtime
		)
		suite.assert_true(bool(historical_valid.get("ok", false)), "historical event history verifies against its canonical floor")
	var forged := later_snapshot.duplicate(true)
	forged["floor_transitions"][1]["completed_plan_digest"] = "0".repeat(64)
	forged["snapshot_digest"] = seal.call("snapshot_digest", forged)
	_assert_rejected(
		suite, seal, forged, registry, later_plan, run_economy, merchant_state,
		empty_event_runtime,
		&"FLOOR_TRANSITION_INVALID", "re-signed prior floor digest drift"
	)


func _test_legacy_empty_event_history(
	suite,
	modern_snapshot: Dictionary,
	registry: RefCounted,
	plan: Dictionary,
	run_economy: Dictionary,
	merchant_state: Dictionary,
	modern_runtime: Dictionary,
	transitions: Array
) -> void:
	var legacy := modern_snapshot.duplicate(true)
	for field: String in [
		"event_runtime_digest", "event_assignment_facts", "event_outcome_facts",
		"event_transaction_facts", "event_receipt_facts", "event_publication_facts",
	]:
		legacy.erase(field)
	legacy["event_resolution_digest"] = ReplayRecorderScript.value_digest([])
	var legacy_reader: RefCounted = load(SEAL_PATH).new()
	legacy["snapshot_digest"] = legacy_reader.call("snapshot_digest", legacy)
	var validated: Dictionary = legacy_reader.call(
		"validate", legacy, registry, plan, run_economy, merchant_state, []
	)
	suite.assert_true(bool(validated.get("ok", false)), "historical schema-3 empty event history remains readable without a secret")
	suite.assert_equal(validated.get("snapshot"), legacy, "legacy read preserves historical bytes")
	suite.assert_true((legacy_reader.call(
		"capture", registry, plan, plan["selected_edge_ids"], _room_fact_inputs_for_plan(plan),
		run_economy, merchant_state, [], transitions
	) as Dictionary).is_empty(), "new capture cannot use the legacy empty Array bypass")
	for legacy_input: Variant in [[{"event_id": "forged_event"}], modern_runtime]:
		var rejected: Dictionary = legacy_reader.call(
			"validate", legacy, registry, plan, run_economy, merchant_state, legacy_input
		)
		suite.assert_equal(rejected.get("code"), &"EVENT_RESOLUTION_INVALID", "legacy reader accepts only empty event history")
	var forged_digest := legacy.duplicate(true)
	forged_digest["event_resolution_digest"] = "0".repeat(64)
	forged_digest["snapshot_digest"] = legacy_reader.call("snapshot_digest", forged_digest)
	var rejected_digest: Dictionary = legacy_reader.call(
		"validate", forged_digest, registry, plan, run_economy, merchant_state, []
	)
	suite.assert_equal(rejected_digest.get("code"), &"EVENT_RESOLUTION_INVALID", "legacy empty history digest remains authoritative")
	var mixed_fields := legacy.duplicate(true)
	mixed_fields["event_runtime_digest"] = modern_snapshot["event_runtime_digest"]
	mixed_fields["snapshot_digest"] = legacy_reader.call("snapshot_digest", mixed_fields)
	var rejected_mixed: Dictionary = legacy_reader.call(
		"validate", mixed_fields, registry, plan, run_economy, merchant_state, []
	)
	suite.assert_equal(rejected_mixed.get("code"), &"INVALID_FIELDS", "legacy and modern Replay fields cannot be mixed")
	suite.assert_true((legacy_reader.call(
		"capture", registry, plan, plan["selected_edge_ids"], _room_fact_inputs_for_plan(plan),
		run_economy, merchant_state, modern_runtime, transitions
	) as Dictionary).is_empty(), "modern empty runtime still needs its authenticated publication root")
	var zero_root := modern_runtime.duplicate(true)
	zero_root["publication_digest"] = "0".repeat(64)
	var modern_reader: RefCounted = load(SEAL_PATH).new(PUBLICATION_SECRET)
	suite.assert_true((modern_reader.call(
		"capture", registry, plan, plan["selected_edge_ids"], _room_fact_inputs_for_plan(plan),
		run_economy, merchant_state, zero_root, transitions
	) as Dictionary).is_empty(), "modern empty publication root cannot be forged")
	_assert_rejected(
		suite, modern_reader, modern_snapshot, registry, plan, run_economy, merchant_state,
		zero_root, &"EVENT_RUNTIME_INVALID", "modern empty root rejects re-signed drift"
	)


func _first_open_edge(plan: Dictionary) -> Dictionary:
	for edge_value: Variant in plan.get("edges", []):
		if edge_value is Dictionary and str((edge_value as Dictionary).get("source_node_id", "")) == str(plan.get("current_node_id", "")):
			return (edge_value as Dictionary).duplicate(true)
	return {}


func _node_by_id(plan: Dictionary, node_id: String) -> Dictionary:
	for node_value: Variant in plan.get("nodes", []):
		if node_value is Dictionary and str((node_value as Dictionary).get("id", "")) == node_id:
			return (node_value as Dictionary).duplicate(true)
	return {}


func _dungeon_event_runtime_for_plan(
	registry: RefCounted,
	plan: Dictionary,
	phase: String = "resolved",
	selected_event_id: String = ""
) -> Dictionary:
	for node_id: String in _route_node_ids(plan):
		var node: Dictionary = _node_by_id(plan, node_id)
		var primary_event_id := str(node.get("event_id", ""))
		if primary_event_id.is_empty():
			continue
		var event_id := selected_event_id if not selected_event_id.is_empty() else (
			"event_trapped_traveler"
			if primary_event_id != "event_trapped_traveler"
			else "event_chronal_altar"
		)
		if phase in ["pending_reward", "reward_completed"]:
			event_id = "event_trapped_traveler"
		elif phase in ["pending_encounter", "encounter_completed"]:
			event_id = "event_sleeping_guardian"
		var fixture := _event_runtime_fixture(registry, plan, event_id)
		if fixture.is_empty():
			return {}
		var runtime: RefCounted = fixture["runtime"]
		var event_state: RefCounted = fixture["event_state"]
		var floor_id := str(plan.get("floor_id", ""))
		var node_key := "%s:%s" % [floor_id, node_id]
		var opened: Dictionary = runtime.call("open_event", {
			"floor_id": floor_id,
			"floor_index": int(plan.get("floor_index", 0)),
			"node_id": node_id,
			"primary_event_id": primary_event_id,
		}, {})
		if not bool(opened.get("ok", false)):
			return {}
		if phase == "reserved":
			var definition := fixture["definition"] as Dictionary
			var option := (definition["options"] as Array)[0] as Dictionary
			var outcome := (option["outcomes"] as Array)[0] as Dictionary
			var reserved: Dictionary = event_state.call(
				"reserve_option", node_key, "event_tx_v1:%s:1" % event_id,
				str(option["id"]), str(outcome["id"]), str(outcome["outcome_key"]), 1
			)
			if not bool(reserved.get("ok", false)):
				return {}
		elif phase != "open":
			var option_id := &"decline" if phase in ["resolved", "dismissed", "pending_publication"] else &"commit"
			_accept_event_facts = phase != "pending_publication"
			var chosen: Dictionary = runtime.call("choose_option", option_id, _event_global_revision)
			if not bool(chosen.get("ok", false)) and not bool(chosen.get("pending_publication", false)):
				return {}
			if phase == "reward_completed":
				var pending := _event_state_from_runtime(runtime.call("snapshot"))
				if not bool(runtime.call(
					"complete_reward", str(pending["pending_reward"]["continuation_id"]),
					{"reward_id": "blessing_fixture"}, _event_global_revision
				).get("ok", false)):
					return {}
			elif phase == "encounter_completed":
				var pending := _event_state_from_runtime(runtime.call("snapshot"))
				if not bool(runtime.call(
					"complete_encounter", str(pending["pending_encounter"]["continuation_id"]),
					true, {}, _event_global_revision
				).get("ok", false)):
					return {}
			elif phase == "dismissed":
				if not bool(runtime.call("dismiss_result", _event_global_revision).get("ok", false)):
					return {}
		var result: Dictionary = runtime.call("snapshot")
		return result if bool(runtime.call("can_restore_snapshot", result)) else {}
	return {}


func _event_runtime_fixture(
	registry: RefCounted, plan: Dictionary, event_id: String
) -> Dictionary:
	_event_global_revision = 10
	_accept_event_facts = true
	_event_provider_context = {
		"global_revision": _event_global_revision,
		"selection": {
			"run_seed": int(plan["run_seed"]), "availability": "LAUNCH",
			"health": {"current": 80.0, "maximum": 100.0},
			"economy": {"gold": 230}, "build": {"curse_ids": []},
			"resources": {"time_shard": 2, "forge_essence": 1},
			"flags": {}, "meta": {},
		},
		"requirements": {
			"resources": {"time_shard": 2, "forge_essence": 1},
			"health": {"current": 80.0, "maximum": 100.0},
			"gold": 230, "reward_tags": [], "curse_ids": [], "narrative_flags": {},
			"floor_index": int(plan["floor_index"]),
		},
	}
	var resource = EventResourceAuthorityScript.new()
	var health = EventHealthAuthorityScript.new()
	var modifier = EventModifierAuthorityScript.new()
	var route = EventRouteAuthorityScript.new()
	var economy = RunEconomyStateScript.new()
	var event_state = DungeonEventRunStateScript.new()
	var profile: Dictionary = {}
	var source: Dictionary = registry.resolve_economy_profile(&"launch_economy_v1")
	for field: String in EconomyProfileScript.ROOT_FIELDS:
		profile[field] = source[field]
	if (
		not resource.configure({"time_shard": 2, "forge_essence": 1})
		or not health.configure(80.0, 100.0)
		or not modifier.configure([], {}, [])
		or not route.configure(plan)
		or not bool(economy.configure(profile, 0).get("ok", false))
		or not economy.restore_snapshot(_run_economy_fixture(registry))
		or not bool(event_state.configure("b".repeat(64)).get("ok", false))
	):
		return {}
	var consequence = ConsequenceRuntimeScript.new()
	if not consequence.configure(resource, health, economy, modifier, route, event_state):
		return {}
	var definition_source: Dictionary = registry.resolve_dungeon_event(StringName(event_id))
	var definition: Dictionary = {}
	for field: String in DungeonEventDefinitionScript.ROOT_FIELDS:
		definition[field] = definition_source[field]
	var runtime = DungeonEventRuntimeScript.new()
	if not runtime.configure(
		[definition], DungeonEventSelectorScript.new(), event_state,
		EventRequirementServiceScript.new(), consequence,
		Callable(self, "_provide_event_context"), Callable(self, "_commit_event_state"),
		Callable(self, "_publish_event_fact"), PUBLICATION_SECRET
	):
		return {}
	return {"runtime": runtime, "event_state": event_state, "definition": definition}


func _empty_dungeon_event_runtime(registry: RefCounted, plan: Dictionary) -> Dictionary:
	var fixture := _event_runtime_fixture(registry, plan, "event_chronal_altar")
	return fixture["runtime"].call("snapshot") if not fixture.is_empty() else {}


func _provide_event_context() -> Dictionary:
	_event_provider_context["global_revision"] = _event_global_revision
	return _event_provider_context.duplicate(true)


func _commit_event_state(_command: Dictionary, expected_revision: int) -> Dictionary:
	if expected_revision != _event_global_revision:
		return {"ok": false, "code": &"STALE_REVISION"}
	_event_global_revision += 1
	return {"ok": true, "code": &"OK", "new_revision": _event_global_revision}


func _publish_event_fact(_fact_id: String, _payload: Dictionary) -> bool:
	return _accept_event_facts


func _event_state_from_runtime(event_runtime: Dictionary) -> Dictionary:
	return (
		((event_runtime.get("consequence_runtime", {}) as Dictionary)
			.get("participant_snapshots", {}) as Dictionary)
			.get("event_state", {}) as Dictionary
	)


func _room_fact_inputs_for_plan(plan: Dictionary) -> Array:
	var result: Array[Dictionary] = []
	for node_id: String in _route_node_ids(plan):
		var node := _node_by_id(plan, node_id)
		result.append({
			"node_id": node_id,
			"fact_type": "room_entered",
			"sequence": result.size(),
		})
		if bool(node.get("cleared", false)):
			result.append({
				"node_id": node_id,
				"fact_type": "room_cleared",
				"sequence": result.size(),
			})
	return result


func _route_node_ids(plan: Dictionary) -> Array[String]:
	var edges_by_id: Dictionary = {}
	for edge_value: Variant in plan.get("edges", []):
		if edge_value is Dictionary:
			edges_by_id[str((edge_value as Dictionary).get("id", ""))] = edge_value
	var result: Array[String] = []
	for edge_id_value: Variant in plan.get("selected_edge_ids", []):
		var edge_id := str(edge_id_value)
		if not edges_by_id.has(edge_id):
			return []
		result.append(str((edges_by_id[edge_id] as Dictionary).get("destination_node_id", "")))
	return result


func _with_current_node_cleared(plan: Dictionary, cleared: bool) -> Dictionary:
	var result := plan.duplicate(true)
	for node_value: Variant in result.get("nodes", []):
		if (
			node_value is Dictionary
			and str((node_value as Dictionary).get("id", "")) == str(result.get("current_node_id", ""))
		):
			(node_value as Dictionary)["cleared"] = cleared
			break
	return result


func _resigned_plan_with_reordered_siblings(plan: Dictionary) -> Dictionary:
	var result := plan.duplicate(true)
	var nodes := result.get("nodes", []) as Array
	for left_index: int in range(nodes.size()):
		var left := nodes[left_index] as Dictionary
		for right_index: int in range(left_index + 1, nodes.size()):
			var right := nodes[right_index] as Dictionary
			if int(left.get("layer", -1)) != int(right.get("layer", -2)):
				continue
			var swap_value: Variant = nodes[left_index]
			nodes[left_index] = nodes[right_index]
			nodes[right_index] = swap_value
			result["generation_digest"] = FloorPlanScript.compute_generation_digest(result)
			return result
	return {}


func _run_economy_fixture(registry: RefCounted) -> Dictionary:
	var source: Dictionary = registry.resolve_economy_profile(&"launch_economy_v1")
	var profile: Dictionary = {}
	for field: String in EconomyProfileScript.ROOT_FIELDS:
		if source.has(field):
			var value: Variant = source[field]
			profile[field] = value.duplicate(true) if value is Array or value is Dictionary else value
	var state = RunEconomyStateScript.new()
	if profile.is_empty() or not bool(state.configure(profile, 0).get("ok", false)):
		return {}
	for transaction: Dictionary in [
		{"id": "tx_reward_0001", "delta": 300, "operation": "gold_delta"},
		{"id": "tx_reroll_0001", "delta": -40, "operation": "gold_reroll"},
		{"id": "tx_purchase_0001", "delta": -80, "operation": "gold_purchase"},
		{"id": "tx_sell_reward_0001", "delta": 50, "operation": "gold_delta"},
	]:
		var prepared: Dictionary = state.prepare_transaction(
			transaction["id"], transaction["delta"], state.revision(),
			{"operation": transaction["operation"]}
		)
		if not bool(prepared.get("ok", false)):
			return {}
		if not bool(state.commit_transaction(prepared["ticket"]).get("ok", false)):
			return {}
	return state.snapshot()


func _merchant_state_fixture(composite_service: bool = true) -> Dictionary:
	var service_snapshot: Dictionary = (
		{
			"schema_id": "planewalker.merchant_service_router",
			"schema_version": 1,
			"authorities": {
				"heal": {"completed_transaction_ids": []},
				"route_reveal": {"completed_transaction_ids": []},
				"sell_reward": {"completed_transaction_ids": ["tx_sell_reward_0001"]},
			},
		}
		if composite_service
		else {"completed_transaction_ids": ["tx_sell_reward_0001"]}
	)
	return {
		"schema_id": "planewalker.merchant_state",
		"schema_version": 1,
		"content_fingerprint": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		"nodes": [{
			"floor_id": "floor_ruins_of_remnant",
			"floor_index": 0,
			"node_id": "shop_a",
			"merchant_id": "merchant_wayfarer",
			"inventory": {
				"schema_version": 1,
				"merchant_id": "merchant_wayfarer",
				"node_id": "shop_a",
				"floor_index": 1,
				"reroll_count": 1,
				"revision": 3,
				"offers": [{
					"offer_id": "offer_a",
					"reward_id": "item_a",
					"category": "item",
					"rarity": "common",
					"price": 80,
					"sold": true,
				}],
			},
			"runtime": {
				"schema_id": "planewalker.merchant_runtime",
				"schema_version": 1,
				"completed_transaction_ids": [
					"tx_purchase_0001", "tx_reroll_0001", "tx_sell_reward_0001",
				],
			},
			"service": service_snapshot,
			"visibility": {"revealed": true},
			"transactions": [
				{
					"sequence": 1,
					"transaction_id": "tx_reroll_0001",
					"kind": "reroll",
					"offer_id": "",
					"reward_id": "",
					"service_id": "",
					"cost_kind": "gold",
					"amount": 40,
					"economy_revision": 2,
					"inventory_revision": 2,
				},
				{
					"sequence": 2,
					"transaction_id": "tx_purchase_0001",
					"kind": "purchase",
					"offer_id": "offer_a",
					"reward_id": "item_a",
					"service_id": "",
					"cost_kind": "gold",
					"amount": 80,
					"economy_revision": 3,
					"inventory_revision": 3,
				},
				{
					"sequence": 3,
					"transaction_id": "tx_sell_reward_0001",
					"kind": "service",
					"offer_id": "",
					"reward_id": "item_sold",
					"service_id": "sell_reward",
					"cost_kind": "reward",
					"amount": 50,
					"economy_revision": 4,
					"inventory_revision": 3,
				},
			],
		}],
		"pending_transaction": {},
	}


func _merchant_transaction_facts_fixture() -> Array:
	var node := (_merchant_state_fixture()["nodes"] as Array)[0] as Dictionary
	var result: Array[Dictionary] = []
	for transaction_value: Variant in node["transactions"]:
		var fact := (transaction_value as Dictionary).duplicate(true)
		fact["floor_id"] = node["floor_id"]
		fact["node_id"] = node["node_id"]
		fact["merchant_id"] = node["merchant_id"]
		result.append(fact)
	return result


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value as Array if value is Array else []
