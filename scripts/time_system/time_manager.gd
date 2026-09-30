class_name TimeManager
extends Node

const TimeRiftScene := preload("res://scenes/time/time_rift.tscn")
const TimeAbilityIdsScript := preload("res://scripts/time_system/time_ability_ids.gd")

const REWIND_WEAPON_WINDOW_DURATION := 2.0
const MAX_WEAPON_STOP_EXTENSION_FRAMES := 60
const WEAPON_REPLAY_SNAPSHOT_SCHEMA_VERSION := 2
const WEAPON_REPLAY_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"time_energy_state",
	"stop_active",
	"stop_source_sequence",
	"stop_source_id",
	"stop_remaining",
	"stop_extension_frames",
	"stop_extension_tokens",
	"rewind_window_remaining",
	"rewind_window_generation",
	"rewind_window_claimed",
]

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
var _active_rift_generations: Dictionary = {}
var _time_rift_source_sequence: int = 0
var _time_stop_remaining: float = 0.0
var _time_stop_active: bool = false
var _time_stop_source_sequence: int = 0
var _time_stop_source_id: StringName = &""
var _time_stop_targets: Array[Node] = []
var _weapon_stop_extension_frames: int = 0
var _weapon_stop_extension_tokens: Dictionary = {}
var _time_accelerate_remaining: float = 0.0
var _time_accelerate_active: bool = false
var _time_accelerate_token: int = 0
var _time_accelerate_publish_lifecycle: bool = false
var _rewind_weapon_window_remaining: float = 0.0
var _rewind_weapon_window_generation: int = 0
var _rewind_weapon_window_claimed: bool = false
var _resource_revision: int = 1
var _weapon_replay_restore_transaction_active: bool = false
var _weapon_replay_restore_transaction_token: int = 0
var _next_weapon_replay_restore_transaction_token: int = 1
var _weapon_replay_restore_transaction_before: Dictionary = {}
var _irreversible_self_damage_generation: int = 1
var _next_irreversible_self_damage_token: int = 1


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
	var previous_energy := energy
	max_energy = stats.time_energy_max
	energy_regen = stats.time_energy_regen
	if max_energy > previous_max_energy:
		energy += max_energy - previous_max_energy
	energy = clampf(energy, 0.0, max_energy)
	if max_energy != previous_max_energy or energy != previous_energy:
		_resource_revision += 1
	energy_changed.emit(energy, max_energy)


func canonical_skill_id(skill_id: StringName) -> StringName:
	return TimeAbilityIdsScript.canonical_id(skill_id)


func action_skill_id(skill_id: StringName) -> StringName:
	return TimeAbilityIdsScript.action_id(skill_id)


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
	_weapon_stop_extension_frames = 0
	_weapon_stop_extension_tokens.clear()
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
	if not _take_self_damage(time_stop_self_damage, &"curse:time_stop"):
		push_error("Time Stop irreversible self-damage claim failed")
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
	_weapon_stop_extension_frames = 0
	_weapon_stop_extension_tokens.clear()
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
	if not _take_self_damage(rewind_self_damage, &"curse:rewind"):
		push_error("Rewind irreversible self-damage claim failed")
	if rewind_heal > 0.0:
		var health_component := get_parent().get_node_or_null("HealthComponent")
		if health_component != null and health_component.has_method("heal"):
			health_component.heal(rewind_heal)
	_rewind_weapon_window_generation += 1
	_rewind_weapon_window_remaining = REWIND_WEAPON_WINDOW_DURATION
	_rewind_weapon_window_claimed = false
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
	_time_rift_source_sequence += 1
	_active_rifts.append(rift)
	_active_rift_generations[rift] = _time_rift_source_sequence
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
	_clear_rewind_weapon_window()
	_prune_active_rifts()
	for rift: Node in _active_rifts.duplicate():
		if rift.has_method("cancel"):
			rift.cancel(true)
	_active_rifts.clear()
	_active_rift_generations.clear()


