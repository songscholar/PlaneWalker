extends Node2D

signal state_changed
signal closed
signal save_rejected(code: StringName)

const Endless := preload("res://scripts/modes/endless_session.gd")
const Profile := preload("res://scripts/modes/endless_profile_service.gd")
const Host := preload("res://scripts/modes/endless_runtime_host.gd")
const Controller := preload("res://scenes/rooms/combat_room_01.tscn")
const SceneHost := preload("res://scripts/dungeon/room_scene_host.gd")
const DungeonFlow := preload("res://scripts/application/dungeon_flow_coordinator.gd")
const FloorEffects := preload("res://scripts/dungeon/floor_rule_effect_authority.gd")
const Presentation := preload("res://scripts/dungeon/native_room_presentation.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const Request := preload("res://scripts/modes/boss_rush_catalog.gd")
const Backdrop := preload("res://scripts/modes/native_mode_arena_backdrop.gd")

var _registry: RefCounted
var _source: RefCounted
var _service: RefCounted
var _save: RefCounted
var _catalog: RefCounted
var _owner := ""
var _save_id := ""
var _root := ""
var _fingerprint := ""
var _initial: Dictionary = {}
var _state: Dictionary = {}
var _stage: Node2D
var _host: Node
var _controller: Node2D
var _scenes: Node
var _dungeon: Node
var _presentation: Node
var _backdrop: CanvasLayer
var _paused := false
var _busy := false
var _active := false
var _pending := ""
var _save_error: StringName = &""
var _process_modes: Array[Dictionary] = []
var _checkpoint_stamp := ""
var _frame_checkpoint := 0


func configure(registry: RefCounted, service: RefCounted, root_path: String) -> Dictionary:
	if _registry != null or not is_inside_tree() or not registry is Registry or not service is Service:
		return _failure(&"ENDLESS_CONFIGURATION_INVALID")
	var identity: Dictionary = service.local_record_storage_identity()
	var loaded: Dictionary = Factory.from_registry(registry)
	if identity.is_empty() or not loaded.ok or not Rules.same(identity.content_snapshot, Content.snapshot(registry)):
		return _failure(&"ENDLESS_CONTENT_INVALID")
	_registry = registry
	_source = service
	_owner = str(identity.profile_id)
	_catalog = loaded.context.catalog
	_fingerprint = Endless.fingerprint(identity.content_snapshot)
	_save_id = "endless_" + Rules.canonical({"profile": _owner, "domain": identity.save_domain, "fingerprint": _fingerprint}).sha256_text().substr(0, 24)
	_root = root_path
	_initial = service.snapshot()
	_initial.revision = 0
	_initial.launch_sequence = 0
	_initial.active_launch_receipt = {}
	_initial.last_settlement_receipt = {}
	_save = Save.new()
	var configured = _save.configure(_root, "0.4.0-dev", identity.content_snapshot)
	if not configured.ok:
		return _failure(configured.code)
	return _reload_service()


func _reload_service() -> Dictionary:
	var service := Profile.new()
	var configured: Dictionary = service.configure_mode(_catalog, _save, _save_id, _owner, _initial, _fingerprint)
	if not configured.ok:
		return configured
	_service = service
	_state = service.mode_session.duplicate(true)
	_pending = ""
	_save_error = &""
	return _success()


func start(request: Dictionary) -> Dictionary:
	if _registry == null or _busy or _active or not _pending.is_empty() or not Request.valid_request(request) or not _source.snapshot().active_launch_receipt.is_empty() or not _source.snapshot().unlocked_characters.has(request.character_id) or not _source.snapshot().unlocked_weapons.has(request.weapon_id):
		return _failure(&"ENDLESS_LAUNCH_INVALID")
	_busy = true
	var candidate := Endless.empty(_fingerprint)
	candidate.sequence = int(_state.sequence) + 1
	candidate.run_id = "endless-%s-%d" % [_owner, candidate.sequence]
	candidate.request = request.duplicate(true)
	candidate.status = "STARTING"
	_service.mode_session = candidate
	var retired: Dictionary = _service.retire_cycle()
	_busy = false
	if not retired.ok:
		return _reject("start", retired.code)
	_state = candidate
	return _launch_cycle()


func _launch_cycle() -> Dictionary:
	_busy = true
	if _state.status == "STARTING" and not _service.payload().get("active_run_state", {}).is_empty() and _service.payload().get("native_run_checkpoint", {}).is_empty():
		# Only the initial domain was retained; no accepted gameplay checkpoint exists.
		_service.mode_session = _state.duplicate(true)
		var retired: Dictionary = _service.retire_cycle()
		if not retired.ok:
			_busy = false
			return _reject("launch", retired.code)
	if not _create_stage():
		_busy = false
		return _reject("launch", &"ENDLESS_NATIVE_INVALID")
	var request: Dictionary = _state.request
	var config := {"schema_version": 1, "milestone": "LAUNCH", "character_id": request.character_id, "weapon_id": request.weapon_id, "enabled_time_skills": request.time_abilities, "difficulty": "normal", "seed": Endless.cycle_seed(int(request.seed), int(_state.cycle_index)), "accessibility_assists": request.accessibility_assists}
	var started: Variant
	if _service.snapshot().active_launch_receipt.is_empty():
		started = _host.start_profile_run(config, _service, int(_service.snapshot().revision))
	else:
		started = _host.retry_profile_startup(_service, int(_service.snapshot().revision))
	if not started.ok:
		_busy = false
		return _reject("launch", started.code)
	if not _host.install_carry(str(_state.carry_build_codec), str(_state.carry_player_codec)):
		_busy = false
		return _reject("launch", &"ENDLESS_CARRY_INVALID")
	if CombatFeedback.ensure_actor_presentation(current_player()) == null:
		_busy = false
		return _reject("launch", &"ENDLESS_NATIVE_INVALID")
	_state.status = "ACTIVE"
	_service.mode_session = _state.duplicate(true)
	_active = true
	_busy = false
	var retained := _checkpoint("checkpoint")
	if retained.ok:
		_presentation.synchronize_active_room()
		_dungeon.refresh(true)
	return retained


func continue_session() -> Dictionary:
	if _active or _busy or not _pending.is_empty() or _state.status not in ["STARTING", "ACTIVE", "CYCLE_CLEAR"] or not _source.snapshot().active_launch_receipt.is_empty():
		return _failure(&"ENDLESS_CONTINUE_INVALID")
	_state.continued = true
	_service.mode_session = _state.duplicate(true)
	if _state.status == "CYCLE_CLEAR":
		return next_cycle()
	if _service.payload().get("native_run_checkpoint", {}).is_empty():
		return _launch_cycle()
	_busy = true
	if not _create_stage():
		_busy = false
		return _reject("continue", &"ENDLESS_NATIVE_INVALID")
	var restored = _host.restore_profile_checkpoint(_service, int(_service.snapshot().revision))
	_busy = false
	if not restored.ok:
		return _reject("continue", restored.code)
	if CombatFeedback.ensure_actor_presentation(current_player()) == null:
		return _reject("continue", &"ENDLESS_NATIVE_INVALID")
	_active = true
	var retained := _checkpoint("checkpoint")
	if retained.ok:
		_presentation.synchronize_active_room(true)
		_dungeon.refresh(true)
	return retained


func next_cycle() -> Dictionary:
	if _busy or not _pending.is_empty() or _state.status != "CYCLE_CLEAR" or _state.cycle_index >= 2147483647:
		return _failure(&"ENDLESS_CYCLE_INVALID")
	_busy = true
	var candidate := _state.duplicate(true)
	candidate.cycle_index += 1
	candidate.cycle_frames = 0
	candidate.status = "STARTING"
	_service.mode_session = candidate
	var retired: Dictionary = _service.retire_cycle()
	_busy = false
	if not retired.ok:
		return _reject("next", retired.code)
	_state = candidate
	return _launch_cycle()


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func current_player() -> Node2D:
	return _controller.get_node("Player") if is_instance_valid(_controller) else null


func runtime_host() -> Node:
	return _host if is_instance_valid(_host) else null


func dungeon_flow() -> Node:
	return _dungeon if is_instance_valid(_dungeon) else null


func is_active() -> bool:
	return _active


func is_paused() -> bool:
	return _paused


func has_pending_save() -> bool:
	return not _pending.is_empty()


func save_error() -> StringName:
	return _save_error


func set_fault_injector(injector: Callable) -> void:
	if _save != null:
		_save.set_fault_injector(injector)


func checkpoint() -> Dictionary:
	return _checkpoint("checkpoint") if _active and not _busy and _pending.is_empty() else _failure(&"ENDLESS_CHECKPOINT_INVALID")


func save_and_return() -> Dictionary:
	if not _active or _busy or not _pending.is_empty():
		return _failure(&"ENDLESS_CHECKPOINT_INVALID")
	return _checkpoint("close")


func retry_save() -> Dictionary:
	if _busy or _pending.is_empty():
		return _failure(&"ENDLESS_RETRY_INVALID")
	var action := _pending
	_pending = ""
	_save_error = &""
	if action == "start":
		var candidate: Dictionary = _service.mode_session.duplicate(true)
		var saved: Dictionary = _service.retire_cycle()
		if not saved.ok:
			return _reject(action, saved.code)
		_state = candidate
		return _launch_cycle()
	if action == "next":
		var candidate: Dictionary = _service.mode_session.duplicate(true)
		var saved: Dictionary = _service.retire_cycle()
		if not saved.ok:
			return _reject(action, saved.code)
		_state = candidate
		return _launch_cycle()
	if action == "launch":
		_clear_stage()
		return _launch_cycle()
	if action == "continue":
		_clear_stage()
		return continue_session()
	return _checkpoint(action)


func reload_saved_session() -> Dictionary:
	if _busy:
		return _failure(&"ENDLESS_RETRY_INVALID")
	var previous: RefCounted = _service
	var result := _reload_service()
	if not result.ok:
		_service = previous
		return result
	close()
	state_changed.emit()
	return result


func set_paused(value: bool) -> void:
	if _active and _state.status == "ACTIVE" and _pending.is_empty():
		_suspend(value)


func close() -> void:
	_clear_stage()
	_active = false


func _create_stage() -> bool:
	_clear_stage()
	_stage = Node2D.new()
	_stage.name = "EndlessDungeon"
	add_child(_stage)
	_backdrop = Backdrop.new()
	_stage.add_child(_backdrop)
	if not _backdrop.configure("floor_ruins_of_remnant"):
		return false
	_scenes = SceneHost.new()
	_scenes.name = "LaunchRoomSceneHost"
	_stage.add_child(_scenes)
	_scenes.room_transitioned.connect(_on_arena_room_transitioned)
	_controller = Controller.instantiate()
	_controller.name = "CombatRoom01"
	_controller.auto_start = false
	_stage.add_child(_controller)
	_host = Host.new()
	_host.name = "RunRuntimeHost"
	_host.room_controller_path = NodePath("../CombatRoom01")
	_host.cycle_index = int(_state.cycle_index)
	for pack: Dictionary in _registry.active_packs():
		_host.content_pack_specs.append({"path": str(pack.root_path).path_join("pack.json"), "required": true})
	_stage.add_child(_host)
	if not Rules.same(Content.snapshot(_host.content_registry()), Content.snapshot(_registry)):
		return false
	var authority := FloorEffects.new()
	if not authority.configure(current_player(), _scenes) or not _host.configure_route_scene_adapter(_scenes) or not _host.configure_floor_rule_effect_authority(authority):
		return false
	_presentation = Presentation.new()
	_stage.add_child(_presentation)
	if not _presentation.configure(_host, _scenes, _controller):
		return false
	_presentation.set_launch_mode(true)
	_dungeon = DungeonFlow.new()
	_dungeon.runtime_host_path = NodePath("../RunRuntimeHost")
	_stage.add_child(_dungeon)
	current_player().authoritative_frame_committed.connect(_on_frame)
	_checkpoint_stamp = ""
	_frame_checkpoint = int(_state.elapsed_frames)
	return true


func _on_arena_room_transitioned(_receipt: Dictionary) -> void:
	var room: Node2D = _scenes.active_room()
	if is_instance_valid(room):
		_backdrop.configure(str(room.binding_snapshot().binding.floor_id))


func _on_frame(_frame: int) -> void:
	if _active and not _paused and not _busy and _pending.is_empty() and _state.status == "ACTIVE":
		_state.elapsed_frames = mini(2147483647, int(_state.elapsed_frames) + 1)
		_state.cycle_frames = mini(2147483647, int(_state.cycle_frames) + 1)


func _process(_delta: float) -> void:
	if not _active or _paused or _busy or not _pending.is_empty() or _state.status != "ACTIVE" or not is_instance_valid(_host):
		return
	var run: Dictionary = _host.runtime_snapshot()
	if Phase.is_terminal(int(run.phase)):
		_finish_cycle(run)
		return
	var stamp := "%d:%s:%d" % [int(run.current_floor_index), str(run.floor_plan.current_node_id), int(run.phase)]
	if stamp != _checkpoint_stamp or int(_state.elapsed_frames) - _frame_checkpoint >= 600:
		var captured: Dictionary = preload("res://scripts/save/native_run_checkpoint_authority.gd").capture(_host)
		if captured.ok:
			_checkpoint("checkpoint")
			_checkpoint_stamp = stamp


func _finish_cycle(run: Dictionary) -> void:
	var player := current_player()
	if player == null:
		return
	if int(run.phase) == Phase.Value.VICTORY:
		if run.completed_floor_ids != preload("res://scripts/save/save_envelope.gd").FLOOR_IDS or player.health.dead:
			_reject("checkpoint", &"ENDLESS_TERMINAL_INVALID")
			return
		var build := Replay.encode_replay_json(_host.native_run_state().reward_replay_build_snapshot())
		var carry := Replay.encode_replay_json(player.reward_effect_snapshot())
		if not build.ok or not carry.ok:
			_reject("checkpoint", &"ENDLESS_CARRY_INVALID")
			return
		_state.carry_build_codec = build.json
		_state.carry_player_codec = carry.json
		_state.completed_cycles.append({"cycle_index": int(_state.cycle_index), "seed": int(run.run_seed), "frames": maxi(1, int(_state.cycle_frames)), "final_floor_rooms": int(run.current_room), "native_digest": Replay.value_digest({"run": run, "player": player.full_player_replay_snapshot()})})
		if _state.completed_cycles.size() > Endless.MAX_SUMMARIES:
			_state.completed_cycles.pop_front()
		_state.status = "CYCLE_CLEAR"
	else:
		_state.status = "DEFEAT"
	_checkpoint("summary")


func _checkpoint(action: String) -> Dictionary:
	if _host == null or _service == null or _busy:
		return _failure(&"ENDLESS_CHECKPOINT_INVALID")
	_busy = true
	_service.mode_session = _state.duplicate(true)
	var saved = _host.checkpoint_profile_run(int(_service.snapshot().revision))
	_busy = false
	if not saved.ok:
		return _reject(action, saved.code)
	_pending = ""
	_save_error = &""
	_frame_checkpoint = int(_state.elapsed_frames)
	if action == "close":
		close()
		closed.emit()
	elif action == "summary":
		_suspend(true)
	elif _paused:
		_suspend(false)
	state_changed.emit()
	return _success()


func _reject(action: String, code: StringName) -> Dictionary:
	_pending = action
	_save_error = code
	_suspend(true)
	save_rejected.emit(code)
	state_changed.emit()
	return _failure(code)


func _suspend(value: bool) -> void:
	_paused = value
	if not is_instance_valid(_stage):
		return
	if value:
		if not _process_modes.is_empty():
			return
		var nodes: Array[Node] = [_stage]
		nodes.append_array(_stage.find_children("*", "Node", true, false))
		for node: Node in nodes:
			_process_modes.append({"node": weakref(node), "mode": node.process_mode})
			node.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		for row: Dictionary in _process_modes:
			var node: Node = row.node.get_ref()
			if is_instance_valid(node):
				node.process_mode = int(row.mode)
		_process_modes.clear()


func _clear_stage() -> void:
	if is_instance_valid(_presentation):
		_presentation.set_launch_mode(false)
	if is_instance_valid(_controller):
		_controller.encounter_runner().cancel()
		var player := current_player()
		player.set_physics_process(false)
		player.configure_hostile_frame_participant(null)
		player.reset_runtime_state()
	if is_instance_valid(_stage):
		for actor: Node in _stage.find_children("*", "Node2D", true, false):
			for group: String in ["enemies", "bosses", "time_stoppable"]:
				actor.remove_from_group(group)
		_stage.process_mode = Node.PROCESS_MODE_DISABLED
		remove_child(_stage)
		_stage.queue_free()
	_stage = null
	_host = null
	_controller = null
	_scenes = null
	_dungeon = null
	_presentation = null
	_backdrop = null
	_process_modes.clear()
	_active = false
	_paused = false


func _exit_tree() -> void:
	close()


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
