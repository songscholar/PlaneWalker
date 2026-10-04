extends Node

const MainScene := preload("res://scenes/main.tscn")
const Suite := preload("res://tests/support/test_suite.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const FacadeScript := preload("res://scripts/application/run_runtime_facade.gd")
const EffectRuntimeScript := preload("res://scripts/items/player_reward_effect_runtime.gd")
const FloorRuleAuthorityScript := preload("res://scripts/dungeon/floor_rule_effect_authority.gd")
const ContentSnapshotScript := preload("res://scripts/content/content_snapshot_provider.gd")
const SaveServiceScript := preload("res://scripts/save/save_service.gd")
const SaveFileOpsScript := preload("res://scripts/save/save_file_ops.gd")

const ATTACK_IDS := ["weapon_temper", "past_strength", "paradox_echo", "void_bargain_power", "heroic_assault"]
const GUARD_IDS := ["chronal_grace", "void_bargain_guard", "heroic_guard"]

var _seen_types: Dictionary = {}
var _seen_panels: Dictionary = {}
var _merchant_purchased := false
var _rest_healed := false
var _modifier_granted := false
var _modifier_source_clear_verified := false
var _modifier_expired := false
var _modifier_restore_verified := false
var _modifier_restore_attempted := false
var _legacy_modifier_restore_verified := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	main.get_node("CombatRoom01").set("spawn_warning_duration", 0.0)
	var started: bool = main.call("_launch_run", {
		"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer",
		"weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal", "seed": 20261004,
	}, false, true)
	suite.assert_true(started, "main launches the authored five-floor mode")
	await get_tree().process_frame
	var flow := main.get_node_or_null("DungeonFlow")
	suite.assert_true(flow != null, "main assembles the dungeon interaction coordinator")
	if flow != null:
		var panel: Control = flow.call("active_panel")
		suite.assert_true(panel != null and panel.visible, "entry opens a player-facing route choice")
		if panel != null:
			var original_locale := TranslationServer.get_locale()
			TranslationServer.set_locale("en")
			await get_tree().process_frame
			suite.assert_equal(flow.get("_map_button").text, tr("UI_DUNGEON_MAP"), "map toolbar follows the selected locale")
			TranslationServer.set_locale(original_locale)
			await get_tree().process_frame
			suite.assert_equal(FocusCoordinator.active_scope(), panel, "controller focus enters route choice")
			var host := main.get_node("RunRuntimeHost")
			var frozen: Dictionary = host.call("runtime_snapshot")
			host.call("_process", 1.0)
			suite.assert_equal(host.call("runtime_snapshot")["run_time_ms"], frozen["run_time_ms"], "route selection never advances authoritative game time")
			suite.assert_true(flow.call("open_map"), "route choice can open its real floor map")
			var map_panel: Control = flow.call("active_panel")
			suite.assert_equal(map_panel.name, "DungeonMapPanel", "map command switches to the projected route graph")
			suite.assert_equal(FocusCoordinator.active_scope(), map_panel, "controller focus enters the map")
			map_panel.call("_request_close")
			panel = flow.call("active_panel")
			suite.assert_true(panel != null and panel.visible, "map close restores the route interaction")
			panel.call("_request_close")
			suite.assert_equal(flow.call("active_panel"), null, "route back closes the interaction")
			var reopen := InputEventAction.new()
			reopen.action = &"interact"
			reopen.pressed = true
			suite.assert_true(flow.call("handle_input", reopen), "controller interact reopens the current room interaction")
			panel = flow.call("active_panel")
			var actions: Array = panel.call("action_controls")
			suite.assert_true(not actions.is_empty(), "route choice exposes controller-focusable destinations")
			var before: Dictionary = main.get_node("RunRuntimeHost").call("runtime_snapshot")
			if not actions.is_empty():
				(actions[0] as Button).pressed.emit()
				await get_tree().process_frame
				var after: Dictionary = main.get_node("RunRuntimeHost").call("runtime_snapshot")
				suite.assert_true(after["floor_plan"]["current_node_id"] != "entry", "native route action enters the first room")
				suite.assert_true(int(after["revision"]) > int(before["revision"]), "route action reaches authoritative state")
				suite.assert_true(main.get_node("LaunchRoomSceneHost").call("active_room") != null, "route action streams the real room scene")
				var unchanged: Dictionary = after.duplicate(true)
				(actions[0] as Button).pressed.emit()
				suite.assert_equal(main.get_node("RunRuntimeHost").call("runtime_snapshot"), unchanged, "retired route button cannot submit twice")
	await _complete_native_dungeon(main, suite)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	suite.finish(get_tree())


func _complete_native_dungeon(main: Node, suite: RefCounted) -> void:
	var host := main.get_node("RunRuntimeHost")
	var flow := main.get_node("DungeonFlow")
	var room_controller := main.get_node("CombatRoom01")
	var player := room_controller.get_node("Player")
	for step: int in range(320):
		flow.call("refresh", true)
		var state: Dictionary = host.call("runtime_snapshot")
		await _observe_event_modifiers(main, state, player, suite)
		if Phase.is_terminal(int(state["phase"])):
			break
		var choice_panel: Control = host.call("choice_panel")
		var panel: Control = flow.call("active_panel")
		if choice_panel.visible:
			suite.assert_equal(flow.call("active_panel"), null, "dungeon panels yield to the authoritative reward selection")
			suite.assert_equal(player.process_mode, Node.PROCESS_MODE_DISABLED, "reward selection keeps physical gameplay frozen")
			var options: Array = choice_panel.call("_option_buttons")
			suite.assert_true(not options.is_empty(), "real room reward has an available option")
			if options.is_empty():
				break
			(options[0] as Button).pressed.emit()
			if bool(choice_panel.get("replacement_panel").visible):
				choice_panel.call("_on_replacement_confirmed")
		elif panel != null:
			_seen_panels[str(panel.name)] = true
			suite.assert_equal(FocusCoordinator.active_scope(), panel, "current native dungeon panel owns controller focus")
			var actions: Array = panel.call("action_controls")
			var selected: Button
			match str(panel.name):
				"RouteChoicePanel", "FloorTransitionPanel":
					selected = _first_available(actions)
				"RoomInteractionPanel":
					var context: Dictionary = host.call("dungeon_ui_context")
					var room_type := str(context["room"]["room_type"])
					_seen_types[room_type] = true
					if room_type == "rest" and not _rest_healed:
						var health := player.get_node("HealthComponent")
						health.call("lose_health", 20.0)
						flow.call("refresh", true)
						actions = panel.call("action_controls")
						selected = _action(actions, "heal")
						_rest_healed = selected != null and not selected.disabled
					if selected == null or selected.disabled:
						selected = _first_available(actions)
				"MerchantPanel":
					_seen_types["shop"] = true
					if not _merchant_purchased:
						for action: Button in actions:
							if str(action.get_meta("action_id", "")) != "leave" and not action.disabled:
								selected = action
								_merchant_purchased = true
								break
					if selected == null:
						selected = _action(actions, "leave")
				"DungeonEventPanel":
					_seen_types["event"] = true
					selected = _first_available(actions)
				_:
					suite.assert_true(false, "unexpected native panel: %s" % panel.name)
					break
			suite.assert_true(selected != null, "native panel offers an executable command: %s" % panel.name)
			if selected == null:
				break
			selected.pressed.emit()
			var committed: Dictionary = host.call("runtime_snapshot")
			if int(committed["revision"]) == int(state["revision"]) and str(panel.name) == "DungeonEventPanel":
				suite.assert_equal(committed, state, "rejected event consequence fully preserves authoritative state")
				suite.assert_true(panel.get("error_label").visible, "rejected event has player-facing feedback")
				var decline := _action(panel.call("action_controls"), "decline")
				suite.assert_true(decline != null and not decline.disabled, "rejected event restores a valid decline command")
				if decline != null and not decline.disabled:
					decline.pressed.emit()
					committed = host.call("runtime_snapshot")
			suite.assert_true(int(committed["revision"]) > int(state["revision"]), "native panel command commits authoritative state: %s" % panel.name)
			if int(committed["revision"]) <= int(state["revision"]):
				break
		else:
			var context: Dictionary = host.call("dungeon_ui_context")
			var room_type := str(context.get("room", {}).get("room_type", ""))
			_seen_types[room_type] = true
			# Use physical hostile death signals while keeping AI movement deterministic.
			room_controller.process_mode = Node.PROCESS_MODE_DISABLED
			for enemy: Node in room_controller.get_node("Enemies").get_children():
				var health := enemy.get_node_or_null("HealthComponent")
				if health != null and not bool(health.get("dead")):
					health.call("lose_health", 1000000.0, player)
		await get_tree().process_frame
	var final: Dictionary = host.call("runtime_snapshot")
	if not Phase.is_terminal(int(final.get("phase", -1))):
		print("Native dungeon stalled: phase=", final["phase"], " node=", final["floor_plan"]["current_node_id"], " event=", host.call("dungeon_ui_context").get("event", {}), " runner=", room_controller.call("encounter_runner").call("snapshot"))
	suite.assert_equal(final.get("completed_floor_ids", []).size(), 5, "native commands complete all five authored floors")
	suite.assert_true(Phase.is_terminal(int(final.get("phase", -1))), "last boss produces the actual terminal run result")
	for room_type: String in ["combat", "treasure", "rest", "shop", "event", "boss"]:
		suite.assert_true(_seen_types.has(room_type), "production route exercises room type: %s" % room_type)
	for panel_name: String in ["RouteChoicePanel", "RoomInteractionPanel", "MerchantPanel", "DungeonEventPanel", "FloorTransitionPanel"]:
		suite.assert_true(_seen_panels.has(panel_name), "production route exercises panel: %s" % panel_name)
	suite.assert_true(_merchant_purchased, "merchant panel executes a purchase or priced service")
	suite.assert_true(_rest_healed, "rest panel exposes physical health recovery after damage")
	suite.assert_true(_modifier_granted, "native event choice installs a real temporary Player effect")
	suite.assert_true(_modifier_source_clear_verified, "granting room clear consumes zero duration in the production flow")
	suite.assert_true(_modifier_expired, "later native room clears expire the authored temporary effect")
	suite.assert_true(_modifier_restore_verified, "native effect survives a physical JSON Save and fresh Facade restore without stacking")
	suite.assert_true(_legacy_modifier_restore_verified, "legacy native save reconstructs a bounded lifetime baseline")
	suite.assert_equal(player.call("event_temporary_modifier_snapshot"), [], "terminal result removes the remaining physical event layer")
	flow.call("refresh", true)
	suite.assert_equal(flow.call("active_panel"), null, "terminal result closes all dungeon interactions")
	suite.assert_true(not bool(flow.get("_map_button").visible), "terminal result retires map access")


func _observe_event_modifiers(main: Node, state: Dictionary, player: Node, suite: RefCounted) -> void:
	if Phase.is_terminal(int(state["phase"])):
		return
	var participants: Dictionary = state.get("dungeon_event_runtime", {}).get("consequence_runtime", {}).get("participant_snapshots", {})
	if participants.is_empty():
		return
	var modifiers: Array = participants["modifier"]["temporary_modifiers"]
	var assignments: Dictionary = participants["event_state"]["selected_event_by_node"]
	var facts: Array = []
	for event: Dictionary in state["events"]:
		if event.get("type") == "room_completed_v1":
			facts.append(event)
	var expected: Array = []
	var attack_multiplier := 1.0
	var guard_multiplier := 1.0
	var regeneration_multiplier := 1.0
	var completed_source := false
	for modifier: Dictionary in modifiers:
		_modifier_granted = true
		var source: String = modifier["source_transaction_id"]
		var assignment: Dictionary = {}
		for candidate: Dictionary in assignments.values():
			if candidate.get("transaction_id") == source:
				assignment = candidate
				break
		var source_index := -1
		for index: int in range(facts.size()):
			if facts[index]["floor_id"] == assignment.get("floor_id") and facts[index]["node_id"] == assignment.get("node_id"):
				source_index = index
				break
		var elapsed := 0 if source_index < 0 else facts.size() - source_index - 1
		if source_index >= 0 and elapsed == 0:
			_modifier_source_clear_verified = true
			completed_source = true
		if elapsed >= int(modifier["duration_rooms"]):
			_modifier_expired = true
			continue
		expected.append({"modifier_id": modifier["modifier_id"], "magnitude": float(modifier["magnitude"]), "source_transaction_id": source})
		if ATTACK_IDS.has(modifier["modifier_id"]):
			attack_multiplier *= float(modifier["magnitude"])
		elif GUARD_IDS.has(modifier["modifier_id"]):
			guard_multiplier /= float(modifier["magnitude"])
		else:
			regeneration_multiplier *= float(modifier["magnitude"])
	expected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["modifier_id"] < b["modifier_id"])
	suite.assert_equal(player.call("event_temporary_modifier_snapshot"), expected, "physical event effects match actual successful room clear history")
	suite.assert_close(player.call("get_effective_attack"), float(player.get("stats").get("attack")) * attack_multiplier, "native grants and expiry reach actual attack")
	suite.assert_close(player.call("get_damage_taken_multiplier"), guard_multiplier, "native grants and expiry reach actual incoming damage")
	suite.assert_close(player.get_node("TimeManager").call("event_energy_regen_multiplier"), regeneration_multiplier, "native grants and expiry reach actual energy regeneration")
	if completed_source and not _modifier_restore_attempted:
		_modifier_restore_attempted = true
		await _assert_native_modifier_restore(main, state, player, expected, suite)


