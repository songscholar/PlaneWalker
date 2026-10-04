extends Node

const DEFAULT_LOCALE := "zh_CN"
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const FloorRuleEffectAuthorityScript := preload(
	"res://scripts/dungeon/floor_rule_effect_authority.gd"
)
const SettlementScript := preload("res://scripts/progression/run_settlement_authority.gd")

@onready var status_label: Label = $DebugLayer/StatusLabel
@onready var combat_room: Node2D = $CombatRoom01
@onready var start_menu: CanvasLayer = $StartMenu
@onready var start_button: Button = $StartMenu/Panel/Margin/VBox/StartButton
@onready var candidate_button: Button = $StartMenu/Panel/Margin/VBox/CandidateButton
@onready var launch_button: Button = $StartMenu/Panel/Margin/VBox/LaunchButton
@onready var last_run_label: Label = $StartMenu/Panel/Margin/VBox/LastRunLabel
@onready var title_label: Label = $StartMenu/Panel/Margin/VBox/Title
@onready var subtitle_label: Label = $StartMenu/Panel/Margin/VBox/Subtitle
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var runtime_host: Node = $RunRuntimeHost
@onready var dungeon_flow: Node = $DungeonFlow
@onready var launch_room_scene_host: Node = $LaunchRoomSceneHost
@onready var accessibility_runtime: Node = $AccessibilityRuntime
@onready var input_remap_panel: Control = $InputRemapLayer/InputRemapPanel
@onready var accessibility_settings_panel: Control = $AccessibilitySettingsLayer/AccessibilitySettingsPanel
@onready var candidate_loadout_panel: Control = $CandidateLabLayer/CandidateLoadoutPanel
@onready var launch_loadout_panel: Control = $LaunchLoadoutLayer/LaunchLoadoutPanel

var _lang_button: Button
var _floor_rule_effect_authority: RefCounted
var _profile_service: RefCounted
var _profile_error := ""
var _terminal_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_configure_launch_dungeon_runtime()
	_configure_production_profile()
	_apply_locale()
	EventBus.run_ended.connect(_on_run_ended)
	start_button.pressed.connect(_start_new_run)
	candidate_button.pressed.connect(_open_candidate_lab)
	launch_button.pressed.connect(_open_launch_loadout)
	candidate_loadout_panel.connect("candidate_requested", _start_candidate_run)
	launch_loadout_panel.connect("launch_requested", _start_launch_run)
	pause_menu.resume_requested.connect(_resume_run)
	pause_menu.remap_requested.connect(_open_input_remap)
	pause_menu.accessibility_requested.connect(_open_accessibility_settings)
	$RunEndOverlay.hub_return_requested.connect(return_to_hub)
	$RunEndOverlay.configure_profile_return(true)
	combat_room.visible = false
	combat_room.process_mode = Node.PROCESS_MODE_DISABLED
	status_label.visible = false
	_setup_language_button()
	_apply_localization()
	_show_start_menu()
	call_deferred("_apply_accessibility_to_runtime")
	_print_input_map()
	runtime_host.set_run_presentation_visible(false)
	if not _profile_error.is_empty():
		status_label.visible = true
		status_label.text = tr("UI_PROFILE_UNAVAILABLE")


func _configure_production_profile() -> void:
	var activated: Dictionary = GameState.activate_profile_content(runtime_host.content_registry())
	if not activated.ok:
		_profile_error = str(activated.code)
		return
	_profile_service = GameState.profile_runtime_service()
	var registry: RefCounted = runtime_host.content_registry()
	var workshop: Array = registry.get_catalog_entries(&"forge_definition", &"LAUNCH")
	var narrative: Array = registry.get_catalog_entries(&"narrative_definition", &"LAUNCH")
	var sources: Array = registry.get_catalog_entries(&"narrative_source_definition", &"LAUNCH")
	if not _profile_service.enable_workshop(workshop).ok or not _profile_service.enable_narrative(narrative, sources).ok:
		_profile_error = "CONTENT_UNAVAILABLE"


