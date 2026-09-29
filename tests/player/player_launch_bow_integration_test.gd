extends Node

const PlayerScene := preload("res://scenes/player/player.tscn")
const PlayerArrowScene := preload("res://scenes/combat/player_arrow.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite
var _commits: Array[Dictionary] = []


class ArrowFixture extends Node2D:
	var source: Node
	var owner_entity: Node


class RecordingEnemy extends Node2D:
	var slow_sources: Dictionary = {}


	func apply_time_rift(source_id: StringName, multiplier: float) -> void:
		slow_sources[source_id] = multiplier


	func clear_time_rift(source_id: StringName) -> void:
		slow_sources.erase(source_id)


class RecordingHitArea extends Area2D:
	var received: Array[RefCounted] = []


	func receive_hit(damage_info: RefCounted) -> float:
		received.append(damage_info)
		return float(damage_info.get("amount"))


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	EventBus.weapon_action_committed.connect(_on_weapon_action_committed)
	await _test_launch_slots_reach_player_coordinator_with_atomic_resources()
	await _test_primary_and_starfall_auto_release_through_player()
	await _test_starfall_freezes_world_space_target_and_static_boss_policy()
	await _test_player_lifecycle_clears_only_owned_arrows()
	await _test_player_death_clears_owned_bow_effects_and_projectiles()
	if EventBus.weapon_action_committed.is_connected(_on_weapon_action_committed):
		EventBus.weapon_action_committed.disconnect(_on_weapon_action_committed)
	_suite.finish(get_tree())


func _test_launch_slots_reach_player_coordinator_with_atomic_resources() -> void:
	_commits.clear()
	var player := await _spawn_launch_bow()
	var time_manager: Node = player.get_node("TimeManager")
	var energy_before: float = time_manager.energy
	_suite.assert_true(player.try_action(&"weapon_skill"), "Launch Bow temporal arrow reaches the equipped runtime")
	_suite.assert_close(time_manager.energy, energy_before - 30.0, "temporal arrow spends exactly thirty Time Energy")
	_suite.assert_equal(
		player.weapon_action_coordinator.cooldown_remaining(&"temporal_arrow"),
		300,
		"temporal arrow starts its exact 300-frame cooldown"
	)
	_suite.assert_equal(_commits.size(), 1, "temporal arrow publishes one committed fact")
	_suite.assert_equal(_commits[0].get("action_id"), "temporal_arrow", "committed fact preserves Launch action identity")
	player.cancel_transient_actions()
	_suite.assert_true(not player.try_action(&"weapon_skill"), "committed cooldown rejects a second temporal arrow")
	_suite.assert_close(time_manager.energy, energy_before - 30.0, "cooldown rejection spends no additional energy")
	await _free_player(player)

	player = await _spawn_launch_bow()
	_suite.assert_true(player.try_action(&"weapon_secondary"), "Launch Bow Scatter reaches the semantic secondary slot")
	_suite.assert_equal(player.weapon_action_coordinator.cooldown_remaining(&"scatter_shot"), 120, "Scatter starts its 120-frame cooldown")
	player.cancel_transient_actions()
	_suite.assert_true(player.try_action(&"weapon_utility"), "Launch Bow Focus Step reaches the semantic utility slot")
	await _free_player(player)


func _test_primary_and_starfall_auto_release_through_player() -> void:
	_commits.clear()
	var player := await _spawn_launch_bow()
	_suite.assert_true(player.try_action(&"weapon_primary"), "Launch primary starts coordinator HOLD")
	for _frame: int in range(227):
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "HOLD", "frame 227 remains held")
	_suite.assert_equal(_commits.size(), 0, "unreleased primary publishes no commit")
	player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "WINDUP", "frame 228 auto-releases Launch primary")
	_suite.assert_equal(_commits.size(), 1, "automatic primary release publishes once")
	_suite.assert_equal(_commits[0].get("action_id"), "precision_draw", "automatic release keeps primary identity")
	player.cancel_transient_actions()
	await _free_player(player)


