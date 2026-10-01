extends Node

const GauntletsWeaponRuntimeScript := preload(
	"res://scripts/combat/weapons/gauntlets_weapon_runtime.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponModifierStateScript := preload(
	"res://scripts/combat/weapons/weapon_modifier_state.gd"
)
const WeaponRuntimeProfileScript := preload(
	"res://scripts/combat/weapons/weapon_runtime_profile.gd"
)

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"


class FakeGauntletsAdapter extends Node2D:
	var base_attack: float = 6.0
	var attack_speed: float = 1.0
	var character_attack_scale: float = 1.0
	var crit_chance: float = 0.05
	var crit_multiplier: float = 1.5
	var begin_count: int = 0
	var release_count: int = 0
	var cancel_count: int = 0
	var finish_count: int = 0
	var reset_count: int = 0
	var fail_begin: bool = false
	var corrupt_begin: bool = false
	var begin_outcomes: Array[StringName] = []
	var aura_outcomes: Array[bool] = []
	var aura_set_count: int = 0
	var aura_source_generation: int = 0
	var staged_definition: Dictionary = {}
	var released_definition: Dictionary = {}
	var result_sink: RefCounted
	var _active: bool = false
	var _released: bool = false


	func configure_result_sink(value: RefCounted) -> bool:
		result_sink = value
		return true


	func begin_profile_action(definition: Dictionary) -> Dictionary:
		begin_count += 1
		var outcome: StringName = begin_outcomes.pop_front() if not begin_outcomes.is_empty() else &"success"
		if fail_begin or outcome == &"fail":
			return {}
		staged_definition = definition.duplicate(true)
		_active = true
		_released = false
		var result := staged_definition.duplicate(true)
		if corrupt_begin or outcome == &"corrupt":
			result["action_id"] = "corrupt_action"
		return result


	func set_combo_slow_aura(active: bool, source_generation: int) -> bool:
		aura_set_count += 1
		if not aura_outcomes.is_empty() and not bool(aura_outcomes.pop_front()):
			return false
		if active:
			if source_generation <= 0:
				return false
			aura_source_generation = source_generation
			return true
		if (
			source_generation > 0
			and aura_source_generation > 0
			and aura_source_generation != source_generation
		):
			return false
		aura_source_generation = 0
		return true


	func release_profile_action() -> bool:
		if not _active or _released:
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
		aura_source_generation = 0


	func cancel_for_gameplay_rewind() -> bool:
		_clear_action()
		return true


	func restore_gameplay_rewind_snapshot_for_rollback(value: Dictionary) -> bool:
		if (
			not value.get("profile_action") is Dictionary
			or typeof(value.get("profile_action_released")) != TYPE_BOOL
			or not value.get("prepared_payloads") is Array
			or value.get("committed_payload_guard") != gameplay_rewind_committed_payload_guard()
		):
			return false
		var definition := value["profile_action"] as Dictionary
		staged_definition = definition.duplicate(true)
		_active = not definition.is_empty()
		_released = bool(value["profile_action_released"])
		released_definition = staged_definition.duplicate(true) if _released else {}
		return true


	func gameplay_rewind_committed_payload_guard() -> Dictionary:
		return {}


	func runtime_snapshot() -> Dictionary:
		return {
			"schema_version": 1,
			"profile_action": staged_definition.duplicate(true) if _active else {},
			"profile_action_released": _released,
		}


	func can_restore_runtime_snapshot(value: Dictionary) -> bool:
		if (
			int(value.get("schema_version", -1)) != 1
			or not value.get("profile_action") is Dictionary
			or typeof(value.get("profile_action_released")) != TYPE_BOOL
		):
			return false
		var definition := value["profile_action"] as Dictionary
		return not (definition.is_empty() and bool(value["profile_action_released"]))


	func restore_runtime_snapshot(value: Dictionary) -> bool:
		if not can_restore_runtime_snapshot(value):
			return false
		var definition := value["profile_action"] as Dictionary
		if definition.is_empty():
			_clear_action()
			return runtime_snapshot() == value
		var outcome: StringName = begin_outcomes.pop_front() if not begin_outcomes.is_empty() else &"success"
		if fail_begin or outcome == &"fail":
			return false
		staged_definition = definition.duplicate(true)
		_active = true
		_released = bool(value["profile_action_released"])
		released_definition = staged_definition.duplicate(true) if _released else {}
		if corrupt_begin or outcome == &"corrupt":
			staged_definition["action_id"] = "corrupt_action"
		return runtime_snapshot() == value


	func _clear_action() -> void:
		_active = false
		_released = false
		staged_definition.clear()
		released_definition.clear()


class FakeGauntletsOwner extends Node2D:
	var stop_extension_calls: Array[Dictionary] = []


	func extend_weapon_time_stop_for_payload_result(
		action_token: int,
		payload_generation: int,
		extension_frames: int
	) -> bool:
		if (
			action_token <= 0
			or payload_generation != action_token
			or extension_frames <= 0
		):
			return false
		stop_extension_calls.append({
			"action_token": action_token,
			"payload_generation": payload_generation,
			"extension_frames": extension_frames,
		})
		return true


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_character_stats_freeze_across_hold_release()
	_test_authoritative_profile_is_frozen()
	_test_five_punches_have_exact_frames_and_damage()
	_test_chain_combo_dedup_damage_and_dash_semantics()
	_test_heavy_counter_skill_and_ultimate_boundaries()
	_test_tier_snapshots_affect_future_actions_only()
	_test_stop_accelerate_rewind_and_rift_interactions()
	_test_rift_near_far_materialization_and_capabilities()
	_test_rift_generation_ownership_fails_closed()
	_test_echo_is_non_recursive()
	_test_replay_payload_transition_projector()
	_test_mid_action_restore_fails_closed_without_side_effects()
	_test_snapshot_aura_invariants_and_restore_atomicity()
	_test_adapter_restore_rollback_and_safe_reset()
	_test_ready_snapshot_tombstones_completed_actions()
	_test_snapshot_reset_determinism_and_bounded_ledgers()
	_suite.finish(get_tree())


func _test_character_stats_freeze_across_hold_release() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var adapter: FakeGauntletsAdapter = fixture["adapter"]
	adapter.base_attack = 5.4
	adapter.attack_speed = 0.9
	adapter.character_attack_scale = 0.9
	adapter.crit_chance = 0.04
	adapter.crit_multiplier = 1.6
	var hold: Dictionary = runtime.plan_intent(
		_press_intent(&"weapon_primary"),
		_context(93001)
	).get("plan", {})
	_assert_character_stats(hold, {}, 0.9, 0.9, 0.04, 1.6, "Gauntlets hold")
	_suite.assert_true(bool(runtime.commit_action(hold, 93001).get("ok", false)), "Gauntlets character-stat hold commits")
	adapter.base_attack = 999.0
	adapter.attack_speed = 4.0
	adapter.character_attack_scale = 4.0
	adapter.crit_chance = 1.0
	adapter.crit_multiplier = 9.0
	var updated_context := _context(93002)
	updated_context["aim_direction"] = Vector2.UP
	updated_context["time_interactions"] = {
		"accelerate_active": true,
		"accelerate_generation": 93002,
	}
	_suite.assert_true(
		runtime.update_hold_context(hold, 93001, updated_context),
		"Gauntlets HOLD context updates without replacing frozen character stats"
	)
	var released: Dictionary = runtime.release_hold(hold, 93001, 0)
	_suite.assert_true(bool(released.get("ok", false)), "Gauntlets character-stat hold releases")
	var finalized: Dictionary = released.get("finalized_plan", {})
	var parameters := _payload_parameters(finalized)
	_assert_character_stats(finalized, parameters, 0.9, 0.9, 0.04, 1.6, "Gauntlets finalized payload")
	_suite.assert_equal(finalized.get("aim_direction_snapshot"), Vector2.UP, "Gauntlets HOLD update keeps the latest aim direction")
	_suite.assert_equal(
		(finalized.get("frozen_context", {}) as Dictionary).get("time_interactions", {}).get("accelerate_generation"),
		93002,
		"Gauntlets HOLD update keeps the latest time context"
	)
	_suite.assert_close(float(adapter.staged_definition.get("base_attack", 0.0)), 5.4, "Gauntlets committed definition keeps the scaled base attack")
	_suite.assert_close(float(adapter.staged_definition.get("character_attack_scale", 0.0)), 0.9, "Gauntlets committed definition freezes character attack scale")
	_suite.assert_close(float(adapter.staged_definition.get("crit_chance", -1.0)), 0.04, "Gauntlets committed definition freezes critical chance")
	_suite.assert_close(float(adapter.staged_definition.get("crit_multiplier", 0.0)), 1.6, "Gauntlets committed definition freezes critical multiplier")
	_free_fixture(fixture)


