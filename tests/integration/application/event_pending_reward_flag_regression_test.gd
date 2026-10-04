extends Node

const FacadeScript := preload("res://scripts/application/run_runtime_facade.gd")
const EffectRuntimeScript := preload("res://scripts/items/player_reward_effect_runtime.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const CompatibilityScript := preload("res://scripts/rewards/reward_compatibility.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var facade = FacadeScript.new()
	suite.assert_true(facade.boot().ok, "pending-reward regression boots real content")
	var config := {
		"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer",
		"weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal", "seed": 20261001,
	}
	suite.assert_true(facade.start_run(config, "pending-reward-flag-regression").ok, "regression starts a deterministic Launch run")
	var player: Node = PlayerScene.instantiate()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(player)
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	var accepted: Dictionary = facade.active_loadout()
	suite.assert_true(player.configure_run(&"pending-reward-flag-regression"), "regression binds the actual run identity")
	config["character_profile"] = accepted["character_profile"]
	config["weapon_profile"] = accepted["weapon_profile"]
	suite.assert_true(player.configure_loadout(config), "regression configures the real Player")
	suite.assert_true(facade.configure_merchant_effect_authority(EffectRuntimeScript.new(), player), "regression binds production reward effects")
	var target_reached := false
	for floor_index: int in range(3):
		for step: int in range(16):
			var choices: Array = facade.route_choices()
			if choices.is_empty():
				suite.assert_true(false, "regression route remains reachable")
				break
			var choice := choices[(20261001 + step) % choices.size()] as Dictionary
			var begun = facade.begin_route_transition(StringName(str(choice["edge_id"])), facade.snapshot()["revision"])
			suite.assert_true(begun.ok, "regression route begins")
			if not begun.ok:
				break
			var finalized = facade.finalize_route_transition(begun.context["transition_id"], begun.new_revision)
			suite.assert_true(finalized.ok, "regression route enters")
			if not finalized.ok:
				break
			var confirmed = facade.confirm_route_transition(begun.context["transition_id"], finalized.new_revision)
			suite.assert_true(confirmed.ok, "regression route confirms")
			facade.publish_confirmed_route_event_facts(confirmed.context.get("event_facts", []))
			var room: Dictionary = facade.current_room_definition()
			EventBus.room_started.emit(str(player.current_run_id()), StringName(str(room["node_id"])), facade.snapshot()["revision"])
			player.advance_action_frame({})
			if str(room.get("room_type", "")) == "event":
				var opened = facade.open_current_event()
				suite.assert_true(opened.ok, "regression opens authored event")
				var view: Dictionary = facade.event_view_state()
				if floor_index == 2 and str(view.get("event_id", "")) == "event_perfect_rewind":
					target_reached = true
					var committed = facade.choose_current_event_option(&"commit", facade.snapshot()["revision"])
					suite.assert_true(committed.ok, "perfect rewind commits reward continuation and narrative flag atomically: %s %s" % [str(committed.code), str(committed.context)])
					if committed.ok:
						_assert_pending_and_resolve(suite, facade)
					break
				var declined = facade.choose_current_event_option(&"decline", facade.snapshot()["revision"])
				suite.assert_true(declined.ok, "regression declines earlier events without invented completion")
				suite.assert_true(facade.dismiss_current_event(facade.snapshot()["revision"]).ok, "regression dismisses earlier event")
			var completed = facade.complete_current_room()
			suite.assert_true(completed.ok, "regression completes preceding domain room")
			if str(room.get("room_type", "")) == "boss":
				break
		if target_reached:
			break
		suite.assert_true(facade.start_next_floor().ok, "regression transitions to the next floor")
	suite.assert_true(target_reached, "real three-floor route reaches the perfect-rewind branch")
	player.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _assert_pending_and_resolve(suite, facade: RefCounted) -> void:
	var state: Dictionary = facade.call("snapshot")
	var runtime := state["dungeon_event_runtime"] as Dictionary
	var parts := runtime["consequence_runtime"]["participant_snapshots"] as Dictionary
	var event_state := parts["event_state"] as Dictionary
	var modifier := parts["modifier"] as Dictionary
	suite.assert_equal(facade.call("event_view_state")["phase"], "pending_reward", "special event remains pending until real reward commit")
	suite.assert_equal(modifier["narrative_flags"], event_state["narrative_flags"], "pending reward keeps modifier and EventRunState flags equal")
	suite.assert_true(bool(event_state["narrative_flags"].get("perfect_rewind_claimed", false)), "pending reward records the authored one-use flag")
	var offer: Dictionary = facade.call("event_reward_offer")
	var options := offer.get("options", []) as Array
	var diagnostics: Dictionary = {}
	if options.is_empty():
		diagnostics["continuation"] = facade.call("_current_event_continuation")
		diagnostics["build_items"] = state["build"].get("items", [])
		diagnostics["rare_candidates"] = []
		var registry: RefCounted = facade.call("content_registry")
		for definition: Dictionary in registry.call("get_by_category", &"item", &"LAUNCH"):
			if str(definition.get("rarity", "")) in ["rare", "legendary", "unique"]:
				(diagnostics["rare_candidates"] as Array).append({
					"id": definition["id"], "rarity": definition["rarity"], "item_mode": definition.get("item_mode", ""),
					"compatible": CompatibilityScript.matches(definition, CompatibilityScript.context_for(state["config"])),
				})
	suite.assert_true(not options.is_empty(), "special event exposes a real content reward offer: %s" % str(diagnostics))
	if options.is_empty():
		return
	var rewarded = facade.call("submit_current_event_reward", StringName(str(options[0]["option_id"])), int(state["revision"]))
	suite.assert_true(rewarded.ok, "real event reward resolves its authenticated continuation")
	suite.assert_equal(facade.call("event_view_state")["phase"], "resolved", "special event reaches terminal result after real reward")
