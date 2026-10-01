extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ActiveItemRuntimeScript := preload("res://scripts/items/active_item_runtime.gd")

const DEFINITIONS := {
	"absolute_zero": ["absolute_zero_device", "freeze_burst", {
		"radius": 180.0,
		"duration_frames": 180,
		"weakpoint_bonus": 0.5,
		"energy_cost": 35.0,
	}],
	"paradox_beacon": ["paradox_beacon", "rewind_echo", {
		"rewind_frames": 180,
		"echo_damage_multiplier": 0.8,
		"energy_cost": 30.0,
	}],
	"gravity_snare": ["gravity_snare_device", "rift_trap", {
		"radius": 220.0,
		"duration_frames": 240,
		"slow_ratio": 0.45,
		"energy_cost": 35.0,
	}],
	"redline_injector": ["redline_injector", "accelerated_combo", {
		"duration_frames": 240,
		"speed_multiplier": 1.5,
		"health_cost_ratio": 0.12,
	}],
	"blood_price": ["blood_price_relic", "low_hp_void", {
		"duration_frames": 240,
		"damage_multiplier": 1.8,
		"health_cost_ratio": 0.18,
	}],
	"aegis_reversal": ["aegis_reversal", "perfect_guard", {
		"duration_frames": 180,
		"counter_multiplier": 1.5,
		"energy_cost": 25.0,
	}],
	"railshot": ["railshot_module", "piercing_barrage", {
		"pierce_bonus": 4,
		"damage_multiplier": 1.6,
		"ammo_refund": 2,
	}],
	"army_of_yesterday": ["army_of_yesterday", "echo_legion", {
		"echo_count": 3,
		"duration_frames": 300,
		"echo_damage_multiplier": 0.45,
		"energy_cost": 40.0,
	}],
}

var _suite


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = TestSuiteScript.new()
	_test_all_handlers_plan_closed_deterministic_payloads()
	_test_invalid_configure_preserves_previous_runtime()
	_test_commit_rejects_tampering_stale_tokens_and_generation()
	_test_commit_is_idempotent_without_restarting_cooldown()
	_test_cooldown_uses_half_open_frame_boundaries()
	_test_snapshot_round_trip_and_invalid_restore_are_atomic()
	_test_reset_invalidates_old_plans_and_clears_runtime_state()
	_suite.finish(get_tree())


func _test_all_handlers_plan_closed_deterministic_payloads() -> void:
	var expected_payload_families := {
		"absolute_zero": "area_weakpoint_exposure",
		"paradox_beacon": "rewind_echo",
		"gravity_snare": "gravity_field",
		"redline_injector": "self_speed_window",
		"blood_price": "self_damage_window",
		"aegis_reversal": "counter_window",
		"railshot": "next_projectile_override",
		"army_of_yesterday": "echo_summon_window",
	}
	var expected_claims := {
		"absolute_zero": {"time_energy": 35.0},
		"paradox_beacon": {"time_energy": 30.0},
		"gravity_snare": {"time_energy": 35.0},
		"redline_injector": {"health": 12.0},
		"blood_price": {"health": 18.0},
		"aegis_reversal": {"time_energy": 25.0},
		"railshot": {"ammo_refund_on_hit": 2},
		"army_of_yesterday": {"time_energy": 40.0},
	}
	for handler_id_value: Variant in DEFINITIONS.keys():
		var handler_id := str(handler_id_value)
		var runtime = ActiveItemRuntimeScript.new()
		_suite.assert_true(runtime.configure(_definition(handler_id)), "%s configures" % handler_id)
		var before: Dictionary = runtime.snapshot()
		var first: Dictionary = runtime.plan_activate(_context(120))
		var second: Dictionary = runtime.plan_activate(_context(120))
		_suite.assert_true(bool(first.get("ok", false)), "%s plans" % handler_id)
		_suite.assert_equal(first, second, "%s planning is deterministic and pure" % handler_id)
		_suite.assert_equal(runtime.snapshot(), before, "%s planning leaves state unchanged" % handler_id)
		var plan: Dictionary = first.get("plan", {})
		_suite.assert_equal(plan.get("handler_id"), handler_id, "%s seals handler identity" % handler_id)
		_suite.assert_equal(plan.get("content_id"), str(DEFINITIONS[handler_id][0]), "%s seals content identity" % handler_id)
		_suite.assert_equal(plan.get("archetype"), str(DEFINITIONS[handler_id][1]), "%s seals archetype" % handler_id)
		_suite.assert_equal(plan.get("runtime_frame"), 120, "%s seals authoritative frame" % handler_id)
		_suite.assert_equal(plan.get("token"), 1, "%s starts with token one" % handler_id)
		_suite.assert_equal(plan.get("generation"), 1, "%s starts with generation one" % handler_id)
		_suite.assert_equal(
			plan.get("resource_claims"),
			expected_claims[handler_id],
			"%s exposes its exact deterministic resource claim" % handler_id
		)
		_suite.assert_equal(
			str((plan.get("payload_descriptor", {}) as Dictionary).get("family", "")),
			expected_payload_families[handler_id],
			"%s exposes its archetype-specific payload" % handler_id
		)
		_suite.assert_true(
			(plan.get("boss_conversion", {}) as Dictionary).get("hard_control", true) == false,
			"%s explicitly forbids Boss hard control" % handler_id
		)


