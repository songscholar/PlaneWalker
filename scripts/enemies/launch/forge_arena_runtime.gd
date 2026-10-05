class_name ForgeArenaRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "arena_origin", "phase_index", "covers", "vents", "cooling_pools", "vent_damage_authority", "damage_claims", "cooling_claims", "occupants", "burns", "events"]
const DAMAGE_FIELDS := ["fact_id", "run_id", "owner_source_id", "construct_id", "runtime_frame", "amount"]
const BURN_FIELDS := ["run_id", "owner_source_id", "target_id", "attack_generation", "runtime_frame"]
const COVER_POSITIONS := [Vector2(192, 120), Vector2(448, 120), Vector2(192, 240), Vector2(448, 240)]
const VENT_POSITIONS := [Vector2(96, 56), Vector2(544, 56), Vector2(96, 304), Vector2(544, 304)]
const COOLING_POSITIONS := [Vector2(320, 48), Vector2(320, 312), Vector2(48, 180), Vector2(592, 180)]
const MAX_EVENTS := 2048
var _definition: Dictionary = {}
var _state: Dictionary = {}
var _initial: Dictionary = {}


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	var parsed := Definition.new().configure_runtime_projection(definition)
	if not parsed.ok or definition.id != "forge_colossus" or not Contract.exact_fields(identity, ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]) or not _id(identity.run_id) or not _id(identity.hostile_source_id) or not Contract.integer_in_range(identity.runtime_frame, 0, 2147483046):
		return _failure("configuration")
	_definition = parsed.definition.duplicate(true)
	_state = {"schema_version": 1, "definition_digest": JSON.stringify(_definition.arena, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false, "arena_origin": {"x": 0.0, "y": 0.0}, "phase_index": 0, "covers": [], "vents": [], "cooling_pools": [], "vent_damage_authority": "rule_forge_vents", "damage_claims": [], "cooling_claims": [], "occupants": {}, "burns": [], "events": []}
	for kind: int in range(3):
		var recipe: Dictionary = _definition.arena.constructs[kind]
		var positions: Array = [COVER_POSITIONS, VENT_POSITIONS, COOLING_POSITIONS][kind]
		for slot: int in range(4):
			var row := {"id": "%s:%d" % [recipe.id, slot], "recipe_id": str(recipe.id), "slot": slot, "position": _point(positions[slot]), "radius_px": float(recipe.radius_px), "max_hp": float(recipe.max_hp), "current_hp": float(recipe.max_hp), "broken": false}
			_state[["covers", "vents", "cooling_pools"][kind]].append(row)
	_initial = snapshot()
	return {"ok": true, "snapshot": snapshot()}


func bind_origin(origin: Dictionary) -> bool:
	if _state.is_empty() or not Contract.valid_point(origin) or not _state.events.is_empty() and _state.arena_origin != origin:
		return false
	_state.arena_origin = origin.duplicate(true)
	_initial.arena_origin = origin.duplicate(true)
	return true


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func advance_frame(frame: int) -> bool:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame) + 1:
		return false
	_clock_to(frame)
	return true


