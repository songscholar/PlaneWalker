extends Node

const AuthorityScript := preload("res://scripts/combat/world_payload_authority.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class PayloadFactory:
	extends RefCounted

	var fail_on_source_token: int = -1
	var reject_frame_for_source_token: int = -1
	var created_nodes: Array[Node] = []

	func create_payload(descriptor: Dictionary) -> Variant:
		if int(descriptor.get("source_token", -1)) == fail_on_source_token:
			return null
		var node := FramePayload.new()
		node.name = "Payload_%s" % str(descriptor.get("payload_family", "unknown"))
		node.set_meta("factory_payload_id", str(descriptor.get("payload_id", "")))
		if int(descriptor.get("source_token", -1)) == reject_frame_for_source_token:
			node.reject_runtime_frame = 0
		created_nodes.append(node)
		return node


class FramePayload:
	extends Node2D

	var last_runtime_frame: int = 0
	var advance_calls: int = 0
	var reject_runtime_frame: int = -1

	func advance_frame(runtime_frame: int) -> bool:
		last_runtime_frame = runtime_frame
		advance_calls += 1
		return runtime_frame != reject_runtime_frame

	func world_payload_frame_snapshot() -> Dictionary:
		return {
			"last_runtime_frame": last_runtime_frame,
			"advance_calls": advance_calls,
		}

	func restore_world_payload_frame_snapshot(value: Dictionary) -> bool:
		if (
			value.size() != 2
			or typeof(value.get("last_runtime_frame")) != TYPE_INT
			or typeof(value.get("advance_calls")) != TYPE_INT
		):
			return false
		last_runtime_frame = int(value["last_runtime_frame"])
		advance_calls = int(value["advance_calls"])
		return world_payload_frame_snapshot() == value


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_factory_registration_and_stable_commit()
	_test_descriptor_validation_is_strict_and_atomic()
	_test_commit_factory_failure_is_atomic()
	_test_gameplay_rewind_preserves_descriptor_and_node_identity()
	_test_time_action_transaction_restore_preserves_existing_node_identity()
	_test_staged_transaction_restore_can_rollback_with_exact_node_identity()
	_test_staged_transaction_restore_commits_exactly_once()
	_test_fixed_frame_lifetime_is_deterministic()
	_test_payload_frame_rejection_rolls_back_every_node_and_descriptor()
	_test_frame_transaction_rollback_restores_exact_payload_state()
	_test_frame_transaction_expiry_is_deferred_until_commit()
	_test_frame_transaction_tracks_added_payloads()
	_test_frame_transaction_rolls_back_added_payload_that_expires()
	_test_frame_transaction_tickets_and_restore_are_fail_closed()
	_test_frame_transaction_preflight_is_pure_and_freezes_commit()
	_test_replay_snapshot_is_complete_sorted_and_reconstructable()
	_test_failed_replay_restore_preserves_exact_live_set()
	_test_generation_invalidation_is_exact_and_permanent()
	_test_generation_invalidation_watermark_is_bounded_and_permanent()
	_test_generation_reset_preflight_is_pure_and_lock_aware()
	_test_replay_restore_cannot_cross_invalidation_boundary()
	_test_cold_restore_rebases_matching_invalidation_history()
	_suite.finish(get_tree())


func _test_factory_registration_and_stable_commit() -> void:
	var authority = AuthorityScript.new()
	add_child(authority)
	var factory := PayloadFactory.new()
	_suite.assert_true(
		not authority.register_factory(&"", Callable(factory, "create_payload")),
		"empty handler identity is rejected"
	)
	_suite.assert_true(
		not authority.register_factory(&"time_rift", Callable()),
		"invalid factory callable is rejected"
	)
	_suite.assert_true(
		authority.register_factory(&"time_rift", Callable(factory, "create_payload")),
		"valid factory registers once"
	)
	_suite.assert_true(
		not authority.register_factory(&"time_rift", Callable(factory, "create_payload")),
		"duplicate factory registration is rejected"
	)

	var descriptor := _descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 120)
	var committed: Dictionary = authority.commit_payload(descriptor)
	_suite.assert_true(bool(committed.get("ok", false)), "fully valid descriptor commits")
	_suite.assert_equal(
		committed.get("payload_id"),
		"run-a:3:rift:8:1",
		"commit returns the canonical five-part stable payload identity"
	)
	_suite.assert_true(authority.contains(&"run-a:3:rift:8:1"), "contains observes committed stable identity")
	var committed_node: Node = authority.payload_node(&"run-a:3:rift:8:1")
	_suite.assert_true(is_instance_valid(committed_node), "commit installs the factory-produced node")
	_suite.assert_true(committed_node.get_parent() != null, "committed payload joins the authority-owned active root")
	_suite.assert_equal(
		str(committed_node.get_meta("world_payload_id", "")),
		"run-a:3:rift:8:1",
		"installed node carries its stable authority identity"
	)
	authority.queue_free()


func _test_descriptor_validation_is_strict_and_atomic() -> void:
	var authority = _authority_with_factory(&"time_rift")
	var valid := _descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 120)
	var malformed_cases: Array[Dictionary] = []
	var unknown_field := valid.duplicate(true)
	unknown_field["presentation_node"] = true
	malformed_cases.append(unknown_field)
	var wrong_id := valid.duplicate(true)
	wrong_id["payload_id"] = "run-a:3:rift:8:2"
	malformed_cases.append(wrong_id)
	var missing_field := valid.duplicate(true)
	missing_field.erase("geometry")
	malformed_cases.append(missing_field)
	var duplicate_claim := valid.duplicate(true)
	duplicate_claim["claims"] = ["enemy:a", "enemy:a"]
	malformed_cases.append(duplicate_claim)
	var recursive_tag := valid.duplicate(true)
	recursive_tag["tags"] = [["world_owned"]]
	malformed_cases.append(recursive_tag)
	var invalid_transform := valid.duplicate(true)
	invalid_transform["transform"] = Transform2D(Vector2(INF, 0.0), Vector2.DOWN, Vector2.ZERO)
	malformed_cases.append(invalid_transform)
	var nondeterministic_parameter := valid.duplicate(true)
	nondeterministic_parameter["parameters"] = {"presentation": Callable(self, "queue_free")}
	malformed_cases.append(nondeterministic_parameter)
	var zero_lifetime := valid.duplicate(true)
	zero_lifetime["remaining_frames"] = 0
	malformed_cases.append(zero_lifetime)

	var before: Dictionary = authority.replay_snapshot()
	for index: int in range(malformed_cases.size()):
		var result: Dictionary = authority.commit_payload(malformed_cases[index])
		_suite.assert_true(not bool(result.get("ok", true)), "malformed descriptor %d fails closed" % index)
		_suite.assert_equal(authority.replay_snapshot(), before, "malformed descriptor %d has no side effect" % index)

	var unknown_handler := valid.duplicate(true)
	unknown_handler["handler_id"] = &"missing_handler"
	var rejected: Dictionary = authority.commit_payload(unknown_handler)
	_suite.assert_equal(rejected.get("code"), &"UNKNOWN_HANDLER", "unknown handler has a stable refusal code")
	_suite.assert_equal(authority.replay_snapshot(), before, "unknown factory cannot mutate authority state")
	authority.queue_free()


