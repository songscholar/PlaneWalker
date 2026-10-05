extends "res://tests/visual/p14_room_visual_contract_test.gd"

const CAPTURE_SIZES := [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(2560, 1080)]
const CAPTURE_ROWS := [
	["room_combat_pillared_hall", "floor_ruins_of_remnant"],
	["room_combat_void_grove", "floor_void_forest"],
	["room_combat_clockwork", "floor_time_rift"],
	["room_boss_forge_colossus", "floor_plane_forge"],
	["room_boss_void_throne", "floor_throne_of_void"],
	["room_treasure_vault", "floor_ruins_of_remnant"],
	["room_shop_wayfarer_tent", "floor_void_forest"],
	["room_rest_campfire", "floor_plane_forge"],
	["room_event_mirror_hall", "floor_time_rift"],
]


func _run() -> void:
	var suite := TestSuiteScript.new()
	var templates := {}
	var floors := {}
	for row: Dictionary in _load_json_array(TEMPLATE_PATH):
		templates[row.id] = row
	for row: Dictionary in _load_json_array(FLOOR_PATH):
		floors[row.id] = row
	for row: Array in CAPTURE_ROWS:
		for size: Vector2i in CAPTURE_SIZES:
			var viewport := SubViewport.new()
			viewport.size = size
			viewport.world_2d = World2D.new()
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(viewport)
			var room := _bound_scene(templates[row[0]], floors[row[1]], true)
			suite.assert_true(room != null, "actual native room binds for capture")
			if room == null:
				viewport.queue_free()
				continue
			viewport.add_child(room)
			var camera := Camera2D.new()
			camera.position = Vector2(320, 180)
			var factor := minf(float(size.x) / 640.0, float(size.y) / 360.0)
			camera.zoom = Vector2.ONE * factor
			viewport.add_child(camera)
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image()
			suite.assert_true(pixels != null and not pixels.is_empty() and pixels.get_size() == size, "capture has exact requested raster dimensions")
			if pixels != null and not pixels.is_empty():
				var first: Sprite2D = room.get_node("RoomArtwork/FloorTiles").get_child(0)
				var transform := first.get_global_transform_with_canvas()
				suite.assert_true(transform.origin.is_equal_approx((Vector2(size) - Vector2(640, 360) * factor) * 0.5), "arena remains centered with ultrawide side margins")
				suite.assert_true(transform.x.is_equal_approx(Vector2(factor, 0)), "native room artwork retains aspect ratio")
				var tiles: Node2D = room.get_node("RoomArtwork/FloorTiles")
				_assert_sprite_raster(suite, pixels, tiles.get_child(105), "floor tile", row[0])
				_assert_sprite_raster(suite, pixels, room.get_node("RoomArtwork/Masonry").get_child(0), "masonry", row[0])
				_assert_sprite_raster(suite, pixels, room.get_node("RoomArtwork/DoorwayWest"), "west doorway", row[0])
				_assert_sprite_raster(suite, pixels, room.get_node("RoomArtwork/DoorwayEast"), "east doorway", row[0])
				var landmark: Sprite2D = room.get_node("RoomArtwork/Landmark")
				_assert_sprite_raster(suite, pixels, landmark, "category landmark", row[0])
				var output := "res://build/visual-evidence/native-rooms/%s-%dx%d.png" % [row[0], size.x, size.y]
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
				suite.assert_equal(pixels.save_png(output), OK, "native room raster screenshot retained")
			viewport.queue_free()
			await get_tree().process_frame
			await get_tree().process_frame
	suite.finish(get_tree())


func _assert_sprite_raster(suite, pixels: Image, sprite: Sprite2D, label: String, room_id: String) -> void:
	var source := sprite.texture.get_image()
	var region := sprite.region_rect if sprite.region_enabled else Rect2(Vector2(sprite.frame_coords) * sprite.get_rect().size, sprite.get_rect().size)
	var transform := sprite.get_global_transform_with_canvas()
	var samples := 0
	var mismatches := 0
	for y: int in range(int(region.size.y)):
		for x: int in range(int(region.size.x)):
			var expected := source.get_pixel(int(region.position.x) + x, int(region.position.y) + y)
			if expected.a < 1.0:
				continue
			var target := Vector2i(transform * (sprite.get_rect().position + Vector2(x + 0.5, y + 0.5)))
			var rendered := pixels.get_pixelv(target)
			if absf(expected.r - rendered.r) > 0.005 or absf(expected.g - rendered.g) > 0.005 or absf(expected.b - rendered.b) > 0.005:
				mismatches += 1
			samples += 1
	suite.assert_true(samples >= 256 and mismatches == 0, "%s/%s renders %s source pixels: %d/%d mismatch" % [room_id, pixels.get_size(), label, mismatches, samples])
