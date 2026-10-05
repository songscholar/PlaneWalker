class_name WorldPayloadAuthority
extends Node

const SceneScope := preload("res://scripts/player/player_scene_scope.gd")
const SCHEMA_VERSION := 1
const MAX_SEGMENT_LENGTH := 64
const MAX_PAYLOAD_ID_LENGTH := 320
const MAX_SET_ENTRY_LENGTH := 160
const MAX_DETERMINISTIC_DEPTH := 8

const DESCRIPTOR_FIELDS: Array[String] = [
	"payload_id",
	"handler_id",
	"run_id",
	"owner_character_generation",
	"payload_family",
	"source_token",
	"payload_generation",
	"transform",
	"geometry",
	"remaining_frames",
	"claims",
	"tags",
	"parameters",
]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_version",
	"revision",
	"invalidation_revision",
	"last_runtime_frame",
	"invalidated_generations",
	"descriptors",
]
const INVALIDATION_FIELDS: Array[String] = [
	"run_id",
	"owner_character_generation",
	"reason",
	"revision",
]
const TRANSACTION_RESTORE_TICKET_FIELDS: Array[String] = [
	"schema_version",
	"authority_instance_id",
	"ticket_id",
]
const FRAME_TRANSACTION_TICKET_FIELDS: Array[String] = [
	"schema_version",
	"authority_instance_id",
	"ticket_id",
	"runtime_frame",
]

var _active_root: Node
var _factories: Dictionary = {}
var _factory_owners: Dictionary = {}
var _descriptors: Dictionary = {}
var _nodes: Dictionary = {}
var _invalidated_generations: Dictionary = {}
var _revision: int = 0
var _invalidation_revision: int = 0
var _last_runtime_frame: int = -1
var _mutation_locked: bool = false
var _next_transaction_restore_ticket_id: int = 1
var _active_transaction_restore: Dictionary = {}
var _next_frame_transaction_ticket_id: int = 1
var _active_frame_transaction: Dictionary = {}
var _frame_transaction_commit_fault_for_test: bool = false


func _init() -> void:
	_active_root = Node.new()
	_active_root.name = "ActiveWorldPayloads"
	add_child(_active_root)


func register_factory(handler_id: StringName, factory: Callable) -> bool:
	if _mutation_locked or not _active_frame_transaction.is_empty():
		return false
	var normalized_handler := _normalized_segment(handler_id)
	if normalized_handler == &"" or not factory.is_valid():
		return false
	var key := str(normalized_handler)
	if _factories.has(key):
		return false
	_factories[key] = factory
	var factory_owner: Object = factory.get_object()
	if factory_owner != null:
		_factory_owners[key] = factory_owner
	return true


func commit_payload(value: Dictionary) -> Dictionary:
	if (
		_mutation_locked
		or not _active_transaction_restore.is_empty()
		or _frame_transaction_is_prepared()
	):
		return _failure(&"AUTHORITY_BUSY")
	var descriptor := _validated_descriptor(value)
	if descriptor.is_empty():
		return _failure(&"INVALID_DESCRIPTOR")
	var payload_id := str(descriptor["payload_id"])
	if _descriptors.has(payload_id):
		return _failure(&"DUPLICATE_PAYLOAD", payload_id)
	if _generation_is_invalidated_normalized(
		descriptor["run_id"] as StringName,
		int(descriptor["owner_character_generation"])
	):
		return _failure(&"INVALIDATED_GENERATION", payload_id)
	var handler_key := str(descriptor["handler_id"])
	if not _factories.has(handler_key):
		return _failure(&"UNKNOWN_HANDLER", payload_id)
	_mutation_locked = true
	var staged := _spawn_payload_node(descriptor)
	if not bool(staged.get("ok", false)):
		_mutation_locked = false
		return _failure(staged.get("code", &"SPAWN_FAILED") as StringName, payload_id)
	var node := staged["node"] as Node
	node.set_meta(&"world_payload_id", StringName(payload_id))
	_descriptors[payload_id] = descriptor
	_nodes[payload_id] = node
	_revision += 1
	_active_root.add_child(node)
	if not _active_frame_transaction.is_empty():
		var added_payloads := _active_frame_transaction.get(
			"added_payloads",
			{}
		) as Dictionary
		added_payloads[payload_id] = {
			"descriptor": descriptor.duplicate(true),
			"node": node,
			"should_advance": not bool(_active_frame_transaction.get(
				"advance_completed",
				false
			)),
		}
		_active_frame_transaction["added_payloads"] = added_payloads
	_mutation_locked = false
	return {
		"ok": true,
		"code": &"PAYLOAD_COMMITTED",
		"payload_id": payload_id,
		"revision": _revision,
	}


func contains(payload_id: StringName) -> bool:
	return _descriptors.has(str(payload_id))


func payload_node(payload_id: StringName) -> Node:
	var value: Variant = _nodes.get(str(payload_id))
	if value is Node and is_instance_valid(value):
		return value as Node
	return null


func payload_descriptor(payload_id: StringName) -> Dictionary:
	var value: Variant = _descriptors.get(str(payload_id))
	if not value is Dictionary:
		return {}
	return (value as Dictionary).duplicate(true)


func preserve_committed_for_gameplay_rewind() -> Dictionary:
	var payload_ids := _sorted_payload_ids()
	var instance_ids: Array[int] = []
	for payload_id: String in payload_ids:
		var node: Node = _nodes[payload_id] as Node
		instance_ids.append(node.get_instance_id())
	return {
		"ok": true,
		"code": &"COMMITTED_PAYLOADS_PRESERVED",
		"payload_ids": payload_ids,
		"node_instance_ids": instance_ids,
		"revision": _revision,
	}


func begin_frame_transaction(runtime_frame: int) -> Dictionary:
	if (
		_mutation_locked
		or not _active_transaction_restore.is_empty()
		or not _active_frame_transaction.is_empty()
		or runtime_frame < 0
		or runtime_frame != _last_runtime_frame + 1
	):
		return {}
	var frame_snapshots: Dictionary = {}
	var before_nodes: Dictionary = {}
	for payload_id: String in _sorted_payload_ids():
		var node_value: Variant = _nodes.get(payload_id)
		if (
			not node_value is Node
			or not is_instance_valid(node_value)
			or not (node_value as Node).has_method("world_payload_frame_snapshot")
		):
			return {}
		var snapshot_value: Variant = (node_value as Node).call(
			"world_payload_frame_snapshot"
		)
		if not snapshot_value is Dictionary:
			return {}
		frame_snapshots[payload_id] = (snapshot_value as Dictionary).duplicate(true)
		before_nodes[payload_id] = node_value as Node
	var ticket := {
		"schema_version": SCHEMA_VERSION,
		"authority_instance_id": get_instance_id(),
		"ticket_id": _next_frame_transaction_ticket_id,
		"runtime_frame": runtime_frame,
	}
	_next_frame_transaction_ticket_id += 1
	_active_frame_transaction = {
		"ticket": ticket.duplicate(true),
		"before": replay_snapshot(),
		"before_nodes": before_nodes,
		"frame_snapshots": frame_snapshots,
		"stashed_descriptors": {},
		"stashed_nodes": {},
		"added_payloads": {},
		"advance_completed": false,
		"commit_prepared": false,
	}
	return ticket.duplicate(true)


