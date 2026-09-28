class_name RewindRecorder
extends Node

@export var target_path: NodePath
@export var health_component_path: NodePath
@export var time_manager_path: NodePath
@export var record_seconds: float = 5.0
@export var samples_per_second: float = 10.0

@onready var target: Node2D = get_node(target_path)
@onready var health_component: Node = get_node(health_component_path)
@onready var time_manager: Node = get_node(time_manager_path)

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
	var snapshot := consume_oldest_snapshot()
	if snapshot.is_empty():
		return
	if restore_player_state(snapshot):
		clear_snapshots()


func consume_oldest_snapshot() -> Dictionary:
	if _snapshots.is_empty():
		return {}
	return _snapshots.pop_front().duplicate(true)


func peek_oldest_snapshot() -> Dictionary:
	if _snapshots.is_empty():
		return {}
	return _snapshots.front().duplicate(true)


func prepare_rewind_transaction() -> Dictionary:
	if _snapshots.is_empty() or target == null or not is_instance_valid(target):
		return {}
	var target_snapshot := peek_oldest_snapshot()
	if not target_snapshot.has("position"):
		return {}
	var origin: Vector2 = target.global_position
	var destination: Vector2 = target_snapshot["position"]
	var path_samples: Array[Vector2] = [origin]
	for index: int in range(_snapshots.size() - 1, -1, -1):
		var sample: Dictionary = _snapshots[index]
		if not sample.has("position") or not sample["position"] is Vector2:
			continue
		var sample_position: Vector2 = sample["position"]
		if path_samples[-1] != sample_position:
			path_samples.append(sample_position)
	if path_samples[-1] != destination:
		path_samples.append(destination)
	return {
		"target_snapshot": target_snapshot.duplicate(true),
		"origin": origin,
		"destination": destination,
		"path_samples": path_samples.duplicate(),
	}


func restore_player_state(snapshot: Dictionary) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if health_component == null or not is_instance_valid(health_component):
		return false
	if not snapshot.has("position") or not snapshot.has("hp"):
		return false
	_cancel_transient_actions()
	if not _restore_safe_action(snapshot.get("safe_action", {})):
		return false
	target.global_position = snapshot["position"]
	if snapshot.has("velocity") and _has_property(target, &"velocity"):
		target.set("velocity", snapshot["velocity"])
	_restore_facing(snapshot.get("facing", Vector2.RIGHT))
	health_component.current_hp = minf(health_component.max_hp, float(snapshot["hp"]))
	health_component.apply_invulnerability(0.5)
	return true


func clear_snapshots() -> void:
	_snapshots.clear()


func _record_snapshot() -> void:
	_snapshots.append({
		"position": target.global_position,
		"facing": _capture_facing(),
		"velocity": target.get("velocity") if _has_property(target, &"velocity") else Vector2.ZERO,
		"hp": health_component.current_hp,
		"safe_action": _capture_safe_action(),
	})
	var max_samples := int(record_seconds * samples_per_second)
	while _snapshots.size() > max_samples:
		_snapshots.pop_front()


func _capture_facing() -> Vector2:
	if target.has_method("get_rewind_facing"):
		return target.call("get_rewind_facing")
	if _has_property(target, &"_last_move_direction"):
		return target.get("_last_move_direction")
	return Vector2.RIGHT


func _restore_facing(facing: Variant) -> void:
	if not facing is Vector2:
		return
	if target.has_method("restore_rewind_facing"):
		target.call("restore_rewind_facing", facing)
	elif _has_property(target, &"_last_move_direction"):
		target.set("_last_move_direction", facing)


func _capture_safe_action() -> Dictionary:
	if target.has_method("get_rewind_safe_action_state"):
		var state: Variant = target.call("get_rewind_safe_action_state")
		if state is Dictionary:
			return state.duplicate(true)
	return {}


func _restore_safe_action(state: Variant) -> bool:
	if not state is Dictionary or not target.has_method("restore_rewind_safe_action_state"):
		return true
	var result: Variant = target.call("restore_rewind_safe_action_state", state.duplicate(true))
	return bool(result) if result is bool else true


func _cancel_transient_actions() -> void:
	if target.has_method("cancel_transient_actions"):
		target.call("cancel_transient_actions")


func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false
