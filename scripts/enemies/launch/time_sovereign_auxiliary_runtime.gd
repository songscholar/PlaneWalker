class_name TimeSovereignAuxiliaryRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const STATE_FIELDS := ["schema_version", "identity", "runtime_frame", "terminal", "receipts", "marks"]
const IDENTITY_FIELDS := ["run_id", "hostile_source_id", "next_generation_floor", "runtime_frame", "seed"]
const RECEIPT_FIELDS := ["fact_id", "run_id", "owner_source_id", "action_id", "attack_generation", "hit_index", "target_id", "runtime_frame", "actual_loss"]
const MARK_FIELDS := ["target_id", "fact_id", "start_frame", "through_frame", "multiplier"]
const MAX_RECEIPTS := 4096
const MAX_FRAME := 2147483647 - Contract.MAX_FRAME

var _state := {}


func configure(identity: Dictionary) -> bool:
	if not Contract.exact_fields(identity, IDENTITY_FIELDS) or not _id(identity.run_id) or not _id(identity.hostile_source_id) or not Contract.integer_in_range(identity.next_generation_floor, 1, MAX_FRAME) or not Contract.integer_in_range(identity.runtime_frame, 0, MAX_FRAME) or not Contract.integer_in_range(identity.seed, -2147483648, 2147483647):
		return false
	_state = {"schema_version": 1, "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false, "receipts": [], "marks": []}
	return true


func initial_at_frame(frame: int, terminal: bool) -> Dictionary:
	var result := {"schema_version": 1, "identity": _state.identity.duplicate(true), "runtime_frame": frame, "terminal": terminal, "receipts": [], "marks": []}
	return result if can_restore_snapshot(result) else {}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func matches_snapshot(value: Dictionary) -> bool:
	return _state == value


func advance_frame(frame: int) -> bool:
	if _state.is_empty() or frame != int(_state.runtime_frame) + 1 or not Contract.integer_in_range(frame, 0, MAX_FRAME):
		return false
	_state.runtime_frame = frame
	_state.marks = _state.marks.filter(func(mark: Dictionary): return frame < int(mark.through_frame))
	return true


func accept_damage_receipt(fact: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not _valid_receipt(fact, int(_state.runtime_frame)) or fact.runtime_frame != _state.runtime_frame or _state.receipts.size() >= MAX_RECEIPTS or _state.receipts.any(func(row: Dictionary): return row.fact_id == fact.fact_id or _hit_key(row) == _hit_key(fact)):
		return {"ok": false}
	if fact.action_id == "traitor_temporal_slash" and float(fact.actual_loss) > 0.0 and _state.marks.size() >= 8 and not _state.marks.any(func(mark: Dictionary): return mark.target_id == fact.target_id):
		return {"ok": false}
	_state.receipts.append(fact.duplicate(true))
	if fact.action_id == "traitor_temporal_slash" and float(fact.actual_loss) > 0.0:
		_state.marks = _state.marks.filter(func(mark: Dictionary): return mark.target_id != fact.target_id)
		_state.marks.append({"target_id": str(fact.target_id), "fact_id": str(fact.fact_id), "start_frame": int(fact.runtime_frame), "through_frame": int(fact.runtime_frame) + 240, "multiplier": 1.15})
	return {"ok": true}


func time_damage_multiplier(target_id: String) -> float:
	for mark: Dictionary in _state.get("marks", []):
		if mark.target_id == target_id:
			return float(mark.multiplier)
	return 1.0


static func collapse_energy_allowance(energy: float, actual_loss: float) -> float:
	if not is_finite(energy) or not is_finite(actual_loss) or energy <= 1.0 or actual_loss <= 0.0:
		return 0.0
	return minf(10.0, energy - 1.0)


func retire() -> void:
	_state.terminal = true
	_state.marks.clear()


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, STATE_FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or value.identity != _state.identity or not Contract.integer_in_range(value.runtime_frame, int(_state.identity.runtime_frame), MAX_FRAME) or typeof(value.terminal) != TYPE_BOOL or not value.receipts is Array or value.receipts.size() > MAX_RECEIPTS or not value.marks is Array or value.marks.size() > 8 or value.terminal and not value.marks.is_empty():
		return false
	var facts := {}
	var hits := {}
	var latest := {}
	for row: Variant in value.receipts:
		if not row is Dictionary or not _valid_receipt(row, int(value.runtime_frame)) or facts.has(row.fact_id) or hits.has(_hit_key(row)):
			return false
		facts[row.fact_id] = row
		hits[_hit_key(row)] = true
		if row.action_id == "traitor_temporal_slash" and float(row.actual_loss) > 0.0:
			if not latest.has(row.target_id) or int(row.runtime_frame) >= int(latest[row.target_id].runtime_frame):
				latest[row.target_id] = row
	var targets := {}
	for mark: Variant in value.marks:
		if not mark is Dictionary or not Contract.exact_fields(mark, MARK_FIELDS) or not _id(mark.target_id) or targets.has(mark.target_id) or not facts.has(mark.fact_id) or not latest.has(mark.target_id) or latest[mark.target_id].fact_id != mark.fact_id or mark.multiplier != 1.15 or typeof(mark.start_frame) != TYPE_INT or typeof(mark.through_frame) != TYPE_INT or mark.start_frame != facts[mark.fact_id].runtime_frame or mark.through_frame != mark.start_frame + 240 or value.runtime_frame >= mark.through_frame:
			return false
		targets[mark.target_id] = true
	for target: String in latest:
		if not value.terminal and int(value.runtime_frame) < int(latest[target].runtime_frame) + 240 and not targets.has(target):
			return false
	return true


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


func _valid_receipt(row: Dictionary, frame: int) -> bool:
	return Contract.exact_fields(row, RECEIPT_FIELDS) and _id(row.fact_id) and row.run_id == _state.identity.run_id and row.owner_source_id == _state.identity.hostile_source_id and row.action_id in ["traitor_temporal_slash", "traitor_enrage_collapse"] and Contract.integer_in_range(row.attack_generation, int(_state.identity.next_generation_floor), MAX_FRAME) and typeof(row.hit_index) == TYPE_INT and row.hit_index == 0 and _id(row.target_id) and Contract.integer_in_range(row.runtime_frame, int(_state.identity.runtime_frame), frame) and Contract.number_in_range(row.actual_loss, 0.0, 1000000.0)


static func _hit_key(row: Dictionary) -> String:
	return JSON.stringify([row.action_id, row.attack_generation, row.hit_index, row.target_id])


static func _id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 128 and value == value.strip_edges() and not value.contains("\n") and not value.contains("\r")
