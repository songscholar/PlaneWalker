extends Node

const MerchantRunStateScript := preload("res://scripts/economy/merchant_run_state.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const CONTENT_FINGERPRINT := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_initialization_and_atomic_shop_commit(suite)
	_test_stale_non_shop_and_identity_rejection(suite)
	_test_atomic_gold_income_commit(suite)
	_test_reward_sale_cross_domain_validation(suite)
	suite.finish(get_tree())


func _test_initialization_and_atomic_shop_commit(suite) -> void:
	var orchestrator = _started_orchestrator()
	var initial_merchant := _merchant_state([], [])
	var initialized = orchestrator.initialize_launch_economy(
		_economy_snapshot(100, 100, []), initial_merchant, orchestrator.revision()
	)
	suite.assert_true(initialized.ok, "Launch economy initializes atomically")
	suite.assert_equal(initialized.new_revision, 3, "initialization advances one revision")
	var state: RefCounted = orchestrator.get("_state")
	_configure_shop_state(state)
	var transaction := {
		"sequence": 1,
		"transaction_id": "tx_shop_purchase",
		"kind": "purchase",
		"offer_id": "offer_1",
		"reward_id": "item_1",
		"service_id": "",
		"cost_kind": "gold",
		"amount": 40,
		"economy_revision": 1,
		"inventory_revision": 2,
	}
	var merchant_after := _merchant_state([_shop_node()], [transaction])
	var economy_after := _economy_snapshot(
		100,
		60,
		[{"transaction_id": "tx_shop_purchase", "operation": "gold_purchase", "amount": -40, "revision": 1}]
	)
	var committed = orchestrator.commit_merchant_transaction(
		economy_after, merchant_after, orchestrator.revision()
	)
	suite.assert_true(committed.ok, "shop transaction commits both domains")
	suite.assert_equal(committed.new_revision, 4, "shop transaction advances one global revision")
	var snapshot: Dictionary = orchestrator.snapshot()
	suite.assert_equal(snapshot.get("run_economy"), economy_after, "economy snapshot installs exactly")
	suite.assert_equal(snapshot.get("merchant_state"), merchant_after, "merchant snapshot installs exactly")


func _test_stale_non_shop_and_identity_rejection(suite) -> void:
	var orchestrator = _started_orchestrator()
	orchestrator.initialize_launch_economy(
		_economy_snapshot(100, 100, []), _merchant_state([], []), orchestrator.revision()
	)
	var state: RefCounted = orchestrator.get("_state")
	_configure_shop_state(state)
	var transaction := {
		"sequence": 1,
		"transaction_id": "tx_shop_guard",
		"kind": "reroll",
		"offer_id": "",
		"reward_id": "",
		"service_id": "",
		"cost_kind": "gold",
		"amount": 40,
		"economy_revision": 1,
		"inventory_revision": 2,
	}
	var merchant_after := _merchant_state([_shop_node()], [transaction])
	var economy_after := _economy_snapshot(
		100, 60,
		[{"transaction_id": "tx_shop_guard", "operation": "gold_reroll", "amount": -40, "revision": 1}]
	)
	var before: Dictionary = orchestrator.snapshot()
	var stale = orchestrator.commit_merchant_transaction(
		economy_after, merchant_after, orchestrator.revision() - 1
	)
	suite.assert_equal(stale.code, &"STALE_REVISION", "stale shop commit rejects")
	suite.assert_equal(orchestrator.snapshot(), before, "stale shop commit mutates nothing")

	var forged_node := _shop_node()
	forged_node["merchant_id"] = "merchant_chronomancer"
	var identity_drift := _merchant_state([forged_node], [transaction])
	var rejected = orchestrator.commit_merchant_transaction(
		economy_after, identity_drift, orchestrator.revision()
	)
	suite.assert_equal(rejected.code, &"INVALID_ARGUMENT", "merchant identity drift rejects")
	suite.assert_equal(orchestrator.snapshot(), before, "identity drift mutates nothing")

	state.set("floor_plan", {
		"floor_id": "floor_ruins_of_remnant",
		"current_node_id": "shop_node",
		"nodes": [{"id": "shop_node", "room_type": "event", "merchant_id": "merchant_wayfarer"}],
	})
	var non_shop = orchestrator.commit_merchant_transaction(
		economy_after, merchant_after, orchestrator.revision()
	)
	suite.assert_equal(non_shop.code, &"INVALID_ARGUMENT", "non-shop node rejects merchant commit")


func _test_atomic_gold_income_commit(suite) -> void:
	var orchestrator = _started_orchestrator()
	var merchant := _merchant_state([], [])
	var economy_before := _economy_snapshot(0, 0, [])
	suite.assert_true(
		orchestrator.initialize_launch_economy(
			economy_before, merchant, orchestrator.revision()
		).ok,
		"gold income fixture initializes Launch economy"
	)
	var state: RefCounted = orchestrator.get("_state")
	_configure_shop_state(state)
	var economy_after := _economy_snapshot(
		0,
		75,
		[{
			"transaction_id": "tx_room_reward_001",
			"operation": "gold_delta",
			"amount": 75,
			"revision": 1,
		}]
	)
	var committed = orchestrator.commit_economy_transaction(
		economy_after, merchant, orchestrator.revision()
	)
	suite.assert_true(committed.ok, "positive gold income commits atomically")
	suite.assert_equal(
		orchestrator.snapshot().get("run_economy"),
		economy_after,
		"gold income installs the exact economy snapshot"
	)
	suite.assert_equal(
		orchestrator.snapshot().get("merchant_state"),
		merchant,
		"gold income preserves the merchant snapshot"
	)

	var committed_snapshot: Dictionary = orchestrator.snapshot()
	var stale = orchestrator.commit_economy_transaction(
		economy_after, merchant, orchestrator.revision() - 1
	)
	suite.assert_equal(stale.code, &"STALE_REVISION", "stale gold income commit rejects")
	suite.assert_equal(
		orchestrator.snapshot(), committed_snapshot,
		"stale gold income commit mutates nothing"
	)

	var forged_merchant := merchant.duplicate(true)
	forged_merchant["next_transaction_sequence"] = 2
	var forged = orchestrator.commit_economy_transaction(
		economy_after, forged_merchant, orchestrator.revision()
	)
	suite.assert_equal(forged.code, &"INVALID_ARGUMENT", "economy-only commit rejects merchant drift")
	suite.assert_equal(
		orchestrator.snapshot(), committed_snapshot,
		"merchant drift rejection remains atomic"
	)


func _test_reward_sale_cross_domain_validation(suite) -> void:
	var orchestrator = _started_orchestrator()
	var initial_merchant := _merchant_state([], [])
	suite.assert_true(
		orchestrator.initialize_launch_economy(
			_economy_snapshot(0, 0, []), initial_merchant, orchestrator.revision()
		).ok,
		"reward sale fixture initializes Launch economy"
	)
	var state: RefCounted = orchestrator.get("_state")
	_configure_shop_state(state)
	var sale_fact := {
		"sequence": 1,
		"transaction_id": "tx_sell_reward_001",
		"kind": "service",
		"offer_id": "",
		"reward_id": "item_1",
		"service_id": "sell_reward",
		"cost_kind": "reward",
		"amount": 25,
		"economy_revision": 1,
		"inventory_revision": 1,
	}
	var merchant_after := _merchant_state([_shop_node()], [sale_fact])
	var forged_economy := _economy_snapshot(
		0,
		20,
		[{
			"transaction_id": "tx_sell_reward_001",
			"operation": "gold_delta",
			"amount": 20,
			"revision": 1,
		}]
	)
	var before: Dictionary = orchestrator.snapshot()
	var rejected = orchestrator.commit_merchant_transaction(
		forged_economy, merchant_after, orchestrator.revision()
	)
	suite.assert_equal(rejected.code, &"INVALID_ARGUMENT", "sell payout amount drift rejects")
	suite.assert_equal(orchestrator.snapshot(), before, "rejected sell payout is atomic")

	var canonical_economy := _economy_snapshot(
		0,
		25,
		[{
			"transaction_id": "tx_sell_reward_001",
			"operation": "gold_delta",
			"amount": 25,
			"revision": 1,
		}]
	)
	var committed = orchestrator.commit_merchant_transaction(
		canonical_economy, merchant_after, orchestrator.revision()
	)
	suite.assert_true(committed.ok, "canonical sell payout commits")


func _started_orchestrator():
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run({
		"seed": 20261002,
		"difficulty": "normal",
		"character_id": "character_time_guardian",
		"weapon_id": "sword",
		"time_ability_id": "time_slow",
		"milestone": "LAUNCH",
	}, "run-merchant-state")
	return orchestrator


func _configure_shop_state(state: RefCounted) -> void:
	state.set("phase", RunPhaseScript.Value.ROOM_ACTIVE)
	state.set("current_floor_index", 0)
	state.set("floor_plan", {
		"floor_id": "floor_ruins_of_remnant",
		"current_node_id": "shop_node",
		"nodes": [{"id": "shop_node", "room_type": "shop", "merchant_id": "merchant_wayfarer"}],
	})


func _economy_snapshot(initial_gold: int, balance: int, ledger: Array) -> Dictionary:
	return {
		"schema_id": "planewalker.run_economy",
		"schema_version": 1,
		"profile_id": "launch_economy_v1",
		"initial_gold": initial_gold,
		"balance": balance,
		"revision": ledger.size(),
		"ledger": ledger.duplicate(true),
		"settled_floor_indices": [],
	}


func _merchant_state(nodes: Array, transactions: Array) -> Dictionary:
	var authority = MerchantRunStateScript.new()
	assert(bool(authority.configure(CONTENT_FINGERPRINT).get("ok", false)))
	for node_value: Variant in nodes:
		var node := (node_value as Dictionary).duplicate(true)
		node["transactions"] = []
		assert(bool(authority.upsert_node(node).get("ok", false)))
	for transaction_value: Variant in transactions:
		assert(bool(authority.record_transaction(
			"floor_ruins_of_remnant:shop_node", transaction_value as Dictionary
		).get("ok", false)))
	return authority.snapshot()


func _shop_node() -> Dictionary:
	return {
		"floor_id": "floor_ruins_of_remnant",
		"floor_index": 0,
		"node_id": "shop_node",
		"merchant_id": "merchant_wayfarer",
		"inventory": {},
		"runtime": {},
		"service": {},
		"visibility": {},
		"transactions": [],
	}
