extends "res://tests/ui/mode_finish_test.gd"

const ARENA_RESOLUTIONS := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]


func _run() -> void:
	_suite = Suite.new()
	_registry = Registry.new()
	_registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var original_size: Vector2i = get_viewport().size
	for row: Array in MODE_ROWS:
		_seed_main_profile("arena-framing-" + str(row[0]))
		var main := Main.instantiate()
		add_child(main)
		await _frames(2)
		var original_camera := get_viewport().get_camera_2d()
		var hub: Node = main.get_node("HubFlowCoordinator")
		_suite.assert_true(hub.travel("hub_council").ok and hub.open_function("gateway").ok, "production gateway owns arena admission " + str(row[0]))
		_daily_action(hub.panel_view(), str(row[0])).pressed.emit()
		var coordinator: Node = main.get_node(str(row[1]))
		_daily_action(coordinator.panel(), "start").pressed.emit()
		await _frames(3)
		var flow: Node = coordinator.runtime()
		if row[0] == "endless":
			var host: Node = flow.runtime_host()
			var admitted := false
			for route: Dictionary in host.route_choices():
				if route.room_type in ["combat", "elite"]:
					admitted = host.select_route(StringName(route.edge_id), int(host.runtime_snapshot().revision)).ok
					break
			_suite.assert_true(admitted, "Endless framing uses an actual admitted native combat room")
			flow.dungeon_flow().refresh(true)
			host.set_process(false)
			flow.dungeon_flow().set_process(false)
		flow.set_process(false)
		var player: Node2D = flow.current_player()
		player.set_physics_process(false)
		await _frames(2)
		await get_tree().create_timer(0.3, true, false, true).timeout
		var preserved: Dictionary = flow.snapshot()
		var player_transform := player.global_transform
		var room: Node2D
		if row[0] == "endless":
			room = flow.get("_scenes").active_room()
		elif row[0] == "boss_rush":
			room = flow.get("_room")
		else:
			room = flow.get("_stage").get_child(0) as Node2D
		_suite.assert_true(room != null and room.find_child("RoomArtwork", true, false) != null, "actual mode arena renders authored bitmap floor " + str(row[0]))
		_suite.assert_true(_has_actor_texture(player), "actual mode Player exposes its authored sprite texture " + str(row[0]))
		if row[0] != "endless":
			_suite.assert_true(_has_actor_texture(flow.current_boss()), "actual mode Boss exposes its authored sprite texture " + str(row[0]))
		var backdrop := flow.find_child("ModeArenaBackdrop", true, false) as TextureRect
		_suite.assert_true(backdrop != null and backdrop.texture != null, "actual arena owns a full-viewport bitmap backdrop " + str(row[0]))
		for resolution: Vector2i in ARENA_RESOLUTIONS:
			_resize_arena(resolution)
			await _frames(3)
			var camera := get_viewport().get_camera_2d()
			_suite.assert_true(camera != null and flow.is_ancestor_of(camera), "active mode owns actual viewport camera " + str([row[0], resolution]))
			var transform := get_viewport().get_final_transform() * get_viewport().get_canvas_transform()
			var arena := Rect2(transform * Vector2.ZERO, transform * Vector2(640, 360) - transform * Vector2.ZERO)
			var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
			_suite.assert_true(bounds.grow(1).encloses(arena) and arena.get_center().distance_to(bounds.get_center()) <= 1.0, "entire native arena is centered without clipping " + str([row[0], resolution]))
			if backdrop != null:
				var backdrop_rect := backdrop.get_global_rect()
				var final := get_viewport().get_final_transform()
				var pixels := Rect2(final * backdrop_rect.position, final * backdrop_rect.end - final * backdrop_rect.position)
				_suite.assert_true(pixels.grow(1).encloses(bounds), "bitmap backdrop covers viewport edges " + str([row[0], resolution, backdrop_rect, final, pixels]))
			_suite.assert_equal(player.global_transform, player_transform, "resize never changes actual Player physics transform " + str([row[0], resolution]))
			_suite.assert_equal(flow.snapshot(), preserved, "resize never changes actual mode domain snapshot " + str([row[0], resolution]))
			await _capture_arena(str(row[0]), resolution)
		_suite.assert_true(coordinator.return_to_hub().ok, "arena camera returns through durable production mode exit " + str(row[0]))
		await _frames(2)
		_suite.assert_true(get_viewport().get_camera_2d() == original_camera, "mode exit restores original viewport camera " + str(row[0]))
		main.queue_free()
		await _frames(2)
		_resize_arena(original_size)
	await get_tree().create_timer(0.3, true, false, true).timeout
	_suite.finish(get_tree())


func _resize_arena(resolution: Vector2i) -> void:
	var viewport := get_viewport() as SubViewport
	viewport.size = resolution
	var scale := maxi(1, floori(minf(float(resolution.x) / 640.0, float(resolution.y) / 360.0)))
	viewport.size_2d_override = resolution / scale
	viewport.size_2d_override_stretch = true


func _has_actor_texture(actor: Node) -> bool:
	for sprite: Node in actor.find_children("*", "Sprite2D", true, false):
		if sprite.texture != null and sprite.texture.resource_path.begins_with("res://assets/production/"):
			return true
	return false


func _capture_arena(mode: String, resolution: Vector2i) -> void:
	if not OS.get_cmdline_user_args().has("--arena-framing-screenshots"):
		return
	await RenderingServer.frame_post_draw
	var pixels := get_viewport().get_texture().get_image()
	_suite.assert_true(pixels != null and not pixels.is_empty() and pixels.get_size() == resolution, "actual arena framebuffer has requested pixel extent " + str([mode, resolution]))
	if pixels == null or pixels.is_empty():
		return
	var gray_count := 0
	var colors := {}
	for x: int in range(0, pixels.get_width(), maxi(1, pixels.get_width() / 32)):
		for y: int in range(0, pixels.get_height(), maxi(1, pixels.get_height() / 18)):
			var color := pixels.get_pixel(x, y)
			colors[color.to_rgba32()] = true
			if color.is_equal_approx(Color(0.3, 0.3, 0.3, 1.0)):
				gray_count += 1
	_suite.assert_true(gray_count == 0 and colors.size() > 12, "actual arena pixels contain artwork and no uncovered default gray " + str([mode, resolution]))
	var path := "res://build/ui-mode-arena-screenshots/%s-%dx%d.png" % [mode, resolution.x, resolution.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	_suite.assert_equal(pixels.save_png(path), OK, "mode arena render evidence is retained " + str([mode, resolution]))