func reset_runtime_state() -> void:
	_clear_weapon_replay_restore_transaction()
	_end_time_stop(false)
	_end_time_accelerate(_time_accelerate_token, false)
	_clear_rewind_weapon_window()
	_time_accelerate_token += 1
	energy = max_energy
	# A full runtime reset invalidates any prepared external-resource ticket even
	# when the numeric balance was already at maximum.
	_resource_revision += 1
	energy_changed.emit(energy, max_energy)
	for skill_id: StringName in _cooldowns.keys():
		_cooldowns[skill_id] = 0.0
		cooldown_changed.emit(skill_id, 0.0)
	_prune_active_rifts()
	for rift: Node in _active_rifts.duplicate():
		if rift.has_method("cancel"):
			rift.cancel(false)
	_active_rifts.clear()
	_active_rift_generations.clear()


func restore_energy(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0:
		return
	var energy_before := energy
	energy = minf(max_energy, energy + amount)
	if energy != energy_before:
		_resource_revision += 1
	energy_changed.emit(energy, max_energy)


func weapon_interaction_context() -> Dictionary:
	_prune_active_rifts()
	var active_rift_descriptors := _active_rift_descriptors()
	var active_rift_generation := (
		int(active_rift_descriptors.back().get("generation", 0))
		if not active_rift_descriptors.is_empty()
		else 0
	)
	return {
		"stop_active": _time_stop_active,
		"stop_generation": _time_stop_source_sequence if _time_stop_active else 0,
		"stop_remaining_frames": roundi(_time_stop_remaining * 60.0),
		"stop_extension_remaining_frames": maxi(
			0,
			MAX_WEAPON_STOP_EXTENSION_FRAMES - _weapon_stop_extension_frames
		),
		"accelerate_active": _time_accelerate_active,
		"accelerate_generation": _time_accelerate_token if _time_accelerate_active else 0,
		"rewind_echo_available": (
			_rewind_weapon_window_remaining > 0.0
			and not _rewind_weapon_window_claimed
		),
		"rewind_echo_generation": _rewind_weapon_window_generation,
		"rift_active": not _active_rifts.is_empty(),
		"rift_generation": active_rift_generation,
		"active_rift_count": _active_rifts.size(),
		"active_rifts": active_rift_descriptors,
	}


func weapon_replay_snapshot() -> Dictionary:
	return {
		"schema_version": WEAPON_REPLAY_SNAPSHOT_SCHEMA_VERSION,
		"time_energy_state": resource_state(&"time_energy"),
		"stop_active": _time_stop_active,
		"stop_source_sequence": _time_stop_source_sequence,
		"stop_source_id": str(_time_stop_source_id),
		"stop_remaining": _time_stop_remaining,
		"stop_extension_frames": _weapon_stop_extension_frames,
		"stop_extension_tokens": _weapon_stop_extension_tokens.duplicate(true),
		"rewind_window_remaining": _rewind_weapon_window_remaining,
		"rewind_window_generation": _rewind_weapon_window_generation,
		"rewind_window_claimed": _rewind_weapon_window_claimed,
	}


func begin_weapon_replay_restore_transaction() -> int:
	if _weapon_replay_restore_transaction_active:
		return 0
	var before := weapon_replay_snapshot()
	if not can_restore_weapon_replay_snapshot(before):
		return 0
	var transaction_token := _next_weapon_replay_restore_transaction_token
	_next_weapon_replay_restore_transaction_token += 1
	_weapon_replay_restore_transaction_active = true
	_weapon_replay_restore_transaction_token = transaction_token
	_weapon_replay_restore_transaction_before = before.duplicate(true)
	return transaction_token


func commit_weapon_replay_restore_transaction(transaction_token: int) -> bool:
	if (
		not _weapon_replay_restore_transaction_active
		or transaction_token <= 0
		or transaction_token != _weapon_replay_restore_transaction_token
	):
		return false
	var before := _weapon_replay_restore_transaction_before.duplicate(true)
	var after := weapon_replay_snapshot()
	if (
		before.is_empty()
		or after.is_empty()
		or not can_restore_weapon_replay_snapshot(before)
		or not can_restore_weapon_replay_snapshot(after)
	):
		if can_restore_weapon_replay_snapshot(before):
			_install_weapon_replay_snapshot_state(before)
		_clear_weapon_replay_restore_transaction()
		return false
	var previous_stop_source_id := StringName(str(before.get("stop_source_id", "")))
	var stop_projection_changed := _weapon_replay_stop_projection(before) != (
		_weapon_replay_stop_projection(after)
	)
	var energy_changed_during_transaction := float(
		(before.get("time_energy_state", {}) as Dictionary).get("current", energy)
	) != energy
	_clear_weapon_replay_restore_transaction()
	if stop_projection_changed:
		_reconcile_replay_time_stop_targets(previous_stop_source_id)
	if energy_changed_during_transaction:
		energy_changed.emit(energy, max_energy)
	return true


func rollback_weapon_replay_restore_transaction(transaction_token: int) -> bool:
	if (
		not _weapon_replay_restore_transaction_active
		or transaction_token <= 0
		or transaction_token != _weapon_replay_restore_transaction_token
	):
		return false
	var before := _weapon_replay_restore_transaction_before.duplicate(true)
	if not can_restore_weapon_replay_snapshot(before):
		_clear_weapon_replay_restore_transaction()
		return false
	var restored := _install_weapon_replay_snapshot_state(before)
	_clear_weapon_replay_restore_transaction()
	return restored and weapon_replay_snapshot() == before


func can_restore_weapon_replay_snapshot(value: Dictionary) -> bool:
	if value.size() != WEAPON_REPLAY_SNAPSHOT_FIELDS.size():
		return false
	for field: String in WEAPON_REPLAY_SNAPSHOT_FIELDS:
		if not value.has(field):
			return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != WEAPON_REPLAY_SNAPSHOT_SCHEMA_VERSION
		or not value["time_energy_state"] is Dictionary
		or not can_restore_resource_state(
			&"time_energy",
			(value["time_energy_state"] as Dictionary).duplicate(true)
		)
		or typeof(value["stop_active"]) != TYPE_BOOL
		or typeof(value["stop_source_sequence"]) != TYPE_INT
		or int(value["stop_source_sequence"]) < 0
		or typeof(value["stop_source_id"]) not in [TYPE_STRING, TYPE_STRING_NAME]
		or typeof(value["stop_remaining"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["stop_remaining"]))
		or float(value["stop_remaining"]) < 0.0
		or typeof(value["stop_extension_frames"]) != TYPE_INT
		or int(value["stop_extension_frames"]) < 0
		or int(value["stop_extension_frames"]) > MAX_WEAPON_STOP_EXTENSION_FRAMES
		or not value["stop_extension_tokens"] is Dictionary
		or typeof(value["rewind_window_remaining"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["rewind_window_remaining"]))
		or float(value["rewind_window_remaining"]) < 0.0
		or typeof(value["rewind_window_generation"]) != TYPE_INT
		or int(value["rewind_window_generation"]) < 0
		or typeof(value["rewind_window_claimed"]) != TYPE_BOOL
	):
		return false
	var stop_active := bool(value["stop_active"])
	if stop_active != (not str(value["stop_source_id"]).is_empty()):
		return false
	if stop_active:
		if int(value["stop_source_sequence"]) <= 0 or float(value["stop_remaining"]) <= 0.0:
			return false
	elif not is_zero_approx(float(value["stop_remaining"])):
		return false
	var stop_tokens := value["stop_extension_tokens"] as Dictionary
	for token_value: Variant in stop_tokens.keys():
		if (
			typeof(token_value) != TYPE_INT
			or int(token_value) <= 0
			or typeof(stop_tokens[token_value]) != TYPE_BOOL
			or not bool(stop_tokens[token_value])
		):
			return false
	if not stop_active and (int(value["stop_extension_frames"]) != 0 or not stop_tokens.is_empty()):
		return false
	var rewind_remaining := float(value["rewind_window_remaining"])
	var rewind_generation := int(value["rewind_window_generation"])
	var rewind_claimed := bool(value["rewind_window_claimed"])
	if rewind_remaining > 0.0 and (rewind_generation <= 0 or rewind_claimed):
		return false
	if rewind_claimed and (rewind_generation <= 0 or not is_zero_approx(rewind_remaining)):
		return false
	if rewind_generation == 0 and (not is_zero_approx(rewind_remaining) or rewind_claimed):
		return false
	return true


