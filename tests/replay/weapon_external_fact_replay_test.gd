extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const HurtboxScript := preload("res://scripts/combat/hurtbox.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const ReplayPlayerScript := preload("res://scripts/replay/replay_player.gd")
const PlayerActionStateScript := preload("res://scripts/player/player_action_state.gd")

const PROFILE_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const REPLAY_CLAIMS_META := &"planewalker_replay_external_fact_claims"


class PartialMutationHealth extends Node:
	var max_hp: float = 1000.0
	var current_hp: float = 1000.0
	var dead: bool = false
	var damage_signal_count: int = 0
	var partial_mutation_calls: int = 0

	func take_damage(damage_info: RefCounted) -> float:
		if dead:
			return 0.0
		var applied := minf(current_hp, float(damage_info.get("amount")))
		current_hp = maxf(0.0, current_hp - applied)
		dead = current_hp <= 0.0
		damage_signal_count += 1
		EventBus.hit_confirmed.emit(damage_info, get_parent(), applied)
		return applied

	func lose_health(amount: float, _source: Variant = null) -> float:
		partial_mutation_calls += 1
		current_hp = maxf(0.0, current_hp - amount * 0.5)
		return 0.0


class ReplayStopProbe extends Node:
	var apply_calls: int = 0
	var clear_calls: int = 0

	func _ready() -> void:
		add_to_group("time_stoppable")

	func apply_time_stop_source(_source_id: StringName, _duration: float) -> void:
		apply_calls += 1

	func clear_time_stop_source(_source_id: StringName) -> void:
		clear_calls += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var sword_profile := _load_profile(suite, "sword_launch_v1")
	if not sword_profile.is_empty():
		await _test_sword_payload_replay(suite, sword_profile, &"weapon_skill", "zone", 0)
		await _test_sword_payload_replay(suite, sword_profile, &"weapon_ultimate", "wave", 60)
	var gun_profile := _load_profile(suite, "gun_launch_v1")
	if not gun_profile.is_empty():
		await _test_failed_gun_forward_restore_is_atomic(suite, gun_profile)
		await _test_record_time_external_fact_validation_is_atomic(suite, gun_profile)
		await _test_gun_cross_instance_target_claim(suite, gun_profile)
		await _test_time_external_facts(suite, gun_profile)
	var staff_profile := _load_profile(suite, "staff_launch_v1")
	if not staff_profile.is_empty():
		await _test_staff_payload_result(suite, staff_profile)
		await _test_staff_resource_reward(suite, staff_profile)
	var gauntlets_profile := _load_profile(suite, "gauntlets_launch_v1")
	if not gauntlets_profile.is_empty():
		await _test_gauntlets_payload_result(suite, gauntlets_profile)
	suite.finish(get_tree())


func _test_sword_payload_replay(
	suite,
	profile: Dictionary,
	semantic_action: StringName,
	payload_kind: String,
	hold_frames: int
) -> void:
	var target := await _spawn_target()
	var target_health: PartialMutationHealth = target.get_node("HealthComponent")
	var hurtbox := target.get_node("Hurtbox")

	var source := await _spawn_player(suite, profile, "sword")
	if source == null:
		target.queue_free()
		await get_tree().process_frame
		return
	var recorder = ReplayRecorderScript.new()
	suite.assert_true(bool(recorder.start_recording(profile, 515151).get("ok", false)), "%s replay recording starts" % payload_kind)
	var checkpoints: Array[Dictionary] = []
	var initial: Dictionary = source.weapon_replay_snapshot()
	checkpoints.append(initial)
	suite.assert_true(bool(recorder.record_snapshot(initial).get("ok", false)), "%s initial checkpoint records" % payload_kind)

	suite.assert_true(await _drive_to_active(source, semantic_action, hold_frames), "%s reaches ACTIVE" % payload_kind)
	var active_before_hit: Dictionary = source.weapon_replay_snapshot()
	checkpoints.append(active_before_hit)
	suite.assert_true(bool(recorder.record_snapshot(active_before_hit).get("ok", false)), "%s ACTIVE checkpoint records before hit" % payload_kind)
	var sword: Node = source.sword_weapon
	var payloads_before: Array = sword.call("launch_payload_snapshots_for_test")
	suite.assert_true(_has_payload_kind(payloads_before, payload_kind), "%s ACTIVE checkpoint owns a real %s node" % [payload_kind, payload_kind])
	var live_payloads_value: Variant = sword.get("_launch_payloads")
	var live_payloads: Array = live_payloads_value if live_payloads_value is Array else []
	suite.assert_true(not live_payloads.is_empty(), "%s adapter exposes one live payload state" % payload_kind)
	if live_payloads.is_empty():
		await _free_player(source)
		target.queue_free()
		await get_tree().process_frame
		return
	var payload_id := int((live_payloads[0] as Dictionary).get("id", 0))
	sword.call("_on_launch_payload_area_entered", hurtbox, payload_id)
	var source_hp_after := float(target_health.current_hp)
	var source_damage_signal_count := target_health.damage_signal_count
	suite.assert_true(source_hp_after < 1000.0, "%s deals real HealthComponent damage" % payload_kind)

	source.advance_action_frame()
	var after_hit: Dictionary = source.weapon_replay_snapshot()
	checkpoints.append(after_hit)
	suite.assert_true(bool(recorder.record_snapshot(after_hit).get("ok", false)), "%s post-hit checkpoint records" % payload_kind)
	var guard := 512
	while str(source.weapon_replay_snapshot().get("phase", "")) != "READY" and guard > 0:
		source.advance_action_frame()
		guard -= 1
	suite.assert_true(guard > 0, "%s source reaches terminal READY" % payload_kind)
	var terminal: Dictionary = source.weapon_replay_snapshot()
	checkpoints.append(terminal)
	suite.assert_true(bool(recorder.record_snapshot(terminal).get("ok", false)), "%s terminal checkpoint records" % payload_kind)

	var source_events: Array[Dictionary] = source.weapon_replay_events()
	var damage_fact_count := 0
	for event: Dictionary in source_events:
		if (
			str(event.get("event_type", "")) == "external_fact"
			and str((event.get("payload", {}) as Dictionary).get("fact_type", "")) == "combat_damage"
		):
			damage_fact_count += 1
		suite.assert_true(bool(recorder.record_event(event).get("ok", false)), "%s records ordered event %s" % [payload_kind, str(event)])
	suite.assert_equal(damage_fact_count, 1, "%s records one authoritative combat-damage fact" % payload_kind)
	var replay: Dictionary = recorder.finish_recording().get("replay", {})
	suite.assert_true(not replay.is_empty(), "%s replay finishes" % payload_kind)
	var expected_terminal_digest := ReplayRecorderScript.value_digest(terminal)
	var expected_payloads: Array = source.sword_weapon.call("launch_payload_snapshots_for_test")

	await _free_player(source)
	target_health.current_hp = 1000.0
	target_health.dead = false
	target.remove_meta(&"planewalker_replay_external_fact_claims")
	var replay_target := await _spawn_player(suite, profile, "sword")
	if replay_target == null:
		target.queue_free()
		await get_tree().process_frame
		return
	var player = ReplayPlayerScript.new()
	suite.assert_true(bool(player.load_replay(replay, profile).get("ok", false)), "%s external-fact replay loads" % payload_kind)
	var restored: Dictionary = player.restore_frame(replay_target, 1)
	suite.assert_true(bool(restored.get("ok", false)), "%s restores pre-hit ACTIVE checkpoint" % payload_kind)
	suite.assert_true(
		_has_payload_kind(replay_target.sword_weapon.call("launch_payload_snapshots_for_test"), payload_kind),
		"%s restore recreates the real payload node" % payload_kind
	)
	var replayed: Dictionary = player.replay_to_terminal(replay_target, 1)
	suite.assert_true(bool(replayed.get("ok", false)), "%s replays from pre-hit ACTIVE checkpoint" % payload_kind)
	suite.assert_close(float(target_health.current_hp), source_hp_after, "%s replay reproduces target HP exactly" % payload_kind)
	suite.assert_equal(target_health.damage_signal_count, source_damage_signal_count, "%s replay does not republish resolved damage signals" % payload_kind)
	suite.assert_equal(target_health.partial_mutation_calls, 0, "%s replay never calls a partially-mutating lose_health provider" % payload_kind)
	suite.assert_equal(
		ReplayRecorderScript.value_digest(replay_target.weapon_replay_snapshot()),
		expected_terminal_digest,
		"%s replay reaches the source terminal authoritative digest" % payload_kind
	)
	suite.assert_equal(
		replay_target.sword_weapon.call("launch_payload_snapshots_for_test"),
		expected_payloads,
		"%s replay preserves terminal payload nodes and stable hit claims" % payload_kind
	)
	var hp_before_repeat := float(target_health.current_hp)
	var repeated: Dictionary = player.replay_to_terminal(replay_target, 1)
	suite.assert_true(bool(repeated.get("ok", false)), "%s repeated replay succeeds" % payload_kind)
	suite.assert_close(float(target_health.current_hp), hp_before_repeat, "%s repeated replay cannot duplicate damage" % payload_kind)
	suite.assert_equal(target_health.damage_signal_count, source_damage_signal_count, "%s repeated replay emits no duplicate damage signal" % payload_kind)
	suite.assert_equal(target_health.partial_mutation_calls, 0, "%s repeated replay still avoids the partial mutation provider" % payload_kind)
	suite.assert_equal(
		ReplayRecorderScript.value_digest(replay_target.weapon_replay_snapshot()),
		expected_terminal_digest,
		"%s repeated replay preserves the same terminal digest" % payload_kind
	)

	await _free_player(replay_target)
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_failed_gun_forward_restore_is_atomic(suite, profile: Dictionary) -> void:
	var source := await _spawn_player(suite, profile, "gun")
	if source == null:
		return
	suite.assert_true(
		await _drive_to_active(source, &"weapon_primary", 18),
		"Gun forward-restore fixture reaches ACTIVE"
	)
	var forged_checkpoint: Dictionary = source.weapon_replay_snapshot()
	forged_checkpoint["coordinator"]["runtime"]["ammo"] = -1
	await _free_player(source)

	var target := await _spawn_player(suite, profile, "gun")
	if target == null:
		return
	var before: Dictionary = target.weapon_replay_snapshot()
	var before_events: Array[Dictionary] = target.weapon_replay_events()
	var before_payloads: Array[Node] = target.gun_weapon.call("owned_projectiles_for_test")
	suite.assert_true(
		not target.restore_weapon_replay_snapshot(forged_checkpoint),
		"Gun restore rejects a runtime-invalid forward checkpoint"
	)
	suite.assert_equal(
		target.weapon_replay_snapshot(),
		before,
		"failed Gun forward restore leaves the complete Player snapshot unchanged"
	)
	suite.assert_equal(
		target.weapon_replay_events(),
		before_events,
		"failed Gun forward restore leaves the event log unchanged"
	)
	suite.assert_equal(
		(target.gun_weapon.call("owned_projectiles_for_test") as Array).size(),
		before_payloads.size(),
		"failed Gun forward restore creates no residual projectile"
	)
	await _free_player(target)


func _test_record_time_external_fact_validation_is_atomic(
	suite,
	profile: Dictionary
) -> void:
	var target := await _spawn_target()
	var source := await _spawn_player(suite, profile, "gun")
	if source == null:
		target.queue_free()
		await get_tree().process_frame
		return
	_set_time_energy(source, 40.0)
	suite.assert_true(
		await _drive_to_active(source, &"weapon_primary", 18),
		"record-time projector fixture reaches Gun ACTIVE"
	)
	_reset_replay_capture(source)
	var state_before_reward: Dictionary = source.weapon_replay_snapshot()
	var action_token := int(state_before_reward.get("token", 0))
	var action_generation := int(state_before_reward.get("generation", 0))
	suite.assert_true(
		action_token > 0 and action_generation > 0,
		"record-time projector fixture exposes an authoritative action identity"
	)

	source.gun_weapon.resource_reward_requested.emit(
		action_token,
		&"time_energy",
		5.0
	)
	var genuine_reward_event := _fact_event(
		source.weapon_replay_events(),
		"weapon_resource_reward"
	)
	suite.assert_true(
		not genuine_reward_event.is_empty(),
		"record-time projector fixture records one genuine state fact"
	)
	if genuine_reward_event.is_empty():
		await _free_player(source)
		target.queue_free()
		await get_tree().process_frame
		return
	var genuine_reward_payload := genuine_reward_event.get("payload", {}) as Dictionary
	var genuine_reward_data := genuine_reward_payload.get("data", {}) as Dictionary
	suite.assert_true(
		source.restore_weapon_replay_snapshot(state_before_reward),
		"record-time projector fixture restores the genuine fact pre-state"
	)
	suite.assert_true(
		source.apply_weapon_replay_event(genuine_reward_event),
		"a legally recorded state fact is accepted by the replay projector"
	)
	suite.assert_equal(
		_fact_event(source.weapon_replay_events(), "weapon_resource_reward"),
		genuine_reward_event,
		"recording and replay preserve the same legal external fact"
	)
	suite.assert_true(
		source.restore_weapon_replay_snapshot(state_before_reward),
		"record-time projector fixture restores the pre-state after parity proof"
	)

	_assert_rejected_record_fact_is_atomic(
		suite,
		source,
		"weapon_resource_reward",
		action_token,
		action_generation + 1,
		genuine_reward_data.duplicate(true),
		"record-time state fact rejects a mismatched action generation"
	)

	var target_path := str(source.get_path_to(target))
	_assert_rejected_record_fact_is_atomic(
		suite,
		source,
		"combat_damage",
		action_token,
		action_generation,
		{
			"target_path": target_path,
			"health_path": "HealthComponent",
			"hp_before": 1000.0,
			"hp_after": 1000.0,
			"resolved_damage": 0.0,
			"target_dead_after": false,
			"state_after": state_before_reward.duplicate(true),
		},
		"record-time projector rejects malformed no-op combat damage"
	)

	var forged_hit_after := state_before_reward.duplicate(true)
	var forged_hit_player := forged_hit_after.get("player_weapon_state", {}) as Dictionary
	var forged_hit_claims := forged_hit_player.get("hit_fact_claims", {}) as Dictionary
	forged_hit_claims[action_token] = true
	forged_hit_player["combo_timeout_frames"] = int(
		forged_hit_player.get("combo_timeout_frames", 0)
	) + 1
	_assert_rejected_record_fact_is_atomic(
		suite,
		source,
		"weapon_hit_claim",
		action_token,
		action_generation,
		{
			"target_path": target_path,
			"state_before_digest": ReplayRecorderScript.value_digest(
				state_before_reward
			),
			"state_after": forged_hit_after,
		},
		"record-time projector rejects a forged weapon-hit claim transition"
	)

	var time_before: Dictionary = source.time_manager.weapon_replay_snapshot()
	_assert_rejected_record_fact_is_atomic(
		suite,
		source,
		"time_interaction_claim",
		action_token,
		action_generation,
		{
			"interaction_id": "bow_rewind_echo",
			"generation": 7,
			"state_before": time_before.duplicate(true),
			"state_after": time_before.duplicate(true),
		},
		"record-time projector rejects a no-op rewind interaction claim"
	)
	_assert_rejected_record_fact_is_atomic(
		suite,
		source,
		"time_stop_extension",
		action_token,
		action_generation,
		{
			"extension_frames": 30,
			"state_before": time_before.duplicate(true),
			"state_after": time_before.duplicate(true),
		},
		"record-time projector rejects an inactive no-op Time Stop extension"
	)

	await _free_player(source)
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_gun_cross_instance_target_claim(suite, profile: Dictionary) -> void:
	var source_target := await _spawn_target()
	var source_health: PartialMutationHealth = source_target.get_node("HealthComponent")
	var source_target_instance := source_target.get_instance_id()
	var source := await _spawn_player(suite, profile, "gun")
	if source == null:
		source_target.queue_free()
		await get_tree().process_frame
		return
	var recorder = ReplayRecorderScript.new()
	_set_time_energy(source, 40.0)
	recorder.start_recording(profile, 616161)
	recorder.record_snapshot(source.weapon_replay_snapshot())
	suite.assert_true(await _drive_to_active(source, &"weapon_primary", 18), "Gun aimed shot reaches ACTIVE")
	var active_before_hit: Dictionary = source.weapon_replay_snapshot()
	suite.assert_true(bool(recorder.record_snapshot(active_before_hit).get("ok", false)), "Gun ACTIVE checkpoint records before hit")
	var projectiles: Array[Node] = source.gun_weapon.call("owned_projectiles_for_test")
	suite.assert_true(not projectiles.is_empty(), "Gun ACTIVE owns a real projectile")
	if projectiles.is_empty():
		await _free_player(source)
		source_target.queue_free()
		await get_tree().process_frame
		return
	projectiles[0].call("_on_area_entered", source_target.get_node("Hurtbox"))
	var action_token := int(active_before_hit.get("token", 0))
	source.gun_weapon.resource_reward_requested.emit(action_token, &"time_energy", 5.0)
	var source_hp_after := source_health.current_hp
	var source_energy_after := float(source.time_manager.energy)
	suite.assert_close(source_energy_after, 45.0, "Gun source applies one external time-energy reward")
	source.advance_action_frame()
	recorder.record_snapshot(source.weapon_replay_snapshot())
	var guard := 512
	while str(source.weapon_replay_snapshot().get("phase", "")) != "READY" and guard > 0:
		source.advance_action_frame()
		guard -= 1
	var source_terminal: Dictionary = source.weapon_replay_snapshot()
	recorder.record_snapshot(source_terminal)
	var resource_fact_count := 0
	var pre_reward_events: Array[Dictionary] = []
	var reward_event: Dictionary = {}
	for event: Dictionary in source.weapon_replay_events():
		var payload := event.get("payload", {}) as Dictionary
		var fact_type := str(payload.get("fact_type", ""))
		if fact_type in ["combat_damage", "weapon_hit_claim"]:
			pre_reward_events.append(event.duplicate(true))
		if (
			str(event.get("event_type", "")) == "external_fact"
			and fact_type == "weapon_resource_reward"
		):
			resource_fact_count += 1
			reward_event = event.duplicate(true)
			var tampered_reward := event.duplicate(true)
			tampered_reward["payload"]["data"]["energy_after"] = float(
				tampered_reward["payload"]["data"]["energy_after"]
			) - 1.0
			suite.assert_true(
				ReplayRecorderScript.validate_event(
					tampered_reward,
					ReplayRecorderScript.profile_identity(profile)
				).is_empty(),
				"Gun reward metadata cannot drift from authoritative time-energy state"
			)
		suite.assert_true(bool(recorder.record_event(event).get("ok", false)), "Gun records ordered replay event")
	suite.assert_equal(resource_fact_count, 1, "Gun records one authoritative resource reward fact")
	suite.assert_true(not pre_reward_events.is_empty(), "Gun records ordered damage/hit prerequisites before its reward")
	suite.assert_true(not reward_event.is_empty(), "Gun exposes the authoritative reward event for CAS regression")
	var replay: Dictionary = recorder.finish_recording().get("replay", {})
	var expected_terminal_digest := ReplayRecorderScript.value_digest(source_terminal)
	var damage_event := _fact_event(pre_reward_events, "combat_damage")
	await _free_player(source)
	source_target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var dash_target_entity := await _spawn_target()
	var dash_replay_target := await _spawn_player(suite, profile, "gun")
	var dash_stop_probe := ReplayStopProbe.new()
	add_child(dash_stop_probe)
	await get_tree().process_frame
	if dash_replay_target != null and not damage_event.is_empty():
		var dash_player = ReplayPlayerScript.new()
		suite.assert_true(
			bool(dash_player.load_replay(replay, profile).get("ok", false)),
			"Gun already-resolved damage fixture loads"
		)
		suite.assert_true(
			bool(dash_player.restore_frame(dash_replay_target, 1).get("ok", false)),
			"Gun already-resolved damage fixture restores ACTIVE checkpoint"
		)
		var damage_data := (damage_event.get("payload", {}) as Dictionary).get(
			"data",
			{}
		) as Dictionary
		var dash_health: PartialMutationHealth = dash_target_entity.get_node("HealthComponent")
		dash_health.current_hp = float(damage_data.get("hp_after", dash_health.current_hp))
		dash_health.dead = bool(damage_data.get("target_dead_after", false))
		dash_target_entity.remove_meta(REPLAY_CLAIMS_META)
		suite.assert_true(
			dash_replay_target.action_state.force_safe_reset(),
			"Gun already-resolved damage fixture clears the weapon projection"
		)
		suite.assert_true(
			dash_replay_target.action_state.transition_to(
				PlayerActionStateScript.State.DASH,
				2
			),
			"Gun already-resolved damage fixture enters Dash"
		)
		_assert_rejected_external_fact_is_atomic(
			suite,
			dash_replay_target,
			damage_event,
			dash_target_entity,
			dash_stop_probe,
			"already-resolved combat damage rejects a failed Dash-state restore"
		)
		suite.assert_true(
			not dash_target_entity.has_meta(REPLAY_CLAIMS_META),
			"failed already-resolved damage leaves no claim metadata"
		)
		suite.assert_equal(
			dash_target_entity.get_meta(REPLAY_CLAIMS_META, {}),
			{},
			"failed already-resolved damage leaves zero claim entries"
		)
		dash_replay_target.action_state.force_safe_reset()
		await _free_player(dash_replay_target)
	dash_target_entity.queue_free()
	dash_stop_probe.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var cas_target_entity := await _spawn_target()
	var cas_replay_target := await _spawn_player(suite, profile, "gun")
	var reward_stop_probe := ReplayStopProbe.new()
	add_child(reward_stop_probe)
	await get_tree().process_frame
	if cas_replay_target != null:
		var cas_player = ReplayPlayerScript.new()
		suite.assert_true(bool(cas_player.load_replay(replay, profile).get("ok", false)), "Gun forged-reward fixture loads")
		suite.assert_true(bool(cas_player.restore_frame(cas_replay_target, 1).get("ok", false)), "Gun forged-reward fixture restores ACTIVE checkpoint")
		for prerequisite_event: Dictionary in pre_reward_events:
			suite.assert_true(
				cas_replay_target.apply_weapon_replay_event(prerequisite_event),
				"Gun forged-reward fixture applies ordered %s prerequisite" % str(
					(prerequisite_event.get("payload", {}) as Dictionary).get("fact_type", "")
				)
			)
		var reward_data := (reward_event.get("payload", {}) as Dictionary).get("data", {}) as Dictionary
		suite.assert_equal(
			ReplayRecorderScript.value_digest(cas_replay_target.weapon_replay_snapshot()),
			str(reward_data.get("state_before_digest", "")),
			"Gun forged-reward fixture reaches the exact authoritative reward pre-state"
		)
		_assert_current_prestate_drift_is_rejected(
			suite,
			cas_replay_target,
			reward_event,
			cas_target_entity,
			reward_stop_probe,
			"Gun resource reward rejects current pre-state combo drift"
		)
		var missing_reward_digest := reward_event.duplicate(true)
		((missing_reward_digest["payload"] as Dictionary)["data"] as Dictionary).erase(
			"state_before_digest"
		)
		suite.assert_true(
			ReplayRecorderScript.validate_event(
				missing_reward_digest,
				ReplayRecorderScript.profile_identity(profile)
			).is_empty(),
			"Gun resource reward requires a state_before_digest"
		)
		_assert_rejected_external_fact_is_atomic(
			suite,
			cas_replay_target,
			missing_reward_digest,
			cas_target_entity,
			reward_stop_probe,
			"Gun resource reward without state_before_digest is rejected"
		)
		var forged_reward := reward_event.duplicate(true)
		var forged_payload := forged_reward["payload"] as Dictionary
		var forged_data := forged_payload["data"] as Dictionary
		var forged_revision := int(forged_data.get("energy_revision_before", 0)) + 10
		forged_data["energy_revision_before"] = forged_revision
		var forged_after := forged_data["state_after"] as Dictionary
		var forged_time_state := forged_after["time_manager_state"] as Dictionary
		var forged_time_energy := forged_time_state["time_energy_state"] as Dictionary
		forged_time_energy["revision"] = forged_revision + 1
		var forged_coordinator := forged_after["coordinator"] as Dictionary
		var forged_transaction := forged_coordinator["resource_transaction"] as Dictionary
		var forged_accounts := forged_transaction["external_accounts"] as Dictionary
		var forged_coordinator_energy := forged_accounts["time_energy"] as Dictionary
		forged_coordinator_energy["revision"] = forged_revision + 1
		suite.assert_true(
			not ReplayRecorderScript.validate_event(
				forged_reward,
				ReplayRecorderScript.profile_identity(profile)
			).is_empty(),
			"Gun forged reward remains structurally self-consistent after its revision jump"
		)
		var cas_before_reject: Dictionary = cas_replay_target.weapon_replay_snapshot()
		suite.assert_true(
			not cas_replay_target.apply_weapon_replay_event(forged_reward),
			"Gun reward CAS rejects an arbitrary but self-consistent revision jump"
		)
		suite.assert_equal(
			cas_replay_target.weapon_replay_snapshot(),
			cas_before_reject,
			"Gun rejected forged reward leaves the complete Player snapshot unchanged"
		)
		var stop_smuggling_reward := reward_event.duplicate(true)
		var stop_reward_data := (stop_smuggling_reward["payload"] as Dictionary)["data"] as Dictionary
		var stop_reward_after := stop_reward_data["state_after"] as Dictionary
		var stop_reward_time := stop_reward_after["time_manager_state"] as Dictionary
		stop_reward_time["stop_active"] = true
		stop_reward_time["stop_source_sequence"] = 78
		stop_reward_time["stop_source_id"] = "forged:78"
		stop_reward_time["stop_remaining"] = 5.0
		suite.assert_true(
			not ReplayRecorderScript.validate_event(
				stop_smuggling_reward,
				ReplayRecorderScript.profile_identity(profile)
			).is_empty(),
			"Gun reward with non-Energy TimeManager smuggling remains structurally valid"
		)
		_assert_rejected_external_fact_is_atomic(
			suite,
			cas_replay_target,
			stop_smuggling_reward,
			cas_target_entity,
			reward_stop_probe,
			"Gun resource reward rejects non-Energy TimeManager smuggling"
		)
		var coordinator_smuggling_reward := reward_event.duplicate(true)
		var coordinator_reward_data := (
			(coordinator_smuggling_reward["payload"] as Dictionary)["data"] as Dictionary
		)
		var coordinator_reward_after := coordinator_reward_data["state_after"] as Dictionary
		var forged_reward_coordinator := coordinator_reward_after["coordinator"] as Dictionary
		forged_reward_coordinator["phase_frame"] = int(
			forged_reward_coordinator.get("phase_frame", 0)
		) + 1
		suite.assert_true(
			not ReplayRecorderScript.validate_event(
				coordinator_smuggling_reward,
				ReplayRecorderScript.profile_identity(profile)
			).is_empty(),
			"Gun reward with a different valid coordinator phase remains structurally valid"
		)
		_assert_rejected_external_fact_is_atomic(
			suite,
			cas_replay_target,
			coordinator_smuggling_reward,
			cas_target_entity,
			reward_stop_probe,
			"Gun resource reward rejects coordinator state smuggling"
		)
		var runtime_smuggling_reward := reward_event.duplicate(true)
		var runtime_reward_data := (
			(runtime_smuggling_reward["payload"] as Dictionary)["data"] as Dictionary
		)
		var runtime_reward_after := runtime_reward_data["state_after"] as Dictionary
		var runtime_reward_coordinator := runtime_reward_after["coordinator"] as Dictionary
		var reward_runtime := runtime_reward_coordinator["runtime"] as Dictionary
		var reward_ammo := int(reward_runtime.get("ammo", 0))
		reward_runtime["ammo"] = reward_ammo - 1 if reward_ammo > 0 else reward_ammo + 1
		suite.assert_true(
			not ReplayRecorderScript.validate_event(
				runtime_smuggling_reward,
				ReplayRecorderScript.profile_identity(profile)
			).is_empty(),
			"Gun reward with a different valid runtime ammo remains structurally valid"
		)
		_assert_rejected_external_fact_is_atomic(
			suite,
			cas_replay_target,
			runtime_smuggling_reward,
			cas_target_entity,
			reward_stop_probe,
			"Gun resource reward rejects runtime state smuggling"
		)
		var extra_claim_reward := reward_event.duplicate(true)
		var extra_claim_reward_data := (
			(extra_claim_reward["payload"] as Dictionary)["data"] as Dictionary
		)
		var extra_claim_reward_after := extra_claim_reward_data["state_after"] as Dictionary
		var extra_claim_reward_player := (
			extra_claim_reward_after["player_weapon_state"] as Dictionary
		)
		var extra_claim_reward_claims := (
			extra_claim_reward_player["action_reward_claims"] as Dictionary
		)
		var extra_claim_reward_token := int(
			(extra_claim_reward["payload"] as Dictionary)["action_token"]
		)
		extra_claim_reward_claims[
			"%d:unrelated_reward" % extra_claim_reward_token
		] = true
		suite.assert_true(
			not ReplayRecorderScript.validate_event(
				extra_claim_reward,
				ReplayRecorderScript.profile_identity(profile)
			).is_empty(),
			"Gun reward with its legal claim plus an unrelated claim remains structurally valid"
		)
		_assert_rejected_external_fact_is_atomic(
			suite,
			cas_replay_target,
			extra_claim_reward,
			cas_target_entity,
			reward_stop_probe,
			"Gun resource reward rejects an extra unrelated reward claim"
		)
		await _free_player(cas_replay_target)
	cas_target_entity.queue_free()
	reward_stop_probe.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var smuggle_target_entity := await _spawn_target()
	var smuggle_replay_target := await _spawn_player(suite, profile, "gun")
	var stop_probe := ReplayStopProbe.new()
	add_child(stop_probe)
	await get_tree().process_frame
	if smuggle_replay_target != null:
		var smuggle_player = ReplayPlayerScript.new()
		suite.assert_true(bool(smuggle_player.load_replay(replay, profile).get("ok", false)), "Gun hit-claim smuggling fixture loads")
		suite.assert_true(bool(smuggle_player.restore_frame(smuggle_replay_target, 1).get("ok", false)), "Gun hit-claim smuggling fixture restores ACTIVE checkpoint")
		var forged_hit_claim: Dictionary = {}
		for prerequisite_event: Dictionary in pre_reward_events:
			var prerequisite_payload := prerequisite_event.get("payload", {}) as Dictionary
			if str(prerequisite_payload.get("fact_type", "")) == "weapon_hit_claim":
				forged_hit_claim = prerequisite_event.duplicate(true)
				break
			_assert_current_prestate_drift_is_rejected(
				suite,
				smuggle_replay_target,
				prerequisite_event,
				smuggle_target_entity,
				stop_probe,
				"combat damage rejects current pre-state combo drift"
			)
			var forged_damage := prerequisite_event.duplicate(true)
			var forged_damage_data := (forged_damage["payload"] as Dictionary)["data"] as Dictionary
			var missing_damage_digest := prerequisite_event.duplicate(true)
			((missing_damage_digest["payload"] as Dictionary)["data"] as Dictionary).erase(
				"state_before_digest"
			)
			suite.assert_true(
				ReplayRecorderScript.validate_event(
					missing_damage_digest,
					ReplayRecorderScript.profile_identity(profile)
				).is_empty(),
				"combat damage requires a state_before_digest"
			)
			_assert_rejected_external_fact_is_atomic(
				suite,
				smuggle_replay_target,
				missing_damage_digest,
				smuggle_target_entity,
				stop_probe,
				"combat damage without state_before_digest is rejected"
			)
			var forged_damage_after := forged_damage_data["state_after"] as Dictionary
			var forged_damage_time := forged_damage_after["time_manager_state"] as Dictionary
			forged_damage_time["stop_active"] = true
			forged_damage_time["stop_source_sequence"] = 79
			forged_damage_time["stop_source_id"] = "forged:79"
			forged_damage_time["stop_remaining"] = 5.0
			suite.assert_true(
				not ReplayRecorderScript.validate_event(
					forged_damage,
					ReplayRecorderScript.profile_identity(profile)
				).is_empty(),
				"combat damage with TimeManager smuggling remains structurally valid"
			)
			_assert_rejected_external_fact_is_atomic(
				suite,
				smuggle_replay_target,
				forged_damage,
				smuggle_target_entity,
				stop_probe,
				"combat damage rejects TimeManager smuggling"
			)
			var player_smuggling_damage := prerequisite_event.duplicate(true)
			var player_damage_data := (
				(player_smuggling_damage["payload"] as Dictionary)["data"] as Dictionary
			)
			var player_damage_after := player_damage_data["state_after"] as Dictionary
			var player_damage_state := player_damage_after["player_weapon_state"] as Dictionary
			player_damage_state["combo_timeout_frames"] = int(
				player_damage_state.get("combo_timeout_frames", 0)
			) + 1
			suite.assert_true(
				not ReplayRecorderScript.validate_event(
					player_smuggling_damage,
					ReplayRecorderScript.profile_identity(profile)
				).is_empty(),
				"combat damage with a different valid combo timeout remains structurally valid"
			)
			_assert_rejected_external_fact_is_atomic(
				suite,
				smuggle_replay_target,
				player_smuggling_damage,
				smuggle_target_entity,
				stop_probe,
				"combat damage rejects Player state smuggling"
			)
			var runtime_smuggling_damage := prerequisite_event.duplicate(true)
			var runtime_damage_data := (
				(runtime_smuggling_damage["payload"] as Dictionary)["data"] as Dictionary
			)
			var runtime_damage_after := runtime_damage_data["state_after"] as Dictionary
			var runtime_damage_coordinator := runtime_damage_after["coordinator"] as Dictionary
			var damage_runtime := runtime_damage_coordinator["runtime"] as Dictionary
			var damage_ammo := int(damage_runtime.get("ammo", 0))
			damage_runtime["ammo"] = damage_ammo - 1 if damage_ammo > 0 else damage_ammo + 1
			suite.assert_true(
				not ReplayRecorderScript.validate_event(
					runtime_smuggling_damage,
					ReplayRecorderScript.profile_identity(profile)
				).is_empty(),
				"combat damage with a different valid runtime ammo remains structurally valid"
			)
			_assert_rejected_external_fact_is_atomic(
				suite,
				smuggle_replay_target,
				runtime_smuggling_damage,
				smuggle_target_entity,
				stop_probe,
				"combat damage rejects runtime state smuggling"
			)
			suite.assert_true(
				smuggle_replay_target.apply_weapon_replay_event(prerequisite_event),
				"Gun hit-claim smuggling fixture applies its damage prerequisite"
			)
		suite.assert_true(not forged_hit_claim.is_empty(), "Gun exposes a hit claim for state-smuggling regression")
		if not forged_hit_claim.is_empty():
			var missing_digest_claim := forged_hit_claim.duplicate(true)
			((missing_digest_claim["payload"] as Dictionary)["data"] as Dictionary).erase(
				"state_before_digest"
			)
			suite.assert_true(
				ReplayRecorderScript.validate_event(
					missing_digest_claim,
					ReplayRecorderScript.profile_identity(profile)
				).is_empty(),
				"Gun hit claim requires a state_before_digest"
			)
			_assert_rejected_external_fact_is_atomic(
				suite,
				smuggle_replay_target,
				missing_digest_claim,
				smuggle_target_entity,
				stop_probe,
				"Gun hit claim without state_before_digest is rejected"
			)

			var extra_diff_claim := forged_hit_claim.duplicate(true)
			var extra_diff_data := (extra_diff_claim["payload"] as Dictionary)["data"] as Dictionary
			var extra_diff_after := extra_diff_data["state_after"] as Dictionary
			var extra_diff_player := extra_diff_after["player_weapon_state"] as Dictionary
			var extra_reward_claims := extra_diff_player["action_reward_claims"] as Dictionary
			extra_reward_claims["%d:forged" % int((extra_diff_claim["payload"] as Dictionary)["action_token"])] = true
			suite.assert_true(
				not ReplayRecorderScript.validate_event(
					extra_diff_claim,
					ReplayRecorderScript.profile_identity(profile)
				).is_empty(),
				"Gun hit claim with an extra valid player claim remains structurally valid"
			)
			_assert_rejected_external_fact_is_atomic(
				suite,
				smuggle_replay_target,
				extra_diff_claim,
				smuggle_target_entity,
				stop_probe,
				"Gun hit claim allows only its target hit_fact_claims transition"
			)

			var forged_hit_payload := forged_hit_claim["payload"] as Dictionary
			var forged_hit_data := forged_hit_payload["data"] as Dictionary
			var forged_hit_after := forged_hit_data["state_after"] as Dictionary
			var forged_hit_time := forged_hit_after["time_manager_state"] as Dictionary
			forged_hit_time["stop_active"] = true
			forged_hit_time["stop_source_sequence"] = 77
			forged_hit_time["stop_source_id"] = "forged:77"
			forged_hit_time["stop_remaining"] = 5.0
			suite.assert_true(
				not ReplayRecorderScript.validate_event(
					forged_hit_claim,
					ReplayRecorderScript.profile_identity(profile)
				).is_empty(),
				"forged Gun hit claim remains structurally self-consistent"
			)
			_assert_rejected_external_fact_is_atomic(
				suite,
				smuggle_replay_target,
				forged_hit_claim,
				smuggle_target_entity,
				stop_probe,
				"Gun hit claim rejects a smuggled Time Stop transition"
			)
		await _free_player(smuggle_replay_target)
	smuggle_target_entity.queue_free()
	stop_probe.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var replay_target_entity := await _spawn_target()
	var replay_health: PartialMutationHealth = replay_target_entity.get_node("HealthComponent")
	suite.assert_true(replay_target_entity.get_instance_id() != source_target_instance, "Gun replay target uses a different Godot instance ID")
	var replay_target := await _spawn_player(suite, profile, "gun")
	if replay_target == null:
		replay_target_entity.queue_free()
		await get_tree().process_frame
		return
	var player = ReplayPlayerScript.new()
	suite.assert_true(bool(player.load_replay(replay, profile).get("ok", false)), "Gun cross-instance replay loads")
	suite.assert_true(bool(player.restore_frame(replay_target, 1).get("ok", false)), "Gun restores pre-hit ACTIVE checkpoint")
	var gun_replay_result: Dictionary = player.replay_to_terminal(replay_target, 1)
	suite.assert_true(bool(gun_replay_result.get("ok", false)), "Gun replays external hit into a new target instance: %s" % str(gun_replay_result))
	suite.assert_close(replay_health.current_hp, source_hp_after, "Gun cross-instance replay reproduces HP")
	suite.assert_close(float(replay_target.time_manager.energy), source_energy_after, "Gun replay reproduces the resource reward")
	suite.assert_equal(
		ReplayRecorderScript.value_digest(replay_target.weapon_replay_snapshot()),
		expected_terminal_digest,
		"Gun cross-instance replay reaches the source terminal digest"
	)
	var restored_projectiles: Array[Node] = replay_target.gun_weapon.call("owned_projectiles_for_test")
	var hp_before_duplicate_collision := replay_health.current_hp
	for projectile: Node in restored_projectiles:
		projectile.call("_on_area_entered", replay_target_entity.get_node("Hurtbox"))
	suite.assert_close(replay_health.current_hp, hp_before_duplicate_collision, "restored Gun projectile stable claim blocks a new-instance duplicate hit")
	suite.assert_equal(replay_health.damage_signal_count, 0, "Gun replay and duplicate collision publish no duplicate damage signal")
	var energy_before_repeat := float(replay_target.time_manager.energy)
	var hp_before_repeat := replay_health.current_hp
	suite.assert_true(bool(player.replay_to_terminal(replay_target, 1).get("ok", false)), "Gun repeated external-fact replay succeeds")
	suite.assert_close(float(replay_target.time_manager.energy), energy_before_repeat, "Gun repeated replay cannot duplicate the reward")
	suite.assert_close(replay_health.current_hp, hp_before_repeat, "Gun repeated replay cannot duplicate cross-instance damage")

	await _free_player(replay_target)
	replay_target_entity.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_staff_payload_result(suite, profile: Dictionary) -> void:
	var source := await _spawn_player(suite, profile, "staff")
	if source == null:
		return
	var recorder = ReplayRecorderScript.new()
	recorder.start_recording(profile, 717171)
	recorder.record_snapshot(source.weapon_replay_snapshot())
	suite.assert_true(await _drive_to_active(source, &"weapon_primary", 0), "Staff projectile reaches ACTIVE")
	var active_before_result: Dictionary = source.weapon_replay_snapshot()
	recorder.record_snapshot(active_before_result)
	var payloads: Array[Node] = source.staff_weapon.call("owned_payloads_for_test")
	suite.assert_true(not payloads.is_empty(), "Staff ACTIVE owns a real projectile payload")
	if payloads.is_empty() or not payloads[0].has_method("hit_for_test"):
		await _free_player(source)
		return
	var result: Dictionary = payloads[0].call("hit_for_test", 777001)
	suite.assert_true(not result.is_empty(), "Staff real payload emits a result through the adapter")
	var finished := _finish_external_source(suite, source, recorder, "Staff payload")
	var events: Array = finished.get("events", [])
	suite.assert_equal(_fact_count(events, "weapon_payload_result"), 1, "Staff records one payload-result external fact")
	var payload_result_event := _fact_event(events, "weapon_payload_result")
	var payload_result_data := (payload_result_event.get("payload", {}) as Dictionary).get("data", {}) as Dictionary
	var payload_result_after := payload_result_data.get("state_after", {}) as Dictionary
	var payload_result_coordinator := payload_result_after.get("coordinator", {}) as Dictionary
	var payload_result_runtime := payload_result_coordinator.get("runtime", {}) as Dictionary
	var payload_result_adapter := payload_result_runtime.get("adapter_snapshot", {}) as Dictionary
	suite.assert_equal(
		payload_result_adapter.get("owned_payloads", []),
		[],
		"Staff terminal payload fact removes the terminal projectile before freezing state_after"
	)
	var callback_claims := payload_result_adapter.get("callback_claims", {}) as Dictionary
	suite.assert_true(
		not callback_claims.is_empty(),
		"Staff terminal payload fact freezes its callback claim in the same state_after"
	)
	var terminal: Dictionary = finished.get("terminal", {})
	var replay: Dictionary = finished.get("replay", {})
	await _free_player(source)

	var replay_target := await _spawn_player(suite, profile, "staff")
	if replay_target == null:
		return
	var guard_target := await _spawn_target()
	var stop_probe := ReplayStopProbe.new()
	add_child(stop_probe)
	await get_tree().process_frame
	var player = ReplayPlayerScript.new()
	suite.assert_true(bool(player.load_replay(replay, profile).get("ok", false)), "Staff payload-result replay loads")
	var restored: Dictionary = player.restore_frame(replay_target, 1)
	suite.assert_true(bool(restored.get("ok", false)), "Staff restores pre-result ACTIVE checkpoint: %s" % str(restored))
	_assert_current_prestate_drift_is_rejected(
		suite,
		replay_target,
		payload_result_event,
		guard_target,
		stop_probe,
		"weapon payload result rejects current pre-state combo drift"
	)
	var missing_payload_digest := payload_result_event.duplicate(true)
	((missing_payload_digest["payload"] as Dictionary)["data"] as Dictionary).erase(
		"state_before_digest"
	)
	suite.assert_true(
		ReplayRecorderScript.validate_event(
			missing_payload_digest,
			ReplayRecorderScript.profile_identity(profile)
		).is_empty(),
		"weapon payload result requires a state_before_digest"
	)
	_assert_rejected_external_fact_is_atomic(
		suite,
		replay_target,
		missing_payload_digest,
		guard_target,
		stop_probe,
		"weapon payload result without state_before_digest is rejected"
	)
	var forged_payload_result := payload_result_event.duplicate(true)
	var forged_payload_data := (forged_payload_result["payload"] as Dictionary)["data"] as Dictionary
	var forged_payload_after := forged_payload_data["state_after"] as Dictionary
	var forged_payload_time := forged_payload_after["time_manager_state"] as Dictionary
	forged_payload_time["stop_active"] = true
	forged_payload_time["stop_source_sequence"] = 80
	forged_payload_time["stop_source_id"] = "forged:80"
	forged_payload_time["stop_remaining"] = 5.0
	suite.assert_true(
		not ReplayRecorderScript.validate_event(
			forged_payload_result,
			ReplayRecorderScript.profile_identity(profile)
		).is_empty(),
		"payload result with TimeManager smuggling remains structurally valid"
	)
	_assert_rejected_external_fact_is_atomic(
		suite,
		replay_target,
		forged_payload_result,
		guard_target,
		stop_probe,
		"weapon payload result rejects TimeManager smuggling"
	)
	var claim_smuggling_payload_result := payload_result_event.duplicate(true)
	var claim_payload_data := (
		(claim_smuggling_payload_result["payload"] as Dictionary)["data"] as Dictionary
	)
	var claim_payload_after := claim_payload_data["state_after"] as Dictionary
	var claim_payload_player := claim_payload_after["player_weapon_state"] as Dictionary
	var claim_payload_rewards := claim_payload_player["action_reward_claims"] as Dictionary
	var claim_payload_token := int(
		(claim_smuggling_payload_result["payload"] as Dictionary)["action_token"]
	)
	claim_payload_rewards["%d:forged_payload_reward" % claim_payload_token] = true
	suite.assert_true(
		not ReplayRecorderScript.validate_event(
			claim_smuggling_payload_result,
			ReplayRecorderScript.profile_identity(profile)
		).is_empty(),
		"payload result with an extra valid reward claim remains structurally valid"
	)
	_assert_rejected_external_fact_is_atomic(
		suite,
		replay_target,
		claim_smuggling_payload_result,
		guard_target,
		stop_probe,
		"weapon payload result rejects Player claim smuggling"
	)
	var runtime_smuggling_payload_result := payload_result_event.duplicate(true)
	var runtime_payload_data := (
		(runtime_smuggling_payload_result["payload"] as Dictionary)["data"] as Dictionary
	)
	var runtime_payload_after := runtime_payload_data["state_after"] as Dictionary
	var runtime_payload_coordinator := runtime_payload_after["coordinator"] as Dictionary
	var payload_runtime := runtime_payload_coordinator["runtime"] as Dictionary
	var payload_mana := float(payload_runtime.get("mana", 0.0))
	payload_runtime["mana"] = payload_mana - 1.0 if payload_mana >= 1.0 else payload_mana + 1.0
	suite.assert_true(
		not ReplayRecorderScript.validate_event(
			runtime_smuggling_payload_result,
			ReplayRecorderScript.profile_identity(profile)
		).is_empty(),
		"payload result with a different valid runtime mana remains structurally valid"
	)
	_assert_rejected_external_fact_is_atomic(
		suite,
		replay_target,
		runtime_smuggling_payload_result,
		guard_target,
		stop_probe,
		"weapon payload result rejects runtime state smuggling"
	)
	var replayed: Dictionary = player.replay_to_terminal(replay_target, 1)
	suite.assert_true(bool(replayed.get("ok", false)), "Staff payload-result fact replays: %s" % str(replayed))
	var terminal_digest := ReplayRecorderScript.value_digest(terminal)
	suite.assert_equal(ReplayRecorderScript.value_digest(replay_target.weapon_replay_snapshot()), terminal_digest, "Staff payload result reaches the source terminal digest")
	suite.assert_true(bool(player.replay_to_terminal(replay_target, 1).get("ok", false)), "Staff repeated payload replay succeeds")
	suite.assert_equal(ReplayRecorderScript.value_digest(replay_target.weapon_replay_snapshot()), terminal_digest, "Staff repeated payload replay is idempotent")
	await _free_player(replay_target)
	guard_target.queue_free()
	stop_probe.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_staff_resource_reward(suite, profile: Dictionary) -> void:
	var source := await _spawn_player(suite, profile, "staff")
	if source == null:
		return
	_set_time_energy(source, 80.0)
	var recorder = ReplayRecorderScript.new()
	recorder.start_recording(profile, 727272)
	recorder.record_snapshot(source.weapon_replay_snapshot())
	suite.assert_true(await _drive_to_active(source, &"weapon_ultimate", 60), "Staff Primordial Wrath reaches ACTIVE")
	var active_before_reward: Dictionary = source.weapon_replay_snapshot()
	var active_energy_state := _time_energy_state(active_before_reward)
	suite.assert_close(float(active_energy_state.get("current", -1.0)), 25.0, "Staff ACTIVE checkpoint freezes the committed Time Energy cost")
	suite.assert_equal(active_energy_state, source.time_manager.resource_state(&"time_energy"), "Staff ACTIVE checkpoint matches the live canonical Time Energy provider")
	suite.assert_equal(active_energy_state, _coordinator_time_energy_state(active_before_reward), "Staff ACTIVE checkpoint keeps both Time Energy authorities identical")
	recorder.record_snapshot(active_before_reward)
	var ultimate_payloads: Array[Node] = source.staff_weapon.call("owned_payloads_for_test")
	suite.assert_equal(ultimate_payloads.size(), 1, "Staff Primordial Wrath owns one real seeded zone")
	if ultimate_payloads.is_empty():
		await _free_player(source)
		return
	ultimate_payloads[0].call("advance_execution_for_test", 6)
	var source_energy_after := float(source.time_manager.energy)
	suite.assert_close(source_energy_after, 27.0, "Staff source applies one ultimate reward after its committed cost")
	var finished := _finish_external_source(suite, source, recorder, "Staff reward")
	suite.assert_equal(_fact_count(finished.get("events", []), "weapon_resource_reward"), 1, "Staff records one resource-reward external fact")
	var terminal: Dictionary = finished.get("terminal", {})
	var terminal_energy_state := _time_energy_state(terminal)
	suite.assert_close(float(terminal_energy_state.get("current", -1.0)), 27.0, "Staff terminal checkpoint freezes the applied Time Energy reward")
	suite.assert_equal(terminal_energy_state, source.time_manager.resource_state(&"time_energy"), "Staff terminal checkpoint matches the live canonical Time Energy provider")
	suite.assert_equal(terminal_energy_state, _coordinator_time_energy_state(terminal), "Staff terminal checkpoint keeps both Time Energy authorities identical")
	var replay: Dictionary = finished.get("replay", {})
	await _free_player(source)

	var replay_target := await _spawn_player(suite, profile, "staff")
	if replay_target == null:
		return
	var player = ReplayPlayerScript.new()
	var loaded: Dictionary = player.load_replay(replay, profile)
	suite.assert_true(bool(loaded.get("ok", false)), "Staff reward replay loads: %s" % str(loaded))
	var restored: Dictionary = player.restore_frame(replay_target, 1)
	suite.assert_true(bool(restored.get("ok", false)), "Staff reward restores pre-result ACTIVE checkpoint: %s" % str(restored))
	suite.assert_equal(replay_target.time_manager.resource_state(&"time_energy"), active_energy_state, "Staff reward checkpoint restore reinstalls exact Time Energy current and revision")
	var replayed: Dictionary = player.replay_to_terminal(replay_target, 1)
	suite.assert_true(bool(replayed.get("ok", false)), "Staff reward fact replays: %s" % str(replayed))
	suite.assert_close(float(replay_target.time_manager.energy), source_energy_after, "Staff replay reproduces ultimate energy reward")
	suite.assert_equal(replay_target.time_manager.resource_state(&"time_energy"), terminal_energy_state, "Staff reward replay reaches exact terminal Time Energy authority")
	var terminal_digest := ReplayRecorderScript.value_digest(terminal)
	suite.assert_equal(ReplayRecorderScript.value_digest(replay_target.weapon_replay_snapshot()), terminal_digest, "Staff reward replay reaches terminal digest")
	var energy_before_repeat := float(replay_target.time_manager.energy)
	suite.assert_true(bool(player.replay_to_terminal(replay_target, 1).get("ok", false)), "Staff repeated reward replay succeeds")
	suite.assert_close(float(replay_target.time_manager.energy), energy_before_repeat, "Staff repeated replay cannot duplicate reward")
	await _free_player(replay_target)


func _test_gauntlets_payload_result(suite, profile: Dictionary) -> void:
	var target := await _spawn_target()
	var target_health: PartialMutationHealth = target.get_node("HealthComponent")
	var source := await _spawn_player(suite, profile, "gauntlets")
	if source == null:
		target.queue_free()
		await get_tree().process_frame
		return
	var recorder = ReplayRecorderScript.new()
	recorder.start_recording(profile, 737373)
	recorder.record_snapshot(source.weapon_replay_snapshot())
	suite.assert_true(await _drive_to_active(source, &"weapon_skill", 0), "Gauntlets Space-Time Shatter reaches ACTIVE")
	var active_before_result: Dictionary = source.weapon_replay_snapshot()
	recorder.record_snapshot(active_before_result)
	var payloads: Array[Node] = source.gauntlets_weapon.call("owned_payloads_for_test")
	suite.assert_true(not payloads.is_empty(), "Gauntlets ACTIVE owns a real payload")
	if payloads.is_empty() or not payloads[0].has_method("_execute_target_hit"):
		await _free_player(source)
		target.queue_free()
		await get_tree().process_frame
		return
	var result: Dictionary = payloads[0].call("_execute_target_hit", target)
	suite.assert_true(not result.is_empty(), "Gauntlets real payload resolves a target result")
	var source_hp_after := target_health.current_hp
	var finished := _finish_external_source(suite, source, recorder, "Gauntlets payload")
	suite.assert_equal(_fact_count(finished.get("events", []), "weapon_payload_result"), 1, "Gauntlets records one payload-result external fact")
	var terminal: Dictionary = finished.get("terminal", {})
	var replay: Dictionary = finished.get("replay", {})
	await _free_player(source)
	target_health.current_hp = 1000.0
	target_health.dead = false
	target.remove_meta(&"planewalker_replay_external_fact_claims")

	var replay_target := await _spawn_player(suite, profile, "gauntlets")
	if replay_target == null:
		target.queue_free()
		await get_tree().process_frame
		return
	var player = ReplayPlayerScript.new()
	var loaded: Dictionary = player.load_replay(replay, profile)
	suite.assert_true(bool(loaded.get("ok", false)), "Gauntlets payload-result replay loads: %s" % str(loaded))
	var restored: Dictionary = player.restore_frame(replay_target, 1)
	suite.assert_true(bool(restored.get("ok", false)), "Gauntlets restores pre-result ACTIVE checkpoint: %s" % str(restored))
	var replayed: Dictionary = player.replay_to_terminal(replay_target, 1)
	suite.assert_true(bool(replayed.get("ok", false)), "Gauntlets payload-result fact replays: %s" % str(replayed))
	suite.assert_close(target_health.current_hp, source_hp_after, "Gauntlets replay reproduces real target HP")
	var terminal_digest := ReplayRecorderScript.value_digest(terminal)
	suite.assert_equal(ReplayRecorderScript.value_digest(replay_target.weapon_replay_snapshot()), terminal_digest, "Gauntlets payload replay reaches terminal digest")
	var hp_before_repeat := target_health.current_hp
	suite.assert_true(bool(player.replay_to_terminal(replay_target, 1).get("ok", false)), "Gauntlets repeated payload replay succeeds")
	suite.assert_close(target_health.current_hp, hp_before_repeat, "Gauntlets repeated replay cannot duplicate damage")
	await _free_player(replay_target)
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_time_external_facts(suite, profile: Dictionary) -> void:
	var source := await _spawn_player(suite, profile, "gun")
	if source == null:
		return
	var recorder = ReplayRecorderScript.new()
	recorder.start_recording(profile, 747474)
	recorder.record_snapshot(source.weapon_replay_snapshot())
	suite.assert_true(await _drive_to_active(source, &"weapon_primary", 0), "time-fact Gun action reaches ACTIVE")
	var time_before: Dictionary = source.time_manager.weapon_replay_snapshot()
	time_before["stop_active"] = true
	time_before["stop_source_sequence"] = 1
	time_before["stop_source_id"] = "replay_stop:1"
	time_before["stop_remaining"] = 1.0
	time_before["stop_extension_frames"] = 0
	time_before["stop_extension_tokens"] = {}
	time_before["rewind_window_remaining"] = 2.0
	time_before["rewind_window_generation"] = 7
	time_before["rewind_window_claimed"] = false
	suite.assert_true(source.time_manager.restore_weapon_replay_snapshot(time_before), "time-fact fixture installs authoritative pre-state")
	var active_before_facts: Dictionary = source.weapon_replay_snapshot()
	recorder.record_snapshot(active_before_facts)
	var token := int(active_before_facts.get("token", 0))
	suite.assert_true(source.claim_weapon_time_interaction(&"bow_rewind_echo", 7), "source claims the rewind interaction")
	suite.assert_true(source.extend_weapon_time_stop(token, 30), "source extends active Time Stop")
	var expected_time_after: Dictionary = source.time_manager.weapon_replay_snapshot()
	var finished := _finish_external_source(suite, source, recorder, "time facts")
	var events: Array = finished.get("events", [])
	suite.assert_equal(_fact_count(events, "time_interaction_claim"), 1, "records one rewind interaction claim fact")
	suite.assert_equal(_fact_count(events, "time_stop_extension"), 1, "records one Time Stop extension fact")
	var replay: Dictionary = finished.get("replay", {})
	var terminal: Dictionary = finished.get("terminal", {})
	await _free_player(source)

	var replay_target := await _spawn_player(suite, profile, "gun")
	if replay_target == null:
		return
	var player = ReplayPlayerScript.new()
	var loaded: Dictionary = player.load_replay(replay, profile)
	suite.assert_true(bool(loaded.get("ok", false)), "time-fact replay loads: %s" % str(loaded))
	var restored: Dictionary = player.restore_frame(replay_target, 1)
	suite.assert_true(bool(restored.get("ok", false)), "time-fact replay restores authoritative pre-state: %s" % str(restored))
	var claim_event := _normalized_replay_event(_fact_event(replay.get("events", []), "time_interaction_claim"))
	var extension_event := _normalized_replay_event(_fact_event(replay.get("events", []), "time_stop_extension"))
	suite.assert_true(not claim_event.is_empty(), "time-fact replay exposes the rewind claim event")
	suite.assert_true(not extension_event.is_empty(), "time-fact replay exposes the Stop extension event")

	var forged_energy_claim := claim_event.duplicate(true)
	var forged_energy_data := (forged_energy_claim.get("payload", {}) as Dictionary).get("data", {}) as Dictionary
	var forged_energy_after := forged_energy_data.get("state_after", {}) as Dictionary
	var forged_energy_state := forged_energy_after.get("time_energy_state", {}) as Dictionary
	var forged_energy_current := float(forged_energy_state.get("current", 0.0))
	var forged_energy_maximum := float(forged_energy_state.get("maximum", 0.0))
	forged_energy_state["current"] = (
		forged_energy_current - 1.0
		if forged_energy_current >= 1.0
		else minf(forged_energy_maximum, forged_energy_current + 1.0)
	)
	suite.assert_true(
		ReplayRecorderScript.validate_event(
			forged_energy_claim,
			ReplayRecorderScript.profile_identity(profile)
		).is_empty(),
		"rewind claim rejects smuggled Time Energy even when the nested resource state is valid"
	)
	var before_energy_smuggle: Dictionary = replay_target.weapon_replay_snapshot()
	suite.assert_true(
		not replay_target.apply_weapon_replay_event(forged_energy_claim),
		"rewind claim application rejects smuggled Time Energy"
	)
	suite.assert_equal(
		replay_target.weapon_replay_snapshot(),
		before_energy_smuggle,
		"rejected rewind Energy smuggling leaves the complete Player snapshot unchanged"
	)

	var forged_stop_claim := claim_event.duplicate(true)
	var forged_stop_data := (forged_stop_claim.get("payload", {}) as Dictionary).get("data", {}) as Dictionary
	var forged_stop_after := forged_stop_data.get("state_after", {}) as Dictionary
	forged_stop_after["stop_remaining"] = float(forged_stop_after.get("stop_remaining", 0.0)) + 0.25
	suite.assert_true(
		ReplayRecorderScript.validate_event(
			forged_stop_claim,
			ReplayRecorderScript.profile_identity(profile)
		).is_empty(),
		"rewind claim rejects a smuggled Time Stop duration"
	)
	var before_stop_smuggle: Dictionary = replay_target.weapon_replay_snapshot()
	suite.assert_true(
		not replay_target.apply_weapon_replay_event(forged_stop_claim),
		"rewind claim application rejects a smuggled Time Stop duration"
	)
	suite.assert_equal(
		replay_target.weapon_replay_snapshot(),
		before_stop_smuggle,
		"rejected rewind Stop smuggling leaves the complete Player snapshot unchanged"
	)

	suite.assert_true(
		replay_target.apply_weapon_replay_event(claim_event),
		"Stop-extension smuggling fixture first applies the genuine rewind claim"
	)
	var forged_rewind_extension := extension_event.duplicate(true)
	var forged_extension_data := (forged_rewind_extension.get("payload", {}) as Dictionary).get("data", {}) as Dictionary
	var forged_extension_after := forged_extension_data.get("state_after", {}) as Dictionary
	forged_extension_after["rewind_window_generation"] = int(
		forged_extension_after.get("rewind_window_generation", 0)
	) + 1
	suite.assert_true(
		ReplayRecorderScript.validate_event(
			forged_rewind_extension,
			ReplayRecorderScript.profile_identity(profile)
		).is_empty(),
		"Time Stop extension rejects a smuggled rewind generation"
	)
	var before_rewind_smuggle: Dictionary = replay_target.weapon_replay_snapshot()
	suite.assert_true(
		not replay_target.apply_weapon_replay_event(forged_rewind_extension),
		"Time Stop extension application rejects a smuggled rewind generation"
	)
	suite.assert_equal(
		replay_target.weapon_replay_snapshot(),
		before_rewind_smuggle,
		"rejected Stop-extension rewind smuggling leaves the complete Player snapshot unchanged"
	)
	restored = player.restore_frame(replay_target, 1)
	suite.assert_true(bool(restored.get("ok", false)), "time-fact checkpoint restores after field-smuggling regressions")
	var drift_state: Dictionary = replay_target.time_manager.resource_state(&"time_energy")
	var drifted: Dictionary = replay_target.time_manager.try_spend_resource(
		&"time_energy",
		1.0,
		int(drift_state.get("revision", 0)),
		&"replay_drift_test"
	)
	suite.assert_true(bool(drifted.get("ok", false)), "time-fact fixture creates an energy/revision drift")
	var drift_before_reject: Dictionary = replay_target.time_manager.weapon_replay_snapshot()
	suite.assert_true(
		not claim_event.is_empty() and not replay_target.apply_weapon_replay_event(claim_event),
		"time fact rejects energy/revision drift instead of treating it as the recorded pre-state"
	)
	suite.assert_equal(
		replay_target.time_manager.weapon_replay_snapshot(),
		drift_before_reject,
		"rejected time fact leaves the drifted state untouched"
	)
	restored = player.restore_frame(replay_target, 1)
	suite.assert_true(bool(restored.get("ok", false)), "time-fact checkpoint restores after the drift rejection")
	var replayed: Dictionary = player.replay_to_terminal(replay_target, 1)
	suite.assert_true(bool(replayed.get("ok", false)), "rewind claim and Stop extension replay: %s" % str(replayed))
	suite.assert_equal(replay_target.time_manager.weapon_replay_snapshot(), expected_time_after, "time facts reproduce exact state_before/state_after transition")
	var terminal_digest := ReplayRecorderScript.value_digest(terminal)
	suite.assert_equal(ReplayRecorderScript.value_digest(replay_target.weapon_replay_snapshot()), terminal_digest, "time fact replay reaches terminal digest")
	suite.assert_true(bool(player.replay_to_terminal(replay_target, 1).get("ok", false)), "repeated time fact replay succeeds")
	suite.assert_equal(replay_target.time_manager.weapon_replay_snapshot(), expected_time_after, "repeated time fact replay is idempotent")
	await _free_player(replay_target)


func _finish_external_source(suite, source: Node, recorder, label: String) -> Dictionary:
	source.advance_action_frame()
	suite.assert_true(bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)), "%s post-fact checkpoint records" % label)
	var guard := 1024
	while str(source.weapon_replay_snapshot().get("phase", "")) != "READY" and guard > 0:
		source.advance_action_frame()
		guard -= 1
	suite.assert_true(guard > 0, "%s source reaches terminal READY" % label)
	var terminal: Dictionary = source.weapon_replay_snapshot()
	suite.assert_true(bool(recorder.record_snapshot(terminal).get("ok", false)), "%s terminal checkpoint records" % label)
	var events: Array[Dictionary] = source.weapon_replay_events()
	for event: Dictionary in events:
		suite.assert_true(bool(recorder.record_event(event).get("ok", false)), "%s event records" % label)
	var replay: Dictionary = recorder.finish_recording().get("replay", {})
	return {"terminal": terminal, "events": events, "replay": replay}


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
		if str(event.get("event_type", "")) == "external_fact" and str(payload.get("fact_type", "")) == fact_type:
			return event.duplicate(true)
	return {}


