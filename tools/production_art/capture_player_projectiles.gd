extends "res://tools/production_art/capture_enemy_atlases.gd"

const ArrowScene := preload("res://scenes/combat/player_arrow.tscn")
const BulletScene := preload("res://scenes/combat/gun_projectile.tscn")
const SpellScene := preload("res://scenes/combat/staff_projectile.tscn")
const ELEMENTS := ["arcane", "fire", "ice", "lightning"]


func _run() -> void:
	var suite := TestSuiteScript.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var template: Dictionary = {}
	var floor_row: Dictionary = {}
	for row: Dictionary in _load_json_array(TEMPLATE_PATH):
		if row.id == "room_combat_pillared_hall":
			template = row
	for row: Dictionary in _load_json_array(FLOOR_PATH):
		if row.id == "floor_ruins_of_remnant":
			floor_row = row
	viewport.add_child(_bound_scene(template, floor_row, true))
	var stage := Node2D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(stage)
	var sprites: Array[Sprite2D] = []
	var before: Array[Dictionary] = []
	for index: int in range(6):
		var projectile: Area2D = ArrowScene.instantiate() if index == 0 else BulletScene.instantiate() if index == 1 else SpellScene.instantiate()
		if index >= 2:
			projectile.element_id = ELEMENTS[index - 2]
		projectile.position = Vector2(52 + index * 104, 180)
		stage.add_child(projectile)
		var visual := projectile.get_node("Visual") as Sprite2D
		visual.scale = Vector2(2, 2)
		visual.set_reduced_motion(false)
		sprites.append(visual)
		before.append(projectile.execution_snapshot())
	for phase: int in range(4):
		for sprite: Sprite2D in sprites:
			sprite.advance_visual(0.0 if phase == 0 else 0.084)
			suite.assert_equal(sprite.frame, phase, "actual projectile node consumes its bitmap phase")
		await _capture(suite, viewport, sprites, "phase-%d" % phase)
	for index: int in range(sprites.size()):
		suite.assert_equal(sprites[index].get_parent().execution_snapshot(), before[index], "rendered projectile art preserves full domain snapshot")
		sprites[index].set_reduced_motion(true)
	await _capture(suite, viewport, sprites, "reduced-motion")
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _capture(suite, viewport: SubViewport, sprites: Array[Sprite2D], suffix: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	for sprite: Sprite2D in sprites:
		_assert_enemy_pixels(suite, pixels, sprite, 16)
	var path := "res://build/visual-evidence/player-projectiles/%s.png" % suffix
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	suite.assert_equal(pixels.save_png(path), OK, "projectile bitmap evidence retained")
