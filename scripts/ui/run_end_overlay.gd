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
	result_label.text = "%s\nRoom reached: %s\nRooms cleared: %s\nRewards: %s" % [
		title,
		result.get("current_room", result.get("rooms_cleared", 0)),
		result.get("rooms_cleared", 0),
		GameState.current_run.get("inventory", []),
	]
	visible = true


func _restart_run() -> void:
	get_tree().reload_current_scene()