func _normalized_replay_event(event: Dictionary) -> Dictionary:
	var normalized := event.duplicate(true)
	normalized.erase("digest")
	return normalized


func _reset_replay_capture(player: Node) -> void:
	var cleared_events: Array[Dictionary] = []
	player.set("_weapon_replay_events", cleared_events)
	player.set("_weapon_replay_capture_sequence", 0)
	player.call("_refresh_weapon_replay_fact_baseline")


func _assert_rejected_record_fact_is_atomic(
	suite,
	player: Node,
	fact_type: String,
	action_token: int,
	action_generation: int,
	data: Dictionary,
	label: String
) -> void:
	var before_snapshot: Dictionary = player.weapon_replay_snapshot()
	var before_events: Array[Dictionary] = player.weapon_replay_events()
	var before_raw_events_value: Variant = player.get("_weapon_replay_events")
	var before_raw_events: Array[Dictionary] = (
		(before_raw_events_value as Array).duplicate(true)
		if before_raw_events_value is Array
		else []
	)
	var before_capture_sequence := int(player.get("_weapon_replay_capture_sequence"))
	var before_baseline_value: Variant = player.get("_weapon_replay_fact_baseline")
	var before_baseline := (
		(before_baseline_value as Dictionary).duplicate(true)
		if before_baseline_value is Dictionary
		else {}
	)
	var recorded := bool(player.call(
		"_record_weapon_replay_external_fact",
		fact_type,
		action_token,
		action_generation,
		data.duplicate(true)
	))
	suite.assert_true(not recorded, label)
	suite.assert_equal(
		player.weapon_replay_events(),
		before_events,
		"%s leaves replay events unchanged" % label
	)
	suite.assert_equal(
		int(player.get("_weapon_replay_capture_sequence")),
		before_capture_sequence,
		"%s leaves replay capture sequence unchanged" % label
	)
	var after_baseline_value: Variant = player.get("_weapon_replay_fact_baseline")
	var after_baseline := (
		(after_baseline_value as Dictionary).duplicate(true)
		if after_baseline_value is Dictionary
		else {}
	)
	suite.assert_equal(
		after_baseline,
		before_baseline,
		"%s leaves the authenticated baseline unchanged" % label
	)
	suite.assert_equal(
		player.weapon_replay_snapshot(),
		before_snapshot,
		"%s leaves the live Player snapshot unchanged" % label
	)

	# Keep each red case isolated so one accepted forgery cannot invalidate the
	# preconditions of the remaining record-time checks.
	player.set("_weapon_replay_events", before_raw_events)
	player.set("_weapon_replay_capture_sequence", before_capture_sequence)
	player.set("_weapon_replay_fact_baseline", before_baseline)


