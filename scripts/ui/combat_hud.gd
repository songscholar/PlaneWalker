extends CanvasLayer

@export var player_path: NodePath

@onready var player: Node = get_node(player_path)
@onready var health: Node = player.get_node("HealthComponent")
@onready var time_manager: Node = player.get_node("TimeManager")
@onready var label: Label = $StatusLabel


func _process(_delta: float) -> void:
	label.text = "HP %.0f/%.0f | Time %.0f/%.0f | Stop CD %.1f | Rewind CD %.1f" % [
		health.current_hp,
		health.max_hp,
		time_manager.energy,
		time_manager.max_energy,
		time_manager.get_cooldown(&"time_stop"),
		time_manager.get_cooldown(&"time_rewind"),
	]
