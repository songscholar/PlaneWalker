extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Proxy := preload("res://scripts/presentation/pixel_proxy_actor.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")


class PresentationPlayer extends Node2D:
	var weapon_snapshot := {"weapon_id": "sword", "action_id": "normal_attack", "phase": "ACTIVE", "token": 1, "runtime": {"facing": Vector2.RIGHT}}


	func _init() -> void:
		add_to_group("player")
		var visual := Polygon2D.new()
		visual.name = "Visual"
		add_child(visual)


	func weapon_presentation_snapshot() -> Dictionary:
		return weapon_snapshot.duplicate(true)


	func get_rewind_facing() -> Vector2:
		return Vector2.RIGHT


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var actor := PresentationPlayer.new()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(actor)
	var proxy := Proxy.new()
	proxy.name = "PixelProxyActor"
	actor.add_child(proxy)
	suite.assert_true(proxy.bind_actor(actor), "player presentation binds")
	var expected := {"sword": "weapon_arc", "bow": "arrow_trail", "gun": "muzzle_flash", "staff": "spell_burst", "gauntlets": "weapon_arc"}
	for weapon: String in expected:
		actor.weapon_snapshot.weapon_id = weapon
		actor.weapon_snapshot.token += 1
		actor.weapon_snapshot.phase = "ACTIVE"
		proxy.play_weapon_cue(StringName(weapon + "_attack"), StringName(weapon + "_effect"))
		proxy.advance_animation_for_test(0.0)
		var effect := proxy.get_node_or_null("ProductionEffectAtlas") as Sprite2D
		suite.assert_true(effect != null, weapon + " consumes a production effect node")
		if effect == null:
			continue
		suite.assert_true(effect.visible, weapon + " effect is visible in active phase")
		suite.assert_equal(effect.texture.resource_path, "res://assets/production/ui/player_effects/%s.png" % expected[weapon], weapon + " uses the matching texture")
		suite.assert_equal(effect.hframes, 4, weapon + " has four effect frames")
		suite.assert_equal(effect.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, weapon + " has hard pixel edges")
		suite.assert_equal(effect.frame, 0, weapon + " starts a fresh visual sequence")
		proxy.advance_animation_for_test(0.09)
		suite.assert_true(effect.frame > 0, weapon + " effect advances")
		proxy.set_feedback_options(true, true)
		proxy.advance_animation_for_test(0.02)
		suite.assert_equal(effect.frame, 1, weapon + " reduced motion uses a fixed readable pose")
		proxy.set_feedback_options(true, false)
		actor.weapon_snapshot.phase = "READY"
		actor.weapon_snapshot.action_id = ""
		proxy.advance_animation_for_test(1.0)
		proxy.advance_animation_for_test(0.0)
		suite.assert_true(not effect.visible, weapon + " completed effect disappears")
		actor.weapon_snapshot.action_id = "normal_attack"
	proxy.play_action(&"time_stop")
	proxy.advance_animation_for_test(0.0)
	var time_effect := proxy.get_node_or_null("ProductionEffectAtlas") as Sprite2D
	suite.assert_true(time_effect != null and time_effect.visible, "time skill consumes production feedback")
	if time_effect != null:
		suite.assert_equal(time_effect.texture.resource_path, "res://assets/production/ui/player_effects/time_ring.png", "time skill uses the time ring")
	proxy.play_action(&"cast")
	proxy.advance_animation_for_test(0.0)
	if time_effect != null:
		suite.assert_equal(time_effect.texture.resource_path, "res://assets/production/ui/player_effects/rift_bloom.png", "cast uses the rift bloom")
	for skill: String in ["time_accelerate", "time_rift"]:
		proxy.play_action(StringName(skill))
		proxy.advance_animation_for_test(0.0)
		var expected_effect := "time_ring" if skill == "time_accelerate" else "rift_bloom"
		suite.assert_true(time_effect != null and time_effect.visible and time_effect.texture.resource_path.ends_with(expected_effect + ".png"), skill + " consumes its production raster")
	actor.weapon_snapshot.weapon_id = "gun"
	actor.weapon_snapshot.phase = "ACTIVE"
	proxy.set_feedback_options(false, false)
	proxy.play_weapon_cue(&"gun_fire", &"gun_muzzle")
	proxy.advance_animation_for_test(0.0)
	if time_effect != null:
		suite.assert_true(not time_effect.visible, "disabled flashing suppresses the muzzle flash")
	actor.weapon_snapshot.weapon_id = "unknown"
	proxy.advance_animation_for_test(0.0)
	if time_effect != null:
		suite.assert_true(not time_effect.visible, "unknown weapon cannot borrow an effect")
	proxy.set_feedback_options(true, false)
	for resource_cue: Array in [["gun", "reload", "gun_reload_marker"], ["staff", "cycle_element", "staff_element_orb"], ["sword", "guard", "sword_guard_flash"], ["bow", "focus_step", "bow_focus_line"]]:
		actor.weapon_snapshot.weapon_id = resource_cue[0]
		actor.weapon_snapshot.action_id = resource_cue[1]
		actor.weapon_snapshot.phase = "RESOURCE_ACTION"
		proxy.play_weapon_cue(StringName(resource_cue[1]), StringName(resource_cue[2]))
		proxy.advance_animation_for_test(0.0)
		suite.assert_true(time_effect != null and not time_effect.visible, "resource/movement/guard cue cannot look like an attack: " + resource_cue[2])
	actor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await _assert_native_player_projection(suite)
	suite.finish(get_tree())