func _assert_rejected_external_fact_is_atomic(
	suite,
	player: Node,
	event: Dictionary,
	target: Node,
	stop_probe: ReplayStopProbe,
	label: String
) -> void:
	var before_snapshot: Dictionary = player.weapon_replay_snapshot()
	var before_events: Array[Dictionary] = player.weapon_replay_events()
	var before_capture_sequence := int(player.get("_weapon_replay_capture_sequence"))
	var before_owned_weapon_nodes := _owned_weapon_node_count(player)
	var before_energy: Dictionary = player.time_manager.resource_state(&"time_energy")
	var health: PartialMutationHealth = target.get_node("HealthComponent")
	var before_hp := health.current_hp
	var before_dead := health.dead
	var before_meta_present := target.has_meta(REPLAY_CLAIMS_META)
	var before_meta_value: Variant = target.get_meta(REPLAY_CLAIMS_META, {})
	var before_meta: Dictionary = (
		(before_meta_value as Dictionary).duplicate(true)
		if before_meta_value is Dictionary
		else {}
	)
	var before_apply_calls := stop_probe.apply_calls
	var before_clear_calls := stop_probe.clear_calls
	var applied: bool = bool(player.apply_weapon_replay_event(event))
	suite.assert_true(not applied, label)
	suite.assert_equal(player.weapon_replay_snapshot(), before_snapshot, "%s leaves Player snapshot unchanged" % label)
	suite.assert_equal(player.weapon_replay_events(), before_events, "%s leaves replay events unchanged" % label)
	suite.assert_equal(
		int(player.get("_weapon_replay_capture_sequence")),
		before_capture_sequence,
		"%s leaves replay capture sequence unchanged" % label
	)
	suite.assert_equal(
		_owned_weapon_node_count(player),
		before_owned_weapon_nodes,
		"%s creates no owned payload/projectile residual" % label
	)
	suite.assert_equal(player.time_manager.resource_state(&"time_energy"), before_energy, "%s leaves Energy unchanged" % label)
	suite.assert_close(health.current_hp, before_hp, "%s leaves HP unchanged" % label)
	suite.assert_equal(health.dead, before_dead, "%s leaves death state unchanged" % label)
	suite.assert_equal(stop_probe.apply_calls, before_apply_calls, "%s applies no Time Stop source" % label)
	suite.assert_equal(stop_probe.clear_calls, before_clear_calls, "%s clears no Time Stop source" % label)
	suite.assert_equal(target.has_meta(REPLAY_CLAIMS_META), before_meta_present, "%s preserves claim metadata presence" % label)
	var after_meta_value: Variant = target.get_meta(REPLAY_CLAIMS_META, {})
	var after_meta: Dictionary = (
		(after_meta_value as Dictionary).duplicate(true)
		if after_meta_value is Dictionary
		else {}
	)
	suite.assert_equal(after_meta, before_meta, "%s leaves claim metadata unchanged" % label)
	if player.weapon_replay_snapshot() != before_snapshot:
		player.restore_weapon_replay_snapshot(before_snapshot)
	health.current_hp = before_hp
	health.dead = before_dead
	if before_meta_present:
		target.set_meta(REPLAY_CLAIMS_META, before_meta)
	else:
		target.remove_meta(REPLAY_CLAIMS_META)
	stop_probe.apply_calls = before_apply_calls
	stop_probe.clear_calls = before_clear_calls


