extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const ChaserScene := preload("res://scenes/enemies/enemy_chaser.tscn")
const TankScene := preload("res://scenes/enemies/enemy_tank.tscn")
const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")
const FloatingTextScript := preload("res://scripts/ui/floating_text_layer.gd")
const CombatFeedbackOverlayScript := preload("res://scripts/presentation/combat_feedback_overlay.gd")
const CombatTelegraphScript := preload("res://scripts/fx/combat_telegraph_2d.gd")
const PixelProxyActorScript := preload("res://scripts/presentation/pixel_proxy_actor.gd")

var _suite


class SnapshotPlayer extends Node2D:
	var weapon_snapshot: Dictionary = {
		"weapon_id": "sword",
		"action_id": "",
		"phase": "READY",
		"runtime": {"facing": Vector2.RIGHT},
	}
	var rewind_facing := Vector2.DOWN
	var character_snapshot: Dictionary = {
		"runtime_kind": "wanderer",
		"resource_value": 0,
		"resource_maximum": 5,
	}


	func _init() -> void:
		add_to_group("player")
		var visual := Polygon2D.new()
		visual.name = "Visual"
		add_child(visual)


	func weapon_presentation_snapshot() -> Dictionary:
		return weapon_snapshot.duplicate(true)


	func get_rewind_facing() -> Vector2:
		return rewind_facing


	func character_presentation_snapshot() -> Dictionary:
		return character_snapshot.duplicate(true)


class VelocityActor extends CharacterBody2D:
	func _init() -> void:
		var visual := Polygon2D.new()
		visual.name = "Visual"
		add_child(visual)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _assert_pixel_proxy_contract()
	_assert_hit_pause_duration_contract()
	_assert_hit_feedback_profiles()
	_assert_audio_contract()
	await _assert_bow_feedback_contract()
	await _assert_gun_feedback_contract()
	await _assert_staff_feedback_contract()
	await _assert_gauntlets_feedback_contract()
	await _assert_character_profile_feedback_contract()
	await _assert_active_item_feedback_contract()
	await _assert_high_frequency_feedback_budget()
	await _assert_unknown_weapon_fails_closed()
	await _assert_audio_cleanup_contract()
	_assert_overlay_contract()
	await _assert_feedback_runtime_gates()
	await _assert_floating_text_contract()
	await _assert_player_weapon_snapshot_proxy_contract()
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
	chaser.configure_hostile_identity(&"feedback-chaser", 1)
	tank.configure_hostile_identity(&"feedback-tank", 1)
	boss.configure_hostile_identity(&"feedback-boss", 1)
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
		_suite.assert_equal(player.sword_weapon.rotation, weapon_rotation, "proxy does not mutate the runtime adapter angle")


func _assert_player_weapon_snapshot_proxy_contract() -> void:
	var player := SnapshotPlayer.new()
	add_child(player)
	var proxy := PixelProxyActorScript.new()
	player.add_child(proxy)
	_suite.assert_true(proxy.bind_actor(player), "snapshot-only player binds to Pixel Proxy")

	player.weapon_snapshot = {
		"weapon_id": "sword",
		"action_id": "light_2",
		"phase": "WINDUP",
		"runtime": {"facing": Vector2.LEFT},
	}
	proxy.advance_animation_for_test(0.01)
	var windup: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(windup.get("state"), "attack", "weapon phase drives player attack presentation")
	_suite.assert_equal(windup.get("weapon_phase"), "WINDUP", "proxy preserves the coordinator weapon phase")
	_suite.assert_equal(windup.get("weapon_action_id"), "light_2", "proxy preserves the coordinator action identity")
	_suite.assert_equal(windup.get("facing"), Vector2.LEFT, "weapon runtime snapshot drives attack facing")
	_suite.assert_equal(windup.get("attack_direction"), Vector2.LEFT, "attack direction follows snapshot facing")

	player.weapon_snapshot = {
		"weapon_id": "sword",
		"action_id": "",
		"phase": "READY",
		"runtime": {"facing": Vector2.LEFT},
	}
	proxy.advance_animation_for_test(0.01)
	var ready: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(ready.get("state"), "idle", "ready weapon snapshot ends attack presentation")
	_suite.assert_equal(ready.get("facing"), Vector2.DOWN, "non-weapon presentation keeps gameplay facing fallback")

	player.weapon_snapshot = {
		"weapon_id": "sword",
		"action_id": "light_3",
		"phase": "ACTIVE",
		"facing": Vector2.UP,
		"runtime": {},
	}
	proxy.advance_animation_for_test(0.01)
	var top_level: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(top_level.get("facing"), Vector2.UP, "top-level weapon facing remains a compatible snapshot shape")

	player.weapon_snapshot = {
		"weapon_id": "bow",
		"action_id": "bow.primary",
		"phase": "HOLD",
		"token": 73,
		"charge_ratio": 0.72,
		"full_charge": false,
		"facing": Vector2.RIGHT,
	}
	proxy.advance_animation_for_test(0.01)
	var bow_hold: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(bow_hold.get("state"), "attack", "Bow hold has an explicit weapon presentation state")
	_suite.assert_equal(bow_hold.get("weapon_id"), "bow", "proxy preserves the equipped Bow identity")
	_suite.assert_equal(bow_hold.get("weapon_visual"), "bow", "Bow snapshot selects a bow silhouette instead of a sword line")
	_suite.assert_equal(bow_hold.get("bow_charge_tier"), "high", "Bow presentation exposes a deterministic charge tier")
	_suite.assert_close(float(bow_hold.get("bow_tension", -1.0)), 0.72, "Bow string tension follows the coordinator snapshot")
	_suite.assert_true(not bool(bow_hold.get("melee_slash_visible", true)), "Bow hold never exposes the melee slash primitive")

	player.weapon_snapshot = {
		"weapon_id": "bow",
		"action_id": "bow.primary",
		"phase": "ACTIVE",
		"token": 73,
		"charge_ratio": 1.0,
		"full_charge": true,
		"facing": Vector2.RIGHT,
	}
	proxy.advance_animation_for_test(0.01)
	var bow_release: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(bow_release.get("bow_charge_tier"), "full", "full-charge Bow release has a distinct presentation tier")
	_suite.assert_close(float(bow_release.get("bow_tension", -1.0)), 1.0, "full-charge Bow release preserves maximum tension")

	var velocity_actor := VelocityActor.new()
	velocity_actor.velocity = Vector2.LEFT * 100.0
	add_child(velocity_actor)
	var velocity_proxy := PixelProxyActorScript.new()
	velocity_actor.add_child(velocity_proxy)
	_suite.assert_true(velocity_proxy.bind_actor(velocity_actor), "non-player velocity actor binds to Pixel Proxy")
	velocity_proxy.advance_animation_for_test(0.01)
	_suite.assert_equal(
		velocity_proxy.get_snapshot_for_test().get("facing"),
		Vector2.LEFT,
		"non-player actors retain the velocity-facing fallback"
	)

	player.queue_free()
	velocity_actor.queue_free()
	await get_tree().process_frame


