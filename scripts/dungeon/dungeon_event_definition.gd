class_name DungeonEventDefinition
extends RefCounted

const ROOT_FIELDS: Array[String] = [
	"category", "id", "schema_version", "name_key", "description_key", "prompt_key",
	"availability", "special", "floor_min", "floor_max", "weight", "repeat_policy",
	"trigger_predicate_id", "outcome_channel", "options",
]
const OPTION_FIELDS: Array[String] = [
	"id", "label_key", "outcome_visibility", "requirements", "outcomes",
]
const OUTCOME_FIELDS: Array[String] = ["id", "weight", "outcome_key", "consequences"]
const OPERATION_FIELDS: Array[String] = ["operation", "arguments"]
const AVAILABILITY: Array[String] = ["LAUNCH", "EXPANSION"]
const EVENT_IDS: Array[String] = [
	"event_chronal_altar", "event_trapped_traveler", "event_cursed_pool",
	"event_smiths_legacy", "event_memory_mirror", "event_planar_merchant",
	"event_void_rift", "event_sleeping_guardian", "event_twisted_well",
	"event_soul_contract", "event_time_paradox", "event_sacrificial_altar",
	"event_lost_journal", "event_rift_garden", "event_final_choice",
	"event_void_whispers", "event_perfect_rewind", "event_old_reunion",
]
const SPECIAL_EVENT_IDS: Array[String] = [
	"event_void_whispers", "event_perfect_rewind", "event_old_reunion",
]
const REPEAT_POLICIES: Array[String] = ["once_per_run", "once_per_floor", "repeatable"]
const TRIGGER_PREDICATES: Array[String] = [
	"always", "low_health", "has_curse", "no_curse", "rich", "poor",
	"perfect_rewind_available", "old_reunion_eligible",
]
const OUTCOME_VISIBILITY: Array[String] = ["preview_exact", "preview_category", "hidden_until_commit"]
const REQUIREMENT_OPERATIONS: Array[String] = [
	"resource_min", "health_min", "health_max_ratio", "gold_min", "has_reward_tag",
	"lacks_curse", "narrative_flag", "floor_index_min",
]
const CONSEQUENCE_OPERATIONS: Array[String] = [
	"resource_delta", "health_delta", "reward_draft", "curse_add", "curse_remove",
	"temporary_modifier", "map_reveal", "encounter_start", "route_skip", "narrative_flag",
]
const RESOURCE_IDS: Array[String] = ["gold", "time_shard", "forge_essence"]
const REWARD_POOL_IDS: Array[String] = ["item", "blessing", "rare_item", "rare_blessing"]
const MODIFIER_IDS: Array[String] = [
	"chronal_grace", "weapon_temper", "past_strength", "paradox_echo", "tranquility",
	"void_bargain_power", "void_bargain_guard", "heroic_guard", "heroic_assault",
]
const CURSE_IDS: Array[String] = [
	"curse_stasis_fracture", "curse_thaw_debt", "curse_blood_memory",
	"curse_erased_present", "curse_starved_horizon", "curse_folded_hunger",
	"curse_glass_cadence", "curse_burnout_clock", "curse_brittle_pact",
	"curse_empty_veins", "curse_narrow_counter", "curse_shattered_aegis",
	"curse_recoil_tax", "curse_empty_magazine", "curse_divided_self",
	"curse_phantom_attention", "curse_fickle_time", "curse_brittle_fortune",
]
const ENCOUNTER_ADAPTER_IDS: Array[String] = [
	"encounter_profile_ruins_adapter_v1", "encounter_profile_forest_adapter_v1",
	"encounter_profile_rift_adapter_v1", "encounter_profile_forge_adapter_v1",
	"encounter_profile_throne_adapter_v1", "boss_encounter_ruin_king_adapter_v1",
	"boss_encounter_forest_heart_adapter_v1", "boss_encounter_time_sovereign_adapter_v1",
	"boss_encounter_forge_colossus_adapter_v1", "boss_encounter_void_throne_adapter_v1",
]
const EXECUTABLE_KEY_PARTS: Array[String] = [
	"script", "callable", "method", "command", "code", "expression", "scene_path", "resource_path",
]

