extends Node

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const GauntletsWeaponScript := preload("res://scripts/combat/gauntlets_weapon.gd")
const GauntletsWeaponRuntimeScript := preload("res://scripts/combat/weapons/gauntlets_weapon_runtime.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"


class RecordingTarget:
	extends Node2D

	var damage_multiplier: float = 1.0
	var received: Array[RefCounted] = []
	var rift_sources: Dictionary = {}


	func receive_hit(damage_info: RefCounted) -> float:
		received.append(damage_info)
		return maxf(0.0, float(damage_info.amount) * damage_multiplier)


	func apply_time_rift(source_id: StringName, multiplier: float) -> void:
		rift_sources[source_id] = multiplier


	func clear_time_rift(source_id: StringName) -> void:
		rift_sources.erase(source_id)


class RecordingSink:
	extends RefCounted

	var results: Array[Dictionary] = []
	var echo_on_next_eligible_hit: bool = false


	func handle_payload_result(
		action_token: int,
		generation: int,
		result: Dictionary
	) -> Dictionary:
		results.append({
			"action_token": action_token,
			"generation": generation,
			"result": result.duplicate(true),
		})
		if (
			echo_on_next_eligible_hit
			and bool(result.get("combo_eligible", false))
			and not bool(result.get("is_echo", false))
		):
			echo_on_next_eligible_hit = false
			return {
				"ok": true,
				"code": &"OK",
				"combo_gain": int(result.get("combo_gain", 0)),
				"combo_count": 3,
				"energy_return": 0.0,
				"stop_extension_frames": 0,
				"echo_descriptor": {
					"descriptor_id": "gauntlets_accelerate_echo",
					"kind": "hitbox",
					"token": action_token,
					"generation": generation,
					"outcome_id": "gauntlets_accelerate_echo:0",
					"outcome_index": 1,
					"seed": 19001,
					"target_deduplication": "per_action_target",
					"parameters": {
						"damage_multiplier": 0.4,
						"combo_gain": 0,
						"combo_eligible": false,
						"energy_eligible": false,
						"stop_extension_eligible": false,
						"recursive_echo": false,
						"is_echo": true,
					},
				},
				"context": {},
			}
		return {
			"ok": true,
			"code": &"OK",
			"combo_gain": int(result.get("combo_gain", 0)),
			"combo_count": 1,
			"energy_return": 0.0,
			"stop_extension_frames": 0,
			"echo_descriptor": {},
			"context": {},
		}


class ReportStateObserver extends RefCounted:
	var weapon: Node
	var records: Array[Dictionary] = []


	func _init(configured_weapon: Node) -> void:
		weapon = configured_weapon


	func handle_payload_result(action_token: int, generation: int, result: Dictionary) -> void:
		records.append({
			"action_token": action_token,
			"generation": generation,
			"result": result.duplicate(true),
			"runtime_snapshot": weapon.runtime_snapshot(),
		})


class RecordingHurtbox:
	extends Area2D

	var received: Array[RefCounted] = []


	func receive_hit(damage_info: RefCounted) -> float:
		received.append(damage_info)
		return float(damage_info.amount)


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_contract_validation_and_atomic_staging()
	await _test_physics_overlap_executes_real_area_hitbox()
	await _test_hitbox_resolves_typed_damage_and_deduplicates()
	await _test_launch_and_rift_spatial_metadata()
	await _test_feedback_damage_tags_use_authoritative_tiers()
	await _test_counter_and_ultimate_invulnerability_lifecycle()
	await _test_accelerate_echo_is_non_recursive()
	await _test_zone_ticks_and_reset_cleanup()
	await _test_runtime_materializes_skill_ultimate_and_rewind_payloads()
	await _test_runtime_snapshot_restore_is_atomic_with_real_adapter()
	await _test_adapter_snapshot_restores_hit_zone_echo_claims_and_callbacks()
	await _test_runtime_snapshot_restore_clears_stale_combo_aura()
	await _test_runtime_rift_generation_executes_only_owned_zone()
	await _test_runtime_rift_plan_freezes_combo_and_generation()
	await _test_combo_slow_aura_source_generation_and_cleanup()
	_suite.finish(get_tree())


func _test_contract_validation_and_atomic_staging() -> void:
	var fixture := await _fixture()
	var weapon: Node = fixture["weapon"]
	for method_name: StringName in [
		&"begin_profile_action",
		&"release_profile_action",
		&"is_profile_action_active",
		&"cancel_profile_action",
		&"finish_profile_action",
		&"reset_runtime_state",
	]:
		_suite.assert_true(weapon.has_method(method_name), "Gauntlets adapter exposes %s" % method_name)

	var malformed := _definition("punch_1", 0, [_descriptor("hitbox", 0, {"damage_multiplier": 0.8})])
	_suite.assert_true(weapon.begin_profile_action(malformed).is_empty(), "invalid token fails construction closed")
	_suite.assert_equal(weapon.prepared_payload_count_for_test(), 0, "invalid construction leaves no staged payload")
	_suite.assert_true(not weapon.is_profile_action_active(), "invalid construction leaves adapter idle")
	var independent_generation := _definition("punch_1", 102, [_descriptor("hitbox", 0, {
		"damage_multiplier": 0.8,
		"combo_gain": 1,
	})], 7)
	_suite.assert_equal(
		weapon.begin_profile_action(independent_generation),
		independent_generation,
		"adapter preserves a valid source generation independently from its action token"
	)
	var staged: Array[Dictionary] = weapon.prepared_payload_snapshots_for_test()
	if staged.size() == 1:
		_suite.assert_equal(staged[0].get("action_token"), 102, "staged payload keeps its action token")
		_suite.assert_equal(staged[0].get("generation"), 7, "staged payload keeps its independent generation")
	weapon.cancel_profile_action()

	var valid := _definition("punch_1", 101, [_descriptor("hitbox", 0, {
		"damage_multiplier": 0.8,
		"combo_gain": 1,
		"combo_eligible": true,
		"energy_eligible": true,
		"stop_extension_eligible": true,
	})])
	_suite.assert_equal(weapon.begin_profile_action(valid), valid, "valid hitbox definition stages atomically")
	_suite.assert_equal(weapon.prepared_payload_count_for_test(), 1, "one hitbox is staged")
	_suite.assert_true(weapon.release_profile_action(), "staged hitbox releases")
	_suite.assert_true(not weapon.release_profile_action(), "action payload cannot release twice")
	await _cleanup_fixture(fixture)


func _test_physics_overlap_executes_real_area_hitbox() -> void:
	var fixture := await _fixture()
	var weapon: Node = fixture["weapon"]
	var enemy := Node2D.new()
	enemy.name = "GauntletsPhysicsEnemy"
	enemy.set_meta("stable_target_id", 4901)
	enemy.add_to_group("enemies")
	var hurtbox := RecordingHurtbox.new()
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	collision.shape = shape
	hurtbox.add_child(collision)
	enemy.add_child(hurtbox)
	add_child(enemy)
	enemy.global_position = Vector2(64.0, 0.0)
	var definition := _definition("punch_1", 151, [_descriptor("hitbox", 0, {
		"damage_multiplier": 0.8,
		"combo_gain": 1,
		"combo_eligible": true,
		"energy_eligible": false,
		"stop_extension_eligible": false,
		"active_frames": 3,
	})])
	weapon.begin_profile_action(definition)
	_suite.assert_true(weapon.release_profile_action(), "real Area2D hitbox attaches for ACTIVE")
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_suite.assert_equal(hurtbox.received.size(), 1, "physics overlap resolves one real melee hit")
	if hurtbox.received.size() == 1:
		_suite.assert_equal(hurtbox.received[0].action_token, 151, "physics hit retains the committed token")
	await _cleanup_nodes([enemy])
	await _cleanup_fixture(fixture)


func _test_hitbox_resolves_typed_damage_and_deduplicates() -> void:
	var fixture := await _fixture()
	var weapon: Node = fixture["weapon"]
	var owner: Node = fixture["owner"]
	var sink: RecordingSink = fixture["sink"]
	var definition := _definition("punch_1", 201, [_descriptor("hitbox", 0, {
		"damage_multiplier": 0.8,
		"combo_gain": 1,
		"critical_chance_bonus": 0.08,
		"time_damage_ratio": 0.2,
		"energy_return": 2.0,
		"stop_extension_frames": 5,
		"combo_eligible": true,
		"energy_eligible": true,
		"stop_extension_eligible": true,
		"range_tiles": 1.5,
		"width_tiles": 1.0,
	})])
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "typed punch stages")
	_suite.assert_true(weapon.release_profile_action(), "typed punch releases")
	var payload: Node = weapon.owned_payloads_for_test()[0]
	var target := _target(5001, Vector2(64.0, 0.0))
	var first: Dictionary = payload.execute_target_for_test(target)
	var duplicate: Dictionary = payload.execute_target_for_test(target)
	_suite.assert_true(not first.is_empty(), "real hitbox resolves its first target entry")
	_suite.assert_true(duplicate.is_empty(), "same token and target cannot resolve twice")
	_suite.assert_equal(target.received.size(), 2, "physical hit and bonus time component use two typed DamageInfo values")
	if target.received.size() == 2:
		var physical: RefCounted = target.received[0]
		var time: RefCounted = target.received[1]
		_suite.assert_close(physical.amount, 4.8, "punch applies frozen base attack times multiplier")
		_suite.assert_equal(physical.damage_type, DamageInfoScript.DamageType.PHYSICAL, "primary component is PHYSICAL")
		_suite.assert_close(physical.crit_chance, 0.08, "primary component keeps frozen Combo critical bonus")
		_suite.assert_equal(physical.source, weapon, "DamageInfo source is the adapter")
		_suite.assert_equal(physical.attacker, owner, "DamageInfo attacker is the owning player")
		_suite.assert_equal(physical.action_token, 201, "DamageInfo freezes the action token")
		_suite.assert_equal(physical.source_generation, 201, "DamageInfo freezes the source generation")
		_suite.assert_close(time.amount, 1.2, "bonus time damage is base attack times frozen ratio")
		_suite.assert_equal(time.damage_type, DamageInfoScript.DamageType.TIME, "bonus component is TIME")
		_suite.assert_true(time.tags.has("non_recursive:time_damage"), "bonus time damage is explicitly non-recursive")
	_suite.assert_equal(sink.results.size(), 1, "eligible target emits one authoritative payload result")
	if sink.results.size() == 1:
		var result: Dictionary = sink.results[0]["result"]
		_suite.assert_equal(result.get("target_id"), 5001, "payload result uses stable target identity")
		_suite.assert_equal(result.get("combo_gain"), 1, "payload result freezes Combo gain")
		_suite.assert_equal(result.get("energy_return"), 2.0, "payload result freezes Energy return")
		_suite.assert_equal(result.get("stop_extension_frames"), 5, "payload result freezes Stop extension")
		_suite.assert_equal(result.get("impact_position"), target.global_position, "payload result records actual impact position")
	var feedback: Array[Dictionary] = weapon.feedback_facts_for_test()
	_suite.assert_equal(feedback.size(), 1, "resolved target emits one deterministic impact fact")
	if feedback.size() == 1:
		_suite.assert_equal(feedback[0].get("weapon_id"), "gauntlets", "impact fact identifies Gauntlets")
		_suite.assert_equal(feedback[0].get("action_token"), 201, "impact fact keeps the committed token")
		_suite.assert_equal(feedback[0].get("target_id"), 5001, "impact fact keeps stable target identity")
		_suite.assert_equal(feedback[0].get("impact_tier"), "light", "impact fact routes the punch through light feedback")
	await _cleanup_nodes([target])
	await _cleanup_fixture(fixture)


