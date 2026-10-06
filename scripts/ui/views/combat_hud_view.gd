class_name CombatHudView
extends CanvasLayer

signal intent_emitted(intent: Dictionary)

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")
const TimeAbilityIdsScript := preload("res://scripts/time_system/time_ability_ids.gd")
const Art := preload("res://scripts/ui/style/ui_artwork.gd")
const ResourceSlot := preload("res://scripts/ui/components/ui_resource_slot.gd")
const Facts := preload("res://scripts/ui/style/combat_hud_facts.gd")
const PRESENTATION_THEME_PATH := "res://assets/production/ui/plane_walker_theme.tres"

@onready var hud_root: Control = $HudRoot
@onready var room_label: Label = $HudRoot/SafeArea/HudLayout/RoomPanel/RoomContent/RoomLabel
@onready var run_time_label: Label = $HudRoot/SafeArea/HudLayout/RoomPanel/RoomContent/RunTimeLabel
@onready var pause_indicator: Label = $HudRoot/SafeArea/HudLayout/PauseIndicator
@onready var hp_bar: ProgressBar = $HudRoot/SafeArea/HudLayout/PlayerPanel/PlayerContent/HPBar
@onready var hp_label: Label = $HudRoot/SafeArea/HudLayout/PlayerPanel/PlayerContent/HPLabel
@onready var energy_bar: ProgressBar = $HudRoot/SafeArea/HudLayout/PlayerPanel/PlayerContent/EnergyBar
@onready var energy_label: Label = $HudRoot/SafeArea/HudLayout/PlayerPanel/PlayerContent/EnergyLabel
@onready var low_hp_indicator: Label = $HudRoot/SafeArea/HudLayout/PlayerPanel/PlayerContent/LowHPIndicator
@onready var build_label: Label = $HudRoot/SafeArea/HudLayout/PlayerPanel/PlayerContent/BuildLabel
@onready var weapon_panel: PanelContainer = $HudRoot/SafeArea/HudLayout/WeaponPanel
@onready var weapon_name_label: Label = $HudRoot/SafeArea/HudLayout/WeaponPanel/WeaponContent/WeaponNameLabel
@onready var weapon_meter_bar: ProgressBar = $HudRoot/SafeArea/HudLayout/WeaponPanel/WeaponContent/WeaponMeterBar
@onready var weapon_meter_label: Label = $HudRoot/SafeArea/HudLayout/WeaponPanel/WeaponContent/WeaponMeterLabel
@onready var weapon_status_label: Label = $HudRoot/SafeArea/HudLayout/WeaponPanel/WeaponContent/WeaponStatusLabel
@onready var character_panel: PanelContainer = $HudRoot/SafeArea/HudLayout/CharacterPanel
@onready var character_name_label: Label = $HudRoot/SafeArea/HudLayout/CharacterPanel/CharacterContent/CharacterNameLabel
@onready var character_meter_bar: ProgressBar = $HudRoot/SafeArea/HudLayout/CharacterPanel/CharacterContent/CharacterMeterBar
@onready var character_meter_label: Label = $HudRoot/SafeArea/HudLayout/CharacterPanel/CharacterContent/CharacterMeterLabel
@onready var character_status_label: Label = $HudRoot/SafeArea/HudLayout/CharacterPanel/CharacterContent/CharacterStatusLabel
@onready var character_cooldown_label: Label = $HudRoot/SafeArea/HudLayout/CharacterPanel/CharacterContent/CharacterCooldownLabel
@onready var active_item_panel: PanelContainer = $HudRoot/SafeArea/HudLayout/ActiveItemPanel
@onready var active_item_name_label: Label = $HudRoot/SafeArea/HudLayout/ActiveItemPanel/ActiveItemContent/ActiveItemNameLabel
@onready var active_item_status_label: Label = $HudRoot/SafeArea/HudLayout/ActiveItemPanel/ActiveItemContent/ActiveItemStatusLabel
@onready var skill_slot_labels: Array[Label] = [
	$HudRoot/SafeArea/HudLayout/SkillPanel/SkillContent/AbilitySlot1Label,
	$HudRoot/SafeArea/HudLayout/SkillPanel/SkillContent/AbilitySlot2Label,
]
@onready var boss_panel: PanelContainer = $HudRoot/SafeArea/HudLayout/BossPanel
@onready var boss_name_label: Label = $HudRoot/SafeArea/HudLayout/BossPanel/BossContent/BossNameLabel
@onready var boss_hp_bar: ProgressBar = $HudRoot/SafeArea/HudLayout/BossPanel/BossContent/BossHPBar
@onready var boss_phase_label: Label = $HudRoot/SafeArea/HudLayout/BossPanel/BossContent/BossPhaseLabel

