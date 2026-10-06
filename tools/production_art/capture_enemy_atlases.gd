extends "res://tests/visual/p14_room_visual_contract_test.gd"

const CAPTURE_ROWS := [
	["room_combat_pillared_hall", "floor_ruins_of_remnant"],
	["room_combat_void_grove", "floor_void_forest"],
	["room_combat_clockwork", "floor_time_rift"],
	["room_boss_forge_colossus", "floor_plane_forge"],
]
const PHASE_NAMES := ["idle", "warning", "active", "recovery"]


func _run() -> void:
	var suite := TestSuiteScript.new()
	var templates := {}
	var floors := {}
	for row: Dictionary in _load_json_array(TEMPLATE_PATH):
		templates[row.id] = row
	for row: Dictionary in _load_json_array(FLOOR_PATH):
		floors[row.id] = row
	var enemies := _load_json_array("res://data/content_packs/base/content/enemies.json")
	for row: Array in CAPTURE_ROWS:
		var definitions: Array = enemies.filter(func(enemy: Dictionary) -> bool: return enemy.floor_id == row[1])
		for phase: int in range(4):
			var viewport := SubViewport.new()
			viewport.size = Vector2i(640, 360)
			viewport.world_2d = World2D.new()
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(viewport)
			var room := _bound_scene(templates[row[0]], floors[row[1]], true)
			viewport.add_child(room)
			var sprites: Array[Sprite2D] = []
			for index: int in range(definitions.size()):
				var identity: String = definitions[index].id
				var packed := load("res://data/content_packs/base/assets/enemies/launch/enemy_%s.tscn" % identity) as PackedScene
				var actor := packed.instantiate() as CharacterBody2D
				actor.position = Vector2(80 + index * 88, 180)
				viewport.add_child(actor)
				var sprite := actor.get_node("Sprite2D") as Sprite2D
				sprite.frame = phase
				sprites.append(sprite)
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image()
			suite.assert_true(pixels != null and not pixels.is_empty(), "native enemy preview is nonblank")
			for sprite: Sprite2D in sprites:
				_assert_enemy_pixels(suite, pixels, sprite)
			var output := "res://build/visual-evidence/enemy-refresh/%s-%s.png" % [row[1], PHASE_NAMES[phase]]
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
			suite.assert_equal(pixels.save_png(output), OK, "native enemy phase preview retained")
			viewport.queue_free()
			await get_tree().process_frame
			await get_tree().process_frame
	suite.finish(get_tree())


func _assert_enemy_pixels(suite, pixels: Image, sprite: Sprite2D) -> void:
	var source := sprite.texture.get_image()
	var region := Rect2(Vector2(sprite.frame_coords) * sprite.get_rect().size, sprite.get_rect().size)
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
	suite.assert_true(samples >= 80 and mismatches == 0, "%s/%s shows production pixels: %d/%d mismatch" % [sprite.texture.resource_path, sprite.frame, mismatches, samples])
