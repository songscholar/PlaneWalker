extends Node

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")
const HealthComponentScript := preload("res://scripts/combat/health_component.gd")
const HitboxScript := preload("res://scripts/combat/hitbox.gd")
const SwordWeaponScript := preload("res://scripts/combat/sword_weapon.gd")
const SwordWeaponRuntimeScript := preload("res://scripts/combat/weapons/sword_weapon_runtime.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const PROFILE_ID := "sword_launch_v1"
const CAPABILITY_BOUNDS := {
	"weapon.attack_speed": {"minimum": 0.2, "maximum": 5.0},
	"weapon.charge_rate": {"minimum": 0.0, "maximum": 6.0},
	"weapon.combo_finisher_damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.heavy_damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.heavy_execute_damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.heavy_execute_threshold": {"minimum": 0.0, "maximum": 1.0},
	"weapon.low_hp_damage": {"minimum": 0.0, "maximum": 10.0},
	"weapon.status_duration": {"minimum": 0.0, "maximum": 10.0},
}

var _suite


class PayloadTarget:
	extends Area2D
	var received_damage: float = 0.0
	var received_tags: Array[String] = []

	func receive_hit(damage_info: RefCounted) -> void:
		received_damage += float(damage_info.get("amount"))
		for tag: Variant in damage_info.get("tags") as Array:
			received_tags.append(str(tag))


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	await _test_launch_profile_identity_and_primary_hold_release()
	await _test_launch_resources_guard_and_counter_transaction()
	await _test_launch_resource_exhaustion_is_atomic()
	await _test_launch_light_chain_progresses_and_wraps()
	await _test_all_launch_semantic_slots_commit_and_release()
	await _test_launch_zone_and_wave_execute_distinct_payloads()
	await _test_launch_all_active_phases_restore_exactly()
	await _test_launch_cancel_reset_snapshot_restore_and_presentation()
	_suite.finish(get_tree())


func _test_launch_profile_identity_and_primary_hold_release() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var configured: bool = fixture["configured"]
	_suite.assert_true(configured, "Sword Launch runtime configures against the authoritative launch profile")
	if not configured:
		await _free_player(fixture["player"])
		return

	var identity: Dictionary = runtime.snapshot()
	_suite.assert_equal(identity.get("profile_id"), PROFILE_ID, "Launch snapshot exposes the Launch profile id")
	_suite.assert_equal(identity.get("profile_version"), 1, "Launch snapshot exposes the Launch profile version")
	_suite.assert_true(runtime.capabilities().has("weapon.status_duration"), "Launch-only capability is retained")

	var pressed: Dictionary = runtime.plan_intent(_intent(&"weapon_primary", &"pressed"), {})
	_suite.assert_true(bool(pressed.get("ok", false)), "primary press produces a hold skeleton")
	var hold_plan: Dictionary = pressed.get("plan", {})
	_suite.assert_equal(_phase(hold_plan, 0).get("phase"), "HOLD", "primary press starts HOLD")
	_suite.assert_equal(_phase(hold_plan, 0).get("charge_complete_frames"), 30, "charged slash threshold is profile-authored")
	_suite.assert_true(bool(runtime.commit_action(hold_plan, 101).get("ok", false)), "primary HOLD commits")
	_suite.assert_equal(runtime.presentation_snapshot().get("phase"), "HOLD", "presentation exposes committed HOLD")

	var quick_release: Dictionary = runtime.release_hold(hold_plan, 101, 12)
	_suite.assert_true(bool(quick_release.get("ok", false)), "short primary release finalizes")
	var quick_plan: Dictionary = quick_release.get("finalized_plan", {})
	_suite.assert_equal(quick_plan.get("action_id"), "light_chain", "short primary release selects light chain")
	_assert_action_lifecycle(runtime, quick_plan, 101, "light_chain")

	var charged_pressed: Dictionary = runtime.plan_intent(_intent(&"weapon_primary", &"pressed"), {})
	var charged_hold: Dictionary = charged_pressed.get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(charged_hold, 102).get("ok", false)), "second primary HOLD commits")
	var charged_release: Dictionary = runtime.release_hold(charged_hold, 102, 30)
	_suite.assert_true(bool(charged_release.get("ok", false)), "threshold primary release finalizes")
	var charged_plan: Dictionary = charged_release.get("finalized_plan", {})
	_suite.assert_equal(charged_plan.get("action_id"), "charged_slash", "threshold primary release selects charged slash")
	_assert_action_lifecycle(runtime, charged_plan, 102, "charged_slash")
	await _free_player(fixture["player"])


