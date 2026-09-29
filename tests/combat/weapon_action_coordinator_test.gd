extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")
const WeaponActionCoordinatorScript := preload("res://scripts/combat/weapons/weapon_action_coordinator.gd")
const WeaponRuntimeScript := preload("res://scripts/combat/weapons/weapon_runtime.gd")


class FakeWeaponRuntime:
	extends WeaponRuntimeScript

	var resource: int = 8
	var active_token: int = 0
	var active_action: StringName = &""
	var reject_secondary: bool = false
	var fail_commit_action: StringName = &""
	var fail_restore: bool = false
	var fail_active_entry: bool = false
	var commit_attempts: int = 0
	var cancel_calls: int = 0
	var finish_calls: int = 0
	var phase_entries: Array[Dictionary] = []


	func weapon_id() -> StringName:
		return &"test_weapon"


	func capabilities() -> PackedStringArray:
		return PackedStringArray(["weapon.damage"])


	func plan_intent(intent: Dictionary, _context: Dictionary) -> Dictionary:
		var intent_id := StringName(str(intent.get("id", "")))
		if intent_id == &"weapon_secondary" and reject_secondary:
			return {"ok": false, "code": &"UNSUPPORTED_INTENT"}
		if intent_id == &"weapon_utility":
			return {
				"ok": true,
				"plan": {
					"weapon_id": "test_weapon",
					"action_id": "invalid_nan",
					"phases": [{
						"phase": "WINDUP",
						"duration_frames": 1,
						"movement_multiplier": NAN,
					}],
					"payloads": [],
				},
			}
		if intent_id == &"weapon_skill":
			var unsafe_plan := _action_plan(intent_id)
			unsafe_plan["unsafe_scalar"] = NAN
			return {"ok": true, "plan": unsafe_plan}
		return {"ok": true, "plan": _action_plan(intent_id)}


	func commit_action(plan: Dictionary, token: int) -> Dictionary:
		commit_attempts += 1
		resource -= 1
		if StringName(str(plan.get("action_id", ""))) == fail_commit_action:
			return {"ok": false, "code": &"PAYLOAD_CONSTRUCTION_FAILED"}
		active_token = token
		active_action = StringName(str(plan.get("action_id", "")))
		return {"ok": true, "context": {"resource": resource}}


	func on_phase_enter(_plan: Dictionary, phase: StringName, token: int) -> Array[Dictionary]:
		phase_entries.append({"phase": str(phase), "token": token})
		if phase == &"ACTIVE" and fail_active_entry:
			return [{"type": "phase_failed", "reason": "test_active_failure"}]
		return []


	func cancel_action(token: int, _reason: StringName) -> void:
		if active_token != token:
			return
		cancel_calls += 1
		active_token = 0
		active_action = &""


	func finish_action(token: int) -> void:
		if active_token != token:
			return
		finish_calls += 1
		active_token = 0
		active_action = &""


	func reset_runtime_state(_reason: StringName) -> void:
		resource = 8
		active_token = 0
		active_action = &""


	func snapshot() -> Dictionary:
		return {
			"resource": resource,
			"active_token": active_token,
			"active_action": str(active_action),
		}


	func restore_snapshot(runtime_snapshot: Dictionary) -> bool:
		if fail_restore:
			return false
		if (
			typeof(runtime_snapshot.get("resource")) != TYPE_INT
			or typeof(runtime_snapshot.get("active_token")) != TYPE_INT
			or typeof(runtime_snapshot.get("active_action")) != TYPE_STRING
		):
			return false
		resource = int(runtime_snapshot["resource"])
		active_token = int(runtime_snapshot["active_token"])
		active_action = StringName(str(runtime_snapshot["active_action"]))
		return true


	func presentation_snapshot() -> Dictionary:
		return {
			"resource": resource,
			"active_action": str(active_action),
		}


	func _action_plan(intent_id: StringName) -> Dictionary:
		var action_id := &"primary_test" if intent_id == &"weapon_primary" else &"secondary_test"
		return {
			"weapon_id": "test_weapon",
			"action_id": str(action_id),
			"phases": [
				{
					"phase": "WINDUP",
					"duration_frames": 6,
					"movement_multiplier": 0.5,
				},
				{
					"phase": "ACTIVE",
					"duration_frames": 2,
					"movement_multiplier": 0.5,
				},
				{
					"phase": "RECOVERY",
					"duration_frames": 4,
					"cancel_from_frame": 2,
					"movement_multiplier": 0.5,
				},
			],
			"payloads": [{
				"descriptor_id": "test_hitbox",
				"damage_multiplier": 1.0,
			}],
		}


