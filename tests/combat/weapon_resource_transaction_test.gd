extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const TimeManagerScript := preload("res://scripts/time_system/time_manager.gd")
const WeaponResourceTransactionScript := preload(
	"res://scripts/combat/weapons/weapon_resource_transaction.gd"
)


class FakeProvider extends RefCounted:
	var resource_id: StringName = &"time_energy"
	var current: float = 100.0
	var maximum: float = 100.0
	var revision: int = 1
	var spend_calls: int = 0
	var fail_commit: bool = false
	var malformed_success_mode: StringName = &""
	var fail_restore: bool = false
	var fail_restore_on_calls: Array[int] = []
	var mutate_before_failed_restore: bool = false
	var reject_restore_preflight: bool = false
	var restore_calls: int = 0


	func _init(id: StringName = &"time_energy") -> void:
		resource_id = id


	func resource_state(resource_id: StringName) -> Dictionary:
		if resource_id != self.resource_id:
			return {"ok": false, "code": &"RESOURCE_NOT_FOUND", "context": {}}
		return {
			"ok": true,
			"code": &"OK",
			"resource_id": str(resource_id),
			"current": current,
			"minimum": 0.0,
			"maximum": maximum,
			"revision": revision,
			"context": {},
		}


	func try_spend_resource(
		resource_id: StringName,
		amount: float,
		expected_revision: int,
		_reason: StringName
	) -> Dictionary:
		spend_calls += 1
		if fail_commit:
			return {"ok": false, "code": &"PROVIDER_FAILURE", "context": {}}
		if resource_id != self.resource_id:
			return {"ok": false, "code": &"RESOURCE_NOT_FOUND", "context": {}}
		if expected_revision != revision:
			return {
				"ok": false,
				"code": &"RESOURCE_REVISION_MISMATCH",
				"context": {"expected_revision": expected_revision, "actual_revision": revision},
			}
		if amount < 0.0 or not is_finite(amount) or current < amount:
			return {"ok": false, "code": &"INSUFFICIENT_RESOURCE", "context": {}}
		var before := current
		if malformed_success_mode == &"failure_after_debit":
			current -= amount
			revision += 1
			return {
				"ok": false,
				"code": &"PROVIDER_FAILURE",
				"resource_id": str(resource_id),
				"context": {},
			}
		if malformed_success_mode == &"free":
			return {
				"ok": true,
				"code": &"OK",
				"resource_id": str(resource_id),
				"before": before,
				"after": before - amount,
				"revision": revision + 1,
				"context": {},
			}
		if malformed_success_mode == &"wrong_amount":
			current -= amount * 0.5
			revision += 1
			return {
				"ok": true,
				"code": &"OK",
				"resource_id": str(resource_id),
				"before": before,
				"after": current,
				"revision": revision,
				"context": {},
			}
		current -= amount
		revision += 1
		if malformed_success_mode == &"wrong_revision":
			return {
				"ok": true,
				"code": &"OK",
				"resource_id": str(resource_id),
				"before": before,
				"after": current,
				"revision": revision + 1,
				"context": {},
			}
		if malformed_success_mode == &"malformed_after_debit":
			return {
				"ok": true,
				"code": &"OK",
				"resource_id": str(resource_id),
				"before": before,
				"context": {},
			}
		return {
			"ok": true,
			"code": &"OK",
			"resource_id": str(resource_id),
			"before": before,
			"after": current,
			"revision": revision,
			"context": {},
		}


	func bump_revision() -> void:
		revision += 1


	func can_restore_resource_state(requested_id: StringName, state: Dictionary) -> bool:
		return not reject_restore_preflight and _restore_state_is_valid(requested_id, state)


	func restore_resource_state(requested_id: StringName, state: Dictionary) -> bool:
		restore_calls += 1
		if not _restore_state_is_valid(requested_id, state):
			return false
		var should_fail := fail_restore or fail_restore_on_calls.has(restore_calls)
		if should_fail and not mutate_before_failed_restore:
			return false
		current = float(state["current"])
		revision = int(state["revision"])
		return not should_fail


	func _restore_state_is_valid(requested_id: StringName, state: Dictionary) -> bool:
		return (
			requested_id == resource_id
			and str(state.get("resource_id", "")) == str(resource_id)
			and typeof(state.get("current")) in [TYPE_INT, TYPE_FLOAT]
			and typeof(state.get("minimum")) in [TYPE_INT, TYPE_FLOAT]
			and typeof(state.get("maximum")) in [TYPE_INT, TYPE_FLOAT]
			and typeof(state.get("revision")) == TYPE_INT
			and float(state.get("minimum", -1.0)) == 0.0
			and float(state.get("maximum", -1.0)) == maximum
			and float(state.get("current", -1.0)) >= 0.0
			and float(state.get("current", -1.0)) <= maximum
			and int(state.get("revision", 0)) > 0
		)


