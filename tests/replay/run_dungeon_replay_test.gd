extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const RunEconomyStateScript := preload("res://scripts/economy/run_economy_state.gd")
const CrumblingGroundRuleScript := preload(
	"res://scripts/dungeon/floor_rules/crumbling_ground_rule.gd"
)

const SEAL_PATH := "res://scripts/replay/run_dungeon_replay_seal.gd"
const FLOOR_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"


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
	var seal: RefCounted = seal_script.new()
	var event_resolutions: Array = _event_resolutions_for_plan(seal, registry, plan)
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
	suite.assert_equal(str(snapshot.get("event_resolution_digest", "")).length(), 64, "seal owns event digest")
	suite.assert_equal(snapshot.get("floor_transitions"), floor_transitions, "seal owns floor transitions")
	suite.assert_equal(str(snapshot.get("snapshot_digest", "")).length(), 64, "seal authenticates historical bytes")

	var valid: Dictionary = seal.call(
		"validate", snapshot, registry, plan, run_economy, merchant_state,
		event_resolutions
	)
	suite.assert_true(bool(valid.get("ok", false)), "valid dungeon Replay seal verifies")
	suite.assert_equal(valid.get("snapshot"), snapshot, "validation returns byte-identical historical snapshot")
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
		suite, seal, registry, floors, templates, run_economy, merchant_state
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

	if not event_resolutions.is_empty():
		var duplicate_events := event_resolutions.duplicate(true)
		duplicate_events.append(duplicate_events[0].duplicate(true))
		duplicate_events[1]["sequence"] = 1
		suite.assert_equal(
			seal.call(
				"capture", registry, plan, route_prefix, room_facts,
				run_economy, merchant_state, duplicate_events, floor_transitions
			),
			{},
			"capture rejects duplicate event resolutions"
		)
		var wrong_event_node := event_resolutions.duplicate(true)
		wrong_event_node[0]["node_id"] = "boss"
		suite.assert_equal(
			seal.call(
				"capture", registry, plan, route_prefix, room_facts,
				run_economy, merchant_state, wrong_event_node, floor_transitions
			),
			{},
			"capture rejects event resolutions outside the cleared route node"
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

	if not event_resolutions.is_empty():
		var changed_events := event_resolutions.duplicate(true)
		changed_events[0]["outcome_id"] = "forged_outcome"
		_assert_rejected(
			suite, seal, snapshot, registry, plan, run_economy, merchant_state, changed_events,
			&"EVENT_RESOLUTION_INVALID", "event outcome authority drift"
		)
		var event_definition_drift = DriftRegistry.new(registry)
		var event_id := str(event_resolutions[0].get("event_id", ""))
		var changed_event: Dictionary = registry.resolve_dungeon_event(
			StringName(event_id)
		)
		changed_event["options"][0]["consequences"] = [
			{"operation": "gold_delta", "amount": 999},
		]
		event_definition_drift.event_overrides[event_id] = changed_event
		_assert_rejected(
			suite, seal, snapshot, event_definition_drift, plan,
			run_economy, merchant_state, event_resolutions, &"EVENT_RESOLUTION_INVALID",
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
	event_resolutions: Array,
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


func _test_floor_rule_replay_round_trip(
	suite,
	seal: RefCounted,
	registry: RefCounted,
	plan: Dictionary,
	route_prefix: Array,
	room_facts: Array,
	run_economy: Dictionary,
	merchant_state: Dictionary,
	event_resolutions: Array,
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
	merchant_state: Dictionary
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
		[], transitions
	)
	suite.assert_true(not later_snapshot.is_empty(), "later-floor canonical transition chain captures")
	if later_snapshot.is_empty():
		return
	var valid: Dictionary = seal.call(
		"validate", later_snapshot, registry, later_plan, run_economy,
		merchant_state, []
	)
	suite.assert_true(bool(valid.get("ok", false)), "later-floor canonical transition chain validates")
	var forged := later_snapshot.duplicate(true)
	forged["floor_transitions"][1]["completed_plan_digest"] = "0".repeat(64)
	forged["snapshot_digest"] = seal.call("snapshot_digest", forged)
	_assert_rejected(
		suite, seal, forged, registry, later_plan, run_economy, merchant_state, [],
		&"FLOOR_TRANSITION_INVALID", "re-signed prior floor digest drift"
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


func _event_resolutions_for_plan(
	seal: RefCounted,
	registry: RefCounted,
	plan: Dictionary
) -> Array:
	var result: Array[Dictionary] = []
	for node_id: String in _route_node_ids(plan):
		var node: Dictionary = _node_by_id(plan, node_id)
		var event_id := str(node.get("event_id", ""))
		if event_id.is_empty() or not bool(node.get("cleared", false)):
			continue
		var definition: Dictionary = registry.resolve_dungeon_event(StringName(event_id))
		var options := definition.get("options", []) as Array
		if options.is_empty():
			return []
		var option_id := str((options[0] as Dictionary).get("id", ""))
		result.append({
			"event_id": event_id,
			"node_id": node_id,
			"option_id": option_id,
			"outcome_id": seal.call(
				"expected_event_outcome_id", definition, node_id, option_id
			),
			"sequence": result.size(),
		})
	return result


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
