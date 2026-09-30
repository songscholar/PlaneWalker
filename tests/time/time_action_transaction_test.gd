extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const TimeActionTransactionScript := preload("res://scripts/time_system/time_action_transaction.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")


class Participant:
	extends RefCounted

	var state: Dictionary = {}
	var commit_calls: int = 0
	var restore_calls: int = 0
	var fail_commit: bool = false
	var mutate_on_failure: bool = true
	var fail_restore: bool = false
	var return_mismatched_snapshot: bool = false
	var received_ticket: Dictionary = {}
	var received_restore_snapshot: Dictionary = {}


	func commit(ticket: Dictionary) -> Dictionary:
		commit_calls += 1
		received_ticket = ticket.duplicate(true)
		var callback_snapshot_before_mutation := (
			(ticket.get("prepared_snapshot", {}) as Dictionary).duplicate(true)
		)
		state = {
			"phase": "installed",
			"token": int(ticket.get("token", 0)),
			"context": (ticket.get("context", {}) as Dictionary).duplicate(true),
		}
		var callback_context := ticket.get("context", {}) as Dictionary
		callback_context["callback_mutation"] = true
		var callback_snapshot := ticket.get("prepared_snapshot", {}) as Dictionary
		callback_snapshot["revision"] = 999999
		if fail_commit:
			if not mutate_on_failure:
				state = callback_snapshot_before_mutation
			return {
				"ok": false,
				"code": &"INSTALL_FAILED",
				"mutated": mutate_on_failure,
			}
		return {
			"ok": true,
			"code": &"INSTALLED",
			"publication": {"source": "participant"},
		}


	func restore(snapshot: Dictionary) -> Dictionary:
		restore_calls += 1
		received_restore_snapshot = snapshot.duplicate(true)
		if fail_restore:
			return {"ok": false, "code": &"RESTORE_REJECTED"}
		state = snapshot.duplicate(true)
		var reported := state.duplicate(true)
		if return_mismatched_snapshot:
			reported["revision"] = int(reported.get("revision", 0)) + 1
		return {
			"ok": true,
			"restored_snapshot": reported,
		}


class TimeStopTarget:
	extends Node

	var applied_duration: float = -1.0
	var applied_source_id: StringName = &""
	var weakpoint_duration: float = -1.0
	var weakpoint_damage_bonus: float = -1.0
	var apply_calls: int = 0
	var clear_calls: int = 0
	var weakpoint_calls: int = 0


	func apply_time_stop_source(source_id: StringName, duration: float) -> void:
		apply_calls += 1
		applied_source_id = source_id
		applied_duration = duration


	func clear_time_stop_source(source_id: StringName) -> void:
		clear_calls += 1
		if source_id == applied_source_id:
			applied_source_id = &""


	func apply_weakpoint(duration: float, damage_bonus: float) -> void:
		weakpoint_calls += 1
		weakpoint_duration = duration
		weakpoint_damage_bonus = damage_bonus


class RejectedDamageResolution:
	extends RefCounted


	func is_prevented() -> bool:
		return true


	func finalized_damage() -> float:
		return 0.0


class RejectingHealth:
	extends Node

	var claim_calls: int = 0
	var received_tokens: Array[int] = []
	var received_generations: Array[int] = []


	func lose_health_irreversible(
		_amount: float,
		_reason: StringName,
		source_token: int,
		source_generation: int,
		_claim_run_id: StringName = &""
	) -> RefCounted:
		claim_calls += 1
		received_tokens.append(source_token)
		received_generations.append(source_generation)
		return RejectedDamageResolution.new()


var _suite
var _committed_fact_count: int = 0
var _last_committed_fact: Dictionary = {}
var _last_rewind_committed: Dictionary = {}
var _atomic_stop_started_count: int = 0
var _atomic_stop_ended_count: int = 0
var _atomic_time_committed_count: int = 0
var _atomic_energy_event_count: int = 0
var _atomic_cooldown_event_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_prepare_freezes_inputs_and_rejects_duplicate()
	_test_ticket_identity_is_closed_and_owner_bound()
	_test_commit_is_exactly_once_and_preserves_frozen_context()
	_test_failed_commit_restores_exact_prepare_snapshot()
	_test_failed_commit_without_restore_requires_explicit_rollback()
	_test_unmutated_commit_rejection_can_finalize_without_restore()
	_test_explicit_rollback_requires_exact_restored_snapshot()
	_test_finalized_watermark_rejects_out_of_order_identities()
	_test_finalized_ticket_diagnostics_are_bounded()
	await _test_time_manager_rollback_preserves_existing_world_node()
	await _test_time_manager_transaction_integration()
	await _test_time_stop_self_damage_rejection_is_atomic()
	await _test_player_time_action_failure_restores_replay_prefix()
	await _test_time_manager_accelerate_settlement_is_frozen()
	await _test_time_manager_rift_settlement_is_frozen()
	_suite.finish(get_tree())


func _test_prepare_freezes_inputs_and_rejects_duplicate() -> void:
	var transaction := TimeActionTransactionScript.new()
	var context := {
		"pre_return_position": Vector2(300.0, 120.0),
		"path": [Vector2(300.0, 120.0), Vector2(96.0, 64.0)],
		"nested": {"selected_pair": ["stop", "rewind"]},
	}
	var prepared_snapshot := _snapshot(4)
	var expected_context := context.duplicate(true)
	var expected_snapshot := prepared_snapshot.duplicate(true)
	var ticket: Dictionary = transaction.prepare(
		8,
		4,
		120,
		&"run-a",
		&"rewind",
		context,
		prepared_snapshot
	)
	_suite.assert_true(not ticket.is_empty(), "valid prepare returns one ticket")
	_suite.assert_equal(ticket.get("context"), expected_context, "ticket freezes the complete pre-context")
	_suite.assert_equal(
		ticket.get("prepared_snapshot"),
		expected_snapshot,
		"ticket freezes the complete participant snapshot"
	)

	context["pre_return_position"] = Vector2.ZERO
	(context["path"] as Array).clear()
	((context["nested"] as Dictionary)["selected_pair"] as Array).append("rift")
	prepared_snapshot["energy"] = 0
	(prepared_snapshot["cooldowns"] as Dictionary)["rewind"] = 999
	_suite.assert_equal(ticket.get("context"), expected_context, "caller context mutation cannot alter the ticket")
	_suite.assert_equal(
		ticket.get("prepared_snapshot"),
		expected_snapshot,
		"caller snapshot mutation cannot alter the ticket"
	)
	_suite.assert_true(
		transaction.prepare(9, 4, 121, &"run-a", &"stop", {}, _snapshot(5)).is_empty(),
		"a second prepare is rejected while one transaction is active"
	)

	var authentic_ticket := ticket.duplicate(true)
	((ticket["context"] as Dictionary)["nested"] as Dictionary)["selected_pair"] = []
	var participant := Participant.new()
	var forged_result: Dictionary = transaction.commit(ticket, participant.commit)
	_suite.assert_true(not bool(forged_result.get("ok", false)), "a mutated public ticket is rejected")
	_suite.assert_equal(participant.commit_calls, 0, "a forged ticket never reaches the commit callback")
	var rolled_back: Dictionary = transaction.rollback(authentic_ticket, participant.restore)
	_suite.assert_true(bool(rolled_back.get("ok", false)), "the authentic ticket remains rollback-capable")
	_suite.assert_equal(
		rolled_back.get("restored_snapshot"),
		expected_snapshot,
		"rollback returns the exact frozen prepare snapshot"
	)


