extends Node

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const EnemyBaseScript := preload("res://scripts/enemies/enemy_base.gd")
const StaffProjectileScript := preload("res://scripts/combat/staff_projectile.gd")
const StaffSpellZoneScript := preload("res://scripts/combat/staff_spell_zone.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


class RecordingDamageTarget extends Node2D:
	var damage_multiplier: float = 1.0
	var invulnerable: bool = false
	var received: Array[RefCounted] = []


	func receive_hit(damage_info: RefCounted) -> float:
		received.append(damage_info)
		if invulnerable:
			return 0.0
		return float(damage_info.amount) * damage_multiplier


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_burn_uses_damage_info_per_owned_source()
	await _test_projectile_reports_actual_primary_splash_and_chain_damage()
	await _test_zone_reports_actual_damage_once_per_target_tick()
	_suite.finish(get_tree())


func _test_burn_uses_damage_info_per_owned_source() -> void:
	var enemy: Node = await _enemy_fixture(100.0)
	var health: Node = enemy.get_node("HealthComponent")
	health.damaged.disconnect(Callable(enemy, "_on_damaged"))
	health.died.disconnect(Callable(enemy, "_on_died"))
	var source_a := Node.new()
	var source_b := Node.new()
	var attacker_a := Node.new()
	var attacker_b := Node.new()
	add_child(source_a)
	add_child(source_b)
	add_child(attacker_a)
	add_child(attacker_b)
	var applied: Array[Dictionary] = []
	var on_damage_applied := func(info: RefCounted, target: Node, amount: float) -> void:
		if target == enemy:
			applied.append({"info": info, "amount": amount})
	EventBus.damage_applied.connect(on_damage_applied)
	_suite.assert_true(
		enemy.apply_damage_vulnerability(&"staff_burn_vulnerability", 60, 0.20),
		"Burn fixture enables the target's normal vulnerability hook"
	)

	_suite.assert_true(
		enemy.apply_elemental_status(&"burn", &"staff_fire_a", 11, 2, 10.0, 1, -1.0, source_a, attacker_a),
		"first Burn source carries explicit damage ownership"
	)
	_suite.assert_true(
		enemy.apply_elemental_status(&"burn", &"staff_fire_b", 12, 2, 5.0, 1, -1.0, source_b, attacker_b),
		"second Burn source remains independently owned"
	)
	enemy.call("_tick_elemental_status_runtime")
	_suite.assert_close(health.current_hp, 82.0, "independent Burn ticks pass through target vulnerability")
	_suite.assert_equal(applied.size(), 2, "multi-source Burn emits one damage pipeline event per source-generation")
	if applied.size() == 2:
		var first: RefCounted = applied[0]["info"]
		var second: RefCounted = applied[1]["info"]
		_suite.assert_equal(first.damage_type, DamageInfoScript.DamageType.FIRE, "first Burn retains FIRE damage type")
		_suite.assert_equal(second.damage_type, DamageInfoScript.DamageType.FIRE, "second Burn retains FIRE damage type")
		_suite.assert_equal(first.source, source_a, "first Burn retains its source")
		_suite.assert_equal(first.attacker, attacker_a, "first Burn retains its attacker")
		_suite.assert_equal(second.source, source_b, "second Burn retains its source")
		_suite.assert_equal(second.attacker, attacker_b, "second Burn retains its attacker")

	health.acquire_invulnerability_source(&"burn_test_guard")
	enemy.call("_tick_elemental_status_runtime")
	_suite.assert_close(health.current_hp, 82.0, "Burn respects HealthComponent invulnerability")
	_suite.assert_equal(applied.size(), 2, "blocked Burn does not report configured damage as applied")
	health.release_invulnerability_source(&"burn_test_guard")

	var killer: Array = []
	health.died.connect(func(value: Variant) -> void: killer.append(value))
	health.current_hp = 4.0
	_suite.assert_true(
		enemy.apply_elemental_status(&"burn", &"staff_finisher", 13, 1, 5.0, 1, -1.0, source_b, attacker_b),
		"lethal Burn fixture applies"
	)
	enemy.call("_tick_elemental_status_runtime")
	_suite.assert_equal(killer.size(), 1, "lethal Burn enters the normal death pipeline exactly once")
	if not killer.is_empty():
		_suite.assert_equal(killer[0], attacker_b, "lethal Burn attributes the kill to its attacker")

	if EventBus.damage_applied.is_connected(on_damage_applied):
		EventBus.damage_applied.disconnect(on_damage_applied)
	for node: Node in [enemy, source_a, source_b, attacker_a, attacker_b]:
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame


func _test_projectile_reports_actual_primary_splash_and_chain_damage() -> void:
	var fire_projectile := StaffProjectileScript.new()
	var source := Node.new()
	var attacker := Node.new()
	add_child(source)
	add_child(attacker)
	_suite.assert_true(fire_projectile.configure_execution(_projectile_execution("fire", 101)), "Fire projectile configures")
	fire_projectile.source = source
	fire_projectile.owner_entity = attacker
	add_child(fire_projectile)
	var primary := _recording_target(1001, Vector2.ZERO, 0.5)
	var splash := _recording_target(1002, Vector2(32.0, 0.0), 0.25)
	var fire_results: Array[Dictionary] = []
	fire_projectile.payload_result.connect(func(_token: int, _generation: int, result: Dictionary) -> void:
		fire_results.append(result)
	)
	var primary_result: Dictionary = fire_projectile.call("_execute_target_hit", primary)
	_suite.assert_close(float(primary_result.get("damage", -1.0)), 10.0, "primary result reports receive_hit resolved damage")
	_suite.assert_equal(primary_result.get("impact_position"), primary.global_position, "primary result freezes the actual impact position")
	var fire_derived := _damage_results(fire_results)
	_suite.assert_equal(fire_derived.size(), 1, "Fire splash emits one derived damage result for the secondary target")
	if fire_derived.size() == 1:
		_suite.assert_equal(fire_derived[0].get("target_id"), 1002, "Fire splash result identifies its resolved target")
		_suite.assert_close(float(fire_derived[0].get("damage", -1.0)), 2.5, "Fire splash reports actual target-resolved damage")
		_suite.assert_equal(fire_derived[0].get("impact_position"), splash.global_position, "Fire splash result records its impact position")
		_suite.assert_true(not bool(fire_derived[0].get("terminal", true)), "derived splash does not terminate the projectile outcome")
	_suite.assert_equal(_terminal_results(fire_results).size(), 1, "derived Fire damage does not duplicate the terminal hit")

	await _cleanup_nodes([fire_projectile, primary, splash])
	var lightning_projectile := StaffProjectileScript.new()
	_suite.assert_true(lightning_projectile.configure_execution(_projectile_execution("lightning", 102)), "Lightning projectile configures")
	lightning_projectile.source = source
	lightning_projectile.owner_entity = attacker
	add_child(lightning_projectile)
	var lightning_primary := _recording_target(1101, Vector2.ZERO, 1.0)
	var chain_target := _recording_target(1102, Vector2(48.0, 0.0), 0.4)
	var lightning_results: Array[Dictionary] = []
	lightning_projectile.payload_result.connect(func(_token: int, _generation: int, result: Dictionary) -> void:
		lightning_results.append(result)
	)
	lightning_projectile.call("_execute_target_hit", lightning_primary)
	var chain_results := _damage_results(lightning_results)
	_suite.assert_equal(chain_results.size(), 1, "Lightning chain emits one derived damage result")
	if chain_results.size() == 1:
		_suite.assert_equal(chain_results[0].get("target_id"), 1102, "chain result identifies the chained target")
		_suite.assert_close(float(chain_results[0].get("damage", -1.0)), 4.0, "chain result uses receive_hit actual damage")
		_suite.assert_equal(chain_results[0].get("impact_position"), chain_target.global_position, "chain result records the chained impact")
	_suite.assert_equal(_terminal_results(lightning_results).size(), 1, "chain damage preserves one terminal projectile result")
	await _cleanup_nodes([lightning_projectile, lightning_primary, chain_target, source, attacker])


func _test_zone_reports_actual_damage_once_per_target_tick() -> void:
	var target := _recording_target(2001, Vector2.ZERO, 0.5)
	var zone := StaffSpellZoneScript.new()
	var execution := _zone_execution("ice_zone", 201, {
		"radius_tiles": 1.0,
		"duration_frames": 2,
		"tick_interval_frames": 1,
		"damage_multiplier": 1.0,
		"move_speed_multiplier": 0.8,
		"attack_speed_multiplier": 0.8,
		"freeze_duration_frames": 1,
	})
	_suite.assert_true(zone.configure_execution(execution), "Ice zone configures")
	add_child(zone)
	var results: Array[Dictionary] = []
	zone.payload_result.connect(func(_token: int, _generation: int, result: Dictionary) -> void:
		results.append(result)
	)
	zone.advance_execution_for_test(2)
	zone.advance_execution_for_test(2)
	var damage_results := _damage_results(results)
	_suite.assert_equal(damage_results.size(), 2, "Ice zone emits exactly one resolved result per target tick")
	if damage_results.size() == 2:
		_suite.assert_true(damage_results[0].get("claim_id") != damage_results[1].get("claim_id"), "zone target-tick claims are unique")
		for result: Dictionary in damage_results:
			_suite.assert_close(float(result.get("damage", -1.0)), 4.5, "zone result reports actual receive_hit damage")
			_suite.assert_equal(result.get("target_id"), 2001, "zone result identifies the damaged target")
			_suite.assert_equal(result.get("impact_position"), target.global_position, "zone result records the target impact position")

	await _cleanup_nodes([zone, target])
	var rift_target := _recording_target(2101, Vector2.ZERO, 0.25)
	var combo_zone := StaffSpellZoneScript.new()
	_suite.assert_true(combo_zone.configure_execution(_zone_execution("combination", 202, {
		"combo_id": "steam_burst",
		"combo_kind": "explosion",
		"combo_parameters": {
			"radius_tiles": 1.0,
			"damage_multiplier": 1.0,
			"damage_split": {"fire": 0.5, "ice": 0.5},
			"time_damage_multiplier": 0.5,
			"blind_duration_frames": 0,
			"blind_miss_chance": 0.0,
		},
	})), "Rift interaction combination configures")
	add_child(combo_zone)
	var combo_results: Array[Dictionary] = []
	combo_zone.payload_result.connect(func(_token: int, _generation: int, result: Dictionary) -> void:
		combo_results.append(result)
	)
	combo_zone.advance_execution_for_test(1)
	var resolved_combo := _damage_results(combo_results)
	_suite.assert_equal(resolved_combo.size(), 3, "combination reports Fire, Ice, and Rift Time damage independently")
	var combo_elements: Array[String] = []
	for result: Dictionary in resolved_combo:
		combo_elements.append(str(result.get("element_id", "")))
		_suite.assert_close(float(result.get("damage", -1.0)), 1.125, "combination result reports actual target-resolved damage")
	combo_elements.sort()
	_suite.assert_equal(combo_elements, ["fire", "ice", "time"], "Rift Time damage keeps its own typed result")

	await _cleanup_nodes([combo_zone, rift_target])
	var ultimate_target := _recording_target(2201, Vector2.ZERO, 0.0)
	var ultimate_zone := StaffSpellZoneScript.new()
	_suite.assert_true(ultimate_zone.configure_execution(_zone_execution("seeded_sequence", 203, {
		"count": 2,
		"tick_interval_frames": 1,
		"elements": ["fire"],
		"radius_tiles": 1.0,
		"damage_multiplier": 1.0,
	})), "Ultimate zone configures")
	add_child(ultimate_zone)
	var ultimate_results: Array[Dictionary] = []
	ultimate_zone.payload_result.connect(func(_token: int, _generation: int, result: Dictionary) -> void:
		ultimate_results.append(result)
	)
	ultimate_zone.advance_execution_for_test(2)
	var resolved_ultimate := _damage_results(ultimate_results)
	_suite.assert_equal(resolved_ultimate.size(), 2, "Ultimate emits one resolved damage result per target tick")
	for result: Dictionary in resolved_ultimate:
		_suite.assert_close(float(result.get("damage", -1.0)), 0.0, "invulnerable/blocked target reports zero actual damage")
		_suite.assert_true(not bool(result.get("hit", true)), "zero actual damage is not reported as a successful Mana-return hit")
	await _cleanup_nodes([ultimate_zone, ultimate_target])


func _enemy_fixture(hp: float) -> Node:
	var enemy := EnemyBaseScript.new()
	enemy.name = "StaffDamageEnemy"
	var health := HealthComponentScript.new()
	health.name = "HealthComponent"
	health.max_hp = hp
	enemy.max_hp = hp
	enemy.add_child(health)
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([Vector2(8, 0), Vector2(-4, -4), Vector2(-4, 4)])
	enemy.add_child(visual)
	add_child(enemy)
	await get_tree().process_frame
	enemy.set_physics_process(false)
	return enemy


func _recording_target(stable_id: int, position: Vector2, multiplier: float) -> RecordingDamageTarget:
	var target := RecordingDamageTarget.new()
	target.set_meta("stable_target_id", stable_id)
	target.global_position = position
	target.damage_multiplier = multiplier
	target.add_to_group("enemies")
	add_child(target)
	return target


func _projectile_execution(element: String, token: int) -> Dictionary:
	return {
		"action_token": token,
		"generation": token,
		"source_action_id": "charged_element",
		"descriptor_id": "staff_%s_%d" % [element, token],
		"outcome_index": 0,
		"deterministic_seed": token * 17,
		"element_id": element,
		"damage": 20.0,
		"base_attack": 9.0,
		"speed": 500.0,
		"max_range_pixels": 640.0,
		"target_deduplication": "per_action_target",
		"effect_descriptor": {
			"explosion_radius_tiles": 1.0,
			"explosion_damage_multiplier": 0.5,
			"burn_duration_frames": 0,
			"burn_tick_interval_frames": 30,
			"burn_damage_multiplier": 0.1,
			"shock_duration_frames": 0,
			"shock_bonus_damage_multiplier": 0.2,
		},
		"combination": {},
		"chain": {"additional_target_count": 1, "chain_range_tiles": 2.0, "chain_damage_multiplier": 0.5},
		"direction": Vector2.RIGHT,
	}


func _zone_execution(zone_mode: String, token: int, zone_parameters: Dictionary) -> Dictionary:
	return {
		"action_token": token,
		"generation": token,
		"source_action_id": "charged_element",
		"descriptor_id": "staff_zone_%d" % token,
		"outcome_index": 1,
		"deterministic_seed": token * 31,
		"mode": zone_mode,
		"parameters": zone_parameters,
		"base_attack": 9.0,
		"status_source_id": StringName("staff_zone:%d" % token),
	}


func _damage_results(results: Array[Dictionary]) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for result: Dictionary in results:
		if str(result.get("type", "")) == "damage_resolved":
			filtered.append(result)
	return filtered


func _terminal_results(results: Array[Dictionary]) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for result: Dictionary in results:
		if bool(result.get("terminal", false)):
			filtered.append(result)
	return filtered


func _cleanup_nodes(nodes: Array) -> void:
	for node_value: Variant in nodes:
		if node_value is Node and is_instance_valid(node_value):
			(node_value as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
