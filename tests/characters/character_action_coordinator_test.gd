extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const CharacterActionContractScript := preload(
	"res://scripts/player/characters/character_action_contract.gd"
)
const CharacterActionCoordinatorScript := preload(
	"res://scripts/player/characters/character_action_coordinator.gd"
)


class IncompleteRuntime extends RefCounted:
	func advance_frame(_context: Dictionary) -> Array[Dictionary]:
		return []


class FakeCharacterRuntime extends RefCounted:
	var last_runtime_frame: int = -1
	var revision: int = 0
	var received_contexts: Array[Dictionary] = []
	var reset_reasons: Array[StringName] = []
	var return_malformed_events: bool = false
	var reject_restore: bool = false
	var mutate_then_reject_restore_once: bool = false


	func advance_frame(context: Dictionary) -> Variant:
		last_runtime_frame = int(context.get("runtime_frame", -1))
		revision += 1
		received_contexts.append(context.duplicate(true))
		if return_malformed_events:
			return {"malformed": true}
		return [{
			"type": "character_runtime_advanced",
			"runtime_frame": last_runtime_frame,
			"payload": context.get("payload", {}).duplicate(true),
		}]


	func snapshot() -> Dictionary:
		return {
			"last_runtime_frame": last_runtime_frame,
			"revision": revision,
			"received_contexts": received_contexts.duplicate(true),
			"reset_reasons": reset_reasons.duplicate(),
		}


	func can_restore_snapshot(value: Dictionary) -> bool:
		return (
			value.size() == 4
			and typeof(value.get("last_runtime_frame")) == TYPE_INT
			and int(value.get("last_runtime_frame", -2)) >= -1
			and typeof(value.get("revision")) == TYPE_INT
			and int(value.get("revision", -1)) >= 0
			and value.get("received_contexts") is Array
			and value.get("reset_reasons") is Array
		)


	func restore_snapshot(value: Dictionary) -> bool:
		if not can_restore_snapshot(value):
			return false
		if mutate_then_reject_restore_once:
			mutate_then_reject_restore_once = false
			last_runtime_frame = int(value["last_runtime_frame"])
			revision = int(value["revision"]) + 100
			return false
		if reject_restore:
			return false
		last_runtime_frame = int(value["last_runtime_frame"])
		revision = int(value["revision"])
		received_contexts = (value["received_contexts"] as Array).duplicate(true)
		reset_reasons = (value["reset_reasons"] as Array).duplicate()
		return true


	func reset_runtime_state(reason: StringName) -> void:
		last_runtime_frame = -1
		revision += 1
		received_contexts.clear()
		reset_reasons.append(reason)


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_unconfigured_coordinator_is_a_monotonic_no_op()
	_test_configure_rejects_incomplete_runtime_without_mutation()
	_test_configured_runtime_receives_authoritative_frame_context()
	_test_invalid_advance_inputs_fail_without_mutation()
	_test_malformed_runtime_events_roll_back_exactly()
	_test_two_phase_frame_can_commit_or_roll_back_exactly()
	_test_two_phase_commit_rejects_runtime_drift()
	_test_unconfigured_runtime_frame_can_reanchor()
	_test_snapshot_is_deep_isolated()
	_test_unconfigured_snapshot_round_trip_restores_exact_state()
	_test_snapshot_round_trip_restores_exact_state()
	_test_invalid_snapshots_fail_without_mutation()
	_test_runtime_restore_rejection_is_atomic()
	_test_runtime_partial_restore_rejection_rolls_back_exactly()
	_test_reset_is_safe_with_and_without_runtime()
	_suite.finish(get_tree())


