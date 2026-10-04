class_name RoomRuntime
extends Node

signal spawn_warning_requested(spawn_definition: Dictionary, duration: float)
signal spawn_requested(spawn_definition: Dictionary)
signal room_started(room_id: StringName, revision: int)
signal room_cleared(room_id: StringName, revision: int)
signal terminal_committed(context: Dictionary, revision: int)
signal runtime_failed(context: Dictionary)

const CommandResultScript := preload("res://scripts/application/command_result.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")

var _facade: RefCounted
var _catalog: RefCounted
var _run_seed: int = 0
var _runner: Node
var _room_active: bool = false
var _room_terminal: bool = false
var _failure: Dictionary = {}
var _current_room: Dictionary = {}
var _current_room_id: StringName = &""
var _emit_room_started: bool = true
var _event_continuation: Dictionary = {}


func configure(
	facade: RefCounted,
	encounter_catalog: RefCounted,
	_room_definitions: Array[Dictionary],
	run_seed: int,
	encounter_runner: Node,
	emit_room_started: bool = true
) -> void:
	_disconnect_runner()
	_facade = facade
	_catalog = encounter_catalog
	_run_seed = run_seed
	_runner = encounter_runner
	_room_active = false
	_room_terminal = false
	_failure.clear()
	_current_room.clear()
	_current_room_id = &""
	_emit_room_started = emit_room_started
	_event_continuation.clear()
	_connect_runner()


