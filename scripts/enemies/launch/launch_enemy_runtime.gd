class_name LaunchEnemyRuntime
extends RefCounted

const Action := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Controls := preload("res://scripts/enemies/launch/hostile_control_runtime.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Seeds := preload("res://scripts/core/seed_service.gd")
const Mechanisms := preload("res://scripts/enemies/launch/enemy_mechanism_handlers.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const DefinitionContract := preload("res://scripts/enemies/launch/hostile_definition_contract.gd")
const DEFINITION_FIELDS: Array[String] = ["id", "actor_kind", "runtime_kind", "max_hp", "defense", "move_speed", "collision_radius_px", "actions", "mechanisms"]
const IDENTITY_FIELDS: Array[String] = ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]
const STATE_FIELDS: Array[String] = ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "mechanism_state", "action", "control"]
const DAMAGE_FACT_FIELDS: Array[String] = ["fact_id", "runtime_frame", "target_source_id", "amount", "hp_after"]

var _definition: Dictionary = {}
var _state: Dictionary = {}
var _action: RefCounted = Action.new()
var _control: RefCounted = Controls.new()


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	_definition.clear()
	_state.clear()
	if not Contract.exact_fields(definition, DEFINITION_FIELDS) or not Contract.exact_fields(identity, IDENTITY_FIELDS):
		return _failure("fields")
	if not Mechanisms.ACTION_IDS.has(definition.id) or definition.runtime_kind != definition.id or definition.actor_kind not in ["enemy", "elite"]:
		return _failure("runtime_kind")
	if not Contract.number_in_range(definition.max_hp, 1.0, 1000000.0) or not Contract.number_in_range(definition.defense, 0.0, 10000.0) or not Contract.number_in_range(definition.move_speed, 0.0, 1000.0) or not Contract.number_in_range(definition.collision_radius_px, 1.0, 32.0):
		return _failure("stats")
	if not Contract.integer_in_range(identity.seed, -2147483648, 2147483647):
		return _failure("seed")
	var authored_mechanisms := DefinitionContract.mechanisms(definition.mechanisms, Enemy.MECHANISM_RULES[definition.id])
	if not authored_mechanisms.ok:
		return authored_mechanisms
	if authored_mechanisms.value.has("kite_min_px") and authored_mechanisms.value.kite_min_px > authored_mechanisms.value.kite_max_px:
		return _failure("kite_bounds")
	var action_identity := identity.duplicate(true)
	action_identity.erase("seed")
	var result: Dictionary = _action.configure({"id": definition.id, "actor_kind": definition.actor_kind, "actions": definition.actions}, action_identity)
	if not result.ok:
		return result
	var normalized_actions: Array = []
	var ids: Array[String] = []
	for candidate: Dictionary in definition.actions:
		var action: Dictionary = Contract.create(candidate, definition.actor_kind).definition
		if int(action.warning_frames) < 30 or action.handler_id not in ["melee", "charge", "projectile_volley", "zone", "heal", "summon"]:
			return _failure("unimplemented_handler_or_warning")
		if action.handler_id == "charge" and (action.hit_schedule.size() != 1 or action.geometry.size() != 1):
			return _failure("unimplemented_charge_schedule")
		ids.append(action.id)
		normalized_actions.append(action)
	var expected := Mechanisms.action_ids(definition.runtime_kind, definition.actor_kind == "elite")
	if ids != expected:
		return _failure("actions")
	var controls: Dictionary = _control.configure({"run_id": identity.run_id, "hostile_source_id": identity.hostile_source_id, "runtime_frame": identity.runtime_frame})
	if not controls.ok:
		return controls
	_definition = definition.duplicate(true)
	_definition.actions = normalized_actions
	_definition.mechanisms = authored_mechanisms.value
	for stat: String in ["max_hp", "defense", "move_speed", "collision_radius_px"]:
		_definition[stat] = float(_definition[stat])
	var stagger_bound := int(_definition.mechanisms.get("first_attack_stagger_frames", 60))
	var rng := Seeds.make_rng(int(identity.seed), StringName("hostile_first_attack_v1:%s" % identity.hostile_source_id))
	_state = {
		"schema_version": 1, "definition_digest": JSON.stringify(_definition, "", true, true).sha256_text(),
		"identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false,
		"mechanism_state": Mechanisms.make_state(definition.runtime_kind, int(identity.runtime_frame) + rng.randi_range(0, stagger_bound)),
	}
	return {"ok": true, "snapshot": snapshot()}