func _test_ticket_identity_is_closed_and_owner_bound() -> void:
	var transaction := TimeActionTransactionScript.new()
	_suite.assert_true(
		transaction.prepare(0, 1, 1, &"run-a", &"stop", {}, _snapshot(1)).is_empty(),
		"zero token is rejected"
	)
	_suite.assert_true(
		transaction.prepare(1, 0, 1, &"run-a", &"stop", {}, _snapshot(1)).is_empty(),
		"zero generation is rejected"
	)
	_suite.assert_true(
		transaction.prepare(1, 1, -1, &"run-a", &"stop", {}, _snapshot(1)).is_empty(),
		"negative frame is rejected"
	)
	_suite.assert_true(
		transaction.prepare(1, 1, 1, &"", &"stop", {}, _snapshot(1)).is_empty(),
		"empty run identity is rejected"
	)
	_suite.assert_true(
		transaction.prepare(1, 1, 1, &"run:a", &"stop", {}, _snapshot(1)).is_empty(),
		"run identities containing the stable-id separator are rejected"
	)
	_suite.assert_true(
		transaction.prepare(1, 1, 1, &"run-a", &"", {}, _snapshot(1)).is_empty(),
		"empty ability identity is rejected"
	)

	var ticket: Dictionary = transaction.prepare(21, 7, 360, &"run-a", &"rift", {}, _snapshot(7))
	var participant := Participant.new()
	for field: String in ["token", "generation", "frame", "run_id", "ability_id"]:
		var forged := ticket.duplicate(true)
		match field:
			"token":
				forged[field] = 22
			"generation":
				forged[field] = 8
			"frame":
				forged[field] = 361
			"run_id":
				forged[field] = &"run-b"
			"ability_id":
				forged[field] = &"stop"
		var rejected: Dictionary = transaction.commit(forged, participant.commit)
		_suite.assert_true(not bool(rejected.get("ok", false)), "forged %s is rejected" % field)
	_suite.assert_equal(participant.commit_calls, 0, "identity forgeries never reach participant code")

	var foreign := TimeActionTransactionScript.new()
	var foreign_result: Dictionary = foreign.commit(ticket, participant.commit)
	_suite.assert_true(not bool(foreign_result.get("ok", false)), "a ticket is bound to its transaction owner")
	_suite.assert_equal(participant.commit_calls, 0, "a foreign owner cannot invoke the callback")
	_suite.assert_true(
		bool(transaction.rollback(ticket, participant.restore).get("ok", false)),
		"identity rejection leaves the authentic transaction intact"
	)


func _test_commit_is_exactly_once_and_preserves_frozen_context() -> void:
	var transaction := TimeActionTransactionScript.new()
	var frozen_context := {
		"pre_return_position": Vector2(144.0, 88.0),
		"selected_pair": ["stop", "rewind"],
	}
	var ticket: Dictionary = transaction.prepare(
		31,
		9,
		480,
		&"run-commit",
		&"rewind",
		frozen_context,
		_snapshot(9)
	)
	var participant := Participant.new()
	var committed: Dictionary = transaction.commit(ticket, participant.commit)
	_suite.assert_true(bool(committed.get("ok", false)), "a valid prepared action commits")
	_suite.assert_equal(StringName(committed.get("code", &"")), &"OK", "successful commit reports OK")
	_suite.assert_equal(participant.commit_calls, 1, "commit callback executes exactly once")
	_suite.assert_equal(
		committed.get("context"),
		frozen_context,
		"callback mutation cannot change committed immutable context"
	)
	_suite.assert_equal(
		participant.received_ticket.get("prepared_snapshot"),
		_snapshot(9),
		"commit callback receives the complete frozen participant snapshot"
	)
	_suite.assert_equal(
		(committed.get("ticket", {}) as Dictionary).get("prepared_snapshot"),
		_snapshot(9),
		"callback mutation cannot change the authoritative prepared snapshot"
	)

	var duplicate: Dictionary = transaction.commit(ticket, participant.commit)
	_suite.assert_true(not bool(duplicate.get("ok", false)), "duplicate commit is rejected")
	_suite.assert_equal(
		StringName(duplicate.get("code", &"")),
		&"ALREADY_COMMITTED",
		"duplicate commit has a stable diagnostic"
	)
	_suite.assert_equal(participant.commit_calls, 1, "duplicate commit never reinvokes participant code")
	var stale_rollback: Dictionary = transaction.rollback(ticket, participant.restore)
	_suite.assert_true(not bool(stale_rollback.get("ok", false)), "rollback after commit is stale")
	_suite.assert_equal(participant.restore_calls, 0, "stale rollback never invokes participant code")
	_suite.assert_true(
		transaction.prepare(31, 9, 481, &"run-commit", &"stop", {}, _snapshot(10)).is_empty(),
		"a finalized token and generation pair cannot be prepared again"
	)


