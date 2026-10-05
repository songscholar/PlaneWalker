class_name ForestAuxiliaryRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "arena_origin", "terminal", "sacs", "flowers", "seeds", "cages", "drain_healed_total", "erosion_steps", "events"]
const EVENT_FIELDS := {"damage": ["kind", "frame", "fact_id", "construct_id", "amount"], "flower": ["kind", "frame", "construct_id", "target_id", "amount"], "seed": ["kind", "frame", "generation", "sac_id"], "legacy_seed": ["kind", "frame", "generation", "position"], "seed_cancel": ["kind", "frame", "generation"], "burst": ["kind", "frame", "generation"], "cage": ["kind", "frame", "generation", "geometry", "damage_multiplier"], "drain": ["kind", "frame", "fact_id", "generation", "hit_index", "actual_loss", "actual_heal"], "erosion": ["kind", "frame", "generation"], "terminal": ["kind", "frame"]}
const SAC_POSITIONS := [Vector2(176, 136), Vector2(464, 136), Vector2(176, 224), Vector2(464, 224)]
const FLOWER_POSITIONS := [Vector2(96, 180), Vector2(320, 288), Vector2(544, 180)]
const MAX_FRAME := 2147447646
const MAX_EVENTS := 4096
const MAX_VALIDATION_CACHE := 4
static var _validation_cache: Array[Dictionary] = []
static var _validation_cache_mutex := Mutex.new()
var _state: Dictionary = {}
var _initial: Dictionary = {}
var _validation_context := PackedByteArray()


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	var parsed := Definition.new().configure_runtime_projection(definition)
	if not parsed.ok or definition.id != "forest_heart" or not Contract.exact_fields(identity, ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]) or not _id(identity.run_id) or not _id(identity.hostile_source_id) or not Contract.integer_in_range(identity.runtime_frame, 0, MAX_FRAME) or not Contract.integer_in_range(identity.next_generation_floor, 1, MAX_FRAME):
		return _failure("configuration")
	_state = {"schema_version": 1, "definition_digest": JSON.stringify(parsed.definition.arena, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "arena_origin": {"x": 0.0, "y": 0.0}, "terminal": false, "sacs": [], "flowers": [], "seeds": [], "cages": [], "drain_healed_total": 0.0, "erosion_steps": 0, "events": []}
	for slot: int in range(4):
		_state.sacs.append({"id": "forest_spore_sac:%d" % slot, "recipe_id": "forest_spore_sac", "slot": slot, "position": _point(SAC_POSITIONS[slot]), "radius_px": 10.0, "max_hp": 30.0, "current_hp": 30.0, "broken": false})
	for slot: int in range(3):
		_state.flowers.append({"id": "forest_healing_flower:%d" % slot, "slot": slot, "position": _point(FLOWER_POSITIONS[slot]), "radius_px": 8.0, "used": false, "heal_amount": 0.0, "used_frame": -1, "target_id": ""})
	_initial = snapshot()
	_validation_context = var_to_bytes([_initial, _state.arena_origin])
	return {"ok": true}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func bind_origin(origin: Dictionary) -> bool:
	if _state.is_empty() or not Contract.valid_point(origin) or origin != _state.arena_origin and (not _state.events.is_empty() or _state.runtime_frame != _initial.runtime_frame):
		return false
	_state.arena_origin = origin.duplicate(true)
	_initial.arena_origin = origin.duplicate(true)
	_validation_context = var_to_bytes([_initial, _state.arena_origin])
	return true


func select_seed_sac(target: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.valid_point(target):
		return {}
	var rows: Array = _state.sacs.filter(func(row: Dictionary): return not row.broken)
	var origin := _vector(_state.arena_origin)
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		var first := (origin + _vector(a.position)).distance_squared_to(_vector(target))
		var second := (origin + _vector(b.position)).distance_squared_to(_vector(target))
		return a.slot < b.slot if is_equal_approx(first, second) else first < second)
	if rows.is_empty():
		return {}
	var result: Dictionary = rows[0].duplicate(true)
	result.position = _point(origin + _vector(result.position))
	return result


func reserve_seed(generation: int, sac_id: String, frame: int) -> Dictionary:
	return _record({"kind": "seed", "frame": frame, "generation": generation, "sac_id": sac_id})


func seed_burst(generation: int, frame: int) -> Dictionary:
	return _record({"kind": "burst", "frame": frame, "generation": generation})


func cancel_seed(generation: int, frame: int) -> Dictionary:
	return _record({"kind": "seed_cancel", "frame": frame, "generation": generation})


func accept_damage_fact(fact: Dictionary) -> Dictionary:
	if not Contract.exact_fields(fact, ["fact_id", "run_id", "owner_source_id", "construct_id", "runtime_frame", "amount"]) or _state.is_empty() or fact.run_id != _state.identity.run_id or fact.owner_source_id != _state.identity.hostile_source_id:
		return _failure("damage_identity")
	var result := _record({"kind": "damage", "frame": fact.runtime_frame, "fact_id": fact.fact_id, "construct_id": fact.construct_id, "amount": fact.amount})
	return result


func consume_flower(id: String, target_id: String, frame: int, actual_heal: float) -> Dictionary:
	return _record({"kind": "flower", "frame": frame, "construct_id": id, "target_id": target_id, "amount": actual_heal})


func spawn_cage(generation: int, frame: int, geometry: Array, damage_multiplier: float) -> Dictionary:
	return _record({"kind": "cage", "frame": frame, "generation": generation, "geometry": geometry.duplicate(true), "damage_multiplier": damage_multiplier})


func drain_allowance(generation: int, actual_loss: float) -> float:
	if _state.is_empty() or _state.terminal or not Contract.number_in_range(actual_loss, 0.0, 1000000.0):
		return 0.0
	var spent := 0.0
	for event: Dictionary in _state.events:
		if event.kind == "drain" and event.generation == generation:
			spent += float(event.actual_heal)
	return minf(actual_loss, minf(80.0 - spent, 200.0 - float(_state.drain_healed_total)))


func accept_drain_receipt(id: String, generation: int, hit_index: int, frame: int, actual_loss: float, actual_heal: float) -> Dictionary:
	return _record({"kind": "drain", "frame": frame, "fact_id": id, "generation": generation, "hit_index": hit_index, "actual_loss": actual_loss, "actual_heal": actual_heal})


func accept_erosion(generation: int, frame: int) -> Dictionary:
	return _record({"kind": "erosion", "frame": frame, "generation": generation})


func advance_frame(frame: int) -> bool:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame) + 1 or frame > MAX_FRAME:
		return false
	_state.runtime_frame = frame
	_refresh(_state)
	return true