func request_action(action_id: String, context: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or bool(_control.modifiers().action_paused) or not Mechanisms.action_available(_definition.runtime_kind, _state.mechanism_state, action_id):
		return _failure("action_unavailable")
	var result: Dictionary = _action.request_action(action_id, context)
	if result.ok:
		_state.mechanism_state = Mechanisms.action_started(_definition.runtime_kind, _state.mechanism_state, action_id)
	return result


func motion_for_frame(frame: int, observations: Dictionary) -> Dictionary:
	if not _valid_observations(frame, observations):
		return _failure("observations")
	var controls := _controls_for_frame(frame)
	if controls.is_empty():
		return _failure("control")
	var displacement := Vector2.ZERO
	var action_state: Dictionary = _action.snapshot()
	var active_action := _action_definition(action_state.action_id)
	var staggered: bool = _definition.runtime_kind == "ruins_wraith" and int(_state.mechanism_state.stagger_remaining_frames) > 0
	if not controls.action_paused and not staggered:
		if _definition.runtime_kind == "shattered_sentinel" and int(_state.mechanism_state.retreat_remaining_frames) > 0:
			displacement = _vector(_state.mechanism_state.retreat_direction) * (float(_definition.mechanisms.retreat_distance_px) / float(_definition.mechanisms.retreat_frames)) * float(controls.movement_multiplier)
		elif not active_action.is_empty() and active_action.handler_id == "charge" and Action.action_phase(frame - int(action_state.commit_frame) - int(action_state.paused_frames), active_action) == "ACTIVE":
			var direction := _vector(action_state.committed_aim)
			var travelled := (_vector(observations.source_position) - _vector(action_state.committed_origin)).dot(direction)
			var remaining := maxf(0.0, float(active_action.parameters.travel_px) - travelled)
			displacement = direction * minf(remaining, float(active_action.parameters.speed_px_per_second) * float(controls.movement_multiplier) / 60.0)
		elif action_state.phase == "IDLE":
			var source := _vector(observations.source_position)
			var target := _vector(observations.target_position)
			var distance := source.distance_to(target)
			var speed := float(_definition.move_speed) * float(controls.movement_multiplier) / 60.0
			if _definition.runtime_kind == "corrosive_moth":
				if distance < float(_definition.mechanisms.kite_min_px):
					var direction := source.direction_to(target) if not is_zero_approx(distance) else _vector(observations.facing_direction).normalized()
					displacement = -direction * minf(float(_definition.mechanisms.kite_min_px) - distance, speed)
				elif distance > float(_definition.mechanisms.kite_max_px):
					displacement = source.direction_to(target) * minf(distance - float(_definition.mechanisms.kite_max_px), speed)
			else:
				displacement = source.direction_to(target) * minf(maxf(0.0, distance - 24.0), speed)
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
	var mechanism: Dictionary = Mechanisms.advance(_definition.runtime_kind, _definition.mechanisms, _state.mechanism_state, previous_action, _action.snapshot())
	if controls.action_paused and _definition.runtime_kind == "shattered_sentinel":
		mechanism.state = _state.mechanism_state.duplicate(true)
	_state.mechanism_state = mechanism.state
	result["mechanism_requests"] = mechanism.requests
	result["threat_facts"] = []
	if _definition.runtime_kind == "ruins_wraith" and not mechanism.requests.is_empty():
		var generation: int = previous_action.geometry_generations[0]
		var cancelled := cancel(&"detonation_consumed")
		result.retired_generations.append_array(cancelled.retired_generations)
		result.phase = "IDLE"
		result.mechanism_requests = [{"kind": "consume_actor", "run_id": _state.identity.run_id, "hostile_source_id": _state.identity.hostile_source_id, "runtime_frame": frame, "action_id": previous_action.action_id, "attack_generation": generation, "hit_index": 63}]
	if select_action and not _state.terminal and not controls.action_paused and frame >= int(_state.mechanism_state.first_attack_ready_frame) and result.phase == "IDLE":
		var selected := _select_action(frame, observations)
		if not selected.is_empty():
			var requested: Dictionary = _action.request_action(selected, observations)
			if requested.ok:
				result.threat_facts = requested.threat_facts
				result.phase = requested.phase
				_state.mechanism_state = Mechanisms.action_started(_definition.runtime_kind, _state.mechanism_state, selected)
	result["action_paused"] = controls.action_paused
	result["movement_multiplier"] = controls.movement_multiplier
	return result


func charge_contact_fact(frame: int, target_id: String) -> Dictionary:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame):
		return {}
	var action_state: Dictionary = _action.snapshot()
	var active_action := _action_definition(action_state.action_id)
	if action_state.phase != "ACTIVE" or active_action.is_empty() or active_action.handler_id != "charge" or target_id != action_state.target_id:
		return {}
	return Action._hit_fact(active_action.hit_schedule[0], active_action, action_state)


