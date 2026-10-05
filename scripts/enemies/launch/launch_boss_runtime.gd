class_name LaunchBossRuntime
extends RefCounted

const Action := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Controls := preload("res://scripts/enemies/launch/hostile_control_runtime.gd")
const Conversion := preload("res://scripts/enemies/launch/boss_conversion_runtime.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Seeds := preload("res://scripts/core/seed_service.gd")
const Arena := preload("res://scripts/enemies/launch/boss_arena_runtime.gd")
const IDENTITY_FIELDS: Array[String] = ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]
const STATE_FIELDS: Array[String] = ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "mechanism_state", "action", "control", "conversion"]
const MECHANISM_FIELDS: Array[String] = ["phase_index", "hp_current", "minimum_hp", "phase_transition_until_frame", "enraged", "action_phase_index", "action_enraged", "delay_remaining_frames", "exposure_through_frame", "last_action_id", "consecutive_actions", "damage_claims", "health_claims", "stop_claims", "history", "rewind", "rewind_healing_spent", "weakpoint_claims"]
const DAMAGE_FACT_FIELDS: Array[String] = ["fact_id", "runtime_frame", "target_source_id", "amount", "hp_after"]
const HISTORY_FIELDS: Array[String] = ["runtime_frame", "position", "hp"]
const REWIND_FIELDS: Array[String] = ["attack_generation", "commit_frame", "history_reference", "landing", "hp_at_commit", "heal_amount", "healing_spent_before", "weakpoint_damage", "consumed", "cancelled"]
const MAX_CLAIMS := 512

