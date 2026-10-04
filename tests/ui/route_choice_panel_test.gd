extends "res://tests/ui/p14_panel_test_base.gd"


func _init() -> void:
	panel_kind = "route"
	panel_scene = "res://scenes/ui/route_choice_panel.tscn"
	command_signal = "route_requested"