class ReplayStopProbe extends Node:
	var apply_calls: int = 0
	var clear_calls: int = 0


	func _ready() -> void:
		add_to_group("time_stoppable")


	func apply_time_stop_source(_source_id: StringName, _duration: float) -> void:
		apply_calls += 1


	func clear_time_stop_source(_source_id: StringName) -> void:
		clear_calls += 1


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_prepare_is_pure_and_isolates_the_plan()
	_test_prepare_rejects_insufficient_resources_without_side_effects()
	_test_tampered_ticket_cannot_remove_external_cost()
	_test_commit_is_atomic_and_token_idempotent()
	_test_provider_revision_rejection_restores_local_cooldown()
	_test_free_success_is_rejected_without_ledger()
	_test_wrong_amount_success_is_compensated()
	_test_wrong_revision_success_is_compensated()
	_test_malformed_success_after_debit_is_compensated()
	_test_failure_after_debit_is_compensated()
	_test_malformed_success_compensation_failure_enters_fail_closed()
	_test_cooldown_uses_half_open_frame_boundaries()
	_test_rewind_safe_reset_preserves_committed_state()
	_test_full_reset_clears_only_weapon_transaction_state()
	_test_strict_snapshot_restore_restores_provider_and_ledgers()
	_test_strict_snapshot_restore_rejects_inconsistent_or_unrestorable_state()
	_test_restore_prevalidates_all_accounts_before_mutation()
	_test_external_restore_failure_rolls_back_all_accounts()
	_test_external_restore_rollback_failure_enters_fail_closed()
	await _test_time_manager_provider_contract()
	await _test_time_manager_replay_restore_transaction_is_observable_atomic()
	_suite.finish(get_tree())


func _test_prepare_is_pure_and_isolates_the_plan() -> void:
	var provider := FakeProvider.new()
	var transaction := _transaction(provider)
	var plan := _plan("arrow_rain", 300, {"time_energy": 20.0})
	var transaction_before: Dictionary = transaction.snapshot()
	var provider_before := {
		"current": provider.current,
		"revision": provider.revision,
		"spend_calls": provider.spend_calls,
	}

	var prepared: Dictionary = transaction.prepare(plan, 7)
	_suite.assert_true(bool(prepared.get("ok", false)), "valid resource transaction prepares")
	_suite.assert_equal(transaction.snapshot(), transaction_before, "prepare leaves transaction state unchanged")
	_suite.assert_equal(
		{"current": provider.current, "revision": provider.revision, "spend_calls": provider.spend_calls},
		provider_before,
		"prepare leaves the provider unchanged"
	)
	plan["cooldown_frames"] = 1
	plan["resource_costs"]["time_energy"] = 99.0
	var committed: Dictionary = transaction.commit(prepared.get("ticket", {}))
	_suite.assert_true(bool(committed.get("ok", false)), "prepared ticket commits after caller plan mutation")
	_suite.assert_close(provider.current, 80.0, "ticket freezes the prepared resource cost")
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 300, "ticket freezes the prepared cooldown")


func _test_prepare_rejects_insufficient_resources_without_side_effects() -> void:
	var provider := FakeProvider.new()
	provider.current = 19.0
	var transaction := _transaction(provider)
	var before: Dictionary = transaction.snapshot()
	var rejected: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		9
	)
	_suite.assert_true(not bool(rejected.get("ok", false)), "insufficient resource rejects during prepare")
	_suite.assert_equal(rejected.get("code"), &"INSUFFICIENT_RESOURCE", "insufficient prepare failure is typed")
	_suite.assert_equal(transaction.snapshot(), before, "insufficient prepare leaves transaction state unchanged")
	_suite.assert_close(provider.current, 19.0, "insufficient prepare leaves provider balance unchanged")
	_suite.assert_equal(provider.spend_calls, 0, "insufficient prepare never enters provider commit")


func _test_tampered_ticket_cannot_remove_external_cost() -> void:
	var provider := FakeProvider.new()
	var transaction := _transaction(provider)
	var prepared: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		10
	)
	var tampered: Dictionary = prepared.get("ticket", {}).duplicate(true)
	tampered["external_debits"] = []
	var rejected: Dictionary = transaction.commit(tampered)
	_suite.assert_true(not bool(rejected.get("ok", false)), "ticket cannot delete a prepared external debit")
	_suite.assert_equal(rejected.get("code"), &"INVALID_TICKET", "tampered ticket fails closed")
	_suite.assert_close(provider.current, 100.0, "tampered ticket spends no resource")
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 0, "tampered ticket starts no cooldown")


