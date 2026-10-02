extends Node

const DungeonEventRuntimeScript := preload("res://scripts/events/dungeon_event_runtime.gd")
const DungeonEventSelectorScript := preload("res://scripts/events/dungeon_event_selector.gd")
const DungeonEventRunStateScript := preload("res://scripts/events/dungeon_event_run_state.gd")
const EventRequirementServiceScript := preload("res://scripts/events/event_requirement_service.gd")
const ConsequenceRuntimeScript := preload("res://scripts/events/dungeon_event_consequence_runtime.gd")
const EventResourceAuthorityScript := preload("res://scripts/events/event_resource_authority.gd")
const EventHealthAuthorityScript := preload("res://scripts/events/event_health_authority.gd")
const EventModifierAuthorityScript := preload("res://scripts/events/event_modifier_authority.gd")
const EventRouteAuthorityScript := preload("res://scripts/events/event_route_authority.gd")
const RunEconomyStateScript := preload("res://scripts/economy/run_economy_state.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")
const SeedServiceScript := preload("res://scripts/core/seed_service.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const CONTENT_FINGERPRINT := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const PUBLICATION_SECRET := "task5-test-publication-secret-0123456789abcdef0123456789abcdef"
const ECONOMY_PROFILE_PATH := "res://data/content_packs/base/content/economy_profiles.json"
const VIEW_FIELDS: Array[String] = [
	"description_key", "event_id", "name_key", "options", "pending_kind",
	"phase", "prompt_key", "result_key", "revision",
]
const OPTION_VIEW_FIELDS: Array[String] = [
	"disabled_reason_key", "eligible", "id", "label_key", "outcome_visibility",
	"visible_preview",
]


class CountingSelector:
	extends RefCounted
	var inner = DungeonEventSelectorScript.new()
	var calls := 0

	func select(definitions: Array, context: Dictionary) -> Dictionary:
		calls += 1
		return inner.select(definitions, context)


var _global_revision := 10
var _provided_context: Dictionary = {}
var _state_writes: Array[Dictionary] = []
var _facts: Array[Dictionary] = []
var _fact_attempts: Array[String] = []
var _external_fact_ids: Dictionary = {}
var _fail_next_fact_count := 0
var _fail_state_operation := ""
var _fail_state_count := 0
var _reenter_runtime: RefCounted
var _reenter_once := false
var _reentry_results: Array[Dictionary] = []
var _reentry_configure_args: Array = []
var _reentry_configure_result := true
var _reentry_restore_result := true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_open_freezes_assignment_and_view_is_safe(suite)
	_test_disabled_reason_and_preview_category(suite)
	_test_hidden_weighted_outcome_channel_and_immediate_resolution(suite)
	_test_pending_reward_continuation_and_restore(suite)
	_test_pending_encounter_continuation(suite)
	_test_stale_duplicate_choice_dismissal_and_exactly_once_facts(suite)
	_test_floor_index_is_zero_based(suite)
	_test_durable_outbox_retries_every_publication_stage(suite)
	_test_outbox_ack_failure_is_idempotent(suite)
	_test_pending_outbox_restore_and_fact_poisoning(suite)
	_test_synchronous_fact_sink_reentry_is_blocked(suite)
	_test_publication_ledger_rejects_partition_and_payload_mutation(suite)
	_test_encounter_success_payload_is_authoritative(suite)
	suite.finish(get_tree())


func _test_open_freezes_assignment_and_view_is_safe(suite) -> void:
	var selector = CountingSelector.new()
	var fixture := _fixture([_immediate_event()], selector)
	var runtime: RefCounted = fixture["runtime"]
	var opened: Dictionary = runtime.call("open_event", _room(), {})
	suite.assert_true(bool(opened.get("ok", false)), "first open assigns the selected event")
	suite.assert_equal(selector.calls, 1, "first open invokes deterministic selection once")
	suite.assert_equal(_state_writes.size(), 2, "first open persists assignment and publication ack")
	suite.assert_equal(_facts.size(), 1, "first open publishes one opened fact")
	var first_view: Dictionary = runtime.call("view_state")
	_assert_view_is_safe(suite, first_view, "first open view")
	suite.assert_equal(first_view["event_id"], "event_chronal_altar", "selected event is projected")
	suite.assert_equal(first_view["phase"], "open", "new assignment is open")
	suite.assert_equal(first_view["revision"], 12, "view uses caller global revision")

	_provided_context["selection"]["primary_event_id"] = "event_trapped_traveler"
	var reopened: Dictionary = runtime.call("open_event", _room("event_trapped_traveler"), {})
	suite.assert_true(bool(reopened.get("ok", false)), "reopening assigned node is idempotent")
	suite.assert_equal(selector.calls, 1, "reopen does not rerun selection")
	suite.assert_equal(_state_writes.size(), 2, "reopen does not rewrite authoritative state")
	suite.assert_equal(_facts.size(), 1, "reopen does not republish opened fact")
	suite.assert_equal(runtime.call("view_state")["event_id"], "event_chronal_altar", "assignment remains frozen")


func _test_disabled_reason_and_preview_category(suite) -> void:
	var fixture := _fixture([_immediate_event()], CountingSelector.new(), 10)
	var runtime: RefCounted = fixture["runtime"]
	suite.assert_true(bool(runtime.call("open_event", _room(), {}).get("ok", false)), "disabled fixture opens")
	var view: Dictionary = runtime.call("view_state")
	var commit := _option_view(view, "commit")
	suite.assert_true(not bool(commit["eligible"]), "unaffordable option is disabled")
	suite.assert_equal(
		commit["disabled_reason_key"],
		"EVENT_REQUIREMENT_GOLD_MIN",
		"disabled option exposes the exact authored requirement reason"
	)
	suite.assert_equal(
		commit["visible_preview"],
		["EVENT_PREVIEW_MODIFIER"],
		"preview_category exposes only safe semantic categories"
	)
	var before: Dictionary = runtime.call("snapshot")
	var rejected: Dictionary = runtime.call("choose_option", &"commit", _global_revision)
	suite.assert_equal(rejected.get("code"), &"OPTION_INELIGIBLE", "disabled choice rejects")
	suite.assert_equal(
		(rejected.get("context", {}) as Dictionary).get("disabled_reason_key"),
		"EVENT_REQUIREMENT_GOLD_MIN",
		"choice rejection retains the exact safe reason"
	)
	suite.assert_equal(runtime.call("snapshot"), before, "disabled choice is atomic")


func _test_hidden_weighted_outcome_channel_and_immediate_resolution(suite) -> void:
	var run_seed := _seed_for_roll("event_outcome_v1:event_void_whispers:event_node", 2, 1)
	var fixture := _fixture([_hidden_event()], CountingSelector.new(), 100, run_seed, 1)
	var runtime: RefCounted = fixture["runtime"]
	suite.assert_true(bool(runtime.call("open_event", _room("event_void_whispers", 1), {}).get("ok", false)), "hidden event opens")
	var open_view: Dictionary = runtime.call("view_state")
	var hidden := _option_view(open_view, "commit")
	suite.assert_equal(hidden["visible_preview"], [], "hidden outcome exposes no precommit preview")
	_assert_no_secret_values(suite, open_view, [
		"power_bargain", "guard_bargain", "void_bargain_power", "void_bargain_guard",
		"curse_brittle_fortune", "curse_fickle_time",
	], "hidden view redaction")

	var chosen: Dictionary = runtime.call("choose_option", &"commit", _global_revision)
	suite.assert_true(bool(chosen.get("ok", false)), "hidden weighted choice commits")
	var resolved: Dictionary = runtime.call("view_state")
	_assert_view_is_safe(suite, resolved, "resolved hidden view")
	suite.assert_equal(resolved["phase"], "resolved", "immediate consequence resolves in one command")
	suite.assert_equal(resolved["result_key"], "EVENT_VOID_WHISPERS_RESULT", "resolved result key is visible after commit")
	var event_snapshot := _event_state_snapshot(runtime.call("snapshot"))
	var assignment := event_snapshot["selected_event_by_node"]["floor_01_ruins:event_node"] as Dictionary
	suite.assert_equal(assignment["outcome_id"], "guard_bargain", "weighted roll uses exact event/node channel")


func _test_pending_reward_continuation_and_restore(suite) -> void:
	var fixture := _fixture([_reward_event()], CountingSelector.new())
	var runtime: RefCounted = fixture["runtime"]
	suite.assert_true(bool(runtime.call("open_event", _room("event_trapped_traveler"), {}).get("ok", false)), "reward event opens")
	suite.assert_true(bool(runtime.call("choose_option", &"commit", _global_revision).get("ok", false)), "reward option enters pending")
	var pending_view: Dictionary = runtime.call("view_state")
	_assert_view_is_safe(suite, pending_view, "pending reward view")
	suite.assert_equal(pending_view["phase"], "pending_reward", "reward draft remains pending")
	suite.assert_equal(pending_view["pending_kind"], "reward", "pending reward kind is projected")
	var saved: Dictionary = runtime.call("snapshot")
	var continuation_id := str(_event_state_snapshot(saved)["pending_reward"]["continuation_id"])
	_assert_no_secret_values(suite, pending_view, [continuation_id, "item"], "pending reward redaction")

	var restored_fixture := _fixture([_reward_event()], CountingSelector.new())
	var restored: RefCounted = restored_fixture["runtime"]
	suite.assert_true(bool(restored.call("restore_snapshot", saved)), "pending reward snapshot restores")
	suite.assert_equal(restored.call("snapshot"), saved, "runtime restore is byte-identical")
	suite.assert_equal(restored.call("view_state")["phase"], "pending_reward", "restored pending phase projects")
	var completed: Dictionary = restored.call(
		"complete_reward", continuation_id, {"reward_id": "reward_fixture"}, _global_revision
	)
	suite.assert_true(bool(completed.get("ok", false)), "authenticated reward continuation resolves")
	suite.assert_equal(restored.call("view_state")["phase"], "resolved", "reward completion resolves event")
	var fact_count := _facts.size()
	var duplicate: Dictionary = restored.call(
		"complete_reward", continuation_id, {"reward_id": "reward_fixture"}, _global_revision
	)
	suite.assert_equal(duplicate.get("code"), &"PENDING_REWARD_NOT_FOUND", "reward continuation completes once")
	suite.assert_equal(_facts.size(), fact_count, "duplicate reward completion publishes no fact")


func _test_pending_encounter_continuation(suite) -> void:
	var fixture := _fixture([_encounter_event()], CountingSelector.new())
	var runtime: RefCounted = fixture["runtime"]
	suite.assert_true(bool(runtime.call("open_event", _room("event_sleeping_guardian"), {}).get("ok", false)), "encounter event opens")
	suite.assert_true(bool(runtime.call("choose_option", &"commit", _global_revision).get("ok", false)), "encounter option enters pending")
	var event_snapshot := _event_state_snapshot(runtime.call("snapshot"))
	var continuation_id := str(event_snapshot["pending_encounter"]["continuation_id"])
	var pending_view: Dictionary = runtime.call("view_state")
	suite.assert_equal(pending_view["phase"], "pending_encounter", "encounter remains pending")
	suite.assert_equal(pending_view["pending_kind"], "encounter", "pending encounter kind is projected")
	_assert_no_secret_values(
		suite,
		pending_view,
		[continuation_id, "encounter_profile_ruins_adapter_v1"],
		"pending encounter redaction"
	)
	var wrong: Dictionary = runtime.call(
		"complete_encounter", "wrong_continuation", true, {}, _global_revision
	)
	suite.assert_equal(wrong.get("code"), &"CONTINUATION_MISMATCH", "wrong encounter continuation rejects")
	var completed: Dictionary = runtime.call(
		"complete_encounter", continuation_id, true, {"encounter_result": "victory"}, _global_revision
	)
	suite.assert_true(bool(completed.get("ok", false)), "authenticated encounter continuation resolves")
	suite.assert_equal(runtime.call("view_state")["phase"], "resolved", "encounter completion resolves event")


func _test_stale_duplicate_choice_dismissal_and_exactly_once_facts(suite) -> void:
	var fixture := _fixture([_immediate_event()], CountingSelector.new())
	var runtime: RefCounted = fixture["runtime"]
	runtime.call("open_event", _room(), {})
	var before: Dictionary = runtime.call("snapshot")
	var stale: Dictionary = runtime.call("choose_option", &"commit", _global_revision - 1)
	suite.assert_equal(stale.get("code"), &"STALE_REVISION", "stale choice rejects")
	suite.assert_equal(runtime.call("snapshot"), before, "stale choice is atomic")
	var facts_before := _facts.size()
	suite.assert_true(bool(runtime.call("choose_option", &"commit", _global_revision).get("ok", false)), "fresh choice resolves")
	suite.assert_equal(_facts.size(), facts_before + 1, "resolved choice publishes one fact")
	var facts_after := _facts.size()
	var duplicate: Dictionary = runtime.call("choose_option", &"commit", _global_revision)
	suite.assert_equal(duplicate.get("code"), &"EVENT_NOT_OPEN", "resolved event rejects duplicate choice")
	suite.assert_equal(_facts.size(), facts_after, "duplicate choice cannot republish")
	var stale_dismiss: Dictionary = runtime.call("dismiss_result", _global_revision - 1)
	suite.assert_equal(stale_dismiss.get("code"), &"STALE_REVISION", "stale dismissal rejects")
	var dismissed: Dictionary = runtime.call("dismiss_result", _global_revision)
	suite.assert_true(bool(dismissed.get("ok", false)), "resolved result dismisses")
	var view: Dictionary = runtime.call("view_state")
	suite.assert_equal(view["phase"], "dismissed", "dismissed phase projects")
	suite.assert_equal(view["result_key"], "EVENT_CHRONAL_ALTAR_RESULT", "dismissal retains result key")
	suite.assert_equal(_unique_fact_ids().size(), _facts.size(), "all emitted fact IDs are exactly once")


func _test_floor_index_is_zero_based(suite) -> void:
	var floor_one := _fixture([_floor_gate_event()], CountingSelector.new(), 100, 42, 0)
	var first_runtime: RefCounted = floor_one["runtime"]
	suite.assert_true(bool(first_runtime.call("open_event", _room("event_chronal_altar", 0), {}).get("ok", false)), "floor one fixture opens")
	var first_option := _option_view(first_runtime.call("view_state"), "commit")
	suite.assert_true(not bool(first_option["eligible"]), "runtime floor zero fails authored floor two minimum")
	suite.assert_equal(first_option["disabled_reason_key"], "EVENT_REQUIREMENT_FLOOR_INDEX_MIN", "floor one rejection is exact")

	var floor_two := _fixture([_floor_gate_event()], CountingSelector.new(), 100, 42, 1)
	var second_runtime: RefCounted = floor_two["runtime"]
	suite.assert_true(bool(second_runtime.call("open_event", _room("event_chronal_altar", 1), {}).get("ok", false)), "floor two fixture opens")
	var second_option := _option_view(second_runtime.call("view_state"), "commit")
	suite.assert_true(bool(second_option["eligible"]), "runtime floor one satisfies authored floor two minimum")


func _test_durable_outbox_retries_every_publication_stage(suite) -> void:
	var open_fixture := _fixture([_immediate_event()], CountingSelector.new())
	var open_runtime: RefCounted = open_fixture["runtime"]
	_fail_next_fact_count = 1
	var open_failed: Dictionary = open_runtime.call("open_event", _room(), {})
	_assert_publication_pending(suite, open_failed, "open fact failure")
	suite.assert_equal((open_runtime.call("snapshot")["pending_facts"] as Array).size(), 1, "open fact remains durable")
	suite.assert_equal(_state_writes.size(), 1, "open candidate persists before external publication")
	_assert_state_candidate_has_outbox(suite, _state_writes[0], 1, 0, "open candidate")
	suite.assert_true(bool(open_runtime.call("open_event", _room(), {}).get("ok", false)), "reopen retries pending open fact")
	suite.assert_equal(_fact_effect_count("event_opened:"), 1, "open fact has one external effect")
	suite.assert_equal((open_runtime.call("snapshot")["pending_facts"] as Array).size(), 0, "open retry acknowledges outbox")

	var choose_fixture := _fixture([_immediate_event()], CountingSelector.new())
	var choose_runtime: RefCounted = choose_fixture["runtime"]
	choose_runtime.call("open_event", _room(), {})
	_fail_next_fact_count = 1
	var choose_failed: Dictionary = choose_runtime.call("choose_option", &"commit", _global_revision)
	_assert_publication_pending(suite, choose_failed, "choice fact failure")
	var duplicate_choice: Dictionary = choose_runtime.call("choose_option", &"commit", _global_revision)
	suite.assert_equal(duplicate_choice.get("code"), &"EVENT_NOT_OPEN", "duplicate choice flushes before phase rejection")
	suite.assert_equal(_fact_effect_count("event_committed:"), 1, "choice fact has one external effect")

	var continuation_fixture := _fixture([_reward_event()], CountingSelector.new())
	var continuation_runtime: RefCounted = continuation_fixture["runtime"]
	continuation_runtime.call("open_event", _room("event_trapped_traveler"), {})
	continuation_runtime.call("choose_option", &"commit", _global_revision)
	var continuation_id := str(_event_state_snapshot(continuation_runtime.call("snapshot"))["pending_reward"]["continuation_id"])
	_fail_next_fact_count = 1
	var continuation_failed: Dictionary = continuation_runtime.call(
		"complete_reward", continuation_id, {"reward_id": "reward_fixture"}, _global_revision
	)
	_assert_publication_pending(suite, continuation_failed, "continuation fact failure")
	var duplicate_continuation: Dictionary = continuation_runtime.call(
		"complete_reward", continuation_id, {"reward_id": "reward_fixture"}, _global_revision
	)
	suite.assert_equal(duplicate_continuation.get("code"), &"PENDING_REWARD_NOT_FOUND", "duplicate continuation flushes before rejection")
	suite.assert_equal(_fact_effect_count("event_reward_completed:"), 1, "continuation fact has one external effect")

	var dismiss_fixture := _fixture([_immediate_event()], CountingSelector.new())
	var dismiss_runtime: RefCounted = dismiss_fixture["runtime"]
	dismiss_runtime.call("open_event", _room(), {})
	dismiss_runtime.call("choose_option", &"commit", _global_revision)
	_fail_next_fact_count = 1
	var dismiss_failed: Dictionary = dismiss_runtime.call("dismiss_result", _global_revision)
	_assert_publication_pending(suite, dismiss_failed, "dismiss fact failure")
	var duplicate_dismiss: Dictionary = dismiss_runtime.call("dismiss_result", _global_revision)
	suite.assert_equal(duplicate_dismiss.get("code"), &"RESULT_NOT_RESOLVED", "duplicate dismiss flushes before rejection")
	suite.assert_equal(_fact_effect_count("event_dismissed:"), 1, "dismiss fact has one external effect")


func _test_outbox_ack_failure_is_idempotent(suite) -> void:
	var fixture := _fixture([_immediate_event()], CountingSelector.new())
	var runtime: RefCounted = fixture["runtime"]
	runtime.call("open_event", _room(), {})
	_fail_state_operation = "ack_event_fact"
	_fail_state_count = 1
	var failed: Dictionary = runtime.call("choose_option", &"commit", _global_revision)
	_assert_publication_pending(suite, failed, "fact ack failure")
	suite.assert_equal(_fact_effect_count("event_committed:"), 1, "fact reaches external sink before ack failure")
	suite.assert_equal((runtime.call("snapshot")["pending_facts"] as Array).size(), 1, "ack failure keeps pending fact")
	var retried: Dictionary = runtime.call("choose_option", &"commit", _global_revision)
	suite.assert_equal(retried.get("code"), &"EVENT_NOT_OPEN", "retry acknowledges before duplicate rejection")
	suite.assert_equal(_fact_effect_count("event_committed:"), 1, "idempotency key prevents a second external effect")
	suite.assert_equal(_fact_attempt_count("event_committed:"), 2, "ack recovery safely retries the same fact ID")
	suite.assert_equal((runtime.call("snapshot")["pending_facts"] as Array).size(), 0, "ack recovery drains pending fact")


func _test_pending_outbox_restore_and_fact_poisoning(suite) -> void:
	var source_fixture := _fixture([_immediate_event()], CountingSelector.new())
	var source: RefCounted = source_fixture["runtime"]
	source.call("open_event", _room(), {})
	_fail_next_fact_count = 1
	var failed: Dictionary = source.call("choose_option", &"commit", _global_revision)
	_assert_publication_pending(suite, failed, "save fixture fact failure")
	var saved: Dictionary = source.call("snapshot")
	suite.assert_equal((saved["pending_facts"] as Array).size(), 1, "save snapshot retains pending outbox")
	var assignment := _event_state_snapshot(saved)["selected_event_by_node"]["floor_01_ruins:event_node"] as Dictionary
	var transaction_id := str(assignment["transaction_id"])

	var restored_fixture := _fixture([_immediate_event()], CountingSelector.new())
	var restored: RefCounted = restored_fixture["runtime"]
	var forged_emitted := saved.duplicate(true)
	(forged_emitted["emitted_fact_ids"] as Array).append("event_dismissed:%s" % transaction_id)
	(forged_emitted["emitted_fact_ids"] as Array).sort()
	suite.assert_true(not bool(restored.call("restore_snapshot", forged_emitted)), "future emitted fact poisoning rejects")
	var forged_pending := saved.duplicate(true)
	(forged_pending["pending_facts"] as Array).append({
		"fact_id": "event_dismissed:%s" % transaction_id,
		"payload": {"kind": "event_dismissed"},
	})
	(forged_pending["pending_facts"] as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["fact_id"]) < str(right["fact_id"])
	)
	suite.assert_true(not bool(restored.call("restore_snapshot", forged_pending)), "future pending fact poisoning rejects")
	suite.assert_true(bool(restored.call("restore_snapshot", saved)), "pending outbox snapshot restores")
	suite.assert_equal(restored.call("snapshot"), saved, "pending outbox restore is byte-identical")
	suite.assert_true(bool(restored.call("flush_pending_facts").get("ok", false)), "restored pending fact flushes")
	suite.assert_equal(_fact_effect_count("event_committed:"), 1, "restored outbox publishes once")
	suite.assert_equal((restored.call("snapshot")["pending_facts"] as Array).size(), 0, "restored outbox drains")


