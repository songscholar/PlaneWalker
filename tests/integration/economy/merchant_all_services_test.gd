extends Node

const MerchantServiceRouterScript := preload(
	"res://scripts/economy/merchant_service_router.gd"
)
const MerchantRuntimeScript := preload("res://scripts/economy/merchant_runtime.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


class FakeInventory extends RefCounted:
	var state := {"revision": 4}

	func snapshot() -> Dictionary:
		return state.duplicate(true)

	func prepare_purchase(_a, _b, _c, _d) -> Dictionary:
		return {"ok": false}

	func commit_purchase(_value: Dictionary) -> Dictionary:
		return {"ok": false}

	func rollback_purchase(_value: Dictionary) -> Dictionary:
		return {"ok": true}

	func prepare_reroll(_a, _b, _c) -> Dictionary:
		return {"ok": false}

	func commit_reroll(_value: Dictionary) -> Dictionary:
		return {"ok": false}

	func rollback_reroll(_value: Dictionary) -> Dictionary:
		return {"ok": true}


class FakeEconomy extends RefCounted:
	var state := {"balance": 500, "revision": 0, "ledger": []}
	var pending: Dictionary = {}
	var last_operation := ""

	func snapshot() -> Dictionary:
		return state.duplicate(true)

	func prepare_transaction(
		transaction_id: String,
		delta: int,
		expected_revision: int,
		context: Dictionary = {}
	) -> Dictionary:
		if not pending.is_empty() or expected_revision != int(state["revision"]):
			return {"ok": false, "code": &"STALE_REVISION"}
		if int(state["balance"]) + delta < 0:
			return {"ok": false, "code": &"INSUFFICIENT_GOLD"}
		pending = {
			"transaction_id": transaction_id,
			"delta": delta,
			"before": state.duplicate(true),
			"context": context.duplicate(true),
		}
		last_operation = str(context.get("operation", ""))
		return {"ok": true, "ticket": pending.duplicate(true)}

	func commit_transaction(ticket: Dictionary) -> Dictionary:
		if ticket != pending:
			return {"ok": false, "code": &"TICKET_STALE"}
		var before := state.duplicate(true)
		state["balance"] = int(state["balance"]) + int(ticket["delta"])
		state["revision"] = int(state["revision"]) + 1
		(state["ledger"] as Array).append({
			"transaction_id": str(ticket["transaction_id"]),
			"operation": str((ticket["context"] as Dictionary)["operation"]),
			"amount": int(ticket["delta"]),
		})
		pending.clear()
		return {"ok": true, "receipt": {
			"transaction_id": str(ticket["transaction_id"]),
			"before": before,
			"after": state.duplicate(true),
		}}

	func rollback_transaction(value: Dictionary) -> Dictionary:
		if value.has("after"):
			state = (value["before"] as Dictionary).duplicate(true)
		else:
			pending.clear()
		return {"ok": true}


class FakeRewardRuntime extends RefCounted:
	func prepare(_definition: Dictionary, _snapshot: Dictionary) -> Dictionary:
		return {"ok": false}

	func commit(_plan: Dictionary, _player: Object) -> Dictionary:
		return {"ok": false}

	func rollback(_receipt: Dictionary, _player: Object) -> Dictionary:
		return {"ok": true}


class FakePlayer extends RefCounted:
	var state := {"health": {"current_hp": 80.0, "max_hp": 100.0}}
	var publication_active := false
	var publication_count := 0

	func reward_effect_snapshot() -> Dictionary:
		return state.duplicate(true)

	func restore_reward_effect_snapshot(value: Dictionary) -> bool:
		state = value.duplicate(true)
		return true

	func reward_effect_apply_operation(_operation: Dictionary) -> Dictionary:
		return {"ok": true}

	func reward_effect_begin_publication() -> bool:
		if publication_active:
			return false
		publication_active = true
		return true

	func reward_effect_publication_can_commit() -> bool:
		return publication_active

	func reward_effect_commit_publication() -> bool:
		if not publication_active:
			return false
		publication_active = false
		publication_count += 1
		return true

	func reward_effect_rollback_publication() -> bool:
		if not publication_active:
			return false
		publication_active = false
		return true


class FakeAuthority extends RefCounted:
	var kind: String
	var state := {"completed_transaction_ids": []}
	var pending: Dictionary = {}
	var last_call := ""
	var last_target := ""

	func _init(value: String) -> void:
		kind = value

	func prepare_service(transaction_id: String, _service_id: StringName, target_id: String) -> Dictionary:
		last_call = "prepare_service"
		last_target = target_id
		return _prepared(transaction_id, {"cost_kind": "gold", "price": 40})

	func prepare_upgrade(transaction_id: String) -> Dictionary:
		last_call = "prepare_upgrade"
		return _prepared(transaction_id, {"cost_kind": "gold", "price": 130})

	func prepare_trade(transaction_id: String, offer_id: String, revision: int) -> Dictionary:
		last_call = "prepare_trade"
		last_target = offer_id
		return _prepared(transaction_id, {
			"cost_kind": "health",
			"health_cost": 24,
			"offer_id": offer_id,
			"reward_id": "rare_reward",
			"inventory_revision": revision,
		})

	func prepare_reveal(transaction_id: String, _floor_plan: Dictionary) -> Dictionary:
		last_call = "prepare_reveal"
		return _prepared(transaction_id, {})

	func prepare_remove(transaction_id: String, reward_id: String, categories: Array) -> Dictionary:
		last_call = "prepare_remove"
		last_target = reward_id
		var category := "curse" if categories == ["curse"] else "item"
		return _prepared(transaction_id, {
			"reward_id": reward_id,
			"category": category,
			"before_ledger": [{
				"id": reward_id,
				"category": category,
				"rarity": "rare",
				"item_mode": "passive",
				"effects": {},
			}],
		})

	func commit_service(ticket: Dictionary) -> Dictionary:
		return _commit(ticket)

	func commit_upgrade(ticket: Dictionary) -> Dictionary:
		return _commit(ticket)

	func commit_trade(ticket: Dictionary) -> Dictionary:
		return _commit(ticket)

	func commit_reveal(ticket: Dictionary) -> Dictionary:
		return _commit(ticket)

	func commit_remove(ticket: Dictionary) -> Dictionary:
		return _commit(ticket)

	func rollback_service(value: Dictionary) -> Dictionary:
		return _rollback(value)

	func rollback_upgrade(value: Dictionary) -> Dictionary:
		return _rollback(value)

	func rollback_trade(value: Dictionary) -> Dictionary:
		return _rollback(value)

	func rollback_reveal(value: Dictionary) -> Dictionary:
		return _rollback(value)

	func rollback_remove(value: Dictionary) -> Dictionary:
		return _rollback(value)

	func snapshot() -> Dictionary:
		return {
			"kind": kind,
			"completed_transaction_ids": (state["completed_transaction_ids"] as Array).duplicate(),
		}

	func can_restore_snapshot(value: Dictionary) -> bool:
		return value.get("kind") == kind and value.get("completed_transaction_ids") is Array

	func restore_snapshot(value: Dictionary) -> bool:
		if not can_restore_snapshot(value):
			return false
		state["completed_transaction_ids"] = (value["completed_transaction_ids"] as Array).duplicate()
		pending.clear()
		return snapshot() == value

	func floor_plan_snapshot() -> Dictionary:
		return {"schema": "visibility", "revealed": true}

	func _prepared(transaction_id: String, values: Dictionary) -> Dictionary:
		pending = {"transaction_id": transaction_id, "kind": kind}
		for key: Variant in values:
			pending[key] = values[key]
		return {"ok": true, "ticket": pending.duplicate(true)}

	func _commit(ticket: Dictionary) -> Dictionary:
		if ticket != pending:
			return {"ok": false, "code": &"TICKET_STALE"}
		var transaction_id := str(ticket["transaction_id"])
		(state["completed_transaction_ids"] as Array).append(transaction_id)
		pending.clear()
		return {"ok": true, "receipt": ticket.duplicate(true)}

	func _rollback(value: Dictionary) -> Dictionary:
		var transaction_id := str(value.get("transaction_id", ""))
		pending.clear()
		(state["completed_transaction_ids"] as Array).erase(transaction_id)
		return {"ok": true, "transaction_id": transaction_id}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_typed_service_routing(suite)
	_test_composite_snapshot_round_trip(suite)
	_test_runtime_cost_kinds_drive_economy(suite)
	suite.finish(get_tree())


func _test_typed_service_routing(suite) -> void:
	var fixture := _fixture()
	var cases := [
		{"id": &"heal", "target": "player", "cost": "gold", "amount": 40, "delta": -40, "authority": "heal"},
		{"id": &"weapon_upgrade", "target": "sword", "cost": "gold", "amount": 130, "delta": -130, "authority": "weapon_upgrade"},
		{"id": &"health_trade", "target": "offer-rare", "cost": "health", "amount": 24, "delta": 0, "authority": "health_trade"},
		{"id": &"cleanse_curse", "target": "curse_owned", "cost": "gold", "amount": 130, "delta": -130, "authority": "reward_mutation"},
		{"id": &"sell_reward", "target": "item_owned", "cost": "reward", "amount": 76, "delta": 76, "authority": "reward_mutation"},
		{"id": &"route_reveal", "target": "floor", "cost": "gold", "amount": 78, "delta": -78, "authority": "visibility"},
	]
	for index: int in range(cases.size()):
		var case: Dictionary = cases[index]
		var transaction_id := "router_case_%d" % index
		var prepared: Dictionary = fixture.router.prepare_service(
			transaction_id, case["id"], str(case["target"])
		)
		suite.assert_true(bool(prepared.get("ok", false)), "%s prepares" % case["id"])
		if not bool(prepared.get("ok", false)):
			continue
		var ticket := prepared["ticket"] as Dictionary
		suite.assert_equal(ticket.get("cost_kind"), case["cost"], "%s cost kind is typed" % case["id"])
		suite.assert_equal(int(ticket.get("amount", -1)), int(case["amount"]), "%s freezes amount" % case["id"])
		suite.assert_equal(int(ticket.get("economy_delta", 999)), int(case["delta"]), "%s freezes economy delta" % case["id"])
		var committed: Dictionary = fixture.router.commit_service(ticket)
		suite.assert_true(bool(committed.get("ok", false)), "%s commits" % case["id"])
		if bool(committed.get("ok", false)):
			var receipt := committed["receipt"] as Dictionary
			suite.assert_equal(receipt.get("service_id"), str(case["id"]), "%s receipt stays typed" % case["id"])
			suite.assert_true(bool(fixture.router.rollback_service(receipt).get("ok", false)), "%s rolls back" % case["id"])


func _test_composite_snapshot_round_trip(suite) -> void:
	var fixture := _fixture()
	var prepared: Dictionary = fixture.router.prepare_service(
		"router_persist", &"route_reveal", "floor"
	)
	suite.assert_true(bool(prepared.get("ok", false)), "persisted route reveal prepares")
	if not bool(prepared.get("ok", false)):
		return
	suite.assert_true(
		bool(fixture.router.commit_service(prepared["ticket"]).get("ok", false)),
		"persisted route reveal commits"
	)
	var canonical: Dictionary = fixture.router.snapshot()
	var restored := _fixture()
	suite.assert_true(restored.router.can_restore_snapshot(canonical), "composite snapshot validates")
	suite.assert_true(restored.router.restore_snapshot(canonical), "composite snapshot restores")
	suite.assert_equal(restored.router.snapshot(), canonical, "composite restore is exact")
	var duplicate: Dictionary = restored.router.prepare_service(
		"router_persist", &"route_reveal", "floor"
	)
	suite.assert_equal(duplicate.get("code"), &"ALREADY_CONSUMED", "restored service id remains consumed")
	suite.assert_equal(
		restored.router.visibility_snapshot(),
		{"schema": "visibility", "revealed": true},
		"visibility snapshot remains available for MerchantRunState"
	)


func _test_runtime_cost_kinds_drive_economy(suite) -> void:
	var fixture := _fixture()
	var economy := FakeEconomy.new()
	var player := FakePlayer.new()
	var runtime = MerchantRuntimeScript.new()
	suite.assert_true(
		runtime.configure(
			economy,
			fixture.inventory,
			FakeRewardRuntime.new(),
			player,
			fixture.router
		),
		"typed runtime configures"
	)
	var health_trade: Dictionary = runtime.execute_service(
		"runtime_health", &"health_trade", "offer-rare", 0
	)
	suite.assert_true(bool(health_trade.get("ok", false)), "health trade commits without a gold ticket")
	suite.assert_equal(health_trade.get("cost_kind"), "health", "health trade result keeps health cost")
	suite.assert_equal(int(economy.state["revision"]), 0, "health trade leaves economy revision unchanged")
	suite.assert_true((health_trade.get("economy_receipt", {}) as Dictionary).is_empty(), "health trade has no fake economy receipt")

	var sold: Dictionary = runtime.execute_service(
		"runtime_sell", &"sell_reward", "item_owned", 0
	)
	suite.assert_true(bool(sold.get("ok", false)), "sell reward commits")
	suite.assert_equal(sold.get("cost_kind"), "reward", "sell result keeps reward cost")
	suite.assert_equal(int(economy.state["balance"]), 576, "sell reward credits authoritative sell price")
	suite.assert_equal(economy.last_operation, "gold_delta", "sell reward records positive gold_delta")

	var revealed: Dictionary = runtime.execute_service(
		"runtime_route", &"route_reveal", "floor", 1
	)
	suite.assert_true(bool(revealed.get("ok", false)), "route reveal commits")
	suite.assert_equal(int(economy.state["balance"]), 498, "gold service debits authoritative price")
	suite.assert_equal(economy.last_operation, "gold_service", "gold service records gold_service")
	suite.assert_equal(player.publication_count, 3, "each completed service publishes exactly once")


func _fixture() -> Dictionary:
	var authorities := {
		"heal": FakeAuthority.new("heal"),
		"weapon_upgrade": FakeAuthority.new("weapon_upgrade"),
		"health_trade": FakeAuthority.new("health_trade"),
		"reward_mutation": FakeAuthority.new("reward_mutation"),
		"visibility": FakeAuthority.new("visibility"),
	}
	var router = MerchantServiceRouterScript.new()
	var configured: Dictionary = router.configure(
		_merchant(),
		_profile(),
		3,
		FakeInventory.new(),
		_floor_plan(),
		authorities
	)
	assert(bool(configured.get("ok", false)))
	return {
		"router": router,
		"authorities": authorities,
		"inventory": router.get("_inventory"),
	}


func _merchant() -> Dictionary:
	return {
		"id": "merchant_forgekeeper",
		"services": [
			"heal", "weapon_upgrade", "health_trade", "cleanse_curse",
			"sell_reward", "route_reveal",
		],
	}


func _profile() -> Dictionary:
	var file := FileAccess.open(
		"res://data/content_packs/base/content/economy_profiles.json",
		FileAccess.READ
	)
	assert(file != null)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	assert(parsed is Array and not (parsed as Array).is_empty())
	return ((parsed as Array)[0] as Dictionary).duplicate(true)


func _floor_plan() -> Dictionary:
	return {"floor_id": "floor_forge", "floor_index": 2, "current_node_id": "shop"}
