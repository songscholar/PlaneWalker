extends Node

const GunWeaponScript := preload("res://scripts/combat/gun_weapon.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


class RecordingOwner extends Node2D:
	var interaction_claims: Array[Dictionary] = []
	var accept_claim: bool = true


	func claim_weapon_time_interaction(interaction_id: StringName, generation: int) -> bool:
		interaction_claims.append({"interaction_id": interaction_id, "generation": generation})
		return accept_claim


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_shotgun_preconstructs_all_pellets_before_atomic_release()
	await _test_construction_failure_rolls_back_every_prepared_projectile()
	await _test_void_penetration_resolves_split_trail_and_cast_invulnerability()
	await _test_rewind_free_shot_claims_window_before_release()
	await _test_runtime_snapshot_restores_prepared_and_released_projectiles()
	await _test_runtime_restore_rolls_back_and_fails_closed_without_health()
	await _test_reset_clears_released_projectiles_and_transient_state()
	_suite.finish(get_tree())


func _test_shotgun_preconstructs_all_pellets_before_atomic_release() -> void:
	var fixture := _fixture()
	var gun: Node = fixture["gun"]
	var descriptors: Array[Dictionary] = []
	for index: int in range(8):
		descriptors.append(_projectile_descriptor(
			"gun_shotgun_pellets",
			index,
			9100 + index,
			{
				"direction": Vector2.RIGHT.rotated(deg_to_rad(lerpf(-45.0, 45.0, float(index) / 7.0))),
				"damage_multiplier": 0.7,
				"speed_tiles_per_second": 25.0,
				"maximum_range_tiles": 5.0,
				"pierce": 0,
				"hit_width_tiles": 0.2,
				"knockback_tiles": 0.5,
			}
		))
	var definition := _definition("shotgun_fire", 91, descriptors)
	_suite.assert_equal(gun.begin_profile_action(definition), definition, "shotgun action stages only after all eight pellets configure")
	_suite.assert_equal(gun.prepared_projectile_count_for_test(), 8, "shotgun keeps eight pellets off-tree before release")
	_suite.assert_equal(_owned_gun_projectiles(fixture["owner"]).size(), 0, "staging publishes no partial projectile")
	var snapshots: Array[Dictionary] = gun.prepared_projectile_snapshots_for_test()
	var seeds: Dictionary = {}
	for index: int in range(snapshots.size()):
		var snapshot := snapshots[index]
		_suite.assert_close(float(snapshot.get("damage", 0.0)), 10.5, "shotgun pellet %d resolves 0.7 attack" % index)
		_suite.assert_close(float(snapshot.get("speed", 0.0)), 1600.0, "shotgun pellet %d resolves tile speed" % index)
		_suite.assert_close(float(snapshot.get("max_range_pixels", 0.0)), 320.0, "shotgun pellet %d resolves tile range" % index)
		_suite.assert_equal(snapshot.get("outcome_index"), index, "shotgun pellet preserves outcome identity")
		seeds[int(snapshot.get("deterministic_seed", 0))] = true
	_suite.assert_equal(seeds.size(), 8, "shotgun pellets preserve distinct deterministic seeds")
	_suite.assert_true(gun.release_profile_action(), "shotgun releases all staged pellets together")
	await get_tree().process_frame
	_suite.assert_equal(_owned_gun_projectiles(fixture["owner"]).size(), 8, "release attaches all eight pellets")
	gun.finish_profile_action()
	_suite.assert_true(not gun.is_profile_action_active(), "finishing clears adapter action state")
	_suite.assert_equal(_owned_gun_projectiles(fixture["owner"]).size(), 8, "finished projectiles continue their committed flight")
	_free_fixture(fixture)
	await get_tree().process_frame


func _test_construction_failure_rolls_back_every_prepared_projectile() -> void:
	var fixture := _fixture()
	var gun: Node = fixture["gun"]
	var valid := _projectile_descriptor("gun_shotgun_pellets", 0, 9200, {
		"direction": Vector2.RIGHT,
		"damage_multiplier": 0.7,
		"speed_tiles_per_second": 25.0,
		"maximum_range_tiles": 5.0,
		"pierce": 0,
		"hit_width_tiles": 0.2,
		"knockback_tiles": 0.5,
	})
	var invalid := valid.duplicate(true)
	invalid["outcome_index"] = 1
	invalid["seed"] = 9201
	(invalid["parameters"] as Dictionary)["direction"] = Vector2.ZERO
	var rejected: Dictionary = gun.begin_profile_action(_definition("shotgun_fire", 92, [valid, invalid]))
	_suite.assert_true(rejected.is_empty(), "one invalid pellet rejects the entire shotgun construction")
	_suite.assert_equal(gun.prepared_projectile_count_for_test(), 0, "failed construction frees every previously prepared pellet")
	_suite.assert_true(not gun.is_profile_action_active(), "failed construction leaves adapter idle")
	_suite.assert_equal(_owned_gun_projectiles(fixture["owner"]).size(), 0, "failed construction never attaches a projectile")
	_free_fixture(fixture)
	await get_tree().process_frame


func _test_void_penetration_resolves_split_trail_and_cast_invulnerability() -> void:
	var fixture := _fixture()
	var gun: Node = fixture["gun"]
	var health: Node = fixture["health"]
	var descriptor := _projectile_descriptor("gun_void_round", 0, 9300, {
		"direction": Vector2.RIGHT,
		"damage_multiplier": 15.0,
		"void_damage_ratio": 0.6,
		"time_damage_ratio": 0.4,
		"speed_tiles_per_second": 60.0,
		"maximum_range_tiles": 30.0,
		"pierce": -1,
		"unlimited_pierce": true,
		"hit_width_tiles": 1.5,
		"knockback_tiles": 0.0,
		"penetration_explosion": {
			"radius_tiles": 1.5,
			"damage_multiplier": 0.3,
			"damage_type": "void",
		},
		"trail": {
			"duration_frames": 300,
			"width_tiles": 1.0,
			"tick_interval_frames": 30,
			"damage_multiplier": 0.1,
			"damage_type": "void",
		},
		"vulnerability": {
			"duration_frames": 180,
			"damage_taken_bonus": 0.15,
		},
	})
	var definition := _definition("void_penetration", 93, [descriptor])
	definition["invulnerable_during_cast"] = true
	_suite.assert_equal(gun.begin_profile_action(definition), definition, "Void Penetration stages its complete execution payload")
	_suite.assert_true(bool(health.get("invulnerable")), "Void Penetration acquires source-aware cast invulnerability")
	var snapshots: Array[Dictionary] = gun.prepared_projectile_snapshots_for_test()
	_suite.assert_equal(snapshots.size(), 1, "Void Penetration prepares one projectile")
	if snapshots.is_empty():
		_free_fixture(fixture)
		await get_tree().process_frame
		return
	var snapshot := snapshots[0]
	_suite.assert_close(float(snapshot.get("damage", 0.0)), 135.0, "Void component resolves sixty percent of fifteen-times attack")
	_suite.assert_close(float(snapshot.get("time_damage_ratio", 0.0)), 6.0, "Time component resolves forty percent of fifteen-times attack")
	_suite.assert_equal(snapshot.get("pierce_mode"), "unlimited", "Void Penetration uses unlimited pierce")
	_suite.assert_equal(snapshot.get("trail_duration_frames"), 300, "Void trail preserves its five-second duration")
	_suite.assert_close(float(snapshot.get("trail_width_pixels", 0.0)), 64.0, "Void trail resolves one tile width")
	_suite.assert_true(gun.release_profile_action(), "Void Penetration releases its staged projectile")
	gun.finish_profile_action()
	_suite.assert_true(not bool(health.get("invulnerable")), "finishing the cast releases only Gun's invulnerability source")
	_free_fixture(fixture)
	await get_tree().process_frame


func _test_rewind_free_shot_claims_window_before_release() -> void:
	var fixture := _fixture()
	var owner: RecordingOwner = fixture["owner"]
	var gun: Node = fixture["gun"]
	var descriptor := _projectile_descriptor("gun_normal_bullet", 0, 9350, {
		"direction": Vector2.RIGHT,
		"damage_multiplier": 1.5,
		"speed_tiles_per_second": 40.0,
		"maximum_range_tiles": 15.0,
		"pierce": 0,
		"hit_width_tiles": 0.2,
		"knockback_tiles": 0.3,
	})
	descriptor["token"] = 935
	var definition := _definition("normal_fire", 935, [descriptor])
	definition["time_interactions"] = [{
		"interaction_id": "gun_rewind_free_shot",
		"rewind_generation": 17,
		"one_shot_claim": true,
	}]
	_suite.assert_equal(gun.begin_profile_action(definition), definition, "Rewind shot stages only after claiming the live window")
	_suite.assert_equal(owner.interaction_claims.size(), 1, "Rewind shot claims one external generation")
	if owner.interaction_claims.size() == 1:
		_suite.assert_equal(owner.interaction_claims[0].get("interaction_id"), &"bow_rewind_echo", "Gun claims the shared Rewind weapon window")
		_suite.assert_equal(owner.interaction_claims[0].get("generation"), 17, "Rewind shot claims its frozen generation")
	_suite.assert_true(gun.release_profile_action(), "claimed Rewind shot releases")
	await get_tree().process_frame
	var projectile: Node = _owned_gun_projectiles(owner)[0]
	var forwarded := [0]
	gun.action_hit_confirmed.connect(func(_token: int, _target: Node) -> void: forwarded[0] += 1)
	gun.reset_runtime_state()
	projectile.action_hit_confirmed.emit(935, owner)
	_suite.assert_equal(forwarded[0], 0, "adapter ignores a stale projectile callback after reset")
	_free_fixture(fixture)
	await get_tree().process_frame

	fixture = _fixture()
	owner = fixture["owner"]
	gun = fixture["gun"]
	owner.accept_claim = false
	_suite.assert_true(gun.begin_profile_action(definition).is_empty(), "rejected Rewind generation fails construction closed")
	_suite.assert_equal(gun.prepared_projectile_count_for_test(), 0, "failed Rewind claim rolls back its staged projectile")
	_suite.assert_true(not gun.is_profile_action_active(), "failed Rewind claim leaves the adapter idle")
	_free_fixture(fixture)
	await get_tree().process_frame


func _test_reset_clears_released_projectiles_and_transient_state() -> void:
	var fixture := _fixture()
	var gun: Node = fixture["gun"]
	var descriptor := _projectile_descriptor("gun_normal_bullet", 0, 9400, {
		"direction": Vector2.RIGHT,
		"damage_multiplier": 1.0,
		"speed_tiles_per_second": 40.0,
		"maximum_range_tiles": 15.0,
		"pierce": 0,
		"hit_width_tiles": 0.2,
		"knockback_tiles": 0.3,
	})
	var definition := _definition("normal_fire", 94, [descriptor])
	_suite.assert_true(gun.profile_definition_valid_for_test(definition), "normal shot definition passes adapter validation")
	_suite.assert_true(not gun.projectile_execution_for_test(descriptor, definition).is_empty(), "normal shot resolves a projectile execution dictionary")
	_suite.assert_true(not gun.begin_profile_action(definition).is_empty(), "normal shot stages")
	_suite.assert_true(gun.release_profile_action(), "normal shot releases")
	await get_tree().process_frame
	_suite.assert_equal(gun.owned_projectile_count_for_test(), 1, "adapter owns the released projectile")
	gun.reset_runtime_state()
	_suite.assert_equal(gun.prepared_projectile_count_for_test(), 0, "reset clears prepared projectile state")
	_suite.assert_equal(gun.owned_projectile_count_for_test(), 0, "reset disposes released projectiles")
	_suite.assert_true(not gun.is_profile_action_active(), "reset clears active action state")
	_free_fixture(fixture)
	await get_tree().process_frame


func _test_runtime_snapshot_restores_prepared_and_released_projectiles() -> void:
	var fixture := _fixture()
	var gun: Node = fixture["gun"]
	var descriptor := _projectile_descriptor("gun_normal_bullet", 0, 9500, {
		"direction": Vector2(0.6, 0.8),
		"damage_multiplier": 1.0,
		"speed_tiles_per_second": 40.0,
		"maximum_range_tiles": 15.0,
		"pierce": 1,
		"hit_width_tiles": 0.2,
		"knockback_tiles": 0.3,
	})
	var definition := _definition("normal_fire", 95, [descriptor])
	_suite.assert_equal(gun.begin_profile_action(definition), definition, "prepared restore fixture stages a projectile")
	var prepared: Dictionary = gun.runtime_snapshot()
	gun.cancel_profile_action()
	_suite.assert_true(gun.restore_runtime_snapshot(prepared), "prepared Gun adapter snapshot restores")
	_suite.assert_equal(gun.runtime_snapshot(), prepared, "prepared Gun adapter round-trips exactly")
	_suite.assert_equal(gun.prepared_projectile_count_for_test(), 1, "prepared restore recreates the off-tree projectile")

	_suite.assert_true(gun.release_profile_action(), "restored prepared projectile releases")
	await get_tree().process_frame
	var owned: Array[Node] = gun.owned_projectiles_for_test()
	_suite.assert_equal(owned.size(), 1, "released restore fixture owns one real projectile")
	if owned.is_empty():
		_free_fixture(fixture)
		await get_tree().process_frame
		return
	owned[0].global_position = Vector2(220.0, 96.0)
	owned[0].advance_execution_for_test(11)
	var released: Dictionary = gun.runtime_snapshot()
	gun.cancel_profile_action()
	await get_tree().process_frame
	_suite.assert_true(gun.restore_runtime_snapshot(released), "released Gun adapter snapshot restores")
	_suite.assert_equal(gun.runtime_snapshot(), released, "released Gun adapter preserves world position and execution progress exactly")
	owned = gun.owned_projectiles_for_test()
	_suite.assert_equal(owned.size(), 1, "released restore recreates one live projectile")
	var forwarded := [0]
	gun.action_hit_confirmed.connect(func(_token: int, _target: Node) -> void: forwarded[0] += 1)
	if not owned.is_empty():
		owned[0].action_hit_confirmed.emit(95, fixture["owner"])
	_suite.assert_equal(forwarded[0], 1, "restored projectile callback remains connected to the adapter")

	var stable: Dictionary = gun.runtime_snapshot()
	var malformed := stable.duplicate(true)
	malformed["owned_projectiles"][0]["execution"]["descriptor_id"] = "forged_descriptor"
	_suite.assert_true(not gun.restore_runtime_snapshot(malformed), "forged adapter payload identity fails closed")
	_suite.assert_equal(gun.runtime_snapshot(), stable, "forged adapter restore preserves the current live payload atomically")
	var extra_top_level := stable.duplicate(true)
	extra_top_level["future_field"] = true
	_suite.assert_true(not gun.can_restore_runtime_snapshot(extra_top_level), "unknown Gun adapter snapshot fields fail closed")
	var extra_payload := stable.duplicate(true)
	extra_payload["owned_projectiles"][0]["future_field"] = true
	_suite.assert_true(not gun.can_restore_runtime_snapshot(extra_payload), "unknown Gun payload wrapper fields fail closed")
	_free_fixture(fixture)
	await get_tree().process_frame


func _test_runtime_restore_rolls_back_and_fails_closed_without_health() -> void:
	var source_fixture := _fixture()
	var source_gun: Node = source_fixture["gun"]
	var target_definition := _void_definition(96, 9600)
	_suite.assert_equal(source_gun.begin_profile_action(target_definition), target_definition, "atomic restore target stages an invulnerable action")
	var target: Dictionary = source_gun.runtime_snapshot()
	_free_fixture(source_fixture)
	await get_tree().process_frame

	var rollback_fixture := _fixture()
	var rollback_owner: Node = rollback_fixture["owner"]
	var rollback_health: Node = rollback_fixture["health"]
	rollback_owner.remove_child(rollback_health)
	var rollback_gun: Node = rollback_fixture["gun"]
	var normal_descriptor := _projectile_descriptor("gun_normal_bullet", 0, 9700, {
		"direction": Vector2.RIGHT,
		"damage_multiplier": 1.0,
		"speed_tiles_per_second": 40.0,
		"maximum_range_tiles": 15.0,
		"pierce": 0,
		"hit_width_tiles": 0.2,
		"knockback_tiles": 0.3,
	})
	var normal_definition := _definition("normal_fire", 97, [normal_descriptor])
	_suite.assert_equal(rollback_gun.begin_profile_action(normal_definition), normal_definition, "rollback fixture stages a non-invulnerable action")
	var current: Dictionary = rollback_gun.runtime_snapshot()
	_suite.assert_true(not rollback_gun.restore_runtime_snapshot(target), "failed invulnerability acquisition rejects the target adapter snapshot")
	_suite.assert_equal(rollback_gun.runtime_snapshot(), current, "failed target application restores the prior live adapter state exactly")
	_free_fixture(rollback_fixture)
	rollback_health.free()
	await get_tree().process_frame

	var fail_closed_fixture := _fixture()
	var fail_closed_gun: Node = fail_closed_fixture["gun"]
	var current_definition := _void_definition(98, 9800)
	_suite.assert_equal(fail_closed_gun.begin_profile_action(current_definition), current_definition, "double-failure fixture stages its rollback action")
	var fail_closed_owner: Node = fail_closed_fixture["owner"]
	var fail_closed_health: Node = fail_closed_fixture["health"]
	fail_closed_owner.remove_child(fail_closed_health)
	_suite.assert_true(not fail_closed_gun.restore_runtime_snapshot(target), "target and rollback application failure returns false")
	var failed_closed: Dictionary = fail_closed_gun.runtime_snapshot()
	_suite.assert_equal(failed_closed.get("phase_state"), "idle", "double restore failure resets the adapter to idle")
	_suite.assert_equal(fail_closed_gun.prepared_projectile_count_for_test(), 0, "double restore failure clears prepared projectiles")
	_suite.assert_equal(fail_closed_gun.owned_projectile_count_for_test(), 0, "double restore failure clears owned projectiles")
	_free_fixture(fail_closed_fixture)
	fail_closed_health.free()
	await get_tree().process_frame


func _fixture() -> Dictionary:
	var owner := RecordingOwner.new()
	owner.name = "GunOwner"
	add_child(owner)
	var health = HealthComponentScript.new()
	health.name = "HealthComponent"
	health.max_hp = 100.0
	owner.add_child(health)
	var gun = GunWeaponScript.new()
	gun.name = "GunWeapon"
	gun.owner_path = NodePath("..")
	owner.add_child(gun)
	return {"owner": owner, "health": health, "gun": gun}


func _free_fixture(fixture: Dictionary) -> void:
	var gun: Node = fixture["gun"]
	if is_instance_valid(gun):
		gun.reset_runtime_state()
	var owner: Node = fixture["owner"]
	if is_instance_valid(owner):
		owner.queue_free()


func _definition(action_id: String, token: int, descriptors: Array) -> Dictionary:
	return {
		"token": token,
		"profile_id": "gun_launch_v1",
		"weapon_id": "gun",
		"action_id": action_id,
		"semantic_action": "weapon_primary",
		"aim_direction": Vector2.RIGHT,
		"base_attack": 15.0,
		"payload_descriptors": descriptors.duplicate(true),
		"time_interactions": [],
		"boss_conversion": {
			"conversion_id": "gun_weakpoint_pressure",
			"allowed_phases": ["RECOVERY", "EXPOSED"],
			"poise_multiplier": 1.1,
		},
		"invulnerable_during_cast": false,
	}


func _void_definition(token: int, seed: int) -> Dictionary:
	var descriptor := _projectile_descriptor("gun_void_round", 0, seed, {
		"direction": Vector2.RIGHT,
		"damage_multiplier": 15.0,
		"void_damage_ratio": 0.6,
		"time_damage_ratio": 0.4,
		"speed_tiles_per_second": 60.0,
		"maximum_range_tiles": 30.0,
		"pierce": -1,
		"unlimited_pierce": true,
		"hit_width_tiles": 1.5,
		"knockback_tiles": 0.0,
	})
	var definition := _definition("void_penetration", token, [descriptor])
	definition["semantic_action"] = "weapon_ultimate"
	definition["invulnerable_during_cast"] = true
	return definition


func _projectile_descriptor(
	descriptor_id: String,
	outcome_index: int,
	seed: int,
	parameters: Dictionary
) -> Dictionary:
	return {
		"descriptor_id": descriptor_id,
		"kind": "projectile",
		"token": 91 + int(seed / 100) - 91,
		"outcome_index": outcome_index,
		"seed": seed,
		"target_deduplication": "per_pellet" if descriptor_id == "gun_shotgun_pellets" else "per_action_token",
		"parameters": parameters.duplicate(true),
	}


func _owned_gun_projectiles(owner: Node) -> Array[Node]:
	var result: Array[Node] = []
	for projectile: Node in get_tree().get_nodes_in_group("gun_projectiles"):
		if is_instance_valid(projectile) and projectile.get("owner_entity") == owner:
			result.append(projectile)
	return result