func accept_damage_fact(fact: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.exact_fields(fact, DAMAGE_FIELDS) or not _id(fact.fact_id) or fact.run_id != _state.identity.run_id or fact.owner_source_id != _state.identity.hostile_source_id or not _id(fact.construct_id) or typeof(fact.runtime_frame) != TYPE_INT or fact.runtime_frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or not Contract.number_in_range(fact.amount, 0.000001, 1000000.0):
		return _failure("damage_fact")
	return _accept_event({"kind": "damage", "runtime_frame": int(fact.runtime_frame), "fact_id": fact.fact_id, "construct_id": fact.construct_id, "amount": float(fact.amount)})


func accept_burn_fact(fact: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.exact_fields(fact, BURN_FIELDS) or fact.run_id != _state.identity.run_id or fact.owner_source_id != _state.identity.hostile_source_id or not _id(fact.target_id) or not Contract.integer_in_range(fact.attack_generation, 1, 2147483046) or fact.runtime_frame != _state.runtime_frame:
		return _failure("burn_fact")
	return _accept_event({"kind": "burn", "runtime_frame": int(fact.runtime_frame), "target_id": fact.target_id, "attack_generation": int(fact.attack_generation)})


func observe_target(target_id: String, position: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not _id(target_id) or not Contract.valid_point(position):
		return _failure("cooling_target")
	var pool := _pool_at(position)
	if _state.occupants.get(target_id, "") == pool:
		return {"ok": true, "cooled": false}
	return _accept_event({"kind": "occupancy", "runtime_frame": int(_state.runtime_frame), "target_id": target_id, "position": position.duplicate(true)})


func accept_phase(phase: int, frame: int) -> Dictionary:
	if _state.is_empty() or _state.terminal or phase <= int(_state.phase_index) or phase > 2 or frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1]:
		return _failure("phase")
	return _accept_event({"kind": "phase", "runtime_frame": frame, "phase_index": phase})


func burn_damage_requests(frame: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _state.is_empty() or _state.terminal or frame != _state.runtime_frame:
		return result
	for burn: Dictionary in _state.burns:
		var age := frame - int(burn.start_frame)
		if age > 0 and age % int(_definition.mechanisms.slam_burn_tick_frames) == 0:
			result.append({"payload_id": "forge-burn:" + JSON.stringify([_state.identity.hostile_source_id, burn.target_id, burn.attack_generation]).sha256_text().substr(0, 40), "hostile_source_id": str(_state.identity.hostile_source_id), "attack_generation": int(burn.attack_generation), "hit_index": age / int(_definition.mechanisms.slam_burn_tick_frames), "target_id": burn.target_id, "runtime_frame": frame, "damage": float(_definition.mechanisms.slam_burn_damage), "damage_type": "fire"})
	return result


func retire() -> void:
	if not _state.is_empty():
		_state.terminal = true
		_state.burns = []


func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
	if _initial.is_empty() or not Contract.exact_fields(value, FIELDS) or value.schema_version != 1 or typeof(value.schema_version) != TYPE_INT or value.definition_digest != _initial.definition_digest or value.identity != _initial.identity or value.arena_origin != _initial.arena_origin or not Contract.integer_in_range(value.runtime_frame, int(_initial.runtime_frame), 2147483046) or typeof(value.terminal) != TYPE_BOOL or not value.events is Array or value.events.size() > MAX_EVENTS:
		return false
	var candidate: RefCounted = get_script().new()
	if not candidate.configure(_definition, _initial.identity).ok or not candidate.bind_origin(_initial.arena_origin):
		return false
	var previous_frame: int = int(_initial.runtime_frame)
	for event: Variant in value.events:
		if not event is Dictionary or not Contract.integer_in_range(event.get("runtime_frame"), previous_frame, int(value.runtime_frame) + (0 if accepted_boundary else 1)):
			return false
		candidate._clock_to(int(event.runtime_frame))
		if not candidate._accept_event(event).ok:
			return false
		previous_frame = int(event.runtime_frame)
	candidate._clock_to(int(value.runtime_frame))
	if value.terminal:
		candidate.retire()
	return candidate.snapshot() == value


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


func initial_at_frame(frame: int, terminal: bool, phase: int) -> Dictionary:
	if _initial.is_empty() or frame < int(_initial.runtime_frame) or phase < 0 or phase > 2:
		return {}
	var candidate: RefCounted = get_script().new()
	candidate.configure(_definition, _initial.identity)
	candidate.bind_origin(_initial.arena_origin)
	candidate._clock_to(frame)
	if phase > 0:
		candidate.accept_phase(phase, frame)
	if terminal:
		candidate.retire()
	return candidate.snapshot()


func _accept_event(event: Dictionary) -> Dictionary:
	if _state.events.size() >= MAX_EVENTS:
		return _failure("event_limit")
	var result := {"ok": true}
	match event.get("kind", ""):
		"damage":
			if not Contract.exact_fields(event, ["kind", "runtime_frame", "fact_id", "construct_id", "amount"]) or not _id(event.fact_id) or not _id(event.construct_id) or not Contract.number_in_range(event.amount, 0.000001, 1000000.0) or _state.damage_claims.any(func(row: Dictionary): return row.fact_id == event.fact_id):
				return _failure("damage_event")
			var found := false
			for cover: Dictionary in _state.covers:
				if cover.id != event.construct_id:
					continue
				if cover.broken:
					return _failure("broken_anvil")
				var amount := minf(float(cover.current_hp), float(event.amount))
				cover.current_hp = float(cover.current_hp) - amount
				cover.broken = cover.current_hp == 0.0
				_state.damage_claims.append({"fact_id": str(event.fact_id), "construct_id": str(event.construct_id), "runtime_frame": int(event.runtime_frame), "amount": amount})
				result["amount"] = amount
				result["broken"] = bool(cover.broken)
				found = true
			if not found:
				return _failure("unknown_anvil")
		"burn":
			if not Contract.exact_fields(event, ["kind", "runtime_frame", "target_id", "attack_generation"]) or not _id(event.target_id) or not Contract.integer_in_range(event.attack_generation, 1, 2147483046) or _state.events.any(func(row: Dictionary): return row.kind == "burn" and row.target_id == event.target_id and row.attack_generation == event.attack_generation):
				return _failure("burn_event")
			_state.burns.append({"target_id": event.target_id, "attack_generation": int(event.attack_generation), "start_frame": int(event.runtime_frame), "through_frame": int(event.runtime_frame) + int(_definition.mechanisms.slam_burn_frames)})
		"occupancy":
			if not Contract.exact_fields(event, ["kind", "runtime_frame", "target_id", "position"]) or not _id(event.target_id) or not Contract.valid_point(event.position):
				return _failure("occupancy_event")
			var pool := _pool_at(event.position)
			if _state.occupants.get(event.target_id, "") == pool:
				return _failure("duplicate_occupancy")
			_state.occupants[event.target_id] = pool
			var last := -2147483046
			for claim: Dictionary in _state.cooling_claims:
				if claim.target_id == event.target_id:
					last = int(claim.runtime_frame)
			var cooled: bool = not pool.is_empty() and int(event.runtime_frame) - last >= int(_definition.mechanisms.cooling_entry_cooldown_frames)
			result["cooled"] = cooled
			if cooled:
				_state.cooling_claims.append({"target_id": event.target_id, "pool_id": pool, "runtime_frame": int(event.runtime_frame)})
				_state.burns = _state.burns.filter(func(row: Dictionary): return row.target_id != event.target_id)
		"phase":
			if not Contract.exact_fields(event, ["kind", "runtime_frame", "phase_index"]) or not Contract.integer_in_range(event.phase_index, int(_state.phase_index) + 1, 2):
				return _failure("phase_event")
			_state.phase_index = int(event.phase_index)
			_state.burns = []
		_: return _failure("unknown_event")
	_state.events.append(event.duplicate(true))
	return result


func _clock_to(frame: int) -> void:
	_state.runtime_frame = frame
	_state.burns = _state.burns.filter(func(row: Dictionary): return row.through_frame >= frame)


func _pool_at(position: Dictionary) -> String:
	var point := Vector2(float(position.x) - float(_state.arena_origin.x), float(position.y) - float(_state.arena_origin.y))
	for pool: Dictionary in _state.cooling_pools:
		if point.distance_to(Vector2(float(pool.position.x), float(pool.position.y))) <= float(pool.radius_px):
			return str(pool.id)
	return ""


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 128


static func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"FORGE_ARENA_INVALID", "field": field}
