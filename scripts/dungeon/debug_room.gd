extends Node2D

@onready var dummy_health: HealthComponent = $TestDummy/HealthComponent
@onready var player_health: HealthComponent = $Player/HealthComponent
@onready var player_time: TimeManager = $Player/TimeManager
@onready var debug_label: Label = $CanvasLayer/DebugLabel


func _ready() -> void:
	dummy_health.damaged.connect(_on_dummy_damaged)
	EventBus.entity_died.connect(_on_entity_died)
	_refresh_debug_label()


func _process(_delta: float) -> void:
	_refresh_debug_label()


func _refresh_debug_label() -> void:
	var dummy_hp := 0.0
	if is_instance_valid(dummy_health):
		dummy_hp = dummy_health.current_hp
	debug_label.text = "Phase 1 Training Room\n"
	debug_label.text += "Move: WASD / Arrows | Dash: Space\n"
	debug_label.text += "Attack: Left Mouse | Heavy: Right Mouse\n"
	debug_label.text += "Time: Q stop / E rewind | HP %.0f | Energy %.0f\n" % [
		player_health.current_hp,
		player_time.energy,
	]
	debug_label.text += "Dummy HP: %.0f\n" % dummy_hp
	debug_label.text += "Kill the dummy to validate entity_died."


func _on_entity_died(entity: Node, _killer: Variant) -> void:
	print("Entity died through EventBus: ", entity.name)


func _on_dummy_damaged(_amount: float, _current_hp: float) -> void:
	_refresh_debug_label()
