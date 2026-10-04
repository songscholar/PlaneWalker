class_name NativeCheckpointPlayerTransaction
extends RefCounted

const Player := preload("res://scripts/player/player_controller.gd")
const World := preload("res://scripts/combat/world_payload_authority.gd")

var _player: Node
var _preimage: Dictionary = {}
var _original_world: Node
var _staged_world: Node
var _original_ledger: RefCounted
var _active := false


func begin(player: Node) -> bool:
	if _active or not player is Player or not player.is_inside_tree() or player.current_run_id() != &"standalone" or player.full_player_replay_snapshot().is_empty():
		return false
	_preimage = player.call("_loadout_configuration_transaction_snapshot")
	_original_world = player.world_payload_authority
	_original_ledger = player.health.get("_irreversible_ledger")
	if _original_world == null or _original_ledger == null or not _original_world is World:
		return false
	_staged_world = World.new()
	var factories: Dictionary = _original_world.get("_factories")
	for id: String in factories:
		if not _staged_world.register_factory(StringName(id), factories[id]):
			_staged_world.free()
			return false
	var original_snapshot: Dictionary = _original_world.replay_snapshot()
	if not original_snapshot.descriptors.is_empty() or not _staged_world.restore_replay_snapshot(original_snapshot):
		_staged_world.free()
		return false
	var staged_ledger: RefCounted = _original_ledger.get_script().new()
	if not staged_ledger.call("configure_run", &"standalone"):
		_staged_world.free()
		return false
	_player = player
	player.remove_child(_original_world)
	_staged_world.name = "WorldPayloadAuthority"
	player.add_child(_staged_world)
	player.world_payload_authority = _staged_world
	player.time_manager.world_payload_authority = _staged_world
	player.health.set("_irreversible_ledger", staged_ledger)
	_active = true
	return true


func rollback() -> bool:
	if not _active or not is_instance_valid(_player):
		return false
	if _staged_world.get_parent() == _player:
		_player.remove_child(_staged_world)
	_staged_world.free()
	_player.add_child(_original_world)
	_player.world_payload_authority = _original_world
	_player.time_manager.world_payload_authority = _original_world
	_player.health.set("_irreversible_ledger", _original_ledger)
	_player.rewind_recorder.set("_run_id", _preimage.run_id)
	var original_character: RefCounted = _preimage.character_action_coordinator
	if original_character != null:
		original_character.restore_action_snapshot(_preimage.full_player.character_action_state)
	_preimage.stats_resource.apply_profile(_preimage.stats_state)
	_player.time_manager.configure_from_stats(_preimage.stats_resource, false)
	var restored: bool = _player.call("_rollback_loadout_configuration", _preimage)
	_active = false
	_preimage.clear()
	return restored


func commit() -> bool:
	if not _active or not is_instance_valid(_player) or _player.world_payload_authority != _staged_world:
		return false
	_original_world.free()
	_original_world = null
	_original_ledger = null
	_preimage.clear()
	_active = false
	return true
