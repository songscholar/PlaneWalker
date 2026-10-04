class_name RunOrchestrator
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunStateScript := preload("res://scripts/application/run_state.gd")
const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")

var _state: RefCounted
var _pending_route_transition: Dictionary = {}
var _next_route_transition_id: int = 1


func _init() -> void:
	_state = RunStateScript.new()


func snapshot() -> Dictionary:
	return _state.snapshot().duplicate(true)


func revision() -> int:
	return int(_state.revision)


func phase() -> int:
	return int(_state.phase)


func is_terminal() -> bool:
	return _state.is_terminal()


func has_consumed_offer(offer_id: String) -> bool:
	return _state.has_consumed_offer(offer_id)


func selection_transaction_snapshot() -> Dictionary:
	return _state.selection_transaction_snapshot().duplicate(true)


func restore_selection_transaction_snapshot(value: Dictionary) -> bool:
	return _state.restore_selection_transaction_snapshot(value.duplicate(true))


func floor_transaction_snapshot() -> Dictionary:
	return _state.floor_transaction_snapshot().duplicate(true)


func can_restore_floor_transaction_snapshot(value: Dictionary) -> bool:
	return _state.can_restore_floor_transaction_snapshot(value.duplicate(true))


func restore_floor_transaction_snapshot(value: Dictionary) -> bool:
	if not _pending_route_transition.is_empty():
		return false
	return _state.restore_floor_transaction_snapshot(value.duplicate(true))


func observe_player_health(current: float, maximum: float) -> bool:
	if not _pending_route_transition.is_empty():
		return false
	return _state.observe_player_health(current, maximum)


func bind_player_reward_baseline(value: Dictionary) -> bool:
	if not _pending_route_transition.is_empty():
		return false
	return _state.bind_player_reward_baseline(value.duplicate(true))


func reward_build_participant() -> Object:
	return _state.build_state


func restore_launch_run_snapshot(
	value: Dictionary,
	floor_definition: Dictionary,
	room_templates: Array
) -> bool:
	if not _pending_route_transition.is_empty():
		return false
	return _state.restore_launch_run_snapshot(
		value.duplicate(true),
		floor_definition.duplicate(true),
		room_templates.duplicate(true)
	)


func initialize_launch_economy(
	economy_snapshot: Dictionary,
	merchant_snapshot: Dictionary,
	expected_revision: int
):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if not _pending_route_transition.is_empty():
		return _reject_floor_operation("initialize_launch_economy")
	if not _state.initialize_launch_economy_state(
		economy_snapshot.duplicate(true), merchant_snapshot.duplicate(true)
	):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _state.revision,
			{"field": "run_economy_or_merchant_state"}
		)
	return CommandResultScript.success(
		_state.advance_revision(),
		{
			"run_economy": _state.run_economy.duplicate(true),
			"merchant_state": _state.merchant_state.duplicate(true),
		}
	)


func initialize_launch_events(runtime_snapshot: Dictionary, expected_revision: int):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if not _pending_route_transition.is_empty():
		return _reject_floor_operation("initialize_launch_events")
	if not _state.initialize_launch_event_state(runtime_snapshot.duplicate(true)):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "dungeon_event_runtime"}
		)
	return CommandResultScript.success(
		_state.advance_revision(),
		{"dungeon_event_runtime": _state.dungeon_event_runtime.duplicate(true)}
	)


func commit_event_transaction(candidate: Dictionary, expected_revision: int):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if not _pending_route_transition.is_empty():
		return _reject_floor_operation("commit_event_transaction")
	if not _state.commit_event_transaction_state(candidate.duplicate(true)):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "event_transaction"}
		)
	return CommandResultScript.success(
		_state.advance_revision(),
		{
			"dungeon_event_runtime": _state.dungeon_event_runtime.duplicate(true),
			"run_economy": _state.run_economy.duplicate(true),
			"floor_plan": _state.floor_plan.duplicate(true),
			"resources": _state.resources.duplicate(true),
			"build": _state.build_state.transaction_snapshot().duplicate(true),
		}
	)


