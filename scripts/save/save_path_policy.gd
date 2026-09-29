class_name SavePathPolicy
extends RefCounted

const SaveResultScript := preload("res://scripts/save/save_result.gd")

const MAX_ID_LENGTH := 32
const MAX_PATH_LENGTH := 240
const MAX_PATH_SEGMENT_LENGTH := 64


static func validate_id(value: Variant, field_name: StringName = &"id"):
	if typeof(value) != TYPE_STRING:
		return _invalid(field_name, "type", value)
	var identifier := str(value)
	if identifier.is_empty() or identifier.length() > MAX_ID_LENGTH:
		return _invalid(field_name, "length", identifier)
	if not _is_lower_ascii_alphanumeric(identifier.unicode_at(0)):
		return _invalid(field_name, "leading-character", identifier)
	for index: int in range(1, identifier.length()):
		var codepoint := identifier.unicode_at(index)
		if not _is_lower_ascii_alphanumeric(codepoint) and codepoint not in [45, 95]:
			return _invalid(field_name, "character", identifier)
	return SaveResultScript.success(identifier)


static func validate_relative_path(value: Variant, field_name: StringName = &"path"):
	if typeof(value) != TYPE_STRING:
		return _invalid(field_name, "type", value)
	var relative_path := str(value)
	if relative_path.is_empty() or relative_path.length() > MAX_PATH_LENGTH:
		return _invalid(field_name, "length", relative_path)
	if relative_path.begins_with("/") or relative_path.ends_with("/"):
		return _invalid(field_name, "absolute-or-directory", relative_path)
	if relative_path.contains("\\") or relative_path.contains(":") or relative_path.contains("//"):
		return _invalid(field_name, "separator-or-scheme", relative_path)

	var segments := relative_path.split("/", true)
	if segments.is_empty():
		return _invalid(field_name, "segments", relative_path)
	for segment: String in segments:
		if not _path_segment_is_valid(segment):
			return _invalid(field_name, "segment", relative_path)
	return SaveResultScript.success(relative_path)


static func _path_segment_is_valid(segment: String) -> bool:
	if segment.is_empty() or segment in [".", ".."] or segment.length() > MAX_PATH_SEGMENT_LENGTH:
		return false
	if not _is_lower_ascii_alphanumeric(segment.unicode_at(0)):
		return false
	for index: int in range(1, segment.length()):
		var codepoint := segment.unicode_at(index)
		if not _is_lower_ascii_alphanumeric(codepoint) and codepoint not in [45, 46, 95]:
			return false
	return true


static func _is_lower_ascii_alphanumeric(codepoint: int) -> bool:
	return (codepoint >= 97 and codepoint <= 122) or (codepoint >= 48 and codepoint <= 57)


static func _invalid(field_name: StringName, reason: String, value: Variant):
	return SaveResultScript.failure(
		&"INVALID_ARGUMENT",
		{
			"field": str(field_name),
			"reason": reason,
			"value": value,
		}
	)
