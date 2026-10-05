class_name LaunchEliteAffixRuntime
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Definition := preload("res://scripts/enemies/launch/elite_affix_definition.gd")
const Identity := preload("res://scripts/enemies/launch/launch_enemy_runtime.gd")
const Rules := preload("res://scripts/enemies/launch/elite_affix_rules.gd")
const CONFIGURATION_FIELDS := ["ids", "floor_index", "pending_ids", "damage_taken_multiplier", "knockback_resistance", "native_revision"]
const FIELDS := ["schema_version", "configuration_digest", "identity", "runtime_frame", "terminal", "regeneration"]
const REGENERATION_FIELDS := ["elapsed_frames", "healed_total", "interrupted_through_frame", "last_heal_frame"]

var _configuration: Dictionary = {}
var _max_hp := 0.0
var _state: Dictionary = {}


func configure(configuration: Dictionary, identity: Dictionary, max_hp: float) -> bool:
	if not _state.is_empty() or not _valid_configuration(configuration) or not Contract.exact_fields(identity, Identity.IDENTITY_FIELDS) or not Contract.number_in_range(max_hp, 1.0, 1000000.0) or not Contract.integer_in_range(identity.runtime_frame, 0, Contract.MAX_FRAME) or not Contract.integer_in_range(identity.seed, -2147483648, 2147483647) or not Contract.integer_in_range(identity.next_generation_floor, 1, 2147483646) or not _stable_identity(identity.run_id) or not _stable_identity(identity.hostile_source_id):
		return false
	_configuration = configuration.duplicate(true)
	_max_hp = max_hp
	_state = {"schema_version": 1, "configuration_digest": JSON.stringify({"configuration": _configuration, "max_hp": _max_hp}, "", true, true).sha256_text(), "identity": identity.duplicate(true), "runtime_frame": identity.runtime_frame, "terminal": false, "regeneration": {}}
	if configuration.ids.has("regenerating"):
		_state.regeneration = {"elapsed_frames": 0, "healed_total": 0.0, "interrupted_through_frame": int(identity.runtime_frame), "last_heal_frame": -1}
	return true


static func _valid_configuration(value: Dictionary) -> bool:
	if not Contract.exact_fields(value, CONFIGURATION_FIELDS) or not Contract.integer_in_range(value.native_revision, 2, 2) or not Contract.integer_in_range(value.floor_index, 1, 5) or not value.ids is Array or value.ids.is_empty() or value.ids.size() > 2 or not value.pending_ids is Array:
		return false
	var seen: Array = []
	var pending: Array = []
	var previous := ""
	for id: Variant in value.ids:
		if not id is String or not Rules.MIN_FLOORS.has(id) or id <= previous or int(value.floor_index) < int(Rules.MIN_FLOORS[id]):
			return false
		for other: String in seen:
			if Rules.EXCLUSIONS[id].has(other) or Rules.EXCLUSIONS[other].has(id):
				return false
		seen.append(id)
		previous = id
		if id not in ["frenzy", "fortified", "regenerating"]:
			pending.append(id)
	return value.pending_ids == pending and Contract.number_in_range(value.damage_taken_multiplier, 1.2 if seen.has("frenzy") else 1.0, 1.2 if seen.has("frenzy") else 1.0) and Contract.number_in_range(value.knockback_resistance, 0.2 if seen.has("fortified") else 0.0, 0.2 if seen.has("fortified") else 0.0)