func restore_weapon_replay_snapshot(value: Dictionary) -> bool:
	if not can_restore_weapon_replay_snapshot(value):
		return false
	var before := weapon_replay_snapshot()
	if before == value:
		return true
	var energy_before := energy
	var previous_stop_source_id := _time_stop_source_id
	if not _install_weapon_replay_snapshot_state(value):
		_install_weapon_replay_snapshot_state(before)
		return false
	if not _weapon_replay_restore_transaction_active:
		_reconcile_replay_time_stop_targets(previous_stop_source_id)
	if energy != energy_before and not _weapon_replay_restore_transaction_active:
		energy_changed.emit(energy, max_energy)
	return true


func _install_weapon_replay_snapshot_state(value: Dictionary) -> bool:
	var time_energy_state := value["time_energy_state"] as Dictionary
	energy = float(time_energy_state["current"])
	_resource_revision = int(time_energy_state["revision"])
	_time_stop_active = bool(value["stop_active"])
	_time_stop_source_sequence = int(value["stop_source_sequence"])
	_time_stop_source_id = StringName(str(value["stop_source_id"]))
	_time_stop_remaining = float(value["stop_remaining"])
	_weapon_stop_extension_frames = int(value["stop_extension_frames"])
	_weapon_stop_extension_tokens = (value["stop_extension_tokens"] as Dictionary).duplicate(true)
	_rewind_weapon_window_remaining = float(value["rewind_window_remaining"])
	_rewind_weapon_window_generation = int(value["rewind_window_generation"])
	_rewind_weapon_window_claimed = bool(value["rewind_window_claimed"])
	return weapon_replay_snapshot() == value


