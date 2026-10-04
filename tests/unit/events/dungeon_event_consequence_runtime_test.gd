extends Node

const ConsequenceRuntimeScript := preload(
	"res://scripts/events/dungeon_event_consequence_runtime.gd"
)
const EventResourceAuthorityScript := preload(
	"res://scripts/events/event_resource_authority.gd"
)
const EventHealthAuthorityScript := preload(
	"res://scripts/events/event_health_authority.gd"
)
const EventModifierAuthorityScript := preload(
	"res://scripts/events/event_modifier_authority.gd"
)
const EventRouteAuthorityScript := preload(
	"res://scripts/events/event_route_authority.gd"
)
const DungeonEventRunStateScript := preload(
	"res://scripts/events/dungeon_event_run_state.gd"
)
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const RunEconomyStateScript := preload("res://scripts/economy/run_economy_state.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ECONOMY_PROFILE_PATH := "res://data/content_packs/base/content/economy_profiles.json"
const FLOORS_PATH := "res://data/content_packs/base/content/floors.json"
const ROOM_TEMPLATES_PATH := "res://data/content_packs/base/content/room_templates.json"


class FailingRouteAuthority:
	extends RefCounted
	var inner: RefCounted
	var fail_commit: bool = true

	func _init(value: RefCounted) -> void:
		inner = value

	func snapshot() -> Dictionary:
		return inner.call("snapshot")

	func can_restore_snapshot(value: Dictionary) -> bool:
		return bool(inner.call("can_restore_snapshot", value))

	func restore_snapshot(value: Dictionary) -> bool:
		return bool(inner.call("restore_snapshot", value))

	func prepare_operations(transaction_id: String, operations: Array, expected_revision: int) -> Dictionary:
		return inner.call("prepare_operations", transaction_id, operations, expected_revision)

	func commit_operations(ticket: Dictionary) -> Dictionary:
		if fail_commit:
			return {"ok": false, "code": &"INJECTED_ROUTE_COMMIT_FAILURE", "context": {}}
		return inner.call("commit_operations", ticket)

	func rollback_operations(receipt: Dictionary) -> Dictionary:
		return inner.call("rollback_operations", receipt)


class FailingRollbackResourceAuthority:
	extends RefCounted
	var inner: RefCounted

	func _init(value: RefCounted) -> void:
		inner = value

	func snapshot() -> Dictionary:
		return inner.call("snapshot")

	func can_restore_snapshot(value: Dictionary) -> bool:
		return bool(inner.call("can_restore_snapshot", value))

	func restore_snapshot(_value: Dictionary) -> bool:
		return false

	func prepare_delta(transaction_id: String, resource_id: StringName, amount: int, expected_revision: int) -> Dictionary:
		return inner.call("prepare_delta", transaction_id, resource_id, amount, expected_revision)

	func commit_delta(ticket: Dictionary) -> Dictionary:
		return inner.call("commit_delta", ticket)

	func rollback_delta(_receipt: Dictionary) -> Dictionary:
		return {"ok": false, "code": &"INJECTED_RESOURCE_ROLLBACK_FAILURE", "context": {}}


class TracingScalarAuthority:
	extends RefCounted
	var inner: RefCounted
	var participant: String
	var trace: Array
	var fail_commit: bool

	func _init(value: RefCounted, name: String, events: Array, fail: bool) -> void:
		inner = value
		participant = name
		trace = events
		fail_commit = fail

	func snapshot() -> Dictionary: return inner.call("snapshot")
	func can_restore_snapshot(value: Dictionary) -> bool: return bool(inner.call("can_restore_snapshot", value))
	func restore_snapshot(value: Dictionary) -> bool: return bool(inner.call("restore_snapshot", value))
	func prepare_delta(transaction_id: String, first: Variant, second: Variant, revision: int) -> Dictionary:
		return inner.call("prepare_delta", transaction_id, first, second, revision)
	func commit_delta(ticket: Dictionary) -> Dictionary:
		trace.append("commit:%s" % participant)
		return {"ok": false, "code": &"INJECTED_COMMIT_FAILURE", "context": {}} if fail_commit else inner.call("commit_delta", ticket)
	func rollback_delta(receipt: Dictionary) -> Dictionary:
		trace.append("rollback:%s" % participant)
		return inner.call("rollback_delta", receipt)


class TracingEconomyAuthority:
	extends RefCounted
	var inner: RefCounted
	var trace: Array
	var fail_commit: bool

	func _init(value: RefCounted, events: Array, fail: bool) -> void:
		inner = value
		trace = events
		fail_commit = fail

	func snapshot() -> Dictionary: return inner.call("snapshot")
	func can_restore_snapshot(value: Dictionary) -> bool: return bool(inner.call("can_restore_snapshot", value))
	func restore_snapshot(value: Dictionary) -> bool: return bool(inner.call("restore_snapshot", value))
	func prepare_transaction(transaction_id: String, amount: int, revision: int, context: Dictionary) -> Dictionary:
		return inner.call("prepare_transaction", transaction_id, amount, revision, context)
	func commit_transaction(ticket: Dictionary) -> Dictionary:
		trace.append("commit:economy")
		return {"ok": false, "code": &"INJECTED_COMMIT_FAILURE", "context": {}} if fail_commit else inner.call("commit_transaction", ticket)
	func rollback_transaction(receipt: Dictionary) -> Dictionary:
		trace.append("rollback:economy")
		return inner.call("rollback_transaction", receipt)


class TracingOperationsAuthority:
	extends RefCounted
	var inner: RefCounted
	var participant: String
	var trace: Array
	var fail_commit: bool

	func _init(value: RefCounted, name: String, events: Array, fail: bool) -> void:
		inner = value
		participant = name
		trace = events
		fail_commit = fail

	func snapshot() -> Dictionary: return inner.call("snapshot")
	func can_restore_snapshot(value: Dictionary) -> bool: return bool(inner.call("can_restore_snapshot", value))
	func restore_snapshot(value: Dictionary) -> bool: return bool(inner.call("restore_snapshot", value))
	func prepare_operations(transaction_id: String, operations: Array, revision: int) -> Dictionary:
		return inner.call("prepare_operations", transaction_id, operations, revision)
	func commit_operations(ticket: Dictionary) -> Dictionary:
		trace.append("commit:%s" % participant)
		return {"ok": false, "code": &"INJECTED_COMMIT_FAILURE", "context": {}} if fail_commit else inner.call("commit_operations", ticket)
	func rollback_operations(receipt: Dictionary) -> Dictionary:
		trace.append("rollback:%s" % participant)
		return inner.call("rollback_operations", receipt)


class TracingEventState:
	extends RefCounted
	var inner: RefCounted
	var trace: Array
	var fail_commit: bool

	func _init(value: RefCounted, events: Array, fail: bool) -> void:
		inner = value
		trace = events
		fail_commit = fail

	func snapshot() -> Dictionary: return inner.call("snapshot")
	func can_restore_snapshot(value: Dictionary) -> bool: return bool(inner.call("can_restore_snapshot", value))
	func restore_snapshot(value: Dictionary) -> bool: return bool(inner.call("restore_snapshot", value))
	func mark_pending_reward(ticket: Dictionary, pending: Dictionary) -> Dictionary:
		trace.append("commit:event_state")
		return {"ok": false, "code": &"INJECTED_COMMIT_FAILURE", "context": {}} if fail_commit else inner.call("mark_pending_reward", ticket, pending)
	func mark_pending_encounter(ticket: Dictionary, pending: Dictionary) -> Dictionary:
		trace.append("commit:event_state")
		return {"ok": false, "code": &"INJECTED_COMMIT_FAILURE", "context": {}} if fail_commit else inner.call("mark_pending_encounter", ticket, pending)
	func resolve_option(ticket: Dictionary, resolution: Dictionary) -> Dictionary:
		trace.append("commit:event_state")
		return {"ok": false, "code": &"INJECTED_COMMIT_FAILURE", "context": {}} if fail_commit else inner.call("resolve_option", ticket, resolution)
	func rollback_transaction(receipt: Dictionary) -> Dictionary:
		trace.append("rollback:event_state")
		return inner.call("rollback_transaction", receipt)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_invalid_commit_tickets_are_typed(suite)
	_test_health_authority(suite)
	_test_modifier_authority(suite)
	_test_route_authority(suite)
	_test_route_outputs_remain_canonical_floor_plans(suite)
	_test_all_ten_consequences_and_exactly_once(suite)
	_test_prepare_is_closed_and_side_effect_free(suite)
	_test_commit_failure_compensates_in_reverse(suite)
	_test_commit_order_and_failure_stage_compensation(suite)
	_test_failed_compensation_enters_integrity_terminal(suite)
	_test_snapshot_restore_is_atomic_and_strict(suite)
	suite.finish(get_tree())


func _test_invalid_commit_tickets_are_typed(suite) -> void:
	var resource = EventResourceAuthorityScript.new()
	resource.configure({"time_shard": 2, "forge_essence": 1})
	var health = EventHealthAuthorityScript.new()
	health.configure(50.0, 100.0)
	var modifier = EventModifierAuthorityScript.new()
	modifier.configure([], {}, [])
	var route = EventRouteAuthorityScript.new()
	route.configure(_route_plan())
	var runtime_fixture := _runtime_fixture("tx_invalid_ticket")
	var cases: Array[Dictionary] = [
		{"label": "resource", "target": resource, "method": "commit_delta"},
		{"label": "health", "target": health, "method": "commit_delta"},
		{"label": "modifier", "target": modifier, "method": "commit_operations"},
		{"label": "route", "target": route, "method": "commit_operations"},
		{"label": "runtime", "target": runtime_fixture["runtime"], "method": "commit_consequences"},
	]
	var invalid_tickets: Array[Dictionary] = [
		{},
		{"schema_id": "ticket_without_transaction_id"},
	]
	for commit_case: Dictionary in cases:
		for invalid_ticket: Dictionary in invalid_tickets:
			var result: Dictionary = commit_case["target"].call(
				str(commit_case["method"]), invalid_ticket.duplicate(true)
			)
			suite.assert_equal(
				result.get("code"),
				&"TICKET_INVALID",
				"%s commit rejects incomplete tickets with a typed error" % str(commit_case["label"])
			)


func _test_health_authority(suite) -> void:
	var authority = EventHealthAuthorityScript.new()
	suite.assert_true(authority.configure(40.0, 100.0), "health authority configures")
	var before: Dictionary = authority.snapshot()
	var spend: Dictionary = authority.prepare_delta("tx_health_spend", -39.0, true, 0)
	suite.assert_true(bool(spend.get("ok", false)), "nonlethal health spend prepares")
	suite.assert_equal(authority.snapshot(), before, "health prepare has no side effects")
	var committed: Dictionary = authority.commit_delta(spend.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "health spend commits")
	suite.assert_close(float(authority.snapshot()["current"]), 1.0, "nonlethal health stops at one")
	suite.assert_equal(authority.prepare_delta("tx_health_lethal", -2.0, true, 1).get("code"), &"NONLETHAL_VIOLATION", "nonlethal overdraw rejects")
	var heal: Dictionary = authority.prepare_delta("tx_health_heal", 500.0, false, 1)
	suite.assert_true(bool(heal.get("ok", false)), "healing prepares")
	var heal_commit: Dictionary = authority.commit_delta(heal.get("ticket", {}))
	suite.assert_true(bool(heal_commit.get("ok", false)), "healing commits")
	suite.assert_close(float(authority.snapshot()["current"]), 100.0, "healing clamps to maximum")
	var forged_health_receipt := (heal_commit.get("receipt", {}) as Dictionary).duplicate(true)
	forged_health_receipt["before"] = (forged_health_receipt["after"] as Dictionary).duplicate(true)
	_resign(forged_health_receipt)
	suite.assert_true(not bool(authority.rollback_delta(forged_health_receipt).get("ok", false)), "re-signed forged health receipt rejects")
	suite.assert_true(authority.restore_snapshot(before), "health snapshot restores")
	suite.assert_equal(authority.snapshot(), before, "health restore is byte-identical")


func _test_modifier_authority(suite) -> void:
	var unsorted = EventModifierAuthorityScript.new()
	suite.assert_true(
		not unsorted.configure(
			["curse_stasis_fracture", "curse_fickle_time"], {}, []
		),
		"modifier authority rejects unsorted curse identifiers without a type error"
	)
	var malformed = EventModifierAuthorityScript.new()
	suite.assert_true(
		not malformed.configure(["curse_fickle_time", 7], {}, []),
		"modifier authority rejects non-string curse identifiers without a type error"
	)
	var authority = EventModifierAuthorityScript.new()
	suite.assert_true(authority.configure(["curse_fickle_time"], {}, []), "modifier authority configures")
	var before: Dictionary = authority.snapshot()
	var operations: Array = [
		{"operation": "curse_remove", "arguments": {"curse_id": "curse_fickle_time"}},
		{"operation": "curse_add", "arguments": {"curse_id": "curse_brittle_fortune"}},
		{"operation": "temporary_modifier", "arguments": {"modifier_id": "chronal_grace", "duration_rooms": 3, "magnitude": 1.15}},
		{"operation": "narrative_flag", "arguments": {"flag": "met_archivist", "value": true}},
	]
	var prepared: Dictionary = authority.prepare_operations("tx_modifiers", operations, 0)
	suite.assert_true(bool(prepared.get("ok", false)), "modifier operations prepare as one ticket")
	suite.assert_equal(authority.snapshot(), before, "modifier prepare has no side effects")
	var committed: Dictionary = authority.commit_operations(prepared.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "modifier operations commit atomically")
	var after: Dictionary = authority.snapshot()
	suite.assert_equal(after["curse_ids"], ["curse_brittle_fortune"], "curse add/remove commit")
	suite.assert_equal((after["narrative_flags"] as Dictionary).get("met_archivist"), true, "narrative flag commits")
	suite.assert_equal((after["temporary_modifiers"] as Array).size(), 1, "temporary modifier commits")
	var forged_modifier_receipt := (committed.get("receipt", {}) as Dictionary).duplicate(true)
	forged_modifier_receipt["before"] = (forged_modifier_receipt["after"] as Dictionary).duplicate(true)
	_resign(forged_modifier_receipt)
	suite.assert_true(not bool(authority.rollback_operations(forged_modifier_receipt).get("ok", false)), "re-signed forged modifier receipt rejects")
	suite.assert_true(bool(authority.rollback_operations(committed.get("receipt", {})).get("ok", false)), "modifier receipt rolls back")
	suite.assert_equal(authority.snapshot(), before, "modifier rollback is byte-identical")


func _test_route_authority(suite) -> void:
	var authority = EventRouteAuthorityScript.new()
	suite.assert_true(authority.configure(_route_plan()), "route authority configures")
	var before: Dictionary = authority.snapshot()
	var dynamic_corruptions: Array[Dictionary] = []
	var wrong_current := before.duplicate(true)
	(wrong_current["plan"] as Dictionary)["current_node_id"] = "combat_a"
	dynamic_corruptions.append({"label": "current prefix", "snapshot": wrong_current})
	var wrong_revision := before.duplicate(true)
	(wrong_revision["plan"] as Dictionary)["revision"] = 2
	dynamic_corruptions.append({"label": "route revision", "snapshot": wrong_revision})
	var wrong_visited := before.duplicate(true)
	(wrong_visited["plan"] as Dictionary)["visited_node_ids"] = ["entry"]
	dynamic_corruptions.append({"label": "visited prefix", "snapshot": wrong_visited})
	var wrong_flag := before.duplicate(true)
	_node(wrong_flag["plan"] as Dictionary, "event_a")["visited"] = false
	dynamic_corruptions.append({"label": "visited flag", "snapshot": wrong_flag})
	var wrong_abandoned := before.duplicate(true)
	(wrong_abandoned["plan"] as Dictionary)["abandoned_node_ids"] = ["shop_a"]
	dynamic_corruptions.append({"label": "abandoned reachability", "snapshot": wrong_abandoned})
	for corruption: Dictionary in dynamic_corruptions:
		suite.assert_true(not authority.can_restore_snapshot(corruption["snapshot"]), "%s tampering rejects" % corruption["label"])
	suite.assert_equal(authority.snapshot(), before, "dynamic snapshot rejection is atomic")
	var reveal: Dictionary = authority.prepare_operations(
		"tx_reveal", [{"operation": "map_reveal", "arguments": {"depth": 2}}], 0
	)
	suite.assert_true(bool(reveal.get("ok", false)), "map reveal prepares")
	suite.assert_equal(authority.snapshot(), before, "route prepare has no side effects")
	var revealed: Dictionary = authority.commit_operations(reveal.get("ticket", {}))
	suite.assert_true(bool(revealed.get("ok", false)), "map reveal commits")
	suite.assert_true(_node(authority.snapshot()["plan"], "event_b").get("revealed", false), "reveal reaches authored depth")
	var forged_route_receipt := (revealed.get("receipt", {}) as Dictionary).duplicate(true)
	forged_route_receipt["before"] = (forged_route_receipt["after"] as Dictionary).duplicate(true)
	_resign(forged_route_receipt)
	suite.assert_true(not bool(authority.rollback_operations(forged_route_receipt).get("ok", false)), "re-signed forged route receipt rejects")
	suite.assert_true(bool(authority.rollback_operations(revealed.get("receipt", {})).get("ok", false)), "map reveal rolls back")
	suite.assert_equal(authority.snapshot(), before, "map reveal rollback is byte-identical")
	var skipped: Dictionary = authority.prepare_operations(
		"tx_skip", [{"operation": "route_skip", "arguments": {"rooms": 2}}], 0
	)
	suite.assert_true(bool(skipped.get("ok", false)), "lowest-choice viable route skip prepares")
	var skip_commit: Dictionary = authority.commit_operations(skipped.get("ticket", {}))
	suite.assert_true(bool(skip_commit.get("ok", false)), "route skip commits through one receipt")
	var plan: Dictionary = authority.snapshot()["plan"]
	suite.assert_equal(plan["current_node_id"], "event_b", "route skip lands after two edges")
	suite.assert_true(bool(_node(plan, "combat_a")["cleared"]), "intermediate skipped room auto-clears")
	suite.assert_true((plan["abandoned_node_ids"] as Array).has("shop_a"), "unselected branch is abandoned")
	for restricted_type: String in ["rest", "shop", "boss"]:
		var restricted = EventRouteAuthorityScript.new()
		var restricted_plan := _route_plan()
		_node(restricted_plan, "combat_a")["room_type"] = restricted_type
		_node(restricted_plan, "shop_a")["room_type"] = restricted_type
		restricted_plan["generation_digest"] = FloorPlanScript.compute_generation_digest(restricted_plan)
		suite.assert_true(restricted.configure(restricted_plan), "%s route fixture configures" % restricted_type)
		suite.assert_equal(
			restricted.prepare_operations("tx_restricted_%s" % restricted_type, [{"operation": "route_skip", "arguments": {"rooms": 2}}], 0).get("code"),
			&"ROUTE_RESTRICTED",
			"route skip rejects %s traversal" % restricted_type
		)
	var shallow = EventRouteAuthorityScript.new()
	var shallow_plan := _route_plan()
	shallow_plan["current_node_id"] = "event_b"
	shallow_plan["selected_edge_ids"] = [
		"edge_entry_event", "edge_event_combat", "edge_combat_event",
	]
	shallow_plan["visited_node_ids"] = ["entry", "event_a", "combat_a", "event_b"]
	shallow_plan["abandoned_node_ids"] = ["shop_a"]
	shallow_plan["revision"] = 3
	for visited_id: String in ["combat_a", "event_b"]:
		var visited_node := _node(shallow_plan, visited_id)
		visited_node["visited"] = true
		visited_node["revealed"] = true
	_node(shallow_plan, "combat_a")["cleared"] = true
	suite.assert_true(shallow.configure(shallow_plan), "shallow route fixture configures")
	suite.assert_equal(
		shallow.prepare_operations("tx_too_shallow", [{"operation": "route_skip", "arguments": {"rooms": 2}}], 0).get("code"),
		&"ROUTE_DEPTH_INSUFFICIENT",
		"route skip rejects insufficient depth"
	)


func _test_route_outputs_remain_canonical_floor_plans(suite) -> void:
	var floors := _load_json_array(FLOORS_PATH)
	var templates := _load_json_array(ROOM_TEMPLATES_PATH)
	suite.assert_true(not floors.is_empty() and not templates.is_empty(), "canonical route fixtures load")
	if floors.is_empty() or templates.is_empty():
		return
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(20261002, floors[0], templates)
	suite.assert_true(bool(generated.get("ok", false)), "canonical FloorPlan fixture generates")
	if not bool(generated.get("ok", false)):
		return
	var reveal_authority = EventRouteAuthorityScript.new()
	reveal_authority.configure(generated["plan"])
	var reveal: Dictionary = reveal_authority.prepare_operations(
		"tx_canonical_reveal", [{"operation": "map_reveal", "arguments": {"depth": 3}}], 0
	)
	var reveal_commit: Dictionary = reveal_authority.commit_operations(reveal.get("ticket", {}))
	suite.assert_true(bool(reveal_commit.get("ok", false)), "canonical map reveal commits")
	var revealed_plan: Dictionary = reveal_authority.snapshot()["plan"]
	suite.assert_true(
		bool(FloorPlanScript.new().configure(revealed_plan, floors[0], templates).get("ok", false)),
		"map reveal preserves canonical FloorPlan revision"
	)

	var found_multi_abandoned := false
	for seed: int in range(20261002, 20261102):
		var candidate: Dictionary = FloorPlanGeneratorScript.new().generate(seed, floors[0], templates)
		if not bool(candidate.get("ok", false)):
			continue
		var branch_plan := _plan_at_wide_branch(candidate["plan"] as Dictionary)
		if branch_plan.is_empty():
			continue
		if not bool(FloorPlanScript.new().configure(branch_plan, floors[0], templates).get("ok", false)):
			continue
		var route_authority = EventRouteAuthorityScript.new()
		if not route_authority.configure(branch_plan):
			continue
		var prepared: Dictionary = route_authority.prepare_operations(
			"tx_canonical_skip_%d" % seed,
			[{"operation": "route_skip", "arguments": {"rooms": 1}}],
			0
		)
		if not bool(prepared.get("ok", false)):
			continue
		var committed: Dictionary = route_authority.commit_operations(prepared.get("ticket", {}))
		if not bool(committed.get("ok", false)):
			continue
		var after_plan: Dictionary = route_authority.snapshot()["plan"]
		var canonical: Dictionary = FloorPlanScript.new().configure(after_plan, floors[0], templates)
		suite.assert_true(bool(canonical.get("ok", false)), "route skip preserves canonical FloorPlan for seed %d" % seed)
		var abandoned := after_plan["abandoned_node_ids"] as Array
		if abandoned.size() >= 2:
			var abandoned_lookup: Dictionary = {}
			for node_id: Variant in abandoned:
				abandoned_lookup[str(node_id)] = true
			var expected_order: Array[String] = []
			for node_value: Variant in after_plan["nodes"]:
				var node_id := str((node_value as Dictionary)["id"])
				if abandoned_lookup.has(node_id):
					expected_order.append(node_id)
			suite.assert_equal(abandoned, expected_order, "abandoned nodes retain canonical plan node order")
			found_multi_abandoned = true
			break
	suite.assert_true(found_multi_abandoned, "fixture covers multiple abandoned nodes")


func _test_all_ten_consequences_and_exactly_once(suite) -> void:
	var fixture := _runtime_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var event_ticket: Dictionary = fixture["event_ticket"]
	var consequences: Array = [
		{"operation": "resource_delta", "arguments": {"resource": "gold", "amount": -10}},
		{"operation": "health_delta", "arguments": {"amount": -5.0, "nonlethal": true}},
		{"operation": "curse_add", "arguments": {"curse_id": "curse_brittle_fortune"}},
		{"operation": "temporary_modifier", "arguments": {"modifier_id": "chronal_grace", "duration_rooms": 3, "magnitude": 1.15}},
		{"operation": "map_reveal", "arguments": {"depth": 1}},
		{"operation": "narrative_flag", "arguments": {"flag": "event_committed", "value": true}},
		{"operation": "reward_draft", "arguments": {"pool_id": "item", "count": 2}},
	]
	var before: Dictionary = runtime.call("snapshot")
	var prepared: Dictionary = runtime.call(
		"prepare_consequences", "tx_event_main", consequences, _context(event_ticket)
	)
	suite.assert_true(bool(prepared.get("ok", false)), "mixed consequence transaction prepares")
	suite.assert_equal(runtime.call("snapshot"), before, "runtime prepare is globally side-effect free")
	for participant: String in ["resource", "health", "economy", "modifier", "route", "event_state"]:
		var participant_object: Object = fixture[participant]
		var participant_before := (before["participant_snapshots"] as Dictionary)[participant] as Dictionary
		suite.assert_true(bool(participant_object.call("can_restore_snapshot", participant_before.duplicate(true))), "%s remains usable after abandoned prepare" % participant)
	var retry_prepared: Dictionary = runtime.call(
		"prepare_consequences", "tx_event_main", consequences, _context(event_ticket)
	)
	suite.assert_true(bool(retry_prepared.get("ok", false)), "abandoned runtime ticket does not block a fresh prepare")
	prepared = retry_prepared
	var forged_ticket := (prepared.get("ticket", {}) as Dictionary).duplicate(true)
	forged_ticket["before"] = runtime.call("snapshot")
	(forged_ticket["context"] as Dictionary)["result_key"] = "EVENT_RESULT_FORGED"
	_resign(forged_ticket)
	suite.assert_equal(runtime.call("commit_consequences", forged_ticket).get("code"), &"TICKET_INVALID", "re-signed forged runtime ticket rejects")
	var committed: Dictionary = runtime.call("commit_consequences", prepared.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "mixed consequence transaction commits")
	var snapshot: Dictionary = runtime.call("snapshot")
	suite.assert_true(runtime.call("_normalize_snapshot", snapshot) != {}, "committed pending snapshot validates for compensation")
	for participant: String in snapshot["participant_snapshots"]:
		var authority: Object = runtime.get("_%s" % participant)
		if authority != null:
			suite.assert_true(authority.call("can_restore_snapshot", snapshot["participant_snapshots"][participant]), "committed participant validates: %s" % participant)
	suite.assert_equal(fixture["economy"].balance(), 90, "gold consequence debits real economy authority")
	suite.assert_equal(fixture["economy"].revision(), 1, "gold consequence advances economy revision once")
	suite.assert_equal(
		fixture["economy"].ledger(),
		[{"transaction_id": "tx_event_main", "operation": "gold_delta", "amount": -10, "revision": 1}],
		"gold consequence appends the replay economy ledger"
	)
	suite.assert_true(not (fixture["resource"].snapshot()["resources"] as Dictionary).has("gold"), "resource authority never shadows gold")
	suite.assert_equal((snapshot["completed_transaction_ids"] as Array).size(), 1, "transaction completes once")
	suite.assert_equal((snapshot["publications"] as Array).size(), 1, "outcome publishes once")
	suite.assert_equal(
		runtime.call("commit_consequences", prepared.get("ticket", {})).get("code"),
		&"ALREADY_COMMITTED",
		"duplicate commit rejects without republishing"
	)
	suite.assert_equal((runtime.call("snapshot")["publications"] as Array).size(), 1, "duplicate commit cannot republish")
	var forged_receipt := (committed.get("receipt", {}) as Dictionary).duplicate(true)
	forged_receipt["before"] = (forged_receipt["after"] as Dictionary).duplicate(true)
	_resign(forged_receipt)
	suite.assert_equal(runtime.call("rollback_consequences", forged_receipt).get("code"), &"RECEIPT_STALE", "re-signed forged runtime receipt rejects")
	suite.assert_true(bool(runtime.call("rollback_consequences", committed.get("receipt", {})).get("ok", false)), "mixed transaction rolls back")
	suite.assert_equal(runtime.call("snapshot"), before, "global rollback is byte-identical")
	suite.assert_equal(fixture["economy"].balance(), 100, "gold rollback restores economy balance")
	suite.assert_equal(fixture["economy"].ledger(), [], "gold rollback removes economy ledger entry")

	var encounter_fixture := _runtime_fixture("tx_event_encounter")
	var encounter: Dictionary = encounter_fixture["runtime"].call(
		"prepare_consequences",
		"tx_event_encounter",
		[
			{"operation": "curse_remove", "arguments": {"curse_id": "curse_fickle_time"}},
			{"operation": "encounter_start", "arguments": {"encounter_id": "encounter_profile_ruins_adapter_v1"}},
		],
		_context(encounter_fixture["event_ticket"])
	)
	suite.assert_true(bool(encounter.get("ok", false)), "curse removal and encounter reservation prepare")
	suite.assert_true(bool(encounter_fixture["runtime"].call("commit_consequences", encounter["ticket"]).get("ok", false)), "encounter reservation commits")
	suite.assert_equal(encounter_fixture["event_state"].snapshot()["pending_encounter"].get("encounter_id"), "encounter_profile_ruins_adapter_v1", "encounter continuation is authenticated")

	var skip_fixture := _runtime_fixture("tx_event_skip")
	var skip: Dictionary = skip_fixture["runtime"].call(
		"prepare_consequences",
		"tx_event_skip",
		[{"operation": "route_skip", "arguments": {"rooms": 2}}],
		_context(skip_fixture["event_ticket"])
	)
	suite.assert_true(bool(skip.get("ok", false)), "tenth consequence route_skip prepares")
	suite.assert_true(bool(skip_fixture["runtime"].call("commit_consequences", skip["ticket"]).get("ok", false)), "tenth consequence route_skip commits")


func _test_prepare_is_closed_and_side_effect_free(suite) -> void:
	var fixture := _runtime_fixture("tx_closed")
	var runtime: RefCounted = fixture["runtime"]
	var context := _context(fixture["event_ticket"])
	context["hidden_override"] = true
	var before: Dictionary = runtime.call("snapshot")
	var invalid_context: Dictionary = runtime.call(
		"prepare_consequences", "tx_closed", [{"operation": "map_reveal", "arguments": {"depth": 1}}], context
	)
	suite.assert_equal(invalid_context.get("code"), &"INVALID_CONTEXT", "unknown context field fails closed")
	var invalid_operation: Dictionary = runtime.call(
		"prepare_consequences", "tx_closed", [{"operation": "map_reveal", "arguments": {"depth": 1, "debug": true}}], _context(fixture["event_ticket"])
	)
	suite.assert_equal(invalid_operation.get("code"), &"INVALID_CONSEQUENCE", "unknown argument fails closed")
	var forged_context := _context(fixture["event_ticket"])
	forged_context["result_key"] = "EVENT_RESULT_FORGED"
	var forged_pending: Dictionary = runtime.call(
		"prepare_consequences",
		"tx_closed",
		[{"operation": "reward_draft", "arguments": {"pool_id": "item", "count": 1}}],
		forged_context
	)
	suite.assert_equal(forged_pending.get("code"), &"INVALID_CONTEXT", "pending reward binds authored outcome key")
	suite.assert_equal(runtime.call("snapshot"), before, "rejected prepares mutate nothing")


func _test_commit_failure_compensates_in_reverse(suite) -> void:
	var fixture := _runtime_fixture("tx_compensate", true, false)
	var runtime: RefCounted = fixture["runtime"]
	var before: Dictionary = runtime.call("snapshot")
	var prepared: Dictionary = runtime.call(
		"prepare_consequences",
		"tx_compensate",
		[
			{"operation": "resource_delta", "arguments": {"resource": "gold", "amount": -10}},
			{"operation": "health_delta", "arguments": {"amount": -5.0, "nonlethal": true}},
			{"operation": "map_reveal", "arguments": {"depth": 1}},
		],
		_context(fixture["event_ticket"])
	)
	suite.assert_true(bool(prepared.get("ok", false)), "failure-stage transaction prepares")
	var committed: Dictionary = runtime.call("commit_consequences", prepared.get("ticket", {}))
	suite.assert_equal(committed.get("code"), &"PARTICIPANT_COMMIT_FAILED", "typed participant commit failure returns")
	suite.assert_equal(runtime.call("snapshot"), before, "successful compensation restores every participant")


func _test_commit_order_and_failure_stage_compensation(suite) -> void:
	var expected_by_stage := {
		"": ["commit:health", "commit:resource", "commit:economy", "commit:route", "commit:modifier", "commit:event_state"],
		"health": ["commit:health"],
		"resource": ["commit:health", "commit:resource", "rollback:health"],
		"economy": ["commit:health", "commit:resource", "commit:economy", "rollback:economy", "rollback:resource", "rollback:health"],
		"route": ["commit:health", "commit:resource", "commit:economy", "commit:route", "rollback:economy", "rollback:resource", "rollback:health"],
		"modifier": ["commit:health", "commit:resource", "commit:economy", "commit:route", "commit:modifier", "rollback:route", "rollback:economy", "rollback:resource", "rollback:health"],
		"event_state": ["commit:health", "commit:resource", "commit:economy", "commit:route", "commit:modifier", "commit:event_state", "rollback:event_state", "rollback:modifier", "rollback:route", "rollback:economy", "rollback:resource", "rollback:health"],
	}
	for failure_stage: String in ["", "health", "resource", "economy", "route", "modifier", "event_state"]:
		var fixture := _traced_runtime_fixture(failure_stage)
		var runtime: RefCounted = fixture["runtime"]
		var before: Dictionary = runtime.call("snapshot")
		var prepared: Dictionary = runtime.call(
			"prepare_consequences",
			str(fixture["transaction_id"]),
			[
				{"operation": "health_delta", "arguments": {"amount": -5.0, "nonlethal": true}},
				{"operation": "resource_delta", "arguments": {"resource": "time_shard", "amount": -1}},
				{"operation": "resource_delta", "arguments": {"resource": "gold", "amount": -10}},
				{"operation": "map_reveal", "arguments": {"depth": 1}},
				{"operation": "narrative_flag", "arguments": {"flag": "trace_complete", "value": true}},
			],
			_context(fixture["event_ticket"])
		)
		suite.assert_true(bool(prepared.get("ok", false)), "%s stage transaction prepares" % (failure_stage if not failure_stage.is_empty() else "success"))
		var committed: Dictionary = runtime.call("commit_consequences", prepared.get("ticket", {}))
		if failure_stage.is_empty():
			suite.assert_true(bool(committed.get("ok", false)), "success trace commits")
		else:
			suite.assert_equal(committed.get("code"), &"PARTICIPANT_COMMIT_FAILED", "%s failure is typed" % failure_stage)
			suite.assert_equal(runtime.call("snapshot"), before, "%s failure restores byte-identical state" % failure_stage)
		suite.assert_equal(fixture["trace"], expected_by_stage[failure_stage], "%s stage follows fixed commit/reverse compensation order" % (failure_stage if not failure_stage.is_empty() else "success"))


func _test_failed_compensation_enters_integrity_terminal(suite) -> void:
	var fixture := _runtime_fixture("tx_integrity", true, true)
	var runtime: RefCounted = fixture["runtime"]
	var prepared: Dictionary = runtime.call(
		"prepare_consequences",
		"tx_integrity",
		[
			{"operation": "resource_delta", "arguments": {"resource": "time_shard", "amount": -1}},
			{"operation": "map_reveal", "arguments": {"depth": 1}},
		],
		_context(fixture["event_ticket"])
	)
	var committed: Dictionary = runtime.call("commit_consequences", prepared.get("ticket", {}))
	suite.assert_equal(committed.get("code"), &"INTEGRITY_TERMINAL", "failed compensation enters typed terminal path")
	suite.assert_true(not (runtime.call("snapshot")["integrity_failure"] as Dictionary).is_empty(), "terminal integrity evidence is retained")
	suite.assert_equal(runtime.call("prepare_consequences", "tx_after_terminal", [], {}).get("code"), &"INTEGRITY_TERMINAL", "integrity terminal blocks later work")


func _test_snapshot_restore_is_atomic_and_strict(suite) -> void:
	var fixture := _runtime_fixture("tx_restore")
	var runtime: RefCounted = fixture["runtime"]
	var saved: Dictionary = runtime.call("snapshot")
	var forged := saved.duplicate(true)
	forged["debug"] = true
	suite.assert_true(not bool(runtime.call("can_restore_snapshot", forged)), "unknown runtime snapshot field fails closed")
	var duplicate_publications := saved.duplicate(true)
	duplicate_publications["completed_transaction_ids"] = ["tx_a", "tx_b"]
	duplicate_publications["revision"] = 2
	duplicate_publications["publications"] = [
		{"transaction_id": "tx_a", "phase": "resolved", "result_key": "EVENT_RESULT_A", "pending_kind": ""},
		{"transaction_id": "tx_a", "phase": "resolved", "result_key": "EVENT_RESULT_A", "pending_kind": ""},
	]
	suite.assert_true(not bool(runtime.call("can_restore_snapshot", duplicate_publications)), "duplicate publications cannot satisfy completed id set")
	suite.assert_true(bool(runtime.call("restore_snapshot", saved)), "canonical runtime snapshot restores")
	suite.assert_equal(runtime.call("snapshot"), saved, "runtime restore is byte-identical")
	var old_prepared: Dictionary = runtime.call(
		"prepare_consequences",
		"tx_restore",
		[{"operation": "map_reveal", "arguments": {"depth": 1}}],
		_context(fixture["event_ticket"])
	)
	suite.assert_true(bool(old_prepared.get("ok", false)), "pre-restore ticket fixture prepares")
	suite.assert_true(bool(runtime.call("restore_snapshot", saved)), "same-state restore rotates runtime capability")
	suite.assert_equal(runtime.call("commit_consequences", old_prepared.get("ticket", {})).get("code"), &"TICKET_INVALID", "pre-restore runtime ticket is revoked")


func _runtime_fixture(
	transaction_id: String = "tx_event_main",
	fail_route_commit: bool = false,
	fail_resource_rollback: bool = false
) -> Dictionary:
	var resource_inner = EventResourceAuthorityScript.new()
	resource_inner.configure({"time_shard": 2, "forge_essence": 1})
	var resource: RefCounted = resource_inner
	if fail_resource_rollback:
		resource = FailingRollbackResourceAuthority.new(resource_inner)
	var health = EventHealthAuthorityScript.new()
	health.configure(50.0, 100.0)
	var modifier = EventModifierAuthorityScript.new()
	modifier.configure(["curse_fickle_time"], {}, [])
	var route_inner = EventRouteAuthorityScript.new()
	route_inner.configure(_route_plan())
	var route: RefCounted = route_inner
	if fail_route_commit:
		route = FailingRouteAuthority.new(route_inner)
	var event_state = DungeonEventRunStateScript.new()
	event_state.configure("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
	event_state.assign_event({
		"floor_id": "floor_01_ruins",
		"floor_index": 1,
		"node_id": "event_a",
		"event_id": "event_test",
		"repeat_policy": "repeatable",
	}, 0)
	var reserved: Dictionary = event_state.reserve_option(
		"floor_01_ruins:event_a", transaction_id, "commit", "commit_outcome", "EVENT_RESULT_TEST", 1
	)
	var runtime = ConsequenceRuntimeScript.new()
	var economy = RunEconomyStateScript.new()
	economy.configure(_load_economy_profile(), 100)
	runtime.configure(resource, health, economy, modifier, route, event_state)
	return {
		"runtime": runtime,
		"resource": resource,
		"health": health,
		"economy": economy,
		"modifier": modifier,
		"route": route,
		"event_state": event_state,
		"event_ticket": reserved["ticket"],
	}


func _traced_runtime_fixture(failure_stage: String) -> Dictionary:
	var transaction_id := "tx_trace_%s" % (failure_stage if not failure_stage.is_empty() else "success")
	var base := _runtime_fixture(transaction_id)
	var trace: Array = []
	var resource = TracingScalarAuthority.new(base["resource"], "resource", trace, failure_stage == "resource")
	var health = TracingScalarAuthority.new(base["health"], "health", trace, failure_stage == "health")
	var economy = TracingEconomyAuthority.new(base["economy"], trace, failure_stage == "economy")
	var route = TracingOperationsAuthority.new(base["route"], "route", trace, failure_stage == "route")
	var modifier = TracingOperationsAuthority.new(base["modifier"], "modifier", trace, failure_stage == "modifier")
	var event_state = TracingEventState.new(base["event_state"], trace, failure_stage == "event_state")
	var runtime = ConsequenceRuntimeScript.new()
	runtime.configure(resource, health, economy, modifier, route, event_state)
	return {
		"runtime": runtime,
		"trace": trace,
		"transaction_id": transaction_id,
		"event_ticket": base["event_ticket"],
	}


func _load_economy_profile() -> Dictionary:
	var file := FileAccess.open(ECONOMY_PROFILE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array or (parsed as Array).is_empty() or not (parsed as Array)[0] is Dictionary:
		return {}
	return ((parsed as Array)[0] as Dictionary).duplicate(true)


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Array).duplicate(true) if parsed is Array else []


func _context(event_ticket: Dictionary) -> Dictionary:
	return {
		"event_ticket": event_ticket.duplicate(true),
		"result_key": "EVENT_RESULT_TEST",
	}


func _route_plan() -> Dictionary:
	var plan := {
		"schema_version": 1,
		"generator_version": "floor_plan_v1",
		"run_seed": 42,
		"floor_id": "floor_01_ruins",
		"floor_index": 0,
		"entry_node_id": "entry",
		"boss_node_id": "boss",
		"current_node_id": "event_a",
		"nodes": [
			_node_data("entry", 0, "entry", true, true, true),
			_node_data("event_a", 1, "event", true, true, true),
			_node_data("combat_a", 2, "combat", false, false, false),
			_node_data("shop_a", 2, "combat", false, false, false),
			_node_data("event_b", 3, "event", false, false, false),
			_node_data("boss", 4, "boss", false, false, false),
		],
		"edges": [
			_edge("edge_entry_event", "entry", "event_a", 0),
			_edge("edge_event_combat", "event_a", "combat_a", 0),
			_edge("edge_event_shop", "event_a", "shop_a", 1),
			_edge("edge_combat_event", "combat_a", "event_b", 0),
			_edge("edge_shop_event", "shop_a", "event_b", 0),
			_edge("edge_event_boss", "event_b", "boss", 0),
		],
		"selected_edge_ids": ["edge_entry_event"],
		"visited_node_ids": ["entry", "event_a"],
		"abandoned_node_ids": [],
		"generation_digest": "",
		"revision": 1,
	}
	plan["generation_digest"] = FloorPlanScript.compute_generation_digest(plan)
	return plan


func _node_data(id: String, layer: int, room_type: String, revealed: bool, visited: bool, cleared: bool) -> Dictionary:
	return {
		"id": id,
		"layer": layer,
		"room_type": room_type,
		"template_id": "template_%s" % id,
		"encounter_id": "",
		"event_id": "event_test" if room_type == "event" else "",
		"merchant_id": "",
		"reward_policy_id": "reward_policy_test",
		"seed_channel_suffix": id,
		"revealed": revealed,
		"visited": visited,
		"cleared": cleared,
	}


func _edge(id: String, source: String, destination: String, order: int) -> Dictionary:
	return {
		"id": id,
		"source_node_id": source,
		"destination_node_id": destination,
		"choice_order": order,
		"locked": false,
		"route_summary_facts": {"room_type": "combat", "template_id": "template_test"},
	}


func _node(plan_or_snapshot: Dictionary, node_id: String) -> Dictionary:
	var nodes: Array = plan_or_snapshot.get("nodes", [])
	for value: Variant in nodes:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == node_id:
			return value as Dictionary
	return {}


func _plan_at_wide_branch(source: Dictionary) -> Dictionary:
	var outgoing: Dictionary = {}
	for edge_value: Variant in source.get("edges", []):
		var edge := edge_value as Dictionary
		var source_id := str(edge["source_node_id"])
		if not outgoing.has(source_id):
			outgoing[source_id] = []
		(outgoing[source_id] as Array).append(edge.duplicate(true))
	for edge_values: Variant in outgoing.values():
		(edge_values as Array).sort_custom(func(left: Variant, right: Variant) -> bool:
			return int((left as Dictionary)["choice_order"]) < int((right as Dictionary)["choice_order"])
		)
	var queue: Array[Dictionary] = [{"node_id": "entry", "path": []}]
	var seen: Dictionary = {}
	var selected_path: Array = []
	var target := ""
	while not queue.is_empty():
		var cursor := queue.pop_front() as Dictionary
		var node_id := str(cursor["node_id"])
		if seen.has(node_id):
			continue
		seen[node_id] = true
		var choices := outgoing.get(node_id, []) as Array
		if choices.size() >= 3:
			target = node_id
			selected_path = (cursor["path"] as Array).duplicate(true)
			break
		for edge_value: Variant in choices:
			var path := (cursor["path"] as Array).duplicate(true)
			path.append((edge_value as Dictionary).duplicate(true))
			queue.append({"node_id": str((edge_value as Dictionary)["destination_node_id"]), "path": path})
	if target.is_empty():
		return {}
	var plan := source.duplicate(true)
	plan["selected_edge_ids"] = []
	plan["visited_node_ids"] = ["entry"]
	plan["current_node_id"] = target
	for node_value: Variant in plan["nodes"]:
		var node := node_value as Dictionary
		var is_entry := str(node["id"]) == "entry"
		node["visited"] = is_entry
		node["revealed"] = is_entry
		node["cleared"] = is_entry
	for edge_value: Variant in selected_path:
		var edge := edge_value as Dictionary
		(plan["selected_edge_ids"] as Array).append(str(edge["id"]))
		var destination_id := str(edge["destination_node_id"])
		(plan["visited_node_ids"] as Array).append(destination_id)
		var node := _node(plan, destination_id)
		node["visited"] = true
		node["revealed"] = true
		node["cleared"] = true
	plan["revision"] = (plan["selected_edge_ids"] as Array).size()
	plan["abandoned_node_ids"] = _canonical_abandoned(plan)
	return plan


func _canonical_abandoned(plan: Dictionary) -> Array[String]:
	var outgoing: Dictionary = {}
	for node_value: Variant in plan["nodes"]:
		outgoing[str((node_value as Dictionary)["id"])] = []
	for edge_value: Variant in plan["edges"]:
		var edge := edge_value as Dictionary
		(outgoing[str(edge["source_node_id"])] as Array).append(edge)
	var reachable: Dictionary = {}
	var pending: Array[String] = [str(plan["current_node_id"])]
	while not pending.is_empty():
		var node_id: String = pending.pop_front()
		if reachable.has(node_id):
			continue
		reachable[node_id] = true
		for edge_value: Variant in outgoing.get(node_id, []):
			var edge := edge_value as Dictionary
			if not bool(edge["locked"]):
				pending.append(str(edge["destination_node_id"]))
	var result: Array[String] = []
	for node_value: Variant in plan["nodes"]:
		var node_id := str((node_value as Dictionary)["id"])
		if not reachable.has(node_id) and not (plan["visited_node_ids"] as Array).has(node_id):
			result.append(node_id)
	return result


func _resign(value: Dictionary) -> void:
	var unsigned := value.duplicate(true)
	unsigned.erase("fingerprint")
	value["fingerprint"] = JSON.stringify(unsigned, "", true, true).sha256_text()
