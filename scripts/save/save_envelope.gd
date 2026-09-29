class_name SaveEnvelope
extends RefCounted

const SaveResultScript := preload("res://scripts/save/save_result.gd")
const SavePathPolicyScript := preload("res://scripts/save/save_path_policy.gd")

const MAGIC := "PWSAVE"
const SCHEMA_VERSION := 1
const INTEGRITY_ALGORITHM := "sha256"
const VALID_DOCUMENT_KINDS: Array[String] = ["profile", "settings"]
const PROFILE_FIELDS: Array[String] = [
	"magic",
	"schema_version",
	"document_kind",
	"profile_id",
	"save_domain",
	"sequence",
	"game_version",
	"created_at_utc",
	"saved_at_utc",
	"content_snapshot",
	"payload",
	"integrity",
]
const SETTINGS_FIELDS: Array[String] = [
	"magic",
	"schema_version",
	"document_kind",
	"sequence",
	"game_version",
	"created_at_utc",
	"saved_at_utc",
	"payload",
	"integrity",
]
const CONTENT_SNAPSHOT_FIELDS: Array[String] = ["aggregate_sha256", "packs"]
const CONTENT_PACK_FIELDS: Array[String] = [
	"pack_id",
	"pack_version",
	"schema_version",
	"fingerprint_sha256",
]
const SETTINGS_PAYLOAD_FIELDS: Array[String] = [
	"locale",
	"master_volume",
	"master_muted",
	"music_volume",
	"sfx_volume",
	"dialogue_volume",
	"camera_shake_enabled",
	"hit_flash_enabled",
	"reduced_motion",
	"text_scale",
	"high_contrast_danger",
	"subtitles_enabled",
	"subtitle_scale",
	"ranged_charge_mode",
	"damage_received_multiplier",
	"enemy_telegraph_scale",
]
const LEGACY_SETTINGS_REQUIRED_FIELDS: Array[String] = [
	"locale",
	"master_volume",
	"master_muted",
	"camera_shake_enabled",
	"hit_flash_enabled",
	"reduced_motion",
]


static func create_profile(
	profile_id: String,
	save_domain: String,
	sequence: int,
	game_version: String,
	created_at_utc: String,
	saved_at_utc: String,
	content_snapshot: Dictionary,
	payload: Dictionary
):
	var profile_validation = SavePathPolicyScript.validate_id(profile_id, &"profile_id")
	if not profile_validation.ok:
		return profile_validation
	var domain_validation = SavePathPolicyScript.validate_id(save_domain, &"save_domain")
	if not domain_validation.ok:
		return domain_validation
	var common_error := _common_create_error(sequence, game_version, created_at_utc, saved_at_utc, payload)
	if not common_error.is_empty():
		return _invalid_create(str(common_error["field"]), str(common_error["reason"]), common_error.get("value"))
	var snapshot_error := _content_snapshot_error(content_snapshot)
	if not snapshot_error.is_empty():
		return _invalid_create(str(snapshot_error["field"]), str(snapshot_error["reason"]), snapshot_error.get("value"))

	var document := {
		"magic": MAGIC,
		"schema_version": SCHEMA_VERSION,
		"document_kind": "profile",
		"profile_id": profile_id,
		"save_domain": save_domain,
		"sequence": sequence,
		"game_version": game_version,
		"created_at_utc": created_at_utc,
		"saved_at_utc": saved_at_utc,
		"content_snapshot": content_snapshot.duplicate(true),
		"payload": payload.duplicate(true),
	}
	return _finish_create(document)


static func create_settings(
	sequence: int,
	game_version: String,
	created_at_utc: String,
	saved_at_utc: String,
	payload: Dictionary
):
	var common_error := _common_create_error(sequence, game_version, created_at_utc, saved_at_utc, payload)
	if not common_error.is_empty():
		return _invalid_create(str(common_error["field"]), str(common_error["reason"]), common_error.get("value"))
	var settings_error := _settings_payload_error(payload)
	if not settings_error.is_empty():
		return _invalid_create(str(settings_error["field"]), str(settings_error["reason"]), settings_error.get("value"))

	var document := {
		"magic": MAGIC,
		"schema_version": SCHEMA_VERSION,
		"document_kind": "settings",
		"sequence": sequence,
		"game_version": game_version,
		"created_at_utc": created_at_utc,
		"saved_at_utc": saved_at_utc,
		"payload": payload.duplicate(true),
	}
	return _finish_create(document)


