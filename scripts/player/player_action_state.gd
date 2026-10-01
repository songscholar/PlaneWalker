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
	&"RESOURCE_ACTION": State.ATTACK_RECOVERY,
}
const BUFFERED_INPUT_PRIORITY: Array[StringName] = [
	&"dash",
	&"time_cast",
	&"combo",
	&"attack",
]
const SNAPSHOT_SCHEMA_VERSION := 1
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"revision",
	"frame",
	"buffers",
	"current_state",
	"state_frame",
	"state_duration_frames",
	"cancel_from_frame",
	"weapon_projection_active",
	"weapon_phase",
]

var current_state: State = State.FREE

var _revision: int = 0
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
	var expires_at := _frame + maxi(1, frames)
	if int(_buffers.get(action_id, -1)) == expires_at:
		return
	_buffers[action_id] = expires_at
	_advance_revision()


func has_buffered_input(action_id: StringName) -> bool:
	return int(_buffers.get(action_id, -1)) > _frame


func consume_buffered_input(action_id: StringName) -> bool:
	if not has_buffered_input(action_id):
		return false
	_buffers.erase(action_id)
	_advance_revision()
	return true


func consume_highest_priority_buffered_input() -> StringName:
	for action_id: StringName in BUFFERED_INPUT_PRIORITY:
		if not has_buffered_input(action_id):
			continue
		var next_state := _state_for_buffered_input(action_id)
		if next_state < 0 or not can_transition_to(next_state as State):
			continue
		_buffers.erase(action_id)
		_advance_revision()
		return action_id
	return &""


func clear_buffered_inputs() -> void:
	if _buffers.is_empty():
		return
	_buffers.clear()
	_advance_revision()


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
	_advance_revision()
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
	if phase in [&"RECOVERY", &"RESOURCE_ACTION"]:
		if cancel_from_frame >= duration_frames:
			return false
	elif cancel_from_frame != -1:
		return false

	var projected_state := int(WEAPON_PHASE_TO_STATE[phase]) as State
	var projected_cancel := cancel_from_frame if phase in [&"RECOVERY", &"RESOURCE_ACTION"] else -1
	var changed := (
		current_state != projected_state
		or _state_frame != phase_frame
		or _state_duration_frames != duration_frames
		or _cancel_from_frame != projected_cancel
		or not _weapon_projection_active
		or _weapon_phase != phase
	)
	current_state = projected_state
	_state_frame = phase_frame
	_state_duration_frames = duration_frames
	_cancel_from_frame = projected_cancel
	_weapon_projection_active = true
	_weapon_phase = phase
	if changed:
		_advance_revision()
	return true


func clear_weapon_projection() -> bool:
	if current_state != State.FREE and not _is_weapon_state(current_state):
		return false
	var changed := not _is_free_action_state()
	_return_to_free()
	if changed:
		_advance_revision()
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
	if _weapon_projection_active and _weapon_phase == &"RESOURCE_ACTION":
		return _recovery_cancel_is_open() and next_state == State.DASH

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
	_advance_buffer_frame_unversioned()
	if not _weapon_projection_active and current_state != State.FREE:
		_state_frame += 1
		if current_state != State.DEAD and is_state_complete():
			if current_state in [State.ATTACK_WINDUP, State.ATTACK_ACTIVE]:
				_state_frame = _state_duration_frames
			else:
				_return_to_free()
	_advance_revision()


func advance_buffer_frame() -> void:
	_advance_buffer_frame_unversioned()
	_advance_revision()


func _advance_buffer_frame_unversioned() -> void:
	_frame += 1
	_prune_expired_buffers()


func is_state_complete() -> bool:
	return current_state not in [State.FREE, State.DEAD] and _state_frame >= _state_duration_frames


func force_safe_reset() -> bool:
	if current_state == State.DEAD:
		return false
	var changed := not _buffers.is_empty() or not _is_free_action_state()
	_buffers.clear()
	_return_to_free()
	if changed:
		_advance_revision()
	return true


func reset_runtime_state() -> void:
	var changed := _frame != 0 or not _buffers.is_empty() or not _is_free_action_state()
	_frame = 0
	_buffers.clear()
	_return_to_free()
	if changed:
		_advance_revision()


func revision() -> int:
	return _revision


func snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"revision": _revision,
		"frame": _frame,
		"buffers": _buffers.duplicate(true),
		"current_state": int(current_state),
		"state_frame": _state_frame,
		"state_duration_frames": _state_duration_frames,
		"cancel_from_frame": _cancel_from_frame,
		"weapon_projection_active": _weapon_projection_active,
		"weapon_phase": _weapon_phase,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	var validated := _validated_snapshot(value)
	return not validated.is_empty() and int(validated["revision"]) <= _revision


func restore_transaction_snapshot(value: Dictionary) -> bool:
	var validated := _validated_snapshot(value)
	if validated.is_empty() or int(validated["revision"]) > _revision:
		return false
	_install_validated_snapshot(validated)
	return true


func restore_replay_snapshot(value: Dictionary) -> bool:
	var validated := _validated_snapshot(value)
	if validated.is_empty():
		return false
	_install_validated_snapshot(validated)
	return snapshot() == validated


func can_restore_replay_snapshot(value: Dictionary) -> bool:
	return not _validated_snapshot(value).is_empty()