func begin_current_room() -> Variant:
	if _facade == null or _catalog == null or _runner == null:
		return _failure_result(&"RUNTIME_NOT_CONFIGURED", {"operation": "begin_current_room"})
	if _room_active:
		return _failure_result(&"INVALID_PHASE", {"operation": "begin_current_room"})
	var room_value: Variant = _facade.call("current_room_definition")
	if not room_value is Dictionary or (room_value as Dictionary).is_empty():
		return _failure_result(&"ROOM_NOT_AVAILABLE", {"operation": "begin_current_room"})
	var next_room := (room_value as Dictionary).duplicate(true)
	var next_room_id := _room_id(next_room)
	if _room_terminal:
		if not _failure.is_empty() or next_room_id == _current_room_id:
			return _failure_result(&"TERMINAL_STATE", {"operation": "begin_current_room"})
		_room_terminal = false
		_current_room.clear()
		_current_room_id = &""
	_current_room = next_room
	_current_room_id = next_room_id
	var entered: Variant = _facade.call("enter_current_room")
	if not _result_ok(entered):
		_current_room.clear()
		_current_room_id = &""
		return entered
	_room_active = true
	_room_terminal = false
	_event_continuation.clear()
	if _emit_room_started:
		room_started.emit(_current_room_id, _result_revision(entered))

	var room_type := str(_current_room.get("type", "combat"))
	var launch_mode := str(_current_room.get("runtime_mode", "")) == "launch"
	if room_type == "event" and not launch_mode:
		_complete_current_room()
		return entered
	if launch_mode and room_type == "event":
		if (
			not _facade.has_method("open_current_event")
			or not _facade.has_method("event_view_state")
		):
			_fail_runtime(&"EVENT_RUNTIME_UNAVAILABLE", {"room_id": str(_current_room_id)})
			return _failure_result(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED")
		var opened: Variant = _facade.call("open_current_event", {
			"room_id": str(_current_room_id),
			"run_seed": _run_seed,
		})
		if not _result_ok(opened):
			_fail_runtime(&"EVENT_RUNTIME_UNAVAILABLE", {
				"room_id": str(_current_room_id),
				"code": str(opened.get("code")) if opened != null else "INVALID_RESULT",
			})
			return opened
		if not sync_event_result(opened):
			_fail_runtime(&"EVENT_RUNTIME_CONFIGURATION_FAILED", {
				"room_id": str(_current_room_id),
			})
			return _failure_result(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED")
		return opened
	if launch_mode and room_type == "shop":
		if not _facade.has_method("open_current_merchant"):
			_fail_runtime(&"MERCHANT_RUNTIME_UNAVAILABLE", {"room_id": str(_current_room_id)})
			return _failure_result(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED")
		var opened: Variant = _facade.call("open_current_merchant")
		if not _result_ok(opened):
			_fail_runtime(&"MERCHANT_RUNTIME_UNAVAILABLE", {
				"room_id": str(_current_room_id),
				"code": str(opened.get("code")) if opened != null else "INVALID_RESULT",
			})
			return opened
		return opened
	if launch_mode and room_type not in ["combat", "elite", "boss"]:
		return entered

	var encounter_id := str(_current_room.get("encounter_id", ""))
	var room_number := int(_current_room.get("room_number", 0))
	var encounter_value: Variant = (
		_facade.call("current_encounter_definition")
		if launch_mode and _facade.has_method("current_encounter_definition")
		else _catalog.call(
			"encounter_definition",
			encounter_id,
			_run_seed,
			room_number
		)
	)
	if not encounter_value is Dictionary or (encounter_value as Dictionary).is_empty():
		_fail_runtime(&"ENCOUNTER_NOT_AVAILABLE", {
			"room_id": str(_current_room_id),
			"encounter_id": encounter_id,
		})
		return _failure_result(&"CONTENT_NOT_AVAILABLE", {"encounter_id": encounter_id})
	_runner.call("start_encounter", (encounter_value as Dictionary).duplicate(true), _run_seed, room_number)
	return entered


func complete_current_room() -> Variant:
	return _complete_current_room()


func synchronize_completed_interaction() -> Variant:
	if not _room_active or _room_terminal or _facade == null:
		return _failure_result(&"TERMINAL_STATE", {"operation": "synchronize_completed_interaction"})
	var state: Dictionary = _facade.call("snapshot")
	var plan := state.get("floor_plan", {}) as Dictionary
	if (
		str(_current_room.get("runtime_mode", "")) != "launch"
		or str(_current_room.get("room_type", "")) not in ["treasure", "rest"]
		or int(state.get("phase", -1)) not in [
			RunPhaseScript.Value.ROOM_RESOLVING, RunPhaseScript.Value.SELECTION_ACTIVE,
		]
		or str(plan.get("current_node_id", "")) != str(_current_room_id)
	):
		return _failure_result(&"INVALID_PHASE", {"operation": "synchronize_completed_interaction"})
	var current_node: Dictionary = {}
	for node: Dictionary in plan.get("nodes", []):
		if str(node.get("id", "")) == str(_current_room_id):
			current_node = node
			break
	if current_node.is_empty() or not bool(current_node.get("cleared", false)):
		return _failure_result(&"INVALID_PHASE", {"operation": "synchronize_completed_interaction"})
	_room_terminal = true
	_room_active = false
	_cancel_runner()
	var revision := _current_revision()
	room_cleared.emit(_current_room_id, revision)
	return CommandResultScript.success(revision, {"room_completed": true})


func event_view_state() -> Dictionary:
	if not _is_active_launch_event() or not _facade.has_method("event_view_state"):
		return {}
	var value: Variant = _facade.call("event_view_state")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func choose_current_event_option(
	option_id: StringName,
	expected_revision: int = -1
) -> Variant:
	if not _is_active_launch_event() or not _facade.has_method("choose_current_event_option"):
		return _failure_result(&"INVALID_PHASE", {"operation": "choose_current_event_option"})
	var revision := _resolved_expected_revision(expected_revision)
	var result: Variant = _facade.call("choose_current_event_option", option_id, revision)
	if _result_ok(result) and not sync_event_result(result):
		return _event_sync_failure("choose_current_event_option")
	return result


func complete_current_event_reward(
	continuation_id: String,
	result: Dictionary,
	expected_revision: int = -1
) -> Variant:
	if not _is_active_launch_event() or not _facade.has_method("complete_current_event_reward"):
		return _failure_result(&"INVALID_PHASE", {"operation": "complete_current_event_reward"})
	if (
		str(_event_continuation.get("kind", "")) != "reward"
		or continuation_id.is_empty()
		or continuation_id != str(_event_continuation.get("continuation_id", ""))
	):
		return _failure_result(&"INVALID_ARGUMENT", {
			"operation": "complete_current_event_reward",
			"reason": "continuation_mismatch",
		})
	var revision := _resolved_expected_revision(expected_revision)
	var completed: Variant = _facade.call(
		"complete_current_event_reward",
		continuation_id,
		result.duplicate(true),
		revision
	)
	if _result_ok(completed) and not sync_event_result(completed):
		return _event_sync_failure("complete_current_event_reward")
	return completed


func dismiss_current_event(expected_revision: int = -1) -> Variant:
	if not _is_active_launch_event() or not _facade.has_method("dismiss_current_event"):
		return _failure_result(&"INVALID_PHASE", {"operation": "dismiss_current_event"})
	var revision := _resolved_expected_revision(expected_revision)
	var dismissed: Variant = _facade.call("dismiss_current_event", revision)
	if _result_ok(dismissed) and not sync_event_result(dismissed):
		return _event_sync_failure("dismiss_current_event")
	return dismissed


func sync_event_result(result: Variant) -> bool:
	if not _is_active_launch_event() or not _result_ok(result):
		return false
	var context := _result_context(result)
	var view_value: Variant = context.get("view_state", {})
	if not view_value is Dictionary or (view_value as Dictionary).is_empty():
		return false
	var view := view_value as Dictionary
	var phase := str(view.get("phase", ""))
	var pending_kind := str(view.get("pending_kind", ""))
	var continuation_value: Variant = context.get("continuation", {})
	if phase in ["pending_reward", "pending_encounter"]:
		if not continuation_value is Dictionary:
			return false
		var continuation := continuation_value as Dictionary
		var kind := str(continuation.get("kind", ""))
		var continuation_id := str(continuation.get("continuation_id", ""))
		var expected_kind := "reward" if phase == "pending_reward" else "encounter"
		if kind != expected_kind or pending_kind != expected_kind or continuation_id.is_empty():
			return false
		if kind == "reward":
			if (
				str(continuation.get("pool_id", "")).is_empty()
				or int(continuation.get("count", 0)) < 1
			):
				return false
			if _runner != null and bool(_runner.call("is_active")):
				return false
		else:
			var encounter_id := str(continuation.get("encounter_id", ""))
			if encounter_id.is_empty():
				return false
			if not _start_event_encounter(encounter_id, continuation_id):
				return false
		_event_continuation = continuation.duplicate(true)
		return true
	if not pending_kind.is_empty() or (continuation_value is Dictionary and not (continuation_value as Dictionary).is_empty()):
		return false
	_event_continuation.clear()
	if _runner != null and bool(_runner.call("is_active")):
		_cancel_runner()
	return phase in ["open", "resolved", "dismissed"]


func leave_current_shop() -> Variant:
	if (
		not _room_active
		or _room_terminal
		or str(_current_room.get("runtime_mode", "")) != "launch"
		or str(_current_room.get("room_type", "")) != "shop"
	):
		return _failure_result(&"INVALID_PHASE", {"operation": "leave_current_shop"})
	return _complete_current_room()


func register_spawned(entity: Node, spawn_definition: Dictionary = {}) -> bool:
	if not _can_delegate_spawn():
		return false
	return bool(_runner.call("register_spawned", entity, spawn_definition.duplicate(true)))


func reject_spawn(spawn_definition: Dictionary, reason: StringName) -> bool:
	if not _can_delegate_spawn():
		return false
	return bool(_runner.call("reject_spawn", spawn_definition.duplicate(true), reason))


func report_player_died(killer: Variant = null) -> Variant:
	if _facade == null:
		return _failure_result(&"RUNTIME_NOT_CONFIGURED", {"operation": "report_player_died"})
	if _room_terminal:
		return _failure_result(&"TERMINAL_STATE", {"operation": "report_player_died"})
	var context := {
		"result": "death",
		"room_id": str(_current_room_id),
		"current_room": int(_current_room.get("room_number", 0)),
		"killer": killer,
	}
	var result: Variant = _facade.call("player_died", context)
	if not _result_ok(result):
		return result
	_room_terminal = true
	_room_active = false
	_cancel_runner()
	terminal_committed.emit(context.duplicate(true), _result_revision(result))
	return result


func report_entity_died(entity: Node) -> bool:
	if not _can_delegate_spawn() or entity == null or not is_instance_valid(entity):
		return false
	return bool(_runner.call("notify_entity_defeated", entity))


func snapshot() -> Dictionary:
	return {
		"configured": _facade != null and _catalog != null and _runner != null,
		"room_active": _room_active,
		"room_terminal": _room_terminal,
		"room_id": str(_current_room_id),
		"room_definition": _current_room.duplicate(true),
		"run_seed": _run_seed,
		"event_continuation": _event_continuation.duplicate(true),
		"failure": _failure.duplicate(true),
		"runner": _runner.call("snapshot") if _runner != null and _runner.has_method("snapshot") else {},
	}


func _connect_runner() -> void:
	if _runner == null:
		return
	if _runner.has_signal("spawn_warning_requested") and not _runner.spawn_warning_requested.is_connected(_on_spawn_warning_requested):
		_runner.spawn_warning_requested.connect(_on_spawn_warning_requested)
	if _runner.has_signal("spawn_requested") and not _runner.spawn_requested.is_connected(_on_spawn_requested):
		_runner.spawn_requested.connect(_on_spawn_requested)
	if _runner.has_signal("encounter_completed") and not _runner.encounter_completed.is_connected(_on_encounter_completed):
		_runner.encounter_completed.connect(_on_encounter_completed)
	if _runner.has_signal("encounter_failed") and not _runner.encounter_failed.is_connected(_on_encounter_failed):
		_runner.encounter_failed.connect(_on_encounter_failed)


func _disconnect_runner() -> void:
	if _runner == null or not is_instance_valid(_runner):
		return
	if _runner.has_signal("spawn_warning_requested") and _runner.spawn_warning_requested.is_connected(_on_spawn_warning_requested):
		_runner.spawn_warning_requested.disconnect(_on_spawn_warning_requested)
	if _runner.has_signal("spawn_requested") and _runner.spawn_requested.is_connected(_on_spawn_requested):
		_runner.spawn_requested.disconnect(_on_spawn_requested)
	if _runner.has_signal("encounter_completed") and _runner.encounter_completed.is_connected(_on_encounter_completed):
		_runner.encounter_completed.disconnect(_on_encounter_completed)
	if _runner.has_signal("encounter_failed") and _runner.encounter_failed.is_connected(_on_encounter_failed):
		_runner.encounter_failed.disconnect(_on_encounter_failed)


func _on_spawn_warning_requested(spawn_definition: Dictionary, duration: float) -> void:
	if _room_active and not _room_terminal:
		spawn_warning_requested.emit(spawn_definition.duplicate(true), duration)


func _on_spawn_requested(spawn_definition: Dictionary) -> void:
	if _room_active and not _room_terminal:
		spawn_requested.emit(spawn_definition.duplicate(true))


func _on_encounter_completed(encounter_id: StringName) -> void:
	if not _room_active or _room_terminal:
		return
	if _is_active_launch_event():
		if (
			str(_event_continuation.get("kind", "")) != "encounter"
			or str(encounter_id) != str(_event_continuation.get("encounter_id", ""))
		):
			return
		_complete_event_encounter(true, {
			"encounter_id": str(encounter_id),
			"result": "victory",
		})
		return
	var expected := str(_current_room.get("encounter_id", ""))
	if not expected.is_empty() and str(encounter_id) != expected:
		return
	_complete_current_room()


func _on_encounter_failed(encounter_id: StringName, reason: StringName, context: Dictionary) -> void:
	if not _room_active or _room_terminal:
		return
	if _is_active_launch_event():
		if (
			str(_event_continuation.get("kind", "")) != "encounter"
			or str(encounter_id) != str(_event_continuation.get("encounter_id", ""))
		):
			return
		var completion_context := context.duplicate(true)
		completion_context["encounter_id"] = str(encounter_id)
		completion_context["reason"] = str(reason)
		_complete_event_encounter(false, completion_context)
		return
	_fail_runtime(reason, {
		"room_id": str(_current_room_id),
		"encounter_id": str(encounter_id),
		"runner_context": context.duplicate(true),
	})


func _complete_current_room() -> Variant:
	if not _room_active or _room_terminal:
		return _failure_result(&"TERMINAL_STATE", {"operation": "complete_current_room"})
	if _is_active_launch_event():
		var view := event_view_state()
		if str(view.get("phase", "")) != "dismissed":
			return _failure_result(&"INVALID_PHASE", {
				"operation": "complete_current_room",
				"reason": "event_result_not_dismissed",
				"phase": str(view.get("phase", "")),
			})
	_room_terminal = true
	_room_active = false
	_cancel_runner()
	var room_type := str(_current_room.get("type", "combat"))
	var result: Variant
	var terminal_context: Dictionary = {}
	var launch_mode := str(_current_room.get("runtime_mode", "")) == "launch"
	if room_type == "boss" and not launch_mode:
		terminal_context = {
			"result": "victory",
			"room_id": str(_current_room_id),
			"current_room": int(_current_room.get("room_number", 0)),
		}
		result = _facade.call("boss_defeated", terminal_context)
	else:
		result = _facade.call("complete_current_room")
	if _result_ok(result):
		var revision := _result_revision(result)
		room_cleared.emit(_current_room_id, revision)
		var facade_snapshot: Dictionary = (
			_facade.call("snapshot") as Dictionary
			if _facade != null and _facade.has_method("snapshot")
			else {}
		)
		if launch_mode and RunPhaseScript.is_terminal(int(facade_snapshot.get("phase", -1))):
			terminal_context = (facade_snapshot.get("result", {}) as Dictionary).duplicate(true)
		if not terminal_context.is_empty():
			terminal_committed.emit(terminal_context.duplicate(true), revision)
	else:
		_failure = {
			"reason": "ROOM_COMMAND_REJECTED",
			"room_id": str(_current_room_id),
			"code": str(result.get("code")) if result != null else "INVALID_RESULT",
		}
		runtime_failed.emit(_failure.duplicate(true))
	return result


func _complete_event_encounter(success: bool, context: Dictionary) -> void:
	if not _facade.has_method("complete_current_event_encounter"):
		_fail_runtime(&"EVENT_RUNTIME_UNAVAILABLE", {"operation": "complete_event_encounter"})
		return
	var continuation_id := str(_event_continuation.get("continuation_id", ""))
	if continuation_id.is_empty():
		return
	var completed: Variant = _facade.call(
		"complete_current_event_encounter",
		continuation_id,
		success,
		context.duplicate(true),
		_current_revision()
	)
	if not _result_ok(completed):
		_fail_runtime(&"EVENT_CONTINUATION_FAILED", {
			"continuation_id": continuation_id,
			"code": str(completed.get("code")) if completed != null else "INVALID_RESULT",
		})
		return
	if not sync_event_result(completed):
		_fail_runtime(&"EVENT_RUNTIME_CONFIGURATION_FAILED", {
			"operation": "complete_event_encounter",
		})


func _fail_runtime(reason: StringName, context: Dictionary) -> void:
	if _room_terminal or not _failure.is_empty():
		return
	_room_terminal = true
	_room_active = false
	_cancel_runner()
	_failure = {
		"result": "runtime_error",
		"runtime_error_code": str(reason),
		"runtime_error_context": context.duplicate(true),
		"room_id": str(_current_room_id),
		"current_room": int(_current_room.get("room_number", 0)),
	}
	if _facade != null and _facade.has_method("player_died"):
		_facade.call("player_died", _failure.duplicate(true))
	runtime_failed.emit(_failure.duplicate(true))


func _can_delegate_spawn() -> bool:
	return (
		_room_active
		and not _room_terminal
		and _runner != null
		and is_instance_valid(_runner)
		and bool(_runner.call("is_active"))
	)


func _cancel_runner() -> void:
	if _runner != null and is_instance_valid(_runner) and _runner.has_method("cancel"):
		_runner.call("cancel")


func _start_event_encounter(encounter_id: String, continuation_id: String) -> bool:
	if _runner == null or _catalog == null:
		return false
	if bool(_runner.call("is_active")):
		return (
			str(_event_continuation.get("kind", "")) == "encounter"
			and str(_event_continuation.get("continuation_id", "")) == continuation_id
			and str(_event_continuation.get("encounter_id", "")) == encounter_id
		)
	var encounter_value: Variant = _catalog.call(
		"encounter_definition",
		encounter_id,
		_run_seed,
		int(_current_room.get("room_number", 0))
	)
	if not encounter_value is Dictionary or (encounter_value as Dictionary).is_empty():
		return false
	_runner.call(
		"start_encounter",
		(encounter_value as Dictionary).duplicate(true),
		_run_seed,
		int(_current_room.get("room_number", 0))
	)
	return true


func _is_active_launch_event() -> bool:
	return (
		_room_active
		and not _room_terminal
		and str(_current_room.get("runtime_mode", "")) == "launch"
		and str(_current_room.get("room_type", _current_room.get("type", ""))) == "event"
	)


func _resolved_expected_revision(expected_revision: int) -> int:
	return _current_revision() if expected_revision < 0 else expected_revision


func _event_sync_failure(operation: String) -> Variant:
	_fail_runtime(&"EVENT_RUNTIME_CONFIGURATION_FAILED", {"operation": operation})
	return _failure_result(&"AUTHORED_RUNTIME_CONFIGURATION_FAILED", {"operation": operation})


func _result_context(result: Variant) -> Dictionary:
	if result is Dictionary:
		var dictionary_value: Variant = (result as Dictionary).get("context", {})
		return (dictionary_value as Dictionary).duplicate(true) if dictionary_value is Dictionary else {}
	if result is Object:
		var object_value: Variant = (result as Object).get("context")
		return (object_value as Dictionary).duplicate(true) if object_value is Dictionary else {}
	return {}


func _room_id(room_definition: Dictionary) -> StringName:
	var explicit_id := str(room_definition.get("id", ""))
	if not explicit_id.is_empty():
		return StringName(explicit_id)
	return StringName("room_%02d" % int(room_definition.get("room_number", 0)))


func _failure_result(code: StringName, context: Dictionary = {}) -> Variant:
	return CommandResultScript.failure(code, _current_revision(), context)


func _current_revision() -> int:
	if _facade == null or not _facade.has_method("snapshot"):
		return 0
	var state_value: Variant = _facade.call("snapshot")
	if not state_value is Dictionary:
		return 0
	return int((state_value as Dictionary).get("revision", 0))


func _result_ok(result: Variant) -> bool:
	return result != null and bool(result.get("ok"))


func _result_revision(result: Variant) -> int:
	if result == null:
		return _current_revision()
	return int(result.get("new_revision"))
