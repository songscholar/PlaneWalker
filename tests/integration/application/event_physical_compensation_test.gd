extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Facade := preload("res://scripts/application/run_runtime_facade.gd")
const Effects := preload("res://scripts/items/player_reward_effect_runtime.gd")
const Result := preload("res://scripts/application/command_result.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const CURSES: Array[String] = [
	"curse_brittle_pact", "curse_empty_veins", "curse_glass_cadence",
]


class RejectingOrchestrator extends RefCounted:
	var base: RefCounted
	var commit_calls := 0

	func snapshot() -> Dictionary:
		return base.call("snapshot").duplicate(true)

	func revision() -> int:
		return int(base.call("revision"))

	func reward_build_participant() -> RefCounted:
		return base.call("reward_build_participant")

	func commit_event_transaction(_candidate: Dictionary, _revision: int):
		commit_calls += 1
		return Result.failure(
			&"STALE_REVISION", revision(), {"stage": "injected_event_commit"}
		)


class PlayerFaultAdapter extends RefCounted:
	var player: Node
	var trace: Array[String] = []
	var effect_preimages: Dictionary = {}
	var effect_restore_fault_id := ""
	var publication_restore_fault := false
	var next_restore_is_health := false
	var health_apply_mode := "ok"
	var health_rollback_mode := "ok"
	var health_before: Dictionary = {}
	var publication_depth := 0

	func reward_effect_snapshot() -> Dictionary:
		return player.call("reward_effect_snapshot").duplicate(true)

	func restore_reward_effect_snapshot(value: Dictionary) -> bool:
		if next_restore_is_health:
			next_restore_is_health = false
			health_before = reward_effect_snapshot()
			trace.append("health_apply")
			if health_apply_mode == "lie":
				return true
			var applied := bool(player.call("restore_reward_effect_snapshot", value, false))
			return applied and health_apply_mode != "partial_failure"
		if not health_before.is_empty() and value == health_before:
			trace.append("health_rollback")
			if health_rollback_mode != "ok":
				return health_rollback_mode == "lie"
		for curse_id: String in effect_preimages:
			if value != effect_preimages[curse_id]:
				continue
			trace.append("curse_rollback:" + curse_id)
			if curse_id == effect_restore_fault_id:
				return false
			break
		return bool(player.call("restore_reward_effect_snapshot", value, false))

	func reward_effect_apply_operation(operation: Dictionary) -> Dictionary:
		return player.call("reward_effect_apply_operation", operation.duplicate(true))

	# Multiple tentative curse effects share the production Player's one publication.
	func reward_effect_begin_publication() -> bool:
		if publication_depth == 0 and not player.call("reward_effect_begin_publication"):
			return false
		publication_depth += 1
		return true

	func reward_effect_publication_can_commit() -> bool:
		return bool(player.call("reward_effect_publication_can_commit"))

	func reward_effect_commit_publication() -> bool:
		publication_depth -= 1
		return publication_depth > 0 or bool(player.call("reward_effect_commit_publication"))

	func reward_effect_rollback_publication() -> bool:
		publication_depth -= 1
		var restored := publication_depth > 0 or bool(player.call("reward_effect_rollback_publication"))
		return restored and not publication_restore_fault


