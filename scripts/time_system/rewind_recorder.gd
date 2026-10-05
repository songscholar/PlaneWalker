class_name RewindRecorder
extends Node

const SceneScope := preload("res://scripts/player/player_scene_scope.gd")

const TICKET_SCHEMA_VERSION := 1
const GAMEPLAY_FRAMES_PER_SECOND := 60
const SAMPLE_CADENCE_FRAMES := 6
const REQUIRED_SAMPLES_PER_SECOND := 10.0

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
var _run_id: StringName = &""
var _history_revision: int = 0
var _next_sample_sequence: int = 1
var _next_ticket_id: int = 1
var _active_transaction: Dictionary = {}
var _restore_fault_for_test: StringName = &""
var _last_runtime_frame: int = 0


func _process(_delta: float) -> void:
	# Authoritative sampling is driven by PlayerController.advance_action_frame().
	pass


func advance_frame(runtime_frame: int) -> bool:
	if (
		not is_finite(samples_per_second)
		or samples_per_second != REQUIRED_SAMPLES_PER_SECOND
		or not is_finite(record_seconds)
		or record_seconds <= 0.0
	):
		return false
	if runtime_frame <= 0 or runtime_frame != _last_runtime_frame + 1:
		return false
	_last_runtime_frame = runtime_frame
	if runtime_frame % SAMPLE_CADENCE_FRAMES == 0:
		_record_snapshot()
	return true


func has_snapshot() -> bool:
	return not _snapshots.is_empty()


func configure_run(run_id: StringName) -> bool:
	var normalized := StringName(str(run_id).strip_edges())
	if normalized == &"" or str(normalized).contains(":"):
		return false
	if _run_id == normalized:
		return true
	_run_id = normalized
	clear_snapshots()
	_sample_timer = 0.0
	_last_runtime_frame = 0
	_active_transaction.clear()
	return true


func current_run_id() -> StringName:
	return _run_id


func rewind_to_oldest_snapshot() -> void:
	var ticket := prepare_rewind_transaction()
	if not ticket.is_empty():
		commit_rewind_transaction(ticket)


func consume_oldest_snapshot() -> Dictionary:
	if _snapshots.is_empty():
		return {}
	var consumed: Dictionary = (_snapshots.pop_front() as Dictionary).duplicate(true)
	_history_revision += 1
	return consumed


func peek_oldest_snapshot() -> Dictionary:
	if _snapshots.is_empty():
		return {}
	return _snapshots.front().duplicate(true)