func _test_launch_and_rift_spatial_metadata() -> void:
	var fixture := await _fixture()
	var weapon: Node = fixture["weapon"]
	var sink: RecordingSink = fixture["sink"]
	var definition := _definition("punch_5", 301, [_descriptor("hitbox", 0, {
		"damage_multiplier": 3.0,
		"combo_gain": 1,
		"launch": 1.0,
		"poise_damage": 18.0,
		"displacement_tiles": 1.5,
		"combo_eligible": true,
		"energy_eligible": false,
		"stop_extension_eligible": false,
		"rift_context": {
			"source_generation": 77,
			"spatial_policy": "zone_intersection",
			"active_rifts": [{"generation": 77, "center": Vector2(80.0, 0.0), "radius": 96.0}],
		},
	})])
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "launch punch stages")
	_suite.assert_true(weapon.release_profile_action(), "launch punch releases")
	var payload: Node = weapon.owned_payloads_for_test()[0]
	var target := _target(6001, Vector2(72.0, 0.0))
	payload.execute_target_for_test(target)
	_suite.assert_equal(target.received.size(), 1, "launch punch damages target once")
	if target.received.size() == 1:
		var control: Dictionary = target.received[0].control_effect
		_suite.assert_equal(control.get("kind"), "launch", "launch uses typed control payload")
		_suite.assert_equal(control.get("conversion_id"), "gauntlets_poised_launch", "launch declares Boss conversion identity")
		_suite.assert_true(not bool(control.get("airborne", true)), "Boss conversion never requests unsupported airborne state")
		_suite.assert_close(float(control.get("poise_damage", 0.0)), 18.0, "launch carries unmultipled base poise damage")
		_suite.assert_close(float(control.get("boss_poise_multiplier", 0.0)), 1.4, "launch carries the Chrono Warden multiplier once")
		_suite.assert_close(float(control.get("displacement_pixels", 0.0)), 96.0, "launch converts displacement tiles once")
		_suite.assert_true(not bool(control.get("interrupt_active_attack", true)), "launch preserves a committed Boss active attack")
	if sink.results.size() == 1:
		var spatial: Dictionary = sink.results[0]["result"].get("spatial_context", {})
		_suite.assert_equal(spatial.get("center"), target.global_position, "Rift metadata freezes the real impact center")
		_suite.assert_equal(spatial.get("source_generation"), 77, "Rift metadata freezes source generation")
		_suite.assert_equal(spatial.get("spatial_policy"), "zone_intersection", "Rift metadata preserves spatial policy")
		_suite.assert_equal((spatial.get("active_rifts", []) as Array).size(), 1, "Rift metadata carries immutable active Rift geometry")
	await _cleanup_nodes([target])
	await _cleanup_fixture(fixture)


func _test_feedback_damage_tags_use_authoritative_tiers() -> void:
	var cases: Array[Dictionary] = [
		{"action_id": "punch_5", "multiplier": 3.0, "expected_tag": "attack:finisher", "audio_cue": &"hit_finisher"},
		{"action_id": "charged_heavy", "multiplier": 4.0, "expected_tag": "attack:heavy", "audio_cue": &"hit_heavy"},
		{"action_id": "dodge_counter", "multiplier": 2.5, "expected_tag": "attack:heavy", "audio_cue": &"hit_heavy"},
		{"action_id": "space_time_shatter", "multiplier": 3.5, "expected_tag": "attack:heavy", "audio_cue": &"hit_heavy", "kind": "shockwave"},
		{"action_id": "primordial_collapse_punch", "multiplier": 12.0, "expected_tag": "attack:heavy", "audio_cue": &"hit_heavy"},
	]
	for index: int in range(cases.size()):
		var case: Dictionary = cases[index]
		var fixture := await _fixture()
		var weapon: Node = fixture["weapon"]
		var kind := str(case.get("kind", "hitbox"))
		var definition := _definition(str(case["action_id"]), 350 + index, [_descriptor(kind, 0, {
			"damage_multiplier": float(case["multiplier"]),
			"combo_gain": 0,
			"combo_eligible": false,
			"energy_eligible": false,
			"stop_extension_eligible": false,
		})])
		weapon.begin_profile_action(definition)
		weapon.release_profile_action()
		var target := _target(6500 + index, Vector2(64.0, 0.0))
		weapon.owned_payloads_for_test()[0].execute_target_for_test(target)
		_suite.assert_equal(target.received.size(), 1, "%s emits one primary feedback DamageInfo" % case["action_id"])
		if target.received.size() == 1:
			_suite.assert_true(
				target.received[0].tags.has(str(case["expected_tag"])),
				"%s routes hit feedback through %s" % [case["action_id"], case["expected_tag"]]
			)
			var profile: Dictionary = CombatFeedback.get_hit_profile_for_test(target.received[0], false)
			_suite.assert_equal(
				profile.get("audio_cue"),
				case["audio_cue"],
				"%s reaches the existing CombatFeedback impact profile" % case["action_id"]
			)
		await _cleanup_nodes([target])
		await _cleanup_fixture(fixture)


