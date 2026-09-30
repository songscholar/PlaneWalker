extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const HurtboxScript := preload("res://scripts/combat/hurtbox.gd")
const ReplayPlayerScript := preload("res://scripts/replay/replay_player.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const REPLAY_CLAIMS_META := &"planewalker_replay_external_fact_claims"


class ReplayHealth extends Node:
	var max_hp: float = 100000.0
	var current_hp: float = 100000.0
	var dead: bool = false
	var damage_signal_count: int = 0

	func take_damage(damage_info: RefCounted) -> float:
		if dead:
			return 0.0
		var applied := minf(current_hp, float(damage_info.get("amount")))
		current_hp = maxf(0.0, current_hp - applied)
		dead = current_hp <= 0.0
		damage_signal_count += 1
		EventBus.hit_confirmed.emit(damage_info, get_parent(), applied)
		return applied


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var profile := _load_profile(suite)
	if not profile.is_empty():
		await _test_high_combo_primary_with_energy_return(suite, profile)
		await _test_high_combo_full_energy_revision_is_stable(suite, profile)
		await _test_skill_zone_and_first_tick(suite, profile)
		await _test_stop_hit_event_order(suite, profile)
		await _test_accelerate_third_hit_spawns_echo(suite, profile)
		await _test_record_time_payload_fact_fails_closed(suite, profile)
	suite.finish(get_tree())


func _test_high_combo_primary_with_energy_return(suite, profile: Dictionary) -> void:
	var target := await _spawn_target()
	var health: ReplayHealth = target.get_node("HealthComponent")
	var source := await _spawn_player(suite, profile)
	if source == null:
		await _free_target(target)
		return

	suite.assert_true(
		await _grant_combo_with_real_hits(source, target, 30),
		"high-Combo replay fixture earns thirty Combo through real Gauntlets hits"
	)
	_reset_target(target)
	var combo_before := _combo_count(source)
	suite.assert_true(combo_before >= 30, "high-Combo replay fixture reaches the time-storm tier")
	_set_time_energy(source, 40.0)
	source.time_manager.energy_regen = 0.0
	_reset_replay_capture(source)

	var recorder = ReplayRecorderScript.new()
	suite.assert_true(
		bool(recorder.start_recording(profile, 810101).get("ok", false)),
		"high-Combo replay recording starts"
	)
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"high-Combo replay records its READY checkpoint"
	)
	suite.assert_true(
		await _drive_to_active(source, &"weapon_primary"),
		"high-Combo primary reaches ACTIVE"
	)
	var active: Dictionary = source.weapon_replay_snapshot()
	suite.assert_true(
		bool(recorder.record_snapshot(active).get("ok", false)),
		"high-Combo replay records its pre-hit ACTIVE checkpoint"
	)
	var hp_before_recorded_hit := health.current_hp
	var energy_before_hit: Dictionary = source.time_manager.resource_state(&"time_energy")
	var result: Dictionary = _execute_live_hit(source, target)
	suite.assert_true(not result.is_empty(), "high-Combo primary resolves through the real hit payload")
	var energy_after_hit: Dictionary = source.time_manager.resource_state(&"time_energy")
	suite.assert_close(float(energy_after_hit.get("current", -1.0)), 43.0, "high-Combo primary returns three Time Energy")
	suite.assert_equal(
		int(energy_after_hit.get("revision", 0)),
		int(energy_before_hit.get("revision", 0)) + 1,
		"non-full high-Combo Energy return increments the authoritative revision once"
	)
	suite.assert_equal(
		_coordinator_time_energy_state(source.weapon_replay_snapshot()),
		energy_after_hit,
		"non-full high-Combo Energy return mirrors the exact revision into the coordinator"
	)
	suite.assert_true(_combo_count(source) > combo_before, "high-Combo primary advances authoritative Combo")

	var replay_data: Dictionary = await _finish_ready_replay(
		suite, source, recorder, "high-Combo primary"
	)
	var replay := replay_data.get("replay", {}) as Dictionary
	var terminal := replay_data.get("terminal", {}) as Dictionary
	var events := replay_data.get("events", []) as Array
	suite.assert_true(_fact_count(events, "combat_damage") >= 1, "high-Combo primary records real damage facts")
	suite.assert_equal(_fact_count(events, "weapon_payload_result"), 1, "high-Combo primary records one payload-result fact")
	var source_instance_id := source.get_instance_id()
	var expected_hp := health.max_hp - (hp_before_recorded_hit - health.current_hp)
	await _free_player(source)
	_reset_target(target)

	var replay_target := await _replay_and_assert(
		suite,
		profile,
		replay,
		terminal,
		target,
		expected_hp,
		"high-Combo primary",
		true
	)
	if replay_target != null:
		suite.assert_true(
			replay_target.get_instance_id() != source_instance_id,
			"high-Combo replay crosses Player instances"
		)
		suite.assert_close(float(replay_target.time_manager.energy), 43.0, "high-Combo replay reproduces Energy return")
		suite.assert_true(_combo_count(replay_target) > combo_before, "high-Combo replay reproduces Combo gain")
		await _free_player(replay_target)
	await _free_target(target)