func can_commit_frame_transaction(ticket: Dictionary) -> bool:
	if not _frame_transaction_ticket_matches(ticket):
		return false
	if bool(_active_frame_transaction.get("commit_prepared", false)):
		return true
	if not _frame_transaction_commit_conditions_are_valid():
		return false
	_active_frame_transaction["commit_prepared"] = true
	return true


func commit_frame_transaction(ticket: Dictionary) -> bool:
	if not _frame_transaction_ticket_matches(ticket):
		return false
	if (
		not bool(_active_frame_transaction.get("commit_prepared", false))
		and not can_commit_frame_transaction(ticket)
	):
		return false
	if _frame_transaction_commit_fault_for_test:
		return false
	var stashed_nodes := _active_frame_transaction.get("stashed_nodes", {}) as Dictionary
	_active_frame_transaction.clear()
	_mutation_locked = true
	for payload_id: String in _sorted_dictionary_keys(stashed_nodes):
		var node_value: Variant = stashed_nodes[payload_id]
		if not node_value is Node or not is_instance_valid(node_value):
			continue
		var node := node_value as Node
		if node.has_method("retire_world_payload"):
			node.call("retire_world_payload", &"expired")
		_dispose_detached(node)
	_mutation_locked = false
	return true


func rollback_frame_transaction(ticket: Dictionary) -> bool:
	if not _frame_transaction_ticket_matches(ticket):
		return false
	if not _frame_transaction_rollback_conditions_are_valid():
		return false
	var before := _active_frame_transaction.get("before", {}) as Dictionary
	var before_nodes := _active_frame_transaction.get("before_nodes", {}) as Dictionary
	var frame_snapshots := _active_frame_transaction.get("frame_snapshots", {}) as Dictionary
	var added_payloads := _active_frame_transaction.get("added_payloads", {}) as Dictionary
	if not _restore_transaction_begin_node_snapshots(before_nodes, frame_snapshots):
		return false

	var added_nodes: Array[Node] = []
	for payload_id: String in _sorted_dictionary_keys(added_payloads):
		var record := added_payloads[payload_id] as Dictionary
		added_nodes.append(record["node"] as Node)

	_descriptors.clear()
	_nodes.clear()
	for descriptor_value: Variant in before.get("descriptors", []) as Array:
		var descriptor := descriptor_value as Dictionary
		var payload_id := str(descriptor.get("payload_id", ""))
		var node := before_nodes[payload_id] as Node
		_descriptors[payload_id] = descriptor.duplicate(true)
		_nodes[payload_id] = node
		if node.get_parent() == null:
			_active_root.add_child(node)
	_revision = int(before.get("revision", _revision))
	_invalidation_revision = int(before.get(
		"invalidation_revision",
		_invalidation_revision
	))
	_last_runtime_frame = int(before.get("last_runtime_frame", _last_runtime_frame))
	_active_frame_transaction.clear()
	_mutation_locked = true
	for node: Node in added_nodes:
		_dispose_detached(node)
	_mutation_locked = false
	return replay_snapshot() == before


func advance_frame(runtime_frame: int) -> Dictionary:
	if _mutation_locked or _frame_transaction_is_prepared():
		return _failure(&"AUTHORITY_BUSY")
	if (
		not _active_frame_transaction.is_empty()
		and int((
			_active_frame_transaction.get("ticket", {}) as Dictionary
		).get("runtime_frame", -1)) != runtime_frame
	):
		return _failure(&"FRAME_TRANSACTION_MISMATCH")
	if runtime_frame < 0 or runtime_frame != _last_runtime_frame + 1:
		return _failure(&"STALE_FRAME")
	var payload_ids := _sorted_payload_ids()
	var frame_snapshots: Dictionary = {}
	for payload_id: String in payload_ids:
		var node_value: Variant = _nodes.get(payload_id)
		if not node_value is Node or not is_instance_valid(node_value):
			return _failure(&"PAYLOAD_NODE_MISSING", payload_id)
		var node := node_value as Node
		if (
			not node.has_method("advance_frame")
			or not node.has_method("world_payload_frame_snapshot")
			or not node.has_method("restore_world_payload_frame_snapshot")
		):
			return _failure(&"PAYLOAD_FRAME_CONTRACT_MISSING", payload_id)
		var frame_snapshot_value: Variant = node.call("world_payload_frame_snapshot")
		if not frame_snapshot_value is Dictionary:
			return _failure(&"PAYLOAD_FRAME_SNAPSHOT_REJECTED", payload_id)
		frame_snapshots[payload_id] = (frame_snapshot_value as Dictionary).duplicate(true)

	_mutation_locked = true
	for payload_id: String in payload_ids:
		var node := _nodes[payload_id] as Node
		var advanced_value: Variant = node.call("advance_frame", runtime_frame)
		if typeof(advanced_value) != TYPE_BOOL or not bool(advanced_value):
			var rolled_back := _restore_payload_frame_snapshots(
				payload_ids,
				frame_snapshots
			)
			_mutation_locked = false
			return _failure(
				&"PAYLOAD_FRAME_REJECTED" if rolled_back else &"PAYLOAD_FRAME_ROLLBACK_FAILED",
				payload_id
			)

	var elapsed_frames := 1
	var expired_ids: Array[String] = []
	var updated_ids: Array[String] = []
	for payload_id: String in payload_ids:
		var descriptor := _descriptors[payload_id] as Dictionary
		var remaining_frames := int(descriptor["remaining_frames"]) - elapsed_frames
		if remaining_frames <= 0:
			expired_ids.append(payload_id)
			continue
		descriptor["remaining_frames"] = remaining_frames
		_descriptors[payload_id] = descriptor
		updated_ids.append(payload_id)
	for payload_id: String in expired_ids:
		if _active_frame_transaction.is_empty():
			_remove_payload_internal(payload_id, &"expired")
		else:
			_stage_expired_payload_for_frame_transaction(payload_id)
	_last_runtime_frame = runtime_frame
	_revision += 1
	if not _active_frame_transaction.is_empty():
		_active_frame_transaction["advance_completed"] = true
	_mutation_locked = false
	return {
		"ok": true,
		"code": &"FRAME_ADVANCED",
		"runtime_frame": runtime_frame,
		"elapsed_frames": elapsed_frames,
		"updated_ids": updated_ids,
		"expired_ids": expired_ids,
		"revision": _revision,
	}


func _stage_expired_payload_for_frame_transaction(payload_id: String) -> void:
	var node_value: Variant = _nodes.get(payload_id)
	var descriptor_value: Variant = _descriptors.get(payload_id)
	_nodes.erase(payload_id)
	_descriptors.erase(payload_id)
	if not node_value is Node or not descriptor_value is Dictionary:
		return
	var node := node_value as Node
	var stashed_descriptors := _active_frame_transaction.get(
		"stashed_descriptors",
		{}
	) as Dictionary
	var stashed_nodes := _active_frame_transaction.get("stashed_nodes", {}) as Dictionary
	stashed_descriptors[payload_id] = (descriptor_value as Dictionary).duplicate(true)
	stashed_nodes[payload_id] = node
	_active_frame_transaction["stashed_descriptors"] = stashed_descriptors
	_active_frame_transaction["stashed_nodes"] = stashed_nodes
	if node.get_parent() != null:
		node.get_parent().remove_child(node)