func commit_merchant_transaction(
	economy_snapshot: Dictionary,
	merchant_snapshot: Dictionary,
	expected_revision: int
):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if not _pending_route_transition.is_empty():
		return _reject_floor_operation("commit_merchant_transaction")
	if not _state.commit_merchant_transaction_state(
		economy_snapshot.duplicate(true), merchant_snapshot.duplicate(true)
	):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _state.revision,
			{"field": "run_economy_or_merchant_state"}
		)
	return CommandResultScript.success(
		_state.advance_revision(),
		{
			"run_economy": _state.run_economy.duplicate(true),
			"merchant_state": _state.merchant_state.duplicate(true),
		}
	)


func commit_economy_transaction(
	economy_snapshot: Dictionary,
	merchant_snapshot: Dictionary,
	expected_revision: int
):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if not _pending_route_transition.is_empty():
		return _reject_floor_operation("commit_economy_transaction")
	if not _state.commit_economy_transaction_state(
		economy_snapshot.duplicate(true), merchant_snapshot.duplicate(true)
	):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _state.revision,
			{"field": "run_economy_or_merchant_state"}
		)
	return CommandResultScript.success(
		_state.advance_revision(),
		{
			"run_economy": _state.run_economy.duplicate(true),
			"merchant_state": _state.merchant_state.duplicate(true),
		}
	)


func commit_floor_rule_state(value: Dictionary, expected_revision: int):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if not _pending_route_transition.is_empty():
		return _reject_floor_operation("commit_floor_rule_state")
	if not _state.commit_floor_rule_state(value.duplicate(true)):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "floor_rule_state"}
		)
	return CommandResultScript.success(
		_state.advance_revision(),
		{"floor_rule_state": _state.floor_rule_state.duplicate(true)}
	)


func commit_floor_rule_observation(value: Dictionary, expected_revision: int):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if not _pending_route_transition.is_empty():
		return _reject_floor_operation("commit_floor_rule_observation")
	if not _state.commit_floor_rule_state(value.duplicate(true)):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "floor_rule_state"}
		)
	return CommandResultScript.success(
		_state.revision,
		{"floor_rule_state": _state.floor_rule_state.duplicate(true)}
	)


func reward_replay_build_snapshot() -> Dictionary:
	return _state.reward_replay_build_snapshot().duplicate(true)


func can_restore_reward_replay_build_snapshot(value: Dictionary) -> bool:
	return _state.can_restore_reward_replay_build_snapshot(value.duplicate(true))


func restore_reward_replay_build_snapshot(value: Dictionary) -> bool:
	return _state.restore_reward_replay_build_snapshot(value.duplicate(true))


func enter_hub():
	if _state.phase != RunPhaseScript.Value.BOOT:
		return _reject_phase()
	return _accept_phase(RunPhaseScript.Value.HUB)


func start_run(config: Dictionary, run_id: String):
	if _state.phase != RunPhaseScript.Value.HUB:
		return _reject_phase()
	var validation = RunConfigScript.validate(config)
	if not validation.ok:
		return CommandResultScript.failure(validation.code, _state.revision, validation.context)
	if run_id.is_empty():
		return CommandResultScript.failure(&"INVALID_ARGUMENT", _state.revision, {"field": "run_id"})
	_state.reset_domain(config, run_id)
	_pending_route_transition.clear()
	_next_route_transition_id = 1
	return _accept_phase(RunPhaseScript.Value.RUN_PREPARING)


