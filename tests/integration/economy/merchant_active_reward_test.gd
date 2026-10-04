extends Node

const AdapterScript := preload("res://scripts/economy/merchant_reward_runtime.gd")
const FacadeScript := preload("res://scripts/application/run_runtime_facade.gd")
const MerchantInventoryScript := preload("res://scripts/economy/merchant_inventory_service.gd")
const MerchantRuntimeScript := preload("res://scripts/economy/merchant_runtime.gd")
const MerchantDefinitionScript := preload("res://scripts/dungeon/merchant_definition.gd")
const EconomyProfileScript := preload("res://scripts/dungeon/economy_profile.gd")
const EconomyScript := preload("res://scripts/economy/run_economy_state.gd")
const PriceScript := preload("res://scripts/economy/shop_price_service.gd")
const PassiveRuntimeScript := preload("res://scripts/items/player_reward_effect_runtime.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_active_purchase_and_composite_rollback(suite)
	_test_active_purchase_compensates_state_sink_rejection(suite)
	_test_prepared_active_purchase_rejects_changed_equipment(suite)
	_test_passive_protocol_and_invalid_active_definition(suite)
	await get_tree().process_frame
	suite.finish(get_tree())


func _test_active_purchase_and_composite_rollback(suite) -> void:
	var fixture := _fixture(suite, false)
	if not fixture.get("ok", false):
		return
	var before := _snapshots(fixture)
	var offer: Dictionary = fixture.inventory.snapshot()["offers"][0]
	var result: Dictionary = fixture.runtime.purchase_reward("tx_active_buy", offer["offer_id"], int(fixture.inventory.snapshot()["revision"]), int(fixture.economy.snapshot()["revision"]))
	suite.assert_true(result.get("ok", false), "real active merchant purchase commits: %s" % result)
	if result.get("ok", false):
		suite.assert_equal(fixture.player.active_item_snapshot()["definition"]["id"], offer["reward_id"], "purchase equips the authored active")
		suite.assert_equal(fixture.economy.balance(), 600 - int(offer["price"]), "active purchase debits its quote")
		suite.assert_equal(result["reward_receipt"].get("kind"), "active_item", "active receipt is separate from passive receipt")
		suite.assert_true(fixture.runtime.rollback_committed_transaction(result).get("ok", false), "committed active purchase compensates")
		suite.assert_equal(_snapshots(fixture), before, "active compensation restores economy inventory runtime and full Player")
	fixture.player.queue_free()


func _test_active_purchase_compensates_state_sink_rejection(suite) -> void:
	var fixture := _fixture(suite, true)
	if not fixture.get("ok", false):
		return
	var equipped: Dictionary = fixture.player.equip_active_item(fixture.actives[-1])
	suite.assert_true(equipped.get("ok", false), "rollback fixture begins with an occupied active slot")
	var before := _snapshots(fixture)
	var offer: Dictionary = fixture.inventory.snapshot()["offers"][0]
	var result: Dictionary = fixture.runtime.purchase_reward("tx_active_rejected", offer["offer_id"], int(fixture.inventory.snapshot()["revision"]), int(fixture.economy.snapshot()["revision"]))
	suite.assert_equal(result.get("code"), &"STATE_COMMIT_FAILED", "state sink rejection remains typed")
	suite.assert_equal(_snapshots(fixture), before, "late rejection restores occupied slot and every participant exactly")
	suite.assert_true(fixture.player.reward_effect_begin_publication(), "compensated active purchase releases publication ownership")
	suite.assert_true(fixture.player.reward_effect_rollback_publication(), "later publication can close cleanly")
	fixture.player.queue_free()


func _test_prepared_active_purchase_rejects_changed_equipment(suite) -> void:
	var fixture := _fixture(suite, false)
	if not fixture.get("ok", false):
		return
	var prepared: Dictionary = fixture.adapter.prepare(fixture.actives[0], fixture.player.reward_effect_snapshot())
	suite.assert_true(prepared.get("ok", false), "active purchase freezes full Player before image")
	fixture.player.equip_active_item(fixture.actives[-1])
	var changed: Dictionary = fixture.player.full_player_replay_snapshot()
	var rejected: Dictionary = fixture.adapter.commit(prepared.get("plan", {}), fixture.player)
	suite.assert_equal(rejected.get("code"), &"STALE_PLAYER_SNAPSHOT", "active equipment change invalidates the prepared purchase")
	suite.assert_equal(fixture.player.full_player_replay_snapshot(), changed, "stale active purchase preserves newer equipment")
	fixture.player.queue_free()


func _test_passive_protocol_and_invalid_active_definition(suite) -> void:
	var fixture := _fixture(suite, false)
	if not fixture.get("ok", false):
		return
	var registry: RefCounted = fixture.facade.content_registry()
	var definition: Dictionary = registry.get_content(&"rewind_salve")
	var snapshot: Dictionary = fixture.player.reward_effect_snapshot()
	var delegate = PassiveRuntimeScript.new()
	var expected: Dictionary = delegate.prepare(definition, snapshot)
	var prepared: Dictionary = fixture.adapter.prepare(definition, snapshot)
	suite.assert_equal(prepared, expected, "passive prepare preserves its established protocol")
	var applied: Dictionary = fixture.adapter.commit(prepared.get("plan", {}), fixture.player)
	suite.assert_true(applied.get("ok", false), "passive delegate still commits")
	suite.assert_true(fixture.adapter.rollback(applied.get("receipt", {}), fixture.player).get("ok", false), "passive delegate still rolls back")
	suite.assert_equal(fixture.player.reward_effect_snapshot(), snapshot, "passive rollback restores the original effect snapshot")
	var forged: Dictionary = fixture.actives[0].duplicate(true)
	forged["active_parameters"] = {}
	var active_before: Dictionary = fixture.player.full_player_replay_snapshot()
	suite.assert_true(not fixture.adapter.prepare(forged, fixture.player.reward_effect_snapshot()).get("ok", false), "invalid authored active parameters fail before purchase")
	suite.assert_equal(fixture.player.full_player_replay_snapshot(), active_before, "invalid active preparation mutates nothing")
	fixture.player.queue_free()


func _fixture(suite, reject_sink: bool) -> Dictionary:
	var facade = FacadeScript.new()
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 20261003}
	if not facade.boot().ok or not facade.start_run(config, "merchant_active_test").ok:
		suite.assert_true(false, "active merchant content authority boots")
		return {"ok": false}
	var player: Node = PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var accepted: Dictionary = facade.active_loadout()
	var player_config: Dictionary = facade.snapshot()["config"].duplicate(true)
	player_config["character_profile"] = accepted["character_profile"]
	player_config["weapon_profile"] = accepted["weapon_profile"]
	player_config["character_talent_definitions"] = accepted["character_talents"]
	var configured: bool = player.configure_run(&"merchant_active_test") and player.configure_loadout(player_config)
	EventBus.room_started.emit("merchant_active_test", &"shop_active_test", 0)
	player.advance_action_frame({})
	suite.assert_true(configured and not player.full_player_replay_snapshot().is_empty(), "real Player exposes full Launch replay ownership")
	var registry: RefCounted = facade.content_registry()
	var actives: Array[Dictionary] = []
	for definition: Dictionary in registry.get_by_category(&"item", &"LAUNCH"):
		if definition.get("item_mode", "") == "active":
			actives.append(definition)
	var profile := _definition_fields(registry.get_content(&"launch_economy_v1"), EconomyProfileScript.ROOT_FIELDS)
	var merchant := _definition_fields(registry.get_content(&"merchant_chronomancer"), MerchantDefinitionScript.ROOT_FIELDS)
	var price = PriceScript.new()
	var inventory = MerchantInventoryScript.new()
	var context := {"archetype_ids": ["freeze_burst", "rewind_echo", "rift_trap", "accelerated_combo", "low_hp_void", "perfect_guard", "piercing_barrage", "echo_legion"], "weapon_ids": ["sword"]}
	var inventory_configured: Dictionary = inventory.configure(20261003, merchant, profile, 2, &"shop_active_test", actives, context, Callable(price, "reward_price"))
	suite.assert_true(inventory_configured.get("ok", false), "authored active inventory configures: %s" % inventory_configured)
	var economy = EconomyScript.new()
	var adapter = AdapterScript.new(PassiveRuntimeScript.new(), player)
	var runtime = MerchantRuntimeScript.new()
	var generated_result: Dictionary = inventory.generate() if inventory_configured.get("ok", false) else {}
	suite.assert_true(generated_result.get("ok", false), "authored active inventory generates: %s" % generated_result)
	var generated: bool = generated_result.get("ok", false)
	var ready: bool = configured and generated and economy.configure(profile, 600).get("ok", false)
	ready = ready and runtime.configure(economy, inventory, adapter, player, null, func(_receipt: Dictionary) -> bool: return not reject_sink)
	suite.assert_true(ready, "real active-only authored merchant fixture configures")
	if not ready:
		player.queue_free()
	return {"ok": ready, "facade": facade, "player": player, "inventory": inventory, "economy": economy, "adapter": adapter, "runtime": runtime, "actives": actives, "price": price}


func _snapshots(fixture: Dictionary) -> Dictionary:
	return {"economy": fixture.economy.snapshot(), "inventory": fixture.inventory.snapshot(), "runtime": fixture.runtime.snapshot(), "player": fixture.player.full_player_replay_snapshot()}


func _definition_fields(definition: Dictionary, fields: Array) -> Dictionary:
	var source := {}
	for field: String in fields:
		source[field] = definition[field]
	return source