static func _stable_identity(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.is_empty() and value.length() <= 128 and value == value.strip_edges() and not value.contains("\n") and not value.contains("\r")


func advance_frame(frame: int, current_hp: float, dead: bool, paused: bool, healing_multiplier: float) -> Dictionary:
	if _state.is_empty() or _state.terminal or frame != int(_state.runtime_frame) + 1 or not Contract.number_in_range(current_hp, 0.0, _max_hp) or not Contract.number_in_range(healing_multiplier, 0.0, 10.0):
		return {"ok": false}
	_state.runtime_frame = frame
	var healed := 0.0
	if dead:
		_state.terminal = true
	elif not paused and not _state.regeneration.is_empty():
		var regeneration: Dictionary = _state.regeneration
		var parameters: Dictionary = Definition.PARAMETERS.regenerating
		regeneration.elapsed_frames += 1
		if int(regeneration.elapsed_frames) % int(parameters.interval_frames) == 0 and frame > int(regeneration.interrupted_through_frame):
			var available := maxf(0.0, _max_hp * float(parameters.total_heal_fraction_cap) - float(regeneration.healed_total))
			healed = minf(_max_hp - current_hp, minf(available, _max_hp * float(parameters.heal_fraction) * healing_multiplier))
			if healed < 0.000001:
				healed = 0.0
			if healed > 0.0:
				regeneration.healed_total = minf(_max_hp * float(parameters.total_heal_fraction_cap), float(regeneration.healed_total) + healed)
				if is_equal_approx(float(regeneration.healed_total), _max_hp * float(parameters.total_heal_fraction_cap)):
					regeneration.healed_total = _max_hp * float(parameters.total_heal_fraction_cap)
				regeneration.last_heal_frame = frame
	return {"ok": true, "healed_amount": healed, "hp_after": current_hp + healed}


func interrupt_regeneration(frame: int) -> bool:
	if _state.is_empty() or _state.terminal or _state.regeneration.is_empty() or frame not in [int(_state.runtime_frame), int(_state.runtime_frame) + 1] or frame > Contract.MAX_FRAME - int(Definition.PARAMETERS.regenerating.heavy_interrupt_frames):
		return false
	_state.regeneration.interrupted_through_frame = frame + int(Definition.PARAMETERS.regenerating.heavy_interrupt_frames)
	return true


func settle_regeneration_heal(frame: int, planned: float, actual: float, before: Dictionary) -> bool:
	if not can_restore_snapshot(before) or _state.regeneration.is_empty() or before.regeneration.is_empty() or frame != int(_state.runtime_frame) or int(before.runtime_frame) + 1 != frame or not Contract.number_in_range(planned, 0.000001, _max_hp) or not Contract.number_in_range(actual, 0.0, planned) or int(_state.regeneration.last_heal_frame) != frame or not is_equal_approx(float(_state.regeneration.healed_total), float(before.regeneration.healed_total) + planned):
		return false
	var cap := _max_hp * float(Definition.PARAMETERS.regenerating.total_heal_fraction_cap)
	_state.regeneration.healed_total = minf(cap, float(before.regeneration.healed_total) + actual)
	if is_equal_approx(float(_state.regeneration.healed_total), cap):
		_state.regeneration.healed_total = cap
	_state.regeneration.last_heal_frame = frame if actual > 0.0 else int(before.regeneration.last_heal_frame)
	return true


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func cancel() -> void:
	if not _state.is_empty():
		_state.terminal = true


func can_restore_snapshot(value: Dictionary) -> bool:
	if _state.is_empty() or not Contract.exact_fields(value, FIELDS) or value.schema_version != 1 or typeof(value.schema_version) != TYPE_INT or value.configuration_digest != _state.configuration_digest or value.identity != _state.identity or not Contract.integer_in_range(value.runtime_frame, int(_state.identity.runtime_frame), Contract.MAX_FRAME) or not value.terminal is bool or not value.regeneration is Dictionary:
		return false
	if not _configuration.ids.has("regenerating"):
		return value.regeneration.is_empty()
	var state: Dictionary = value.regeneration
	var origin := int(_state.identity.runtime_frame)
	var frame := int(value.runtime_frame)
	if not Contract.exact_fields(state, REGENERATION_FIELDS) or not Contract.integer_in_range(state.elapsed_frames, 0, frame - origin) or not Contract.number_in_range(state.healed_total, 0.0, _max_hp * float(Definition.PARAMETERS.regenerating.total_heal_fraction_cap)) or not Contract.integer_in_range(state.interrupted_through_frame, origin, mini(Contract.MAX_FRAME, frame + 1 + int(Definition.PARAMETERS.regenerating.heavy_interrupt_frames))) or not Contract.integer_in_range(state.last_heal_frame, -1, frame):
		return false
	if state.last_heal_frame != -1 and (state.last_heal_frame < origin + int(Definition.PARAMETERS.regenerating.interval_frames) or state.elapsed_frames < int(Definition.PARAMETERS.regenerating.interval_frames)):
		return false
	return (float(state.healed_total) == 0.0) == (state.last_heal_frame == -1)


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value):
		return false
	_state = value.duplicate(true)
	return true