func _assert_current_prestate_drift_is_rejected(
	suite,
	player: Node,
	event: Dictionary,
	target: Node,
	stop_probe: ReplayStopProbe,
	label: String
) -> void:
	var clean_snapshot: Dictionary = player.weapon_replay_snapshot()
	var clean_events: Array[Dictionary] = player.weapon_replay_events()
	var clean_capture_sequence := int(player.get("_weapon_replay_capture_sequence"))
	var clean_player_state := clean_snapshot.get("player_weapon_state", {}) as Dictionary
	var clean_combo_timeout := int(clean_player_state.get("combo_timeout_frames", 0))
	player.set("_weapon_combo_timeout_frames", clean_combo_timeout + 1)
	var drifted_snapshot: Dictionary = player.weapon_replay_snapshot()
	var event_data := (event.get("payload", {}) as Dictionary).get("data", {}) as Dictionary
	suite.assert_true(
		ReplayRecorderScript.value_digest(drifted_snapshot) != str(
			event_data.get("state_before_digest", "")
		),
		"%s fixture changes the complete pre-state digest" % label
	)
	_assert_rejected_external_fact_is_atomic(
		suite,
		player,
		event,
		target,
		stop_probe,
		label
	)
	suite.assert_true(
		player.restore_weapon_replay_snapshot(clean_snapshot),
		"%s fixture restores the authoritative pre-state" % label
	)
	suite.assert_equal(
		player.weapon_replay_events(),
		clean_events,
		"%s fixture restores the replay event prefix" % label
	)
	suite.assert_equal(
		int(player.get("_weapon_replay_capture_sequence")),
		clean_capture_sequence,
		"%s fixture restores the replay capture sequence" % label
	)