func _test_high_combo_full_energy_revision_is_stable(suite, profile: Dictionary) -> void:
	var target := await _spawn_target()
	var health: ReplayHealth = target.get_node("HealthComponent")
	var source := await _spawn_player(suite, profile)
	if source == null:
		await _free_target(target)
		return

	suite.assert_true(
		await _grant_combo_with_real_hits(source, target, 30),
		"full-Energy replay fixture earns thirty Combo through real Gauntlets hits"
	)
	_reset_target(target)
	_set_time_energy(source, 100.0)
	_reset_replay_capture(source)

	var recorder = ReplayRecorderScript.new()
	suite.assert_true(
		bool(recorder.start_recording(profile, 810102).get("ok", false)),
		"full-Energy high-Combo replay recording starts"
	)
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"full-Energy high-Combo replay records its READY checkpoint"
	)
	suite.assert_true(
		await _drive_to_active(source, &"weapon_primary"),
		"full-Energy high-Combo primary reaches ACTIVE"
	)
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"full-Energy high-Combo replay records its pre-hit ACTIVE checkpoint"
	)
	var hp_before_recorded_hit := health.current_hp
	var energy_before_hit: Dictionary = source.time_manager.resource_state(&"time_energy")
	var result: Dictionary = _execute_live_hit(source, target)
	suite.assert_true(not result.is_empty(), "full-Energy high-Combo primary resolves through the real hit payload")
	var energy_after_hit: Dictionary = source.time_manager.resource_state(&"time_energy")
	suite.assert_close(
		float(energy_after_hit.get("current", -1.0)),
		float(energy_before_hit.get("current", -2.0)),
		"full-Energy high-Combo return leaves current Energy capped"
	)
	suite.assert_equal(
		int(energy_after_hit.get("revision", 0)),
		int(energy_before_hit.get("revision", -1)),
		"full-Energy high-Combo return leaves the authoritative revision unchanged"
	)
	suite.assert_equal(
		_coordinator_time_energy_state(source.weapon_replay_snapshot()),
		energy_before_hit,
		"full-Energy high-Combo return leaves the coordinator Energy mirror unchanged"
	)

	var replay_data: Dictionary = await _finish_ready_replay(
		suite, source, recorder, "full-Energy high-Combo primary"
	)
	var replay := replay_data.get("replay", {}) as Dictionary
	var terminal := replay_data.get("terminal", {}) as Dictionary
	var events := replay_data.get("events", []) as Array
	suite.assert_equal(
		_fact_count(events, "weapon_payload_result"),
		1,
		"full-Energy high-Combo primary records one payload-result fact"
	)
	var expected_hp := health.max_hp - (hp_before_recorded_hit - health.current_hp)
	await _free_player(source)
	_reset_target(target)

	var replay_target := await _replay_and_assert(
		suite,
		profile,
		replay,
		terminal,
		target,
		expected_hp,
		"full-Energy high-Combo primary"
	)
	if replay_target != null:
		var replay_energy: Dictionary = replay_target.time_manager.resource_state(&"time_energy")
		suite.assert_equal(
			replay_energy,
			energy_before_hit,
			"full-Energy high-Combo replay preserves current Energy and revision exactly"
		)
		await _free_player(replay_target)
	await _free_target(target)


func _test_skill_zone_and_first_tick(suite, profile: Dictionary) -> void:
	var target := await _spawn_target()
	var health: ReplayHealth = target.get_node("HealthComponent")
	var source := await _spawn_player(suite, profile)
	if source == null:
		await _free_target(target)
		return
	_set_time_energy(source, 80.0)
	_reset_replay_capture(source)

	var recorder = ReplayRecorderScript.new()
	suite.assert_true(
		bool(recorder.start_recording(profile, 810202).get("ok", false)),
		"Gauntlets zone replay recording starts"
	)
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"Gauntlets zone replay records its READY checkpoint"
	)
	suite.assert_true(
		await _drive_to_active(source, &"weapon_skill"),
		"Space-Time Shatter reaches ACTIVE"
	)
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"Gauntlets zone replay records its pre-hit ACTIVE checkpoint"
	)
	var hit_result := _execute_live_hit(source, target)
	suite.assert_true(not hit_result.is_empty(), "Space-Time Shatter resolves its real opening hit")
	var zone := _first_owned_payload(source, "zone")
	suite.assert_true(zone != null, "Space-Time Shatter creates a real owned zone")
	if zone != null:
		var zone_snapshot: Dictionary = zone.call("execution_snapshot")
		var tick_interval := int(zone_snapshot.get("tick_interval_frames", 0))
		suite.assert_true(tick_interval > 0, "Space-Time Shatter exposes a positive tick interval")
		zone.call("advance_execution_for_test", tick_interval)
		var after_tick: Dictionary = zone.call("execution_snapshot")
		suite.assert_equal(
			(after_tick.get("damage_claim_keys", []) as Array).size(),
			1,
			"Space-Time Shatter records exactly one first-tick damage claim"
		)

	var replay_data: Dictionary = await _finish_ready_replay(
		suite, source, recorder, "Gauntlets zone tick"
	)
	var replay := replay_data.get("replay", {}) as Dictionary
	var terminal := replay_data.get("terminal", {}) as Dictionary
	var events := replay_data.get("events", []) as Array
	suite.assert_equal(_fact_count(events, "weapon_payload_result"), 2, "zone replay records opening-hit and first-tick payload results")
	suite.assert_true(_fact_count(events, "combat_damage") >= 2, "zone replay records opening-hit and first-tick damage")
	var expected_hp := health.current_hp
	await _free_player(source)
	_reset_target(target)

	var replay_target := await _replay_and_assert(
		suite,
		profile,
		replay,
		terminal,
		target,
		expected_hp,
		"Gauntlets zone tick"
	)
	if replay_target != null:
		var replay_zone := _first_owned_payload(replay_target, "zone")
		suite.assert_true(replay_zone != null, "zone replay preserves the owned zone at terminal")
		if replay_zone != null:
			var replay_zone_snapshot: Dictionary = replay_zone.call("execution_snapshot")
			suite.assert_equal(
				(replay_zone_snapshot.get("damage_claim_keys", []) as Array).size(),
				1,
				"zone replay restores exactly one first-tick damage claim"
			)
		await _free_player(replay_target)
	await _free_target(target)


