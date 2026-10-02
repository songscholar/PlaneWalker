extends Node

const AuthorityScript := preload(
	"res://scripts/economy/reward_build_mutation_authority.gd"
)
const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class FakePlayer extends RefCounted:
	var state: Dictionary = {"value": 10.0, "history": []}
	var fail_next_restore: bool = false
	var publication_active: bool = false


	func reward_effect_snapshot() -> Dictionary:
		return state.duplicate(true)


	func restore_reward_effect_snapshot(value: Dictionary) -> bool:
		state = value.duplicate(true)
		if fail_next_restore:
			fail_next_restore = false
			return false
		return true


	func reward_effect_apply_operation(operation: Dictionary) -> Dictionary:
		var amount := float(operation.get("value", 0.0))
		match str(operation.get("effect_id", "")):
			"add":
				state["value"] = float(state["value"]) + amount
			"multiply":
				state["value"] = float(state["value"]) * amount
			_:
				return {"ok": false, "code": &"UNKNOWN_EFFECT"}
		(state["history"] as Array).append(str(operation["effect_id"]))
		return {"ok": true, "code": &"OK"}


	func reward_effect_begin_publication() -> bool:
		if publication_active:
			return false
		publication_active = true
		return true


	func reward_effect_rollback_publication() -> bool:
		if not publication_active:
			return false
		publication_active = false
		return true


class FakeRewardRuntime extends RefCounted:
	func prepare(definition: Dictionary, player_snapshot: Dictionary) -> Dictionary:
		var effects := definition.get("effects", {}) as Dictionary
		if effects.size() != 1:
			return {"ok": false, "code": &"INVALID_EFFECTS"}
		var effect_id := str(effects.keys()[0])
		return {
			"ok": true,
			"plan": {
				"definition_id": str(definition.get("id", "")),
				"player_snapshot": player_snapshot.duplicate(true),
				"operation": {"effect_id": effect_id, "value": effects[effect_id]},
			},
		}


	func commit(plan: Dictionary, player: Object) -> Dictionary:
		if player.call("reward_effect_snapshot") != plan.get("player_snapshot", {}):
			return {"ok": false, "code": &"STALE_PLAYER_SNAPSHOT"}
		var before: Dictionary = player.call("reward_effect_snapshot")
		var applied: Dictionary = player.call(
			"reward_effect_apply_operation",
			(plan.get("operation", {}) as Dictionary).duplicate(true)
		)
		if not bool(applied.get("ok", false)):
			player.call("restore_reward_effect_snapshot", before)
			return applied
		return {
			"ok": true,
			"receipt": {
				"before": before,
				"after": player.call("reward_effect_snapshot"),
			},
		}


	func rollback(receipt: Dictionary, player: Object) -> Dictionary:
		if player.call("reward_effect_snapshot") != receipt.get("after", {}):
			return {"ok": false, "code": &"STALE_PLAYER_SNAPSHOT"}
		return {
			"ok": bool(player.call(
				"restore_reward_effect_snapshot",
				(receipt.get("before", {}) as Dictionary).duplicate(true)
			)),
		}


class FailingBuildParticipant extends RefCounted:
	var state: Dictionary = {}
	var fail_next_restore: bool = false


	func _init(initial: Dictionary) -> void:
		state = initial.duplicate(true)


	func transaction_snapshot() -> Dictionary:
		return state.duplicate(true)


	func can_restore_transaction_snapshot(value: Dictionary) -> bool:
		return not value.is_empty()


	func restore_transaction_snapshot(value: Dictionary) -> bool:
		state = value.duplicate(true)
		if fail_next_restore:
			fail_next_restore = false
			return false
		return true


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_remove_first_middle_and_last_preserves_order(suite)
	_test_remove_preserves_external_runtime_overlay(suite)
	_test_category_and_owned_guards(suite)
	_test_stale_prepare_and_commit_failure_are_atomic(suite)
	_test_snapshot_restore_preserves_duplicate_ids_and_ledger(suite)
	suite.finish(get_tree())


