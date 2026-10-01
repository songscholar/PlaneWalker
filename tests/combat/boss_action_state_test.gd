extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_idle_time_stop_invents_no_slam()
	await _test_windup_time_stop_delays_only_current_phase()
	await _test_recovery_time_stop_extends_only_recovery()
	await _test_slam_excludes_melee_and_special_patterns()
	await _test_every_action_uses_one_exclusive_clock()
	await _test_character_stop_exposure_tail_waits_for_the_owned_source_window()
	await _test_character_stop_exposure_tail_is_exactly_once_and_exactly_thirty_frames()
	await _test_character_stop_exposure_uses_unscaled_integer_runtime_frames()
	await _test_character_stop_exposure_claim_lifecycle_preserves_generation_deduplication()
	await _test_character_stop_exposure_snapshot_is_isolated_replay_safe_and_atomic()
	await _test_character_stop_exposure_live_restore_cannot_bypass_generation_deduplication()
	_suite.finish(get_tree())


func _test_idle_time_stop_invents_no_slam() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	var health: Node = subject["health"]
	var slam_count := [0]
	health.damaged.connect(func(_amount: float, _current_hp: float) -> void: slam_count[0] += 1)

	boss.apply_time_stop(0.2)
	boss.set_physics_process(true)
	await get_tree().create_timer(0.25).timeout

	var snapshot: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(snapshot["action"], "NONE", "idle time stop invents no action")
	_suite.assert_equal(snapshot["phase"], "IDLE", "idle time stop keeps the boss idle")
	_suite.assert_equal(slam_count[0], 0, "idle time stop resolves no slam")
	await _cleanup_subject(subject)


func _test_windup_time_stop_delays_only_current_phase() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	boss.force_slam_for_test()
	var before: Dictionary = _boss_snapshot(boss)

	boss.apply_time_stop(0.2)
	var delayed: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(delayed["action"], "SLAM", "windup time stop preserves the committed slam")
	_suite.assert_equal(delayed["phase"], "WINDUP", "windup time stop keeps the current phase")
	_suite.assert_true(float(delayed["remaining"]) > float(before["remaining"]), "windup time stop delays the current action")

	boss.set_physics_process(true)
	await get_tree().create_timer(float(delayed["remaining"]) + 0.05).timeout
	var recovery: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(recovery["action"], "SLAM", "slam remains the active action through recovery")
	_suite.assert_equal(recovery["phase"], "RECOVERY", "slam enters one recovery phase")
	_suite.assert_true(float(recovery["remaining"]) <= boss.slam_recovery + 0.01, "windup time stop does not also extend future recovery")
	await _cleanup_subject(subject)


func _test_recovery_time_stop_extends_only_recovery() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	var health: Node = subject["health"]
	var slam_count := [0]
	health.damaged.connect(func(_amount: float, _current_hp: float) -> void: slam_count[0] += 1)

	boss.force_slam_for_test()
	boss.set_physics_process(true)
	await get_tree().create_timer(boss.slam_windup + 0.05).timeout
	boss.set_physics_process(false)
	var before: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(before["phase"], "RECOVERY", "test reaches slam recovery")

	boss.apply_time_stop(0.2)
	var delayed: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(delayed["action"], "SLAM", "recovery time stop preserves the current action")
	_suite.assert_equal(delayed["phase"], "RECOVERY", "recovery time stop does not create windup")
	_suite.assert_true(float(delayed["remaining"]) >= float(before["remaining"]) + 0.79, "recovery time stop extends the current recovery by at least 0.8 seconds")

	boss.set_physics_process(true)
	await get_tree().create_timer(float(delayed["remaining"]) + 0.12).timeout
	var completed: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(completed["action"], "NONE", "extended recovery completes without another slam")
	_suite.assert_equal(completed["phase"], "IDLE", "extended recovery returns to idle")
	_suite.assert_equal(slam_count[0], 1, "recovery time stop resolves no duplicate slam")
	await _cleanup_subject(subject)


