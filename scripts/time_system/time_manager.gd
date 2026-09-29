class_name TimeManager
extends Node

const TimeRiftScene := preload("res://scenes/time/time_rift.tscn")

const ACTION_TO_CANONICAL: Dictionary = {
	&"stop": &"stop",
	&"rewind": &"rewind",
	&"rift": &"rift",
	&"accelerate": &"accelerate",
	&"time_stop": &"stop",
	&"time_rewind": &"rewind",
	&"time_rift": &"rift",
	&"time_accelerate": &"accelerate",
}

signal energy_changed(current: float, maximum: float)
signal cooldown_changed(skill_id: StringName, remaining: float)
signal rewind_committed(transaction: Dictionary)

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
var rewind_echo_enabled: bool = false
var rewind_path_hit_multiplier: float = 0.0
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
var _active_rifts: Array[Node] = []
var _time_stop_remaining: float = 0.0
var _time_stop_active: bool = false
var _time_stop_source_sequence: int = 0
var _time_stop_source_id: StringName = &""
var _time_stop_targets: Array[Node] = []
var _time_accelerate_remaining: float = 0.0
var _time_accelerate_active: bool = false
var _time_accelerate_token: int = 0
var _time_accelerate_publish_lifecycle: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	energy = max_energy
	energy_changed.emit(energy, max_energy)


func _process(delta: float) -> void:
	_regen_energy(delta)
	_tick_cooldowns(delta)
	_tick_active_effects(delta)


func configure_from_stats(stats: Resource) -> void:
	var previous_max_energy := max_energy
	max_energy = stats.time_energy_max
	energy_regen = stats.time_energy_regen
	if max_energy > previous_max_energy:
		energy += max_energy - previous_max_energy
	energy = clampf(energy, 0.0, max_energy)
	energy_changed.emit(energy, max_energy)


func canonical_skill_id(skill_id: StringName) -> StringName:
	return StringName(ACTION_TO_CANONICAL.get(skill_id, &""))


func action_skill_id(skill_id: StringName) -> StringName:
	match canonical_skill_id(skill_id):
		&"stop":
			return &"time_stop"
		&"rewind":
			return &"time_rewind"
		&"rift":
			return &"time_rift"
		&"accelerate":
			return &"time_accelerate"
		_:
			return &""


func can_use(skill_id: StringName, context: Dictionary) -> bool:
	match canonical_skill_id(skill_id):
		&"stop":
			return can_time_stop()
		&"rewind":
			return can_rewind(context.get("recorder") as Node)
		&"rift":
			return context.get("position") is Vector2 and can_time_rift(context.get("position", Vector2.ZERO))
		&"accelerate":
			return can_time_accelerate()
		_:
			return false


func try_use(skill_id: StringName, context: Dictionary) -> bool:
	if not can_use(skill_id, context):
		return false
	match canonical_skill_id(skill_id):
		&"stop":
			return try_time_stop()
		&"rewind":
			return try_rewind(context.get("recorder") as Node)
		&"rift":
			return try_time_rift(context.get("position", Vector2.ZERO))
		&"accelerate":
			return try_time_accelerate()
		_:
			return false


func can_time_stop() -> bool:
	var effective_cost := time_stop_cost * time_stop_cost_multiplier
	return not _time_stop_active and _can_pay(&"time_stop", effective_cost)


func try_time_stop() -> bool:
	var effective_cost := time_stop_cost * time_stop_cost_multiplier
	var effective_duration := time_stop_duration + time_stop_duration_bonus
	if not can_time_stop():
		return false
	_pay_cost(&"time_stop", effective_cost, time_stop_cooldown)
	_time_stop_source_sequence += 1
	_time_stop_source_id = StringName("time_stop:%d:%d" % [get_instance_id(), _time_stop_source_sequence])
	_time_stop_remaining = maxf(0.0, effective_duration)
	_time_stop_active = true
	_time_stop_targets.clear()
	for node: Node in get_tree().get_nodes_in_group("time_stoppable"):
		if node.has_method("apply_time_stop_source"):
			node.apply_time_stop_source(_time_stop_source_id, effective_duration)
			_time_stop_targets.append(node)
		elif node.has_method("apply_time_stop"):
			node.apply_time_stop(effective_duration)
		if node.has_method("apply_weakpoint"):
			node.apply_weakpoint(time_stop_weakpoint_duration, time_stop_weakpoint_damage_bonus)
	EventBus.time_skill_started.emit(&"time_stop", {})
	_take_self_damage(time_stop_self_damage, &"curse:time_stop")
	if _time_stop_remaining <= 0.0:
		_end_time_stop(true)
	return true


