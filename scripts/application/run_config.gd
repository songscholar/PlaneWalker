class_name RunConfig
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")

const DEFAULTS := {
	"schema_version": 1,
	"milestone": "M1",
	"character_id": "wanderer",
	"weapon_id": "sword",
	"enabled_time_skills": ["time_stop", "time_rewind"],
	"difficulty": "normal",
	"seed": 0,
}


static func validate(value: Dictionary):
	var config := normalized(value)
	if typeof(config["schema_version"]) != TYPE_INT or int(config["schema_version"]) != 1:
		return _invalid("schema_version")
	for field: String in ["milestone", "character_id", "weapon_id", "difficulty"]:
		if typeof(config[field]) != TYPE_STRING or str(config[field]).is_empty():
			return _invalid(field)
	if typeof(config["enabled_time_skills"]) != TYPE_ARRAY:
		return _invalid("enabled_time_skills")
	for skill_id: Variant in config["enabled_time_skills"]:
		if typeof(skill_id) != TYPE_STRING or str(skill_id).is_empty():
			return _invalid("enabled_time_skills")
	if typeof(config["seed"]) != TYPE_INT:
		return _invalid("seed")
	return CommandResultScript.success(0)


static func normalized(value: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate(true)
	for field: String in DEFAULTS.keys():
		if value.has(field):
			var field_value: Variant = value[field]
			if typeof(field_value) == TYPE_ARRAY or typeof(field_value) == TYPE_DICTIONARY:
				result[field] = field_value.duplicate(true)
			else:
				result[field] = field_value
	return result


static func _invalid(field: String):
	return CommandResultScript.failure(&"INVALID_ARGUMENT", 0, {"field": field})
