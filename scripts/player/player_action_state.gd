class_name PlayerActionState
extends RefCounted

enum State {
	FREE,
	ATTACK_WINDUP,
	ATTACK_ACTIVE,
	ATTACK_RECOVERY,
	DASH,
	TIME_CAST,
	HITSTUN,
	DEAD,
}

const INPUT_BUFFER_FRAMES := 8
const COMBO_BUFFER_FRAMES := 12
const WEAPON_PHASE_TO_STATE: Dictionary = {
	&"HOLD": State.ATTACK_WINDUP,
	&"WINDUP": State.ATTACK_WINDUP,
	&"ACTIVE": State.ATTACK_ACTIVE,
	&"RECOVERY": State.ATTACK_RECOVERY,
}
const BUFFERED_INPUT_PRIORITY: Array[StringName] = [
	&"dash",
	&"time_cast",
	&"combo",
	&"attack",
]

var current_state: State = State.FREE

var _frame: int = 0
var _buffers: Dictionary = {}
var _state_frame: int = 0
var _state_duration_frames: int = 0
var _cancel_from_frame: int = -1
var _weapon_projection_active: bool = false
var _weapon_phase: StringName = &""


func buffer_input(action_id: StringName, frames: int = INPUT_BUFFER_FRAMES) -> void:
	if str(action_id).is_empty():
		return
	_buffers[action_id] = _frame + maxi(1, frames)


func has_buffered_input(action_id: StringName) -> bool:
	return int(_buffers.get(action_id, -1)) > _frame


func consume_buffered_input(action_id: StringName) -> bool:
	if not has_buffered_input(action_id):
		return false
	_buffers.erase(action_id)
	return true


func consume_highest_priority_buffered_input() -> StringName:
	for action_id: StringName in BUFFERED_INPUT_PRIORITY:
		if not has_buffered_input(action_id):
			continue
		var next_state := _state_for_buffered_input(action_id)
		if next_state < 0 or not can_transition_to(next_state as State):
			continue
		_buffers.erase(action_id)
		return action_id
	return &""


func clear_buffered_inputs() -> void:
	_buffers.clear()


func transition_to(next_state: State, duration_frames: int, cancel_from_frame: int = -1) -> bool:
	if next_state != State.DEAD and duration_frames <= 0:
		return false
	if not can_transition_to(next_state):
		return false
	current_state = next_state
	_state_frame = 0
	_state_duration_frames = 0 if next_state == State.DEAD else maxi(1, duration_frames)
	_cancel_from_frame = maxi(0, cancel_from_frame) if next_state == State.ATTACK_RECOVERY and cancel_from_frame >= 0 else -1
	_weapon_projection_active = false
	_weapon_phase = &""
	return true


func project_weapon_phase(
	phase: StringName,
	phase_frame: int,
	duration_frames: int,
	cancel_from_frame: int = -1
) -> bool:
	if current_state != State.FREE and not _is_weapon_state(current_state):
		return false
	if not WEAPON_PHASE_TO_STATE.has(phase):
		return false
	if duration_frames <= 0 or phase_frame < 0 or phase_frame >= duration_frames:
		return false
	if cancel_from_frame < -1:
		return false
	if phase == &"RECOVERY":
		if cancel_from_frame >= duration_frames:
			return false
	elif cancel_from_frame != -1:
		return false

	current_state = int(WEAPON_PHASE_TO_STATE[phase]) as State
	_state_frame = phase_frame
	_state_duration_frames = duration_frames
	_cancel_from_frame = cancel_from_frame if phase == &"RECOVERY" else -1
	_weapon_projection_active = true
	_weapon_phase = phase
	return true


func clear_weapon_projection() -> bool:
	if current_state != State.FREE and not _is_weapon_state(current_state):
		return false
	_return_to_free()
	return true


func can_transition_to(next_state: State) -> bool:
	if current_state == State.DEAD or next_state == current_state:
		return false
	if next_state == State.DEAD:
		return true
	if next_state == State.HITSTUN:
		return current_state != State.DEAD
	if current_state == State.HITSTUN:
		return false
	if _weapon_projection_active and _weapon_phase == &"HOLD":
		return next_state in [State.DASH, State.TIME_CAST]

	match current_state:
		State.FREE:
			return next_state in [State.ATTACK_WINDUP, State.DASH, State.TIME_CAST]
		State.ATTACK_WINDUP:
			return next_state == State.ATTACK_ACTIVE
		State.ATTACK_ACTIVE:
			return next_state == State.ATTACK_RECOVERY
		State.ATTACK_RECOVERY:
			return _recovery_cancel_is_open() and next_state in [State.ATTACK_WINDUP, State.DASH, State.TIME_CAST]
		_:
			return false


func advance_frame() -> void:
	advance_buffer_frame()
	if _weapon_projection_active:
		return
	if current_state == State.FREE:
		return
	_state_frame += 1
	if current_state == State.DEAD:
		return
	if not is_state_complete():
		return
	if current_state in [State.ATTACK_WINDUP, State.ATTACK_ACTIVE]:
		_state_frame = _state_duration_frames
		return
	_return_to_free()


func advance_buffer_frame() -> void:
	_frame += 1
	_prune_expired_buffers()


func is_state_complete() -> bool:
	return current_state not in [State.FREE, State.DEAD] and _state_frame >= _state_duration_frames


func force_safe_reset() -> bool:
	if current_state == State.DEAD:
		return false
	clear_buffered_inputs()
	_return_to_free()
	return true


func reset_runtime_state() -> void:
	_frame = 0
	clear_buffered_inputs()
	_return_to_free()


func elapsed_state_frames() -> int:
	return _state_frame


func remaining_state_frames() -> int:
	if current_state == State.FREE or current_state == State.DEAD:
		return 0
	return maxi(0, _state_duration_frames - _state_frame)


func _recovery_cancel_is_open() -> bool:
	return _cancel_from_frame >= 0 and _state_frame >= _cancel_from_frame


func _state_for_buffered_input(action_id: StringName) -> int:
	match action_id:
		&"dash":
			return State.DASH
		&"time_cast":
			return State.TIME_CAST
		&"combo", &"attack":
			return State.ATTACK_WINDUP
		_:
			return -1


func _return_to_free() -> void:
	current_state = State.FREE
	_state_frame = 0
	_state_duration_frames = 0
	_cancel_from_frame = -1
	_weapon_projection_active = false
	_weapon_phase = &""


func _is_weapon_state(state: State) -> bool:
	return state in [State.ATTACK_WINDUP, State.ATTACK_ACTIVE, State.ATTACK_RECOVERY]


func _prune_expired_buffers() -> void:
	for action_id: Variant in _buffers.keys():
		if int(_buffers[action_id]) <= _frame:
			_buffers.erase(action_id)