func retire_payload(
	payload_id: StringName,
	callback_run_id: StringName,
	callback_owner_character_generation: int,
	reason: StringName
) -> Dictionary:
	if _mutation_locked or not _active_frame_transaction.is_empty():
		return _failure(&"AUTHORITY_BUSY", str(payload_id))
	var normalized_run_id := _normalized_segment(callback_run_id)
	var normalized_reason := _normalized_segment(reason)
	if (
		normalized_run_id == &""
		or callback_owner_character_generation <= 0
		or normalized_reason == &""
	):
		return _failure(&"INVALID_CALLBACK", str(payload_id))
	if _generation_is_invalidated_normalized(
		normalized_run_id,
		callback_owner_character_generation
	):
		return _failure(&"STALE_CALLBACK", str(payload_id))
	var key := str(payload_id)
	var descriptor_value: Variant = _descriptors.get(key)
	if not descriptor_value is Dictionary:
		return _failure(&"PAYLOAD_NOT_FOUND", key)
	var descriptor := descriptor_value as Dictionary
	if (
		descriptor["run_id"] != normalized_run_id
		or int(descriptor["owner_character_generation"])
		!= callback_owner_character_generation
	):
		return _failure(&"STALE_CALLBACK", key)
	_mutation_locked = true
	_remove_payload_internal(key, normalized_reason)
	_revision += 1
	_mutation_locked = false
	return {
		"ok": true,
		"code": &"PAYLOAD_RETIRED",
		"payload_id": key,
		"reason": normalized_reason,
		"revision": _revision,
	}


func invalidate_generation(
	run_id: StringName,
	owner_character_generation: int,
	reason: StringName
) -> Dictionary:
	if _mutation_locked or not _active_frame_transaction.is_empty():
		return _invalidation_failure(&"AUTHORITY_BUSY")
	var normalized_run_id := _normalized_segment(run_id)
	var normalized_reason := _normalized_segment(reason)
	if normalized_run_id == &"":
		return _invalidation_failure(&"INVALID_RUN_ID")
	if owner_character_generation <= 0:
		return _invalidation_failure(&"INVALID_GENERATION")
	if normalized_reason == &"":
		return _invalidation_failure(&"INVALID_REASON")
	if _generation_is_invalidated_normalized(
		normalized_run_id,
		owner_character_generation
	):
		return _invalidation_failure(&"GENERATION_ALREADY_INVALIDATED")

	var removed_ids: Array[String] = []
	for payload_id: String in _sorted_payload_ids():
		var descriptor := _descriptors[payload_id] as Dictionary
		if (
			descriptor["run_id"] == normalized_run_id
			and int(descriptor["owner_character_generation"])
			<= owner_character_generation
		):
			removed_ids.append(payload_id)
	_mutation_locked = true
	_invalidation_revision += 1
	_invalidated_generations[str(normalized_run_id)] = {
		"run_id": normalized_run_id,
		"owner_character_generation": owner_character_generation,
		"reason": normalized_reason,
		"revision": _invalidation_revision,
	}
	_revision += 1
	for payload_id: String in removed_ids:
		_remove_payload_internal(payload_id, normalized_reason)
	_mutation_locked = false
	return {
		"ok": true,
		"code": &"GENERATION_INVALIDATED",
		"run_id": normalized_run_id,
		"owner_character_generation": owner_character_generation,
		"reason": normalized_reason,
		"removed_ids": removed_ids,
		"revision": _revision,
		"invalidation_revision": _invalidation_revision,
	}


func can_invalidate_generation(
	run_id: StringName,
	owner_character_generation: int,
	reason: StringName
) -> bool:
	if _mutation_locked or not _active_frame_transaction.is_empty():
		return false
	var normalized_run_id := _normalized_segment(run_id)
	var normalized_reason := _normalized_segment(reason)
	if (
		normalized_run_id == &""
		or owner_character_generation <= 0
		or normalized_reason == &""
	):
		return false
	return not _generation_is_invalidated_normalized(
		normalized_run_id,
		owner_character_generation
	)


func first_available_generation(
	run_id: StringName,
	minimum_generation: int = 1
) -> int:
	var normalized_run_id := _normalized_segment(run_id)
	if normalized_run_id == &"" or minimum_generation <= 0:
		return 0
	var candidate := minimum_generation
	var watermark_value: Variant = _invalidated_generations.get(str(normalized_run_id))
	if watermark_value is Dictionary:
		var watermark := int((watermark_value as Dictionary).get(
			"owner_character_generation",
			0
		))
		if candidate <= watermark:
			candidate = watermark + 1
			if candidate <= 0:
				return 0
	return candidate


func can_reset_generation_runtime(
	run_id: StringName,
	owner_character_generation: int,
	reason: StringName
) -> bool:
	if (
		_mutation_locked
		or not _active_frame_transaction.is_empty()
		or not _active_transaction_restore.is_empty()
	):
		return false
	var normalized_run_id := _normalized_segment(run_id)
	var normalized_reason := _normalized_segment(reason)
	if (
		normalized_run_id == &""
		or owner_character_generation <= 0
		or normalized_reason == &""
	):
		return false
	for descriptor_value: Variant in _descriptors.values():
		if not descriptor_value is Dictionary:
			return false
		var descriptor := descriptor_value as Dictionary
		if (
			descriptor.get("run_id") != normalized_run_id
			or int(descriptor.get("owner_character_generation", 0))
			!= owner_character_generation
		):
			return false
	return first_available_generation(
		normalized_run_id,
		owner_character_generation + 1
	) > 0


func replay_snapshot() -> Dictionary:
	var descriptors: Array[Dictionary] = []
	for payload_id: String in _sorted_payload_ids():
		descriptors.append((_descriptors[payload_id] as Dictionary).duplicate(true))
	var invalidations: Array[Dictionary] = []
	for invalidation_value: Variant in _invalidated_generations.values():
		if invalidation_value is Dictionary:
			invalidations.append((invalidation_value as Dictionary).duplicate(true))
	invalidations.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _generation_key(
			left["run_id"] as StringName,
			int(left["owner_character_generation"])
		) < _generation_key(
			right["run_id"] as StringName,
			int(right["owner_character_generation"])
		)
	)
	return {
		"schema_version": SCHEMA_VERSION,
		"revision": _revision,
		"invalidation_revision": _invalidation_revision,
		"last_runtime_frame": _last_runtime_frame,
		"invalidated_generations": invalidations,
		"descriptors": descriptors,
	}