func _owned_weapon_node_count(player: Node) -> int:
	var snapshot: Dictionary = player.weapon_replay_snapshot()
	match str(snapshot.get("weapon_id", "")):
		"gun":
			var gun: Variant = player.get("gun_weapon")
			if gun is Object and is_instance_valid(gun) and gun.has_method(
				"owned_projectile_count_for_test"
			):
				return int(gun.call("owned_projectile_count_for_test"))
		"staff":
			var staff: Variant = player.get("staff_weapon")
			if staff is Object and is_instance_valid(staff) and staff.has_method(
				"owned_payload_count_for_test"
			):
				return int(staff.call("owned_payload_count_for_test"))
		"gauntlets":
			var gauntlets: Variant = player.get("gauntlets_weapon")
			if gauntlets is Object and is_instance_valid(gauntlets) and gauntlets.has_method(
				"owned_payload_count_for_test"
			):
				return int(gauntlets.call("owned_payload_count_for_test"))
		"sword":
			var sword: Variant = player.get("sword_weapon")
			if sword is Object and is_instance_valid(sword) and sword.has_method(
				"launch_payload_snapshots_for_test"
			):
				var payloads: Variant = sword.call("launch_payload_snapshots_for_test")
				return (payloads as Array).size() if payloads is Array else 0
	return 0