func _test_commit_factory_failure_is_atomic() -> void:
	var authority = AuthorityScript.new()
	add_child(authority)
	var factory := PayloadFactory.new()
	factory.fail_on_source_token = 9
	_suite.assert_true(authority.register_factory(&"time_rift", Callable(factory, "create_payload")), "failing factory fixture registers")
	var before: Dictionary = authority.replay_snapshot()
	var rejected: Dictionary = authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 9, 1, &"time_rift", 120)
	)
	_suite.assert_equal(rejected.get("code"), &"SPAWN_FAILED", "failed factory spawn is explicit")
	_suite.assert_equal(authority.replay_snapshot(), before, "failed factory spawn leaves state byte-for-byte exact")
	_suite.assert_true(not authority.contains(&"run-a:3:rift:9:1"), "failed factory does not publish a partial payload")
	authority.queue_free()


func _test_gameplay_rewind_preserves_descriptor_and_node_identity() -> void:
	var authority = _authority_with_factory(&"time_rift")
	var committed: Dictionary = authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 120)
	)
	_suite.assert_true(bool(committed.get("ok", false)), "rewind fixture commits")
	var before_snapshot: Dictionary = authority.replay_snapshot()
	var before_node: Node = authority.payload_node(&"run-a:3:rift:8:1")
	var preserved: Dictionary = authority.preserve_committed_for_gameplay_rewind()
	_suite.assert_true(bool(preserved.get("ok", false)), "gameplay Rewind preservation succeeds")
	_suite.assert_equal(preserved.get("code"), &"COMMITTED_PAYLOADS_PRESERVED", "gameplay Rewind names its preserve-only semantic")
	_suite.assert_equal(authority.replay_snapshot(), before_snapshot, "gameplay Rewind never installs or mutates a Replay snapshot")
	_suite.assert_true(
		authority.payload_node(&"run-a:3:rift:8:1") == before_node,
		"gameplay Rewind preserves the exact committed Node instance"
	)
	authority.queue_free()


func _test_time_action_transaction_restore_preserves_existing_node_identity() -> void:
	var authority = _authority_with_factory(&"time_rift")
	var existing := _descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 120)
	var added_after_prepare := _descriptor(&"run-a", 3, &"rift", 9, 1, &"time_rift", 120)
	_suite.assert_true(bool(authority.commit_payload(existing).get("ok", false)), "prepared payload commits")
	var prepared: Dictionary = authority.replay_snapshot()
	var existing_node: Node = authority.payload_node(&"run-a:3:rift:8:1")
	_suite.assert_true(bool(authority.commit_payload(added_after_prepare).get("ok", false)), "post-prepare payload commits")
	_suite.assert_true(
		authority.restore_transaction_snapshot(prepared),
		"TimeAction transaction restore removes only post-prepare payloads"
	)
	_suite.assert_equal(authority.replay_snapshot(), prepared, "transaction restore returns the exact prepared descriptor root")
	_suite.assert_true(
		authority.payload_node(&"run-a:3:rift:8:1") == existing_node,
		"transaction restore preserves the exact pre-existing Node instance"
	)
	_suite.assert_true(
		not authority.contains(&"run-a:3:rift:9:1"),
		"transaction restore removes the payload committed after prepare"
	)
	authority.queue_free()


func _test_staged_transaction_restore_can_rollback_with_exact_node_identity() -> void:
	var authority = _authority_with_factory(&"time_rift")
	var existing := _descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 120)
	var added_after_prepare := _descriptor(&"run-a", 3, &"rift", 9, 1, &"time_rift", 120)
	_suite.assert_true(bool(authority.commit_payload(existing).get("ok", false)), "staged rollback existing payload commits")
	var prepared: Dictionary = authority.replay_snapshot()
	var existing_node: Node = authority.payload_node(&"run-a:3:rift:8:1")
	_suite.assert_true(bool(authority.commit_payload(added_after_prepare).get("ok", false)), "staged rollback added payload commits")
	var before: Dictionary = authority.replay_snapshot()
	var added_node: Node = authority.payload_node(&"run-a:3:rift:9:1")

	var ticket: Dictionary = authority.begin_transaction_restore(prepared)
	_suite.assert_true(not ticket.is_empty(), "staged rollback begins with an opaque ticket")
	_suite.assert_equal(authority.replay_snapshot(), prepared, "begin publishes the prepared descriptor root")
	_suite.assert_true(authority.payload_node(&"run-a:3:rift:8:1") == existing_node, "begin leaves prepared Node identity untouched")
	_suite.assert_true(not authority.contains(&"run-a:3:rift:9:1"), "begin detaches the post-prepare payload")
	_suite.assert_true(is_instance_valid(added_node), "detached payload remains alive for compensation")
	_suite.assert_true(added_node.get_parent() == null, "detached payload is not live in the scene tree")
	_suite.assert_true(authority.begin_transaction_restore(prepared).is_empty(), "a second begin is rejected while staged")
	var busy_commit: Dictionary = authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 10, 1, &"time_rift", 120)
	)
	_suite.assert_equal(busy_commit.get("code"), &"AUTHORITY_BUSY", "staged transaction blocks concurrent mutation")
	var stale_ticket := ticket.duplicate(true)
	stale_ticket["ticket_id"] = int(stale_ticket["ticket_id"]) + 1
	_suite.assert_true(not authority.commit_transaction_restore(stale_ticket), "wrong ticket cannot commit")
	_suite.assert_true(not authority.rollback_transaction_restore(stale_ticket), "wrong ticket cannot roll back")
	var other_authority = _authority_with_factory(&"time_rift")
	_suite.assert_true(bool(other_authority.commit_payload(existing).get("ok", false)), "cross-authority fixture existing payload commits")
	var other_prepared: Dictionary = other_authority.replay_snapshot()
	_suite.assert_true(bool(other_authority.commit_payload(added_after_prepare).get("ok", false)), "cross-authority fixture added payload commits")
	var other_ticket: Dictionary = other_authority.begin_transaction_restore(other_prepared)
	_suite.assert_true(not other_ticket.is_empty(), "cross-authority fixture begins with the same local ticket sequence")
	_suite.assert_true(not other_authority.commit_transaction_restore(ticket), "ticket capability cannot cross Authority instances")
	_suite.assert_true(other_authority.rollback_transaction_restore(other_ticket), "owning Authority accepts its own ticket")
	other_authority.queue_free()

	_suite.assert_true(authority.rollback_transaction_restore(ticket), "matching ticket rolls the staged transaction back")
	_suite.assert_equal(authority.replay_snapshot(), before, "rollback restores revision, frame, and descriptors exactly")
	_suite.assert_true(authority.payload_node(&"run-a:3:rift:8:1") == existing_node, "rollback preserves prepared Node identity")
	_suite.assert_true(authority.payload_node(&"run-a:3:rift:9:1") == added_node, "rollback reattaches the exact detached Node")
	_suite.assert_true(not authority.rollback_transaction_restore(ticket), "consumed rollback ticket is stale")
	_suite.assert_true(not authority.commit_transaction_restore(ticket), "rolled-back ticket cannot commit later")
	authority.queue_free()


