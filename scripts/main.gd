extends Node

@onready var status_label: Label = $DebugLayer/StatusLabel


func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	_print_input_map()
	GameState.start_run({
		"character_id": "wanderer",
		"weapon_id": "sword",
		"difficulty": "normal",
	})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_print_input_map()
	if event.is_action_pressed("interact") and GameState.phase == GameState.GamePhase.DEATH:
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed("interact"):
		EventBus.room_started.emit(&"debug_room_01")
		EventBus.publish(EventBus.ROOM_STARTED, {"room_id": "debug_room_01"})
		print("Debug room_started emitted.")


func _on_run_started(run_data: Dictionary) -> void:
	var text := "Plane Walker MVP Phase 0\n"
	text += "Phase: %s\n" % _phase_name(GameState.phase)
	text += "Character: %s\n" % run_data.get("character_id", "")
	text += "Weapon: %s\n" % run_data.get("weapon_id", "")
	text += "Seed: %s\n\n" % GameState.run_seed
	text += "Input smoke test:\n"
	text += "WASD/Arrows move actions registered\n"
	text += "Mouse Left attack, Mouse Right heavy_attack\n"
	text += "Space dash, Q time_stop, E time_rewind\n"
	text += "Room 5 spawns the Chrono Warden boss"
	status_label.text = text
	print("Run started: ", run_data)


func _on_run_ended(result: Dictionary) -> void:
	status_label.text = "Run ended\nResult: %s\nRooms cleared: %s\nRewards: %s" % [
		result.get("result", ""),
		result.get("rooms_cleared", 0),
		GameState.current_run.get("inventory", []),
	]
	print("Run ended: ", result)


func _print_input_map() -> void:
	var actions := [
		"move_up",
		"move_down",
		"move_left",
		"move_right",
		"attack",
		"heavy_attack",
		"dash",
		"time_stop",
		"time_rewind",
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
