class_name CollapsingPlaneRule
extends "res://scripts/dungeon/floor_rule_runtime.gd"


func _init() -> void:
	_define_rule(&"rule_collapsing_plane", {
		"warning_frames": 75,
		"active_frames": 180,
		"recovery_frames": 60,
		"cycle_count": 1,
		"effect_interval_frames": 180,
		"effect_kind": "modifier",
		"modifier_id": "collapsing_plane_zone_lock",
		"modifier_values": {
			"zone_locked": true,
			"safe_area_required": true,
		},
		"presentation_cue_id": "floor_rule_collapsing_plane",
	})