func prepare_rewind_transaction(pre_return_position: Variant = null) -> Dictionary:
	if not _active_transaction.is_empty() or not _transaction_contract_ready():
		return {}
	var origin: Vector2 = target.global_position
	if pre_return_position != null:
		if not _finite_vector(pre_return_position):
			return {}
		origin = pre_return_position as Vector2
	var target_snapshot := _validated_recorded_snapshot(peek_oldest_snapshot())
	if target_snapshot.is_empty() or StringName(str(target_snapshot["run_id"])) != _run_id:
		return {}
	if not bool(target.call("can_prepare_gameplay_rewind")):
		return {}
	var health_before_value: Variant = health_component.call("runtime_state_snapshot")
	var player_before_value: Variant = target.call("rewind_transaction_snapshot")
	var time_before_value: Variant = time_manager.call("gameplay_rewind_transaction_snapshot")
	var settlement_value: Variant = time_manager.call("prepare_gameplay_rewind_settlement_context")
	if (
		not health_before_value is Dictionary
		or not player_before_value is Dictionary
		or not time_before_value is Dictionary
		or not settlement_value is Dictionary
	):
		return {}
	var health_before := (health_before_value as Dictionary).duplicate(true)
	var player_before := (player_before_value as Dictionary).duplicate(true)
	var time_before := (time_before_value as Dictionary).duplicate(true)
	var settlement := (settlement_value as Dictionary).duplicate(true)
	if (
		health_before.is_empty()
		or player_before.is_empty()
		or time_before.is_empty()
		or settlement.is_empty()
		or bool(health_before.get("dead", false))
		or StringName(str(health_before.get("run_id", ""))) != _run_id
		or StringName(str(player_before.get("run_id", ""))) != _run_id
		or StringName(str(settlement.get("run_id", ""))) != _run_id
	):
		return {}
	var ledger_before_value: Variant = health_before.get("ledger", {})
	if not ledger_before_value is Dictionary:
		return {}
	var ledger_before := ledger_before_value as Dictionary
	var current_total := float(ledger_before.get("irreversible_hp_loss_total", -1.0))
	var current_revision := int(ledger_before.get("revision", -1))
	var snapshot_total := float(target_snapshot["irreversible_hp_loss_total"])
	var snapshot_revision := int(target_snapshot["irreversible_hp_loss_revision"])
	var irreversible_delta := current_total - snapshot_total
	if (
		not is_finite(current_total)
		or not is_finite(snapshot_total)
		or not is_finite(irreversible_delta)
		or current_total < 0.0
		or snapshot_total < 0.0
		or irreversible_delta < 0.0
		or current_revision < snapshot_revision
	):
		return {}
	var current_max_hp := float(health_before.get("max_hp", 0.0))
	var healing_multiplier := float(health_before.get("healing_multiplier", -1.0))
	if (
		not is_finite(current_max_hp)
		or current_max_hp <= 0.0
		or not is_finite(healing_multiplier)
		or healing_multiplier < 0.0
	):
		return {}
	var target_hp := clampf(
		float(target_snapshot["hp"]) - irreversible_delta,
		0.0,
		current_max_hp
	)
	if not is_finite(target_hp):
		return {}

	var health_transaction_value: Variant = health_component.call("transaction_snapshot")
	if not health_transaction_value is Dictionary or (health_transaction_value as Dictionary).is_empty():
		return {}
	var health_transaction := (health_transaction_value as Dictionary).duplicate(true)
	var destination: Vector2 = target_snapshot["position"]
	var path_samples := _rewind_path_samples(origin, destination)
	var before := {
		"player": player_before,
		"health": health_before,
		"health_transaction": health_transaction,
		"time": time_before,
		"history": _snapshots.duplicate(true),
		"history_revision": _history_revision,
	}
	var participant_revision := {
		"history": _history_revision,
		"ledger": current_revision,
		"action": int((player_before.get("action_state", {}) as Dictionary).get("revision", -1)),
		"coordinator": int((player_before.get("coordinator", {}) as Dictionary).get("generation", -1)),
		"time": int(time_before.get("resource_revision", -1)),
	}
	var ticket_id := _next_ticket_id
	_next_ticket_id += 1
	var fingerprint := _ticket_fingerprint(
		ticket_id,
		_history_revision,
		int(target_snapshot["sample_sequence"]),
		target_hp,
		participant_revision
	)
	var transaction_context := {
		"origin": origin,
		"destination": destination,
		"path_samples": path_samples.duplicate(),
	}
	var public_ticket := {
		"schema_version": TICKET_SCHEMA_VERSION,
		"ticket_id": ticket_id,
		"owner_instance_id": get_instance_id(),
		"run_id": _run_id,
		"history_revision": _history_revision,
		"participant_revision": participant_revision.duplicate(true),
		"before": before.duplicate(true),
		"target_snapshot": target_snapshot.duplicate(true),
		"target_hp": target_hp,
		"fingerprint": fingerprint,
		"origin": origin,
		"destination": destination,
		"path_samples": path_samples.duplicate(),
		"transaction_context": transaction_context.duplicate(true),
	}
	_active_transaction = {
		"public": public_ticket.duplicate(true),
		"before": before,
		"target_snapshot": target_snapshot,
		"target_hp": target_hp,
		"settlement": settlement,
		"transaction_context": transaction_context,
	}
	return public_ticket.duplicate(true)


