extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Store := preload("res://scripts/replay/run_replay_stream_store.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var player: Node2D = main.get_node("CombatRoom01/Player")
	var available := player.has_method("native_replay_recording_snapshot") and player.has_method("validate_native_replay_recording_snapshot")
	suite.assert_true(available, "actual Player supplies owned native recording capture and validation APIs")
	if not available:
		await _close(main)
		suite.finish(get_tree())
		return
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 4}
	suite.assert_true(main._launch_run(config, false, true), "actual Main launches the recorded capture fixture")
	_freeze(main)
	var recorder: Node = main.get_node("NativeRunReplayRecorder")
	var host: Node = main.get_node("RunRuntimeHost")
	var selected: Dictionary = host.route_choices()[0]
	for choice: Dictionary in host.route_choices():
		if choice.room_type == "combat":
			selected = choice
			break
	suite.assert_true(host.select_route(StringName(selected.edge_id), int(host.runtime_snapshot().revision)).ok, "actual native room supplies recorded hostiles")
	host.set_dungeon_selection_safety(false)
	player.health.acquire_invulnerability_source(&"native_recording_snapshot_fixture")
	suite.assert_true(recorder.observe_transition().ok, "actual room boundary is retained")
	for index: int in range(12):
		var intents := {"movement": Vector2.ZERO, "aim": Vector2.RIGHT}
		if index == 0:
			intents["weapon"] = [{"id": "weapon_primary", "edge": "pressed", "mode": str(player.call("_weapon_semantic_input_mode", &"weapon_primary")), "held_frames": 0}]
		suite.assert_true(player.advance_action_frame(intents), "actual recorded weapon frame %d commits" % index)
		var captured: Dictionary = player.call("native_replay_recording_snapshot")
		suite.assert_true(_exact(captured, player.full_player_replay_snapshot()), "native capture preserves full public typed bytes at frame %d" % index)
		_check_validation(suite, player, captured, "current owned native frame %d" % index)
		await get_tree().physics_frame
	var current: Dictionary = player.call("native_replay_recording_snapshot")
	var current_bytes := var_to_bytes(current)
	var history: Array[Dictionary] = current.weapon_replay_events
	suite.assert_true(not history.is_empty() and history.is_read_only(), "real weapon history has a read-only capture wrapper")
	suite.assert_true(_frozen_events(history), "every certified event descendant is deeply sealed")
	var public: Dictionary = player.full_player_replay_snapshot()
	suite.assert_true(not public.weapon_replay_events.is_read_only() and not public.weapon_replay_events[0].payload.is_read_only(), "public full snapshot retains mutable detached history")
	public.weapon_replay_events[0].payload["caller_mutation"] = true
	public.player_state.position = Vector2(1, 2)
	suite.assert_equal(var_to_bytes(player.full_player_replay_snapshot()), current_bytes, "public mutation cannot change actual Player state or sealed history")
	var foreign := current.duplicate(true)
	var foreign_history: Array[Dictionary] = foreign.weapon_replay_events
	foreign_history.make_read_only()
	_check_validation(suite, player, foreign, "same-count foreign read-only history retains cold acceptance")
	foreign = current.duplicate(true)
	foreign.weapon_replay_events[0].payload["unsafe"] = self
	foreign.weapon_replay_events.make_read_only()
	_check_validation(suite, player, foreign, "foreign same-count unsafe history cannot acquire shortcut")
	suite.assert_true(not player.call("validate_native_replay_recording_snapshot", foreign, current.identity).ok, "foreign same-count unsafe history refuses")
	var forged := current.duplicate(false)
	forged.player_state = current.player_state.duplicate(true)
	forged.player_state["unsafe"] = self
	_check_validation(suite, player, forged, "owned history never skips unsafe other state")
	suite.assert_true(not player.call("validate_native_replay_recording_snapshot", forged, current.identity).ok, "unsafe other state refuses with owned history")
	forged = current.duplicate(false)
	forged.action_state = current.action_state.duplicate(true)
	forged.action_state.frame += 1
	_check_validation(suite, player, forged, "owned history never skips forged frame clocks")
	suite.assert_true(not player.call("validate_native_replay_recording_snapshot", forged, current.identity).ok, "forged frame clock refuses with owned history")
	var wrong_identity: Dictionary = current.identity.duplicate(true)
	wrong_identity.run_id = "foreign-recording-run"
	suite.assert_equal(player.call("validate_native_replay_recording_snapshot", current, wrong_identity), Replay.validate_full_player_snapshot(current, wrong_identity), "owned history never skips expected run identity")
	suite.assert_true(not player.call("validate_native_replay_recording_snapshot", current, wrong_identity).ok, "foreign expected run identity refuses")
	var packed_history: Array[Dictionary] = history.duplicate(true)
	packed_history[0].payload["packed_fallback"] = PackedByteArray([1, 2, 3])
	player.set("_weapon_replay_events", packed_history)
	var packed: Dictionary = player.call("native_replay_recording_snapshot")
	suite.assert_true(_exact(packed, player.full_player_replay_snapshot()) and not packed.weapon_replay_events.is_read_only(), "Packed descendants use byte-exact detached cold capture")
	_check_validation(suite, player, packed, "Packed fallback retains original validator")
	var packed_before := var_to_bytes(player.full_player_replay_snapshot())
	packed.weapon_replay_events[0].payload.packed_fallback[0] = 255
	suite.assert_equal(var_to_bytes(player.full_player_replay_snapshot()), packed_before, "Packed fallback caller mutation stays detached")
	player.set("_weapon_replay_events", history.duplicate(false))
	suite.assert_equal(var_to_bytes(player.call("native_replay_recording_snapshot")), current_bytes, "restored actual history returns to exact certified boundary")
	var latest: Dictionary = recorder.latest_observation()
	var latest_bytes := var_to_bytes(latest)
	latest.player.weapon_replay_events[0].payload["latest_caller_mutation"] = true
	latest.player.health_state.current_hp = -1.0
	suite.assert_equal(var_to_bytes(recorder.latest_observation()), latest_bytes, "public latest cannot mutate shared private recording")
	var before_recording: Dictionary = recorder.snapshot()
	var before_player := var_to_bytes(player.full_player_replay_snapshot())
	var runner: Node = host.native_checkpoint_participants().controller.encounter_runner()
	var before_native := var_to_bytes(runner.native_cold_snapshot())
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not suite.expect_rejected_player_frame(player), "late native whole-frame refusal exercises sealed-history rollback")
	player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	suite.assert_equal(var_to_bytes(player.full_player_replay_snapshot()), before_player, "late rollback restores complete Player typed state")
	suite.assert_equal(var_to_bytes(runner.native_cold_snapshot()), before_native, "late rollback restores actual native hostile typed state")
	suite.assert_equal(recorder.snapshot(), before_recording, "refused whole frame adds no tape observation")
	suite.assert_equal(var_to_bytes(recorder.latest_observation()), latest_bytes, "rollback preserves previous private recording boundary")
	suite.assert_true(player.advance_action_frame({"movement": Vector2.ZERO, "aim": Vector2.RIGHT}), "same authoritative frame retries successfully")
	suite.assert_equal(recorder.snapshot().observation_count, before_recording.observation_count + 1, "successful same-frame retry records exactly once")
	var final: Dictionary = recorder.latest_observation()
	suite.assert_true(_exact(final.player, player.full_player_replay_snapshot()), "final automatic tape preserves complete public typed bytes")
	suite.assert_true(recorder.flush().ok, "actual native capture flushes into physical immutable chunks")
	var identity: Dictionary = GameState.profile_runtime_service().local_record_storage_identity()
	var physical := Store.new()
	suite.assert_true(physical.configure(recorder.storage_root(), "0.4.0-dev", identity.content_snapshot, identity.profile_id, identity.save_domain).ok, "fresh physical reader opens the actual recording")
	var read: Dictionary = physical.read(str(recorder.snapshot().id), int(final.sequence))
	suite.assert_true(read.ok and _exact(read.context.observation, final), "physical random seek preserves shared observation typed bytes")
	await _close(main)
	suite.finish(get_tree())


