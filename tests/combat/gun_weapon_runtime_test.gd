extends Node

const GunWeaponRuntimeScript := preload("res://scripts/combat/weapons/gun_weapon_runtime.gd")
const GunWeaponScript := preload("res://scripts/combat/gun_weapon.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponActionCoordinatorScript := preload("res://scripts/combat/weapons/weapon_action_coordinator.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponResourceTransactionScript := preload("res://scripts/combat/weapons/weapon_resource_transaction.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"


class FakeGunAdapter extends Node2D:
	var base_attack: float = 15.0
	var attack_speed: float = 1.0
	var character_attack_scale: float = 1.0
	var crit_chance: float = 0.05
	var crit_multiplier: float = 1.5
	var fail_begin: bool = false
	var corrupt_begin: bool = false
	var fail_release: bool = false
	var begin_count: int = 0
	var release_count: int = 0
	var cancel_count: int = 0
	var finish_count: int = 0
	var reset_count: int = 0
	var gameplay_rewind_restore_calls: int = 0
	var drift_gameplay_rewind_restore_on_calls: Array[int] = []
	var staged_definition: Dictionary = {}
	var released_definition: Dictionary = {}
	var _active: bool = false
	var _released: bool = false


	func begin_profile_action(definition: Dictionary) -> Dictionary:
		begin_count += 1
		if fail_begin:
			return {}
		staged_definition = definition.duplicate(true)
		_active = true
		_released = false
		var result := staged_definition.duplicate(true)
		if corrupt_begin:
			result["action_id"] = "corrupt_action"
		return result


	func release_profile_action() -> bool:
		if fail_release or not _active or _released:
			return false
		_released = true
		release_count += 1
		released_definition = staged_definition.duplicate(true)
		return true


	func is_profile_action_active() -> bool:
		return _active


	func cancel_profile_action() -> void:
		cancel_count += 1
		_clear_action()


	func finish_profile_action() -> void:
		finish_count += 1
		_clear_action()


	func reset_runtime_state() -> void:
		reset_count += 1
		_clear_action()


	func cancel_for_gameplay_rewind() -> bool:
		_clear_action()
		return true


	func restore_gameplay_rewind_snapshot_for_rollback(value: Dictionary) -> bool:
		gameplay_rewind_restore_calls += 1
		if (
			not value.get("profile_action") is Dictionary
			or typeof(value.get("profile_action_released")) != TYPE_BOOL
			or not value.get("prepared_projectiles") is Array
			or not value.get("action_claims_by_token") is Dictionary
			or value.get("committed_payload_guard") != gameplay_rewind_committed_payload_guard()
		):
			return false
		var action := value["profile_action"] as Dictionary
		_active = not action.is_empty()
		_released = bool(value["profile_action_released"])
		staged_definition = action.duplicate(true)
		released_definition = action.duplicate(true) if _released else {}
		if drift_gameplay_rewind_restore_on_calls.has(gameplay_rewind_restore_calls):
			staged_definition["restore_drift"] = true
		return true


	func gameplay_rewind_committed_payload_guard() -> Dictionary:
		return {}


	func runtime_snapshot() -> Dictionary:
		return {
			"schema_version": 1,
			"profile_action": staged_definition.duplicate(true) if _active else {},
			"profile_action_released": _released,
			"phase_state": "idle" if not _active else ("released" if _released else "prepared"),
			"prepared_projectiles": [],
			"owned_projectiles": [],
			"action_claims_by_token": {},
		}


	func can_restore_runtime_snapshot(value: Dictionary) -> bool:
		return (
			int(value.get("schema_version", -1)) == 1
			and value.get("profile_action") is Dictionary
			and typeof(value.get("profile_action_released")) == TYPE_BOOL
			and str(value.get("phase_state", "")) in ["idle", "prepared", "released"]
			and value.get("prepared_projectiles") is Array
			and value.get("owned_projectiles") is Array
			and value.get("action_claims_by_token") is Dictionary
		)


	func restore_runtime_snapshot(value: Dictionary) -> bool:
		if not can_restore_runtime_snapshot(value):
			return false
		var action := value["profile_action"] as Dictionary
		_active = not action.is_empty()
		_released = bool(value["profile_action_released"])
		staged_definition = action.duplicate(true)
		released_definition = action.duplicate(true) if _released else {}
		return runtime_snapshot() == value


	func _clear_action() -> void:
		_active = false
		_released = false
		staged_definition.clear()
		released_definition.clear()


class FakeTimeEnergyProvider extends RefCounted:
	var current: float = 100.0
	var revision: int = 1
	var spend_calls: int = 0


	func resource_state(resource_id: StringName) -> Dictionary:
		if resource_id != &"time_energy":
			return {"ok": false, "code": &"RESOURCE_NOT_FOUND", "context": {}}
		return {
			"ok": true,
			"code": &"OK",
			"resource_id": "time_energy",
			"current": current,
			"minimum": 0.0,
			"maximum": 100.0,
			"revision": revision,
			"context": {},
		}


	func try_spend_resource(
		resource_id: StringName,
		amount: float,
		expected_revision: int,
		_reason: StringName
	) -> Dictionary:
		spend_calls += 1
		if resource_id != &"time_energy" or expected_revision != revision or current < amount:
			return {"ok": false, "code": &"RESOURCE_COMMIT_FAILED", "context": {}}
		var before := current
		current -= amount
		revision += 1
		return {
			"ok": true,
			"code": &"OK",
			"resource_id": "time_energy",
			"before": before,
			"after": current,
			"revision": revision,
			"context": {},
		}


var _suite
var _coordinator_facts: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_character_stats_freeze_across_hold_release()
	_test_catalog_profile_is_strict()
	_test_primary_hold_and_ammo_boundaries()
	_test_coordinator_publishes_real_hold_identity_and_live_reload()
	_test_shotgun_is_atomic_seeded_and_pellet_scoped()
	_test_reload_half_open_boundaries_and_completion()
	_test_perfect_reload_grants_free_time_load_without_touching_active_cooldown()
	_test_active_time_load_refills_and_accelerates_future_shots()
	_test_ultimate_hold_boundary_and_time_load_amplification()
	_test_four_time_interactions_and_chrono_warden_conversion()
	_test_snapshot_restore_reset_and_modifier_boundaries()
	_test_failed_gameplay_rewind_restore_compensates_adapter_and_runtime()
	await _test_real_adapter_gameplay_rewind_preserves_committed_projectile_identity()
	_suite.finish(get_tree())


func _test_character_stats_freeze_across_hold_release() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var adapter: FakeGunAdapter = fixture["gun"]
	adapter.base_attack = 13.5
	adapter.attack_speed = 0.9
	adapter.character_attack_scale = 0.9
	adapter.crit_chance = 0.04
	adapter.crit_multiplier = 1.6
	var hold: Dictionary = runtime.plan_intent(
		_press_intent(&"weapon_primary"),
		_context(91001)
	).get("plan", {})
	_assert_character_stats(hold, {}, 0.9, 0.9, 0.04, 1.6, "Gun hold")
	_suite.assert_true(bool(runtime.commit_action(hold, 91001).get("ok", false)), "Gun character-stat hold commits")
	adapter.base_attack = 999.0
	adapter.attack_speed = 4.0
	adapter.character_attack_scale = 4.0
	adapter.crit_chance = 1.0
	adapter.crit_multiplier = 9.0
	var live_context := _context(91002)
	live_context["aim_direction"] = Vector2.UP
	_suite.assert_true(
		runtime.update_hold_context(hold, 91001, live_context),
		"Gun HOLD context updates without replacing frozen character stats"
	)
	var released: Dictionary = runtime.release_hold(hold, 91001, 0)
	_suite.assert_true(bool(released.get("ok", false)), "Gun character-stat hold releases")
	var finalized: Dictionary = released.get("finalized_plan", {})
	_suite.assert_equal(int(finalized.get("run_seed", 0)), 91002, "Gun HOLD keeps live run seed updates")
	_suite.assert_equal(finalized.get("aim_direction_snapshot", Vector2.ZERO), Vector2.UP, "Gun HOLD keeps live aim updates")
	var parameters := _payload_parameters(finalized)
	_assert_character_stats(finalized, parameters, 0.9, 0.9, 0.04, 1.6, "Gun finalized payload")
	_suite.assert_close(float(adapter.staged_definition.get("base_attack", 0.0)), 13.5, "Gun committed definition keeps the scaled base attack")
	_suite.assert_close(float(adapter.staged_definition.get("character_attack_scale", 0.0)), 0.9, "Gun committed definition freezes character attack scale")
	_suite.assert_close(float(adapter.staged_definition.get("crit_chance", -1.0)), 0.04, "Gun committed definition freezes critical chance")
	_suite.assert_close(float(adapter.staged_definition.get("crit_multiplier", 0.0)), 1.6, "Gun committed definition freezes critical multiplier")
	_free_fixture(fixture)


func _test_catalog_profile_is_strict() -> void:
	for method_name: StringName in [
		&"cancel_for_gameplay_rewind",
		&"restore_gameplay_rewind_snapshot_for_rollback",
		&"gameplay_rewind_committed_payload_guard",
	]:
		_suite.assert_true(
			GunWeaponRuntimeScript.REQUIRED_ADAPTER_METHODS.has(method_name),
			"Gun Runtime configuration requires %s" % method_name
		)
	var fixture := _fixture()
	_suite.assert_true(bool(fixture.get("configured", false)), "authoritative gun_launch_v1 fixture configures")
	var runtime: RefCounted = fixture["runtime"]
	_suite.assert_equal(
		_sorted_strings(runtime.capabilities()),
		[
			"weapon.ammo_capacity",
			"weapon.attack_speed",
			"weapon.damage",
			"weapon.reload_window",
			"weapon.status_duration",
		],
		"Gun exposes only the declared capability set"
	)

	for drift_case: Dictionary in [
		{"label": "normal windup", "section": "actions", "id": "normal_fire", "field": "windup_frames", "value": 2},
		{"label": "aimed multiplier", "section": "payloads", "id": "gun_aimed_bullet", "field": "damage_multiplier", "value": 1.8},
		{"label": "shotgun spread", "section": "payloads", "id": "gun_shotgun_pellets", "field": "spread_degrees", "value": 28.0},
		{"label": "Time Load cooldown", "section": "actions", "id": "time_load", "field": "cooldown_frames", "value": 0},
		{"label": "ultimate cost", "section": "actions", "id": "void_penetration", "field": "resource_costs", "value": {"time_energy": 55.0}},
	]:
		var drift := _catalog_profile("gun_launch_v1")
		var id_field := "action_id" if drift_case["section"] == "actions" else "payload_id"
		var entry := _dictionary_ref_by_id(drift[drift_case["section"]], id_field, drift_case["id"])
		if drift_case["section"] == "payloads":
			(entry["parameters"] as Dictionary)[drift_case["field"]] = drift_case["value"]
		else:
			entry[drift_case["field"]] = drift_case["value"]
		_assert_profile_rejected(fixture["owner"], fixture["modifiers"], drift, drift_case["label"])

	for metadata_drift: Dictionary in [
		{"label": "availability", "field": "availability", "value": ["NEXT", "LAUNCH"]},
		{"label": "name localization key", "field": "name_key", "value": "WEAPON_GUN_ALT_NAME"},
		{"label": "description localization key", "field": "description_key", "value": "WEAPON_GUN_ALT_DESC"},
		{"label": "tag set", "field": "tags", "value": ["ammunition", "reload"]},
		{"label": "compatibility", "field": "compatibility", "value": {"weapon_ids": ["gun"], "modes": ["endless"]}},
		{"label": "reference set", "field": "references", "value": ["gun", "gun_projectile"]},
	]:
		var drift := _catalog_profile("gun_launch_v1")
		drift[metadata_drift["field"]] = metadata_drift["value"]
		_assert_profile_rejected(
			fixture["owner"],
			fixture["modifiers"],
			drift,
			metadata_drift["label"]
		)

	_free_fixture(fixture)


func _test_coordinator_publishes_real_hold_identity_and_live_reload() -> void:
	var fixture := _coordinator_fixture()
	var coordinator: RefCounted = fixture["coordinator"]
	var runtime: RefCounted = fixture["runtime"]
	var provider: FakeTimeEnergyProvider = fixture["provider"]

	var pressed: Dictionary = coordinator.submit_intent(
		_press_intent(&"weapon_primary"),
		_context(7051)
	)
	var normal_token := int(pressed.get("token", 0))
	_advance_coordinator(coordinator, 17)
	var released: Dictionary = coordinator.submit_intent(
		_release_intent(&"weapon_primary", 999),
		_context(7052)
	)
	_suite.assert_true(bool(released.get("ok", false)), "coordinator releases the seventeen-frame primary HOLD")
	_suite.assert_equal(released.get("token"), normal_token, "normal_fire keeps the original HOLD token")
	_suite.assert_equal(coordinator.snapshot().get("plan", {}).get("action_id"), "normal_fire", "coordinator adopts normal_fire as the live action identity")
	_suite.assert_equal(coordinator.presentation_snapshot().get("action_id"), "normal_fire", "normal_fire identity reaches presentation")
	_suite.assert_equal(_coordinator_facts.size(), 1, "normal HOLD release publishes one committed fact")
	_suite.assert_equal(_coordinator_facts[0].get("action_id"), "normal_fire", "normal committed fact uses the real release identity")
	coordinator.cancel(&"normal_identity_verified")

	pressed = coordinator.submit_intent(_press_intent(&"weapon_primary"), _context(7053))
	var aimed_token := int(pressed.get("token", 0))
	_advance_coordinator(coordinator, 18)
	released = coordinator.submit_intent(_release_intent(&"weapon_primary", 0), _context(7054))
	_suite.assert_true(bool(released.get("ok", false)), "coordinator releases the eighteen-frame primary HOLD")
	_suite.assert_equal(released.get("token"), aimed_token, "aimed_fire keeps the original HOLD token")
	_suite.assert_equal(coordinator.snapshot().get("plan", {}).get("action_id"), "aimed_fire", "coordinator adopts aimed_fire as the live action identity")
	_suite.assert_equal(coordinator.presentation_snapshot().get("action_id"), "aimed_fire", "aimed_fire identity reaches presentation")
	_suite.assert_equal(_coordinator_facts.size(), 2, "aimed HOLD release publishes one additional committed fact")
	_suite.assert_equal(_coordinator_facts[1].get("action_id"), "aimed_fire", "aimed committed fact uses the real release identity")
	coordinator.cancel(&"aimed_identity_verified")

	_suite.assert_true(_restore_ammo(runtime, 2), "coordinator reload fixture restores two rounds")
	var started: Dictionary = coordinator.submit_intent(
		_press_intent(&"weapon_utility"),
		_context(7055)
	)
	var reload_token := int(started.get("token", 0))
	_advance_coordinator(coordinator, 28)
	_suite.assert_equal(coordinator.phase_name(), &"RESOURCE_ACTION", "reload reaches its authoritative resource phase")
	_suite.assert_equal(coordinator.presentation_snapshot().get("phase_frame"), 20, "reload reaches global perfect frame twenty-eight")
	var facts_before_confirm := _coordinator_facts.size()
	var confirmed: Dictionary = coordinator.submit_intent(
		{"id": "weapon_utility", "edge": "pressed", "held_frames": 999},
		{"run_seed": 7056, "aim_direction": Vector2.LEFT, "time_interactions": {}}
	)
	_suite.assert_true(bool(confirmed.get("ok", false)), "coordinator consumes perfect reload confirmation")
	_suite.assert_equal(confirmed.get("token"), reload_token, "perfect reload preserves the original action token")
	_suite.assert_equal(coordinator.phase_name(), &"RECOVERY", "perfect reload atomically replaces the remaining tail")
	_suite.assert_equal(coordinator.presentation_snapshot().get("phase_duration_frames"), 4, "perfect reload adopts four recovery frames")
	_suite.assert_equal(runtime.snapshot().get("ammo"), 7, "coordinator-confirmed perfect reload grants overfill")
	_suite.assert_equal(runtime.snapshot().get("time_load_source"), "perfect_reload", "coordinator-confirmed perfect reload grants free Time Load")
	_suite.assert_equal(_coordinator_facts.size(), facts_before_confirm, "perfect reload confirmation publishes no second committed fact")
	_suite.assert_equal(provider.spend_calls, 0, "free perfect-reload Time Load never spends external Time Energy")
	coordinator.cancel(&"perfect_reload_verified")
	_free_fixture(fixture)


func _test_primary_hold_and_ammo_boundaries() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var hold: Dictionary = runtime.plan_intent(
		_press_intent(&"weapon_primary"),
		_context(7000)
	).get("plan", {})
	_suite.assert_equal(
		hold.get("allowed_release_action_ids"),
		["normal_fire", "aimed_fire"],
		"primary HOLD declares both real release action identities"
	)
	_suite.assert_equal(
		hold.get("release_action_fingerprints"),
		{
			"normal_fire": "gun-launch-v1:normal-fire:v1",
			"aimed_fire": "gun-launch-v1:aimed-fire:v1",
		},
		"primary HOLD freezes both release fingerprints"
	)
	_suite.assert_true(bool(runtime.commit_action(hold, 11).get("ok", false)), "primary HOLD commits on one token")
	var normal_release: Dictionary = runtime.release_hold(hold, 11, 17)
	_suite.assert_true(bool(normal_release.get("ok", false)), "seventeen-frame primary HOLD releases")
	_suite.assert_equal(normal_release.get("finalized_plan", {}).get("action_id"), "normal_fire", "seventeen-frame HOLD publishes normal_fire")
	_suite.assert_equal(normal_release.get("finalized_plan", {}).get("release_action_fingerprint"), "gun-launch-v1:normal-fire:v1", "normal release carries its declared fingerprint")
	_suite.assert_true(not normal_release.get("finalized_plan", {}).has("resolved_action_id"), "normal release uses the real action ID without an alias field")
	runtime.finish_action(11)

	hold = runtime.plan_intent(_press_intent(&"weapon_primary"), _context(70001)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(hold, 12).get("ok", false)), "second primary HOLD commits")
	var aimed_release: Dictionary = runtime.release_hold(hold, 12, 18)
	_suite.assert_true(bool(aimed_release.get("ok", false)), "eighteen-frame primary HOLD releases")
	_suite.assert_equal(aimed_release.get("finalized_plan", {}).get("action_id"), "aimed_fire", "eighteen-frame HOLD publishes aimed_fire")
	_suite.assert_equal(aimed_release.get("finalized_plan", {}).get("release_action_fingerprint"), "gun-launch-v1:aimed-fire:v1", "aimed release carries its declared fingerprint")
	_suite.assert_true(not aimed_release.get("finalized_plan", {}).has("resolved_action_id"), "aimed release uses the real action ID without an alias field")
	runtime.finish_action(12)
	_suite.assert_true(_restore_ammo(runtime, 6), "primary HOLD fixture restores the base magazine")

	var normal: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 17),
		_context(7001)
	).get("plan", {})
	_assert_action(normal, "normal_fire", 3, 1, 8)
	_suite.assert_equal(normal.get("ammo_cost"), 1, "seventeen held frames cost one round")
	_suite.assert_equal(normal.get("cancel_total_frame"), 5, "normal fire opens cancel at total frame five")
	var normal_parameters := _payload_parameters(normal)
	_suite.assert_close(float(normal_parameters.get("damage_multiplier", 0.0)), 1.0, "normal fire uses 1.0x damage")
	_suite.assert_close(float(normal_parameters.get("speed_tiles_per_second", 0.0)), 40.0, "normal fire uses forty-tile speed")
	_suite.assert_close(float(normal_parameters.get("maximum_range_tiles", 0.0)), 15.0, "normal fire uses fifteen-tile range")

	var aimed: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 18),
		_context(7002)
	).get("plan", {})
	_assert_action(aimed, "aimed_fire", 8, 1, 12)
	_suite.assert_equal(aimed.get("ammo_cost"), 1, "eighteen held frames cost one round")
	_suite.assert_equal(aimed.get("cancel_total_frame"), 10, "aimed fire opens cancel at total frame ten")
	var aimed_parameters := _payload_parameters(aimed)
	_suite.assert_close(float(aimed_parameters.get("damage_multiplier", 0.0)), 2.5, "aimed fire uses 2.5x damage")
	_suite.assert_close(float(aimed_parameters.get("critical_chance_bonus", 0.0)), 0.20, "aimed fire gains twenty percent critical chance")
	_suite.assert_equal(aimed_parameters.get("pierce"), 1, "aimed fire pierces one enemy")

	_suite.assert_true(_restore_ammo(runtime, 0), "ammo zero fixture restores")
	var empty_before: Dictionary = runtime.snapshot()
	var empty_primary: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), _context(7003))
	_suite.assert_true(bool(empty_primary.get("ok", false)), "empty primary plans reload instead of a shot")
	_suite.assert_equal(empty_primary.get("plan", {}).get("action_id"), "reload", "empty primary resolves only reload")
	_suite.assert_equal(runtime.snapshot(), empty_before, "empty-primary planning does not mutate ammunition")

	_suite.assert_true(_restore_ammo(runtime, 1), "ammo one fixture restores")
	var one_before: Dictionary = runtime.snapshot()
	var rejected_shotgun: Dictionary = runtime.plan_intent(_press_intent(&"weapon_secondary"), _context(7004))
	_suite.assert_true(not bool(rejected_shotgun.get("ok", false)), "shotgun rejects with one round")
	_suite.assert_equal(rejected_shotgun.get("code"), &"INSUFFICIENT_AMMO", "one-round rejection is typed")
	_suite.assert_equal(runtime.snapshot(), one_before, "rejected shotgun has no ammunition mutation")

	_suite.assert_true(_restore_ammo(runtime, 2), "ammo two fixture restores")
	var shotgun: Dictionary = runtime.plan_intent(_press_intent(&"weapon_secondary"), _context(7005)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(shotgun, 21).get("ok", false)), "shotgun atomically commits at two rounds")
	_suite.assert_equal(runtime.snapshot().get("ammo"), 0, "shotgun atomically consumes two rounds")
	runtime.finish_action(21)

	_suite.assert_true(_restore_ammo(runtime, 6), "base magazine fixture restores")
	normal = runtime.plan_intent(_release_intent(&"weapon_primary", 0), _context(7006)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(normal, 22).get("ok", false)), "normal fire commits from six rounds")
	_suite.assert_equal(runtime.snapshot().get("ammo"), 5, "normal fire consumes one of six rounds")
	runtime.finish_action(22)

	_suite.assert_true(_restore_ammo(runtime, 7), "overfill magazine fixture restores")
	aimed = runtime.plan_intent(_release_intent(&"weapon_primary", 18), _context(7007)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(aimed, 23).get("ok", false)), "aimed fire commits from seven rounds")
	_suite.assert_equal(runtime.snapshot().get("ammo"), 6, "aimed fire consumes one of seven rounds")
	runtime.finish_action(23)
	_free_fixture(fixture)


