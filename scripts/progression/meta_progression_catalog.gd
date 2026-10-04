class_name MetaProgressionCatalog
extends RefCounted

const CHARACTER_IDS := ["primordial_knight", "time_guardian", "time_lord", "void_walker", "wanderer"]
const WEAPON_IDS := ["bow", "gauntlets", "gun", "staff", "sword"]
const TIME_IDS := ["accelerate", "rewind", "rift", "stop"]
const NPC_IDS := ["elara", "hermes", "morpheus", "nemesis", "odysseus", "phia", "sibyl", "vera"]
const FACTION_IDS := ["council", "merchants", "shardborn", "void_cult"]
const BOSS_IDS := ["forest_heart", "forge_colossus", "ruin_king", "time_sovereign", "void_throne"]
const FLOOR_IDS := ["floor_plane_forge", "floor_ruins_of_remnant", "floor_throne_of_void", "floor_time_rift", "floor_void_forest"]
const HIDDEN_LINE_IDS := ["primordial_whispers", "voice_of_void", "walkers_song"]
const STAT_IDS := ["max_hp", "attack", "defense", "speed", "attack_speed", "entrance_healing", "void_reduction"]
const REFERENCE_CATEGORIES := ["item", "achievement", "cosmetic", "artifact", "environment_record", "narrative_flag", "tutorial_lesson", "tutorial_hint", "training_task", "enchantment", "ending", "archetype"]
const BRANCH_COUNTS := {"W": 10, "C": 8, "L": 10, "F": 8, "P": 6}
const MAX_VALUE := 2147483647

var _definitions: Dictionary = {}
var _references: Dictionary = {}
var _fingerprint := ""


func configure(entries: Array, reference_ids: Dictionary = {}) -> Dictionary:
	if entries.size() != 42:
		return _failure(&"NODE_COUNT_INVALID")
	var candidate: Dictionary = {}
	for value: Variant in entries:
		if not exact_fields(value, ["id", "branch", "cost", "prerequisites", "effects"]):
			return _failure(&"NODE_SHAPE_INVALID")
		var id: Variant = value.id
		if not id is String or not _canonical_node_id(id) or candidate.has(id) or value.branch != id.left(1):
			return _failure(&"NODE_ID_INVALID")
		if not exact_fields(value.cost, ["chronos_shards", "existential_imprints"]) or not bounded_int(value.cost.chronos_shards, 1, MAX_VALUE) or not bounded_int(value.cost.existential_imprints, 0, MAX_VALUE):
			return _failure(&"COST_INVALID", {"node_id": id})
		if not value.prerequisites is Array or value.prerequisites.size() > 8 or not value.effects is Array or value.effects.is_empty() or value.effects.size() > 8:
			return _failure(&"NODE_LIST_INVALID")
		var prerequisites: Array = []
		for prerequisite: Variant in value.prerequisites:
			if not prerequisite is String or not _canonical_node_id(prerequisite) or prerequisite == id or prerequisites.has(prerequisite):
				return _failure(&"PREREQUISITE_INVALID")
			prerequisites.append(prerequisite)
		prerequisites.sort()
		for effect: Variant in value.effects:
			if not _valid_effect(effect):
				return _failure(&"EFFECT_INVALID", {"node_id": id})
		candidate[id] = {"id": id, "branch": value.branch, "cost": {"chronos_shards": int(value.cost.chronos_shards), "existential_imprints": int(value.cost.existential_imprints)}, "prerequisites": prerequisites, "effects": value.effects.duplicate(true)}
	for id: String in candidate:
		if _has_cycle(id, candidate, [], {}):
			return _failure(&"PREREQUISITE_CYCLE")
	var bonuses := empty_stat_bonuses()
	for entry: Dictionary in candidate.values():
		for effect: Dictionary in entry.effects:
			if effect.kind == "stat_bonus":
				bonuses[effect.stat] += float(effect.magnitude)
	if not valid_stat_budget(bonuses):
		return _failure(&"COMBAT_BUDGET_EXCEEDED")
	var references: Dictionary = {}
	for category: Variant in reference_ids:
		if not category is String or not REFERENCE_CATEGORIES.has(category):
			return _failure(&"REFERENCE_CATEGORY_INVALID")
		var refs: Variant = reference_ids[category]
		if not refs is Array or refs.size() > 4096:
			return _failure(&"REFERENCE_LIST_INVALID")
		var normalized: Array = []
		for ref: Variant in refs:
			if not stable_id(ref) or normalized.has(ref):
				return _failure(&"REFERENCE_ID_INVALID")
			normalized.append(ref)
		normalized.sort()
		references[category] = normalized
	_definitions = candidate
	_references = references
	_fingerprint = JSON.stringify({"nodes": snapshot(), "references": _references}, "", true, true).sha256_text()
	return _success({"catalog_fingerprint": _fingerprint})


