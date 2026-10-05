class_name HostileControlRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const IDENTITY_FIELDS: Array[String] = ["run_id", "hostile_source_id", "runtime_frame"]
const SNAPSHOT_FIELDS: Array[String] = ["schema_version", "identity", "runtime_frame", "terminal", "sources"]
const SOURCE_FIELDS: Array[String] = ["id", "kind", "applied_frame", "expires_through_frame", "magnitude"]
const KINDS: Array[String] = ["stop", "rift", "weakpoint", "vulnerability", "attack_buff", "speed_buff", "attack_debuff"]
const MAX_SOURCES := 64
const MAX_COUNTER := 2147483647

var _state: Dictionary = {}


func configure(identity: Dictionary) -> Dictionary:
	_state.clear()
	if not Contract.exact_fields(identity, IDENTITY_FIELDS):
		return _failure("identity")
	if not _stable_id(identity.run_id) or not _stable_id(identity.hostile_source_id) or not _frame(identity.runtime_frame):
		return _failure("identity")
	_state = {
		"schema_version": 1,
		"identity": {"run_id": identity.run_id, "hostile_source_id": identity.hostile_source_id, "runtime_frame": int(identity.runtime_frame)},
		"runtime_frame": int(identity.runtime_frame), "terminal": false, "sources": [],
	}
	return {"ok": true, "snapshot": snapshot()}


func add_source(source_id: String, kind: String, duration_frames: int, magnitude: float) -> bool:
	if _state.is_empty() or _state.terminal or not _stable_id(source_id) or kind not in KINDS:
		return false
	if duration_frames <= 0 or duration_frames > Contract.MAX_FRAME or not is_finite(magnitude):
		return false
	if _state.sources.size() >= MAX_SOURCES or int(_state.runtime_frame) > MAX_COUNTER - duration_frames:
		return false
	for row: Dictionary in _state.sources:
		if row.id == source_id:
			return false
	match kind:
		"stop":
			if magnitude != 1.0:
				return false
		"rift":
			if magnitude <= 0.0 or magnitude > 1.0:
				return false
			magnitude = maxf(0.40, magnitude)
		"weakpoint", "vulnerability":
			if magnitude <= 0.0 or magnitude > 2.0:
				return false
		"attack_buff", "speed_buff":
			if magnitude < 1.0 or magnitude > 1.25:
				return false
		"attack_debuff":
			if magnitude < 0.8 or magnitude > 1.0:
				return false
	_state.sources.append({"id": source_id, "kind": kind, "applied_frame": _state.runtime_frame, "expires_through_frame": int(_state.runtime_frame) + duration_frames, "magnitude": magnitude})
	_state.sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return true


func clear_source(source_id: String) -> bool:
	if _state.is_empty():
		return false
	for index: int in range(_state.sources.size()):
		if _state.sources[index].id == source_id:
			_state.sources.remove_at(index)
			return true
	return false


func advance_frame(runtime_frame: int) -> Dictionary:
	if _state.is_empty() or _state.terminal or runtime_frame != int(_state.runtime_frame) + 1 or runtime_frame > MAX_COUNTER - Contract.MAX_FRAME:
		return _failure("runtime_frame")
	_state.runtime_frame = runtime_frame
	var retained: Array[Dictionary] = []
	var expired: Array[String] = []
	for row: Dictionary in _state.sources:
		if int(row.expires_through_frame) < runtime_frame:
			expired.append(row.id)
		else:
			retained.append(row)
	_state.sources = retained
	var result := modifiers()
	result["ok"] = true
	result["runtime_frame"] = runtime_frame
	result["expired_sources"] = expired
	return result


