class_name LaunchBossRuntime
extends RefCounted

const Action := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Controls := preload("res://scripts/enemies/launch/hostile_control_runtime.gd")
const Conversion := preload("res://scripts/enemies/launch/boss_conversion_runtime.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Seeds := preload("res://scripts/core/seed_service.gd")
const Arena := preload("res://scripts/enemies/launch/boss_arena_runtime.gd")
const ForestArena := preload("res://scripts/enemies/launch/forest_arena_runtime.gd")
const ForestAuxiliary := preload("res://scripts/enemies/launch/forest_auxiliary_runtime.gd")
const VoidArena := preload("res://scripts/enemies/launch/void_arena_runtime.gd")
const VoidAuxiliary := preload("res://scripts/enemies/launch/void_auxiliary_runtime.gd")
const ForgeArena := preload("res://scripts/enemies/launch/forge_arena_runtime.gd")
const VoidHalf := preload("res://scripts/enemies/launch/void_half_arena_geometry.gd")
const TimeResponses := preload("res://scripts/enemies/launch/time_sovereign_response_runtime.gd")
const TimeAuxiliary := preload("res://scripts/enemies/launch/time_sovereign_auxiliary_runtime.gd")
const IDENTITY_FIELDS: Array[String] = ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]
const STATE_FIELDS: Array[String] = ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "mechanism_state", "action", "control", "conversion"]
const MECHANISM_FIELDS: Array[String] = ["phase_index", "hp_current", "minimum_hp", "phase_transition_until_frame", "enraged", "action_phase_index", "action_enraged", "delay_remaining_frames", "exposure_through_frame", "last_action_id", "consecutive_actions", "damage_claims", "health_claims", "stop_claims", "history", "rewind", "rewind_healing_spent", "weakpoint_claims"]
const DAMAGE_FACT_FIELDS: Array[String] = ["fact_id", "runtime_frame", "target_source_id", "amount", "hp_after"]
const HISTORY_FIELDS: Array[String] = ["runtime_frame", "position", "hp"]
const REWIND_FIELDS: Array[String] = ["attack_generation", "commit_frame", "history_reference", "landing", "hp_at_commit", "heal_amount", "healing_spent_before", "weakpoint_damage", "consumed", "cancelled"]
const MAX_CLAIMS := 512
const MAX_DAMAGE_CLAIMS := 10000
const MAX_SNAPSHOT_VALIDATION_CACHE := 4

var _definition: Dictionary = {}
var _state: Dictionary = {}
var _action: RefCounted
var _control: RefCounted = Controls.new()
var _conversion: RefCounted = Conversion.new()
var _arena_origin := {"x": 0.0, "y": 0.0}
var _arena_trunk_origin := {"x": 320.0, "y": 144.0}
var _arena: RefCounted
var _forest_auxiliary: RefCounted
var _void_arena: RefCounted
var _void_auxiliary: RefCounted
var _forge_arena: RefCounted
var _legacy_void_action := false
var _time_response: RefCounted
var _time_auxiliary: RefCounted
var _legacy_time_action := false
var _snapshot_validation_cache: Array[Dictionary] = []
var _snapshot_validation_cache_mutex := Mutex.new()


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	_clear_snapshot_validation_cache()
	_definition.clear()
	_state.clear()
	_action = null
	_arena = null
	_forest_auxiliary = null
	_void_arena = null
	_void_auxiliary = null
	_forge_arena = null
	_legacy_void_action = false
	_time_response = null
	_time_auxiliary = null
	_legacy_time_action = false
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
	elif _definition.id == "forest_heart":
		_arena = ForestArena.new()
		if not _arena.configure(_definition, identity).ok or not _arena.bind_origin(_arena_origin):
			return _failure("forest_arena_configuration")
		_forest_auxiliary = ForestAuxiliary.new()
		if not _forest_auxiliary.configure(_definition, identity).ok or not _forest_auxiliary.bind_origin(_arena_origin):
			return _failure("forest_auxiliary_configuration")
	elif _definition.id == "void_throne":
		_void_arena = VoidArena.new()
		if not _void_arena.configure(_definition, identity).ok or not _void_arena.bind_origin(_arena_origin):
			return _failure("void_arena_configuration")
		_void_auxiliary = VoidAuxiliary.new()
		if not _void_auxiliary.configure(_definition, identity).ok or not _void_auxiliary.bind_origin(_arena_origin):
			return _failure("void_auxiliary_configuration")
	elif _definition.id == "forge_colossus":
		_forge_arena = ForgeArena.new()
		if not _forge_arena.configure(_definition, identity).ok or not _forge_arena.bind_origin(_arena_origin):
			return _failure("forge_arena_configuration")
	elif _definition.id == "time_sovereign":
		_time_response = TimeResponses.new()
		if not _time_response.configure(identity, _definition.mechanisms):
			return _failure("time_response_configuration")
		_time_auxiliary = TimeAuxiliary.new()
		if not _time_auxiliary.configure(identity):
			return _failure("time_auxiliary_configuration")
	var action_identity := identity.duplicate(true)
	action_identity.erase("seed")
	var initial_action := Action.new()
	var action_result := initial_action.configure({"id": _definition.id, "actor_kind": "boss", "actions": _actions_for_regime(0, false)}, action_identity)
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
		_state.schema_version = 4 if _definition.id == "forest_heart" else 2
	if _void_arena != null:
		_state.schema_version = 8
		_state["void_half_index"] = 0
	if _forge_arena != null:
		_state.schema_version = 6
	if _time_response != null:
		_state.schema_version = 10
	return {"ok": true, "snapshot": snapshot()}


func configure_arena_origin(origin: Dictionary, trunk_origin: Dictionary = {}) -> bool:
	_clear_snapshot_validation_cache()
	if not Contract.valid_point(origin) or not trunk_origin.is_empty() and not Contract.valid_point(trunk_origin):
		return false
	if _arena != null and _definition.id == "forest_heart" and not _arena.bind_origin(origin):
		return false
	if _forest_auxiliary != null and not _forest_auxiliary.bind_origin(origin):
		return false
	if _void_arena != null and not _void_arena.bind_origin(origin):
		return false
	if _void_auxiliary != null and not _void_auxiliary.bind_origin(origin):
		return false
	if _forge_arena != null and not _forge_arena.bind_origin(origin):
		return false
	_arena_origin = origin.duplicate(true)
	_arena_trunk_origin = {"x": float(origin.x) + 320.0, "y": float(origin.y) + 144.0} if trunk_origin.is_empty() else trunk_origin.duplicate(true)
	return true


