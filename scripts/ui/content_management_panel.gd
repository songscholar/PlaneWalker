class_name ContentManagementPanel
extends "res://scripts/ui/dungeon_panel_view.gd"

signal command_requested(operation: String, payload: Dictionary, revision: int)

var _directory: FileDialog


func _ready() -> void:
	super._ready()
	_directory = FileDialog.new()
	_directory.title = tr("UI_CONTENT_INSTALL")
	_directory.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_directory.access = FileDialog.ACCESS_FILESYSTEM
	_directory.size = Vector2i(560, 300)
	add_child(_directory)
	_directory.dir_selected.connect(_install_selected)
	_directory.canceled.connect(_send.bind("cancel", {}))


func _validate(state: Dictionary):
	if state.keys().size() != 8 or state.get("run_id") != "content-manager" or typeof(state.get("revision")) != TYPE_INT or not state.get("installed") is Array or not state.get("activation") is Dictionary or not state.get("locked") is bool or not state.get("diagnostics") is Array or not state.get("entitlements") is Dictionary or typeof(state.get("epoch")) != TYPE_INT:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	if state.revision < 0 or state.epoch != state.revision or not state.activation.get("save_domain") is String or not state.activation.get("activation_order") is Array:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	var ids: Array = []
	for id: Variant in state.activation.activation_order:
		if not id is String or id.is_empty() or ids.has(id):
			return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
		ids.append(id)
	ids.clear()
	for row: Variant in state.installed:
		if not row is Dictionary or not row.get("pack_id") is String or row.pack_id.is_empty() or ids.has(row.pack_id) or not row.get("pack_version") is String or not row.get("enabled") is bool or not row.get("owned") is bool:
			return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
		ids.append(row.pack_id)
	for row: Variant in state.diagnostics:
		if not row is Dictionary or not row.get("pack_id", "") is String:
			return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	return CommandResultScript.success(int(state.revision))


func _render_state() -> void:
	title_label.text = tr("UI_CONTENT_TITLE")
	summary_label.text = tr("UI_CONTENT_BASE") if _state.activation.save_domain == "base" else tr("UI_CONTENT_LOCAL")
	if _state.locked:
		_add_text(tr("UI_CONTENT_RUN_LOCK"), "RunLock")
	_add_action("install", tr("UI_CONTENT_INSTALL"), "", not _state.locked, "", _choose_directory)
	_add_action("refresh", tr("UI_CONTENT_REFRESH"), "", not _state.locked, "", _send.bind("refresh", {}))
	if _state.installed.is_empty():
		_add_text(tr("UI_CONTENT_EMPTY"), "EmptyPackages")
	for row: Dictionary in _state.installed:
		var checkbox := CheckBox.new()
		checkbox.text = "%s  %s" % [str(row.pack_id), str(row.pack_version)]
		checkbox.button_pressed = bool(row.enabled)
		checkbox.disabled = _state.locked or not row.owned
		checkbox.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		checkbox.custom_minimum_size = Vector2(0, 29)
		checkbox.add_theme_font_size_override("font_size", 12)
		for selected: bool in [false, true]:
			var key := "checked" if selected else "unchecked"
			checkbox.add_theme_icon_override(key, _selection_icon(selected, false))
			checkbox.add_theme_icon_override(key + "_disabled", _selection_icon(selected, true))
		checkbox.set_meta("available", not checkbox.disabled)
		checkbox.set_meta("action_id", "enable:" + str(row.pack_id))
		var selected: Array = _state.activation.activation_order.duplicate()
		selected.erase("base")
		if row.enabled:
			selected.erase(row.pack_id)
		else:
			selected.append(row.pack_id)
		checkbox.pressed.connect(_activate_action.bind(checkbox, _send.bind("set_enabled", {"ids": selected}), _epoch))
		rows_container.add_child(checkbox)
		_actions.append(checkbox)
		if not row.owned:
			_add_text(tr("UI_CONTENT_ENTITLEMENT_REQUIRED"), "Entitlement")
		_add_action("remove:" + str(row.pack_id), tr("UI_CONTENT_REMOVE"), "", not _state.locked and not row.enabled, "", _send.bind("uninstall", {"id": row.pack_id}))
	for row: Dictionary in _state.diagnostics:
		_add_text(tr("UI_CONTENT_ISOLATED_FMT") % str(row.get("pack_id", "")), "Diagnostic")


func _choose_directory() -> void:
	_directory.title = tr("UI_CONTENT_INSTALL")
	_directory.popup_centered(Vector2i(560, 300))


static func _selection_icon(selected: bool, disabled: bool) -> ImageTexture:
	var pixels := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	var border := Color("647a80") if disabled else Color("8ceaff")
	for x: int in range(2, 14):
		for y: int in range(2, 14):
			if x in [2, 13] or y in [2, 13]:
				pixels.set_pixel(x, y, border)
	if selected:
		for point: Vector2i in [Vector2i(4, 7), Vector2i(5, 8), Vector2i(6, 9), Vector2i(7, 8), Vector2i(8, 7), Vector2i(9, 6), Vector2i(10, 5), Vector2i(11, 4)]:
			pixels.set_pixelv(point, border)
			pixels.set_pixelv(point + Vector2i.DOWN, border)
	return ImageTexture.create_from_image(pixels)


func _install_selected(path: String) -> void:
	_send("install", {"path": path})


func _send(operation: String, payload: Dictionary) -> void:
	command_requested.emit(operation, payload.duplicate(true), int(_state.revision))


func close_panel() -> void:
	if is_instance_valid(_directory):
		_directory.hide()
	super.close_panel()
