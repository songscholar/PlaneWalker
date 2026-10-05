extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const SOURCE := "res://scripts/modes/authored_challenge_catalog.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	if not ResourceLoader.exists(SOURCE):
		suite.assert_true(false, "authored challenges require actual validated fixed Builds, ordered Bosses and five distinct objectives")
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var catalog: RefCounted = load(SOURCE).new()
	suite.assert_true(catalog.configure(registry), "authored catalog validates real production effects, weapon support, Bosses and rooms")
	var entries: Array = catalog.entries()
	suite.assert_equal(entries.size(), 5, "five authored fixed weapon trials exist")
	var weapons := {}
	var objectives := {}
	for definition: Dictionary in entries:
		weapons[definition.weapon_id] = true
		objectives[definition.objective.kind] = true
		suite.assert_equal(definition.boss_ids.size(), 3, "each trial has three ordered production Bosses")
		suite.assert_equal(catalog.build_definitions(definition.id).size(), 5, "each trial installs exactly three passive items one blessing and one curse")
		for stage_index: int in range(3):
			var stage: Dictionary = catalog.stage(definition.id, stage_index)
			suite.assert_equal(stage.boss_id, definition.boss_ids[stage_index], "authored stage uses the declared production Boss")
			suite.assert_equal(catalog.request(definition.id, stage_index).weapon_id, definition.weapon_id, "stage request uses its fixed authored weapon")
			stage.runtime_definition.clear()
			suite.assert_true(not catalog.stage(definition.id, stage_index).runtime_definition.is_empty(), "caller cannot mutate actual arena definitions")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/production/modes/authored_challenges.json"))
	for mutation: String in ["duplicate_id", "duplicate_weapon", "missing_boss", "active_item", "unsupported_weapon_effect", "invalid_objective", "unbounded_frames", "unknown_field"]:
		var changed: Dictionary = source.duplicate(true)
		match mutation:
			"duplicate_id": changed.sets[1].id = changed.sets[0].id
			"duplicate_weapon": changed.sets[1].weapon_id = changed.sets[0].weapon_id
			"missing_boss": changed.sets[0].boss_ids[0] = "fake"
			"active_item": changed.sets[0].item_ids[0] = "absolute_zero_device"
			"unsupported_weapon_effect": changed.sets[0].item_ids[0] = "piercing_draw"
			"invalid_objective": changed.sets[0].objective.kind = "description_only"
			"unbounded_frames": changed.sets[0].objective.limit = 2147483647
			"unknown_field": changed.sets[0].unknown = true
		var invalid: RefCounted = load(SOURCE).new()
		suite.assert_true(not invalid.configure(registry, changed), "invalid authored catalog refuses before publication: " + mutation)
	suite.assert_equal(weapons.size(), 5, "five trials use five unique weapons")
	suite.assert_equal(objectives.size(), 5, "five trials use distinct executable objectives")
	entries[0].item_ids.clear()
	suite.assert_equal(catalog.entries()[0].item_ids.size(), 3, "catalog getters return detached content")
	suite.assert_true(catalog.stage("fake", 0).is_empty() and catalog.stage(catalog.entries()[0].id, 3).is_empty(), "unknown set or out-of-route stage refuses")
	suite.finish(get_tree())