func _test_synchronous_fact_sink_reentry_is_blocked(suite) -> void:
	var fixture := _fixture([_immediate_event()], CountingSelector.new())
	var runtime: RefCounted = fixture["runtime"]
	_reenter_runtime = runtime
	_reentry_configure_args = (fixture["configure_args"] as Array).duplicate()
	_reenter_once = true
	var opened: Dictionary = runtime.call("open_event", _room(), {})
	suite.assert_true(bool(opened.get("ok", false)), "outer publication completes after blocked reentry")
	suite.assert_equal(_reentry_results.size(), 2, "fact sink attempted both nested entry points")
	for result: Dictionary in _reentry_results:
		suite.assert_equal(result.get("code"), &"PUBLICATION_IN_PROGRESS", "nested mutation is typed and deferred")
	suite.assert_true(not _reentry_configure_result, "configure rejects during synchronous delivery")
	suite.assert_true(not _reentry_restore_result, "restore rejects during synchronous delivery")
	suite.assert_equal(_fact_attempt_count("event_opened:"), 1, "synchronous reentry never invokes fact sink twice")
	suite.assert_equal(_fact_effect_count("event_opened:"), 1, "outer publication has exactly one external effect")
	suite.assert_equal((runtime.call("snapshot")["pending_facts"] as Array).size(), 0, "outer ack drains outbox")


