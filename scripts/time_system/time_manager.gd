class_name TimeManager
extends Node

const SceneScope := preload("res://scripts/player/player_scene_scope.gd")

const TimeRiftScene := preload("res://scenes/time/time_rift.tscn")
const TimeAbilityIdsScript := preload("res://scripts/time_system/time_ability_ids.gd")
const TimeActionTransactionScript := preload(
	"res://scripts/time_system/time_action_transaction.gd"
)

const GAMEPLAY_FRAMES_PER_SECOND := 60
const FIXED_FRAME_SECONDS := 1.0 / float(GAMEPLAY_FRAMES_PER_SECOND)
const ENERGY_FIXED_POINT_SCALE := 1_000_000
const FRAME_SIGNAL_TRANSACTION_SCHEMA_VERSION := 1
const FRAME_SIGNAL_PUBLICATION_SCHEMA_VERSION := 1
const REWIND_WEAPON_WINDOW_DURATION_FRAMES := 2 * GAMEPLAY_FRAMES_PER_SECOND
const REWIND_WEAPON_WINDOW_DURATION := (
	float(REWIND_WEAPON_WINDOW_DURATION_FRAMES) / float(GAMEPLAY_FRAMES_PER_SECOND)
)
const COOLDOWN_SKILL_IDS: Array[StringName] = [
	&"time_stop",
	&"time_rewind",
	&"time_rift",
	&"time_accelerate",
]
const TIME_REPLAY_SNAPSHOT_SCHEMA_VERSION := 1
const TIME_REPLAY_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"runtime_frame",
	"energy_state",
	"energy_regen_remainder",
	"cooldowns",
	"stop_active",
	"stop_source_sequence",
	"stop_source_id",
	"stop_remaining",
	"stop_extension_frames",
	"stop_extension_tokens",
	"accelerate_active",
	"accelerate_token",
	"accelerate_remaining",
	"accelerate_multiplier",
	"accelerate_publish_lifecycle",
	"rewind_window_remaining",
	"rewind_window_generation",
	"rewind_window_claimed",
	"rift_source_sequence",
	"active_rifts",
]
const MAX_WEAPON_STOP_EXTENSION_FRAMES := 60
const WEAPON_REPLAY_SNAPSHOT_SCHEMA_VERSION := 3
const WEAPON_REPLAY_SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"time_energy_state",
	"energy_regen_remainder",
	"stop_active",
	"stop_source_sequence",
	"stop_source_id",
	"stop_remaining",
	"stop_extension_frames",
	"stop_extension_tokens",
	"rewind_window_remaining",
	"rewind_window_generation",
	"rewind_window_claimed",
]
const GAMEPLAY_REWIND_TRANSACTION_FIELDS: Array[String] = [
	"energy",
	"max_energy",
	"cooldowns",
	"resource_revision",
	"rewind_window_remaining",
	"rewind_window_generation",
	"rewind_window_claimed",
	"self_damage_generation",
	"next_self_damage_token",
]
const REWARD_EFFECT_SNAPSHOT_FIELDS: Array[String] = [
	"energy",
	"max_energy",
	"resource_revision",
	"time_stop_duration_bonus",
	"time_stop_cost_multiplier",
	"time_stop_weakpoint_damage_bonus",
	"time_stop_weakpoint_duration",
	"time_stop_self_damage",
	"rewind_cost_multiplier",
	"rewind_heal",
	"rewind_echo_enabled",
	"rewind_path_hit_multiplier",
	"rewind_self_damage",
	"time_rift_cost_multiplier",
	"time_rift_duration_bonus",
	"time_rift_radius_bonus",
	"time_rift_slow_bonus",
	"time_accelerate_cost_multiplier",
	"time_accelerate_duration_bonus",
	"time_accelerate_multiplier_bonus",
	"low_energy_regen_multiplier",
	"low_energy_threshold",
]

signal energy_changed(current: float, maximum: float)
signal cooldown_changed(skill_id: StringName, remaining: float)
signal rewind_committed(transaction: Dictionary)

@export var max_energy: float = 100.0
@export var energy_regen: float = 2.0
@export var time_stop_cost: float = 35.0
@export var time_stop_cooldown: float = 12.0
@export var time_stop_duration: float = 3.0
@export var rewind_cost: float = 45.0
@export var rewind_cooldown: float = 15.0
@export var time_rift_cost: float = 30.0
@export var time_rift_cooldown: float = 10.0
@export var time_rift_duration: float = 4.0
@export var time_rift_radius: float = 92.0
@export var time_rift_slow_multiplier: float = 0.45
@export var time_accelerate_cost: float = 35.0
@export var time_accelerate_cooldown: float = 14.0
@export var time_accelerate_duration: float = 3.0
@export var time_accelerate_multiplier: float = 1.35

@onready var world_payload_authority: Node = get_parent().get_node_or_null(
	"WorldPayloadAuthority"
)

var energy: float = 100.0
var time_stop_duration_bonus: float = 0.0
var time_stop_cost_multiplier: float = 1.0
var time_stop_weakpoint_damage_bonus: float = 0.0
var time_stop_weakpoint_duration: float = 0.0
var rewind_cost_multiplier: float = 1.0
var rewind_heal: float = 0.0
var rewind_echo_enabled: bool = false
var rewind_path_hit_multiplier: float = 0.0
var time_rift_cost_multiplier: float = 1.0
var time_rift_duration_bonus: float = 0.0
var time_rift_radius_bonus: float = 0.0
var time_rift_slow_bonus: float = 0.0
var time_accelerate_cost_multiplier: float = 1.0
var time_accelerate_duration_bonus: float = 0.0
var time_accelerate_multiplier_bonus: float = 0.0
var low_energy_regen_multiplier: float = 1.0
var low_energy_threshold: float = 30.0
var time_stop_self_damage: float = 0.0
var rewind_self_damage: float = 0.0
var _floor_rule_cost_multiplier: float = 1.0
var _event_energy_regen_multiplier: float = 1.0
var _cooldowns: Dictionary = {
	&"time_stop": 0.0,
	&"time_rewind": 0.0,
	&"time_rift": 0.0,
	&"time_accelerate": 0.0,
}
var _cooldown_frames: Dictionary = {
	&"time_stop": 0,
	&"time_rewind": 0,
	&"time_rift": 0,
	&"time_accelerate": 0,
}
var _active_rifts: Array[Node] = []
var _active_rift_generations: Dictionary = {}
var _time_rift_source_sequence: int = 0
var _time_stop_remaining: float = 0.0
var _time_stop_remaining_frames: int = 0
var _time_stop_active: bool = false
var _time_stop_source_sequence: int = 0
var _time_stop_source_id: StringName = &""
var _time_stop_targets: Array[Node] = []
var _weapon_stop_extension_frames: int = 0
var _weapon_stop_extension_tokens: Dictionary = {}
var _time_accelerate_remaining: float = 0.0
var _time_accelerate_remaining_frames: int = 0
var _time_accelerate_active: bool = false
var _time_accelerate_token: int = 0
var _time_accelerate_publish_lifecycle: bool = false
var _time_accelerate_multiplier_active: float = 1.0
var _rewind_weapon_window_remaining: float = 0.0
var _rewind_weapon_window_remaining_frames: int = 0
var _rewind_weapon_window_generation: int = 0
var _rewind_weapon_window_claimed: bool = false
var _resource_revision: int = 1
var _weapon_replay_restore_transaction_active: bool = false
var _weapon_replay_restore_transaction_token: int = 0
var _next_weapon_replay_restore_transaction_token: int = 1
var _weapon_replay_restore_transaction_before: Dictionary = {}
var _irreversible_self_damage_generation: int = 1
var _next_irreversible_self_damage_token: int = 1
var _last_runtime_frame: int = 0
var _energy_regen_remainder: int = 0
var _time_action_transaction: RefCounted = TimeActionTransactionScript.new()
var _prepared_time_action_settlement: Dictionary = {}
var _prepared_time_action_ticket_fingerprint: String = ""
var _next_frame_signal_transaction_ticket_id: int = 1
var _active_frame_signal_transaction: Dictionary = {}
var _next_frame_signal_publication_id: int = 1
var _prepared_frame_signal_publication: Dictionary = {}
var _finalized_frame_signal_publication: Dictionary = {}
var _frame_signal_publication_in_progress: bool = false
var _post_publication_frame_signal_events: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	if world_payload_authority != null:
		if not world_payload_authority.register_factory(
			&"time_rift",
			Callable(self, "_spawn_time_rift_payload")
		):
			push_error("WorldPayloadAuthority rejected the Time Rift factory")
	energy = max_energy
	_publish_energy_changed(energy, max_energy)


func _process(_delta: float) -> void:
	# Gameplay time advances only through advance_frame(). This callback remains
	# available for presentation-only projection and must stay gameplay-pure.
	pass


func set_floor_rule_cost_multiplier(value: float) -> bool:
	if not is_finite(value) or value <= 0.0:
		return false
	_floor_rule_cost_multiplier = value
	return true


func floor_rule_cost_multiplier() -> float:
	return _floor_rule_cost_multiplier


func set_event_energy_regen_multiplier(value: float) -> bool:
	if not is_finite(value) or value <= 0.0:
		return false
	_event_energy_regen_multiplier = value
	return true


func event_energy_regen_multiplier() -> float:
	return _event_energy_regen_multiplier


func _floor_rule_adjusted_cost(base_cost: float, reward_multiplier: float) -> float:
	return base_cost * reward_multiplier * _floor_rule_cost_multiplier


static func _seconds_to_authoritative_frames(seconds: float) -> int:
	if not is_finite(seconds) or seconds <= 0.0:
		return 0
	return maxi(1, roundi(seconds * float(GAMEPLAY_FRAMES_PER_SECOND)))


static func _frames_to_seconds(frame_count: int) -> float:
	return float(maxi(0, frame_count)) / float(GAMEPLAY_FRAMES_PER_SECOND)


func _set_time_stop_remaining_frames(frame_count: int) -> void:
	_time_stop_remaining_frames = maxi(0, frame_count)
	_time_stop_remaining = _frames_to_seconds(_time_stop_remaining_frames)


func _set_time_accelerate_remaining_frames(frame_count: int) -> void:
	_time_accelerate_remaining_frames = maxi(0, frame_count)
	_time_accelerate_remaining = _frames_to_seconds(_time_accelerate_remaining_frames)


func _set_rewind_window_remaining_frames(frame_count: int) -> void:
	_rewind_weapon_window_remaining_frames = maxi(0, frame_count)
	_rewind_weapon_window_remaining = _frames_to_seconds(
		_rewind_weapon_window_remaining_frames
	)


func _install_cooldowns_from_seconds(value: Dictionary) -> bool:
	if value.size() != COOLDOWN_SKILL_IDS.size():
		return false
	var installed_seconds: Dictionary = {}
	var installed_frames: Dictionary = {}
	for skill_id: StringName in COOLDOWN_SKILL_IDS:
		var seconds_value: Variant = value.get(skill_id)
		if (
			typeof(seconds_value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(seconds_value))
			or float(seconds_value) < 0.0
		):
			return false
		var frame_count := _seconds_to_authoritative_frames(float(seconds_value))
		installed_frames[skill_id] = frame_count
		installed_seconds[skill_id] = _frames_to_seconds(frame_count)
	_cooldown_frames = installed_frames
	_cooldowns = installed_seconds
	return true


func _refresh_cooldown_seconds_projection() -> bool:
	var projected_seconds: Dictionary = {}
	for skill_id: StringName in COOLDOWN_SKILL_IDS:
		var frame_value: Variant = _cooldown_frames.get(skill_id)
		if (
			typeof(frame_value) != TYPE_INT
			or int(frame_value) < 0
		):
			return false
		projected_seconds[skill_id] = _frames_to_seconds(int(frame_value))
	_cooldowns = projected_seconds
	return true


func _set_cooldown_seconds(skill_id: StringName, seconds: float) -> bool:
	if not COOLDOWN_SKILL_IDS.has(skill_id) or not is_finite(seconds) or seconds < 0.0:
		return false
	var frame_count := _seconds_to_authoritative_frames(seconds)
	_cooldown_frames[skill_id] = frame_count
	_cooldowns[skill_id] = _frames_to_seconds(frame_count)
	return true


func _set_cooldown_frames(skill_id: StringName, frame_count: int) -> bool:
	if not COOLDOWN_SKILL_IDS.has(skill_id) or frame_count < 0:
		return false
	_cooldown_frames[skill_id] = frame_count
	_cooldowns[skill_id] = _frames_to_seconds(frame_count)
	return true


func begin_frame_signal_transaction(runtime_frame: int) -> Dictionary:
	if (
		not _active_frame_signal_transaction.is_empty()
		or not _prepared_frame_signal_publication.is_empty()
		or not _finalized_frame_signal_publication.is_empty()
		or _frame_signal_publication_in_progress
		or runtime_frame <= 0
		or runtime_frame != _last_runtime_frame + 1
	):
		return {}
	var ticket := {
		"schema_version": FRAME_SIGNAL_TRANSACTION_SCHEMA_VERSION,
		"ticket_id": _next_frame_signal_transaction_ticket_id,
		"owner_instance_id": get_instance_id(),
		"runtime_frame": runtime_frame,
	}
	_next_frame_signal_transaction_ticket_id += 1
	ticket["fingerprint"] = _frame_signal_transaction_ticket_fingerprint(ticket)
	_active_frame_signal_transaction = {
		"ticket": ticket.duplicate(true),
		"events": [],
	}
	return ticket.duplicate(true)


func can_commit_frame_signal_transaction(ticket: Dictionary) -> bool:
	return (
		_frame_signal_transaction_ticket_matches(ticket)
		and _finalized_frame_signal_publication.is_empty()
		and not _frame_signal_publication_in_progress
		and int(ticket.get("runtime_frame", -1)) == _last_runtime_frame
	)


func prepare_frame_signal_publication(ticket: Dictionary) -> Dictionary:
	if not can_commit_frame_signal_transaction(ticket):
		return {}
	if not _prepared_frame_signal_publication.is_empty():
		if ticket == _prepared_frame_signal_publication.get("transaction_ticket", {}):
			return _prepared_frame_signal_publication.duplicate(true)
		return {}
	var publication := {
		"schema_version": FRAME_SIGNAL_PUBLICATION_SCHEMA_VERSION,
		"publication_id": _next_frame_signal_publication_id,
		"owner_instance_id": get_instance_id(),
		"runtime_frame": _last_runtime_frame,
		"transaction_ticket": ticket.duplicate(true),
		"events": (
			_active_frame_signal_transaction.get("events", []) as Array
		).duplicate(true),
	}
	_next_frame_signal_publication_id += 1
	publication["fingerprint"] = _frame_signal_publication_fingerprint(publication)
	_prepared_frame_signal_publication = publication.duplicate(true)
	return publication.duplicate(true)