static func validate(
	value: Variant,
	expected_document_kind: StringName = &"",
	expected_profile_id: String = "",
	expected_save_domain: String = ""
):
	if typeof(value) != TYPE_DICTIONARY:
		return _corrupt("document", "type")
	var document: Dictionary = (value as Dictionary).duplicate(true)
	if typeof(document.get("magic")) != TYPE_STRING or str(document.get("magic")) != MAGIC:
		return _corrupt("magic", "value")
	if not _is_integer_number(document.get("schema_version")):
		return _corrupt("schema_version", "type")
	var schema_version := int(document["schema_version"])
	if schema_version > SCHEMA_VERSION:
		return SaveResultScript.failure(
			&"FORWARD_VERSION",
			{"schema_version": schema_version, "supported_version": SCHEMA_VERSION}
		)
	if schema_version != SCHEMA_VERSION:
		return _corrupt("schema_version", "value")
	if typeof(document.get("document_kind")) != TYPE_STRING:
		return _corrupt("document_kind", "type")

	var document_kind := str(document["document_kind"])
	if not VALID_DOCUMENT_KINDS.has(document_kind):
		return _corrupt("document_kind", "value")
	var expected_kind := str(expected_document_kind)
	if not expected_kind.is_empty() and not VALID_DOCUMENT_KINDS.has(expected_kind):
		return SaveResultScript.failure(
			&"INVALID_ARGUMENT",
			{"field": "expected_document_kind", "value": expected_kind}
		)
	if not expected_kind.is_empty() and document_kind != expected_kind:
		return _corrupt("document_kind", "unexpected", {"expected": expected_kind, "actual": document_kind})

	var expected_fields := PROFILE_FIELDS if document_kind == "profile" else SETTINGS_FIELDS
	if not _has_exact_fields(document, expected_fields):
		return _corrupt("document", "fields")
	var common_error := _common_document_error(document)
	if not common_error.is_empty():
		return _corrupt(str(common_error["field"]), str(common_error["reason"]), {"value": common_error.get("value")})

	if document_kind == "profile":
		var profile_error := _profile_document_error(document, expected_profile_id, expected_save_domain)
		if not profile_error.is_empty():
			return _corrupt(str(profile_error["field"]), str(profile_error["reason"]), {"value": profile_error.get("value")})
	else:
		if not expected_profile_id.is_empty() or not expected_save_domain.is_empty():
			return SaveResultScript.failure(
				&"INVALID_ARGUMENT",
				{"field": "expected_profile_scope", "reason": "settings-not-profile-scoped"}
			)
		var settings_error := _settings_payload_error(document["payload"])
		if not settings_error.is_empty():
			return _corrupt(str(settings_error["field"]), str(settings_error["reason"]), {"value": settings_error.get("value")})

	var integrity_error := _integrity_error(document)
	if not integrity_error.is_empty():
		return _corrupt(str(integrity_error["field"]), str(integrity_error["reason"]), {"value": integrity_error.get("value")})
	return SaveResultScript.success(document)


static func canonical_json(value: Variant) -> String:
	if not _is_json_compatible(value):
		return ""
	return JSON.stringify(value, "", true, true)


static func sha256_digest(value: Variant) -> String:
	var serialized := canonical_json(value)
	if serialized.is_empty():
		return ""
	return serialized.sha256_text()


static func content_snapshot_digest(packs_value: Variant) -> String:
	if typeof(packs_value) != TYPE_ARRAY:
		return ""
	var packs: Array = (packs_value as Array).duplicate(true)
	for pack_value: Variant in packs:
		if typeof(pack_value) != TYPE_DICTIONARY:
			return ""
	_sort_content_packs(packs)
	var normalized: Variant = _json_round_trip({"packs": packs})
	return sha256_digest(normalized)


static func _finish_create(document: Dictionary):
	var normalized_value: Variant = _json_round_trip(document)
	if typeof(normalized_value) != TYPE_DICTIONARY:
		return _invalid_create("document", "json-round-trip", null)
	var normalized_document: Dictionary = normalized_value
	var digest := sha256_digest(normalized_document)
	if digest.is_empty():
		return _invalid_create("integrity", "digest", null)
	normalized_document["integrity"] = {
		"algorithm": INTEGRITY_ALGORITHM,
		"digest": digest,
	}
	return SaveResultScript.success(normalized_document)