func _test_authoritative_profile_is_frozen() -> void:
	var fixture := _fixture()
	_suite.assert_true(bool(fixture.get("configured", false)), "authoritative gauntlets_launch_v1 configures")
	var runtime: RefCounted = fixture["runtime"]
	_suite.assert_equal(
		_sorted_strings(runtime.capabilities()),
		["weapon.attack_speed", "weapon.combo_timeout", "weapon.damage", "weapon.status_duration"],
		"Gauntlets exposes only frozen capabilities"
	)
	_suite.assert_equal(fixture["adapter"].result_sink, runtime, "adapter receives the authoritative result sink")
	var drift := _catalog_profile("gauntlets_launch_v1")
	(_dictionary_ref_by_id(drift["payloads"], "payload_id", "gauntlets_punch_1")["parameters"] as Dictionary)["damage_multiplier"] = 0.81
	var profile = WeaponRuntimeProfileScript.new()
	_suite.assert_true(bool(profile.configure(drift).get("ok", false)), "numeric drift remains schema-valid")
	var rejected = GauntletsWeaponRuntimeScript.new()
	_suite.assert_true(not rejected.configure(fixture["owner"], profile, fixture["modifiers"]), "runtime rejects profile drift fail-closed")
	var metadata_drift := _catalog_profile("gauntlets_launch_v1")
	_dictionary_ref_by_id(metadata_drift["actions"], "action_id", "punch_1")["movement_multiplier"] = 0.71
	var metadata_profile = WeaponRuntimeProfileScript.new()
	_suite.assert_true(bool(metadata_profile.configure(metadata_drift).get("ok", false)), "metadata drift remains schema-valid")
	var metadata_rejected = GauntletsWeaponRuntimeScript.new()
	_suite.assert_true(not metadata_rejected.configure(fixture["owner"], metadata_profile, fixture["modifiers"]), "full-profile fingerprint rejects non-numeric gameplay drift")
	_free_fixture(fixture)


func _test_rift_near_far_materialization_and_capabilities() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	_grant_combo(runtime, 30, 1400)
	var near_context := _context(6401)
	near_context["time_interactions"] = {
		"rift_active": true,
		"rift_generation": 101,
		"active_rifts": [{"generation": 101, "center": Vector2(160.0, 0.0), "radius": 8.0}],
	}
	var near_skill: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), near_context).get("plan", {})
	_suite.assert_close(float(near_skill.get("resource_costs", {}).get("time_energy", 0.0)), 14.0, "intersecting Rift reduces high-Combo skill cost")
	_suite.assert_equal((_interaction(near_skill, "rift").get("active_rifts", []) as Array).size(), 1, "intersecting Rift alone is frozen")
	var near_zone := (_payload_parameters(near_skill).get("zone", {}) as Dictionary)
	_suite.assert_close(float(near_zone.get("radius_tiles", 0.0)), 3.75, "Rift multiplier reaches the real Shatter zone radius")
	_suite.assert_equal(near_zone.get("duration_frames"), 450, "Rift multiplier reaches the real Shatter zone duration")

	var far_context := _context(6402)
	far_context["time_interactions"] = {
		"rift_active": true,
		"rift_generation": 102,
		"active_rifts": [{"generation": 102, "center": Vector2(1000.0, 0.0), "radius": 8.0}],
	}
	var far_skill: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), far_context).get("plan", {})
	_suite.assert_close(float(far_skill.get("resource_costs", {}).get("time_energy", 0.0)), 20.0, "non-intersecting Rift cannot reduce cost")
	_suite.assert_true(_interaction(far_skill, "rift").is_empty(), "non-intersecting Rift cannot materialize an effect descriptor")
	var far_zone := (_payload_parameters(far_skill).get("zone", {}) as Dictionary)
	_suite.assert_close(float(far_zone.get("radius_tiles", 0.0)), 2.5, "far Rift leaves the high-Combo zone radius unchanged")
	_suite.assert_equal(far_zone.get("duration_frames"), 300, "far Rift leaves the high-Combo zone duration unchanged")
	var malformed_context := _context(6405)
	malformed_context["time_interactions"] = {
		"rift_active": true,
		"rift_generation": 103,
		"active_rifts": [
			{"generation": 103, "center": Vector2.ZERO, "radius": 8.0},
			{"generation": 103, "center": Vector2.ONE, "radius": 8.0},
		],
	}
	_suite.assert_equal(runtime.plan_intent(_press_intent(&"weapon_skill"), malformed_context).get("code"), &"INVALID_CONTEXT", "duplicate Rift generation fails closed")

	_suite.assert_true(runtime.apply_modifier(&"weapon.combo_timeout", 2.0), "declared Combo timeout capability applies")
	var combo_plan := _primary_plan(runtime, _context(6403))
	_suite.assert_true(bool(runtime.commit_action(combo_plan, 1500).get("ok", false)), "modified Combo action commits")
	runtime.handle_payload_result(1500, 1500, {"target_id": 6403, "outcome_id": "capability:combo", "damage": 1.0, "hit_confirmed": true})
	var combo_snapshot: Dictionary = runtime.snapshot().get("combo_state", {})
	_suite.assert_equal(combo_snapshot.get("combo_timeout_frames_remaining"), 240, "Combo timeout capability changes the authoritative timer")
	_suite.assert_equal(combo_snapshot.get("combo_timeout_cap_frames"), 240, "snapshot freezes the authoritative timeout cap")
	runtime.finish_action(1500)
	_suite.assert_true(runtime.apply_modifier(&"weapon.status_duration", 2.0), "declared status duration capability applies")
	var duration_skill: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), _context(6404)).get("plan", {})
	_suite.assert_equal((_payload_parameters(duration_skill).get("zone", {}) as Dictionary).get("duration_frames"), 600, "status duration capability changes the real high-Combo zone")
	_free_fixture(fixture)


func _test_rift_generation_ownership_fails_closed() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	_grant_combo(runtime, 30, 1450)
	var invalid_cases: Array[Dictionary] = [
		{
			"label": "missing Rift generation",
			"time_interactions": {
				"rift_active": true,
				"active_rifts": [{"generation": 111, "center": Vector2(96.0, 0.0), "radius": 8.0}],
			},
		},
		{
			"label": "zero Rift generation",
			"time_interactions": {
				"rift_active": true,
				"rift_generation": 0,
				"active_rifts": [{"generation": 112, "center": Vector2(96.0, 0.0), "radius": 8.0}],
			},
		},
		{
			"label": "mismatched Rift generation",
			"time_interactions": {
				"rift_active": true,
				"rift_generation": 113,
				"active_rifts": [{"generation": 114, "center": Vector2(96.0, 0.0), "radius": 8.0}],
			},
		},
	]
	for index: int in range(invalid_cases.size()):
		var context := _context(6450 + index)
		context["time_interactions"] = invalid_cases[index]["time_interactions"]
		var rejected: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), context)
		_suite.assert_equal(
			rejected.get("code"),
			&"INVALID_CONTEXT",
			"%s fails closed before Rift benefits materialize" % str(invalid_cases[index]["label"])
		)

	var mixed_context := _context(6453)
	mixed_context["time_interactions"] = {
		"rift_active": true,
		"rift_generation": 115,
		"active_rifts": [
			{"generation": 115, "center": Vector2(1000.0, 0.0), "radius": 8.0},
			{"generation": 116, "center": Vector2(96.0, 0.0), "radius": 8.0},
		],
	}
	var mixed_skill: Dictionary = runtime.plan_intent(
		_press_intent(&"weapon_skill"), mixed_context
	).get("plan", {})
	_suite.assert_close(
		float(mixed_skill.get("resource_costs", {}).get("time_energy", 0.0)),
		20.0,
		"a nearby foreign Rift generation cannot grant the authorized source's cost reduction"
	)
	_suite.assert_true(
		_interaction(mixed_skill, "rift").is_empty(),
		"a nearby foreign Rift generation cannot materialize the authorized source's enhancement"
	)
	var mixed_zone := (_payload_parameters(mixed_skill).get("zone", {}) as Dictionary)
	_suite.assert_close(
		float(mixed_zone.get("radius_tiles", 0.0)),
		2.5,
		"a nearby foreign Rift generation leaves zone radius unchanged"
	)
	_suite.assert_equal(
		mixed_zone.get("duration_frames"),
		300,
		"a nearby foreign Rift generation leaves zone duration unchanged"
	)
	_free_fixture(fixture)


