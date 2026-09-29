extends Node

const StaffWeaponRuntimeScript := preload("res://scripts/combat/weapons/staff_weapon_runtime.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponActionCoordinatorScript := preload("res://scripts/combat/weapons/weapon_action_coordinator.gd")
const WeaponModifierStateScript := preload("res://scripts/combat/weapons/weapon_modifier_state.gd")
const WeaponResourceTransactionScript := preload("res://scripts/combat/weapons/weapon_resource_transaction.gd")
const WeaponRuntimeProfileScript := preload("res://scripts/combat/weapons/weapon_runtime_profile.gd")

const PROFILE_CATALOG_PATH := "res://data/content_packs/base/content/weapon_runtime_profiles.json"
const ELEMENT_COSTS := {
	"fire": 20.0,
	"ice": 25.0,
	"lightning": 18.0,
}
const ORDERED_COMBOS: Array[Dictionary] = [
	{"first": "fire", "second": "ice", "combo_id": "steam_burst", "extra": 15.0},
	{"first": "fire", "second": "lightning", "combo_id": "blazing_storm", "extra": 20.0},
	{"first": "ice", "second": "lightning", "combo_id": "crystal_thunder", "extra": 18.0},
	{"first": "ice", "second": "fire", "combo_id": "reverse_steam", "extra": 15.0},
	{"first": "lightning", "second": "fire", "combo_id": "thunder_flare", "extra": 20.0},
	{"first": "lightning", "second": "ice", "combo_id": "thunder_crystal", "extra": 18.0},
]


class FakeStaffAdapter extends Node2D:
	var base_attack: float = 9.0
	var attack_speed: float = 0.85
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


	func _clear_action() -> void:
		_active = false
		_released = false
		staged_definition.clear()
		released_definition.clear()


class FakeTimeEnergyProvider extends RefCounted:
	var current: float = 100.0
	var revision: int = 1


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
	_test_authoritative_profile_is_frozen()
	_test_primary_charge_and_element_costs()
	_test_mana_regeneration_and_bounded_damage_return()
	_test_payload_target_deduplication_is_per_outcome()
	_test_six_ordered_combinations_and_atomic_refund()
	_test_near_expiry_combo_projectile_does_not_extend_window()
	_test_overlapping_combo_reservations_are_token_owned()
	_test_lightning_first_combo_preserves_origin_material()
	_test_same_element_timeout_and_insufficient_total_reject()
	_test_four_time_context_plans()
	_test_rewind_claims_are_bounded_and_restore_safe()
	_test_skill_ultimate_and_boss_descriptors()
	_test_coordinator_hold_snapshot_and_reset_boundaries()
	_test_cast_ledgers_are_bounded()
	_suite.finish(get_tree())


func _test_authoritative_profile_is_frozen() -> void:
	var fixture := _fixture()
	_suite.assert_true(bool(fixture.get("configured", false)), "authoritative staff_launch_v1 configures")
	var runtime: RefCounted = fixture["runtime"]
	_suite.assert_equal(
		_sorted_strings(runtime.capabilities()),
		[
			"weapon.attack_speed",
			"weapon.charge_rate",
			"weapon.damage",
			"weapon.mana_max",
			"weapon.status_duration",
		],
		"Staff exposes only the frozen capability set"
	)
	for drift_case: Dictionary in [
		{"label": "charge threshold", "section": "actions", "id": "charged_element", "field": "hold_threshold_frames", "value": 29},
		{"label": "Mana regeneration", "section": "resources", "id": "mana", "field": "regen_per_second", "value": 2.0},
		{"label": "Fire Mana cost", "section": "payload_cost", "id": "staff_element_cast", "field": "fire", "value": 19.0},
		{"label": "Stop area multiplier", "section": "time_stop", "id": "stop", "field": "area_multiplier", "value": 1.4},
	]:
		var drift := _catalog_profile("staff_launch_v1")
		match str(drift_case["section"]):
			"actions":
				_dictionary_ref_by_id(drift["actions"], "action_id", drift_case["id"])[drift_case["field"]] = drift_case["value"]
			"resources":
				_dictionary_ref_by_id(drift["resources"], "resource_id", drift_case["id"])[drift_case["field"]] = drift_case["value"]
			"payload_cost":
				var payload := _dictionary_ref_by_id(drift["payloads"], "payload_id", drift_case["id"])
				((payload["parameters"] as Dictionary)["costs"] as Dictionary)[drift_case["field"]] = drift_case["value"]
			"time_stop":
				(((drift["time_interactions"] as Dictionary)["stop"] as Dictionary)["parameters"] as Dictionary)[drift_case["field"]] = drift_case["value"]
		_assert_profile_rejected(fixture["owner"], fixture["modifiers"], drift, drift_case["label"])
	_free_fixture(fixture)


func _test_primary_charge_and_element_costs() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var adapter: FakeStaffAdapter = fixture["adapter"]
	var hold: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), _context(9101)).get("plan", {})
	_suite.assert_equal(_phase(hold, 0).get("phase"), "HOLD", "Staff primary uses coordinator HOLD")
	_suite.assert_equal(_phase(hold, 0).get("charge_complete_frames"), 30, "Staff charged spell completes at frame thirty")
	_suite.assert_equal(_phase(hold, 0).get("minimum_hold_frames"), 0, "Staff primary may release immediately")
	var tap: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 29), _context(9102)).get("plan", {})
	_suite.assert_equal(tap.get("action_id"), "arcane_bolt", "frame twenty-nine remains the free basic spell")
	_suite.assert_close(float(tap.get("mana_cost", -1.0)), 0.0, "Arcane Bolt costs no Mana")
	var charged: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9103)).get("plan", {})
	_suite.assert_equal(charged.get("action_id"), "charged_element", "frame thirty resolves the charged element spell")
	_suite.assert_equal(charged.get("element"), "fire", "Staff starts on Fire")
	_suite.assert_close(float(charged.get("mana_cost", 0.0)), 20.0, "Fire costs twenty Mana")
	_suite.assert_close(float(_payload_parameters(charged).get("resolved_damage_multiplier", 0.0)), 4.0, "Fire uses its authoritative element damage")
	_suite.assert_true(bool(runtime.commit_action(charged, 11).get("ok", false)), "Fire charged spell commits")
	_suite.assert_close(float(runtime.snapshot().get("mana", 0.0)), 80.0, "Fire commit spends twenty Mana atomically")
	_suite.assert_equal(adapter.staged_definition.get("action_id"), "charged_element", "adapter stages the coordinator definition")
	_suite.assert_equal(_first_descriptor_parameters(adapter.staged_definition).get("element"), "fire", "staged Fire payload freezes element identity")
	runtime.cancel_action(11, &"fire_verified")

	_suite.assert_true(_cycle_element(runtime, 12), "utility cycles Fire to Ice")
	charged = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9104)).get("plan", {})
	_suite.assert_equal(charged.get("element"), "ice", "Ice becomes the current element")
	_suite.assert_close(float(charged.get("mana_cost", 0.0)), 25.0, "Ice costs twenty-five Mana")
	_suite.assert_close(float(_payload_parameters(charged).get("resolved_damage_multiplier", 0.0)), 2.5, "Ice uses its authoritative element damage")
	_suite.assert_true(bool(runtime.commit_action(charged, 13).get("ok", false)), "Ice charged spell commits")
	runtime.cancel_action(13, &"ice_verified")

	_suite.assert_true(_cycle_element(runtime, 14), "utility cycles Ice to Lightning")
	charged = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9105)).get("plan", {})
	_suite.assert_equal(charged.get("element"), "lightning", "Lightning becomes the current element")
	_suite.assert_close(float(charged.get("mana_cost", 0.0)), 18.0, "Lightning costs eighteen Mana")
	_suite.assert_close(float(_payload_parameters(charged).get("resolved_damage_multiplier", 0.0)), 3.0, "Lightning uses its authoritative element damage")
	_free_fixture(fixture)


