extends "res://tools/production_art/capture_enemy_atlases.gd"

const Fixture := preload("res://tests/presentation/player_zone_art_test.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")


func _run() -> void:
	var suite := TestSuiteScript.new()
	var registry := Registry.new()
	var loaded: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not loaded.has_blocking_errors(), "zone capture loads actual Launch catalog")
	var template: Dictionary = {}
	var floor_row: Dictionary = {}
	for row: Dictionary in _load_json_array(TEMPLATE_PATH):
		if row.id == "room_combat_pillared_hall": template = row
	for row: Dictionary in _load_json_array(FLOOR_PATH):
		if row.id == "floor_ruins_of_remnant": floor_row = row
	for identity: String in Fixture.STAFF_IDS + Fixture.GAUNTLET_IDS:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(640, 360)
		viewport.world_2d = World2D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		viewport.add_child(_bound_scene(template, floor_row, true))
		var stage := Node2D.new()
		stage.process_mode = Node.PROCESS_MODE_DISABLED
		viewport.add_child(stage)
		var is_staff: bool = identity in Fixture.STAFF_IDS
		var zone: Node2D = Fixture.StaffScene.instantiate() if is_staff else Fixture.Gauntlets.new()
		zone.position = Vector2(320, 180)
		var execution: Dictionary = Fixture.staff_execution(identity) if is_staff else Fixture.gauntlets_execution(identity)
		if execution.mode == "combination":
			execution.parameters.combo_parameters.delay_frames = 60
			execution.parameters.combo_parameters.origins = [Vector2(180, 180), Vector2(460, 180)]
		suite.assert_true(zone.configure_execution(execution), "room capture configures actual native zone " + identity)
		stage.add_child(zone)
		var player: Node2D = PlayerScene.instantiate()
		player.position = Vector2(320, 180)
		stage.add_child(player)
		var weapon := "staff" if is_staff else "gauntlets"
		var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "character_talents": [], "weapon_id": weapon, "weapon_profile": registry.resolve_weapon_runtime_profile(StringName(weapon), &"LAUNCH"), "enabled_time_skills": [&"stop", &"rewind"], "difficulty": "normal", "seed": 20261006}
		suite.assert_true(player.configure_run(StringName("zone-capture-" + identity)) and player.configure_loadout(config), "zone room capture equips actual Player")
		var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
		proxy.advance_animation_for_test(0.0)
		var player_before: Dictionary = player.full_player_replay_snapshot()
		var visual: Node = zone.get_node("ProductionZoneAtlas")
		visual.set_reduced_motion(false)
		var phases := 1 if identity == "steam_burst" else 4
		for phase: int in range(phases):
			if phase > 0: zone.advance_execution_for_test(6)
			visual.sync_from_owner()
			await _capture(suite, viewport, player, visual, identity, "phase-%d" % phase)
		visual.set_reduced_motion(true)
		visual.sync_from_owner()
		await _capture(suite, viewport, player, visual, identity, "reduced-motion")
		suite.assert_equal(player.full_player_replay_snapshot(), player_before, "zone rendering preserves complete native Player snapshot")
		viewport.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		CombatFeedback.reset_feedback_for_test()
	suite.finish(get_tree())


func _capture(suite, viewport: SubViewport, player: Node2D, visual: Node, identity: String, suffix: String) -> void:
	var zone: Node = visual.get_parent()
	var before: Dictionary = zone.execution_snapshot()
	player.hide()
	var pixels := await _pixels(viewport)
	for sprite: Sprite2D in visual.get_children():
		_assert_enemy_pixels(suite, pixels, sprite, 80)
	var isolated := "res://build/visual-evidence/player-zones/%s-%s-source.png" % [identity, suffix]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolated.get_base_dir()))
	suite.assert_equal(pixels.save_png(isolated), OK, "unoccluded zone source pixel evidence retained")
	player.show()
	pixels = await _pixels(viewport)
	var output := "res://build/visual-evidence/player-zones/%s-%s.png" % [identity, suffix]
	suite.assert_equal(pixels.save_png(output), OK, "native zone and Player composition retained")
	suite.assert_equal(zone.execution_snapshot(), before, "zone capture preserves exact native execution state")


func _pixels(viewport: SubViewport) -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
