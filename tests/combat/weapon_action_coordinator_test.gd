extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponActionContractScript := preload("res://scripts/combat/weapons/weapon_action_contract.gd")
const WeaponActionCoordinatorScript := preload("res://scripts/combat/weapons/weapon_action_coordinator.gd")
const WeaponResourceTransactionScript := preload("res://scripts/combat/weapons/weapon_resource_transaction.gd")
const WeaponRuntimeScript := preload("res://scripts/combat/weapons/weapon_runtime.gd")


class FakeResourceProvider extends RefCounted:
	var current: float = 100.0
	var revision: int = 1
	var spend_calls: int = 0
	var reject_commit: bool = false
	var fail_restore: bool = false
	var fail_restore_on_calls: Array[int] = []
	var restore_calls: int = 0


	func resource_state(resource_id: StringName) -> Dictionary:
		if resource_id != &"time_energy":
			return {"ok": false, "code": &"RESOURCE_NOT_FOUND", "context": {}}
		return {
			"ok": true,
			"code": &"OK",
			"resource_id": "time_energy",
			"current": current,
			"minimum": 0.0,
			"maximum": 100.0,
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
		if reject_commit:
			return {"ok": false, "code": &"PROVIDER_REJECTED", "context": {}}
		if resource_id != &"time_energy" or expected_revision != revision or current < amount:
			return {"ok": false, "code": &"RESOURCE_COMMIT_FAILED", "context": {}}
		var before := current
		current -= amount
		revision += 1
		return {
			"ok": true,
			"code": &"OK",
			"resource_id": "time_energy",
			"before": before,
			"after": current,
			"revision": revision,
			"context": {},
		}


	func restore_resource_state(resource_id: StringName, state: Dictionary) -> bool:
		restore_calls += 1
		if (
			resource_id != &"time_energy"
			or str(state.get("resource_id", "")) != "time_energy"
			or typeof(state.get("current")) not in [TYPE_INT, TYPE_FLOAT]
			or float(state.get("current", -1.0)) < 0.0
			or float(state.get("current", -1.0)) > 100.0
			or float(state.get("minimum", -1.0)) != 0.0
			or float(state.get("maximum", -1.0)) != 100.0
			or typeof(state.get("revision")) != TYPE_INT
			or int(state.get("revision", 0)) <= 0
		):
			return false
		if fail_restore or fail_restore_on_calls.has(restore_calls):
			return false
		current = float(state["current"])
		revision = int(state["revision"])
		return true


class FakeWeaponRuntime:
	extends WeaponRuntimeScript

	var resource: int = 8
	var active_token: int = 0
	var active_action: StringName = &""
	var reject_secondary: bool = false
	var fail_commit_action: StringName = &""
	var fail_restore: bool = false
	var fail_restore_on_calls: Array[int] = []
	var drift_restore_on_calls: Array[int] = []
	var fail_active_entry: bool = false
	var fail_phase_entry: StringName = &""
	var tamper_finalized_field: StringName = &""
	var return_channel_utility: bool = false
	var return_reload_utility: bool = false
	var return_hold_release_variant: bool = false
	var tamper_release_fingerprint: bool = false
	var malformed_live_tail: bool = false
	var reject_unsupported_sword_semantics: bool = false
	var commit_attempts: int = 0
	var cancel_calls: int = 0
	var finish_calls: int = 0
	var hold_release_calls: int = 0
	var released_hold_frames: Array[int] = []
	var phase_entries: Array[Dictionary] = []
	var action_cooldown_frames: int = 0
	var external_resource_cost: float = 0.0
	var live_confirm_calls: int = 0
	var live_confirm_phase: StringName = &""
	var live_confirm_frame: int = -1
	var runtime_tick_frames: Array[int] = []
	var restore_calls: int = 0
	var reset_calls: int = 0
	var last_reset_reason: StringName = &""
	var gameplay_rewind_cancel_calls: int = 0
	var gameplay_rewind_restore_calls: int = 0
	var fail_gameplay_rewind_cancel: bool = false
	var fail_gameplay_rewind_restore: bool = false
	var mutate_before_failed_gameplay_rewind_cancel: bool = false
	var mutate_before_failed_gameplay_rewind_restore: bool = false
	var committed_payload_guard: Dictionary = {
		"instance_ids": [101],
		"snapshots": [{"payload_id": "committed_fixture", "hit_claims": ["enemy:a"]}],
	}


	func weapon_id() -> StringName:
		return &"test_weapon"


	func capabilities() -> PackedStringArray:
		return PackedStringArray(["weapon.damage"])


	func plan_intent(intent: Dictionary, _context: Dictionary) -> Dictionary:
		var intent_id := StringName(str(intent.get("id", "")))
		if (
			reject_unsupported_sword_semantics
			and intent_id in [&"weapon_utility", &"weapon_skill", &"weapon_ultimate"]
		):
			return {"ok": false, "code": &"UNSUPPORTED_INTENT", "context": {"intent_id": str(intent_id)}}
		if intent_id == &"weapon_secondary" and reject_secondary:
			return {"ok": false, "code": &"UNSUPPORTED_INTENT"}
		if intent_id == &"weapon_utility" and return_reload_utility:
			return {"ok": true, "plan": _reload_plan()}
		if intent_id == &"weapon_utility" and return_channel_utility:
			return {"ok": true, "plan": _channel_plan()}
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
		if phase == fail_phase_entry:
			return [{"type": "phase_failed", "reason": "test_immediate_phase_failure"}]
		if phase == &"ACTIVE" and fail_active_entry:
			return [{"type": "phase_failed", "reason": "test_active_failure"}]
		if phase == &"ACTIVE":
			return [
				{"type": "payload_released", "token": token},
				{"type": "cue_requested", "token": token},
			]
		return []


	func release_hold(plan: Dictionary, token: int, held_frames: int) -> Dictionary:
		if active_token != token:
			return {"ok": false, "code": &"STALE_TOKEN"}
		hold_release_calls += 1
		released_hold_frames.append(held_frames)
		var finalized_plan := plan.duplicate(true)
		var finalized_phases: Array = finalized_plan.get("phases", [])
		finalized_phases.pop_front()
		finalized_plan["phases"] = finalized_phases
		finalized_plan["held_frames"] = held_frames
		if return_hold_release_variant:
			finalized_plan["action_id"] = "aimed_test"
			finalized_plan["release_action_fingerprint"] = (
				"tampered"
				if tamper_release_fingerprint
				else "aimed-test-v1"
			)
		match tamper_finalized_field:
			&"weapon_id":
				finalized_plan["weapon_id"] = "tampered_weapon"
			&"action_id":
				finalized_plan["action_id"] = "tampered_action"
			&"profile_id":
				finalized_plan["profile_id"] = "tampered_profile"
			&"profile_version":
				finalized_plan["profile_version"] = 2
		return {
			"ok": true,
			"code": &"OK",
			"finalized_plan": finalized_plan,
			"context": {"held_frames": held_frames},
		}


	func handle_live_intent(
		_plan: Dictionary,
		_token: int,
		phase: StringName,
		phase_frame: int,
		intent: Dictionary,
		_context: Dictionary
	) -> Dictionary:
		if not return_reload_utility or StringName(str(intent.get("id", ""))) != &"weapon_utility":
			return {"handled": false}
		live_confirm_calls += 1
		live_confirm_phase = phase
		live_confirm_frame = phase_frame
		if phase != &"RESOURCE_ACTION" or phase_frame != 2:
			return {"handled": true, "ok": false, "code": &"RELOAD_CONFIRM_OUTSIDE_WINDOW"}
		resource = 99 if malformed_live_tail else 7
		var recovery_duration := 0 if malformed_live_tail else 4
		return {
			"handled": true,
			"ok": true,
			"replacement_phases": [{
				"phase": "RECOVERY",
				"duration_frames": recovery_duration,
				"movement_multiplier": 0.65,
			}],
			"context": {"perfect_reload": true},
		}


	func advance_runtime_frame(coordinator_frame: int) -> Array[Dictionary]:
		runtime_tick_frames.append(coordinator_frame)
		return []


	func cancel_action(token: int, _reason: StringName) -> void:
		if active_token != token:
			return
		cancel_calls += 1
		active_token = 0
		active_action = &""


	func cancel_for_gameplay_rewind(
		token: int,
		_reason: StringName,
		hold_runtime_snapshot: Dictionary = {}
	) -> bool:
		gameplay_rewind_cancel_calls += 1
		if mutate_before_failed_gameplay_rewind_cancel:
			resource = -1
			active_token = 0
			active_action = &""
		if fail_gameplay_rewind_cancel:
			return false
		if token > 0 and active_token != token:
			return false
		if not hold_runtime_snapshot.is_empty():
			resource = int(hold_runtime_snapshot.get("resource", resource))
		active_token = 0
		active_action = &""
		return true


	func gameplay_rewind_snapshot() -> Dictionary:
		return {
			"resource": resource,
			"active_token": active_token,
			"active_action": str(active_action),
			"committed_payload_guard": committed_payload_guard.duplicate(true),
		}


	func restore_gameplay_rewind_snapshot_for_rollback(value: Dictionary) -> bool:
		gameplay_rewind_restore_calls += 1
		if mutate_before_failed_gameplay_rewind_restore:
			resource = -2
			active_token = 0
			active_action = &""
		if (
			fail_gameplay_rewind_restore
			or not value.get("committed_payload_guard") is Dictionary
			or value["committed_payload_guard"] != committed_payload_guard
			or typeof(value.get("resource")) != TYPE_INT
			or typeof(value.get("active_token")) != TYPE_INT
			or typeof(value.get("active_action")) != TYPE_STRING
		):
			return false
		resource = int(value["resource"])
		active_token = int(value["active_token"])
		active_action = StringName(str(value["active_action"]))
		return gameplay_rewind_snapshot() == value


	func gameplay_rewind_committed_payload_guard() -> Dictionary:
		return committed_payload_guard.duplicate(true)


	func finish_action(token: int) -> void:
		if active_token != token:
			return
		finish_calls += 1
		active_token = 0
		active_action = &""


	func reset_runtime_state(reason: StringName) -> void:
		reset_calls += 1
		last_reset_reason = reason
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
		restore_calls += 1
		if fail_restore or fail_restore_on_calls.has(restore_calls):
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
		if drift_restore_on_calls.has(restore_calls):
			resource += 1
		return true


	func presentation_snapshot() -> Dictionary:
		return {
			"resource": resource,
			"active_action": str(active_action),
		}


	func _action_plan(intent_id: StringName) -> Dictionary:
		var resource_costs := (
			{"time_energy": external_resource_cost}
			if external_resource_cost > 0.0
			else {}
		)
		if intent_id == &"weapon_ultimate":
			var hold_plan := {
				"weapon_id": "test_weapon",
				"action_id": "hold_test",
				"profile_id": "test_profile",
				"profile_version": 1,
				"cooldown_frames": action_cooldown_frames,
				"resource_costs": resource_costs,
				"phases": [
					{
						"phase": "HOLD",
						"duration_frames": 5,
						"minimum_hold_frames": 2,
						"charge_complete_frames": 4,
						"hold_progress_multiplier": 1.0,
						"movement_start_multiplier": 1.0,
						"movement_multiplier": 0.25,
					},
					{
						"phase": "WINDUP",
						"duration_frames": 2,
						"movement_multiplier": 0.5,
					},
					{
						"phase": "ACTIVE",
						"duration_frames": 1,
						"movement_multiplier": 0.5,
					},
					{
						"phase": "RECOVERY",
						"duration_frames": 2,
						"cancel_from_frame": 1,
						"movement_multiplier": 0.5,
					},
				],
				"payloads": [{"descriptor_id": "hold_hitbox"}],
			}
			if return_hold_release_variant:
				hold_plan["allowed_release_action_ids"] = ["normal_test", "aimed_test"]
				hold_plan["release_action_fingerprints"] = {
					"normal_test": "normal-test-v1",
					"aimed_test": "aimed-test-v1",
				}
			return hold_plan
		var action_id := &"primary_test" if intent_id == &"weapon_primary" else &"secondary_test"
		return {
			"weapon_id": "test_weapon",
			"action_id": str(action_id),
			"cooldown_frames": action_cooldown_frames,
			"resource_costs": resource_costs,
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


	func _channel_plan() -> Dictionary:
		return {
			"weapon_id": "test_weapon",
			"action_id": "channel_test",
			"cooldown_frames": 0,
			"resource_costs": {},
			"phases": [{
				"phase": "CHANNEL",
				"duration_frames": 4,
				"movement_multiplier": 0.5,
			}],
			"payloads": [],
		}


	func _reload_plan() -> Dictionary:
		return {
			"weapon_id": "test_weapon",
			"action_id": "reload_test",
			"cooldown_frames": 0,
			"resource_costs": {},
			"phases": [
				{"phase": "WINDUP", "duration_frames": 2, "movement_multiplier": 0.65},
				{
					"phase": "RESOURCE_ACTION",
					"duration_frames": 5,
					"cancel_from_frame": 0,
					"movement_multiplier": 0.65,
				},
				{"phase": "RECOVERY", "duration_frames": 2, "movement_multiplier": 0.65},
			],
			"payloads": [{"descriptor_id": "reload_transaction"}],
		}


var _suite
var _committed_facts: Array[Dictionary] = []
var _runtime_events: Array[Dictionary] = []
var _published_event_order: Array[String] = []
var _publication_observer_coordinator: RefCounted
var _publication_observer_begin_results: Array[bool] = []
var _publication_observer_discard_publication: Dictionary = {}
var _publication_observer_discard_results: Array[bool] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_rejected_plan_is_atomic()
	_test_failed_commit_restores_runtime_and_coordinator()
	_test_non_hold_commit_publishes_runtime_commit_context()
	_test_failed_commit_with_failed_rollback_resets_safe()
	_test_phase_failure_cancels_safe()
	_test_windup_active_recovery_and_cancel_boundary()
	_test_buffer_consumption_can_be_deferred_for_external_priority()
	_test_short_buffer_expires_before_cancel_window()
	_test_cancel_invalidates_stale_tokens_idempotently()
	_test_snapshot_is_isolated_and_safe_restore_is_generation_safe()
	_test_runtime_snapshot_restores_ready_and_active_state_exactly()
	_test_runtime_snapshot_restore_rejects_stale_token_resurrection()
	_test_runtime_snapshot_restore_rejects_inconsistent_resource_ledger_atomically()
	_test_runtime_restore_failure_rolls_back_without_touching_resources()
	_test_runtime_rollback_failure_forces_fail_closed_ready_state()
	_test_final_snapshot_mismatch_rolls_back_exactly()
	_test_resource_rollback_failure_forces_fail_closed_ready_state()
	_test_hold_edges_keep_one_action_token_and_one_commit()
	_test_hold_releases_automatically_once_at_maximum()
	_test_under_minimum_hold_release_cancels_without_payload_or_cue()
	_test_stale_hold_release_is_rejected_after_cancel()
	_test_hold_snapshot_isolated_and_restore_rejection_is_atomic()
	_test_tampered_finalized_hold_plan_rolls_back_and_cancels()
	_test_hold_release_variant_adopts_real_action_identity()
	_test_hold_release_variant_fingerprint_is_frozen()
	_test_terminal_hold_requires_declared_release_variants()
	_test_contract_rejects_invalid_hold_boundaries()
	_test_contract_validates_extended_hold_metadata()
	_test_contract_accepts_resource_action_cancel_boundary()
	_test_contract_validates_plan_resources_and_cooldown()
	_test_resource_prepare_rejects_before_runtime_commit()
	_test_resource_commit_failure_rolls_back_runtime_and_cooldown()
	_test_resource_success_spends_once_and_enforces_cooldown()
	_test_hold_cost_commits_only_on_valid_release()
	_test_hold_abort_restores_runtime_owned_resource_until_release_commit()
	_test_hold_release_success_survives_immediate_phase_cancellation()
	_test_dynamic_hold_progress_controls_movement()
	_test_reserved_context_fields_are_rejected()
	_test_reserved_context_rejects_before_busy_buffering()
	_test_ready_presentation_queries_committed_cooldown_ledger()
	_test_live_input_actions_do_not_enter_busy_buffer()
	_test_reload_live_intent_uses_coordinator_phase_frame()
	_test_malformed_live_intent_tail_rolls_back_runtime_only()
	_test_runtime_tick_uses_coordinator_frame_while_ready_and_busy()
	_test_busy_unsupported_sword_semantics_preserve_existing_buffer()
	_test_frame_event_buffer_rollback_discards_all_events()
	_test_frame_event_buffer_commit_publishes_once_in_original_order()
	_test_frame_event_publication_is_two_phase_and_observer_atomic()
	_test_finalized_frame_event_publication_discard_is_authenticated_and_exactly_once()
	_test_finalized_frame_event_publication_discard_rejects_publish_reentry()
	_test_rewind_safe_reset_preserves_committed_resources()
	_test_gameplay_rewind_cancel_preserves_committed_payload_guard()
	_test_gameplay_rewind_rollback_restores_windup_local_state_exactly()
	_test_gameplay_rewind_rollback_restores_hold_without_refunding_authority()
	_test_gameplay_rewind_rejects_payload_identity_drift()
	_test_gameplay_rewind_cancel_rollback_failure_forces_fail_closed()
	_test_gameplay_rewind_restore_rollback_failure_forces_fail_closed()
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


func _test_non_hold_commit_publishes_runtime_commit_context() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{"source": "runtime_commit_context"}
	)

	_suite.assert_true(bool(committed.get("ok", false)), "non-HOLD fixture commits")
	_suite.assert_equal(_committed_facts.size(), 1, "non-HOLD commit publishes once")
	_suite.assert_equal(
		(_committed_facts[0].get("context", {}) as Dictionary).get("resource"),
		7,
		"published non-HOLD context preserves the runtime commit result"
	)


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


func _test_runtime_snapshot_restores_ready_and_active_state_exactly() -> void:
	var source := _fixture()
	var source_coordinator: RefCounted = source["coordinator"]
	var committed: Dictionary = source_coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{"aim_direction": Vector2(0.25, -0.75)}
	)
	_suite.assert_true(bool(committed.get("ok", false)), "runtime restore fixture commits a representative action")
	_advance(source_coordinator, 3)
	var active_snapshot: Dictionary = source_coordinator.snapshot()

	var target := _fixture()
	var target_coordinator: RefCounted = target["coordinator"]
	_suite.assert_true(target_coordinator.restore_snapshot(active_snapshot), "strict runtime restore accepts a valid active action")
	_suite.assert_equal(target_coordinator.snapshot(), active_snapshot, "active restore reinstalls phase, frame, plan, context, token, runtime, and resources exactly")

	_advance(source_coordinator, 2)
	_advance(target_coordinator, 2)
	_suite.assert_equal(target_coordinator.snapshot(), source_coordinator.snapshot(), "restored active action advances deterministically")

	source_coordinator.cancel(&"ready_restore_fixture")
	source_coordinator.advance_frame()
	var ready_snapshot: Dictionary = source_coordinator.snapshot()
	_suite.assert_true(target_coordinator.restore_snapshot(ready_snapshot), "strict runtime restore accepts a later READY state")
	_suite.assert_equal(target_coordinator.snapshot(), ready_snapshot, "READY restore reinstalls the authoritative terminal state exactly")
	var next: Dictionary = target_coordinator.submit_intent({"id": "weapon_secondary", "edge": "pressed"}, {})
	_suite.assert_true(bool(next.get("ok", false)), "restored READY state accepts the next action")
	_suite.assert_true(int(next.get("token", 0)) > int(committed.get("token", 0)), "restored READY state preserves the token floor")