func _weapon_replay_stop_projection(value: Dictionary) -> Dictionary:
	return {
		"active": bool(value.get("stop_active", false)),
		"source_id": str(value.get("stop_source_id", "")),
		"remaining": float(value.get("stop_remaining", 0.0)),
	}


func _clear_weapon_replay_restore_transaction() -> void:
	_weapon_replay_restore_transaction_active = false
	_weapon_replay_restore_transaction_token = 0
	_weapon_replay_restore_transaction_before.clear()


func _reconcile_replay_time_stop_targets(previous_source_id: StringName) -> void:
	if previous_source_id != &"":
		for target: Node in _time_stop_targets.duplicate():
			if is_instance_valid(target) and target.has_method("clear_time_stop_source"):
				target.clear_time_stop_source(previous_source_id)
	_time_stop_targets.clear()
	if not _time_stop_active or _time_stop_source_id == &"" or _time_stop_remaining <= 0.0:
		return
	for node: Node in get_tree().get_nodes_in_group("time_stoppable"):
		if node.has_method("apply_time_stop_source"):
			node.apply_time_stop_source(_time_stop_source_id, _time_stop_remaining)
			_time_stop_targets.append(node)
		elif node.has_method("apply_time_stop"):
			node.apply_time_stop(_time_stop_remaining)


func extend_stop_for_weapon(action_token: int, extension_frames: int) -> bool:
	if (
		not _time_stop_active
		or action_token <= 0
		or extension_frames <= 0
		or _weapon_stop_extension_tokens.has(action_token)
	):
		return false
	var available := MAX_WEAPON_STOP_EXTENSION_FRAMES - _weapon_stop_extension_frames
	var granted := mini(extension_frames, available)
	if granted <= 0:
		return false
	_weapon_stop_extension_tokens[action_token] = true
	_weapon_stop_extension_frames += granted
	_time_stop_remaining += float(granted) / 60.0
	return true


