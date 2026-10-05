class_name LaunchSummonRuntime
extends "res://scripts/enemies/launch/launch_enemy_runtime.gd"

const SummonProjection := preload("res://scripts/enemies/launch/launch_summon_projection.gd")
const FIELDS := ["id", "actor_kind", "runtime_kind", "max_hp", "defense", "move_speed", "collision_radius_px", "actions", "mechanisms", "summon_contract"]
const MECHANISM_FIELDS := ["first_attack_ready_frame", "last_action_id", "consecutive_actions", "hp_after", "damage_claims"]


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	_definition.clear()
	_state.clear()
	if not Contract.exact_fields(definition, FIELDS) or not Contract.exact_fields(identity, IDENTITY_FIELDS) or not definition.summon_contract is Dictionary or not Contract.exact_fields(definition.summon_contract, ["definition", "parent"]) or not definition.summon_contract.definition is Dictionary or not definition.summon_contract.parent is Dictionary or not Contract.integer_in_range(identity.seed, -2147483648, 2147483647):
		return _failure("summon_fields")
	var projection := SummonProjection.create(definition.summon_contract.definition, definition.summon_contract.parent)
	if not projection.ok or JSON.stringify(projection.definition, "", true, true) != JSON.stringify(definition, "", true, true):
		return _failure("summon_projection")
	var action_identity := identity.duplicate(true)
	action_identity.erase("seed")
	if not _action.configure({"id": definition.id, "actor_kind": "summon", "actions": definition.actions}, action_identity).ok or not _control.configure({"run_id": identity.run_id, "hostile_source_id": identity.hostile_source_id, "runtime_frame": identity.runtime_frame}).ok:
		return _failure("summon_identity")
	_definition = definition.duplicate(true)
	_state = {"schema_version": 1, "definition_digest": JSON.stringify(_definition, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false, "mechanism_state": {"first_attack_ready_frame": int(identity.runtime_frame), "last_action_id": "", "consecutive_actions": 0, "hp_after": float(definition.max_hp), "damage_claims": []}}
	return {"ok": true, "snapshot": snapshot()}


func request_action(action_id: String, context: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or _definition.mechanisms.harmless or _control.modifiers().action_paused:
		return _failure("summon_unavailable")
	var result: Dictionary = _action.request_action(action_id, context)
	if result.ok:
		_state.mechanism_state.consecutive_actions = int(_state.mechanism_state.consecutive_actions) + 1
		_state.mechanism_state.last_action_id = action_id
	return result


func advance_frame(frame: int, observations: Dictionary, select_action: bool = true, external_action_paused: bool = false) -> Dictionary:
	if not _valid_observations(frame, observations):
		return _failure("observations")
	var controls: Dictionary = _control.advance_frame(frame)
	if not controls.ok:
		return controls
	var paused: bool = bool(controls.action_paused) or external_action_paused
	var result: Dictionary = _action.advance_frame(frame, observations, paused)
	if not result.ok:
		return result
	_state.runtime_frame = frame
	result["mechanism_requests"] = []
	result["threat_facts"] = []
	if select_action and not paused and not _definition.mechanisms.harmless and result.phase == "IDLE":
		var selected := _select_action(frame, observations)
		if not selected.is_empty():
			var requested := request_action(selected, observations)
			if requested.ok:
				result.threat_facts = requested.threat_facts
				result.phase = requested.phase
	result["action_paused"] = paused
	result["movement_multiplier"] = float(controls.movement_multiplier)
	for hit: Dictionary in result.hit_facts:
		hit.damage *= float(controls.get("attack_multiplier", 1.0))
	return result


func motion_for_frame(frame: int, observations: Dictionary) -> Dictionary:
	if not _valid_observations(frame, observations):
		return _failure("observations")
	var controls := _controls_for_frame(frame)
	if controls.is_empty():
		return _failure("controls")
	var displacement := Vector2.ZERO
	var state: Dictionary = _action.snapshot()
	var action := _action_definition(str(state.action_id))
	var position := _vector(observations.source_position)
	if not controls.action_paused:
		if not action.is_empty() and action.handler_id == "charge" and Action.action_phase(frame - int(state.commit_frame) - int(state.paused_frames), action) == "ACTIVE":
			var direction := _vector(state.committed_aim)
			var remaining := maxf(0.0, float(action.parameters.travel_px) - (position - _vector(state.committed_origin)).dot(direction))
			displacement = direction * minf(remaining, float(action.parameters.speed_px_per_second) * float(controls.movement_multiplier) / 60.0)
		elif not action.is_empty() and action.handler_id == "blink":
			var elapsed := frame - int(state.commit_frame) - int(state.paused_frames)
			if elapsed > 0 and elapsed <= int(action.parameters.transit_frames):
				displacement = position.direction_to(_vector(state.committed_target)) * minf(position.distance_to(_vector(state.committed_target)), float(action.parameters.travel_px) / float(action.parameters.transit_frames))
		elif state.phase == "IDLE":
			var target := _vector(observations.target_position)
			var range_px := float(_definition.actions[0].distance_max_px)
			displacement = position.direction_to(target) * minf(maxf(0.0, position.distance_to(target) - minf(range_px, 24.0)), float(_definition.move_speed) * float(controls.movement_multiplier) / 60.0)
	return {"ok": true, "displacement": {"x": displacement.x, "y": displacement.y}, "action_paused": bool(controls.action_paused)}


func accept_damage_fact(value: Dictionary) -> Dictionary:
	return _accept_health(value, false)


func accept_health_fact(value: Dictionary) -> Dictionary:
	return _accept_health(value, true)


func _accept_health(value: Dictionary, healing: bool) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.exact_fields(value, DAMAGE_FACT_FIELDS) or not value.fact_id is String or value.fact_id.is_empty() or value.fact_id.length() > 128 or value.target_source_id != _state.identity.hostile_source_id or not Contract.integer_in_range(value.runtime_frame, int(_state.runtime_frame), int(_state.runtime_frame) + 1) or not Contract.number_in_range(value.amount, 0.000001, 1000000.0) or not Contract.number_in_range(value.hp_after, 0.0, _definition.max_hp):
		return _failure("health_fact")
	if healing and float(value.hp_after) < float(_state.mechanism_state.hp_after):
		return _failure("healing_direction")
	var claim := str(value.fact_id).sha256_text()
	if _state.mechanism_state.damage_claims.has(claim) or _state.mechanism_state.damage_claims.size() >= 4096:
		return _failure("health_claim")
	_state.mechanism_state.damage_claims.append(claim)
	_state.mechanism_state.hp_after = float(value.hp_after)
	return {"ok": true, "retired_generations": []}


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, STATE_FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or value.definition_digest != _state.definition_digest or value.identity != _state.identity or not Contract.integer_in_range(value.runtime_frame, int(_state.identity.runtime_frame), 2147400000) or typeof(value.terminal) != TYPE_BOOL or not value.mechanism_state is Dictionary or not Contract.exact_fields(value.mechanism_state, MECHANISM_FIELDS):
		return false
	var mechanism: Dictionary = value.mechanism_state
	if mechanism.first_attack_ready_frame != _state.identity.runtime_frame or not mechanism.last_action_id is String or mechanism.last_action_id not in ["", str(_definition.actions[0].id)] or not Contract.integer_in_range(mechanism.consecutive_actions, 0, 2147400000) or not Contract.number_in_range(mechanism.hp_after, 0.0, _definition.max_hp) or not mechanism.damage_claims is Array or mechanism.damage_claims.size() > 4096:
		return false
	var claims := {}
	for claim: Variant in mechanism.damage_claims:
		if not claim is String or claim.length() != 64 or not claim.is_valid_hex_number(false) or claims.has(claim):
			return false
		claims[claim] = true
	return value.action is Dictionary and value.control is Dictionary and _action.can_restore_snapshot(value.action) and _control.can_restore_snapshot(value.control) and value.action.last_runtime_frame == value.runtime_frame and value.control.runtime_frame == value.runtime_frame and value.control.terminal == value.terminal and (not value.terminal or value.action.phase == "IDLE")


func _species_action_available(_action_id: String) -> bool:
	return not _state.terminal and not _definition.mechanisms.harmless


func species_damage_taken_multiplier() -> float:
	return 1.0


func species_attack_multiplier() -> float:
	return 1.0


func species_speed_multiplier() -> float:
	return 1.0