func _test_shotgun_is_atomic_seeded_and_pellet_scoped() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var gun: FakeGunAdapter = fixture["gun"]
	var plan: Dictionary = runtime.plan_intent(
		_press_intent(&"weapon_secondary"),
		_context(91001)
	).get("plan", {})
	_assert_action(plan, "shotgun_fire", 8, 2, 20)
	_suite.assert_equal(plan.get("ammo_cost"), 2, "shotgun baseline costs two rounds")
	_suite.assert_equal(plan.get("cancel_total_frame"), 14, "shotgun opens cancel at total frame fourteen")
	_suite.assert_true(bool(runtime.commit_action(plan, 31).get("ok", false)), "shotgun stages eight deterministic pellets")
	var descriptors: Array = gun.staged_definition.get("payload_descriptors", [])
	_suite.assert_equal(descriptors.size(), 8, "shotgun materializes eight pellets")
	_suite.assert_close(float(descriptors[0].get("parameters", {}).get("angle_degrees", 0.0)), -45.0, "first pellet begins at minus forty-five degrees")
	_suite.assert_close(float(descriptors[7].get("parameters", {}).get("angle_degrees", 0.0)), 45.0, "last pellet ends at plus forty-five degrees")
	var seeds: Dictionary = {}
	for index: int in range(descriptors.size()):
		var descriptor: Dictionary = descriptors[index]
		_suite.assert_equal(descriptor.get("token"), 31, "pellet %d shares the action token" % index)
		_suite.assert_equal(descriptor.get("outcome_index"), index, "pellet %d owns its outcome index" % index)
		_suite.assert_equal(descriptor.get("target_deduplication"), "per_pellet", "pellet %d deduplicates targets independently" % index)
		seeds[descriptor.get("seed")] = true
	_suite.assert_equal(seeds.size(), 8, "each pellet receives a deterministic unique seed")
	var first_definition := gun.staged_definition.duplicate(true)
	runtime.finish_action(31)
	_suite.assert_true(_restore_ammo(runtime, 6), "shotgun determinism fixture restores ammunition")
	plan = runtime.plan_intent(_press_intent(&"weapon_secondary"), _context(91001)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(plan, 31).get("ok", false)), "same shotgun action can be reconstructed")
	_suite.assert_equal(gun.staged_definition, first_definition, "same run seed and token reproduce the full pellet packet")
	runtime.finish_action(31)

	_suite.assert_true(_restore_ammo(runtime, 2), "construction failure fixture restores two rounds")
	plan = runtime.plan_intent(_press_intent(&"weapon_secondary"), _context(91002)).get("plan", {})
	var before: Dictionary = runtime.snapshot()
	gun.fail_begin = true
	var failed: Dictionary = runtime.commit_action(plan, 32)
	_suite.assert_true(not bool(failed.get("ok", false)), "projectile construction failure rejects the shotgun")
	_suite.assert_equal(failed.get("code"), &"PAYLOAD_CONSTRUCTION_FAILED", "construction failure is typed")
	_suite.assert_equal(runtime.snapshot(), before, "construction failure preserves ammunition and runtime ledgers")
	_free_fixture(fixture)