func _test_staged_transaction_restore_commits_exactly_once() -> void:
	var authority = _authority_with_factory(&"time_rift")
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 120)
	).get("ok", false)), "staged commit existing payload commits")
	var prepared: Dictionary = authority.replay_snapshot()
	var existing_node: Node = authority.payload_node(&"run-a:3:rift:8:1")
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 9, 1, &"time_rift", 120)
	).get("ok", false)), "staged commit added payload commits")
	var added_node: Node = authority.payload_node(&"run-a:3:rift:9:1")
	var ticket: Dictionary = authority.begin_transaction_restore(prepared)
	_suite.assert_true(not ticket.is_empty(), "staged commit begins")
	_suite.assert_true(authority.commit_transaction_restore(ticket), "matching ticket commits detached retirement")
	_suite.assert_equal(authority.replay_snapshot(), prepared, "commit keeps the exact prepared descriptor root")
	_suite.assert_true(authority.payload_node(&"run-a:3:rift:8:1") == existing_node, "commit preserves prepared Node identity")
	_suite.assert_true(not is_instance_valid(added_node), "commit finally disposes the detached payload")
	_suite.assert_true(not authority.commit_transaction_restore(ticket), "committed ticket is exactly once")
	_suite.assert_true(not authority.rollback_transaction_restore(ticket), "committed ticket cannot roll back")
	authority.queue_free()


func _test_fixed_frame_lifetime_is_deterministic() -> void:
	var authority = _authority_with_factory(&"time_rift")
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 3)
	).get("ok", false)), "lifetime fixture commits")
	var frame_zero: Dictionary = authority.advance_frame(0)
	_suite.assert_true(bool(frame_zero.get("ok", false)), "frame zero deterministically advances one fixed frame")
	_suite.assert_equal(
		int(authority.payload_descriptor(&"run-a:3:rift:8:1").get("remaining_frames", -1)),
		2,
		"first fixed frame decrements lifetime once"
	)
	var before_stale: Dictionary = authority.replay_snapshot()
	var stale: Dictionary = authority.advance_frame(0)
	_suite.assert_equal(stale.get("code"), &"STALE_FRAME", "duplicate frame is rejected")
	_suite.assert_equal(authority.replay_snapshot(), before_stale, "duplicate frame does not double-tick payloads")
	var skipped: Dictionary = authority.advance_frame(2)
	_suite.assert_equal(skipped.get("code"), &"STALE_FRAME", "skipped frame is rejected")
	_suite.assert_equal(authority.replay_snapshot(), before_stale, "skipped frame cannot split Node and descriptor lifetime")
	_suite.assert_true(bool(authority.advance_frame(1).get("ok", false)), "next frame advances")
	var expired: Dictionary = authority.advance_frame(2)
	_suite.assert_equal(expired.get("expired_ids"), ["run-a:3:rift:8:1"], "zero lifetime expires the exact stable payload")
	_suite.assert_true(not authority.contains(&"run-a:3:rift:8:1"), "expired payload leaves the authoritative set")
	authority.queue_free()


func _test_payload_frame_rejection_rolls_back_every_node_and_descriptor() -> void:
	var authority = AuthorityScript.new()
	add_child(authority)
	var factory := PayloadFactory.new()
	factory.reject_frame_for_source_token = 9
	_suite.assert_true(
		authority.register_factory(&"time_rift", Callable(factory, "create_payload")),
		"frame rollback fixture factory registers"
	)
	for source_token: int in [8, 9]:
		_suite.assert_true(bool(authority.commit_payload(
			_descriptor(&"run-a", 3, &"rift", source_token, 1, &"time_rift", 120)
		).get("ok", false)), "frame rollback payload %d commits" % source_token)
	var before: Dictionary = authority.replay_snapshot()
	var first_node := authority.payload_node(&"run-a:3:rift:8:1") as FramePayload
	var second_node := authority.payload_node(&"run-a:3:rift:9:1") as FramePayload
	var first_before := first_node.world_payload_frame_snapshot()
	var second_before := second_node.world_payload_frame_snapshot()
	var rejected: Dictionary = authority.advance_frame(0)
	_suite.assert_equal(rejected.get("code"), &"PAYLOAD_FRAME_REJECTED", "payload frame rejection is explicit")
	_suite.assert_equal(authority.replay_snapshot(), before, "failed payload frame leaves descriptor authority byte-exact")
	_suite.assert_equal(first_node.world_payload_frame_snapshot(), first_before, "earlier payload frame mutation rolls back")
	_suite.assert_equal(second_node.world_payload_frame_snapshot(), second_before, "rejecting payload frame mutation rolls back")
	authority.queue_free()


