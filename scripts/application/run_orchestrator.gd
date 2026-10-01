class_name RunOrchestrator
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunStateScript := preload("res://scripts/application/run_state.gd")
const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")

var _state: RefCounted


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
	return _accept_phase(RunPhaseScript.Value.RUN_PREPARING)


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
	]:
		return _reject_phase()
	_state.open_offer = {}
	_state.result = context.duplicate(true)
	return _accept_phase(RunPhaseScript.Value.DEFEAT)


func boss_defeated(context: Dictionary = {}):
	if _state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _state.revision)
	if _state.phase != RunPhaseScript.Value.BOSS_ACTIVE:
		return _reject_phase()
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
	return _state.build_state.apply_definition(definition)


func _reject_phase():
	if _state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _state.revision)
	return CommandResultScript.failure(&"INVALID_PHASE", _state.revision)