func _assert_character_profile_feedback_contract() -> void:
	CombatFeedback.reset_feedback_for_test()
	var player := SnapshotPlayer.new()
	add_child(player)
	await get_tree().process_frame
	var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
	_suite.assert_true(proxy != null, "character feedback probe receives a player proxy")
	if proxy == null:
		player.queue_free()
		return
	var cases: Array[Dictionary] = [
		{"character": "wanderer", "resource": 3, "maximum": 5, "skill": "waypoint_recall"},
		{"character": "time_guardian", "resource": 2, "maximum": 3, "skill": "chrono_fortress"},
		{"character": "void_walker", "resource": 75, "maximum": 100, "skill": "void_devour"},
		{"character": "primordial_knight", "resource": 2, "maximum": 3, "skill": "realm_cleave"},
		{"character": "time_lord", "resource": 2, "maximum": 3, "skill": "codex_dominion"},
	]
	var palette_ids: Array[String] = []
	for case: Dictionary in cases:
		player.character_snapshot = {
			"runtime_kind": case["character"],
			"resource_value": case["resource"],
			"resource_maximum": case["maximum"],
		}
		proxy.advance_animation_for_test(0.01)
		var snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(snapshot.get("character_profile_id"), case["character"], "%s selects its visual profile" % case["character"])
		_suite.assert_close(float(snapshot.get("character_resource_ratio", -1.0)), float(case["resource"]) / float(case["maximum"]), "%s resource aura follows its meter" % case["character"])
		_suite.assert_equal(snapshot.get("character_skill_cue_id"), case["skill"], "%s selects its profile skill cue" % case["character"])
		palette_ids.append(str(snapshot.get("palette_id", "")))
	var unique_palettes: Dictionary = {}
	for palette_id: String in palette_ids:
		unique_palettes[palette_id] = true
	_suite.assert_equal(unique_palettes.size(), 5, "all five characters have distinct profile palettes")

	var budget: Dictionary = CombatFeedback.get_feedback_budget_snapshot_for_test()
	var profile_limits := budget.get("character_profile_limits", {}) as Dictionary
	for case: Dictionary in cases:
		_suite.assert_true(int(profile_limits.get(case["character"], 0)) > 0, "%s has an explicit cue budget" % case["character"])

	player.character_snapshot = {"runtime_kind": "time_lord", "resource_value": 2, "resource_maximum": 3}
	proxy.advance_animation_for_test(0.01)
	CombatFeedback.set_feedback_options({
		"camera_shake_enabled": false,
		"hit_flash_enabled": false,
		"reduced_motion": true,
		"high_contrast_danger": true,
		"subtitles_enabled": false,
		"subtitle_scale": 1.5,
		"master_volume": 0.0,
		"sfx_volume": 1.0,
	})
	_suite.assert_true(
		CombatFeedback.present_character_skill_result_for_test(player, &"time_lord", &"codex_dominion", true, &""),
		"accepted character skill emits its bounded profile cue"
	)
	var success_snapshot: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(success_snapshot.get("character_cue_kind"), "success", "accepted character skill uses success presentation")
	_suite.assert_true(not bool(success_snapshot.get("flash_active", true)), "disabled flash reaches character cues")
	_suite.assert_close(float(CombatFeedback.get_camera_feedback_snapshot_for_test().get("trauma", -1.0)), 0.0, "reduced motion suppresses character cue shake")

	proxy.advance_animation_for_test(1.0)
	_suite.assert_true(
		CombatFeedback.present_character_skill_result_for_test(player, &"time_lord", &"codex_dominion", false, &"cooldown"),
		"rejected character skill emits accessible rejection feedback"
	)
	var rejection_snapshot: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(rejection_snapshot.get("character_cue_kind"), "rejected", "rejection uses a distinct cue kind")
	_suite.assert_true(bool(rejection_snapshot.get("character_rejection_active", false)), "rejection keeps a geometry cue when subtitles are disabled")
	_suite.assert_true(not bool(rejection_snapshot.get("character_success_active", true)), "rejection never replays the success animation")
	_suite.assert_true(bool(rejection_snapshot.get("high_contrast_character_feedback", false)), "rejection respects high-contrast feedback")
	var accessible: Dictionary = CombatFeedback.get_character_feedback_snapshot_for_test()
	_suite.assert_true(not bool(accessible.get("subtitle_visible", true)), "subtitle preference is respected")
	_suite.assert_equal(accessible.get("subtitle_scale"), 1.5, "subtitle scale remains available to accessible feedback")
	_suite.assert_close(float(accessible.get("audio_intensity", -1.0)), 0.0, "muted volume suppresses character cue audio")
	_suite.assert_equal(accessible.get("reason"), "cooldown", "rejection reason remains machine-readable")

	CombatFeedback.reset_feedback_for_test()
	var limit := int(profile_limits.get("time_lord", 0))
	for index: int in range(limit + 2):
		CombatFeedback.present_character_skill_result_for_test(
			player,
			&"time_lord",
			&"codex_dominion",
			true,
			StringName("probe_%d" % index)
		)
	budget = CombatFeedback.get_feedback_budget_snapshot_for_test()
	_suite.assert_equal((budget.get("character_cues_accepted", {}) as Dictionary).get("time_lord"), limit, "Time Lord cue budget caps accepted cues")
	_suite.assert_equal((budget.get("character_cues_rejected", {}) as Dictionary).get("time_lord"), 2, "Time Lord cue budget rejects overflow deterministically")

	CombatFeedback.set_feedback_options({
		"camera_shake_enabled": true,
		"hit_flash_enabled": true,
		"reduced_motion": false,
		"high_contrast_danger": false,
		"subtitles_enabled": true,
		"subtitle_scale": 1.0,
		"master_volume": 0.85,
		"sfx_volume": 0.9,
	})
	player.queue_free()
	await get_tree().process_frame


