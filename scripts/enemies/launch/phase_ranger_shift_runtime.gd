class_name PhaseRangerShiftRuntime
extends RefCounted

const Pattern := preload("res://scripts/enemies/launch/launch_elite_teleport_runtime.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const WARNING_FRAMES := 23


static func initial_state(enabled: bool = true) -> Dictionary:
	var state := Pattern.initial_state()
	state["enabled"] = enabled
	return state


static func parameters(authored: Dictionary) -> Dictionary:
	return {"interval_frames": int(authored.shift_cooldown_frames), "departure_warning_frames": WARNING_FRAMES, "arrival_recovery_frames": int(authored.shift_recovery_frames), "distance_max_px": float(authored.shift_distance_cap_px)}


static func reservation_due(state: Dictionary, authored: Dictionary) -> bool:
	return state.enabled and Pattern.reservation_due(_pattern(state), parameters(authored))


static func blocks_actions(state: Dictionary, authored: Dictionary, busy: bool = false) -> bool:
	return state.enabled and not (busy and state.phase == "IDLE") and (state.phase == "ARRIVAL" and int(state.remaining_frames) > 0 or Pattern.blocks_actions(_pattern(state), parameters(authored)))


static func candidate_offsets(state: Dictionary, identity: Dictionary, authored: Dictionary) -> Array[Vector2]:
	return Pattern.candidate_offsets(_identity(identity), state.reservations.size() + 1, float(authored.shift_distance_cap_px))


static func advance(state: Dictionary, frame: int, paused: bool, busy: bool, observation: Dictionary, authored: Dictionary) -> Dictionary:
	if not state.enabled:
		return {"state": state.duplicate(true), "relocation": {}}
	var result := Pattern.advance(_pattern(state), frame, paused or (busy and reservation_due(state, authored)), observation, parameters(authored))
	result.state["enabled"] = true
	return result


static func cancel(state: Dictionary) -> void:
	Pattern.cancel(state)


static func can_restore(state: Dictionary, identity: Dictionary, frame: int, terminal: bool, authored: Dictionary) -> bool:
	if not Contract.exact_fields(state, Pattern.FIELDS + ["enabled"]) or typeof(state.enabled) != TYPE_BOOL:
		return false
	if not state.enabled:
		return state == initial_state(false) and Pattern.can_restore(_pattern(state), _identity(identity), frame, terminal, parameters(authored))
	return Pattern.can_restore(_pattern(state), _identity(identity), frame, terminal, parameters(authored))


static func _pattern(state: Dictionary) -> Dictionary:
	var value := state.duplicate(true)
	value.erase("enabled")
	return value


static func _identity(identity: Dictionary) -> Dictionary:
	var value := identity.duplicate(true)
	value.hostile_source_id = str(value.hostile_source_id) + ":phase-shift"
	return value
