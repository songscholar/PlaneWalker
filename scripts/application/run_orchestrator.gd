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
	var offer_id := str(_state.open_offer.get("offer_id", ""))
	if not _state.mark_offer_consumed(offer_id):
		return CommandResultScript.failure(&"ALREADY_CONSUMED", _state.revision, {"offer_id": offer_id})
	_record_selected_definition(definition)
	_state.open_offer = {}
	return _accept_phase(RunPhaseScript.Value.ROOM_TRANSITION)


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
	return CommandResultScript.success(_state.revision)


func _record_selected_definition(definition: Dictionary) -> void:
	match str(definition.get("category", "")):
		"item":
			_state.build_state.record_item(definition)
		"blessing":
			_state.build_state.record_blessing(definition)
		"curse":
			_state.build_state.record_curse(definition)
		"talent":
			_state.build_state.record_talent(definition)


func _reject_phase():
	if _state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", _state.revision)
	return CommandResultScript.failure(&"INVALID_PHASE", _state.revision)
