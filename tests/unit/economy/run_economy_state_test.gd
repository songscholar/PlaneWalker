extends Node

const RunEconomyStateScript := preload("res://scripts/economy/run_economy_state.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_PATH := "res://data/content_packs/base/content/economy_profiles.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var profile := _load_profile()
	suite.assert_true(not profile.is_empty(), "Launch economy profile fixture loads")
	if profile.is_empty():
		suite.finish(get_tree())
		return
	_test_configure_and_balance(suite, profile)
	_test_prepare_commit_and_ledger(suite, profile)
	_test_pending_and_committed_rollback(suite, profile)
	_test_rejected_transactions_are_atomic(suite, profile)
	_test_gold_cap_and_overflow_decay(suite, profile)
	_test_snapshot_restore_and_validation(suite, profile)
	suite.finish(get_tree())


func _test_configure_and_balance(suite, profile: Dictionary) -> void:
	var economy = RunEconomyStateScript.new()
	var configured: Dictionary = economy.configure(profile, 120)
	suite.assert_true(bool(configured.get("ok", false)), "valid profile configures economy")
	suite.assert_equal(economy.balance(), 120, "configured economy exposes initial balance")
	suite.assert_equal(economy.revision(), 0, "configured economy starts at revision zero")
	suite.assert_equal(economy.ledger(), [], "configured economy starts with an empty ledger")

	var before: Dictionary = economy.snapshot()
	var invalid_profile := profile.duplicate(true)
	invalid_profile["gold_caps"] = [700]
	var rejected: Dictionary = economy.configure(invalid_profile, 999)
	suite.assert_true(not bool(rejected.get("ok", false)), "invalid profile is rejected")
	suite.assert_equal(economy.snapshot(), before, "failed configure preserves prior authority")
	suite.assert_true(
		not bool(economy.configure(profile, -1).get("ok", false)),
		"negative initial balance is rejected"
	)
	suite.assert_equal(economy.snapshot(), before, "negative initial balance is atomic")


func _test_prepare_commit_and_ledger(suite, profile: Dictionary) -> void:
	var economy = _configured(profile, 100)
	var prepared: Dictionary = economy.prepare_transaction(
		"tx_reward_0001",
		25,
		economy.revision(),
		{"operation": "gold_delta", "source_id": "room_reward"}
	)
	suite.assert_true(bool(prepared.get("ok", false)), "income transaction prepares")
	suite.assert_equal(economy.balance(), 100, "prepare reserves without publishing balance")
	suite.assert_equal(economy.revision(), 0, "prepare does not advance committed revision")
	var ticket: Dictionary = prepared.get("ticket", {})
	suite.assert_equal(ticket.get("before_balance"), 100, "ticket captures before balance")
	suite.assert_equal(ticket.get("after_balance"), 125, "ticket captures projected balance")

	var committed: Dictionary = economy.commit_transaction(ticket)
	suite.assert_true(bool(committed.get("ok", false)), "matching ticket commits")
	suite.assert_equal(economy.balance(), 125, "commit publishes balance")
	suite.assert_equal(economy.revision(), 1, "commit advances revision once")
	suite.assert_equal(
		economy.ledger(),
		[{"transaction_id": "tx_reward_0001", "operation": "gold_delta", "amount": 25, "revision": 1}],
		"commit appends Replay-compatible ledger entry"
	)
	var receipt: Dictionary = committed.get("receipt", {})
	suite.assert_equal(receipt.get("context", {}).get("source_id"), "room_reward", "receipt preserves transaction context")
	suite.assert_true(
		not bool(economy.commit_transaction(ticket).get("ok", false)),
		"committed ticket cannot commit twice"
	)
	suite.assert_equal(economy.balance(), 125, "duplicate commit preserves balance")


func _test_pending_and_committed_rollback(suite, profile: Dictionary) -> void:
	var economy = _configured(profile, 150)
	var pending: Dictionary = economy.prepare_transaction(
		"tx_purchase_0001", -70, 0, {"operation": "gold_purchase", "offer_id": "offer_sword"}
	)
	suite.assert_true(bool(pending.get("ok", false)), "purchase prepares against available balance")
	var before_rollback: Dictionary = economy.snapshot()
	var wrong_ticket := (pending.get("ticket", {}) as Dictionary).duplicate(true)
	wrong_ticket["amount"] = -60
	suite.assert_true(
		not bool(economy.rollback_transaction(wrong_ticket).get("ok", false)),
		"forged pending ticket cannot rollback"
	)
	suite.assert_equal(economy.snapshot(), before_rollback, "forged pending rollback is atomic")
	var rolled_pending: Dictionary = economy.rollback_transaction(pending.get("ticket", {}))
	suite.assert_true(bool(rolled_pending.get("ok", false)), "matching pending ticket rolls back")
	suite.assert_equal(economy.balance(), 150, "pending rollback preserves balance")
	suite.assert_equal(economy.revision(), 0, "pending rollback preserves revision")

	var retry: Dictionary = economy.prepare_transaction(
		"tx_purchase_0001", -70, 0, {"operation": "gold_purchase", "offer_id": "offer_sword"}
	)
	var committed: Dictionary = economy.commit_transaction(retry.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "rolled-back id can be retried")
	suite.assert_equal(economy.balance(), 80, "purchase commit debits balance")
	var forged_receipt := (committed.get("receipt", {}) as Dictionary).duplicate(true)
	forged_receipt["before"] = _configured(profile, 140).snapshot()
	forged_receipt["before_balance"] = 140
	var before_forged_receipt: Dictionary = economy.snapshot()
	suite.assert_true(
		not bool(economy.rollback_transaction(forged_receipt).get("ok", false)),
		"receipt cannot substitute an unrelated valid before snapshot"
	)
	suite.assert_equal(economy.snapshot(), before_forged_receipt, "forged receipt rollback is atomic")
	var rolled_commit: Dictionary = economy.rollback_transaction(committed.get("receipt", {}))
	suite.assert_true(bool(rolled_commit.get("ok", false)), "latest committed receipt compensates")
	suite.assert_equal(economy.balance(), 150, "committed rollback restores balance")
	suite.assert_equal(economy.revision(), 0, "committed rollback restores revision")
	suite.assert_equal(economy.ledger(), [], "committed rollback removes unpublished ledger entry")


func _test_rejected_transactions_are_atomic(suite, profile: Dictionary) -> void:
	var economy = _configured(profile, 50)
	var canonical: Dictionary = economy.snapshot()
	var invalid_cases: Array[Dictionary] = [
		{"label": "empty transaction id", "id": "", "delta": 1, "revision": 0, "context": {"operation": "gold_delta"}},
		{"label": "unstable transaction id", "id": "Bad Id", "delta": 1, "revision": 0, "context": {"operation": "gold_delta"}},
		{"label": "zero delta", "id": "tx_zero", "delta": 0, "revision": 0, "context": {"operation": "gold_delta"}},
		{"label": "unsupported operation", "id": "tx_bad_op", "delta": 1, "revision": 0, "context": {"operation": "mint_everything"}},
		{"label": "positive purchase", "id": "tx_positive_purchase", "delta": 1, "revision": 0, "context": {"operation": "gold_purchase"}},
		{"label": "stale revision", "id": "tx_stale", "delta": 1, "revision": 1, "context": {"operation": "gold_delta"}},
		{"label": "negative balance", "id": "tx_overdraw", "delta": -51, "revision": 0, "context": {"operation": "gold_purchase"}},
	]
	for case: Dictionary in invalid_cases:
		var result: Dictionary = economy.prepare_transaction(
			str(case["id"]), int(case["delta"]), int(case["revision"]), case["context"]
		)
		suite.assert_true(not bool(result.get("ok", false)), "%s is rejected" % case["label"])
		suite.assert_equal(economy.snapshot(), canonical, "%s preserves committed state" % case["label"])

	var pending: Dictionary = economy.prepare_transaction(
		"tx_pending", 10, 0, {"operation": "gold_delta"}
	)
	suite.assert_true(bool(pending.get("ok", false)), "pending fixture prepares")
	suite.assert_true(
		not bool(economy.prepare_transaction("tx_other", 5, 0, {"operation": "gold_delta"}).get("ok", false)),
		"second transaction is rejected while one is pending"
	)
	suite.assert_equal(economy.snapshot(), canonical, "pending collision preserves committed state")
	var committed: Dictionary = economy.commit_transaction(pending.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "pending fixture commits")
	var after_commit: Dictionary = economy.snapshot()
	suite.assert_true(
		not bool(economy.prepare_transaction("tx_pending", 10, 1, {"operation": "gold_delta"}).get("ok", false)),
		"committed transaction id cannot be reused"
	)
	suite.assert_equal(economy.snapshot(), after_commit, "duplicate transaction id is atomic")

	var later: Dictionary = economy.prepare_transaction(
		"tx_later", 5, 1, {"operation": "gold_delta"}
	)
	var later_commit: Dictionary = economy.commit_transaction(later.get("ticket", {}))
	suite.assert_true(bool(later_commit.get("ok", false)), "later transaction commits")
	var before_stale_rollback: Dictionary = economy.snapshot()
	suite.assert_true(
		not bool(economy.rollback_transaction(committed.get("receipt", {})).get("ok", false)),
		"non-latest committed receipt cannot rollback"
	)
	suite.assert_equal(economy.snapshot(), before_stale_rollback, "stale rollback preserves authority")


func _test_gold_cap_and_overflow_decay(suite, profile: Dictionary) -> void:
	var economy = _configured(profile, 1000)
	var settled: Dictionary = economy.apply_floor_transition(0, 0, "tx_floor_1_decay")
	suite.assert_true(bool(settled.get("ok", false)), "floor transition applies overflow decay")
	suite.assert_equal(economy.balance(), 850, "half of floor-one overflow survives")
	suite.assert_equal(
		economy.ledger(),
		[{"transaction_id": "tx_floor_1_decay", "operation": "gold_decay", "amount": -150, "revision": 1}],
		"overflow decay is sealed in economy ledger"
	)
	var after_decay: Dictionary = economy.snapshot()
	suite.assert_true(
		not bool(economy.apply_floor_transition(0, 1, "tx_floor_1_decay_again").get("ok", false)),
		"same floor cannot decay overflow twice"
	)
	suite.assert_equal(economy.snapshot(), after_decay, "duplicate floor decay is atomic")
	var restored = _configured(profile, 0)
	suite.assert_true(restored.restore_snapshot(after_decay), "decayed economy snapshot restores")
	suite.assert_equal(restored.snapshot(), after_decay, "decay restore preserves floor settlement")

	var forged_decay := after_decay.duplicate(true)
	forged_decay["ledger"][0]["amount"] = -149
	forged_decay["balance"] = 851
	var forged_target = _configured(profile, 0)
	suite.assert_true(
		not forged_target.restore_snapshot(forged_decay),
		"snapshot rejects decay amount that does not match profile formula"
	)

	var rolled_decay: Dictionary = economy.rollback_transaction(settled.get("receipt", {}))
	suite.assert_true(bool(rolled_decay.get("ok", false)), "decay receipt compensates")
	suite.assert_equal(economy.balance(), 1000, "decay compensation restores overflow")
	suite.assert_equal(economy.ledger(), [], "decay compensation restores ledger")
	suite.assert_true(
		bool(economy.apply_floor_transition(0, 0, "tx_floor_1_decay_retry").get("ok", false)),
		"compensated floor decay can be retried"
	)

	var under_cap = _configured(profile, 500)
	var no_decay: Dictionary = under_cap.apply_floor_transition(0, 0, "tx_floor_1_noop")
	suite.assert_true(bool(no_decay.get("ok", false)), "under-cap transition succeeds as settlement")
	suite.assert_equal(no_decay.get("context", {}).get("decayed_gold"), 0, "under-cap transition reports no decay")
	suite.assert_equal(under_cap.balance(), 500, "under-cap settlement preserves balance")
	suite.assert_equal(
		under_cap.ledger(),
		[{"transaction_id": "tx_floor_1_noop", "operation": "gold_decay", "amount": 0, "revision": 1}],
		"under-cap settlement records an exactly-once replay fact"
	)
	var under_cap_after: Dictionary = under_cap.snapshot()
	var restored_under_cap = _configured(profile, 0)
	suite.assert_true(
		restored_under_cap.restore_snapshot(under_cap_after),
		"under-cap settlement snapshot restores"
	)
	suite.assert_equal(
		restored_under_cap.snapshot(), under_cap_after,
		"under-cap restore preserves exactly-once settlement"
	)
	suite.assert_true(
		not bool(under_cap.apply_floor_transition(0, 1, "tx_floor_1_noop_again").get("ok", false)),
		"under-cap floor cannot settle twice"
	)
	suite.assert_equal(under_cap.snapshot(), under_cap_after, "duplicate under-cap settlement is atomic")


func _test_snapshot_restore_and_validation(suite, profile: Dictionary) -> void:
	var source = _configured(profile, 200)
	var prepared: Dictionary = source.prepare_transaction(
		"tx_restore_income", 45, 0, {"operation": "gold_delta"}
	)
	source.commit_transaction(prepared.get("ticket", {}))
	var canonical: Dictionary = source.snapshot()
	var exposed: Dictionary = source.snapshot()
	exposed["ledger"][0]["amount"] = 999
	suite.assert_equal(source.snapshot(), canonical, "snapshot is deeply isolated")

	var restored = _configured(profile, 0)
	suite.assert_true(restored.can_restore_snapshot(canonical), "canonical snapshot validates")
	suite.assert_true(restored.restore_snapshot(canonical), "canonical snapshot restores")
	suite.assert_equal(restored.snapshot(), canonical, "restore reproduces exact committed state")

	var json_value: Variant = JSON.parse_string(JSON.stringify(canonical))
	suite.assert_true(json_value is Dictionary, "snapshot crosses JSON boundary")
	if json_value is Dictionary:
		var json_restored = _configured(profile, 0)
		suite.assert_true(json_restored.restore_snapshot(json_value), "JSON-normalized snapshot restores")
		suite.assert_equal(json_restored.snapshot(), canonical, "JSON restore canonicalizes integers")

	var mutation_cases: Array[Dictionary] = []
	var extra := canonical.duplicate(true)
	extra["forged"] = true
	mutation_cases.append({"label": "extra field", "value": extra})
	var negative := canonical.duplicate(true)
	negative["balance"] = -1
	mutation_cases.append({"label": "negative balance", "value": negative})
	var revision_drift := canonical.duplicate(true)
	revision_drift["revision"] = 4
	mutation_cases.append({"label": "revision drift", "value": revision_drift})
	var balance_drift := canonical.duplicate(true)
	balance_drift["balance"] = 246
	mutation_cases.append({"label": "balance drift", "value": balance_drift})
	var duplicate := canonical.duplicate(true)
	duplicate["ledger"].append((duplicate["ledger"][0] as Dictionary).duplicate(true))
	duplicate["ledger"][1]["revision"] = 2
	duplicate["revision"] = 2
	duplicate["balance"] = 290
	mutation_cases.append({"label": "duplicate transaction", "value": duplicate})
	var unsupported := canonical.duplicate(true)
	unsupported["ledger"][0]["operation"] = "mint_everything"
	mutation_cases.append({"label": "unsupported operation", "value": unsupported})
	var positive_purchase := canonical.duplicate(true)
	positive_purchase["ledger"][0]["operation"] = "gold_purchase"
	mutation_cases.append({"label": "positive purchase", "value": positive_purchase})
	var wrong_profile := canonical.duplicate(true)
	wrong_profile["profile_id"] = "other_economy"
	mutation_cases.append({"label": "profile mismatch", "value": wrong_profile})
	var invalid_floor := canonical.duplicate(true)
	invalid_floor["settled_floor_indices"] = [5]
	mutation_cases.append({"label": "invalid floor index", "value": invalid_floor})

	for case: Dictionary in mutation_cases:
		var target = _configured(profile, 10)
		var before: Dictionary = target.snapshot()
		suite.assert_true(
			not target.can_restore_snapshot(case["value"]),
			"%s snapshot is rejected" % case["label"]
		)
		suite.assert_true(
			not target.restore_snapshot(case["value"]),
			"%s snapshot cannot restore" % case["label"]
		)
		suite.assert_equal(target.snapshot(), before, "%s restore failure is atomic" % case["label"])

	var pending_target = _configured(profile, 10)
	var pending: Dictionary = pending_target.prepare_transaction(
		"tx_restore_block", 5, 0, {"operation": "gold_delta"}
	)
	suite.assert_true(bool(pending.get("ok", false)), "restore block fixture prepares")
	suite.assert_true(
		not pending_target.restore_snapshot(canonical),
		"restore cannot discard a pending transaction"
	)
	suite.assert_equal(pending_target.balance(), 10, "rejected pending restore preserves balance")


func _configured(profile: Dictionary, initial_gold: int):
	var economy = RunEconomyStateScript.new()
	economy.configure(profile, initial_gold)
	return economy


func _load_profile() -> Dictionary:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array or (parsed as Array).is_empty():
		return {}
	var first: Variant = (parsed as Array)[0]
	return (first as Dictionary).duplicate(true) if first is Dictionary else {}
