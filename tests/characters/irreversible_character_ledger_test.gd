extends Node

const LedgerScript := preload("res://scripts/player/characters/irreversible_character_ledger.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_run_configuration_is_authoritative()
	_test_actual_loss_is_monotonic_and_claims_are_exactly_once()
	_test_invalid_claims_fail_without_mutation()
	_test_snapshot_is_isolated_and_rooted()
	_test_new_run_invalidates_old_claims_and_snapshots()
	_test_replay_restore_requires_a_fully_validated_snapshot()
	_test_transaction_restore_accepts_only_an_exact_frozen_snapshot()
	_test_transaction_discard_consumes_without_restoring()
	_suite.finish(get_tree())


func _test_run_configuration_is_authoritative() -> void:
	var ledger = LedgerScript.new()
	_suite.assert_true(not ledger.configure_run(&""), "empty run identity is rejected")
	_suite.assert_true(not ledger.configure_run(&"bad:run"), "run identity cannot forge claim-key separators")
	_suite.assert_true(ledger.configure_run(&"run-a"), "first valid run identity configures the ledger")
	_suite.assert_true(ledger.configure_run(&"run-a"), "same run configuration is idempotent")
	_suite.assert_true(not ledger.configure_run(&"run-b"), "a configured ledger rejects a different run identity")
	_suite.assert_equal(
		ledger.hp_loss_state(),
		{"irreversible_hp_loss_total": 0.0, "revision": 0},
		"configuration starts an empty monotonic state"
	)


func _test_actual_loss_is_monotonic_and_claims_are_exactly_once() -> void:
	var ledger = _configured_ledger(&"run-a")
	var first: Dictionary = ledger.record_hp_loss(7.5, &"curse:rewind", 11, 3, &"run-a")
	_suite.assert_true(bool(first.get("ok", false)), "first actual-loss claim is accepted")
	_suite.assert_equal(first.get("claim_key"), "run-a:curse:rewind:3:11", "claim key preserves the stable namespaced reason")
	_suite.assert_equal(
		ledger.hp_loss_state(),
		{"irreversible_hp_loss_total": 7.5, "revision": 1},
		"accepted claim increments actual-loss total and revision once"
	)

	# The caller reports the actual three HP removed by an overkill request, not the request size.
	var terminal: Dictionary = ledger.record_hp_loss(3.0, &"terminal_cost", 12, 3, &"run-a")
	_suite.assert_true(bool(terminal.get("ok", false)), "terminal actual-loss claim remains recordable")
	_suite.assert_equal(
		ledger.hp_loss_state(),
		{"irreversible_hp_loss_total": 10.5, "revision": 2},
		"ledger accumulates actual loss rather than an external requested amount"
	)

	var before_duplicate: Dictionary = ledger.snapshot()
	var duplicate: Dictionary = ledger.record_hp_loss(99.0, &"curse:rewind", 11, 3, &"run-a")
	_suite.assert_true(not bool(duplicate.get("ok", true)), "duplicate stable claim is rejected")
	_suite.assert_equal(duplicate.get("code"), &"DUPLICATE_CLAIM", "duplicate has a stable refusal code")
	_suite.assert_equal(ledger.snapshot(), before_duplicate, "duplicate claim has no ledger side effect")


func _test_invalid_claims_fail_without_mutation() -> void:
	var ledger = _configured_ledger(&"run-a")
	var before: Dictionary = ledger.snapshot()
	var invalid_results: Array[Dictionary] = [
		ledger.record_hp_loss(0.0, &"self_cost", 1, 1, &"run-a"),
		ledger.record_hp_loss(-1.0, &"self_cost", 1, 1, &"run-a"),
		ledger.record_hp_loss(INF, &"self_cost", 1, 1, &"run-a"),
		ledger.record_hp_loss(NAN, &"self_cost", 1, 1, &"run-a"),
		ledger.record_hp_loss(1.0, &"", 1, 1, &"run-a"),
		ledger.record_hp_loss(1.0, &"   ", 1, 1, &"run-a"),
		ledger.record_hp_loss(1.0, &"self_cost", 0, 1, &"run-a"),
		ledger.record_hp_loss(1.0, &"self_cost", -1, 1, &"run-a"),
		ledger.record_hp_loss(1.0, &"self_cost", 1, 0, &"run-a"),
		ledger.record_hp_loss(1.0, &"self_cost", 1, -1, &"run-a"),
		ledger.record_hp_loss(1.0, &"self_cost", 1, 1, &"run-stale"),
	]
	for index: int in range(invalid_results.size()):
		_suite.assert_true(
			not bool(invalid_results[index].get("ok", true)),
			"invalid claim %d fails closed" % index
		)
	_suite.assert_equal(ledger.snapshot(), before, "invalid claims do not mutate total, revision, claims, or root")


func _test_snapshot_is_isolated_and_rooted() -> void:
	var ledger = _configured_ledger(&"run-a")
	ledger.record_hp_loss(2.25, &"corruption_tick", 21, 4, &"run-a")
	var snapshot: Dictionary = ledger.snapshot()
	_suite.assert_equal(str(snapshot.get("run_id")), "run-a", "snapshot carries authoritative run identity")
	_suite.assert_equal(snapshot.get("irreversible_hp_loss_total"), 2.25, "snapshot carries exact actual-loss total")
	_suite.assert_equal(snapshot.get("revision"), 1, "snapshot carries monotonic revision")
	_suite.assert_equal(str(snapshot.get("claim_root")).length(), 64, "snapshot carries a SHA-256 claim root")
	var claims := snapshot.get("claims", {}) as Dictionary
	_suite.assert_true(claims.has("run-a:corruption_tick:4:21"), "snapshot claim map is keyed by stable claim identity")
	(snapshot["claims"] as Dictionary).clear()
	snapshot["irreversible_hp_loss_total"] = 0.0
	snapshot["claim_root"] = "0".repeat(64)
	_suite.assert_equal(
		ledger.hp_loss_state(),
		{"irreversible_hp_loss_total": 2.25, "revision": 1},
		"mutating a returned snapshot cannot refund live irreversible loss"
	)
	_suite.assert_true(not (ledger.snapshot().get("claims", {}) as Dictionary).is_empty(), "snapshot claim map is deep-isolated")


func _test_new_run_invalidates_old_claims_and_snapshots() -> void:
	var ledger = _configured_ledger(&"run-a")
	_suite.assert_true(bool(ledger.record_hp_loss(4.0, &"self_cost", 8, 2, &"run-a").get("ok", false)), "old run claim is accepted")
	var old_run_snapshot: Dictionary = ledger.snapshot()
	ledger.reset_for_run(&"run-a")
	_suite.assert_equal(ledger.snapshot(), old_run_snapshot, "same-run reset cannot refund irreversible loss")
	ledger.reset_for_run(&"run-b")
	_suite.assert_equal(
		ledger.hp_loss_state(),
		{"irreversible_hp_loss_total": 0.0, "revision": 0},
		"new run starts with an empty irreversible state"
	)
	_suite.assert_true(
		not bool(ledger.record_hp_loss(1.0, &"self_cost", 8, 2, &"run-a").get("ok", true)),
		"old-run callback is invalid after reset"
	)
	_suite.assert_true(not ledger.restore_replay_snapshot(old_run_snapshot), "old-run Replay snapshot cannot cross the reset boundary")
	var new_claim: Dictionary = ledger.record_hp_loss(1.0, &"self_cost", 8, 2, &"run-b")
	_suite.assert_true(bool(new_claim.get("ok", false)), "same numeric identity is reusable only under the new run")
	_suite.assert_equal(new_claim.get("claim_key"), "run-b:self_cost:2:8", "new run owns a distinct stable claim key")


func _test_replay_restore_requires_a_fully_validated_snapshot() -> void:
	var source = _configured_ledger(&"run-a")
	source.record_hp_loss(1.25, &"self_cost", 31, 6, &"run-a")
	source.record_hp_loss(2.75, &"terminal_cost", 32, 6, &"run-a")
	var replay_snapshot: Dictionary = source.snapshot()
	var restored = LedgerScript.new()
	_suite.assert_true(restored.restore_replay_snapshot(replay_snapshot), "fully validated Replay snapshot restores into an empty ledger")
	_suite.assert_equal(restored.snapshot(), replay_snapshot, "Replay restore installs exact validated state")

	var before_rejections: Dictionary = restored.snapshot()
	var forged_root := replay_snapshot.duplicate(true)
	forged_root["claim_root"] = "0".repeat(64)
	var forged_total := replay_snapshot.duplicate(true)
	forged_total["irreversible_hp_loss_total"] = 400.0
	var forged_revision := replay_snapshot.duplicate(true)
	forged_revision["revision"] = 9
	var forged_key := replay_snapshot.duplicate(true)
	var forged_claims := forged_key["claims"] as Dictionary
	var first_key: Variant = forged_claims.keys()[0]
	forged_claims["run-a:self_cost:6:999"] = forged_claims[first_key]
	forged_claims.erase(first_key)
	var missing_field := replay_snapshot.duplicate(true)
	missing_field.erase("claims")
	var unknown_field := replay_snapshot.duplicate(true)
	unknown_field["unexpected"] = true
	var invalid_snapshots: Array[Dictionary] = [
		forged_root,
		forged_total,
		forged_revision,
		forged_key,
		missing_field,
		unknown_field,
	]
	for index: int in range(invalid_snapshots.size()):
		_suite.assert_true(
			not restored.restore_replay_snapshot(invalid_snapshots[index]),
			"invalid Replay snapshot %d is rejected" % index
		)
	_suite.assert_equal(restored.snapshot(), before_rejections, "failed Replay restores are atomic")


func _test_transaction_restore_accepts_only_an_exact_frozen_snapshot() -> void:
	var ledger = _configured_ledger(&"run-a")
	ledger.record_hp_loss(2.0, &"self_cost", 41, 7, &"run-a")
	var ordinary_snapshot: Dictionary = ledger.snapshot()
	ledger.record_hp_loss(1.0, &"terminal_cost", 42, 7, &"run-a")
	_suite.assert_true(
		not ledger.restore_transaction_snapshot(ordinary_snapshot),
		"ordinary observation snapshot has no transaction rollback authority"
	)
	var frozen_before: Dictionary = ledger.freeze_transaction_snapshot()
	ledger.record_hp_loss(5.0, &"corruption_tick", 43, 7, &"run-a")
	var live_after: Dictionary = ledger.snapshot()

	var external = _configured_ledger(&"run-a")
	external.record_hp_loss(9.0, &"external_cost", 50, 8, &"run-a")
	var valid_but_not_frozen_here: Dictionary = external.snapshot()
	_suite.assert_true(
		not ledger.restore_transaction_snapshot(valid_but_not_frozen_here),
		"transaction restore rejects a valid snapshot not frozen by this ledger"
	)
	var forged_frozen := frozen_before.duplicate(true)
	forged_frozen["irreversible_hp_loss_total"] = 0.0
	_suite.assert_true(not ledger.restore_transaction_snapshot(forged_frozen), "transaction restore rejects a forged frozen snapshot")
	_suite.assert_equal(ledger.snapshot(), live_after, "failed transaction restores leave live state exact")
	_suite.assert_true(ledger.restore_transaction_snapshot(frozen_before), "exact frozen pre-transaction snapshot rolls back")
	_suite.assert_equal(ledger.snapshot(), frozen_before, "transaction rollback restores total, revision, claims, and root exactly")
	_suite.assert_true(not ledger.restore_transaction_snapshot(frozen_before), "transaction rollback consumes its frozen authority once")


func _test_transaction_discard_consumes_without_restoring() -> void:
	var ledger = _configured_ledger(&"run-a")
	ledger.record_hp_loss(2.0, &"self_cost", 61, 9, &"run-a")
	var frozen_before: Dictionary = ledger.freeze_transaction_snapshot()
	ledger.record_hp_loss(3.0, &"corruption_tick", 62, 9, &"run-a")
	var live_after: Dictionary = ledger.snapshot()
	_suite.assert_true(
		ledger.discard_transaction_snapshot(frozen_before),
		"successful transaction consumes its rollback capability"
	)
	_suite.assert_equal(ledger.snapshot(), live_after, "discard keeps the committed live ledger state")
	_suite.assert_true(
		not ledger.restore_transaction_snapshot(frozen_before),
		"discarded transaction snapshot cannot refund committed loss"
	)
	_suite.assert_true(
		not ledger.discard_transaction_snapshot(frozen_before),
		"discard is single-use"
	)


func _configured_ledger(run_id: StringName):
	var ledger = LedgerScript.new()
	_suite.assert_true(ledger.configure_run(run_id), "ledger fixture configures %s" % str(run_id))
	return ledger