func _test_reload_half_open_boundaries_and_completion() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	for case: Dictionary in [
		{"frame": 7, "segment": "locked_open", "cancel": false, "perfect": false, "complete": false},
		{"frame": 8, "segment": "dash_cancel", "cancel": true, "perfect": false, "complete": false},
		{"frame": 27, "segment": "dash_cancel", "cancel": true, "perfect": false, "complete": false},
		{"frame": 28, "segment": "perfect", "cancel": true, "perfect": true, "complete": false},
		{"frame": 35, "segment": "perfect", "cancel": true, "perfect": true, "complete": false},
		{"frame": 36, "segment": "dash_cancel", "cancel": true, "perfect": false, "complete": false},
		{"frame": 39, "segment": "dash_cancel", "cancel": true, "perfect": false, "complete": false},
		{"frame": 40, "segment": "locked_complete", "cancel": false, "perfect": false, "complete": false},
		{"frame": 48, "segment": "complete", "cancel": false, "perfect": false, "complete": true},
	]:
		var window: Dictionary = runtime.reload_window(int(case["frame"]))
		_suite.assert_equal(window.get("segment"), case["segment"], "reload frame %d selects the exact half-open segment" % case["frame"])
		_suite.assert_equal(window.get("dash_cancellable"), case["cancel"], "reload frame %d reports dash cancellation exactly" % case["frame"])
		_suite.assert_equal(window.get("perfect_confirm"), case["perfect"], "reload frame %d reports perfect confirmation exactly" % case["frame"])
		_suite.assert_equal(window.get("complete"), case["complete"], "reload frame %d reports completion exactly" % case["frame"])

	_suite.assert_true(_restore_ammo(runtime, 2), "normal reload fixture restores two rounds")
	var reload_plan: Dictionary = runtime.plan_intent(_press_intent(&"weapon_utility"), _context(8001)).get("plan", {})
	_suite.assert_equal(_phase(reload_plan, 0).get("phase"), "WINDUP", "reload starts with WINDUP")
	_suite.assert_equal(_phase(reload_plan, 0).get("duration_frames"), 8, "reload WINDUP lasts eight frames")
	_suite.assert_equal(_phase(reload_plan, 1).get("phase"), "RESOURCE_ACTION", "reload middle segment is RESOURCE_ACTION")
	_suite.assert_equal(_phase(reload_plan, 1).get("duration_frames"), 32, "reload RESOURCE_ACTION lasts thirty-two frames")
	_suite.assert_equal(_phase(reload_plan, 1).get("cancel_from_frame"), 0, "reload RESOURCE_ACTION is Dash-cancellable from its first frame")
	_suite.assert_equal(_phase(reload_plan, 2).get("phase"), "RECOVERY", "reload ends in RECOVERY")
	_suite.assert_equal(_phase(reload_plan, 2).get("duration_frames"), 8, "reload RECOVERY lasts eight frames")
	_suite.assert_true(not _phase(reload_plan, 2).has("cancel_from_frame"), "reload final RECOVERY remains locked")
	_suite.assert_true(bool(runtime.commit_action(reload_plan, 41).get("ok", false)), "normal reload commits")
	runtime.on_phase_enter(reload_plan, &"RESOURCE_ACTION", 41)
	var early: Dictionary = runtime.handle_live_intent(
		reload_plan,
		41,
		&"RESOURCE_ACTION",
		19,
		{"id": "weapon_utility", "edge": "pressed", "held_frames": 999},
		{}
	)
	_suite.assert_true(bool(early.get("ok", false)), "early confirmation is consumed without aborting reload")
	_suite.assert_true(not bool(early.get("context", {}).get("perfect_reload", true)), "frame twenty-seven is not perfect")
	_suite.assert_equal(early.get("context", {}).get("reload_frame"), 27, "early confirmation derives frame twenty-seven from coordinator phase data")
	_suite.assert_true((early.get("replacement_phases", []) as Array).is_empty(), "early confirmation keeps the ordinary reload tail")
	_suite.assert_equal(runtime.snapshot().get("ammo"), 2, "early confirmation grants no partial ammunition")
	_suite.assert_equal(runtime.snapshot().get("active_token"), 41, "early confirmation preserves the active reload token")
	_suite.assert_equal(runtime.snapshot().get("active_phase"), "RESOURCE_ACTION", "early confirmation does not restart the reload")
	runtime.finish_action(41)
	_suite.assert_equal(runtime.snapshot().get("ammo"), 6, "normal reload completion fills to six")

	_suite.assert_true(_restore_ammo(runtime, 1), "cancelled reload fixture restores one round")
	reload_plan = runtime.plan_intent(_press_intent(&"weapon_utility"), _context(8002)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(reload_plan, 42).get("ok", false)), "cancelled reload commits")
	runtime.cancel_action(42, &"dash_cancel")
	_suite.assert_equal(runtime.snapshot().get("ammo"), 1, "cancelled reload preserves current ammunition")

	_suite.assert_true(_restore_ammo(runtime, 0), "empty-primary reload fixture restores zero rounds")
	reload_plan = runtime.plan_intent(_press_intent(&"weapon_primary"), _context(8003)).get("plan", {})
	_suite.assert_equal(reload_plan.get("action_id"), "reload", "empty primary produces the reload action")
	_suite.assert_true(bool(runtime.commit_action(reload_plan, 43).get("ok", false)), "empty-primary reload commits")
	_suite.assert_equal(runtime.snapshot().get("ammo"), 0, "empty-primary reload remains at zero before completion")
	runtime.finish_action(43)
	_suite.assert_equal(runtime.snapshot().get("ammo"), 6, "empty-primary reload fills only on completion")
	_free_fixture(fixture)


