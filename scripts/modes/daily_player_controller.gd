extends "res://scripts/player/player_controller.gd"

var _daily_condition_ids: Array = []
var _daily_extra_dash_remaining := 0
var _daily_base_mobility: Dictionary = {}
var _daily_base_time: Dictionary = {}


func configure_daily_rules(ids: Array) -> bool:
	if not _daily_base_mobility.is_empty() or _runtime_frame != 0 or ids.size() > 2:
		return false
	for id: Variant in ids:
		if not id is String or id not in ["dodge_master", "temporal_disorder"] or _daily_condition_ids.has(id):
			return false
		_daily_condition_ids.append(id)
	_daily_condition_ids.sort()
	_daily_base_mobility = mobility_snapshot()
	_daily_base_time = {"stop_cooldown": time_manager.time_stop_cooldown, "rewind_cooldown": time_manager.rewind_cooldown, "rift_cooldown": time_manager.time_rift_cooldown, "accelerate_cooldown": time_manager.time_accelerate_cooldown, "stop_duration": time_manager.time_stop_duration + time_manager.time_stop_duration_bonus, "rift_duration": time_manager.time_rift_duration + time_manager.time_rift_duration_bonus, "accelerate_duration": time_manager.time_accelerate_duration + time_manager.time_accelerate_duration_bonus, "rewind_history": rewind_recorder.record_seconds}
	if ids.has("dodge_master"):
		var mobility := _daily_base_mobility.duplicate(true)
		mobility.dash_invulnerable_frames = maxi(0, int(mobility.dash_invulnerable_frames) - 3)
		if not apply_mobility_profile(mobility):
			return false
		_daily_extra_dash_remaining = 1
	if ids.has("temporal_disorder"):
		time_manager.time_stop_cooldown *= 2.0
		time_manager.rewind_cooldown *= 2.0
		time_manager.time_rift_cooldown *= 2.0
		time_manager.time_accelerate_cooldown *= 2.0
		time_manager.time_stop_duration *= 1.5
		time_manager.time_stop_duration_bonus *= 1.5
		time_manager.time_rift_duration *= 1.5
		time_manager.time_rift_duration_bonus *= 1.5
		time_manager.time_accelerate_duration *= 1.5
		time_manager.time_accelerate_duration_bonus *= 1.5
		rewind_recorder.record_seconds *= 1.5
	return true


func daily_rule_snapshot() -> Dictionary:
	return {"schema_version": 1, "ids": _daily_condition_ids.duplicate(), "extra_dash_remaining": _daily_extra_dash_remaining, "base_mobility": _daily_base_mobility.duplicate(true), "base_time": _daily_base_time.duplicate(true)}


func _advance_player_fixed_timers() -> void:
	super._advance_player_fixed_timers()
	if _daily_condition_ids.has("dodge_master") and _dash_cooldown_remaining_frames == 0:
		_daily_extra_dash_remaining = 1


func _begin_dash() -> bool:
	var spending: bool = _daily_condition_ids.has("dodge_master") and _dash_cooldown_remaining_frames > 0 and _daily_extra_dash_remaining == 1
	var cooldown := _dash_cooldown_remaining_frames
	if spending:
		_dash_cooldown_remaining_frames = 0
	var accepted := super._begin_dash()
	if spending:
		if accepted:
			_daily_extra_dash_remaining = 0
		else:
			_dash_cooldown_remaining_frames = cooldown
	return accepted


func _fixed_frame_transaction_snapshot() -> Dictionary:
	var result := super._fixed_frame_transaction_snapshot()
	if not result.is_empty():
		result["daily_extra_dash_remaining"] = _daily_extra_dash_remaining
	return result


func _restore_fixed_frame_transaction(value: Dictionary) -> bool:
	if not value.has("daily_extra_dash_remaining") or typeof(value.daily_extra_dash_remaining) != TYPE_INT or value.daily_extra_dash_remaining not in [0, 1]:
		return false
	_daily_extra_dash_remaining = int(value.daily_extra_dash_remaining)
	return super._restore_fixed_frame_transaction(value)
