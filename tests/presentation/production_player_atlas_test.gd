extends Node2D

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const ACTORS := ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	var loaded: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not loaded.has_blocking_errors(), "atlas native fixture loads actual activated Launch profiles")
	var stage := Node2D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(stage)
	for index: int in range(5):
		var player: Node2D = PlayerScene.instantiate()
		stage.add_child(player)
		player.position = Vector2(64 + index * 128, 175)
		var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": ACTORS[index], "character_profile": registry.resolve_character_runtime_profile(StringName(ACTORS[index]), &"LAUNCH"), "character_talents": [], "weapon_id": "sword", "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH"), "enabled_time_skills": [&"stop", &"rewind"], "difficulty": "normal", "seed": 20261005}
		suite.assert_true(player.configure_run(StringName("atlas-" + ACTORS[index])) and player.configure_loadout(config), "actual native Player configures the authored character: " + ACTORS[index])
		var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
		var before: Dictionary = player.full_player_replay_snapshot()
		proxy.advance_animation_for_test(0.1)
		var atlas := proxy.get_node_or_null("ProductionActorAtlas") as Sprite2D
		suite.assert_true(atlas != null and atlas.texture != null and atlas.visible, "actual Player receives bitmap atlas projection: " + ACTORS[index])
		if atlas != null:
			suite.assert_true(atlas.has_method("snapshot"), "atlas exposes detached presentation contract")
			suite.assert_equal(atlas.snapshot().actor_id, ACTORS[index], "projection selects actual Player character identity")
			var first: int = atlas.frame
			proxy.advance_animation_for_test(0.25)
			suite.assert_true(atlas.frame != first, "actual idle presentation advances visible raster frames")
			proxy.play_action(&"attack", 0.2)
			proxy.advance_animation_for_test(0.02)
			suite.assert_equal(atlas.snapshot().state, "attack", "existing authoritative cue selects atlas attack row")
			suite.assert_true(proxy.get_snapshot_for_test().melee_slash_visible, "bitmap body preserves equipped sword feedback")
			proxy.set_feedback_options(false, true)
			proxy.advance_animation_for_test(0.02)
			first = atlas.frame
			proxy.advance_animation_for_test(0.02)
			suite.assert_equal(atlas.frame, first, "reduced motion freezes atlas within the current action")
			proxy.set_feedback_options(true, false)
			suite.assert_true(not atlas.configure("unknown_actor") and not atlas.visible, "unknown atlas identity refuses visible projection")
			suite.assert_true(atlas.configure(ACTORS[index]) and atlas.visible, "valid identity restores cached bitmap after a refused projection")
			suite.assert_true(not atlas.present(&"idle", Vector2.RIGHT, INF, false, false), "nonfinite presentation clock is rejected")
			suite.assert_true(atlas.present(&"move", Vector2.LEFT, 1.0, false, false) and atlas.flip_h, "raster mirrors left-facing motion without changing native aim")
			atlas.present(&"death", Vector2.LEFT, 1.0, false, false)
			atlas.present(&"death", Vector2.LEFT, 4.0, false, false)
			suite.assert_equal(atlas.frame, 23, "death stops on its final frame instead of looping")
			atlas.present(&"idle", Vector2.RIGHT, 4.0, false, false)
		suite.assert_equal(player.full_player_replay_snapshot(), before, "presentation does not mutate any native Player action, time, weapon, health or replay field")
		var label := Label.new()
		label.position = Vector2(5 + index * 128, 220)
		label.size = Vector2(118, 28)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text = ACTORS[index].replace("_", " ")
		label.add_theme_font_size_override("font_size", 12)
		add_child(label)
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var directory := "res://build/visual-evidence/p17a-actor-atlases"
		DirAccess.make_dir_recursive_absolute(directory)
		get_viewport().get_texture().get_image().save_png(directory + "/actual-players.png")
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()
	suite.finish(get_tree())
