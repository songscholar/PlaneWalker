extends RefCounted

const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Rush := preload("res://scripts/modes/boss_rush_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const Handler := preload("res://scripts/content/effects/effect_handler_catalog.gd")
const SOURCE := "res://assets/production/modes/daily_boss.json"
const PROJECTION_FIELDS := ["day_index", "day_key", "reset_at", "seed", "boss_id", "weapon_id", "time_abilities", "item_ids", "blessing_id", "curse_id", "condition_ids"]
const CONDITION_IDS := ["frail", "melee_specialist", "ranged_specialist"]
const MAX_DAY := 2932896

var _definition: Dictionary = {}
var _fingerprint := ""
var _registry: RefCounted
var _rush: RefCounted
var _conditions: Dictionary = {}


func configure(registry: RefCounted) -> bool:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if not Meta.exact_fields(source, ["schema_version", "mode_id", "utc_offset_seconds", "attempt_limit", "archive_days", "character_id", "starting_hp", "presets", "conditions"]) or source.schema_version != 1 or source.mode_id != "daily_boss" or source.utc_offset_seconds != 28800 or source.attempt_limit != 3 or source.archive_days != 31 or source.character_id != "wanderer" or source.starting_hp != 100 or not source.presets is Array or source.presets.size() != 5 or not source.conditions is Array or source.conditions.size() != 3:
		return false
	var rush := Rush.new()
	if not rush.configure(registry):
		return false
	var weapons := {}
	var handler := Handler.new()
	for row: Variant in source.presets:
		if not Meta.exact_fields(row, ["weapon_id", "time_abilities", "item_ids", "blessing_id", "curse_id"]) or row.weapon_id not in Meta.WEAPON_IDS or weapons.has(row.weapon_id) or not row.time_abilities is Array or row.time_abilities.size() != 2 or row.time_abilities[0] not in Meta.TIME_IDS or row.time_abilities[1] not in Meta.TIME_IDS or row.time_abilities[0] == row.time_abilities[1] or not row.item_ids is Array or row.item_ids.size() != 3:
			return false
		weapons[row.weapon_id] = true
		var ids := {}
		var entries: Array = row.item_ids.duplicate()
		entries.append(row.blessing_id)
		entries.append(row.curse_id)
		for index: int in range(entries.size()):
			var id: Variant = entries[index]
			if not id is String or ids.has(id):
				return false
			ids[id] = true
			var content: Dictionary = registry.get_content(StringName(id))
			var category := "item" if index < 3 else ("blessing" if index == 3 else "curse")
			if content.get("category") != category or not content.get("availability", []).has("LAUNCH") or not content.get("effects") is Dictionary or content.effects.is_empty() or category == "item" and content.get("item_mode") != "passive" or handler.validate_effects(content.effects, {"category": category}).has_blocking_errors():
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
	var conditions := {}
	for row: Variant in source.conditions:
		if not Meta.exact_fields(row, ["id", "name_key", "melee_effects", "ranged_effects"]) or row.id not in CONDITION_IDS or conditions.has(row.id) or not row.name_key is String or not row.name_key.begins_with("UI_DAILY_CONDITION_"):
			return false
		for key: String in ["melee_effects", "ranged_effects"]:
			if not row[key] is Dictionary or row[key].is_empty() or handler.validate_effects(row[key], {"category": "curse"}).has_blocking_errors():
				return false
		conditions[row.id] = row.duplicate(true)
	_definition = source.duplicate(true)
	_fingerprint = Rules.canonical(_definition).sha256_text()
	_registry = registry
	_rush = rush
	_conditions = conditions
	return true


func fingerprint() -> String:
	return _fingerprint


func projection(timestamp: int) -> Dictionary:
	return projection_for_day(day_index(timestamp))


func projection_for_day(day: int) -> Dictionary:
	if _definition.is_empty() or day < 0 or day > MAX_DAY:
		return {}
	var identity := "plane-walker-daily-boss-v1|%s|%d" % [fingerprint(), day]
	var seed := _number(identity, "seed") % Meta.MAX_VALUE
	var boss_index := _number(identity, "boss") % 5
	var preset: Dictionary = _definition.presets[_number(identity, "preset") % 5]
	var rule_index := _number(identity, "rule") % 3
	var conditions: Array = [CONDITION_IDS[rule_index]]
	if _number(identity, "count") % 2 == 1:
		conditions.append(CONDITION_IDS[1 + _number(identity, "second") % 2] if rule_index == 0 else CONDITION_IDS[0])
	var date := Time.get_datetime_dict_from_unix_time(day * 86400)
	return {"day_index": day, "day_key": "%04d-%02d-%02d" % [date.year, date.month, date.day], "reset_at": (day + 1) * 86400 - 28800, "seed": seed, "boss_id": Rush.BOSSES[boss_index], "weapon_id": preset.weapon_id, "time_abilities": preset.time_abilities.duplicate(), "item_ids": preset.item_ids.duplicate(), "blessing_id": preset.blessing_id, "curse_id": preset.curse_id, "condition_ids": conditions}


func calendar(timestamp: int) -> Array:
	var result: Array = []
	for offset: int in range(7):
		result.append(projection_for_day(day_index(timestamp) + offset))
	return result


func valid_projection(value: Variant) -> bool:
	return Meta.exact_fields(value, PROJECTION_FIELDS) and Meta.bounded_int(value.day_index, 0, MAX_DAY) and Rules.same(value, projection_for_day(int(value.day_index)))


func stage(definition: Dictionary) -> Dictionary:
	return _rush.stage(Rush.BOSSES.find(definition.boss_id)) if valid_projection(definition) else {}


func request(definition: Dictionary) -> Dictionary:
	if not valid_projection(definition):
		return {}
	return {"character_id": "wanderer", "weapon_id": definition.weapon_id, "time_abilities": definition.time_abilities.duplicate(), "seed": int(definition.seed), "accessibility_assists": {"damage_received_multiplier": 1.0, "enemy_telegraph_scale": 1.0}}


func build_definitions(definition: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not valid_projection(definition):
		return result
	for id: String in definition.item_ids + [definition.blessing_id, definition.curse_id]:
		result.append(_registry.get_content(StringName(id)))
	var melee: bool = definition.weapon_id in ["sword", "gauntlets"]
	for id: String in definition.condition_ids:
		result.append({"id": "daily_" + id, "category": "curse", "effects": _conditions[id]["melee_effects" if melee else "ranged_effects"].duplicate(true)})
	return result


func condition_key(id: String) -> String:
	return str(_conditions.get(id, {}).get("name_key", ""))


func baseline_definition(max_hp: float) -> Dictionary:
	return {"id": "daily_starting_hp", "category": "curse", "effects": {"max_hp_multiplier": float(_definition.starting_hp) / max_hp}} if max_hp > 0 else {}


static func day_index(timestamp: int) -> int:
	return int(floor(float(timestamp + 28800) / 86400.0))


static func _number(identity: String, channel: String) -> int:
	return (identity + "|" + channel).sha256_text().substr(0, 12).hex_to_int()
