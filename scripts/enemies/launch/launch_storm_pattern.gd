class_name LaunchStormPattern
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Seeds := preload("res://scripts/core/seed_service.gd")
const FIELDS := ["initial_fast", "fast_multiplier", "slow_multiplier", "swap_interval_frames", "swap_warning_frames"]


static func create(seed: int, source_id: String, generation: int, index: int, mechanisms: Dictionary) -> Dictionary:
	var rng := Seeds.make_rng(seed, StringName("chrono_storm_pattern_v1:%s:%d" % [source_id, generation]))
	return {"initial_fast": (rng.randi_range(0, 1) + index) % 2 == 0, "fast_multiplier": float(mechanisms.fast_multiplier), "slow_multiplier": float(mechanisms.slow_multiplier), "swap_interval_frames": int(mechanisms.swap_interval_frames), "swap_warning_frames": int(mechanisms.swap_warning_frames)}


static func valid(value: Variant) -> bool:
	return value is Dictionary and Contract.exact_fields(value, FIELDS) and typeof(value.initial_fast) == TYPE_BOOL and Contract.number_in_range(value.fast_multiplier, 1.0, 1.25) and Contract.number_in_range(value.slow_multiplier, 0.6, 1.0) and Contract.integer_in_range(value.swap_interval_frames, 90, 180) and Contract.integer_in_range(value.swap_warning_frames, 30, 120) and value.swap_warning_frames < value.swap_interval_frames


static func project(value: Dictionary, active_frame: int, frame: int) -> Dictionary:
	var elapsed := maxi(0, frame - active_frame)
	var cycle: int = elapsed / int(value.swap_interval_frames)
	var fast: bool = bool(value.initial_fast) != (cycle % 2 == 1)
	return {"fast": fast, "slow_multiplier": 1.0 if fast else float(value.slow_multiplier), "speed_multiplier": float(value.fast_multiplier) if fast else 1.0, "swap_warning": frame >= active_frame and elapsed % int(value.swap_interval_frames) >= int(value.swap_interval_frames) - int(value.swap_warning_frames)}