func _test_runtime_snapshot_restore_rejects_stale_token_resurrection() -> void:
	var source := _fixture()
	var source_coordinator: RefCounted = source["coordinator"]
	source_coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	source_coordinator.advance_frame()
	var active_snapshot: Dictionary = source_coordinator.snapshot()
	source_coordinator.cancel(&"token_resurrection_fixture")
	source_coordinator.advance_frame()
	var ready_snapshot: Dictionary = source_coordinator.snapshot()

	var target := _fixture()
	var target_coordinator: RefCounted = target["coordinator"]
	_suite.assert_true(target_coordinator.restore_snapshot(active_snapshot), "token resurrection fixture restores the active state once")
	_suite.assert_true(target_coordinator.restore_snapshot(ready_snapshot), "token resurrection fixture advances to READY")
	var before: Dictionary = target_coordinator.snapshot()
	_suite.assert_true(not target_coordinator.restore_snapshot(active_snapshot), "READY token floor rejects resurrection of the completed action")
	_suite.assert_equal(target_coordinator.snapshot(), before, "stale token resurrection rejection is atomic")


func _test_runtime_snapshot_restore_rejects_inconsistent_resource_ledger_atomically() -> void:
	var source := _fixture()
	var source_coordinator: RefCounted = source["coordinator"]
	source_coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	source_coordinator.advance_frame()
	var inconsistent: Dictionary = source_coordinator.snapshot()
	var token := int(inconsistent.get("token", 0))
	inconsistent["resource_transaction"]["committed_tokens"][token]["ticket"]["action_id"] = "forged_action"

	var target := _fixture()
	var target_coordinator: RefCounted = target["coordinator"]
	var before: Dictionary = target_coordinator.snapshot()
	_suite.assert_true(not target_coordinator.restore_snapshot(inconsistent), "coordinator rejects an inconsistent resource transaction ledger")
	_suite.assert_equal(target_coordinator.snapshot(), before, "resource-ledger restore rejection preserves coordinator, runtime, and provider state")


