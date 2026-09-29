extends Node

const BowWeaponRuntimeScript := preload("res://scripts/combat/weapons/bow_weapon_runtime.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponActionCoordinatorScript := preload("res://scripts/combat/weapons/weapon_action_coordinator.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"


class FakeBowAdapter extends Node2D:
	var base_attack: float = 30.0
	var attack_speed: float = 1.0
	var fail_begin: bool = false
	var corrupt_begin: bool = false
	var fail_release: bool = false
	var begin_count: int = 0
	var release_count: int = 0
	var cancel_count: int = 0
	var finish_count: int = 0
	var reset_count: int = 0
	var staged_definition: Dictionary = {}
	var released_definition: Dictionary = {}
	var _active: bool = false
	var _released: bool = false

	func begin_profile_shot(definition: Dictionary) -> Dictionary:
		begin_count += 1
		if fail_begin:
			return {}
		staged_definition = definition.duplicate(true)
		_active = true
		_released = false
		var result := staged_definition.duplicate(true)
		if corrupt_begin:
			result["damage"] = float(result.get("damage", 0.0)) + 1.0
		return result

	func release_profile_shot() -> bool:
		if fail_release or not _active or _released:
			return false
		_released = true
		release_count += 1
		released_definition = staged_definition.duplicate(true)
		return true

	func is_profile_action_active() -> bool:
		return _active

	func cancel_profile_shot() -> void:
		cancel_count += 1
		_clear_action()

	func finish_profile_shot() -> void:
		finish_count += 1
		_clear_action()

	func reset_runtime_state() -> void:
		reset_count += 1
		_clear_action()

	func _clear_action() -> void:
		_active = false
		_released = false
		staged_definition.clear()
		released_definition.clear()


var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_profile_snapshot_capabilities_and_drift_rejection()
	_test_candidate_charge_boundaries_and_payload_curve()
	_test_coordinator_hold_skeleton_finalizes_on_the_same_token()
	_test_real_coordinator_owns_the_complete_hold_transaction()
	_test_authoritative_charge_rate_capability_scales_effective_hold()
	_test_modifier_and_action_plan_are_frozen()
	_test_commit_active_exactly_once_and_reward_deduplication()
	_test_commit_release_cancel_and_reset_fail_atomically()
	_test_quiescent_snapshot_restore_preserves_reward_ledger()
	_suite.finish(get_tree())


func _test_profile_snapshot_capabilities_and_drift_rejection() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var profile: RefCounted = fixture["profile"]
	_suite.assert_equal(
		_sorted_strings(runtime.capabilities()),
		[
			"weapon.attack_speed",
			"weapon.charge_rate",
			"weapon.damage",
			"weapon.full_charge_damage",
			"weapon.pierce",
		],
		"runtime exposes the candidate Bow capability set"
	)

	var exposed: Dictionary = profile.snapshot()
	(exposed["actions"] as Array)[0]["hold_threshold_frames"] = 1
	(exposed["payloads"] as Array)[0]["parameters"]["maximum_speed"] = 999.0
	var isolated: Dictionary = runtime.plan_intent(_release_intent(54), _aim_context(Vector2.RIGHT))
	_suite.assert_true(bool(isolated.get("ok", false)), "runtime retains an isolated candidate profile snapshot")
	_suite.assert_equal(isolated.get("plan", {}).get("hold", {}).get("minimum_frames"), 9, "caller mutation cannot change minimum charge")
	_suite.assert_close(
		float(_payload_parameters(isolated.get("plan", {})).get("speed", 0.0)),
		680.0,
		"caller mutation cannot change candidate maximum speed"
	)

	for drift_case: Dictionary in [
		{"path": "action.recovery_frames", "value": 22},
		{"path": "action.maximum_hold_frames_missing", "value": null},
		{"path": "resource.maximum", "value": 55.0},
		{"path": "payload.maximum_damage_multiplier", "value": 1.8},
		{"path": "cue.audio_id", "value": "bow_release_drift"},
	]:
		var drift := _profile_definition()
		match str(drift_case["path"]):
			"action.recovery_frames":
				(drift["actions"] as Array)[0]["recovery_frames"] = drift_case["value"]
			"action.maximum_hold_frames_missing":
				(drift["actions"] as Array)[0].erase("maximum_hold_frames")
			"resource.maximum":
				(drift["resources"] as Array)[0]["maximum"] = drift_case["value"]
			"payload.maximum_damage_multiplier":
				(drift["payloads"] as Array)[0]["parameters"]["maximum_damage_multiplier"] = drift_case["value"]
			"cue.audio_id":
				(drift["cues"] as Array)[0]["audio_id"] = drift_case["value"]
		var drift_profile = WeaponRuntimeProfileScript.new()
		var parsed: Dictionary = drift_profile.configure(drift)
		_suite.assert_true(bool(parsed.get("ok", false)), "%s drift remains schema-valid" % drift_case["path"])
		var rejected = BowWeaponRuntimeScript.new()
		_suite.assert_true(
			not rejected.configure(fixture["owner"], drift_profile, fixture["modifiers"]),
			"runtime rejects parser-valid %s drift" % drift_case["path"]
		)
	_free_fixture(fixture)


func _test_candidate_charge_boundaries_and_payload_curve() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var before: Dictionary = runtime.snapshot()
	var undercharged: Dictionary = runtime.plan_intent(_release_intent(8), _aim_context(Vector2.RIGHT))
	_suite.assert_true(not bool(undercharged.get("ok", false)), "eight held frames reject below the candidate minimum")
	_suite.assert_equal(undercharged.get("code"), &"UNDERCHARGED", "undercharge rejection is typed")
	_suite.assert_equal(runtime.snapshot(), before, "undercharge rejection has no cooldown or runtime side effect")

	var minimum: Dictionary = runtime.plan_intent(_release_intent(9), _aim_context(Vector2.RIGHT)).get("plan", {})
	_assert_candidate_plan(minimum, 9, 9.0 / 54.0, false)
	_suite.assert_close(float(_payload_parameters(minimum).get("damage_multiplier", 0.0)), 0.75 + 9.0 / 54.0, "minimum shot interpolates candidate damage")
	_suite.assert_close(float(_payload_parameters(minimum).get("speed", 0.0)), 440.0 + 240.0 * 9.0 / 54.0, "minimum shot interpolates candidate speed")

	var below_full: Dictionary = runtime.plan_intent(_release_intent(52), _aim_context(Vector2.RIGHT)).get("plan", {})
	_assert_candidate_plan(below_full, 52, 52.0 / 54.0, false)
	_suite.assert_equal(_payload_parameters(below_full).get("pierce"), 0, "fifty-two frames remain below full-charge pierce")
	_suite.assert_close(float(_payload_parameters(below_full).get("time_energy_restore", -1.0)), 0.0, "non-full shot grants no energy")

	var threshold: Dictionary = runtime.plan_intent(_release_intent(53), _aim_context(Vector2.RIGHT)).get("plan", {})
	_assert_candidate_plan(threshold, 53, 53.0 / 54.0, true)
	_suite.assert_equal(_payload_parameters(threshold).get("pierce"), 1, "0.98 threshold grants one candidate pierce")
	_suite.assert_close(float(_payload_parameters(threshold).get("time_energy_restore", 0.0)), 6.0, "0.98 threshold offers six energy once")

	var maximum: Dictionary = runtime.plan_intent(_release_intent(54), _aim_context(Vector2.RIGHT)).get("plan", {})
	_assert_candidate_plan(maximum, 54, 1.0, true)
	_suite.assert_close(float(_payload_parameters(maximum).get("damage_multiplier", 0.0)), 1.75, "full charge reaches exact maximum damage")
	_suite.assert_close(float(_payload_parameters(maximum).get("speed", 0.0)), 680.0, "full charge reaches exact maximum speed")
	_suite.assert_equal(_phase(maximum, 2).get("duration_frames"), 21, "candidate cooldown remains twenty-one recovery frames")

	var clamped: Dictionary = runtime.plan_intent(_release_intent(90), _aim_context(Vector2.RIGHT)).get("plan", {})
	_assert_candidate_plan(clamped, 90, 1.0, true)
	_suite.assert_equal(clamped.get("hold", {}).get("effective_frames"), 54, "charge clamps at the fifty-four frame maximum")
	_free_fixture(fixture)


func _test_coordinator_hold_skeleton_finalizes_on_the_same_token() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var bow: FakeBowAdapter = fixture["bow"]
	var pressed: Dictionary = runtime.plan_intent(_press_intent(), _aim_context(Vector2(3.0, 4.0)))
	_suite.assert_true(bool(pressed.get("ok", false)), "primary press plans a coordinator-owned HOLD skeleton")
	var skeleton: Dictionary = pressed.get("plan", {})
	_suite.assert_equal(_phase(skeleton, 0).get("phase"), "HOLD", "candidate charge begins with HOLD")
	_suite.assert_equal(_phase(skeleton, 0).get("duration_frames"), 54, "HOLD owns the fifty-four frame maximum")
	_suite.assert_equal(_phase(skeleton, 0).get("minimum_hold_frames"), 9, "HOLD owns the nine frame minimum")
	_suite.assert_equal(_phase(skeleton, 0).get("charge_complete_frames"), 54, "candidate baseline completes charge at fifty-four effective frames")
	_suite.assert_close(float(_phase(skeleton, 0).get("hold_progress_multiplier", -1.0)), 1.0, "candidate baseline advances HOLD at one effective frame per raw frame")
	_suite.assert_equal(_phase(skeleton, 1).get("phase"), "WINDUP", "HOLD skeleton declares its release path")
	_suite.assert_true(bool(runtime.commit_action(skeleton, 201).get("ok", false)), "HOLD skeleton commits")
	_suite.assert_equal(runtime.snapshot().get("active_phase"), "HOLD", "runtime tracks the committed HOLD under the action token")
	_suite.assert_equal(bow.begin_count, 0, "press commit does not construct or stage an arrow")
	_suite.assert_true(runtime.on_phase_enter(skeleton, &"HOLD", 201).is_empty(), "HOLD entry releases no payload or cue")

	var hold_snapshot: Dictionary = runtime.snapshot()
	var undercharged: Dictionary = runtime.release_hold(skeleton, 201, 8)
	_suite.assert_true(not bool(undercharged.get("ok", false)), "runtime independently rejects an under-minimum release")
	_suite.assert_equal(undercharged.get("code"), &"UNDERCHARGED", "runtime undercharge failure is typed")
	_suite.assert_equal(runtime.snapshot(), hold_snapshot, "undercharged release leaves the HOLD transaction restorable")
	_suite.assert_equal(bow.begin_count, 0, "undercharged release never stages a projectile")
	runtime.cancel_action(201, &"rollback_fixture")
	_suite.assert_true(runtime.restore_snapshot(hold_snapshot), "active HOLD snapshot restores for atomic release rollback")
	bow.base_attack = 300.0
	_suite.assert_true(runtime.apply_modifier(&"weapon.damage", 2.0), "live damage changes after HOLD commit")

	var released: Dictionary = runtime.release_hold(skeleton, 201, 54)
	_suite.assert_true(bool(released.get("ok", false)), "valid HOLD release finalizes the same action token")
	var finalized: Dictionary = released.get("finalized_plan", {})
	for identity_field: String in ["weapon_id", "action_id", "profile_id", "profile_version"]:
		_suite.assert_equal(finalized.get(identity_field), skeleton.get(identity_field), "finalized HOLD preserves %s" % identity_field)
	_suite.assert_equal(_phase(finalized, 0).get("phase"), "WINDUP", "finalized plan removes HOLD and begins windup")
	_suite.assert_true(not _phase_names(finalized).has("HOLD"), "finalized plan contains no second charge clock")
	_suite.assert_equal(finalized.get("hold", {}).get("raw_frames"), 54, "finalized plan records coordinator-held frames")
	_suite.assert_equal(_payload_parameters(finalized).get("direction"), Vector2(0.6, 0.8), "release uses the aim snapshot frozen at press")
	_suite.assert_close(float(_payload_parameters(finalized).get("damage", 0.0)), 30.0 * 1.75, "release uses attack and modifier state frozen at press")
	_suite.assert_equal(runtime.snapshot().get("active_token"), 201, "release preserves the committed token")
	_suite.assert_equal(runtime.snapshot().get("active_phase"), "WINDUP", "release advances runtime to finalized windup")
	_suite.assert_equal(bow.begin_count, 1, "release stages exactly one immutable arrow")

	var stale_release: Dictionary = runtime.release_hold(skeleton, 201, 54)
	_suite.assert_true(not bool(stale_release.get("ok", false)), "duplicate release cannot finalize the token twice")
	_suite.assert_equal(bow.begin_count, 1, "duplicate release cannot construct another arrow")
	_suite.assert_true(runtime.on_phase_enter(finalized, &"WINDUP", 201).is_empty(), "finalized windup releases no payload")
	_suite.assert_equal(runtime.on_phase_enter(finalized, &"ACTIVE", 201).size(), 2, "finalized ACTIVE releases payload and cue once")
	_suite.assert_equal(bow.release_count, 1, "same-token HOLD path releases one projectile")
	runtime.on_phase_enter(finalized, &"RECOVERY", 201)
	runtime.finish_action(201)
	_free_fixture(fixture)


func _test_real_coordinator_owns_the_complete_hold_transaction() -> void:
	var fixture := _fixture()
	var bow: FakeBowAdapter = fixture["bow"]
	var coordinator = WeaponActionCoordinatorScript.new()
	_suite.assert_true(coordinator.configure(fixture["runtime"]), "real coordinator accepts the Bow runtime contract")
	var committed_count := [0]
	coordinator.weapon_action_committed.connect(func(
		_weapon_id: StringName,
		_action_id: StringName,
		_token: int,
		_context: Dictionary
	) -> void:
		committed_count[0] += 1
	)
	var pressed: Dictionary = coordinator.submit_intent(
		_press_intent(),
		_aim_context(Vector2.RIGHT)
	)
	_suite.assert_true(bool(pressed.get("ok", false)), "real coordinator commits candidate Bow press")
	var token := int(pressed.get("token", 0))
	var generation := int(pressed.get("generation", 0))
	_suite.assert_equal(coordinator.phase_name(), &"HOLD", "real coordinator owns Bow HOLD timing")
	_suite.assert_equal(committed_count[0], 0, "Bow HOLD publishes no commit before a valid release")
	for _frame: int in range(9):
		coordinator.advance_frame()
	var released: Dictionary = coordinator.submit_intent(_release_intent(9), {})
	_suite.assert_true(bool(released.get("ok", false)), "real coordinator releases Bow at the minimum boundary")
	_suite.assert_equal(released.get("token"), token, "real coordinator preserves the Bow action token across release")
	_suite.assert_equal(released.get("generation"), generation, "real coordinator preserves the Bow generation across release")
	_suite.assert_equal(coordinator.phase_name(), &"WINDUP", "real coordinator adopts Bow finalized windup")
	_suite.assert_equal(committed_count[0], 1, "Bow release publishes exactly one action commit")
	_suite.assert_equal(bow.begin_count, 1, "real coordinator stages one arrow on release")
	coordinator.advance_frame()
	_suite.assert_equal(coordinator.phase_name(), &"ACTIVE", "one windup frame reaches Bow ACTIVE")
	_suite.assert_equal(bow.release_count, 1, "real coordinator ACTIVE releases one arrow")
	coordinator.cancel(&"test_cleanup")
	_free_fixture(fixture)


func _test_authoritative_charge_rate_capability_scales_effective_hold() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var bow: FakeBowAdapter = fixture["bow"]
	var modifiers: RefCounted = fixture["modifiers"]
	_suite.assert_true(
		modifiers.apply_additive(&"weapon.charge_rate", 0.5, 1.0),
		"Bow item bonus reaches the authoritative charge-rate capability"
	)
	var accelerated: Dictionary = runtime.plan_intent(
		_release_intent(36),
		_aim_context(Vector2.RIGHT)
	).get("plan", {})
	_suite.assert_equal(
		accelerated.get("hold", {}).get("effective_frames"),
		54.0,
		"a 1.5 charge-rate modifier converts thirty-six raw frames into full charge"
	)
	_suite.assert_true(
		bool(_payload_parameters(accelerated).get("full_charge", false)),
		"charge-rate capability can reach the frozen full-charge threshold"
	)

	var pressed_plan: Dictionary = runtime.plan_intent(
		_press_intent(),
		_aim_context(Vector2.RIGHT)
	).get("plan", {})
	var hold_phase := _phase(pressed_plan, 0)
	_suite.assert_equal(
		hold_phase.get("charge_complete_frames"),
		54,
		"Bow skeleton keeps the candidate fifty-four effective-frame charge scale"
	)
	_suite.assert_close(
		float(hold_phase.get("hold_progress_multiplier", -1.0)),
		1.5,
		"Bow skeleton exports the frozen charge-rate multiplier to the coordinator"
	)

	var coordinator = WeaponActionCoordinatorScript.new()
	_suite.assert_true(coordinator.configure(runtime), "coordinator accepts the accelerated Bow runtime")
	_suite.assert_true(
		bool(coordinator.submit_intent(_press_intent(), _aim_context(Vector2.RIGHT)).get("ok", false)),
		"accelerated Bow begins one coordinator-owned HOLD"
	)
	for _frame: int in range(35):
		coordinator.advance_frame()
	var before_full: Dictionary = coordinator.presentation_snapshot()
	_suite.assert_close(
		float(before_full.get("charge_ratio", -1.0)),
		52.5 / 54.0,
		"thirty-five raw frames remain below full charge at 1.5x"
	)
	coordinator.advance_frame()
	var full: Dictionary = coordinator.presentation_snapshot()
	_suite.assert_close(
		float(full.get("effective_hold_frames", -1.0)),
		54.0,
		"thirty-six raw frames reach fifty-four effective charge frames at 1.5x"
	)
	_suite.assert_close(
		float(full.get("charge_ratio", -1.0)),
		1.0,
		"coordinator HUD ratio reaches full charge after thirty-six raw frames"
	)
	_suite.assert_close(
		float(full.get("movement_multiplier", -1.0)),
		float(hold_phase.get("movement_multiplier", -2.0)),
		"full-charge HOLD applies the Bow phase's completed movement multiplier"
	)
	_suite.assert_true(
		bool(coordinator.submit_intent(_release_intent(36), {}).get("ok", false)),
		"accelerated Bow releases at the thirty-six-frame full-charge boundary"
	)
	_suite.assert_close(
		float(bow.staged_definition.get("damage", 0.0)),
		30.0 * 1.75,
		"accelerated coordinator release stages full-charge candidate damage"
	)
	coordinator.cancel(&"test_cleanup")
	_free_fixture(fixture)


func _test_modifier_and_action_plan_are_frozen() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var bow: FakeBowAdapter = fixture["bow"]
	var modifiers: RefCounted = fixture["modifiers"]
	_suite.assert_true(runtime.apply_modifier(&"weapon.damage", 1.5), "declared damage modifier applies")
	_suite.assert_true(runtime.apply_modifier(&"weapon.full_charge_damage", 1.35), "declared full-charge modifier applies")
	_suite.assert_true(runtime.apply_modifier(&"weapon.pierce", 3.0), "declared pierce modifier applies")
	_suite.assert_true(not runtime.apply_modifier(&"weapon.ammo_capacity", 2.0), "undeclared modifier fails closed")

	var plan: Dictionary = runtime.plan_intent(_release_intent(54), _aim_context(Vector2(3.0, 4.0))).get("plan", {})
	var frozen_parameters := _payload_parameters(plan)
	_suite.assert_close(float(frozen_parameters.get("damage", 0.0)), 30.0 * 1.75 * 1.35 * 1.5, "plan freezes base attack, full-charge reward, and generic damage")
	_suite.assert_equal(frozen_parameters.get("pierce"), 4, "plan combines full-charge and authoritative generic pierce")
	_suite.assert_equal(frozen_parameters.get("direction"), Vector2(0.6, 0.8), "plan freezes normalized aim direction")

	bow.base_attack = 300.0
	_suite.assert_true(runtime.apply_modifier(&"weapon.damage", 2.0), "live modifier changes after plan freeze")
	_suite.assert_true(runtime.apply_modifier(&"weapon.full_charge_damage", 4.0), "live full-charge modifier changes after plan freeze")
	_suite.assert_true(runtime.apply_modifier(&"weapon.pierce", 10.0), "live pierce modifier changes after plan freeze")
	_suite.assert_true(bool(runtime.commit_action(plan, 301).get("ok", false)), "frozen candidate plan commits")
	_suite.assert_close(float(bow.staged_definition.get("damage", 0.0)), 30.0 * 1.75 * 1.35 * 1.5, "adapter receives frozen damage rather than live mutable fields")
	_suite.assert_equal(bow.staged_definition.get("pierce"), 4, "adapter receives frozen pierce")
	_suite.assert_equal(bow.staged_definition.get("token"), 301, "adapter payload receives the committed action token")
	_suite.assert_true(bool(bow.staged_definition.get("energy_reward_once_per_action", false)), "adapter payload carries the once-per-token reward policy")
	runtime.cancel_action(301, &"test_cleanup")
	_free_fixture(fixture)


func _test_commit_active_exactly_once_and_reward_deduplication() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var bow: FakeBowAdapter = fixture["bow"]
	var plan: Dictionary = runtime.plan_intent(_release_intent(54), _aim_context(Vector2.RIGHT)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(plan, 401).get("ok", false)), "full-charge shot commits")
	_suite.assert_true(runtime.on_phase_enter(plan, &"WINDUP", 401).is_empty(), "windup releases no payload")
	var active_events: Array = runtime.on_phase_enter(plan, &"ACTIVE", 401)
	_suite.assert_equal(active_events.size(), 2, "first ACTIVE entry releases one payload and one cue")
	_suite.assert_equal(bow.release_count, 1, "adapter releases exactly one staged projectile")
	_suite.assert_true(runtime.on_phase_enter(plan, &"ACTIVE", 401).is_empty(), "duplicate ACTIVE entry is ignored")
	_suite.assert_equal(bow.release_count, 1, "duplicate ACTIVE cannot release a second projectile")
	_suite.assert_true(runtime.on_phase_enter(plan, &"ACTIVE", 999).is_empty(), "stale token cannot release a projectile")

	var reward: Dictionary = runtime.claim_action_reward(401, &"full_charge_energy")
	_suite.assert_true(bool(reward.get("ok", false)), "first full-charge hit claims the action reward")
	_suite.assert_close(float(reward.get("amount", 0.0)), 6.0, "claimed action reward is six energy")
	var duplicate: Dictionary = runtime.claim_action_reward(401, &"full_charge_energy")
	_suite.assert_true(not bool(duplicate.get("ok", false)), "second target cannot claim energy for the same action token")
	_suite.assert_equal(duplicate.get("code"), &"REWARD_ALREADY_CLAIMED", "duplicate target rejection is explicit")
	_suite.assert_true(not bool(runtime.claim_action_reward(402, &"full_charge_energy").get("ok", false)), "unknown token cannot claim a reward")
	_suite.assert_true(not bool(runtime.claim_action_reward(401, &"unknown_reward").get("ok", false)), "unknown reward kind fails closed")

	runtime.on_phase_enter(plan, &"RECOVERY", 401)
	runtime.finish_action(401)
	_suite.assert_true(not bow.is_profile_action_active(), "finish clears staged adapter authority")
	_free_fixture(fixture)


