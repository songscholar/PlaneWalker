extends RefCounted

const Source := preload("res://scripts/dungeon/launch_hostile_content_source.gd")


class RegistryFixture extends RefCounted:
	var rows: Dictionary = {}

	func get_by_category(category: StringName, _availability: StringName = &"") -> Array:
		return rows.get(str(category), []).duplicate(true)

	func get_content(content_id: StringName) -> Dictionary:
		for category_rows: Array in rows.values():
			for row: Dictionary in category_rows:
				if row.id == str(content_id):
					return row.duplicate(true)
		return {}


static func registry() -> RefCounted:
	var source := Source.new()
	var loaded := source.load_authored()
	var result := RegistryFixture.new()
	result.rows = source.snapshot_rows() if loaded.ok else {}
	return result


static func profile(floor_index: int) -> Dictionary:
	var source := Source.new()
	if not source.load_authored().ok:
		return {}
	var profiles: Array = source.get_by_category(&"launch_encounter_profile", &"LAUNCH")
	return profiles[floor_index].duplicate(true) if floor_index >= 0 and floor_index < profiles.size() else {}