func start_floor(
	plan: Dictionary,
	floor_definition: Dictionary,
	room_templates: Array,
	expected_revision: int
):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if not _state.is_launch_floor_mode():
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "config.milestone", "reason": "floor_plan_not_supported"}
		)
	if (
		_state.phase != RunPhaseScript.Value.RUN_PREPARING
		or not _pending_route_transition.is_empty()
	):
		return _reject_floor_operation("start_floor")
	var floor_index := int(plan.get("floor_index", -1))
	if (
		floor_index < 0
		or floor_index > 4
		or floor_index != (_state.completed_floor_ids as Array).size()
		or int(floor_definition.get("order", 0)) - 1 != floor_index
		or str(plan.get("floor_id", "")) != str(floor_definition.get("id", ""))
	):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "floor_plan.floor_index", "received": floor_index}
		)
	var configured: Dictionary = _state.configure_floor_plan(
		plan.duplicate(true), floor_definition.duplicate(true), room_templates.duplicate(true)
	)
	if not bool(configured.get("ok", false)):
		return CommandResultScript.failure(
			StringName(str(configured.get("code", &"INVALID_ARGUMENT"))),
			_state.revision,
			(configured.get("context", {}) as Dictionary).duplicate(true)
		)
	_state.phase = RunPhaseScript.Value.ROOM_ACTIVE
	var accepted_revision: int = int(_state.advance_revision())
	return CommandResultScript.success(
		accepted_revision,
		{
			"floor_id": str(plan.get("floor_id", "")),
			"floor_index": floor_index,
			"plan": _state.floor_plan.duplicate(true),
		}
	)


func select_route(edge_id: StringName, expected_revision: int):
	return begin_route_transition(edge_id, expected_revision)


func begin_route_transition(edge_id: StringName, expected_revision: int):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if (
		not _state.is_launch_floor_mode()
		or not _pending_route_transition.is_empty()
		or _state.phase not in [RunPhaseScript.Value.ROOM_ACTIVE, RunPhaseScript.Value.ROOM_RESOLVING]
	):
		return _reject_floor_operation("begin_route_transition")
	if str(edge_id).is_empty():
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT", _state.revision, {"field": "edge_id"}
		)
	var before: Dictionary = _state.floor_transaction_snapshot()
	var selected: Dictionary = _state.select_floor_edge(edge_id)
	if not bool(selected.get("ok", false)):
		var selected_code := StringName(str(selected.get("code", &"INVALID_ARGUMENT")))
		if selected_code == &"INVALID_PHASE":
			return _reject_floor_operation("begin_route_transition")
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{
				"field": "edge_id",
				"edge_id": str(edge_id),
				"reason": str(selected_code).to_lower(),
			}
		)
	var transition_id := "%s:route-%d" % [_state.run_id, _next_route_transition_id]
	_next_route_transition_id += 1
	_state.phase = RunPhaseScript.Value.ROOM_TRANSITION
	var staged_revision: int = int(_state.advance_revision())
	var node_id := str(selected.get("node_id", ""))
	_pending_route_transition = {
		"transition_id": transition_id,
		"before": before.duplicate(true),
		"floor_id": str(_state.floor_plan.get("floor_id", "")),
		"floor_index": int(_state.current_floor_index),
		"edge_id": str(edge_id),
		"node_id": node_id,
		"staged_revision": staged_revision,
	}
	return CommandResultScript.success(
		staged_revision,
		{
			"transition_id": transition_id,
			"floor_id": str(_pending_route_transition["floor_id"]),
			"floor_index": int(_pending_route_transition["floor_index"]),
			"edge_id": str(edge_id),
			"node_id": node_id,
			"pending_transition": true,
		}
	)


func finalize_route_transition(transition_id: String, expected_revision: int):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	var pending_validation = _validate_pending_route_transition(
		transition_id, "finalize_route_transition"
	)
	if not pending_validation.ok:
		return pending_validation
	if _state.phase != RunPhaseScript.Value.ROOM_TRANSITION:
		return _reject_floor_operation("finalize_route_transition")
	var committed := _pending_route_transition.duplicate(true)
	_pending_route_transition.clear()
	_state.phase = RunPhaseScript.Value.ROOM_ENTERING
	var committed_revision: int = int(_state.advance_revision())
	return CommandResultScript.success(
		committed_revision,
		{
			"transition_id": transition_id,
			"floor_id": str(committed["floor_id"]),
			"floor_index": int(committed["floor_index"]),
			"edge_id": str(committed["edge_id"]),
			"node_id": str(committed["node_id"]),
			"pending_transition": false,
		}
	)