func claim_weapon_interaction(interaction_id: StringName, generation: int) -> bool:
	if interaction_id != &"bow_rewind_echo":
		return false
	if (
		generation <= 0
		or generation != _rewind_weapon_window_generation
		or _rewind_weapon_window_remaining <= 0.0
		or _rewind_weapon_window_claimed
	):
		return false
	_rewind_weapon_window_claimed = true
	_rewind_weapon_window_remaining = 0.0
	return true


func resource_state(resource_id: StringName) -> Dictionary:
	if resource_id != &"time_energy":
		return {
			"ok": false,
			"code": &"RESOURCE_NOT_FOUND",
			"context": {"resource_id": str(resource_id)},
		}
	return {
		"ok": true,
		"code": &"OK",
		"resource_id": "time_energy",
		"current": energy,
		"minimum": 0.0,
		"maximum": max_energy,
		"revision": _resource_revision,
		"context": {},
	}


func can_restore_resource_state(resource_id: StringName, state: Dictionary) -> bool:
	const RESOURCE_STATE_FIELDS: Array[String] = [
		"ok",
		"code",
		"resource_id",
		"current",
		"minimum",
		"maximum",
		"revision",
		"context",
	]
	if resource_id != &"time_energy" or state.size() != RESOURCE_STATE_FIELDS.size():
		return false
	for field: String in RESOURCE_STATE_FIELDS:
		if not state.has(field):
			return false
	for field: String in ["current", "minimum", "maximum"]:
		var value: Variant = state[field]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	return (
		typeof(state["ok"]) == TYPE_BOOL
		and bool(state["ok"])
		and typeof(state["code"]) in [TYPE_STRING, TYPE_STRING_NAME]
		and str(state["code"]) == "OK"
		and typeof(state["resource_id"]) in [TYPE_STRING, TYPE_STRING_NAME]
		and str(state["resource_id"]) == "time_energy"
		and float(state["minimum"]) == 0.0
		and float(state["maximum"]) == max_energy
		and float(state["current"]) >= 0.0
		and float(state["current"]) <= max_energy
		and typeof(state["revision"]) == TYPE_INT
		and int(state["revision"]) > 0
		and state["context"] is Dictionary
		and (state["context"] as Dictionary).is_empty()
	)


func try_spend_resource(
	resource_id: StringName,
	amount: float,
	expected_revision: int,
	reason: StringName
) -> Dictionary:
	if resource_id != &"time_energy":
		return {
			"ok": false,
			"code": &"RESOURCE_NOT_FOUND",
			"context": {"resource_id": str(resource_id)},
		}
	if not is_finite(amount) or amount < 0.0:
		return {
			"ok": false,
			"code": &"INVALID_RESOURCE_AMOUNT",
			"context": {"resource_id": str(resource_id)},
		}
	if expected_revision != _resource_revision:
		return {
			"ok": false,
			"code": &"RESOURCE_REVISION_MISMATCH",
			"context": {
				"resource_id": str(resource_id),
				"expected_revision": expected_revision,
				"actual_revision": _resource_revision,
			},
		}
	if energy < amount:
		return {
			"ok": false,
			"code": &"INSUFFICIENT_RESOURCE",
			"context": {
				"resource_id": str(resource_id),
				"required": amount,
				"current": energy,
			},
		}
	var before := energy
	if amount > 0.0:
		energy = maxf(0.0, energy - amount)
		_resource_revision += 1
		energy_changed.emit(energy, max_energy)
	return {
		"ok": true,
		"code": &"OK",
		"resource_id": str(resource_id),
		"before": before,
		"after": energy,
		"revision": _resource_revision,
		"reason": str(reason),
		"context": {},
	}


func restore_resource_state(resource_id: StringName, state: Dictionary) -> bool:
	if not can_restore_resource_state(resource_id, state):
		return false
	var energy_before := energy
	energy = float(state["current"])
	_resource_revision = int(state["revision"])
	if energy != energy_before and not _weapon_replay_restore_transaction_active:
		energy_changed.emit(energy, max_energy)
	return true


func get_cooldown(skill_id: StringName) -> float:
	return float(_cooldowns.get(skill_id, 0.0))


