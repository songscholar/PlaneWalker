class_name NarrativeViewState
extends RefCounted

const Rules := preload("res://scripts/ui/contracts/dungeon_view_state_rules.gd")
const FIELDS := ["schema_version", "revision", "run_id", "mode", "subject_id", "title_key", "text_key", "close_available", "rows"]
const ROW_FIELDS := ["action_id", "node_id", "choice_id", "name_key", "text_key", "available", "consumed", "missing_count"]


static func validate(value: Variant):
	if not Rules.header(value, FIELDS) or value.mode not in ["dialogue", "story", "choice", "ending", "credits"] or not Rules.identifier(value.subject_id) or not Rules.key(value.title_key) or not Rules.key(value.text_key, true) or not value.close_available is bool or not value.rows is Array or value.rows.size() > 32:
		return Rules.reject(value, "root")
	if value.mode in ["ending", "credits"] and value.close_available:
		return Rules.reject(value, "close_available")
	var ids: Array = []
	for row: Variant in value.rows:
		if not Rules.exact(row, ROW_FIELDS) or not Rules.identifier(row.action_id) or ids.has(row.action_id) or not _optional_id(row.node_id) or not _optional_id(row.choice_id) or not Rules.key(row.name_key) or not Rules.key(row.text_key, true) or not row.available is bool or not row.consumed is bool or not Rules.integer(row.missing_count) or row.missing_count < 0 or row.missing_count > 64 or row.available and (row.consumed or row.missing_count > 0):
			return Rules.reject(value, "row")
		ids.append(row.action_id)
	return Rules.accept(value)


static func _optional_id(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and (value.is_empty() or Rules.identifier(value))
