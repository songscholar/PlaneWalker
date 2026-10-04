extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunRuntimeFacadeScript := preload(
	"res://scripts/application/run_runtime_facade.gd"
)

const FIXED_SEED := 20261002


class FloorSettlementEconomyFault:
	extends RefCounted

	var base: RefCounted
	var fail_apply: bool = false
	var corrupt_commit_snapshot: bool = false
	var _settlement_committed: bool = false

	func _init(source: RefCounted) -> void:
		base = source

	func revision() -> int:
		return int(base.call("revision"))

	func balance() -> int:
		return int(base.call("balance"))

	func snapshot() -> Dictionary:
		var value: Dictionary = base.call("snapshot").duplicate(true)
		if corrupt_commit_snapshot and _settlement_committed:
			value["profile_id"] = "forged_profile"
		return value

	func prepare_transaction(transaction_id: String, delta: int, expected_revision: int, context: Dictionary = {}) -> Dictionary:
		return base.call("prepare_transaction", transaction_id, delta, expected_revision, context.duplicate(true))

	func commit_transaction(ticket: Dictionary) -> Dictionary:
		return base.call("commit_transaction", ticket.duplicate(true))

	func rollback_transaction(receipt_or_ticket: Dictionary) -> Dictionary:
		return base.call("rollback_transaction", receipt_or_ticket.duplicate(true))

	func can_restore_snapshot(value: Dictionary) -> bool:
		return bool(base.call("can_restore_snapshot", value.duplicate(true)))

	func apply_floor_transition(
		floor_index: int,
		expected_revision: int,
		transaction_id: String = ""
	) -> Dictionary:
		if fail_apply:
			return {
				"ok": false,
				"code": &"COMMIT_FAILED",
				"context": {"stage": "injected_floor_settlement"},
			}
		var result: Dictionary = base.call(
			"apply_floor_transition", floor_index, expected_revision, transaction_id
		)
		_settlement_committed = bool(result.get("ok", false))
		return result.duplicate(true)

	func restore_snapshot(value: Dictionary) -> bool:
		var restored := bool(base.call("restore_snapshot", value.duplicate(true)))
		if restored:
			_settlement_committed = false
		return restored


class CompleteFloorFaultOrchestrator:
	extends RefCounted

	var base: RefCounted
	var complete_floor_calls: int = 0

	func _init(source: RefCounted) -> void:
		base = source

	func snapshot() -> Dictionary:
		return base.call("snapshot").duplicate(true)

	func revision() -> int:
		return int(base.call("revision"))

	func phase() -> int:
		return int(base.call("phase"))

	func is_terminal() -> bool:
		return bool(base.call("is_terminal"))

	func floor_transaction_snapshot() -> Dictionary:
		return base.call("floor_transaction_snapshot").duplicate(true)

	func restore_floor_transaction_snapshot(value: Dictionary) -> bool:
		return bool(base.call(
			"restore_floor_transaction_snapshot", value.duplicate(true)
		))

	func complete_floor_node(node_id: String, expected_revision: int):
		return base.call("complete_floor_node", node_id, expected_revision)

	func commit_economy_transaction(
		economy_snapshot: Dictionary,
		merchant_snapshot: Dictionary,
		expected_revision: int
	):
		return base.call(
			"commit_economy_transaction",
			economy_snapshot.duplicate(true),
			merchant_snapshot.duplicate(true),
			expected_revision
		)

	func complete_floor(_context: Dictionary = {}, _expected_revision: int = -1):
		complete_floor_calls += 1
		return CommandResultScript.failure(
			&"COMMIT_FAILED",
			revision(),
			{"stage": "injected_complete_floor"}
		)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_under_cap_settlement_is_exactly_once(suite)
	_test_over_cap_settlement_is_deterministic(suite)
	_test_settlement_failure_restores_complete_transaction(suite)
	_test_run_state_sink_failure_restores_complete_transaction(suite)
	_test_complete_floor_failure_restores_complete_transaction(suite)
	suite.finish(get_tree())


