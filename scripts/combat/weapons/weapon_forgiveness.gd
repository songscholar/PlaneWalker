class_name WeaponForgiveness
extends RefCounted

const SCHEMA_VERSION := 1
const CONTEXT_FIELD := "character_forgiveness"
const ENVELOPE_FIELDS: Array[String] = [
	"schema_version",
	"descriptor",
	"fingerprint",
]
const DESCRIPTOR_FIELDS := {
	"sword": [
		"weapon_id", "expires_after_frames", "recovery_reduction_frames",
		"minimum_recovery_frames",
	],
	"bow": ["weapon_id", "expires_after_frames", "full_charge_frames"],
	"gun": [
		"weapon_id", "expires_after_frames", "perfect_start_frame", "perfect_end_frame",
	],
	"staff": [
		"weapon_id", "expires_after_frames", "window_extension_frames", "window_cap_frames",
	],
	"gauntlets": [
		"weapon_id", "expires_after_frames", "combo_extension_frames", "combo_cap_frames",
	],
}


static func freeze_from_context(context: Dictionary, expected_weapon_id: StringName) -> Dictionary:
	if not context.has(CONTEXT_FIELD):
		return {"ok": true, "code": &"OK", "envelope": {}}
	var descriptor_value: Variant = context.get(CONTEXT_FIELD)
	if not descriptor_value is Dictionary:
		return _failure(&"INVALID_FORGIVENESS_DESCRIPTOR")
	var descriptor := _normalized_descriptor(descriptor_value as Dictionary, expected_weapon_id)
	if descriptor.is_empty():
		return _failure(&"INVALID_FORGIVENESS_DESCRIPTOR")
	var envelope := {
		"schema_version": SCHEMA_VERSION,
		"descriptor": descriptor,
	}
	envelope["fingerprint"] = _fingerprint(envelope)
	return {
		"ok": true,
		"code": &"OK",
		"envelope": envelope.duplicate(true),
	}


static func attach_to_plan(plan: Dictionary, envelope_value: Variant) -> bool:
	if not envelope_value is Dictionary:
		return false
	var envelope := envelope_value as Dictionary
	if envelope.is_empty():
		plan.erase(CONTEXT_FIELD)
		return true
	var weapon_id := StringName(str(plan.get("weapon_id", "")))
	if not is_valid_envelope(envelope, weapon_id):
		return false
	plan[CONTEXT_FIELD] = envelope.duplicate(true)
	return true


static func envelope_from_plan(plan: Dictionary, expected_weapon_id: StringName) -> Dictionary:
	if not plan.has(CONTEXT_FIELD):
		return {}
	var value: Variant = plan.get(CONTEXT_FIELD)
	if not value is Dictionary or not is_valid_envelope(value as Dictionary, expected_weapon_id):
		return {}
	return (value as Dictionary).duplicate(true)


static func plan_envelope_is_valid(plan: Dictionary, expected_weapon_id: StringName) -> bool:
	if not plan.has(CONTEXT_FIELD):
		return true
	var value: Variant = plan.get(CONTEXT_FIELD)
	return value is Dictionary and is_valid_envelope(value as Dictionary, expected_weapon_id)


static func is_valid_envelope(value: Dictionary, expected_weapon_id: StringName) -> bool:
	if not _has_exact_fields(value, ENVELOPE_FIELDS):
		return false
	if (
		typeof(value.get("schema_version")) != TYPE_INT
		or int(value.get("schema_version", -1)) != SCHEMA_VERSION
		or not value.get("descriptor") is Dictionary
		or typeof(value.get("fingerprint")) != TYPE_STRING
	):
		return false
	var descriptor := _normalized_descriptor(
		value["descriptor"] as Dictionary,
		expected_weapon_id
	)
	if descriptor.is_empty() or descriptor != value["descriptor"]:
		return false
	var signed := {
		"schema_version": SCHEMA_VERSION,
		"descriptor": descriptor,
	}
	return str(value["fingerprint"]) == _fingerprint(signed)