func _end_time_stop(publish_end_event: bool) -> bool:
	if not _time_stop_active:
		return false
	var source_id := _time_stop_source_id
	for target: Node in _time_stop_targets.duplicate():
		if is_instance_valid(target) and target.has_method("clear_time_stop_source"):
			target.clear_time_stop_source(source_id)
	_time_stop_targets.clear()
	_time_stop_source_id = &""
	_time_stop_active = false
	_time_stop_remaining = 0.0
	if publish_end_event:
		EventBus.time_skill_ended.emit(&"time_stop", {})
	return true


func can_rewind(recorder: Node) -> bool:
	if recorder == null or not recorder.has_method("has_snapshot") or not recorder.has_snapshot():
		return false
	var effective_cost := rewind_cost * rewind_cost_multiplier
	if not _can_pay(&"time_rewind", effective_cost):
		return false
	return recorder.has_method("prepare_rewind_transaction") and recorder.has_method("consume_oldest_snapshot") and recorder.has_method("restore_player_state")


func try_rewind(recorder: Node) -> bool:
	var effective_cost := rewind_cost * rewind_cost_multiplier
	if not can_rewind(recorder):
		return false
	var transaction: Dictionary = recorder.prepare_rewind_transaction()
	if transaction.is_empty():
		return false
	var target_snapshot: Dictionary = transaction.get("target_snapshot", {})
	if target_snapshot.is_empty() or not recorder.restore_player_state(target_snapshot):
		return false
	recorder.consume_oldest_snapshot()
	if recorder.has_method("clear_snapshots"):
		recorder.clear_snapshots()
	EventBus.time_skill_started.emit(&"time_rewind", {})
	_pay_cost(&"time_rewind", effective_cost, rewind_cooldown)
	_take_self_damage(rewind_self_damage, &"curse:rewind")
	if rewind_heal > 0.0:
		var health_component := get_parent().get_node_or_null("HealthComponent")
		if health_component != null and health_component.has_method("heal"):
			health_component.heal(rewind_heal)
	rewind_committed.emit(transaction.duplicate(true))
	EventBus.time_skill_ended.emit(&"time_rewind", {})
	return true


func can_time_rift(_rift_position: Vector2 = Vector2.ZERO) -> bool:
	var effective_cost := time_rift_cost * time_rift_cost_multiplier
	var owner_entity := get_parent()
	return owner_entity != null and owner_entity.get_parent() != null and _can_pay(&"time_rift", effective_cost)


func try_time_rift(rift_position: Vector2) -> bool:
	var effective_cost := time_rift_cost * time_rift_cost_multiplier
	if not can_time_rift(rift_position):
		return false
	_pay_cost(&"time_rift", effective_cost, time_rift_cooldown)
	var rift := TimeRiftScene.instantiate()
	rift.duration = time_rift_duration + time_rift_duration_bonus
	rift.radius = time_rift_radius + time_rift_radius_bonus
	rift.slow_multiplier = clampf(time_rift_slow_multiplier - time_rift_slow_bonus, 0.1, 1.0)
	var parent := get_parent().get_parent()
	parent.add_child(rift)
	rift.global_position = rift_position
	_prune_active_rifts()
	_active_rifts.append(rift)
	EventBus.time_skill_started.emit(&"time_rift", {"position": rift_position})
	return true


func can_time_accelerate() -> bool:
	var effective_cost := time_accelerate_cost * time_accelerate_cost_multiplier
	var owner_entity := get_parent()
	if owner_entity == null:
		return false
	if _time_accelerate_active or not owner_entity.has_method("apply_time_acceleration_token"):
		return false
	return _can_pay(&"time_accelerate", effective_cost)


