extends Node

const GauntletsComboStateScript := preload(
	"res://scripts/combat/weapons/gauntlets_combo_state.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_chain_and_combo_are_independent()
	_test_five_step_chain_wraps_authoritatively()
	_test_target_deduplication_is_per_action_token()
	_test_timeout_damage_and_dash_boundaries()
	_test_all_combo_tier_boundaries()
	_test_snapshot_restore_and_bounded_ledger()
	_suite.finish(get_tree())


func _test_chain_and_combo_are_independent() -> void:
	var state = GauntletsComboStateScript.new()
	_suite.assert_equal(state.peek_primary_action_id(), &"punch_1", "fresh chain starts at punch one")
	_suite.assert_true(state.commit_primary_action(&"punch_1", 1), "punch one advances the chain")
	_suite.assert_equal(state.snapshot().get("chain_step"), 1, "chain advances before any hit confirms")
	_suite.assert_equal(state.snapshot().get("combo_count"), 0, "chain commit does not invent Combo")
	var confirmed: Dictionary = state.record_hit(1, 1, 101, 1, true)
	_suite.assert_true(bool(confirmed.get("ok", false)), "eligible hit confirms")
	_suite.assert_equal(confirmed.get("combo_gain"), 1, "eligible hit grants its frozen gain")
	_suite.assert_equal(state.snapshot().get("chain_step"), 1, "hit confirmation never advances chain")
	_suite.assert_equal(state.snapshot().get("combo_count"), 1, "hit confirmation advances Combo")
	state.reset_combo(&"separation_check")
	_suite.assert_equal(state.snapshot().get("chain_step"), 1, "Combo reset preserves chain state")
	_suite.assert_equal(state.snapshot().get("combo_count"), 0, "Combo reset clears only Combo")


func _test_five_step_chain_wraps_authoritatively() -> void:
	var state = GauntletsComboStateScript.new()
	var expected: Array[StringName] = [&"punch_1", &"punch_2", &"punch_3", &"punch_4", &"punch_5"]
	for index: int in range(expected.size()):
		_suite.assert_equal(state.peek_primary_action_id(), expected[index], "chain exposes punch %d" % (index + 1))
		_suite.assert_true(state.commit_primary_action(expected[index], index + 1), "chain commits punch %d" % (index + 1))
	_suite.assert_equal(state.peek_primary_action_id(), &"punch_1", "fifth punch wraps to punch one")
	_suite.assert_true(not state.commit_primary_action(&"punch_4", 10), "out-of-order chain action fails closed")
	_suite.assert_equal(state.peek_primary_action_id(), &"punch_1", "rejected action cannot mutate chain")
	state.reset_chain()
	_suite.assert_equal(state.peek_primary_action_id(), &"punch_1", "explicit chain reset returns to punch one")


func _test_target_deduplication_is_per_action_token() -> void:
	var state = GauntletsComboStateScript.new()
	var first: Dictionary = state.record_hit(20, 20, 7001, 3, true)
	var duplicate: Dictionary = state.record_hit(20, 20, 7001, 3, true)
	var second_target: Dictionary = state.record_hit(20, 20, 7002, 3, true)
	var next_action: Dictionary = state.record_hit(21, 21, 7001, 1, true)
	_suite.assert_equal(first.get("combo_gain"), 3, "first token-target pair grants Combo")
	_suite.assert_equal(duplicate.get("code"), &"DUPLICATE_TARGET", "same token-target pair is rejected")
	_suite.assert_equal(second_target.get("combo_gain"), 3, "same token may confirm a different target")
	_suite.assert_equal(next_action.get("combo_gain"), 1, "new token may confirm the original target")
	_suite.assert_equal(state.snapshot().get("combo_count"), 7, "deduplication admits only unique token-target pairs")
	_suite.assert_equal(
		state.record_hit(21, 22, 7003, 1, true).get("code"),
		&"STALE_GENERATION",
		"mismatched generation fails closed"
	)
	var ineligible: Dictionary = state.record_hit(22, 22, 7004, 5, false)
	_suite.assert_true(bool(ineligible.get("ok", false)), "ineligible auxiliary hit is handled")
	_suite.assert_equal(ineligible.get("combo_gain"), 0, "ineligible auxiliary hit cannot grant Combo")
	_suite.assert_equal(state.snapshot().get("combo_count"), 7, "ineligible hit preserves Combo")


func _test_timeout_damage_and_dash_boundaries() -> void:
	var state = GauntletsComboStateScript.new()
	state.record_hit(30, 30, 8001, 5, true)
	_suite.assert_true(not state.advance_frames(119), "one hundred nineteen quiet frames retain Combo")
	_suite.assert_equal(state.snapshot().get("combo_count"), 5, "Combo survives frame one hundred nineteen")
	state.notify_dash_completed()
	_suite.assert_equal(state.snapshot().get("combo_count"), 5, "Dash never resets Combo")
	_suite.assert_true(state.advance_frames(1), "frame one hundred twenty resets Combo")
	_suite.assert_equal(state.snapshot().get("combo_count"), 0, "timeout clears Combo exactly at one hundred twenty")
	state.record_hit(31, 31, 8002, 3, true)
	_suite.assert_true(not state.notify_real_damage(0.0), "zero damage does not reset Combo")
	_suite.assert_equal(state.snapshot().get("combo_count"), 3, "zero damage preserves Combo")
	_suite.assert_true(state.notify_real_damage(1.0), "real player damage resets Combo")
	_suite.assert_equal(state.snapshot().get("combo_count"), 0, "real player damage clears Combo")
	_suite.assert_true(not state.notify_real_damage(NAN), "non-finite damage fails closed")


func _test_all_combo_tier_boundaries() -> void:
	var cases: Array[Dictionary] = [
		{"combo": 4, "tier": "none", "speed": 1.0, "critical": 0.0, "time": 0.0, "energy": 0, "aura": false},
		{"combo": 5, "tier": "gale", "speed": 1.10, "critical": 0.0, "time": 0.0, "energy": 0, "aura": false},
		{"combo": 9, "tier": "gale", "speed": 1.10, "critical": 0.0, "time": 0.0, "energy": 0, "aura": false},
		{"combo": 10, "tier": "strong_gale", "speed": 1.10, "critical": 0.08, "time": 0.0, "energy": 0, "aura": false},
		{"combo": 14, "tier": "strong_gale", "speed": 1.10, "critical": 0.08, "time": 0.0, "energy": 0, "aura": false},
		{"combo": 15, "tier": "raging_gale", "speed": 1.15, "critical": 0.12, "time": 0.0, "energy": 1, "aura": false},
		{"combo": 19, "tier": "raging_gale", "speed": 1.15, "critical": 0.12, "time": 0.0, "energy": 1, "aura": false},
		{"combo": 20, "tier": "storm", "speed": 1.20, "critical": 0.15, "time": 0.10, "energy": 2, "aura": false},
		{"combo": 29, "tier": "storm", "speed": 1.20, "critical": 0.15, "time": 0.10, "energy": 2, "aura": false},
		{"combo": 30, "tier": "time_storm", "speed": 1.25, "critical": 0.20, "time": 0.20, "energy": 3, "aura": true},
	]
	for case: Dictionary in cases:
		var state = GauntletsComboStateScript.new()
		if int(case["combo"]) > 0:
			state.record_hit(100 + int(case["combo"]), 100 + int(case["combo"]), 9000 + int(case["combo"]), int(case["combo"]), true)
		var tier: Dictionary = state.tier_snapshot()
		_suite.assert_equal(tier.get("tier_id"), case["tier"], "Combo %d resolves tier" % int(case["combo"]))
		_suite.assert_close(float(tier.get("attack_speed_multiplier", 0.0)), float(case["speed"]), "Combo %d resolves attack speed" % int(case["combo"]))
		_suite.assert_close(float(tier.get("critical_chance_bonus", -1.0)), float(case["critical"]), "Combo %d resolves critical bonus" % int(case["combo"]))
		_suite.assert_close(float(tier.get("time_damage_ratio", -1.0)), float(case["time"]), "Combo %d resolves time damage" % int(case["combo"]))
		_suite.assert_equal(tier.get("energy_return"), case["energy"], "Combo %d resolves energy return" % int(case["combo"]))
		_suite.assert_equal(bool((tier.get("slow_aura", {}) as Dictionary).get("enabled", false)), bool(case["aura"]), "Combo %d resolves slow aura" % int(case["combo"]))


func _test_snapshot_restore_and_bounded_ledger() -> void:
	var state = GauntletsComboStateScript.new()
	for token: int in range(1, 301):
		state.record_hit(token, token, 10000 + token, 1, true)
	var snapshot: Dictionary = state.snapshot()
	_suite.assert_equal((snapshot.get("hit_targets_by_token", {}) as Dictionary).size(), 256, "hit ledger is bounded to two hundred fifty-six actions")
	_suite.assert_true(int(snapshot.get("action_token_floor", 0)) >= 44, "bounded ledger advances a stale-token floor")
	_suite.assert_equal(state.record_hit(1, 1, 12000, 1, true).get("code"), &"STALE_ACTION_TOKEN", "pruned action token cannot re-enter the ledger")
	var restored = GauntletsComboStateScript.new()
	_suite.assert_true(restored.restore_snapshot(snapshot), "valid Combo snapshot restores")
	_suite.assert_equal(restored.snapshot(), snapshot, "snapshot restore is deterministic")
	var corrupt := snapshot.duplicate(true)
	corrupt["chain_step"] = 5
	_suite.assert_true(not restored.restore_snapshot(corrupt), "out-of-range chain snapshot fails closed")
	_suite.assert_equal(restored.snapshot(), snapshot, "rejected snapshot preserves prior state")
	state.reset(&"run_terminal")
	_suite.assert_equal(state.snapshot().get("chain_step"), 0, "full reset clears chain")
	_suite.assert_equal(state.snapshot().get("combo_count"), 0, "full reset clears Combo")
	_suite.assert_equal(state.snapshot().get("hit_targets_by_token"), {}, "full reset clears hit ledger")