func _test_counter_and_ultimate_invulnerability_lifecycle() -> void:
	for action_id: String in ["dodge_counter", "primordial_collapse_punch"]:
		var fixture := await _fixture()
		var weapon: Node = fixture["weapon"]
		var health: Node = fixture["health"]
		var definition := _definition(action_id, 400 + action_id.length(), [_descriptor("hitbox", 0, {
			"damage_multiplier": 2.5 if action_id == "dodge_counter" else 12.0,
			"combo_gain": 5 if action_id == "dodge_counter" else 0,
			"combo_eligible": action_id == "dodge_counter",
			"energy_eligible": false,
			"stop_extension_eligible": false,
		})])
		definition["invulnerable_during_cast"] = true
		_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "%s stages atomically" % action_id)
		_suite.assert_equal(
			health.invulnerable,
			action_id == "primordial_collapse_punch",
			"%s acquires protection at its authoritative phase boundary" % action_id
		)
		_suite.assert_true(weapon.release_profile_action(), "%s releases" % action_id)
		_suite.assert_true(health.invulnerable, "%s owns protection during ACTIVE" % action_id)
		if action_id == "dodge_counter":
			var payload: Node = weapon.owned_payloads_for_test()[0]
			payload.advance_execution_for_test(4)
			_suite.assert_true(health.invulnerable, "Dodge Counter keeps invulnerability through ACTIVE frame four")
			payload.advance_execution_for_test(1)
			_suite.assert_true(not health.invulnerable, "Dodge Counter releases invulnerability exactly after ACTIVE frame five")
		weapon.finish_profile_action()
		_suite.assert_true(not health.invulnerable, "%s finish releases only its owned protection" % action_id)
		await _cleanup_fixture(fixture)


func _test_accelerate_echo_is_non_recursive() -> void:
	var fixture := await _fixture()
	var weapon: Node = fixture["weapon"]
	var sink: RecordingSink = fixture["sink"]
	var observer := ReportStateObserver.new(weapon)
	weapon.payload_result_reported.connect(observer.handle_payload_result)
	sink.echo_on_next_eligible_hit = true
	var definition := _definition("punch_1", 501, [_descriptor("hitbox", 0, {
		"damage_multiplier": 0.8,
		"combo_gain": 1,
		"combo_eligible": true,
		"energy_eligible": true,
		"stop_extension_eligible": true,
	})])
	weapon.begin_profile_action(definition)
	weapon.release_profile_action()
	var primary: Node = weapon.owned_payloads_for_test()[0]
	var target := _target(7001, Vector2(64.0, 0.0))
	primary.execute_target_for_test(target)
	_suite.assert_equal(observer.records.size(), 1, "accelerated primary exposes one public payload result")
	if observer.records.size() == 1:
		var observed_payloads := (
			(observer.records[0].get("runtime_snapshot", {}) as Dictionary).get("owned_payloads", [])
		) as Array
		var observed_echoes := 0
		for payload_value: Variant in observed_payloads:
			var payload_snapshot := (payload_value as Dictionary).get("snapshot", {}) as Dictionary
			if bool(payload_snapshot.get("is_echo", false)):
				observed_echoes += 1
		_suite.assert_equal(observed_echoes, 1, "Accelerate echo exists before the public payload-result signal")
	var payloads: Array[Node] = weapon.owned_payloads_for_test()
	_suite.assert_equal(payloads.size(), 2, "third eligible hit response spawns one dynamic echo")
	if payloads.size() == 2:
		var echo_snapshot: Dictionary = payloads[1].execution_snapshot()
		_suite.assert_true(bool(echo_snapshot.get("is_echo", false)), "dynamic payload is marked as an echo")
		_suite.assert_true(not bool(echo_snapshot.get("combo_eligible", true)), "echo cannot grow Combo")
		_suite.assert_true(not bool(echo_snapshot.get("energy_eligible", true)), "echo cannot return Energy")
		_suite.assert_true(not bool(echo_snapshot.get("stop_extension_eligible", true)), "echo cannot extend Stop")
		_suite.assert_true(not bool(echo_snapshot.get("recursive_echo", true)), "echo cannot recursively spawn another echo")
		var echo_target := _target(7002, Vector2(64.0, 8.0))
		payloads[1].execute_target_for_test(echo_target)
		_suite.assert_equal(weapon.owned_payloads_for_test().size(), 2, "echo result cannot recursively append another payload")
		await _cleanup_nodes([echo_target])
	await _cleanup_nodes([target])
	await _cleanup_fixture(fixture)


func _test_zone_ticks_and_reset_cleanup() -> void:
	var fixture := await _fixture()
	var weapon: Node = fixture["weapon"]
	var definition := _definition("space_time_shatter", 601, [_descriptor("shockwave", 0, {
		"damage_multiplier": 3.5,
		"damage_type_split": {"physical": 0.5, "time": 0.5},
		"combo_gain": 0,
		"combo_eligible": false,
		"energy_eligible": false,
		"stop_extension_eligible": false,
		"range_tiles": 3.0,
		"width_tiles": 2.0,
		"zone": {
			"mode": "space_time_shatter",
			"radius_tiles": 2.0,
			"duration_frames": 60,
			"tick_interval_frames": 30,
			"damage_multiplier": 0.15,
			"damage_type_split": {"time": 1.0},
			"move_speed_multiplier": 0.6,
		},
	})])
	weapon.begin_profile_action(definition)
	weapon.release_profile_action()
	var shockwave: Node = weapon.owned_payloads_for_test()[0]
	var impact_target := _target(8001, Vector2(96.0, 0.0))
	shockwave.execute_target_for_test(impact_target)
	var payloads: Array[Node] = weapon.owned_payloads_for_test()
	_suite.assert_equal(payloads.size(), 2, "Shatter hit materializes one owned zone")
	var zone_target := _target(8002, impact_target.global_position + Vector2(24.0, 0.0))
	if payloads.size() == 2:
		var zone: Node = payloads[1]
		zone.advance_execution_for_test(29)
		_suite.assert_equal(zone_target.received.size(), 0, "zone waits until its exact tick boundary")
		zone.advance_execution_for_test(1)
		_suite.assert_equal(zone_target.received.size(), 1, "zone deals one real tick on frame thirty")
		if zone_target.received.size() == 1:
			_suite.assert_equal(zone_target.received[0].damage_type, DamageInfoScript.DamageType.TIME, "Shatter zone tick is typed TIME damage")
			_suite.assert_close(zone_target.received[0].amount, 0.9, "Shatter zone tick uses base attack times frozen multiplier")
		_suite.assert_true(not zone_target.rift_sources.is_empty(), "zone applies a source-owned slow while target remains inside")
	weapon.reset_runtime_state()
	_suite.assert_equal(weapon.owned_payload_count_for_test(), 0, "reset removes every released hitbox, echo, and zone")
	_suite.assert_true(zone_target.rift_sources.is_empty(), "reset clears only the zone's owned slow source")
	await _cleanup_nodes([impact_target, zone_target])
	await _cleanup_fixture(fixture)


