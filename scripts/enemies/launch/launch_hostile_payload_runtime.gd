class_name LaunchHostilePayloadRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Actions := preload("res://scripts/enemies/launch/hostile_action_coordinator.gd")
const Controls := preload("res://scripts/enemies/launch/hostile_control_runtime.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Definitions := preload("res://scripts/enemies/launch/hostile_definition_contract.gd")
const Debris := preload("res://scripts/enemies/launch/ruin_debris_runtime.gd")
const MAX_PROJECTILES := 32
const MAX_ZONES := 12
const MAX_RESERVATIONS := 256
const MAX_CLAIMS := 4096
const MAX_FRAME := 2147483647 - Contract.MAX_FRAME
const STATE_FIELDS := ["schema_version", "run_id", "initial_frame", "runtime_frame", "claims", "projectiles", "zones"]
const DEBRIS_STATE_FIELDS := ["schema_version", "run_id", "initial_frame", "runtime_frame", "claims", "projectiles", "zones", "arena_debris", "debris_impacts"]
const HIT_FIELDS := ["run_id", "hostile_source_id", "attack_generation", "hit_index", "runtime_frame", "target_id", "action_id", "damage", "damage_type", "handler_id", "geometry", "parameters"]
const PROJECTILE_FIELDS := ["id", "definition", "phase", "activated_frame", "age", "travel", "position", "control", "hit_targets"]
const ZONE_FIELDS := ["id", "definition", "phase", "activated_frame", "age", "control"]
const PROJECTILE_DEFINITION_FIELDS := ["kind", "run_id", "source_id", "generation", "hit_index", "reserved_frame", "origin", "direction", "radius", "speed", "lifetime_frames", "range_px", "damage", "damage_type", "target_id", "bounds", "impact_pool", "pierce_count", "visual_kind"]
const ZONE_DEFINITION_FIELDS := ["kind", "run_id", "source_id", "generation", "hit_index", "reserved_frame", "position", "radius", "damage", "damage_type", "warning_frames", "lifetime_frames", "tick_frames", "bounds", "visual_kind"]

var _state: Dictionary = {}


func configure(run_id: String, runtime_frame: int = 0) -> bool:
	if not _stable_id(run_id) or not _frame(runtime_frame):
		return false
	_state = {"schema_version": 1, "run_id": run_id, "initial_frame": runtime_frame, "runtime_frame": runtime_frame, "claims": [], "projectiles": [], "zones": []}
	return true


func reserve_projectile(hit: Dictionary, bounds: Dictionary, mechanisms: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.projectiles.size() + _state.zones.size() >= MAX_RESERVATIONS or _state.claims.size() >= MAX_CLAIMS:
		return _failure("reservation_capacity")
	var definition := _projectile_definition(hit, bounds, mechanisms)
	if definition.is_empty():
		return _failure("projectile_definition")
	var id := _id(definition)
	if _has_claim(_state, definition):
		return _failure("duplicate_reservation")
	if definition.has("debris_recipe") and not _enable_debris(definition.debris_recipe):
		return _failure("debris_recipe")
	var phase := "ACTIVE" if _active_count(_state.projectiles) < MAX_PROJECTILES else "PENDING"
	var record := {"id": id, "definition": definition, "phase": phase, "activated_frame": _state.runtime_frame if phase == "ACTIVE" else -1, "age": 0, "travel": 0.0, "position": definition.origin.duplicate(), "control": _new_control(id, int(_state.runtime_frame)), "hit_targets": []}
	_state.claims.append({"id": id, "key": _reservation_key(definition)})
	_state.projectiles.append(record)
	return {"ok": true, "id": id, "phase": phase}


func reserve_death_pool(request: Dictionary, zone_capacity: int = MAX_ZONES) -> Dictionary:
	if _state.is_empty() or zone_capacity < 0 or zone_capacity > MAX_ZONES or not Contract.exact_fields(request, ["kind", "run_id", "hostile_source_id", "runtime_frame", "attack_generation", "position", "bounds", "parameters"]):
		return _failure("death_request")
	if request.kind != "death_pool" or request.run_id != _state.run_id or request.runtime_frame != _state.runtime_frame or not _stable_id(request.hostile_source_id) or not Contract.integer_in_range(request.attack_generation, 1, MAX_FRAME):
		return _failure("death_identity")
	if not _valid_bounds(request.bounds) or not Contract.valid_point(request.position) or not _inside(request.position, request.bounds) or not request.parameters is Dictionary or not Contract.exact_fields(request.parameters, ["warning_frames", "radius", "damage"]):
		return _failure("death_parameters")
	if not Contract.integer_in_range(request.parameters.warning_frames, 23, 600) or not Contract.number_in_range(request.parameters.radius, 1, 320) or not Contract.number_in_range(request.parameters.damage, 0, 600):
		return _failure("death_values")
	var definition := {"kind": "death_pool", "run_id": request.run_id, "source_id": request.hostile_source_id, "generation": int(request.attack_generation), "hit_index": 63, "reserved_frame": int(request.runtime_frame), "position": Contract.point(request.position), "radius": float(request.parameters.radius), "damage": float(request.parameters.damage), "damage_type": "void", "warning_frames": int(request.parameters.warning_frames), "lifetime_frames": 1, "tick_frames": 1, "bounds": request.bounds.duplicate(true), "visual_kind": "acid"}
	return _reserve_zone(_state, definition, zone_capacity)


func reserve_boss_aftershock(request: Dictionary, zone_capacity: int = MAX_ZONES) -> Dictionary:
	if _state.is_empty() or zone_capacity < 0 or zone_capacity > MAX_ZONES or not Contract.exact_fields(request, ["kind", "run_id", "hostile_source_id", "runtime_frame", "attack_generation", "position", "bounds", "parameters"]) or request.kind != "boss_aftershock" or request.run_id != _state.run_id or request.runtime_frame != _state.runtime_frame or not _stable_id(request.hostile_source_id) or not Contract.integer_in_range(request.attack_generation, 1, MAX_FRAME):
		return _failure("aftershock_identity")
	if not _valid_bounds(request.bounds) or not Contract.valid_point(request.position) or not _inside(request.position, request.bounds) or not request.parameters is Dictionary or not Contract.exact_fields(request.parameters, ["delay_frames", "warning_frames", "radius", "damage"]):
		return _failure("aftershock_parameters")
	var parameters: Dictionary = request.parameters
	if not Contract.integer_in_range(parameters.delay_frames, 20, 20) or not Contract.integer_in_range(parameters.warning_frames, 40, 40) or not Contract.number_in_range(parameters.radius, 32.0, 32.0) or not Contract.number_in_range(parameters.damage, 9.6, 18.0):
		return _failure("aftershock_values")
	var definition := {"kind": "boss_aftershock", "run_id": request.run_id, "source_id": request.hostile_source_id, "generation": int(request.attack_generation), "hit_index": 61, "reserved_frame": int(request.runtime_frame), "position": Contract.point(request.position), "radius": float(parameters.radius), "damage": float(parameters.damage), "damage_type": "physical", "warning_frames": int(parameters.warning_frames), "delay_frames": int(parameters.delay_frames), "lifetime_frames": 1, "tick_frames": 1, "bounds": request.bounds.duplicate(true), "visual_kind": "physical"}
	return _reserve_zone(_state, definition, zone_capacity)


func retire_arena_payloads(sources: Array[String]) -> void:
	for index: int in range(_state.zones.size() - 1, -1, -1):
		var row: Dictionary = _state.zones[index]
		if row.definition.kind == "boss_aftershock" and sources.has(str(row.definition.source_id)):
			_state.zones.remove_at(index)


func motion_for_frame(frame: int) -> Dictionary:
	if _state.is_empty() or frame != int(_state.runtime_frame) + 1 or not _frame(frame):
		return {}
	var result: Dictionary = {}
	for row: Dictionary in _state.projectiles:
		if row.phase != "ACTIVE":
			continue
		var modifiers := _control_for_frame(row.control, frame)
		if modifiers.is_empty():
			return {}
		var definition: Dictionary = row.definition
		var distance := 0.0 if modifiers.action_paused else minf(float(definition.range_px) - float(row.travel), float(definition.speed) * float(modifiers.movement_multiplier) / 60.0)
		var displacement := {"x": float(definition.direction.x) * distance, "y": float(definition.direction.y) * distance}
		result[row.id] = {"displacement": displacement, "from": row.position.duplicate(), "to": {"x": float(row.position.x) + float(displacement.x), "y": float(row.position.y) + float(displacement.y)}, "radius": definition.radius, "action_paused": modifiers.action_paused}
	return result


func advance_frame(frame: int, observations: Dictionary, zone_capacity: int = MAX_ZONES, debris_context: Dictionary = {}) -> Dictionary:
	if _state.is_empty() or zone_capacity < 0 or zone_capacity > MAX_ZONES or frame != int(_state.runtime_frame) + 1 or not _frame(frame) or not _valid_observations(observations):
		return _failure("frame_or_observations")
	var motion := motion_for_frame(frame)
	for id: Variant in observations.projectile_contacts:
		if not motion.has(id) or not _valid_contact(observations.projectile_contacts[id], motion[id], observations.targets):
			return _failure("contact")
		for row: Dictionary in _state.projectiles:
			if row.id == id and observations.projectile_contacts[id].kind == "target" and row.hit_targets.has(observations.projectile_contacts[id].target_id):
				return _failure("duplicate_pierced_target")
	var next := snapshot()
	next.runtime_frame = frame
	var damages: Array[Dictionary] = []
	var retired: Array[String] = []
	var retained: Array[Dictionary] = []
	var impacts: Array[Dictionary] = []
	var debris_events: Array[Dictionary] = []
	for row: Dictionary in next.projectiles:
		var control := _advanced_control(row.control, frame)
		if control.is_empty():
			return _failure("control")
		row.control = control
		if row.phase == "PENDING":
			retained.append(row)
			continue
		if observations.projectile_contacts.has(row.id):
			var contact: Dictionary = observations.projectile_contacts[row.id]
			if contact.kind == "target":
				damages.append(_damage(row.id, row.definition, contact.target_id, frame))
				row.hit_targets.append(contact.target_id)
			if contact.kind == "world" or row.hit_targets.size() > int(row.definition.pierce_count):
				_record_debris_impact(next, row.definition, contact.position, frame, debris_events)
				if not row.definition.impact_pool.is_empty():
					impacts.append(_impact_definition(row.definition, contact.position, frame))
				retired.append(row.id)
				continue
		var step: Dictionary = motion[row.id]
		if not step.action_paused:
			row.age = int(row.age) + 1
			row.travel = minf(float(row.definition.range_px), float(row.travel) + sqrt(float(step.displacement.x) ** 2 + float(step.displacement.y) ** 2))
			row.position = _trajectory_position(row.definition, float(row.travel))
		if row.age >= row.definition.lifetime_frames or row.travel >= float(row.definition.range_px) - 0.00001 or not _inside(row.position, row.definition.bounds):
			_record_debris_impact(next, row.definition, row.position, frame, debris_events)
			retired.append(row.id)
		else:
			retained.append(row)
	next.projectiles = retained
	var retained_zones: Array[Dictionary] = []
	for row: Dictionary in next.zones:
		row.control = _advanced_control(row.control, frame)
		if row.control.is_empty():
			return _failure("zone_control")
		if row.phase == "PENDING":
			retained_zones.append(row)
			continue
		var modifier := _modifiers(row.control)
		if not modifier.action_paused:
			row.age = int(row.age) + 1
		var definition: Dictionary = row.definition
		var delay: int = int(definition.get("delay_frames", 0))
		if row.phase == "DORMANT" and int(row.age) >= delay:
			row.phase = "WARNING"
		var active_age: int = int(row.age) - int(definition.warning_frames) - delay
		if active_age >= 0:
			row.phase = "ACTIVE"
		var pulse: bool = not modifier.action_paused and ((definition.kind in ["death_pool", "boss_aftershock"] and active_age == 0) or (definition.kind == "impact_pool" and active_age > 0 and active_age % int(definition.tick_frames) == 0))
		if pulse:
			var target_ids: Array = observations.targets.keys()
			target_ids.sort()
			for target_id: String in target_ids:
				if _vector(observations.targets[target_id].position).distance_to(_vector(definition.position)) <= float(definition.radius):
					damages.append(_damage(row.id, definition, target_id, frame))
		if (definition.kind in ["death_pool", "boss_aftershock"] and active_age >= 0) or active_age >= int(definition.lifetime_frames):
			retired.append(row.id)
		else:
			retained_zones.append(row)
	next.zones = retained_zones
	for definition: Dictionary in impacts:
		var reserved := _reserve_zone(next, definition, zone_capacity)
		if not reserved.ok:
			return reserved
	_activate_pending(next.projectiles, MAX_PROJECTILES, frame)
	_activate_pending(next.zones, zone_capacity, frame)
	if next.schema_version == 2:
		var debris := _debris_runtime(next)
		if debris == null or not debris.advance_frame(frame, debris_events, debris_context.get("occupied", {}), int(debris_context.get("foreign_constructs", 0)), debris_context.get("retired_sources", [])).ok:
			return _failure("debris_transition")
		next.arena_debris = debris.snapshot()
	_state = next
	return {"ok": true, "runtime_frame": frame, "damage_requests": damages, "retired_payload_ids": retired, "pending_work": pending_work()}


func add_control_source(payload_id: String, source_id: String, kind: String, duration_frames: int, magnitude: float) -> bool:
	for collection: String in ["projectiles", "zones"]:
		for row: Dictionary in _state.get(collection, []):
			if row.id != payload_id:
				continue
			var control := _control_runtime(row.control)
			if control == null or not control.add_source(source_id, kind, duration_frames, magnitude):
				return false
			row.control = control.snapshot()
			return true
	return false


func clear_control_source(payload_id: String, source_id: String) -> bool:
	for collection: String in ["projectiles", "zones"]:
		for row: Dictionary in _state.get(collection, []):
			if row.id == payload_id:
				var control := _control_runtime(row.control)
				if control == null or not control.clear_source(source_id):
					return false
				row.control = control.snapshot()
				return true
	return false


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func accept_debris_damage(fact: Dictionary) -> Dictionary:
	var debris := _debris_runtime(_state)
	if debris == null:
		return _failure("debris_unavailable")
	var result: Dictionary = debris.accept_damage_fact(fact)
	if result.ok:
		_state.arena_debris = debris.snapshot()
	return result


func pending_work() -> Dictionary:
	return {"projectiles": _state.get("projectiles", []).size(), "zones": _state.get("zones", []).size()}


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or typeof(value.get("schema_version")) != TYPE_INT or value.schema_version not in [1, 2] or not Contract.exact_fields(value, DEBRIS_STATE_FIELDS if value.schema_version == 2 else STATE_FIELDS) or value.run_id != _state.run_id or value.initial_frame != _state.initial_frame or not _frame(value.runtime_frame) or value.runtime_frame < value.initial_frame:
		return false
	if not value.claims is Array or value.claims.size() > MAX_CLAIMS or not value.projectiles is Array or not value.zones is Array or value.projectiles.size() + value.zones.size() > MAX_RESERVATIONS:
		return false
	var claims: Dictionary = {}
	var keys: Dictionary = {}
	for claim: Variant in value.claims:
		if not claim is Dictionary or not Contract.exact_fields(claim, ["id", "key"]) or not _payload_id(claim.id) or not _payload_id(claim.key) or claims.has(claim.id) or keys.has(claim.key):
			return false
		claims[claim.id] = claim.key
		keys[claim.key] = true
	var live: Dictionary = {}
	for row: Variant in value.projectiles:
		if not row is Dictionary or not Contract.exact_fields(row, PROJECTILE_FIELDS) or not _valid_live_record(row, value, claims, live, true):
			return false
		if not _valid_projectile_definition(row.definition) or not Contract.number_in_range(row.travel, 0, float(row.definition.range_px) - 0.000001) or not Contract.valid_point(row.position):
			return false
		if value.schema_version == 1 and row.definition.has("debris_recipe"):
			return false
		if row.position != _trajectory_position(row.definition, float(row.travel)) or not _inside(row.position, row.definition.bounds) or row.age >= row.definition.lifetime_frames:
			return false
		if row.phase == "PENDING" and (row.age != 0 or float(row.travel) != 0.0):
			return false
		if not row.hit_targets is Array or row.hit_targets.size() > int(row.definition.pierce_count) or row.hit_targets.size() > int(row.age) or row.phase == "PENDING" and not row.hit_targets.is_empty():
			return false
		var seen_targets: Dictionary = {}
		for target: Variant in row.hit_targets:
			if not _stable_id(target) or seen_targets.has(target):
				return false
			seen_targets[target] = true
		if float(row.travel) > float(row.definition.speed) * float(row.age) / 60.0 + 0.00001:
			return false
	for row: Variant in value.zones:
		if not row is Dictionary or not Contract.exact_fields(row, ZONE_FIELDS) or not _valid_live_record(row, value, claims, live, false) or not _valid_zone_definition(row.definition):
			return false
		var delay: int = int(row.definition.get("delay_frames", 0))
		if row.age >= int(row.definition.warning_frames) + delay + int(row.definition.lifetime_frames) or (row.definition.kind in ["death_pool", "boss_aftershock"] and row.age >= int(row.definition.warning_frames) + delay):
			return false
		if row.phase == "PENDING" and row.age != 0:
			return false
		if row.phase != "PENDING" and row.phase != ("DORMANT" if row.age < delay else ("WARNING" if row.age < int(row.definition.warning_frames) + delay else "ACTIVE")):
			return false
	if value.schema_version == 2 and not _valid_debris_state(value, claims, keys):
		return false
	return _active_count(value.projectiles) <= MAX_PROJECTILES and _active_count(value.zones) <= MAX_ZONES


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


func _projectile_definition(hit: Dictionary, bounds: Dictionary, mechanisms: Dictionary) -> Dictionary:
	if not Contract.exact_fields(hit, HIT_FIELDS) or hit.run_id != _state.run_id or hit.runtime_frame != _state.runtime_frame or hit.handler_id != "projectile_volley" or not _stable_id(hit.hostile_source_id) or not _stable_id(hit.target_id) or not Contract.valid_id(hit.action_id):
		return {}
	if not Contract.integer_in_range(hit.attack_generation, 1, MAX_FRAME) or not Contract.integer_in_range(hit.hit_index, 0, 63) or not Contract.number_in_range(hit.damage, 0, 600) or hit.damage_type not in Contract.DAMAGE_TYPES or not _valid_bounds(bounds):
		return {}
	if not hit.parameters is Dictionary or not Contract._parameters("projectile_volley", hit.parameters).ok or not hit.geometry is Array or hit.geometry.is_empty() or hit.geometry.size() > 16:
		return {}
	var index := int(hit.hit_index) if hit.geometry.size() > 1 else 0
	if index >= hit.geometry.size():
		return {}
	for lane_index: int in range(hit.geometry.size()):
		var fact: Variant = hit.geometry[lane_index]
		if not fact is Dictionary or Actions.native_threat_fact(fact).is_empty() or fact.hostile_source_id != hit.hostile_source_id or fact.attack_generation != int(hit.attack_generation) + lane_index or fact.shape != "line":
			return {}
	var lane: Dictionary = hit.geometry[index]
	var range_px := float(lane.length)
	if not Contract.number_in_range(range_px, 1.0, float(hit.parameters.speed_px_per_second) * float(hit.parameters.lifetime_frames) / 60.0) or not _inside(lane.origin, bounds):
		return {}
	var pool: Dictionary = {}
	var debris_recipe: Dictionary = {}
	if hit.action_id == "guardian_debris_barrage" and not mechanisms.is_empty():
		if not Contract.exact_fields(mechanisms, ["debris_hp", "debris_lifetime_frames", "debris_count_cap"]) or mechanisms.debris_hp != 20 or mechanisms.debris_lifetime_frames != 480 or mechanisms.debris_count_cap != 4:
			return {}
		debris_recipe = {"max_hp": float(mechanisms.debris_hp), "lifetime_frames": int(mechanisms.debris_lifetime_frames), "count_cap": int(mechanisms.debris_count_cap), "radius_px": 12.0}
	elif not mechanisms.is_empty() and not mechanisms.has("debris_hp"):
		var base := mechanisms.duplicate(true)
		var scaling: Variant = base.get("mechanism_scaling", {})
		base.erase("mechanism_scaling")
		var parsed := Definitions.mechanisms(base, Enemy.MECHANISM_RULES.corrosive_moth)
		if mechanisms.has("mechanism_scaling"):
			if not Contract.exact_fields(scaling, ["schema_version", "damage_multiplier", "base"]) or scaling.schema_version != 1 or not Contract.number_in_range(scaling.damage_multiplier, 1.0, 2.0):
				return {}
			parsed = Enemy.scaled_mechanisms(scaling.base, "corrosive_moth", float(scaling.damage_multiplier))
			if not parsed.ok or JSON.parse_string(JSON.stringify(base)) != JSON.parse_string(JSON.stringify(parsed.value)):
				return {}
		if not parsed.ok:
			return {}
		pool = {"radius": float(mechanisms.impact_pool_radius_px), "lifetime_frames": int(mechanisms.impact_pool_lifetime_frames), "damage": float(mechanisms.impact_pool_damage), "tick_frames": int(mechanisms.impact_pool_tick_frames)}
	var definition := {"kind": "projectile", "run_id": hit.run_id, "source_id": hit.hostile_source_id, "generation": int(lane.attack_generation), "hit_index": int(hit.hit_index), "reserved_frame": int(hit.runtime_frame), "origin": Contract.point(lane.origin), "direction": Contract.point(lane.aim_direction), "radius": float(lane.radius), "speed": float(hit.parameters.speed_px_per_second), "lifetime_frames": int(hit.parameters.lifetime_frames), "range_px": range_px, "damage": float(hit.damage), "damage_type": hit.damage_type, "target_id": hit.target_id, "bounds": bounds.duplicate(true), "impact_pool": pool, "pierce_count": int(hit.parameters.pierce_count), "visual_kind": "acid" if hit.action_id.begins_with("corrosive_moth.") else str(hit.damage_type)}
	if not debris_recipe.is_empty():
		definition["debris_recipe"] = debris_recipe
	return definition if _valid_projectile_definition(definition) else {}


func _enable_debris(recipe: Dictionary) -> bool:
	if _state.schema_version == 2:
		return _state.arena_debris.recipe == recipe
	var debris := Debris.new()
	if not debris.configure(str(_state.run_id), int(_state.initial_frame), recipe):
		return false
	var state: Dictionary = debris.snapshot()
	state.runtime_frame = _state.runtime_frame
	if not debris.restore_snapshot(state):
		return false
	_state.schema_version = 2
	_state["arena_debris"] = state
	_state["debris_impacts"] = []
	return true


func _debris_runtime(value: Dictionary) -> RefCounted:
	if value.get("schema_version") != 2 or not value.get("arena_debris") is Dictionary or not value.arena_debris.get("recipe") is Dictionary:
		return null
	var runtime := Debris.new()
	return runtime if runtime.configure(str(value.run_id), int(value.initial_frame), value.arena_debris.recipe) and runtime.restore_snapshot(value.arena_debris) else null


func _valid_debris_state(value: Dictionary, claims: Dictionary, keys: Dictionary) -> bool:
	var debris := _debris_runtime(value)
	if debris == null or value.arena_debris.runtime_frame != value.runtime_frame or not value.debris_impacts is Array or value.debris_impacts.size() != value.arena_debris.rows.size():
		return false
	for index: int in range(value.debris_impacts.size()):
		var receipt: Variant = value.debris_impacts[index]
		if not receipt is Dictionary or not Contract.exact_fields(receipt, ["event", "projectile_definition"]) or not receipt.event is Dictionary or not receipt.projectile_definition is Dictionary:
			return false
		var definition: Dictionary = receipt.projectile_definition
		var event: Dictionary = receipt.event
		if not definition.has("debris_recipe") or not _valid_projectile_definition(definition) or definition.debris_recipe != value.arena_debris.recipe or not claims.has(_id(definition)) or not keys.has(_reservation_key(definition)) or event != value.arena_debris.rows[index].event or event.run_id != definition.run_id or event.source_id != definition.source_id or event.generation != definition.generation or event.hit_index != definition.hit_index or event.bounds != definition.bounds or event.runtime_frame <= definition.reserved_frame:
			return false
		var origin := _vector(definition.origin)
		var endpoint := origin + _vector(definition.direction) * float(definition.range_px)
		if Geometry2D.get_closest_point_to_segment(_vector(event.position), origin, endpoint).distance_to(_vector(event.position)) > 0.05:
			return false
		if origin.distance_to(_vector(event.position)) > minf(float(definition.range_px), float(definition.speed) * float(event.runtime_frame - definition.reserved_frame) / 60.0) + 0.05:
			return false
	return true


static func _record_debris_impact(next: Dictionary, definition: Dictionary, position: Dictionary, frame: int, events: Array[Dictionary]) -> void:
	if not definition.has("debris_recipe"):
		return
	var event := {"run_id": definition.run_id, "source_id": definition.source_id, "generation": definition.generation, "hit_index": definition.hit_index, "runtime_frame": frame, "position": position.duplicate(true), "bounds": definition.bounds.duplicate(true)}
	events.append(event)
	next.debris_impacts.append({"event": event.duplicate(true), "projectile_definition": definition.duplicate(true)})


static func _projectile_fields(definition: Dictionary) -> Array:
	return PROJECTILE_DEFINITION_FIELDS + ["debris_recipe"] if definition.has("debris_recipe") else PROJECTILE_DEFINITION_FIELDS


func _reserve_zone(state: Dictionary, definition: Dictionary, zone_capacity: int = MAX_ZONES) -> Dictionary:
	var id := _id(definition)
	if _has_claim(state, definition) or state.projectiles.size() + state.zones.size() >= MAX_RESERVATIONS or state.claims.size() >= MAX_CLAIMS or not _valid_zone_definition(definition):
		return _failure("zone_reservation")
	var phase := ("DORMANT" if int(definition.get("delay_frames", 0)) > 0 else ("WARNING" if definition.warning_frames > 0 else "ACTIVE")) if _active_count(state.zones) < zone_capacity else "PENDING"
	state.claims.append({"id": id, "key": _reservation_key(definition)})
	state.zones.append({"id": id, "definition": definition, "phase": phase, "activated_frame": state.runtime_frame if phase != "PENDING" else -1, "age": 0, "control": _new_control(id, int(state.runtime_frame))})
	return {"ok": true, "id": id, "phase": phase}


func _impact_definition(projectile: Dictionary, position: Dictionary, frame: int) -> Dictionary:
	var pool: Dictionary = projectile.impact_pool
	return {"kind": "impact_pool", "run_id": projectile.run_id, "source_id": projectile.source_id, "generation": projectile.generation, "hit_index": projectile.hit_index, "reserved_frame": frame, "position": Contract.point(position), "radius": pool.radius, "damage": pool.damage, "damage_type": projectile.damage_type, "warning_frames": 0, "lifetime_frames": pool.lifetime_frames, "tick_frames": pool.tick_frames, "bounds": projectile.bounds.duplicate(true), "visual_kind": projectile.visual_kind}


func _valid_live_record(row: Dictionary, state: Dictionary, claims: Dictionary, live: Dictionary, projectile: bool) -> bool:
	if not row.definition is Dictionary or not Contract.exact_fields(row.definition, _projectile_fields(row.definition) if projectile else _zone_fields(row.definition)) or not _payload_id(row.id) or row.id != _id(row.definition) or not claims.has(row.id) or claims[row.id] != _reservation_key(row.definition) or live.has(row.id) or row.phase not in (["PENDING", "ACTIVE"] if projectile else ["PENDING", "DORMANT", "WARNING", "ACTIVE"]):
		return false
	if not Contract.integer_in_range(row.activated_frame, -1, int(state.runtime_frame)) or not Contract.integer_in_range(row.age, 0, Contract.MAX_FRAME) or not row.definition.has("reserved_frame") or not _frame(row.definition.reserved_frame) or row.definition.reserved_frame < state.initial_frame or row.definition.reserved_frame > state.runtime_frame:
		return false
	if (row.phase == "PENDING") != (row.activated_frame == -1) or (row.activated_frame != -1 and (row.activated_frame < row.definition.reserved_frame or row.age > state.runtime_frame - row.activated_frame)):
		return false
	var control := _control_runtime(row.control)
	if control == null or row.control.runtime_frame != state.runtime_frame or row.control.identity.run_id != state.run_id or row.control.identity.runtime_frame != row.definition.reserved_frame or row.control.identity.hostile_source_id != row.id or row.control.terminal:
		return false
	live[row.id] = true
	return true


func _valid_projectile_definition(row: Dictionary) -> bool:
	if not Contract.exact_fields(row, _projectile_fields(row)) or row.kind != "projectile" or not _valid_definition_identity(row) or not Contract.valid_point(row.origin) or not Contract.valid_point(row.direction, 1) or not is_equal_approx(_vector(row.direction).length(), 1.0) or not _inside(row.origin, row.bounds) or not _stable_id(row.target_id):
		return false
	if row.has("debris_recipe"):
		var debris := Debris.new()
		if not row.debris_recipe is Dictionary or not debris.configure(str(row.run_id), int(_state.initial_frame), row.debris_recipe) or row.radius != 5.0 or row.speed != 128.0 or row.lifetime_frames != 90 or row.range_px != 192.0 or row.pierce_count != 0 or row.damage_type != "physical" or not row.impact_pool.is_empty() or row.hit_index >= Debris.MAX_BARRAGE_PROJECTILES:
			return false
	if not Contract.number_in_range(row.radius, 1, 320) or not Contract.number_in_range(row.speed, 1, 480) or not Contract.integer_in_range(row.lifetime_frames, 1, 600) or not Contract.number_in_range(row.range_px, 1.0, float(row.speed) * float(row.lifetime_frames) / 60.0) or not Contract.integer_in_range(row.pierce_count, 0, 8) or not row.impact_pool is Dictionary:
		return false
	return row.impact_pool.is_empty() or (Contract.exact_fields(row.impact_pool, ["radius", "lifetime_frames", "damage", "tick_frames"]) and Contract.number_in_range(row.impact_pool.radius, 1, 320) and Contract.number_in_range(row.impact_pool.damage, 0, 600) and Contract.integer_in_range(row.impact_pool.lifetime_frames, 1, 1200) and Contract.integer_in_range(row.impact_pool.tick_frames, 1, 600))


func _valid_zone_definition(row: Dictionary) -> bool:
	if not Contract.exact_fields(row, _zone_fields(row)) or row.kind not in ["death_pool", "impact_pool", "boss_aftershock"] or not _valid_definition_identity(row) or not Contract.valid_point(row.position) or not _inside(row.position, row.bounds) or not Contract.number_in_range(row.radius, 1, 320) or not Contract.integer_in_range(row.warning_frames, 0, 600) or not Contract.integer_in_range(row.lifetime_frames, 1, 1200) or not Contract.integer_in_range(row.tick_frames, 1, 600):
		return false
	if row.kind == "boss_aftershock":
		return typeof(row.delay_frames) == TYPE_INT and row.delay_frames == 20 and row.warning_frames == 40 and row.lifetime_frames == 1 and row.tick_frames == 1 and row.hit_index == 61 and row.radius == 32.0 and row.damage_type == "physical" and row.visual_kind == "physical" and Contract.number_in_range(row.damage, 9.6, 18.0)
	return (row.kind != "death_pool" or (row.warning_frames >= 23 and row.lifetime_frames == 1 and row.tick_frames == 1 and row.hit_index == 63)) and (row.kind != "impact_pool" or row.warning_frames == 0)


static func _zone_fields(definition: Dictionary) -> Array:
	return ZONE_DEFINITION_FIELDS + ["delay_frames"] if definition.get("kind", "") == "boss_aftershock" else ZONE_DEFINITION_FIELDS


func _valid_definition_identity(row: Dictionary) -> bool:
	return row.run_id == _state.run_id and _stable_id(row.source_id) and Contract.integer_in_range(row.generation, 1, MAX_FRAME) and Contract.integer_in_range(row.hit_index, 0, 63) and _frame(row.reserved_frame) and Contract.number_in_range(row.damage, 0, 600) and row.damage_type in Contract.DAMAGE_TYPES and row.visual_kind in ["acid", "physical", "time", "void", "fire", "ice", "lightning"] and _valid_bounds(row.bounds)


func _valid_observations(value: Dictionary) -> bool:
	if not Contract.exact_fields(value, ["projectile_contacts", "targets"]) or not value.projectile_contacts is Dictionary or not value.targets is Dictionary or value.targets.size() > 64:
		return false
	for id: Variant in value.targets:
		var target: Variant = value.targets[id]
		if not _stable_id(id) or not target is Dictionary or not Contract.exact_fields(target, ["position", "collision_radius_px"]) or not Contract.valid_point(target.position) or not Contract.number_in_range(target.collision_radius_px, 0, 32):
			return false
	return true


func _valid_contact(value: Variant, motion: Dictionary, targets: Dictionary) -> bool:
	if not value is Dictionary or not Contract.exact_fields(value, ["kind", "target_id", "position"]) or value.kind not in ["world", "target"] or not Contract.valid_point(value.position) or motion.action_paused:
		return false
	if value.kind == "target" and (not targets.has(value.target_id) or not _stable_id(value.target_id)):
		return false
	if value.kind == "target" and _vector(targets[value.target_id].position).distance_to(_vector(value.position)) > float(targets[value.target_id].collision_radius_px) + float(motion.radius) + 0.05:
		return false
	if value.kind == "world" and value.target_id != "":
		return false
	var start := _vector(motion.from)
	var end := _vector(motion.to)
	var point := _vector(value.position)
	return Geometry2D.get_closest_point_to_segment(point, start, end).distance_to(point) <= 0.01


func _new_control(id: String, frame: int) -> Dictionary:
	var runtime := Controls.new()
	runtime.configure({"run_id": _state.run_id, "hostile_source_id": id, "runtime_frame": frame})
	return runtime.snapshot()


func _control_runtime(value: Variant) -> RefCounted:
	if not value is Dictionary or not value.get("identity") is Dictionary or not Contract.exact_fields(value.identity, Controls.IDENTITY_FIELDS):
		return null
	var runtime := Controls.new()
	if not runtime.configure(value.identity).ok or not runtime.restore_snapshot(value):
		return null
	return runtime


func _advanced_control(value: Dictionary, frame: int) -> Dictionary:
	var runtime := _control_runtime(value)
	if runtime == null or not runtime.advance_frame(frame).ok:
		return {}
	return runtime.snapshot()


func _control_for_frame(value: Dictionary, frame: int) -> Dictionary:
	var advanced := _advanced_control(value, frame)
	return _modifiers(advanced) if not advanced.is_empty() else {}


func _modifiers(value: Dictionary) -> Dictionary:
	var runtime := _control_runtime(value)
	return runtime.modifiers() if runtime != null else {}


static func _activate_pending(rows: Array, limit: int, frame: int) -> void:
	var active := _active_count(rows)
	for row: Dictionary in rows:
		if row.phase == "PENDING" and active < limit:
			row.phase = "DORMANT" if int(row.definition.get("delay_frames", 0)) > 0 else ("WARNING" if row.definition.get("warning_frames", 0) > 0 else "ACTIVE")
			row.activated_frame = frame
			active += 1


static func _active_count(rows: Array) -> int:
	var count := 0
	for row: Dictionary in rows:
		if row.phase != "PENDING":
			count += 1
	return count


static func _damage(id: String, definition: Dictionary, target_id: String, frame: int) -> Dictionary:
	return {"payload_id": id, "hostile_source_id": definition.source_id, "attack_generation": definition.generation, "hit_index": definition.hit_index if definition.kind == "projectile" else frame, "target_id": target_id, "runtime_frame": frame, "damage": definition.damage, "damage_type": definition.damage_type}


static func _id(definition: Dictionary) -> String:
	return "payload-" + JSON.stringify(definition, "", true, true).sha256_text().substr(0, 40)


static func _reservation_key(definition: Dictionary) -> String:
	return _id({"run_id": definition.run_id, "kind": definition.kind, "source_id": definition.source_id, "generation": definition.generation, "hit_index": definition.hit_index})


static func _has_claim(state: Dictionary, definition: Dictionary) -> bool:
	var key := _reservation_key(definition)
	for claim: Dictionary in state.claims:
		if claim.key == key:
			return true
	return false


static func _trajectory_position(definition: Dictionary, travel: float) -> Dictionary:
	return {"x": float(definition.origin.x) + float(definition.direction.x) * travel, "y": float(definition.origin.y) + float(definition.direction.y) * travel}


static func _payload_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 48 or not value.begins_with("payload-"):
		return false
	for code: int in value.substr(8).to_utf8_buffer():
		if code < 48 or (code > 57 and code < 97) or code > 102:
			return false
	return true


static func _valid_bounds(value: Variant) -> bool:
	return value is Dictionary and Contract.exact_fields(value, ["x", "y", "width", "height"]) and Contract.number_in_range(value.x, -1000000, 1000000) and Contract.number_in_range(value.y, -1000000, 1000000) and Contract.number_in_range(value.width, 1, 4096) and Contract.number_in_range(value.height, 1, 4096)


static func _inside(point: Dictionary, bounds: Dictionary) -> bool:
	return float(point.x) >= float(bounds.x) and float(point.x) <= float(bounds.x) + float(bounds.width) and float(point.y) >= float(bounds.y) and float(point.y) <= float(bounds.y) + float(bounds.height)


static func _stable_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 64 or value.strip_edges() != value:
		return false
	for code: int in value.to_utf8_buffer():
		if code < 33 or code > 126:
			return false
	return true


static func _frame(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and Contract.integer_in_range(value, 0, MAX_FRAME)


static func _vector(point: Dictionary) -> Vector2:
	return Vector2(float(point.x), float(point.y))


static func _point(point: Vector2) -> Dictionary:
	return {"x": point.x, "y": point.y}


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "code": &"HOSTILE_PAYLOAD_INVALID", "context": {"reason": reason}}