func _test_all_launch_semantic_slots_commit_and_release() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	if not fixture["configured"]:
		await _free_player(fixture["player"])
		return

	var guard_planned: Dictionary = runtime.plan_intent(_intent(&"weapon_secondary", &"pressed"), {})
	var guard_plan: Dictionary = guard_planned.get("plan", {})
	_suite.assert_true(bool(guard_planned.get("ok", false)), "guard semantic plans")
	_suite.assert_true(bool(runtime.commit_action(guard_plan, 201).get("ok", false)), "guard commits")
	runtime.on_phase_enter(guard_plan, &"WINDUP", 201)
	runtime.on_phase_enter(guard_plan, &"ACTIVE", 201)
	var guard_damage := DamageInfoScript.new(50.0, DamageInfoScript.DamageType.PHYSICAL, self, self)
	fixture["health"].take_damage(guard_damage)
	runtime.on_phase_enter(guard_plan, &"RECOVERY", 201)
	runtime.finish_action(201)

	var direct_cases: Array[Dictionary] = [
		{"semantic": &"weapon_utility", "action": "counter", "token": 202},
		{"semantic": &"weapon_skill", "action": "temporal_judgment", "token": 203},
	]
	for case: Dictionary in direct_cases:
		var planned: Dictionary = runtime.plan_intent(_intent(case["semantic"], &"pressed"), {})
		_suite.assert_true(bool(planned.get("ok", false)), "%s semantic plans" % case["action"])
		var plan: Dictionary = planned.get("plan", {})
		_suite.assert_equal(plan.get("action_id"), case["action"], "%s resolves the authored action" % case["action"])
		_suite.assert_true(bool(runtime.commit_action(plan, case["token"]).get("ok", false)), "%s commits" % case["action"])
		_assert_action_lifecycle(runtime, plan, case["token"], case["action"])

	var ultimate_pressed: Dictionary = runtime.plan_intent(_intent(&"weapon_ultimate", &"pressed"), {})
	_suite.assert_true(bool(ultimate_pressed.get("ok", false)), "ultimate press produces a hold skeleton")
	var ultimate_hold: Dictionary = ultimate_pressed.get("plan", {})
	_suite.assert_equal(_phase(ultimate_hold, 0).get("minimum_hold_frames"), 60, "ultimate preserves its charge requirement")
	_suite.assert_true(bool(runtime.commit_action(ultimate_hold, 204).get("ok", false)), "ultimate HOLD commits")
	var ultimate_release: Dictionary = runtime.release_hold(ultimate_hold, 204, 60)
	_suite.assert_true(bool(ultimate_release.get("ok", false)), "charged ultimate release finalizes")
	var ultimate_plan: Dictionary = ultimate_release.get("finalized_plan", {})
	_suite.assert_equal(ultimate_plan.get("action_id"), "primordial_edge", "ultimate release resolves Primordial Edge")
	_assert_action_lifecycle(runtime, ultimate_plan, 204, "primordial_edge")
	await _free_player(fixture["player"])


