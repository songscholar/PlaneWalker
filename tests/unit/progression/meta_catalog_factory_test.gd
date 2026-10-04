extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const ProjectionScript := preload("res://scripts/progression/meta_run_projection.gd")


func _ready() -> void:
	var suite = Suite.new()
	var loaded: Dictionary = Factory.load_base()
	suite.assert_true(loaded.ok, "production catalogs configure without test fixtures: %s" % str(loaded.get("code")))
	if not loaded.ok:
		suite.finish(get_tree())
		return
	var catalog: RefCounted = loaded.context.catalog
	suite.assert_equal(catalog.ids().size(), 42, "all authored legacy nodes retain domain identity")
	for row: Array in [["item", 50], ["enchantment", 15], ["artifact", 10], ["environment_record", 21], ["ending", 5], ["tutorial_lesson", 10], ["tutorial_hint", 15], ["training_task", 6], ["archetype", 8]]:
		suite.assert_equal(loaded.context.references[row[0]].size(), row[1], "production %s references are complete" % row[0])
	var profile = Profile.new()
	suite.assert_true(profile.configure(catalog), "production profile derives from authored content")
	var snapshot: Dictionary = profile.snapshot()
	snapshot.discovered_items = [loaded.context.references.item[0]]
	snapshot.narrative_state.environment_records = ["E1-1"]
	snapshot.narrative_state.artifacts = ["wardens_badge"]
	snapshot.narrative_state.endings = ["shattered_freedom"]
	snapshot.tutorial_state.completed_lessons = ["movement_dodge"]
	suite.assert_true(profile.restore_snapshot(snapshot), "actual authored reference identities persist in strict profile")
	var projection: Dictionary = ProjectionScript.from_profile(profile.snapshot(), catalog)
	suite.assert_true(projection.ok and ProjectionScript.validate(projection.context.projection, catalog), "authoritative catalog validates immutable run effects")
	var wrong := profile.snapshot()
	wrong.narrative_state.artifacts = ["invented-artifact"]
	suite.assert_true(not profile.restore_snapshot(wrong), "invented progression reference refuses")
	var forged := profile.snapshot()
	forged.unlocked_nodes = ["F-01", "F-02", "F-03"]
	forged.forge_state.sword.enchant_preferences = ["EN-01", "EN-04"]
	suite.assert_true(profile.can_restore_snapshot(forged), "positive control: independent element/time enchants fit two unlocked slots")
	for pair: Array in [["EN-01", "EN-02"], ["EN-01", "EN-03"], ["EN-02", "EN-03"], ["EN-04", "EN-05"]]:
		forged.forge_state.sword.enchant_preferences = pair
		suite.assert_true(not profile.can_restore_snapshot(forged), "mutually exclusive %s preferences cannot enter a saved profile" % str(pair))
	suite.finish(get_tree())
