extends Node

const DEFAULT_LOCALE := "zh_CN"
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")

@onready var status_label: Label = $DebugLayer/StatusLabel
@onready var combat_room: Node2D = $CombatRoom01
@onready var start_menu: CanvasLayer = $StartMenu
@onready var start_button: Button = $StartMenu/Panel/Margin/VBox/StartButton
@onready var candidate_button: Button = $StartMenu/Panel/Margin/VBox/CandidateButton
@onready var last_run_label: Label = $StartMenu/Panel/Margin/VBox/LastRunLabel
@onready var title_label: Label = $StartMenu/Panel/Margin/VBox/Title
@onready var subtitle_label: Label = $StartMenu/Panel/Margin/VBox/Subtitle
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var runtime_host: Node = $RunRuntimeHost
@onready var accessibility_runtime: Node = $AccessibilityRuntime
@onready var input_remap_panel: Control = $InputRemapLayer/InputRemapPanel
@onready var accessibility_settings_panel: Control = $AccessibilitySettingsLayer/AccessibilitySettingsPanel
@onready var candidate_loadout_panel: Control = $CandidateLabLayer/CandidateLoadoutPanel

var _lang_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_locale()
	EventBus.run_ended.connect(_on_run_ended)
	start_button.pressed.connect(_start_new_run)
	candidate_button.pressed.connect(_open_candidate_lab)
	candidate_loadout_panel.connect("candidate_requested", _start_candidate_run)
	pause_menu.resume_requested.connect(_resume_run)
	pause_menu.remap_requested.connect(_open_input_remap)
	pause_menu.accessibility_requested.connect(_open_accessibility_settings)
	combat_room.visible = false
	combat_room.process_mode = Node.PROCESS_MODE_DISABLED
	status_label.visible = false
	_setup_language_button()
	_apply_localization()
	_show_start_menu()
	call_deferred("_apply_accessibility_to_runtime")
	_print_input_map()


func _apply_locale() -> void:
	TranslationServer.set_locale(str(GameState.get_setting("locale", DEFAULT_LOCALE)))


func _setup_language_button() -> void:
	if _lang_button != null:
		return
	_lang_button = Button.new()
	_lang_button.name = "LanguageButton"
	_lang_button.custom_minimum_size = Vector2(360, 40)
	_lang_button.focus_mode = Control.FOCUS_ALL
	_lang_button.pressed.connect(_toggle_language)
	start_button.get_parent().add_child(_lang_button)


func _toggle_language() -> void:
	var next_locale := "en" if str(TranslationServer.get_locale()) == "zh_CN" else "zh_CN"
	GameState.set_setting("locale", next_locale)
	TranslationServer.set_locale(next_locale)
	_apply_localization()
	_show_start_menu()


func _apply_localization() -> void:
	title_label.text = tr("UI_TITLE")
	subtitle_label.text = tr("UI_SUBTITLE")
	start_button.text = tr("UI_QUICK_START")
	candidate_button.text = tr("UI_CANDIDATE_LAB")
	if _lang_button != null:
		_lang_button.text = tr("UI_LANG_EN") if str(TranslationServer.get_locale()) == "zh_CN" else tr("UI_LANG_ZH")
	candidate_loadout_panel.call("refresh_localization")


func _unhandled_input(event: InputEvent) -> void:
	if input_remap_panel.visible or accessibility_settings_panel.visible or candidate_loadout_panel.visible:
		return
	if event.is_action_pressed("pause"):
		_toggle_pause()
		return
	if event.is_action_pressed("interact") and start_menu.visible:
		_start_new_run()
		return
	var phase := int(runtime_host.call("runtime_snapshot").get("phase", RunPhaseScript.Value.HUB))
	if event.is_action_pressed("interact") and RunPhaseScript.is_terminal(phase):
		get_tree().paused = false
		get_tree().reload_current_scene()


func _start_new_run() -> void:
	if not start_menu.visible:
		return
	_launch_run(_build_run_config(), false)


func _open_candidate_lab() -> void:
	if not start_menu.visible:
		return
	candidate_loadout_panel.call("open_panel", candidate_button)


func _start_candidate_run(candidate_config: Dictionary) -> void:
	if not start_menu.visible or not candidate_loadout_panel.visible:
		return
	var config := candidate_config.duplicate(true)
	config["seed"] = int(Time.get_unix_time_from_system())
	config["accessibility_assists"] = _accessibility_assists()
	_launch_run(config, true)


func _launch_run(config: Dictionary, from_candidate: bool) -> bool:
	get_tree().paused = false
	combat_room.visible = true
	combat_room.process_mode = Node.PROCESS_MODE_PAUSABLE
	var started = runtime_host.call("start_run", config)
	if not started.ok:
		combat_room.visible = false
		combat_room.process_mode = Node.PROCESS_MODE_DISABLED
		if from_candidate:
			candidate_loadout_panel.call("show_start_rejected")
		return false
	if candidate_loadout_panel.visible:
		candidate_loadout_panel.call("close_panel")
	FocusCoordinator.close_scope(start_menu)
	start_menu.visible = false
	_on_run_started(config)
	return true


func _build_run_config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": int(Time.get_unix_time_from_system()),
		"accessibility_assists": _accessibility_assists(),
	}


func _accessibility_assists() -> Dictionary:
	var settings := GameState.normalized_settings()
	return {
		"damage_received_multiplier": float(settings.get("damage_received_multiplier", 1.0)),
		"enemy_telegraph_scale": float(settings.get("enemy_telegraph_scale", 1.0)),
	}