func request_action(action_id: String, context: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not _action_available(action_id) or int(_state.runtime_frame) <= int(_state.mechanism_state.phase_transition_until_frame):
		return _failure("action_unavailable")
	if not _sync_action_regime():
		return _failure("action_regime")
	var requested_context := context.duplicate(true)
	var response := {}
	if _time_response != null and action_id in Definition.RESPONSE_IDS:
		response = _time_response.pending_request(int(_state.runtime_frame))
		if response.is_empty() or response.action_id != action_id or not Contract.exact_fields(context, Action.CONTEXT_FIELDS):
			return _failure("response_requires_committed_ability")
		if action_id == "traitor.counter_rewind":
			requested_context.target_position = response.receipt.endpoint.duplicate(true)
			requested_context.facing_direction = response.receipt.facing.duplicate(true)
		else:
			requested_context.target_position = context.source_position.duplicate(true)
	if _void_arena != null and action_id in VoidHalf.ACTION_IDS:
		if not Contract.exact_fields(context, Action.CONTEXT_FIELDS) or not Contract.valid_point(context.source_position) or not Contract.valid_point(context.target_position) or not Contract.valid_point(context.facing_direction, 1) or _vector(context.facing_direction).is_zero_approx():
			return _failure("half_context")
		requested_context = VoidHalf.anchored_context(context, _arena_origin, action_id == "voidking_enrage_zero" and int(_state.void_half_index) % 2 == 1)
	var seed_sac := {}
	if _forest_auxiliary != null and action_id == "matriarch_void_seed":
		seed_sac = _forest_auxiliary.select_seed_sac(context.get("target_position", {}))
		if seed_sac.is_empty():
			return _failure("seed_sacs_exhausted")
		requested_context.target_position = seed_sac.position.duplicate(true)
	elif _forest_auxiliary != null and action_id == "matriarch_void_cage":
		if not Contract.valid_point(context.get("target_position")):
			return _failure("cage_context")
		requested_context.source_position = context.target_position.duplicate(true)
		requested_context.target_position = {"x": float(context.target_position.x) + 1.0, "y": float(context.target_position.y)}
	var rooted: bool = _definition.id == "forest_heart" and action_id == "matriarch_root_sweep"
	if rooted:
		if not Contract.exact_fields(context, Action.CONTEXT_FIELDS) or not Contract.valid_point(context.target_position):
			return _failure("root_sweep_context")
		var selected: Dictionary = _arena.select_sweep_root(context.target_position)
		if selected.is_empty():
			return _failure("root_sweep_unavailable")
		requested_context.source_position = selected.position.duplicate(true)
	var before := snapshot()
	var result: Dictionary = _action.request_action(action_id, requested_context)
	if result.ok and not response.is_empty() and not _time_response.commit_request(response, int(result.attack_generation), int(_state.runtime_frame), int(_state.mechanism_state.phase_index)):
		restore_snapshot(before)
		return _failure("time_response_commit")
	if result.ok and rooted and not _arena.accept_sweep_commit(_action.snapshot()):
		restore_snapshot(before)
		return _failure("root_sweep_commit")
	if result.ok and not seed_sac.is_empty() and not _forest_auxiliary.reserve_seed(int(_action.snapshot().geometry_generations[0]), str(seed_sac.id), int(_state.runtime_frame)).ok:
		restore_snapshot(before)
		return _failure("seed_commit")
	if result.ok:
		if action_id == "voidking_enrage_zero":
			_state.void_half_index += 1
		var mechanism: Dictionary = _state.mechanism_state
		mechanism.consecutive_actions = int(mechanism.consecutive_actions) + 1 if response.is_empty() and mechanism.last_action_id == action_id else 1
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
		if _void_auxiliary != null and action.action_id == "voidking_void_step" and frame - int(action.commit_frame) - int(action.paused_frames) == int(definition.warning_frames):
			displacement = _vector(action.committed_geometry[0].origin) - _vector(observations.source_position)
			relocation = true
		elif action.action_id in ["traitor.counter_rewind", "traitor_blink"] and frame - int(action.commit_frame) - int(action.paused_frames) == int(definition.warning_frames):
			displacement = _vector(action.committed_geometry[0].origin) - _vector(observations.source_position)
			relocation = true
		elif not definition.is_empty() and definition.handler_id == "self_rewind" and Action.action_phase(frame - int(action.commit_frame) - int(action.paused_frames), definition) == "ACTIVE" and not _state.mechanism_state.rewind.is_empty() and not _state.mechanism_state.rewind.consumed:
			displacement = _vector(_state.mechanism_state.rewind.landing) - _vector(observations.source_position)
			relocation = true
		elif not definition.is_empty() and definition.handler_id == "charge" and Action.action_phase(frame - int(action.commit_frame) - int(action.paused_frames), definition) == "ACTIVE":
			var direction := _vector(action.committed_aim)
			var travelled := (_vector(observations.source_position) - _vector(action.committed_origin)).dot(direction)
			displacement = direction * minf(maxf(0.0, float(definition.parameters.travel_px) - travelled), float(definition.parameters.speed_px_per_second) * float(control.movement_multiplier) / 60.0)
		elif not definition.is_empty() and definition.handler_id == "wall" and action.phase == "WARNING":
			var direction := _vector(action.committed_aim)
			var desired := _vector(action.committed_origin) - direction * (float(_definition.collision_radius_px) + 7.0)
			var remaining := _vector(observations.source_position).distance_to(desired)
			displacement = _vector(observations.source_position).direction_to(desired) * minf(remaining, float(_definition.phases[int(_state.mechanism_state.phase_index)].move_speed) / 60.0)
		elif action.phase == "IDLE":
			var source := _vector(observations.source_position)
			var target := _vector(observations.target_position)
			var speed := float(_definition.phases[int(_state.mechanism_state.phase_index)].move_speed) * float(control.movement_multiplier) / 60.0
			displacement = source.direction_to(target) * minf(maxf(0.0, source.distance_to(target) - 40.0), speed)
		elif _definition.id == "forge_colossus" and action.action_id == "forge_forged_cyclone" and Action.action_phase(frame - int(action.commit_frame) - int(action.paused_frames), definition) == "ACTIVE":
			displacement = _vector(action.committed_aim) * float(_definition.mechanisms.cyclone_move_speed) * float(control.movement_multiplier) / 60.0
	return {"ok": true, "displacement": _point(displacement), "action_paused": paused, "relocation": relocation}


func advance_frame(frame: int, observations: Dictionary, select_action: bool = true, external_action_paused: bool = false) -> Dictionary:
	if not _valid_observations(frame, observations):
		return _failure("observations")
	var before := snapshot()
	var controls: Dictionary = _control.advance_frame(frame)
	if not controls.ok:
		return controls
	controls.attack_multiplier = float(controls.get("attack_multiplier", 1.0)) * daily_outgoing_multiplier()
	var delayed := _delays_action(frame)
	var result: Dictionary = _action.advance_frame(frame, observations, delayed or external_action_paused)
	if not result.ok:
		_control.restore_snapshot(before.control)
		return result
	_state.runtime_frame = frame
	if _time_response != null and not _time_response.advance_frame(frame):
		restore_snapshot(before)
		return _failure("time_response_frame")
	if _time_auxiliary != null and not _time_auxiliary.advance_frame(frame):
		restore_snapshot(before)
		return _failure("time_auxiliary_frame")
	if _forge_arena != null and not _forge_arena.advance_frame(frame):
		restore_snapshot(before)
		return _failure("forge_arena_frame")
	if _arena != null and not _arena.advance_frame(frame):
		restore_snapshot(before)
		return _failure("arena_frame")
	if _forest_auxiliary != null and not _forest_auxiliary.advance_frame(frame):
		restore_snapshot(before)
		return _failure("forest_auxiliary_frame")
	if _void_arena != null and not _void_arena.advance_frame(frame):
		restore_snapshot(before)
		return _failure("void_arena_frame")
	if _void_auxiliary != null and not _void_auxiliary.advance_frame(frame):
		restore_snapshot(before)
		return _failure("void_auxiliary_frame")
	if delayed and int(_state.mechanism_state.delay_remaining_frames) > 0 and _action.snapshot().phase in ["WARNING", "RECOVERY"] and not external_action_paused:
		_state.mechanism_state.delay_remaining_frames -= 1
	_state.mechanism_state.enraged = frame - int(_state.identity.runtime_frame) >= int(_definition.enrage.threshold_frames)
	if not _conversion.advance_frame(frame, _character_tail_must_wait()):
		restore_snapshot(before)
		return _failure("conversion_frame")
	result["mechanism_requests"] = []
	result["threat_facts"] = []
	if _void_auxiliary != null:
		for effect: Dictionary in result.effect_requests:
			if not str(effect.action_id).begins_with("voidking_"):
				continue
			var multiplier := (float(_definition.enrage.damage_multiplier) if _state.mechanism_state.action_enraged else 1.0) * float(controls.get("attack_multiplier", 1.0))
			if not _void_auxiliary.reserve_cast({"run_id": str(_state.identity.run_id), "owner_source_id": str(_state.identity.hostile_source_id), "action_id": effect.action_id, "attack_generation": int(effect.attack_generation), "runtime_frame": frame, "geometry": effect.geometry.duplicate(true), "damage_multiplier": multiplier}).ok:
				restore_snapshot(before)
				return _failure("void_cast_reservation")
			if effect.action_id == "voidking_void_step":
				var landing := _point(_vector(observations.source_position))
				var landed := _vector(landing).is_equal_approx(_vector(effect.geometry[0].origin))
				if not _void_auxiliary.accept_landing_receipt({"run_id": str(_state.identity.run_id), "owner_source_id": str(_state.identity.hostile_source_id), "attack_generation": int(effect.attack_generation), "runtime_frame": frame, "position": landing, "landed": landed}).ok:
					restore_snapshot(before)
					return _failure("void_step_landing")
				var retired: Dictionary = _action.cancel(&"void_step_landed" if landed else &"void_step_blocked")
				result.retired_generations.append_array(retired.retired_generations)
				result.phase = "IDLE"
		for request: Dictionary in _void_auxiliary.mechanism_requests(frame):
			result.mechanism_requests.append(request)
		var followup: Dictionary = _void_auxiliary.step_followup_request(frame)
		if not followup.is_empty() and _action.snapshot().phase == "IDLE":
			for id: String in ["voidking_scepter_strike", "voidking_void_bolt"]:
				var requested := request_action(id, observations)
				if not requested.ok:
					continue
				if not _void_auxiliary.accept_followup_receipt(int(followup.step_generation), int(requested.attack_generation), frame).ok:
					restore_snapshot(before)
					return _failure("void_step_followup")
				result.threat_facts = requested.threat_facts
				result.phase = requested.phase
				break
		_conversion.synchronize_tail(_character_tail_must_wait())
	if _forest_auxiliary != null:
		for request: Dictionary in _forest_auxiliary.cage_requests(frame):
			request.hostile_source_id = str(_state.identity.hostile_source_id)
			request.run_id = str(_state.identity.run_id)
			result.mechanism_requests.append(request)
	if _arena != null and _definition.id == "ruin_king":
		for wall: Dictionary in _arena.snapshot().walls:
			if wall.broken or frame != int(wall.spawn_frame) + int(wall.lifetime_frames):
				continue
			result.mechanism_requests.append({"kind": "boss_wall_collapse", "run_id": str(_state.identity.run_id), "hostile_source_id": str(_state.identity.hostile_source_id), "runtime_frame": frame, "attack_generation": int(wall.attack_generation) + int(wall.slot), "wall_id": str(wall.id), "position": wall.position.duplicate(true), "parameters": {"warning_frames": int(_definition.mechanisms.wall_collapse_warning_frames), "radius": float(_definition.mechanisms.wall_collapse_radius_px), "damage": float(_definition.mechanisms.wall_collapse_damage) * (float(_definition.enrage.damage_multiplier) if _state.mechanism_state.enraged else 1.0) * float(controls.get("attack_multiplier", 1.0))}})
	for hit: Dictionary in result.hit_facts:
		hit.damage = float(hit.damage) * float(controls.get("attack_multiplier", 1.0))
		if _forest_auxiliary != null and hit.action_id == "matriarch_void_seed":
			var burst: Dictionary = _forest_auxiliary.seed_burst(int(hit.attack_generation), frame)
			if not burst.ok:
				restore_snapshot(before)
				return _failure("seed_burst")
			result.mechanism_requests.append({"kind": "forest_seed_pool", "run_id": str(_state.identity.run_id), "hostile_source_id": str(_state.identity.hostile_source_id), "runtime_frame": frame, "attack_generation": int(hit.attack_generation), "position": burst.position.duplicate(true), "parameters": {"radius": float(_definition.mechanisms.seed_pool_radius_px), "lifetime_frames": int(_definition.mechanisms.seed_pool_lifetime_frames), "tick_frames": int(_definition.mechanisms.seed_pool_tick_frames), "damage": float(_definition.mechanisms.seed_pool_tick_damage) * (float(_definition.enrage.damage_multiplier) if _state.mechanism_state.action_enraged else 1.0) * float(controls.get("attack_multiplier", 1.0))}})
		if _forest_auxiliary != null and hit.action_id == "matriarch_enrage_dissolution" and int(_forest_auxiliary.snapshot().erosion_steps) < 2 and not _forest_auxiliary.accept_erosion(int(hit.attack_generation), frame).ok:
			restore_snapshot(before)
			return _failure("forest_erosion")
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
		_time_response.observe_action(_action.snapshot())
		for hit: Dictionary in result.hit_facts:
			if hit.action_id == "traitor.counter_rift" and _time_response.grant_rift_recovery(int(hit.attack_generation)):
				_state.mechanism_state.delay_remaining_frames += int(_definition.mechanisms.counter_rift_recovery_extension_frames)
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
		var response: Dictionary = _time_response.pending_request(frame) if _time_response != null else {}
		var selected := str(response.action_id) if not response.is_empty() else _select_action(frame, observations)
		if not selected.is_empty():
			var requested := request_action(selected, observations)
			if requested.ok:
				result.threat_facts = requested.threat_facts
				result.phase = requested.phase
	result["action_paused"] = delayed or external_action_paused
	result["movement_multiplier"] = float(controls.movement_multiplier)
	return result


func daily_outgoing_multiplier() -> float:
	return 2.0 if _definition.get("daily_conditions", {}).get("ids", []).has("final_strike") and not _state.is_empty() and float(_state.mechanism_state.hp_current) < float(_definition.max_hp) * 0.1 else 1.0


func charge_contact_fact(frame: int, target_id: String) -> Dictionary:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame):
		return {}
	var state: Dictionary = _action.snapshot()
	var action := _action_definition(str(state.action_id))
	if state.phase != "ACTIVE" or action.is_empty() or action.handler_id != "charge" or target_id != state.target_id:
		return {}
	var result := Action._hit_fact(action.hit_schedule[0], action, state)
	result.damage = float(result.damage) * daily_outgoing_multiplier()
	return result


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
	if mechanism.damage_claims.size() >= MAX_DAMAGE_CLAIMS or mechanism.damage_claims.has(value.fact_id) or not is_equal_approx(maxf(0.0, float(mechanism.hp_current) - float(value.amount)), float(value.hp_after)):
		return _failure("duplicate_or_inconsistent_damage")
	var before := snapshot()
	mechanism.damage_claims.append(value.fact_id)
	mechanism.hp_current = float(value.hp_after)
	_update_history_hp(int(value.runtime_frame), float(value.hp_after))
	mechanism.minimum_hp = minf(float(mechanism.minimum_hp), float(value.hp_after))
	var phase := _phase_for_hp(float(mechanism.minimum_hp))
	var retired: Array = []
	if phase > int(mechanism.phase_index):
		_cancel_pending_rewind()
		_cancel_pending_forest_seed(int(value.runtime_frame))
		retired = _action.cancel(&"phase_transition").retired_generations
		mechanism.phase_index = phase
		mechanism.phase_transition_until_frame = int(value.runtime_frame) + 59
		mechanism.delay_remaining_frames = 0
		if _definition.id == "forest_heart" and not _arena.accept_phase_retirement(int(value.runtime_frame)).ok:
			restore_snapshot(before)
			return _failure("forest_phase_retirement")
		if _forge_arena != null and not _forge_arena.accept_phase(phase, int(value.runtime_frame)).ok:
			restore_snapshot(before)
			return _failure("forge_phase_retirement")
		if _void_arena != null and not _void_arena.accept_phase(phase, int(value.runtime_frame)).ok:
			restore_snapshot(before)
			return _failure("void_phase_retirement")
		if _void_auxiliary != null and not _void_auxiliary.accept_phase(phase, int(value.runtime_frame)).ok:
			restore_snapshot(before)
			return _failure("void_auxiliary_phase")
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