func _test_remove_first_middle_and_last_preserves_order(suite) -> void:
	var cases: Array[Dictionary] = [
		{"id": "item_add", "expected": 23.0},
		{"id": "blessing_multiply", "expected": 18.0},
		{"id": "curse_add", "expected": 30.0},
	]
	for case: Dictionary in cases:
		var fixture := _fixture(_ledger())
		var prepared: Dictionary = fixture.authority.prepare_remove(
			"remove_%s" % str(case["id"]),
			str(case["id"]),
			["item", "blessing", "curse"]
		)
		suite.assert_true(bool(prepared.get("ok", false)), "%s prepares" % str(case["id"]))
		suite.assert_equal(
			fixture.player.reward_effect_snapshot(),
			fixture.before_player,
			"%s prepare has zero lasting player side effects" % str(case["id"])
		)
		var committed: Dictionary = fixture.authority.commit_remove(prepared.get("ticket", {}))
		suite.assert_true(bool(committed.get("ok", false)), "%s commits" % str(case["id"]))
		suite.assert_close(
			float(fixture.player.state["value"]),
			float(case["expected"]),
			"%s is rebuilt from baseline in acquisition order" % str(case["id"])
		)
		suite.assert_true(
			not fixture.build.selected_ids().has(str(case["id"])),
			"%s leaves the authoritative build" % str(case["id"])
		)
		var rolled_back: Dictionary = fixture.authority.rollback_remove(committed.get("receipt", {}))
		suite.assert_true(bool(rolled_back.get("ok", false)), "%s rolls back" % str(case["id"]))
		suite.assert_equal(fixture.player.reward_effect_snapshot(), fixture.before_player, "rollback restores player exactly")
		suite.assert_equal(fixture.build.transaction_snapshot(), fixture.before_build, "rollback restores build exactly")


func _test_remove_preserves_external_runtime_overlay(suite) -> void:
	var ledger: Array[Dictionary] = [_definition("item_add", "item", "add", 5.0)]
	var fixture := _fixture(ledger)
	fixture.player.state["value"] = 12.0
	(fixture.player.state["history"] as Array).append("runtime_heal")
	var synchronized: Dictionary = fixture.authority.synchronize_live_state(
		ledger,
		fixture.build.transaction_snapshot()
	)
	suite.assert_true(bool(synchronized.get("ok", false)), "external runtime state synchronizes")
	var prepared: Dictionary = fixture.authority.prepare_remove(
		"remove_with_runtime_overlay",
		"item_add",
		["item"]
	)
	suite.assert_true(bool(prepared.get("ok", false)), "overlay removal prepares")
	var committed: Dictionary = fixture.authority.commit_remove(prepared.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "overlay removal commits")
	suite.assert_close(
		float(fixture.player.state["value"]),
		7.0,
		"removing the reward preserves the external numeric delta"
	)
	suite.assert_equal(
		fixture.player.state["history"],
		["runtime_heal"],
		"removing the reward preserves runtime-only history"
	)
	var rolled_back: Dictionary = fixture.authority.rollback_remove(
		committed.get("receipt", {})
	)
	suite.assert_true(bool(rolled_back.get("ok", false)), "overlay removal rolls back")
	suite.assert_close(
		float(fixture.player.state["value"]),
		12.0,
		"overlay rollback restores the exact live numeric state"
	)
	suite.assert_equal(
		fixture.player.state["history"],
		["add", "runtime_heal"],
		"overlay rollback restores the exact live history"
	)


func _test_category_and_owned_guards(suite) -> void:
	var ledger := _ledger()
	ledger.append(_definition("active_item", "item", "add", 1.0, "active"))
	ledger.append(_definition("talent_reward", "talent", "add", 1.0))
	var fixture := _fixture(ledger)
	suite.assert_equal(
		fixture.authority.prepare_remove("missing", "not_owned", ["item"]).get("code"),
		&"REWARD_NOT_OWNED",
		"unowned rewards reject"
	)
	suite.assert_equal(
		fixture.authority.prepare_remove("wrong_category", "curse_add", ["item"]).get("code"),
		&"CATEGORY_NOT_ALLOWED",
		"caller category allowlist is authoritative"
	)
	suite.assert_equal(
		fixture.authority.prepare_remove("active", "active_item", ["item"]).get("code"),
		&"ACTIVE_ITEM_UNSUPPORTED",
		"active items cannot be sold"
	)
	suite.assert_equal(
		fixture.authority.prepare_remove("talent", "talent_reward", ["talent"]).get("code"),
		&"TALENT_UNSUPPORTED",
		"talents cannot be removed"
	)


