class_name VoidAuxiliaryRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Action := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "arena_origin", "terminal", "phase_index", "casts", "burns", "statuses", "pickups", "landings", "exposure_through_frame", "events"]
const CAST_FIELDS := ["run_id", "owner_source_id", "action_id", "attack_generation", "runtime_frame", "geometry", "damage_multiplier"]
const DAMAGE_FIELDS := ["fact_id", "run_id", "owner_source_id", "attack_generation", "hit_index", "target_id", "runtime_frame", "actual_loss"]
const LANDING_FIELDS := ["run_id", "owner_source_id", "attack_generation", "runtime_frame", "position", "landed"]
const PICKUP_FIELDS := ["fact_id", "run_id", "owner_source_id", "pickup_id", "target_id", "runtime_frame", "energy_before", "energy_after", "maximum", "revision_before", "revision_after"]
const EVENT_FIELDS := {"cast": ["kind", "frame", "action_id", "generation", "geometry", "damage_multiplier"], "damage": ["kind", "frame", "fact_id", "generation", "hit_index", "target_id", "actual_loss"], "landing": ["kind", "frame", "generation", "position", "landed"], "followup": ["kind", "frame", "generation", "followup_generation"], "pickup": ["kind", "frame", "fact_id", "pickup_id", "target_id", "energy_before", "energy_after", "maximum", "revision_before", "revision_after"], "phase": ["kind", "frame", "phase_index"], "terminal": ["kind", "frame"]}
const MAX_FRAME := 2147447646
const MAX_EVENTS := 4096
var _definition: Dictionary = {}
var _state: Dictionary = {}
var _initial: Dictionary = {}


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	var parsed := Definition.new().configure_runtime_projection(definition)
	if not parsed.ok or definition.id != "void_throne" or not Contract.exact_fields(identity, ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]) or not _id(identity.run_id) or not _id(identity.hostile_source_id) or not Contract.integer_in_range(identity.runtime_frame, 0, MAX_FRAME) or not Contract.integer_in_range(identity.next_generation_floor, 1, MAX_FRAME) or not Contract.integer_in_range(identity.seed, -2147483648, 2147483647):
		return _failure("configuration")
	_definition = parsed.definition.duplicate(true)
	_state = {"schema_version": 1, "definition_digest": JSON.stringify(_definition, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "arena_origin": {"x": 0.0, "y": 0.0}, "terminal": false, "phase_index": 0, "casts": [], "burns": [], "statuses": [], "pickups": [], "landings": [], "exposure_through_frame": int(identity.runtime_frame) - 1, "events": []}
	_initial = snapshot()
	return {"ok": true}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func bind_origin(origin: Dictionary) -> bool:
	if _state.is_empty() or not Contract.valid_point(origin) or origin != _state.arena_origin and (not _state.events.is_empty() or _state.runtime_frame != _initial.runtime_frame):
		return false
	_state.arena_origin = origin.duplicate(true)
	_initial.arena_origin = origin.duplicate(true)
	return true


func reserve_cast(fact: Dictionary) -> Dictionary:
	if not _identity(fact) or not Contract.exact_fields(fact, CAST_FIELDS):
		return _failure("cast_identity")
	return _record({"kind": "cast", "frame": fact.runtime_frame, "action_id": fact.action_id, "generation": fact.attack_generation, "geometry": fact.geometry.duplicate(true), "damage_multiplier": fact.damage_multiplier})


func accept_damage_receipt(fact: Dictionary) -> Dictionary:
	if not _identity(fact) or not Contract.exact_fields(fact, DAMAGE_FIELDS):
		return _failure("damage_identity")
	return _record({"kind": "damage", "frame": fact.runtime_frame, "fact_id": fact.fact_id, "generation": fact.attack_generation, "hit_index": fact.hit_index, "target_id": fact.target_id, "actual_loss": fact.actual_loss})


func accept_landing_receipt(fact: Dictionary) -> Dictionary:
	if not _identity(fact) or not Contract.exact_fields(fact, LANDING_FIELDS):
		return _failure("landing_identity")
	return _record({"kind": "landing", "frame": fact.runtime_frame, "generation": fact.attack_generation, "position": fact.position.duplicate(true), "landed": fact.landed})


func accept_followup_receipt(generation: int, followup_generation: int, frame: int) -> Dictionary:
	return _record({"kind": "followup", "frame": frame, "generation": generation, "followup_generation": followup_generation})


func consume_pickup(fact: Dictionary) -> Dictionary:
	if not _identity(fact) or not Contract.exact_fields(fact, PICKUP_FIELDS):
		return _failure("pickup_identity")
	var event := fact.duplicate(true)
	event.erase("run_id")
	event.erase("owner_source_id")
	event.erase("runtime_frame")
	event["kind"] = "pickup"
	event["frame"] = fact.runtime_frame
	return _record(event)


func accept_phase(phase: int, frame: int) -> Dictionary:
	return _record({"kind": "phase", "frame": frame, "phase_index": phase})


func advance_frame(frame: int) -> bool:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame) + 1 or frame > MAX_FRAME:
		return false
	_state.runtime_frame = frame
	_refresh(_state)
	return true