func rollback_route_transition(transition_id: String, expected_revision: int):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	var pending_validation = _validate_pending_route_transition(
		transition_id, "rollback_route_transition"
	)
	if not pending_validation.ok:
		return pending_validation
	var before: Dictionary = _pending_route_transition.get("before", {}).duplicate(true)
	if not _state.restore_floor_transaction_snapshot(before):
		return CommandResultScript.failure(
			&"INTEGRITY_FAILURE",
			_state.revision,
			{"stage": "route_transition_rollback", "transition_id": transition_id}
		)
	_pending_route_transition.clear()
	return CommandResultScript.success(
		_state.revision,
		{"transition_id": transition_id, "rolled_back": true}
	)


func enter_floor_node(node_id: String, expected_revision: int):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if (
		_state.phase != RunPhaseScript.Value.ROOM_ENTERING
		or not _state.is_launch_floor_mode()
		or not _pending_route_transition.is_empty()
	):
		return _reject_floor_operation("enter_floor_node")
	var node: Dictionary = _state.current_floor_node()
	if (
		node.is_empty()
		or node_id.is_empty()
		or node_id != str(node.get("id", ""))
		or node_id == str(_state.floor_plan.get("entry_node_id", "entry"))
		or not bool(node.get("visited", false))
		or bool(node.get("cleared", false))
	):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "node_id", "node_id": node_id}
		)
	_state.phase = _active_phase_for_room_type(str(node.get("room_type", "")))
	return CommandResultScript.success(
		_state.advance_revision(),
		{"floor_id": str(_state.floor_plan.get("floor_id", "")), "node": node}
	)


func complete_floor_node(node_id: String, expected_revision: int):
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if not _state.is_launch_floor_mode() or not _pending_route_transition.is_empty():
		return _reject_floor_operation("complete_floor_node")
	var node: Dictionary = _state.current_floor_node()
	if node.is_empty() or _state.phase != _active_phase_for_room_type(str(node.get("room_type", ""))):
		return _reject_floor_operation("complete_floor_node")
	if node_id.is_empty() or node_id != str(node.get("id", "")):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "node_id", "node_id": node_id}
		)
	var completed: Dictionary = _state.complete_current_floor_node(node_id)
	if not bool(completed.get("ok", false)):
		return CommandResultScript.failure(
			StringName(str(completed.get("code", &"INVALID_ARGUMENT"))),
			_state.revision,
			(completed.get("context", {}) as Dictionary).duplicate(true)
		)
	_state.phase = RunPhaseScript.Value.ROOM_RESOLVING
	return CommandResultScript.success(
		_state.advance_revision(),
		{
			"floor_id": str(_state.floor_plan.get("floor_id", "")),
			"floor_index": int(_state.current_floor_index),
			"node": _state.current_floor_node(),
		}
	)


