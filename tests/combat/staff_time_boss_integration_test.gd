extends Node

const BossScene := preload("res://scenes/enemies/boss_chrono_warden.tscn")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const StaffWeaponRuntimeScript := preload("res://scripts/combat/weapons/staff_weapon_runtime.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"


class RecordingStaffAdapter extends Node2D:
	var base_attack: float = 9.0
	var attack_speed: float = 0.85
	var staged_definition: Dictionary = {}
	var _active: bool = false


	func begin_profile_action(definition: Dictionary) -> Dictionary:
		if _active:
			return {}
		staged_definition = definition.duplicate(true)
		_active = true
		return staged_definition.duplicate(true)


	func release_profile_action() -> bool:
		return _active


	func is_profile_action_active() -> bool:
		return _active


	func cancel_profile_action() -> void:
		_clear_action()


	func finish_profile_action() -> void:
		_clear_action()


	func reset_runtime_state() -> void:
		_clear_action()


	func _clear_action() -> void:
		_active = false
		staged_definition.clear()


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_time_source_generations_and_rewind_claim_are_atomic()
	_test_rift_combo_rejects_stale_callbacks_and_refunds_once()
	await _test_boss_windup_rejects_control_even_while_exposed()
	await _test_boss_recovery_and_exposed_conversions_are_generation_owned()
	_suite.finish(get_tree())


func _test_time_source_generations_and_rewind_claim_are_atomic() -> void:
	var fixture := _staff_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var adapter: RecordingStaffAdapter = fixture["adapter"]
	_suite.assert_true(bool(fixture.get("configured", false)), "Staff time-integration fixture configures")

	for missing_case: Dictionary in [
		{"label": "Stop", "intent": _press_intent(&"weapon_skill"), "time": {"stop_active": true}},
		{"label": "Rewind", "intent": _release_intent(&"weapon_primary", 30), "time": {"rewind_echo_available": true}},
		{"label": "Accelerate", "intent": _press_intent(&"weapon_primary"), "time": {"accelerate_active": true}},
		{"label": "Rift", "intent": _release_intent(&"weapon_primary", 30), "time": {"rift_active": true}},
	]:
		var missing_context := _context(1000)
		missing_context["time_interactions"] = (missing_case["time"] as Dictionary).duplicate(true)
		_suite.assert_equal(
			runtime.plan_intent(missing_case["intent"], missing_context).get("code"),
			&"SOURCE_GENERATION_REQUIRED",
			"%s fails closed without a source generation" % missing_case["label"]
		)

	var stop_context := _context(1001)
	stop_context["time_interactions"] = {"stop_active": true, "stop_generation": 71}
	var stop_plan: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), stop_context).get("plan", {})
	var stop_descriptor := _interaction(stop_plan, "staff_stop_field")
	_suite.assert_equal(stop_descriptor.get("source_generation"), 71, "Stop freezes its source generation in the plan")
	_suite.assert_true(bool(runtime.commit_action(stop_plan, 7101).get("ok", false)), "Stop-enhanced Plane Collapse commits")
	_suite.assert_equal(
		_interaction(adapter.staged_definition, "staff_stop_field").get("source_generation"),
		71,
		"Stop source generation survives payload staging"
	)
	runtime.cancel_action(7101, &"stop_generation_verified")

	var accelerate_context := _context(1002)
	accelerate_context["time_interactions"] = {"accelerate_active": true, "accelerate_generation": 72}
	var accelerate_hold: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), accelerate_context).get("plan", {})
	_suite.assert_equal(_phase(accelerate_hold, 0).get("charge_complete_frames"), 15, "Accelerate shortens the authoritative Staff charge")
	var accelerated: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 15), accelerate_context).get("plan", {})
	_suite.assert_equal(_interaction(accelerated, "staff_fast_charge").get("source_generation"), 72, "Accelerate freezes its source generation")
	_suite.assert_true(bool(runtime.commit_action(accelerated, 7201).get("ok", false)), "Accelerated charged cast commits")
	_suite.assert_equal(
		_interaction(adapter.staged_definition, "staff_fast_charge").get("source_generation"),
		72,
		"Accelerate source generation survives payload staging"
	)
	runtime.cancel_action(7201, &"accelerate_generation_verified")

	runtime.reset_runtime_state(&"rewind_fixture")
	var rewind_context := _context(1003)
	rewind_context["time_interactions"] = {"rewind_echo_available": true, "rewind_echo_generation": 73}
	var first_rewind: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), rewind_context).get("plan", {})
	var stale_prebuilt_rewind: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), rewind_context).get("plan", {})
	_suite.assert_close(float(first_rewind.get("mana_cost", -1.0)), 0.0, "Rewind grants one Mana-free charged cast")
	_suite.assert_equal(_interaction(first_rewind, "staff_rewind_free_cast").get("rewind_generation"), 73, "Rewind freezes the echo generation")
	_suite.assert_true(bool(runtime.commit_action(first_rewind, 7301).get("ok", false)), "first Rewind generation claim commits")
	runtime.cancel_action(7301, &"rewind_cast_cancelled")
	var mana_before_stale := float(runtime.snapshot().get("mana", 0.0))
	_suite.assert_equal(
		runtime.commit_action(stale_prebuilt_rewind, 7302).get("code"),
		&"STALE_REWIND_GENERATION",
		"a prebuilt plan cannot reuse an already claimed Rewind generation"
	)
	_suite.assert_close(float(runtime.snapshot().get("mana", 0.0)), mana_before_stale, "stale Rewind rejection does not mutate Mana")
	var replanned: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), rewind_context).get("plan", {})
	_suite.assert_close(float(replanned.get("mana_cost", 0.0)), 20.0, "claimed Rewind generation falls back to the ordinary element cost")
	_suite.assert_true(_interaction(replanned, "staff_rewind_free_cast").is_empty(), "claimed Rewind generation emits no second interaction")
	_free_staff_fixture(fixture)


