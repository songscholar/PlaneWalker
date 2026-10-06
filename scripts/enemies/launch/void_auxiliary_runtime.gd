class_name VoidAuxiliaryRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Action := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const VoidHalf := preload("res://scripts/enemies/launch/void_half_arena_geometry.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "arena_origin", "terminal", "phase_index", "casts", "burns", "statuses", "pickups", "landings", "exposure_through_frame", "events"]
const CAST_FIELDS := ["run_id", "owner_source_id", "action_id", "attack_generation", "runtime_frame", "geometry", "damage_multiplier"]
const DAMAGE_FIELDS := ["fact_id", "run_id", "owner_source_id", "attack_generation", "hit_index", "target_id", "runtime_frame", "actual_loss"]
const LANDING_FIELDS := ["run_id", "owner_source_id", "attack_generation", "runtime_frame", "position", "landed"]
const PICKUP_FIELDS := ["fact_id", "run_id", "owner_source_id", "pickup_id", "target_id", "runtime_frame", "energy_before", "energy_after", "maximum", "revision_before", "revision_after"]
const EVENT_FIELDS := {"cast": ["kind", "frame", "action_id", "generation", "geometry", "damage_multiplier"], "damage": ["kind", "frame", "fact_id", "generation", "hit_index", "target_id", "actual_loss"], "landing": ["kind", "frame", "generation", "position", "landed"], "followup": ["kind", "frame", "generation", "followup_generation"], "pickup": ["kind", "frame", "fact_id", "pickup_id", "target_id", "energy_before", "energy_after", "maximum", "revision_before", "revision_after"], "phase": ["kind", "frame", "phase_index"], "terminal": ["kind", "frame"]}
const MAX_FRAME := 2147447646
const MAX_EVENTS := 4096
const MAX_VALIDATION_CACHE := 4
const MAX_EVENT_CHECKPOINT_BYTES := 524288
const MAX_REPLAY_CHECKPOINT_BYTES := 1048576
static var _validation_cache: Array[Dictionary] = []
static var _validation_cache_mutex := Mutex.new()
var _definition: Dictionary = {}
var _state: Dictionary = {}
var _initial: Dictionary = {}
var _event_replay_checkpoint: Dictionary = {}
var _event_replay_checkpoint_mutex := Mutex.new()


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	var parsed := Definition.new().configure_runtime_projection(definition)
	if not parsed.ok or definition.id != "void_throne" or not Contract.exact_fields(identity, ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]) or not _id(identity.run_id) or not _id(identity.hostile_source_id) or not Contract.integer_in_range(identity.runtime_frame, 0, MAX_FRAME) or not Contract.integer_in_range(identity.next_generation_floor, 1, MAX_FRAME) or not Contract.integer_in_range(identity.seed, -2147483648, 2147483647):
		return _failure("configuration")
	_definition = parsed.definition.duplicate(true)
	_state = {"schema_version": 1, "definition_digest": JSON.stringify(_definition, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "arena_origin": {"x": 0.0, "y": 0.0}, "terminal": false, "phase_index": 0, "casts": [], "burns": [], "statuses": [], "pickups": [], "landings": [], "exposure_through_frame": int(identity.runtime_frame) - 1, "events": []}
	_initial = snapshot()
	_clear_event_replay_checkpoint()
	return {"ok": true}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func matches_snapshot(value: Dictionary) -> bool:
	return _state == value


func native_exposure_through_frame() -> int:
	return int(_state.get("exposure_through_frame", -1))


func bind_origin(origin: Dictionary) -> bool:
	if _state.is_empty() or not Contract.valid_point(origin) or origin != _state.arena_origin and (not _state.events.is_empty() or _state.runtime_frame != _initial.runtime_frame):
		return false
	_state.arena_origin = origin.duplicate(true)
	_initial.arena_origin = origin.duplicate(true)
	_clear_event_replay_checkpoint()
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
	return _burn_damage_requests(_state, frame)


func burn_damage_requests_for_snapshot(value: Dictionary, frame: int) -> Dictionary:
	if not can_restore_snapshot(value):
		return _failure("burn_snapshot")
	return {"ok": true, "requests": _burn_damage_requests(value, frame)}


func _burn_damage_requests(state: Dictionary, frame: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if state.is_empty() or state.terminal or frame != int(state.runtime_frame):
		return result
	for burn: Dictionary in state.burns:
		var age := frame - int(burn.start_frame)
		if age > 0 and age % int(_definition.mechanisms.scepter_burn_tick_frames) == 0:
			result.append({"payload_id": "void-burn:" + JSON.stringify([state.identity.hostile_source_id, burn.target_id, burn.attack_generation]).sha256_text().substr(0, 40), "hostile_source_id": str(state.identity.hostile_source_id), "attack_generation": int(burn.attack_generation), "hit_index": age / int(_definition.mechanisms.scepter_burn_tick_frames), "target_id": burn.target_id, "runtime_frame": frame, "damage": float(_definition.mechanisms.scepter_burn_damage), "damage_type": "void"})
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
	# Typed bytes distinguish integer event authority from numerically equal floats.
	var context := var_to_bytes([_definition, _initial])
	var encoded := var_to_bytes(value)
	if _validation_cache_contains(context, encoded, accepted_boundary):
		return true
	# Serialization alone cannot certify null/freed-Object aliases.
	var checkpoint_eligible := context.size() <= MAX_EVENT_CHECKPOINT_BYTES and Replay.replay_value_is_safe([_definition, _initial, value.events])
	var event_bytes := var_to_bytes(value.events) if checkpoint_eligible else PackedByteArray()
	checkpoint_eligible = checkpoint_eligible and event_bytes.size() <= MAX_EVENT_CHECKPOINT_BYTES
	var replay := _event_checkpoint_replay(context, event_bytes, int(value.runtime_frame)) if checkpoint_eligible else {}
	var checkpoint: Dictionary = {}
	if replay.is_empty():
		replay = _initial.duplicate(true)
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
		# Keep the event-time state, before expiry at the requested later frame.
		if checkpoint_eligible and previous <= int(value.runtime_frame):
			var replay_bytes := var_to_bytes(replay)
			if replay_bytes.size() <= MAX_REPLAY_CHECKPOINT_BYTES:
				checkpoint = {"context": context, "events": event_bytes, "replay": replay_bytes, "frame": previous}
	replay.runtime_frame = int(value.runtime_frame)
	_refresh(replay)
	var valid: bool = replay == value or JSON.parse_string(JSON.stringify(replay)) == JSON.parse_string(JSON.stringify(value))
	if valid:
		_cache_validated_snapshot(context, encoded, accepted_boundary)
		if not checkpoint.is_empty():
			if get_script() == VoidAuxiliaryRuntime and OS.get_thread_caller_id() == OS.get_main_thread_id():
				var retained: Dictionary = bytes_to_var(checkpoint.replay)
				_freeze_checkpoint_value(retained)
				checkpoint["decoded"] = retained
			_event_replay_checkpoint_mutex.lock()
			_event_replay_checkpoint = checkpoint
			_event_replay_checkpoint_mutex.unlock()
	return valid


func _event_checkpoint_replay(context: PackedByteArray, events: PackedByteArray, frame: int) -> Dictionary:
	var replay_bytes := PackedByteArray()
	var retained: Dictionary = {}
	_event_replay_checkpoint_mutex.lock()
	if not _event_replay_checkpoint.is_empty() and _event_replay_checkpoint.context == context and _event_replay_checkpoint.events == events and frame >= int(_event_replay_checkpoint.frame):
		if get_script() == VoidAuxiliaryRuntime and OS.get_thread_caller_id() == OS.get_main_thread_id() and _event_replay_checkpoint.get("decoded") is Dictionary:
			retained = _event_replay_checkpoint.decoded
		else:
			replay_bytes = _event_replay_checkpoint.replay
	_event_replay_checkpoint_mutex.unlock()
	# Read-only Dictionary traversal is not thread-safe in Godot 4.6.1.
	# Main-thread expiry only replaces top-level arrays; workers decode private state.
	if not retained.is_empty():
		return retained.duplicate()
	return bytes_to_var(replay_bytes) if not replay_bytes.is_empty() else {}


static func _freeze_checkpoint_value(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value:
			_freeze_checkpoint_value(key)
			_freeze_checkpoint_value(value[key])
		value.make_read_only()
	elif value is Array:
		for child: Variant in value:
			_freeze_checkpoint_value(child)
		value.make_read_only()


func _clear_event_replay_checkpoint() -> void:
	_event_replay_checkpoint_mutex.lock()
	_event_replay_checkpoint.clear()
	_event_replay_checkpoint_mutex.unlock()


static func _validation_cache_contains(context: PackedByteArray, encoded: PackedByteArray, accepted_boundary: bool) -> bool:
	_validation_cache_mutex.lock()
	for row: Dictionary in _validation_cache:
		if row.accepted_boundary == accepted_boundary and row.context == context and row.snapshot == encoded:
			_validation_cache_mutex.unlock()
			return true
	_validation_cache_mutex.unlock()
	return false


static func _cache_validated_snapshot(context: PackedByteArray, encoded: PackedByteArray, accepted_boundary: bool) -> void:
	_validation_cache_mutex.lock()
	for row: Dictionary in _validation_cache:
		if row.accepted_boundary == accepted_boundary and row.context == context and row.snapshot == encoded:
			_validation_cache_mutex.unlock()
			return
	if _validation_cache.size() == MAX_VALIDATION_CACHE:
		_validation_cache.pop_front()
	_validation_cache.append({"context": context, "snapshot": encoded, "accepted_boundary": accepted_boundary})
	_validation_cache_mutex.unlock()


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
	var room_half: bool = action.id in VoidHalf.ACTION_IDS and not value.is_empty() and value[0] is Dictionary and value[0].get("radius") == 90.0 and value[0].get("length") == 640.0
	if room_half and not VoidHalf.valid_geometry(value, str(action.id), state.arena_origin):
		return false
	for index: int in range(value.size()):
		var row: Variant = value[index]
		var recipe: Dictionary = VoidHalf.recipe(str(action.id))[index] if room_half else action.geometry[index]
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
