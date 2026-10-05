extends Node2D

signal state_changed
signal save_rejected(code: StringName)

const Registry := preload("res://scripts/content/content_registry.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Catalog := preload("res://scripts/modes/daily_boss_catalog.gd")
const Session := preload("res://scripts/modes/daily_boss_session.gd")
const Arena := preload("res://scripts/modes/native_boss_arena_builder.gd")
const EffectRuntime := preload("res://scripts/items/player_reward_effect_runtime.gd")
const Rules := preload("res://scripts/community/local_run_record_rules.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Meta := preload("res://scripts/progression/meta_progression_catalog.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Rewards := preload("res://scripts/modes/daily_reward_state.gd")
const DailyPlayerScene := preload("res://scripts/modes/daily_player.tscn")
const BossDefinition := preload("res://scripts/enemies/launch/boss_definition.gd")

var _registry: RefCounted
var _service: RefCounted
var _catalog: RefCounted
var _save: RefCounted
var _clock: Callable
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
var _last_hp := 0.0
var _last_frame := -1
var _native_frames := 0
var _storage_scope: Dictionary = {}


func configure(registry: RefCounted, service: RefCounted, root_path: String, clock: Callable = Callable()) -> Dictionary:
	if _registry != null or not is_inside_tree() or not registry is Registry or not service is Service:
		return _failure(&"DAILY_CONFIGURATION_INVALID")
	var catalog := Catalog.new()
	if not catalog.configure(registry):
		return _failure(&"DAILY_CONTENT_INVALID")
	var identity: Dictionary = service.local_record_storage_identity()
	var storage := Save.new()
	if identity.is_empty() or not Rules.same(identity.content_snapshot, Content.snapshot(registry)) or not storage.configure(root_path, "0.4.0-dev", identity.content_snapshot).ok:
		return _failure(&"DAILY_CONFIGURATION_INVALID")
	var id := _mode_save_id(identity, catalog.fingerprint())
	var loaded = storage.load_profile(id, "local")
	var upgrading := false
	if not loaded.ok and loaded.code == &"NOT_FOUND":
		var legacy = storage.load_profile(_mode_save_id(identity, catalog.legacy_fingerprint()), "local")
		if legacy.ok:
			loaded = legacy
			upgrading = true
		elif legacy.code != &"NOT_FOUND":
			return _failure(legacy.code)
	if not loaded.ok and loaded.code != &"NOT_FOUND":
		return _failure(loaded.code)
	var session: Variant = loaded.payload.get("daily_session", {}) if loaded.ok else Session.empty(catalog.fingerprint())
	var migrated := Session.migrate(session, catalog, identity.profile_id)
	if not migrated.ok:
		return _failure(&"DAILY_SAVE_INVALID")
	var primary = storage.inspect_profile(id, "local")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _failure(primary.code)
	if upgrading:
		if primary.code != &"NOT_FOUND":
			return _failure(&"DAILY_STALE_PRIMARY")
		var upgraded = storage.save_profile_compare_exchange(id, "local", {"daily_session": migrated.state}, {})
		primary = storage.inspect_profile(id, "local")
		if upgraded.metadata.get("reason") == "expected_primary_stale":
			return _failure(&"DAILY_STALE_PRIMARY")
		if not primary.ok or not Rules.same(primary.payload.payload.get("daily_session", {}), migrated.state):
			return _failure(&"DAILY_SAVE_INVALID")
	_registry = registry
	_service = service
	_catalog = catalog
	_save = storage
	_save_id = id
	_profile_id = identity.profile_id
	_domain = identity.save_domain
	_clock = clock if clock.is_valid() else func(): return int(Time.get_unix_time_from_system())
	_state = migrated.state
	_storage_scope = {"root_path": root_path, "save_id": id, "save_domain": "local", "source_owner_id": identity.profile_id, "source_save_domain": identity.save_domain, "content_snapshot": identity.content_snapshot.duplicate(true), "mode_fingerprint": catalog.fingerprint()}
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
	var now := _now()
	var definition: Dictionary = _catalog.projection(now)
	var day: Dictionary = _day(_state, int(definition.day_index)) if not definition.is_empty() else {}
	var reason := _start_reason(definition)
	return {"definition": definition, "calendar": _catalog.calendar(now), "remaining_seconds": maxi(0, int(definition.get("reset_at", 0)) - now), "remaining_attempts": 3 - int(day.get("attempts", 0)), "results": day.get("results", []).duplicate(true), "best": day.get("best", {}).duplicate(true), "available": reason == &"", "reason": str(reason), "active": _state.active.duplicate(true), "native_active": is_active(), "native_retry": _native_retry, "paused": _paused, "pending": has_pending_save(), "save_error": str(_save_error), "rewards": _state.reward_state.duplicate(true), "perfect_title_active": not definition.is_empty() and int(_state.reward_state.perfect_day) == int(definition.day_index), "exchange_available": not _busy and not has_pending_save() and _state.active.is_empty()}


func start() -> Dictionary:
	var definition: Dictionary = _catalog.projection(_now()) if _catalog != null else {}
	var reason := _start_reason(definition)
	if reason != &"":
		return _failure(reason)
	var candidate := _state.duplicate(true)
	var day := _day(candidate, int(definition.day_index))
	if day.is_empty():
		day = {"day_index": int(definition.day_index), "day_key": definition.day_key, "attempts": 0, "results": [], "best": {}}
		candidate.days.append(day)
		Session.trim_archive(candidate)
	day.attempts += 1
	candidate.latest_day = int(definition.day_index)
	candidate.active = {"day_index": int(definition.day_index), "attempt": int(day.attempts), "run_id": Session.run_id(_profile_id, int(definition.day_index), int(day.attempts)), "definition": definition.duplicate(true), "elapsed_frames": 0, "damage_events": 0}
	return _persist(candidate, "stage")


func abandon() -> Dictionary:
	if _registry == null or _busy or has_pending_save() or _state.active.is_empty():
		return _failure(&"DAILY_COMMAND_INVALID")
	_set_paused(true)
	return _persist(_terminal_candidate("ABANDON", "", ""), "terminal")


func retry_save() -> Dictionary:
	return _persist(_pending.duplicate(true), _pending_action) if has_pending_save() and not _busy else _failure(&"DAILY_RETRY_INVALID")


func retry_native() -> Dictionary:
	if not _native_retry or _busy or has_pending_save() or _state.active.is_empty():
		return _failure(&"DAILY_RETRY_INVALID")
	return _start_native()


func purchase_reward(id: String) -> Dictionary:
	if _registry == null or _busy or has_pending_save() or not _state.active.is_empty():
		return _failure(&"DAILY_COMMAND_INVALID")
	var bought := Rewards.purchase(_state.reward_state, id)
	if not bought.ok:
		return _failure(&"DAILY_EXCHANGE_INVALID")
	var candidate := _state.duplicate(true)
	candidate.reward_state = bought.state
	return _persist(candidate, "exchange")


func mode_reward_storage_scope() -> Dictionary:
	return _storage_scope.duplicate(true)


func reload_saved_session() -> Dictionary:
	if _save == null or _busy:
		return _failure(&"DAILY_RETRY_INVALID")
	var loaded = _save.load_profile(_save_id, "local")
	var primary = _save.inspect_profile(_save_id, "local")
	var session: Variant = loaded.payload.get("daily_session", {}) if loaded.ok else {}
	var migrated := Session.migrate(session, _catalog, _profile_id)
	if not loaded.ok or not primary.ok or not migrated.ok:
		return _failure(&"DAILY_SAVE_INVALID")
	close()
	_state = migrated.state
	_durable = primary.payload.duplicate(true)
	_pending.clear()
	_pending_action = ""
	_save_error = &""
	state_changed.emit()
	return _success()


func snapshot() -> Dictionary:
	return _state.duplicate(true)


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


func condition_key(id: String) -> String:
	return _catalog.condition_key(id) if _catalog != null else ""


func set_fault_injector(injector: Callable) -> void:
	if _save != null:
		_save.set_fault_injector(injector)


func set_paused(value: bool) -> void:
	if is_active() and not _busy and not has_pending_save() and _terminal.is_empty():
		_set_paused(value)


func is_paused() -> bool:
	return _paused


func close() -> void:
	_clear_stage()
	_native_retry = false
	if is_instance_valid(_camera):
		_camera.enabled = false


func _start_reason(definition: Dictionary) -> StringName:
	if _registry == null or definition.is_empty():
		return &"DAILY_CLOCK_INVALID"
	if _domain != "base":
		return &"DAILY_MOD_UNAVAILABLE"
	var profile: Dictionary = _service.snapshot()
	if int(profile.statistics.victories) < 1 or not profile.completed_boss_ids.has("void_throne"):
		return &"DAILY_VICTORY_REQUIRED"
	if not profile.active_launch_receipt.is_empty():
		return &"DAILY_NORMAL_RUN_ACTIVE"
	if int(definition.day_index) < int(_state.latest_day):
		return &"DAILY_CLOCK_ROLLBACK"
	if _busy or has_pending_save():
		return &"DAILY_SAVE_PENDING"
	if not _state.active.is_empty():
		return &"DAILY_ATTEMPT_ACTIVE"
	if int(_day(_state, int(definition.day_index)).get("attempts", 0)) >= 3:
		return &"DAILY_ATTEMPTS_EXHAUSTED"
	return &""


func _persist(candidate: Dictionary, action: String) -> Dictionary:
	if not Session.valid(candidate, _catalog, _profile_id):
		return _failure(&"DAILY_SAVE_INVALID")
	_busy = true
	var primary = _save.inspect_profile(_save_id, "local")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _reject_save(candidate, action, primary.code)
	if (_durable.is_empty() and primary.code != &"NOT_FOUND") or (not _durable.is_empty() and (not primary.ok or not Rules.same(primary.payload, _durable))):
		return _reject_save(candidate, action, &"DAILY_STALE_PRIMARY")
	var written = _save.save_profile_compare_exchange(_save_id, "local", {"daily_session": candidate}, _durable)
	var actual = _save.inspect_profile(_save_id, "local")
	if written.metadata.get("reason") == "expected_primary_stale":
		return _reject_save(candidate, action, &"DAILY_STALE_PRIMARY")
	if not actual.ok or not Rules.same(actual.payload.payload.get("daily_session", {}), candidate):
		var changed: bool = actual.ok and not Rules.same(actual.payload, _durable)
		var code: StringName = &"DAILY_STALE_PRIMARY" if changed or written.metadata.get("reason") == "expected_primary_stale" else written.code
		return _reject_save(candidate, action, code if not written.ok else &"DAILY_SAVE_INVALID")
	_state = Session.normalized(candidate)
	_durable = actual.payload.duplicate(true)
	_pending.clear()
	_pending_action = ""
	_save_error = &""
	_busy = false
	if action == "stage":
		return _start_native()
	if action == "terminal":
		close()
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
	var stage_definition: Dictionary = _catalog.stage(active.definition)
	var original_boss: Dictionary = stage_definition.runtime_definition.duplicate(true)
	var projected := BossDefinition.daily_projection(original_boss, _catalog.native_condition_ids(active.definition, "boss"))
	if not projected.ok:
		return _reject_native("boss_daily_projection")
	stage_definition.runtime_definition = projected.definition
	var built: Dictionary = Arena.build(_stage, _registry, stage_definition, _catalog.request(active.definition), active.run_id, "daily", "daily_boss", DailyPlayerScene)
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
	for definition: Dictionary in _catalog.build_definitions(active.definition):
		var prepared: Dictionary = effects.prepare(definition, _player.reward_effect_snapshot())
		if not prepared.ok:
			return _reject_native("prepare %s: %s" % [definition.id, str(prepared)])
		var committed: Dictionary = effects.commit(prepared.context.plan, _player)
		if not committed.ok:
			return _reject_native("commit %s: %s" % [definition.id, str(committed)])
		_build_receipts.append({"definition_id": definition.id, "receipt": committed.context.receipt})
	var player_rules_before: Dictionary = _player.daily_rule_snapshot()
	if not _player.configure_daily_rules(_catalog.native_condition_ids(active.definition, "player")):
		return _reject_native("player_daily_rules")
	for id: String in active.definition.condition_ids:
		if Catalog.NATIVE_RULES.has(id):
			_build_receipts.append({"definition_id": "daily_" + id, "receipt": {"operation_count": 1, "before_snapshot": {"player": player_rules_before.duplicate(true), "boss": original_boss.duplicate(true)}, "after_snapshot": {"player": _player.daily_rule_snapshot(), "boss": projected.definition.duplicate(true)}}})
	_native_retry = false
	_paused = false
	_terminal.clear()
	_last_hp = float(_player.health.current_hp)
	_last_frame = int(_player.priority_arbitration_snapshot().frame)
	_native_frames = 0
	_player.authoritative_frame_committed.connect(_on_frame)
	_player.health.died.connect(_on_player_died)
	_player.health.damaged.connect(_on_damage)
	_player.health.healed.connect(_on_healed)
	_boss.hostile_final_death.connect(_on_boss_death)
	_camera.enabled = true
	_camera.make_current()
	state_changed.emit()
	return _success()


func _reject_native(reason: String) -> Dictionary:
	_clear_stage()
	_native_retry = true
	_save_error = &"DAILY_NATIVE_INVALID"
	state_changed.emit()
	return {"ok": false, "code": _save_error, "context": {"reason": reason}}


func _on_frame(frame: int) -> void:
	if not is_active() or _paused or _busy or has_pending_save() or not _terminal.is_empty() or frame <= _last_frame or frame != int(_player.priority_arbitration_snapshot().frame):
		return
	_last_frame = frame
	_native_frames += 1
	_observe_hp(float(_player.health.current_hp))
	_state.active.elapsed_frames = mini(Meta.MAX_VALUE, int(_state.active.elapsed_frames) + 1)
	_orchestrator.advance_time(1.0 / 60.0)


func _on_damage(amount: float, hp: float) -> void:
	if _accept_health_notice(amount, hp) and hp < _last_hp:
		_observe_hp(hp)


func _on_healed(amount: float, hp: float) -> void:
	if _accept_health_notice(amount, hp) and hp > _last_hp:
		_last_hp = hp


func _accept_health_notice(amount: float, hp: float) -> bool:
	return is_active() and not _paused and not _busy and not has_pending_save() and _terminal.is_empty() and is_finite(amount) and is_finite(hp) and amount > 0 and is_equal_approx(hp, float(_player.health.current_hp))


func _observe_hp(hp: float) -> void:
	if hp < _last_hp and int(_state.active.damage_events) >= 0:
		_state.active.damage_events = mini(Meta.MAX_VALUE, int(_state.active.damage_events) + 1)
	_last_hp = hp


func _on_boss_death(source: StringName, receipt: String) -> void:
	if not is_active() or _busy or has_pending_save() or not _terminal.is_empty() or _boss.get_parent() != _stage or _boss.target != _player:
		return
	var native: Dictionary = _boss.launch_runtime_snapshot()
	var run := str(_state.active.run_id)
	var expected := "hostile_defeat:" + (run + "|" + str(source)).sha256_text().substr(0, 40)
	if native.is_empty() or not native.runtime.terminal or not _boss.health.dead or _boss.health.current_hp > 0.0 or _player.health.dead or source != _boss.hostile_source_id or receipt != expected or native.death_receipt != receipt or str(native.runtime.identity.run_id) != run or str(_player.current_run_id()) != run or _native_frames < 1:
		return
	var digest := Replay.value_digest({"boss": native, "player": _player.full_player_replay_snapshot(), "daily_player": _player.daily_rule_snapshot()})
	if digest.is_empty():
		return
	_terminal = {"status": "VICTORY", "receipt": receipt, "digest": digest}
	_apply_terminal.call_deferred()


func _on_player_died(_killer: Variant) -> void:
	if not is_active() or _busy or has_pending_save() or not _terminal.is_empty() or _player.get_parent() != _stage or not _player.health.dead or _player.health.current_hp > 0.0 or _native_frames < 1:
		return
	var digest := Replay.value_digest({"boss": _boss.launch_runtime_snapshot(), "player": _player.full_player_replay_snapshot(), "daily_player": _player.daily_rule_snapshot()})
	if not digest.is_empty():
		_terminal = {"status": "DEFEAT", "receipt": "", "digest": digest}
		_apply_terminal.call_deferred()


func _apply_terminal() -> void:
	if _terminal.is_empty() or not is_active() or has_pending_save():
		return
	_set_paused(true)
	var outcome = _orchestrator.boss_defeated({"result": "victory"}) if _terminal.status == "VICTORY" else _orchestrator.player_died({"result": "death"})
	if outcome.ok:
		_persist(_terminal_candidate(_terminal.status, _terminal.receipt, _terminal.digest), "terminal")


func _terminal_candidate(status: String, receipt: String, digest: String) -> Dictionary:
	var candidate := _state.duplicate(true)
	var active: Dictionary = candidate.active
	var run := str(active.run_id)
	var hp := 0
	if is_instance_valid(_player) and _player.health.max_hp > 0:
		hp = clampi(roundi(float(_player.health.current_hp) / float(_player.health.max_hp) * 100000.0), 0, 100000)
		if status == "VICTORY" and _player.health.current_hp > 0:
			hp = maxi(1, hp)
	var day := _day(candidate, int(active.day_index))
	day.results.append({"attempt": int(active.attempt), "run_id": run, "status": status, "elapsed_frames": int(active.elapsed_frames), "remaining_hp_milli": hp, "hostile_source_id": "daily-" + run.sha256_text().substr(0, 40), "death_receipt": receipt, "native_digest": digest, "damage_events": int(active.damage_events)})
	day.best = Session.best(day.results)
	candidate.reward_state = Rewards.award(candidate.reward_state, int(active.day_index), status, int(active.damage_events))
	candidate.active = {}
	return candidate


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


func _now() -> int:
	var value: Variant = _clock.call()
	return int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0 and float(value) < float(Catalog.MAX_DAY * 86400) else -86400


func _exit_tree() -> void:
	close()


static func _day(state: Dictionary, day: int) -> Dictionary:
	for row: Dictionary in state.days:
		if int(row.day_index) == day:
			return row
	return {}


static func _success() -> Dictionary:
	return {"ok": true, "code": &"OK", "context": {}}


static func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}


static func _mode_save_id(identity: Dictionary, fingerprint: String) -> String:
	return "daily_" + Rules.canonical({"profile_id": identity.profile_id, "save_domain": identity.save_domain, "content_snapshot": identity.content_snapshot, "mode_fingerprint": fingerprint}).sha256_text().substr(0, 26)