class EffectFaultRuntime extends RefCounted:
	var base := Effects.new()
	var adapter: PlayerFaultAdapter
	var prepare_calls := 0
	var fail_prepare_call := 0

	func prepare(definition: Dictionary, before: Dictionary) -> Dictionary:
		prepare_calls += 1
		adapter.effect_preimages[str(definition["id"])] = before.duplicate(true)
		if prepare_calls == fail_prepare_call:
			return {"ok": false, "code": &"INJECTED_PREPARE_FAILURE"}
		return base.prepare(definition, before)

	func commit(plan: Dictionary, player: Object) -> Dictionary:
		return base.commit(plan, player)

	func rollback(receipt: Dictionary, player: Object) -> Dictionary:
		return base.rollback(receipt, player)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	_test_health_compensation(suite, "ok", "ok", &"STALE_REVISION")
	_test_health_compensation(suite, "ok", "refuse", &"INTEGRITY_FAILURE")
	_test_health_compensation(suite, "ok", "lie", &"INTEGRITY_FAILURE")
	_test_health_compensation(suite, "partial_failure", "ok", &"COMMIT_FAILED")
	_test_health_compensation(suite, "partial_failure", "refuse", &"INTEGRITY_FAILURE")
	_test_health_compensation(suite, "lie", "ok", &"COMMIT_FAILED")
	_test_curse_compensation(suite, true, false, false)
	_test_curse_compensation(suite, true, true, false)
	_test_curse_compensation(suite, false, false, false)
	_test_curse_compensation(suite, false, true, false)
	_test_curse_compensation(suite, false, false, true)
	_test_health_failure_still_compensates_curses(suite)
	await get_tree().process_frame
	suite.finish(get_tree())


func _fixture(suite, suffix: String) -> Dictionary:
	var facade := Facade.new()
	suite.assert_true(facade.boot().ok, "compensation boots real content: " + suffix)
	var run_id := "event-compensation-" + suffix
	var config := {
		"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer",
		"weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal", "seed": 20261004,
	}
	suite.assert_true(facade.start_run(config, run_id).ok, "compensation starts real generated floor")
	var player: Node = PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var loadout: Dictionary = facade.active_loadout()
	config["character_profile"] = loadout["character_profile"]
	config["weapon_profile"] = loadout["weapon_profile"]
	suite.assert_true(player.call("configure_run", StringName(run_id)), "physical Player binds run")
	suite.assert_true(player.call("configure_loadout", config), "physical Player installs production loadout")
	var adapter := PlayerFaultAdapter.new()
	adapter.player = player
	var effects := EffectFaultRuntime.new()
	effects.adapter = adapter
	suite.assert_true(facade.configure_merchant_effect_authority(effects, adapter), "Facade binds production effects through fault adapter")
	var authority: RefCounted = facade.get("_orchestrator")
	var rejecting := RejectingOrchestrator.new()
	rejecting.base = authority
	facade.set("_orchestrator", rejecting)
	return {
		"facade": facade, "player": player, "adapter": adapter, "effects": effects,
		"authority": authority, "rejecting": rejecting,
		"domain_before": authority.call("snapshot").duplicate(true),
		"physical_before": player.call("reward_effect_snapshot").duplicate(true),
	}


func _command(fixture: Dictionary, curses: Array, health_cost: float) -> Dictionary:
	var runtime: RefCounted = fixture["facade"].get("_event_runtime")
	var consequences: RefCounted = runtime.get("_consequences")
	var modifier: RefCounted = consequences.get("_modifier")
	var modifier_state: Dictionary = modifier.call("snapshot")
	modifier_state["curse_ids"] = curses.duplicate()
	modifier_state["curse_ids"].sort()
	assert(modifier.call("restore_snapshot", modifier_state))
	if health_cost > 0.0:
		var health: RefCounted = consequences.get("_health")
		var health_state: Dictionary = health.call("snapshot")
		health_state["current"] = float(health_state["current"]) - health_cost
		assert(health.call("restore_snapshot", health_state))
	var state: Dictionary = runtime.call("snapshot")
	var publication: Dictionary = {}
	for field: String in [
		"emitted_fact_ids", "pending_facts", "encounter_success_by_transaction",
		"publication_ledger", "publication_digest",
	]:
		publication[field] = state[field]
	return {
		"operation": "choose_option" if health_cost > 0.0 else "ack_event_fact",
		"publication_state": publication,
		"event_state": state["consequence_runtime"]["participant_snapshots"]["event_state"],
	}


func _invoke(fixture: Dictionary, command: Dictionary) -> Dictionary:
	return fixture["facade"].call(
		"_commit_event_runtime_state", command, fixture["authority"].call("revision")
	)