func finalize_frame_signal_publication(publication: Dictionary) -> bool:
	var transaction_ticket_value: Variant = publication.get("transaction_ticket")
	if not transaction_ticket_value is Dictionary:
		return false
	var transaction_ticket := transaction_ticket_value as Dictionary
	if (
		not _frame_signal_publication_matches(publication)
		or not _frame_signal_transaction_ticket_matches(transaction_ticket)
		or int(transaction_ticket.get("runtime_frame", -1)) != _last_runtime_frame
		or not _finalized_frame_signal_publication.is_empty()
		or _frame_signal_publication_in_progress
		or _active_frame_signal_transaction.get("events", []) != publication.get("events", [])
	):
		return false
	_active_frame_signal_transaction.clear()
	_finalized_frame_signal_publication = _prepared_frame_signal_publication.duplicate(true)
	_prepared_frame_signal_publication.clear()
	return true


func discard_finalized_frame_signal_publication(publication: Dictionary) -> bool:
	if (
		_frame_signal_publication_in_progress
		or not _finalized_frame_signal_publication_matches(publication)
	):
		return false
	_finalized_frame_signal_publication.clear()
	return true


func publish_prepared_frame_signals() -> void:
	if _finalized_frame_signal_publication.is_empty() or _frame_signal_publication_in_progress:
		return
	var events: Array = (
		_finalized_frame_signal_publication.get("events", []) as Array
	).duplicate(true)
	_finalized_frame_signal_publication.clear()
	_frame_signal_publication_in_progress = true
	_flush_frame_signal_events(events)
	while not _post_publication_frame_signal_events.is_empty():
		var deferred: Array = _post_publication_frame_signal_events.duplicate(true)
		_post_publication_frame_signal_events.clear()
		_flush_frame_signal_events(deferred)
	_frame_signal_publication_in_progress = false


func commit_frame_signal_transaction(ticket: Dictionary) -> bool:
	var publication := prepare_frame_signal_publication(ticket)
	if publication.is_empty() or not finalize_frame_signal_publication(publication):
		return false
	publish_prepared_frame_signals()
	return true


func rollback_frame_signal_transaction(ticket: Dictionary) -> bool:
	if not _frame_signal_transaction_ticket_matches(ticket):
		return false
	_active_frame_signal_transaction.clear()
	_prepared_frame_signal_publication.clear()
	return true


func _frame_signal_publication_matches(publication: Dictionary) -> bool:
	if (
		_prepared_frame_signal_publication.is_empty()
		or publication.size() != 7
		or typeof(publication.get("schema_version")) != TYPE_INT
		or int(publication.get("schema_version", -1))
		!= FRAME_SIGNAL_PUBLICATION_SCHEMA_VERSION
		or typeof(publication.get("publication_id")) != TYPE_INT
		or int(publication.get("publication_id", 0)) <= 0
		or typeof(publication.get("owner_instance_id")) != TYPE_INT
		or int(publication.get("owner_instance_id", 0)) != get_instance_id()
		or typeof(publication.get("runtime_frame")) != TYPE_INT
		or int(publication.get("runtime_frame", -1)) != _last_runtime_frame
		or not publication.get("transaction_ticket") is Dictionary
		or not publication.get("events") is Array
		or typeof(publication.get("fingerprint")) != TYPE_STRING
		or str(publication.get("fingerprint", ""))
		!= _frame_signal_publication_fingerprint(publication)
	):
		return false
	return publication == _prepared_frame_signal_publication


func _frame_signal_publication_fingerprint(publication: Dictionary) -> String:
	var signed := publication.duplicate(true)
	signed.erase("fingerprint")
	return var_to_bytes(signed).hex_encode().sha256_text()


func _finalized_frame_signal_publication_matches(publication: Dictionary) -> bool:
	if (
		_finalized_frame_signal_publication.is_empty()
		or publication.size() != 7
		or typeof(publication.get("schema_version")) != TYPE_INT
		or int(publication.get("schema_version", -1))
		!= FRAME_SIGNAL_PUBLICATION_SCHEMA_VERSION
		or typeof(publication.get("publication_id")) != TYPE_INT
		or int(publication.get("publication_id", 0)) <= 0
		or typeof(publication.get("owner_instance_id")) != TYPE_INT
		or int(publication.get("owner_instance_id", 0)) != get_instance_id()
		or typeof(publication.get("runtime_frame")) != TYPE_INT
		or int(publication.get("runtime_frame", -1)) <= 0
		or not publication.get("transaction_ticket") is Dictionary
		or not publication.get("events") is Array
		or typeof(publication.get("fingerprint")) != TYPE_STRING
		or str(publication.get("fingerprint", ""))
		!= _frame_signal_publication_fingerprint(publication)
	):
		return false
	var transaction_ticket := publication.get("transaction_ticket") as Dictionary
	if not _frame_signal_transaction_ticket_is_authentic(
		transaction_ticket,
		int(publication.get("runtime_frame", -1))
	):
		return false
	return publication == _finalized_frame_signal_publication


func _frame_signal_transaction_ticket_matches(ticket: Dictionary) -> bool:
	if (
		_active_frame_signal_transaction.is_empty()
		or not _active_frame_signal_transaction.get("ticket") is Dictionary
	):
		return false
	var active_ticket := _active_frame_signal_transaction.get("ticket") as Dictionary
	return (
		_frame_signal_transaction_ticket_is_authentic(
			ticket,
			int(active_ticket.get("runtime_frame", -1))
		)
		and ticket == active_ticket
	)


func _frame_signal_transaction_ticket_is_authentic(
	ticket: Dictionary,
	expected_runtime_frame: int
) -> bool:
	return (
		ticket.size() == 5
		and typeof(ticket.get("schema_version")) == TYPE_INT
		and int(ticket.get("schema_version", -1))
		== FRAME_SIGNAL_TRANSACTION_SCHEMA_VERSION
		and typeof(ticket.get("ticket_id")) == TYPE_INT
		and int(ticket.get("ticket_id", 0)) > 0
		and typeof(ticket.get("owner_instance_id")) == TYPE_INT
		and int(ticket.get("owner_instance_id", 0)) == get_instance_id()
		and typeof(ticket.get("runtime_frame")) == TYPE_INT
		and int(ticket.get("runtime_frame", -1)) == expected_runtime_frame
		and expected_runtime_frame > 0
		and typeof(ticket.get("fingerprint")) == TYPE_STRING
		and str(ticket.get("fingerprint", ""))
		== _frame_signal_transaction_ticket_fingerprint(ticket)
	)


func _frame_signal_transaction_ticket_fingerprint(ticket: Dictionary) -> String:
	var signed := ticket.duplicate(true)
	signed.erase("fingerprint")
	return var_to_bytes(signed).hex_encode().sha256_text()


func _queue_or_flush_frame_signal_event(kind: StringName, arguments: Array) -> void:
	var event := {
		"kind": kind,
		"arguments": arguments.duplicate(true),
	}
	if _active_frame_signal_transaction.is_empty():
		if not _finalized_frame_signal_publication.is_empty() or _frame_signal_publication_in_progress:
			_post_publication_frame_signal_events.append(event)
			return
		_flush_frame_signal_event(event)
		return
	var events := _active_frame_signal_transaction.get("events", []) as Array
	events.append(event)
	_active_frame_signal_transaction["events"] = events


func _flush_frame_signal_event(event: Dictionary) -> void:
	var kind := StringName(str(event.get("kind", "")))
	var arguments := event.get("arguments", []) as Array
	match kind:
		&"energy_changed":
			energy_changed.emit(float(arguments[0]), float(arguments[1]))
		&"cooldown_changed":
			cooldown_changed.emit(
				StringName(str(arguments[0])),
				float(arguments[1])
			)
		&"rewind_committed":
			rewind_committed.emit((arguments[0] as Dictionary).duplicate(true))
		&"time_skill_started":
			SceneScope.event_bus(self).time_skill_started.emit(
				StringName(str(arguments[0])),
				(arguments[1] as Dictionary).duplicate(true)
			)
		&"time_skill_ended":
			SceneScope.event_bus(self).time_skill_ended.emit(
				StringName(str(arguments[0])),
				(arguments[1] as Dictionary).duplicate(true)
			)
		&"time_skill_committed":
			SceneScope.event_bus(self).time_skill_committed.emit(
				StringName(str(arguments[0])),
				int(arguments[1]),
				int(arguments[2]),
				int(arguments[3]),
				StringName(str(arguments[4])),
				(arguments[5] as Dictionary).duplicate(true)
			)


func _flush_frame_signal_events(events: Array) -> void:
	for event_value: Variant in events:
		if event_value is Dictionary:
			_flush_frame_signal_event(event_value as Dictionary)


func _publish_energy_changed(current: float, maximum: float) -> void:
	_queue_or_flush_frame_signal_event(
		&"energy_changed",
		[current, maximum]
	)


func _publish_cooldown_changed(skill_id: StringName, remaining: float) -> void:
	_queue_or_flush_frame_signal_event(
		&"cooldown_changed",
		[skill_id, remaining]
	)


func _publish_rewind_committed(transaction: Dictionary) -> void:
	_queue_or_flush_frame_signal_event(
		&"rewind_committed",
		[transaction.duplicate(true)]
	)


func _publish_time_skill_started(skill_id: StringName, context: Dictionary) -> void:
	_queue_or_flush_frame_signal_event(
		&"time_skill_started",
		[skill_id, context.duplicate(true)]
	)


func _publish_time_skill_ended(skill_id: StringName, context: Dictionary) -> void:
	_queue_or_flush_frame_signal_event(
		&"time_skill_ended",
		[skill_id, context.duplicate(true)]
	)


func _publish_time_skill_committed(
	ability_id: StringName,
	token: int,
	generation: int,
	frame: int,
	run_id: StringName,
	context: Dictionary
) -> void:
	_queue_or_flush_frame_signal_event(
		&"time_skill_committed",
		[
			ability_id,
			token,
			generation,
			frame,
			run_id,
			context.duplicate(true),
		]
	)


func advance_frame(runtime_frame: int) -> bool:
	if runtime_frame <= 0 or runtime_frame != _last_runtime_frame + 1:
		return false
	if (
		not _active_frame_signal_transaction.is_empty()
		and int((
			_active_frame_signal_transaction.get("ticket", {}) as Dictionary
		).get("runtime_frame", -1)) != runtime_frame
	):
		return false
	if not _refresh_cooldown_seconds_projection():
		return false
	_last_runtime_frame = runtime_frame
	_regen_energy_fixed_frame()
	_tick_cooldowns()
	_tick_active_effects()
	_prune_active_rifts()
	return true


func replay_snapshot() -> Dictionary:
	_refresh_cooldown_seconds_projection()
	_prune_active_rifts()
	return {
		"schema_version": TIME_REPLAY_SNAPSHOT_SCHEMA_VERSION,
		"runtime_frame": _last_runtime_frame,
		"energy_state": resource_state(&"time_energy"),
		"energy_regen_remainder": _energy_regen_remainder,
		"cooldowns": _cooldowns.duplicate(true),
		"stop_active": _time_stop_active,
		"stop_source_sequence": _time_stop_source_sequence,
		"stop_source_id": str(_time_stop_source_id),
		"stop_remaining": _time_stop_remaining,
		"stop_extension_frames": _weapon_stop_extension_frames,
		"stop_extension_tokens": _weapon_stop_extension_tokens.duplicate(true),
		"accelerate_active": _time_accelerate_active,
		"accelerate_token": _time_accelerate_token,
		"accelerate_remaining": _time_accelerate_remaining,
		"accelerate_multiplier": _time_accelerate_multiplier_active,
		"accelerate_publish_lifecycle": _time_accelerate_publish_lifecycle,
		"rewind_window_remaining": _rewind_weapon_window_remaining,
		"rewind_window_generation": _rewind_weapon_window_generation,
		"rewind_window_claimed": _rewind_weapon_window_claimed,
		"rift_source_sequence": _time_rift_source_sequence,
		"active_rifts": _active_rift_payload_descriptors(),
	}


func reward_effect_snapshot() -> Dictionary:
	return {
		"energy": energy,
		"max_energy": max_energy,
		"resource_revision": _resource_revision,
		"time_stop_duration_bonus": time_stop_duration_bonus,
		"time_stop_cost_multiplier": time_stop_cost_multiplier,
		"time_stop_weakpoint_damage_bonus": time_stop_weakpoint_damage_bonus,
		"time_stop_weakpoint_duration": time_stop_weakpoint_duration,
		"time_stop_self_damage": time_stop_self_damage,
		"rewind_cost_multiplier": rewind_cost_multiplier,
		"rewind_heal": rewind_heal,
		"rewind_echo_enabled": rewind_echo_enabled,
		"rewind_path_hit_multiplier": rewind_path_hit_multiplier,
		"rewind_self_damage": rewind_self_damage,
		"time_rift_cost_multiplier": time_rift_cost_multiplier,
		"time_rift_duration_bonus": time_rift_duration_bonus,
		"time_rift_radius_bonus": time_rift_radius_bonus,
		"time_rift_slow_bonus": time_rift_slow_bonus,
		"time_accelerate_cost_multiplier": time_accelerate_cost_multiplier,
		"time_accelerate_duration_bonus": time_accelerate_duration_bonus,
		"time_accelerate_multiplier_bonus": time_accelerate_multiplier_bonus,
		"low_energy_regen_multiplier": low_energy_regen_multiplier,
		"low_energy_threshold": low_energy_threshold,
	}


func restore_reward_effect_snapshot(value: Dictionary, publish_signal: bool = true) -> bool:
	if not can_restore_reward_effect_snapshot(value):
		return false
	var energy_changed_during_restore := (
		energy != float(value["energy"])
		or max_energy != float(value["max_energy"])
	)
	energy = float(value["energy"])
	max_energy = float(value["max_energy"])
	_resource_revision = int(value["resource_revision"])
	time_stop_duration_bonus = float(value["time_stop_duration_bonus"])
	time_stop_cost_multiplier = float(value["time_stop_cost_multiplier"])
	time_stop_weakpoint_damage_bonus = float(value["time_stop_weakpoint_damage_bonus"])
	time_stop_weakpoint_duration = float(value["time_stop_weakpoint_duration"])
	time_stop_self_damage = float(value["time_stop_self_damage"])
	rewind_cost_multiplier = float(value["rewind_cost_multiplier"])
	rewind_heal = float(value["rewind_heal"])
	rewind_echo_enabled = bool(value["rewind_echo_enabled"])
	rewind_path_hit_multiplier = float(value["rewind_path_hit_multiplier"])
	rewind_self_damage = float(value["rewind_self_damage"])
	time_rift_cost_multiplier = float(value["time_rift_cost_multiplier"])
	time_rift_duration_bonus = float(value["time_rift_duration_bonus"])
	time_rift_radius_bonus = float(value["time_rift_radius_bonus"])
	time_rift_slow_bonus = float(value["time_rift_slow_bonus"])
	time_accelerate_cost_multiplier = float(value["time_accelerate_cost_multiplier"])
	time_accelerate_duration_bonus = float(value["time_accelerate_duration_bonus"])
	time_accelerate_multiplier_bonus = float(value["time_accelerate_multiplier_bonus"])
	low_energy_regen_multiplier = float(value["low_energy_regen_multiplier"])
	low_energy_threshold = float(value["low_energy_threshold"])
	if energy_changed_during_restore and publish_signal:
		_publish_energy_changed(energy, max_energy)
	return reward_effect_snapshot() == value


