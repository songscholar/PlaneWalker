extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite
var _commits: Array[Dictionary] = []
var _hit_facts: Array[Dictionary] = []
var _resource_facts: Array[Dictionary] = []


class ProjectileFixture extends Node2D:
	var source: Node
	var owner_entity: Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	EventBus.weapon_action_committed.connect(_on_weapon_action_committed)
	EventBus.weapon_hit_confirmed.connect(_on_weapon_hit_confirmed)
	EventBus.weapon_resource_changed.connect(_on_weapon_resource_changed)
	await _test_launch_and_expansion_assemble_authoritative_gun()
	await _test_milestone_and_inert_adapter_fail_closed()
	await _test_gun_aim_stats_and_modifier_bounds()
	await _test_primary_and_ultimate_hold_boundaries()
	await _test_reload_live_confirm_path()
	await _test_typed_hit_and_resource_facts()
	await _test_lifecycle_clears_only_owned_gun_projectiles()
	if EventBus.weapon_action_committed.is_connected(_on_weapon_action_committed):
		EventBus.weapon_action_committed.disconnect(_on_weapon_action_committed)
	if EventBus.weapon_hit_confirmed.is_connected(_on_weapon_hit_confirmed):
		EventBus.weapon_hit_confirmed.disconnect(_on_weapon_hit_confirmed)
	if EventBus.weapon_resource_changed.is_connected(_on_weapon_resource_changed):
		EventBus.weapon_resource_changed.disconnect(_on_weapon_resource_changed)
	_suite.finish(get_tree())


func _test_launch_and_expansion_assemble_authoritative_gun() -> void:
	for milestone: String in ["LAUNCH", "EXPANSION"]:
		var player := await _spawn_player()
		_suite.assert_true(
			player.configure_loadout(_gun_config(milestone)),
			"%s accepts the explicit authoritative Gun profile" % milestone
		)
		_suite.assert_true(player.weapon_runtime != null, "%s assembles a non-null Gun runtime" % milestone)
		_suite.assert_true(player.weapon_action_coordinator != null, "%s assembles a non-null Gun coordinator" % milestone)
		_suite.assert_true(player.get_node_or_null("GunWeapon") != null, "%s scene owns the Gun adapter" % milestone)
		_suite.assert_equal(player.weapon_presentation_snapshot().get("weapon_id"), "gun", "%s equips Gun authority" % milestone)
		_suite.assert_equal(player.weapon_presentation_snapshot().get("profile_id"), "gun_launch_v1", "%s preserves Gun profile identity" % milestone)
		await _free_player(player)


func _test_milestone_and_inert_adapter_fail_closed() -> void:
	var player := await _spawn_player()
	var accepted_before: Dictionary = player.weapon_presentation_snapshot()
	for milestone: String in ["M1", "NEXT"]:
		_suite.assert_true(
			not player.configure_loadout(_gun_config(milestone)),
			"%s rejects the Launch-only Gun profile" % milestone
		)
		_suite.assert_equal(
			player.weapon_presentation_snapshot(),
			accepted_before,
			"%s Gun rejection preserves the accepted runtime atomically" % milestone
		)

	var gun: Node = player.get_node("GunWeapon")
	player.remove_child(gun)
	_suite.assert_true(
		not player.configure_loadout(_gun_config("LAUNCH")),
		"Gun configuration fails closed when its adapter is inert or absent"
	)
	_suite.assert_equal(
		player.weapon_presentation_snapshot(),
		accepted_before,
		"inert Gun rejection preserves the prior runtime"
	)
	player.add_child(gun)
	await _free_player(player)


