class_name TrainingPanelView
extends Control

signal selection_requested(request: Dictionary)
signal play_requested
signal reset_requested
signal back_requested

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const PlayIcon := preload("res://data/content_packs/base/assets/training/play.png")
const PauseIcon := preload("res://data/content_packs/base/assets/training/pause.png")
const ResetIcon := preload("res://data/content_packs/base/assets/training/reset.png")
const BackIcon := preload("res://data/content_packs/base/assets/training/back.png")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")

var _selectors: Dictionary = {}
var _play: Button
var _reset: Button
var _back: Button
var _progress: Label
var _health: ProgressBar
var _energy: ProgressBar
var _hp_text: Label
var _energy_text: Label
var _tasks: Dictionary = {}
var _seed := 42
var _rendering := false
var _configured := false
var _last_projection: Dictionary = {}
var _practicing := false


func _ready() -> void:
	theme = load("res://assets/production/ui/plane_walker_theme.tres") as Theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_layout()


func configure(registry: RefCounted) -> bool:
	if _configured or not is_inside_tree():
		return false
	for row: Dictionary in registry.get_catalog_entries(&"tutorial_definition", &"LAUNCH"):
		if row.get("definition_kind") == "training_task":
			_tasks[row.task_id] = row.duplicate(true)
	if _tasks.size() != 6:
		return false
	for id: String in ["T-01", "T-02", "T-03", "T-04", "T-05", "T-06"]:
		_add_item("task_id", id + "  " + tr(_tasks[id].name_key), id)
	for id: String in Catalog.CHARACTER_IDS:
		_add_item("character_id", tr("CHARACTER_%s_NAME" % id.to_upper()), id)
	for id: String in Catalog.WEAPON_IDS:
		_add_item("weapon_id", tr("WEAPON_%s_NAME" % id.to_upper()), id)
	for first: int in range(Catalog.TIME_IDS.size()):
		for second: int in range(first + 1, Catalog.TIME_IDS.size()):
			var pair := [Catalog.TIME_IDS[first], Catalog.TIME_IDS[second]]
			if pair[1] == "stop":
				pair.reverse()
			var text := tr("UI_TIME_PAIR_FMT") % [tr("TIME_ABILITY_%s_NAME" % pair[0].to_upper()), tr("TIME_ABILITY_%s_NAME" % pair[1].to_upper())]
			_add_item("time_abilities", text, pair)
	_configured = true
	_apply_accessibility()
	FocusCoordinator.link_ring(focus_controls(), true)
	return true


func select_request(request: Dictionary) -> void:
	_rendering = true
	_seed = int(request.seed)
	for field: String in _selectors:
		var option: OptionButton = _selectors[field]
		for index: int in range(option.item_count):
			if option.get_item_metadata(index) == request[field]:
				option.select(index)
				break
	_rendering = false


func selected_request() -> Dictionary:
	var request := {"seed": _seed}
	for field: String in _selectors:
		request[field] = _selectors[field].get_selected_metadata()
	return request.duplicate(true)


func project(progress: Dictionary, request: Dictionary, hp: Vector2, energy: Vector2, rejection: StringName) -> void:
	if not _configured or not progress.get("ok", false):
		return
	var projection := {"revision": int(progress.context.get("revision", 0)), "task": request.task_id, "counters": progress.context.counters.duplicate(true), "claims": progress.context.training_claims.duplicate(true), "hp": hp, "energy": energy, "rejection": rejection}
	if projection == _last_projection:
		return
	_last_projection = projection.duplicate(true)
	var lines: PackedStringArray = []
	var task: Dictionary = _tasks[request.task_id]
	for row: Dictionary in task.receipt_requirements:
		var count: int = int(progress.context.counters.get("task:%s:%s" % [request.task_id, row.action_id], 0))
		lines.append("%s  %d/%d" % [tr("UI_TUTORIAL_ACTION_%s" % str(row.action_id).to_upper()), count, int(row.count)])
	_progress.text = " / ".join(lines)
	if progress.context.training_claims.has(request.task_id):
		_progress.text += "\n" + tr("UI_TRAINING_COMPLETE")
	if rejection != &"":
		_progress.text = tr("UI_TRAINING_SAVE_RETRY")
	_health.max_value = maxf(1.0, hp.y)
	_health.value = hp.x
	_energy.max_value = maxf(1.0, energy.y)
	_energy.value = energy.x
	_hp_text.text = "HP %d/%d" % [roundi(hp.x), roundi(hp.y)]
	_energy_text.text = "%d/%d" % [roundi(energy.x), roundi(energy.y)]


func set_practicing(practicing: bool) -> void:
	_practicing = practicing
	_play.icon = PauseIcon if practicing else PlayIcon
	_play.tooltip_text = tr("UI_TRAINING_PAUSE" if practicing else "UI_TRAINING_PLAY")


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSLATION_CHANGED or not _configured:
		return
	for field: String in _selectors:
		var option: OptionButton = _selectors[field]
		for index: int in range(option.item_count):
			var value: Variant = option.get_item_metadata(index)
			var text := ""
			match field:
				"task_id":
					text = str(value) + "  " + tr(_tasks[value].name_key)
				"character_id":
					text = tr("CHARACTER_%s_NAME" % str(value).to_upper())
				"weapon_id":
					text = tr("WEAPON_%s_NAME" % str(value).to_upper())
				"time_abilities":
					text = tr("UI_TIME_PAIR_FMT") % [tr("TIME_ABILITY_%s_NAME" % str(value[0]).to_upper()), tr("TIME_ABILITY_%s_NAME" % str(value[1]).to_upper())]
			option.set_item_text(index, text)
	set_practicing(_practicing)
	_reset.tooltip_text = tr("UI_RESET_ACTION")
	_back.tooltip_text = tr("UI_BACK")
	_last_projection.clear()