func can_restore_reward_effect_snapshot(value: Dictionary) -> bool:
	if value.size() != REWARD_EFFECT_SNAPSHOT_FIELDS.size():
		return false
	for field: String in REWARD_EFFECT_SNAPSHOT_FIELDS:
		if not value.has(field):
			return false
	for field: String in REWARD_EFFECT_SNAPSHOT_FIELDS:
		if field == "rewind_echo_enabled" or field == "resource_revision":
			continue
		if typeof(value[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[field])):
			return false
	if (
		typeof(value["resource_revision"]) != TYPE_INT
		or int(value["resource_revision"]) <= 0
		or typeof(value["rewind_echo_enabled"]) != TYPE_BOOL
		or float(value["max_energy"]) <= 0.0
		or float(value["energy"]) < 0.0
		or float(value["energy"]) > float(value["max_energy"])
	):
		return false
	for field: String in REWARD_EFFECT_SNAPSHOT_FIELDS:
		if field in ["energy", "max_energy", "resource_revision", "rewind_echo_enabled"]:
			continue
		if float(value[field]) < 0.0:
			return false
	for field: String in [
		"time_stop_cost_multiplier",
		"rewind_cost_multiplier",
		"time_rift_cost_multiplier",
		"time_accelerate_cost_multiplier",
	]:
		if float(value[field]) <= 0.0:
			return false
	return true


func can_restore_replay_snapshot(value: Dictionary) -> bool:
	if value.size() != TIME_REPLAY_SNAPSHOT_FIELDS.size():
		return false
	for field: String in TIME_REPLAY_SNAPSHOT_FIELDS:
		if not value.has(field):
			return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != TIME_REPLAY_SNAPSHOT_SCHEMA_VERSION
		or typeof(value["runtime_frame"]) != TYPE_INT
		or int(value["runtime_frame"]) < 0
		or not value["energy_state"] is Dictionary
		or not can_restore_resource_state(&"time_energy", value["energy_state"] as Dictionary)
		or typeof(value["energy_regen_remainder"]) != TYPE_INT
		or int(value["energy_regen_remainder"]) < 0
		or int(value["energy_regen_remainder"]) >= GAMEPLAY_FRAMES_PER_SECOND
		or not value["cooldowns"] is Dictionary
		or typeof(value["stop_active"]) != TYPE_BOOL
		or typeof(value["stop_source_sequence"]) != TYPE_INT
		or int(value["stop_source_sequence"]) < 0
		or typeof(value["stop_source_id"]) not in [TYPE_STRING, TYPE_STRING_NAME]
		or typeof(value["stop_remaining"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["stop_remaining"]))
		or float(value["stop_remaining"]) < 0.0
		or typeof(value["stop_extension_frames"]) != TYPE_INT
		or int(value["stop_extension_frames"]) < 0
		or int(value["stop_extension_frames"]) > MAX_WEAPON_STOP_EXTENSION_FRAMES
		or not value["stop_extension_tokens"] is Dictionary
		or typeof(value["accelerate_active"]) != TYPE_BOOL
		or typeof(value["accelerate_token"]) != TYPE_INT
		or int(value["accelerate_token"]) < 0
		or typeof(value["accelerate_remaining"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["accelerate_remaining"]))
		or float(value["accelerate_remaining"]) < 0.0
		or typeof(value["accelerate_multiplier"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["accelerate_multiplier"]))
		or float(value["accelerate_multiplier"]) <= 0.0
		or typeof(value["accelerate_publish_lifecycle"]) != TYPE_BOOL
		or typeof(value["rewind_window_remaining"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["rewind_window_remaining"]))
		or float(value["rewind_window_remaining"]) < 0.0
		or typeof(value["rewind_window_generation"]) != TYPE_INT
		or int(value["rewind_window_generation"]) < 0
		or typeof(value["rewind_window_claimed"]) != TYPE_BOOL
		or typeof(value["rift_source_sequence"]) != TYPE_INT
		or int(value["rift_source_sequence"]) < 0
		or not value["active_rifts"] is Array
	):
		return false
	var cooldowns := value["cooldowns"] as Dictionary
	if cooldowns.size() != _cooldowns.size():
		return false
	for skill_id: StringName in _cooldowns.keys():
		if (
			not cooldowns.has(skill_id)
			or typeof(cooldowns[skill_id]) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(cooldowns[skill_id]))
			or float(cooldowns[skill_id]) < 0.0
		):
			return false
	var stop_active := bool(value["stop_active"])
	if stop_active != (not str(value["stop_source_id"]).is_empty()):
		return false
	if stop_active != (float(value["stop_remaining"]) > 0.0):
		return false
	var accelerate_active := bool(value["accelerate_active"])
	if accelerate_active != (float(value["accelerate_remaining"]) > 0.0):
		return false
	if accelerate_active and int(value["accelerate_token"]) <= 0:
		return false
	var rewind_remaining := float(value["rewind_window_remaining"])
	var rewind_generation := int(value["rewind_window_generation"])
	var rewind_claimed := bool(value["rewind_window_claimed"])
	if rewind_remaining > 0.0 and (rewind_generation <= 0 or rewind_claimed):
		return false
	if rewind_claimed and (rewind_generation <= 0 or not is_zero_approx(rewind_remaining)):
		return false
	return true


func restore_replay_snapshot(value: Dictionary) -> bool:
	if not can_restore_replay_snapshot(value):
		return false
	var before := replay_snapshot()
	if _install_time_replay_snapshot(value) and replay_snapshot() == value:
		return true
	_install_time_replay_snapshot(before)
	return false


func time_action_snapshot() -> Dictionary:
	var world_snapshot: Dictionary = {}
	if world_payload_authority != null and world_payload_authority.has_method("replay_snapshot"):
		var world_value: Variant = world_payload_authority.call("replay_snapshot")
		if world_value is Dictionary:
			world_snapshot = (world_value as Dictionary).duplicate(true)
	var character_participant: Dictionary = {}
	var owner_entity := get_parent()
	if owner_entity != null and owner_entity.has_method(
		"character_time_action_participant_snapshot"
	):
		var participant_value: Variant = owner_entity.call(
			"character_time_action_participant_snapshot"
		)
		if not participant_value is Dictionary or (participant_value as Dictionary).is_empty():
			return {}
		character_participant = (participant_value as Dictionary).duplicate(true)
	return {
		"time_manager": replay_snapshot(),
		"world_payloads": world_snapshot,
		"character_participant": character_participant,
	}


func prepare_time_action(
	token: int,
	generation: int,
	frame: int,
	run_id: StringName,
	ability_id: StringName,
	context: Dictionary
) -> Dictionary:
	var canonical := canonical_skill_id(ability_id)
	var owner_entity := get_parent()
	var loadout := owner_entity.get_node_or_null("PlayerLoadoutRuntime") if owner_entity != null else null
	if (
		not _prepared_time_action_settlement.is_empty()
		or canonical == &""
		or frame != _last_runtime_frame
		or owner_entity == null
		or not owner_entity.has_method("current_run_id")
		or StringName(str(owner_entity.call("current_run_id"))) != run_id
		or loadout == null
		or not loadout.has_method("has_time_ability")
		or not bool(loadout.call("has_time_ability", canonical))
	):
		return {}
	if canonical == &"rewind" and not context.get("pre_return_position") is Vector2:
		return {}
	if canonical == &"rewind" and not _finite_vector2(context.get("pre_return_position")):
		return {}
	if canonical == &"rift" and not context.get("position") is Vector2:
		return {}
	if canonical == &"rift" and not _finite_vector2(context.get("position")):
		return {}
	var runtime_context := _time_action_runtime_context(canonical, context)
	if not can_use(canonical, runtime_context):
		return {}
	var settlement := _prepare_time_action_settlement(
		canonical,
		context,
		runtime_context,
		owner_entity,
		run_id
	)
	if settlement.is_empty():
		return {}
	var transaction_context := context.duplicate(true)
	transaction_context["ability_id"] = canonical
	transaction_context["token"] = token
	transaction_context["generation"] = generation
	transaction_context["runtime_frame"] = frame
	transaction_context["run_id"] = run_id
	transaction_context["run_revision"] = int(owner_entity.call(
		"owner_character_generation"
	)) if owner_entity.has_method("owner_character_generation") else generation
	transaction_context["owner_character_generation"] = int(owner_entity.call(
		"owner_character_generation"
	)) if owner_entity.has_method("owner_character_generation") else generation
	transaction_context.merge(
		_time_action_character_facts(frame, owner_entity, settlement),
		true
	)
	var character_decision: Dictionary = {}
	if owner_entity.has_method("plan_character_time_action"):
		var plan_value: Variant = owner_entity.call(
			"plan_character_time_action",
			transaction_context.duplicate(true)
		)
		if not plan_value is Dictionary or not bool((plan_value as Dictionary).get("ok", false)):
			_rollback_time_action_settlement(settlement)
			return {}
		character_decision = (
			(plan_value as Dictionary).get("decision", {}) as Dictionary
		).duplicate(true)
	transaction_context["character_decision"] = character_decision
	var prepared_snapshot := time_action_snapshot()
	if prepared_snapshot.is_empty():
		_rollback_time_action_settlement(settlement)
		return {}
	var ticket_value: Variant = _time_action_transaction.call(
		"prepare",
		token,
		generation,
		frame,
		run_id,
		canonical,
		transaction_context,
		prepared_snapshot
	)
	if not ticket_value is Dictionary or (ticket_value as Dictionary).is_empty():
		_rollback_time_action_settlement(settlement)
		return {}
	var ticket := (ticket_value as Dictionary).duplicate(true)
	_prepared_time_action_settlement = settlement
	_prepared_time_action_ticket_fingerprint = str(ticket.get("fingerprint", ""))
	return ticket


func commit_time_action(ticket: Dictionary) -> Dictionary:
	var result_value: Variant = _time_action_transaction.call(
		"commit",
		ticket.duplicate(true),
		Callable(self, "_commit_time_action_ticket"),
		Callable(self, "_restore_time_action_snapshot")
	)
	if not result_value is Dictionary:
		return {"ok": false, "code": &"INVALID_TRANSACTION_RESULT"}
	var result := (result_value as Dictionary).duplicate(true)
	if bool(result.get("ok", false)):
		var committed_ticket := result.get("ticket", {}) as Dictionary
		_publish_time_skill_committed(
			StringName(str(committed_ticket.get("ability_id", ""))),
			int(committed_ticket.get("token", 0)),
			int(committed_ticket.get("generation", 0)),
			int(committed_ticket.get("frame", 0)),
			StringName(str(committed_ticket.get("run_id", ""))),
			(committed_ticket.get("context", {}) as Dictionary).duplicate(true)
		)
	var result_code := StringName(str(result.get("code", "")))
	if (
		bool(result.get("ok", false))
		or result_code in [&"COMMIT_FAILED_ROLLED_BACK", &"COMMIT_REJECTED_UNMUTATED"]
	):
		_clear_prepared_time_action_settlement()
	return result


func rollback_time_action(ticket: Dictionary) -> Dictionary:
	var result_value: Variant = _time_action_transaction.call(
		"rollback",
		ticket.duplicate(true),
		Callable(self, "_restore_time_action_snapshot")
	)
	var result: Dictionary = (
		(result_value as Dictionary).duplicate(true)
		if result_value is Dictionary
		else {"ok": false, "code": &"INVALID_TRANSACTION_RESULT"}
	)
	if bool(result.get("ok", false)):
		_clear_prepared_time_action_settlement()
	return result


func _commit_time_action_ticket(ticket: Dictionary) -> Dictionary:
	var prepared_value: Variant = ticket.get("prepared_snapshot")
	if (
		not prepared_value is Dictionary
		or not _prepared_time_action_settlement_matches(ticket)
	):
		return {"ok": false, "code": &"INVALID_PREPARED_SETTLEMENT", "mutated": false}
	if time_action_snapshot() != prepared_value:
		var released := _rollback_prepared_time_action_settlement()
		return {
			"ok": false,
			"code": &"PARTICIPANT_DRIFT" if released else &"SETTLEMENT_ROLLBACK_FAILED",
			"mutated": not released,
		}
	var ability_id := StringName(str(ticket.get("ability_id", "")))
	var context := (ticket.get("context", {}) as Dictionary).duplicate(true)
	var committed := _commit_prepared_time_action_settlement(ability_id)
	if not committed:
		return {
			"ok": false,
			"code": &"ABILITY_COMMIT_REJECTED",
			"mutated": time_action_snapshot() != prepared_value,
		}
	var owner_entity := get_parent()
	if owner_entity != null and owner_entity.has_method("commit_character_time_action"):
		context.merge(
			_time_action_character_facts(
				int(ticket.get("frame", _last_runtime_frame)),
				owner_entity,
				_prepared_time_action_settlement
			),
			true
		)
		if not bool(owner_entity.call(
			"commit_character_time_action",
			context.duplicate(true)
		)):
			return {
				"ok": false,
				"code": &"CHARACTER_COMMIT_REJECTED",
				"mutated": time_action_snapshot() != prepared_value,
			}
	return {
		"ok": true,
		"code": &"TIME_ACTION_COMMITTED",
		"ability_id": ability_id,
		"context": context,
	}