func _test_runtime_restore_failure_rolls_back_without_touching_resources() -> void:
	var source := _fixture()
	var source_coordinator: RefCounted = source["coordinator"]
	source_coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	source_coordinator.advance_frame()
	var target_snapshot: Dictionary = source_coordinator.snapshot()

	var target := _fixture()
	var coordinator: RefCounted = target["coordinator"]
	var runtime: FakeWeaponRuntime = target["runtime"]
	var provider: FakeResourceProvider = target["provider"]
	var before: Dictionary = coordinator.snapshot()
	runtime.fail_restore_on_calls = [1]

	_suite.assert_true(not coordinator.restore_snapshot(target_snapshot), "runtime target restore failure rejects the replay snapshot")
	_suite.assert_equal(coordinator.snapshot(), before, "runtime target failure restores the exact prior coordinator snapshot")
	_suite.assert_equal(runtime.restore_calls, 2, "failed target restore is followed by one checked runtime rollback")
	_suite.assert_equal(provider.restore_calls, 0, "runtime failure occurs before any external account is modified")


func _test_runtime_rollback_failure_forces_fail_closed_ready_state() -> void:
	var source := _fixture()
	var source_coordinator: RefCounted = source["coordinator"]
	source_coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	source_coordinator.advance_frame()
	var target_snapshot: Dictionary = source_coordinator.snapshot()

	var target := _fixture()
	var coordinator: RefCounted = target["coordinator"]
	var runtime: FakeWeaponRuntime = target["runtime"]
	var provider: FakeResourceProvider = target["provider"]
	var transaction: RefCounted = target["resource_transaction"]
	runtime.fail_restore_on_calls = [2]
	provider.fail_restore_on_calls = [1]

	_suite.assert_true(not coordinator.restore_snapshot(target_snapshot), "resource failure with runtime rollback failure rejects restore")
	_suite.assert_equal(runtime.restore_calls, 2, "runtime target and rollback are each attempted once")
	_suite.assert_equal(runtime.reset_calls, 1, "runtime rollback failure triggers one explicit safe reset")
	_suite.assert_equal(coordinator.phase_name(), &"READY", "failed rollback cannot leave the coordinator ACTIVE")
	_suite.assert_equal(coordinator.current_token(), 0, "failed rollback clears the action token")
	_suite.assert_true(not bool(transaction.snapshot().get("configured", true)), "failed rollback closes the resource transaction")


func _test_final_snapshot_mismatch_rolls_back_exactly() -> void:
	var source := _fixture()
	var source_coordinator: RefCounted = source["coordinator"]
	source_coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	source_coordinator.advance_frame()
	var target_snapshot: Dictionary = source_coordinator.snapshot()

	var target := _fixture()
	var coordinator: RefCounted = target["coordinator"]
	var runtime: FakeWeaponRuntime = target["runtime"]
	var before: Dictionary = coordinator.snapshot()
	runtime.drift_restore_on_calls = [1]

	_suite.assert_true(not coordinator.restore_snapshot(target_snapshot), "post-restore snapshot mismatch rejects replay state")
	_suite.assert_equal(coordinator.snapshot(), before, "final mismatch strictly restores runtime, resource, and coordinator state")
	_suite.assert_equal(runtime.restore_calls, 2, "final mismatch performs one checked runtime rollback")
	_suite.assert_equal(runtime.reset_calls, 0, "successful mismatch rollback does not require a safe reset")


func _test_resource_rollback_failure_forces_fail_closed_ready_state() -> void:
	var source := _fixture()
	var source_runtime: FakeWeaponRuntime = source["runtime"]
	var source_coordinator: RefCounted = source["coordinator"]
	source_runtime.external_resource_cost = 20.0
	source_coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	source_coordinator.advance_frame()
	var target_snapshot: Dictionary = source_coordinator.snapshot()

	var target := _fixture()
	var coordinator: RefCounted = target["coordinator"]
	var runtime: FakeWeaponRuntime = target["runtime"]
	var provider: FakeResourceProvider = target["provider"]
	var transaction: RefCounted = target["resource_transaction"]
	runtime.drift_restore_on_calls = [1]
	provider.fail_restore_on_calls = [2]

	_suite.assert_true(not coordinator.restore_snapshot(target_snapshot), "resource rollback failure rejects the mismatched replay snapshot")
	_suite.assert_equal(coordinator.phase_name(), &"READY", "resource rollback failure cannot retain ACTIVE state")
	_suite.assert_equal(coordinator.current_token(), 0, "resource rollback failure clears the action token")
	_suite.assert_equal(runtime.active_token, 0, "safe reset clears the runtime action token")
	_suite.assert_true(not bool(transaction.snapshot().get("configured", true)), "resource rollback failure leaves the transaction fail closed")


func _test_hold_edges_keep_one_action_token_and_one_commit() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var pressed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "pressed"},
		{"source": "hold_transaction"}
	)
	var token := int(pressed.get("token", 0))
	var generation := int(pressed.get("generation", 0))
	_suite.assert_true(bool(pressed.get("ok", false)), "hold press reserves the transaction token")
	_suite.assert_equal(coordinator.phase_name(), &"HOLD", "hold press enters coordinator-owned HOLD")
	_suite.assert_true(token > 0, "hold transaction receives an action token")
	_suite.assert_equal(_committed_facts.size(), 0, "HOLD press publishes no committed fact before a valid release")

	coordinator.advance_frame()
	var held: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "held", "held_frames": 999},
		{}
	)
	_suite.assert_true(bool(held.get("ok", false)), "held edge is acknowledged")
	_suite.assert_equal(held.get("code"), &"HOLDING", "held edge reports HOLDING without recommit")
	_suite.assert_equal(held.get("token"), token, "held edge keeps the original action token")
	_suite.assert_equal(held.get("generation"), generation, "held edge keeps the original generation")
	_suite.assert_equal(held.get("held_frames"), 1, "held edge reports the coordinator clock instead of trusting input frames")
	_suite.assert_equal(runtime.commit_attempts, 1, "held edge does not commit a second runtime action")
	_suite.assert_equal(_committed_facts.size(), 0, "held edge publishes no premature commit fact")

	coordinator.advance_frame()
	var released: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released", "held_frames": 999},
		{}
	)
	_suite.assert_true(bool(released.get("ok", false)), "release at the minimum hold boundary succeeds")
	_suite.assert_equal(released.get("code"), &"HOLD_RELEASED", "manual release reports a hold release")
	_suite.assert_equal(released.get("token"), token, "release keeps the original action token")
	_suite.assert_equal(released.get("generation"), generation, "release keeps the original generation")
	_suite.assert_equal(released.get("held_frames"), 2, "release freezes the authoritative hold duration")
	_suite.assert_equal(coordinator.phase_name(), &"WINDUP", "release advances the same action into windup")
	_suite.assert_equal(
		coordinator.snapshot().get("plan", {}).get("phases", [])[0].get("phase"),
		"WINDUP",
		"release atomically adopts a finalized plan without the HOLD skeleton phase"
	)
	_suite.assert_equal(runtime.hold_release_calls, 1, "runtime receives exactly one hold release")
	_suite.assert_equal(runtime.released_hold_frames, [2], "runtime receives the coordinator-owned hold duration")
	_suite.assert_equal(runtime.commit_attempts, 1, "release does not recommit the runtime action")
	_suite.assert_equal(_committed_facts.size(), 1, "valid release publishes exactly one committed fact")
	_suite.assert_equal(_committed_facts[0].get("token"), token, "release fact keeps the reserved HOLD token")


func _test_hold_releases_automatically_once_at_maximum() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var pressed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "pressed"},
		{}
	)
	var token := int(pressed.get("token", 0))
	var generation := int(pressed.get("generation", 0))

	_advance(coordinator, 5)
	_suite.assert_equal(coordinator.phase_name(), &"WINDUP", "maximum hold advances automatically into windup")
	_suite.assert_equal(coordinator.current_token(), token, "automatic release preserves the action token")
	_suite.assert_equal(coordinator.generation(), generation, "automatic release preserves the generation")
	_suite.assert_equal(runtime.hold_release_calls, 1, "maximum hold releases exactly once")
	_suite.assert_equal(runtime.released_hold_frames, [5], "automatic release freezes the maximum hold duration")
	_suite.assert_equal(runtime.commit_attempts, 1, "automatic release never recommits the action")
	_suite.assert_equal(_committed_facts.size(), 1, "automatic release publishes one committed fact")

	var stale_release: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released", "held_frames": 5},
		{}
	)
	_suite.assert_true(not bool(stale_release.get("ok", false)), "release after automatic release is stale")
	_suite.assert_equal(stale_release.get("code"), &"STALE_HOLD_EDGE", "stale automatic-release edge fails closed")
	_suite.assert_equal(runtime.hold_release_calls, 1, "stale release cannot release the runtime twice")


func _test_under_minimum_hold_release_cancels_without_payload_or_cue() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var pressed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "pressed"},
		{}
	)
	var token := int(pressed.get("token", 0))
	var generation := int(pressed.get("generation", 0))
	coordinator.advance_frame()

	var released: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released", "held_frames": 999},
		{}
	)
	_suite.assert_true(not bool(released.get("ok", false)), "under-minimum release is rejected")
	_suite.assert_equal(released.get("code"), &"HOLD_TOO_SHORT", "under-minimum release reports its boundary failure")
	_suite.assert_equal(released.get("context", {}).get("held_frames"), 1, "failure reports authoritative held frames")
	_suite.assert_equal(released.get("context", {}).get("minimum_hold_frames"), 2, "failure reports the minimum boundary")
	_suite.assert_equal(coordinator.phase_name(), &"READY", "under-minimum release cancels atomically to ready")
	_suite.assert_equal(coordinator.current_token(), 0, "under-minimum release clears the action token")
	_suite.assert_true(coordinator.generation() > generation, "under-minimum release invalidates the action generation")
	_suite.assert_true(not coordinator.is_action_token_current(token, generation), "under-minimum release makes the token stale")
	_suite.assert_equal(runtime.cancel_calls, 1, "under-minimum release cancels runtime exactly once")
	_suite.assert_equal(runtime.hold_release_calls, 0, "under-minimum release never reaches runtime release")
	_suite.assert_equal(_runtime_events.size(), 0, "under-minimum release emits no payload or cue")
	_suite.assert_equal(_phase_names(runtime.phase_entries), ["HOLD"], "under-minimum release never enters payload phases")
	_suite.assert_equal(_committed_facts.size(), 0, "under-minimum release publishes no committed fact")


