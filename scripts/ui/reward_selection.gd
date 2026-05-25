class_name RewardSelection
extends CanvasLayer

const RewardPoolScript := preload("res://scripts/rewards/reward_pool.gd")

@export var player_path: NodePath
@export var option_count: int = 3

@onready var player: Node = get_node(player_path)
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var option_box: VBoxContainer = $Panel/Margin/VBox/Options

var _current_options: Array[Dictionary] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.room_cleared.connect(_on_room_cleared)


func _on_room_cleared(_room_id: StringName) -> void:
	GameState.set_phase(GameState.GamePhase.SELECTION)
	_current_options = RewardPoolScript.roll_options(
		option_count,
		GameState.run_seed,
		GameState.current_room,
		GameState.current_run.get("inventory", [])
	)
	_render_options()
	visible = true


func _render_options() -> void:
	title_label.text = "Choose a reward"
	for child: Node in option_box.get_children():
		child.queue_free()

	for index: int in range(_current_options.size()):
		var reward := _current_options[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(420.0, 72.0)
		button.text = "%s\n%s" % [reward.get("name", "Reward"), reward.get("description", "")]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_reward.bind(index))
		option_box.add_child(button)


func _select_reward(index: int) -> void:
	if index < 0 or index >= _current_options.size():
		return
	var reward := _current_options[index]
	if player != null and player.has_method("apply_reward"):
		player.apply_reward(reward)
	GameState.add_run_reward(reward)
	EventBus.reward_selected.emit(reward)
	EventBus.publish(EventBus.REWARD_SELECTED, {"reward": reward})
	visible = false
	GameState.set_phase(GameState.GamePhase.ROOM_CLEAR)