func restore_replay_snapshot(value: Dictionary) -> bool:
	if not can_restore_replay_snapshot(value):
		return false
	var validated := _validated_replay_snapshot(value)
	if replay_snapshot() == value:
		return true
	var candidate_invalidations := validated["invalidated_generations_by_key"] as Dictionary
	if not _can_restore_invalidation_history(candidate_invalidations):
		return false

	_mutation_locked = true
	var staging_root := Node.new()
	staging_root.name = "StagedWorldPayloads"
	var staged_nodes: Dictionary = {}
	var candidate_descriptors := validated["descriptors"] as Array
	for descriptor_value: Variant in candidate_descriptors:
		var descriptor := descriptor_value as Dictionary
		var handler_key := str(descriptor["handler_id"])
		if not _factories.has(handler_key):
			_dispose_detached(staging_root)
			_mutation_locked = false
			return false
		var staged := _spawn_payload_node(descriptor)
		if not bool(staged.get("ok", false)):
			_dispose_detached(staging_root)
			_mutation_locked = false
			return false
		var node := staged["node"] as Node
		var payload_id := str(descriptor["payload_id"])
		node.set_meta(&"world_payload_id", StringName(payload_id))
		staging_root.add_child(node)
		staged_nodes[payload_id] = node

	var old_root := _active_root
	var old_nodes := _nodes.duplicate()
	if old_root.get_parent() == self:
		remove_child(old_root)
	_active_root = staging_root
	_active_root.name = "ActiveWorldPayloads"
	_descriptors.clear()
	for descriptor_value: Variant in candidate_descriptors:
		var descriptor := descriptor_value as Dictionary
		_descriptors[str(descriptor["payload_id"])] = descriptor.duplicate(true)
	_nodes = staged_nodes
	_invalidated_generations = candidate_invalidations.duplicate(true)
	_revision = int(validated["revision"])
	_invalidation_revision = int(validated["invalidation_revision"])
	_last_runtime_frame = int(validated["last_runtime_frame"])
	add_child(staging_root)
	for old_node_value: Variant in old_nodes.values():
		if old_node_value is Node and is_instance_valid(old_node_value):
			var old_node := old_node_value as Node
			if old_node.has_method("retire_world_payload"):
				old_node.call("retire_world_payload", &"replay_replaced")
	_dispose_detached(old_root)
	_mutation_locked = false
	return true


func _can_restore_invalidation_history(candidate: Dictionary) -> bool:
	# A private, disabled viewer may seek across Rewind; live worlds retain history.
	var world := SceneScope.replay_world(self)
	var player := get_parent()
	if (
		world != null
		and world.get_script() == SceneScope.ReplayWorld
		and world.isolation_valid()
		and player is Node2D
		and player.is_inside_tree()
		and not player.is_queued_for_deletion()
		and world.owns_player(player)
		and player.process_mode == Node.PROCESS_MODE_DISABLED
		and not player.is_physics_processing()
		and player.get("_hostile_frame_participant") == null
		and player.get("world_payload_authority") == self
	):
		return true
	for current_key: Variant in _invalidated_generations.keys():
		if not candidate.has(current_key) or candidate[current_key] != _invalidated_generations[current_key]:
			return false
	return true


func can_restore_replay_snapshot(value: Dictionary) -> bool:
	if (
		_mutation_locked
		or not _active_frame_transaction.is_empty()
		or not _active_transaction_restore.is_empty()
	):
		return false
	var validated := _validated_replay_snapshot(value)
	if validated.is_empty():
		return false
	var candidate_invalidations := validated["invalidated_generations_by_key"] as Dictionary
	if not _can_restore_invalidation_history(candidate_invalidations):
		return false
	for descriptor_value: Variant in validated["descriptors"] as Array:
		var descriptor := descriptor_value as Dictionary
		if not _factories.has(str(descriptor["handler_id"])):
			return false
	return true


func restore_transaction_snapshot(value: Dictionary) -> bool:
	var ticket := begin_transaction_restore(value)
	if ticket.is_empty():
		return false
	if commit_transaction_restore(ticket):
		return true
	rollback_transaction_restore(ticket)
	return false


func begin_transaction_restore(value: Dictionary) -> Dictionary:
	if (
		_mutation_locked
		or not _active_transaction_restore.is_empty()
		or not _active_frame_transaction.is_empty()
	):
		return {}
	var validated := _validated_replay_snapshot(value)
	if validated.is_empty():
		return {}
	var candidate_invalidations := validated["invalidated_generations_by_key"] as Dictionary
	if not _can_restore_invalidation_history(candidate_invalidations):
		return {}

	var candidate_descriptors_by_id: Dictionary = {}
	for descriptor_value: Variant in validated["descriptors"] as Array:
		var descriptor := descriptor_value as Dictionary
		var payload_id := str(descriptor["payload_id"])
		candidate_descriptors_by_id[payload_id] = descriptor
		if not _factories.has(str(descriptor["handler_id"])):
			return {}

	var replaced_payload_ids: Array[String] = []
	for payload_id: String in _sorted_payload_ids():
		var current_node_value: Variant = _nodes.get(payload_id)
		if not _is_live_transaction_node(current_node_value):
			return {}
		if (
			not candidate_descriptors_by_id.has(payload_id)
			or candidate_descriptors_by_id[payload_id] != _descriptors[payload_id]
		):
			replaced_payload_ids.append(payload_id)

	var before := replay_snapshot()
	var before_invalidated_generations := _invalidated_generations.duplicate(true)
	var stashed_descriptors: Dictionary = {}
	var stashed_nodes: Dictionary = {}
	var spawned_nodes: Dictionary = {}
	_mutation_locked = true
	for payload_id: String in _sorted_dictionary_keys(candidate_descriptors_by_id):
		var descriptor := candidate_descriptors_by_id[payload_id] as Dictionary
		if (
			_descriptors.get(payload_id) is Dictionary
			and _descriptors[payload_id] == descriptor
			and _is_live_transaction_node(_nodes.get(payload_id))
		):
			continue
		var staged := _spawn_payload_node(descriptor)
		if not bool(staged.get("ok", false)):
			for spawned_value: Variant in spawned_nodes.values():
				if spawned_value is Node and is_instance_valid(spawned_value):
					_dispose_detached(spawned_value as Node)
			_mutation_locked = false
			return {}
		var spawned := staged["node"] as Node
		spawned.set_meta(&"world_payload_id", StringName(payload_id))
		spawned_nodes[payload_id] = spawned
	for payload_id: String in replaced_payload_ids:
		var node := _nodes[payload_id] as Node
		stashed_descriptors[payload_id] = (
			_descriptors[payload_id] as Dictionary
		).duplicate(true)
		stashed_nodes[payload_id] = node
		_nodes.erase(payload_id)
		_descriptors.erase(payload_id)
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
	for payload_id: String in _sorted_dictionary_keys(spawned_nodes):
		var descriptor := candidate_descriptors_by_id[payload_id] as Dictionary
		var node := spawned_nodes[payload_id] as Node
		_descriptors[payload_id] = descriptor.duplicate(true)
		_nodes[payload_id] = node
		_active_root.add_child(node)
	_invalidated_generations = candidate_invalidations.duplicate(true)
	_revision = int(validated["revision"])
	_invalidation_revision = int(validated["invalidation_revision"])
	_last_runtime_frame = int(validated["last_runtime_frame"])

	var ticket_id := _next_transaction_restore_ticket_id
	_next_transaction_restore_ticket_id += 1
	var ticket := {
		"schema_version": SCHEMA_VERSION,
		"authority_instance_id": get_instance_id(),
		"ticket_id": ticket_id,
	}
	_active_transaction_restore = {
		"ticket": ticket.duplicate(true),
		"before": before,
		"target": value.duplicate(true),
		"stashed_descriptors": stashed_descriptors,
		"stashed_nodes": stashed_nodes,
		"spawned_nodes": spawned_nodes,
		"before_invalidated_generations": before_invalidated_generations,
	}
	if replay_snapshot() != value:
		_rollback_active_transaction_restore()
		return {}
	return ticket