func _test_publication_ledger_rejects_partition_and_payload_mutation(suite) -> void:
	var pending_fixture := _fixture([_immediate_event()], CountingSelector.new())
	var pending_runtime: RefCounted = pending_fixture["runtime"]
	pending_runtime.call("open_event", _room(), {})
	_fail_next_fact_count = 1
	pending_runtime.call("choose_option", &"commit", _global_revision)
	var pending_saved: Dictionary = pending_runtime.call("snapshot")
	suite.assert_true(pending_saved.has("publication_ledger"), "snapshot carries authenticated publication ledger")
	suite.assert_true(pending_saved.has("publication_digest"), "snapshot carries publication digest")
	if not pending_saved.has("publication_ledger"):
		return
	var pending_index := _ledger_entry_index(pending_saved, "event_committed:")
	suite.assert_true(pending_index >= 0, "pending ledger contains committed fact")
	if pending_index < 0:
		return
	var swapped_to_emitted := pending_saved.duplicate(true)
	var pending_entry := (swapped_to_emitted["publication_ledger"] as Array)[pending_index] as Dictionary
	var pending_fact_id := str(pending_entry["fact_id"])
	(swapped_to_emitted["pending_facts"] as Array).clear()
	(swapped_to_emitted["emitted_fact_ids"] as Array).append(pending_fact_id)
	(swapped_to_emitted["emitted_fact_ids"] as Array).sort()
	pending_entry["status"] = "emitted"
	suite.assert_true(not bool(pending_runtime.call("restore_snapshot", swapped_to_emitted)), "pending to emitted partition swap rejects")
	var payload_mutation := pending_saved.duplicate(true)
	((payload_mutation["publication_ledger"] as Array)[pending_index]["payload"] as Dictionary)["debug"] = true
	suite.assert_true(not bool(pending_runtime.call("restore_snapshot", payload_mutation)), "ledger payload extra field rejects")
	var pending_payload_mutation := pending_saved.duplicate(true)
	((pending_payload_mutation["pending_facts"] as Array)[0]["payload"] as Dictionary)["debug"] = true
	suite.assert_true(not bool(pending_runtime.call("restore_snapshot", pending_payload_mutation)), "pending payload extra field rejects")
	var wrong_secret_fixture := _fixture(
		[_immediate_event()],
		CountingSelector.new(),
		100,
		42,
		0,
		"wrong-publication-secret-0123456789abcdef0123456789abcdef"
	)
	var wrong_secret_runtime: RefCounted = wrong_secret_fixture["runtime"]
	suite.assert_true(not bool(wrong_secret_runtime.call("restore_snapshot", pending_saved)), "wrong publication secret rejects restore")

	var emitted_fixture := _fixture([_immediate_event()], CountingSelector.new())
	var emitted_runtime: RefCounted = emitted_fixture["runtime"]
	emitted_runtime.call("open_event", _room(), {})
	emitted_runtime.call("choose_option", &"commit", _global_revision)
	var emitted_saved: Dictionary = emitted_runtime.call("snapshot")
	var emitted_index := _ledger_entry_index(emitted_saved, "event_committed:")
	suite.assert_true(emitted_index >= 0, "emitted ledger contains committed fact")
	if emitted_index < 0:
		return
	var swapped_to_pending := emitted_saved.duplicate(true)
	var emitted_entry := (swapped_to_pending["publication_ledger"] as Array)[emitted_index] as Dictionary
	var emitted_fact_id := str(emitted_entry["fact_id"])
	(swapped_to_pending["emitted_fact_ids"] as Array).erase(emitted_fact_id)
	(swapped_to_pending["pending_facts"] as Array).append({
		"fact_id": emitted_fact_id,
		"payload": (emitted_entry["payload"] as Dictionary).duplicate(true),
	})
	(swapped_to_pending["pending_facts"] as Array).sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return str(left["fact_id"]) < str(right["fact_id"])
	)
	emitted_entry["status"] = "pending"
	suite.assert_true(not bool(emitted_runtime.call("restore_snapshot", swapped_to_pending)), "emitted to pending partition swap rejects")


