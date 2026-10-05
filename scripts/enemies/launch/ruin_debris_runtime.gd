class_name RuinDebrisRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const FIELDS := ["schema_version", "run_id", "initial_frame", "runtime_frame", "recipe", "rows", "damage_claims", "retirements"]
const RECIPE_FIELDS := ["max_hp", "lifetime_frames", "count_cap", "radius_px"]
const EVENT_FIELDS := ["run_id", "source_id", "generation", "hit_index", "runtime_frame", "position", "bounds"]
const ROW_FIELDS := ["id", "event", "position", "phase", "activated_frame", "age", "current_hp"]
const DAMAGE_FIELDS := ["fact_id", "run_id", "construct_id", "runtime_frame", "amount"]
const MAX_ROWS := 4096
const MAX_FRAME := 2147483647 - Contract.MAX_FRAME
var _state: Dictionary = {}


func configure(run_id: String, frame: int, recipe: Dictionary) -> bool:
	if not _id(run_id) or not Contract.integer_in_range(frame, 0, MAX_FRAME) or not Contract.exact_fields(recipe, RECIPE_FIELDS) or recipe.max_hp != 20.0 or recipe.lifetime_frames != 480 or recipe.count_cap != 4 or recipe.radius_px != 12.0:
		return false
	_state = {"schema_version": 1, "run_id": run_id, "initial_frame": frame, "runtime_frame": frame, "recipe": recipe.duplicate(true), "rows": [], "damage_claims": [], "retirements": {}}
	return true


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func active_count() -> int:
	return _active_count(_state.get("rows", []))


func advance_frame(frame: int, impacts: Array, occupied: Dictionary, foreign_constructs: int, retired_sources: Array) -> Dictionary:
	if _state.is_empty() or frame != int(_state.runtime_frame) + 1 or not Contract.integer_in_range(frame, 0, MAX_FRAME) or not Contract.integer_in_range(foreign_constructs, 0, 8) or impacts.size() > 32 or not _valid_occupied(occupied):
		return _failure("frame_or_context")
	var next := snapshot()
	next.runtime_frame = frame
	for source: Variant in retired_sources:
		if not _id(source):
			return _failure("retired_source")
		if not next.retirements.has(source):
			next.retirements[source] = frame
	for row: Dictionary in next.rows:
		if row.activated_frame >= 0:
			row.age = mini(mini(frame, int(next.retirements.get(row.event.source_id, frame))) - int(row.activated_frame), int(next.recipe.lifetime_frames))
		row.phase = _phase(row, next)
	var seen: Dictionary = {}
	for row: Dictionary in next.rows:
		seen[row.id] = true
	for value: Variant in impacts:
		if not value is Dictionary or not _valid_event(value, next) or value.runtime_frame != frame:
			return _failure("impact")
		var id := _event_id(value)
		if seen.has(id) or next.rows.size() >= MAX_ROWS:
			return _failure("duplicate_or_capacity")
		seen[id] = true
		next.rows.append({"id": id, "event": value.duplicate(true), "position": {}, "phase": "RETIRED" if next.retirements.has(value.source_id) else "PENDING", "activated_frame": -1, "age": 0, "current_hp": float(next.recipe.max_hp)})
	var available := mini(int(next.recipe.count_cap), 8 - foreign_constructs) - _active_count(next.rows)
	if available < 0:
		return _failure("shared_construct_capacity")
	for row: Dictionary in next.rows:
		if row.phase != "PENDING" or available == 0:
			continue
		for point: Vector2 in candidate_positions(row.event.bounds, row.event.position):
			if not _position_clear(point, occupied, next.rows, float(next.recipe.radius_px)):
				continue
			row.position = {"x": point.x, "y": point.y}
			row.activated_frame = frame
			row.phase = "ACTIVE"
			available -= 1
			break
	_state = next
	return {"ok": true}