func commit_rewind_transaction(ticket: Dictionary) -> bool:
	if not _ticket_matches_active(ticket):
		return false
	var before := _active_transaction["before"] as Dictionary
	var target_snapshot := (_active_transaction["target_snapshot"] as Dictionary).duplicate(true)
	var settlement := (_active_transaction["settlement"] as Dictionary).duplicate(true)
	var public_ticket := (_active_transaction["public"] as Dictionary).duplicate(true)
	if not _participants_match_before(before):
		var discarded := bool(health_component.call(
			"discard_transaction_snapshot",
			(before["health_transaction"] as Dictionary).duplicate(true)
		))
		_active_transaction.clear()
		if not discarded:
			target.process_mode = Node.PROCESS_MODE_DISABLED
			push_error("Gameplay Rewind stale transaction discard failed closed")
		return false
	if _consume_restore_fault(&"preflight_action"):
		_rollback_active_transaction(&"preflight_failed")
		return false

	if not bool(target.call("install_gameplay_rewind_state", target_snapshot)):
		_rollback_active_transaction(&"action_install_failed")
		return false
	if _consume_restore_fault(&"after_action_install"):
		_rollback_active_transaction(&"after_action_install")
		return false

	var health_publication_value: Variant = health_component.call(
		"install_rewind_transaction_state",
		float(_active_transaction["target_hp"]),
		float(settlement["self_damage"]),
		&"curse:rewind",
		int(settlement["self_damage_token"]),
		int(settlement["self_damage_generation"]),
		float(settlement["heal"]),
		_run_id
	)
	if not health_publication_value is Dictionary or not bool((health_publication_value as Dictionary).get("ok", false)):
		_rollback_active_transaction(&"health_install_failed")
		return false
	var health_publication := (health_publication_value as Dictionary).duplicate(true)
	if _consume_restore_fault(&"after_health_install"):
		_rollback_active_transaction(&"after_health_install")
		return false

	if not bool(time_manager.call(
		"install_gameplay_rewind_settlement",
		settlement,
		(before["time"] as Dictionary).duplicate(true)
	)):
		_rollback_active_transaction(&"time_install_failed")
		return false
	if _consume_restore_fault(&"after_time_install"):
		_rollback_active_transaction(&"after_time_install")
		return false
	if _consume_restore_fault(&"before_history_consume"):
		_rollback_active_transaction(&"before_history_consume")
		return false

	_snapshots.clear()
	_history_revision += 1
	if _consume_restore_fault(&"after_history_consume"):
		_rollback_active_transaction(&"after_history_consume")
		return false
	if not _verify_committed_state(health_publication) or _consume_restore_fault(&"final_verification"):
		_rollback_active_transaction(&"final_verification_failed")
		return false
	if not bool(health_component.call(
		"discard_transaction_snapshot",
		(before["health_transaction"] as Dictionary).duplicate(true)
	)):
		_rollback_active_transaction(&"ledger_commit_failed")
		return false

	_active_transaction.clear()
	target.call("mark_gameplay_rewind_replay_boundary")
	if not bool(health_publication.get("died", false)):
		health_component.call("apply_invulnerability", 0.5)
	SceneScope.event_bus(self).time_skill_started.emit(&"time_rewind", {})
	health_component.call("publish_rewind_transaction_state", health_publication)
	time_manager.call(
		"publish_gameplay_rewind_commit",
		public_ticket.duplicate(true),
		(before["time"] as Dictionary).duplicate(true)
	)
	SceneScope.event_bus(self).time_skill_ended.emit(&"time_rewind", {})
	return true


func rollback_rewind_transaction(ticket: Dictionary) -> Dictionary:
	if not _ticket_matches_active(ticket):
		return {"ok": false, "code": &"INVALID_TICKET"}
	var before := _active_transaction["before"] as Dictionary
	var discarded := bool(health_component.call(
		"discard_transaction_snapshot",
		(before["health_transaction"] as Dictionary).duplicate(true)
	))
	_active_transaction.clear()
	return {
		"ok": discarded,
		"code": &"ROLLED_BACK" if discarded else &"ROLLBACK_FAILED",
	}


func set_restore_fault_for_test(stage: StringName) -> void:
	_restore_fault_for_test = stage


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
	if _snapshots.is_empty():
		return
	_snapshots.clear()
	_history_revision += 1


func reset_runtime_state() -> bool:
	if _consume_restore_fault(&"reset_runtime_state"):
		return false
	if not _active_transaction.is_empty():
		return false
	clear_snapshots()
	_sample_timer = 0.0
	_last_runtime_frame = 0
	return true