func _test_stale_hold_release_is_rejected_after_cancel() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var pressed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "pressed"},
		{}
	)
	var token := int(pressed.get("token", 0))
	var generation := int(pressed.get("generation", 0))
	coordinator.cancel(&"dash_cancel")

	_suite.assert_true(coordinator.generation() > generation, "dash cancellation invalidates the HOLD generation")
	_suite.assert_true(not coordinator.is_action_token_current(token, generation), "dash cancellation invalidates the HOLD token")
	var stale_release: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released", "held_frames": 4},
		{}
	)
	_suite.assert_true(not bool(stale_release.get("ok", false)), "release after dash cancellation is rejected")
	_suite.assert_equal(stale_release.get("code"), &"STALE_HOLD_EDGE", "cancelled HOLD release reports stale edge")
	_suite.assert_equal(runtime.commit_attempts, 1, "stale release cannot create a new runtime action")
	_suite.assert_equal(runtime.hold_release_calls, 0, "stale release cannot reach runtime release")
	_suite.assert_equal(runtime.cancel_calls, 1, "dash cancellation remains idempotent after stale release")


func _test_hold_snapshot_isolated_and_restore_rejection_is_atomic() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	coordinator.submit_intent({"id": "weapon_ultimate", "edge": "pressed"}, {})
	coordinator.advance_frame()
	var hold_snapshot: Dictionary = coordinator.snapshot()
	var before_restore: Dictionary = coordinator.snapshot()
	var exposed_plan: Dictionary = hold_snapshot["plan"]
	var exposed_phases: Array = exposed_plan["phases"]
	(exposed_phases[0] as Dictionary)["minimum_hold_frames"] = 0

	_suite.assert_equal(
		coordinator.snapshot()["plan"]["phases"][0]["minimum_hold_frames"],
		2,
		"mutating an exposed HOLD snapshot cannot alter coordinator boundaries"
	)
	_suite.assert_true(not coordinator.restore_safe(before_restore), "mid-HOLD restore is rejected")
	_suite.assert_equal(coordinator.snapshot(), before_restore, "mid-HOLD restore rejection is atomic")
	var presentation: Dictionary = coordinator.presentation_snapshot()
	_suite.assert_equal(presentation.get("hold_frames"), 1, "presentation exposes authoritative HOLD progress")
	_suite.assert_equal(presentation.get("minimum_hold_frames"), 2, "presentation exposes the minimum HOLD boundary")
	_suite.assert_equal(presentation.get("maximum_hold_frames"), 5, "presentation exposes the maximum HOLD boundary")


func _test_tampered_finalized_hold_plan_rolls_back_and_cancels() -> void:
	for field: StringName in [&"weapon_id", &"action_id", &"profile_id", &"profile_version"]:
		var fixture := _fixture()
		var coordinator: RefCounted = fixture["coordinator"]
		var runtime: FakeWeaponRuntime = fixture["runtime"]
		runtime.tamper_finalized_field = field
		var pressed: Dictionary = coordinator.submit_intent(
			{"id": "weapon_ultimate", "edge": "pressed"},
			{}
		)
		var token := int(pressed.get("token", 0))
		var generation := int(pressed.get("generation", 0))
		_advance(coordinator, 2)

		var released: Dictionary = coordinator.submit_intent(
			{"id": "weapon_ultimate", "edge": "released", "held_frames": 2},
			{}
		)
		var label := str(field)
		_suite.assert_true(not bool(released.get("ok", false)), "%s tampering is rejected" % label)
		_suite.assert_equal(released.get("code"), WeaponActionContractScript.CODE_INVALID_PLAN, "%s tampering uses the plan contract failure" % label)
		_suite.assert_equal(released.get("context", {}).get("field"), label, "%s tampering names the rejected field" % label)
		_suite.assert_equal(coordinator.phase_name(), &"READY", "%s tampering cancels to ready" % label)
		_suite.assert_equal(coordinator.current_token(), 0, "%s tampering clears the action token" % label)
		_suite.assert_true(coordinator.generation() > generation, "%s tampering invalidates generation" % label)
		_suite.assert_true(not coordinator.is_action_token_current(token, generation), "%s tampering cannot retain a stale token" % label)
		_suite.assert_equal(runtime.cancel_calls, 1, "%s tampering cancels the restored runtime once" % label)
		_suite.assert_equal(_runtime_events.size(), 0, "%s tampering emits no payload or cue" % label)
		_suite.assert_equal(_committed_facts.size(), 0, "%s tampering publishes no committed fact" % label)


func _test_hold_release_variant_adopts_real_action_identity() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	runtime.return_hold_release_variant = true
	runtime.action_cooldown_frames = 20
	var pressed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "pressed"},
		{"source": "variant_identity"}
	)
	var token := int(pressed.get("token", 0))
	_advance(coordinator, 2)
	var released: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released", "held_frames": 999},
		{}
	)

	_suite.assert_true(bool(released.get("ok", false)), "declared hold release variant succeeds")
	_suite.assert_equal(released.get("token"), token, "release variant preserves the original hold token")
	_suite.assert_equal(coordinator.snapshot().get("plan", {}).get("action_id"), "aimed_test", "coordinator adopts the finalized action identity")
	_suite.assert_equal(_committed_facts.size(), 1, "release variant publishes exactly one committed fact")
	_suite.assert_equal(_committed_facts[0].get("action_id"), "aimed_test", "committed fact uses the real finalized action id")
	_suite.assert_equal(_committed_facts[0].get("context", {}).get("action_id"), "aimed_test", "committed context uses the real finalized action id")
	_suite.assert_equal(coordinator.presentation_snapshot().get("action_id"), "aimed_test", "presentation uses the real finalized action id")
	_suite.assert_equal(coordinator.cooldown_remaining(&"aimed_test"), 20, "cooldown ledger uses the finalized action identity")
	_suite.assert_equal(coordinator.cooldown_remaining(&"hold_test"), 0, "hold skeleton identity never receives a cooldown")
	_suite.assert_equal(runtime.commit_attempts, 1, "release variant does not recommit the runtime")


func _test_hold_release_variant_fingerprint_is_frozen() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	runtime.return_hold_release_variant = true
	runtime.tamper_release_fingerprint = true
	var pressed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "pressed"},
		{}
	)
	var generation := int(pressed.get("generation", 0))
	_advance(coordinator, 2)
	var released: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released", "held_frames": 2},
		{}
	)

	_suite.assert_true(not bool(released.get("ok", false)), "undeclared release fingerprint fails closed")
	_suite.assert_equal(released.get("code"), WeaponActionContractScript.CODE_INVALID_PLAN, "fingerprint mismatch uses the plan contract failure")
	_suite.assert_equal(released.get("context", {}).get("field"), "release_action_fingerprint", "fingerprint mismatch names the rejected field")
	_suite.assert_equal(coordinator.phase_name(), &"READY", "fingerprint mismatch cancels the hold transaction")
	_suite.assert_true(coordinator.generation() > generation, "fingerprint mismatch invalidates the hold generation")
	_suite.assert_equal(runtime.resource, 8, "fingerprint mismatch rolls runtime state back")
	_suite.assert_equal(_committed_facts.size(), 0, "fingerprint mismatch publishes no committed fact")


func _test_terminal_hold_requires_declared_release_variants() -> void:
	var variant_hold := {
		"weapon_id": "test_weapon",
		"action_id": "primary_hold",
		"profile_id": "test_profile",
		"profile_version": 1,
		"allowed_release_action_ids": ["normal_test", "aimed_test"],
		"release_action_fingerprints": {
			"normal_test": "normal-test-v1",
			"aimed_test": "aimed-test-v1",
		},
		"phases": [{
			"phase": "HOLD",
			"duration_frames": 600,
			"minimum_hold_frames": 0,
			"charge_complete_frames": 18,
		}],
		"payloads": [],
	}
	_suite.assert_true(
		bool(WeaponActionContractScript.validate_plan(variant_hold, &"test_weapon").get("ok", false)),
		"declared release variants allow a terminal HOLD skeleton"
	)

	var undeclared_hold := variant_hold.duplicate(true)
	undeclared_hold.erase("allowed_release_action_ids")
	undeclared_hold.erase("release_action_fingerprints")
	_suite.assert_true(
		not bool(WeaponActionContractScript.validate_plan(undeclared_hold, &"test_weapon").get("ok", false)),
		"legacy terminal HOLD without release variants remains invalid"
	)


func _test_contract_rejects_invalid_hold_boundaries() -> void:
	var invalid_minimum := {
		"weapon_id": "test_weapon",
		"action_id": "invalid_hold_minimum",
		"phases": [{
			"phase": "HOLD",
			"duration_frames": 5,
			"minimum_hold_frames": 6,
		}],
		"payloads": [],
	}
	var minimum_result: Dictionary = WeaponActionContractScript.validate_plan(invalid_minimum, &"test_weapon")
	_suite.assert_true(not bool(minimum_result.get("ok", false)), "minimum HOLD boundary cannot exceed maximum duration")

	var misplaced_hold := {
		"weapon_id": "test_weapon",
		"action_id": "misplaced_hold",
		"phases": [
			{"phase": "WINDUP", "duration_frames": 1},
			{"phase": "HOLD", "duration_frames": 5, "minimum_hold_frames": 2},
		],
		"payloads": [],
	}
	var misplaced_result: Dictionary = WeaponActionContractScript.validate_plan(misplaced_hold, &"test_weapon")
	_suite.assert_true(not bool(misplaced_result.get("ok", false)), "HOLD must be the first action phase")

	var terminal_hold := {
		"weapon_id": "test_weapon",
		"action_id": "terminal_hold",
		"phases": [{"phase": "HOLD", "duration_frames": 5, "minimum_hold_frames": 2}],
		"payloads": [],
	}
	var terminal_result: Dictionary = WeaponActionContractScript.validate_plan(terminal_hold, &"test_weapon")
	_suite.assert_true(not bool(terminal_result.get("ok", false)), "HOLD requires a release phase in the same action plan")