func _test_mana_regeneration_and_bounded_damage_return() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var fire: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9201)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(fire, 21).get("ok", false)), "Mana regeneration fixture spends Fire")
	_suite.assert_true(
		bool(runtime.payload_result(21, 21, &"fire_regen", &"fire", 2101, false, 0.0, true).get("ok", false)),
		"Fire hit confirms through the authoritative payload-result ingress"
	)
	_suite.assert_equal(
		runtime.payload_result(21, 22, &"fire_regen", &"fire", 2102, false, 10.0, true).get("code"),
		&"STALE_GENERATION",
		"a stale payload generation fails closed"
	)
	_suite.assert_equal(
		runtime.payload_result(21, 21, &"fire_regen", &"fire", 2101, false, 10.0, true).get("code"),
		&"DUPLICATE_TARGET",
		"the per-action target ledger rejects duplicate damage"
	)
	runtime.finish_action(21)
	runtime.advance_runtime_frame(0)
	runtime.advance_runtime_frame(60)
	_suite.assert_close(float(runtime.snapshot().get("mana", 0.0)), 83.0, "Staff regenerates exactly three Mana per sixty frames")
	var returned: Dictionary = runtime.payload_result(21, 21, &"fire_regen", &"fire", 2102, false, 100.0, true)
	_suite.assert_close(float(returned.get("mana_return", 0.0)), 2.0, "damage returns two percent Mana")
	returned = runtime.payload_result(21, 21, &"fire_regen", &"fire", 2103, false, 1000.0, true)
	_suite.assert_close(float(returned.get("mana_return", 0.0)), 3.0, "one outcome is capped at five returned Mana")
	returned = runtime.payload_result(21, 21, &"fire_regen", &"fire", 2104, true, 1000.0, true)
	_suite.assert_close(float(returned.get("mana_return", 0.0)), 0.0, "multi-target hits cannot exceed the per-outcome cap")
	_suite.assert_equal(
		runtime.payload_result(21, 21, &"fire_regen", &"fire", 2105, true, 10.0, true).get("code"),
		&"OUTCOME_TERMINAL",
		"terminal outcomes reject late duplicate callbacks"
	)

	var near_cap_cast: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9202)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(near_cap_cast, 22).get("ok", false)), "near-cap Mana return fixture commits")
	var near_cap: Dictionary = runtime.snapshot()
	near_cap["mana"] = 99.0
	_suite.assert_true(runtime.restore_snapshot(near_cap), "active Staff snapshot accepts an in-range Mana balance")
	_suite.assert_equal(
		runtime.payload_result(22, 22, &"near_cap", &"fire", 2201, false, -1.0, true).get("code"),
		&"INVALID_DAMAGE",
		"invalid damage cannot mutate the Mana ledger"
	)
	returned = runtime.payload_result(22, 22, &"near_cap", &"fire", 2201, true, 100.0, true)
	_suite.assert_close(float(returned.get("mana_return", 0.0)), 1.0, "Mana return is also bounded by maximum Mana")
	_suite.assert_close(float(runtime.snapshot().get("mana", 0.0)), 100.0, "Mana never exceeds one hundred")
	runtime.finish_action(22)
	runtime.reset_runtime_state(&"mana_reset")
	_suite.assert_close(float(runtime.snapshot().get("mana", 0.0)), 100.0, "reset restores one hundred Mana")
	_suite.assert_equal(runtime.snapshot().get("mana_return_by_outcome"), {}, "reset clears bounded Mana-return ledgers")
	_free_fixture(fixture)