func _test_frame_transaction_rollback_restores_exact_payload_state() -> void:
	var authority = _authority_with_factory(&"time_rift")
	var payload_id := &"run-a:3:rift:8:1"
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 3)
	).get("ok", false)), "frame transaction rollback fixture commits")
	var payload := authority.payload_node(payload_id) as FramePayload
	payload.last_runtime_frame = -1
	payload.advance_calls = 7
	var before: Dictionary = authority.replay_snapshot()
	var before_descriptor: Dictionary = authority.payload_descriptor(payload_id)
	var before_node_state: Dictionary = payload.world_payload_frame_snapshot()
	var ticket: Dictionary = authority.begin_frame_transaction(0)
	_suite.assert_true(not ticket.is_empty(), "frame transaction begins for the next exact frame")
	_suite.assert_true(bool(authority.advance_frame(0).get("ok", false)), "transactional frame advances")
	_suite.assert_equal(
		int(authority.payload_descriptor(payload_id).get("remaining_frames", -1)),
		2,
		"transactional frame tentatively decrements descriptor lifetime"
	)
	_suite.assert_true(authority.rollback_frame_transaction(ticket), "matching frame ticket rolls back")
	_suite.assert_equal(authority.replay_snapshot(), before, "rollback restores revision and runtime frame exactly")
	_suite.assert_equal(authority.payload_descriptor(payload_id), before_descriptor, "rollback restores descriptor exactly")
	_suite.assert_true(authority.payload_node(payload_id) == payload, "rollback preserves exact payload Node identity")
	_suite.assert_equal(payload.world_payload_frame_snapshot(), before_node_state, "rollback restores payload-local frame state")
	authority.queue_free()


func _test_frame_transaction_expiry_is_deferred_until_commit() -> void:
	var authority = _authority_with_factory(&"time_rift")
	var payload_id := &"run-a:3:rift:8:1"
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 1)
	).get("ok", false)), "frame expiry fixture commits")
	var payload := authority.payload_node(payload_id) as FramePayload
	payload.last_runtime_frame = -1
	var before: Dictionary = authority.replay_snapshot()
	var before_node_state: Dictionary = payload.world_payload_frame_snapshot()

	var rollback_ticket: Dictionary = authority.begin_frame_transaction(0)
	_suite.assert_true(bool(authority.advance_frame(0).get("ok", false)), "expiring frame advances transactionally")
	_suite.assert_true(not authority.contains(payload_id), "expired payload is detached from tentative authority")
	_suite.assert_true(is_instance_valid(payload), "expired payload remains alive until transaction settlement")
	_suite.assert_true(payload.get_parent() == null, "expired payload is detached while settlement is pending")
	_suite.assert_true(authority.rollback_frame_transaction(rollback_ticket), "expiry transaction rolls back")
	_suite.assert_equal(authority.replay_snapshot(), before, "expiry rollback restores the exact descriptor root")
	_suite.assert_true(authority.payload_node(payload_id) == payload, "expiry rollback reattaches the exact same Node")
	_suite.assert_equal(payload.world_payload_frame_snapshot(), before_node_state, "expiry rollback restores Node frame state")

	var commit_ticket: Dictionary = authority.begin_frame_transaction(0)
	_suite.assert_true(bool(authority.advance_frame(0).get("ok", false)), "expiring frame can be retried after rollback")
	_suite.assert_true(authority.can_commit_frame_transaction(commit_ticket), "valid expiry settlement preflights")
	_suite.assert_true(is_instance_valid(payload), "preflight does not destroy the expired Node")
	_suite.assert_true(authority.commit_frame_transaction(commit_ticket), "preflighted expiry settlement commits")
	_suite.assert_true(not is_instance_valid(payload), "commit is the first point that destroys the expired Node")
	_suite.assert_true(not authority.contains(payload_id), "committed expiry stays absent")
	_suite.assert_true(not authority.commit_frame_transaction(commit_ticket), "consumed frame ticket cannot commit twice")
	_suite.assert_true(not authority.rollback_frame_transaction(commit_ticket), "consumed frame ticket cannot roll back")
	authority.queue_free()


func _test_frame_transaction_tracks_added_payloads() -> void:
	var authority = _authority_with_factory(&"time_rift")
	var before: Dictionary = authority.replay_snapshot()
	var pre_advance_ticket: Dictionary = authority.begin_frame_transaction(0)
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 7, 1, &"time_rift", 3)
	).get("ok", false)), "pre-advance frame addition commits tentatively")
	var pre_advance_node: Node = authority.payload_node(&"run-a:3:rift:7:1")
	_suite.assert_true(authority.rollback_frame_transaction(pre_advance_ticket), "pre-advance addition rolls back")
	_suite.assert_equal(authority.replay_snapshot(), before, "pre-advance addition rollback restores exact authority")
	_suite.assert_true(not is_instance_valid(pre_advance_node), "pre-advance rolled-back addition Node is destroyed")

	var rollback_ticket: Dictionary = authority.begin_frame_transaction(0)
	_suite.assert_true(bool(authority.advance_frame(0).get("ok", false)), "empty authority advances inside rollback fixture")
	var rollback_commit: Dictionary = authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 3)
	)
	_suite.assert_true(bool(rollback_commit.get("ok", false)), "frame transaction accepts newly committed payload")
	var rollback_node: Node = authority.payload_node(&"run-a:3:rift:8:1")
	_suite.assert_true(authority.rollback_frame_transaction(rollback_ticket), "frame addition rolls back")
	_suite.assert_equal(authority.replay_snapshot(), before, "addition rollback restores exact pre-frame authority")
	_suite.assert_true(not authority.contains(&"run-a:3:rift:8:1"), "rolled-back addition is no longer authoritative")
	_suite.assert_true(not is_instance_valid(rollback_node), "rolled-back addition Node is destroyed")

	var commit_ticket: Dictionary = authority.begin_frame_transaction(0)
	var committed: Dictionary = authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 9, 1, &"time_rift", 3)
	)
	_suite.assert_true(bool(committed.get("ok", false)), "pre-advance frame addition commits tentatively")
	var committed_node: Node = authority.payload_node(&"run-a:3:rift:9:1")
	_suite.assert_true(bool(authority.advance_frame(0).get("ok", false)), "frame advances the tentative addition")
	_suite.assert_true(authority.can_commit_frame_transaction(commit_ticket), "addition settlement preflights")
	_suite.assert_true(authority.commit_frame_transaction(commit_ticket), "addition settlement commits")
	_suite.assert_true(authority.contains(&"run-a:3:rift:9:1"), "committed addition remains authoritative")
	_suite.assert_true(authority.payload_node(&"run-a:3:rift:9:1") == committed_node, "commit preserves added Node identity")
	_suite.assert_equal(
		int(authority.payload_descriptor(&"run-a:3:rift:9:1").get("remaining_frames", -1)),
		2,
		"committed addition retains its deterministic frame advance"
	)
	authority.queue_free()


