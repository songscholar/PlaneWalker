extends "res://scripts/ui/dungeon_panel_view.gd"

const Art := preload("res://scripts/ui/style/ui_artwork.gd")
var _transport: VBoxContainer
var _picture: TextureRect
var _library: Node
var _selector: OptionButton
var _speed: OptionButton
var _timeline: HSlider
var _time_label: Label
var _play: Button
var _room_label: Label
var _import: FileDialog
var _delete: ConfirmationDialog
var _delete_id := ""
var _signature := ""
var _revision := 0


func _build_layout() -> void:
	super._build_layout()
	_transport = VBoxContainer.new()
	_transport.name = "ReplayTransport"
	_transport.add_theme_constant_override("separation", 3)
	var layout := scroll.get_parent()
	layout.add_child(_transport)
	layout.move_child(_transport, footer.get_index())
	Art.button_icon(back_button, Art.icon(&"controls", &"back"))


func _clear_rows() -> void:
	if is_instance_valid(_transport):
		for child: Node in _transport.get_children():
			_transport.remove_child(child)
			child.queue_free()
	_picture = null
	super._clear_rows()


func _ready() -> void:
	super._ready()
	panel_root.minimum_size_changed.connect(func(): _fit_panel.call_deferred())
	_import = FileDialog.new()
	_import.name = "ReplayImportDialog"
	_import.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import.access = FileDialog.ACCESS_FILESYSTEM
	_import.filters = PackedStringArray(["*.json ; Plane Walker Replay"])
	_import.title = tr("UI_REPLAY_IMPORT")
	add_child(_import)
	_import.file_selected.connect(_import_selected)
	_import.canceled.connect(_refresh.bind(true))
	_import.window_input.connect(_dialog_input.bind(_import))
	_delete = ConfirmationDialog.new()
	_delete.name = "ReplayDeleteDialog"
	_delete.dialog_text = tr("UI_REPLAY_REMOVE_CONFIRM")
	add_child(_delete)
	_delete.confirmed.connect(_remove_confirmed)
	_delete.canceled.connect(_remove_canceled)
	_delete.window_input.connect(_dialog_input.bind(_delete))


func configure(library: Node) -> Dictionary:
	if _library != null or not is_node_ready() or not is_instance_valid(library) or not library.has_method("current_world"):
		return {"ok": false, "code": &"REPLAY_VIEW_TARGET_INVALID", "context": {}}
	_library = library
	_library.changed.connect(_refresh)
	_library.rejected.connect(_show_failure)
	return {"ok": true, "code": &"OK", "context": {}}


func open() -> Dictionary:
	if not is_instance_valid(_library):
		return {"ok": false, "code": &"REPLAY_VIEW_TARGET_INVALID", "context": {}}
	var loaded: Dictionary = _library.reload()
	if not loaded.ok:
		return loaded
	_signature = ""
	return _refresh(true)


func _validate(value: Dictionary):
	if value.size() != 4 or value.get("run_id") != "replay-library" or typeof(value.get("revision")) != TYPE_INT or not value.get("entries") is Array or not value.get("selection") is Dictionary:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	return CommandResultScript.success(int(value.revision))


func _refresh(force: bool = false) -> Dictionary:
	if not is_instance_valid(_library) or not force and not visible:
		return {"ok": true}
	var entries: Array = _library.rows()
	var selection: Dictionary = _library.snapshot()
	var signature := JSON.stringify([entries, selection.selected_id])
	if not force and visible and signature == _signature:
		_state.selection = selection.duplicate(true)
		_submitted = false
		for action: Control in _actions:
			(action as Button).disabled = not bool(action.get_meta("available", false))
		_update_timeline()
		return {"ok": true}
	_signature = signature
	_revision += 1
	var result = render({"run_id": "replay-library", "revision": _revision, "entries": entries, "selection": selection})
	return {"ok": result.ok, "code": result.code, "context": result.context.duplicate(true)}