func _test_rift_combo_rejects_stale_callbacks_and_refunds_once() -> void:
	var fixture := _staff_fixture()
	var runtime: RefCounted = fixture["runtime"]
	_suite.assert_true(bool(fixture.get("configured", false)), "Staff Rift-integration fixture configures")

	var fire: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(2001)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(fire, 8101).get("ok", false)), "Rift fixture Fire cast commits")
	var cast_ledger: Dictionary = (runtime.snapshot().get("cast_ledgers", {}) as Dictionary).get("8101", {})
	_suite.assert_equal(cast_ledger.get("generation"), 8101, "new Staff cast binds callbacks to its action generation")
	var fire_result: Dictionary = runtime.payload_result(8101, 8101, &"fire_open", &"fire", 8101, true, 0.0, true)
	_suite.assert_equal(fire_result.get("code"), &"OK", "confirmed Fire payload uses the live cast generation")
	_suite.assert_true(
		bool(fire_result.get("ok", false)),
		"confirmed Fire payload opens the ordered-combination window"
	)
	runtime.finish_action(8101)
	_suite.assert_true(_cycle_element(runtime, 8102), "Rift fixture cycles Fire to Ice")

	var rift_context := _context(2002)
	rift_context["time_interactions"] = {"rift_active": true, "rift_generation": 82}
	var combo: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), rift_context).get("plan", {})
	var rift_descriptor := _interaction(combo, "staff_rift_combination")
	_suite.assert_equal(rift_descriptor.get("source_generation"), 82, "Rift freezes its source generation")
	_suite.assert_equal(rift_descriptor.get("combo_id"), "steam_burst", "Rift binds the frozen ordered pair")
	_suite.assert_true(bool(runtime.commit_action(combo, 8103).get("ok", false)), "Rift combination reserves base and surcharge Mana")
	_suite.assert_close(float(runtime.snapshot().get("mana", 0.0)), 40.0, "Rift combination reserves forty Mana before outcome")

	var refunded: Dictionary = runtime.payload_result(8103, 8103, &"rift_terminal_miss", &"ice", -1, true, 0.0, false)
	_suite.assert_close(float(refunded.get("refunded_mana", 0.0)), 15.0, "terminal miss refunds the combination surcharge once")
	_suite.assert_close(float(runtime.snapshot().get("mana", 0.0)), 55.0, "terminal miss preserves the base cost and restores only the surcharge")
	_suite.assert_equal(runtime.payload_result(8103, 8103, &"rift_terminal_miss", &"ice", -1, true, 0.0, false).get("code"), &"OUTCOME_TERMINAL", "duplicate terminal callback is rejected")
	_suite.assert_equal(runtime.payload_result(8103, 8104, &"rift_terminal_miss", &"ice", -1, true, 0.0, false).get("code"), &"STALE_GENERATION", "stale payload generation is rejected")
	_suite.assert_close(float(runtime.snapshot().get("mana", 0.0)), 55.0, "duplicate and stale callbacks cannot refund twice")
	runtime.finish_action(8103)
	_free_staff_fixture(fixture)