func _test_record_time_payload_fact_fails_closed(suite, profile: Dictionary) -> void:
	var target := await _spawn_target()
	var source := await _spawn_player(suite, profile)
	if source == null:
		await _free_target(target)
		return
	suite.assert_true(
		await _drive_to_active(source, &"weapon_primary"),
		"record-time fail-closed fixture reaches ACTIVE"
	)
	suite.assert_true(
		not _execute_live_hit(source, target).is_empty(),
		"record-time fail-closed fixture captures a real payload result"
	)
	var payload_event := _fact_event(source.weapon_replay_events(), "weapon_payload_result")
	suite.assert_true(
		not payload_event.is_empty(),
		"record-time fail-closed fixture exposes a real payload-result fact"
	)
	if payload_event.is_empty():
		await _free_player(source)
		await _free_target(target)
		return
	var payload := payload_event.get("payload", {}) as Dictionary
	var recorded_data := (payload.get("data", {}) as Dictionary).duplicate(true)
	var forged_after: Dictionary = source.weapon_replay_snapshot()
	var forged_player_state := forged_after.get("player_weapon_state", {}) as Dictionary
	forged_player_state["combo_timeout_frames"] = int(
		forged_player_state.get("combo_timeout_frames", 0)
	) + 1
	recorded_data["state_after"] = forged_after
	recorded_data.erase("state_before_digest")
	_reset_replay_capture(source)
	var before_snapshot: Dictionary = source.weapon_replay_snapshot()
	var before_events: Array[Dictionary] = source.weapon_replay_events()
	var before_sequence := int(source.get("_weapon_replay_capture_sequence"))
	var baseline_value: Variant = source.get("_weapon_replay_fact_baseline")
	var before_baseline := (
		(baseline_value as Dictionary).duplicate(true)
		if baseline_value is Dictionary
		else {}
	)
	source.call(
		"_record_weapon_replay_external_fact",
		"weapon_payload_result",
		int(payload.get("action_token", 0)),
		int(payload.get("action_generation", 0)),
		recorded_data
	)
	suite.assert_true(
		source.weapon_replay_events() == before_events,
		"record-time projector rejects an unauthorized payload state without appending an event"
	)
	suite.assert_equal(
		int(source.get("_weapon_replay_capture_sequence")),
		before_sequence,
		"record-time projector rejection does not consume a capture sequence"
	)
	var after_baseline_value: Variant = source.get("_weapon_replay_fact_baseline")
	var after_baseline := (
		(after_baseline_value as Dictionary).duplicate(true)
		if after_baseline_value is Dictionary
		else {}
	)
	suite.assert_true(
		after_baseline == before_baseline,
		"record-time projector rejection does not refresh the authenticated baseline"
	)
	suite.assert_true(
		source.weapon_replay_snapshot() == before_snapshot,
		"record-time projector rejection leaves live Player state unchanged"
	)
	await _free_player(source)
	await _free_target(target)