func _test_slam_excludes_melee_and_special_patterns() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	var health: Node = subject["health"]
	var damage_count := [0]
	health.damaged.connect(func(_amount: float, _current_hp: float) -> void: damage_count[0] += 1)

	boss.force_slam_for_test()
	boss._attack_cooldown_remaining = 0.0
	boss._pattern_timer = 0.0
	boss._special_index = 1
	var projectile_count_before := _hostile_projectile_count(boss)
	boss.set_physics_process(true)
	await get_tree().create_timer(0.12).timeout

	var snapshot: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(snapshot["action"], "SLAM", "slam remains the sole committed action")
	_suite.assert_equal(snapshot["phase"], "WINDUP", "slam is still winding up during mutual exclusion check")
	_suite.assert_equal(damage_count[0], 0, "slam windup blocks basic melee damage")
	_suite.assert_equal(_hostile_projectile_count(boss), projectile_count_before, "slam windup blocks radial projectile patterns")
	_suite.assert_equal(boss._special_index, 1, "blocked special pattern is not consumed")
	await _cleanup_subject(subject)


func _test_every_action_uses_one_exclusive_clock() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	var action_names: Array[String] = ["MELEE", "SLAM", "RADIAL", "AIMED", "SUMMON", "TIME_CRACK"]
	if not boss.has_method("force_action_for_test"):
		_suite.assert_true(false, "boss exposes deterministic action forcing for the shared action clock")
		await _cleanup_subject(subject)
		return

	boss._attack_cooldown_remaining = 0.0
	_suite.assert_true(boss.force_action_for_test(action_names[0]), "first boss action can enter the shared clock")
	for index: int in range(1, action_names.size()):
		_suite.assert_true(not boss.force_action_for_test(action_names[index]), "%s cannot replace an active %s action" % [action_names[index], action_names[0]])
	var snapshot: Dictionary = _boss_snapshot(boss)
	_suite.assert_equal(snapshot["action"], action_names[0], "mutual exclusion preserves the original committed action")
	_suite.assert_equal(snapshot["phase"], "WINDUP", "mutual exclusion preserves the original committed phase")
	await _cleanup_subject(subject)


func _test_character_stop_exposure_tail_waits_for_the_owned_source_window() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	var initial: Dictionary = boss.character_boss_exposure_snapshot()
	_suite.assert_true(not boss.extend_character_boss_exposure(31, 30), "idle Boss without exposure or committed recovery fails closed")
	_suite.assert_equal(boss.character_boss_exposure_snapshot(), initial, "missing-window rejection does not consume the Stop generation")

	boss.apply_time_stop_source(&"guardian-stop-window", 0.5)
	_suite.assert_true(bool(_boss_snapshot(boss).get("exposed", false)), "owned Stop source opens the Boss exposure window")
	_suite.assert_true(boss.extend_character_boss_exposure(31, 30), "the exposed Stop generation reserves one character tail")
	_suite.assert_equal(boss.character_boss_exposure_snapshot().get("tail_state"), "pending", "the character tail waits behind the owned Stop source")
	boss.advance_character_boss_exposure_for_test(30)
	_suite.assert_equal(boss.character_boss_exposure_snapshot().get("remaining_tail_frames"), 30, "pending tail cannot overlap or consume inside the original Stop exposure")

	boss.clear_time_stop_source(&"guardian-stop-window")
	_suite.assert_equal(boss.character_boss_exposure_snapshot().get("tail_state"), "active", "clearing the owned Stop source activates the exact tail")
	_suite.assert_true(bool(_boss_snapshot(boss).get("exposed", false)), "source cleanup cannot create a one-frame vulnerability gap")
	boss.advance_character_boss_exposure_for_test(30)
	_suite.assert_true(not bool(_boss_snapshot(boss).get("exposed", true)), "the source-owned extension closes after its exact tail")
	await _cleanup_subject(subject)


