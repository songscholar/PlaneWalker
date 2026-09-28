extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const ChaserScene := preload("res://scenes/enemies/enemy_chaser.tscn")
const TankScene := preload("res://scenes/enemies/enemy_tank.tscn")
const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")
const FloatingTextScript := preload("res://scripts/ui/floating_text_layer.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _assert_pixel_proxy_contract()
	_assert_hit_pause_duration_contract()
	_assert_hit_feedback_profiles()
	_assert_audio_contract()
	await _assert_audio_cleanup_contract()
	_assert_overlay_contract()
	await _assert_feedback_runtime_gates()
	await _assert_floating_text_contract()
	CombatFeedback.reset_feedback_for_test()
	for _frame: int in range(6):
		await get_tree().process_frame
	_suite.finish(get_tree())


func _assert_pixel_proxy_contract() -> void:
	var camera := Camera2D.new()
	camera.position = Vector2(640.0, 360.0)
	camera.zoom = Vector2(0.5, 0.5)
	camera.enabled = true
	add_child(camera)
	var stage := Node2D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(stage)
	var player := PlayerScene.instantiate()
	var chaser := ChaserScene.instantiate()
	var tank := TankScene.instantiate()
	var boss := BossScene.instantiate()
	stage.add_child(player)
	stage.add_child(chaser)
	stage.add_child(tank)
	stage.add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame

	var player_proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
	var chaser_proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(chaser)
	var tank_proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(tank)
	var boss_proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(boss)

	_suite.assert_true(player_proxy != null, "player receives a Pixel Proxy")
	_suite.assert_true(chaser_proxy != null, "chaser receives a Pixel Proxy")
	_suite.assert_true(tank_proxy != null, "tank receives a Pixel Proxy")
	_suite.assert_true(boss_proxy != null, "Boss receives a Pixel Proxy")
	if player_proxy == null or chaser_proxy == null or tank_proxy == null or boss_proxy == null:
		stage.queue_free()
		await get_tree().process_frame
		return

	var player_snapshot: Dictionary = player_proxy.get_snapshot_for_test()
	var chaser_snapshot: Dictionary = chaser_proxy.get_snapshot_for_test()
	var tank_snapshot: Dictionary = tank_proxy.get_snapshot_for_test()
	var boss_snapshot: Dictionary = boss_proxy.get_snapshot_for_test()
	_suite.assert_equal(player_snapshot.get("role"), "player", "player role is explicit")
	_suite.assert_equal(chaser_snapshot.get("role"), "chaser", "chaser role is explicit")
	_suite.assert_equal(tank_snapshot.get("role"), "tank", "tank role is explicit")
	_suite.assert_equal(boss_snapshot.get("role"), "boss", "Boss role is explicit")
	_suite.assert_equal(player_snapshot.get("pixel_unit"), 2, "Pixel Proxy uses a two-pixel unit")
	_suite.assert_equal(
		player_snapshot.get("texture_filter"),
		CanvasItem.TEXTURE_FILTER_NEAREST,
		"Pixel Proxy enforces nearest filtering"
	)
	_suite.assert_true(
		player_snapshot.get("palette_id") != chaser_snapshot.get("palette_id"),
		"player and danger silhouettes use distinct palettes"
	)
	_suite.assert_true(
		boss_snapshot.get("footprint", Vector2i.ZERO).x > tank_snapshot.get("footprint", Vector2i.ZERO).x,
		"Boss has the largest readable silhouette"
	)
	_suite.assert_equal(player_snapshot.get("screen_pixel_unit"), 2.0, "Pixel Proxy keeps a two-pixel screen unit")
	_suite.assert_equal(player_snapshot.get("world_pixel_unit"), 4.0, "0.5 camera zoom maps two screen pixels to four world units")
	var screen_footprint: Vector2 = player_snapshot.get("screen_footprint", Vector2.ZERO)
	_suite.assert_close(screen_footprint.x, 24.0, "camera zoom does not halve proxy screen width")
	_suite.assert_close(screen_footprint.y, 32.0, "camera zoom does not halve proxy screen height")
	player_proxy.play_action(&"dash")
	var dash_spawn_snapshot: Dictionary = player_proxy.get_snapshot_for_test()
	var afterimage: Node2D = player_proxy.spawn_afterimage(Vector2(103.3, 99.1), 1.0)
	_suite.assert_true(afterimage != null, "dash presentation can spawn an afterimage")
	if afterimage != null:
		var afterimage_screen_footprint := Vector2(player_snapshot.get("footprint", Vector2i.ZERO)) * afterimage.scale * Vector2(0.5, 0.5)
		_suite.assert_equal(
			afterimage_screen_footprint,
			dash_spawn_snapshot.get("screen_footprint"),
			"afterimage inherits the active dash footprint at 0.5 zoom"
		)
		_suite.assert_true(
			is_equal_approx(fmod(absf(afterimage.global_position.x), 4.0), 0.0)
				and is_equal_approx(fmod(absf(afterimage.global_position.y), 4.0), 0.0),
			"afterimage origin snaps to the two-screen-pixel world unit"
		)
		afterimage._process(0.6)
		var drift_snapshot: Dictionary = afterimage.get_snapshot_for_test()
		_suite.assert_true(bool(drift_snapshot.get("pixel_snapped", false)), "afterimage drift stays screen-pixel snapped")
		_suite.assert_equal(
			drift_snapshot.get("screen_footprint"),
			dash_spawn_snapshot.get("screen_footprint"),
			"afterimage keeps the dash footprint while drifting"
		)
		afterimage.queue_free()
	_suite.assert_true(not (player.get_node("Visual") as CanvasItem).visible, "legacy player polygon is replaced")
	_suite.assert_true(not (boss.get_node("Visual") as CanvasItem).visible, "legacy Boss polygon is replaced")
	_suite.assert_true(
		CombatFeedback.ensure_actor_proxy_for_test(player) == player_proxy,
		"proxy installation is idempotent"
	)
	_suite.assert_true(
		bool(player_snapshot.get("velocity_capability_cached", false)),
		"proxy caches the actor velocity capability at bind time"
	)
	var actor_cache: Dictionary = CombatFeedback.get_actor_cache_snapshot_for_test()
	_suite.assert_true(bool(actor_cache.get("player_cached", false)), "feedback coordinator caches the player reference")
	_suite.assert_true(bool(actor_cache.get("health_cached", false)), "feedback coordinator caches the player health interface")

	player_proxy.play_action(&"attack")
	player_proxy.advance_animation_for_test(0.03)
	var attack_snapshot: Dictionary = player_proxy.get_snapshot_for_test()
	_suite.assert_equal(attack_snapshot.get("state"), "attack", "attack animation enters immediately")
	_suite.assert_true(bool(attack_snapshot.get("pixel_snapped")), "attack transform is pixel snapped")
	player_proxy.play_action(&"dash")
	player_proxy.advance_animation_for_test(0.03)
	_suite.assert_equal(
		player_proxy.get_snapshot_for_test().get("state"),
		"dash",
		"dash has a dedicated core animation"
	)
	tank_proxy.play_action(&"windup")
	tank_proxy.advance_animation_for_test(0.1)
	_suite.assert_equal(
		tank_proxy.get_snapshot_for_test().get("state"),
		"windup",
		"enemy windup has a dedicated animation"
	)

	_assert_directional_proxy_contract(player, player_proxy)
	_assert_boss_proxy_semantics(boss, boss_proxy)

	stage.queue_free()
	camera.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _assert_directional_proxy_contract(player: Node2D, proxy: Node) -> void:
	var directions := [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
	for direction: Vector2 in directions:
		player.sword_weapon.rotation = direction.angle()
		player.restore_rewind_facing(direction)
		var gameplay_position: Vector2 = player.global_position
		var gameplay_velocity: Vector2 = player.velocity
		var weapon_rotation: float = player.sword_weapon.rotation

		proxy.play_action(&"attack")
		proxy.advance_animation_for_test(0.01)
		var attack: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(attack.get("facing"), direction, "attack reads %s weapon facing" % str(direction))
		_suite.assert_equal(attack.get("attack_direction"), direction, "attack slash follows %s" % str(direction))
		_suite.assert_equal(attack.get("screen_action_offset"), direction * 2.0, "attack lunge follows %s" % str(direction))

		proxy.play_action(&"dash")
		proxy.advance_animation_for_test(0.01)
		var dash: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(dash.get("facing"), direction, "dash reads %s gameplay facing" % str(direction))
		_suite.assert_equal(dash.get("screen_action_offset"), direction * 4.0, "dash displacement follows %s" % str(direction))
		var stretch: Vector2 = dash.get("action_scale", Vector2.ONE)
		if absf(direction.x) > 0.0:
			_suite.assert_true(stretch.x > stretch.y, "horizontal dash stretches horizontally")
		else:
			_suite.assert_true(stretch.y > stretch.x, "vertical dash stretches vertically")

		_suite.assert_equal(player.global_position, gameplay_position, "proxy never moves the player")
		_suite.assert_equal(player.velocity, gameplay_velocity, "proxy never changes gameplay velocity")
		_suite.assert_equal(player.sword_weapon.rotation, weapon_rotation, "proxy only reads weapon angle")


func _assert_boss_proxy_semantics(boss: Node, proxy: Node) -> void:
	proxy.advance_animation_for_test(0.01)
	var phase_one: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(phase_one.get("boss_phase_marks"), 1, "Boss phase one has one shape mark")
	_suite.assert_equal(phase_one.get("boss_core_shape"), "sealed", "normal Boss core is sealed")
	_suite.assert_equal(phase_one.get("boss_texture_pattern"), "flowing_ticks", "normal Boss texture flows")

	boss._phase = 3
	proxy.advance_animation_for_test(0.01)
	var phase_three: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(phase_three.get("boss_phase_marks"), 3, "Boss phase three adds shape marks")
	_suite.assert_true(
		float(phase_three.get("boss_luminance", 0.0)) > float(phase_one.get("boss_luminance", 0.0)),
		"Boss phase increases brightness independently of hue"
	)

	boss._exposed = true
	proxy.advance_animation_for_test(0.01)
	var exposed: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(exposed.get("boss_core_shape"), "split", "exposure opens the Boss core shape")

	boss._exposure_sources[&"time_stop"] = 1
	var gameplay_before: Dictionary = boss.get_boss_ui_snapshot().duplicate(true)
	proxy.advance_animation_for_test(0.01)
	var frozen: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(frozen.get("boss_texture_pattern"), "frozen_grid", "time stop adds a frozen texture cue")
	_suite.assert_equal(boss.get_boss_ui_snapshot(), gameplay_before, "Boss proxy never mutates Boss gameplay state")


func _assert_hit_pause_duration_contract() -> void:
	for render_fps: int in [30, 60, 144]:
		CombatFeedback.reset_feedback_for_test()
		CombatFeedback.request_hit_pause(0.1)
		var requested: Dictionary = CombatFeedback.get_hit_pause_snapshot_for_test()
		var started_usec := int(requested.get("started_usec", 0))
		var deadline_usec := int(requested.get("deadline_usec", 0))
		var frame_usec := int(round(1000000.0 / float(render_fps)))
		var simulated_now := started_usec
		while simulated_now < deadline_usec:
			simulated_now += frame_usec
			CombatFeedback.update_hit_pause_for_test(simulated_now)
			if simulated_now < deadline_usec:
				_suite.assert_true(
					bool(CombatFeedback.get_hit_pause_snapshot_for_test().get("active", false)),
					"%d FPS cannot end hit pause before its real-time deadline" % render_fps
				)
		_suite.assert_true(
			not bool(CombatFeedback.get_hit_pause_snapshot_for_test().get("active", true)),
			"%d FPS ends hit pause on the first update after its real-time deadline" % render_fps
		)
		_suite.assert_true(simulated_now - started_usec >= 100000, "%d FPS honors the full requested duration" % render_fps)
		_suite.assert_true(
			simulated_now - started_usec < 100000 + frame_usec,
			"%d FPS cannot extend hit pause beyond one scheduler interval" % render_fps
		)
		_suite.assert_close(Engine.time_scale, 1.0, "%d FPS restores time scale" % render_fps)

	Engine.time_scale = 0.5
	CombatFeedback.request_hit_pause(0.05)
	var scaled_request: Dictionary = CombatFeedback.get_hit_pause_snapshot_for_test()
	CombatFeedback.update_hit_pause_for_test(int(scaled_request.get("deadline_usec", 0)))
	_suite.assert_close(Engine.time_scale, 0.5, "hit pause restores a pre-existing gameplay time scale")
	Engine.time_scale = 1.0


func _assert_hit_feedback_profiles() -> void:
	var light := DamageInfoScript.new(10.0, DamageInfoScript.DamageType.PHYSICAL)
	light.tags.append("weapon:sword")
	var finisher := light.copy_for_source(self)
	finisher.tags.append("attack:finisher")
	var heavy := light.copy_for_source(self)
	heavy.tags.append("attack:heavy")
	var hostile := light.copy_for_source(self)
	hostile.tags.clear()
	hostile.tags.append("enemy:melee")

	var light_profile: Dictionary = CombatFeedback.get_hit_profile_for_test(light, false)
	var finisher_profile: Dictionary = CombatFeedback.get_hit_profile_for_test(finisher, false)
	var heavy_profile: Dictionary = CombatFeedback.get_hit_profile_for_test(heavy, false)
	var hostile_profile: Dictionary = CombatFeedback.get_hit_profile_for_test(hostile, true)
	_suite.assert_equal(light_profile.get("pause_frames"), 3, "light hit pauses for three frames")
	_suite.assert_equal(finisher_profile.get("pause_frames"), 5, "finisher pauses for five frames")
	_suite.assert_equal(heavy_profile.get("pause_frames"), 6, "heavy hit pauses for six frames")
	_suite.assert_equal(hostile_profile.get("pause_frames"), 2, "player hurt pauses for two frames")
	_suite.assert_true(
		float(heavy_profile.get("camera_trauma", 0.0)) > float(light_profile.get("camera_trauma", 0.0)),
		"heavy hit camera feedback exceeds light hit"
	)
	_suite.assert_equal(heavy_profile.get("audio_cue"), &"hit_heavy", "heavy hit has a distinct cue")
	_suite.assert_equal(hostile_profile.get("audio_cue"), &"player_hurt", "player hurt has a distinct cue")


func _assert_audio_contract() -> void:
	var contract: Dictionary = CombatFeedback.get_audio_contract_for_test()
	var cues: Dictionary = contract.get("cues", {})
	_suite.assert_true(cues.size() >= 8, "M1 synthesized audio library covers core combat events")
	_suite.assert_equal(contract.get("bus"), &"SFX", "combat cues route through the dedicated SFX bus")
	for cue_id: Variant in cues.keys():
		var cue: Dictionary = cues[cue_id]
		_suite.assert_true(int(cue.get("data_bytes", 0)) > 0, "audio cue %s has PCM data" % str(cue_id))
		_suite.assert_equal(int(cue.get("mix_rate", 0)), 22050, "audio cue %s uses the M1 mix rate" % str(cue_id))
	_suite.assert_true(
		cues.get(&"time_stop", {}).get("fingerprint") != cues.get(&"time_rewind", {}).get("fingerprint"),
		"Time Stop and Rewind have distinct audio signatures"
	)


func _assert_audio_cleanup_contract() -> void:
	_suite.assert_true(CombatFeedback.play_audio_cue_for_test(&"enemy_death"), "audio cue can start")
	_suite.assert_true(CombatFeedback.play_audio_cue_for_test(&"time_rewind"), "overlapping cue can start")
	var active: Dictionary = CombatFeedback.get_audio_contract_for_test()
	if bool(active.get("headless_playback_suppressed", false)):
		_suite.assert_equal(active.get("active_voice_count"), 0, "headless validation does not allocate audio playback")
	else:
		_suite.assert_true(int(active.get("active_voice_count", 0)) >= 1, "cleanup test begins with active playback")
	_suite.assert_true(int(active.get("assigned_stream_count", 0)) >= 1, "active voices retain their streams")
	CombatFeedback.reset_transient_feedback()
	for _frame: int in range(6):
		await get_tree().process_frame
	var cleaned: Dictionary = CombatFeedback.get_audio_contract_for_test()
	_suite.assert_equal(cleaned.get("active_voice_count"), 0, "production reset stops every SFX voice")
	_suite.assert_equal(cleaned.get("assigned_stream_count"), 0, "production reset releases every voice stream")


func _assert_overlay_contract() -> void:
	CombatFeedback.preview_time_feedback_for_test(&"time_stop")
	var stop_snapshot: Dictionary = CombatFeedback.get_overlay_snapshot_for_test()
	CombatFeedback.preview_time_feedback_for_test(&"time_rewind")
	var rewind_snapshot: Dictionary = CombatFeedback.get_overlay_snapshot_for_test()
	_suite.assert_equal(stop_snapshot.get("mode"), "time_stop", "Time Stop overlay is explicit")
	_suite.assert_equal(rewind_snapshot.get("mode"), "time_rewind", "Rewind overlay is explicit")
	_suite.assert_true(
		stop_snapshot.get("accent") != rewind_snapshot.get("accent"),
		"Time Stop and Rewind use distinct visual language"
	)
	_suite.assert_true(
		stop_snapshot.get("pattern") != rewind_snapshot.get("pattern"),
		"time abilities use distinct overlay shapes"
	)


func _assert_feedback_runtime_gates() -> void:
	var stage := Node2D.new()
	stage.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(stage)
	var player := PlayerScene.instantiate()
	stage.add_child(player)
	await get_tree().process_frame
	var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
	_suite.assert_true(proxy != null, "runtime-gate test receives a player proxy")
	if proxy == null:
		stage.queue_free()
		await get_tree().process_frame
		return

	CombatFeedback.set_feedback_options({
		"camera_shake_enabled": false,
		"hit_flash_enabled": false,
		"reduced_motion": false,
	})
	CombatFeedback.add_camera_trauma(8.0)
	_suite.assert_close(
		float(CombatFeedback.get_camera_feedback_snapshot_for_test().get("trauma", -1.0)),
		0.0,
		"camera shake can be disabled at runtime"
	)
	proxy.play_action(&"hit")
	proxy.advance_animation_for_test(0.01)
	_suite.assert_true(not bool(proxy.get_snapshot_for_test().get("flash_active", true)), "actor hit flash can be disabled")
	CombatFeedback.preview_hit_feedback_for_test(true)
	_suite.assert_true(
		not bool(CombatFeedback.get_overlay_snapshot_for_test().get("hit_active", true)),
		"screen hit flash can be disabled"
	)

	CombatFeedback.set_feedback_options({
		"camera_shake_enabled": true,
		"hit_flash_enabled": true,
		"reduced_motion": true,
	})
	_suite.assert_true(bool(proxy.get_snapshot_for_test().get("reduced_motion", false)), "reduced motion reaches live proxies")
	_suite.assert_true(proxy.spawn_afterimage(player.global_position) == null, "reduced motion suppresses afterimages")
	CombatFeedback.add_camera_trauma(8.0)
	_suite.assert_close(
		float(CombatFeedback.get_camera_feedback_snapshot_for_test().get("trauma", -1.0)),
		0.0,
		"reduced motion suppresses camera shake"
	)

	CombatFeedback.set_feedback_options({
		"camera_shake_enabled": true,
		"hit_flash_enabled": true,
		"reduced_motion": false,
	})
	stage.queue_free()
	await get_tree().process_frame


func _assert_floating_text_contract() -> void:
	var layer := FloatingTextScript.new()
	var camera := Camera2D.new()
	camera.position = Vector2(640.0, 360.0)
	camera.zoom = Vector2(0.5, 0.5)
	camera.enabled = true
	var target := Node2D.new()
	target.position = Vector2(720.0, 400.0)
	add_child(camera)
	add_child(layer)
	add_child(target)
	await get_tree().process_frame
	await get_tree().process_frame
	var heavy := DamageInfoScript.new(42.0, DamageInfoScript.DamageType.PHYSICAL)
	heavy.tags.append("weapon:sword")
	heavy.tags.append("attack:heavy")
	var expected_anchor := target.get_viewport().get_canvas_transform() * target.global_position
	var expected_start := Vector2(roundf(expected_anchor.x - 18.0), roundf(expected_anchor.y - 42.0))
	EventBus.hit_confirmed.emit(heavy, target, 42.0)
	await get_tree().process_frame
	var snapshots: Array[Dictionary] = layer.get_active_text_snapshots_for_test()
	_suite.assert_equal(snapshots.size(), 1, "one logical hit creates one damage number")
	if not snapshots.is_empty():
		var snapshot: Dictionary = snapshots[0]
		_suite.assert_equal(snapshot.get("text"), "!42", "heavy hit damage text is recognizable")
		_suite.assert_true(bool(snapshot.get("pixel_snapped")), "damage text is pixel snapped")
		_suite.assert_equal(
			snapshot.get("start"),
			expected_start,
			"damage text converts world position through the active camera canvas transform"
		)
		_suite.assert_true(
			(snapshot.get("start") as Vector2).distance_to(target.global_position) > 100.0,
			"camera-space damage text is not placed at raw world coordinates"
		)
		_suite.assert_true(int(snapshot.get("font_size", 0)) > 16, "power hit uses stronger text hierarchy")
		_suite.assert_true(int(snapshot.get("outline_size", 0)) >= 2, "damage text keeps a readable hard outline")
	layer.queue_free()
	target.queue_free()
	camera.queue_free()
	CombatFeedback.reset_transient_feedback()
	for _frame: int in range(6):
		await get_tree().process_frame