func retire() -> void:
	if not _state.is_empty() and not _state.terminal:
		_record({"kind": "terminal", "frame": int(_state.runtime_frame)})


func cage_requests(frame: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame):
		return result
	for event: Dictionary in _state.events:
		if event.kind != "cage":
			continue
		var age := frame - int(event.frame)
		var live: Array = _state.cages.filter(func(row: Dictionary): return row.attack_generation == event.generation and not row.broken and not row.expired)
		if live.is_empty():
			continue
		if age >= 0 and age <= 240 and age % 60 == 0:
			var center := _vector(event.geometry[0].origin) + Vector2(24.0, 24.0)
			result.append(_cage_request(event, "forest_cage_pulse", "forest_cage:%d" % int(event.generation), frame, int(age / 60), center, 30, 20.0, 8.0 * float(event.damage_multiplier)))
		if age == 260:
			for wall: Dictionary in live:
				result.append(_cage_request(event, "forest_cage_collapse", str(wall.id), frame, int(wall.slot), _vector(_state.arena_origin) + _vector(wall.position), 40, 24.0, 15.0 * float(event.damage_multiplier)))
	return result


func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
	if _initial.is_empty():
		return false
	var context := _validation_context
	var encoded := var_to_bytes(value)
	if _validation_cache_contains(context, encoded, accepted_boundary):
		return true
	if not _can_restore_snapshot_uncached(value, accepted_boundary):
		return false
	_cache_validated_snapshot(context, encoded, accepted_boundary)
	return true


func _can_restore_snapshot_uncached(value: Dictionary, accepted_boundary: bool = false) -> bool:
	if _initial.is_empty() or not Contract.exact_fields(value, FIELDS) or value.schema_version != 1 or value.identity != _initial.identity or value.definition_digest != _initial.definition_digest or value.arena_origin != _state.arena_origin or not Contract.integer_in_range(value.runtime_frame, int(_initial.runtime_frame), MAX_FRAME) or not value.events is Array or value.events.size() > MAX_EVENTS:
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