func _test_launch_resources_guard_and_counter_transaction() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var player: Node = fixture["player"]
	var health: Node = fixture["health"]
	var sword: Node = fixture["sword"]
	if not fixture["configured"]:
		await _free_player(player)
		return

	var initial: Dictionary = runtime.snapshot()
	var initial_resources: Dictionary = initial.get("resources", {})
	_suite.assert_close(float((initial_resources.get("guard", {}) as Dictionary).get("current", -1.0)), 100.0, "Guard starts full")
	_suite.assert_close(float((initial_resources.get("guard", {}) as Dictionary).get("maximum", -1.0)), 100.0, "Guard maximum comes from the profile")
	_suite.assert_close(float((initial_resources.get("intent", {}) as Dictionary).get("current", -1.0)), 0.0, "Intent starts empty")
	var before_counter_rejection: Dictionary = runtime.snapshot()
	var rejected_counter: Dictionary = runtime.plan_intent(_intent(&"weapon_utility", &"pressed"), {})
	_suite.assert_true(not bool(rejected_counter.get("ok", false)), "Counter rejects at zero Intent")
	_suite.assert_equal(rejected_counter.get("code"), &"INSUFFICIENT_RESOURCE", "Counter reports an explicit resource rejection")
	_suite.assert_equal(runtime.snapshot(), before_counter_rejection, "zero-Intent Counter rejection has no side effects")

	var guard_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_secondary", &"pressed"), {}).get("plan", {})
	_suite.assert_equal(_phase(guard_plan, 1).get("duration_frames"), 12, "Guard keeps a twelve-frame active window after windup")
	_suite.assert_equal(((guard_plan.get("payloads", []) as Array)[0] as Dictionary).get("parameters", {}).get("perfect_window_frames"), 3, "Guard exposes its three-frame perfect window")
	_suite.assert_true(bool(runtime.commit_action(guard_plan, 401).get("ok", false)), "Guard commits with sufficient resource")
	_suite.assert_close(float((runtime.snapshot().get("resources", {}).get("guard", {}) as Dictionary).get("current", -1.0)), 90.0, "Guard commit atomically spends ten Guard")
	runtime.on_phase_enter(guard_plan, &"ACTIVE", 401)
	runtime.advance_runtime_frame(3)
	var hp_before := float(health.current_hp)
	var incoming := DamageInfoScript.new(50.0, DamageInfoScript.DamageType.PHYSICAL, self, self)
	var applied: float = health.take_damage(incoming)
	_suite.assert_close(applied, 25.0, "active Guard applies the authored 0.5 block multiplier")
	_suite.assert_close(float(health.current_hp), hp_before - 25.0, "Guard changes authoritative player HP")
	_suite.assert_true(sword.has_method("last_guard_result_for_test"), "Sword adapter exposes an explicit Guard result contract")
	if sword.has_method("last_guard_result_for_test"):
		var guard_result: Dictionary = sword.call("last_guard_result_for_test")
		_suite.assert_close(float(guard_result.get("blocked_damage", -1.0)), 25.0, "Guard result records blocked damage")
		_suite.assert_close(float(guard_result.get("block_multiplier", -1.0)), 0.5, "Guard result records its multiplier")
	runtime.on_phase_enter(guard_plan, &"RECOVERY", 401)
	runtime.finish_action(401)

	var after_guard: Dictionary = runtime.snapshot()
	_suite.assert_close(float((after_guard.get("resources", {}).get("intent", {}) as Dictionary).get("current", -1.0)), 25.0, "blocked damage grants deterministic Intent")
	var counter_result: Dictionary = runtime.plan_intent(_intent(&"weapon_utility", &"pressed"), {})
	_suite.assert_true(bool(counter_result.get("ok", false)), "Counter plans once Intent is available")
	var counter_plan: Dictionary = counter_result.get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(counter_plan, 402).get("ok", false)), "Counter commits with exactly twenty-five Intent")
	_suite.assert_close(float((runtime.snapshot().get("resources", {}).get("intent", {}) as Dictionary).get("current", -1.0)), 0.0, "Counter atomically spends twenty-five Intent")
	runtime.on_phase_enter(counter_plan, &"WINDUP", 402)
	var counter_events: Array = runtime.on_phase_enter(counter_plan, &"ACTIVE", 402)
	_suite.assert_equal((counter_events[0] as Dictionary).get("payload_kind") if not counter_events.is_empty() else "", "hitbox", "Counter releases a real hitbox payload")
	_suite.assert_true(sword.hitbox.is_active(), "Counter activates the authoritative Sword hitbox")
	runtime.on_phase_enter(counter_plan, &"RECOVERY", 402)
	runtime.finish_action(402)

	runtime.advance_runtime_frame(1)
	runtime.advance_runtime_frame(61)
	var regenerated: Dictionary = runtime.snapshot()
	_suite.assert_close(float((regenerated.get("resources", {}).get("guard", {}) as Dictionary).get("current", -1.0)), 98.0, "Guard regenerates eight points per second")
	var presentation: Dictionary = runtime.presentation_snapshot()
	_suite.assert_equal(presentation.get("resources"), regenerated.get("resources"), "presentation exposes authoritative resources")
	_suite.assert_true(runtime.restore_snapshot(regenerated), "quiescent resource snapshot restores")
	runtime.reset_runtime_state(&"resource_reset")
	var reset_resources: Dictionary = runtime.snapshot().get("resources", {})
	_suite.assert_close(float((reset_resources.get("guard", {}) as Dictionary).get("current", -1.0)), 100.0, "reset restores initial Guard")
	_suite.assert_close(float((reset_resources.get("intent", {}) as Dictionary).get("current", -1.0)), 0.0, "reset clears Intent")

	var perfect_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_secondary", &"pressed"), {}).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(perfect_plan, 403).get("ok", false)), "Perfect Guard commits from reset resources")
	runtime.on_phase_enter(perfect_plan, &"ACTIVE", 403)
	var perfect_hp_before := float(health.current_hp)
	var perfect_damage := DamageInfoScript.new(50.0, DamageInfoScript.DamageType.PHYSICAL, self, self)
	health.take_damage(perfect_damage)
	_suite.assert_close(float(health.current_hp), perfect_hp_before, "Perfect Guard refunds the engine damage floor and preserves HP")
	var perfect_result: Dictionary = sword.call("last_guard_result_for_test")
	_suite.assert_true(bool(perfect_result.get("perfect", false)), "first active Guard frame is a real perfect block window")
	_suite.assert_close(float(perfect_result.get("blocked_damage", 0.0)), 50.0, "Perfect Guard blocks the full authored hit")
	_suite.assert_close(float((runtime.snapshot().get("resources", {}).get("intent", {}) as Dictionary).get("current", -1.0)), 60.0, "Perfect Guard grants blocked damage plus authored Intent bonus")
	runtime.finish_action(403)
	await _free_player(player)