func _test_commit_release_cancel_and_reset_fail_atomically() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var bow: FakeBowAdapter = fixture["bow"]
	var plan: Dictionary = runtime.plan_intent(_release_intent(54), _aim_context(Vector2.RIGHT)).get("plan", {})
	var baseline: Dictionary = runtime.snapshot()
	_suite.assert_true(not bool(runtime.commit_action(plan, 0).get("ok", false)), "non-positive token is rejected")
	_suite.assert_equal(runtime.snapshot(), baseline, "invalid token leaves runtime unchanged")

	var forged := plan.duplicate(true)
	(forged["payloads"] as Array)[0]["parameters"]["speed"] = 999.0
	_suite.assert_true(not bool(runtime.commit_action(forged, 501).get("ok", false)), "forged payload is rejected")
	_suite.assert_equal(runtime.snapshot(), baseline, "forged plan rejection is atomic")

	bow.fail_begin = true
	_suite.assert_true(not bool(runtime.commit_action(plan, 502).get("ok", false)), "payload construction failure rejects commit")
	_suite.assert_equal(runtime.snapshot(), baseline, "construction failure rolls back runtime state")
	_suite.assert_true(not bow.is_profile_action_active(), "construction failure leaves adapter idle")
	bow.fail_begin = false
	bow.corrupt_begin = true
	_suite.assert_true(not bool(runtime.commit_action(plan, 503).get("ok", false)), "adapter payload mismatch rejects commit")
	_suite.assert_equal(runtime.snapshot(), baseline, "adapter mismatch rolls back runtime state")
	_suite.assert_true(not bow.is_profile_action_active(), "adapter mismatch cancels staged payload")
	bow.corrupt_begin = false

	_suite.assert_true(bool(runtime.commit_action(plan, 504).get("ok", false)), "valid shot commits after atomic failures")
	runtime.cancel_action(999, &"stale")
	_suite.assert_true(bow.is_profile_action_active(), "stale token cannot cancel staged payload")
	runtime.cancel_action(504, &"dash")
	_suite.assert_true(not bow.is_profile_action_active(), "matching Dash cancellation clears staged payload")
	_suite.assert_equal(runtime.snapshot().get("active_token"), 0, "matching cancellation clears runtime token")

	bow.fail_release = true
	_suite.assert_true(bool(runtime.commit_action(plan, 505).get("ok", false)), "release-failure fixture commits staged payload")
	var failed_events: Array = runtime.on_phase_enter(plan, &"ACTIVE", 505)
	_suite.assert_equal(failed_events, [{"type": "phase_failed", "reason": "payload_activation_failed"}], "ACTIVE failure requests coordinator cancellation")
	runtime.cancel_action(505, &"payload_activation_failed")
	bow.fail_release = false
	runtime.reset_runtime_state(&"new_run")
	_suite.assert_equal(runtime.snapshot().get("active_token"), 0, "reset clears active token")
	_suite.assert_equal(runtime.snapshot().get("reward_eligible_tokens"), [], "reset clears reward eligibility ledger")
	_suite.assert_equal(runtime.snapshot().get("reward_claimed_tokens"), [], "reset clears claimed reward ledger")
	_suite.assert_true(bow.reset_count > 0, "reset delegates adapter cleanup")
	_free_fixture(fixture)


