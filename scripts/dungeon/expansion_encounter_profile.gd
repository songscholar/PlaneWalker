class_name ExpansionEncounterProfile
extends RefCounted

const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Common := preload("res://scripts/enemies/launch/hostile_definition_contract.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const Enemy := preload("res://scripts/enemies/expansion/expansion_enemy_definition.gd")
const Profile := preload("res://scripts/dungeon/launch_encounter_profile.gd")
const Runtime := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const FIELDS := ["category", "id", "schema_version", "name_key", "description_key", "availability", "tags", "compatibility", "references", "floor_id", "profile_id", "selection_revision", "recipes"]
var _definition := {}


func configure(source: Dictionary) -> Dictionary:
	_definition.clear()
	if not Contract.exact_fields(source, FIELDS) or source.category != "expansion_encounter_profile" or not Contract.integer_in_range(source.schema_version, 1, 1) or not Contract.integer_in_range(source.selection_revision, 3, 3) or not Ids.FLOOR_IDS.has(source.floor_id):
		return Common.failure("expansion_encounter", "identity")
	var index: int = Ids.FLOOR_IDS.find(source.floor_id)
	var enemy_id: String = Enemy.IDS[index]
	if source.id != "expansion_profile_" + enemy_id or source.profile_id != Ids.PROFILE_IDS[index] or source.availability != ["EXPANSION"] or source.compatibility != {} or not Common.localization_key(source.name_key) or not Common.localization_key(source.description_key) or not Common.string_list(source.tags, [], 1, 8, "tags").ok:
		return Common.failure("metadata", "identity")
	if not source.recipes is Array or source.recipes.size() != 1 or not source.recipes[0] is Dictionary:
		return Common.failure("recipes", "one_authored_recipe_required")
	var recipe: Dictionary = source.recipes[0]
	if not Contract.exact_fields(recipe, Profile.RECIPE_FIELDS) or recipe.id != enemy_id + "_frontiers_v3" or recipe.room_type != "combat" or recipe.template_ids != ["room_combat_open_field"] or not Contract.integer_in_range(recipe.threat_budget, 1, 5):
		return Common.failure("recipe", "identity")
	var parsed := Runtime.normalize_encounter({"id": source.profile_id + "." + recipe.id, "floor_id": source.floor_id, "recipe_id": recipe.id, "room_type": "combat", "waves": recipe.waves})
	if not parsed.ok or parsed.definition.waves.size() != 1 or parsed.definition.waves[0].spawns.size() != 1 or parsed.definition.waves[0].spawns[0].enemy_id != enemy_id or parsed.definition.waves[0].spawns[0].elite:
		return Common.failure("waves", "one_matching_enemy_required")
	var expected: Array[String] = [enemy_id, source.floor_id, source.profile_id, "room_combat_open_field"]
	expected.sort()
	var references: Variant = source.references
	if not references is Array:
		return Common.failure("references", "array_required")
	references = references.duplicate()
	references.sort()
	if references != expected:
		return Common.failure("references", "exact_binding_required")
	_definition = source.duplicate(true)
	_definition.references = expected
	_definition.recipes[0].waves = parsed.definition.waves
	return {"ok": true, "definition": snapshot(), "context": {}}


func snapshot() -> Dictionary:
	return _definition.duplicate(true)