func _install_validated_snapshot(validated: Dictionary) -> void:
	_revision = int(validated["revision"])
	_frame = int(validated["frame"])
	_buffers = (validated["buffers"] as Dictionary).duplicate(true)
	current_state = int(validated["current_state"]) as State
	_state_frame = int(validated["state_frame"])
	_state_duration_frames = int(validated["state_duration_frames"])
	_cancel_from_frame = int(validated["cancel_from_frame"])
	_weapon_projection_active = bool(validated["weapon_projection_active"])
	_weapon_phase = validated["weapon_phase"] as StringName


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


func _is_free_action_state() -> bool:
	return (
		current_state == State.FREE
		and _state_frame == 0
		and _state_duration_frames == 0
		and _cancel_from_frame == -1
		and not _weapon_projection_active
		and _weapon_phase == &""
	)


func _is_weapon_state(state: State) -> bool:
	return state in [State.ATTACK_WINDUP, State.ATTACK_ACTIVE, State.ATTACK_RECOVERY]


func _prune_expired_buffers() -> void:
	for action_id: Variant in _buffers.keys():
		if int(_buffers[action_id]) <= _frame:
			_buffers.erase(action_id)


func _advance_revision() -> void:
	_revision += 1


static func _validated_snapshot(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return {}
	if typeof(value["schema_version"]) != TYPE_INT or int(value["schema_version"]) != SNAPSHOT_SCHEMA_VERSION:
		return {}
	if typeof(value["revision"]) != TYPE_INT or int(value["revision"]) < 0:
		return {}
	if typeof(value["frame"]) != TYPE_INT or int(value["frame"]) < 0:
		return {}
	if not value["buffers"] is Dictionary:
		return {}
	if typeof(value["current_state"]) != TYPE_INT:
		return {}
	var restored_state := int(value["current_state"])
	if restored_state < State.FREE or restored_state > State.DEAD:
		return {}
	if typeof(value["state_frame"]) != TYPE_INT or int(value["state_frame"]) < 0:
		return {}
	if typeof(value["state_duration_frames"]) != TYPE_INT or int(value["state_duration_frames"]) < 0:
		return {}
	if typeof(value["cancel_from_frame"]) != TYPE_INT or int(value["cancel_from_frame"]) < -1:
		return {}
	if typeof(value["weapon_projection_active"]) != TYPE_BOOL:
		return {}
	if typeof(value["weapon_phase"]) != TYPE_STRING and typeof(value["weapon_phase"]) != TYPE_STRING_NAME:
		return {}

	var restored_frame := int(value["frame"])
	var restored_buffers: Dictionary = {}
	for action_id_value: Variant in (value["buffers"] as Dictionary).keys():
		if typeof(action_id_value) != TYPE_STRING and typeof(action_id_value) != TYPE_STRING_NAME:
			return {}
		var action_id := StringName(str(action_id_value))
		if action_id == &"" or restored_buffers.has(action_id):
			return {}
		var expires_at: Variant = (value["buffers"] as Dictionary)[action_id_value]
		if typeof(expires_at) != TYPE_INT or int(expires_at) <= restored_frame:
			return {}
		restored_buffers[action_id] = int(expires_at)

	var state_frame := int(value["state_frame"])
	var state_duration_frames := int(value["state_duration_frames"])
	var cancel_from_frame := int(value["cancel_from_frame"])
	var projection_active := bool(value["weapon_projection_active"])
	var weapon_phase := StringName(str(value["weapon_phase"]))
	if not _snapshot_runtime_is_valid(
		restored_state,
		state_frame,
		state_duration_frames,
		cancel_from_frame,
		projection_active,
		weapon_phase
	):
		return {}

	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"revision": int(value["revision"]),
		"frame": restored_frame,
		"buffers": restored_buffers,
		"current_state": restored_state,
		"state_frame": state_frame,
		"state_duration_frames": state_duration_frames,
		"cancel_from_frame": cancel_from_frame,
		"weapon_projection_active": projection_active,
		"weapon_phase": weapon_phase,
	}


static func _snapshot_runtime_is_valid(
	restored_state: int,
	state_frame: int,
	state_duration_frames: int,
	cancel_from_frame: int,
	projection_active: bool,
	weapon_phase: StringName
) -> bool:
	if restored_state == State.FREE:
		return (
			state_frame == 0
			and state_duration_frames == 0
			and cancel_from_frame == -1
			and not projection_active
			and weapon_phase == &""
		)
	if restored_state == State.DEAD:
		return (
			state_duration_frames == 0
			and cancel_from_frame == -1
			and not projection_active
			and weapon_phase == &""
		)
	if state_duration_frames <= 0:
		return false
	if restored_state in [State.ATTACK_WINDUP, State.ATTACK_ACTIVE]:
		if state_frame > state_duration_frames:
			return false
	elif state_frame >= state_duration_frames:
		return false
	if restored_state != State.ATTACK_RECOVERY and cancel_from_frame != -1:
		return false
	if not projection_active:
		return weapon_phase == &""
	if not WEAPON_PHASE_TO_STATE.has(weapon_phase):
		return false
	if int(WEAPON_PHASE_TO_STATE[weapon_phase]) != restored_state or state_frame >= state_duration_frames:
		return false
	if weapon_phase in [&"RECOVERY", &"RESOURCE_ACTION"]:
		return cancel_from_frame < state_duration_frames
	return cancel_from_frame == -1


static func _has_exact_fields(value: Dictionary, expected_fields: Array[String]) -> bool:
	if value.size() != expected_fields.size():
		return false
	for field: String in expected_fields:
		if not value.has(field):
			return false
	for key: Variant in value.keys():
		if (typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME) or not expected_fields.has(str(key)):
			return false
	return true