func _test_payload_target_deduplication_is_per_outcome() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var plan: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 30),
		_context(9251)
	).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(plan, 251).get("ok", false)), "per-outcome target fixture commits")
	var first: Dictionary = runtime.payload_result(251, 251, &"tick:0", &"fire", 901, false, 100.0, true)
	var second: Dictionary = runtime.payload_result(251, 251, &"tick:1", &"fire", 901, false, 100.0, true)
	_suite.assert_true(bool(first.get("ok", false)), "first outcome accepts its target")
	_suite.assert_true(bool(second.get("ok", false)), "a different outcome may damage the same target")
	_suite.assert_close(float(first.get("mana_return", 0.0)), 2.0, "first outcome returns its own bounded Mana")
	_suite.assert_close(float(second.get("mana_return", 0.0)), 2.0, "second outcome returns its own bounded Mana")
	_suite.assert_equal(
		runtime.payload_result(251, 251, &"tick:1", &"fire", 901, false, 100.0, true).get("code"),
		&"DUPLICATE_TARGET",
		"the same outcome still rejects a duplicate target"
	)
	runtime.cancel_action(251, &"per_outcome_verified")
	_free_fixture(fixture)


func _test_six_ordered_combinations_and_atomic_refund() -> void:
	for index: int in range(ORDERED_COMBOS.size()):
		var case := ORDERED_COMBOS[index]
		var fixture := _fixture()
		var runtime: RefCounted = fixture["runtime"]
		_set_element(runtime, StringName(case["first"]), 1000 + index * 10)
		var first_token := 1001 + index * 10
		var first: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9300 + index)).get("plan", {})
		_suite.assert_true(bool(runtime.commit_action(first, first_token).get("ok", false)), "%s first cast commits" % case["combo_id"])
		_suite.assert_equal(runtime.snapshot().get("combo_element"), "", "%s commit alone does not open the window" % case["combo_id"])
		_suite.assert_true(
			bool(runtime.payload_result(
				first_token,
				first_token,
				StringName("first_%s" % case["combo_id"]),
				StringName(case["first"]),
				first_token,
				true,
				0.0,
				true
			).get("ok", false)),
			"%s first hit opens the window" % case["combo_id"]
		)
		runtime.finish_action(first_token)
		_set_element(runtime, StringName(case["second"]), first_token + 1)
		var second_token := first_token + 4
		var second: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9400 + index)).get("plan", {})
		var expected_cost := float(ELEMENT_COSTS[case["second"]]) + float(case["extra"])
		_suite.assert_close(float(second.get("mana_cost", 0.0)), expected_cost, "%s reserves base plus combination Mana" % case["combo_id"])
		_suite.assert_equal((second.get("combo", {}) as Dictionary).get("combo_id"), case["combo_id"], "%s preserves ordered pair identity" % case["combo_id"])
		_suite.assert_true(bool(runtime.commit_action(second, second_token).get("ok", false)), "%s second cast reserves atomically" % case["combo_id"])
		var confirmation: Dictionary = runtime.payload_result(
			second_token,
			second_token,
			StringName("second_%s" % case["combo_id"]),
			StringName(case["second"]),
			second_token,
			true,
			0.0,
			true
		)
		_suite.assert_equal((confirmation.get("combo", {}) as Dictionary).get("combo_id"), case["combo_id"], "%s triggers only on second hit confirmation" % case["combo_id"])
		runtime.finish_action(second_token)
		var expected_mana := 100.0 - float(ELEMENT_COSTS[case["first"]]) - expected_cost
		_suite.assert_close(float(runtime.snapshot().get("mana", 0.0)), expected_mana, "%s consumes its confirmed reservation" % case["combo_id"])
		_free_fixture(fixture)

	var rollback_fixture := _fixture()
	var rollback_runtime: RefCounted = rollback_fixture["runtime"]
	var rollback_adapter: FakeStaffAdapter = rollback_fixture["adapter"]
	_commit_confirmed_element(rollback_runtime, &"fire", 1701, 9501)
	_set_element(rollback_runtime, &"ice", 1702)
	var before_second: Dictionary = rollback_runtime.snapshot()
	var ice_combo: Dictionary = rollback_runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9502)).get("plan", {})
	rollback_adapter.fail_begin = true
	_suite.assert_true(not bool(rollback_runtime.commit_action(ice_combo, 1705).get("ok", false)), "payload construction failure rejects the combination")
	_suite.assert_equal(rollback_runtime.snapshot(), before_second, "failed construction preserves Mana and sequence atomically")
	rollback_adapter.fail_begin = false
	_suite.assert_true(bool(rollback_runtime.commit_action(ice_combo, 1705).get("ok", false)), "combination commits after construction recovers")
	_suite.assert_close(float(rollback_runtime.snapshot().get("mana", 0.0)), 40.0, "Fire to Ice reserves twenty-five plus fifteen")
	rollback_runtime.cancel_action(1705, &"combo_cancelled")
	_suite.assert_close(float(rollback_runtime.snapshot().get("mana", 0.0)), 55.0, "cancel refunds only the extra combination reservation")
	_suite.assert_true(bool(rollback_runtime.commit_action(ice_combo, 1706).get("ok", false)), "combination can reserve again after cancel")
	var missed: Dictionary = rollback_runtime.payload_result(1706, 1706, &"missed_combo", &"ice", -1, true, 0.0, false)
	_suite.assert_true(bool(missed.get("ok", false)), "terminal miss closes the pending combination outcome")
	_suite.assert_close(float(missed.get("refunded_mana", 0.0)), 15.0, "terminal miss refunds the combination surcharge exactly once")
	var after_miss := float(rollback_runtime.snapshot().get("mana", 0.0))
	_suite.assert_true(not bool(rollback_runtime.payload_result(1706, 1706, &"missed_combo", &"ice", -1, true, 0.0, false).get("ok", false)), "duplicate terminal miss fails closed")
	_suite.assert_close(float(rollback_runtime.snapshot().get("mana", 0.0)), after_miss, "duplicate terminal miss cannot refund twice")
	rollback_runtime.finish_action(1706)
	var expiry_balance: Dictionary = rollback_runtime.snapshot()
	expiry_balance["mana"] = 55.0
	_suite.assert_true(rollback_runtime.restore_snapshot(expiry_balance), "reservation-expiry fixture restores enough Mana")
	_suite.assert_true(bool(rollback_runtime.commit_action(ice_combo, 1707).get("ok", false)), "unresolved combination reserves for the expiry path")
	_suite.assert_close(float(rollback_runtime.snapshot().get("mana", 0.0)), 15.0, "expiry fixture reserves base plus surcharge")
	rollback_runtime.advance_runtime_frame(0)
	rollback_runtime.advance_runtime_frame(300)
	_suite.assert_close(float(rollback_runtime.snapshot().get("mana", 0.0)), 45.0, "reservation expiry refunds the surcharge while normal Mana regeneration continues")
	rollback_runtime.advance_runtime_frame(301)
	_suite.assert_close(float(rollback_runtime.snapshot().get("mana", 0.0)), 45.05, "expired reservation cannot refund twice")
	rollback_runtime.finish_action(1707)
	_free_fixture(rollback_fixture)