var _suite
var _committed_facts: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_rejected_plan_is_atomic()
	_test_failed_commit_restores_runtime_and_coordinator()
	_test_failed_commit_with_failed_rollback_resets_safe()
	_test_phase_failure_cancels_safe()
	_test_windup_active_recovery_and_cancel_boundary()
	_test_buffer_consumption_can_be_deferred_for_external_priority()
	_test_short_buffer_expires_before_cancel_window()
	_test_cancel_invalidates_stale_tokens_idempotently()
	_test_snapshot_is_isolated_and_safe_restore_is_generation_safe()
	_test_contract_rejects_non_finite_plans()
	_test_contract_rejects_non_finite_plan_metadata()
	_suite.finish(get_tree())


func _test_rejected_plan_is_atomic() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	runtime.reject_secondary = true
	var before: Dictionary = coordinator.snapshot()

	var result: Dictionary = coordinator.submit_intent(
		{"id": "weapon_secondary", "edge": "pressed"},
		{"source": "atomic_rejection"}
	)

	_suite.assert_true(not bool(result.get("ok", false)), "rejected plan reports failure")
	_suite.assert_equal(coordinator.snapshot(), before, "rejected plan leaves the coordinator snapshot unchanged")
	_suite.assert_equal(runtime.commit_attempts, 0, "rejected plan never enters runtime commit")
	_suite.assert_equal(_committed_facts.size(), 0, "rejected plan publishes no committed fact")


func _test_failed_commit_restores_runtime_and_coordinator() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	runtime.fail_commit_action = &"primary_test"
	var before: Dictionary = coordinator.snapshot()
	var resource_before := runtime.resource

	var result: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{"source": "commit_rollback"}
	)

	_suite.assert_true(not bool(result.get("ok", false)), "failed commit reports failure")
	_suite.assert_equal(runtime.commit_attempts, 1, "runtime commit was attempted exactly once")
	_suite.assert_equal(runtime.resource, resource_before, "failed commit restores runtime resource state")
	_suite.assert_equal(coordinator.snapshot(), before, "failed commit restores the coordinator snapshot")
	_suite.assert_equal(_committed_facts.size(), 0, "failed commit publishes no committed fact")


func _test_failed_commit_with_failed_rollback_resets_safe() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{"source": "rollback_failure_fixture"}
	)
	_advance(coordinator, 10)
	var old_token := int(committed.get("token", 0))
	var generation_before := int(coordinator.generation())
	runtime.fail_commit_action = &"secondary_test"
	runtime.fail_restore = true

	var result: Dictionary = coordinator.submit_intent(
		{"id": "weapon_secondary", "edge": "pressed"},
		{"source": "rollback_failure"}
	)

	_suite.assert_true(not bool(result.get("ok", false)), "failed rollback still reports a rejected commit")
	_suite.assert_equal(result.get("code"), WeaponActionContractScript.CODE_COMMIT_FAILED, "failed rollback uses the commit failure code")
	_suite.assert_equal(result.get("context", {}).get("reason"), "rollback_failed", "failed rollback is explicit")
	_suite.assert_equal(runtime.resource, 8, "failed rollback resets runtime resources to a safe baseline")
	_suite.assert_equal(runtime.active_token, 0, "failed rollback leaves no runtime action token")
	_suite.assert_equal(coordinator.phase_name(), &"READY", "failed rollback leaves the coordinator ready")
	_suite.assert_equal(coordinator.current_token(), 0, "failed rollback leaves no coordinator token")
	_suite.assert_true(coordinator.generation() > generation_before, "failed rollback invalidates the replaced action generation")
	_suite.assert_true(not coordinator.is_action_token_current(old_token, generation_before), "failed rollback cannot revive the replaced token")
	_suite.assert_equal(_committed_facts.size(), 1, "failed replacement publishes no additional committed fact")


func _test_phase_failure_cancels_safe() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	runtime.fail_active_entry = true
	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	var token := int(committed.get("token", 0))
	var generation := int(committed.get("generation", 0))
	_advance(coordinator, 6)
	_suite.assert_equal(coordinator.phase_name(), &"READY", "phase failure returns coordinator to ready")
	_suite.assert_equal(coordinator.current_token(), 0, "phase failure clears the action token")
	_suite.assert_true(coordinator.generation() > generation, "phase failure invalidates the action generation")
	_suite.assert_true(not coordinator.is_action_token_current(token, generation), "phase failure cannot retain a stale token")
	_suite.assert_equal(runtime.cancel_calls, 1, "phase failure cancels the runtime exactly once")