func initial_at_frame(frame: int, terminal: bool, historical_action: Dictionary = {}) -> Dictionary:
	var result := _initial.duplicate(true)
	result.runtime_frame = frame
	if terminal:
		result.events.append({"kind": "terminal", "frame": frame})
		result.terminal = true
	elif historical_action.get("action_id") == "matriarch_void_seed" and historical_action.get("geometry_generations", []).size() == 1 and historical_action.get("committed_geometry", []).size() == 1:
		var event := {"kind": "legacy_seed", "frame": frame, "generation": int(historical_action.geometry_generations[0]), "position": _point(_vector(historical_action.committed_geometry[0].origin) - _vector(result.arena_origin))}
		if not _apply(result, event).ok:
			return {}
		result.events.append(event)
		if not historical_action.get("resolved_hit_indices", []).is_empty():
			var burst := {"kind": "burst", "frame": frame, "generation": int(event.generation)}
			_apply(result, burst)
			result.events.append(burst)
	return result if can_restore_snapshot(result, true) else {}


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
		"damage":
			if not _id(event.fact_id) or not _id(event.construct_id) or not Contract.number_in_range(event.amount, 0.000001, 1000000.0) or state.events.any(func(row: Dictionary): return row.get("fact_id", "") == event.fact_id):
				return _failure("damage_claim")
			for row: Dictionary in state.sacs + state.cages:
				if row.id != event.construct_id:
					continue
				if row.broken or bool(row.get("expired", false)) or row.has("spawn_frame") and event.frame >= int(row.spawn_frame) + 300:
					return _failure("inactive_construct")
				var amount := minf(float(row.current_hp), float(event.amount))
				row.current_hp -= amount
				row.broken = row.current_hp == 0.0
				var cancelled: Array = []
				if row.broken:
					for seed: Dictionary in state.seeds:
						if seed.sac_id == row.id and seed.burst_frame == -1 and seed.cancelled_frame == -1:
							seed.cancelled_frame = int(event.frame)
							cancelled.append(int(seed.generation))
				return {"ok": true, "amount": amount, "cancelled_seed_generations": cancelled}
			return _failure("unknown_construct")
		"flower":
			if not _id(event.target_id) or not Contract.number_in_range(event.amount, 0.000001, 20.0):
				return _failure("flower_receipt")
			for row: Dictionary in state.flowers:
				if row.id == event.construct_id and not row.used:
					row.used = true
					row.heal_amount = float(event.amount)
					row.used_frame = int(event.frame)
					row.target_id = str(event.target_id)
					return {"ok": true}
			return _failure("spent_flower")
		"seed":
			if not _generation(event.generation, state) or state.seeds.any(func(row: Dictionary): return row.generation == event.generation):
				return _failure("seed_identity")
			for sac: Dictionary in state.sacs:
				if sac.id == event.sac_id and not sac.broken:
					state.seeds.append({"generation": int(event.generation), "commit_frame": int(event.frame), "sac_id": str(event.sac_id), "position": sac.position.duplicate(true), "burst_frame": -1, "cancelled_frame": -1})
					return {"ok": true}
			return _failure("seed_sac")
		"legacy_seed":
			if not _generation(event.generation, state) or not Contract.valid_point(event.position) or not state.seeds.is_empty() or state.events.any(func(row: Dictionary): return row.kind == "legacy_seed"):
				return _failure("historical_seed")
			state.seeds.append({"generation": int(event.generation), "commit_frame": int(event.frame), "sac_id": "", "position": event.position.duplicate(true), "burst_frame": -1, "cancelled_frame": -1})
			return {"ok": true}
		"burst":
			for row: Dictionary in state.seeds:
				if row.generation == event.generation and row.burst_frame == -1 and row.cancelled_frame == -1:
					row.burst_frame = int(event.frame)
					return {"ok": true, "position": _point(_vector(state.arena_origin) + _vector(row.position))}
			return _failure("seed_burst")
		"seed_cancel":
			for row: Dictionary in state.seeds:
				if row.generation == event.generation and row.burst_frame == -1 and row.cancelled_frame == -1:
					row.cancelled_frame = int(event.frame)
					return {"ok": true}
			return _failure("seed_cancel")
		"cage":
			if not _generation(event.generation, state) or not _cage_geometry(event.geometry) or not Contract.number_in_range(event.damage_multiplier, 1.0, 6.0) or state.cages.any(func(row: Dictionary): return row.attack_generation == event.generation):
				return _failure("cage_geometry")
			for slot: int in range(3):
				var fact: Dictionary = event.geometry[slot]
				var direction := _vector(fact.aim_direction)
				state.cages.append({"id": "forest_cage:%d:%d" % [int(event.generation), slot], "slot": slot, "position": _point(_vector(fact.origin) + direction * float(fact.length) * 0.5 - _vector(state.arena_origin)), "rotation": direction.angle(), "length": float(fact.length), "thickness": 10.0, "max_hp": 50.0, "current_hp": 50.0, "broken": false, "expired": false, "spawn_frame": int(event.frame), "lifetime_frames": 300, "attack_generation": int(event.generation)})
			return {"ok": true}
		"drain":
			if not _id(event.fact_id) or not _generation(event.generation, state) or not Contract.integer_in_range(event.hit_index, 0, 3) or not Contract.number_in_range(event.actual_loss, 0.0, 1000000.0) or not Contract.number_in_range(event.actual_heal, 0.0, minf(80.0, float(event.actual_loss))) or state.events.any(func(row: Dictionary): return row.get("fact_id", "") == event.fact_id or row.kind == "drain" and row.generation == event.generation and row.hit_index == event.hit_index):
				return _failure("drain_receipt")
			var spent := 0.0
			for previous: Dictionary in state.events:
				if previous.kind == "drain" and previous.generation == event.generation:
					spent += float(previous.actual_heal)
			if spent + float(event.actual_heal) > 80.0 or float(state.drain_healed_total) + float(event.actual_heal) > 200.0:
				return _failure("drain_cap")
			state.drain_healed_total += float(event.actual_heal)
			return {"ok": true}
		"erosion":
			if not _generation(event.generation, state) or state.erosion_steps >= 2 or state.events.any(func(row: Dictionary): return row.kind == "erosion" and row.generation == event.generation):
				return _failure("erosion_limit")
			state.erosion_steps += 1
			return {"ok": true}
		"terminal":
			state.terminal = true
			return {"ok": true}
	return _failure("unknown_event")