func complete_floor(context: Dictionary = {}, expected_revision: int = -1):
	if expected_revision < 0:
		expected_revision = int(_state.revision)
	var revision_validation = _validate_expected_revision(expected_revision)
	if not revision_validation.ok:
		return revision_validation
	if (
		not _state.is_launch_floor_mode()
		or not _pending_route_transition.is_empty()
		or _state.phase != RunPhaseScript.Value.ROOM_RESOLVING
	):
		return _reject_floor_operation("complete_floor")
	var node: Dictionary = _state.current_floor_node()
	if (
		node.is_empty()
		or str(node.get("id", "")) != str(_state.floor_plan.get("boss_node_id", ""))
		or str(node.get("room_type", "")) != "boss"
		or not bool(node.get("cleared", false))
	):
		return _reject_floor_operation("complete_floor")
	var floor_id := str(_state.floor_plan.get("floor_id", ""))
	var floor_index := int(_state.current_floor_index)
	if not _state.append_completed_floor():
		return CommandResultScript.failure(
			&"COMMIT_FAILED",
			_state.revision,
			{"field": "completed_floor_ids", "floor_id": floor_id}
		)
	var terminal := floor_index == 4
	if terminal:
		_state.result = context.duplicate(true)
		if str(_state.result.get("result", "")).is_empty():
			_state.result["result"] = "victory"
		_state.result["floor_id"] = floor_id
		_state.result["floor_index"] = floor_index
		_state.phase = RunPhaseScript.Value.VICTORY
	else:
		_state.phase = RunPhaseScript.Value.RUN_PREPARING
	var completed_revision: int = int(_state.advance_revision())
	return CommandResultScript.success(
		completed_revision,
		{
			"floor_id": floor_id,
			"floor_index": floor_index,
			"terminal": terminal,
			"completed_floor_ids": (_state.completed_floor_ids as Array).duplicate(),
		}
	)


func preparation_completed():
	if _state.phase != RunPhaseScript.Value.RUN_PREPARING:
		return _reject_phase()
	_state.current_room = 1
	return _accept_phase(RunPhaseScript.Value.ROOM_ENTERING)


func room_entered(is_boss: bool):
	if _state.phase != RunPhaseScript.Value.ROOM_ENTERING:
		return _reject_phase()
	return _accept_phase(
		RunPhaseScript.Value.BOSS_ACTIVE if is_boss else RunPhaseScript.Value.COMBAT_ACTIVE
	)


func room_cleared():
	if _state.phase != RunPhaseScript.Value.COMBAT_ACTIVE:
		return _reject_phase()
	return _accept_phase(RunPhaseScript.Value.ROOM_RESOLVING)


func open_selection(offer: Dictionary):
	if _state.phase != RunPhaseScript.Value.ROOM_RESOLVING:
		return _reject_phase()
	var validation = SelectionOfferScript.validate(offer)
	if not validation.ok:
		return CommandResultScript.failure(validation.code, _state.revision, validation.context)
	var offer_id := str(offer["offer_id"])
	if _state.has_consumed_offer(offer_id):
		return CommandResultScript.failure(&"ALREADY_CONSUMED", _state.revision, {"offer_id": offer_id})
	if int(offer["revision"]) != _state.revision:
		return CommandResultScript.failure(&"STALE_REVISION", _state.revision)
	_state.open_offer = SelectionOfferScript.copy_of(offer)
	return _accept_phase(RunPhaseScript.Value.SELECTION_ACTIVE)


func selection_resolved(definition: Dictionary = {}):
	if _state.phase != RunPhaseScript.Value.SELECTION_ACTIVE:
		return _reject_phase()
	var definition_validation = _validate_selected_definition(definition)
	if not definition_validation.ok:
		return definition_validation
	var before: Dictionary = _state.selection_transaction_snapshot()
	var offer_id := str(_state.open_offer.get("offer_id", ""))
	if not _state.mark_offer_consumed(offer_id):
		return CommandResultScript.failure(&"ALREADY_CONSUMED", _state.revision, {"offer_id": offer_id})
	var build_result := _record_selected_definition(definition)
	if not bool(build_result.get("ok", false)):
		if not _state.restore_selection_transaction_snapshot(before):
			push_error("Legacy selection rollback failed after BuildState rejection")
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_state.revision,
				{
					"field": str(build_result.get("field", "build")),
					"stage": "build_state_rollback",
				}
			)
		return CommandResultScript.failure(
			&"COMMIT_FAILED",
			_state.revision,
			{"field": str(build_result.get("field", "build"))}
		)
	_state.open_offer = {}
	return _accept_phase(RunPhaseScript.Value.ROOM_TRANSITION)


