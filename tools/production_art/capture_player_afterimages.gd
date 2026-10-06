extends "res://tools/production_art/capture_enemy_atlases.gd"

const Registry := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const IDS := ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]


func _run() -> void:
	var suite := TestSuiteScript.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var template: Dictionary = {}
	var floor_row: Dictionary = {}
	for row: Dictionary in _load_json_array(TEMPLATE_PATH):
		if row.id == "room_combat_pillared_hall": template = row
	for row: Dictionary in _load_json_array(FLOOR_PATH):
		if row.id == "floor_ruins_of_remnant": floor_row = row
	viewport.add_child(_bound_scene(template, floor_row, true))
	var stage := Node2D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(stage)
	var ghosts: Array[Node2D] = []
	var players: Array[Node2D] = []
	var before: Array[Dictionary] = []
	for index: int in range(IDS.size()):
		var identity: String = IDS[index]
		var player: Node2D = PlayerScene.instantiate()
		player.position = Vector2(70 + index * 124, 170)
		stage.add_child(player)
		var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": identity, "character_profile": registry.resolve_character_runtime_profile(StringName(identity), &"LAUNCH"), "character_talents": [], "weapon_id": "sword", "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH"), "enabled_time_skills": [&"stop", &"rewind"], "difficulty": "normal", "seed": 20261006}
		suite.assert_true(player.configure_run(StringName("afterimage-capture-" + identity)) and player.configure_loadout(config), "afterimage capture configures native Player")
		var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
		proxy.advance_animation_for_test(0.0)
		var source: Sprite2D = proxy.get_node("ProductionActorAtlas")
		source.frame = 5
		source.flip_h = index % 2 == 1
		var ghost: Node2D = proxy.spawn_afterimage(player.position, 1.0)
		ghost.hide()
		player.hide()
		ghosts.append(ghost)
		players.append(player)
		before.append(player.full_player_replay_snapshot())
	var background := await _pixels(viewport)
	for ghost: Node2D in ghosts:
		ghost.show()
	for phase: int in range(3):
		if phase > 0:
			for ghost: Node2D in ghosts:
				ghost._process(0.25)
		var rendered := await _pixels(viewport)
		for ghost: Node2D in ghosts:
			_assert_ghost_pixels(suite, rendered, background, ghost.get_node("ProductionAfterimageAtlas"))
		var path := "res://build/visual-evidence/player-afterimages/fade-%d.png" % phase
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		suite.assert_equal(rendered.save_png(path), OK, "native afterimage capture retained")
	for index: int in range(players.size()):
		suite.assert_equal(players[index].full_player_replay_snapshot(), before[index], "rendered afterimage preserves the full native Player snapshot")
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()
	suite.finish(get_tree())


func _pixels(viewport: SubViewport) -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _assert_ghost_pixels(suite, rendered: Image, background: Image, sprite: Sprite2D) -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(sprite.texture.resource_path))
	var size := Vector2i(sprite.get_rect().size)
	var origin := Vector2i(sprite.frame_coords) * size
	var pose := sprite.get_global_transform_with_canvas()
	var tint: Color = sprite.modulate * sprite.get_parent().modulate
	var samples := 0
	var mismatches := 0
	for y: int in range(size.y):
		for x: int in range(size.x):
			var color := source.get_pixelv(origin + Vector2i(size.x - 1 - x if sprite.flip_h else x, y))
			if color.a < 1.0: continue
			var position := Vector2i(pose * (sprite.get_rect().position + Vector2(x + 0.5, y + 0.5)))
			var expected := background.get_pixelv(position).lerp(Color(color.r * tint.r, color.g * tint.g, color.b * tint.b), tint.a)
			var actual := rendered.get_pixelv(position)
			if absf(expected.r - actual.r) > 0.012 or absf(expected.g - actual.g) > 0.012 or absf(expected.b - actual.b) > 0.012:
				mismatches += 1
			samples += 1
	suite.assert_true(samples > 80 and mismatches == 0, "actual afterimage blends the frozen source pose: %d/%d mismatch" % [mismatches, samples])