func definition(id: StringName) -> Dictionary:
	return (_definitions.get(str(id), {}) as Dictionary).duplicate(true)


func ids() -> Array:
	var values := _definitions.keys()
	values.sort()
	return values


func snapshot() -> Array:
	var values: Array = []
	for id: String in ids():
		values.append(definition(StringName(id)))
	return values


func fingerprint() -> String:
	return _fingerprint


func has_reference(category: String, id: String) -> bool:
	return (_references.get(category, []) as Array).has(id)


static func empty_stat_bonuses() -> Dictionary:
	var value: Dictionary = {}
	for id: String in STAT_IDS:
		value[id] = 0.0
	return value


static func valid_stat_budget(value: Variant) -> bool:
	if not exact_fields(value, STAT_IDS):
		return false
	var total := 0.0
	for id: String in STAT_IDS:
		if not finite_number(value[id], 0.0, 0.05):
			return false
		total += float(value[id])
	return total <= 0.15 + 0.000000001


static func bounded_int(value: Variant, minimum: int, maximum: int) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum


static func finite_number(value: Variant, minimum: float, maximum: float) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum + 0.000000000001


static func exact_fields(value: Variant, fields: Array) -> bool:
	if not value is Dictionary or value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func stable_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 96:
		return false
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9][A-Za-z0-9_.:-]*$")
	return pattern.search(value) != null


static func fingerprint_valid(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	var pattern := RegEx.new()
	pattern.compile("^[0-9a-f]{64}$")
	return pattern.search(value) != null


func _canonical_node_id(id: String) -> bool:
	for branch: String in BRANCH_COUNTS:
		for number: int in range(1, int(BRANCH_COUNTS[branch]) + 1):
			if id == "%s-%02d" % [branch, number]:
				return true
	return false


func _valid_effect(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	match value.get("kind"):
		"stat_bonus":
			return exact_fields(value, ["kind", "stat", "magnitude"]) and STAT_IDS.has(value.stat) and finite_number(value.magnitude, 0.01, 0.05) and absf(float(value.magnitude) * 100.0 - roundf(float(value.magnitude) * 100.0)) <= 0.000000000001
		"option":
			return exact_fields(value, ["kind", "option_id"]) and stable_id(value.option_id)
		"soul_retention":
			return exact_fields(value, ["kind", "value"]) and finite_number(value.value, 0.5, 0.7) and float(value.value) in [0.5, 0.7]
		"hub_discount":
			return exact_fields(value, ["kind", "value"]) and finite_number(value.value, 0.0, 0.1) and absf(float(value.value) * 100.0 - roundf(float(value.value) * 100.0)) <= 0.000000000001
	return false


func _has_cycle(id: String, entries: Dictionary, path: Array, visited: Dictionary) -> bool:
	if path.has(id):
		return true
	if visited.has(id):
		return false
	var next_path := path.duplicate()
	next_path.append(id)
	for required: String in entries[id].prerequisites:
		if not entries.has(required) or _has_cycle(required, entries, next_path, visited):
			return true
	visited[id] = true
	return false


static func _success(context: Dictionary = {}) -> Dictionary:
	return {"ok": true, "code": &"OK", "context": context}


static func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context}
