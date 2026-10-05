class_name LaunchEncounterCatalog
extends RefCounted

const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const Profile := preload("res://scripts/dungeon/launch_encounter_profile.gd")
const Extension := preload("res://scripts/dungeon/launch_encounter_extension.gd")
const Runtime := preload("res://scripts/dungeon/launch_encounter_runtime.gd")
const Seed := preload("res://scripts/core/seed_service.gd")
const Enemy := preload("res://scripts/enemies/launch/enemy_definition.gd")
const Boss := preload("res://scripts/enemies/launch/boss_definition.gd")
const Affix := preload("res://scripts/enemies/launch/elite_affix_definition.gd")
const Room := preload("res://scripts/dungeon/room_template_definition.gd")
const AuthoredSource := preload("res://scripts/dungeon/launch_hostile_content_source.gd")
const BASE_RESOURCE_ROOT := "res://data/content_packs/base/"

var _actors: Dictionary = {}
var _affixes: Dictionary = {}
var _profiles: Dictionary = {}
var _recipes: Dictionary = {}
var _extensions: Dictionary = {}
var _boss_encounters: Dictionary = {}
var _snapshot: Dictionary = {}


func configure_authored() -> Dictionary:
	var source := AuthoredSource.new()
	var loaded := source.load_authored()
	if not loaded.ok:
		return _failure("source", "invalid_authored_collection", loaded)
	return configure(source)


func configure(registry: RefCounted) -> Dictionary:
	_clear()
	if registry == null or not registry.has_method("get_by_category") or not registry.has_method("get_content"):
		return _failure("registry", "unsupported")
	for category: String in ["enemy_definition", "boss_definition", "elite_affix_definition", "launch_encounter_profile"]:
		var rows: Variant = registry.get_catalog_entries(StringName(category), &"LAUNCH") if registry.has_method("get_catalog_entries") else registry.get_by_category(StringName(category), &"LAUNCH")
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
			else:
				var affix_result := Affix.new().configure(candidate)
				if not affix_result.ok:
					return _failure("affix", "invalid_definition", affix_result)
				_affixes[candidate.id] = affix_result.definition
	for profile: Dictionary in _profiles.values():
		var recipe_result := _register_recipes(profile.id, profile.floor_id, profile.recipes, registry)
		if not recipe_result.ok:
			return recipe_result
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
	var extensions: Variant = registry.get_catalog_entries(&"launch_encounter_extension", &"LAUNCH") if registry.has_method("get_catalog_entries") else registry.get_by_category(&"launch_encounter_extension", &"LAUNCH")
	if not extensions is Array or not extensions.is_empty() and extensions.size() != Extension.IDS.size():
		return _failure("extensions", "invalid_collection")
	for candidate: Variant in extensions:
		if not candidate is Dictionary:
			return _failure("extension", "invalid_definition")
		var parsed := Extension.new().configure(candidate)
		if not parsed.ok or _extensions.has(parsed.get("definition", {}).get("profile_id", "")):
			return _failure("extension", "invalid_or_duplicate_definition", parsed)
		var definition: Dictionary = parsed.definition
		var registered := _register_recipes(definition.profile_id, definition.floor_id, definition.recipes, registry)
		if not registered.ok:
			return registered
		_extensions[definition.profile_id] = definition.recipes.duplicate(true)
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


func resolve_for_revision(profile_id: String, run_seed: int, node_id: String, room_type: String, template_id: String, selection_revision: int, previous_recipe_id: String = "") -> Dictionary:
	if selection_revision not in [1, 2]:
		return {}
	if selection_revision == 1 or profile_id not in [Ids.PROFILE_IDS[0], Ids.PROFILE_IDS[1]] or room_type != "elite":
		return resolve_for_node(profile_id, run_seed, node_id, room_type, template_id, previous_recipe_id)
	if _snapshot.is_empty() or not _profiles.has(profile_id) or not _extensions.has(profile_id) or node_id.is_empty() or node_id.length() > 64:
		return {}
	var candidates: Array[String] = []
	var recipes: Array = _profiles[profile_id].recipes.duplicate(true)
	recipes.append_array(_extensions[profile_id])
	for recipe: Dictionary in recipes:
		if recipe.room_type == room_type and (template_id.is_empty() or recipe.template_ids.has(template_id)):
			candidates.append(recipe.id)
	candidates.sort()
	if candidates.size() > 1:
		candidates.erase(previous_recipe_id)
	if candidates.is_empty():
		return {}
	var rng := Seed.make_rng(run_seed, StringName("launch_encounter_v2:%s:%s" % [_profiles[profile_id].floor_id, node_id]))
	return _recipes[profile_id + "." + candidates[rng.randi_range(0, candidates.size() - 1)]].duplicate(true)


func enemy_definition(enemy_id: String) -> Dictionary:
	return _actors.get(enemy_id, {}).duplicate(true) if not _snapshot.is_empty() else {}


func affix_definition(affix_id: String) -> Dictionary:
	return _affixes.get(affix_id, {}).duplicate(true) if not _snapshot.is_empty() else {}