func _test_runtime_materializes_skill_ultimate_and_rewind_payloads() -> void:
	var skill_fixture := await _runtime_fixture()
	var skill_runtime: RefCounted = skill_fixture["runtime"]
	var skill_weapon: Node = skill_fixture["weapon"]
	var skill_plan: Dictionary = skill_runtime.plan_intent(
		{"id": "weapon_skill", "edge": "pressed"}, _runtime_context(9101)
	).get("plan", {})
	_suite.assert_true(bool(skill_runtime.commit_action(skill_plan, 910).get("ok", false)), "Runtime commits real Shatter payload")
	_suite.assert_equal(skill_weapon.prepared_payload_count_for_test(), 1, "Shatter stages one authoritative impact payload")
	skill_runtime.on_phase_enter(skill_plan, &"ACTIVE", 910)
	var skill_target := _target(9910, Vector2(96.0, 0.0))
	skill_weapon.owned_payloads_for_test()[0].execute_target_for_test(skill_target)
	var skill_payloads: Array[Node] = skill_weapon.owned_payloads_for_test()
	_suite.assert_equal(skill_payloads.size(), 2, "real Shatter hit materializes its zone through the Adapter")
	if skill_payloads.size() == 2:
		var zone_snapshot: Dictionary = skill_payloads[1].execution_snapshot()
		_suite.assert_equal(zone_snapshot.get("mode"), "space_time_shatter", "Shatter zone keeps its typed mode")
	await _cleanup_nodes([skill_target])
	await _cleanup_fixture(skill_fixture)

	var ultimate_fixture := await _runtime_fixture()
	var ultimate_runtime: RefCounted = ultimate_fixture["runtime"]
	var ultimate_weapon: Node = ultimate_fixture["weapon"]
	var ultimate_plan: Dictionary = ultimate_runtime.plan_intent(
		{"id": "weapon_ultimate", "edge": "released", "held_frames": 60},
		_runtime_context(9102)
	).get("plan", {})
	_suite.assert_true(bool(ultimate_runtime.commit_action(ultimate_plan, 911).get("ok", false)), "Runtime commits real Collapse payloads")
	_suite.assert_equal(ultimate_weapon.prepared_payload_count_for_test(), 2, "Collapse stages main fist and four-tile cone wave")
	ultimate_runtime.on_phase_enter(ultimate_plan, &"ACTIVE", 911)
	var ultimate_target := _target(9911, Vector2(64.0, 0.0))
	var ultimate_payloads: Array[Node] = ultimate_weapon.owned_payloads_for_test()
	ultimate_payloads[0].execute_target_for_test(ultimate_target)
	ultimate_payloads[1].execute_target_for_test(ultimate_target)
	_suite.assert_equal(ultimate_target.received.size(), 3, "overlapping fist and wave share one damage claim")
	var ultimate_total := 0.0
	for info: RefCounted in ultimate_target.received:
		ultimate_total += float(info.get("amount"))
	_suite.assert_close(ultimate_total, 72.0, "overlap resolves exactly one twelve-times mixed-damage hit")
	var reverse_target := _target(9913, Vector2(72.0, 8.0))
	ultimate_payloads[1].execute_target_for_test(reverse_target)
	ultimate_payloads[0].execute_target_for_test(reverse_target)
	_suite.assert_equal(reverse_target.received.size(), 3, "wave-first overlap still resolves exactly one mixed-damage hit")
	_suite.assert_true(ultimate_weapon.owned_payloads_for_test().size() >= 4, "wave-first overlap still materializes the primary collapse zone")
	await _cleanup_nodes([ultimate_target, reverse_target])
	await _cleanup_fixture(ultimate_fixture)

	var rewind_fixture := await _runtime_fixture()
	var rewind_runtime: RefCounted = rewind_fixture["runtime"]
	var rewind_weapon: Node = rewind_fixture["weapon"]
	var rewind_context := _runtime_context(9103)
	rewind_context["dash_completion_token"] = 77
	rewind_context["frames_since_dash_completion"] = 8
	rewind_context["time_interactions"] = {
		"rewind_counter_available": true,
		"rewind_generation": 44,
		"rewind_remaining_frames": 120,
	}
	var rewind_plan: Dictionary = rewind_runtime.plan_intent(
		{"id": "weapon_primary", "edge": "pressed"}, rewind_context
	).get("plan", {})
	_suite.assert_true(bool(rewind_runtime.commit_action(rewind_plan, 912).get("ok", false)), "Runtime commits empowered real Counter")
	rewind_runtime.on_phase_enter(rewind_plan, &"ACTIVE", 912)
	var rewind_target := _target(9912, Vector2(64.0, 0.0))
	rewind_weapon.owned_payloads_for_test()[0].execute_target_for_test(rewind_target)
	var rewind_payloads: Array[Node] = rewind_weapon.owned_payloads_for_test()
	_suite.assert_equal(rewind_payloads.size(), 2, "Rewind Counter hit materializes its time shockwave zone")
	if rewind_payloads.size() == 2:
		var rewind_zone: Dictionary = rewind_payloads[1].execution_snapshot()
		_suite.assert_equal(rewind_zone.get("mode"), "rewind_counter_shockwave", "Rewind shockwave keeps its typed mode")
	await _cleanup_nodes([rewind_target])
	await _cleanup_fixture(rewind_fixture)


