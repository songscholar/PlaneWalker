extends "res://tests/integration/save/main_native_resume_test.gd"

const NativeRoute := preload("res://tests/support/native_launch_route_fixture.gd")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261005}
	suite.assert_true(main._launch_run(config, false, true), "actual Main prepares the narrative checkpoint launch")
	_freeze(main)
	main.set_process(false)
	var host: Node = main.get_node("RunRuntimeHost")
	var player: Node = main.get_node("CombatRoom01/Player")
	var service: RefCounted = GameState.profile_runtime_service()
	var prepared: bool = await NativeRoute.reach(main, suite)
	suite.assert_true(prepared, "actual route reaches a cleared native fifth-floor room")
	if not prepared:
		await _dispose(main)
		suite.finish(get_tree())
		return
	main.get_node("DungeonFlow").set_process(false)
	main.get_node("DungeonFlow")._close_panels()
	_freeze(main)
	var room_host: Node = main.get_node("LaunchRoomSceneHost")
	var template: Dictionary = host.native_checkpoint_participants().facade.current_room_restore_target().template
	var installed: Dictionary = service.install_narrative_occurrence("choice", "choice_vera_1", room_host.active_room(), template, "room_exit", main.get_node("NarrativeOccurrences"))
	suite.assert_true(installed.ok, "Vera cost uses the authenticated fifth-floor native occurrence: " + str(installed))
	if not installed.ok:
		await _dispose(main)
		suite.finish(get_tree())
		return
	var token: Area2D = installed.context.occurrence
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	player.global_position = token.global_position
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	suite.assert_true(token.overlaps_body(player), "native Vera occurrence observes actual Player contact: " + str({"player_position": player.global_position, "token_position": token.global_position, "body_layer": player.collision_layer, "mask": token.collision_mask, "disable_mode": player.disable_mode, "body_process": player.process_mode, "token_process": token.process_mode, "bodies": token.get_overlapping_bodies(), "token_queued": token.is_queued_for_deletion()}))
	if not token.overlaps_body(player):
		await _dispose(main)
		suite.finish(get_tree())
		return
	suite.assert_true(main.checkpoint_current_run().ok, "native fifth-floor safe checkpoint exists before the narrative cost")
	var profile_before: Dictionary = service.snapshot()
	var payload_before: Dictionary = service.payload()
	var player_before: Dictionary = player.full_player_replay_snapshot()
	var run_before: Dictionary = host.runtime_snapshot()
	var command := {"command_id": "main-vera-checkpoint", "kind": "narrative_choice", "definition_id": "choice_vera_1", "choice_id": "listen"}
	service.get("_save").set_fault_injector(_inject_fault)
	_fault = true
	var failed: Dictionary = service.execute_narrative(command, int(profile_before.revision), token)
	suite.assert_true(not failed.ok and failed.code != &"OCCURRENCE_INVALID", "physical promotion fault refuses the staged narrative cost: " + str(failed.code))
	suite.assert_equal(service.snapshot(), profile_before, "failed narrative cost preserves all Profile facts")
	suite.assert_equal(service.payload(), payload_before, "failed narrative cost preserves the full durable native checkpoint")
	suite.assert_equal(player.full_player_replay_snapshot(), player_before, "staged narrative capture compensates every live Player participant")
	suite.assert_equal(host.runtime_snapshot(), run_before, "staged narrative capture compensates the complete live Run")
	_fault = false
	service.get("_save").set_fault_injector(Callable())
	var saved: Dictionary = service.execute_narrative(command, int(profile_before.revision), token)
	suite.assert_true(saved.ok, "Vera retry persists the cost with the full native checkpoint: " + str(saved.code))
	suite.assert_equal(player.health.max_hp, float(player_before.reward_effect_state.health.max_hp) - 5.0, "saved Vera choice reduces actual maximum HP exactly once")
	suite.assert_true(service.authenticated_native_checkpoint(int(service.snapshot().revision)).ok, "saved effect and full Replay authenticate before another Main frame")
	var player_after: Dictionary = player.full_player_replay_snapshot()
	var run_after: Dictionary = host.runtime_snapshot()
	var profile_after: Dictionary = service.snapshot()
	await _dispose(main)
	GameState.set("_profile_runtime", null)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.set_process(false)
	_freeze(main)
	var hub: Node = main.get_node("HubFlowCoordinator")
	suite.assert_true(hub.open_function("gateway").ok, "cold Main exposes the narrative checkpoint in the real Hub")
	var resume := _action(hub, "resume")
	suite.assert_true(resume != null and not resume.disabled, "narrative persistence keeps the native Resume command available")
	if resume != null and not resume.disabled:
		resume.pressed.emit()
		_freeze(main)
		player = main.get_node("CombatRoom01/Player")
		host = main.get_node("RunRuntimeHost")
		suite.assert_true(not hub.is_hub_visible(), "actual native Resume succeeds after the narrative cost")
		suite.assert_true(player.full_player_replay_snapshot() == player_after, "cold Resume retains the full post-cost Replay: " + str(_differences(player.full_player_replay_snapshot(), player_after, "player")))
		suite.assert_true(_json_equal(host.runtime_snapshot(), run_after), "cold Resume retains the resulting canonical Run")
		suite.assert_equal(GameState.profile_runtime_service().snapshot(), profile_after, "cold Resume cannot repeat the choice or change Profile revision")
	await _dispose(main)
	suite.finish(get_tree())