func _test_stale_prepare_and_commit_failure_are_atomic(suite) -> void:
	var stale := _fixture(_ledger())
	stale.player.state["value"] = 999.0
	var stale_result: Dictionary = stale.authority.prepare_remove("stale_player", "curse_add", ["curse"])
	suite.assert_equal(stale_result.get("code"), &"STALE_PLAYER_SNAPSHOT", "prepare rejects player drift")
	suite.assert_close(float(stale.player.state["value"]), 999.0, "stale rejection does not overwrite live player")
	var stale_build := _fixture(_ledger())
	stale_build.build.apply_definition(_definition("late_item", "item", "add", 1.0))
	var stale_build_result: Dictionary = stale_build.authority.prepare_remove(
		"stale_build",
		"curse_add",
		["curse"]
	)
	suite.assert_equal(
		stale_build_result.get("code"),
		&"STALE_BUILD_SNAPSHOT",
		"prepare rejects build drift"
	)

	var fixture := _fixture(_ledger(), true)
	var prepared: Dictionary = fixture.authority.prepare_remove("fail_build", "blessing_multiply", ["blessing"])
	fixture.build.fail_next_restore = true
	var committed: Dictionary = fixture.authority.commit_remove(prepared.get("ticket", {}))
	suite.assert_equal(committed.get("code"), &"COMMIT_FAILED_ROLLED_BACK", "build install failure is compensated")
	suite.assert_equal(fixture.player.reward_effect_snapshot(), fixture.before_player, "failed commit restores exact player")
	suite.assert_equal(fixture.build.transaction_snapshot(), fixture.before_build, "failed commit restores exact build")


func _test_snapshot_restore_preserves_duplicate_ids_and_ledger(suite) -> void:
	var fixture := _fixture(_ledger())
	var prepared: Dictionary = fixture.authority.prepare_remove("persisted_remove", "curse_add", ["curse"])
	var committed: Dictionary = fixture.authority.commit_remove(prepared.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "persisted removal commits")
	var saved: Dictionary = fixture.authority.snapshot()
	suite.assert_equal((saved.get("definition_ledger", []) as Array).size(), 2, "snapshot stores remaining definition ledger")

	var restored = AuthorityScript.new()
	var configured: Dictionary = restored.configure(
		saved.get("run_start_player_baseline", {}),
		saved.get("definition_ledger", []),
		fixture.build.transaction_snapshot(),
		fixture.build,
		fixture.player,
		FakeRewardRuntime.new()
	)
	suite.assert_true(bool(configured.get("ok", false)), "restore target configures from saved authority inputs")
	suite.assert_true(restored.can_restore_snapshot(saved), "authority snapshot validates")
	suite.assert_true(restored.restore_snapshot(saved), "authority snapshot restores")
	suite.assert_equal(
		restored.prepare_remove("persisted_remove", "item_add", ["item"]).get("code"),
		&"DUPLICATE_TRANSACTION",
		"restored completed transaction cannot replay"
	)


func _fixture(ledger: Array[Dictionary], failing_build: bool = false) -> Dictionary:
	var build = RunBuildStateScript.new()
	build.reset("LAUNCH")
	var player := FakePlayer.new()
	var runtime := FakeRewardRuntime.new()
	for definition: Dictionary in ledger:
		build.apply_definition(definition)
		var prepared: Dictionary = runtime.prepare(definition, player.reward_effect_snapshot())
		runtime.commit(prepared.get("plan", {}), player)
	var participant: RefCounted = FailingBuildParticipant.new(build.transaction_snapshot()) if failing_build else build
	var authority = AuthorityScript.new()
	var configured: Dictionary = authority.configure(
		{"value": 10.0, "history": []},
		ledger,
		participant.call("transaction_snapshot"),
		participant,
		player,
		runtime
	)
	if not bool(configured.get("ok", false)):
		push_error("Reward mutation fixture failed: %s" % str(configured))
	return {
		"authority": authority,
		"build": participant,
		"player": player,
		"before_build": participant.call("transaction_snapshot"),
		"before_player": player.reward_effect_snapshot(),
	}


func _ledger() -> Array[Dictionary]:
	return [
		_definition("item_add", "item", "add", 5.0),
		_definition("blessing_multiply", "blessing", "multiply", 2.0),
		_definition("curse_add", "curse", "add", 3.0),
	]


func _definition(
	content_id: String,
	category: String,
	effect_id: String,
	value: float,
	item_mode: String = "passive"
) -> Dictionary:
	var definition := {
		"id": content_id,
		"category": category,
		"archetype": "",
		"effects": {effect_id: value},
	}
	if category == "item":
		definition["item_mode"] = item_mode
	return definition