func _test_failed_commit_restores_exact_prepare_snapshot() -> void:
	var transaction := TimeActionTransactionScript.new()
	var before := _snapshot(11)
	var ticket: Dictionary = transaction.prepare(
		41,
		11,
		600,
		&"run-restore",
		&"stop",
		{"stop_origin": Vector2(64.0, 32.0)},
		before
	)
	var participant := Participant.new()
	participant.state = before.duplicate(true)
	participant.fail_commit = true
	participant.mutate_on_failure = true
	var rejected: Dictionary = transaction.commit(ticket, participant.commit, participant.restore)
	_suite.assert_true(not bool(rejected.get("ok", true)), "failed participant commit is rejected")
	_suite.assert_equal(
		StringName(rejected.get("code", &"")),
		&"COMMIT_FAILED_ROLLED_BACK",
		"failed commit reports verified rollback"
	)
	_suite.assert_equal(
		StringName(rejected.get("failure_code", &"")),
		&"INSTALL_FAILED",
		"failed commit preserves the participant diagnostic"
	)
	_suite.assert_equal(participant.commit_calls, 1, "failed commit is attempted once")
	_suite.assert_equal(participant.restore_calls, 1, "failed commit invokes one compensation restore")
	_suite.assert_equal(participant.received_restore_snapshot, before, "restore receives the frozen prepare snapshot")
	_suite.assert_equal(participant.state, before, "participant state is restored exactly")
	_suite.assert_equal(rejected.get("restored_snapshot"), before, "result returns the exact restored snapshot")
	_suite.assert_true(
		not bool(transaction.commit(ticket, participant.commit, participant.restore).get("ok", false)),
		"a compensated failed commit cannot execute again"
	)
	_suite.assert_equal(participant.commit_calls, 1, "compensated failure remains exactly once")
	_suite.assert_true(
		not bool(transaction.rollback(ticket, participant.restore).get("ok", false)),
		"a compensated failure leaves no rollback-capable ticket"
	)


func _test_failed_commit_without_restore_requires_explicit_rollback() -> void:
	var transaction := TimeActionTransactionScript.new()
	var before := _snapshot(13)
	var ticket: Dictionary = transaction.prepare(
		51,
		13,
		720,
		&"run-explicit-rollback",
		&"accelerate",
		{},
		before
	)
	var participant := Participant.new()
	participant.state = before.duplicate(true)
	participant.fail_commit = true
	participant.mutate_on_failure = true
	var rejected: Dictionary = transaction.commit(ticket, participant.commit)
	_suite.assert_true(not bool(rejected.get("ok", true)), "failed commit without compensation is rejected")
	_suite.assert_equal(
		StringName(rejected.get("code", &"")),
		&"RESTORE_CALLBACK_REQUIRED",
		"mutating failure never claims implicit rollback"
	)
	_suite.assert_true(participant.state != before, "fixture proves the failed callback changed participant state")
	var retried: Dictionary = transaction.commit(ticket, participant.commit, participant.restore)
	_suite.assert_true(not bool(retried.get("ok", false)), "an attempted commit cannot be retried")
	_suite.assert_equal(
		StringName(retried.get("code", &"")),
		&"COMMIT_ALREADY_ATTEMPTED",
		"retry receives a stable diagnostic"
	)
	_suite.assert_equal(participant.commit_calls, 1, "retry never reinvokes participant commit")
	var rolled_back: Dictionary = transaction.rollback(ticket, participant.restore)
	_suite.assert_true(bool(rolled_back.get("ok", false)), "explicit rollback remains available after failed commit")
	_suite.assert_equal(rolled_back.get("restored_snapshot"), before, "explicit rollback returns the exact snapshot")
	_suite.assert_equal(participant.state, before, "explicit rollback restores participant state")


func _test_unmutated_commit_rejection_can_finalize_without_restore() -> void:
	var transaction := TimeActionTransactionScript.new()
	var before := _snapshot(15)
	var ticket: Dictionary = transaction.prepare(
		61,
		15,
		840,
		&"run-unmutated",
		&"rift",
		{},
		before
	)
	var participant := Participant.new()
	participant.state = before.duplicate(true)
	participant.fail_commit = true
	participant.mutate_on_failure = false
	var rejected: Dictionary = transaction.commit(ticket, participant.commit)
	_suite.assert_true(not bool(rejected.get("ok", true)), "declared-unmutated participant rejection fails")
	_suite.assert_equal(
		StringName(rejected.get("code", &"")),
		&"COMMIT_REJECTED_UNMUTATED",
		"unmutated rejection has an explicit non-rollback diagnostic"
	)
	_suite.assert_equal(participant.state, before, "declared-unmutated rejection preserves participant state")
	_suite.assert_true(
		not bool(transaction.rollback(ticket, participant.restore).get("ok", false)),
		"finalized unmutated rejection makes rollback stale"
	)
	_suite.assert_equal(participant.restore_calls, 0, "unmutated rejection does not invent a restore")


func _test_explicit_rollback_requires_exact_restored_snapshot() -> void:
	var transaction := TimeActionTransactionScript.new()
	var before := _snapshot(17)
	var ticket: Dictionary = transaction.prepare(
		71,
		17,
		960,
		&"run-rollback-validation",
		&"stop",
		{},
		before
	)
	var participant := Participant.new()
	participant.return_mismatched_snapshot = true
	var mismatch: Dictionary = transaction.rollback(ticket, participant.restore)
	_suite.assert_true(not bool(mismatch.get("ok", false)), "mismatched restore evidence is rejected")
	_suite.assert_equal(
		StringName(mismatch.get("code", &"")),
		&"ROLLBACK_FAILED",
		"mismatched restore evidence reports rollback failure"
	)
	participant.return_mismatched_snapshot = false
	var restored: Dictionary = transaction.rollback(ticket, participant.restore)
	_suite.assert_true(bool(restored.get("ok", false)), "failed rollback validation leaves one recovery path")
	_suite.assert_equal(restored.get("restored_snapshot"), before, "successful retry returns exact snapshot")
	var stale: Dictionary = transaction.rollback(ticket, participant.restore)
	_suite.assert_true(not bool(stale.get("ok", false)), "duplicate rollback is stale")
	_suite.assert_equal(StringName(stale.get("code", &"")), &"STALE_TICKET", "stale rollback has a stable code")
	_suite.assert_equal(participant.restore_calls, 2, "stale rollback never reinvokes participant restore")