func _test_stop_hit_event_order(suite, profile: Dictionary) -> void:
	var target := await _spawn_target()
	var health: ReplayHealth = target.get_node("HealthComponent")
	var source := await _spawn_player(suite, profile)
	if source == null:
		await _free_target(target)
		return
	_set_time_energy(source, 100.0)
	suite.assert_true(source.time_manager.try_time_stop(), "Stop replay fixture starts authoritative Time Stop")
	_reset_replay_capture(source)

	var recorder = ReplayRecorderScript.new()
	suite.assert_true(
		bool(recorder.start_recording(profile, 810303).get("ok", false)),
		"Stop-active replay recording starts"
	)
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"Stop-active replay records its READY checkpoint"
	)
	suite.assert_true(await _drive_to_active(source, &"weapon_primary"), "Stop-active primary reaches ACTIVE")
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"Stop-active replay records its pre-hit ACTIVE checkpoint"
	)
	var result: Dictionary = _execute_live_hit(source, target)
	suite.assert_true(not result.is_empty(), "Stop-active primary resolves through the real hit payload")

	var replay_data: Dictionary = await _finish_ready_replay(
		suite, source, recorder, "Stop-active hit"
	)
	var replay := replay_data.get("replay", {}) as Dictionary
	var terminal := replay_data.get("terminal", {}) as Dictionary
	var events := replay_data.get("events", []) as Array
	var ordered_facts := _external_fact_types(events)
	suite.assert_equal(
		ordered_facts,
		["combat_damage", "weapon_payload_result"],
		"Stop-active hit folds its extension into the ordered payload result"
	)
	suite.assert_equal(
		_fact_count(events, "time_stop_extension"),
		0,
		"Stop-active Gauntlets hit does not publish a competing standalone Stop fact"
	)
	var expected_hp := health.current_hp
	await _free_player(source)
	_reset_target(target)
	await _assert_stop_payload_smuggling_is_rejected(
		suite,
		profile,
		replay,
		target
	)
	_reset_target(target)

	var replay_target := await _replay_and_assert(
		suite,
		profile,
		replay,
		terminal,
		target,
		expected_hp,
		"Stop-active hit"
	)
	if replay_target != null:
		var time_state: Dictionary = replay_target.time_manager.weapon_replay_snapshot()
		suite.assert_true(bool(time_state.get("stop_active", false)), "Stop-active replay preserves active Time Stop")
		suite.assert_equal(int(time_state.get("stop_extension_frames", 0)), 5, "Stop-active replay applies one five-frame extension")
		await _free_player(replay_target)
	await _free_target(target)


func _test_accelerate_third_hit_spawns_echo(suite, profile: Dictionary) -> void:
	var target := await _spawn_target()
	var health: ReplayHealth = target.get_node("HealthComponent")
	var source := await _spawn_player(suite, profile)
	if source == null:
		await _free_target(target)
		return
	_set_time_energy(source, 100.0)
	suite.assert_true(source.time_manager.try_time_accelerate(), "Accelerate replay fixture starts authoritative acceleration")
	for index: int in range(2):
		suite.assert_true(
			await _drive_to_active(source, &"weapon_primary"),
			"Accelerate setup hit %d reaches ACTIVE" % (index + 1)
		)
		suite.assert_true(
			not _execute_live_hit(source, target).is_empty(),
			"Accelerate setup hit %d resolves" % (index + 1)
		)
		suite.assert_true(
			await _advance_to_ready(source),
			"Accelerate setup hit %d reaches READY" % (index + 1)
		)
		_reset_replay_capture(source)
	_reset_target(target)
	_reset_replay_capture(source)

	var recorder = ReplayRecorderScript.new()
	suite.assert_true(
		bool(recorder.start_recording(profile, 810404).get("ok", false)),
		"Accelerate third-hit replay recording starts"
	)
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"Accelerate third-hit replay records its READY checkpoint"
	)
	suite.assert_true(await _drive_to_active(source, &"weapon_primary"), "Accelerate third primary reaches ACTIVE")
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"Accelerate third-hit replay records its pre-hit ACTIVE checkpoint"
	)
	var hp_before_recorded_hit := health.current_hp
	var result: Dictionary = _execute_live_hit(source, target)
	suite.assert_true(not result.is_empty(), "Accelerate third primary resolves through the real hit payload")
	suite.assert_equal(_owned_echo_count(source), 1, "Accelerate third hit creates one real owned echo payload")
	source.advance_action_frame()
	var terminal: Dictionary = source.weapon_replay_snapshot()
	suite.assert_true(
		bool(recorder.record_snapshot(terminal).get("ok", false)),
		"Accelerate third-hit replay records its echo checkpoint"
	)
	var events := _record_all_events(suite, source, recorder, "Accelerate third hit")
	var finish: Dictionary = recorder.finish_recording()
	suite.assert_true(bool(finish.get("ok", false)), "Accelerate third-hit replay finishes")
	var replay := finish.get("replay", {}) as Dictionary
	suite.assert_equal(_fact_count(events, "weapon_payload_result"), 1, "Accelerate third hit records one payload-result fact")
	var expected_hp := health.max_hp - (hp_before_recorded_hit - health.current_hp)
	await _free_player(source)
	_reset_target(target)

	var replay_target := await _replay_and_assert(
		suite,
		profile,
		replay,
		terminal,
		target,
		expected_hp,
		"Accelerate third hit"
	)
	if replay_target != null:
		suite.assert_equal(_owned_echo_count(replay_target), 1, "Accelerate replay materializes the owned echo payload")
		await _free_player(replay_target)
	await _free_target(target)