func _test_character_stop_exposure_tail_is_exactly_once_and_exactly_thirty_frames() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	_suite.assert_true(boss.force_action_for_test("SLAM"), "exposure-tail fixture commits one Boss action")
	var windup: Dictionary = _boss_snapshot(boss)
	boss.advance_action_for_test(float(windup.get("remaining", 0.0)) + 0.01)
	_suite.assert_equal(_boss_snapshot(boss).get("phase"), "RECOVERY", "exposure-tail fixture reaches committed recovery")

	_suite.assert_true(
		boss.extend_character_boss_exposure(41, 30),
		"one positive Stop generation reserves the exact maximum exposure tail"
	)
	var reserved: Dictionary = boss.character_boss_exposure_snapshot()
	_suite.assert_equal(reserved.get("claimed_stop_generation_floor"), 41, "accepted Stop generation advances the permanent deduplication floor")
	_suite.assert_equal(reserved.get("remaining_tail_frames"), 30, "accepted Stop conversion reserves exactly thirty frames")
	_suite.assert_equal(reserved.get("tail_state"), "pending", "recovery keeps the exposure tail pending")
	_suite.assert_true(not boss.extend_character_boss_exposure(41, 30), "same Stop generation cannot stack its exposure tail")
	_suite.assert_true(not boss.extend_character_boss_exposure(0, 30), "non-positive Stop generation fails closed")
	_suite.assert_true(not boss.extend_character_boss_exposure(40, 30), "older Stop generation fails closed")
	_suite.assert_true(not boss.extend_character_boss_exposure(42, 0), "non-positive exposure duration fails closed")
	_suite.assert_true(not boss.extend_character_boss_exposure(42, 31), "an exposure request above the thirty-frame bound fails closed")
	_suite.assert_equal(boss.character_boss_exposure_snapshot(), reserved, "rejected exposure requests leave the complete ledger unchanged")

	var recovery: Dictionary = _boss_snapshot(boss)
	boss.advance_action_for_test(float(recovery.get("remaining", 0.0)) + 0.01)
	_suite.assert_equal(_boss_snapshot(boss).get("phase"), "IDLE", "the original committed recovery completes normally")
	_suite.assert_true(bool(_boss_snapshot(boss).get("exposed", false)), "completion activates the reserved vulnerability tail")
	_suite.assert_equal(boss.character_boss_exposure_snapshot().get("tail_state"), "active", "completion advances the claim lifecycle to active")

	boss.advance_character_boss_exposure_for_test(29)
	_suite.assert_true(bool(_boss_snapshot(boss).get("exposed", false)), "the Boss remains exposed through tail frame twenty-nine")
	_suite.assert_equal(boss.character_boss_exposure_snapshot().get("remaining_tail_frames"), 1, "twenty-nine frames leave one exact exposure frame")
	boss.advance_character_boss_exposure_for_test(1)
	_suite.assert_true(not bool(_boss_snapshot(boss).get("exposed", true)), "the Boss exposure closes exactly on tail frame thirty")
	_suite.assert_equal(boss.character_boss_exposure_snapshot().get("remaining_tail_frames"), 0, "completed tail retains no active duration")
	_suite.assert_equal(boss.character_boss_exposure_snapshot().get("claimed_stop_generation_floor"), 41, "tail completion preserves the permanent Stop-generation claim")
	await _cleanup_subject(subject)


func _test_character_stop_exposure_uses_unscaled_integer_runtime_frames() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	boss.apply_time_stop_source(&"integer-frame-window", 0.5)
	_suite.assert_true(boss.extend_character_boss_exposure(47, 30), "integer-frame fixture reserves one exposure tail")
	boss.clear_time_stop_source(&"integer-frame-window")
	_suite.assert_equal(boss.character_boss_exposure_snapshot().get("tail_state"), "active", "integer-frame fixture activates its tail")

	_suite.assert_true(
		boss.elemental_status_runtime.apply_status(&"slow", &"frame-slow", 1, 120, 0.25, 30, 0.10),
		"integer-frame fixture installs a severe elemental attack-speed multiplier"
	)
	_suite.assert_true(
		boss.elemental_status_runtime.apply_status(&"freeze", &"frame-freeze", 1, 120, 1.0),
		"integer-frame fixture installs a hard elemental freeze"
	)
	boss.call("_tick_additional_action_timers", 999.0)
	_suite.assert_equal(
		boss.character_boss_exposure_snapshot().get("remaining_tail_frames"),
		30,
		"scaled delta cannot consume any character exposure frame"
	)
	boss.call("_tick_unscaled_runtime_frame", 100)
	boss.call("_tick_unscaled_runtime_frame", 129)
	_suite.assert_equal(
		boss.character_boss_exposure_snapshot().get("remaining_tail_frames"),
		1,
		"twenty-nine authoritative integer frames consume exactly twenty-nine tail frames despite slow and freeze"
	)
	_suite.assert_true(bool(_boss_snapshot(boss).get("exposed", false)), "tail remains exposed through authoritative frame twenty-nine")
	boss.call("_tick_unscaled_runtime_frame", 130)
	_suite.assert_equal(
		boss.character_boss_exposure_snapshot().get("remaining_tail_frames"),
		0,
		"authoritative integer frame thirty consumes the exact final tail frame"
	)
	_suite.assert_true(not bool(_boss_snapshot(boss).get("exposed", true)), "tail closes on authoritative frame thirty even while the Boss is frozen")
	await _cleanup_subject(subject)


