extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Summons := preload("res://scripts/enemies/launch/launch_summon_authority.gd")
const Spatial := preload("res://scripts/enemies/launch/enemy_spatial_runtime.gd")
const CONTENT := "res://data/content_packs/base/content/"


func _ready() -> void:
	var suite := Suite.new()
	var summon_source: PackedByteArray = FileAccess.get_file_as_bytes(CONTENT + "summons.json")
	var enemy_source: PackedByteArray = FileAccess.get_file_as_bytes(CONTENT + "enemies.json")
	var boss_source: PackedByteArray = FileAccess.get_file_as_bytes(CONTENT + "bosses.json")
	var authority := Summons.new()
	var spatial := Spatial.new()
	suite.assert_true(authority.configure("run-catalog-cache", 7) and spatial.configure_catalog(), "authentic catalogs pass existing complete parsers")
	var summon_cache: Variant = _cache_entries("launch_summon_authority")
	var spatial_cache: Variant = _cache_entries("enemy_spatial_runtime")
	suite.assert_true(summon_cache is Array and summon_cache.size() > 0 and summon_cache.size() <= 4, "summon catalog retains bounded successful exact-source cache")
	suite.assert_true(spatial_cache is Array and spatial_cache.size() > 0 and spatial_cache.size() <= 4, "spatial catalog retains bounded successful exact-source cache")
	if not summon_cache is Array or not spatial_cache is Array:
		suite.finish(get_tree())
		return
	for cache: Array in [summon_cache, spatial_cache]:
		for entry: Dictionary in cache:
			suite.assert_true(entry.source is PackedByteArray and entry.state is PackedByteArray, "cached source and projection use detached native typed bytes")
	var summon_state := _summon_catalog(authority)
	var spatial_state: Dictionary = spatial.get("_actions").duplicate(true)
	suite.assert_true(summon_cache.any(func(entry: Dictionary): return entry.source == var_to_bytes([summon_source, enemy_source, boss_source])), "summon key owns all three exact current raw catalogs")
	suite.assert_true(spatial_cache.any(func(entry: Dictionary): return entry.source == enemy_source), "spatial key owns exact current raw enemy catalog")
	for _repeat: int in range(8):
		var next := Summons.new()
		var next_spatial := Spatial.new()
		suite.assert_true(next.configure("another-native-run", 13) and next_spatial.configure_catalog(), "new native instances reuse validated catalogs")
		suite.assert_equal(_summon_catalog(next), summon_state, "cache restores full summon definitions and ownership policy")
		suite.assert_equal(next_spatial.get("_actions"), spatial_state, "cache restores all five spatial actions")
		next.get("_definitions").clear()
		next.get("_summon_actions").clear()
		next.get("_ordinary_parents")["shattered_sentinel"].max_hp = -1.0
		next_spatial.get("_actions").clear()
		suite.assert_true(authority.configure("run-catalog-cache", 7) and spatial.configure_catalog(), "instance mutation cannot poison shared accepted bytes")
		suite.assert_equal(_summon_catalog(authority), summon_state, "catalog source remains isolated from another instance")
		suite.assert_equal(spatial.get("_actions"), spatial_state, "spatial source remains isolated from another instance")
	var missing := Summons.new()
	suite.assert_true(not missing.configure("", 0) and not missing.configure("valid", -1), "warm catalogs cannot bypass native run/frame boundary validation")
	var pending := Summons.new()
	suite.assert_true(pending.configure("run-catalog-cache", 7), "pending fixture has authentic catalog")
	pending.set("_pending", {"ticket_id": 1})
	suite.assert_true(not pending.configure("run-catalog-cache", 7), "warm catalog cannot overwrite pending native transaction")
	for changed: PackedByteArray in [PackedByteArray(), "null".to_utf8_buffer(), "{}".to_utf8_buffer(), "[null]".to_utf8_buffer()]:
		var before_summons: int = _cache_entries("launch_summon_authority").size()
		var before_spatial: int = _cache_entries("enemy_spatial_runtime").size()
		suite.assert_true(not authority.call("_configure_catalog_sources", changed, enemy_source, boss_source), "malformed summon raw bytes miss warm cache and are refused")
		suite.assert_true(not authority.call("_configure_catalog_sources", summon_source, changed, boss_source), "malformed enemy raw bytes miss warm summon cache and are refused")
		suite.assert_true(not authority.call("_configure_catalog_sources", summon_source, enemy_source, changed), "malformed boss raw bytes miss warm summon cache and are refused")
		suite.assert_true(not spatial.call("_configure_catalog_source", changed), "malformed enemy raw bytes miss warm spatial cache and are refused")
		suite.assert_equal(_cache_entries("launch_summon_authority").size(), before_summons, "refused catalog sources never populate summon cache")
		suite.assert_equal(_cache_entries("enemy_spatial_runtime").size(), before_spatial, "refused catalog sources never populate spatial cache")
	var summons: Array = JSON.parse_string(summon_source.get_string_from_utf8())
	summons[0].lifetime_frames = true
	suite.assert_true(not authority.call("_configure_catalog_sources", JSON.stringify(summons).to_utf8_buffer(), enemy_source, boss_source), "warm exact-source key cannot hide a forged typed summon field")
	var enemies: Array = JSON.parse_string(enemy_source.get_string_from_utf8())
	enemies[0].max_hp += 1.0
	suite.assert_true(authority.call("_configure_catalog_sources", summon_source, JSON.stringify(enemies).to_utf8_buffer(), boss_source), "valid changed enemy bytes run the definition parser independently")
	suite.assert_equal(authority.get("_ordinary_parents")[enemies[0].id].max_hp, enemies[0].max_hp, "accepted raw-source edit replaces the cached enemy projection")
	enemies[0].max_hp = true
	suite.assert_true(not authority.call("_configure_catalog_sources", summon_source, JSON.stringify(enemies).to_utf8_buffer(), boss_source), "changed typed enemy bytes still execute complete definition parser")
	var invalid_spatial: Array = JSON.parse_string(enemy_source.get_string_from_utf8())
	for parent: Dictionary in invalid_spatial:
		for action: Dictionary in parent.actions + parent.elite_actions:
			if action.handler_id == "wall":
				action.warning_frames = true
	suite.assert_true(not spatial.call("_configure_catalog_source", JSON.stringify(invalid_spatial).to_utf8_buffer()), "changed spatial action bytes retain typed action validation")
	var bosses: Array = JSON.parse_string(boss_source.get_string_from_utf8())
	for parent: Dictionary in bosses:
		for action: Dictionary in parent.actions:
			if action.handler_id == "summon":
				action.warning_frames = true
	suite.assert_true(not authority.call("_configure_catalog_sources", summon_source, enemy_source, JSON.stringify(bosses).to_utf8_buffer()), "changed boss action bytes retain typed summon validation")
	# Whitespace edits decode identically but remain separate raw-source entries.
	for index: int in range(6):
		var suffix := "\n".repeat(index + 1).to_utf8_buffer()
		suite.assert_true(authority.call("_configure_catalog_sources", summon_source + suffix, enemy_source, boss_source) and spatial.call("_configure_catalog_source", enemy_source + suffix), "every changed raw catalog is independently accepted")
		suite.assert_equal(_summon_catalog(authority), summon_state, "raw-source edit preserves canonical summon semantics")
		suite.assert_equal(spatial.get("_actions"), spatial_state, "raw-source edit preserves canonical spatial semantics")
		suite.assert_true(_cache_entries("launch_summon_authority").size() <= 4 and _cache_entries("enemy_spatial_runtime").size() <= 4, "catalog cache stays bounded during exact raw-source eviction")
	var threads: Array[Thread] = []
	for _worker: int in range(5):
		var thread := Thread.new()
		threads.append(thread)
		suite.assert_equal(thread.start(func() -> bool:
			for _repeat: int in range(20):
				var worker := Summons.new()
				var worker_spatial := Spatial.new()
				if not worker.configure("thread-run", 3) or not worker_spatial.configure_catalog() or _summon_catalog(worker) != summon_state or worker_spatial.get("_actions") != spatial_state:
					return false
				worker.get("_definitions").clear()
				worker_spatial.get("_actions").clear()
				if worker.call("_configure_catalog_sources", summon_source, enemy_source, "[null]".to_utf8_buffer()) or worker_spatial.call("_configure_catalog_source", "[null]".to_utf8_buffer()):
					return false
			return true), OK, "parallel native catalog worker starts")
	for thread: Thread in threads:
		suite.assert_true(thread.wait_to_finish(), "concurrent catalog hits, instance isolation and malformed misses retain exact verdicts")
	suite.assert_true(_cache_entries("launch_summon_authority").size() <= 4 and _cache_entries("enemy_spatial_runtime").size() <= 4, "concurrent catalog cache remains bounded")
	suite.finish(get_tree())


func _summon_catalog(authority: RefCounted) -> Dictionary:
	var result := {}
	for field: String in ["_definitions", "_death_actions", "_ordinary_parents", "_summon_actions", "_summon_owner_retirement"]:
		result[field] = authority.get(field).duplicate(true)
	return result


func _cache_entries(kind: String) -> Variant:
	var source: Script = load("res://scripts/enemies/launch/%s.gd" % kind)
	return source.get("_catalog_cache")
