class_name HostileActionCoordinator
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Telegraph := preload("res://scripts/combat/hostile_telegraph_fact.gd")
const DEFINITION_FIELDS: Array[String] = ["id", "actor_kind", "actions"]
const IDENTITY_FIELDS: Array[String] = ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame"]
const CONTEXT_FIELDS: Array[String] = ["runtime_frame", "source_position", "target_position", "facing_direction", "target_id"]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version", "definition_digest", "identity", "last_runtime_frame",
	"next_generation_floor", "decision_index", "phase", "action_id", "commit_frame",
	"committed_origin", "committed_target", "committed_aim", "target_id",
	"committed_geometry", "geometry_generations", "resolved_hit_indices", "cooldowns", "idle_through_frame", "paused_frames",
]
const MAX_COUNTER := 2147483647
const BOSS_ACTION_PREFIXES := {"ruin_king": "guardian_", "forest_heart": "matriarch_", "time_sovereign": "traitor_", "forge_colossus": "forge_", "void_throne": "voidking_"}

var _actions: Dictionary = {}
var _definition: Dictionary = {}
var _state: Dictionary = {}


func configure(definition: Dictionary, identity: Dictionary) -> Dictionary:
	_actions.clear()
	_definition.clear()
	_state.clear()
	if not Contract.exact_fields(definition, DEFINITION_FIELDS) or not Contract.valid_id(definition.id):
		return _failure("definition", "invalid")
	if typeof(definition.actor_kind) != TYPE_STRING or definition.actor_kind not in Contract.ACTOR_KINDS:
		return _failure("actor_kind", "unsupported")
	if not definition.actions is Array or definition.actions.is_empty() or definition.actions.size() > 64:
		return _failure("actions", "invalid_array")
	if not _valid_identity(identity):
		return _failure("identity", "invalid")
	var normalized_actions: Array[Dictionary] = []
	for candidate: Variant in definition.actions:
		if not candidate is Dictionary:
			return _failure("actions", "invalid_record")
		var normalized := Contract.create(candidate, definition.actor_kind)
		if not normalized.ok:
			return normalized
		var action: Dictionary = normalized.definition
		if _actions.has(action.id) or not _action_belongs_to_actor(action.id, definition.id, definition.actor_kind):
			_actions.clear()
			return _failure("actions.id", "duplicate_or_foreign")
		_actions[action.id] = action
		normalized_actions.append(action.duplicate(true))
	_definition = {"id": definition.id, "actor_kind": definition.actor_kind, "actions": normalized_actions}
	var normalized_identity := {
		"run_id": identity.run_id, "hostile_source_id": identity.hostile_source_id,
		"next_generation_floor": int(identity.next_generation_floor), "runtime_frame": int(identity.runtime_frame),
	}
	_state = {
		"schema_version": 1, "definition_digest": _digest(_definition), "identity": normalized_identity,
		"last_runtime_frame": int(identity.runtime_frame), "next_generation_floor": int(identity.next_generation_floor),
		"decision_index": 0, "phase": "IDLE", "action_id": "", "commit_frame": -1,
		"committed_origin": {}, "committed_target": {}, "committed_aim": {}, "target_id": "",
		"committed_geometry": [], "geometry_generations": [], "resolved_hit_indices": [],
		"cooldowns": {}, "idle_through_frame": int(identity.runtime_frame) - 1, "paused_frames": 0,
	}
	return {"ok": true, "snapshot": snapshot(), "context": {}}


static func _action_belongs_to_actor(action_id: String, definition_id: String, actor_kind: String) -> bool:
	if actor_kind != "boss":
		return action_id.begins_with(definition_id + ".")
	return BOSS_ACTION_PREFIXES.has(definition_id) and (action_id.begins_with(BOSS_ACTION_PREFIXES[definition_id]) or (definition_id == "time_sovereign" and action_id.begins_with("traitor.counter_")))