func try_time_accelerate() -> bool:
	var effective_cost := time_accelerate_cost * time_accelerate_cost_multiplier
	var effective_duration := time_accelerate_duration + time_accelerate_duration_bonus
	var effective_multiplier := time_accelerate_multiplier + time_accelerate_multiplier_bonus
	if not can_time_accelerate():
		return false
	var owner_entity := get_parent()
	var next_token := _time_accelerate_token + 1
	if not bool(owner_entity.apply_time_acceleration_token(next_token, effective_multiplier, effective_duration)):
		return false
	_time_accelerate_token = next_token
	_time_accelerate_active = true
	_time_accelerate_publish_lifecycle = true
	_time_accelerate_remaining = maxf(0.0, effective_duration)
	_pay_cost(&"time_accelerate", effective_cost, time_accelerate_cooldown)
	EventBus.time_skill_started.emit(&"time_accelerate", {})
	if _time_accelerate_remaining <= 0.0:
		_end_time_accelerate(_time_accelerate_token, true)
	return true


func apply_legacy_time_acceleration(multiplier: float, duration: float) -> bool:
	if _time_accelerate_active or duration <= 0.0:
		return false
	var owner_entity := get_parent()
	if owner_entity == null or not owner_entity.has_method("apply_time_acceleration_token"):
		return false
	var next_token := _time_accelerate_token + 1
	if not bool(owner_entity.apply_time_acceleration_token(next_token, multiplier, duration)):
		return false
	_time_accelerate_token = next_token
	_time_accelerate_active = true
	_time_accelerate_publish_lifecycle = false
	_time_accelerate_remaining = duration
	return true


func _end_time_accelerate(token: int, publish_end_event: bool) -> bool:
	if not _time_accelerate_active or token != _time_accelerate_token:
		return false
	var should_publish := publish_end_event and _time_accelerate_publish_lifecycle
	_time_accelerate_active = false
	_time_accelerate_publish_lifecycle = false
	_time_accelerate_remaining = 0.0
	var owner_entity := get_parent()
	if owner_entity != null:
		if owner_entity.has_method("clear_time_acceleration"):
			owner_entity.clear_time_acceleration(token)
		elif owner_entity.has_method("_clear_time_acceleration"):
			owner_entity._clear_time_acceleration(token)
	if should_publish:
		EventBus.time_skill_ended.emit(&"time_accelerate", {})
	return true


func cancel_all_time_effects(_reason: StringName) -> void:
	_end_time_stop(true)
	_end_time_accelerate(_time_accelerate_token, true)
	for rift: Node in _active_rifts.duplicate():
		if is_instance_valid(rift) and rift.has_method("cancel"):
			rift.cancel(true)
	_active_rifts.clear()


func reset_runtime_state() -> void:
	_end_time_stop(false)
	_end_time_accelerate(_time_accelerate_token, false)
	_time_accelerate_token += 1
	energy = max_energy
	energy_changed.emit(energy, max_energy)
	for skill_id: StringName in _cooldowns.keys():
		_cooldowns[skill_id] = 0.0
		cooldown_changed.emit(skill_id, 0.0)
	for rift: Node in _active_rifts.duplicate():
		if is_instance_valid(rift) and rift.has_method("cancel"):
			rift.cancel(false)
	_active_rifts.clear()


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


func _tick_active_effects(delta: float) -> void:
	if _time_stop_active and _time_stop_remaining > 0.0:
		_time_stop_remaining = maxf(0.0, _time_stop_remaining - delta)
		if _time_stop_remaining <= 0.0:
			_end_time_stop(true)
	if _time_accelerate_active and _time_accelerate_remaining > 0.0:
		var active_token := _time_accelerate_token
		_time_accelerate_remaining = maxf(0.0, _time_accelerate_remaining - delta)
		if _time_accelerate_remaining <= 0.0:
			_end_time_accelerate(active_token, true)


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


func _prune_active_rifts() -> void:
	for rift: Node in _active_rifts.duplicate():
		if not is_instance_valid(rift) or rift.is_queued_for_deletion():
			_active_rifts.erase(rift)
