extends Node

const MerchantRuntimeScript := preload("res://scripts/economy/merchant_runtime.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class FakePlayer extends RefCounted:
	var state := {"generation": 1, "rewards": []}
	var publication_active := false
	var publication_count := 0

	func reward_effect_snapshot() -> Dictionary:
		return state.duplicate(true)

	func restore_reward_effect_snapshot(value: Dictionary) -> bool:
		state = value.duplicate(true)
		return true

	func reward_effect_apply_operation(_operation: Dictionary) -> Dictionary:
		return {"ok": true, "code": &"OK"}

	func reward_effect_begin_publication() -> bool:
		if publication_active:
			return false
		publication_active = true
		return true

	func reward_effect_publication_can_commit() -> bool:
		return publication_active

	func reward_effect_commit_publication() -> bool:
		if not publication_active:
			return false
		publication_active = false
		publication_count += 1
		return true

	func reward_effect_rollback_publication() -> bool:
		if not publication_active:
			return false
		publication_active = false
		return true


class FakeEconomy extends RefCounted:
	var state := {"balance": 100, "revision": 0, "ledger": []}
	var pending: Dictionary = {}
	var consumed: Dictionary = {}
	var last_prepare_context: Dictionary = {}
	var fail_commit := false
	var fail_rollback := false

	func snapshot() -> Dictionary:
		return state.duplicate(true)

	func prepare_transaction(
		transaction_id: String,
		delta: int,
		expected_revision: int,
		context: Dictionary = {}
	) -> Dictionary:
		if consumed.has(transaction_id):
			return {"ok": false, "code": &"ALREADY_CONSUMED"}
		if not pending.is_empty() or expected_revision != int(state["revision"]):
			return {"ok": false, "code": &"STALE_REVISION"}
		if int(state["balance"]) + delta < 0:
			return {"ok": false, "code": &"INSUFFICIENT_GOLD"}
		pending = {
			"transaction_id": transaction_id,
			"delta": delta,
			"before": state.duplicate(true),
			"context": context.duplicate(true),
		}
		last_prepare_context = context.duplicate(true)
		return {"ok": true, "code": &"OK", "ticket": pending.duplicate(true)}

	func commit_transaction(ticket: Dictionary) -> Dictionary:
		if fail_commit or ticket != pending:
			return {"ok": false, "code": &"COMMIT_FAILED"}
		var before := state.duplicate(true)
		state["balance"] = int(state["balance"]) + int(ticket["delta"])
		state["revision"] = int(state["revision"]) + 1
		(state["ledger"] as Array).append(str(ticket["transaction_id"]))
		consumed[str(ticket["transaction_id"])] = true
		pending.clear()
		return {
			"ok": true,
			"code": &"OK",
			"receipt": {
				"transaction_id": str(ticket["transaction_id"]),
				"before": before,
				"after": state.duplicate(true),
			},
		}

	func rollback_transaction(value: Dictionary) -> Dictionary:
		if fail_rollback:
			return {"ok": false, "code": &"ROLLBACK_FAILED"}
		if value.has("after"):
			if state != value["after"]:
				return {"ok": false, "code": &"STALE_ROLLBACK"}
			state = (value["before"] as Dictionary).duplicate(true)
			consumed.erase(str(value["transaction_id"]))
		else:
			pending.clear()
		return {"ok": true, "code": &"ROLLED_BACK"}


class FakeInventory extends RefCounted:
	var state := {
		"revision": 0,
		"reroll_count": 0,
		"offers": [{
			"offer_id": "offer-1",
			"price": 50,
			"sold": false,
			"definition": {
				"id": "reward-1",
				"category": "item",
				"effects": {"heal": 10.0},
			},
		}],
	}
	var fail_commit := false
	var fail_reroll_commit := false
	var fail_rollback := false

	func snapshot() -> Dictionary:
		return state.duplicate(true)

	func prepare_purchase(
		transaction_id: String,
		before: Dictionary,
		offer_id: String,
		expected_revision: int
	) -> Dictionary:
		if before != state or expected_revision != int(state["revision"]):
			return {"ok": false, "code": &"STALE_INVENTORY"}
		var offer := (state["offers"] as Array)[0] as Dictionary
		if str(offer["offer_id"]) != offer_id or bool(offer["sold"]):
			return {"ok": false, "code": &"OFFER_UNAVAILABLE"}
		var after := state.duplicate(true)
		((after["offers"] as Array)[0] as Dictionary)["sold"] = true
		after["revision"] = int(after["revision"]) + 1
		return {
			"ok": true,
			"code": &"OK",
			"ticket": {
				"transaction_id": transaction_id,
				"offer": offer.duplicate(true),
				"before": state.duplicate(true),
				"after": after,
			},
		}

	func commit_purchase(ticket: Dictionary) -> Dictionary:
		if fail_commit or state != ticket.get("before", {}):
			return {"ok": false, "code": &"COMMIT_FAILED"}
		state = (ticket["after"] as Dictionary).duplicate(true)
		return {"ok": true, "code": &"OK", "receipt": ticket.duplicate(true)}

	func rollback_purchase(value: Dictionary) -> Dictionary:
		if fail_rollback:
			return {"ok": false, "code": &"ROLLBACK_FAILED"}
		if value.has("after") and state == value["after"]:
			state = (value["before"] as Dictionary).duplicate(true)
		return {"ok": true, "code": &"ROLLED_BACK"}

	func prepare_reroll(
		transaction_id: String,
		before: Dictionary,
		expected_revision: int
	) -> Dictionary:
		if before != state or expected_revision != int(state["revision"]):
			return {"ok": false, "code": &"STALE_INVENTORY"}
		var after := state.duplicate(true)
		after["revision"] = int(after["revision"]) + 1
		after["reroll_count"] = int(after["reroll_count"]) + 1
		((after["offers"] as Array)[0] as Dictionary)["offer_id"] = "offer-r%d" % int(after["reroll_count"])
		((after["offers"] as Array)[0] as Dictionary)["sold"] = false
		return {
			"ok": true,
			"code": &"OK",
			"ticket": {
				"transaction_id": transaction_id,
				"price": 40,
				"before": state.duplicate(true),
				"after": after,
			},
		}

	func commit_reroll(ticket: Dictionary) -> Dictionary:
		if fail_reroll_commit or state != ticket.get("before", {}):
			return {"ok": false, "code": &"COMMIT_FAILED"}
		state = (ticket["after"] as Dictionary).duplicate(true)
		return {"ok": true, "code": &"OK", "receipt": ticket.duplicate(true)}

	func rollback_reroll(value: Dictionary) -> Dictionary:
		return rollback_purchase(value)


class FakeRewardRuntime extends RefCounted:
	var fail_commit := false
	var fail_rollback := false
	var commit_failure_code: StringName = &"COMMIT_FAILED_ROLLED_BACK"

	func prepare(definition: Dictionary, snapshot: Dictionary) -> Dictionary:
		return {
			"ok": true,
			"code": &"OK",
			"plan": {"definition": definition.duplicate(true), "before": snapshot.duplicate(true)},
		}

	func commit(plan: Dictionary, player: Object) -> Dictionary:
		if fail_commit:
			return {"ok": false, "code": commit_failure_code}
		var before: Dictionary = player.call("reward_effect_snapshot")
		var next := before.duplicate(true)
		(next["rewards"] as Array).append(str((plan["definition"] as Dictionary)["id"]))
		player.set("state", next)
		return {
			"ok": true,
			"code": &"OK",
			"receipt": {"before": before, "after": next.duplicate(true)},
		}

	func rollback(receipt: Dictionary, player: Object) -> Dictionary:
		if fail_rollback:
			return {"ok": false, "code": &"ROLLBACK_FAILED"}
		player.set("state", (receipt["before"] as Dictionary).duplicate(true))
		return {"ok": true, "code": &"ROLLED_BACK"}


class StateSinkProbe extends RefCounted:
	var accept := false
	var payloads: Array[Dictionary] = []

	func commit_state(payload: Dictionary) -> bool:
		payloads.append(payload.duplicate(true))
		return accept


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_purchase_commits_all_participants(suite)
	_test_insufficient_gold_is_atomic(suite)
	_test_reward_failure_is_atomic(suite)
	_test_reward_rollback_failure_is_integrity_failure(suite)
	_test_economy_failure_rolls_back_player(suite)
	_test_inventory_failure_rolls_back_economy_and_player(suite)
	_test_rollback_failure_is_integrity_failure(suite)
	_test_duplicate_transaction_is_rejected(suite)
	_test_snapshot_restore_preserves_completed_transactions(suite)
	_test_reroll_commits_atomically(suite)
	_test_reroll_inventory_failure_compensates_economy(suite)
	_test_composite_receipt_rolls_back_committed_purchase(suite)
	_test_state_sink_failure_rolls_back_before_publication(suite)
	suite.finish(get_tree())


func _test_purchase_commits_all_participants(suite) -> void:
	var fixture := _fixture()
	var result: Dictionary = fixture.runtime.purchase_reward("tx_1", "offer-1", 0, 0)
	suite.assert_true(bool(result.get("ok", false)), "purchase commits")
	suite.assert_equal(fixture.economy.snapshot().get("balance"), 50, "purchase debits gold")
	suite.assert_equal(((fixture.inventory.snapshot()["offers"] as Array)[0] as Dictionary).get("sold"), true, "purchase marks offer sold")
	suite.assert_equal(fixture.player.state.get("rewards"), ["reward-1"], "purchase commits reward")
	suite.assert_equal(fixture.player.publication_count, 1, "purchase publishes player changes once")
	suite.assert_equal(result.get("transaction_id"), "tx_1", "receipt preserves transaction id")
	suite.assert_equal(
		fixture.economy.last_prepare_context.get("operation"),
		"gold_purchase",
		"purchase uses the replay-authorized economy operation"
	)


func _test_insufficient_gold_is_atomic(suite) -> void:
	var fixture := _fixture()
	fixture.economy.state["balance"] = 25
	var before := _snapshots(fixture)
	var result: Dictionary = fixture.runtime.purchase_reward("tx-poor", "offer-1", 0, 0)
	suite.assert_equal(result.get("code"), &"INSUFFICIENT_GOLD", "insufficient gold is explicit")
	suite.assert_equal(_snapshots(fixture), before, "insufficient gold mutates nothing")


func _test_reward_failure_is_atomic(suite) -> void:
	var fixture := _fixture()
	fixture.reward.fail_commit = true
	var before := _snapshots(fixture)
	var result: Dictionary = fixture.runtime.purchase_reward("tx-reward-fail", "offer-1", 0, 0)
	suite.assert_equal(result.get("code"), &"REWARD_COMMIT_FAILED", "reward failure is typed")
	suite.assert_equal(_snapshots(fixture), before, "reward failure mutates nothing")


func _test_reward_rollback_failure_is_integrity_failure(suite) -> void:
	var fixture := _fixture()
	fixture.reward.fail_commit = true
	fixture.reward.commit_failure_code = &"ROLLBACK_FAILED"
	var result: Dictionary = fixture.runtime.purchase_reward(
		"tx_reward_integrity", "offer-1", 0, 0
	)
	suite.assert_equal(
		result.get("code"), &"INTEGRITY_FAILURE",
		"reward internal rollback failure is terminal-grade"
	)


func _test_economy_failure_rolls_back_player(suite) -> void:
	var fixture := _fixture()
	fixture.economy.fail_commit = true
	var before := _snapshots(fixture)
	var result: Dictionary = fixture.runtime.purchase_reward("tx-economy-fail", "offer-1", 0, 0)
	suite.assert_equal(result.get("code"), &"ECONOMY_COMMIT_FAILED", "economy failure is typed")
	suite.assert_equal(_snapshots(fixture), before, "economy failure restores player and inventory")


func _test_inventory_failure_rolls_back_economy_and_player(suite) -> void:
	var fixture := _fixture()
	fixture.inventory.fail_commit = true
	var before := _snapshots(fixture)
	var result: Dictionary = fixture.runtime.purchase_reward("tx-inventory-fail", "offer-1", 0, 0)
	suite.assert_equal(result.get("code"), &"INVENTORY_COMMIT_FAILED", "inventory failure is typed")
	suite.assert_equal(_snapshots(fixture), before, "inventory failure restores economy and player")
	suite.assert_equal(fixture.player.publication_count, 0, "failed purchase publishes no player changes")


func _test_rollback_failure_is_integrity_failure(suite) -> void:
	var fixture := _fixture()
	fixture.inventory.fail_commit = true
	fixture.economy.fail_rollback = true
	var result: Dictionary = fixture.runtime.purchase_reward("tx-integrity", "offer-1", 0, 0)
	suite.assert_equal(result.get("code"), &"INTEGRITY_FAILURE", "failed compensation is terminal-grade")


func _test_duplicate_transaction_is_rejected(suite) -> void:
	var fixture := _fixture()
	var first: Dictionary = fixture.runtime.purchase_reward("tx-repeat", "offer-1", 0, 0)
	suite.assert_true(bool(first.get("ok", false)), "first transaction commits")
	var after := _snapshots(fixture)
	var second: Dictionary = fixture.runtime.purchase_reward("tx-repeat", "offer-1", 1, 1)
	suite.assert_equal(second.get("code"), &"ALREADY_CONSUMED", "duplicate transaction is rejected")
	suite.assert_equal(_snapshots(fixture), after, "duplicate transaction has no side effect")


func _test_snapshot_restore_preserves_completed_transactions(suite) -> void:
	var fixture := _fixture()
	var first: Dictionary = fixture.runtime.purchase_reward("tx_restore", "offer-1", 0, 0)
	suite.assert_true(bool(first.get("ok", false)), "snapshot fixture commits")
	var canonical: Dictionary = fixture.runtime.snapshot()
	suite.assert_true(fixture.runtime.can_restore_snapshot(canonical), "canonical runtime snapshot validates")

	var restored_fixture := _fixture()
	suite.assert_true(
		restored_fixture.runtime.restore_snapshot(canonical),
		"completed transaction snapshot restores"
	)
	var before := _snapshots(restored_fixture)
	var repeated: Dictionary = restored_fixture.runtime.purchase_reward(
		"tx_restore", "offer-1", 0, 0
	)
	suite.assert_equal(repeated.get("code"), &"ALREADY_CONSUMED", "restored transaction remains consumed")
	suite.assert_equal(_snapshots(restored_fixture), before, "restored duplicate mutates nothing")

	var unknown_field := canonical.duplicate(true)
	unknown_field["extra"] = true
	var duplicate_id := canonical.duplicate(true)
	duplicate_id["completed_transaction_ids"] = ["tx_restore", "tx_restore"]
	var empty_id := canonical.duplicate(true)
	empty_id["completed_transaction_ids"] = [""]
	for mutation: Dictionary in [
		{"label": "unknown field", "value": unknown_field},
		{"label": "duplicate id", "value": duplicate_id},
		{"label": "empty id", "value": empty_id},
	]:
		var runtime_before: Dictionary = restored_fixture.runtime.snapshot()
		suite.assert_true(
			not restored_fixture.runtime.restore_snapshot(mutation["value"]),
			"%s snapshot rejects" % mutation["label"]
		)
		suite.assert_equal(
			restored_fixture.runtime.snapshot(), runtime_before,
			"%s restore rejection is atomic" % mutation["label"]
		)


func _test_reroll_commits_atomically(suite) -> void:
	var fixture := _fixture()
	var result: Dictionary = fixture.runtime.reroll("tx_reroll", 0, 0)
	suite.assert_true(bool(result.get("ok", false)), "reroll commits")
	suite.assert_equal(fixture.economy.snapshot().get("balance"), 60, "reroll debits exact quote")
	suite.assert_equal(fixture.inventory.snapshot().get("reroll_count"), 1, "reroll advances inventory")
	suite.assert_equal(
		fixture.economy.last_prepare_context.get("operation"),
		"gold_reroll",
		"reroll uses the replay-authorized economy operation"
	)
	var after := _snapshots(fixture)
	var repeated: Dictionary = fixture.runtime.reroll("tx_reroll", 1, 1)
	suite.assert_equal(repeated.get("code"), &"ALREADY_CONSUMED", "duplicate reroll rejects")
	suite.assert_equal(_snapshots(fixture), after, "duplicate reroll mutates nothing")


func _test_reroll_inventory_failure_compensates_economy(suite) -> void:
	var fixture := _fixture()
	fixture.inventory.fail_reroll_commit = true
	var before := _snapshots(fixture)
	var result: Dictionary = fixture.runtime.reroll("tx_reroll_fail", 0, 0)
	suite.assert_equal(result.get("code"), &"INVENTORY_COMMIT_FAILED", "reroll inventory failure is typed")
	suite.assert_equal(_snapshots(fixture), before, "reroll inventory failure restores economy and inventory")


func _test_composite_receipt_rolls_back_committed_purchase(suite) -> void:
	var fixture := _fixture()
	var before := _snapshots(fixture)
	var committed: Dictionary = fixture.runtime.purchase_reward(
		"tx_composite", "offer-1", 0, 0
	)
	suite.assert_true(bool(committed.get("ok", false)), "composite fixture commits")
	var compensated: Dictionary = fixture.runtime.rollback_committed_transaction(committed)
	suite.assert_true(bool(compensated.get("ok", false)), "composite receipt compensates")
	suite.assert_equal(_snapshots(fixture), before, "composite compensation restores every participant")
	var retried: Dictionary = fixture.runtime.purchase_reward(
		"tx_composite", "offer-1", 0, 0
	)
	suite.assert_true(bool(retried.get("ok", false)), "compensated transaction ID can retry")


func _test_state_sink_failure_rolls_back_before_publication(suite) -> void:
	var sink := StateSinkProbe.new()
	var fixture := _fixture(Callable(sink, "commit_state"))
	var before := _snapshots(fixture)
	var result: Dictionary = fixture.runtime.purchase_reward(
		"tx_sink_reject", "offer-1", 0, 0
	)
	suite.assert_equal(result.get("code"), &"STATE_COMMIT_FAILED", "state sink rejection is typed")
	suite.assert_equal(_snapshots(fixture), before, "state sink rejection compensates all domains")
	suite.assert_equal(fixture.player.publication_count, 0, "state sink rejection publishes nothing")
	suite.assert_equal(sink.payloads.size(), 1, "state sink observes one canonical candidate")
	suite.assert_equal(
		(sink.payloads[0].get("transaction", {}) as Dictionary).get("transaction_id"),
		"tx_sink_reject",
		"state sink candidate keeps transaction identity"
	)


func _fixture(state_sink: Callable = Callable()) -> Dictionary:
	var economy := FakeEconomy.new()
	var inventory := FakeInventory.new()
	var reward := FakeRewardRuntime.new()
	var player := FakePlayer.new()
	var runtime = MerchantRuntimeScript.new()
	var configured: bool = runtime.configure(
		economy, inventory, reward, player, null, state_sink
	)
	assert(configured)
	return {
		"runtime": runtime,
		"economy": economy,
		"inventory": inventory,
		"reward": reward,
		"player": player,
	}


func _snapshots(fixture: Dictionary) -> Dictionary:
	return {
		"economy": fixture.economy.snapshot(),
		"inventory": fixture.inventory.snapshot(),
		"player": fixture.player.state.duplicate(true),
	}