func _test_near_expiry_combo_projectile_does_not_extend_window() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	_commit_confirmed_element(runtime, &"fire", 1751, 9551)
	_set_element(runtime, &"ice", 1752)
	runtime.advance_runtime_frame(0)
	runtime.advance_runtime_frame(298)
	_suite.assert_equal(
		runtime.snapshot().get("combo_remaining_frames"),
		2,
		"near-expiry fixture leaves only two frames in the original combination window"
	)

	var second_token := 1755
	var second: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 30),
		_context(9552)
	).get("plan", {})
	_suite.assert_equal(
		second.get("combo_window_remaining_frames"),
		2,
		"combination plan freezes the original window remaining at commit"
	)
	_suite.assert_true(
		bool(runtime.commit_action(second, second_token).get("ok", false)),
		"near-expiry second element commits"
	)
	_suite.assert_equal(
		(runtime.snapshot().get("pending_combo", {}) as Dictionary).get("remaining_frames"),
		2,
		"pending combination inherits the frozen window instead of resetting to three hundred frames"
	)
	var mana_after_commit := float(runtime.snapshot().get("mana", 0.0))
	runtime.finish_action(second_token)

	runtime.advance_runtime_frame(300)
	var expired: Dictionary = runtime.snapshot()
	_suite.assert_equal(expired.get("pending_combo"), {}, "original combination expiry clears the pending reservation")
	_suite.assert_equal(
		((expired.get("cast_ledgers", {}) as Dictionary).get(str(second_token), {}) as Dictionary).get("combo"),
		{},
		"original combination expiry clears the token ledger combination"
	)
	_suite.assert_close(
		float(expired.get("mana", 0.0)),
		mana_after_commit + 15.0 + 0.1,
		"original combination expiry refunds the surcharge exactly once while Mana regenerates"
	)
	runtime.advance_runtime_frame(301)
	_suite.assert_close(
		float(runtime.snapshot().get("mana", 0.0)),
		mana_after_commit + 15.0 + 0.15,
		"later frames cannot refund the expired surcharge twice"
	)

	var late_hit: Dictionary = runtime.payload_result(
		second_token,
		second_token,
		&"late_ice_projectile",
		&"ice",
		second_token,
		true,
		0.0,
		true
	)
	_suite.assert_true(bool(late_hit.get("ok", false)), "late projectile remains a valid normal element hit")
	_suite.assert_equal(late_hit.get("combo"), {}, "late projectile cannot trigger the expired combination")
	_suite.assert_close(
		float(runtime.snapshot().get("mana", 0.0)),
		mana_after_commit + 15.0 + 0.15,
		"late projectile cannot refund the expired surcharge again"
	)
	_free_fixture(fixture)


func _test_overlapping_combo_reservations_are_token_owned() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	_commit_confirmed_element(runtime, &"fire", 1761, 9561)
	_set_element(runtime, &"ice", 1762)
	var combo_plan: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 30),
		_context(9562)
	).get("plan", {})
	var tokens: Array[int] = [1765, 1766, 1767]
	for token: int in tokens:
		var refill: Dictionary = runtime.snapshot()
		refill["mana"] = 100.0
		_suite.assert_true(runtime.restore_snapshot(refill), "overlap token %d restores Mana without losing reservations" % token)
		_suite.assert_true(bool(runtime.commit_action(combo_plan, token).get("ok", false)), "overlap token %d reserves independently" % token)
		runtime.finish_action(token)
	var pending: Dictionary = runtime.snapshot().get("pending_combos", {})
	_suite.assert_equal(pending.size(), 3, "three in-flight combination casts retain three token-owned reservations")

	var confirmed: Dictionary = runtime.payload_result(1766, 1766, &"confirmed_overlap", &"ice", 1766, true, 0.0, true)
	_suite.assert_equal((confirmed.get("combo", {}) as Dictionary).get("combo_id"), "steam_burst", "one overlap token confirms its own combination")
	pending = runtime.snapshot().get("pending_combos", {})
	_suite.assert_true(not pending.has("1766") and pending.has("1765") and pending.has("1767"), "confirmation removes only its token reservation")

	var missed: Dictionary = runtime.payload_result(1765, 1765, &"missed_overlap", &"ice", -1, true, 0.0, false)
	_suite.assert_close(float(missed.get("refunded_mana", 0.0)), 15.0, "one overlap miss refunds only its surcharge")
	var ledgers: Dictionary = runtime.snapshot().get("cast_ledgers", {})
	_suite.assert_equal((ledgers.get("1765", {}) as Dictionary).get("combo"), {}, "miss clears only the missed token ledger")
	_suite.assert_equal((ledgers.get("1766", {}) as Dictionary).get("combo"), {}, "confirmation consumes the confirmed token ledger")

	runtime.advance_runtime_frame(0)
	runtime.advance_runtime_frame(300)
	var expired: Dictionary = runtime.snapshot()
	_suite.assert_equal(expired.get("pending_combos"), {}, "expiry closes the final overlap reservation")
	ledgers = expired.get("cast_ledgers", {})
	_suite.assert_equal((ledgers.get("1767", {}) as Dictionary).get("combo"), {}, "expiry clears only the expiring token ledger")
	_free_fixture(fixture)


