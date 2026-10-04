extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Main := preload("res://scenes/main.tscn")
const RouteFixture := preload("res://tests/support/native_launch_route_fixture.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var main := Main.instantiate()
	add_child(main)
	await get_tree().process_frame
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": "wanderer", "weapon_id": "sword", "enabled_time_skills": ["stop", "rewind"], "difficulty": "normal", "seed": 6}
	suite.assert_true(main._launch_run(config, false, true), "actual Main accepts the deterministic event-ambush launch")
	RouteFixture.freeze(main)
	main.get_node("DungeonFlow").set_process(false)
	var host: Node = main.get_node("RunRuntimeHost")
	var controller: Node = main.get_node("CombatRoom01")
	var player: Node = controller.get_node("Player")
	var reached := true
	for node_id: String in ["layer_01_a", "layer_02_a", "layer_03_c"]:
		var selected := false
		for route: Dictionary in host.route_choices():
			if route.node_id == node_id:
				selected = host.select_route(StringName(route.edge_id), int(host.runtime_snapshot().revision)).ok
				break
		if not selected:
			reached = false
			break
		if node_id == "layer_03_c":
			break
		# Prerequisite room clears are fixtures; the event route and ambush stay native.
		var room: Node = host.native_checkpoint_participants().runtime
		if not room.complete_current_room().ok:
			reached = false
			break
		for _choice: int in range(6):
			var state: Dictionary = host.runtime_snapshot()
			if state.open_offer.is_empty():
				break
			var offer: Dictionary = state.open_offer
			host._on_option_chosen(str(offer.offer_id), str(offer.options[0].option_id), int(offer.revision))
		await get_tree().process_frame
	suite.assert_true(reached, "actual Host routes through the generated prerequisites to the event node")
	if not reached:
		await _dispose(main)
		suite.finish(get_tree())
		return
	var facade: RefCounted = host.native_checkpoint_participants().facade
	var view: Dictionary = facade.event_view_state()
	suite.assert_equal(view.get("event_id", ""), "event_sleeping_guardian", "actual event selector freezes the authored sleeping guardian occurrence")
	var actual_room: Node = host.native_checkpoint_participants().scene_host.active_room()
	var anchor: Node = actual_room.get_node_or_null("EncounterAnchors/enemy_wave_primary")
	suite.assert_true(anchor != null, "actual authored event scene declares its native encounter spawn anchor")
	var catalog: RefCounted = facade.encounter_catalog()
	suite.assert_true(catalog.has_method("resolve_for_event"), "actual Launch catalog resolves ambush recipes against event geometry and node identity")
	if anchor == null or not catalog.has_method("resolve_for_event") or view.get("event_id") != "event_sleeping_guardian":
		await _dispose(main)
		suite.finish(get_tree())
		return
	var chosen: Variant = host.choose_event_option(&"commit", int(host.runtime_snapshot().revision))
	suite.assert_true(chosen.ok, "actual authored guardian option starts the native event encounter")
	var runner: Node = controller.encounter_runner()
	var started: Dictionary = runner.native_launch_snapshot()
	suite.assert_true(not started.is_empty() and started.encounter.identity.room_id == "layer_03_c", "event continuation binds the actual native encounter to the event floor node")
	if not chosen.ok or started.is_empty():
		await _dispose(main)
		suite.finish(get_tree())
		return
	var pending: Dictionary = host.runtime_snapshot()
	var native_room_runtime: Node = host.native_checkpoint_participants().runtime
	var pending_room: Dictionary = native_room_runtime.snapshot()
	var forged := {
		"ok": true, "new_revision": int(pending.revision),
		"context": {"view_state": {"phase": "resolved", "pending_kind": ""}, "continuation": {}},
	}
	suite.assert_true(not native_room_runtime.sync_event_result(forged), "forged resolved command view cannot cancel actual active native event encounter")
	suite.assert_equal(native_room_runtime.snapshot(), pending_room, "rejected forged sync preserves the actual native room and continuation")
	runner.encounter_completed.emit(StringName(started.definition.id))
	runner.encounter_completed.emit(&"encounter_profile_ruins_adapter_v1")
	runner.encounter_failed.emit(StringName(started.definition.id), &"forged_failure", {})
	suite.assert_equal(host.runtime_snapshot(), pending, "active native encounter and original profile signals cannot forge event consequences")
	host.set_dungeon_selection_safety(false)
	var spawned := false
	var accepted := true
	for _frame: int in range(600):
		for actor: Node in controller.get_node("Enemies").get_children():
			if not actor.is_queued_for_deletion():
				spawned = true
				actor.get_node("HealthComponent").lose_health(1000.0, null)
		if not player.advance_action_frame():
			accepted = false
			break
		if facade.event_view_state().get("phase") == "resolved":
			break
		await get_tree().physics_frame
	var resolved: Dictionary = facade.event_view_state()
	suite.assert_true(accepted and spawned and resolved.get("phase") == "resolved" and not runner.is_active(), "native ambush spawns actual actors and authentic final deaths resolve its original event continuation")
	var after: Dictionary = host.runtime_snapshot()
	runner.encounter_completed.emit(StringName(started.definition.id))
	suite.assert_equal(host.runtime_snapshot(), after, "repeated concrete encounter completion cannot duplicate the event outcome")
	var dismissed: Variant = host.dismiss_event(int(host.runtime_snapshot().revision))
	suite.assert_true(dismissed.ok and host.native_run_state().current_floor_node().cleared, "resolved native ambush can dismiss and continue normal room routing")
	await _dispose(main)
	suite.finish(get_tree())


func _dispose(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