func _test_character_stop_exposure_claim_lifecycle_preserves_generation_deduplication() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	_suite.assert_true(boss.force_action_for_test("SLAM"), "cancel fixture commits one Boss action")
	var windup: Dictionary = _boss_snapshot(boss)
	boss.advance_action_for_test(float(windup.get("remaining", 0.0)) + 0.01)
	_suite.assert_true(boss.extend_character_boss_exposure(51, 30), "cancel fixture reserves generation 51")
	boss.cancel_active_attack()
	var cancelled: Dictionary = boss.character_boss_exposure_snapshot()
	_suite.assert_equal(cancelled.get("remaining_tail_frames"), 0, "cancellation clears the active claim lifecycle")
	_suite.assert_equal(cancelled.get("claimed_stop_generation_floor"), 51, "cancellation cannot erase the used generation")
	_suite.assert_true(not bool(_boss_snapshot(boss).get("exposed", true)), "cancellation leaves no residual character exposure source")

	_suite.assert_true(boss.force_action_for_test("SLAM"), "Boss may commit a fresh action after cancellation")
	windup = _boss_snapshot(boss)
	boss.advance_action_for_test(float(windup.get("remaining", 0.0)) + 0.01)
	_suite.assert_true(not boss.extend_character_boss_exposure(51, 30), "fresh action cannot reuse the cancelled Stop generation")
	_suite.assert_true(boss.extend_character_boss_exposure(52, 30), "a newer Stop generation owns an independent exposure claim")
	boss.reset_character_boss_exposure_state()
	var reset: Dictionary = boss.character_boss_exposure_snapshot()
	_suite.assert_equal(reset.get("remaining_tail_frames"), 0, "explicit reset clears pending and active claim lifetime")
	_suite.assert_equal(reset.get("claimed_stop_generation_floor"), 52, "explicit reset preserves permanent generation deduplication")
	_suite.assert_true(not boss.extend_character_boss_exposure(52, 30), "reset cannot make the same Stop generation reusable")
	await _cleanup_subject(subject)