func _test_quiescent_snapshot_restore_preserves_reward_ledger() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var bow: FakeBowAdapter = fixture["bow"]
	var plan: Dictionary = runtime.plan_intent(_release_intent(54), _aim_context(Vector2.RIGHT)).get("plan", {})
	runtime.commit_action(plan, 601)
	runtime.on_phase_enter(plan, &"ACTIVE", 601)
	var unsafe: Dictionary = runtime.snapshot()
	_suite.assert_true(not runtime.restore_snapshot(unsafe), "restore rejects an active projectile transaction")
	runtime.on_phase_enter(plan, &"RECOVERY", 601)
	runtime.finish_action(601)
	var safe: Dictionary = runtime.snapshot()
	(safe["reward_eligible_tokens"] as Array).append(999)
	_suite.assert_equal(runtime.snapshot().get("reward_eligible_tokens"), [601], "returned snapshots are isolated")
	safe = runtime.snapshot()
	_suite.assert_true(bool(runtime.claim_action_reward(601, &"full_charge_energy").get("ok", false)), "reward can be claimed before restore")
	_suite.assert_equal(runtime.snapshot().get("reward_claimed_tokens"), [601], "claim ledger records the token")
	_suite.assert_true(runtime.restore_snapshot(safe), "quiescent snapshot restores")
	_suite.assert_equal(runtime.snapshot().get("reward_claimed_tokens"), [], "restore rolls claim ledger back to captured state")
	_suite.assert_true(bool(runtime.claim_action_reward(601, &"full_charge_energy").get("ok", false)), "restored eligibility can be claimed exactly once again")

	var malformed := safe.duplicate(true)
	malformed["reward_claimed_tokens"] = [999]
	var before_rejection: Dictionary = runtime.snapshot()
	_suite.assert_true(not runtime.restore_snapshot(malformed), "restore rejects claims without matching eligibility")
	_suite.assert_equal(runtime.snapshot(), before_rejection, "malformed restore rejection is atomic")
	_suite.assert_true(not bow.is_profile_action_active(), "snapshot restore leaves adapter quiescent")
	_free_fixture(fixture)


