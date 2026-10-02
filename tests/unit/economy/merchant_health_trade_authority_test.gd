extends Node

const MerchantHealthTradeAuthorityScript := preload(
	"res://scripts/economy/merchant_health_trade_authority.gd"
)
const PlayerRewardEffectRuntimeScript := preload(
	"res://scripts/items/player_reward_effect_runtime.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const MERCHANTS_PATH := "res://data/content_packs/base/content/merchants.json"


class FakePlayer extends RefCounted:
	var state: Dictionary
	var fail_health_commit_after_apply: bool = false

	func _init(current_hp: float = 100.0) -> void:
		state = {
			"schema_version": 1,
			"health": {"current_hp": current_hp, "max_hp": 100.0},
			"stats": {"attack_multiplier": 1.0},
		}

	func reward_effect_snapshot() -> Dictionary:
		return state.duplicate(true)

	func can_restore_reward_effect_snapshot(value: Dictionary) -> bool:
		if not value.has("health") or not value["health"] is Dictionary:
			return false
		if not value.has("stats") or not value["stats"] is Dictionary:
			return false
		var health := value["health"] as Dictionary
		return (
			typeof(health.get("current_hp")) in [TYPE_INT, TYPE_FLOAT]
			and typeof(health.get("max_hp")) in [TYPE_INT, TYPE_FLOAT]
			and float(health["current_hp"]) >= 0.0
			and float(health["max_hp"]) > 0.0
		)

	func restore_reward_effect_snapshot(value: Dictionary) -> bool:
		if not can_restore_reward_effect_snapshot(value):
			return false
		state = value.duplicate(true)
		return true

	func reward_effect_apply_operation(operation: Dictionary) -> Dictionary:
		if (
			str(operation.get("effect_id", "")) != "attack_multiplier"
			or str(operation.get("runtime_domain", "")) != "weapon"
			or typeof(operation.get("value")) not in [TYPE_INT, TYPE_FLOAT]
		):
			return {"ok": false, "code": &"OPERATION_REJECTED"}
		var stats := state["stats"] as Dictionary
		stats["attack_multiplier"] = (
			float(stats["attack_multiplier"]) * float(operation["value"])
		)
		return {"ok": true, "code": &"OK"}

	func prepare_nonlethal_health_cost(
		transaction_id: String,
		cost: int,
		frozen_snapshot: Dictionary
	) -> Dictionary:
		if frozen_snapshot != state or cost <= 0:
			return {"ok": false, "code": &"HEALTH_COST_STALE"}
		var after := frozen_snapshot.duplicate(true)
		var health := after["health"] as Dictionary
		health["current_hp"] = float(health["current_hp"]) - float(cost)
		if float(health["current_hp"]) < 1.0:
			return {"ok": false, "code": &"HEALTH_COST_LETHAL"}
		return {
			"ok": true,
			"code": &"OK",
			"ticket": {
				"transaction_id": transaction_id,
				"cost": cost,
				"before_snapshot": frozen_snapshot.duplicate(true),
				"after_snapshot": after,
			},
		}

	func commit_nonlethal_health_cost(ticket: Dictionary) -> Dictionary:
		if state != ticket.get("before_snapshot", {}):
			return {"ok": false, "code": &"HEALTH_COST_STALE"}
		state = (ticket.get("after_snapshot", {}) as Dictionary).duplicate(true)
		if fail_health_commit_after_apply:
			return {"ok": false, "code": &"HEALTH_COST_APPLY_FAILED"}
		return {
			"ok": true,
			"code": &"OK",
			"receipt": ticket.duplicate(true),
		}

	func rollback_nonlethal_health_cost(receipt_or_ticket: Dictionary) -> Dictionary:
		var before := receipt_or_ticket.get("before_snapshot", {}) as Dictionary
		var after := receipt_or_ticket.get("after_snapshot", {}) as Dictionary
		if state == before:
			return {"ok": true, "code": &"OK"}
		if state != after:
			return {"ok": false, "code": &"HEALTH_COST_STALE"}
		state = before.duplicate(true)
		return {"ok": true, "code": &"OK"}


class FakeInventory extends RefCounted:
	var state: Dictionary
	var definitions: Dictionary = {}
	var fail_commit_after_apply: bool = false

	func _init(rarities: Array[String] = ["rare"]) -> void:
		var offers: Array[Dictionary] = []
		for index: int in range(rarities.size()):
			var rarity := rarities[index]
			var reward_id := "trade_reward_%d" % index
			definitions[reward_id] = {
				"id": reward_id,
				"category": "blessing",
				"rarity": rarity,
				"effects": {"attack_multiplier": 1.12},
			}
			offers.append({
				"offer_id": "offer_%d" % index,
				"reward_id": reward_id,
				"category": "blessing",
				"rarity": rarity,
				"price": 999,
				"sold": false,
			})
		state = {
			"schema_version": 1,
			"merchant_id": "merchant_chronomancer",
			"node_id": "health_trade_node",
			"floor_index": 2,
			"reroll_count": 0,
			"revision": 1,
			"offers": offers,
		}

	func open_inventory() -> Dictionary:
		return {"ok": true, "code": &"OK", "snapshot": state.duplicate(true)}

	func snapshot() -> Dictionary:
		return state.duplicate(true)

	func can_restore_snapshot(value: Dictionary) -> bool:
		return (
			value.has("revision")
			and typeof(value["revision"]) == TYPE_INT
			and value.has("offers")
			and value["offers"] is Array
		)

	func restore_snapshot(value: Dictionary) -> bool:
		if not can_restore_snapshot(value):
			return false
		state = value.duplicate(true)
		return true

	func prepare_purchase(
		transaction_id: String,
		state_snapshot: Dictionary,
		offer_id: String,
		expected_revision: int
	) -> Dictionary:
		if state_snapshot != state:
			return {"ok": false, "code": &"MERCHANT_INVENTORY_STATE_STALE"}
		if expected_revision != int(state["revision"]):
			return {"ok": false, "code": &"STALE_REVISION"}
		var after := state.duplicate(true)
		var selected: Dictionary = {}
		for index: int in range((after["offers"] as Array).size()):
			var offer := ((after["offers"] as Array)[index] as Dictionary).duplicate(true)
			if str(offer["offer_id"]) != offer_id:
				continue
			if bool(offer["sold"]):
				return {"ok": false, "code": &"MERCHANT_INVENTORY_OFFER_SOLD"}
			offer["sold"] = true
			(after["offers"] as Array)[index] = offer
			selected = offer.duplicate(true)
			break
		if selected.is_empty():
			return {"ok": false, "code": &"MERCHANT_INVENTORY_OFFER_NOT_FOUND"}
		after["revision"] = expected_revision + 1
		var payload := selected.duplicate(true)
		payload["definition"] = (definitions[str(selected["reward_id"])] as Dictionary).duplicate(true)
		return {
			"ok": true,
			"code": &"OK",
			"ticket": {
				"transaction_id": transaction_id,
				"offer": payload,
				"before_snapshot": state.duplicate(true),
				"after_snapshot": after,
			},
		}

	func commit_purchase(ticket: Dictionary) -> Dictionary:
		if state != ticket.get("before_snapshot", {}):
			return {"ok": false, "code": &"MERCHANT_INVENTORY_STATE_STALE"}
		state = (ticket.get("after_snapshot", {}) as Dictionary).duplicate(true)
		if fail_commit_after_apply:
			return {"ok": false, "code": &"INVENTORY_COMMIT_FAILED"}
		return {
			"ok": true,
			"code": &"OK",
			"receipt": ticket.duplicate(true),
		}

	func rollback_purchase(receipt_or_ticket: Dictionary) -> Dictionary:
		var before := receipt_or_ticket.get("before_snapshot", {}) as Dictionary
		var after := receipt_or_ticket.get("after_snapshot", {}) as Dictionary
		if state == before:
			return {"ok": true, "code": &"OK"}
		if state != after:
			return {"ok": false, "code": &"MERCHANT_INVENTORY_STATE_STALE"}
		state = before.duplicate(true)
		return {"ok": true, "code": &"OK"}


class FailingRewardRuntime extends RefCounted:
	var delegate = PlayerRewardEffectRuntimeScript.new()

	func prepare(definition: Dictionary, player_snapshot: Dictionary) -> Dictionary:
		return delegate.prepare(definition, player_snapshot)

	func commit(_plan: Dictionary, _player: Object) -> Dictionary:
		return {"ok": false, "code": &"REWARD_FAILURE"}

	func rollback(receipt: Dictionary, player: Object) -> Dictionary:
		return delegate.rollback(receipt, player)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_configure_requires_health_trade_policy(suite)
	_test_prepare_binds_authoritative_rare_offer_and_health_cost(suite)
	_test_health_cost_is_nonlethal_at_low_hp(suite)
	_test_sold_stale_and_no_eligible_inventory_reject(suite)
	_test_health_commit_failure_restores_exactly(suite)
	_test_reward_failure_restores_health_exactly(suite)
	_test_inventory_failure_restores_reward_and_health_exactly(suite)
	_test_success_rollback_is_exact(suite)
	_test_snapshot_restore_preserves_duplicate_ids(suite)
	suite.finish(get_tree())


func _test_configure_requires_health_trade_policy(suite) -> void:
	var player := FakePlayer.new()
	var inventory := FakeInventory.new()
	var no_service := _merchant("merchant_wayfarer")
	var authority = MerchantHealthTradeAuthorityScript.new()
	suite.assert_equal(
		authority.configure(
			no_service, player, PlayerRewardEffectRuntimeScript.new(), inventory
		).get("code"),
		&"SERVICE_NOT_OFFERED",
		"merchant service list is authoritative"
	)
	var no_health := _merchant("merchant_chronomancer")
	no_health["accepted_costs"] = ["gold", "time_shard"]
	suite.assert_equal(
		authority.configure(
			no_health, player, PlayerRewardEffectRuntimeScript.new(), inventory
		).get("code"),
		&"COST_NOT_ACCEPTED",
		"merchant accepted costs must include health"
	)


func _test_prepare_binds_authoritative_rare_offer_and_health_cost(suite) -> void:
	var fixture := _fixture(100.0)
	var before_player: Dictionary = fixture.player.reward_effect_snapshot()
	var before_inventory: Dictionary = fixture.inventory.state.duplicate(true)
	var prepared: Dictionary = fixture.authority.prepare_trade("trade_prepare", "offer_0", 1)
	suite.assert_true(bool(prepared.get("ok", false)), "rare health trade prepares")
	var ticket := prepared.get("ticket", {}) as Dictionary
	suite.assert_equal(ticket.get("cost_kind"), "health", "ticket freezes health as the cost kind")
	suite.assert_equal(ticket.get("health_cost"), 30, "cost is ceil of thirty percent current HP")
	suite.assert_equal(ticket.get("offer_id"), "offer_0", "ticket binds the requested current offer")
	suite.assert_equal(ticket.get("reward_id"), "trade_reward_0", "reward comes from inventory authority")
	suite.assert_equal(ticket.get("rarity"), "rare", "ticket freezes authoritative rarity")
	suite.assert_equal(fixture.player.reward_effect_snapshot(), before_player, "prepare has zero player side effects")
	suite.assert_equal(fixture.inventory.state, before_inventory, "prepare has zero inventory side effects")

	var tampered := ticket.duplicate(true)
	tampered["health_cost"] = 1
	suite.assert_equal(
		fixture.authority.commit_trade(tampered).get("code"),
		&"TICKET_INVALID",
		"UI cannot override the authoritative health cost"
	)
	var forged_definition := ticket.duplicate(true)
	(forged_definition["reward_definition"] as Dictionary)["id"] = "ui_forged_reward"
	suite.assert_equal(
		fixture.authority.commit_trade(forged_definition).get("code"),
		&"TICKET_INVALID",
		"UI cannot replace the inventory reward definition"
	)


func _test_health_cost_is_nonlethal_at_low_hp(suite) -> void:
	var two_hp := _fixture(2.0)
	var prepared: Dictionary = two_hp.authority.prepare_trade("trade_two_hp", "offer_0", 1)
	suite.assert_true(bool(prepared.get("ok", false)), "two HP can trade nonlethally")
	suite.assert_equal(prepared.get("ticket", {}).get("health_cost"), 1, "two HP rounds the cost up to one")
	var committed: Dictionary = two_hp.authority.commit_trade(prepared.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "two HP trade commits")
	suite.assert_close(float(two_hp.player.state["health"]["current_hp"]), 1.0, "trade leaves at least one HP")

	var one_hp := _fixture(1.0)
	var rejected: Dictionary = one_hp.authority.prepare_trade("trade_one_hp", "offer_0", 1)
	suite.assert_equal(rejected.get("code"), &"HEALTH_COST_LETHAL", "one HP trade rejects before mutation")
	suite.assert_close(float(one_hp.player.state["health"]["current_hp"]), 1.0, "lethal rejection preserves HP")


func _test_sold_stale_and_no_eligible_inventory_reject(suite) -> void:
	var sold := _fixture(100.0)
	(sold.inventory.state["offers"][0] as Dictionary)["sold"] = true
	suite.assert_equal(
		sold.authority.prepare_trade("trade_sold", "offer_0", 1).get("code"),
		&"OFFER_SOLD",
		"sold offer cannot be health traded"
	)
	var stale := _fixture(100.0)
	suite.assert_equal(
		stale.authority.prepare_trade("trade_stale", "offer_0", 2).get("code"),
		&"STALE_REVISION",
		"caller revision must match current inventory"
	)
	var common_only := _fixture(100.0, ["common"])
	suite.assert_equal(
		common_only.authority.prepare_trade("trade_common", "offer_0", 1).get("code"),
		&"NO_ELIGIBLE_OFFER",
		"inventory without an unsold rare-or-better offer rejects"
	)


func _test_health_commit_failure_restores_exactly(suite) -> void:
	var fixture := _fixture(64.0)
	fixture.player.fail_health_commit_after_apply = true
	var before_player: Dictionary = fixture.player.reward_effect_snapshot()
	var before_inventory: Dictionary = fixture.inventory.state.duplicate(true)
	var prepared: Dictionary = fixture.authority.prepare_trade(
		"trade_health_failure", "offer_0", 1
	)
	var failed: Dictionary = fixture.authority.commit_trade(prepared.get("ticket", {}))
	suite.assert_equal(
		failed.get("code"),
		&"HEALTH_COMMIT_FAILED",
		"mutating health failure aborts the trade"
	)
	suite.assert_equal(
		fixture.player.reward_effect_snapshot(),
		before_player,
		"health commit failure restores the complete reward snapshot"
	)
	suite.assert_equal(
		fixture.inventory.state,
		before_inventory,
		"health commit failure does not sell inventory"
	)


func _test_reward_failure_restores_health_exactly(suite) -> void:
	var fixture := _fixture(73.0, ["rare"], FailingRewardRuntime.new())
	var before_player: Dictionary = fixture.player.reward_effect_snapshot()
	var before_inventory: Dictionary = fixture.inventory.state.duplicate(true)
	var prepared: Dictionary = fixture.authority.prepare_trade("trade_reward_failure", "offer_0", 1)
	var failed: Dictionary = fixture.authority.commit_trade(prepared.get("ticket", {}))
	suite.assert_equal(failed.get("code"), &"REWARD_COMMIT_FAILED", "reward failure aborts the trade")
	suite.assert_equal(fixture.player.reward_effect_snapshot(), before_player, "reward failure restores full player snapshot")
	suite.assert_equal(fixture.inventory.state, before_inventory, "reward failure never sells the inventory offer")


func _test_inventory_failure_restores_reward_and_health_exactly(suite) -> void:
	var fixture := _fixture(81.0)
	fixture.inventory.fail_commit_after_apply = true
	var before_player: Dictionary = fixture.player.reward_effect_snapshot()
	var before_inventory: Dictionary = fixture.inventory.state.duplicate(true)
	var prepared: Dictionary = fixture.authority.prepare_trade("trade_inventory_failure", "offer_0", 1)
	var failed: Dictionary = fixture.authority.commit_trade(prepared.get("ticket", {}))
	suite.assert_equal(failed.get("code"), &"INVENTORY_COMMIT_FAILED", "inventory failure aborts the trade")
	suite.assert_equal(fixture.player.reward_effect_snapshot(), before_player, "inventory failure reverses reward and health")
	suite.assert_equal(fixture.inventory.state, before_inventory, "mutating inventory failure restores exact state")


func _test_success_rollback_is_exact(suite) -> void:
	var fixture := _fixture(100.0, ["legendary"])
	var before_player: Dictionary = fixture.player.reward_effect_snapshot()
	var before_inventory: Dictionary = fixture.inventory.state.duplicate(true)
	var before_authority: Dictionary = fixture.authority.snapshot()
	var prepared: Dictionary = fixture.authority.prepare_trade("trade_rollback", "offer_0", 1)
	var committed: Dictionary = fixture.authority.commit_trade(prepared.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "legendary health trade commits")
	suite.assert_close(float(fixture.player.state["health"]["current_hp"]), 70.0, "commit charges frozen health cost")
	suite.assert_close(float(fixture.player.state["stats"]["attack_multiplier"]), 1.12, "commit applies reward")
	suite.assert_true(bool(fixture.inventory.state["offers"][0]["sold"]), "commit marks inventory sold")
	var rolled_back: Dictionary = fixture.authority.rollback_trade(committed.get("receipt", {}))
	suite.assert_true(bool(rolled_back.get("ok", false)), "committed health trade rolls back")
	suite.assert_equal(fixture.player.reward_effect_snapshot(), before_player, "rollback restores exact player snapshot")
	suite.assert_equal(fixture.inventory.state, before_inventory, "rollback restores exact inventory snapshot")
	suite.assert_equal(fixture.authority.snapshot(), before_authority, "rollback restores exact authority snapshot")


func _test_snapshot_restore_preserves_duplicate_ids(suite) -> void:
	var fixture := _fixture(100.0)
	var prepared: Dictionary = fixture.authority.prepare_trade("trade_restore", "offer_0", 1)
	suite.assert_true(bool(fixture.authority.commit_trade(prepared.get("ticket", {})).get("ok", false)), "restore fixture commits")
	var saved: Dictionary = fixture.authority.snapshot()
	var restored = MerchantHealthTradeAuthorityScript.new()
	var configured: Dictionary = restored.configure(
		_merchant("merchant_chronomancer"),
		fixture.player,
		PlayerRewardEffectRuntimeScript.new(),
		fixture.inventory
	)
	suite.assert_true(bool(configured.get("ok", false)), "restored authority configures")
	suite.assert_true(restored.can_restore_snapshot(saved), "completed transaction snapshot validates")
	suite.assert_true(restored.restore_snapshot(saved), "completed transaction snapshot restores")
	suite.assert_equal(restored.snapshot(), saved, "snapshot round trips exactly")
	suite.assert_equal(
		restored.prepare_trade("trade_restore", "offer_0", 2).get("code"),
		&"DUPLICATE_TRANSACTION",
		"restored completed transaction remains consumed"
	)


func _fixture(
	current_hp: float,
	rarities: Array[String] = ["rare"],
	reward_runtime: Object = null
) -> Dictionary:
	var player := FakePlayer.new(current_hp)
	var inventory := FakeInventory.new(rarities)
	var authority = MerchantHealthTradeAuthorityScript.new()
	var runtime: Object = reward_runtime if reward_runtime != null else PlayerRewardEffectRuntimeScript.new()
	var configured: Dictionary = authority.configure(
		_merchant("merchant_chronomancer"), player, runtime, inventory
	)
	if not bool(configured.get("ok", false)):
		push_error("Merchant health trade fixture failed: %s" % str(configured))
	return {
		"authority": authority,
		"player": player,
		"reward_runtime": runtime,
		"inventory": inventory,
	}


func _merchant(merchant_id: String) -> Dictionary:
	var file := FileAccess.open(MERCHANTS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for merchant_value: Variant in parsed as Array:
			if merchant_value is Dictionary and str(merchant_value.get("id", "")) == merchant_id:
				return (merchant_value as Dictionary).duplicate(true)
	return {}
