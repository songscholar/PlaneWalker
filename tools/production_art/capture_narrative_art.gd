extends "res://tools/production_art/capture_enemy_atlases.gd"

const ArtCatalog := preload("res://scripts/presentation/ui_art_catalog.gd")


func _run() -> void:
	var suite := TestSuiteScript.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(640, 360)
	backdrop.color = Color("#111619")
	viewport.add_child(backdrop)
	var sprites: Array[Sprite2D] = []
	for index: int in range(ArtCatalog.REQUIRED_GENERATED.npc_portraits.size()):
		sprites.append(_sprite(viewport, &"npc_portraits", ArtCatalog.REQUIRED_GENERATED.npc_portraits[index], Vector2(44 + index * 79, 50)))
	for index: int in range(ArtCatalog.REQUIRED_GENERATED.ending_art.size()):
		var position := Vector2(104 + index % 3 * 216, 174 + index / 3 * 112)
		sprites.append(_sprite(viewport, &"ending_art", ArtCatalog.REQUIRED_GENERATED.ending_art[index], position))
	await _capture_phases(suite, viewport, sprites, "narrative")
	for sprite: Sprite2D in sprites:
		sprite.queue_free()
	await get_tree().process_frame
	sprites.clear()
	for index: int in range(ArtCatalog.REQUIRED_GENERATED.controls.size()):
		sprites.append(_sprite(viewport, &"controls", ArtCatalog.REQUIRED_GENERATED.controls[index], Vector2(44 + index % 11 * 55, 120 + index / 11 * 112)))
	await _capture_phases(suite, viewport, sprites, "controls")
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _sprite(viewport: SubViewport, family: StringName, identity: String, position: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = load(ArtCatalog.texture_path(family, StringName(identity)))
	sprite.hframes = 4
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = position
	viewport.add_child(sprite)
	return sprite


func _capture_phases(suite, viewport: SubViewport, sprites: Array[Sprite2D], family: String) -> void:
	for phase: int in range(4):
		for sprite: Sprite2D in sprites:
			sprite.frame = phase
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		for sprite: Sprite2D in sprites:
			_assert_enemy_pixels(suite, pixels, sprite, 32)
		var path := "res://build/visual-evidence/narrative-art/%s-phase-%d.png" % [family, phase]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		suite.assert_equal(pixels.save_png(path), OK, "narrative and command source pixels retained")