func _replay_and_assert(
	suite,
	profile: Dictionary,
	replay: Dictionary,
	expected_terminal: Dictionary,
	target: Node2D,
	expected_hp: float,
	label: String,
	disable_energy_regen: bool = false
) -> Node:
	if replay.is_empty():
		suite.assert_true(false, "%s produces a non-empty replay" % label)
		return null
	var replay_target := await _spawn_player(suite, profile)
	if replay_target == null:
		return null
	if disable_energy_regen:
		replay_target.time_manager.energy_regen = 0.0
	var player = ReplayPlayerScript.new()
	var loaded: Dictionary = player.load_replay(replay, profile)
	suite.assert_true(bool(loaded.get("ok", false)), "%s replay loads: %s" % [label, str(loaded)])
	if not bool(loaded.get("ok", false)):
		return replay_target
	var restored: Dictionary = player.restore_frame(replay_target, 1)
	suite.assert_true(bool(restored.get("ok", false)), "%s restores its ACTIVE checkpoint: %s" % [label, str(restored)])
	if bool(restored.get("ok", false)):
		_assert_next_fact_rejection_is_atomic(suite, replay_target, replay, target, label)
	var replayed: Dictionary = player.replay_to_terminal(replay_target, 1)
	suite.assert_true(bool(replayed.get("ok", false)), "%s replays to terminal: %s" % [label, str(replayed)])
	suite.assert_close(
		float((target.get_node("HealthComponent") as ReplayHealth).current_hp),
		expected_hp,
		"%s replay reproduces target HP" % label
	)
	var terminal_digest := ReplayRecorderScript.value_digest(expected_terminal)
	suite.assert_equal(
		ReplayRecorderScript.value_digest(replay_target.weapon_replay_snapshot()),
		terminal_digest,
		"%s replay reaches the source authoritative digest" % label
	)
	var hp_before_repeat := float((target.get_node("HealthComponent") as ReplayHealth).current_hp)
	var snapshot_before_repeat: Dictionary = replay_target.weapon_replay_snapshot()
	var events_before_repeat: Array[Dictionary] = replay_target.weapon_replay_events()
	var repeated: Dictionary = player.replay_to_terminal(replay_target, 1)
	suite.assert_true(bool(repeated.get("ok", false)), "%s repeated replay succeeds" % label)
	suite.assert_close(
		float((target.get_node("HealthComponent") as ReplayHealth).current_hp),
		hp_before_repeat,
		"%s repeated replay cannot duplicate damage" % label
	)
	suite.assert_equal(
		replay_target.weapon_replay_snapshot(),
		snapshot_before_repeat,
		"%s repeated replay preserves the terminal snapshot" % label
	)
	suite.assert_equal(
		replay_target.weapon_replay_events(),
		events_before_repeat,
		"%s repeated replay cannot duplicate the event prefix" % label
	)
	return replay_target