func request_action(action_id: String, context: Dictionary) -> Dictionary:
	if _state.is_empty() or not _actions.has(action_id):
		return _failure("action_id", "unknown")
	if not _valid_context(context, int(_state.last_runtime_frame)):
		return _failure("context", "invalid")
	if _state.phase != "IDLE" or int(_state.last_runtime_frame) <= int(_state.idle_through_frame):
		return _failure("phase", "busy")
	if int(_state.cooldowns.get(action_id, 0)) > int(_state.last_runtime_frame):
		return _failure("cooldown", "not_ready")
	var action: Dictionary = _actions[action_id]
	var source := _vector(_quantized_point(_vector(context.source_position)))
	var target := _vector(_quantized_point(_vector(context.target_position)))
	var distance := source.distance_to(target)
	if distance < float(action.distance_min_px) or distance > float(action.distance_max_px):
		return _failure("distance", "outside_selection_range")
	var aim := source.direction_to(target)
	if aim.is_zero_approx():
		aim = _vector(context.facing_direction).normalized()
	var count := maxi(1, action.geometry.size())
	if int(_state.next_generation_floor) > MAX_COUNTER - count or int(_state.decision_index) == MAX_COUNTER:
		return _failure("generation", "exhausted")
	var next := _state.duplicate(true)
	next.phase = "WARNING"
	next.action_id = action_id
	next.commit_frame = int(next.last_runtime_frame)
	next.committed_origin = _quantized_point(source)
	next.committed_target = _quantized_point(target)
	next.committed_aim = _point(aim)
	next.target_id = context.target_id
	next.geometry_generations = []
	for index: int in range(count):
		next.geometry_generations.append(int(next.next_generation_floor) + index)
	next.next_generation_floor = int(next.next_generation_floor) + count
	next.decision_index = int(next.decision_index) + 1
	next.resolved_hit_indices = []
	next.paused_frames = 0
	next.cooldowns[action_id] = int(next.commit_frame) + int(action.cooldown_frames)
	next.idle_through_frame = int(next.commit_frame) + int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames) + int(action.idle_frames) - 1
	next.committed_geometry = _committed_geometry(action, next)
	_state = next
	return {
		"ok": true, "phase": "WARNING", "action_id": action_id, "handler_id": action.handler_id,
		"attack_generation": _state.geometry_generations[0], "threat_facts": _state.committed_geometry.duplicate(true),
		"hit_facts": [], "retired_generations": [], "cue_id": action.cue_id,
	}


func advance_frame(runtime_frame: int, observations: Dictionary, action_paused: bool = false) -> Dictionary:
	if _state.is_empty() or runtime_frame != int(_state.last_runtime_frame) + 1 or runtime_frame > MAX_COUNTER - Contract.MAX_FRAME:
		return _failure("runtime_frame", "nonsequential")
	if not _valid_context(observations, runtime_frame):
		return _failure("observations", "invalid")
	var next := _state.duplicate(true)
	next.last_runtime_frame = runtime_frame
	var hits: Array[Dictionary] = []
	var retire: Array = []
	var effects: Array[Dictionary] = []
	var extensions: Array[Dictionary] = []
	if not str(next.action_id).is_empty():
		var action: Dictionary = _actions[next.action_id]
		if action_paused:
			if int(next.paused_frames) >= Contract.MAX_FRAME:
				return _failure("paused_frames", "duration_exceeds_bound")
			next.paused_frames = int(next.paused_frames) + 1
			next.idle_through_frame = int(next.idle_through_frame) + 1
			for fact: Dictionary in next.committed_geometry:
				extensions.append({"hostile_source_id": next.identity.hostile_source_id, "attack_generation": fact.attack_generation, "expected_through_frame": fact.active_through_frame, "new_through_frame": int(fact.active_through_frame) + 1})
				fact.active_through_frame = int(fact.active_through_frame) + 1
		var elapsed := runtime_frame - int(next.commit_frame) - int(next.paused_frames)
		next.phase = action_phase(elapsed, action)
		if next.phase == "ACTIVE":
			var active_offset := elapsed - int(action.warning_frames)
			for scheduled: Dictionary in action.hit_schedule:
				if int(scheduled.offset_frame) == active_offset and not next.resolved_hit_indices.has(scheduled.hit_index):
					next.resolved_hit_indices.append(scheduled.hit_index)
					hits.append(_hit_fact(scheduled, action, next))
			if active_offset == 0 and not action_paused:
				effects.append({
					"run_id": next.identity.run_id, "hostile_source_id": next.identity.hostile_source_id,
					"attack_generation": next.geometry_generations[0], "runtime_frame": runtime_frame,
					"action_id": next.action_id, "handler_id": action.handler_id,
					"parameters": action.parameters.duplicate(true), "geometry": next.committed_geometry.duplicate(true),
					"target_id": next.target_id,
				})
		if next.phase == "IDLE":
			retire = next.geometry_generations.duplicate()
			_clear_action(next)
	_state = next
	return {"ok": true, "runtime_frame": runtime_frame, "phase": _state.phase, "hit_facts": hits, "effect_requests": effects, "retired_generations": retire, "threat_extensions": extensions}


