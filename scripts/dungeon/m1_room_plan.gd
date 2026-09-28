class_name M1RoomPlan
extends RefCounted

const EncounterCatalogScript := preload("res://scripts/dungeon/encounter_catalog.gd")


static func definitions(catalog: RefCounted = null, run_seed: int = 0) -> Array[Dictionary]:
	var active_catalog: RefCounted = catalog
	if active_catalog == null:
		active_catalog = EncounterCatalogScript.new()
		var report = active_catalog.load_path()
		if report.has_blocking_errors():
			return []
	return active_catalog.room_definitions(run_seed)