var _last_revision: int = -1
var _last_run_id: String = ""
var _last_state: Dictionary = {}
var _actor_art: TextureRect
var _hp_counter: Label
var _energy_counter: Label
var _hp_gauge: ProgressBar
var _energy_gauge: ProgressBar
var _danger_marker: Label
var _weapon_slot: Control
var _character_slot: Control
var _active_slot: Control
var _time_slots: Array[Control] = []
var _boss_title: Label
var _boss_art: TextureRect
var _boss_gauge: ProgressBar
var _phase_pips: HBoxContainer


func _ready() -> void:
	hud_root.theme = load(PRESENTATION_THEME_PATH) as Theme
	hud_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var frame := hud_root.get_theme_stylebox("panel", "PanelContainer").duplicate() as StyleBox
	frame.content_margin_left = 8
	frame.content_margin_right = 8
	frame.content_margin_top = 5
	frame.content_margin_bottom = 5
	for panel_name: String in ["RoomPanel", "WeaponPanel", "CharacterPanel", "ActiveItemPanel", "PlayerPanel", "SkillPanel"]:
		(hud_root.get_node("SafeArea/HudLayout/" + panel_name) as PanelContainer).add_theme_stylebox_override("panel", frame)
	low_hp_indicator.visible = false
	boss_panel.visible = false
	pause_indicator.visible = false
	character_panel.visible = false
	active_item_panel.visible = false
	_build_graphical_layout()