func _record_snapshot() -> void:
	var hp_loss_state: Dictionary = (
		health_component.call("hp_loss_state")
		if health_component != null and health_component.has_method("hp_loss_state")
		else {"irreversible_hp_loss_total": 0.0, "revision": 0}
	)
	_snapshots.append({
		"sample_sequence": _next_sample_sequence,
		"run_id": _run_id,
		"position": target.global_position,
		"facing": _capture_facing(),
		"velocity": target.get("velocity") if _has_property(target, &"velocity") else Vector2.ZERO,
		"hp": health_component.current_hp,
		"irreversible_hp_loss_total": float(hp_loss_state.get("irreversible_hp_loss_total", 0.0)),
		"irreversible_hp_loss_revision": int(hp_loss_state.get("revision", 0)),
		"safe_action": _capture_safe_action(),
	})
	_next_sample_sequence += 1
	_history_revision += 1
	var max_samples := int(record_seconds * samples_per_second)
	while _snapshots.size() > max_samples:
		_snapshots.pop_front()
		_history_revision += 1


func _transaction_contract_ready() -> bool:
	return (
		_run_id != &""
		and not _snapshots.is_empty()
		and target != null
		and is_instance_valid(target)
		and health_component != null
		and is_instance_valid(health_component)
		and time_manager != null
		and is_instance_valid(time_manager)
		and target.has_method("can_prepare_gameplay_rewind")
		and target.has_method("rewind_transaction_snapshot")
		and target.has_method("install_gameplay_rewind_state")
		and target.has_method("restore_rewind_transaction_snapshot")
		and target.has_method("gameplay_rewind_commit_matches")
		and target.has_method("mark_gameplay_rewind_replay_boundary")
		and health_component.has_method("runtime_state_snapshot")
		and health_component.has_method("transaction_snapshot")
		and health_component.has_method("restore_transaction_snapshot")
		and health_component.has_method("discard_transaction_snapshot")
		and health_component.has_method("install_rewind_transaction_state")
		and health_component.has_method("publish_rewind_transaction_state")
		and time_manager.has_method("gameplay_rewind_transaction_snapshot")
		and time_manager.has_method("prepare_gameplay_rewind_settlement_context")
		and time_manager.has_method("install_gameplay_rewind_settlement")
		and time_manager.has_method("restore_gameplay_rewind_transaction_snapshot")
		and time_manager.has_method("publish_gameplay_rewind_commit")
	)


func _validated_recorded_snapshot(value: Dictionary) -> Dictionary:
	for field: String in [
		"sample_sequence", "run_id", "position", "facing", "velocity", "hp",
		"irreversible_hp_loss_total", "irreversible_hp_loss_revision", "safe_action",
	]:
		if not value.has(field):
			return {}
	if (
		typeof(value["sample_sequence"]) != TYPE_INT
		or int(value["sample_sequence"]) <= 0
		or typeof(value["run_id"]) not in [TYPE_STRING, TYPE_STRING_NAME]
		or str(value["run_id"]).is_empty()
		or not _finite_vector(value["position"])
		or not _finite_vector(value["facing"])
		or (value["facing"] as Vector2).length_squared() <= 0.001
		or not _finite_vector(value["velocity"])
		or typeof(value["hp"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["hp"]))
		or float(value["hp"]) < 0.0
		or typeof(value["irreversible_hp_loss_total"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["irreversible_hp_loss_total"]))
		or float(value["irreversible_hp_loss_total"]) < 0.0
		or typeof(value["irreversible_hp_loss_revision"]) != TYPE_INT
		or int(value["irreversible_hp_loss_revision"]) < 0
		or not value["safe_action"] is Dictionary
	):
		return {}
	return value.duplicate(true)


func _rewind_path_samples(origin: Vector2, destination: Vector2) -> Array[Vector2]:
	var path_samples: Array[Vector2] = [origin]
	for index: int in range(_snapshots.size() - 1, -1, -1):
		var sample: Dictionary = _snapshots[index]
		if not _finite_vector(sample.get("position")):
			continue
		var sample_position: Vector2 = sample["position"]
		if path_samples[-1] != sample_position:
			path_samples.append(sample_position)
	if path_samples[-1] != destination:
		path_samples.append(destination)
	return path_samples