func _configure_launch_dungeon_runtime() -> void:
	_floor_rule_effect_authority = FloorRuleEffectAuthorityScript.new()
	var player := combat_room.get_node_or_null("Player")
	var authority_configured := bool(_floor_rule_effect_authority.call(
		"configure", player, launch_room_scene_host
	))
	var route_adapter_configured := bool(runtime_host.call(
		"configure_route_scene_adapter", launch_room_scene_host
	))
	var effect_authority_configured := bool(runtime_host.call(
		"configure_floor_rule_effect_authority", _floor_rule_effect_authority
	))
	if (
		not authority_configured
		or not route_adapter_configured
		or not effect_authority_configured
	):
		push_error("Launch dungeon runtime configuration failed")


func _apply_locale() -> void:
	TranslationServer.set_locale(str(GameState.get_setting("locale", DEFAULT_LOCALE)))


func _setup_language_button() -> void:
	if _lang_button != null:
		return
	_lang_button = Button.new()
	_lang_button.name = "LanguageButton"
	_lang_button.custom_minimum_size = Vector2(360, 34)
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
	launch_button.text = tr("UI_LAUNCH_LOADOUT")
	if _lang_button != null:
		_lang_button.text = tr("UI_LANG_EN") if str(TranslationServer.get_locale()) == "zh_CN" else tr("UI_LANG_ZH")
	candidate_loadout_panel.call("refresh_localization")
	launch_loadout_panel.call("refresh_localization")


func _unhandled_input(event: InputEvent) -> void:
	if (
		input_remap_panel.visible
		or accessibility_settings_panel.visible
		or candidate_loadout_panel.visible
		or launch_loadout_panel.visible
	):
		return
	if not start_menu.visible and bool(dungeon_flow.call("handle_input", event)):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		_toggle_pause()
		return
	if event.is_action_pressed("interact") and start_menu.visible:
		_start_new_run()
		return
	var phase := int(runtime_host.call("runtime_snapshot").get("phase", RunPhaseScript.Value.HUB))
	if event.is_action_pressed("interact") and RunPhaseScript.is_terminal(phase):
		return_to_hub()


func _start_new_run() -> void:
	if not start_menu.visible:
		return
	_launch_run(_build_run_config(), false)


func _open_candidate_lab() -> void:
	if not start_menu.visible:
		return
	candidate_loadout_panel.call("open_panel", candidate_button)


func _open_launch_loadout() -> void:
	if not start_menu.visible:
		return
	launch_loadout_panel.call("open_panel", launch_button)


func _start_candidate_run(candidate_config: Dictionary) -> void:
	if not start_menu.visible or not candidate_loadout_panel.visible:
		return
	var config := candidate_config.duplicate(true)
	config["seed"] = int(Time.get_unix_time_from_system())
	config["accessibility_assists"] = _accessibility_assists()
	_launch_run(config, true)


func _start_launch_run(launch_config: Dictionary) -> void:
	if not start_menu.visible or not launch_loadout_panel.visible:
		return
	var config := launch_config.duplicate(true)
	config["seed"] = int(Time.get_unix_time_from_system())
	config["accessibility_assists"] = _accessibility_assists()
	_launch_run(config, false, true)