func _assert_stop_payload_smuggling_is_rejected(
	suite,
	profile: Dictionary,
	replay: Dictionary,
	target: Node2D
) -> void:
	var replay_target := await _spawn_player(suite, profile)
	if replay_target == null:
		return
	var replay_player = ReplayPlayerScript.new()
	var loaded: Dictionary = replay_player.load_replay(replay, profile)
	suite.assert_true(
		bool(loaded.get("ok", false)),
		"Stop payload-smuggling replay loads: %s" % str(loaded)
	)
	if not bool(loaded.get("ok", false)):
		await _free_player(replay_target)
		return
	var restored: Dictionary = replay_player.restore_frame(replay_target, 1)
	suite.assert_true(
		bool(restored.get("ok", false)),
		"Stop payload-smuggling fixture restores the ACTIVE checkpoint: %s" % str(restored)
	)
	if not bool(restored.get("ok", false)):
		await _free_player(replay_target)
		return
	var prefix_count := int(replay_target.weapon_replay_snapshot().get("event_prefix_count", 0))
	var replay_events := replay.get("events", []) as Array
	var payload_event: Dictionary = {}
	for event_index: int in range(prefix_count, replay_events.size()):
		var event_value: Variant = replay_events[event_index]
		if not event_value is Dictionary:
			continue
		var event := _normalized_replay_event(event_value as Dictionary)
		var event_payload := event.get("payload", {}) as Dictionary
		if (
			str(event.get("event_type", "")) == "external_fact"
			and str(event_payload.get("fact_type", "")) == "weapon_payload_result"
		):
			payload_event = event
			break
		suite.assert_true(
			replay_target.apply_weapon_replay_event(event),
			"Stop payload-smuggling fixture applies the genuine pre-payload event"
		)
	suite.assert_true(
		not payload_event.is_empty(),
		"Stop payload-smuggling fixture exposes the folded payload-result fact"
	)
	if payload_event.is_empty():
		await _free_player(replay_target)
		return

	var mutation_labels: Array[String] = [
		"extension frames",
		"remaining frames",
		"extension token",
		"Stop source sequence",
		"Stop source id",
		"rewind state",
	]
	for mutation_label: String in mutation_labels:
		var forged := payload_event.duplicate(true)
		var forged_data := (forged.get("payload", {}) as Dictionary).get("data", {}) as Dictionary
		var forged_after := forged_data.get("state_after", {}) as Dictionary
		var forged_time := forged_after.get("time_manager_state", {}) as Dictionary
		match mutation_label:
			"extension frames":
				forged_time["stop_extension_frames"] = int(
					forged_time.get("stop_extension_frames", 0)
				) + 1
			"remaining frames":
				forged_time["stop_remaining"] = float(
					forged_time.get("stop_remaining", 0.0)
				) + (1.0 / 60.0)
			"extension token":
				var tokens := (forged_time.get("stop_extension_tokens", {}) as Dictionary).duplicate(true)
				tokens[999999] = true
				forged_time["stop_extension_tokens"] = tokens
			"Stop source sequence":
				forged_time["stop_source_sequence"] = int(
					forged_time.get("stop_source_sequence", 0)
				) + 1
			"Stop source id":
				forged_time["stop_source_id"] = "%s:forged" % str(
					forged_time.get("stop_source_id", "")
				)
			"rewind state":
				forged_time["rewind_window_generation"] = int(
					forged_time.get("rewind_window_generation", 0)
				) + 1
		var validation := ReplayRecorderScript.validate_event(
			forged,
			ReplayRecorderScript.profile_identity(profile)
		)
		suite.assert_true(
			not validation.is_empty(),
			"Stop payload %s forgery remains structurally valid for transition-layer rejection" % mutation_label
		)
		var before_snapshot: Dictionary = replay_target.weapon_replay_snapshot()
		var before_events: Array[Dictionary] = replay_target.weapon_replay_events()
		var before_sequence := int(replay_target.get("_weapon_replay_capture_sequence"))
		var before_owned := int(replay_target.gauntlets_weapon.call("owned_payload_count_for_test"))
		var health: ReplayHealth = target.get_node("HealthComponent")
		var before_hp := health.current_hp
		suite.assert_true(
			not replay_target.apply_weapon_replay_event(forged),
			"Stop payload rejects smuggled %s" % mutation_label
		)
		suite.assert_equal(
			replay_target.weapon_replay_snapshot(),
			before_snapshot,
			"rejected Stop payload %s smuggling leaves Player state unchanged" % mutation_label
		)
		suite.assert_equal(
			replay_target.weapon_replay_events(),
			before_events,
			"rejected Stop payload %s smuggling leaves the event prefix unchanged" % mutation_label
		)
		suite.assert_equal(
			int(replay_target.get("_weapon_replay_capture_sequence")),
			before_sequence,
			"rejected Stop payload %s smuggling leaves capture sequence unchanged" % mutation_label
		)
		suite.assert_equal(
			int(replay_target.gauntlets_weapon.call("owned_payload_count_for_test")),
			before_owned,
			"rejected Stop payload %s smuggling creates no payload residual" % mutation_label
		)
		suite.assert_close(
			health.current_hp,
			before_hp,
			"rejected Stop payload %s smuggling leaves target HP unchanged" % mutation_label
		)
	await _free_player(replay_target)


func _assert_next_fact_rejection_is_atomic(
	suite,
	player: Node,
	replay: Dictionary,
	target: Node2D,
	label: String
) -> void:
	var current: Dictionary = player.weapon_replay_snapshot()
	var prefix_count := int(current.get("event_prefix_count", 0))
	var replay_events := replay.get("events", []) as Array
	var next_fact: Dictionary = {}
	for event_index: int in range(prefix_count, replay_events.size()):
		var event_value: Variant = replay_events[event_index]
		if not event_value is Dictionary:
			continue
		var event := (event_value as Dictionary).duplicate(true)
		if str(event.get("event_type", "")) != "external_fact":
			continue
		event.erase("digest")
		var data := (event.get("payload", {}) as Dictionary).get("data", {}) as Dictionary
		if not data.has("state_before_digest"):
			continue
		next_fact = event
		break
	suite.assert_true(not next_fact.is_empty(), "%s exposes a digest-guarded fact for rejection" % label)
	if next_fact.is_empty():
		return
	var data := (next_fact["payload"] as Dictionary)["data"] as Dictionary
	data["state_before_digest"] = "0000000000000000000000000000000000000000000000000000000000000000"
	var before_snapshot: Dictionary = player.weapon_replay_snapshot()
	var before_events: Array[Dictionary] = player.weapon_replay_events()
	var before_energy: Dictionary = player.time_manager.resource_state(&"time_energy")
	var before_owned := int(player.gauntlets_weapon.call("owned_payload_count_for_test"))
	var health: ReplayHealth = target.get_node("HealthComponent")
	var before_hp := health.current_hp
	var before_dead := health.dead
	var before_meta_present := target.has_meta(REPLAY_CLAIMS_META)
	var before_meta_value: Variant = target.get_meta(REPLAY_CLAIMS_META, {})
	var before_meta := (
		(before_meta_value as Dictionary).duplicate(true)
		if before_meta_value is Dictionary
		else {}
	)
	suite.assert_true(
		not bool(player.apply_weapon_replay_event(next_fact)),
		"%s rejects a forged pre-state digest" % label
	)
	suite.assert_equal(player.weapon_replay_snapshot(), before_snapshot, "%s rejection leaves Player state unchanged" % label)
	suite.assert_equal(player.weapon_replay_events(), before_events, "%s rejection leaves the event prefix unchanged" % label)
	suite.assert_equal(player.time_manager.resource_state(&"time_energy"), before_energy, "%s rejection leaves Energy unchanged" % label)
	suite.assert_equal(int(player.gauntlets_weapon.call("owned_payload_count_for_test")), before_owned, "%s rejection creates no payload residual" % label)
	suite.assert_close(health.current_hp, before_hp, "%s rejection leaves target HP unchanged" % label)
	suite.assert_equal(health.dead, before_dead, "%s rejection leaves target death state unchanged" % label)
	suite.assert_equal(target.has_meta(REPLAY_CLAIMS_META), before_meta_present, "%s rejection preserves claim metadata presence" % label)
	var after_meta_value: Variant = target.get_meta(REPLAY_CLAIMS_META, {})
	var after_meta := (
		(after_meta_value as Dictionary).duplicate(true)
		if after_meta_value is Dictionary
		else {}
	)
	suite.assert_equal(after_meta, before_meta, "%s rejection leaves claim metadata unchanged" % label)


