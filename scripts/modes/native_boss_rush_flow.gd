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
const Arena := preload("res://scripts/modes/native_boss_arena_builder.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const Carried := preload("res://scripts/modes/boss_rush_carried_rules.gd")
const RewardEffects := preload("res://scripts/items/player_reward_effect_runtime.gd")

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
var _carried := false
var _carry_rules: RefCounted
var _stage_hp_loss := 0.0
var _stage_signal_loss := 0.0
var _stage_last_frame := -1
var _stage_last_hp := 0.0
var _root_path := ""
var _domain := ""


func configure(registry: RefCounted, service: RefCounted, root_path: String, carried: bool = false) -> Dictionary:
	if _registry != null or not is_inside_tree() or not registry is Registry or not service is Service:
		return _failure(&"CHALLENGE_CONFIGURATION_INVALID")
	var catalog := Catalog.new()
	if not catalog.configure(registry, carried):
		return _failure(&"CHALLENGE_CONTENT_INVALID")
	_carried = carried
	_carry_rules = Carried.new()
	if carried and not _carry_rules.configure(registry):
		return _failure(&"CHALLENGE_CONTENT_INVALID")
	var identity: Dictionary = service.local_record_storage_identity()
	var storage := Save.new()
	if identity.is_empty() or not Rules.same(identity.content_snapshot, Content.snapshot(registry)) or not storage.configure(root_path, "0.4.0-dev", identity.content_snapshot).ok:
		return _failure(&"CHALLENGE_CONFIGURATION_INVALID")
	var id := "rush_" + Rules.canonical({"profile_id": identity.profile_id, "save_domain": identity.save_domain, "content_snapshot": identity.content_snapshot, "mode_fingerprint": catalog.fingerprint()}).sha256_text().substr(0, 26)
	var loaded = storage.load_profile(id, "local")
	if not loaded.ok and loaded.code != &"NOT_FOUND":
		return _failure(loaded.code)
	var session: Variant = loaded.payload.get("boss_rush_session", {}) if loaded.ok else _empty_session(catalog.fingerprint())
	if not _valid_session(session, catalog.fingerprint(), identity.profile_id):
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
	_root_path = root_path
	_domain = identity.save_domain
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
	if _registry == null or _busy or _active or not _pending.is_empty() or not is_unlocked() or not Catalog.valid_request(request) or not _service.snapshot().active_launch_receipt.is_empty() or not _service.snapshot().unlocked_characters.has(request.character_id) or not _service.snapshot().unlocked_weapons.has(request.weapon_id) or _state.session_sequence >= Meta.MAX_VALUE:
		return _failure(&"CHALLENGE_LAUNCH_INVALID")
	var candidate := _empty_session(_catalog.fingerprint())
	if _carried:
		candidate.carried.history = _state.carried.history.duplicate(true)
		candidate.carried.archived = _state.carried.archived.duplicate(true)
		candidate.carried.reward_ids = _state.carried.reward_ids.duplicate()
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
	if candidate.status == "STAGE_CLEAR" and not _carried:
		candidate.stage_index += 1
	if not _carried or candidate.status != "STAGE_CLEAR":
		candidate.status = "ACTIVE"
	return _persist(candidate, "stage")


func next_stage() -> Dictionary:
	if _carried or not _active or _busy or not _pending.is_empty() or _state.status != "STAGE_CLEAR":
		return _failure(&"CHALLENGE_STAGE_INVALID")
	var candidate := _state.duplicate(true)
	candidate.stage_index += 1
	candidate.status = "ACTIVE"
	return _persist(candidate, "stage")


func save_and_return() -> Dictionary:
	if not _active or _busy or not _pending.is_empty():
		return _failure(&"CHALLENGE_STAGE_INVALID")
	_freeze_stage()
	var candidate := _state.duplicate(true)
	if _carried and candidate.status == "ACTIVE":
		_capture_carried(candidate)
	return _persist(candidate, "close")


func is_unlocked() -> bool:
	return not _carried or _service != null and int(_service.snapshot().statistics.victories) > 0


func uses_carried_rules() -> bool:
	return _carried


func choose_reward(index: int) -> Dictionary:
	if not _carried or not _active or _busy or not _pending.is_empty() or _state.status != "STAGE_CLEAR" or index < 0 or index >= _state.carried.choices.size() or not is_instance_valid(_player):
		return _failure(&"CHALLENGE_CHOICE_INVALID")
	var candidate := _state.duplicate(true)
	var choice: Dictionary = candidate.carried.choices[index]
	var installed := Carried.hydrate(candidate.carried.portable, _player.reward_effect_snapshot())
	if installed.is_empty() or not _player.restore_reward_effect_snapshot(installed):
		return _failure(&"CHALLENGE_BUILD_INVALID")
	var before: Dictionary = _player.reward_effect_snapshot()
	if choice.kind == "restore":
		var restored := before.duplicate(true)
		restored.health.current_hp = float(restored.health.max_hp)
		restored.health.dead = false
		restored.time.energy = float(restored.time.max_energy)
		if not _player.restore_reward_effect_snapshot(restored):
			return _failure(&"CHALLENGE_BUILD_INVALID")
	else:
		var definition: Dictionary = _carry_rules.reward_definition(choice)
		if choice.kind == "item" and definition.get("item_mode") == "active":
			if not _player.equip_active_item(definition, true).ok:
				return _failure(&"CHALLENGE_BUILD_INVALID")
			candidate.carried.active_item_id = choice.id
			candidate.carried.active_cooldown_frames = 0
		else:
			var effects := RewardEffects.new()
			var prepared := effects.prepare(definition, before)
			if not prepared.ok or not effects.commit(prepared.context.plan, _player).ok:
				return _failure(&"CHALLENGE_BUILD_INVALID")
		candidate.carried[choice.kind + "_ids"].append(choice.id)
	candidate.carried.portable = Carried.portable(_player.reward_effect_snapshot())
	candidate.carried.choice_receipts.append({"stage_index": int(candidate.stage_index), "kind": choice.kind, "id": choice.id})
	candidate.carried.choices = []
	candidate.stage_index += 1
	candidate.status = "ACTIVE"
	var result := _persist(candidate, "stage")
	if not result.ok and is_instance_valid(_player):
		_player.restore_reward_effect_snapshot(before, false)
	return result


func mode_reward_storage_scope() -> Dictionary:
	return {"root_path": _root_path, "save_id": _save_id, "save_domain": "local", "source_owner_id": _profile_id, "source_save_domain": _domain, "content_snapshot": Content.snapshot(_registry), "mode_fingerprint": _catalog.fingerprint()} if _carried and _registry != null else {}


func verified_reward_claims() -> Dictionary:
	if not _carried or _save == null:
		return _failure(&"CHALLENGE_CONFIGURATION_INVALID")
	var loaded = _save.load_profile(_save_id, "local")
	var session: Variant = loaded.payload.get("boss_rush_session", {}) if loaded.ok else {}
	if not loaded.ok or not _valid_session(session, _catalog.fingerprint(), _profile_id):
		return _failure(&"CHALLENGE_SAVE_INVALID")
	var claims: Array[Dictionary] = []
	for id: String in session.carried.reward_ids:
		claims.append({"id": "boss_rush_carried:" + id, "kind": "entitlement", "amount": 1, "item_id": id})
	return {"ok": true, "code": &"OK", "context": {"mode_id": "boss_rush_carried", "claims": claims}}


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
	if not _valid_session(session, _catalog.fingerprint(), _profile_id) or not primary.ok:
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
	if not _valid_session(candidate, _catalog.fingerprint(), _profile_id):
		return _failure(&"CHALLENGE_SAVE_INVALID")
	_busy = true
	var primary = _save.inspect_profile(_save_id, "local")
	if not primary.ok and primary.code != &"NOT_FOUND":
		return _reject_save(candidate, action, primary.code)
	if (_durable.is_empty() and primary.code != &"NOT_FOUND") or (not _durable.is_empty() and (not primary.ok or not Rules.same(primary.payload, _durable))):
		return _reject_save(candidate, action, &"CHALLENGE_STALE_PRIMARY")
	var written = _save.save_profile_compare_exchange(_save_id, "local", {"boss_rush_session": candidate}, _durable)
	var actual = _save.inspect_profile(_save_id, "local")
	if written.metadata.get("reason") == "expected_primary_stale":
		return _reject_save(candidate, action, &"CHALLENGE_STALE_PRIMARY")
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
	var definition: Dictionary = _catalog.stage(int(_state.stage_index))
	_stage = Node2D.new()
	add_child(_stage)
	var request: Dictionary = _state.request
	var run_id := "%s-stage-%d" % [_state.run_id, int(_state.stage_index) + 1]
	var built: Dictionary = Arena.build(_stage, _registry, definition, request, run_id, "rush", "boss_rush")
	_native_failure = str(built.get("reason", ""))
	if not built.ok:
		_clear_stage()
		return false
	_room = built.room
	_player = built.player
	_boss = built.boss
	_effects = built.effects
	_bridge = built.bridge
	_orchestrator = built.orchestrator
	if _carried:
		var fresh: Dictionary = _player.reward_effect_snapshot()
		var portable: Dictionary = _state.carried.portable
		var installed := Carried.hydrate(portable, fresh) if not portable.is_empty() else fresh.duplicate(true)
		if portable.is_empty():
			installed.stats.max_hp = 100.0
			installed.health.max_hp = 100.0
			installed.health.current_hp = 100.0
			installed.health.dead = false
		if installed.is_empty() or not _player.restore_reward_effect_snapshot(installed):
			_native_failure = "carried_player_projection"
			_clear_stage()
			return false
		_state.carried.portable = Carried.portable(_player.reward_effect_snapshot())
		if not _state.carried.active_item_id.is_empty():
			if not _player.equip_active_item(_registry.get_content(StringName(_state.carried.active_item_id)), true).ok:
				_native_failure = "carried_active_item"
				_clear_stage()
				return false
			var active: Dictionary = _player.active_item_snapshot()
			active.cooldown_end_frame = int(_state.carried.active_cooldown_frames) - 1
			if not _player.active_item_runtime.restore_snapshot(active):
				_native_failure = "carried_active_cooldown"
				_clear_stage()
				return false
	_stage_frames = 0
	_stage_hp_loss = 0.0
	_stage_signal_loss = 0.0
	_stage_last_frame = int(_player.priority_arbitration_snapshot().frame)
	_stage_last_hp = float(_player.health.current_hp)
	_paused = false
	_terminal.clear()
	_player.authoritative_frame_committed.connect(_on_frame)
	_player.health.died.connect(_on_player_died)
	if _carried:
		_player.health.damaged.connect(_on_player_damaged)
		_player.health.healed.connect(_on_player_healed)
	_boss.hostile_final_death.connect(_on_boss_death)
	_active = true
	_camera.enabled = true
	_camera.make_current()
	if _state.status != "ACTIVE":
		_freeze_stage()
	return true


func _on_frame(frame: int) -> void:
	if not _active or _paused or _busy or not _pending.is_empty() or _state.status != "ACTIVE" or _orchestrator.is_terminal() or frame <= _stage_last_frame or frame != int(_player.priority_arbitration_snapshot().frame):
		return
	_stage_last_frame = frame
	_stage_frames += 1
	_state.elapsed_frames = mini(Meta.MAX_VALUE, int(_state.elapsed_frames) + 1)
	if _carried:
		_observe_hp(float(_player.health.current_hp))
		_capture_damage(_state)
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
	if _carried:
		_capture_carried(candidate)
	if _terminal.kind == "victory":
		if not _orchestrator.boss_defeated({"result": "victory"}).ok:
			return
		candidate.completed_stages.append({"stage_index": int(candidate.stage_index), "boss_id": _catalog.stage(int(candidate.stage_index)).boss_id, "run_id": str(_player.current_run_id()), "hostile_source_id": _terminal.source, "death_receipt": _terminal.receipt, "frames": _stage_frames, "native_digest": _terminal.native_digest})
		candidate.status = "VICTORY" if candidate.stage_index == 4 else "STAGE_CLEAR"
		if _carried:
			var health: Dictionary = candidate.carried.portable.health
			health.current_hp = minf(float(health.max_hp), float(health.current_hp) + float(health.max_hp) * 0.3)
			health.dead = false
			if candidate.status == "STAGE_CLEAR":
				candidate.carried.choices = _carry_rules.choices(candidate.request, int(candidate.stage_index), candidate.carried)
			else:
				_carry_rules.add_history(candidate)
	else:
		if not _orchestrator.player_died({"result": "death"}).ok:
			return
		candidate.status = "DEFEAT"
	_persist(candidate, "summary")


func _capture_damage(candidate: Dictionary) -> void:
	var total := maxf(float(_player.health.hp_loss_state().irreversible_hp_loss_total), _stage_signal_loss)
	candidate.carried.damage_taken = float(candidate.carried.damage_taken) + maxf(0.0, total - _stage_hp_loss)
	_stage_hp_loss = total


func _on_player_damaged(amount: float, current_hp: float) -> void:
	if _accept_hp_notice(amount, current_hp) and current_hp < _stage_last_hp:
		_observe_hp(current_hp)


func _on_player_healed(amount: float, current_hp: float) -> void:
	if _accept_hp_notice(amount, current_hp) and current_hp > _stage_last_hp:
		_stage_last_hp = current_hp


func _accept_hp_notice(amount: float, current_hp: float) -> bool:
	return _carried and _active and _state.status == "ACTIVE" and not _busy and _pending.is_empty() and _terminal.is_empty() and is_finite(amount) and amount > 0.0 and is_finite(current_hp) and is_equal_approx(current_hp, float(_player.health.current_hp))


func _observe_hp(current_hp: float) -> void:
	_stage_signal_loss += maxf(0.0, _stage_last_hp - current_hp)
	_stage_last_hp = current_hp


func _capture_carried(candidate: Dictionary) -> void:
	_capture_damage(candidate)
	candidate.carried.portable = Carried.portable(_player.reward_effect_snapshot())
	if not candidate.carried.active_item_id.is_empty():
		candidate.carried.active_cooldown_frames = int(_player.active_item_runtime.cooldown_remaining())


func _empty_session(fingerprint: String) -> Dictionary:
	var result := Catalog.empty_session(fingerprint)
	if _carried:
		result.schema_version = 2
		result["carried"] = Carried.empty_state()
	return result


func _valid_session(value: Variant, fingerprint: String, owner: String) -> bool:
	return _carry_rules.valid(value, fingerprint, owner) if _carried else Catalog.valid_session(value, fingerprint, owner)


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
