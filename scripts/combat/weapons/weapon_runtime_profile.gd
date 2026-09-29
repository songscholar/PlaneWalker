class_name WeaponRuntimeProfile
extends RefCounted

const ID_PATTERN := "^[a-z0-9][a-z0-9_.-]{0,95}$"
const LOCALIZATION_KEY_PATTERN := "^[A-Z][A-Z0-9_]{1,127}$"
const PARAMETER_KEY_PATTERN := "^[a-z][a-z0-9_.-]{0,95}$"

const REQUIRED_FIELDS: Array[String] = [
	"id",
	"category",
	"availability",
	"name_key",
	"description_key",
	"tags",
	"compatibility",
	"effects",
	"references",
	"profile_version",
	"weapon_id",
	"actions",
	"resources",
	"capabilities",
	"payloads",
	"cues",
]
const OPTIONAL_FIELDS: Array[String] = [
	"runtime_kind",
	"time_interactions",
	"boss_interactions",
]
const MILESTONES: Array[String] = ["M1", "CURRENT", "NEXT", "LAUNCH", "EXPANSION"]
const RUNTIME_KINDS: Array[String] = ["sword", "bow", "gun", "staff", "gauntlets"]
const SEMANTIC_ACTIONS: Array[String] = [
	"weapon_primary",
	"weapon_secondary",
	"weapon_utility",
	"weapon_skill",
	"weapon_ultimate",
]
const ACTIVATION_MODES: Array[String] = ["press", "release", "hold", "toggle", "channel", "confirm"]
const COMPATIBILITY_FIELDS: Array[String] = [
	"character_ids",
	"weapon_ids",
	"time_ability_ids",
	"archetype_ids",
	"modes",
]
const ACTION_FIELDS: Array[String] = [
	"action_id",
	"semantic_action",
	"activation_mode",
	"windup_frames",
	"active_frames",
	"recovery_frames",
	"cancel_from_frame",
	"buffer_frames",
	"movement_multiplier",
	"resource_costs",
	"payload_id",
	"cue_id",
]
const ACTION_OPTIONAL_FIELDS: Array[String] = ["hold_threshold_frames", "maximum_hold_frames"]
const RESOURCE_FIELDS: Array[String] = ["resource_id", "minimum", "maximum", "initial"]
const RESOURCE_OPTIONAL_FIELDS: Array[String] = ["regen_per_second"]
const PAYLOAD_FIELDS: Array[String] = ["payload_id", "kind", "parameters"]
const CUE_FIELDS: Array[String] = ["cue_id", "animation_id", "vfx_id", "audio_id", "camera_id"]
const TIME_INTERACTION_FIELDS: Array[String] = ["interaction_id", "type", "parameters"]
const BOSS_INTERACTION_FIELDS: Array[String] = ["conversion_id", "type", "parameters"]
const TIME_ABILITY_IDS: Array[String] = ["stop", "rewind", "accelerate", "rift"]
const BOSS_IDS: Array[String] = ["chrono_warden"]
const EXECUTION_KEY_FRAGMENTS: Array[String] = ["script", "method", "callable", "handler"]

var _snapshot: Dictionary = {}
var _actions_by_semantic: Dictionary = {}
var _resources_by_id: Dictionary = {}
var _payloads_by_id: Dictionary = {}
var _cues_by_id: Dictionary = {}
var _time_interactions_by_id: Dictionary = {}
var _boss_interactions_by_id: Dictionary = {}
var _capabilities: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	var validation := _validate_and_normalize(source)
	if not bool(validation.get("ok", false)):
		return validation
	var normalized: Dictionary = validation["profile"]
	_snapshot = normalized.duplicate(true)
	_rebuild_indexes()
	return {
		"ok": true,
		"profile": snapshot(),
		"context": {},
	}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func action_for_semantic(semantic_action: StringName) -> Dictionary:
	var actions := actions_for_semantic(semantic_action)
	return actions[0] if not actions.is_empty() else {}