func accept_time_ability_receipt(value: Dictionary) -> Dictionary:
	return _time_response.accept_receipt(value) if _time_response != null else _failure("unsupported_time_response")


func accept_time_response_watch_hit(value: Dictionary) -> Dictionary:
	if _time_response == null:
		return _failure("unsupported_time_response")
	var result: Dictionary = _time_response.accept_watch_hit(value, _action.snapshot())
	if not result.ok:
		return result
	result["retired_generations"] = []
	if result.cancel_action:
		result.retired_generations = _action.cancel(&"watch_time_response_counterplay").retired_generations
		_state.mechanism_state.delay_remaining_frames = 0
	if result.exposure_frames > 0:
		_state.mechanism_state.exposure_through_frame = maxi(int(_state.mechanism_state.exposure_through_frame), int(value.runtime_frame) + int(result.exposure_frames) - 1)
	if result.recovery_frames > 0:
		_state.mechanism_state.phase_transition_until_frame = maxi(int(_state.mechanism_state.phase_transition_until_frame), int(value.runtime_frame) + int(result.recovery_frames) - 1)
	_conversion.synchronize_tail(_character_tail_must_wait())
	return result


func time_response_zone_alive(generation: int) -> bool:
	return _time_response != null and _time_response.zone_alive(generation)


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
	return not _state.is_empty() and not _state.terminal and (int(_state.runtime_frame) <= int(_state.mechanism_state.exposure_through_frame) or _conversion.is_character_exposed() or _definition.id == "forest_heart" and _arena.is_exposed() or _void_arena != null and _void_arena.is_exposed() or _void_auxiliary != null and int(_state.runtime_frame) <= int(_void_auxiliary.snapshot().exposure_through_frame))


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
	if _forest_auxiliary != null:
		value["forest_auxiliary"] = _forest_auxiliary.snapshot()
	if _forge_arena != null:
		value["forge_arena_state"] = _forge_arena.snapshot()
	if _void_arena != null:
		value["void_arena_state"] = _void_arena.snapshot()
	if _void_auxiliary != null:
		value["void_auxiliary"] = _void_auxiliary.snapshot()
	if _time_response != null:
		value["time_response"] = _time_response.snapshot()
	if _time_auxiliary != null:
		value["time_auxiliary"] = _time_auxiliary.snapshot()
	return value


