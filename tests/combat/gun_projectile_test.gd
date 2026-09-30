extends Node

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const GunProjectileScene := preload("res://scenes/combat/gun_projectile.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


class RecordingEnemy extends Node2D:
	var rifted: bool = false
	var vulnerabilities: Array[Dictionary] = []


	func is_time_rifted() -> bool:
		return rifted


	func apply_damage_vulnerability(
		source_id: StringName,
		duration_frames: int,
		damage_taken_bonus: float
	) -> bool:
		vulnerabilities.append({
			"source_id": source_id,
			"duration_frames": duration_frames,
			"damage_taken_bonus": damage_taken_bonus,
		})
		return true


class RecordingBoss extends Node2D:
	var phase: String = "WINDUP"
	var exposed: bool = false
	var conversions: Array[Dictionary] = []


	func get_boss_ui_snapshot() -> Dictionary:
		return {
			"action": "AIMED",
			"phase": phase,
			"remaining": 1.0,
			"exposed": exposed,
		}


	func apply_weapon_control_conversion(
		source_id: StringName,
		recovery_frames: int,
		exposure_frames: int,
		poise_damage: float
	) -> bool:
		conversions.append({
			"source_id": source_id,
			"recovery_frames": recovery_frames,
			"exposure_frames": exposure_frames,
			"poise_damage": poise_damage,
		})
		return true


class RecordingHitArea extends Area2D:
	var received: Array[RefCounted] = []


	func receive_hit(damage_info: RefCounted) -> float:
		received.append(damage_info)
		return float(damage_info.get("amount"))


class RecordingStopOwner extends Node2D:
	var extensions: Array[Dictionary] = []
	var claimed_tokens: Dictionary = {}


	func extend_weapon_time_stop(action_token: int, extension_frames: int) -> bool:
		if claimed_tokens.has(action_token):
			return false
		claimed_tokens[action_token] = true
		extensions.append({"action_token": action_token, "extension_frames": extension_frames})
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_configuration_contract_covers_launch_projectiles()
	await _test_execution_snapshot_restores_live_flight_and_claims_atomically()
	await _test_shotgun_deduplicates_per_pellet_and_rewards_per_action()
	await _test_time_load_damage_is_an_additive_time_split()
	await _test_stop_aimed_fire_applies_one_time_burst_and_extension_per_action()
	await _test_void_round_pierces_distinct_enemy_identities()
	await _test_void_secondary_payloads_apply_spatial_explosion_and_vulnerability()
	await _test_rift_trail_ticks_only_spatially_intersecting_enemies()
	await _test_boss_conversion_fails_closed_during_windup()
	await _cleanup_projectiles()
	_suite.finish(get_tree())


func _test_configuration_contract_covers_launch_projectiles() -> void:
	for case: Dictionary in [
		{"action_id": "normal_fire", "damage": 30.0, "speed": 760.0, "damage_type": DamageInfoScript.DamageType.PHYSICAL, "pierce": 0},
		{"action_id": "aimed_fire", "damage": 54.0, "speed": 920.0, "damage_type": DamageInfoScript.DamageType.PHYSICAL, "pierce": 0},
		{"action_id": "shotgun_fire", "damage": 11.4, "speed": 700.0, "damage_type": DamageInfoScript.DamageType.PHYSICAL, "pierce": 0},
		{"action_id": "void_penetration", "damage": 330.0, "speed": 980.0, "damage_type": DamageInfoScript.DamageType.VOID, "pierce": 99},
	]:
		var projectile = GunProjectileScene.instantiate()
		var execution := _execution(str(case["action_id"]), int(case["pierce"]))
		execution["damage"] = case["damage"]
		execution["speed"] = case["speed"]
		execution["damage_type"] = case["damage_type"]
		_suite.assert_true(projectile.configure_execution(execution), "%s configures through the frozen execution Dictionary" % case["action_id"])
		var snapshot: Dictionary = projectile.execution_snapshot()
		_suite.assert_equal(snapshot.get("source_action_id"), case["action_id"], "%s preserves action identity" % case["action_id"])
		_suite.assert_close(float(snapshot.get("damage", 0.0)), float(case["damage"]), "%s preserves resolved damage" % case["action_id"])
		_suite.assert_close(float(snapshot.get("speed", 0.0)), float(case["speed"]), "%s preserves resolved speed" % case["action_id"])
		projectile.free()

	var invalid = GunProjectileScene.instantiate()
	var invalid_execution := _execution("reload", 0)
	_suite.assert_true(not invalid.configure_execution(invalid_execution), "non-projectile Gun actions fail closed")
	invalid_execution = _execution("normal_fire", 0)
	invalid_execution["trail"] = {"duration_frames": 90, "width_pixels": 64.0, "tick_interval_frames": 0, "tick_damage_multiplier": 0.2}
	invalid_execution["time_interactions"] = [{"interaction_id": "gun_rift_trail"}]
	_suite.assert_true(not invalid.configure_execution(invalid_execution), "malformed Rift trail timing fails closed")
	invalid.free()


func _test_execution_snapshot_restores_live_flight_and_claims_atomically() -> void:
	var projectile = GunProjectileScene.instantiate()
	var shared_claims: Dictionary = {}
	var execution := _execution("void_penetration", 99)
	execution["damage"] = 90.0
	execution["damage_type"] = DamageInfoScript.DamageType.VOID
	execution["pierce_mode"] = "unlimited"
	execution["resource_reward"] = {"reward_id": "gun_restore_reward", "amount": 1.0}
	execution["action_claims"] = shared_claims
	execution["trail"] = {
		"duration_frames": 90,
		"width_pixels": 64.0,
		"tick_interval_frames": 30,
		"tick_damage_multiplier": 0.2,
		"damage_type": "void",
	}
	_suite.assert_true(projectile.configure_execution(execution), "restorable Gun projectile configures")
	projectile.direction = Vector2(0.8, 0.6)
	add_child(projectile)
	await get_tree().process_frame
	projectile.global_position = Vector2(144.0, 72.0)
	projectile.call("_append_trail_point", Vector2(80.0, 48.0))
	var first := _enemy_target(1)
	first["enemy"].set_meta("stable_target_id", 9911)
	add_child(first["enemy"])
	projectile.call("_on_area_entered", first["areas"][0])
	projectile.advance_execution_for_test(7)
	projectile.call("_refresh_trail_targets")
	var authoritative: Dictionary = projectile.execution_snapshot()
	_suite.assert_equal(authoritative.get("trail_target_ids"), [9911], "Gun trail snapshot preserves stable target membership")

	var restored = GunProjectileScene.instantiate()
	_suite.assert_true(restored.restore_execution_snapshot(authoritative), "live Gun projectile execution restores off-tree")
	_suite.assert_equal(restored.execution_snapshot(), authoritative, "restored projectile preserves direction, progress, trail, hit, and action claims")
	add_child(restored)
	_suite.assert_equal(restored.execution_snapshot(), authoritative, "tree attachment preserves restored remaining lifetime and execution progress")
	_suite.assert_true(restored.is_physics_processing(), "restored live projectile resumes authoritative flight processing")
	var first_instance_id: int = int(first["enemy"].get_instance_id())
	first["enemy"].queue_free()
	await get_tree().process_frame
	var rebuilt := _enemy_target(1)
	rebuilt["enemy"].set_meta("stable_target_id", 9911)
	add_child(rebuilt["enemy"])
	_suite.assert_true(int(rebuilt["enemy"].get_instance_id()) != first_instance_id, "restored hit fixture rebuilds the target with a different instance id")
	restored.call("_on_area_entered", rebuilt["areas"][0])
	_suite.assert_true((rebuilt["areas"][0] as RecordingHitArea).received.is_empty(), "stable restored hit claim prevents duplicate damage after instance-id drift")
	var before_trail_tick := (rebuilt["areas"][0] as RecordingHitArea).received.size()
	restored.advance_execution_for_test(23)
	_suite.assert_true((rebuilt["areas"][0] as RecordingHitArea).received.size() > before_trail_tick, "restored Gun trail rebinds to the rebuilt target on its next tick")
	var reward_events := [0]
	restored.resource_reward_requested.connect(func(_token: int, _reward_id: StringName, _amount: float) -> void: reward_events[0] += 1)
	var second := _enemy_target(1)
	add_child(second["enemy"])
	restored.call("_on_area_entered", second["areas"][0])
	_suite.assert_equal(second["areas"][0].received.size(), 1, "restored projectile remains live for a new target")
	_suite.assert_equal(reward_events[0], 0, "restored resource claim cannot pay the same action twice")

	var stable: Dictionary = restored.execution_snapshot()
	var malformed := stable.duplicate(true)
	malformed["lifetime_remaining"] = -1.0
	_suite.assert_true(not restored.restore_execution_snapshot(malformed), "malformed remaining lifetime fails closed")
	_suite.assert_equal(restored.execution_snapshot(), stable, "malformed projectile restore is atomic")
	var extra_field := stable.duplicate(true)
	extra_field["future_field"] = true
	_suite.assert_true(not restored.can_restore_execution_snapshot(extra_field), "unknown projectile execution fields fail closed")
	_suite.assert_equal(restored.execution_snapshot(), stable, "unknown-field preflight leaves the projectile untouched")
	projectile.queue_free()
	restored.queue_free()
	rebuilt["enemy"].queue_free()
	second["enemy"].queue_free()
	await get_tree().process_frame


func _test_shotgun_deduplicates_per_pellet_and_rewards_per_action() -> void:
	var shared_claims: Dictionary = {}
	var action_events := [0]
	var reward_events := [0]
	var projectile_events := [0]
	var pellets: Array[Node] = []
	for outcome_index: int in range(2):
		var pellet = GunProjectileScene.instantiate()
		var execution := _execution("shotgun_fire", 0)
		execution["outcome_index"] = outcome_index
		execution["deterministic_seed"] = 4100 + outcome_index
		execution["damage"] = 11.4
		execution["action_claims"] = shared_claims
		execution["resource_reward"] = {"reward_id": "gun_rewind_free_shot", "amount": 1.0}
		_suite.assert_true(pellet.configure_execution(execution), "shotgun pellet %d configures" % outcome_index)
		pellet.action_hit_confirmed.connect(func(_token: int, _target: Node) -> void: action_events[0] += 1)
		pellet.resource_reward_requested.connect(func(_token: int, _reward_id: StringName, _amount: float) -> void: reward_events[0] += 1)
		pellet.projectile_hit_confirmed.connect(func(_token: int, _outcome: int, _target: Node) -> void: projectile_events[0] += 1)
		add_child(pellet)
		pellets.append(pellet)
	await get_tree().process_frame

	var target := _enemy_target(2)
	add_child(target["enemy"])
	for pellet: Node in pellets:
		pellet.call("_on_area_entered", target["areas"][0])
		pellet.call("_on_area_entered", target["areas"][1])
	var hit_count := 0
	for area: RecordingHitArea in target["areas"]:
		hit_count += area.received.size()
	_suite.assert_equal(hit_count, 2, "two pellets damage one enemy once each across multiple hurtboxes")
	_suite.assert_equal(projectile_events[0], 2, "each pellet publishes one projectile hit confirmation")
	_suite.assert_equal(action_events[0], 1, "shared action claims publish one action confirmation")
	_suite.assert_equal(reward_events[0], 1, "shared action claims request one resource reward")
	for area: RecordingHitArea in target["areas"]:
		for hit: RefCounted in area.received:
			_suite.assert_true(hit.tags.has("weapon:gun"), "shotgun damage carries Gun identity")
			_suite.assert_true(hit.tags.has("non_recursive:resource_reward"), "shotgun damage cannot recurse into resource reward")
	target["enemy"].queue_free()
	await get_tree().process_frame


func _test_time_load_damage_is_an_additive_time_split() -> void:
	var projectile = GunProjectileScene.instantiate()
	var execution := _execution("aimed_fire", 0)
	execution["damage"] = 54.0
	execution["base_attack"] = 30.0
	execution["time_damage_ratio"] = 0.15
	_suite.assert_true(projectile.configure_execution(execution), "Time Load aimed shot configures")
	add_child(projectile)
	await get_tree().process_frame
	var target := _enemy_target(1)
	add_child(target["enemy"])
	projectile.call("_on_area_entered", target["areas"][0])
	var hits: Array[RefCounted] = target["areas"][0].received
	_suite.assert_equal(hits.size(), 2, "Time Load hit emits base and additive time components")
	_suite.assert_equal(hits[0].damage_type, DamageInfoScript.DamageType.PHYSICAL, "aimed base component remains physical")
	_suite.assert_close(hits[0].amount, 54.0, "aimed base damage is unchanged by Time Load")
	_suite.assert_equal(hits[1].damage_type, DamageInfoScript.DamageType.TIME, "Time Load bonus uses TIME damage")
	_suite.assert_close(hits[1].amount, 4.5, "Time Load adds fifteen percent of base attack")
	_suite.assert_true(hits[1].tags.has("non_recursive:time_interaction"), "Time Load bonus cannot recursively trigger another time interaction")
	target["enemy"].queue_free()
	await get_tree().process_frame


func _test_stop_aimed_fire_applies_one_time_burst_and_extension_per_action() -> void:
	var owner := RecordingStopOwner.new()
	add_child(owner)
	var projectile = GunProjectileScene.instantiate()
	var execution := _execution("aimed_fire", 1)
	execution["damage"] = 75.0
	execution["base_attack"] = 30.0
	execution["time_interactions"] = [{
		"interaction_id": "gun_aimed_time_burst",
		"requires_action": "aimed_fire",
		"explosion_radius_tiles": 2.0,
		"explosion_damage_multiplier": 1.0,
		"damage_type": "time",
		"stop_extension_frames": 30,
		"extension_once_per_action_token": true,
	}]
	projectile.owner_entity = owner
	_suite.assert_true(projectile.configure_execution(execution), "Stop+Aimed execution configures its entity payload")
	add_child(projectile)
	await get_tree().process_frame

	var impact := _enemy_target(1)
	var nearby := _enemy_target(1)
	var outside := _enemy_target(1)
	add_child(impact["enemy"])
	add_child(nearby["enemy"])
	add_child(outside["enemy"])
	impact["enemy"].global_position = Vector2.ZERO
	nearby["enemy"].global_position = Vector2(96.0, 0.0)
	outside["enemy"].global_position = Vector2(192.0, 0.0)
	projectile.call("_on_area_entered", impact["areas"][0])

	var impact_hits: Array[RefCounted] = impact["areas"][0].received
	_suite.assert_equal(impact_hits.size(), 2, "Stop+Aimed impact receives base and one burst component")
	if impact_hits.size() >= 2:
		_suite.assert_close(impact_hits[1].amount, 30.0, "Stop burst deals one base attack as damage")
		_suite.assert_equal(impact_hits[1].damage_type, DamageInfoScript.DamageType.TIME, "Stop burst deals TIME damage")
		_suite.assert_true(impact_hits[1].tags.has("attack:gun_aimed_time_burst"), "Stop burst carries its interaction identity")
	_suite.assert_equal(nearby["areas"][0].received.size(), 1, "Stop burst damages an enemy inside two tiles")
	_suite.assert_equal(outside["areas"][0].received.size(), 0, "Stop burst excludes enemies outside two tiles")
	_suite.assert_equal(owner.extensions, [{"action_token": 901, "extension_frames": 30}], "Stop extension is requested once for the action token")

	projectile.call("_on_area_entered", nearby["areas"][0])
	_suite.assert_equal(owner.extensions.size(), 1, "a piercing Aimed shot cannot extend Stop twice")
	_suite.assert_equal(impact["areas"][0].received.size(), 2, "a second impact cannot replay the action-scoped Stop burst")

	projectile.reset_execution_state()
	var stale_target := _enemy_target(1)
	add_child(stale_target["enemy"])
	projectile.call("_on_area_entered", stale_target["areas"][0])
	_suite.assert_equal(stale_target["areas"][0].received.size(), 0, "reset rejects a stale queued hit callback")
	_suite.assert_equal(owner.extensions.size(), 1, "reset rejects a stale Stop extension callback")

	impact["enemy"].queue_free()
	nearby["enemy"].queue_free()
	outside["enemy"].queue_free()
	stale_target["enemy"].queue_free()
	owner.queue_free()
	await get_tree().process_frame


func _test_void_round_pierces_distinct_enemy_identities() -> void:
	var projectile = GunProjectileScene.instantiate()
	var execution := _execution("void_penetration", 99)
	execution["damage"] = 330.0
	execution["damage_type"] = DamageInfoScript.DamageType.VOID
	_suite.assert_true(projectile.configure_execution(execution), "Void Penetration projectile configures")
	add_child(projectile)
	await get_tree().process_frame
	var first := _enemy_target(2)
	var second := _enemy_target(1)
	add_child(first["enemy"])
	add_child(second["enemy"])
	projectile.call("_on_area_entered", first["areas"][0])
	projectile.call("_on_area_entered", first["areas"][1])
	projectile.call("_on_area_entered", second["areas"][0])
	_suite.assert_equal(first["areas"][0].received.size() + first["areas"][1].received.size(), 1, "Void round deduplicates the first enemy identity")
	_suite.assert_equal(second["areas"][0].received.size(), 1, "Void round pierces into a second enemy")
	_suite.assert_equal(first["areas"][0].received[0].damage_type, DamageInfoScript.DamageType.VOID, "Void round emits VOID DamageInfo")
	_suite.assert_true(not projectile.is_queued_for_deletion(), "ninety-nine pierce survives two distinct enemies")
	first["enemy"].queue_free()
	second["enemy"].queue_free()
	projectile.queue_free()
	await get_tree().process_frame


func _test_void_secondary_payloads_apply_spatial_explosion_and_vulnerability() -> void:
	var projectile = GunProjectileScene.instantiate()
	var execution := _execution("void_penetration", 0)
	execution["damage"] = 270.0
	execution["base_attack"] = 30.0
	execution["damage_type"] = DamageInfoScript.DamageType.VOID
	execution["time_damage_ratio"] = 6.0
	execution["pierce_mode"] = "unlimited"
	execution["penetration_explosion"] = {
		"radius_pixels": 96.0,
		"damage_multiplier": 0.3,
		"damage_type": "void",
	}
	execution["vulnerability"] = {
		"duration_frames": 180,
		"damage_taken_bonus": 0.15,
	}
	_suite.assert_true(projectile.configure_execution(execution), "Void secondary payloads configure")
	add_child(projectile)
	await get_tree().process_frame
	var impact := _enemy_target(1)
	var nearby := _enemy_target(1)
	var outside := _enemy_target(1)
	add_child(impact["enemy"])
	add_child(nearby["enemy"])
	add_child(outside["enemy"])
	impact["enemy"].global_position = Vector2.ZERO
	nearby["enemy"].global_position = Vector2(64.0, 0.0)
	outside["enemy"].global_position = Vector2(160.0, 0.0)
	projectile.call("_on_area_entered", impact["areas"][0])
	var impact_hits: Array[RefCounted] = impact["areas"][0].received
	_suite.assert_equal(impact_hits.size(), 3, "impact target receives Void, Time, and one explosion component")
	_suite.assert_equal(impact_hits[0].damage_type, DamageInfoScript.DamageType.VOID, "Void base component preserves damage type")
	_suite.assert_close(impact_hits[0].amount, 270.0, "Void base component resolves sixty percent of total")
	_suite.assert_equal(impact_hits[1].damage_type, DamageInfoScript.DamageType.TIME, "Void split emits a Time component")
	_suite.assert_close(impact_hits[1].amount, 180.0, "Void Time component resolves forty percent of total")
	_suite.assert_close(impact_hits[2].amount, 9.0, "penetration explosion deals thirty percent attack")
	_suite.assert_equal(nearby["areas"][0].received.size(), 1, "nearby enemy receives one spatial explosion hit")
	_suite.assert_equal(outside["areas"][0].received.size(), 0, "enemy outside explosion radius is untouched")
	_suite.assert_equal(impact["enemy"].vulnerabilities.size(), 1, "impact applies one source-aware vulnerability")
	_suite.assert_equal(impact["enemy"].vulnerabilities[0].get("duration_frames"), 180, "vulnerability preserves its duration")
	_suite.assert_close(float(impact["enemy"].vulnerabilities[0].get("damage_taken_bonus", 0.0)), 0.15, "vulnerability preserves its damage bonus")
	impact["enemy"].queue_free()
	nearby["enemy"].queue_free()
	outside["enemy"].queue_free()
	projectile.queue_free()
	await get_tree().process_frame


func _test_rift_trail_ticks_only_spatially_intersecting_enemies() -> void:
	var projectile = GunProjectileScene.instantiate()
	var execution := _execution("normal_fire", 0)
	execution["trail"] = {
		"duration_frames": 90,
		"width_pixels": 64.0,
		"tick_interval_frames": 30,
		"tick_damage_multiplier": 0.2,
	}
	execution["time_interactions"] = [{"interaction_id": "gun_rift_trail"}]
	_suite.assert_true(projectile.configure_execution(execution), "Rift trail configures from its interaction descriptor")
	add_child(projectile)
	await get_tree().process_frame
	projectile.call("_append_trail_point", Vector2(128.0, 0.0))
	var intersecting := _enemy_target(2)
	var outside := _enemy_target(1)
	add_child(intersecting["enemy"])
	add_child(outside["enemy"])
	intersecting["enemy"].global_position = Vector2(64.0, 0.0)
	outside["enemy"].global_position = Vector2(64.0, 64.0)
	projectile.call("_refresh_trail_targets")
	projectile.call("_tick_trail_targets")
	_suite.assert_equal(intersecting["areas"][0].received.size() + intersecting["areas"][1].received.size(), 1, "Rift trail ticks one hurtbox for an intersecting enemy identity")
	_suite.assert_equal(outside["areas"][0].received.size(), 0, "Rift trail ignores enemies outside its spatial width")
	var trail_hit: RefCounted = intersecting["areas"][0].received[0]
	_suite.assert_equal(trail_hit.damage_type, DamageInfoScript.DamageType.TIME, "Rift trail deals time damage")
	_suite.assert_close(trail_hit.amount, 6.0, "Rift trail tick uses frozen base attack multiplier")
	_suite.assert_true(trail_hit.tags.has("attack:gun_rift_trail"), "Rift trail tick carries its interaction identity")
	projectile.reset_execution_state()
	var reset_snapshot: Dictionary = projectile.execution_snapshot()
	_suite.assert_equal(reset_snapshot.get("trail_point_count"), 0, "reset clears Rift trail points before deletion")
	_suite.assert_equal(reset_snapshot.get("trail_target_count"), 0, "reset clears Rift trail target references before deletion")
	_suite.assert_true(projectile.is_queued_for_deletion(), "reset disposes the projectile")
	intersecting["enemy"].queue_free()
	outside["enemy"].queue_free()
	await get_tree().process_frame


func _test_boss_conversion_fails_closed_during_windup() -> void:
	var conversion := {
		"conversion_id": "gun_weakpoint_pressure",
		"allowed_phases": ["RECOVERY", "EXPOSED"],
		"poise_damage": 33.0,
	}
	var windup_boss := _boss_target("WINDUP", true)
	add_child(windup_boss["boss"])
	var windup_projectile = GunProjectileScene.instantiate()
	var windup_execution := _execution("aimed_fire", 0)
	windup_execution["boss_conversion"] = conversion
	_suite.assert_true(windup_projectile.configure_execution(windup_execution), "Boss conversion projectile configures")
	add_child(windup_projectile)
	await get_tree().process_frame
	windup_projectile.call("_on_area_entered", windup_boss["area"])
	_suite.assert_true(windup_boss["boss"].conversions.is_empty(), "pre-exposed WINDUP rejects Gun poise conversion")

	var recovery_boss := _boss_target("RECOVERY", false)
	add_child(recovery_boss["boss"])
	var recovery_projectile = GunProjectileScene.instantiate()
	var recovery_execution := _execution("aimed_fire", 0)
	recovery_execution["action_token"] = 902
	recovery_execution["boss_conversion"] = conversion
	_suite.assert_true(recovery_projectile.configure_execution(recovery_execution), "recovery conversion projectile configures")
	add_child(recovery_projectile)
	await get_tree().process_frame
	recovery_projectile.call("_on_area_entered", recovery_boss["area"])
	_suite.assert_equal(recovery_boss["boss"].conversions.size(), 1, "RECOVERY forwards one Gun poise conversion")
	_suite.assert_equal(recovery_boss["boss"].conversions[0].get("recovery_frames"), 0, "Gun poise conversion does not extend recovery")
	_suite.assert_equal(recovery_boss["boss"].conversions[0].get("exposure_frames"), 0, "Gun poise conversion does not create exposure")
	_suite.assert_close(float(recovery_boss["boss"].conversions[0].get("poise_damage", 0.0)), 33.0, "Gun conversion preserves resolved poise damage")
	windup_boss["boss"].queue_free()
	recovery_boss["boss"].queue_free()
	await get_tree().process_frame


func _execution(action_id: String, pierce: int) -> Dictionary:
	return {
		"action_token": 901,
		"source_action_id": action_id,
		"descriptor_id": "gun_%s" % action_id,
		"outcome_index": 0,
		"deterministic_seed": 20260929,
		"damage": 30.0,
		"base_attack": 30.0,
		"speed": 760.0,
		"max_range_pixels": 960.0,
		"pierce": pierce,
		"pierce_mode": "limited",
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"time_damage_ratio": 0.0,
		"trail": {},
		"time_interactions": [],
		"boss_conversion": {},
		"resource_reward": {},
		"action_claims": {},
		"tags": ["weapon:gun", "action:%s" % action_id],
	}


func _enemy_target(hurtbox_count: int) -> Dictionary:
	var enemy := RecordingEnemy.new()
	enemy.add_to_group("enemies")
	var areas: Array[RecordingHitArea] = []
	for _index: int in range(hurtbox_count):
		var area := RecordingHitArea.new()
		enemy.add_child(area)
		areas.append(area)
	return {"enemy": enemy, "areas": areas}


func _boss_target(phase: String, exposed: bool) -> Dictionary:
	var boss := RecordingBoss.new()
	boss.phase = phase
	boss.exposed = exposed
	boss.add_to_group("enemies")
	boss.add_to_group("bosses")
	var area := RecordingHitArea.new()
	boss.add_child(area)
	return {"boss": boss, "area": area}


func _cleanup_projectiles() -> void:
	for projectile: Node in get_tree().get_nodes_in_group("gun_projectiles"):
		if is_instance_valid(projectile):
			projectile.queue_free()
	await get_tree().process_frame