func _test_runtime_snapshot_restore_is_atomic_with_real_adapter() -> void:
	var fixture := await _runtime_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var weapon: Node = fixture["weapon"]
	var health: Node = fixture["health"]
	var plan: Dictionary = runtime.plan_intent(
		{"id": "weapon_ultimate", "edge": "released", "held_frames": 60},
		_runtime_context(9201)
	).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(plan, 920).get("ok", false)), "snapshot fixture stages real Collapse payloads")
	var windup_snapshot: Dictionary = runtime.snapshot()
	var windup_adapter := windup_snapshot.get("adapter", {}) as Dictionary
	var prepared_before: Array[Dictionary] = weapon.prepared_payload_snapshots_for_test()
	_suite.assert_equal(prepared_before.size(), 2, "snapshot fixture owns two prepared Collapse payloads")
	_suite.assert_equal((windup_adapter.get("prepared_payloads", []) as Array).size(), 2, "WINDUP snapshot serializes both prepared payloads")
	_suite.assert_true(health.invulnerable, "Collapse WINDUP owns cast invulnerability")
	var forged_runtime_top_level := windup_snapshot.duplicate(true)
	forged_runtime_top_level["unexpected_authority"] = true
	_suite.assert_true(
		not runtime.restore_snapshot(forged_runtime_top_level),
		"Gauntlets Runtime rejects an unknown top-level snapshot field"
	)
	_suite.assert_equal(runtime.snapshot(), windup_snapshot, "Gauntlets Runtime top-level rejection is atomic")

	var malformed_snapshot := windup_snapshot.duplicate(true)
	var malformed_definition := (malformed_snapshot["committed_definition"] as Dictionary).duplicate(true)
	var malformed_descriptors := (malformed_definition["payload_descriptors"] as Array).duplicate(true)
	(malformed_descriptors[0] as Dictionary)["kind"] = "invalid_kind"
	malformed_definition["payload_descriptors"] = malformed_descriptors
	malformed_snapshot["committed_definition"] = malformed_definition
	_suite.assert_true(not runtime.restore_snapshot(malformed_snapshot), "malformed real WINDUP snapshot fails closed")
	_suite.assert_equal(runtime.snapshot(), windup_snapshot, "malformed real WINDUP preserves Runtime state")
	_suite.assert_equal(weapon.prepared_payload_snapshots_for_test(), prepared_before, "malformed real WINDUP preserves prepared payloads")
	_suite.assert_true(health.invulnerable, "malformed real WINDUP preserves cast invulnerability")

	runtime.on_phase_enter(plan, &"ACTIVE", 920)
	var restore_target := _target(9920, Vector2(64.0, 0.0))
	weapon.owned_payloads_for_test()[0].execute_target_for_test(restore_target)
	var active_snapshot: Dictionary = runtime.snapshot()
	var owned_before := _payload_snapshots(weapon.owned_payloads_for_test())
	_suite.assert_equal(owned_before.size(), 3, "ACTIVE snapshot fixture owns both Collapse hits and the spawned zone")
	_suite.assert_equal(((active_snapshot.get("adapter", {}) as Dictionary).get("owned_payloads", []) as Array).size(), 3, "ACTIVE snapshot serializes released hits and spawned zone")
	var rewind_before: Dictionary = runtime.gameplay_rewind_snapshot()
	var payload_guard_before: Dictionary = runtime.gameplay_rewind_committed_payload_guard()
	_suite.assert_true(runtime.cancel_for_gameplay_rewind(920, &"test_gameplay_rewind"), "Gameplay Rewind cancels Collapse action-local state")
	_suite.assert_equal(runtime.gameplay_rewind_committed_payload_guard(), payload_guard_before, "Gameplay Rewind preserves Collapse hit and zone identities plus claims")
	_suite.assert_true(runtime.restore_gameplay_rewind_snapshot_for_rollback(rewind_before), "Collapse rollback restores action-local state")
	_suite.assert_equal(runtime.gameplay_rewind_snapshot(), rewind_before, "Collapse rollback restores exact bytes without replacing payloads")
	_suite.assert_equal(runtime.gameplay_rewind_committed_payload_guard(), payload_guard_before, "Collapse rollback preserves the same committed payload instances")
	_suite.assert_true(runtime.restore_snapshot(windup_snapshot), "ACTIVE restores the exact prepared WINDUP state")
	_suite.assert_equal(runtime.snapshot(), windup_snapshot, "ACTIVE to WINDUP restore is deterministic")
	_suite.assert_equal(weapon.prepared_payload_snapshots_for_test(), prepared_before, "ACTIVE to WINDUP rebuilds prepared payloads")
	_suite.assert_equal(weapon.owned_payload_count_for_test(), 0, "ACTIVE to WINDUP removes released payloads")
	_suite.assert_true(health.invulnerable, "ACTIVE to WINDUP preserves Collapse invulnerability")
	_suite.assert_true(runtime.restore_snapshot(active_snapshot), "WINDUP restores the exact released ACTIVE state")
	_suite.assert_equal(runtime.snapshot(), active_snapshot, "WINDUP to ACTIVE restore is deterministic")
	_suite.assert_equal(_payload_snapshots(weapon.owned_payloads_for_test()), owned_before, "WINDUP to ACTIVE rebuilds released payloads")

	runtime.on_phase_enter(plan, &"RECOVERY", 920)
	var recovery_snapshot: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.restore_snapshot(active_snapshot), "RECOVERY restores the exact ACTIVE payload state")
	_suite.assert_equal(runtime.snapshot(), active_snapshot, "RECOVERY to ACTIVE restore is deterministic")
	_suite.assert_equal(_payload_snapshots(weapon.owned_payloads_for_test()), owned_before, "RECOVERY to ACTIVE rebuilds released payloads")
	_suite.assert_true(runtime.restore_snapshot(recovery_snapshot), "ACTIVE restores the exact RECOVERY payload state")
	_suite.assert_equal(runtime.snapshot(), recovery_snapshot, "ACTIVE to RECOVERY restore is deterministic")
	_suite.assert_true(health.invulnerable, "RECOVERY restore preserves invulnerability")
	await _cleanup_nodes([restore_target])
	await _cleanup_fixture(fixture)


func _test_adapter_snapshot_restores_hit_zone_echo_claims_and_callbacks() -> void:
	var fixture := await _fixture()
	var weapon: Node = fixture["weapon"]
	var sink: RecordingSink = fixture["sink"]
	sink.echo_on_next_eligible_hit = true
	var definition := _definition("charged_heavy", 930, [_descriptor("hitbox", 0, {
		"damage_multiplier": 4.0,
		"combo_gain": 3,
		"combo_eligible": true,
		"energy_eligible": true,
		"stop_extension_eligible": true,
		"recursive_echo": false,
		"is_echo": false,
		"active_frames": 5,
		"zone": {
			"mode": "charged_heavy_shockwave",
			"radius_tiles": 1.5,
			"duration_frames": 90,
			"tick_interval_frames": 30,
			"damage_multiplier": 0.2,
			"damage_type_split": {"physical": 1.0},
			"move_speed_multiplier": 1.0,
		},
	})])
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "snapshot claims fixture stages")
	_suite.assert_true(weapon.release_profile_action(), "snapshot claims fixture releases")
	var first_target := _target(9930, Vector2(64.0, 0.0))
	var primary: Node = weapon.owned_payloads_for_test()[0]
	primary.advance_execution_for_test(2)
	primary.execute_target_for_test(first_target)
	var spawned_payloads: Array[Node] = weapon.owned_payloads_for_test()
	if spawned_payloads.size() == 3:
		spawned_payloads[1].advance_execution_for_test(30)
		spawned_payloads[2].execute_target_for_test(first_target)
	var before: Dictionary = weapon.runtime_snapshot()
	var before_payloads := before.get("owned_payloads", []) as Array
	_suite.assert_equal(before_payloads.size(), 3, "snapshot owns primary hit, spawned zone, and echo")
	_suite.assert_true((before.get("reported_claim_order", []) as Array).size() >= 2, "snapshot preserves reported callback claims")
	if before_payloads.size() == 3:
		var primary_snapshot := (before_payloads[0] as Dictionary).get("snapshot", {}) as Dictionary
		var zone_snapshot := (before_payloads[1] as Dictionary).get("snapshot", {}) as Dictionary
		_suite.assert_equal(primary_snapshot.get("remaining_frames"), 3, "hit snapshot preserves remaining execution frames")
		_suite.assert_equal(primary_snapshot.get("direction"), Vector2.RIGHT, "hit snapshot preserves world direction")
		_suite.assert_equal(zone_snapshot.get("remaining_frames"), 60, "zone snapshot preserves remaining execution frames")
		_suite.assert_true(not (zone_snapshot.get("damage_claim_keys", []) as Array).is_empty(), "zone snapshot preserves damage claims")
		_suite.assert_equal((before_payloads[1] as Dictionary).get("global_position"), Vector2(64.0, 0.0), "zone snapshot preserves world position")
	weapon.reset_runtime_state()
	_suite.assert_equal(weapon.owned_payload_count_for_test(), 0, "restore fixture removes live nodes before reconstruction")
	_suite.assert_true(weapon.restore_runtime_snapshot(before), "adapter reconstructs a released snapshot from reset state")
	_suite.assert_equal(weapon.runtime_snapshot(), before, "adapter restore is deterministic")
	var restored_payloads: Array[Node] = weapon.owned_payloads_for_test()
	_suite.assert_equal(restored_payloads.size(), 3, "restore rebuilds hit, zone, and echo nodes")
	var first_received := first_target.received.size()
	var duplicate_results_before := sink.results.size()
	restored_payloads[0].execute_target_for_test(first_target)
	restored_payloads[2].execute_target_for_test(first_target)
	_suite.assert_equal(first_target.received.size(), first_received, "restored hit claim prevents duplicate damage and reward")
	_suite.assert_equal(sink.results.size(), duplicate_results_before, "restored hit and echo claims suppress duplicate callbacks")
	var next_target := _target(9931, Vector2(96.0, 0.0))
	var results_before := sink.results.size()
	restored_payloads[0].execute_target_for_test(next_target)
	_suite.assert_true(sink.results.size() > results_before, "restored payload callback remains live")
	var after_callback: Dictionary = weapon.runtime_snapshot()
	var forged_hit_snapshot: Dictionary = restored_payloads[0].execution_snapshot()
	forged_hit_snapshot["unexpected_authority"] = true
	var hit_before_rejection: Dictionary = restored_payloads[0].execution_snapshot()
	var hit_dependencies := {
		"source": weapon,
		"owner_entity": weapon.get_parent(),
		"progress_claims": {},
		"progress_claim_order": [],
		"damage_claims": {},
		"damage_claim_order": [],
	}
	_suite.assert_true(
		not restored_payloads[0].can_restore_execution_snapshot(forged_hit_snapshot),
		"Gauntlets hit snapshot rejects unknown authoritative fields"
	)
	_suite.assert_true(
		not restored_payloads[0].restore_execution_snapshot(forged_hit_snapshot, hit_dependencies),
		"Gauntlets hit restore rejects an unknown authoritative field"
	)
	_suite.assert_equal(
		restored_payloads[0].execution_snapshot(),
		hit_before_rejection,
		"Gauntlets hit unknown-field rejection is atomic"
	)
	var forged_zone_snapshot: Dictionary = restored_payloads[1].execution_snapshot()
	forged_zone_snapshot["unexpected_authority"] = true
	var zone_before_rejection: Dictionary = restored_payloads[1].execution_snapshot()
	var zone_dependencies := {
		"source": weapon,
		"owner_entity": weapon.get_parent(),
	}
	_suite.assert_true(
		not restored_payloads[1].can_restore_execution_snapshot(forged_zone_snapshot),
		"Gauntlets zone snapshot rejects unknown authoritative fields"
	)
	_suite.assert_true(
		not restored_payloads[1].restore_execution_snapshot(forged_zone_snapshot, zone_dependencies),
		"Gauntlets zone restore rejects an unknown authoritative field"
	)
	_suite.assert_equal(
		restored_payloads[1].execution_snapshot(),
		zone_before_rejection,
		"Gauntlets zone unknown-field rejection is atomic"
	)
	var forged_adapter_top_level := after_callback.duplicate(true)
	forged_adapter_top_level["unexpected_authority"] = true
	_suite.assert_true(
		not weapon.can_restore_runtime_snapshot(forged_adapter_top_level),
		"Gauntlets Adapter rejects an unknown top-level snapshot field"
	)
	_suite.assert_true(
		not weapon.restore_runtime_snapshot(forged_adapter_top_level),
		"Gauntlets Adapter restore rejects an unknown top-level snapshot field"
	)
	_suite.assert_equal(weapon.runtime_snapshot(), after_callback, "Gauntlets Adapter top-level rejection is atomic")
	var forged_adapter_wrapper := after_callback.duplicate(true)
	forged_adapter_wrapper["owned_payloads"][0]["unexpected_authority"] = true
	_suite.assert_true(
		not weapon.can_restore_runtime_snapshot(forged_adapter_wrapper),
		"Gauntlets Adapter rejects an unknown payload-wrapper field"
	)
	_suite.assert_true(
		not weapon.restore_runtime_snapshot(forged_adapter_wrapper),
		"Gauntlets Adapter restore rejects an unknown payload-wrapper field"
	)
	_suite.assert_equal(weapon.runtime_snapshot(), after_callback, "Gauntlets Adapter wrapper rejection is atomic")
	var malformed: Dictionary = before.duplicate(true)
	var malformed_owned := (malformed["owned_payloads"] as Array).duplicate(true)
	(malformed_owned[0] as Dictionary)["global_position"] = Vector2(INF, 0.0)
	malformed["owned_payloads"] = malformed_owned
	_suite.assert_true(not weapon.restore_runtime_snapshot(malformed), "malformed adapter snapshot fails closed")
	_suite.assert_equal(weapon.runtime_snapshot(), after_callback, "failed adapter restore rolls back atomically")
	await _cleanup_nodes([first_target, next_target])
	await _cleanup_fixture(fixture)