func native_runtime_frame() -> int:
	return int(_state.get("runtime_frame", -1))


func native_run_id() -> String:
	return str(_state.get("identity", {}).get("run_id", ""))


func native_is_terminal() -> bool:
	return bool(_state.get("terminal", false))


func native_action_snapshot() -> Dictionary:
	return _action.snapshot() if _action != null else {}


func time_auxiliary_snapshot() -> Dictionary:
	return _time_auxiliary.snapshot() if _time_auxiliary != null else {}


func accept_time_auxiliary_damage_receipt(fact: Dictionary) -> Dictionary:
	return _time_auxiliary.accept_damage_receipt(fact) if _time_auxiliary != null else _failure("time_auxiliary")


func time_damage_multiplier(target_id: String) -> float:
	return _time_auxiliary.time_damage_multiplier(target_id) if _time_auxiliary != null else 1.0


func void_arena_snapshot() -> Dictionary:
	return _void_arena.snapshot() if _void_arena != null else {}


func native_void_arena_geometry_snapshot() -> Dictionary:
	return _void_arena.native_geometry_snapshot() if _void_arena != null else {}


func native_void_active_pickups() -> Array:
	return _void_auxiliary.active_pickups() if _void_auxiliary != null else []


func void_auxiliary_snapshot() -> Dictionary:
	return _void_auxiliary.snapshot() if _void_auxiliary != null else {}


func accept_void_damage_receipt(fact: Dictionary) -> Dictionary:
	return _void_auxiliary.accept_damage_receipt(fact) if _void_auxiliary != null else _failure("void_auxiliary")


func accept_void_pickup_receipt(fact: Dictionary) -> Dictionary:
	return _void_auxiliary.consume_pickup(fact) if _void_auxiliary != null else _failure("void_auxiliary")


func void_burn_damage_requests(frame: int) -> Array[Dictionary]:
	return _void_auxiliary.burn_damage_requests(frame) if _void_auxiliary != null else []


func void_target_modifiers(target_id: String) -> Dictionary:
	return _void_auxiliary.target_modifiers(target_id) if _void_auxiliary != null else {}


func void_action_for_generation(generation: int) -> String:
	return _void_auxiliary.action_for_generation(generation) if _void_auxiliary != null else ""


func accept_void_arena_damage(fact: Dictionary) -> Dictionary:
	if _void_arena == null or _state.terminal:
		return _failure("void_arena_unavailable")
	var result: Dictionary = _void_arena.accept_damage_fact(fact)
	if not result.ok:
		return result
	result["retired_generations"] = []
	if result.interrupt_denial and _action.snapshot().action_id in ["voidking_existence_denial", "voidking_enrage_zero"] and _action.snapshot().phase in ["WARNING", "ACTIVE"]:
		result.retired_generations = _action.cancel(&"plane_core_interrupt").retired_generations
		_state.mechanism_state.delay_remaining_frames = 0
	_conversion.synchronize_tail(_character_tail_must_wait())
	return result


func void_player_heal_pending() -> bool:
	return _void_arena != null and _void_arena.player_heal_pending()


func accept_void_player_heal(run_id: String, player_source_id: String, frame: int, maximum_hp: float, amount: float, alive: bool) -> bool:
	return _void_arena != null and _void_arena.accept_player_heal(run_id, player_source_id, frame, maximum_hp, amount, alive).ok


func arena_snapshot() -> Dictionary:
	return _arena.snapshot() if _arena != null else _forge_arena.snapshot() if _forge_arena != null else {}


func forge_arena_snapshot() -> Dictionary:
	return _forge_arena.snapshot() if _forge_arena != null else {}


func observe_forge_target(target_id: String, position: Dictionary) -> Dictionary:
	return _forge_arena.observe_target(target_id, position) if _forge_arena != null else _failure("forge_arena")


func accept_forge_burn_fact(fact: Dictionary) -> Dictionary:
	return _forge_arena.accept_burn_fact(fact) if _forge_arena != null else _failure("forge_arena")


func forge_burn_damage_requests(frame: int) -> Array[Dictionary]:
	return _forge_arena.burn_damage_requests(frame) if _forge_arena != null else []


func forest_auxiliary_snapshot() -> Dictionary:
	return _forest_auxiliary.snapshot() if _forest_auxiliary != null else {}