func _test_contract_validates_extended_hold_metadata() -> void:
	var valid_plan := _extended_hold_plan()
	_suite.assert_true(
		bool(WeaponActionContractScript.validate_plan(valid_plan, &"test_weapon").get("ok", false)),
		"extended HOLD metadata is optional and valid within the phase boundary"
	)

	var legacy_plan := valid_plan.duplicate(true)
	var legacy_hold: Dictionary = (legacy_plan["phases"] as Array)[0]
	legacy_hold.erase("charge_complete_frames")
	legacy_hold.erase("hold_progress_multiplier")
	legacy_hold.erase("movement_start_multiplier")
	_suite.assert_true(
		bool(WeaponActionContractScript.validate_plan(legacy_plan, &"test_weapon").get("ok", false)),
		"legacy HOLD plans remain valid when extended metadata is absent"
	)

	for field: String in ["charge_complete_frames", "hold_progress_multiplier", "movement_start_multiplier"]:
		var misplaced := valid_plan.duplicate(true)
		var phases: Array = misplaced["phases"]
		var hold: Dictionary = phases[0]
		var windup: Dictionary = phases[1]
		windup[field] = hold[field]
		var misplaced_result: Dictionary = WeaponActionContractScript.validate_plan(misplaced, &"test_weapon")
		_suite.assert_true(not bool(misplaced_result.get("ok", false)), "%s is HOLD-only" % field)

	var before_minimum := valid_plan.duplicate(true)
	(before_minimum["phases"] as Array)[0]["charge_complete_frames"] = 1
	_suite.assert_true(
		not bool(WeaponActionContractScript.validate_plan(before_minimum, &"test_weapon").get("ok", false)),
		"charge completion cannot precede the minimum HOLD boundary"
	)

	var after_duration := valid_plan.duplicate(true)
	(after_duration["phases"] as Array)[0]["charge_complete_frames"] = 6
	_suite.assert_true(
		not bool(WeaponActionContractScript.validate_plan(after_duration, &"test_weapon").get("ok", false)),
		"charge completion cannot exceed the automatic-release duration"
	)

	for field: String in ["hold_progress_multiplier", "movement_start_multiplier"]:
		var negative := valid_plan.duplicate(true)
		(negative["phases"] as Array)[0][field] = -0.01
		_suite.assert_true(
			not bool(WeaponActionContractScript.validate_plan(negative, &"test_weapon").get("ok", false)),
			"%s rejects negative values" % field
		)


func _test_contract_accepts_resource_action_cancel_boundary() -> void:
	var valid_plan := {
		"weapon_id": "test_weapon",
		"action_id": "reload_test",
		"phases": [{
			"phase": "RESOURCE_ACTION",
			"duration_frames": 32,
			"cancel_from_frame": 0,
			"movement_multiplier": 0.65,
		}],
		"payloads": [],
	}
	var accepted: Dictionary = WeaponActionContractScript.validate_plan(valid_plan, &"test_weapon")
	_suite.assert_true(bool(accepted.get("ok", false)), "resource action may expose an explicit half-open cancel boundary")

	var invalid_plan := valid_plan.duplicate(true)
	(invalid_plan["phases"][0] as Dictionary)["cancel_from_frame"] = 32
	var rejected: Dictionary = WeaponActionContractScript.validate_plan(invalid_plan, &"test_weapon")
	_suite.assert_true(not bool(rejected.get("ok", false)), "resource action cancel boundary remains half-open")

func _test_contract_validates_plan_resources_and_cooldown() -> void:
	var valid_plan := _extended_hold_plan()
	valid_plan["cooldown_frames"] = 0
	valid_plan["resource_costs"] = {
		"time_energy": 20.0,
		&"ammo": 1,
	}
	_suite.assert_true(
		bool(WeaponActionContractScript.validate_plan(valid_plan, &"test_weapon").get("ok", false)),
		"finite non-negative cooldowns and resource costs are accepted"
	)

	for invalid_cooldown: Variant in [-1, 1.5, WeaponActionContractScript.MAX_PHASE_FRAMES + 1]:
		var invalid := valid_plan.duplicate(true)
		invalid["cooldown_frames"] = invalid_cooldown
		_suite.assert_true(
			not bool(WeaponActionContractScript.validate_plan(invalid, &"test_weapon").get("ok", false)),
			"invalid cooldown %s fails closed" % str(invalid_cooldown)
		)

	var non_dictionary_costs := valid_plan.duplicate(true)
	non_dictionary_costs["resource_costs"] = []
	_suite.assert_true(
		not bool(WeaponActionContractScript.validate_plan(non_dictionary_costs, &"test_weapon").get("ok", false)),
		"resource costs must be a dictionary"
	)

	for invalid_cost: Variant in [-1.0, NAN, INF, "one"]:
		var invalid := valid_plan.duplicate(true)
		invalid["resource_costs"] = {"ammo": invalid_cost}
		_suite.assert_true(
			not bool(WeaponActionContractScript.validate_plan(invalid, &"test_weapon").get("ok", false)),
			"invalid resource cost %s fails closed" % str(invalid_cost)
		)

	var empty_resource_id := valid_plan.duplicate(true)
	empty_resource_id["resource_costs"] = {"": 1.0}
	_suite.assert_true(
		not bool(WeaponActionContractScript.validate_plan(empty_resource_id, &"test_weapon").get("ok", false)),
		"resource costs reject empty resource identifiers"
	)


func _test_resource_prepare_rejects_before_runtime_commit() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var provider: FakeResourceProvider = fixture["provider"]
	runtime.external_resource_cost = 20.0
	provider.current = 19.0

	var rejected: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	_suite.assert_true(not bool(rejected.get("ok", false)), "insufficient external resource rejects")
	_suite.assert_equal(rejected.get("code"), &"INSUFFICIENT_RESOURCE", "resource prepare failure is typed")
	_suite.assert_equal(runtime.commit_attempts, 0, "resource prepare rejects before runtime payload staging")
	_suite.assert_equal(provider.spend_calls, 0, "resource prepare rejection never calls provider commit")
	_suite.assert_equal(_committed_facts.size(), 0, "resource prepare rejection publishes no fact")


func _test_resource_commit_failure_rolls_back_runtime_and_cooldown() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var provider: FakeResourceProvider = fixture["provider"]
	runtime.external_resource_cost = 20.0
	runtime.action_cooldown_frames = 30
	provider.reject_commit = true

	var rejected: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	_suite.assert_true(not bool(rejected.get("ok", false)), "provider rejection fails the action")
	_suite.assert_equal(runtime.commit_attempts, 1, "runtime payload is staged before the final resource commit")
	_suite.assert_equal(runtime.resource, 8, "provider rejection restores the runtime snapshot")
	_suite.assert_equal(coordinator.phase_name(), &"READY", "provider rejection keeps coordinator ready")
	_suite.assert_equal(coordinator.cooldown_remaining(&"primary_test"), 0, "provider rejection rolls cooldown back")
	_suite.assert_close(provider.current, 100.0, "provider rejection spends no energy")
	_suite.assert_equal(_committed_facts.size(), 0, "provider rejection publishes no committed fact")


func _test_resource_success_spends_once_and_enforces_cooldown() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var provider: FakeResourceProvider = fixture["provider"]
	runtime.external_resource_cost = 20.0
	runtime.action_cooldown_frames = 20

	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	_suite.assert_true(bool(committed.get("ok", false)), "funded action commits")
	_suite.assert_close(provider.current, 80.0, "funded action spends once")
	_suite.assert_equal(provider.spend_calls, 1, "funded action calls provider once")
	_suite.assert_equal(coordinator.cooldown_remaining(&"primary_test"), 20, "funded action starts cooldown")
	_advance(coordinator, 12)
	var attempts_before := runtime.commit_attempts
	var cooling_down: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	_suite.assert_true(not bool(cooling_down.get("ok", false)), "active cooldown rejects a ready action")
	_suite.assert_equal(cooling_down.get("code"), &"COOLDOWN_ACTIVE", "cooldown rejection is typed")
	_suite.assert_equal(runtime.commit_attempts, attempts_before, "cooldown rejects before runtime staging")
	_suite.assert_close(provider.current, 80.0, "cooldown rejection spends no additional energy")
	_advance(coordinator, 8)
	_suite.assert_true(
		bool(coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {}).get("ok", false)),
		"action reopens exactly when cooldown reaches zero"
	)
	_suite.assert_close(provider.current, 60.0, "second legal action spends once")


func _test_hold_cost_commits_only_on_valid_release() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var provider: FakeResourceProvider = fixture["provider"]
	runtime.external_resource_cost = 20.0
	runtime.action_cooldown_frames = 40

	_suite.assert_true(
		bool(coordinator.submit_intent({"id": "weapon_ultimate", "edge": "pressed"}, {}).get("ok", false)),
		"paid HOLD reserves a token"
	)
	coordinator.advance_frame()
	var undercharged: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released", "held_frames": 1},
		{}
	)
	_suite.assert_true(not bool(undercharged.get("ok", false)), "undercharged paid HOLD rejects")
	_suite.assert_close(provider.current, 100.0, "undercharged HOLD spends no resource")
	_suite.assert_equal(coordinator.cooldown_remaining(&"hold_test"), 0, "undercharged HOLD starts no cooldown")
	_suite.assert_equal(_committed_facts.size(), 0, "undercharged HOLD publishes no committed fact")

	_suite.assert_true(
		bool(coordinator.submit_intent({"id": "weapon_ultimate", "edge": "pressed"}, {}).get("ok", false)),
		"fresh paid HOLD reserves a new token"
	)
	_advance(coordinator, 2)
	var released: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released", "held_frames": 2},
		{}
	)
	_suite.assert_true(bool(released.get("ok", false)), "valid paid HOLD releases")
	_suite.assert_close(provider.current, 80.0, "valid HOLD spends exactly once at release")
	_suite.assert_equal(coordinator.cooldown_remaining(&"hold_test"), 40, "valid HOLD starts cooldown at release")
	_suite.assert_equal(_committed_facts.size(), 1, "valid HOLD publishes exactly one committed fact")


func _test_hold_abort_restores_runtime_owned_resource_until_release_commit() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]

	coordinator.submit_intent({"id": "weapon_ultimate", "edge": "pressed"}, {})
	_suite.assert_equal(runtime.resource, 7, "HOLD press may stage runtime-owned resource state")
	coordinator.cancel(&"dash_cancel")
	_suite.assert_equal(runtime.resource, 8, "cancelling an unreleased HOLD restores the press snapshot")

	coordinator.submit_intent({"id": "weapon_ultimate", "edge": "pressed"}, {})
	coordinator.advance_frame()
	var undercharged: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released"},
		{}
	)
	_suite.assert_true(not bool(undercharged.get("ok", false)), "undercharged HOLD aborts")
	_suite.assert_equal(runtime.resource, 8, "undercharged HOLD restores runtime-owned resources")

	coordinator.submit_intent({"id": "weapon_ultimate", "edge": "pressed"}, {})
	_advance(coordinator, 2)
	var released: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released"},
		{}
	)
	_suite.assert_true(bool(released.get("ok", false)), "valid HOLD reaches its irreversible release commit")
	_suite.assert_equal(runtime.resource, 7, "valid release retains the runtime-owned debit")
	coordinator.cancel(&"post_release_cancel")
	_suite.assert_equal(runtime.resource, 7, "post-commit cancellation cannot refund runtime-owned resources")