func _test_unconfigured_coordinator_is_a_monotonic_no_op() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	var initial: Dictionary = coordinator.snapshot()
	_suite.assert_equal(initial.get("last_runtime_frame"), -1, "new coordinator starts before frame zero")
	_suite.assert_equal(initial.get("revision"), 0, "new coordinator starts at revision zero")
	_suite.assert_true(not bool(initial.get("runtime_configured", true)), "new coordinator has no runtime")

	var frame_zero: Dictionary = coordinator.advance_frame(0)
	_suite.assert_true(bool(frame_zero.get("ok", false)), "frame zero is accepted without a runtime")
	_suite.assert_equal(
		frame_zero.get("code"),
		CharacterActionContractScript.CODE_NO_RUNTIME,
		"unconfigured advancement reports an explicit no-op"
	)
	_suite.assert_equal(frame_zero.get("events"), [], "unconfigured advancement publishes no events")
	_suite.assert_equal(coordinator.snapshot().get("last_runtime_frame"), 0, "no-op advancement owns the frame cursor")

	var frame_three: Dictionary = coordinator.advance_frame(3)
	_suite.assert_true(bool(frame_three.get("ok", false)), "strictly newer frames may skip forward")
	var before_rejections: Dictionary = coordinator.snapshot()
	for invalid_frame: Variant in [3, 2, -1, 4.0, "4"]:
		var rejected: Dictionary = coordinator.advance_frame(invalid_frame)
		_suite.assert_true(not bool(rejected.get("ok", true)), "invalid or stale frame %s is rejected" % str(invalid_frame))
		_suite.assert_equal(coordinator.snapshot(), before_rejections, "rejected frame leaves no-op state unchanged")


func _test_configure_rejects_incomplete_runtime_without_mutation() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	coordinator.advance_frame(5)
	var before: Dictionary = coordinator.snapshot()
	_suite.assert_true(not coordinator.configure(null), "null is not a configured runtime")
	_suite.assert_true(not coordinator.configure(IncompleteRuntime.new()), "runtime contract must be complete")
	_suite.assert_equal(coordinator.snapshot(), before, "failed configure is atomic")


func _test_configured_runtime_receives_authoritative_frame_context() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "complete future runtime configures")
	var caller_context := {"payload": {"value": 7}}
	var advanced: Dictionary = coordinator.advance_frame(12, caller_context)
	_suite.assert_true(bool(advanced.get("ok", false)), "configured runtime advances")
	_suite.assert_equal(advanced.get("code"), CharacterActionContractScript.CODE_OK, "configured runtime reports OK")
	_suite.assert_equal(runtime.last_runtime_frame, 12, "runtime receives the authoritative integer frame")
	_suite.assert_equal(
		(runtime.received_contexts[0] as Dictionary).get("runtime_frame"),
		12,
		"coordinator injects runtime_frame into runtime context"
	)
	_suite.assert_equal(
		advanced.get("events"),
		[{"type": "character_runtime_advanced", "runtime_frame": 12, "payload": {"value": 7}}],
		"runtime events are returned through the coordinator"
	)
	caller_context.payload.value = 99
	(advanced["events"] as Array)[0].payload.value = 88
	_suite.assert_equal(
		(runtime.received_contexts[0] as Dictionary).payload.value,
		7,
		"caller and returned event mutation cannot rewrite runtime input history"
	)


func _test_invalid_advance_inputs_fail_without_mutation() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "runtime configures for invalid-input coverage")
	var before: Dictionary = coordinator.snapshot()
	var reserved_frame: Dictionary = coordinator.advance_frame(1, {"runtime_frame": 1})
	_suite.assert_true(not bool(reserved_frame.get("ok", true)), "caller cannot spoof the reserved frame field")
	_suite.assert_equal(
		reserved_frame.get("code"),
		CharacterActionContractScript.CODE_INVALID_CONTEXT,
		"reserved frame field has a stable refusal code"
	)
	_suite.assert_equal(coordinator.snapshot(), before, "reserved context rejection is atomic")

	var wrong_context: Dictionary = coordinator.advance_frame(1, ["not", "a", "dictionary"])
	_suite.assert_true(not bool(wrong_context.get("ok", true)), "non-dictionary context is rejected")
	_suite.assert_equal(coordinator.snapshot(), before, "invalid context type leaves coordinator and runtime unchanged")


func _test_malformed_runtime_events_roll_back_exactly() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "runtime configures for rollback coverage")
	var before: Dictionary = coordinator.snapshot()
	runtime.return_malformed_events = true
	var rejected: Dictionary = coordinator.advance_frame(1, {"payload": {"value": 3}})
	_suite.assert_true(not bool(rejected.get("ok", true)), "malformed runtime event result is rejected")
	_suite.assert_equal(
		rejected.get("code"),
		CharacterActionContractScript.CODE_RUNTIME_REJECTED,
		"malformed runtime events have a stable refusal code"
	)
	_suite.assert_equal(coordinator.snapshot(), before, "failed runtime advancement restores both participant snapshots")


