class_name TutorialNativeAdapter
extends RefCounted

signal observation_saved(receipt: Dictionary)

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Content := preload("res://scripts/onboarding/tutorial_catalog.gd")
const Progress := preload("res://scripts/onboarding/tutorial_progress.gd")
const Candidate := preload("res://scripts/progression/profile_command_candidate.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const Run := preload("res://scripts/application/run_state.gd")
const Phase := preload("res://scripts/application/run_phase.gd")
const Player := preload("res://scripts/player/player_controller.gd")
const ActionState := preload("res://scripts/player/player_action_state.gd")
const MAX_PENDING := 64
const ACTIVE_PHASES := [Phase.Value.ROOM_ACTIVE, Phase.Value.COMBAT_ACTIVE, Phase.Value.BOSS_ACTIVE]

var _run: RefCounted
var _player: WeakRef
var _launch: Dictionary = {}
var _identity: Dictionary = {}
var _projection: Dictionary = {}
var _pending: Array = []
var _last_frame := 0
var _next_action_sequence := 1
var _last_position := Vector2.ZERO
var _below_half := false
var _first_entry := false
var _retired := false
var _publishing := false
var _callback: Callable


func bind_normal_run(profile: Dictionary, run: RefCounted, player: Node, tutorial_content: RefCounted = null) -> Dictionary:
	if _retired or _publishing or _run != null or not run is Run or not is_instance_valid(player) or not player is Player or not player.is_inside_tree() or not player.has_signal("authoritative_frame_committed") or not player.has_method("authoritative_frame_intents"):
		return Candidate.failure(&"TUTORIAL_BINDING_INVALID")
	var content := tutorial_content
	if content == null:
		var loaded := Factory.load_base()
		if not loaded.ok:
			return loaded
		content = Content.new()
		var entries: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/tutorial_definitions.json"))
		if not entries is Array or not content.configure(entries, loaded.context.catalog).ok:
			return Candidate.failure(&"TUTORIAL_CONTENT_INVALID")
	if not content is Content or content.meta_catalog() == null:
		return Candidate.failure(&"TUTORIAL_CONTENT_INVALID")
	var decoded := Progress.decode(profile, content)
	if not decoded.ok or profile.active_launch_receipt.is_empty():
		return Candidate.failure(&"TUTORIAL_BINDING_INVALID")
	var launch: Dictionary = profile.active_launch_receipt
	var identity: Dictionary = player.full_player_replay_identity()
	var projection_value: Variant = run.resources.get("meta_run_projection", {})
	if not projection_value is Dictionary:
		return Candidate.failure(&"TUTORIAL_BINDING_INVALID")
	var projection: Dictionary = projection_value
	if not MetaProjection.validate(projection, content.meta_catalog()):
		return Candidate.failure(&"TUTORIAL_BINDING_INVALID")
	var config: Dictionary = player.loadout_runtime.snapshot()
	if identity.is_empty() or run.run_id != launch.run_id or run.run_seed != launch.seed or projection.is_empty() or projection.get("projection_digest") != launch.projection_digest or identity.run_id != launch.run_id or identity.get("meta_projection_digest") != launch.projection_digest or identity.character_id != launch.character_id or identity.weapon_id != launch.weapon_id or identity.time_ability_ids != launch.time_abilities or config.get("milestone") not in ["LAUNCH", "EXPANSION"]:
		return Candidate.failure(&"TUTORIAL_BINDING_INVALID")
	var arbitration: Dictionary = player.priority_arbitration_snapshot()
	var watermark: Dictionary = decoded.context.watermarks.get("normal_run", {})
	if not watermark.is_empty() and watermark.session_sequence > launch.sequence:
		return Candidate.failure(&"TUTORIAL_BINDING_INVALID")
	_run = run
	_player = weakref(player)
	_launch = launch.duplicate(true)
	_identity = identity
	_projection = projection.duplicate(true)
	_last_frame = int(arbitration.frame)
	_last_position = player.global_position
	_below_half = player.health.current_hp < player.health.max_hp * 0.5
	_first_entry = not watermark.is_empty() and watermark.session_sequence == launch.sequence
	_next_action_sequence = int(watermark.action_sequence) + 1 if _first_entry else 1
	_callback = Callable(self, "_on_committed_frame")
	player.authoritative_frame_committed.connect(_callback)
	return Candidate.success()


func is_live_binding() -> bool:
	return _live_identity()


func pending_observations() -> Array:
	var result: Array = []
	for row: Dictionary in _pending:
		result.append(row.receipt.duplicate(true))
	return result


func prepared_observation(profile: Dictionary) -> Dictionary:
	if _publishing or not _live_identity() or _pending.is_empty() or profile.get("active_launch_receipt") != _launch:
		return Candidate.failure(&"NATIVE_OBSERVATION_UNAVAILABLE")
	return Candidate.success((_pending[0] as Dictionary).duplicate(true))


func can_confirm_saved(receipt: Dictionary, seal: Dictionary) -> bool:
	return not _publishing and _live_identity() and not _pending.is_empty() and _pending[0].receipt == receipt and _pending[0].seal == seal


func confirm_saved(receipt: Dictionary, seal: Dictionary) -> Dictionary:
	if not can_confirm_saved(receipt, seal):
		return Candidate.failure(&"NATIVE_PUBLICATION_PENDING")
	_pending.pop_front()
	_publishing = true
	observation_saved.emit(receipt.duplicate(true))
	_publishing = false
	if not _live_identity():
		return Candidate.failure(&"NATIVE_PUBLICATION_PENDING", {"published": true, "receipt": receipt.duplicate(true)})
	return Candidate.success()


func detach() -> void:
	if _player != null:
		var player: Node = _player.get_ref()
		if is_instance_valid(player) and player.authoritative_frame_committed.is_connected(_callback):
			player.authoritative_frame_committed.disconnect(_callback)
	_pending.clear()
	_run = null
	_player = null
	_launch.clear()
	_identity.clear()
	_projection.clear()
	_retired = true


func _on_committed_frame(frame: int) -> void:
	if _publishing or not _live_identity():
		return
	var player: Node2D = _player.get_ref()
	var intents: Dictionary = player.authoritative_frame_intents(frame)
	if intents.is_empty():
		return
	var arbitration: Dictionary = player.priority_arbitration_snapshot()
	if int(arbitration.frame) != frame:
		return
	if frame == _last_frame:
		return
	if frame != _last_frame + 1:
		_retired = true
		return
	var position: Vector2 = player.global_position
	var moved := position.distance_squared_to(_last_position) > 0.000001
	_last_frame = frame
	_last_position = position
	var below_half: bool = player.health.current_hp < player.health.max_hp * 0.5
	var became_low := below_half and not _below_half
	_below_half = below_half
	if _run.suspended or _run.phase not in ACTIVE_PHASES or player.get_tree().paused or player.health.dead:
		return
	var actions: Array = []
	var movement: Vector2 = intents.get("movement", Vector2.ZERO)
	if moved and movement.length_squared() > 0.000001 and player.action_state.current_state != ActionState.State.DASH:
		actions.append("move")
	var accepted: Dictionary = arbitration.accepted
	var action_id := str(accepted.get("id", ""))
	if accepted.get("edge") == "pressed" and action_id in ["dash", "weapon_primary", "weapon_skill", "time_slot_1"]:
		actions.append(action_id)
	var triggers: Array = []
	if not _first_entry:
		triggers.append("first_dungeon_entry")
	if became_low:
		triggers.append("health_below_half")
	if actions.is_empty() and not triggers.is_empty():
		actions.append("")
	if _pending.size() + actions.size() > MAX_PENDING or _next_action_sequence > Catalog.MAX_VALUE - actions.size():
		_retired = true
		return
	for index: int in range(actions.size()):
		var receipt := {"run_id": _launch.run_id, "session_sequence": int(_launch.sequence), "action_sequence": _next_action_sequence, "action_id": actions[index], "context_id": "normal_run", "trigger_ids": triggers.duplicate() if index == 0 else []}
		var seal := {"owner_id": get_instance_id(), "frame": frame, "generation": int(_identity.owner_character_generation), "receipt_digest": JSON.stringify(receipt, "", true, true).sha256_text()}
		_pending.append({"receipt": receipt, "seal": seal})
		_next_action_sequence += 1
	if not actions.is_empty():
		_first_entry = true


func _live_identity() -> bool:
	if _retired or _run == null or _player == null:
		return false
	var player: Node = _player.get_ref()
	var projection: Variant = _run.resources.get("meta_run_projection", {})
	if not is_instance_valid(player) or not player.is_inside_tree() or _run.run_id != _launch.run_id or _run.run_seed != _launch.seed or projection != _projection:
		return false
	return player.full_player_replay_identity() == _identity
