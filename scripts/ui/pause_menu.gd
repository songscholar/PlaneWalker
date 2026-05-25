class_name PauseMenu
extends CanvasLayer

signal resume_requested()

@onready var resume_button: Button = $Panel/Margin/VBox/ResumeButton


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_button.pressed.connect(_on_resume_pressed)


func show_pause() -> void:
	visible = true


func hide_pause() -> void:
	visible = false


func _on_resume_pressed() -> void:
	resume_requested.emit()
