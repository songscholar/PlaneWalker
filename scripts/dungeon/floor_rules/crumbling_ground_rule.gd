class_name CrumblingGroundRule
extends "res://scripts/dungeon/floor_rule_runtime.gd"


func _init() -> void:
	_define_rule(&"rule_crumbling_ground", {
		"warning_frames": 45,
		"active_frames": 90,
		"recovery_frames": 45,
		"cycle_count": 2,
		"effect_interval_frames": 30,
		"effect_kind": "damage",
		"damage_amount": 8.0,
		"damage_type": "physical",
		"presentation_cue_id": "floor_rule_crumbling_ground",
	})