func _restore_time_action_snapshot(value: Dictionary) -> Dictionary:
	if not _rollback_prepared_time_action_settlement():
		return {"ok": false, "code": &"SETTLEMENT_ROLLBACK_FAILED"}
	var manager_value: Variant = value.get("time_manager")
	var world_value: Variant = value.get("world_payloads")
	var participant_value: Variant = value.get("character_participant")
	if (
		not manager_value is Dictionary
		or not world_value is Dictionary
		or not participant_value is Dictionary
	):
		return {"ok": false, "code": &"INVALID_PREPARED_SNAPSHOT"}
	var before := time_action_snapshot()
	if before == value:
		return {
			"ok": true,
			"code": &"RESTORED",
			"restored_snapshot": before,
		}
	if (
		world_payload_authority == null
		or not world_payload_authority.has_method("begin_transaction_restore")
		or not world_payload_authority.has_method("commit_transaction_restore")
		or not world_payload_authority.has_method("rollback_transaction_restore")
		or not can_restore_replay_snapshot(manager_value as Dictionary)
	):
		return {"ok": false, "code": &"INVALID_PREPARED_SNAPSHOT"}
	var before_manager := before.get("time_manager", {}) as Dictionary
	var before_participant := before.get("character_participant", {}) as Dictionary
	var owner_entity := get_parent()
	var world_ticket_value: Variant = world_payload_authority.call(
		"begin_transaction_restore",
		(world_value as Dictionary).duplicate(true)
	)
	if not world_ticket_value is Dictionary or (world_ticket_value as Dictionary).is_empty():
		return {"ok": false, "code": &"RESTORE_FAILED"}
	var world_ticket := (world_ticket_value as Dictionary).duplicate(true)
	if not restore_replay_snapshot((manager_value as Dictionary).duplicate(true)):
		var world_rollback_ok := bool(world_payload_authority.call(
			"rollback_transaction_restore",
			world_ticket.duplicate(true)
		))
		var manager_rollback_ok := restore_replay_snapshot(before_manager.duplicate(true))
		return {
			"ok": false,
			"code": (
				&"RESTORE_FAILED"
				if world_rollback_ok and manager_rollback_ok
				else &"RESTORE_ROLLBACK_FAILED"
			),
		}
	if not _restore_time_action_character_participant(
		owner_entity,
		(participant_value as Dictionary).duplicate(true)
	):
		var participant_world_rollback_ok := bool(world_payload_authority.call(
			"rollback_transaction_restore",
			world_ticket.duplicate(true)
		))
		var participant_manager_rollback_ok := restore_replay_snapshot(
			before_manager.duplicate(true)
		)
		var participant_rollback_ok := _restore_time_action_character_participant(
			owner_entity,
			before_participant.duplicate(true)
		)
		return {
			"ok": false,
			"code": (
				&"RESTORE_FAILED"
				if participant_world_rollback_ok
				and participant_manager_rollback_ok
				and participant_rollback_ok
				else &"RESTORE_ROLLBACK_FAILED"
			),
		}
	var staged_restored := time_action_snapshot()
	if staged_restored != value:
		var mismatch_world_rollback_ok := bool(world_payload_authority.call(
			"rollback_transaction_restore",
			world_ticket.duplicate(true)
		))
		var mismatch_manager_rollback_ok := restore_replay_snapshot(
			before_manager.duplicate(true)
		)
		var mismatch_participant_rollback_ok := _restore_time_action_character_participant(
			owner_entity,
			before_participant.duplicate(true)
		)
		return {
			"ok": false,
			"code": (
				&"RESTORE_MISMATCH"
				if mismatch_manager_rollback_ok
				and mismatch_world_rollback_ok
				and mismatch_participant_rollback_ok
				else &"RESTORE_ROLLBACK_FAILED"
			),
			"restored_snapshot": staged_restored,
		}
	if not bool(world_payload_authority.call(
		"commit_transaction_restore",
		world_ticket.duplicate(true)
	)):
		var commit_world_rollback_ok := bool(world_payload_authority.call(
			"rollback_transaction_restore",
			world_ticket.duplicate(true)
		))
		var commit_manager_rollback_ok := restore_replay_snapshot(
			before_manager.duplicate(true)
		)
		var commit_participant_rollback_ok := _restore_time_action_character_participant(
			owner_entity,
			before_participant.duplicate(true)
		)
		return {
			"ok": false,
			"code": (
				&"RESTORE_FAILED"
				if commit_manager_rollback_ok
				and commit_world_rollback_ok
				and commit_participant_rollback_ok
				else &"RESTORE_ROLLBACK_FAILED"
			),
		}
	return {
		"ok": true,
		"code": &"RESTORED",
		"restored_snapshot": value.duplicate(true),
	}


func _time_action_runtime_context(ability_id: StringName, context: Dictionary) -> Dictionary:
	var runtime_context := context.duplicate(true)
	if ability_id == &"rewind":
		var owner_entity := get_parent()
		var recorder: Node = null
		if owner_entity != null:
			var recorder_value: Variant = owner_entity.get("rewind_recorder")
			if recorder_value is Node:
				recorder = recorder_value as Node
			else:
				recorder = owner_entity.get_node_or_null("RewindRecorder")
		runtime_context["recorder"] = recorder
	return runtime_context