func _test_encounter_success_payload_is_authoritative(suite) -> void:
	var true_fixture := _fixture([_encounter_event()], CountingSelector.new())
	var true_runtime: RefCounted = true_fixture["runtime"]
	true_runtime.call("open_event", _room("event_sleeping_guardian"), {})
	true_runtime.call("choose_option", &"commit", _global_revision)
	var true_state := _event_state_snapshot(true_runtime.call("snapshot"))
	var true_continuation_id := str(true_state["pending_encounter"]["continuation_id"])
	suite.assert_true(bool(true_runtime.call(
		"complete_encounter", true_continuation_id, true, {}, _global_revision
	).get("ok", false)), "successful encounter continuation completes")
	var true_payload := _fact_payload("event_encounter_completed:")
	suite.assert_equal(true_payload.get("success"), true, "successful encounter fact preserves true")
	var true_saved: Dictionary = true_runtime.call("snapshot")
	var true_assignment := _event_state_snapshot(true_saved)["selected_event_by_node"]["floor_01_ruins:event_node"] as Dictionary
	var true_transaction_id := str(true_assignment["transaction_id"])
	var restored_fixture := _fixture([_encounter_event()], CountingSelector.new())
	var restored: RefCounted = restored_fixture["runtime"]
	suite.assert_true(bool(restored.call("restore_snapshot", true_saved)), "encounter success snapshot restores with same secret")
	var forged_success := true_saved.duplicate(true)
	(forged_success["encounter_success_by_transaction"] as Dictionary)[true_transaction_id] = false
	suite.assert_true(not bool(restored.call("restore_snapshot", forged_success)), "encounter success mutation rejects")

	var false_fixture := _fixture([_encounter_event()], CountingSelector.new())
	var false_runtime: RefCounted = false_fixture["runtime"]
	false_runtime.call("open_event", _room("event_sleeping_guardian"), {})
	false_runtime.call("choose_option", &"commit", _global_revision)
	var false_state := _event_state_snapshot(false_runtime.call("snapshot"))
	var false_continuation_id := str(false_state["pending_encounter"]["continuation_id"])
	suite.assert_true(bool(false_runtime.call(
		"complete_encounter", false_continuation_id, false, {}, _global_revision
	).get("ok", false)), "failed encounter continuation completes")
	var false_payload := _fact_payload("event_encounter_completed:")
	suite.assert_equal(false_payload.get("success"), false, "failed encounter fact preserves false")


