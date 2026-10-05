extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const BASE := "res://data/content_packs/base/"
const COUNTS := {"meta_node": 42, "hub_district": 3, "forge_definition": 20, "narrative_definition": 57, "narrative_source_definition": 13, "tutorial_definition": 34, "enemy_definition": 22, "boss_definition": 5, "summon_definition": 9, "elite_affix_definition": 10, "launch_encounter_profile": 5, "launch_encounter_extension": 2, "cosmetic_definition": 15}
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	_test_activation()
	_test_atomic_rejection()
	suite.finish(get_tree())


func _test_activation() -> void:
	var registry := Registry.new()
	var report = registry.load_packs([{ "path": BASE + "pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "actual complete pack activates: %s" % str(report.blocking_errors))
	if report.has_blocking_errors():
		return
	suite.assert_equal(report.loaded_count, 448, "complete base content includes fifteen cosmetics and two encounter extensions")
	for category: String in COUNTS:
		suite.assert_equal(registry.get_by_category(StringName(category), &"LAUNCH").size(), COUNTS[category], "complete %s count" % category)
		suite.assert_true(registry.get_by_category(StringName(category), &"M1").is_empty(), "new %s content does not widen M1" % category)
	var recipe_count := 0
	for profile: Dictionary in registry.get_by_category(&"launch_encounter_profile", &"LAUNCH"):
		recipe_count += profile.recipes.size()
	suite.assert_equal(recipe_count, 40, "all forty authored encounter recipes remain accessible")
	var factory := Factory.new()
	suite.assert_true(factory.has_method("from_registry"), "production Meta factory accepts activated Registry")
	suite.assert_true(registry.has_method("get_catalog_entries"), "Registry exposes detached authored catalogs")
	if factory.has_method("from_registry") and registry.has_method("get_catalog_entries"):
		var loaded: Dictionary = factory.call("from_registry", registry, &"LAUNCH")
		suite.assert_true(loaded.ok, "activated actual content creates the production Meta catalog")
		if loaded.ok:
			suite.assert_equal(loaded.context.catalog.fingerprint(), Factory.load_base().context.catalog.fingerprint(), "Registry and offline base resolve identical domain identities")
		suite.assert_true(not factory.call("from_registry", registry, &"M1").ok and not factory.call("from_registry", RefCounted.new()).ok, "Meta factory rejects unsupported milestones and foreign objects")
		var rows: Array = registry.call("get_catalog_entries", &"hub_district", &"LAUNCH")
		if not rows.is_empty():
			suite.assert_true(not rows[0].has("pack_id") and not rows[0].has("pack_version"), "strict authored catalogs exclude storage provenance")
			rows[0].functions[0].npc_id = "invented"
			suite.assert_true(registry.get_content(&"hub_council").functions[0].npc_id != "invented", "catalog caller cannot alias Registry ownership")


func _test_atomic_rejection() -> void:
	var all: Array = []
	for file: String in ["archetype_profiles", "blessings", "character_runtime_profiles", "characters", "curses", "dungeon_events", "economy_profiles", "floors", "items", "merchants", "room_templates", "talents", "time_abilities", "weapon_runtime_profiles", "weapons", "meta_nodes", "hub_districts", "forge_definitions", "narrative_definitions", "narrative_sources", "tutorial_definitions", "enemies", "bosses", "summons", "elite_affixes", "launch_encounters"]:
		all.append_array(JSON.parse_string(FileAccess.get_file_as_string(BASE + "content/" + file + ".json")))
	var positive := Registry.new()
	var accepted = positive.load_packs([{ "path": _fixture(all), "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not accepted.has_blocking_errors() and accepted.loaded_count == 431, "positive complete composite fixture proves negative probes reach real validation")
	var corrupt := all.duplicate(true)
	_find(corrupt, "hub_council").functions[0].position.unexpected = true
	_assert_rejected(corrupt, "unknown nested Hub fields reject atomically")
	corrupt = all.duplicate(true)
	_find(corrupt, "hub_council").functions[0].npc_id = "invented"
	_assert_rejected(corrupt, "Hub NPC references must resolve")
	corrupt = all.duplicate(true)
	_find(corrupt, "hub_council").name_key = "MISSING_LOCALIZATION"
	_assert_rejected(corrupt, "P16 localization is checked before activation")
	corrupt = all.duplicate(true)
	corrupt.erase(_find(corrupt, "meta_w_01"))
	_assert_rejected(corrupt, "incomplete Meta catalogs reject before activation")
	corrupt = all.duplicate(true)
	_find(corrupt, "meta_w_01").meta_effects[0].unexpected = true
	_assert_rejected(corrupt, "closed Meta domain shape rejects nested additions")
	corrupt = all.duplicate(true)
	var sources: Array = corrupt.filter(func(row: Dictionary) -> bool: return row.category == "narrative_source_definition")
	corrupt.erase(sources[0])
	_assert_rejected(corrupt, "all thirteen native narrative sources are mandatory")
	corrupt = all.duplicate(true)
	var npcs: Array = corrupt.filter(func(row: Dictionary) -> bool: return row.category == "narrative_definition" and row.definition_kind == "npc")
	npcs[0].dialogue_nodes[0].choices[0].unexpected = true
	_assert_rejected(corrupt, "nested narrative choices remain closed at native activation")
	corrupt = all.duplicate(true)
	var lessons: Array = corrupt.filter(func(row: Dictionary) -> bool: return row.category == "tutorial_definition" and row.definition_kind == "lesson")
	lessons[0].receipt_requirements[0].count = -1
	_assert_rejected(corrupt, "tutorial objectives require bounded genuine counts")
	corrupt = all.duplicate(true)
	corrupt.erase(_find(corrupt, "corrosive_moth"))
	_assert_rejected(corrupt, "missing authored enemy cannot activate an incomplete Launch roster")
	corrupt = all.duplicate(true)
	var encounters: Array = corrupt.filter(func(row: Dictionary) -> bool: return row.category == "launch_encounter_profile")
	encounters[0].recipes[0].template_ids = ["room_combat_missing"]
	_assert_rejected(corrupt, "encounter templates require actual Registry closure")
	corrupt = all.duplicate(true)
	encounters = corrupt.filter(func(row: Dictionary) -> bool: return row.category == "launch_encounter_profile")
	encounters[0].recipes[-1].template_ids = ["room_elite_missing"]
	_assert_rejected(corrupt, "later encounter recipes also require Registry closure")
	var path := _fixture(corrupt)
	var optional := Registry.new()
	var report = optional.load_packs([{ "path": BASE + "pack.json", "required": true}, {"path": path, "required": false}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "optional malformed specialized pack remains isolated")
	suite.assert_equal(report.loaded_count, 448, "optional isolation preserves complete base contents and encounter extensions")
	suite.assert_equal(report.isolated_pack_ids, ["p16-registry-probe"], "optional failure names only the malformed pack")
	var extended := all.duplicate(true)
	extended.append_array(JSON.parse_string(FileAccess.get_file_as_string(BASE + "content/launch_encounter_extensions.json")))
	var extended_registry := Registry.new()
	var extended_report = extended_registry.load_packs([{ "path": _fixture(extended), "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not extended_report.has_blocking_errors() and extended_report.loaded_count == 433, "positive extensions fixture reaches complete reference validation")
	_find(extended, "encounter_extension_ruins_terminal_v2").recipes[0].template_ids = ["room_elite_missing"]
	_assert_rejected(extended, "encounter extensions share exact template Registry closure")


func _assert_rejected(rows: Array, message: String) -> void:
	var registry := Registry.new()
	var report = registry.load_packs([{ "path": _fixture(rows), "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(report.has_blocking_errors(), message)
	suite.assert_equal(report.loaded_count, 0, "required specialized failure exposes no partial entries")
	suite.assert_true(registry.get_by_category(&"character").is_empty(), "ordinary entries are also rolled back")


func _find(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.id == id:
			return row
	return {}


func _fixture(rows: Array) -> String:
	var root := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("p16-registry-probe")
	DirAccess.make_dir_recursive_absolute(root)
	var content := JSON.stringify(rows, "\t")
	var localization := FileAccess.get_file_as_string(BASE + "localization/translations.csv")
	_write(root.path_join("content.json"), content)
	_write(root.path_join("translations.csv"), localization)
	var pack := {"pack_id": "p16-registry-probe", "pack_version": "0.4.0-dev", "schema_version": 2, "game_version_range": ">=0.4.0-dev <1.0.0", "dependencies": [], "load_order": 1, "content_manifest": ["content.json"], "localization_sources": ["translations.csv"], "asset_manifest": [], "integrity_hashes": {"content.json": content.sha256_text(), "translations.csv": localization.sha256_text()}, "entitlement_tag": ""}
	var path := root.path_join("pack.json")
	_write(path, JSON.stringify(pack, "\t"))
	return path


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	suite.assert_true(file != null, "isolated Registry fixture is writable")
	if file != null:
		file.store_string(text)
