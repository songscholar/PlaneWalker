extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const TICKET_REQUIRED_FIELDS: Array[String] = [
	"schema_version",
	"ticket_id",
	"owner_instance_id",
	"run_id",
	"history_revision",
	"participant_revision",
	"before",
	"target_snapshot",
	"target_hp",
	"fingerprint",
]
const RESTORE_FAULT_STAGES: Array[StringName] = [
	&"preflight_action",
	&"after_action_install",
	&"after_health_install",
	&"after_time_install",
	&"before_history_consume",
	&"after_history_consume",
	&"final_verification",
]


class RewindEventProbe:
	extends RefCounted

	var started_count: int = 0
	var ended_count: int = 0
	var committed_count: int = 0
	var committed_transactions: Array[Dictionary] = []


	func on_time_skill_started(skill_id: StringName, _context: Dictionary) -> void:
		if skill_id == &"time_rewind":
			started_count += 1


	func on_time_skill_ended(skill_id: StringName, _context: Dictionary) -> void:
		if skill_id == &"time_rewind":
			ended_count += 1


	func on_rewind_committed(transaction: Dictionary) -> void:
		committed_count += 1
		committed_transactions.append(transaction.duplicate(true))


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_prepare_is_pure_and_applies_irreversible_target_formula()
	await _test_prepare_rejects_invalid_or_terminal_state()
	await _test_ticket_integrity_and_single_use()
	await _test_participant_drift_rejects_without_installing()
	await _test_every_install_fault_rolls_back_exactly()
	await _test_success_commits_and_publishes_exactly_once()
	_suite.finish(get_tree())


func _test_prepare_is_pure_and_applies_irreversible_target_formula() -> void:
	var player: Node = await _spawn_player(&"rewind-prepare-run")
	var health: Node = player.get_node("HealthComponent")
	var manager: Node = player.get_node("TimeManager")
	var recorder: Node = player.get_node("RewindRecorder")

	health.max_hp = 140.0
	health.current_hp = 120.0
	player.global_position = Vector2(16.0, 32.0)
	player.velocity = Vector2(3.0, -2.0)
	player.restore_rewind_facing(Vector2.UP)
	recorder.clear_snapshots()
	recorder._record_snapshot()

	var loss_resolution: RefCounted = health.lose_health_irreversible(
		32.0,
		&"void_devour",
		7,
		3
	)
	_suite.assert_true(loss_resolution != null, "irreversible target fixture records one loss")
	health.heal(22.0)
	player.global_position = Vector2(240.0, 176.0)
	player.velocity = Vector2(-8.0, 5.0)
	player.restore_rewind_facing(Vector2.LEFT)
	manager.energy = 91.0
	manager.rewind_cost = 0.0
	manager.rewind_cooldown = 0.0
	manager.rewind_self_damage = 0.0
	manager.rewind_heal = 0.0
	_suite.assert_true(
		int(player.action_state.snapshot().get("current_state", 0)) != 0,
		"prepare-purity fixture owns a live non-free action state"
	)

	var before := _complete_runtime_snapshot(player)
	var ticket: Dictionary = recorder.prepare_rewind_transaction()
	_suite.assert_true(not ticket.is_empty(), "valid rewind prepare returns a ticket")
	_assert_ticket_shape(ticket, recorder, &"rewind-prepare-run")
	_suite.assert_true(
		_complete_runtime_snapshot(player) == before,
		"prepare has zero player, health, action, time, ledger, or history side effects"
	)
	_suite.assert_close(
		float(ticket.get("target_hp", -1.0)),
		88.0,
		"target hp subtracts irreversible loss since the snapshot"
	)
	_suite.assert_close(
		float((ticket.get("target_snapshot", {}) as Dictionary).get("hp", -1.0)),
		120.0,
		"ticket preserves the captured snapshot hp separately from projected target hp"
	)

	_suite.assert_true(
		recorder.commit_rewind_transaction(ticket),
		"the prepared ticket commits once"
	)
	_suite.assert_close(health.current_hp, 88.0, "direct commit installs the projected target hp")
	_suite.assert_equal(player.global_position, Vector2(16.0, 32.0), "direct commit installs target position")
	_suite.assert_true(
		not recorder.commit_rewind_transaction(ticket),
		"a committed ticket rejects duplicate commit"
	)
	var rollback_after_commit: Dictionary = recorder.rollback_rewind_transaction(ticket)
	_suite.assert_true(
		not bool(rollback_after_commit.get("ok", false)),
		"a committed ticket rejects rollback"
	)

	await _free_player(player)