func _assert_active_item_feedback_contract() -> void:
	var player := SnapshotPlayer.new()
	add_child(player)
	await get_tree().process_frame
	var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
	_suite.assert_true(proxy != null, "active-item feedback receives a player proxy")
	_suite.assert_true(
		CombatFeedback.has_method("present_active_item_result_for_test"),
		"combat feedback exposes active-item presentation"
	)
	_suite.assert_true(
		CombatFeedback.has_method("get_active_item_feedback_snapshot_for_test"),
		"combat feedback exposes active-item accessibility evidence"
	)
	if (
		proxy == null
		or not CombatFeedback.has_method("present_active_item_result_for_test")
		or not CombatFeedback.has_method("get_active_item_feedback_snapshot_for_test")
	):
		player.queue_free()
		await get_tree().process_frame
		return

	CombatFeedback.reset_feedback_for_test()
	CombatFeedback.set_feedback_options({
		"camera_shake_enabled": true,
		"hit_flash_enabled": true,
		"reduced_motion": true,
		"high_contrast_danger": true,
		"subtitles_enabled": true,
		"subtitle_scale": 1.5,
		"master_volume": 0.85,
		"sfx_volume": 0.9,
	})
	_suite.assert_true(
		CombatFeedback.present_active_item_result_for_test(
			player,
			&"absolute_zero_device",
			&"absolute_zero",
			true,
			&""
		),
		"accepted active item emits its bounded feedback cue"
	)
	var proxy_snapshot: Dictionary = proxy.get_snapshot_for_test()
	_suite.assert_equal(proxy_snapshot.get("active_item_cue_id"), "absolute_zero", "active handler selects a closed pixel cue")
	_suite.assert_equal(proxy_snapshot.get("active_item_cue_kind"), "success", "accepted active uses success geometry")
	_suite.assert_true(bool(proxy_snapshot.get("active_item_cue_active", false)), "active cue remains visible under reduced motion")
	_suite.assert_true(bool(proxy_snapshot.get("high_contrast_active_item_feedback", false)), "active cue respects high contrast")
	_suite.assert_close(
		float(CombatFeedback.get_camera_feedback_snapshot_for_test().get("trauma", -1.0)),
		0.0,
		"reduced motion suppresses active-item camera shake"
	)
	var accessible: Dictionary = CombatFeedback.get_active_item_feedback_snapshot_for_test()
	_suite.assert_equal(accessible.get("content_id"), "absolute_zero_device", "feedback keeps content identity")
	_suite.assert_equal(accessible.get("subtitle_key"), "ABSOLUTE_ZERO_DEVICE_NAME", "active subtitle uses a localized content key")
	_suite.assert_equal(accessible.get("status_key"), "HUD_WEAPON_READY", "accepted subtitle status is localized")
	_suite.assert_true(bool(accessible.get("subtitle_visible", false)), "subtitle preference is respected")
	_suite.assert_equal(accessible.get("subtitle_scale"), 1.5, "active subtitle scale follows accessibility settings")
	var audio_history: Array = CombatFeedback.get_audio_contract_for_test().get("history", [])
	_suite.assert_true(audio_history.has(&"time_stop"), "active item routes through the synthesized audio contract")

	proxy.advance_animation_for_test(1.0)
	_suite.assert_true(
		CombatFeedback.present_active_item_result_for_test(
			player,
			&"absolute_zero_device",
			&"absolute_zero",
			false,
			&"cooldown_active"
		),
		"rejected active item emits a distinct accessible cue"
	)
	proxy_snapshot = proxy.get_snapshot_for_test()
	_suite.assert_equal(proxy_snapshot.get("active_item_cue_kind"), "rejected", "active rejection uses distinct geometry")
	accessible = CombatFeedback.get_active_item_feedback_snapshot_for_test()
	_suite.assert_equal(accessible.get("reason"), "cooldown_active", "active rejection reason remains machine-readable")
	_suite.assert_equal(accessible.get("status_key"), "HUD_WEAPON_COOLDOWN_FMT", "cooldown rejection exposes a localized status key")

	CombatFeedback.reset_feedback_for_test()
	var budget: Dictionary = CombatFeedback.get_feedback_budget_snapshot_for_test()
	var limit := int(budget.get("max_active_item_cues", 0))
	_suite.assert_true(limit > 0, "active-item feedback has an explicit per-window budget")
	for index: int in range(limit + 2):
		CombatFeedback.present_active_item_result_for_test(
			player,
			&"absolute_zero_device",
			&"absolute_zero",
			true,
			StringName("probe_%d" % index)
		)
	budget = CombatFeedback.get_feedback_budget_snapshot_for_test()
	_suite.assert_equal(budget.get("active_item_cues_accepted"), limit, "active-item cue budget caps accepted cues")
	_suite.assert_equal(budget.get("active_item_cues_rejected"), 2, "active-item cue budget rejects overflow deterministically")

	CombatFeedback.set_feedback_options({
		"camera_shake_enabled": true,
		"hit_flash_enabled": true,
		"reduced_motion": false,
		"high_contrast_danger": false,
		"subtitles_enabled": true,
		"subtitle_scale": 1.0,
		"master_volume": 0.85,
		"sfx_volume": 0.9,
	})
	player.queue_free()
	await get_tree().process_frame


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
	var light := _feedback_damage(10.0, ["weapon:sword"], 1)
	var finisher := _feedback_damage(10.0, ["weapon:sword", "attack:finisher"], 2)
	var heavy := _feedback_damage(10.0, ["weapon:sword", "attack:heavy"], 3)
	var hostile := _feedback_damage(10.0, ["enemy:melee"], 4)
	var gauntlets := _feedback_damage(10.0, ["weapon:gauntlets"], 5)

	var light_profile: Dictionary = CombatFeedback.get_hit_profile_for_test(light, false)
	var finisher_profile: Dictionary = CombatFeedback.get_hit_profile_for_test(finisher, false)
	var heavy_profile: Dictionary = CombatFeedback.get_hit_profile_for_test(heavy, false)
	var hostile_profile: Dictionary = CombatFeedback.get_hit_profile_for_test(hostile, true)
	var gauntlets_profile: Dictionary = CombatFeedback.get_hit_profile_for_test(gauntlets, false)
	_suite.assert_equal(light_profile.get("pause_frames"), 3, "light hit pauses for three frames")
	_suite.assert_equal(finisher_profile.get("pause_frames"), 5, "finisher pauses for five frames")
	_suite.assert_equal(heavy_profile.get("pause_frames"), 6, "heavy hit pauses for six frames")
	_suite.assert_equal(hostile_profile.get("pause_frames"), 2, "player hurt pauses for two frames")
	_suite.assert_equal(gauntlets_profile.get("pause_frames"), 3, "Gauntlets contact keeps a crisp three-frame hit pause")
	_suite.assert_equal(gauntlets_profile.get("audio_cue"), &"hit_light", "Gauntlets contact keeps the dedicated impact audio path")
	_suite.assert_close(float(gauntlets_profile.get("camera_trauma", 0.0)), 3.0, "Gauntlets contact keeps its light-hit camera response")
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
	_suite.assert_true(cues.has(&"bow_release"), "Bow profile release cue has a dedicated audio signature")
	_suite.assert_true(cues.has(&"bow_tension_low"), "Bow tension can expose a low-tier audio signature")
	_suite.assert_true(cues.has(&"bow_tension_high"), "Bow tension can expose a high-tier audio signature")
	_suite.assert_true(
		cues.get(&"bow_release", {}).get("fingerprint") != cues.get(&"sword_swing", {}).get("fingerprint"),
		"Bow release never aliases the Sword swing signature"
	)
	for cue_id: StringName in [
		&"gun_fire",
		&"gun_aimed_fire",
		&"gun_shotgun",
		&"gun_reload",
		&"gun_time_load",
		&"gun_ultimate",
	]:
		_suite.assert_true(cues.has(cue_id), "Gun cue %s has a dedicated audio signature" % str(cue_id))
		_suite.assert_true(
			cues.get(cue_id, {}).get("fingerprint") != cues.get(&"sword_swing", {}).get("fingerprint"),
			"Gun cue %s never aliases the Sword swing signature" % str(cue_id)
		)
	for cue_id: StringName in [
		&"staff_basic",
		&"staff_element_cast",
		&"staff_cycle",
		&"staff_skill",
		&"staff_ultimate",
	]:
		_suite.assert_true(cues.has(cue_id), "Staff cue %s has a dedicated audio signature" % str(cue_id))
		_suite.assert_true(
			cues.get(cue_id, {}).get("fingerprint") != cues.get(&"sword_swing", {}).get("fingerprint"),
			"Staff cue %s never aliases the Sword swing signature" % str(cue_id)
		)
	for cue_id: StringName in [
		&"gauntlets_jab",
		&"gauntlets_hook",
		&"gauntlets_uppercut",
		&"gauntlets_charged",
		&"gauntlets_counter",
		&"gauntlets_skill",
		&"gauntlets_ultimate",
	]:
		_suite.assert_true(cues.has(cue_id), "Gauntlets cue %s has a dedicated audio signature" % str(cue_id))
		_suite.assert_true(
			cues.get(cue_id, {}).get("fingerprint") != cues.get(&"sword_swing", {}).get("fingerprint"),
			"Gauntlets cue %s never aliases the Sword swing signature" % str(cue_id)
		)