var _definition: Dictionary = {}
var _state: Dictionary = {}
var _action: RefCounted
var _control: RefCounted = Controls.new()
var _conversion: RefCounted = Conversion.new()
var _arena: RefCounted


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	_definition.clear()
	_state.clear()
	_action = null
	_arena = null
	if not Contract.exact_fields(identity, IDENTITY_FIELDS) or not Contract.integer_in_range(identity.seed, -2147483648, 2147483647):
		return _failure("identity")
	var parsed := Definition.new().configure_runtime_projection(definition)
	if not parsed.ok:
		return parsed
	_definition = parsed.definition.duplicate(true)
	if _definition.id == "ruin_king":
		_arena = Arena.new()
		if not _arena.configure(_definition, identity).ok:
			return _failure("arena_configuration")
	var action_identity := identity.duplicate(true)
	action_identity.erase("seed")
	var initial_action := Action.new()
	var action_result := initial_action.configure({"id": _definition.id, "actor_kind": "boss", "actions": _definition.actions + _definition.time_responses}, action_identity)
	if not action_result.ok:
		_definition.clear()
		return action_result
	var controls: Dictionary = _control.configure({"run_id": identity.run_id, "hostile_source_id": identity.hostile_source_id, "runtime_frame": identity.runtime_frame})
	if not controls.ok:
		_definition.clear()
		return controls
	if not _conversion.configure({"run_id": identity.run_id, "hostile_source_id": identity.hostile_source_id, "runtime_frame": identity.runtime_frame}):
		_definition.clear()
		return _failure("conversion_identity")
	_state = {"schema_version": 1, "definition_digest": JSON.stringify(_definition, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false, "mechanism_state": {"phase_index": 0, "hp_current": float(_definition.max_hp), "minimum_hp": float(_definition.max_hp), "phase_transition_until_frame": int(identity.runtime_frame) - 1, "enraged": false, "action_phase_index": 0, "action_enraged": false, "delay_remaining_frames": 0, "exposure_through_frame": int(identity.runtime_frame) - 1, "last_action_id": "", "consecutive_actions": 0, "damage_claims": [], "health_claims": [], "stop_claims": [], "history": [], "rewind": {}, "rewind_healing_spent": 0.0, "weakpoint_claims": []}}
	_action = initial_action
	if _arena != null:
		_state.schema_version = 2
	return {"ok": true, "snapshot": snapshot()}


func request_action(action_id: String, context: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not _action_available(action_id) or int(_state.runtime_frame) <= int(_state.mechanism_state.phase_transition_until_frame):
		return _failure("action_unavailable")
	if not _sync_action_regime():
		return _failure("action_regime")
	var result: Dictionary = _action.request_action(action_id, context)
	if result.ok:
		var mechanism: Dictionary = _state.mechanism_state
		mechanism.consecutive_actions = int(mechanism.consecutive_actions) + 1 if mechanism.last_action_id == action_id else 1
		mechanism.last_action_id = action_id
		if action_id == "traitor_self_rewind":
			var reference: Dictionary = mechanism.history[0].duplicate(true) if not mechanism.history.is_empty() else {"runtime_frame": int(_state.runtime_frame), "position": context.source_position.duplicate(true), "hp": float(mechanism.hp_current)}
			var healing := minf(maxf(0.0, float(reference.hp) - float(mechanism.hp_current)), minf(float(_definition.mechanisms.rewind_heal_per_cast_cap), float(_definition.mechanisms.rewind_heal_encounter_cap) - float(mechanism.rewind_healing_spent)))
			var action: Dictionary = _action.snapshot()
			mechanism.rewind = {"attack_generation": int(action.geometry_generations[0]), "commit_frame": int(_state.runtime_frame), "history_reference": reference, "landing": reference.position.duplicate(true), "hp_at_commit": float(mechanism.hp_current), "heal_amount": healing, "healing_spent_before": float(mechanism.rewind_healing_spent), "weakpoint_damage": 0.0, "consumed": false, "cancelled": false}
			result.threat_facts = [{"hostile_source_id": _state.identity.hostile_source_id, "attack_generation": int(action.geometry_generations[0]), "shape": "circle", "origin": reference.position.duplicate(true), "aim_direction": {"x": 1.0, "y": 0.0}, "target_point": reference.position.duplicate(true), "summon_slots": [], "radius": 16.0, "length": 0.0, "active_from_frame": int(_state.runtime_frame), "active_through_frame": int(action.idle_through_frame) - int(_action_definition(action_id).idle_frames)}]
	return result


func motion_for_frame(frame: int, observations: Dictionary) -> Dictionary:
	if not _valid_observations(frame, observations):
		return _failure("observations")
	var control := _controls_for_frame(frame)
	if control.is_empty():
		return _failure("control")
	var paused := _delays_action(frame)
	var displacement := Vector2.ZERO
	var relocation := false
	var action: Dictionary = _action.snapshot()
	var definition := _action_definition(str(action.action_id))
	if not paused:
		if not definition.is_empty() and definition.handler_id == "self_rewind" and Action.action_phase(frame - int(action.commit_frame) - int(action.paused_frames), definition) == "ACTIVE" and not _state.mechanism_state.rewind.is_empty() and not _state.mechanism_state.rewind.consumed:
			displacement = _vector(_state.mechanism_state.rewind.landing) - _vector(observations.source_position)
			relocation = true
		elif not definition.is_empty() and definition.handler_id == "charge" and Action.action_phase(frame - int(action.commit_frame) - int(action.paused_frames), definition) == "ACTIVE":
			var direction := _vector(action.committed_aim)
			var travelled := (_vector(observations.source_position) - _vector(action.committed_origin)).dot(direction)
			displacement = direction * minf(maxf(0.0, float(definition.parameters.travel_px) - travelled), float(definition.parameters.speed_px_per_second) * float(control.movement_multiplier) / 60.0)
		elif action.phase == "IDLE":
			var source := _vector(observations.source_position)
			var target := _vector(observations.target_position)
			var speed := float(_definition.phases[int(_state.mechanism_state.phase_index)].move_speed) * float(control.movement_multiplier) / 60.0
			displacement = source.direction_to(target) * minf(maxf(0.0, source.distance_to(target) - 40.0), speed)
	return {"ok": true, "displacement": _point(displacement), "action_paused": paused, "relocation": relocation}


func advance_frame(frame: int, observations: Dictionary, select_action: bool = true, external_action_paused: bool = false) -> Dictionary:
	if not _valid_observations(frame, observations):
		return _failure("observations")
	var before := snapshot()
	var controls: Dictionary = _control.advance_frame(frame)
	if not controls.ok:
		return controls
	var delayed := _delays_action(frame)
	var result: Dictionary = _action.advance_frame(frame, observations, delayed or external_action_paused)
	if not result.ok:
		_control.restore_snapshot(before.control)
		return result
	_state.runtime_frame = frame
	if _arena != null and not _arena.advance_frame(frame):
		restore_snapshot(before)
		return _failure("arena_frame")
	if int(_state.mechanism_state.delay_remaining_frames) > 0 and _action.snapshot().phase in ["WARNING", "RECOVERY"] and not external_action_paused:
		_state.mechanism_state.delay_remaining_frames -= 1
	_state.mechanism_state.enraged = frame - int(_state.identity.runtime_frame) >= int(_definition.enrage.threshold_frames)
	if not _conversion.advance_frame(frame, _character_tail_must_wait()):
		restore_snapshot(before)
		return _failure("conversion_frame")
	result["mechanism_requests"] = []
	result["threat_facts"] = []
	for hit: Dictionary in result.hit_facts:
		hit.damage = float(hit.damage) * float(controls.get("attack_multiplier", 1.0))
		if _definition.id == "ruin_king" and hit.action_id == "guardian_enrage_collapse":
			for cover: Dictionary in _arena.snapshot().covers:
				if cover.broken:
					continue
				var fact_id := ("enrage_cover:%s:%d:%s" % [_state.identity.hostile_source_id, int(hit.attack_generation), cover.id]).sha256_text()
				if not _arena.accept_damage_fact({"fact_id": fact_id, "run_id": str(_state.identity.run_id), "owner_source_id": str(_state.identity.hostile_source_id), "construct_id": cover.id, "runtime_frame": frame, "amount": float(cover.current_hp)}).ok:
					restore_snapshot(before)
					return _failure("enrage_cover_retirement")
		if _definition.id == "ruin_king" and hit.action_id == "guardian_fist_slam":
			var parameters: Dictionary = _definition.mechanisms
			result.mechanism_requests.append({"kind": "boss_aftershock", "run_id": str(_state.identity.run_id), "hostile_source_id": str(_state.identity.hostile_source_id), "runtime_frame": frame, "attack_generation": int(hit.attack_generation), "position": hit.geometry[0].origin.duplicate(true), "parameters": {"delay_frames": int(parameters.aftershock_delay_frames) - int(parameters.aftershock_warning_frames), "warning_frames": int(parameters.aftershock_warning_frames), "radius": float(parameters.aftershock_radius_px), "damage": float(parameters.aftershock_damage) * (float(_definition.enrage.damage_multiplier) if _state.mechanism_state.action_enraged else 1.0) * float(controls.get("attack_multiplier", 1.0))}})
	if _definition.id == "time_sovereign":
		var mechanism: Dictionary = _state.mechanism_state
		mechanism.history.append({"runtime_frame": frame, "position": observations.source_position.duplicate(true), "hp": float(mechanism.hp_current)})
		while mechanism.history.size() > int(_definition.mechanisms.history_frames):
			mechanism.history.pop_front()
		if result.phase == "ACTIVE" and _action.snapshot().action_id == "traitor_self_rewind" and not mechanism.rewind.is_empty() and not mechanism.rewind.consumed:
			mechanism.rewind.consumed = true
			mechanism.rewind_healing_spent += float(mechanism.rewind.heal_amount)
			result.mechanism_requests.append({"kind": "boss_self_rewind", "run_id": _state.identity.run_id, "hostile_source_id": _state.identity.hostile_source_id, "runtime_frame": frame, "attack_generation": int(mechanism.rewind.attack_generation), "hit_index": 62, "position": observations.source_position.duplicate(true), "amount": float(mechanism.rewind.heal_amount)})
	if result.phase == "IDLE" and not _sync_action_regime():
		restore_snapshot(before)
		return _failure("action_regime")
	if select_action and not external_action_paused and not delayed and result.phase == "IDLE":
		var selected := _select_action(frame, observations)
		if not selected.is_empty():
			var requested := request_action(selected, observations)
			if requested.ok:
				result.threat_facts = requested.threat_facts
				result.phase = requested.phase
	result["action_paused"] = delayed or external_action_paused
	result["movement_multiplier"] = float(controls.movement_multiplier)
	return result


func charge_contact_fact(frame: int, target_id: String) -> Dictionary:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame):
		return {}
	var state: Dictionary = _action.snapshot()
	var action := _action_definition(str(state.action_id))
	if state.phase != "ACTIVE" or action.is_empty() or action.handler_id != "charge" or target_id != state.target_id:
		return {}
	return Action._hit_fact(action.hit_schedule[0], action, state)


func add_control_source(source_id: String, kind: String, duration_frames: int, magnitude: float) -> bool:
	if _state.is_empty() or _state.terminal:
		return false
	if kind == "rift" and not Contract.number_in_range(magnitude, 0.000001, 1.0):
		return false
	if kind == "stop":
		if magnitude != 1.0 or not Contract.integer_in_range(duration_frames, 1, Contract.MAX_FRAME) or _state.mechanism_state.stop_claims.has(source_id) or _state.mechanism_state.stop_claims.size() >= MAX_CLAIMS:
			return false
		if not _control.add_source(source_id, "weakpoint", 45, 0.35):
			return false
		_state.mechanism_state.stop_claims.append(source_id)
		_state.mechanism_state.exposure_through_frame = maxi(int(_state.mechanism_state.exposure_through_frame), int(_state.runtime_frame) + 45)
		if _action.snapshot().phase in ["WARNING", "RECOVERY"]:
			_state.mechanism_state.delay_remaining_frames = mini(Contract.MAX_FRAME, int(_state.mechanism_state.delay_remaining_frames) + clampi(roundi(duration_frames * 0.35), 30, 66))
		_conversion.synchronize_tail(_character_tail_must_wait())
		return true
	return _control.add_source(source_id, kind, duration_frames, maxf(0.70, magnitude) if kind == "rift" else magnitude)


func clear_control_source(source_id: String) -> bool:
	return _control.clear_source(source_id)


func control_modifiers() -> Dictionary:
	return _control.modifiers()


func accept_damage_fact(value: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.exact_fields(value, DAMAGE_FACT_FIELDS):
		return _failure("damage_fact")
	if typeof(value.fact_id) != TYPE_STRING or value.fact_id.is_empty() or value.fact_id.length() > 128 or value.target_source_id != _state.identity.hostile_source_id or typeof(value.runtime_frame) != TYPE_INT or value.runtime_frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or not Contract.number_in_range(value.amount, 0.000001, 1000000.0) or not Contract.number_in_range(value.hp_after, 0.0, _definition.max_hp):
		return _failure("damage_identity_or_value")
	var mechanism: Dictionary = _state.mechanism_state
	if mechanism.damage_claims.has(value.fact_id) or not is_equal_approx(maxf(0.0, float(mechanism.hp_current) - float(value.amount)), float(value.hp_after)):
		return _failure("duplicate_or_inconsistent_damage")
	var before := snapshot()
	if mechanism.damage_claims.size() >= MAX_CLAIMS:
		mechanism.damage_claims.pop_front()
	mechanism.damage_claims.append(value.fact_id)
	mechanism.hp_current = float(value.hp_after)
	_update_history_hp(int(value.runtime_frame), float(value.hp_after))
	mechanism.minimum_hp = minf(float(mechanism.minimum_hp), float(value.hp_after))
	var phase := _phase_for_hp(float(mechanism.minimum_hp))
	var retired: Array = []
	if phase > int(mechanism.phase_index):
		_cancel_pending_rewind()
		retired = _action.cancel(&"phase_transition").retired_generations
		mechanism.phase_index = phase
		mechanism.phase_transition_until_frame = int(value.runtime_frame) + 59
		mechanism.delay_remaining_frames = 0
		if not _sync_action_regime():
			restore_snapshot(before)
			return _failure("action_regime")
	_conversion.synchronize_tail(_character_tail_must_wait())
	return {"ok": true, "retired_generations": retired}


func accept_health_fact(value: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.exact_fields(value, DAMAGE_FACT_FIELDS):
		return _failure("health_fact")
	if typeof(value.fact_id) != TYPE_STRING or value.fact_id.is_empty() or value.fact_id.length() > 128 or value.target_source_id != _state.identity.hostile_source_id or typeof(value.runtime_frame) != TYPE_INT or value.runtime_frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or not Contract.number_in_range(value.amount, 0.000001, _definition.max_hp) or not Contract.number_in_range(value.hp_after, 0.000001, _definition.max_hp):
		return _failure("health_identity_or_value")
	var mechanism: Dictionary = _state.mechanism_state
	if float(mechanism.hp_current) <= 0.0 or mechanism.health_claims.has(value.fact_id) or not is_equal_approx(float(mechanism.hp_current) + float(value.amount), float(value.hp_after)):
		return _failure("duplicate_or_inconsistent_health")
	if mechanism.health_claims.size() >= MAX_CLAIMS:
		mechanism.health_claims.pop_front()
	mechanism.health_claims.append(value.fact_id)
	mechanism.hp_current = float(value.hp_after)
	_update_history_hp(int(value.runtime_frame), float(value.hp_after))
	return {"ok": true}


func accept_weakpoint_damage_fact(value: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or _definition.id != "time_sovereign" or not Contract.exact_fields(value, ["fact_id", "runtime_frame", "attack_generation", "amount"]):
		return _failure("weakpoint_fact")
	var mechanism: Dictionary = _state.mechanism_state
	if typeof(value.fact_id) != TYPE_STRING or value.fact_id.is_empty() or value.fact_id.length() > 128 or typeof(value.runtime_frame) != TYPE_INT or value.runtime_frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or not Contract.integer_in_range(value.attack_generation, 1, Controls.MAX_COUNTER) or not Contract.number_in_range(value.amount, 0.000001, 1000000.0) or mechanism.weakpoint_claims.has(value.fact_id) or mechanism.rewind.is_empty() or mechanism.rewind.consumed or value.attack_generation != mechanism.rewind.attack_generation or _action.snapshot().phase != "WARNING" or _action.snapshot().action_id != "traitor_self_rewind":
		return _failure("weakpoint_identity_or_cast")
	if mechanism.weakpoint_claims.size() >= MAX_CLAIMS:
		mechanism.weakpoint_claims.pop_front()
	mechanism.weakpoint_claims.append(value.fact_id)
	mechanism.rewind.weakpoint_damage = minf(float(_definition.mechanisms.rewind_interrupt_damage), float(mechanism.rewind.weakpoint_damage) + float(value.amount))
	if float(mechanism.rewind.weakpoint_damage) < float(_definition.mechanisms.rewind_interrupt_damage):
		return {"ok": true, "cancelled": false, "retired_generations": []}
	_cancel_pending_rewind()
	var result: Dictionary = _action.cancel(&"watch_rewind_interrupt")
	mechanism.phase_transition_until_frame = int(value.runtime_frame) + 54
	mechanism.delay_remaining_frames = 0
	_conversion.synchronize_tail(_character_tail_must_wait())
	return {"ok": true, "cancelled": true, "retired_generations": result.retired_generations}


func _update_history_hp(frame: int, hp: float) -> void:
	var history: Array = _state.mechanism_state.history
	if not history.is_empty() and int(history.back().runtime_frame) == frame:
		history.back().hp = hp


func _cancel_pending_rewind() -> void:
	var rewind: Dictionary = _state.mechanism_state.rewind
	if not rewind.is_empty() and not rewind.consumed:
		rewind.cancelled = true
		rewind.consumed = true


func species_damage_taken_multiplier() -> float:
	if _state.is_empty() or _definition.id != "void_throne":
		return 1.0
	return float(_definition.mechanisms.core_exposure_damage_multiplier) if is_exposed() else float(_definition.mechanisms.outer_body_damage_multiplier)


func is_exposed() -> bool:
	return not _state.is_empty() and not _state.terminal and (int(_state.runtime_frame) <= int(_state.mechanism_state.exposure_through_frame) or _conversion.is_character_exposed())


func apply_weapon_control_conversion(source_id: String, recovery_frames: int, exposure_frames: int, poise_damage: float) -> bool:
	if _state.is_empty() or _state.terminal:
		return false
	var phase: String = _action.snapshot().phase
	var converted: Dictionary = _conversion.convert_weapon(source_id, recovery_frames, exposure_frames, poise_damage, phase, is_exposed(), float(_definition.phases[int(_state.mechanism_state.phase_index)].poise_threshold), int(_definition.mechanisms.get("poise_recovery_extension_frames", 45)))
	if not converted.ok:
		return false
	_state.mechanism_state.delay_remaining_frames = mini(Contract.MAX_FRAME, int(_state.mechanism_state.delay_remaining_frames) + int(converted.recovery_frames))
	if int(converted.exposure_frames) > 0:
		_state.mechanism_state.exposure_through_frame = maxi(int(_state.mechanism_state.exposure_through_frame), int(_state.runtime_frame) + int(converted.exposure_frames))
	_conversion.synchronize_tail(_character_tail_must_wait())
	return true


func extend_character_boss_exposure(stop_generation: int, frames: int) -> bool:
	if _state.is_empty() or _state.terminal:
		return false
	return _conversion.extend_character(stop_generation, frames, is_exposed() or _action.snapshot().phase == "RECOVERY", _character_tail_must_wait())


func character_boss_exposure_snapshot(identity: Dictionary) -> Dictionary:
	return _conversion.exposure_snapshot(identity)


func can_restore_character_boss_exposure(value: Dictionary, identity: Dictionary, authorized: bool = false) -> bool:
	return not _state.is_empty() and _conversion.can_restore_exposure(value, identity, _character_tail_must_wait(), authorized)


func restore_character_boss_exposure(value: Dictionary, identity: Dictionary, authorized: bool = false) -> bool:
	return not _state.is_empty() and _conversion.restore_exposure(value, identity, _character_tail_must_wait(), authorized)


func snapshot() -> Dictionary:
	if _state.is_empty():
		return {}
	var value := _state.duplicate(true)
	value["action"] = _action.snapshot()
	value["control"] = _control.snapshot()
	value["conversion"] = _conversion.snapshot()
	if _arena != null:
		value["arena_state"] = _arena.snapshot()
	return value


func arena_snapshot() -> Dictionary:
	return _arena.snapshot() if _arena != null else {}


func accept_arena_damage_fact(value: Dictionary) -> Dictionary:
	return _arena.accept_damage_fact(value) if _arena != null and not _state.terminal else _failure("arena_unavailable")


func accept_arena_charge_impact(construct_id: String) -> Dictionary:
	var action: Dictionary = _action.snapshot()
	if _arena == null or _state.terminal or action.phase != "ACTIVE" or action.action_id != "guardian_charge" or action.geometry_generations.is_empty():
		return _failure("charge_impact")
	var fact_id := ("arena_charge:%s:%d:%s" % [_state.identity.hostile_source_id, int(action.geometry_generations[0]), construct_id]).sha256_text()
	var result: Dictionary = _arena.accept_damage_fact({"fact_id": fact_id, "run_id": str(_state.identity.run_id), "owner_source_id": str(_state.identity.hostile_source_id), "construct_id": construct_id, "runtime_frame": int(_state.runtime_frame), "amount": 80.0})
	if not result.ok:
		return result
	var cancelled: Dictionary = _action.cancel(&"declared_cover_charge_impact")
	_state.mechanism_state.phase_transition_until_frame = int(_state.runtime_frame) + 59
	_state.mechanism_state.exposure_through_frame = maxi(int(_state.mechanism_state.exposure_through_frame), int(_state.runtime_frame) + 59)
	_state.mechanism_state.delay_remaining_frames = 0
	_conversion.synchronize_tail(_character_tail_must_wait())
	return {"ok": true, "retired_generations": cancelled.retired_generations}


func normalize_native_snapshot(value: Dictionary) -> Dictionary:
	if _arena == null:
		return value.duplicate(true) if can_restore_snapshot(value) else {}
	if value.get("schema_version") == 2:
		return value.duplicate(true) if can_restore_snapshot(value) else {}
	if value.get("schema_version") != 1 or not Contract.exact_fields(value, STATE_FIELDS) or typeof(value.get("runtime_frame")) != TYPE_INT or typeof(value.get("terminal")) != TYPE_BOOL:
		return {}
	var normalized := value.duplicate(true)
	normalized.schema_version = 2
	normalized.arena_state = _arena.initial_at_frame(int(value.runtime_frame), bool(value.terminal))
	return normalized if can_restore_snapshot(normalized) else {}


func can_restore_native_snapshot(value: Dictionary) -> bool:
	return can_restore_snapshot(value) and (_arena == null or _arena.can_restore_snapshot(value.arena_state, true))


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, STATE_FIELDS + ["arena_state"] if _arena != null else STATE_FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != (2 if _arena != null else 1) or value.definition_digest != _state.definition_digest or value.identity != _state.identity or not Contract.integer_in_range(value.runtime_frame, int(_state.identity.runtime_frame), Controls.MAX_COUNTER - Contract.MAX_FRAME) or typeof(value.terminal) != TYPE_BOOL:
		return false
	if _arena != null and (not value.arena_state is Dictionary or not _arena.can_restore_snapshot(value.arena_state) or value.arena_state.runtime_frame != value.runtime_frame or value.arena_state.terminal != value.terminal):
		return false
	if not value.mechanism_state is Dictionary or not Contract.exact_fields(value.mechanism_state, MECHANISM_FIELDS) or not value.action is Dictionary or not value.control is Dictionary or not value.conversion is Dictionary or not _conversion.can_restore_snapshot(value.conversion):
		return false
	var mechanism: Dictionary = value.mechanism_state
	if not Contract.integer_in_range(mechanism.phase_index, 0, _definition.phases.size() - 1) or not Contract.integer_in_range(mechanism.action_phase_index, 0, int(mechanism.phase_index)) or not Contract.number_in_range(mechanism.hp_current, 0.0, _definition.max_hp) or not Contract.number_in_range(mechanism.minimum_hp, 0.0, float(mechanism.hp_current)) or int(mechanism.phase_index) != _phase_for_hp(float(mechanism.minimum_hp)):
		return false
	if typeof(mechanism.enraged) != TYPE_BOOL or mechanism.enraged != (int(value.runtime_frame) - int(value.identity.runtime_frame) >= int(_definition.enrage.threshold_frames)) or typeof(mechanism.action_enraged) != TYPE_BOOL or mechanism.action_enraged and not mechanism.enraged:
		return false
	if not Contract.integer_in_range(mechanism.phase_transition_until_frame, int(value.identity.runtime_frame) - 1, int(value.runtime_frame) + 60) or not Contract.integer_in_range(mechanism.exposure_through_frame, int(value.identity.runtime_frame) - 1, int(value.runtime_frame) + 120) or not Contract.integer_in_range(mechanism.delay_remaining_frames, 0, Contract.MAX_FRAME) or not Contract.integer_in_range(mechanism.consecutive_actions, 0, 3):
		return false
	if typeof(mechanism.last_action_id) != TYPE_STRING or not mechanism.last_action_id.is_empty() and _action_definition(mechanism.last_action_id).is_empty() or (mechanism.last_action_id.is_empty() != (int(mechanism.consecutive_actions) == 0)):
		return false
	if not mechanism.last_action_id.is_empty() and int(mechanism.consecutive_actions) > int(_action_definition(mechanism.last_action_id).max_consecutive):
		return false
	for field: String in ["damage_claims", "health_claims", "stop_claims"]:
		if not mechanism[field] is Array or mechanism[field].size() > MAX_CLAIMS:
			return false
		var seen: Dictionary = {}
		for id: Variant in mechanism[field]:
			if typeof(id) != TYPE_STRING or id.is_empty() or id.length() > (64 if field == "stop_claims" else 128) or seen.has(id):
				return false
			seen[id] = true
	var action := _make_action(int(mechanism.action_phase_index), mechanism.action_enraged)
	if action == null or not action.can_restore_snapshot(value.action) or not _control.can_restore_snapshot(value.control):
		return false
	if not _valid_temporal_state(mechanism, value):
		return false
	for source: Dictionary in value.control.sources:
		if source.kind == "stop" or source.kind == "rift" and float(source.magnitude) < 0.70:
			return false
	if int(value.action.last_runtime_frame) != int(value.runtime_frame) or int(value.control.runtime_frame) != int(value.runtime_frame) or int(value.conversion.runtime_frame) != int(value.runtime_frame) or value.control.terminal != value.terminal:
		return false
	if int(value.runtime_frame) <= int(mechanism.phase_transition_until_frame) and value.action.phase != "IDLE":
		return false
	if int(mechanism.action_phase_index) != int(mechanism.phase_index) or float(value.conversion.poise) > float(_definition.phases[int(mechanism.phase_index)].poise_threshold):
		return false
	if not value.conversion.claims.is_empty():
		var must_wait: bool = value.action.phase == "RECOVERY" or int(value.runtime_frame) <= int(mechanism.exposure_through_frame)
		if (value.conversion.claims[0].state == "pending") != must_wait:
			return false
	return not value.terminal or value.action.phase == "IDLE" and int(mechanism.delay_remaining_frames) == 0 and value.conversion.claims.is_empty() and value.conversion.weapon_sources.is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	var action := _make_action(int(value.mechanism_state.action_phase_index), value.mechanism_state.action_enraged)
	if not action.restore_snapshot(value.action) or not _control.restore_snapshot(value.control) or not _conversion.restore_snapshot(value.conversion):
		return false
	if _arena != null and not _arena.restore_snapshot(value.arena_state):
		return false
	_action = action
	_state = value.duplicate(true)
	_state.erase("action")
	_state.erase("control")
	_state.erase("conversion")
	_state.erase("arena_state")
	return true


func cancel(reason: StringName = &"cancelled") -> Dictionary:
	if _state.is_empty() or _state.terminal or reason == &"":
		return _failure("terminal")
	var result: Dictionary = _action.cancel(reason)
	_cancel_pending_rewind()
	_control.cancel(reason)
	_conversion.cancel()
	_state.terminal = true
	if _arena != null:
		_arena.retire()
	_state.mechanism_state.delay_remaining_frames = 0
	return result


func cancel_action(reason: StringName = &"interrupted") -> Dictionary:
	if _state.is_empty() or _state.terminal or reason == &"":
		return _failure("action_unavailable")
	_state.mechanism_state.delay_remaining_frames = 0
	_cancel_pending_rewind()
	var result: Dictionary = _action.cancel(reason)
	_conversion.synchronize_tail(_character_tail_must_wait())
	return result


func _valid_temporal_state(mechanism: Dictionary, value: Dictionary) -> bool:
	if not mechanism.history is Array or not mechanism.rewind is Dictionary or not mechanism.weakpoint_claims is Array or mechanism.weakpoint_claims.size() > MAX_CLAIMS or not Contract.number_in_range(mechanism.rewind_healing_spent, 0.0, 300.0):
		return false
	if _definition.id != "time_sovereign":
		return mechanism.history.is_empty() and mechanism.rewind.is_empty() and mechanism.weakpoint_claims.is_empty() and float(mechanism.rewind_healing_spent) == 0.0
	var history_size := mini(int(_definition.mechanisms.history_frames), int(value.runtime_frame) - int(value.identity.runtime_frame))
	if mechanism.history.size() != history_size:
		return false
	for index: int in range(mechanism.history.size()):
		var row: Variant = mechanism.history[index]
		if not _valid_history_row(row) or int(row.runtime_frame) != int(value.runtime_frame) - history_size + 1 + index:
			return false
	var seen: Dictionary = {}
	for claim: Variant in mechanism.weakpoint_claims:
		if typeof(claim) != TYPE_STRING or claim.is_empty() or claim.length() > 128 or seen.has(claim):
			return false
		seen[claim] = true
	var rewind: Dictionary = mechanism.rewind
	if rewind.is_empty():
		return mechanism.rewind_healing_spent == 0.0 and mechanism.weakpoint_claims.is_empty()
	if not Contract.exact_fields(rewind, REWIND_FIELDS) or not _valid_history_row(rewind.history_reference) or rewind.landing != rewind.history_reference.position or not Contract.integer_in_range(rewind.attack_generation, int(value.identity.next_generation_floor), int(value.action.next_generation_floor) - 1) or not Contract.integer_in_range(rewind.commit_frame, int(value.identity.runtime_frame), int(value.runtime_frame)):
		return false
	if not Contract.integer_in_range(rewind.history_reference.runtime_frame, maxi(int(value.identity.runtime_frame), int(rewind.commit_frame) - int(_definition.mechanisms.history_frames) + 1), int(rewind.commit_frame)) or not Contract.number_in_range(rewind.hp_at_commit, 0.000001, _definition.max_hp) or not Contract.number_in_range(rewind.healing_spent_before, 0.0, _definition.mechanisms.rewind_heal_encounter_cap) or not Contract.number_in_range(rewind.heal_amount, 0.0, _definition.mechanisms.rewind_heal_per_cast_cap) or not Contract.number_in_range(rewind.weakpoint_damage, 0.0, _definition.mechanisms.rewind_interrupt_damage) or typeof(rewind.consumed) != TYPE_BOOL or typeof(rewind.cancelled) != TYPE_BOOL or rewind.cancelled and not rewind.consumed:
		return false
	var expected_heal := minf(maxf(0.0, float(rewind.history_reference.hp) - float(rewind.hp_at_commit)), minf(float(_definition.mechanisms.rewind_heal_per_cast_cap), float(_definition.mechanisms.rewind_heal_encounter_cap) - float(rewind.healing_spent_before)))
	if not is_equal_approx(float(rewind.heal_amount), expected_heal) or not is_equal_approx(float(mechanism.rewind_healing_spent), float(rewind.healing_spent_before) + (float(rewind.heal_amount) if rewind.consumed and not rewind.cancelled else 0.0)):
		return false
	if not rewind.consumed:
		return value.action.action_id == "traitor_self_rewind" and value.action.phase == "WARNING" and value.action.geometry_generations == [rewind.attack_generation] and int(value.action.commit_frame) == int(rewind.commit_frame)
	return true


func _valid_history_row(value: Variant) -> bool:
	if not value is Dictionary or not Contract.exact_fields(value, HISTORY_FIELDS) or typeof(value.runtime_frame) != TYPE_INT or not Contract.valid_point(value.position) or not Contract.number_in_range(value.hp, 0.0, _definition.max_hp):
		return false
	var bounds: Dictionary = _definition.arena.bounds
	return float(value.position.x) >= float(bounds.x) and float(value.position.x) <= float(bounds.x) + float(bounds.width) and float(value.position.y) >= float(bounds.y) and float(value.position.y) <= float(bounds.y) + float(bounds.height)


func _sync_action_regime() -> bool:
	var mechanism: Dictionary = _state.mechanism_state
	if _action.snapshot().phase != "IDLE" or int(mechanism.action_phase_index) == int(mechanism.phase_index) and mechanism.action_enraged == mechanism.enraged:
		return true
	var next := _make_action(int(mechanism.phase_index), mechanism.enraged)
	if next == null:
		return false
	var checkpoint: Dictionary = _action.snapshot()
	checkpoint.definition_digest = next.snapshot().definition_digest
	if not next.restore_snapshot(checkpoint):
		return false
	_action = next
	mechanism.action_phase_index = mechanism.phase_index
	mechanism.action_enraged = mechanism.enraged
	return true


func _make_action(phase_index: int, enraged: bool) -> RefCounted:
	var identity: Dictionary = _state.identity.duplicate(true)
	identity.erase("seed")
	var result := Action.new()
	var actions := _actions_for_regime(phase_index, enraged)
	return result if result.configure({"id": _definition.id, "actor_kind": "boss", "actions": actions}, identity).ok else null


func _actions_for_regime(phase_index: int, enraged: bool) -> Array:
	var actions: Array = (_definition.actions + _definition.time_responses).duplicate(true)
	var overrides: Dictionary = _definition.mechanisms.phase_damage_overrides.get(_definition.phases[phase_index].id, {})
	for action: Dictionary in actions:
		if enraged:
			action.cooldown_frames = ceili(int(action.cooldown_frames) * float(_definition.enrage.cooldown_multiplier))
		for hit: Dictionary in action.hit_schedule:
			hit.damage = float(overrides.get(action.id, hit.damage)) * (float(_definition.enrage.damage_multiplier) if enraged else 1.0)
	return actions


func _action_available(action_id: String) -> bool:
	var action := _action_definition(action_id)
	if action.is_empty() or action_id not in _definition.phases[int(_state.mechanism_state.phase_index)].action_ids and not (_state.mechanism_state.enraged and action_id == _definition.enrage.action_id):
		return false
	return _state.mechanism_state.last_action_id != action_id or int(_state.mechanism_state.consecutive_actions) < int(action.max_consecutive)


func _select_action(frame: int, observations: Dictionary) -> String:
	var current: Dictionary = _action.snapshot()
	if frame <= int(current.idle_through_frame) or frame <= int(_state.mechanism_state.phase_transition_until_frame):
		return ""
	var candidates: Array[Dictionary] = []
	var weight := 0
	var distance := _vector(observations.source_position).distance_to(_vector(observations.target_position))
	for action: Dictionary in _definition.actions:
		if _action_available(action.id) and int(current.cooldowns.get(action.id, 0)) <= frame and distance >= float(action.distance_min_px) and distance <= float(action.distance_max_px):
			candidates.append(action)
			weight += int(action.weight)
	if candidates.is_empty():
		return ""
	var rng := Seeds.make_rng(int(_state.identity.seed), StringName("boss_decision_v1:%s:%d:%d" % [_state.identity.hostile_source_id, int(_state.mechanism_state.phase_index), int(current.decision_index)]))
	var selected := rng.randi_range(1, weight)
	for action: Dictionary in candidates:
		selected -= int(action.weight)
		if selected <= 0:
			return action.id
	return ""


func _action_definition(action_id: String) -> Dictionary:
	if _state.is_empty():
		return {}
	for action: Dictionary in _actions_for_regime(int(_state.mechanism_state.action_phase_index), _state.mechanism_state.action_enraged):
		if action.id == action_id:
			return action
	return {}


func _phase_for_hp(hp: float) -> int:
	var phase := 0
	for index: int in range(1, _definition.phases.size()):
		if hp <= float(_definition.max_hp) * float(_definition.phases[index].hp_threshold):
			phase = index
	return phase


func _delays_action(frame: int) -> bool:
	return frame <= int(_state.mechanism_state.phase_transition_until_frame) or int(_state.mechanism_state.delay_remaining_frames) > 0 and _action.snapshot().phase in ["WARNING", "RECOVERY"]


func _character_tail_must_wait() -> bool:
	return not _state.is_empty() and (_action.snapshot().phase == "RECOVERY" or int(_state.runtime_frame) <= int(_state.mechanism_state.exposure_through_frame))


func _controls_for_frame(frame: int) -> Dictionary:
	var preview := Controls.new()
	preview.configure(_control.snapshot().identity)
	if not preview.restore_snapshot(_control.snapshot()):
		return {}
	var result: Dictionary = preview.advance_frame(frame)
	return result if result.ok else {}


func _valid_observations(frame: int, observations: Dictionary) -> bool:
	return not _state.is_empty() and not _state.terminal and frame == int(_state.runtime_frame) + 1 and Contract.exact_fields(observations, Action.CONTEXT_FIELDS) and observations.runtime_frame == frame and Contract.valid_point(observations.source_position) and Contract.valid_point(observations.target_position) and Contract.valid_point(observations.facing_direction, 1.0) and typeof(observations.target_id) == TYPE_STRING and not observations.target_id.is_empty()


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))


static func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"LAUNCH_BOSS_INVALID", "context": {"field": field}}