func retire() -> void:
	if not _state.is_empty() and not _state.terminal:
		_record({"kind": "terminal", "frame": int(_state.runtime_frame)})


func action_for_generation(generation: int) -> String:
	var cast := _cast_for(_state, generation)
	return str(cast.action_id) if not cast.is_empty() else ""


func target_modifiers(target_id: String) -> Dictionary:
	var result := {}
	if _state.is_empty() or _state.terminal:
		return result
	for status: Dictionary in _state.statuses:
		if status.target_id == target_id:
			result[status.modifier] = minf(float(result.get(status.modifier, 1.0)), float(status.multiplier))
	return result


func active_pickups() -> Array:
	return [] if _state.is_empty() or _state.terminal else _state.pickups.filter(func(row: Dictionary): return not row.used and not row.retired and int(_state.runtime_frame) < int(row.through_frame)).duplicate(true)


func burn_damage_requests(frame: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame):
		return result
	for burn: Dictionary in _state.burns:
		var age := frame - int(burn.start_frame)
		if age > 0 and age % int(_definition.mechanisms.scepter_burn_tick_frames) == 0:
			result.append({"payload_id": "void-burn:" + JSON.stringify([_state.identity.hostile_source_id, burn.target_id, burn.attack_generation]).sha256_text().substr(0, 40), "hostile_source_id": str(_state.identity.hostile_source_id), "attack_generation": int(burn.attack_generation), "hit_index": age / int(_definition.mechanisms.scepter_burn_tick_frames), "target_id": burn.target_id, "runtime_frame": frame, "damage": float(_definition.mechanisms.scepter_burn_damage), "damage_type": "void"})
	return result


func mechanism_requests(frame: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame):
		return result
	for cast: Dictionary in _state.casts:
		if cast.retired or cast.action_id != "voidking_plane_tear" or frame != int(cast.spawn_frame) + int(_action(cast.action_id).active_frames):
			continue
		var geometry: Dictionary = cast.geometry[0]
		result.append({"kind": "void_tear_final", "hostile_source_id": str(_state.identity.hostile_source_id), "run_id": str(_state.identity.run_id), "attack_generation": int(cast.generation), "hit_index": 63, "runtime_frame": frame, "construct_id": "void-tear:%d" % int(cast.generation), "position": _point(_vector(geometry.origin) + _vector(geometry.aim_direction) * float(geometry.length)), "parameters": {"warning_frames": int(_definition.mechanisms.tear_final_warning_frames), "radius": float(_definition.mechanisms.tear_final_radius_px), "damage": float(_definition.mechanisms.tear_final_damage) * float(cast.damage_multiplier)}})
	return result


