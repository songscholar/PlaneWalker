extends Node

const StaffProjectileScene := preload("res://scenes/combat/staff_projectile.tscn")
const StaffSpellZoneScene := preload("res://scenes/combat/staff_spell_zone.tscn")
const StaffWeaponScript := preload("res://scripts/combat/staff_weapon.gd")
const StaffWeaponRuntimeScript := preload("res://scripts/combat/weapons/staff_weapon_runtime.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")
const EnemyChaserScene := preload("res://scenes/enemies/enemy_chaser.tscn")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class ResultSink extends RefCounted:
	var results: Array[Dictionary] = []


	func handle_payload_result(token: int, generation: int, result: Dictionary) -> Dictionary:
		results.append({
			"token": token,
			"generation": generation,
			"result": result.duplicate(true),
		})
		return {"ok": true}


class RuntimeResultSink extends RefCounted:
	var results: Array[Dictionary] = []
	var response: Dictionary = {"ok": true, "combo": {}}


	func handle_payload_result(token: int, generation: int, result: Dictionary) -> Dictionary:
		results.append({
			"token": token,
			"generation": generation,
			"result": result.duplicate(true),
		})
		return response.duplicate(true)


class ReportStateObserver extends RefCounted:
	var weapon: Node
	var runtime_sink: RefCounted
	var records: Array[Dictionary] = []


	func _init(configured_weapon: Node, configured_runtime_sink: RefCounted) -> void:
		weapon = configured_weapon
		runtime_sink = configured_runtime_sink


	func handle_payload_result(token: int, generation: int, result: Dictionary) -> void:
		records.append({
			"token": token,
			"generation": generation,
			"result": result.duplicate(true),
			"runtime_result_count": runtime_sink.results.size(),
			"runtime_snapshot": weapon.runtime_snapshot(),
		})


class ZoneCompletionObserver extends RefCounted:
	var zone: Node
	var records: Array[Dictionary] = []


	func _init(configured_zone: Node) -> void:
		zone = configured_zone


	func handle_payload_result(_token: int, _generation: int, result: Dictionary) -> void:
		if str(result.get("type", "")) != "zone_complete":
			return
		var snapshot: Dictionary = zone.execution_snapshot()
		records.append({
			"result": result.duplicate(true),
			"snapshot": snapshot,
			"restorable": zone.can_restore_execution_snapshot(snapshot),
		})


class RecordingDamageTarget extends Node2D:
	var received: Array[RefCounted] = []


	func receive_hit(damage_info: RefCounted) -> float:
		received.append(damage_info)
		return float(damage_info.amount)


class RewardOwner extends Node2D:
	var reward_claims: Dictionary = {}


	func claim_weapon_action_reward(token: int, reward_kind: StringName) -> bool:
		var key := "%d:%s" % [token, str(reward_kind)]
		if token <= 0 or reward_kind == &"" or reward_claims.has(key):
			return false
		reward_claims[key] = true
		return true


	func on_staff_resource_reward_requested(
		token: int,
		claim_id: StringName,
		reward_id: StringName,
		amount: float
	) -> void:
		if reward_id != &"time_energy" or not claim_weapon_action_reward(token, claim_id):
			return
		var time_manager := get_node_or_null("TimeManager")
		if time_manager != null and time_manager.has_method("restore_energy"):
			time_manager.call("restore_energy", amount)


class RecordingTimeManager extends Node:
	var energy: float = 0.0
	var max_energy: float = 100.0


	func restore_energy(amount: float) -> void:
		energy = minf(max_energy, energy + maxf(0.0, amount))


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_basic_projectile_confirms_once()
	_test_adapter_normalizes_runtime_result()
	_test_reported_result_observes_complete_authoritative_state()
	_test_real_derived_damage_returns_mana_from_resolved_amounts()
	_test_adapter_requires_runtime_combo_confirmation()
	_test_real_adapter_near_expiry_late_hit_refunds_without_zone()
	_test_fire_result_freezes_explosion_and_burn()
	_test_fire_executes_spatial_damage_and_owned_burn_on_real_enemies()
	_test_ice_zone_ticks_exactly_and_cleans_up()
	_test_ice_zone_executes_damage_slow_freeze_and_departure_cleanup()
	_test_lightning_chain_is_distance_then_stable_id_and_deduplicated()
	_test_lightning_chain_executes_real_damage_and_owned_shock()
	_test_lightning_first_combos_use_first_cast_origins()
	await _test_killed_lightning_chain_targets_preserve_frozen_origins()
	_test_all_six_combination_descriptors_execute()
	_test_all_six_combinations_execute_real_damage_and_statuses()
	_test_blind_seed_uses_stable_action_target_material_once()
	_test_planar_collapse_and_seeded_ultimate_damage_real_enemies()
	_test_stop_collapse_scaling_and_six_tile_aim_offset()
	_test_rift_combination_expands_area_and_adds_time_damage()
	_test_lightning_first_rift_uses_frozen_origins()
	_test_ultimate_invulnerability_and_per_tick_time_energy()
	_test_construction_failure_reports_once_and_is_atomic()
	_test_terminal_results_are_exactly_once()
	_test_zone_completion_snapshot_is_terminal_before_emit()
	_test_staff_damage_info_freezes_action_identity()
	_test_seeded_ultimate_has_twenty_repeatable_ticks()
	_test_adapter_reset_clears_persistent_projectile_statuses()
	_test_cancel_scans_only_matching_staff_status_source()
	_test_runtime_bookkeeping_remains_bounded_across_long_session()
	_test_reset_rejects_stale_payload_callbacks()
	_test_payload_execution_snapshot_restore_preserves_progress_and_claims()
	_test_runtime_snapshot_restore_is_atomic_with_real_adapter()
	_test_released_derived_payload_snapshot_restores()
	_test_transient_status_restore_fails_when_target_is_missing()
	await get_tree().create_timer(0.25).timeout
	_suite.finish(get_tree())


func _test_basic_projectile_confirms_once() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var sink: ResultSink = fixture["sink"]
	var definition := _definition("arcane_bolt", [_projectile_descriptor("staff_arcane_bolt", {})])
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "basic Staff projectile constructs")
	_suite.assert_true(weapon.release_profile_action(), "basic Staff projectile releases")
	var projectile: Node = _first_payload(weapon, "StaffProjectile")
	_suite.assert_true(projectile != null, "basic release owns a StaffProjectile")
	if projectile != null:
		projectile.hit_for_test(101, [])
		projectile.hit_for_test(101, [])
	var hits := _results_of_type(sink, "hit_confirmed")
	_suite.assert_equal(hits.size(), 1, "basic projectile reports one hit for repeated target entry")
	if hits.size() == 1:
		_suite.assert_equal(hits[0].get("target_id"), 101, "basic hit preserves stable target identity")
		_suite.assert_equal(hits[0].get("element_id"), "arcane", "basic hit reports arcane identity")
	_free_fixture(fixture)


func _test_adapter_normalizes_runtime_result() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var runtime_sink: RuntimeResultSink = fixture["runtime_sink"]
	var fire := {
		"element_id": "fire",
		"damage_multiplier": 4.0,
		"explosion_radius_tiles": 2.5,
		"burn_duration_frames": 240,
		"burn_tick_interval_frames": 30,
		"burn_damage_multiplier": 0.1,
	}
	var definition := _definition("charged_element", [_projectile_descriptor("staff_element_cast", fire, "typed_element")])
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "normalized runtime fixture constructs")
	_suite.assert_true(weapon.release_profile_action(), "normalized runtime fixture releases")
	var projectile: Node = _first_payload(weapon, "StaffProjectile")
	if projectile != null:
		var resolved := {
			"type": "damage_resolved",
			"claim_id": "damage:0:fire_splash:fire:151",
			"descriptor_id": "staff_element_cast",
			"outcome_index": 0,
			"outcome_id": "staff_element_cast:0",
			"target_id": 151,
			"element_id": "fire",
			"element": "fire",
			"terminal": false,
			"hit": true,
			"damage": 12.5,
			"damage_scope": "fire_splash",
			"impact_position": Vector2(32.0, 16.0),
		}
		projectile.payload_result.emit(77, 4, resolved)
		projectile.payload_result.emit(77, 4, resolved)
		projectile.hit_for_test(151, [])
	_suite.assert_equal(runtime_sink.results.size(), 2, "adapter reports one non-terminal damage packet and one terminal hit exactly once")
	if runtime_sink.results.size() == 2:
		var derived: Dictionary = runtime_sink.results[0].get("result", {})
		_suite.assert_equal(derived.get("outcome_id"), "staff_element_cast:0:fire_splash:fire", "derived damage freezes a target-independent effect outcome")
		_suite.assert_true(not bool(derived.get("terminal", true)), "derived damage remains non-terminal")
		_suite.assert_close(float(derived.get("damage", 0.0)), 12.5, "derived runtime result uses actual resolved damage")
		var normalized: Dictionary = runtime_sink.results[1].get("result", {})
		_suite.assert_equal(normalized.get("outcome_id"), "staff_element_cast:0", "runtime outcome identity is target-independent")
		_suite.assert_equal(normalized.get("element"), "fire", "runtime result maps element identity")
		_suite.assert_equal(normalized.get("target_id"), 151, "runtime result maps stable target identity")
		_suite.assert_true(bool(normalized.get("terminal", false)), "projectile hit is terminal for its outcome")
		_suite.assert_true(not bool(normalized.get("hit", true)), "zero resolved primary damage preserves the actual miss flag")
		_suite.assert_close(float(normalized.get("damage", -1.0)), 0.0, "terminal runtime result never substitutes configured projectile damage")
	_free_fixture(fixture)


func _test_reported_result_observes_complete_authoritative_state() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var runtime_sink: RuntimeResultSink = fixture["runtime_sink"]
	runtime_sink.response = {
		"ok": true,
		"combo": {
			"combo_id": "steam_burst",
			"kind": "explosion",
			"parameters": {
				"radius_tiles": 3.5,
				"damage_multiplier": 2.0,
				"damage_split": {"fire": 0.5, "ice": 0.5},
				"blind_duration_frames": 90,
				"blind_miss_chance": 0.25,
			},
		},
	}
	var observer := ReportStateObserver.new(weapon, runtime_sink)
	weapon.payload_result_reported.connect(observer.handle_payload_result)
	var ice := {
		"element_id": "ice",
		"damage_multiplier": 2.5,
		"zone_radius_tiles": 3.0,
		"zone_duration_frames": 300,
		"zone_tick_interval_frames": 30,
		"zone_damage_multiplier": 0.08,
		"move_speed_multiplier": 0.5,
		"attack_speed_multiplier": 0.7,
		"freeze_duration_frames": 60,
	}
	var definition := _definition(
		"charged_element",
		[_projectile_descriptor("staff_observable_ice", ice, "typed_element")]
	)
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "observable Staff result fixture constructs")
	_suite.assert_true(weapon.release_profile_action(), "observable Staff result fixture releases")
	var projectile := _first_payload(weapon, "StaffProjectile")
	if projectile != null:
		projectile.hit_for_test(152, [])
	_suite.assert_equal(observer.records.size(), 1, "terminal Staff hit reports one observable result")
	if observer.records.size() == 1:
		var record: Dictionary = observer.records[0]
		var snapshot: Dictionary = record.get("runtime_snapshot", {})
		_suite.assert_equal(record.get("runtime_result_count"), 1, "runtime reducer completes before the public result signal")
		_suite.assert_true(
			(snapshot.get("callback_claims", {}) as Dictionary).has("77:4:hit:0:152"),
			"callback claim is committed before the public result signal"
		)
		var modes: Array[String] = []
		var kinds: Array[String] = []
		for payload_value: Variant in snapshot.get("owned_payloads", []):
			var payload_snapshot := payload_value as Dictionary
			kinds.append(str(payload_snapshot.get("kind", "")))
			var execution := payload_snapshot.get("execution", {}) as Dictionary
			modes.append(str(execution.get("mode", "")))
		modes.sort()
		_suite.assert_equal(kinds, ["zone", "zone"], "terminal projectile cleanup precedes the public result signal")
		_suite.assert_equal(modes, ["combination", "ice_zone"], "result and confirmed combination zones exist before the public result signal")
	_free_fixture(fixture)