func _test_lightning_first_combo_preserves_origin_material() -> void:
	for second_element: StringName in [&"fire", &"ice"]:
		var fixture := _fixture()
		var runtime: RefCounted = fixture["runtime"]
		_set_element(runtime, &"lightning", 1770)
		var lightning: Dictionary = runtime.plan_intent(
			_release_intent(&"weapon_primary", 30),
			_context(9570)
		).get("plan", {})
		_suite.assert_true(bool(runtime.commit_action(lightning, 1775).get("ok", false)), "Lightning opener commits for %s" % str(second_element))
		var opener: Dictionary = runtime.handle_payload_result(1775, 1775, {
			"outcome_id": "lightning_opener",
			"element": "lightning",
			"target_id": 10,
			"terminal": true,
			"damage": 27.0,
			"hit": true,
			"chain_target_ids": [20, 30],
			"chain_origin_positions": [Vector2(64.0, 0.0), Vector2(128.0, 0.0)],
		})
		_suite.assert_true(bool(opener.get("ok", false)), "Lightning opener records stable chain material")
		runtime.finish_action(1775)
		_set_element(runtime, second_element, 1776)
		var second: Dictionary = runtime.plan_intent(
			_release_intent(&"weapon_primary", 30),
			_context(9571)
		).get("plan", {})
		_suite.assert_true(bool(runtime.commit_action(second, 1780).get("ok", false)), "Lightning to %s second cast commits" % str(second_element))
		var result: Dictionary = runtime.handle_payload_result(1780, 1780, {
			"outcome_id": "second_hit",
			"element": str(second_element),
			"target_id": 40,
			"terminal": true,
			"damage": 9.0,
			"hit": true,
			"chain_target_ids": [],
		})
		var confirmed_combo: Dictionary = result.get("combo", {})
		var parameters: Dictionary = confirmed_combo.get("parameters", {})
		_suite.assert_equal(parameters.get("origin_target_ids"), [20, 30], "Lightning-first %s uses first-cast chain ids" % str(second_element))
		_suite.assert_equal(
			parameters.get("origin_positions"),
			[Vector2(64.0, 0.0), Vector2(128.0, 0.0)],
			"Lightning-first %s uses first-cast stable positions"
			% str(second_element)
		)
		runtime.finish_action(1780)
		_free_fixture(fixture)


func _test_same_element_timeout_and_insufficient_total_reject() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	_commit_confirmed_element(runtime, &"fire", 1801, 9601)
	var same: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9602)).get("plan", {})
	_suite.assert_true((same.get("combo", {}) as Dictionary).is_empty(), "same-element casts cannot form a combination")
	_suite.assert_close(float(same.get("mana_cost", 0.0)), 20.0, "same-element rejection reserves only the base spell")
	runtime.advance_runtime_frame(0)
	runtime.advance_runtime_frame(299)
	_suite.assert_equal(runtime.snapshot().get("combo_remaining_frames"), 1, "ordered combination window remains open through frame 299")
	runtime.advance_runtime_frame(300)
	_suite.assert_equal(runtime.snapshot().get("combo_remaining_frames"), 0, "ordered combination window expires at frame 300")
	_set_element(runtime, &"ice", 1802)
	var expired: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9603)).get("plan", {})
	_suite.assert_true((expired.get("combo", {}) as Dictionary).is_empty(), "expired first hit cannot reserve a combination")

	runtime.reset_runtime_state(&"insufficient_fixture")
	_commit_confirmed_element(runtime, &"fire", 1811, 9604)
	_set_element(runtime, &"ice", 1812)
	var low: Dictionary = runtime.snapshot()
	low["mana"] = 39.0
	_suite.assert_true(runtime.restore_snapshot(low), "insufficient fixture restores thirty-nine Mana")
	var rejected: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9605))
	_suite.assert_true(not bool(rejected.get("ok", false)), "insufficient base plus combination Mana rejects before construction")
	_suite.assert_equal(rejected.get("code"), &"INSUFFICIENT_MANA", "insufficient total reports the Staff resource boundary")
	_suite.assert_close(float(runtime.snapshot().get("mana", 0.0)), 39.0, "rejected planning does not mutate Mana")
	_suite.assert_equal(runtime.snapshot().get("combo_element"), "fire", "rejected planning does not mutate the confirmed sequence")
	_free_fixture(fixture)