func _test_prepare_rejects_invalid_or_terminal_state() -> void:
	var player: Node = await _spawn_player(&"rewind-invalid-run")
	var health: Node = player.get_node("HealthComponent")
	var recorder: Node = player.get_node("RewindRecorder")
	player.global_position = Vector2(24.0, 48.0)
	recorder.clear_snapshots()
	recorder._record_snapshot()
	var valid_snapshot: Dictionary = recorder.peek_oldest_snapshot()

	var run_mismatch := valid_snapshot.duplicate(true)
	run_mismatch["run_id"] = "foreign-run"
	recorder._snapshots[0] = run_mismatch
	_assert_rejected_prepare_is_pure(player, "run-id mismatch is rejected")

	var revision_regression := valid_snapshot.duplicate(true)
	revision_regression["irreversible_hp_loss_revision"] = 1
	recorder._snapshots[0] = revision_regression
	_assert_rejected_prepare_is_pure(player, "ledger revision regression is rejected")

	var negative_delta := valid_snapshot.duplicate(true)
	negative_delta["irreversible_hp_loss_total"] = 1.0
	recorder._snapshots[0] = negative_delta
	_assert_rejected_prepare_is_pure(player, "negative irreversible-loss delta is rejected")

	var non_finite_hp := valid_snapshot.duplicate(true)
	non_finite_hp["hp"] = NAN
	recorder._snapshots[0] = non_finite_hp
	_assert_rejected_prepare_is_pure(player, "non-finite snapshot hp is rejected", false)
	_suite.assert_true(is_nan(float(recorder._snapshots[0]["hp"])), "rejected non-finite hp remains unmodified")

	var non_finite_loss := valid_snapshot.duplicate(true)
	non_finite_loss["irreversible_hp_loss_total"] = NAN
	recorder._snapshots[0] = non_finite_loss
	_assert_rejected_prepare_is_pure(player, "non-finite irreversible total is rejected", false)
	_suite.assert_true(
		is_nan(float(recorder._snapshots[0]["irreversible_hp_loss_total"])),
		"rejected non-finite irreversible total remains unmodified"
	)

	recorder._snapshots[0] = valid_snapshot.duplicate(true)
	health.lose_health(health.current_hp, &"terminal_fixture")
	_suite.assert_true(health.dead, "terminal rewind fixture is dead")
	_assert_rejected_prepare_is_pure(player, "terminal state cannot prepare a rewind revival")

	await _free_player(player)


