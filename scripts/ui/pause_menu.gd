class_name PauseMenu
extends CanvasLayer

signal resume_requested()
signal remap_requested()
signal accessibility_requested()

@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var resume_button: Button = $Panel/Margin/VBox/ResumeButton
@onready var settings_button: Button = $Panel/Margin/VBox/SettingsButton
@onready var remap_button: Button = $Panel/Margin/VBox/RemapButton
@onready var restart_button: Button = $Panel/Margin/VBox/RestartButton
@onready var quit_button: Button = $Panel/Margin/VBox/QuitButton


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	title_label.text = tr("UI_PAUSED")
	resume_button.text = tr("UI_RESUME")
	settings_button.text = tr("UI_ACCESSIBILITY_SETTINGS")
	remap_button.text = tr("UI_INPUT_REMAP")
	restart_button.text = tr("UI_RESTART_RUN")
	quit_button.text = tr("UI_QUIT")
	resume_button.pressed.connect(_on_resume_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	remap_button.pressed.connect(_on_remap_pressed)
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	FocusCoordinator.link_ring(
		[resume_button, settings_button, remap_button, restart_button, quit_button],
		false
	)


func show_pause() -> void:
	visible = true
	FocusCoordinator.open_scope(self, resume_button)


func hide_pause() -> void:
	FocusCoordinator.close_scope(self)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and FocusCoordinator.active_scope() == self and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_settings_pressed() -> void:
	accessibility_requested.emit()


func _on_remap_pressed() -> void:
	remap_requested.emit()


func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	get_tree().quit()