func _test_finalized_watermark_rejects_out_of_order_identities() -> void:
	var transaction := TimeActionTransactionScript.new()
	var participant := Participant.new()
	var first: Dictionary = transaction.prepare(
		10,
		2,
		100,
		&"run-watermark-a",
		&"stop",
		{},
		_snapshot(1)
	)
	_suite.assert_true(not first.is_empty(), "the first identity establishes a run watermark")
	_suite.assert_true(bool(transaction.commit(first, participant.commit).get("ok", false)), "the first identity commits")
	_suite.assert_true(
		transaction.prepare(9, 2, 101, &"run-watermark-a", &"stop", {}, _snapshot(2)).is_empty(),
		"a lower token in the finalized generation cannot be prepared"
	)
	_suite.assert_true(
		transaction.prepare(10, 2, 102, &"run-watermark-a", &"rift", {}, _snapshot(3)).is_empty(),
		"the finalized token cannot be reused with a different frame or ability"
	)
	_suite.assert_true(
		transaction.prepare(999, 1, 103, &"run-watermark-a", &"stop", {}, _snapshot(4)).is_empty(),
		"a token from an older generation cannot outrun the current generation watermark"
	)

	var next_generation: Dictionary = transaction.prepare(
		1,
		3,
		104,
		&"run-watermark-a",
		&"accelerate",
		{},
		_snapshot(5)
	)
	_suite.assert_true(not next_generation.is_empty(), "a newer generation may restart its monotonic token sequence")
	_suite.assert_true(
		bool(transaction.rollback(next_generation, participant.restore).get("ok", false)),
		"rolling back the newer generation still finalizes its identity"
	)
	_suite.assert_true(
		transaction.prepare(9999, 2, 105, &"run-watermark-a", &"stop", {}, _snapshot(6)).is_empty(),
		"advancing a generation permanently tombstones every older generation"
	)
	_suite.assert_true(
		transaction.prepare(1, 3, 106, &"run-watermark-a", &"stop", {}, _snapshot(7)).is_empty(),
		"a rolled-back token cannot be prepared again"
	)

	var independent_run: Dictionary = transaction.prepare(
		1,
		1,
		0,
		&"run-watermark-b",
		&"stop",
		{},
		_snapshot(8)
	)
	_suite.assert_true(not independent_run.is_empty(), "watermarks remain isolated by stable run identity")
	_suite.assert_true(
		bool(transaction.rollback(independent_run, participant.restore).get("ok", false)),
		"an independent run can finalize its own first generation"
	)


func _test_finalized_ticket_diagnostics_are_bounded() -> void:
	var transaction := TimeActionTransactionScript.new()
	var participant := Participant.new()
	var oldest_ticket: Dictionary = {}
	var newest_ticket: Dictionary = {}
	for token: int in range(1, 5001):
		var ticket: Dictionary = transaction.prepare(
			token,
			1,
			token,
			&"run-bounded-ledger",
			&"stop",
			{},
			_snapshot(token)
		)
		_suite.assert_true(not ticket.is_empty(), "monotonic action %d prepares" % token)
		_suite.assert_true(bool(transaction.commit(ticket, participant.commit).get("ok", false)), "monotonic action %d commits" % token)
		if token == 1:
			oldest_ticket = ticket.duplicate(true)
		if token == 5000:
			newest_ticket = ticket.duplicate(true)

	var finalized_tickets := transaction.get("_finalized_tickets") as Dictionary
	var finalized_ticket_order := transaction.get("_finalized_ticket_order") as Array
	var finalized_watermarks := transaction.get("_finalized_watermarks") as Dictionary
	_suite.assert_true(finalized_tickets.size() <= 64, "recent ticket diagnostics have a constant upper bound")
	_suite.assert_true(finalized_ticket_order.size() <= 64, "diagnostic eviction order has the same constant upper bound")
	_suite.assert_equal(finalized_tickets.size(), finalized_ticket_order.size(), "diagnostic cache and eviction order remain synchronized")
	_suite.assert_equal(finalized_watermarks.size(), 1, "five thousand actions collapse to one run watermark")
	_suite.assert_equal(participant.commit_calls, 5000, "every distinct monotonic action commits exactly once")

	var recent_duplicate: Dictionary = transaction.commit(newest_ticket, participant.commit)
	_suite.assert_equal(
		StringName(recent_duplicate.get("code", &"")),
		&"ALREADY_COMMITTED",
		"a recent committed ticket retains the precise duplicate diagnostic"
	)
	var compacted_duplicate: Dictionary = transaction.commit(oldest_ticket, participant.commit)
	_suite.assert_equal(
		StringName(compacted_duplicate.get("code", &"")),
		&"STALE_TICKET",
		"an evicted authentic ticket remains stale instead of becoming invalid or executable"
	)
	_suite.assert_equal(participant.commit_calls, 5000, "neither recent nor compacted duplicates reexecute participant code")
	_suite.assert_true(
		transaction.prepare(1, 1, 5001, &"run-bounded-ledger", &"stop", {}, _snapshot(5001)).is_empty(),
		"compaction never resurrects an evicted finalized identity"
	)


