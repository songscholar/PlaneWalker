class_name LaunchLoadoutPanel
extends Control

signal launch_requested(config: Dictionary)

const WEAPONS: Array[String] = ["sword", "bow", "gun", "staff", "gauntlets"]
const WEAPON_LOCALIZATION_KEYS: Array[String] = [
	"WEAPON_SWORD_NAME",
	"WEAPON_BOW_NAME",
	"WEAPON_GUN_NAME",
	"WEAPON_STAFF_NAME",
	"WEAPON_GAUNTLETS_NAME",
]
const TIME_PAIRS: Array[Array] = [
	["stop", "rewind"],
	["stop", "rift"],
	["stop", "accelerate"],
	["rewind", "rift"],
	["rewind", "accelerate"],
	["rift", "accelerate"],
]
const TIME_LOCALIZATION_KEYS := {
	"stop": "TIME_ABILITY_STOP_NAME",
	"rewind": "TIME_ABILITY_REWIND_NAME",
	"rift": "TIME_ABILITY_RIFT_NAME",
	"accelerate": "TIME_ABILITY_ACCELERATE_NAME",
}

@onready var title_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/TitleLabel
@onready var warning_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/WarningLabel
@onready var weapon_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/WeaponLabel
@onready var weapon_option: OptionButton = $SafeArea/Center/PanelRoot/Margin/Layout/WeaponOption
@onready var time_pair_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/TimePairLabel
@onready var time_pair_option: OptionButton = $SafeArea/Center/PanelRoot/Margin/Layout/TimePairOption
@onready var summary_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/SummaryLabel
@onready var start_button: Button = $SafeArea/Center/PanelRoot/Margin/Layout/StartButton
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
	_focus_controls = [weapon_option, time_pair_option, start_button, back_button]
	weapon_option.item_selected.connect(_on_selection_changed)
	time_pair_option.item_selected.connect(_on_selection_changed)
	weapon_option.gui_input.connect(_on_option_gui_input.bind(weapon_option))
	time_pair_option.gui_input.connect(_on_option_gui_input.bind(time_pair_option))
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(close_panel)
	FocusCoordinator.link_ring(_focus_controls, false)
	_apply_localization()


func open_panel(restore_focus: Control = null) -> void:
	if restore_focus != null:
		_restore_focus = restore_focus
	_showing_rejection = false
	status_label.text = ""
	visible = true
	FocusCoordinator.link_ring(_focus_controls, false)
	FocusCoordinator.open_scope(self, weapon_option)


func close_panel() -> void:
	if not visible:
		return
	FocusCoordinator.close_scope(self)
	visible = false
	_showing_rejection = false
	status_label.text = ""
	call_deferred("_restore_configured_focus")


func show_start_rejected() -> void:
	if not visible:
		return
	_showing_rejection = true
	status_label.text = tr("UI_LAUNCH_START_REJECTED")
	FocusCoordinator.recover(self, weapon_option)


func refresh_localization() -> void:
	_apply_localization()


func refresh_selection() -> void:
	_update_summary()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
	elif event.is_action_pressed("interact") and get_viewport().gui_get_focus_owner() == start_button:
		get_viewport().set_input_as_handled()
		_on_start_pressed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_apply_localization()


func _on_selection_changed(_index: int) -> void:
	_showing_rejection = false
	status_label.text = ""
	_update_summary()


func _on_option_gui_input(event: InputEvent, option: OptionButton) -> void:
	var direction := 0
	if event.is_action_pressed("ui_left"):
		direction = -1
	elif event.is_action_pressed("ui_right"):
		direction = 1
	if direction == 0 or option.item_count <= 0:
		return
	option.select(posmod(option.selected + direction, option.item_count))
	_on_selection_changed(option.selected)
	option.accept_event()


func _restore_configured_focus() -> void:
	if _restore_focus == null or not is_instance_valid(_restore_focus):
		return
	if _restore_focus.is_inside_tree() and _restore_focus.is_visible_in_tree():
		_restore_focus.grab_focus()


func _on_start_pressed() -> void:
	var weapon_index := weapon_option.selected
	var pair_index := time_pair_option.selected
	if weapon_index < 0 or weapon_index >= WEAPONS.size() or pair_index < 0 or pair_index >= TIME_PAIRS.size():
		show_start_rejected()
		return
	_showing_rejection = false
	status_label.text = ""
	launch_requested.emit({
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": "wanderer",
		"weapon_id": WEAPONS[weapon_index],
		"enabled_time_skills": (TIME_PAIRS[pair_index] as Array).duplicate(true),
		"difficulty": "normal",
	})


func _apply_localization() -> void:
	var weapon_index := maxi(0, weapon_option.selected)
	var pair_index := maxi(0, time_pair_option.selected)
	title_label.text = tr("UI_LAUNCH_LOADOUT_TITLE")
	warning_label.text = tr("UI_LAUNCH_LOADOUT_WARNING")
	weapon_label.text = tr("UI_LAUNCH_WEAPON_LABEL")
	time_pair_label.text = tr("UI_LAUNCH_TIME_PAIR_LABEL")
	start_button.text = tr("UI_LAUNCH_START")
	back_button.text = tr("UI_BACK")
	weapon_option.clear()
	for key: String in WEAPON_LOCALIZATION_KEYS:
		weapon_option.add_item(tr(key))
	time_pair_option.clear()
	for pair: Array in TIME_PAIRS:
		time_pair_option.add_item(tr("UI_TIME_PAIR_FMT") % [
			tr(str(TIME_LOCALIZATION_KEYS[str(pair[0])])),
			tr(str(TIME_LOCALIZATION_KEYS[str(pair[1])])),
		])
	weapon_option.select(clampi(weapon_index, 0, WEAPONS.size() - 1))
	time_pair_option.select(clampi(pair_index, 0, TIME_PAIRS.size() - 1))
	status_label.text = tr("UI_LAUNCH_START_REJECTED") if _showing_rejection else ""
	_update_summary()


func _update_summary() -> void:
	if weapon_option.selected < 0 or time_pair_option.selected < 0:
		summary_label.text = ""
		return
	summary_label.text = tr("UI_LAUNCH_SELECTION_FMT") % [
		weapon_option.get_item_text(weapon_option.selected),
		time_pair_option.get_item_text(time_pair_option.selected),
	]