func _build_graphical_layout() -> void:
	var layout: Control = hud_root.get_node("SafeArea/HudLayout")
	for panel_name: String in ["PlayerPanel", "WeaponPanel", "CharacterPanel", "ActiveItemPanel", "SkillPanel", "BossPanel"]:
		var panel: PanelContainer = layout.get_node(panel_name)
		panel.get_child(0).hide()
	_place(layout.get_node("PlayerPanel"), Vector2(0, 1), Rect2(0, -46, 220, 46))
	_place(weapon_panel, Vector2.ONE, Rect2(-248, -44, 56, 44))
	_place(layout.get_node("SkillPanel"), Vector2.ONE, Rect2(-186, -44, 118, 44))
	_place(active_item_panel, Vector2.ONE, Rect2(-62, -44, 56, 44))
	_place(character_panel, Vector2(0, 1), Rect2(0, -96, 56, 44))
	_place(boss_panel, Vector2(0.5, 0), Rect2(-172, 0, 344, 34))
	var boss_frame := hud_root.get_theme_stylebox("panel", "PanelContainer").duplicate() as StyleBox
	boss_frame.content_margin_left = 6
	boss_frame.content_margin_right = 6
	boss_frame.content_margin_top = 2
	boss_frame.content_margin_bottom = 2
	boss_panel.add_theme_stylebox_override("panel", boss_frame)
	for panel: PanelContainer in [weapon_panel, character_panel, active_item_panel, layout.get_node("SkillPanel")]:
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_weapon_slot = _slot(weapon_panel, "WeaponSlot")
	_character_slot = _slot(character_panel, "CharacterSlot")
	_active_slot = _slot(active_item_panel, "ActiveItemSlot")
	var pair := HBoxContainer.new()
	pair.name = "TimeSlots"
	pair.add_theme_constant_override("separation", 6)
	layout.get_node("SkillPanel").add_child(pair)
	for index: int in range(2):
		_time_slots.append(_slot(pair, "TimeSlot%d" % (index + 1)))
	var vitals := Control.new()
	vitals.name = "GraphicalVitals"
	layout.get_node("PlayerPanel").add_child(vitals)
	_actor_art = Art.image(null, 32, "ActorPortrait")
	vitals.add_child(_actor_art)
	_actor_art.position = Vector2(0, 2)
	_actor_art.size = Vector2(32, 32)
	_hp_counter = _counter(vitals, "HpCounter", Rect2(38, -2, 166, 20), Color("edf0dc"))
	_energy_counter = _counter(vitals, "EnergyCounter", Rect2(54, 16, 150, 20), Color("61d5e7"))
	var energy_art := Art.image(Art.icon(&"items", &"chronal_battery"), 12, "EnergyGlyph")
	vitals.add_child(energy_art)
	energy_art.position = Vector2(38, 20)
	energy_art.size = Vector2(12, 12)
	_hp_gauge = _gauge(vitals, Rect2(38, 16, 166, 2), Color("f07065"))
	_energy_gauge = _gauge(vitals, Rect2(38, 34, 166, 2), Color("61d5e7"))
	_danger_marker = _counter(vitals, "DangerMarker", Rect2(0, -3, 24, 24), Color("f07065"))
	_danger_marker.text = "!"
	_danger_marker.visible = false
	var boss := Control.new()
	boss.name = "GraphicalBossStrip"
	boss_panel.add_child(boss)
	_boss_art = Art.image(null, 20, "BossPortrait")
	boss.add_child(_boss_art)
	_boss_art.position = Vector2(0, 0)
	_boss_art.size = Vector2(20, 20)
	_boss_title = _counter(boss, "BossTitle", Rect2(26, -3, 248, 25), Color("edf0dc"))
	_boss_title.theme_type_variation = &"DisplayLabel"
	_boss_gauge = _gauge(boss, Rect2(0, 25, 332, 3), Color("f07065"))
	_phase_pips = HBoxContainer.new()
	_phase_pips.name = "BossPhasePips"
	_phase_pips.position = Vector2(278, 4)
	_phase_pips.add_theme_constant_override("separation", 3)
	boss.add_child(_phase_pips)
	for control: Control in hud_root.find_children("*", "Control", true, false):
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE


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


func _slot(parent: Control, slot_name: String) -> Control:
	var slot := ResourceSlot.new()
	slot.name = slot_name
	parent.add_child(slot)
	return slot


func _counter(parent: Control, label_name: String, bounds: Rect2, color: Color) -> Label:
	var label := Label.new()
	label.name = label_name
	label.theme_type_variation = &"CounterLabel"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.position = bounds.position
	label.size = bounds.size
	return label


func _gauge(parent: Control, bounds: Rect2, color: Color) -> ProgressBar:
	var gauge := ProgressBar.new()
	gauge.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	gauge.add_theme_stylebox_override("fill", fill)
	var empty := StyleBoxFlat.new()
	empty.bg_color = Color("242d2d")
	gauge.add_theme_stylebox_override("background", empty)
	parent.add_child(gauge)
	gauge.position = bounds.position
	gauge.size = bounds.size
	return gauge


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and not _last_state.is_empty():
		_render_state(_last_state)


func render(view_state: Dictionary):
	var validation = RunViewStateScript.validate(view_state)
	if not validation.ok:
		return validation
	var revision := int(view_state["revision"])
	var run_id := str(view_state["run_id"])
	if run_id == _last_run_id and revision <= _last_revision:
		return CommandResultScript.failure(
			&"STALE_REVISION",
			_last_revision,
			{"received_revision": revision, "last_revision": _last_revision}
		)

	var state := RunViewStateScript.copy_of(view_state)
	_last_run_id = run_id
	_last_revision = revision
	_last_state = state
	_render_state(state)
	return CommandResultScript.success(revision)


