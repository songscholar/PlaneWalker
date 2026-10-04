class_name HubFlowCoordinator
extends Node

signal launch_requested(config: Dictionary)
signal tutorial_requested
signal settings_requested(kind: String, restore_focus: Control)

const Facade := preload("res://scripts/hub/hub_runtime_facade.gd")
const SceneHost := preload("res://scripts/hub/hub_scene_host.gd")
const PanelViewScript := preload("res://scripts/ui/hub_panel_view.gd")
const Result := preload("res://scripts/application/command_result.gd")

var _facade: RefCounted
var _registry: RefCounted
var _scene_host: Node2D
var _scene_layer: CanvasLayer
var _layer: CanvasLayer
var _panel: Control
var _toolbar: Control
var _district: OptionButton
var _currency: Label
var _title: Label
var _status: Label
var _functions: HBoxContainer
var _settings: MenuButton
var _active := false
var _ui_epoch := 0
var _state: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scene_host = SceneHost.new()
	_scene_host.name = "HubSceneHost"
	_scene_layer = CanvasLayer.new()
	_scene_layer.name = "HubWorldLayer"
	_scene_layer.layer = 1
	add_child(_scene_layer)
	_scene_layer.add_child(_scene_host)
	_scene_host.function_requested.connect(_on_scene_function)
	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)
	_build_toolbar()
	_panel = PanelViewScript.new()
	_panel.name = "HubPanelView"
	_layer.add_child(_panel)
	_panel.command_requested.connect(submit_command)
	_panel.close_requested.connect(func(_revision: int): close_panel())
	_panel.tutorial_requested.connect(func(): tutorial_requested.emit())
	get_viewport().size_changed.connect(_fit_scene)
	_fit_scene()
	hide_hub()


func configure(registry: RefCounted, service: RefCounted) -> Dictionary:
	if not is_node_ready():
		return {"ok": false, "code": &"NOT_CONFIGURED", "context": {}}
	var candidate := Facade.new()
	var configured: Dictionary = candidate.configure(registry, service)
	if not configured.ok:
		return configured
	_registry = registry
	_facade = candidate
	return refresh()


func view_state() -> Dictionary:
	return _facade.view_state() if _facade != null else {}


func scene_host() -> Node2D:
	return _scene_host


func panel_view() -> Control:
	return _panel


func is_hub_visible() -> bool:
	return _active


func show_hub() -> Dictionary:
	if _facade == null:
		return {"ok": false, "code": &"NOT_CONFIGURED", "context": {}}
	_active = true
	_scene_host.visible = true
	_scene_layer.visible = true
	_layer.visible = true
	return refresh()


func hide_hub() -> void:
	_active = false
	_ui_epoch += 1
	if is_instance_valid(_panel):
		_panel.close_panel()
	if is_instance_valid(_scene_host):
		_scene_host.set_interaction_enabled(false)
		_scene_host.visible = false
	if is_instance_valid(_layer):
		_layer.visible = false
	if is_instance_valid(_scene_layer):
		_scene_layer.visible = false
	FocusCoordinator.close_scope(self)


func refresh() -> Dictionary:
	if _facade == null:
		return {"ok": false, "code": &"NOT_CONFIGURED", "context": {}}
	_state = _facade.view_state()
	if _state.is_empty():
		return {"ok": false, "code": &"CONTENT_UNAVAILABLE", "context": {}}
	var definition: Dictionary = {}
	for row: Dictionary in _registry.get_catalog_entries(&"hub_district", &"LAUNCH"):
		if row.id == _state.district_id:
			definition = row
	var installed = _scene_host.install_district(definition)
	if not installed.ok:
		return installed.to_dictionary()
	_ui_epoch += 1
	_refresh_toolbar()
	if _active and not str(_state.panel_id).is_empty():
		var rendered = _panel.render(_state)
		if not rendered.ok:
			return rendered.to_dictionary()
	else:
		_panel.close_panel()
	_scene_host.set_interaction_enabled(_active and not _panel.visible)
	return {"ok": true, "code": &"OK", "context": {}}


func travel(id: String) -> Dictionary:
	if not _active or _facade == null or get_tree().paused:
		return {"ok": false, "code": &"INVALID_PHASE", "context": {}}
	if not str(_state.panel_id).is_empty():
		var closed := close_panel()
		if not closed.ok:
			return closed
	if _state.district_id == id:
		return {"ok": true, "code": &"OK", "context": {}}
	var traveled: Dictionary = _facade.travel(id, int(_state.revision), int(_state.epoch))
	if traveled.ok:
		refresh()
	return traveled


func open_function(id: String) -> Dictionary:
	return submit_command({"epoch": _state.get("epoch", -1), "function_id": id, "operation": "open", "payload": {}}, int(_state.get("revision", -1)))


func close_panel() -> Dictionary:
	if not _active or str(_state.get("panel_id", "")).is_empty():
		return {"ok": false, "code": &"INVALID_PHASE", "context": {}}
	return submit_command({"epoch": _state.epoch, "function_id": _state.function_id, "operation": "back", "payload": {}}, int(_state.revision))


func submit_command(command: Dictionary, revision: int) -> Dictionary:
	if not _active or _facade == null or get_tree().paused:
		return {"ok": false, "code": &"INVALID_PHASE", "context": {}}
	var result: Dictionary = _facade.command(command, revision)
	if not result.ok:
		refresh()
		if _panel.visible:
			_panel.show_rejection("UI_HUB_SAVE_RETRY")
		else:
			_status.text = tr("UI_HUB_SAVE_RETRY")
		return result
	GameState.refresh_profile_state()
	refresh()
	if command.operation == "launch":
		launch_requested.emit(result.context.run_config.duplicate(true))
	return result