func _test_windup_active_recovery_and_cancel_boundary() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]

	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{"aim": Vector2.RIGHT}
	)
	_suite.assert_true(bool(committed.get("ok", false)), "primary action commits")
	_suite.assert_equal(coordinator.phase_name(), &"WINDUP", "commit begins in windup")
	_suite.assert_equal(_committed_facts.size(), 1, "initial commit publishes one fact")
	var first_token := int(committed.get("token", 0))

	_advance(coordinator, 5)
	_suite.assert_equal(coordinator.phase_name(), &"WINDUP", "windup remains active before its half-open end")
	coordinator.advance_frame()
	_suite.assert_equal(coordinator.phase_name(), &"ACTIVE", "windup transitions to active on frame six")

	var buffered: Dictionary = coordinator.submit_intent(
		{"id": "weapon_secondary", "edge": "pressed"},
		{"aim": Vector2.DOWN}
	)
	_suite.assert_true(bool(buffered.get("ok", false)), "secondary intent buffers during active")
	_suite.assert_equal(buffered.get("code"), &"BUFFERED", "busy submission reports buffered status")
	_suite.assert_equal(_committed_facts.size(), 1, "buffering publishes no committed fact")

	_advance(coordinator, 2)
	_suite.assert_equal(coordinator.phase_name(), &"RECOVERY", "active advances to recovery")
	_suite.assert_true(not coordinator.recovery_cancel_is_open(), "recovery cancel remains closed before its boundary")
	var recovery_presentation: Dictionary = coordinator.presentation_snapshot()
	_suite.assert_equal(recovery_presentation.get("cancel_from_frame"), 2, "presentation exposes the authoritative recovery cancel frame")
	coordinator.advance_frame()
	_suite.assert_equal(coordinator.phase_name(), &"RECOVERY", "buffer waits before the recovery cancel frame")
	_suite.assert_true(not coordinator.recovery_cancel_is_open(), "first recovery frame remains outside the cancel window")
	_suite.assert_equal(_committed_facts.size(), 1, "waiting buffer still publishes no fact")
	coordinator.advance_frame()

	_suite.assert_equal(coordinator.phase_name(), &"WINDUP", "buffered action takes authority at the cancel boundary")
	_suite.assert_equal(runtime.cancel_calls, 1, "replaced action is cancelled exactly once")
	_suite.assert_equal(_committed_facts.size(), 2, "buffered action publishes exactly one additional fact")
	_suite.assert_true(int(_committed_facts[1]["token"]) > first_token, "replacement receives a new immutable token")
	_suite.assert_equal(str(_committed_facts[1]["action_id"]), "secondary_test", "replacement fact identifies the buffered action")

	_advance(coordinator, 12)
	_suite.assert_equal(coordinator.phase_name(), &"READY", "replacement finishes through all declared phases")
	_suite.assert_equal(runtime.finish_calls, 1, "completed replacement finishes exactly once")
	_suite.assert_equal(
		_phase_names(runtime.phase_entries),
		["WINDUP", "ACTIVE", "RECOVERY", "WINDUP", "ACTIVE", "RECOVERY"],
		"each committed action enters each declared phase exactly once"
	)


func _test_buffer_consumption_can_be_deferred_for_external_priority() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	coordinator.submit_intent({"id": "weapon_secondary", "edge": "pressed", "buffer_frames": 20}, {})
	_advance(coordinator, 8)
	_suite.assert_equal(coordinator.phase_name(), &"RECOVERY", "deferred fixture reaches recovery")
	var original_token := int(coordinator.current_token())
	coordinator.advance_frame(false)
	coordinator.advance_frame(false)
	_suite.assert_true(coordinator.recovery_cancel_is_open(), "deferred fixture reaches the cancel boundary")
	_suite.assert_equal(coordinator.current_token(), original_token, "deferred advancement does not auto-commit the buffered weapon action")
	_suite.assert_true(coordinator.consume_buffered_intent(), "external owner can release the buffered weapon action after priority arbitration")
	_suite.assert_true(coordinator.current_token() != original_token, "released buffered action receives a new token")
	_suite.assert_equal(coordinator.phase_name(), &"WINDUP", "released buffered action begins after arbitration")


func _test_short_buffer_expires_before_cancel_window() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	var buffered: Dictionary = coordinator.submit_intent(
		{"id": "weapon_secondary", "edge": "pressed", "buffer_frames": 2},
		{}
	)
	_suite.assert_true(bool(buffered.get("ok", false)), "short-lived intent buffers")
	_advance(coordinator, 8)
	_suite.assert_equal(coordinator.phase_name(), &"RECOVERY", "first action reaches recovery after short buffer expires")
	_advance(coordinator, 4)
	_suite.assert_equal(coordinator.phase_name(), &"READY", "expired buffer does not start another action")
	_suite.assert_equal(_committed_facts.size(), 1, "expired buffer publishes no committed fact")