func latest_state() -> Dictionary:
	return _last_state.duplicate(true)


func _render_state(state: Dictionary) -> void:
	var flags := state["ui_flags"] as Dictionary
	var show_hud := bool(flags["show_hud"])
	hud_root.visible = show_hud
	if not show_hud:
		return

	var room := state["room"] as Dictionary
	room_label.text = "%d / %d" % [int(room["index"]), int(room["total"])]
	run_time_label.text = _format_time(int(state["run_time_ms"]))
	pause_indicator.visible = bool(state["suspended"]) or bool(flags["show_pause"])
	pause_indicator.text = tr("UI_PAUSED")

	var player := state["player"] as Dictionary
	var hp := float(player["hp"])
	var max_hp := float(player["max_hp"])
	var energy := float(player["energy"])
	var max_energy := float(player["max_energy"])
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_label.text = "HP  %d / %d" % [roundi(hp), roundi(max_hp)]
	energy_bar.max_value = max_energy
	energy_bar.value = energy
	energy_label.text = "%s  %d / %d" % [tr("UI_TIME"), roundi(energy), roundi(max_energy)]
	low_hp_indicator.visible = hp / max_hp <= 0.3
	low_hp_indicator.text = "!  HP < 30%  !"
	_hp_counter.text = "HP  %d / %d" % [roundi(hp), roundi(max_hp)]
	_energy_counter.text = "%d / %d" % [roundi(energy), roundi(max_energy)]
	_hp_gauge.max_value = max_hp
	_hp_gauge.value = hp
	_energy_gauge.max_value = max_energy
	_energy_gauge.value = energy
	_danger_marker.visible = low_hp_indicator.visible

	var time_slots := player["time_slots"] as Array
	for index: int in range(skill_slot_labels.size()):
		var slot := time_slots[index] as Dictionary
		skill_slot_labels[index].text = _format_skill(
			str(slot["ability_id"]),
			float(slot["cooldown"])
		)
		_time_slots[index].call("render_slot", StringName(slot.ability_id), 0, 0, float(slot.cooldown) <= 0, tr("HUD_WEAPON_READY") if float(slot.cooldown) <= 0 else "%.1f" % float(slot.cooldown))
		_time_slots[index].tooltip_text = skill_slot_labels[index].text

	_render_weapon(state["weapon_state"] as Dictionary)
	_render_character(state["character_state"])
	_render_active_item(state["active_item_state"])

	var build := state["build"] as Dictionary
	var archetype := str(build["dominant_archetype"])
	build_label.text = tr("HUD_BUILD_UNFORMED") if archetype.is_empty() else tr("HUD_BUILD_FMT") % tr("ARCHETYPE_" + archetype.to_upper() + "_NAME")

	var boss: Variant = state["boss"]
	boss_panel.visible = boss != null
	if boss == null:
		return
	var boss_state := boss as Dictionary
	boss_name_label.text = tr(str(boss_state["name_key"]))
	boss_hp_bar.max_value = float(boss_state["max_hp"])
	boss_hp_bar.value = float(boss_state["hp"])
	boss_phase_label.text = tr("UI_STATUS_PHASE_FMT") % ("%d / %d" % [int(boss_state["phase_index"]), int(boss_state["phase_total"])])
	_boss_title.text = boss_name_label.text
	_boss_art.texture = Art.actor(str(boss_state.boss_id))
	_boss_gauge.max_value = boss_hp_bar.max_value
	_boss_gauge.value = boss_hp_bar.value
	if _phase_pips.get_child_count() != int(boss_state.phase_total):
		for pip: Node in _phase_pips.get_children():
			_phase_pips.remove_child(pip)
			pip.queue_free()
		for index: int in range(int(boss_state.phase_total)):
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(8, 6)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_phase_pips.add_child(pip)
	for index: int in range(_phase_pips.get_child_count()):
		(_phase_pips.get_child(index) as ColorRect).color = Color("f07065") if index < int(boss_state.phase_index) else Color("697771")
	boss_panel.tooltip_text = boss_name_label.text + " / " + boss_phase_label.text


