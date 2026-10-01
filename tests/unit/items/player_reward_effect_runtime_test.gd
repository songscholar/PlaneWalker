extends Node

const PlayerRewardEffectRuntimeScript := preload(
	"res://scripts/items/player_reward_effect_runtime.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class FakeReport extends RefCounted:
	var blocking: bool = false


	func _init(has_blocking_errors_value: bool = false) -> void:
		blocking = has_blocking_errors_value


	func has_blocking_errors() -> bool:
		return blocking


class FakeCatalog extends RefCounted:
	var descriptors: Dictionary = {}


	func _init(source: Dictionary) -> void:
		descriptors = source.duplicate(true)


	func validate_effects(effects: Variant, _context: Dictionary) -> RefCounted:
		if not effects is Dictionary or (effects as Dictionary).is_empty():
			return FakeReport.new(true)
		for effect_id_value: Variant in (effects as Dictionary).keys():
			if not descriptors.has(str(effect_id_value)):
				return FakeReport.new(true)
			var value: Variant = (effects as Dictionary)[effect_id_value]
			if typeof(value) not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
				return FakeReport.new(true)
			if typeof(value) in [TYPE_INT, TYPE_FLOAT] and not is_finite(float(value)):
				return FakeReport.new(true)
		return FakeReport.new(false)


	func normalize_effects(effects: Variant) -> Dictionary:
		if not effects is Dictionary:
			return {}
		var ids: Array[String] = []
		for effect_id_value: Variant in (effects as Dictionary).keys():
			var effect_id := str(effect_id_value)
			if not descriptors.has(effect_id):
				return {}
			ids.append(effect_id)
		ids.sort()
		var normalized: Dictionary = {}
		for effect_id: String in ids:
			normalized[effect_id] = (effects as Dictionary)[effect_id]
		return normalized


	func effect_descriptor(effect_id: StringName) -> Dictionary:
		var descriptor_value: Variant = descriptors.get(str(effect_id), {})
		return (
			(descriptor_value as Dictionary).duplicate(true)
			if descriptor_value is Dictionary
			else {}
		)


class FakePlayer extends Node:
	var state: Dictionary = {
		"generation": 1,
		"effects": [],
		"domains": {},
	}
	var attempted_effect_ids: Array[String] = []
	var fail_effect_id: String = ""
	var fail_restore: bool = false
	var restore_count: int = 0


	func reward_effect_snapshot() -> Dictionary:
		return state.duplicate(true)


	func restore_reward_effect_snapshot(value: Dictionary) -> bool:
		restore_count += 1
		if fail_restore:
			return false
		state = value.duplicate(true)
		return state == value


	func reward_effect_apply_operation(operation: Dictionary) -> Dictionary:
		var effect_id := str(operation.get("effect_id", ""))
		var runtime_domain := str(operation.get("runtime_domain", ""))
		attempted_effect_ids.append(effect_id)
		var effects := state.get("effects", []) as Array
		effects.append(effect_id)
		state["effects"] = effects
		var domains := state.get("domains", {}) as Dictionary
		domains[runtime_domain] = operation.get("value")
		state["domains"] = domains
		if effect_id == fail_effect_id:
			return {"ok": false, "code": &"INJECTED_OPERATION_FAILURE"}
		return {"ok": true, "code": &"OK"}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_prepare_is_deterministic_and_domain_ordered(suite)
	_test_prepare_rejects_invalid_definition_and_missing_domain(suite)
	_test_commit_rejects_snapshot_drift_and_digest_tampering(suite)
	_test_persistent_failure_restores_exact_snapshot(suite)
	_test_trigger_failure_restores_exact_snapshot(suite)
	_test_rollback_failure_is_reported(suite)
	_test_explicit_rollback_restores_exact_snapshot(suite)
	_test_prepare_and_receipt_are_deep_copies(suite)
	_test_real_catalog_descriptors_prepare_a_plan(suite)
	suite.finish(get_tree())


func _test_prepare_is_deterministic_and_domain_ordered(suite) -> void:
	var runtime = PlayerRewardEffectRuntimeScript.new(_catalog())
	var snapshot := _snapshot()
	var first_definition := _definition({
		"trigger_effect": 6.0,
		"character_effect": 5.0,
		"weapon_effect": 4.0,
		"time_effect": 3.0,
		"health_effect": 2.0,
		"stats_effect": 1.0,
	})
	var second_definition := _definition({
		"health_effect": 2.0,
		"stats_effect": 1.0,
		"trigger_effect": 6.0,
		"weapon_effect": 4.0,
		"character_effect": 5.0,
		"time_effect": 3.0,
	})
	var first: Dictionary = runtime.prepare(first_definition, snapshot)
	var second: Dictionary = runtime.prepare(second_definition, snapshot)
	suite.assert_true(bool(first.get("ok", false)), "first deterministic plan prepares")
	suite.assert_true(bool(second.get("ok", false)), "second deterministic plan prepares")
	var first_plan: Dictionary = first.get("plan", {})
	var second_plan: Dictionary = second.get("plan", {})
	suite.assert_equal(first_plan.get("digest"), second_plan.get("digest"), "source key order does not change plan digest")
	var ordered_ids: Array[String] = []
	var ordered_domains: Array[String] = []
	for operation_value: Variant in first_plan.get("operations", []):
		var operation := operation_value as Dictionary
		ordered_ids.append(str(operation.get("effect_id", "")))
		ordered_domains.append(str(operation.get("runtime_domain", "")))
	suite.assert_equal(
		ordered_ids,
		[
			"stats_effect", "health_effect", "time_effect",
			"weapon_effect", "character_effect", "trigger_effect",
		],
		"operations follow stable domain order"
	)
	suite.assert_equal(
		ordered_domains,
		["stats", "health", "time", "weapon", "character", "trigger"],
		"every operation preserves its catalog runtime domain"
	)


func _test_prepare_rejects_invalid_definition_and_missing_domain(suite) -> void:
	var runtime = PlayerRewardEffectRuntimeScript.new(_catalog())
	var missing_id: Dictionary = runtime.prepare({
		"category": "item",
		"effects": {"stats_effect": 1.0},
	}, _snapshot())
	suite.assert_equal(missing_id.get("code"), &"INVALID_DEFINITION", "definition id is required")
	var unknown_effect: Dictionary = runtime.prepare(
		_definition({"unknown_effect": 1.0}),
		_snapshot()
	)
	suite.assert_equal(unknown_effect.get("code"), &"INVALID_EFFECTS", "unknown effects fail catalog validation")

	var missing_domain_catalog := _catalog()
	missing_domain_catalog.descriptors["stats_effect"].erase("runtime_domain")
	var missing_domain_runtime = PlayerRewardEffectRuntimeScript.new(missing_domain_catalog)
	var missing_domain: Dictionary = missing_domain_runtime.prepare(
		_definition({"stats_effect": 1.0}),
		_snapshot()
	)
	suite.assert_equal(missing_domain.get("code"), &"MISSING_RUNTIME_DOMAIN", "catalog entries require runtime domains")


func _test_commit_rejects_snapshot_drift_and_digest_tampering(suite) -> void:
	var runtime = PlayerRewardEffectRuntimeScript.new(_catalog())
	var player := FakePlayer.new()
	var prepared: Dictionary = runtime.prepare(_definition({"stats_effect": 1.0}), player.reward_effect_snapshot())
	player.state["generation"] = 2
	var stale: Dictionary = runtime.commit(prepared.get("plan", {}), player)
	suite.assert_equal(stale.get("code"), &"STALE_PLAYER_SNAPSHOT", "commit rejects player snapshot drift")
	suite.assert_true(player.attempted_effect_ids.is_empty(), "stale plan applies no operation")

	player.state["generation"] = 1
	var tampered_plan: Dictionary = (prepared.get("plan", {}) as Dictionary).duplicate(true)
	(tampered_plan["operations"][0] as Dictionary)["value"] = 99.0
	var tampered: Dictionary = runtime.commit(tampered_plan, player)
	suite.assert_equal(tampered.get("code"), &"INVALID_PLAN", "digest tampering is rejected")
	suite.assert_true(player.attempted_effect_ids.is_empty(), "tampered plan applies no operation")
	player.free()


func _test_persistent_failure_restores_exact_snapshot(suite) -> void:
	var runtime = PlayerRewardEffectRuntimeScript.new(_catalog())
	var player := FakePlayer.new()
	player.fail_effect_id = "time_effect"
	var before := player.reward_effect_snapshot()
	var prepared: Dictionary = runtime.prepare(_definition({
		"stats_effect": 1.0,
		"health_effect": 2.0,
		"time_effect": 3.0,
		"trigger_effect": 6.0,
	}), before)
	var committed: Dictionary = runtime.commit(prepared.get("plan", {}), player)
	suite.assert_equal(committed.get("code"), &"COMMIT_FAILED_ROLLED_BACK", "persistent failure reports compensated commit")
	suite.assert_equal(player.reward_effect_snapshot(), before, "persistent failure restores exact player snapshot")
	suite.assert_equal(player.restore_count, 1, "persistent failure restores once")
	suite.assert_equal(
		player.attempted_effect_ids,
		["stats_effect", "health_effect", "time_effect"],
		"commit stops at the failed persistent operation"
	)
	player.free()


func _test_trigger_failure_restores_exact_snapshot(suite) -> void:
	var runtime = PlayerRewardEffectRuntimeScript.new(_catalog())
	var player := FakePlayer.new()
	player.fail_effect_id = "trigger_effect"
	var before := player.reward_effect_snapshot()
	var prepared: Dictionary = runtime.prepare(_definition({
		"stats_effect": 1.0,
		"weapon_effect": 4.0,
		"character_effect": 5.0,
		"trigger_effect": 6.0,
	}), before)
	var committed: Dictionary = runtime.commit(prepared.get("plan", {}), player)
	suite.assert_equal(committed.get("code"), &"COMMIT_FAILED_ROLLED_BACK", "trigger failure reports compensated commit")
	suite.assert_equal(player.reward_effect_snapshot(), before, "trigger failure restores persistent and trigger mutations")
	suite.assert_equal(
		player.attempted_effect_ids,
		["stats_effect", "weapon_effect", "character_effect", "trigger_effect"],
		"trigger runs only after persistent domains"
	)
	player.free()


func _test_rollback_failure_is_reported(suite) -> void:
	var runtime = PlayerRewardEffectRuntimeScript.new(_catalog())
	var player := FakePlayer.new()
	player.fail_effect_id = "health_effect"
	player.fail_restore = true
	var prepared: Dictionary = runtime.prepare(_definition({
		"stats_effect": 1.0,
		"health_effect": 2.0,
	}), player.reward_effect_snapshot())
	var committed: Dictionary = runtime.commit(prepared.get("plan", {}), player)
	suite.assert_equal(committed.get("code"), &"ROLLBACK_FAILED", "failed compensation is explicit")
	suite.assert_true(not player.reward_effect_snapshot().get("effects", []).is_empty(), "rollback failure is not reported as restored")
	player.free()


func _test_explicit_rollback_restores_exact_snapshot(suite) -> void:
	var runtime = PlayerRewardEffectRuntimeScript.new(_catalog())
	var player := FakePlayer.new()
	var before := player.reward_effect_snapshot()
	var prepared: Dictionary = runtime.prepare(_definition({
		"stats_effect": 1.0,
		"trigger_effect": 6.0,
	}), before)
	var committed: Dictionary = runtime.commit(prepared.get("plan", {}), player)
	suite.assert_true(bool(committed.get("ok", false)), "plan commits before explicit rollback")
	suite.assert_true(player.reward_effect_snapshot() != before, "successful commit changes player snapshot")
	var rolled_back: Dictionary = runtime.rollback(committed.get("receipt", {}), player)
	suite.assert_true(bool(rolled_back.get("ok", false)), "explicit rollback succeeds")
	suite.assert_equal(player.reward_effect_snapshot(), before, "explicit rollback restores exact pre-commit snapshot")
	player.free()


func _test_prepare_and_receipt_are_deep_copies(suite) -> void:
	var runtime = PlayerRewardEffectRuntimeScript.new(_catalog())
	var player := FakePlayer.new()
	var definition := _definition({"stats_effect": 1.0})
	var snapshot := player.reward_effect_snapshot()
	var prepared: Dictionary = runtime.prepare(definition, snapshot)
	definition["effects"]["stats_effect"] = 9.0
	snapshot["domains"]["forged"] = true
	var plan := prepared.get("plan", {}) as Dictionary
	suite.assert_equal((plan["operations"][0] as Dictionary).get("value"), 1.0, "plan is isolated from definition mutation")
	suite.assert_true(not (plan["player_snapshot"] as Dictionary)["domains"].has("forged"), "plan is isolated from snapshot mutation")

	var committed: Dictionary = runtime.commit(plan, player)
	var receipt := committed.get("receipt", {}) as Dictionary
	var player_after := player.reward_effect_snapshot()
	(receipt["after_snapshot"] as Dictionary)["generation"] = 999
	suite.assert_equal(player.reward_effect_snapshot(), player_after, "receipt mutation cannot mutate player state")
	player.free()


func _test_real_catalog_descriptors_prepare_a_plan(suite) -> void:
	var runtime = PlayerRewardEffectRuntimeScript.new()
	var prepared: Dictionary = runtime.prepare({
		"id": "fixture_real_catalog_reward",
		"category": "item",
		"effects": {
			"heal": 10.0,
			"max_hp_bonus": 20.0,
			"time_stop_duration_bonus": 1.0,
		},
	}, _snapshot())
	suite.assert_true(bool(prepared.get("ok", false)), "real catalog prepares known item effects")
	if not bool(prepared.get("ok", false)):
		return
	var domains: Array[String] = []
	for operation_value: Variant in (prepared["plan"] as Dictionary).get("operations", []):
		domains.append(str((operation_value as Dictionary).get("runtime_domain", "")))
	suite.assert_equal(domains, ["stats", "time", "trigger"], "real catalog domains drive operation staging")


func _catalog() -> FakeCatalog:
	return FakeCatalog.new({
		"stats_effect": _descriptor("stats_effect", "stats"),
		"health_effect": _descriptor("health_effect", "health"),
		"time_effect": _descriptor("time_effect", "time"),
		"weapon_effect": _descriptor("weapon_effect", "weapon"),
		"character_effect": _descriptor("character_effect", "character"),
		"trigger_effect": _descriptor("trigger_effect", "trigger", "trigger"),
	})


func _descriptor(effect_id: String, runtime_domain: String, stack_rule: String = "add") -> Dictionary:
	return {
		"effect_id": effect_id,
		"value_type": "number",
		"minimum": 0.0,
		"maximum": 100.0,
		"stack_rule": stack_rule,
		"allowed_categories": ["item"],
		"runtime_domain": runtime_domain,
	}


func _definition(effects: Dictionary) -> Dictionary:
	return {
		"id": "fixture_reward",
		"category": "item",
		"effects": effects.duplicate(true),
	}


func _snapshot() -> Dictionary:
	return {
		"generation": 1,
		"effects": [],
		"domains": {},
	}
