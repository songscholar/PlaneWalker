class_name CommandResult
extends RefCounted

const STANDARD_CODES: Array[StringName] = [
	&"OK",
	&"INVALID_PHASE",
	&"STALE_REVISION",
	&"OFFER_CLOSED",
	&"OPTION_NOT_FOUND",
	&"ALREADY_CONSUMED",
	&"SELECTION_RESERVED",
	&"RESERVATION_NOT_FOUND",
	&"COMMIT_FAILED",
	&"INTEGRITY_FAILURE",
	&"PLAYER_EFFECT_FAILED",
	&"TERMINAL_STATE",
	&"CONTENT_NOT_AVAILABLE",
	&"LOADOUT_APPLY_FAILED",
	&"AUTHORED_RUNTIME_CONFIGURATION_FAILED",
	&"DUPLICATE_TRANSACTION",
	&"INSUFFICIENT_GOLD",
	&"TRANSACTION_PENDING",
	&"TRANSACTION_NOT_FOUND",
	&"TRANSACTION_STALE",
	&"SAVE_FAILED",
	&"NATIVE_PUBLICATION_PENDING",
	&"NATIVE_RESTORE_REQUIRED",
	&"CHECKPOINT_UNSAFE",
	&"NATIVE_CHECKPOINT_NOT_AVAILABLE",
	&"NATIVE_CHECKPOINT_INVALID",
	&"STALE_DURABLE_PROFILE",
	&"INVALID_ARGUMENT",
]

var ok: bool = false
var code: StringName = &"INVALID_ARGUMENT"
var message_key: StringName = &""
var context: Dictionary = {}
var new_revision: int = 0


static func success(
	p_new_revision: int,
	p_context: Dictionary = {},
	p_message_key: StringName = &""
):
	var result = load("res://scripts/application/command_result.gd").new()
	result.ok = true
	result.code = &"OK"
	result.message_key = p_message_key
	result.context = p_context.duplicate(true)
	result.new_revision = p_new_revision
	return result


static func failure(
	p_code: StringName,
	p_new_revision: int,
	p_context: Dictionary = {},
	p_message_key: StringName = &""
):
	var result = load("res://scripts/application/command_result.gd").new()
	result.ok = false
	result.code = p_code if is_standard_code(p_code) and p_code != &"OK" else &"INVALID_ARGUMENT"
	result.message_key = p_message_key
	result.context = p_context.duplicate(true)
	if result.code == &"INVALID_ARGUMENT" and p_code != &"INVALID_ARGUMENT":
		result.context["requested_code"] = str(p_code)
	result.new_revision = p_new_revision
	return result


static func is_standard_code(p_code: StringName) -> bool:
	return STANDARD_CODES.has(p_code)
