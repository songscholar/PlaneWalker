class_name EventSelection
extends CanvasLayer

const RewardPoolScript := preload("res://scripts/rewards/reward_pool.gd")

@export var player_path: NodePath

@onready var player: Node = get_node(player_path)
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var option_box: VBoxContainer = $Panel/Margin/VBox/Options

var _current_options: Array[Dictionary] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.room_started.connect(_on_room_started)


func _on_room_started(_room_id: StringName) -> void:
	if GameState.get_current_room_type() != "event":
		visible = false
		return
	GameState.set_phase(GameState.GamePhase.SELECTION)
	_current_options = _build_options()
	_render_options()
	visible = true


func _build_options() -> Array[Dictionary]:
	return [
		{
			"id": "chrono_spring",
			"name": "Chrono Spring",
			"description": "Heal 45 HP and restore 25 time energy.",
			"effects": {"heal": 45.0, "time_energy_restore": 25.0},
		},
		{
			"id": "stabilized_core",
			"name": "Stabilized Core",
			"description": "Gain 15 maximum time energy and refill it.",
			"effects": {"time_energy_max_bonus": 15.0, "time_energy_restore": 15.0},
		},
		{
			"id": "fractured_cache",
			"name": "Fractured Cache",
			"description": "Lose 25 HP to take one immediate build reward.",
			"hp_cost": 25.0,
			"grant_reward": true,
		},
	]


func _render_options() -> void:
	title_label.text = "Temporal event - Room %d" % GameState.current_room
	for child: Node in option_box.get_children():
		option_box.remove_child(child)
		child.queue_free()

	for index: int in range(_current_options.size()):
		var option := _current_options[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(420.0, 78.0)
		button.text = "%s\n%s" % [
			option.get("name", "Event"),
			option.get("description", ""),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_select_option.bind(index))
		option_box.add_child(button)


func _select_option(index: int) -> void:
	if not visible:
		return
	if index < 0 or index >= _current_options.size():
		return
	var option := _current_options[index].duplicate(true)
	_apply_event_option(option)
	GameState.add_run_event(option)
	visible = false
	if GameState.phase == GameState.GamePhase.DEATH:
		return
	EventBus.reward_selected.emit(option)
	EventBus.publish(EventBus.REWARD_SELECTED, {"reward": option})


func _apply_event_option(option: Dictionary) -> void:
	if option.has("effects") and player != null and player.has_method("apply_reward"):
		player.apply_reward({"id": option.get("id", "event"), "effects": option.get("effects", {})})

	if option.get("grant_reward", false):
		_pay_hp_cost(float(option.get("hp_cost", 0.0)))
		if GameState.phase == GameState.GamePhase.DEATH:
			return
		var rewards := RewardPoolScript.roll_options(
			1,
			GameState.run_seed,
			GameState.current_room,
			GameState.current_run.get("inventory", [])
		)
		if not rewards.is_empty():
			var reward := rewards[0]
			if player != null and player.has_method("apply_reward"):
				player.apply_reward(reward)
			GameState.add_run_reward(reward)
			option["granted_reward_id"] = reward.get("id", "")


func _pay_hp_cost(amount: float) -> void:
	if amount <= 0.0 or player == null:
		return
	var health: Node = player.get_node_or_null("HealthComponent")
	if health != null and health.has_method("lose_health"):
		health.lose_health(amount, &"event:fractured_cache")