func _test_boss_windup_rejects_control_even_while_exposed() -> void:
	var subject := await _boss_fixture()
	var boss: Node = subject["boss"]
	_suite.assert_true(boss.force_action_for_test("SLAM"), "Boss commits a SLAM for the Staff control boundary")
	boss.apply_time_stop_source(&"staff_stop:91", 0.5)
	boss.apply_time_rift(&"staff_rift:92", 0.45)
	var before: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_equal(before.get("phase"), "WINDUP", "Stop and Rift preserve the committed WINDUP")
	_suite.assert_true(bool(before.get("exposed", false)), "Stop and Rift expose the Boss without replacing its action")
	_suite.assert_true(not boss.apply_elemental_status(&"freeze", &"staff_ice", 91, 60), "WINDUP rejects Staff Freeze even while exposed")
	_suite.assert_true(not boss.apply_elemental_status(&"blind", &"staff_steam", 92, 60, 0.75), "WINDUP rejects Staff Blind even while exposed")
	_suite.assert_equal(boss.get_boss_ui_snapshot(), before, "rejected Staff control leaves committed Boss state unchanged")
	_suite.assert_equal(boss.elemental_status_snapshot().get("source_count"), 0, "rejected WINDUP control creates no owned status")
	boss.clear_time_stop_source(&"staff_stop:91")
	boss.clear_time_rift(&"staff_rift:92")
	await _cleanup_boss_fixture(subject)


func _test_boss_recovery_and_exposed_conversions_are_generation_owned() -> void:
	var subject := await _boss_fixture()
	var boss: Node = subject["boss"]
	_suite.assert_true(boss.force_action_for_test("SLAM"), "Boss commits a SLAM before Staff recovery conversion")
	var windup: Dictionary = boss.get_boss_ui_snapshot()
	boss.advance_action_for_test(float(windup.get("remaining", 0.0)) + 0.01)
	var recovery: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_equal(recovery.get("phase"), "RECOVERY", "Staff control fixture reaches Boss RECOVERY")

	_suite.assert_true(boss.apply_elemental_status(&"freeze", &"staff_ice", 101, 60), "RECOVERY converts Staff Freeze generation 101")
	var freeze_101: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_close(float(freeze_101.get("remaining")), float(recovery.get("remaining")) + 12.0 / 60.0, "Freeze converts to twelve recovery-delay frames")
	_suite.assert_true(boss.apply_elemental_status(&"freeze", &"staff_ice", 101, 90), "same Freeze tuple refreshes its lifetime")
	_suite.assert_close(float(boss.get_boss_ui_snapshot().get("remaining")), float(freeze_101.get("remaining")), "same Freeze tuple does not duplicate its delay")
	_suite.assert_true(boss.apply_elemental_status(&"freeze", &"staff_ice", 102, 60), "a new Freeze generation owns an independent conversion")
	var freeze_102: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_close(float(freeze_102.get("remaining")), float(freeze_101.get("remaining")) + 12.0 / 60.0, "new Freeze generation adds one bounded delay")
	_suite.assert_equal(boss.clear_owned_elemental_statuses(&"staff_ice", 101), 1, "exact cleanup removes only Freeze generation 101")
	_suite.assert_true(boss.has_elemental_status(&"freeze", &"staff_ice", 102), "exact cleanup preserves Freeze generation 102")

	_suite.assert_true(boss.apply_elemental_status(&"blind", &"staff_steam", 103, 60, 0.75), "RECOVERY converts Staff Blind")
	var blinded: Dictionary = boss.get_boss_ui_snapshot()
	_suite.assert_close(float(blinded.get("remaining")), float(freeze_102.get("remaining")) + 8.0 / 60.0, "Blind converts to eight recovery-delay frames")
	_suite.assert_equal(boss.get_action_resolution_count_for_test("SLAM"), 1, "Staff conversions never re-resolve the committed SLAM")
	boss.advance_action_for_test(float(blinded.get("remaining", 0.0)) + 0.01)
	_suite.assert_equal(boss.get_boss_ui_snapshot().get("phase"), "IDLE", "converted recovery returns to the existing IDLE clock")

	boss.apply_time_rift(&"staff_rift:104", 0.45)
	boss._pattern_timer = 0.4
	_suite.assert_true(boss.apply_elemental_status(&"freeze", &"staff_exposed_ice", 104, 60), "EXPOSED idle Boss accepts Freeze conversion")
	_suite.assert_close(boss._pattern_timer, 0.4 + 12.0 / 60.0, "EXPOSED Freeze delays only the idle pattern clock")
	_suite.assert_true(boss.apply_elemental_status(&"blind", &"staff_exposed_steam", 105, 60, 0.75), "EXPOSED idle Boss accepts Blind conversion")
	_suite.assert_close(boss._pattern_timer, 0.4 + 20.0 / 60.0, "EXPOSED Blind adds its bounded eight-frame delay")
	_suite.assert_equal(boss.get_boss_ui_snapshot().get("action"), "NONE", "EXPOSED conversions invent no Boss action")

	var health: Node = boss.get_node("HealthComponent")
	health.current_hp = health.max_hp * 0.50
	boss.call("_update_phase")
	_suite.assert_equal(boss.get_boss_ui_snapshot().get("boss_phase"), 2, "Boss crosses the phase boundary")
	_suite.assert_equal(boss.elemental_status_snapshot().get("source_count"), 0, "phase transition clears every Staff source generation")
	boss.clear_time_rift(&"staff_rift:104")
	await _cleanup_boss_fixture(subject)