func _test_invalid_configure_preserves_previous_runtime() -> void:
	var runtime = ActiveItemRuntimeScript.new()
	_suite.assert_true(runtime.configure(_definition("absolute_zero")), "valid definition configures")
	var committed: Dictionary = _commit(runtime, 10)
	_suite.assert_true(bool(committed.get("ok", false)), "fixture activation commits")
	var before: Dictionary = runtime.snapshot()
	var invalid := _definition("gravity_snare")
	invalid["active_parameters"]["script_path"] = 1
	_suite.assert_true(not runtime.configure(invalid), "unknown executable-like field rejects")
	_suite.assert_equal(runtime.snapshot(), before, "failed configure preserves equipped runtime exactly")


func _test_commit_rejects_tampering_stale_tokens_and_generation() -> void:
	var runtime = ActiveItemRuntimeScript.new()
	runtime.configure(_definition("paradox_beacon"))
	var prepared: Dictionary = runtime.plan_activate(_context(20))
	var plan: Dictionary = (prepared.get("plan", {}) as Dictionary).duplicate(true)
	plan["payload_descriptor"]["echo_damage_multiplier"] = 99.0
	var before: Dictionary = runtime.snapshot()
	var tampered: Dictionary = runtime.commit_activate(plan, int(plan.get("token", 0)))
	_suite.assert_true(not bool(tampered.get("ok", true)), "tampered plan rejects")
	_suite.assert_equal(tampered.get("code"), &"PLAN_TAMPERED", "tampering is typed")
	_suite.assert_equal(runtime.snapshot(), before, "tampered plan leaves state unchanged")

	var valid_plan: Dictionary = prepared.get("plan", {})
	var wrong_token: Dictionary = runtime.commit_activate(valid_plan, 2)
	_suite.assert_equal(wrong_token.get("code"), &"STALE_TOKEN", "wrong token rejects")
	_suite.assert_equal(runtime.snapshot(), before, "wrong token leaves state unchanged")

	runtime.reset_runtime_state(&"replacement")
	var stale_generation: Dictionary = runtime.commit_activate(valid_plan, 1)
	_suite.assert_equal(stale_generation.get("code"), &"STALE_GENERATION", "pre-reset plan rejects")


func _test_commit_is_idempotent_without_restarting_cooldown() -> void:
	var runtime = ActiveItemRuntimeScript.new()
	runtime.configure(_definition("railshot"))
	var prepared: Dictionary = runtime.plan_activate(_context(50))
	var plan: Dictionary = prepared.get("plan", {})
	var committed: Dictionary = runtime.commit_activate(plan, 1)
	_suite.assert_true(bool(committed.get("ok", false)), "first commit succeeds")
	_suite.assert_equal(runtime.cooldown_remaining(), 900, "commit starts exact cooldown")
	var duplicate: Dictionary = runtime.commit_activate(plan, 1)
	_suite.assert_true(bool(duplicate.get("ok", false)), "identical duplicate is idempotent")
	_suite.assert_equal(duplicate.get("code"), &"ALREADY_COMMITTED", "duplicate is explicit")
	_suite.assert_equal(runtime.cooldown_remaining(), 900, "duplicate does not restart cooldown")
	var rejected: Dictionary = runtime.plan_activate(_context(50))
	_suite.assert_equal(rejected.get("code"), &"COOLDOWN_ACTIVE", "repeat input during cooldown rejects")