func _test_health_compensation(suite, apply_mode: String, rollback_mode: String, expected_code: StringName) -> void:
	var label := "health-" + apply_mode + "-" + rollback_mode
	var fixture := _fixture(suite, label)
	var adapter: PlayerFaultAdapter = fixture["adapter"]
	adapter.next_restore_is_health = true
	adapter.health_apply_mode = apply_mode
	adapter.health_rollback_mode = rollback_mode
	var result := _invoke(fixture, _command(fixture, [], 10.0))
	suite.assert_equal(result["code"], expected_code, label + " reports compensation outcome")
	suite.assert_equal(adapter.trace, ["health_apply", "health_rollback"], label + " always attempts physical health compensation")
	suite.assert_equal(fixture["rejecting"].commit_calls, 1 if apply_mode == "ok" else 0, label + " validates physical application before domain commit")
	suite.assert_equal(fixture["authority"].call("snapshot"), fixture["domain_before"], label + " preserves domain state and revision")
	if rollback_mode == "ok":
		suite.assert_equal(adapter.reward_effect_snapshot(), fixture["physical_before"], label + " restores exact physical Player preimage")
	else:
		suite.assert_true(adapter.reward_effect_snapshot() != fixture["physical_before"], label + " exposes unresolved physical divergence")
	fixture["player"].queue_free()


func _test_curse_compensation(suite, fail_prepare: bool, fail_restore: bool, fail_publication: bool) -> void:
	var label := "curses-%s-%s-%s" % [fail_prepare, fail_restore, fail_publication]
	var fixture := _fixture(suite, label)
	var adapter: PlayerFaultAdapter = fixture["adapter"]
	if fail_prepare:
		fixture["effects"].fail_prepare_call = 3
	if fail_restore:
		adapter.effect_restore_fault_id = CURSES[1]
	adapter.publication_restore_fault = fail_publication
	var result := _invoke(fixture, _command(fixture, CURSES, 0.0))
	var expected := &"COMMIT_FAILED" if fail_prepare else &"STALE_REVISION"
	if fail_restore or fail_publication:
		expected = &"INTEGRITY_FAILURE"
	suite.assert_equal(result["code"], expected, label + " preserves original error only after complete compensation")
	suite.assert_equal(adapter.trace, [
		"curse_rollback:" + CURSES[2],
		"curse_rollback:" + CURSES[1],
		"curse_rollback:" + CURSES[0],
	], label + " compensates latest effect first and attempts every participant")
	suite.assert_equal(adapter.reward_effect_snapshot(), fixture["physical_before"], label + " remaining compensation restores original Player")
	suite.assert_equal(adapter.publication_depth, 0, label + " closes every publication participant")
	suite.assert_equal(fixture["authority"].call("snapshot"), fixture["domain_before"], label + " preserves complete domain state")
	fixture["player"].queue_free()


func _test_health_failure_still_compensates_curses(suite) -> void:
	var fixture := _fixture(suite, "health-and-curses")
	var adapter: PlayerFaultAdapter = fixture["adapter"]
	adapter.next_restore_is_health = true
	adapter.health_apply_mode = "partial_failure"
	adapter.health_rollback_mode = "refuse"
	var result := _invoke(fixture, _command(fixture, [CURSES[0], CURSES[1]], 10.0))
	suite.assert_equal(result["code"], &"INTEGRITY_FAILURE", "health compensation failure remains integrity failure after curse restoration")
	suite.assert_equal(adapter.trace, [
		"health_apply", "health_rollback",
		"curse_rollback:" + CURSES[1], "curse_rollback:" + CURSES[0],
	], "failed health compensation still attempts both curse participants in reverse order")
	suite.assert_equal(adapter.reward_effect_snapshot(), fixture["physical_before"], "earlier effect preimages remain recoverable after refused health restore")
	suite.assert_equal(adapter.publication_depth, 0, "health failure closes curse publications")
	fixture["player"].queue_free()
