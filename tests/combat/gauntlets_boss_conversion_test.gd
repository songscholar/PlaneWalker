extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")

const EXPECTED_POISE_MULTIPLIER := 1.4

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_damage_info_copy_preserves_control_contract()
	await _test_windup_rejects_launch_without_mutating_committed_action()
	await _test_recovery_converts_launch_to_deduplicated_poise()
	await _test_phase_and_explicit_reset_cleanup_preserve_generation_safety()
	await _test_dead_target_clears_control_ownership_and_rejects_callbacks()
	_suite.finish(get_tree())


func _test_damage_info_copy_preserves_control_contract() -> void:
	var original := _launch_damage(101, 101)
	var copied: RefCounted = original.copy_for_source(self)
	_suite.assert_equal(int(copied.get("action_token")), 101, "DamageInfo copies the Gauntlets action token")
	_suite.assert_equal(int(copied.get("source_generation")), 101, "DamageInfo copies the Gauntlets source generation")
	_suite.assert_equal(
		(copied.get("control_effect") as Dictionary).get("conversion_id"),
		"gauntlets_poised_launch",
		"DamageInfo copies the Boss conversion identity"
	)
	(copied.get("control_effect") as Dictionary)["poise_damage"] = 99.0
	var copied_tags: Array[String] = copied.get("tags")
	copied_tags.append("mutated:test")
	_suite.assert_close(
		float((original.get("control_effect") as Dictionary).get("poise_damage")),
		10.0,
		"copied control payload cannot mutate the committed original"
	)
	_suite.assert_equal(
		copied.get("tags"),
		["weapon:gauntlets", "action:punch_5", "control:launch"],
		"copied tag getter cannot mutate the copied DamageInfo"
	)
	_suite.assert_equal(
		original.get("tags"),
		["weapon:gauntlets", "action:punch_5", "control:launch"],
		"copied tag mutation cannot alter the committed original"
	)


func _test_windup_rejects_launch_without_mutating_committed_action() -> void:
	var subject := await _boss_fixture()
	var boss: Node = subject["boss"]
	var health: Node = boss.get_node("HealthComponent")
	_suite.assert_true(boss.force_action_for_test("SLAM"), "Gauntlets fixture commits a Boss SLAM")
	var before: Dictionary = boss.get_boss_ui_snapshot()
	var position_before: Vector2 = boss.global_position
	_suite.assert_true(health.take_damage(_launch_damage(201, 201)) > 0.0, "launch hit still deals resolved damage during WINDUP")
	var after: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_equal(after.get("action"), before.get("action"), "rejected launch preserves the committed action")
	_suite.assert_equal(after.get("phase"), "WINDUP", "rejected launch preserves the committed WINDUP")
	_suite.assert_close(float(after.get("remaining")), float(before.get("remaining")), "rejected launch cannot rewrite the action clock")
	_suite.assert_equal(boss.global_position, position_before, "unsupported launch never moves the Boss during WINDUP")
	var control: Dictionary = boss.get_weapon_control_snapshot_for_test()
	_suite.assert_close(float(control.get("poise", -1.0)), 0.0, "rejected WINDUP launch adds no poise")
	_suite.assert_equal(int(control.get("hit_claim_count", -1)), 0, "rejected WINDUP launch consumes no target claim")
	_suite.assert_true(not bool(control.get("airborne", true)), "Chrono Warden never enters unsupported airborne state")
	await _cleanup_fixture(subject)


