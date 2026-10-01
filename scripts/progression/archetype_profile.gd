class_name ArchetypeProfile
extends RefCounted

const ID_PATTERN := "^[a-z0-9][a-z0-9_.-]{0,63}$"
const LOCALIZATION_KEY_PATTERN := "^[A-Z][A-Z0-9_]{1,127}$"

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
	"archetype_id",
	"mechanic_tags",
	"starter_min",
	"payoff_min",
	"risk_min",
	"boss_conversion_id",
	"boss_response_key",
]
const COMPATIBILITY_FIELDS: Array[String] = [
	"character_ids",
	"weapon_ids",
	"time_ability_ids",
	"archetype_ids",
	"modes",
]
const ARCHETYPE_IDS: Array[String] = [
	"freeze_burst",
	"rewind_echo",
	"rift_trap",
	"accelerated_combo",
	"low_hp_void",
	"perfect_guard",
	"piercing_barrage",
	"echo_legion",
]
const BOSS_CONVERSIONS := {
	"freeze_burst": "boss_weakpoint_exposure",
	"rewind_echo": "boss_rewind_path_strike",
	"rift_trap": "boss_projectile_window",
	"accelerated_combo": "boss_combo_break",
	"low_hp_void": "boss_execute_warning",
	"perfect_guard": "boss_counter_window",
	"piercing_barrage": "boss_weakpoint_ammo_refund",
	"echo_legion": "boss_facing_lure",
}
const AVAILABILITY: Array[String] = ["LAUNCH", "EXPANSION"]

var profile_id: StringName = &""
var profile_version: int = 0
var archetype_id: StringName = &""
var availability: PackedStringArray = PackedStringArray()
var mechanic_tags: PackedStringArray = PackedStringArray()
var starter_min: int = 0
var payoff_min: int = 0
var risk_min: int = 0
var boss_conversion_id: StringName = &""
var boss_response_key: StringName = &""

var _snapshot: Dictionary = {}


static func from_definition(definition: Dictionary):
	var profile = new()
	var result := profile.configure(definition)
	return profile if bool(result.get("ok", false)) else null


func configure(source: Dictionary) -> Dictionary:
	var validation := _validate_and_normalize(source)
	if not bool(validation.get("ok", false)):
		return validation
	_snapshot = (validation["profile"] as Dictionary).duplicate(true)
	_project_fields()
	return {
		"ok": true,
		"profile": snapshot(),
		"context": {},
	}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _project_fields() -> void:
	profile_id = StringName(str(_snapshot["id"]))
	profile_version = int(_snapshot["profile_version"])
	archetype_id = StringName(str(_snapshot["archetype_id"]))
	availability = PackedStringArray(_snapshot["availability"])
	mechanic_tags = PackedStringArray(_snapshot["mechanic_tags"])
	starter_min = int(_snapshot["starter_min"])
	payoff_min = int(_snapshot["payoff_min"])
	risk_min = int(_snapshot["risk_min"])
	boss_conversion_id = StringName(str(_snapshot["boss_conversion_id"]))
	boss_response_key = StringName(str(_snapshot["boss_response_key"]))


