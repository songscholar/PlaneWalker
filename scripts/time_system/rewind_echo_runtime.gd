class_name RewindEchoRuntime
extends Node2D

const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")

signal echo_started(path_samples: Array[Vector2])
signal echo_ended()

@export var time_manager_path: NodePath = NodePath("../TimeManager")
@export var owner_entity_path: NodePath = NodePath("..")
@export var health_component_path: NodePath = NodePath("../HealthComponent")
@export var duration: float = 2.0
@export var pulse_interval: float = 0.5
@export var pulse_damage_multiplier: float = 0.25
@export var path_radius: float = 28.0

@onready var time_manager: Node = get_node(time_manager_path)
@onready var owner_entity: Node = get_node(owner_entity_path)
@onready var health_component: Node = get_node(health_component_path)
@onready var path_proxy: Line2D = $PathProxy

var _active: bool = false
var _elapsed: float = 0.0
var _next_pulse_at: float = 0.5
var _committed_attack: float = 0.0
var _committed_path_hit_multiplier: float = 0.0
var _committed_path: Array[Vector2] = []
var _path_hit_enemy_ids: Dictionary = {}
var _echo_start_count: int = 0


func _ready() -> void:
	global_position = Vector2.ZERO
	path_proxy.visible = false
	_next_pulse_at = _pulse_step()
	time_manager.rewind_committed.connect(_on_rewind_committed)
	if health_component.has_signal("died"):
		health_component.died.connect(_on_owner_died)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not _active or delta <= 0.0:
		return
	if not _owner_is_alive():
		cancel_echo()
		return
	_elapsed = minf(duration, _elapsed + delta)
	_apply_unresolved_path_hits()
	while _next_pulse_at <= duration and _elapsed + 0.0001 >= _next_pulse_at:
		_apply_pulse()
		_next_pulse_at += _pulse_step()
	if _elapsed + 0.0001 >= duration:
		_finish_echo()


func is_echo_active() -> bool:
	return _active


func get_echo_start_count() -> int:
	return _echo_start_count


func get_committed_path() -> Array[Vector2]:
	return _committed_path.duplicate()


func get_proxy_point_count() -> int:
	return path_proxy.get_point_count()


func cancel_echo() -> void:
	if not _active:
		return
	_clear_echo_state()
	echo_ended.emit()


func _on_rewind_committed(transaction: Dictionary) -> void:
	if not time_manager.rewind_echo_enabled or not _owner_is_alive():
		return
	var raw_path: Variant = transaction.get("path_samples", [])
	if not raw_path is Array or raw_path.size() < 2:
		return
	var copied_path: Array[Vector2] = []
	for sample: Variant in raw_path:
		if sample is Vector2:
			copied_path.append(sample)
	if copied_path.size() < 2:
		return
	if _active:
		cancel_echo()
	_active = true
	_elapsed = 0.0
	_next_pulse_at = _pulse_step()
	_committed_attack = _read_owner_attack()
	_committed_path_hit_multiplier = maxf(0.0, time_manager.rewind_path_hit_multiplier)
	_committed_path = copied_path.duplicate()
	_path_hit_enemy_ids.clear()
	_echo_start_count += 1
	_draw_path_proxy()
	_apply_unresolved_path_hits()
	echo_started.emit(_committed_path.duplicate())


func _apply_pulse() -> void:
	var hit_this_pulse: Dictionary = {}
	for enemy: Node in _enemies_near_path():
		var enemy_id := enemy.get_instance_id()
		if hit_this_pulse.has(enemy_id):
			continue
		hit_this_pulse[enemy_id] = true
		_apply_damage(enemy, _committed_attack * pulse_damage_multiplier, "time:rewind_echo_pulse")


func _apply_unresolved_path_hits() -> void:
	if _committed_path_hit_multiplier <= 0.0:
		return
	for enemy: Node in _enemies_near_path():
		var enemy_id := enemy.get_instance_id()
		if _path_hit_enemy_ids.has(enemy_id):
			continue
		_path_hit_enemy_ids[enemy_id] = true
		_apply_damage(enemy, _committed_attack * _committed_path_hit_multiplier, "time:rewind_path_hit")


func _apply_damage(enemy: Node, amount: float, damage_tag: String) -> void:
	if amount <= 0.0 or not is_instance_valid(enemy):
		return
	var enemy_health := enemy.get_node_or_null("HealthComponent")
	if enemy_health == null or not enemy_health.has_method("take_damage"):
		return
	if enemy_health.has_method("is_alive") and not enemy_health.is_alive():
		return
	var damage_info := DamageInfoScript.new(amount, DamageInfoScript.DamageType.TIME, self, owner_entity)
	damage_info.can_crit = false
	damage_info.tags.append(damage_tag)
	enemy_health.take_damage(damage_info)


func _enemies_near_path() -> Array[Node]:
	var result: Array[Node] = []
	for candidate: Node in get_tree().get_nodes_in_group("enemies"):
		if not candidate is Node2D or not is_instance_valid(candidate):
			continue
		if _is_point_near_path(candidate.global_position):
			result.append(candidate)
	return result


func _is_point_near_path(point: Vector2) -> bool:
	for index: int in range(_committed_path.size() - 1):
		if _distance_to_segment(point, _committed_path[index], _committed_path[index + 1]) <= path_radius:
			return true
	return false


func _distance_to_segment(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)
	var progress := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * progress)


func _draw_path_proxy() -> void:
	path_proxy.clear_points()
	for point: Vector2 in _committed_path:
		path_proxy.add_point(point)
	path_proxy.visible = true


func _finish_echo() -> void:
	_clear_echo_state()
	echo_ended.emit()


func _clear_echo_state() -> void:
	_active = false
	_elapsed = 0.0
	_next_pulse_at = _pulse_step()
	_committed_attack = 0.0
	_committed_path_hit_multiplier = 0.0
	_committed_path.clear()
	_path_hit_enemy_ids.clear()
	path_proxy.clear_points()
	path_proxy.visible = false


func _owner_is_alive() -> bool:
	if owner_entity == null or not is_instance_valid(owner_entity):
		return false
	if health_component == null or not is_instance_valid(health_component):
		return false
	return not health_component.has_method("is_alive") or health_component.is_alive()


func _read_owner_attack() -> float:
	var stats: Variant = owner_entity.get("stats")
	if stats == null:
		return 0.0
	return maxf(0.0, float(stats.get("attack")))


func _pulse_step() -> float:
	return maxf(0.001, pulse_interval)


func _on_owner_died(_killer: Variant) -> void:
	cancel_echo()
