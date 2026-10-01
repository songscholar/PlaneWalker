class_name PlayerLoadoutRuntime
extends Node

var _config: Dictionary = {
	"weapon_id": "sword",
	"enabled_time_skills": ["stop", "rewind"],
}
var _weapon_id: StringName = &"sword"
var _time_ability_ids: Array[StringName] = [&"stop", &"rewind"]
var _weapon_profile: Dictionary = {}
var _character_id: StringName = &"wanderer"
var _character_profile: Dictionary = {}
var _character_talent_ids: Array[StringName] = []
var _character_talent_definitions: Array[Dictionary] = []


func configure(config: Dictionary) -> bool:
	var raw_character_id: Variant = config.get("character_id", "wanderer")
	if typeof(raw_character_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var next_character_id := StringName(str(raw_character_id))
	if next_character_id == &"":
		return false
	var next_character_profile: Dictionary = {}
	if config.has("character_profile"):
		var raw_character_profile: Variant = config.get("character_profile")
		if not raw_character_profile is Dictionary or (raw_character_profile as Dictionary).is_empty():
			return false
		next_character_profile = (raw_character_profile as Dictionary).duplicate(true)
		var raw_character_profile_id: Variant = next_character_profile.get("id")
		var raw_profile_character_id: Variant = next_character_profile.get("character_id")
		if (
			typeof(raw_character_profile_id) not in [TYPE_STRING, TYPE_STRING_NAME]
			or str(raw_character_profile_id).is_empty()
			or typeof(raw_profile_character_id) not in [TYPE_STRING, TYPE_STRING_NAME]
			or StringName(str(raw_profile_character_id)) != next_character_id
		):
			return false
		if next_character_profile.has("runtime_kind"):
			var raw_character_runtime_kind: Variant = next_character_profile.get("runtime_kind")
			if (
				typeof(raw_character_runtime_kind) not in [TYPE_STRING, TYPE_STRING_NAME]
				or str(raw_character_runtime_kind).is_empty()
			):
				return false

	var next_character_talent_ids: Array[StringName] = []
	var raw_character_talent_ids: Variant = config.get("character_talents", [])
	if not raw_character_talent_ids is Array:
		return false
	for raw_talent_id: Variant in raw_character_talent_ids as Array:
		if typeof(raw_talent_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var talent_id := StringName(str(raw_talent_id))
		if talent_id == &"" or next_character_talent_ids.has(talent_id):
			return false
		next_character_talent_ids.append(talent_id)
	if not next_character_profile.is_empty():
		var allowed_talents_value: Variant = next_character_profile.get("talent_ids", [])
		if not allowed_talents_value is Array:
			return false
		for talent_id: StringName in next_character_talent_ids:
			if not (allowed_talents_value as Array).has(str(talent_id)):
				return false
		var canonical_talent_ids: Array[StringName] = []
		for allowed_talent_value: Variant in allowed_talents_value as Array:
			if typeof(allowed_talent_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return false
			var allowed_talent_id := StringName(str(allowed_talent_value))
			if next_character_talent_ids.has(allowed_talent_id):
				canonical_talent_ids.append(allowed_talent_id)
		if canonical_talent_ids.size() != next_character_talent_ids.size():
			return false
		next_character_talent_ids = canonical_talent_ids

	var raw_talent_definitions: Variant = config.get("character_talent_definitions", [])
	if not raw_talent_definitions is Array:
		return false
	var talent_definitions_by_id: Dictionary = {}
	for definition_value: Variant in raw_talent_definitions as Array:
		if not definition_value is Dictionary:
			return false
		var definition := (definition_value as Dictionary).duplicate(true)
		var definition_id := StringName(str(definition.get("id", "")))
		if (
			definition_id == &""
			or talent_definitions_by_id.has(definition_id)
			or not next_character_talent_ids.has(definition_id)
			or str(definition.get("category", "")) != "talent"
			or not definition.get("effects") is Dictionary
			or (definition.get("effects") as Dictionary).is_empty()
			or not definition.get("compatibility") is Dictionary
			or (definition.get("compatibility") as Dictionary).get(
				"character_ids", []
			) != [str(next_character_id)]
		):
			return false
		talent_definitions_by_id[definition_id] = definition
	if talent_definitions_by_id.size() != next_character_talent_ids.size():
		return false
	var next_character_talent_definitions: Array[Dictionary] = []
	for talent_id: StringName in next_character_talent_ids:
		if not talent_definitions_by_id.has(talent_id):
			return false
		next_character_talent_definitions.append(
			(talent_definitions_by_id[talent_id] as Dictionary).duplicate(true)
		)

	var raw_weapon_id: Variant = config.get("weapon_id")
	if typeof(raw_weapon_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	var next_weapon_id := StringName(str(raw_weapon_id))
	if next_weapon_id == &"":
		return false
	var next_weapon_profile: Dictionary = {}
	if config.has("weapon_profile"):
		var raw_weapon_profile: Variant = config.get("weapon_profile")
		if not raw_weapon_profile is Dictionary or (raw_weapon_profile as Dictionary).is_empty():
			return false
		next_weapon_profile = (raw_weapon_profile as Dictionary).duplicate(true)
		var raw_profile_id: Variant = next_weapon_profile.get("id")
		var raw_profile_weapon_id: Variant = next_weapon_profile.get("weapon_id")
		if typeof(raw_profile_id) not in [TYPE_STRING, TYPE_STRING_NAME] or str(raw_profile_id).is_empty():
			return false
		if typeof(raw_profile_weapon_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		if StringName(str(raw_profile_weapon_id)) != next_weapon_id:
			return false
		if next_weapon_profile.has("runtime_kind"):
			var raw_runtime_kind: Variant = next_weapon_profile.get("runtime_kind")
			if typeof(raw_runtime_kind) not in [TYPE_STRING, TYPE_STRING_NAME]:
				return false
			if StringName(str(raw_runtime_kind)) != next_weapon_id:
				return false

	var raw_time_ability_ids: Variant = config.get("enabled_time_skills")
	if not raw_time_ability_ids is Array or raw_time_ability_ids.size() != 2:
		return false
	var next_time_ability_ids: Array[StringName] = []
	for raw_ability_id: Variant in raw_time_ability_ids:
		if typeof(raw_ability_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var ability_id := StringName(str(raw_ability_id))
		if ability_id == &"" or next_time_ability_ids.has(ability_id):
			return false
		next_time_ability_ids.append(ability_id)

	_config = config.duplicate(true)
	_character_id = next_character_id
	_character_profile = next_character_profile.duplicate(true)
	_character_talent_ids = next_character_talent_ids.duplicate()
	_character_talent_definitions = next_character_talent_definitions.duplicate(true)
	_weapon_id = next_weapon_id
	_time_ability_ids = next_time_ability_ids.duplicate()
	_weapon_profile = next_weapon_profile.duplicate(true)
	return true


func snapshot() -> Dictionary:
	return _config.duplicate(true)


func weapon_id() -> StringName:
	return _weapon_id


func character_id() -> StringName:
	return _character_id


func character_profile_id() -> StringName:
	return StringName(str(_character_profile.get("id", "")))


func character_profile_snapshot() -> Dictionary:
	return _character_profile.duplicate(true)


func character_talent_ids() -> Array:
	return _character_talent_ids.duplicate(true)


func character_talent_definitions() -> Array[Dictionary]:
	return _character_talent_definitions.duplicate(true)


func install_character_talent(definition: Dictionary) -> bool:
	if _character_profile.is_empty():
		return false
	var talent_id := StringName(str(definition.get("id", "")))
	var allowed: Array = _character_profile.get("talent_ids", [])
	if (
		talent_id == &""
		or _character_talent_ids.has(talent_id)
		or not allowed.has(str(talent_id))
		or str(definition.get("category", "")) != "talent"
		or not definition.get("effects") is Dictionary
		or (definition.get("effects") as Dictionary).is_empty()
		or not definition.get("compatibility") is Dictionary
		or (definition.get("compatibility") as Dictionary).get(
			"character_ids", []
		) != [str(_character_id)]
	):
		return false
	var candidate := _config.duplicate(true)
	var ids: Array = candidate.get("character_talents", []).duplicate()
	var definitions: Array = candidate.get(
		"character_talent_definitions", []
	).duplicate(true)
	ids.append(str(talent_id))
	definitions.append(definition.duplicate(true))
	candidate["character_talents"] = ids
	candidate["character_talent_definitions"] = definitions
	return configure(candidate)


func weapon_profile_id() -> StringName:
	return StringName(str(_weapon_profile.get("id", "")))


func weapon_profile_snapshot() -> Dictionary:
	return _weapon_profile.duplicate(true)


func run_seed() -> int:
	return int(_config.get("seed", 0))


func time_ability_ids() -> Array:
	return _time_ability_ids.duplicate(true)


func has_weapon(id: StringName) -> bool:
	return id != &"" and _weapon_id == id


func has_time_ability(id: StringName) -> bool:
	return id != &"" and _time_ability_ids.has(id)