func _time_action_character_facts(
	frame: int,
	_owner_entity: Node,
	settlement: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	var ability_id := StringName(str(settlement.get("ability_id", "")))
	match ability_id:
		&"stop":
			result["stop_generation"] = int(settlement.get("source_sequence", 0))
			result["stop_until_frame"] = frame + int(settlement.get("duration_frames", 0))
		&"rift":
			result["rift_generation"] = int(settlement.get("source_token", 0))
			result["rift_center"] = settlement.get("position", Vector2.ZERO)
			var descriptor := settlement.get("descriptor", {}) as Dictionary
			var geometry := descriptor.get("geometry", {}) as Dictionary
			result["rift_radius"] = float(geometry.get("radius", 0.0))
		&"accelerate":
			result["shorten_echo_frames"] = 1
	return result


func _restore_time_action_character_participant(
	owner_entity: Node,
	value: Dictionary
) -> bool:
	if value.is_empty():
		return false
	return (
		owner_entity != null
		and owner_entity.has_method("restore_character_time_action_participant_snapshot")
		and bool(owner_entity.call(
			"restore_character_time_action_participant_snapshot",
			value.duplicate(true)
		))
	)


func _prepare_time_action_settlement(
	ability_id: StringName,
	context: Dictionary,
	runtime_context: Dictionary,
	owner_entity: Node,
	run_id: StringName
) -> Dictionary:
	match ability_id:
		&"stop":
			var stop_cost := _floor_rule_adjusted_cost(
				time_stop_cost,
				time_stop_cost_multiplier
			)
			if (
				not _valid_nonnegative_scalar(stop_cost)
				or not _valid_nonnegative_scalar(time_stop_cooldown)
				or not is_finite(time_stop_duration + time_stop_duration_bonus)
				or not is_finite(time_stop_weakpoint_damage_bonus)
				or not is_finite(time_stop_weakpoint_duration)
				or not _valid_nonnegative_scalar(time_stop_self_damage)
			):
				return {}
			var stop_sequence := _time_stop_source_sequence + 1
			return {
				"ability_id": ability_id,
				"cost": stop_cost,
				"cooldown_frames": _seconds_to_authoritative_frames(time_stop_cooldown),
				"duration_frames": _seconds_to_authoritative_frames(
					time_stop_duration + time_stop_duration_bonus
				),
				"source_sequence": stop_sequence,
				"source_id": _time_stop_source_id_for_sequence(stop_sequence),
				"weakpoint_damage_bonus": time_stop_weakpoint_damage_bonus,
				"weakpoint_duration_frames": _seconds_to_authoritative_frames(
					maxf(0.0, time_stop_weakpoint_duration)
				),
				"self_damage": time_stop_self_damage,
			}
		&"rewind":
			var recorder := runtime_context.get("recorder") as Node
			if recorder == null or not is_instance_valid(recorder):
				return {}
			var recorder_ticket_value: Variant = recorder.call(
				"prepare_rewind_transaction",
				context.get("pre_return_position")
			)
			if (
				not recorder_ticket_value is Dictionary
				or (recorder_ticket_value as Dictionary).is_empty()
			):
				return {}
			return {
				"ability_id": ability_id,
				"recorder": recorder,
				"recorder_ticket": (recorder_ticket_value as Dictionary).duplicate(true),
				"rewind_status": &"prepared",
				"rewind_echo_enabled": rewind_echo_enabled,
				"rewind_path_hit_multiplier": rewind_path_hit_multiplier,
			}
		&"rift":
			if (
				owner_entity == null
				or not owner_entity.has_method("owner_character_generation")
			):
				return {}
			var rift_cost := _floor_rule_adjusted_cost(
				time_rift_cost,
				time_rift_cost_multiplier
			)
			var rift_duration := maxf(0.0, time_rift_duration + time_rift_duration_bonus)
			var rift_radius := time_rift_radius + time_rift_radius_bonus
			var rift_slow := clampf(
				time_rift_slow_multiplier - time_rift_slow_bonus,
				0.1,
				1.0
			)
			if (
				not _valid_nonnegative_scalar(rift_cost)
				or not _valid_nonnegative_scalar(time_rift_cooldown)
				or not is_finite(rift_duration)
				or not is_finite(rift_radius)
				or rift_radius <= 0.0
				or not is_finite(rift_slow)
			):
				return {}
			var rift_position := context.get("position") as Vector2
			var owner_generation := int(owner_entity.call("owner_character_generation"))
			var source_token := _time_rift_source_sequence + 1
			var duration_frames := maxi(
				1,
				roundi(rift_duration * float(GAMEPLAY_FRAMES_PER_SECOND))
			)
			var payload_id := "%s:%d:rift:%d:1" % [
				run_id,
				owner_generation,
				source_token,
			]
			return {
				"ability_id": ability_id,
				"cost": rift_cost,
				"cooldown_frames": _seconds_to_authoritative_frames(time_rift_cooldown),
				"source_token": source_token,
				"position": rift_position,
				"descriptor": {
					"payload_id": payload_id,
					"handler_id": &"time_rift",
					"run_id": run_id,
					"owner_character_generation": owner_generation,
					"payload_family": &"rift",
					"source_token": source_token,
					"payload_generation": 1,
					"transform": Transform2D(0.0, rift_position),
					"geometry": {"center": rift_position, "radius": rift_radius},
					"remaining_frames": duration_frames,
					"claims": [],
					"tags": ["world_owned"],
					"parameters": {
						"slow_multiplier": rift_slow,
						"duration_seconds": _frames_to_seconds(duration_frames),
					},
				},
			}
		&"accelerate":
			var accelerate_cost := _floor_rule_adjusted_cost(
				time_accelerate_cost,
				time_accelerate_cost_multiplier
			)
			var accelerate_duration := (
				time_accelerate_duration + time_accelerate_duration_bonus
			)
			var accelerate_multiplier := (
				time_accelerate_multiplier + time_accelerate_multiplier_bonus
			)
			if (
				not _valid_nonnegative_scalar(accelerate_cost)
				or not _valid_nonnegative_scalar(time_accelerate_cooldown)
				or not is_finite(accelerate_duration)
				or not is_finite(accelerate_multiplier)
				or accelerate_multiplier <= 0.0
			):
				return {}
			return {
				"ability_id": ability_id,
				"cost": accelerate_cost,
				"cooldown_frames": _seconds_to_authoritative_frames(
					time_accelerate_cooldown
				),
				"duration_frames": _seconds_to_authoritative_frames(
					accelerate_duration
				),
				"multiplier": accelerate_multiplier,
				"token": _time_accelerate_token + 1,
			}
	return {}


func _commit_prepared_time_action_settlement(ability_id: StringName) -> bool:
	if (
		_prepared_time_action_settlement.is_empty()
		or StringName(str(_prepared_time_action_settlement.get("ability_id", "")))
		!= ability_id
	):
		return false
	match ability_id:
		&"stop":
			return _commit_frozen_time_stop(_prepared_time_action_settlement)
		&"rewind":
			return _commit_frozen_rewind(_prepared_time_action_settlement)
		&"rift":
			return _commit_frozen_time_rift(_prepared_time_action_settlement)
		&"accelerate":
			return _commit_frozen_time_accelerate(_prepared_time_action_settlement)
	return false


func _commit_frozen_time_stop(settlement: Dictionary) -> bool:
	var cost := float(settlement.get("cost", -1.0))
	var cooldown_frames := int(settlement.get("cooldown_frames", -1))
	var duration_frames := int(settlement.get("duration_frames", -1))
	if (
		_time_stop_active
		or duration_frames < 0
		or not _can_pay_frozen(&"time_stop", cost)
	):
		return false
	if not _take_self_damage(
		float(settlement.get("self_damage", 0.0)),
		&"curse:time_stop"
	):
		return false
	if not _pay_frozen_cost(&"time_stop", cost, cooldown_frames):
		return false
	_time_stop_source_sequence = int(settlement.get("source_sequence", 0))
	_time_stop_source_id = StringName(str(settlement.get("source_id", "")))
	_set_time_stop_remaining_frames(duration_frames)
	_time_stop_active = true
	_weapon_stop_extension_frames = 0
	_weapon_stop_extension_tokens.clear()
	_time_stop_targets.clear()
	var authoritative_duration := _frames_to_seconds(duration_frames)
	var weakpoint_duration := _frames_to_seconds(
		int(settlement.get("weakpoint_duration_frames", 0))
	)
	var weakpoint_bonus := float(settlement.get("weakpoint_damage_bonus", 0.0))
	for node: Node in SceneScope.nodes_in_group(self, "time_stoppable"):
		if node.has_method("apply_time_stop_source"):
			node.apply_time_stop_source(_time_stop_source_id, authoritative_duration)
			_time_stop_targets.append(node)
		elif node.has_method("apply_time_stop"):
			node.apply_time_stop(authoritative_duration)
		if node.has_method("apply_weakpoint"):
			node.apply_weakpoint(weakpoint_duration, weakpoint_bonus)
	_publish_time_skill_started(&"time_stop", {})
	if _time_stop_remaining_frames <= 0:
		_end_time_stop(true)
	return true


func _commit_frozen_rewind(settlement: Dictionary) -> bool:
	var recorder := settlement.get("recorder") as Node
	var recorder_ticket_value: Variant = settlement.get("recorder_ticket")
	if (
		recorder == null
		or not is_instance_valid(recorder)
		or not recorder_ticket_value is Dictionary
		or StringName(str(settlement.get("rewind_status", ""))) != &"prepared"
	):
		return false
	settlement["rewind_status"] = &"commit_attempted"
	var current_echo_enabled := rewind_echo_enabled
	var current_path_hit_multiplier := rewind_path_hit_multiplier
	rewind_echo_enabled = bool(settlement.get("rewind_echo_enabled", false))
	rewind_path_hit_multiplier = float(
		settlement.get("rewind_path_hit_multiplier", 0.0)
	)
	var committed := bool(recorder.call(
		"commit_rewind_transaction",
		(recorder_ticket_value as Dictionary).duplicate(true)
	))
	rewind_echo_enabled = current_echo_enabled
	rewind_path_hit_multiplier = current_path_hit_multiplier
	return committed


func _commit_frozen_time_rift(settlement: Dictionary) -> bool:
	var descriptor_value: Variant = settlement.get("descriptor")
	var cost := float(settlement.get("cost", -1.0))
	var cooldown_frames := int(settlement.get("cooldown_frames", -1))
	if (
		not descriptor_value is Dictionary
		or world_payload_authority == null
		or not _can_pay_frozen(&"time_rift", cost)
	):
		return false
	var descriptor := (descriptor_value as Dictionary).duplicate(true)
	var committed_value: Variant = world_payload_authority.call(
		"commit_payload",
		descriptor
	)
	if (
		not committed_value is Dictionary
		or not bool((committed_value as Dictionary).get("ok", false))
	):
		return false
	var payload_id := StringName(str(descriptor.get("payload_id", "")))
	var rift := world_payload_authority.call("payload_node", payload_id) as Node
	if rift == null:
		return false
	if not _pay_frozen_cost(&"time_rift", cost, cooldown_frames):
		return false
	var source_token := int(settlement.get("source_token", 0))
	_prune_active_rifts()
	_time_rift_source_sequence = source_token
	_active_rifts.append(rift)
	_active_rift_generations[rift] = source_token
	_publish_time_skill_started(
		&"time_rift",
		{"position": settlement.get("position", Vector2.ZERO)}
	)
	return true


func _commit_frozen_time_accelerate(settlement: Dictionary) -> bool:
	var cost := float(settlement.get("cost", -1.0))
	var cooldown_frames := int(settlement.get("cooldown_frames", -1))
	var duration_frames := int(settlement.get("duration_frames", -1))
	var multiplier := float(settlement.get("multiplier", 0.0))
	var token := int(settlement.get("token", 0))
	var owner_entity := get_parent()
	if (
		_time_accelerate_active
		or owner_entity == null
		or not owner_entity.has_method("apply_time_acceleration_token")
		or duration_frames < 0
		or multiplier <= 0.0
		or token <= 0
		or not _can_pay_frozen(&"time_accelerate", cost)
	):
		return false
	if not bool(owner_entity.call(
		"apply_time_acceleration_token",
		token,
		multiplier,
		_frames_to_seconds(duration_frames)
	)):
		return false
	_time_accelerate_token = token
	_time_accelerate_active = true
	_time_accelerate_publish_lifecycle = true
	_time_accelerate_multiplier_active = multiplier
	_set_time_accelerate_remaining_frames(duration_frames)
	if not _pay_frozen_cost(&"time_accelerate", cost, cooldown_frames):
		return false
	_publish_time_skill_started(&"time_accelerate", {})
	if _time_accelerate_remaining_frames <= 0:
		_end_time_accelerate(_time_accelerate_token, true)
	return true


func _can_pay_frozen(skill_id: StringName, cost: float) -> bool:
	return (
		_valid_nonnegative_scalar(cost)
		and energy >= cost
		and int(_cooldown_frames.get(skill_id, -1)) == 0
	)


func _pay_frozen_cost(
	skill_id: StringName,
	cost: float,
	cooldown_frames: int
) -> bool:
	if cooldown_frames < 0 or not _can_pay_frozen(skill_id, cost):
		return false
	var energy_before := energy
	energy = maxf(0.0, energy - cost)
	if energy != energy_before:
		_resource_revision += 1
	if not _set_cooldown_frames(skill_id, cooldown_frames):
		return false
	_publish_energy_changed(energy, max_energy)
	_publish_cooldown_changed(skill_id, _frames_to_seconds(cooldown_frames))
	return true


func _prepared_time_action_settlement_matches(ticket: Dictionary) -> bool:
	return (
		not _prepared_time_action_settlement.is_empty()
		and not _prepared_time_action_ticket_fingerprint.is_empty()
		and str(ticket.get("fingerprint", ""))
		== _prepared_time_action_ticket_fingerprint
		and StringName(str(ticket.get("ability_id", "")))
		== StringName(str(_prepared_time_action_settlement.get("ability_id", "")))
	)


func _rollback_prepared_time_action_settlement() -> bool:
	if _prepared_time_action_settlement.is_empty():
		return true
	return _rollback_time_action_settlement(_prepared_time_action_settlement)


func _rollback_time_action_settlement(settlement: Dictionary) -> bool:
	if StringName(str(settlement.get("ability_id", ""))) != &"rewind":
		return true
	var status := StringName(str(settlement.get("rewind_status", "")))
	if status in [&"rolled_back", &"commit_attempted"]:
		return true
	if status != &"prepared":
		return false
	var recorder := settlement.get("recorder") as Node
	var recorder_ticket_value: Variant = settlement.get("recorder_ticket")
	if (
		recorder == null
		or not is_instance_valid(recorder)
		or not recorder_ticket_value is Dictionary
	):
		return false
	var rollback_value: Variant = recorder.call(
		"rollback_rewind_transaction",
		(recorder_ticket_value as Dictionary).duplicate(true)
	)
	if not rollback_value is Dictionary or not bool(
		(rollback_value as Dictionary).get("ok", false)
	):
		return false
	settlement["rewind_status"] = &"rolled_back"
	return true


func _clear_prepared_time_action_settlement() -> void:
	_prepared_time_action_settlement.clear()
	_prepared_time_action_ticket_fingerprint = ""


static func _valid_nonnegative_scalar(value: float) -> bool:
	return is_finite(value) and value >= 0.0


static func _finite_vector2(value: Variant) -> bool:
	return (
		value is Vector2
		and is_finite((value as Vector2).x)
		and is_finite((value as Vector2).y)
	)


func _install_time_replay_snapshot(value: Dictionary) -> bool:
	if not can_restore_replay_snapshot(value):
		return false
	var owner_entity := get_parent()
	if owner_entity != null and owner_entity.has_method("_force_clear_time_acceleration"):
		owner_entity.call("_force_clear_time_acceleration")
	var energy_state := value["energy_state"] as Dictionary
	energy = float(energy_state["current"])
	_resource_revision = int(energy_state["revision"])
	_last_runtime_frame = int(value["runtime_frame"])
	_energy_regen_remainder = int(value["energy_regen_remainder"])
	if not _install_cooldowns_from_seconds(value["cooldowns"] as Dictionary):
		return false
	var previous_stop_source_id := _time_stop_source_id
	_time_stop_active = bool(value["stop_active"])
	_time_stop_source_sequence = int(value["stop_source_sequence"])
	_time_stop_source_id = StringName(str(value["stop_source_id"]))
	_set_time_stop_remaining_frames(
		_seconds_to_authoritative_frames(float(value["stop_remaining"]))
	)
	_weapon_stop_extension_frames = int(value["stop_extension_frames"])
	_weapon_stop_extension_tokens = (value["stop_extension_tokens"] as Dictionary).duplicate(true)
	_time_accelerate_active = bool(value["accelerate_active"])
	_time_accelerate_token = int(value["accelerate_token"])
	_set_time_accelerate_remaining_frames(
		_seconds_to_authoritative_frames(float(value["accelerate_remaining"]))
	)
	_time_accelerate_multiplier_active = float(value["accelerate_multiplier"])
	_time_accelerate_publish_lifecycle = bool(value["accelerate_publish_lifecycle"])
	_set_rewind_window_remaining_frames(
		_seconds_to_authoritative_frames(float(value["rewind_window_remaining"]))
	)
	_rewind_weapon_window_generation = int(value["rewind_window_generation"])
	_rewind_weapon_window_claimed = bool(value["rewind_window_claimed"])
	_time_rift_source_sequence = int(value["rift_source_sequence"])
	if not _weapon_replay_restore_transaction_active:
		_reconcile_replay_time_stop_targets(previous_stop_source_id)
	if _time_accelerate_active:
		if (
			owner_entity == null
			or not owner_entity.has_method("apply_time_acceleration_token")
			or not bool(owner_entity.call(
				"apply_time_acceleration_token",
				_time_accelerate_token,
				_time_accelerate_multiplier_active,
				_time_accelerate_remaining
			))
		):
			return false
	_sync_active_rifts_from_authority()
	return replay_snapshot() == value


func _sync_active_rifts_from_authority() -> void:
	_active_rifts.clear()
	_active_rift_generations.clear()
	if world_payload_authority == null:
		return
	for descriptor: Dictionary in _active_rift_payload_descriptors():
		var payload_id := StringName(str(descriptor.get("payload_id", "")))
		var node := world_payload_authority.call("payload_node", payload_id) as Node
		if node == null:
			continue
		_active_rifts.append(node)
		_active_rift_generations[node] = int(descriptor.get("source_token", 0))


func configure_from_stats(stats: Resource, publish_signal: bool = true) -> void:
	var previous_max_energy := max_energy
	var previous_energy := energy
	max_energy = stats.time_energy_max
	energy_regen = stats.time_energy_regen
	if max_energy > previous_max_energy:
		energy += max_energy - previous_max_energy
	energy = clampf(energy, 0.0, max_energy)
	if max_energy != previous_max_energy or energy != previous_energy:
		_resource_revision += 1
		if publish_signal:
			_publish_energy_changed(energy, max_energy)


func canonical_skill_id(skill_id: StringName) -> StringName:
	return TimeAbilityIdsScript.canonical_id(skill_id)


func action_skill_id(skill_id: StringName) -> StringName:
	return TimeAbilityIdsScript.action_id(skill_id)


func can_use(skill_id: StringName, context: Dictionary) -> bool:
	match canonical_skill_id(skill_id):
		&"stop":
			return can_time_stop()
		&"rewind":
			return can_rewind(context.get("recorder") as Node)
		&"rift":
			return context.get("position") is Vector2 and can_time_rift(context.get("position", Vector2.ZERO))
		&"accelerate":
			return can_time_accelerate()
		_:
			return false


func try_use(skill_id: StringName, context: Dictionary) -> bool:
	if not can_use(skill_id, context):
		return false
	match canonical_skill_id(skill_id):
		&"stop":
			return try_time_stop()
		&"rewind":
			return try_rewind(context.get("recorder") as Node)
		&"rift":
			return try_time_rift(context.get("position", Vector2.ZERO))
		&"accelerate":
			return try_time_accelerate()
		_:
			return false


func can_time_stop() -> bool:
	var effective_cost := _floor_rule_adjusted_cost(
		time_stop_cost,
		time_stop_cost_multiplier
	)
	return not _time_stop_active and _can_pay(&"time_stop", effective_cost)


func try_time_stop() -> bool:
	var effective_cost := _floor_rule_adjusted_cost(
		time_stop_cost,
		time_stop_cost_multiplier
	)
	var effective_duration := time_stop_duration + time_stop_duration_bonus
	var duration_frames := _seconds_to_authoritative_frames(effective_duration)
	var authoritative_duration := _frames_to_seconds(duration_frames)
	if not can_time_stop():
		return false
	if not _take_self_damage(time_stop_self_damage, &"curse:time_stop"):
		return false
	_pay_cost(&"time_stop", effective_cost, time_stop_cooldown)
	_time_stop_source_sequence += 1
	_time_stop_source_id = _time_stop_source_id_for_sequence(_time_stop_source_sequence)
	_set_time_stop_remaining_frames(duration_frames)
	_time_stop_active = true
	_weapon_stop_extension_frames = 0
	_weapon_stop_extension_tokens.clear()
	_time_stop_targets.clear()
	for node: Node in SceneScope.nodes_in_group(self, "time_stoppable"):
		if node.has_method("apply_time_stop_source"):
			node.apply_time_stop_source(_time_stop_source_id, authoritative_duration)
			_time_stop_targets.append(node)
		elif node.has_method("apply_time_stop"):
			node.apply_time_stop(authoritative_duration)
		if node.has_method("apply_weakpoint"):
			node.apply_weakpoint(time_stop_weakpoint_duration, time_stop_weakpoint_damage_bonus)
	_publish_time_skill_started(&"time_stop", {})
	if _time_stop_remaining_frames <= 0:
		_end_time_stop(true)
	return true


func _time_stop_source_id_for_sequence(sequence: int) -> StringName:
	var owner_entity := get_parent()
	var run_id := &"unbound"
	var owner_generation := 1
	if owner_entity != null and owner_entity.has_method("current_run_id"):
		run_id = StringName(str(owner_entity.call("current_run_id")))
	if owner_entity != null and owner_entity.has_method("owner_character_generation"):
		owner_generation = maxi(1, int(owner_entity.call("owner_character_generation")))
	if run_id == &"":
		run_id = &"unbound"
	return StringName("time_stop:%s:%d:%d" % [str(run_id), owner_generation, sequence])


func _end_time_stop(publish_end_event: bool) -> bool:
	if not _time_stop_active:
		return false
	var source_id := _time_stop_source_id
	for target_value: Variant in _time_stop_targets.duplicate():
		if not is_instance_valid(target_value):
			continue
		var target := target_value as Node
		if target != null and target.has_method("clear_time_stop_source"):
			target.clear_time_stop_source(source_id)
	_time_stop_targets.clear()
	_time_stop_source_id = &""
	_time_stop_active = false
	_set_time_stop_remaining_frames(0)
	_weapon_stop_extension_frames = 0
	_weapon_stop_extension_tokens.clear()
	if publish_end_event:
		_publish_time_skill_ended(&"time_stop", {})
	return true


func can_rewind(recorder: Node) -> bool:
	if recorder == null or not recorder.has_method("has_snapshot") or not recorder.has_snapshot():
		return false
	var effective_cost := _floor_rule_adjusted_cost(rewind_cost, rewind_cost_multiplier)
	if not _can_pay(&"time_rewind", effective_cost):
		return false
	return (
		recorder.has_method("prepare_rewind_transaction")
		and recorder.has_method("commit_rewind_transaction")
		and recorder.has_method("rollback_rewind_transaction")
	)


func try_rewind(recorder: Node) -> bool:
	if not can_rewind(recorder):
		return false
	var transaction: Dictionary = recorder.prepare_rewind_transaction()
	if transaction.is_empty():
		return false
	return bool(recorder.commit_rewind_transaction(transaction))


func can_time_rift(_rift_position: Vector2 = Vector2.ZERO) -> bool:
	var effective_cost := _floor_rule_adjusted_cost(
		time_rift_cost,
		time_rift_cost_multiplier
	)
	var owner_entity := get_parent()
	return (
		owner_entity != null
		and owner_entity.get_parent() != null
		and world_payload_authority != null
		and _can_pay(&"time_rift", effective_cost)
	)


func try_time_rift(rift_position: Vector2) -> bool:
	var effective_cost := _floor_rule_adjusted_cost(
		time_rift_cost,
		time_rift_cost_multiplier
	)
	if not can_time_rift(rift_position):
		return false
	var owner_entity := get_parent()
	if (
		not owner_entity.has_method("current_run_id")
		or not owner_entity.has_method("owner_character_generation")
	):
		return false
	var run_id := StringName(str(owner_entity.call("current_run_id")))
	var owner_generation := int(owner_entity.call("owner_character_generation"))
	var source_token := _time_rift_source_sequence + 1
	var effective_duration := maxf(0.0, time_rift_duration + time_rift_duration_bonus)
	var effective_radius := time_rift_radius + time_rift_radius_bonus
	var effective_slow := clampf(
		time_rift_slow_multiplier - time_rift_slow_bonus,
		0.1,
		1.0
	)
	var payload_id := "%s:%d:rift:%d:1" % [run_id, owner_generation, source_token]
	var descriptor := {
		"payload_id": payload_id,
		"handler_id": &"time_rift",
		"run_id": run_id,
		"owner_character_generation": owner_generation,
		"payload_family": &"rift",
		"source_token": source_token,
		"payload_generation": 1,
		"transform": Transform2D(0.0, rift_position),
		"geometry": {"center": rift_position, "radius": effective_radius},
		"remaining_frames": maxi(1, roundi(effective_duration * 60.0)),
		"claims": [],
		"tags": ["world_owned"],
		"parameters": {
			"slow_multiplier": effective_slow,
			"duration_seconds": effective_duration,
		},
	}
	var committed_value: Variant = world_payload_authority.call(
		"commit_payload",
		descriptor
	)
	if not committed_value is Dictionary or not bool((committed_value as Dictionary).get("ok", false)):
		return false
	var rift := world_payload_authority.call("payload_node", StringName(payload_id)) as Node
	if rift == null:
		return false
	_pay_cost(&"time_rift", effective_cost, time_rift_cooldown)
	_prune_active_rifts()
	_time_rift_source_sequence = source_token
	_active_rifts.append(rift)
	_active_rift_generations[rift] = source_token
	_publish_time_skill_started(&"time_rift", {"position": rift_position})
	return true


func _spawn_time_rift_payload(descriptor: Dictionary) -> Node:
	var geometry_value: Variant = descriptor.get("geometry")
	var parameters_value: Variant = descriptor.get("parameters")
	if not geometry_value is Dictionary or not parameters_value is Dictionary:
		return null
	var geometry := geometry_value as Dictionary
	var parameters := parameters_value as Dictionary
	var rift := TimeRiftScene.instantiate()
	if (
		not rift.has_method("configure_world_payload_identity")
		or not bool(rift.call(
			"configure_world_payload_identity",
			StringName(str(descriptor.get("payload_id", "")))
		))
		or not rift.has_method("configure_world_payload_retirement")
		or not bool(rift.call(
			"configure_world_payload_retirement",
			Callable(self, "_request_time_rift_payload_retirement")
		))
	):
		rift.free()
		return null
	rift.duration = float(descriptor.get("remaining_frames", 1)) / 60.0
	rift.radius = float(geometry.get("radius", 0.0))
	rift.slow_multiplier = float(parameters.get("slow_multiplier", 1.0))
	rift.transform = descriptor.get("transform", Transform2D.IDENTITY)
	return rift


func _request_time_rift_payload_retirement(
	payload_id: StringName,
	reason: StringName
) -> Dictionary:
	if (
		world_payload_authority == null
		or not world_payload_authority.has_method("payload_descriptor")
		or not world_payload_authority.has_method("retire_payload")
	):
		return {"ok": false, "code": &"AUTHORITY_UNAVAILABLE"}
	var descriptor_value: Variant = world_payload_authority.call(
		"payload_descriptor",
		payload_id
	)
	if not descriptor_value is Dictionary or (descriptor_value as Dictionary).is_empty():
		return {"ok": false, "code": &"PAYLOAD_NOT_FOUND"}
	call_deferred("_retire_time_rift_payload", payload_id, reason)
	return {"ok": true, "code": &"RETIREMENT_REQUESTED"}


func _retire_time_rift_payload(payload_id: StringName, reason: StringName) -> Dictionary:
	if (
		world_payload_authority == null
		or not world_payload_authority.has_method("payload_descriptor")
		or not world_payload_authority.has_method("retire_payload")
	):
		return {"ok": false, "code": &"AUTHORITY_UNAVAILABLE"}
	var descriptor_value: Variant = world_payload_authority.call(
		"payload_descriptor",
		payload_id
	)
	if not descriptor_value is Dictionary or (descriptor_value as Dictionary).is_empty():
		return {"ok": false, "code": &"PAYLOAD_NOT_FOUND"}
	var descriptor := descriptor_value as Dictionary
	var retired_value: Variant = world_payload_authority.call(
		"retire_payload",
		payload_id,
		StringName(str(descriptor.get("run_id", ""))),
		int(descriptor.get("owner_character_generation", 0)),
		reason
	)
	return (
		(retired_value as Dictionary).duplicate(true)
		if retired_value is Dictionary
		else {"ok": false, "code": &"INVALID_RETIRE_RESULT"}
	)


func can_time_accelerate() -> bool:
	var effective_cost := _floor_rule_adjusted_cost(
		time_accelerate_cost,
		time_accelerate_cost_multiplier
	)
	var owner_entity := get_parent()
	if owner_entity == null:
		return false
	if _time_accelerate_active or not owner_entity.has_method("apply_time_acceleration_token"):
		return false
	return _can_pay(&"time_accelerate", effective_cost)


func try_time_accelerate() -> bool:
	var effective_cost := _floor_rule_adjusted_cost(
		time_accelerate_cost,
		time_accelerate_cost_multiplier
	)
	var effective_duration := time_accelerate_duration + time_accelerate_duration_bonus
	var duration_frames := _seconds_to_authoritative_frames(effective_duration)
	var authoritative_duration := _frames_to_seconds(duration_frames)
	var effective_multiplier := time_accelerate_multiplier + time_accelerate_multiplier_bonus
	if not can_time_accelerate():
		return false
	var owner_entity := get_parent()
	var next_token := _time_accelerate_token + 1
	if not bool(owner_entity.apply_time_acceleration_token(next_token, effective_multiplier, authoritative_duration)):
		return false
	_time_accelerate_token = next_token
	_time_accelerate_active = true
	_time_accelerate_publish_lifecycle = true
	_time_accelerate_multiplier_active = effective_multiplier
	_set_time_accelerate_remaining_frames(duration_frames)
	_pay_cost(&"time_accelerate", effective_cost, time_accelerate_cooldown)
	_publish_time_skill_started(&"time_accelerate", {})
	if _time_accelerate_remaining_frames <= 0:
		_end_time_accelerate(_time_accelerate_token, true)
	return true


func apply_legacy_time_acceleration(multiplier: float, duration: float) -> bool:
	var duration_frames := _seconds_to_authoritative_frames(duration)
	var authoritative_duration := _frames_to_seconds(duration_frames)
	if _time_accelerate_active or duration_frames <= 0:
		return false
	var owner_entity := get_parent()
	if owner_entity == null or not owner_entity.has_method("apply_time_acceleration_token"):
		return false
	var next_token := _time_accelerate_token + 1
	if not bool(owner_entity.apply_time_acceleration_token(next_token, multiplier, authoritative_duration)):
		return false
	_time_accelerate_token = next_token
	_time_accelerate_active = true
	_time_accelerate_publish_lifecycle = false
	_time_accelerate_multiplier_active = multiplier
	_set_time_accelerate_remaining_frames(duration_frames)
	return true


func _end_time_accelerate(token: int, publish_end_event: bool) -> bool:
	if not _time_accelerate_active or token != _time_accelerate_token:
		return false
	var should_publish := publish_end_event and _time_accelerate_publish_lifecycle
	_time_accelerate_active = false
	_time_accelerate_publish_lifecycle = false
	_time_accelerate_multiplier_active = 1.0
	_set_time_accelerate_remaining_frames(0)
	var owner_entity := get_parent()
	if owner_entity != null:
		if owner_entity.has_method("clear_time_acceleration"):
			owner_entity.clear_time_acceleration(token)
		elif owner_entity.has_method("_clear_time_acceleration"):
			owner_entity._clear_time_acceleration(token)
	if should_publish:
		_publish_time_skill_ended(&"time_accelerate", {})
	return true


func cancel_all_time_effects(_reason: StringName) -> void:
	_end_time_stop(true)
	_end_time_accelerate(_time_accelerate_token, true)
	_clear_rewind_weapon_window()
	_retire_active_rifts(_reason)


func reset_runtime_state(reset_frame_clock: bool = false) -> void:
	_active_frame_signal_transaction.clear()
	if not _rollback_prepared_time_action_settlement():
		push_error("Prepared TimeAction settlement rollback failed during runtime reset")
	_clear_prepared_time_action_settlement()
	_clear_weapon_replay_restore_transaction()
	_time_action_transaction = TimeActionTransactionScript.new()
	_end_time_stop(false)
	_end_time_accelerate(_time_accelerate_token, false)
	_clear_rewind_weapon_window()
	_time_accelerate_token += 1
	if reset_frame_clock:
		_last_runtime_frame = 0
	_energy_regen_remainder = 0
	_floor_rule_cost_multiplier = 1.0
	_event_energy_regen_multiplier = 1.0
	energy = max_energy
	# A full runtime reset invalidates any prepared external-resource ticket even
	# when the numeric balance was already at maximum.
	_resource_revision += 1
	_publish_energy_changed(energy, max_energy)
	for skill_id: StringName in COOLDOWN_SKILL_IDS:
		_set_cooldown_seconds(skill_id, 0.0)
		_publish_cooldown_changed(skill_id, 0.0)
	_retire_active_rifts(&"runtime_reset")


func restore_energy(amount: float, publish_signal: bool = true) -> float:
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	var energy_before := energy
	energy = minf(max_energy, energy + amount)
	if energy != energy_before:
		_resource_revision += 1
	if publish_signal:
		_publish_energy_changed(energy, max_energy)
	return energy - energy_before


func publish_reward_energy_changed(current: float, maximum: float) -> bool:
	if (
		not is_finite(current)
		or not is_finite(maximum)
		or maximum <= 0.0
		or current < 0.0
		or current > maximum
	):
		return false
	_publish_energy_changed(current, maximum)
	return true


func gameplay_rewind_transaction_snapshot() -> Dictionary:
	_refresh_cooldown_seconds_projection()
	return {
		"energy": energy,
		"max_energy": max_energy,
		"cooldowns": _cooldowns.duplicate(true),
		"resource_revision": _resource_revision,
		"rewind_window_remaining": _rewind_weapon_window_remaining,
		"rewind_window_generation": _rewind_weapon_window_generation,
		"rewind_window_claimed": _rewind_weapon_window_claimed,
		"self_damage_generation": _irreversible_self_damage_generation,
		"next_self_damage_token": _next_irreversible_self_damage_token,
	}


func fixed_frame_transaction_snapshot() -> Dictionary:
	var time_action_value: Variant = _time_action_transaction.call("runtime_snapshot")
	if not time_action_value is Dictionary or (time_action_value as Dictionary).is_empty():
		return {}
	return {
		"gameplay": gameplay_rewind_transaction_snapshot(),
		"time_action": (time_action_value as Dictionary).duplicate(true),
	}


func restore_fixed_frame_transaction_snapshot(value: Dictionary) -> bool:
	if (
		value.size() != 2
		or not value.get("gameplay") is Dictionary
		or not value.get("time_action") is Dictionary
	):
		return false
	var before_gameplay := gameplay_rewind_transaction_snapshot()
	var before_time_action_value: Variant = _time_action_transaction.call("runtime_snapshot")
	if not before_time_action_value is Dictionary:
		return false
	var before_time_action := (before_time_action_value as Dictionary).duplicate(true)
	if not restore_gameplay_rewind_transaction_snapshot(
		(value["gameplay"] as Dictionary).duplicate(true)
	):
		return false
	if not bool(_time_action_transaction.call(
		"restore_runtime_snapshot",
		(value["time_action"] as Dictionary).duplicate(true)
	)):
		var gameplay_rollback_ok := restore_gameplay_rewind_transaction_snapshot(before_gameplay)
		var action_rollback_ok := bool(_time_action_transaction.call(
			"restore_runtime_snapshot",
			before_time_action
		))
		if not gameplay_rollback_ok or not action_rollback_ok:
			push_error("Time fixed-frame transaction rollback failed closed")
		return false
	return fixed_frame_transaction_snapshot() == value


func prepare_gameplay_rewind_settlement_context() -> Dictionary:
	var effective_cost := _floor_rule_adjusted_cost(rewind_cost, rewind_cost_multiplier)
	var health_component := get_parent().get_node_or_null("HealthComponent")
	if (
		health_component == null
		or not health_component.has_method("irreversible_run_id")
		or not is_finite(effective_cost)
		or effective_cost < 0.0
		or not is_finite(rewind_cooldown)
		or rewind_cooldown < 0.0
		or not is_finite(rewind_self_damage)
		or rewind_self_damage < 0.0
		or not is_finite(rewind_heal)
		or rewind_heal < 0.0
		or not _can_pay(&"time_rewind", effective_cost)
	):
		return {}
	var run_id := StringName(str(health_component.call("irreversible_run_id")))
	if run_id == &"":
		return {}
	return {
		"run_id": run_id,
		"cost": effective_cost,
		"cooldown": rewind_cooldown,
		"self_damage": rewind_self_damage,
		"heal": rewind_heal,
		"self_damage_token": _next_irreversible_self_damage_token,
		"self_damage_generation": _irreversible_self_damage_generation,
	}


func install_gameplay_rewind_settlement(context: Dictionary, before: Dictionary) -> bool:
	if (
		not _valid_gameplay_rewind_transaction_snapshot(before)
		or gameplay_rewind_transaction_snapshot() != before
		or not _valid_gameplay_rewind_settlement_context(context)
	):
		return false
	var health_component := get_parent().get_node_or_null("HealthComponent")
	if (
		health_component == null
		or not health_component.has_method("irreversible_run_id")
		or StringName(str(health_component.call("irreversible_run_id"))) != context["run_id"]
	):
		return false
	energy = maxf(0.0, energy - float(context["cost"]))
	if not _set_cooldown_seconds(&"time_rewind", float(context["cooldown"])):
		return false
	_resource_revision += 1
	if float(context["self_damage"]) > 0.0:
		_next_irreversible_self_damage_token += 1
	_rewind_weapon_window_generation += 1
	_set_rewind_window_remaining_frames(REWIND_WEAPON_WINDOW_DURATION_FRAMES)
	_rewind_weapon_window_claimed = false
	return true


func restore_gameplay_rewind_transaction_snapshot(value: Dictionary) -> bool:
	if not _valid_gameplay_rewind_transaction_snapshot(value):
		return false
	energy = float(value["energy"])
	max_energy = float(value["max_energy"])
	if not _install_cooldowns_from_seconds(value["cooldowns"] as Dictionary):
		return false
	_resource_revision = int(value["resource_revision"])
	_set_rewind_window_remaining_frames(
		_seconds_to_authoritative_frames(float(value["rewind_window_remaining"]))
	)
	_rewind_weapon_window_generation = int(value["rewind_window_generation"])
	_rewind_weapon_window_claimed = bool(value["rewind_window_claimed"])
	_irreversible_self_damage_generation = int(value["self_damage_generation"])
	_next_irreversible_self_damage_token = int(value["next_self_damage_token"])
	return gameplay_rewind_transaction_snapshot() == value


func publish_gameplay_rewind_commit(transaction: Dictionary, before: Dictionary) -> bool:
	if not _valid_gameplay_rewind_transaction_snapshot(before):
		return false
	if float(before["energy"]) != energy:
		_publish_energy_changed(energy, max_energy)
	_publish_cooldown_changed(&"time_rewind", get_cooldown(&"time_rewind"))
	_publish_rewind_committed(transaction.duplicate(true))
	return true


func _valid_gameplay_rewind_settlement_context(value: Dictionary) -> bool:
	if value.size() != 7:
		return false
	for field: String in [
		"run_id", "cost", "cooldown", "self_damage", "heal",
		"self_damage_token", "self_damage_generation",
	]:
		if not value.has(field):
			return false
	if typeof(value["run_id"]) not in [TYPE_STRING, TYPE_STRING_NAME] or str(value["run_id"]).is_empty():
		return false
	for field: String in ["cost", "cooldown", "self_damage", "heal"]:
		if typeof(value[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[field])) or float(value[field]) < 0.0:
			return false
	return (
		typeof(value["self_damage_token"]) == TYPE_INT
		and int(value["self_damage_token"]) == _next_irreversible_self_damage_token
		and typeof(value["self_damage_generation"]) == TYPE_INT
		and int(value["self_damage_generation"]) == _irreversible_self_damage_generation
		and _can_pay(&"time_rewind", float(value["cost"]))
	)


func _valid_gameplay_rewind_transaction_snapshot(value: Dictionary) -> bool:
	if value.size() != GAMEPLAY_REWIND_TRANSACTION_FIELDS.size():
		return false
	for field: String in GAMEPLAY_REWIND_TRANSACTION_FIELDS:
		if not value.has(field):
			return false
	for field: String in ["energy", "max_energy", "rewind_window_remaining"]:
		if typeof(value[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[field])) or float(value[field]) < 0.0:
			return false
	if float(value["energy"]) > float(value["max_energy"]):
		return false
	if not value["cooldowns"] is Dictionary:
		return false
	var cooldowns := value["cooldowns"] as Dictionary
	if cooldowns.size() != _cooldowns.size():
		return false
	for skill_id: StringName in _cooldowns.keys():
		if not cooldowns.has(skill_id) or typeof(cooldowns[skill_id]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(cooldowns[skill_id])) or float(cooldowns[skill_id]) < 0.0:
			return false
	return (
		typeof(value["resource_revision"]) == TYPE_INT
		and int(value["resource_revision"]) > 0
		and typeof(value["rewind_window_generation"]) == TYPE_INT
		and int(value["rewind_window_generation"]) >= 0
		and typeof(value["rewind_window_claimed"]) == TYPE_BOOL
		and typeof(value["self_damage_generation"]) == TYPE_INT
		and int(value["self_damage_generation"]) > 0
		and typeof(value["next_self_damage_token"]) == TYPE_INT
		and int(value["next_self_damage_token"]) > 0
	)


func weapon_interaction_context() -> Dictionary:
	_prune_active_rifts()
	var active_rift_descriptors := _active_rift_descriptors()
	var active_rift_generation := (
		int(active_rift_descriptors.back().get("generation", 0))
		if not active_rift_descriptors.is_empty()
		else 0
	)
	return {
		"stop_active": _time_stop_active,
		"stop_generation": _time_stop_source_sequence if _time_stop_active else 0,
		"stop_remaining_frames": _time_stop_remaining_frames,
		"stop_extension_remaining_frames": maxi(
			0,
			MAX_WEAPON_STOP_EXTENSION_FRAMES - _weapon_stop_extension_frames
		),
		"accelerate_active": _time_accelerate_active,
		"accelerate_generation": _time_accelerate_token if _time_accelerate_active else 0,
		"rewind_echo_available": (
			_rewind_weapon_window_remaining_frames > 0
			and not _rewind_weapon_window_claimed
		),
		"rewind_echo_generation": _rewind_weapon_window_generation,
		"rift_active": not _active_rifts.is_empty(),
		"rift_generation": active_rift_generation,
		"active_rift_count": _active_rifts.size(),
		"active_rifts": active_rift_descriptors,
	}


func weapon_replay_snapshot() -> Dictionary:
	return {
		"schema_version": WEAPON_REPLAY_SNAPSHOT_SCHEMA_VERSION,
		"time_energy_state": resource_state(&"time_energy"),
		"energy_regen_remainder": _energy_regen_remainder,
		"stop_active": _time_stop_active,
		"stop_source_sequence": _time_stop_source_sequence,
		"stop_source_id": str(_time_stop_source_id),
		"stop_remaining": _time_stop_remaining,
		"stop_extension_frames": _weapon_stop_extension_frames,
		"stop_extension_tokens": _weapon_stop_extension_tokens.duplicate(true),
		"rewind_window_remaining": _rewind_weapon_window_remaining,
		"rewind_window_generation": _rewind_weapon_window_generation,
		"rewind_window_claimed": _rewind_weapon_window_claimed,
	}


func begin_weapon_replay_restore_transaction() -> int:
	if _weapon_replay_restore_transaction_active:
		return 0
	var before := weapon_replay_snapshot()
	if not can_restore_weapon_replay_snapshot(before):
		return 0
	var transaction_token := _next_weapon_replay_restore_transaction_token
	_next_weapon_replay_restore_transaction_token += 1
	_weapon_replay_restore_transaction_active = true
	_weapon_replay_restore_transaction_token = transaction_token
	_weapon_replay_restore_transaction_before = before.duplicate(true)
	return transaction_token


func commit_weapon_replay_restore_transaction(transaction_token: int) -> bool:
	if (
		not _weapon_replay_restore_transaction_active
		or transaction_token <= 0
		or transaction_token != _weapon_replay_restore_transaction_token
	):
		return false
	var before := _weapon_replay_restore_transaction_before.duplicate(true)
	var after := weapon_replay_snapshot()
	if (
		before.is_empty()
		or after.is_empty()
		or not can_restore_weapon_replay_snapshot(before)
		or not can_restore_weapon_replay_snapshot(after)
	):
		if can_restore_weapon_replay_snapshot(before):
			_install_weapon_replay_snapshot_state(before)
		_clear_weapon_replay_restore_transaction()
		return false
	var previous_stop_source_id := StringName(str(before.get("stop_source_id", "")))
	var stop_projection_changed := _weapon_replay_stop_projection(before) != (
		_weapon_replay_stop_projection(after)
	)
	var energy_changed_during_transaction := float(
		(before.get("time_energy_state", {}) as Dictionary).get("current", energy)
	) != energy
	_clear_weapon_replay_restore_transaction()
	if stop_projection_changed:
		_reconcile_replay_time_stop_targets(previous_stop_source_id)
	if energy_changed_during_transaction:
		_publish_energy_changed(energy, max_energy)
	return true


func rollback_weapon_replay_restore_transaction(transaction_token: int) -> bool:
	if (
		not _weapon_replay_restore_transaction_active
		or transaction_token <= 0
		or transaction_token != _weapon_replay_restore_transaction_token
	):
		return false
	var before := _weapon_replay_restore_transaction_before.duplicate(true)
	if not can_restore_weapon_replay_snapshot(before):
		_clear_weapon_replay_restore_transaction()
		return false
	var restored := _install_weapon_replay_snapshot_state(before)
	_clear_weapon_replay_restore_transaction()
	return restored and weapon_replay_snapshot() == before


func can_restore_weapon_replay_snapshot(value: Dictionary) -> bool:
	if value.size() != WEAPON_REPLAY_SNAPSHOT_FIELDS.size():
		return false
	for field: String in WEAPON_REPLAY_SNAPSHOT_FIELDS:
		if not value.has(field):
			return false
	if (
		typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != WEAPON_REPLAY_SNAPSHOT_SCHEMA_VERSION
		or not value["time_energy_state"] is Dictionary
		or not can_restore_resource_state(
			&"time_energy",
			(value["time_energy_state"] as Dictionary).duplicate(true)
		)
		or typeof(value["energy_regen_remainder"]) != TYPE_INT
		or int(value["energy_regen_remainder"]) < 0
		or int(value["energy_regen_remainder"]) >= GAMEPLAY_FRAMES_PER_SECOND
		or typeof(value["stop_active"]) != TYPE_BOOL
		or typeof(value["stop_source_sequence"]) != TYPE_INT
		or int(value["stop_source_sequence"]) < 0
		or typeof(value["stop_source_id"]) not in [TYPE_STRING, TYPE_STRING_NAME]
		or typeof(value["stop_remaining"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["stop_remaining"]))
		or float(value["stop_remaining"]) < 0.0
		or typeof(value["stop_extension_frames"]) != TYPE_INT
		or int(value["stop_extension_frames"]) < 0
		or int(value["stop_extension_frames"]) > MAX_WEAPON_STOP_EXTENSION_FRAMES
		or not value["stop_extension_tokens"] is Dictionary
		or typeof(value["rewind_window_remaining"]) not in [TYPE_INT, TYPE_FLOAT]
		or not is_finite(float(value["rewind_window_remaining"]))
		or float(value["rewind_window_remaining"]) < 0.0
		or typeof(value["rewind_window_generation"]) != TYPE_INT
		or int(value["rewind_window_generation"]) < 0
		or typeof(value["rewind_window_claimed"]) != TYPE_BOOL
	):
		return false
	var stop_active := bool(value["stop_active"])
	if stop_active != (not str(value["stop_source_id"]).is_empty()):
		return false
	if stop_active:
		if int(value["stop_source_sequence"]) <= 0 or float(value["stop_remaining"]) <= 0.0:
			return false
	elif not is_zero_approx(float(value["stop_remaining"])):
		return false
	var stop_tokens := value["stop_extension_tokens"] as Dictionary
	for token_value: Variant in stop_tokens.keys():
		if (
			typeof(token_value) != TYPE_INT
			or int(token_value) <= 0
			or typeof(stop_tokens[token_value]) != TYPE_BOOL
			or not bool(stop_tokens[token_value])
		):
			return false
	if not stop_active and (int(value["stop_extension_frames"]) != 0 or not stop_tokens.is_empty()):
		return false
	var rewind_remaining := float(value["rewind_window_remaining"])
	var rewind_generation := int(value["rewind_window_generation"])
	var rewind_claimed := bool(value["rewind_window_claimed"])
	if rewind_remaining > 0.0 and (rewind_generation <= 0 or rewind_claimed):
		return false
	if rewind_claimed and (rewind_generation <= 0 or not is_zero_approx(rewind_remaining)):
		return false
	if rewind_generation == 0 and (not is_zero_approx(rewind_remaining) or rewind_claimed):
		return false
	return true


func restore_weapon_replay_snapshot(value: Dictionary) -> bool:
	if not can_restore_weapon_replay_snapshot(value):
		return false
	var before := weapon_replay_snapshot()
	if before == value:
		return true
	var energy_before := energy
	var previous_stop_source_id := _time_stop_source_id
	if not _install_weapon_replay_snapshot_state(value):
		_install_weapon_replay_snapshot_state(before)
		return false
	if not _weapon_replay_restore_transaction_active:
		_reconcile_replay_time_stop_targets(previous_stop_source_id)
	if energy != energy_before and not _weapon_replay_restore_transaction_active:
		_publish_energy_changed(energy, max_energy)
	return true


func _install_weapon_replay_snapshot_state(value: Dictionary) -> bool:
	var time_energy_state := value["time_energy_state"] as Dictionary
	energy = float(time_energy_state["current"])
	_resource_revision = int(time_energy_state["revision"])
	_energy_regen_remainder = int(value["energy_regen_remainder"])
	_time_stop_active = bool(value["stop_active"])
	_time_stop_source_sequence = int(value["stop_source_sequence"])
	_time_stop_source_id = StringName(str(value["stop_source_id"]))
	_set_time_stop_remaining_frames(
		_seconds_to_authoritative_frames(float(value["stop_remaining"]))
	)
	_weapon_stop_extension_frames = int(value["stop_extension_frames"])
	_weapon_stop_extension_tokens = (value["stop_extension_tokens"] as Dictionary).duplicate(true)
	_set_rewind_window_remaining_frames(
		_seconds_to_authoritative_frames(float(value["rewind_window_remaining"]))
	)
	_rewind_weapon_window_generation = int(value["rewind_window_generation"])
	_rewind_weapon_window_claimed = bool(value["rewind_window_claimed"])
	return weapon_replay_snapshot() == value


func _weapon_replay_stop_projection(value: Dictionary) -> Dictionary:
	return {
		"active": bool(value.get("stop_active", false)),
		"source_id": str(value.get("stop_source_id", "")),
		"remaining": float(value.get("stop_remaining", 0.0)),
	}


func _clear_weapon_replay_restore_transaction() -> void:
	_weapon_replay_restore_transaction_active = false
	_weapon_replay_restore_transaction_token = 0
	_weapon_replay_restore_transaction_before.clear()


func _reconcile_replay_time_stop_targets(previous_source_id: StringName) -> void:
	if previous_source_id != &"":
		for target: Node in _time_stop_targets.duplicate():
			if is_instance_valid(target) and target.has_method("clear_time_stop_source"):
				target.clear_time_stop_source(previous_source_id)
	_time_stop_targets.clear()
	if not _time_stop_active or _time_stop_source_id == &"" or _time_stop_remaining <= 0.0:
		return
	for node: Node in SceneScope.nodes_in_group(self, "time_stoppable"):
		if node.has_method("apply_time_stop_source"):
			node.apply_time_stop_source(_time_stop_source_id, _time_stop_remaining)
			_time_stop_targets.append(node)
		elif node.has_method("apply_time_stop"):
			node.apply_time_stop(_time_stop_remaining)


func extend_stop_for_weapon(action_token: int, extension_frames: int) -> bool:
	if (
		not _time_stop_active
		or action_token <= 0
		or extension_frames <= 0
		or _weapon_stop_extension_tokens.has(action_token)
	):
		return false
	var available := MAX_WEAPON_STOP_EXTENSION_FRAMES - _weapon_stop_extension_frames
	var granted := mini(extension_frames, available)
	if granted <= 0:
		return false
	_weapon_stop_extension_tokens[action_token] = true
	_weapon_stop_extension_frames += granted
	_set_time_stop_remaining_frames(_time_stop_remaining_frames + granted)
	return true


func claim_weapon_interaction(interaction_id: StringName, generation: int) -> bool:
	if interaction_id != &"bow_rewind_echo":
		return false
	if (
		generation <= 0
		or generation != _rewind_weapon_window_generation
		or _rewind_weapon_window_remaining_frames <= 0
		or _rewind_weapon_window_claimed
	):
		return false
	_rewind_weapon_window_claimed = true
	_set_rewind_window_remaining_frames(0)
	return true


func resource_state(resource_id: StringName) -> Dictionary:
	if resource_id != &"time_energy":
		return {
			"ok": false,
			"code": &"RESOURCE_NOT_FOUND",
			"context": {"resource_id": str(resource_id)},
		}
	return {
		"ok": true,
		"code": &"OK",
		"resource_id": "time_energy",
		"current": energy,
		"minimum": 0.0,
		"maximum": max_energy,
		"revision": _resource_revision,
		"context": {},
	}


func can_restore_resource_state(resource_id: StringName, state: Dictionary) -> bool:
	const RESOURCE_STATE_FIELDS: Array[String] = [
		"ok",
		"code",
		"resource_id",
		"current",
		"minimum",
		"maximum",
		"revision",
		"context",
	]
	if resource_id != &"time_energy" or state.size() != RESOURCE_STATE_FIELDS.size():
		return false
	for field: String in RESOURCE_STATE_FIELDS:
		if not state.has(field):
			return false
	for field: String in ["current", "minimum", "maximum"]:
		var value: Variant = state[field]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	return (
		typeof(state["ok"]) == TYPE_BOOL
		and bool(state["ok"])
		and typeof(state["code"]) in [TYPE_STRING, TYPE_STRING_NAME]
		and str(state["code"]) == "OK"
		and typeof(state["resource_id"]) in [TYPE_STRING, TYPE_STRING_NAME]
		and str(state["resource_id"]) == "time_energy"
		and float(state["minimum"]) == 0.0
		and float(state["maximum"]) == max_energy
		and float(state["current"]) >= 0.0
		and float(state["current"]) <= max_energy
		and typeof(state["revision"]) == TYPE_INT
		and int(state["revision"]) > 0
		and state["context"] is Dictionary
		and (state["context"] as Dictionary).is_empty()
	)


func try_spend_resource(
	resource_id: StringName,
	amount: float,
	expected_revision: int,
	reason: StringName
) -> Dictionary:
	if resource_id != &"time_energy":
		return {
			"ok": false,
			"code": &"RESOURCE_NOT_FOUND",
			"context": {"resource_id": str(resource_id)},
		}
	if not is_finite(amount) or amount < 0.0:
		return {
			"ok": false,
			"code": &"INVALID_RESOURCE_AMOUNT",
			"context": {"resource_id": str(resource_id)},
		}
	if expected_revision != _resource_revision:
		return {
			"ok": false,
			"code": &"RESOURCE_REVISION_MISMATCH",
			"context": {
				"resource_id": str(resource_id),
				"expected_revision": expected_revision,
				"actual_revision": _resource_revision,
			},
		}
	if energy < amount:
		return {
			"ok": false,
			"code": &"INSUFFICIENT_RESOURCE",
			"context": {
				"resource_id": str(resource_id),
				"required": amount,
				"current": energy,
			},
		}
	var before := energy
	if amount > 0.0:
		energy = maxf(0.0, energy - amount)
		_resource_revision += 1
		_publish_energy_changed(energy, max_energy)
	return {
		"ok": true,
		"code": &"OK",
		"resource_id": str(resource_id),
		"before": before,
		"after": energy,
		"revision": _resource_revision,
		"reason": str(reason),
		"context": {},
	}


func restore_resource_state(resource_id: StringName, state: Dictionary, publish_signal: bool = true) -> bool:
	if not can_restore_resource_state(resource_id, state):
		return false
	var energy_before := energy
	energy = float(state["current"])
	_resource_revision = int(state["revision"])
	if publish_signal and energy != energy_before and not _weapon_replay_restore_transaction_active:
		_publish_energy_changed(energy, max_energy)
	return true


func get_cooldown(skill_id: StringName) -> float:
	_refresh_cooldown_seconds_projection()
	return float(_cooldowns.get(skill_id, 0.0))


func reduce_longer_equipped_cooldown_frames(
	equipped_time_abilities: Array,
	amount_frames: int
) -> bool:
	if equipped_time_abilities.size() != 2 or amount_frames <= 0:
		return false
	var canonical_ids: Array[StringName] = []
	for ability_value: Variant in equipped_time_abilities:
		if typeof(ability_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var canonical := canonical_skill_id(StringName(str(ability_value)))
		var cooldown_id := action_skill_id(canonical)
		if cooldown_id == &"" or canonical_ids.has(cooldown_id):
			return false
		canonical_ids.append(cooldown_id)
	var selected := canonical_ids[0]
	if int(_cooldown_frames.get(canonical_ids[1], 0)) > int(
		_cooldown_frames.get(selected, 0)
	):
		selected = canonical_ids[1]
	var before := int(_cooldown_frames.get(selected, -1))
	if before < 0:
		return false
	var after := maxi(0, before - amount_frames)
	if not _set_cooldown_frames(selected, after):
		return false
	if after != before:
		_publish_cooldown_changed(selected, _frames_to_seconds(after))
	return true


func extend_boss_exposure_frames(
	stop_generation: int,
	amount_frames: int,
	target_identity: Dictionary = {}
) -> bool:
	if stop_generation <= 0 or amount_frames <= 0 or get_tree() == null:
		return false
	var bosses := _active_character_boss_exposure_targets(target_identity)
	if bosses.size() != 1:
		return false
	return bool(bosses[0].call(
		"extend_character_boss_exposure",
		stop_generation,
		amount_frames
	))


func active_boss_exposure_identity() -> Dictionary:
	var bosses := _active_character_boss_exposure_targets({})
	if bosses.size() != 1:
		return {}
	return (bosses[0].call("character_boss_exposure_identity") as Dictionary).duplicate(true)


func _active_character_boss_exposure_targets(target_identity: Dictionary) -> Array[Node]:
	var bosses: Array[Node] = []
	if get_tree() == null:
		return bosses
	for candidate: Node in SceneScope.nodes_in_group(self, "bosses"):
		if (
			not is_instance_valid(candidate)
			or candidate.is_queued_for_deletion()
			or not candidate.has_method("extend_character_boss_exposure")
			or not candidate.has_method("character_boss_exposure_identity")
		):
			continue
		var health := candidate.get_node_or_null("HealthComponent")
		if health == null or not health.has_method("is_alive") or not bool(health.call("is_alive")):
			continue
		var identity_value: Variant = candidate.call("character_boss_exposure_identity")
		if not identity_value is Dictionary or (identity_value as Dictionary).is_empty():
			continue
		var identity := identity_value as Dictionary
		if not target_identity.is_empty() and identity != target_identity:
			continue
		bosses.append(candidate)
	return bosses


func _regen_energy(delta: float) -> void:
	if energy >= max_energy:
		return
	var regen_multiplier := low_energy_regen_multiplier if energy < low_energy_threshold else 1.0
	var energy_before := energy
	energy = minf(max_energy, energy + energy_regen * regen_multiplier * _event_energy_regen_multiplier * delta)
	if energy != energy_before:
		_resource_revision += 1
	_publish_energy_changed(energy, max_energy)


func _regen_energy_fixed_frame() -> void:
	if energy >= max_energy:
		_energy_regen_remainder = 0
		return
	var regen_multiplier := low_energy_regen_multiplier if energy < low_energy_threshold else 1.0
	var scaled_per_second := roundi(energy_regen * regen_multiplier * _event_energy_regen_multiplier * float(ENERGY_FIXED_POINT_SCALE))
	if scaled_per_second <= 0:
		return
	var accumulated := _energy_regen_remainder + scaled_per_second
	var granted_units := accumulated / GAMEPLAY_FRAMES_PER_SECOND
	_energy_regen_remainder = accumulated % GAMEPLAY_FRAMES_PER_SECOND
	if granted_units <= 0:
		return
	var energy_before := energy
	energy = minf(max_energy, energy + float(granted_units) / float(ENERGY_FIXED_POINT_SCALE))
	if energy != energy_before:
		_resource_revision += 1
		_publish_energy_changed(energy, max_energy)
	if energy >= max_energy:
		_energy_regen_remainder = 0


func _tick_cooldowns() -> void:
	for skill_id: StringName in COOLDOWN_SKILL_IDS:
		var previous_frames := int(_cooldown_frames.get(skill_id, 0))
		if previous_frames <= 0:
			continue
		var remaining_frames := maxi(0, previous_frames - 1)
		_cooldown_frames[skill_id] = remaining_frames
		_cooldowns[skill_id] = _frames_to_seconds(remaining_frames)
		_publish_cooldown_changed(skill_id, _cooldowns[skill_id])


func _tick_active_effects(compatibility_delta: float = -FIXED_FRAME_SECONDS) -> void:
	var frame_count := 1
	if compatibility_delta >= 0.0:
		if not is_finite(compatibility_delta):
			return
		frame_count = _seconds_to_authoritative_frames(compatibility_delta)
	for _frame: int in range(frame_count):
		_tick_active_effects_one_frame()


func _tick_active_effects_one_frame() -> void:
	if _rewind_weapon_window_remaining_frames > 0:
		_set_rewind_window_remaining_frames(_rewind_weapon_window_remaining_frames - 1)
		if _rewind_weapon_window_remaining_frames <= 0:
			_rewind_weapon_window_claimed = true
	if _time_stop_active and _time_stop_remaining_frames > 0:
		_set_time_stop_remaining_frames(_time_stop_remaining_frames - 1)
		if _time_stop_remaining_frames <= 0:
			_end_time_stop(true)
	if _time_accelerate_active and _time_accelerate_remaining_frames > 0:
		var active_token := _time_accelerate_token
		_set_time_accelerate_remaining_frames(_time_accelerate_remaining_frames - 1)
		if _time_accelerate_remaining_frames <= 0:
			_end_time_accelerate(active_token, true)


func _clear_rewind_weapon_window() -> void:
	_set_rewind_window_remaining_frames(0)
	_rewind_weapon_window_claimed = false


func _can_pay(skill_id: StringName, cost: float) -> bool:
	return energy >= cost and get_cooldown(skill_id) <= 0.0


func _pay_cost(skill_id: StringName, cost: float, cooldown: float) -> void:
	var energy_before := energy
	energy = maxf(0.0, energy - cost)
	if energy != energy_before:
		_resource_revision += 1
	_set_cooldown_seconds(skill_id, cooldown)
	_publish_energy_changed(energy, max_energy)
	_publish_cooldown_changed(skill_id, get_cooldown(skill_id))


func _take_self_damage(amount: float, source_tag: StringName) -> bool:
	if amount <= 0.0:
		return true
	var owner_entity := get_parent()
	var health_component := owner_entity.get_node_or_null("HealthComponent")
	if health_component == null or not health_component.has_method("lose_health_irreversible"):
		return false
	var claim_token := _next_irreversible_self_damage_token
	var resolution: Variant = health_component.call(
		"lose_health_irreversible",
		amount,
		source_tag,
		claim_token,
		_irreversible_self_damage_generation
	)
	var committed := (
		resolution is RefCounted
		and not bool((resolution as RefCounted).call("is_prevented"))
		and float((resolution as RefCounted).call("finalized_damage")) > 0.0
	)
	if committed:
		_next_irreversible_self_damage_token += 1
	return committed


func _prune_active_rifts() -> void:
	var valid_rifts: Array[Node] = []
	var valid_generations: Dictionary = {}
	for rift_value: Variant in _active_rifts:
		if not is_instance_valid(rift_value):
			continue
		var rift := rift_value as Node
		if (
			rift == null
			or rift.is_queued_for_deletion()
			or (rift.has_method("is_finished") and bool(rift.call("is_finished")))
		):
			continue
		valid_rifts.append(rift)
		var generation := int(_active_rift_generations.get(rift, 0))
		if generation > 0:
			valid_generations[rift] = generation
	_active_rifts = valid_rifts
	_active_rift_generations = valid_generations


func _retire_active_rifts(reason: StringName) -> void:
	_prune_active_rifts()
	var owner_entity := get_parent()
	var run_id := (
		StringName(str(owner_entity.call("current_run_id")))
		if owner_entity != null and owner_entity.has_method("current_run_id")
		else &""
	)
	var owner_generation := (
		int(owner_entity.call("owner_character_generation"))
		if owner_entity != null and owner_entity.has_method("owner_character_generation")
		else 0
	)
	for rift_value: Variant in _active_rifts.duplicate():
		if not is_instance_valid(rift_value):
			continue
		var rift := rift_value as Node
		var retired := false
		if (
			rift != null
			and world_payload_authority != null
			and rift.has_meta(&"world_payload_id")
			and run_id != &""
			and owner_generation > 0
		):
			var retired_value: Variant = world_payload_authority.call(
				"retire_payload",
				StringName(str(rift.get_meta(&"world_payload_id"))),
				run_id,
				owner_generation,
				reason
			)
			retired = retired_value is Dictionary and bool(
				(retired_value as Dictionary).get("ok", false)
			)
		if not retired and rift != null and rift.has_method("cancel"):
			rift.call("cancel", reason != &"runtime_reset")
	_active_rifts.clear()
	_active_rift_generations.clear()


func _active_rift_descriptors() -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	for rift: Node in _active_rifts:
		var generation := int(_active_rift_generations.get(rift, 0))
		if generation <= 0 or not rift is Node2D:
			continue
		var radius_value: Variant = rift.get("radius")
		if typeof(radius_value) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var radius := float(radius_value)
		if not is_finite(radius) or radius <= 0.0:
			continue
		descriptors.append({
			"generation": generation,
			"center": (rift as Node2D).global_position,
			"radius": radius,
		})
	descriptors.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("generation", 0)) < int(right.get("generation", 0))
	)
	return descriptors


func _active_rift_payload_descriptors() -> Array[Dictionary]:
	var descriptors: Array[Dictionary] = []
	if world_payload_authority == null or not world_payload_authority.has_method("replay_snapshot"):
		return descriptors
	var snapshot_value: Variant = world_payload_authority.call("replay_snapshot")
	if not snapshot_value is Dictionary:
		return descriptors
	var descriptor_values: Variant = (snapshot_value as Dictionary).get("descriptors")
	if not descriptor_values is Array:
		return descriptors
	for descriptor_value: Variant in descriptor_values as Array:
		if (
			descriptor_value is Dictionary
			and StringName(str((descriptor_value as Dictionary).get("handler_id", ""))) == &"time_rift"
		):
			descriptors.append((descriptor_value as Dictionary).duplicate(true))
	return descriptors
