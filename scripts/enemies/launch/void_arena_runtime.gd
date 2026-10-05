class_name VoidArenaRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "arena_origin", "phase_index", "pillars", "cores", "rounds_started", "round_completed_frame", "exposure_through_frame", "core_break_claims", "player_heal", "events"]
const IDENTITY_FIELDS := ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]
const FACT_FIELDS := ["fact_id", "run_id", "owner_source_id", "construct_id", "runtime_frame", "amount"]
const MAX_FRAME := 2147447646
const MAX_EVENTS := 4096
const PILLAR_POSITIONS := [Vector2(160, 104), Vector2(480, 104), Vector2(160, 256), Vector2(480, 256)]
const CORE_POSITIONS := [Vector2(240, 112), Vector2(400, 112), Vector2(240, 248), Vector2(400, 248)]
var _definition: Dictionary = {}
var _initial: Dictionary = {}
var _state: Dictionary = {}


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	_definition.clear()
	_initial.clear()
	_state.clear()
	var parsed := Definition.new().configure_runtime_projection(definition)
	if not parsed.ok or definition.id != "void_throne" or not Contract.exact_fields(identity, IDENTITY_FIELDS) or not _id(identity.run_id) or not _id(identity.hostile_source_id) or not Contract.integer_in_range(identity.runtime_frame, 0, MAX_FRAME - 720) or not Contract.integer_in_range(identity.next_generation_floor, 1, MAX_FRAME) or not Contract.integer_in_range(identity.seed, -2147483648, 2147483647):
		return _failure("configuration")
	_definition = parsed.definition.duplicate(true)
	var recipes: Array = _definition.arena.constructs
	if recipes.size() != 2 or recipes[0] != {"id": "void_cover_pillar", "kind": "cover", "count": 4, "max_hp": 120.0, "radius_px": 14.0} or recipes[1] != {"id": "void_plane_core", "kind": "arena_core", "count": 4, "max_hp": 100.0, "radius_px": 12.0}:
		return _failure("recipes")
	for pair: Array in [["core_break_body_damage", 100.0], ["core_break_exposure_frames", 60], ["core_round_exposure_frames", 120], ["core_regeneration_frames", 600], ["core_round_cap", 2], ["p3_player_heal_fraction", 0.3]]:
		if _definition.mechanisms.get(pair[0]) != pair[1]:
			return _failure("mechanisms")
	var pillars: Array[Dictionary] = []
	for slot: int in range(4):
		pillars.append({"id": "void_cover_pillar:%d" % slot, "recipe_id": "void_cover_pillar", "slot": slot, "position": _point(PILLAR_POSITIONS[slot]), "radius_px": 14.0, "max_hp": 120.0, "current_hp": 120.0, "broken": false, "debris": false})
	_state = {"schema_version": 1, "definition_digest": JSON.stringify({"arena": _definition.arena, "mechanisms": _definition.mechanisms}, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false, "arena_origin": {"x": 0.0, "y": 0.0}, "phase_index": 0, "pillars": pillars, "cores": [], "rounds_started": 0, "round_completed_frame": -1, "exposure_through_frame": int(identity.runtime_frame) - 1, "core_break_claims": [], "player_heal": {}, "events": []}
	_initial = snapshot()
	return {"ok": true, "snapshot": snapshot()}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func bind_origin(origin: Dictionary) -> bool:
	if _state.is_empty() or _state.terminal or not Contract.valid_point(origin) or origin != _state.arena_origin and (int(_state.runtime_frame) != int(_initial.runtime_frame) or not _state.events.is_empty()):
		return false
	_state.arena_origin = origin.duplicate(true)
	return true


func accept_phase(phase_index: int, frame: int) -> Dictionary:
	return _accept_event({"kind": "phase", "runtime_frame": frame, "payload": {"phase_index": phase_index}})


func accept_damage_fact(fact: Dictionary) -> Dictionary:
	if _state.is_empty() or not Contract.exact_fields(fact, FACT_FIELDS) or fact.run_id != _state.identity.run_id or fact.owner_source_id != _state.identity.hostile_source_id:
		return _failure("damage_identity")
	return _accept_event({"kind": "damage", "runtime_frame": fact.runtime_frame, "payload": {"fact_id": fact.fact_id, "construct_id": fact.construct_id, "amount": fact.amount}})


func player_heal_pending() -> bool:
	return not _state.is_empty() and not _state.terminal and _state.phase_index == 2 and _state.player_heal.is_empty()


func accept_player_heal(run_id: String, player_source_id: String, frame: int, maximum_hp: float, amount: float, alive: bool) -> Dictionary:
	return _accept_event({"kind": "player_heal", "runtime_frame": frame, "payload": {"run_id": run_id, "player_source_id": player_source_id, "maximum_hp": maximum_hp, "amount": amount, "alive": alive}})


func advance_frame(frame: int) -> bool:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame) + 1 or frame > MAX_FRAME:
		return false
	_seek(frame)
	return true