func _test_launch_resource_exhaustion_is_atomic() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	if not fixture["configured"]:
		await _free_player(fixture["player"])
		return
	for use_index: int in range(10):
		var plan: Dictionary = runtime.plan_intent(_intent(&"weapon_secondary", &"pressed"), {}).get("plan", {})
		_suite.assert_true(bool(runtime.commit_action(plan, 450 + use_index).get("ok", false)), "Guard use %d spends its authored cost" % (use_index + 1))
		runtime.finish_action(450 + use_index)
	var exhausted: Dictionary = runtime.snapshot()
	_suite.assert_close(float((exhausted.get("resources", {}).get("guard", {}) as Dictionary).get("current", -1.0)), 0.0, "ten Guards exhaust the one-hundred-point resource")
	var rejected: Dictionary = runtime.plan_intent(_intent(&"weapon_secondary", &"pressed"), {})
	_suite.assert_equal(rejected.get("code"), &"INSUFFICIENT_RESOURCE", "an eleventh Guard is explicitly rejected")
	_suite.assert_equal(runtime.snapshot(), exhausted, "exhausted Guard rejection is atomic")
	await _free_player(fixture["player"])


func _test_launch_light_chain_progresses_and_wraps() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	if not fixture["configured"]:
		await _free_player(fixture["player"])
		return
	for step: int in range(3):
		var hold_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_primary", &"pressed"), {}).get("plan", {})
		var token := 500 + step
		runtime.commit_action(hold_plan, token)
		var released: Dictionary = runtime.release_hold(hold_plan, token, 0)
		var plan: Dictionary = released.get("finalized_plan", {})
		_suite.assert_equal(plan.get("combo_step_before"), step, "Light Chain plan freezes its current combo step")
		runtime.on_phase_enter(plan, &"ACTIVE", token)
		runtime.on_phase_enter(plan, &"RECOVERY", token)
		runtime.finish_action(token)
		_suite.assert_equal(runtime.snapshot().get("launch_combo_step"), (step + 1) % 3, "Light Chain advances and wraps its combo")
	_suite.assert_equal(runtime.presentation_snapshot().get("combo_step"), 0, "presentation reports wrapped Launch combo")
	var timeout_hold: Dictionary = runtime.plan_intent(_intent(&"weapon_primary", &"pressed"), {}).get("plan", {})
	runtime.commit_action(timeout_hold, 503)
	var timeout_plan: Dictionary = runtime.release_hold(timeout_hold, 503, 0).get("finalized_plan", {})
	runtime.on_phase_enter(timeout_plan, &"ACTIVE", 503)
	runtime.finish_action(503)
	runtime.advance_runtime_frame(47)
	_suite.assert_equal(runtime.snapshot().get("launch_combo_step"), 1, "Launch combo remains live before its timeout")
	runtime.advance_runtime_frame(48)
	_suite.assert_equal(runtime.snapshot().get("launch_combo_step"), 0, "Launch combo resets exactly at the authored timeout")
	await _free_player(fixture["player"])