func _time_energy_state(snapshot: Dictionary) -> Dictionary:
	var time_state_value: Variant = snapshot.get("time_manager_state")
	if not time_state_value is Dictionary:
		return {}
	var energy_value: Variant = (time_state_value as Dictionary).get("time_energy_state")
	return (energy_value as Dictionary).duplicate(true) if energy_value is Dictionary else {}


func _coordinator_time_energy_state(snapshot: Dictionary) -> Dictionary:
	var coordinator_value: Variant = snapshot.get("coordinator")
	if not coordinator_value is Dictionary:
		return {}
	var transaction_value: Variant = (coordinator_value as Dictionary).get("resource_transaction")
	if not transaction_value is Dictionary:
		return {}
	var accounts_value: Variant = (transaction_value as Dictionary).get("external_accounts")
	if not accounts_value is Dictionary:
		return {}
	var energy_value: Variant = (accounts_value as Dictionary).get("time_energy")
	return (energy_value as Dictionary).duplicate(true) if energy_value is Dictionary else {}


func _set_time_energy(player: Node, current: float) -> void:
	var state: Dictionary = player.time_manager.resource_state(&"time_energy")
	state["current"] = current
	state["revision"] = int(state.get("revision", 0)) + 1
	player.time_manager.restore_resource_state(&"time_energy", state)