func forest_cage_requests(frame: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = _forest_auxiliary.cage_requests(frame) if _forest_auxiliary != null else []
	for request: Dictionary in result:
		request.hostile_source_id = str(_state.identity.hostile_source_id)
		request.run_id = str(_state.identity.run_id)
	return result


func accept_forest_auxiliary_damage(fact: Dictionary) -> Dictionary:
	if _forest_auxiliary == null:
		return _failure("forest_unavailable")
	var result: Dictionary = _forest_auxiliary.accept_damage_fact(fact)
	if result.ok and result.cancelled_seed_generations.has(_action.snapshot().geometry_generations[0] if not _action.snapshot().geometry_generations.is_empty() else 0):
		result["retired_generations"] = cancel_action(&"marked_sac_destroyed").retired_generations
	return result


func accept_forest_flower(id: String, target_id: String, frame: int, amount: float) -> bool:
	return _forest_auxiliary != null and _forest_auxiliary.consume_flower(id, target_id, frame, amount).ok


func accept_forest_cage(request: Dictionary) -> bool:
	if _forest_auxiliary == null or _state.terminal or request.get("action_id") != "matriarch_void_cage" or request.get("runtime_frame") != _state.runtime_frame or request.get("attack_generation") != _action.snapshot().geometry_generations[0] or request.get("geometry") != _action.snapshot().committed_geometry:
		return false
	var geometry: Array = []
	for fact: Dictionary in request.geometry:
		geometry.append({"origin": fact.origin.duplicate(true), "aim_direction": fact.aim_direction.duplicate(true), "length": float(fact.length), "radius": float(fact.radius)})
	var difficulty: float = float(_definition.get("difficulty", {}).get("damage_multiplier", 1.0))
	return _forest_auxiliary.spawn_cage(int(request.attack_generation), int(request.runtime_frame), geometry, difficulty * daily_outgoing_multiplier() * (float(_definition.enrage.damage_multiplier) if _state.mechanism_state.action_enraged else 1.0)).ok


func forest_drain_allowance(generation: int, actual_loss: float) -> float:
	return _forest_auxiliary.drain_allowance(generation, actual_loss) if _forest_auxiliary != null else 0.0


func accept_forest_drain(id: String, generation: int, index: int, frame: int, loss: float, healed: float) -> bool:
	return _forest_auxiliary != null and _forest_auxiliary.accept_drain_receipt(id, generation, index, frame, loss, healed).ok


func accept_arena_damage_fact(value: Dictionary) -> Dictionary:
	if _forge_arena != null:
		return _forge_arena.accept_damage_fact(value) if not _state.terminal else _failure("arena_unavailable")
	if _arena == null or _state.terminal:
		return _failure("arena_unavailable")
	var result: Dictionary = _arena.accept_damage_fact(value)
	if result.ok:
		if _definition.id == "forest_heart" and result.broken and _arena.sweep_root_id(_action.snapshot()) == value.construct_id:
			result["retired_generations"] = _action.cancel(&"selected_root_destroyed").retired_generations
			_state.mechanism_state.delay_remaining_frames = 0
		_conversion.synchronize_tail(_character_tail_must_wait())
	return result


func accept_arena_wall_request(request: Dictionary, bounds: Dictionary) -> Dictionary:
	var action: Dictionary = _action.snapshot()
	if _arena == null or _state.terminal or action.phase != "ACTIVE" or action.action_id != "guardian_wall" or action.geometry_generations.is_empty() or request.get("attack_generation") != action.geometry_generations[0] or request.get("geometry") != action.committed_geometry:
		return _failure("wall_action")
	return _arena.accept_wall_request(request, bounds)


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
	if _time_response != null:
		if value.get("schema_version") == 10:
			return value.duplicate(true) if can_restore_snapshot(value) else {}
		if value.get("schema_version") not in [1, 9] or not Contract.exact_fields(value, STATE_FIELDS + (["time_response"] if value.schema_version == 9 else [])) or typeof(value.get("runtime_frame")) != TYPE_INT or typeof(value.get("terminal")) != TYPE_BOOL:
			return {}
		var upgraded := value.duplicate(true)
		upgraded.schema_version = 10
		if value.schema_version == 1:
			upgraded["time_response"] = _time_response.initial_at_frame(int(value.runtime_frame), bool(value.terminal))
		upgraded["time_auxiliary"] = _time_auxiliary.initial_at_frame(int(value.runtime_frame), bool(value.terminal))
		return upgraded if can_restore_snapshot(upgraded) else {}
	if _forge_arena != null:
		if value.get("schema_version") == 6:
			return value.duplicate(true) if can_restore_snapshot(value) else {}
		if value.get("schema_version") != 1 or not Contract.exact_fields(value, STATE_FIELDS) or not value.get("mechanism_state") is Dictionary or not Contract.integer_in_range(value.mechanism_state.get("phase_index"), 0, 2) or not Contract.integer_in_range(value.get("runtime_frame"), int(_state.identity.runtime_frame), Controls.MAX_COUNTER - Contract.MAX_FRAME) or typeof(value.get("terminal")) != TYPE_BOOL:
			return {}
		var upgraded := value.duplicate(true)
		upgraded.schema_version = 6
		upgraded["forge_arena_state"] = _forge_arena.initial_at_frame(int(value.runtime_frame), bool(value.terminal), int(value.mechanism_state.phase_index))
		return upgraded if can_restore_snapshot(upgraded) else {}
	if _void_arena != null:
		if value.get("schema_version") == 8:
			return value.duplicate(true) if can_restore_snapshot(value) else {}
		var historical_fields := STATE_FIELDS + (["void_arena_state", "void_auxiliary"] if value.get("schema_version") == 7 else ["void_arena_state"] if value.get("schema_version") == 5 else [])
		if value.get("schema_version") not in [1, 5, 7] or not Contract.exact_fields(value, historical_fields) or not value.get("mechanism_state") is Dictionary or not Contract.integer_in_range(value.mechanism_state.get("phase_index"), 0, 2) or not Contract.integer_in_range(value.get("runtime_frame"), int(_state.identity.runtime_frame), VoidArena.MAX_FRAME) or typeof(value.get("terminal")) != TYPE_BOOL:
			return {}
		var upgraded := value.duplicate(true)
		upgraded.schema_version = 8
		upgraded["void_half_index"] = 0
		if value.schema_version == 1:
			upgraded["void_arena_state"] = _void_arena.initial_at_frame(int(value.runtime_frame), bool(value.terminal), int(value.mechanism_state.phase_index))
		if value.schema_version != 7:
			upgraded["void_auxiliary"] = _void_auxiliary.initial_at_frame(int(value.runtime_frame), bool(value.terminal), int(value.mechanism_state.phase_index))
		return upgraded if can_restore_snapshot(upgraded) else {}
	if _arena == null:
		return value.duplicate(true) if can_restore_snapshot(value) else {}
	if _definition.id == "forest_heart":
		return _normalize_forest_native_snapshot(value)
	if value.get("schema_version") == 2:
		if not value.get("arena_state") is Dictionary:
			return {}
		var normalized := value.duplicate(true)
		normalized.arena_state = _arena.normalize_snapshot(value.arena_state)
		return normalized if can_restore_snapshot(normalized) else {}
	if value.get("schema_version") != 1 or not Contract.exact_fields(value, STATE_FIELDS) or typeof(value.get("runtime_frame")) != TYPE_INT or typeof(value.get("terminal")) != TYPE_BOOL:
		return {}
	var normalized := value.duplicate(true)
	normalized.schema_version = 2
	if _definition.id == "forest_heart":
		if not value.get("mechanism_state") is Dictionary or not value.mechanism_state.get("phase_index") is int:
			return {}
		normalized.arena_state = _arena.initial_at_frame(int(value.runtime_frame), bool(value.terminal), int(value.mechanism_state.phase_index))
	else:
		normalized.arena_state = _arena.initial_at_frame(int(value.runtime_frame), bool(value.terminal))
	return normalized if can_restore_snapshot(normalized) else {}


func _normalize_forest_native_snapshot(value: Dictionary) -> Dictionary:
	if value.get("schema_version") == 4:
		return value.duplicate(true) if can_restore_snapshot(value) else {}
	if value.get("schema_version") == 3 and Contract.exact_fields(value, STATE_FIELDS + ["arena_state"]):
		var upgraded := value.duplicate(true)
		upgraded.schema_version = 4
		upgraded.action = _normalize_forest_action(upgraded)
		upgraded["forest_auxiliary"] = _forest_auxiliary.initial_at_frame(int(value.runtime_frame), bool(value.terminal), upgraded.action)
		return upgraded if can_restore_snapshot(upgraded) else {}
	if typeof(value.get("schema_version")) != TYPE_INT or value.get("schema_version") not in [1, 2] or not Contract.exact_fields(value, STATE_FIELDS + (["arena_state"] if value.schema_version == 2 else [])) or not value.get("mechanism_state") is Dictionary or not value.mechanism_state.get("phase_index") is int or not value.get("action") is Dictionary or typeof(value.get("runtime_frame")) != TYPE_INT or typeof(value.get("terminal")) != TYPE_BOOL:
		return {}
	var normalized := value.duplicate(true)
	normalized.schema_version = 4
	normalized.action = _normalize_forest_action(normalized)
	normalized["forest_auxiliary"] = _forest_auxiliary.initial_at_frame(int(value.runtime_frame), bool(value.terminal), normalized.action)
	if value.schema_version == 2:
		if not value.arena_state is Dictionary or value.arena_state.get("schema_version") != 1:
			return {}
		normalized.arena_state = _arena.normalize_snapshot(value.arena_state, value.action)
	else:
		normalized.arena_state = _arena.initial_at_frame(int(value.runtime_frame), bool(value.terminal), int(value.mechanism_state.phase_index), value.action)
	return normalized if can_restore_snapshot(normalized) else {}


func _normalize_forest_action(value: Dictionary) -> Dictionary:
	if not value.get("mechanism_state") is Dictionary or not value.get("action") is Dictionary or not Contract.integer_in_range(value.mechanism_state.get("action_phase_index"), 0, _definition.phases.size() - 1) or typeof(value.mechanism_state.get("action_enraged")) != TYPE_BOOL:
		return {}
	var action := _make_action(int(value.mechanism_state.action_phase_index), bool(value.mechanism_state.action_enraged))
	if action.can_restore_snapshot(value.action):
		return value.action.duplicate(true)
	var historical_actions := _actions_for_regime(int(value.mechanism_state.action_phase_index), bool(value.mechanism_state.action_enraged))
	for row: Dictionary in historical_actions:
		if row.id == "matriarch_void_cage":
			for canonical: Dictionary in _definition.actions:
				if canonical.id == row.id:
					row.geometry = canonical.geometry.duplicate(true)
	var identity: Dictionary = _state.identity.duplicate(true)
	identity.erase("seed")
	var historical := Action.new()
	if not historical.configure({"id": _definition.id, "actor_kind": "boss", "actions": historical_actions}, identity).ok or not historical.can_restore_snapshot(value.action):
		return {}
	var result: Dictionary = value.action.duplicate(true)
	result.definition_digest = action.snapshot().definition_digest
	return result if action.can_restore_snapshot(result) else {}


func can_restore_native_snapshot(value: Dictionary) -> bool:
	return can_restore_snapshot(value) and (_arena == null or _arena.can_restore_snapshot(value.arena_state, true)) and (_forest_auxiliary == null or _forest_auxiliary.can_restore_snapshot(value.forest_auxiliary, true)) and (_void_arena == null or _void_arena.can_restore_snapshot(value.void_arena_state, true)) and (_void_auxiliary == null or _void_auxiliary.can_restore_snapshot(value.void_auxiliary, true)) and (_forge_arena == null or _forge_arena.can_restore_snapshot(value.forge_arena_state, true))


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty():
		return false
	var context := _snapshot_validation_context()
	var encoded := var_to_bytes(value)
	_snapshot_validation_cache_mutex.lock()
	for entry: Dictionary in _snapshot_validation_cache:
		if entry.context == context and entry.snapshot == encoded:
			_snapshot_validation_cache_mutex.unlock()
			return true
	_snapshot_validation_cache_mutex.unlock()
	if not _can_restore_snapshot_uncached(value):
		return false
	_snapshot_validation_cache_mutex.lock()
	for entry: Dictionary in _snapshot_validation_cache:
		if entry.context == context and entry.snapshot == encoded:
			_snapshot_validation_cache_mutex.unlock()
			return true
	if _snapshot_validation_cache.size() == MAX_SNAPSHOT_VALIDATION_CACHE:
		_snapshot_validation_cache.pop_front()
	_snapshot_validation_cache.append({"context": context, "snapshot": encoded})
	_snapshot_validation_cache_mutex.unlock()
	return true


func _clear_snapshot_validation_cache() -> void:
	_snapshot_validation_cache_mutex.lock()
	_snapshot_validation_cache.clear()
	_snapshot_validation_cache_mutex.unlock()


func _snapshot_validation_context() -> PackedByteArray:
	# Historical validity depends on configured authority, not the current frame.
	var context: Array = [_definition, _state.get("definition_digest"), _state.get("identity"), _arena_origin, _arena_trunk_origin]
	for authority: RefCounted in [_control, _conversion, _time_response, _time_auxiliary]:
		if authority == null:
			context.append(null)
		else:
			var state: Dictionary = authority.get("_state")
			context.append([state.is_empty(), state.get("identity"), state.get("definition_digest")])
	if _time_response != null:
		context.append(_time_response.get("_mechanisms"))
	for arena: RefCounted in [_arena, _forest_auxiliary, _void_arena, _void_auxiliary, _forge_arena]:
		if arena == null:
			context.append(null)
		else:
			var state: Dictionary = arena.get("_state")
			context.append([arena.get("_initial"), state.get("arena_origin")])
			if arena in [_void_arena, _void_auxiliary, _forge_arena]:
				context.append(arena.get("_definition"))
			if arena == _arena and _definition.id == "ruin_king":
				var ids: Array = []
				for cover: Dictionary in state.get("covers", []):
					ids.append(cover.get("id"))
				context.append(ids)
	return var_to_bytes(context)


func _can_restore_snapshot_uncached(value: Dictionary) -> bool:
	var fields: Array = STATE_FIELDS + (["arena_state"] if _arena != null else []) + (["forest_auxiliary"] if _forest_auxiliary != null else []) + (["void_arena_state", "void_auxiliary", "void_half_index"] if _void_arena != null else []) + (["forge_arena_state"] if _forge_arena != null else []) + (["time_response", "time_auxiliary"] if _time_response != null else [])
	if _state.is_empty() or not Contract.exact_fields(value, fields) or typeof(value.schema_version) != TYPE_INT or value.schema_version != (10 if _time_response != null else 6 if _forge_arena != null else 8 if _void_arena != null else 4 if _definition.id == "forest_heart" else 2 if _arena != null else 1) or value.definition_digest != _state.definition_digest or value.identity != _state.identity or not Contract.integer_in_range(value.runtime_frame, int(_state.identity.runtime_frame), Controls.MAX_COUNTER - Contract.MAX_FRAME) or typeof(value.terminal) != TYPE_BOOL:
		return false
	if _time_response != null and (not value.time_response is Dictionary or not _time_response.can_restore_snapshot(value.time_response) or value.time_response.runtime_frame != value.runtime_frame or value.time_response.terminal != value.terminal):
		return false
	if _time_auxiliary != null and (not value.time_auxiliary is Dictionary or not _time_auxiliary.can_restore_snapshot(value.time_auxiliary) or value.time_auxiliary.runtime_frame != value.runtime_frame or value.time_auxiliary.terminal != value.terminal):
		return false
	if _forest_auxiliary != null and (not value.forest_auxiliary is Dictionary or not _forest_auxiliary.can_restore_snapshot(value.forest_auxiliary) or value.forest_auxiliary.runtime_frame != value.runtime_frame or value.forest_auxiliary.terminal != value.terminal):
		return false
	if _arena != null and (not value.arena_state is Dictionary or not _arena.can_restore_snapshot(value.arena_state) or value.arena_state.runtime_frame != value.runtime_frame or value.arena_state.terminal != value.terminal):
		return false
	if _void_arena != null and (not value.void_arena_state is Dictionary or not _void_arena.can_restore_snapshot(value.void_arena_state) or value.void_arena_state.runtime_frame != value.runtime_frame or value.void_arena_state.terminal != value.terminal):
		return false
	if _void_auxiliary != null and (not value.void_auxiliary is Dictionary or not _void_auxiliary.can_restore_snapshot(value.void_auxiliary) or value.void_auxiliary.runtime_frame != value.runtime_frame or value.void_auxiliary.terminal != value.terminal):
		return false
	if _forge_arena != null and (not value.forge_arena_state is Dictionary or not _forge_arena.can_restore_snapshot(value.forge_arena_state) or value.forge_arena_state.runtime_frame != value.runtime_frame or value.forge_arena_state.terminal != value.terminal):
		return false
	if not value.mechanism_state is Dictionary or not Contract.exact_fields(value.mechanism_state, MECHANISM_FIELDS) or not value.action is Dictionary or not value.control is Dictionary or not value.conversion is Dictionary or not _conversion.can_restore_snapshot(value.conversion):
		return false
	if _arena != null and _definition.id == "ruin_king":
		for claim: Dictionary in value.arena_state.wall_claims:
			if claim.attack_generation < int(_state.identity.next_generation_floor) or not Contract.integer_in_range(value.action.get("next_generation_floor"), 1, Controls.MAX_COUNTER) or claim.attack_generation + 1 >= int(value.action.next_generation_floor):
				return false
	var mechanism: Dictionary = value.mechanism_state
	if _void_arena != null and value.void_arena_state.phase_index != mechanism.phase_index:
		return false
	if _void_auxiliary != null:
		if value.void_auxiliary.phase_index != mechanism.phase_index:
			return false
		for cast: Dictionary in value.void_auxiliary.casts:
			for geometry: Dictionary in cast.geometry:
				if geometry.attack_generation >= value.action.get("next_generation_floor", -1):
					return false
		for landing: Dictionary in value.void_auxiliary.landings:
			if landing.followup_generation >= value.action.get("next_generation_floor", -1):
				return false
	if _forge_arena != null and value.forge_arena_state.phase_index != mechanism.phase_index:
		return false
	if _definition.id == "forest_heart" and (value.arena_state.phase_retirement.is_empty() != (mechanism.phase_index == 0)):
		return false
	if not Contract.integer_in_range(mechanism.phase_index, 0, _definition.phases.size() - 1) or not Contract.integer_in_range(mechanism.action_phase_index, 0, int(mechanism.phase_index)) or not Contract.number_in_range(mechanism.hp_current, 0.0, _definition.max_hp) or not Contract.number_in_range(mechanism.minimum_hp, 0.0, float(mechanism.hp_current)) or int(mechanism.phase_index) != _phase_for_hp(float(mechanism.minimum_hp)):
		return false
	if typeof(mechanism.enraged) != TYPE_BOOL or mechanism.enraged != (int(value.runtime_frame) - int(value.identity.runtime_frame) >= int(_definition.enrage.threshold_frames)) or typeof(mechanism.action_enraged) != TYPE_BOOL or mechanism.action_enraged and not mechanism.enraged:
		return false
	var recovery_bound := int(_definition.mechanisms.counter_accelerate_exposure_frames) if _time_response != null else 60
	if not Contract.integer_in_range(mechanism.phase_transition_until_frame, int(value.identity.runtime_frame) - 1, int(value.runtime_frame) + recovery_bound) or not Contract.integer_in_range(mechanism.exposure_through_frame, int(value.identity.runtime_frame) - 1, int(value.runtime_frame) + 120) or not Contract.integer_in_range(mechanism.delay_remaining_frames, 0, Contract.MAX_FRAME) or not Contract.integer_in_range(mechanism.consecutive_actions, 0, 3):
		return false
	if typeof(mechanism.last_action_id) != TYPE_STRING or not mechanism.last_action_id.is_empty() and _action_definition(mechanism.last_action_id).is_empty() or (mechanism.last_action_id.is_empty() != (int(mechanism.consecutive_actions) == 0)):
		return false
	if not mechanism.last_action_id.is_empty() and int(mechanism.consecutive_actions) > int(_action_definition(mechanism.last_action_id).max_consecutive):
		return false
	for field: String in ["damage_claims", "health_claims", "stop_claims"]:
		var capacity := MAX_DAMAGE_CLAIMS if field == "damage_claims" else MAX_CLAIMS
		if not mechanism[field] is Array or mechanism[field].size() > capacity:
			return false
		var seen: Dictionary = {}
		for id: Variant in mechanism[field]:
			if typeof(id) != TYPE_STRING or id.is_empty() or id.length() > (64 if field == "stop_claims" else 128) or seen.has(id):
				return false
			seen[id] = true
	var action := _action_for_snapshot(value)
	if action == null or not action.can_restore_snapshot(value.action) or not _control.can_restore_snapshot(value.control):
		return false
	if _time_response != null and not value.time_response.active.is_empty() and value.time_response.active.attack_generation >= int(value.action.next_generation_floor):
		return false
	if _time_response != null and value.action.action_id in Definition.RESPONSE_IDS and value.action.definition_digest == _make_action(int(mechanism.action_phase_index), mechanism.action_enraged).snapshot().definition_digest:
		var active: Dictionary = value.time_response.active
		if active.is_empty() or value.action.action_id != "traitor.counter_" + str(active.receipt.ability_id) or value.action.commit_frame != active.start_frame or value.action.geometry_generations[0] != active.attack_generation or active.cancelled or active.shattered:
			return false
	if _time_response != null and value.action.action_id == "traitor.counter_rewind" and Action._locks_time_receipt_facing(_action_definition("traitor.counter_rewind")):
		var active: Dictionary = value.time_response.active
		if active.is_empty() or active.receipt.ability_id != "rewind" or value.action.commit_frame != active.start_frame or value.action.geometry_generations[0] != active.attack_generation or value.action.committed_target != Action._quantized_point(_vector(active.receipt.endpoint)) or not _vector(value.action.committed_aim).is_equal_approx(_vector(active.receipt.facing)):
			return false
	if _void_arena != null:
		if not Contract.integer_in_range(value.void_half_index, 0, int(value.action.decision_index)):
			return false
		var selected: Dictionary = _action_definition(str(value.action.action_id))
		if value.action.phase != "IDLE" and VoidHalf.current_action(selected) and value.action.definition_digest == _make_action(int(mechanism.action_phase_index), mechanism.action_enraged).snapshot().definition_digest:
			if not VoidHalf.valid_geometry(value.action.committed_geometry, str(value.action.action_id), _arena_origin):
				return false
			if value.action.action_id == "voidking_enrage_zero" and (int(value.void_half_index) == 0 or (float(value.action.committed_aim.x) < 0.0) != (int(value.void_half_index) % 2 == 0)):
				return false
	if _definition.id == "forest_heart":
		if value.arena_state.historical_sweep_generation >= value.action.next_generation_floor or not _arena.can_restore_sweep_action(value.action, value.arena_state, _arena_trunk_origin):
			return false
		for claim: Dictionary in value.arena_state.sweep_claims:
			if claim.attack_generation >= value.action.next_generation_floor:
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
		var root_exposed: bool = _definition.id == "forest_heart" and not value.terminal and int(value.runtime_frame) <= int(value.arena_state.exposure_through_frame)
		var core_exposed: bool = _void_arena != null and not value.terminal and int(value.runtime_frame) <= int(value.void_arena_state.exposure_through_frame)
		var tentacle_exposed: bool = _void_auxiliary != null and not value.terminal and int(value.runtime_frame) <= int(value.void_auxiliary.exposure_through_frame)
		var must_wait: bool = value.action.phase == "RECOVERY" or int(value.runtime_frame) <= int(mechanism.exposure_through_frame) or root_exposed or core_exposed or tentacle_exposed
		if (value.conversion.claims[0].state == "pending") != must_wait:
			return false
	return not value.terminal or value.action.phase == "IDLE" and int(mechanism.delay_remaining_frames) == 0 and value.conversion.claims.is_empty() and value.conversion.weapon_sources.is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	var action := _action_for_snapshot(value)
	if not action.restore_snapshot(value.action) or not _control.restore_snapshot(value.control) or not _conversion.restore_snapshot(value.conversion):
		return false
	if _arena != null and not _arena.restore_snapshot(value.arena_state):
		return false
	if _forest_auxiliary != null and not _forest_auxiliary.restore_snapshot(value.forest_auxiliary):
		return false
	if _void_arena != null and not _void_arena.restore_snapshot(value.void_arena_state):
		return false
	if _void_auxiliary != null and not _void_auxiliary.restore_snapshot(value.void_auxiliary):
		return false
	if _forge_arena != null and not _forge_arena.restore_snapshot(value.forge_arena_state):
		return false
	if _time_response != null and not _time_response.restore_snapshot(value.time_response):
		return false
	if _time_auxiliary != null and not _time_auxiliary.restore_snapshot(value.time_auxiliary):
		return false
	_action = action
	_legacy_void_action = _void_arena != null and value.action.definition_digest != _make_action(int(value.mechanism_state.action_phase_index), bool(value.mechanism_state.action_enraged)).snapshot().definition_digest
	_legacy_time_action = _time_response != null and value.action.definition_digest != _make_action(int(value.mechanism_state.action_phase_index), bool(value.mechanism_state.action_enraged)).snapshot().definition_digest
	_state = value.duplicate(true)
	_state.erase("action")
	_state.erase("control")
	_state.erase("conversion")
	_state.erase("arena_state")
	_state.erase("forest_auxiliary")
	_state.erase("void_arena_state")
	_state.erase("void_auxiliary")
	_state.erase("forge_arena_state")
	_state.erase("time_response")
	_state.erase("time_auxiliary")
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
	if _forest_auxiliary != null:
		_forest_auxiliary.retire()
	if _void_arena != null:
		_void_arena.retire()
	if _void_auxiliary != null:
		_void_auxiliary.retire()
	if _forge_arena != null:
		_forge_arena.retire()
	if _time_response != null:
		_time_response.retire()
	if _time_auxiliary != null:
		_time_auxiliary.retire()
	_state.mechanism_state.delay_remaining_frames = 0
	return result


func cancel_action(reason: StringName = &"interrupted") -> Dictionary:
	if _state.is_empty() or _state.terminal or reason == &"":
		return _failure("action_unavailable")
	_state.mechanism_state.delay_remaining_frames = 0
	_cancel_pending_rewind()
	_cancel_pending_forest_seed(int(_state.runtime_frame))
	var result: Dictionary = _action.cancel(reason)
	_conversion.synchronize_tail(_character_tail_must_wait())
	return result


func _cancel_pending_forest_seed(frame: int) -> void:
	if _forest_auxiliary == null or _action.snapshot().action_id != "matriarch_void_seed" or _action.snapshot().geometry_generations.is_empty():
		return
	var generation := int(_action.snapshot().geometry_generations[0])
	var state: Dictionary = _forest_auxiliary.snapshot()
	for seed: Dictionary in state.seeds:
		if seed.generation == generation and seed.burst_frame == -1 and seed.cancelled_frame == -1:
			_forest_auxiliary.cancel_seed(generation, maxi(frame, int(state.events.back().frame)))


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
	if _action.snapshot().phase != "IDLE" or not _legacy_void_action and not _legacy_time_action and int(mechanism.action_phase_index) == int(mechanism.phase_index) and mechanism.action_enraged == mechanism.enraged:
		return true
	var next := _make_action(int(mechanism.phase_index), mechanism.enraged)
	if next == null:
		return false
	var checkpoint: Dictionary = _action.snapshot()
	if int(mechanism.action_phase_index) == int(mechanism.phase_index) and mechanism.action_enraged == mechanism.enraged and checkpoint.definition_digest == next.snapshot().definition_digest:
		return true
	checkpoint.definition_digest = next.snapshot().definition_digest
	if not next.restore_snapshot(checkpoint):
		return false
	_action = next
	_legacy_void_action = false
	_legacy_time_action = false
	mechanism.action_phase_index = mechanism.phase_index
	mechanism.action_enraged = mechanism.enraged
	return true


func _make_action(phase_index: int, enraged: bool, room_half: bool = true, current_time_responses: bool = true) -> RefCounted:
	var identity: Dictionary = _state.identity.duplicate(true)
	identity.erase("seed")
	var result := Action.new()
	var actions := _actions_for_regime(phase_index, enraged, room_half, current_time_responses)
	return result if result.configure({"id": _definition.id, "actor_kind": "boss", "actions": actions}, identity).ok else null


func _action_for_snapshot(value: Dictionary) -> RefCounted:
	var current := _make_action(int(value.mechanism_state.action_phase_index), bool(value.mechanism_state.action_enraged))
	if current != null and current.can_restore_snapshot(value.action):
		return current
	if _void_arena != null:
		var historical := _make_action(int(value.mechanism_state.action_phase_index), bool(value.mechanism_state.action_enraged), false)
		if historical != null and historical.can_restore_snapshot(value.action):
			return historical
	if _time_response != null:
		var historical := _make_action(int(value.mechanism_state.action_phase_index), bool(value.mechanism_state.action_enraged), true, false)
		if historical != null and historical.can_restore_snapshot(value.action):
			return historical
	return null


func _actions_for_regime(phase_index: int, enraged: bool, room_half: bool = true, current_time_responses: bool = true) -> Array:
	var actions: Array = (_definition.actions + _definition.time_responses).duplicate(true)
	var overrides: Dictionary = _definition.mechanisms.phase_damage_overrides.get(_definition.phases[phase_index].id, {})
	for action: Dictionary in actions:
		if current_time_responses and _definition.id == "time_sovereign" and action.id in Definition.RESPONSE_IDS:
			action.cooldown_frames = int(_definition.mechanisms.response_shared_cooldown_p1_frames if phase_index == 0 else _definition.mechanisms.response_shared_cooldown_p2_frames)
			action.distance_max_px = 640.0
			if action.id == "traitor.counter_rewind":
				action.geometry = [{"shape": "target_circle", "origin_offset": {"x": -48.0, "y": 0.0}, "aim_offset_degrees": 0.0, "radius": 12.0, "length": 0.0}, {"shape": "target_circle", "origin_offset": {"x": 0.0, "y": 0.0}, "aim_offset_degrees": 0.0, "radius": 8.0, "length": 0.0}]
		if room_half and _definition.id == "void_throne" and action.id in VoidHalf.ACTION_IDS:
			action.geometry = VoidHalf.recipe(str(action.id))
		if action.id == "matriarch_void_cage":
			action.geometry = [{"shape": "line", "origin_offset": {"x": -24.0, "y": -24.0}, "aim_offset_degrees": 90.0, "radius": 5.0, "length": 48.0}, {"shape": "line", "origin_offset": {"x": 24.0, "y": -24.0}, "aim_offset_degrees": 90.0, "radius": 5.0, "length": 48.0}, {"shape": "line", "origin_offset": {"x": -24.0, "y": 24.0}, "aim_offset_degrees": 0.0, "radius": 5.0, "length": 16.0}]
		if enraged:
			action.cooldown_frames = ceili(int(action.cooldown_frames) * float(_definition.enrage.cooldown_multiplier))
		for hit: Dictionary in action.hit_schedule:
			hit.damage = float(overrides.get(action.id, hit.damage)) * (float(_definition.enrage.damage_multiplier) if enraged else 1.0)
	return actions


func _action_available(action_id: String) -> bool:
	var action := _action_definition(action_id)
	if _time_response != null and action_id in Definition.RESPONSE_IDS:
		var response: Dictionary = _time_response.pending_request(int(_state.runtime_frame))
		return not response.is_empty() and response.action_id == action_id
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
		var action_distance := distance
		if _definition.id == "forest_heart" and action.id == "matriarch_root_sweep":
			var selected: Dictionary = _arena.select_sweep_root(observations.target_position)
			if selected.is_empty():
				continue
			action_distance = _vector(selected.position).distance_to(_vector(observations.target_position))
		if _action_available(action.id) and int(current.cooldowns.get(action.id, 0)) <= frame and action_distance >= float(action.distance_min_px) and action_distance <= float(action.distance_max_px):
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
	return not _state.is_empty() and (_action.snapshot().phase == "RECOVERY" or int(_state.runtime_frame) <= int(_state.mechanism_state.exposure_through_frame) or _definition.id == "forest_heart" and _arena.is_exposed() or _void_arena != null and _void_arena.is_exposed() or _void_auxiliary != null and int(_state.runtime_frame) <= int(_void_auxiliary.snapshot().exposure_through_frame))


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