func _launch_run(config: Dictionary, from_candidate: bool, from_launch: bool = false) -> bool:
	if not from_candidate and (_profile_service == null or not _profile_error.is_empty()):
		return false
	get_tree().paused = false
	combat_room.visible = true
	combat_room.process_mode = Node.PROCESS_MODE_PAUSABLE
	var started: Variant
	if from_candidate:
		started = runtime_host.start_run(config)
	elif not _profile_service.snapshot().active_launch_receipt.is_empty():
		started = runtime_host.retry_profile_startup(_profile_service, int(_profile_service.snapshot().revision))
	else:
		started = runtime_host.start_profile_run(config, _profile_service, int(_profile_service.snapshot().revision))
	if not started.ok:
		combat_room.visible = false
		combat_room.process_mode = Node.PROCESS_MODE_DISABLED
		if from_candidate:
			candidate_loadout_panel.call("show_start_rejected")
		elif from_launch:
			launch_loadout_panel.call("show_start_rejected")
		return false
	if not from_candidate:
		var bound: Dictionary = _profile_service.bind_narrative_run(runtime_host.native_run_state(), combat_room.get_node("Player"))
		if not bound.ok:
			_profile_error = str(bound.code)
			combat_room.process_mode = Node.PROCESS_MODE_DISABLED
			return false
		GameState.refresh_profile_state()
	_terminal_pending = false
	runtime_host.set_run_presentation_visible(true)
	if candidate_loadout_panel.visible:
		candidate_loadout_panel.call("close_panel")
	if launch_loadout_panel.visible:
		launch_loadout_panel.call("close_panel")
	FocusCoordinator.close_scope(start_menu)
	start_menu.visible = false
	_on_run_started(runtime_host.runtime_snapshot().config)
	dungeon_flow.call("refresh", true)
	return true


func _build_run_config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "LAUNCH",
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
	FocusCoordinator.link_ring([start_button, candidate_button, launch_button, _lang_button], false)
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


func _on_run_ended(run_id: String, result: Dictionary, _revision: int) -> void:
	var native: Dictionary = runtime_host.runtime_snapshot()
	if native.get("run_id") != run_id or not RunPhaseScript.is_terminal(int(native.get("phase", -1))):
		return
	if _profile_service != null and _profile_service.snapshot().active_launch_receipt.get("run_id") == run_id:
		_terminal_pending = true
		if int(native.phase) == RunPhaseScript.Value.DEFEAT:
			retry_terminal_settlement()
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


func retry_terminal_settlement() -> Dictionary:
	var terminal: Dictionary = runtime_host.runtime_snapshot()
	if _profile_service == null or not RunPhaseScript.is_terminal(int(terminal.get("phase", -1))):
		return {"ok": false, "code": &"INVALID_PHASE", "context": {}}
	var profile: Dictionary = _profile_service.snapshot()
	if profile.active_launch_receipt.is_empty():
		var same: bool = profile.last_settlement_receipt.get("run_id") == terminal.get("run_id")
		return {"ok": same, "code": &"OK" if same else &"INVALID_PHASE", "context": {}}
	if int(terminal.phase) == RunPhaseScript.Value.VICTORY:
		var chosen := false
		var prefix := "ending-choice:%d:" % int(profile.launch_sequence)
		for marker: String in profile.narrative_state.consumed_sources:
			chosen = chosen or marker.begins_with(prefix)
		if not chosen or not profile.narrative_state.heart_fragments.has("heart_fragment_5"):
			return {"ok": false, "code": &"FINAL_CHOICE_PENDING", "context": {}}
	var receipts: Array = []
	for event: Dictionary in terminal.events:
		if event.get("type") == SettlementScript.SOURCE_TYPE:
			receipts.append(event.receipt.duplicate(true))
	var settled: Dictionary = _profile_service.settle_terminal(terminal, receipts, int(profile.revision))
	if settled.ok:
		_terminal_pending = false
		GameState.refresh_profile_state()
	else:
		$RunEndOverlay.show_save_pending()
	return settled


func return_to_hub() -> bool:
	var terminal: Dictionary = runtime_host.runtime_snapshot()
	if not RunPhaseScript.is_terminal(int(terminal.get("phase", -1))):
		return false
	if _terminal_pending:
		if int(terminal.phase) == RunPhaseScript.Value.VICTORY:
			status_label.text = tr("UI_ENDING_PENDING")
			return false
		if not retry_terminal_settlement().ok:
			return false
	get_tree().paused = false
	$RunEndOverlay.hide_overlay()
	combat_room.visible = false
	combat_room.process_mode = Node.PROCESS_MODE_DISABLED
	status_label.visible = false
	runtime_host.set_run_presentation_visible(false)
	_show_start_menu()
	return true


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