func focus_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for field: String in ["task_id", "character_id", "weapon_id", "time_abilities"]:
		controls.append(_selectors[field])
	controls.append_array([_play, _reset, _back])
	return controls


func selector(field: String) -> OptionButton:
	return _selectors.get(field)


func progress_label() -> Label:
	return _progress


func play_button() -> Button:
	return _play


func reset_button() -> Button:
	return _reset


func back_button() -> Button:
	return _back


func _build_layout() -> void:
	var toolbar := PanelContainer.new()
	toolbar.name = "Toolbar"
	toolbar.add_theme_stylebox_override("panel", _band_style())
	add_child(toolbar)
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	toolbar.offset_bottom = 68
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	toolbar.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	row.add_child(grid)
	for field: String in ["task_id", "character_id", "weapon_id", "time_abilities"]:
		var option := OptionButton.new()
		option.name = field
		option.custom_minimum_size = Vector2(0, 27)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.fit_to_longest_item = false
		option.add_theme_font_size_override("font_size", 12)
		option.add_theme_constant_override("icon_max_width", 32 if field == "time_abilities" else 16)
		option.tooltip_text = tr({"task_id": "UI_TUTORIAL_TRAINING", "character_id": "UI_LAUNCH_CHARACTER_LABEL", "weapon_id": "UI_LAUNCH_WEAPON_LABEL", "time_abilities": "UI_LAUNCH_TIME_PAIR_LABEL"}[field])
		option.item_selected.connect(_selection_changed)
		option.gui_input.connect(_selector_input.bind(option))
		grid.add_child(option)
		_selectors[field] = option
	var tools := GridContainer.new()
	tools.columns = 2
	tools.add_theme_constant_override("h_separation", 4)
	tools.add_theme_constant_override("v_separation", 4)
	row.add_child(tools)
	_play = _tool(tools, "Play", PlayIcon, "UI_TRAINING_PLAY", func(): play_requested.emit())
	_reset = _tool(tools, "Reset", ResetIcon, "UI_RESET_ACTION", func(): reset_requested.emit())
	_back = _tool(tools, "Back", BackIcon, "UI_BACK", func(): back_requested.emit())
	var footer := PanelContainer.new()
	footer.name = "Status"
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -58
	footer.offset_bottom = 0
	footer.add_theme_stylebox_override("panel", _band_style())
	add_child(footer)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 8)
	footer.add_child(status)
	_progress = Label.new()
	_progress.name = "DurableProgress"
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress.add_theme_font_size_override("font_size", 12)
	status.add_child(_progress)
	var resources := VBoxContainer.new()
	resources.custom_minimum_size.x = 120
	resources.add_theme_constant_override("separation", 4)
	status.add_child(resources)
	_health = _resource_bar(resources, "Health", Color("ae5260"))
	_energy = _resource_bar(resources, "TimeEnergy", Color("61a58e"))
	_hp_text = _bar_text(_health)
	_energy_text = _bar_text(_energy)


func _tool(parent: Node, id: String, texture: Texture2D, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.custom_minimum_size = Vector2(28, 27)
	button.icon = texture
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.tooltip_text = tr(tooltip)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _resource_bar(parent: Node, id: String, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = id
	bar.show_percentage = false
	bar.custom_minimum_size.y = 22
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func _bar_text(bar: ProgressBar) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	bar.add_child(label)
	return label


func _add_item(field: String, label: String, metadata: Variant) -> void:
	var option: OptionButton = _selectors[field]
	option.add_item(label)
	option.set_item_metadata(option.item_count - 1, metadata)
	match field:
		"character_id":
			option.set_item_icon(option.item_count - 1, Art.actor(str(metadata)))
		"weapon_id":
			option.set_item_icon(option.item_count - 1, Art.icon(&"weapons", StringName(metadata)))
		"time_abilities":
			option.set_item_icon(option.item_count - 1, _time_pair_icon(metadata))


func _time_pair_icon(pair: Array) -> Texture2D:
	var combined := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for index: int in range(2):
		var source := Art.icon(&"time_abilities", StringName(pair[index])) as AtlasTexture
		if source == null:
			return null
		var pixels := source.atlas.get_image()
		if pixels == null:
			return null
		if pixels.is_compressed():
			pixels.decompress()
		pixels.convert(Image.FORMAT_RGBA8)
		combined.blit_rect(pixels, Rect2i(source.region), Vector2i(index * 32, 0))
	combined.resize(32, 16, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(combined)


func _selection_changed(_index: int) -> void:
	if _configured and not _rendering:
		selection_requested.emit(selected_request())


func _selector_input(event: InputEvent, option: OptionButton) -> void:
	var direction := 1 if event.is_action_pressed("ui_right") else (-1 if event.is_action_pressed("ui_left") else 0)
	if direction != 0 and _configured and not _rendering:
		var index := posmod(option.selected + direction, option.item_count)
		option.select(index)
		_selection_changed(index)
		option.accept_event()


func _apply_accessibility() -> void:
	var runtimes := get_tree().get_nodes_in_group("accessibility_runtime")
	if not runtimes.is_empty():
		runtimes[0].apply_to_tree(self)


static func _band_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202625")
	style.border_color = Color("758b7f")
	style.border_width_bottom = 1
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