func _render_state() -> void:
	_selector = null
	_speed = null
	_timeline = null
	_time_label = null
	_play = null
	_room_label = null
	title_label.text = tr("UI_REPLAY_LIBRARY")
	summary_label.text = tr("UI_REPLAY_COUNT_FMT") % [int(_state.entries.size()), 40 if _library.has_method("attach_stream_store") else 20]
	if str(_state.selection.selected_id).is_empty():
		var import_tool := _tool(_transport, "import", "", "UI_REPLAY_IMPORT", _choose_import)
		import_tool.text = tr("UI_REPLAY_IMPORT")
	if _state.entries.is_empty():
		_add_text(tr("UI_REPLAY_EMPTY"), "EmptyLibrary")
		return
	_selector = OptionButton.new()
	_selector.name = "RecordingSelector"
	_selector.custom_minimum_size = Vector2(0, 29)
	_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selector.add_theme_font_size_override("font_size", 12)
	_selector.add_theme_constant_override("icon_max_width", 20)
	_selector.expand_icon = true
	_selector.fit_to_longest_item = false
	_selector.add_item(tr("UI_REPLAY_SELECT"))
	for row: Dictionary in _state.entries:
		var status := " / " + tr("UI_REPLAY_STATUS_" + str(row.status)) if row.has("status") else ""
		_selector.add_item("%s / %s / %.2fs / #%d%s" % [tr("CHARACTER_%s_NAME" % str(row.character_id).to_upper()), tr("WEAPON_%s_NAME" % str(row.weapon_id).to_upper()), float(int(row.last_frame) - int(row.first_frame)) / 60.0, int(row.seed), status])
		_selector.set_item_metadata(_selector.item_count - 1, row.id)
		_selector.set_item_icon(_selector.item_count - 1, Art.actor(str(row.character_id)))
		if row.id == _state.selection.selected_id:
			_selector.select(_selector.item_count - 1)
	_selector.item_selected.connect(_select_recording.bind(_epoch))
	_selector.gui_input.connect(_selector_input.bind(_selector, _epoch))
	var selection := HBoxContainer.new()
	selection.name = "RecordingSelection"
	selection.add_theme_constant_override("separation", 8)
	rows_container.add_child(selection)
	for row: Dictionary in _state.entries:
		if row.id == _state.selection.selected_id:
			selection.add_child(Art.image(Art.actor(str(row.character_id)), 32, "RecordingArtwork"))
	selection.add_child(_selector)
	if str(_state.selection.selected_id).is_empty():
		for row: Dictionary in _state.entries:
			_recording_row(row)
		return
	var world: SubViewport = _library.current_world()
	if not is_instance_valid(world):
		return
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var view := TextureRect.new()
	view.name = "ReplayPicture"
	view.texture = world.get_texture()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.custom_minimum_size = Vector2(0, 180)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_container.add_child(view)
	_picture = view
	_fit_panel()
	_timeline = HSlider.new()
	_timeline.name = "ReplayTimeline"
	_timeline.min_value = 0
	_timeline.max_value = maxi(0, int(_state.selection.frame_count) - 1)
	_timeline.step = 1
	_timeline.custom_minimum_size = Vector2(0, 24)
	_timeline.focus_mode = Control.FOCUS_ALL
	_timeline.value_changed.connect(_seek.bind(_epoch))
	_transport.add_child(_timeline)
	var tools := HBoxContainer.new()
	tools.name = "ReplayControls"
	_transport.add_child(tools)
	_play = _tool(tools, "play", ">", "UI_REPLAY_PLAY", _toggle_play)
	_speed = OptionButton.new()
	_speed.name = "PlaybackSpeed"
	_speed.custom_minimum_size = Vector2(64, 29)
	_speed.tooltip_text = tr("UI_REPLAY_SPEED")
	for speed: float in [0.5, 1.0, 2.0]:
		_speed.add_item("%sx" % str(speed))
		_speed.set_item_metadata(_speed.item_count - 1, speed)
	_speed.item_selected.connect(_set_speed.bind(_epoch))
	_speed.gui_input.connect(_selector_input.bind(_speed, _epoch))
	tools.add_child(_speed)
	_tool(tools, "import", tr("UI_REPLAY_IMPORT"), "UI_REPLAY_IMPORT", _choose_import)
	_tool(tools, "export", tr("UI_REPLAY_EXPORT"), "UI_REPLAY_EXPORT", _export_recording)
	_tool(tools, "remove", "x", "UI_REPLAY_REMOVE", _choose_remove)
	_time_label = _label("", "ReplayTime", 11)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tools.add_child(_time_label)
	if _state.selection.has("bookmarks"):
		var transitions := HBoxContainer.new()
		_transport.add_child(transitions)
		_tool(transitions, "previous_room", "<", "UI_REPLAY_PREVIOUS_ROOM", func(): _library.seek_transition(-1))
		_tool(transitions, "next_room", ">", "UI_REPLAY_NEXT_ROOM", func(): _library.seek_transition(1))
		_room_label = _label("", "ReplayRoom", 11)
		transitions.add_child(_room_label)
	_update_timeline()


