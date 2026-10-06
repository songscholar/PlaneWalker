class_name ModeCombatHudView
extends Control

signal pause_requested

const Contract := preload("res://scripts/ui/contracts/mode_combat_hud_view_state.gd")
const Result := preload("res://scripts/application/command_result.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const Slot := preload("res://scripts/ui/components/ui_resource_slot.gd")
const Facts := preload("res://scripts/ui/style/combat_hud_facts.gd")
const MODE_KEYS := {"boss_rush": "UI_MODE_BOSS_RUSH", "daily": "UI_DAILY_TITLE", "authored": "UI_AUTHORED_TITLE", "endless": "UI_MODE_ENDLESS"}
var _state: Dictionary = {}
var _retired_runs: Dictionary = {}
var _timer: Label
var _portrait: TextureRect
var _hp: Label
var _energy: Label
var _hp_gauge: ProgressBar
var _energy_gauge: ProgressBar
var _weapon: Control
var _character: Control
var _active: Control
var _time_slots: Array[Control] = []
var _boss_strip: Control
var _boss_portrait: TextureRect
var _boss_title: Label
var _boss_gauge: ProgressBar
var _boss_phases: HBoxContainer
var _pause: Button


func _ready() -> void:
	name = "ModeCombatHud"
	theme = load("res://assets/production/ui/plane_walker_theme.tres") as Theme
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer = _label(self, "ModeTimer", Rect2(10, 7, 150, 66))
	_timer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pause = Button.new()
	_pause.name = "PauseButton"
	_pause.custom_minimum_size = Vector2(32, 29)
	_pause.tooltip_text = tr("UI_MODE_PAUSE")
	_pause.focus_mode = Control.FOCUS_ALL
	Art.button_icon(_pause, Art.icon(&"controls", &"pause"))
	add_child(_pause)
	_place(_pause, Vector2(1, 0), Rect2(-42, 10, 32, 29))
	_pause.pressed.connect(func(): pause_requested.emit())
	var vitals := Control.new()
	vitals.name = "ModeVitals"
	add_child(vitals)
	_place(vitals, Vector2(0, 1), Rect2(10, -70, 220, 60))
	_portrait = Art.image(null, 40, "ModePlayerPortrait")
	vitals.add_child(_portrait)
	_portrait.position = Vector2(0, 8)
	_portrait.size = Vector2(40, 40)
	_hp = _label(vitals, "ModeHpCounter", Rect2(46, 0, 174, 25))
	_energy = _label(vitals, "ModeEnergyCounter", Rect2(46, 29, 174, 25))
	_energy.add_theme_color_override("font_color", Color("61d5e7"))
	_hp_gauge = _gauge(vitals, "ModeHpGauge", Rect2(46, 26, 174, 3), Color("f07065"))
	_energy_gauge = _gauge(vitals, "ModeEnergyGauge", Rect2(46, 55, 174, 3), Color("61d5e7"))
	_weapon = _slot(self, "WeaponSlot")
	_place(_weapon, Vector2.ONE, Rect2(-258, -54, 56, 44))
	for index: int in range(2):
		var slot := _slot(self, "TimeSlot%d" % (index + 1))
		_time_slots.append(slot)
		_place(slot, Vector2.ONE, Rect2(-196 + index * 62, -54, 56, 44))
	_active = _slot(self, "ActiveItemSlot")
	_place(_active, Vector2.ONE, Rect2(-72, -54, 56, 44))
	_character = _slot(self, "CharacterSlot")
	_place(_character, Vector2(0, 1), Rect2(10, -120, 56, 44))
	_boss_strip = Control.new()
	_boss_strip.name = "ModeBossStrip"
	add_child(_boss_strip)
	_place(_boss_strip, Vector2(0.5, 0), Rect2(-156, 8, 312, 45))
	_boss_portrait = Art.image(null, 24, "ModeBossPortrait")
	_boss_strip.add_child(_boss_portrait)
	_boss_portrait.size = Vector2(24, 24)
	_boss_title = _label(_boss_strip, "ModeBossTitle", Rect2(30, 0, 228, 26))
	_boss_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_boss_gauge = _gauge(_boss_strip, "ModeBossGauge", Rect2(0, 31, 312, 4), Color("f07065"))
	_boss_phases = HBoxContainer.new()
	_boss_phases.name = "ModeBossPhases"
	_boss_strip.add_child(_boss_phases)
	_boss_phases.position = Vector2(264, 8)
	_boss_phases.add_theme_constant_override("separation", 3)
	visible = false


func render(view: Dictionary):
	var validation = Contract.validate(view)
	if not validation.ok:
		return validation
	if not _state.is_empty() and view.run_id == _state.run_id and view.revision <= _state.revision:
		return Result.failure(&"STALE_REVISION", int(_state.revision))
	if _retired_runs.has(view.run_id):
		return Result.failure(&"STALE_REVISION", int(_state.revision), {"field": "run_id"})
	if not _state.is_empty() and view.run_id != _state.run_id:
		_retired_runs[_state.run_id] = true
	_state = view.duplicate(true)
	_render()
	return Result.success(int(view.revision))


func latest_state() -> Dictionary:
	return _state.duplicate(true)


func _render() -> void:
	_timer.text = "%s\n%d / %d  %.2fs" % [tr(MODE_KEYS[_state.mode_id]), int(_state.stage_index) + 1, int(_state.stage_total), float(_state.elapsed_frames) / 60.0]
	var player: Dictionary = _state.player
	_hp.text = "HP  %d / %d" % [roundi(player.hp), roundi(player.max_hp)]
	_energy.text = "%d / %d" % [roundi(player.energy), roundi(player.max_energy)]
	_hp_gauge.max_value = player.max_hp
	_hp_gauge.value = player.hp
	_energy_gauge.max_value = player.max_energy
	_energy_gauge.value = player.energy
	_portrait.modulate = Color("f07065") if float(player.hp) / float(player.max_hp) <= 0.25 else Color.WHITE
	var weapon: Dictionary = _state.weapon_state
	var weapon_facts := Facts.weapon(weapon)
	_weapon.render_slot(StringName(weapon.weapon_id), weapon.meter_current, weapon.meter_max, weapon.status_id == "ready", "%d/%d" % [roundi(weapon.meter_current), roundi(weapon.meter_max)])
	_weapon.tooltip_text = "\n".join([weapon_facts.name, weapon_facts.meter, weapon_facts.status])
	_character.visible = _state.character_state is Dictionary
	if _state.character_state is Dictionary:
		var character: Dictionary = _state.character_state
		_portrait.texture = Art.actor(str(character.character_id))
		_character.set_artwork(Art.actor(str(character.character_id)))
		_character.render_slot(&"", character.meter_current, character.meter_max, float(character.cooldown_current) == 0, "%.1fs" % (float(character.cooldown_current) / 60.0) if float(character.cooldown_current) > 0 else "%d/%d" % [roundi(character.meter_current), roundi(character.meter_max)])
		var character_facts := Facts.character(character)
		_character.tooltip_text = "\n".join([character_facts.name, character_facts.meter, character_facts.status, character_facts.cooldown])
	_active.visible = _state.active_item_state is Dictionary
	if _state.active_item_state is Dictionary:
		var active: Dictionary = _state.active_item_state
		_active.render_slot(StringName(active.icon_id), active.cooldown_max - active.cooldown_current, active.cooldown_max, active.ready, tr("HUD_ACTIVE_ITEM_READY") if active.ready else "%.1fs" % (float(active.cooldown_current) / 60.0))
		_active.tooltip_text = tr(active.name_key)
	for index: int in range(2):
		var source: Dictionary = player.time_slots[index]
		_time_slots[index].render_slot(StringName(source.ability_id), 0, 0, float(source.cooldown) == 0, tr("HUD_WEAPON_READY") if float(source.cooldown) == 0 else "%.1fs" % float(source.cooldown))
		_time_slots[index].tooltip_text = tr("INPUT_ACTION_" + str(source.action_id).to_upper())
	_boss_strip.visible = _state.boss is Dictionary
	if _state.boss is Dictionary:
		var boss: Dictionary = _state.boss
		_boss_title.text = tr(boss.name_key)
		_boss_portrait.texture = Art.actor(str(boss.boss_id))
		_boss_gauge.max_value = boss.max_hp
		_boss_gauge.value = boss.hp
		if _boss_phases.get_child_count() != int(boss.phase_total):
			for pip: Node in _boss_phases.get_children():
				_boss_phases.remove_child(pip)
				pip.queue_free()
			for index: int in range(int(boss.phase_total)):
				var pip := ColorRect.new()
				pip.custom_minimum_size = Vector2(8, 8)
				pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_boss_phases.add_child(pip)
		for index: int in range(_boss_phases.get_child_count()):
			(_boss_phases.get_child(index) as ColorRect).color = Color("e5bd69") if index < int(boss.phase_index) else Color("46554f")


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not _state.is_empty():
		_pause.tooltip_text = tr("UI_MODE_PAUSE")
		_render()


func _place(control: Control, anchor: Vector2, bounds: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = bounds.position.x
	control.offset_top = bounds.position.y
	control.offset_right = bounds.end.x
	control.offset_bottom = bounds.end.y


func _slot(parent: Control, node_name: String) -> Control:
	var slot := Slot.new()
	slot.name = node_name
	parent.add_child(slot)
	return slot


func _label(parent: Control, node_name: String, bounds: Rect2) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = &"CounterLabel"
	label.add_theme_font_size_override("font_size", 11)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.position = bounds.position
	label.size = bounds.size
	return label


func _gauge(parent: Control, node_name: String, bounds: Rect2, color: Color) -> ProgressBar:
	var gauge := ProgressBar.new()
	gauge.name = node_name
	gauge.show_percentage = false
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	gauge.add_theme_stylebox_override("fill", fill)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("242d2d")
	gauge.add_theme_stylebox_override("background", background)
	parent.add_child(gauge)
	gauge.position = bounds.position
	gauge.size = bounds.size
	return gauge