func _test_perfect_reload_grants_free_time_load_without_touching_active_cooldown() -> void:
	for boundary: int in [28, 35]:
		var fixture := _fixture()
		var runtime: RefCounted = fixture["runtime"]
		var active_plan: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), _context(8100 + boundary)).get("plan", {})
		_suite.assert_true(bool(runtime.commit_action(active_plan, 50).get("ok", false)), "active Time Load commits before perfect reload boundary %d" % boundary)
		runtime.finish_action(50)
		_advance_runtime_frames(runtime, 60)
		_suite.assert_true(_restore_ammo(runtime, 2), "perfect reload boundary %d restores two rounds" % boundary)
		var reload_plan: Dictionary = runtime.plan_intent(_press_intent(&"weapon_utility"), _context(8200 + boundary)).get("plan", {})
		_suite.assert_true(bool(runtime.commit_action(reload_plan, 51).get("ok", false)), "reload commits at perfect boundary %d" % boundary)
		runtime.on_phase_enter(reload_plan, &"RESOURCE_ACTION", 51)
		var confirmed: Dictionary = runtime.handle_live_intent(
			reload_plan,
			51,
			&"RESOURCE_ACTION",
			boundary - 8,
			_press_intent(&"weapon_utility"),
			{}
		)
		_suite.assert_true(bool(confirmed.get("ok", false)), "perfect boundary %d confirms" % boundary)
		_suite.assert_true(bool(confirmed.get("context", {}).get("perfect_reload", false)), "perfect boundary %d grants the perfect result" % boundary)
		_suite.assert_equal(runtime.snapshot().get("ammo"), 7, "perfect reload fills to seven at frame %d" % boundary)
		_suite.assert_equal(runtime.snapshot().get("time_load_source"), "perfect_reload", "perfect reload grants free Time Load")
		_suite.assert_equal(runtime.snapshot().get("time_load_remaining_frames"), 300, "free Time Load lasts five seconds")
		_suite.assert_true(not runtime.snapshot().has("time_load_cooldown_remaining_frames"), "Time Load cooldown remains coordinator transaction authority")
		_suite.assert_equal(_phase({"phases": confirmed.get("replacement_phases", [])}, 0).get("duration_frames"), 4, "perfect reload transitions to four-frame recovery")
		_suite.assert_close(float(_phase({"phases": confirmed.get("replacement_phases", [])}, 0).get("movement_multiplier", 0.0)), 0.65, "perfect reload preserves reload movement")
		runtime.finish_action(51)
		_free_fixture(fixture)

	var late_fixture := _fixture()
	var late_runtime: RefCounted = late_fixture["runtime"]
	_suite.assert_true(_restore_ammo(late_runtime, 3), "late reload fixture restores three rounds")
	var late_plan: Dictionary = late_runtime.plan_intent(_press_intent(&"weapon_utility"), _context(8301)).get("plan", {})
	_suite.assert_true(bool(late_runtime.commit_action(late_plan, 52).get("ok", false)), "late reload commits")
	late_runtime.on_phase_enter(late_plan, &"RESOURCE_ACTION", 52)
	var late: Dictionary = late_runtime.handle_live_intent(
		late_plan,
		52,
		&"RESOURCE_ACTION",
		28,
		_press_intent(&"weapon_utility"),
		{}
	)
	_suite.assert_true(bool(late.get("ok", false)), "late confirmation is consumed")
	_suite.assert_true(not bool(late.get("context", {}).get("perfect_reload", true)), "frame thirty-six is outside the perfect window")
	_suite.assert_true((late.get("replacement_phases", []) as Array).is_empty(), "late confirmation leaves the ordinary reload tail intact")
	_suite.assert_equal(late_runtime.snapshot().get("ammo"), 3, "late confirmation grants no partial reward")
	_suite.assert_equal(late_runtime.snapshot().get("active_token"), 52, "late confirmation preserves the active reload token")
	_suite.assert_equal(late_runtime.snapshot().get("active_phase"), "RESOURCE_ACTION", "late confirmation does not restart the reload")
	late_runtime.finish_action(52)
	_suite.assert_equal(late_runtime.snapshot().get("ammo"), 6, "late confirmation continues normal reload")
	_free_fixture(late_fixture)

	var rollback_fixture := _fixture()
	var rollback_runtime: RefCounted = rollback_fixture["runtime"]
	_suite.assert_true(_restore_ammo(rollback_runtime, 2), "rollback reload fixture restores two rounds")
	var rollback_plan: Dictionary = rollback_runtime.plan_intent(_press_intent(&"weapon_utility"), _context(8302)).get("plan", {})
	_suite.assert_true(bool(rollback_runtime.commit_action(rollback_plan, 53).get("ok", false)), "rollback reload commits")
	rollback_runtime.on_phase_enter(rollback_plan, &"RESOURCE_ACTION", 53)
	var before_confirm: Dictionary = rollback_runtime.snapshot()
	var proposed: Dictionary = rollback_runtime.handle_live_intent(
		rollback_plan,
		53,
		&"RESOURCE_ACTION",
		20,
		_press_intent(&"weapon_utility"),
		{}
	)
	_suite.assert_true(bool(proposed.get("context", {}).get("perfect_reload", false)), "rollback fixture first proposes a perfect reload")
	_suite.assert_equal(rollback_runtime.snapshot().get("ammo"), 7, "perfect proposal mutates runtime-owned ammunition before coordinator validation")
	_suite.assert_true(rollback_runtime.restore_snapshot(before_confirm), "active reload snapshot can restore after a rejected replacement tail")
	_suite.assert_equal(rollback_runtime.snapshot(), before_confirm, "active reload rollback restores token, phase, ammunition, buff, and adapter state")
	rollback_runtime.cancel_action(53, &"rollback_test_cleanup")
	_free_fixture(rollback_fixture)