func _test_hold_release_success_survives_immediate_phase_cancellation() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var provider: FakeResourceProvider = fixture["provider"]
	runtime.external_resource_cost = 20.0
	runtime.action_cooldown_frames = 40
	runtime.fail_phase_entry = &"WINDUP"

	var pressed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "pressed"},
		{}
	)
	_advance(coordinator, 2)
	var released: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released"},
		{}
	)

	_suite.assert_true(bool(released.get("ok", false)), "release remains successful after the committed fact is published")
	_suite.assert_equal(released.get("code"), WeaponActionContractScript.CODE_HOLD_RELEASED, "irreversible release keeps its success code")
	_suite.assert_equal(released.get("token"), pressed.get("token"), "irreversible release reports the committed token")
	_suite.assert_equal(coordinator.phase_name(), &"READY", "immediate phase failure may still cancel future action state")
	_suite.assert_close(provider.current, 80.0, "immediate cancellation cannot refund an external commit")
	_suite.assert_equal(coordinator.cooldown_remaining(&"hold_test"), 40, "immediate cancellation preserves committed cooldown")
	_suite.assert_equal(runtime.resource, 7, "immediate cancellation preserves the runtime-owned release debit")
	_suite.assert_equal(_committed_facts.size(), 1, "irreversible release publishes exactly one committed fact")


func _test_dynamic_hold_progress_controls_movement() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	coordinator.submit_intent({"id": "weapon_ultimate", "edge": "pressed"}, {})
	_advance(coordinator, 2)
	var presentation: Dictionary = coordinator.presentation_snapshot()
	_suite.assert_equal(presentation.get("hold_frames"), 2, "HOLD presentation exposes raw coordinator frames")
	_suite.assert_close(float(presentation.get("effective_hold_frames", -1.0)), 2.0, "HOLD presentation exposes effective frames")
	_suite.assert_equal(presentation.get("charge_complete_frames"), 4, "HOLD presentation separates charge completion from auto release")
	_suite.assert_equal(presentation.get("maximum_hold_frames"), 5, "HOLD presentation preserves auto-release boundary")
	_suite.assert_close(float(presentation.get("charge_ratio", -1.0)), 0.5, "HOLD presentation computes charge ratio")
	_suite.assert_close(coordinator.movement_multiplier(), 0.625, "HOLD movement interpolates from start to end multiplier")


func _test_reserved_context_fields_are_rejected() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var rejected: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{"action_token": 999}
	)
	_suite.assert_true(not bool(rejected.get("ok", false)), "callers cannot forge reserved action context")
	_suite.assert_equal(rejected.get("code"), WeaponActionContractScript.CODE_INVALID_INTENT, "reserved context rejection is typed")
	_suite.assert_equal(runtime.commit_attempts, 0, "reserved context rejects before runtime planning")


func _test_reserved_context_rejects_before_busy_buffering() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	var snapshot_before: Dictionary = coordinator.snapshot()

	var rejected: Dictionary = coordinator.submit_intent(
		{"id": "weapon_secondary", "edge": "pressed", "buffer_frames": 20},
		{"resource_transaction": {"forged": true}}
	)

	_suite.assert_true(not bool(rejected.get("ok", false)), "reserved resource context fails before busy buffering")
	_suite.assert_equal(rejected.get("code"), WeaponActionContractScript.CODE_INVALID_INTENT, "busy reserved context rejection is typed")
	_suite.assert_equal(rejected.get("context", {}).get("field"), "resource_transaction", "resource transaction context is coordinator-owned")
	_suite.assert_equal(coordinator.snapshot(), snapshot_before, "reserved busy submission cannot mutate the buffer")
	_suite.assert_equal(runtime.commit_attempts, 1, "reserved busy submission never reaches planning or commit")


func _test_ready_presentation_queries_committed_cooldown_ledger() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	runtime.action_cooldown_frames = 20
	coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	_advance(coordinator, 12)
	_suite.assert_equal(coordinator.phase_name(), &"READY", "cooldown presentation fixture finishes its action")

	var presentation: Dictionary = coordinator.presentation_snapshot(&"primary_test")
	_suite.assert_equal(presentation.get("phase"), "READY", "cooldown remains queryable while ready")
	_suite.assert_equal(presentation.get("cooldown_action_id"), "primary_test", "presentation identifies the queried cooldown action")
	_suite.assert_equal(presentation.get("cooldown_remaining_frames"), 8, "ready presentation reports the live cooldown")
	_suite.assert_equal(presentation.get("cooldown_ledger", {}).get("primary_test"), 8, "presentation exposes the queryable cooldown ledger")


func _test_live_input_actions_do_not_enter_busy_buffer() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	var token_before := int(coordinator.current_token())

	var hold_rejected: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "pressed", "buffer_frames": 20},
		{}
	)
	_suite.assert_true(not bool(hold_rejected.get("ok", false)), "HOLD press is rejected while the cancel window is closed")
	_suite.assert_true(hold_rejected.get("code") != WeaponActionContractScript.CODE_BUFFERED, "HOLD press never enters the ordinary input buffer")

	runtime.return_channel_utility = true
	var channel_rejected: Dictionary = coordinator.submit_intent(
		{"id": "weapon_utility", "edge": "pressed", "buffer_frames": 20},
		{}
	)
	_suite.assert_true(not bool(channel_rejected.get("ok", false)), "CHANNEL press is rejected while the cancel window is closed")
	_suite.assert_true(channel_rejected.get("code") != WeaponActionContractScript.CODE_BUFFERED, "CHANNEL press never enters the ordinary input buffer")

	var release_rejected: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "released", "buffer_frames": 20},
		{}
	)
	_suite.assert_true(not bool(release_rejected.get("ok", false)), "release edge is stale while no matching HOLD owns the token")
	_suite.assert_equal(release_rejected.get("code"), WeaponActionContractScript.CODE_STALE_HOLD_EDGE, "release edge fails closed instead of buffering")

	_advance(coordinator, 12)
	_suite.assert_equal(coordinator.phase_name(), &"READY", "original action completes without starting an unmanned live-input action")
	_suite.assert_equal(runtime.commit_attempts, 1, "busy HOLD, CHANNEL, and release submissions never commit later")
	_suite.assert_true(token_before > 0, "fixture began with an authoritative action token")


func _test_reload_live_intent_uses_coordinator_phase_frame() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	runtime.return_reload_utility = true
	var started: Dictionary = coordinator.submit_intent(
		{"id": "weapon_utility", "edge": "pressed"},
		{}
	)
	var token := int(started.get("token", 0))
	_advance(coordinator, 4)
	_suite.assert_equal(coordinator.phase_name(), &"RESOURCE_ACTION", "reload reaches its coordinator-owned resource phase")
	_suite.assert_equal(coordinator.presentation_snapshot().get("phase_frame"), 2, "reload confirm fixture reaches authoritative frame two")

	var confirmed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_utility", "edge": "pressed", "held_frames": 999},
		{"source": "perfect_reload_confirm"}
	)
	_suite.assert_true(bool(confirmed.get("ok", false)), "live reload confirmation is consumed by the active action")
	_suite.assert_equal(confirmed.get("token"), token, "reload confirmation preserves the active action token")
	_suite.assert_equal(runtime.live_confirm_calls, 1, "runtime receives one live confirmation")
	_suite.assert_equal(runtime.live_confirm_phase, &"RESOURCE_ACTION", "runtime receives the coordinator-owned phase")
	_suite.assert_equal(runtime.live_confirm_frame, 2, "runtime receives the coordinator-owned phase frame")
	_suite.assert_equal(runtime.resource, 7, "perfect confirmation commits runtime-owned reload reward")
	_suite.assert_equal(coordinator.phase_name(), &"RECOVERY", "perfect confirmation atomically replaces the remaining tail")
	_suite.assert_equal(coordinator.presentation_snapshot().get("phase_duration_frames"), 4, "perfect confirmation adopts four recovery frames")
	_suite.assert_true(coordinator.snapshot().get("buffered_submission", {}).is_empty(), "live confirmation never enters the ordinary input buffer")
	_suite.assert_equal(runtime.commit_attempts, 1, "live confirmation never recommits the runtime")
	_suite.assert_equal(_committed_facts.size(), 1, "live confirmation never publishes a second committed fact")


func _test_malformed_live_intent_tail_rolls_back_runtime_only() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	runtime.return_reload_utility = true
	runtime.malformed_live_tail = true
	var started: Dictionary = coordinator.submit_intent(
		{"id": "weapon_utility", "edge": "pressed"},
		{}
	)
	var token := int(started.get("token", 0))
	var generation := int(started.get("generation", 0))
	_advance(coordinator, 4)
	var before: Dictionary = coordinator.snapshot()
	var rejected: Dictionary = coordinator.submit_intent(
		{"id": "weapon_utility", "edge": "pressed"},
		{}
	)

	_suite.assert_true(not bool(rejected.get("ok", false)), "malformed live replacement tail fails closed")
	_suite.assert_equal(rejected.get("code"), WeaponActionContractScript.CODE_INVALID_PLAN, "malformed live tail uses the plan contract failure")
	_suite.assert_equal(runtime.resource, 7, "malformed live tail restores the pre-confirm runtime snapshot")
	_suite.assert_equal(coordinator.current_token(), token, "malformed live tail preserves the active reload token")
	_suite.assert_equal(coordinator.generation(), generation, "malformed live tail preserves the active generation")
	_suite.assert_equal(coordinator.phase_name(), &"RESOURCE_ACTION", "malformed live tail leaves reload in its authoritative phase")
	_suite.assert_equal(coordinator.snapshot(), before, "malformed live tail leaves coordinator state unchanged")
	_suite.assert_equal(_committed_facts.size(), 1, "malformed live tail publishes no additional committed fact")


func _test_runtime_tick_uses_coordinator_frame_while_ready_and_busy() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	_advance(coordinator, 3)
	coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	_advance(coordinator, 2)
	_suite.assert_equal(runtime.runtime_tick_frames, [1, 2, 3, 4, 5], "runtime state ticks only from the coordinator's monotonic frame")