func _test_mid_action_restore_fails_closed_without_side_effects() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var adapter: FakeGauntletsAdapter = fixture["adapter"]
	var plan := _primary_plan(runtime, _context(7501))
	_suite.assert_true(bool(runtime.commit_action(plan, 1750).get("ok", false)), "restore fixture stages WINDUP")
	var windup_snapshot: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.restore_snapshot(windup_snapshot), "staged WINDUP snapshot remains safely reconstructable")
	_suite.assert_equal(runtime.snapshot(), windup_snapshot, "WINDUP restore is deterministic")
	var staged_before_malformed := adapter.staged_definition.duplicate(true)
	var malformed_windup := windup_snapshot.duplicate(true)
	var malformed_definition := (malformed_windup["committed_definition"] as Dictionary).duplicate(true)
	var malformed_descriptors := (malformed_definition["payload_descriptors"] as Array).duplicate(true)
	(malformed_descriptors[0] as Dictionary)["kind"] = "invalid_kind"
	malformed_definition["payload_descriptors"] = malformed_descriptors
	malformed_windup["committed_definition"] = malformed_definition
	var cancel_before_malformed := adapter.cancel_count
	_suite.assert_true(
		not runtime.restore_snapshot(malformed_windup),
		"malformed WINDUP definition is rejected before Adapter mutation"
	)
	_suite.assert_equal(runtime.snapshot(), windup_snapshot, "malformed WINDUP rejection preserves Runtime state")
	_suite.assert_equal(adapter.staged_definition, staged_before_malformed, "malformed WINDUP rejection preserves staged payload")
	_suite.assert_equal(adapter.cancel_count, cancel_before_malformed, "malformed WINDUP rejection never cancels the live Adapter")
	var invalid_identity_cases: Array[Dictionary] = []
	var wrong_generation := windup_snapshot.duplicate(true)
	var wrong_generation_definition := (wrong_generation["committed_definition"] as Dictionary).duplicate(true)
	wrong_generation_definition["generation"] = 1751
	var wrong_generation_descriptors := (wrong_generation_definition["payload_descriptors"] as Array).duplicate(true)
	(wrong_generation_descriptors[0] as Dictionary)["generation"] = 1751
	wrong_generation_definition["payload_descriptors"] = wrong_generation_descriptors
	wrong_generation["committed_definition"] = wrong_generation_definition
	invalid_identity_cases.append({"label": "definition generation drift", "snapshot": wrong_generation})
	var missing_ledger := windup_snapshot.duplicate(true)
	(missing_ledger["action_ledgers"] as Dictionary).erase("1750")
	invalid_identity_cases.append({"label": "missing active ledger", "snapshot": missing_ledger})
	var wrong_ledger_generation := windup_snapshot.duplicate(true)
	var wrong_ledger := ((wrong_ledger_generation["action_ledgers"] as Dictionary)["1750"] as Dictionary).duplicate(true)
	wrong_ledger["generation"] = 1751
	(wrong_ledger_generation["action_ledgers"] as Dictionary)["1750"] = wrong_ledger
	invalid_identity_cases.append({"label": "active ledger generation drift", "snapshot": wrong_ledger_generation})
	var stale_token := windup_snapshot.duplicate(true)
	stale_token["action_token_floor"] = 1750
	invalid_identity_cases.append({"label": "stale active token", "snapshot": stale_token})
	for mirrored_field: String in ["chain_step", "combo_count", "combo_remaining_frames"]:
		var mirrored_drift := windup_snapshot.duplicate(true)
		mirrored_drift[mirrored_field] = int(mirrored_drift[mirrored_field]) + 1
		invalid_identity_cases.append({
			"label": "%s mirror drift" % mirrored_field,
			"snapshot": mirrored_drift,
		})
	var canonical_ledger := ((windup_snapshot["action_ledgers"] as Dictionary)["1750"] as Dictionary).duplicate(true)
	var corrupt_tier := (canonical_ledger["combo_tier_snapshot"] as Dictionary).duplicate(true)
	corrupt_tier["tier_id"] = "corrupt_tier"
	var ledger_tamper_cases: Array[Dictionary] = [
		{"label": "ledger action drift", "field": "action_id", "value": "punch_5"},
		{"label": "ledger Combo gain drift", "field": "combo_gain", "value": int(canonical_ledger["combo_gain"]) + 1},
		{"label": "ledger Combo eligibility drift", "field": "combo_eligible", "value": not bool(canonical_ledger["combo_eligible"])},
		{"label": "ledger Energy eligibility drift", "field": "energy_eligible", "value": not bool(canonical_ledger["energy_eligible"])},
		{"label": "ledger Stop eligibility drift", "field": "stop_extension_eligible", "value": not bool(canonical_ledger["stop_extension_eligible"])},
		{"label": "ledger Stop generation drift", "field": "stop_generation", "value": int(canonical_ledger["stop_generation"]) + 1},
		{"label": "ledger Accelerate eligibility drift", "field": "accelerate_eligible", "value": not bool(canonical_ledger["accelerate_eligible"])},
		{"label": "ledger Accelerate generation drift", "field": "accelerate_generation", "value": int(canonical_ledger["accelerate_generation"]) + 1},
		{"label": "ledger damage drift", "field": "damage_multiplier", "value": float(canonical_ledger["damage_multiplier"]) + 0.01},
		{"label": "ledger Combo timeout drift", "field": "combo_timeout_frames", "value": int(canonical_ledger["combo_timeout_frames"]) + 1},
		{"label": "ledger tier drift", "field": "combo_tier_snapshot", "value": corrupt_tier},
		{"label": "ledger seed drift", "field": "run_seed", "value": int(canonical_ledger["run_seed"]) + 1},
		{"label": "ledger payload drift", "field": "payload_id", "value": "corrupt_payload"},
	]
	for tamper_case: Dictionary in ledger_tamper_cases:
		var tampered_snapshot := windup_snapshot.duplicate(true)
		var tampered_ledger := canonical_ledger.duplicate(true)
		tampered_ledger[str(tamper_case["field"])] = tamper_case["value"]
		(tampered_snapshot["action_ledgers"] as Dictionary)["1750"] = tampered_ledger
		invalid_identity_cases.append({"label": tamper_case["label"], "snapshot": tampered_snapshot})
	var missing_ledger_field := windup_snapshot.duplicate(true)
	var incomplete_ledger := canonical_ledger.duplicate(true)
	incomplete_ledger.erase("combo_gain")
	(missing_ledger_field["action_ledgers"] as Dictionary)["1750"] = incomplete_ledger
	invalid_identity_cases.append({"label": "missing ledger field", "snapshot": missing_ledger_field})
	var unexpected_ledger_field := windup_snapshot.duplicate(true)
	var expanded_ledger := canonical_ledger.duplicate(true)
	expanded_ledger["unexpected_authority"] = true
	(unexpected_ledger_field["action_ledgers"] as Dictionary)["1750"] = expanded_ledger
	invalid_identity_cases.append({"label": "unexpected ledger field", "snapshot": unexpected_ledger_field})
	for invalid_case: Dictionary in invalid_identity_cases:
		var cancel_before_identity := adapter.cancel_count
		_suite.assert_true(
			not runtime.restore_snapshot(invalid_case["snapshot"]),
			"%s fails closed before Adapter mutation" % str(invalid_case["label"])
		)
		_suite.assert_equal(runtime.snapshot(), windup_snapshot, "%s preserves Runtime state" % str(invalid_case["label"]))
		_suite.assert_equal(adapter.staged_definition, staged_before_malformed, "%s preserves staged payload" % str(invalid_case["label"]))
		_suite.assert_equal(adapter.cancel_count, cancel_before_identity, "%s never cancels the live Adapter" % str(invalid_case["label"]))
	runtime.on_phase_enter(plan, &"ACTIVE", 1750)
	var active_snapshot: Dictionary = runtime.snapshot()
	var active_definition := adapter.released_definition.duplicate(true)
	_suite.assert_true(runtime.restore_snapshot(windup_snapshot), "ACTIVE reconstructs an older authoritative WINDUP snapshot")
	_suite.assert_equal(runtime.snapshot(), windup_snapshot, "ACTIVE to WINDUP restore is deterministic")
	_suite.assert_equal(adapter.released_definition, {}, "ACTIVE to WINDUP removes released payload state")
	_suite.assert_true(runtime.restore_snapshot(active_snapshot), "WINDUP reconstructs the released ACTIVE snapshot")
	_suite.assert_equal(runtime.snapshot(), active_snapshot, "WINDUP to ACTIVE restore is deterministic")
	_suite.assert_equal(adapter.released_definition, active_definition, "ACTIVE restore reconstructs released payload state")
	_suite.assert_true(runtime.restore_snapshot(active_snapshot), "released ACTIVE snapshot is idempotent")
	runtime.on_phase_enter(plan, &"RECOVERY", 1750)
	var recovery_snapshot: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.restore_snapshot(windup_snapshot), "RECOVERY reconstructs an older authoritative WINDUP snapshot")
	_suite.assert_equal(runtime.snapshot(), windup_snapshot, "RECOVERY to WINDUP restore is deterministic")
	_suite.assert_true(runtime.restore_snapshot(recovery_snapshot), "WINDUP reconstructs the released RECOVERY snapshot")
	_suite.assert_equal(runtime.snapshot(), recovery_snapshot, "WINDUP to RECOVERY restore is deterministic")
	_suite.assert_true(runtime.restore_snapshot(recovery_snapshot), "RECOVERY snapshot is idempotent")
	_free_fixture(fixture)


