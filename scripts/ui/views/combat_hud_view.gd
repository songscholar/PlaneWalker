class_name CombatHudView
extends CanvasLayer

signal intent_emitted(intent: Dictionary)

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")
const TimeAbilityIdsScript := preload("res://scripts/time_system/time_ability_ids.gd")

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


func _ready() -> void:
	low_hp_indicator.visible = false
	boss_panel.visible = false
	pause_indicator.visible = false


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

	var time_slots := player["time_slots"] as Array
	for index: int in range(skill_slot_labels.size()):
		var slot := time_slots[index] as Dictionary
		skill_slot_labels[index].text = _format_skill(
			str(slot["ability_id"]),
			float(slot["cooldown"])
		)

	_render_weapon(state["weapon_state"] as Dictionary)

	var build := state["build"] as Dictionary
	var archetype := str(build["dominant_archetype"])
	build_label.text = tr("HUD_BUILD_UNFORMED") if archetype.is_empty() else tr("HUD_BUILD_FMT") % tr("ARCHETYPE_" + archetype.to_upper())

	var boss: Variant = state["boss"]
	boss_panel.visible = boss != null
	if boss == null:
		return
	var boss_state := boss as Dictionary
	boss_name_label.text = tr(str(boss_state["name_key"]))
	boss_hp_bar.max_value = float(boss_state["max_hp"])
	boss_hp_bar.value = float(boss_state["hp"])
	boss_phase_label.text = tr("UI_STATUS_PHASE_FMT") % ("%d / %d" % [int(boss_state["phase_index"]), int(boss_state["phase_total"])])


func _format_skill(ability_id: String, cooldown: float) -> String:
	var label := tr(TimeAbilityIdsScript.localization_key(ability_id))
	if cooldown <= 0.0:
		return "%s  %s" % [label, tr("HUD_WEAPON_READY")]
	return "%s  %s" % [label, tr("HUD_WEAPON_COOLDOWN_FMT") % cooldown]


func _render_weapon(weapon: Dictionary) -> void:
	var weapon_id := str(weapon["weapon_id"])
	var meter_kind := str(weapon["meter_kind"])
	var meter_current := float(weapon["meter_current"])
	var meter_max := float(weapon["meter_max"])
	weapon_name_label.text = tr("WEAPON_%s_NAME" % weapon_id.to_upper())
	weapon_meter_bar.max_value = meter_max
	weapon_meter_bar.value = meter_current
	weapon_meter_label.text = _format_weapon_meter(meter_kind, meter_current, meter_max)
	weapon_status_label.text = _format_weapon_status(weapon)


func _format_weapon_meter(meter_kind: String, current: float, maximum: float) -> String:
	var key := "HUD_WEAPON_METER_%s_FMT" % meter_kind.to_upper()
	return tr(key) % [roundi(current), roundi(maximum)]


func _format_weapon_status(weapon: Dictionary) -> String:
	var status_id := str(weapon["status_id"])
	var status_remaining := float(weapon["status_remaining"])
	var secondary_id := str(weapon["secondary_id"])
	var secondary_value := float(weapon["secondary_value"])
	if status_id == "time_load":
		return tr("HUD_WEAPON_STATUS_TIME_LOAD_FMT") % (status_remaining / 60.0)
	if status_id == "perfect_reload":
		return tr("HUD_WEAPON_STATUS_PERFECT_RELOAD")
	if secondary_id == "time_load" and secondary_value > 0.0:
		return tr("HUD_WEAPON_STATUS_TIME_LOAD_FMT") % (secondary_value / 60.0)
	if status_id == "ready":
		return tr("HUD_WEAPON_READY")
	return tr("HUD_WEAPON_STATUS_%s" % status_id.to_upper())


func _format_time(run_time_ms: int) -> String:
	var total_seconds := maxi(0, run_time_ms / 1000)
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]
