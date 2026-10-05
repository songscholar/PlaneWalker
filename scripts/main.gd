extends Node

const DEFAULT_LOCALE := "zh_CN"
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const FloorRuleEffectAuthorityScript := preload(
	"res://scripts/dungeon/floor_rule_effect_authority.gd"
)
const SettlementScript := preload("res://scripts/progression/run_settlement_authority.gd")
const HubFlowScript := preload("res://scripts/hub/hub_flow_coordinator.gd")
const TutorialFlowScript := preload("res://scripts/onboarding/tutorial_flow_coordinator.gd")
const TrainingFlowScript := preload("res://scripts/training/training_flow_coordinator.gd")
const NarrativeFlowScript := preload("res://scripts/narrative/narrative_flow_coordinator.gd")
const NativeRoomPresentationScript := preload("res://scripts/dungeon/native_room_presentation.gd")
const MusicDirectorScript := preload("res://scripts/audio/music_director.gd")
const ContentManagerScript := preload("res://scripts/expansion/expansion_content_manager.gd")
const ContentManagementPanelScript := preload("res://scripts/ui/content_management_panel.gd")
const StartupDiagnosticScript := preload("res://scripts/operations/packaged_startup_diagnostic.gd")
const LocalRecordsScript := preload("res://scripts/community/local_run_records.gd")
const ContentSnapshotScript := preload("res://scripts/content/content_snapshot_provider.gd")
const BossRushScript := preload("res://scripts/modes/boss_rush_coordinator.gd")
const DailyBossScript := preload("res://scripts/modes/daily_boss_coordinator.gd")

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
var _hub_flow: Node
var _tutorial_flow: Node
var _training_flow: Node2D
var _narrative_flow: Node
var _selected_ending_id := ""
var _credits_pending := false
var _terminal_notice_run_id := ""
var _room_presentation: Node
var _checkpoint_stamp := ""
var _checkpoint_retry_at := 0
var _content_manager: RefCounted
var _content_activation: Dictionary = {}
var _content_panel: Control
var _content_revision := 0
var _content_reload_pending := false
var _last_launch_rejection: Dictionary = {}
var _local_records: RefCounted
var _boss_rush: Node2D
var _daily_boss: Node2D