static func descriptor(envelope: Dictionary, expected_weapon_id: StringName) -> Dictionary:
	if not is_valid_envelope(envelope, expected_weapon_id):
		return {}
	return (envelope["descriptor"] as Dictionary).duplicate(true)


static func descriptor_int(
	envelope: Dictionary,
	expected_weapon_id: StringName,
	field: String,
	fallback: int
) -> int:
	var frozen := descriptor(envelope, expected_weapon_id)
	return int(frozen.get(field, fallback)) if not frozen.is_empty() else fallback


static func consumption_context(plan: Dictionary, expected_weapon_id: StringName) -> Dictionary:
	var envelope := envelope_from_plan(plan, expected_weapon_id)
	if envelope.is_empty():
		return {}
	return {
		"consume_forgiveness": true,
		"weapon_id": str(expected_weapon_id),
		"character_forgiveness_fingerprint": str(envelope["fingerprint"]),
		"character_forgiveness": (envelope["descriptor"] as Dictionary).duplicate(true),
	}


static func merge_consumption_context(
	base: Dictionary,
	plan: Dictionary,
	expected_weapon_id: StringName
) -> Dictionary:
	var result := base.duplicate(true)
	var consume := consumption_context(plan, expected_weapon_id)
	for key: Variant in consume.keys():
		result[key] = consume[key]
	return result


static func _normalized_descriptor(
	value: Dictionary,
	expected_weapon_id: StringName
) -> Dictionary:
	var weapon_id := str(expected_weapon_id)
	var fields_value: Variant = DESCRIPTOR_FIELDS.get(weapon_id)
	if not fields_value is Array or not _has_exact_fields(value, fields_value as Array):
		return {}
	if (
		typeof(value.get("weapon_id")) not in [TYPE_STRING, TYPE_STRING_NAME]
		or str(value.get("weapon_id", "")) != weapon_id
		or typeof(value.get("expires_after_frames")) != TYPE_INT
		or int(value.get("expires_after_frames", 0)) != 180
	):
		return {}
	var result := value.duplicate(true)
	result["weapon_id"] = weapon_id
	match expected_weapon_id:
		&"sword":
			if (
				typeof(value.get("recovery_reduction_frames")) != TYPE_INT
				or int(value.get("recovery_reduction_frames", 0)) != 4
				or typeof(value.get("minimum_recovery_frames")) != TYPE_INT
				or int(value.get("minimum_recovery_frames", 0)) != 1
			):
				return {}
		&"bow":
			if typeof(value.get("full_charge_frames")) != TYPE_INT or int(value.get("full_charge_frames", 0)) != 44:
				return {}
		&"gun":
			if (
				typeof(value.get("perfect_start_frame")) != TYPE_INT
				or int(value.get("perfect_start_frame", 0)) != 26
				or typeof(value.get("perfect_end_frame")) != TYPE_INT
				or int(value.get("perfect_end_frame", 0)) != 37
			):
				return {}
		&"staff":
			if (
				typeof(value.get("window_extension_frames")) != TYPE_INT
				or int(value.get("window_extension_frames", 0)) != 60
				or typeof(value.get("window_cap_frames")) != TYPE_INT
				or int(value.get("window_cap_frames", 0)) != 360
			):
				return {}
		&"gauntlets":
			if (
				typeof(value.get("combo_extension_frames")) != TYPE_INT
				or int(value.get("combo_extension_frames", 0)) != 30
				or typeof(value.get("combo_cap_frames")) != TYPE_INT
				or int(value.get("combo_cap_frames", 0)) != 150
			):
				return {}
		_:
			return {}
	return result


static func _fingerprint(value: Dictionary) -> String:
	return var_to_bytes(value).hex_encode().sha256_text()


static func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size():
		return false
	for field_value: Variant in fields:
		if typeof(field_value) != TYPE_STRING or not value.has(str(field_value)):
			return false
	return true


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "envelope": {}}
