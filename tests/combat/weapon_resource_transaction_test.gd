extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const TimeManagerScript := preload("res://scripts/time_system/time_manager.gd")
const WeaponResourceTransactionScript := preload(
	"res://scripts/combat/weapons/weapon_resource_transaction.gd"
)


class FakeProvider extends RefCounted:
	var current: float = 100.0
	var maximum: float = 100.0
	var revision: int = 1
	var spend_calls: int = 0
	var fail_commit: bool = false


	func resource_state(resource_id: StringName) -> Dictionary:
		if resource_id != &"time_energy":
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
		if resource_id != &"time_energy":
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
		current -= amount
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


	func bump_revision() -> void:
		revision += 1


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
	_test_cooldown_uses_half_open_frame_boundaries()
	_test_rewind_safe_reset_preserves_committed_state()
	_test_full_reset_clears_only_weapon_transaction_state()
	await _test_time_manager_provider_contract()
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


func _plan(action_id: String, cooldown_frames: int, resource_costs: Dictionary) -> Dictionary:
	return {
		"weapon_id": "bow",
		"action_id": action_id,
		"cooldown_frames": cooldown_frames,
		"resource_costs": resource_costs.duplicate(true),
	}
