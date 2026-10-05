extends Node2D

signal state_changed
signal save_rejected(code: StringName)
signal closed

const Registry := preload("res://scripts/content/content_registry.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Catalog := preload("res://scripts/modes/authored_challenge_catalog.gd")
const Session := preload("res://scripts/modes/authored_challenge_session.gd")
const Arena := preload("res://scripts/modes/native_boss_arena_builder.gd")
const EffectRuntime := preload("res://scripts/items/player_reward_effect_runtime.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")

var _registry: RefCounted
var _service: RefCounted
var _catalog: RefCounted
var _save: RefCounted
var _save_id := ""
var _profile_id := ""
var _domain := ""
var _state: Dictionary = {}
var _durable: Dictionary = {}
var _pending: Dictionary = {}
var _pending_action := ""
var _save_error: StringName = &""
var _busy := false
var _native_retry := false
var _stage: Node2D
var _player: Node2D
var _boss: Node2D
var _effects: RefCounted
var _orchestrator: RefCounted
var _camera: Camera2D
var _paused := false
var _stage_modes: Array[Dictionary] = []
var _terminal: Dictionary = {}
var _baseline: Dictionary = {}
var _build_receipts: Array = []
var _native_frames := 0
var _last_frame := -1
var _last_hp := 0.0


func configure(registry: RefCounted, service: RefCounted, root_path: String) -> Dictionary:
	if _registry != null or not is_inside_tree() or not registry is Registry or not service is Service:
		return _failure(&"AUTHORED_CONFIGURATION_INVALID")
	var catalog := Catalog.new()
	if not catalog.configure(registry):
		return _failure(&"AUTHORED_CONTENT_INVALID")
	var identity: Dictionary = service.local_record_storage_identity()
	var storage := Save.new()
	if identity.is_empty() or not Rules.same(identity.content_snapshot, Content.snapshot(registry)) or not storage.configure(root_path, "0.4.0-dev", identity.content_snapshot).ok:
		return _failure(&"AUTHORED_CONFIGURATION_INVALID")
	var id := "authored_" + Rules.canonical({"profile_id": identity.profile_id, "save_domain": identity.save_domain, "content_snapshot": identity.content_snapshot, "mode_fingerprint": catalog.fingerprint()}).sha256_text().substr(0, 23)
	var loaded = storage.load_profile(id, "local")
	if not loaded.ok and loaded.code != &"NOT_FOUND":
		return _failure(loaded.code)
	var session: Variant = loaded.payload.get("authored_session", {}) if loaded.ok else Session.empty(catalog.fingerprint())
	if not Session.valid(session, catalog, identity.profile_id):
		return _failure(&"AUTHORED_SAVE_INVALID")
	var primary = storage.inspect_profile(id, "local")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _failure(primary.code)
	_registry = registry
	_service = service
	_catalog = catalog
	_save = storage
	_save_id = id
	_profile_id = identity.profile_id
	_domain = identity.save_domain
	_state = Session.normalized(session)
	_durable = primary.payload.duplicate(true) if primary.ok else {}
	_camera = Camera2D.new()
	_camera.position = Vector2(320, 180)
	_camera.enabled = false
	add_child(_camera)
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	return _success()


func preview() -> Dictionary:
	if _catalog == null:
		return {}
	var active: Dictionary = _state.active
	var definition: Dictionary = _catalog.definition(str(active.get("set_id", "")))
	return {"sets": _catalog.entries(), "active": active.duplicate(true), "history": _state.history.duplicate(true), "best": _state.best.duplicate(true), "native_active": is_active(), "paused": _paused, "pending": has_pending_save(), "native_retry": _native_retry, "save_error": str(_save_error), "start_reason": str(_start_reason()), "current_boss_id": definition.boss_ids[int(active.stage_index)] if not definition.is_empty() else ""}


func snapshot() -> Dictionary:
	return _state.duplicate(true)


func start(set_id: String) -> Dictionary:
	var reason := _start_reason()
	if reason != &"":
		return _failure(reason)
	if _catalog.definition(set_id).is_empty() or _state.sequence >= Meta.MAX_VALUE:
		return _failure(&"AUTHORED_COMMAND_INVALID")
	var candidate := _state.duplicate(true)
	candidate.sequence += 1
	candidate.active = {"sequence": int(candidate.sequence), "set_id": set_id, "run_id": Session.run_id(_profile_id, set_id, int(candidate.sequence)), "stage_index": 0, "status": "ACTIVE", "elapsed_frames": 0, "stage_frames": 0, "damage_events": 0, "stage_damage_events": 0, "continued": false, "stages": []}
	return _persist(candidate, "stage")


func next_stage() -> Dictionary:
	if not is_active() or _busy or has_pending_save() or _state.active.status != "STAGE_CLEAR":
		return _failure(&"AUTHORED_COMMAND_INVALID")
	var candidate := _state.duplicate(true)
	_advance_stage(candidate.active)
	return _persist(candidate, "stage")


func continue_session() -> Dictionary:
	if _registry == null or is_active() or _busy or has_pending_save() or _state.active.is_empty() or not _service.snapshot().active_launch_receipt.is_empty():
		return _failure(&"AUTHORED_COMMAND_INVALID")
	var candidate := _state.duplicate(true)
	candidate.active.continued = true
	if candidate.active.status == "STAGE_CLEAR":
		_advance_stage(candidate.active)
	return _persist(candidate, "stage")


func save_and_return() -> Dictionary:
	if not is_active() or _busy or has_pending_save() or not _terminal.is_empty() and _state.active.status == "ACTIVE":
		return _failure(&"AUTHORED_COMMAND_INVALID")
	_set_paused(true)
	var candidate := _state.duplicate(true)
	candidate.active.continued = true
	return _persist(candidate, "close")


func abandon() -> Dictionary:
	if _registry == null or _busy or has_pending_save() or _state.active.is_empty():
		return _failure(&"AUTHORED_COMMAND_INVALID")
	_set_paused(true)
	return _persist(_result_candidate("ABANDON", ""), "terminal")


func retry_save() -> Dictionary:
	return _persist(_pending.duplicate(true), _pending_action) if has_pending_save() and not _busy else _failure(&"AUTHORED_RETRY_INVALID")


func retry_native() -> Dictionary:
	return _start_native() if _native_retry and not _busy and not has_pending_save() and not _state.active.is_empty() else _failure(&"AUTHORED_RETRY_INVALID")


func reload_saved_session() -> Dictionary:
	if _save == null or _busy:
		return _failure(&"AUTHORED_RETRY_INVALID")
	var loaded = _save.load_profile(_save_id, "local")
	var primary = _save.inspect_profile(_save_id, "local")
	var session: Variant = loaded.payload.get("authored_session", {}) if loaded.ok else {}
	if not loaded.ok or not primary.ok or not Session.valid(session, _catalog, _profile_id):
		return _failure(&"AUTHORED_SAVE_INVALID")
	close()
	_state = Session.normalized(session)
	_durable = primary.payload.duplicate(true)
	_pending.clear()
	_pending_action = ""
	_save_error = &""
	state_changed.emit()
	return _success()


func is_active() -> bool:
	return is_instance_valid(_stage) and is_instance_valid(_player) and not _state.active.is_empty()


func has_pending_save() -> bool:
	return not _pending.is_empty()


func current_player() -> Node2D:
	return _player if is_instance_valid(_player) else null


func current_boss() -> Node2D:
	return _boss if is_instance_valid(_boss) else null


func baseline_player_effects() -> Dictionary:
	return _baseline.duplicate(true)


func installed_build_receipts() -> Array:
	return _build_receipts.duplicate(true)


func set_fault_injector(injector: Callable) -> void:
	if _save != null:
		_save.set_fault_injector(injector)


func set_paused(value: bool) -> void:
	if is_active() and _state.active.status == "ACTIVE" and not _busy and not has_pending_save() and _terminal.is_empty():
		_set_paused(value)


func is_paused() -> bool:
	return _paused


func close() -> void:
	_clear_stage()
	_native_retry = false
	if is_instance_valid(_camera):
		_camera.enabled = false


func _start_reason() -> StringName:
	if _registry == null:
		return &"AUTHORED_CONFIGURATION_INVALID"
	if _domain != "base":
		return &"AUTHORED_MOD_UNAVAILABLE"
	var profile: Dictionary = _service.snapshot()
	if int(profile.statistics.victories) < 1 or not profile.completed_boss_ids.has("void_throne"):
		return &"AUTHORED_VICTORY_REQUIRED"
	if not profile.active_launch_receipt.is_empty():
		return &"AUTHORED_NORMAL_RUN_ACTIVE"
	if _busy or has_pending_save():
		return &"AUTHORED_SAVE_PENDING"
	return &"AUTHORED_ATTEMPT_ACTIVE" if not _state.active.is_empty() else &""


func _persist(candidate: Dictionary, action: String) -> Dictionary:
	if not Session.valid(candidate, _catalog, _profile_id):
		return _failure(&"AUTHORED_SAVE_INVALID")
	_busy = true
	var primary = _save.inspect_profile(_save_id, "local")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _reject_save(candidate, action, primary.code)
	if _durable.is_empty() and primary.code != &"NOT_FOUND" or not _durable.is_empty() and (not primary.ok or not Rules.same(primary.payload, _durable)):
		return _reject_save(candidate, action, &"AUTHORED_STALE_PRIMARY")
	var written = _save.save_profile_compare_exchange(_save_id, "local", {"authored_session": candidate}, _durable)
	var actual = _save.inspect_profile(_save_id, "local")
	if written.metadata.get("reason") == "expected_primary_stale":
		return _reject_save(candidate, action, &"AUTHORED_STALE_PRIMARY")
	if not actual.ok or not Rules.same(actual.payload.payload.get("authored_session", {}), candidate):
		var changed: bool = actual.ok and not Rules.same(actual.payload, _durable)
		return _reject_save(candidate, action, &"AUTHORED_STALE_PRIMARY" if changed else (written.code if not written.ok else &"AUTHORED_SAVE_INVALID"))
	_state = Session.normalized(candidate)
	_durable = actual.payload.duplicate(true)
	_pending.clear()
	_pending_action = ""
	_save_error = &""
	_busy = false
	if action == "stage":
		return _start_native()
	if action in ["terminal", "close"]:
		close()
		if action == "close":
			closed.emit()
	state_changed.emit()
	return _success()


func _reject_save(candidate: Dictionary, action: String, code: StringName) -> Dictionary:
	_pending = candidate.duplicate(true)
	_pending_action = action
	_save_error = code
	_set_paused(true)
	_busy = false
	save_rejected.emit(code)
	state_changed.emit()
	return _failure(code)


func _start_native() -> Dictionary:
	_clear_stage()
	var active: Dictionary = _state.active
	_stage = Node2D.new()
	add_child(_stage)
	var run := Session.stage_run_id(active.run_id, int(active.stage_index))
	var built: Dictionary = Arena.build(_stage, _registry, _catalog.stage(active.set_id, int(active.stage_index)), _catalog.request(active.set_id, int(active.stage_index)), run, "authored", "authored_challenge")
	if not built.ok:
		return _reject_native(str(built.get("reason", "arena")))
	_player = built.player
	_boss = built.boss
	_effects = built.effects
	_orchestrator = built.orchestrator
	var effects := EffectRuntime.new()
	var baseline: Dictionary = effects.prepare(_catalog.baseline_definition(float(_player.health.max_hp)), _player.reward_effect_snapshot())
	if not baseline.ok or not effects.commit(baseline.context.plan, _player).ok:
		return _reject_native("starting_hp")
	_baseline = _player.reward_effect_snapshot()
	_build_receipts.clear()
	for definition: Dictionary in _catalog.build_definitions(active.set_id):
		var prepared: Dictionary = effects.prepare(definition, _player.reward_effect_snapshot())
		if not prepared.ok:
			return _reject_native("prepare %s: %s" % [definition.id, str(prepared)])
		var committed: Dictionary = effects.commit(prepared.context.plan, _player)
		if not committed.ok:
			return _reject_native("commit %s: %s" % [definition.id, str(committed)])
		_build_receipts.append({"definition_id": definition.id, "receipt": committed.context.receipt})
	_native_retry = false
	_paused = false
	_native_frames = 0
	_last_frame = int(_player.priority_arbitration_snapshot().frame)
	_last_hp = float(_player.health.current_hp)
	_player.authoritative_frame_committed.connect(_on_frame)
	_player.health.damaged.connect(_on_damage)
	_player.health.healed.connect(_on_healed)
	_player.health.died.connect(_on_player_died)
	_boss.hostile_final_death.connect(_on_boss_death)
	_camera.enabled = true
	_camera.make_current()
	state_changed.emit()
	return _success()


func _reject_native(reason: String) -> Dictionary:
	_clear_stage()
	_native_retry = true
	_save_error = &"AUTHORED_NATIVE_INVALID"
	state_changed.emit()
	return {"ok": false, "code": _save_error, "context": {"reason": reason}}


func _on_frame(frame: int) -> void:
	if not is_active() or _paused or _busy or has_pending_save() or not _terminal.is_empty() or _state.active.status != "ACTIVE" or frame <= _last_frame or frame != int(_player.priority_arbitration_snapshot().frame):
		return
	_last_frame = frame
	_native_frames += 1
	_state.active.elapsed_frames = mini(Meta.MAX_VALUE, int(_state.active.elapsed_frames) + 1)
	_state.active.stage_frames = mini(Meta.MAX_VALUE, int(_state.active.stage_frames) + 1)
	_orchestrator.advance_time(1.0 / 60.0)


func _on_damage(amount: float, hp: float) -> void:
	if not is_active() or _paused or _busy or has_pending_save() or not _terminal.is_empty() or _state.active.status != "ACTIVE" or not is_finite(amount) or not is_finite(hp) or amount <= 0 or hp >= _last_hp or hp < float(_player.health.current_hp):
		return
	_last_hp = hp
	_state.active.damage_events = mini(Meta.MAX_VALUE, int(_state.active.damage_events) + 1)
	_state.active.stage_damage_events = mini(Meta.MAX_VALUE, int(_state.active.stage_damage_events) + 1)


func _on_healed(amount: float, hp: float) -> void:
	if not is_active() or _paused or _busy or has_pending_save() or not _terminal.is_empty() or _state.active.status != "ACTIVE" or not is_finite(amount) or not is_finite(hp) or amount <= 0 or hp <= _last_hp or hp > float(_player.health.current_hp):
		return
	_last_hp = hp


func _on_boss_death(source: StringName, receipt: String) -> void:
	_capture_boss_death.call_deferred(source, receipt)


func _capture_boss_death(source: StringName, receipt: String) -> void:
	if not is_active() or _busy or has_pending_save() or not _terminal.is_empty() or _state.active.status != "ACTIVE" or _boss.get_parent() != _stage or _boss.target != _player:
		return
	var native: Dictionary = _boss.launch_runtime_snapshot()
	var run := Session.stage_run_id(_state.active.run_id, int(_state.active.stage_index))
	var expected := "hostile_defeat:" + (run + "|" + str(source)).sha256_text().substr(0, 40)
	if native.is_empty() or not native.runtime.terminal or not _boss.health.dead or _boss.health.current_hp > 0 or _player.health.dead or source != _boss.hostile_source_id or receipt != expected or native.death_receipt != receipt or str(native.runtime.identity.run_id) != run or str(_player.current_run_id()) != run or _native_frames < 1:
		return
	var digest := Replay.value_digest({"boss": native, "player": _player.full_player_replay_snapshot()})
	if digest.is_empty():
		return
	_terminal = {"status": "BOSS_CLEAR", "receipt": receipt, "digest": digest}
	_set_paused(true)
	var candidate := _state.duplicate(true)
	var active: Dictionary = candidate.active
	var definition: Dictionary = _catalog.definition(active.set_id)
	active.stages.append({"stage_index": int(active.stage_index), "boss_id": definition.boss_ids[int(active.stage_index)], "run_id": run, "hostile_source_id": str(source), "death_receipt": receipt, "frames": int(active.stage_frames), "damage_events": int(active.stage_damage_events), "remaining_hp_milli": _hp_milli(), "native_digest": digest})
	if not Session.objective_passed(definition, active.stages, int(active.elapsed_frames), int(active.damage_events)):
		candidate = _result_candidate("OBJECTIVE_FAILED", digest, candidate)
	elif int(active.stage_index) == 2:
		candidate = _result_candidate("VICTORY", digest, candidate)
	else:
		active.status = "STAGE_CLEAR"
	_orchestrator.boss_defeated({"result": "victory"})
	_persist(candidate, "terminal" if candidate.active.is_empty() else "clear")


func _on_player_died(_killer: Variant) -> void:
	_capture_player_death.call_deferred()


func _capture_player_death() -> void:
	if not is_active() or _busy or has_pending_save() or not _terminal.is_empty() or _state.active.status != "ACTIVE" or _player.get_parent() != _stage or not _player.health.dead or _player.health.current_hp > 0 or _native_frames < 1:
		return
	var digest := Replay.value_digest({"boss": _boss.launch_runtime_snapshot(), "player": _player.full_player_replay_snapshot()})
	if digest.is_empty():
		return
	_terminal = {"status": "DEFEAT", "digest": digest}
	_set_paused(true)
	_orchestrator.player_died({"result": "death"})
	_persist(_result_candidate("DEFEAT", digest), "terminal")


func _result_candidate(status: String, digest: String, source: Dictionary = {}) -> Dictionary:
	var candidate := _state.duplicate(true) if source.is_empty() else source.duplicate(true)
	var active: Dictionary = candidate.active
	var result := {"sequence": int(active.sequence), "set_id": active.set_id, "run_id": active.run_id, "status": status, "elapsed_frames": int(active.elapsed_frames), "damage_events": int(active.damage_events), "remaining_hp_milli": _hp_milli(), "continued": bool(active.continued), "stages": active.stages.duplicate(true), "terminal_digest": digest}
	if not candidate.history.has(active.set_id):
		candidate.history[active.set_id] = []
	candidate.history[active.set_id].append(result)
	while candidate.history[active.set_id].size() > 10:
		candidate.history[active.set_id].pop_front()
	if status == "VICTORY" and not result.continued and (not candidate.best.has(active.set_id) or Session.ranks_before(result, candidate.best[active.set_id])):
		candidate.best[active.set_id] = result.duplicate(true)
	candidate.active = {}
	return candidate


func _hp_milli() -> int:
	if not is_instance_valid(_player) or _player.health.max_hp <= 0 or _player.health.dead:
		return 0
	return maxi(1, clampi(roundi(float(_player.health.current_hp) / float(_player.health.max_hp) * 100000), 0, 100000))


static func _advance_stage(active: Dictionary) -> void:
	active.stage_index += 1
	active.status = "ACTIVE"
	active.stage_frames = 0
	active.stage_damage_events = 0


func _set_paused(value: bool) -> void:
	_paused = value
	if not is_instance_valid(_stage):
		return
	if value:
		if not _stage_modes.is_empty():
			return
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
	_player = null
	_boss = null
	_effects = null
	_orchestrator = null
	_stage_modes.clear()
	_terminal.clear()
	_paused = false


func _fit_camera() -> void:
	if is_instance_valid(_camera):
		var size := get_viewport_rect().size
		_camera.zoom = Vector2.ONE * maxf(minf(size.x / 640.0, size.y / 360.0), 0.1)


func _exit_tree() -> void:
	close()


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
