extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixture := preload("res://tests/presentation/player_effect_atlas_test.gd")
const Proxy := preload("res://scripts/presentation/pixel_proxy_actor.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var actor := Fixture.PresentationPlayer.new()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var proxy := Proxy.new()
	proxy.name = "PixelProxyActor"
	actor.add_child(proxy)
	suite.assert_true(proxy.bind_actor(actor), "held weapon fixture binds the existing presentation owner")
	for identity: String in ["sword", "bow", "gun", "gauntlets", "staff_arcane", "staff_fire", "staff_ice", "staff_lightning"]:
		actor.weapon_snapshot.weapon_id = "staff" if identity.begins_with("staff_") else identity
		actor.weapon_snapshot.runtime.element = identity.trim_prefix("staff_") if identity.begins_with("staff_") else ""
		for phase: String in ["READY", "HOLD", "WINDUP", "ACTIVE", "RESOURCE_ACTION", "RECOVERY"]:
			actor.weapon_snapshot.phase = phase
			proxy.advance_animation_for_test(0.0)
			var sprite := proxy.get_node_or_null("ProductionHeldWeaponAtlas") as Sprite2D
			suite.assert_true(sprite != null and sprite.texture != null and sprite.visible, identity + " consumes the held weapon bitmap during " + phase)
			if sprite == null or sprite.texture == null: continue
			suite.assert_equal(sprite.texture.resource_path, "res://assets/production/ui/held_weapons/%s.png" % identity, "held raster selects exact equipment and element identity")
			var expected := 0 if phase == "READY" else 2 if phase == "ACTIVE" else 3 if phase == "RECOVERY" else 1
			suite.assert_equal(sprite.frame, expected, "held raster projects copied action phase")
			suite.assert_equal(sprite.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "held raster uses nearest filtering")
		proxy.set_feedback_options(true, true)
		proxy.advance_animation_for_test(0.0)
		var sprite := proxy.get_node_or_null("ProductionHeldWeaponAtlas") as Sprite2D
		if sprite != null: suite.assert_equal(sprite.frame, 0, "reduced motion fixes the readable held pose")
		proxy.set_feedback_options(true, false)
	actor.weapon_snapshot.weapon_id = "unknown"
	proxy.advance_animation_for_test(0.0)
	var held := proxy.get_node_or_null("ProductionHeldWeaponAtlas") as Sprite2D
	if held != null: suite.assert_true(not held.visible, "unknown equipment cannot borrow held weapon art")
	actor.weapon_snapshot.weapon_id = "staff"
	actor.weapon_snapshot.runtime.element = "unknown"
	proxy.advance_animation_for_test(0.0)
	if held != null: suite.assert_true(not held.visible, "unknown staff element cannot borrow a colored gem")
	actor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await _assert_native_players(suite)
	suite.finish(get_tree())


func _assert_native_players(suite) -> void:
	var registry := Registry.new()
	var loaded: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not loaded.has_blocking_errors(), "held weapon tests load the actual Launch catalog")
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		CombatFeedback.reset_feedback_for_test()
		var player: Node2D = PlayerScene.instantiate()
		player.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(player)
		var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "character_talents": [], "weapon_id": weapon, "weapon_profile": registry.resolve_weapon_runtime_profile(StringName(weapon), &"LAUNCH"), "enabled_time_skills": [&"stop", &"rewind"], "difficulty": "normal", "seed": 20261006}
		suite.assert_true(player.configure_run(StringName("held-" + weapon)) and player.configure_loadout(config), "actual Player equips " + weapon)
		var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
		var before: Dictionary = player.full_player_replay_snapshot()
		proxy.advance_animation_for_test(0.0)
		var sprite := proxy.get_node_or_null("ProductionHeldWeaponAtlas") as Sprite2D
		suite.assert_true(sprite != null and sprite.visible and sprite.texture != null, "actual Player consumes held art for " + weapon)
		if sprite != null:
			for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
				proxy._facing = direction
				proxy._sync_held_weapon_atlas()
				suite.assert_true(sprite.get_global_transform_with_canvas().x.is_equal_approx(direction), "held weapon uses integer screen pixels along " + str(direction))
		proxy.set_feedback_options(false, true)
		proxy.advance_animation_for_test(0.09)
		suite.assert_equal(player.full_player_replay_snapshot(), before, "held artwork leaves all native Player action/time/replay state unchanged")
		player.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()