func _test_time_manager_rollback_preserves_existing_world_node() -> void:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	var manager: Node = player.get_node("TimeManager")
	manager.set_process(false)
	var recorder: Node = player.get_node("RewindRecorder")
	recorder.set_process(false)
	add_child(player)
	await get_tree().process_frame
	player.reset_runtime_state()
	_suite.assert_true(player.configure_loadout({
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rift"],
	}), "transaction Node identity fixture configures Stop and Rift")
	manager.time_rift_cost = 0.0
	manager.time_rift_cooldown = 0.0
	manager.time_stop_cost = 0.0
	manager.time_stop_cooldown = 0.0
	_suite.assert_true(manager.try_time_rift(Vector2(96.0, 64.0)), "existing committed Rift fixture spawns")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	var payload_id := StringName("%s:%d:rift:1:1" % [
		player.current_run_id(),
		player.owner_character_generation(),
	])
	var existing_node: Node = authority.payload_node(payload_id)
	var before: Dictionary = authority.replay_snapshot()
	var ticket: Dictionary = manager.prepare_time_action(
		201,
		5,
		0,
		player.current_run_id(),
		&"stop",
		{}
	)
	_suite.assert_true(not ticket.is_empty(), "Stop prepares while a committed Rift exists")
	var rolled_back: Dictionary = manager.rollback_time_action(ticket)
	_suite.assert_true(bool(rolled_back.get("ok", false)), "unmutated TimeAction rollback succeeds")
	_suite.assert_equal(authority.replay_snapshot(), before, "unmutated rollback preserves the world descriptor root")
	_suite.assert_true(
		authority.payload_node(payload_id) == existing_node,
		"unmutated TimeAction rollback preserves the exact committed Rift Node"
	)
	player.reset_runtime_state()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_time_manager_transaction_integration() -> void:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	var manager: Node = player.get_node("TimeManager")
	manager.set_process(false)
	var recorder: Node = player.get_node("RewindRecorder")
	recorder.set_process(false)
	add_child(player)
	await get_tree().process_frame
	player.reset_runtime_state()
	player.advance_action_frame({})
	manager.energy_regen = 0.0
	manager.time_stop_cost = 0.0
	manager.time_stop_cooldown = 2.0
	manager.time_stop_duration = 1.0
	_committed_fact_count = 0
	_last_committed_fact.clear()
	EventBus.time_skill_committed.connect(_on_time_skill_committed)

	var run_id: StringName = player.current_run_id()
	var rollback_ticket: Dictionary = manager.prepare_time_action(
		101,
		3,
		1,
		run_id,
		&"stop",
		{}
	)
	_suite.assert_true(not rollback_ticket.is_empty(), "TimeManager prepares an equipped Stop at the authoritative frame")
	var prepared_snapshot := (rollback_ticket.get("prepared_snapshot", {}) as Dictionary).duplicate(true)
	var rolled_back: Dictionary = manager.rollback_time_action(rollback_ticket)
	_suite.assert_true(bool(rolled_back.get("ok", false)), "TimeManager explicitly rolls back a prepared action")
	_suite.assert_equal(rolled_back.get("restored_snapshot"), prepared_snapshot, "TimeManager rollback returns the exact prepare snapshot")
	_suite.assert_equal(manager.time_action_snapshot(), prepared_snapshot, "TimeManager rollback restores every participant byte-for-byte")
	_suite.assert_equal(_committed_fact_count, 0, "prepare and rollback publish no committed fact")

	manager.time_stop_cost = 16.0
	manager.time_stop_cost_multiplier = 1.25
	manager.time_stop_cooldown = 2.25
	manager.time_stop_duration = 1.0
	manager.time_stop_duration_bonus = 0.5
	manager.time_stop_weakpoint_damage_bonus = 0.4
	manager.time_stop_weakpoint_duration = 0.75
	manager.time_stop_self_damage = 3.0
	var stop_target := TimeStopTarget.new()
	stop_target.add_to_group("time_stoppable")
	add_child(stop_target)
	var health: Node = player.get_node("HealthComponent")
	var hp_before_stop := float(health.get("current_hp"))
	var commit_ticket: Dictionary = manager.prepare_time_action(
		102,
		3,
		1,
		run_id,
		&"stop",
		{}
	)
	_suite.assert_true(not commit_ticket.is_empty(), "TimeManager prepares a replacement transaction")
	manager.time_stop_cost = 999.0
	manager.time_stop_cost_multiplier = 999.0
	manager.time_stop_cooldown = 9.0
	manager.time_stop_duration = 9.0
	manager.time_stop_duration_bonus = 9.0
	manager.time_stop_weakpoint_damage_bonus = 9.0
	manager.time_stop_weakpoint_duration = 9.0
	manager.time_stop_self_damage = 9.0
	var committed: Dictionary = manager.commit_time_action(commit_ticket)
	_suite.assert_true(bool(committed.get("ok", false)), "TimeManager commits the prepared Stop exactly once")
	_suite.assert_equal(_committed_fact_count, 1, "successful TimeAction publishes one committed fact")
	_suite.assert_equal(_last_committed_fact.get("ability_id"), &"stop", "committed fact uses the canonical ability id")
	_suite.assert_equal(_last_committed_fact.get("token"), 102, "committed fact preserves the action token")
	_suite.assert_equal(_last_committed_fact.get("frame"), 1, "committed fact preserves the authoritative frame")
	_suite.assert_true(bool(manager.weapon_interaction_context().get("stop_active", false)), "committed TimeAction applies the selected ability")
	_suite.assert_close(manager.energy, 80.0, "Stop commit spends the cost multiplier frozen at prepare")
	_suite.assert_equal(
		int((manager.get("_cooldown_frames") as Dictionary).get(&"time_stop", -1)),
		135,
		"Stop commit installs the frozen integer cooldown frame count"
	)
	_suite.assert_equal(int(manager.get("_time_stop_remaining_frames")), 90, "Stop commit installs the frozen duration frames")
	_suite.assert_close(stop_target.applied_duration, 1.5, "Stop target receives the frozen authoritative duration")
	_suite.assert_close(stop_target.weakpoint_duration, 0.75, "Stop target receives frozen weakpoint duration")
	_suite.assert_close(stop_target.weakpoint_damage_bonus, 0.4, "Stop target receives frozen weakpoint damage")
	_suite.assert_close(float(health.get("current_hp")), hp_before_stop - 3.0, "Stop applies frozen irreversible self-damage")
	_suite.assert_true(not bool(manager.commit_time_action(commit_ticket).get("ok", false)), "duplicate TimeAction commit is rejected")
	_suite.assert_equal(_committed_fact_count, 1, "duplicate commit cannot publish another fact")

	var unequipped: Dictionary = manager.prepare_time_action(
		103,
		3,
		1,
		run_id,
		&"rift",
		{"position": Vector2.ZERO}
	)
	_suite.assert_true(unequipped.is_empty(), "TimeAction prepare rejects an unequipped ability without mutation")
	manager.cancel_all_time_effects(&"time_action_test_cleanup")
	manager.rewind_cost = 12.0
	manager.rewind_cost_multiplier = 1.5
	manager.rewind_cooldown = 2.25
	manager.rewind_self_damage = 4.0
	manager.rewind_heal = 1.0
	manager.rewind_echo_enabled = true
	manager.rewind_path_hit_multiplier = 0.4
	for _frame: int in range(5):
		player.advance_action_frame({})
	var frozen_origin := Vector2(320.0, 144.0)
	player.global_position = frozen_origin
	var prepared_history: Dictionary = recorder.peek_oldest_snapshot()
	var energy_before_rewind := float(manager.energy)
	var hp_before_rewind := float(prepared_history.get("hp", -1.0))
	_last_rewind_committed.clear()
	manager.rewind_committed.connect(_on_rewind_committed)
	var rewind_ticket: Dictionary = manager.prepare_time_action(
		104,
		3,
		6,
		run_id,
		&"rewind",
		{"pre_return_position": frozen_origin}
	)
	_suite.assert_true(not rewind_ticket.is_empty(), "Rewind TimeAction prepares against a real six-frame snapshot")
	var recorder_ticket := (
		(manager.get("_prepared_time_action_settlement") as Dictionary).get(
			"recorder_ticket",
			{}
		) as Dictionary
	).duplicate(true)
	manager.rewind_cost = 999.0
	manager.rewind_cost_multiplier = 999.0
	manager.rewind_cooldown = 99.0
	manager.rewind_self_damage = 0.0
	manager.rewind_heal = 99.0
	manager.rewind_echo_enabled = false
	manager.rewind_path_hit_multiplier = 0.0
	player.global_position = Vector2(12.0, 34.0)
	_suite.assert_equal(
		(rewind_ticket.get("context", {}) as Dictionary).get("pre_return_position"),
		frozen_origin,
		"Rewind prepare freezes the pre-return position before later movement"
	)
	var rewind_committed: Dictionary = manager.commit_time_action(rewind_ticket)
	_suite.assert_true(bool(rewind_committed.get("ok", false)), "prepared Rewind commits after position-only participant drift")
	_suite.assert_equal(_committed_fact_count, 2, "Rewind commit publishes one additional committed fact")
	_suite.assert_equal(_last_rewind_committed.get("origin"), frozen_origin, "Rewind publication keeps the frozen prepare origin")
	var committed_path := _last_rewind_committed.get("path_samples", []) as Array
	_suite.assert_true(not committed_path.is_empty(), "Rewind publication preserves its prepared path")
	if not committed_path.is_empty():
		_suite.assert_equal(committed_path.front(), frozen_origin, "Rewind path begins at the frozen pre-return position")
	_suite.assert_equal(_last_rewind_committed.get("destination"), prepared_history.get("position"), "Rewind destination remains the prepared history position")
	_suite.assert_equal(_last_rewind_committed.get("target_snapshot"), prepared_history, "Rewind commit consumes the exact prepared history snapshot")
	_suite.assert_equal(_last_rewind_committed.get("history_revision"), recorder_ticket.get("history_revision"), "Rewind commit preserves the prepared history revision")
	_suite.assert_close(manager.energy, energy_before_rewind - 18.0, "Rewind commit spends the frozen multiplied energy cost")
	_suite.assert_equal(
		int((manager.get("_cooldown_frames") as Dictionary).get(&"time_rewind", -1)),
		135,
		"Rewind commit installs the frozen cooldown frame count"
	)
	_suite.assert_close(float(health.get("current_hp")), hp_before_rewind - 3.0, "Rewind uses frozen self-damage and heal values")
	var echo_runtime: Node = player.get_node("RewindEchoRuntime")
	_suite.assert_true(bool(echo_runtime.call("is_echo_active")), "Rewind uses the frozen echo-enabled modifier")
	_suite.assert_close(float(echo_runtime.get("_committed_path_hit_multiplier")), 0.4, "Rewind echo captures the frozen path-hit modifier")
	manager.rewind_committed.disconnect(_on_rewind_committed)
	EventBus.time_skill_committed.disconnect(_on_time_skill_committed)
	await get_tree().create_timer(0.55).timeout
	stop_target.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_time_stop_self_damage_rejection_is_atomic() -> void:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	var manager: Node = player.get_node("TimeManager")
	manager.set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	add_child(player)
	await get_tree().process_frame
	player.reset_runtime_state()
	_suite.assert_true(player.configure_loadout({
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rift"],
	}), "self-damage rejection fixture equips Stop")

	var original_health: Node = player.get_node("HealthComponent")
	player.remove_child(original_health)
	original_health.queue_free()
	var rejecting_health := RejectingHealth.new()
	rejecting_health.name = "HealthComponent"
	player.add_child(rejecting_health)

	manager.energy_regen = 0.0
	manager.time_stop_cost = 15.0
	manager.time_stop_cooldown = 2.0
	manager.time_stop_duration = 1.0
	manager.time_stop_self_damage = 4.0
	var stop_target := TimeStopTarget.new()
	stop_target.add_to_group("time_stoppable")
	add_child(stop_target)

	_atomic_stop_started_count = 0
	_atomic_stop_ended_count = 0
	_atomic_time_committed_count = 0
	_atomic_energy_event_count = 0
	_atomic_cooldown_event_count = 0
	EventBus.time_skill_started.connect(_on_atomic_time_skill_started)
	EventBus.time_skill_ended.connect(_on_atomic_time_skill_ended)
	EventBus.time_skill_committed.connect(_on_atomic_time_skill_committed)
	manager.energy_changed.connect(_on_atomic_energy_changed)
	manager.cooldown_changed.connect(_on_atomic_cooldown_changed)

	var prepared_before := _time_stop_atomic_state(manager)
	var ticket: Dictionary = manager.prepare_time_action(
		501,
		11,
		0,
		player.current_run_id(),
		&"stop",
		{}
	)
	_suite.assert_true(not ticket.is_empty(), "Stop prepares before the irreversible claim is attempted")
	var rejected_commit: Dictionary = manager.commit_time_action(ticket)
	_suite.assert_true(not bool(rejected_commit.get("ok", false)), "rejected prepared Stop claim fails the TimeAction commit")
	_suite.assert_equal(
		StringName(str(rejected_commit.get("code", ""))),
		&"COMMIT_REJECTED_UNMUTATED",
		"rejected prepared Stop claim reports an unmutated failure"
	)
	_suite.assert_equal(manager.call("replay_snapshot"), prepared_before.get("replay"), "prepared Stop rejection restores the exact TimeManager state")
	_suite.assert_equal(_time_stop_atomic_state(manager), prepared_before, "prepared Stop rejection preserves energy, cooldown, source identity, targets, and claim counters")
	_suite.assert_equal(rejecting_health.claim_calls, 1, "prepared Stop attempts exactly one irreversible claim")
	_suite.assert_equal(rejecting_health.received_tokens, [1], "prepared Stop rejection does not consume its claim token")
	_suite.assert_equal(rejecting_health.received_generations, [1], "prepared Stop uses the current irreversible generation")
	_assert_rejected_stop_published_nothing(stop_target, "prepared Stop")

	var direct_before := _time_stop_atomic_state(manager)
	_suite.assert_true(not manager.try_time_stop(), "rejected direct Stop claim returns false")
	_suite.assert_equal(_time_stop_atomic_state(manager), direct_before, "direct Stop rejection preserves energy, cooldown, source identity, targets, and claim counters")
	_suite.assert_equal(rejecting_health.claim_calls, 2, "direct Stop attempts exactly one additional irreversible claim")
	_suite.assert_equal(rejecting_health.received_tokens, [1, 1], "direct Stop retries the unconsumed claim token")
	_suite.assert_equal(rejecting_health.received_generations, [1, 1], "direct Stop preserves the irreversible generation")
	_assert_rejected_stop_published_nothing(stop_target, "direct Stop")

	EventBus.time_skill_started.disconnect(_on_atomic_time_skill_started)
	EventBus.time_skill_ended.disconnect(_on_atomic_time_skill_ended)
	EventBus.time_skill_committed.disconnect(_on_atomic_time_skill_committed)
	manager.energy_changed.disconnect(_on_atomic_energy_changed)
	manager.cooldown_changed.disconnect(_on_atomic_cooldown_changed)
	stop_target.queue_free()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _time_stop_atomic_state(manager: Node) -> Dictionary:
	return {
		"replay": manager.call("replay_snapshot"),
		"interaction": manager.call("weapon_interaction_context"),
		"stop_source_id": str(manager.get("_time_stop_source_id")),
		"stop_targets": (manager.get("_time_stop_targets") as Array).duplicate(),
		"self_damage_generation": int(manager.get("_irreversible_self_damage_generation")),
		"next_self_damage_token": int(manager.get("_next_irreversible_self_damage_token")),
	}