func modifiers() -> Dictionary:
	var result := {"action_paused": false, "movement_multiplier": 1.0, "weakpoint_bonus": 0.0, "damage_taken_multiplier": 1.0}
	var speed := 1.0
	var attack_buff := 1.0
	var attack_debuff := 1.0
	var has_attack := false
	for row: Dictionary in _state.get("sources", []):
		match row.kind:
			"stop": result.action_paused = true
			"rift": result.movement_multiplier = minf(float(result.movement_multiplier), float(row.magnitude))
			"weakpoint": result.weakpoint_bonus = maxf(float(result.weakpoint_bonus), float(row.magnitude))
			"vulnerability": result.damage_taken_multiplier = minf(3.0, float(result.damage_taken_multiplier) + float(row.magnitude))
			"speed_buff": speed = maxf(speed, float(row.magnitude))
			"attack_buff":
				has_attack = true
				attack_buff = maxf(attack_buff, float(row.magnitude))
			"attack_debuff":
				has_attack = true
				attack_debuff = minf(attack_debuff, float(row.magnitude))
	result.movement_multiplier = float(result.movement_multiplier) * speed
	if has_attack:
		result["attack_multiplier"] = attack_buff * attack_debuff
	return result


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func matches_snapshot(value: Dictionary) -> bool:
	return _state == value


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, SNAPSHOT_FIELDS):
		return false
	if not Contract.integer_in_range(value.schema_version, 1, 1) or not value.identity is Dictionary or not Contract.exact_fields(value.identity, IDENTITY_FIELDS):
		return false
	if value.identity.run_id != _state.identity.run_id or value.identity.hostile_source_id != _state.identity.hostile_source_id or not _frame(value.identity.runtime_frame) or int(value.identity.runtime_frame) != int(_state.identity.runtime_frame):
		return false
	if not _frame(value.runtime_frame) or int(value.runtime_frame) < int(_state.identity.runtime_frame) or typeof(value.terminal) != TYPE_BOOL:
		return false
	if not value.sources is Array or value.sources.size() > MAX_SOURCES or (value.terminal and not value.sources.is_empty()):
		return false
	var previous_id := ""
	for candidate: Variant in value.sources:
		if not candidate is Dictionary or not Contract.exact_fields(candidate, SOURCE_FIELDS):
			return false
		var row := candidate as Dictionary
		if not _stable_id(row.id) or str(row.id) <= previous_id or row.kind not in KINDS:
			return false
		previous_id = row.id
		if not _frame(row.applied_frame) or not _frame(row.expires_through_frame):
			return false
		if int(row.applied_frame) < int(value.identity.runtime_frame) or int(row.applied_frame) > int(value.runtime_frame):
			return false
		if int(row.expires_through_frame) < int(value.runtime_frame) or int(row.expires_through_frame) <= int(row.applied_frame) or int(row.expires_through_frame) - int(row.applied_frame) > Contract.MAX_FRAME:
			return false
		if not _valid_magnitude(row.kind, row.magnitude):
			return false
	return true


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	_state.schema_version = int(_state.schema_version)
	_state.identity.runtime_frame = int(_state.identity.runtime_frame)
	_state.runtime_frame = int(_state.runtime_frame)
	for row: Dictionary in _state.sources:
		row.applied_frame = int(row.applied_frame)
		row.expires_through_frame = int(row.expires_through_frame)
		row.magnitude = float(row.magnitude)
	return true


func cancel(_reason: StringName = &"cancelled") -> bool:
	if _state.is_empty() or _state.terminal:
		return false
	_state.sources.clear()
	_state.terminal = true
	return true


static func _valid_magnitude(kind: String, value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
		return false
	match kind:
		"stop": return float(value) == 1.0
		"rift": return float(value) >= 0.40 and float(value) <= 1.0
		"weakpoint", "vulnerability": return float(value) > 0.0 and float(value) <= 2.0
		"attack_buff", "speed_buff": return float(value) >= 1.0 and float(value) <= 1.25
		"attack_debuff": return float(value) >= 0.8 and float(value) <= 1.0
	return false


static func _frame(value: Variant) -> bool:
	return Contract.integer_in_range(value, 0, MAX_COUNTER - Contract.MAX_FRAME)


static func _stable_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value == value.strip_edges() and value.length() <= 64


static func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"HOSTILE_CONTROL_INVALID", "context": {"field": field}}
