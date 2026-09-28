class_name ContentValidationReport
extends RefCounted

var blocking_errors: Array[Dictionary] = []
var isolated_errors: Array[Dictionary] = []
var warnings: Array[Dictionary] = []
var loaded_count: int = 0


func has_blocking_errors() -> bool:
	return not blocking_errors.is_empty()


func add_error(message: String, context: Dictionary, blocking: bool) -> void:
	var target := blocking_errors if blocking else isolated_errors
	target.append({"message": message, "context": context.duplicate(true)})


func add_warning(message: String, context: Dictionary = {}) -> void:
	warnings.append({"message": message, "context": context.duplicate(true)})