func _assert_rejected_stop_published_nothing(target: TimeStopTarget, label: String) -> void:
	_suite.assert_equal(_atomic_stop_started_count, 0, "%s rejection publishes no Stop start" % label)
	_suite.assert_equal(_atomic_stop_ended_count, 0, "%s rejection publishes no Stop end" % label)
	_suite.assert_equal(_atomic_time_committed_count, 0, "%s rejection publishes no committed fact" % label)
	_suite.assert_equal(_atomic_energy_event_count, 0, "%s rejection publishes no energy event" % label)
	_suite.assert_equal(_atomic_cooldown_event_count, 0, "%s rejection publishes no cooldown event" % label)
	_suite.assert_equal(target.apply_calls, 0, "%s rejection never applies a Stop source" % label)
	_suite.assert_equal(target.clear_calls, 0, "%s rejection has no compensating target clear" % label)
	_suite.assert_equal(target.weakpoint_calls, 0, "%s rejection never applies a weakpoint" % label)
	_suite.assert_equal(target.applied_source_id, &"", "%s rejection applies no Stop source" % label)
	_suite.assert_close(target.applied_duration, -1.0, "%s rejection changes no Stop duration" % label)
	_suite.assert_close(target.weakpoint_duration, -1.0, "%s rejection applies no weakpoint duration" % label)
	_suite.assert_close(target.weakpoint_damage_bonus, -1.0, "%s rejection applies no weakpoint bonus" % label)