func _assert_bow_feedback_contract() -> void:
	var player := SnapshotPlayer.new()
	player.weapon_snapshot = {
		"weapon_id": "bow",
		"action_id": "bow.primary",
		"phase": "ACTIVE",
		"token": 701,
		"charge_ratio": 0.72,
		"full_charge": false,
		"facing": Vector2.RIGHT,
	}
	add_child(player)
	await get_tree().process_frame
	_suite.assert_true(
		CombatFeedback.ensure_actor_proxy_for_test(player) != null,
		"Bow feedback probe receives a player proxy"
	)
	CombatFeedback.reset_feedback_for_test()

	EventBus.weapon_cue_requested.emit(
		&"bow",
		&"bow.primary",
		701,
		{
			"cue_id": "bow_candidate_release",
			"animation_id": "bow_release",
			"vfx_id": "bow_arrow_trail",
			"audio_id": "bow_release",
			"camera_id": "impact_light",
		}
	)
	EventBus.weapon_cue_requested.emit(
		&"bow",
		&"bow.primary",
		701,
		{
			"cue_id": "bow_candidate_release",
			"animation_id": "bow_release",
			"vfx_id": "bow_arrow_trail",
			"audio_id": "bow_release",
			"camera_id": "impact_light",
		}
	)
	var history: Array = CombatFeedback.get_audio_contract_for_test().get("history", [])
	_suite.assert_equal(history.count(&"bow_release"), 1, "one Bow action token plays its Profile release cue exactly once")
	_suite.assert_equal(history.count(&"sword_swing"), 0, "Bow release never falls back to the legacy Sword cue")

	EventBus.weapon_cue_requested.emit(
		&"bow",
		&"bow.primary",
		701,
		{
			"cue_id": "bow_tension_high",
			"animation_id": "bow_tension",
			"vfx_id": "bow_tension_high",
			"audio_id": "bow_tension_high",
			"camera_id": "",
		}
	)
	EventBus.weapon_cue_requested.emit(
		&"bow",
		&"bow.primary",
		702,
		{
			"cue_id": "bow_candidate_release",
			"animation_id": "bow_release",
			"vfx_id": "bow_arrow_trail",
			"audio_id": "bow_release",
			"camera_id": "impact_light",
		}
	)
	history = CombatFeedback.get_audio_contract_for_test().get("history", [])
	_suite.assert_equal(history.count(&"bow_tension_high"), 1, "one token can carry a distinct future Bow tension cue")
	_suite.assert_equal(history.count(&"bow_release"), 2, "a later Bow token receives its own release cue")
	CombatFeedback.reset_feedback_for_test()
	EventBus.weapon_cue_requested.emit(
		&"bow",
		&"bow.primary",
		701,
		{
			"cue_id": "bow_candidate_release",
			"animation_id": "bow_release",
			"vfx_id": "bow_arrow_trail",
			"audio_id": "bow_release",
			"camera_id": "impact_light",
		}
	)
	history = CombatFeedback.get_audio_contract_for_test().get("history", [])
	_suite.assert_equal(history.count(&"bow_release"), 1, "feedback reset permits token reuse in a later run")

	player.queue_free()
	await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()


