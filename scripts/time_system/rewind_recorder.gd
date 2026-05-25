class_name RewindRecorder
extends Node

@export var target_path: NodePath
@export var health_component_path: NodePath
@export var time_manager_path: NodePath
@export var record_seconds: float = 5.0
@export var samples_per_second: float = 10.0

@onready var target: Node2D = get_node(target_path)
@onready var health_component: HealthComponent = get_node(health_component_path)
@onready var time_manager: TimeManager = get_node(time_manager_path)

var _snapshots: Array[Dictionary] = []
var _sample_timer: float = 0.0


func _process(delta: float) -> void:
	_sample_timer += delta
	var sample_interval := 1.0 / samples_per_second
	if _sample_timer < sample_interval:
		return
	_sample_timer -= sample_interval
	_record_snapshot()


func has_snapshot() -> bool:
	return not _snapshots.is_empty()


func rewind_to_oldest_snapshot() -> void:
	if _snapshots.is_empty():
		return
	var snapshot: Dictionary = _snapshots.front()
	target.global_position = snapshot["position"]
	health_component.current_hp = minf(health_component.max_hp, snapshot["hp"])
	time_manager.energy = minf(time_manager.max_energy, snapshot["energy"])
	time_manager.energy_changed.emit(time_manager.energy, time_manager.max_energy)
	health_component.apply_invulnerability(0.5)
	_snapshots.clear()


func _record_snapshot() -> void:
	_snapshots.append({
		"position": target.global_position,
		"hp": health_component.current_hp,
		"energy": time_manager.energy,
	})
	var max_samples := int(record_seconds * samples_per_second)
	while _snapshots.size() > max_samples:
		_snapshots.pop_front()