func _test_commit_is_atomic_and_token_idempotent() -> void:
	var provider := FakeProvider.new()
	var transaction := _transaction(provider)
	var prepared: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		11
	)
	var first: Dictionary = transaction.commit(prepared.get("ticket", {}))
	_suite.assert_true(bool(first.get("ok", false)), "first commit succeeds")
	_suite.assert_close(provider.current, 80.0, "first commit spends the external resource once")
	_suite.assert_equal(provider.spend_calls, 1, "first commit calls the provider once")
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 300, "first commit starts the action cooldown")

	var duplicate: Dictionary = transaction.commit(prepared.get("ticket", {}))
	_suite.assert_true(bool(duplicate.get("ok", false)), "same-token duplicate commit is idempotent")
	_suite.assert_equal(duplicate.get("code"), &"ALREADY_COMMITTED", "idempotent duplicate is explicit")
	_suite.assert_close(provider.current, 80.0, "duplicate commit spends no additional resource")
	_suite.assert_equal(provider.spend_calls, 1, "duplicate commit does not call the provider again")
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 300, "duplicate commit does not restart cooldown")

	var reused: Dictionary = transaction.prepare(
		_plan("horizon_piercer", 900, {"time_energy": 55.0}),
		11
	)
	_suite.assert_true(not bool(reused.get("ok", false)), "same token cannot identify a different transaction")
	_suite.assert_equal(reused.get("code"), &"TOKEN_REUSED", "token reuse mismatch is typed")


func _test_provider_revision_rejection_restores_local_cooldown() -> void:
	var provider := FakeProvider.new()
	var transaction := _transaction(provider)
	var prepared: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		13
	)
	provider.bump_revision()
	var rejected: Dictionary = transaction.commit(prepared.get("ticket", {}))
	_suite.assert_true(not bool(rejected.get("ok", false)), "stale provider revision rejects commit")
	_suite.assert_equal(rejected.get("code"), &"RESOURCE_REVISION_MISMATCH", "provider revision failure is preserved")
	_suite.assert_close(provider.current, 100.0, "revision rejection spends no resource")
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 0, "revision rejection rolls local cooldown back")

	var retry: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		13
	)
	_suite.assert_true(bool(retry.get("ok", false)), "failed commit does not consume the action token")
	_suite.assert_true(bool(transaction.commit(retry.get("ticket", {})).get("ok", false)), "fresh revision can commit")


func _test_free_success_is_rejected_without_ledger() -> void:
	var provider := FakeProvider.new()
	provider.malformed_success_mode = &"free"
	var transaction := _transaction(provider)
	var prepared: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		14
	)

	var rejected: Dictionary = transaction.commit(prepared.get("ticket", {}))
	_suite.assert_true(not bool(rejected.get("ok", false)), "unchanged provider state rejects a fake success")
	_suite.assert_equal(rejected.get("code"), &"RESOURCE_COMMIT_FAILED", "fake success uses the commit failure code")
	_suite.assert_close(provider.current, 100.0, "fake success cannot grant a free action")
	_suite.assert_equal(provider.revision, 1, "fake success preserves the provider revision")
	_suite.assert_equal(provider.restore_calls, 0, "unchanged provider state needs no compensation")
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 0, "fake success restores the local cooldown")
	_suite.assert_true(
		(transaction.snapshot().get("committed_tokens", {}) as Dictionary).is_empty(),
		"fake success creates no committed ledger"
	)


func _test_wrong_amount_success_is_compensated() -> void:
	var provider := FakeProvider.new()
	provider.malformed_success_mode = &"wrong_amount"
	var transaction := _transaction(provider)
	var prepared: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		15
	)

	var rejected: Dictionary = transaction.commit(prepared.get("ticket", {}))
	_suite.assert_true(not bool(rejected.get("ok", false)), "wrong debit amount rejects provider success")
	_suite.assert_equal(rejected.get("code"), &"RESOURCE_COMMIT_FAILED", "wrong amount uses the commit failure code")
	_suite.assert_close(provider.current, 100.0, "wrong debit amount is compensated")
	_suite.assert_equal(provider.revision, 1, "wrong debit compensation restores the revision")
	_suite.assert_equal(provider.restore_calls, 1, "wrong debit amount invokes one compensation")
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 0, "wrong debit restores the local cooldown")
	_suite.assert_true(
		(transaction.snapshot().get("committed_tokens", {}) as Dictionary).is_empty(),
		"wrong debit creates no committed ledger"
	)


func _test_wrong_revision_success_is_compensated() -> void:
	var provider := FakeProvider.new()
	provider.malformed_success_mode = &"wrong_revision"
	var transaction := _transaction(provider)
	var prepared: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		16
	)

	var rejected: Dictionary = transaction.commit(prepared.get("ticket", {}))
	_suite.assert_true(not bool(rejected.get("ok", false)), "wrong revision rejects provider success")
	_suite.assert_equal(rejected.get("code"), &"RESOURCE_COMMIT_FAILED", "wrong revision uses the commit failure code")
	_suite.assert_close(provider.current, 100.0, "wrong revision debit is compensated")
	_suite.assert_equal(provider.revision, 1, "wrong revision compensation restores the revision")
	_suite.assert_equal(provider.restore_calls, 1, "wrong revision invokes one compensation")
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 0, "wrong revision restores the local cooldown")
	_suite.assert_true(
		(transaction.snapshot().get("committed_tokens", {}) as Dictionary).is_empty(),
		"wrong revision creates no committed ledger"
	)


