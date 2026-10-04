class_name LaunchEncounterCatalog
extends RefCounted

const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const Contract := preload("res://scripts/enemies/launch/hostile_action_contract.gd")
const Profile := preload("res://scripts/dungeon/launch_encounter_profile.gd")
const Runtime := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const Seed := preload("res://scripts/core/seed_service.gd")
const BASE_RESOURCE_ROOT := "res://data/content_packs/base/"

var _actors: Dictionary = {}
var _profiles: Dictionary = {}
var _recipes: Dictionary = {}
var _boss_encounters: Dictionary = {}
var _snapshot: Dictionary = {}


func configure(registry: RefCounted) -> Dictionary:
	_clear()
	if registry == null or not registry.has_method("get_by_category") or not registry.has_method("get_content"):
		return _failure("registry", "unsupported")
	for category: String in ["enemy_definition", "boss_definition", "elite_affix_definition", "launch_encounter_profile"]:
		var rows: Variant = registry.get_by_category(StringName(category), &"LAUNCH")
		if not rows is Array:
			return _failure(category, "invalid_collection")
		var expected: Array = Ids.enemy_ids() if category == "enemy_definition" else (Ids.BOSS_IDS if category == "boss_definition" else (Ids.AFFIX_IDS if category == "elite_affix_definition" else Ids.PROFILE_IDS))
		if rows.size() != expected.size():
			return _failure(category, "incomplete_launch_collection")
		var seen: Dictionary = {}
		for candidate: Variant in rows:
			if not candidate is Dictionary or candidate.get("category") != category or typeof(candidate.get("id")) != TYPE_STRING or not expected.has(candidate.id) or seen.has(candidate.id):
				return _failure(category, "unsupported_or_duplicate_identity")
			seen[candidate.id] = true
			if category in ["enemy_definition", "boss_definition"]:
				var actor_result := _normalize_actor(candidate, category)
				if not actor_result.ok:
					return actor_result
				_actors[candidate.id] = actor_result.definition
			elif category == "launch_encounter_profile":
				var parser := Profile.new()
				var profile_result := parser.configure(candidate)
				if not profile_result.ok:
					return _failure("profile", "invalid_definition", profile_result)
				_profiles[candidate.id] = profile_result.definition
	for profile: Dictionary in _profiles.values():
		for recipe: Dictionary in profile.recipes:
			for template_id: String in recipe.template_ids:
				var template: Variant = registry.get_content(StringName(template_id))
				if not template is Dictionary or template.get("category") != "room_template" or template.get("room_type") != recipe.room_type:
					return _failure("template_id", "dangling_or_wrong_type")
			for wave: Dictionary in recipe.waves:
				var threat := 0
				for spawn: Dictionary in wave.spawns:
					if not _actors.has(spawn.enemy_id) or _actors[spawn.enemy_id].category != "enemy_definition":
						return _failure("enemy_id", "dangling_reference")
					threat += int(_actors[spawn.enemy_id].threat_cost) + (3 if spawn.elite else 0)
				if threat > int(recipe.threat_budget):
					return _failure("threat_budget", "wave_exceeds_budget")
			var encounter := {"id": profile.id + "." + recipe.id, "floor_id": profile.floor_id, "recipe_id": recipe.id, "room_type": recipe.room_type, "waves": recipe.waves.duplicate(true)}
			_recipes[encounter.id] = encounter
		var floor_index := Ids.PROFILE_IDS.find(profile.id)
		var boss_warning := 40 if floor_index == 0 else (25 if floor_index == 4 else 30)
		var boss_encounter := {
			"id": profile.boss_encounter_id, "floor_id": profile.floor_id, "recipe_id": profile.boss_id, "room_type": "boss",
			"waves": [{"id": profile.boss_id + "_wave_1", "delay_frames": 0, "warning_frames": boss_warning, "spawns": [
				{"id": profile.boss_id + "_spawn_1", "enemy_id": profile.boss_id, "spawn_slot_id": "boss_primary", "spawn_offset": {"x": 0.0, "y": 0.0}, "elite": false, "affix_ids": [], "mechanism_ids": []},
			]}],
		}
		var boss_result := Runtime.normalize_encounter(boss_encounter)
		if not boss_result.ok:
			return _failure("boss_encounter", "invalid_definition")
		_boss_encounters[profile.boss_encounter_id] = boss_result.definition
	_snapshot = {"schema_version": 1, "enemy_count": 22, "boss_count": 5, "affix_count": 10, "profile_count": _profiles.size(), "recipe_count": _recipes.size(), "boss_encounter_count": _boss_encounters.size()}
	return {"ok": true, "snapshot": snapshot(), "context": {}}