func _regen_energy(delta: float) -> void:
	if energy >= max_energy:
		return
	var regen_multiplier := low_energy_regen_multiplier if energy < low_energy_threshold else 1.0
	var energy_before := energy
	energy = minf(max_energy, energy + energy_regen * regen_multiplier * delta)
	if energy != energy_before:
		_resource_revision += 1
	energy_changed.emit(energy, max_energy)


func _tick_cooldowns(delta: float) -> void:
	for skill_id: StringName in _cooldowns.keys():
		var previous := float(_cooldowns[skill_id])
		if previous <= 0.0:
			continue
		_cooldowns[skill_id] = maxf(0.0, previous - delta)
		cooldown_changed.emit(skill_id, _cooldowns[skill_id])


func _tick_active_effects(delta: float) -> void:
	if _rewind_weapon_window_remaining > 0.0:
		_rewind_weapon_window_remaining = maxf(0.0, _rewind_weapon_window_remaining - delta)
		if _rewind_weapon_window_remaining <= 0.0:
			_rewind_weapon_window_claimed = true
	if _time_stop_active and _time_stop_remaining > 0.0:
		_time_stop_remaining = maxf(0.0, _time_stop_remaining - delta)
		if _time_stop_remaining <= 0.0:
			_end_time_stop(true)
	if _time_accelerate_active and _time_accelerate_remaining > 0.0:
		var active_token := _time_accelerate_token
		_time_accelerate_remaining = maxf(0.0, _time_accelerate_remaining - delta)
		if _time_accelerate_remaining <= 0.0:
			_end_time_accelerate(active_token, true)


func _clear_rewind_weapon_window() -> void:
	_rewind_weapon_window_remaining = 0.0
	_rewind_weapon_window_claimed = false


func _can_pay(skill_id: StringName, cost: float) -> bool:
	return energy >= cost and get_cooldown(skill_id) <= 0.0


func _pay_cost(skill_id: StringName, cost: float, cooldown: float) -> void:
	var energy_before := energy
	energy = maxf(0.0, energy - cost)
	if energy != energy_before:
		_resource_revision += 1
	_cooldowns[skill_id] = cooldown
	energy_changed.emit(energy, max_energy)
	cooldown_changed.emit(skill_id, cooldown)


func _take_self_damage(amount: float, source_tag: StringName) -> bool:
	if amount <= 0.0:
		return true
	var owner_entity := get_parent()
	var health_component := owner_entity.get_node_or_null("HealthComponent")
	if health_component == null or not health_component.has_method("lose_health_irreversible"):
		return false
	var claim_token := _next_irreversible_self_damage_token
	_next_irreversible_self_damage_token += 1
	var resolution: Variant = health_component.call(
		"lose_health_irreversible",
		amount,
		source_tag,
		claim_token,
		_irreversible_self_damage_generation
	)
	return (
		resolution is RefCounted
		and not bool((resolution as RefCounted).call("is_prevented"))
		and float((resolution as RefCounted).call("finalized_damage")) > 0.0
	)


func _prune_active_rifts() -> void:
	var valid_rifts: Array[Node] = []
	var valid_generations: Dictionary = {}
	for rift_value: Variant in _active_rifts:
		if not is_instance_valid(rift_value):
			continue
		var rift := rift_value as Node
		if rift == null or rift.is_queued_for_deletion():
			continue
		valid_rifts.append(rift)
		var generation := int(_active_rift_generations.get(rift, 0))
		if generation > 0:
			valid_generations[rift] = generation
	_active_rifts = valid_rifts
	_active_rift_generations = valid_generations


func _active_rift_descriptors() -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	for rift: Node in _active_rifts:
		var generation := int(_active_rift_generations.get(rift, 0))
		if generation <= 0 or not rift is Node2D:
			continue
		var radius_value: Variant = rift.get("radius")
		if typeof(radius_value) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var radius := float(radius_value)
		if not is_finite(radius) or radius <= 0.0:
			continue
		descriptors.append({
			"generation": generation,
			"center": (rift as Node2D).global_position,
			"radius": radius,
		})
	descriptors.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("generation", 0)) < int(right.get("generation", 0))
	)
	return descriptors