func _test_malformed_success_after_debit_is_compensated() -> void:
	var provider := FakeProvider.new()
	provider.malformed_success_mode = &"malformed_after_debit"
	var transaction := _transaction(provider)
	var prepared: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		17
	)

	var rejected: Dictionary = transaction.commit(prepared.get("ticket", {}))
	_suite.assert_true(not bool(rejected.get("ok", false)), "malformed success rejects after a debit")
	_suite.assert_equal(rejected.get("code"), &"RESOURCE_COMMIT_FAILED", "malformed success uses the commit failure code")
	_suite.assert_close(provider.current, 100.0, "malformed success debit is compensated")
	_suite.assert_equal(provider.revision, 1, "malformed success compensation restores the revision")
	_suite.assert_equal(provider.restore_calls, 1, "malformed success invokes one compensation")
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 0, "malformed success restores the local cooldown")
	_suite.assert_true(
		(transaction.snapshot().get("committed_tokens", {}) as Dictionary).is_empty(),
		"malformed success creates no committed ledger"
	)


func _test_failure_after_debit_is_compensated() -> void:
	var provider := FakeProvider.new()
	provider.malformed_success_mode = &"failure_after_debit"
	var transaction := _transaction(provider)
	var prepared: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		171
	)

	var rejected: Dictionary = transaction.commit(prepared.get("ticket", {}))
	_suite.assert_true(not bool(rejected.get("ok", false)), "provider failure rejects after a debit")
	_suite.assert_equal(rejected.get("code"), &"PROVIDER_FAILURE", "provider failure preserves its typed code")
	_suite.assert_close(provider.current, 100.0, "provider failure debit is compensated")
	_suite.assert_equal(provider.revision, 1, "provider failure compensation restores the revision")
	_suite.assert_equal(provider.restore_calls, 1, "provider failure after debit invokes one compensation")
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 0, "provider failure restores the local cooldown")
	_suite.assert_true(
		(transaction.snapshot().get("committed_tokens", {}) as Dictionary).is_empty(),
		"provider failure creates no committed ledger"
	)


func _test_malformed_success_compensation_failure_enters_fail_closed() -> void:
	var provider := FakeProvider.new()
	provider.malformed_success_mode = &"malformed_after_debit"
	provider.fail_restore_on_calls = [1]
	var transaction := _transaction(provider)
	var prepared: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		18
	)

	var rejected: Dictionary = transaction.commit(prepared.get("ticket", {}))
	_suite.assert_true(not bool(rejected.get("ok", false)), "failed compensation rejects malformed success")
	_suite.assert_equal(rejected.get("code"), &"RESOURCE_COMMIT_FAILED", "failed compensation preserves the commit failure code")
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 0, "failed compensation clears the local cooldown")
	_suite.assert_true(
		(transaction.snapshot().get("committed_tokens", {}) as Dictionary).is_empty(),
		"failed compensation creates no committed ledger"
	)
	_suite.assert_true(not bool(transaction.snapshot().get("configured", true)), "failed compensation poisons the transaction closed")
	var later: Dictionary = transaction.prepare(_plan("arrow_rain", 300, {"time_energy": 20.0}), 19)
	_suite.assert_equal(later.get("code"), &"NOT_CONFIGURED", "fail-closed transaction rejects later prepares")


func _test_cooldown_uses_half_open_frame_boundaries() -> void:
	var provider := FakeProvider.new()
	var transaction := _transaction(provider)
	var plan := _plan("scatter_shot", 120, {})
	var prepared: Dictionary = transaction.prepare(plan, 21)
	_suite.assert_true(bool(transaction.commit(prepared.get("ticket", {})).get("ok", false)), "cooldown fixture commits")
	transaction.advance_frame(119)
	_suite.assert_equal(transaction.cooldown_remaining(&"scatter_shot"), 1, "cooldown remains closed through frame 119")
	var still_closed: Dictionary = transaction.prepare(plan, 22)
	_suite.assert_true(not bool(still_closed.get("ok", false)), "action remains unavailable before the half-open end")
	_suite.assert_equal(still_closed.get("code"), &"COOLDOWN_ACTIVE", "closed boundary reports cooldown")
	transaction.advance_frame()
	_suite.assert_equal(transaction.cooldown_remaining(&"scatter_shot"), 0, "frame 120 opens the cooldown boundary")
	_suite.assert_true(bool(transaction.prepare(plan, 22).get("ok", false)), "action prepares exactly at frame 120")


func _test_rewind_safe_reset_preserves_committed_state() -> void:
	var provider := FakeProvider.new()
	var transaction := _transaction(provider)
	var prepared: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		31
	)
	transaction.commit(prepared.get("ticket", {}))
	var before: Dictionary = transaction.snapshot()
	var provider_before := {"current": provider.current, "revision": provider.revision}

	transaction.rewind_safe_reset()
	_suite.assert_equal(transaction.snapshot(), before, "rewind-safe reset preserves cooldowns and committed-token ledger")
	_suite.assert_equal(
		{"current": provider.current, "revision": provider.revision},
		provider_before,
		"rewind-safe reset does not restore or spend provider resources"
	)


