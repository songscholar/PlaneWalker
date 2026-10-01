class_name SaveMigrationV1ToV2
extends RefCounted

const ActiveItemRuntimeScript := preload("res://scripts/items/active_item_runtime.gd")
const SaveResultScript := preload("res://scripts/save/save_result.gd")


func migrate(document: Dictionary, _context: Dictionary = {}):
	if (
		document.get("schema_version") != 1
		or not document.get("payload") is Dictionary
	):
		return _failure("invalid_schema_v1_document")

	var migrated := document.duplicate(true)
	var payload := migrated["payload"] as Dictionary
	var defaults_added := false
	if payload.has("active_item_state"):
		var active_value: Variant = payload["active_item_state"]
		if (
			not active_value is Dictionary
			or not bool(ActiveItemRuntimeScript.new().call(
				"can_restore_snapshot",
				(active_value as Dictionary).duplicate(true)
			))
		):
			return _failure("active_item_state_invalid")
	else:
		payload["active_item_state"] = empty_active_item_state()
		defaults_added = true

	if payload.has("reward_effect_state"):
		if not payload["reward_effect_state"] is Dictionary:
			return _failure("reward_effect_state_invalid")
	else:
		payload["reward_effect_state"] = {}
		defaults_added = true

	migrated["schema_version"] = 2
	return SaveResultScript.success(migrated, {
		"runtime_defaults_added": defaults_added,
	})


static func empty_active_item_state() -> Dictionary:
	return {
		"schema_version": 1,
		"configured": false,
		"definition": {},
		"generation": 0,
		"next_token": 1,
		"current_frame": -1,
		"cooldown_end_frame": -1,
		"handler_state": {},
		"committed_receipts": {},
	}


static func _failure(reason: String):
	return SaveResultScript.failure(&"MIGRATION_FAILED", {
		"from_version": 1,
		"to_version": 2,
		"reason": reason,
	})
