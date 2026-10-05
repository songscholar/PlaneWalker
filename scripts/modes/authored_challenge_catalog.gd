extends RefCounted

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Rush := preload("res://scripts/modes/boss_rush_catalog.gd")
const Handler := preload("res://scripts/content/effects/effect_handler_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const SOURCE := "res://assets/production/modes/authored_challenges.json"
const OBJECTIVES := ["total_time", "damage_events", "stage_time", "minimum_hp", "no_damage"]
const SET_FIELDS := ["id", "name_key", "seed", "weapon_id", "time_abilities", "item_ids", "blessing_id", "curse_id", "boss_ids", "objective"]

var _source: Dictionary = {}
var _sets: Dictionary = {}
var _registry: RefCounted
var _rush: RefCounted


func configure(registry: RefCounted, definition: Dictionary = {}) -> bool:
	if not _source.is_empty() or not registry is Registry:
		return false
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE)) if definition.is_empty() else definition
	if not Meta.exact_fields(source, ["schema_version", "mode_id", "character_id", "starting_hp", "history_limit", "sets"]) or source.schema_version != 1 or source.mode_id != "authored_challenges" or source.character_id != "wanderer" or source.starting_hp != 100 or source.history_limit != 10 or not source.sets is Array or source.sets.size() != 5:
		return false
	var rush := Rush.new()
	if not rush.configure(registry):
		return false
	var sets := {}
	var weapons := {}
	var objectives := {}
	var handler := Handler.new()
	for row: Variant in source.sets:
		if not Meta.exact_fields(row, SET_FIELDS) or not row.id is String or not row.id.is_valid_identifier() or row.id.length() > 48 or sets.has(row.id) or not row.name_key is String or not row.name_key.begins_with("UI_AUTHORED_") or not Meta.bounded_int(row.seed, 0, Meta.MAX_VALUE) or row.weapon_id not in Meta.WEAPON_IDS or weapons.has(row.weapon_id) or not row.time_abilities is Array or row.time_abilities.size() != 2 or row.time_abilities[0] not in Meta.TIME_IDS or row.time_abilities[1] not in Meta.TIME_IDS or row.time_abilities[0] == row.time_abilities[1] or not row.item_ids is Array or row.item_ids.size() != 3 or not row.boss_ids is Array or row.boss_ids.size() != 3 or not valid_objective(row.objective) or objectives.has(row.objective.kind):
			return false
		var boss_ids := {}
		for id: Variant in row.boss_ids:
			if id not in Rush.BOSSES or boss_ids.has(id):
				return false
			boss_ids[id] = true
		var ids := {}
		var content_ids: Array = row.item_ids.duplicate()
		content_ids.append(row.blessing_id)
		content_ids.append(row.curse_id)
		for index: int in range(content_ids.size()):
			var id: Variant = content_ids[index]
			if not id is String or ids.has(id):
				return false
			ids[id] = true
			var category := "item" if index < 3 else ("blessing" if index == 3 else "curse")
			var content: Dictionary = registry.get_content(StringName(id))
			if content.get("category") != category or not content.get("availability", []).has("LAUNCH") or category == "item" and content.get("item_mode") != "passive" or not content.get("effects") is Dictionary or content.effects.is_empty() or handler.validate_effects(content.effects, {"category": category}).has_blocking_errors():
				return false
			for effect_id: String in content.effects:
				var descriptor: Dictionary = handler.effect_descriptor(StringName(effect_id))
				if descriptor.get("runtime_domain") != "weapon":
					continue
				var supported := false
				for capability: Dictionary in descriptor.weapon_capabilities:
					supported = supported or capability.weapon_id == row.weapon_id
				if not supported:
					return false
		sets[row.id] = row.duplicate(true)
		weapons[row.weapon_id] = true
		objectives[row.objective.kind] = true
	_source = source.duplicate(true)
	_sets = sets
	_registry = registry
	_rush = rush
	return true


func fingerprint() -> String:
	return Rules.canonical(_source).sha256_text() if not _source.is_empty() else ""


func entries() -> Array:
	return _source.get("sets", []).duplicate(true)


func definition(id: String) -> Dictionary:
	return _sets.get(id, {}).duplicate(true)


func stage(id: String, index: int) -> Dictionary:
	var trial := definition(id)
	if trial.is_empty() or index < 0 or index >= 3:
		return {}
	return _rush.stage(Rush.BOSSES.find(trial.boss_ids[index]))


func request(id: String, index: int) -> Dictionary:
	var trial := definition(id)
	if trial.is_empty() or index < 0 or index >= 3:
		return {}
	return {"character_id": "wanderer", "weapon_id": trial.weapon_id, "time_abilities": trial.time_abilities.duplicate(), "seed": int(trial.seed) + index, "accessibility_assists": {"damage_received_multiplier": 1.0, "enemy_telegraph_scale": 1.0}}


func build_definitions(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var trial := definition(id)
	if not trial.is_empty():
		for content_id: String in trial.item_ids + [trial.blessing_id, trial.curse_id]:
			result.append(_registry.get_content(StringName(content_id)))
	return result


func baseline_definition(max_hp: float) -> Dictionary:
	return {"id": "authored_starting_hp", "category": "curse", "effects": {"max_hp_multiplier": float(_source.starting_hp) / max_hp}} if max_hp > 0 and not _source.is_empty() else {}


static func valid_objective(value: Variant) -> bool:
	if not Meta.exact_fields(value, ["kind", "limit", "name_key"]) or value.kind not in OBJECTIVES or not value.name_key is String or not value.name_key.begins_with("UI_AUTHORED_"):
		return false
	match value.kind:
		"total_time", "stage_time": return Meta.bounded_int(value.limit, 60, 36000)
		"damage_events": return Meta.bounded_int(value.limit, 1, 100)
		"minimum_hp": return Meta.bounded_int(value.limit, 1, 100000)
		"no_damage": return typeof(value.limit) in [TYPE_INT, TYPE_FLOAT] and value.limit == 0
	return false