func reserve_terminal_death_pool(position: Dictionary, bounds: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or _definition.runtime_kind != "corrosive_moth" or _state.mechanism_state.death_pool_reserved or not Contract.valid_point(position):
		return {}
	var generation: int = _action.reserve_terminal_generation()
	if generation < 1:
		return {}
	_state.mechanism_state.death_pool_reserved = true
	var request := {"kind": "death_pool", "run_id": _state.identity.run_id, "hostile_source_id": _state.identity.hostile_source_id, "runtime_frame": _state.runtime_frame, "attack_generation": generation, "position": position.duplicate(true), "bounds": bounds.duplicate(true), "parameters": {"warning_frames": int(_definition.mechanisms.death_pool_warning_frames), "radius": float(_definition.mechanisms.death_pool_radius_px), "damage": float(_definition.mechanisms.death_pool_damage)}}
	cancel(&"death")
	return request


func add_control_source(source_id: String, kind: String, duration_frames: int, magnitude: float) -> bool:
	return not _state.is_empty() and not _state.terminal and _control.add_source(source_id, kind, duration_frames, magnitude)


func clear_control_source(source_id: String) -> bool:
	return _control.clear_source(source_id)


func control_modifiers() -> Dictionary:
	return _control.modifiers()


func accept_damage_fact(value: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.exact_fields(value, DAMAGE_FACT_FIELDS):
		return _failure("damage_fact")
	if typeof(value.fact_id) != TYPE_STRING or value.fact_id.is_empty() or value.fact_id.length() > 128 or value.target_source_id != _state.identity.hostile_source_id or typeof(value.runtime_frame) != TYPE_INT or value.runtime_frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or not Contract.number_in_range(value.amount, 0.000001, 1000000.0) or not Contract.number_in_range(value.hp_after, 0.0, _definition.max_hp):
		return _failure("damage_fact_identity_or_value")
	var prepared: Dictionary = Mechanisms.accept_damage(_definition.runtime_kind, _definition.mechanisms, _state.mechanism_state, _action.snapshot(), value)
	if not prepared.ok:
		return _failure("duplicate_damage_fact")
	_state.mechanism_state = prepared.state
	var retired: Array = []
	if prepared.cancel_action:
		retired = _action.cancel(&"health_damage_interrupt").retired_generations
	return {"ok": true, "retired_generations": retired}


func species_damage_taken_multiplier() -> float:
	return Mechanisms.damage_taken_multiplier(_definition.runtime_kind, _definition.mechanisms, _state.mechanism_state) if not _state.is_empty() else 1.0


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
	if not value.mechanism_state is Dictionary:
		return false
	var mechanism: Dictionary = value.mechanism_state
	if not Mechanisms.valid_state(_definition.runtime_kind, _definition.mechanisms, mechanism, _state.mechanism_state.first_attack_ready_frame):
		return false
	if _definition.runtime_kind == "ruins_wraith" and mechanism.detonation_consumed and not value.terminal:
		return false
	if _definition.runtime_kind == "corrosive_moth" and mechanism.death_pool_reserved and not value.terminal:
		return false
	if not value.action is Dictionary or not value.control is Dictionary or not _action.can_restore_snapshot(value.action) or not _control.can_restore_snapshot(value.control):
		return false
	if value.action.last_runtime_frame != value.runtime_frame or value.control.runtime_frame != value.runtime_frame or value.control.terminal != value.terminal:
		return false
	if _definition.runtime_kind == "stone_shell_strider" and value.action.action_id == "stone_shell_strider.shell_shock" and int(mechanism.shell_shock_cycle) == 0:
		return false
	return not value.terminal or (value.action.phase == "IDLE" and int(mechanism.get("retreat_remaining_frames", 0)) == 0)


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
	if _state.mechanism_state.has("retreat_remaining_frames"):
		_state.mechanism_state.retreat_remaining_frames = 0
	return result


func cancel_action(reason: StringName = &"interrupted") -> Dictionary:
	if _state.is_empty() or _state.terminal or reason == &"":
		return _failure("action_unavailable")
	if _state.mechanism_state.has("retreat_remaining_frames"):
		_state.mechanism_state.retreat_remaining_frames = 0
	return _action.cancel(reason)


func _select_action(frame: int, observations: Dictionary) -> String:
	var current: Dictionary = _action.snapshot()
	if frame <= int(current.idle_through_frame):
		return ""
	var candidates: Array = _definition.actions.duplicate()
	if _definition.runtime_kind == "stone_shell_strider" and _definition.actor_kind == "elite":
		var shock := _action_definition("stone_shell_strider.shell_shock")
		candidates.erase(shock)
		candidates.push_front(shock)
	for candidate: Dictionary in candidates:
		var distance := _vector(observations.source_position).distance_to(_vector(observations.target_position))
		if int(current.cooldowns.get(candidate.id, 0)) <= frame and distance >= float(candidate.distance_min_px) and distance <= float(candidate.distance_max_px) and Mechanisms.action_available(_definition.runtime_kind, _state.mechanism_state, candidate.id):
			return candidate.id
	return ""


func _action_definition(action_id: String) -> Dictionary:
	for candidate: Dictionary in _definition.actions:
		if candidate.id == action_id:
			return candidate
	return {}


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