func _format_skill(ability_id: String, cooldown: float) -> String:
	var label := tr(TimeAbilityIdsScript.localization_key(ability_id))
	if cooldown <= 0.0:
		return "%s  %s" % [label, tr("HUD_WEAPON_READY")]
	return "%s  %s" % [label, tr("HUD_WEAPON_COOLDOWN_FMT") % cooldown]


func _render_active_item(value: Variant) -> void:
	active_item_panel.visible = value is Dictionary
	if not value is Dictionary:
		return
	var active := value as Dictionary
	active_item_name_label.text = tr(str(active["name_key"]))
	var cooldown_frames := int(active["cooldown_current"])
	active_item_status_label.text = (
		tr("HUD_WEAPON_READY")
		if bool(active["ready"])
		else tr("HUD_WEAPON_COOLDOWN_FMT") % (float(cooldown_frames) / 60.0)
	)
	_active_slot.call("render_slot", StringName(active.content_id), int(active.cooldown_max) - cooldown_frames, int(active.cooldown_max), bool(active.ready), tr("HUD_WEAPON_READY") if bool(active.ready) else "%.1f" % (float(cooldown_frames) / 60.0))
	_active_slot.tooltip_text = active_item_name_label.text + " / " + active_item_status_label.text


func _render_character(value: Variant) -> void:
	character_panel.visible = value is Dictionary
	_actor_art.visible = value is Dictionary
	if not value is Dictionary:
		return
	var character := value as Dictionary
	var character_id := str(character["character_id"])
	var meter_current := float(character["meter_current"])
	var meter_max := float(character["meter_max"])
	var cooldown_current := float(character["cooldown_current"])
	var facts := Facts.character(character)
	character_name_label.text = facts.name
	character_meter_bar.max_value = meter_max
	character_meter_bar.value = meter_current
	character_meter_label.text = facts.meter
	character_status_label.text = facts.status
	character_cooldown_label.text = facts.cooldown
	_actor_art.texture = Art.actor(character_id)
	_character_slot.call("set_artwork", Art.actor(character_id))
	_character_slot.call("render_slot", &"", meter_current, meter_max, cooldown_current <= 0, "%.1f" % (cooldown_current / 60.0) if cooldown_current > 0 else "%d/%d" % [roundi(meter_current), roundi(meter_max)])
	_character_slot.tooltip_text = " / ".join([character_name_label.text, character_meter_label.text, character_status_label.text, character_cooldown_label.text])


func _render_weapon(weapon: Dictionary) -> void:
	var weapon_id := str(weapon["weapon_id"])
	var meter_current := float(weapon["meter_current"])
	var meter_max := float(weapon["meter_max"])
	var facts := Facts.weapon(weapon)
	weapon_name_label.text = facts.name
	weapon_meter_bar.max_value = meter_max
	weapon_meter_bar.value = meter_current
	weapon_meter_label.text = facts.meter
	weapon_status_label.text = facts.status
	_weapon_slot.call("render_slot", StringName(weapon_id), meter_current, meter_max, str(weapon.phase) == "READY", "%d/%d" % [roundi(meter_current), roundi(meter_max)])
	_weapon_slot.tooltip_text = " / ".join([weapon_name_label.text, weapon_meter_label.text, weapon_status_label.text])


func _format_time(run_time_ms: int) -> String:
	var total_seconds := maxi(0, run_time_ms / 1000)
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]
