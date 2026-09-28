class_name SelectionOffer
extends RefCounted

const CommandResultScript := preload("res://scripts/application/command_result.gd")

const REQUIRED_OPTION_FIELDS: Array[String] = [
	"option_id",
	"content_id",
	"name_key",
	"description_key",
	"archetype_key",
	"role_key",
	"rarity",
	"icon_id",
]


static func validate(value: Dictionary):
	var revision := int(value.get("revision", 0))
	if typeof(value.get("schema_version")) != TYPE_INT or int(value.get("schema_version")) != 1:
		return _invalid(revision, "schema_version")
	for field: String in ["offer_id", "category", "title_key"]:
		if typeof(value.get(field)) != TYPE_STRING or str(value.get(field)).is_empty():
			return _invalid(revision, field)
	if typeof(value.get("revision")) != TYPE_INT or revision < 0:
		return _invalid(maxi(0, revision), "revision")
	if typeof(value.get("can_skip")) != TYPE_BOOL:
		return _invalid(revision, "can_skip")
	var options: Variant = value.get("options")
	if typeof(options) != TYPE_ARRAY or options.is_empty():
		return _invalid(revision, "options")

	var option_ids: Dictionary = {}
	for option_value: Variant in options:
		if typeof(option_value) != TYPE_DICTIONARY:
			return _invalid(revision, "options")
		var option: Dictionary = option_value
		for field: String in REQUIRED_OPTION_FIELDS:
			if typeof(option.get(field)) != TYPE_STRING or str(option.get(field)).is_empty():
				return _invalid(revision, "options.%s" % field)
		var option_id := str(option["option_id"])
		if option_ids.has(option_id):
			return _invalid(revision, "options.option_id")
		option_ids[option_id] = true
		if typeof(option.get("effect_summary_keys")) != TYPE_ARRAY:
			return _invalid(revision, "options.effect_summary_keys")
		for key: Variant in option["effect_summary_keys"]:
			if typeof(key) != TYPE_STRING or str(key).is_empty():
				return _invalid(revision, "options.effect_summary_keys")
	return CommandResultScript.success(revision)


static func copy_of(value: Dictionary) -> Dictionary:
	return value.duplicate(true)


static func _invalid(revision: int, field: String):
	return CommandResultScript.failure(&"INVALID_ARGUMENT", revision, {"field": field})