func _assert_native_modifier_restore(main: Node, state: Dictionary, player: Node, expected: Array, suite: RefCounted) -> void:
	var facade: RefCounted = main.get_node("RunRuntimeHost").get("_facade")
	var content := ContentSnapshotScript.snapshot(facade.call("content_registry"))
	var root := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("native_event_restore")
	var service = SaveServiceScript.new()
	suite.assert_true(service.configure(root, "0.4.0-dev", content).ok, "native event SaveService configures")
	var saved = service.save_profile("slot_1", "base", {"active_run_state": state})
	suite.assert_true(saved.ok, "authentic event grant saves through the physical SaveService: %s" % saved.to_dictionary())
	if not saved.ok:
		return
	var loaded = service.load_profile("slot_1", "base")
	suite.assert_true(loaded.ok, "authentic event grant loads through physical JSON")
	if not loaded.ok:
		return
	for legacy: bool in [false, true]:
		var restored_player := PlayerScene.instantiate()
		restored_player.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(restored_player)
		var loadout: Dictionary = facade.call("active_loadout")
		var config: Dictionary = state["config"].duplicate(true)
		config["character_profile"] = loadout["character_profile"].duplicate(true)
		config["weapon_profile"] = loadout["weapon_profile"].duplicate(true)
		config["character_talent_definitions"] = loadout["character_talents"].duplicate(true)
		suite.assert_true(restored_player.call("configure_run", StringName(state["run_id"])), "restored Player binds the matching run identity")
		suite.assert_true(restored_player.call("configure_loadout", config), "restored Player installs the authored Launch loadout")
		suite.assert_true(restored_player.call("restore_reward_effect_snapshot", player.call("reward_effect_snapshot"), false), "restored physical Player installs permanent rewards independently")
		var authority = FloorRuleAuthorityScript.new()
		suite.assert_true(authority.configure(restored_player, main.get_node("LaunchRoomSceneHost")), "restored effect uses the real floor rule authority")
		var restored = FacadeScript.new()
		suite.assert_true(restored.boot().ok, "fresh effect Facade boots")
		suite.assert_true(restored.configure_merchant_effect_authority(EffectRuntimeScript.new(), restored_player), "restored effect binds actual Player participants")
		var snapshot: Dictionary = loaded.payload["active_run_state"].duplicate(true)
		if legacy:
			var old_events: Array = []
			for event: Dictionary in snapshot["events"]:
				if event.get("type") != "room_completed_v1":
					old_events.append(event.duplicate(true))
			snapshot["events"] = old_events
		var accepted = restored.restore_launch_run(snapshot, authority)
		suite.assert_true(accepted.ok, "event lifetime restores%s: %s %s" % [" from a legacy room ledger" if legacy else " exactly", accepted.code, accepted.context])
		if accepted.ok:
			suite.assert_equal(restored_player.call("event_temporary_modifier_snapshot"), expected, "restored event projection preserves magnitude and source without stacking")
			suite.assert_close(restored_player.call("get_damage_taken_multiplier"), player.call("get_damage_taken_multiplier"), "restored native guard retains physical mitigation")
			var before: Array = restored_player.call("event_temporary_modifier_snapshot")
			suite.assert_true(restored.call("_sync_player_event_modifiers"), "repeated authoritative projection succeeds")
			suite.assert_equal(restored_player.call("event_temporary_modifier_snapshot"), before, "repeated authoritative projection cannot duplicate an effect")
			if legacy:
				var baselines := 0
				for event: Dictionary in restored.snapshot()["events"]:
					if event.get("type") == "modifier_lifetime_baseline_v1":
						baselines += 1
				suite.assert_equal(baselines, expected.size(), "legacy restore records one baseline per dismissed source")
				_legacy_modifier_restore_verified = baselines == expected.size() and _assert_saved_later_clears(restored, restored_player, authority, service, expected, suite)
			else:
				suite.assert_equal(restored.snapshot(), state, "current Save restore preserves the exact authenticated RunState")
				_assert_malformed_reward_baseline(restored, restored_player, authority, service, snapshot, suite)
				_modifier_restore_verified = _assert_saved_later_clears(restored, restored_player, authority, service, expected, suite)
		authority.reset()
		restored = null
		restored_player.queue_free()
		await get_tree().process_frame
	suite.assert_true(SaveFileOpsScript.new().remove_tree(root).ok, "native event restore cleans its isolated test save")


