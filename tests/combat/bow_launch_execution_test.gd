extends Node

const BowWeaponScript := preload("res://scripts/combat/bow_weapon.gd")
const BowWeaponRuntimeScript := preload("res://scripts/combat/weapons/bow_weapon_runtime.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const PlayerArrowScript := preload("res://scripts/combat/player_arrow.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")

const PIXELS_PER_CELL := 64.0
const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"

var _suite


class TestPlayer extends CharacterBody2D:
	var invulnerable: bool = false
	var interaction_claims: Dictionary = {}


	func claim_weapon_time_interaction(interaction_id: StringName, generation: int) -> bool:
		var key := "%s:%d" % [str(interaction_id), generation]
		if interaction_claims.has(key):
			return false
		interaction_claims[key] = true
		return true


class RecordingEnemy extends Node2D:
	var rifted: bool = false
	var slow_sources: Dictionary = {}
	var stop_sources: Dictionary = {}


	func apply_time_rift(source_id: StringName, multiplier: float) -> void:
		slow_sources[source_id] = multiplier


	func clear_time_rift(source_id: StringName) -> void:
		slow_sources.erase(source_id)


	func is_time_rifted() -> bool:
		return rifted


	func apply_time_stop_source(source_id: StringName, duration: float) -> void:
		stop_sources[source_id] = duration


	func clear_time_stop_source(source_id: StringName) -> void:
		stop_sources.erase(source_id)


class RecordingRift extends Node2D:
	var radius: float = 100.0


class RecordingHitArea extends Area2D:
	var received: Array[RefCounted] = []


	func receive_hit(damage_info: RefCounted) -> float:
		received.append(damage_info)
		return float(damage_info.amount)


class RecordingBoss extends Node2D:
	var phase: String = "WINDUP"
	var action: String = "SLAM"
	var exposed: bool = false
	var conversions: Array[Dictionary] = []


	func get_boss_ui_snapshot() -> Dictionary:
		return {
			"action": action,
			"phase": phase,
			"remaining": 1.0,
			"exposed": exposed or phase == "RECOVERY",
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


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	if not await _assert_launch_adapter_contract():
		_suite.finish(get_tree())
		return
	await _test_scatter_releases_five_deterministic_arrows()
	await _test_focus_step_moves_opposite_aim_with_swept_collision()
	await _test_temporal_arrow_uses_time_damage_infinite_pierce_and_trail_ticks()
	await _test_starfall_releases_ten_waves_of_three()
	await _test_rewind_preflight_supports_trails_centers_scatter_and_skips_starfall()
	await _test_release_failure_is_atomic_before_rewind_claim()
	await _test_launch_damage_uses_frozen_resolved_multiplier()
	await _test_rift_detonation_is_action_scoped_and_uses_live_radius()
	await _test_enemy_identity_deduplication_and_source_aware_freeze_cleanup()
	await _test_trail_and_starfall_statuses_cleanup_without_timers()
	await _test_time_interactions_and_boss_conversion_are_consumed_safely()
	await _test_real_runtime_packet_executes_through_adapter()
	await _test_prepared_runtime_snapshot_restores_exactly()
	await _test_live_arrow_snapshot_restores_targets_without_duplicate_damage()
	await _test_malformed_and_missing_target_restore_are_atomic()
	await _test_starfall_snapshot_resumes_without_duplicate_wave()
	_suite.finish(get_tree())


func _assert_launch_adapter_contract() -> bool:
	var fixture := await _bow_fixture()
	var bow: Node = fixture["bow"]
	var required: Array[StringName] = [
		&"begin_profile_action",
		&"release_profile_action",
		&"cancel_profile_action",
		&"finish_profile_action",
		&"advance_profile_action_frames",
		&"advance_profile_action_for_test",
	]
	var available := true
	for method_name: StringName in required:
		var present := bow.has_method(method_name)
		_suite.assert_true(present, "Launch Bow adapter exposes %s" % method_name)
		available = available and present
	await _cleanup_fixture(fixture)
	return available


func _test_scatter_releases_five_deterministic_arrows() -> void:
	var fixture := await _bow_fixture()
	var bow: Node = fixture["bow"]
	var descriptors: Array[Dictionary] = []
	var angles: Array[float] = [-30.0, -15.0, 0.0, 15.0, 30.0]
	for index: int in range(angles.size()):
		descriptors.append(_arrow_descriptor(
			"bow_scatter",
			index,
			1000 + index,
			Vector2.RIGHT.rotated(deg_to_rad(angles[index])),
			{
				"angle_degrees": angles[index],
				"damage_multiplier": 0.6,
				"speed_cells_per_second": 18.0,
				"range_cells": 8.0,
				"hit_width_cells": 0.3,
				"target_deduplication": "per_projectile",
			}
		))
	var definition := _launch_definition("scatter_shot", descriptors)
	_suite.assert_equal(bow.begin_profile_action(definition), definition, "Scatter stages an isolated deterministic descriptor set")
	_suite.assert_true(bow.release_profile_action(), "Scatter releases its committed payload")
	var arrows := _arrows_for_token(701)
	_suite.assert_equal(arrows.size(), 5, "Scatter releases exactly five arrows")
	for index: int in range(arrows.size()):
		var arrow: Node = arrows[index]
		_suite.assert_close(rad_to_deg((arrow.direction as Vector2).angle()), angles[index], "Scatter arrow %d preserves deterministic fan angle" % index)
		_suite.assert_equal(arrow.action_token, 701, "Scatter arrow %d shares the committed action token" % index)
		_suite.assert_equal(arrow.outcome_index, index, "Scatter arrow %d preserves outcome index" % index)
		_suite.assert_equal(arrow.deterministic_seed, 1000 + index, "Scatter arrow %d preserves deterministic seed" % index)
		_suite.assert_close(arrow.damage, 30.0 * 0.6, "Scatter arrow %d applies the exact multiplier" % index)
		_suite.assert_close(arrow.speed, 18.0 * PIXELS_PER_CELL, "Scatter arrow %d converts cell speed once" % index)
	await _cleanup_fixture(fixture)


func _test_focus_step_moves_opposite_aim_with_swept_collision() -> void:
	var fixture := await _bow_fixture(true)
	var player: TestPlayer = fixture["player"]
	var bow: Node = fixture["bow"]
	var definition := _launch_definition("focus_step", [{
		"descriptor_id": "bow_focus_step",
		"kind": "movement",
		"outcome_index": 0,
		"seed": 1701,
		"parameters": {
			"direction": Vector2.LEFT,
			"distance_pixels": 96.0,
			"collision_mode": "swept",
			"invulnerable": false,
		},
	}])
	bow.begin_profile_action(definition)
	_suite.assert_true(bow.release_profile_action(), "Focus Step executes its movement descriptor")
	_suite.assert_close(player.global_position.x, -96.0, "Focus Step moves exactly 96 pixels opposite aim in open space")
	_suite.assert_close(player.global_position.y, 0.0, "Focus Step preserves the orthogonal axis")
	_suite.assert_true(not player.invulnerable, "Focus Step grants no invulnerability")

	player.global_position = Vector2.ZERO
	var wall := StaticBody2D.new()
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(12.0, 80.0)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	add_child(wall)
	wall.global_position = Vector2(-52.0, 0.0)
	await get_tree().physics_frame
	bow.finish_profile_action()
	bow.begin_profile_action(definition)
	_suite.assert_true(bow.release_profile_action(), "Focus Step remains executable against an obstacle")
	_suite.assert_true(player.global_position.x > -52.0, "Swept Focus Step cannot tunnel through a blocking wall")
	_suite.assert_true(player.global_position.x < 0.0, "Swept Focus Step still moves up to the collision")
	wall.queue_free()
	await _cleanup_fixture(fixture)


func _test_temporal_arrow_uses_time_damage_infinite_pierce_and_trail_ticks() -> void:
	var fixture := await _bow_fixture()
	var bow: Node = fixture["bow"]
	var descriptor := _arrow_descriptor(
		"bow_temporal_arrow",
		0,
		2701,
		Vector2.RIGHT,
		{
			"damage_multiplier": 5.0,
			"time_damage_ratio": 1.0,
			"speed_cells_per_second": 10.0,
			"range_cells": 20.0,
			"pierce_mode": "unlimited",
			"trail": {
				"duration_frames": 300,
				"width_cells": 0.8,
				"tick_interval_frames": 30,
				"tick_damage_multiplier": 0.2,
				"slow_ratio": 0.3,
			},
			"first_hit_control": {"control_id": "temporal_freeze", "duration_frames": 90},
		}
	)
	var definition := _launch_definition("temporal_arrow", [descriptor])
	bow.begin_profile_action(definition)
	_suite.assert_true(bow.release_profile_action(), "Temporal Arrow releases its committed payload")
	var arrows := _arrows_for_token(701)
	_suite.assert_equal(arrows.size(), 1, "Temporal Arrow releases one projectile")
	var arrow: Node = arrows[0]
	var snapshot: Dictionary = arrow.execution_snapshot()
	_suite.assert_equal(snapshot["damage_type"], "TIME", "Temporal Arrow deals time damage")
	_suite.assert_equal(snapshot["pierce_mode"], "unlimited", "Temporal Arrow uses unlimited pierce")
	_suite.assert_equal(snapshot["trail_duration_frames"], 300, "Temporal trail persists for 300 frames")
	_suite.assert_equal(snapshot["trail_tick_interval_frames"], 30, "Temporal trail ticks every 30 frames")

	var target := _recording_target(false)
	add_child(target["enemy"])
	target["enemy"].global_position = arrow.global_position
	var hit_area: RecordingHitArea = target["area"]
	arrow.call("_on_area_entered", hit_area)
	_suite.assert_equal(hit_area.received.size(), 1, "Temporal projectile damages the first target once")
	_suite.assert_equal(hit_area.received[0].damage_type, 1, "Temporal projectile emits TIME DamageInfo")
	_suite.assert_true(not arrow.is_queued_for_deletion(), "Unlimited-pierce Temporal Arrow survives a hit")
	arrow.call("_on_trail_area_entered", hit_area)
	arrow.advance_execution_for_test(29)
	_suite.assert_equal(hit_area.received.size(), 1, "Temporal trail does not tick before frame 30")
	arrow.advance_execution_for_test(1)
	_suite.assert_equal(hit_area.received.size(), 2, "Temporal trail ticks exactly on frame 30")
	_suite.assert_equal(hit_area.received[1].damage_type, 1, "Temporal trail tick also deals TIME damage")
	_suite.assert_close(hit_area.received[1].amount, 30.0 * 0.2, "Temporal trail tick uses base attack times 0.2")
	target["enemy"].queue_free()
	await _cleanup_fixture(fixture)


func _test_starfall_releases_ten_waves_of_three() -> void:
	var fixture := await _bow_fixture()
	var bow: Node = fixture["bow"]
	var scheduled_arrows: Array[Dictionary] = []
	for index: int in range(30):
		scheduled_arrows.append({
			"wave_index": index / 3,
			"arrow_index": index % 3,
			"outcome_index": index,
			"seed": 4000 + index,
			"maximum_offset_cells": 1.5,
		})
	var definition := _launch_definition("starfall_arrow_rain", [{
		"descriptor_id": "bow_starfall",
		"kind": "zone_schedule",
		"outcome_index": 0,
		"seed": 3701,
		"parameters": {
			"wave_count": 10,
			"wave_interval_frames": 9,
			"arrows_per_wave": 3,
			"arrow_damage_multiplier": 1.2,
			"time_damage_ratio": 0.6,
			"radius_cells": 4.0,
			"arrows": scheduled_arrows,
		},
	}])
	bow.begin_profile_action(definition)
	_suite.assert_true(bow.release_profile_action(), "Starfall starts its committed wave schedule")
	_suite.assert_equal(_arrows_for_token(701).size(), 3, "Starfall releases wave zero immediately")
	bow.advance_profile_action_for_test(8)
	_suite.assert_equal(_arrows_for_token(701).size(), 3, "Starfall waits nine frames between waves")
	bow.advance_profile_action_for_test(1)
	_suite.assert_equal(_arrows_for_token(701).size(), 6, "Starfall releases the second wave on frame nine")
	bow.advance_profile_action_for_test(72)
	var arrows := _arrows_for_token(701)
	_suite.assert_equal(arrows.size(), 30, "Starfall releases ten waves of three arrows")
	var outcome_indices: Array[int] = []
	for arrow: Node in arrows:
		outcome_indices.append(arrow.outcome_index)
	outcome_indices.sort()
	_suite.assert_equal(outcome_indices, range(30), "Starfall preserves one deterministic outcome index per arrow")
	await _cleanup_fixture(fixture)


func _test_rewind_preflight_supports_trails_centers_scatter_and_skips_starfall() -> void:
	var fixture := await _bow_fixture()
	var player: TestPlayer = fixture["player"]
	var bow: Node = fixture["bow"]
	var temporal_descriptor := _arrow_descriptor(
		"bow_temporal_arrow",
		0,
		5101,
		Vector2.RIGHT,
		{
			"damage_multiplier": 5.0,
			"time_damage_ratio": 1.0,
			"speed_cells_per_second": 10.0,
			"range_cells": 20.0,
			"pierce_mode": "unlimited",
			"trail": {"duration_frames": 300, "width_cells": 0.8, "tick_interval_frames": 30, "tick_damage_multiplier": 0.2, "slow_ratio": 0.3},
		}
	)
	temporal_descriptor["kind"] = "projectile_trail"
	var temporal := _launch_definition("temporal_arrow", [temporal_descriptor])
	temporal["time_interactions"] = [_rewind_interaction(91)]
	bow.begin_profile_action(temporal)
	_suite.assert_true(bow.release_profile_action(), "Rewind preflight accepts projectile_trail before spawning payloads")
	_suite.assert_equal(_arrows_for_token(701).size(), 4, "Temporal Arrow receives three Rewind phantoms")
	_suite.assert_equal(player.interaction_claims.size(), 1, "Temporal Arrow claims the Rewind generation once")
	bow.finish_profile_action()
	_clear_arrows()
	await get_tree().process_frame

	var scatter_descriptors: Array[Dictionary] = []
	for index: int in range(5):
		scatter_descriptors.append(_arrow_descriptor(
			"bow_scatter",
			index,
			5200 + index,
			Vector2.RIGHT.rotated(deg_to_rad(-30.0 + 15.0 * index)),
			{"damage_multiplier": 0.6, "speed_cells_per_second": 18.0, "range_cells": 8.0}
		))
	var scatter := _launch_definition("scatter_shot", scatter_descriptors)
	scatter["time_interactions"] = [_rewind_interaction(92)]
	bow.begin_profile_action(scatter)
	_suite.assert_true(bow.release_profile_action(), "Scatter accepts a generation-safe Rewind echo")
	var phantom_angles: Array[float] = []
	for arrow: Node in _arrows_for_token(701):
		if arrow.attack_tags.has("time:rewind_phantom"):
			phantom_angles.append(snappedf(rad_to_deg((arrow.direction as Vector2).angle()), 0.01))
	phantom_angles.sort()
	_suite.assert_equal(phantom_angles, [-15.0, 0.0, 15.0], "Scatter phantoms center on immutable aim_direction, not the left pellet")
	bow.finish_profile_action()
	_clear_arrows()
	await get_tree().process_frame

	var starfall := _starfall_definition()
	starfall["time_interactions"] = [_rewind_interaction(93)]
	var claims_before := player.interaction_claims.size()
	bow.begin_profile_action(starfall)
	_suite.assert_true(bow.release_profile_action(), "Starfall explicitly ignores incompatible Rewind descriptors")
	_suite.assert_equal(player.interaction_claims.size(), claims_before, "Starfall does not consume the Rewind generation")
	_suite.assert_equal(_arrows_for_token(701).size(), 3, "Starfall still releases wave zero when Rewind is available")
	await _cleanup_fixture(fixture)


func _test_release_failure_is_atomic_before_rewind_claim() -> void:
	var fixture := await _bow_fixture()
	var player: TestPlayer = fixture["player"]
	var bow: Node = fixture["bow"]
	var valid := _arrow_descriptor(
		"bow_temporal_arrow",
		0,
		5901,
		Vector2.RIGHT,
		{
			"damage_multiplier": 5.0,
			"time_damage_ratio": 1.0,
			"speed_cells_per_second": 10.0,
			"range_cells": 20.0,
		}
	)
	var malformed := _arrow_descriptor(
		"bow_temporal_arrow_malformed",
		1,
		5902,
		Vector2.RIGHT,
		{
			"damage_multiplier": 5.0,
			"time_damage_ratio": 1.0,
			"speed_cells_per_second": 10.0,
			"range_cells": 20.0,
			"trail": {
				"duration_frames": 300,
				"width_cells": 0.8,
				"tick_interval_frames": 0,
				"tick_damage_multiplier": 0.2,
			},
		}
	)
	var definition := _launch_definition("temporal_arrow", [valid, malformed])
	definition["time_interactions"] = [_rewind_interaction(94)]
	_suite.assert_equal(
		bow.begin_profile_action(definition),
		definition,
		"malformed nested projectile state reaches release preflight coverage"
	)
	_suite.assert_true(
		not bow.release_profile_action(),
		"release rejects a malformed second projectile descriptor"
	)
	_suite.assert_true(
		_arrows_for_token(701).is_empty(),
		"failed release rolls back every projectile staged by this action"
	)
	_suite.assert_true(
		player.interaction_claims.is_empty(),
		"failed release does not consume the available Rewind generation"
	)
	await _cleanup_fixture(fixture)


func _test_launch_damage_uses_frozen_resolved_multiplier() -> void:
	var fixture := await _bow_fixture()
	var bow: Node = fixture["bow"]
	var descriptor := _arrow_descriptor(
		"bow_scatter",
		0,
		6101,
		Vector2.RIGHT,
		{
			"damage_multiplier": 0.6,
			"resolved_damage_multiplier": 1.2,
			"speed_cells_per_second": 18.0,
			"range_cells": 8.0,
		}
	)
	var definition := _launch_definition("scatter_shot", [descriptor])
	bow.base_attack = 30.0
	bow.begin_profile_action(definition)
	bow.base_attack = 100.0
	_suite.assert_true(bow.release_profile_action(), "staged payload releases after adapter stats change")
	var arrow: Node = _arrows_for_token(701)[0]
	_suite.assert_close(arrow.damage, 36.0, "execution uses frozen base attack times resolved modifier")
	_suite.assert_close(arrow.base_attack, 30.0, "trail and interaction damage retain the staged base attack")
	await _cleanup_fixture(fixture)


func _test_rift_detonation_is_action_scoped_and_uses_live_radius() -> void:
	var fixture := await _bow_fixture()
	var bow: Node = fixture["bow"]
	var descriptors: Array[Dictionary] = []
	for index: int in range(2):
		descriptors.append(_arrow_descriptor(
			"bow_scatter",
			index,
			7000 + index,
			Vector2.RIGHT,
			{"damage_multiplier": 1.0, "speed_cells_per_second": 18.0, "range_cells": 8.0, "full_charge": true}
		))
	var definition := _launch_definition("scatter_shot", descriptors)
	definition["time_interactions"] = [{
		"interaction_id": "bow_rift_penetration",
		"detonation_damage_multiplier": 1.5,
		"detonation_radius_multiplier": 1.5,
	}]
	bow.begin_profile_action(definition)
	_suite.assert_true(bow.release_profile_action(), "Rift action releases its shared interaction claim")
	var target := _recording_enemy_target(2)
	var bystander := _recording_enemy_target(2)
	add_child(target["enemy"])
	add_child(bystander["enemy"])
	target["enemy"].rifted = true
	target["enemy"].global_position = Vector2.ZERO
	bystander["enemy"].global_position = Vector2(145.0, 0.0)
	var rift := RecordingRift.new()
	rift.add_to_group("time_rifts")
	rift.radius = 100.0
	rift.global_position = Vector2.ZERO
	add_child(rift)
	var arrows := _arrows_for_token(701)
	arrows[0].call("_on_area_entered", target["areas"][0])
	arrows[1].call("_on_area_entered", target["areas"][1])
	var radial_hits := 0
	for area: RecordingHitArea in bystander["areas"]:
		for hit: RefCounted in area.received:
			if hit.tags.has("attack:rift_detonation"):
				radial_hits += 1
	_suite.assert_equal(radial_hits, 1, "Rift detonates once per action and reaches radius*1.5 without duplicate hurtbox hits")
	rift.queue_free()
	target["enemy"].queue_free()
	bystander["enemy"].queue_free()
	await _cleanup_fixture(fixture)


func _test_enemy_identity_deduplication_and_source_aware_freeze_cleanup() -> void:
	var fixture := await _bow_fixture()
	var bow: Node = fixture["bow"]
	var descriptor := _arrow_descriptor(
		"bow_temporal_arrow",
		0,
		8101,
		Vector2.RIGHT,
		{
			"damage_multiplier": 5.0,
			"time_damage_ratio": 1.0,
			"speed_cells_per_second": 10.0,
			"range_cells": 20.0,
			"pierce_mode": "unlimited",
			"first_hit_control": {"duration_frames": 90},
		}
	)
	var definition := _launch_definition("temporal_arrow", [descriptor])
	bow.begin_profile_action(definition)
	bow.release_profile_action()
	var arrow: Node = _arrows_for_token(701)[0]
	var target := _recording_enemy_target(2)
	add_child(target["enemy"])
	arrow.call("_on_area_entered", target["areas"][0])
	arrow.call("_on_area_entered", target["areas"][1])
	_suite.assert_equal(target["areas"][0].received.size() + target["areas"][1].received.size(), 1, "one projectile damages an enemy identity once across multiple hurtboxes")
	_suite.assert_equal(target["enemy"].stop_sources.size(), 1, "ordinary first hit uses a unique source-aware stop")
	arrow.advance_execution_for_test(89)
	_suite.assert_equal(target["enemy"].stop_sources.size(), 1, "source-aware stop remains through frame 89")
	arrow.advance_execution_for_test(1)
	_suite.assert_true(target["enemy"].stop_sources.is_empty(), "PlayerArrow clears its stop source exactly at frame 90")
	target["enemy"].queue_free()
	await _cleanup_fixture(fixture)


func _test_trail_and_starfall_statuses_cleanup_without_timers() -> void:
	var fixture := await _bow_fixture()
	var player: TestPlayer = fixture["player"]
	var health := HealthComponentScript.new()
	health.name = "HealthComponent"
	player.add_child(health)
	var bow: Node = fixture["bow"]
	var target := _recording_enemy_target(1)
	add_child(target["enemy"])
	target["enemy"].global_position = Vector2(320.0, 0.0)
	var starfall := _starfall_definition()
	bow.begin_profile_action(starfall)
	_suite.assert_true(bow.release_profile_action(), "Starfall starts its source-aware area lifecycle")
	_suite.assert_true(health.invulnerable, "Starfall owns frame-bounded invulnerability during its active schedule")
	_suite.assert_equal(target["enemy"].slow_sources.size(), 1, "Starfall applies one source-aware area slow")
	bow.advance_profile_action_for_test(30)
	var erosion_sources: Dictionary = target["enemy"].get_meta("bow_time_erosion_sources", {})
	_suite.assert_equal(erosion_sources.values(), [1], "Starfall adds one erosion stack at frame 30")
	health.apply_invulnerability(0.05)
	bow.cancel_profile_action()
	_suite.assert_true(health.invulnerable, "Starfall cancellation releases only its source while timed Dash invulnerability remains active")
	_suite.assert_true(target["enemy"].slow_sources.is_empty(), "Starfall cancellation clears its slow source")
	_suite.assert_true(not target["enemy"].has_meta("bow_time_erosion_sources"), "Starfall cancellation clears erosion metadata")
	await get_tree().create_timer(0.07).timeout
	_suite.assert_true(not health.invulnerable, "invulnerability ends when the overlapping Dash timer expires")
	_suite.assert_true(health.acquire_invulnerability_source(&"manual_source"), "source-aware invulnerability acquisition succeeds")
	_suite.assert_true(not health.acquire_invulnerability_source(&"manual_source"), "duplicate invulnerability source acquisition fails closed")
	_suite.assert_true(not health.acquire_invulnerability_source(&""), "empty invulnerability source acquisition fails closed")
	_suite.assert_true(health.release_invulnerability_source(&"manual_source"), "source-aware invulnerability release succeeds")
	_suite.assert_true(not health.release_invulnerability_source(&"manual_source"), "missing invulnerability source release fails closed")
	bow.begin_profile_action(starfall)
	bow.release_profile_action()
	bow.advance_profile_action_for_test(90)
	_suite.assert_true(not health.invulnerable, "Starfall natural frame-90 completion clears invulnerability without a timer")
	_suite.assert_true(target["enemy"].slow_sources.is_empty(), "Starfall natural completion clears area slow")
	bow.finish_profile_action()
	bow.begin_profile_action(starfall)
	bow.release_profile_action()
	_suite.assert_true(health.acquire_invulnerability_source(&"dash_reset_overlap"), "Dash source can overlap a later Starfall")
	bow.reset_runtime_state()
	await get_tree().process_frame
	_suite.assert_true(health.invulnerable, "Bow reset releases only the Starfall source")
	_suite.assert_true(health.release_invulnerability_source(&"dash_reset_overlap"), "reset overlap releases its independent Dash source")
	_suite.assert_true(not health.invulnerable, "reset overlap leaves no stale invulnerability source")
	_suite.assert_true(health.acquire_invulnerability_source(&"death_cleanup"), "death cleanup source is acquired")
	health.call("_die", null)
	_suite.assert_true(not health.invulnerable, "death clears source-owned invulnerability")
	_suite.assert_true(not health.release_invulnerability_source(&"death_cleanup"), "death removes the owned source instead of leaving it releasable")
	_suite.assert_true(_arrows_for_token(701).is_empty(), "Bow runtime reset frees spawned projectiles owned by the adapter")

	var arrow = load("res://scenes/combat/player_arrow.tscn").instantiate()
	arrow.action_token = 900
	arrow.outcome_index = 1
	arrow.base_attack = 30.0
	arrow.trail_duration_frames = 2
	arrow.trail_tick_interval_frames = 1
	arrow.trail_width_pixels = 64.0
	arrow.trail_tick_damage_multiplier = 0.2
	arrow.trail_slow_ratio = 0.3
	arrow.global_position = target["enemy"].global_position
	add_child(arrow)
	await get_tree().process_frame
	arrow.call("_on_trail_area_entered", target["areas"][0])
	arrow.call("_apply_trail_slow", target["enemy"])
	_suite.assert_true(not target["enemy"].slow_sources.is_empty(), "trail applies its source-aware slow while a point remains")
	arrow.advance_execution_for_test(2)
	_suite.assert_true(target["enemy"].slow_sources.is_empty(), "last trail point expiration immediately clears slow and targets")
	arrow.queue_free()
	target["enemy"].queue_free()
	await _cleanup_fixture(fixture)


func _test_time_interactions_and_boss_conversion_are_consumed_safely() -> void:
	var fixture := await _bow_fixture()
	var bow: Node = fixture["bow"]
	var descriptor := _arrow_descriptor(
		"bow_launch_arrow",
		0,
		5701,
		Vector2.RIGHT,
		{
			"damage_multiplier": 4.5,
			"time_damage_ratio": 0.5,
			"speed_cells_per_second": 32.0,
			"range_cells": 25.0,
			"pierce_mode": "unlimited",
			"full_charge": true,
		}
	)
	var definition := _launch_definition("precision_draw", [descriptor])
	definition["time_interactions"] = [
		{"interaction_id": "bow_stopped_target_burst", "trigger": "full_charge_hit", "explosion_radius_cells": 2.5, "explosion_damage_multiplier": 2.0, "stop_extension_frames": 60},
		{"interaction_id": "bow_echo_arrows", "rewind_echo_generation": 31, "phantom_count": 3, "damage_multiplier": 0.5, "angle_offsets_degrees": [-15.0, 0.0, 15.0], "phantom_descriptors": [{"outcome_index": 1, "seed": 5801, "angle_offset_degrees": -15.0}, {"outcome_index": 2, "seed": 5802, "angle_offset_degrees": 0.0}, {"outcome_index": 3, "seed": 5803, "angle_offset_degrees": 15.0}]},
		{"interaction_id": "bow_charge_speed", "charge_rate_multiplier": 2.0, "quick_recovery_reduction_frames": 6},
		{"interaction_id": "bow_rift_penetration", "trigger": "full_charge_hit_in_rift", "detonation_damage_multiplier": 1.5, "detonation_radius_multiplier": 1.5},
	]
	definition["boss_conversion"] = {
		"preserve_committed_active_attack": true,
		"allowed_phases": ["RECOVERY", "EXPOSED"],
		"recovery_extension_frames": 48,
		"exposure_frames": 60,
		"poise_damage": 12.0,
	}
	bow.begin_profile_action(definition)
	_suite.assert_true(bow.release_profile_action(), "Full-charge launch arrow consumes time-interaction descriptors")
	var arrows := _arrows_for_token(701)
	_suite.assert_equal(arrows.size(), 4, "Rewind descriptor adds exactly three phantom arrows")
	var main_arrow: Node
	var phantom_count := 0
	for arrow: Node in arrows:
		if arrow.attack_tags.has("time:rewind_phantom"):
			phantom_count += 1
		else:
			main_arrow = arrow
	_suite.assert_equal(phantom_count, 3, "All rewind extras are tagged as non-recursive phantom arrows")
	_suite.assert_true(main_arrow.attack_tags.has("time:stop_interaction"), "Stop interaction is attached to the main arrow")
	_suite.assert_true(main_arrow.attack_tags.has("time:accelerate_interaction"), "Accelerate interaction is attached to the main arrow")
	_suite.assert_true(main_arrow.attack_tags.has("time:rift_interaction"), "Rift interaction is attached to the main arrow")

	var target := _recording_target(true)
	var boss: RecordingBoss = target["enemy"]
	boss.exposed = true
	add_child(boss)
	var hit_area: RecordingHitArea = target["area"]
	main_arrow.call("_on_area_entered", hit_area)
	_suite.assert_equal(boss.action, "SLAM", "Bow control never replaces a committed Boss active attack")
	_suite.assert_true(boss.conversions.is_empty(), "Boss conversion is rejected during committed windup even when already exposed")

	var recovery_arrow = PlayerArrowScript.new()
	recovery_arrow.action_token = 702
	recovery_arrow.damage = 10.0
	recovery_arrow.damage_type = 1
	recovery_arrow.boss_conversion = definition["boss_conversion"].duplicate(true)
	recovery_arrow.attack_tags.clear()
	recovery_arrow.attack_tags.append("weapon:bow")
	boss.phase = "RECOVERY"
	recovery_arrow.call("_on_area_entered", hit_area)
	_suite.assert_equal(boss.action, "SLAM", "Recovery conversion preserves the Boss action identity")
	_suite.assert_equal(boss.conversions.size(), 1, "Recovery hit forwards one Boss conversion")
	_suite.assert_close(float(boss.conversions[0]["poise_damage"]), 12.0, "Boss conversion preserves poise contribution")
	recovery_arrow.free()
	boss.queue_free()
	await _cleanup_fixture(fixture)


func _test_real_runtime_packet_executes_through_adapter() -> void:
	var fixture := await _bow_fixture()
	var player: TestPlayer = fixture["player"]
	var bow: Node = fixture["bow"]
	var profile = WeaponRuntimeProfileScript.new()
	var profile_result: Dictionary = profile.configure(_launch_profile_definition())
	_suite.assert_true(bool(profile_result.get("ok", false)), "real adapter integration parses bow_launch_v1")
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(modifiers.configure(
		PackedStringArray([
			"weapon.attack_speed",
			"weapon.charge_rate",
			"weapon.damage",
			"weapon.full_charge_damage",
			"weapon.pierce",
			"weapon.status_duration",
		]),
		{
			"weapon.attack_speed": {"minimum": 0.2, "maximum": 5.0},
			"weapon.charge_rate": {"minimum": 0.0, "maximum": 5.0},
			"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
			"weapon.full_charge_damage": {"minimum": 0.0, "maximum": 11.0},
			"weapon.pierce": {"minimum": 0.0, "maximum": 20.0},
			"weapon.status_duration": {"minimum": 0.0, "maximum": 10.0},
		}
	), "real adapter integration configures launch modifiers")
	var runtime = BowWeaponRuntimeScript.new()
	_suite.assert_true(runtime.configure(player, profile, modifiers), "real Bow runtime accepts the real BowWeapon adapter")

	var scatter_result: Dictionary = runtime.plan_intent(
		{"id": &"weapon_secondary", "edge": &"pressed", "held_frames": 0},
		_runtime_context()
	)
	var scatter_plan: Dictionary = scatter_result.get("plan", {})
	_suite.assert_true(bool(scatter_result.get("ok", false)), "real runtime plans Scatter")
	_suite.assert_true(bool(runtime.commit_action(scatter_plan, 801).get("ok", false)), "real runtime stages Scatter in BowWeapon")
	runtime.on_phase_enter(scatter_plan, &"WINDUP", 801)
	_suite.assert_equal(runtime.on_phase_enter(scatter_plan, &"ACTIVE", 801).size(), 2, "real runtime releases Scatter through ACTIVE")
	_suite.assert_equal(_arrows_for_token(801).size(), 5, "runtime-to-adapter Scatter releases five arrows")
	runtime.finish_action(801)
	_suite.assert_true(not bow.is_profile_action_active(), "real runtime finish clears adapter staging")
	_clear_arrows()

	var temporal_context := _runtime_context()
	temporal_context["time_interactions"] = {
		"stop_active": false,
		"rewind_echo_available": true,
		"rewind_echo_generation": 50,
		"accelerate_active": false,
		"rift_active": false,
	}
	var temporal_result: Dictionary = runtime.plan_intent(
		{"id": &"weapon_skill", "edge": &"pressed", "held_frames": 0},
		temporal_context
	)
	var temporal_plan: Dictionary = temporal_result.get("plan", {})
	_suite.assert_true(bool(temporal_result.get("ok", false)), "real runtime plans Temporal Arrow")
	_suite.assert_true(bool(runtime.commit_action(temporal_plan, 802).get("ok", false)), "real runtime stages Temporal Arrow")
	runtime.on_phase_enter(temporal_plan, &"WINDUP", 802)
	runtime.on_phase_enter(temporal_plan, &"ACTIVE", 802)
	var temporal_arrows := _arrows_for_token(802)
	_suite.assert_equal(temporal_arrows.size(), 4, "runtime-to-adapter Temporal Arrow releases one main arrow and three Rewind phantoms")
	if not temporal_arrows.is_empty():
		var snapshot: Dictionary = temporal_arrows[0].execution_snapshot()
		_suite.assert_equal(snapshot.get("damage_type"), "TIME", "runtime packet preserves Temporal Arrow damage type")
		_suite.assert_equal(snapshot.get("trail_duration_frames"), 300, "runtime packet preserves the 300-frame trail")
		_suite.assert_equal(snapshot.get("trail_tick_interval_frames"), 30, "runtime packet preserves the 30-frame trail tick")
		var outcomes: Array[int] = []
		var target := _recording_enemy_target(1)
		add_child(target["enemy"])
		var area: RecordingHitArea = target["areas"][0]
		var trail_damage := 0.0
		for arrow: Node in temporal_arrows:
			outcomes.append(int(arrow.outcome_index))
			arrow.call("_on_trail_area_entered", area)
			arrow.call("_tick_trail_targets")
			arrow.call("_apply_first_hit_control", area)
			trail_damage += float(area.received[-1].amount)
		outcomes.sort()
		_suite.assert_equal(outcomes, [0, 1, 2, 3], "real Runtime assigns unique Temporal outcomes after the main payload maximum")
		_suite.assert_close(trail_damage, 15.0, "Temporal Rewind trail ticks preserve main damage and scale each phantom by one half")
		_suite.assert_equal(target["enemy"].slow_sources.size(), 4, "main and phantom trail slow sources remain isolated by outcome")
		_suite.assert_equal(target["enemy"].stop_sources.size(), 4, "main and phantom first-hit control sources remain isolated by outcome")
		temporal_arrows[1].queue_free()
		await get_tree().process_frame
		_suite.assert_equal(target["enemy"].slow_sources.size(), 3, "freeing one phantom clears only its trail slow source")
		_suite.assert_equal(target["enemy"].stop_sources.size(), 3, "freeing one phantom clears only its first-hit control source")
		target["enemy"].queue_free()
	runtime.finish_action(802)
	_clear_arrows()

	var primary_context := _runtime_context()
	primary_context["time_interactions"] = {
		"stop_active": true,
		"rewind_echo_available": true,
		"rewind_echo_generation": 51,
		"accelerate_active": false,
		"rift_active": true,
	}
	var primary_result: Dictionary = runtime.plan_intent(
		{"id": &"weapon_primary", "edge": &"released", "held_frames": 48},
		primary_context
	)
	var primary_plan: Dictionary = primary_result.get("plan", {})
	_suite.assert_true(bool(primary_result.get("ok", false)), "real runtime plans a full-charge interaction arrow")
	_suite.assert_true(bool(runtime.commit_action(primary_plan, 803).get("ok", false)), "real runtime stages the full-charge packet")
	runtime.on_phase_enter(primary_plan, &"WINDUP", 803)
	runtime.on_phase_enter(primary_plan, &"ACTIVE", 803)
	var primary_arrows := _arrows_for_token(803)
	_suite.assert_equal(primary_arrows.size(), 4, "real runtime packet creates one main and three generation-claimed phantom arrows")
	var primary_outcomes: Array[int] = []
	for arrow: Node in primary_arrows:
		primary_outcomes.append(int(arrow.outcome_index))
	_suite.assert_equal(primary_outcomes, [0, 1, 2, 3], "real Runtime keeps full-charge Rewind outcomes unique")
	runtime.finish_action(803)
	await _cleanup_fixture(fixture)


func _test_prepared_runtime_snapshot_restores_exactly() -> void:
	var fixture := await _bow_fixture()
	var bow: Node = fixture["bow"]
	var definition := _launch_definition("scatter_shot", [
		_arrow_descriptor(
			"bow_scatter_restore",
			0,
			9201,
			Vector2.RIGHT,
			{"damage_multiplier": 0.6, "speed_cells_per_second": 18.0, "range_cells": 8.0}
		),
	])
	_suite.assert_equal(bow.begin_profile_action(definition), definition, "prepared restore fixture stages the committed Bow definition")
	var snapshot: Dictionary = bow.runtime_snapshot()
	bow.finish_profile_action()
	_suite.assert_true(bow.restore_runtime_snapshot(snapshot), "prepared Bow payload restores before release")
	_suite.assert_equal(bow.runtime_snapshot(), snapshot, "prepared Bow payload round-trips exactly")
	_suite.assert_true(_arrows_for_token(701).is_empty(), "prepared restore does not ghost-release an arrow")
	await _cleanup_fixture(fixture)


func _test_live_arrow_snapshot_restores_targets_without_duplicate_damage() -> void:
	var fixture := await _bow_fixture()
	var bow: Node = fixture["bow"]
	var target := _recording_enemy_target(1)
	target["enemy"].set_meta("stable_target_id", 9301)
	add_child(target["enemy"])
	var descriptor := _arrow_descriptor(
		"bow_temporal_restore",
		0,
		9302,
		Vector2.RIGHT,
		{
			"damage_multiplier": 5.0,
			"time_damage_ratio": 1.0,
			"speed_cells_per_second": 10.0,
			"range_cells": 20.0,
			"pierce_mode": "unlimited",
			"trail": {"duration_frames": 300, "width_cells": 0.8, "tick_interval_frames": 30, "tick_damage_multiplier": 0.2, "slow_ratio": 0.3},
			"first_hit_control": {"duration_frames": 90},
		}
	)
	bow.begin_profile_action(_launch_definition("temporal_arrow", [descriptor]))
	_suite.assert_true(bow.release_profile_action(), "live-arrow restore fixture releases Temporal Arrow")
	var arrow: Node = _arrows_for_token(701)[0]
	var area: RecordingHitArea = target["areas"][0]
	arrow.global_position = Vector2(173.0, 41.0)
	arrow.call("_on_area_entered", area)
	arrow.call("_on_trail_area_entered", area)
	arrow.call("_tick_trail_targets")
	arrow.advance_execution_for_test(7)
	var snapshot: Dictionary = bow.runtime_snapshot()
	var original_instance_id: int = int(target["enemy"].get_instance_id())
	_suite.assert_true(not snapshot.is_empty(), "live Bow adapter emits an authoritative runtime snapshot")
	bow.reset_runtime_state()
	await get_tree().process_frame
	_suite.assert_true(target["enemy"].slow_sources.is_empty(), "reset clears the original trail slow before restore")
	_suite.assert_true(target["enemy"].stop_sources.is_empty(), "reset clears the original time-stop source before restore")
	target["enemy"].queue_free()
	await get_tree().process_frame
	var replacement := _recording_enemy_target(1)
	replacement["enemy"].set_meta("stable_target_id", 9301)
	add_child(replacement["enemy"])
	_suite.assert_true(replacement["enemy"].get_instance_id() != original_instance_id, "restore fixture recreates the target with a different local instance id")
	_suite.assert_true(bow.restore_runtime_snapshot(snapshot), "live Bow arrow restores with transient target bindings")
	_suite.assert_equal(bow.runtime_snapshot(), snapshot, "live arrow world position, lifetime, distance and trail state round-trip exactly")
	var restored: Node = _arrows_for_token(701)[0]
	_suite.assert_equal(restored.global_position, Vector2(173.0, 41.0), "restored arrow preserves its authoritative world position")
	_suite.assert_equal(replacement["enemy"].slow_sources.size(), 1, "restored trail rebinds its source-aware slow to the rebuilt target")
	_suite.assert_equal(replacement["enemy"].stop_sources.size(), 1, "restored first-hit control rebinds to the rebuilt target")
	var replacement_area: RecordingHitArea = replacement["areas"][0]
	restored.call("_on_area_entered", replacement_area)
	_suite.assert_true(replacement_area.received.is_empty(), "stable hit claims prevent duplicate damage after target instance-id drift")
	replacement["enemy"].queue_free()
	await _cleanup_fixture(fixture)


func _test_malformed_and_missing_target_restore_are_atomic() -> void:
	var fixture := await _bow_fixture()
	var bow: Node = fixture["bow"]
	var descriptor := _arrow_descriptor(
		"bow_restore_validation",
		0,
		9401,
		Vector2.RIGHT,
		{"damage_multiplier": 1.0, "speed_cells_per_second": 12.0, "range_cells": 8.0, "pierce_mode": "unlimited"}
	)
	bow.begin_profile_action(_launch_definition("precision_draw", [descriptor]))
	bow.release_profile_action()
	var current: Dictionary = bow.runtime_snapshot()
	var malformed := current.duplicate(true)
	(malformed["arrows"][0]["execution"] as Dictionary).erase("damage_type_value")
	_suite.assert_true(not bow.can_restore_runtime_snapshot(malformed), "missing arrow damage type is rejected during preflight")
	_suite.assert_true(not bow.restore_runtime_snapshot(malformed), "malformed arrow payload is rejected atomically")
	_suite.assert_equal(bow.runtime_snapshot(), current, "malformed restore leaves the current Bow runtime untouched")
	var extra_top_level := current.duplicate(true)
	extra_top_level["future_field"] = true
	_suite.assert_true(not bow.can_restore_runtime_snapshot(extra_top_level), "unknown Bow snapshot fields fail closed")
	var extra_execution := current.duplicate(true)
	(extra_execution["arrows"][0]["execution"] as Dictionary)["future_field"] = true
	_suite.assert_true(not bow.can_restore_runtime_snapshot(extra_execution), "unknown arrow execution fields fail closed")

	var target := _recording_enemy_target(1)
	target["enemy"].set_meta("stable_target_id", 9402)
	add_child(target["enemy"])
	var arrow: Node = _arrows_for_token(701)[0]
	arrow.trail_duration_frames = 120
	arrow.trail_tick_interval_frames = 30
	arrow.trail_width_pixels = 64.0
	arrow.trail_tick_damage_multiplier = 0.2
	arrow.trail_slow_ratio = 0.3
	arrow.call("_append_trail_point", arrow.global_position)
	arrow.call("_on_trail_area_entered", target["areas"][0])
	arrow.call("_tick_trail_targets")
	var missing_target_snapshot: Dictionary = bow.runtime_snapshot()
	bow.reset_runtime_state()
	await get_tree().process_frame
	target["enemy"].queue_free()
	await get_tree().process_frame
	var idle_before: Dictionary = bow.runtime_snapshot()
	_suite.assert_true(not bow.restore_runtime_snapshot(missing_target_snapshot), "missing transient trail target rejects the live-arrow install")
	_suite.assert_equal(bow.runtime_snapshot(), idle_before, "failed transient-target install rolls back to the exact prior adapter state")
	await _cleanup_fixture(fixture)


func _test_starfall_snapshot_resumes_without_duplicate_wave() -> void:
	var fixture := await _bow_fixture()
	var player: TestPlayer = fixture["player"]
	var health := HealthComponentScript.new()
	health.name = "HealthComponent"
	player.add_child(health)
	var bow: Node = fixture["bow"]
	var target := _recording_enemy_target(1)
	target["enemy"].set_meta("stable_target_id", 9501)
	target["enemy"].global_position = Vector2(320.0, 0.0)
	add_child(target["enemy"])
	var definition := _starfall_definition()
	bow.begin_profile_action(definition)
	_suite.assert_true(bow.release_profile_action(), "Starfall restore fixture starts its wave schedule")
	bow.advance_profile_action_for_test(35)
	var snapshot: Dictionary = bow.runtime_snapshot()
	var restored_wave_count := (snapshot["arrows"] as Array).size()
	var frames_until_next := int((snapshot["starfall_schedule"] as Dictionary)["frames_until_next"])
	var erosion_before := int(((snapshot["starfall_targets"] as Array)[0] as Dictionary)["erosion_stacks"])
	bow.reset_runtime_state()
	await get_tree().process_frame
	_suite.assert_true(bow.restore_runtime_snapshot(snapshot), "Starfall schedule, arrows and area state restore together")
	_suite.assert_equal(bow.runtime_snapshot(), snapshot, "Starfall authoritative state round-trips exactly")
	_suite.assert_true(health.invulnerable, "restored Starfall reacquires its owned invulnerability source")
	_suite.assert_equal(target["enemy"].slow_sources.size(), 1, "restored Starfall reapplies its area slow")
	var sources: Dictionary = target["enemy"].get_meta("bow_time_erosion_sources", {})
	_suite.assert_equal(sources.values(), [erosion_before], "restored Starfall preserves erosion stacks")
	bow.advance_profile_action_for_test(maxi(1, frames_until_next))
	_suite.assert_equal(_arrows_for_token(701).size(), restored_wave_count + 3, "restored Starfall releases only the next scheduled wave")
	var outcomes: Dictionary = {}
	for arrow: Node in _arrows_for_token(701):
		outcomes[int(arrow.outcome_index)] = true
	_suite.assert_equal(outcomes.size(), _arrows_for_token(701).size(), "restored Starfall never duplicates an already released outcome")
	target["enemy"].queue_free()
	await _cleanup_fixture(fixture)


func _runtime_context() -> Dictionary:
	return {
		"aim_direction": Vector2.RIGHT,
		"target_point": Vector2(320.0, 0.0),
		"run_seed": 20260929,
		"time_interactions": {},
		"boss_context": {},
	}


func _launch_profile_definition() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == "bow_launch_v1":
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _launch_definition(action_id: String, descriptors: Array) -> Dictionary:
	return {
		"token": 701,
		"profile_id": "bow_launch_v1",
		"weapon_id": "bow",
		"action_id": action_id,
		"semantic_action": "weapon_primary",
		"aim_direction": Vector2.RIGHT,
		"target_point": Vector2(320.0, 0.0),
		"payload_descriptors": descriptors.duplicate(true),
		"time_interactions": [],
		"boss_conversion": {
			"preserve_committed_active_attack": true,
			"allowed_phases": ["RECOVERY", "EXPOSED"],
		},
	}


func _rewind_interaction(generation: int) -> Dictionary:
	return {
		"interaction_id": "bow_echo_arrows",
		"rewind_echo_generation": generation,
		"phantom_count": 3,
		"damage_multiplier": 0.5,
		"angle_offsets_degrees": [-15.0, 0.0, 15.0],
		"phantom_descriptors": [
			{"outcome_index": 30, "seed": generation * 100 + 1, "angle_offset_degrees": -15.0},
			{"outcome_index": 31, "seed": generation * 100 + 2, "angle_offset_degrees": 0.0},
			{"outcome_index": 32, "seed": generation * 100 + 3, "angle_offset_degrees": 15.0},
		],
	}


func _starfall_definition() -> Dictionary:
	var scheduled_arrows: Array[Dictionary] = []
	for index: int in range(30):
		scheduled_arrows.append({
			"wave_index": index / 3,
			"arrow_index": index % 3,
			"outcome_index": index,
			"seed": 9000 + index,
			"maximum_offset_cells": 1.5,
		})
	return _launch_definition("starfall_arrow_rain", [{
		"descriptor_id": "bow_starfall",
		"kind": "zone_schedule",
		"outcome_index": 0,
		"seed": 8901,
		"parameters": {
			"wave_count": 10,
			"wave_interval_frames": 9,
			"arrows_per_wave": 3,
			"arrow_damage_multiplier": 1.2,
			"resolved_arrow_damage_multiplier": 1.2,
			"time_damage_ratio": 0.6,
			"radius_cells": 4.0,
			"invulnerable": true,
			"invulnerability_frames": 90,
			"slow_ratio": 0.4,
			"time_erosion": {
				"stack_interval_frames": 30,
				"time_damage_taken_per_stack": 0.03,
				"maximum_stacks": 10,
			},
			"arrows": scheduled_arrows,
		},
	}])


func _arrow_descriptor(
	descriptor_id: String,
	outcome_index: int,
	seed: int,
	direction: Vector2,
	extra_parameters: Dictionary
) -> Dictionary:
	var parameters := {"direction": direction}
	parameters.merge(extra_parameters, true)
	return {
		"descriptor_id": descriptor_id,
		"kind": "projectile",
		"outcome_index": outcome_index,
		"seed": seed,
		"parameters": parameters,
	}


func _bow_fixture(with_collision: bool = false) -> Dictionary:
	var player := TestPlayer.new()
	player.name = "Player"
	if with_collision:
		var shape_node := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 10.0
		shape_node.shape = shape
		player.add_child(shape_node)
	add_child(player)
	var bow = BowWeaponScript.new()
	bow.name = "BowWeapon"
	bow.owner_path = NodePath("..")
	player.add_child(bow)
	await get_tree().process_frame
	return {"player": player, "bow": bow}


func _cleanup_fixture(fixture: Dictionary) -> void:
	var player: Node = fixture["player"]
	if is_instance_valid(player):
		player.queue_free()
	_clear_arrows()
	await get_tree().process_frame


func _clear_arrows() -> void:
	for arrow: Node in get_tree().get_nodes_in_group("player_arrows"):
		if is_instance_valid(arrow):
			arrow.queue_free()


func _arrows_for_token(token: int) -> Array[Node]:
	var result: Array[Node] = []
	for arrow: Node in get_tree().get_nodes_in_group("player_arrows"):
		if int(arrow.get("action_token")) == token:
			result.append(arrow)
	result.sort_custom(func(left: Node, right: Node) -> bool:
		return int(left.get("outcome_index")) < int(right.get("outcome_index"))
	)
	return result


func _recording_target(as_boss: bool) -> Dictionary:
	var enemy: Node2D = RecordingBoss.new() if as_boss else Node2D.new()
	enemy.add_to_group("enemies")
	if as_boss:
		enemy.add_to_group("bosses")
	var area := RecordingHitArea.new()
	enemy.add_child(area)
	return {"enemy": enemy, "area": area}


func _recording_enemy_target(hurtbox_count: int) -> Dictionary:
	var enemy := RecordingEnemy.new()
	enemy.add_to_group("enemies")
	var areas: Array[RecordingHitArea] = []
	for _index: int in range(hurtbox_count):
		var area := RecordingHitArea.new()
		enemy.add_child(area)
		areas.append(area)
	return {"enemy": enemy, "areas": areas}
