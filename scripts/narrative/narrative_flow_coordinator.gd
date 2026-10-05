class_name NarrativeFlowCoordinator
extends Node

signal ending_selected(ending_id: String, receipt: Dictionary)
signal credits_completed(ending_id: String, receipt: Dictionary)
signal command_rejected(code: StringName)

const Registry := preload("res://scripts/content/content_registry.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Host := preload("res://scripts/application/run_runtime_host.gd")
const RoomHost := preload("res://scripts/dungeon/room_scene_host.gd")
const Player := preload("res://scripts/player/player_controller.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Predicates := preload("res://scripts/narrative/narrative_predicates.gd")
const Settlement := preload("res://scripts/progression/run_settlement_authority.gd")
const Model := preload("res://scripts/narrative/narrative_view_model.gd")
const PanelScript := preload("res://scripts/ui/narrative_panel_view.gd")
const Marker := preload("res://scripts/narrative/narrative_occurrence_marker.gd")

var _registry: RefCounted
var _service: RefCounted
var _host: Node
var _room_host: Node
var _player: CharacterBody2D
var _runtime_parent: Node2D
var _model := Model.new()
var _panel: Control
var _run: RefCounted
var _launch: Dictionary = {}
var _generation := 0
var _epoch := 0
var _sequence := 0
var _room_snapshot: Dictionary = {}
var _occurrences: Array = []
var _active_occurrence: Dictionary = {}
var _terminal := false
var _busy := false
var _recovery_pending := false
var _safety_owned := false
var _dismissed: Array = []
var _profile_id := ""
var _ending_handoff_id := ""
var _collision_mode_owned := false
var _original_disable_mode := CollisionObject2D.DISABLE_MODE_REMOVE
var _contact_retry_after_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.name = "NarrativeLayer"
	layer.layer = 44
	add_child(layer)
	_panel = PanelScript.new()
	_panel.name = "NarrativePanelView"
	layer.add_child(_panel)
	_panel.action_requested.connect(submit_action)
	_panel.close_requested.connect(func(_revision: int): close())


func configure(registry: RefCounted, service: RefCounted, host: Node, room_scene_host: Node, actual_player: Node, combat_runtime_parent: Node2D) -> Dictionary:
	if _service != null:
		return Candidate.success() if _registry == registry and _service == service and _host == host and _room_host == room_scene_host and _player == actual_player and _runtime_parent == combat_runtime_parent else Candidate.failure(&"ALREADY_CONFIGURED")
	if not is_node_ready() or not registry is Registry or not service is Service or not host is Host or not room_scene_host is RoomHost or not actual_player is Player or not is_instance_valid(combat_runtime_parent) or not combat_runtime_parent.is_inside_tree() or host.get("_player") != actual_player or host.content_registry() != registry:
		return Candidate.failure(&"NARRATIVE_FLOW_CONFIGURATION_INVALID")
	if not service.narrative_dialogue_view("phia").ok:
		return Candidate.failure(&"NARRATIVE_NOT_CONFIGURED")
	_registry = registry
	_service = service
	_host = host
	_room_host = room_scene_host
	_player = actual_player
	_runtime_parent = combat_runtime_parent
	_profile_id = str(service.get("_profile_id"))
	_room_host.room_transitioned.connect(_on_room_transitioned)
	return Candidate.success()


func panel() -> Control:
	return _panel


func bind_active_run() -> Dictionary:
	if _service == null or _busy or _recovery_pending:
		return Candidate.failure(&"NATIVE_PUBLICATION_PENDING" if _recovery_pending else &"NOT_CONFIGURED")
	retire_active_run()
	if not is_instance_valid(_host) or not is_instance_valid(_player) or _host.get("_player") != _player:
		return Candidate.failure(&"NARRATIVE_BINDING_INVALID")
	var run: RefCounted = _host.native_run_state()
	var bound: Dictionary = _service.bind_narrative_run(run, _player)
	if not bound.ok:
		return bound
	_run = run
	_launch = _service.snapshot().active_launch_receipt.duplicate(true)
	_generation = _player.owner_character_generation()
	_original_disable_mode = _player.disable_mode
	_player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	_collision_mode_owned = true
	return refresh_occurrences()


func retire_active_run() -> void:
	_epoch += 1
	close()
	_retire_occurrences()
	if _collision_mode_owned and _owns_player() and _player.disable_mode == CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE:
		_player.disable_mode = _original_disable_mode
	_collision_mode_owned = false
	_run = null
	_launch.clear()
	_generation = 0
	_terminal = false
	_recovery_pending = false
	_dismissed.clear()
	_ending_handoff_id = ""
	_contact_retry_after_ms = 0


func terminal_victory() -> Dictionary:
	if not _participants_current() or _run.phase != Phase.Value.VICTORY or _run.suspended or get_tree().paused:
		return Candidate.failure(&"NARRATIVE_TERMINAL_INVALID")
	var view: Dictionary = _service.narrative_ending_view()
	if not view.ok or not view.context.victory:
		return Candidate.failure(&"NARRATIVE_TERMINAL_INVALID")
	_terminal = true
	close()
	_retire_occurrences()
	var selected := _selected_ending(_service.snapshot())
	if not selected.is_empty() and _heart_collected():
		if _ending_handoff_id != selected:
			_ending_handoff_id = selected
			ending_selected.emit(selected, {"ending_id": selected, "recovered": true})
		return Candidate.success({"ending_id": selected, "recovered": true})
	if _heart_collected():
		return _show_endings()
	return _install("collect", "heart_fragment_5", {"source_receipt_id": "heart_fragment_5", "text_key": "SOURCE_HEART_FRAGMENT_5_TEXT", "source_kind": "heart_fragment"})


func open_dialogue(npc_id: String) -> Dictionary:
	if _service == null or _busy or _recovery_pending or get_tree().paused:
		return Candidate.failure(&"INVALID_PHASE")
	var definition := _definition("npc_" + npc_id)
	var result: Dictionary = _service.narrative_dialogue_view(npc_id)
	if not result.ok or definition.is_empty():
		return result if not result.ok else Candidate.failure(&"NPC_UNKNOWN")
	_active_occurrence.clear()
	return _render(_model.dialogue(_service.snapshot(), _view_run_id(), definition, result.context))


func show_selected_credits(ending_id: String) -> Dictionary:
	if _service == null or _busy or _recovery_pending or not _service.snapshot().active_launch_receipt.is_empty():
		return Candidate.failure(&"NARRATIVE_SETTLEMENT_PENDING")
	var profile: Dictionary = _service.snapshot()
	var selected := _selected_ending(profile)
	if selected != ending_id or not profile.narrative_state.endings.has(ending_id):
		return Candidate.failure(&"ENDING_NOT_SELECTED")
	var view: Dictionary = _service.narrative_ending_view()
	if not view.ok or not view.context.victory:
		return Candidate.failure(&"NARRATIVE_TERMINAL_INVALID")
	for ending: Dictionary in view.context.endings:
		if ending.ending_id == ending_id:
			return _render(_model.credits(profile, _view_run_id(), ending))
	return Candidate.failure(&"ENDING_UNKNOWN")


func resume_selected_credits() -> Dictionary:
	if _service == null:
		return Candidate.failure(&"NOT_CONFIGURED")
	var profile: Dictionary = _service.snapshot()
	var selected := _selected_ending(profile)
	if selected.is_empty() or profile.narrative_state.credits_completed.has(selected):
		return Candidate.success({"resumed": false})
	var result := show_selected_credits(selected)
	if result.ok:
		result.context.resumed = true
	return result


func close() -> void:
	if is_instance_valid(_panel) and _panel.visible and _panel.view_state().get("mode") == "choice" and not _active_occurrence.is_empty():
		_dismissed.append(str(_active_occurrence.definition.source_receipt_id))
	if is_instance_valid(_panel):
		_panel.close_panel()
	if _safety_owned and _participants_current():
		_host.set_dungeon_selection_safety(false)
	_safety_owned = false
	_active_occurrence.clear()


func process_pending_contact() -> Dictionary:
	if _busy or _recovery_pending:
		return Candidate.failure(&"NATIVE_PUBLICATION_PENDING" if _recovery_pending else &"BUSY")
	if not _participants_current() or get_tree().paused or _run.suspended or _panel.visible:
		return Candidate.success({"consumed": false})
	if _room_snapshot != _room_host.active_snapshot():
		return refresh_occurrences()
	for record: Dictionary in _occurrences:
		var token: Area2D = record.token.get_ref()
		if not is_instance_valid(token) or not token.overlaps_body(_player) or _player.global_position.distance_to(token.global_position) > Service.OCCURRENCE_RADIUS:
			continue
		_active_occurrence = record
		if record.kind == "choice":
			return _render(_model.choice(_service.snapshot(), _view_run_id(), record.definition))
		return _execute({"kind": "narrative_collect", "source_receipt_id": record.id}, int(_service.snapshot().revision), token)
	return Candidate.success({"consumed": false})


func submit_action(action_id: String, expected_revision: int) -> Dictionary:
	if _service == null or _busy or _recovery_pending or not _panel.visible or get_tree().paused:
		return Candidate.failure(&"INVALID_PHASE")
	var state: Dictionary = _panel.view_state()
	var selected: Dictionary = {}
	for row: Dictionary in state.rows:
		if row.action_id == action_id and row.available:
			selected = row
	if selected.is_empty() or expected_revision != state.revision:
		return _reject(Candidate.failure(&"NARRATIVE_ACTION_INVALID"))
	if expected_revision != _service.snapshot().revision:
		return _reject(Candidate.failure(&"STALE_REVISION"))
	match state.mode:
		"story":
			close()
			return _show_endings() if _terminal and _heart_collected() else refresh_occurrences()
		"dialogue":
			return _execute({"kind": "narrative_dialogue", "npc_id": state.subject_id, "node_id": selected.node_id, "choice_id": selected.choice_id}, expected_revision)
		"choice":
			if not _participants_current() or _active_occurrence.is_empty():
				return _reject(Candidate.failure(&"OCCURRENCE_INVALID"))
			var token: Area2D = _active_occurrence.token.get_ref()
			return _execute({"kind": "narrative_choice", "definition_id": state.subject_id, "choice_id": selected.choice_id}, expected_revision, token)
		"ending":
			if not _terminal or not _participants_current() or not _heart_collected():
				return _reject(Candidate.failure(&"NARRATIVE_TERMINAL_INVALID"))
			return _execute({"kind": "narrative_ending", "ending_id": selected.choice_id}, expected_revision)
		"credits":
			if not _service.snapshot().active_launch_receipt.is_empty() or _selected_ending(_service.snapshot()) != selected.choice_id:
				return _reject(Candidate.failure(&"NARRATIVE_SETTLEMENT_PENDING"))
			return _execute({"kind": "narrative_credits", "ending_id": selected.choice_id}, expected_revision)
	return _reject(Candidate.failure(&"NARRATIVE_ACTION_INVALID"))


func refresh_occurrences() -> Dictionary:
	_retire_occurrences()
	if not _participants_current() or _run.suspended or get_tree().paused or _terminal:
		return Candidate.success()
	var node: Dictionary = _run.current_floor_node()
	if node.is_empty() or not node.cleared or node.id == _run.floor_plan.entry_node_id or not is_instance_valid(_room_host.active_room()):
		return Candidate.success()
	var profile: Dictionary = _service.snapshot()
	var content: RefCounted = _service.get("_narrative_content")
	var rows: Array = _registry.get_catalog_entries(&"narrative_definition", &"LAUNCH") + _registry.get_catalog_entries(&"narrative_source_definition", &"LAUNCH")
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_heart: bool = a.get("source_kind") == "heart_fragment"
		var b_heart: bool = b.get("source_kind") == "heart_fragment"
		return a_heart and not b_heart)
	for definition: Dictionary in rows:
		var kind: String = str(definition.get("definition_kind", "source"))
		if kind == "hidden_line":
			var step_index: int = int(profile.narrative_state.hidden_steps.get(definition.storyline_id, 0)) + 1
			for step: Dictionary in definition.steps:
				if step.index == step_index and step.floor_id == _run.floor_plan.floor_id and Predicates.missing(definition.requirements + step.requirements, profile, content).is_empty():
					return _install("collect", str(step.source_receipt_id), step)
			continue
		if kind not in ["source", "artifact", "environment_record", "choice"] or definition.floor_id != _run.floor_plan.floor_id:
			continue
		var source_id: String = str(definition.source_receipt_id)
		var prefix := "choice:" if kind == "choice" else ("source:" if kind == "source" else "pickup:")
		if profile.narrative_state.consumed_sources.has(prefix + source_id) or _dismissed.has(source_id):
			continue
		if kind == "source" and definition.source_kind == "heart_fragment":
			if node.id != _run.floor_plan.boss_node_id or not _boss_source_current(definition.requirements[0].id):
				continue
		elif not Predicates.missing(definition.get("requirements", []), profile, content).is_empty():
			continue
		if kind == "choice":
			var completed: int = profile.narrative_state.vera_conversations if definition.choice_family == "vera" else profile.narrative_state.nemesis_choices.size()
			if definition.sequence != completed + 1:
				continue
		return _install("choice" if kind == "choice" else "collect", str(definition.id) if kind == "choice" else source_id, definition)
	return Candidate.success()


func recover_active_run() -> Dictionary:
	if _service == null or _busy or not _participants_current():
		return Candidate.failure(&"NARRATIVE_BINDING_INVALID")
	var epoch := _epoch
	var restored: Dictionary = _service.restore_narrative_run()
	if not restored.ok or epoch != _epoch or not _participants_current():
		return restored if not restored.ok else Candidate.failure(&"NARRATIVE_CONTEXT_CHANGED")
	_recovery_pending = false
	return terminal_victory() if _terminal else refresh_occurrences()


func _physics_process(delta: float) -> void:
	if _terminal and _participants_current() and not _recovery_pending and not _busy and not _panel.visible and not get_tree().paused and not _run.suspended and _run.phase == Phase.Value.VICTORY and not _heart_collected() and _room_snapshot == _room_host.active_snapshot() and not _occurrences.is_empty():
		var token: Area2D = _occurrences[0].token.get_ref()
		if is_instance_valid(token) and _player.health != null and not _player.health.dead:
			# Terminal traversal deliberately bypasses every Player action/time/replay clock.
			var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			_player.move_and_collide(direction * float(_player.stats.move_speed) * clampf(delta, 0.0, 0.05))
	if Time.get_ticks_msec() >= _contact_retry_after_ms:
		var result := process_pending_contact()
		if not result.ok:
			_contact_retry_after_ms = Time.get_ticks_msec() + 1000


func _install(kind: String, id: String, definition: Dictionary) -> Dictionary:
	var room: Node2D = _room_host.active_room()
	if not is_instance_valid(room):
		return Candidate.failure(&"OCCURRENCE_INVALID")
	var template: Dictionary = {}
	for row: Dictionary in _registry.get_catalog_entries(&"room_template", &"LAUNCH"):
		if row.id == _run.current_floor_node().template_id:
			template = row
	var installed: Dictionary = _service.install_narrative_occurrence(kind, id, room, template, "room_exit", _runtime_parent)
	if not installed.ok:
		return installed
	var token: Area2D = installed.context.occurrence
	token.process_mode = Node.PROCESS_MODE_PAUSABLE
	var marker := Marker.new()
	token.add_child(marker)
	marker.configure(definition.get("source_kind") == "heart_fragment")
	_occurrences.append({"token": weakref(token), "kind": kind, "id": id, "definition": definition.duplicate(true)})
	_room_snapshot = _room_host.active_snapshot().duplicate(true)
	return Candidate.success({"installed": true})


func _execute(fields: Dictionary, revision: int, token: Area2D = null) -> Dictionary:
	var command := fields.duplicate(true)
	_sequence += 1
	command.command_id = "native-story:%s:%d:%d" % [_profile_id, revision, _sequence]
	var epoch := _epoch
	var room_stamp: Dictionary = _room_host.active_snapshot().duplicate(true)
	var needs_native: bool = command.kind in ["narrative_collect", "narrative_choice", "narrative_ending"]
	_busy = true
	var result: Dictionary = _service.execute_narrative(command, revision, token)
	_busy = false
	if result.code == &"NATIVE_PUBLICATION_PENDING":
		_recovery_pending = true
		return _reject(result)
	if not result.ok:
		return _reject(result)
	if epoch != _epoch or needs_native and (not _participants_current() or _room_host.active_snapshot() != room_stamp):
		return _reject(Candidate.failure(&"NARRATIVE_CONTEXT_CHANGED"))
	if result.context.get("deferred", false):
		if not _active_occurrence.is_empty():
			_dismissed.append(str(_active_occurrence.definition.source_receipt_id))
		close()
		refresh_occurrences()
		return result
	match command.kind:
		"narrative_dialogue": open_dialogue(str(command.npc_id))
		"narrative_collect", "narrative_choice":
			_retire_occurrences()
			_render(_model.story(_service.snapshot(), _view_run_id(), str(result.context.source_id), str(result.context.get("text_key", _active_occurrence.get("definition", {}).get("description_key", "UI_NARRATIVE_COLLECTED"))), _terminal))
		"narrative_ending":
			close()
			_retire_occurrences()
			_ending_handoff_id = str(command.ending_id)
			ending_selected.emit(str(command.ending_id), result.context.duplicate(true))
		"narrative_credits":
			close()
			credits_completed.emit(str(command.ending_id), result.context.duplicate(true))
	return result


func _show_endings() -> Dictionary:
	if not _selected_ending(_service.snapshot()).is_empty():
		return terminal_victory()
	var view: Dictionary = _service.narrative_ending_view()
	return _render(_model.endings(_service.snapshot(), _view_run_id(), view.context)) if view.ok and view.context.victory else Candidate.failure(&"NARRATIVE_TERMINAL_INVALID")


func _render(projected: Dictionary) -> Dictionary:
	if not projected.ok:
		return projected
	if _participants_current() and not _host.get("_selection_safety_active"):
		_host.set_dungeon_selection_safety(true)
		_safety_owned = true
	var rendered = _panel.render(projected.context.view_state)
	return Candidate.success() if rendered.ok else Candidate.failure(rendered.code)


func _reject(result: Dictionary) -> Dictionary:
	if is_instance_valid(_panel) and _panel.visible:
		if result.code == &"STALE_REVISION":
			var state: Dictionary = _panel.view_state()
			match state.mode:
				"dialogue": open_dialogue(str(state.subject_id))
				"story": _render(_model.story(_service.snapshot(), _view_run_id(), str(state.subject_id), str(state.text_key), _terminal))
				"ending": _show_endings()
				"credits": show_selected_credits(str(state.subject_id))
				"choice":
					if _participants_current() and not _active_occurrence.is_empty():
						_render(_model.choice(_service.snapshot(), _view_run_id(), _active_occurrence.definition))
		_panel.show_rejection("UI_NARRATIVE_SAVE_RETRY")
	command_rejected.emit(result.code)
	return result


func _retire_occurrences() -> void:
	if _service != null and _service.get("_narrative_run") == _run:
		_service.retire_narrative_occurrences()
	_occurrences.clear()
	_room_snapshot.clear()


func _participants_current() -> bool:
	if _service == null or _run == null or _launch.is_empty() or not is_instance_valid(_host) or not is_instance_valid(_player) or not is_instance_valid(_room_host) or not is_instance_valid(_runtime_parent):
		return false
	return _host.native_run_state() == _run and _host.get("_player") == _player and _host.content_registry() == _registry and _player.is_inside_tree() and _player.current_run_id() == StringName(_launch.run_id) and _player.owner_character_generation() == _generation and _service.snapshot().active_launch_receipt == _launch and _service.get("_narrative_run") == _run and _service.get("_narrative_player").get_ref() == _player


func _owns_player() -> bool:
	return _run != null and not _launch.is_empty() and is_instance_valid(_host) and is_instance_valid(_player) and _host.native_run_state() == _run and _host.get("_player") == _player and _player.current_run_id() == StringName(_launch.run_id) and _player.owner_character_generation() == _generation


func _heart_collected() -> bool:
	var state: Dictionary = _service.snapshot().narrative_state
	return state.heart_fragments.has("floor_throne_of_void") and state.consumed_sources.has("source:heart_fragment_5")


func _boss_source_current(boss_id: String) -> bool:
	for event: Dictionary in _run.events:
		if event.get("type") == Settlement.SOURCE_TYPE and event.get("receipt", {}).get("payload", {}).get("boss_id") == boss_id:
			return true
	return false


func _definition(id: String) -> Dictionary:
	for definition: Dictionary in _registry.get_catalog_entries(&"narrative_definition", &"LAUNCH"):
		if definition.id == id:
			return definition
	return {}


func _selected_ending(profile: Dictionary) -> String:
	var receipt: Dictionary = profile.active_launch_receipt if not profile.active_launch_receipt.is_empty() else profile.last_settlement_receipt
	if receipt.is_empty():
		return ""
	var prefix := "ending-choice:%d:" % int(receipt.sequence)
	for source: String in profile.narrative_state.consumed_sources:
		if source.begins_with(prefix):
			return source.substr(prefix.length())
	return ""


func _view_run_id() -> String:
	return str(_launch.run_id) if not _launch.is_empty() else _profile_id


func _on_room_transitioned(_receipt: Dictionary) -> void:
	if _busy:
		_epoch += 1
		return
	close()
	_dismissed.clear()
	refresh_occurrences()


func _exit_tree() -> void:
	retire_active_run()