func validate_selection_commit(definition: Dictionary = {}):
	if _state.phase != RunPhaseScript.Value.SELECTION_ACTIVE:
		return _reject_phase()
	return _validate_selected_definition(definition)


func commit_selection_and_transition(definition: Dictionary = {}):
	var validation = validate_selection_commit(definition)
	if not validation.ok:
		return validation
	var before: Dictionary = _state.selection_transaction_snapshot()
	var offer_id := str(_state.open_offer.get("offer_id", ""))
	if not _state.mark_offer_consumed(offer_id):
		return CommandResultScript.failure(
			&"ALREADY_CONSUMED",
			_state.revision,
			{"offer_id": offer_id}
		)
	var build_result := _record_selected_definition(definition)
	if not bool(build_result.get("ok", false)):
		if not _state.restore_selection_transaction_snapshot(before):
			push_error("Selection commit rollback failed after BuildState rejection")
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_state.revision,
				{
					"field": str(build_result.get("field", "build")),
					"stage": "build_state_rollback",
				}
			)
		return CommandResultScript.failure(
			&"COMMIT_FAILED",
			_state.revision,
			{"field": str(build_result.get("field", "build"))}
		)
	_state.open_offer = {}
	if _state.is_launch_floor_mode():
		return _accept_phase(RunPhaseScript.Value.ROOM_RESOLVING)
	_state.phase = RunPhaseScript.Value.ROOM_TRANSITION
	var selection_revision: int = int(_state.advance_revision())
	_state.current_room += 1
	_state.phase = RunPhaseScript.Value.ROOM_ENTERING
	var transition_revision: int = int(_state.advance_revision())
	return CommandResultScript.success(
		transition_revision,
		{
			"offer_id": offer_id,
			"selection_revision": selection_revision,
			"build_result": build_result.duplicate(true),
		}
	)


func transition_completed():
	if _state.phase != RunPhaseScript.Value.ROOM_TRANSITION:
		return _reject_phase()
	_state.current_room += 1
	return _accept_phase(RunPhaseScript.Value.ROOM_ENTERING)


func player_died(context: Dictionary = {}):
	if _state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _state.revision)
	if _state.phase not in [
		RunPhaseScript.Value.ROOM_ENTERING,
		RunPhaseScript.Value.COMBAT_ACTIVE,
		RunPhaseScript.Value.ROOM_RESOLVING,
		RunPhaseScript.Value.SELECTION_ACTIVE,
		RunPhaseScript.Value.ROOM_TRANSITION,
		RunPhaseScript.Value.BOSS_ACTIVE,
		RunPhaseScript.Value.ROOM_ACTIVE,
	]:
		return _reject_phase()
	if not _pending_route_transition.is_empty():
		var transition_id := str(_pending_route_transition.get("transition_id", ""))
		var before: Dictionary = _pending_route_transition.get("before", {}).duplicate(true)
		if not _state.restore_floor_transaction_snapshot(before):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_state.revision,
				{
					"stage": "route_transition_death_rollback",
					"transition_id": transition_id,
				}
			)
		_pending_route_transition.clear()
	_state.open_offer = {}
	_state.result = context.duplicate(true)
	return _accept_phase(RunPhaseScript.Value.DEFEAT)


func boss_defeated(context: Dictionary = {}):
	if _state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _state.revision)
	if _state.phase != RunPhaseScript.Value.BOSS_ACTIVE:
		return _reject_phase()
	if _state.is_launch_floor_mode() and _state.has_active_floor_plan():
		var before: Dictionary = _state.floor_transaction_snapshot()
		var node_id := str(_state.floor_plan.get("current_node_id", ""))
		var node_completed = complete_floor_node(node_id, _state.revision)
		if not node_completed.ok:
			return node_completed
		var floor_completed = complete_floor(context, _state.revision)
		if floor_completed.ok:
			return floor_completed
		if not _state.restore_floor_transaction_snapshot(before):
			return CommandResultScript.failure(
				&"INTEGRITY_FAILURE",
				_state.revision,
				{"stage": "boss_floor_completion_rollback"}
			)
		return floor_completed
	_state.open_offer = {}
	_state.result = context.duplicate(true)
	return _accept_phase(RunPhaseScript.Value.VICTORY)