func _test_runtime_snapshot_restore_clears_stale_combo_aura() -> void:
	var fixture := await _runtime_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var weapon: Node = fixture["weapon"]
	var low_combo_snapshot: Dictionary = runtime.snapshot()
	_suite.assert_true(
		_grant_runtime_combo_for_test(runtime, 30, 940),
		"real Adapter fixture reaches the thirty-Combo aura tier"
	)
	_suite.assert_true(
		not weapon.combo_slow_aura_snapshot_for_test().is_empty(),
		"thirty Combo materializes the real source-owned aura"
	)
	_suite.assert_true(runtime.restore_snapshot(low_combo_snapshot), "low-Combo READY snapshot restores")
	_suite.assert_equal(runtime.snapshot().get("aura_source_generation"), 0, "low-Combo restore clears Runtime aura ownership")
	_suite.assert_equal(weapon.combo_slow_aura_snapshot_for_test(), {}, "low-Combo restore clears the real Adapter aura")
	await _cleanup_fixture(fixture)


func _test_runtime_rift_generation_executes_only_owned_zone() -> void:
	var near_fixture := await _runtime_fixture()
	var near_runtime: RefCounted = near_fixture["runtime"]
	var near_weapon: Node = near_fixture["weapon"]
	_suite.assert_true(_restore_combo_for_test(near_runtime, 30), "near Rift fixture restores thirty Combo")
	var near_context := _runtime_context(9301)
	near_context["time_interactions"] = {
		"rift_active": true,
		"rift_generation": 301,
		"active_rifts": [{"generation": 301, "center": Vector2(96.0, 0.0), "radius": 8.0}],
	}
	var near_plan: Dictionary = near_runtime.plan_intent(
		{"id": "weapon_skill", "edge": "pressed"}, near_context
	).get("plan", {})
	_suite.assert_close(float(near_plan.get("resource_costs", {}).get("time_energy", 0.0)), 14.0, "near owned Rift reduces real Shatter cost")
	_suite.assert_true(bool(near_runtime.commit_action(near_plan, 930).get("ok", false)), "near owned Rift stages real Shatter")
	near_runtime.on_phase_enter(near_plan, &"ACTIVE", 930)
	var near_target := _target(9930, Vector2(96.0, 0.0))
	var near_shockwave: Node = near_weapon.owned_payloads_for_test()[0]
	var near_hit_result: Dictionary = near_shockwave.execute_target_for_test(near_target)
	var near_payloads: Array[Node] = near_weapon.owned_payloads_for_test()
	_suite.assert_equal(near_payloads.size(), 2, "near owned Rift materializes one real Shatter zone")
	if near_payloads.size() == 2:
		var near_zone: Dictionary = near_payloads[1].execution_snapshot()
		var near_parameters := near_zone.get("parameters", {}) as Dictionary
		_suite.assert_close(float(near_parameters.get("radius_tiles", 0.0)), 3.75, "near owned Rift expands real zone radius")
		_suite.assert_equal(near_parameters.get("duration_frames"), 450, "near owned Rift extends real zone duration")
		_suite.assert_equal(near_parameters.get("rift_source_generation"), 301, "real zone records the intersecting owned Rift generation")
	near_weapon.reset_runtime_state()
	_suite.assert_equal(near_weapon.owned_payload_count_for_test(), 0, "near Rift reset clears every real payload")
	var sink_count_after_reset := (near_fixture["sink"] as RecordingSink).results.size()
	var stale_result := near_hit_result.duplicate(true)
	stale_result["claim_id"] = "stale_rift_callback"
	stale_result["outcome_id"] = "stale_rift_callback:0"
	stale_result["target_id"] = 19930
	near_shockwave.payload_result.emit(930, 930, stale_result)
	_suite.assert_equal(near_weapon.owned_payload_count_for_test(), 0, "reset payload callback cannot resurrect a Rift zone")
	_suite.assert_equal(
		(near_fixture["sink"] as RecordingSink).results.size(),
		sink_count_after_reset,
		"reset payload callback never reaches the Runtime sink"
	)
	_suite.assert_equal(near_weapon.feedback_facts_for_test(), [], "reset payload callback emits no combat feedback fact")
	await _cleanup_nodes([near_target])
	await _cleanup_fixture(near_fixture)

	var far_fixture := await _runtime_fixture()
	var far_runtime: RefCounted = far_fixture["runtime"]
	var far_weapon: Node = far_fixture["weapon"]
	_suite.assert_true(_restore_combo_for_test(far_runtime, 30), "far Rift fixture restores thirty Combo")
	var far_context := _runtime_context(9302)
	far_context["time_interactions"] = {
		"rift_active": true,
		"rift_generation": 302,
		"active_rifts": [{"generation": 302, "center": Vector2(1000.0, 0.0), "radius": 8.0}],
	}
	var far_plan: Dictionary = far_runtime.plan_intent(
		{"id": "weapon_skill", "edge": "pressed"}, far_context
	).get("plan", {})
	_suite.assert_close(float(far_plan.get("resource_costs", {}).get("time_energy", 0.0)), 20.0, "far owned Rift leaves real Shatter cost unchanged")
	_suite.assert_true(bool(far_runtime.commit_action(far_plan, 931).get("ok", false)), "far owned Rift stages real Shatter")
	far_runtime.on_phase_enter(far_plan, &"ACTIVE", 931)
	var far_target := _target(9931, Vector2(96.0, 0.0))
	far_weapon.owned_payloads_for_test()[0].execute_target_for_test(far_target)
	var far_payloads: Array[Node] = far_weapon.owned_payloads_for_test()
	_suite.assert_equal(far_payloads.size(), 2, "far owned Rift still materializes the base real Shatter zone")
	if far_payloads.size() == 2:
		var far_zone: Dictionary = far_payloads[1].execution_snapshot()
		var far_parameters := far_zone.get("parameters", {}) as Dictionary
		_suite.assert_close(float(far_parameters.get("radius_tiles", 0.0)), 2.5, "far owned Rift leaves real zone radius unchanged")
		_suite.assert_equal(far_parameters.get("duration_frames"), 300, "far owned Rift leaves real zone duration unchanged")
		_suite.assert_equal(far_parameters.get("rift_source_generation", 0), 0, "far owned Rift does not claim real zone ownership")
	far_weapon.reset_runtime_state()
	_suite.assert_equal(far_weapon.owned_payload_count_for_test(), 0, "far Rift reset clears every real payload")
	await _cleanup_nodes([far_target])
	await _cleanup_fixture(far_fixture)

	var invalid_fixture := await _runtime_fixture()
	var invalid_runtime: RefCounted = invalid_fixture["runtime"]
	var invalid_weapon: Node = invalid_fixture["weapon"]
	_suite.assert_true(_restore_combo_for_test(invalid_runtime, 30), "invalid Rift fixture restores thirty Combo")
	for time_context: Dictionary in [
		{
			"rift_active": true,
			"rift_generation": 0,
			"active_rifts": [{"generation": 303, "center": Vector2(96.0, 0.0), "radius": 8.0}],
		},
		{
			"rift_active": true,
			"rift_generation": 304,
			"active_rifts": [{"generation": 305, "center": Vector2(96.0, 0.0), "radius": 8.0}],
		},
	]:
		var invalid_context := _runtime_context(9303)
		invalid_context["time_interactions"] = time_context
		_suite.assert_equal(
			invalid_runtime.plan_intent({"id": "weapon_skill", "edge": "pressed"}, invalid_context).get("code"),
			&"INVALID_CONTEXT",
			"invalid Rift generation fails closed before real Adapter staging"
		)
		_suite.assert_equal(invalid_weapon.prepared_payload_count_for_test(), 0, "invalid Rift generation stages no real payload")
		_suite.assert_equal(invalid_weapon.owned_payload_count_for_test(), 0, "invalid Rift generation owns no real payload")
	await _cleanup_fixture(invalid_fixture)