func cancel(reason: StringName) -> Dictionary:
	if _state.is_empty() or reason == &"":
		return _failure("cancel", "invalid")
	var retired: Array = _state.geometry_generations.duplicate()
	_clear_action(_state)
	_state.idle_through_frame = int(_state.last_runtime_frame) - 1
	return {"ok": true, "reason": reason, "retired_generations": retired, "hit_facts": []}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, SNAPSHOT_FIELDS):
		return false
	if typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or value.definition_digest != _state.definition_digest or value.identity != _state.identity:
		return false
	for field: String in ["last_runtime_frame", "next_generation_floor", "decision_index", "commit_frame", "idle_through_frame", "paused_frames"]:
		if typeof(value[field]) != TYPE_INT:
			return false
	if value.last_runtime_frame < int(_state.identity.runtime_frame) or value.last_runtime_frame > MAX_COUNTER - Contract.MAX_FRAME:
		return false
	if value.next_generation_floor < int(_state.identity.next_generation_floor) or value.next_generation_floor > MAX_COUNTER or value.decision_index < 0 or value.decision_index > MAX_COUNTER:
		return false
	if value.paused_frames < 0 or value.paused_frames > Contract.MAX_FRAME:
		return false
	if typeof(value.phase) != TYPE_STRING or typeof(value.action_id) != TYPE_STRING or typeof(value.target_id) != TYPE_STRING:
		return false
	if not value.geometry_generations is Array or not value.resolved_hit_indices is Array or not value.committed_geometry is Array or not value.cooldowns is Dictionary:
		return false
	if value.idle_through_frame < int(value.identity.runtime_frame) - 1 or value.idle_through_frame > value.last_runtime_frame + Contract.MAX_FRAME * 4:
		return false
	for action_id: Variant in value.cooldowns:
		if typeof(action_id) != TYPE_STRING or not _actions.has(action_id) or typeof(value.cooldowns[action_id]) != TYPE_INT:
			return false
		if value.cooldowns[action_id] < int(value.identity.runtime_frame) or value.cooldowns[action_id] > value.last_runtime_frame + Contract.MAX_FRAME:
			return false
	if value.action_id.is_empty():
		return value.phase == "IDLE" and value.commit_frame == -1 and value.committed_origin == {} and value.committed_target == {} and value.committed_aim == {} and value.target_id == "" and value.committed_geometry == [] and value.geometry_generations == [] and value.resolved_hit_indices == [] and value.paused_frames == 0
	if not _actions.has(value.action_id) or value.decision_index < 1 or not _valid_stable_id(value.target_id):
		return false
	var action: Dictionary = _actions[value.action_id]
	if value.commit_frame < int(value.identity.runtime_frame) or value.commit_frame > value.last_runtime_frame:
		return false
	var elapsed: int = value.last_runtime_frame - value.commit_frame - value.paused_frames
	if elapsed < 0:
		return false
	if value.phase != action_phase(elapsed, action) or value.phase == "IDLE":
		return false
	if not Contract.valid_point(value.committed_origin) or not Contract.valid_point(value.committed_target) or not Contract.valid_point(value.committed_aim, 1):
		return false
	if not _is_quantized(value.committed_origin) or not _is_quantized(value.committed_target) or not is_equal_approx(_vector(value.committed_aim).length(), 1):
		return false
	var target_direction := _vector(value.committed_origin).direction_to(_vector(value.committed_target))
	if not target_direction.is_zero_approx() and not _vector(value.committed_aim).is_equal_approx(target_direction):
		return false
	if value.geometry_generations.size() != maxi(1, action.geometry.size()):
		return false
	for index: int in range(value.geometry_generations.size()):
		var generation: Variant = value.geometry_generations[index]
		if typeof(generation) != TYPE_INT or generation < int(value.identity.next_generation_floor) or generation >= value.next_generation_floor:
			return false
		if index > 0 and generation != value.geometry_generations[index - 1] + 1:
			return false
	if value.next_generation_floor != value.geometry_generations.back() + 1 or value.committed_geometry != _committed_geometry(action, value):
		return false
	var expected_claims: Array = []
	for hit: Dictionary in action.hit_schedule:
		if elapsed >= int(action.warning_frames) + int(hit.offset_frame):
			expected_claims.append(hit.hit_index)
	if value.resolved_hit_indices != expected_claims or value.cooldowns.get(value.action_id, -1) != value.commit_frame + int(action.cooldown_frames):
		return false
	return value.idle_through_frame == value.commit_frame + int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames) + int(action.idle_frames) + value.paused_frames - 1


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


func active_threat_facts() -> Array:
	return _state.get("committed_geometry", []).duplicate(true)


static func native_threat_fact(value: Dictionary) -> Dictionary:
	if not Contract.exact_fields(value, Telegraph.FIELDS):
		return {}
	for field: String in ["origin", "aim_direction", "target_point"]:
		if not Contract.valid_point(value[field]):
			return {}
	if not value.summon_slots is Array:
		return {}
	var native := value.duplicate(true)
	for field: String in ["origin", "aim_direction", "target_point"]:
		native[field] = _vector(value[field])
	var slots: Array[Vector2] = []
	for candidate: Variant in value.summon_slots:
		if not Contract.valid_point(candidate):
			return {}
		slots.append(_vector(candidate))
	native.summon_slots = slots
	return Telegraph.create(native)