static func _common_create_error(
	sequence: int,
	game_version: String,
	created_at_utc: String,
	saved_at_utc: String,
	payload: Dictionary
) -> Dictionary:
	if sequence < 0:
		return {"field": "sequence", "reason": "minimum", "value": sequence}
	if game_version.is_empty():
		return {"field": "game_version", "reason": "empty", "value": game_version}
	if not _is_utc_timestamp(created_at_utc):
		return {"field": "created_at_utc", "reason": "format", "value": created_at_utc}
	if not _is_utc_timestamp(saved_at_utc):
		return {"field": "saved_at_utc", "reason": "format", "value": saved_at_utc}
	if created_at_utc > saved_at_utc:
		return {"field": "saved_at_utc", "reason": "before-created", "value": saved_at_utc}
	if not _is_json_compatible(payload):
		return {"field": "payload", "reason": "json-compatible"}
	return {}


static func _common_document_error(document: Dictionary) -> Dictionary:
	if not _is_integer_number(document["sequence"]) or int(document["sequence"]) < 0:
		return {"field": "sequence", "reason": "type-or-minimum", "value": document["sequence"]}
	if typeof(document["game_version"]) != TYPE_STRING or str(document["game_version"]).is_empty():
		return {"field": "game_version", "reason": "type-or-empty", "value": document["game_version"]}
	if typeof(document["created_at_utc"]) != TYPE_STRING or not _is_utc_timestamp(str(document["created_at_utc"])):
		return {"field": "created_at_utc", "reason": "format", "value": document["created_at_utc"]}
	if typeof(document["saved_at_utc"]) != TYPE_STRING or not _is_utc_timestamp(str(document["saved_at_utc"])):
		return {"field": "saved_at_utc", "reason": "format", "value": document["saved_at_utc"]}
	if str(document["created_at_utc"]) > str(document["saved_at_utc"]):
		return {"field": "saved_at_utc", "reason": "before-created", "value": document["saved_at_utc"]}
	if typeof(document["payload"]) != TYPE_DICTIONARY or not _is_json_compatible(document["payload"]):
		return {"field": "payload", "reason": "type-or-json-compatible"}
	return {}


static func _profile_document_error(
	document: Dictionary,
	expected_profile_id: String,
	expected_save_domain: String
) -> Dictionary:
	if not SavePathPolicyScript.validate_id(document["profile_id"], &"profile_id").ok:
		return {"field": "profile_id", "reason": "value", "value": document["profile_id"]}
	if not SavePathPolicyScript.validate_id(document["save_domain"], &"save_domain").ok:
		return {"field": "save_domain", "reason": "value", "value": document["save_domain"]}
	if not expected_profile_id.is_empty() and str(document["profile_id"]) != expected_profile_id:
		return {"field": "profile_id", "reason": "unexpected", "value": document["profile_id"]}
	if not expected_save_domain.is_empty() and str(document["save_domain"]) != expected_save_domain:
		return {"field": "save_domain", "reason": "unexpected", "value": document["save_domain"]}
	if typeof(document["content_snapshot"]) != TYPE_DICTIONARY:
		return {"field": "content_snapshot", "reason": "type", "value": typeof(document["content_snapshot"])}
	return _content_snapshot_error(document["content_snapshot"])


static func _content_snapshot_error(snapshot: Dictionary) -> Dictionary:
	if not _has_exact_fields(snapshot, CONTENT_SNAPSHOT_FIELDS):
		return {"field": "content_snapshot", "reason": "fields"}
	if typeof(snapshot["aggregate_sha256"]) != TYPE_STRING or not _is_sha256_hex(str(snapshot["aggregate_sha256"])):
		return {"field": "content_snapshot.aggregate_sha256", "reason": "value", "value": snapshot["aggregate_sha256"]}
	if typeof(snapshot["packs"]) != TYPE_ARRAY or snapshot["packs"].is_empty():
		return {"field": "content_snapshot.packs", "reason": "type-or-empty"}

	var packs: Array = snapshot["packs"]
	var pack_records: Dictionary = {}
	for index: int in range(packs.size()):
		var pack_value: Variant = packs[index]
		if typeof(pack_value) != TYPE_DICTIONARY:
			return {"field": "content_snapshot.packs[%d]" % index, "reason": "type"}
		var pack: Dictionary = pack_value
		if not _has_exact_fields(pack, CONTENT_PACK_FIELDS):
			return {"field": "content_snapshot.packs[%d]" % index, "reason": "fields"}
		if not _identifier_is_valid(pack["pack_id"], 64):
			return {"field": "content_snapshot.packs[%d].pack_id" % index, "reason": "value", "value": pack["pack_id"]}
		if typeof(pack["pack_version"]) != TYPE_STRING or str(pack["pack_version"]).is_empty():
			return {"field": "content_snapshot.packs[%d].pack_version" % index, "reason": "type-or-empty"}
		if not _is_integer_number(pack["schema_version"]) or int(pack["schema_version"]) < 1:
			return {"field": "content_snapshot.packs[%d].schema_version" % index, "reason": "type-or-minimum"}
		if typeof(pack["fingerprint_sha256"]) != TYPE_STRING or not _is_sha256_hex(str(pack["fingerprint_sha256"])):
			return {"field": "content_snapshot.packs[%d].fingerprint_sha256" % index, "reason": "value"}
		var record_key := canonical_json(pack)
		if pack_records.has(record_key):
			return {"field": "content_snapshot.packs", "reason": "duplicate"}
		pack_records[record_key] = true

	var sorted_packs: Array = packs.duplicate(true)
	_sort_content_packs(sorted_packs)
	if packs != sorted_packs:
		return {"field": "content_snapshot.packs", "reason": "not-sorted"}
	var aggregate := content_snapshot_digest(packs)
	if aggregate != str(snapshot["aggregate_sha256"]):
		return {
			"field": "content_snapshot.aggregate_sha256",
			"reason": "mismatch",
			"value": snapshot["aggregate_sha256"],
		}
	return {}


