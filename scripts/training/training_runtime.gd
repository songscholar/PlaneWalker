class_name TrainingRuntime
extends RefCounted

signal observation_saved(receipt: Dictionary)

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const Player := preload("res://scripts/player/player_controller.gd")
const World := preload("res://scripts/combat/world_payload_authority.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const ActionState := preload("res://scripts/player/player_action_state.gd")
const TrainingBoss := preload("res://scripts/training/training_chrono_warden.gd")
const MAX_PENDING := 64

var _player: WeakRef
var _world: WeakRef
var _identity: Dictionary = {}
var _config: Dictionary = {}
var _drill: Dictionary = {}
var _pending: Array = []
var _counts: Dictionary = {}
var _last_frame := 0
var _last_position := Vector2.ZERO
var _next_action := 1
var _retired := false
var _publishing := false
var _callback: Callable
var _boss: WeakRef
var _boss_health: WeakRef
var _boss_parent: WeakRef
var _boss_identity: Dictionary = {}


func configure(player: Node, config: Dictionary, drill: Dictionary, boss: Node = null) -> bool:
	if _player != null or _retired or not player is Player or not is_instance_valid(player) or not player.is_inside_tree() or not Catalog.exact_fields(config, ["session_sequence", "seed"]) or not Catalog.bounded_int(config.session_sequence, 1, Catalog.MAX_VALUE) or not Catalog.bounded_int(config.seed, 0, Catalog.MAX_VALUE) or drill.get("definition_kind") != "training_task" or drill.get("task_id") not in ["T-01", "T-02", "T-03", "T-04", "T-05", "T-06"] or not drill.get("receipt_requirements") is Array:
		return false
	var world: Node = player.world_payload_authority
	var identity: Dictionary = player.full_player_replay_identity()
	var native: Dictionary = player.full_player_replay_snapshot()
	var expected_run_id := "training-%s-%s" % [str(int(config.seed)), str(drill.task_id).to_lower()]
	if not world is World or not is_instance_valid(world) or not world.is_inside_tree() or world.get_parent() != player or world != player.get_node_or_null("WorldPayloadAuthority") or identity.is_empty() or str(identity.run_id) != expected_run_id or player.loadout_runtime.run_seed() != int(config.seed) or identity.has("meta_projection_digest") or native.is_empty() or not Replay.validate_full_player_snapshot(native, identity).ok or player.health.dead:
		return false
	for requirement: Variant in drill.receipt_requirements:
		if not requirement is Dictionary or requirement.get("context_id") != "training_drill" or requirement.get("action_id") not in ["move", "dash", "weapon_primary", "weapon_skill", "time_slot_1", "boss_conversion"] or not Catalog.bounded_int(requirement.get("count"), 1, 100):
			return false
	if drill.task_id == "T-05":
		if not boss is TrainingBoss or not is_instance_valid(boss) or not boss.is_inside_tree() or boss.target != player or not is_instance_valid(boss.health) or boss.get_node_or_null("HealthComponent") != boss.health or str(boss.health.irreversible_run_id()) != str(identity.run_id) or boss.training_binding_identity().is_empty() or boss.training_binding_identity().run_id != str(identity.run_id):
			return false
		_boss = weakref(boss)
		_boss_health = weakref(boss.health)
		_boss_parent = weakref(boss.get_parent())
		_boss_identity = boss.training_binding_identity()
	elif boss != null:
		return false
	_player = weakref(player)
	_world = weakref(world)
	_identity = identity.duplicate(true)
	_config = config.duplicate(true)
	_drill = drill.duplicate(true)
	_last_frame = int(native.frame)
	_last_position = player.global_position
	_callback = Callable(self, "_on_committed_frame")
	player.authoritative_frame_committed.connect(_callback)
	return true


func task_id() -> String:
	return str(_drill.get("task_id", ""))


func is_live_binding() -> bool:
	return not native_checkpoint().is_empty()


func native_checkpoint() -> Dictionary:
	if _retired or _player == null or _world == null:
		return {}
	var player: Node = _player.get_ref()
	var world: Node = _world.get_ref()
	if not is_instance_valid(player) or not is_instance_valid(world) or not player.is_inside_tree() or not world.is_inside_tree() or player.world_payload_authority != world or player.get_node_or_null("WorldPayloadAuthority") != world or world.get_parent() != player or player.full_player_replay_identity() != _identity or player.loadout_runtime.run_seed() != int(_config.seed):
		return {}
	var native: Dictionary = player.full_player_replay_snapshot()
	if not native.is_empty() and int(native.frame) < _last_frame:
		_retired = true
		return {}
	if native.is_empty() or not Replay.validate_full_player_snapshot(native, _identity).ok:
		return {}
	var checkpoint := {"player_id": player.get_instance_id(), "world_id": world.get_instance_id(), "native": native}
	if _boss != null:
		var boss: Node = _boss.get_ref()
		var boss_health: Node = _boss_health.get_ref()
		var boss_parent: Node = _boss_parent.get_ref()
		if not is_instance_valid(boss) or not is_instance_valid(boss_health) or not is_instance_valid(boss_parent) or not boss_health.is_alive() or not boss.is_inside_tree() or boss.get_parent() != boss_parent or boss.health != boss_health or boss.get_node_or_null("HealthComponent") != boss_health or boss.target != player or boss.training_binding_identity() != _boss_identity or str(boss_health.irreversible_run_id()) != str(_identity.run_id):
			return {}
		checkpoint.boss_id = boss.get_instance_id()
		checkpoint.boss_health_id = boss_health.get_instance_id()
		checkpoint.boss = boss.training_binding_snapshot()
	return checkpoint


func snapshot() -> Dictionary:
	return {"task_id": task_id(), "seed": _config.get("seed", 0), "session_sequence": _config.get("session_sequence", 0), "runtime_frame": _last_frame, "counts": _counts.duplicate(true), "pending_count": _pending.size(), "retired": _retired}


func pending_observations() -> Array:
	var result: Array = []
	for row: Dictionary in _pending:
		result.append(row.receipt.duplicate(true))
	return result


func prepared_observation(profile: Dictionary) -> Dictionary:
	var launch: Variant = profile.get("active_launch_receipt")
	if _publishing or not launch is Dictionary or not launch.is_empty() or not is_live_binding() or _pending.is_empty():
		return Candidate.failure(&"TRAINING_OBSERVATION_UNAVAILABLE")
	return Candidate.success((_pending[0] as Dictionary).duplicate(true))


func can_confirm_saved(receipt: Dictionary, seal: Dictionary) -> bool:
	return not _publishing and is_live_binding() and not _pending.is_empty() and _pending[0].receipt == receipt and _pending[0].seal == seal


func confirm_saved(receipt: Dictionary, seal: Dictionary) -> Dictionary:
	if not can_confirm_saved(receipt, seal):
		return Candidate.failure(&"NATIVE_PUBLICATION_PENDING")
	_pending.pop_front()
	_publishing = true
	observation_saved.emit(receipt.duplicate(true))
	_publishing = false
	return Candidate.success() if is_live_binding() else Candidate.failure(&"NATIVE_PUBLICATION_PENDING")


func detach() -> void:
	var player: Node = _player.get_ref() if _player != null else null
	if is_instance_valid(player) and player.authoritative_frame_committed.is_connected(_callback):
		player.authoritative_frame_committed.disconnect(_callback)
	_pending.clear()
	_player = null
	_world = null
	_boss = null
	_boss_health = null
	_boss_parent = null
	_retired = true


func _on_committed_frame(frame: int) -> void:
	if _publishing or not is_live_binding():
		return
	var player: Node2D = _player.get_ref()
	var intents: Dictionary = player.authoritative_frame_intents(frame)
	var arbitration: Dictionary = player.priority_arbitration_snapshot()
	if intents.is_empty() or int(arbitration.frame) != frame or frame == _last_frame:
		return
	if frame != _last_frame + 1:
		_retired = true
		return
	var moved := player.global_position.distance_squared_to(_last_position) > 0.000001
	_last_frame = frame
	_last_position = player.global_position
	if player.get_tree().paused or player.health.dead:
		return
	var actions: Array = []
	var movement: Vector2 = intents.get("movement", Vector2.ZERO)
	if moved and movement.length_squared() > 0.000001 and player.action_state.current_state != ActionState.State.DASH:
		actions.append("move")
	var accepted: Dictionary = arbitration.accepted
	var action := str(accepted.get("id", ""))
	var edge := str(accepted.get("edge", ""))
	var primary_committed: bool = action == "weapon_primary" and edge in ["pressed", "released"] and player.weapon_action_coordinator.phase_name() != &"HOLD"
	if primary_committed or edge == "pressed" and action in ["dash", "weapon_skill", "time_slot_1"]:
		actions.append(action)
	if edge == "pressed" and action in ["time_slot_1", "time_slot_2"] and _converted_boss(player, frame, action):
		actions.append("boss_conversion")
	for id: String in actions:
		var requirement: Dictionary = {}
		for row: Dictionary in _drill.receipt_requirements:
			if row.action_id == id:
				requirement = row
		if requirement.is_empty():
			continue
		if int(_counts.get(id, 0)) >= int(requirement.count):
			continue
		if _pending.size() >= MAX_PENDING or _next_action >= Catalog.MAX_VALUE:
			_retired = true
			return
		_counts[id] = mini(int(_counts.get(id, 0)) + 1, int(requirement.count))
		var receipt := {"run_id": "", "session_sequence": int(_config.session_sequence), "action_sequence": _next_action, "action_id": id, "context_id": "training_drill", "trigger_ids": []}
		var seal := {"owner_id": get_instance_id(), "player_id": player.get_instance_id(), "world_id": (_world.get_ref() as Node).get_instance_id(), "frame": frame, "generation": int(_identity.owner_character_generation), "receipt_digest": JSON.stringify(receipt, "", true, true).sha256_text()}
		_pending.append({"receipt": receipt, "seal": seal})
		_next_action += 1


func _converted_boss(player: Node, frame: int, action: String) -> bool:
	var slot := 0 if action == "time_slot_1" else 1
	if _boss == null or player.loadout_runtime.time_ability_ids()[slot] != &"stop":
		return false
	var boss: Node = _boss.get_ref()
	if not is_instance_valid(boss) or not boss.health.is_alive():
		return false
	var time: Dictionary = player.time_manager.replay_snapshot()
	var source := StringName(str(time.stop_source_id))
	var fact: Dictionary = boss.training_conversion_fact(source)
	var targets: Array = player.time_manager.get("_time_stop_targets")
	return time.stop_active and int(time.stop_source_sequence) > 0 and source != &"" and targets.has(boss) and boss.get("_time_stop_sources").has(source) and not fact.is_empty() and int(fact.frame) == frame and fact.run_id == _identity.run_id and int(fact.player_id) == player.get_instance_id() and int(fact.boss_id) == boss.get_instance_id() and fact.before.phase in ["WINDUP", "RECOVERY"] and fact.before.action == fact.after.action and fact.before.phase == fact.after.phase and fact.after.exposed and float(fact.after.remaining) > float(fact.before.remaining) and boss.get_boss_ui_snapshot() == fact.after
