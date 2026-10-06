extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	var loaded: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not loaded.has_blocking_errors(), "afterimage test uses the native Launch registry")
	for identity: String in ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]:
		CombatFeedback.reset_feedback_for_test()
		CombatFeedback.set_feedback_options({"hit_flash_enabled": true, "reduced_motion": false})
		var player: Node2D = PlayerScene.instantiate()
		player.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(player)
		var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": identity, "character_profile": registry.resolve_character_runtime_profile(StringName(identity), &"LAUNCH"), "character_talents": [], "weapon_id": "sword", "weapon_profile": registry.resolve_weapon_runtime_profile(&"sword", &"LAUNCH"), "enabled_time_skills": [&"stop", &"rewind"], "difficulty": "normal", "seed": 20261006}
		suite.assert_true(player.configure_run(StringName("afterimage-" + identity)) and player.configure_loadout(config), "native Player configures " + identity)
		var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
		proxy.advance_animation_for_test(0.0)
		var source: Sprite2D = proxy.get_node("ProductionActorAtlas")
		source.frame = 5
		source.flip_h = true
		var before: Dictionary = player.full_player_replay_snapshot()
		var afterimage: Node2D = proxy.spawn_afterimage(Vector2(103.3, 99.1), 1.0)
		var captured := afterimage.get_node_or_null("ProductionAfterimageAtlas") as Sprite2D
		suite.assert_true(captured != null, "afterimage consumes the actual character raster: " + identity)
		if captured != null:
			suite.assert_equal(captured.texture, source.texture, "afterimage retains the same selected character/cosmetic texture")
			suite.assert_true(captured.hframes == 4 and captured.vframes == 6 and captured.frame == 5 and captured.flip_h, "afterimage freezes the selected pose and facing")
			suite.assert_equal(captured.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "afterimage keeps hard pixel edges")
			source.frame = 0
			source.flip_h = false
			afterimage._process(0.5)
			suite.assert_true(captured.frame == 5 and captured.flip_h and afterimage.modulate.a < 1.0, "source pose changes leave fading afterimage stable")
			suite.assert_true(afterimage.get_snapshot_for_test().pixel_snapped, "raster afterimage drift remains pixel snapped")
		suite.assert_equal(player.full_player_replay_snapshot(), before, "afterimage has no native gameplay/replay writes")
		afterimage.queue_free()
		proxy.set_feedback_options(true, true)
		suite.assert_true(proxy.spawn_afterimage(Vector2.ZERO) == null, "reduced motion suppresses raster afterimages")
		player.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()
	suite.finish(get_tree())