func _assert_malformed_reward_baseline(facade: RefCounted, player: Node, authority: RefCounted, service: RefCounted, snapshot: Dictionary, suite: RefCounted) -> void:
	var baseline: Variant = snapshot["resources"].get("player_reward_run_start_baseline")
	suite.assert_true(baseline is Dictionary and not baseline.is_empty(), "native checkpoint retains the original run-start Player reward baseline before the first merchant")
	if not baseline is Dictionary or baseline.is_empty():
		return
	var state_before: Dictionary = facade.snapshot()
	var physical_before: Dictionary = player.call("reward_effect_snapshot")
	var temporary_before: Array = player.call("event_temporary_modifier_snapshot")
	var loaded_before = service.load_profile("slot_1", "base")
	suite.assert_true(loaded_before.ok, "malformed baseline checks start with the authentic physical save")
	if not loaded_before.ok:
		return
	for mutation: Dictionary in [
		{"label": "unknown baseline field", "change": func(value: Dictionary): value["unknown"] = true},
		{"label": "missing baseline domain", "change": func(value: Dictionary): value.erase("stats")},
		{"label": "missing nested baseline field", "change": func(value: Dictionary): value["weapon"].erase("runtime")},
	]:
		var malformed: Dictionary = snapshot.duplicate(true)
		(mutation["change"] as Callable).call(malformed["resources"]["player_reward_run_start_baseline"])
		var rejected_save = service.save_profile("slot_1", "base", {"active_run_state": malformed})
		suite.assert_true(not rejected_save.ok, "%s cannot replace the authentic Save" % mutation["label"])
		var still_saved = service.load_profile("slot_1", "base")
		suite.assert_true(still_saved.ok, "refused baseline preserves the readable physical Save")
		if still_saved.ok:
			suite.assert_equal(still_saved.payload, loaded_before.payload, "refused baseline leaves the existing physical JSON payload unchanged")
		var rejected_restore = facade.restore_launch_run(malformed, authority)
		suite.assert_true(not rejected_restore.ok, "%s cannot enter the live Facade" % mutation["label"])
		suite.assert_equal(facade.snapshot(), state_before, "malformed reward baseline preserves all authoritative state")
		suite.assert_equal(player.call("reward_effect_snapshot"), physical_before, "malformed reward baseline cannot mutate physical permanent rewards")
		suite.assert_equal(player.call("event_temporary_modifier_snapshot"), temporary_before, "malformed reward baseline cannot mutate the independent temporary layer")


