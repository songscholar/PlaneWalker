class_name LaunchEnemyRuntime
extends RefCounted

const Action := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Controls := preload("res://scripts/enemies/launch/hostile_control_runtime.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Seeds := preload("res://scripts/core/seed_service.gd")
const DEFINITION_FIELDS: Array[String] = ["id", "actor_kind", "runtime_kind", "max_hp", "defense", "move_speed", "actions"]
const IDENTITY_FIELDS: Array[String] = ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]
const STATE_FIELDS: Array[String] = ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "mechanism_state", "action", "control"]
const MECHANISM_FIELDS: Array[String] = ["first_attack_ready_frame", "retreat_remaining_frames", "retreat_direction"]

var _definition: Dictionary = {}
var _state: Dictionary = {}
var _action: RefCounted = Action.new()
var _control: RefCounted = Controls.new()


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	_definition.clear()
	_state.clear()
	if not Contract.exact_fields(definition, DEFINITION_FIELDS) or not Contract.exact_fields(identity, IDENTITY_FIELDS):
		return _failure("fields")
	if definition.id != "shattered_sentinel" or definition.runtime_kind != definition.id or definition.actor_kind not in ["enemy", "elite"]:
		return _failure("runtime_kind")
	if not Contract.number_in_range(definition.max_hp, 1.0, 1000000.0) or not Contract.number_in_range(definition.defense, 0.0, 10000.0) or not Contract.number_in_range(definition.move_speed, 0.0, 1000.0):
		return _failure("stats")
	if not Contract.integer_in_range(identity.seed, -2147483648, 2147483647):
		return _failure("seed")
	var action_identity := identity.duplicate(true)
	action_identity.erase("seed")
	var result: Dictionary = _action.configure({"id": definition.id, "actor_kind": definition.actor_kind, "actions": definition.actions}, action_identity)
	if not result.ok:
		return result
	var normalized_actions: Array = []
	var ids: Array[String] = []
	for candidate: Dictionary in definition.actions:
		var action: Dictionary = Contract.create(candidate, definition.actor_kind).definition
		if int(action.warning_frames) < 30 or action.handler_id != "melee":
			return _failure("unimplemented_handler_or_warning")
		ids.append(action.id)
		normalized_actions.append(action)
	var expected := ["shattered_sentinel.shield_sweep"]
	if definition.actor_kind == "elite":
		expected.append("shattered_sentinel.boulder_slam")
	if ids != expected:
		return _failure("actions")
	var controls: Dictionary = _control.configure({"run_id": identity.run_id, "hostile_source_id": identity.hostile_source_id, "runtime_frame": identity.runtime_frame})
	if not controls.ok:
		return controls
	_definition = definition.duplicate(true)
	_definition.actions = normalized_actions
	var rng := Seeds.make_rng(int(identity.seed), StringName("hostile_first_attack_v1:%s" % identity.hostile_source_id))
	_state = {
		"schema_version": 1, "definition_digest": JSON.stringify(_definition).sha256_text(),
		"identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false,
		"mechanism_state": {"first_attack_ready_frame": int(identity.runtime_frame) + rng.randi_range(0, 60), "retreat_remaining_frames": 0, "retreat_direction": {"x": 0.0, "y": 0.0}},
	}
	return {"ok": true, "snapshot": snapshot()}