static func _settings_payload_error(payload: Dictionary) -> Dictionary:
	if not _has_required_fields(payload, LEGACY_SETTINGS_REQUIRED_FIELDS):
		return {"field": "payload", "reason": "missing-required-fields"}
	if not _has_only_known_fields(payload, SETTINGS_PAYLOAD_FIELDS):
		return {"field": "payload", "reason": "unknown-fields"}
	if typeof(payload["locale"]) != TYPE_STRING or str(payload["locale"]) not in ["zh_CN", "en"]:
		return {"field": "payload.locale", "reason": "value", "value": payload["locale"]}
	for field: String in ["master_volume", "music_volume", "sfx_volume", "dialogue_volume"]:
		if not payload.has(field):
			continue
		var volume_error := _finite_range_error(payload[field], "payload.%s" % field, 0.0, 1.0)
		if not volume_error.is_empty():
			return volume_error
	for field: String in [
		"master_muted",
		"camera_shake_enabled",
		"hit_flash_enabled",
		"reduced_motion",
		"high_contrast_danger",
		"subtitles_enabled",
	]:
		if not payload.has(field):
			continue
		if typeof(payload[field]) != TYPE_BOOL:
			return {"field": "payload.%s" % field, "reason": "type", "value": payload[field]}
	for field: String in ["text_scale", "subtitle_scale"]:
		if payload.has(field) and not _number_is_one_of(payload[field], [1.0, 1.25, 1.5]):
			return {"field": "payload.%s" % field, "reason": "value", "value": payload[field]}
	if payload.has("ranged_charge_mode") and (
		typeof(payload["ranged_charge_mode"]) != TYPE_STRING
		or str(payload["ranged_charge_mode"]) not in ["hold", "toggle"]
	):
		return {"field": "payload.ranged_charge_mode", "reason": "value", "value": payload["ranged_charge_mode"]}
	if payload.has("damage_received_multiplier") and not _number_is_one_of(payload["damage_received_multiplier"], [1.0, 0.8, 0.6]):
		return {"field": "payload.damage_received_multiplier", "reason": "value", "value": payload["damage_received_multiplier"]}
	if payload.has("enemy_telegraph_scale") and not _number_is_one_of(payload["enemy_telegraph_scale"], [1.0, 1.25, 1.5]):
		return {"field": "payload.enemy_telegraph_scale", "reason": "value", "value": payload["enemy_telegraph_scale"]}
	return {}


static func _finite_range_error(value: Variant, field: String, minimum: float, maximum: float) -> Dictionary:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return {"field": field, "reason": "type", "value": value}
	var numeric := float(value)
	if not is_finite(numeric) or numeric < minimum or numeric > maximum:
		return {"field": field, "reason": "range", "value": value}
	return {}


static func _number_is_one_of(value: Variant, allowed: Array[float]) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric in allowed