func encounter_definition(encounter_id: String, run_seed: int = 0, room_number: int = 0, room_type: String = "") -> Dictionary:
	if _snapshot.is_empty() or room_number < 0:
		return {}
	if _boss_encounters.has(encounter_id):
		return _boss_encounters[encounter_id].duplicate(true) if room_type in ["", "boss"] else {}
	if _recipes.has(encounter_id):
		return _recipes[encounter_id].duplicate(true) if room_type in ["", str(_recipes[encounter_id].room_type)] else {}
	return resolve_for_node(encounter_id, run_seed, "room_%d" % room_number, "combat" if room_type.is_empty() else room_type)


func resolve_for_node(profile_id: String, run_seed: int, node_id: String, room_type: String, template_id: String = "", previous_recipe_id: String = "") -> Dictionary:
	if _snapshot.is_empty() or not _profiles.has(profile_id) or node_id.is_empty() or node_id.length() > 64 or room_type not in ["combat", "elite"]:
		return {}
	var profile: Dictionary = _profiles[profile_id]
	var candidates: Array[String] = []
	for recipe: Dictionary in profile.recipes:
		if recipe.room_type == room_type and (template_id.is_empty() or recipe.template_ids.has(template_id)):
			candidates.append(recipe.id)
	candidates.sort()
	if candidates.size() > 1:
		candidates.erase(previous_recipe_id)
	if candidates.is_empty():
		return {}
	var rng := Seed.make_rng(run_seed, StringName("launch_encounter_v1:%s:%s" % [profile.floor_id, node_id]))
	var recipe_id: String = candidates[rng.randi_range(0, candidates.size() - 1)]
	return _recipes[profile_id + "." + recipe_id].duplicate(true)


func enemy_definition(enemy_id: String) -> Dictionary:
	return _actors.get(enemy_id, {}).duplicate(true) if not _snapshot.is_empty() else {}


func spawn_slot(slot_id: String) -> Dictionary:
	if _snapshot.is_empty() or slot_id not in ["enemy_wave_primary", "boss_primary"]:
		return {}
	return {"id": slot_id, "anchor_id": slot_id, "node_path": "EncounterAnchors/" + slot_id}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _normalize_actor(source: Dictionary, category: String) -> Dictionary:
	var expected_scene: String = "assets/enemies/launch/enemy_%s.tscn" % source.id if category == "enemy_definition" else "assets/bosses/launch/boss_%s.tscn" % source.id
	var floor_index: int = int(Ids.ENEMY_FLOORS[source.id]) if category == "enemy_definition" else Ids.BOSS_IDS.find(source.id) + 1
	if source.get("scene") != expected_scene or not Contract.integer_in_range(source.get("floor_index"), floor_index, floor_index):
		return _failure("scene", "actor_identity_mismatch")
	if category == "enemy_definition" and not Contract.integer_in_range(source.get("threat_cost"), 1, 5):
		return _failure("threat_cost", "invalid")
	var result := source.duplicate(true)
	result.scene = BASE_RESOURCE_ROOT + expected_scene
	result.floor_index = floor_index
	if category == "enemy_definition":
		result.threat_cost = int(source.threat_cost)
	return {"ok": true, "definition": result}


func _failure(field: String, reason: String, detail: Dictionary = {}) -> Dictionary:
	_clear()
	return {"ok": false, "code": &"LAUNCH_CATALOG_INVALID", "context": {"field": field, "reason": reason, "detail": detail.duplicate(true)}}


func _clear() -> void:
	_actors.clear()
	_profiles.clear()
	_recipes.clear()
	_boss_encounters.clear()
	_snapshot.clear()