func _test_full_reset_clears_only_weapon_transaction_state() -> void:
	var provider := FakeProvider.new()
	var transaction := _transaction(provider)
	var plan := _plan("arrow_rain", 300, {"time_energy": 20.0})
	var prepared: Dictionary = transaction.prepare(plan, 41)
	transaction.commit(prepared.get("ticket", {}))
	var provider_before := {"current": provider.current, "revision": provider.revision}

	transaction.reset_runtime_state()
	_suite.assert_equal(transaction.cooldown_remaining(&"arrow_rain"), 0, "full reset clears weapon cooldown")
	_suite.assert_equal(
		{"current": provider.current, "revision": provider.revision},
		provider_before,
		"full reset does not reset the external provider"
	)
	_suite.assert_true(bool(transaction.prepare(plan, 41).get("ok", false)), "full reset clears committed-token idempotency state")


func _test_strict_snapshot_restore_restores_provider_and_ledgers() -> void:
	var provider := FakeProvider.new()
	var transaction := _transaction(provider)
	var plan := _plan("arrow_rain", 300, {"time_energy": 20.0})
	var prepared: Dictionary = transaction.prepare(plan, 51)
	_suite.assert_true(bool(transaction.commit(prepared.get("ticket", {})).get("ok", false)), "restore fixture commits")
	transaction.advance_frame(17)
	var authoritative: Dictionary = transaction.snapshot()

	provider.current = 7.0
	provider.revision = 99
	transaction.reset_runtime_state()
	_suite.assert_true(transaction.restore_snapshot(authoritative), "strict restore accepts a self-consistent authoritative snapshot")
	_suite.assert_equal(transaction.snapshot(), authoritative, "strict restore reinstalls cooldown and committed-token ledgers exactly")
	_suite.assert_close(provider.current, 80.0, "strict restore reinstalls the external resource balance")
	_suite.assert_equal(provider.revision, 2, "strict restore reinstalls the external resource revision")
	var duplicate: Dictionary = transaction.commit(prepared.get("ticket", {}))
	_suite.assert_equal(duplicate.get("code"), &"ALREADY_COMMITTED", "restored transaction ledger remains idempotent")
	_suite.assert_equal(provider.spend_calls, 1, "restored ledger prevents a duplicate provider debit")


func _test_strict_snapshot_restore_rejects_inconsistent_or_unrestorable_state() -> void:
	var provider := FakeProvider.new()
	var transaction := _transaction(provider)
	var prepared: Dictionary = transaction.prepare(
		_plan("arrow_rain", 300, {"time_energy": 20.0}),
		61
	)
	transaction.commit(prepared.get("ticket", {}))
	var authoritative: Dictionary = transaction.snapshot()
	var before: Dictionary = transaction.snapshot()
	var provider_before := {"current": provider.current, "revision": provider.revision}

	var inconsistent := authoritative.duplicate(true)
	inconsistent["committed_tokens"][61]["ticket"]["token"] = 62
	_suite.assert_true(not transaction.restore_snapshot(inconsistent), "restore rejects a ledger whose token key and ticket disagree")
	_suite.assert_equal(transaction.snapshot(), before, "inconsistent restore rejection is transaction-atomic")
	_suite.assert_equal(
		{"current": provider.current, "revision": provider.revision},
		provider_before,
		"inconsistent restore rejection leaves the provider unchanged"
	)

	provider.fail_restore = true
	var changed_provider_state := authoritative.duplicate(true)
	changed_provider_state["external_accounts"]["time_energy"]["current"] = 90.0
	changed_provider_state["external_accounts"]["time_energy"]["revision"] = 3
	_suite.assert_true(not transaction.restore_snapshot(changed_provider_state), "restore fails closed when the provider cannot restore its balance")
	_suite.assert_equal(transaction.snapshot(), before, "provider restore failure preserves transaction ledgers")
	_suite.assert_equal(
		{"current": provider.current, "revision": provider.revision},
		provider_before,
		"provider restore failure preserves the prior balance and revision"
	)


func _test_restore_prevalidates_all_accounts_before_mutation() -> void:
	var energy := FakeProvider.new(&"time_energy")
	var focus := FakeProvider.new(&"focus")
	var transaction := _multi_transaction(energy, focus)
	var invalid_target: Dictionary = transaction.snapshot()
	invalid_target["external_accounts"]["time_energy"]["current"] = 80.0
	invalid_target["external_accounts"]["time_energy"]["revision"] = 2
	invalid_target["external_accounts"]["focus"]["current"] = 40.0
	invalid_target["external_accounts"]["focus"]["maximum"] = 200.0
	invalid_target["external_accounts"]["focus"]["revision"] = 2

	_suite.assert_true(
		not transaction.restore_snapshot(invalid_target),
		"restore rejects a provider-specific bound mismatch during preflight"
	)
	_suite.assert_equal(energy.restore_calls, 0, "preflight rejects before the first provider is modified")
	_suite.assert_equal(focus.restore_calls, 0, "preflight does not call the invalid provider restore")
	_suite.assert_close(energy.current, 100.0, "preflight rejection preserves the first provider")
	_suite.assert_close(focus.current, 100.0, "preflight rejection preserves the second provider")