func _test_active_time_load_refills_and_accelerates_future_shots() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	_suite.assert_true(_restore_ammo(runtime, 1), "active Time Load fixture restores one round")
	var skill: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), _context(8401)).get("plan", {})
	_assert_action_without_active(skill, "time_load", 8, 4)
	_suite.assert_equal(skill.get("resource_costs"), {"time_energy": 25.0}, "active Time Load costs twenty-five Time Energy")
	_suite.assert_equal(skill.get("cooldown_frames"), 360, "active Time Load owns a six-second cooldown")
	_suite.assert_true(bool(runtime.commit_action(skill, 61).get("ok", false)), "active Time Load commits")
	_suite.assert_equal(runtime.snapshot().get("ammo"), 6, "active Time Load refills to six")
	_suite.assert_equal(runtime.snapshot().get("time_load_source"), "active", "active Time Load records its source")
	_suite.assert_equal(runtime.snapshot().get("time_load_remaining_frames"), 300, "active Time Load lasts three hundred frames")
	runtime.finish_action(61)

	var shot: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 0), _context(8402)).get("plan", {})
	_suite.assert_equal(shot.get("ammo_cost"), 0, "Time Load makes future shots ammunition-free")
	_suite.assert_equal(_phase(shot, 0).get("duration_frames"), 2, "Time Load shortens normal windup by forty percent")
	_suite.assert_equal(_phase(shot, 2).get("duration_frames"), 5, "Time Load shortens normal recovery by forty percent")
	_suite.assert_close(float(_payload_parameters(shot).get("time_damage_ratio", 0.0)), 0.15, "Time Load adds fifteen percent attack as time damage")
	_suite.assert_true(bool(runtime.commit_action(shot, 62).get("ok", false)), "free Time Load shot commits")
	_suite.assert_equal(runtime.snapshot().get("ammo"), 6, "Time Load shot consumes no ammunition")
	runtime.finish_action(62)

	_advance_runtime_frames(runtime, 299)
	_suite.assert_equal(runtime.snapshot().get("time_load_remaining_frames"), 1, "Time Load remains active through frame two hundred ninety-nine")
	_suite.assert_equal(runtime.snapshot().get("time_load_source"), "active", "Time Load source remains active before the final tick")
	_advance_runtime_frames(runtime, 1)
	_suite.assert_equal(runtime.snapshot().get("time_load_remaining_frames"), 0, "Time Load expires after three hundred frames")
	_suite.assert_equal(runtime.snapshot().get("time_load_source"), "", "expired Time Load clears its source")
	var next_skill: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), _context(8403)).get("plan", {})
	_suite.assert_equal(next_skill.get("cooldown_frames"), 360, "future active Time Load exposes cooldown to WeaponResourceTransaction")
	_free_fixture(fixture)


func _test_ultimate_hold_boundary_and_time_load_amplification() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var skeleton: Dictionary = runtime.plan_intent(
		_press_intent(&"weapon_ultimate"),
		_context(8501)
	).get("plan", {})
	_suite.assert_equal(_phase(skeleton, 0).get("phase"), "HOLD", "Void Penetration begins in coordinator-owned HOLD")
	_suite.assert_equal(_phase(skeleton, 0).get("minimum_hold_frames"), 60, "Void Penetration requires sixty held frames")
	_suite.assert_equal(skeleton.get("allowed_release_action_ids"), ["void_penetration"], "Void HOLD declares its one real release identity")
	_suite.assert_equal(skeleton.get("release_action_fingerprints", {}).get("void_penetration"), "gun-launch-v1:void-penetration:v1", "Void HOLD freezes its release fingerprint")
	_suite.assert_true(bool(runtime.commit_action(skeleton, 71).get("ok", false)), "ultimate HOLD commits without constructing a projectile")
	var undercharged: Dictionary = runtime.release_hold(skeleton, 71, 59)
	_suite.assert_true(not bool(undercharged.get("ok", false)), "fifty-nine held frames reject Void Penetration")
	_suite.assert_equal(undercharged.get("code"), &"UNDERCHARGED", "ultimate undercharge is typed")
	_suite.assert_equal(fixture["gun"].begin_count, 0, "undercharged ultimate constructs no projectile")
	runtime.cancel_action(71, &"undercharged")

	skeleton = runtime.plan_intent(_press_intent(&"weapon_ultimate"), _context(8502)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(skeleton, 72).get("ok", false)), "sixty-frame ultimate HOLD commits")
	var released: Dictionary = runtime.release_hold(skeleton, 72, 60)
	_suite.assert_true(bool(released.get("ok", false)), "sixty held frames release Void Penetration")
	var ultimate: Dictionary = released.get("finalized_plan", {})
	_assert_action(ultimate, "void_penetration", 18, 3, 25)
	_suite.assert_equal(ultimate.get("release_action_fingerprint"), "gun-launch-v1:void-penetration:v1", "Void release carries its declared fingerprint")
	_suite.assert_equal(ultimate.get("resource_costs"), {"time_energy": 65.0}, "Void Penetration costs sixty-five Time Energy")
	_suite.assert_equal(ultimate.get("cooldown_frames"), 720, "Void Penetration owns a twelve-second cooldown")
	_suite.assert_true(bool(ultimate.get("invulnerable_during_cast", false)), "Void Penetration is invulnerable during its cast")
	var parameters := _payload_parameters(ultimate)
	_suite.assert_close(float(parameters.get("damage_multiplier", 0.0)), 15.0, "Void Penetration uses 15.0x damage")
	_suite.assert_close(float(parameters.get("void_damage_ratio", 0.0)), 0.60, "Void Penetration is sixty percent void")
	_suite.assert_close(float(parameters.get("time_damage_ratio", 0.0)), 0.40, "Void Penetration is forty percent time")
	_suite.assert_true(bool(parameters.get("unlimited_pierce", false)), "Void Penetration has unlimited pierce")
	_suite.assert_equal(parameters.get("trail_duration_frames"), 300, "Void trail lasts five seconds")
	runtime.finish_action(72)

	var skill: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), _context(8503)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(skill, 73).get("ok", false)), "Time Load commits before amplified ultimate")
	runtime.finish_action(73)
	var amplified: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_ultimate", 60),
		_context(8504)
	).get("plan", {})
	parameters = _payload_parameters(amplified)
	_suite.assert_close(float(parameters.get("damage_multiplier", 0.0)), 19.5, "Time Load multiplies ultimate damage by 1.3")
	_suite.assert_close(float(parameters.get("penetration_explosion", {}).get("radius_tiles", 0.0)), 2.25, "Time Load multiplies penetration explosion radius by 1.5")
	_free_fixture(fixture)


