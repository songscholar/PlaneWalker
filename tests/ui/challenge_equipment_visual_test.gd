extends "res://tests/integration/progression/challenge_equipment_test.gd"


func _run() -> void:
	suite = Suite.new()
	registry = Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	catalog = Factory.from_registry(registry).context.catalog
	var rewards := Rewards.new()
	rewards.configure()
	var selected := rewards.projection(_reward_collection(rewards), {"profile_id": "visual", "save_domain": "base", "content_snapshot": Content.snapshot(registry)})
	var meta: Dictionary = ProjectionScript.from_profile(Fixtures.profile(catalog), catalog, selected).context.projection
	var screenshots := OS.get_cmdline_user_args().has("--challenge-equipment-screenshots")
	for resolution: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.world_2d = World2D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		var background := ColorRect.new()
		background.color = Color(0.055, 0.08, 0.09)
		background.size = Vector2(resolution)
		viewport.add_child(background)
		var stage := Node2D.new()
		stage.scale = Vector2.ONE * (float(resolution.x) / 640.0)
		viewport.add_child(stage)
		var characters := ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]
		var weapons := ["sword", "bow", "gun", "staff", "gauntlets"]
		var players: Array[Node] = []
		for index: int in range(5):
			var player: Node = PlayerScene.instantiate()
			player.process_mode = Node.PROCESS_MODE_DISABLED
			stage.add_child(player)
			player.set_physics_process(false)
			player.position = Vector2(90 + index * 115, 185)
			suite.assert_true(player.configure_loadout(_config(characters[index], weapons[index], ["stop", "rewind"], meta)), "actual five-character five-weapon equipped presentation constructs")
			var proxy := PixelProxy.new()
			proxy.process_mode = Node.PROCESS_MODE_ALWAYS
			player.add_child(proxy)
			suite.assert_true(proxy.bind_actor(player), "production proxy binds equipped actor")
			proxy.call("_advance_animation", 0.0)
			suite.assert_true(Rules.same(proxy.get_snapshot_for_test().challenge_rewards, selected.presentation), "all equipped presentation kinds remain frozen")
			players.append(player)
		await get_tree().process_frame
		await get_tree().process_frame
		if screenshots:
			await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image()
			suite.assert_true(pixels != null and not pixels.is_empty(), "equipped native actors render a real bitmap")
			if pixels != null and not pixels.is_empty():
				for player: Node in players:
					var colors := {}
					var center: Vector2 = player.global_position
					var factor := float(resolution.x) / 640.0
					for y: int in range(int(center.y - 36 * factor), int(center.y + 24 * factor), maxi(1, int(factor))):
						for x: int in range(int(center.x - 26 * factor), int(center.x + 26 * factor), maxi(1, int(factor))):
							colors[pixels.get_pixel(x, y).to_rgba32()] = true
					suite.assert_true(colors.size() > 8, "each actual tinted atlas weapon and earned badges is nonblank")
				var output := "res://build/p26-equipment-screenshots/native-%dx%d.png" % [resolution.x, resolution.y]
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
				suite.assert_equal(pixels.save_png(output), OK, "equipped native presentation raster retained")
		viewport.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	suite.finish(get_tree())
