class_name TimeManager
extends Node

const TimeRiftScene := preload("res://scenes/time/time_rift.tscn")

signal energy_changed(current: float, maximum: float)
signal cooldown_changed(skill_id: StringName, remaining: float)

@export var max_energy: float = 100.0
@export var energy_regen: float = 2.0
@export var time_stop_cost: float = 35.0
@export var time_stop_cooldown: float = 12.0
@export var time_stop_duration: float = 3.0
@export var rewind_cost: float = 45.0
@export var rewind_cooldown: float = 15.0
@export var time_rift_cost: float = 30.0
@export var time_rift_cooldown: float = 10.0
@export var time_rift_duration: float = 4.0
@export var time_rift_radius: float = 92.0
@export var time_rift_slow_multiplier: float = 0.45
@export var time_accelerate_cost: float = 35.0
@export var time_accelerate_cooldown: float = 14.0
@export var time_accelerate_duration: float = 3.0
@export var time_accelerate_multiplier: float = 1.35

var energy: float = 100.0
var time_stop_duration_bonus: float = 0.0
var time_stop_cost_multiplier: float = 1.0
var time_stop_weakpoint_damage_bonus: float = 0.0
var time_stop_weakpoint_duration: float = 0.0
var rewind_cost_multiplier: float = 1.0
var rewind_heal: float = 0.0
var time_rift_cost_multiplier: float = 1.0
var time_rift_duration_bonus: float = 0.0
var time_rift_radius_bonus: float = 0.0
var time_rift_slow_bonus: float = 0.0
var time_accelerate_cost_multiplier: float = 1.0
var time_accelerate_duration_bonus: float = 0.0
var time_accelerate_multiplier_bonus: float = 0.0
var low_energy_regen_multiplier: float = 1.0
var low_energy_threshold: float = 30.0
var time_stop_self_damage: float = 0.0
var rewind_self_damage: float = 0.0
var _cooldowns: Dictionary = {
	&"time_stop": 0.0,
	&"time_rewind": 0.0,
	&"time_rift": 0.0,
	&"time_accelerate": 0.0,
}


func _ready() -> void:
	energy = max_energy
	energy_changed.emit(energy, max_energy)


func _process(delta: float) -> void:
	_regen_energy(delta)
	_tick_cooldowns(delta)


func configure_from_stats(stats: Resource) -> void:
	var previous_max_energy := max_energy
	max_energy = stats.time_energy_max
	energy_regen = stats.time_energy_regen
	if max_energy > previous_max_energy:
		energy += max_energy - previous_max_energy
	energy = clampf(energy, 0.0, max_energy)
	energy_changed.emit(energy, max_energy)


func try_time_stop() -> void:
	var effective_cost := time_stop_cost * time_stop_cost_multiplier
	var effective_duration := time_stop_duration + time_stop_duration_bonus
	if not _can_pay(&"time_stop", effective_cost):
		return
	_pay_cost(&"time_stop", effective_cost, time_stop_cooldown)
	_take_self_damage(time_stop_self_damage, &"curse:time_stop")
	EventBus.time_skill_started.emit(&"time_stop")
	EventBus.publish(EventBus.TIME_SKILL_STARTED, {"skill_id": "time_stop"})
	for node: Node in get_tree().get_nodes_in_group("time_stoppable"):
		if node.has_method("apply_time_stop"):
			node.apply_time_stop(effective_duration)
		if node.has_method("apply_weakpoint"):
			node.apply_weakpoint(time_stop_weakpoint_duration, time_stop_weakpoint_damage_bonus)
	await get_tree().create_timer(effective_duration).timeout
	EventBus.time_skill_ended.emit(&"time_stop")
	EventBus.publish(EventBus.TIME_SKILL_ENDED, {"skill_id": "time_stop"})


