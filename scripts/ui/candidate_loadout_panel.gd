class_name CandidateLoadoutPanel
extends Control

signal candidate_requested(config: Dictionary)

const PRESETS := [
	{
		"schema_version": 1,
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "bow",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
	},
	{
		"schema_version": 1,
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rift"],
		"difficulty": "normal",
	},
	{
		"schema_version": 1,
		"milestone": "NEXT",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "accelerate"],
		"difficulty": "normal",
	},
]

const PRESET_LOCALIZATION := [
	["CHARACTER_WANDERER_NAME", "WEAPON_BOW_NAME", "TIME_ABILITY_STOP_NAME", "TIME_ABILITY_REWIND_NAME"],
	["CHARACTER_WANDERER_NAME", "WEAPON_SWORD_NAME", "TIME_ABILITY_STOP_NAME", "TIME_ABILITY_RIFT_NAME"],
	["CHARACTER_WANDERER_NAME", "WEAPON_SWORD_NAME", "TIME_ABILITY_STOP_NAME", "TIME_ABILITY_ACCELERATE_NAME"],
]

@onready var title_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/TitleLabel
@onready var warning_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/WarningLabel
@onready var bow_button: Button = $SafeArea/Center/PanelRoot/Margin/Layout/BowButton
@onready var rift_button: Button = $SafeArea/Center/PanelRoot/Margin/Layout/RiftButton
@onready var accelerate_button: Button = $SafeArea/Center/PanelRoot/Margin/Layout/AccelerateButton
@onready var status_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/StatusLabel
@onready var back_button: Button = $SafeArea/Center/PanelRoot/Margin/Layout/BackButton

var _restore_focus: Control
var _focus_controls: Array[Control] = []
var _showing_rejection := false


func configure(restore_focus: Control = null) -> void:
	_restore_focus = restore_focus


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_focus_controls = [bow_button, rift_button, accelerate_button, back_button]
	for index: int in range(3):
		var button := _focus_controls[index] as Button
		button.pressed.connect(_on_preset_pressed.bind(index))
	back_button.pressed.connect(close_panel)
	FocusCoordinator.link_ring(_focus_controls, false)
	_apply_localization()


func open_panel(restore_focus: Control = null) -> void:
	if restore_focus != null:
		_restore_focus = restore_focus
	if _restore_focus != null and _restore_focus.is_inside_tree() and _restore_focus.is_visible_in_tree():
		_restore_focus.grab_focus()
	_showing_rejection = false
	status_label.text = ""
	visible = true
	FocusCoordinator.link_ring(_focus_controls, false)
	FocusCoordinator.open_scope(self, bow_button)


func close_panel() -> void:
	if not visible:
		return
	FocusCoordinator.close_scope(self)
	visible = false
	_showing_rejection = false
	status_label.text = ""


func show_start_rejected() -> void:
	if not visible:
		return
	_showing_rejection = true
	status_label.text = tr("UI_CANDIDATE_START_REJECTED")
	FocusCoordinator.recover(self, bow_button)


func refresh_localization() -> void:
	_apply_localization()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_localization()


func _on_preset_pressed(index: int) -> void:
	if index < 0 or index >= PRESETS.size():
		return
	_showing_rejection = false
	status_label.text = ""
	candidate_requested.emit((PRESETS[index] as Dictionary).duplicate(true))


func _apply_localization() -> void:
	title_label.text = tr("UI_CANDIDATE_LAB_TITLE")
	warning_label.text = tr("UI_CANDIDATE_LAB_WARNING")
	var preset_buttons: Array[Button] = [bow_button, rift_button, accelerate_button]
	for index: int in range(preset_buttons.size()):
		var keys: Array = PRESET_LOCALIZATION[index]
		preset_buttons[index].text = tr("UI_CANDIDATE_PRESET_FMT") % [
			tr(str(keys[0])),
			tr(str(keys[1])),
			tr(str(keys[2])),
			tr(str(keys[3])),
		]
	back_button.text = tr("UI_BACK")
	status_label.text = tr("UI_CANDIDATE_START_REJECTED") if _showing_rejection else ""