static func _integrity_error(document: Dictionary) -> Dictionary:
	if typeof(document["integrity"]) != TYPE_DICTIONARY:
		return {"field": "integrity", "reason": "type"}
	var integrity: Dictionary = document["integrity"]
	if not _has_exact_fields(integrity, ["algorithm", "digest"]):
		return {"field": "integrity", "reason": "fields"}
	if typeof(integrity["algorithm"]) != TYPE_STRING or str(integrity["algorithm"]) != INTEGRITY_ALGORITHM:
		return {"field": "integrity.algorithm", "reason": "value", "value": integrity["algorithm"]}
	if typeof(integrity["digest"]) != TYPE_STRING or not _is_sha256_hex(str(integrity["digest"])):
		return {"field": "integrity.digest", "reason": "value", "value": integrity["digest"]}
	var unsigned_document := document.duplicate(true)
	unsigned_document.erase("integrity")
	var actual_digest := sha256_digest(unsigned_document)
	if actual_digest != str(integrity["digest"]):
		return {
			"field": "integrity.digest",
			"reason": "mismatch",
			"value": integrity["digest"],
			"actual": actual_digest,
		}
	return {}


static func _has_exact_fields(value: Dictionary, expected_fields: Array) -> bool:
	if value.size() != expected_fields.size():
		return false
	for field: Variant in expected_fields:
		if not value.has(field):
			return false
	return true


static func _has_required_fields(value: Dictionary, required_fields: Array) -> bool:
	for field: Variant in required_fields:
		if not value.has(field):
			return false
	return true


static func _has_only_known_fields(value: Dictionary, known_fields: Array) -> bool:
	for field: Variant in value.keys():
		if not known_fields.has(field):
			return false
	return true


static func _sort_content_packs(packs: Array) -> void:
	packs.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _content_pack_sort_key(left) < _content_pack_sort_key(right)
	)


static func _content_pack_sort_key(pack: Dictionary) -> String:
	return "%s\u001f%s\u001f%010d\u001f%s" % [
		str(pack.get("pack_id", "")),
		str(pack.get("pack_version", "")),
		int(pack.get("schema_version", 0)),
		str(pack.get("fingerprint_sha256", "")),
	]


static func _identifier_is_valid(value: Variant, max_length: int) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var identifier := str(value)
	if identifier.is_empty() or identifier.length() > max_length:
		return false
	if not _is_lower_ascii_alphanumeric(identifier.unicode_at(0)):
		return false
	for index: int in range(1, identifier.length()):
		var codepoint := identifier.unicode_at(index)
		if not _is_lower_ascii_alphanumeric(codepoint) and codepoint not in [45, 95]:
			return false
	return true


static func _is_utc_timestamp(value: String) -> bool:
	if value.length() != 20:
		return false
	if value.substr(4, 1) != "-" or value.substr(7, 1) != "-":
		return false
	if value.substr(10, 1) != "T" or value.substr(13, 1) != ":" or value.substr(16, 1) != ":" or value.substr(19, 1) != "Z":
		return false
	for index: int in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]:
		var codepoint := value.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
			return false
	var year := int(value.substr(0, 4))
	var month := int(value.substr(5, 2))
	var day := int(value.substr(8, 2))
	var hour := int(value.substr(11, 2))
	var minute := int(value.substr(14, 2))
	var second := int(value.substr(17, 2))
	if year <= 0 or month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59:
		return false
	var month_days: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month == 2 and _is_leap_year(year):
		month_days[1] = 29
	return day >= 1 and day <= month_days[month - 1]


static func _is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)


static func _is_json_compatible(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for child: Variant in value:
				if not _is_json_compatible(child):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in (value as Dictionary).keys():
				if typeof(key) != TYPE_STRING or not _is_json_compatible((value as Dictionary)[key]):
					return false
			return true
		_:
			return false


static func _json_round_trip(value: Variant) -> Variant:
	var serialized := canonical_json(value)
	if serialized.is_empty():
		return null
	var parser := JSON.new()
	if parser.parse(serialized) != OK:
		return null
	return parser.data


static func _is_sha256_hex(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var codepoint := value.unicode_at(index)
		if not ((codepoint >= 48 and codepoint <= 57) or (codepoint >= 97 and codepoint <= 102)):
			return false
	return true


static func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == floorf(numeric)


static func _is_lower_ascii_alphanumeric(codepoint: int) -> bool:
	return (codepoint >= 97 and codepoint <= 122) or (codepoint >= 48 and codepoint <= 57)


static func _invalid_create(field: String, reason: String, value: Variant):
	return SaveResultScript.failure(
		&"INVALID_ARGUMENT",
		{"field": field, "reason": reason, "value": value}
	)


static func _corrupt(field: String, reason: String, context: Dictionary = {}):
	var metadata := context.duplicate(true)
	metadata["field"] = field
	metadata["reason"] = reason
	return SaveResultScript.failure(&"CORRUPT", metadata)