func _test_snapshot_aura_invariants_and_restore_atomicity() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var adapter: FakeGauntletsAdapter = fixture["adapter"]
	var low_combo_snapshot: Dictionary = runtime.snapshot()
	_grant_combo(runtime, 30, 2100)
	var high_combo_snapshot: Dictionary = runtime.snapshot()
	var high_generation := int(high_combo_snapshot.get("aura_source_generation", 0))
	_suite.assert_true(high_generation > 0, "thirty Combo owns a positive aura generation")
	_suite.assert_equal(adapter.aura_source_generation, high_generation, "Runtime and Adapter agree on high-Combo aura ownership")

	var missing_high_aura := high_combo_snapshot.duplicate(true)
	missing_high_aura["aura_source_generation"] = 0
	var aura_calls_before_invalid := adapter.aura_set_count
	_suite.assert_true(not runtime.restore_snapshot(missing_high_aura), "high-Combo snapshot without aura ownership fails closed")
	_suite.assert_equal(runtime.snapshot(), high_combo_snapshot, "missing high-Combo aura rejection preserves Runtime state")
	_suite.assert_equal(adapter.aura_set_count, aura_calls_before_invalid, "missing high-Combo aura is rejected before Adapter mutation")

	var unexpected_low_aura := low_combo_snapshot.duplicate(true)
	unexpected_low_aura["aura_source_generation"] = high_generation
	_suite.assert_true(not runtime.restore_snapshot(unexpected_low_aura), "low-Combo snapshot with aura ownership fails closed")

	adapter.aura_outcomes = [false]
	_suite.assert_true(not runtime.restore_snapshot(low_combo_snapshot), "failed aura cleanup rejects low-Combo restore")
	_suite.assert_equal(runtime.snapshot(), high_combo_snapshot, "failed aura cleanup preserves high-Combo Runtime state")
	_suite.assert_equal(adapter.aura_source_generation, high_generation, "failed aura cleanup preserves Adapter ownership")

	_suite.assert_true(runtime.restore_snapshot(low_combo_snapshot), "successful aura cleanup restores low Combo atomically")
	_suite.assert_equal(adapter.aura_source_generation, 0, "low-Combo restore clears Adapter aura ownership")
	adapter.aura_outcomes = [false]
	_suite.assert_true(not runtime.restore_snapshot(high_combo_snapshot), "failed aura reconstruction rejects high-Combo restore")
	_suite.assert_equal(runtime.snapshot(), low_combo_snapshot, "failed aura reconstruction preserves low-Combo Runtime state")
	_suite.assert_equal(adapter.aura_source_generation, 0, "failed aura reconstruction preserves cleared Adapter state")
	_suite.assert_true(runtime.restore_snapshot(high_combo_snapshot), "high-Combo aura reconstructs after the failure is removed")
	_suite.assert_equal(adapter.aura_source_generation, high_generation, "successful restore reconstructs the exact aura generation")
	_free_fixture(fixture)


func _test_adapter_restore_rollback_and_safe_reset() -> void:
	var target_fixture := _fixture()
	var target_runtime: RefCounted = target_fixture["runtime"]
	var target_plan := _primary_plan(target_runtime, _context(7602))
	_suite.assert_true(bool(target_runtime.commit_action(target_plan, 1770).get("ok", false)), "target restore fixture stages WINDUP")
	var target_snapshot: Dictionary = target_runtime.snapshot()

	var rollback_fixture := _fixture()
	var rollback_runtime: RefCounted = rollback_fixture["runtime"]
	var rollback_adapter: FakeGauntletsAdapter = rollback_fixture["adapter"]
	var rollback_plan := _primary_plan(rollback_runtime, _context(7601))
	_suite.assert_true(bool(rollback_runtime.commit_action(rollback_plan, 1760).get("ok", false)), "rollback fixture stages its original WINDUP")
	var original_snapshot: Dictionary = rollback_runtime.snapshot()
	var original_definition := rollback_adapter.staged_definition.duplicate(true)
	rollback_adapter.begin_outcomes = [&"fail", &"success"]
	_suite.assert_true(not rollback_runtime.restore_snapshot(target_snapshot), "one target begin failure rejects restore")
	_suite.assert_equal(rollback_runtime.snapshot(), original_snapshot, "successful rollback preserves original Runtime state")
	_suite.assert_equal(rollback_adapter.staged_definition, original_definition, "successful rollback reconstructs the original Adapter definition")

	rollback_adapter.begin_outcomes = [&"corrupt", &"success"]
	_suite.assert_true(not rollback_runtime.restore_snapshot(target_snapshot), "corrupt target begin return rejects restore")
	_suite.assert_equal(rollback_runtime.snapshot(), original_snapshot, "corrupt target begin rolls Runtime back atomically")
	_suite.assert_equal(rollback_adapter.staged_definition, original_definition, "corrupt target begin rolls Adapter back atomically")
	_free_fixture(rollback_fixture)

	var reset_fixture := _fixture()
	var reset_runtime: RefCounted = reset_fixture["runtime"]
	var reset_adapter: FakeGauntletsAdapter = reset_fixture["adapter"]
	var reset_plan := _primary_plan(reset_runtime, _context(7603))
	_suite.assert_true(bool(reset_runtime.commit_action(reset_plan, 1780).get("ok", false)), "safe-reset fixture stages its original WINDUP")
	reset_adapter.begin_outcomes = [&"fail", &"fail"]
	_suite.assert_true(not reset_runtime.restore_snapshot(target_snapshot), "persistent target and rollback begin failures reject restore")
	var reset_snapshot: Dictionary = reset_runtime.snapshot()
	_suite.assert_equal(reset_snapshot.get("active_phase"), "READY", "persistent begin failure resets Runtime to READY")
	_suite.assert_equal(reset_snapshot.get("active_token"), 0, "persistent begin failure clears Runtime action ownership")
	_suite.assert_true(not bool(reset_snapshot.get("adapter_active", true)), "persistent begin failure resets Adapter to inactive")
	_suite.assert_equal(reset_adapter.staged_definition, {}, "persistent begin failure clears Adapter payload state")
	_free_fixture(reset_fixture)
	_free_fixture(target_fixture)


func _test_ready_snapshot_tombstones_completed_actions() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var initial_ready: Dictionary = runtime.snapshot()
	var token := 1790
	var plan := _primary_plan(runtime, _context(7701))
	_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "tombstone fixture stages one action")
	var windup_snapshot: Dictionary = runtime.snapshot()
	runtime.finish_action(token)
	var completed_ready: Dictionary = runtime.snapshot()
	_suite.assert_equal(completed_ready.get("active_phase"), "READY", "finished action returns Runtime to READY")
	_suite.assert_equal(completed_ready.get("action_ledgers"), {}, "finished action retires its callback ledger")
	_suite.assert_equal(completed_ready.get("action_token_floor"), token, "finished action advances the serialized token floor")

	_suite.assert_true(runtime.restore_snapshot(initial_ready), "older clean READY checkpoint may restore domain state")
	var stale_ready := initial_ready.duplicate(true)
	stale_ready["action_ledgers"] = (windup_snapshot["action_ledgers"] as Dictionary).duplicate(true)
	_suite.assert_true(not runtime.restore_snapshot(stale_ready), "READY snapshot cannot resurrect a completed action ledger")
	var stale_result: Dictionary = runtime.handle_payload_result(token, token, {
		"target_id": 7701, "outcome_id": "retired:callback", "damage": 1.0, "hit_confirmed": true,
	})
	_suite.assert_equal(stale_result.get("code"), &"STALE_GENERATION", "completed callback remains tombstoned after READY restore")
	var reused_plan := _primary_plan(runtime, _context(7702))
	_suite.assert_equal(runtime.commit_action(reused_plan, token).get("code"), &"INVALID_TOKEN", "READY restore cannot reuse a completed action token")
	_free_fixture(fixture)


