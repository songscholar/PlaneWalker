class_name ForestArenaRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const HISTORICAL_FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "roots", "damage_claims", "phase_retirement", "exposure_through_frame"]
const FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "roots", "damage_claims", "phase_retirement", "exposure_through_frame", "arena_origin", "sweep_claims", "historical_sweep_generation"]
const ROOT_FIELDS := ["id", "recipe_id", "slot", "position", "radius_px", "max_hp", "current_hp", "broken", "retired"]
const FACT_FIELDS := ["fact_id", "run_id", "owner_source_id", "construct_id", "runtime_frame", "amount"]
const CLAIM_FIELDS := ["fact_id", "construct_id", "runtime_frame", "amount"]
const SWEEP_FIELDS := ["attack_generation", "runtime_frame", "root_id", "target_position", "target_id", "damage_claim_count", "phase_retirement_applied"]
const POSITIONS := [Vector2(112, 104), Vector2(240, 104), Vector2(400, 104), Vector2(528, 104), Vector2(176, 256), Vector2(464, 256)]
const MAX_FRAME := 2147447646
var _state: Dictionary = {}
var _initial: Dictionary = {}


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	_state.clear()
	_initial.clear()
	var parsed := Definition.new().configure_runtime_projection(definition)
	if not parsed.ok or definition.id != "forest_heart" or not Contract.exact_fields(identity, ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]) or not _id(identity.run_id) or not _id(identity.hostile_source_id) or not Contract.integer_in_range(identity.runtime_frame, 0, MAX_FRAME):
		return _failure("configuration")
	var recipe: Dictionary = parsed.definition.arena.constructs[0]
	if recipe.id != "forest_root" or recipe.count != 6 or recipe.max_hp != 100.0 or recipe.radius_px != 12.0 or parsed.definition.mechanisms.root_break_exposure_frames != 45 or parsed.definition.mechanisms.p2_root_retirement_count != 3:
		return _failure("root_recipe")
	var roots: Array[Dictionary] = []
	for slot: int in range(6):
		roots.append({"id": "forest_root:%d" % slot, "recipe_id": "forest_root", "slot": slot, "position": {"x": POSITIONS[slot].x, "y": POSITIONS[slot].y}, "radius_px": 12.0, "max_hp": 100.0, "current_hp": 100.0, "broken": false, "retired": false})
	_state = {"schema_version": 2, "definition_digest": JSON.stringify(parsed.definition.arena, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false, "roots": roots, "damage_claims": [], "phase_retirement": {}, "exposure_through_frame": int(identity.runtime_frame) - 1, "arena_origin": {"x": 0.0, "y": 0.0}, "sweep_claims": [], "historical_sweep_generation": 0}
	_initial = snapshot()
	return {"ok": true, "snapshot": snapshot()}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func is_exposed() -> bool:
	return not _state.is_empty() and not _state.terminal and int(_state.runtime_frame) <= int(_state.exposure_through_frame)


func bind_origin(origin: Dictionary) -> bool:
	if _state.is_empty() or not Contract.valid_point(origin) or _state.terminal:
		return false
	if origin != _state.arena_origin and (int(_state.runtime_frame) != int(_initial.runtime_frame) or not _state.sweep_claims.is_empty() or int(_state.historical_sweep_generation) != 0):
		return false
	_state.arena_origin = origin.duplicate(true)
	return true


func select_sweep_root(target: Dictionary) -> Dictionary:
	return {} if _state.is_empty() or _state.terminal or not Contract.valid_point(target) else _select_root(_state.roots, target, _state.arena_origin)


func accept_sweep_commit(action: Dictionary) -> bool:
	if _state.is_empty() or _state.terminal or _state.sweep_claims.size() >= 128 or action.get("action_id") != "matriarch_root_sweep" or action.get("phase") != "WARNING" or action.get("commit_frame") != _state.runtime_frame or not action.get("geometry_generations") is Array or action.geometry_generations.size() != 1 or not Contract.integer_in_range(action.geometry_generations[0], int(_state.identity.next_generation_floor), MAX_FRAME) or not Contract.valid_point(action.get("committed_target")) or not _id(action.get("target_id")):
		return false
	var selected := select_sweep_root(action.committed_target)
	if selected.is_empty() or action.get("committed_origin") != selected.position:
		return false
	if not _state.sweep_claims.is_empty() and int(action.geometry_generations[0]) <= int(_state.sweep_claims.back().attack_generation):
		return false
	_state.sweep_claims.append({"attack_generation": int(action.geometry_generations[0]), "runtime_frame": int(_state.runtime_frame), "root_id": str(selected.id), "target_position": action.committed_target.duplicate(true), "target_id": str(action.target_id), "damage_claim_count": _state.damage_claims.size(), "phase_retirement_applied": not _state.phase_retirement.is_empty()})
	return true


func sweep_root_id(action: Dictionary) -> String:
	if action.get("action_id") != "matriarch_root_sweep" or not action.get("geometry_generations") is Array or action.geometry_generations.size() != 1:
		return ""
	for claim: Dictionary in _state.get("sweep_claims", []):
		if claim.attack_generation == action.geometry_generations[0]:
			return str(claim.root_id)
	return ""


func can_restore_sweep_action(action: Dictionary, value: Dictionary, historical_origin: Dictionary) -> bool:
	if action.action_id != "matriarch_root_sweep":
		return true
	if action.geometry_generations.size() != 1:
		return false
	var generation: int = int(action.geometry_generations[0])
	if generation == int(value.historical_sweep_generation):
		return Contract.valid_point(historical_origin) and action.committed_origin == Actions._quantized_point(Vector2(float(historical_origin.x), float(historical_origin.y)))
	for claim: Dictionary in value.sweep_claims:
		if claim.attack_generation != generation:
			continue
		for row: Dictionary in value.roots:
			if row.id == claim.root_id:
				return not row.broken and not row.retired and action.commit_frame == claim.runtime_frame and action.committed_target == claim.target_position and action.target_id == claim.target_id and action.committed_origin == _world_root(row, value.arena_origin)
	return false


func accept_damage_fact(fact: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.exact_fields(fact, FACT_FIELDS) or not _id(fact.fact_id) or fact.run_id != _state.identity.run_id or fact.owner_source_id != _state.identity.hostile_source_id or typeof(fact.construct_id) != TYPE_STRING or not Contract.integer_in_range(fact.runtime_frame, int(_state.runtime_frame), mini(int(_state.runtime_frame) + 1, MAX_FRAME)) or not Contract.number_in_range(fact.amount, 0.000001, 1000000.0) or _state.damage_claims.size() >= 512:
		return _failure("damage_fact")
	for claim: Dictionary in _state.damage_claims:
		if claim.fact_id == fact.fact_id:
			return _failure("duplicate_damage")
	if not _state.damage_claims.is_empty() and int(fact.runtime_frame) < int(_state.damage_claims.back().runtime_frame):
		return _failure("damage_order")
	for row: Dictionary in _state.roots:
		if row.id != fact.construct_id:
			continue
		if row.broken or row.retired:
			return _failure("inactive_root")
		var amount := minf(float(row.current_hp), float(fact.amount))
		row.current_hp -= amount
		row.broken = row.current_hp == 0.0
		_state.damage_claims.append({"fact_id": str(fact.fact_id), "construct_id": str(row.id), "runtime_frame": int(fact.runtime_frame), "amount": amount})
		if row.broken:
			_state.exposure_through_frame = maxi(int(_state.exposure_through_frame), int(fact.runtime_frame) + 44)
		return {"ok": true, "amount": amount, "broken": row.broken}
	return _failure("unknown_root")


func accept_phase_retirement(frame: int) -> Dictionary:
	if _state.is_empty() or _state.terminal or not _state.phase_retirement.is_empty() or not Contract.integer_in_range(frame, int(_state.runtime_frame), mini(int(_state.runtime_frame) + 1, MAX_FRAME)):
		return _failure("phase_retirement")
	var ids := _retirement_ids(_state, frame)
	_state.phase_retirement = {"runtime_frame": frame, "root_ids": ids}
	for row: Dictionary in _state.roots:
		row.retired = ids.has(row.id)
	return {"ok": true, "root_ids": ids.duplicate()}


func advance_frame(frame: int) -> bool:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame) + 1 or frame > MAX_FRAME:
		return false
	_state.runtime_frame = frame
	return true


func retire() -> void:
	if not _state.is_empty():
		_state.terminal = true


func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
	if _initial.is_empty() or not Contract.exact_fields(value, FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 2 or value.definition_digest != _initial.definition_digest or value.identity != _initial.identity or not Contract.integer_in_range(value.runtime_frame, int(_initial.runtime_frame), MAX_FRAME) or typeof(value.terminal) != TYPE_BOOL or not value.roots is Array or value.roots.size() != 6 or not value.damage_claims is Array or value.damage_claims.size() > 512 or not value.phase_retirement is Dictionary or not Contract.valid_point(value.arena_origin) or not value.sweep_claims is Array or value.sweep_claims.size() > 128 or not Contract.integer_in_range(value.historical_sweep_generation, 0, MAX_FRAME):
		return false
	var roots: Dictionary = {}
	for slot: int in range(6):
		var row: Variant = value.roots[slot]
		if not row is Dictionary or not Contract.exact_fields(row, ROOT_FIELDS):
			return false
		for field: String in ["id", "recipe_id", "slot", "position", "radius_px", "max_hp"]:
			if row[field] != _initial.roots[slot][field]:
				return false
		roots[row.id] = row
	var retired: Array = []
	if not value.phase_retirement.is_empty():
		if not Contract.exact_fields(value.phase_retirement, ["runtime_frame", "root_ids"]) or not Contract.integer_in_range(value.phase_retirement.runtime_frame, int(_initial.runtime_frame), int(value.runtime_frame) + (0 if accepted_boundary else 1)) or not value.phase_retirement.root_ids is Array or value.phase_retirement.root_ids != _retirement_ids(value, int(value.phase_retirement.runtime_frame)):
			return false
		retired = value.phase_retirement.root_ids
	var losses: Dictionary = {}
	var seen: Dictionary = {}
	var exposure: int = int(_initial.runtime_frame) - 1
	var previous_damage_frame: int = int(_initial.runtime_frame)
	for fact: Variant in value.damage_claims:
		if not fact is Dictionary or not Contract.exact_fields(fact, CLAIM_FIELDS) or not _id(fact.fact_id) or seen.has(fact.fact_id) or typeof(fact.construct_id) != TYPE_STRING or not roots.has(fact.construct_id) or not Contract.number_in_range(fact.amount, 0.000001, 100.0) or not Contract.integer_in_range(fact.runtime_frame, int(_initial.runtime_frame), int(value.runtime_frame) + (0 if accepted_boundary else 1)):
			return false
		if retired.has(fact.construct_id) and fact.runtime_frame > value.phase_retirement.runtime_frame:
			return false
		if fact.runtime_frame < previous_damage_frame:
			return false
		previous_damage_frame = int(fact.runtime_frame)
		seen[fact.fact_id] = true
		losses[fact.construct_id] = float(losses.get(fact.construct_id, 0.0)) + float(fact.amount)
		if losses[fact.construct_id] == 100.0:
			exposure = maxi(exposure, int(fact.runtime_frame) + 44)
	for row: Dictionary in value.roots:
		var loss := float(losses.get(row.id, 0.0))
		if loss > 100.0 or not Contract.number_in_range(row.current_hp, 0.0, 100.0) or not is_equal_approx(float(row.current_hp), 100.0 - loss) or typeof(row.broken) != TYPE_BOOL or row.broken != (loss == 100.0) or typeof(row.retired) != TYPE_BOOL or row.retired != retired.has(row.id):
			return false
	return typeof(value.exposure_through_frame) == TYPE_INT and value.exposure_through_frame == exposure and _valid_sweep_claims(value)


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


func normalize_snapshot(value: Dictionary, historical_action: Dictionary = {}) -> Dictionary:
	if value.get("schema_version") == 2:
		return value.duplicate(true) if can_restore_snapshot(value) else {}
	if typeof(value.get("schema_version")) != TYPE_INT or value.get("schema_version") != 1 or not Contract.exact_fields(value, HISTORICAL_FIELDS):
		return {}
	var normalized := value.duplicate(true)
	normalized.schema_version = 2
	normalized.arena_origin = _state.arena_origin.duplicate(true)
	normalized.sweep_claims = []
	normalized.historical_sweep_generation = _historical_sweep(historical_action)
	return normalized if can_restore_snapshot(normalized) else {}


func initial_at_frame(frame: int, terminal: bool, phase_index: int = 0, historical_action: Dictionary = {}) -> Dictionary:
	var value := _initial.duplicate(true)
	value.runtime_frame = frame
	value.terminal = terminal
	value.arena_origin = _state.arena_origin.duplicate(true)
	value.historical_sweep_generation = _historical_sweep(historical_action)
	if phase_index > 0:
		var ids := _retirement_ids(value, frame)
		value.phase_retirement = {"runtime_frame": frame, "root_ids": ids}
		for row: Dictionary in value.roots:
			row.retired = ids.has(row.id)
	return value if can_restore_snapshot(value, true) else {}


func _valid_sweep_claims(value: Dictionary) -> bool:
	if int(value.historical_sweep_generation) != 0 and int(value.historical_sweep_generation) < int(value.identity.next_generation_floor):
		return false
	var previous_generation: int = maxi(int(value.identity.next_generation_floor) - 1, int(value.historical_sweep_generation))
	var previous_frame: int = int(_initial.runtime_frame)
	var consumed_damage := 0
	var phase_applied := false
	var rows: Array = _initial.roots.duplicate(true)
	for candidate: Variant in value.sweep_claims:
		if not candidate is Dictionary or not Contract.exact_fields(candidate, SWEEP_FIELDS):
			return false
		var claim := candidate as Dictionary
		if not Contract.integer_in_range(claim.attack_generation, previous_generation + 1, MAX_FRAME) or not Contract.integer_in_range(claim.runtime_frame, previous_frame, int(value.runtime_frame)) or not Contract.valid_point(claim.target_position) or claim.target_position != Actions._quantized_point(Vector2(float(claim.target_position.x), float(claim.target_position.y))) or not _id(claim.target_id) or not Contract.integer_in_range(claim.damage_claim_count, consumed_damage, value.damage_claims.size()) or typeof(claim.phase_retirement_applied) != TYPE_BOOL or phase_applied and not claim.phase_retirement_applied:
			return false
		# Replay ordered damage prefixes once rather than rebuilding every cast's history.
		while consumed_damage < int(claim.damage_claim_count):
			var fact: Dictionary = value.damage_claims[consumed_damage]
			if fact.runtime_frame > claim.runtime_frame:
				return false
			for row: Dictionary in rows:
				if row.id == fact.construct_id:
					row.current_hp -= float(fact.amount)
					row.broken = row.current_hp <= 0.0
			consumed_damage += 1
		if consumed_damage < value.damage_claims.size() and value.damage_claims[consumed_damage].runtime_frame < claim.runtime_frame:
			return false
		if claim.phase_retirement_applied:
			if value.phase_retirement.is_empty() or value.phase_retirement.runtime_frame > claim.runtime_frame:
				return false
			for row: Dictionary in rows:
				row.retired = value.phase_retirement.root_ids.has(row.id)
		elif not value.phase_retirement.is_empty() and value.phase_retirement.runtime_frame < claim.runtime_frame:
			return false
		phase_applied = claim.phase_retirement_applied
		var selected := _select_root(rows, claim.target_position, value.arena_origin)
		if selected.is_empty() or claim.root_id != selected.id:
			return false
		previous_generation = int(claim.attack_generation)
		previous_frame = int(claim.runtime_frame)
	return true


static func _select_root(rows: Array, target: Dictionary, origin: Dictionary) -> Dictionary:
	var quantized := Actions._quantized_point(Vector2(float(target.x), float(target.y)))
	var point := Vector2(float(quantized.x), float(quantized.y))
	var best := {}
	var best_distance := INF
	for row: Dictionary in rows:
		if row.broken or row.retired:
			continue
		var position := _world_root(row, origin)
		var distance := Vector2(float(position.x), float(position.y)).distance_squared_to(point)
		if distance <= 96.0 * 96.0 and distance < best_distance:
			best = {"id": str(row.id), "position": position}
			best_distance = distance
	return best


static func _world_root(row: Dictionary, origin: Dictionary) -> Dictionary:
	return Actions._quantized_point(Vector2(float(origin.x) + float(row.position.x), float(origin.y) + float(row.position.y)))


static func _historical_sweep(action: Dictionary) -> int:
	return int(action.geometry_generations[0]) if action.get("action_id") == "matriarch_root_sweep" and action.get("geometry_generations") is Array and action.geometry_generations.size() == 1 and action.geometry_generations[0] is int else 0


static func _retirement_ids(value: Dictionary, frame: int) -> Array[String]:
	var damage: Dictionary = {}
	for fact: Variant in value.damage_claims:
		if fact is Dictionary and fact.get("construct_id") is String and fact.get("runtime_frame") is int and Contract.number_in_range(fact.get("amount"), 0.000001, 100.0) and fact.runtime_frame <= frame:
			damage[fact.construct_id] = float(damage.get(fact.construct_id, 0.0)) + float(fact.amount)
	var ids: Array[String] = []
	for row: Dictionary in value.roots:
		if float(damage.get(row.id, 0.0)) < 100.0 and ids.size() < 3:
			ids.append(str(row.id))
	return ids


static func _id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 256 and value.strip_edges() == value


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "code": &"FOREST_ARENA_INVALID", "context": {"reason": reason}}