func _test_real_derived_damage_returns_mana_from_resolved_amounts() -> void:
	var fixture := _runtime_weapon_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var weapon: Node = fixture["weapon"]
	var primary := _real_enemy(Vector2(96.0, 0.0), 1000.0, 161)
	var splash := _real_enemy(Vector2(96.0, 32.0), 1000.0, 162)
	var plan: Dictionary = runtime.plan_intent(
		{"id": "weapon_primary", "edge": "released", "held_frames": 30},
		_staff_runtime_context(15161)
	).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(plan, 1516).get("ok", false)), "resolved-damage Mana fixture commits Fire")
	_suite.assert_equal(runtime.on_phase_enter(plan, &"ACTIVE", 1516).size(), 2, "resolved-damage Mana fixture releases Fire")
	var projectile := _latest_projectile(weapon)
	if projectile != null:
		projectile.call("_on_area_entered", primary.get_node("Hurtbox"))
	_suite.assert_close(float(primary.health.current_hp), 964.0, "primary receives the real resolved Fire packet")
	_suite.assert_close(float(splash.health.current_hp), 964.0, "splash target receives the real resolved derived packet")
	_suite.assert_close(
		float(runtime.snapshot().get("mana", 0.0)),
		81.44,
		"primary and derived resolved damage each return two percent Mana without configured-damage substitution"
	)
	runtime.finish_action(1516)
	weapon.reset_runtime_state()
	_free_real_enemies([primary, splash])
	_free_runtime_weapon_fixture(fixture)


func _test_adapter_requires_runtime_combo_confirmation() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var runtime_sink: RuntimeResultSink = fixture["runtime_sink"]
	var steam := {
		"combo_id": "steam_burst",
		"first": "fire",
		"second": "ice",
		"kind": "explosion",
		"extra_mana": 15.0,
		"parameters": {
			"radius_tiles": 3.5,
			"damage_multiplier": 3.0,
			"damage_split": {"fire": 0.5, "ice": 0.5},
			"blind_duration_frames": 180,
			"blind_miss_chance": 0.3,
		},
	}
	var ice := {
		"element_id": "ice",
		"damage_multiplier": 2.5,
		"zone_radius_tiles": 3.0,
		"zone_duration_frames": 300,
		"zone_tick_interval_frames": 30,
		"zone_damage_multiplier": 0.08,
		"move_speed_multiplier": 0.5,
		"attack_speed_multiplier": 0.7,
		"freeze_duration_frames": 60,
		"combination": steam,
	}
	var definition := _definition(
		"charged_element",
		[_projectile_descriptor("staff_element_cast", ice, "typed_element")]
	)
	runtime_sink.response = {
		"ok": true,
		"combo": {},
		"refunded_mana": 15.0,
	}
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "near-expiry adapter fixture constructs")
	_suite.assert_true(weapon.release_profile_action(), "near-expiry adapter fixture releases")
	var projectile: Node = _first_payload(weapon, "StaffProjectile")
	if projectile != null:
		projectile.hit_for_test(152, [])
	_suite.assert_true(
		_combination_zone(weapon, "steam_burst") == null,
		"late hit cannot create a combination zone when runtime has expired and refunded it"
	)
	_free_fixture(fixture)


func _test_real_adapter_near_expiry_late_hit_refunds_without_zone() -> void:
	var fixture := _runtime_weapon_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var weapon: Node = fixture["weapon"]
	var fire_plan: Dictionary = runtime.plan_intent(
		{"id": "weapon_primary", "edge": "released", "held_frames": 30},
		_staff_runtime_context(15201)
	).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(fire_plan, 1521).get("ok", false)), "real near-expiry Fire opener commits")
	_suite.assert_equal(runtime.on_phase_enter(fire_plan, &"ACTIVE", 1521).size(), 2, "real near-expiry Fire opener releases")
	var fire_projectile := _latest_projectile(weapon)
	var opener_target := _real_enemy(Vector2(96.0, 0.0), 1000.0, 15201)
	if fire_projectile != null:
		fire_projectile.call("_on_area_entered", opener_target.get_node("Hurtbox"))
	runtime.finish_action(1521)
	_set_runtime_element(runtime, &"ice", 1522)
	runtime.advance_runtime_frame(0)
	runtime.advance_runtime_frame(298)
	var ice_plan: Dictionary = runtime.plan_intent(
		{"id": "weapon_primary", "edge": "released", "held_frames": 30},
		_staff_runtime_context(15202)
	).get("plan", {})
	_suite.assert_equal(ice_plan.get("combo_window_remaining_frames"), 2, "real adapter freezes the near-expiry window")
	_suite.assert_true(bool(runtime.commit_action(ice_plan, 1525).get("ok", false)), "real near-expiry Ice cast commits")
	_suite.assert_equal(runtime.on_phase_enter(ice_plan, &"ACTIVE", 1525).size(), 2, "real near-expiry Ice cast releases")
	var ice_projectile := _latest_projectile(weapon)
	runtime.finish_action(1525)
	runtime.advance_runtime_frame(300)
	var after_expiry: Dictionary = runtime.snapshot()
	_suite.assert_equal(after_expiry.get("pending_combos"), {}, "real adapter expiry closes and refunds its reservation")
	var mana_after_expiry := float(after_expiry.get("mana", 0.0))
	var late_target := _real_enemy(Vector2(192.0, 0.0), 1000.0, 15202)
	if ice_projectile != null:
		ice_projectile.call("_on_area_entered", late_target.get_node("Hurtbox"))
	_suite.assert_true(_combination_zone(weapon, "steam_burst") == null, "real late projectile cannot bypass runtime combo expiry")
	_suite.assert_close(
		float(runtime.snapshot().get("mana", 0.0)),
		mana_after_expiry + 0.45,
		"real late hit returns only normal damage Mana and cannot refund twice"
	)
	_free_real_enemies([opener_target, late_target])
	_free_runtime_weapon_fixture(fixture)


func _test_fire_result_freezes_explosion_and_burn() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var sink: ResultSink = fixture["sink"]
	var fire := {
		"element_id": "fire",
		"explosion_radius_tiles": 2.5,
		"burn_duration_frames": 240,
		"burn_tick_interval_frames": 30,
		"burn_damage_multiplier": 0.1,
	}
	var definition := _definition("charged_element", [_projectile_descriptor("staff_element_cast", fire, "typed_element")])
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "Fire charged spell constructs")
	_suite.assert_true(weapon.release_profile_action(), "Fire charged spell releases")
	var projectile: Node = _first_payload(weapon, "StaffProjectile")
	if projectile != null:
		projectile.hit_for_test(201, [])
	var hits := _results_of_type(sink, "hit_confirmed")
	_suite.assert_equal(hits.size(), 1, "Fire spell confirms once")
	if hits.size() == 1:
		var effects: Array = hits[0].get("effect_descriptors", [])
		var explosion := _dictionary_by_id(effects, "effect_id", "fire_explosion")
		var burn := _dictionary_by_id(effects, "effect_id", "burn")
		_suite.assert_close(float(explosion.get("parameters", {}).get("radius_tiles", 0.0)), 2.5, "Fire freezes its explosion radius")
		_suite.assert_equal(burn.get("parameters", {}).get("duration_frames"), 240, "Fire freezes burn duration")
		_suite.assert_equal(burn.get("parameters", {}).get("tick_interval_frames"), 30, "Fire freezes burn interval")
		_suite.assert_close(float(burn.get("parameters", {}).get("damage_multiplier", 0.0)), 0.1, "Fire freezes burn damage")
	_free_fixture(fixture)


func _test_fire_executes_spatial_damage_and_owned_burn_on_real_enemies() -> void:
	var primary := _real_enemy(Vector2.ZERO, 1000.0, 201)
	var nearby := _real_enemy(Vector2(64.0, 0.0), 1000.0, 202)
	var outside := _real_enemy(Vector2(192.0, 0.0), 1000.0, 203)
	var projectile: Node = StaffProjectileScene.instantiate()
	var execution := _projectile_execution(401, "fire", {
		"damage": 36.0,
		"effect_descriptor": {
			"explosion_radius_tiles": 2.5,
			"burn_duration_frames": 240,
			"burn_tick_interval_frames": 30,
			"burn_damage_multiplier": 0.1,
		},
	})
	_suite.assert_true(projectile.configure_execution(execution), "real Fire projectile configures")
	add_child(projectile)
	projectile.call("_on_area_entered", primary.get_node("Hurtbox"))
	var source_id := _staff_status_source(88, "staff_arcane_bolt", 0)
	_suite.assert_close(float(primary.health.current_hp), 964.0, "Fire primary takes one resolved explosion hit")
	_suite.assert_close(float(nearby.health.current_hp), 964.0, "Fire explosion damages a nearby real enemy once")
	_suite.assert_close(float(outside.health.current_hp), 1000.0, "Fire explosion excludes enemies outside its radius")
	_suite.assert_true(primary.has_elemental_status(&"burn", source_id, 5), "Fire owns burn on the primary target")
	_suite.assert_true(nearby.has_elemental_status(&"burn", source_id, 5), "Fire owns burn on nearby explosion targets")
	for _frame: int in range(30):
		primary.call("_tick_elemental_status_runtime")
	_suite.assert_close(float(primary.health.current_hp), 963.0, "Fire burn tick honors the shared one-damage minimum at frame thirty")
	_free_real_enemies([primary, nearby, outside])


func _test_ice_zone_ticks_exactly_and_cleans_up() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var sink: ResultSink = fixture["sink"]
	var ice := {
		"element_id": "ice",
		"zone_radius_tiles": 3.0,
		"zone_duration_frames": 300,
		"zone_tick_interval_frames": 30,
		"zone_damage_multiplier": 0.08,
		"move_speed_multiplier": 0.5,
		"attack_speed_multiplier": 0.7,
		"freeze_duration_frames": 60,
	}
	var definition := _definition("charged_element", [_projectile_descriptor("staff_element_cast", ice, "typed_element")])
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "Ice charged spell constructs")
	_suite.assert_true(weapon.release_profile_action(), "Ice charged spell releases")
	var projectile: Node = _first_payload(weapon, "StaffProjectile")
	if projectile != null:
		projectile.hit_for_test(301, [])
	var zone: Node = _first_payload(weapon, "StaffSpellZone")
	_suite.assert_true(zone != null, "Ice impact creates one owned zone")
	if zone != null:
		zone.advance_execution_for_test(300)
		zone.advance_execution_for_test(60)
	var ticks := _results_of_type(sink, "zone_tick")
	var completions := _results_of_type(sink, "zone_complete")
	_suite.assert_equal(ticks.size(), 10, "300-frame Ice zone ticks exactly ten times at thirty-frame intervals")
	_suite.assert_equal(completions.size(), 1, "Ice zone completes exactly once")
	if not ticks.is_empty():
		_suite.assert_equal(ticks.front().get("execution_frame"), 30, "first Ice tick occurs at frame thirty")
		_suite.assert_equal(ticks.back().get("execution_frame"), 300, "final Ice tick occurs at frame three hundred")
	weapon.reset_runtime_state()
	_suite.assert_equal(weapon.owned_payload_count_for_test(), 0, "Staff reset clears the completed Ice zone ownership")
	_free_fixture(fixture)


func _test_ice_zone_executes_damage_slow_freeze_and_departure_cleanup() -> void:
	var enemy := _real_enemy(Vector2.ZERO, 1000.0, 301)
	var zone: Node = StaffSpellZoneScene.instantiate()
	var execution := _zone_execution(501, "ice_zone", {
		"radius_tiles": 3.0,
		"duration_frames": 300,
		"tick_interval_frames": 30,
		"damage_multiplier": 0.08,
		"move_speed_multiplier": 0.5,
		"attack_speed_multiplier": 0.7,
		"freeze_duration_frames": 60,
	})
	_suite.assert_true(zone.configure_execution(execution), "real Ice zone configures")
	add_child(zone)
	zone.global_position = Vector2.ZERO
	zone.advance_execution_for_test(30)
	var source_id := _staff_status_source(99, "staff_zone", 0)
	_suite.assert_close(float(enemy.health.current_hp), 999.0, "Ice zone tick honors the shared one-damage minimum")
	_suite.assert_true(enemy.has_elemental_status(&"slow", source_id, 6), "Ice zone applies source-generation slow while inside")
	enemy.global_position = Vector2(256.0, 0.0)
	zone.advance_execution_for_test(1)
	_suite.assert_true(not enemy.has_elemental_status(&"slow", source_id, 6), "Ice zone clears its exact slow when a target leaves")
	enemy.global_position = Vector2.ZERO
	zone.advance_execution_for_test(269)
	_suite.assert_close(float(enemy.health.current_hp), 990.0, "Ice zone resolves exactly ten real damage ticks")
	_suite.assert_true(not enemy.has_elemental_status(&"slow", source_id, 6), "Ice zone clears slow when the field completes")
	_suite.assert_true(enemy.has_elemental_status(&"freeze", source_id, 6), "Ice zone applies its terminal owned freeze")
	_free_real_enemies([enemy])