func _test_character_stop_exposure_snapshot_is_isolated_replay_safe_and_atomic() -> void:
	var source_subject: Dictionary = await _spawn_subject()
	var source: Node = source_subject["boss"]
	var replay_authority := RefCounted.new()
	_suite.assert_true(source.configure_character_boss_exposure_replay_authority(replay_authority), "snapshot fixture installs a protected Replay authority")
	_suite.assert_true(source.force_action_for_test("SLAM"), "snapshot fixture commits one Boss action")
	var windup: Dictionary = _boss_snapshot(source)
	source.advance_action_for_test(float(windup.get("remaining", 0.0)) + 0.01)
	_suite.assert_true(source.extend_character_boss_exposure(61, 30), "snapshot fixture reserves one exposure tail")
	var recovery: Dictionary = _boss_snapshot(source)
	source.advance_action_for_test(float(recovery.get("remaining", 0.0)) + 0.01)
	var checkpoint: Dictionary = source.character_boss_exposure_snapshot()
	_suite.assert_equal(checkpoint.get("tail_state"), "active", "checkpoint captures an active replay-safe tail")
	(checkpoint.get("claims", []) as Array).clear()
	_suite.assert_equal((source.character_boss_exposure_snapshot().get("claims", []) as Array).size(), 1, "mutating a returned snapshot cannot mutate the live ledger")
	checkpoint = source.character_boss_exposure_snapshot()

	source.advance_character_boss_exposure_for_test(10)
	_suite.assert_equal(source.character_boss_exposure_snapshot().get("remaining_tail_frames"), 20, "fixture diverges after its checkpoint")
	_suite.assert_true(not source.can_restore_character_boss_exposure_snapshot(checkpoint), "ordinary live restore cannot rewind an already-consumed tail")
	_suite.assert_true(source.can_restore_character_boss_exposure_replay_snapshot(checkpoint, replay_authority), "protected exact active checkpoint passes Replay restore preflight")
	_suite.assert_true(source.restore_character_boss_exposure_replay_snapshot(checkpoint, replay_authority), "protected active checkpoint restores atomically")
	_suite.assert_equal(source.character_boss_exposure_snapshot(), checkpoint, "restore reinstalls every data-only exposure field exactly")

	var replay_subject: Dictionary = await _spawn_subject()
	var replay_target: Node = replay_subject["boss"]
	_suite.assert_true(replay_target.configure_character_boss_exposure_replay_authority(replay_authority), "fresh Replay target installs the protected authority")
	_suite.assert_true(replay_target.can_restore_character_boss_exposure_replay_snapshot(checkpoint, replay_authority), "fresh Replay target accepts the data-only checkpoint")
	_suite.assert_true(replay_target.restore_character_boss_exposure_replay_snapshot(checkpoint, replay_authority), "fresh Replay target reconstructs the exposure ledger")
	_suite.assert_equal(replay_target.character_boss_exposure_snapshot(), checkpoint, "Replay reconstruction is byte-equivalent")
	_suite.assert_true(bool(_boss_snapshot(replay_target).get("exposed", false)), "Replay reconstruction restores the actual Boss vulnerability")

	var invalid_snapshots: Array[Dictionary] = []
	var missing_field := checkpoint.duplicate(true)
	missing_field.erase("claims")
	invalid_snapshots.append(missing_field)
	var unknown_field := checkpoint.duplicate(true)
	unknown_field["smuggled"] = true
	invalid_snapshots.append(unknown_field)
	var stale_floor := checkpoint.duplicate(true)
	stale_floor["claimed_stop_generation_floor"] = 60
	invalid_snapshots.append(stale_floor)
	var oversized_claim := checkpoint.duplicate(true)
	((oversized_claim["claims"] as Array)[0] as Dictionary)["remaining_frames"] = 31
	invalid_snapshots.append(oversized_claim)
	var foreign_run := checkpoint.duplicate(true)
	(foreign_run["identity"] as Dictionary)["run_id"] = "foreign-run"
	invalid_snapshots.append(foreign_run)
	var foreign_room := checkpoint.duplicate(true)
	(foreign_room["identity"] as Dictionary)["room_id"] = "foreign-room"
	invalid_snapshots.append(foreign_room)
	var foreign_encounter := checkpoint.duplicate(true)
	(foreign_encounter["identity"] as Dictionary)["encounter_id"] = "foreign-encounter"
	invalid_snapshots.append(foreign_encounter)
	var foreign_boss := checkpoint.duplicate(true)
	(foreign_boss["identity"] as Dictionary)["hostile_source_id"] = "foreign-boss"
	invalid_snapshots.append(foreign_boss)
	for index: int in range(invalid_snapshots.size()):
		var before: Dictionary = replay_target.character_boss_exposure_snapshot()
		_suite.assert_true(
			not replay_target.can_restore_character_boss_exposure_replay_snapshot(invalid_snapshots[index], replay_authority),
			"invalid exposure snapshot %d fails preflight" % index
		)
		_suite.assert_true(
			not replay_target.restore_character_boss_exposure_replay_snapshot(invalid_snapshots[index], replay_authority),
			"invalid exposure snapshot %d fails restore" % index
		)
		_suite.assert_equal(replay_target.character_boss_exposure_snapshot(), before, "failed exposure restore %d is atomic" % index)

	await _cleanup_subject(replay_subject)
	await _cleanup_subject(source_subject)