func resolve_for_event(profile_id: String, run_seed: int, node_id: String, template: Dictionary) -> Dictionary:
	if _snapshot.is_empty() or not _profiles.has(profile_id) or node_id.is_empty() or node_id.length() > 64:
		return {}
	var parsed := Room.new().configure(template)
	if not parsed.ok or parsed.definition.room_type != "event":
		return {}
	var profile: Dictionary = _profiles[profile_id]
	if not parsed.definition.floor_ids.has(profile.floor_id):
		return {}
	var candidates: Array[String] = []
	for recipe: Dictionary in profile.recipes:
		if recipe.room_type == "combat" and _valid_spawn_positions(recipe, parsed.definition):
			candidates.append(recipe.id)
	candidates.sort()
	if candidates.is_empty():
		return {}
	var rng := Seed.make_rng(run_seed, StringName("launch_event_encounter_v1:%s:%s" % [profile.floor_id, node_id]))
	return _recipes[profile_id + "." + candidates[rng.randi_range(0, candidates.size() - 1)]].duplicate(true)


func spawn_slot(slot_id: String) -> Dictionary:
	if _snapshot.is_empty() or slot_id not in ["enemy_wave_primary", "elite_primary", "boss_primary"]:
		return {}
	return {"id": slot_id, "anchor_id": slot_id, "node_path": "EncounterAnchors/" + slot_id}


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func _normalize_actor(source: Dictionary, category: String) -> Dictionary:
	var expected_scene: String = "assets/enemies/launch/enemy_%s.tscn" % source.id if category == "enemy_definition" else "assets/bosses/launch/boss_%s.tscn" % source.id
	var floor_index: int = int(Ids.ENEMY_FLOORS[source.id]) if category == "enemy_definition" else Ids.BOSS_IDS.find(source.id) + 1
	var parser: RefCounted = Enemy.new() if category == "enemy_definition" else Boss.new()
	var parsed: Dictionary = parser.configure(source)
	if not parsed.ok:
		return _failure("actor", "invalid_definition", parsed)
	var result: Dictionary = parsed.definition
	result.scene = BASE_RESOURCE_ROOT + expected_scene
	result.floor_index = floor_index
	if category == "enemy_definition":
		result.threat_cost = int(source.threat_cost)
	return {"ok": true, "definition": result}


func _valid_spawn_positions(recipe: Dictionary, template: Dictionary) -> bool:
	var entry := Vector2.ZERO
	var anchors: Dictionary = {}
	for anchor: Dictionary in template.spawn_anchors:
		anchors[anchor.id] = Vector2(float(anchor.position.x), float(anchor.position.y))
		if anchor.kind == "player":
			entry = anchors[anchor.id]
	var bounds: Dictionary = template.camera_bounds
	var safe := Rect2(float(bounds.x) + 16.0, float(bounds.y) + 16.0, float(bounds.width) - 32.0, float(bounds.height) - 32.0)
	for wave: Dictionary in recipe.waves:
		var positions: Array[Vector2] = []
		for spawn: Dictionary in wave.spawns:
			if not anchors.has(spawn.spawn_slot_id):
				return false
			var offset := Vector2(float(spawn.spawn_offset.x), float(spawn.spawn_offset.y))
			if not is_zero_approx(fposmod(offset.x, 16.0)) or not is_zero_approx(fposmod(offset.y, 16.0)):
				return false
			var point: Vector2 = anchors[spawn.spawn_slot_id] + offset
			if point.x < safe.position.x or point.y < safe.position.y or point.x > safe.end.x or point.y > safe.end.y or point.distance_to(entry) < 64.0:
				return false
			for previous: Vector2 in positions:
				if point.distance_to(previous) < 32.0:
					return false
			positions.append(point)
	return true


func _register_recipes(profile_id: String, floor_id: String, recipes: Array, registry: RefCounted) -> Dictionary:
	for recipe: Dictionary in recipes:
		for template_id: String in recipe.template_ids:
			var template: Variant = registry.get_content(StringName(template_id))
			if not template is Dictionary:
				return _failure("template_id", "dangling_or_wrong_type")
			if registry.has_method("get_catalog_entries"):
				template.erase("pack_id")
				template.erase("pack_version")
			var room_result := Room.new().configure(template)
			if not room_result.ok or template.room_type != recipe.room_type or not template.floor_ids.has(floor_id):
				return _failure("template_id", "incompatible_definition")
			if not _valid_spawn_positions(recipe, room_result.definition):
				return _failure("spawn_offset", "invalid_room_geometry")
		for wave: Dictionary in recipe.waves:
			var threat := 0
			for spawn: Dictionary in wave.spawns:
				if not _actors.has(spawn.enemy_id) or _actors[spawn.enemy_id].category != "enemy_definition":
					return _failure("enemy_id", "dangling_reference")
				threat += int(_actors[spawn.enemy_id].threat_cost) + (3 if spawn.elite else 0)
			if threat > int(recipe.threat_budget):
				return _failure("threat_budget", "wave_exceeds_budget")
		var encounter := {"id": profile_id + "." + recipe.id, "floor_id": floor_id, "recipe_id": recipe.id, "room_type": recipe.room_type, "waves": recipe.waves.duplicate(true)}
		if _recipes.has(encounter.id):
			return _failure("recipe_id", "duplicate")
		_recipes[encounter.id] = encounter
	return {"ok": true}


func _failure(field: String, reason: String, detail: Dictionary = {}) -> Dictionary:
	_clear()
	return {"ok": false, "code": &"LAUNCH_CATALOG_INVALID", "context": {"field": field, "reason": reason, "detail": detail.duplicate(true)}}


func _clear() -> void:
	_actors.clear()
	_affixes.clear()
	_profiles.clear()
	_recipes.clear()
	_extensions.clear()
	_boss_encounters.clear()
	_snapshot.clear()