func _test_lightning_chain_is_distance_then_stable_id_and_deduplicated() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var sink: ResultSink = fixture["sink"]
	var lightning := {
		"element_id": "lightning",
		"additional_target_count": 3,
		"chain_range_tiles": 4.0,
		"chain_damage_multiplier": 0.7,
		"chain_order": "distance_then_stable_target_id",
	}
	var definition := _definition("charged_element", [_projectile_descriptor("staff_element_cast", lightning, "typed_element")])
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "Lightning charged spell constructs")
	_suite.assert_true(weapon.release_profile_action(), "Lightning charged spell releases")
	var projectile: Node = _first_payload(weapon, "StaffProjectile")
	var candidates := [
		{"target_id": 40, "distance_tiles": 2.0},
		{"target_id": 30, "distance_tiles": 1.0},
		{"target_id": 20, "distance_tiles": 1.0},
		{"target_id": 20, "distance_tiles": 0.5},
		{"target_id": 50, "distance_tiles": 4.5},
		{"target_id": 10, "distance_tiles": 0.1},
	]
	if projectile != null:
		projectile.hit_for_test(10, candidates)
	var hits := _results_of_type(sink, "hit_confirmed")
	_suite.assert_equal(hits.size(), 1, "Lightning cast reports one primary result")
	if hits.size() == 1:
		_suite.assert_equal(hits[0].get("chain_target_ids"), [20, 30, 40], "Lightning sorts by distance then stable target id and removes duplicates")
	_free_fixture(fixture)


func _test_lightning_chain_executes_real_damage_and_owned_shock() -> void:
	var primary := _real_enemy(Vector2.ZERO, 1000.0, 10)
	var second := _real_enemy(Vector2(64.0, 0.0), 1000.0, 20)
	var third := _real_enemy(Vector2(64.0, 0.0), 1000.0, 30)
	var fourth := _real_enemy(Vector2(128.0, 0.0), 1000.0, 40)
	var outside := _real_enemy(Vector2(320.0, 0.0), 1000.0, 50)
	var sink := ResultSink.new()
	var projectile: Node = StaffProjectileScene.instantiate()
	projectile.payload_result.connect(sink.handle_payload_result)
	var execution := _projectile_execution(601, "lightning", {
		"damage": 27.0,
		"effect_descriptor": {
			"shock_duration_frames": 180,
			"shock_bonus_damage_multiplier": 0.1,
		},
		"chain": {
			"additional_target_count": 3,
			"chain_range_tiles": 4.0,
			"chain_damage_multiplier": 0.7,
			"chain_order": "distance_then_stable_target_id",
		},
	})
	_suite.assert_true(projectile.configure_execution(execution), "real Lightning projectile configures")
	add_child(projectile)
	projectile.call("_on_area_entered", primary.get_node("Hurtbox"))
	var hits := _results_of_type(sink, "hit_confirmed")
	_suite.assert_equal(hits.size(), 1, "real Lightning cast reports one terminal hit")
	if hits.size() == 1:
		_suite.assert_equal(hits[0].get("chain_target_ids"), [20, 30, 40], "real Lightning chain preserves deterministic distance/id order")
	_suite.assert_close(float(primary.health.current_hp), 973.0, "Lightning primary takes full damage once")
	for target: Node in [second, third, fourth]:
		_suite.assert_close(float(target.health.current_hp), 981.1, "Lightning chain target takes seventy-percent damage once")
	var source_id := _staff_status_source(88, "staff_arcane_bolt", 0)
	for target: Node in [primary, second, third, fourth]:
		_suite.assert_true(target.has_elemental_status(&"shock", source_id, 5), "Lightning owns shock on every confirmed target")
	_suite.assert_close(float(outside.health.current_hp), 1000.0, "Lightning excludes targets beyond chain range")
	_free_real_enemies([primary, second, third, fourth, outside])


func _test_lightning_first_combos_use_first_cast_origins() -> void:
	_test_lightning_first_combo_real_execution(&"fire", "thunder_flare", 14.85, &"")
	_test_lightning_first_combo_real_execution(&"ice", "thunder_crystal", 11.88, &"freeze")


func _test_lightning_first_combo_real_execution(
	second_element: StringName,
	combo_id: String,
	expected_combo_damage: float,
	expected_status: StringName
) -> void:
	var fixture := _runtime_weapon_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var weapon: Node = fixture["weapon"]
	var primary := _real_enemy(Vector2.ZERO, 1000.0, 310)
	var first_chain := _real_enemy(Vector2(64.0, 0.0), 1000.0, 320)
	var second_chain := _real_enemy(Vector2(128.0, 0.0), 1000.0, 330)
	_set_runtime_element(runtime, &"lightning", 3100)
	var lightning_plan: Dictionary = runtime.plan_intent(
		{"id": "weapon_primary", "edge": "released", "held_frames": 30},
		_staff_runtime_context(31001)
	).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(lightning_plan, 3110).get("ok", false)), "real Lightning opener commits for %s" % combo_id)
	_suite.assert_equal(runtime.on_phase_enter(lightning_plan, &"ACTIVE", 3110).size(), 2, "real Lightning opener releases for %s" % combo_id)
	var lightning_projectile: Node = _first_payload(weapon, "StaffProjectile")
	if lightning_projectile != null:
		lightning_projectile.call("_on_area_entered", primary.get_node("Hurtbox"))
	runtime.finish_action(3110)
	_suite.assert_equal(runtime.snapshot().get("combo_element"), "lightning", "real Lightning hit opens the ordered window")

	_set_runtime_element(runtime, second_element, 3120)
	var second_plan: Dictionary = runtime.plan_intent(
		{"id": "weapon_primary", "edge": "released", "held_frames": 30},
		_staff_runtime_context(31002)
	).get("plan", {})
	_suite.assert_equal((second_plan.get("combo", {}) as Dictionary).get("combo_id"), combo_id, "%s plan binds the Lightning-first pair" % combo_id)
	_suite.assert_true(bool(runtime.commit_action(second_plan, 3130).get("ok", false)), "%s second cast commits" % combo_id)
	_suite.assert_equal(runtime.on_phase_enter(second_plan, &"ACTIVE", 3130).size(), 2, "%s second cast releases" % combo_id)
	var second_projectile: Node = _latest_projectile(weapon)
	var combo_impact := _real_enemy(Vector2(512.0, 0.0), 1000.0, 340)
	var hp_before_first := float(first_chain.health.current_hp)
	var hp_before_second := float(second_chain.health.current_hp)
	if second_projectile != null:
		second_projectile.call("_on_area_entered", combo_impact.get_node("Hurtbox"))
	var combo_zone := _combination_zone(weapon, combo_id)
	_suite.assert_true(combo_zone != null, "%s creates a runtime-confirmed live zone" % combo_id)
	if combo_zone != null:
		var parameters: Dictionary = combo_zone.execution_snapshot().get("parameters", {}).get("combo_parameters", {})
		_suite.assert_equal(parameters.get("origin_target_ids"), [320, 330], "%s preserves first-cast chain ids" % combo_id)
		_suite.assert_equal(
			parameters.get("origin_positions"),
			[Vector2(64.0, 0.0), Vector2(128.0, 0.0)],
			"%s preserves first-cast stable positions" % combo_id
		)
		combo_zone.advance_execution_for_test(60)
	_suite.assert_close(float(first_chain.health.current_hp), hp_before_first - expected_combo_damage, "%s damages the first Lightning chain origin" % combo_id)
	_suite.assert_close(float(second_chain.health.current_hp), hp_before_second - expected_combo_damage, "%s damages the second Lightning chain origin" % combo_id)
	if expected_status != &"":
		var source_id := _staff_status_source(3130, "staff_element_cast:%s" % combo_id, 0)
		_suite.assert_true(first_chain.has_elemental_status(expected_status, source_id, 3130), "%s applies its origin status to the first chain target" % combo_id)
		_suite.assert_true(second_chain.has_elemental_status(expected_status, source_id, 3130), "%s applies its origin status to the second chain target" % combo_id)
	runtime.finish_action(3130)
	_free_real_enemies([primary, first_chain, second_chain, combo_impact])
	_free_runtime_weapon_fixture(fixture)


func _test_killed_lightning_chain_targets_preserve_frozen_origins() -> void:
	var fixture := _runtime_weapon_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var weapon: Node = fixture["weapon"]
	var primary := _real_enemy(Vector2.ZERO, 1000.0, 3410)
	var first_chain := _real_enemy(Vector2(64.0, 0.0), 10.0, 3420)
	var second_chain := _real_enemy(Vector2(128.0, 0.0), 10.0, 3430)
	_set_runtime_element(runtime, &"lightning", 34100)
	var opener: Dictionary = runtime.plan_intent(
		{"id": "weapon_primary", "edge": "released", "held_frames": 30},
		_staff_runtime_context(34101)
	).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(opener, 34110).get("ok", false)), "lethal Lightning opener commits")
	_suite.assert_equal(runtime.on_phase_enter(opener, &"ACTIVE", 34110).size(), 2, "lethal Lightning opener releases")
	var opener_projectile: Node = _latest_projectile(weapon)
	if opener_projectile != null:
		opener_projectile.call("_on_area_entered", primary.get_node("Hurtbox"))
	_suite.assert_true(first_chain.is_queued_for_deletion() or not first_chain.is_in_group("enemies"), "first lethal chain target leaves the live enemy group")
	_suite.assert_true(second_chain.is_queued_for_deletion() or not second_chain.is_in_group("enemies"), "second lethal chain target leaves the live enemy group")
	runtime.finish_action(34110)
	await get_tree().create_timer(0.25).timeout
	var first_witness := _real_enemy(Vector2(64.0, 0.0), 1000.0, 3440)
	var second_witness := _real_enemy(Vector2(128.0, 0.0), 1000.0, 3450)
	_set_runtime_element(runtime, &"fire", 34120)
	var finisher: Dictionary = runtime.plan_intent(
		{"id": "weapon_primary", "edge": "released", "held_frames": 30},
		_staff_runtime_context(34102)
	).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(finisher, 34130).get("ok", false)), "post-lethal thunder_flare commits")
	_suite.assert_equal(runtime.on_phase_enter(finisher, &"ACTIVE", 34130).size(), 2, "post-lethal thunder_flare releases")
	var finisher_projectile: Node = _latest_projectile(weapon)
	var impact := _real_enemy(Vector2(512.0, 0.0), 1000.0, 3460)
	if finisher_projectile != null:
		finisher_projectile.call("_on_area_entered", impact.get_node("Hurtbox"))
	var combo_zone := _combination_zone(weapon, "thunder_flare")
	_suite.assert_true(combo_zone != null, "killed chain targets cannot erase thunder_flare origins")
	if combo_zone != null:
		var parameters: Dictionary = combo_zone.execution_snapshot().get("parameters", {}).get("combo_parameters", {})
		_suite.assert_equal(parameters.get("origin_target_ids"), [3420, 3430], "lethal chain retains stable target ids")
		_suite.assert_equal(parameters.get("origin_positions"), [Vector2(64.0, 0.0), Vector2(128.0, 0.0)], "lethal chain retains frozen target positions")
		combo_zone.advance_execution_for_test(60)
	_suite.assert_true(float(first_witness.health.current_hp) < 1000.0, "first frozen origin still executes after its original target dies")
	_suite.assert_true(float(second_witness.health.current_hp) < 1000.0, "second frozen origin still executes after its original target dies")
	runtime.finish_action(34130)
	_free_real_enemies([primary, first_witness, second_witness, impact])
	_free_runtime_weapon_fixture(fixture)


func _test_all_six_combination_descriptors_execute() -> void:
	var combinations: Array = _staff_payload().get("parameters", {}).get("combinations", [])
	_suite.assert_equal(combinations.size(), 6, "authoritative Staff Profile exposes six ordered combinations")
	for index: int in range(combinations.size()):
		var combo: Dictionary = combinations[index]
		var sink := ResultSink.new()
		var zone: Node = StaffSpellZoneScene.instantiate()
		add_child(zone)
		zone.payload_result.connect(sink.handle_payload_result)
		var execution := _zone_execution(
			200 + index,
			"combination",
			{
				"combo_id": str(combo.get("combo_id", "")),
				"combo_kind": str(combo.get("kind", "")),
				"combo_parameters": (combo.get("parameters", {}) as Dictionary).duplicate(true),
			}
		)
		_suite.assert_true(zone.configure_execution(execution), "%s combination zone configures" % str(combo.get("combo_id", "")))
		zone.advance_execution_for_test(400)
		var resolved := _results_of_type(sink, "combination_resolved")
		_suite.assert_equal(resolved.size(), 1, "%s resolves exactly once" % str(combo.get("combo_id", "")))
		if resolved.size() == 1:
			_suite.assert_equal(resolved[0].get("combo_id"), combo.get("combo_id"), "combination result preserves stable combo id")
			_suite.assert_equal(resolved[0].get("combo_kind"), combo.get("kind"), "combination result preserves execution kind")
		zone.free()