func _test_busy_unsupported_sword_semantics_preserve_existing_buffer() -> void:
	for target_phase: StringName in [&"HOLD", &"WINDUP", &"ACTIVE", &"RECOVERY"]:
		var fixture := _fixture()
		var coordinator: RefCounted = fixture["coordinator"]
		var runtime: FakeWeaponRuntime = fixture["runtime"]
		if target_phase == &"HOLD":
			coordinator.submit_intent({"id": "weapon_ultimate", "edge": "pressed"}, {})
		else:
			coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
			if target_phase == &"ACTIVE":
				_advance(coordinator, 6)
			elif target_phase == &"RECOVERY":
				_advance(coordinator, 8)
		_suite.assert_equal(coordinator.phase_name(), target_phase, "%s fixture reaches its busy phase" % str(target_phase))
		_suite.assert_true(not coordinator.recovery_cancel_is_open(), "%s fixture keeps the cancel window closed" % str(target_phase))

		var buffered: Dictionary = coordinator.submit_intent(
			{"id": "weapon_secondary", "edge": "pressed", "buffer_frames": 30},
			{"source": "existing_valid_buffer"}
		)
		_suite.assert_equal(buffered.get("code"), WeaponActionContractScript.CODE_BUFFERED, "%s fixture stores one valid ordinary buffer" % str(target_phase))
		var token_before := int(coordinator.current_token())
		var snapshot_before: Dictionary = coordinator.snapshot()
		runtime.reject_unsupported_sword_semantics = true

		for semantic_action: StringName in [&"weapon_utility", &"weapon_skill", &"weapon_ultimate"]:
			var rejected: Dictionary = coordinator.submit_intent(
				{"id": str(semantic_action), "edge": "pressed", "buffer_frames": 30},
				{"source": "unsupported_sword_semantic"}
			)
			var label := "%s/%s" % [str(target_phase), str(semantic_action)]
			_suite.assert_true(not bool(rejected.get("ok", false)), "%s fails atomically while busy" % label)
			_suite.assert_equal(rejected.get("code"), &"UNSUPPORTED_INTENT", "%s preserves the runtime plan failure" % label)
			_suite.assert_equal(coordinator.snapshot(), snapshot_before, "%s cannot replace the valid buffered action" % label)
			_suite.assert_equal(coordinator.current_token(), token_before, "%s cannot mutate the active token" % label)


func _test_frame_event_buffer_rollback_discards_all_events() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	_suite.assert_true(coordinator.begin_frame_event_buffer(), "frame event rollback fixture opens one buffer")
	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	_suite.assert_true(bool(committed.get("ok", false)), "frame event rollback fixture commits one action")
	_advance(coordinator, 6)
	_suite.assert_equal(_committed_facts, [], "buffered action commit is not observable before settlement")
	_suite.assert_equal(_runtime_events, [], "buffered runtime events are not observable before settlement")
	_suite.assert_equal(_published_event_order, [], "buffered mixed events publish no partial prefix")
	_suite.assert_true(coordinator.rollback_frame_event_buffer(), "matching rollback discards the complete frame buffer")
	_suite.assert_equal(_committed_facts, [], "rollback never publishes the action commit")
	_suite.assert_equal(_runtime_events, [], "rollback never publishes runtime events")
	_suite.assert_equal(_published_event_order, [], "rollback leaves no observable event order")
	_suite.assert_true(not coordinator.rollback_frame_event_buffer(), "frame event rollback is exactly once")
	_suite.assert_true(not coordinator.commit_frame_event_buffer(), "rolled-back frame buffer cannot commit later")


func _test_frame_event_buffer_commit_publishes_once_in_original_order() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	_suite.assert_true(coordinator.begin_frame_event_buffer(), "frame event commit fixture opens one buffer")
	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	_suite.assert_true(bool(committed.get("ok", false)), "frame event commit fixture commits one action")
	_advance(coordinator, 6)
	_suite.assert_equal(_published_event_order, [], "commit fixture remains externally silent until settlement")
	_suite.assert_true(coordinator.commit_frame_event_buffer(), "matching commit flushes the frame buffer")
	_suite.assert_equal(_committed_facts.size(), 1, "frame buffer publishes the action commit exactly once")
	_suite.assert_equal(_runtime_events.size(), 2, "frame buffer publishes both runtime events exactly once")
	_suite.assert_equal(
		_published_event_order,
		[
			"commit:primary_test",
			"runtime:payload_released",
			"runtime:cue_requested",
		],
		"frame buffer preserves the original mixed-signal publication order"
	)
	_suite.assert_true(not coordinator.commit_frame_event_buffer(), "frame event commit is exactly once")
	_suite.assert_true(not coordinator.rollback_frame_event_buffer(), "committed frame buffer cannot roll back later")
	_suite.assert_equal(_committed_facts.size(), 1, "duplicate settlement cannot republish the action commit")
	_suite.assert_equal(_runtime_events.size(), 2, "duplicate settlement cannot republish runtime events")


func _test_frame_event_publication_is_two_phase_and_observer_atomic() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	_suite.assert_true(coordinator.begin_frame_event_buffer(), "two-phase fixture opens one frame buffer")
	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	_suite.assert_true(bool(committed.get("ok", false)), "two-phase fixture commits one action")
	_advance(coordinator, 6)
	var publication: Dictionary = coordinator.prepare_frame_event_publication()
	_suite.assert_true(not publication.is_empty(), "prepare returns an authenticated publication ticket")
	_suite.assert_equal(
		(publication.get("events", []) as Array).size(),
		3,
		"publication ticket freezes every buffered event without emitting"
	)
	_suite.assert_equal(_published_event_order, [], "prepare remains externally silent")

	var isolated_copy := publication.duplicate(true)
	(isolated_copy["events"] as Array).clear()
	_suite.assert_equal(
		(coordinator.prepare_frame_event_publication().get("events", []) as Array).size(),
		3,
		"caller mutation cannot alter the authoritative prepared publication"
	)
	var forged := publication.duplicate(true)
	forged["fingerprint"] = "forged"
	_suite.assert_true(
		not coordinator.finalize_frame_event_publication(forged),
		"finalize rejects a forged publication without consuming the buffer"
	)
	_suite.assert_true(coordinator.frame_event_buffer_is_active(), "forged finalize preserves the live buffer")
	coordinator.set("_frame_event_commit_fault_for_test", true)
	_suite.assert_true(
		coordinator.finalize_frame_event_publication(publication),
		"a successful prepare freezes commit eligibility before fault injection"
	)
	coordinator.set("_frame_event_commit_fault_for_test", false)
	_suite.assert_true(not coordinator.frame_event_buffer_is_active(), "finalize closes the internal frame buffer")
	_suite.assert_equal(_published_event_order, [], "finalize remains externally silent")
	_suite.assert_true(
		not coordinator.begin_frame_event_buffer(),
		"a finalized unpublished batch blocks a replacement buffer"
	)
	_suite.assert_true(
		not coordinator.rollback_frame_event_buffer(),
		"finalized publication cannot be discarded through the old rollback path"
	)

	_publication_observer_coordinator = coordinator
	_publication_observer_begin_results.clear()
	coordinator.weapon_action_committed.connect(_on_weapon_publication_observer)
	coordinator.publish_prepared_frame_events()
	coordinator.weapon_action_committed.disconnect(_on_weapon_publication_observer)
	_publication_observer_coordinator = null
	_suite.assert_equal(
		_publication_observer_begin_results,
		[false],
		"observer re-entry cannot replace the batch while publication is in progress"
	)
	_suite.assert_equal(
		_published_event_order,
		[
			"commit:primary_test",
			"runtime:payload_released",
			"runtime:cue_requested",
		],
		"prepared publication emits once in original mixed-event order"
	)
	coordinator.publish_prepared_frame_events()
	_suite.assert_equal(_committed_facts.size(), 1, "duplicate publish cannot repeat the committed fact")
	_suite.assert_equal(_runtime_events.size(), 2, "duplicate publish cannot repeat runtime events")
	_suite.assert_true(coordinator.begin_frame_event_buffer(), "a new frame buffer may begin after publication")
	_suite.assert_true(coordinator.rollback_frame_event_buffer(), "post-publication buffer remains independently reversible")


func _test_finalized_frame_event_publication_discard_is_authenticated_and_exactly_once() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	_suite.assert_true(coordinator.begin_frame_event_buffer(), "discard fixture opens one frame buffer")
	_suite.assert_true(
		bool(coordinator.submit_intent(
			{"id": "weapon_primary", "edge": "pressed"},
			{}
		).get("ok", false)),
		"discard fixture commits one buffered action"
	)
	_advance(coordinator, 6)
	var publication: Dictionary = coordinator.prepare_frame_event_publication()
	_suite.assert_true(
		coordinator.finalize_frame_event_publication(publication),
		"discard fixture finalizes an observer-invisible publication"
	)

	var forged := publication.duplicate(true)
	forged["fingerprint"] = "forged"
	_suite.assert_true(
		not coordinator.discard_finalized_frame_event_publication(forged),
		"forged finalized event publication cannot be discarded"
	)
	_suite.assert_true(
		not coordinator.begin_frame_event_buffer(),
		"forged discard preserves the authoritative finalized batch"
	)
	coordinator.call(
		"_publish_weapon_runtime_event",
		{"type": &"survives_discard"}
	)
	_suite.assert_true(
		coordinator.discard_finalized_frame_event_publication(publication),
		"authentic finalized event publication is discarded before observers see it"
	)
	_suite.assert_equal(_published_event_order, [], "discard remains completely observer-silent")
	_suite.assert_true(
		not coordinator.discard_finalized_frame_event_publication(publication),
		"finalized event publication discard is exactly once"
	)
	_suite.assert_true(coordinator.begin_frame_event_buffer(), "successful discard releases the next frame buffer")
	var replacement_publication: Dictionary = coordinator.prepare_frame_event_publication()
	_suite.assert_true(
		coordinator.finalize_frame_event_publication(replacement_publication),
		"replacement frame buffer can finalize after discard"
	)
	coordinator.publish_prepared_frame_events()
	_suite.assert_equal(
		_published_event_order,
		["runtime:survives_discard"],
		"successful discard preserves the independent post-publication event queue"
	)


func _test_finalized_frame_event_publication_discard_rejects_publish_reentry() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	_suite.assert_true(coordinator.begin_frame_event_buffer(), "reentrant discard fixture opens one frame buffer")
	_suite.assert_true(
		bool(coordinator.submit_intent(
			{"id": "weapon_primary", "edge": "pressed"},
			{}
		).get("ok", false)),
		"reentrant discard fixture commits one buffered action"
	)
	_advance(coordinator, 6)
	var publication: Dictionary = coordinator.prepare_frame_event_publication()
	_suite.assert_true(
		coordinator.finalize_frame_event_publication(publication),
		"reentrant discard fixture finalizes one publication"
	)

	_publication_observer_coordinator = coordinator
	_publication_observer_discard_publication = publication.duplicate(true)
	_publication_observer_discard_results.clear()
	coordinator.weapon_action_committed.connect(_on_weapon_publication_discard_observer)
	coordinator.publish_prepared_frame_events()
	coordinator.weapon_action_committed.disconnect(_on_weapon_publication_discard_observer)
	_publication_observer_coordinator = null
	_publication_observer_discard_publication.clear()
	_suite.assert_equal(
		_publication_observer_discard_results,
		[false],
		"observer re-entry cannot discard a publication already in progress"
	)
	_suite.assert_equal(
		_published_event_order,
		[
			"commit:primary_test",
			"runtime:payload_released",
			"runtime:cue_requested",
			"runtime:observer_deferred",
		],
		"reentrant discard cannot remove the observer-seen batch or its post-publication queue"
	)
	_suite.assert_true(
		not coordinator.discard_finalized_frame_event_publication(publication),
		"an already published event batch cannot be discarded afterward"
	)


