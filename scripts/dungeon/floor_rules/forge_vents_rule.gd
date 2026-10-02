class_name ForgeVentsRule
extends "res://scripts/dungeon/floor_rule_runtime.gd"


func _init() -> void:
	_define_rule(&"rule_forge_vents", {
		"warning_frames": 30,
		"active_frames": 60,
		"recovery_frames": 90,
		"cycle_count": 3,
		"effect_interval_frames": 20,
		"effect_kind": "damage",
		"damage_amount": 10.0,
		"damage_type": "fire",
		"presentation_cue_id": "floor_rule_forge_vents",
	})