func _test_launch_zone_and_wave_execute_distinct_payloads() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var sword: Node = fixture["sword"]
	if not fixture["configured"]:
		await _free_player(fixture["player"])
		return
	_suite.assert_true(sword.has_method("launch_payload_snapshots_for_test"), "Sword adapter exposes Launch payload executions")
	var zone_target := _payload_target(Vector2.ZERO, "zone_target")

	var skill_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_skill", &"pressed"), {}).get("plan", {})
	runtime.commit_action(skill_plan, 601)
	var skill_events: Array = runtime.on_phase_enter(skill_plan, &"ACTIVE", 601)
	var skill_payload_event: Dictionary = skill_events[0] if not skill_events.is_empty() else {}
	var skill_descriptors: Array = skill_payload_event.get("payload_descriptors", [])
	_suite.assert_equal(skill_payload_event.get("payload_kind"), "zone", "Temporal Judgment emits a zone event")
	_suite.assert_equal(skill_descriptors.size(), 1, "Temporal Judgment emits one executable descriptor")
	if not skill_descriptors.is_empty():
		var zone_parameters: Dictionary = (skill_descriptors[0] as Dictionary).get("parameters", {})
		_suite.assert_equal(zone_parameters.get("duration_frames"), 90, "Temporal Judgment preserves its duration")
		_suite.assert_close(float(zone_parameters.get("radius_pixels", 0.0)), 192.0, "Temporal Judgment has an explicit three-tile radius")
		_suite.assert_close(float(zone_parameters.get("damage_multiplier", 0.0)), 2.8, "Temporal Judgment preserves damage semantics")
	if sword.has_method("launch_payload_snapshots_for_test"):
		var zone_snapshots: Array = sword.call("launch_payload_snapshots_for_test")
		_suite.assert_true(not zone_snapshots.is_empty(), "Temporal Judgment creates a live payload node")
		if not zone_snapshots.is_empty():
			_suite.assert_equal((zone_snapshots.back() as Dictionary).get("kind"), "zone", "live Temporal Judgment payload is typed zone")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_suite.assert_close(zone_target.received_damage, 84.0, "Temporal Judgment zone applies authoritative profile damage to a live Hurtbox contract")
	_suite.assert_true(zone_target.received_tags.has("payload:zone"), "Temporal Judgment damage carries a zone payload tag")
	var zone_position_before_move: Vector2 = (sword.call("launch_payload_snapshots_for_test") as Array).back().get("position", Vector2.ZERO)
	fixture["player"].position = Vector2(480.0, 160.0)
	fixture["player"].rotation = PI * 0.5
	await get_tree().physics_frame
	var zone_position_after_move: Vector2 = (sword.call("launch_payload_snapshots_for_test") as Array).back().get("position", Vector2.ZERO)
	_suite.assert_equal(zone_position_after_move, zone_position_before_move, "Temporal Judgment remains world-anchored after the player moves and rotates")
	var zone_snapshot: Dictionary = runtime.snapshot()
	runtime.reset_runtime_state(&"zone_restore_probe")
	_suite.assert_true(runtime.restore_snapshot(zone_snapshot), "ACTIVE Launch snapshot restores a persistent zone")
	_suite.assert_equal(runtime.snapshot(), zone_snapshot, "ACTIVE zone restoration is exact")
	var restored_zone_snapshots: Array = sword.call("launch_payload_snapshots_for_test")
	_suite.assert_true(not restored_zone_snapshots.is_empty(), "restored Launch mechanics recreate the live zone")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_suite.assert_close(zone_target.received_damage, 84.0, "restored zone preserves stable target claims and does not damage the same entity twice")
	runtime.finish_action(601)
	fixture["player"].position = Vector2.ZERO
	fixture["player"].rotation = 0.0

	var ultimate_hold: Dictionary = runtime.plan_intent(_intent(&"weapon_ultimate", &"pressed"), {}).get("plan", {})
	var wave_target := _payload_target(Vector2(320.0, 0.0), "wave_target")
	runtime.commit_action(ultimate_hold, 602)
	var ultimate_release: Dictionary = runtime.release_hold(ultimate_hold, 602, 60)
	var ultimate_plan: Dictionary = ultimate_release.get("finalized_plan", {})
	var ultimate_events: Array = runtime.on_phase_enter(ultimate_plan, &"ACTIVE", 602)
	var wave_event: Dictionary = ultimate_events[0] if not ultimate_events.is_empty() else {}
	var wave_descriptors: Array = wave_event.get("payload_descriptors", [])
	_suite.assert_equal(wave_event.get("payload_kind"), "wave", "Primordial Edge emits a wave event")
	if not wave_descriptors.is_empty():
		var wave_parameters: Dictionary = (wave_descriptors[0] as Dictionary).get("parameters", {})
		_suite.assert_close(float(wave_parameters.get("range_pixels", 0.0)), 640.0, "Primordial Edge has an explicit ten-tile range")
		_suite.assert_close(float(wave_parameters.get("damage_multiplier", 0.0)), 9.0, "Primordial Edge preserves damage semantics")
	if sword.has_method("launch_payload_snapshots_for_test"):
		var wave_snapshots: Array = sword.call("launch_payload_snapshots_for_test")
		var found_wave := false
		for payload_snapshot: Dictionary in wave_snapshots:
			found_wave = found_wave or str(payload_snapshot.get("kind", "")) == "wave"
		_suite.assert_true(found_wave, "Primordial Edge creates a distinct live wave payload node")
	runtime.advance_runtime_frame(6)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var moving_wave: Dictionary = {}
	for payload_snapshot: Dictionary in sword.call("launch_payload_snapshots_for_test"):
		if str(payload_snapshot.get("kind", "")) == "wave":
			moving_wave = payload_snapshot
	var wave_position: Vector2 = moving_wave.get("position", Vector2.ZERO)
	_suite.assert_close(wave_position.x, 320.0, "Primordial Edge sweeps halfway across its range at half duration")
	_suite.assert_close(wave_target.received_damage, 270.0, "Primordial Edge moving wave applies authoritative profile damage at its swept position")
	_suite.assert_true(wave_target.received_tags.has("payload:wave"), "Primordial Edge damage carries a wave payload tag")
	var wave_snapshot: Dictionary = runtime.snapshot()
	fixture["player"].position += Vector2(320.0, 240.0)
	fixture["player"].rotation = PI
	await get_tree().physics_frame
	var anchored_wave_position: Vector2 = Vector2.ZERO
	for payload_snapshot: Dictionary in sword.call("launch_payload_snapshots_for_test"):
		if str(payload_snapshot.get("kind", "")) == "wave":
			anchored_wave_position = payload_snapshot.get("position", Vector2.ZERO)
	_suite.assert_equal(anchored_wave_position, wave_position, "Primordial Edge remains world-anchored after player movement")
	runtime.reset_runtime_state(&"wave_restore_probe")
	_suite.assert_true(runtime.restore_snapshot(wave_snapshot), "ACTIVE Primordial Edge snapshot restores")
	_suite.assert_equal(runtime.snapshot(), wave_snapshot, "ACTIVE wave restoration is exact")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_suite.assert_close(wave_target.received_damage, 270.0, "restored wave preserves stable target claims and cannot hit the same entity twice")
	var wave_frame_before_expiry := int(runtime.snapshot().get("last_runtime_frame", 0))
	runtime.advance_runtime_frame(wave_frame_before_expiry + 12)
	var wave_expired := true
	for payload_snapshot: Dictionary in sword.call("launch_payload_snapshots_for_test"):
		wave_expired = wave_expired and str(payload_snapshot.get("kind", "")) != "wave"
	_suite.assert_true(wave_expired, "Primordial Edge wave expires after its authored travel duration")
	runtime.finish_action(602)
	runtime.reset_runtime_state(&"payload_cleanup")
	if sword.has_method("launch_payload_snapshots_for_test"):
		_suite.assert_true((sword.call("launch_payload_snapshots_for_test") as Array).is_empty(), "reset clears owned Launch payloads")
	zone_target.queue_free()
	wave_target.queue_free()
	await _free_player(fixture["player"])