func _validate_and_normalize(source: Dictionary) -> Dictionary:
	var root_error := _exact_fields_error(source, REQUIRED_FIELDS, "profile")
	if not root_error.is_empty():
		return root_error
	if not _matches(ID_PATTERN, source["id"]):
		return _failure("id", "invalid")
	if typeof(source["category"]) != TYPE_STRING or str(source["category"]) != "archetype_profile":
		return _failure("category", "unsupported")
	if not _array_equals_strings(source["availability"], AVAILABILITY):
		return _failure("availability", "unsupported")
	if not _matches(LOCALIZATION_KEY_PATTERN, source["name_key"]):
		return _failure("name_key", "invalid")
	if not _matches(LOCALIZATION_KEY_PATTERN, source["description_key"]):
		return _failure("description_key", "invalid")
	var tags_error := _string_list_error(source["tags"], false, "tags")
	if not tags_error.is_empty():
		return tags_error
	var compatibility_error := _compatibility_error(source["compatibility"])
	if not compatibility_error.is_empty():
		return compatibility_error
	if not source["effects"] is Dictionary or not (source["effects"] as Dictionary).is_empty():
		return _failure("effects", "must_be_empty")
	var references_error := _string_list_error(source["references"], true, "references")
	if not references_error.is_empty():
		return references_error
	if not _is_exact_integer(source["profile_version"], 1):
		return _failure("profile_version", "unsupported_version")
	if typeof(source["archetype_id"]) != TYPE_STRING or not ARCHETYPE_IDS.has(str(source["archetype_id"])):
		return _failure("archetype_id", "unsupported")

	var archetype := str(source["archetype_id"])
	var mechanic_tags_error := _string_list_error(source["mechanic_tags"], false, "mechanic_tags")
	if not mechanic_tags_error.is_empty():
		return mechanic_tags_error
	var authored_mechanic_tags: Array = source["mechanic_tags"]
	if authored_mechanic_tags.size() < 4:
		return _failure("mechanic_tags", "insufficient_coverage")
	if not _is_exact_integer(source["starter_min"], 3):
		return _failure("starter_min", "expected_three")
	if not _is_exact_integer(source["payoff_min"], 2):
		return _failure("payoff_min", "expected_two")
	if not _is_exact_integer(source["risk_min"], 1):
		return _failure("risk_min", "expected_one")
	if typeof(source["boss_conversion_id"]) != TYPE_STRING or (
		str(source["boss_conversion_id"]) != str(BOSS_CONVERSIONS[archetype])
	):
		return _failure("boss_conversion_id", "archetype_mismatch")
	var expected_boss_response_key := "ARCHETYPE_%s_BOSS_RESPONSE" % archetype.to_upper()
	if typeof(source["boss_response_key"]) != TYPE_STRING or (
		str(source["boss_response_key"]) != expected_boss_response_key
	):
		return _failure("boss_response_key", "archetype_mismatch")

	var normalized := {
		"id": str(source["id"]),
		"profile_version": 1,
		"archetype_id": archetype,
		"availability": AVAILABILITY.duplicate(),
		"mechanic_tags": authored_mechanic_tags.duplicate(true),
		"starter_min": 3,
		"payoff_min": 2,
		"risk_min": 1,
		"boss_conversion_id": str(source["boss_conversion_id"]),
		"boss_response_key": str(source["boss_response_key"]),
	}
	return {"ok": true, "profile": normalized, "context": {}}


func _compatibility_error(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("compatibility", "expected_dictionary")
	for key_value: Variant in (value as Dictionary).keys():
		var key := str(key_value)
		if not COMPATIBILITY_FIELDS.has(key):
			return _failure("compatibility.%s" % key, "unknown")
		var list_error := _string_list_error(
			(value as Dictionary)[key_value],
			true,
			"compatibility.%s" % key
		)
		if not list_error.is_empty():
			return list_error
	return {}


func _string_list_error(value: Variant, allow_empty: bool, field: String) -> Dictionary:
	if not value is Array:
		return _failure(field, "expected_array")
	if not allow_empty and (value as Array).is_empty():
		return _failure(field, "expected_non_empty_array")
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var entry: Variant = (value as Array)[index]
		if not _matches(ID_PATTERN, entry):
			return _failure("%s[%d]" % [field, index], "invalid")
		var text := str(entry)
		if seen.has(text):
			return _failure("%s[%d]" % [field, index], "duplicate")
		seen[text] = true
	return {}


func _array_equals_strings(value: Variant, expected: Array[String]) -> bool:
	if not value is Array or (value as Array).size() != expected.size():
		return false
	for index: int in range(expected.size()):
		if typeof((value as Array)[index]) != TYPE_STRING:
			return false
		if str((value as Array)[index]) != expected[index]:
			return false
	return true


func _exact_fields_error(value: Dictionary, fields: Array[String], path: String) -> Dictionary:
	for field: String in fields:
		if not value.has(field):
			return _failure("%s.%s" % [path, field], "missing")
	for field_value: Variant in value.keys():
		var field := str(field_value)
		if not fields.has(field):
			return _failure("%s.%s" % [path, field], "unknown")
	return {}


func _matches(pattern: String, value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(str(value)) != null


func _is_exact_integer(value: Variant, expected: int) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == floorf(numeric) and int(numeric) == expected


func _failure(field: String, reason: String) -> Dictionary:
	return {
		"ok": false,
		"profile": {},
		"context": {"field": field, "reason": reason},
	}
