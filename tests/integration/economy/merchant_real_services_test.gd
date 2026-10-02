extends Node

const MerchantInventoryServiceScript := preload(
	"res://scripts/economy/merchant_inventory_service.gd"
)
const MerchantRuntimeScript := preload("res://scripts/economy/merchant_runtime.gd")
const MerchantServiceAuthorityScript := preload(
	"res://scripts/economy/merchant_service_authority.gd"
)
const PlayerRewardEffectRuntimeScript := preload(
	"res://scripts/items/player_reward_effect_runtime.gd"
)
const RunEconomyStateScript := preload("res://scripts/economy/run_economy_state.gd")
const ShopPriceServiceScript := preload("res://scripts/economy/shop_price_service.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const MERCHANTS_PATH := "res://data/content_packs/base/content/merchants.json"
const ECONOMY_PATH := "res://data/content_packs/base/content/economy_profiles.json"
const REWARD_PATHS: Array[String] = [
	"res://data/content_packs/base/content/items.json",
	"res://data/content_packs/base/content/blessings.json",
	"res://data/content_packs/base/content/curses.json",
]


class RuntimePlayer extends RefCounted:
	var state := {
		"generation": 1,
		"health": {"current_hp": 40.0, "max_hp": 100.0},
		"operations": [],
	}
	var publication_active := false
	var publication_count := 0

	func reward_effect_snapshot() -> Dictionary:
		return state.duplicate(true)

	func restore_reward_effect_snapshot(value: Dictionary) -> bool:
		if value.is_empty():
			return false
		state = value.duplicate(true)
		return true

	func reward_effect_apply_operation(operation: Dictionary) -> Dictionary:
		if operation.is_empty():
			return {"ok": false, "code": &"INVALID_OPERATION"}
		(state["operations"] as Array).append(operation.duplicate(true))
		if str(operation.get("effect_id", "")) == "heal":
			var health := state["health"] as Dictionary
			health["current_hp"] = minf(
				float(health["max_hp"]),
				float(health["current_hp"]) + float(operation.get("value", 0.0))
			)
		return {"ok": true, "code": &"OK"}

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


class FailingCommitInventory extends RefCounted:
	var inner: RefCounted

	func _init(value: RefCounted) -> void:
		inner = value

	func snapshot() -> Dictionary:
		return inner.call("snapshot")

	func prepare_purchase(
		transaction_id: String,
		state_snapshot: Dictionary,
		offer_id: String,
		expected_revision: int
	) -> Dictionary:
		return inner.call(
			"prepare_purchase", transaction_id, state_snapshot, offer_id, expected_revision
		)

	func commit_purchase(_ticket: Dictionary) -> Dictionary:
		return {"ok": false, "code": &"INJECTED_INVENTORY_COMMIT_FAILURE"}

	func rollback_purchase(value: Dictionary) -> Dictionary:
		return inner.call("rollback_purchase", value)

	func prepare_reroll(
		transaction_id: String,
		state_snapshot: Dictionary,
		expected_revision: int
	) -> Dictionary:
		return inner.call(
			"prepare_reroll", transaction_id, state_snapshot, expected_revision
		)

	func commit_reroll(ticket: Dictionary) -> Dictionary:
		return inner.call("commit_reroll", ticket)

	func rollback_reroll(value: Dictionary) -> Dictionary:
		return inner.call("rollback_reroll", value)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_real_purchase_reroll_and_restore(suite)
	_test_real_participants_compensate_inventory_commit_failure(suite)
	_test_real_heal_service_and_composite_rollback(suite)
	suite.finish(get_tree())


func _test_real_purchase_reroll_and_restore(suite) -> void:
	var fixture := _fixture(false)
	suite.assert_true(bool(fixture.get("ok", false)), "real services fixture configures")
	if not bool(fixture.get("ok", false)):
		return
	var inventory_before: Dictionary = fixture.inventory.snapshot()
	var economy_before: Dictionary = fixture.economy.snapshot()
	var first_offer := (inventory_before["offers"] as Array)[0] as Dictionary
	var purchased: Dictionary = fixture.runtime.purchase_reward(
		"tx_real_purchase",
		str(first_offer["offer_id"]),
		int(inventory_before["revision"]),
		int(economy_before["revision"])
	)
	suite.assert_true(bool(purchased.get("ok", false)), "real purchase commits")
	suite.assert_equal(
		fixture.economy.balance(),
		int(economy_before["balance"]) - int(first_offer["price"]),
		"real purchase debits the stored quote"
	)
	suite.assert_equal(
		(fixture.economy.ledger()[-1] as Dictionary).get("operation"),
		"gold_purchase",
		"real purchase appends the replay-authorized ledger operation"
	)
	suite.assert_true(
		_offer_sold(fixture.inventory.snapshot(), str(first_offer["offer_id"])),
		"real purchase persists sold state"
	)
	suite.assert_true(
		not (fixture.player.state["operations"] as Array).is_empty(),
		"real reward runtime applies typed player operations"
	)
	suite.assert_equal(fixture.player.publication_count, 1, "real purchase publishes once")

	var inventory_after_purchase: Dictionary = fixture.inventory.snapshot()
	var economy_after_purchase: Dictionary = fixture.economy.snapshot()
	var rerolled: Dictionary = fixture.runtime.reroll(
		"tx_real_reroll",
		int(inventory_after_purchase["revision"]),
		int(economy_after_purchase["revision"])
	)
	suite.assert_true(bool(rerolled.get("ok", false)), "real reroll commits")
	suite.assert_equal(fixture.inventory.snapshot().get("reroll_count"), 1, "real reroll advances once")
	suite.assert_equal(
		(fixture.economy.ledger()[-1] as Dictionary).get("operation"),
		"gold_reroll",
		"real reroll appends the replay-authorized ledger operation"
	)
	suite.assert_equal(
		fixture.inventory.open_inventory().get("snapshot"),
		fixture.inventory.snapshot(),
		"reopen returns the committed reroll inventory"
	)

	var saved := {
		"economy": fixture.economy.snapshot(),
		"inventory": fixture.inventory.snapshot(),
		"runtime": fixture.runtime.snapshot(),
		"player": fixture.player.reward_effect_snapshot(),
	}
	var restored := _fixture(false)
	suite.assert_true(bool(restored.get("ok", false)), "restore fixture configures")
	if not bool(restored.get("ok", false)):
		return
	suite.assert_true(restored.economy.restore_snapshot(saved["economy"]), "economy restores")
	suite.assert_true(restored.inventory.restore_snapshot(saved["inventory"]), "inventory restores")
	suite.assert_true(restored.runtime.restore_snapshot(saved["runtime"]), "runtime IDs restore")
	suite.assert_true(restored.player.restore_reward_effect_snapshot(saved["player"]), "player restores")
	var before_duplicate := _snapshots(restored)
	var duplicate: Dictionary = restored.runtime.purchase_reward(
		"tx_real_purchase",
		str(first_offer["offer_id"]),
		int(restored.inventory.snapshot()["revision"]),
		int(restored.economy.snapshot()["revision"])
	)
	suite.assert_equal(duplicate.get("code"), &"ALREADY_CONSUMED", "restored purchase ID stays consumed")
	suite.assert_equal(_snapshots(restored), before_duplicate, "restored duplicate mutates nothing")


func _test_real_participants_compensate_inventory_commit_failure(suite) -> void:
	var fixture := _fixture(true)
	suite.assert_true(bool(fixture.get("ok", false)), "failure fixture configures")
	if not bool(fixture.get("ok", false)):
		return
	var before := _snapshots(fixture)
	var inventory_before: Dictionary = fixture.inventory.snapshot()
	var offer := (inventory_before["offers"] as Array)[0] as Dictionary
	var result: Dictionary = fixture.runtime.purchase_reward(
		"tx_real_failure",
		str(offer["offer_id"]),
		int(inventory_before["revision"]),
		int(fixture.economy.snapshot()["revision"])
	)
	suite.assert_equal(result.get("code"), &"INVENTORY_COMMIT_FAILED", "injected failure is typed")
	suite.assert_equal(_snapshots(fixture), before, "real economy, inventory, and player all compensate")
	suite.assert_equal(fixture.player.publication_count, 0, "compensated failure publishes nothing")


func _test_real_heal_service_and_composite_rollback(suite) -> void:
	var fixture := _fixture(false)
	suite.assert_true(bool(fixture.get("ok", false)), "heal fixture configures")
	if not bool(fixture.get("ok", false)):
		return
	var before := _snapshots(fixture)
	var result: Dictionary = fixture.runtime.execute_service(
		"tx_real_heal", &"heal", "player", int(fixture.economy.snapshot()["revision"])
	)
	suite.assert_true(bool(result.get("ok", false)), "real heal service commits")
	suite.assert_close(
		float(fixture.player.state["health"]["current_hp"]), 70.0,
		"heal derives thirty percent max health from authority"
	)
	suite.assert_equal(fixture.economy.balance(), 960, "heal debits authoritative floor-one price")
	suite.assert_equal(
		(fixture.economy.ledger()[-1] as Dictionary).get("operation"),
		"gold_service",
		"heal records a typed service ledger fact"
	)
	suite.assert_equal(fixture.player.publication_count, 1, "heal publishes once after commit")
	var compensated: Dictionary = fixture.runtime.rollback_committed_transaction(result)
	suite.assert_true(bool(compensated.get("ok", false)), "heal composite receipt compensates")
	suite.assert_equal(_snapshots(fixture), before, "heal compensation restores player and economy")


func _fixture(fail_inventory_commit: bool) -> Dictionary:
	var merchants := _read_dictionary_array(MERCHANTS_PATH)
	var profiles := _read_dictionary_array(ECONOMY_PATH)
	var rewards := _reward_catalog()
	if merchants.is_empty() or profiles.size() != 1 or rewards.is_empty():
		return {"ok": false}
	var merchant := merchants[0]
	var profile := profiles[0]
	var price = ShopPriceServiceScript.new()
	var inventory = MerchantInventoryServiceScript.new()
	var configured: Dictionary = inventory.configure(
		20261002,
		merchant,
		profile,
		1,
		&"shop_node",
		rewards,
		_full_compatibility_context(),
		Callable(price, "reward_price")
	)
	if not bool(configured.get("ok", false)) or not bool(inventory.generate().get("ok", false)):
		return {"ok": false}
	var economy = RunEconomyStateScript.new()
	if not bool(economy.configure(profile, 1000).get("ok", false)):
		return {"ok": false}
	var player := RuntimePlayer.new()
	var reward = PlayerRewardEffectRuntimeScript.new()
	var service_authority = MerchantServiceAuthorityScript.new()
	if not bool(service_authority.configure(
		merchant, profile, 1, player, reward
	).get("ok", false)):
		return {"ok": false}
	var runtime_inventory: Object = FailingCommitInventory.new(inventory) if fail_inventory_commit else inventory
	var runtime = MerchantRuntimeScript.new()
	if not runtime.configure(economy, runtime_inventory, reward, player, service_authority):
		return {"ok": false}
	return {
		"ok": true,
		"economy": economy,
		"inventory": inventory,
		"runtime": runtime,
		"player": player,
		"price": price,
		"reward": reward,
		"service_authority": service_authority,
		"runtime_inventory": runtime_inventory,
	}


func _snapshots(fixture: Dictionary) -> Dictionary:
	return {
		"economy": fixture.economy.snapshot(),
		"inventory": fixture.inventory.snapshot(),
		"runtime": fixture.runtime.snapshot(),
		"service": fixture.service_authority.snapshot(),
		"player": fixture.player.reward_effect_snapshot(),
	}


func _offer_sold(snapshot: Dictionary, offer_id: String) -> bool:
	for offer_value: Variant in snapshot.get("offers", []):
		if offer_value is Dictionary:
			var offer := offer_value as Dictionary
			if str(offer.get("offer_id", "")) == offer_id:
				return bool(offer.get("sold", false))
	return false


func _full_compatibility_context() -> Dictionary:
	return {
		"archetype_ids": [
			"freeze_burst", "rewind_echo", "rift_trap", "accelerated_combo",
			"low_hp_void", "perfect_guard", "piercing_barrage", "echo_legion",
		],
		"weapon_ids": ["sword", "bow", "gun", "staff", "gauntlets"],
	}


func _reward_catalog() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for path: String in REWARD_PATHS:
		values.append_array(_read_dictionary_array(path))
	return values


func _read_dictionary_array(path: String) -> Array[Dictionary]:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var values: Array[Dictionary] = []
	if not parsed is Array:
		return values
	for entry: Variant in parsed as Array:
		if entry is Dictionary:
			values.append((entry as Dictionary).duplicate(true))
	return values