func _test_four_time_context_plans() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var missing_generation := _context(9700)
	missing_generation["time_interactions"] = {"stop_active": true}
	_suite.assert_equal(
		runtime.plan_intent(_press_intent(&"weapon_skill"), missing_generation).get("code"),
		&"SOURCE_GENERATION_REQUIRED",
		"active time interactions fail closed without a source generation"
	)
	var stop_context := _context(9701)
	stop_context["time_interactions"] = {"stop_active": true, "stop_generation": 31}
	var collapse: Dictionary = runtime.plan_intent(_press_intent(&"weapon_skill"), stop_context).get("plan", {})
	var stop := _dictionary_by_id(collapse.get("time_interactions", []), "interaction_id", "staff_stop_field")
	_suite.assert_close(float(stop.get("area_multiplier", 0.0)), 1.5, "Stop expands Plane Collapse area by 1.5")
	_suite.assert_equal(stop.get("requires_action"), "planar_collapse", "Stop field remains action-scoped")

	var rewind_context := _context(9702)
	rewind_context["time_interactions"] = {"rewind_echo_available": true, "rewind_echo_generation": 41}
	var rewind: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), rewind_context).get("plan", {})
	_suite.assert_close(float(rewind.get("mana_cost", -1.0)), 0.0, "Rewind makes one charged spell Mana-free")
	_suite.assert_close(float(_payload_parameters(rewind).get("damage_multiplier", 0.0)), 5.2, "Rewind empowers authoritative Fire damage by thirty percent")
	var rewind_descriptor := _dictionary_by_id(rewind.get("time_interactions", []), "interaction_id", "staff_rewind_free_cast")
	_suite.assert_equal(rewind_descriptor.get("rewind_generation"), 41, "Rewind freezes its generation")
	_suite.assert_true(bool(runtime.commit_action(rewind, 1901).get("ok", false)), "Rewind charged cast commits")
	runtime.cancel_action(1901, &"rewind_verified")
	var claimed: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), rewind_context).get("plan", {})
	_suite.assert_close(float(claimed.get("mana_cost", 0.0)), 20.0, "claimed Rewind generation cannot make a second cast free")

	var accelerate_context := _context(9703)
	accelerate_context["time_interactions"] = {"accelerate_active": true, "accelerate_generation": 42}
	var accelerated_hold: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), accelerate_context).get("plan", {})
	_suite.assert_equal(_phase(accelerated_hold, 0).get("charge_complete_frames"), 15, "Accelerate completes Staff charge at fifteen frames")
	var accelerated: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 15), accelerate_context).get("plan", {})
	_suite.assert_equal(accelerated.get("action_id"), "charged_element", "Accelerate frame fifteen resolves a charged spell")
	_suite.assert_close(float(accelerated.get("mana_cost", 0.0)), 14.0, "Accelerate reduces Fire Mana cost by thirty percent")
	var fast := _dictionary_by_id(accelerated.get("time_interactions", []), "interaction_id", "staff_fast_charge")
	_suite.assert_close(float(fast.get("mana_multiplier", 0.0)), 0.7, "Accelerate descriptor freezes its Mana multiplier")

	runtime.reset_runtime_state(&"rift_fixture")
	_commit_confirmed_element(runtime, &"fire", 1911, 9704)
	_set_element(runtime, &"ice", 1912)
	var rift_context := _context(9705)
	rift_context["time_interactions"] = {
		"rift_active": true,
		"rift_generation": 43,
		"active_rifts": [{
			"generation": 43,
			"center": Vector2(640.0, 320.0),
			"radius": 92.0,
		}],
	}
	var rift_combo: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), rift_context).get("plan", {})
	var rift := _dictionary_by_id(rift_combo.get("time_interactions", []), "interaction_id", "staff_rift_combination")
	_suite.assert_close(float(rift.get("area_multiplier", 0.0)), 1.3, "Rift expands ordered combination area")
	_suite.assert_close(float(rift.get("time_damage_multiplier", 0.0)), 0.5, "Rift adds bounded Time damage")
	_suite.assert_equal(rift.get("combo_id"), "steam_burst", "Rift descriptor binds the frozen ordered pair")
	_suite.assert_equal((rift.get("active_rifts", []) as Array).size(), 1, "Rift descriptor carries frozen spatial descriptors into execution")
	_suite.assert_equal(((rift.get("active_rifts", []) as Array)[0] as Dictionary).get("generation"), 43, "Rift spatial descriptor preserves source generation")
	_free_fixture(fixture)


func _test_rewind_claims_are_bounded_and_restore_safe() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	for index: int in range(260):
		var generation := index + 1
		var context := _context(9720 + index)
		context["time_interactions"] = {
			"rewind_cast_available": true,
			"rewind_generation": generation,
		}
		var plan: Dictionary = runtime.plan_intent(
			_release_intent(&"weapon_primary", 30),
			context
		).get("plan", {})
		var token := 2200 + index
		_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "bounded Rewind generation %d commits" % generation)
		runtime.cancel_action(token, &"bounded_rewind_fixture")
	var claimed: Array = runtime.snapshot().get("claimed_rewind_generations", [])
	_suite.assert_equal(claimed.size(), 256, "Staff retains at most 256 Rewind generation claims")
	_suite.assert_true(1 not in claimed and 4 not in claimed, "Staff prunes the oldest Rewind generation claims")
	_suite.assert_true(5 in claimed and 260 in claimed, "Staff retains the newest Rewind generation claims")
	_suite.assert_equal(runtime.snapshot().get("claimed_rewind_generation_floor"), 4, "Staff retains a monotonic floor for pruned Rewind claims")
	var old_context := _context(99801)
	old_context["time_interactions"] = {"rewind_cast_available": true, "rewind_generation": 1}
	var old_generation_plan: Dictionary = runtime.plan_intent(
		_release_intent(&"weapon_primary", 30),
		old_context
	).get("plan", {})
	_suite.assert_close(float(old_generation_plan.get("mana_cost", 0.0)), 20.0, "a pruned Rewind generation cannot become free again")

	var valid_snapshot: Dictionary = runtime.snapshot()
	_suite.assert_true(runtime.restore_snapshot(valid_snapshot), "bounded Rewind claim snapshot restores")
	var invalid_snapshot := valid_snapshot.duplicate(true)
	var oversized: Array[int] = []
	for generation: int in range(1, 258):
		oversized.append(generation)
	invalid_snapshot["claimed_rewind_generations"] = oversized
	_suite.assert_true(not runtime.restore_snapshot(invalid_snapshot), "oversized Rewind claim snapshot fails closed")
	_suite.assert_equal(runtime.snapshot(), valid_snapshot, "rejected Rewind claim snapshot leaves runtime state unchanged")
	_free_fixture(fixture)


