extends "res://tests/integration/combat/void_auxiliary_lifecycle_test.gd"


func _run() -> void:
	suite = Suite.new()
	var context := _open_case(false, Vector2(900, 500))
	suite.assert_true(context.player.configure_loadout({"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "weapon_profile": context.player._weapon_profile_catalog_definition(&"sword_launch_v1"), "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 42}), "actual Player frame uses complete Launch loadout")
	suite.assert_true(context.player.configure_hostile_frame_participant(context.bridge), "actual Player frame owns production Void bridge")
	suite.assert_equal(context.actor.get_node("Hurtbox").receive_hit(_damage(context.player, 50, 2500.0)), 1500.0, "actual authenticated body hit enters phase two")
	await _player_frames(context, 60)
	context.player.global_position = Vector2(350, 180)
	context.player.health.acquire_invulnerability_source(&"pickup-player-frame")
	_request(context, "voidking_shard_projection")
	await _player_frames(context, 88)
	var state: Dictionary = context.actor.native_void_auxiliary_snapshot()
	suite.assert_equal(state.pickups.size(), 4, "actual accepted Player frames materialize four finite shard pickups")
	context.player.global_position = Vector2(float(state.pickups[0].position.x), float(state.pickups[0].position.y))
	context.player.time_manager.energy = 98.0
	var publications: Array = []
	context.player.time_manager.energy_changed.connect(func(current: float, _maximum: float): publications.append(current))
	var player_before: Dictionary = context.player.weapon_replay_snapshot()
	var owner_before: Dictionary = context.actor.launch_runtime_snapshot()
	var effects_before: Dictionary = context.effects.snapshot()
	context.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", true)
	suite.assert_true(not suite.expect_rejected_player_frame(context.player), "late actual World refusal rejects whole native pickup frame")
	suite.assert_equal(context.player.weapon_replay_snapshot(), player_before, "actual Player rollback compensates energy revision and event buffer")
	suite.assert_equal(context.actor.launch_runtime_snapshot(), owner_before, "actual Player rollback compensates pickup once only receipt")
	suite.assert_equal(context.effects.snapshot(), effects_before, "actual Player rollback compensates native effect claims")
	suite.assert_true(publications.is_empty(), "refused actual Player frame publishes no early energy signal")
	context.player.world_payload_authority.set("_frame_transaction_commit_fault_for_test", false)
	await _player_frames(context, 89)
	suite.assert_equal(context.player.time_manager.energy, 100.0, "same actual Player frame retries capped pickup energy once")
	suite.assert_true(not publications.is_empty() and publications.back() == 100.0, "accepted actual Player frame publishes final native energy")
	await _cold_owner(context)
	await _capture_pickups(context)
	var ownership: Dictionary = context.player.loadout_runtime.snapshot()
	suite.assert_true(context.player.try_action(&"time_slot_1"), "normal Stop command remains available against native Void")
	await _player_frames(context, 119)
	suite.assert_equal(context.player.loadout_runtime.snapshot(), ownership, "native auxiliary encounter retains paid time and weapon ownership")
	suite.assert_true(context.player.configure_hostile_frame_participant(null), "actual Player detaches finished native auxiliary bridge")
	await _close_case(context)
	suite.finish(get_tree())


func _player_frames(context: Dictionary, through: int) -> void:
	for frame: int in range(int(context.frame) + 1, through + 1):
		var accepted: bool = context.player.advance_action_frame({"aim": Vector2.RIGHT})
		suite.assert_true(accepted, "normal actual Player frame %d commits native Void" % frame)
		if not accepted:
			return
		context.frame = frame
		await get_tree().physics_frame


func _capture_pickups(context: Dictionary) -> void:
	if OS.get_environment("PLANEWALKER_CAPTURE_NATIVE") != "1" or DisplayServer.get_name() == "headless":
		return
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(2560, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.world_2d = context.actor.get_world_2d()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var scale_value := minf(float(resolution.x) / 640.0, float(resolution.y) / 360.0)
		var inset := (Vector2(resolution) - Vector2(640, 360) * scale_value) * 0.5
		viewport.canvas_transform = Transform2D(0.0, Vector2.ONE * scale_value, 0.0, inset)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		suite.assert_equal(pixels.get_size(), resolution, "actual native pickup raster has supported resolution")
		for pickup: Node2D in context.actor.get_node("VoidAuxiliaryPickups").get_children():
			var colors := {}
			var center := Vector2i(pickup.global_position * scale_value + inset)
			var extent := ceili(12.0 * scale_value)
			for y: int in range(center.y - extent, center.y + extent):
				for x: int in range(center.x - extent, center.x + extent):
					colors[pixels.get_pixel(x, y).to_rgba32()] = true
			suite.assert_true(colors.size() >= 5, "actual native pickup artwork is nonblank at supported resolution")
		var path := "res://build/visual-evidence/void-arena/native-shard-pickups-%dx%d.png" % [resolution.x, resolution.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		suite.assert_equal(pixels.save_png(path), OK, "actual native pickup raster is retained")
		viewport.queue_free()
		await get_tree().process_frame