func _test_gun_aim_stats_and_modifier_bounds() -> void:
	var player := await _spawn_gun()
	var gun: Node2D = player.get_node("GunWeapon")
	_suite.assert_close(float(gun.get("base_attack")), 15.0, "Gun uses its authoritative base attack")
	_suite.assert_close(float(gun.get("attack_speed")), 0.9, "Gun uses its authoritative attack speed")
	gun.global_rotation = PI * 0.5
	_suite.assert_equal(
		player.call("_weapon_aim_direction").round(),
		Vector2.DOWN,
		"Gun submission context reads the equipped Gun adapter rotation"
	)
	_suite.assert_true(player.apply_weapon_modifier(&"weapon.ammo_capacity", 12.0), "Gun ammo-capacity modifier is bounded and accepted")
	_suite.assert_true(player.apply_weapon_modifier(&"weapon.reload_window", 1.5), "Gun reload-window modifier is bounded and accepted")
	var before: Dictionary = player.weapon_modifier_state.snapshot()
	_suite.assert_true(not player.apply_weapon_modifier(&"weapon.ammo_capacity", 21.0), "Gun ammo-capacity modifier rejects its upper overflow")
	_suite.assert_true(not player.apply_weapon_modifier(&"weapon.reload_window", 11.0), "Gun reload-window modifier rejects its upper overflow")
	_suite.assert_equal(player.weapon_modifier_state.snapshot(), before, "Gun modifier rejection is atomic")
	await _free_player(player)


func _test_primary_and_ultimate_hold_boundaries() -> void:
	_commits.clear()
	var player := await _spawn_gun()
	_suite.assert_true(player.try_action(&"weapon_primary"), "Gun primary enters coordinator HOLD")
	for _frame: int in range(17):
		player.advance_action_frame()
	_suite.assert_true(bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")), "Gun primary releases at frame 17")
	_suite.assert_equal(_last_commit_action(), "normal_fire", "primary frame 17 resolves Normal Fire")
	await _free_player(player)

	player = await _spawn_gun()
	_suite.assert_true(player.try_action(&"weapon_primary"), "Gun aimed fixture enters HOLD")
	for _frame: int in range(18):
		player.advance_action_frame()
	_suite.assert_true(bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")), "Gun primary releases at frame 18")
	_suite.assert_equal(_last_commit_action(), "aimed_fire", "primary frame 18 resolves Aimed Fire")
	await _free_player(player)

	player = await _spawn_gun()
	var time_manager: Node = player.get_node("TimeManager")
	_suite.assert_true(player.try_action(&"weapon_ultimate"), "Gun ultimate enters its sixty-frame HOLD")
	for _frame: int in range(59):
		player.advance_action_frame()
	_suite.assert_true(
		not bool(player.call("_submit_weapon_intent", &"weapon_ultimate", &"released")),
		"Gun ultimate rejects frame 59"
	)
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "READY", "undercharged ultimate rolls back to READY")
	_suite.assert_close(time_manager.energy, 100.0, "undercharged ultimate spends no Time Energy")
	await _free_player(player)

	player = await _spawn_gun()
	time_manager = player.get_node("TimeManager")
	_suite.assert_true(player.try_action(&"weapon_ultimate"), "Gun ultimate frame-60 fixture enters HOLD")
	for _frame: int in range(60):
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "WINDUP", "Gun ultimate auto-releases at frame 60")
	_suite.assert_equal(_last_commit_action(), "void_penetration", "ultimate frame 60 resolves Void Penetration")
	_suite.assert_close(time_manager.energy, 35.0, "Void Penetration atomically spends sixty-five Time Energy")
	await _free_player(player)


func _test_reload_live_confirm_path() -> void:
	var player := await _spawn_gun()
	_suite.assert_true(player.try_action(&"weapon_primary"), "reload fixture starts primary HOLD")
	_suite.assert_true(bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")), "reload fixture spends one round")
	player.cancel_transient_actions()
	_suite.assert_equal(player.weapon_runtime.snapshot().get("ammo"), 5, "committed primary leaves five rounds")
	_suite.assert_true(player.try_action(&"weapon_utility"), "Gun utility starts Reload")
	for _frame: int in range(28):
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "RESOURCE_ACTION", "reload reaches its live-confirm phase")
	_suite.assert_true(player.try_action(&"weapon_utility"), "second utility press reaches coordinator live confirm")
	_suite.assert_equal(player.weapon_runtime.snapshot().get("ammo"), 7, "perfect reload live confirm overfills to seven")
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "RECOVERY", "perfect confirm replaces the remainder with recovery")
	await _free_player(player)