func _test_skill_ultimate_and_boss_descriptors() -> void:
	var first_fixture := _fixture()
	var first_runtime: RefCounted = first_fixture["runtime"]
	var first_adapter: FakeStaffAdapter = first_fixture["adapter"]
	var skill: Dictionary = first_runtime.plan_intent(_press_intent(&"weapon_skill"), _context(9751)).get("plan", {})
	_suite.assert_close(float(skill.get("mana_cost", 0.0)), 30.0, "Plane Collapse reserves thirty Mana")
	_suite.assert_close(float((skill.get("resource_costs", {}) as Dictionary).get("time_energy", 0.0)), 20.0, "Plane Collapse exposes its external Time Energy cost")
	var boss := skill.get("boss_conversion", {}) as Dictionary
	_suite.assert_equal(boss.get("active_attack_policy"), "preserve_committed", "Staff never interrupts a committed Boss attack")
	_suite.assert_equal(boss.get("allowed_states"), ["RECOVERY", "EXPOSED"], "Staff control conversion is limited to readable Boss windows")
	_suite.assert_equal(boss.get("cleanup_policy"), "source_generation_owned", "Boss conversion cleanup is generation-owned")

	var ultimate_hold: Dictionary = first_runtime.plan_intent(_press_intent(&"weapon_ultimate"), _context(9752)).get("plan", {})
	_suite.assert_equal(_phase(ultimate_hold, 0).get("minimum_hold_frames"), 60, "Primordial Wrath requires sixty hold frames")
	var ultimate: Dictionary = first_runtime.plan_intent(_release_intent(&"weapon_ultimate", 60), _context(9753)).get("plan", {})
	_suite.assert_close(float(ultimate.get("mana_cost", 0.0)), 60.0, "Primordial Wrath reserves sixty Mana")
	_suite.assert_close(float((ultimate.get("resource_costs", {}) as Dictionary).get("time_energy", 0.0)), 55.0, "Primordial Wrath exposes its external Time Energy cost")
	_suite.assert_true(bool(first_runtime.commit_action(ultimate, 3001).get("ok", false)), "first deterministic ultimate commits")
	var first_descriptors: Array = (first_adapter.staged_definition.get("payload_descriptors", []) as Array).duplicate(true)
	_suite.assert_equal(first_descriptors.size(), 1, "Primordial Wrath materializes one deterministic sequence zone")
	if first_descriptors.size() == 1:
		_suite.assert_equal(
			int((first_descriptors[0].get("parameters", {}) as Dictionary).get("count", 0)),
			20,
			"Primordial Wrath sequence zone owns exactly twenty outcomes"
		)

	var second_fixture := _fixture()
	var second_runtime: RefCounted = second_fixture["runtime"]
	var second_adapter: FakeStaffAdapter = second_fixture["adapter"]
	var repeated: Dictionary = second_runtime.plan_intent(_release_intent(&"weapon_ultimate", 60), _context(9753)).get("plan", {})
	_suite.assert_true(bool(second_runtime.commit_action(repeated, 3001).get("ok", false)), "second deterministic ultimate commits")
	_suite.assert_equal((second_adapter.staged_definition.get("payload_descriptors", []) as Array), first_descriptors, "same seed and token reproduce the exact ultimate sequence")
	_free_fixture(second_fixture)
	_free_fixture(first_fixture)


func _test_coordinator_hold_snapshot_and_reset_boundaries() -> void:
	_coordinator_facts.clear()
	var fixture := _coordinator_fixture()
	var runtime: RefCounted = fixture["runtime"]
	var coordinator: RefCounted = fixture["coordinator"]
	_suite.assert_true(bool(coordinator.submit_intent(_press_intent(&"weapon_primary"), _context(9801)).get("ok", false)), "Coordinator accepts Staff primary HOLD")
	for _frame: int in range(30):
		coordinator.advance_frame()
	var released: Dictionary = coordinator.submit_intent(_release_intent(&"weapon_primary", 0), _context(9802))
	_suite.assert_true(bool(released.get("ok", false)), "Coordinator releases frame-thirty Staff charge")
	_suite.assert_equal(_coordinator_facts.back().get("action_id"), "charged_element", "Coordinator publishes the finalized charged action identity")
	_suite.assert_close(float(runtime.snapshot().get("mana", 0.0)), 80.0, "Coordinator release commits runtime-owned Mana")
	coordinator.cancel(&"coordinator_verified")

	var hold: Dictionary = runtime.plan_intent(_press_intent(&"weapon_primary"), _context(9803)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(hold, 2001).get("ok", false)), "Staff HOLD commits without staging a payload")
	var hold_snapshot: Dictionary = runtime.snapshot()
	runtime.cancel_action(2001, &"snapshot_fixture")
	_suite.assert_true(runtime.restore_snapshot(hold_snapshot), "quiescent Staff HOLD snapshot restores")
	_suite.assert_equal(runtime.snapshot().get("active_phase"), "HOLD", "restored Staff HOLD preserves coordinator-owned phase identity")
	var released_hold: Dictionary = runtime.release_hold(hold, 2001, 30)
	_suite.assert_true(bool(released_hold.get("ok", false)), "restored HOLD releases on its original token")
	runtime.cancel_action(2001, &"snapshot_cleanup")

	var active_plan: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(9804)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(active_plan, 2002).get("ok", false)), "active snapshot fixture stages a real payload")
	_suite.assert_equal(runtime.on_phase_enter(active_plan, &"ACTIVE", 2002).size(), 2, "active snapshot fixture releases the payload")
	var active_snapshot: Dictionary = runtime.snapshot()
	runtime.cancel_action(2002, &"active_snapshot_fixture")
	_suite.assert_true(not runtime.restore_snapshot(active_snapshot), "released ACTIVE payload snapshots fail closed")
	_suite.assert_equal(runtime.snapshot().get("active_phase"), "READY", "failed ACTIVE restore preserves a safe ready state")

	runtime.reset_runtime_state(&"new_run")
	var reset: Dictionary = runtime.snapshot()
	_suite.assert_close(float(reset.get("mana", 0.0)), 100.0, "new run restores Mana")
	_suite.assert_equal(reset.get("current_element"), "fire", "new run restores Fire")
	_suite.assert_equal(reset.get("combo_element"), "", "new run clears ordered sequence")
	_suite.assert_equal(reset.get("combo_remaining_frames"), 0, "new run clears combination window")
	_suite.assert_equal(reset.get("pending_combo"), {}, "new run clears reservations")
	_suite.assert_equal(reset.get("active_phase"), "READY", "new run clears active action state")
	_free_fixture(fixture)


