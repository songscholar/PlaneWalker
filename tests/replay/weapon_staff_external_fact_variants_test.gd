extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const HurtboxScript := preload("res://scripts/combat/hurtbox.gd")
const ReplayPlayerScript := preload("res://scripts/replay/replay_player.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const PROFILE_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const REPLAY_CLAIMS_META := &"planewalker_replay_external_fact_claims"


class ReplayHealth extends Node:
	var max_hp: float = 1000.0
	var current_hp: float = 1000.0
	var dead: bool = false

	func take_damage(damage_info: RefCounted) -> float:
		if dead:
			return 0.0
		var applied := minf(current_hp, float(damage_info.get("amount")))
		current_hp = maxf(0.0, current_hp - applied)
		dead = current_hp <= 0.0
		EventBus.hit_confirmed.emit(damage_info, get_parent(), applied)
		return applied


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var profile := _load_profile(suite)
	if not profile.is_empty():
		await _test_ice_projectile_zone_replay_and_forgery_rejection(suite, profile)
		await _test_sequential_staff_actions_share_generation_and_restore(suite, profile)
	suite.finish(get_tree())


func _test_ice_projectile_zone_replay_and_forgery_rejection(
	suite,
	profile: Dictionary
) -> void:
	var target := await _spawn_target()
	var target_health: ReplayHealth = target.get_node("HealthComponent")
	var source := await _spawn_player(suite, profile)
	if source == null:
		target.queue_free()
		await get_tree().process_frame
		return
	source.weapon_runtime.set("_current_element", &"ice")
	var recorder = ReplayRecorderScript.new()
	suite.assert_true(
		bool(recorder.start_recording(profile, 919191).get("ok", false)),
		"Staff ice replay recording starts"
	)
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"Staff ice replay records its initial checkpoint"
	)
	suite.assert_equal(
		str(source.weapon_runtime.presentation_snapshot().get("element", "")),
		"ice",
		"Staff replay fixture selects ice deterministically"
	)
	suite.assert_true(
		await _drive_to_active(source, &"weapon_primary", 30),
		"Staff charged ice projectile reaches ACTIVE"
	)
	var active_before_hit: Dictionary = source.weapon_replay_snapshot()
	suite.assert_true(
		bool(recorder.record_snapshot(active_before_hit).get("ok", false)),
		"Staff ice replay records the pre-hit ACTIVE checkpoint"
	)
	var payloads: Array[Node] = source.staff_weapon.call("owned_payloads_for_test")
	suite.assert_equal(payloads.size(), 1, "Staff charged ice action owns one projectile")
	if payloads.is_empty() or not payloads[0].has_method("_execute_target_hit"):
		await _free_player(source)
		target.queue_free()
		await get_tree().process_frame
		return
	var hit_result: Dictionary = payloads[0].call("_execute_target_hit", target)
	suite.assert_equal(str(hit_result.get("element", "")), "ice", "Staff projectile reports an ice hit")
	suite.assert_true(target_health.current_hp < 1000.0, "Staff ice projectile resolves real combat damage")
	var source_hp_after := target_health.current_hp
	var source_after_hit: Dictionary = source.weapon_replay_snapshot()
	var source_runtime := (source_after_hit.get("coordinator", {}) as Dictionary).get(
		"runtime",
		{}
	) as Dictionary
	var source_adapter := source_runtime.get("adapter_snapshot", {}) as Dictionary
	var source_owned := source_adapter.get("owned_payloads", []) as Array
	suite.assert_equal(source_owned.size(), 1, "Staff terminal ice projectile is replaced by one zone")
	if not source_owned.is_empty():
		var zone_execution := (source_owned[0] as Dictionary).get("execution", {}) as Dictionary
		suite.assert_equal(zone_execution.get("mode"), "ice_zone", "Staff replacement payload is an ice zone")
		suite.assert_close(
			float((zone_execution.get("parameters", {}) as Dictionary).get("radius_tiles", 0.0)),
			3.0,
			"Staff ice zone freezes the profile-authored radius"
		)
	source.advance_action_frame()
	suite.assert_true(
		bool(recorder.record_snapshot(source.weapon_replay_snapshot()).get("ok", false)),
		"Staff ice replay records its post-hit checkpoint"
	)
	await _drive_to_ready(source)
	var terminal: Dictionary = source.weapon_replay_snapshot()
	suite.assert_true(
		bool(recorder.record_snapshot(terminal).get("ok", false)),
		"Staff ice replay records its terminal checkpoint"
	)
	var source_events: Array[Dictionary] = source.weapon_replay_events()
	var damage_event := _fact_event(source_events, "combat_damage")
	var payload_event := _fact_event(source_events, "weapon_payload_result")
	suite.assert_true(not damage_event.is_empty(), "Staff ice hit records combat damage")
	suite.assert_true(not payload_event.is_empty(), "Staff ice hit records its payload result")
	for event: Dictionary in source_events:
		suite.assert_true(
			bool(recorder.record_event(event).get("ok", false)),
			"Staff ice replay records ordered event %s" % str(event.get("capture_sequence", 0))
		)
	var replay: Dictionary = recorder.finish_recording().get("replay", {})
	var expected_terminal_digest := ReplayRecorderScript.value_digest(terminal)
	await _free_player(source)

	target_health.current_hp = 1000.0
	target_health.dead = false
	target.remove_meta(REPLAY_CLAIMS_META)
	var replay_target := await _spawn_player(suite, profile)
	if replay_target == null:
		target.queue_free()
		await get_tree().process_frame
		return
	var replay_player = ReplayPlayerScript.new()
	suite.assert_true(
		bool(replay_player.load_replay(replay, profile).get("ok", false)),
		"Staff ice external-fact replay loads"
	)
	var restored: Dictionary = replay_player.restore_frame(replay_target, 1)
	suite.assert_true(
		bool(restored.get("ok", false)),
		"Staff ice replay restores the pre-hit ACTIVE checkpoint: %s" % str(restored)
	)
	var replayed: Dictionary = replay_player.replay_to_terminal(replay_target, 1)
	suite.assert_true(bool(replayed.get("ok", false)), "Staff ice hit and zone replay end to end")
	suite.assert_close(target_health.current_hp, source_hp_after, "Staff ice replay reproduces exact HP")
	suite.assert_equal(
		ReplayRecorderScript.value_digest(replay_target.weapon_replay_snapshot()),
		expected_terminal_digest,
		"Staff ice replay reaches the authoritative terminal digest"
	)
	await _free_player(replay_target)

	target_health.current_hp = 1000.0
	target_health.dead = false
	target.remove_meta(REPLAY_CLAIMS_META)
	var forged_target := await _spawn_player(suite, profile)
	if forged_target != null:
		var forged_player = ReplayPlayerScript.new()
		suite.assert_true(
			bool(forged_player.load_replay(replay, profile).get("ok", false)),
			"Staff forged-zone fixture loads"
		)
		var forged_restored: Dictionary = forged_player.restore_frame(forged_target, 1)
		suite.assert_true(
			bool(forged_restored.get("ok", false)),
			"Staff forged-zone fixture restores ACTIVE: %s" % str(forged_restored)
		)
		suite.assert_true(
			forged_target.apply_weapon_replay_event(damage_event),
			"Staff forged-zone fixture applies the ordered combat damage prerequisite"
		)
		var forged_event := payload_event.duplicate(true)
		var forged_data := (forged_event["payload"] as Dictionary)["data"] as Dictionary
		var forged_result := forged_data["result"] as Dictionary
		var forged_zone := forged_result["spawn_zone"] as Dictionary
		var forged_parameters := forged_zone["parameters"] as Dictionary
		forged_parameters["radius_tiles"] = float(forged_parameters["radius_tiles"]) + 1.0
		suite.assert_true(
			not ReplayRecorderScript.validate_event(
				forged_event,
				ReplayRecorderScript.profile_identity(profile)
			).is_empty(),
			"Staff forged ice-zone parameters remain structurally valid"
		)
		var before_reject: Dictionary = forged_target.weapon_replay_snapshot()
		var hp_before_reject := target_health.current_hp
		var payload_count_before := int(forged_target.staff_weapon.call("owned_payload_count_for_test"))
		suite.assert_true(
			not forged_target.apply_weapon_replay_event(forged_event),
			"Staff replay rejects forged ice-zone radius"
		)
		suite.assert_equal(
			forged_target.weapon_replay_snapshot(),
			before_reject,
			"Staff forged zone rejection leaves the complete Player snapshot unchanged"
		)
		suite.assert_close(target_health.current_hp, hp_before_reject, "Staff forged zone rejection leaves HP unchanged")
		suite.assert_equal(
			int(forged_target.staff_weapon.call("owned_payload_count_for_test")),
			payload_count_before,
			"Staff forged zone rejection creates no payload residual"
		)
		await _free_player(forged_target)
	target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_sequential_staff_actions_share_generation_and_restore(
	suite,
	profile: Dictionary
) -> void:
	var player := await _spawn_player(suite, profile)
	if player == null:
		return
	player.advance_action_frame()
	suite.assert_true(
		player.try_action(&"weapon_utility"),
		"Staff replay generation fixture commits Element Cycle"
	)
	await _drive_to_ready(player)
	suite.assert_true(
		await _drive_to_active(player, &"weapon_primary", 30),
		"Staff replay generation fixture commits Charged Element"
	)
	var snapshot: Dictionary = player.weapon_replay_snapshot()
	var player_state := snapshot.get("player_weapon_state", {}) as Dictionary
	var token_order := player_state.get("action_token_order", []) as Array
	var generations := player_state.get("action_generations_by_token", {}) as Dictionary
	suite.assert_equal(token_order.size(), 2, "Staff replay fixture tracks both sequential actions")
	if token_order.size() == 2:
		var first_token := int(token_order[0])
		var second_token := int(token_order[1])
		suite.assert_true(second_token > first_token, "Staff sequential actions receive increasing tokens")
		suite.assert_equal(
			int(generations.get(first_token, 0)),
			int(generations.get(second_token, -1)),
			"Staff sequential READY actions legitimately share one coordinator generation"
		)
	var before_restore_digest := ReplayRecorderScript.value_digest(snapshot)
	suite.assert_true(
		player.restore_weapon_replay_snapshot(snapshot),
		"Staff replay restores a valid snapshot with equal adjacent generations: %s" % str(
			player.weapon_replay_restore_status()
		)
	)
	suite.assert_equal(
		ReplayRecorderScript.value_digest(player.weapon_replay_snapshot()),
		before_restore_digest,
		"Staff equal-generation replay restore preserves the authoritative digest"
	)
	await _free_player(player)