func _test_five_punches_have_exact_frames_and_damage() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var adapter: FakeGauntletsAdapter = fixture["adapter"]
	var cases: Array[Dictionary] = [
		{"id": "punch_1", "frames": [3, 3, 5], "damage": 0.8},
		{"id": "punch_2", "frames": [2, 3, 5], "damage": 0.9},
		{"id": "punch_3", "frames": [3, 4, 6], "damage": 1.2},
		{"id": "punch_4", "frames": [3, 4, 6], "damage": 1.3},
		{"id": "punch_5", "frames": [5, 6, 14], "damage": 3.0},
	]
	for index: int in range(cases.size()):
		var plan: Dictionary = _primary_plan(runtime, _context(2000 + index))
		_suite.assert_equal(plan.get("action_id"), cases[index]["id"], "primary resolves authoritative punch %d" % (index + 1))
		for phase_index: int in range(3):
			_suite.assert_equal(_phase(plan, phase_index).get("duration_frames"), cases[index]["frames"][phase_index], "punch %d phase %d uses exact frames" % [index + 1, phase_index])
		_suite.assert_close(float(_payload_parameters(plan).get("damage_multiplier", 0.0)), float(cases[index]["damage"]), "punch %d uses exact multiplier" % (index + 1))
		var token := 10 + index
		_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "punch %d commits" % (index + 1))
		_suite.assert_equal(adapter.staged_definition.get("action_id"), cases[index]["id"], "adapter stages punch %d" % (index + 1))
		_suite.assert_equal(_first_descriptor(adapter.staged_definition).get("generation"), token, "punch descriptor freezes generation")
		runtime.finish_action(token)
	_suite.assert_equal(runtime.presentation_snapshot().get("next_chain_action_id"), "punch_1", "fifth punch wraps the chain")
	_suite.assert_equal(runtime.snapshot().get("combo_state", {}).get("combo_count"), 0, "unconfirmed chain never grants Combo")
	_free_fixture(fixture)


func _test_chain_combo_dedup_damage_and_dash_semantics() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var plan: Dictionary = _primary_plan(runtime, _context(3001))
	_suite.assert_true(bool(runtime.commit_action(plan, 30).get("ok", false)), "Combo fixture punch commits")
	var first: Dictionary = runtime.handle_payload_result(30, 30, {
		"type": "damage_resolved", "target_id": 301, "outcome_id": "punch:0", "damage": 4.8,
		"hit_confirmed": true, "terminal": true,
	})
	_suite.assert_equal(first.get("combo_gain"), 1, "confirmed punch grants one Combo")
	_suite.assert_equal(
		runtime.handle_payload_result(30, 30, {"type": "damage_resolved", "target_id": 301, "outcome_id": "punch:1", "damage": 1.0, "hit_confirmed": true, "terminal": true}).get("code"),
		&"DUPLICATE_TARGET",
		"same action-target pair cannot add Combo twice"
	)
	runtime.finish_action(30)
	var chain_before := int(runtime.snapshot().get("combo_state", {}).get("chain_step", -1))
	runtime.on_dash_completed()
	_suite.assert_equal(runtime.snapshot().get("combo_state", {}).get("combo_count"), 1, "Dash preserves Combo")
	runtime.on_player_damaged()
	_suite.assert_equal(runtime.snapshot().get("combo_state", {}).get("combo_count"), 0, "real damage resets Combo")
	_suite.assert_equal(runtime.snapshot().get("combo_state", {}).get("chain_step"), chain_before, "real damage preserves chain")
	_free_fixture(fixture)


func _test_heavy_counter_skill_and_ultimate_boundaries() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var heavy_hold: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), _context(4001)).get("plan", {})
	_suite.assert_equal(_phase(heavy_hold, 0).get("phase"), "HOLD", "primary starts authoritative HOLD")
	_suite.assert_equal(_phase(heavy_hold, 0).get("charge_complete_frames"), 30, "heavy charge completes at thirty frames")
	var release29: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 29), _context(4002)).get("plan", {})
	_suite.assert_equal(release29.get("action_id"), "punch_1", "primary frame twenty-nine resolves the current punch")
	var heavy: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(4003)).get("plan", {})
	_assert_action(heavy, "charged_heavy", [6, 5, 16], 4.0, "charged heavy")
	_suite.assert_close(float(_payload_parameters(heavy).get("knockback_tiles", 0.0)), 3.0, "charged heavy freezes three-tile knockback")
	var heavy_zone := (_payload_parameters(heavy).get("zone", {}) as Dictionary)
	_suite.assert_equal(heavy_zone.get("mode"), "charged_heavy_shockwave", "charged heavy materializes its typed shockwave")
	_suite.assert_close(float(heavy_zone.get("radius_tiles", 0.0)), 1.5, "charged heavy shockwave uses one-point-five tiles")
	_suite.assert_close(float(heavy_zone.get("damage_multiplier", 0.0)), 0.2, "charged heavy shockwave uses fixed physical multiplier")
	var counter7: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), _dash_context(4004, 7)).get("plan", {})
	var counter8: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), _dash_context(4005, 8)).get("plan", {})
	var normal9_hold: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), _dash_context(4006, 9)).get("plan", {})
	_assert_action(counter7, "dodge_counter", [2, 5, 8], 2.5, "counter frame seven")
	_assert_action(counter8, "dodge_counter", [2, 5, 8], 2.5, "counter frame eight")
	_suite.assert_close(float(_payload_parameters(counter8).get("critical_chance_bonus", 0.0)), 0.25, "Dodge Counter freezes its fixed critical bonus")
	_suite.assert_close(float(_payload_parameters(counter8).get("knockback_tiles", 0.0)), 1.5, "Dodge Counter freezes one-point-five-tile knockback")
	_suite.assert_equal(_phase(normal9_hold, 0).get("phase"), "HOLD", "frame nine falls back to normal primary hold")
	var normal9: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 0), _dash_context(4006, 9)).get("plan", {})
	_suite.assert_equal(normal9.get("action_id"), "punch_1", "frame nine release resolves the current punch")
	var skill: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), _context(4007)).get("plan", {})
	_assert_action(skill, "space_time_shatter", [5, 8, 12], 3.5, "space-time shatter")
	_suite.assert_close(float(skill.get("resource_costs", {}).get("time_energy", 0.0)), 20.0, "skill costs twenty Time Energy")
	var ultimate_hold: Dictionary = runtime.plan_intent(_press_intent(&"weapon_ultimate"), _context(4008)).get("plan", {})
	_suite.assert_equal(_phase(ultimate_hold, 0).get("charge_complete_frames"), 60, "ultimate charge completes at sixty frames")
	_suite.assert_equal(runtime.plan_intent(_release_intent(&"weapon_ultimate", 59), _context(4009)).get("code"), &"UNDERCHARGED", "ultimate frame fifty-nine is undercharged")
	var ultimate: Dictionary = runtime.plan_intent(_release_intent(&"weapon_ultimate", 60), _context(4010)).get("plan", {})
	_assert_action(ultimate, "primordial_collapse_punch", [20, 10, 30], 12.0, "primordial collapse")
	_suite.assert_close(float(ultimate.get("resource_costs", {}).get("time_energy", 0.0)), 55.0, "ultimate costs fifty-five Time Energy")
	_suite.assert_true(bool(ultimate.get("invulnerable_during_cast", false)), "ultimate freezes cast invulnerability")
	_free_fixture(fixture)

	var finisher_fixture := _fixture()
	var finisher_runtime: RefCounted = finisher_fixture["runtime"]
	_grant_combo(finisher_runtime, 15, 4500)
	for step: int in range(4):
		var setup_plan := _primary_plan(finisher_runtime, _context(4600 + step))
		_suite.assert_true(bool(finisher_runtime.commit_action(setup_plan, 4600 + step).get("ok", false)), "finisher setup punch %d commits" % step)
		finisher_runtime.finish_action(4600 + step)
	var finisher: Dictionary = _primary_plan(finisher_runtime, _context(4700))
	_suite.assert_equal(finisher.get("action_id"), "punch_5", "fifteen-Combo setup reaches authoritative finisher")
	_suite.assert_close(float(_payload_parameters(finisher).get("knockback_tiles", 0.0)), 1.5, "punch five freezes one-point-five-tile knockback")
	_suite.assert_close(float(_payload_parameters(finisher).get("time_damage_ratio", 0.0)), 0.5, "punch five freezes its fixed fifteen-Combo time bonus")
	_free_fixture(finisher_fixture)


func _test_tier_snapshots_affect_future_actions_only() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var before: Dictionary = _primary_plan(runtime, _context(5001))
	_suite.assert_equal(before.get("combo_tier_snapshot", {}).get("tier_id"), "none", "pre-hit plan freezes no tier")
	_grant_combo(runtime, 30, 500)
	var after: Dictionary = _primary_plan(runtime, _context(5002))
	_suite.assert_equal(after.get("combo_tier_snapshot", {}).get("tier_id"), "time_storm", "future plan sees thirty-Combo tier")
	_suite.assert_close(float(_payload_parameters(after).get("critical_chance_bonus", 0.0)), 0.20, "future plan freezes twenty percent critical")
	_suite.assert_close(float(_payload_parameters(after).get("time_damage_ratio", 0.0)), 0.20, "future primary freezes twenty percent time damage")
	_suite.assert_equal(_payload_parameters(after).get("energy_return"), 3, "future plan freezes three Energy return")
	_suite.assert_equal(before.get("combo_tier_snapshot", {}).get("tier_id"), "none", "existing plan remains immutable after Combo changes")
	_free_fixture(fixture)