func _test_all_six_combinations_execute_real_damage_and_statuses() -> void:
	_test_real_combination("steam_burst", "explosion", {
		"radius_tiles": 3.5,
		"damage_multiplier": 3.0,
		"damage_split": {"fire": 0.5, "ice": 0.5},
		"blind_duration_frames": 180,
		"blind_miss_chance": 0.3,
	}, 27.0, &"blind", 1)
	_test_real_combination("blazing_storm", "zone", {
		"radius_tiles": 3.0,
		"duration_frames": 60,
		"tick_interval_frames": 30,
		"fire_damage_multiplier": 0.8,
		"lightning_damage_multiplier": 0.6,
		"apply_burn": true,
	}, 12.6, &"burn", 60)
	_test_real_combination("crystal_thunder", "delayed_explosion", {
		"delay_frames": 30,
		"radius_tiles": 3.0,
		"ice_damage_multiplier": 2.5,
		"lightning_damage_multiplier": 2.0,
		"ice_surface_duration_frames": 60,
		"ice_surface_move_speed_multiplier": 0.3,
	}, 40.5, &"slow", 31)
	_test_real_combination("reverse_steam", "staged_zone_explosion", {
		"freeze_radius_tiles": 3.0,
		"freeze_duration_frames": 90,
		"delay_frames": 60,
		"explosion_radius_tiles": 3.5,
		"explosion_damage_multiplier": 3.0,
		"damage_split": {"fire": 0.5, "ice": 0.5},
		"blind_duration_frames": 180,
		"blind_miss_chance": 0.3,
	}, 27.0, &"blind", 60)
	_test_real_combination("thunder_flare", "chain_delayed_explosions", {
		"delay_frames": 60,
		"radius_tiles": 1.5,
		"fire_damage_multiplier": 1.5,
		"origin_policy": "confirmed_chain_targets",
		"origin_positions": [Vector2.ZERO],
	}, 13.5, &"", 60)
	_test_real_combination("thunder_crystal", "chain_delayed_crystals", {
		"delay_frames": 60,
		"radius_tiles": 1.5,
		"ice_damage_multiplier": 1.2,
		"freeze_duration_frames": 30,
		"origin_policy": "confirmed_chain_targets",
		"origin_positions": [Vector2.ZERO],
	}, 10.8, &"freeze", 60)


func _test_real_combination(
	combo_id: String,
	combo_kind: String,
	combo_parameters: Dictionary,
	expected_damage: float,
	expected_status: StringName,
	advance_frames: int
) -> void:
	var enemy := _real_enemy(Vector2.ZERO, 1000.0, 700 + combo_id.hash())
	var zone: Node = StaffSpellZoneScene.instantiate()
	var execution := _zone_execution(700 + combo_id.hash(), "combination", {
		"combo_id": combo_id,
		"combo_kind": combo_kind,
		"combo_parameters": combo_parameters.duplicate(true),
	})
	_suite.assert_true(zone.configure_execution(execution), "%s real combination configures" % combo_id)
	add_child(zone)
	zone.global_position = Vector2.ZERO
	zone.advance_execution_for_test(advance_frames)
	_suite.assert_close(float(enemy.health.current_hp), 1000.0 - expected_damage, "%s applies its authoritative real damage" % combo_id)
	if expected_status != &"":
		var source_id := _staff_status_source(99, "staff_zone", 0)
		_suite.assert_true(enemy.has_elemental_status(expected_status, source_id, 6), "%s applies its source-generation status" % combo_id)
	zone.reset_execution_state()
	if is_instance_valid(zone):
		zone.free()
	_free_real_enemies([enemy])


func _test_blind_seed_uses_stable_action_target_material_once() -> void:
	var first := _blind_seed_fixture(1001, 77001)
	var repeated := _blind_seed_fixture(1001, 77001)
	var other_target := _blind_seed_fixture(1002, 77001)
	_suite.assert_equal(first.get("seed"), repeated.get("seed"), "Blind seed ignores transient instance identity for the same action and target")
	_suite.assert_equal(first.get("results"), repeated.get("results"), "Blind outcomes replay for stable run/action/target material")
	_suite.assert_true(first.get("seed") != other_target.get("seed"), "Blind seed includes the stable target identity")
	_suite.assert_equal(first.get("seed"), first.get("seed_after_second_status"), "a later Blind status does not reset the enemy-wide deterministic seed")


func _blind_seed_fixture(stable_target_id: int, seed: int) -> Dictionary:
	var enemy := _real_enemy(Vector2.ZERO, 1000.0, stable_target_id)
	var parameters := {
		"combo_id": "steam_burst",
		"combo_kind": "explosion",
		"combo_parameters": {
			"radius_tiles": 3.5,
			"damage_multiplier": 3.0,
			"damage_split": {"fire": 0.5, "ice": 0.5},
			"blind_duration_frames": 180,
			"blind_miss_chance": 0.3,
		},
	}
	var zone: Node = StaffSpellZoneScene.instantiate()
	_suite.assert_true(zone.configure_execution(_zone_execution(seed, "combination", parameters)), "Blind deterministic seed fixture configures")
	add_child(zone)
	zone.advance_execution_for_test(1)
	var configured_seed := int(enemy.get_meta("elemental_status_seed_initialized", -1))
	var results: Array[bool] = []
	for action_sequence: int in range(24):
		results.append(enemy.elemental_status_runtime.should_blind_miss(action_sequence))
	var second_zone: Node = StaffSpellZoneScene.instantiate()
	var second_execution := _zone_execution(seed + 999, "combination", parameters)
	second_execution["generation"] = 7
	second_execution["descriptor_id"] = "staff_zone_second_blind"
	_suite.assert_true(second_zone.configure_execution(second_execution), "second Blind source configures")
	add_child(second_zone)
	second_zone.advance_execution_for_test(1)
	var seed_after_second_status := int(enemy.get_meta("elemental_status_seed_initialized", -2))
	if is_instance_valid(zone):
		zone.free()
	if is_instance_valid(second_zone):
		second_zone.free()
	_free_real_enemies([enemy])
	return {
		"seed": configured_seed,
		"seed_after_second_status": seed_after_second_status,
		"results": results,
	}


func _test_planar_collapse_and_seeded_ultimate_damage_real_enemies() -> void:
	var collapse_target := _real_enemy(Vector2.ZERO, 1000.0, 801)
	var collapse: Node = StaffSpellZoneScene.instantiate()
	var collapse_execution := _zone_execution(801, "planar_collapse", {
		"damage_multiplier": 3.2,
		"duration_frames": 180,
		"radius_tiles": 4.0,
		"ordinary_freeze_frames": 120,
		"boss_slow_multiplier": 0.3,
		"boss_slow_duration_frames": 60,
		"void_erosion_duration_frames": 360,
		"void_erosion_tick_interval_frames": 30,
		"void_erosion_damage_multiplier": 0.06,
	})
	_suite.assert_true(collapse.configure_execution(collapse_execution), "Plane Collapse real zone configures")
	add_child(collapse)
	collapse.global_position = Vector2.ZERO
	collapse.advance_execution_for_test(360)
	_suite.assert_close(float(collapse_target.health.current_hp), 959.2, "Plane Collapse executes impact plus twelve minimum-one erosion ticks")
	var collapse_source := _staff_status_source(99, "staff_zone", 0)
	_suite.assert_true(collapse_target.has_elemental_status(&"freeze", collapse_source, 6), "Plane Collapse owns ordinary-target freeze")
	_free_real_enemies([collapse_target])

	var ultimate_target := _real_enemy(Vector2.ZERO, 1000.0, 802)
	var ultimate: Node = StaffSpellZoneScene.instantiate()
	var ultimate_execution := _zone_execution(802, "seeded_sequence", {
		"damage_multiplier": 0.9,
		"count": 20,
		"tick_interval_frames": 6,
		"radius_tiles": 5.0,
		"elements": ["fire", "ice", "lightning"],
	})
	_suite.assert_true(ultimate.configure_execution(ultimate_execution), "Primordial Wrath real zone configures")
	add_child(ultimate)
	ultimate.global_position = Vector2.ZERO
	ultimate.advance_execution_for_test(120)
	_suite.assert_close(float(ultimate_target.health.current_hp), 838.0, "Primordial Wrath executes all twenty seeded damage ticks")
	_free_real_enemies([ultimate_target])


func _test_stop_collapse_scaling_and_six_tile_aim_offset() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node2D = fixture["weapon"]
	weapon.global_position = Vector2(100.0, 80.0)
	var collapse_parameters := {
		"damage_multiplier": 3.2,
		"duration_frames": 180,
		"radius_tiles": 4.0,
		"ordinary_freeze_frames": 120,
		"boss_slow_multiplier": 0.3,
		"boss_slow_duration_frames": 60,
		"void_erosion_duration_frames": 360,
		"void_erosion_tick_interval_frames": 30,
		"void_erosion_damage_multiplier": 0.06,
	}
	var definition := _definition(
		"planar_collapse",
		[_zone_descriptor("staff_planar_collapse", collapse_parameters)]
	)
	definition["aim_direction"] = Vector2.DOWN
	definition["time_interactions"] = [{
		"interaction_id": "staff_stop_field",
		"source_generation": 71,
		"area_multiplier": 1.5,
		"duration_multiplier": 1.5,
	}]
	definition["boss_conversion"] = _boss_conversion_fixture()
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "Stop Plane Collapse constructs")
	var snapshots: Array = weapon.prepared_payload_snapshots_for_test()
	var positions: Array = weapon.prepared_payload_positions_for_test()
	_suite.assert_equal(snapshots.size(), 1, "Stop Plane Collapse prepares one zone")
	if snapshots.size() == 1:
		var parameters: Dictionary = snapshots[0].get("parameters", {})
		_suite.assert_close(float(parameters.get("radius_tiles", 0.0)), 6.0, "Stop expands Plane Collapse radius by 1.5")
		_suite.assert_equal(int(parameters.get("duration_frames", 0)), 270, "Stop expands Plane Collapse field duration by 1.5")
		_suite.assert_equal(int(parameters.get("void_erosion_duration_frames", 0)), 540, "Stop expands Plane Collapse erosion duration by 1.5")
		_suite.assert_equal((snapshots[0].get("boss_conversion", {}) as Dictionary).get("conversion_id"), "staff_control_conversion", "Plane Collapse execution freezes Boss conversion policy")
	_suite.assert_equal(positions.size(), 1, "Stop Plane Collapse freezes one prepared target point")
	if positions.size() == 1:
		_suite.assert_equal(positions[0], Vector2(100.0, 464.0), "Plane Collapse lands exactly six tiles along frozen aim")
	_free_fixture(fixture)


func _test_rift_combination_expands_area_and_adds_time_damage() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var runtime_sink: RuntimeResultSink = fixture["runtime_sink"]
	var enemy := _real_enemy(Vector2.ZERO, 1000.0, 811)
	var steam := {
		"combo_id": "steam_burst",
		"kind": "explosion",
		"parameters": {
			"radius_tiles": 3.5,
			"damage_multiplier": 3.0,
			"damage_split": {"fire": 0.5, "ice": 0.5},
			"blind_duration_frames": 180,
			"blind_miss_chance": 0.3,
		},
	}
	var ice := {
		"element_id": "ice",
		"damage_multiplier": 2.5,
		"zone_radius_tiles": 3.0,
		"zone_duration_frames": 300,
		"zone_tick_interval_frames": 30,
		"zone_damage_multiplier": 0.08,
		"move_speed_multiplier": 0.5,
		"attack_speed_multiplier": 0.7,
		"freeze_duration_frames": 60,
		"combination": steam,
	}
	var definition := _definition(
		"charged_element",
		[_projectile_descriptor("staff_element_cast", ice, "typed_element")]
	)
	definition["time_interactions"] = [{
		"interaction_id": "staff_rift_combination",
		"source_generation": 82,
		"combo_id": "steam_burst",
		"area_multiplier": 1.3,
		"time_damage_multiplier": 0.5,
		"spatial_policy": "zone_intersection",
		"active_rifts": [{
			"generation": 82,
			"center": Vector2(316.0, 0.0),
			"radius": 92.0,
		}],
	}]
	runtime_sink.response = {"ok": true, "combo": steam.duplicate(true)}
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "Rift Staff combination constructs")
	_suite.assert_true(weapon.release_profile_action(), "Rift Staff combination releases")
	var projectile: Node = _first_payload(weapon, "StaffProjectile")
	if projectile != null:
		projectile.call("_on_area_entered", enemy.get_node("Hurtbox"))
	var combo_zone := _combination_zone(weapon, "steam_burst")
	_suite.assert_true(combo_zone != null, "Rift hit creates a live combination zone")
	if combo_zone != null:
		var combo_parameters: Dictionary = combo_zone.execution_snapshot().get("parameters", {}).get("combo_parameters", {})
		_suite.assert_close(float(combo_parameters.get("radius_tiles", 0.0)), 4.55, "Rift expands the combination radius by 1.3")
		_suite.assert_close(float(combo_parameters.get("time_damage_multiplier", 0.0)), 0.5, "Rift freezes the added Time damage multiplier")
		combo_zone.advance_execution_for_test(1)
	_suite.assert_close(float(enemy.health.current_hp), 946.0, "Rift Steam Burst adds one bounded base-attack Time packet")
	weapon.reset_runtime_state()
	_free_real_enemies([enemy])
	_free_fixture(fixture)
	_test_non_intersecting_and_stale_rifts_do_not_empower_combo(steam, ice)


