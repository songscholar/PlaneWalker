extends Node

const PlayerRewardEffectRuntimeScript := preload(
	"res://scripts/items/player_reward_effect_runtime.gd"
)
const RunRuntimeFacadeScript := preload(
	"res://scripts/application/run_runtime_facade.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const FIRST_SEED := 20261001
const SEED_SEARCH_COUNT := 128
const GOLD_GRANT := 1000


class RuntimePlayer:
	extends RefCounted

	var state := {
		"generation": 1,
		"health": {"current_hp": 40.0, "max_hp": 100.0},
		"operations": [],
	}
	var publication_active := false
	var publication_count := 0

	func reward_effect_snapshot() -> Dictionary:
		return state.duplicate(true)

	func can_restore_reward_effect_snapshot(value: Dictionary) -> bool:
		return (
			not value.is_empty()
			and value.get("health") is Dictionary
			and value.get("operations") is Array
		)

	func restore_reward_effect_snapshot(value: Dictionary) -> bool:
		if not can_restore_reward_effect_snapshot(value):
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


class InertEncounterRunner:
	extends Node

	func start_encounter(_definition: Dictionary, _run_seed: int, _room_number: int) -> void:
		pass

	func cancel() -> void:
		pass

	func is_active() -> bool:
		return false

	func snapshot() -> Dictionary:
		return {"active": false}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_real_facade_merchant_flow_and_restore(suite)
	suite.finish(get_tree())


func _test_real_facade_merchant_flow_and_restore(suite) -> void:
	var fixture := _launch_fixture_with_wayfarer_shop(suite)
	if not bool(fixture.get("ok", false)):
		return
	var facade: RefCounted = fixture["facade"]
	var player: RuntimePlayer = fixture["player"]
	var path: Array[String] = fixture["path"]

	suite.assert_true(
		facade.has_method("grant_run_gold"),
		"Facade exposes the authoritative positive gold command"
	)
	suite.assert_true(
		facade.has_method("restore_launch_run"),
		"Facade exposes strict Launch RunState restoration"
	)
	if not facade.has_method("grant_run_gold"):
		return

	var before_grant: Dictionary = facade.call("snapshot")
	var granted = facade.call("grant_run_gold", "tx_test_shop_income", GOLD_GRANT, "test_room_reward")
	suite.assert_true(_result_ok(granted), "authoritative room income commits")
	if not _result_ok(granted):
		return
	var after_grant: Dictionary = facade.call("snapshot")
	suite.assert_equal(
		int(after_grant["revision"]),
		int(before_grant["revision"]) + 1,
		"gold income advances RunState exactly once"
	)
	var granted_economy := after_grant["run_economy"] as Dictionary
	suite.assert_equal(int(granted_economy["balance"]), GOLD_GRANT, "gold income reaches the canonical economy snapshot")
	suite.assert_equal(
		str((granted_economy["ledger"] as Array)[0].get("operation", "")),
		"gold_delta",
		"gold income records a typed economy fact"
	)
	var duplicate_grant_before := after_grant.duplicate(true)
	var duplicate_grant = facade.call("grant_run_gold", "tx_test_shop_income", GOLD_GRANT, "test_room_reward")
	suite.assert_true(not _result_ok(duplicate_grant), "duplicate gold transaction is rejected")
	suite.assert_equal(facade.call("snapshot"), duplicate_grant_before, "duplicate gold transaction mutates nothing")

	suite.assert_true(_follow_path_to_shop(suite, facade, path), "generated FloorPlan route reaches the Wayfarer shop")
	if str((facade.call("current_room_definition") as Dictionary).get("room_type", "")) != "shop":
		return

	var runner := InertEncounterRunner.new()
	add_child(runner)
	var room_runtime: Node = facade.call("create_room_runtime", runner)
	suite.assert_true(room_runtime != null, "Facade creates the production RoomRuntime for the shop")
	if room_runtime == null:
		runner.queue_free()
		return
	add_child(room_runtime)
	var before_open_revision := int((facade.call("snapshot") as Dictionary)["revision"])
	var opened = room_runtime.call("begin_current_room")
	suite.assert_true(_result_ok(opened), "RoomRuntime opens the current merchant")
	if not _result_ok(opened):
		room_runtime.queue_free()
		runner.queue_free()
		return
	var opened_snapshot: Dictionary = facade.call("snapshot")
	suite.assert_equal(
		int(opened_snapshot["revision"]),
		before_open_revision + 1,
		"first merchant open persists one node snapshot"
	)
	var view_before: Dictionary = facade.call("merchant_view_state")
	suite.assert_equal(str(view_before.get("merchant_id", "")), "merchant_wayfarer", "the generated room resolves its authored merchant")
	suite.assert_equal(int(view_before.get("gold", -1)), GOLD_GRANT, "merchant view reads canonical gold")
	var inventory_before := view_before.get("inventory", {}) as Dictionary
	suite.assert_true(not (inventory_before.get("offers", []) as Array).is_empty(), "real deterministic inventory exposes offers")
	if (inventory_before.get("offers", []) as Array).is_empty():
		room_runtime.queue_free()
		runner.queue_free()
		return
	var reopened = facade.call("open_current_merchant")
	suite.assert_true(_result_ok(reopened), "reopening an active merchant succeeds idempotently")
	suite.assert_equal(
		(facade.call("merchant_view_state") as Dictionary).get("inventory"),
		inventory_before,
		"reopening does not reroll deterministic inventory"
	)
	suite.assert_equal(
		int((facade.call("snapshot") as Dictionary)["revision"]),
		int(opened_snapshot["revision"]),
		"idempotent reopen writes no extra RunState revision"
	)

	var first_offer := (inventory_before["offers"] as Array)[0] as Dictionary
	var before_purchase_revision := int((facade.call("snapshot") as Dictionary)["revision"])
	var purchased = facade.call(
		"purchase_current_merchant", "tx_test_shop_purchase", str(first_offer["offer_id"])
	)
	suite.assert_true(_result_ok(purchased), "real Facade purchase commits")
	suite.assert_equal(str(purchased.get("code")), "OK", "real Facade purchase returns the stable success code")
	if not _result_ok(purchased):
		room_runtime.queue_free()
		runner.queue_free()
		return
	suite.assert_equal(player.publication_count, 1, "purchase publishes player feedback exactly once")
	suite.assert_equal(
		int((facade.call("snapshot") as Dictionary)["revision"]),
		before_purchase_revision + 1,
		"purchase advances RunState exactly once"
	)
	var after_purchase_view: Dictionary = facade.call("merchant_view_state")
	suite.assert_true(
		_offer_sold(after_purchase_view["inventory"], str(first_offer["offer_id"])),
		"purchased offer is authoritatively sold"
	)
	var duplicate_purchase_snapshot: Dictionary = facade.call("snapshot")
	var duplicate_purchase = facade.call(
		"purchase_current_merchant", "tx_test_shop_purchase", str(first_offer["offer_id"])
	)
	suite.assert_true(not _result_ok(duplicate_purchase), "duplicate purchase transaction is rejected")
	suite.assert_equal(player.publication_count, 1, "duplicate purchase publishes nothing")
	suite.assert_equal(facade.call("snapshot"), duplicate_purchase_snapshot, "duplicate purchase mutates no RunState")

	var before_reroll_revision := int((facade.call("snapshot") as Dictionary)["revision"])
	var rerolled = facade.call("reroll_current_merchant", "tx_test_shop_reroll")
	suite.assert_true(_result_ok(rerolled), "real Facade reroll commits")
	if not _result_ok(rerolled):
		room_runtime.queue_free()
		runner.queue_free()
		return
	var after_reroll_view: Dictionary = facade.call("merchant_view_state")
	suite.assert_equal(
		int((after_reroll_view["inventory"] as Dictionary).get("reroll_count", -1)),
		1,
		"reroll count advances once"
	)
	suite.assert_equal(
		int((facade.call("snapshot") as Dictionary)["revision"]),
		before_reroll_revision + 1,
		"reroll advances RunState exactly once"
	)
	suite.assert_equal(player.publication_count, 1, "reroll publishes no player reward feedback")

	var hp_before_heal := float(player.state["health"]["current_hp"])
	var before_heal_revision := int((facade.call("snapshot") as Dictionary)["revision"])
	var healed = facade.call(
		"execute_current_merchant_service", "tx_test_shop_heal", &"heal", "player"
	)
	suite.assert_true(_result_ok(healed), "real Facade heal service commits")
	if not _result_ok(healed):
		room_runtime.queue_free()
		runner.queue_free()
		return
	suite.assert_true(
		float(player.state["health"]["current_hp"]) > hp_before_heal,
		"heal service mutates the real player participant"
	)
	suite.assert_equal(player.publication_count, 2, "heal publishes player feedback exactly once")
	suite.assert_equal(
		int((facade.call("snapshot") as Dictionary)["revision"]),
		before_heal_revision + 1,
		"heal advances RunState exactly once"
	)
	var healed_hp := float(player.state["health"]["current_hp"])
	var gold_before_sale := int((facade.call("merchant_view_state") as Dictionary)["gold"])
	var before_sale_revision := int((facade.call("snapshot") as Dictionary)["revision"])
	var sold = facade.call(
		"execute_current_merchant_service",
		"tx_test_shop_sell_reward",
		&"sell_reward",
		str(first_offer["reward_id"])
	)
	suite.assert_true(_result_ok(sold), "real Facade sell_reward service commits after purchase and heal")
	if not _result_ok(sold):
		room_runtime.queue_free()
		runner.queue_free()
		return
	suite.assert_equal(
		float(player.state["health"]["current_hp"]),
		healed_hp,
		"selling a reward preserves the non-build heal overlay"
	)
	suite.assert_true(
		int((facade.call("merchant_view_state") as Dictionary)["gold"]) > gold_before_sale,
		"selling a reward credits the authoritative economy"
	)
	suite.assert_equal(player.publication_count, 3, "sell_reward publishes player feedback exactly once")
	suite.assert_equal(
		int((facade.call("snapshot") as Dictionary)["revision"]),
		before_sale_revision + 1,
		"sell_reward advances RunState exactly once"
	)

	var saved_run_state: Dictionary = facade.call("snapshot")
	_assert_persisted_transactions(suite, saved_run_state)
	var saved_player_state := player.reward_effect_snapshot()
	var saved_merchant_view: Dictionary = facade.call("merchant_view_state")

	if facade.has_method("restore_launch_run"):
		var restored_player := RuntimePlayer.new()
		suite.assert_true(
			restored_player.restore_reward_effect_snapshot(saved_player_state),
			"restore fixture installs the matching player snapshot"
		)
		var restored_facade = RunRuntimeFacadeScript.new()
		suite.assert_true(_result_ok(restored_facade.boot()), "restore Facade boots from real base content")
		var restored_reward_runtime = PlayerRewardEffectRuntimeScript.new()
		suite.assert_true(
			restored_facade.configure_merchant_effect_authority(restored_reward_runtime, restored_player),
			"restore Facade installs real reward participants"
		)
		var restored = restored_facade.call("restore_launch_run", saved_run_state.duplicate(true))
		suite.assert_true(_result_ok(restored), "strict Launch RunState restore succeeds")
		if _result_ok(restored):
			suite.assert_equal(restored_facade.snapshot(), saved_run_state, "restore installs the exact authoritative RunState")
			var restored_view: Dictionary = restored_facade.merchant_view_state()
			suite.assert_equal(restored_view, saved_merchant_view, "restore reconstructs the live merchant session exactly")
			var restore_revision := int(restored_facade.snapshot()["revision"])
			var restored_open = restored_facade.open_current_merchant()
			suite.assert_true(_result_ok(restored_open), "restored merchant reopens without regeneration")
			suite.assert_equal(restored_facade.merchant_view_state(), saved_merchant_view, "restored reopen preserves the saved inventory")
			suite.assert_equal(int(restored_facade.snapshot()["revision"]), restore_revision, "restored reopen adds no revision")
			var restored_duplicate = restored_facade.purchase_current_merchant(
				"tx_test_shop_purchase", str(first_offer["offer_id"])
			)
			suite.assert_true(not _result_ok(restored_duplicate), "restored completed transaction ID stays consumed")
			var restored_sale_duplicate = restored_facade.execute_current_merchant_service(
				"tx_test_shop_sell_reward", &"sell_reward", str(first_offer["reward_id"])
			)
			suite.assert_true(
				not _result_ok(restored_sale_duplicate),
				"restored sell transaction ID stays consumed"
			)
			suite.assert_equal(restored_player.publication_count, 0, "restored duplicate publishes no feedback")

	var before_leave_revision := int((facade.call("snapshot") as Dictionary)["revision"])
	var left = room_runtime.call("leave_current_shop")
	suite.assert_true(_result_ok(left), "RoomRuntime explicitly leaves and completes the shop")
	if _result_ok(left):
		suite.assert_equal(
			int((facade.call("snapshot") as Dictionary)["revision"]),
			before_leave_revision + 1,
			"explicit shop leave advances RunState exactly once"
		)
	room_runtime.queue_free()
	runner.queue_free()


func _launch_fixture_with_wayfarer_shop(suite) -> Dictionary:
	for seed_offset: int in range(SEED_SEARCH_COUNT):
		var player := RuntimePlayer.new()
		var facade = RunRuntimeFacadeScript.new()
		var booted = facade.boot()
		if not _result_ok(booted):
			continue
		var reward_runtime = PlayerRewardEffectRuntimeScript.new()
		if not facade.configure_merchant_effect_authority(reward_runtime, player):
			continue
		var seed := FIRST_SEED + seed_offset
		var started = facade.start_run(_launch_config(seed), "merchant-facade-%d" % seed)
		if not _result_ok(started):
			continue
		var plan := (facade.snapshot() as Dictionary).get("floor_plan", {}) as Dictionary
		var path := _path_to_wayfarer_shop(plan)
		if not path.is_empty():
			suite.assert_true(true, "real base content generates a reachable Wayfarer shop")
			return {
				"ok": true,
				"facade": facade,
				"player": player,
				"reward_runtime": reward_runtime,
				"path": path,
				"seed": seed,
			}
	suite.assert_true(false, "deterministic seed search finds a reachable Wayfarer shop")
	return {"ok": false}


func _path_to_wayfarer_shop(plan: Dictionary) -> Array[String]:
	var target_id := ""
	for node_value: Variant in plan.get("nodes", []):
		if not node_value is Dictionary:
			continue
		var node := node_value as Dictionary
		if (
			str(node.get("room_type", "")) == "shop"
			and str(node.get("merchant_id", "")) == "merchant_wayfarer"
		):
			target_id = str(node.get("id", ""))
			break
	if target_id.is_empty():
		return []
	var entry_id := str(plan.get("entry_node_id", "entry"))
	var queue: Array[String] = [entry_id]
	var paths: Dictionary = {entry_id: []}
	while not queue.is_empty():
		var source_id: String = queue.pop_front()
		if source_id == target_id:
			var resolved: Array[String] = []
			for edge_id: Variant in paths[source_id]:
				resolved.append(str(edge_id))
			return resolved
		for edge_value: Variant in plan.get("edges", []):
			if not edge_value is Dictionary:
				continue
			var edge := edge_value as Dictionary
			if str(edge.get("source_node_id", "")) != source_id or bool(edge.get("locked", false)):
				continue
			var destination_id := str(edge.get("destination_node_id", ""))
			if destination_id.is_empty() or paths.has(destination_id):
				continue
			var next_path: Array = (paths[source_id] as Array).duplicate()
			next_path.append(str(edge.get("id", "")))
			paths[destination_id] = next_path
			queue.append(destination_id)
	return []


func _follow_path_to_shop(suite, facade: RefCounted, path: Array[String]) -> bool:
	for path_index: int in range(path.size()):
		var revision := int((facade.call("snapshot") as Dictionary)["revision"])
		var begun = facade.call("begin_route_transition", StringName(path[path_index]), revision)
		suite.assert_true(_result_ok(begun), "shop route edge %d begins" % (path_index + 1))
		if not _result_ok(begun):
			return false
		var transition_id := str(begun.get("context").get("transition_id", ""))
		var finalized = facade.call("finalize_route_transition", transition_id, int(begun.get("new_revision")))
		suite.assert_true(_result_ok(finalized), "shop route edge %d finalizes" % (path_index + 1))
		if not _result_ok(finalized):
			return false
		var confirmed = facade.call("confirm_route_transition", transition_id, int(finalized.get("new_revision")))
		suite.assert_true(_result_ok(confirmed), "shop route edge %d confirms" % (path_index + 1))
		if not _result_ok(confirmed):
			return false
		var room := facade.call("current_room_definition") as Dictionary
		if path_index == path.size() - 1:
			return (
				str(room.get("room_type", "")) == "shop"
				and str(room.get("merchant_id", "")) == "merchant_wayfarer"
			)
		var completed = facade.call("complete_current_room")
		suite.assert_true(_result_ok(completed), "intermediate generated room %d completes" % (path_index + 1))
		if not _result_ok(completed):
			return false
	return false


func _assert_persisted_transactions(suite, snapshot: Dictionary) -> void:
	var economy := snapshot.get("run_economy", {}) as Dictionary
	var merchant := snapshot.get("merchant_state", {}) as Dictionary
	var ledger := economy.get("ledger", []) as Array
	var nodes := merchant.get("nodes", []) as Array
	suite.assert_equal(ledger.size(), 5, "income, purchase, reroll, heal, and sale persist five economy facts")
	suite.assert_equal(nodes.size(), 1, "one visited shop persists one merchant node")
	if nodes.size() != 1:
		return
	var transactions := (nodes[0] as Dictionary).get("transactions", []) as Array
	suite.assert_equal(transactions.size(), 4, "purchase, reroll, heal, and sale persist four merchant facts")
	var expected_ids := [
		"tx_test_shop_purchase",
		"tx_test_shop_reroll",
		"tx_test_shop_heal",
		"tx_test_shop_sell_reward",
	]
	for index: int in range(mini(transactions.size(), expected_ids.size())):
		var fact := transactions[index] as Dictionary
		suite.assert_equal(int(fact.get("sequence", -1)), index + 1, "merchant fact sequence is contiguous")
		suite.assert_equal(str(fact.get("transaction_id", "")), expected_ids[index], "merchant fact keeps transaction identity")
		var ledger_entry := _ledger_entry(ledger, expected_ids[index])
		suite.assert_true(not ledger_entry.is_empty(), "merchant fact has a matching economy ledger entry")
		if not ledger_entry.is_empty():
			suite.assert_equal(
				int(fact.get("economy_revision", -1)),
				int(ledger_entry.get("revision", -2)),
				"merchant fact references the exact economy revision"
			)
			suite.assert_equal(
				int(fact.get("amount", -1)),
				absi(int(ledger_entry.get("amount", 0))),
				"merchant fact amount matches the economy debit"
			)


func _ledger_entry(ledger: Array, transaction_id: String) -> Dictionary:
	for entry_value: Variant in ledger:
		if entry_value is Dictionary and str((entry_value as Dictionary).get("transaction_id", "")) == transaction_id:
			return (entry_value as Dictionary).duplicate(true)
	return {}


func _offer_sold(inventory: Dictionary, offer_id: String) -> bool:
	for offer_value: Variant in inventory.get("offers", []):
		if offer_value is Dictionary:
			var offer := offer_value as Dictionary
			if str(offer.get("offer_id", "")) == offer_id:
				return bool(offer.get("sold", false))
	return false


func _launch_config(seed: int) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": seed,
	}


func _result_ok(result: Variant) -> bool:
	return result != null and bool(result.get("ok"))
