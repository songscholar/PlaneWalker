class_name SaveMigrationV2ToV3
extends RefCounted

const SaveResultScript := preload("res://scripts/save/save_result.gd")

const P14_DEFAULTS := {
	"current_floor_index": -1,
	"floor_plan": {},
	"completed_floor_ids": [],
	"run_economy": {},
	"seen_event_ids": [],
	"merchant_state": {},
	"floor_rule_state": {},
	"dungeon_event_runtime": {},
}
const FLOOR_PLAN_MILESTONES: Array[String] = ["LAUNCH", "EXPANSION"]


func migrate(document: Dictionary, _context: Dictionary = {}):
	if document.get("schema_version") != 2 or not document.get("payload") is Dictionary:
		return _failure(&"MIGRATION_FAILED", "invalid_schema_v2_document")

	var migrated := document.duplicate(true)
	var document_kind := str(migrated.get("document_kind", "profile"))
	if document_kind == "settings":
		migrated["schema_version"] = 3
		return SaveResultScript.success(migrated, {
			"active_run_defaults_added": false,
		})
	if document_kind != "profile":
		return _failure(&"MIGRATION_FAILED", "document_kind_invalid")

	var payload := migrated["payload"] as Dictionary
	if not payload.has("active_run_state"):
		payload["active_run_state"] = {}
		migrated["schema_version"] = 3
		return SaveResultScript.success(migrated, {
			"active_run_defaults_added": true,
		})
	if not payload["active_run_state"] is Dictionary:
		return _failure(&"MIGRATION_FAILED", "active_run_state_invalid")

	var active_run := payload["active_run_state"] as Dictionary
	if active_run.is_empty():
		migrated["schema_version"] = 3
		return SaveResultScript.success(migrated, {
			"active_run_defaults_added": false,
		})

	var config_value: Variant = active_run.get("config", {})
	if not config_value is Dictionary:
		return _failure(&"MIGRATION_FAILED", "active_run_config_invalid")
	var milestone := str((config_value as Dictionary).get("milestone", ""))
	if FLOOR_PLAN_MILESTONES.has(milestone):
		var floor_plan_value: Variant = active_run.get("floor_plan", {})
		if not floor_plan_value is Dictionary or (floor_plan_value as Dictionary).is_empty():
			return _failure(
				&"MIGRATION_UNSAFE_ACTIVE_RUN",
				"active_floor_plan_cannot_be_invented",
				{"milestone": milestone}
			)

	var preserve_legacy_event_history := (
		FLOOR_PLAN_MILESTONES.has(milestone)
		and active_run.get("seen_event_ids") is Array
		and not (active_run["seen_event_ids"] as Array).is_empty()
	)
	var defaults_added := false
	for field: String in P14_DEFAULTS:
		if active_run.has(field):
			continue
		# Recorded legacy events cannot be represented by an empty event authority.
		# Keep this field absent so v3 reads retain the historical projection.
		if field == "dungeon_event_runtime" and preserve_legacy_event_history:
			continue
		active_run[field] = _deep_copy(P14_DEFAULTS[field])
		defaults_added = true

	migrated["schema_version"] = 3
	return SaveResultScript.success(migrated, {
		"active_run_defaults_added": defaults_added,
	})


func _failure(code: StringName, reason: String, extra_metadata: Dictionary = {}):
	var metadata := extra_metadata.duplicate(true)
	metadata["from_version"] = 2
	metadata["to_version"] = 3
	metadata["reason"] = reason
	metadata["player_notice_required"] = code == &"MIGRATION_UNSAFE_ACTIVE_RUN"
	return SaveResultScript.failure(code, metadata)


func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value
