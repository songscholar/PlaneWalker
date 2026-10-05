extends "res://tests/integration/combat/void_auxiliary_lifecycle_test.gd"


func _run() -> void:
	suite = Suite.new()
	var context := _open_case(true, Vector2(900, 500))
	suite.assert_close(context.actor.get_node("Hurtbox").receive_hit(_damage(context.player, 22, 1500.0)), 900.0, "actual body damage enters native third phase")
	_frames(context, 120)
	context.player.global_position = Vector2(320, 270)
	_request(context, "voidking_void_end")
	var warning: Dictionary = context.actor.launch_runtime_snapshot().runtime.action
	suite.assert_equal(warning.committed_geometry[0].origin, {"x": 0.0, "y": 90.0}, "real moved Boss warns room-relative half")
	var hp := float(context.player.health.current_hp)
	_frames(context, 199)
	suite.assert_close(context.player.health.current_hp, hp, "opposite half corridor stays safe through complete80framewarning")
	var telegraphs: Node = context.actor.get_node_or_null("LaunchTelegraphs")
	suite.assert_true(telegraphs != null and telegraphs.get_child_count() == 3, "actual half warning projects all three marked primitives before damage")
	await _capture_half(context, "warning")
	context.player.global_position = Vector2(320, 90)
	var player_before: Dictionary = context.player.health.transaction_snapshot()
	var actor_before: Dictionary = context.actor.launch_runtime_snapshot()
	var effects_before: Dictionary = context.effects.snapshot()
	var ticket: Dictionary = context.bridge.begin_frame(200)
	suite.assert_true(context.bridge.prepare_frame(ticket), "actual half damage and three finite zones prepare")
	suite.assert_close(context.player.health.current_hp, hp - 55.0, "marked half delivers actual55Healthloss once")
	suite.assert_true(context.bridge.rollback_frame(ticket), "late native frame refusal compensates half cast")
	suite.assert_true(context.player.health.restore_transaction_snapshot(player_before), "outerPlayerHealth restores refused half damage")
	suite.assert_equal(context.actor.launch_runtime_snapshot(), actor_before, "refused half restores exact Boss geometry and parity")
	suite.assert_equal(context.effects.snapshot(), effects_before, "refused half restores finite zones and native effects")
	_frames(context, 200)
	suite.assert_close(context.player.health.current_hp, hp - 55.0, "same marked half frame retries once after compensation")
	var zones: Array = context.effects.semantic_snapshot().zones.filter(func(row: Dictionary): return row.action_id == "voidking_void_end")
	suite.assert_equal(zones.size(), 3, "actual half and two circles create exactly three finite zones")
	for zone: Dictionary in zones:
		suite.assert_equal(zone.lifetime_frames, 300, "actual half zone uses authoredTTL300")
		suite.assert_equal(zone.expires_frame, 499, "zone lifetime ends after exactly300accepted active frames")
	context.player.global_position = Vector2(320, 270)
	await _capture_half(context, "active")
	await _cold_owner(context)
	_frames(context, 201)
	suite.assert_close(context.player.health.current_hp, hp - 55.0, "normalnativecontinuation after capture and coldsave retains safe route")
	_frames(context, 250)
	suite.assert_true(context.actor.get_node("LaunchTelegraphs").get_child_count() == 0, "primary action warning retires before finite half zone")
	await _capture_half(context, "persistent")
	context.player.global_position = Vector2(900, 500)
	_frames(context, 499)
	suite.assert_equal(context.effects.semantic_snapshot().zones.filter(func(row: Dictionary): return row.action_id == "voidking_void_end").size(), 3, "zones retain their last authored lifetime frame")
	_frames(context, 500)
	suite.assert_true(context.effects.semantic_snapshot().zones.filter(func(row: Dictionary): return row.action_id == "voidking_void_end").is_empty(), "zones retire at finite exclusiveTTL300boundary")
	await _close_case(context)
	suite.finish(get_tree())


func _capture_half(context: Dictionary, pose: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/void-half-native-screenshots"))
	for size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(2560, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.world_2d = get_viewport().world_2d
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		add_child(viewport)
		var camera := Camera2D.new()
		viewport.add_child(camera)
		camera.position = Vector2(320, 180)
		camera.zoom = Vector2.ONE * minf(float(size.x) / 640.0, float(size.y) / 360.0)
		camera.make_current()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		var scale_value := minf(float(size.x) / 640.0, float(size.y) / 360.0)
		var inset := (Vector2(size) - Vector2(640, 360) * scale_value) * 0.5
		for world_point: Vector2 in [Vector2(64, 24), Vector2(320, 24), Vector2(576, 24)]:
			var screen := Vector2i(world_point * scale_value + inset)
			var color := image.get_pixel(screen.x, screen.y)
			suite.assert_true(color.r > color.g + 0.07, "actualmarkedhalf danger reaches left/center/right raster before damage at" + str(size))
		var safe_point := Vector2i(Vector2(320, 318) * scale_value + inset)
		var safe_color := image.get_pixel(safe_point.x, safe_point.y)
		suite.assert_true(safe_color.r <= safe_color.g + 0.07, "oppositecorridor has no false dangerfill at" + str(size))
		if size.x > 640.0 * scale_value:
			var margin_color := image.get_pixel(int(inset.x * 0.5), int(90.0 * scale_value + inset.y))
			suite.assert_true(margin_color.r <= margin_color.g + 0.07, "ultrawide margins contain no out-of-room danger projection")
		var danger_pixels := 0
		var data := image.get_data()
		for index: int in range(0, data.size(), 4):
			if int(data[index]) > 110 and int(data[index + 2]) > 80 and int(data[index + 1]) < 170:
				danger_pixels += 1
		suite.assert_true(danger_pixels > 1000, "native halfwarning/zone raster remains nonblank at" + str(size))
		suite.assert_equal(image.save_png("res://build/void-half-native-screenshots/%s-%dx%d.png" % [pose, size.x, size.y]), OK, "native marked half capture writes")
		viewport.queue_free()
		await get_tree().process_frame