func _test_player_time_action_failure_restores_replay_prefix() -> void:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	var manager: Node = player.get_node("TimeManager")
	manager.set_process(false)
	var recorder: Node = player.get_node("RewindRecorder")
	recorder.set_process(false)
	add_child(player)
	await get_tree().process_frame
	player.reset_runtime_state()
	manager.energy_regen = 0.0
	manager.rewind_cost = 0.0
	manager.rewind_cooldown = 0.0
	for _frame: int in range(6):
		_suite.assert_true(player.advance_action_frame({}), "Replay-prefix fixture records Rewind history")
	_suite.assert_true(
		player.advance_action_frame({"weapon_primary": {"edge": &"pressed"}}),
		"Replay-prefix fixture records one nonempty Weapon intent"
	)
	player.cancel_transient_actions()
	var before: Dictionary = player.rewind_transaction_snapshot()
	_suite.assert_true(not before.is_empty(), "Replay-prefix fixture captures the Player outer transaction")
	_suite.assert_true(
		not (before.get("replay_events", []) as Array).is_empty(),
		"Player outer transaction includes the existing Replay event prefix"
	)
	recorder.set_restore_fault_for_test(&"after_action_install")
	_suite.assert_true(
		not player.try_action(&"time_rewind"),
		"injected Rewind participant fault rejects the TimeAction commit"
	)
	_suite.assert_equal(
		player.rewind_transaction_snapshot(),
		before,
		"failed TimeAction restores Player state, Replay prefix, capture sequence, baseline, and invalid reasons exactly"
	)
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_time_manager_accelerate_settlement_is_frozen() -> void:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	var manager: Node = player.get_node("TimeManager")
	manager.set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	add_child(player)
	await get_tree().process_frame
	player.reset_runtime_state()
	_suite.assert_true(player.configure_loadout({
		"weapon_id": "sword",
		"enabled_time_skills": ["rift", "accelerate"],
	}), "Accelerate settlement fixture configures its loadout")
	manager.energy_regen = 0.0
	manager.time_accelerate_cost = 12.0
	manager.time_accelerate_cost_multiplier = 1.5
	manager.time_accelerate_cooldown = 2.25
	manager.time_accelerate_duration = 0.75
	manager.time_accelerate_duration_bonus = 0.25
	manager.time_accelerate_multiplier = 1.2
	manager.time_accelerate_multiplier_bonus = 0.3
	var ticket: Dictionary = manager.prepare_time_action(
		301,
		7,
		0,
		player.current_run_id(),
		&"accelerate",
		{}
	)
	_suite.assert_true(not ticket.is_empty(), "Accelerate prepares its complete frozen settlement")
	manager.time_accelerate_cost = 999.0
	manager.time_accelerate_cost_multiplier = 999.0
	manager.time_accelerate_cooldown = 9.0
	manager.time_accelerate_duration = 9.0
	manager.time_accelerate_duration_bonus = 9.0
	manager.time_accelerate_multiplier = 9.0
	manager.time_accelerate_multiplier_bonus = 9.0
	var committed: Dictionary = manager.commit_time_action(ticket)
	_suite.assert_true(bool(committed.get("ok", false)), "Accelerate commits from frozen prepare values")
	_suite.assert_close(manager.energy, 82.0, "Accelerate spends its frozen multiplied cost")
	_suite.assert_equal(int((manager.get("_cooldown_frames") as Dictionary).get(&"time_accelerate", -1)), 135, "Accelerate installs frozen cooldown frames")
	_suite.assert_equal(int(manager.get("_time_accelerate_remaining_frames")), 60, "Accelerate installs frozen duration frames")
	_suite.assert_close(float(manager.get("_time_accelerate_multiplier_active")), 1.5, "Accelerate installs the frozen multiplier")
	_suite.assert_close(float(player.get("_time_acceleration_multiplier")), 1.5, "player movement receives the frozen acceleration multiplier")
	manager.cancel_all_time_effects(&"accelerate_settlement_cleanup")
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_time_manager_rift_settlement_is_frozen() -> void:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	var manager: Node = player.get_node("TimeManager")
	manager.set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	add_child(player)
	await get_tree().process_frame
	player.reset_runtime_state()
	_suite.assert_true(player.configure_loadout({
		"weapon_id": "sword",
		"enabled_time_skills": ["rift", "accelerate"],
	}), "Rift settlement fixture configures its loadout")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	manager.energy_regen = 0.0
	manager.time_rift_cost = 10.0
	manager.time_rift_cost_multiplier = 1.5
	manager.time_rift_cooldown = 1.5
	manager.time_rift_duration = 1.25
	manager.time_rift_duration_bonus = 0.25
	manager.time_rift_radius = 80.0
	manager.time_rift_radius_bonus = 12.0
	manager.time_rift_slow_multiplier = 0.6
	manager.time_rift_slow_bonus = 0.15
	var rift_position := Vector2(180.0, 96.0)
	var ticket: Dictionary = manager.prepare_time_action(
		401,
		9,
		0,
		player.current_run_id(),
		&"rift",
		{"position": rift_position}
	)
	_suite.assert_true(not ticket.is_empty(), "Rift prepares its complete world descriptor")
	manager.time_rift_cost = 999.0
	manager.time_rift_cost_multiplier = 999.0
	manager.time_rift_cooldown = 9.0
	manager.time_rift_duration = 9.0
	manager.time_rift_duration_bonus = 9.0
	manager.time_rift_radius = 9.0
	manager.time_rift_radius_bonus = 9.0
	manager.time_rift_slow_multiplier = 1.0
	manager.time_rift_slow_bonus = 0.0
	var committed: Dictionary = manager.commit_time_action(ticket)
	_suite.assert_true(bool(committed.get("ok", false)), "Rift commits from its frozen prepared descriptor")
	_suite.assert_close(manager.energy, 85.0, "Rift spends its frozen multiplied cost")
	_suite.assert_equal(int((manager.get("_cooldown_frames") as Dictionary).get(&"time_rift", -1)), 90, "Rift installs frozen cooldown frames")
	var active_rifts := manager.weapon_interaction_context().get("active_rifts", []) as Array
	_suite.assert_equal(active_rifts.size(), 1, "Rift commit publishes one interaction descriptor")
	var payload_descriptors := (
		authority.replay_snapshot().get("descriptors", []) as Array
	)
	_suite.assert_equal(payload_descriptors.size(), 1, "Rift commit publishes one authoritative payload descriptor")
	if not payload_descriptors.is_empty():
		var descriptor := payload_descriptors.front() as Dictionary
		_suite.assert_equal(descriptor.get("remaining_frames"), 90, "Rift descriptor keeps frozen duration frames")
		_suite.assert_equal((descriptor.get("geometry", {}) as Dictionary).get("center"), rift_position, "Rift descriptor keeps the prepared position")
		_suite.assert_close(float((descriptor.get("geometry", {}) as Dictionary).get("radius", -1.0)), 92.0, "Rift descriptor keeps frozen radius")
		_suite.assert_close(float((descriptor.get("parameters", {}) as Dictionary).get("slow_multiplier", -1.0)), 0.45, "Rift descriptor keeps frozen slow multiplier")
	player.reset_runtime_state()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _on_time_skill_committed(
	ability_id: StringName,
	token: int,
	generation: int,
	frame: int,
	run_id: StringName,
	context: Dictionary
) -> void:
	_committed_fact_count += 1
	_last_committed_fact = {
		"ability_id": ability_id,
		"token": token,
		"generation": generation,
		"frame": frame,
		"run_id": run_id,
		"context": context.duplicate(true),
	}