func commit_transaction_restore(ticket: Dictionary) -> bool:
	if not _transaction_restore_ticket_matches(ticket):
		return false
	var target := _active_transaction_restore["target"] as Dictionary
	if replay_snapshot() != target or not _active_transaction_target_nodes_are_live():
		return false
	var stashed_nodes := _active_transaction_restore["stashed_nodes"] as Dictionary
	for payload_id: String in _sorted_dictionary_keys(stashed_nodes):
		var node_value: Variant = stashed_nodes[payload_id]
		if not _is_live_transaction_node(node_value) or (node_value as Node).get_parent() != null:
			return false
	for payload_id: String in _sorted_dictionary_keys(stashed_nodes):
		var node_value: Variant = stashed_nodes[payload_id]
		if node_value is Node and is_instance_valid(node_value):
			var node := node_value as Node
			if node.has_method("retire_world_payload"):
				node.call("retire_world_payload", &"transaction_rollback")
			_dispose_detached(node)
	_active_transaction_restore.clear()
	_mutation_locked = false
	return true


func rollback_transaction_restore(ticket: Dictionary) -> bool:
	if not _transaction_restore_ticket_matches(ticket):
		return false
	return _rollback_active_transaction_restore()


func _spawn_payload_node(descriptor: Dictionary) -> Dictionary:
	var handler_key := str(descriptor["handler_id"])
	if not _factories.has(handler_key):
		return {"ok": false, "code": &"UNKNOWN_HANDLER"}
	var factory := _factories[handler_key] as Callable
	var spawned: Variant = factory.call(descriptor.duplicate(true))
	if not spawned is Node:
		return {"ok": false, "code": &"SPAWN_FAILED"}
	var node := spawned as Node
	if not is_instance_valid(node) or node.get_parent() != null or node.is_queued_for_deletion():
		return {"ok": false, "code": &"INVALID_SPAWN"}
	return {"ok": true, "node": node}


func reset_runtime_clock() -> bool:
	if (
		_mutation_locked
		or not _active_frame_transaction.is_empty()
		or not _active_transaction_restore.is_empty()
		or not _descriptors.is_empty()
	):
		return false
	_last_runtime_frame = 0
	_revision += 1
	return true


func reanchor_empty_runtime_clock(runtime_frame: int) -> bool:
	if (
		_mutation_locked
		or not _active_frame_transaction.is_empty()
		or not _active_transaction_restore.is_empty()
		or not _descriptors.is_empty()
		or runtime_frame < -1
	):
		return false
	if _last_runtime_frame == runtime_frame:
		return true
	_last_runtime_frame = runtime_frame
	_revision += 1
	return true


func generation_is_invalidated(
	run_id: StringName,
	owner_character_generation: int
) -> bool:
	var normalized_run_id := _normalized_segment(run_id)
	if normalized_run_id == &"" or owner_character_generation <= 0:
		return false
	return _generation_is_invalidated_normalized(
		normalized_run_id,
		owner_character_generation
	)


func _generation_is_invalidated_normalized(
	normalized_run_id: StringName,
	owner_character_generation: int
) -> bool:
	var watermark_value: Variant = _invalidated_generations.get(str(normalized_run_id))
	return (
		watermark_value is Dictionary
		and owner_character_generation
		<= int((watermark_value as Dictionary).get(
			"owner_character_generation",
			0
		))
	)


func _remove_payload_internal(payload_id: String, reason: StringName) -> void:
	var node_value: Variant = _nodes.get(payload_id)
	_nodes.erase(payload_id)
	_descriptors.erase(payload_id)
	if not node_value is Node or not is_instance_valid(node_value):
		return
	var node := node_value as Node
	if node.has_method("retire_world_payload"):
		node.call("retire_world_payload", reason)
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	_dispose_detached(node)


func _restore_payload_frame_snapshots(
	payload_ids: Array[String],
	frame_snapshots: Dictionary
) -> bool:
	var restored_all := true
	for payload_id: String in payload_ids:
		var node_value: Variant = _nodes.get(payload_id)
		var snapshot_value: Variant = frame_snapshots.get(payload_id)
		if (
			not node_value is Node
			or not is_instance_valid(node_value)
			or not snapshot_value is Dictionary
		):
			restored_all = false
			continue
		var restored_value: Variant = (node_value as Node).call(
			"restore_world_payload_frame_snapshot",
			(snapshot_value as Dictionary).duplicate(true)
		)
		if typeof(restored_value) != TYPE_BOOL or not bool(restored_value):
			restored_all = false
	return restored_all


func _frame_transaction_is_prepared() -> bool:
	return (
		not _active_frame_transaction.is_empty()
		and bool(_active_frame_transaction.get("commit_prepared", false))
	)


func _frame_transaction_commit_conditions_are_valid() -> bool:
	if (
		_mutation_locked
		or _active_frame_transaction.is_empty()
		or not bool(_active_frame_transaction.get("advance_completed", false))
	):
		return false
	var ticket := _active_frame_transaction.get("ticket", {}) as Dictionary
	var before := _active_frame_transaction.get("before", {}) as Dictionary
	var before_nodes := _active_frame_transaction.get("before_nodes", {}) as Dictionary
	var added_payloads := _active_frame_transaction.get("added_payloads", {}) as Dictionary
	var stashed_descriptors := _active_frame_transaction.get(
		"stashed_descriptors",
		{}
	) as Dictionary
	var stashed_nodes := _active_frame_transaction.get("stashed_nodes", {}) as Dictionary
	if (
		int(ticket.get("runtime_frame", -1)) != _last_runtime_frame
		or int(before.get("invalidation_revision", -1)) != _invalidation_revision
		or before.get("invalidated_generations", [])
		!= replay_snapshot().get("invalidated_generations", [])
		or int(before.get("revision", -1)) + added_payloads.size() + 1
		!= _revision
		or stashed_descriptors.size() != stashed_nodes.size()
	):
		return false

	var expected_live_descriptors: Dictionary = {}
	var expected_live_nodes: Dictionary = {}
	var expected_stashed_descriptors: Dictionary = {}
	var expected_stashed_nodes: Dictionary = {}
	for descriptor_value: Variant in before.get("descriptors", []) as Array:
		if not descriptor_value is Dictionary:
			return false
		var descriptor := (descriptor_value as Dictionary).duplicate(true)
		var payload_id := str(descriptor.get("payload_id", ""))
		var node_value: Variant = before_nodes.get(payload_id)
		if not _is_live_transaction_node(node_value):
			return false
		if int(descriptor.get("remaining_frames", 0)) <= 1:
			expected_stashed_descriptors[payload_id] = descriptor
			expected_stashed_nodes[payload_id] = node_value
		else:
			descriptor["remaining_frames"] = int(descriptor["remaining_frames"]) - 1
			expected_live_descriptors[payload_id] = descriptor
			expected_live_nodes[payload_id] = node_value

	for payload_id: String in _sorted_dictionary_keys(added_payloads):
		var record_value: Variant = added_payloads[payload_id]
		if not record_value is Dictionary:
			return false
		var record := record_value as Dictionary
		if (
			not record.get("descriptor") is Dictionary
			or not _is_live_transaction_node(record.get("node"))
			or typeof(record.get("should_advance")) != TYPE_BOOL
		):
			return false
		var descriptor := (record["descriptor"] as Dictionary).duplicate(true)
		if str(descriptor.get("payload_id", "")) != payload_id:
			return false
		var node_value: Variant = record["node"]
		if bool(record["should_advance"]):
			if int(descriptor.get("remaining_frames", 0)) <= 1:
				expected_stashed_descriptors[payload_id] = descriptor
				expected_stashed_nodes[payload_id] = node_value
				continue
			descriptor["remaining_frames"] = int(descriptor["remaining_frames"]) - 1
		expected_live_descriptors[payload_id] = descriptor
		expected_live_nodes[payload_id] = node_value

	if (
		expected_live_descriptors != _descriptors
		or expected_live_descriptors.size() != _nodes.size()
		or expected_stashed_descriptors != stashed_descriptors
		or expected_stashed_nodes.size() != stashed_nodes.size()
	):
		return false
	for payload_id: String in _sorted_dictionary_keys(expected_live_nodes):
		var node_value: Variant = _nodes.get(payload_id)
		if (
			node_value != expected_live_nodes[payload_id]
			or not _is_live_transaction_node(node_value)
			or (node_value as Node).get_parent() != _active_root
		):
			return false
	for payload_id: String in _sorted_dictionary_keys(expected_stashed_nodes):
		var node_value: Variant = stashed_nodes.get(payload_id)
		if (
			node_value != expected_stashed_nodes[payload_id]
			or not _is_live_transaction_node(node_value)
			or (node_value as Node).get_parent() != null
		):
			return false
	return true