func _test_runtime_rift_plan_freezes_combo_and_generation() -> void:
	var fixture := await _runtime_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var weapon: Node = fixture["weapon"]
	_suite.assert_true(_restore_combo_for_test(runtime, 30), "frozen Rift fixture restores thirty Combo")
	var context := _runtime_context(9351)
	context["time_interactions"] = {
		"rift_active": true,
		"rift_generation": 351,
		"active_rifts": [{"generation": 351, "center": Vector2(96.0, 0.0), "radius": 8.0}],
	}
	var plan: Dictionary = runtime.plan_intent(
		{"id": "weapon_skill", "edge": "pressed"}, context
	).get("plan", {})
	_suite.assert_close(float(plan.get("resource_costs", {}).get("time_energy", 0.0)), 14.0, "planned owned Rift freezes its reduced cost")
	runtime.reset_combo()
	_suite.assert_equal(int(runtime.snapshot().get("combo_count", -1)), 0, "live Combo can change after the plan is frozen")
	_suite.assert_true(bool(runtime.commit_action(plan, 935).get("ok", false)), "frozen Rift plan commits after live Combo reset")
	runtime.on_phase_enter(plan, &"ACTIVE", 935)
	var target := _target(9935, Vector2(96.0, 0.0))
	weapon.owned_payloads_for_test()[0].execute_target_for_test(target)
	var payloads: Array[Node] = weapon.owned_payloads_for_test()
	_suite.assert_equal(payloads.size(), 2, "frozen Rift plan still materializes its owned zone")
	if payloads.size() == 2:
		var zone_snapshot: Dictionary = payloads[1].execution_snapshot()
		var parameters := zone_snapshot.get("parameters", {}) as Dictionary
		_suite.assert_close(float(parameters.get("radius_tiles", 0.0)), 3.75, "frozen Rift keeps its 1.5x radius after Combo reset")
		_suite.assert_equal(parameters.get("duration_frames"), 450, "frozen Rift keeps its 1.5x duration after Combo reset")
		_suite.assert_equal(parameters.get("rift_source_generation"), 351, "frozen Rift keeps the originally authorized generation")
	await _cleanup_nodes([target])
	await _cleanup_fixture(fixture)


func _test_combo_slow_aura_source_generation_and_cleanup() -> void:
	var fixture := await _fixture()
	var owner: Node = fixture["owner"]
	var health: Node = fixture["health"]
	var weapon: Node = fixture["weapon"]
	var target := _target(9001, Vector2(120.0, 0.0))
	target.apply_time_rift(&"foreign_slow", 0.7)
	_suite.assert_true(weapon.set_combo_slow_aura(true, 91), "thirty-Combo tier activates one source-aware aura")
	var aura_snapshot: Dictionary = weapon.combo_slow_aura_snapshot_for_test()
	_suite.assert_true(bool(aura_snapshot.get("visual_visible", false)), "active thirty-Combo aura has a real visible presentation")
	_suite.assert_close(float(aura_snapshot.get("visual_radius_pixels", 0.0)), 128.0, "aura visual matches the authoritative two-tile slow radius")
	_suite.assert_equal(aura_snapshot.get("visual_ring_count"), 2, "aura uses two readable pixel rings instead of an invisible gameplay-only node")
	weapon.advance_combo_slow_aura_for_test(1)
	_suite.assert_close(float(target.rift_sources.get(&"gauntlets_combo_aura:91", 0.0)), 0.85, "Combo aura slows targets within two tiles to eighty-five percent")
	_suite.assert_true(not weapon.set_combo_slow_aura(false, 90), "stale tier generation cannot clear the live aura")
	_suite.assert_true(target.rift_sources.has(&"gauntlets_combo_aura:91"), "stale cleanup preserves the live source")
	_suite.assert_true(weapon.set_combo_slow_aura(true, 92), "new tier generation replaces the prior aura")
	_suite.assert_true(not target.rift_sources.has(&"gauntlets_combo_aura:91"), "generation replacement removes only the prior aura source")
	weapon.advance_combo_slow_aura_for_test(1)
	_suite.assert_true(target.rift_sources.has(&"gauntlets_combo_aura:92"), "replacement aura owns its new source generation")
	target.global_position = Vector2(129.0, 0.0)
	weapon.advance_combo_slow_aura_for_test(1)
	_suite.assert_true(not target.rift_sources.has(&"gauntlets_combo_aura:92"), "target leaving the two-tile boundary clears the aura immediately")
	target.global_position = Vector2(64.0, 0.0)
	weapon.advance_combo_slow_aura_for_test(1)
	_suite.assert_true(target.rift_sources.has(&"gauntlets_combo_aura:92"), "target re-entry reapplies the exact source")
	weapon.reset_runtime_state()
	_suite.assert_true(not target.rift_sources.has(&"gauntlets_combo_aura:92"), "runtime reset clears the live Combo aura source")
	_suite.assert_true(target.rift_sources.has(&"foreign_slow"), "runtime reset preserves unrelated slow ownership")
	_suite.assert_equal(weapon.combo_slow_aura_snapshot_for_test(), {}, "runtime reset removes aura execution state")
	_suite.assert_true(weapon.set_combo_slow_aura(true, 93), "fresh runtime generation can reactivate the aura after reset")
	weapon.advance_combo_slow_aura_for_test(1)
	_suite.assert_true(target.rift_sources.has(&"gauntlets_combo_aura:93"), "reactivated aura owns only its fresh generation")
	health.lose_health(health.current_hp, self)
	_suite.assert_true(not target.rift_sources.has(&"gauntlets_combo_aura:93"), "owner death clears the Combo aura synchronously")
	_suite.assert_true(target.rift_sources.has(&"foreign_slow"), "owner death preserves unrelated slow ownership")
	_suite.assert_equal(weapon.combo_slow_aura_snapshot_for_test(), {}, "death removes the aura execution state")
	_suite.assert_true(is_instance_valid(owner), "aura cleanup does not dispose its owner fixture")
	await _cleanup_nodes([target])
	await _cleanup_fixture(fixture)