func _test_typed_hit_and_resource_facts() -> void:
	_commits.clear()
	_hit_facts.clear()
	_resource_facts.clear()
	var player := await _spawn_gun()
	_hit_facts.clear()
	_resource_facts.clear()
	_suite.assert_true(player.try_action(&"weapon_primary"), "typed-fact fixture starts Gun primary HOLD")
	_suite.assert_true(
		bool(player.call("_submit_weapon_intent", &"weapon_primary", &"released")),
		"typed-fact fixture commits Normal Fire"
	)
	var token := int(_commits.back().get("token", 0)) if not _commits.is_empty() else 0
	_suite.assert_true(token > 0, "typed-fact fixture captures a coordinator token")
	_suite.assert_equal(_resource_facts.size(), 1, "ammo spend publishes one typed resource fact")
	if _resource_facts.size() == 1:
		var ammo_fact: Dictionary = _resource_facts[0]
		_suite.assert_equal(ammo_fact.get("weapon_id"), &"gun", "ammo fact identifies Gun")
		_suite.assert_equal(ammo_fact.get("resource_id"), &"ammo", "ammo fact identifies the resource")
		_suite.assert_close(float(ammo_fact.get("current", -1.0)), 5.0, "ammo fact publishes the committed balance")
		_suite.assert_close(float(ammo_fact.get("maximum", -1.0)), 6.0, "ammo fact publishes magazine capacity")

	var target := Node2D.new()
	add_child(target)
	var gun: Node = player.get_node("GunWeapon")
	gun.action_hit_confirmed.emit(token, target)
	gun.action_hit_confirmed.emit(token, target)
	_suite.assert_equal(_hit_facts.size(), 1, "duplicate adapter hit callbacks publish one typed hit fact")
	if _hit_facts.size() == 1:
		var hit_fact: Dictionary = _hit_facts[0]
		_suite.assert_equal(hit_fact.get("weapon_id"), &"gun", "hit fact identifies Gun")
		_suite.assert_equal(hit_fact.get("action_id"), &"normal_fire", "hit fact resolves the committed action")
		_suite.assert_equal(hit_fact.get("token"), token, "hit fact preserves the coordinator token")
		_suite.assert_equal(hit_fact.get("target_id"), target.get_instance_id(), "hit fact preserves target identity")

	var time_manager: Node = player.get_node("TimeManager")
	time_manager.energy = 80.0
	var resource_count_before_reward := _resource_facts.size()
	gun.resource_reward_requested.emit(token, &"time_energy", 5.0)
	gun.resource_reward_requested.emit(token, &"time_energy", 5.0)
	_suite.assert_close(time_manager.energy, 85.0, "duplicate adapter resource callbacks grant Time Energy once")
	_suite.assert_equal(
		_resource_facts.size(),
		resource_count_before_reward + 1,
		"one accepted Gun reward publishes one typed resource fact"
	)
	if _resource_facts.size() == resource_count_before_reward + 1:
		var reward_fact: Dictionary = _resource_facts.back()
		_suite.assert_equal(reward_fact.get("resource_id"), &"time_energy", "reward fact identifies Time Energy")
		_suite.assert_close(float(reward_fact.get("current", -1.0)), 85.0, "reward fact publishes the restored balance")
		_suite.assert_equal(reward_fact.get("reason"), &"projectile_reward", "reward fact publishes a stable reason")

	gun.resource_reward_requested.emit(token, &"unknown_reward", 10.0)
	_suite.assert_equal(
		_resource_facts.size(),
		resource_count_before_reward + 1,
		"unknown Gun resource rewards fail closed without a fact"
	)
	target.queue_free()
	await _free_player(player)


