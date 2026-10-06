extends "res://tools/production_art/capture_enemy_atlases.gd"

const Fixture := preload("res://tests/presentation/player_effect_atlas_test.gd")
const Proxy := preload("res://scripts/presentation/pixel_proxy_actor.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const IDS := ["sword", "bow", "gun", "gauntlets", "staff_arcane", "staff_fire", "staff_ice", "staff_lightning"]
const PHASES := ["READY", "WINDUP", "ACTIVE", "RECOVERY"]


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
		if row.id == "room_combat_pillared_hall": template = row
	for row: Dictionary in _load_json_array(FLOOR_PATH):
		if row.id == "floor_ruins_of_remnant": floor_row = row
	viewport.add_child(_bound_scene(template, floor_row, true))
	var stage := Node2D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	viewport.add_child(stage)
	var actors: Array[Node2D] = []
	var proxies: Array[Node] = []
	var registry := Registry.new()
	var loaded: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not loaded.has_blocking_errors(), "held capture loads actual Launch profiles")
	var players: Array[Node2D] = []
	var native_proxies: Array[Node] = []
	var before: Array[Dictionary] = []
	for index: int in range(IDS.size()):
		var identity: String = IDS[index]
		var actor := Fixture.PresentationPlayer.new()
		actor.position = Vector2(30 + index * 80, 120)
		actor.weapon_snapshot.weapon_id = "staff" if identity.begins_with("staff_") else identity
		actor.weapon_snapshot.runtime.element = identity.trim_prefix("staff_") if identity.begins_with("staff_") else ""
		stage.add_child(actor)
		var proxy := Proxy.new()
		proxy.name = "PixelProxyActor"
		actor.add_child(proxy)
		suite.assert_true(proxy.bind_actor(actor), "held capture binds production proxy for " + identity)
		actors.append(actor)
		proxies.append(proxy)
	var weapons := ["sword", "bow", "gun", "staff", "gauntlets"]
	for index: int in range(weapons.size()):
		var weapon: String = weapons[index]
		var player: Node2D = PlayerScene.instantiate()
		player.position = Vector2(60 + index * 124, 265)
		stage.add_child(player)
		var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "character_talents": [], "weapon_id": weapon, "weapon_profile": registry.resolve_weapon_runtime_profile(StringName(weapon), &"LAUNCH"), "enabled_time_skills": [&"stop", &"rewind"], "difficulty": "normal", "seed": 20261006}
		suite.assert_true(player.configure_run(StringName("held-capture-" + weapon)) and player.configure_loadout(config), "held capture equips actual Player with " + weapon)
		var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
		proxy.advance_animation_for_test(0.0)
		players.append(player)
		native_proxies.append(proxy)
		before.append(player.full_player_replay_snapshot())
	for phase: int in range(PHASES.size()):
		for index: int in range(actors.size()):
			actors[index].weapon_snapshot.phase = PHASES[phase]
			proxies[index].advance_animation_for_test(0.0)
			var sprite: Sprite2D = proxies[index].get_node("ProductionHeldWeaponAtlas")
			suite.assert_equal(sprite.frame, phase, "room capture consumes exact phase " + PHASES[phase])
		await _capture(suite, viewport, proxies + native_proxies, "phase-%d" % phase)
	for proxy: Node in proxies + native_proxies:
		proxy.set_feedback_options(true, true)
		proxy.advance_animation_for_test(0.0)
		suite.assert_equal(proxy.get_node("ProductionHeldWeaponAtlas").frame, 0, "room capture freezes readable reduced-motion pose")
	await _capture(suite, viewport, proxies + native_proxies, "reduced-motion")
	for index: int in range(players.size()):
		suite.assert_equal(players[index].full_player_replay_snapshot(), before[index], "held room capture preserves complete native Player snapshot")
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()
	suite.finish(get_tree())


func _capture(suite, viewport: SubViewport, proxies: Array, suffix: String) -> void:
	var effects: Array[Sprite2D] = []
	for proxy: Node in proxies:
		var effect := proxy.get_node_or_null("ProductionEffectAtlas") as Sprite2D
		if effect != null and effect.visible:
			effects.append(effect)
			effect.hide()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	for proxy: Node in proxies:
		_assert_enemy_pixels(suite, pixels, proxy.get_node("ProductionHeldWeaponAtlas"), 16)
	var isolated := "res://build/visual-evidence/held-weapons/%s-held-only.png" % suffix
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolated.get_base_dir()))
	suite.assert_equal(pixels.save_png(isolated), OK, "unoccluded held weapon pixels retained")
	for effect: Sprite2D in effects:
		effect.show()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	pixels = viewport.get_texture().get_image()
	var output := "res://build/visual-evidence/held-weapons/%s.png" % suffix
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	suite.assert_equal(pixels.save_png(output), OK, "held weapon native room evidence retained")