func _test_rewind_safe_reset_preserves_committed_resources() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var provider: FakeResourceProvider = fixture["provider"]
	runtime.external_resource_cost = 20.0
	runtime.action_cooldown_frames = 30
	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	var generation_before := int(committed.get("generation", 0))
	coordinator.restore_rewind_safe_state()
	_suite.assert_equal(coordinator.phase_name(), &"READY", "rewind-safe reset abandons the active action")
	_suite.assert_true(coordinator.generation() > generation_before, "rewind-safe reset invalidates the action generation")
	_suite.assert_close(provider.current, 80.0, "rewind-safe reset does not refund external resource")
	_suite.assert_equal(coordinator.cooldown_remaining(&"primary_test"), 30, "rewind-safe reset preserves committed cooldown")


func _test_gameplay_rewind_cancel_preserves_committed_payload_guard() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var provider: FakeResourceProvider = fixture["provider"]
	runtime.external_resource_cost = 20.0
	runtime.action_cooldown_frames = 30
	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	_suite.assert_true(bool(committed.get("ok", false)), "gameplay rewind fixture commits")
	var payload_guard_before := runtime.gameplay_rewind_committed_payload_guard()
	_suite.assert_true(
		bool(coordinator.cancel_for_gameplay_rewind()),
		"gameplay rewind cancel succeeds"
	)
	_suite.assert_equal(coordinator.phase_name(), &"READY", "gameplay rewind clears action-local phase")
	_suite.assert_equal(runtime.gameplay_rewind_cancel_calls, 1, "runtime receives the payload-preserving cancel")
	_suite.assert_equal(
		runtime.gameplay_rewind_committed_payload_guard(),
		payload_guard_before,
		"committed payload identity, snapshot, and hit claims remain exact"
	)
	_suite.assert_close(provider.current, 80.0, "gameplay rewind cancel preserves committed external cost")
	_suite.assert_equal(coordinator.cooldown_remaining(&"primary_test"), 30, "gameplay rewind cancel preserves cooldown")


func _test_gameplay_rewind_rollback_restores_windup_local_state_exactly() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	_suite.assert_true(bool(committed.get("ok", false)), "rollback fixture commits")
	var before: Dictionary = coordinator.gameplay_rewind_snapshot()
	_suite.assert_true(bool(coordinator.cancel_for_gameplay_rewind()), "rollback fixture cancels")
	_suite.assert_true(
		bool(coordinator.restore_gameplay_rewind_snapshot_for_rollback(before)),
		"rollback restores the cancelled action"
	)
	_suite.assert_equal(
		coordinator.gameplay_rewind_snapshot(),
		before,
		"rollback restores coordinator and runtime action-local bytes exactly"
	)
	_suite.assert_equal(runtime.gameplay_rewind_restore_calls, 1, "runtime local state restores once")


func _test_gameplay_rewind_rollback_restores_hold_without_refunding_authority() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var provider: FakeResourceProvider = fixture["provider"]
	var started: Dictionary = coordinator.submit_intent(
		{"id": "weapon_ultimate", "edge": "pressed"},
		{}
	)
	_suite.assert_true(bool(started.get("ok", false)), "HOLD rollback fixture starts")
	_suite.assert_equal(runtime.resource, 7, "fixture exposes provisional HOLD runtime state")
	var before: Dictionary = coordinator.gameplay_rewind_snapshot()
	_suite.assert_true(bool(coordinator.cancel_for_gameplay_rewind()), "HOLD cancel succeeds")
	_suite.assert_equal(runtime.resource, 8, "unreleased HOLD cancel restores its press snapshot")
	_suite.assert_close(provider.current, 100.0, "unreleased HOLD never spends external authority")
	_suite.assert_true(
		bool(coordinator.restore_gameplay_rewind_snapshot_for_rollback(before)),
		"transaction rollback restores the exact pre-cancel HOLD"
	)
	_suite.assert_equal(runtime.resource, 7, "rollback restores provisional HOLD runtime state exactly")
	_suite.assert_close(provider.current, 100.0, "rollback cannot mint or spend external authority")


func _test_gameplay_rewind_rejects_payload_identity_drift() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	coordinator.submit_intent({"id": "weapon_primary", "edge": "pressed"}, {})
	var before: Dictionary = coordinator.gameplay_rewind_snapshot()
	_suite.assert_true(bool(coordinator.cancel_for_gameplay_rewind()), "identity drift fixture cancels")
	runtime.committed_payload_guard["instance_ids"] = [202]
	var cancelled_state: Dictionary = coordinator.gameplay_rewind_snapshot()
	_suite.assert_true(
		not bool(coordinator.restore_gameplay_rewind_snapshot_for_rollback(before)),
		"rollback rejects replaced committed payload identity"
	)
	_suite.assert_equal(
		coordinator.gameplay_rewind_snapshot(),
		cancelled_state,
		"rejected rollback cannot mutate cancelled local state"
	)


func _test_gameplay_rewind_cancel_rollback_failure_forces_fail_closed() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var provider: FakeResourceProvider = fixture["provider"]
	var transaction: RefCounted = fixture["resource_transaction"]
	runtime.external_resource_cost = 20.0
	runtime.action_cooldown_frames = 30
	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	var generation_before := int(committed.get("generation", 0))
	runtime.mutate_before_failed_gameplay_rewind_cancel = true
	runtime.fail_gameplay_rewind_cancel = true
	runtime.fail_gameplay_rewind_restore = true

	_suite.assert_true(
		not bool(coordinator.cancel_for_gameplay_rewind()),
		"failed Gameplay Rewind cancel reports failure"
	)
	_suite.assert_equal(coordinator.phase_name(), &"READY", "unrecoverable cancel clears the coordinator action")
	_suite.assert_equal(coordinator.current_token(), 0, "unrecoverable cancel clears the coordinator token")
	_suite.assert_true(coordinator.generation() > generation_before, "unrecoverable cancel invalidates the action generation")
	_suite.assert_equal(runtime.reset_calls, 1, "unrecoverable cancel resets the divergent runtime once")
	_suite.assert_true(
		not bool(transaction.snapshot().get("configured", true)),
		"unrecoverable cancel fails the resource transaction closed"
	)
	_suite.assert_close(provider.current, 80.0, "fail-closed cancel cannot refund a committed external cost")


func _test_gameplay_rewind_restore_rollback_failure_forces_fail_closed() -> void:
	var fixture := _fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: FakeWeaponRuntime = fixture["runtime"]
	var provider: FakeResourceProvider = fixture["provider"]
	var transaction: RefCounted = fixture["resource_transaction"]
	runtime.external_resource_cost = 20.0
	runtime.action_cooldown_frames = 30
	var committed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_primary", "edge": "pressed"},
		{}
	)
	var target: Dictionary = coordinator.gameplay_rewind_snapshot()
	_suite.assert_true(bool(coordinator.cancel_for_gameplay_rewind()), "restore failure fixture cancels normally")
	var cancelled_generation: int = int(coordinator.generation())
	runtime.mutate_before_failed_gameplay_rewind_restore = true
	runtime.fail_gameplay_rewind_restore = true

	_suite.assert_true(
		not bool(coordinator.restore_gameplay_rewind_snapshot_for_rollback(target)),
		"failed Gameplay Rewind restore reports failure"
	)
	_suite.assert_equal(coordinator.phase_name(), &"READY", "unrecoverable restore leaves no active coordinator action")
	_suite.assert_equal(coordinator.current_token(), 0, "unrecoverable restore leaves no active token")
	_suite.assert_true(coordinator.generation() > cancelled_generation, "unrecoverable restore advances the generation floor")
	_suite.assert_equal(runtime.reset_calls, 1, "unrecoverable restore resets the divergent runtime once")
	_suite.assert_true(
		not bool(transaction.snapshot().get("configured", true)),
		"unrecoverable restore fails the resource transaction closed"
	)
	_suite.assert_close(provider.current, 80.0, "fail-closed restore cannot refund a committed external cost")
	_suite.assert_true(bool(committed.get("ok", false)), "restore failure fixture committed before cancellation")


func _extended_hold_plan() -> Dictionary:
	return {
		"weapon_id": "test_weapon",
		"action_id": "extended_hold",
		"phases": [
			{
				"phase": "HOLD",
				"duration_frames": 5,
				"minimum_hold_frames": 2,
				"charge_complete_frames": 4,
				"hold_progress_multiplier": 1.25,
				"movement_start_multiplier": 1.0,
				"movement_multiplier": 0.65,
			},
			{"phase": "WINDUP", "duration_frames": 1},
		],
		"payloads": [],
	}


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
	_runtime_events.clear()
	_published_event_order.clear()
	var runtime := FakeWeaponRuntime.new()
	var provider := FakeResourceProvider.new()
	var resource_transaction = WeaponResourceTransactionScript.new()
	_suite.assert_true(
		resource_transaction.configure(
			&"test_weapon",
			PackedStringArray(),
			{&"time_energy": provider}
		),
		"coordinator resource transaction fixture configures"
	)
	var coordinator = WeaponActionCoordinatorScript.new()
	_suite.assert_true(
		coordinator.configure(runtime, resource_transaction),
		"coordinator accepts runtime and resource transaction fixtures"
	)
	coordinator.weapon_action_committed.connect(_on_weapon_action_committed)
	coordinator.weapon_runtime_event.connect(_on_weapon_runtime_event)
	return {
		"coordinator": coordinator,
		"runtime": runtime,
		"provider": provider,
		"resource_transaction": resource_transaction,
	}


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
	_published_event_order.append("commit:%s" % str(action_id))
	_committed_facts.append({
		"weapon_id": str(weapon_id),
		"action_id": str(action_id),
		"token": token,
		"context": context.duplicate(true),
	})


func _on_weapon_runtime_event(event: Dictionary) -> void:
	_published_event_order.append("runtime:%s" % str(event.get("type", "")))
	_runtime_events.append(event.duplicate(true))


func _on_weapon_publication_observer(
	_weapon_id: StringName,
	_action_id: StringName,
	_token: int,
	_context: Dictionary
) -> void:
	_publication_observer_begin_results.append(
		_publication_observer_coordinator != null
		and bool(_publication_observer_coordinator.call("begin_frame_event_buffer"))
	)


func _on_weapon_publication_discard_observer(
	_weapon_id: StringName,
	_action_id: StringName,
	_token: int,
	_context: Dictionary
) -> void:
	if _publication_observer_coordinator == null:
		return
	_publication_observer_coordinator.call(
		"_publish_weapon_runtime_event",
		{"type": &"observer_deferred"}
	)
	_publication_observer_discard_results.append(bool(
		_publication_observer_coordinator.call(
			"discard_finalized_frame_event_publication",
			_publication_observer_discard_publication.duplicate(true)
		)
	))
