class_name PauseMenu
extends CanvasLayer

signal resume_requested()

@onready var resume_button: Button = $Panel/Margin/VBox/ResumeButton
@onready var volume_label: Label = $Panel/Margin/VBox/VolumeLabel
@onready var volume_slider: HSlider = $Panel/Margin/VBox/VolumeSlider
@onready var mute_toggle: CheckButton = $Panel/Margin/VBox/MuteToggle


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	resume_button.pressed.connect(_on_resume_pressed)
	volume_slider.value_changed.connect(_on_volume_changed)
	mute_toggle.toggled.connect(_on_mute_toggled)
	_load_settings()
	_apply_audio_settings()


func show_pause() -> void:
	visible = true


func hide_pause() -> void:
	visible = false


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _load_settings() -> void:
	volume_slider.value = float(GameState.get_setting("master_volume", 0.85))
	mute_toggle.button_pressed = bool(GameState.get_setting("master_muted", false))
	_update_volume_label()


func _on_volume_changed(value: float) -> void:
	GameState.set_setting("master_volume", clampf(value, 0.0, 1.0))
	_update_volume_label()
	_apply_audio_settings()


func _on_mute_toggled(toggled_on: bool) -> void:
	GameState.set_setting("master_muted", toggled_on)
	_apply_audio_settings()


func _update_volume_label() -> void:
	volume_label.text = "Master Volume %d%%" % roundi(volume_slider.value * 100.0)


func _apply_audio_settings() -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index < 0:
		return
	var muted := bool(GameState.get_setting("master_muted", false))
	var volume := float(GameState.get_setting("master_volume", 0.85))
	AudioServer.set_bus_mute(bus_index, muted)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(clampf(volume, 0.001, 1.0)))