func accept_damage_fact(fact: Dictionary) -> Dictionary:
	if _state.is_empty() or not Contract.exact_fields(fact, DAMAGE_FIELDS) or not _id(fact.fact_id) or fact.run_id != _state.run_id or typeof(fact.construct_id) != TYPE_STRING or not Contract.integer_in_range(fact.runtime_frame, int(_state.runtime_frame), int(_state.runtime_frame) + 1) or not Contract.number_in_range(fact.amount, 0.000001, 1000000.0) or _state.damage_claims.size() >= MAX_ROWS:
		return _failure("damage_fact")
	for claim: Dictionary in _state.damage_claims:
		if claim.fact_id == fact.fact_id:
			return _failure("duplicate_damage")
	for row: Dictionary in _state.rows:
		if row.id != fact.construct_id:
			continue
		if row.phase != "ACTIVE" or fact.runtime_frame >= int(row.activated_frame) + int(_state.recipe.lifetime_frames):
			return _failure("inactive_damage")
		var amount := minf(float(row.current_hp), float(fact.amount))
		row.current_hp -= amount
		if row.current_hp == 0.0:
			row.phase = "BROKEN"
		var accepted := fact.duplicate(true)
		accepted.amount = amount
		_state.damage_claims.append(accepted)
		return {"ok": true, "amount": amount}
	return _failure("unknown_construct")


func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or value.run_id != _state.run_id or value.initial_frame != _state.initial_frame or value.recipe != _state.recipe or not Contract.integer_in_range(value.runtime_frame, int(_state.initial_frame), MAX_FRAME) or not value.rows is Array or value.rows.size() > MAX_ROWS or not value.damage_claims is Array or value.damage_claims.size() > MAX_ROWS or not value.retirements is Dictionary or value.retirements.size() > MAX_ROWS:
		return false
	for source: Variant in value.retirements:
		if not _id(source) or not Contract.integer_in_range(value.retirements[source], int(value.initial_frame), int(value.runtime_frame)):
			return false
	var rows: Dictionary = {}
	var live_rows: Array[Dictionary] = []
	for candidate: Variant in value.rows:
		if not candidate is Dictionary or not Contract.exact_fields(candidate, ROW_FIELDS) or not candidate.event is Dictionary or not _valid_event(candidate.event, value) or candidate.id != _event_id(candidate.event) or rows.has(candidate.id) or not Contract.integer_in_range(candidate.activated_frame, -1, int(value.runtime_frame)) or not Contract.integer_in_range(candidate.age, 0, int(value.recipe.lifetime_frames)) or not Contract.number_in_range(candidate.current_hp, 0.0, float(value.recipe.max_hp)):
			return false
		if candidate.activated_frame == -1:
			if candidate.position != {} or candidate.age != 0 or candidate.current_hp != value.recipe.max_hp:
				return false
		else:
			if candidate.activated_frame < candidate.event.runtime_frame or not Contract.valid_point(candidate.position) or not candidate_positions(candidate.event.bounds, candidate.event.position).has(_vector(candidate.position)):
				return false
			var elapsed := mini(int(value.runtime_frame), int(value.retirements.get(candidate.event.source_id, value.runtime_frame))) - int(candidate.activated_frame)
			if elapsed < 0 or candidate.age != mini(elapsed, int(value.recipe.lifetime_frames)):
				return false
		if typeof(candidate.phase) != TYPE_STRING or candidate.phase != _phase(candidate, value):
			return false
		if candidate.phase == "ACTIVE":
			if not _position_clear(_vector(candidate.position), {}, live_rows, float(value.recipe.radius_px)):
				return false
			live_rows.append(candidate)
		rows[candidate.id] = candidate
	var losses: Dictionary = {}
	var seen: Dictionary = {}
	for fact: Variant in value.damage_claims:
		if not fact is Dictionary or not Contract.exact_fields(fact, DAMAGE_FIELDS) or not _id(fact.fact_id) or seen.has(fact.fact_id) or fact.run_id != value.run_id or typeof(fact.construct_id) != TYPE_STRING or not rows.has(fact.construct_id) or not Contract.number_in_range(fact.amount, 0.000001, float(value.recipe.max_hp)) or not Contract.integer_in_range(fact.runtime_frame, int(value.initial_frame), int(value.runtime_frame) + (0 if accepted_boundary else 1)):
			return false
		var row: Dictionary = rows[fact.construct_id]
		if row.activated_frame == -1 or fact.runtime_frame < row.activated_frame or fact.runtime_frame >= int(row.activated_frame) + int(value.recipe.lifetime_frames) or value.retirements.has(row.event.source_id) and fact.runtime_frame > value.retirements[row.event.source_id]:
			return false
		seen[fact.fact_id] = true
		losses[row.id] = float(losses.get(row.id, 0.0)) + float(fact.amount)
	for row: Dictionary in rows.values():
		var loss := float(losses.get(row.id, 0.0))
		if loss > float(value.recipe.max_hp) or not is_equal_approx(float(row.current_hp), float(value.recipe.max_hp) - loss):
			return false
	return _active_count(value.rows) <= int(value.recipe.count_cap)


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