func _fixture(
	definitions: Array,
	selector: RefCounted,
	gold: int = 100,
	run_seed: int = 42,
	floor_index: int = 0,
	publication_secret: String = PUBLICATION_SECRET
) -> Dictionary:
	_global_revision = 10
	_state_writes.clear()
	_facts.clear()
	_fact_attempts.clear()
	_external_fact_ids.clear()
	_fail_next_fact_count = 0
	_fail_state_operation = ""
	_fail_state_count = 0
	_reenter_runtime = null
	_reenter_once = false
	_reentry_results.clear()
	_reentry_configure_args.clear()
	_reentry_configure_result = true
	_reentry_restore_result = true
	_provided_context = {
		"global_revision": _global_revision,
		"selection": {
			"run_seed": run_seed,
			"availability": "LAUNCH",
			"floor_id": "floor_01_ruins",
			"floor_index": floor_index,
			"node_id": "event_node",
			"primary_event_id": str((definitions[0] as Dictionary)["id"]),
			"health": {"current": 80.0, "maximum": 100.0},
			"economy": {"gold": gold},
			"build": {"curse_ids": []},
			"resources": {"gold": gold, "time_shard": 2, "forge_essence": 1},
			"flags": {},
			"meta": {"perfect_rewind_available": false, "old_reunion_eligible": false},
			"seen_run_event_ids": [],
			"seen_floor_event_keys": [],
		},
		"requirements": {
			"resources": {"gold": gold, "time_shard": 2, "forge_essence": 1},
			"health": {"current": 80.0, "maximum": 100.0},
			"gold": gold,
			"reward_tags": [],
			"curse_ids": [],
			"narrative_flags": {},
			"floor_index": floor_index,
		},
	}
	var resource = EventResourceAuthorityScript.new()
	resource.configure({"time_shard": 2, "forge_essence": 1})
	var health = EventHealthAuthorityScript.new()
	health.configure(80.0, 100.0)
	var modifier = EventModifierAuthorityScript.new()
	modifier.configure([], {}, [])
	var economy = RunEconomyStateScript.new()
	economy.configure(_load_economy_profile(), gold)
	var route = EventRouteAuthorityScript.new()
	route.configure(_route_plan(floor_index))
	var event_state = DungeonEventRunStateScript.new()
	event_state.configure(CONTENT_FINGERPRINT)
	var consequence = ConsequenceRuntimeScript.new()
	consequence.configure(resource, health, economy, modifier, route, event_state)
	var runtime = DungeonEventRuntimeScript.new()
	var requirement_service = EventRequirementServiceScript.new()
	var configure_args: Array = [
		definitions,
		selector,
		event_state,
		requirement_service,
		consequence,
		Callable(self, "_provide_context"),
		Callable(self, "_commit_state"),
		Callable(self, "_publish_fact"),
		publication_secret,
	]
	var configured: bool = bool(runtime.callv("configure", configure_args))
	return {
		"runtime": runtime,
		"configured": configured,
		"event_state": event_state,
		"consequence": consequence,
		"configure_args": configure_args,
	}