func request_action(action_id: String, context: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or bool(_control.modifiers().action_paused) or int(_state.mechanism_state.retreat_remaining_frames) > 0:
		return _failure("action_unavailable")
	return _action.request_action(action_id, context)


func motion_for_frame(frame: int, observations: Dictionary) -> Dictionary:
	if not _valid_observations(frame, observations):
		return _failure("observations")
	var controls := _controls_for_frame(frame)
	if controls.is_empty():
		return _failure("control")
	var displacement := Vector2.ZERO
	if not controls.action_paused:
		if int(_state.mechanism_state.retreat_remaining_frames) > 0:
			displacement = _vector(_state.mechanism_state.retreat_direction) * (19.0 / 48.0) * float(controls.movement_multiplier)
		elif _action.snapshot().phase == "IDLE":
			var source := _vector(observations.source_position)
			var target := _vector(observations.target_position)
			var distance := source.distance_to(target)
			var step := minf(maxf(0.0, distance - 24.0), float(_definition.move_speed) * float(controls.movement_multiplier) / 60.0)
			displacement = source.direction_to(target) * step
	return {"ok": true, "displacement": {"x": displacement.x, "y": displacement.y}, "action_paused": controls.action_paused}


func advance_frame(frame: int, observations: Dictionary, select_action: bool = true, external_action_paused: bool = false) -> Dictionary:
	if not _valid_observations(frame, observations):
		return _failure("observations")
	var before := snapshot()
	var controls: Dictionary = _control.advance_frame(frame)
	if not controls.ok:
		return controls
	controls.action_paused = controls.action_paused or external_action_paused
	var previous_action: Dictionary = _action.snapshot()
	var result: Dictionary = _action.advance_frame(frame, observations, controls.action_paused)
	if not result.ok:
		_control.restore_snapshot(before.control)
		return result
	_state.runtime_frame = frame
	if not controls.action_paused and int(_state.mechanism_state.retreat_remaining_frames) > 0:
		_state.mechanism_state.retreat_remaining_frames -= 1
	if previous_action.phase == "ACTIVE" and result.phase == "RECOVERY" and previous_action.action_id == "shattered_sentinel.shield_sweep":
		_state.mechanism_state.retreat_remaining_frames = 48
		var direction := -_vector(previous_action.committed_aim)
		_state.mechanism_state.retreat_direction = {"x": direction.x, "y": direction.y}
	result["threat_facts"] = []
	if select_action and not controls.action_paused and int(_state.mechanism_state.retreat_remaining_frames) == 0 and frame >= int(_state.mechanism_state.first_attack_ready_frame) and result.phase == "IDLE":
		var selected := _select_action(frame)
		if not selected.is_empty():
			var requested: Dictionary = _action.request_action(selected, observations)
			if requested.ok:
				result.threat_facts = requested.threat_facts
				result.phase = requested.phase
	result["action_paused"] = controls.action_paused
	result["movement_multiplier"] = controls.movement_multiplier
	return result


func add_control_source(source_id: String, kind: String, duration_frames: int, magnitude: float) -> bool:
	return not _state.is_empty() and not _state.terminal and _control.add_source(source_id, kind, duration_frames, magnitude)


func clear_control_source(source_id: String) -> bool:
	return _control.clear_source(source_id)


func control_modifiers() -> Dictionary:
	return _control.modifiers()


func snapshot() -> Dictionary:
	if _state.is_empty():
		return {}
	var value := _state.duplicate(true)
	value["action"] = _action.snapshot()
	value["control"] = _control.snapshot()
	return value


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, STATE_FIELDS) or value.schema_version != 1 or typeof(value.schema_version) != TYPE_INT or value.definition_digest != _state.definition_digest or value.identity != _state.identity:
		return false
	if typeof(value.runtime_frame) != TYPE_INT or value.runtime_frame < int(_state.identity.runtime_frame) or typeof(value.terminal) != TYPE_BOOL:
		return false
	if not value.mechanism_state is Dictionary or not Contract.exact_fields(value.mechanism_state, MECHANISM_FIELDS):
		return false
	var mechanism: Dictionary = value.mechanism_state
	if mechanism.first_attack_ready_frame != _state.mechanism_state.first_attack_ready_frame or not Contract.integer_in_range(mechanism.retreat_remaining_frames, 0, 48) or typeof(mechanism.retreat_remaining_frames) != TYPE_INT or not Contract.valid_point(mechanism.retreat_direction, 1.0):
		return false
	if mechanism.retreat_remaining_frames > 0 and not is_equal_approx(_vector(mechanism.retreat_direction).length(), 1.0):
		return false
	if not value.action is Dictionary or not value.control is Dictionary or not _action.can_restore_snapshot(value.action) or not _control.can_restore_snapshot(value.control):
		return false
	if value.action.last_runtime_frame != value.runtime_frame or value.control.runtime_frame != value.runtime_frame or value.control.terminal != value.terminal:
		return false
	return not value.terminal or (value.action.phase == "IDLE" and mechanism.retreat_remaining_frames == 0)


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_action.restore_snapshot(value.action)
	_control.restore_snapshot(value.control)
	_state = value.duplicate(true)
	_state.erase("action")
	_state.erase("control")
	return true


func cancel(reason: StringName = &"cancelled") -> Dictionary:
	if _state.is_empty() or _state.terminal or reason == &"":
		return _failure("terminal")
	var result: Dictionary = _action.cancel(reason)
	_control.cancel(reason)
	_state.terminal = true
	_state.mechanism_state.retreat_remaining_frames = 0
	return result


func cancel_action(reason: StringName = &"interrupted") -> Dictionary:
	if _state.is_empty() or _state.terminal or reason == &"":
		return _failure("action_unavailable")
	_state.mechanism_state.retreat_remaining_frames = 0
	return _action.cancel(reason)


func _select_action(frame: int) -> String:
	var current: Dictionary = _action.snapshot()
	if frame <= int(current.idle_through_frame):
		return ""
	for candidate: Dictionary in _definition.actions:
		if int(current.cooldowns.get(candidate.id, 0)) <= frame:
			return candidate.id
	return ""


func _controls_for_frame(frame: int) -> Dictionary:
	var preview: RefCounted = Controls.new()
	preview.configure(_control.snapshot().identity)
	if not preview.restore_snapshot(_control.snapshot()):
		return {}
	var result: Dictionary = preview.advance_frame(frame)
	return result if result.ok else {}


func _valid_observations(frame: int, observations: Dictionary) -> bool:
	return not _state.is_empty() and not _state.terminal and frame == int(_state.runtime_frame) + 1 and Contract.exact_fields(observations, Action.CONTEXT_FIELDS) and observations.runtime_frame == frame and Contract.valid_point(observations.source_position) and Contract.valid_point(observations.target_position) and Contract.valid_point(observations.facing_direction, 1.0) and typeof(observations.target_id) == TYPE_STRING and not observations.target_id.is_empty()


static func _vector(point: Dictionary) -> Vector2:
	return Vector2(float(point.x), float(point.y))


static func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"LAUNCH_ENEMY_INVALID", "context": {"field": field}}
