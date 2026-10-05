class_name NativeBossRushFlow
extends Node2D

signal state_changed
signal closed
signal save_rejected(code: StringName)

const Registry := preload("res://scripts/content/content_registry.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Catalog := preload("res://scripts/modes/boss_rush_catalog.gd")
const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const Orchestrator := preload("res://scripts/application/run_orchestrator.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Bridge := preload("res://scripts/enemies/launch/hostile_frame_bridge.gd")
const Effects := preload("res://scripts/enemies/launch/launch_hostile_effect_authority.gd")
const Threats := preload("res://scripts/combat/hostile_threat_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")

var _registry: RefCounted
var _service: RefCounted
var _catalog: RefCounted
var _save: RefCounted
var _save_id := ""
var _profile_id := ""
var _state: Dictionary = {}
var _durable: Dictionary = {}
var _pending: Dictionary = {}
var _pending_action := ""
var _save_error: StringName = &""
var _stage: Node2D
var _room: Node2D
var _player: Node2D
var _boss: Node2D
var _effects: RefCounted
var _bridge: RefCounted
var _orchestrator: RefCounted
var _camera: Camera2D
var _stage_frames := 0
var _active := false
var _busy := false
var _terminal: Dictionary = {}
var _native_failure := ""
var _paused := false
var _stage_modes: Array[Dictionary] = []


func configure(registry: RefCounted, service: RefCounted, root_path: String) -> Dictionary:
	if _registry != null or not is_inside_tree() or not registry is Registry or not service is Service:
		return _failure(&"CHALLENGE_CONFIGURATION_INVALID")
	var catalog := Catalog.new()
	if not catalog.configure(registry):
		return _failure(&"CHALLENGE_CONTENT_INVALID")
	var identity: Dictionary = service.local_record_storage_identity()
	var storage := Save.new()
	if identity.is_empty() or not Rules.same(identity.content_snapshot, Content.snapshot(registry)) or not storage.configure(root_path, "0.4.0-dev", identity.content_snapshot).ok:
		return _failure(&"CHALLENGE_CONFIGURATION_INVALID")
	var id := "rush_" + Rules.canonical({"profile_id": identity.profile_id, "save_domain": identity.save_domain, "content_snapshot": identity.content_snapshot, "mode_fingerprint": catalog.fingerprint()}).sha256_text().substr(0, 26)
	var loaded = storage.load_profile(id, "local")
	if not loaded.ok and loaded.code != &"NOT_FOUND":
		return _failure(loaded.code)
	var session: Variant = loaded.payload.get("boss_rush_session", {}) if loaded.ok else Catalog.empty_session(catalog.fingerprint())
	if not Catalog.valid_session(session, catalog.fingerprint(), identity.profile_id):
		return _failure(&"CHALLENGE_SAVE_INVALID")
	var primary = storage.inspect_profile(id, "local")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _failure(primary.code)
	_registry = registry
	_service = service
	_catalog = catalog
	_save = storage
	_save_id = id
	_profile_id = identity.profile_id
	_state = _normalized(session)
	_durable = primary.payload.duplicate(true) if primary.ok else {}
	_camera = Camera2D.new()
	_camera.position = Vector2(320, 180)
	_camera.enabled = false
	add_child(_camera)
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	return _success()


func start(request: Dictionary) -> Dictionary:
	if _registry == null or _busy or _active or not _pending.is_empty() or not Catalog.valid_request(request) or not _service.snapshot().active_launch_receipt.is_empty() or not _service.snapshot().unlocked_characters.has(request.character_id) or not _service.snapshot().unlocked_weapons.has(request.weapon_id) or _state.session_sequence >= Meta.MAX_VALUE:
		return _failure(&"CHALLENGE_LAUNCH_INVALID")
	var candidate := Catalog.empty_session(_catalog.fingerprint())
	candidate.session_sequence = int(_state.session_sequence) + 1
	candidate.run_id = "boss-rush-%s-%d" % [_profile_id, candidate.session_sequence]
	candidate.request = request.duplicate(true)
	candidate.status = "ACTIVE"
	return _persist(candidate, "stage")


func continue_session() -> Dictionary:
	if _registry == null or _active or _busy or not _pending.is_empty() or _state.status not in ["ACTIVE", "STAGE_CLEAR"] or not _service.snapshot().active_launch_receipt.is_empty():
		return _failure(&"CHALLENGE_CONTINUE_INVALID")
	var candidate := _state.duplicate(true)
	candidate.continued = true
	if candidate.status == "STAGE_CLEAR":
		candidate.stage_index += 1
	candidate.status = "ACTIVE"
	return _persist(candidate, "stage")


func next_stage() -> Dictionary:
	if not _active or _busy or not _pending.is_empty() or _state.status != "STAGE_CLEAR":
		return _failure(&"CHALLENGE_STAGE_INVALID")
	var candidate := _state.duplicate(true)
	candidate.stage_index += 1
	candidate.status = "ACTIVE"
	return _persist(candidate, "stage")


func save_and_return() -> Dictionary:
	if not _active or _busy or not _pending.is_empty():
		return _failure(&"CHALLENGE_STAGE_INVALID")
	_freeze_stage()
	return _persist(_state.duplicate(true), "close")


func retry_save() -> Dictionary:
	if _pending.is_empty() or _busy:
		return _failure(&"CHALLENGE_RETRY_INVALID")
	return _persist(_pending.duplicate(true), _pending_action)


func set_fault_injector(injector: Callable) -> void:
	if _save != null:
		_save.set_fault_injector(injector)


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func has_pending_save() -> bool:
	return not _pending.is_empty()


func save_error() -> StringName:
	return _save_error


func reload_saved_session() -> Dictionary:
	if _save == null or _busy:
		return _failure(&"CHALLENGE_RETRY_INVALID")
	var loaded = _save.load_profile(_save_id, "local")
	if not loaded.ok:
		return _failure(loaded.code)
	var session: Variant = loaded.payload.get("boss_rush_session", {})
	var primary = _save.inspect_profile(_save_id, "local")
	if not Catalog.valid_session(session, _catalog.fingerprint(), _profile_id) or not primary.ok:
		return _failure(&"CHALLENGE_SAVE_INVALID")
	close()
	_state = _normalized(session)
	_durable = primary.payload.duplicate(true)
	_pending.clear()
	_pending_action = ""
	_save_error = &""
	state_changed.emit()
	return _success()


func is_active() -> bool:
	return _active


func is_paused() -> bool:
	return _active and _paused


func set_paused(value: bool) -> void:
	if _active and _state.status == "ACTIVE" and _pending.is_empty() and is_instance_valid(_stage):
		_suspend_stage(value)


func current_player() -> Node2D:
	return _player if is_instance_valid(_player) else null


func current_boss() -> Node2D:
	return _boss if is_instance_valid(_boss) else null


func close() -> void:
	_clear_stage()
	_active = false
	if is_instance_valid(_camera):
		_camera.enabled = false


func _persist(candidate: Dictionary, action: String) -> Dictionary:
	if not Catalog.valid_session(candidate, _catalog.fingerprint(), _profile_id):
		return _failure(&"CHALLENGE_SAVE_INVALID")
	_busy = true
	var primary = _save.inspect_profile(_save_id, "local")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _reject_save(candidate, action, primary.code)
	if (_durable.is_empty() and primary.code != &"NOT_FOUND") or (not _durable.is_empty() and (not primary.ok or not Rules.same(primary.payload, _durable))):
		return _reject_save(candidate, action, &"CHALLENGE_STALE_PRIMARY")
	var written = _save.save_profile_compare_exchange(_save_id, "local", {"boss_rush_session": candidate}, _durable)
	var actual = _save.inspect_profile(_save_id, "local")
	if not actual.ok or not Rules.same(actual.payload.payload.get("boss_rush_session", {}), candidate):
		var changed: bool = actual.ok and not Rules.same(actual.payload, _durable)
		var code: StringName = &"CHALLENGE_STALE_PRIMARY" if changed or written.metadata.get("reason") == "expected_primary_stale" else written.code
		return _reject_save(candidate, action, code if not written.ok else &"CHALLENGE_SAVE_INVALID")
	_state = _normalized(candidate)
	_durable = actual.payload.duplicate(true)
	_pending.clear()
	_pending_action = ""
	_save_error = &""
	_busy = false
	if action == "stage":
		if not _create_stage():
			_active = false
			_camera.enabled = false
			_save_error = &"CHALLENGE_NATIVE_INVALID"
			state_changed.emit()
			return {"ok": false, "code": &"CHALLENGE_NATIVE_INVALID", "context": {"reason": _native_failure}}
	elif action == "close":
		close()
		closed.emit()
	state_changed.emit()
	return _success()


func _reject_save(candidate: Dictionary, action: String, code: StringName) -> Dictionary:
	_pending = candidate.duplicate(true)
	_pending_action = action
	_save_error = code
	_freeze_stage()
	_busy = false
	save_rejected.emit(code)
	return _failure(code)


func _create_stage() -> bool:
	_clear_stage()
	_native_failure = "player_configuration"
	var definition: Dictionary = _catalog.stage(int(_state.stage_index))
	var room_scene: PackedScene = load(definition.template.scene_path)
	var boss_scene: PackedScene = load(definition.boss_scene)
	_stage = Node2D.new()
	add_child(_stage)
	_room = room_scene.instantiate()
	_stage.add_child(_room)
	_player = PlayerScene.instantiate()
	_player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	_stage.add_child(_player)
	var request: Dictionary = _state.request
	var run_id := "%s-stage-%d" % [_state.run_id, int(_state.stage_index) + 1]
	var native_config := {"milestone": "LAUNCH", "seed": int(request.seed), "character_id": request.character_id, "weapon_id": request.weapon_id, "enabled_time_skills": request.time_abilities.duplicate(), "accessibility_assists": request.accessibility_assists, "character_profile": _registry.resolve_character_runtime_profile(StringName(request.character_id), &"LAUNCH"), "weapon_profile": _registry.resolve_weapon_runtime_profile(StringName(request.weapon_id), &"LAUNCH")}
	if not _player.configure_run(StringName(run_id)) or not _player.configure_loadout(native_config):
		_clear_stage()
		return false
	_player.global_position = _room.get_node("PlayerEntry").global_position
	_boss = boss_scene.instantiate()
	var source_id := "rush-" + run_id.sha256_text().substr(0, 40)
	_boss.set_meta("run_id", StringName(run_id))
	_boss.set_meta("encounter_id", &"boss_rush")
	_boss.set_meta("room_id", StringName(str(definition.template.id)))
	_boss.set_meta("encounter_spawn_id", source_id)
	_boss.set_meta("stable_target_id", run_id.sha256_text().substr(0, 12).hex_to_int())
	_boss.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	_stage.add_child(_boss)
	_boss.global_position = _room.get_node("EncounterAnchors/boss_primary").global_position
	_boss.target = _player
	var identity := {"run_id": run_id, "hostile_source_id": source_id, "next_generation_floor": 1, "runtime_frame": int(_player.priority_arbitration_snapshot().frame), "seed": int(request.seed)}
	var boss_configured: Dictionary = _boss.configure_launch_definition(definition.runtime_definition, identity)
	_native_failure = "boss_definition: " + str(boss_configured)
	if not boss_configured.ok:
		_clear_stage()
		return false
	var motion_configured: Dictionary = _boss.configure_launch_room_motion(_room, definition.template)
	_native_failure = "boss_room_motion: " + str(motion_configured)
	if not motion_configured.ok or not _boss.configure_character_boss_exposure_replay_authority(RefCounted.new()):
		_clear_stage()
		return false
	var payloads := Node2D.new()
	_stage.add_child(payloads)
	_effects = Effects.new()
	_bridge = Bridge.new()
	_native_failure = "effects_configuration"
	if not _effects.configure(run_id, int(identity.runtime_frame)) or not _effects.configure_native_payloads(payloads):
		_clear_stage()
		return false
	_native_failure = "bridge_configuration"
	if not _bridge.configure(_player, Threats.new(), [_boss], _effects) or not _player.configure_hostile_frame_participant(_bridge):
		_clear_stage()
		return false
	_orchestrator = Orchestrator.new()
	_orchestrator.enter_hub()
	_orchestrator.start_run({"milestone": "LAUNCH", "character_id": request.character_id, "weapon_id": request.weapon_id, "enabled_time_skills": request.time_abilities, "seed": int(request.seed), "accessibility_assists": request.accessibility_assists}, run_id)
	_orchestrator.preparation_completed()
	_orchestrator.room_entered(true)
	_stage_frames = 0
	_paused = false
	_terminal.clear()
	_player.authoritative_frame_committed.connect(_on_frame)
	_player.health.died.connect(_on_player_died)
	_boss.hostile_final_death.connect(_on_boss_death)
	_active = true
	_camera.enabled = true
	_camera.make_current()
	return true


func _on_frame(_frame: int) -> void:
	if not _active or _paused or _busy or not _pending.is_empty() or _state.status != "ACTIVE" or _orchestrator.is_terminal():
		return
	_stage_frames += 1
	_state.elapsed_frames = mini(Meta.MAX_VALUE, int(_state.elapsed_frames) + 1)
	_orchestrator.advance_time(1.0 / 60.0)


func _on_boss_death(source: StringName, receipt: String) -> void:
	if _busy or not _active or not _terminal.is_empty() or _state.status != "ACTIVE" or not is_instance_valid(_boss) or not is_instance_valid(_player) or _boss.get_parent() != _stage or _boss.target != _player:
		return
	var native: Dictionary = _boss.launch_runtime_snapshot()
	var player_identity: Dictionary = _player.full_player_replay_identity()
	var expected := "hostile_defeat:%s" % (str(_player.current_run_id()) + "|" + str(source)).sha256_text().substr(0, 40)
	if native.is_empty() or not native.runtime.terminal or not _boss.health.dead or _boss.health.current_hp > 0.0 or source != _boss.hostile_source_id or receipt != expected or native.death_receipt != receipt or str(native.runtime.identity.run_id) != str(_player.current_run_id()) or player_identity.is_empty() or _stage_frames < 1:
		return
	var digest := Replay.value_digest({"boss": native, "player": _player.full_player_replay_snapshot()})
	if digest.is_empty():
		return
	_terminal = {"kind": "victory", "source": str(source), "receipt": receipt, "native_digest": digest}
	_apply_terminal.call_deferred()


func _on_player_died(_killer: Variant) -> void:
	if _busy or not _active or not _terminal.is_empty() or _state.status != "ACTIVE" or not is_instance_valid(_player) or _player.get_parent() != _stage or not _player.health.dead or _player.health.current_hp > 0.0:
		return
	_terminal = {"kind": "death"}
	_apply_terminal.call_deferred()


func _apply_terminal() -> void:
	if _terminal.is_empty() or not _active or _state.status != "ACTIVE":
		return
	_freeze_stage()
	var candidate := _state.duplicate(true)
	if _terminal.kind == "victory":
		if not _orchestrator.boss_defeated({"result": "victory"}).ok:
			return
		candidate.completed_stages.append({"stage_index": int(candidate.stage_index), "boss_id": _catalog.stage(int(candidate.stage_index)).boss_id, "run_id": str(_player.current_run_id()), "hostile_source_id": _terminal.source, "death_receipt": _terminal.receipt, "frames": _stage_frames, "native_digest": _terminal.native_digest})
		candidate.status = "VICTORY" if candidate.stage_index == 4 else "STAGE_CLEAR"
	else:
		if not _orchestrator.player_died({"result": "death"}).ok:
			return
		candidate.status = "DEFEAT"
	_persist(candidate, "summary")


func _freeze_stage() -> void:
	if is_instance_valid(_stage):
		_suspend_stage(true)


func _fit_camera() -> void:
	if not is_instance_valid(_camera):
		return
	var size := get_viewport_rect().size
	var factor := minf(size.x / 640.0, size.y / 360.0)
	_camera.zoom = Vector2.ONE * maxf(factor, 0.1)


func _suspend_stage(value: bool) -> void:
	_paused = value
	if value:
		if not _stage_modes.is_empty():
			return
		# Player descendants can process independently of the stage root.
		var nodes: Array[Node] = [_stage]
		nodes.append_array(_stage.find_children("*", "Node", true, false))
		for node: Node in nodes:
			_stage_modes.append({"node": weakref(node), "mode": node.process_mode})
			node.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		for row: Dictionary in _stage_modes:
			var node: Node = row.node.get_ref()
			if is_instance_valid(node):
				node.process_mode = int(row.mode)
		_stage_modes.clear()


func _clear_stage() -> void:
	if is_instance_valid(_player):
		_player.set_physics_process(false)
		_player.configure_hostile_frame_participant(null)
		if _player.is_inside_tree():
			_player.reset_runtime_state()
	if _effects != null:
		_effects.dispose_native_effects()
	if is_instance_valid(_stage):
		for actor: Node in _stage.find_children("*", "Node2D", true, false):
			for group: String in ["enemies", "bosses", "time_stoppable"]:
				actor.remove_from_group(group)
		_stage.process_mode = Node.PROCESS_MODE_DISABLED
		remove_child(_stage)
		_stage.queue_free()
	_stage = null
	_stage_modes.clear()
	_paused = false
	_room = null
	_player = null
	_boss = null
	_effects = null
	_bridge = null
	_orchestrator = null
	_terminal.clear()


func _exit_tree() -> void:
	close()


static func _normalized(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for field: String in ["schema_version", "session_sequence", "stage_index", "elapsed_frames"]:
		result[field] = int(result[field])
	if not result.request.is_empty():
		result.request.seed = int(result.request.seed)
	for row: Dictionary in result.completed_stages:
		row.stage_index = int(row.stage_index)
		row.frames = int(row.frames)
	return result


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