func _assert_gun_feedback_contract() -> void:
	var player := SnapshotPlayer.new()
	player.weapon_snapshot = {
		"weapon_id": "gun",
		"action_id": "normal_fire",
		"phase": "ACTIVE",
		"token": 801,
		"ammo": 5,
		"ammo_maximum": 6,
		"reload_frame": -1,
		"reload_window": {"segment": "invalid", "perfect_confirm": false},
		"time_load_source": "",
		"time_load_remaining_frames": 0,
		"facing": Vector2.RIGHT,
	}
	add_child(player)
	await get_tree().process_frame
	var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
	_suite.assert_true(proxy != null, "Gun feedback probe receives a player proxy")
	CombatFeedback.reset_feedback_for_test()

	EventBus.weapon_cue_requested.emit(
		&"gun",
		&"normal_fire",
		801,
		{
			"cue_id": "gun_normal_fire",
			"animation_id": "gun_fire",
			"vfx_id": "gun_muzzle",
			"audio_id": "gun_fire",
			"camera_id": "impact_light",
		}
	)
	EventBus.weapon_cue_requested.emit(
		&"gun",
		&"normal_fire",
		801,
		{
			"cue_id": "gun_normal_fire",
			"animation_id": "gun_fire",
			"vfx_id": "gun_muzzle",
			"audio_id": "gun_fire",
			"camera_id": "impact_light",
		}
	)
	var history: Array = CombatFeedback.get_audio_contract_for_test().get("history", [])
	_suite.assert_equal(history.count(&"gun_fire"), 1, "one Gun action token plays its Profile fire cue exactly once")
	_suite.assert_equal(history.count(&"sword_swing"), 0, "Gun fire never falls back to the legacy Sword cue")
	if proxy != null:
		proxy.advance_animation_for_test(0.01)
		var fire_snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(fire_snapshot.get("weapon_visual"), "gun", "Gun cue keeps a firearm silhouette")
		_suite.assert_true(bool(fire_snapshot.get("gun_muzzle_visible", false)), "Gun active fire exposes a muzzle cue")
		_suite.assert_true(not bool(fire_snapshot.get("melee_slash_visible", true)), "Gun fire never exposes the melee slash primitive")

	player.weapon_snapshot = {
		"weapon_id": "gun",
		"action_id": "reload",
		"phase": "RESOURCE_ACTION",
		"token": 802,
		"ammo": 1,
		"ammo_maximum": 6,
		"reload_frame": 30,
		"reload_window": {"segment": "perfect", "perfect_confirm": true},
		"time_load_source": "perfect_reload",
		"time_load_remaining_frames": 300,
		"facing": Vector2.LEFT,
	}
	if proxy != null:
		proxy.advance_animation_for_test(0.01)
		var reload_snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(reload_snapshot.get("state"), "attack", "Gun reload remains an explicit weapon presentation state")
		_suite.assert_true(bool(reload_snapshot.get("gun_reload_marker_visible", false)), "Gun reload exposes its progress marker")
		_suite.assert_true(bool(reload_snapshot.get("gun_perfect_ring_visible", false)), "perfect reload window exposes a shape cue")
		_suite.assert_true(bool(reload_snapshot.get("gun_time_load_active", false)), "free Time Load adds a persistent tint cue")
		_suite.assert_equal(reload_snapshot.get("facing"), Vector2.LEFT, "Gun reload reads snapshot facing")

	EventBus.weapon_cue_requested.emit(
		&"gun",
		&"reload",
		802,
		{
			"cue_id": "gun_reload_start",
			"animation_id": "gun_reload",
			"vfx_id": "gun_reload_marker",
			"audio_id": "gun_reload",
			"camera_id": "resource_action",
		}
	)
	history = CombatFeedback.get_audio_contract_for_test().get("history", [])
	_suite.assert_equal(history.count(&"gun_reload"), 1, "Gun reload has a dedicated cue")
	_suite.assert_equal(history.count(&"sword_swing"), 0, "Gun reload never aliases Sword audio")

	player.queue_free()
	await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()