func _test_ticket_integrity_and_single_use() -> void:
	var tamper_player: Node = await _spawn_player(&"rewind-tamper-run")
	var tamper_recorder: Node = tamper_player.get_node("RewindRecorder")
	_record_distinct_destination(tamper_player)
	var tamper_ticket: Dictionary = tamper_recorder.prepare_rewind_transaction()
	var before_tamper_attempt := _complete_runtime_snapshot(tamper_player)
	var forged_ticket := tamper_ticket.duplicate(true)
	forged_ticket["target_hp"] = float(forged_ticket.get("target_hp", 0.0)) + 1.0
	_suite.assert_true(
		not tamper_recorder.commit_rewind_transaction(forged_ticket),
		"fingerprint rejects a modified ticket"
	)
	_suite.assert_true(
		_complete_runtime_snapshot(tamper_player) == before_tamper_attempt,
		"tampered ticket rejection is side-effect free"
	)
	var tamper_cleanup: Dictionary = tamper_recorder.rollback_rewind_transaction(tamper_ticket)
	_suite.assert_true(
		bool(tamper_cleanup.get("ok", false)),
		"rejecting a forged copy does not consume the authentic ticket"
	)
	await _free_player(tamper_player)

	var owner_player: Node = await _spawn_player(&"rewind-owner-run")
	var foreign_player: Node = await _spawn_player(&"rewind-foreign-run")
	var owner_recorder: Node = owner_player.get_node("RewindRecorder")
	var foreign_recorder: Node = foreign_player.get_node("RewindRecorder")
	_record_distinct_destination(owner_player)
	_record_distinct_destination(foreign_player)
	var owner_ticket: Dictionary = owner_recorder.prepare_rewind_transaction()
	var foreign_before := _complete_runtime_snapshot(foreign_player)
	_suite.assert_true(
		not foreign_recorder.commit_rewind_transaction(owner_ticket),
		"foreign recorder rejects another owner's ticket"
	)
	_suite.assert_true(
		_complete_runtime_snapshot(foreign_player) == foreign_before,
		"foreign ticket rejection cannot mutate the receiving runtime"
	)
	var foreign_rollback: Dictionary = foreign_recorder.rollback_rewind_transaction(owner_ticket)
	_suite.assert_true(
		not bool(foreign_rollback.get("ok", false)),
		"foreign recorder also rejects rollback"
	)
	var owner_cleanup: Dictionary = owner_recorder.rollback_rewind_transaction(owner_ticket)
	_suite.assert_true(bool(owner_cleanup.get("ok", false)), "ticket owner can still roll back after foreign rejection")
	await _free_player(owner_player)
	await _free_player(foreign_player)

	var stale_player: Node = await _spawn_player(&"rewind-stale-run")
	var stale_recorder: Node = stale_player.get_node("RewindRecorder")
	_record_distinct_destination(stale_player)
	var stale_ticket: Dictionary = stale_recorder.prepare_rewind_transaction()
	stale_recorder._record_snapshot()
	var state_after_history_drift := _complete_runtime_snapshot(stale_player)
	_suite.assert_true(
		not stale_recorder.commit_rewind_transaction(stale_ticket),
		"history revision drift makes a prepared ticket stale"
	)
	_suite.assert_true(
		_complete_runtime_snapshot(stale_player) == state_after_history_drift,
		"stale commit rejection preserves the newer history"
	)
	var stale_rollback: Dictionary = stale_recorder.rollback_rewind_transaction(stale_ticket)
	_suite.assert_true(
		not bool(stale_rollback.get("ok", false)),
		"stale ticket rejects rollback instead of erasing newer history"
	)
	await _free_player(stale_player)

	var rollback_player: Node = await _spawn_player(&"rewind-double-rollback-run")
	var rollback_recorder: Node = rollback_player.get_node("RewindRecorder")
	_record_distinct_destination(rollback_player)
	var rollback_ticket: Dictionary = rollback_recorder.prepare_rewind_transaction()
	var rollback_before := _complete_runtime_snapshot(rollback_player)
	var first_rollback: Dictionary = rollback_recorder.rollback_rewind_transaction(rollback_ticket)
	_suite.assert_true(bool(first_rollback.get("ok", false)), "prepared ticket rolls back once")
	_suite.assert_true(
		_complete_runtime_snapshot(rollback_player) == rollback_before,
		"rollback of an uninstalled ticket preserves its exact frozen before state"
	)
	var second_rollback: Dictionary = rollback_recorder.rollback_rewind_transaction(rollback_ticket)
	_suite.assert_true(
		not bool(second_rollback.get("ok", false)),
		"rolled-back ticket rejects duplicate rollback"
	)
	_suite.assert_true(
		not rollback_recorder.commit_rewind_transaction(rollback_ticket),
		"rolled-back ticket also rejects later commit"
	)
	await _free_player(rollback_player)


func _test_participant_drift_rejects_without_installing() -> void:
	var player: Node = await _spawn_player(&"rewind-participant-drift-run")
	var recorder: Node = player.get_node("RewindRecorder")
	_record_distinct_destination(player)
	var ticket: Dictionary = recorder.prepare_rewind_transaction()
	_suite.assert_true(not ticket.is_empty(), "participant-drift fixture prepares a ticket")
	_suite.assert_true(
		player.action_state.has_method("snapshot") and player.action_state.has_method("revision"),
		"PlayerActionState exposes transactional snapshot and revision authority"
	)
	player.action_state.buffer_input(&"dash")
	var drifted_state := _complete_runtime_snapshot(player)
	_suite.assert_true(
		not recorder.commit_rewind_transaction(ticket),
		"participant revision drift rejects commit before any install"
	)
	_suite.assert_true(
		_complete_runtime_snapshot(player) == drifted_state,
		"participant drift rejection preserves the participant's newer state"
	)

	await _free_player(player)

	var healing_player: Node = await _spawn_player(&"rewind-healing-drift-run")
	var healing_health: Node = healing_player.get_node("HealthComponent")
	var healing_recorder: Node = healing_player.get_node("RewindRecorder")
	_record_distinct_destination(healing_player)
	var healing_ticket: Dictionary = healing_recorder.prepare_rewind_transaction()
	_suite.assert_true(not healing_ticket.is_empty(), "healing-drift fixture prepares a ticket")
	healing_health.healing_multiplier = 1.75
	var healing_drifted_state := _complete_runtime_snapshot(healing_player)
	_suite.assert_true(
		not healing_recorder.commit_rewind_transaction(healing_ticket),
		"healing multiplier drift rejects commit before health installation"
	)
	_suite.assert_true(
		_complete_runtime_snapshot(healing_player) == healing_drifted_state,
		"healing multiplier drift preserves the newer health policy"
	)

	await _free_player(healing_player)


