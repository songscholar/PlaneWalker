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
	_assert_hit_feedback_profiles()
	_assert_audio_contract()
	await _assert_audio_cleanup_contract()
	_assert_overlay_contract()
	await _assert_floating_text_contract()
	CombatFeedback.reset_feedback_for_test()
	for _frame: int in range(6):
		await get_tree().process_frame
	_suite.finish(get_tree())


func _assert_pixel_proxy_contract() -> void:
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
	_suite.assert_true(not (player.get_node("Visual") as CanvasItem).visible, "legacy player polygon is replaced")
	_suite.assert_true(not (boss.get_node("Visual") as CanvasItem).visible, "legacy Boss polygon is replaced")
	_suite.assert_true(
		CombatFeedback.ensure_actor_proxy_for_test(player) == player_proxy,
		"proxy installation is idempotent"
	)

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

	stage.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


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


func _assert_floating_text_contract() -> void:
	var layer := FloatingTextScript.new()
	var target := Node2D.new()
	target.position = Vector2(103.4, 97.7)
	add_child(layer)
	add_child(target)
	var heavy := DamageInfoScript.new(42.0, DamageInfoScript.DamageType.PHYSICAL)
	heavy.tags.append("weapon:sword")
	heavy.tags.append("attack:heavy")
	EventBus.hit_confirmed.emit(heavy, target, 42.0)
	await get_tree().process_frame
	var snapshots: Array[Dictionary] = layer.get_active_text_snapshots_for_test()
	_suite.assert_equal(snapshots.size(), 1, "one logical hit creates one damage number")
	if not snapshots.is_empty():
		var snapshot: Dictionary = snapshots[0]
		_suite.assert_equal(snapshot.get("text"), "!42", "heavy hit damage text is recognizable")
		_suite.assert_true(bool(snapshot.get("pixel_snapped")), "damage text is pixel snapped")
		_suite.assert_true(int(snapshot.get("font_size", 0)) > 16, "power hit uses stronger text hierarchy")
		_suite.assert_true(int(snapshot.get("outline_size", 0)) >= 2, "damage text keeps a readable hard outline")
	layer.queue_free()
	target.queue_free()
	CombatFeedback.reset_transient_feedback()
	for _frame: int in range(6):
		await get_tree().process_frame