func _test_stop_accelerate_rewind_and_rift_interactions() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var stop_context := _context(6001)
	stop_context["time_interactions"] = {"stop_active": true, "stop_generation": 81}
	var stop_total := 0
	for index: int in range(7):
		var token := 600 + index
		var plan: Dictionary = _primary_plan(runtime, stop_context)
		_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "Stop punch %d commits" % index)
		var result: Dictionary = runtime.handle_payload_result(token, token, {"type": "damage_resolved", "target_id": 700 + index, "outcome_id": "stop:%d" % index, "damage": 5.0, "hit_confirmed": true, "terminal": true})
		stop_total += int(result.get("stop_extension_frames", 0))
		runtime.finish_action(token)
	_suite.assert_equal(stop_total, 30, "one Stop source is capped at thirty extension frames")
	var stop_calls := (fixture["owner"] as FakeGauntletsOwner).stop_extension_calls
	_suite.assert_equal(stop_calls.size(), 6, "Stop fixture invokes the payload-scoped owner interface only until the cap")
	for call: Dictionary in stop_calls:
		_suite.assert_equal(call.get("payload_generation"), call.get("action_token"), "Stop owner receives matching action token and payload generation")
		_suite.assert_equal(call.get("extension_frames"), 5, "Stop owner receives the exact five-frame payload extension")

	var accelerate_context := _context(6100)
	accelerate_context["time_interactions"] = {"accelerate_active": true, "accelerate_generation": 82}
	var third_result: Dictionary = {}
	var third_multiplier := 0.0
	for index: int in range(3):
		var token := 620 + index
		var plan: Dictionary = _primary_plan(runtime, accelerate_context)
		third_multiplier = float(_payload_parameters(plan).get("damage_multiplier", 0.0))
		_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "Accelerate punch %d commits" % index)
		third_result = runtime.handle_payload_result(token, token, {"type": "damage_resolved", "target_id": 800 + index, "outcome_id": "accelerate:%d" % index, "damage": 5.0, "hit_confirmed": true, "terminal": true})
		runtime.finish_action(token)
	_suite.assert_true(not (third_result.get("echo_descriptor", {}) as Dictionary).is_empty(), "third accelerated primary creates one echo")
	_suite.assert_close(float((third_result.get("echo_descriptor", {}).get("parameters", {}) as Dictionary).get("damage_multiplier", 0.0)), 0.5 * third_multiplier, "echo freezes half of the third punch multiplier")

	var rewind_context := _dash_context(6200, 8)
	rewind_context["time_interactions"] = {"rewind_counter_available": true, "rewind_generation": 83, "rewind_remaining_frames": 120}
	var counter: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), rewind_context).get("plan", {})
	_suite.assert_close(float(_payload_parameters(counter).get("damage_multiplier", 0.0)), 5.0, "Rewind doubles Dodge Counter damage")
	_suite.assert_true(bool(runtime.commit_action(counter, 630).get("ok", false)), "Rewind Counter commits")
	_suite.assert_equal(runtime.snapshot().get("claimed_rewind_generations"), [83], "Rewind generation is claimed exactly once")
	runtime.finish_action(630)
	_suite.assert_equal(runtime.plan_intent(_press_intent(&"weapon_primary"), rewind_context).get("code"), &"STALE_REWIND_GENERATION", "claimed Rewind generation cannot be reused")

	_grant_combo(runtime, 30 - int(runtime.snapshot().get("combo_state", {}).get("combo_count", 0)), 900)
	var rift_context := _context(6300)
	rift_context["time_interactions"] = {
		"rift_active": true,
		"rift_generation": 84,
		"active_rifts": [{"generation": 84, "center": Vector2(2.0, 3.0), "radius": 2.5}],
	}
	var skill: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), rift_context).get("plan", {})
	_suite.assert_close(float(skill.get("resource_costs", {}).get("time_energy", 0.0)), 14.0, "high-Combo Rift reduces skill cost by thirty percent")
	_suite.assert_close(float(_interaction(skill, "rift").get("effect_multiplier", 0.0)), 1.5, "high-Combo Rift freezes one-point-five effect multiplier")
	_suite.assert_equal((_interaction(skill, "rift").get("active_rifts", []) as Array).size(), 1, "Rift descriptor freezes spatial source set")
	_free_fixture(fixture)


func _test_echo_is_non_recursive() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var context := _context(7001)
	context["time_interactions"] = {
		"stop_active": true, "stop_generation": 91,
		"accelerate_active": true, "accelerate_generation": 92,
	}
	var plan: Dictionary = _primary_plan(runtime, context)
	_suite.assert_true(bool(runtime.commit_action(plan, 700).get("ok", false)), "echo guard fixture commits")
	var before_combo := int(runtime.snapshot().get("combo_state", {}).get("combo_count", 0))
	var echo: Dictionary = runtime.handle_payload_result(700, 700, {
		"type": "damage_resolved", "target_id": 901, "outcome_id": "echo:0", "damage": 2.0,
		"hit_confirmed": true, "terminal": true, "is_echo": true,
		"combo_eligible": false, "energy_eligible": false, "stop_extension_eligible": false,
		"recursive_echo": false,
	})
	_suite.assert_true(bool(echo.get("ok", false)), "echo result is consumed")
	_suite.assert_equal(echo.get("combo_gain"), 0, "echo cannot grant Combo")
	_suite.assert_equal(echo.get("energy_return"), 0, "echo cannot return Energy")
	_suite.assert_equal(echo.get("stop_extension_frames"), 0, "echo cannot extend Stop")
	_suite.assert_true((echo.get("echo_descriptor", {}) as Dictionary).is_empty(), "echo cannot recursively create another echo")
	_suite.assert_equal(runtime.snapshot().get("combo_state", {}).get("combo_count"), before_combo, "echo leaves Combo unchanged")
	_free_fixture(fixture)