func _provide_context() -> Dictionary:
	_provided_context["global_revision"] = _global_revision
	return _provided_context.duplicate(true)


func _load_economy_profile() -> Dictionary:
	var file := FileAccess.open(ECONOMY_PROFILE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array or (parsed as Array).is_empty() or not (parsed as Array)[0] is Dictionary:
		return {}
	return ((parsed as Array)[0] as Dictionary).duplicate(true)


func _commit_state(command: Dictionary, expected_revision: int) -> Dictionary:
	if expected_revision != _global_revision:
		return {"ok": false, "code": &"STALE_REVISION", "new_revision": _global_revision, "context": {}}
	if _fail_state_count > 0 and str(command.get("operation", "")) == _fail_state_operation:
		_fail_state_count -= 1
		return {"ok": false, "code": &"INJECTED_STATE_SINK_FAILURE", "new_revision": _global_revision, "context": {}}
	_state_writes.append(command.duplicate(true))
	_global_revision += 1
	_provided_context["global_revision"] = _global_revision
	return {"ok": true, "code": &"OK", "new_revision": _global_revision, "context": {}}


func _publish_fact(fact_id: String, payload: Dictionary) -> bool:
	_fact_attempts.append(fact_id)
	if _reenter_once and _reenter_runtime != null:
		_reenter_once = false
		_reentry_results.append(_reenter_runtime.call("flush_pending_facts"))
		_reentry_results.append(_reenter_runtime.call("open_event", _room(), {}))
		var delivery_snapshot: Dictionary = _reenter_runtime.call("snapshot")
		_reentry_configure_result = bool(_reenter_runtime.callv(
			"configure", _reentry_configure_args
		))
		_reentry_restore_result = bool(_reenter_runtime.call(
			"restore_snapshot", delivery_snapshot
		))
	if _fail_next_fact_count > 0:
		_fail_next_fact_count -= 1
		return false
	if _external_fact_ids.has(fact_id):
		return true
	_external_fact_ids[fact_id] = true
	_facts.append({"fact_id": fact_id, "payload": payload.duplicate(true)})
	return true


func _room(primary_event_id: String = "event_chronal_altar", floor_index: int = 0) -> Dictionary:
	return {
		"floor_id": "floor_01_ruins",
		"floor_index": floor_index,
		"node_id": "event_node",
		"primary_event_id": primary_event_id,
	}


func _immediate_event() -> Dictionary:
	return _event_definition("event_chronal_altar", "once_per_run", [
		_option(
			"commit",
			"preview_category",
			[{"operation": "gold_min", "arguments": {"amount": 50}}],
			[{
				"id": "commit_outcome",
				"weight": 1,
				"outcome_key": "EVENT_CHRONAL_ALTAR_RESULT",
				"consequences": [{
					"operation": "temporary_modifier",
					"arguments": {"modifier_id": "chronal_grace", "duration_rooms": 2, "magnitude": 1.1},
				}],
			}]
		),
		_option(
			"decline",
			"preview_exact",
			[{"operation": "floor_index_min", "arguments": {"value": 1}}],
			[{
				"id": "decline_outcome",
				"weight": 1,
				"outcome_key": "EVENT_CHRONAL_ALTAR_DECLINE_RESULT",
				"consequences": [{"operation": "narrative_flag", "arguments": {"flag": "declined", "value": true}}],
			}]
		),
	])


func _floor_gate_event() -> Dictionary:
	var definition := _immediate_event()
	var options := definition["options"] as Array
	var commit := (options[0] as Dictionary).duplicate(true)
	commit["requirements"] = [{
		"operation": "floor_index_min",
		"arguments": {"value": 2},
	}]
	options[0] = commit
	return definition


func _reward_event() -> Dictionary:
	return _event_definition("event_trapped_traveler", "once_per_run", [
		_option(
			"commit",
			"preview_category",
			[{"operation": "floor_index_min", "arguments": {"value": 1}}],
			[{
				"id": "reward_outcome",
				"weight": 1,
				"outcome_key": "EVENT_TRAPPED_TRAVELER_RESULT",
				"consequences": [{"operation": "reward_draft", "arguments": {"pool_id": "item", "count": 2}}],
			}]
		),
		_decline_option("EVENT_TRAPPED_TRAVELER_DECLINE_RESULT"),
	])


func _encounter_event() -> Dictionary:
	return _event_definition("event_sleeping_guardian", "once_per_floor", [
		_option(
			"commit",
			"preview_category",
			[{"operation": "floor_index_min", "arguments": {"value": 1}}],
			[{
				"id": "encounter_outcome",
				"weight": 1,
				"outcome_key": "EVENT_SLEEPING_GUARDIAN_RESULT",
				"consequences": [{
					"operation": "encounter_start",
					"arguments": {"encounter_id": "encounter_profile_ruins_adapter_v1"},
				}],
			}]
		),
		_decline_option("EVENT_SLEEPING_GUARDIAN_DECLINE_RESULT"),
	])


func _hidden_event() -> Dictionary:
	return _event_definition("event_void_whispers", "once_per_run", [
		_option(
			"commit",
			"hidden_until_commit",
			[{"operation": "floor_index_min", "arguments": {"value": 2}}],
			[
				{
					"id": "power_bargain",
					"weight": 1,
					"outcome_key": "EVENT_VOID_WHISPERS_RESULT",
					"consequences": [{
						"operation": "temporary_modifier",
						"arguments": {"modifier_id": "void_bargain_power", "duration_rooms": 2, "magnitude": 1.2},
					}],
				},
				{
					"id": "guard_bargain",
					"weight": 1,
					"outcome_key": "EVENT_VOID_WHISPERS_RESULT",
					"consequences": [{
						"operation": "temporary_modifier",
						"arguments": {"modifier_id": "void_bargain_guard", "duration_rooms": 2, "magnitude": 1.2},
					}],
				},
			]
		),
		_decline_option("EVENT_VOID_WHISPERS_DECLINE_RESULT"),
	], true, 2)


func _event_definition(
	id: String,
	repeat_policy: String,
	options: Array,
	special: bool = false,
	floor_min: int = 1
) -> Dictionary:
	return {
		"category": "dungeon_event",
		"id": id,
		"schema_version": 1,
		"name_key": "%s_NAME" % id.to_upper(),
		"description_key": "%s_DESC" % id.to_upper(),
		"prompt_key": "%s_PROMPT" % id.to_upper(),
		"availability": ["LAUNCH", "EXPANSION"],
		"special": special,
		"floor_min": floor_min,
		"floor_max": 5,
		"weight": 10,
		"repeat_policy": repeat_policy,
		"trigger_predicate_id": "always",
		"outcome_channel": "event_outcome_v1",
		"options": options,
	}


func _option(id: String, visibility: String, requirements: Array, outcomes: Array) -> Dictionary:
	return {
		"id": id,
		"label_key": "EVENT_OPTION_%s" % id.to_upper(),
		"outcome_visibility": visibility,
		"requirements": requirements,
		"outcomes": outcomes,
	}


func _decline_option(result_key: String) -> Dictionary:
	return _option(
		"decline",
		"preview_exact",
		[{"operation": "floor_index_min", "arguments": {"value": 1}}],
		[{
			"id": "decline_outcome",
			"weight": 1,
			"outcome_key": result_key,
			"consequences": [{"operation": "narrative_flag", "arguments": {"flag": "declined", "value": true}}],
		}]
	)


func _route_plan(floor_index: int) -> Dictionary:
	var plan := {
		"schema_version": 1,
		"generator_version": "floor_plan_v1",
		"run_seed": 42,
		"floor_id": "floor_01_ruins",
		"floor_index": floor_index,
		"entry_node_id": "entry",
		"boss_node_id": "boss",
		"current_node_id": "event_node",
		"nodes": [
			_node_data("entry", 0, "entry", true, true, true),
			_node_data("event_node", 1, "event", true, true, true),
			_node_data("combat", 2, "combat", false, false, false),
			_node_data("boss", 3, "boss", false, false, false),
		],
		"edges": [
			_edge("edge_entry_event", "entry", "event_node", 0),
			_edge("edge_event_combat", "event_node", "combat", 0),
			_edge("edge_combat_boss", "combat", "boss", 0),
		],
		"selected_edge_ids": ["edge_entry_event"],
		"visited_node_ids": ["entry", "event_node"],
		"abandoned_node_ids": [],
		"generation_digest": "",
		"revision": 1,
	}
	plan["generation_digest"] = FloorPlanScript.compute_generation_digest(plan)
	return plan


func _node_data(id: String, layer: int, room_type: String, revealed: bool, visited: bool, cleared: bool) -> Dictionary:
	return {
		"id": id,
		"layer": layer,
		"room_type": room_type,
		"template_id": "template_%s" % id,
		"encounter_id": "",
		"event_id": "event_chronal_altar" if room_type == "event" else "",
		"merchant_id": "",
		"reward_policy_id": "reward_policy_test",
		"seed_channel_suffix": id,
		"revealed": revealed,
		"visited": visited,
		"cleared": cleared,
	}


func _edge(id: String, source: String, destination: String, order: int) -> Dictionary:
	return {
		"id": id,
		"source_node_id": source,
		"destination_node_id": destination,
		"choice_order": order,
		"locked": false,
		"route_summary_facts": {"room_type": "combat", "template_id": "template_test"},
	}


func _event_state_snapshot(runtime_snapshot: Dictionary) -> Dictionary:
	return (
		(runtime_snapshot["consequence_runtime"] as Dictionary)["participant_snapshots"]
		as Dictionary
	)["event_state"] as Dictionary


func _option_view(view: Dictionary, option_id: String) -> Dictionary:
	for value: Variant in view.get("options", []):
		if value is Dictionary and str((value as Dictionary).get("id", "")) == option_id:
			return value as Dictionary
	return {}


func _assert_view_is_safe(suite, view: Dictionary, label: String) -> void:
	suite.assert_equal(_sorted_keys(view), VIEW_FIELDS, "%s root fields are exact" % label)
	for value: Variant in view.get("options", []):
		suite.assert_true(value is Dictionary, "%s option is a dictionary" % label)
		if value is Dictionary:
			suite.assert_equal(
				_sorted_keys(value as Dictionary),
				OPTION_VIEW_FIELDS,
				"%s option fields are exact" % label
			)
	var serialized := JSON.stringify(view)
	for forbidden: String in [
		"transaction_id", "continuation_id", "outcome_id", "outcome_key", "consequences",
		"requirements", "operation", "arguments", "ticket", "receipt", "weight", "roll", "channel",
	]:
		suite.assert_true(not serialized.contains(forbidden), "%s hides %s" % [label, forbidden])


func _assert_no_secret_values(suite, value: Dictionary, secrets: Array[String], label: String) -> void:
	var serialized := JSON.stringify(value)
	for secret: String in secrets:
			suite.assert_true(not serialized.contains(secret), "%s hides %s" % [label, secret])


func _assert_publication_pending(suite, result: Dictionary, label: String) -> void:
	suite.assert_true(not bool(result.get("ok", true)), "%s reports a retryable failure" % label)
	suite.assert_equal(result.get("committed"), true, "%s retains committed domain state" % label)
	suite.assert_equal(result.get("pending_publication"), true, "%s reports durable pending publication" % label)


func _assert_state_candidate_has_outbox(
	suite,
	command: Dictionary,
	pending_count: int,
	emitted_count: int,
	label: String
) -> void:
	suite.assert_equal(
		_sorted_keys(command),
		["event_state", "operation", "payload", "publication_state"],
		"%s fields are exact" % label
	)
	var publication := command.get("publication_state", {}) as Dictionary
	suite.assert_equal(
		_sorted_keys(publication),
		[
			"emitted_fact_ids", "encounter_success_by_transaction", "pending_facts",
			"publication_digest", "publication_ledger",
		],
		"%s publication fields are exact" % label
	)
	suite.assert_equal((publication.get("pending_facts", []) as Array).size(), pending_count, "%s pending count" % label)
	suite.assert_equal((publication.get("emitted_fact_ids", []) as Array).size(), emitted_count, "%s emitted count" % label)
	suite.assert_true(command.get("event_state") is Dictionary, "%s includes event state" % label)


func _fact_effect_count(prefix: String) -> int:
	var count := 0
	for fact: Dictionary in _facts:
		if str(fact["fact_id"]).begins_with(prefix):
			count += 1
	return count


func _fact_payload(prefix: String) -> Dictionary:
	for fact: Dictionary in _facts:
		if str(fact["fact_id"]).begins_with(prefix):
			return (fact["payload"] as Dictionary).duplicate(true)
	return {}


func _fact_attempt_count(prefix: String) -> int:
	var count := 0
	for fact_id: String in _fact_attempts:
		if fact_id.begins_with(prefix):
			count += 1
	return count


func _ledger_entry_index(snapshot_value: Dictionary, fact_prefix: String) -> int:
	var ledger: Array = snapshot_value.get("publication_ledger", [])
	for index: int in range(ledger.size()):
		var entry: Variant = ledger[index]
		if entry is Dictionary and str((entry as Dictionary).get("fact_id", "")).begins_with(fact_prefix):
			return index
	return -1


func _sorted_keys(value: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key_value: Variant in value.keys():
		keys.append(str(key_value))
	keys.sort()
	return keys


func _seed_for_roll(channel: String, total_weight: int, desired_roll: int) -> int:
	for seed: int in range(1, 10000):
		if posmod(SeedServiceScript.derive_seed(seed, StringName(channel), 1, 0, 0), total_weight) == desired_roll:
			return seed
	return 1


func _unique_fact_ids() -> Dictionary:
	var ids: Dictionary = {}
	for fact: Dictionary in _facts:
		ids[str(fact["fact_id"])] = true
	return ids
