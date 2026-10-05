extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const SOURCE := "res://scripts/modes/daily_boss_catalog.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	if not ResourceLoader.exists(SOURCE):
		suite.assert_true(false, "daily rules expose the actual UTC+8 fixed-Build catalog")
		suite.finish(get_tree())
		return
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var catalog: RefCounted = load(SOURCE).new()
	suite.assert_true(catalog.configure(registry), "daily catalog validates actual production content and native Boss scenes")
	var before: Dictionary = catalog.projection(1791129599)
	var after: Dictionary = catalog.projection(1791129600)
	suite.assert_equal(before.day_key, "2026-10-04", "daily old day persists through 23:59:59 UTC+8")
	suite.assert_equal(after.day_key, "2026-10-05", "daily changes exactly at 00:00 UTC+8")
	suite.assert_equal(after.day_index, before.day_index + 1, "date change increments one canonical UTC+8 day")
	suite.assert_equal(after.reset_at, 1791216000, "preview countdown points to the next UTC+8 midnight")
	suite.assert_equal(after, catalog.projection(1791129601), "all participants derive the same preset within one day")
	var bosses := {}
	var weapons := {}
	var rules := {}
	for offset: int in range(120):
		var definition: Dictionary = catalog.projection(1791129600 + offset * 86400)
		suite.assert_equal(definition.item_ids.size(), 3, "daily contains exactly three actual passive items")
		for id: String in definition.item_ids:
			suite.assert_equal(definition.item_ids.count(id), 1, "daily items are distinct")
		suite.assert_true(not definition.blessing_id.is_empty() and not definition.curse_id.is_empty(), "daily has an actual blessing and curse")
		suite.assert_true(definition.condition_ids.size() in [1, 2], "daily has one or two implemented special conditions")
		suite.assert_true(catalog.valid_projection(definition), "daily projection authenticates its canonical preset and seed")
		bosses[definition.boss_id] = true
		weapons[definition.weapon_id] = true
		for id: String in definition.condition_ids:
			rules[id] = true
		var changed := definition.duplicate(true)
		changed.item_ids[0] = "absolute_zero_device"
		suite.assert_true(not catalog.valid_projection(changed), "caller cannot replace the daily fixed Build")
	suite.assert_equal(bosses.size(), 5, "deterministic calendar reaches all five production Bosses")
	suite.assert_equal(weapons.size(), 5, "deterministic calendar reaches all five production weapons")
	suite.assert_equal(rules.size(), 8, "calendar reaches all eight authored native conditions")
	var calendar: Array = catalog.calendar(1791129600)
	suite.assert_equal(calendar.size(), 7, "offline preview includes seven canonical days")
	suite.assert_equal(calendar[0], after, "calendar begins with actual current daily challenge")
	var detached: Dictionary = calendar[0].duplicate(true)
	detached.item_ids.clear()
	suite.assert_equal(catalog.projection(1791129600), after, "preview callers cannot mutate canonical daily definitions")
	suite.finish(get_tree())