func _fixture() -> Dictionary:
	var owner := Node.new()
	owner.name = "BowRuntimeOwner"
	var bow := FakeBowAdapter.new()
	bow.name = "BowWeapon"
	owner.add_child(bow)
	var profile = WeaponRuntimeProfileScript.new()
	var profile_result: Dictionary = profile.configure(_profile_definition())
	_suite.assert_true(bool(profile_result.get("ok", false)), "authoritative bow_candidate_v1 profile configures")
	var modifiers = WeaponModifierStateScript.new()
	_suite.assert_true(
		modifiers.configure(
			PackedStringArray([
				"weapon.attack_speed",
				"weapon.charge_rate",
				"weapon.damage",
				"weapon.full_charge_damage",
				"weapon.pierce",
			]),
			{
				"weapon.attack_speed": {"minimum": 0.2, "maximum": 5.0},
				"weapon.charge_rate": {"minimum": 0.0, "maximum": 5.0},
				"weapon.damage": {"minimum": 0.0, "maximum": 10.0},
				"weapon.full_charge_damage": {"minimum": 0.0, "maximum": 11.0},
				"weapon.pierce": {"minimum": 0.0, "maximum": 20.0},
			}
		),
		"Bow modifier state configures from profile capabilities"
	)
	var runtime = BowWeaponRuntimeScript.new()
	_suite.assert_true(runtime.configure(owner, profile, modifiers), "Bow runtime configures with the profile adapter contract")
	return {
		"owner": owner,
		"bow": bow,
		"profile": profile,
		"modifiers": modifiers,
		"runtime": runtime,
	}