func _test_under_cap_settlement_is_exactly_once(suite) -> void:
	var facade = _boss_ready_facade(suite, "floor-economy-under-cap")
	if facade == null:
		return
	var before: Dictionary = facade.snapshot()
	var completed = facade.complete_current_room()
	suite.assert_true(completed.ok, "under-cap Boss completion commits")
	if not completed.ok:
		return
	var after: Dictionary = facade.snapshot()
	var ledger: Array = after.get("run_economy", {}).get("ledger", [])
	var expected := _expected_room_income(1)
	expected.append({
		"transaction_id": "tx_floor_1_settlement", "operation": "gold_decay",
		"amount": 0, "revision": 4,
	})
	suite.assert_equal(before["run_economy"]["ledger"], _expected_room_income(1).slice(0, 2), "pre-Boss rooms already committed their exact income")
	suite.assert_equal(
		ledger,
		expected,
		"under-cap Boss completion appends exact Boss income and one zero-decay fact"
	)
	suite.assert_equal(after["run_economy"]["balance"], 140, "all three authored room incomes survive under-cap settlement")
	suite.assert_equal(
		after.get("run_economy", {}).get("settled_floor_indices"),
		[0],
		"under-cap Boss completion marks floor one settled"
	)
	suite.assert_equal(
		int(after.get("revision", -1)),
		int(before.get("revision", -1)) + 4,
		"Boss completion owns node, room income, settlement, and floor revisions"
	)
	var before_duplicate: Dictionary = after.duplicate(true)
	var duplicate = facade.complete_current_room()
	suite.assert_true(not duplicate.ok, "duplicate Boss completion rejects")
	suite.assert_equal(
		facade.snapshot(),
		before_duplicate,
		"duplicate Boss completion appends no ledger or floor fact"
	)


func _test_over_cap_settlement_is_deterministic(suite) -> void:
	var facade = _boss_ready_facade(suite, "floor-economy-over-cap", 1000)
	if facade == null:
		return
	var before: Dictionary = facade.snapshot()
	var completed = facade.complete_current_room()
	suite.assert_true(completed.ok, "over-cap Boss completion commits")
	if not completed.ok:
		return
	var economy: Dictionary = facade.snapshot().get("run_economy", {})
	suite.assert_equal(before["run_economy"]["balance"], 1080, "seed grant and two authored room incomes precede Boss settlement")
	var expected: Array = [{
		"transaction_id": "tx_test_seed_gold_floor-economy-over-cap",
		"operation": "gold_delta", "amount": 1000, "revision": 1,
	}]
	expected.append_array(_expected_room_income(2))
	expected.append({
		"transaction_id": "tx_floor_1_settlement", "operation": "gold_decay",
		"amount": -220, "revision": 5,
	})
	suite.assert_equal(
		economy.get("balance"),
		920,
		"floor-one overflow retains exactly half of gold above the 700 cap"
	)
	suite.assert_equal(
		economy.get("ledger"),
		expected,
		"over-cap Boss completion records the deterministic decay fact"
	)
	suite.assert_equal(
		completed.context.get("economy_settlement", {}).get("context", {}).get("decayed_gold"),
		220,
		"completion context reports the exact decayed amount"
	)
	suite.assert_equal(
		facade.snapshot().get("merchant_state"),
		before.get("merchant_state"),
		"floor settlement preserves merchant state"
	)


func _test_settlement_failure_restores_complete_transaction(suite) -> void:
	var facade = _boss_ready_facade(suite, "floor-economy-apply-failure", 1000)
	if facade == null:
		return
	var real_economy: RefCounted = facade.get("_economy_state")
	var fault := FloorSettlementEconomyFault.new(real_economy)
	fault.fail_apply = true
	facade.set("_economy_state", fault)
	var before: Dictionary = facade.snapshot()
	var failed = facade.complete_current_room()
	suite.assert_equal(failed.code, &"COMMIT_FAILED", "settlement failure propagates")
	_assert_complete_floor_rollback(
		suite, facade, fault, before, "settlement failure"
	)


func _test_run_state_sink_failure_restores_complete_transaction(suite) -> void:
	var facade = _boss_ready_facade(suite, "floor-economy-sink-failure", 1000)
	if facade == null:
		return
	var real_economy: RefCounted = facade.get("_economy_state")
	var fault := FloorSettlementEconomyFault.new(real_economy)
	fault.corrupt_commit_snapshot = true
	facade.set("_economy_state", fault)
	var before: Dictionary = facade.snapshot()
	var failed = facade.complete_current_room()
	suite.assert_equal(
		failed.code,
		&"INVALID_ARGUMENT",
		"RunState economy sink rejects a corrupted settlement snapshot"
	)
	_assert_complete_floor_rollback(
		suite, facade, fault, before, "RunState economy sink failure"
	)