func _test_recovery_converts_launch_to_deduplicated_poise() -> void:
	var subject := await _boss_fixture()
	var boss: Node = subject["boss"]
	var health: Node = boss.get_node("HealthComponent")
	_suite.assert_true(boss.force_action_for_test("SLAM"), "Boss commits SLAM before the Gauntlets recovery conversion")
	var windup: Dictionary = boss.get_boss_ui_snapshot()
	boss.advance_action_for_test(float(windup.get("remaining", 0.0)) + 0.01)
	var recovery: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_equal(recovery.get("phase"), "RECOVERY", "Gauntlets conversion fixture reaches Boss recovery")
	var position_before: Vector2 = boss.global_position
	var first_hit := _launch_damage(301, 301)
	_suite.assert_true(health.take_damage(first_hit) > 0.0, "eligible Gauntlets launch deals resolved damage")
	var converted: Dictionary = boss.get_weapon_control_snapshot_for_test()
	_suite.assert_close(
		float(converted.get("poise", 0.0)),
		10.0 * EXPECTED_POISE_MULTIPLIER,
		"Chrono Warden applies the authoritative 1.4 Gauntlets poise multiplier"
	)
	_suite.assert_equal(int(converted.get("source_count", -1)), 0, "pure poise conversion leaves no timer-backed source")
	_suite.assert_equal(int(converted.get("hit_claim_count", 0)), 1, "eligible launch claims this action token for the target")
	_suite.assert_true(not bool(converted.get("airborne", true)), "eligible launch converts to poise instead of airborne")
	_suite.assert_equal(boss.global_position, position_before, "poise conversion uses no unsupported displacement path")
	_suite.assert_equal(boss.get_action_resolution_count_for_test("SLAM"), 1, "poise conversion cannot resolve the committed attack twice")

	_suite.assert_true(health.take_damage(first_hit) > 0.0, "duplicate payload may still deal ordinary damage")
	var duplicate: Dictionary = boss.get_weapon_control_snapshot_for_test()
	_suite.assert_close(float(duplicate.get("poise", 0.0)), 14.0, "same action token and target cannot add poise twice")
	_suite.assert_equal(int(duplicate.get("source_count", -1)), 0, "duplicate payload cannot create a timer-backed source")

	_suite.assert_true(health.take_damage(_launch_damage(302, 999)) > 0.0, "stale-generation payload still resolves ordinary damage")
	_suite.assert_close(
		float(boss.get_weapon_control_snapshot_for_test().get("poise", 0.0)),
		14.0,
		"mismatched action/source generation cannot add poise"
	)
	var airborne := _launch_damage(303, 303, {"airborne": true})
	_suite.assert_true(health.take_damage(airborne) > 0.0, "invalid airborne payload still resolves ordinary damage")
	_suite.assert_close(
		float(boss.get_weapon_control_snapshot_for_test().get("poise", 0.0)),
		14.0,
		"airborne payload is rejected atomically at the Boss boundary"
	)
	var wrong_multiplier := _launch_damage(304, 304, {"boss_poise_multiplier": 1.5})
	_suite.assert_true(health.take_damage(wrong_multiplier) > 0.0, "numeric-authority drift still resolves ordinary damage")
	_suite.assert_close(
		float(boss.get_weapon_control_snapshot_for_test().get("poise", 0.0)),
		14.0,
		"Boss rejects a drifted Gauntlets poise multiplier"
	)
	_suite.assert_equal(boss.get_boss_ui_snapshot().get("phase"), "RECOVERY", "conversion preserves the committed recovery phase")
	await _cleanup_fixture(subject)


func _test_phase_and_explicit_reset_cleanup_preserve_generation_safety() -> void:
	var subject := await _boss_fixture()
	var boss: Node = subject["boss"]
	var health: Node = boss.get_node("HealthComponent")
	_suite.assert_true(boss.force_action_for_test("SLAM"), "phase-cleanup fixture commits SLAM")
	var windup: Dictionary = boss.get_boss_ui_snapshot()
	boss.advance_action_for_test(float(windup.get("remaining", 0.0)) + 0.01)
	health.take_damage(_launch_damage(401, 401))
	_suite.assert_close(float(boss.get_weapon_control_snapshot_for_test().get("poise", 0.0)), 14.0, "fixture owns poise before phase change")

	health.current_hp = health.max_hp * 0.50
	boss.call("_update_phase")
	var phased: Dictionary = boss.get_weapon_control_snapshot_for_test()
	_suite.assert_close(float(phased.get("poise", -1.0)), 0.0, "phase change clears accumulated weapon poise")
	_suite.assert_equal(int(phased.get("source_count", -1)), 0, "phase change clears source-generation ownership")
	boss.apply_time_rift(&"gauntlets_phase_fixture", 0.45)
	health.take_damage(_launch_damage(401, 401))
	_suite.assert_close(
		float(boss.get_weapon_control_snapshot_for_test().get("poise", 0.0)),
		0.0,
		"phase cleanup retains the action-token tombstone against stale callbacks"
	)
	health.take_damage(_launch_damage(402, 402))
	_suite.assert_close(float(boss.get_weapon_control_snapshot_for_test().get("poise", 0.0)), 14.0, "new generation can contribute after phase cleanup")

	boss.call("clear_weapon_hit_control_state", &"gauntlets_test_reset")
	var reset: Dictionary = boss.get_weapon_control_snapshot_for_test()
	_suite.assert_close(float(reset.get("poise", -1.0)), 0.0, "explicit runtime reset clears poise")
	_suite.assert_equal(int(reset.get("source_count", -1)), 0, "explicit runtime reset clears source owners")
	_suite.assert_equal(int(reset.get("hit_claim_count", -1)), 0, "explicit runtime reset clears target claims")
	health.take_damage(_launch_damage(401, 401))
	_suite.assert_close(float(boss.get_weapon_control_snapshot_for_test().get("poise", 0.0)), 14.0, "fresh run may reuse its reset action token")
	boss.clear_time_rift(&"gauntlets_phase_fixture")
	await _cleanup_fixture(subject)


