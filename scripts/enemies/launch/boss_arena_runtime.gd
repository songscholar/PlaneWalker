class_name BossArenaRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/boss_definition.gd")
const FIELDS := ["schema_version", "definition_digest", "identity", "runtime_frame", "terminal", "covers", "damage_claims"]
const COVER_FIELDS := ["id", "recipe_id", "slot", "position", "radius_px", "max_hp", "current_hp", "broken"]
const FACT_FIELDS := ["fact_id", "run_id", "owner_source_id", "construct_id", "runtime_frame", "amount"]
const CLAIM_FIELDS := ["fact_id", "construct_id", "runtime_frame", "amount"]
const MAX_CLAIMS := 512
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
	_state = {"schema_version": 1, "definition_digest": JSON.stringify(verified.definition.arena, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": int(identity.runtime_frame), "terminal": false, "covers": covers, "damage_claims": []}
	_initial = _state.duplicate(true)
	return {"ok": true, "snapshot": snapshot()}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func cover_snapshot(id: String) -> Dictionary:
	for cover: Dictionary in _state.get("covers", []):
		if cover.id == id:
			return cover.duplicate(true)
	return {}


func accept_damage_fact(fact: Dictionary) -> Dictionary:
	if _state.is_empty() or _state.terminal or not Contract.exact_fields(fact, FACT_FIELDS) or not _id(fact.fact_id) or fact.run_id != _state.identity.run_id or fact.owner_source_id != _state.identity.hostile_source_id or typeof(fact.construct_id) != TYPE_STRING or typeof(fact.runtime_frame) != TYPE_INT or fact.runtime_frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or not Contract.number_in_range(fact.amount, 0.000001, 1000000.0) or _state.damage_claims.size() >= MAX_CLAIMS:
		return _failure("damage_fact")
	for claim: Dictionary in _state.damage_claims:
		if claim.fact_id == fact.fact_id:
			return _failure("duplicate")
	for cover: Dictionary in _state.covers:
		if cover.id != fact.construct_id:
			continue
		if cover.broken:
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
	return true


func retire() -> void:
	if not _state.is_empty():
		_state.terminal = true


func can_restore_snapshot(value: Dictionary, accepted_boundary: bool = false) -> bool:
	if _initial.is_empty() or not Contract.exact_fields(value, FIELDS) or typeof(value.schema_version) != TYPE_INT or value.schema_version != 1 or value.definition_digest != _initial.definition_digest or value.identity != _initial.identity or not Contract.integer_in_range(value.runtime_frame, int(_initial.runtime_frame), 2147483046) or typeof(value.terminal) != TYPE_BOOL or not value.covers is Array or value.covers.size() != 4 or not value.damage_claims is Array or value.damage_claims.size() > MAX_CLAIMS:
		return false
	var losses: Dictionary = {}
	var seen: Dictionary = {}
	for row: Variant in value.damage_claims:
		if not row is Dictionary or not Contract.exact_fields(row, CLAIM_FIELDS) or not _id(row.fact_id) or seen.has(row.fact_id) or typeof(row.construct_id) != TYPE_STRING or not Contract.number_in_range(row.amount, 0.000001, 80.0) or not Contract.integer_in_range(row.runtime_frame, int(_initial.runtime_frame), int(value.runtime_frame) + (0 if accepted_boundary else 1)) or cover_snapshot(str(row.construct_id)).is_empty():
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
	return true


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
