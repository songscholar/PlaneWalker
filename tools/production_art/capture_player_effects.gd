extends "res://tools/production_art/capture_enemy_atlases.gd"

const PlayerFixture := preload("res://tests/presentation/player_effect_atlas_test.gd")
const Proxy := preload("res://scripts/presentation/pixel_proxy_actor.gd")
const EFFECT_CASES := ["sword", "bow", "gun", "staff", "time_stop", "cast"]


func _run() -> void:
	var suite := TestSuiteScript.new()
	var template: Dictionary = {}
	var floor_row: Dictionary = {}
	for row: Dictionary in _load_json_array(TEMPLATE_PATH):
		if row.id == "room_combat_pillared_hall":
			template = row
	for row: Dictionary in _load_json_array(FLOOR_PATH):
		if row.id == "floor_ruins_of_remnant":
			floor_row = row
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	viewport.add_child(_bound_scene(template, floor_row, true))
	var stage := Node2D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(stage)
	var proxies: Array[Node2D] = []
	var sprites: Array[Sprite2D] = []
	for index: int in range(EFFECT_CASES.size()):
		var actor := PlayerFixture.PresentationPlayer.new()
		actor.position = Vector2(48 + index * 104, 180)
		actor.weapon_snapshot.weapon_id = EFFECT_CASES[index]
		stage.add_child(actor)
		var proxy := Proxy.new()
		proxy.name = "PixelProxyActor"
		actor.add_child(proxy)
		suite.assert_true(proxy.bind_actor(actor), "player effect preview binds existing presentation")
		proxy.set_feedback_options(true, false)
		if EFFECT_CASES[index] in ["time_stop", "cast"]:
			proxy.play_action(StringName(EFFECT_CASES[index]), 0.22)
		else:
			proxy.play_weapon_cue(&"preview_attack", &"preview_effect")
		proxies.append(proxy)
		sprites.append(proxy.get_node("ProductionEffectAtlas"))
	for phase: int in range(4):
		for proxy: Node2D in proxies:
			proxy.advance_animation_for_test(0.0 if phase == 0 else 0.056)
		for sprite: Sprite2D in sprites:
			suite.assert_true(sprite.visible and sprite.frame == phase, "rendered preview displays the requested atlas phase")
		await _capture_effects(suite, viewport, sprites, "phase-%d" % phase)
	for proxy: Node2D in proxies:
		proxy.set_feedback_options(true, true)
	await _capture_effects(suite, viewport, sprites, "reduced-motion")
	proxies[2].set_feedback_options(false, true)
	suite.assert_true(not sprites[2].visible, "disabled flash suppresses rendered muzzle")
	await _capture_effects(suite, viewport, sprites, "flash-disabled")
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _capture_effects(suite, viewport: SubViewport, sprites: Array[Sprite2D], suffix: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	suite.assert_true(pixels != null and not pixels.is_empty(), "player effect capture is nonblank")
	for sprite: Sprite2D in sprites:
		if sprite.visible:
			var source := Image.load_from_file(ProjectSettings.globalize_path(sprite.texture.resource_path))
			var imported := sprite.texture.get_image()
			var opaque_match := true
			for y: int in range(source.get_height()):
				for x: int in range(source.get_width()):
					if source.get_pixel(x, y).a > 0.0 and not source.get_pixel(x, y).is_equal_approx(imported.get_pixel(x, y)):
						opaque_match = false
			suite.assert_true(opaque_match, "effect imported opaque pixels match current source")
			_assert_enemy_pixels(suite, pixels, sprite, 16)
	var path := "res://build/visual-evidence/player-effects/%s.png" % suffix
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	suite.assert_equal(pixels.save_png(path), OK, "effect raster evidence is retained")