func _drive_to_active(player: Node, semantic_action: StringName, hold_frames: int) -> bool:
	player.advance_action_frame()
	if not player.try_action(semantic_action):
		return false
	if str(player.weapon_replay_snapshot().get("phase", "")) == "HOLD":
		for _frame: int in range(hold_frames):
			if str(player.weapon_replay_snapshot().get("phase", "")) != "HOLD":
				break
			player.advance_action_frame()
		if (
			str(player.weapon_replay_snapshot().get("phase", "")) == "HOLD"
			and not bool(player.call("_submit_weapon_intent", semantic_action, &"released"))
		):
			return false
	var guard := 512
	while str(player.weapon_replay_snapshot().get("phase", "")) != "ACTIVE" and guard > 0:
		player.advance_action_frame()
		guard -= 1
	return guard > 0


func _spawn_player(suite, profile: Dictionary, weapon_id: String) -> Node:
	var player := PlayerScene.instantiate()
	player.name = "ReplaySource"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var configured: bool = bool(player.configure_loadout({
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": weapon_id,
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 515151,
		"weapon_profile": profile.duplicate(true),
	}))
	suite.assert_true(configured, "%s replay fixture configures" % weapon_id)
	if not configured:
		await _free_player(player)
		return null
	return player


func _spawn_target() -> Node2D:
	var target := Node2D.new()
	target.name = "ReplayTarget"
	target.add_to_group("enemies")
	var target_health := PartialMutationHealth.new()
	target_health.name = "HealthComponent"
	target.add_child(target_health)
	var hurtbox := HurtboxScript.new()
	hurtbox.name = "Hurtbox"
	hurtbox.health_component_path = NodePath("../HealthComponent")
	target.add_child(hurtbox)
	add_child(target)
	await get_tree().process_frame
	return target


func _free_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.cancel_transient_actions()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _has_payload_kind(payloads: Array, expected_kind: String) -> bool:
	for payload_value: Variant in payloads:
		if payload_value is Dictionary and str((payload_value as Dictionary).get("kind", "")) == expected_kind:
			return true
	return false


func _load_profile(suite, profile_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	suite.assert_true(parsed is Array, "weapon profile catalog parses for external-fact replay")
	if not parsed is Array:
		return {}
	for value: Variant in parsed:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == profile_id:
			return (value as Dictionary).duplicate(true)
	suite.assert_true(false, "%s exists for external-fact replay" % profile_id)
	return {}