func _test_dead_target_clears_control_ownership_and_rejects_callbacks() -> void:
	var subject := await _boss_fixture()
	var boss: Node = subject["boss"]
	var health: Node = boss.get_node("HealthComponent")
	boss.apply_time_rift(&"gauntlets_death_fixture", 0.45)
	health.take_damage(_launch_damage(501, 501))
	_suite.assert_close(float(boss.get_weapon_control_snapshot_for_test().get("poise", 0.0)), 14.0, "death fixture owns weapon poise")
	health.lose_health(health.current_hp, self)
	var dead_snapshot: Dictionary = boss.get_weapon_control_snapshot_for_test()
	_suite.assert_close(float(dead_snapshot.get("poise", -1.0)), 0.0, "death clears weapon poise synchronously")
	_suite.assert_equal(int(dead_snapshot.get("source_count", -1)), 0, "death clears source-generation ownership")
	_suite.assert_equal(int(dead_snapshot.get("hit_claim_count", -1)), 0, "death clears target claims")
	_suite.assert_close(health.take_damage(_launch_damage(502, 502)), 0.0, "dead target rejects late damage and control callbacks")
	await get_tree().create_timer(0.22).timeout
	await _cleanup_fixture(subject)


func _launch_damage(action_token: int, source_generation: int, overrides: Dictionary = {}) -> RefCounted:
	var effect := {
		"kind": "launch",
		"conversion_id": "gauntlets_poised_launch",
		"airborne": false,
		"poise_damage": 10.0,
		"boss_poise_multiplier": EXPECTED_POISE_MULTIPLIER,
		"displacement_pixels": 96.0,
		"allowed_states": ["RECOVERY", "EXPOSED"],
		"active_attack_policy": "preserve_committed",
		"interrupt_active_attack": false,
	}
	for key: Variant in overrides.keys():
		effect[key] = overrides[key]
	return DamageInfoScript.from_plan({
		"run_id": &"test_run",
		"target_id": &"boss_fixture",
		"hostile_source_id": StringName("test:gauntlets:%d:%d" % [action_token, source_generation]),
		"attack_generation": source_generation,
		"action_token": action_token,
		"amount": 8.0,
		"damage_type": DamageInfoScript.DamageType.PHYSICAL,
		"source": self,
		"attacker": self,
		"tags": ["weapon:gauntlets", "action:punch_5", "control:launch"],
		"source_generation": source_generation,
		"control_effect": effect,
	})


func _boss_fixture() -> Dictionary:
	var target := Node2D.new()
	target.name = "GauntletsBossTarget"
	target.add_to_group("player")
	var target_health := HealthComponentScript.new()
	target_health.name = "HealthComponent"
	target_health.max_hp = 500.0
	target.add_child(target_health)
	add_child(target)
	target.global_position = Vector2(32.0, 0.0)

	var boss := BossScene.instantiate()
	boss.set_physics_process(false)
	add_child(boss)
	boss.set_physics_process(false)
	boss.global_position = Vector2.ZERO
	boss._pattern_timer = 99.0
	boss._attack_cooldown_remaining = 99.0
	await get_tree().process_frame
	return {"boss": boss, "target": target}


func _cleanup_fixture(subject: Dictionary) -> void:
	await get_tree().create_timer(0.10).timeout
	for key: String in ["boss", "target"]:
		var node_value: Variant = subject.get(key)
		if is_instance_valid(node_value):
			(node_value as Node).queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
