class_name TrainingChronoWarden
extends "res://scripts/enemies/boss_chrono_warden.gd"

const MAX_CONVERSIONS := 16
var _training_conversions: Dictionary = {}


func apply_time_stop_source(source_id: StringName, duration: float) -> void:
	var before := get_boss_ui_snapshot()
	var existed := _time_stop_sources.has(source_id)
	super.apply_time_stop_source(source_id, duration)
	var after := get_boss_ui_snapshot()
	if existed or source_id == &"" or not _time_stop_sources.has(source_id) or before.phase not in ["WINDUP", "RECOVERY"] or before.action == "NONE" or float(before.remaining) <= 0.0 or before.action != after.action or before.phase != after.phase or not after.exposed or float(after.remaining) <= float(before.remaining) or not is_instance_valid(target) or not target.has_method("current_run_id"):
		return
	if _training_conversions.size() >= MAX_CONVERSIONS:
		_training_conversions.erase(_training_conversions.keys()[0])
	_training_conversions[str(source_id)] = {"source_id": str(source_id), "run_id": str(target.current_run_id()), "frame": int(target.get("_runtime_frame")), "boss_id": get_instance_id(), "player_id": target.get_instance_id(), "before": before.duplicate(true), "after": after.duplicate(true)}


func training_conversion_fact(source_id: StringName) -> Dictionary:
	return (_training_conversions.get(str(source_id), {}) as Dictionary).duplicate(true)


func training_binding_identity() -> Dictionary:
	var identity := character_boss_exposure_identity()
	identity.erase("hostile_next_generation_floor")
	identity.erase("committed_attack_generation")
	return identity


func training_binding_snapshot() -> Dictionary:
	return {"identity": training_binding_identity(), "health": health.runtime_state_snapshot(), "action": get_boss_ui_snapshot(), "position": global_position, "stop_sources": _time_stop_sources.duplicate(true), "conversions": _training_conversions.duplicate(true)}