func try_rewind(recorder: Node) -> void:
	if recorder == null or not recorder.has_snapshot():
		return
	var effective_cost := rewind_cost * rewind_cost_multiplier
	if not _can_pay(&"time_rewind", effective_cost):
		return
	_pay_cost(&"time_rewind", effective_cost, rewind_cooldown)
	_take_self_damage(rewind_self_damage, &"curse:rewind")
	EventBus.time_skill_started.emit(&"time_rewind")
	EventBus.publish(EventBus.TIME_SKILL_STARTED, {"skill_id": "time_rewind"})
	recorder.rewind_to_oldest_snapshot()
	if rewind_heal > 0.0:
		var health_component := get_parent().get_node_or_null("HealthComponent")
		if health_component != null and health_component.has_method("heal"):
			health_component.heal(rewind_heal)
	EventBus.time_skill_ended.emit(&"time_rewind")
	EventBus.publish(EventBus.TIME_SKILL_ENDED, {"skill_id": "time_rewind"})


func try_time_rift(rift_position: Vector2) -> bool:
	var effective_cost := time_rift_cost * time_rift_cost_multiplier
	if not _can_pay(&"time_rift", effective_cost):
		return false
	_pay_cost(&"time_rift", effective_cost, time_rift_cooldown)
	var rift := TimeRiftScene.instantiate()
	rift.duration = time_rift_duration + time_rift_duration_bonus
	rift.radius = time_rift_radius + time_rift_radius_bonus
	rift.slow_multiplier = clampf(time_rift_slow_multiplier - time_rift_slow_bonus, 0.1, 1.0)
	var parent := get_parent().get_parent()
	parent.add_child(rift)
	rift.global_position = rift_position
	EventBus.time_skill_started.emit(&"time_rift")
	EventBus.publish(EventBus.TIME_SKILL_STARTED, {"skill_id": "time_rift", "position": rift_position})
	return true


func try_time_accelerate() -> bool:
	var effective_cost := time_accelerate_cost * time_accelerate_cost_multiplier
	var effective_duration := time_accelerate_duration + time_accelerate_duration_bonus
	var effective_multiplier := time_accelerate_multiplier + time_accelerate_multiplier_bonus
	if not _can_pay(&"time_accelerate", effective_cost):
		return false
	_pay_cost(&"time_accelerate", effective_cost, time_accelerate_cooldown)
	var owner_entity := get_parent()
	if owner_entity.has_method("apply_time_acceleration"):
		owner_entity.apply_time_acceleration(effective_multiplier, effective_duration)
	EventBus.time_skill_started.emit(&"time_accelerate")
	EventBus.publish(EventBus.TIME_SKILL_STARTED, {"skill_id": "time_accelerate"})
	get_tree().create_timer(effective_duration).timeout.connect(_end_time_accelerate)
	return true


func _end_time_accelerate() -> void:
	EventBus.time_skill_ended.emit(&"time_accelerate")
	EventBus.publish(EventBus.TIME_SKILL_ENDED, {"skill_id": "time_accelerate"})


func restore_energy(amount: float) -> void:
	energy = minf(max_energy, energy + amount)
	energy_changed.emit(energy, max_energy)


func get_cooldown(skill_id: StringName) -> float:
	return float(_cooldowns.get(skill_id, 0.0))


func _regen_energy(delta: float) -> void:
	if energy >= max_energy:
		return
	var regen_multiplier := low_energy_regen_multiplier if energy < low_energy_threshold else 1.0
	energy = minf(max_energy, energy + energy_regen * regen_multiplier * delta)
	energy_changed.emit(energy, max_energy)


func _tick_cooldowns(delta: float) -> void:
	for skill_id: StringName in _cooldowns.keys():
		var previous := float(_cooldowns[skill_id])
		if previous <= 0.0:
			continue
		_cooldowns[skill_id] = maxf(0.0, previous - delta)
		cooldown_changed.emit(skill_id, _cooldowns[skill_id])


func _can_pay(skill_id: StringName, cost: float) -> bool:
	return energy >= cost and get_cooldown(skill_id) <= 0.0


func _pay_cost(skill_id: StringName, cost: float, cooldown: float) -> void:
	energy = maxf(0.0, energy - cost)
	_cooldowns[skill_id] = cooldown
	energy_changed.emit(energy, max_energy)
	cooldown_changed.emit(skill_id, cooldown)


func _take_self_damage(amount: float, source_tag: StringName) -> void:
	if amount <= 0.0:
		return
	var owner_entity := get_parent()
	var health_component := owner_entity.get_node_or_null("HealthComponent")
	if health_component == null:
		return
	if health_component.has_method("lose_health"):
		health_component.lose_health(amount, source_tag)
