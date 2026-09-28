class_name RunOrchestrator
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunConfigScript := preload("res://scripts/application/run_config.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunStateScript := preload("res://scripts/application/run_state.gd")
const SelectionOfferScript := preload("res://scripts/application/selection_offer.gd")

var state: RefCounted


func _init() -> void:
	state = RunStateScript.new()


func enter_hub():
	if state.phase != RunPhaseScript.Value.BOOT:
		return _reject_phase()
	return _accept_phase(RunPhaseScript.Value.HUB)


func start_run(config: Dictionary, run_id: String):
	if state.phase != RunPhaseScript.Value.HUB:
		return _reject_phase()
	var validation = RunConfigScript.validate(config)
	if not validation.ok:
		return CommandResultScript.failure(validation.code, state.revision, validation.context)
	if run_id.is_empty():
		return CommandResultScript.failure(&"INVALID_ARGUMENT", state.revision, {"field": "run_id"})
	state.reset(config, run_id)
	return _accept_phase(RunPhaseScript.Value.RUN_PREPARING)


func preparation_completed():
	if state.phase != RunPhaseScript.Value.RUN_PREPARING:
		return _reject_phase()
	state.current_room = 1
	return _accept_phase(RunPhaseScript.Value.ROOM_ENTERING)


func room_entered(is_boss: bool):
	if state.phase != RunPhaseScript.Value.ROOM_ENTERING:
		return _reject_phase()
	return _accept_phase(
		RunPhaseScript.Value.BOSS_ACTIVE if is_boss else RunPhaseScript.Value.COMBAT_ACTIVE
	)


func room_cleared():
	if state.phase != RunPhaseScript.Value.COMBAT_ACTIVE:
		return _reject_phase()
	return _accept_phase(RunPhaseScript.Value.ROOM_RESOLVING)


func open_selection(offer: Dictionary):
	if state.phase != RunPhaseScript.Value.ROOM_RESOLVING:
		return _reject_phase()
	var validation = SelectionOfferScript.validate(offer)
	if not validation.ok:
		return CommandResultScript.failure(validation.code, state.revision, validation.context)
	var offer_id := str(offer["offer_id"])
	if state.has_consumed_offer(offer_id):
		return CommandResultScript.failure(&"ALREADY_CONSUMED", state.revision, {"offer_id": offer_id})
	if int(offer["revision"]) != state.revision:
		return CommandResultScript.failure(&"STALE_REVISION", state.revision)
	state.open_offer = SelectionOfferScript.copy_of(offer)
	return _accept_phase(RunPhaseScript.Value.SELECTION_ACTIVE)


func selection_resolved():
	if state.phase != RunPhaseScript.Value.SELECTION_ACTIVE:
		return _reject_phase()
	var offer_id := str(state.open_offer.get("offer_id", ""))
	if not state.mark_offer_consumed(offer_id):
		return CommandResultScript.failure(&"ALREADY_CONSUMED", state.revision, {"offer_id": offer_id})
	state.open_offer = {}
	return _accept_phase(RunPhaseScript.Value.ROOM_TRANSITION)


func transition_completed():
	if state.phase != RunPhaseScript.Value.ROOM_TRANSITION:
		return _reject_phase()
	state.current_room += 1
	return _accept_phase(RunPhaseScript.Value.ROOM_ENTERING)


func player_died(context: Dictionary = {}):
	if state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", state.revision)
	if state.phase not in [
		RunPhaseScript.Value.ROOM_ENTERING,
		RunPhaseScript.Value.COMBAT_ACTIVE,
		RunPhaseScript.Value.BOSS_ACTIVE,
	]:
		return _reject_phase()
	state.result = context.duplicate(true)
	return _accept_phase(RunPhaseScript.Value.DEFEAT)


func boss_defeated(context: Dictionary = {}):
	if state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", state.revision)
	if state.phase != RunPhaseScript.Value.BOSS_ACTIVE:
		return _reject_phase()
	state.open_offer = {}
	state.result = context.duplicate(true)
	return _accept_phase(RunPhaseScript.Value.VICTORY)


func pause_run():
	if state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", state.revision)
	if state.phase in [RunPhaseScript.Value.BOOT, RunPhaseScript.Value.HUB] or state.suspended:
		return _reject_phase()
	state.suspended = true
	return _accept_without_phase_change()


func resume_run():
	if state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", state.revision)
	if not state.suspended:
		return _reject_phase()
	state.suspended = false
	return _accept_without_phase_change()


func _accept_phase(next_phase: int):
	state.phase = next_phase
	return CommandResultScript.success(state.advance_revision())


func _accept_without_phase_change():
	return CommandResultScript.success(state.advance_revision())


func _reject_phase():
	if state.is_terminal():
		return CommandResultScript.failure(&"TERMINAL_STATE", state.revision)
	return CommandResultScript.failure(&"INVALID_PHASE", state.revision)