func _test_non_intersecting_and_stale_rifts_do_not_empower_combo(steam: Dictionary, ice: Dictionary) -> void:
	for case: Dictionary in [
		{"label": "far", "source_generation": 83, "descriptor_generation": 83, "center": Vector2(2000.0, 0.0)},
		{"label": "stale", "source_generation": 84, "descriptor_generation": 83, "center": Vector2.ZERO},
	]:
		var fixture := _weapon_fixture()
		var weapon: Node = fixture["weapon"]
		var runtime_sink: RuntimeResultSink = fixture["runtime_sink"]
		var enemy := _real_enemy(Vector2.ZERO, 1000.0, 812 + int(case["source_generation"]))
		var definition := _definition(
			"charged_element",
			[_projectile_descriptor("staff_element_cast", ice, "typed_element")]
		)
		definition["time_interactions"] = [{
			"interaction_id": "staff_rift_combination",
			"source_generation": int(case["source_generation"]),
			"combo_id": "steam_burst",
			"area_multiplier": 1.3,
			"time_damage_multiplier": 0.5,
			"spatial_policy": "zone_intersection",
			"active_rifts": [{
				"generation": int(case["descriptor_generation"]),
				"center": case["center"],
				"radius": 92.0,
			}],
		}]
		runtime_sink.response = {"ok": true, "combo": steam.duplicate(true)}
		_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "%s Rift combination constructs" % case["label"])
		_suite.assert_true(weapon.release_profile_action(), "%s Rift combination releases" % case["label"])
		var projectile: Node = _first_payload(weapon, "StaffProjectile")
		if projectile != null:
			projectile.call("_on_area_entered", enemy.get_node("Hurtbox"))
		var combo_zone := _combination_zone(weapon, "steam_burst")
		_suite.assert_true(combo_zone != null, "%s Rift still creates the ordinary combination zone" % case["label"])
		if combo_zone != null:
			var combo_parameters: Dictionary = combo_zone.execution_snapshot().get("parameters", {}).get("combo_parameters", {})
			_suite.assert_close(float(combo_parameters.get("radius_tiles", 0.0)), 3.5, "%s Rift cannot expand a non-intersecting generation" % case["label"])
			_suite.assert_true(not combo_parameters.has("time_damage_multiplier"), "%s Rift cannot add Time damage" % case["label"])
		weapon.reset_runtime_state()
		_free_real_enemies([enemy])
		_free_fixture(fixture)


func _test_lightning_first_rift_uses_frozen_origins() -> void:
	var raw_combo := {
		"combo_id": "thunder_flare",
		"first": "lightning",
		"second": "fire",
		"kind": "chain_delayed_explosions",
		"parameters": {
			"delay_frames": 60,
			"radius_tiles": 1.5,
			"fire_damage_multiplier": 1.5,
			"origin_policy": "confirmed_chain_targets",
		},
	}
	for case: Dictionary in [
		{
			"label": "second-impact-only",
			"source_generation": 91,
			"descriptor_generation": 91,
			"rift_center": Vector2(28.0, 0.0),
			"origins": [Vector2(1000.0, 0.0), Vector2(1200.0, 0.0)],
			"empowered": false,
		},
		{
			"label": "first-origin",
			"source_generation": 92,
			"descriptor_generation": 92,
			"rift_center": Vector2(640.0, 0.0),
			"origins": [Vector2(640.0, 0.0), Vector2(1200.0, 0.0)],
			"empowered": true,
		},
		{
			"label": "stale-origin",
			"source_generation": 93,
			"descriptor_generation": 92,
			"rift_center": Vector2(640.0, 0.0),
			"origins": [Vector2(640.0, 0.0), Vector2(1200.0, 0.0)],
			"empowered": false,
		},
	]:
		var fixture := _weapon_fixture()
		var weapon: Node = fixture["weapon"]
		var runtime_sink: RuntimeResultSink = fixture["runtime_sink"]
		var fire := {
			"element_id": "fire",
			"damage_multiplier": 4.0,
			"combination": raw_combo.duplicate(true),
		}
		var definition := _definition(
			"charged_element",
			[_projectile_descriptor("staff_element_cast", fire, "typed_element")]
		)
		definition["time_interactions"] = [{
			"interaction_id": "staff_rift_combination",
			"source_generation": int(case["source_generation"]),
			"combo_id": "thunder_flare",
			"area_multiplier": 1.3,
			"time_damage_multiplier": 0.5,
			"spatial_policy": "zone_intersection",
			"active_rifts": [{
				"generation": int(case["descriptor_generation"]),
				"center": case["rift_center"],
				"radius": 32.0,
			}],
		}]
		var confirmed := raw_combo.duplicate(true)
		var confirmed_parameters := (confirmed["parameters"] as Dictionary).duplicate(true)
		confirmed_parameters["origin_target_ids"] = [501, 502]
		confirmed_parameters["origin_positions"] = (case["origins"] as Array).duplicate()
		confirmed["parameters"] = confirmed_parameters
		runtime_sink.response = {"ok": true, "combo": confirmed}
		_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "%s Lightning-first Rift fixture constructs" % case["label"])
		_suite.assert_true(weapon.release_profile_action(), "%s Lightning-first Rift fixture releases" % case["label"])
		var projectile: Node = _first_payload(weapon, "StaffProjectile")
		if projectile != null:
			projectile.hit_for_test(503, [])
		var combo_zone := _combination_zone(weapon, "thunder_flare")
		_suite.assert_true(combo_zone != null, "%s creates its ordinary combo zone" % case["label"])
		if combo_zone != null:
			var parameters: Dictionary = combo_zone.execution_snapshot().get("parameters", {}).get("combo_parameters", {})
			var expected_radius := 1.95 if bool(case["empowered"]) else 1.5
			_suite.assert_close(float(parameters.get("radius_tiles", 0.0)), expected_radius, "%s uses frozen origins for Rift area" % case["label"])
			_suite.assert_equal(parameters.has("time_damage_multiplier"), bool(case["empowered"]), "%s gates Rift Time damage by frozen origin intersection" % case["label"])
		weapon.reset_runtime_state()
		_free_fixture(fixture)


func _test_ultimate_invulnerability_and_per_tick_time_energy() -> void:
	var owner := RewardOwner.new()
	owner.name = "StaffRewardOwner"
	var health := HealthComponentScript.new()
	health.name = "HealthComponent"
	health.max_hp = 100.0
	owner.add_child(health)
	var time_manager := RecordingTimeManager.new()
	time_manager.name = "TimeManager"
	owner.add_child(time_manager)
	add_child(owner)
	var weapon := StaffWeaponScript.new()
	weapon.name = "StaffWeapon"
	owner.add_child(weapon)
	weapon.resource_reward_requested.connect(owner.on_staff_resource_reward_requested)
	var definition := _definition(
		"primordial_wrath",
		[_zone_descriptor("staff_primordial_wrath", {
			"damage_multiplier": 0.9,
			"count": 20,
			"tick_interval_frames": 6,
			"radius_tiles": 5.0,
			"time_energy_return_per_tick": 2.0,
			"elements": ["fire", "ice", "lightning"],
		}, "seeded_sequence")]
	)
	definition["invulnerable_during_cast"] = true
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "Primordial Wrath acquires cast invulnerability")
	_suite.assert_true(health.invulnerable, "Primordial Wrath owner is invulnerable during the committed cast")
	_suite.assert_true(weapon.release_profile_action(), "Primordial Wrath releases its sequence zone")
	var zone := _zone_by_mode(weapon, "seeded_sequence")
	_suite.assert_true(zone != null, "Primordial Wrath owns one seeded sequence zone")
	if zone != null:
		zone.advance_execution_for_test(12)
	_suite.assert_close(time_manager.energy, 4.0, "two ultimate ticks restore exactly four Time Energy")
	_suite.assert_equal(owner.reward_claims.size(), 2, "ultimate ticks use distinct exactly-once reward claims")
	var reward_snapshot: Dictionary = weapon.runtime_snapshot()
	if zone != null:
		zone.advance_execution_for_test(6)
	_suite.assert_close(time_manager.energy, 6.0, "third ultimate tick restores one additional reward")
	_suite.assert_true(weapon.restore_runtime_snapshot(reward_snapshot), "ultimate adapter restores the two-tick payload state")
	var restored_zone := _zone_by_mode(weapon, "seeded_sequence")
	if restored_zone != null:
		restored_zone.advance_execution_for_test(6)
	_suite.assert_close(time_manager.energy, 6.0, "restoring before an already claimed reward cannot grant it twice")
	_suite.assert_equal(owner.reward_claims.size(), 3, "owner reward claims remain the final exactly-once authority")
	if restored_zone != null:
		restored_zone.advance_execution_for_test(6)
	_suite.assert_close(time_manager.energy, 8.0, "restored ultimate continues with the next unclaimed reward")
	weapon.finish_profile_action()
	_suite.assert_true(not health.invulnerable, "finishing Primordial Wrath releases cast invulnerability")
	weapon.reset_runtime_state()
	owner.free()


func _test_construction_failure_reports_once_and_is_atomic() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var sink: ResultSink = fixture["sink"]
	var invalid := _projectile_descriptor("staff_arcane_bolt", {})
	invalid["parameters"] = {"element_id": "bogus"}
	invalid["kind"] = "unknown_payload_kind"
	var definition := _definition("arcane_bolt", [invalid])
	_suite.assert_true(weapon.begin_profile_action(definition).is_empty(), "malformed Staff payload construction fails closed")
	_suite.assert_equal(weapon.prepared_payload_count_for_test(), 0, "failed construction retains no partial payload")
	_suite.assert_true(not weapon.is_profile_action_active(), "failed construction retains no active adapter transaction")
	var failures := _results_of_type(sink, "construction_failed")
	_suite.assert_equal(failures.size(), 1, "construction failure reports exactly once")
	_free_fixture(fixture)


func _test_terminal_results_are_exactly_once() -> void:
	var projectile_sink := ResultSink.new()
	var projectile: Node = StaffProjectileScene.instantiate()
	add_child(projectile)
	projectile.payload_result.connect(projectile_sink.handle_payload_result)
	_suite.assert_true(projectile.configure_execution(_projectile_execution(301, "arcane", {})), "terminal projectile configures")
	projectile.complete_without_hit_for_test()
	projectile.complete_without_hit_for_test()
	_suite.assert_equal(_results_of_type(projectile_sink, "terminal_miss").size(), 1, "terminal_miss emits exactly once")
	projectile.free()

	var zone_sink := ResultSink.new()
	var zone: Node = StaffSpellZoneScene.instantiate()
	add_child(zone)
	zone.payload_result.connect(zone_sink.handle_payload_result)
	_suite.assert_true(zone.configure_execution(_zone_execution(302, "ice_zone", {
		"duration_frames": 60,
		"tick_interval_frames": 30,
		"radius_tiles": 2.0,
		"damage_multiplier": 0.1,
	})), "terminal zone configures")
	zone.advance_execution_for_test(60)
	zone.advance_execution_for_test(60)
	_suite.assert_equal(_results_of_type(zone_sink, "zone_complete").size(), 1, "zone_complete emits exactly once")
	zone.free()


