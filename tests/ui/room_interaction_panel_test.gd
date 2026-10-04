extends "res://tests/ui/p14_panel_test_base.gd"


func _init() -> void:
	panel_kind = "room"
	panel_scene = "res://scenes/ui/room_interaction_panel.tscn"
	command_signal = "room_choice_requested"