func _test_cancel_invalidates_stale_tokens_idempotently() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var committed: Dictionary = coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	var old_token := int(committed.get("token", 0))
	var old_generation := int(coordinator.snapshot().get("generation", 0))
	_suite.assert_true(coordinator.is_action_token_current(old_token, old_generation), "fresh token is current")

	coordinator.cancel(&"test_cancel")
	_suite.assert_equal(coordinator.phase_name(), &"READY", "cancel returns coordinator to ready")
	_suite.assert_true(not coordinator.is_action_token_current(old_token, old_generation), "cancel invalidates stale token and generation")
	_suite.assert_equal(runtime.cancel_calls, 1, "active runtime receives one cancellation")
	coordinator.cancel(&"test_cancel_again")
	_suite.assert_equal(runtime.cancel_calls, 1, "repeated cancellation is idempotent for the runtime")


func _test_snapshot_is_isolated_and_safe_restore_is_generation_safe() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var safe_snapshot: Dictionary = coordinator.snapshot()
	var exposed_runtime: Dictionary = safe_snapshot["runtime"]
	exposed_runtime["resource"] = -999
	_suite.assert_equal(runtime.resource, 8, "mutating an exposed snapshot cannot mutate runtime state")

	var committed: Dictionary = coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	var active_snapshot: Dictionary = coordinator.snapshot()
	var before_unsafe_restore: Dictionary = coordinator.snapshot()
	_suite.assert_true(not coordinator.restore_safe(active_snapshot), "unsafe mid-action snapshot is rejected")
	_suite.assert_equal(coordinator.snapshot(), before_unsafe_restore, "unsafe restore rejection is atomic")

	coordinator.cancel(&"restore_fixture")
	var generation_before_restore := int(coordinator.snapshot()["generation"])
	_suite.assert_true(coordinator.restore_safe(_fixture()["coordinator"].snapshot()), "ready snapshot restores safely")
	_suite.assert_equal(coordinator.phase_name(), &"READY", "safe restore remains ready")
	_suite.assert_equal(runtime.resource, 8, "safe restore restores runtime state")
	_suite.assert_true(int(coordinator.snapshot()["generation"]) > generation_before_restore, "safe restore advances generation")
	_suite.assert_true(
		not coordinator.is_action_token_current(int(committed.get("token", 0)), generation_before_restore),
		"safe restore cannot revive a prior action token"
	)


func _test_contract_rejects_non_finite_plans() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var before: Dictionary = coordinator.snapshot()
	var result: Dictionary = coordinator.submit_intent({"id": "weapon_utility", "edge": "pressed"}, {})

	_suite.assert_true(not bool(result.get("ok", false)), "non-finite plan is rejected")
	_suite.assert_equal(result.get("code"), WeaponActionContractScript.CODE_INVALID_PLAN, "contract reports invalid plan")
	_suite.assert_equal(runtime.commit_attempts, 0, "invalid plan never reaches commit")
	_suite.assert_equal(coordinator.snapshot(), before, "invalid plan rejection preserves state")


func _test_contract_rejects_non_finite_plan_metadata() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var before: Dictionary = coordinator.snapshot()
	var result: Dictionary = coordinator.submit_intent({"id": "weapon_skill", "edge": "pressed"}, {})

	_suite.assert_true(not bool(result.get("ok", false)), "non-finite top-level plan metadata is rejected")
	_suite.assert_equal(result.get("code"), WeaponActionContractScript.CODE_INVALID_PLAN, "metadata rejection uses the plan contract code")
	_suite.assert_equal(runtime.commit_attempts, 0, "non-finite metadata never reaches commit")
	_suite.assert_equal(coordinator.snapshot(), before, "metadata rejection preserves coordinator state")


func _fixture() -> Dictionary:
	_committed_facts.clear()
	var runtime := FakeWeaponRuntime.new()
	var coordinator = WeaponActionCoordinatorScript.new()
	_suite.assert_true(coordinator.configure(runtime), "coordinator accepts a weapon runtime fixture")
	coordinator.weapon_action_committed.connect(_on_weapon_action_committed)
	return {"coordinator": coordinator, "runtime": runtime}


func _advance(coordinator: RefCounted, frames: int) -> void:
	for _frame: int in range(frames):
		coordinator.advance_frame()


func _phase_names(entries: Array[Dictionary]) -> Array[String]:
	var names: Array[String] = []
	for entry: Dictionary in entries:
		names.append(str(entry.get("phase", "")))
	return names


func _on_weapon_action_committed(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	context: Dictionary
) -> void:
	_committed_facts.append({
		"weapon_id": str(weapon_id),
		"action_id": str(action_id),
		"token": token,
		"context": context.duplicate(true),
	})
