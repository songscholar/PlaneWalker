class_name VoidSporesRule
extends "res://scripts/dungeon/floor_rule_runtime.gd"


func _init() -> void:
	_define_rule(&"rule_void_spores", {
		"warning_frames": 60,
		"active_frames": 120,
		"recovery_frames": 60,
		"cycle_count": 2,
		"effect_interval_frames": 40,
		"effect_kind": "damage",
		"damage_amount": 5.0,
		"damage_type": "void",
		"presentation_cue_id": "floor_rule_void_spores",
	})
