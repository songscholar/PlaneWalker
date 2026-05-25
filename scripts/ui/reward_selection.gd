class_name RewardSelection
extends CanvasLayer

const RewardPoolScript := preload("res://scripts/rewards/reward_pool.gd")
const BlessingPoolScript := preload("res://scripts/rewards/blessing_pool.gd")
const TalentPoolScript := preload("res://scripts/rewards/talent_pool.gd")

@export var player_path: NodePath
@export var option_count: int = 3

@onready var player: Node = get_node(player_path)
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var option_box: VBoxContainer = $Panel/Margin/VBox/Options

var _current_options: Array[Dictionary] = []
var _current_selection_category: String = "item"


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.room_cleared.connect(_on_room_cleared)
	EventBus.curse_offer_resolved.connect(_on_curse_offer_resolved)


func _on_room_cleared(_room_id: StringName) -> void:
	if GameState.is_curse_offer_pending():
		return
	_show_reward_options()


func _on_curse_offer_resolved() -> void:
	if GameState.phase == GameState.GamePhase.DEATH or GameState.phase == GameState.GamePhase.RUN_END:
		return
	_show_reward_options()


func _show_reward_options() -> void:
	GameState.set_phase(GameState.GamePhase.SELECTION)
	_current_selection_category = _selection_category_for_current_room()
	_current_options = _roll_current_options()
	_render_options()
	visible = true


func _render_options() -> void:
	var title_prefix := _title_for_current_category()
	title_label.text = "%s - Room %d cleared" % [title_prefix, GameState.current_room]
	for child: Node in option_box.get_children():
		option_box.remove_child(child)
		child.queue_free()

	for index: int in range(_current_options.size()):
		var reward := _current_options[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(420.0, 72.0)
		button.text = "%s\n%s\n%s" % [
			reward.get("name", "Reward"),
			RewardPoolScript.get_reward_route_label(reward),
			reward.get("description", ""),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_reward.bind(index))
		option_box.add_child(button)


func _select_reward(index: int) -> void:
	if index < 0 or index >= _current_options.size():
		return
	var reward := _current_options[index]
	if player != null and player.has_method("apply_reward"):
		player.apply_reward(reward)
	_record_selected_reward(reward)
	EventBus.reward_selected.emit(reward)
	EventBus.publish(EventBus.REWARD_SELECTED, {"reward": reward})
	visible = false
	if GameState.phase != GameState.GamePhase.RUN_END:
		GameState.set_phase(GameState.GamePhase.ROOM_CLEAR)


func _selection_category_for_current_room() -> String:
	if GameState.current_room == 3:
		return "talent"
	if GameState.current_room == 4:
		return "blessing"
	return "item"


func _roll_current_options() -> Array[Dictionary]:
	match _current_selection_category:
		"talent":
			return TalentPoolScript.roll_options(
				3,
				GameState.run_seed,
				GameState.current_room,
				GameState.current_run.get("talents", [])
			)
		"blessing":
			return BlessingPoolScript.roll_options(
				2,
				GameState.run_seed,
				GameState.current_room,
				GameState.current_run.get("active_blessings", [])
			)
		_:
			var reward_option_count := option_count
			if GameState.get_current_room_type() == "elite":
				reward_option_count += 1
			return RewardPoolScript.roll_options(
				reward_option_count,
				GameState.run_seed,
				GameState.current_room,
				GameState.current_run.get("inventory", [])
			)


func _title_for_current_category() -> String:
	match _current_selection_category:
		"talent":
			return "Choose a talent"
		"blessing":
			return "Choose a blessing"
		_:
			if GameState.get_current_room_type() == "elite":
				return "Choose an elite reward"
			return "Choose a reward"


func _record_selected_reward(reward: Dictionary) -> void:
	match str(reward.get("category", _current_selection_category)):
		"blessing":
			GameState.add_run_blessing(reward)
		"talent":
			GameState.add_run_talent(reward)
		_:
			GameState.add_run_reward(reward)