func _test_external_restore_failure_rolls_back_all_accounts() -> void:
	var energy := FakeProvider.new(&"time_energy")
	var focus := FakeProvider.new(&"focus")
	var transaction := _multi_transaction(energy, focus)
	var before: Dictionary = transaction.snapshot()
	var target := before.duplicate(true)
	for resource_id: String in ["time_energy", "focus"]:
		target["external_accounts"][resource_id]["current"] = 80.0
		target["external_accounts"][resource_id]["revision"] = 2
	focus.fail_restore_on_calls = [1]
	focus.mutate_before_failed_restore = true

	_suite.assert_true(not transaction.restore_snapshot(target), "one provider restore failure rejects the whole transaction")
	_suite.assert_equal(transaction.snapshot(), before, "provider failure rolls every external account and local ledger back")
	_suite.assert_close(energy.current, 100.0, "earlier provider mutation is compensated")
	_suite.assert_close(focus.current, 100.0, "failing provider mutation is compensated")
	_suite.assert_equal(energy.restore_calls, 2, "earlier provider receives target and compensation restores")
	_suite.assert_equal(focus.restore_calls, 2, "failing provider receives failure and compensation restores")


func _test_external_restore_rollback_failure_enters_fail_closed() -> void:
	var energy := FakeProvider.new(&"time_energy")
	var focus := FakeProvider.new(&"focus")
	var transaction := _multi_transaction(energy, focus)
	var target: Dictionary = transaction.snapshot()
	for resource_id: String in ["time_energy", "focus"]:
		target["external_accounts"][resource_id]["current"] = 80.0
		target["external_accounts"][resource_id]["revision"] = 2
	energy.fail_restore_on_calls = [2]
	focus.fail_restore_on_calls = [1]

	_suite.assert_true(not transaction.restore_snapshot(target), "failed compensation rejects the restore")
	_suite.assert_true(not bool(transaction.snapshot().get("configured", true)), "failed compensation poisons the transaction closed")
	var rejected: Dictionary = transaction.prepare(_plan("closed_after_restore_failure", 0, {}), 71)
	_suite.assert_equal(rejected.get("code"), &"NOT_CONFIGURED", "fail-closed transaction rejects later actions")