func _test_two_phase_frame_can_commit_or_roll_back_exactly() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "runtime configures for two-phase frame coverage")
	var before: Dictionary = coordinator.snapshot()
	var prepared: Dictionary = coordinator.prepare_frame_advance(4, {"payload": {"value": 4}})
	_suite.assert_true(bool(prepared.get("ok", false)), "two-phase frame prepares")
	_suite.assert_equal(coordinator.runtime_frame(), -1, "prepare does not publish the coordinator frame")
	_suite.assert_equal(runtime.last_runtime_frame, 4, "prepare stages the runtime mutation")
	_suite.assert_true(coordinator.rollback_prepared_frame(), "prepared frame rolls back")
	_suite.assert_equal(coordinator.snapshot(), before, "prepared rollback restores the exact coordinator and runtime state")

	_suite.assert_true(
		bool(coordinator.prepare_frame_advance(4, {"payload": {"value": 4}}).get("ok", false)),
		"rolled-back frame can prepare again"
	)
	var committed: Dictionary = coordinator.commit_prepared_frame()
	_suite.assert_true(bool(committed.get("ok", false)), "prepared frame commits")
	_suite.assert_equal(coordinator.runtime_frame(), 4, "commit publishes the staged frame")
	_suite.assert_equal(runtime.last_runtime_frame, 4, "commit preserves the staged runtime state")


func _test_two_phase_commit_rejects_runtime_drift() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "runtime configures for staged drift coverage")
	var before: Dictionary = coordinator.snapshot()
	_suite.assert_true(
		bool(coordinator.prepare_frame_advance(3, {"payload": {"value": 3}}).get("ok", false)),
		"staged drift fixture prepares"
	)
	runtime.last_runtime_frame = 99
	runtime.revision += 1
	var rejected: Dictionary = coordinator.commit_prepared_frame()
	_suite.assert_true(not bool(rejected.get("ok", true)), "runtime drift rejects staged commit")
	_suite.assert_equal(
		rejected.get("code"),
		CharacterActionContractScript.CODE_RUNTIME_REJECTED,
		"runtime drift has a stable rejection code"
	)
	_suite.assert_equal(coordinator.snapshot(), before, "runtime drift restores the exact pre-prepare state")


func _test_unconfigured_runtime_frame_can_reanchor() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	_suite.assert_true(coordinator.reanchor_unconfigured_runtime_frame(20), "base coordinator reanchors")
	_suite.assert_equal(coordinator.runtime_frame(), 20, "reanchor installs the nonzero compatible frame")
	_suite.assert_true(not coordinator.reanchor_unconfigured_runtime_frame(-2), "invalid reanchor frame is rejected")
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "runtime configures after compatible reanchor")
	_suite.assert_true(
		not coordinator.reanchor_unconfigured_runtime_frame(30),
		"configured character runtime cannot be silently reanchored"
	)


func _test_snapshot_is_deep_isolated() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "runtime configures for isolation coverage")
	coordinator.advance_frame(1, {"payload": {"value": 4}})
	var value: Dictionary = coordinator.snapshot()
	(value["runtime"] as Dictionary).received_contexts[0].payload.value = 100
	value["last_runtime_frame"] = 100
	_suite.assert_equal(coordinator.snapshot().get("last_runtime_frame"), 1, "snapshot scalar mutation is isolated")
	_suite.assert_equal(
		(coordinator.snapshot()["runtime"] as Dictionary).received_contexts[0].payload.value,
		4,
		"snapshot nested mutation is isolated"
	)


func _test_unconfigured_snapshot_round_trip_restores_exact_state() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	coordinator.advance_frame(1)
	var target: Dictionary = coordinator.snapshot()
	coordinator.advance_frame(6)
	_suite.assert_true(
		coordinator.can_restore_snapshot(target),
		"no-runtime base snapshot is restorable"
	)
	_suite.assert_true(coordinator.restore_snapshot(target), "no-runtime base snapshot restores")
	_suite.assert_equal(
		coordinator.snapshot(),
		target,
		"no-runtime restore installs frame and revision exactly"
	)


func _test_snapshot_round_trip_restores_exact_state() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "runtime configures for restore coverage")
	coordinator.advance_frame(2, {"payload": {"value": 2}})
	var target: Dictionary = coordinator.snapshot()
	coordinator.advance_frame(7, {"payload": {"value": 7}})
	_suite.assert_true(coordinator.can_restore_snapshot(target), "prior complete snapshot is restorable")
	_suite.assert_true(coordinator.restore_snapshot(target), "prior complete snapshot restores")
	_suite.assert_equal(coordinator.snapshot(), target, "restore installs frame, revision, and runtime exactly")