func _assert_staff_feedback_contract() -> void:
	var player := SnapshotPlayer.new()
	player.weapon_snapshot = {
		"weapon_id": "staff",
		"action_id": "charged_element",
		"phase": "ACTIVE",
		"token": 901,
		"runtime": {
			"element": "ice",
			"combo_element": "fire",
			"combo_remaining_frames": 180,
			"pending_combo": {},
		},
		"facing": Vector2.RIGHT,
	}
	add_child(player)
	await get_tree().process_frame
	var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
	_suite.assert_true(proxy != null, "Staff feedback probe receives a player proxy")
	CombatFeedback.reset_feedback_for_test()


	EventBus.weapon_cue_requested.emit(
		&"staff",
		&"charged_element",
		901,
		{
			"cue_id": "staff_element_cast",
			"animation_id": "staff_charge",
			"vfx_id": "staff_element_cast",
			"audio_id": "staff_element_cast",
			"camera_id": "impact_medium",
		}
	)
	EventBus.weapon_cue_requested.emit(
		&"staff",
		&"charged_element",
		901,
		{
			"cue_id": "staff_element_cast",
			"animation_id": "staff_charge",
			"vfx_id": "staff_element_cast",
			"audio_id": "staff_element_cast",
			"camera_id": "impact_medium",
		}
	)
	var history: Array = CombatFeedback.get_audio_contract_for_test().get("history", [])
	_suite.assert_equal(history.count(&"staff_element_cast"), 1, "one Staff action token plays its cast cue exactly once")
	_suite.assert_equal(history.count(&"sword_swing"), 0, "Staff cast never falls back to the legacy Sword cue")
	if proxy != null:
		proxy.advance_animation_for_test(0.01)
		var cast_snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(cast_snapshot.get("weapon_visual"), "staff", "Staff cue keeps a staff silhouette")
		_suite.assert_equal(cast_snapshot.get("staff_element"), "ice", "Staff proxy reads the canonical runtime element")
		_suite.assert_true(bool(cast_snapshot.get("staff_cast_circle_visible", false)), "charged Staff cast exposes a cast circle")
		_suite.assert_true(bool(cast_snapshot.get("staff_combination_signature_visible", false)), "active sequence exposes a combination signature")
		_suite.assert_true(not bool(cast_snapshot.get("melee_slash_visible", true)), "Staff cast never exposes the melee slash primitive")

	player.weapon_snapshot = {
		"weapon_id": "staff",
		"action_id": "planar_collapse",
		"phase": "ACTIVE",
		"token": 902,
		"runtime": {
			"element": "lightning",
			"combo_element": "",
			"combo_remaining_frames": 0,
			"pending_combo": {},
		},
		"facing": Vector2.LEFT,
	}
	if proxy != null:
		proxy.advance_animation_for_test(0.01)
		var zone_snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_true(bool(zone_snapshot.get("staff_zone_boundary_visible", false)), "Plane Collapse exposes a zone boundary")
		_suite.assert_equal(zone_snapshot.get("staff_element"), "lightning", "Staff proxy updates from canonical runtime element changes")
		_suite.assert_true(not bool(zone_snapshot.get("staff_combination_signature_visible", true)), "expired Staff combo hides its signature")
		_suite.assert_equal(zone_snapshot.get("facing"), Vector2.LEFT, "Staff cast reads snapshot facing")

	player.queue_free()
	await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()


func _assert_gauntlets_feedback_contract() -> void:
	var player := SnapshotPlayer.new()
	player.weapon_snapshot = {
		"weapon_id": "gauntlets",
		"action_id": "dodge_counter",
		"phase": "ACTIVE",
		"token": 1001,
		"runtime": {
			"combo_count": 15,
			"chain_step": 0,
			"counter_ready": true,
		},
		"facing": Vector2.LEFT,
	}
	add_child(player)
	await get_tree().process_frame
	var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
	_suite.assert_true(proxy != null, "Gauntlets feedback probe receives a player proxy")
	CombatFeedback.reset_feedback_for_test()
	if proxy != null:
		proxy.advance_animation_for_test(0.01)
		var equipped_snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(
			equipped_snapshot.get("weapon_visual"),
			"gauntlets",
			"Gauntlets snapshot selects a fist silhouette instead of the Sword fallback"
		)
		_suite.assert_true(
			not bool(equipped_snapshot.get("melee_slash_visible", true)),
			"Gauntlets never exposes the Sword slash primitive"
		)

	EventBus.weapon_cue_requested.emit(
		&"gauntlets",
		&"dodge_counter",
		1001,
		{
			"cue_id": "gauntlets_dodge_counter",
			"animation_id": "gauntlets_counter",
			"vfx_id": "gauntlets_counter_line",
			"audio_id": "gauntlets_counter",
			"camera_id": "impact_heavy",
		}
	)
	EventBus.weapon_cue_requested.emit(
		&"gauntlets",
		&"dodge_counter",
		1001,
		{
			"cue_id": "gauntlets_dodge_counter",
			"animation_id": "gauntlets_counter",
			"vfx_id": "gauntlets_counter_line",
			"audio_id": "gauntlets_counter",
			"camera_id": "impact_heavy",
		}
	)
	var history: Array = CombatFeedback.get_audio_contract_for_test().get("history", [])
	_suite.assert_equal(history.count(&"gauntlets_counter"), 1, "one Gauntlets token plays its Counter cue exactly once")
	_suite.assert_equal(history.count(&"sword_swing"), 0, "Gauntlets never falls back to the legacy Sword cue")
	_suite.assert_true(
		float(CombatFeedback.get_camera_feedback_snapshot_for_test().get("trauma", 0.0)) >= 1.5,
		"Gauntlets Counter preserves the heavy camera response"
	)
	if proxy != null:
		var counter_snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(
			counter_snapshot.get("presentation_animation_id"),
			"gauntlets_counter",
			"CombatFeedback routes the Profile animation id into the player proxy"
		)
		_suite.assert_equal(
			counter_snapshot.get("presentation_vfx_id"),
			"gauntlets_counter_line",
			"CombatFeedback routes the Profile VFX id into the player proxy"
		)
		_suite.assert_true(
			bool(counter_snapshot.get("gauntlets_counter_line_visible", false)),
			"Dodge Counter renders a dedicated speed-line cue"
		)

	EventBus.weapon_cue_requested.emit(
		&"gauntlets",
		&"punch_1",
		1002,
		{
			"cue_id": "gauntlets_left_jab",
			"animation_id": "gauntlets_left_jab",
			"vfx_id": "gauntlets_jab_wind",
			"audio_id": "gauntlets_jab",
			"camera_id": "impact_light",
		}
	)
	if proxy != null:
		var left_snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(left_snapshot.get("gauntlets_lead_fist"), "left", "first punch visibly leads with the left fist")
		_suite.assert_true(bool(left_snapshot.get("gauntlets_punch_wind_visible", false)), "left jab renders a punch-wind trail")

	EventBus.weapon_cue_requested.emit(
		&"gauntlets",
		&"punch_2",
		1003,
		{
			"cue_id": "gauntlets_right_jab",
			"animation_id": "gauntlets_right_jab",
			"vfx_id": "gauntlets_jab_wind",
			"audio_id": "gauntlets_jab",
			"camera_id": "impact_light",
		}
	)
	if proxy != null:
		var right_snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(right_snapshot.get("gauntlets_lead_fist"), "right", "second punch visibly leads with the right fist")
		_suite.assert_true(bool(right_snapshot.get("gauntlets_punch_wind_visible", false)), "right jab keeps the punch-wind trail")
		proxy.advance_animation_for_test(0.30)
		var expired_snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_true(
			not bool(expired_snapshot.get("gauntlets_punch_wind_visible", true)),
			"transient punch wind expires instead of sticking to the actor"
		)

	player.queue_free()
	await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()


