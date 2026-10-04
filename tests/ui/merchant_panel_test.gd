extends "res://tests/ui/p14_panel_test_base.gd"


func _init() -> void:
	panel_kind = "merchant"
	panel_scene = "res://scenes/ui/merchant_panel.tscn"
	command_signal = "merchant_action_requested"