func _test_frame_transaction_rolls_back_added_payload_that_expires() -> void:
	var authority = _authority_with_factory(&"time_rift")
	var before: Dictionary = authority.replay_snapshot()
	var ticket: Dictionary = authority.begin_frame_transaction(0)
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 1)
	).get("ok", false)), "one-frame addition commits tentatively")
	var added_node: Node = authority.payload_node(&"run-a:3:rift:8:1")
	_suite.assert_true(bool(authority.advance_frame(0).get("ok", false)), "one-frame addition advances and expires")
	_suite.assert_true(not authority.contains(&"run-a:3:rift:8:1"), "expired addition leaves tentative authority")
	_suite.assert_true(is_instance_valid(added_node), "expired addition remains compensatable")
	_suite.assert_true(authority.rollback_frame_transaction(ticket), "expired addition transaction rolls back")
	_suite.assert_equal(authority.replay_snapshot(), before, "expired addition rollback restores exact pre-frame state")
	_suite.assert_true(not is_instance_valid(added_node), "expired addition is destroyed rather than reattached")
	authority.queue_free()


func _test_frame_transaction_tickets_and_restore_are_fail_closed() -> void:
	var authority = _authority_with_factory(&"time_rift")
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 3)
	).get("ok", false)), "ticket boundary fixture commits")
	var target: Dictionary = authority.replay_snapshot()
	var ticket: Dictionary = authority.begin_frame_transaction(0)
	_suite.assert_true(not ticket.is_empty(), "ticket boundary frame begins")
	var pending_before_mutations: Dictionary = authority.replay_snapshot()
	_suite.assert_equal(
		authority.retire_payload(&"run-a:3:rift:8:1", &"run-a", 3, &"expired").get("code"),
		&"AUTHORITY_BUSY",
		"untracked retirement is blocked during a frame transaction"
	)
	_suite.assert_equal(
		authority.invalidate_generation(&"run-a", 3, &"run_reset").get("code"),
		&"AUTHORITY_BUSY",
		"untracked invalidation is blocked during a frame transaction"
	)
	_suite.assert_true(
		not authority.register_factory(&"character_echo", Callable(PayloadFactory.new(), "create_payload")),
		"factory mutation is blocked during a frame transaction"
	)
	_suite.assert_true(not authority.reset_runtime_clock(), "clock reset is blocked during a frame transaction")
	_suite.assert_true(not authority.reanchor_empty_runtime_clock(-1), "clock reanchor is blocked during a frame transaction")
	_suite.assert_equal(authority.replay_snapshot(), pending_before_mutations, "blocked untracked mutations leave state exact")
	_suite.assert_true(authority.begin_transaction_restore(target).is_empty(), "restore transaction cannot overlap frame transaction")
	_suite.assert_true(not authority.restore_transaction_snapshot(target), "one-shot transaction restore cannot overlap frame transaction")
	_suite.assert_true(not authority.restore_replay_snapshot(target), "Replay restore cannot overlap frame transaction")
	_suite.assert_true(bool(authority.advance_frame(0).get("ok", false)), "ticket boundary frame advances")
	var pending: Dictionary = authority.replay_snapshot()
	var payload: Node = authority.payload_node(&"run-a:3:rift:8:1")

	var forged := ticket.duplicate(true)
	forged["ticket_id"] = int(forged["ticket_id"]) + 1
	_suite.assert_true(not authority.can_commit_frame_transaction(forged), "forged frame ticket cannot preflight")
	_suite.assert_true(not authority.commit_frame_transaction(forged), "forged frame ticket cannot commit")
	_suite.assert_true(not authority.rollback_frame_transaction(forged), "forged frame ticket cannot roll back")
	var extended := ticket.duplicate(true)
	extended["extra"] = true
	_suite.assert_true(not authority.can_commit_frame_transaction(extended), "ticket with extra capability data is rejected")
	_suite.assert_equal(authority.replay_snapshot(), pending, "forged tickets leave pending descriptor state exact")
	_suite.assert_true(authority.payload_node(&"run-a:3:rift:8:1") == payload, "forged tickets preserve Node identity")
	_suite.assert_true(authority.rollback_frame_transaction(ticket), "owning exact ticket remains usable")

	var restore_ticket: Dictionary = authority.begin_transaction_restore(target)
	_suite.assert_true(not restore_ticket.is_empty(), "restore transaction can begin after frame rollback")
	_suite.assert_true(authority.begin_frame_transaction(0).is_empty(), "frame transaction cannot overlap restore transaction")
	_suite.assert_true(authority.rollback_transaction_restore(restore_ticket), "restore fixture rolls back cleanly")
	authority.queue_free()