func _test_replay_payload_transition_projector() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var normal_token := 725
	var normal_plan := _primary_plan(runtime, _context(7250))
	_suite.assert_true(
		bool(runtime.commit_action(normal_plan, normal_token).get("ok", false)),
		"Replay projector normal-hit fixture commits"
	)
	var normal_result := {
		"type": "damage_resolved", "target_id": 9725, "outcome_id": "projector:normal",
		"damage": 4.0, "hit_confirmed": true, "terminal": true,
	}
	var normal_before: Dictionary = runtime.snapshot()
	var miss_result := normal_result.duplicate(true)
	miss_result["outcome_id"] = "projector:miss"
	miss_result["hit_confirmed"] = false
	var miss_projection: Dictionary = runtime.project_payload_result_replay_transition(
		normal_before, normal_token, normal_token, miss_result
	)
	_suite.assert_true(bool(miss_projection.get("ok", false)), "Replay projector accepts a non-hit result")
	_suite.assert_equal(miss_projection.get("runtime_snapshot"), normal_before, "Replay projector leaves runtime state unchanged for a non-hit")
	_suite.assert_equal(miss_projection.get("context", {}).get("combo_gain"), 0, "Replay projector exposes zero Combo for a non-hit")
	_suite.assert_equal(miss_projection.get("context", {}).get("energy_return"), 0, "Replay projector exposes zero Energy for a non-hit")
	_suite.assert_equal(miss_projection.get("context", {}).get("stop_extension_frames"), 0, "Replay projector exposes zero Stop extension for a non-hit")
	_suite.assert_true((miss_projection.get("context", {}).get("echo_descriptor", {}) as Dictionary).is_empty(), "Replay projector exposes no echo for a non-hit")
	_suite.assert_equal(runtime.snapshot(), normal_before, "non-hit projection is side-effect free")
	var normal_before_copy := normal_before.duplicate(true)
	var normal_projection: Dictionary = runtime.project_payload_result_replay_transition(
		normal_before, normal_token, normal_token, normal_result
	)
	_suite.assert_true(bool(normal_projection.get("ok", false)), "Replay projector accepts a normal hit")
	_suite.assert_equal(normal_before, normal_before_copy, "Replay projector never mutates its input snapshot")
	_suite.assert_equal(runtime.snapshot(), normal_before_copy, "Replay projector never mutates live Runtime state")
	_suite.assert_equal(
		normal_projection.get("runtime_snapshot", {}).get("adapter"),
		normal_before.get("adapter"),
		"Replay projector preserves the adapter subtree"
	)
	var normal_live: Dictionary = runtime.handle_payload_result(normal_token, normal_token, normal_result)
	_assert_projected_payload_matches_live(runtime, normal_projection, normal_live, "normal hit")
	_suite.assert_equal(
		normal_projection.get("context", {}).get("combo_gain"),
		1,
		"Replay projector records the normal hit Combo gain"
	)

	var duplicate_before: Dictionary = runtime.snapshot()
	var duplicate_projection: Dictionary = runtime.project_payload_result_replay_transition(
		duplicate_before, normal_token, normal_token, normal_result
	)
	_suite.assert_true(not bool(duplicate_projection.get("ok", true)), "Replay projector rejects a duplicate target")
	_suite.assert_equal(duplicate_projection.get("code"), &"DUPLICATE_TARGET", "duplicate target uses the authoritative rejection code")
	_suite.assert_equal(runtime.snapshot(), duplicate_before, "duplicate projection is side-effect free")
	var stale_projection: Dictionary = runtime.project_payload_result_replay_transition(
		duplicate_before, normal_token, normal_token + 1, normal_result
	)
	_suite.assert_true(not bool(stale_projection.get("ok", true)), "Replay projector rejects a stale generation")
	_suite.assert_equal(stale_projection.get("code"), &"STALE_GENERATION", "stale generation uses the authoritative rejection code")
	_suite.assert_equal(runtime.snapshot(), duplicate_before, "stale projection is side-effect free")
	runtime.finish_action(normal_token)
	_free_fixture(fixture)

	var high_fixture := _fixture()
	var high_runtime: RefCounted = high_fixture["runtime"]
	_grant_combo(high_runtime, 30, 7300)
	var high_token := 7400
	var high_plan := _primary_plan(high_runtime, _context(7400))
	_suite.assert_true(bool(high_runtime.commit_action(high_plan, high_token).get("ok", false)), "Replay projector high-Combo fixture commits")
	var high_result := {
		"type": "damage_resolved", "target_id": 9740, "outcome_id": "projector:high_combo",
		"damage": 4.0, "hit_confirmed": true, "terminal": true,
	}
	var high_before: Dictionary = high_runtime.snapshot()
	var high_projection: Dictionary = high_runtime.project_payload_result_replay_transition(
		high_before, high_token, high_token, high_result
	)
	var high_live: Dictionary = high_runtime.handle_payload_result(high_token, high_token, high_result)
	_assert_projected_payload_matches_live(high_runtime, high_projection, high_live, "high-Combo hit")
	_suite.assert_equal(high_projection.get("context", {}).get("energy_return"), 3, "Replay projector exposes exact frozen-tier Energy return")
	_suite.assert_equal(high_projection.get("runtime_snapshot", {}).get("aura_source_generation"), high_token, "Replay projector advances the high-Combo aura source")
	high_runtime.finish_action(high_token)
	_free_fixture(high_fixture)

	var stop_fixture := _fixture()
	var stop_runtime: RefCounted = stop_fixture["runtime"]
	var stop_context := _context(7500)
	stop_context["time_interactions"] = {"stop_active": true, "stop_generation": 175}
	var stop_token := 7500
	var stop_plan := _primary_plan(stop_runtime, stop_context)
	_suite.assert_true(bool(stop_runtime.commit_action(stop_plan, stop_token).get("ok", false)), "Replay projector Stop fixture commits")
	var stop_result := {
		"type": "damage_resolved", "target_id": 9750, "outcome_id": "projector:stop",
		"damage": 4.0, "hit_confirmed": true, "terminal": true,
	}
	var stop_projection: Dictionary = stop_runtime.project_payload_result_replay_transition(
		stop_runtime.snapshot(), stop_token, stop_token, stop_result
	)
	var stop_live: Dictionary = stop_runtime.handle_payload_result(stop_token, stop_token, stop_result)
	_assert_projected_payload_matches_live(stop_runtime, stop_projection, stop_live, "Stop hit")
	_suite.assert_equal(stop_projection.get("context", {}).get("stop_extension_frames"), 5, "Replay projector exposes exact Stop extension")
	_suite.assert_equal(stop_projection.get("runtime_snapshot", {}).get("stop_extensions_by_generation", {}).get("175"), 5, "Replay projector advances only the owned Stop ledger")
	var stop_owner_calls := (stop_fixture["owner"] as FakeGauntletsOwner).stop_extension_calls
	_suite.assert_equal(stop_owner_calls.size(), 1, "live Stop hit invokes the payload-scoped owner interface once")
	if not stop_owner_calls.is_empty():
		_suite.assert_equal(stop_owner_calls[0].get("action_token"), stop_token, "live Stop hit forwards the authoritative action token")
		_suite.assert_equal(stop_owner_calls[0].get("payload_generation"), stop_token, "live Stop hit forwards the authoritative payload generation")
		_suite.assert_equal(stop_owner_calls[0].get("extension_frames"), 5, "live Stop hit forwards the projected five-frame extension")
	stop_runtime.finish_action(stop_token)
	_free_fixture(stop_fixture)

	var accelerate_fixture := _fixture()
	var accelerate_runtime: RefCounted = accelerate_fixture["runtime"]
	var accelerate_context := _context(7600)
	accelerate_context["time_interactions"] = {"accelerate_active": true, "accelerate_generation": 176}
	for index: int in range(3):
		var token := 7600 + index
		var plan := _primary_plan(accelerate_runtime, accelerate_context)
		_suite.assert_true(bool(accelerate_runtime.commit_action(plan, token).get("ok", false)), "Replay projector Accelerate fixture %d commits" % (index + 1))
		var result := {
			"type": "damage_resolved", "target_id": 9760 + index,
			"outcome_id": "projector:accelerate:%d" % (index + 1),
			"damage": 4.0, "hit_confirmed": true, "terminal": true,
		}
		var projection: Dictionary = accelerate_runtime.project_payload_result_replay_transition(
			accelerate_runtime.snapshot(), token, token, result
		)
		var live: Dictionary = accelerate_runtime.handle_payload_result(token, token, result)
		_assert_projected_payload_matches_live(accelerate_runtime, projection, live, "Accelerate hit %d" % (index + 1))
		_suite.assert_equal(
			(projection.get("runtime_snapshot", {}).get("accelerate_hits_by_generation", {}) as Dictionary).get("176"),
			index + 1,
			"Replay projector advances Accelerate hit %d exactly once" % (index + 1)
		)
		_suite.assert_equal(
			(projection.get("context", {}).get("echo_descriptor", {}) as Dictionary).is_empty(),
			index < 2,
			"Replay projector creates an echo only on Accelerate hit %d" % (index + 1)
		)
		accelerate_runtime.finish_action(token)

	var echo_token := 7610
	var echo_plan := _primary_plan(accelerate_runtime, accelerate_context)
	_suite.assert_true(bool(accelerate_runtime.commit_action(echo_plan, echo_token).get("ok", false)), "Replay projector echo fixture commits")
	var echo_result := {
		"type": "damage_resolved", "target_id": 9770, "outcome_id": "projector:echo",
		"damage": 2.0, "hit_confirmed": true, "terminal": true, "is_echo": true,
		"combo_eligible": false, "energy_eligible": false, "stop_extension_eligible": false,
		"recursive_echo": false,
	}
	var echo_before: Dictionary = accelerate_runtime.snapshot()
	var echo_projection: Dictionary = accelerate_runtime.project_payload_result_replay_transition(
		echo_before, echo_token, echo_token, echo_result
	)
	var echo_live: Dictionary = accelerate_runtime.handle_payload_result(echo_token, echo_token, echo_result)
	_assert_projected_payload_matches_live(accelerate_runtime, echo_projection, echo_live, "echo hit")
	_suite.assert_equal(
		echo_projection.get("runtime_snapshot", {}).get("accelerate_hits_by_generation"),
		echo_before.get("accelerate_hits_by_generation"),
		"Replay projector never advances Accelerate for an echo"
	)
	_suite.assert_true((echo_projection.get("context", {}).get("echo_descriptor", {}) as Dictionary).is_empty(), "Replay projector never creates a recursive echo")
	accelerate_runtime.finish_action(echo_token)
	_free_fixture(accelerate_fixture)

	var zone_fixture := _fixture()
	var zone_runtime: RefCounted = zone_fixture["runtime"]
	var zone_token := 7700
	var zone_plan: Dictionary = zone_runtime.plan_intent(
		_press_intent(&"weapon_skill"), _context(7700)
	).get("plan", {})
	_suite.assert_true(bool(zone_runtime.commit_action(zone_plan, zone_token).get("ok", false)), "Replay projector zone fixture commits")
	var zone_result := {
		"type": "damage_resolved", "payload_kind": "zone", "target_id": 9771,
		"outcome_id": "projector:zone", "damage": 1.0, "hit_confirmed": true,
		"terminal": false,
	}
	var zone_projection: Dictionary = zone_runtime.project_payload_result_replay_transition(
		zone_runtime.snapshot(), zone_token, zone_token, zone_result
	)
	var zone_live: Dictionary = zone_runtime.handle_payload_result(zone_token, zone_token, zone_result)
	_assert_projected_payload_matches_live(zone_runtime, zone_projection, zone_live, "zone hit")
	_suite.assert_equal(zone_projection.get("context", {}).get("combo_gain"), 0, "Replay projector preserves a zone action's frozen zero Combo gain")
	zone_runtime.finish_action(zone_token)
	_free_fixture(zone_fixture)