func _fact_event(events: Array[Dictionary], fact_type: String) -> Dictionary:
	for event: Dictionary in events:
		var payload_value: Variant = event.get("payload")
		if (
			str(event.get("event_type", "")) == "external_fact"
			and payload_value is Dictionary
			and str((payload_value as Dictionary).get("fact_type", "")) == fact_type
		):
			return event.duplicate(true)
	return {}


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


func _drive_to_ready(player: Node) -> void:
	var guard := 512
	while str(player.weapon_replay_snapshot().get("phase", "")) != "READY" and guard > 0:
		player.advance_action_frame()
		guard -= 1


func _spawn_player(suite, profile: Dictionary) -> Node:
	var player := PlayerScene.instantiate()
	player.name = "StaffReplaySource"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	var configured: bool = bool(player.configure_loadout({
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "staff",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 919191,
		"weapon_profile": profile.duplicate(true),
	}))
	suite.assert_true(configured, "Staff replay variant fixture configures")
	if not configured:
		await _free_player(player)
		return null
	return player


func _spawn_target() -> Node2D:
	var target := Node2D.new()
	target.name = "StaffReplayTarget"
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


func _free_player(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	player.cancel_transient_actions()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _load_profile(suite) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	suite.assert_true(parsed is Array, "Staff replay variant profile catalog parses")
	if not parsed is Array:
		return {}
	for value: Variant in parsed:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == "staff_launch_v1":
			return (value as Dictionary).duplicate(true)
	suite.assert_true(false, "Staff replay variant profile exists")
	return {}