func _on_rewind_committed(transaction: Dictionary) -> void:
	_last_rewind_committed = transaction.duplicate(true)


func _on_atomic_time_skill_started(skill_id: StringName, _context: Dictionary) -> void:
	if skill_id == &"time_stop":
		_atomic_stop_started_count += 1


func _on_atomic_time_skill_ended(skill_id: StringName, _context: Dictionary) -> void:
	if skill_id == &"time_stop":
		_atomic_stop_ended_count += 1


func _on_atomic_time_skill_committed(
	ability_id: StringName,
	_token: int,
	_generation: int,
	_frame: int,
	_run_id: StringName,
	_context: Dictionary
) -> void:
	if ability_id == &"stop":
		_atomic_time_committed_count += 1


func _on_atomic_energy_changed(_current: float, _maximum: float) -> void:
	_atomic_energy_event_count += 1


func _on_atomic_cooldown_changed(skill_id: StringName, _remaining: float) -> void:
	if skill_id == &"time_stop":
		_atomic_cooldown_event_count += 1


func _snapshot(revision: int) -> Dictionary:
	return {
		"revision": revision,
		"energy": 100 - revision,
		"cooldowns": {
			"stop": revision,
			"rewind": revision + 1,
			"rift": revision + 2,
			"accelerate": revision + 3,
		},
		"active_rifts": [
			{
				"payload_id": "run:%d:rift" % revision,
				"center": Vector2(float(revision), float(revision + 1)),
			},
		],
	}
