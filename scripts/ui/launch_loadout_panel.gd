class_name LaunchLoadoutPanel
extends Control

signal launch_requested(config: Dictionary)

const ContentRegistryScript := preload("res://scripts/content/content_registry.gd")
const RunLoadoutCatalogScript := preload("res://scripts/application/run_loadout_catalog.gd")

const BASE_PACK_PATH := "res://data/content_packs/base/pack.json"
const GAME_VERSION := "0.4.0-dev"
const LAUNCH_MILESTONE := &"LAUNCH"

@onready var title_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/TitleLabel
@onready var warning_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/WarningLabel
@onready var character_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/CharacterLabel
@onready var character_option: OptionButton = $SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/CharacterOption
@onready var weapon_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/WeaponLabel
@onready var weapon_option: OptionButton = $SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/WeaponOption
@onready var time_pair_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/TimePairLabel
@onready var time_pair_option: OptionButton = $SafeArea/Center/PanelRoot/Margin/Layout/SelectorGrid/TimePairOption
@onready var description_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/DescriptionLabel
@onready var summary_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/SummaryLabel
@onready var start_button: Button = $SafeArea/Center/PanelRoot/Margin/Layout/ButtonRow/StartButton
@onready var back_button: Button = $SafeArea/Center/PanelRoot/Margin/Layout/ButtonRow/BackButton
@onready var status_label: Label = $SafeArea/Center/PanelRoot/Margin/Layout/StatusLabel

var _restore_focus: Control
var _focus_controls: Array[Control] = []
var _catalog: RefCounted
var _characters: Array[Dictionary] = []
var _weapons: Array[Dictionary] = []
var _time_pairs: Array[Dictionary] = []
var _catalog_ready := false
var _showing_rejection := false


func configure(restore_focus: Control = null, catalog: RefCounted = null) -> void:
	_restore_focus = restore_focus
	if catalog != null:
		_catalog = catalog
		if is_node_ready():
			_install_catalog(catalog)
			_apply_localization()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_focus_controls = [
		character_option,
		weapon_option,
		time_pair_option,
		start_button,
		back_button,
	]
	for option: OptionButton in [character_option, weapon_option, time_pair_option]:
		option.item_selected.connect(_on_selection_changed)
		option.gui_input.connect(_on_option_gui_input.bind(option))
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(close_panel)
	FocusCoordinator.link_ring(_focus_controls, false)
	_ensure_catalog()
	_apply_localization()


func open_panel(restore_focus: Control = null) -> void:
	if restore_focus != null:
		_restore_focus = restore_focus
	_showing_rejection = false
	status_label.text = ""
	visible = true
	FocusCoordinator.link_ring(_focus_controls, false)
	FocusCoordinator.open_scope(self, character_option)


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
	FocusCoordinator.recover(self, character_option)


func refresh_localization() -> void:
	_apply_localization()


func refresh_selection() -> void:
	_showing_rejection = false
	status_label.text = ""
	_update_selection_text()


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
	_update_selection_text()


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
	if not _catalog_ready:
		show_start_rejected()
		return
	var character_id := _selected_id(character_option)
	var weapon_id := _selected_id(weapon_option)
	var time_pair_id := _selected_id(time_pair_option)
	var time_pair := _entry_by_id(_time_pairs, time_pair_id)
	var ability_ids_value: Variant = time_pair.get("ability_ids", [])
	if (
		character_id.is_empty()
		or weapon_id.is_empty()
		or time_pair_id.is_empty()
		or not ability_ids_value is Array
		or (ability_ids_value as Array).size() != 2
	):
		show_start_rejected()
		return
	_showing_rejection = false
	status_label.text = ""
	launch_requested.emit({
		"schema_version": 1,
		"milestone": "LAUNCH",
		"character_id": character_id,
		"weapon_id": weapon_id,
		"enabled_time_skills": (ability_ids_value as Array).duplicate(),
		"difficulty": "normal",
	})


func _ensure_catalog() -> void:
	if _catalog != null:
		_install_catalog(_catalog)
		return
	var registry := ContentRegistryScript.new()
	var report = registry.load_packs(
		[{"path": BASE_PACK_PATH, "required": true}],
		GAME_VERSION,
		&"M1"
	)
	if report.has_blocking_errors():
		_clear_catalog()
		return
	var catalog := RunLoadoutCatalogScript.new()
	if not catalog.configure(registry, LAUNCH_MILESTONE):
		_clear_catalog()
		return
	_catalog = catalog
	_install_catalog(catalog)