func _test_zone_completion_snapshot_is_terminal_before_emit() -> void:
	var zone: Node = StaffSpellZoneScene.instantiate()
	add_child(zone)
	var observer := ZoneCompletionObserver.new(zone)
	zone.payload_result.connect(observer.handle_payload_result)
	_suite.assert_true(zone.configure_execution(_zone_execution(303, "ice_zone", {
		"duration_frames": 1,
		"tick_interval_frames": 1,
		"radius_tiles": 2.0,
		"damage_multiplier": 0.1,
	})), "terminal snapshot zone configures")
	zone.advance_execution_for_test(1)
	_suite.assert_equal(observer.records.size(), 1, "zone completion exposes one terminal snapshot")
	if observer.records.size() == 1:
		var record: Dictionary = observer.records[0]
		var snapshot: Dictionary = record.get("snapshot", {})
		_suite.assert_true(not bool(snapshot.get("execution_active", true)), "zone is inactive before completion is observed")
		_suite.assert_true(bool(snapshot.get("completion_emitted", false)), "zone completion claim is committed before it is observed")
		_suite.assert_true(bool(record.get("restorable", false)), "completion observer never captures an unrecoverable active/completed state")
		_suite.assert_true(bool((record.get("result", {}) as Dictionary).get("terminal", false)), "zone completion is marked terminal for adapter cleanup")
	if is_instance_valid(zone):
		zone.free()


func _test_staff_damage_info_freezes_action_identity() -> void:
	var projectile: Node = StaffProjectileScene.instantiate()
	_suite.assert_true(
		projectile.configure_execution(_projectile_execution(304, "arcane", {})),
		"identity projectile configures"
	)
	add_child(projectile)
	var projectile_target := RecordingDamageTarget.new()
	projectile_target.set_meta("stable_target_id", 30401)
	add_child(projectile_target)
	projectile.call("_execute_target_hit", projectile_target)
	_suite.assert_equal(projectile_target.received.size(), 1, "projectile delivers one typed DamageInfo")
	if projectile_target.received.size() == 1:
		_suite.assert_equal(projectile_target.received[0].action_token, 88, "projectile DamageInfo freezes action token")
		_suite.assert_equal(projectile_target.received[0].source_generation, 5, "projectile DamageInfo freezes source generation")

	var zone: Node = StaffSpellZoneScene.instantiate()
	_suite.assert_true(zone.configure_execution(_zone_execution(305, "ice_zone", {
		"duration_frames": 30,
		"tick_interval_frames": 30,
		"radius_tiles": 2.0,
		"damage_multiplier": 0.1,
	})), "identity zone configures")
	add_child(zone)
	var zone_target := RecordingDamageTarget.new()
	zone_target.set_meta("stable_target_id", 30501)
	add_child(zone_target)
	zone.call("_damage_target", zone_target, 3.0, "ice")
	_suite.assert_equal(zone_target.received.size(), 1, "zone delivers one typed DamageInfo")
	if zone_target.received.size() == 1:
		_suite.assert_equal(zone_target.received[0].action_token, 99, "zone DamageInfo freezes action token")
		_suite.assert_equal(zone_target.received[0].source_generation, 6, "zone DamageInfo freezes source generation")
	for node: Node in [projectile, projectile_target, zone, zone_target]:
		if is_instance_valid(node):
			node.free()


func _test_seeded_ultimate_has_twenty_repeatable_ticks() -> void:
	var first := _ultimate_results(99173)
	var second := _ultimate_results(99173)
	var different := _ultimate_results(99174)
	_suite.assert_equal(first.size(), 20, "Primordial Wrath resolves exactly twenty ticks")
	_suite.assert_equal(first, second, "same ultimate seed reproduces the exact element sequence")
	_suite.assert_true(first != different, "different ultimate seed changes the deterministic sequence")


func _test_adapter_reset_clears_persistent_projectile_statuses() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var enemy := _real_enemy(Vector2.ZERO, 1000.0, 901)
	var fire := {
		"element_id": "fire",
		"damage_multiplier": 4.0,
		"explosion_radius_tiles": 2.5,
		"burn_duration_frames": 240,
		"burn_tick_interval_frames": 30,
		"burn_damage_multiplier": 0.1,
	}
	var definition := _definition("charged_element", [_projectile_descriptor("staff_element_cast", fire, "typed_element")])
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "persistent status cleanup fixture constructs")
	_suite.assert_true(weapon.release_profile_action(), "persistent status cleanup fixture releases")
	var projectile: Node = _first_payload(weapon, "StaffProjectile")
	if projectile != null:
		projectile.call("_on_area_entered", enemy.get_node("Hurtbox"))
	var source_id := _staff_status_source(77, "staff_element_cast", 0)
	_suite.assert_true(enemy.has_elemental_status(&"burn", source_id, 4), "released Staff projectile owns a persistent burn")
	weapon.reset_runtime_state()
	_suite.assert_true(not enemy.has_elemental_status(&"burn", source_id, 4), "Staff reset clears exact persistent projectile ownership")
	_free_real_enemies([enemy])
	_free_fixture(fixture)


func _test_cancel_scans_only_matching_staff_status_source() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var enemy := _real_enemy(Vector2.ZERO, 1000.0, 902)
	var cancelled_source := _staff_status_source(77, "cancelled", 0)
	var other_staff_source := _staff_status_source(88, "other", 0)
	var foreign_source := &"sword:77:foreign:0"
	_suite.assert_true(enemy.apply_elemental_status(&"burn", cancelled_source, 4, 240, 1.0), "cancel cleanup fixture applies matching Staff status")
	_suite.assert_true(enemy.apply_elemental_status(&"shock", other_staff_source, 4, 240, 0.2), "cancel cleanup fixture applies another Staff action status")
	_suite.assert_true(enemy.apply_elemental_status(&"slow", foreign_source, 4, 240, 0.5), "cancel cleanup fixture applies foreign weapon status")
	var definition := _definition("arcane_bolt", [_projectile_descriptor("staff_arcane_bolt", {})])
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "cancel cleanup fixture opens the matching Staff action")
	weapon.cancel_profile_action()
	_suite.assert_true(not enemy.has_elemental_status(&"burn", cancelled_source, 4), "cancel scans and clears only its exact Staff token-generation source")
	_suite.assert_true(enemy.has_elemental_status(&"shock", other_staff_source, 4), "cancel preserves another Staff action source")
	_suite.assert_true(enemy.has_elemental_status(&"slow", foreign_source, 4), "cancel preserves non-Staff status ownership")
	weapon.reset_runtime_state()
	_suite.assert_true(not enemy.has_elemental_status(&"shock", other_staff_source, 4), "reset scans and clears remaining Staff-owned sources")
	_suite.assert_true(enemy.has_elemental_status(&"slow", foreign_source, 4), "reset preserves non-Staff status ownership")
	_free_real_enemies([enemy])
	_free_fixture(fixture)


func _test_runtime_bookkeeping_remains_bounded_across_long_session() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var definition := _definition(
		"primordial_wrath",
		[_zone_descriptor("staff_primordial_wrath", {
			"damage_multiplier": 0.9,
			"count": 530,
			"tick_interval_frames": 1,
			"radius_tiles": 5.0,
			"time_energy_return_per_tick": 2.0,
			"elements": ["fire", "ice", "lightning"],
		}, "seeded_sequence")]
	)
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "long-session Staff action constructs")
	_suite.assert_true(weapon.release_profile_action(), "long-session Staff action releases")
	var stale_zone := _zone_by_mode(weapon, "seeded_sequence")
	_suite.assert_true(stale_zone != null, "long-session fixture owns its seeded sequence zone")
	if stale_zone != null:
		stale_zone.advance_execution_for_test(530)
	var bounded: Dictionary = weapon.runtime_bookkeeping_snapshot_for_test()
	_suite.assert_equal(int(bounded.get("owned_payload_count", -1)), 0, "completed queued payloads are pruned from ownership")
	_suite.assert_equal(int(bounded.get("owned_payload_identity_count", -1)), 0, "completed queued payload identities are pruned")
	_suite.assert_equal(int(bounded.get("callback_claim_count", -1)), 512, "callback claims retain only the newest fixed-size window")
	_suite.assert_equal(int(bounded.get("resource_reward_claim_count", -1)), 128, "resource reward claims retain only the newest fixed-size window")
	var callback_count := int(bounded.get("callback_claim_count", -1))
	var reward_count := int(bounded.get("resource_reward_claim_count", -1))
	if stale_zone != null:
		stale_zone.payload_result.emit(77, 4, {
			"type": "ultimate_tick",
			"claim_id": "ultimate_tick:stale",
			"descriptor_id": "staff_primordial_wrath",
			"outcome_index": 0,
		})
		stale_zone.resource_reward_requested.emit(
			77,
			4,
			&"staff_ultimate_tick:stale",
			&"time_energy",
			2.0
		)
	var after_stale: Dictionary = weapon.runtime_bookkeeping_snapshot_for_test()
	_suite.assert_equal(int(after_stale.get("callback_claim_count", -1)), callback_count, "pruned stale payload cannot refill callback claims")
	_suite.assert_equal(int(after_stale.get("resource_reward_claim_count", -1)), reward_count, "pruned stale payload cannot refill reward claims")
	weapon.reset_runtime_state()
	var reset_snapshot: Dictionary = weapon.runtime_bookkeeping_snapshot_for_test()
	for field: String in [
		"owned_payload_count",
		"owned_payload_identity_count",
		"callback_claim_count",
		"resource_reward_claim_count",
	]:
		_suite.assert_equal(int(reset_snapshot.get(field, -1)), 0, "Staff reset clears bounded runtime field %s" % field)
	_free_fixture(fixture)


func _test_reset_rejects_stale_payload_callbacks() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var sink: ResultSink = fixture["sink"]
	var definition := _definition("arcane_bolt", [_projectile_descriptor("staff_arcane_bolt", {})])
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "stale callback fixture constructs")
	_suite.assert_true(weapon.release_profile_action(), "stale callback fixture releases")
	var projectile: Node = _first_payload(weapon, "StaffProjectile")
	weapon.reset_runtime_state()
	var before := sink.results.size()
	if projectile != null:
		projectile.hit_for_test(701, [])
		projectile.complete_without_hit_for_test()
	_suite.assert_equal(sink.results.size(), before, "reset-owned stale payload cannot report into the next runtime generation")
	_suite.assert_equal(weapon.owned_payload_count_for_test(), 0, "reset clears all owned Staff payloads")
	_free_fixture(fixture)