func _test_time_manager_provider_contract() -> void:
	var manager = TimeManagerScript.new()
	manager.energy_regen = 0.0
	add_child(manager)
	await get_tree().process_frame
	var signal_count := [0]
	manager.energy_changed.connect(func(_current: float, _maximum: float) -> void:
		signal_count[0] += 1
	)

	var state: Dictionary = manager.resource_state(&"time_energy")
	_suite.assert_true(bool(state.get("ok", false)), "TimeManager exposes the generic time-energy provider")
	var revision := int(state.get("revision", 0))
	var spent: Dictionary = manager.try_spend_resource(&"time_energy", 20.0, revision, &"test")
	_suite.assert_true(bool(spent.get("ok", false)), "TimeManager atomically spends a valid request")
	_suite.assert_close(manager.energy, 80.0, "TimeManager applies the requested debit")
	_suite.assert_equal(signal_count[0], 1, "successful provider debit emits one energy change")
	var spent_state: Dictionary = manager.resource_state(&"time_energy")

	var stale: Dictionary = manager.try_spend_resource(&"time_energy", 10.0, revision, &"stale")
	_suite.assert_true(not bool(stale.get("ok", false)), "TimeManager rejects a stale provider revision")
	_suite.assert_equal(stale.get("code"), &"RESOURCE_REVISION_MISMATCH", "stale provider failure is typed")
	_suite.assert_close(manager.energy, 80.0, "stale provider rejection leaves energy unchanged")
	_suite.assert_equal(signal_count[0], 1, "stale provider rejection emits no energy change")

	var live_revision := int(manager.resource_state(&"time_energy").get("revision", 0))
	var invalid: Dictionary = manager.try_spend_resource(&"time_energy", INF, live_revision, &"invalid")
	_suite.assert_true(not bool(invalid.get("ok", false)), "TimeManager rejects non-finite debit")
	_suite.assert_close(manager.energy, 80.0, "invalid provider request leaves energy unchanged")
	_suite.assert_equal(signal_count[0], 1, "invalid provider request emits no energy change")

	_suite.assert_true(
		manager.restore_resource_state(&"time_energy", spent_state),
		"TimeManager accepts a strict authoritative resource restore"
	)
	_suite.assert_close(manager.energy, 80.0, "TimeManager restore reinstalls the balance")
	_suite.assert_equal(
		manager.resource_state(&"time_energy").get("revision"),
		spent_state.get("revision"),
		"TimeManager restore reinstalls the revision"
	)

	var replay_snapshot: Dictionary = manager.weapon_replay_snapshot()
	manager.restore_energy(5.0)
	_suite.assert_close(manager.energy, 85.0, "TimeManager replay fixture creates an energy drift")
	var signals_before_replay_restore: int = int(signal_count[0])
	_suite.assert_true(
		manager.restore_weapon_replay_snapshot(replay_snapshot),
		"TimeManager replay restore reinstalls canonical time energy"
	)
	_suite.assert_equal(
		manager.weapon_replay_snapshot(),
		replay_snapshot,
		"TimeManager replay restore reinstalls current, maximum, and revision exactly"
	)
	_suite.assert_equal(
		signal_count[0],
		signals_before_replay_restore + 1,
		"TimeManager replay restore emits one energy change after commit"
	)
	_suite.assert_true(
		manager.restore_weapon_replay_snapshot(replay_snapshot),
		"TimeManager repeated replay restore is idempotent"
	)
	_suite.assert_equal(
		signal_count[0],
		signals_before_replay_restore + 1,
		"TimeManager idempotent replay restore emits no duplicate energy change"
	)

	var invalid_replay_snapshots: Array[Dictionary] = []
	var legacy_replay_snapshot := replay_snapshot.duplicate(true)
	legacy_replay_snapshot["schema_version"] = 1
	legacy_replay_snapshot.erase("time_energy_state")
	invalid_replay_snapshots.append(legacy_replay_snapshot)
	var missing_energy_field := replay_snapshot.duplicate(true)
	missing_energy_field["time_energy_state"].erase("revision")
	invalid_replay_snapshots.append(missing_energy_field)
	var extra_energy_field := replay_snapshot.duplicate(true)
	extra_energy_field["time_energy_state"]["unexpected_authority"] = true
	invalid_replay_snapshots.append(extra_energy_field)
	var invalid_energy_value := replay_snapshot.duplicate(true)
	invalid_energy_value["time_energy_state"]["current"] = NAN
	invalid_replay_snapshots.append(invalid_energy_value)
	var invalid_energy_revision := replay_snapshot.duplicate(true)
	invalid_energy_revision["time_energy_state"]["revision"] = 0
	invalid_replay_snapshots.append(invalid_energy_revision)
	var invalid_energy_maximum := replay_snapshot.duplicate(true)
	invalid_energy_maximum["time_energy_state"]["maximum"] = manager.max_energy + 1.0
	invalid_replay_snapshots.append(invalid_energy_maximum)
	for invalid_snapshot: Dictionary in invalid_replay_snapshots:
		var before_invalid := manager.weapon_replay_snapshot()
		var invalid_signal_count: int = int(signal_count[0])
		_suite.assert_true(
			not manager.restore_weapon_replay_snapshot(invalid_snapshot),
			"TimeManager rejects malformed replay energy authority"
		)
		_suite.assert_equal(
			manager.weapon_replay_snapshot(),
			before_invalid,
			"TimeManager malformed replay energy rejection is atomic"
		)
		_suite.assert_equal(
			signal_count[0],
			invalid_signal_count,
			"TimeManager rejected replay energy emits no signal"
		)

	manager.queue_free()
	await get_tree().process_frame