func _test_four_time_interactions_and_chrono_warden_conversion() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var stop_context := _context(8601)
	stop_context["time_interactions"] = {"stop_active": true}
	var aimed: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 18),
		stop_context
	).get("plan", {})
	var stop := _dictionary_by_id(aimed.get("time_interactions", []), "interaction_id", "gun_aimed_time_burst")
	_suite.assert_close(float(stop.get("explosion_radius_tiles", 0.0)), 2.0, "Stop aimed shot creates a two-tile time explosion")
	_suite.assert_close(float(stop.get("explosion_damage_multiplier", 0.0)), 1.0, "Stop aimed shot adds 1.0x attack as time damage")
	_suite.assert_equal(stop.get("stop_extension_frames"), 30, "Stop aimed shot extends one Stop by thirty frames")

	var rewind_context := _context(8602)
	rewind_context["time_interactions"] = {
		"rewind_echo_available": true,
		"rewind_echo_generation": 11,
	}
	var rewind: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 0),
		rewind_context
	).get("plan", {})
	_suite.assert_equal(rewind.get("ammo_cost"), 0, "Rewind makes the next shot ammunition-free")
	_suite.assert_close(float(_payload_parameters(rewind).get("damage_multiplier", 0.0)), 1.5, "Rewind multiplies the next shot damage by 1.5")
	var rewind_descriptor := _dictionary_by_id(rewind.get("time_interactions", []), "interaction_id", "gun_rewind_free_shot")
	_suite.assert_equal(rewind_descriptor.get("rewind_generation"), 11, "Rewind descriptor freezes its generation")
	_suite.assert_true(bool(rewind_descriptor.get("one_shot_claim", false)), "Rewind descriptor is an explicit one-shot claim")
	_suite.assert_true(bool(runtime.commit_action(rewind, 81).get("ok", false)), "generation-safe Rewind shot commits")
	runtime.finish_action(81)
	var claimed: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 0),
		rewind_context
	).get("plan", {})
	_suite.assert_equal(claimed.get("ammo_cost"), 1, "claimed Rewind generation cannot make a second shot free")
	_suite.assert_true(_dictionary_by_id(claimed.get("time_interactions", []), "interaction_id", "gun_rewind_free_shot").is_empty(), "claimed Rewind generation emits no duplicate descriptor")
	runtime.reset_runtime_state(&"rewind_lifecycle_reset")
	var reset_rewind: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 0),
		rewind_context
	).get("plan", {})
	_suite.assert_equal(reset_rewind.get("ammo_cost"), 0, "runtime reset clears the prior Rewind generation claim ledger")
	var conflicting_rewind_context := _context(8605)
	conflicting_rewind_context["time_interactions"] = {
		"rewind_echo_available": true,
		"rewind_shot_available": false,
		"rewind_echo_generation": 12,
		"rewind_generation": 13,
	}
	var conflicting_rewind: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 0),
		conflicting_rewind_context
	)
	_suite.assert_true(not bool(conflicting_rewind.get("ok", false)), "conflicting Rewind aliases fail closed")
	_suite.assert_equal(conflicting_rewind.get("code"), &"INVALID_CONTEXT", "Rewind alias conflicts use the context validation boundary")

	var accelerate_context := _context(8603)
	accelerate_context["time_interactions"] = {"accelerate_active": true}
	var shotgun: Dictionary = runtime.plan_intent(
		_press_intent(&"weapon_secondary"),
		accelerate_context
	).get("plan", {})
	_suite.assert_equal(shotgun.get("ammo_cost"), 1, "Accelerate halves two-round shotgun cost and rounds up")
	_suite.assert_equal(_phase(shotgun, 2).get("duration_frames"), 16, "Accelerate removes four shotgun recovery frames")
	var accelerate := _dictionary_by_id(shotgun.get("time_interactions", []), "interaction_id", "gun_recovery_speed")
	_suite.assert_equal(accelerate.get("recovery_delta_frames"), -4, "Accelerate descriptor freezes the four-frame recovery reduction")

	var rift_context := _context(8604)
	rift_context["time_interactions"] = {"rift_active": true}
	var rift_shot: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 0),
		rift_context
	).get("plan", {})
	var rift := _dictionary_by_id(rift_shot.get("time_interactions", []), "interaction_id", "gun_rift_trail")
	_suite.assert_equal(rift.get("duration_frames"), 90, "Rift projectile trail lasts ninety frames")
	_suite.assert_equal(rift.get("spatial_policy"), "projectile_path_intersection", "Rift trail is spatial rather than a global tick")

	var boss: Dictionary = rift_shot.get("boss_conversion", {})
	_suite.assert_equal(boss.get("target_id"), "chrono_warden", "Gun Boss conversion targets Chrono Warden")
	_suite.assert_equal(boss.get("active_attack_policy"), "preserve_committed", "Gun pressure cannot interrupt a committed Boss attack")
	_suite.assert_equal(boss.get("control_conversion"), "poise_contribution", "unsupported pressure converts to poise")
	_suite.assert_close(float(boss.get("poise_multiplier", 0.0)), 1.1, "Chrono Warden uses the 1.1 poise baseline")
	_free_fixture(fixture)


