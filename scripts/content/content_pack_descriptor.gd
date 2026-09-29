class_name ContentPackDescriptor
extends RefCounted

const PACK_SCHEMA_VERSION := 2
const ID_PATTERN := "^[a-z0-9][a-z0-9_-]{0,63}$"
const VERSION_PATTERN := "^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?$"
const DIGEST_PATTERN := "^[a-f0-9]{64}$"
const RELATIVE_PATH_PATTERN := "^(?!/)(?!.*(?:^|/)\\.\\.(?:/|$))(?!.*//)[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$"
const REQUIRED_FIELDS: Array[String] = [
	"pack_id",
	"pack_version",
	"schema_version",
	"game_version_range",
	"dependencies",
	"load_order",
	"content_manifest",
	"localization_sources",
	"asset_manifest",
	"integrity_hashes",
	"entitlement_tag",
]


static func load_path(path: String, required_pack: bool = false) -> Dictionary:
	var pack_path := path
	if not path.to_lower().ends_with(".json"):
		pack_path = path.path_join("pack.json")
	if not FileAccess.file_exists(pack_path):
		return _failure(&"NOT_FOUND", {"path": pack_path})
	var file := FileAccess.open(pack_path, FileAccess.READ)
	if file == null:
		return _failure(&"IO_ERROR", {"path": pack_path})
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return _failure(
			&"INVALID_JSON",
			{
				"path": pack_path,
				"line": parser.get_error_line(),
				"message": parser.get_error_message(),
			}
		)
	if not parser.data is Dictionary:
		return _failure(&"INVALID_PACK", {"path": pack_path, "field": "root"})
	var source: Dictionary = (parser.data as Dictionary).duplicate(true)
	var validation := _validate_source(source, pack_path)
	if not bool(validation.get("ok", false)):
		return validation

	var root_path := pack_path.get_base_dir()
	var integrity_hashes: Dictionary = source["integrity_hashes"]
	var declared_paths := _declared_paths(source)
	for relative_path: String in declared_paths:
		if not integrity_hashes.has(relative_path):
			return _failure(
				&"INTEGRITY_MISSING",
				{"path": pack_path, "file": relative_path}
			)
	for relative_path_value: Variant in integrity_hashes.keys():
		var relative_path := str(relative_path_value)
		if not declared_paths.has(relative_path):
			return _failure(
				&"INVALID_PACK",
				{"path": pack_path, "field": "integrity_hashes", "file": relative_path, "reason": "undeclared_file"}
			)
		var content_path := root_path.path_join(relative_path)
		if not FileAccess.file_exists(content_path):
			return _failure(&"NOT_FOUND", {"path": content_path, "file": relative_path})
		var actual_digest := _file_sha256(content_path)
		if actual_digest.is_empty():
			return _failure(&"IO_ERROR", {"path": content_path, "file": relative_path})
		if actual_digest != str(integrity_hashes[relative_path]):
			return _failure(
				&"INTEGRITY_MISMATCH",
				{
					"path": content_path,
					"file": relative_path,
					"expected": str(integrity_hashes[relative_path]),
					"actual": actual_digest,
				}
			)

	var descriptor := source.duplicate(true)
	descriptor["source_path"] = pack_path
	descriptor["root_path"] = root_path
	descriptor["required_pack"] = required_pack
	descriptor["fingerprint_sha256"] = canonical_digest(source)
	return {
		"ok": true,
		"code": &"OK",
		"descriptor": descriptor,
		"context": {},
	}


static func canonical_digest(source: Dictionary) -> String:
	return _sha256_bytes(JSON.stringify(source, "", true).to_utf8_buffer())