func _test_payload_execution_snapshot_restore_preserves_progress_and_claims() -> void:
	var projectile_sink := ResultSink.new()
	var projectile: Node = StaffProjectileScene.instantiate()
	add_child(projectile)
	projectile.payload_result.connect(projectile_sink.handle_payload_result)
	_suite.assert_true(projectile.configure_execution(_projectile_execution(17001, "arcane", {})), "projectile snapshot fixture configures")
	projectile.global_position = Vector2(96.0, 48.0)
	projectile.call("_physics_process", 0.25)
	var projectile_snapshot: Dictionary = projectile.execution_snapshot()
	var forged_projectile_snapshot := projectile_snapshot.duplicate(true)
	forged_projectile_snapshot["unexpected_authority"] = true
	_suite.assert_true(
		not projectile.can_restore_execution_snapshot(forged_projectile_snapshot),
		"projectile snapshot rejects unknown authoritative fields"
	)
	_suite.assert_true(
		not projectile.restore_execution_snapshot(forged_projectile_snapshot),
		"projectile restore rejects an unknown authoritative field"
	)
	_suite.assert_equal(
		projectile.execution_snapshot(),
		projectile_snapshot,
		"projectile unknown-field rejection is atomic"
	)
	var restored_projectile: Node = StaffProjectileScene.instantiate()
	add_child(restored_projectile)
	_suite.assert_true(restored_projectile.restore_execution_snapshot(projectile_snapshot), "projectile restores authoritative execution state")
	_suite.assert_equal(restored_projectile.execution_snapshot(), projectile_snapshot, "projectile restore preserves direction, distance and claims exactly")
	var terminal_sink := ResultSink.new()
	restored_projectile.payload_result.connect(terminal_sink.handle_payload_result)
	restored_projectile.hit_for_test(17003, [])
	var terminal_snapshot: Dictionary = restored_projectile.execution_snapshot()
	var terminal_restore: Node = StaffProjectileScene.instantiate()
	add_child(terminal_restore)
	terminal_restore.payload_result.connect(terminal_sink.handle_payload_result)
	_suite.assert_true(terminal_restore.restore_execution_snapshot(terminal_snapshot), "terminal projectile restores its hit claim")
	var terminal_count := terminal_sink.results.size()
	terminal_restore.hit_for_test(17003, [])
	_suite.assert_equal(terminal_sink.results.size(), terminal_count, "restored terminal projectile cannot repeat its claimed hit")
	projectile.reset_execution_state()
	projectile.free()
	if is_instance_valid(restored_projectile):
		restored_projectile.reset_execution_state()
		restored_projectile.free()
	terminal_restore.reset_execution_state()
	terminal_restore.free()

	var zone_sink := ResultSink.new()
	var zone: Node = StaffSpellZoneScene.instantiate()
	add_child(zone)
	zone.payload_result.connect(zone_sink.handle_payload_result)
	_suite.assert_true(zone.configure_execution(_zone_execution(17002, "seeded_sequence", {
		"damage_multiplier": 0.9,
		"count": 20,
		"tick_interval_frames": 6,
		"radius_tiles": 5.0,
		"time_energy_return_per_tick": 2.0,
		"elements": ["fire", "ice", "lightning"],
	})), "zone snapshot fixture configures")
	zone.call("_physics_process", 0.1)
	zone.advance_execution_for_test(6)
	var zone_snapshot: Dictionary = zone.execution_snapshot()
	var forged_zone_snapshot := zone_snapshot.duplicate(true)
	forged_zone_snapshot["unexpected_authority"] = true
	_suite.assert_true(
		not zone.can_restore_execution_snapshot(forged_zone_snapshot),
		"zone snapshot rejects unknown authoritative fields"
	)
	_suite.assert_true(
		not zone.restore_execution_snapshot(forged_zone_snapshot),
		"zone restore rejects an unknown authoritative field"
	)
	_suite.assert_equal(
		zone.execution_snapshot(),
		zone_snapshot,
		"zone unknown-field rejection is atomic"
	)
	var restored_zone: Node = StaffSpellZoneScene.instantiate()
	add_child(restored_zone)
	restored_zone.payload_result.connect(zone_sink.handle_payload_result)
	_suite.assert_true(restored_zone.restore_execution_snapshot(zone_snapshot), "zone restores authoritative execution state")
	_suite.assert_equal(restored_zone.execution_snapshot(), zone_snapshot, "zone restore preserves frames, fractional progress and claims exactly")
	var result_count_before := zone_sink.results.size()
	restored_zone.advance_execution_for_test(6)
	_suite.assert_equal(zone_sink.results.size(), result_count_before + 1, "restored zone emits only its next deterministic tick")
	zone.reset_execution_state()
	zone.free()
	restored_zone.reset_execution_state()
	restored_zone.free()


func _test_runtime_snapshot_restore_is_atomic_with_real_adapter() -> void:
	var fixture := _runtime_weapon_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var weapon: Node = fixture["weapon"]
	var plan: Dictionary = runtime.plan_intent(
		{"id": "weapon_primary", "edge": "released", "held_frames": 30},
		_staff_runtime_context(17101)
	).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(plan, 17110).get("ok", false)), "real Staff restore fixture commits")
	var windup_snapshot: Dictionary = runtime.snapshot()
	_suite.assert_equal(weapon.prepared_payload_count_for_test(), 1, "WINDUP owns one prepared payload")
	_suite.assert_equal(runtime.on_phase_enter(plan, &"ACTIVE", 17110).size(), 2, "real Staff restore fixture releases")
	var projectile := _latest_projectile(weapon)
	if projectile != null:
		projectile.call("_physics_process", 0.2)
	var active_snapshot: Dictionary = runtime.snapshot()
	var active_adapter: Dictionary = active_snapshot.get("adapter_snapshot", {})
	_suite.assert_equal((active_adapter.get("owned_payloads", []) as Array).size(), 1, "ACTIVE snapshot contains the live projectile")
	var forged_runtime_top_level := active_snapshot.duplicate(true)
	forged_runtime_top_level["unexpected_authority"] = true
	_suite.assert_true(
		not runtime.restore_snapshot(forged_runtime_top_level),
		"Staff Runtime rejects an unknown top-level snapshot field"
	)
	_suite.assert_equal(runtime.snapshot(), active_snapshot, "Staff Runtime top-level rejection is atomic")
	var forged_adapter_top_level := active_adapter.duplicate(true)
	forged_adapter_top_level["unexpected_authority"] = true
	_suite.assert_true(
		not weapon.can_restore_runtime_snapshot(forged_adapter_top_level),
		"Staff Adapter rejects an unknown top-level snapshot field"
	)
	_suite.assert_true(
		not weapon.restore_runtime_snapshot(forged_adapter_top_level),
		"Staff Adapter restore rejects an unknown top-level snapshot field"
	)
	_suite.assert_equal(weapon.runtime_snapshot(), active_adapter, "Staff Adapter top-level rejection is atomic")
	var forged_adapter_wrapper := active_adapter.duplicate(true)
	forged_adapter_wrapper["owned_payloads"][0]["unexpected_authority"] = true
	_suite.assert_true(
		not weapon.can_restore_runtime_snapshot(forged_adapter_wrapper),
		"Staff Adapter rejects an unknown payload-wrapper field"
	)
	_suite.assert_true(
		not weapon.restore_runtime_snapshot(forged_adapter_wrapper),
		"Staff Adapter restore rejects an unknown payload-wrapper field"
	)
	_suite.assert_equal(weapon.runtime_snapshot(), active_adapter, "Staff Adapter wrapper rejection is atomic")
	var forged_windup: Dictionary = windup_snapshot.duplicate(true)
	forged_windup["adapter_snapshot"]["prepared_payloads"][0]["execution"]["damage"] = 9999.0
	_suite.assert_true(not runtime.restore_snapshot(forged_windup), "prepared payload must match its committed descriptor exactly")
	_suite.assert_equal(runtime.snapshot(), active_snapshot, "forged prepared payload rejection is atomic")
	var forged_windup_position: Dictionary = windup_snapshot.duplicate(true)
	forged_windup_position["adapter_snapshot"]["prepared_payloads"][0]["global_position"] += Vector2(512.0, -256.0)
	_suite.assert_true(
		not runtime.restore_snapshot(forged_windup_position),
		"prepared payload position must match the authoritative committed payload position"
	)
	_suite.assert_equal(runtime.snapshot(), active_snapshot, "forged prepared position rejection is atomic")
	var forged_owned_identity := active_adapter.duplicate(true)
	forged_owned_identity["owned_payloads"][0]["execution"]["descriptor_id"] = "forged_staff_payload"
	_suite.assert_true(
		not weapon.can_restore_runtime_snapshot(forged_owned_identity),
		"released payload identity must belong to a committed descriptor"
	)
	_suite.assert_true(
		not weapon.restore_runtime_snapshot(forged_owned_identity),
		"released payload restore rejects an uncommitted descriptor identity"
	)
	_suite.assert_equal(weapon.runtime_snapshot(), active_adapter, "forged released identity rejection is atomic")
	var forged_owned_execution := active_adapter.duplicate(true)
	forged_owned_execution["owned_payloads"][0]["execution"]["damage"] = 9999.0
	_suite.assert_true(
		not weapon.can_restore_runtime_snapshot(forged_owned_execution),
		"released payload execution must remain bound to its committed descriptor"
	)
	_suite.assert_true(
		not weapon.restore_runtime_snapshot(forged_owned_execution),
		"released payload restore rejects forged committed execution parameters"
	)
	_suite.assert_equal(weapon.runtime_snapshot(), active_adapter, "forged released execution rejection is atomic")
	var forged_owned_count := active_adapter.duplicate(true)
	var injected_payload := (forged_owned_count["owned_payloads"][0] as Dictionary).duplicate(true)
	injected_payload["execution"]["descriptor_id"] = "injected_staff_payload"
	forged_owned_count["owned_payloads"].append(injected_payload)
	_suite.assert_true(
		not weapon.can_restore_runtime_snapshot(forged_owned_count),
		"released payload count is bounded by committed descriptor lineages"
	)
	_suite.assert_true(
		not weapon.restore_runtime_snapshot(forged_owned_count),
		"released payload restore rejects an injected additional payload"
	)
	_suite.assert_equal(weapon.runtime_snapshot(), active_adapter, "forged released count rejection is atomic")
	_suite.assert_true(runtime.restore_snapshot(windup_snapshot), "ACTIVE restores the exact prepared WINDUP state")
	_suite.assert_equal(runtime.snapshot(), windup_snapshot, "WINDUP restore is deterministic")
	_suite.assert_equal(weapon.prepared_payload_count_for_test(), 1, "restored WINDUP recreates its prepared payload")
	_suite.assert_true(runtime.restore_snapshot(active_snapshot), "WINDUP restores the exact ACTIVE payload state")
	_suite.assert_equal(runtime.snapshot(), active_snapshot, "ACTIVE restore is deterministic")
	_suite.assert_equal(weapon.owned_payload_count_for_test(), 1, "restored ACTIVE recreates its live projectile")

	runtime.on_phase_enter(plan, &"RECOVERY", 17110)
	var recovery_snapshot: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.restore_snapshot(active_snapshot), "RECOVERY restores the exact ACTIVE payload state")
	_suite.assert_true(runtime.restore_snapshot(recovery_snapshot), "ACTIVE restores the exact RECOVERY payload state")
	_suite.assert_equal(runtime.snapshot(), recovery_snapshot, "RECOVERY restore preserves the live projectile")

	var before_malformed: Dictionary = runtime.snapshot()
	var malformed := before_malformed.duplicate(true)
	malformed["adapter_snapshot"]["owned_payloads"][0]["execution"]["distance_travelled"] = -1.0
	_suite.assert_true(not runtime.restore_snapshot(malformed), "malformed adapter payload snapshot fails closed")
	_suite.assert_equal(runtime.snapshot(), before_malformed, "malformed restore leaves runtime and live payload unchanged")
	var install_failure: Dictionary = weapon.runtime_snapshot()
	install_failure["profile_action"]["invulnerable_during_cast"] = true
	_suite.assert_true(weapon.can_restore_runtime_snapshot(install_failure), "application-failure fixture passes structural prevalidation")
	_suite.assert_true(not weapon.restore_runtime_snapshot(install_failure), "failed restored invulnerability acquisition rolls back")
	_suite.assert_equal(weapon.runtime_snapshot(), before_malformed["adapter_snapshot"], "application failure restores the exact prior adapter state")

	var enemy := _real_enemy(Vector2(256.0, 0.0), 1000.0, 17120)
	var restored_projectile := _latest_projectile(weapon)
	if restored_projectile != null:
		restored_projectile.call("_on_area_entered", enemy.get_node("Hurtbox"))
	_suite.assert_true(float(enemy.health.current_hp) < 1000.0, "restored projectile callback still executes real damage")
	var ledger: Dictionary = (runtime.snapshot().get("cast_ledgers", {}) as Dictionary).get("17110", {})
	_suite.assert_true(bool(ledger.get("confirmed_hit", false)), "restored projectile callback still reaches the runtime ledger")
	runtime.finish_action(17110)
	_free_real_enemies([enemy])
	_free_runtime_weapon_fixture(fixture)


func _test_transient_status_restore_fails_when_target_is_missing() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var enemy := _real_enemy(Vector2.ZERO, 1000.0, 17201)
	var execution := _zone_execution(17202, "ice_zone", {
		"duration_frames": 300,
		"tick_interval_frames": 30,
		"radius_tiles": 3.0,
		"damage_multiplier": 0.08,
		"move_speed_multiplier": 0.5,
		"attack_speed_multiplier": 0.7,
		"freeze_duration_frames": 60,
	})
	weapon.call("_attach_dynamic_zone", execution, Vector2.ZERO)
	var zone := _zone_by_mode(weapon, "ice_zone")
	_suite.assert_true(zone != null, "transient restore fixture owns an ice zone")
	if zone != null:
		zone.advance_execution_for_test(1)
	var target_snapshot: Dictionary = weapon.runtime_snapshot()
	var owned_snapshots := target_snapshot.get("owned_payloads", []) as Array
	var zone_execution := (owned_snapshots[0] as Dictionary).get("execution", {}) as Dictionary
	var transient_ids := zone_execution.get("transient_status_target_ids", {}) as Dictionary
	_suite.assert_equal(
		transient_ids.get("slow", []),
		[17201],
		"ice zone snapshot freezes the transient slow target identity"
	)
	_free_real_enemies([enemy])
	weapon.reset_runtime_state()
	var before: Dictionary = weapon.runtime_snapshot()
	_suite.assert_true(not weapon.restore_runtime_snapshot(target_snapshot), "missing transient target rejects payload restore")
	_suite.assert_equal(weapon.runtime_snapshot(), before, "missing transient target failure rolls back atomically")
	_free_fixture(fixture)