func _refresh(state: Dictionary) -> void:
	for row: Dictionary in state.cages:
		row.expired = int(state.runtime_frame) >= int(row.spawn_frame) + 300


static func _cage_geometry(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for slot: int in range(3):
		var row: Variant = value[slot]
		if not row is Dictionary or not Contract.exact_fields(row, ["origin", "aim_direction", "length", "radius"]) or not Contract.valid_point(row.origin) or not Contract.valid_point(row.aim_direction) or row.radius != 5.0 or row.length != (48.0 if slot < 2 else 16.0) or not _vector(row.aim_direction).is_equal_approx(Vector2.DOWN if slot < 2 else Vector2.RIGHT):
			return false
	var first := _vector(value[0].origin)
	return _vector(value[1].origin) == first + Vector2(48.0, 0.0) and _vector(value[2].origin) == first + Vector2(0.0, 48.0)


static func _cage_request(event: Dictionary, kind: String, id: String, frame: int, index: int, position: Vector2, warning: int, radius: float, damage: float) -> Dictionary:
	return {"kind": kind, "hostile_source_id": "", "run_id": "", "attack_generation": int(event.generation), "hit_index": index, "runtime_frame": frame, "construct_id": id, "position": _point(position), "parameters": {"warning_frames": warning, "radius": radius, "damage": damage}}


static func _valid_event(event: Dictionary) -> bool:
	return event.get("kind") in EVENT_FIELDS and Contract.exact_fields(event, EVENT_FIELDS[event.kind]) and Contract.integer_in_range(event.frame, 0, MAX_FRAME)


static func _generation(value: Variant, state: Dictionary) -> bool:
	return Contract.integer_in_range(value, int(state.identity.next_generation_floor), MAX_FRAME)


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))


static func _id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 256 and value.strip_edges() == value


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "code": &"FOREST_AUXILIARY_INVALID", "context": {"reason": reason}}
