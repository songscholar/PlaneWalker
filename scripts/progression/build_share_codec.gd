class_name BuildShareCodec
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Library := preload("res://scripts/progression/build_library.gd")
const Result := preload("res://scripts/progression/profile_command_candidate.gd")
const PAYLOAD_FIELDS := ["schema_version", "name", "character_id", "weapon_id", "time_abilities"]
const MAX_CODE_LENGTH := 1024


static func encode(build: Dictionary) -> Dictionary:
	if not Catalog.exact_fields(build, Library.BUILD_FIELDS) or not Catalog.stable_id(build.id):
		return Result.failure(&"SHARE_CODE_INVALID")
	var pair: Variant = build.time_abilities
	if not pair is Array:
		return Result.failure(&"SHARE_CODE_INVALID")
	var sorted_pair: Array = pair.duplicate(true)
	if sorted_pair.size() != 2 or not sorted_pair[0] is String or not sorted_pair[1] is String:
		return Result.failure(&"SHARE_CODE_INVALID")
	sorted_pair.sort()
	var payload := {"schema_version": 1, "name": build.name, "character_id": build.character_id, "weapon_id": build.weapon_id, "time_abilities": sorted_pair}
	if not _valid_payload(payload):
		return Result.failure(&"SHARE_CODE_INVALID")
	var serialized := JSON.stringify(payload, "", true, true)
	var code := "PW1.%s.%s" % [Marshalls.utf8_to_base64(serialized), serialized.sha256_text()]
	return Result.success({"share_code": code}) if code.length() <= MAX_CODE_LENGTH else Result.failure(&"SHARE_CODE_INVALID")


static func decode(code: Variant) -> Dictionary:
	if not code is String or code.is_empty() or code.length() > MAX_CODE_LENGTH:
		return Result.failure(&"SHARE_CODE_INVALID")
	var parts: PackedStringArray = code.split(".")
	if parts.size() != 3 or parts[0] != "PW1" or not Catalog.fingerprint_valid(parts[2]):
		return Result.failure(&"SHARE_CODE_INVALID")
	var pattern := RegEx.new()
	pattern.compile("^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$")
	if parts[1].is_empty() or pattern.search(parts[1]) == null:
		return Result.failure(&"SHARE_CODE_INVALID")
	var serialized := Marshalls.base64_to_utf8(parts[1])
	if Marshalls.utf8_to_base64(serialized) != parts[1] or serialized.sha256_text() != parts[2]:
		return Result.failure(&"SHARE_CODE_INVALID")
	var parser := JSON.new()
	if parser.parse(serialized) != OK or not _valid_payload(parser.data):
		return Result.failure(&"SHARE_CODE_INVALID")
	var payload: Dictionary = parser.data
	payload.schema_version = 1
	if JSON.stringify(payload, "", true, true) != serialized:
		return Result.failure(&"SHARE_CODE_INVALID")
	return Result.success({"build": {"id": "share-" + parts[2].left(32), "name": payload.name, "character_id": payload.character_id, "weapon_id": payload.weapon_id, "time_abilities": payload.time_abilities.duplicate()}})


static func _valid_payload(value: Variant) -> bool:
	if not Catalog.exact_fields(value, PAYLOAD_FIELDS) or not Catalog.bounded_int(value.schema_version, 1, 1) or not value.name is String or value.name.strip_edges().is_empty() or value.name.length() > 64 or value.name.to_utf8_buffer().has(0):
		return false
	if not value.character_id is String or not Catalog.CHARACTER_IDS.has(value.character_id) or not value.weapon_id is String or not Catalog.WEAPON_IDS.has(value.weapon_id):
		return false
	return value.time_abilities is Array and value.time_abilities.size() == 2 and value.time_abilities[0] is String and value.time_abilities[1] is String and Catalog.TIME_IDS.has(value.time_abilities[0]) and Catalog.TIME_IDS.has(value.time_abilities[1]) and value.time_abilities[0] < value.time_abilities[1]