func _show_start_menu() -> void:
	start_menu.visible = true
	FocusCoordinator.link_ring([start_button, candidate_button, _lang_button], false)
	FocusCoordinator.open_scope(start_menu, start_button)
	var summary: Dictionary = GameState.persistent.get("last_run_summary", {})
	if summary.is_empty():
		last_run_label.text = tr("UI_NO_RUNS")
		return
	last_run_label.text = tr("UI_LAST_RUN_FMT") % [
		_result_label(str(summary.get("result", "death"))),
		int(GameState.persistent.get("best_rooms_cleared", 0)),
		int(GameState.persistent.get("runs_completed", 0)),
	]


func _result_label(result: String) -> String:
	return tr("RESULT_" + result.to_upper())


func _on_run_started(run_data: Dictionary) -> void:
	_apply_run_accessibility_assists(run_data)
	var snapshot: Dictionary = runtime_host.call("runtime_snapshot")
	status_label.visible = true
	var text := tr("UI_STATUS_HEADER") + "\n"
	text += tr("UI_STATUS_PHASE_FMT") % _phase_name(int(snapshot.get("phase", -1))) + "\n"
	text += tr("UI_STATUS_CHARACTER_FMT") % run_data.get("character_id", "") + "\n"
	text += tr("UI_STATUS_WEAPON_FMT") % run_data.get("weapon_id", "") + "\n"
	text += tr("UI_STATUS_SEED_FMT") % int(snapshot.get("run_seed", 0)) + "\n\n"
	text += tr("UI_STATUS_INPUT_HEADER") + "\n"
	text += tr("UI_STATUS_INPUT_MOVE") + "\n"
	text += tr("UI_STATUS_INPUT_ATTACK") + "\n"
	text += tr("UI_STATUS_INPUT_TIME") + "\n"
	text += tr("UI_STATUS_BOSS_HINT")
	status_label.text = text
	print("Run started: ", run_data)


func _apply_run_accessibility_assists(run_data: Dictionary) -> void:
	var player_health := combat_room.get_node_or_null("Player/HealthComponent")
	if player_health == null or not player_health.has_method("configure_accessibility_assists"):
		return
	var assists_value: Variant = run_data.get("accessibility_assists", {})
	var assists: Dictionary = assists_value.duplicate(true) if assists_value is Dictionary else {}
	player_health.call("configure_accessibility_assists", assists)


func _on_run_ended(_run_id: String, result: Dictionary, _revision: int) -> void:
	GameState.record_run_summary(result)
	get_tree().paused = false
	combat_room.process_mode = Node.PROCESS_MODE_DISABLED
	pause_menu.hide_pause()
	status_label.visible = true
	var snapshot: Dictionary = runtime_host.call("runtime_snapshot")
	status_label.text = "%s\n%s: %s\n%s: %s\n%s: %s" % [
		tr("UI_RUN_ENDED"),
		tr("UI_RESULT"), _result_label(str(result.get("result", "death"))),
		tr("UI_ROOMS_CLEARED"), str(result.get("rooms_cleared", 0)),
		tr("UI_REWARDS"), str((snapshot.get("build", {}) as Dictionary).get("items", [])),
	]
	print("Run ended: ", result)


func _toggle_pause() -> void:
	if get_tree().paused:
		_resume_run()
	else:
		_pause_run()


func _pause_run() -> void:
	var snapshot: Dictionary = runtime_host.call("runtime_snapshot")
	var phase := int(snapshot.get("phase", RunPhaseScript.Value.HUB))
	if phase == RunPhaseScript.Value.HUB or RunPhaseScript.is_terminal(phase):
		return
	var paused = runtime_host.call("pause_run")
	if not paused.ok:
		return
	get_tree().paused = true
	pause_menu.show_pause()


func _resume_run() -> void:
	if not get_tree().paused:
		return
	var resumed = runtime_host.call("resume_run")
	if not resumed.ok:
		return
	get_tree().paused = false
	pause_menu.hide_pause()


func _open_input_remap() -> void:
	input_remap_panel.call("open_panel", pause_menu.remap_button)


func _open_accessibility_settings() -> void:
	accessibility_settings_panel.call("open_panel", pause_menu.settings_button)


func _apply_accessibility_to_runtime() -> void:
	accessibility_runtime.call("apply_to_tree", self)


func _print_input_map() -> void:
	var actions := [
		"move_up",
		"move_down",
		"move_left",
		"move_right",
		"attack",
		"heavy_attack",
		"ranged_attack",
		"dash",
		"time_stop",
		"time_rewind",
		"time_rift",
		"time_accelerate",
		"interact",
		"pause",
	]
	for action: String in actions:
		print("Input action '%s' events: %s" % [action, InputMap.action_get_events(action)])


func _phase_name(phase: int) -> String:
	match phase:
		RunPhaseScript.Value.BOOT:
			return tr("PHASE_BOOT")
		RunPhaseScript.Value.HUB:
			return tr("PHASE_HUB")
		RunPhaseScript.Value.RUN_PREPARING:
			return tr("PHASE_RUN_START")
		RunPhaseScript.Value.ROOM_ENTERING, RunPhaseScript.Value.COMBAT_ACTIVE:
			return tr("PHASE_DUNGEON")
		RunPhaseScript.Value.ROOM_RESOLVING:
			return tr("PHASE_ROOM_CLEAR")
		RunPhaseScript.Value.SELECTION_ACTIVE, RunPhaseScript.Value.ROOM_TRANSITION:
			return tr("PHASE_SELECTION")
		RunPhaseScript.Value.BOSS_ACTIVE:
			return tr("PHASE_BOSS_FIGHT")
		RunPhaseScript.Value.DEFEAT:
			return tr("PHASE_DEATH")
		RunPhaseScript.Value.VICTORY:
			return tr("PHASE_RUN_END")
		_:
			return "UNKNOWN"
