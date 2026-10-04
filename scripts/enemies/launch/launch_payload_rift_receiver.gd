extends Area2D


func apply_time_rift(source_id: StringName, multiplier: float) -> void:
	if get_parent().has_method("apply_time_rift"):
		get_parent().apply_time_rift(source_id, multiplier)


func clear_time_rift(source_id: StringName) -> void:
	if get_parent().has_method("clear_time_rift"):
		get_parent().clear_time_rift(source_id)
