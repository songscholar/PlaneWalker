class_name LaunchHostileContentSource
extends RefCounted

const SOURCES := {
	"enemy_definition": "res://data/content_packs/base/content/enemies.json",
	"boss_definition": "res://data/content_packs/base/content/bosses.json",
	"elite_affix_definition": "res://data/content_packs/base/content/elite_affixes.json",
	"launch_encounter_profile": "res://data/content_packs/base/content/launch_encounters.json",
	"room_template": "res://data/content_packs/base/content/room_templates.json",
}

var _rows: Dictionary = {}


func load_authored() -> Dictionary:
	_rows.clear()
	var candidate: Dictionary = {}
	for category: String in SOURCES:
		var file := FileAccess.open(SOURCES[category], FileAccess.READ)
		if file == null or file.get_length() > 1048576:
			return {"ok": false, "context": {"category": category, "reason": "unavailable_or_oversized"}}
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if not parsed is Array or parsed.is_empty():
			return {"ok": false, "context": {"category": category, "reason": "invalid_collection"}}
		candidate[category] = parsed.duplicate(true)
	_rows = candidate
	return {"ok": true, "context": {}}


func get_by_category(category: StringName, _availability: StringName = &"") -> Array:
	return _rows.get(str(category), []).duplicate(true)


func get_content(content_id: StringName) -> Dictionary:
	for rows: Array in _rows.values():
		for row: Variant in rows:
			if row is Dictionary and row.get("id") == str(content_id):
				return row.duplicate(true)
	return {}


func snapshot_rows() -> Dictionary:
	return _rows.duplicate(true)