func _test_invalid_snapshots_fail_without_mutation() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "runtime configures for snapshot validation")
	coordinator.advance_frame(3)
	var valid: Dictionary = coordinator.snapshot()
	var missing := valid.duplicate(true)
	missing.erase("runtime")
	var unknown := valid.duplicate(true)
	unknown["unknown"] = true
	var future_revision := valid.duplicate(true)
	future_revision["revision"] = int(valid["revision"]) + 1
	var future_frame := valid.duplicate(true)
	future_frame["last_runtime_frame"] = 4
	var mismatched_configuration := valid.duplicate(true)
	mismatched_configuration["runtime_configured"] = false
	mismatched_configuration["runtime"] = {}
	var invalid_values: Array[Dictionary] = [
		missing,
		unknown,
		future_revision,
		future_frame,
		mismatched_configuration,
	]
	var before: Dictionary = coordinator.snapshot()
	for index: int in range(invalid_values.size()):
		_suite.assert_true(
			not coordinator.can_restore_snapshot(invalid_values[index]),
			"invalid snapshot %d cannot restore" % index
		)
		_suite.assert_true(
			not coordinator.restore_snapshot(invalid_values[index]),
			"invalid snapshot %d restore fails" % index
		)
		_suite.assert_equal(coordinator.snapshot(), before, "invalid snapshot restore is atomic")


func _test_runtime_restore_rejection_is_atomic() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "runtime configures for restore rejection")
	coordinator.advance_frame(1)
	var target: Dictionary = coordinator.snapshot()
	coordinator.advance_frame(2)
	var before: Dictionary = coordinator.snapshot()
	runtime.reject_restore = true
	_suite.assert_true(not coordinator.restore_snapshot(target), "runtime may reject a staged restore")
	_suite.assert_equal(coordinator.snapshot(), before, "runtime restore rejection leaves live state exact")


func _test_runtime_partial_restore_rejection_rolls_back_exactly() -> void:
	var coordinator = CharacterActionCoordinatorScript.new()
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "runtime configures for partial restore rejection")
	coordinator.advance_frame(1)
	var target: Dictionary = coordinator.snapshot()
	coordinator.advance_frame(2)
	var before: Dictionary = coordinator.snapshot()
	runtime.mutate_then_reject_restore_once = true
	_suite.assert_true(not coordinator.restore_snapshot(target), "partially mutating runtime rejection fails")
	_suite.assert_equal(coordinator.snapshot(), before, "partial runtime rejection restores the exact live state")


func _test_reset_is_safe_with_and_without_runtime() -> void:
	var no_runtime = CharacterActionCoordinatorScript.new()
	no_runtime.advance_frame(4)
	_suite.assert_true(no_runtime.reset_runtime_state(&"new_run"), "unconfigured reset is safe")
	_suite.assert_equal(no_runtime.snapshot().get("last_runtime_frame"), -1, "unconfigured reset clears the frame cursor")
	var no_runtime_after_reset: Dictionary = no_runtime.snapshot()
	_suite.assert_true(not no_runtime.reset_runtime_state(&""), "empty reset reason is rejected")
	_suite.assert_equal(no_runtime.snapshot(), no_runtime_after_reset, "invalid reset reason is atomic")

	var coordinator = CharacterActionCoordinatorScript.new()
	var runtime := FakeCharacterRuntime.new()
	_suite.assert_true(coordinator.configure(runtime), "runtime configures for reset coverage")
	coordinator.advance_frame(9)
	_suite.assert_true(coordinator.reset_runtime_state(&"loadout_replacement"), "configured reset succeeds")
	_suite.assert_equal(coordinator.snapshot().get("last_runtime_frame"), -1, "configured reset clears coordinator frame")
	_suite.assert_equal(runtime.last_runtime_frame, -1, "configured reset reaches runtime")
	_suite.assert_equal(runtime.reset_reasons, [&"loadout_replacement"], "runtime receives the typed reset reason")
	_suite.assert_true(bool(coordinator.snapshot().get("runtime_configured", false)), "reset preserves runtime configuration")