func _test_lifecycle_clears_only_owned_gun_projectiles() -> void:
	var player := await _spawn_gun()
	var gun: Node = player.get_node("GunWeapon")
	var unrelated_owner := Node.new()
	add_child(unrelated_owner)
	var unrelated_source := Node.new()
	unrelated_owner.add_child(unrelated_source)
	var unrelated := _projectile_fixture(unrelated_owner, unrelated_source)

	var owned := _projectile_fixture(player, gun)
	player.reset_runtime_state()
	_suite.assert_true(owned.is_queued_for_deletion(), "runtime reset clears owned Gun projectiles")
	_suite.assert_true(not unrelated.is_queued_for_deletion(), "runtime reset preserves unrelated projectiles")
	await get_tree().process_frame

	owned = _projectile_fixture(player, gun)
	_suite.assert_true(player.restore_rewind_safe_action_state({"action_state": "FREE"}), "rewind-safe restore succeeds")
	_suite.assert_true(not owned.is_queued_for_deletion(), "rewind restore preserves owned Gun projectiles")
	_suite.assert_true(not unrelated.is_queued_for_deletion(), "rewind restore preserves unrelated projectiles")
	await get_tree().process_frame
	owned.queue_free()
	await get_tree().process_frame

	owned = _projectile_fixture(player, gun)
	_suite.assert_true(player.configure_loadout(_gun_config("LAUNCH")), "Gun loadout reconfigure succeeds")
	_suite.assert_true(owned.is_queued_for_deletion(), "loadout reconfigure clears prior Gun projectiles")
	_suite.assert_true(not unrelated.is_queued_for_deletion(), "loadout reconfigure preserves unrelated projectiles")
	await get_tree().process_frame

	owned = _projectile_fixture(player, gun)
	player.call("_on_died", null)
	_suite.assert_true(owned.is_queued_for_deletion(), "death clears owned Gun projectiles")
	_suite.assert_true(not unrelated.is_queued_for_deletion(), "death preserves unrelated projectiles")

	if is_instance_valid(unrelated):
		unrelated.queue_free()
	if is_instance_valid(unrelated_owner):
		unrelated_owner.queue_free()
	await _free_player(player)


func _spawn_player() -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	return player


func _spawn_gun() -> Node:
	var player := await _spawn_player()
	_suite.assert_true(player.configure_loadout(_gun_config("LAUNCH")), "Player accepts the authoritative Launch Gun profile")
	return player


func _gun_config(milestone: String) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": milestone,
		"character_id": "wanderer",
		"weapon_id": "gun",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
		"weapon_profile": _profile_definition("gun_launch_v1"),
	}


func _profile_definition(profile_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/content_packs/base/content/weapon_runtime_profiles.json")
	)
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == profile_id:
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _projectile_fixture(owner_entity: Node, source: Node) -> ProjectileFixture:
	var projectile := ProjectileFixture.new()
	projectile.owner_entity = owner_entity
	projectile.source = source
	projectile.add_to_group("player_projectiles")
	projectile.add_to_group("gun_projectiles")
	add_child(projectile)
	return projectile


func _last_commit_action() -> String:
	return str(_commits.back().get("action_id", "")) if not _commits.is_empty() else ""


func _free_player(player: Node) -> void:
	player.cancel_transient_actions()
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _on_weapon_action_committed(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	context: Dictionary
) -> void:
	_commits.append({
		"weapon_id": str(weapon_id),
		"action_id": str(action_id),
		"token": token,
		"context": context.duplicate(true),
	})


func _on_weapon_hit_confirmed(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	target_id: int,
	context: Dictionary
) -> void:
	_hit_facts.append({
		"weapon_id": weapon_id,
		"action_id": action_id,
		"token": token,
		"target_id": target_id,
		"context": context.duplicate(true),
	})


func _on_weapon_resource_changed(
	weapon_id: StringName,
	resource_id: StringName,
	current: float,
	maximum: float,
	reason: StringName
) -> void:
	_resource_facts.append({
		"weapon_id": weapon_id,
		"resource_id": resource_id,
		"current": current,
		"maximum": maximum,
		"reason": reason,
	})
