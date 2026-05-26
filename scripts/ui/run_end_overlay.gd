class_name RunEndOverlay
extends CanvasLayer

@onready var panel: PanelContainer = $Panel
@onready var result_label: Label = $Panel/Margin/VBox/ResultLabel
@onready var restart_button: Button = $Panel/Margin/VBox/RestartButton


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.run_ended.connect(_on_run_ended)
	restart_button.pressed.connect(_restart_run)


func _on_run_ended(result: Dictionary) -> void:
	var outcome := str(result.get("result", ""))
	var title := "Run Complete" if outcome == "floor_cleared" else "Run Failed"
	result_label.text = "%s\nRoom reached: %s\nRooms cleared: %s\nKills: %s\nTime: %s\nItems: %s\nBlessings: %s\nTalents: %s\nCurses: %s" % [
		title,
		result.get("current_room", result.get("rooms_cleared", 0)),
		result.get("rooms_cleared", 0),
		result.get("kills", 0),
		_format_time(float(result.get("run_time", 0.0))),
		_names_for(result.get("rewards", [])),
		_names_for(result.get("blessings", [])),
		_names_for(result.get("talent_choices", [])),
		_names_for(result.get("curses", [])),
	]
	visible = true


func _restart_run() -> void:
	get_tree().reload_current_scene()


func _format_time(seconds: float) -> String:
	var total_seconds := maxi(0, roundi(seconds))
	return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]


func _names_for(entries: Array) -> String:
	if entries.is_empty():
		return "-"
	var names: Array[String] = []
	for entry: Variant in entries:
		if typeof(entry) == TYPE_DICTIONARY:
			names.append(str((entry as Dictionary).get("name", (entry as Dictionary).get("id", "unknown"))))
		else:
			names.append(str(entry))
	return ", ".join(names)
