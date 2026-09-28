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


func transition_to(next_state: State, duration_frames: int, cancel_from_frame: int = -1) -> bool:
	if next_state != State.DEAD and duration_frames <= 0:
		return false
	if not can_transition_to(next_state):
		return false
	current_state = next_state
	_state_frame = 0
	_state_duration_frames = 0 if next_state == State.DEAD else maxi(1, duration_frames)
	_cancel_from_frame = maxi(0, cancel_from_frame) if next_state == State.ATTACK_RECOVERY and cancel_from_frame >= 0 else -1
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
	_frame += 1
	_prune_expired_buffers()
	if current_state == State.FREE:
		return
	_state_frame += 1
	if current_state == State.DEAD:
		return
	if _state_frame >= _state_duration_frames:
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


func _prune_expired_buffers() -> void:
	for action_id: Variant in _buffers.keys():
		if int(_buffers[action_id]) <= _frame:
			_buffers.erase(action_id)
