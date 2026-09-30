extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TimeRiftScene := preload("res://scenes/time/time_rift.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite
var _frame_signal_events: Array[String] = []
var _publication_observer_manager: Node
var _publication_observer_begin_results: Array[bool] = []
var _publication_observer_discard_publication: Dictionary = {}
var _publication_observer_discard_results: Array[bool] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_process_is_gameplay_pure()
	await _test_prepare_rejects_wrong_run_and_frame_atomically()
	await _test_sixty_frames_are_exactly_one_gameplay_second()
	await _test_stop_and_accelerate_expire_on_exact_frames()
	await _test_all_four_cooldowns_expire_on_exact_frames()
	await _test_frame_signal_transaction_is_atomic_and_exactly_once()
	await _test_frame_signal_publication_is_two_phase_and_observer_atomic()
	await _test_finalized_frame_signal_publication_discard_is_authenticated_and_exactly_once()
	await _test_finalized_frame_signal_publication_discard_rejects_publish_reentry()
	await _test_fractional_fixed_point_regen_is_exact_and_restorable()
	await _test_rewind_window_expires_on_exact_frame()
	await _test_rewind_samples_every_six_frames()
	await _test_live_and_replay_frames_produce_identical_time_state()
	await _test_time_rift_frame_snapshot_is_atomic()
	await _test_real_rift_uses_world_payload_authority_semantics()
	_suite.finish(get_tree())


func _test_process_is_gameplay_pure() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 60.0
	_suite.assert_true(manager.has_method("replay_snapshot"), "TimeManager exposes its complete deterministic replay snapshot")
	var before: Dictionary = manager.call("replay_snapshot") if manager.has_method("replay_snapshot") else {}
	manager.call("_process", 10.0)
	var after: Dictionary = manager.call("replay_snapshot") if manager.has_method("replay_snapshot") else {"missing": true}
	_suite.assert_equal(after, before, "presentation _process cannot mutate authoritative time gameplay state")
	await _free_player(player)


func _test_prepare_rejects_wrong_run_and_frame_atomically() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	var before: Dictionary = manager.time_action_snapshot()
	var wrong_run: Dictionary = manager.prepare_time_action(
		901,
		7,
		0,
		&"wrong-run",
		&"stop",
		{}
	)
	_suite.assert_true(wrong_run.is_empty(), "TimeAction prepare rejects the wrong run identity")
	_suite.assert_equal(
		manager.time_action_snapshot(),
		before,
		"wrong-run prepare rejection preserves every TimeAction participant exactly"
	)

	var wrong_frame: Dictionary = manager.prepare_time_action(
		902,
		7,
		1,
		player.current_run_id(),
		&"stop",
		{}
	)
	_suite.assert_true(wrong_frame.is_empty(), "TimeAction prepare rejects a non-current frame")
	_suite.assert_equal(
		manager.time_action_snapshot(),
		before,
		"wrong-frame prepare rejection preserves every TimeAction participant exactly"
	)
	await _free_player(player)


func _test_sixty_frames_are_exactly_one_gameplay_second() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 60.0
	manager.time_stop_cost = 100.0
	manager.time_stop_duration = 0.0
	manager.time_stop_cooldown = 1.0
	_suite.assert_true(manager.try_time_stop(), "fixed-frame fixture spends energy and starts a one-second cooldown")
	_suite.assert_close(manager.energy, 0.0, "fixture begins with empty energy")
	_advance(player, 59)
	_suite.assert_close(manager.energy, 59.0, "59 authoritative frames regenerate exactly 59 energy")
	_suite.assert_true(manager.get_cooldown(&"time_stop") > 0.0, "one-second cooldown remains active through frame 59")
	_advance(player, 1)
	_suite.assert_close(manager.energy, 60.0, "60 authoritative frames regenerate exactly one second of energy")
	_suite.assert_close(manager.get_cooldown(&"time_stop"), 0.0, "one-second cooldown expires exactly on frame 60")
	await _free_player(player)


func _test_stop_and_accelerate_expire_on_exact_frames() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 0.0
	manager.time_stop_cost = 0.0
	manager.time_stop_cooldown = 0.0
	manager.time_stop_duration = 3.0
	_suite.assert_true(manager.try_time_stop(), "default three-second Stop commits")
	_advance(player, 179)
	_suite.assert_true(bool(manager.weapon_interaction_context().get("stop_active", false)), "Stop remains active through frame 179")
	_advance(player, 1)
	_suite.assert_true(not bool(manager.weapon_interaction_context().get("stop_active", true)), "Stop expires exactly on frame 180")
	_advance(player, 1)
	_suite.assert_true(not bool(manager.weapon_interaction_context().get("stop_active", true)), "Stop stays expired after frame 180")

	player.reset_runtime_state()
	manager.time_accelerate_cost = 0.0
	manager.time_accelerate_cooldown = 0.0
	manager.time_accelerate_duration = 3.0
	_suite.assert_true(manager.try_time_accelerate(), "default three-second Accelerate commits")
	_advance(player, 179)
	_suite.assert_true(bool(manager.weapon_interaction_context().get("accelerate_active", false)), "Accelerate remains active through frame 179")
	_advance(player, 1)
	_suite.assert_true(not bool(manager.weapon_interaction_context().get("accelerate_active", true)), "Accelerate expires exactly on frame 180")
	_advance(player, 1)
	_suite.assert_true(not bool(manager.weapon_interaction_context().get("accelerate_active", true)), "Accelerate stays expired after frame 180")
	await _free_player(player)


func _test_all_four_cooldowns_expire_on_exact_frames() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 0.0
	manager.set("_cooldown_frames", {
		&"time_stop": 120,
		&"time_rewind": 120,
		&"time_rift": 120,
		&"time_accelerate": 120,
	})
	manager.set("_cooldowns", {
		&"time_stop": 999.0,
		&"time_rewind": 999.0,
		&"time_rift": 999.0,
		&"time_accelerate": 999.0,
	})
	_suite.assert_close(
		manager.get_cooldown(&"time_stop"),
		2.0,
		"derived cooldown seconds cannot overwrite authoritative integer frames"
	)
	_suite.assert_equal(
		manager.get("_cooldown_frames"),
		{
			&"time_stop": 120,
			&"time_rewind": 120,
			&"time_rift": 120,
			&"time_accelerate": 120,
		},
		"reading cooldown projection preserves authoritative frame counts"
	)
	_suite.assert_equal(
		(manager.replay_snapshot().get("cooldowns", {}) as Dictionary).get(&"time_stop"),
		2.0,
		"replay snapshots repair a corrupted compatibility projection from frames"
	)
	_advance(player, 119)
	for skill_id: StringName in [&"time_stop", &"time_rewind", &"time_rift", &"time_accelerate"]:
		_suite.assert_close(
			manager.get_cooldown(skill_id),
			1.0 / 60.0,
			"%s cooldown has exactly one frame remaining at frame 119" % skill_id,
			0.000001
		)
	_advance(player, 1)
	for skill_id: StringName in [&"time_stop", &"time_rewind", &"time_rift", &"time_accelerate"]:
		_suite.assert_close(manager.get_cooldown(skill_id), 0.0, "%s cooldown expires exactly on frame 120" % skill_id)
	_advance(player, 1)
	for skill_id: StringName in [&"time_stop", &"time_rewind", &"time_rift", &"time_accelerate"]:
		_suite.assert_close(manager.get_cooldown(skill_id), 0.0, "%s cooldown stays expired after frame 120" % skill_id)
	await _free_player(player)


func _test_frame_signal_transaction_is_atomic_and_exactly_once() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 60.0
	manager.time_stop_cost = 1.0
	manager.time_stop_cooldown = 1.0 / 60.0
	manager.time_stop_duration = 1.0 / 60.0
	_suite.assert_true(manager.try_time_stop(), "signal transaction fixture starts one-frame Stop")
	manager.energy_changed.connect(_on_frame_energy_changed)
	manager.cooldown_changed.connect(_on_frame_cooldown_changed)
	EventBus.time_skill_ended.connect(_on_frame_time_skill_ended)
	_frame_signal_events.clear()

	var ticket: Dictionary = manager.begin_frame_signal_transaction(1)
	_suite.assert_true(not ticket.is_empty(), "frame signal transaction begins for the next authoritative frame")
	_suite.assert_true(manager.advance_frame(1), "buffered authoritative frame advances")
	_suite.assert_true(_frame_signal_events.is_empty(), "frame observers see no partial events before commit")
	var forged := ticket.duplicate(true)
	forged["runtime_frame"] = 2
	_suite.assert_true(not manager.commit_frame_signal_transaction(forged), "forged frame signal ticket is rejected")
	_suite.assert_true(manager.commit_frame_signal_transaction(ticket), "authentic frame signal transaction commits")
	_suite.assert_equal(
		_frame_signal_events,
		["energy", "cooldown:time_stop", "ended:time_stop"],
		"frame commit flushes energy, cooldown, and Stop-ended events in mutation order"
	)
	_suite.assert_true(not manager.commit_frame_signal_transaction(ticket), "duplicate frame signal commit is rejected")

	_suite.assert_true(manager.try_time_stop(), "rollback fixture starts another one-frame Stop")
	_frame_signal_events.clear()
	var rollback_ticket: Dictionary = manager.begin_frame_signal_transaction(2)
	_suite.assert_true(not rollback_ticket.is_empty(), "second frame signal transaction begins")
	_suite.assert_true(manager.advance_frame(2), "rollback fixture advances its buffered frame")
	_suite.assert_true(_frame_signal_events.is_empty(), "rollback fixture remains invisible before settlement")
	_suite.assert_true(manager.rollback_frame_signal_transaction(rollback_ticket), "frame signal rollback discards buffered events")
	_suite.assert_true(_frame_signal_events.is_empty(), "rolled-back frame events never reach observers")
	_suite.assert_true(not manager.rollback_frame_signal_transaction(rollback_ticket), "duplicate frame signal rollback is rejected")

	manager.energy_changed.disconnect(_on_frame_energy_changed)
	manager.cooldown_changed.disconnect(_on_frame_cooldown_changed)
	EventBus.time_skill_ended.disconnect(_on_frame_time_skill_ended)
	await _free_player(player)


func _test_frame_signal_publication_is_two_phase_and_observer_atomic() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 60.0
	manager.time_stop_cost = 1.0
	manager.time_stop_cooldown = 1.0 / 60.0
	manager.time_stop_duration = 1.0 / 60.0
	_suite.assert_true(manager.try_time_stop(), "two-phase signal fixture starts one-frame Stop")
	manager.energy_changed.connect(_on_frame_energy_changed)
	manager.cooldown_changed.connect(_on_frame_cooldown_changed)
	EventBus.time_skill_ended.connect(_on_frame_time_skill_ended)
	_frame_signal_events.clear()

	var transaction_ticket: Dictionary = manager.begin_frame_signal_transaction(1)
	_suite.assert_true(not transaction_ticket.is_empty(), "two-phase signal transaction begins")
	_suite.assert_true(manager.advance_frame(1), "two-phase signal fixture advances one authoritative frame")
	var publication: Dictionary = manager.prepare_frame_signal_publication(transaction_ticket)
	_suite.assert_true(not publication.is_empty(), "signal prepare returns an authenticated publication ticket")
	_suite.assert_equal(
		(publication.get("events", []) as Array).size(),
		3,
		"signal publication freezes every buffered event without emitting"
	)
	_suite.assert_equal(_frame_signal_events, [], "signal prepare remains externally silent")

	var isolated_copy := publication.duplicate(true)
	(isolated_copy["events"] as Array).clear()
	_suite.assert_equal(
		(manager.prepare_frame_signal_publication(transaction_ticket).get("events", []) as Array).size(),
		3,
		"caller mutation cannot alter the authoritative signal publication"
	)
	var forged := publication.duplicate(true)
	forged["fingerprint"] = "forged"
	_suite.assert_true(
		not manager.finalize_frame_signal_publication(forged),
		"signal finalize rejects a forged publication without consuming the transaction"
	)
	_suite.assert_true(
		manager.can_commit_frame_signal_transaction(transaction_ticket),
		"forged signal finalize preserves the live transaction"
	)
	_suite.assert_true(
		manager.finalize_frame_signal_publication(publication),
		"authentic signal finalize consumes the internal transaction without publishing"
	)
	_suite.assert_equal(_frame_signal_events, [], "signal finalize remains externally silent")
	_suite.assert_true(
		manager.begin_frame_signal_transaction(2).is_empty(),
		"a finalized unpublished signal batch blocks a replacement transaction"
	)
	_suite.assert_true(
		not manager.rollback_frame_signal_transaction(transaction_ticket),
		"finalized signal publication cannot be discarded through rollback"
	)

	_publication_observer_manager = manager
	_publication_observer_begin_results.clear()
	manager.energy_changed.connect(_on_time_publication_observer)
	manager.publish_prepared_frame_signals()
	manager.energy_changed.disconnect(_on_time_publication_observer)
	_publication_observer_manager = null
	_suite.assert_equal(
		_publication_observer_begin_results,
		[false],
		"signal observer re-entry cannot replace the batch during publication"
	)
	_suite.assert_equal(
		_frame_signal_events,
		["energy", "cooldown:time_stop", "ended:time_stop"],
		"prepared signals publish once in original mutation order"
	)
	manager.publish_prepared_frame_signals()
	_suite.assert_equal(_frame_signal_events.size(), 3, "duplicate signal publish is a no-op")
	var next_ticket: Dictionary = manager.begin_frame_signal_transaction(2)
	_suite.assert_true(not next_ticket.is_empty(), "a new signal transaction may begin after publication")
	_suite.assert_true(manager.rollback_frame_signal_transaction(next_ticket), "post-publication signal transaction remains reversible")

	manager.energy_changed.disconnect(_on_frame_energy_changed)
	manager.cooldown_changed.disconnect(_on_frame_cooldown_changed)
	EventBus.time_skill_ended.disconnect(_on_frame_time_skill_ended)
	await _free_player(player)


func _test_finalized_frame_signal_publication_discard_is_authenticated_and_exactly_once() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 60.0
	manager.time_stop_cost = 1.0
	manager.time_stop_cooldown = 1.0 / 60.0
	manager.time_stop_duration = 1.0 / 60.0
	_suite.assert_true(manager.try_time_stop(), "signal discard fixture starts one-frame Stop")
	manager.energy_changed.connect(_on_frame_energy_changed)
	manager.cooldown_changed.connect(_on_frame_cooldown_changed)
	EventBus.time_skill_ended.connect(_on_frame_time_skill_ended)
	_frame_signal_events.clear()

	var transaction_ticket: Dictionary = manager.begin_frame_signal_transaction(1)
	_suite.assert_true(manager.advance_frame(1), "signal discard fixture advances one frame")
	var publication: Dictionary = manager.prepare_frame_signal_publication(transaction_ticket)
	_suite.assert_true(
		manager.finalize_frame_signal_publication(publication),
		"signal discard fixture finalizes an observer-invisible publication"
	)

	var forged := publication.duplicate(true)
	var forged_ticket := forged["transaction_ticket"] as Dictionary
	forged_ticket["fingerprint"] = "forged"
	forged["transaction_ticket"] = forged_ticket
	var unsigned_forged := forged.duplicate(true)
	unsigned_forged.erase("fingerprint")
	forged["fingerprint"] = var_to_bytes(unsigned_forged).hex_encode().sha256_text()
	_suite.assert_true(
		not manager.discard_finalized_frame_signal_publication(forged),
		"forged nested transaction ticket cannot authenticate a signal discard"
	)
	_suite.assert_true(
		manager.begin_frame_signal_transaction(2).is_empty(),
		"forged signal discard preserves the authoritative finalized batch"
	)
	manager.call(
		"_publish_time_skill_ended",
		&"survives_discard",
		{}
	)
	_suite.assert_true(
		manager.discard_finalized_frame_signal_publication(publication),
		"authentic finalized signal publication is discarded before observers see it"
	)
	_suite.assert_equal(_frame_signal_events, [], "signal discard remains completely observer-silent")
	_suite.assert_true(
		not manager.discard_finalized_frame_signal_publication(publication),
		"finalized signal publication discard is exactly once"
	)
	var replacement_ticket: Dictionary = manager.begin_frame_signal_transaction(2)
	_suite.assert_true(not replacement_ticket.is_empty(), "successful signal discard releases the next frame transaction")
	_suite.assert_true(
		manager.advance_frame(2),
		"replacement signal transaction advances after discard"
	)
	var replacement_publication: Dictionary = manager.prepare_frame_signal_publication(
		replacement_ticket
	)
	_suite.assert_true(
		manager.finalize_frame_signal_publication(replacement_publication),
		"replacement signal transaction finalizes after discard"
	)
	manager.publish_prepared_frame_signals()
	_suite.assert_equal(
		_frame_signal_events,
		["ended:survives_discard"],
		"successful signal discard preserves the independent post-publication event queue"
	)

	manager.energy_changed.disconnect(_on_frame_energy_changed)
	manager.cooldown_changed.disconnect(_on_frame_cooldown_changed)
	EventBus.time_skill_ended.disconnect(_on_frame_time_skill_ended)
	await _free_player(player)


func _test_finalized_frame_signal_publication_discard_rejects_publish_reentry() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy_regen = 60.0
	manager.time_stop_cost = 1.0
	manager.time_stop_cooldown = 1.0 / 60.0
	manager.time_stop_duration = 1.0 / 60.0
	_suite.assert_true(manager.try_time_stop(), "signal reentrant discard fixture starts one-frame Stop")
	manager.energy_changed.connect(_on_frame_energy_changed)
	manager.cooldown_changed.connect(_on_frame_cooldown_changed)
	EventBus.time_skill_ended.connect(_on_frame_time_skill_ended)
	_frame_signal_events.clear()

	var transaction_ticket: Dictionary = manager.begin_frame_signal_transaction(1)
	_suite.assert_true(manager.advance_frame(1), "signal reentrant discard fixture advances one frame")
	var publication: Dictionary = manager.prepare_frame_signal_publication(transaction_ticket)
	_suite.assert_true(
		manager.finalize_frame_signal_publication(publication),
		"signal reentrant discard fixture finalizes one publication"
	)

	_publication_observer_manager = manager
	_publication_observer_discard_publication = publication.duplicate(true)
	_publication_observer_discard_results.clear()
	manager.energy_changed.connect(_on_time_publication_discard_observer)
	manager.publish_prepared_frame_signals()
	manager.energy_changed.disconnect(_on_time_publication_discard_observer)
	_publication_observer_manager = null
	_publication_observer_discard_publication.clear()
	_suite.assert_equal(
		_publication_observer_discard_results,
		[false],
		"signal observer re-entry cannot discard a publication already in progress"
	)
	_suite.assert_equal(
		_frame_signal_events,
		[
			"energy",
			"cooldown:time_stop",
			"ended:time_stop",
			"ended:observer_deferred",
		],
		"reentrant signal discard cannot remove the observer-seen batch or post-publication queue"
	)
	_suite.assert_true(
		not manager.discard_finalized_frame_signal_publication(publication),
		"an already published signal batch cannot be discarded afterward"
	)

	manager.energy_changed.disconnect(_on_frame_energy_changed)
	manager.cooldown_changed.disconnect(_on_frame_cooldown_changed)
	EventBus.time_skill_ended.disconnect(_on_frame_time_skill_ended)
	await _free_player(player)


func _on_frame_energy_changed(_current: float, _maximum: float) -> void:
	_frame_signal_events.append("energy")


func _on_frame_cooldown_changed(skill_id: StringName, _remaining: float) -> void:
	_frame_signal_events.append("cooldown:%s" % skill_id)


func _on_frame_time_skill_ended(skill_id: StringName, _context: Dictionary) -> void:
	_frame_signal_events.append("ended:%s" % skill_id)


func _on_time_publication_observer(_current: float, _maximum: float) -> void:
	_publication_observer_begin_results.append(
		_publication_observer_manager != null
		and not (
			_publication_observer_manager.call("begin_frame_signal_transaction", 2) as Dictionary
		).is_empty()
	)


func _on_time_publication_discard_observer(_current: float, _maximum: float) -> void:
	if _publication_observer_manager == null:
		return
	_publication_observer_manager.call(
		"_publish_time_skill_ended",
		&"observer_deferred",
		{}
	)
	_publication_observer_discard_results.append(bool(
		_publication_observer_manager.call(
			"discard_finalized_frame_signal_publication",
			_publication_observer_discard_publication.duplicate(true)
		)
	))


func _test_fractional_fixed_point_regen_is_exact_and_restorable() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	manager.energy = 0.0
	manager.energy_regen = 7.25
	for runtime_frame: int in range(1, 60):
		_suite.assert_true(manager.advance_frame(runtime_frame), "fractional regen accepts frame %d" % runtime_frame)
	_suite.assert_close(manager.energy, 7.129166, "59 frames grant the exact fixed-point 7.25/s prefix", 0.000001)
	_suite.assert_equal(int(manager.get("_energy_regen_remainder")), 40, "59-frame fractional regen preserves its exact numerator remainder")
	var frame_59_snapshot: Dictionary = manager.replay_snapshot()
	_suite.assert_true(manager.advance_frame(60), "fractional regen accepts frame 60")
	_suite.assert_close(manager.energy, 7.25, "60 frames grant exactly 7.25 energy", 0.000001)
	_suite.assert_equal(int(manager.get("_energy_regen_remainder")), 0, "one exact second consumes the fractional remainder")
	_suite.assert_true(manager.restore_replay_snapshot(frame_59_snapshot), "fractional regen snapshot restores")
	_suite.assert_equal(manager.replay_snapshot(), frame_59_snapshot, "fractional regen restore returns the exact energy and remainder state")

	manager.reset_runtime_state(true)
	manager.energy = 29.9
	manager.energy_regen = 7.25
	manager.low_energy_threshold = 30.0
	manager.low_energy_regen_multiplier = 2.0
	_suite.assert_true(manager.advance_frame(1), "low-energy threshold fixture accepts its first frame")
	_suite.assert_close(manager.energy, 30.141666, "the crossing frame uses the low-energy multiplier exactly", 0.000001)
	_suite.assert_equal(int(manager.get("_energy_regen_remainder")), 40, "threshold crossing retains the fixed-point remainder")
	_suite.assert_true(manager.advance_frame(2), "low-energy threshold fixture accepts its second frame")
	_suite.assert_close(manager.energy, 30.2625, "the frame after crossing uses the normal multiplier without losing remainder", 0.000001)
	_suite.assert_equal(int(manager.get("_energy_regen_remainder")), 0, "post-threshold frame consumes the carried remainder exactly")
	await _free_player(player)


func _test_rewind_window_expires_on_exact_frame() -> void:
	var player := await _spawn_player()
	var manager: Node = player.get_node("TimeManager")
	var recorder: Node = player.get_node("RewindRecorder")
	manager.energy_regen = 0.0
	manager.rewind_cost = 0.0
	manager.rewind_cooldown = 0.0
	_advance(player, 6)
	_suite.assert_true(manager.try_rewind(recorder), "real Gameplay Rewind opens its weapon interaction window")
	_advance(player, 119)
	_suite.assert_true(bool(manager.weapon_interaction_context().get("rewind_echo_available", false)), "Rewind window remains available through frame 119")
	_advance(player, 1)
	_suite.assert_true(not bool(manager.weapon_interaction_context().get("rewind_echo_available", true)), "Rewind window expires exactly on frame 120")
	_advance(player, 1)
	_suite.assert_true(not bool(manager.weapon_interaction_context().get("rewind_echo_available", true)), "Rewind window stays expired after frame 120")
	await get_tree().create_timer(0.55).timeout
	await _free_player(player)


func _test_rewind_samples_every_six_frames() -> void:
	var player := await _spawn_player()
	var recorder: Node = player.get_node("RewindRecorder")
	_suite.assert_true(recorder.reset_runtime_state(), "Rewind cadence fixture resets cleanly")
	_suite.assert_true(recorder.has_method("advance_frame"), "RewindRecorder exposes the authoritative frame sampler")
	for runtime_frame: int in range(1, 6):
		_suite.assert_true(recorder.advance_frame(runtime_frame), "Rewind accepts sequential frame %d" % runtime_frame)
	_suite.assert_true(not recorder.has_snapshot(), "Rewind history remains empty before the sixth authoritative frame")
	var before_rejections: Dictionary = recorder.peek_oldest_snapshot()
	_suite.assert_true(not recorder.advance_frame(5), "Rewind rejects a duplicate frame")
	_suite.assert_true(not recorder.advance_frame(7), "Rewind rejects a skipped frame")
	_suite.assert_equal(recorder.peek_oldest_snapshot(), before_rejections, "duplicate and skipped frames cannot mutate history")
	_suite.assert_equal(int(recorder.get("_last_runtime_frame")), 5, "duplicate and skipped frames cannot move the cadence cursor")
	_suite.assert_true(recorder.advance_frame(6), "Rewind accepts the sixth sequential frame")
	_suite.assert_true(recorder.has_snapshot(), "Rewind records exactly on the sixth authoritative frame")
	for runtime_frame: int in range(7, 13):
		_suite.assert_true(recorder.advance_frame(runtime_frame), "Rewind accepts sequential frame %d" % runtime_frame)
	_suite.assert_equal((recorder.get("_snapshots") as Array).size(), 2, "Rewind records again exactly on frame 12")

	_suite.assert_true(recorder.reset_runtime_state(), "Rewind reset clears the cadence phase")
	recorder.samples_per_second = 0.0
	_suite.assert_true(not recorder.advance_frame(1), "invalid sample configuration is rejected")
	_suite.assert_equal(int(recorder.get("_last_runtime_frame")), 0, "invalid sample configuration cannot move the cadence cursor")
	_suite.assert_true(not recorder.has_snapshot(), "invalid sample configuration cannot create history")
	recorder.samples_per_second = 10.0
	recorder.record_seconds = 0.0
	_suite.assert_true(not recorder.advance_frame(1), "invalid record window is rejected before cursor mutation")
	_suite.assert_equal(int(recorder.get("_last_runtime_frame")), 0, "invalid record window cannot move the cadence cursor")
	_suite.assert_true(not recorder.has_snapshot(), "invalid record window cannot create history")
	recorder.record_seconds = 5.0
	for runtime_frame: int in range(1, 6):
		_suite.assert_true(recorder.advance_frame(runtime_frame), "reset cadence accepts sequential frame %d" % runtime_frame)
	_suite.assert_true(not recorder.has_snapshot(), "reset cadence remains empty through its new frame five")
	_suite.assert_true(recorder.advance_frame(6), "reset cadence accepts its new sixth frame")
	_suite.assert_true(recorder.has_snapshot(), "reset cadence samples on its new frame six")
	await _free_player(player)


func _test_live_and_replay_frames_produce_identical_time_state() -> void:
	var live := await _spawn_player()
	var replay := await _spawn_player()
	live.reset_runtime_state()
	replay.reset_runtime_state()
	var live_manager: Node = live.get_node("TimeManager")
	var replay_manager: Node = replay.get_node("TimeManager")
	for manager: Node in [live_manager, replay_manager]:
		manager.energy_regen = 7.25
		manager.time_stop_cost = 10.0
		manager.time_stop_cooldown = 2.0
		manager.time_stop_duration = 1.5
	_suite.assert_true(live_manager.try_time_stop(), "live fixture starts Stop")
	_suite.assert_true(replay_manager.try_time_stop(), "replay fixture starts the same Stop")
	for frame: int in range(180):
		live.call("advance_action_frame", {})
		replay.call("advance_action_frame", {"source": "replay", "frame": frame + 1})
	var live_snapshot: Dictionary = live_manager.call("replay_snapshot") if live_manager.has_method("replay_snapshot") else {}
	var replay_snapshot: Dictionary = replay_manager.call("replay_snapshot") if replay_manager.has_method("replay_snapshot") else {"missing": true}
	_suite.assert_equal(replay_snapshot, live_snapshot, "live and Replay frame envelopes reach the identical time-state digest")
	await _free_player(live)
	await _free_player(replay)


func _test_time_rift_frame_snapshot_is_atomic() -> void:
	var rift := TimeRiftScene.instantiate()
	rift.duration = 2.0 / 60.0
	var payload_id := StringName("fixed-frame-test:1:rift:1:1")
	_suite.assert_true(rift.configure_world_payload_identity(payload_id), "Rift accepts its stable payload identity before entering the tree")
	add_child(rift)
	await get_tree().process_frame

	var initial: Dictionary = rift.world_payload_frame_snapshot()
	_suite.assert_equal(initial.size(), 7, "Rift frame snapshot exposes only its exact rollback fields")
	for field: String in [
		"schema_version", "payload_id", "source_id", "remaining_frames",
		"last_runtime_frame", "finished", "retirement_requested",
	]:
		_suite.assert_true(initial.has(field), "Rift frame snapshot includes %s" % field)
	_suite.assert_equal(int(initial.get("remaining_frames", -1)), 2, "Rift snapshot stores integer remaining frames")
	_suite.assert_equal(int(initial.get("last_runtime_frame", 0)), -1, "Rift snapshot starts before the first authoritative frame")
	_suite.assert_true(not bool(initial.get("finished", true)), "Rift snapshot starts active")
	var caller_copy := initial.duplicate(true)
	caller_copy["remaining_frames"] = 99
	_suite.assert_equal(rift.world_payload_frame_snapshot(), initial, "mutating a returned Rift snapshot cannot mutate node state")

	_suite.assert_true(rift.advance_frame(17), "Rift accepts any non-negative absolute first runtime frame")
	var frame_17: Dictionary = rift.world_payload_frame_snapshot()
	_suite.assert_equal(int(frame_17.get("remaining_frames", -1)), 1, "Rift consumes exactly one integer frame")
	_suite.assert_equal(int(frame_17.get("last_runtime_frame", -1)), 17, "Rift records the accepted absolute frame")
	_suite.assert_true(not rift.advance_frame(17), "Rift rejects a duplicate runtime frame")
	_suite.assert_equal(rift.world_payload_frame_snapshot(), frame_17, "duplicate rejection cannot mutate Rift frame state")
	_suite.assert_true(not rift.advance_frame(19), "Rift rejects a skipped runtime frame")
	_suite.assert_equal(rift.world_payload_frame_snapshot(), frame_17, "skip rejection cannot mutate Rift frame state")
	_suite.assert_true(rift.restore_world_payload_frame_snapshot(initial), "Rift restores its complete pre-frame snapshot")
	_suite.assert_equal(rift.world_payload_frame_snapshot(), initial, "Rift restore reaches exact snapshot equality")

	_suite.assert_true(rift.advance_frame(17), "Rift replays the restored first frame")
	_suite.assert_true(rift.advance_frame(18), "Rift reaches its exact terminal frame")
	var finished: Dictionary = rift.world_payload_frame_snapshot()
	_suite.assert_equal(int(finished.get("remaining_frames", -1)), 0, "terminal Rift snapshot preserves zero remaining frames")
	_suite.assert_true(bool(finished.get("finished", false)), "terminal Rift snapshot preserves finished lifecycle state")
	_suite.assert_true(rift.restore_world_payload_frame_snapshot(initial), "Rift can atomically roll terminal frame state back to active")
	_suite.assert_equal(rift.world_payload_frame_snapshot(), initial, "terminal rollback restores active state exactly")
	_suite.assert_true(rift.restore_world_payload_frame_snapshot(finished), "Rift can restore terminal lifecycle state exactly")
	_suite.assert_equal(rift.world_payload_frame_snapshot(), finished, "terminal lifecycle restore reaches exact equality")

	var malformed := finished.duplicate(true)
	malformed.erase("source_id")
	var before_malformed: Dictionary = rift.world_payload_frame_snapshot()
	_suite.assert_true(not rift.restore_world_payload_frame_snapshot(malformed), "Rift rejects a malformed frame snapshot")
	_suite.assert_equal(rift.world_payload_frame_snapshot(), before_malformed, "malformed restore rejection is atomic")
	rift.retire_world_payload(&"test_cleanup")
	await get_tree().process_frame
	await get_tree().process_frame


func _test_real_rift_uses_world_payload_authority_semantics() -> void:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout({
		"weapon_id": "sword",
		"enabled_time_skills": ["rift", "accelerate"],
	}), "Rift authority fixture configures")
	var manager: Node = player.get_node("TimeManager")
	var authority: Node = player.get_node("WorldPayloadAuthority")
	manager.time_rift_cost = 0.0
	manager.time_rift_cooldown = 0.0
	manager.time_rift_duration = 2.0
	var center := Vector2(144.0, 96.0)
	_suite.assert_true(manager.try_time_rift(center), "real Rift commits through WorldPayloadAuthority")
	var payload_id := StringName("%s:%d:rift:1:1" % [
		player.current_run_id(),
		player.owner_character_generation(),
	])
	_suite.assert_true(authority.contains(payload_id), "Rift stable payload identity becomes authoritative")
	var committed_node: Node = authority.payload_node(payload_id)
	var committed_source_id: StringName = committed_node.call("source_id") if committed_node.has_method("source_id") else &""
	_suite.assert_equal(committed_source_id, StringName("world_payload:%s" % payload_id), "Rift derives its gameplay source identity from the stable payload ID")
	var preserved: Dictionary = authority.preserve_committed_for_gameplay_rewind()
	_suite.assert_true(bool(preserved.get("ok", false)), "Gameplay Rewind uses preserve-only world semantics")
	_suite.assert_true(authority.payload_node(payload_id) == committed_node, "Gameplay Rewind preserves the exact Rift Node instance")
	var prepared_action_snapshot: Dictionary = manager.time_action_snapshot()
	_suite.assert_true(manager.try_time_rift(center + Vector2(64.0, 0.0)), "rollback fixture commits one additional Rift")
	var added_payload_id := StringName("%s:%d:rift:2:1" % [
		player.current_run_id(),
		player.owner_character_generation(),
	])
	_suite.assert_true(authority.contains(added_payload_id), "rollback fixture exposes the newly added Rift")
	_frame_signal_events.clear()
	EventBus.time_skill_ended.connect(_on_frame_time_skill_ended)
	var rollback_result: Dictionary = manager.call(
		"_restore_time_action_snapshot",
		prepared_action_snapshot.duplicate(true)
	)
	_suite.assert_true(bool(rollback_result.get("ok", false)), "TimeAction rollback restores the prepared manager/world snapshot")
	_suite.assert_true(
		not _frame_signal_events.has("ended:time_rift"),
		"transactional Rift rollback publishes no ended lifecycle event"
	)
	EventBus.time_skill_ended.disconnect(_on_frame_time_skill_ended)
	_suite.assert_equal(manager.time_action_snapshot(), prepared_action_snapshot, "TimeAction rollback reaches exact participant snapshot equality")
	_suite.assert_true(authority.payload_node(payload_id) == committed_node, "TimeAction rollback preserves the existing Rift Node identity")
	_suite.assert_true(not authority.contains(added_payload_id), "TimeAction rollback removes only the newly added Rift")
	_suite.assert_true(manager.try_time_rift(center + Vector2(96.0, 0.0)), "manual cancel fixture commits another world-owned Rift")
	var cancelled_node: Node = authority.payload_node(added_payload_id)
	_suite.assert_true(cancelled_node != null, "manual cancel fixture exposes its committed Rift Node")
	var fault_before: Dictionary = manager.time_action_snapshot()
	var failing_target := prepared_action_snapshot.duplicate(true)
	var failing_manager := failing_target.get("time_manager", {}) as Dictionary
	failing_manager["accelerate_active"] = true
	failing_manager["accelerate_token"] = 1
	failing_manager["accelerate_remaining"] = 1.0
	failing_manager["accelerate_multiplier"] = 1.35
	failing_manager["accelerate_publish_lifecycle"] = false
	failing_target["time_manager"] = failing_manager
	player.remove_child(manager)
	var failed_restore: Dictionary = manager.call(
		"_restore_time_action_snapshot",
		failing_target
	)
	player.add_child(manager)
	_suite.assert_true(not bool(failed_restore.get("ok", true)), "failed manager restore rejects the staged TimeAction rollback")
	_suite.assert_equal(manager.time_action_snapshot(), fault_before, "failed manager restore rolls every participant back atomically")
	_suite.assert_true(authority.payload_node(added_payload_id) == cancelled_node, "failed manager restore reattaches the exact staged Rift Node")
	if cancelled_node != null:
		cancelled_node.call("cancel", false)
	_suite.assert_true(
		cancelled_node != null and bool(cancelled_node.call("is_finished")),
		"manual Rift cancel hides the completed Node immediately"
	)
	_suite.assert_equal(
		int(manager.weapon_interaction_context().get("rift_generation", 0)),
		1,
		"manual Rift cancel falls back to the remaining source immediately"
	)
	await get_tree().process_frame
	await get_tree().process_frame
	_suite.assert_true(not authority.contains(added_payload_id), "manual Rift cancel retires its Authority descriptor before freeing the Node")
	_suite.assert_true(authority.payload_node(payload_id) == committed_node, "manual Rift cancel preserves unrelated committed Node identity")
	manager.call("_sync_active_rifts_from_authority")

	var replay_state: Dictionary = authority.replay_snapshot()
	var retired: Dictionary = authority.retire_payload(
		payload_id,
		player.current_run_id(),
		player.owner_character_generation(),
		&"replay_fixture_replace"
	)
	_suite.assert_true(bool(retired.get("ok", false)), "fixture removes the live Rift before Replay reconstruction")
	_suite.assert_true(not authority.contains(payload_id), "retired Rift leaves the live authority set")
	_suite.assert_true(authority.restore_replay_snapshot(replay_state), "Replay restore reconstructs the complete active Rift descriptor")
	manager.call("_sync_active_rifts_from_authority")
	var reconstructed_node: Node = authority.payload_node(payload_id)
	_suite.assert_true(reconstructed_node != null, "Replay restore creates the real Rift Node")
	_suite.assert_true(reconstructed_node != committed_node, "Replay reconstruction replaces rather than reuses the retired Node")
	var reconstructed_source_id: StringName = reconstructed_node.call("source_id") if reconstructed_node.has_method("source_id") else &""
	_suite.assert_equal(reconstructed_source_id, committed_source_id, "Replay reconstruction preserves the Rift gameplay source identity")
	_suite.assert_equal(authority.replay_snapshot(), replay_state, "Replay reconstruction reaches the exact descriptor snapshot")
	_suite.assert_equal(int(authority.replay_snapshot().get("last_runtime_frame", -2)), 0, "reconstructed Rift resumes from the reset frame-zero authority anchor")
	_suite.assert_equal(int(authority.payload_descriptor(payload_id).get("remaining_frames", -1)), 120, "reconstructed Rift restores all 120 duration frames")
	_suite.assert_equal(int((reconstructed_node.call("world_payload_frame_snapshot") as Dictionary).get("remaining_frames", -1)), 120, "reconstructed Rift Node restores all 120 duration frames")
	_advance(player, 118)
	_suite.assert_true(authority.contains(payload_id), "two-second Rift remains authoritative through frame 118")
	_suite.assert_equal(int(authority.payload_descriptor(payload_id).get("remaining_frames", -1)), 2, "Rift has exactly two frames remaining at frame 118")
	_suite.assert_equal(int((reconstructed_node.call("world_payload_frame_snapshot") as Dictionary).get("remaining_frames", -1)), 2, "Rift Node has exactly two frames remaining at frame 118")
	_advance(player, 1)
	_suite.assert_true(authority.contains(payload_id), "two-second Rift remains authoritative through frame 119")
	_suite.assert_equal(int(authority.payload_descriptor(payload_id).get("remaining_frames", -1)), 1, "Rift has exactly one frame remaining at frame 119")
	_advance(player, 1)
	_suite.assert_true(not authority.contains(payload_id), "two-second Rift expires exactly on frame 120")
	_advance(player, 1)
	_suite.assert_true(not authority.contains(payload_id), "expired Rift stays retired after frame 120")
	await _free_player(player)


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	var manager: Node = player.get_node("TimeManager")
	manager.set_process(false)
	var recorder: Node = player.get_node("RewindRecorder")
	recorder.set_process(false)
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.reset_runtime_state()
	return player


func _free_player(player: Node) -> void:
	if not is_instance_valid(player):
		return
	player.reset_runtime_state()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _advance(player: Node, frame_count: int) -> void:
	for _frame: int in range(maxi(0, frame_count)):
		player.call("advance_action_frame", {})