func _test_starfall_freezes_world_space_target_and_static_boss_policy() -> void:
	var player := await _spawn_launch_bow()
	player.global_position = Vector2(640.0, 128.0)
	player.get_node("BowWeapon").global_rotation = 0.0
	_suite.assert_true(player.try_action(&"weapon_ultimate"), "Starfall begins from an offset player position")
	var hold_plan: Dictionary = player.weapon_action_coordinator.snapshot().get("plan", {})
	_suite.assert_equal(
		hold_plan.get("target_point_snapshot"),
		Vector2(1152.0, 128.0),
		"Starfall targets eight cells forward in world space"
	)
	for _frame: int in range(60):
		player.advance_action_frame()
	var runtime_snapshot: Dictionary = player.weapon_action_coordinator.snapshot().get("runtime", {})
	var definition: Dictionary = runtime_snapshot.get("committed_launch_definition", {})
	var boss_policy: Dictionary = definition.get("boss_conversion", {})
	_suite.assert_equal(boss_policy.get("target_id"), "chrono_warden", "Player packet carries static Chrono Warden policy")
	_suite.assert_true(not boss_policy.has("apply_now"), "Player packet defers Boss phase evaluation until projectile hit")
	player.cancel_transient_actions()
	await _free_player(player)


func _test_player_lifecycle_clears_only_owned_arrows() -> void:
	var player := await _spawn_launch_bow()
	var unrelated_owner := Node.new()
	add_child(unrelated_owner)
	var unrelated_source := Node.new()
	unrelated_owner.add_child(unrelated_source)

	var owned := _arrow_fixture(player, player.get_node("BowWeapon"))
	var unrelated := _arrow_fixture(unrelated_owner, unrelated_source)
	player.cancel_transient_actions()
	_suite.assert_true(owned.is_queued_for_deletion(), "transient cancellation queues the player's Bow arrows for cleanup")
	_suite.assert_true(not unrelated.is_queued_for_deletion(), "transient cancellation preserves unrelated arrow-group nodes")
	await get_tree().process_frame

	owned = _arrow_fixture(player, player.get_node("BowWeapon"))
	_suite.assert_true(
		player.restore_rewind_safe_action_state({"action_state": "FREE"}),
		"rewind-safe restore succeeds for arrow cleanup coverage"
	)
	_suite.assert_true(owned.is_queued_for_deletion(), "rewind restore clears the player's already-generated Bow arrows")
	_suite.assert_true(not unrelated.is_queued_for_deletion(), "rewind restore still preserves unrelated arrows")
	await get_tree().process_frame

	owned = _arrow_fixture(player, player.get_node("BowWeapon"))
	_suite.assert_true(player.configure_loadout(_launch_config()), "same-profile loadout reconfigure succeeds")
	_suite.assert_true(owned.is_queued_for_deletion(), "loadout reconfigure clears the previous runtime's Bow arrows")
	_suite.assert_true(not unrelated.is_queued_for_deletion(), "loadout reconfigure preserves unrelated arrows")
	await get_tree().process_frame

	if is_instance_valid(unrelated):
		unrelated.queue_free()
	if is_instance_valid(unrelated_owner):
		unrelated_owner.queue_free()
	await _free_player(player)

	_commits.clear()
	player = await _spawn_launch_bow()
	var time_manager: Node = player.get_node("TimeManager")
	_suite.assert_true(player.try_action(&"weapon_ultimate"), "Starfall starts its sixty-frame HOLD gate")
	for _frame: int in range(59):
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "HOLD", "Starfall frame 59 remains held")
	_suite.assert_close(time_manager.energy, 100.0, "Starfall HOLD does not spend energy early")
	player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "WINDUP", "Starfall frame 60 auto-releases")
	_suite.assert_close(time_manager.energy, 30.0, "Starfall release atomically spends seventy Time Energy")
	_suite.assert_equal(player.weapon_action_coordinator.cooldown_remaining(&"starfall_arrow_rain"), 900, "Starfall starts its exact 900-frame cooldown")
	_suite.assert_equal(_commits.size(), 1, "Starfall publishes one committed fact")
	_suite.assert_equal(_commits[0].get("action_id"), "starfall_arrow_rain", "Starfall commit preserves action identity")
	for _frame: int in range(20):
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "ACTIVE", "Starfall enters its coordinator-owned active phase")
	_suite.assert_equal(_player_arrow_count(), 3, "ACTIVE entry releases the first Starfall wave")
	for _frame: int in range(81):
		player.advance_action_frame()
	_suite.assert_equal(_player_arrow_count(), 30, "coordinator ACTIVE frames release all ten deterministic Starfall waves")
	for _frame: int in range(9):
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "RECOVERY", "Starfall schedule ends with the coordinator active phase")
	_suite.assert_equal(_player_arrow_count(), 30, "Starfall emits no extra wave after the active window")
	player.cancel_transient_actions()
	await _free_player(player)


