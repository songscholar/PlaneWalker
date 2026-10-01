extends Node

const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")
const ElementalStatusRuntimeScript := preload("res://scripts/combat/elemental_status_runtime.gd")
const EnemyBaseScript := preload("res://scripts/enemies/enemy_base.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_tuple_keys_overlap_refresh_and_exact_removal()
	_test_burn_ticks_and_expiry_are_frame_exact()
	_test_slow_cap_clear_owned_and_reset()
	_test_blind_is_seeded_order_independent_and_stateless()
	await _test_enemy_blind_seed_lifecycle_is_run_scoped()
	await _test_enemy_hooks_coexist_with_vulnerability_and_clean_on_death()
	await _test_boss_freeze_and_blind_convert_without_breaking_commitment()
	_suite.finish(get_tree())


func _test_tuple_keys_overlap_refresh_and_exact_removal() -> void:
	var runtime = _runtime(101)
	_suite.assert_true(
		runtime.apply_status(&"burn", &"staff_fire", 7, 3, 2.0, 2),
		"first tuple applies"
	)
	_suite.assert_true(
		runtime.apply_status(&"burn", &"staff_fire", 7, 6, 2.0, 2),
		"same tuple refreshes"
	)
	_suite.assert_equal(runtime.source_count(&"burn"), 1, "refresh creates no duplicate source")
	_suite.assert_equal(
		runtime.remaining_frames(&"burn", &"staff_fire", 7),
		6,
		"refresh extends the same tuple to the requested lifetime"
	)
	_suite.assert_true(
		runtime.apply_status(&"burn", &"staff_fire", 8, 4, 3.0, 2),
		"new generation owns an independent tuple"
	)
	_suite.assert_true(
		runtime.apply_status(&"burn", &"staff_fire_alt", 7, 5, 4.0, 2),
		"new source owns an independent tuple"
	)
	_suite.assert_equal(runtime.source_count(&"burn"), 3, "overlapping tuples coexist")
	_suite.assert_true(
		runtime.remove_status(&"burn", &"staff_fire", 7),
		"one exact tuple removes"
	)
	_suite.assert_true(
		runtime.has_status(&"burn", &"staff_fire", 8),
		"removing one generation preserves another"
	)
	_suite.assert_true(
		runtime.has_status(&"burn", &"staff_fire_alt", 7),
		"removing one source preserves another"
	)
	_suite.assert_true(
		not runtime.remove_status(&"burn", &"staff_fire", 7),
		"removing a missing tuple fails closed"
	)


func _test_burn_ticks_and_expiry_are_frame_exact() -> void:
	var runtime = _runtime(202)
	var source := Node.new()
	var attacker := Node.new()
	_suite.assert_true(runtime.apply_status(&"burn", &"fire_orb", 3, 6, 4.0, 2, -1.0, source, attacker), "burn fixture applies")
	var total_damage := 0.0
	var tick_sources: Array = []
	for _frame: int in range(5):
		var events: Dictionary = runtime.advance_frame()
		total_damage += float(events.get("burn_damage", 0.0))
		for tick_value: Variant in events.get("burn_ticks", []):
			var tick := tick_value as Dictionary
			tick_sources.append([tick.get("damage_source"), tick.get("damage_attacker")])
	_suite.assert_close(total_damage, 8.0, "burn ticks at frames two and four")
	_suite.assert_equal(tick_sources, [[source, attacker], [source, attacker]], "each Burn tick retains source and attacker ownership")
	_suite.assert_true(runtime.has_status(&"burn", &"fire_orb", 3), "burn remains active through frame five")
	var expiry_events: Dictionary = runtime.advance_frame()
	total_damage += float(expiry_events.get("burn_damage", 0.0))
	_suite.assert_close(total_damage, 12.0, "burn delivers its final tick on the expiry frame")
	_suite.assert_true(not runtime.has_status(&"burn", &"fire_orb", 3), "burn expires exactly on frame six")
	_suite.assert_equal((expiry_events.get("expired", []) as Array).size(), 1, "expiry reports the removed tuple once")
	source.free()
	attacker.free()


func _test_slow_cap_clear_owned_and_reset() -> void:
	var runtime = _runtime(303)
	_suite.assert_true(runtime.apply_status(&"slow", &"ice_field", 11, 30, 0.65), "ordinary slow applies")
	_suite.assert_true(runtime.apply_status(&"slow", &"collapse", 12, 30, 0.10, 30, 0.20), "strong slow applies")
	_suite.assert_close(runtime.slow_multiplier(), 0.30, "overlapping movement slow cannot cross the configured floor")
	_suite.assert_close(runtime.attack_speed_multiplier(), 0.30, "overlapping attack slow cannot cross the configured floor")
	_suite.assert_true(runtime.apply_status(&"freeze", &"ice_field", 11, 12), "owned freeze applies")
	_suite.assert_true(runtime.apply_status(&"shock", &"ice_field", 11, 20, 0.20), "owned shock applies")
	_suite.assert_true(runtime.apply_status(&"blind", &"ice_field", 11, 20, 0.40), "owned blind applies")
	_suite.assert_equal(runtime.clear_owned(&"ice_field", 11), 4, "clear-owned removes every effect for one source generation")
	_suite.assert_close(runtime.slow_multiplier(), 0.30, "independent strong slow survives clear-owned")
	_suite.assert_true(runtime.has_status(&"slow", &"collapse", 12), "clear-owned preserves other source generations")
	_suite.assert_true(not runtime.is_frozen(), "clear-owned releases its freeze")
	_suite.assert_close(runtime.shock_damage_bonus(), 0.0, "clear-owned releases its shock")
	runtime.reset_runtime_state()
	_suite.assert_equal(runtime.source_count(), 0, "reset clears every remaining status")
	_suite.assert_close(runtime.slow_multiplier(), 1.0, "reset restores unmodified speed")


func _test_blind_is_seeded_order_independent_and_stateless() -> void:
	var first = _runtime(404)
	var second = _runtime(404)
	first.apply_status(&"blind", &"steam_a", 1, 90, 0.35)
	first.apply_status(&"blind", &"steam_b", 2, 90, 0.40)
	second.apply_status(&"blind", &"steam_b", 2, 90, 0.40)
	second.apply_status(&"blind", &"steam_a", 1, 90, 0.35)
	var first_results: Array[bool] = []
	var second_results: Array[bool] = []
	for action_sequence: int in range(32):
		first_results.append(first.should_blind_miss(action_sequence))
		second_results.append(second.should_blind_miss(action_sequence))
	_suite.assert_equal(first_results, second_results, "blind outcomes ignore insertion order for the same seed and tuples")
	_suite.assert_equal(
		first.should_blind_miss(9),
		first.should_blind_miss(9),
		"blind queries are stateless and repeatable"
	)
	_suite.assert_true(first_results.has(true), "deterministic blind sample contains misses")
	_suite.assert_true(first_results.has(false), "deterministic blind sample contains successful attacks")


func _test_enemy_blind_seed_lifecycle_is_run_scoped() -> void:
	var first: Node = await _enemy_fixture()
	var repeated: Node = await _enemy_fixture()
	_suite.assert_true(
		first.get_instance_id() != repeated.get_instance_id(),
		"Blind replay fixtures are distinct enemy instances"
	)
	_configure_enemy_blind_fixture(first, 4404, "stable:blind_enemy_4")
	_configure_enemy_blind_fixture(repeated, 4404, "stable:blind_enemy_4")
	var first_results := _blind_results_for_enemy(first)
	var repeated_results := _blind_results_for_enemy(repeated)
	_suite.assert_equal(
		first_results,
		repeated_results,
		"same run seed and status material replay across distinct instance ids"
	)

	_suite.assert_true(
		first.clear_elemental_status(&"blind", &"steam", 10),
		"ordinary exact clear removes the Blind tuple"
	)
	_suite.assert_true(
		first.has_meta("elemental_status_seed_initialized"),
		"ordinary exact clear preserves the run-scoped Blind seed"
	)
	first.apply_elemental_status(&"blind", &"steam", 10, 30, 0.50)
	_suite.assert_equal(
		_blind_results_for_enemy(first),
		first_results,
		"reapplying Blind during one live run does not reseed outcomes"
	)
	first.clear_elemental_statuses(&"boss_phase_transition")
	_suite.assert_true(
		first.has_meta("elemental_status_seed_initialized"),
		"phase-style status clear preserves the live enemy run seed"
	)
	_suite.assert_equal(
		str(first.get_meta("elemental_status_seed_material", "")),
		"stable:blind_enemy_4",
		"phase-style status clear preserves stable seed material"
	)

	first.reset_elemental_statuses()
	_suite.assert_true(
		not first.has_meta("elemental_status_seed_initialized"),
		"full elemental runtime reset releases the previous run seed"
	)
	_suite.assert_true(
		not first.has_meta("elemental_status_seed_material"),
		"full elemental runtime reset releases the previous run material"
	)
	_configure_enemy_blind_fixture(first, 9917, "stable:blind_enemy_4")
	var next_run_results := _blind_results_for_enemy(first)
	_suite.assert_true(
		next_run_results != first_results,
		"the reused enemy accepts a new deterministic seed after full reset"
	)

	first.queue_free()
	repeated.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_enemy_hooks_coexist_with_vulnerability_and_clean_on_death() -> void:
	var enemy: Node = await _enemy_fixture()
	var health: Node = enemy.get_node("HealthComponent")
	_suite.assert_true(enemy.apply_elemental_status(&"slow", &"ice_zone", 5, 60, 0.50, 30, 0.70), "enemy accepts source-aware slow")
	_suite.assert_close(enemy.call("_current_move_speed"), enemy.move_speed * 0.50, "elemental slow affects enemy movement")
	_suite.assert_close(float(enemy.elemental_status_snapshot().get("attack_speed_multiplier")), 0.70, "elemental slow preserves a distinct attack multiplier")
	_suite.assert_true(enemy.apply_damage_vulnerability(&"gun_void", 60, 0.15), "Gun vulnerability remains available")
	_suite.assert_true(enemy.apply_elemental_status(&"shock", &"lightning", 8, 60, 0.20), "enemy accepts source-aware shock")
	_suite.assert_close(enemy.get_damage_taken_multiplier(), 1.35, "shock adds without replacing Gun vulnerability")
	_suite.assert_true(enemy.apply_elemental_status(&"freeze", &"ice_burst", 9, 12), "ordinary enemy accepts hard freeze")
	_suite.assert_true(enemy.is_elementally_frozen(), "ordinary enemy reports hard freeze")
	_suite.assert_true(enemy.apply_elemental_status(&"blind", &"steam", 10, 30, 0.50), "ordinary enemy accepts blind")
	_suite.assert_true(enemy.clear_elemental_status(&"slow", &"ice_zone", 5), "enemy removes one exact status tuple")
	_suite.assert_true(enemy.elemental_status_snapshot().get("source_count", 0) > 0, "exact removal preserves unrelated statuses")
	enemy.reset_elemental_statuses()
	_suite.assert_equal(enemy.elemental_status_snapshot().get("source_count"), 0, "enemy reset clears statuses")

	enemy.apply_elemental_status(&"burn", &"death_burn", 1, 120, 3.0, 30)
	enemy.apply_elemental_status(&"slow", &"death_slow", 1, 120, 0.60)
	_configure_enemy_blind_fixture(enemy, 5510, "stable:death_fixture")
	health.lose_health(health.current_hp, self)
	_suite.assert_equal(enemy.elemental_status_snapshot().get("source_count"), 0, "death synchronously clears all statuses")
	_suite.assert_true(not enemy.has_meta("elemental_status_seed_initialized"), "death releases the previous run Blind seed")
	_suite.assert_true(not enemy.has_meta("elemental_status_seed_material"), "death releases the previous run Blind seed material")
	await get_tree().create_timer(0.25).timeout


func _test_boss_freeze_and_blind_convert_without_breaking_commitment() -> void:
	var subject: Dictionary = await _boss_fixture()
	var boss: Node = subject["boss"]
	_suite.assert_true(boss.force_action_for_test("SLAM"), "boss conversion fixture commits an action")
	var before: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_true(
		not boss.apply_elemental_status(&"freeze", &"staff_ice_active", 4, 60),
		"boss rejects hard control while an attack is committed"
	)
	var preserved: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_equal(preserved.get("action"), before.get("action"), "active-attack control preserves the committed action")
	_suite.assert_equal(preserved.get("phase"), before.get("phase"), "active-attack control preserves the committed phase")
	_suite.assert_close(float(preserved.get("remaining")), float(before.get("remaining")), "active-attack control does not mutate the committed clock")
	_suite.assert_true(not boss.is_elementally_frozen(), "boss freeze conversion never hard-freezes the behavior clock")

	boss.advance_action_for_test(float(preserved.get("remaining")) + 0.01)
	_suite.assert_equal(boss.get_action_resolution_count_for_test("SLAM"), 1, "protected committed action still resolves exactly once")
	_suite.assert_equal(boss.get_boss_ui_snapshot().get("phase"), "RECOVERY", "fixture reaches the allowed recovery conversion state")

	_suite.assert_true(boss.apply_elemental_status(&"freeze", &"staff_ice", 5, 60), "recovery freeze converts instead of hard-controlling")
	var frozen: Dictionary = boss.get_boss_ui_snapshot()
	var recovery_before_conversion: float = float(boss.slam_recovery)
	_suite.assert_close(float(frozen.get("remaining")), recovery_before_conversion + 12.0 / 60.0, "boss freeze converts to twelve recovery-delay frames")
	var refresh_before := float(frozen.get("remaining"))
	boss.apply_elemental_status(&"freeze", &"staff_ice", 5, 90)
	_suite.assert_close(float(boss.get_boss_ui_snapshot().get("remaining")), refresh_before, "same freeze tuple refreshes without duplicating conversion delay")
	boss.apply_elemental_status(&"blind", &"staff_steam", 6, 60, 0.75)
	var blinded: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_equal(blinded.get("action"), "SLAM", "blind conversion preserves the committed action")
	_suite.assert_equal(blinded.get("phase"), "RECOVERY", "blind conversion preserves the committed phase")
	_suite.assert_close(float(blinded.get("remaining")), refresh_before + 8.0 / 60.0, "boss blind converts to eight delay frames")

	boss.advance_action_for_test(float(blinded.get("remaining")) + 0.01)
	_suite.assert_equal(boss.get_action_resolution_count_for_test("SLAM"), 1, "converted control still resolves the committed action exactly once")
	_suite.assert_equal(boss.get_boss_ui_snapshot().get("phase"), "IDLE", "converted recovery returns to the existing idle clock")

	boss.apply_elemental_status(&"burn", &"phase_burn", 6, 120, 2.0, 30)
	var health: Node = boss.get_node("HealthComponent")
	health.current_hp = health.max_hp * 0.50
	boss.call("_update_phase")
	_suite.assert_equal(boss.get_boss_ui_snapshot().get("boss_phase"), 2, "fixture crosses the boss phase boundary")
	_suite.assert_equal(boss.elemental_status_snapshot().get("source_count"), 0, "boss phase transition clears all owned statuses")
	await _cleanup_boss_fixture(subject)


func _runtime(seed: int):
	var runtime = ElementalStatusRuntimeScript.new()
	runtime.configure(seed, 0.30)
	return runtime


func _configure_enemy_blind_fixture(enemy: Node, seed: int, seed_material: String) -> void:
	enemy.configure_elemental_status_seed(seed, 0.30)
	enemy.set_meta("elemental_status_seed_initialized", seed)
	enemy.set_meta("elemental_status_seed_material", seed_material)
	enemy.apply_elemental_status(&"blind", &"steam", 10, 30, 0.50)


func _blind_results_for_enemy(enemy: Node) -> Array[bool]:
	var results: Array[bool] = []
	for action_sequence: int in range(32):
		results.append(enemy.elemental_status_runtime.should_blind_miss(action_sequence))
	return results


func _enemy_fixture() -> Node:
	var enemy = EnemyBaseScript.new()
	enemy.name = "ElementalEnemy"
	var health = HealthComponentScript.new()
	health.name = "HealthComponent"
	enemy.add_child(health)
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = PackedVector2Array([Vector2(8, 0), Vector2(-4, -4), Vector2(-4, 4)])
	enemy.add_child(visual)
	add_child(enemy)
	await get_tree().process_frame
	enemy.set_physics_process(false)
	return enemy


func _boss_fixture() -> Dictionary:
	var target := Node2D.new()
	target.name = "PlayerTarget"
	target.add_to_group("player")
	var target_health := HealthComponentScript.new()
	target_health.name = "HealthComponent"
	target_health.max_hp = 500.0
	target.add_child(target_health)
	add_child(target)
	target.global_position = Vector2(32.0, 0.0)

	var boss := BossScene.instantiate()
	boss.set_physics_process(false)
	boss.configure_hostile_identity(&"elemental-status-boss", 1)
	add_child(boss)
	boss.set_physics_process(false)
	boss.global_position = Vector2.ZERO
	boss._pattern_timer = 99.0
	boss._attack_cooldown_remaining = 99.0
	await get_tree().process_frame
	return {"boss": boss, "target": target}


func _cleanup_boss_fixture(subject: Dictionary) -> void:
	var boss: Node = subject["boss"]
	var target: Node = subject["target"]
	if is_instance_valid(boss):
		boss.queue_free()
	if is_instance_valid(target):
		target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