func pause_run():
	if _state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _state.revision)
	if _state.phase in [RunPhaseScript.Value.BOOT, RunPhaseScript.Value.HUB] or _state.suspended:
		return _reject_phase()
	_state.suspended = true
	return _accept_without_phase_change()


func resume_run():
	if _state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _state.revision)
	if not _state.suspended:
		return _reject_phase()
	_state.suspended = false
	return _accept_without_phase_change()


func advance_time(delta_seconds: float):
	if not is_finite(delta_seconds) or delta_seconds < 0.0:
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "delta_seconds"}
		)
	if _state.suspended or _state.is_terminal() or _state.phase in [
		RunPhaseScript.Value.BOOT,
		RunPhaseScript.Value.HUB,
	]:
		return CommandResultScript.success(
			_state.revision,
			{"advanced_ms": 0, "run_time_ms": _state.run_time_ms}
		)
	var advanced_ms: int = int(_state.advance_time(delta_seconds))
	return CommandResultScript.success(
		_state.revision,
		{"advanced_ms": advanced_ms, "run_time_ms": _state.run_time_ms}
	)


func _accept_phase(next_phase: int):
	_state.phase = next_phase
	return CommandResultScript.success(_state.advance_revision())


func _accept_without_phase_change():
	return CommandResultScript.success(_state.advance_revision())


func _validate_expected_revision(expected_revision: int):
	if expected_revision != int(_state.revision):
		return CommandResultScript.failure(
			&"STALE_REVISION",
			_state.revision,
			{
				"received_revision": expected_revision,
				"last_revision": int(_state.revision),
			}
		)
	return CommandResultScript.success(_state.revision)


func _validate_pending_route_transition(transition_id: String, operation: String):
	if (
		_pending_route_transition.is_empty()
		or transition_id.is_empty()
		or transition_id != str(_pending_route_transition.get("transition_id", ""))
	):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "transition_id", "operation": operation}
		)
	return CommandResultScript.success(_state.revision)


func _reject_floor_operation(operation: String):
	if _state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _state.revision)
	return CommandResultScript.failure(
		&"INVALID_PHASE", _state.revision, {"operation": operation}
	)


func _active_phase_for_room_type(room_type: String) -> int:
	if room_type == "boss":
		return RunPhaseScript.Value.BOSS_ACTIVE
	if room_type == "combat" or room_type == "elite":
		return RunPhaseScript.Value.COMBAT_ACTIVE
	return RunPhaseScript.Value.ROOM_ACTIVE


func _validate_selected_definition(definition: Dictionary):
	if definition.is_empty():
		return CommandResultScript.success(_state.revision)
	var content_id := str(definition.get("id", ""))
	var category := str(definition.get("category", ""))
	if content_id.is_empty():
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "definition.id"}
		)
	if category not in ["item", "blessing", "curse", "talent", "contract"]:
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "definition.category"}
		)
	if category == "contract" and content_id != "decline_contract":
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{"field": "definition.id"}
		)
	var build_validation: Dictionary = _state.build_state.validate_definition(definition)
	if not bool(build_validation.get("ok", false)):
		return CommandResultScript.failure(
			&"INVALID_ARGUMENT",
			_state.revision,
			{
				"field": str(build_validation.get("field", "definition")),
				"reason": str(build_validation.get("reason", "invalid")),
			}
		)
	return CommandResultScript.success(_state.revision)


func _record_selected_definition(definition: Dictionary) -> Dictionary:
	if definition.is_empty():
		return {"ok": true, "changed": false}
	return _state.apply_reward_definition(definition)


func _reject_phase():
	if _state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _state.revision)
	return CommandResultScript.failure(&"INVALID_PHASE", _state.revision)