func _assert_projected_payload_matches_live(
	runtime: RefCounted,
	projection: Dictionary,
	live_result: Dictionary,
	label: String
) -> void:
	_suite.assert_true(bool(projection.get("ok", false)), "%s projection succeeds" % label)
	_suite.assert_equal(projection.get("runtime_snapshot"), runtime.snapshot(), "%s projection matches the live runtime transition" % label)
	var context := projection.get("context", {}) as Dictionary
	for field: String in ["combo_gain", "energy_return", "stop_extension_frames", "echo_descriptor", "tier"]:
		_suite.assert_equal(context.get(field), live_result.get(field), "%s projects exact %s" % [label, field])


func _test_snapshot_reset_determinism_and_bounded_ledgers() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	for index: int in range(260):
		var token := 1000 + index
		var plan: Dictionary = _primary_plan(runtime, _context(8000 + index))
		_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "bounded runtime action %d commits" % index)
		runtime.handle_payload_result(token, token, {"type": "damage_resolved", "target_id": 2000 + index, "outcome_id": "bounded:%d" % index, "damage": 1.0, "hit_confirmed": true, "terminal": true})
		runtime.finish_action(token)
	var snapshot: Dictionary = runtime.snapshot()
	_suite.assert_equal((snapshot.get("action_ledgers", {}) as Dictionary).size(), 0, "finished runtime action ledgers are retired immediately")
	_suite.assert_equal(snapshot.get("action_token_floor"), 1259, "finished actions advance the serialized callback floor")
	_suite.assert_equal((snapshot.get("combo_state", {}).get("hit_targets_by_token", {}) as Dictionary).size(), 256, "Combo ledger is bounded")
	_suite.assert_true(runtime.restore_snapshot(snapshot), "valid runtime snapshot restores")
	_suite.assert_equal(runtime.snapshot(), snapshot, "runtime snapshot restore is deterministic")
	var second_fixture := _fixture()
	var first_plan: Dictionary = _primary_plan(runtime, _context(9999))
	var second_plan: Dictionary = _primary_plan(second_fixture["runtime"], _context(9999))
	runtime.reset_runtime_state(&"determinism_fixture")
	second_fixture["runtime"].reset_runtime_state(&"determinism_fixture")
	first_plan = _primary_plan(runtime, _context(9999))
	second_plan = _primary_plan(second_fixture["runtime"], _context(9999))
	_suite.assert_true(bool(runtime.commit_action(first_plan, 77).get("ok", false)), "first deterministic action commits")
	_suite.assert_true(bool(second_fixture["runtime"].commit_action(second_plan, 77).get("ok", false)), "second deterministic action commits")
	_suite.assert_equal(_first_descriptor(fixture["adapter"].staged_definition).get("seed"), _first_descriptor(second_fixture["adapter"].staged_definition).get("seed"), "same seed and token produce the same descriptor seed")
	runtime.reset_runtime_state(&"run_terminal")
	var reset: Dictionary = runtime.snapshot()
	_suite.assert_equal(reset.get("combo_state", {}).get("combo_count"), 0, "reset clears Combo")
	_suite.assert_equal(reset.get("combo_state", {}).get("chain_step"), 0, "reset clears chain")
	_suite.assert_equal(reset.get("action_ledgers"), {}, "reset clears action ledgers")
	_suite.assert_equal(reset.get("stop_extensions_by_generation"), {}, "reset clears Stop ledger")
	_suite.assert_equal(reset.get("accelerate_hits_by_generation"), {}, "reset clears Accelerate ledger")
	_free_fixture(second_fixture)
	_free_fixture(fixture)


func _fixture() -> Dictionary:
	var owner := FakeGauntletsOwner.new()
	var adapter := FakeGauntletsAdapter.new()
	adapter.name = "GauntletsWeapon"
	owner.add_child(adapter)
	var definition := _catalog_profile("gauntlets_launch_v1")
	var profile = WeaponRuntimeProfileScript.new()
	var parsed: Dictionary = profile.configure(definition)
	var modifiers = WeaponModifierStateScript.new()
	var capabilities := PackedStringArray(definition.get("capabilities", []))
	var configured_modifiers := modifiers.configure(capabilities, _modifier_bounds(capabilities))
	var runtime = GauntletsWeaponRuntimeScript.new()
	var configured: bool = bool(parsed.get("ok", false)) and configured_modifiers and runtime.configure(owner, profile, modifiers)
	return {"owner": owner, "adapter": adapter, "profile": profile, "modifiers": modifiers, "runtime": runtime, "configured": configured}


func _grant_combo(runtime: RefCounted, amount: int, token_seed: int) -> void:
	for index: int in range(maxi(0, amount)):
		var token := token_seed + index
		var plan: Dictionary = _primary_plan(runtime, _context(12000 + token))
		_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "Combo grant action %d commits" % index)
		var result: Dictionary = runtime.handle_payload_result(token, token, {"type": "damage_resolved", "target_id": 30000 + token, "outcome_id": "grant:%d" % index, "damage": 1.0, "hit_confirmed": true, "terminal": true})
		_suite.assert_true(bool(result.get("ok", false)), "Combo grant hit %d confirms" % index)
		runtime.finish_action(token)


func _primary_plan(runtime: RefCounted, context: Dictionary, held_frames: int = 0) -> Dictionary:
	return runtime.plan_intent(
		_release_intent(&"weapon_primary", held_frames),
		context
	).get("plan", {})


func _assert_action(plan: Dictionary, action_id: String, frames: Array, damage: float, label: String) -> void:
	_suite.assert_equal(plan.get("action_id"), action_id, "%s resolves action" % label)
	for index: int in range(3):
		_suite.assert_equal(_phase(plan, index).get("duration_frames"), frames[index], "%s phase %d uses exact frames" % [label, index])
	_suite.assert_close(float(_payload_parameters(plan).get("damage_multiplier", 0.0)), damage, "%s uses exact damage" % label)


func _free_fixture(fixture: Dictionary) -> void:
	var owner: Node = fixture.get("owner")
	if owner != null and is_instance_valid(owner):
		owner.free()


func _press_intent(intent_id: StringName) -> Dictionary:
	return {"id": str(intent_id), "edge": "pressed"}


func _release_intent(intent_id: StringName, held_frames: int) -> Dictionary:
	return {"id": str(intent_id), "edge": "released", "held_frames": held_frames}


func _context(run_seed: int) -> Dictionary:
	return {
		"run_seed": run_seed,
		"aim_direction": Vector2.RIGHT,
		"dash_completion_token": 0,
		"frames_since_dash_completion": -1,
		"dash_direction": Vector2.RIGHT,
		"player_generation": 1,
		"time_interactions": {},
	}


func _dash_context(run_seed: int, frames_since_dash: int) -> Dictionary:
	var result := _context(run_seed)
	result["dash_completion_token"] = 77
	result["frames_since_dash_completion"] = frames_since_dash
	result["dash_direction"] = Vector2.LEFT
	return result


func _phase(plan: Dictionary, index: int) -> Dictionary:
	var phases: Variant = plan.get("phases", [])
	if not phases is Array or index < 0 or index >= (phases as Array).size():
		return {}
	var value: Variant = (phases as Array)[index]
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _payload_parameters(plan: Dictionary) -> Dictionary:
	var payloads: Variant = plan.get("payloads", [])
	if not payloads is Array or (payloads as Array).is_empty():
		return {}
	var payload: Variant = (payloads as Array)[0]
	return ((payload as Dictionary).get("parameters", {}) as Dictionary).duplicate(true) if payload is Dictionary else {}


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


func _first_descriptor(definition: Dictionary) -> Dictionary:
	var descriptors: Variant = definition.get("payload_descriptors", [])
	if not descriptors is Array or (descriptors as Array).is_empty():
		return {}
	var value: Variant = (descriptors as Array)[0]
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _interaction(plan: Dictionary, interaction_id: String) -> Dictionary:
	for value: Variant in plan.get("time_interactions", []) as Array:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == interaction_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _catalog_profile(profile_id: String) -> Dictionary:
	var file := FileAccess.open(PROFILE_CATALOG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return {}
	for value: Variant in parsed as Array:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == profile_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _dictionary_ref_by_id(values: Variant, id_field: String, expected_id: String) -> Dictionary:
	if not values is Array:
		return {}
	for value: Variant in values as Array:
		if value is Dictionary and str((value as Dictionary).get(id_field, "")) == expected_id:
			return value as Dictionary
	return {}


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
		bounds[capability] = {"minimum": 0.1, "maximum": 200.0}
	return bounds