func _test_every_install_fault_rolls_back_exactly() -> void:
	for stage: StringName in RESTORE_FAULT_STAGES:
		var player: Node = await _spawn_player(StringName("rewind-fault-%s" % str(stage)))
		var health: Node = player.get_node("HealthComponent")
		var manager: Node = player.get_node("TimeManager")
		var recorder: Node = player.get_node("RewindRecorder")

		health.max_hp = 120.0
		health.current_hp = 110.0
		player.global_position = Vector2(12.0, 28.0)
		player.velocity = Vector2(1.0, 2.0)
		player.restore_rewind_facing(Vector2.UP)
		recorder.clear_snapshots()
		recorder._record_snapshot()
		player.global_position = Vector2(24.0, 36.0)
		recorder._record_snapshot()

		player.global_position = Vector2(220.0, 164.0)
		player.velocity = Vector2(-4.0, 7.0)
		player.restore_rewind_facing(Vector2.LEFT)
		health.current_hp = 67.0
		health.lose_health_irreversible(9.0, &"rewind_fault_loss", 17, 4)
		health.heal(5.0)
		manager.energy = 88.0
		manager._cooldowns[&"time_stop"] = 3.25
		manager.rewind_cost = 31.0
		manager.rewind_self_damage = 6.0
		manager.rewind_heal = 4.0
		_suite.assert_true(
			int(player.action_state.snapshot().get("current_state", 0)) != 0,
			"%s fixture owns a live non-free action state" % stage
		)
		var before := _complete_runtime_snapshot(player)
		var probe := RewindEventProbe.new()
		_connect_probe(manager, probe)

		_suite.assert_true(
			recorder.has_method("set_restore_fault_for_test"),
			"RewindRecorder exposes deterministic restore fault injection"
		)
		if recorder.has_method("set_restore_fault_for_test"):
			recorder.call("set_restore_fault_for_test", stage)
			_suite.assert_true(
				not manager.try_rewind(recorder),
				"%s install fault rejects the rewind" % stage
			)
			_suite.assert_true(
				_complete_runtime_snapshot(player) == before,
				"%s install fault restores position, velocity, facing, hp, dead, action, history, energy, cooldown, and ledger exactly" % stage
			)
			_assert_probe_counts(probe, 0, "%s failed rewind" % stage)

		_disconnect_probe(manager, probe)
		await _free_player(player)


