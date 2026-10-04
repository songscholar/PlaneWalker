extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Facade := preload("res://scripts/application/run_runtime_facade.gd")
const RewardRuntime := preload("res://scripts/items/player_reward_effect_runtime.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Phases := preload("res://scripts/application/run_phase.gd")
const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")


class FailingEffectRuntime extends RefCounted:
	var runtime = RewardRuntime.new()

	func prepare(definition: Dictionary, before: Dictionary) -> Dictionary:
		return runtime.prepare(definition, before)

	func commit(plan: Dictionary, player: Object) -> Dictionary:
		runtime.commit(plan, player)
		return {"ok": false, "code": &"INJECTED_EFFECT_FAILURE"}

	func rollback(receipt: Dictionary, player: Object) -> Dictionary:
		return runtime.rollback(receipt, player)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	var facade = Facade.new()
	suite.assert_true(facade.boot().ok, "reward fixture boots real content")
	suite.assert_true(facade.start_run({
		"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer",
		"weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal", "seed": 20261004,
	}, "dungeon-rewards").ok, "reward fixture starts five-floor run")
	var player := PlayerScene.instantiate()
	add_child(player)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var loadout: Dictionary = facade.active_loadout()
	var config: Dictionary = facade.snapshot()["config"].duplicate(true)
	config["character_profile"] = loadout["character_profile"]
	config["weapon_profile"] = loadout["weapon_profile"]
	suite.assert_true(player.configure_run(&"dungeon-rewards"), "player accepts run identity")
	suite.assert_true(player.configure_loadout(config), "player receives canonical loadout")
	suite.assert_true(facade.configure_merchant_effect_authority(RewardRuntime.new(), player), "rewards bind physical Player")
	for api: String in ["open_current_room_reward", "commit_current_reward", "resolve_current_room_interaction", "room_interaction_view_state", "event_reward_offer", "submit_current_event_reward", "merchant_service_choices"]:
		suite.assert_true(facade.has_method(api), "production command exists: %s" % api)
	var choices: Array = facade.route_choices()
	var edge: String = str(choices[0]["edge_id"])
	var begun = facade.begin_route_transition(StringName(edge), int(facade.snapshot()["revision"]))
	suite.assert_true(begun.ok, "route starts")
	if begun.ok:
		var transition_id: String = begun.context["transition_id"]
		var finalized = facade.finalize_route_transition(transition_id, begun.new_revision)
		suite.assert_true(finalized.ok, "route finalizes")
		if finalized.ok:
			suite.assert_true(facade.confirm_route_transition(transition_id, finalized.new_revision).ok, "route confirms")
			suite.assert_true(facade.enter_current_room().ok, "combat room enters")
			var before: Dictionary = facade.snapshot()
			suite.assert_true(facade.complete_current_room().ok, "combat room resolves")
			var after: Dictionary = facade.snapshot()
			suite.assert_true(int(after["run_economy"]["balance"]) > int(before["run_economy"]["balance"]), "combat produces actual room gold")
			var once: Dictionary = after.duplicate(true)
			suite.assert_true(not facade.complete_current_room().ok, "repeated room completion is rejected")
			suite.assert_equal(facade.snapshot(), once, "duplicate clear cannot pay twice")
			if facade.has_method("open_current_room_reward"):
				var opened = facade.call("open_current_room_reward", int(after["revision"]))
				suite.assert_true(opened.ok, "cleared combat offers a real reward draft")
				if opened.ok:
					var offer: Dictionary = opened.context["offer"]
					var original_node: String = str(after["floor_plan"]["current_node_id"])
					var physical_before: Dictionary = player.reward_effect_snapshot()
					var open_state: Dictionary = facade.snapshot()
					var loaded: Dictionary = SaveEnvelopeScript._normalize_profile_payload({"active_run_state": JSON.parse_string(JSON.stringify(open_state))}, 3)["active_run_state"]
					suite.assert_equal(loaded, open_state, "open ordinary draft survives persisted JSON roundtrip")
					var restored = Facade.new()
					suite.assert_true(restored.boot().ok, "fresh Facade boots for open-draft restore")
					suite.assert_true(restored.configure_merchant_effect_authority(RewardRuntime.new(), player), "fresh Facade binds physical Player")
					var restored_result = restored.restore_launch_run(loaded)
					suite.assert_true(restored_result.ok, "fresh Facade restores an open ordinary draft: %s" % str(restored_result.context))
					if restored_result.ok:
						facade = restored
						suite.assert_equal(facade.snapshot(), open_state, "fresh Facade preserves the complete open offer")
						suite.assert_true(facade.configure_merchant_effect_authority(FailingEffectRuntime.new(), player), "fixture injects physical effect failure")
						var failed = facade.commit_current_reward(offer["offer_id"], offer["options"][0]["option_id"], offer["revision"])
						suite.assert_true(not failed.ok, "partially applied physical reward failure is rejected")
						suite.assert_equal(player.reward_effect_snapshot(), physical_before, "physical reward rollback restores Player exactly")
						suite.assert_equal(facade.snapshot(), open_state, "physical reward failure preserves canonical draft and ledger")
						suite.assert_true(facade.configure_merchant_effect_authority(RewardRuntime.new(), player), "fixture restores production reward runtime")
					var committed = facade.call("commit_current_reward", offer["offer_id"], offer["options"][0]["option_id"], offer["revision"])
					suite.assert_true(committed.ok, "canonical reward applies to domain and Player")
					suite.assert_true(player.reward_effect_snapshot() != physical_before, "selected reward changes physical Player")
					var rewarded: Dictionary = facade.snapshot()
					suite.assert_equal(rewarded["phase"], Phases.Value.ROOM_RESOLVING, "Launch selection returns to route choice")
					suite.assert_equal(rewarded["floor_plan"]["current_node_id"], original_node, "reward does not advance the linear M1 room counter")
					suite.assert_equal(rewarded["build"]["reward_history"].size(), 1, "reward enters canonical ledger once")
					var rejected = facade.call("commit_current_reward", offer["offer_id"], offer["options"][0]["option_id"], offer["revision"])
					suite.assert_true(not rejected.ok, "duplicate reward rejected")
					suite.assert_equal(facade.snapshot(), rewarded, "duplicate reward has no domain mutation")
	_assert_rest_healing(suite, facade, player)
	player.queue_free()
	facade = null
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _assert_rest_healing(suite, facade: RefCounted, player: Node) -> void:
	var reached_rest := false
	for step: int in range(6):
		var choices: Array = facade.route_choices()
		if choices.is_empty():
			break
		var begun = facade.begin_route_transition(StringName(str(choices[0]["edge_id"])), int(facade.snapshot()["revision"]))
		suite.assert_true(begun.ok, "rest regression begins route")
		if not begun.ok:
			break
		var finalized = facade.finalize_route_transition(begun.context["transition_id"], begun.new_revision)
		suite.assert_true(finalized.ok, "rest regression finalizes route")
		if not finalized.ok:
			break
		suite.assert_true(facade.confirm_route_transition(begun.context["transition_id"], finalized.new_revision).ok, "rest regression confirms route")
		var room: Dictionary = facade.current_room_definition()
		if str(room["room_type"]) == "rest":
			reached_rest = true
			suite.assert_true(facade.enter_current_room().ok, "rest room enters")
			var injured: Dictionary = player.reward_effect_snapshot()
			injured["health"]["current_hp"] = float(injured["health"]["max_hp"]) * 0.5
			suite.assert_true(player.restore_reward_effect_snapshot(injured), "fixture injures physical Player")
			var healed = facade.resolve_current_room_interaction(&"heal", int(facade.snapshot()["revision"]))
			suite.assert_true(healed.ok, "rest heals after node clear without stale event-route drift: %s" % str(healed.context))
			var state: Dictionary = facade.snapshot()
			suite.assert_equal(float(state["resources"]["health"]["current"]), float(player.reward_effect_snapshot()["health"]["current_hp"]), "rest health remains authoritative in Save snapshot")
			suite.assert_true(float(player.reward_effect_snapshot()["health"]["current_hp"]) > float(injured["health"]["current_hp"]), "rest physically heals")
			break
		if str(room["room_type"]) == "event":
			suite.assert_true(facade.open_current_event().ok, "rest regression opens preceding event")
			suite.assert_true(facade.choose_current_event_option(&"decline", int(facade.snapshot()["revision"])).ok, "rest regression resolves preceding event")
			suite.assert_true(facade.dismiss_current_event(int(facade.snapshot()["revision"])).ok, "rest regression dismisses preceding event")
		else:
			suite.assert_true(facade.enter_current_room().ok, "rest regression enters preceding room")
		suite.assert_true(facade.complete_current_room().ok, "rest regression completes preceding room")
	suite.assert_true(reached_rest, "real route reaches authored rest room")