func _test_snapshot_restore_reset_and_modifier_boundaries() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	_suite.assert_true(not runtime.apply_modifier(&"weapon.pierce", 2.0), "unsupported Gun modifier fails closed")
	_suite.assert_true(runtime.apply_modifier(&"weapon.damage", 1.25), "declared Gun damage modifier applies")
	_suite.assert_true(_restore_ammo(runtime, 4), "snapshot fixture restores four rounds")
	var skill: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), _context(8701)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(skill, 91).get("ok", false)), "snapshot fixture activates Time Load")
	runtime.finish_action(91)
	_advance_runtime_frames(runtime, 37)
	var rewind_context := _context(8702)
	rewind_context["time_interactions"] = {"rewind_shot_available": true, "rewind_generation": 19}
	var rewind: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 0), rewind_context).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(rewind, 92).get("ok", false)), "snapshot fixture claims a Rewind generation")
	runtime.finish_action(92)
	var stable: Dictionary = runtime.snapshot()
	_advance_runtime_frames(runtime, 50)
	_suite.assert_true(_restore_ammo(runtime, 1), "snapshot fixture mutates ammunition before restore")
	_suite.assert_true(runtime.restore_snapshot(stable), "quiescent Gun snapshot restores")
	_suite.assert_equal(runtime.snapshot(), stable, "Gun snapshot round-trips all ammunition, buff, and claim state")

	var hold: Dictionary = runtime.plan_intent(_press_intent(&"weapon_ultimate"), _context(8703)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(hold, 93).get("ok", false)), "ultimate HOLD commits for snapshot")
	var hold_snapshot: Dictionary = runtime.snapshot()
	runtime.cancel_action(93, &"hold_snapshot")
	_suite.assert_true(runtime.restore_snapshot(hold_snapshot), "quiescent ultimate HOLD snapshot restores")
	_suite.assert_equal(runtime.snapshot().get("active_phase"), "HOLD", "restored Gun snapshot returns to HOLD")
	_suite.assert_true(bool(runtime.release_hold(hold, 93, 60).get("ok", false)), "restored HOLD releases on its original token")
	var active: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.restore_snapshot(active), "active constructed projectile snapshot restores")
	_suite.assert_equal(runtime.snapshot(), active, "active Gun snapshot round-trips adapter phase and payload authority")
	runtime.on_phase_enter(active["active_plan"], &"ACTIVE", 93)
	var released: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.restore_snapshot(released), "released ACTIVE Gun snapshot restores")
	_suite.assert_equal(runtime.snapshot(), released, "released ACTIVE Gun snapshot round-trips exactly")
	runtime.on_phase_enter(released["active_plan"], &"RECOVERY", 93)
	var recovery: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.restore_snapshot(recovery), "released RECOVERY Gun snapshot restores")
	_suite.assert_equal(runtime.snapshot(), recovery, "released RECOVERY Gun snapshot round-trips exactly")
	var malformed := recovery.duplicate(true)
	malformed["adapter_snapshot"]["phase_state"] = "prepared"
	_suite.assert_true(not runtime.restore_snapshot(malformed), "Gun runtime rejects adapter phase drift")
	_suite.assert_equal(runtime.snapshot(), recovery, "invalid Gun runtime restore is atomic")
	var extra_field := recovery.duplicate(true)
	extra_field["future_field"] = true
	_suite.assert_true(not runtime.restore_snapshot(extra_field), "unknown Gun runtime snapshot fields fail closed")
	_suite.assert_equal(runtime.snapshot(), recovery, "unknown-field Gun runtime rejection is atomic")
	runtime.cancel_action(93, &"cleanup")

	runtime.reset_runtime_state(&"new_run")
	var reset: Dictionary = runtime.snapshot()
	_suite.assert_equal(reset.get("ammo"), 6, "reset restores the six-round base magazine")
	_suite.assert_equal(reset.get("time_load_source"), "", "reset clears Time Load")
	_suite.assert_equal(reset.get("time_load_remaining_frames"), 0, "reset clears Time Load duration")
	_suite.assert_equal(reset.get("claimed_rewind_generations"), [], "reset clears one-shot Rewind claims")
	_free_fixture(fixture)


func _test_failed_gameplay_rewind_restore_compensates_adapter_and_runtime() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var adapter: FakeGunAdapter = fixture["gun"]
	var target_plan: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 0),
		_context(8801)
	).get("plan", {})
	_suite.assert_true(
		bool(runtime.commit_action(target_plan, 101).get("ok", false)),
		"Gameplay Rewind failure fixture stages one target action"
	)
	var target: Dictionary = runtime.gameplay_rewind_snapshot()
	runtime.cancel_action(101, &"gameplay_rewind_failure_fixture")
	var before: Dictionary = runtime.gameplay_rewind_snapshot()
	adapter.drift_gameplay_rewind_restore_on_calls = [1]
	_suite.assert_true(
		not runtime.restore_gameplay_rewind_snapshot_for_rollback(target),
		"adapter post-restore drift rejects the Gameplay Rewind target"
	)
	_suite.assert_equal(
		adapter.gameplay_rewind_restore_calls,
		2,
		"failed Gameplay Rewind restore compensates the adapter exactly once"
	)
	_suite.assert_equal(
		runtime.gameplay_rewind_snapshot(),
		before,
		"failed Gameplay Rewind restore preserves the exact pre-call runtime and adapter state"
	)
	_free_fixture(fixture)


func _test_real_adapter_gameplay_rewind_preserves_committed_projectile_identity() -> void:
	var fixture := _real_adapter_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var gun: Node = fixture["gun"]
	_suite.assert_true(bool(fixture["configured"]), "real Gun Runtime and adapter fixture configures")
	if not bool(fixture["configured"]):
		runtime.reset_runtime_state(&"real_adapter_fixture_cleanup")
		_free_fixture(fixture)
		await get_tree().process_frame
		return
	var committed_plan: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 0),
		_context(8802)
	).get("plan", {})
	_suite.assert_true(
		bool(runtime.commit_action(committed_plan, 102).get("ok", false)),
		"real Gun Runtime stages the committed projectile fixture"
	)
	runtime.on_phase_enter(committed_plan, &"WINDUP", 102)
	runtime.on_phase_enter(committed_plan, &"ACTIVE", 102)
	await get_tree().process_frame
	var committed_nodes: Array[Node] = gun.owned_projectiles_for_test()
	_suite.assert_equal(committed_nodes.size(), 1, "real Gun adapter owns one committed projectile")
	if committed_nodes.is_empty():
		runtime.reset_runtime_state(&"real_adapter_fixture_cleanup")
		_free_fixture(fixture)
		await get_tree().process_frame
		return
	var committed_projectile := committed_nodes[0]
	var committed_instance_id := committed_projectile.get_instance_id()
	runtime.finish_action(102)

	var prepared_plan: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 0),
		_context(8803)
	).get("plan", {})
	_suite.assert_true(
		bool(runtime.commit_action(prepared_plan, 103).get("ok", false)),
		"real Gun Runtime stages a second action-local projectile"
	)
	_suite.assert_equal(gun.prepared_projectile_count_for_test(), 1, "rollback fixture owns one prepared projectile")
	var before: Dictionary = runtime.gameplay_rewind_snapshot()
	var guard_before: Dictionary = runtime.gameplay_rewind_committed_payload_guard()
	_suite.assert_true(
		runtime.cancel_for_gameplay_rewind(103, &"real_adapter_gameplay_rewind"),
		"real Gun Gameplay Rewind cancel succeeds"
	)
	_suite.assert_equal(gun.prepared_projectile_count_for_test(), 0, "Gameplay Rewind cancel clears only prepared action-local state")
	committed_nodes = gun.owned_projectiles_for_test()
	_suite.assert_true(
		committed_nodes.size() == 1 and committed_nodes[0] == committed_projectile,
		"Gameplay Rewind cancel preserves the identical committed projectile Node"
	)
	_suite.assert_equal(
		runtime.gameplay_rewind_committed_payload_guard(),
		guard_before,
		"Gameplay Rewind cancel preserves committed Gun identity, execution, and claims"
	)
	_suite.assert_true(
		runtime.restore_gameplay_rewind_snapshot_for_rollback(before),
		"real Gun Gameplay Rewind rollback restores action-local state"
	)
	_suite.assert_equal(runtime.gameplay_rewind_snapshot(), before, "real Gun rollback restores exact runtime and adapter bytes")
	_suite.assert_equal(gun.prepared_projectile_count_for_test(), 1, "real Gun rollback recreates the prepared action-local projectile")
	committed_nodes = gun.owned_projectiles_for_test()
	_suite.assert_true(
		committed_nodes.size() == 1
		and committed_nodes[0] == committed_projectile
		and committed_nodes[0].get_instance_id() == committed_instance_id,
		"real Gun rollback never respawns or replaces the committed projectile"
	)
	_suite.assert_equal(
		runtime.gameplay_rewind_committed_payload_guard(),
		guard_before,
		"real Gun rollback preserves the committed payload guard exactly"
	)
	runtime.reset_runtime_state(&"real_adapter_fixture_cleanup")
	_free_fixture(fixture)
	await get_tree().process_frame

func _fixture() -> Dictionary:
	var owner := Node2D.new()
	var gun := FakeGunAdapter.new()
	gun.name = "GunWeapon"
	owner.add_child(gun)
	var definition := _catalog_profile("gun_launch_v1")
	var profile = WeaponRuntimeProfileScript.new()
	var parsed: Dictionary = profile.configure(definition)
	var modifiers = WeaponModifierStateScript.new()
	var capabilities := PackedStringArray(definition.get("capabilities", []))
	var configured_modifiers := modifiers.configure(capabilities, _modifier_bounds(capabilities))
	var runtime = GunWeaponRuntimeScript.new()
	var configured: bool = bool(parsed.get("ok", false)) and configured_modifiers and runtime.configure(owner, profile, modifiers)
	return {
		"owner": owner,
		"gun": gun,
		"profile": profile,
		"modifiers": modifiers,
		"runtime": runtime,
		"configured": configured,
	}


