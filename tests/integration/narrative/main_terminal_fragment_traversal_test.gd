extends "res://tests/integration/narrative/main_narrative_flow_test.gd"


func _run() -> void:
	suite = Suite.new()
	_main = MainScene.instantiate()
	add_child(_main)
	await get_tree().process_frame
	_flow = _main.get_node("NarrativeFlow")
	_service = GameState.profile_runtime_service()
	_host = _main.get_node("RunRuntimeHost")
	_room_host = _main.get_node("LaunchRoomSceneHost")
	_player = _main.get_node("CombatRoom01/Player")
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "accelerate"], "difficulty": "normal", "seed": 4}
	suite.assert_true(_main._launch_run(config, false, true), "terminal traversal starts real Main with explicit synthetic route prerequisites")
	_run_state = _host.native_run_state()
	NativeRoute.freeze(_main)
	_run_state.run_time_ms = 1000
	var reached: bool = await NativeRoute.reach(_main, suite, true)
	suite.assert_true(reached, "synthetic combat receipts enter the production terminal narrative flow")
	var diagnostic := {"schema_version": 1, "report_kind": "native_terminal_fragment_traversal", "prerequisite_route_synthetic": true, "combat_certification": false, "seed": 4, "frames": 0, "positions": [], "rejections": [], "collected": false}
	_flow.command_rejected.connect(func(code: StringName): diagnostic.rejections.append({"code": str(code), "frame": diagnostic.frames, "time_ms": Time.get_ticks_msec()}))
	if not reached:
		print("NATIVE_TERMINAL_TRAVERSAL ", JSON.stringify(diagnostic))
		await _finish()
		return
	var occurrences: Array = _flow.get("_occurrences")
	suite.assert_true(occurrences.size() == 1 and is_instance_valid(occurrences[0].token.get_ref()), "production terminal installs its real Area2D fragment")
	if occurrences.size() != 1 or not is_instance_valid(occurrences[0].token.get_ref()):
		await _finish()
		return
	var heart: Area2D = occurrences[0].token.get_ref()
	diagnostic["start_position"] = {"x": _player.global_position.x, "y": _player.global_position.y}
	diagnostic["fragment_position"] = {"x": heart.global_position.x, "y": heart.global_position.y}
	diagnostic["participants_current"] = _flow._participants_current()
	diagnostic["player_disabled"] = not _player.can_process()
	diagnostic["player_disable_mode"] = _player.disable_mode
	diagnostic["player_collision_layer"] = _player.collision_layer
	diagnostic["fragment_collision_mask"] = heart.collision_mask
	var clocks_before := _participant_clocks()
	var run_before: Dictionary = _run_state.snapshot()
	var started_at_ms := Time.get_ticks_msec()
	for frame: int in range(300):
		if not is_instance_valid(heart) or _flow.panel().visible:
			break
		var direction := _player.global_position.direction_to(heart.global_position)
		Input.action_press("move_right", maxf(0.0, direction.x))
		Input.action_press("move_left", maxf(0.0, -direction.x))
		Input.action_press("move_down", maxf(0.0, direction.y))
		Input.action_press("move_up", maxf(0.0, -direction.y))
		_flow._physics_process(1.0 / 60.0)
		await get_tree().physics_frame
		diagnostic.frames = frame + 1
		if frame % 30 == 0:
			diagnostic.positions.append({"frame": frame + 1, "x": _player.global_position.x, "y": _player.global_position.y, "overlap": is_instance_valid(heart) and heart.overlaps_body(_player)})
	for action: String in ["move_right", "move_left", "move_down", "move_up"]:
		Input.action_release(action)
	diagnostic["end_position"] = {"x": _player.global_position.x, "y": _player.global_position.y}
	diagnostic.collected = _service.snapshot().narrative_state.heart_fragments.has("floor_throne_of_void")
	diagnostic["panel_visible"] = _flow.panel().visible
	diagnostic["participants_current_after"] = _flow._participants_current()
	diagnostic["player_alive"] = not _player.health.dead
	diagnostic["flow_recovery_pending"] = _flow.get("_recovery_pending")
	diagnostic["elapsed_ms"] = Time.get_ticks_msec() - started_at_ms
	diagnostic["contact_retry_remaining_ms"] = maxi(0, int(_flow.get("_contact_retry_after_ms")) - Time.get_ticks_msec())
	print("NATIVE_TERMINAL_TRAVERSAL ", JSON.stringify(diagnostic))
	suite.assert_true(diagnostic.collected and _service.snapshot().narrative_state.consumed_sources.has("source:heart_fragment_5"), "ordinary terminal movement collects the real fragment through actual Area2D overlap")
	suite.assert_true(diagnostic.rejections.is_empty(), "legitimate fragment approach does not submit outside the authoritative contact radius")
	suite.assert_equal(_participant_clocks(), clocks_before, "terminal traversal advances no Player action, time, weapon, replay or World clock")
	suite.assert_equal(_run_state.snapshot(), run_before, "terminal fragment traversal preserves the exact terminal Run state")
	suite.assert_true(_flow.panel().visible and _flow.panel().view_state().mode == "story", "saved physical fragment opens its narrative text without choosing an ending")
	await _finish()


func _participant_clocks() -> Dictionary:
	return {"player": _player.get("_runtime_frame"), "time": _player.time_manager.replay_snapshot().runtime_frame, "weapon": _player.weapon_action_coordinator.snapshot().frame, "action": _player.action_state.snapshot().frame, "character": _player.character_action_coordinator.snapshot().last_runtime_frame, "world": _player.world_payload_authority.replay_snapshot().last_runtime_frame, "rewind": _player.rewind_recorder.get("_last_runtime_frame")}