func _check_validation(suite: RefCounted, player: Node, snapshot: Dictionary, label: String) -> void:
	var expected: Dictionary = Replay.validate_full_player_snapshot(snapshot, snapshot.identity)
	var actual: Dictionary = player.call("validate_native_replay_recording_snapshot", snapshot, snapshot.identity)
	suite.assert_equal(actual, expected, label + " keeps full validator verdict")


static func _exact(left: Variant, right: Variant) -> bool:
	return var_to_bytes(left) == var_to_bytes(right)


static func _frozen_events(events: Array[Dictionary]) -> bool:
	for event: Dictionary in events:
		if not _frozen(event):
			return false
	return true


static func _frozen(value: Variant) -> bool:
	if value is Dictionary:
		if not value.is_read_only():
			return false
		for child: Variant in value.values():
			if not _frozen(child):
				return false
	elif value is Array:
		if not value.is_read_only():
			return false
		for child: Variant in value:
			if not _frozen(child):
				return false
	return true


func _close(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout


func _freeze(main: Node) -> void:
	main.set_process(false)
	main.get_node("RunRuntimeHost").set_process(false)
	main.get_node("DungeonFlow").set_process(false)
	main.get_node("TutorialFlow").set_process(false)
	main.get_node("NarrativeFlow").set_physics_process(false)
	var player: Node = main.get_node("CombatRoom01/Player")
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