static func _validate_source(source: Dictionary, pack_path: String) -> Dictionary:
	for field: String in REQUIRED_FIELDS:
		if not source.has(field):
			return _failure(&"INVALID_PACK", {"path": pack_path, "field": field, "reason": "missing"})
	for field_value: Variant in source.keys():
		var field := str(field_value)
		if not REQUIRED_FIELDS.has(field):
			return _failure(&"INVALID_PACK", {"path": pack_path, "field": field, "reason": "unknown"})
	if not _matches(ID_PATTERN, source["pack_id"]):
		return _failure(&"INVALID_PACK", {"path": pack_path, "field": "pack_id"})
	if not _matches(VERSION_PATTERN, source["pack_version"]):
		return _failure(&"INVALID_PACK", {"path": pack_path, "field": "pack_version"})
	if not _numeric_integer_equals(source["schema_version"], PACK_SCHEMA_VERSION):
		return _failure(&"UNSUPPORTED_SCHEMA", {"path": pack_path, "field": "schema_version"})
	if typeof(source["game_version_range"]) != TYPE_STRING or str(source["game_version_range"]).is_empty():
		return _failure(&"INVALID_PACK", {"path": pack_path, "field": "game_version_range"})
	if typeof(source["load_order"]) not in [TYPE_INT, TYPE_FLOAT] or not _is_integral_number(source["load_order"]):
		return _failure(&"INVALID_PACK", {"path": pack_path, "field": "load_order"})
	if typeof(source["entitlement_tag"]) != TYPE_STRING or not _matches("^[a-z0-9_.-]{0,64}$", source["entitlement_tag"]):
		return _failure(&"INVALID_PACK", {"path": pack_path, "field": "entitlement_tag"})
	var dependency_error := _dependency_error(source["dependencies"])
	if not dependency_error.is_empty():
		dependency_error["path"] = pack_path
		return _failure(&"INVALID_PACK", dependency_error)
	for field: String in ["content_manifest", "localization_sources", "asset_manifest"]:
		var path_error := _path_list_error(source[field], field)
		if not path_error.is_empty():
			path_error["path"] = pack_path
			return _failure(&"INVALID_PACK", path_error)
	var integrity_error := _integrity_error(source["integrity_hashes"])
	if not integrity_error.is_empty():
		integrity_error["path"] = pack_path
		return _failure(&"INVALID_PACK", integrity_error)
	return {"ok": true, "code": &"OK", "context": {}}


static func _dependency_error(value: Variant) -> Dictionary:
	if not value is Array:
		return {"field": "dependencies", "reason": "not_array"}
	var seen: Dictionary = {}
	for entry_value: Variant in value:
		if not entry_value is Dictionary:
			return {"field": "dependencies", "reason": "entry_not_dictionary"}
		var entry: Dictionary = entry_value
		if entry.size() != 3:
			return {"field": "dependencies", "reason": "unknown_or_missing_field"}
		for field: String in ["pack_id", "version_range", "required"]:
			if not entry.has(field):
				return {"field": "dependencies", "reason": "missing_%s" % field}
		if not _matches(ID_PATTERN, entry["pack_id"]):
			return {"field": "dependencies", "reason": "invalid_pack_id"}
		var dependency_id := str(entry["pack_id"])
		if seen.has(dependency_id):
			return {"field": "dependencies", "reason": "duplicate_pack_id", "pack_id": dependency_id}
		seen[dependency_id] = true
		if typeof(entry["version_range"]) != TYPE_STRING or str(entry["version_range"]).is_empty():
			return {"field": "dependencies", "reason": "invalid_version_range", "pack_id": dependency_id}
		if typeof(entry["required"]) != TYPE_BOOL:
			return {"field": "dependencies", "reason": "invalid_required", "pack_id": dependency_id}
	return {}


static func _path_list_error(value: Variant, field: String) -> Dictionary:
	if not value is Array:
		return {"field": field, "reason": "not_array"}
	var seen: Dictionary = {}
	for path_value: Variant in value:
		if not _matches(RELATIVE_PATH_PATTERN, path_value):
			return {"field": field, "reason": "invalid_path", "value": path_value}
		var relative_path := str(path_value)
		if relative_path.to_lower().ends_with(".gd") or seen.has(relative_path):
			return {"field": field, "reason": "script_or_duplicate_path", "value": relative_path}
		seen[relative_path] = true
	return {}


static func _integrity_error(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"field": "integrity_hashes", "reason": "not_dictionary"}
	for path_value: Variant in (value as Dictionary).keys():
		if not _matches(RELATIVE_PATH_PATTERN, path_value):
			return {"field": "integrity_hashes", "reason": "invalid_path", "value": path_value}
		if not _matches(DIGEST_PATTERN, (value as Dictionary)[path_value]):
			return {"field": "integrity_hashes", "reason": "invalid_digest", "value": path_value}
	return {}


static func _declared_paths(source: Dictionary) -> Array[String]:
	var declared: Dictionary = {}
	for field: String in ["content_manifest", "localization_sources", "asset_manifest"]:
		for path_value: Variant in source[field]:
			declared[str(path_value)] = true
	var paths: Array[String] = []
	for path_value: Variant in declared.keys():
		paths.append(str(path_value))
	paths.sort()
	return paths


static func _file_sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return _sha256_bytes(file.get_buffer(file.get_length()))


static func _sha256_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()


static func _matches(pattern: String, value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return false
	return regex.search(str(value)) != null


static func _numeric_integer_equals(value: Variant, expected: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and _is_integral_number(value) and int(value) == expected


static func _is_integral_number(value: Variant) -> bool:
	var numeric := float(value)
	return is_finite(numeric) and numeric == floorf(numeric)


static func _failure(code: StringName, context: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"descriptor": {},
		"context": context.duplicate(true),
	}
