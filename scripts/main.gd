extends Node

@onready var status_label: Label = $DebugLayer/StatusLabel
@onready var combat_room: Node2D = $CombatRoom01
@onready var start_menu: CanvasLayer = $StartMenu
@onready var start_button: Button = $StartMenu/Panel/Margin/VBox/StartButton
@onready var last_run_label: Label = $StartMenu/Panel/Margin/VBox/LastRunLabel
@onready var pause_menu: CanvasLayer = $PauseMenu

var _phase_before_pause: GameState.GamePhase = GameState.GamePhase.DUNGEON


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	start_button.pressed.connect(_start_new_run)
	pause_menu.resume_requested.connect(_resume_run)
	combat_room.visible = false
	combat_room.process_mode = Node.PROCESS_MODE_DISABLED
	status_label.visible = false
	GameState.set_phase(GameState.GamePhase.HUB)
	_show_start_menu()
	_print_input_map()


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
		last_run_label.text = "No runs recorded"
		return
	last_run_label.text = "Last: %s | Best rooms: %d | Runs: %d" % [
		str(summary.get("result", "unknown")).capitalize(),
		int(GameState.persistent.get("best_rooms_cleared", 0)),
		int(GameState.persistent.get("runs_completed", 0)),
	]


func _on_run_started(run_data: Dictionary) -> void:
	status_label.visible = true
	var text := "Plane Walker MVP Phase 0\n"
	text += "Phase: %s\n" % _phase_name(GameState.phase)
	text += "Character: %s\n" % run_data.get("character_id", "")
	text += "Weapon: %s\n" % run_data.get("weapon_id", "")
	text += "Seed: %s\n\n" % GameState.run_seed
	text += "Input smoke test:\n"
	text += "WASD/Arrows move actions registered\n"
	text += "Mouse Left attack, Mouse Right heavy_attack\n"
	text += "X ranged_attack, Space dash, Q time_stop, E time_rewind, R time_rift, C time_accelerate\n"
	text += "Room 5 spawns the Chrono Warden boss"
	status_label.text = text
	print("Run started: ", run_data)


func _on_run_ended(result: Dictionary) -> void:
	get_tree().paused = false
	pause_menu.hide_pause()
	status_label.visible = true
	status_label.text = "Run ended\nResult: %s\nRooms cleared: %s\nRewards: %s" % [
		result.get("result", ""),
		result.get("rooms_cleared", 0),
		GameState.current_run.get("inventory", []),
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
			return "BOOT"
		GameState.GamePhase.HUB:
			return "HUB"
		GameState.GamePhase.RUN_START:
			return "RUN_START"
		GameState.GamePhase.DUNGEON:
			return "DUNGEON"
		GameState.GamePhase.ROOM_CLEAR:
			return "ROOM_CLEAR"
		GameState.GamePhase.SELECTION:
			return "SELECTION"
		GameState.GamePhase.BOSS_FIGHT:
			return "BOSS_FIGHT"
		GameState.GamePhase.DEATH:
			return "DEATH"
		GameState.GamePhase.RUN_END:
			return "RUN_END"
		GameState.GamePhase.PAUSED:
			return "PAUSED"
		_:
			return "UNKNOWN"
