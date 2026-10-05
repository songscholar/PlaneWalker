extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p15_catalog_fixtures.gd")
const Ids := preload("res://scripts/enemies/launch/launch_hostile_ids.gd")
const Runtime := preload("res://scripts/dungeon/launch_encounter_runtime.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = Suite.new()
	suite.assert_true(FileAccess.file_exists("res://data/content_packs/base/content/launch_encounters.json"), "forty Launch recipes must exist in the authoritative authored catalog")
	var implementation = load("res://scripts/dungeon/launch_encounter_catalog.gd")
	suite.assert_true(implementation != null, "real Launch catalog implementation exists")
	if implementation == null:
		suite.finish(get_tree())
		return
	var catalog: RefCounted = implementation.new()
	var registry := Fixtures.registry()
	suite.assert_true(catalog.configure_authored().ok, "inactive catalog reads authoritative hostile content without activating Base Pack")
	suite.assert_true(catalog.configure(registry).ok, "five profiles with closed references configure")
	suite.assert_equal(catalog.snapshot().enemy_count, 22, "catalog requires twenty-two ordinary identities")
	suite.assert_equal(catalog.snapshot().recipe_count, 42, "catalog retains forty historical recipes and two explicit additive elite recipes")
	for floor_index: int in range(5):
		var profile_id: String = Ids.PROFILE_IDS[floor_index]
		var boss: Dictionary = catalog.encounter_definition(Ids.BOSS_ENCOUNTER_IDS[floor_index], 12, 1, "boss")
		suite.assert_equal(boss.waves[0].spawns[0].enemy_id, Ids.BOSS_IDS[floor_index], "Boss identity is distinct from Warden")
		suite.assert_true(Runtime.normalize_encounter(boss).ok, "Boss encounter executes through fixed-frame runtime")
		var chosen: Dictionary = catalog.encounter_definition(profile_id, 1729, 3, "combat")
		suite.assert_true(Runtime.normalize_encounter(chosen).ok, "combat choice is executable")
		suite.assert_equal(catalog.encounter_definition(profile_id, 1729, 3, "combat"), chosen, "same seed resolves same recipe and positions")
		var next: Dictionary = catalog.resolve_for_node(profile_id, 1729, "node:4", "combat", "", chosen.recipe_id)
		suite.assert_true(not next.is_empty() and next.recipe_id != chosen.recipe_id, "consecutive compatible choices avoid immediate repeat")
		var elite: Dictionary = catalog.encounter_definition(profile_id, 1729, 4, "elite")
		suite.assert_true(Runtime.normalize_encounter(elite).ok, "elite roster preserves floor affix counts")
		for recipe: Dictionary in registry.rows.launch_encounter_profile[floor_index].recipes:
			var direct: Dictionary = catalog.encounter_definition(profile_id + "." + recipe.id, 0, 0, recipe.room_type)
			suite.assert_true(Runtime.normalize_encounter(direct).ok, "every authored recipe resolves directly")
			for template_id: String in recipe.template_ids:
				var compatible: Dictionary = catalog.resolve_for_node(profile_id, 1729, "node:template", recipe.room_type, template_id)
				suite.assert_equal(compatible.get("recipe_id"), recipe.id, "each actual compatible template resolves its authored recipe")
	suite.assert_equal(catalog.encounter_definition("unknown_launch", 1, 1, "combat"), {}, "unknown Launch reference rejects")
	suite.assert_equal(catalog.encounter_definition(Ids.PROFILE_IDS[0], 1, 1, "shop"), {}, "unsupported room type rejects")
	suite.assert_equal(catalog.resolve_for_node(Ids.PROFILE_IDS[0], 1, "node:1", "combat", "missing_template"), {}, "no compatible template rejects")
	suite.assert_equal(catalog.enemy_definition("chrono_warden"), {}, "Launch cannot resolve M1 compatibility Boss")
	suite.assert_equal(catalog.spawn_slot("enemy_wave_primary").node_path, "EncounterAnchors/enemy_wave_primary", "Launch uses real streamed anchors")
	suite.assert_equal(catalog.spawn_slot("elite_primary").node_path, "EncounterAnchors/elite_primary", "elite waves bind actual authored elite anchor")
	suite.assert_true(catalog.has_method("resolve_for_event"), "Launch event ambush resolves against actual event geometry")
	if catalog.has_method("resolve_for_event"):
		for template_id: String in ["room_event_shrine", "room_event_crossroads", "room_event_mirror_hall"]:
			var event_template: Dictionary = registry.get_content(StringName(template_id))
			var event_encounter: Dictionary = catalog.resolve_for_event(Ids.PROFILE_IDS[0], 6, "layer_03_c", event_template)
			suite.assert_true(not event_encounter.is_empty() and event_encounter.get("room_type") == "combat", "event geometry accepts an authored ordinary combat recipe")
			suite.assert_equal(catalog.resolve_for_event(Ids.PROFILE_IDS[0], 6, "layer_03_c", event_template), event_encounter, "event recipe and offsets are deterministic")
			suite.assert_equal(catalog.encounter_definition(event_encounter.get("id", "")), event_encounter, "event resolution preserves the concrete authored recipe")
			suite.assert_equal(catalog.resolve_for_node(Ids.PROFILE_IDS[0], 6, "layer_03_c", "combat", template_id), {}, "event resolution cannot weaken ordinary template compatibility")
		var missing_event_anchor: Dictionary = registry.get_content(&"room_event_crossroads")
		missing_event_anchor.spawn_anchors = [missing_event_anchor.spawn_anchors[0]]
		suite.assert_equal(catalog.resolve_for_event(Ids.PROFILE_IDS[0], 6, "layer_03_c", missing_event_anchor), {}, "event recipes require their actual declared enemy anchor")
		var entry_overlap: Dictionary = registry.get_content(&"room_event_crossroads")
		entry_overlap.spawn_anchors[1].position = entry_overlap.spawn_anchors[0].position.duplicate()
		suite.assert_equal(catalog.resolve_for_event(Ids.PROFILE_IDS[0], 6, "layer_03_c", entry_overlap), {}, "event geometry refuses overlap with Player entry")
		suite.assert_equal(catalog.resolve_for_event(Ids.PROFILE_IDS[0], 6, "", registry.get_content(&"room_event_crossroads")), {}, "event resolution requires actual node identity")
		suite.assert_equal(catalog.resolve_for_event(Ids.PROFILE_IDS[0], 6, "layer_03_c", registry.get_content(&"room_combat_open_field")), {}, "event resolution rejects ordinary rooms")
		suite.assert_equal(catalog.resolve_for_event("unknown_launch", 6, "layer_03_c", registry.get_content(&"room_event_crossroads")), {}, "event resolution rejects unknown profiles")
	var isolated: Dictionary = catalog.enemy_definition("shattered_sentinel")
	isolated.scene = "res://arbitrary.tscn"
	suite.assert_true(catalog.enemy_definition("shattered_sentinel").scene.ends_with("enemy_shattered_sentinel.tscn"), "actor lookups are deeply isolated")
	for category: String in ["enemy_definition", "boss_definition", "elite_affix_definition", "launch_encounter_profile"]:
		var incomplete := Fixtures.registry()
		incomplete.rows[category].pop_back()
		suite.assert_true(not catalog.configure(incomplete).ok, "missing " + category + " rejects activation")
		suite.assert_equal(catalog.snapshot(), {}, "failed catalog configure clears old state")
	var dangling := Fixtures.registry()
	dangling.rows.launch_encounter_profile[0].recipes[0].waves[0].spawns[0].enemy_id = "forge_spirit"
	suite.assert_true(not catalog.configure(dangling).ok, "undeclared Expansion species rejects")
	var foreign_scene := Fixtures.registry()
	foreign_scene.rows.enemy_definition[0].scene = "../private.tscn"
	suite.assert_true(not catalog.configure(foreign_scene).ok, "scene path cannot leave Base Pack")
	var duplicate := Fixtures.registry()
	duplicate.rows.launch_encounter_profile[0].recipes[1].id = duplicate.rows.launch_encounter_profile[0].recipes[0].id
	suite.assert_true(not catalog.configure(duplicate).ok, "duplicate recipe ID rejects")
	var over_budget := Fixtures.registry()
	over_budget.rows.launch_encounter_profile[0].recipes[0].threat_budget = 1
	suite.assert_true(not catalog.configure(over_budget).ok, "recipe threat budget cannot be undersized")
	var invalid_pair := Fixtures.registry()
	invalid_pair.rows.launch_encounter_profile[2].recipes[5].waves[0].spawns[0].affix_ids = ["frenzy", "fortified"]
	suite.assert_true(not catalog.configure(invalid_pair).ok, "symmetric excluded elite pair rejects")
	var wrong_floor := Fixtures.registry()
	wrong_floor.rows.launch_encounter_profile[0].recipes[0].template_ids = ["room_combat_void_grove"]
	suite.assert_true(not catalog.configure(wrong_floor).ok, "template outside authored floor compatibility rejects")
	var bad_anchor := Fixtures.registry()
	bad_anchor.rows.room_template[10].spawn_anchors[1].id = "missing_elite_anchor"
	suite.assert_true(not catalog.configure(bad_anchor).ok, "missing physical elite anchor rejects")
	var outside := Fixtures.registry()
	outside.rows.launch_encounter_profile[0].recipes[0].waves[0].spawns[0].spawn_offset.x = -320
	suite.assert_true(not catalog.configure(outside).ok, "offset outside sixteen-pixel room margin rejects")
	var overlap := Fixtures.registry()
	overlap.rows.launch_encounter_profile[0].recipes[0].waves[0].spawns[1].spawn_offset = overlap.rows.launch_encounter_profile[0].recipes[0].waves[0].spawns[0].spawn_offset.duplicate()
	suite.assert_true(not catalog.configure(overlap).ok, "actors less than thirty-two pixels apart reject")
	var malformed_affix := Fixtures.registry()
	malformed_affix.rows.elite_affix_definition[0].parameters.damage_multiplier = true
	suite.assert_true(not catalog.configure(malformed_affix).ok, "actual closed elite affix definition is parsed")
	var profile_script = load("res://scripts/dungeon/launch_encounter_profile.gd")
	var parser: RefCounted = profile_script.new()
	for field: String in Fixtures.profile(0):
		var missing := Fixtures.profile(0)
		missing.erase(field)
		suite.assert_true(not parser.configure(missing).ok, "profile requires " + field)
		suite.assert_equal(parser.snapshot(), {}, "failed profile parse clears state")
	var malformed := Fixtures.profile(0)
	malformed.recipes[0].waves[0].warning_frames = true
	suite.assert_true(not parser.configure(malformed).ok, "Boolean cannot become wave warning")
	malformed = Fixtures.profile(0)
	malformed.recipes[0].template_ids.append("room_elite_arena")
	suite.assert_true(not parser.configure(malformed).ok, "mixed template type rejects")
	malformed = Fixtures.profile(0)
	malformed.references.pop_back()
	suite.assert_true(not parser.configure(malformed).ok, "profile references close exact actor set")
	suite.finish(get_tree())