func _test_player_death_clears_owned_bow_effects_and_projectiles() -> void:
	var player := await _spawn_launch_bow()
	var bow: Node = player.get_node("BowWeapon")
	var health: Node = player.get_node("HealthComponent")
	var unrelated_owner := Node.new()
	add_child(unrelated_owner)
	var unrelated_source := Node.new()
	unrelated_owner.add_child(unrelated_source)
	var unrelated := _arrow_fixture(unrelated_owner, unrelated_source)

	var enemy := RecordingEnemy.new()
	enemy.add_to_group("enemies")
	var hit_area := RecordingHitArea.new()
	enemy.add_child(hit_area)
	add_child(enemy)
	enemy.global_position = player.global_position + Vector2.RIGHT * 512.0

	_suite.assert_true(player.try_action(&"weapon_ultimate"), "death fixture starts Starfall")
	for _frame: int in range(80):
		player.advance_action_frame()
	_suite.assert_equal(player.weapon_presentation_snapshot().get("phase"), "ACTIVE", "death fixture reaches Starfall ACTIVE")
	_suite.assert_true(_player_arrow_count() >= 3, "death fixture owns active Starfall arrows")
	_suite.assert_true(not enemy.slow_sources.is_empty(), "Starfall applies its source-owned slow before death")
	_suite.assert_true(health.invulnerable, "Starfall owns invulnerability before death")
	for _frame: int in range(30):
		player.advance_action_frame()
	_suite.assert_true(enemy.has_meta("bow_time_erosion_sources"), "Starfall applies erosion metadata before death")

	var temporal_arrow = PlayerArrowScene.instantiate()
	temporal_arrow.owner_entity = player
	temporal_arrow.source = bow
	temporal_arrow.action_token = 9901
	temporal_arrow.outcome_index = 41
	temporal_arrow.base_attack = 30.0
	temporal_arrow.trail_duration_frames = 300
	temporal_arrow.trail_tick_interval_frames = 30
	temporal_arrow.trail_width_pixels = 64.0
	temporal_arrow.trail_tick_damage_multiplier = 0.2
	temporal_arrow.trail_slow_ratio = 0.3
	temporal_arrow.global_position = enemy.global_position
	add_child(temporal_arrow)
	await get_tree().process_frame
	temporal_arrow.call("_on_trail_area_entered", hit_area)
	temporal_arrow.call("_apply_trail_slow", enemy)
	_suite.assert_true(enemy.slow_sources.has(&"bow_trail_9901_41"), "Temporal trail owns an isolated slow source before death")

	player.call("_on_died", null)
	_suite.assert_true(temporal_arrow.is_queued_for_deletion(), "death queues the player's Temporal arrow for cleanup")
	_suite.assert_true(not unrelated.is_queued_for_deletion(), "death preserves unrelated player_arrows nodes")
	_suite.assert_equal(enemy.slow_sources.keys(), [&"bow_trail_9901_41"], "death clears Starfall slow synchronously while the queued Temporal arrow retains only its own source")
	_suite.assert_true(not enemy.has_meta("bow_time_erosion_sources"), "death clears Starfall erosion metadata")
	_suite.assert_true(not health.invulnerable, "death releases Starfall's invulnerability source")
	await get_tree().process_frame
	_suite.assert_true(not is_instance_valid(temporal_arrow), "death removes the owned Temporal arrow from the scene")
	_suite.assert_true(enemy.slow_sources.is_empty(), "owned Temporal arrow exit clears its trail slow source")

	if is_instance_valid(unrelated):
		unrelated.queue_free()
	if is_instance_valid(unrelated_owner):
		unrelated_owner.queue_free()
	if is_instance_valid(enemy):
		enemy.queue_free()
	await _free_player(player)


func _spawn_launch_bow() -> Node:
	var player := PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	await get_tree().process_frame
	_suite.assert_true(player.configure_loadout(_launch_config()), "Player accepts the authoritative Launch Bow profile")
	return player


func _launch_config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 20260929,
		"weapon_profile": _profile_definition("bow_launch_v1"),
	}


func _arrow_fixture(owner_entity: Node, source: Node) -> ArrowFixture:
	var arrow := ArrowFixture.new()
	arrow.owner_entity = owner_entity
	arrow.source = source
	arrow.add_to_group("player_arrows")
	add_child(arrow)
	return arrow


func _free_player(player: Node) -> void:
	player.cancel_transient_actions()
	await get_tree().create_timer(0.65).timeout
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


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


func _player_arrow_count() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("player_arrows"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			count += 1
	return count


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
