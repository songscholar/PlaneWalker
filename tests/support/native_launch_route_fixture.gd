extends RefCounted

const Phase := preload("res://scripts/application/run_phase.gd")
const Settlement := preload("res://scripts/progression/run_settlement_authority.gd")


static func reach(main: Node, suite: RefCounted, final_victory: bool = false) -> bool:
	var host: Node = main.get_node("RunRuntimeHost")
	# Combat and Boss receipts are fixtures; route, reward and native handoffs are real.
	for _step: int in range(140):
		var state: Dictionary = host.runtime_snapshot()
		var room: Node = host.native_checkpoint_participants().runtime
		var context: Dictionary = host.dungeon_ui_context()
		var node: Dictionary = host.native_run_state().current_floor_node()
		if final_victory and int(state.phase) == Phase.Value.VICTORY:
			return true
		if not final_victory and int(state.current_floor_index) == 4 and node.cleared and node.id != state.floor_plan.entry_node_id and state.open_offer.is_empty():
			return true
		var result: Variant
		if not state.open_offer.is_empty():
			var offer: Dictionary = state.open_offer
			host._on_option_chosen(str(offer.offer_id), str(offer.options[0].option_id), int(offer.revision))
			result = {"ok": int(host.runtime_snapshot().revision) > int(state.revision), "code": "reward"}
		elif int(state.phase) == Phase.Value.RUN_PREPARING:
			result = host.start_next_floor(int(state.revision))
		elif node.id == state.floor_plan.entry_node_id or node.cleared:
			var routes: Array = host.route_choices()
			if routes.is_empty():
				return false
			var selected: Dictionary = routes[0]
			for candidate: Dictionary in routes:
				if candidate.room_type in ["combat", "elite", "boss"]:
					selected = candidate
					break
			result = host.select_route(StringName(selected.edge_id), int(state.revision))
		else:
			match node.room_type:
				"shop":
					result = host.leave_merchant(int(state.revision))
				"event":
					result = host.choose_event_option(&"decline", int(state.revision)) if context.event.phase == "open" else host.dismiss_event(int(state.revision))
				"treasure", "rest":
					result = host.resolve_room_interaction(&"leave", int(state.revision))
				_:
					if node.room_type == "boss":
						var launch: Dictionary = GameState.profile_runtime_service().snapshot().active_launch_receipt
						var source := {"schema_id": Settlement.SOURCE_TYPE, "run_id": launch.run_id, "launch_sequence": int(launch.sequence), "floor_id": state.floor_plan.floor_id, "node_id": node.id, "kind": "boss", "payload": {"actor_role": "principal", "boss_id": Settlement.BOSS_ORDER[int(state.current_floor_index)]}}
						source["source_id"] = Settlement.source_id(source, source.payload.boss_id)
						host.native_run_state().events.append({"type": Settlement.SOURCE_TYPE, "receipt": source})
					result = room.complete_current_room()
		if not result.ok:
			suite.assert_true(false, "native fixture route progresses at floor %d node %s phase %d: %s" % [state.current_floor_index, node.id, state.phase, result.get("code")])
			return false
		main.get_node("DungeonFlow").refresh(true)
		freeze(main)
		await main.get_tree().process_frame
	return false


static func freeze(main: Node) -> void:
	main.set_process(false)
	main.get_node("RunRuntimeHost").set_process(false)
	var player: Node = main.get_node("CombatRoom01/Player")
	player.set_physics_process(false)
	player.get_node("TimeManager").set_process(false)
	player.get_node("RewindRecorder").set_process(false)
	main.get_node("TutorialFlow").set_process(false)
	main.get_node("NarrativeFlow").set_physics_process(false)