var _snapshot: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	_snapshot.clear()
	var normalized_result := _normalize(source)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result
	_snapshot = (normalized_result["definition"] as Dictionary).duplicate(true)
	return {"ok": true, "definition": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _normalize(source: Dictionary) -> Dictionary:
	var fields_error := _exact_fields_error(source, ROOT_FIELDS, "event")
	if not fields_error.is_empty():
		return fields_error
	if typeof(source["category"]) != TYPE_STRING or str(source["category"]) != "dungeon_event":
		return _failure("category", "unsupported")
	if not _is_integer_in_range(source["schema_version"], 1, 1):
		return _failure("schema_version", "unsupported")
	if typeof(source["id"]) != TYPE_STRING or not EVENT_IDS.has(str(source["id"])):
		return _failure("id", "unsupported")
	var event_id := str(source["id"])
	for field: String in ["name_key", "description_key", "prompt_key"]:
		if not _valid_localization_key(source[field]):
			return _failure(field, "invalid")
	var availability_result := _normalize_string_list(
		source["availability"], AVAILABILITY, false, "availability"
	)
	if not bool(availability_result.get("ok", false)):
		return availability_result
	if (availability_result["values"] as Array) != AVAILABILITY:
		return _failure("availability", "exact_launch_expansion_required")
	if typeof(source["special"]) != TYPE_BOOL:
		return _failure("special", "expected_boolean")
	if bool(source["special"]) != SPECIAL_EVENT_IDS.has(event_id):
		return _failure("special", "event_identity_mismatch")
	for field: String in ["floor_min", "floor_max"]:
		if not _is_integer_in_range(source[field], 1, 5):
			return _failure(field, "out_of_range")
	if int(source["floor_min"]) > int(source["floor_max"]):
		return _failure("floor_min", "greater_than_max")
	if not _is_integer_in_range(source["weight"], 1, 100):
		return _failure("weight", "out_of_range")
	if typeof(source["repeat_policy"]) != TYPE_STRING or not REPEAT_POLICIES.has(str(source["repeat_policy"])):
		return _failure("repeat_policy", "unsupported")
	if typeof(source["trigger_predicate_id"]) != TYPE_STRING or not TRIGGER_PREDICATES.has(str(source["trigger_predicate_id"])):
		return _failure("trigger_predicate_id", "unsupported")
	if typeof(source["outcome_channel"]) != TYPE_STRING or str(source["outcome_channel"]) != "event_outcome_v1":
		return _failure("outcome_channel", "unsupported")
	var options_result := _normalize_options(source["options"])
	if not bool(options_result.get("ok", false)):
		return options_result

	return {
		"ok": true,
		"definition": {
			"category": "dungeon_event",
			"id": event_id,
			"schema_version": 1,
			"name_key": str(source["name_key"]),
			"description_key": str(source["description_key"]),
			"prompt_key": str(source["prompt_key"]),
			"availability": (availability_result["values"] as Array).duplicate(),
			"special": bool(source["special"]),
			"floor_min": int(source["floor_min"]),
			"floor_max": int(source["floor_max"]),
			"weight": int(source["weight"]),
			"repeat_policy": str(source["repeat_policy"]),
			"trigger_predicate_id": str(source["trigger_predicate_id"]),
			"outcome_channel": str(source["outcome_channel"]),
			"options": (options_result["values"] as Array).duplicate(true),
		},
	}


func _normalize_options(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).size() < 2 or (value as Array).size() > 3:
		return _failure("options", "expected_two_or_three")
	var values: Array[Dictionary] = []
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var option_value: Variant = (value as Array)[index]
		if not option_value is Dictionary:
			return _failure("options[%d]" % index, "expected_dictionary")
		var option: Dictionary = option_value
		var fields_error := _exact_fields_error(option, OPTION_FIELDS, "options[%d]" % index)
		if not fields_error.is_empty():
			return fields_error
		if not _valid_id(option["id"]):
			return _failure("options[%d].id" % index, "invalid")
		var option_id := str(option["id"])
		if seen.has(option_id):
			return _failure("options[%d].id" % index, "duplicate")
		seen[option_id] = true
		if not _valid_localization_key(option["label_key"]):
			return _failure("options[%d].label_key" % index, "invalid")
		if typeof(option["outcome_visibility"]) != TYPE_STRING or not OUTCOME_VISIBILITY.has(str(option["outcome_visibility"])):
			return _failure("options[%d].outcome_visibility" % index, "unsupported")
		var requirements_result := _normalize_operations(
			option["requirements"], REQUIREMENT_OPERATIONS, false, "options[%d].requirements" % index
		)
		if not bool(requirements_result.get("ok", false)):
			return requirements_result
		var outcomes_result := _normalize_outcomes(
			option["outcomes"], str(option["outcome_visibility"]), "options[%d].outcomes" % index
		)
		if not bool(outcomes_result.get("ok", false)):
			return outcomes_result
		values.append({
			"id": option_id,
			"label_key": str(option["label_key"]),
			"outcome_visibility": str(option["outcome_visibility"]),
			"requirements": (requirements_result["values"] as Array).duplicate(true),
			"outcomes": (outcomes_result["values"] as Array).duplicate(true),
		})
	return {"ok": true, "values": values, "context": {}}


func _normalize_outcomes(value: Variant, visibility: String, path: String) -> Dictionary:
	if not value is Array or (value as Array).is_empty() or (value as Array).size() > 4:
		return _failure(path, "expected_one_to_four")
	if visibility == "hidden_until_commit" and (value as Array).size() < 2:
		return _failure(path, "hidden_requires_multiple_outcomes")
	var values: Array[Dictionary] = []
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var outcome_value: Variant = (value as Array)[index]
		if not outcome_value is Dictionary:
			return _failure("%s[%d]" % [path, index], "expected_dictionary")
		var outcome: Dictionary = outcome_value
		var fields_error := _exact_fields_error(outcome, OUTCOME_FIELDS, "%s[%d]" % [path, index])
		if not fields_error.is_empty():
			return fields_error
		if not _valid_id(outcome["id"]):
			return _failure("%s[%d].id" % [path, index], "invalid")
		var outcome_id := str(outcome["id"])
		if seen.has(outcome_id):
			return _failure("%s[%d].id" % [path, index], "duplicate")
		seen[outcome_id] = true
		if not _is_integer_in_range(outcome["weight"], 1, 100):
			return _failure("%s[%d].weight" % [path, index], "out_of_range")
		if not _valid_localization_key(outcome["outcome_key"]):
			return _failure("%s[%d].outcome_key" % [path, index], "invalid")
		var consequences_result := _normalize_operations(
			outcome["consequences"],
			CONSEQUENCE_OPERATIONS,
			false,
			"%s[%d].consequences" % [path, index]
		)
		if not bool(consequences_result.get("ok", false)):
			return consequences_result
		values.append({
			"id": outcome_id,
			"weight": int(outcome["weight"]),
			"outcome_key": str(outcome["outcome_key"]),
			"consequences": (consequences_result["values"] as Array).duplicate(true),
		})
	return {"ok": true, "values": values, "context": {}}


func _normalize_operations(value: Variant, allowed: Array[String], allow_empty: bool, path: String) -> Dictionary:
	if not value is Array or (not allow_empty and (value as Array).is_empty()):
		return _failure(path, "expected_array")
	var values: Array[Dictionary] = []
	for index: int in range((value as Array).size()):
		var operation_value: Variant = (value as Array)[index]
		if not operation_value is Dictionary:
			return _failure("%s[%d]" % [path, index], "expected_dictionary")
		var operation: Dictionary = operation_value
		var fields_error := _exact_fields_error(operation, OPERATION_FIELDS, "%s[%d]" % [path, index])
		if not fields_error.is_empty():
			return fields_error
		if typeof(operation["operation"]) != TYPE_STRING or not allowed.has(str(operation["operation"])):
			return _failure("%s[%d].operation" % [path, index], "unsupported")
		var arguments_result := _normalize_arguments(operation["arguments"], "%s[%d].arguments" % [path, index])
		if not bool(arguments_result.get("ok", false)):
			return arguments_result
		var operation_arguments_error := _operation_arguments_error(
			str(operation["operation"]),
			arguments_result["value"] as Dictionary,
			"%s[%d].arguments" % [path, index]
		)
		if not operation_arguments_error.is_empty():
			return operation_arguments_error
		var canonical_arguments := _canonical_operation_arguments(
			str(operation["operation"]),
			arguments_result["value"] as Dictionary
		)
		values.append({
			"operation": str(operation["operation"]),
			"arguments": canonical_arguments,
		})
	return {"ok": true, "values": values, "context": {}}


func _canonical_operation_arguments(
	operation: String,
	arguments: Dictionary
) -> Dictionary:
	var canonical := arguments.duplicate(true)
	match operation:
		"resource_min", "gold_min", "resource_delta":
			canonical["amount"] = int(canonical["amount"])
		"floor_index_min":
			canonical["value"] = int(canonical["value"])
		"reward_draft":
			canonical["count"] = int(canonical["count"])
		"temporary_modifier":
			canonical["duration_rooms"] = int(canonical["duration_rooms"])
			canonical["magnitude"] = float(canonical["magnitude"])
		"map_reveal":
			canonical["depth"] = int(canonical["depth"])
		"route_skip":
			canonical["rooms"] = int(canonical["rooms"])
	return canonical


func _normalize_arguments(value: Variant, path: String) -> Dictionary:
	if not value is Dictionary:
		return _failure(path, "expected_dictionary")
	if (value as Dictionary).is_empty():
		return _failure(path, "expected_non_empty_dictionary")
	var normalized: Dictionary = {}
	for key_value: Variant in (value as Dictionary).keys():
		if typeof(key_value) != TYPE_STRING:
			return _failure(path, "non_string_key")
		var key := str(key_value)
		if not _valid_id(key) or _is_executable_key(key):
			return _failure("%s.%s" % [path, key], "executable_or_invalid_key")
		var argument: Variant = (value as Dictionary)[key_value]
		if typeof(argument) not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			return _failure("%s.%s" % [path, key], "non_scalar")
		if typeof(argument) in [TYPE_INT, TYPE_FLOAT] and not is_finite(float(argument)):
			return _failure("%s.%s" % [path, key], "non_finite")
		if typeof(argument) == TYPE_STRING:
			if (
				str(argument).is_empty()
				or str(argument).length() > 96
				or not _matches("^[A-Za-z0-9_.:-]+$", argument)
				or _is_executable_string(str(argument))
			):
				return _failure("%s.%s" % [path, key], "executable_or_oversized_string")
		normalized[key] = argument
	return {"ok": true, "value": normalized, "context": {}}


func _operation_arguments_error(operation: String, arguments: Dictionary, path: String) -> Dictionary:
	var expected_fields: Array[String] = []
	match operation:
		"resource_min", "resource_delta": expected_fields = ["resource", "amount"]
		"health_min", "gold_min": expected_fields = ["amount"]
		"health_max_ratio": expected_fields = ["ratio"]
		"has_reward_tag": expected_fields = ["tag"]
		"lacks_curse", "curse_add", "curse_remove": expected_fields = ["curse_id"]
		"narrative_flag": expected_fields = ["flag", "value"]
		"floor_index_min": expected_fields = ["value"]
		"health_delta": expected_fields = ["amount", "nonlethal"]
		"reward_draft": expected_fields = ["pool_id", "count"]
		"temporary_modifier": expected_fields = ["modifier_id", "duration_rooms", "magnitude"]
		"map_reveal": expected_fields = ["depth"]
		"encounter_start": expected_fields = ["encounter_id"]
		"route_skip": expected_fields = ["rooms"]
		_: return _failure(path, "unsupported_operation")
	var fields_error := _exact_argument_fields_error(arguments, expected_fields, path)
	if not fields_error.is_empty():
		return fields_error
	match operation:
		"resource_min":
			if not _string_in(arguments["resource"], RESOURCE_IDS): return _failure("%s.resource" % path, "unsupported_reference")
			if not _is_integer_in_range(arguments["amount"], 1, 9999): return _failure("%s.amount" % path, "out_of_range")
		"health_min":
			if not _number_in_range(arguments["amount"], 0.0, 9999.0, false, true): return _failure("%s.amount" % path, "out_of_range")
		"health_max_ratio":
			if not _number_in_range(arguments["ratio"], 0.0, 1.0, false, false): return _failure("%s.ratio" % path, "out_of_range")
		"gold_min":
			if not _is_integer_in_range(arguments["amount"], 1, 999999): return _failure("%s.amount" % path, "out_of_range")
		"has_reward_tag":
			if not _valid_id(arguments["tag"]): return _failure("%s.tag" % path, "invalid")
		"lacks_curse", "curse_add", "curse_remove":
			if not _string_in(arguments["curse_id"], CURSE_IDS): return _failure("%s.curse_id" % path, "unsupported_reference")
		"narrative_flag":
			if not _valid_id(arguments["flag"]): return _failure("%s.flag" % path, "invalid")
			if typeof(arguments["value"]) != TYPE_BOOL: return _failure("%s.value" % path, "expected_boolean")
		"floor_index_min":
			if not _is_integer_in_range(arguments["value"], 1, 5): return _failure("%s.value" % path, "out_of_range")
		"resource_delta":
			if not _string_in(arguments["resource"], RESOURCE_IDS): return _failure("%s.resource" % path, "unsupported_reference")
			if not _is_integer_in_range(arguments["amount"], -9999, 9999) or int(arguments["amount"]) == 0: return _failure("%s.amount" % path, "out_of_range")
		"health_delta":
			if not _number_in_range(arguments["amount"], -9999.0, 9999.0, true, true) or is_zero_approx(float(arguments["amount"])): return _failure("%s.amount" % path, "out_of_range")
			if typeof(arguments["nonlethal"]) != TYPE_BOOL: return _failure("%s.nonlethal" % path, "expected_boolean")
		"reward_draft":
			if not _string_in(arguments["pool_id"], REWARD_POOL_IDS): return _failure("%s.pool_id" % path, "unsupported_reference")
			if not _is_integer_in_range(arguments["count"], 1, 3): return _failure("%s.count" % path, "out_of_range")
		"temporary_modifier":
			if not _string_in(arguments["modifier_id"], MODIFIER_IDS): return _failure("%s.modifier_id" % path, "unsupported_reference")
			if not _is_integer_in_range(arguments["duration_rooms"], 1, 5): return _failure("%s.duration_rooms" % path, "out_of_range")
			if not _number_in_range(arguments["magnitude"], 0.0, 10.0, false, true): return _failure("%s.magnitude" % path, "out_of_range")
		"map_reveal":
			if not _is_integer_in_range(arguments["depth"], 1, 5): return _failure("%s.depth" % path, "out_of_range")
		"encounter_start":
			if not _string_in(arguments["encounter_id"], ENCOUNTER_ADAPTER_IDS): return _failure("%s.encounter_id" % path, "unsupported_adapter")
		"route_skip":
			if not _is_integer_in_range(arguments["rooms"], 1, 2): return _failure("%s.rooms" % path, "out_of_range")
	return {}


func _exact_argument_fields_error(arguments: Dictionary, fields: Array[String], path: String) -> Dictionary:
	for field: String in fields:
		if not arguments.has(field):
			return _failure("%s.%s" % [path, field], "missing")
	for key: Variant in arguments.keys():
		if typeof(key) != TYPE_STRING or not fields.has(str(key)):
			return _failure("%s.%s" % [path, str(key)], "unknown")
	return {}


func _string_in(value: Variant, allowed: Array[String]) -> bool:
	return typeof(value) == TYPE_STRING and allowed.has(str(value))


func _number_in_range(value: Variant, minimum: float, maximum: float, include_minimum: bool, include_maximum: bool) -> bool:
	if not _is_finite_number(value):
		return false
	var numeric := float(value)
	return (numeric >= minimum if include_minimum else numeric > minimum) and (numeric <= maximum if include_maximum else numeric < maximum)


func _is_executable_key(value: String) -> bool:
	var lowered := value.to_lower()
	for part: String in EXECUTABLE_KEY_PARTS:
		if lowered.contains(part):
			return true
	return false


func _is_executable_string(value: String) -> bool:
	var lowered := value.strip_edges().to_lower()
	return (
		lowered.begins_with("res://")
		or lowered.begins_with("user://")
		or lowered.contains("://")
		or lowered.ends_with(".gd")
		or lowered.ends_with(".tscn")
		or lowered.contains("func(")
		or lowered.contains("call(")
		or lowered.contains("eval(")
	)


func _normalize_string_list(value: Variant, allowed: Array[String], allow_empty: bool, field: String) -> Dictionary:
	if not value is Array or (not allow_empty and (value as Array).is_empty()):
		return _failure(field, "expected_array")
	var normalized: Array[String] = []
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry: Variant = (value as Array)[index]
		if typeof(entry) != TYPE_STRING or not allowed.has(str(entry)):
			return _failure("%s[%d]" % [field, index], "unsupported")
		if seen.has(str(entry)):
			return _failure("%s[%d]" % [field, index], "duplicate")
		seen[str(entry)] = true
		normalized.append(str(entry))
	return {"ok": true, "values": normalized, "context": {}}


func _exact_fields_error(value: Dictionary, fields: Array[String], path: String) -> Dictionary:
	for field: String in fields:
		if not value.has(field):
			return _failure("%s.%s" % [path, field], "missing")
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING or not fields.has(str(key)):
			return _failure("%s.%s" % [path, str(key)], "unknown")
	return {}


func _valid_id(value: Variant) -> bool:
	return _matches("^[a-z][a-z0-9_]{0,95}$", value)


func _valid_localization_key(value: Variant) -> bool:
	return _matches("^[A-Z][A-Z0-9_]{1,127}$", value)


func _matches(pattern: String, value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(str(value)) != null


func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == floorf(numeric) and numeric >= minimum and numeric <= maximum


func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _failure(field: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"code": &"DUNGEON_EVENT_INVALID",
		"definition": {},
		"context": {"field": field, "reason": reason},
	}
