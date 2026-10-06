extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const ArtCatalog := preload("res://scripts/presentation/ui_art_catalog.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var panel: Control = main.get_node_or_null("ChallengeRewardsLayer/ChallengeRewardsPanel")
	suite.assert_true(panel != null, "production Main installs earned challenge equipment controls")
	if panel == null:
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var service: RefCounted = GameState.profile_runtime_service()
	var absent: Dictionary = service.claim_mode_rewards("boss_rush_carried", int(service.snapshot().revision))
	suite.assert_equal(absent.code, &"NOT_FOUND", "Main registers the actual durable Boss Rush source before it has a result")
	var fixture: Dictionary = service.snapshot()
	fixture.statistics.finished_runs = 1
	fixture.statistics.victories = 1
	var save: RefCounted = service.get("_save")
	suite.assert_true(save.save_profile("slot_1", "base", {"meta_profile_state": fixture}).ok, "test seeds an eligible physical Profile")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.set("_profile_runtime", null)
	main = Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	service = GameState.profile_runtime_service()
	panel = main.get_node("ChallengeRewardsLayer/ChallengeRewardsPanel")
	var hub: Node = main.get_node("HubFlowCoordinator")
	var coordinator: Node = main.get_node("BossRushCoordinator")
	var flow: Node = coordinator.runtime()
	suite.assert_true(hub.open_function("gateway").ok, "actual gateway owns mode selection")
	_action(hub.panel_view(), "boss_rush").pressed.emit()
	coordinator.panel().action_controls()[0].pressed.emit()
	for index: int in range(5):
		for _frame: int in range(3):
			await get_tree().physics_frame
		flow.current_boss().health.lose_health(100000, flow.current_player())
		await get_tree().process_frame
		await get_tree().process_frame
		if index < 4:
			suite.assert_true(flow.choose_reward(2).ok, "actual carried victory accepts recovery reward")
	suite.assert_true(coordinator.return_to_hub().ok, "durable five-Boss victory returns through production Main")
	suite.assert_true(service.challenge_reward_collection().owned_ids.has("walker_proof"), "mode exit automatically claims authenticated durable rewards")
	suite.assert_true(hub.travel("hub_rift").ok and hub.open_function("gallery").ok, "actual gallery opens equipment collection")
	var entry := _action(hub.panel_view(), "challenge_rewards")
	suite.assert_true(entry != null, "gallery contains earned challenge collection entry")
	if entry != null:
		entry.pressed.emit()
		await get_tree().process_frame
		suite.assert_true(panel.visible and not hub.is_hub_visible() and FocusCoordinator.active_scope() == panel, "challenge collection exclusively owns controller focus")
		suite.assert_true(main.call("_content_mutation_locked"), "open challenge collection binds source content")
		_action(panel, "synchronize").pressed.emit()
		suite.assert_true(not _action(panel, "reward:walker_proof").disabled, "duplicate reward synchronization restores usable equipment controls")
		var equip := _action(panel, "reward:walker_proof")
		suite.assert_true(equip is CheckBox and not equip.button_pressed, "owned proof exposes a persistent equipment toggle")
		var proof_row := panel.find_child("ChallengeRewardRow_walker_proof", true, false)
		var artwork: TextureRect = proof_row.find_child("ChallengeRewardArtwork", true, false) if proof_row != null else null
		suite.assert_true(artwork != null and artwork.texture is AtlasTexture and artwork.texture.atlas.resource_path == ArtCatalog.texture_path(&"challenge_rewards", &"walker_proof"), "earned proof displays its authored canonical pixel atlas")
		if equip != null:
			var retired: Callable = equip.pressed.get_connections()[0].callable
			save = service.get("_save")
			save.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
			equip.pressed.emit()
			suite.assert_true(not service.challenge_reward_collection().equipped_ids.has("walker_proof") and panel.error_label.visible, "failed durable equipment write preserves selection and exposes retry")
			save.set_fault_injector(Callable())
			_action(panel, "reward:walker_proof").pressed.emit()
			suite.assert_true(service.challenge_reward_collection().equipped_ids.has("walker_proof"), "retry equips authored reward through actual Profile")
			var revision: int = service.snapshot().revision
			retired.call()
			suite.assert_equal(service.snapshot().revision, revision, "retired collection callback cannot repeat a published mutation")
		var visual_dir := OS.get_environment("PLANEWALKER_CHALLENGE_REWARDS_VISUAL_OUTPUT")
		if not visual_dir.is_empty():
			DirAccess.make_dir_recursive_absolute(visual_dir)
			for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
				DisplayServer.window_set_size(resolution)
				await get_tree().process_frame
				await RenderingServer.frame_post_draw
				suite.assert_equal(get_viewport().get_texture().get_image().save_png(visual_dir.path_join("challenge-rewards-%dx%d.png" % [resolution.x, resolution.y])), OK, "native equipment framebuffer captures supported size")
		var cancel := InputEventJoypadButton.new()
		cancel.button_index = JOY_BUTTON_B
		cancel.pressed = true
		suite.assert_true(panel.handle_input(cancel), "controller cancel closes challenge collection")
		suite.assert_true(not panel.visible and hub.is_hub_visible() and hub.panel_view().visible and FocusCoordinator.active_scope() == hub.panel_view(), "controller return restores actual gallery and focus")
		suite.assert_true(not main.call("_content_mutation_locked"), "closed collection releases content mutation lock")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _action(panel: Control, id: String) -> Button:
	for action: Control in panel.action_controls():
		if str(action.get_meta("action_id", "")) == id:
			return action as Button
	return null