func _install_catalog(catalog: RefCounted) -> void:
	_clear_catalog()
	if (
		catalog == null
		or not catalog.has_method("characters")
		or not catalog.has_method("weapons")
		or not catalog.has_method("time_pairs")
		or not catalog.has_method("is_ready")
	):
		return
	if not bool(catalog.call("is_ready")):
		return
	_characters = _dictionary_array(catalog.call("characters"))
	_weapons = _dictionary_array(catalog.call("weapons"))
	_time_pairs = _dictionary_array(catalog.call("time_pairs"))
	_catalog_ready = (
		_characters.size() == 5
		and _weapons.size() == 5
		and _time_pairs.size() == 6
	)


func _clear_catalog() -> void:
	_characters.clear()
	_weapons.clear()
	_time_pairs.clear()
	_catalog_ready = false


func _apply_localization() -> void:
	var character_id := _selected_id(character_option)
	var weapon_id := _selected_id(weapon_option)
	var time_pair_id := _selected_id(time_pair_option)
	title_label.text = tr("UI_LAUNCH_LOADOUT_TITLE")
	warning_label.text = tr("UI_LAUNCH_LOADOUT_WARNING")
	character_label.text = tr("UI_LAUNCH_CHARACTER_LABEL")
	weapon_label.text = tr("UI_LAUNCH_WEAPON_LABEL")
	time_pair_label.text = tr("UI_LAUNCH_TIME_PAIR_LABEL")
	start_button.text = tr("UI_LAUNCH_START")
	back_button.text = tr("UI_BACK")
	_populate_definition_option(character_option, _characters, character_id)
	_populate_definition_option(weapon_option, _weapons, weapon_id)
	_populate_time_pair_option(time_pair_option, _time_pairs, time_pair_id)
	start_button.disabled = not _catalog_ready
	status_label.text = tr("UI_LAUNCH_START_REJECTED") if _showing_rejection else ""
	_update_selection_text()


func _populate_definition_option(option: OptionButton, entries: Array[Dictionary], selected_id: String) -> void:
	option.clear()
	for entry: Dictionary in entries:
		var item_index := option.item_count
		option.add_item(tr(str(entry.get("name_key", ""))))
		option.set_item_metadata(item_index, str(entry.get("id", "")))
	_select_id(option, selected_id)


func _populate_time_pair_option(option: OptionButton, entries: Array[Dictionary], selected_id: String) -> void:
	option.clear()
	for entry: Dictionary in entries:
		var name_keys_value: Variant = entry.get("name_keys", [])
		if not name_keys_value is Array or (name_keys_value as Array).size() != 2:
			continue
		var name_keys: Array = name_keys_value
		var item_index := option.item_count
		option.add_item(tr("UI_TIME_PAIR_FMT") % [
			tr(str(name_keys[0])),
			tr(str(name_keys[1])),
		])
		option.set_item_metadata(item_index, str(entry.get("id", "")))
	_select_id(option, selected_id)


func _select_id(option: OptionButton, selected_id: String) -> void:
	if option.item_count <= 0:
		return
	for index: int in range(option.item_count):
		if str(option.get_item_metadata(index)) == selected_id:
			option.select(index)
			return
	option.select(0)


func _update_selection_text() -> void:
	if (
		character_option.item_count <= 0
		or weapon_option.item_count <= 0
		or time_pair_option.item_count <= 0
	):
		description_label.text = ""
		summary_label.text = ""
		return
	var character := _entry_by_id(_characters, _selected_id(character_option))
	description_label.text = tr(str(character.get("description_key", "")))
	var identity_text := "%s / %s" % [
		character_option.get_item_text(character_option.selected),
		weapon_option.get_item_text(weapon_option.selected),
	]
	summary_label.text = tr("UI_LAUNCH_SELECTION_FMT") % [
		identity_text,
		time_pair_option.get_item_text(time_pair_option.selected),
	]


func _selected_id(option: OptionButton) -> String:
	if option == null or option.selected < 0 or option.selected >= option.item_count:
		return ""
	return str(option.get_item_metadata(option.selected))


func _entry_by_id(entries: Array[Dictionary], entry_id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if str(entry.get("id", "")) == entry_id:
			return entry.duplicate(true)
	return {}


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for entry_value: Variant in value:
		if not entry_value is Dictionary:
			return []
		result.append((entry_value as Dictionary).duplicate(true))
	return result
