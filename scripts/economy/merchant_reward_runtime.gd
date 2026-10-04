class_name MerchantRewardRuntime
extends RefCounted

const PassiveRuntimeScript := preload("res://scripts/items/player_reward_effect_runtime.gd")
const ActiveRuntimeScript := preload("res://scripts/items/active_item_runtime.gd")
const ACTIVE_PLAN_FIELDS := ["schema_version", "kind", "definition", "player_reward_snapshot", "full_player_snapshot", "digest"]
const ACTIVE_RECEIPT_FIELDS := ["schema_version", "kind", "plan_digest", "before_full_snapshot", "after_full_snapshot", "digest"]
const ACTIVE_PLAYER_METHODS := ["reward_effect_snapshot", "full_player_replay_snapshot", "restore_full_player_replay_snapshot", "active_item_snapshot", "equip_active_item"]

var _passive: Object
var _player: Object


func _init(passive_runtime: Object = null, player: Object = null) -> void:
	_passive = passive_runtime if passive_runtime != null else PassiveRuntimeScript.new()
	_player = player


func prepare(definition: Dictionary, player_snapshot: Dictionary) -> Dictionary:
	if str(definition.get("item_mode", "")) != "active":
		return _passive.call("prepare", definition, player_snapshot)
	if not _valid_active_player(_player):
		return _failure(&"INVALID_PLAYER")
	var validator = ActiveRuntimeScript.new()
	if not validator.configure(definition.duplicate(true)):
		return _failure(&"INVALID_DEFINITION")
	var full_snapshot: Dictionary = _player.call("full_player_replay_snapshot")
	if full_snapshot.is_empty() or player_snapshot.is_empty():
		return _failure(&"INVALID_PLAYER_SNAPSHOT")
	if _player.call("reward_effect_snapshot") != player_snapshot:
		return _failure(&"STALE_PLAYER_SNAPSHOT")
	var plan := {
		"schema_version": 1, "kind": "active_item", "definition": definition.duplicate(true),
		"player_reward_snapshot": player_snapshot.duplicate(true),
		"full_player_snapshot": full_snapshot.duplicate(true),
	}
	plan["digest"] = _digest(plan)
	return {"ok": true, "code": &"OK", "plan": plan}


func commit(plan: Dictionary, player: Object) -> Dictionary:
	if str(plan.get("kind", "")) != "active_item":
		return _passive.call("commit", plan, player)
	if not _valid_active_player(player) or player != _player:
		return _failure(&"INVALID_PLAYER")
	if not _valid_active_document(plan, ACTIVE_PLAN_FIELDS) or not plan.get("definition") is Dictionary or not plan.get("full_player_snapshot") is Dictionary or not plan.get("player_reward_snapshot") is Dictionary:
		return _failure(&"INVALID_PLAN")
	var validator = ActiveRuntimeScript.new()
	if not validator.configure(plan["definition"]):
		return _failure(&"INVALID_PLAN")
	var before: Dictionary = player.call("full_player_replay_snapshot")
	if before.is_empty() or before != plan["full_player_snapshot"] or player.call("reward_effect_snapshot") != plan["player_reward_snapshot"]:
		return _failure(&"STALE_PLAYER_SNAPSHOT")
	var active: Dictionary = player.call("active_item_snapshot")
	var equipped: Dictionary = player.call("equip_active_item", plan["definition"], bool(active.get("configured", false)))
	var after: Dictionary = player.call("full_player_replay_snapshot")
	if not equipped.get("ok", false) or after.is_empty():
		return _failure(&"COMMIT_FAILED_ROLLED_BACK" if _restore_exact(player, before) else &"ROLLBACK_FAILED")
	var receipt := {
		"schema_version": 1, "kind": "active_item", "plan_digest": str(plan["digest"]),
		"before_full_snapshot": before.duplicate(true), "after_full_snapshot": after.duplicate(true),
	}
	receipt["digest"] = _digest(receipt)
	return {"ok": true, "code": &"OK", "receipt": receipt}


func rollback(receipt: Dictionary, player: Object) -> Dictionary:
	if str(receipt.get("kind", "")) != "active_item":
		return _passive.call("rollback", receipt, player)
	if not _valid_active_player(player) or player != _player:
		return _failure(&"INVALID_PLAYER")
	if not _valid_active_document(receipt, ACTIVE_RECEIPT_FIELDS) or not receipt.get("before_full_snapshot") is Dictionary or not receipt.get("after_full_snapshot") is Dictionary:
		return _failure(&"INVALID_RECEIPT")
	var before := receipt["before_full_snapshot"] as Dictionary
	var after := receipt["after_full_snapshot"] as Dictionary
	if before.is_empty() or after.is_empty() or player.call("full_player_replay_snapshot") != after:
		return _failure(&"STALE_PLAYER_SNAPSHOT")
	if not _restore_exact(player, before):
		return _failure(&"ROLLBACK_FAILED")
	return {"ok": true, "code": &"ROLLED_BACK", "restored_snapshot": before.duplicate(true)}


func _valid_active_player(player: Object) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	for method: String in ACTIVE_PLAYER_METHODS:
		if not player.has_method(method):
			return false
	return true


func _valid_active_document(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size() or typeof(value.get("schema_version")) != TYPE_INT or value.get("schema_version") != 1 or value.get("kind") != "active_item":
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	var unsigned := value.duplicate(true)
	unsigned.erase("digest")
	return typeof(value["digest"]) == TYPE_STRING and value["digest"] == _digest(unsigned)


func _restore_exact(player: Object, snapshot: Dictionary) -> bool:
	return bool(player.call("restore_full_player_replay_snapshot", snapshot.duplicate(true))) and player.call("full_player_replay_snapshot") == snapshot


func _digest(value: Variant) -> String:
	return var_to_bytes(_canonical(value)).hex_encode().sha256_text()


func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var canonical: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key: Variant in keys:
			canonical[str(key)] = _canonical(value[key])
		return canonical
	if value is Array:
		var canonical: Array = []
		for entry: Variant in value:
			canonical.append(_canonical(entry))
		return canonical
	return str(value) if typeof(value) == TYPE_STRING_NAME else value


func _failure(code: StringName) -> Dictionary:
	return {"ok": false, "code": code, "context": {}}