func retire() -> void:
	if not _state.is_empty():
		_state.terminal = true


func is_exposed() -> bool:
	return not _state.is_empty() and not _state.terminal and int(_state.runtime_frame) <= int(_state.exposure_through_frame)


func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
	if _initial.is_empty() or not Contract.exact_fields(value, FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or value.definition_digest != _initial.definition_digest or value.identity != _initial.identity or not Contract.integer_in_range(value.runtime_frame, int(_initial.runtime_frame), MAX_FRAME) or typeof(value.terminal) != TYPE_BOOL or not Contract.valid_point(value.arena_origin) or value.arena_origin != _state.arena_origin or not value.events is Array or value.events.size() > MAX_EVENTS:
		return false
	var rebuilt := get_script().new() as RefCounted
	if not rebuilt.configure(_definition, _initial.identity).ok or not rebuilt.bind_origin(value.arena_origin):
		return false
	var previous_frame: int = int(_initial.runtime_frame)
	for event: Variant in value.events:
		if not event is Dictionary or not Contract.exact_fields(event, ["kind", "runtime_frame", "payload"]) or not Contract.integer_in_range(event.runtime_frame, previous_frame, mini(int(value.runtime_frame) + (0 if accepted_boundary else 1), MAX_FRAME)):
			return false
		previous_frame = int(event.runtime_frame)
		rebuilt._seek(previous_frame)
		if not rebuilt._accept_event(event).ok:
			return false
	# Events may be accepted for the next frame before that frame commits.
	if int(rebuilt.snapshot().runtime_frame) <= int(value.runtime_frame):
		rebuilt._seek(int(value.runtime_frame))
	rebuilt._state.runtime_frame = int(value.runtime_frame)
	rebuilt._state.terminal = value.terminal
	return rebuilt.snapshot() == value


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


func initial_at_frame(frame: int, terminal: bool, phase_index: int = 0) -> Dictionary:
	if _initial.is_empty() or not Contract.integer_in_range(frame, int(_initial.runtime_frame), MAX_FRAME) or not Contract.integer_in_range(phase_index, 0, 2):
		return {}
	var rebuilt := get_script().new() as RefCounted
	rebuilt.configure(_definition, _initial.identity)
	rebuilt.bind_origin(_state.arena_origin)
	rebuilt._seek(frame)
	if phase_index > 0 and not rebuilt.accept_phase(phase_index, frame).ok:
		return {}
	if terminal:
		rebuilt.retire()
	return rebuilt.snapshot()


func _accept_event(event: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or _state.events.size() >= MAX_EVENTS or not Contract.exact_fields(event, ["kind", "runtime_frame", "payload"]) or not event.payload is Dictionary or not Contract.integer_in_range(event.runtime_frame, int(_state.runtime_frame), mini(int(_state.runtime_frame) + 1, MAX_FRAME)) or not _state.events.is_empty() and int(event.runtime_frame) < int(_state.events.back().runtime_frame):
		return _failure("event")
	match event.kind:
		"phase":
			return _accept_phase_event(event)
		"damage":
			return _accept_damage_event(event)
		"player_heal":
			return _accept_heal_event(event)
	return _failure("event_kind")


func _accept_phase_event(event: Dictionary) -> Dictionary:
	if not Contract.exact_fields(event.payload, ["phase_index"]) or not Contract.integer_in_range(event.payload.phase_index, int(_state.phase_index) + 1, 2):
		return _failure("phase")
	_state.phase_index = event.payload.phase_index
	for pillar: Dictionary in _state.pillars:
		pillar.debris = true
	if _state.phase_index == 2:
		_start_round(1)
	_state.events.append(event.duplicate(true))
	return {"ok": true, "player_heal_pending": player_heal_pending()}


func _accept_damage_event(event: Dictionary) -> Dictionary:
	var payload: Dictionary = event.payload
	if not Contract.exact_fields(payload, ["fact_id", "construct_id", "amount"]) or not _id(payload.fact_id) or not _id(payload.construct_id) or not Contract.number_in_range(payload.amount, 0.000001, 1000000.0):
		return _failure("damage")
	for previous: Dictionary in _state.events:
		if previous.kind == "damage" and previous.payload.fact_id == payload.fact_id:
			return _failure("duplicate_damage")
	for row: Dictionary in _state.pillars + _state.cores:
		if row.id != payload.construct_id:
			continue
		if row.broken or bool(row.get("debris", false)):
			return _failure("retired_construct")
		var amount := minf(float(row.current_hp), float(payload.amount))
		row.current_hp -= amount
		row.broken = row.current_hp == 0.0
		var retained := event.duplicate(true)
		retained.payload.amount = amount
		_state.events.append(retained)
		var core_break: bool = row.recipe_id == "void_plane_core" and row.broken
		if core_break:
			_state.core_break_claims.append({"fact_id": str(payload.fact_id), "core_id": str(row.id), "runtime_frame": int(event.runtime_frame), "round": int(row.round), "body_damage": 100.0})
			_state.exposure_through_frame = maxi(int(_state.exposure_through_frame), int(event.runtime_frame) + 59)
			if _state.cores.all(func(core: Dictionary): return core.broken):
				_state.round_completed_frame = int(event.runtime_frame)
				_state.exposure_through_frame = maxi(int(_state.exposure_through_frame), int(event.runtime_frame) + 119)
		return {"ok": true, "amount": amount, "broken": bool(row.broken), "body_damage": 100.0 if core_break else 0.0, "interrupt_denial": core_break, "exposure_through_frame": int(_state.exposure_through_frame)}
	return _failure("unknown_construct")


func _accept_heal_event(event: Dictionary) -> Dictionary:
	var payload: Dictionary = event.payload
	if not player_heal_pending() or not Contract.exact_fields(payload, ["run_id", "player_source_id", "maximum_hp", "amount", "alive"]) or payload.run_id != _state.identity.run_id or not _id(payload.player_source_id) or not Contract.number_in_range(payload.maximum_hp, 1.0, 1000000.0) or not Contract.number_in_range(payload.amount, 0.0, float(payload.maximum_hp) * 0.3) or typeof(payload.alive) != TYPE_BOOL or not payload.alive:
		return _failure("player_heal")
	_state.player_heal = {"player_source_id": str(payload.player_source_id), "runtime_frame": int(event.runtime_frame), "maximum_hp": float(payload.maximum_hp), "amount": float(payload.amount)}
	_state.events.append(event.duplicate(true))
	return {"ok": true}


func _seek(frame: int) -> void:
	_state.runtime_frame = frame
	if _state.phase_index == 2 and _state.rounds_started == 1 and int(_state.round_completed_frame) >= 0 and frame >= int(_state.round_completed_frame) + 600:
		_start_round(2)


func _start_round(round_index: int) -> void:
	_state.rounds_started = round_index
	_state.round_completed_frame = -1
	var cores: Array[Dictionary] = []
	for slot: int in range(4):
		cores.append({"id": "void_plane_core:%d:%d" % [round_index, slot], "recipe_id": "void_plane_core", "slot": slot, "round": round_index, "position": _point(CORE_POSITIONS[slot]), "radius_px": 12.0, "max_hp": 100.0, "current_hp": 100.0, "broken": false})
	_state.cores = cores


static func _id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 128


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


static func _failure(code: String) -> Dictionary:
	return {"ok": false, "error": "VOID_ARENA_" + code.to_upper()}