func _test_cast_ledgers_are_bounded() -> void:
	var fixture := _fixture()
	var runtime: RefCounted = fixture["runtime"]
	var first_token := 4001
	for index: int in range(260):
		var token := first_token + index
		var plan: Dictionary = runtime.plan_intent(
			_release_intent(&"weapon_primary", 30),
			_context(11000 + index)
		).get("plan", {})
		_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "bounded ledger cast %d commits" % index)
		runtime.finish_action(token)
		var refill: Dictionary = runtime.snapshot()
		refill["mana"] = 100.0
		_suite.assert_true(runtime.restore_snapshot(refill), "bounded ledger cast %d restores quiescent Mana" % index)
	var ledgers: Dictionary = runtime.snapshot().get("cast_ledgers", {})
	_suite.assert_equal(ledgers.size(), 256, "Staff retains at most 256 completed cast ledgers")
	_suite.assert_true(not ledgers.has(str(first_token)), "Staff prunes the oldest completed cast ledger")
	_suite.assert_true(ledgers.has(str(first_token + 259)), "Staff retains the newest completed cast ledger")
	_free_fixture(fixture)


func _fixture() -> Dictionary:
	var owner := Node2D.new()
	var adapter := FakeStaffAdapter.new()
	adapter.name = "StaffWeapon"
	owner.add_child(adapter)
	var definition := _catalog_profile("staff_launch_v1")
	var profile = WeaponRuntimeProfileScript.new()
	var parsed: Dictionary = profile.configure(definition)
	var modifiers = WeaponModifierStateScript.new()
	var capabilities := PackedStringArray(definition.get("capabilities", []))
	var configured_modifiers := modifiers.configure(capabilities, _modifier_bounds(capabilities))
	var runtime = StaffWeaponRuntimeScript.new()
	var configured: bool = bool(parsed.get("ok", false)) and configured_modifiers and runtime.configure(owner, profile, modifiers)
	return {
		"owner": owner,
		"adapter": adapter,
		"profile": profile,
		"modifiers": modifiers,
		"runtime": runtime,
		"configured": configured,
	}


func _coordinator_fixture() -> Dictionary:
	var fixture := _fixture()
	var provider := FakeTimeEnergyProvider.new()
	var transaction = WeaponResourceTransactionScript.new()
	_suite.assert_true(
		transaction.configure(&"staff", PackedStringArray(["mana"]), {&"time_energy": provider}),
		"Staff resource transaction recognizes runtime-owned Mana"
	)
	var coordinator = WeaponActionCoordinatorScript.new()
	_suite.assert_true(coordinator.configure(fixture["runtime"], transaction), "Coordinator accepts the Staff runtime contract")
	coordinator.weapon_action_committed.connect(_on_staff_action_committed)
	fixture["provider"] = provider
	fixture["transaction"] = transaction
	fixture["coordinator"] = coordinator
	return fixture


func _on_staff_action_committed(
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


func _commit_confirmed_element(
	runtime: RefCounted,
	element: StringName,
	token: int,
	run_seed: int
) -> void:
	_set_element(runtime, element, token - 3)
	var plan: Dictionary = runtime.plan_intent(_release_intent(&"weapon_primary", 30), _context(run_seed)).get("plan", {})
	_suite.assert_true(bool(runtime.commit_action(plan, token).get("ok", false)), "%s fixture cast commits" % str(element))
	_suite.assert_true(
		bool(runtime.payload_result(token, token, StringName("fixture_%d" % token), element, token, true, 0.0, true).get("ok", false)),
		"%s fixture hit confirms" % str(element)
	)
	runtime.finish_action(token)


func _set_element(runtime: RefCounted, target: StringName, token_seed: int) -> void:
	var guard := 0
	while StringName(str(runtime.presentation_snapshot().get("element", ""))) != target and guard < 3:
		_suite.assert_true(_cycle_element(runtime, token_seed + guard), "element cycle reaches %s" % str(target))
		guard += 1
	_suite.assert_equal(runtime.presentation_snapshot().get("element"), str(target), "current element resolves %s" % str(target))


func _cycle_element(runtime: RefCounted, token: int) -> bool:
	var plan_result: Dictionary = runtime.plan_intent(_press_intent(&"weapon_utility"), _context(9900 + token))
	if not bool(plan_result.get("ok", false)):
		return false
	var plan: Dictionary = plan_result["plan"]
	if not bool(runtime.commit_action(plan, token).get("ok", false)):
		return false
	runtime.finish_action(token)
	return true


func _assert_profile_rejected(owner: Node, modifiers: RefCounted, definition: Dictionary, label: String) -> void:
	var profile = WeaponRuntimeProfileScript.new()
	var parsed: Dictionary = profile.configure(definition)
	_suite.assert_true(bool(parsed.get("ok", false)), "%s drift remains parser-valid" % label)
	var runtime = StaffWeaponRuntimeScript.new()
	_suite.assert_true(not runtime.configure(owner, profile, modifiers), "runtime rejects frozen %s drift" % label)


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
		"time_interactions": {},
	}


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


func _first_descriptor_parameters(definition: Dictionary) -> Dictionary:
	var descriptors_value: Variant = definition.get("payload_descriptors", [])
	if not descriptors_value is Array or (descriptors_value as Array).is_empty():
		return {}
	var descriptor_value: Variant = (descriptors_value as Array)[0]
	if not descriptor_value is Dictionary:
		return {}
	var parameters_value: Variant = (descriptor_value as Dictionary).get("parameters", {})
	return (parameters_value as Dictionary).duplicate(true) if parameters_value is Dictionary else {}


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
		bounds[capability] = {"minimum": 0.1, "maximum": 200.0}
	return bounds
