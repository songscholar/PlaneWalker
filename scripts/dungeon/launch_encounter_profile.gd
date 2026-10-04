class_name LaunchEncounterProfile
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const Runtime := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const FIELDS: Array[String] = ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "references", "floor_id", "boss_id", "boss_encounter_id", "recipes"]
const RECIPE_FIELDS: Array[String] = ["id", "room_type", "template_ids", "threat_budget", "waves"]
const RECIPE_IDS := [
	["sentinel_line", "watcher_guard", "moth_crossfire", "wraith_shell", "ruin_full", "sentinel_trial", "shell_trial", "watcher_trial"],
	["hunter_archer", "bramble_spores", "caller_archer", "lurker_hunter", "forest_full", "hunter_trial", "bramble_trial", "caller_trial"],
	["guard_priest", "weaver_blink", "hound_pack", "storm_archer", "rift_full", "guard_trial", "blink_trial", "storm_trial"],
	["titan_ranger", "web_titan", "chaos_crossfire", "ripper_pack", "forge_full", "titan_trial", "chaos_trial", "ripper_trial"],
	["throne_front", "throne_lanes", "throne_mirror", "throne_space", "throne_guard", "throne_titan_trial", "throne_chaos_trial", "throne_blink_trial"],
]
const BUDGET_MIN: Array[int] = [4, 5, 6, 7, 7]
const BUDGET_MAX: Array[int] = [6, 8, 9, 10, 11]

var _snapshot: Dictionary = {}


func configure(source: Dictionary) -> Dictionary:
	_snapshot.clear()
	if not Contract.exact_fields(source, FIELDS) or typeof(source.category) != TYPE_STRING or source.category != "launch_encounter_profile" or not Contract.integer_in_range(source.schema_version, 1, 1) or typeof(source.id) != TYPE_STRING or not Ids.PROFILE_IDS.has(source.id):
		return _failure("profile", "invalid_fields")
	var floor_index := Ids.PROFILE_IDS.find(source.id)
	if source.floor_id != Ids.FLOOR_IDS[floor_index] or source.boss_id != Ids.BOSS_IDS[floor_index] or source.boss_encounter_id != Ids.BOSS_ENCOUNTER_IDS[floor_index]:
		return _failure("profile", "floor_boss_identity_mismatch")
	if not _localization_key(source.name_key) or not _localization_key(source.description_key) or source.availability != ["LAUNCH", "EXPANSION"] or not source.compatibility is Dictionary or not source.compatibility.is_empty():
		return _failure("metadata", "invalid")
	if not _id_list(source.tags, 8) or not _id_list(source.references, 28) or not source.recipes is Array or source.recipes.size() != 8:
		return _failure("recipes", "invalid_count")
	var recipes: Array[Dictionary] = []
	var recipe_ids: Dictionary = {}
	var references: Array[String] = [source.boss_id]
	for candidate: Variant in source.recipes:
		if not candidate is Dictionary or not Contract.exact_fields(candidate, RECIPE_FIELDS) or typeof(candidate.id) != TYPE_STRING or not RECIPE_IDS[floor_index].has(candidate.id) or recipe_ids.has(candidate.id):
			return _failure("recipes.id", "unsupported_or_duplicate")
		var recipe_index: int = RECIPE_IDS[floor_index].find(candidate.id)
		var room_type := "combat" if recipe_index < 5 else "elite"
		if candidate.room_type != room_type or not _id_list(candidate.template_ids, 10) or candidate.template_ids.is_empty():
			return _failure("recipes.room_type", "identity_mismatch")
		for template_id: String in candidate.template_ids:
			if not template_id.begins_with("room_" + room_type + "_"):
				return _failure("recipes.template_ids", "wrong_room_type")
		var maximum := BUDGET_MAX[floor_index] + (3 if room_type == "elite" else 0)
		if not Contract.integer_in_range(candidate.threat_budget, BUDGET_MIN[floor_index], maximum):
			return _failure("recipes.threat_budget", "out_of_range")
		var encounter := {"id": source.id + "." + candidate.id, "floor_id": source.floor_id, "recipe_id": candidate.id, "room_type": room_type, "waves": candidate.waves}
		var result := Runtime.normalize_encounter(encounter)
		if not result.ok:
			return result
		for wave: Dictionary in result.definition.waves:
			for spawn: Dictionary in wave.spawns:
				if not references.has(spawn.enemy_id):
					references.append(spawn.enemy_id)
		recipe_ids[candidate.id] = true
		recipes.append({"id": candidate.id, "room_type": room_type, "template_ids": candidate.template_ids.duplicate(), "threat_budget": int(candidate.threat_budget), "waves": result.definition.waves})
	var supplied: Array = source.references.duplicate()
	supplied.sort()
	references.sort()
	if supplied != references:
		return _failure("references", "exact_actor_closure_required")
	_snapshot = {
		"category": "launch_encounter_profile", "id": source.id, "schema_version": 1,
		"name_key": source.name_key, "description_key": source.description_key,
		"availability": ["LAUNCH", "EXPANSION"], "tags": source.tags.duplicate(), "compatibility": {}, "references": references,
		"floor_id": source.floor_id, "boss_id": source.boss_id, "boss_encounter_id": source.boss_encounter_id, "recipes": recipes,
	}
	return {"ok": true, "definition": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


static func _id_list(value: Variant, maximum: int) -> bool:
	if not value is Array or value.size() > maximum:
		return false
	var seen: Array[String] = []
	for entry: Variant in value:
		if not Contract.valid_id(entry) or seen.has(entry):
			return false
		seen.append(entry)
	return true


static func _localization_key(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 96:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not (code >= 65 and code <= 90) and not (code >= 48 and code <= 57) and code != 95:
			return false
	return true


static func _failure(field: String, reason: String) -> Dictionary:
	return {"ok": false, "code": &"LAUNCH_ENCOUNTER_PROFILE_INVALID", "context": {"field": field, "reason": reason}}
