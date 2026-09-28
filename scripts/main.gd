extends Node

const DEFAULT_LOCALE := "zh_CN"

@onready var status_label: Label = $DebugLayer/StatusLabel
@onready var combat_room: Node2D = $CombatRoom01
@onready var start_menu: CanvasLayer = $StartMenu
@onready var start_button: Button = $StartMenu/Panel/Margin/VBox/StartButton
@onready var last_run_label: Label = $StartMenu/Panel/Margin/VBox/LastRunLabel
@onready var title_label: Label = $StartMenu/Panel/Margin/VBox/Title
@onready var subtitle_label: Label = $StartMenu/Panel/Margin/VBox/Subtitle
@onready var pause_menu: CanvasLayer = $PauseMenu

var _phase_before_pause: GameState.GamePhase = GameState.GamePhase.DUNGEON
var _lang_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_locale()
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	start_button.pressed.connect(_start_new_run)
	pause_menu.resume_requested.connect(_resume_run)
	combat_room.visible = false
	combat_room.process_mode = Node.PROCESS_MODE_DISABLED
	status_label.visible = false
	GameState.set_phase(GameState.GamePhase.HUB)
	_setup_language_button()
	_apply_localization()
	_show_start_menu()
	_print_input_map()


func _apply_locale() -> void:
	TranslationServer.set_locale(str(GameState.get_setting("locale", DEFAULT_LOCALE)))


func _setup_language_button() -> void:
	if _lang_button != null:
		return
	_lang_button = Button.new()
	_lang_button.custom_minimum_size = Vector2(360, 40)
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
	if _lang_button != null:
		_lang_button.text = tr("UI_LANG_EN") if str(TranslationServer.get_locale()) == "zh_CN" else tr("UI_LANG_ZH")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		return
	if event.is_action_pressed("interact") and GameState.phase == GameState.GamePhase.DEATH:
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed("interact") and GameState.phase == GameState.GamePhase.HUB:
		_start_new_run()
		return
	if event.is_action_pressed("interact"):
		EventBus.room_started.emit(&"debug_room_01")
		EventBus.publish(EventBus.ROOM_STARTED, {"room_id": "debug_room_01"})
		print("Debug room_started emitted.")


func _start_new_run() -> void:
	if not start_menu.visible:
		return
	get_tree().paused = false
	start_menu.visible = false
	combat_room.visible = true
	combat_room.process_mode = Node.PROCESS_MODE_INHERIT
	GameState.start_run({
		"character_id": "wanderer",
		"weapon_id": "sword",
		"difficulty": "normal",
	})
	if combat_room.has_method("begin_run"):
		combat_room.begin_run()


func _show_start_menu() -> void:
	start_menu.visible = true
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
	status_label.visible = true
	var text := tr("UI_STATUS_HEADER") + "\n"
	text += tr("UI_STATUS_PHASE_FMT") % _phase_name(GameState.phase) + "\n"
	text += tr("UI_STATUS_CHARACTER_FMT") % run_data.get("character_id", "") + "\n"
	text += tr("UI_STATUS_WEAPON_FMT") % run_data.get("weapon_id", "") + "\n"
	text += tr("UI_STATUS_SEED_FMT") % GameState.run_seed + "\n\n"
	text += tr("UI_STATUS_INPUT_HEADER") + "\n"
	text += tr("UI_STATUS_INPUT_MOVE") + "\n"
	text += tr("UI_STATUS_INPUT_ATTACK") + "\n"
	text += tr("UI_STATUS_INPUT_TIME") + "\n"
	text += tr("UI_STATUS_BOSS_HINT")
	status_label.text = text
	print("Run started: ", run_data)


func _on_run_ended(result: Dictionary) -> void:
	get_tree().paused = false
	pause_menu.hide_pause()
	status_label.visible = true
	status_label.text = "%s\n%s: %s\n%s: %s\n%s: %s" % [
		tr("UI_RUN_ENDED"),
		tr("UI_RESULT"), _result_label(str(result.get("result", "death"))),
		tr("UI_ROOMS_CLEARED"), str(result.get("rooms_cleared", 0)),
		tr("UI_REWARDS"), str(GameState.current_run.get("inventory", [])),
	]
	print("Run ended: ", result)


func _toggle_pause() -> void:
	if get_tree().paused:
		_resume_run()
	else:
		_pause_run()


func _pause_run() -> void:
	if GameState.phase == GameState.GamePhase.HUB or GameState.phase == GameState.GamePhase.DEATH or GameState.phase == GameState.GamePhase.RUN_END:
		return
	_phase_before_pause = GameState.phase
	GameState.set_phase(GameState.GamePhase.PAUSED)
	get_tree().paused = true
	pause_menu.show_pause()


func _resume_run() -> void:
	if not get_tree().paused and GameState.phase != GameState.GamePhase.PAUSED:
		return
	get_tree().paused = false
	pause_menu.hide_pause()
	if GameState.phase == GameState.GamePhase.PAUSED:
		GameState.set_phase(_phase_before_pause)


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
		GameState.GamePhase.BOOT:
			return tr("PHASE_BOOT")
		GameState.GamePhase.HUB:
			return tr("PHASE_HUB")
		GameState.GamePhase.RUN_START:
			return tr("PHASE_RUN_START")
		GameState.GamePhase.DUNGEON:
			return tr("PHASE_DUNGEON")
		GameState.GamePhase.ROOM_CLEAR:
			return tr("PHASE_ROOM_CLEAR")
		GameState.GamePhase.SELECTION:
			return tr("PHASE_SELECTION")
		GameState.GamePhase.BOSS_FIGHT:
			return tr("PHASE_BOSS_FIGHT")
		GameState.GamePhase.DEATH:
			return tr("PHASE_DEATH")
		GameState.GamePhase.RUN_END:
			return tr("PHASE_RUN_END")
		GameState.GamePhase.PAUSED:
			return tr("PHASE_PAUSED")
		_:
			return "UNKNOWN"
