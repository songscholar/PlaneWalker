class_name NativeTrainingFlow
extends Node2D

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")

signal task_completed(task_id: StringName)
signal observation_rejected(code: StringName)
signal observations_saved

var _registry: RefCounted
var _service: RefCounted
var _player: Node2D
var _adapter: RefCounted
var _request: Dictionary = {}
var _busy := false
var _last_rejection: StringName = &""
var _boss_provider: Callable
var _boss: Node2D


func configure(registry: RefCounted, service: RefCounted, boss_provider: Callable = Callable()) -> Dictionary:
	if _registry != null or not is_inside_tree() or not registry is Registry or not service is Service or service.snapshot().is_empty():
		return Candidate.failure(&"TRAINING_CONFIGURATION_INVALID")
	var catalog := Factory.from_registry(registry)
	if not catalog.ok or service.snapshot().catalog_fingerprint != catalog.context.catalog.fingerprint():
		return Candidate.failure(&"TRAINING_CONFIGURATION_INVALID")
	var enabled: Dictionary = service.enable_tutorial(registry.get_catalog_entries(&"tutorial_definition", &"LAUNCH"))
	if not enabled.ok:
		return enabled
	_registry = registry
	_service = service
	_boss_provider = boss_provider
	return Candidate.success()


func start(request: Dictionary) -> Dictionary:
	if _registry == null or _busy or not _valid_request(request) or not _service.snapshot().active_launch_receipt.is_empty():
		return Candidate.failure(&"TRAINING_CONFIGURATION_INVALID")
	if request.task_id == "T-05" and not _boss_provider.is_valid():
		return Candidate.failure(&"TRAINING_BOSS_UNAVAILABLE")
	if _player != null:
		return Candidate.failure(&"TRAINING_ALREADY_ACTIVE")
	_busy = true
	var player: Node2D = PlayerScene.instantiate()
	player.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	add_child(player)
	var native_config := {"milestone": "LAUNCH", "seed": int(request.seed), "character_id": request.character_id, "weapon_id": request.weapon_id, "enabled_time_skills": request.time_abilities.duplicate(), "character_profile": _registry.resolve_character_runtime_profile(StringName(request.character_id), &"LAUNCH"), "weapon_profile": _registry.resolve_weapon_runtime_profile(StringName(request.weapon_id), &"LAUNCH")}
	var run_id := "training-%s-%s" % [str(int(request.seed)), str(request.task_id).to_lower()]
	if not player.configure_run(StringName(run_id)) or not player.configure_loadout(native_config):
		player.queue_free()
		_busy = false
		return Candidate.failure(&"TRAINING_NATIVE_CONFIGURATION_INVALID")
	var boss: Node2D = _boss_provider.call(player, request) if request.task_id == "T-05" else null
	var bound: Dictionary = _service.bind_training(player, request.task_id, int(request.seed), boss)
	if not bound.ok:
		if is_instance_valid(boss):
			boss.queue_free()
		player.queue_free()
		_busy = false
		return bound
	_player = player
	_adapter = bound.context.adapter
	_boss = boss
	_request = request.duplicate(true)
	_busy = false
	return Candidate.success({"player": _player, "adapter": _adapter})


func training_player() -> Node2D:
	return _player if is_instance_valid(_player) else null


func training_adapter() -> RefCounted:
	return _adapter


func process_pending_observations() -> Dictionary:
	if _busy:
		return Candidate.failure(&"BUSY")
	if _adapter == null or not is_instance_valid(_player) or _player.get_parent() != self or not _adapter.is_live_binding():
		return Candidate.failure(&"TRAINING_BINDING_INVALID")
	if get_tree().paused:
		return Candidate.success({"consumed": false})
	_busy = true
	var result := Candidate.success({"consumed": false})
	var completed: Array = []
	while not _adapter.pending_observations().is_empty():
		result = _service.observe_training(_adapter, int(_service.snapshot().revision))
		if not result.ok:
			break
		completed.append_array(result.context.get("completed_tasks", []))
	_busy = false
	if result.ok:
		_last_rejection = &""
		result.context.completed_tasks = completed.duplicate()
		for id: String in completed:
			task_completed.emit(StringName(id))
		if result.context.get("consumed", false) and _adapter != null and _adapter.is_live_binding() and _adapter.pending_observations().is_empty() and not _service.get("_training_recovery_pending"):
			observations_saved.emit()
	return result


func prepare_retirement() -> Dictionary:
	if _busy or get_tree().paused or _adapter == null:
		return Candidate.failure(&"TRAINING_BINDING_INVALID")
	if _service.get("_training_recovery_pending"):
		return Candidate.failure(&"NATIVE_PUBLICATION_PENDING")
	if _adapter.pending_observations().is_empty():
		return Candidate.success({"consumed": false})
	return process_pending_observations()


func reset_attempt() -> Dictionary:
	if _busy or _request.is_empty() or get_tree().paused:
		return Candidate.failure(&"TRAINING_BINDING_INVALID")
	var drained := prepare_retirement()
	if not drained.ok:
		return drained
	var request := _request.duplicate(true)
	close()
	return start(request)


func close() -> void:
	if _busy:
		return
	if _service != null and _adapter != null and _service.get("_training_adapter") == _adapter:
		_service.retire_training()
	elif _adapter != null:
		_adapter.detach()
	if is_instance_valid(_player):
		_player.set_physics_process(false)
		# Weapon adapters also own native payloads outside the Player subtree.
		if not _player.reset_runtime_state():
			push_error("Native training Player retirement failed to clear owned payloads")
		_player.queue_free()
	if is_instance_valid(_boss):
		_boss.set_physics_process(false)
		_boss.remove_from_group("enemies")
		_boss.remove_from_group("bosses")
		_boss.remove_from_group("time_stoppable")
		_boss.queue_free()
	_player = null
	_boss = null
	_adapter = null
	_request.clear()
	_last_rejection = &""


func _process(_delta: float) -> void:
	if _busy or _adapter == null or _adapter.pending_observations().is_empty():
		return
	var result := process_pending_observations()
	if not result.ok and result.code != _last_rejection:
		_last_rejection = result.code
		observation_rejected.emit(result.code)


func _exit_tree() -> void:
	close()


static func _valid_request(request: Dictionary) -> bool:
	if not Catalog.exact_fields(request, ["task_id", "seed", "character_id", "weapon_id", "time_abilities"]) or not request.task_id is String or request.task_id not in ["T-01", "T-02", "T-03", "T-04", "T-05", "T-06"] or not Catalog.bounded_int(request.seed, 0, Catalog.MAX_VALUE) or not request.character_id is String or request.character_id not in Catalog.CHARACTER_IDS or not request.weapon_id is String or request.weapon_id not in Catalog.WEAPON_IDS or not request.time_abilities is Array or request.time_abilities.size() != 2:
		return false
	return request.time_abilities[0] is String and request.time_abilities[1] is String and request.time_abilities[0] in Catalog.TIME_IDS and request.time_abilities[1] in Catalog.TIME_IDS and request.time_abilities[0] != request.time_abilities[1]