func _test_cooldown_uses_half_open_frame_boundaries() -> void:
	var runtime = ActiveItemRuntimeScript.new()
	runtime.configure(_definition("aegis_reversal"))
	_commit(runtime, 100)
	_suite.assert_equal(runtime.cooldown_remaining(), 900, "cooldown includes commit frame")
	var events: Array[Dictionary] = runtime.advance_frame(_context(999))
	_suite.assert_equal(runtime.cooldown_remaining(), 1, "cooldown remains closed before boundary")
	_suite.assert_true(not _has_event(events, "active_item_ready"), "ready does not publish early")
	events = runtime.advance_frame(_context(1000))
	_suite.assert_equal(runtime.cooldown_remaining(), 0, "cooldown opens at exact half-open boundary")
	_suite.assert_true(_has_event(events, "active_item_ready"), "ready publishes once at boundary")
	_suite.assert_true(bool(runtime.plan_activate(_context(1000)).get("ok", false)), "boundary frame may plan again")


func _test_snapshot_round_trip_and_invalid_restore_are_atomic() -> void:
	var runtime = ActiveItemRuntimeScript.new()
	runtime.configure(_definition("army_of_yesterday"))
	_commit(runtime, 30)
	runtime.advance_frame(_context(40))
	var snapshot: Dictionary = runtime.snapshot()
	var restored = ActiveItemRuntimeScript.new()
	_suite.assert_true(restored.can_restore_snapshot(snapshot), "valid snapshot preflights")
	_suite.assert_true(restored.restore_snapshot(snapshot), "valid snapshot restores")
	_suite.assert_equal(restored.snapshot(), snapshot, "snapshot round trip is exact")

	var invalid: Dictionary = snapshot.duplicate(true)
	invalid["cooldown_end_frame"] = 10
	var before: Dictionary = restored.snapshot()
	_suite.assert_true(not restored.can_restore_snapshot(invalid), "inconsistent cooldown rejects preflight")
	_suite.assert_true(not restored.restore_snapshot(invalid), "inconsistent cooldown does not restore")
	_suite.assert_equal(restored.snapshot(), before, "failed restore is atomic")


func _test_reset_invalidates_old_plans_and_clears_runtime_state() -> void:
	var runtime = ActiveItemRuntimeScript.new()
	runtime.configure(_definition("blood_price"))
	var old_plan: Dictionary = runtime.plan_activate(_context(5)).get("plan", {})
	_commit(runtime, 5)
	var configured_before: Dictionary = runtime.snapshot().get("definition", {})
	runtime.reset_runtime_state(&"run_restart")
	var snapshot: Dictionary = runtime.snapshot()
	_suite.assert_equal(snapshot.get("definition"), configured_before, "reset preserves equipped definition")
	_suite.assert_equal(snapshot.get("cooldown_end_frame"), -1, "reset clears cooldown")
	_suite.assert_equal(snapshot.get("handler_state"), {}, "reset clears handler state")
	_suite.assert_equal(snapshot.get("generation"), 2, "reset advances generation")
	_suite.assert_equal(snapshot.get("next_token"), 1, "reset restarts token ledger")
	_suite.assert_equal(
		runtime.commit_activate(old_plan, 1).get("code"),
		&"STALE_GENERATION",
		"reset invalidates pre-reset plans"
	)


func _definition(handler_id: String) -> Dictionary:
	var fixture: Array = DEFINITIONS[handler_id]
	return {
		"id": str(fixture[0]),
		"category": "item",
		"availability": ["LAUNCH", "EXPANSION"],
		"name_key": "%s_NAME" % str(fixture[0]).to_upper(),
		"description_key": "%s_DESC" % str(fixture[0]).to_upper(),
		"tags": ["active", "risk", str(fixture[1])],
		"compatibility": {"archetype_ids": [str(fixture[1])]},
		"effects": {},
		"kind": "time",
		"archetype": str(fixture[1]),
		"role": "risk",
		"rarity": "rare",
		"icon_id": "content_%s" % str(fixture[0]),
		"item_mode": "active",
		"active_handler_id": handler_id,
		"cooldown_frames": 900,
		"active_parameters": (fixture[2] as Dictionary).duplicate(true),
	}


func _context(runtime_frame: int) -> Dictionary:
	return {
		"runtime_frame": runtime_frame,
		"energy_current": 100.0,
		"health_current": 100.0,
		"health_maximum": 100.0,
		"is_boss_target": true,
	}


func _commit(runtime, runtime_frame: int) -> Dictionary:
	var prepared: Dictionary = runtime.plan_activate(_context(runtime_frame))
	if not bool(prepared.get("ok", false)):
		return prepared
	var plan: Dictionary = prepared.get("plan", {})
	return runtime.commit_activate(plan, int(plan.get("token", 0)))


func _has_event(events: Array[Dictionary], event_type: String) -> bool:
	for event: Dictionary in events:
		if str(event.get("type", "")) == event_type:
			return true
	return false