func _test_launch_all_active_phases_restore_exactly() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var sword: Node = fixture["sword"]
	if not fixture["configured"]:
		await _free_player(fixture["player"])
		return

	var ultimate_hold: Dictionary = runtime.plan_intent(_intent(&"weapon_ultimate", &"pressed"), {}).get("plan", {})
	runtime.commit_action(ultimate_hold, 701)
	var hold_snapshot: Dictionary = runtime.snapshot()
	runtime.cancel_action(701, &"hold_restore_probe")
	_suite.assert_true(runtime.restore_snapshot(hold_snapshot), "Primordial Edge HOLD snapshot restores")
	_suite.assert_equal(runtime.snapshot(), hold_snapshot, "HOLD restoration is exact")
	_suite.assert_equal(runtime.presentation_snapshot().get("phase"), "HOLD", "restored HOLD remains releasable")
	runtime.cancel_action(701, &"hold_restore_cleanup")

	var guard_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_secondary", &"pressed"), {}).get("plan", {})
	runtime.commit_action(guard_plan, 702)
	var windup_snapshot: Dictionary = runtime.snapshot()
	runtime.cancel_action(702, &"windup_restore_probe")
	_suite.assert_true(runtime.restore_snapshot(windup_snapshot), "Guard WINDUP snapshot restores")
	_suite.assert_equal(runtime.snapshot(), windup_snapshot, "WINDUP restoration is exact")
	_suite.assert_true(sword.is_attacking(), "restored WINDUP rehydrates the adapter commitment")
	runtime.on_phase_enter(guard_plan, &"ACTIVE", 702)
	runtime.advance_runtime_frame(1)
	var active_snapshot: Dictionary = runtime.snapshot()
	runtime.cancel_action(702, &"active_restore_probe")
	_suite.assert_true(runtime.restore_snapshot(active_snapshot), "Guard ACTIVE snapshot restores")
	_suite.assert_equal(runtime.snapshot(), active_snapshot, "ACTIVE Guard restoration is exact")
	_suite.assert_true(bool((runtime.presentation_snapshot().get("launch_mechanics", {}) as Dictionary).get("guard_active", false)), "restored ACTIVE Guard retains its perfect-window state")
	runtime.on_phase_enter(guard_plan, &"RECOVERY", 702)
	var recovery_snapshot: Dictionary = runtime.snapshot()
	runtime.cancel_action(702, &"recovery_restore_probe")
	_suite.assert_true(runtime.restore_snapshot(recovery_snapshot), "Guard RECOVERY snapshot restores")
	_suite.assert_equal(runtime.snapshot(), recovery_snapshot, "RECOVERY restoration is exact")
	_suite.assert_true(sword.is_attacking(), "restored RECOVERY keeps the adapter committed until finish")
	runtime.finish_action(702)

	var wave_hold: Dictionary = runtime.plan_intent(_intent(&"weapon_ultimate", &"pressed"), {}).get("plan", {})
	runtime.commit_action(wave_hold, 703)
	var wave_plan: Dictionary = runtime.release_hold(wave_hold, 703, 60).get("finalized_plan", {})
	runtime.on_phase_enter(wave_plan, &"ACTIVE", 703)
	var recovery_wave_frame_before_expiry := int(runtime.snapshot().get("last_runtime_frame", 0))
	runtime.advance_runtime_frame(recovery_wave_frame_before_expiry + 12)
	runtime.on_phase_enter(wave_plan, &"RECOVERY", 703)
	var wave_recovery_snapshot: Dictionary = runtime.snapshot()
	_suite.assert_true((sword.call("launch_payload_snapshots_for_test") as Array).is_empty(), "Primordial Edge wave expires before RECOVERY")
	runtime.cancel_action(703, &"wave_recovery_restore_probe")
	_suite.assert_true(runtime.restore_snapshot(wave_recovery_snapshot), "Primordial Edge RECOVERY snapshot without an expired wave restores")
	_suite.assert_equal(runtime.snapshot(), wave_recovery_snapshot, "Primordial Edge RECOVERY restoration is exact")
	runtime.finish_action(703)
	await _free_player(fixture["player"])