func _finish_ready_replay(suite, source: Node, recorder, label: String) -> Dictionary:
	source.advance_action_frame()
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"%s records its post-fact checkpoint" % label
	)
	suite.assert_true(await _advance_to_ready(source), "%s source reaches READY" % label)
	var terminal: Dictionary = source.weapon_replay_snapshot()
	suite.assert_true(
		bool(recorder.record_snapshot(terminal).get("ok", false)),
		"%s records its READY terminal checkpoint" % label
	)
	var events := _record_all_events(suite, source, recorder, label)
	var finish: Dictionary = recorder.finish_recording()
	suite.assert_true(bool(finish.get("ok", false)), "%s replay finishes: %s" % [label, str(finish)])
	return {
		"terminal": terminal,
		"events": events,
		"replay": (finish.get("replay", {}) as Dictionary).duplicate(true),
	}


func _record_all_events(suite, source: Node, recorder, label: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = source.weapon_replay_events()
	for event: Dictionary in events:
		var recorded: Dictionary = recorder.record_event(event)
		suite.assert_true(bool(recorded.get("ok", false)), "%s records ordered event: %s" % [label, str(recorded)])
	return events


func _grant_combo_with_real_hits(player: Node, target: Node2D, hit_count: int) -> bool:
	for _index: int in range(hit_count):
		if not await _drive_to_active(player, &"weapon_primary"):
			return false
		if _execute_live_hit(player, target).is_empty():
			return false
		if not await _advance_to_ready(player):
			return false
		# The setup hits establish authentic Runtime/Adapter state, but they are
		# outside the replay segment under test. Bounding the discarded prefix
		# avoids quadratic prefix hashing while preserving the gameplay state.
		_reset_replay_capture(player)
	return true


func _drive_to_active(player: Node, semantic_action: StringName) -> bool:
	# Each helper invocation represents a fresh physical press after the prior
	# button-up edge. Reset only the input latch; gameplay state remains real.
	var router_value: Variant = player.get("_weapon_intent_router")
	if router_value is RefCounted and (router_value as RefCounted).has_method("reset_action"):
		(router_value as RefCounted).call("reset_action", semantic_action)
	player.advance_action_frame()
	if not player.try_action(semantic_action):
		return false
	if str(player.weapon_replay_snapshot().get("phase", "")) == "HOLD":
		if not bool(player.call("_submit_weapon_intent", semantic_action, &"released")):
			return false
	var guard := 512
	while str(player.weapon_replay_snapshot().get("phase", "")) != "ACTIVE" and guard > 0:
		player.advance_action_frame()
		guard -= 1
	return guard > 0


func _advance_to_ready(player: Node) -> bool:
	var guard := 1024
	while str(player.weapon_replay_snapshot().get("phase", "")) != "READY" and guard > 0:
		player.advance_action_frame()
		guard -= 1
	return guard > 0


func _execute_live_hit(player: Node, target: Node2D) -> Dictionary:
	var payload := _first_owned_payload(player, "hit")
	if payload == null or not payload.has_method("execute_target_for_test"):
		return {}
	return payload.call("execute_target_for_test", target) as Dictionary


func _first_owned_payload(player: Node, payload_type: String) -> Node:
	var payloads: Array[Node] = player.gauntlets_weapon.call("owned_payloads_for_test")
	for payload: Node in payloads:
		if not is_instance_valid(payload):
			continue
		var is_zone := payload.is_in_group("gauntlets_zones")
		if (payload_type == "zone" and is_zone) or (payload_type == "hit" and not is_zone):
			return payload
	return null


func _owned_echo_count(player: Node) -> int:
	var count := 0
	var payloads: Array[Node] = player.gauntlets_weapon.call("owned_payloads_for_test")
	for payload: Node in payloads:
		if not is_instance_valid(payload) or not payload.has_method("execution_snapshot"):
			continue
		var snapshot: Dictionary = payload.call("execution_snapshot")
		if bool(snapshot.get("is_echo", false)):
			count += 1
	return count


func _combo_count(player: Node) -> int:
	if player.weapon_runtime == null or not player.weapon_runtime.has_method("snapshot"):
		return -1
	return int((player.weapon_runtime.call("snapshot") as Dictionary).get("combo_count", -1))


func _reset_replay_capture(player: Node) -> void:
	var cleared_events: Array[Dictionary] = []
	player.set("_weapon_replay_events", cleared_events)
	player.set("_weapon_replay_capture_sequence", 0)
	player.call("_refresh_weapon_replay_fact_baseline")


func _set_time_energy(player: Node, current: float) -> void:
	var state: Dictionary = player.time_manager.resource_state(&"time_energy")
	state["current"] = current
	state["revision"] = int(state.get("revision", 0)) + 1
	player.time_manager.restore_resource_state(&"time_energy", state)
	player.call("_refresh_weapon_replay_fact_baseline")


func _fact_count(events: Array, fact_type: String) -> int:
	var count := 0
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event := event_value as Dictionary
		var payload := event.get("payload", {}) as Dictionary
		if str(event.get("event_type", "")) == "external_fact" and str(payload.get("fact_type", "")) == fact_type:
			count += 1
	return count


func _fact_event(events: Array, fact_type: String) -> Dictionary:
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event := event_value as Dictionary
		var payload := event.get("payload", {}) as Dictionary
		if (
			str(event.get("event_type", "")) == "external_fact"
			and str(payload.get("fact_type", "")) == fact_type
		):
			return event.duplicate(true)
	return {}


func _normalized_replay_event(event: Dictionary) -> Dictionary:
	var normalized := event.duplicate(true)
	normalized.erase("digest")
	return normalized


func _external_fact_types(events: Array) -> Array[String]:
	var result: Array[String] = []
	for event_value: Variant in events:
		if not event_value is Dictionary:
			continue
		var event := event_value as Dictionary
		if str(event.get("event_type", "")) != "external_fact":
			continue
		var payload := event.get("payload", {}) as Dictionary
		result.append(str(payload.get("fact_type", "")))
	return result


func _coordinator_time_energy_state(snapshot: Dictionary) -> Dictionary:
	var coordinator_value: Variant = snapshot.get("coordinator")
	if not coordinator_value is Dictionary:
		return {}
	var transaction_value: Variant = (coordinator_value as Dictionary).get(
		"resource_transaction"
	)
	if not transaction_value is Dictionary:
		return {}
	var accounts_value: Variant = (transaction_value as Dictionary).get("external_accounts")
	if not accounts_value is Dictionary:
		return {}
	var energy_value: Variant = (accounts_value as Dictionary).get("time_energy")
	return (
		(energy_value as Dictionary).duplicate(true)
		if energy_value is Dictionary
		else {}
	)


func _spawn_player(suite, profile: Dictionary) -> Node:
	var player := PlayerScene.instantiate()
	player.name = "ReplaySource"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var configured := bool(player.configure_loadout({
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "gauntlets",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 810000,
		"weapon_profile": profile.duplicate(true),
	}))
	suite.assert_true(configured, "Gauntlets external-fact variant fixture configures")
	if not configured:
		await _free_player(player)
		return null
	return player


func _spawn_target() -> Node2D:
	var target := Node2D.new()
	target.name = "ReplayTarget"
	target.add_to_group("enemies")
	var health := ReplayHealth.new()
	health.name = "HealthComponent"
	target.add_child(health)
	var hurtbox := HurtboxScript.new()
	hurtbox.name = "Hurtbox"
	hurtbox.health_component_path = NodePath("../HealthComponent")
	target.add_child(hurtbox)
	add_child(target)
	await get_tree().process_frame
	return target


func _reset_target(target: Node2D) -> void:
	var health: ReplayHealth = target.get_node("HealthComponent")
	health.current_hp = health.max_hp
	health.dead = false
	health.damage_signal_count = 0
	target.remove_meta(REPLAY_CLAIMS_META)


func _free_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.cancel_transient_actions()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _free_target(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _load_profile(suite) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	suite.assert_true(parsed is Array, "Gauntlets profile catalog parses for replay variants")
	if not parsed is Array:
		return {}
	for value: Variant in parsed:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == "gauntlets_launch_v1":
			return (value as Dictionary).duplicate(true)
	suite.assert_true(false, "gauntlets_launch_v1 exists for replay variants")
	return {}