func _test_frame_transaction_preflight_is_pure_and_freezes_commit() -> void:
	var authority = _authority_with_factory(&"time_rift")
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 3)
	).get("ok", false)), "preflight fixture commits")
	var ticket: Dictionary = authority.begin_frame_transaction(0)
	_suite.assert_true(bool(authority.advance_frame(0).get("ok", false)), "preflight fixture advances")
	var before: Dictionary = authority.replay_snapshot()
	var payload: Node = authority.payload_node(&"run-a:3:rift:8:1")
	var payload_state: Dictionary = (payload as FramePayload).world_payload_frame_snapshot()
	_suite.assert_true(authority.can_commit_frame_transaction(ticket), "matching frame ticket can commit")
	_suite.assert_equal(authority.replay_snapshot(), before, "commit preflight does not change Replay-visible state")
	_suite.assert_true(authority.payload_node(&"run-a:3:rift:8:1") == payload, "commit preflight preserves Node identity")
	_suite.assert_equal((payload as FramePayload).world_payload_frame_snapshot(), payload_state, "commit preflight does not mutate Node state")
	_suite.assert_true(authority.can_commit_frame_transaction(ticket), "commit preflight is idempotent")
	var blocked: Dictionary = authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 9, 1, &"time_rift", 3)
	)
	_suite.assert_equal(blocked.get("code"), &"AUTHORITY_BUSY", "preflight freezes further frame mutations")
	_suite.assert_equal(authority.replay_snapshot(), before, "rejected post-preflight mutation leaves state exact")
	_suite.assert_true(authority.commit_frame_transaction(ticket), "preflighted commit has no later validation failure")
	authority.queue_free()


func _test_replay_snapshot_is_complete_sorted_and_reconstructable() -> void:
	var source = AuthorityScript.new()
	add_child(source)
	var rift_factory := PayloadFactory.new()
	var echo_factory := PayloadFactory.new()
	_suite.assert_true(source.register_factory(&"time_rift", Callable(rift_factory, "create_payload")), "source Rift factory registers")
	_suite.assert_true(source.register_factory(&"character_echo", Callable(echo_factory, "create_payload")), "source echo factory registers")
	_suite.assert_true(bool(source.commit_payload(
		_descriptor(&"run-a", 4, &"rift", 20, 2, &"time_rift", 90)
	).get("ok", false)), "lexically later payload commits first")
	var echo := _descriptor(&"run-a", 4, &"echo", 2, 1, &"character_echo", 45)
	echo["claims"] = ["enemy:b", "enemy:a"]
	echo["tags"] = ["no_resource", "world_owned", "no_mastery"]
	echo["parameters"] = {"damage": 12.5, "offsets": [Vector2.LEFT, Vector2.RIGHT]}
	_suite.assert_true(bool(source.commit_payload(echo).get("ok", false)), "lexically earlier payload commits second")
	_suite.assert_true(bool(source.advance_frame(0).get("ok", false)), "source frame state is captured")

	var snapshot: Dictionary = source.replay_snapshot()
	var descriptors := snapshot.get("descriptors", []) as Array
	_suite.assert_equal(descriptors.size(), 2, "Replay snapshot captures the complete descriptor set")
	_suite.assert_equal(
		str((descriptors[0] as Dictionary).get("payload_id", "")),
		"run-a:4:echo:2:1",
		"Replay descriptor set is sorted by stable payload identity"
	)
	_suite.assert_equal(
		(descriptors[0] as Dictionary).get("claims"),
		["enemy:a", "enemy:b"],
		"unordered claim set is stored canonically"
	)
	_suite.assert_equal(
		(descriptors[0] as Dictionary).get("tags"),
		["no_mastery", "no_resource", "world_owned"],
		"non-recursive tag set is stored canonically"
	)

	var restored = AuthorityScript.new()
	add_child(restored)
	var restored_rift_factory := PayloadFactory.new()
	var restored_echo_factory := PayloadFactory.new()
	_suite.assert_true(restored.register_factory(&"time_rift", Callable(restored_rift_factory, "create_payload")), "restore Rift factory registers")
	_suite.assert_true(restored.register_factory(&"character_echo", Callable(restored_echo_factory, "create_payload")), "restore echo factory registers")
	_suite.assert_true(restored.restore_replay_snapshot(snapshot), "fully validated Replay snapshot restores")
	_suite.assert_equal(restored.replay_snapshot(), snapshot, "Replay restore installs the complete exact snapshot")
	_suite.assert_true(restored.contains(&"run-a:4:echo:2:1"), "Replay restore reconstructs echo")
	_suite.assert_true(restored.contains(&"run-a:4:rift:20:2"), "Replay restore reconstructs Rift")
	source.queue_free()
	restored.queue_free()


func _test_failed_replay_restore_preserves_exact_live_set() -> void:
	var authority = AuthorityScript.new()
	add_child(authority)
	var factory := PayloadFactory.new()
	_suite.assert_true(authority.register_factory(&"time_rift", Callable(factory, "create_payload")), "atomic restore factory registers")
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-live", 9, &"rift", 1, 1, &"time_rift", 30)
	).get("ok", false)), "live payload commits")
	var before: Dictionary = authority.replay_snapshot()
	var before_node: Node = authority.payload_node(&"run-live:9:rift:1:1")

	var candidate := before.duplicate(true)
	var descriptors := candidate["descriptors"] as Array
	descriptors.append(_descriptor(&"run-new", 10, &"rift", 6, 1, &"time_rift", 60))
	descriptors.append(_descriptor(&"run-new", 10, &"rift", 7, 1, &"time_rift", 60))
	descriptors.sort_custom(func(a: Dictionary, b: Dictionary): return str(a["payload_id"]) < str(b["payload_id"]))
	candidate["revision"] = int(candidate["revision"]) + 1
	factory.fail_on_source_token = 7
	_suite.assert_true(not authority.restore_replay_snapshot(candidate), "one failed staged spawn rejects the whole Replay restore")
	_suite.assert_equal(authority.replay_snapshot(), before, "partial Replay restore leaves every live descriptor exact")
	_suite.assert_true(
		authority.payload_node(&"run-live:9:rift:1:1") == before_node,
		"partial Replay restore preserves the exact prior live Node instance"
	)
	_suite.assert_true(not authority.contains(&"run-new:10:rift:6:1"), "successfully staged prefix never becomes partially authoritative")
	authority.queue_free()


