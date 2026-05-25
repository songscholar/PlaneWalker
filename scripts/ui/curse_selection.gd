class_name CurseSelection
extends CanvasLayer

const CursePoolScript := preload("res://scripts/curses/curse_pool.gd")

@export var player_path: NodePath
@export var option_count: int = 2

@onready var player: Node = get_node(player_path)
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var option_box: VBoxContainer = $Panel/Margin/VBox/Options
@onready var skip_button: Button = $Panel/Margin/VBox/SkipButton

var _current_options: Array[Dictionary] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	skip_button.pressed.connect(_skip_curse)
	EventBus.room_cleared.connect(_on_room_cleared)


func _on_room_cleared(_room_id: StringName) -> void:
	if not GameState.is_curse_offer_pending():
		return
	GameState.set_phase(GameState.GamePhase.SELECTION)
	_current_options = CursePoolScript.roll_options(
		option_count,
		GameState.run_seed,
		GameState.current_room,
		GameState.current_run.get("active_curses", [])
	)
	_render_options()
	visible = true


func _render_options() -> void:
	title_label.text = "Risk altar - Room %d cleared" % GameState.current_room
	for child: Node in option_box.get_children():
		child.queue_free()

	for index: int in range(_current_options.size()):
		var curse := _current_options[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(420.0, 84.0)
		button.text = "%s\nRisk: %s\n%s" % [
			curse.get("name", "Curse"),
			str(curse.get("risk", "unknown")).capitalize(),
			curse.get("description", ""),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_curse.bind(index))
		option_box.add_child(button)


func _select_curse(index: int) -> void:
	if index < 0 or index >= _current_options.size():
		return
	var curse := _current_options[index]
	if player != null and player.has_method("apply_curse"):
		player.apply_curse(curse)
	_resolve_offer()


func _skip_curse() -> void:
	_resolve_offer()


func _resolve_offer() -> void:
	visible = false
	GameState.set_curse_offer_pending(false)
	EventBus.curse_offer_resolved.emit()
	EventBus.publish(EventBus.CURSE_OFFER_RESOLVED)
