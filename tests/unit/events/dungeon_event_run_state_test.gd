extends Node

const DungeonEventRunStateScript := preload(
	"res://scripts/events/dungeon_event_run_state.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const CONTENT_FINGERPRINT := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const OTHER_FINGERPRINT := "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
const ROOT_FIELDS: Array[String] = [
	"completed_transaction_ids", "content_fingerprint", "narrative_flags",
	"pending_encounter", "pending_reward", "pending_transaction", "resolved_outcomes",
	"revision", "schema_id", "schema_version", "seen_floor_event_keys",
	"seen_run_event_ids", "selected_event_by_node", "temporary_modifiers",
]
const ASSIGNMENT_FIELDS: Array[String] = [
	"event_id", "floor_id", "floor_index", "node_id", "option_id", "outcome_id",
	"outcome_key", "phase", "repeat_policy", "result_key", "transaction_id",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_configuration_and_repeat_policies(suite)
	_test_reward_state_machine_and_result_retention(suite)
	_test_pending_encounter_round_trip(suite)
	_test_stale_tampered_and_duplicate_rejection(suite)
	_test_pending_and_committed_rollback(suite)
	_test_receipt_capability_lifecycle(suite)
	_test_snapshot_restore_is_strict_and_atomic(suite)
	suite.finish(get_tree())


func _test_configuration_and_repeat_policies(suite) -> void:
	var state = DungeonEventRunStateScript.new()
	suite.assert_equal(state.snapshot(), {}, "unconfigured event state has no snapshot")
	var configured: Dictionary = state.configure(CONTENT_FINGERPRINT)
	suite.assert_true(bool(configured.get("ok", false)), "valid fingerprint configures event state")
	var empty_snapshot: Dictionary = state.snapshot()
	_assert_exact_fields(suite, empty_snapshot, ROOT_FIELDS, "root snapshot")
	suite.assert_equal(empty_snapshot["schema_id"], "planewalker.dungeon_event_state", "schema is stable")
	suite.assert_equal(empty_snapshot["schema_version"], 1, "schema version is stable")
	suite.assert_equal(empty_snapshot["revision"], 0, "new state starts at revision zero")
	suite.assert_equal(empty_snapshot["selected_event_by_node"], {}, "new state has no assignments")

	var once_run: Dictionary = state.assign_event(
		_assignment("floor_ruins_of_remnant", 0, "layer_02_a", "event_chronal_altar", "once_per_run"),
		0
	)
	suite.assert_true(bool(once_run.get("ok", false)), "once-per-run event opens")
	var first_node: Dictionary = state.snapshot()["selected_event_by_node"]["floor_ruins_of_remnant:layer_02_a"]
	_assert_exact_fields(suite, first_node, ASSIGNMENT_FIELDS, "stored assignment")
	suite.assert_equal(first_node["phase"], "open", "assignment transitions unassigned to open")
	suite.assert_equal(state.snapshot()["seen_run_event_ids"], ["event_chronal_altar"], "run history records assignment")
	suite.assert_equal(
		state.snapshot()["seen_floor_event_keys"],
		["floor_ruins_of_remnant:event_chronal_altar"],
		"floor history records assignment"
	)

	var before_once_run: Dictionary = state.snapshot()
	var repeated_run: Dictionary = state.assign_event(
		_assignment("floor_void_forest", 1, "layer_02_b", "event_chronal_altar", "once_per_run"),
		1
	)
	suite.assert_equal(repeated_run.get("code"), &"REPEAT_POLICY_BLOCKED", "once-per-run cannot repeat")
	suite.assert_equal(state.snapshot(), before_once_run, "blocked run repeat is atomic")

	suite.assert_true(bool(state.assign_event(
		_assignment("floor_void_forest", 1, "layer_02_a", "event_memory_mirror", "once_per_floor"),
		1
	).get("ok", false)), "once-per-floor event opens on first node")
	var before_floor_repeat: Dictionary = state.snapshot()
	var repeated_floor: Dictionary = state.assign_event(
		_assignment("floor_void_forest", 1, "layer_03_a", "event_memory_mirror", "once_per_floor"),
		2
	)
	suite.assert_equal(repeated_floor.get("code"), &"REPEAT_POLICY_BLOCKED", "once-per-floor blocks same floor")
	suite.assert_equal(state.snapshot(), before_floor_repeat, "blocked floor repeat is atomic")
	suite.assert_true(bool(state.assign_event(
		_assignment("floor_temporal_rift", 2, "layer_02_a", "event_memory_mirror", "once_per_floor"),
		2
	).get("ok", false)), "once-per-floor permits a later floor")

	suite.assert_true(bool(state.assign_event(
		_assignment("floor_temporal_rift", 2, "layer_03_a", "event_lost_journal", "repeatable"),
		3
	).get("ok", false)), "repeatable event opens once")
	suite.assert_true(bool(state.assign_event(
		_assignment("floor_eternal_forge", 3, "layer_02_a", "event_lost_journal", "repeatable"),
		4
	).get("ok", false)), "repeatable event opens again")
	suite.assert_equal(
		state.snapshot()["seen_run_event_ids"],
		["event_chronal_altar", "event_lost_journal", "event_memory_mirror"],
		"run history is unique and sorted"
	)


func _test_reward_state_machine_and_result_retention(suite) -> void:
	var state = _configured_state()
	var node_key := "floor_ruins_of_remnant:layer_02_a"
	suite.assert_true(bool(state.assign_event(
		_assignment("floor_ruins_of_remnant", 0, "layer_02_a", "event_chronal_altar", "once_per_run"),
		0
	).get("ok", false)), "reward fixture opens")
	var reserved: Dictionary = state.reserve_option(
		node_key,
		"tx_event_reward_001",
		"offer_blood",
		"outcome_blood_rare",
		"EVENT_CHRONAL_ALTAR_BLOOD_RARE_RESULT",
		1
	)
	suite.assert_true(bool(reserved.get("ok", false)), "open event reserves an option")
	var ticket: Dictionary = reserved.get("ticket", {})
	suite.assert_equal(_phase(state, node_key), "reserved", "reserve moves event to reserved")
	suite.assert_equal(state.snapshot()["pending_transaction"], ticket, "ticket is the persisted transaction")

	var pending: Dictionary = state.mark_pending_reward(ticket, {
		"continuation_id": "event_reward_001",
		"pool_id": "pool_launch_event_reward",
		"count": 3,
	})
	suite.assert_true(bool(pending.get("ok", false)), "reserved transaction enters pending reward")
	suite.assert_equal(_phase(state, node_key), "pending_reward", "reward phase is explicit")
	suite.assert_equal(
		state.snapshot()["pending_reward"]["continuation_id"],
		"event_reward_001",
		"pending reward survives in snapshot"
	)

	var resolved: Dictionary = state.resolve_option(ticket, {
		"result_key": "EVENT_CHRONAL_ALTAR_BLOOD_RARE_RESULT",
		"narrative_flags": {"accepted_chronal_blood": true},
		"temporary_modifiers": [{
			"modifier_id": "modifier_event_blood_haste",
			"duration_rooms": 3,
			"magnitude": 0.2,
			"source_transaction_id": "tx_event_reward_001",
		}],
	})
	suite.assert_true(bool(resolved.get("ok", false)), "pending reward resolves")
	suite.assert_equal(_phase(state, node_key), "resolved", "resolved result is retained")
	suite.assert_equal(state.snapshot()["pending_transaction"], {}, "resolve clears transaction")
	suite.assert_equal(state.snapshot()["pending_reward"], {}, "resolve clears pending reward")
	suite.assert_equal(state.snapshot()["completed_transaction_ids"], ["tx_event_reward_001"], "completion is recorded")
	suite.assert_equal(state.snapshot()["narrative_flags"], {"accepted_chronal_blood": true}, "flags commit with result")
	suite.assert_equal((state.snapshot()["resolved_outcomes"] as Array).size(), 1, "resolved outcome fact is retained")
	suite.assert_true(state.can_restore_snapshot(state.snapshot()), "resolved snapshot remains restorable")

	var dismissed: Dictionary = state.dismiss_result(node_key, 3)
	suite.assert_true(bool(dismissed.get("ok", false)), "resolved result dismisses")
	suite.assert_equal(_phase(state, node_key), "dismissed", "result enters dismissed phase")
	suite.assert_equal(
		state.snapshot()["selected_event_by_node"][node_key]["result_key"],
		"EVENT_CHRONAL_ALTAR_BLOOD_RARE_RESULT",
		"dismissal retains result key"
	)
	suite.assert_equal(state.snapshot()["resolved_outcomes"][0]["dismissed"], true, "fact records dismissal")
	suite.assert_true(state.can_restore_snapshot(state.snapshot()), "dismissed snapshot remains restorable")


func _test_pending_encounter_round_trip(suite) -> void:
	var source = _configured_state()
	var node_key := "floor_void_forest:layer_03_a"
	suite.assert_true(bool(source.assign_event(
		_assignment("floor_void_forest", 1, "layer_03_a", "event_sleeping_guardian", "once_per_floor"),
		0
	).get("ok", false)), "encounter fixture opens")
	var reserved: Dictionary = source.reserve_option(
		node_key,
		"tx_event_encounter_001",
		"wake_guardian",
		"outcome_guardian_awake",
		"EVENT_SLEEPING_GUARDIAN_AWAKE_RESULT",
		1
	)
	var ticket: Dictionary = reserved.get("ticket", {})
	suite.assert_true(bool(source.mark_pending_encounter(ticket, {
		"continuation_id": "event_encounter_001",
		"encounter_id": "encounter_profile_forest_adapter_v1",
	}).get("ok", false)), "reserved transaction enters pending encounter")
	var saved: Dictionary = source.snapshot()

	var restored = _configured_state()
	suite.assert_true(restored.can_restore_snapshot(saved), "pending encounter snapshot validates")
	suite.assert_true(restored.restore_snapshot(saved), "pending encounter snapshot restores")
	suite.assert_equal(restored.snapshot(), saved, "pending encounter round-trips byte-identically")
	suite.assert_equal(_phase(restored, node_key), "pending_encounter", "pending encounter phase restores")
	suite.assert_true(bool(restored.resolve_option(restored.snapshot()["pending_transaction"], {
		"result_key": "EVENT_SLEEPING_GUARDIAN_AWAKE_RESULT",
		"narrative_flags": {},
		"temporary_modifiers": [],
	}).get("ok", false)), "restored encounter resolves with persisted ticket")


func _test_stale_tampered_and_duplicate_rejection(suite) -> void:
	var state = _configured_state()
	var node_key := "floor_ruins_of_remnant:layer_02_a"
	suite.assert_true(bool(state.assign_event(
		_assignment("floor_ruins_of_remnant", 0, "layer_02_a", "event_cursed_pool", "once_per_run"),
		0
	).get("ok", false)), "rejection fixture opens")
	var before_stale: Dictionary = state.snapshot()
	var stale: Dictionary = state.reserve_option(
		node_key, "tx_event_stale", "drink", "outcome_drink", "EVENT_CURSED_POOL_DRINK_RESULT", 0
	)
	suite.assert_equal(stale.get("code"), &"STALE_REVISION", "stale reservation is rejected")
	suite.assert_equal(state.snapshot(), before_stale, "stale reservation is atomic")

	var reserved: Dictionary = state.reserve_option(
		node_key, "tx_event_tamper", "drink", "outcome_drink", "EVENT_CURSED_POOL_DRINK_RESULT", 1
	)
	var ticket: Dictionary = reserved.get("ticket", {})
	var before_tamper: Dictionary = state.snapshot()
	var tampered: Dictionary = ticket.duplicate(true)
	tampered["outcome_id"] = "outcome_forged"
	suite.assert_equal(
		state.mark_pending_reward(tampered, {
			"continuation_id": "event_reward_tamper",
			"pool_id": "pool_launch_event_reward",
			"count": 1,
		}).get("code"),
		&"TRANSACTION_STALE",
		"tampered ticket is rejected"
	)
	suite.assert_equal(state.snapshot(), before_tamper, "tampered ticket rejection is atomic")

	suite.assert_true(bool(state.resolve_option(ticket, {
		"result_key": "EVENT_CURSED_POOL_DRINK_RESULT",
		"narrative_flags": {},
		"temporary_modifiers": [],
	}).get("ok", false)), "tamper fixture resolves")
	var before_duplicate: Dictionary = state.snapshot()
	var second_node := _assignment("floor_void_forest", 1, "layer_02_a", "event_lost_journal", "repeatable")
	suite.assert_true(bool(state.assign_event(second_node, 3).get("ok", false)), "duplicate fixture second event opens")
	var before_duplicate_reserve: Dictionary = state.snapshot()
	var duplicate: Dictionary = state.reserve_option(
		"floor_void_forest:layer_02_a",
		"tx_event_tamper",
		"read",
		"outcome_read",
		"EVENT_LOST_JOURNAL_READ_RESULT",
		4
	)
	suite.assert_equal(duplicate.get("code"), &"DUPLICATE_TRANSACTION", "completed transaction ID cannot repeat")
	suite.assert_equal(state.snapshot(), before_duplicate_reserve, "duplicate rejection is atomic")
	suite.assert_true(before_duplicate != state.snapshot(), "fixture advanced only through the accepted assignment")


func _test_pending_and_committed_rollback(suite) -> void:
	var state = _configured_state()
	var node_key := "floor_temporal_rift:layer_02_a"
	suite.assert_true(bool(state.assign_event(
		_assignment("floor_temporal_rift", 2, "layer_02_a", "event_time_paradox", "repeatable"),
		0
	).get("ok", false)), "rollback fixture opens")
	var before_reserve: Dictionary = state.snapshot()
	var reserved: Dictionary = state.reserve_option(
		node_key,
		"tx_event_rollback_pending",
		"stabilize",
		"outcome_stable",
		"EVENT_TIME_PARADOX_STABLE_RESULT",
		1
	)
	var ticket: Dictionary = reserved.get("ticket", {})
	suite.assert_true(bool(state.mark_pending_encounter(ticket, {
		"continuation_id": "event_encounter_rollback",
		"encounter_id": "encounter_profile_rift_adapter_v1",
	}).get("ok", false)), "rollback fixture reaches pending encounter")
	var pending_rollback: Dictionary = state.rollback_transaction(ticket)
	suite.assert_true(bool(pending_rollback.get("ok", false)), "pending transaction rolls back")
	suite.assert_equal(state.snapshot(), before_reserve, "pending rollback restores byte-identical state")

	var second_reserve: Dictionary = state.reserve_option(
		node_key,
		"tx_event_rollback_commit",
		"stabilize",
		"outcome_stable",
		"EVENT_TIME_PARADOX_STABLE_RESULT",
		1
	)
	var committed: Dictionary = state.resolve_option(second_reserve.get("ticket", {}), {
		"result_key": "EVENT_TIME_PARADOX_STABLE_RESULT",
		"narrative_flags": {"stabilized_paradox": true},
		"temporary_modifiers": [],
	})
	suite.assert_true(bool(committed.get("ok", false)), "rollback fixture commits")
	var receipt: Dictionary = committed.get("receipt", {})
	var before_tampered_receipt: Dictionary = state.snapshot()
	var tampered_receipt: Dictionary = receipt.duplicate(true)
	var alternate_before: Dictionary = receipt["before"].duplicate(true)
	alternate_before["narrative_flags"] = {"forged_rollback_target": true}
	suite.assert_true(
		state.can_restore_snapshot(alternate_before),
		"tampered receipt fixture uses an otherwise legal before snapshot"
	)
	tampered_receipt["before"] = alternate_before.duplicate(true)
	tampered_receipt["ticket"]["before"] = alternate_before.duplicate(true)
	suite.assert_true(
		not bool(state.rollback_transaction(tampered_receipt).get("ok", false)),
		"receipt cannot substitute another legal rollback target"
	)
	suite.assert_equal(
		state.snapshot(),
		before_tampered_receipt,
		"tampered committed receipt leaves state byte-identical"
	)
	suite.assert_true(bool(state.rollback_transaction(receipt).get("ok", false)), "latest commit rolls back")
	suite.assert_equal(state.snapshot(), before_reserve, "committed rollback restores byte-identical state")
	suite.assert_true(not bool(state.rollback_transaction(receipt).get("ok", false)), "consumed receipt is stale")


func _test_receipt_capability_lifecycle(suite) -> void:
	var state = _configured_state()
	var node_key := "floor_void_throne:layer_02_a"
	suite.assert_true(bool(state.assign_event(
		_assignment("floor_void_throne", 4, "layer_02_a", "event_final_choice", "once_per_run"),
		0
	).get("ok", false)), "receipt lifecycle fixture opens")
	var reserved: Dictionary = state.reserve_option(
		node_key,
		"tx_event_receipt_lifecycle",
		"accept_truth",
		"outcome_truth",
		"EVENT_FINAL_CHOICE_TRUTH_RESULT",
		1
	)
	var committed: Dictionary = state.resolve_option(reserved.get("ticket", {}), {
		"result_key": "EVENT_FINAL_CHOICE_TRUTH_RESULT",
		"narrative_flags": {"accepted_final_truth": true},
		"temporary_modifiers": [],
	})
	suite.assert_true(bool(committed.get("ok", false)), "receipt lifecycle fixture commits")
	var receipt: Dictionary = committed.get("receipt", {})
	var resolved_snapshot: Dictionary = state.snapshot()

	suite.assert_true(bool(state.configure(CONTENT_FINGERPRINT).get("ok", false)), "reconfigure succeeds")
	var configured_snapshot: Dictionary = state.snapshot()
	suite.assert_true(
		not bool(state.rollback_transaction(receipt).get("ok", false)),
		"configure invalidates old committed receipt capability"
	)
	suite.assert_equal(state.snapshot(), configured_snapshot, "reconfigured state rejects old receipt atomically")

	suite.assert_true(state.restore_snapshot(resolved_snapshot), "resolved snapshot restores without receipt capability")
	var restored_snapshot: Dictionary = state.snapshot()
	suite.assert_true(
		not bool(state.rollback_transaction(receipt).get("ok", false)),
		"restore does not resurrect an old committed receipt capability"
	)
	suite.assert_equal(state.snapshot(), restored_snapshot, "restored state rejects old receipt atomically")


func _test_snapshot_restore_is_strict_and_atomic(suite) -> void:
	var source = _configured_state()
	suite.assert_true(bool(source.assign_event(
		_assignment("floor_eternal_forge", 3, "layer_02_a", "event_smiths_legacy", "once_per_floor"),
		0
	).get("ok", false)), "restore source opens")
	var reserved: Dictionary = source.reserve_option(
		"floor_eternal_forge:layer_02_a",
		"tx_event_restore",
		"honor_legacy",
		"outcome_forged",
		"EVENT_SMITHS_LEGACY_FORGED_RESULT",
		1
	)
	suite.assert_true(bool(source.mark_pending_reward(reserved.get("ticket", {}), {
		"continuation_id": "event_reward_restore",
		"pool_id": "pool_launch_event_reward",
		"count": 2,
	}).get("ok", false)), "restore source reaches pending reward")
	var saved: Dictionary = source.snapshot()

	var restored = _configured_state()
	suite.assert_true(restored.can_restore_snapshot(saved), "canonical snapshot validates")
	suite.assert_true(restored.restore_snapshot(saved), "canonical snapshot restores")
	suite.assert_equal(restored.snapshot(), saved, "canonical snapshot is byte-identical")
	var before: Dictionary = restored.snapshot()

	var corruptions: Array[Dictionary] = []
	var wrong_fingerprint := before.duplicate(true)
	wrong_fingerprint["content_fingerprint"] = OTHER_FINGERPRINT
	corruptions.append(wrong_fingerprint)
	var extra_root := before.duplicate(true)
	extra_root["unexpected"] = true
	corruptions.append(extra_root)
	var stale_revision := before.duplicate(true)
	stale_revision["pending_transaction"]["expected_revision"] = 99
	corruptions.append(stale_revision)
	var forged_before := before.duplicate(true)
	forged_before["pending_transaction"]["before"]["revision"] = 99
	corruptions.append(forged_before)
	var unsorted_completed := before.duplicate(true)
	unsorted_completed["completed_transaction_ids"] = ["tx_z", "tx_a"]
	corruptions.append(unsorted_completed)
	var inconsistent_phase := before.duplicate(true)
	inconsistent_phase["selected_event_by_node"]["floor_eternal_forge:layer_02_a"]["phase"] = "open"
	corruptions.append(inconsistent_phase)
	var impossible_revision := before.duplicate(true)
	impossible_revision["revision"] = 1
	corruptions.append(impossible_revision)
	var inflated_revision := before.duplicate(true)
	inflated_revision["revision"] = 999
	corruptions.append(inflated_revision)
	var both_pending := before.duplicate(true)
	both_pending["pending_encounter"] = {
		"continuation_id": "event_encounter_forged",
		"encounter_id": "encounter_profile_forge_adapter_v1",
		"event_id": "event_smiths_legacy",
		"node_key": "floor_eternal_forge:layer_02_a",
		"transaction_id": "tx_event_restore",
	}
	corruptions.append(both_pending)
	for corrupt: Dictionary in corruptions:
		suite.assert_true(not restored.can_restore_snapshot(corrupt), "corrupt snapshot fails validation")
		suite.assert_true(not restored.restore_snapshot(corrupt), "corrupt snapshot fails restore")
		suite.assert_equal(restored.snapshot(), before, "failed restore leaves state byte-identical")

	var wrong_authority = DungeonEventRunStateScript.new()
	suite.assert_true(bool(wrong_authority.configure(OTHER_FINGERPRINT).get("ok", false)), "other authority configures")
	suite.assert_true(not wrong_authority.can_restore_snapshot(before), "fingerprint drift fails closed")


func _configured_state():
	var state = DungeonEventRunStateScript.new()
	var configured: Dictionary = state.configure(CONTENT_FINGERPRINT)
	if not bool(configured.get("ok", false)):
		push_error("DungeonEventRunState fixture failed: %s" % str(configured))
	return state


func _assignment(
	floor_id: String,
	floor_index: int,
	node_id: String,
	event_id: String,
	repeat_policy: String
) -> Dictionary:
	return {
		"floor_id": floor_id,
		"floor_index": floor_index,
		"node_id": node_id,
		"event_id": event_id,
		"repeat_policy": repeat_policy,
	}


func _phase(state, node_key: String) -> String:
	return str(state.snapshot()["selected_event_by_node"][node_key]["phase"])


func _assert_exact_fields(suite, value: Dictionary, fields: Array[String], label: String) -> void:
	var actual: Array[String] = []
	for key: Variant in value.keys():
		actual.append(str(key))
	actual.sort()
	var expected := fields.duplicate()
	expected.sort()
	suite.assert_equal(actual, expected, "%s has exact fields" % label)