func _test_generation_invalidation_is_exact_and_permanent() -> void:
	var authority = _authority_with_factory(&"time_rift")
	var descriptors: Array[Dictionary] = [
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 120),
		_descriptor(&"run-a", 3, &"rift", 9, 1, &"time_rift", 120),
		_descriptor(&"run-a", 4, &"rift", 8, 1, &"time_rift", 120),
		_descriptor(&"run-b", 3, &"rift", 8, 1, &"time_rift", 120),
	]
	for descriptor: Dictionary in descriptors:
		_suite.assert_true(bool(authority.commit_payload(descriptor).get("ok", false)), "generation fixture payload commits")
	var run_a_generation_four_node: Node = authority.payload_node(&"run-a:4:rift:8:1")
	var run_b_generation_three_node: Node = authority.payload_node(&"run-b:3:rift:8:1")
	var cleared: Dictionary = authority.invalidate_generation(&"run-a", 3, &"loadout_replacement")
	_suite.assert_true(bool(cleared.get("ok", false)), "exact outgoing generation invalidates")
	_suite.assert_equal(
		cleared.get("removed_ids"),
		["run-a:3:rift:8:1", "run-a:3:rift:9:1"],
		"invalidation returns the sorted exact removed stable identities"
	)
	_suite.assert_equal(cleared.get("invalidation_revision"), 1, "first invalidation advances its monotonic revision")
	_suite.assert_true(not authority.contains(&"run-a:3:rift:8:1"), "outgoing generation payload is removed")
	_suite.assert_true(authority.contains(&"run-a:4:rift:8:1"), "same-run next generation is untouched")
	_suite.assert_true(authority.contains(&"run-b:3:rift:8:1"), "same numeric generation in another run is untouched")
	_suite.assert_true(authority.payload_node(&"run-a:4:rift:8:1") == run_a_generation_four_node, "neighbor generation preserves Node identity")
	_suite.assert_true(authority.payload_node(&"run-b:3:rift:8:1") == run_b_generation_three_node, "neighbor run preserves Node identity")

	var stale_commit: Dictionary = authority.commit_payload(descriptors[0])
	_suite.assert_equal(stale_commit.get("code"), &"INVALIDATED_GENERATION", "invalidated owner generation can never be reused")
	var stale_callback: Dictionary = authority.retire_payload(
		&"run-a:3:rift:8:1", &"run-a", 3, &"payload_completed"
	)
	_suite.assert_equal(stale_callback.get("code"), &"STALE_CALLBACK", "late callback from invalidated generation is rejected")
	_suite.assert_true(authority.contains(&"run-a:4:rift:8:1"), "stale callback cannot touch another generation")
	_suite.assert_true(authority.contains(&"run-b:3:rift:8:1"), "stale callback cannot touch another run")
	var duplicate_invalidation: Dictionary = authority.invalidate_generation(&"run-a", 3, &"loadout_replacement")
	_suite.assert_equal(duplicate_invalidation.get("code"), &"GENERATION_ALREADY_INVALIDATED", "repeat invalidation is rejected")
	_suite.assert_equal(duplicate_invalidation.get("invalidation_revision"), 1, "repeat invalidation cannot advance revision")
	authority.queue_free()


func _test_generation_invalidation_watermark_is_bounded_and_permanent() -> void:
	const INVALIDATION_COUNT := 5000
	var authority = _authority_with_factory(&"time_rift")
	var all_invalidations_succeeded := true
	for generation: int in range(1, INVALIDATION_COUNT + 1):
		var result: Dictionary = authority.invalidate_generation(
			&"run-stress",
			generation,
			&"generation_rotation"
		)
		if not bool(result.get("ok", false)):
			all_invalidations_succeeded = false
			break
	_suite.assert_true(
		all_invalidations_succeeded,
		"sequential generation stress invalidations all succeed"
	)
	var snapshot: Dictionary = authority.replay_snapshot()
	var invalidations := snapshot.get("invalidated_generations", []) as Array
	_suite.assert_equal(
		invalidations.size(),
		1,
		"sequential tombstones compact to one per-run generation watermark"
	)
	if invalidations.size() == 1:
		_suite.assert_equal(
			int((invalidations[0] as Dictionary).get("owner_character_generation", 0)),
			INVALIDATION_COUNT,
			"compacted watermark records the highest invalidated generation"
		)
	_suite.assert_equal(
		int(snapshot.get("invalidation_revision", -1)),
		INVALIDATION_COUNT,
		"compaction preserves the monotonic invalidation revision"
	)
	_suite.assert_equal(
		authority.first_available_generation(&"run-stress", 1),
		INVALIDATION_COUNT + 1,
		"first available generation skips the complete compacted history"
	)
	for stale_generation: int in [1, INVALIDATION_COUNT / 2, INVALIDATION_COUNT]:
		_suite.assert_true(
			authority.generation_is_invalidated(&"run-stress", stale_generation),
			"compacted history permanently rejects old generation %d" % stale_generation
		)
		_suite.assert_equal(
			authority.commit_payload(_descriptor(
				&"run-stress",
				stale_generation,
				&"rift",
				stale_generation,
				1,
				&"time_rift",
				30
			)).get("code"),
			&"INVALIDATED_GENERATION",
			"compacted generation %d cannot be resurrected" % stale_generation
		)
	_suite.assert_equal(
		authority.invalidate_generation(
			&"run-stress",
			INVALIDATION_COUNT - 1,
			&"generation_rotation"
		).get("code"),
		&"GENERATION_ALREADY_INVALIDATED",
		"an old generation remains tombstoned after its exact record is compacted"
	)

	var restored = _authority_with_factory(&"time_rift")
	_suite.assert_true(
		restored.restore_replay_snapshot(snapshot),
		"compacted generation watermark survives Replay restore"
	)
	_suite.assert_equal(
		restored.replay_snapshot(),
		snapshot,
		"Replay restore preserves the exact compacted invalidation snapshot"
	)
	_suite.assert_true(
		restored.generation_is_invalidated(&"run-stress", 1),
		"restored watermark still rejects the oldest generation"
	)
	_suite.assert_equal(
		restored.first_available_generation(&"run-stress", 1),
		INVALIDATION_COUNT + 1,
		"restored watermark preserves A-to-B-to-A generation skipping"
	)

	var before_transaction: Dictionary = authority.replay_snapshot()
	var ticket: Dictionary = authority.begin_frame_transaction(0)
	_suite.assert_true(not ticket.is_empty(), "compacted watermark frame transaction begins")
	_suite.assert_true(
		bool(authority.advance_frame(0).get("ok", false)),
		"compacted watermark frame transaction advances"
	)
	_suite.assert_true(
		authority.rollback_frame_transaction(ticket),
		"compacted watermark frame transaction rolls back"
	)
	_suite.assert_equal(
		authority.replay_snapshot(),
		before_transaction,
		"frame rollback preserves the exact compacted watermark"
	)
	authority.queue_free()
	restored.queue_free()