func _fixture() -> Dictionary:
	var owner := Node2D.new()
	owner.name = "GauntletsOwner"
	add_child(owner)
	var health = HealthComponentScript.new()
	health.name = "HealthComponent"
	health.max_hp = 100.0
	owner.add_child(health)
	var weapon = GauntletsWeaponScript.new()
	weapon.name = "GauntletsWeapon"
	weapon.owner_path = NodePath("..")
	owner.add_child(weapon)
	var sink := RecordingSink.new()
	_suite.assert_true(weapon.configure_result_sink(sink), "Gauntlets adapter accepts a runtime result sink")
	await get_tree().process_frame
	return {"owner": owner, "health": health, "weapon": weapon, "sink": sink}


func _runtime_fixture() -> Dictionary:
	var fixture := await _fixture()
	var definition := _catalog_profile("gauntlets_launch_v1")
	var profile = WeaponRuntimeProfileScript.new()
	var parsed: Dictionary = profile.configure(definition)
	var capabilities := PackedStringArray(definition.get("capabilities", []))
	var modifiers = WeaponModifierStateScript.new()
	var bounds: Dictionary = {}
	for capability: String in capabilities:
		bounds[capability] = {"minimum": 0.1, "maximum": 200.0}
	var runtime = GauntletsWeaponRuntimeScript.new()
	_suite.assert_true(bool(parsed.get("ok", false)), "real Adapter fixture parses the frozen profile")
	_suite.assert_true(modifiers.configure(capabilities, bounds), "real Adapter fixture configures modifiers")
	_suite.assert_true(runtime.configure(fixture["owner"], profile, modifiers), "real Runtime configures the real Gauntlets Adapter")
	fixture["runtime"] = runtime
	return fixture


func _runtime_context(run_seed: int) -> Dictionary:
	return {
		"run_seed": run_seed,
		"aim_direction": Vector2.RIGHT,
		"dash_completion_token": 0,
		"frames_since_dash_completion": -1,
		"dash_direction": Vector2.RIGHT,
		"player_generation": 1,
		"time_interactions": {},
	}


func _restore_combo_for_test(runtime: RefCounted, combo_count: int) -> bool:
	var restored: Dictionary = runtime.snapshot()
	var combo := (restored.get("combo_state", {}) as Dictionary).duplicate(true)
	combo["combo_count"] = combo_count
	combo["combo_timeout_frames_remaining"] = 120 if combo_count > 0 else 0
	combo["combo_timeout_cap_frames"] = 120
	restored["combo_state"] = combo
	restored["combo_count"] = combo_count
	restored["combo_remaining_frames"] = 120 if combo_count > 0 else 0
	restored["aura_source_generation"] = 1 if combo_count >= 30 else 0
	return runtime.restore_snapshot(restored)


func _grant_runtime_combo_for_test(runtime: RefCounted, amount: int, token_seed: int) -> bool:
	for index: int in range(amount):
		var token := token_seed + index
		var plan: Dictionary = runtime.plan_intent(
			{"id": "weapon_primary", "edge": "released", "held_frames": 0},
			_runtime_context(14000 + token)
		).get("plan", {})
		if not bool(runtime.commit_action(plan, token).get("ok", false)):
			return false
		var result: Dictionary = runtime.handle_payload_result(token, token, {
			"type": "damage_resolved",
			"target_id": 24000 + token,
			"outcome_id": "aura_grant:%d" % index,
			"damage": 1.0,
			"hit_confirmed": true,
			"terminal": true,
		})
		if not bool(result.get("ok", false)):
			return false
		runtime.finish_action(token)
	return int(runtime.snapshot().get("combo_count", 0)) == amount


func _payload_snapshots(payloads: Array[Node]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for payload: Node in payloads:
		if payload != null and is_instance_valid(payload) and payload.has_method("execution_snapshot"):
			result.append((payload.call("execution_snapshot") as Dictionary).duplicate(true))
	return result


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


func _definition(action_id: String, token: int, descriptors: Array, source_generation: int = -1) -> Dictionary:
	var generation := token if source_generation <= 0 else source_generation
	var frozen_descriptors: Array = descriptors.duplicate(true)
	for descriptor_value: Variant in frozen_descriptors:
		if not descriptor_value is Dictionary:
			continue
		var descriptor := descriptor_value as Dictionary
		descriptor["token"] = token
		descriptor["generation"] = generation
	return {
		"token": token,
		"generation": generation,
		"profile_id": "gauntlets_launch_v1",
		"weapon_id": "gauntlets",
		"action_id": action_id,
		"semantic_action": "weapon_primary",
		"aim_direction": Vector2.RIGHT,
		"base_attack": 6.0,
		"payload_descriptors": frozen_descriptors,
		"time_interactions": [],
		"boss_conversion": {
			"conversion_id": "gauntlets_poised_launch",
			"allowed_states": ["RECOVERY", "EXPOSED"],
			"active_attack_policy": "preserve_committed",
			"poise_multiplier": 1.4,
			"airborne": false,
		},
		"invulnerable_during_cast": false,
	}


func _descriptor(kind: String, outcome_index: int, parameters: Dictionary) -> Dictionary:
	return {
		"descriptor_id": "gauntlets_%s_%d" % [kind, outcome_index],
		"kind": kind,
		"token": 1,
		"generation": 1,
		"outcome_id": "gauntlets_%s:%d" % [kind, outcome_index],
		"outcome_index": outcome_index,
		"seed": 1000 + outcome_index,
		"target_deduplication": "per_action_target",
		"parameters": parameters.duplicate(true),
	}


func _target(stable_id: int, position: Vector2) -> RecordingTarget:
	var target := RecordingTarget.new()
	target.set_meta("stable_target_id", stable_id)
	target.global_position = position
	target.add_to_group("enemies")
	add_child(target)
	return target


func _cleanup_fixture(fixture: Dictionary) -> void:
	var weapon_value: Variant = fixture.get("weapon")
	if weapon_value is Node and is_instance_valid(weapon_value):
		(weapon_value as Node).call("reset_runtime_state")
	var owner_value: Variant = fixture.get("owner")
	if owner_value is Node and is_instance_valid(owner_value):
		(owner_value as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _cleanup_nodes(nodes: Array) -> void:
	for node_value: Variant in nodes:
		if node_value is Node and is_instance_valid(node_value):
			(node_value as Node).queue_free()
	await get_tree().process_frame