func _test_complete_floor_failure_restores_complete_transaction(suite) -> void:
	var facade = _boss_ready_facade(suite, "floor-economy-complete-failure", 1000)
	if facade == null:
		return
	var real_orchestrator: RefCounted = facade.get("_orchestrator")
	var fault_orchestrator := CompleteFloorFaultOrchestrator.new(real_orchestrator)
	facade.set("_orchestrator", fault_orchestrator)
	var economy: RefCounted = facade.get("_economy_state")
	var before: Dictionary = facade.snapshot()
	var failed = facade.complete_current_room()
	suite.assert_equal(failed.code, &"COMMIT_FAILED", "complete-floor failure propagates")
	suite.assert_equal(
		fault_orchestrator.complete_floor_calls,
		1,
		"complete-floor failure is injected after the economy sink commits"
	)
	_assert_complete_floor_rollback(
		suite, facade, economy, before, "complete-floor failure"
	)


func _assert_complete_floor_rollback(
	suite,
	facade,
	economy_authority: RefCounted,
	before: Dictionary,
	label: String
) -> void:
	var after: Dictionary = facade.snapshot()
	suite.assert_equal(after, before, "%s restores the exact RunState snapshot" % label)
	suite.assert_equal(
		after.get("floor_plan"),
		before.get("floor_plan"),
		"%s restores the uncleared Boss floor plan" % label
	)
	suite.assert_equal(
		after.get("phase"), before.get("phase"), "%s restores Boss phase" % label
	)
	suite.assert_equal(
		after.get("revision"), before.get("revision"), "%s restores command revision" % label
	)
	suite.assert_equal(
		after.get("run_economy"),
		before.get("run_economy"),
		"%s restores RunState economy snapshot" % label
	)
	suite.assert_equal(
		after.get("merchant_state"),
		before.get("merchant_state"),
		"%s restores merchant snapshot" % label
	)
	suite.assert_equal(
		economy_authority.call("snapshot"),
		before.get("run_economy"),
		"%s restores the live economy authority" % label
	)


func _boss_ready_facade(suite, run_id: String, starting_gold: int = 0):
	var facade = RunRuntimeFacadeScript.new()
	var booted = facade.boot()
	suite.assert_true(booted.ok, "%s facade boots" % run_id)
	if not booted.ok:
		return null
	var started = facade.start_run(_launch_config(), run_id)
	suite.assert_true(started.ok, "%s Launch run starts" % run_id)
	if not started.ok:
		return null
	if starting_gold > 0:
		var granted = facade.grant_run_gold(
			"tx_test_seed_gold_%s" % run_id, starting_gold, "test_fixture"
		)
		suite.assert_true(granted.ok, "%s seed gold commits" % run_id)
		if not granted.ok:
			return null

	while str(facade.current_room_definition().get("room_type", "")) != "boss":
		var choices: Array[Dictionary] = facade.route_choices()
		suite.assert_true(not choices.is_empty(), "%s exposes the next route" % run_id)
		if choices.is_empty():
			return null
		var begun = facade.begin_route_transition(
			StringName(str(choices[0].get("edge_id", ""))),
			int(facade.snapshot().get("revision", -1))
		)
		suite.assert_true(begun.ok, "%s route begins" % run_id)
		if not begun.ok:
			return null
		var transition_id := str(begun.context.get("transition_id", ""))
		var finalized = facade.finalize_route_transition(
			transition_id, int(begun.new_revision)
		)
		suite.assert_true(finalized.ok, "%s route finalizes" % run_id)
		if not finalized.ok:
			return null
		var confirmed = facade.confirm_route_transition(
			transition_id, int(finalized.new_revision)
		)
		suite.assert_true(confirmed.ok, "%s route confirms" % run_id)
		if not confirmed.ok:
			return null
		if str(facade.current_room_definition().get("room_type", "")) == "boss":
			break
		var completed = facade.complete_current_room()
		suite.assert_true(completed.ok, "%s non-Boss room completes" % run_id)
		if not completed.ok:
			return null

	suite.assert_equal(
		str(facade.current_room_definition().get("room_type", "")),
		"boss",
		"%s reaches the Boss node" % run_id
	)
	return facade


func _launch_config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": FIXED_SEED,
	}


func _expected_room_income(first_revision: int) -> Array:
	return [
		{"transaction_id": "room_gold:floor_ruins_of_remnant:layer_01_a", "operation": "gold_delta", "amount": 30, "revision": first_revision},
		{"transaction_id": "room_gold:floor_ruins_of_remnant:layer_02_a", "operation": "gold_delta", "amount": 50, "revision": first_revision + 1},
		{"transaction_id": "room_gold:floor_ruins_of_remnant:boss", "operation": "gold_delta", "amount": 60, "revision": first_revision + 2},
	]