func _test_character_stop_exposure_live_restore_cannot_bypass_generation_deduplication() -> void:
	var subject: Dictionary = await _spawn_subject()
	var boss: Node = subject["boss"]
	boss.apply_time_stop_source(&"generation-61-window", 0.5)
	_suite.assert_true(boss.extend_character_boss_exposure(61, 30), "live-restore fixture claims generation 61")
	boss.clear_time_stop_source(&"generation-61-window")
	var generation_61: Dictionary = boss.character_boss_exposure_snapshot()
	boss.advance_character_boss_exposure_for_test(1)
	var generation_61_advanced: Dictionary = boss.character_boss_exposure_snapshot()
	_suite.assert_true(
		not boss.restore_character_boss_exposure_snapshot(generation_61),
		"ordinary runtime restore cannot resurrect a consumed frame inside the same generation"
	)
	_suite.assert_equal(boss.character_boss_exposure_snapshot(), generation_61_advanced, "same-generation live rewind rejection is atomic")
	_suite.assert_true(boss.extend_character_boss_exposure(62, 30), "live-restore fixture advances to generation 62")
	var generation_62: Dictionary = boss.character_boss_exposure_snapshot()

	_suite.assert_true(
		not boss.can_restore_character_boss_exposure_snapshot(generation_61),
		"ordinary runtime restore preflight rejects a generation-floor rollback"
	)
	_suite.assert_true(
		not boss.restore_character_boss_exposure_snapshot(generation_61),
		"ordinary runtime restore cannot bypass live monotonic generation deduplication"
	)
	_suite.assert_equal(boss.character_boss_exposure_snapshot(), generation_62, "rejected live rollback leaves the generation-62 ledger exact")
	_suite.assert_true(not boss.has_method("restore_character_boss_exposure_replay_snapshot") or not bool(boss.call(
		"restore_character_boss_exposure_replay_snapshot",
		generation_61,
		RefCounted.new()
	)), "an unconfigured caller cannot invoke protected Replay exact restore")
	await _cleanup_subject(subject)


func _spawn_subject() -> Dictionary:
	var player := PlayerScene.instantiate()
	player.set_physics_process(false)
	add_child(player)
	player.global_position = Vector2(48.0, 0.0)

	var boss := BossScene.instantiate()
	boss.set_physics_process(false)
	boss.configure_hostile_identity(&"boss-action-state-warden", 1)
	boss.set_meta("run_id", &"run-boss-action-state")
	boss.set_meta("room_id", &"room-boss-action-state")
	boss.set_meta("encounter_id", &"encounter-boss-action-state")
	boss.set_meta("encounter_spawn_id", &"spawn-boss-action-state")
	boss.set_meta("encounter_enemy_id", &"chrono_warden")
	add_child(boss)
	boss.set_physics_process(false)
	boss.global_position = Vector2.ZERO
	boss.move_speed = 0.0
	boss._pattern_timer = 99.0
	boss._attack_cooldown_remaining = 99.0
	await get_tree().process_frame
	return {
		"player": player,
		"boss": boss,
		"health": player.get_node("HealthComponent"),
	}


func _cleanup_subject(subject: Dictionary) -> void:
	var boss: Node = subject["boss"]
	var player: Node = subject["player"]
	if is_instance_valid(boss):
		boss.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _hostile_projectile_count(boss: Node) -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("time_stoppable"):
		if node != boss and node.get_script() != null and str(node.get_script().resource_path).ends_with("enemy_projectile.gd"):
			count += 1
	return count


func _boss_snapshot(boss: Node) -> Dictionary:
	if boss.has_method("get_boss_ui_snapshot"):
		return boss.get_boss_ui_snapshot()
	_suite.assert_true(false, "boss exposes an action snapshot")
	return {
		"action": "MISSING",
		"phase": "MISSING",
		"remaining": 0.0,
	}
