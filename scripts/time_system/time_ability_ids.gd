class_name TimeAbilityIds
extends RefCounted

const ABILITY_TO_ACTION: Dictionary = {
	&"stop": &"time_stop",
	&"rewind": &"time_rewind",
	&"rift": &"time_rift",
	&"accelerate": &"time_accelerate",
}

const ACTION_TO_ABILITY: Dictionary = {
	&"time_stop": &"stop",
	&"time_rewind": &"rewind",
	&"time_rift": &"rift",
	&"time_accelerate": &"accelerate",
}


static func canonical_id(skill_id: Variant) -> StringName:
	if typeof(skill_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return &""
	var normalized := StringName(str(skill_id))
	if ABILITY_TO_ACTION.has(normalized):
		return normalized
	return StringName(ACTION_TO_ABILITY.get(normalized, &""))


static func action_id(skill_id: Variant) -> StringName:
	var ability_id := canonical_id(skill_id)
	return StringName(ABILITY_TO_ACTION.get(ability_id, &""))


static func is_canonical_id(ability_id: Variant) -> bool:
	if typeof(ability_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	return ABILITY_TO_ACTION.has(StringName(str(ability_id)))


static func is_action_id(action_id: Variant) -> bool:
	if typeof(action_id) not in [TYPE_STRING, TYPE_STRING_NAME]:
		return false
	return ACTION_TO_ABILITY.has(StringName(str(action_id)))


static func pair_matches(ability_id: Variant, mapped_action_id: Variant) -> bool:
	if not is_canonical_id(ability_id) or not is_action_id(mapped_action_id):
		return false
	return action_id(ability_id) == StringName(str(mapped_action_id))


static func localization_key(ability_id: Variant) -> String:
	if not is_canonical_id(ability_id):
		return ""
	return "TIME_ABILITY_%s_NAME" % str(ability_id).to_upper()
