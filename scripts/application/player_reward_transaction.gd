class_name PlayerRewardTransaction
extends RefCounted

var _player: Object
var _runtime: Object
var _before: Dictionary = {}
var _receipt: Dictionary = {}
var _kind := ""
var _publication := false


func configure(player: Object, runtime: Object) -> bool:
	_player = player
	_runtime = runtime
	return player != null and is_instance_valid(player) and runtime != null


func apply(definition: Dictionary) -> bool:
	if _player == null or not is_instance_valid(_player) or not _kind.is_empty():
		return false
	if str(definition.get("id", "")) == "decline_contract":
		_kind = "none"
		return true
	if str(definition.get("category", "")) == "talent":
		_kind = "talent"
		for method: String in ["character_talent_transaction_snapshot", "restore_character_talent_transaction_snapshot", "install_character_talent"]:
			if not _player.has_method(method):
				return false
		_before = _player.call("character_talent_transaction_snapshot")
		return not _before.is_empty() and bool(_player.call("install_character_talent", definition))
	if str(definition.get("item_mode", "")) == "active":
		_kind = "active"
		for method: String in ["full_player_replay_snapshot", "restore_full_player_replay_snapshot", "equip_active_item", "active_item_snapshot"]:
			if not _player.has_method(method):
				return false
		_before = _player.call("full_player_replay_snapshot")
		if _before.is_empty():
			return false
		var current: Dictionary = _player.call("active_item_snapshot")
		var equipped: Dictionary = _player.call("equip_active_item", definition, bool(current.get("configured", false)))
		return bool(equipped.get("ok", false))
	_kind = "effect"
	if not bool(_player.call("reward_effect_begin_publication")):
		return false
	_publication = true
	_before = _player.call("reward_effect_snapshot")
	var prepared: Dictionary = _runtime.call("prepare", definition, _before)
	if not bool(prepared.get("ok", false)):
		return false
	var applied: Dictionary = _runtime.call("commit", prepared["plan"], _player)
	if not bool(applied.get("ok", false)):
		return false
	_receipt = applied["receipt"]
	return bool(_player.call("reward_effect_publication_can_commit"))


func commit() -> bool:
	if _kind.is_empty():
		return false
	if _publication and not bool(_player.call("reward_effect_commit_publication")):
		return false
	_publication = false
	_kind = ""
	_before.clear()
	_receipt.clear()
	return true


func rollback() -> bool:
	var restored := true
	if _player == null or not is_instance_valid(_player):
		_clear_transaction()
		return false
	if not _before.is_empty():
		match _kind:
			"talent":
				restored = _restore_verified("restore_character_talent_transaction_snapshot", "character_talent_transaction_snapshot")
			"active":
				restored = _restore_verified("restore_full_player_replay_snapshot", "full_player_replay_snapshot")
			"effect":
				restored = _restore_verified("restore_reward_effect_snapshot", "reward_effect_snapshot")
	if _publication:
		restored = bool(_player.call("reward_effect_rollback_publication")) and restored
	_clear_transaction()
	return restored


func _restore_verified(restore_method: String, snapshot_method: String) -> bool:
	var succeeded := bool(_player.call(restore_method, _before.duplicate(true)))
	return _player.call(snapshot_method) == _before and succeeded


func _clear_transaction() -> void:
	_publication = false
	_kind = ""
	_before.clear()
	_receipt.clear()
