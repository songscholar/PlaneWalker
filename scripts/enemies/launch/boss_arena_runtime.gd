class_name BossArenaRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const HISTORICAL_FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "covers", "damage_claims"]
const FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "covers", "damage_claims", "walls", "wall_claims"]
const COVER_FIELDS := ["id", "recipe_id", "slot", "position", "radius_px", "max_hp", "current_hp", "broken"]
const WALL_FIELDS := ["id", "recipe_id", "slot", "attack_generation", "spawn_frame", "position", "direction", "radius_px", "length_px", "max_hp", "current_hp", "broken", "lifetime_frames", "age", "expired"]
const WALL_CLAIM_FIELDS := ["attack_generation", "runtime_frame", "bounds", "geometry"]
const GEOMETRY_FIELDS := ["hostile_source_id", "attack_generation", "shape", "origin", "aim_direction", "target_point", "summon_slots", "radius", "length", "active_from_frame", "active_through_frame"]
const FACT_FIELDS := ["fact_id", "run_id", "owner_source_id", "construct_id", "runtime_frame", "amount"]
const CLAIM_FIELDS := ["fact_id", "construct_id", "runtime_frame", "amount"]
const MAX_CLAIMS := 512
const MAX_WALL_CASTS := 128
const POSITIONS := [Vector2(160.0, 120.0), Vector2(480.0, 120.0), Vector2(160.0, 240.0), Vector2(480.0, 240.0)]
var _state: Dictionary = {}
var _initial: Dictionary = {}


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	_state.clear()
	_initial.clear()
	var verified := Definition.new().configure_runtime_projection(definition)
	if not verified.ok or definition.id != "ruin_king" or not Contract.exact_fields(identity, ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]) or not _id(identity.run_id) or not _id(identity.hostile_source_id) or not Contract.integer_in_range(identity.runtime_frame, 0, 2147447646):
		return _failure("configuration")
	var recipe: Dictionary = verified.definition.arena.constructs[0]
	var covers: Array[Dictionary] = []
	for slot: int in range(4):
		covers.append({"id": "%s:%d" % [recipe.id, slot], "recipe_id": str(recipe.id), "slot": slot, "position": {"x": POSITIONS[slot].x, "y": POSITIONS[slot].y}, "radius_px": float(recipe.radius_px), "max_hp": float(recipe.max_hp), "current_hp": float(recipe.max_hp), "broken": false})
	_state = {"schema_version": 2, "definition_digest": JSON.stringify(verified.definition.arena, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false, "covers": covers, "damage_claims": [], "walls": [], "wall_claims": []}
	_initial = _state.duplicate(true)
	return {"ok": true, "snapshot": snapshot()}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func cover_snapshot(id: String) -> Dictionary:
	for cover: Dictionary in _state.get("covers", []):
		if cover.id == id:
			return cover.duplicate(true)
	return {}


func wall_snapshot(id: String) -> Dictionary:
	for wall: Dictionary in _state.get("walls", []):
		if wall.id == id:
			return wall.duplicate(true)
	return {}


func accept_wall_request(request: Dictionary, bounds: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or request.get("action_id") != "guardian_wall" or request.get("handler_id") != "wall" or request.get("run_id") != _state.identity.run_id or request.get("hostile_source_id") != _state.identity.hostile_source_id or request.get("runtime_frame") != _state.runtime_frame or request.get("parameters") != {"hit_points": 150.0, "lifetime_frames": 600, "gap_px": 32.0} or not request.get("geometry") is Array or _state.wall_claims.size() >= MAX_WALL_CASTS:
		return _failure("wall_request")
	var claim := {"attack_generation": request.get("attack_generation"), "runtime_frame": request.runtime_frame, "bounds": bounds.duplicate(true), "geometry": request.get("geometry", []).duplicate(true)}
	if not _valid_wall_claim(claim, int(_state.runtime_frame)):
		return _failure("wall_geometry")
	for previous: Dictionary in _state.wall_claims:
		if previous.attack_generation == claim.attack_generation:
			return _failure("wall_duplicate")
	_state.wall_claims.append(claim)
	for slot: int in range(2):
		_state.walls.append(_initial_wall(claim, slot))
	return {"ok": true}


func accept_damage_fact(fact: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.exact_fields(fact, FACT_FIELDS) or not _id(fact.fact_id) or fact.run_id != _state.identity.run_id or fact.owner_source_id != _state.identity.hostile_source_id or typeof(fact.construct_id) != TYPE_STRING or typeof(fact.runtime_frame) != TYPE_INT or fact.runtime_frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or not Contract.number_in_range(fact.amount, 0.000001, 1000000.0) or _state.damage_claims.size() >= MAX_CLAIMS:
		return _failure("damage_fact")
	for claim: Dictionary in _state.damage_claims:
		if claim.fact_id == fact.fact_id:
			return _failure("duplicate")
	for cover: Dictionary in _state.covers + _state.walls:
		if cover.id != fact.construct_id:
			continue
		if cover.broken or bool(cover.get("expired", false)):
			return _failure("retired_cover")
		var amount := minf(float(cover.current_hp), float(fact.amount))
		cover.current_hp = maxf(0.0, float(cover.current_hp) - amount)
		cover.broken = cover.current_hp == 0.0
		_state.damage_claims.append({"fact_id": str(fact.fact_id), "construct_id": str(cover.id), "runtime_frame": int(fact.runtime_frame), "amount": amount})
		return {"ok": true, "amount": amount, "broken": bool(cover.broken)}
	return _failure("unknown_cover")


func advance_frame(frame: int) -> bool:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame) + 1:
		return false
	_state.runtime_frame = frame
	for wall: Dictionary in _state.walls:
		wall.age = mini(frame - int(wall.spawn_frame), int(wall.lifetime_frames))
		wall.expired = wall.age == wall.lifetime_frames
	return true


func retire() -> void:
	if not _state.is_empty():
		_state.terminal = true


func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
	if _initial.is_empty() or not Contract.exact_fields(value, FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 2 or value.definition_digest != _initial.definition_digest or value.identity != _initial.identity or not Contract.integer_in_range(value.runtime_frame, int(_initial.runtime_frame), 2147483046) or typeof(value.terminal) != TYPE_BOOL or not value.covers is Array or value.covers.size() != 4 or not value.damage_claims is Array or value.damage_claims.size() > MAX_CLAIMS or not value.wall_claims is Array or value.wall_claims.size() > MAX_WALL_CASTS or not value.walls is Array or value.walls.size() != value.wall_claims.size() * 2:
		return false
	var initial_walls: Dictionary = {}
	var generations: Dictionary = {}
	for claim: Variant in value.wall_claims:
		if not claim is Dictionary or not _valid_wall_claim(claim, int(value.runtime_frame)) or generations.has(claim.attack_generation) or claim.runtime_frame < int(_initial.runtime_frame):
			return false
		for fact: Dictionary in claim.geometry:
			if fact.hostile_source_id != value.identity.hostile_source_id:
				return false
		generations[claim.attack_generation] = true
		for slot: int in range(2):
			var wall := _initial_wall(claim, slot)
			initial_walls[wall.id] = wall
	var losses: Dictionary = {}
	var seen: Dictionary = {}
	for row: Variant in value.damage_claims:
		if not row is Dictionary or not Contract.exact_fields(row, CLAIM_FIELDS) or not _id(row.fact_id) or seen.has(row.fact_id) or typeof(row.construct_id) != TYPE_STRING or not Contract.number_in_range(row.amount, 0.000001, 150.0) or not Contract.integer_in_range(row.runtime_frame, int(_initial.runtime_frame), int(value.runtime_frame) + (0 if accepted_boundary else 1)) or cover_snapshot(str(row.construct_id)).is_empty() and not initial_walls.has(row.construct_id):
			return false
		if initial_walls.has(row.construct_id) and (row.runtime_frame < initial_walls[row.construct_id].spawn_frame or row.runtime_frame >= initial_walls[row.construct_id].spawn_frame + 600):
			return false
		seen[row.fact_id] = true
		losses[row.construct_id] = float(losses.get(row.construct_id, 0.0)) + float(row.amount)
	for index: int in range(4):
		var row: Variant = value.covers[index]
		var initial: Dictionary = _initial.covers[index]
		if not row is Dictionary or not Contract.exact_fields(row, COVER_FIELDS):
			return false
		for field: String in ["id", "recipe_id", "slot", "position", "radius_px", "max_hp"]:
			if row[field] != initial[field]:
				return false
		var loss := float(losses.get(row.id, 0.0))
		if loss > float(row.max_hp) or not Contract.number_in_range(row.current_hp, 0.0, row.max_hp) or not is_equal_approx(float(row.current_hp), float(row.max_hp) - loss) or typeof(row.broken) != TYPE_BOOL or row.broken != (float(row.current_hp) == 0.0):
			return false
	var wall_index := 0
	for claim: Dictionary in value.wall_claims:
		for slot: int in range(2):
			var row: Variant = value.walls[wall_index]
			var initial := _initial_wall(claim, slot)
			wall_index += 1
			if not row is Dictionary or not Contract.exact_fields(row, WALL_FIELDS):
				return false
			for field: String in WALL_FIELDS:
				if field not in ["current_hp", "broken", "age", "expired"] and row[field] != initial[field]:
					return false
			var loss := float(losses.get(row.id, 0.0))
			if loss > 150.0 or not Contract.number_in_range(row.current_hp, 0.0, 150.0) or not is_equal_approx(float(row.current_hp), 150.0 - loss) or typeof(row.broken) != TYPE_BOOL or row.broken != (float(row.current_hp) == 0.0) or typeof(row.age) != TYPE_INT or row.age != mini(int(value.runtime_frame) - int(row.spawn_frame), 600) or typeof(row.expired) != TYPE_BOOL or row.expired != (row.age == 600):
				return false
	return true


func normalize_snapshot(value: Dictionary) -> Dictionary:
	if value.get("schema_version") == 2:
		return value.duplicate(true) if can_restore_snapshot(value) else {}
	if value.get("schema_version") != 1 or typeof(value.schema_version) != TYPE_INT or not Contract.exact_fields(value, HISTORICAL_FIELDS):
		return {}
	var normalized := value.duplicate(true)
	normalized.schema_version = 2
	normalized.walls = []
	normalized.wall_claims = []
	return normalized if can_restore_snapshot(normalized) else {}


static func _valid_wall_claim(claim: Dictionary, frame: int) -> bool:
	if not Contract.exact_fields(claim, WALL_CLAIM_FIELDS) or not Contract.integer_in_range(claim.attack_generation, 1, 2147483046) or not Contract.integer_in_range(claim.runtime_frame, 0, frame) or not claim.bounds is Dictionary or not Contract.exact_fields(claim.bounds, ["x", "y", "width", "height"]) or not claim.geometry is Array or claim.geometry.size() != 2:
		return false
	for field: String in ["x", "y"]:
		if not Contract.number_in_range(claim.bounds[field], -1000000.0, 1000000.0):
			return false
	if claim.bounds.width != 640.0 or claim.bounds.height != 360.0:
		return false
	var direction := Vector2.ZERO
	for slot: int in range(2):
		var fact: Variant = claim.geometry[slot]
		if not fact is Dictionary or not Contract.exact_fields(fact, GEOMETRY_FIELDS) or fact.shape != "line" or fact.radius != 6.0 or fact.length != 64.0 or fact.attack_generation != claim.attack_generation + slot or not Contract.valid_point(fact.origin) or not Contract.valid_point(fact.aim_direction, 1.0) or not Contract.valid_point(fact.target_point) or fact.summon_slots != [] or not _id(fact.hostile_source_id) or not Contract.integer_in_range(fact.active_from_frame, 0, claim.runtime_frame) or not Contract.integer_in_range(fact.active_through_frame, claim.runtime_frame, 2147483046):
			return false
		var aim := Vector2(float(fact.aim_direction.x), float(fact.aim_direction.y))
		if not is_equal_approx(aim.length_squared(), 1.0):
			return false
		if slot == 0:
			direction = aim
		elif aim != direction or not Vector2(float(fact.origin.x), float(fact.origin.y)).is_equal_approx(Vector2(float(claim.geometry[0].origin.x), float(claim.geometry[0].origin.y)) + direction * 96.0):
			return false
		var origin := Vector2(float(fact.origin.x) - float(claim.bounds.x), float(fact.origin.y) - float(claim.bounds.y))
		var endpoint := origin + aim * 64.0
		for point: Vector2 in [origin, endpoint]:
			if point.x < 6.0 or point.x > 634.0 or point.y < 6.0 or point.y > 354.0:
				return false
	return true


static func _initial_wall(claim: Dictionary, slot: int) -> Dictionary:
	var fact: Dictionary = claim.geometry[slot]
	var direction := Vector2(float(fact.aim_direction.x), float(fact.aim_direction.y))
	var center := Vector2(float(fact.origin.x) - float(claim.bounds.x), float(fact.origin.y) - float(claim.bounds.y)) + direction * 32.0
	return {"id": "guardian_wall:%d:%d" % [int(claim.attack_generation), slot], "recipe_id": "guardian_wall", "slot": slot, "attack_generation": int(claim.attack_generation), "spawn_frame": int(claim.runtime_frame), "position": {"x": center.x, "y": center.y}, "direction": fact.aim_direction.duplicate(true), "radius_px": 6.0, "length_px": 64.0, "max_hp": 150.0, "current_hp": 150.0, "broken": false, "lifetime_frames": 600, "age": 0, "expired": false}


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


func initial_at_frame(frame: int, terminal: bool) -> Dictionary:
	if _initial.is_empty() or frame < int(_initial.runtime_frame):
		return {}
	var value := _initial.duplicate(true)
	value.runtime_frame = frame
	value.terminal = terminal
	return value


static func _id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 128


static func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"BOSS_ARENA_INVALID", "field": field}