func _assert_saved_later_clears(facade: RefCounted, player: Node, authority: RefCounted, service: RefCounted, expected: Array, suite: RefCounted) -> bool:
	var grants: Array = facade.snapshot()["dungeon_event_runtime"]["consequence_runtime"]["participant_snapshots"]["modifier"]["temporary_modifiers"].duplicate(true)
	var duration := int(grants[0]["duration_rooms"])
	var source: String = expected[0]["source_transaction_id"]
	for clear_index: int in range(duration):
		var state: Dictionary = facade.snapshot()
		if state["completed_floor_ids"].size() > int(state["current_floor_index"]):
			var next = facade.start_next_floor()
			suite.assert_true(next.ok, "saved lifetime continues across a real floor transition")
			if not next.ok:
				return false
		var choices: Array = facade.route_choices()
		suite.assert_true(not choices.is_empty(), "saved restored run exposes the next authored room")
		if choices.is_empty():
			return false
		var begun = facade.begin_route_transition(StringName(choices[0]["edge_id"]), int(facade.snapshot()["revision"]))
		suite.assert_true(begun.ok, "saved continuation begins the production route transaction")
		if not begun.ok:
			return false
		var transition_id: String = begun.context["transition_id"]
		var finalized = facade.finalize_route_transition(transition_id, begun.new_revision)
		suite.assert_true(finalized.ok, "saved continuation finalizes the production route transaction")
		if not finalized.ok:
			return false
		var confirmed = facade.confirm_route_transition(transition_id, finalized.new_revision)
		suite.assert_true(confirmed.ok, "saved continuation confirms the production route transaction")
		if not confirmed.ok:
			return false
		var entered = facade.enter_current_room()
		suite.assert_true(entered.ok, "saved continuation enters its real authored room")
		if not entered.ok:
			return false
		var room: Dictionary = facade.current_room_definition()
		var completed
		if room["room_type"] in ["rest", "treasure"]:
			completed = facade.resolve_current_room_interaction(&"leave", int(facade.snapshot()["revision"]))
		elif room["room_type"] == "event":
			var opened = facade.open_current_event()
			if not opened.ok:
				return false
			var declined = facade.choose_current_event_option(&"decline", int(facade.snapshot()["revision"]))
			if not declined.ok:
				return false
			completed = facade.dismiss_current_event(int(facade.snapshot()["revision"]))
		else:
			if room["room_type"] == "shop":
				var opened = facade.open_current_merchant()
				suite.assert_true(opened.ok, "saved continuation opens its authored merchant before leaving: %s %s" % [opened.code, opened.context])
				if not opened.ok:
					return false
			completed = facade.complete_current_room()
		suite.assert_true(completed.ok, "saved lifetime advances only after an authentic successful completion: %s" % completed.context)
		if not completed.ok:
			return false
		var physical: Array = player.call("event_temporary_modifier_snapshot")
		var present := false
		for modifier: Dictionary in physical:
			present = present or modifier["source_transaction_id"] == source
		suite.assert_equal(present, clear_index + 1 < duration, "saved physical effect expires on the exact authored successful room count")
		var progressed: Dictionary = facade.snapshot()
		var saved = service.save_profile("slot_1", "base", {"active_run_state": progressed})
		suite.assert_true(saved.ok, "progressed saved lifetime seals to physical JSON")
		if not saved.ok:
			return false
		var loaded = service.load_profile("slot_1", "base")
		suite.assert_true(loaded.ok, "progressed saved lifetime loads from physical JSON")
		if not loaded.ok:
			return false
		var restored = FacadeScript.new()
		if not restored.boot().ok or not restored.configure_merchant_effect_authority(EffectRuntimeScript.new(), player):
			return false
		var resumed = restored.restore_launch_run(loaded.payload["active_run_state"], authority)
		suite.assert_true(resumed.ok, "repeated Save/Facade restore retains its original lifetime and reward baselines: %s %s" % [resumed.code, resumed.context])
		if not resumed.ok:
			return false
		suite.assert_equal(restored.snapshot(), progressed, "repeated restore does not rewrite completion sequence or baseline")
		suite.assert_equal(player.call("event_temporary_modifier_snapshot"), physical, "repeated restore cannot extend or stack the real Player effect")
		facade = restored
	suite.assert_equal(facade.snapshot()["dungeon_event_runtime"]["consequence_runtime"]["participant_snapshots"]["modifier"]["temporary_modifiers"], grants, "saved expiry retains the original authenticated grant")
	return true


func _first_available(actions: Array) -> Button:
	for action: Button in actions:
		if not action.disabled:
			return action
	return null


func _action(actions: Array, action_id: String) -> Button:
	for action: Button in actions:
		if str(action.get_meta("action_id", "")) == action_id:
			return action
	return null