func actions_for_semantic(semantic_action: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actions_value: Variant = _actions_by_semantic.get(str(semantic_action), [])
	if not actions_value is Array:
		return result
	for action_value: Variant in actions_value as Array:
		if action_value is Dictionary:
			result.append((action_value as Dictionary).duplicate(true))
	return result


func resource(resource_id: StringName) -> Dictionary:
	return _copy_indexed(_resources_by_id, resource_id)


func payload(payload_id: StringName) -> Dictionary:
	return _copy_indexed(_payloads_by_id, payload_id)


func cue(cue_id: StringName) -> Dictionary:
	return _copy_indexed(_cues_by_id, cue_id)


func time_interaction(ability_id: StringName) -> Dictionary:
	return _copy_indexed(_time_interactions_by_id, ability_id)


func boss_interaction(boss_id: StringName) -> Dictionary:
	return _copy_indexed(_boss_interactions_by_id, boss_id)


func has_capability(capability_id: StringName) -> bool:
	return _capabilities.has(str(capability_id))


func _validate_and_normalize(source: Dictionary) -> Dictionary:
	var root_error := _exact_fields_error(source, REQUIRED_FIELDS, OPTIONAL_FIELDS, "profile")
	if not root_error.is_empty():
		return root_error
	if not _matches(ID_PATTERN, source["id"]):
		return _failure("id", "invalid")
	if source["category"] != "weapon_runtime_profile":
		return _failure("category", "unsupported")
	var availability_error := _string_list_error(source["availability"], MILESTONES, true, "availability")
	if not availability_error.is_empty():
		return availability_error
	if not _matches(LOCALIZATION_KEY_PATTERN, source["name_key"]):
		return _failure("name_key", "invalid")
	if not _matches(LOCALIZATION_KEY_PATTERN, source["description_key"]):
		return _failure("description_key", "invalid")
	var tags_error := _string_list_error(source["tags"], [], false, "tags")
	if not tags_error.is_empty():
		return tags_error
	var compatibility_error := _compatibility_error(source["compatibility"])
	if not compatibility_error.is_empty():
		return compatibility_error
	if not source["effects"] is Dictionary or not (source["effects"] as Dictionary).is_empty():
		return _failure("effects", "must_be_empty")
	var references_error := _string_list_error(source["references"], [], false, "references")
	if not references_error.is_empty():
		return references_error
	if not _is_positive_integer(source["profile_version"]):
		return _failure("profile_version", "expected_positive_integer")
	if not _matches(ID_PATTERN, source["weapon_id"]):
		return _failure("weapon_id", "invalid")

	var profile_id := str(source["id"])
	var weapon_id := str(source["weapon_id"])
	if not profile_id.begins_with("%s_" % weapon_id):
		return _failure("weapon_id", "profile_identity_mismatch")
	if not (source["references"] as Array).has(weapon_id):
		return _failure("references", "weapon_reference_missing")
	var compatibility: Dictionary = source["compatibility"]
	if compatibility.has("weapon_ids") and not (compatibility["weapon_ids"] as Array).has(weapon_id):
		return _failure("compatibility.weapon_ids", "weapon_missing")
	if source.has("runtime_kind"):
		if typeof(source["runtime_kind"]) != TYPE_STRING or not RUNTIME_KINDS.has(str(source["runtime_kind"])):
			return _failure("runtime_kind", "unsupported")
		if str(source["runtime_kind"]) != weapon_id:
			return _failure("runtime_kind", "weapon_mismatch")
	if profile_id == "sword_m1_v1":
		var availability: Array = source["availability"]
		if not availability.has("M1") or not availability.has("CURRENT"):
			return _failure("availability", "sword_m1_requires_m1_and_current")

	var resources_result := _validate_resources(source["resources"])
	if not bool(resources_result.get("ok", false)):
		return resources_result
	var payloads_result := _validate_payloads(source["payloads"])
	if not bool(payloads_result.get("ok", false)):
		return payloads_result
	var cues_result := _validate_cues(source["cues"])
	if not bool(cues_result.get("ok", false)):
		return cues_result
	var actions_result := _validate_actions(
		source["actions"],
		resources_result["ids"],
		payloads_result["ids"],
		cues_result["ids"]
	)
	if not bool(actions_result.get("ok", false)):
		return actions_result
	var capabilities_error := _string_list_error(source["capabilities"], [], true, "capabilities")
	if not capabilities_error.is_empty():
		return capabilities_error

	if source.has("time_interactions"):
		var time_error := _interaction_map_error(
			source["time_interactions"],
			TIME_ABILITY_IDS,
			TIME_INTERACTION_FIELDS,
			"time_interactions"
		)
		if not time_error.is_empty():
			return time_error
	if source.has("boss_interactions"):
		var boss_error := _interaction_map_error(
			source["boss_interactions"],
			BOSS_IDS,
			BOSS_INTERACTION_FIELDS,
			"boss_interactions"
		)
		if not boss_error.is_empty():
			return boss_error

	return {
		"ok": true,
		"profile": source.duplicate(true),
		"context": {},
	}


func _validate_resources(value: Variant) -> Dictionary:
	if not value is Array:
		return _failure("resources", "expected_array")
	var ids: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry_value: Variant = (value as Array)[index]
		var field := "resources[%d]" % index
		if not entry_value is Dictionary:
			return _failure(field, "expected_dictionary")
		var entry: Dictionary = entry_value
		var fields_error := _exact_fields_error(entry, RESOURCE_FIELDS, RESOURCE_OPTIONAL_FIELDS, field)
		if not fields_error.is_empty():
			return fields_error
		if not _matches(ID_PATTERN, entry["resource_id"]):
			return _failure("%s.resource_id" % field, "invalid")
		var resource_id := str(entry["resource_id"])
		if ids.has(resource_id):
			return _failure("%s.resource_id" % field, "duplicate")
		for bound: String in ["minimum", "maximum", "initial"]:
			if not _is_finite_number(entry[bound]):
				return _failure("%s.%s" % [field, bound], "expected_finite_number")
		var minimum := float(entry["minimum"])
		var maximum := float(entry["maximum"])
		var initial := float(entry["initial"])
		if minimum > maximum:
			return _failure(field, "inverted_bounds")
		if initial < minimum or initial > maximum:
			return _failure("%s.initial" % field, "outside_bounds")
		if entry.has("regen_per_second"):
			if not _is_finite_number(entry["regen_per_second"]) or float(entry["regen_per_second"]) < 0.0:
				return _failure("%s.regen_per_second" % field, "expected_non_negative_number")
		ids[resource_id] = true
	return {"ok": true, "ids": ids, "context": {}}


func _validate_payloads(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).is_empty():
		return _failure("payloads", "expected_non_empty_array")
	var ids: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry_value: Variant = (value as Array)[index]
		var field := "payloads[%d]" % index
		if not entry_value is Dictionary:
			return _failure(field, "expected_dictionary")
		var entry: Dictionary = entry_value
		var fields_error := _exact_fields_error(entry, PAYLOAD_FIELDS, [], field)
		if not fields_error.is_empty():
			return fields_error
		if not _matches(ID_PATTERN, entry["payload_id"]):
			return _failure("%s.payload_id" % field, "invalid")
		if not _matches(ID_PATTERN, entry["kind"]):
			return _failure("%s.kind" % field, "invalid")
		var payload_id := str(entry["payload_id"])
		if ids.has(payload_id):
			return _failure("%s.payload_id" % field, "duplicate")
		var parameters_error := _parameters_error(entry["parameters"], "%s.parameters" % field)
		if not parameters_error.is_empty():
			return parameters_error
		ids[payload_id] = true
	return {"ok": true, "ids": ids, "context": {}}


func _validate_cues(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).is_empty():
		return _failure("cues", "expected_non_empty_array")
	var ids: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry_value: Variant = (value as Array)[index]
		var field := "cues[%d]" % index
		if not entry_value is Dictionary:
			return _failure(field, "expected_dictionary")
		var entry: Dictionary = entry_value
		var fields_error := _exact_fields_error(entry, CUE_FIELDS, [], field)
		if not fields_error.is_empty():
			return fields_error
		for cue_field: String in CUE_FIELDS:
			if not _matches(ID_PATTERN, entry[cue_field]):
				return _failure("%s.%s" % [field, cue_field], "invalid")
		var cue_id := str(entry["cue_id"])
		if ids.has(cue_id):
			return _failure("%s.cue_id" % field, "duplicate")
		ids[cue_id] = true
	return {"ok": true, "ids": ids, "context": {}}


func _validate_actions(value: Variant, resource_ids: Dictionary, payload_ids: Dictionary, cue_ids: Dictionary) -> Dictionary:
	if not value is Array or (value as Array).is_empty():
		return _failure("actions", "expected_non_empty_array")
	var action_ids: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry_value: Variant = (value as Array)[index]
		var field := "actions[%d]" % index
		if not entry_value is Dictionary:
			return _failure(field, "expected_dictionary")
		var entry: Dictionary = entry_value
		var fields_error := _exact_fields_error(entry, ACTION_FIELDS, ACTION_OPTIONAL_FIELDS, field)
		if not fields_error.is_empty():
			return fields_error
		if not _matches(ID_PATTERN, entry["action_id"]):
			return _failure("%s.action_id" % field, "invalid")
		var action_id := str(entry["action_id"])
		if action_ids.has(action_id):
			return _failure("%s.action_id" % field, "duplicate")
		if typeof(entry["semantic_action"]) != TYPE_STRING or not SEMANTIC_ACTIONS.has(str(entry["semantic_action"])):
			return _failure("%s.semantic_action" % field, "unsupported")
		if typeof(entry["activation_mode"]) != TYPE_STRING or not ACTIVATION_MODES.has(str(entry["activation_mode"])):
			return _failure("%s.activation_mode" % field, "unsupported")
		for frame_field: String in ["windup_frames", "active_frames", "recovery_frames", "buffer_frames"]:
			if not _is_positive_integer(entry[frame_field]):
				return _failure("%s.%s" % [field, frame_field], "expected_positive_integer")
		if entry["cancel_from_frame"] != null:
			if not _is_positive_integer(entry["cancel_from_frame"]):
				return _failure("%s.cancel_from_frame" % field, "expected_positive_integer_or_null")
			if int(entry["cancel_from_frame"]) > int(entry["recovery_frames"]):
				return _failure("%s.cancel_from_frame" % field, "after_recovery")
		for hold_field: String in ACTION_OPTIONAL_FIELDS:
			if entry.has(hold_field) and not _is_non_negative_integer(entry[hold_field]):
				return _failure("%s.%s" % [field, hold_field], "expected_non_negative_integer")
		if entry.has("hold_threshold_frames") and entry.has("maximum_hold_frames") and int(entry["maximum_hold_frames"]) < int(entry["hold_threshold_frames"]):
			return _failure("%s.maximum_hold_frames" % field, "before_hold_threshold")
		if not _is_finite_number(entry["movement_multiplier"]):
			return _failure("%s.movement_multiplier" % field, "expected_finite_number")
		var movement_multiplier := float(entry["movement_multiplier"])
		if movement_multiplier < 0.0 or movement_multiplier > 10.0:
			return _failure("%s.movement_multiplier" % field, "out_of_range")
		if not entry["resource_costs"] is Dictionary:
			return _failure("%s.resource_costs" % field, "expected_dictionary")
		for resource_value: Variant in (entry["resource_costs"] as Dictionary).keys():
			var resource_id := str(resource_value)
			if not _matches(ID_PATTERN, resource_id) or (resource_id != "time_energy" and not resource_ids.has(resource_id)):
				return _failure("%s.resource_costs.%s" % [field, resource_id], "unknown_resource")
			var cost: Variant = (entry["resource_costs"] as Dictionary)[resource_value]
			if not _is_finite_number(cost) or float(cost) < 0.0:
				return _failure("%s.resource_costs.%s" % [field, resource_id], "invalid_cost")
		var payload_id := str(entry["payload_id"])
		if not payload_ids.has(payload_id):
			return _failure("%s.payload_id" % field, "unknown_payload")
		var cue_id := str(entry["cue_id"])
		if not cue_ids.has(cue_id):
			return _failure("%s.cue_id" % field, "unknown_cue")
		action_ids[action_id] = true
	return {"ok": true, "context": {}}


func _interaction_map_error(value: Variant, allowed_ids: Array[String], fields: Array[String], field: String) -> Dictionary:
	if not value is Dictionary:
		return _failure(field, "expected_dictionary")
	for id_value: Variant in (value as Dictionary).keys():
		var interaction_id := str(id_value)
		if not allowed_ids.has(interaction_id):
			return _failure("%s.%s" % [field, interaction_id], "unsupported")
		var descriptor_value: Variant = (value as Dictionary)[id_value]
		if not descriptor_value is Dictionary:
			return _failure("%s.%s" % [field, interaction_id], "expected_dictionary")
		var descriptor: Dictionary = descriptor_value
		var descriptor_field := "%s.%s" % [field, interaction_id]
		var fields_error := _exact_fields_error(descriptor, fields, [], descriptor_field)
		if not fields_error.is_empty():
			return fields_error
		var identity_field := "interaction_id" if fields.has("interaction_id") else "conversion_id"
		if not _matches(ID_PATTERN, descriptor[identity_field]):
			return _failure("%s.%s" % [descriptor_field, identity_field], "invalid")
		if not _matches(ID_PATTERN, descriptor["type"]):
			return _failure("%s.type" % descriptor_field, "invalid")
		var parameters_error := _parameters_error(descriptor["parameters"], "%s.parameters" % descriptor_field)
		if not parameters_error.is_empty():
			return parameters_error
	return {}


func _parameters_error(value: Variant, field: String) -> Dictionary:
	if not value is Dictionary:
		return _failure(field, "expected_dictionary")
	for key_value: Variant in (value as Dictionary).keys():
		var key := str(key_value)
		if not _matches(PARAMETER_KEY_PATTERN, key) or _is_execution_key(key):
			return _failure("%s.%s" % [field, key], "executable_key_forbidden")
		var parameter_error := _parameter_value_error((value as Dictionary)[key_value], "%s.%s" % [field, key])
		if not parameter_error.is_empty():
			return parameter_error
	return {}


func _parameter_value_error(value: Variant, field: String) -> Dictionary:
	match typeof(value):
		TYPE_BOOL:
			return {}
		TYPE_INT, TYPE_FLOAT:
			return {} if is_finite(float(value)) else _failure(field, "non_finite")
		TYPE_STRING:
			var text := str(value)
			if text.is_empty() or text.contains("://") or text.to_lower().ends_with(".gd"):
				return _failure(field, "executable_value_forbidden")
			return {}
		TYPE_ARRAY:
			for index: int in range((value as Array).size()):
				var child_error := _parameter_value_error((value as Array)[index], "%s[%d]" % [field, index])
				if not child_error.is_empty():
					return child_error
			return {}
		TYPE_DICTIONARY:
			return _parameters_error(value, field)
		_:
			return _failure(field, "unsupported_type")


func _compatibility_error(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("compatibility", "expected_dictionary")
	for key_value: Variant in (value as Dictionary).keys():
		var key := str(key_value)
		if not COMPATIBILITY_FIELDS.has(key):
			return _failure("compatibility.%s" % key, "unknown")
		var list_error := _string_list_error((value as Dictionary)[key_value], [], false, "compatibility.%s" % key)
		if not list_error.is_empty():
			return list_error
	return {}


func _string_list_error(value: Variant, allowed: Array[String], require_non_empty: bool, field: String) -> Dictionary:
	if not value is Array:
		return _failure(field, "expected_array")
	if require_non_empty and (value as Array).is_empty():
		return _failure(field, "expected_non_empty_array")
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry: Variant = (value as Array)[index]
		if typeof(entry) != TYPE_STRING:
			return _failure("%s[%d]" % [field, index], "invalid")
		var text := str(entry)
		if allowed.is_empty():
			if not _matches(ID_PATTERN, text):
				return _failure("%s[%d]" % [field, index], "invalid")
		elif not allowed.has(text):
			return _failure("%s[%d]" % [field, index], "unsupported")
		if seen.has(text):
			return _failure("%s[%d]" % [field, index], "duplicate")
		seen[text] = true
	return {}


func _exact_fields_error(source: Dictionary, required: Array[String], optional: Array[String], field: String) -> Dictionary:
	for required_field: String in required:
		if not source.has(required_field):
			return _failure("%s.%s" % [field, required_field], "missing")
	for key_value: Variant in source.keys():
		var key := str(key_value)
		if not required.has(key) and not optional.has(key):
			return _failure("%s.%s" % [field, key], "unknown")
	return {}


func _rebuild_indexes() -> void:
	_actions_by_semantic.clear()
	_resources_by_id.clear()
	_payloads_by_id.clear()
	_cues_by_id.clear()
	_time_interactions_by_id.clear()
	_boss_interactions_by_id.clear()
	_capabilities.clear()
	for action_value: Variant in _snapshot.get("actions", []):
		var action: Dictionary = action_value
		var semantic_id := str(action["semantic_action"])
		if not _actions_by_semantic.has(semantic_id):
			_actions_by_semantic[semantic_id] = []
		(_actions_by_semantic[semantic_id] as Array).append(action.duplicate(true))
	for resource_value: Variant in _snapshot.get("resources", []):
		var resource_definition: Dictionary = resource_value
		_resources_by_id[str(resource_definition["resource_id"])] = resource_definition.duplicate(true)
	for payload_value: Variant in _snapshot.get("payloads", []):
		var payload_definition: Dictionary = payload_value
		_payloads_by_id[str(payload_definition["payload_id"])] = payload_definition.duplicate(true)
	for cue_value: Variant in _snapshot.get("cues", []):
		var cue_definition: Dictionary = cue_value
		_cues_by_id[str(cue_definition["cue_id"])] = cue_definition.duplicate(true)
	for capability_value: Variant in _snapshot.get("capabilities", []):
		_capabilities[str(capability_value)] = true
	for ability_value: Variant in _snapshot.get("time_interactions", {}).keys():
		var ability_id := str(ability_value)
		_time_interactions_by_id[ability_id] = (_snapshot["time_interactions"][ability_value] as Dictionary).duplicate(true)
	for boss_value: Variant in _snapshot.get("boss_interactions", {}).keys():
		var boss_id := str(boss_value)
		_boss_interactions_by_id[boss_id] = (_snapshot["boss_interactions"][boss_value] as Dictionary).duplicate(true)


func _copy_indexed(index: Dictionary, id: StringName) -> Dictionary:
	var value: Variant = index.get(str(id), {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _is_execution_key(value: String) -> bool:
	var normalized := value.to_lower()
	for fragment: String in EXECUTION_KEY_FRAGMENTS:
		if normalized.contains(fragment):
			return true
	return false


func _is_positive_integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and int(value) >= 1


func _is_non_negative_integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and int(value) >= 0


func _is_finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _matches(pattern: String, value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(str(value)) != null


func _failure(field: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"profile": {},
		"context": {"field": field, "reason": reason},
	}