func _real_adapter_fixture() -> Dictionary:
	var owner := Node2D.new()
	owner.name = "RealGunRuntimeOwner"
	add_child(owner)
	var health = HealthComponentScript.new()
	health.name = "HealthComponent"
	health.max_hp = 100.0
	owner.add_child(health)
	var gun = GunWeaponScript.new()
	gun.name = "GunWeapon"
	gun.owner_path = NodePath("..")
	owner.add_child(gun)
	var definition := _catalog_profile("gun_launch_v1")
	var profile = WeaponRuntimeProfileScript.new()
	var parsed: Dictionary = profile.configure(definition)
	var modifiers = WeaponModifierStateScript.new()
	var capabilities := PackedStringArray(definition.get("capabilities", []))
	var configured_modifiers := modifiers.configure(capabilities, _modifier_bounds(capabilities))
	var runtime = GunWeaponRuntimeScript.new()
	var configured := bool(parsed.get("ok", false)) and configured_modifiers and runtime.configure(owner, profile, modifiers)
	return {
		"owner": owner,
		"gun": gun,
		"health": health,
		"profile": profile,
		"modifiers": modifiers,
		"runtime": runtime,
		"configured": configured,
	}


func _coordinator_fixture() -> Dictionary:
	_coordinator_facts.clear()
	var fixture := _fixture()
	var provider := FakeTimeEnergyProvider.new()
	var resource_transaction = WeaponResourceTransactionScript.new()
	_suite.assert_true(
		resource_transaction.configure(
			&"gun",
			PackedStringArray(["ammo"]),
			{&"time_energy": provider}
		),
		"Gun coordinator resource transaction fixture configures"
	)
	var coordinator = WeaponActionCoordinatorScript.new()
	_suite.assert_true(
		coordinator.configure(fixture["runtime"], resource_transaction),
		"Gun coordinator accepts the real runtime"
	)
	coordinator.weapon_action_committed.connect(_on_gun_action_committed)
	fixture["provider"] = provider
	fixture["resource_transaction"] = resource_transaction
	fixture["coordinator"] = coordinator
	return fixture


func _free_fixture(fixture: Dictionary) -> void:
	var owner: Node = fixture.get("owner")
	if owner != null and is_instance_valid(owner):
		owner.free()


func _restore_ammo(runtime: RefCounted, ammo: int) -> bool:
	var value: Dictionary = runtime.snapshot()
	value["ammo"] = ammo
	return bool(runtime.restore_snapshot(value))


func _advance_runtime_frames(runtime: RefCounted, frame_count: int) -> void:
	var first_frame := int(runtime.snapshot().get("last_runtime_frame", -1)) + 1
	for offset: int in range(frame_count):
		runtime.advance_runtime_frame(first_frame + offset)


func _advance_coordinator(coordinator: RefCounted, frame_count: int) -> void:
	for _frame: int in range(frame_count):
		coordinator.advance_frame()


func _on_gun_action_committed(
	weapon_id: StringName,
	action_id: StringName,
	token: int,
	context: Dictionary
) -> void:
	_coordinator_facts.append({
		"weapon_id": str(weapon_id),
		"action_id": str(action_id),
		"token": token,
		"context": context.duplicate(true),
	})


func _assert_profile_rejected(owner: Node, modifiers: RefCounted, definition: Dictionary, label: String) -> void:
	var profile = WeaponRuntimeProfileScript.new()
	var parsed: Dictionary = profile.configure(definition)
	_suite.assert_true(bool(parsed.get("ok", false)), "%s remains parser-valid" % label)
	var runtime = GunWeaponRuntimeScript.new()
	_suite.assert_true(not runtime.configure(owner, profile, modifiers), "runtime rejects parser-valid %s drift" % label)


func _assert_action(plan: Dictionary, action_id: String, windup: int, active: int, recovery: int) -> void:
	_suite.assert_equal(plan.get("action_id"), action_id, "%s resolves exact action identity" % action_id)
	_suite.assert_equal(_phase(plan, 0).get("phase"), "WINDUP", "%s starts in WINDUP" % action_id)
	_suite.assert_equal(_phase(plan, 0).get("duration_frames"), windup, "%s freezes windup frames" % action_id)
	_suite.assert_equal(_phase(plan, 1).get("phase"), "ACTIVE", "%s enters ACTIVE" % action_id)
	_suite.assert_equal(_phase(plan, 1).get("duration_frames"), active, "%s freezes active frames" % action_id)
	_suite.assert_equal(_phase(plan, 2).get("phase"), "RECOVERY", "%s enters RECOVERY" % action_id)
	_suite.assert_equal(_phase(plan, 2).get("duration_frames"), recovery, "%s freezes recovery frames" % action_id)


func _assert_action_without_active(plan: Dictionary, action_id: String, windup: int, recovery: int) -> void:
	_suite.assert_equal(plan.get("action_id"), action_id, "%s resolves exact action identity" % action_id)
	_suite.assert_equal(_phase(plan, 0).get("phase"), "WINDUP", "%s starts in WINDUP" % action_id)
	_suite.assert_equal(_phase(plan, 0).get("duration_frames"), windup, "%s freezes windup frames" % action_id)
	_suite.assert_equal(_phase(plan, 1).get("phase"), "RECOVERY", "%s omits a synthetic active phase" % action_id)
	_suite.assert_equal(_phase(plan, 1).get("duration_frames"), recovery, "%s freezes recovery frames" % action_id)


func _phase(plan: Dictionary, index: int) -> Dictionary:
	var phases_value: Variant = plan.get("phases", [])
	if not phases_value is Array or index < 0 or index >= (phases_value as Array).size():
		return {}
	var value: Variant = (phases_value as Array)[index]
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _payload_parameters(plan: Dictionary) -> Dictionary:
	var payloads_value: Variant = plan.get("payloads", [])
	if not payloads_value is Array or (payloads_value as Array).is_empty():
		return {}
	var payload_value: Variant = (payloads_value as Array)[0]
	if not payload_value is Dictionary:
		return {}
	var parameters_value: Variant = (payload_value as Dictionary).get("parameters", {})
	return (parameters_value as Dictionary).duplicate(true) if parameters_value is Dictionary else {}


func _assert_character_stats(
	plan: Dictionary,
	parameters: Dictionary,
	attack_scale: float,
	attack_speed: float,
	crit_chance: float,
	crit_multiplier: float,
	label: String
) -> void:
	for source: Dictionary in [plan, parameters]:
		if source.is_empty():
			continue
		_suite.assert_close(float(source.get("character_attack_scale", 0.0)), attack_scale, "%s freezes character attack scale" % label)
		_suite.assert_close(float(source.get("attack_speed", 0.0)), attack_speed, "%s freezes attack speed" % label)
		_suite.assert_close(float(source.get("crit_chance", -1.0)), crit_chance, "%s freezes critical chance" % label)
		_suite.assert_close(float(source.get("crit_multiplier", 0.0)), crit_multiplier, "%s freezes critical multiplier" % label)


func _press_intent(intent_id: StringName) -> Dictionary:
	return {"id": str(intent_id), "edge": "pressed"}


func _release_intent(intent_id: StringName, held_frames: int) -> Dictionary:
	return {"id": str(intent_id), "edge": "released", "held_frames": held_frames}


func _context(run_seed: int) -> Dictionary:
	return {
		"run_seed": run_seed,
		"aim_direction": Vector2.RIGHT,
		"time_interactions": {},
	}


func _dictionary_by_id(values: Variant, id_field: String, expected_id: String) -> Dictionary:
	if not values is Array:
		return {}
	for value: Variant in values as Array:
		if value is Dictionary and str((value as Dictionary).get(id_field, "")) == expected_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _dictionary_ref_by_id(values: Variant, id_field: String, expected_id: String) -> Dictionary:
	if not values is Array:
		return {}
	for value: Variant in values as Array:
		if value is Dictionary and str((value as Dictionary).get(id_field, "")) == expected_id:
			return value as Dictionary
	return {}


func _catalog_profile(profile_id: String) -> Dictionary:
	var file := FileAccess.open(PROFILE_CATALOG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return {}
	return _dictionary_by_id(parsed, "id", profile_id)


func _sorted_strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is PackedStringArray or values is Array:
		for value: Variant in values:
			result.append(str(value))
	result.sort()
	return result


func _modifier_bounds(capabilities: PackedStringArray) -> Dictionary:
	var bounds: Dictionary = {}
	for capability: String in capabilities:
		bounds[capability] = {"minimum": 0.1, "maximum": 10.0}
	return bounds