func _test_success_commits_and_publishes_exactly_once() -> void:
	var player: Node = await _spawn_player(&"rewind-success-run")
	var health: Node = player.get_node("HealthComponent")
	var manager: Node = player.get_node("TimeManager")
	var recorder: Node = player.get_node("RewindRecorder")

	player.global_position = Vector2(48.0, 72.0)
	player.velocity = Vector2(12.0, -4.0)
	player.restore_rewind_facing(Vector2.UP)
	health.current_hp = 80.0
	recorder.clear_snapshots()
	recorder._record_snapshot()
	player.global_position = Vector2(56.0, 80.0)
	recorder._record_snapshot()
	var oldest_snapshot: Dictionary = recorder.peek_oldest_snapshot()
	_suite.assert_true(not oldest_snapshot.has("energy"), "rewind snapshot excludes energy")
	_suite.assert_true(not oldest_snapshot.has("cooldowns"), "rewind snapshot excludes cooldowns")
	_suite.assert_equal(str(oldest_snapshot.get("run_id", "")), "rewind-success-run", "snapshot carries authoritative run identity")

	player.global_position = Vector2(260.0, 180.0)
	player.velocity = Vector2.ZERO
	player.restore_rewind_facing(Vector2.RIGHT)
	health.current_hp = 25.0
	manager.energy = 90.0
	manager.rewind_cost = 45.0
	manager.rewind_self_damage = 18.0
	manager.rewind_heal = 28.0
	var probe := RewindEventProbe.new()
	_connect_probe(manager, probe)

	_suite.assert_true(manager.try_rewind(recorder), "valid rewind succeeds")
	_suite.assert_equal(player.global_position, Vector2(48.0, 72.0), "successful rewind restores player position")
	_suite.assert_equal(player.velocity, Vector2(12.0, -4.0), "successful rewind restores player velocity")
	_suite.assert_equal(player.get_rewind_facing(), Vector2.UP, "successful rewind restores player facing")
	_suite.assert_close(health.current_hp, 90.0, "successful rewind restores hp, applies self-cost, then healing")
	_suite.assert_close(manager.energy, 45.0, "successful rewind pays cost from current energy")
	_suite.assert_close(manager.get_cooldown(&"time_rewind"), manager.rewind_cooldown, "successful rewind starts cooldown once")
	_suite.assert_true(not recorder.has_snapshot(), "successful rewind consumes the invalidated timeline")
	_suite.assert_equal(
		health.hp_loss_state(),
		{"irreversible_hp_loss_total": 18.0, "revision": 1},
		"successful rewind cannot refund its irreversible self-cost"
	)
	_assert_probe_counts(probe, 1, "successful rewind")
	_suite.assert_equal(probe.committed_transactions.size(), 1, "successful rewind publishes one frozen transaction")

	var state_after_success := _complete_runtime_snapshot(player)
	_suite.assert_true(not manager.try_rewind(recorder), "empty rewind rejects a second commit")
	_suite.assert_true(
		_complete_runtime_snapshot(player) == state_after_success,
		"rejected second rewind has no state side effects"
	)
	_assert_probe_counts(probe, 1, "rejected second rewind")

	_disconnect_probe(manager, probe)
	await _free_player(player)


func _spawn_player(run_id: StringName) -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	_suite.assert_true(player.configure_run(run_id), "%s installs one authoritative run" % run_id)
	_suite.assert_equal(
		str(player.get_node("RewindRecorder").current_run_id()),
		str(run_id),
		"Player injects the same run identity into Rewind"
	)
	return player


func _free_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	var health: Node = player.get_node_or_null("HealthComponent")
	if (
		health != null
		and not (health._active_invulnerability_tokens as Dictionary).is_empty()
	):
		await get_tree().create_timer(0.55).timeout
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _record_distinct_destination(player: Node) -> void:
	var health: Node = player.get_node("HealthComponent")
	var recorder: Node = player.get_node("RewindRecorder")
	recorder.clear_snapshots()
	player.global_position = Vector2(12.0, 24.0)
	player.velocity = Vector2(2.0, -1.0)
	health.current_hp = 83.0
	recorder._record_snapshot()
	player.global_position = Vector2(212.0, 144.0)
	player.velocity = Vector2(-6.0, 3.0)
	health.current_hp = 51.0


func _assert_rejected_prepare_is_pure(
	player: Node,
	label: String,
	compare_history: bool = true
) -> void:
	var recorder: Node = player.get_node("RewindRecorder")
	var before := _complete_runtime_snapshot(player)
	_suite.assert_true(recorder.prepare_rewind_transaction().is_empty(), label)
	var after := _complete_runtime_snapshot(player)
	if not compare_history:
		var before_history: Array = before.get("history", [])
		var after_history: Array = after.get("history", [])
		before.erase("history")
		after.erase("history")
		_suite.assert_equal(after_history.size(), before_history.size(), "%s preserves history size" % label)
	_suite.assert_true(after == before, "%s without mutation" % label)


func _assert_ticket_shape(ticket: Dictionary, recorder: Node, run_id: StringName) -> void:
	for field: String in TICKET_REQUIRED_FIELDS:
		_suite.assert_true(ticket.has(field), "rewind ticket includes %s" % field)
	_suite.assert_true(int(ticket.get("schema_version", 0)) > 0, "rewind ticket has a positive schema version")
	_suite.assert_true(int(ticket.get("ticket_id", 0)) > 0, "rewind ticket has a positive stable id")
	_suite.assert_equal(
		int(ticket.get("owner_instance_id", 0)),
		recorder.get_instance_id(),
		"rewind ticket binds to its recorder owner"
	)
	_suite.assert_equal(str(ticket.get("run_id", "")), str(run_id), "rewind ticket binds to its run")
	_suite.assert_true(int(ticket.get("history_revision", -1)) >= 0, "rewind ticket freezes history revision")
	_suite.assert_true(ticket.get("participant_revision") is Dictionary, "rewind ticket freezes participant revisions")
	_suite.assert_true(ticket.get("before") is Dictionary, "rewind ticket freezes complete before state")
	_suite.assert_true(ticket.get("target_snapshot") is Dictionary, "rewind ticket freezes target snapshot")
	_suite.assert_true(is_finite(float(ticket.get("target_hp", NAN))), "rewind ticket target hp is finite")
	_suite.assert_true(_is_sha256(ticket.get("fingerprint", "")), "rewind ticket carries a sha-256 fingerprint")


