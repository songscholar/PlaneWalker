class_name EnemySpatialRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const STATE_FIELDS := ["schema_version", "run_id", "initial_frame", "runtime_frame", "rows", "damage_claims"]
const ROW_FIELDS := ["id", "owner_id", "definition_id", "action_id", "generation", "slot", "kind", "geometry", "parameters", "reserved_frame", "warning_frame", "active_frame", "expires_frame", "phase", "hp", "recipients", "transit_claims", "collapse_frame"]
const MAX_ROWS := 256
const MAX_CLAIMS := 4096
const MAX_CATALOG_CACHE := 4
static var _catalog_cache: Array[Dictionary] = []
static var _catalog_cache_mutex := Mutex.new()
var _actions := {}


func configure_catalog() -> bool:
	return _configure_catalog_source(FileAccess.get_file_as_bytes("res://data/content_packs/base/content/enemies.json"))


func _configure_catalog_source(source: PackedByteArray) -> bool:
	_actions.clear()
	var cached := _cached_catalog(source)
	if not cached.is_empty():
		_actions = cached
		return true
	if not _configure_catalog_source_uncached(source):
		return false
	_cache_catalog(source, var_to_bytes(_actions))
	return true


func _configure_catalog_source_uncached(source_bytes: PackedByteArray) -> bool:
	var parser := JSON.new()
	if parser.parse(source_bytes.get_string_from_utf8()) != OK:
		return false
	var data: Variant = parser.data
	if not data is Array:
		return false
	for definition: Variant in data:
		if not definition is Dictionary or not definition.get("id") is String or not definition.get("actions") is Array or not definition.get("elite_actions") is Array:
			return false
		for source: Variant in definition.actions + definition.elite_actions:
			if not source is Dictionary or not source.get("handler_id") is String:
				return false
			if source.handler_id not in ["wall", "link", "portal"]:
				continue
			var parsed := Contract.create(source, "elite" if definition.elite_actions.has(source) else "enemy")
			if not parsed.ok:
				return false
			_actions[source.id] = {"definition_id": definition.id, "action": parsed.definition}
	return _actions.size() == 5


static func _cached_catalog(encoded: PackedByteArray) -> Dictionary:
	_catalog_cache_mutex.lock()
	for row: Dictionary in _catalog_cache:
		if row.source == encoded:
			var state: PackedByteArray = row.state
			_catalog_cache_mutex.unlock()
			return bytes_to_var(state)
	_catalog_cache_mutex.unlock()
	return {}


static func _cache_catalog(encoded: PackedByteArray, state: PackedByteArray) -> void:
	_catalog_cache_mutex.lock()
	for row: Dictionary in _catalog_cache:
		if row.source == encoded:
			_catalog_cache_mutex.unlock()
			return
	if _catalog_cache.size() == MAX_CATALOG_CACHE:
		_catalog_cache.pop_front()
	_catalog_cache.append({"source": encoded, "state": state})
	_catalog_cache_mutex.unlock()


static func initial_state(run_id: String, frame: int) -> Dictionary:
	return {"schema_version": 1, "run_id": run_id, "initial_frame": frame, "runtime_frame": frame, "rows": [], "damage_claims": []}