func _frame_transaction_rollback_conditions_are_valid() -> bool:
	if _mutation_locked or _active_frame_transaction.is_empty():
		return false
	var ticket := _active_frame_transaction.get("ticket", {}) as Dictionary
	var before := _active_frame_transaction.get("before", {}) as Dictionary
	var before_nodes := _active_frame_transaction.get("before_nodes", {}) as Dictionary
	var added_payloads := _active_frame_transaction.get("added_payloads", {}) as Dictionary
	var stashed_descriptors := _active_frame_transaction.get(
		"stashed_descriptors",
		{}
	) as Dictionary
	var stashed_nodes := _active_frame_transaction.get("stashed_nodes", {}) as Dictionary
	var advance_completed := bool(_active_frame_transaction.get(
		"advance_completed",
		false
	))
	if (
		_descriptors.size() != _nodes.size()
		or stashed_descriptors.size() != stashed_nodes.size()
		or int(before.get("invalidation_revision", -1)) != _invalidation_revision
		or before.get("invalidated_generations", [])
		!= replay_snapshot().get("invalidated_generations", [])
		or int(before.get("revision", -1)) + added_payloads.size()
		+ (1 if advance_completed else 0) != _revision
		or _last_runtime_frame
		!= (int(ticket.get("runtime_frame", -1)) if advance_completed else int(before.get(
			"last_runtime_frame",
			-2
		)))
	):
		return false

	var expected_nodes: Dictionary = before_nodes.duplicate()
	for payload_id: String in _sorted_dictionary_keys(added_payloads):
		var record_value: Variant = added_payloads[payload_id]
		if not record_value is Dictionary:
			return false
		var record := record_value as Dictionary
		if not _is_live_transaction_node(record.get("node")):
			return false
		expected_nodes[payload_id] = record["node"]
	if expected_nodes.size() != _nodes.size() + stashed_nodes.size():
		return false
	for payload_id: String in _sorted_dictionary_keys(expected_nodes):
		var expected_node: Variant = expected_nodes[payload_id]
		var is_live := _nodes.has(payload_id)
		var is_stashed := stashed_nodes.has(payload_id)
		if is_live == is_stashed:
			return false
		if is_live:
			var node_value: Variant = _nodes[payload_id]
			if (
				node_value != expected_node
				or not _descriptors.get(payload_id) is Dictionary
				or not _is_live_transaction_node(node_value)
				or (node_value as Node).get_parent() != _active_root
			):
				return false
		else:
			var node_value: Variant = stashed_nodes[payload_id]
			if (
				node_value != expected_node
				or not stashed_descriptors.get(payload_id) is Dictionary
				or not _is_live_transaction_node(node_value)
				or (node_value as Node).get_parent() != null
			):
				return false
	return true


func _restore_transaction_begin_node_snapshots(
	before_nodes: Dictionary,
	frame_snapshots: Dictionary
) -> bool:
	if before_nodes.size() != frame_snapshots.size():
		return false
	var restored_all := true
	for payload_id: String in _sorted_dictionary_keys(before_nodes):
		var node_value: Variant = before_nodes[payload_id]
		var snapshot_value: Variant = frame_snapshots.get(payload_id)
		if (
			not _is_live_transaction_node(node_value)
			or not snapshot_value is Dictionary
			or not (node_value as Node).has_method(
				"restore_world_payload_frame_snapshot"
			)
		):
			restored_all = false
			continue
		var restored_value: Variant = (node_value as Node).call(
			"restore_world_payload_frame_snapshot",
			(snapshot_value as Dictionary).duplicate(true)
		)
		if typeof(restored_value) != TYPE_BOOL or not bool(restored_value):
			restored_all = false
	return restored_all


func _transaction_restore_ticket_matches(ticket: Dictionary) -> bool:
	if (
		_active_transaction_restore.is_empty()
		or not _has_exact_fields(ticket, TRANSACTION_RESTORE_TICKET_FIELDS)
		or typeof(ticket.get("schema_version")) != TYPE_INT
		or int(ticket.get("schema_version", -1)) != SCHEMA_VERSION
		or typeof(ticket.get("authority_instance_id")) != TYPE_INT
		or int(ticket.get("authority_instance_id", 0)) != get_instance_id()
		or typeof(ticket.get("ticket_id")) != TYPE_INT
		or int(ticket.get("ticket_id", 0)) <= 0
	):
		return false
	return ticket == _active_transaction_restore.get("ticket", {})


func _frame_transaction_ticket_matches(ticket: Dictionary) -> bool:
	if (
		_active_frame_transaction.is_empty()
		or not _has_exact_fields(ticket, FRAME_TRANSACTION_TICKET_FIELDS)
		or typeof(ticket.get("schema_version")) != TYPE_INT
		or int(ticket.get("schema_version", -1)) != SCHEMA_VERSION
		or typeof(ticket.get("authority_instance_id")) != TYPE_INT
		or int(ticket.get("authority_instance_id", 0)) != get_instance_id()
		or typeof(ticket.get("ticket_id")) != TYPE_INT
		or int(ticket.get("ticket_id", 0)) <= 0
		or typeof(ticket.get("runtime_frame")) != TYPE_INT
		or int(ticket.get("runtime_frame", -1)) < 0
	):
		return false
	return ticket == _active_frame_transaction.get("ticket", {})