func _test_launch_cancel_reset_snapshot_restore_and_presentation() -> void:
	var fixture := await _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var sword: Node = fixture["sword"]
	if not fixture["configured"]:
		await _free_player(fixture["player"])
		return

	var planned: Dictionary = runtime.plan_intent(_intent(&"weapon_skill", &"pressed"), {})
	var plan: Dictionary = planned.get("plan", {})
	var forged_plan := plan.duplicate(true)
	(forged_plan["payloads"] as Array)[0]["parameters"]["damage_multiplier"] = 999.0
	var before_forged_commit: Dictionary = runtime.snapshot()
	_suite.assert_true(not bool(runtime.commit_action(forged_plan, 300).get("ok", false)), "forged Launch payload is rejected")
	_suite.assert_equal(runtime.snapshot(), before_forged_commit, "forged Launch payload rejection is atomic")
	_suite.assert_true(bool(runtime.commit_action(plan, 301).get("ok", false)), "skill commits for cancellation test")
	runtime.on_phase_enter(plan, &"ACTIVE", 301)
	_suite.assert_true(sword.is_attacking(), "Launch adapter is active before cancellation")
	runtime.cancel_action(999, &"stale")
	_suite.assert_true(sword.is_attacking(), "stale cancellation token is ignored")
	runtime.cancel_action(301, &"matching")
	_suite.assert_true(not sword.is_attacking(), "matching cancellation closes the Launch adapter")
	_suite.assert_equal(runtime.presentation_snapshot().get("phase"), "READY", "cancellation returns presentation to READY")

	var original_hold: Dictionary = runtime.plan_intent(_intent(&"weapon_primary", &"pressed"), {}).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(original_hold, 304).get("ok", false)), "primary HOLD commits for identity test")
	var forged_hold := original_hold.duplicate(true)
	(forged_hold["release_action_fingerprints"] as Dictionary)["charged_slash"] = "forged"
	_suite.assert_true(not bool(runtime.release_hold(forged_hold, 304, 30).get("ok", false)), "forged HOLD identity cannot release")
	runtime.cancel_action(304, &"forged_release_cleanup")

	var safe_snapshot: Dictionary = runtime.snapshot()
	_suite.assert_equal(safe_snapshot.get("profile_id"), PROFILE_ID, "safe snapshot retains Launch identity")
	var skill_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_skill", &"pressed"), {}).get("plan", {})
	runtime.commit_action(skill_plan, 302)
	runtime.finish_action(302)
	_suite.assert_true(runtime.restore_snapshot(safe_snapshot), "quiescent Launch snapshot restores")
	_suite.assert_equal(runtime.snapshot().get("profile_id"), PROFILE_ID, "restored runtime remains on Launch profile")

	var hold_plan: Dictionary = runtime.plan_intent(_intent(&"weapon_primary", &"pressed"), {}).get("plan", {})
	runtime.commit_action(hold_plan, 303)
	_suite.assert_equal(runtime.presentation_snapshot().get("action_id"), "sword_primary_charge", "presentation exposes primary charge identity")
	runtime.reset_runtime_state(&"new_run")
	var reset: Dictionary = runtime.snapshot()
	_suite.assert_equal(reset.get("active_token"), 0, "reset clears active token")
	_suite.assert_equal(reset.get("active_phase"), "READY", "reset clears active phase")
	_suite.assert_true(not sword.is_attacking(), "reset clears adapter state")
	await _free_player(fixture["player"])