func valid_state(value: Dictionary) -> bool:
	if not Contract.exact_fields(value, STATE_FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or not _stable(value.run_id) or not _frame(value.initial_frame) or not _frame(value.runtime_frame) or value.runtime_frame < value.initial_frame or not value.rows is Array or value.rows.size() > MAX_ROWS or not _claims(value.damage_claims):
		return false
	var ids := {}
	var active := 0
	var portals := {}
	var links := {}
	for row: Variant in value.rows:
		if not row is Dictionary or not Contract.exact_fields(row, ROW_FIELDS) or not _actions.has(row.action_id) or _actions[row.action_id].definition_id != row.definition_id or not _stable(row.owner_id) or not Contract.integer_in_range(row.generation, 1, 2147400000) or not Contract.integer_in_range(row.slot, 0, 2):
			return false
		var action: Dictionary = _actions[row.action_id].action
		if row.id != _id(value.run_id, row.owner_id, row.generation, row.slot) or ids.has(row.id) or row.kind != action.handler_id or row.parameters != action.parameters or row.phase not in ["PENDING", "WARNING", "ACTIVE", "COLLAPSE", "RETIRED"] or not _frame(row.reserved_frame) or row.reserved_frame < value.initial_frame or row.reserved_frame > value.runtime_frame or typeof(row.warning_frame) != TYPE_INT or typeof(row.active_frame) != TYPE_INT or typeof(row.expires_frame) != TYPE_INT or typeof(row.collapse_frame) != TYPE_INT or not row.geometry is Array or row.geometry.size() != (2 if row.kind == "portal" else 1) or not row.recipients is Array or not row.transit_claims is Dictionary:
			return false
		ids[row.id] = true
		for fact: Variant in row.geometry:
			if not fact is Dictionary or Actions.native_threat_fact(fact).is_empty() or fact.hostile_source_id != row.owner_id or fact.attack_generation != row.generation or fact.active_from_frame != row.reserved_frame or fact.active_through_frame != row.reserved_frame + 1200:
				return false
		if row.kind == "wall" and not _valid_wall(row) or row.kind == "portal" and (row.slot != 0 or row.geometry.any(func(fact: Dictionary): return fact.shape != "circle" or fact.radius != 16.0 or fact.length != 0.0) or _vector(row.geometry[0].origin).distance_to(_vector(row.geometry[1].origin)) < float(row.parameters.min_distance_px)) or row.kind == "link" and (row.slot != 0 or row.geometry[0].shape != "line" or row.geometry[0].radius != 3.0):
			return false
		if not Contract.number_in_range(row.hp, 0.0, float(action.parameters.get("hit_points", 0.0))):
			return false
		if row.kind == "link":
			if row.recipients.size() != 2 or not _stable(row.recipients[0]) or not _stable(row.recipients[1]) or row.recipients[0] >= row.recipients[1] or row.owner_id in row.recipients:
				return false
		elif not row.recipients.is_empty():
			return false
		if row.phase == "PENDING" and [row.warning_frame, row.active_frame, row.expires_frame, row.collapse_frame] != [-1, -1, -1, -1]:
			return false
		if row.phase == "WARNING" and (row.warning_frame < row.reserved_frame or row.warning_frame > value.runtime_frame or row.active_frame != -1 or row.expires_frame != -1 or row.collapse_frame != -1):
			return false
		if row.phase in ["ACTIVE", "COLLAPSE"]:
			if row.warning_frame < row.reserved_frame or row.active_frame != row.warning_frame + int(action.warning_frames) or row.active_frame > value.runtime_frame or row.expires_frame != row.active_frame + int(row.parameters.lifetime_frames):
				return false
			if row.phase == "ACTIVE" and (row.expires_frame <= value.runtime_frame or row.collapse_frame != -1 or row.kind != "portal" and row.hp <= 0.0):
				return false
			if row.phase == "COLLAPSE" and (row.kind != "portal" or row.collapse_frame < row.active_frame or row.collapse_frame > value.runtime_frame or value.runtime_frame >= row.collapse_frame + 45):
				return false
		if row.phase == "RETIRED" and not ((row.active_frame == -1 and row.expires_frame == -1 and row.collapse_frame == -1 and (row.warning_frame == -1 or row.warning_frame >= row.reserved_frame and row.warning_frame <= value.runtime_frame)) or (row.warning_frame >= row.reserved_frame and row.warning_frame <= value.runtime_frame and row.active_frame == row.warning_frame + int(action.warning_frames) and row.active_frame <= value.runtime_frame and row.expires_frame == row.active_frame + int(row.parameters.lifetime_frames) and (row.collapse_frame == -1 or row.kind == "portal" and row.collapse_frame >= row.active_frame and row.collapse_frame <= value.runtime_frame))):
			return false
		if row.kind != "portal" and not row.transit_claims.is_empty() or row.transit_claims.size() > 40:
			return false
		for target: Variant in row.transit_claims:
			if not _stable(target) or not _frame(row.transit_claims[target]) or row.transit_claims[target] < row.active_frame or row.transit_claims[target] > value.runtime_frame + 1:
				return false
		if row.phase == "ACTIVE":
			active += 1
			portals[row.owner_id] = int(portals.get(row.owner_id, 0)) + int(row.kind == "portal")
			links[row.owner_id] = int(links.get(row.owner_id, 0)) + int(row.kind == "link")
	for count: int in portals.values():
		if count > 1:
			return false
	for count: int in links.values():
		if count > 3:
			return false
	return active <= 8


func reserve(state: Dictionary, request: Dictionary, definition_id: String, allies: Dictionary) -> bool:
	if not valid_state(state) or not Contract.exact_fields(request, ["run_id", "hostile_source_id", "attack_generation", "runtime_frame", "action_id", "handler_id", "parameters", "geometry", "target_id"]) or not _actions.has(request.action_id) or _actions[request.action_id].definition_id != definition_id or request.parameters != _actions[request.action_id].action.parameters or request.handler_id != _actions[request.action_id].action.handler_id or request.run_id != state.run_id or request.runtime_frame != state.runtime_frame or not _stable(request.hostile_source_id) or not _stable(request.target_id) or not Contract.integer_in_range(request.attack_generation, 1, 2147400000) or not request.geometry is Array or request.geometry.size() != _actions[request.action_id].action.geometry.size():
		return false
	for fact: Variant in request.geometry:
		if not fact is Dictionary or Actions.native_threat_fact(fact).is_empty() or fact.hostile_source_id != request.hostile_source_id:
			return false
	var action: Dictionary = _actions[request.action_id].action
	var count: int = request.geometry.size() if action.handler_id == "wall" else 1
	while state.rows.size() + count > MAX_ROWS:
		var retired: int = state.rows.find_custom(func(row: Dictionary): return row.phase == "RETIRED")
		if retired < 0:
			break
		state.rows.remove_at(retired)
	if state.rows.size() + count > MAX_ROWS:
		return false
	var recipients: Array[String] = []
	var geometry: Array = request.geometry.duplicate(true)
	if action.handler_id == "wall":
		geometry = _wall_geometry(request)
	elif action.handler_id == "portal":
		for fact: Dictionary in geometry:
			fact.attack_generation = request.attack_generation
			fact.active_from_frame = state.runtime_frame
			fact.active_through_frame = state.runtime_frame + 1200
	if action.handler_id == "link":
		for source: String in allies:
			if source != request.hostile_source_id and not allies[source].dead and allies[source].kind in ["enemy", "elite"]:
				recipients.append(source)
		recipients.sort()
		if recipients.size() < 2:
			return true
		recipients.resize(2)
		var from := _vector(allies[recipients[0]].position)
		var to := _vector(allies[recipients[1]].position)
		geometry = [_fact(request.hostile_source_id, request.attack_generation, "line", from, from.direction_to(to), 3.0, from.distance_to(to), state.runtime_frame)]
	for slot: int in range(count):
		var id := _id(state.run_id, request.hostile_source_id, request.attack_generation, slot)
		if state.rows.any(func(row: Dictionary): return row.id == id):
			return false
		var row := {"id": id, "owner_id": request.hostile_source_id, "definition_id": definition_id, "action_id": request.action_id, "generation": int(request.attack_generation), "slot": slot, "kind": action.handler_id, "geometry": [geometry[slot].duplicate(true)] if action.handler_id == "wall" else geometry.duplicate(true), "parameters": action.parameters.duplicate(true), "reserved_frame": int(state.runtime_frame), "warning_frame": int(state.runtime_frame), "active_frame": -1, "expires_frame": -1, "phase": "WARNING", "hp": float(action.parameters.get("hit_points", 0.0)), "recipients": recipients.duplicate(), "transit_claims": {}, "collapse_frame": -1}
		state.rows.append(row)
	return true


func advance(state: Dictionary, frame: int, observations: Dictionary, safe: Callable, foreign_constructs: int = 0) -> Dictionary:
	if not valid_state(state) or not safe.is_valid() or frame != int(state.runtime_frame) + 1 or foreign_constructs < 0 or foreign_constructs > 8:
		return {"ok": false}
	state.runtime_frame = frame
	var collapse_warnings: Array = []
	for row: Dictionary in state.rows:
		if row.phase == "RETIRED":
			continue
		var owner_dead: bool = not observations.has(row.owner_id) or observations[row.owner_id].dead
		var recipient_dead: bool = row.recipients.any(func(id: String): return not observations.has(id) or observations[id].dead)
		if row.phase == "COLLAPSE":
			if frame == int(row.collapse_frame) + 45:
				row.phase = "RETIRED"
			continue
		if owner_dead or recipient_dead or row.phase == "ACTIVE" and frame >= int(row.expires_frame):
			if owner_dead and row.kind == "portal" and row.phase == "ACTIVE":
				row.phase = "COLLAPSE"
				row.collapse_frame = frame
				collapse_warnings.append(row.duplicate(true))
			else:
				row.phase = "RETIRED"
			continue
		if row.phase == "ACTIVE":
			if row.kind == "link":
				var from := _vector(observations[row.recipients[0]].position)
				var to := _vector(observations[row.recipients[1]].position)
				row.geometry = [_fact(row.owner_id, row.generation, "line", from, from.direction_to(to), 3.0, from.distance_to(to), row.reserved_frame)]
			continue
		var owned: int = state.rows.filter(func(other: Dictionary): return other.phase == "ACTIVE" and other.owner_id == row.owner_id and other.kind == row.kind).size()
		var capacity: bool = active_count(state) + foreign_constructs < 8 and (row.kind != "portal" or owned == 0) and (row.kind != "link" or owned < 3)
		if row.phase == "PENDING":
			if capacity and safe.call(row):
				row.phase = "WARNING"
				row.warning_frame = frame
		elif frame >= int(row.warning_frame) + int(_actions[row.action_id].action.warning_frames):
			if capacity and safe.call(row):
				row.phase = "ACTIVE"
				row.active_frame = frame
				row.expires_frame = frame + int(row.parameters.lifetime_frames)
			else:
				row.phase = "PENDING"
				row.warning_frame = -1
	return {"ok": true, "collapse_warnings": collapse_warnings}


func accept_damage(state: Dictionary, id: String, fact: Dictionary) -> float:
	if not Contract.exact_fields(fact, ["run_id", "source_id", "generation", "hit_index", "runtime_frame", "amount"]) or fact.run_id != state.run_id or not _stable(fact.source_id) or not Contract.integer_in_range(fact.generation, 1, 2147400000) or not Contract.integer_in_range(fact.hit_index, 0, 63) or fact.runtime_frame not in [int(state.runtime_frame), int(state.runtime_frame) + 1] or not Contract.number_in_range(fact.amount, 0.000001, 1000000.0):
		return 0.0
	var claim := JSON.stringify([id, fact.run_id, fact.source_id, fact.generation, fact.hit_index]).sha256_text()
	if state.damage_claims.has(claim) or state.damage_claims.size() >= MAX_CLAIMS:
		return 0.0
	for row: Dictionary in state.rows:
		if row.id == id and row.phase == "ACTIVE" and row.kind in ["wall", "link"]:
			var amount := minf(float(fact.amount), float(row.hp))
			row.hp -= amount
			state.damage_claims.append(claim)
			if row.hp == 0.0:
				row.phase = "RETIRED"
			return amount
	return 0.0


static func active_count(state: Dictionary) -> int:
	return state.rows.filter(func(row: Dictionary): return row.phase == "ACTIVE").size()


static func _wall_geometry(request: Dictionary) -> Array:
	var center := _vector(request.geometry[0].target_point)
	var axis := _vector(request.geometry[1].aim_direction)
	var normal := axis.orthogonal()
	var length := float(request.geometry[0].length)
	var corner := center - axis * length * 0.5 - normal * length * 0.5
	var result: Array = []
	for slot: int in range(3):
		var origin := corner + axis * length if slot == 2 else corner
		var fact := _fact(request.hostile_source_id, request.attack_generation, "line", origin, axis if slot == 0 else normal, float(request.geometry[slot].radius), length, request.runtime_frame)
		fact.target_point = _point(center)
		result.append(fact)
	return result


static func _valid_wall(row: Dictionary) -> bool:
	var fact: Dictionary = row.geometry[0]
	if fact.shape != "line" or fact.radius != 3.0 or fact.length != 48.0:
		return false
	var direction := _vector(fact.aim_direction)
	var axis := direction if row.slot == 0 else direction.rotated(PI * 0.5)
	var corner := _vector(fact.target_point) - axis * 24.0 - axis.orthogonal() * 24.0
	return _vector(fact.origin).is_equal_approx(corner + axis * 48.0 if row.slot == 2 else corner)


static func _id(run_id: String, owner: String, generation: int, slot: int) -> String:
	return "spatial_" + JSON.stringify([run_id, owner, generation, slot]).sha256_text().substr(0, 48)


static func _fact(source: String, generation: int, shape: String, origin: Vector2, direction: Vector2, radius: float, length: float, frame: int) -> Dictionary:
	return {"hostile_source_id": source, "attack_generation": generation, "shape": shape, "origin": _point(origin), "aim_direction": _point(direction if not direction.is_zero_approx() else Vector2.RIGHT), "target_point": _point(origin), "summon_slots": [], "radius": radius, "length": length, "active_from_frame": frame, "active_through_frame": frame + 1200}


static func _claims(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_CLAIMS:
		return false
	var seen := {}
	for claim: Variant in value:
		if not claim is String or claim.length() != 64 or not claim.is_valid_hex_number(false) or seen.has(claim):
			return false
		seen[claim] = true
	return true


static func _stable(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= 128 and value == value.strip_edges()


static func _frame(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= 2147400000


static func _vector(point: Dictionary) -> Vector2:
	return Vector2(float(point.x), float(point.y))


static func _point(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