func _rollback_active_transaction_restore() -> bool:
	if _active_transaction_restore.is_empty():
		return false
	var before := _active_transaction_restore["before"] as Dictionary
	var stashed_descriptors := (
		_active_transaction_restore["stashed_descriptors"] as Dictionary
	)
	var stashed_nodes := _active_transaction_restore["stashed_nodes"] as Dictionary
	var spawned_nodes := _active_transaction_restore["spawned_nodes"] as Dictionary
	if stashed_descriptors.size() != stashed_nodes.size():
		return false
	for payload_id: String in _sorted_dictionary_keys(spawned_nodes):
		var node_value: Variant = spawned_nodes[payload_id]
		if (
			not _is_live_transaction_node(node_value)
			or _nodes.get(payload_id) != node_value
			or (node_value as Node).get_parent() != _active_root
		):
			return false
	for payload_id: String in _sorted_dictionary_keys(spawned_nodes):
		var node := spawned_nodes[payload_id] as Node
		_nodes.erase(payload_id)
		_descriptors.erase(payload_id)
		if node.get_parent() == _active_root:
			_active_root.remove_child(node)
		if node.has_method("retire_world_payload"):
			node.call("retire_world_payload", &"transaction_rollback")
		_dispose_detached(node)
	for payload_id: String in _sorted_dictionary_keys(stashed_nodes):
		if (
			_descriptors.has(payload_id)
			or _nodes.has(payload_id)
			or not stashed_descriptors.get(payload_id) is Dictionary
			or not _is_live_transaction_node(stashed_nodes[payload_id])
		):
			return false
		var node := stashed_nodes[payload_id] as Node
		if node.get_parent() != null:
			return false

	for payload_id: String in _sorted_dictionary_keys(stashed_nodes):
		var node := stashed_nodes[payload_id] as Node
		_descriptors[payload_id] = (
			stashed_descriptors[payload_id] as Dictionary
		).duplicate(true)
		_nodes[payload_id] = node
		_active_root.add_child(node)
	_revision = int(before["revision"])
	_invalidation_revision = int(before["invalidation_revision"])
	_last_runtime_frame = int(before["last_runtime_frame"])
	_invalidated_generations = (
		_active_transaction_restore["before_invalidated_generations"] as Dictionary
	).duplicate(true)
	_active_transaction_restore.clear()
	_mutation_locked = false
	return replay_snapshot() == before


func _active_transaction_target_nodes_are_live() -> bool:
	if _active_transaction_restore.is_empty():
		return false
	var target := _active_transaction_restore["target"] as Dictionary
	if replay_snapshot() != target:
		return false
	for payload_id: String in _sorted_payload_ids():
		var node_value: Variant = _nodes.get(payload_id)
		if (
			not _is_live_transaction_node(node_value)
			or (node_value as Node).get_parent() != _active_root
		):
			return false
	return true


static func _is_live_transaction_node(value: Variant) -> bool:
	return (
		value is Node
		and is_instance_valid(value)
		and not (value as Node).is_queued_for_deletion()
	)


static func _sorted_dictionary_keys(value: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in value.keys():
		keys.append(str(key))
	keys.sort()
	return keys


func _sorted_payload_ids() -> Array[String]:
	var payload_ids: Array[String] = []
	for payload_id: Variant in _descriptors.keys():
		payload_ids.append(str(payload_id))
	payload_ids.sort()
	return payload_ids


func _failure(code: StringName, payload_id: String = "") -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"payload_id": payload_id,
		"revision": _revision,
		"invalidation_revision": _invalidation_revision,
	}


func _invalidation_failure(code: StringName) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"removed_ids": [],
		"revision": _revision,
		"invalidation_revision": _invalidation_revision,
	}


func _validated_replay_snapshot(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return {}
	if typeof(value["schema_version"]) != TYPE_INT or int(value["schema_version"]) != SCHEMA_VERSION:
		return {}
	if typeof(value["revision"]) != TYPE_INT or int(value["revision"]) < 0:
		return {}
	if (
		typeof(value["invalidation_revision"]) != TYPE_INT
		or int(value["invalidation_revision"]) < 0
	):
		return {}
	if typeof(value["last_runtime_frame"]) != TYPE_INT or int(value["last_runtime_frame"]) < -1:
		return {}
	if not value["invalidated_generations"] is Array or not value["descriptors"] is Array:
		return {}

	var invalidation_revision := int(value["invalidation_revision"])
	var source_invalidations := value["invalidated_generations"] as Array
	if invalidation_revision == 0 and not source_invalidations.is_empty():
		return {}
	if invalidation_revision > 0 and source_invalidations.is_empty():
		return {}
	var invalidations: Array[Dictionary] = []
	var invalidations_by_key: Dictionary = {}
	var seen_invalidation_revisions: Dictionary = {}
	var last_invalidation_key := ""
	var latest_invalidation_revision := 0
	for invalidation_value: Variant in source_invalidations:
		if not invalidation_value is Dictionary:
			return {}
		var invalidation := _validated_invalidation(invalidation_value as Dictionary)
		if invalidation.is_empty():
			return {}
		var key := _generation_key(
			invalidation["run_id"] as StringName,
			int(invalidation["owner_character_generation"])
		)
		if not last_invalidation_key.is_empty() and key <= last_invalidation_key:
			return {}
		var record_revision := int(invalidation["revision"])
		if (
			record_revision <= 0
			or record_revision > invalidation_revision
			or seen_invalidation_revisions.has(record_revision)
		):
			return {}
		seen_invalidation_revisions[record_revision] = true
		latest_invalidation_revision = maxi(
			latest_invalidation_revision,
			record_revision
		)
		var run_key := str(invalidation["run_id"])
		var compacted_value: Variant = invalidations_by_key.get(run_key)
		if not compacted_value is Dictionary:
			invalidations_by_key[run_key] = invalidation.duplicate(true)
		else:
			var compacted := compacted_value as Dictionary
			var highest_generation := maxi(
				int(compacted["owner_character_generation"]),
				int(invalidation["owner_character_generation"])
			)
			if record_revision > int(compacted["revision"]):
				compacted["reason"] = invalidation["reason"]
				compacted["revision"] = record_revision
			compacted["owner_character_generation"] = highest_generation
			invalidations_by_key[run_key] = compacted
		last_invalidation_key = key
	if latest_invalidation_revision != invalidation_revision:
		return {}
	for invalidation_value: Variant in invalidations_by_key.values():
		invalidations.append((invalidation_value as Dictionary).duplicate(true))
	invalidations.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _generation_key(
			left["run_id"] as StringName,
			int(left["owner_character_generation"])
		) < _generation_key(
			right["run_id"] as StringName,
			int(right["owner_character_generation"])
		)
	)

	var descriptors: Array[Dictionary] = []
	var descriptor_ids: Dictionary = {}
	var last_payload_id := ""
	for descriptor_value: Variant in value["descriptors"] as Array:
		if not descriptor_value is Dictionary:
			return {}
		var descriptor := _validated_descriptor(descriptor_value as Dictionary)
		if descriptor.is_empty() or descriptor != descriptor_value:
			return {}
		var payload_id := str(descriptor["payload_id"])
		if (
			descriptor_ids.has(payload_id)
			or (not last_payload_id.is_empty() and payload_id <= last_payload_id)
		):
			return {}
		var invalidation_value: Variant = invalidations_by_key.get(
			str(descriptor["run_id"])
		)
		if (
			invalidation_value is Dictionary
			and int(descriptor["owner_character_generation"])
			<= int((invalidation_value as Dictionary).get(
				"owner_character_generation",
				0
			))
		):
			return {}
		descriptor_ids[payload_id] = true
		descriptors.append(descriptor)
		last_payload_id = payload_id

	return {
		"schema_version": SCHEMA_VERSION,
		"revision": int(value["revision"]),
		"invalidation_revision": invalidation_revision,
		"last_runtime_frame": int(value["last_runtime_frame"]),
		"invalidated_generations": invalidations,
		"invalidated_generations_by_key": invalidations_by_key,
		"descriptors": descriptors,
	}