static func candidate_positions(bounds: Dictionary, impact: Dictionary) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var origin := Vector2(float(bounds.x), float(bounds.y))
	for y: int in range(64, 289, 16):
		for x: int in range(64, 577, 16):
			if x > 284 and x < 356 or y > 144 and y < 216:
				continue
			result.append(origin + Vector2(x, y))
	var target := _vector(impact)
	result.sort_custom(func(a: Vector2, b: Vector2):
		var first := a.distance_squared_to(target)
		var second := b.distance_squared_to(target)
		return a.y < b.y or a.y == b.y and a.x < b.x if is_equal_approx(first, second) else first < second)
	return result


static func _phase(row: Dictionary, value: Dictionary) -> String:
	if value.retirements.has(row.event.source_id):
		return "RETIRED"
	if row.activated_frame == -1:
		return "PENDING"
	if row.current_hp == 0.0:
		return "BROKEN"
	return "EXPIRED" if row.age == value.recipe.lifetime_frames else "ACTIVE"


static func _valid_event(event: Dictionary, state: Dictionary) -> bool:
	if not Contract.exact_fields(event, EVENT_FIELDS) or event.run_id != state.run_id or not _id(event.source_id) or not Contract.integer_in_range(event.generation, 1, MAX_FRAME) or not Contract.integer_in_range(event.hit_index, 0, 5) or not Contract.integer_in_range(event.runtime_frame, int(state.initial_frame), int(state.runtime_frame)) or not Contract.valid_point(event.position) or not event.bounds is Dictionary or not Contract.exact_fields(event.bounds, ["x", "y", "width", "height"]) or event.bounds.width != 640.0 or event.bounds.height != 360.0:
		return false
	return Contract.number_in_range(event.bounds.x, -1000000.0, 1000000.0) and Contract.number_in_range(event.bounds.y, -1000000.0, 1000000.0)


static func _valid_occupied(value: Dictionary) -> bool:
	if value.size() > 4096:
		return false
	for id: Variant in value:
		var row: Variant = value[id]
		if not _id(id) or not row is Dictionary or not Contract.exact_fields(row, ["position", "radius", "clearance"]) or not Contract.valid_point(row.position) or not Contract.number_in_range(row.radius, 0.0, 320.0) or not Contract.number_in_range(row.clearance, 0.0, 48.0):
			return false
	return true


static func _position_clear(point: Vector2, occupied: Dictionary, rows: Array, radius: float) -> bool:
	for blocker: Dictionary in occupied.values():
		if point.distance_to(_vector(blocker.position)) <= radius + float(blocker.radius) + float(blocker.clearance) + 0.5:
			return false
	for row: Dictionary in rows:
		if row.phase == "ACTIVE" and point.distance_to(_vector(row.position)) < radius * 2.0 + 48.0:
			return false
	return true


static func _active_count(rows: Array) -> int:
	var count := 0
	for row: Dictionary in rows:
		count += int(row.phase == "ACTIVE")
	return count


static func _event_id(event: Dictionary) -> String:
	return "debris-" + JSON.stringify([event.run_id, event.source_id, event.generation, event.hit_index], "", true, true).sha256_text()


static func _vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))


static func _id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 256 and value.strip_edges() == value


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "code": &"RUIN_DEBRIS_INVALID", "context": {"reason": reason}}