func _profile_definition() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_CATALOG_PATH))
	if not parsed is Array:
		return {}
	for definition_value: Variant in parsed as Array:
		if definition_value is Dictionary and str((definition_value as Dictionary).get("id", "")) == "bow_candidate_v1":
			return (definition_value as Dictionary).duplicate(true)
	return {}


func _release_intent(held_frames: int) -> Dictionary:
	return {
		"id": &"weapon_primary",
		"edge": &"released",
		"held_frames": held_frames,
	}


func _press_intent() -> Dictionary:
	return {
		"id": &"weapon_primary",
		"edge": &"pressed",
		"held_frames": 0,
	}


func _aim_context(direction: Vector2) -> Dictionary:
	return {"aim_direction": direction}


func _assert_candidate_plan(plan: Dictionary, raw_frames: int, ratio: float, full_charge: bool) -> void:
	_suite.assert_equal(plan.get("action_id"), "candidate_draw", "%d-frame shot uses candidate action" % raw_frames)
	_suite.assert_equal(plan.get("activation_mode"), "release", "%d-frame shot remains release activated" % raw_frames)
	_suite.assert_equal(plan.get("cooldown_frames"), 21, "%d-frame shot freezes candidate cooldown" % raw_frames)
	_suite.assert_equal(plan.get("hold", {}).get("raw_frames"), raw_frames, "%d-frame shot records raw held frames" % raw_frames)
	_suite.assert_close(float(plan.get("hold", {}).get("charge_ratio", -1.0)), ratio, "%d-frame shot records charge ratio" % raw_frames)
	_suite.assert_equal(_phase(plan, 0).get("duration_frames"), 1, "%d-frame shot keeps one windup frame" % raw_frames)
	_suite.assert_equal(_phase(plan, 1).get("duration_frames"), 1, "%d-frame shot keeps one active frame" % raw_frames)
	_suite.assert_equal(_payload_parameters(plan).get("full_charge"), full_charge, "%d-frame shot classifies full charge" % raw_frames)
	_suite.assert_equal(_payload_parameters(plan).get("energy_reward_once_per_action"), true, "%d-frame shot freezes reward deduplication policy" % raw_frames)


func _payload_parameters(plan: Dictionary) -> Dictionary:
	var payloads_value: Variant = plan.get("payloads", [])
	if not payloads_value is Array or (payloads_value as Array).is_empty():
		return {}
	var payload_value: Variant = (payloads_value as Array)[0]
	if not payload_value is Dictionary or not (payload_value as Dictionary).get("parameters") is Dictionary:
		return {}
	return ((payload_value as Dictionary)["parameters"] as Dictionary).duplicate(true)


func _phase(plan: Dictionary, index: int) -> Dictionary:
	var phases_value: Variant = plan.get("phases", [])
	if not phases_value is Array or index < 0 or index >= (phases_value as Array).size():
		return {}
	var phase_value: Variant = (phases_value as Array)[index]
	return (phase_value as Dictionary).duplicate(true) if phase_value is Dictionary else {}


func _phase_names(plan: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for phase_value: Variant in plan.get("phases", []):
		if phase_value is Dictionary:
			result.append(str((phase_value as Dictionary).get("phase", "")))
	return result


func _sorted_strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result


func _free_fixture(fixture: Dictionary) -> void:
	var owner: Node = fixture["owner"]
	owner.free()