func _assert_action_lifecycle(runtime: RefCounted, plan: Dictionary, token: int, action_id: String) -> void:
	_suite.assert_equal(runtime.presentation_snapshot().get("action_id"), action_id, "%s presentation exposes action id" % action_id)
	_suite.assert_true(runtime.on_phase_enter(plan, &"WINDUP", token).is_empty(), "%s windup is side-effect free" % action_id)
	var active_events: Array = runtime.on_phase_enter(plan, &"ACTIVE", token)
	_suite.assert_equal(active_events.size(), 2, "%s ACTIVE releases one payload and one cue" % action_id)
	_suite.assert_equal(active_events[0].get("action_id") if not active_events.is_empty() else "", action_id, "%s payload event preserves action identity" % action_id)
	runtime.on_phase_enter(plan, &"RECOVERY", token)
	runtime.finish_action(token)
	_suite.assert_equal(runtime.presentation_snapshot().get("phase"), "READY", "%s finish returns READY" % action_id)


func _fixture() -> Dictionary:
	var player := Node2D.new()
	player.name = "SwordLaunchTestOwner"
	player.add_to_group("player")
	var health = HealthComponentScript.new()
	health.name = "HealthComponent"
	health.max_hp = 200.0
	player.add_child(health)
	var sword = SwordWeaponScript.new()
	sword.name = "SwordWeapon"
	sword.owner_path = NodePath("..")
	var hitbox = HitboxScript.new()
	hitbox.name = "Hitbox"
	sword.add_child(hitbox)
	player.add_child(sword)
	add_child(player)
	await get_tree().process_frame
	var profile = WeaponRuntimeProfileScript.new()
	var definition := _profile_definition()
	var profile_result: Dictionary = profile.configure(definition)
	_suite.assert_true(bool(profile_result.get("ok", false)), "authoritative sword_launch_v1 profile parses")
	var capabilities := PackedStringArray(definition.get("capabilities", []))
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(modifiers.configure(capabilities, CAPABILITY_BOUNDS), "Launch modifier state configures")
	var runtime = SwordWeaponRuntimeScript.new()
	_suite.assert_true(runtime.bind_adapter(sword), "Launch runtime binds the real Sword adapter")
	var configured := runtime.configure(player, profile, modifiers)
	return {
		"player": player,
		"health": health,
		"sword": sword,
		"runtime": runtime,
		"configured": configured,
	}


func _profile_definition() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == PROFILE_ID:
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _intent(semantic: StringName, edge: StringName, held_frames: int = 0) -> Dictionary:
	var result := {"id": str(semantic), "edge": str(edge)}
	if edge == &"released":
		result["held_frames"] = held_frames
	return result


func _phase(plan: Dictionary, index: int) -> Dictionary:
	var phases_value: Variant = plan.get("phases", [])
	if not phases_value is Array or index < 0 or index >= (phases_value as Array).size():
		return {}
	var phase_value: Variant = (phases_value as Array)[index]
	return (phase_value as Dictionary).duplicate(true) if phase_value is Dictionary else {}


func _payload_target(position: Vector2, stable_key: String) -> PayloadTarget:
	var target := PayloadTarget.new()
	target.position = position
	target.set_meta("stable_entity_key", stable_key)
	target.collision_layer = 1
	target.collision_mask = 0
	target.monitorable = true
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	collision.shape = shape
	target.add_child(collision)
	add_child(target)
	return target


func _free_player(player: Node) -> void:
	player.queue_free()
	await get_tree().process_frame
