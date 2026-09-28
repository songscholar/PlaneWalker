extends Node2D

@onready var dummy_health: Node = $TestDummy/HealthComponent
@onready var player_health: Node = $Player/HealthComponent
@onready var player_time: Node = $Player/TimeManager
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
	debug_label.text = tr("DEBUG_TRAINING_ROOM") + "\n"
	debug_label.text += tr("DEBUG_MOVE") + "\n"
	debug_label.text += tr("DEBUG_ATTACK") + "\n"
	debug_label.text += tr("DEBUG_TIME_FMT") % [
		player_health.current_hp,
		player_time.energy,
	] + "\n"
	debug_label.text += tr("DEBUG_DUMMY_HP_FMT") % dummy_hp + "\n"
	debug_label.text += tr("DEBUG_KILL_DUMMY")


func _on_entity_died(entity: Node, _killer: Variant) -> void:
	print("Entity died through EventBus: ", entity.name)


func _on_dummy_damaged(_amount: float, _current_hp: float) -> void:
	_refresh_debug_label()