func _staff_fixture() -> Dictionary:
	var owner := Node2D.new()
	var adapter := RecordingStaffAdapter.new()
	adapter.name = "StaffWeapon"
	owner.add_child(adapter)
	var definition := _catalog_profile("staff_launch_v1")
	var profile = WeaponRuntimeProfileScript.new()
	var parsed: Dictionary = profile.configure(definition)
	var modifiers = WeaponModifierStateScript.new()
	var capabilities := PackedStringArray(definition.get("capabilities", []))
	var configured_modifiers := modifiers.configure(capabilities, _modifier_bounds(capabilities))
	var runtime = StaffWeaponRuntimeScript.new()
	var configured := bool(parsed.get("ok", false)) and configured_modifiers and runtime.configure(owner, profile, modifiers)
	return {
		"owner": owner,
		"adapter": adapter,
		"runtime": runtime,
		"configured": configured,
	}


func _free_staff_fixture(fixture: Dictionary) -> void:
	var owner: Node = fixture.get("owner")
	if owner != null and is_instance_valid(owner):
		owner.free()


func _boss_fixture() -> Dictionary:
	var target := Node2D.new()
	target.name = "StaffBossTarget"
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


func _cleanup_boss_fixture(subject: Dictionary) -> void:
	for key: String in ["boss", "target"]:
		var node: Node = subject[key]
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _cycle_element(runtime: RefCounted, token: int) -> bool:
	var plan_result: Dictionary = runtime.plan_intent(_press_intent(&"weapon_utility"), _context(9000 + token))
	if not bool(plan_result.get("ok", false)):
		return false
	var plan: Dictionary = plan_result["plan"]
	if not bool(runtime.commit_action(plan, token).get("ok", false)):
		return false
	runtime.finish_action(token)
	return true


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


func _phase(plan: Dictionary, index: int) -> Dictionary:
	var phases_value: Variant = plan.get("phases", [])
	if not phases_value is Array or index < 0 or index >= (phases_value as Array).size():
		return {}
	var value: Variant = (phases_value as Array)[index]
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _interaction(container: Dictionary, interaction_id: String) -> Dictionary:
	var values: Variant = container.get("time_interactions", [])
	if not values is Array:
		return {}
	for value: Variant in values as Array:
		if value is Dictionary and str((value as Dictionary).get("interaction_id", "")) == interaction_id:
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


func _modifier_bounds(capabilities: PackedStringArray) -> Dictionary:
	var bounds: Dictionary = {}
	for capability: String in capabilities:
		bounds[capability] = {"minimum": 0.1, "maximum": 200.0}
	return bounds