func _complete_runtime_snapshot(player: Node) -> Dictionary:
	var health: Node = player.get_node("HealthComponent")
	var manager: Node = player.get_node("TimeManager")
	var recorder: Node = player.get_node("RewindRecorder")
	var action_snapshot: Dictionary = (
		(player.action_state.call("snapshot") as Dictionary).duplicate(true)
		if player.action_state.has_method("snapshot")
		else {"missing_transaction_snapshot": true}
	)
	var coordinator_snapshot: Dictionary = (
		(player.weapon_action_coordinator.call("gameplay_rewind_snapshot") as Dictionary).duplicate(true)
		if player.weapon_action_coordinator.has_method("gameplay_rewind_snapshot")
		else player.weapon_action_coordinator.snapshot().duplicate(true)
	)
	var player_transaction: Dictionary = (
		(player.call("rewind_transaction_snapshot") as Dictionary).duplicate(true)
		if player.has_method("rewind_transaction_snapshot")
		else {}
	)
	var health_runtime: Dictionary = (
		(health.call("runtime_state_snapshot") as Dictionary).duplicate(true)
		if health.has_method("runtime_state_snapshot")
		else {}
	)
	var time_transaction: Dictionary = (
		(manager.call("gameplay_rewind_transaction_snapshot") as Dictionary).duplicate(true)
		if manager.has_method("gameplay_rewind_transaction_snapshot")
		else {}
	)
	return {
		"position": player.global_position,
		"velocity": player.velocity,
		"facing": player.get_rewind_facing(),
		"hp": health.current_hp,
		"dead": health.dead,
		"safe_action": player.get_rewind_safe_action_state().duplicate(true),
		"action_state": action_snapshot,
		"coordinator": coordinator_snapshot,
		"player_transaction": player_transaction,
		"health_runtime": health_runtime,
		"time_transaction": time_transaction,
		"history": _snapshot_history(recorder),
		"energy": manager.energy,
		"cooldowns": manager._cooldowns.duplicate(true),
		"time_replay_state": manager.weapon_replay_snapshot().duplicate(true),
		"ledger": health.irreversible_ledger_snapshot().duplicate(true),
	}


func _snapshot_history(recorder: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for snapshot: Dictionary in recorder._snapshots:
		result.append(snapshot.duplicate(true))
	return result


func _connect_probe(manager: Node, probe: RewindEventProbe) -> void:
	EventBus.time_skill_started.connect(probe.on_time_skill_started)
	EventBus.time_skill_ended.connect(probe.on_time_skill_ended)
	manager.rewind_committed.connect(probe.on_rewind_committed)


func _disconnect_probe(manager: Node, probe: RewindEventProbe) -> void:
	if EventBus.time_skill_started.is_connected(probe.on_time_skill_started):
		EventBus.time_skill_started.disconnect(probe.on_time_skill_started)
	if EventBus.time_skill_ended.is_connected(probe.on_time_skill_ended):
		EventBus.time_skill_ended.disconnect(probe.on_time_skill_ended)
	if manager.rewind_committed.is_connected(probe.on_rewind_committed):
		manager.rewind_committed.disconnect(probe.on_rewind_committed)


func _assert_probe_counts(probe: RewindEventProbe, expected: int, label: String) -> void:
	_suite.assert_equal(probe.started_count, expected, "%s publishes start exactly %d time(s)" % [label, expected])
	_suite.assert_equal(probe.ended_count, expected, "%s publishes end exactly %d time(s)" % [label, expected])
	_suite.assert_equal(probe.committed_count, expected, "%s publishes commit exactly %d time(s)" % [label, expected])


func _is_sha256(value: Variant) -> bool:
	var text := str(value)
	if text.length() != 64:
		return false
	for index: int in range(text.length()):
		var code := text.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true