func _assert_high_frequency_feedback_budget() -> void:
	var player := SnapshotPlayer.new()
	add_child(player)
	await get_tree().process_frame
	var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
	_suite.assert_true(proxy != null, "feedback budget probe receives a player proxy")
	CombatFeedback.reset_feedback_for_test()
	var wall_clock_start := int(
		CombatFeedback.get_feedback_budget_snapshot_for_test().get("window_started_usec", 0)
	)
	Engine.time_scale = 0.01
	EventBus.weapon_cue_requested.emit(
		&"sword",
		&"light_chain",
		1999,
		{
			"cue_id": "sword_wall_clock_probe",
			"animation_id": "sword_light",
			"vfx_id": "sword_slash",
			"audio_id": "sword_swing",
			"camera_id": "",
		}
	)
	CombatFeedback.call("update_feedback_budget_clock_for_test", wall_clock_start + 1_010_000)
	var wall_clock_budget: Dictionary = CombatFeedback.get_feedback_budget_snapshot_for_test()
	_suite.assert_equal(
		wall_clock_budget.get("weapon_cues_accepted"),
		0,
		"feedback budget window follows monotonic wall time while gameplay time is slowed"
	)
	Engine.time_scale = 1.0
	CombatFeedback.reset_feedback_for_test()

	var patterns: Array[Dictionary] = [
		{"weapon": &"bow", "action": &"bow.primary", "cue": "bow_tension_high", "audio": "bow_tension_high"},
		{"weapon": &"gun", "action": &"reload", "cue": "gun_perfect_reload", "audio": "gun_reload"},
		{"weapon": &"staff", "action": &"charged_element", "cue": "staff_element_cast", "audio": "staff_element_cast"},
		{"weapon": &"gauntlets", "action": &"punch_1", "cue": "gauntlets_combo", "audio": "gauntlets_jab"},
	]
	for index: int in range(16):
		var pattern: Dictionary = patterns[index % patterns.size()]
		EventBus.weapon_cue_requested.emit(
			pattern["weapon"],
			pattern["action"],
			2000 + index,
			{
				"cue_id": pattern["cue"],
				"animation_id": pattern["cue"],
				"vfx_id": pattern["cue"],
				"audio_id": pattern["audio"],
				"camera_id": "",
			}
		)
	var budget: Dictionary = CombatFeedback.get_feedback_budget_snapshot_for_test()
	_suite.assert_equal(budget.get("weapon_cues_accepted"), 12, "high-frequency weapon feedback is capped per second")
	_suite.assert_equal(budget.get("weapon_cues_rejected"), 4, "excess weapon feedback is rejected deterministically")

	for _index: int in range(12):
		CombatFeedback.add_camera_trauma(20.0)
	budget = CombatFeedback.get_feedback_budget_snapshot_for_test()
	_suite.assert_equal(budget.get("camera_events_accepted"), 8, "camera feedback has a per-second event budget")
	_suite.assert_equal(budget.get("camera_events_rejected"), 4, "excess camera requests are suppressed")
	_suite.assert_true(
		float(CombatFeedback.get_camera_feedback_snapshot_for_test().get("trauma", 0.0)) <= 8.0,
		"camera trauma intensity remains capped"
	)

	if proxy != null:
		for _index: int in range(5):
			proxy.play_action(&"hit")
		var flash_snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(flash_snapshot.get("flash_events_accepted"), 3, "actor flashes stay at or below three per second")
		_suite.assert_equal(flash_snapshot.get("flash_events_rejected"), 2, "excess actor flashes are suppressed")

	var target := VelocityActor.new()
	add_child(target)
	await get_tree().process_frame
	var rapid_hit := _feedback_damage(8.0, ["weapon:gauntlets"], 6)
	for _index: int in range(14):
		EventBus.hit_confirmed.emit(rapid_hit, target, 8.0)
	budget = CombatFeedback.get_feedback_budget_snapshot_for_test()
	_suite.assert_equal(budget.get("hit_pauses_accepted"), 8, "rapid multi-hit pause is capped per second")
	_suite.assert_equal(budget.get("hit_pauses_rejected"), 6, "excess rapid hit pauses are suppressed")
	_suite.assert_equal(budget.get("hit_audio_accepted"), 12, "rapid multi-hit audio is capped per second")
	_suite.assert_equal(budget.get("hit_audio_rejected"), 2, "excess rapid hit audio is suppressed")
	_suite.assert_equal(budget.get("screen_flashes_accepted"), 3, "full-screen hit flashes remain capped during rapid hits")
	_suite.assert_equal(budget.get("screen_flashes_rejected"), 11, "excess full-screen hit flashes are suppressed")
	var hit_audio_history: Array = CombatFeedback.get_audio_contract_for_test().get("history", [])
	_suite.assert_equal(hit_audio_history.count(&"hit_light"), 12, "audio history contains only the accepted rapid-hit cues")
	target.queue_free()
	await get_tree().process_frame

	CombatFeedback.advance_feedback_budget_for_test(1.01)
	EventBus.weapon_cue_requested.emit(
		&"gauntlets",
		&"punch_2",
		3000,
		{
			"cue_id": "gauntlets_combo_next_window",
			"animation_id": "gauntlets_right_jab",
			"vfx_id": "gauntlets_jab_wind",
			"audio_id": "gauntlets_jab",
			"camera_id": "",
		}
	)
	budget = CombatFeedback.get_feedback_budget_snapshot_for_test()
	_suite.assert_equal(budget.get("weapon_cues_accepted"), 1, "feedback budget reopens after its one-second window")
	_suite.assert_equal(budget.get("weapon_cues_rejected"), 0, "new window starts without stale rejections")
	_suite.assert_equal(budget.get("hit_pauses_accepted"), 0, "new window clears rapid-hit pause accounting")
	_suite.assert_equal(budget.get("hit_audio_accepted"), 0, "new window clears rapid-hit audio accounting")

	player.queue_free()
	await get_tree().process_frame
	CombatFeedback.reset_feedback_for_test()


