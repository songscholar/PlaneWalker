extends "res://tools/production_art/capture_enemy_atlases.gd"

const Catalog := preload("res://scripts/presentation/ui_art_catalog.gd")
const Events := preload("res://scripts/dungeon/dungeon_event_definition.gd")


func _run() -> void:
	var suite := TestSuiteScript.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var sprites: Array[Sprite2D] = []
	for index: int in range(Events.EVENT_IDS.size()):
		var identity: String = Events.EVENT_IDS[index]
		var sprite := Sprite2D.new()
		sprite.texture = load(Catalog.texture_path(&"event_art", StringName(identity)))
		sprite.hframes = 4
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(53 + index % 6 * 106, 54 + index / 6 * 110)
		viewport.add_child(sprite)
		sprites.append(sprite)
	for phase: int in range(4):
		for sprite: Sprite2D in sprites:
			sprite.frame = phase
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		for sprite: Sprite2D in sprites:
			_assert_enemy_pixels(suite, pixels, sprite)
		var path := "res://build/visual-evidence/event-art/phase-%d.png" % phase
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		suite.assert_equal(pixels.save_png(path), OK, "all event vignette pixels retained")
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())
