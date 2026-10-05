class_name ForestArenaRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "roots", "damage_claims", "phase_retirement", "exposure_through_frame"]
const ROOT_FIELDS := ["id", "recipe_id", "slot", "position", "radius_px", "max_hp", "current_hp", "broken", "retired"]
const FACT_FIELDS := ["fact_id", "run_id", "owner_source_id", "construct_id", "runtime_frame", "amount"]
const CLAIM_FIELDS := ["fact_id", "construct_id", "runtime_frame", "amount"]
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
	_state = {"schema_version": 1, "definition_digest": JSON.stringify(parsed.definition.arena, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false, "roots": roots, "damage_claims": [], "phase_retirement": {}, "exposure_through_frame": int(identity.runtime_frame) - 1}
	_initial = snapshot()
	return {"ok": true, "snapshot": snapshot()}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func is_exposed() -> bool:
	return not _state.is_empty() and not _state.terminal and int(_state.runtime_frame) <= int(_state.exposure_through_frame)


func accept_damage_fact(fact: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.exact_fields(fact, FACT_FIELDS) or not _id(fact.fact_id) or fact.run_id != _state.identity.run_id or fact.owner_source_id != _state.identity.hostile_source_id or typeof(fact.construct_id) != TYPE_STRING or not Contract.integer_in_range(fact.runtime_frame, int(_state.runtime_frame), mini(int(_state.runtime_frame) + 1, MAX_FRAME)) or not Contract.number_in_range(fact.amount, 0.000001, 1000000.0) or _state.damage_claims.size() >= 512:
		return _failure("damage_fact")
	for claim: Dictionary in _state.damage_claims:
		if claim.fact_id == fact.fact_id:
			return _failure("duplicate_damage")
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
	if _initial.is_empty() or not Contract.exact_fields(value, FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or value.definition_digest != _initial.definition_digest or value.identity != _initial.identity or not Contract.integer_in_range(value.runtime_frame, int(_initial.runtime_frame), MAX_FRAME) or typeof(value.terminal) != TYPE_BOOL or not value.roots is Array or value.roots.size() != 6 or not value.damage_claims is Array or value.damage_claims.size() > 512 or not value.phase_retirement is Dictionary:
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
	for fact: Variant in value.damage_claims:
		if not fact is Dictionary or not Contract.exact_fields(fact, CLAIM_FIELDS) or not _id(fact.fact_id) or seen.has(fact.fact_id) or typeof(fact.construct_id) != TYPE_STRING or not roots.has(fact.construct_id) or not Contract.number_in_range(fact.amount, 0.000001, 100.0) or not Contract.integer_in_range(fact.runtime_frame, int(_initial.runtime_frame), int(value.runtime_frame) + (0 if accepted_boundary else 1)):
			return false
		if retired.has(fact.construct_id) and fact.runtime_frame > value.phase_retirement.runtime_frame:
			return false
		seen[fact.fact_id] = true
		losses[fact.construct_id] = float(losses.get(fact.construct_id, 0.0)) + float(fact.amount)
		if losses[fact.construct_id] == 100.0:
			exposure = maxi(exposure, int(fact.runtime_frame) + 44)
	for row: Dictionary in value.roots:
		var loss := float(losses.get(row.id, 0.0))
		if loss > 100.0 or not Contract.number_in_range(row.current_hp, 0.0, 100.0) or not is_equal_approx(float(row.current_hp), 100.0 - loss) or typeof(row.broken) != TYPE_BOOL or row.broken != (loss == 100.0) or typeof(row.retired) != TYPE_BOOL or row.retired != retired.has(row.id):
			return false
	return typeof(value.exposure_through_frame) == TYPE_INT and value.exposure_through_frame == exposure


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true


func normalize_snapshot(value: Dictionary) -> Dictionary:
	return value.duplicate(true) if can_restore_snapshot(value) else {}


func initial_at_frame(frame: int, terminal: bool, phase_index: int = 0) -> Dictionary:
	var value := _initial.duplicate(true)
	value.runtime_frame = frame
	value.terminal = terminal
	if phase_index > 0:
		var ids := _retirement_ids(value, frame)
		value.phase_retirement = {"runtime_frame": frame, "root_ids": ids}
		for row: Dictionary in value.roots:
			row.retired = ids.has(row.id)
	return value if can_restore_snapshot(value, true) else {}


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