func _assert_native_player_projection(suite) -> void:
	var registry := Registry.new()
	var loaded: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not loaded.has_blocking_errors(), "effect integration loads actual Launch profiles")
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		CombatFeedback.reset_feedback_for_test()
		CombatFeedback.set_feedback_options({"hit_flash_enabled": true, "reduced_motion": false})
		var player: Node2D = PlayerScene.instantiate()
		player.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(player)
		var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "character_profile": registry.resolve_character_runtime_profile(&"wanderer", &"LAUNCH"), "character_talents": [], "weapon_id": weapon, "weapon_profile": registry.resolve_weapon_runtime_profile(StringName(weapon), &"LAUNCH"), "enabled_time_skills": [&"stop", &"rewind"], "difficulty": "normal", "seed": 20261006}
		suite.assert_true(player.configure_run(StringName("effect-" + weapon)) and player.configure_loadout(config), "actual Player configures " + weapon)
		var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
		var before: Dictionary = player.full_player_replay_snapshot()
		EventBus.weapon_cue_requested.emit(StringName(weapon), &"normal_attack", 1, {"cue_id": "active", "animation_id": weapon + "_attack", "vfx_id": weapon + "_effect"})
		proxy.advance_animation_for_test(0.0)
		var effect := proxy.get_node("ProductionEffectAtlas") as Sprite2D
		suite.assert_true(effect.visible and effect.texture != null, "production EventBus feedback reaches actual Player bitmap: " + weapon)
		proxy.advance_animation_for_test(0.09)
		suite.assert_true(effect.frame > 0, "native Player bitmap animation advances: " + weapon)
		for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			proxy._attack_direction = direction
			proxy._sync_effect_atlas()
			var transform := effect.get_global_transform_with_canvas()
			suite.assert_true(transform.x.is_equal_approx(direction * 2.0), "effect pixel columns keep integer size for " + str(direction))
			suite.assert_true(transform.y.is_equal_approx(direction.orthogonal() * -2.0), "effect pixel rows keep integer size for " + str(direction))
		proxy.set_feedback_options(false, true)
		proxy.advance_animation_for_test(0.01)
		suite.assert_equal(player.full_player_replay_snapshot(), before, "presentation preserves native action/time/health/replay state: " + weapon)
		player.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()