func step_followup_request(frame: int) -> Dictionary:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame):
		return {}
	for landing: Dictionary in _state.landings:
		if landing.landed and not landing.retired and landing.followup_generation == 0:
			return {"action_id": "voidking_scepter_strike", "step_generation": int(landing.generation), "position": landing.position.duplicate(true), "warning_frames": int(_definition.mechanisms.step_followup_warning_frames)}
	return {}


func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
	if _initial.is_empty() or not Contract.exact_fields(value, FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or value.identity != _initial.identity or value.definition_digest != _initial.definition_digest or value.arena_origin != _initial.arena_origin or not Contract.integer_in_range(value.runtime_frame, int(_initial.runtime_frame), MAX_FRAME) or not value.events is Array or value.events.size() > MAX_EVENTS:
		return false
	var replay := _initial.duplicate(true)
	var previous := int(_initial.runtime_frame)
	for candidate: Variant in value.events:
		if not candidate is Dictionary or not _valid_event(candidate) or candidate.frame < previous or candidate.frame > int(value.runtime_frame) + (0 if accepted_boundary else 1):
			return false
		replay.runtime_frame = mini(int(candidate.frame), int(value.runtime_frame))
		_refresh(replay)
		if not _apply(replay, candidate).ok:
			return false
		replay.events.append(candidate.duplicate(true))
		previous = int(candidate.frame)
	replay.runtime_frame = int(value.runtime_frame)
	_refresh(replay)
	return JSON.parse_string(JSON.stringify(replay)) == JSON.parse_string(JSON.stringify(value))


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


func initial_at_frame(frame: int, terminal: bool, phase: int) -> Dictionary:
	if _initial.is_empty() or frame < int(_initial.runtime_frame) or phase < 0 or phase > 2:
		return {}
	var result := _initial.duplicate(true)
	result.runtime_frame = frame
	if phase > 0:
		var event := {"kind": "phase", "frame": frame, "phase_index": phase}
		_apply(result, event)
		result.events.append(event)
	if terminal:
		var event := {"kind": "terminal", "frame": frame}
		_apply(result, event)
		result.events.append(event)
	return result if can_restore_snapshot(result, true) else {}


func _identity(fact: Dictionary) -> bool:
	return not _state.is_empty() and fact.get("run_id") == _state.identity.run_id and fact.get("owner_source_id") == _state.identity.hostile_source_id


func _record(event: Dictionary) -> Dictionary:
	if _state.is_empty() or not _valid_event(event) or event.frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or not _state.events.is_empty() and event.frame < _state.events.back().frame or _state.events.size() >= MAX_EVENTS:
		return _failure("event_boundary")
	var next := snapshot()
	var result := _apply(next, event)
	if not result.ok:
		return result
	next.events.append(event.duplicate(true))
	_state = next
	return result


func _apply(state: Dictionary, event: Dictionary) -> Dictionary:
	if state.terminal:
		return _failure("terminal_event")
	match event.kind:
		"cast":
			var action := _action(event.action_id)
			if action.is_empty() or not _generation(event.generation, state) or not _geometry(event.geometry, action, state, event.generation) or not Contract.number_in_range(event.damage_multiplier, 0.000001, 6.0) or state.casts.any(func(row: Dictionary): return row.geometry.any(func(fact: Dictionary): return event.generation <= int(fact.attack_generation) and int(event.generation) + event.geometry.size() > int(fact.attack_generation))):
				return _failure("cast_authority")
			state.casts.append({"action_id": str(event.action_id), "generation": int(event.generation), "spawn_frame": int(event.frame), "geometry": event.geometry.duplicate(true), "damage_multiplier": float(event.damage_multiplier), "phase_index": int(state.phase_index), "retired": false})
			if event.action_id == "voidking_shard_projection":
				var available: int = int(_definition.mechanisms.shard_pickup_count_cap) - state.pickups.filter(func(row: Dictionary): return not row.used and not row.retired and event.frame < row.through_frame).size()
				for slot: int in range(maxi(0, available)):
					var origin := _vector(event.geometry[0].origin)
					var position := origin + Vector2.RIGHT.rotated(float(slot) * PI * 0.5) * 56.0
					position.x = clampf(position.x, float(state.arena_origin.x) + 16.0, float(state.arena_origin.x) + 624.0)
					position.y = clampf(position.y, float(state.arena_origin.y) + 16.0, float(state.arena_origin.y) + 344.0)
					state.pickups.append({"id": "void-shard:%d:%d" % [int(event.generation), slot], "generation": int(event.generation), "slot": slot, "position": _point(position), "radius_px": 8.0, "spawn_frame": int(event.frame), "through_frame": int(event.frame) + int(_definition.mechanisms.shard_pickup_lifetime_frames), "used": false, "retired": false, "target_id": "", "used_frame": -1, "energy_amount": 0.0})
			if event.action_id == "voidking_tentacle_lash":
				state.exposure_through_frame = maxi(int(state.exposure_through_frame), int(event.frame) + int(_definition.mechanisms.tentacle_exposure_frames) - 1)
		"damage":
			var cast := _cast_for(state, event.generation)
			if cast.is_empty() or cast.retired or not _id(event.fact_id) or not _id(event.target_id) or not Contract.integer_in_range(event.hit_index, 0, 63) or not Contract.number_in_range(event.actual_loss, 0.0, 1000000.0) or state.events.any(func(row: Dictionary): return row.get("fact_id", "") == event.fact_id or row.kind == "damage" and row.generation == event.generation and row.hit_index == event.hit_index and row.target_id == event.target_id):
				return _failure("damage_receipt")
			if event.frame < int(cast.spawn_frame) or event.frame > int(cast.spawn_frame) + _damage_lifetime(_action(cast.action_id)):
				return _failure("damage_lifetime")
			if event.actual_loss > 0.0:
				match cast.action_id:
					"voidking_scepter_strike": state.burns.append({"target_id": str(event.target_id), "attack_generation": int(event.generation), "start_frame": int(event.frame), "through_frame": int(event.frame) + int(_definition.mechanisms.scepter_burn_frames)})
					"voidking_void_bolt": _status(state, event, "movement_multiplier", float(_definition.mechanisms.bolt_slow_multiplier), int(_definition.mechanisms.bolt_slow_frames))
					"voidking_void_grasp": _status(state, event, "movement_multiplier", float(_definition.mechanisms.grasp_slow_multiplier), int(_definition.mechanisms.grasp_slow_frames))
					"voidking_devour": _status(state, event, "attack_multiplier", float(_definition.mechanisms.devour_damage_output_multiplier), int(_definition.mechanisms.devour_debuff_frames))
		"landing":
			var cast := _cast_for(state, event.generation)
			if cast.is_empty() or cast.retired or cast.action_id != "voidking_void_step" or typeof(event.landed) != TYPE_BOOL or not Contract.valid_point(event.position) or event.frame != cast.spawn_frame or event.landed and event.position != cast.geometry[0].origin or state.landings.any(func(row: Dictionary): return row.generation == event.generation):
				return _failure("landing_receipt")
			state.landings.append({"generation": int(event.generation), "frame": int(event.frame), "position": event.position.duplicate(true), "landed": bool(event.landed), "retired": false, "followup_generation": 0, "followup_frame": -1})
		"followup":
			if not _generation(event.followup_generation, state) or event.followup_generation <= event.generation:
				return _failure("followup_generation")
			var found := false
			for landing: Dictionary in state.landings:
				if landing.generation == event.generation and landing.landed and not landing.retired and landing.followup_generation == 0 and event.frame >= int(landing.frame):
					landing.followup_generation = int(event.followup_generation)
					landing.followup_frame = int(event.frame)
					found = true
			if not found:
				return _failure("followup_receipt")
		"pickup":
			if not _id(event.fact_id) or not _id(event.target_id) or not Contract.number_in_range(event.maximum, 1.0, 1000000.0) or not Contract.number_in_range(event.energy_before, 0.0, event.maximum) or not Contract.number_in_range(event.energy_after, event.energy_before, event.maximum) or not is_equal_approx(float(event.energy_after), minf(float(event.maximum), float(event.energy_before) + float(_definition.mechanisms.shard_pickup_energy))) or not Contract.integer_in_range(event.revision_before, 1, MAX_FRAME) or event.revision_after != int(event.revision_before) + (1 if event.energy_after > event.energy_before else 0) or state.events.any(func(row: Dictionary): return row.get("fact_id", "") == event.fact_id):
				return _failure("pickup_resource_receipt")
			var found := false
			for pickup: Dictionary in state.pickups:
				if pickup.id == event.pickup_id and not pickup.used and not pickup.retired and event.frame < pickup.through_frame:
					pickup.used = true
					pickup.target_id = str(event.target_id)
					pickup.used_frame = int(event.frame)
					pickup.energy_amount = float(event.energy_after) - float(event.energy_before)
					found = true
			if not found:
				return _failure("inactive_pickup")
		"phase":
			if not Contract.integer_in_range(event.phase_index, int(state.phase_index) + 1, 2):
				return _failure("phase_order")
			state.phase_index = int(event.phase_index)
			_clear_finite(state, int(event.frame))
		"terminal":
			state.terminal = true
			_clear_finite(state, int(event.frame))
		_: return _failure("event_kind")
	return {"ok": true}


func _status(state: Dictionary, event: Dictionary, modifier: String, multiplier: float, duration: int) -> void:
	state.statuses.append({"target_id": str(event.target_id), "attack_generation": int(event.generation), "modifier": modifier, "multiplier": multiplier, "start_frame": int(event.frame), "through_frame": int(event.frame) + duration})


func _geometry(value: Variant, action: Dictionary, state: Dictionary, generation: int) -> bool:
	if not value is Array or value.size() != action.geometry.size():
		return false
	for index: int in range(value.size()):
		var row: Variant = value[index]
		var recipe: Dictionary = action.geometry[index]
		if not row is Dictionary or Action.native_threat_fact(row).is_empty() or row.hostile_source_id != state.identity.hostile_source_id or row.attack_generation != generation + index or row.shape != recipe.shape or row.radius != recipe.radius or row.length != recipe.length or not is_equal_approx(_vector(row.aim_direction).length(), 1.0):
			return false
	return true


func _action(id: Variant) -> Dictionary:
	for row: Dictionary in _definition.actions:
		if row.id == id:
			return row
	return {}


static func _cast_for(state: Dictionary, generation: int) -> Dictionary:
	for cast: Dictionary in state.get("casts", []):
		for geometry: Dictionary in cast.geometry:
			if geometry.attack_generation == generation:
				return cast
	return {}


static func _damage_lifetime(action: Dictionary) -> int:
	return int(action.parameters.lifetime_frames) if action.handler_id == "projectile_volley" else int(action.active_frames) - 1


static func _refresh(state: Dictionary) -> void:
	state.burns = state.burns.filter(func(row: Dictionary): return row.through_frame >= state.runtime_frame)
	state.statuses = state.statuses.filter(func(row: Dictionary): return row.through_frame > state.runtime_frame)


static func _clear_finite(state: Dictionary, frame: int) -> void:
	state.burns = []
	state.statuses = []
	state.exposure_through_frame = frame - 1
	for row: Dictionary in state.casts + state.pickups + state.landings:
		row.retired = true


static func _valid_event(event: Dictionary) -> bool:
	return typeof(event.get("kind")) == TYPE_STRING and EVENT_FIELDS.has(event.kind) and Contract.exact_fields(event, EVENT_FIELDS[event.kind]) and typeof(event.frame) == TYPE_INT and Contract.integer_in_range(event.frame, 0, MAX_FRAME)


static func _generation(value: Variant, state: Dictionary) -> bool:
	return typeof(value) == TYPE_INT and Contract.integer_in_range(value, int(state.identity.next_generation_floor), MAX_FRAME)


static func _id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 128


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))


static func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"VOID_AUXILIARY_INVALID", "field": field}
