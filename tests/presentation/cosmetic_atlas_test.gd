extends Node2D

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Catalog := preload("res://scripts/progression/cosmetic_catalog.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var catalog := Catalog.load_base()
	var stage := Node2D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(stage)
	var index := 0
	for character: String in ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]:
		var player: Node2D = PlayerScene.instantiate()
		stage.add_child(player)
		player.position = Vector2(64 + index * 128, 160)
		var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": character, "character_profile": registry.resolve_character_runtime_profile(StringName(character), &"LAUNCH"), "character_talents": [], "weapon_id": "sword", "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH"), "enabled_time_skills": [&"stop", &"rewind"], "difficulty": "normal", "seed": 20261005}
		suite.assert_true(player.configure_run(StringName("cosmetic-" + character)) and player.configure_loadout(config), "actual Player configures native character " + character)
		var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
		proxy.advance_animation_for_test(0.1)
		var before: Dictionary = player.full_player_replay_snapshot()
		var atlas := proxy.get_node("ProductionActorAtlas") as Sprite2D
		for route: String in ["default", "return", "victory"]:
			var id := character + "." + route
			suite.assert_true(proxy.apply_cosmetic(id), "native appearance projection accepts authored raster " + id)
			var texture: Texture2D = load(catalog.definition(id).atlas_path)
			suite.assert_equal(atlas.texture, texture, "gameplay uses the same full raster sheet as the collection preview")
			for state: StringName in [&"idle", &"move", &"attack", &"cast", &"hurt", &"death"]:
				suite.assert_true(atlas.present(state, Vector2.RIGHT, 10.0, true, false), "appearance preserves native animation state " + str(state))
				atlas.present(state, Vector2.RIGHT, 10.3, false, false)
				suite.assert_equal(atlas.texture, texture, "hit flash and animation cannot overwrite the equipped raster")
			proxy.advance_animation_for_test(0.1)
			suite.assert_equal(atlas.snapshot().cosmetic_id, id, "automatic presentation clock retains equipped appearance")
			suite.assert_equal(player.full_player_replay_snapshot(), before, "cosmetics never mutate native Player, Health, weapon, time, replay or world state")
		suite.assert_true(not proxy.apply_cosmetic("invented.appearance"), "unregistered appearance refuses")
		suite.assert_equal(atlas.snapshot().cosmetic_id, character + ".victory", "refused appearance preserves prior valid raster")
		index += 1
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var directory := "res://build/visual-evidence/p23-cosmetics"
		DirAccess.make_dir_recursive_absolute(directory)
		get_viewport().get_texture().get_image().save_png(directory + "/actual-cosmetic-players.png")
	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()
	suite.finish(get_tree())