func _assert_unknown_weapon_fails_closed() -> void:
	CombatFeedback.reset_feedback_for_test()
	var player := SnapshotPlayer.new()
	player.weapon_snapshot = {
		"weapon_id": "unknown_weapon",
		"action_id": "unknown.primary",
		"phase": "ACTIVE",
		"token": 4001,
		"facing": Vector2.RIGHT,
	}
	add_child(player)
	await get_tree().process_frame
	var proxy: Node = CombatFeedback.ensure_actor_proxy_for_test(player)
	_suite.assert_true(proxy != null, "unknown-weapon probe receives a player proxy")
	if proxy != null:
		proxy.advance_animation_for_test(0.01)
		var snapshot: Dictionary = proxy.get_snapshot_for_test()
		_suite.assert_equal(snapshot.get("weapon_visual"), "", "unknown weapon presentation fails closed")
		_suite.assert_true(not bool(snapshot.get("melee_slash_visible", true)), "unknown weapon never renders the Sword slash")
	EventBus.weapon_cue_requested.emit(
		&"unknown_weapon",
		&"unknown.primary",
		4001,
		{
			"cue_id": "forged_unknown_weapon_cue",
			"animation_id": "sword_light",
			"vfx_id": "sword_slash",
			"audio_id": "sword_swing",
			"camera_id": "impact_ultimate",
		}
	)
	var audio_history: Array = CombatFeedback.get_audio_contract_for_test().get("history", [])
	_suite.assert_equal(audio_history.count(&"sword_swing"), 0, "unknown weapon cues cannot trigger known weapon audio")
	var budget: Dictionary = CombatFeedback.get_feedback_budget_snapshot_for_test()
	_suite.assert_equal(budget.get("weapon_cues_accepted"), 0, "unknown weapon cues do not consume the shared feedback budget")
	player.queue_free()
	await get_tree().process_frame


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

	var overlay = CombatFeedbackOverlayScript.new()
	add_child(overlay)
	overlay.set_danger_accessibility(true)
	overlay.set_low_health_ratio(0.2)
	var danger: Dictionary = overlay.get_snapshot_for_test()
	_suite.assert_true(bool(danger.get("high_contrast_danger", false)), "danger overlay enables high contrast")
	_suite.assert_true(
		_luminance(danger.get("danger_foreground", Color.BLACK))
			- _luminance(danger.get("danger_background", Color.WHITE)) >= 0.70,
		"danger overlay preserves at least 0.70 light/dark luminance separation"
	)
	_suite.assert_true(not str(danger.get("danger_pattern", "")).is_empty(), "danger remains color-independent through geometry")

	var telegraph = CombatTelegraphScript.new()
	add_child(telegraph)
	telegraph.set_accessibility_options(true, 1.5)
	telegraph.show_telegraph(
		"test",
		"circle",
		Vector2.ZERO,
		Vector2.RIGHT,
		Vector2.ZERO,
		[],
		20.0,
		40.0,
		1.0
	)
	var telegraph_snapshot: Dictionary = telegraph.get_snapshot()
	_suite.assert_close(float(telegraph_snapshot.get("radius", 0.0)), 30.0, "telegraph scale enlarges visual radius")
	_suite.assert_close(float(telegraph_snapshot.get("length", 0.0)), 60.0, "telegraph scale enlarges visual length")
	_suite.assert_close(float(telegraph_snapshot.get("remaining", 0.0)), 1.5, "telegraph scale extends visual lead only")
	_suite.assert_equal(telegraph_snapshot.get("shape"), "circle", "telegraph keeps its geometric cue")
	_suite.assert_true(bool(telegraph_snapshot.get("high_contrast_danger", false)), "telegraph uses the high-contrast palette")
	overlay.queue_free()
	telegraph.queue_free()


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
	var heavy := _feedback_damage(42.0, ["weapon:sword", "attack:heavy"], 7)
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


func _feedback_damage(amount: float, tags: Array[String], token: int) -> RefCounted:
	return DamageInfoScript.from_plan({
		"run_id": &"feedback_test",
		"target_id": &"feedback_target",
		"hostile_source_id": StringName("test:feedback:%d" % token),
		"attack_generation": token,
		"action_token": token,
		"amount": amount,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"source": self,
		"attacker": self,
		"tags": tags,
		"source_generation": token,
	})


func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