func _test_generation_reset_preflight_is_pure_and_lock_aware() -> void:
	var authority = _authority_with_factory(&"time_rift")
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 120)
	).get("ok", false)), "runtime reset preflight fixture commits")
	var before: Dictionary = authority.replay_snapshot()
	_suite.assert_true(
		authority.can_reset_generation_runtime(&"run-a", 3, &"player_runtime_reset"),
		"runtime reset preflight accepts an authority owned only by the outgoing generation"
	)
	_suite.assert_equal(
		authority.replay_snapshot(),
		before,
		"runtime reset preflight is observation-only"
	)
	var ticket: Dictionary = authority.begin_transaction_restore(before)
	_suite.assert_true(not ticket.is_empty(), "runtime reset preflight fixture locks authority mutation")
	_suite.assert_true(
		not authority.can_reset_generation_runtime(&"run-a", 3, &"player_runtime_reset"),
		"runtime reset preflight rejects while a restore transaction owns the authority"
	)
	_suite.assert_true(authority.rollback_transaction_restore(ticket), "runtime reset preflight fixture unlocks cleanly")
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 4, &"rift", 9, 1, &"time_rift", 120)
	).get("ok", false)), "foreign generation clock-reset blocker commits")
	_suite.assert_true(
		not authority.can_reset_generation_runtime(&"run-a", 3, &"player_runtime_reset"),
		"runtime reset preflight rejects a payload that outgoing-generation invalidation cannot remove"
	)
	_suite.assert_true(bool(authority.invalidate_generation(
		&"run-a", 1, &"generation_history"
	).get("ok", false)), "generation one tombstone installs")
	_suite.assert_true(bool(authority.invalidate_generation(
		&"run-a", 2, &"generation_history"
	).get("ok", false)), "generation two tombstone installs")
	_suite.assert_equal(
		authority.first_available_generation(&"run-a", 1),
		3,
		"first available generation skips the complete tombstone prefix"
	)
	authority.queue_free()


func _test_replay_restore_cannot_cross_invalidation_boundary() -> void:
	var authority = _authority_with_factory(&"time_rift")
	_suite.assert_true(bool(authority.commit_payload(
		_descriptor(&"run-a", 3, &"rift", 8, 1, &"time_rift", 120)
	).get("ok", false)), "pre-invalidation fixture commits")
	var stale_snapshot: Dictionary = authority.replay_snapshot()
	_suite.assert_true(bool(authority.invalidate_generation(
		&"run-a", 3, &"run_reset"
	).get("ok", false)), "generation boundary commits")
	var after_invalidation: Dictionary = authority.replay_snapshot()
	_suite.assert_true(
		not authority.restore_replay_snapshot(stale_snapshot),
		"Replay restore cannot resurrect a generation invalidated by reset"
	)
	_suite.assert_equal(authority.replay_snapshot(), after_invalidation, "rejected stale Replay leaves tombstone and state exact")
	authority.queue_free()


func _test_cold_restore_rebases_matching_invalidation_history() -> void:
	var fresh = _authority_with_factory(&"time_rift")
	var retained = _authority_with_factory(&"time_rift")
	fresh.invalidate_generation(&"standalone", 2, &"run_replacement")
	fresh.invalidate_generation(&"run-second", 1, &"player_runtime_reset")
	retained.invalidate_generation(&"standalone", 2, &"run_replacement")
	retained.invalidate_generation(&"run-first", 2, &"player_died")
	retained.invalidate_generation(&"run-second", 1, &"player_runtime_reset")
	var fresh_before: Dictionary = fresh.replay_snapshot()
	var target: Dictionary = retained.replay_snapshot()
	var forged := target.duplicate(true)
	for row: Dictionary in forged.invalidated_generations:
		if row.run_id == &"run-second":
			row.reason = &"unrelated_reason"
	_suite.assert_true(not fresh.restore_replay_snapshot(forged), "cold history rebase rejects a changed invalidation reason")
	_suite.assert_equal(fresh.replay_snapshot(), fresh_before, "refused history rebase preserves the entire live authority")
	_suite.assert_true(fresh.restore_replay_snapshot(target), "cold restore accepts matching generation tombstones at higher retained revisions")
	_suite.assert_equal(fresh.replay_snapshot(), target, "cold restore retains the exact previous-run history and revision watermark")
	var reordered := target.duplicate(true)
	for row: Dictionary in reordered.invalidated_generations:
		if row.run_id == &"run-first":
			row.revision = 3
		elif row.run_id == &"run-second":
			row.revision = 2
	_suite.assert_true(not fresh.restore_replay_snapshot(reordered), "retained history cannot reduce one tombstone revision while keeping every run key")
	_suite.assert_equal(fresh.replay_snapshot(), target, "refused tombstone revision rollback leaves the exact live history")
	_suite.assert_true(not fresh.restore_replay_snapshot(fresh_before), "rebased live history cannot drop previous-run tombstones or reduce revisions")
	_suite.assert_equal(fresh.replay_snapshot(), target, "history rollback refusal preserves the accepted retained tombstones")
	fresh.queue_free()
	retained.queue_free()


func _authority_with_factory(handler_id: StringName):
	var authority = AuthorityScript.new()
	add_child(authority)
	var factory := PayloadFactory.new()
	_suite.assert_true(
		authority.register_factory(handler_id, Callable(factory, "create_payload")),
		"%s fixture factory registers" % str(handler_id)
	)
	return authority


func _descriptor(
	run_id: StringName,
	owner_character_generation: int,
	payload_family: StringName,
	source_token: int,
	payload_generation: int,
	handler_id: StringName,
	remaining_frames: int
) -> Dictionary:
	return {
		"payload_id": "%s:%d:%s:%d:%d" % [
			str(run_id),
			owner_character_generation,
			str(payload_family),
			source_token,
			payload_generation,
		],
		"handler_id": handler_id,
		"run_id": run_id,
		"owner_character_generation": owner_character_generation,
		"payload_family": payload_family,
		"source_token": source_token,
		"payload_generation": payload_generation,
		"transform": Transform2D.IDENTITY,
		"geometry": {"center": Vector2.ZERO, "radius": 96.0},
		"remaining_frames": remaining_frames,
		"claims": [],
		"tags": ["world_owned"],
		"parameters": {},
	}
