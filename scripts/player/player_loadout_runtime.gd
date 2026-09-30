class_name PlayerLoadoutRuntime
extends Node

var _config: Dictionary = {
	"weapon_id": "sword",
	"enabled_time_skills": ["stop", "rewind"],
}
var _weapon_id: StringName = &"sword"
var _time_ability_ids: Array[StringName] = [&"stop", &"rewind"]
var _weapon_profile: Dictionary = {}


func configure(config: Dictionary) -> bool:
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
	_weapon_id = next_weapon_id
	_time_ability_ids = next_time_ability_ids.duplicate()
	_weapon_profile = next_weapon_profile.duplicate(true)
	return true


func snapshot() -> Dictionary:
	return _config.duplicate(true)


func weapon_id() -> StringName:
	return _weapon_id


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