func _test_time_manager_replay_restore_transaction_is_observable_atomic() -> void:
	var manager = TimeManagerScript.new()
	manager.energy_regen = 0.0
	add_child(manager)
	var stop_probe := ReplayStopProbe.new()
	add_child(stop_probe)
	await get_tree().process_frame

	var observed_snapshots: Array[Dictionary] = []
	manager.energy_changed.connect(func(_current: float, _maximum: float) -> void:
		observed_snapshots.append(manager.weapon_replay_snapshot())
	)
	var before: Dictionary = manager.weapon_replay_snapshot()
	var target := before.duplicate(true)
	target["time_energy_state"]["current"] = 60.0
	target["time_energy_state"]["revision"] = int(
		target["time_energy_state"]["revision"]
	) + 1
	target["stop_active"] = true
	target["stop_source_sequence"] = 1
	target["stop_source_id"] = "replay:stop:1"
	target["stop_remaining"] = 2.5

	var commit_transaction_token: int = manager.begin_weapon_replay_restore_transaction()
	_suite.assert_true(
		commit_transaction_token > 0,
		"TimeManager begins one replay restore transaction"
	)
	_suite.assert_equal(
		manager.begin_weapon_replay_restore_transaction(),
		0,
		"TimeManager rejects a nested replay restore transaction"
	)
	_suite.assert_true(
		not manager.commit_weapon_replay_restore_transaction(commit_transaction_token + 1),
		"a foreign token cannot commit the active replay restore transaction"
	)
	_suite.assert_true(
		not manager.rollback_weapon_replay_restore_transaction(commit_transaction_token + 1),
		"a foreign token cannot roll back the active replay restore transaction"
	)
	_suite.assert_true(
		manager.restore_resource_state(
			&"time_energy",
			(target["time_energy_state"] as Dictionary).duplicate(true)
		),
		"replay transaction stages the coordinator resource restore"
	)
	_suite.assert_true(
		manager.restore_weapon_replay_snapshot(target),
		"replay transaction stages the complete TimeManager snapshot"
	)
	_suite.assert_equal(
		observed_snapshots.size(),
		0,
		"staged replay restore exposes no intermediate energy signal"
	)
	_suite.assert_equal(stop_probe.apply_calls, 0, "staged replay restore does not apply Stop early")
	_suite.assert_equal(stop_probe.clear_calls, 0, "staged replay restore does not clear Stop early")
	_suite.assert_true(
		manager.commit_weapon_replay_restore_transaction(commit_transaction_token),
		"complete replay restore publishes atomically"
	)
	_suite.assert_equal(observed_snapshots, [target], "commit observers see only the complete after snapshot")
	_suite.assert_equal(stop_probe.apply_calls, 1, "commit applies the final Stop source once")
	_suite.assert_equal(stop_probe.clear_calls, 0, "commit does not clear an absent previous Stop source")
	_suite.assert_true(
		not manager.commit_weapon_replay_restore_transaction(commit_transaction_token),
		"TimeManager rejects commit without an active replay restore transaction"
	)
	_suite.assert_true(
		not manager.rollback_weapon_replay_restore_transaction(commit_transaction_token),
		"TimeManager rejects rollback without an active replay restore transaction"
	)

	var committed: Dictionary = manager.weapon_replay_snapshot()
	var rollback_target := committed.duplicate(true)
	rollback_target["time_energy_state"]["current"] = 20.0
	rollback_target["time_energy_state"]["revision"] = int(
		rollback_target["time_energy_state"]["revision"]
	) + 1
	rollback_target["stop_source_sequence"] = 2
	rollback_target["stop_source_id"] = "replay:stop:2"
	rollback_target["stop_remaining"] = 1.0
	var observed_before_rollback := observed_snapshots.size()
	var apply_before_rollback := stop_probe.apply_calls
	var clear_before_rollback := stop_probe.clear_calls
	var rollback_transaction_token: int = manager.begin_weapon_replay_restore_transaction()
	_suite.assert_true(rollback_transaction_token > 0, "rollback fixture begins")
	_suite.assert_true(
		manager.restore_resource_state(
			&"time_energy",
			(rollback_target["time_energy_state"] as Dictionary).duplicate(true)
		),
		"rollback fixture stages resource state"
	)
	_suite.assert_true(
		manager.restore_weapon_replay_snapshot(rollback_target),
		"rollback fixture stages complete time state"
	)
	_suite.assert_true(
		manager.rollback_weapon_replay_restore_transaction(rollback_transaction_token),
		"failed outer restore can silently roll back the TimeManager transaction"
	)
	_suite.assert_equal(manager.weapon_replay_snapshot(), committed, "rollback restores exact before authority")
	_suite.assert_equal(
		observed_snapshots.size(),
		observed_before_rollback,
		"rollback publishes no transient energy signal"
	)
	_suite.assert_equal(stop_probe.apply_calls, apply_before_rollback, "rollback applies no transient Stop")
	_suite.assert_equal(stop_probe.clear_calls, clear_before_rollback, "rollback clears no live Stop")
	_suite.assert_true(
		not manager.rollback_weapon_replay_restore_transaction(rollback_transaction_token),
		"completed rollback cannot be applied twice"
	)

	var abandoned_transaction_token: int = manager.begin_weapon_replay_restore_transaction()
	_suite.assert_true(abandoned_transaction_token > 0, "reset fixture begins a replay restore transaction")
	manager.reset_runtime_state()
	var post_reset_transaction_token: int = manager.begin_weapon_replay_restore_transaction()
	_suite.assert_true(
		post_reset_transaction_token > abandoned_transaction_token,
		"runtime reset invalidates an abandoned replay restore transaction"
	)
	_suite.assert_true(
		manager.rollback_weapon_replay_restore_transaction(post_reset_transaction_token),
		"post-reset replay restore transaction remains usable"
	)

	stop_probe.queue_free()
	manager.queue_free()
	await get_tree().process_frame


func _transaction(provider: Object) -> RefCounted:
	var transaction = WeaponResourceTransactionScript.new()
	_suite.assert_true(
		transaction.configure(
			&"bow",
			PackedStringArray(["charge"]),
			{&"time_energy": provider}
		),
		"resource transaction fixture configures"
	)
	return transaction


func _multi_transaction(energy: Object, focus: Object) -> RefCounted:
	var transaction = WeaponResourceTransactionScript.new()
	_suite.assert_true(
		transaction.configure(
			&"bow",
			PackedStringArray(),
			{&"time_energy": energy, &"focus": focus}
		),
		"multi-account resource transaction fixture configures"
	)
	return transaction


func _plan(action_id: String, cooldown_frames: int, resource_costs: Dictionary) -> Dictionary:
	return {
		"weapon_id": "bow",
		"action_id": action_id,
		"cooldown_frames": cooldown_frames,
		"resource_costs": resource_costs.duplicate(true),
	}