func _ticket_fingerprint(
	ticket_id: int,
	history_revision: int,
	sample_sequence: int,
	target_hp: float,
	participant_revision: Dictionary
) -> String:
	return (
		"%d|%d|%d|%s|%d|%.9f|%s"
		% [
			TICKET_SCHEMA_VERSION,
			ticket_id,
			get_instance_id(),
			str(_run_id),
			history_revision,
			target_hp,
			JSON.stringify(participant_revision, "", false),
		]
	).sha256_text()


func _ticket_matches_active(ticket: Dictionary) -> bool:
	if _active_transaction.is_empty() or not _active_transaction.get("public") is Dictionary:
		return false
	var authoritative := _active_transaction["public"] as Dictionary
	return (
		typeof(ticket.get("schema_version")) == TYPE_INT
		and int(ticket.get("schema_version")) == TICKET_SCHEMA_VERSION
		and typeof(ticket.get("owner_instance_id")) == TYPE_INT
		and int(ticket.get("owner_instance_id")) == get_instance_id()
		and ticket == authoritative
	)


func _participants_match_before(before: Dictionary) -> bool:
	if (
		_history_revision != int(before.get("history_revision", -1))
		or _snapshots != before.get("history", [])
		or not _player_participant_matches_before(before.get("player", {}))
		or health_component.call("runtime_state_snapshot") != before.get("health", {})
		or time_manager.call("gameplay_rewind_transaction_snapshot") != before.get("time", {})
	):
		return false
	return true


func _player_participant_matches_before(before_value: Variant) -> bool:
	if not before_value is Dictionary:
		return false
	var current_value: Variant = target.call("rewind_transaction_snapshot")
	if not current_value is Dictionary:
		return false
	var before := before_value as Dictionary
	var current := (current_value as Dictionary).duplicate(true)
	if not before.get("position") is Vector2 or not current.get("position") is Vector2:
		return false
	# The prepared transaction owns the rewind origin, so movement after prepare
	# may change only the live position. Every other player participant field
	# remains drift-protected.
	current["position"] = before["position"]
	return current == before


func _verify_committed_state(health_publication: Dictionary) -> bool:
	var target_snapshot := _active_transaction["target_snapshot"] as Dictionary
	var before := _active_transaction["before"] as Dictionary
	var player_before := before["player"] as Dictionary
	var coordinator_before := player_before.get("coordinator", {}) as Dictionary
	var committed_guard := coordinator_before.get("committed_payload_guard", {}) as Dictionary
	return (
		_snapshots.is_empty()
		and bool(target.call(
			"gameplay_rewind_commit_matches",
			target_snapshot.duplicate(true),
			committed_guard.duplicate(true)
		))
		and is_equal_approx(
			float(health_component.get("current_hp")),
			float(health_publication.get("final_hp", -1.0))
		)
		and bool(health_component.get("dead")) == bool(health_publication.get("died", false))
	)


func _rollback_active_transaction(_reason: StringName) -> bool:
	if _active_transaction.is_empty() or not _active_transaction.get("before") is Dictionary:
		return false
	var before := _active_transaction["before"] as Dictionary
	var time_ok := bool(time_manager.call(
		"restore_gameplay_rewind_transaction_snapshot",
		(before["time"] as Dictionary).duplicate(true)
	))
	var health_ok := bool(health_component.call(
		"restore_transaction_snapshot",
		(before["health_transaction"] as Dictionary).duplicate(true)
	))
	var player_ok := bool(target.call(
		"restore_rewind_transaction_snapshot",
		(before["player"] as Dictionary).duplicate(true)
	))
	_snapshots = (before["history"] as Array).duplicate(true)
	_history_revision = int(before["history_revision"])
	var verified := (
		time_ok
		and health_ok
		and player_ok
		and _participants_match_before(before)
	)
	_active_transaction.clear()
	if not verified:
		target.process_mode = Node.PROCESS_MODE_DISABLED
		push_error("Gameplay Rewind rollback failed closed")
	return verified


func _consume_restore_fault(stage: StringName) -> bool:
	if _restore_fault_for_test != stage:
		return false
	_restore_fault_for_test = &""
	return true


func _finite_vector(value: Variant) -> bool:
	return value is Vector2 and is_finite((value as Vector2).x) and is_finite((value as Vector2).y)


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