func _test_released_derived_payload_snapshot_restores() -> void:
	var fixture := _weapon_fixture()
	var weapon: Node = fixture["weapon"]
	var ice_parameters := {
		"element_id": "ice",
		"damage_multiplier": 2.5,
		"speed_tiles_per_second": 14.0,
		"maximum_range_tiles": 8.0,
		"hit_width_tiles": 0.6,
		"zone_radius_tiles": 3.0,
		"zone_duration_frames": 300,
		"zone_tick_interval_frames": 30,
		"zone_damage_multiplier": 0.08,
		"move_speed_multiplier": 0.5,
		"attack_speed_multiplier": 0.7,
		"freeze_duration_frames": 60,
	}
	var definition := _definition(
		"charged_element",
		[_projectile_descriptor("staff_ice_restore", ice_parameters, "typed_element")]
	)
	_suite.assert_true(not weapon.begin_profile_action(definition).is_empty(), "derived Staff restore fixture constructs")
	_suite.assert_true(weapon.release_profile_action(), "derived Staff restore fixture releases")
	var projectile := _first_payload(weapon, "StaffProjectile")
	_suite.assert_true(projectile != null, "derived Staff restore fixture owns its committed projectile")
	if projectile != null:
		projectile.hit_for_test(17301, [])
	var derived_snapshot: Dictionary = weapon.runtime_snapshot()
	var owned_payloads := derived_snapshot.get("owned_payloads", []) as Array
	_suite.assert_equal(owned_payloads.size(), 1, "terminal ice projectile is replaced by one derived zone")
	if owned_payloads.size() == 1:
		_suite.assert_equal(
			((owned_payloads[0] as Dictionary).get("execution", {}) as Dictionary).get("descriptor_id"),
			"staff_ice_restore:ice_zone",
			"derived zone retains its deterministic committed lineage identity"
		)
	_suite.assert_true(
		weapon.can_restore_runtime_snapshot(derived_snapshot),
		"released derived payload passes committed-lineage prevalidation"
	)
	weapon.reset_runtime_state()
	_suite.assert_true(
		weapon.restore_runtime_snapshot(derived_snapshot),
		"released derived payload restores through its committed descriptor lineage"
	)
	_suite.assert_equal(weapon.runtime_snapshot(), derived_snapshot, "derived payload restore is deterministic")
	_free_fixture(fixture)


func _weapon_fixture() -> Dictionary:
	var weapon := StaffWeaponScript.new()
	weapon.name = "StaffWeapon"
	add_child(weapon)
	var sink := ResultSink.new()
	var runtime_sink := RuntimeResultSink.new()
	_suite.assert_true(weapon.configure_result_sink(runtime_sink), "Staff adapter accepts the runtime payload-result sink")
	weapon.payload_result_reported.connect(sink.handle_payload_result)
	return {"weapon": weapon, "sink": sink, "runtime_sink": runtime_sink}


func _runtime_weapon_fixture() -> Dictionary:
	var owner := Node2D.new()
	owner.name = "StaffRuntimeOwner"
	add_child(owner)
	var weapon := StaffWeaponScript.new()
	weapon.name = "StaffWeapon"
	owner.add_child(weapon)
	var definition := _staff_profile()
	var profile = WeaponRuntimeProfileScript.new()
	var parsed: Dictionary = profile.configure(definition)
	var modifiers = WeaponModifierStateScript.new()
	var capabilities := PackedStringArray(definition.get("capabilities", []))
	var bounds: Dictionary = {}
	for capability: String in capabilities:
		bounds[capability] = {"minimum": 0.1, "maximum": 200.0}
	var runtime = StaffWeaponRuntimeScript.new()
	var configured := (
		bool(parsed.get("ok", false))
		and modifiers.configure(capabilities, bounds)
		and runtime.configure(owner, profile, modifiers)
		and weapon.configure_result_sink(runtime)
	)
	_suite.assert_true(configured, "real Staff adapter/runtime fixture configures")
	return {
		"owner": owner,
		"weapon": weapon,
		"runtime": runtime,
		"profile": profile,
		"modifiers": modifiers,
	}


func _free_fixture(fixture: Dictionary) -> void:
	var weapon: Node = fixture.get("weapon")
	if weapon != null and is_instance_valid(weapon):
		weapon.reset_runtime_state()
		weapon.free()


func _free_runtime_weapon_fixture(fixture: Dictionary) -> void:
	var owner: Node = fixture.get("owner")
	if owner != null and is_instance_valid(owner):
		var weapon := owner.get_node_or_null("StaffWeapon")
		if weapon != null and weapon.has_method("reset_runtime_state"):
			weapon.call("reset_runtime_state")
		owner.free()


func _set_runtime_element(runtime: RefCounted, target: StringName, token_seed: int) -> void:
	var guard := 0
	while StringName(str(runtime.presentation_snapshot().get("element", ""))) != target and guard < 3:
		var token := token_seed + guard
		var plan: Dictionary = runtime.plan_intent(
			{"id": "weapon_utility", "edge": "pressed"},
			_staff_runtime_context(32000 + token)
		).get("plan", {})
		_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "real Staff cycles toward %s" % str(target))
		runtime.finish_action(token)
		guard += 1
	_suite.assert_equal(runtime.presentation_snapshot().get("element"), str(target), "real Staff resolves %s" % str(target))


func _staff_runtime_context(run_seed: int) -> Dictionary:
	return {
		"run_seed": run_seed,
		"aim_direction": Vector2.RIGHT,
		"time_interactions": {},
	}


func _definition(action_id: String, descriptors: Array) -> Dictionary:
	return {
		"token": 77,
		"generation": 4,
		"profile_id": "staff_launch_v1",
		"weapon_id": "staff",
		"action_id": action_id,
		"aim_direction": Vector2.RIGHT,
		"base_attack": 9.0,
		"payload_descriptors": descriptors.duplicate(true),
		"time_interactions": [],
		"boss_conversion": {},
		"invulnerable_during_cast": false,
	}


func _projectile_descriptor(
	descriptor_id: String,
	parameters: Dictionary,
	kind: String = "projectile"
) -> Dictionary:
	var merged := {
		"element_id": "arcane",
		"damage_multiplier": 0.8,
		"speed_tiles_per_second": 8.75,
		"maximum_range_tiles": 12.0,
		"hit_width_tiles": 0.3,
	}
	for key: Variant in parameters:
		merged[key] = parameters[key]
	return {
		"descriptor_id": descriptor_id,
		"kind": kind,
		"token": 77,
		"generation": 4,
		"outcome_index": 0,
		"seed": 84001,
		"target_deduplication": "per_action_target",
		"parameters": merged,
	}


func _zone_descriptor(
	descriptor_id: String,
	parameters: Dictionary,
	kind: String = "zone"
) -> Dictionary:
	return {
		"descriptor_id": descriptor_id,
		"kind": kind,
		"token": 77,
		"generation": 4,
		"outcome_index": 0,
		"seed": 84001,
		"target_deduplication": "per_action_target_tick",
		"parameters": parameters.duplicate(true),
	}


func _projectile_execution(seed: int, element_id: String, extra: Dictionary) -> Dictionary:
	var execution := {
		"action_token": 88,
		"generation": 5,
		"source_action_id": "arcane_bolt",
		"descriptor_id": "staff_arcane_bolt",
		"outcome_index": 0,
		"deterministic_seed": seed,
		"element_id": element_id,
		"damage": 7.2,
		"base_attack": 9.0,
		"speed": 560.0,
		"max_range_pixels": 768.0,
		"target_deduplication": "per_action_target",
		"effect_descriptor": {},
		"combination": {},
		"chain": {},
	}
	for key: Variant in extra:
		execution[key] = extra[key]
	return execution


func _zone_execution(seed: int, mode: String, parameters: Dictionary) -> Dictionary:
	return {
		"action_token": 99,
		"generation": 6,
		"source_action_id": "charged_element",
		"descriptor_id": "staff_zone",
		"outcome_index": 0,
		"deterministic_seed": seed,
		"mode": mode,
		"base_attack": 9.0,
		"parameters": parameters.duplicate(true),
	}


func _ultimate_results(seed: int) -> Array[Dictionary]:
	var sink := ResultSink.new()
	var zone: Node = StaffSpellZoneScene.instantiate()
	add_child(zone)
	zone.payload_result.connect(sink.handle_payload_result)
	var configured: bool = bool(zone.configure_execution(_zone_execution(seed, "seeded_sequence", {
		"count": 20,
		"tick_interval_frames": 6,
		"radius_tiles": 5.0,
		"elements": ["fire", "ice", "lightning"],
	})))
	_suite.assert_true(configured, "seeded ultimate zone configures")
	if configured:
		zone.advance_execution_for_test(120)
	var ticks := _results_of_type(sink, "ultimate_tick")
	zone.free()
	return ticks


func _first_payload(weapon: Node, expected_class: String) -> Node:
	for payload: Node in weapon.owned_payloads_for_test():
		if payload.get_class() == expected_class or str(payload.get_script().get_global_name()) == expected_class:
			return payload
	return null


func _latest_projectile(weapon: Node) -> Node:
	var payloads: Array[Node] = weapon.owned_payloads_for_test()
	for index: int in range(payloads.size() - 1, -1, -1):
		var payload := payloads[index]
		if payload.get_class() == "StaffProjectile" or str(payload.get_script().get_global_name()) == "StaffProjectile":
			return payload
	return null


func _zone_by_mode(weapon: Node, expected_mode: String) -> Node:
	for payload: Node in weapon.owned_payloads_for_test():
		if payload.has_method("execution_snapshot"):
			var snapshot: Dictionary = payload.call("execution_snapshot")
			if str(snapshot.get("mode", "")) == expected_mode:
				return payload
	return null


func _combination_zone(weapon: Node, combo_id: String) -> Node:
	for payload: Node in weapon.owned_payloads_for_test():
		if not payload.has_method("execution_snapshot"):
			continue
		var snapshot: Dictionary = payload.call("execution_snapshot")
		if str(snapshot.get("mode", "")) != "combination":
			continue
		var zone_parameters: Dictionary = snapshot.get("parameters", {})
		if str(zone_parameters.get("combo_id", "")) == combo_id:
			return payload
	return null


func _results_of_type(sink: ResultSink, result_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Dictionary in sink.results:
		var payload: Dictionary = record.get("result", {})
		if str(payload.get("type", "")) == result_type:
			result.append(payload.duplicate(true))
	return result


func _dictionary_by_id(values: Variant, field: String, identity: String) -> Dictionary:
	if not values is Array:
		return {}
	for value: Variant in values as Array:
		if value is Dictionary and str((value as Dictionary).get(field, "")) == identity:
			return (value as Dictionary).duplicate(true)
	return {}


func _real_enemy(position: Vector2, maximum_hp: float, stable_target_id: int) -> Node:
	var enemy: Node = EnemyChaserScene.instantiate()
	enemy.max_hp = maximum_hp
	enemy.global_position = position
	enemy.set_meta("stable_target_id", stable_target_id)
	add_child(enemy)
	enemy.set_physics_process(false)
	var damaged_callable := Callable(enemy, "_on_damaged")
	if enemy.health.damaged.is_connected(damaged_callable):
		enemy.health.damaged.disconnect(damaged_callable)
	return enemy


func _free_real_enemies(enemies: Array) -> void:
	for enemy_value: Variant in enemies:
		if enemy_value is Node and is_instance_valid(enemy_value):
			(enemy_value as Node).free()


func _staff_status_source(token: int, descriptor: String, outcome_index: int) -> StringName:
	return StringName("staff:%d:%s:%d" % [token, descriptor, outcome_index])


func _boss_conversion_fixture() -> Dictionary:
	return {
		"target_id": "chrono_warden",
		"conversion_id": "staff_control_conversion",
		"preserve_committed_active_attack": true,
		"allowed_states": ["RECOVERY", "EXPOSED"],
		"freeze_delay_frames": 12,
		"blind_delay_frames": 8,
	}


func _staff_payload() -> Dictionary:
	var profile := _staff_profile()
	for payload_value: Variant in profile.get("payloads", []):
		if payload_value is Dictionary and str((payload_value as Dictionary).get("payload_id", "")) == "staff_element_cast":
			return (payload_value as Dictionary).duplicate(true)
	return {}


func _staff_profile() -> Dictionary:
	var file := FileAccess.open("res://data/content_packs/base/content/weapon_runtime_profiles.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return {}
	for profile_value: Variant in parsed as Array:
		if profile_value is Dictionary and str((profile_value as Dictionary).get("id", "")) == "staff_launch_v1":
			return (profile_value as Dictionary).duplicate(true)
	return {}