func _enter_tree() -> void:
	var manager := ContentManagerScript.new()
	var configured: Dictionary = manager.configure(GameState.save_path.get_base_dir().path_join("plane_walker/content"), [{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"EXPANSION", Callable(), _content_mutation_locked)
	if configured.ok:
		_content_manager = manager
		_content_activation = manager.activation_context()
		get_node("RunRuntimeHost").content_pack_specs = _content_activation.pack_specs.duplicate(true)


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
	_setup_hub()
	_setup_tutorial()
	_setup_training()
	_setup_boss_rush()
	_setup_daily_boss()
	_setup_narrative()
	_setup_music()
	_setup_content_management()
	if _hub_flow == null:
		_show_start_menu()
	call_deferred("_apply_accessibility_to_runtime")
	_print_input_map()
	runtime_host.set_run_presentation_visible(false)
	if not _profile_error.is_empty():
		status_label.visible = true
		status_label.text = tr("UI_PROFILE_UNAVAILABLE")
	if "--plane-walker-startup-check" in OS.get_cmdline_user_args():
		call_deferred("_verify_packaged_startup")


func _verify_packaged_startup() -> void:
	var diagnostic := StartupDiagnosticScript.new()
	get_tree().root.add_child(diagnostic)
	diagnostic.verify(self)


func _setup_music() -> void:
	var director := MusicDirectorScript.new()
	director.name = "MusicDirector"
	add_child(director)
	if not director.configure(_music_context):
		director.queue_free()
		push_error("Original music configuration failed")


func _music_context() -> Dictionary:
	var cue_id := "music_hub"
	if _credits_pending:
		cue_id = "music_credits"
	elif _training_flow != null and _training_flow.is_training_active():
		cue_id = "music_training"
	elif _boss_rush != null and _boss_rush.is_open():
		var mode_state: Dictionary = _boss_rush.runtime().snapshot()
		if mode_state.status in ["VICTORY", "DEFEAT"]:
			cue_id = "music_victory" if mode_state.status == "VICTORY" else "music_defeat"
		elif _boss_rush.runtime().is_active():
			cue_id = "music_boss_" + BossRushScript.Catalog.BOSSES[int(mode_state.stage_index)]
	elif _daily_boss != null and _daily_boss.is_open():
		var daily: Dictionary = _daily_boss.runtime().preview()
		if daily.native_active:
			cue_id = "music_boss_" + str(daily.active.definition.boss_id)
		elif not daily.results.is_empty() and daily.active.is_empty():
			cue_id = "music_victory" if daily.results[-1].status == "VICTORY" else "music_defeat"
	elif (_hub_flow == null or not _hub_flow.is_hub_visible()) and combat_room.visible:
		var state: Dictionary = runtime_host.runtime_snapshot()
		var phase := int(state.get("phase", -1))
		if RunPhaseScript.is_terminal(phase):
			cue_id = "music_victory" if phase == RunPhaseScript.Value.VICTORY else "music_defeat"
		else:
			var index := clampi(int(state.get("current_floor_index", 0)), 0, 4)
			var node: Dictionary = runtime_host.native_run_state().current_floor_node() if runtime_host.native_run_state() != null else {}
			cue_id = MusicDirectorScript.BOSS_CUES[index] if node.get("room_type") == "boss" and not node.get("cleared", false) else MusicDirectorScript.FLOOR_CUES[index]
	return {"cue_id": cue_id, "paused": get_tree().paused or _boss_rush != null and _boss_rush.is_open() and _boss_rush.runtime().is_paused() or _daily_boss != null and _daily_boss.is_open() and _daily_boss.runtime().is_paused()}


func _setup_content_management() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ContentManagementLayer"
	layer.layer = 61
	add_child(layer)
	_content_panel = ContentManagementPanelScript.new()
	_content_panel.name = "ContentManagementPanel"
	layer.add_child(_content_panel)
	_content_panel.command_requested.connect(submit_content_command)
	_content_panel.closed.connect(_content_management_closed)


func content_manager() -> RefCounted:
	return _content_manager


func _content_mutation_locked() -> bool:
	if _content_reload_pending or _credits_pending or _training_flow != null and _training_flow.is_training_active() or _boss_rush != null and _boss_rush.is_open() or _daily_boss != null and _daily_boss.is_open():
		return true
	var service: RefCounted = _profile_service if _profile_service != null else GameState.profile_runtime_service()
	if service != null and not service.snapshot().active_launch_receipt.is_empty():
		return true
	var host := get_node_or_null("RunRuntimeHost")
	if host != null and host.is_node_ready():
		var state: Dictionary = host.runtime_snapshot()
		return not str(state.get("run_id", "")).is_empty() and not RunPhaseScript.is_terminal(int(state.get("phase", -1)))
	return false


func open_content_management() -> Dictionary:
	if _content_manager == null or _content_panel == null or _hub_flow == null or not _hub_flow.is_hub_visible() or _credits_pending or _content_reload_pending:
		return {"ok": false, "code": &"INVALID_PHASE", "context": {}}
	_hub_flow.close_panel()
	_hub_flow.scene_host().set_interaction_enabled(false)
	return _refresh_content_panel()


func _refresh_content_panel() -> Dictionary:
	_content_revision += 1
	var discovery: Dictionary = _content_manager.discovery()
	var state := {"run_id": "content-manager", "revision": _content_revision, "epoch": _content_revision, "installed": discovery.installed, "activation": discovery.activation, "locked": _content_mutation_locked(), "diagnostics": discovery.diagnostics, "entitlements": discovery.entitlements}
	var rendered: Variant = _content_panel.render(state)
	return {"ok": rendered.ok, "code": rendered.code, "context": rendered.context.duplicate(true)}


func submit_content_command(operation: String, payload: Dictionary, revision: int) -> Dictionary:
	if _content_manager == null or _content_panel == null or not _content_panel.visible or _hub_flow == null or not _hub_flow.is_hub_visible() or revision != _content_revision or _content_reload_pending:
		return {"ok": false, "code": &"STALE_REVISION", "context": {}}
	if operation == "set_enabled" and get_tree().current_scene != self:
		return {"ok": false, "code": &"NATIVE_SCENE_REQUIRED", "context": {}}
	var before: Dictionary = _content_manager.activation_context()
	var result: Dictionary
	match operation:
		"install":
			result = _content_manager.install(str(payload.get("path", "")))
		"set_enabled":
			result = _content_manager.set_enabled(payload.get("ids", []) if payload.get("ids") is Array else [null])
		"uninstall":
			result = _content_manager.uninstall(str(payload.get("id", "")))
		"refresh":
			result = _content_manager.refresh()
		"cancel":
			result = {"ok": true, "code": &"OK", "context": {}}
		_:
			result = {"ok": false, "code": &"INVALID_ARGUMENT", "context": {}}
	if result.ok and _content_manager.activation_context() != before:
		_content_reload_pending = true
		_content_panel.close_panel()
		call_deferred("_reload_content_scene")
	else:
		_refresh_content_panel()
		if not result.ok:
			_content_panel.show_rejection("UI_CONTENT_REJECTED")
	return result.duplicate(true)


func _reload_content_scene() -> void:
	if not _content_reload_pending or get_tree().current_scene != self:
		return
	var error := get_tree().reload_current_scene()
	if error != OK:
		push_error("Content selection retained, native scene reload failed: %s" % error_string(error))


func _content_management_closed() -> void:
	if _hub_flow != null and _hub_flow.is_hub_visible() and not _content_reload_pending:
		_hub_flow.refresh()


func _setup_hub() -> void:
	if _profile_service == null or not _profile_error.is_empty():
		return
	var hub := HubFlowScript.new()
	hub.name = "HubFlowCoordinator"
	add_child(hub)
	var providers: Dictionary = {"leaderboard": _local_records.provider_row} if _local_records != null else {}
	var configured: Dictionary = hub.configure(runtime_host.content_registry(), _profile_service, providers)
	if not configured.ok:
		_profile_error = str(configured.code)
		hub.queue_free()
		return
	_hub_flow = hub
	hub.launch_requested.connect(_start_hub_run)
	hub.resume_requested.connect(_start_hub_run)
	hub.tutorial_requested.connect(_open_hub_tutorial)
	hub.boss_rush_requested.connect(_open_boss_rush)
	hub.daily_boss_requested.connect(_open_daily_boss)
	hub.settings_requested.connect(_open_hub_setting)
	start_menu.visible = false
	FocusCoordinator.close_scope(start_menu)
	hub.show_hub()


func _setup_tutorial() -> void:
	if _profile_service == null or not _profile_error.is_empty():
		return
	var flow := TutorialFlowScript.new()
	flow.name = "TutorialFlow"
	add_child(flow)
	var configured: Dictionary = flow.configure(runtime_host.content_registry(), _profile_service, runtime_host, combat_room.get_node("Player"), input_remap_panel.get("_service"))
	if not configured.ok:
		_profile_error = str(configured.code)
		flow.queue_free()
		return
	_tutorial_flow = flow
	flow.review_panel().closed.connect(_refresh_hub_after_review)
	flow.training_requested.connect(_start_hub_training)


func _setup_training() -> void:
	if _profile_service == null or not _profile_error.is_empty():
		return
	var flow := TrainingFlowScript.new()
	flow.name = "TrainingFlow"
	add_child(flow)
	var configured: Dictionary = flow.configure(runtime_host.content_registry(), _profile_service)
	if not configured.ok:
		_profile_error = str(configured.code)
		flow.queue_free()
		return
	_training_flow = flow
	flow.closed.connect(_on_training_closed)


func _setup_boss_rush() -> void:
	if _profile_service == null or not _profile_error.is_empty():
		return
	var coordinator := BossRushScript.new()
	coordinator.name = "BossRushCoordinator"
	add_child(coordinator)
	var configured: Dictionary = coordinator.configure(runtime_host.content_registry(), _profile_service, GameState.save_path.get_base_dir().path_join("plane_walker/challenges"))
	if not configured.ok:
		coordinator.queue_free()
		return
	_boss_rush = coordinator
	coordinator.closed.connect(_on_training_closed)


func _open_boss_rush(config: Dictionary) -> void:
	if _boss_rush == null or _hub_flow == null or not _hub_flow.is_hub_visible() or not _profile_service.snapshot().active_launch_receipt.is_empty():
		return
	var request := {"character_id": config.character_id, "weapon_id": config.weapon_id, "time_abilities": config.enabled_time_skills.duplicate(), "seed": 20261005, "accessibility_assists": {"damage_received_multiplier": float(GameState.persistent.settings.damage_received_multiplier), "enemy_telegraph_scale": float(GameState.persistent.settings.enemy_telegraph_scale)}}
	if _boss_rush.open(request).ok:
		_hub_flow.close_panel()
		_hub_flow.hide_hub()


func _setup_daily_boss() -> void:
	if _profile_service == null or not _profile_error.is_empty():
		return
	var coordinator := DailyBossScript.new()
	coordinator.name = "DailyBossCoordinator"
	add_child(coordinator)
	var configured: Dictionary = coordinator.configure(runtime_host.content_registry(), _profile_service, GameState.save_path.get_base_dir().path_join("plane_walker/daily"))
	if not configured.ok:
		coordinator.queue_free()
		return
	_daily_boss = coordinator
	coordinator.closed.connect(_on_training_closed)


func _open_daily_boss() -> void:
	if _daily_boss == null or _hub_flow == null or not _hub_flow.is_hub_visible() or not _profile_service.snapshot().active_launch_receipt.is_empty():
		return
	if _daily_boss.open().ok:
		_hub_flow.close_panel()
		_hub_flow.hide_hub()


func _start_hub_training(task_id: StringName, expected_revision: int) -> bool:
	if _training_flow == null or _hub_flow == null or not _hub_flow.is_hub_visible() or _credits_pending or not _profile_error.is_empty():
		return false
	var profile: Dictionary = _profile_service.snapshot()
	if int(profile.revision) != expected_revision or not profile.active_launch_receipt.is_empty():
		return false
	var opened: Dictionary = _training_flow.open(str(task_id))
	if not opened.ok:
		return false
	_tutorial_flow.close()
	_hub_flow.hide_hub()
	return true


func _on_training_closed() -> void:
	GameState.refresh_profile_state()
	if _hub_flow != null:
		_hub_flow.show_hub()


func _setup_narrative() -> void:
	if _profile_service == null or not _profile_error.is_empty():
		return
	var occurrences := Node2D.new()
	occurrences.name = "NarrativeOccurrences"
	add_child(occurrences)
	var flow := NarrativeFlowScript.new()
	flow.name = "NarrativeFlow"
	add_child(flow)
	var configured: Dictionary = flow.configure(runtime_host.content_registry(), _profile_service, runtime_host, launch_room_scene_host, combat_room.get_node("Player"), occurrences)
	if not configured.ok:
		_profile_error = str(configured.code)
		flow.queue_free()
		occurrences.queue_free()
		return
	_narrative_flow = flow
	flow.ending_selected.connect(_on_ending_selected)
	flow.credits_completed.connect(_on_credits_completed)
	var resumed: Dictionary = flow.resume_selected_credits()
	if resumed.ok and resumed.context.get("resumed", false):
		_selected_ending_id = str(flow.panel().view_state().subject_id)
		_credits_pending = true
		if _hub_flow != null:
			_hub_flow.hide_hub()


func _refresh_hub_after_review() -> void:
	if _hub_flow != null and _hub_flow.is_hub_visible():
		_hub_flow.refresh()


func _open_hub_tutorial() -> void:
	if _tutorial_flow != null and _hub_flow != null and _hub_flow.is_hub_visible():
		_hub_flow.close_panel()
		_tutorial_flow.open_review()


func _start_hub_run(config: Dictionary) -> void:
	if _hub_flow == null or not _hub_flow.is_hub_visible():
		return
	if not _launch_run(config, false, true):
		_hub_flow.show_launch_rejection()


func _open_hub_setting(kind: String, restore_focus: Control) -> void:
	match kind:
		"accessibility":
			accessibility_settings_panel.open_panel(restore_focus)
		"input":
			input_remap_panel.open_panel(restore_focus)
		"language":
			_toggle_language()
		"content":
			open_content_management()


func _configure_production_profile() -> void:
	var activated: Dictionary = GameState.activate_profile_content(runtime_host.content_registry(), str(_content_activation.get("save_domain", "base")))
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
		return
	var records := LocalRecordsScript.new()
	var records_configured := records.configure(_profile_service, GameState.save_path.get_base_dir().path_join("plane_walker/local_records"), "0.4.0-dev", ContentSnapshotScript.snapshot(registry), str(_content_activation.get("save_domain", "base")))
	if records_configured.ok:
		_local_records = records
		_sync_local_records()


func _sync_local_records() -> Dictionary:
	return _local_records.sync_settled_run() if _local_records != null else {"ok": false, "code": &"PROVIDER_UNAVAILABLE", "context": {}}


func _configure_launch_dungeon_runtime() -> void:
	_room_presentation = NativeRoomPresentationScript.new()
	_room_presentation.name = "NativeRoomPresentation"
	add_child(_room_presentation)
	if not _room_presentation.configure(runtime_host, launch_room_scene_host, combat_room):
		push_error("Native room presentation configuration failed")
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
	if start_menu.visible:
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
	if _daily_boss != null and _daily_boss.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if _boss_rush != null and _boss_rush.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if _training_flow != null and _training_flow.is_training_active():
		return
	if (
		input_remap_panel.visible
		or accessibility_settings_panel.visible
		or candidate_loadout_panel.visible
		or launch_loadout_panel.visible
	):
		return
	if _tutorial_flow != null and _tutorial_flow.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if _narrative_flow != null and _narrative_flow.panel().visible:
		return
	if _hub_flow != null and _hub_flow.is_hub_visible():
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
	if _credits_pending or _content_reload_pending or _content_panel != null and _content_panel.visible:
		return false
	if not from_candidate and (_profile_service == null or not _profile_error.is_empty()):
		return false
	config = config.duplicate(true)
	if not from_candidate and str(_content_activation.get("save_domain", "base")) != "base":
		config.milestone = "EXPANSION"
	get_tree().paused = false
	combat_room.visible = true
	combat_room.process_mode = Node.PROCESS_MODE_PAUSABLE
	var pending_config: Dictionary = _profile_service.pending_launch_config() if not from_candidate else {}
	var effective_config := pending_config if not pending_config.is_empty() else config
	_room_presentation.set_launch_mode(str(effective_config.get("milestone", "")) in ["LAUNCH", "EXPANSION"])
	var was_in_hub: bool = _hub_flow != null and _hub_flow.is_hub_visible()
	if was_in_hub:
		_hub_flow.hide_hub()
	var started: Variant
	if from_candidate:
		started = runtime_host.start_run(config)
	elif not _profile_service.snapshot().active_launch_receipt.is_empty():
		if not _profile_service.payload().get("native_run_checkpoint", {}).is_empty():
			started = runtime_host.restore_profile_checkpoint(_profile_service, int(_profile_service.snapshot().revision))
		else:
			started = runtime_host.retry_profile_startup(_profile_service, int(_profile_service.snapshot().revision))
	else:
		started = runtime_host.start_profile_run(config, _profile_service, int(_profile_service.snapshot().revision))
	if not started.ok:
		_last_launch_rejection = {"code": started.code, "context": started.context.duplicate(true)}
		combat_room.visible = false
		combat_room.process_mode = Node.PROCESS_MODE_DISABLED
		_room_presentation.set_launch_mode(false)
		if was_in_hub:
			_hub_flow.show_hub()
		if from_candidate:
			candidate_loadout_panel.call("show_start_rejected")
		elif from_launch:
			launch_loadout_panel.call("show_start_rejected")
		return false
	_last_launch_rejection.clear()
	_room_presentation.set_launch_mode(str(runtime_host.runtime_snapshot().config.get("milestone", "")) in ["LAUNCH", "EXPANSION"])
	_room_presentation.synchronize_active_room(bool(started.context.get("restored", false)))
	if not from_candidate:
		var bound: Dictionary = _narrative_flow.bind_active_run() if _narrative_flow != null else {"ok": false, "code": &"NARRATIVE_NOT_CONFIGURED"}
		if not bound.ok:
			_profile_error = str(bound.code)
			combat_room.process_mode = Node.PROCESS_MODE_DISABLED
			return false
		GameState.refresh_profile_state()
		if _tutorial_flow != null:
			var tutorial_bound: Dictionary = _tutorial_flow.bind_active_run()
			if not tutorial_bound.ok:
				_profile_error = str(tutorial_bound.code)
				combat_room.process_mode = Node.PROCESS_MODE_DISABLED
				return false
	_terminal_pending = false
	_selected_ending_id = ""
	_terminal_notice_run_id = ""
	runtime_host.set_process(true)
	runtime_host.set_run_presentation_visible(true)
	if candidate_loadout_panel.visible:
		candidate_loadout_panel.call("close_panel")
	if launch_loadout_panel.visible:
		launch_loadout_panel.call("close_panel")
	FocusCoordinator.close_scope(start_menu)
	start_menu.visible = false
	_on_run_started(runtime_host.runtime_snapshot().config)
	status_label.visible = from_candidate
	if bool(started.context.get("restored", false)):
		var presented: Variant = runtime_host.present_restored_checkpoint(func(): dungeon_flow.refresh(true))
		if not presented.ok:
			_profile_error = str(presented.code)
			combat_room.process_mode = Node.PROCESS_MODE_DISABLED
			return false
	else:
		dungeon_flow.refresh(true)
	_checkpoint_stamp = ""
	if not from_candidate:
		if bool(started.context.get("restored", false)):
			_checkpoint_stamp = _native_checkpoint_stamp()
		else:
			checkpoint_current_run()
	var snapshot: Dictionary = runtime_host.runtime_snapshot()
	if RunPhaseScript.is_terminal(int(snapshot.phase)):
		_on_run_ended(str(snapshot.run_id), snapshot.result, int(snapshot.revision))
	return true


func checkpoint_current_run() -> Dictionary:
	if _profile_service == null or _profile_service.snapshot().active_launch_receipt.is_empty() or runtime_host.runtime_snapshot().get("run_id") != _profile_service.snapshot().active_launch_receipt.get("run_id"):
		return {"ok": false, "code": &"INVALID_PHASE", "context": {}}
	var result: Variant = runtime_host.checkpoint_profile_run(int(_profile_service.snapshot().revision))
	if result.ok:
		_checkpoint_stamp = _native_checkpoint_stamp()
		_checkpoint_retry_at = 0
		GameState.refresh_profile_state()
	elif result.code not in [&"CHECKPOINT_UNSAFE", &"NATIVE_CHECKPOINT_UNSAFE", &"INVALID_PHASE"]:
		_checkpoint_retry_at = Time.get_ticks_msec() + 2000
	return {"ok": result.ok, "code": result.code, "context": result.context.duplicate(true)}


func _native_checkpoint_stamp() -> String:
	var state: Dictionary = runtime_host.runtime_snapshot()
	return "%s:%s:%s:%s:%s:%s" % [state.get("run_id", ""), state.get("revision", -1), state.get("phase", -1), state.get("floor_plan", {}).get("floor_id", ""), state.get("floor_plan", {}).get("current_node_id", ""), state.get("events", []).size()]


func _process(_delta: float) -> void:
	if _profile_service == null or _credits_pending or _hub_flow == null or _hub_flow.is_hub_visible() or _profile_service.snapshot().active_launch_receipt.is_empty():
		return
	var stamp := _native_checkpoint_stamp()
	if stamp == _checkpoint_stamp or _checkpoint_retry_at > Time.get_ticks_msec():
		return
	var result := checkpoint_current_run()
	if result.code in [&"CHECKPOINT_UNSAFE", &"NATIVE_CHECKPOINT_UNSAFE", &"INVALID_PHASE"]:
		_checkpoint_stamp = stamp


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
	if _terminal_notice_run_id == run_id:
		return
	_terminal_notice_run_id = run_id
	if _tutorial_flow != null:
		_tutorial_flow.close()
		_tutorial_flow.retire_active_run()
	var profile_run: bool = _profile_service != null and _profile_service.snapshot().active_launch_receipt.get("run_id") == run_id
	if profile_run:
		_terminal_pending = true
		if int(native.phase) == RunPhaseScript.Value.DEFEAT:
			retry_terminal_settlement()
	get_tree().paused = false
	combat_room.process_mode = Node.PROCESS_MODE_DISABLED
	runtime_host.set_process(false)
	pause_menu.hide_pause()
	dungeon_flow.refresh(true)
	if profile_run and int(native.phase) == RunPhaseScript.Value.VICTORY and _narrative_flow != null:
		$RunEndOverlay.hide_overlay()
		runtime_host.set_run_presentation_visible(false)
		status_label.visible = false
		var narrative: Dictionary = _narrative_flow.terminal_victory()
		if not narrative.ok:
			status_label.visible = true
			status_label.text = tr("UI_NARRATIVE_SAVE_RETRY")
		return
	status_label.visible = true
	var snapshot: Dictionary = runtime_host.call("runtime_snapshot")
	status_label.text = "%s\n%s: %s\n%s: %s\n%s: %s" % [
		tr("UI_RUN_ENDED"),
		tr("UI_RESULT"), _result_label(str(result.get("result", "death"))),
		tr("UI_ROOMS_CLEARED"), str(result.get("rooms_cleared", 0)),
		tr("UI_REWARDS"), str((snapshot.get("build", {}) as Dictionary).get("items", [])),
	]
	print("Run ended: ", result)


func _on_ending_selected(ending_id: String, _receipt: Dictionary) -> void:
	if _profile_service == null or _saved_ending_id() != ending_id or int(runtime_host.runtime_snapshot().get("phase", -1)) != RunPhaseScript.Value.VICTORY:
		return
	_selected_ending_id = ending_id
	GameState.refresh_profile_state()
	_continue_victory()


func _saved_ending_id() -> String:
	if _profile_service == null:
		return ""
	var profile: Dictionary = _profile_service.snapshot()
	var receipt: Dictionary = profile.active_launch_receipt if not profile.active_launch_receipt.is_empty() else profile.last_settlement_receipt
	if receipt.is_empty():
		return ""
	var prefix := "ending-choice:%d:" % int(receipt.sequence)
	for marker: String in profile.narrative_state.consumed_sources:
		if marker.begins_with(prefix):
			return marker.substr(prefix.length())
	return ""


func _continue_victory() -> bool:
	var ending_id := _saved_ending_id()
	if ending_id.is_empty() or _narrative_flow == null:
		return false
	_selected_ending_id = ending_id
	var settled := retry_terminal_settlement()
	if not settled.ok:
		$RunEndOverlay.show_victory_save_retry()
		return false
	var credits: Dictionary = _narrative_flow.show_selected_credits(ending_id)
	if not credits.ok:
		$RunEndOverlay.show_victory_save_retry()
		return false
	_credits_pending = true
	$RunEndOverlay.hide_overlay()
	status_label.visible = false
	return true


func _on_credits_completed(ending_id: String, _receipt: Dictionary) -> void:
	if _profile_service == null or not _credits_pending or ending_id != _selected_ending_id or _saved_ending_id() != ending_id:
		return
	if not _profile_service.snapshot().narrative_state.credits_completed.has(ending_id):
		return
	_credits_pending = false
	_narrative_flow.retire_active_run()
	GameState.refresh_profile_state()
	_show_hub_after_run()


func retry_terminal_settlement() -> Dictionary:
	var terminal: Dictionary = runtime_host.runtime_snapshot()
	if _profile_service == null or not RunPhaseScript.is_terminal(int(terminal.get("phase", -1))):
		return {"ok": false, "code": &"INVALID_PHASE", "context": {}}
	var profile: Dictionary = _profile_service.snapshot()
	if profile.active_launch_receipt.is_empty():
		var same: bool = profile.last_settlement_receipt.get("run_id") == terminal.get("run_id")
		if same:
			_sync_local_records()
		return {"ok": same, "code": &"OK" if same else &"INVALID_PHASE", "context": {}}
	if int(terminal.phase) == RunPhaseScript.Value.VICTORY:
		var chosen := false
		var prefix := "ending-choice:%d:" % int(profile.launch_sequence)
		for marker: String in profile.narrative_state.consumed_sources:
			chosen = chosen or marker.begins_with(prefix)
		if not chosen or not profile.narrative_state.heart_fragments.has("floor_throne_of_void") or not profile.narrative_state.consumed_sources.has("source:heart_fragment_5"):
			return {"ok": false, "code": &"FINAL_CHOICE_PENDING", "context": {}}
	var receipts: Array = []
	for event: Dictionary in terminal.events:
		if event.get("type") == SettlementScript.SOURCE_TYPE:
			receipts.append(event.receipt.duplicate(true))
	var settled: Dictionary = _profile_service.settle_terminal(terminal, receipts, int(profile.revision))
	if settled.ok:
		_terminal_pending = false
		GameState.refresh_profile_state()
		_sync_local_records()
	else:
		$RunEndOverlay.show_save_pending()
	return settled


func return_to_hub() -> bool:
	if _credits_pending:
		return false
	var terminal: Dictionary = runtime_host.runtime_snapshot()
	if not RunPhaseScript.is_terminal(int(terminal.get("phase", -1))):
		return false
	if _terminal_pending:
		if int(terminal.phase) == RunPhaseScript.Value.VICTORY:
			_continue_victory()
			return false
		if not retry_terminal_settlement().ok:
			return false
	if int(terminal.phase) == RunPhaseScript.Value.VICTORY and not _saved_ending_id().is_empty() and not _profile_service.snapshot().narrative_state.credits_completed.has(_saved_ending_id()):
		_continue_victory()
		return false
	if _narrative_flow != null:
		_narrative_flow.retire_active_run()
	_show_hub_after_run()
	return true


func _show_hub_after_run() -> void:
	_sync_local_records()
	get_tree().paused = false
	_room_presentation.set_launch_mode(false)
	$RunEndOverlay.hide_overlay()
	combat_room.visible = false
	combat_room.process_mode = Node.PROCESS_MODE_DISABLED
	status_label.visible = false
	runtime_host.set_run_presentation_visible(false)
	if _hub_flow != null:
		_hub_flow.show_hub()
	else:
		_show_start_menu()


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
	checkpoint_current_run()
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
