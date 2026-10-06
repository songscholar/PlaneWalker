class_name PlatformPanel
extends "res://scripts/ui/dungeon_panel_view.gd"

const Coordinator := preload("res://scripts/platform/platform_service_coordinator.gd")
const Provider := preload("res://scripts/platform/platform_provider.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const SECTIONS := ["account", "storage", "community", "content", "sharing"]
var _coordinator: RefCounted
var _section := "account"
var _section_selector: TabBar
var _status_art: TextureRect
var _display_name: LineEdit
var _capture_source: Callable


func _build_layout() -> void:
	super._build_layout()
	var layout := scroll.get_parent()
	var status := HBoxContainer.new()
	status.name = "PlatformStatus"
	status.add_theme_constant_override("separation", 6)
	layout.add_child(status)
	layout.move_child(status, summary_label.get_index())
	_status_art = Art.image(Art.icon(&"room_types", &"rest"), 24, "PlatformStatusArtwork")
	status.add_child(_status_art)
	summary_label.reparent(status, false)
	_section_selector = TabBar.new()
	_section_selector.name = "PlatformSections"
	_section_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section_selector.custom_minimum_size = Vector2(0, 29)
	_section_selector.focus_mode = Control.FOCUS_ALL
	_section_selector.add_theme_font_size_override("font_size", 12)
	_section_selector.scrolling_enabled = true
	_section_selector.clip_tabs = true
	for section: String in SECTIONS:
		_section_selector.add_tab(tr("UI_PLATFORM_SECTION_" + section.to_upper()))
		_section_selector.set_tab_icon(_section_selector.tab_count - 1, Art.icon(&"controls", StringName(section)))
	_section_selector.add_theme_constant_override("icon_max_width", 16)
	_section_selector.tab_changed.connect(func(index: int):
		if visible and not _submitted:
			select_section(SECTIONS[index]))
	layout.add_child(_section_selector)
	layout.move_child(_section_selector, scroll.get_index())
	Art.button_icon(back_button, Art.icon(&"controls", &"back"))


func configure(provider: RefCounted, profile: RefCounted) -> Dictionary:
	if _coordinator != null or not is_node_ready():
		return Provider.failure(&"INVALID_ARGUMENT")
	var coordinator_value := Coordinator.new()
	var result := coordinator_value.configure(provider, profile)
	if result.ok:
		_coordinator = coordinator_value
	return result


func coordinator() -> RefCounted:
	return _coordinator


func set_screenshot_source(source: Callable) -> void:
	_capture_source = source


func open() -> Dictionary:
	if _coordinator == null:
		return Provider.failure(&"NOT_CONFIGURED")
	var refreshed: Dictionary = _coordinator.refresh()
	return _redraw() if refreshed.ok else refreshed


func is_open() -> bool:
	return visible


func select_section(section: String) -> Dictionary:
	if not visible or section not in SECTIONS:
		return Provider.failure(&"INVALID_ARGUMENT")
	_section = section
	return open()


func submit_command(command: String, request: Dictionary, revision: int) -> Dictionary:
	if not visible or _coordinator == null:
		return Provider.failure(&"NOT_OPEN")
	var result: Dictionary = _coordinator.execute(command, request, revision)
	if result.ok:
		_redraw()
	else:
		show_rejection("UI_PLATFORM_STALE" if result.code == &"STALE_REVISION" else "UI_PLATFORM_SAVE_FAILED")
	return result


func handle_input(event: InputEvent) -> bool:
	if not visible or FocusCoordinator.active_scope() != self:
		return false
	if event.is_action_pressed("ui_cancel"):
		_request_close()
		return true
	var controls := _focus_controls()
	var owner := get_viewport().gui_get_focus_owner()
	var direction := 1 if event.is_action_pressed("ui_down") else (-1 if event.is_action_pressed("ui_up") else 0)
	if direction != 0 and not controls.is_empty():
		var index := controls.find(owner)
		controls[posmod(index + direction, controls.size())].grab_focus()
		return true
	if owner == _section_selector and (event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")):
		var index := posmod(_section_selector.current_tab + (1 if event.is_action_pressed("ui_right") else -1), SECTIONS.size())
		select_section(SECTIONS[index])
		return true
	if event.is_action_pressed("ui_accept") and owner is Button and not owner.disabled:
		owner.pressed.emit()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


func _validate(value: Dictionary):
	if value.size() != 4 or value.get("run_id") != "platform-panel" or not value.get("revision") is int or not value.get("model") is Dictionary or value.get("section") not in SECTIONS:
		return CommandResultScript.failure(&"INVALID_ARGUMENT", 0)
	return CommandResultScript.success(value.revision)


func _redraw() -> Dictionary:
	var value: Dictionary = _coordinator.snapshot()
	var result = render({"run_id": "platform-panel", "revision": int(value.revision), "model": value.model, "section": _section})
	return Provider.success() if result.ok else Provider.failure(result.code)


func _render_state() -> void:
	_display_name = null
	title_label.text = tr("UI_PLATFORM_TITLE")
	summary_label.text = tr("UI_PLATFORM_STATUS_" + str(_state.model.status))
	_section_selector.set_block_signals(true)
	for index: int in range(SECTIONS.size()):
		_section_selector.set_tab_title(index, tr("UI_PLATFORM_SECTION_" + str(SECTIONS[index]).to_upper()))
	_section_selector.current_tab = SECTIONS.find(_state.section)
	_section_selector.set_block_signals(false)
	_status_art.modulate = Color("e5bd69") if str(_state.model.status).begins_with("OFFLINE") else Color("79baa1")
	match _state.section:
		"account":
			_render_account()
		"storage":
			_render_storage()
		"community":
			_render_community()
		"content":
			_render_content()
		"sharing":
			_render_sharing()
	if not str(_state.model.notice_key).is_empty():
		_add_text(tr(str(_state.model.notice_key)), "Notice")
	if not str(_state.model.artifact_path).is_empty():
		var path := _add_text(str(_state.model.artifact_path), "ArtifactPath")
		path.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		if str(_state.model.artifact_path).get_extension().to_lower() == "png" and FileAccess.file_exists(str(_state.model.artifact_path)):
			var pixels := Image.load_from_file(str(_state.model.artifact_path))
			if pixels != null and not pixels.is_empty():
				var preview := Art.image(ImageTexture.create_from_image(pixels), 120, "PlatformScreenshotPreview")
				preview.custom_minimum_size = Vector2(0, 150)
				preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				rows_container.add_child(preview)
	if not str(_state.model.share_code).is_empty():
		var code := LineEdit.new()
		code.name = "ShareCode"
		code.editable = false
		code.text = _state.model.share_code
		code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows_container.add_child(code)
	_add_command("refresh", "UI_PLATFORM_REFRESH", {})


func _render_account() -> void:
	_add_text(str(_state.model.identity.id), "Identity")
	_display_name = LineEdit.new()
	_display_name.name = "DisplayName"
	_display_name.text = _state.model.identity.display_name
	_display_name.max_length = 64
	_display_name.placeholder_text = tr("UI_PLATFORM_DISPLAY_NAME")
	_display_name.tooltip_text = tr("UI_PLATFORM_DISPLAY_NAME")
	_display_name.custom_minimum_size = Vector2(0, 29)
	_display_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_display_name.add_theme_font_size_override("font_size", 12)
	rows_container.add_child(_display_name)
	_add_action("rename", tr("UI_PLATFORM_SAVE_NAME"), "", true, "", _rename)
	_add_text(tr("UI_PLATFORM_ACHIEVEMENTS"), "AchievementsTitle")
	if _state.model.achievements.is_empty():
		_add_text(tr("UI_PLATFORM_ACHIEVEMENTS_EMPTY"), "EmptyAchievements")
	for id: String in _state.model.achievements:
		var key := "UI_PLATFORM_ACHIEVEMENT_" + id.to_upper()
		var caption := tr(key)
		_add_text(caption if caption != key else id.replace("_", " ").capitalize(), "Achievement")


func _render_storage() -> void:
	_add_command("backup_profile", "UI_PLATFORM_BACKUP_PROFILE", {})
	_add_command("export_profile", "UI_PLATFORM_EXPORT_PROFILE", {})
	if _state.model.cloud.is_empty():
		_add_text(tr("UI_PLATFORM_CLOUD_EMPTY"), "EmptyCloud")
	for entry: Dictionary in _state.model.cloud:
		_add_text(str(entry.key), "CloudKey")
		_add_command("export_cloud", "UI_PLATFORM_EXPORT_BACKUP", {"key": entry.key}, "export_cloud:" + str(entry.key))


func _render_community() -> void:
	_add_text(tr("UI_PLATFORM_FRIENDS"), "FriendsTitle")
	if _state.model.friends.is_empty():
		_add_text(tr("UI_PLATFORM_FRIENDS_EMPTY"), "EmptyFriends")
	for friend: Dictionary in _state.model.friends:
		_add_text(str(friend.display_name), "Friend")
	_add_text(tr("UI_PLATFORM_LOCAL_BOARD"), "BoardTitle")
	if _state.model.leaderboard.is_empty():
		_add_text(tr("UI_PLATFORM_BOARD_EMPTY"), "EmptyBoard")
	for entry: Dictionary in _state.model.leaderboard:
		_art_row("%s / %d / %.2fs" % [str(entry.display_name), int(entry.score), float(entry.elapsed_ms) / 1000.0], Art.icon(&"mode_art", &"boss_rush"), "LeaderboardEntry")


func _render_content() -> void:
	if _state.model.content.is_empty() and _state.model.entitlements.is_empty():
		_add_text(tr("UI_PLATFORM_CONTENT_EMPTY"), "EmptyContent")
	for entry: Dictionary in _state.model.content:
		_art_row("%s / %s" % [entry.pack_id, entry.pack_version], Art.icon(&"room_types", &"treasure"), "LocalPack")
	for entry: Dictionary in _state.model.entitlements:
		_add_text(tr(str(entry.name_key)) + " / " + tr("UI_PLATFORM_OWNED" if entry.owned else "UI_PLATFORM_UNOWNED"), "Entitlement")


func _render_sharing() -> void:
	var capture := _add_action("screenshot", tr("UI_PLATFORM_SCREENSHOT"), "", DisplayServer.get_name() != "headless" or _capture_source.is_valid(), "", _capture)
	Art.button_icon(capture, Art.icon(&"controls", &"screenshot"))
	if _state.model.builds.is_empty():
		_add_text(tr("UI_PLATFORM_BUILDS_EMPTY"), "EmptyBuilds")
	for build: Dictionary in _state.model.builds:
		_add_command("share_build", "UI_PLATFORM_SHARE_BUILD", {"build_id": build.id}, "share_build:" + str(build.id), str(build.name))
	if _state.model.replays.is_empty():
		_add_text(tr("UI_PLATFORM_REPLAYS_EMPTY"), "EmptyReplays")
	for replay: Dictionary in _state.model.replays:
		_add_command("share_replay", "UI_PLATFORM_SHARE_REPLAY", {"id": replay.id}, "share_replay:" + str(replay.id))


func _add_command(command: String, key: String, request: Dictionary, action_id: String = "", description: String = "") -> void:
	var button := _add_action(action_id if not action_id.is_empty() else command, tr(key), description, true, "", _submit.bind(command, request.duplicate(true), int(_state.revision)))
	Art.button_icon(button, Art.icon(&"controls", &"refresh" if command == "refresh" else &"export"))


func _art_row(text: String, texture: Texture2D, node_name: String) -> void:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 8)
	rows_container.add_child(row)
	row.add_child(Art.image(texture, 24, node_name + "Artwork"))
	row.add_child(_label(text, node_name + "Facts", 11))


func _submit(command: String, request: Dictionary, revision: int) -> void:
	submit_command(command, request, revision)


func _rename() -> void:
	submit_command("rename", {"display_name": _display_name.text}, int(_state.revision))


func _capture() -> void:
	var image: Variant = _capture_source.call() if _capture_source.is_valid() else get_viewport().get_texture().get_image()
	if not image is Image:
		show_rejection("UI_PLATFORM_SAVE_FAILED")
		return
	submit_command("screenshot", {"image": image}, int(_state.revision))


func _select_index(index: int, source_epoch: int) -> void:
	if source_epoch == _epoch and visible and index >= 0 and index < SECTIONS.size():
		select_section(SECTIONS[index])


func _focus_controls() -> Array[Control]:
	var controls: Array[Control] = [_section_selector]
	if is_instance_valid(_display_name):
		controls.append(_display_name)
	controls.append_array(super._focus_controls())
	return controls


func _exit_tree() -> void:
	FocusCoordinator.close_scope(self)