static func action_phase(elapsed: int, action: Dictionary) -> String:
	if elapsed < int(action.warning_frames):
		return "WARNING"
	if elapsed < int(action.warning_frames) + int(action.active_frames):
		return "ACTIVE"
	if elapsed < int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames):
		return "RECOVERY"
	return "IDLE"


static func _committed_geometry(action: Dictionary, state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source := _vector(state.committed_origin)
	var target := _vector(state.committed_target)
	var aim := _vector(state.committed_aim)
	var through: int = int(state.commit_frame) + int(action.warning_frames) + int(action.active_frames) + int(action.recovery_frames) + int(state.paused_frames) - 1
	for index: int in range(action.geometry.size()):
		var primitive: Dictionary = action.geometry[index]
		var offset := _vector(primitive.origin_offset).rotated(aim.angle())
		var origin := target + offset if primitive.shape == "target_circle" else source + offset
		var slots: Array = [_point(origin)] if primitive.shape == "summon_slots" else []
		result.append({
			"hostile_source_id": state.identity.hostile_source_id, "attack_generation": state.geometry_generations[index],
			"shape": primitive.shape, "origin": _point(origin),
			"aim_direction": _point(aim.rotated(deg_to_rad(primitive.aim_offset_degrees))),
			"target_point": _point(origin) if primitive.shape == "target_circle" else state.committed_target.duplicate(true), "summon_slots": slots,
			"radius": primitive.radius, "length": primitive.length,
			"active_from_frame": state.commit_frame, "active_through_frame": through,
		})
	return result


static func _hit_fact(hit: Dictionary, action: Dictionary, state: Dictionary) -> Dictionary:
	return {
		"run_id": state.identity.run_id, "hostile_source_id": state.identity.hostile_source_id,
		"attack_generation": state.geometry_generations[0], "hit_index": hit.hit_index,
		"runtime_frame": state.last_runtime_frame, "target_id": state.target_id, "action_id": state.action_id,
		"damage": hit.damage, "damage_type": hit.damage_type, "handler_id": action.handler_id,
		"geometry": state.committed_geometry.duplicate(true), "parameters": action.parameters.duplicate(true),
	}


static func _clear_action(state: Dictionary) -> void:
	state.phase = "IDLE"
	state.action_id = ""
	state.commit_frame = -1
	state.committed_origin = {}
	state.committed_target = {}
	state.committed_aim = {}
	state.target_id = ""
	state.committed_geometry = []
	state.geometry_generations = []
	state.resolved_hit_indices = []
	state.paused_frames = 0


static func _valid_identity(value: Dictionary) -> bool:
	return Contract.exact_fields(value, IDENTITY_FIELDS) and _valid_stable_id(value.run_id) and _valid_stable_id(value.hostile_source_id) and Contract.integer_in_range(value.next_generation_floor, 1, MAX_COUNTER - Contract.MAX_PRIMITIVES) and Contract.integer_in_range(value.runtime_frame, 0, MAX_COUNTER - Contract.MAX_FRAME)


static func _valid_context(value: Dictionary, frame: int) -> bool:
	if not Contract.exact_fields(value, CONTEXT_FIELDS) or typeof(value.runtime_frame) != TYPE_INT or value.runtime_frame != frame or not _valid_stable_id(value.target_id):
		return false
	return Contract.valid_point(value.source_position) and Contract.valid_point(value.target_position) and Contract.valid_point(value.facing_direction, 1) and not _vector(value.facing_direction).is_zero_approx()


static func _valid_stable_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 64 or value.strip_edges() != value:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if code < 33 or code > 126:
			return false
	return true


static func _vector(value: Dictionary) -> Vector2:
	return Vector2(float(value.x), float(value.y))


static func _point(value: Vector2) -> Dictionary:
	return {"x": float(value.x), "y": float(value.y)}


static func _quantized_point(value: Vector2) -> Dictionary:
	return {"x": snappedf(value.x, 1.0 / 256.0), "y": snappedf(value.y, 1.0 / 256.0)}


static func _is_quantized(value: Dictionary) -> bool:
	return float(value.x) == snappedf(float(value.x), 1.0 / 256.0) and float(value.y) == snappedf(float(value.y), 1.0 / 256.0)


static func _digest(value: Dictionary) -> String:
	return JSON.stringify(_canonical(value)).sha256_text()


static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var ordered: Dictionary = {}
		for key: String in keys:
			ordered[key] = _canonical(value[key])
		return ordered
	if value is Array:
		var ordered: Array = []
		for entry: Variant in value:
			ordered.append(_canonical(entry))
		return ordered
	return value


static func _failure(field: String, reason: String) -> Dictionary:
	return {"ok": false, "code": &"HOSTILE_FRAME_INVALID", "context": {"field": field, "reason": reason}}
