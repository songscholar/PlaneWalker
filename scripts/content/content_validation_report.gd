class_name ContentValidationReport
extends RefCounted

var blocking_errors: Array[Dictionary] = []
var isolated_errors: Array[Dictionary] = []
var warnings: Array[Dictionary] = []
var loaded_count: int = 0
var active_pack_count: int = 0
var isolated_pack_ids: Array[String] = []
var content_count_by_category: Dictionary = {}
var metadata: Dictionary = {}


func has_blocking_errors() -> bool:
	return not blocking_errors.is_empty()


func add_error(message: String, context: Dictionary, blocking: bool) -> void:
	var target := blocking_errors if blocking else isolated_errors
	target.append({"message": message, "context": context.duplicate(true)})


func add_warning(message: String, context: Dictionary = {}) -> void:
	warnings.append({"message": message, "context": context.duplicate(true)})


func merge(other: Variant) -> void:
	if other == null:
		return
	for error: Dictionary in other.blocking_errors:
		blocking_errors.append(error.duplicate(true))
	for error: Dictionary in other.isolated_errors:
		isolated_errors.append(error.duplicate(true))
	for warning: Dictionary in other.warnings:
		warnings.append(warning.duplicate(true))
	loaded_count += int(other.loaded_count)


func set_activation_summary(
	active_count: int,
	isolated_ids: Array,
	category_counts: Dictionary,
	activation_metadata: Dictionary = {}
) -> void:
	active_pack_count = maxi(0, active_count)
	isolated_pack_ids.clear()
	for pack_id: Variant in isolated_ids:
		isolated_pack_ids.append(str(pack_id))
	isolated_pack_ids.sort()
	content_count_by_category = category_counts.duplicate(true)
	metadata = activation_metadata.duplicate(true)
