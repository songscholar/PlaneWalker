extends "res://tests/ui/p14_panel_test_base.gd"


func _init() -> void:
	panel_kind = "transition"
	panel_scene = "res://scenes/ui/floor_transition_panel.tscn"
	command_signal = "floor_transition_requested"
