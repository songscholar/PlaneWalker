class_name RunLoadoutCatalog
extends RefCounted

const RunLoadoutPolicyScript := preload("res://scripts/application/run_loadout_policy.gd")

const CHARACTER_ORDER: Array[String] = [
	"wanderer",
	"time_guardian",
	"void_walker",
	"primordial_knight",
	"time_lord",
]
const WEAPON_ORDER: Array[String] = ["sword", "bow", "gun", "staff", "gauntlets"]
const TIME_ABILITY_ORDER: Array[String] = ["stop", "rewind", "rift", "accelerate"]

var _characters: Array[Dictionary] = []
var _weapons: Array[Dictionary] = []
var _time_pairs: Array[Dictionary] = []
var _loadouts: Array[Dictionary] = []
var _milestone := ""
var _last_error: Dictionary = {}


func configure(registry: RefCounted, milestone: StringName = &"LAUNCH") -> bool:
	_clear()
	_milestone = str(milestone)
	if registry == null or not registry.has_method("get_by_category"):
		return _fail("registry_boundary")
	if _milestone.is_empty():
		return _fail("milestone_empty")

	var characters_by_id := _definitions_by_id(
		registry.call("get_by_category", &"character", milestone),
		"character"
	)
	if characters_by_id.is_empty():
		return false
	var weapons_by_id := _definitions_by_id(
		registry.call("get_by_category", &"weapon", milestone),
		"weapon"
	)
	if weapons_by_id.is_empty():
		return false
	var time_abilities_by_id := _definitions_by_id(
		registry.call("get_by_category", &"time_ability", milestone),
		"time_ability"
	)
	if time_abilities_by_id.is_empty():
		return false

	_characters = _ordered_entries(CHARACTER_ORDER, characters_by_id, "character")
	if _characters.size() != CHARACTER_ORDER.size():
		return false
	_weapons = _ordered_entries(WEAPON_ORDER, weapons_by_id, "weapon")
	if _weapons.size() != WEAPON_ORDER.size():
		return false
	var time_abilities := _ordered_entries(TIME_ABILITY_ORDER, time_abilities_by_id, "time_ability")
	if time_abilities.size() != TIME_ABILITY_ORDER.size():
		return false
	_time_pairs = _build_time_pairs(time_abilities)
	if _time_pairs.size() != 6:
		return _fail("time_pair_count", {"actual": _time_pairs.size(), "expected": 6})

	var policy := RunLoadoutPolicyScript.new()
	for character: Dictionary in _characters:
		for weapon: Dictionary in _weapons:
			for time_pair: Dictionary in _time_pairs:
				var config := {
					"schema_version": 1,
					"milestone": _milestone,
					"character_id": str(character.get("id", "")),
					"weapon_id": str(weapon.get("id", "")),
					"enabled_time_skills": (
						time_pair.get("ability_ids", []) as Array
					).duplicate(),
					"difficulty": "normal",
				}
				var validation = policy.validate(config, registry)
				if not validation.ok:
					return _fail(
						"loadout_rejected",
						{
							"config": config.duplicate(true),
							"code": str(validation.code),
							"context": validation.context.duplicate(true),
						}
					)
				_loadouts.append(config)
	if _loadouts.size() != 150:
		return _fail("loadout_count", {"actual": _loadouts.size(), "expected": 150})
	return true


func is_ready() -> bool:
	return (
		_characters.size() == 5
		and _weapons.size() == 5
		and _time_pairs.size() == 6
		and _loadouts.size() == 150
	)


func milestone() -> String:
	return _milestone


func characters() -> Array[Dictionary]:
	return _deep_copy_entries(_characters)


func weapons() -> Array[Dictionary]:
	return _deep_copy_entries(_weapons)


func time_pairs() -> Array[Dictionary]:
	return _deep_copy_entries(_time_pairs)


func loadouts() -> Array[Dictionary]:
	return _deep_copy_entries(_loadouts)


func last_error() -> Dictionary:
	return _last_error.duplicate(true)


func _definitions_by_id(value: Variant, expected_category: String) -> Dictionary:
	if not value is Array:
		_fail("category_query_type", {"category": expected_category})
		return {}
	var definitions_by_id := {}
	for definition_value: Variant in value:
		if not definition_value is Dictionary:
			_fail("definition_type", {"category": expected_category})
			return {}
		var definition: Dictionary = definition_value
		if str(definition.get("category", "")) != expected_category:
			_fail(
				"category_mismatch",
				{
					"category": expected_category,
					"actual": str(definition.get("category", "")),
				}
			)
			return {}
		var content_id := str(definition.get("id", ""))
		if content_id.is_empty() or definitions_by_id.has(content_id):
			_fail(
				"missing_or_duplicate_id",
				{"category": expected_category, "content_id": content_id}
			)
			return {}
		definitions_by_id[content_id] = definition.duplicate(true)
	if definitions_by_id.is_empty():
		_fail("category_empty", {"category": expected_category})
		return {}
	return definitions_by_id


func _ordered_entries(order: Array[String], definitions_by_id: Dictionary, category: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for content_id: String in order:
		var definition_value: Variant = definitions_by_id.get(content_id, {})
		if not definition_value is Dictionary or (definition_value as Dictionary).is_empty():
			_fail("required_content_missing", {"category": category, "content_id": content_id})
			return []
		var definition: Dictionary = definition_value
		var name_key := str(definition.get("name_key", ""))
		var description_key := str(definition.get("description_key", ""))
		if name_key.is_empty() or description_key.is_empty():
			_fail("localization_key_missing", {"category": category, "content_id": content_id})
			return []
		entries.append({
			"id": content_id,
			"name_key": name_key,
			"description_key": description_key,
		})
	return entries


func _build_time_pairs(time_abilities: Array[Dictionary]) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	for first_index: int in range(time_abilities.size() - 1):
		for second_index: int in range(first_index + 1, time_abilities.size()):
			var first: Dictionary = time_abilities[first_index]
			var second: Dictionary = time_abilities[second_index]
			var first_id := str(first.get("id", ""))
			var second_id := str(second.get("id", ""))
			pairs.append({
				"id": "%s+%s" % [first_id, second_id],
				"ability_ids": [first_id, second_id],
				"name_keys": [str(first.get("name_key", "")), str(second.get("name_key", ""))],
				"description_keys": [
					str(first.get("description_key", "")),
					str(second.get("description_key", "")),
				],
			})
	return pairs


func _deep_copy_entries(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in source:
		result.append(entry.duplicate(true))
	return result


func _clear() -> void:
	_characters.clear()
	_weapons.clear()
	_time_pairs.clear()
	_loadouts.clear()
	_milestone = ""
	_last_error.clear()


func _fail(reason: String, context: Dictionary = {}) -> bool:
	_last_error = context.duplicate(true)
	_last_error["reason"] = reason
	_characters.clear()
	_weapons.clear()
	_time_pairs.clear()
	_loadouts.clear()
	return false
