class_name LaunchEncounterExtension
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const Profile := preload("res://scripts/dungeon/launch_encounter_profile.gd")
const Runtime := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const IDS := ["encounter_extension_ruins_terminal_v2", "encounter_extension_forest_terminal_v2"]
const RECIPE_IDS := ["wraith_trial_v2", "spore_trial_v2"]
const SPECIES_IDS := ["ruins_wraith", "void_spore"]
const FIELDS := ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "references", "floor_id", "profile_id", "selection_revision", "recipes"]
var _snapshot := {}


func configure(source: Dictionary) -> Dictionary:
	_snapshot.clear()
	if not Contract.exact_fields(source, FIELDS) or source.get("category") != "launch_encounter_extension" or not Contract.integer_in_range(source.get("schema_version"), 1, 1) or not IDS.has(source.get("id")) or not Contract.integer_in_range(source.get("selection_revision"), 2, 2):
		return _failure("identity")
	var floor_index := IDS.find(source.id)
	if source.floor_id != Ids.FLOOR_IDS[floor_index] or source.profile_id != Ids.PROFILE_IDS[floor_index] or source.availability != ["LAUNCH", "EXPANSION"] or not source.compatibility is Dictionary or not source.compatibility.is_empty() or not Profile._localization_key(source.name_key) or not Profile._localization_key(source.description_key) or not Profile._id_list(source.tags, 8) or not Profile._id_list(source.references, 28):
		return _failure("metadata")
	if not source.recipes is Array or source.recipes.size() != 1 or not source.recipes[0] is Dictionary:
		return _failure("recipes")
	var recipe: Dictionary = source.recipes[0]
	if not Contract.exact_fields(recipe, Profile.RECIPE_FIELDS) or recipe.id != RECIPE_IDS[floor_index] or recipe.room_type != "elite" or not Profile._id_list(recipe.template_ids, 5) or recipe.template_ids.is_empty() or not Contract.integer_in_range(recipe.threat_budget, Profile.BUDGET_MIN[floor_index], Profile.BUDGET_MAX[floor_index] + 3):
		return _failure("recipe")
	for template_id: String in recipe.template_ids:
		if not template_id.begins_with("room_elite_"):
			return _failure("template_ids")
	var parsed := Runtime.normalize_encounter({"id": source.profile_id + "." + recipe.id, "floor_id": source.floor_id, "recipe_id": recipe.id, "room_type": "elite", "waves": recipe.waves})
	if not parsed.ok:
		return _failure("waves")
	var references: Array[String] = [source.profile_id]
	var elite_count := 0
	for wave: Dictionary in parsed.definition.waves:
		if int(wave.warning_frames) < (30 if floor_index == 0 else 23):
			return _failure("warning_frames")
		for spawn: Dictionary in wave.spawns:
			if not references.has(spawn.enemy_id):
				references.append(spawn.enemy_id)
			if spawn.elite:
				if spawn.enemy_id != SPECIES_IDS[floor_index]:
					return _failure("elite_species")
				elite_count += 1
	var supplied: Array = source.references.duplicate()
	supplied.sort()
	references.sort()
	if elite_count != 1 or supplied != references:
		return _failure("references")
	_snapshot = source.duplicate(true)
	_snapshot.references = references
	_snapshot.recipes[0].waves = parsed.definition.waves
	return {"ok": true, "definition": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


static func _failure(field: String) -> Dictionary:
	return {"ok": false, "code": &"LAUNCH_ENCOUNTER_EXTENSION_INVALID", "context": {"field": field}}
