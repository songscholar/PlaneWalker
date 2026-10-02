class_name SaveResult
extends RefCounted

const STANDARD_CODES: Array[StringName] = [
	&"OK",
	&"NOT_FOUND",
	&"RECOVERED",
	&"INVALID_ARGUMENT",
	&"IO_ERROR",
	&"CORRUPT",
	&"FORWARD_VERSION",
	&"MIGRATION_UNAVAILABLE",
	&"MIGRATION_FAILED",
	&"MIGRATION_UNSAFE_ACTIVE_RUN",
	&"CONTENT_MISMATCH",
	&"BUSY",
]
const SUCCESS_CODES: Array[StringName] = [&"OK", &"RECOVERED"]

var ok: bool = false
var code: StringName = &"INVALID_ARGUMENT"
var payload: Variant = {}
var metadata: Dictionary = {}
var diagnostics: Array[Dictionary] = []
var source_kind: StringName = &""
var migrated_from: int = -1
var migrated_to: int = -1
var player_notice_required: bool = false


static func success(
	p_payload: Variant = {},
	p_metadata: Dictionary = {},
	p_diagnostics: Array[Dictionary] = [],
	p_code: StringName = &"OK"
):
	var result = load("res://scripts/save/save_result.gd").new()
	result.code = p_code if SUCCESS_CODES.has(p_code) else &"OK"
	result.ok = true
	result.payload = _deep_copy(p_payload)
	result.metadata = p_metadata.duplicate(true)
	result.diagnostics = p_diagnostics.duplicate(true)
	result._load_summary_fields()
	return result


static func failure(
	p_code: StringName,
	p_metadata: Dictionary = {},
	p_diagnostics: Array[Dictionary] = []
):
	var result = load("res://scripts/save/save_result.gd").new()
	result.code = p_code if STANDARD_CODES.has(p_code) and not SUCCESS_CODES.has(p_code) else &"INVALID_ARGUMENT"
	result.ok = false
	result.payload = {}
	result.metadata = p_metadata.duplicate(true)
	result.diagnostics = p_diagnostics.duplicate(true)
	if result.code == &"INVALID_ARGUMENT" and p_code != &"INVALID_ARGUMENT":
		result.metadata["requested_code"] = str(p_code)
	result._load_summary_fields()
	return result


static func is_standard_code(p_code: StringName) -> bool:
	return STANDARD_CODES.has(p_code)


func to_dictionary() -> Dictionary:
	return {
		"ok": ok,
		"code": code,
		"payload": _deep_copy(payload),
		"metadata": metadata.duplicate(true),
		"diagnostics": diagnostics.duplicate(true),
		"source_kind": source_kind,
		"migrated_from": migrated_from,
		"migrated_to": migrated_to,
		"player_notice_required": player_notice_required,
	}


func _load_summary_fields() -> void:
	source_kind = StringName(str(metadata.get("source_kind", "")))
	migrated_from = int(metadata.get("migrated_from", -1))
	migrated_to = int(metadata.get("migrated_to", -1))
	player_notice_required = code == &"RECOVERED" or bool(metadata.get("player_notice_required", false))


static func _deep_copy(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		return (value as Dictionary).duplicate(true)
	if typeof(value) == TYPE_ARRAY:
		return (value as Array).duplicate(true)
	return value
