class_name CombatHudView
extends CanvasLayer

signal intent_emitted(intent: Dictionary)

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")

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
@onready var stop_label: Label = $HudRoot/SafeArea/HudLayout/SkillPanel/SkillContent/StopLabel
@onready var rewind_label: Label = $HudRoot/SafeArea/HudLayout/SkillPanel/SkillContent/RewindLabel
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

	var cooldowns := player["cooldowns"] as Dictionary
	stop_label.text = _format_skill("Q", float(cooldowns.get("time_stop", 0.0)))
	rewind_label.text = _format_skill("E", float(cooldowns.get("time_rewind", 0.0)))

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


func _format_skill(label: String, cooldown: float) -> String:
	if cooldown <= 0.0:
		return "%s  %s" % [label, tr("HUD_WEAPON_READY")]
	return "%s  %s" % [label, tr("HUD_WEAPON_COOLDOWN_FMT") % cooldown]


func _format_time(run_time_ms: int) -> String:
	var total_seconds := maxi(0, run_time_ms / 1000)
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]
