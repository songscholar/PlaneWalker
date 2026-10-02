class_name TemporalDistortionRule
extends "res://scripts/dungeon/floor_rule_runtime.gd"


func _init() -> void:
	_define_rule(&"rule_temporal_distortion", {
		"warning_frames": 45,
		"active_frames": 150,
		"recovery_frames": 45,
		"cycle_count": 2,
		"effect_interval_frames": 150,
		"effect_kind": "modifier",
		"modifier_id": "temporal_distortion",
		"modifier_values": {
			"movement_multiplier": 0.85,
			"time_cost_multiplier": 1.15,
		},
		"presentation_cue_id": "floor_rule_temporal_distortion",
	})