func show_launch_rejection() -> void:
	if _panel.visible:
		_panel.show_rejection("UI_LAUNCH_START_REJECTED")


func _on_scene_function(id: String, epoch: int) -> void:
	if not _active or epoch != int(_scene_host.snapshot().epoch):
		return
	open_function(id)


func _build_toolbar() -> void:
	_toolbar = Control.new()
	_toolbar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_toolbar)
	var header := VBoxContainer.new()
	header.name = "Header"
	_toolbar.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 12
	header.offset_right = -12
	header.offset_top = 6
	var top := HBoxContainer.new()
	header.add_child(top)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 14)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_district = OptionButton.new()
	_district.name = "DistrictSelector"
	_district.custom_minimum_size = Vector2(152, 26)
	_district.add_theme_font_size_override("font_size", 11)
	top.add_child(_district)
	_settings = MenuButton.new()
	_settings.text = "..."
	_settings.tooltip_text = tr("UI_ACCESSIBILITY_SETTINGS")
	_settings.custom_minimum_size = Vector2(28, 26)
	top.add_child(_settings)
	_settings.get_popup().id_pressed.connect(_settings_selected)
	_currency = Label.new()
	_currency.add_theme_font_size_override("font_size", 11)
	header.add_child(_currency)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_status)
	_functions = HBoxContainer.new()
	_functions.name = "Destinations"
	_functions.alignment = BoxContainer.ALIGNMENT_CENTER
	_toolbar.add_child(_functions)
	_functions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_functions.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_functions.offset_left = 12
	_functions.offset_right = -12
	_functions.offset_top = -34
	_functions.offset_bottom = -6


func _refresh_toolbar() -> void:
	_title.text = tr("UI_TITLE")
	_currency.text = tr("UI_HUB_CURRENCIES_FMT") % [int(_state.currencies.chronos_shards), int(_state.currencies.existential_imprints)]
	_status.text = ""
	_district.clear()
	for row: Dictionary in _state.districts:
		_district.add_item(tr(str(row.name_key)))
		var index := _district.item_count - 1
		_district.set_item_metadata(index, row.id)
		_district.set_item_disabled(index, not row.available)
		if row.current:
			_district.select(index)
	for callback: Dictionary in _district.item_selected.get_connections():
		_district.item_selected.disconnect(callback.callable)
	_district.item_selected.connect(_district_selected.bind(_ui_epoch))
	for child: Node in _functions.get_children():
		_functions.remove_child(child)
		child.queue_free()
	for row: Dictionary in _state.functions:
		if row.district_id != _state.district_id:
			continue
		var button := Button.new()
		button.text = tr(str(row.name_key))
		button.custom_minimum_size = Vector2(0, 28)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 11)
		button.disabled = not row.available
		button.pressed.connect(_toolbar_function.bind(str(row.id), _ui_epoch))
		_functions.add_child(button)
	var popup := _settings.get_popup()
	popup.clear()
	popup.add_item(tr("UI_ACCESSIBILITY_SETTINGS"), 0)
	popup.add_item(tr("UI_INPUT_REMAP"), 1)
	popup.add_item(tr("UI_LANG_EN") if str(TranslationServer.get_locale()) == "zh_CN" else tr("UI_LANG_ZH"), 2)
	FocusCoordinator.link_ring(_toolbar_controls(), false)
	var runtimes := get_tree().get_nodes_in_group("accessibility_runtime")
	if not runtimes.is_empty():
		runtimes[0].apply_to_tree(_toolbar)
	if FocusCoordinator.active_scope() == self:
		FocusCoordinator.recover(self, _district)


func _toolbar_controls() -> Array[Control]:
	var controls: Array[Control] = [_district, _settings]
	for child: Node in _functions.get_children():
		if not child.disabled:
			controls.append(child)
	return controls


func _district_selected(index: int, epoch: int) -> void:
	if not _active or epoch != _ui_epoch or index < 0 or index >= _district.item_count or _district.is_item_disabled(index):
		return
	travel(str(_district.get_item_metadata(index)))


func _toolbar_function(id: String, epoch: int) -> void:
	if _active and epoch == _ui_epoch:
		open_function(id)


func _settings_selected(id: int) -> void:
	if _active:
		settings_requested.emit(["accessibility", "input", "language"][id], _settings)


func _fit_scene() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var factor := minf(viewport.x / 640.0, viewport.y / 360.0)
	_scene_host.scale = Vector2.ONE * factor
	_scene_host.position = (viewport - Vector2(640, 360) * factor) / 2


func _unhandled_input(event: InputEvent) -> void:
	if not _active or _panel.visible:
		return
	var controller_menu: bool = event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK
	var cancel: bool = event.is_action_pressed("ui_cancel") or event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B
	if (event.is_action_pressed("ui_focus_next") or controller_menu) and FocusCoordinator.active_scope() == null:
		FocusCoordinator.open_scope(self, _district)
		get_viewport().set_input_as_handled()
	elif (cancel or controller_menu) and FocusCoordinator.active_scope() == self:
		FocusCoordinator.close_scope(self)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not _state.is_empty():
		_refresh_toolbar()
		_scene_host.refresh_localization()