static func _validated_descriptor(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, DESCRIPTOR_FIELDS):
		return {}
	var run_id := _normalized_segment(value["run_id"])
	var handler_id := _normalized_segment(value["handler_id"])
	var payload_family := _normalized_segment(value["payload_family"])
	if run_id == &"" or handler_id == &"" or payload_family == &"":
		return {}
	if (
		typeof(value["owner_character_generation"]) != TYPE_INT
		or int(value["owner_character_generation"]) <= 0
		or typeof(value["source_token"]) != TYPE_INT
		or int(value["source_token"]) <= 0
		or typeof(value["payload_generation"]) != TYPE_INT
		or int(value["payload_generation"]) <= 0
		or typeof(value["remaining_frames"]) != TYPE_INT
		or int(value["remaining_frames"]) <= 0
	):
		return {}
	if typeof(value["transform"]) != TYPE_TRANSFORM2D or not _finite_transform(value["transform"]):
		return {}
	if not value["geometry"] is Dictionary or (value["geometry"] as Dictionary).is_empty():
		return {}
	if not value["parameters"] is Dictionary:
		return {}
	if (
		not _is_deterministic_value(value["geometry"], 0)
		or not _is_deterministic_value(value["parameters"], 0)
	):
		return {}
	var claims := _canonical_string_set(value["claims"], true)
	if claims.is_empty() and (not value["claims"] is Array or not (value["claims"] as Array).is_empty()):
		return {}
	var tags := _canonical_string_set(value["tags"], false)
	if tags.is_empty() and (not value["tags"] is Array or not (value["tags"] as Array).is_empty()):
		return {}
	var expected_payload_id := _stable_payload_id(
		run_id,
		int(value["owner_character_generation"]),
		payload_family,
		int(value["source_token"]),
		int(value["payload_generation"])
	)
	if (
		typeof(value["payload_id"]) != TYPE_STRING
		and typeof(value["payload_id"]) != TYPE_STRING_NAME
	):
		return {}
	if str(value["payload_id"]) != expected_payload_id:
		return {}
	return {
		"payload_id": expected_payload_id,
		"handler_id": handler_id,
		"run_id": run_id,
		"owner_character_generation": int(value["owner_character_generation"]),
		"payload_family": payload_family,
		"source_token": int(value["source_token"]),
		"payload_generation": int(value["payload_generation"]),
		"transform": value["transform"],
		"geometry": (value["geometry"] as Dictionary).duplicate(true),
		"remaining_frames": int(value["remaining_frames"]),
		"claims": claims,
		"tags": tags,
		"parameters": (value["parameters"] as Dictionary).duplicate(true),
	}


static func _validated_invalidation(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, INVALIDATION_FIELDS):
		return {}
	var run_id := _normalized_segment(value["run_id"])
	var reason := _normalized_segment(value["reason"])
	if run_id == &"" or reason == &"":
		return {}
	if (
		typeof(value["owner_character_generation"]) != TYPE_INT
		or int(value["owner_character_generation"]) <= 0
		or typeof(value["revision"]) != TYPE_INT
		or int(value["revision"]) <= 0
	):
		return {}
	return {
		"run_id": run_id,
		"owner_character_generation": int(value["owner_character_generation"]),
		"reason": reason,
		"revision": int(value["revision"]),
	}


static func _canonical_string_set(value: Variant, allow_colon: bool) -> Array[String]:
	var empty: Array[String] = []
	if not value is Array:
		return empty
	var normalized_values: Array[String] = []
	var seen: Dictionary = {}
	for entry: Variant in value as Array:
		if typeof(entry) != TYPE_STRING and typeof(entry) != TYPE_STRING_NAME:
			return empty
		var normalized := str(entry)
		if (
			normalized.is_empty()
			or normalized != normalized.strip_edges()
			or normalized.length() > MAX_SET_ENTRY_LENGTH
			or normalized.contains("\n")
			or normalized.contains("\r")
			or normalized.contains("\t")
			or (not allow_colon and normalized.contains(":"))
			or seen.has(normalized)
		):
			return empty
		seen[normalized] = true
		normalized_values.append(normalized)
	normalized_values.sort()
	return normalized_values


static func _is_deterministic_value(value: Variant, depth: int) -> bool:
	if depth > MAX_DETERMINISTIC_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_STRING, TYPE_STRING_NAME:
			var text := str(value)
			return text.length() <= 1024 and not text.to_utf8_buffer().has(0)
		TYPE_VECTOR2:
			var vector := value as Vector2
			return is_finite(vector.x) and is_finite(vector.y)
		TYPE_VECTOR2I:
			return true
		TYPE_RECT2:
			var rect := value as Rect2
			return (
				is_finite(rect.position.x)
				and is_finite(rect.position.y)
				and is_finite(rect.size.x)
				and is_finite(rect.size.y)
			)
		TYPE_COLOR:
			var color := value as Color
			return (
				is_finite(color.r)
				and is_finite(color.g)
				and is_finite(color.b)
				and is_finite(color.a)
			)
		TYPE_TRANSFORM2D:
			return _finite_transform(value as Transform2D)
		TYPE_ARRAY:
			for entry: Variant in value as Array:
				if not _is_deterministic_value(entry, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			var dictionary := value as Dictionary
			for key: Variant in dictionary.keys():
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					return false
				var normalized_key := str(key)
				if (
					normalized_key.is_empty()
					or normalized_key != normalized_key.strip_edges()
					or normalized_key.length() > MAX_SEGMENT_LENGTH
					or normalized_key.contains("\n")
					or normalized_key.contains("\r")
					or normalized_key.contains("\t")
				):
					return false
				if not _is_deterministic_value(dictionary[key], depth + 1):
					return false
			return true
		_:
			return false


static func _finite_transform(value: Transform2D) -> bool:
	return (
		is_finite(value.x.x)
		and is_finite(value.x.y)
		and is_finite(value.y.x)
		and is_finite(value.y.y)
		and is_finite(value.origin.x)
		and is_finite(value.origin.y)
	)


static func _normalized_segment(value: Variant) -> StringName:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return &""
	var text := str(value)
	if (
		text.is_empty()
		or text != text.strip_edges()
		or text.length() > MAX_SEGMENT_LENGTH
		or text.contains(":")
	):
		return &""
	for character: String in text:
		var code := character.unicode_at(0)
		var valid := (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or character == "_"
			or character == "-"
			or character == "."
		)
		if not valid:
			return &""
	return StringName(text)


static func _stable_payload_id(
	run_id: StringName,
	owner_character_generation: int,
	payload_family: StringName,
	source_token: int,
	payload_generation: int
) -> String:
	var payload_id := "%s:%d:%s:%d:%d" % [
		str(run_id),
		owner_character_generation,
		str(payload_family),
		source_token,
		payload_generation,
	]
	if payload_id.length() > MAX_PAYLOAD_ID_LENGTH:
		return ""
	return payload_id


static func _generation_key(run_id: StringName, owner_character_generation: int) -> String:
	return "%s:%d" % [str(run_id), owner_character_generation]


static func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


static func _dispose_detached(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()