func _tool(parent: Node, id: String, _text: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = ""
	var ids := {"play": "play", "import": "import", "export": "export", "remove": "delete", "previous_room": "back", "next_room": "next"}
	Art.button_icon(button, Art.icon(&"controls", StringName(ids.get(id, "play"))))
	button.tooltip_text = tr(tooltip)
	button.custom_minimum_size = Vector2(32, 29)
	button.add_theme_font_size_override("font_size", 12)
	button.set_meta("action_id", id)
	button.set_meta("available", true)
	button.pressed.connect(_activate_action.bind(button, callback, _epoch))
	parent.add_child(button)
	_actions.append(button)
	return button


func _update_timeline() -> void:
	if not is_instance_valid(_timeline):
		return
	var state: Dictionary = _library.snapshot()
	_timeline.set_value_no_signal(float(state.cursor))
	Art.button_icon(_play, Art.icon(&"controls", &"pause" if state.playing else &"play"))
	_play.tooltip_text = tr("UI_REPLAY_PAUSE" if state.playing else "UI_REPLAY_PLAY")
	for index: int in range(_speed.item_count):
		if _speed.get_item_metadata(index) == state.speed:
			_speed.select(index)
	_time_label.text = "%.2fs / %.2fs" % [float(state.cursor) / 60.0, float(maxi(0, int(state.frame_count) - 1)) / 60.0]
	if is_instance_valid(_room_label):
		var world: SubViewport = _library.current_world()
		if not is_instance_valid(world):
			return
		var observation: Dictionary = world.observation()
		var binding: Dictionary = observation.get("scene", {}).get("binding", {})
		_room_label.text = tr("FLOOR_%s_NAME" % str(binding.get("floor_id", "")).trim_prefix("floor_").to_upper()) if not binding.is_empty() else ""


func _recording_row(row: Dictionary, selectable: bool = true) -> void:
	var line := HBoxContainer.new()
	line.name = "RecordingRow"
	line.add_theme_constant_override("separation", 8)
	rows_container.add_child(line)
	line.add_child(Art.image(Art.actor(str(row.character_id)), 32, "RecordingArtwork"))
	line.add_child(Art.image(Art.icon(&"weapons", StringName(row.weapon_id)), 24, "RecordingWeapon"))
	var details := "%s / %s\n%.2fs  /  #%d" % [tr("CHARACTER_%s_NAME" % str(row.character_id).to_upper()), tr("WEAPON_%s_NAME" % str(row.weapon_id).to_upper()), float(int(row.last_frame) - int(row.first_frame)) / 60.0, int(row.seed)]
	if row.has("status"):
		details += "  /  " + tr("UI_REPLAY_STATUS_" + str(row.status))
	line.add_child(_label(details, "RecordingFacts", 11))
	if selectable:
		_tool(line, "recording:" + str(row.id), "", "UI_REPLAY_PLAY", func():
			var result: Dictionary = _library.select(str(row.id))
			if not result.ok:
				_show_failure(result.code))


func _fit_panel() -> void:
	super._fit_panel()
	if is_instance_valid(_picture):
		_picture.custom_minimum_size.y = 100 if panel_root.size.y < 400 else 220


func apply_accessibility_settings(_settings: Dictionary) -> void:
	_fit_panel.call_deferred()


func _focus_controls() -> Array[Control]:
	var controls: Array[Control] = super._focus_controls()
	for control: Control in [_selector, _timeline, _speed]:
		if is_instance_valid(control):
			controls.insert(controls.size() - 1, control)
	return controls


func _selector_input(event: InputEvent, option: OptionButton, source_epoch: int) -> void:
	if source_epoch != _epoch or not visible or option.disabled:
		return
	var direction := 1 if event.is_action_pressed("ui_right") else (-1 if event.is_action_pressed("ui_left") else 0)
	if direction == 0:
		return
	var index := posmod(option.selected + direction, option.item_count)
	option.select(index)
	option.accept_event()
	option.item_selected.emit(index)


func _select_recording(index: int, source_epoch: int) -> void:
	if source_epoch != _epoch or not visible or index < 0 or index >= _selector.item_count:
		return
	if index == 0:
		_library.close_selection()
		_refresh(true)
		return
	var result: Dictionary = _library.select(str(_selector.get_item_metadata(index)))
	if not result.ok:
		_show_failure(result.code)


func _seek(value: float, source_epoch: int) -> void:
	if source_epoch == _epoch and visible:
		var result: Dictionary = _library.seek(int(value))
		if not result.ok:
			_show_failure(result.code)


func _toggle_play() -> void:
	_library.set_playing(not _library.snapshot().playing)


func _set_speed(index: int, source_epoch: int) -> void:
	if source_epoch == _epoch and visible and index >= 0 and index < _speed.item_count:
		_library.set_speed(float(_speed.get_item_metadata(index)))


func _choose_import() -> void:
	_library.set_playing(false)
	_import.popup_centered(Vector2i(560, 300))


func _import_selected(path: String) -> void:
	if not visible:
		return
	var result: Dictionary = _library.import_file(path)
	_refresh(true)
	if not result.ok:
		_show_failure(result.code)


func _export_recording() -> void:
	var result: Dictionary = _library.export_recording(str(_library.snapshot().selected_id))
	_refresh()
	if result.ok:
		error_label.text = tr("UI_REPLAY_EXPORTED") + "\n" + str(result.context.path)
		error_label.visible = true
	else:
		_show_failure(result.code)


func _choose_remove() -> void:
	_library.set_playing(false)
	_delete_id = str(_library.snapshot().selected_id)
	_delete.popup_centered()


func _remove_confirmed() -> void:
	if visible and _delete_id == str(_library.snapshot().selected_id):
		var result: Dictionary = _library.remove(_delete_id)
		_refresh(true)
		if not result.ok:
			_show_failure(result.code)
	_delete_id = ""


func _remove_canceled() -> void:
	_delete_id = ""
	_refresh(true)


func _dialog_input(event: InputEvent, dialog: Window) -> void:
	if visible and dialog.visible and event.is_action_pressed("ui_cancel"):
		dialog.set_input_as_handled()
		dialog.hide()
		dialog.emit_signal("canceled")


func _show_failure(code: StringName) -> void:
	var key := "UI_REPLAY_INVALID"
	if code in [&"REPLAY_ARCHIVE_CAPACITY", &"RUN_REPLAY_STORE_CAPACITY"]:
		key = "UI_REPLAY_FULL"
	elif code == &"REPLAY_PACKAGE_INCOMPATIBLE":
		key = "UI_REPLAY_INCOMPATIBLE"
	elif code in [&"REPLAY_ARCHIVE_STALE_PRIMARY", &"REPLAY_EXPORT_FAILED"]:
		key = "UI_REPLAY_SAVE_FAILED"
	show_rejection(key)


func _process(delta: float) -> void:
	if visible and is_instance_valid(_library):
		_library.advance(delta)


func close_panel() -> void:
	if is_instance_valid(_import):
		_import.hide()
	if is_instance_valid(_delete):
		_delete.hide()
	if is_instance_valid(_library):
		_library.close_selection()
	_signature = ""
	super.close_panel()
