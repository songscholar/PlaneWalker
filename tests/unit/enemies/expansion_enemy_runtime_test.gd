extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Enemy := preload("res://scripts/enemies/expansion/expansion_enemy_definition.gd")
const Runtime := preload("res://scripts/enemies/expansion/expansion_enemy_runtime.gd")
const Fixtures := preload("res://tests/support/p15_action_fixtures.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Catalog := preload("res://scripts/dungeon/launch_encounter_catalog.gd")
const Snapshot := preload("res://scripts/content/content_snapshot_provider.gd")
const Facade := preload("res://scripts/application/run_runtime_facade.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var source: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/temporal_frontiers/content/enemies.json"))
	for row: Dictionary in source:
		var parser := Enemy.new()
		suite.assert_true(parser.configure(row).ok, "five authored Expansion patterns parse: " + str(row.id))
		var identity := Fixtures.identity()
		identity.seed = 42
		var live := Runtime.new()
		var cold := Runtime.new()
		suite.assert_true(live.configure(parser.runtime_projection(), identity).ok and cold.configure(parser.runtime_projection(), identity).ok, "trusted Expansion domain binds real identity")
		suite.assert_true(live.request_action(row.actions[0].id, Fixtures.context()).ok, "authored Expansion warning commits")
		suite.assert_true(live.add_control_source("expansion_stop", "stop", 3, 1.0), "Stop participates in every Expansion warning")
		for frame: int in range(1, 4):
			var result := live.advance_frame(frame, Fixtures.context(frame), false)
			suite.assert_true(result.ok and result.action_paused and result.hit_facts.is_empty(), "Stop retains full Expansion warning")
		suite.assert_true(cold.restore_snapshot(live.snapshot()), "Expansion cold state restores after control pause")
		var forged := live.snapshot()
		forged.mechanism_state.foreign_mechanism = true
		suite.assert_true(not cold.restore_snapshot(forged) and cold.snapshot() == live.snapshot(), "foreign Expansion mechanism refuses without mutation")
		forged = live.snapshot()
		forged.mechanism_state.hp_after = float(row.max_hp) + 1.0
		suite.assert_true(not cold.restore_snapshot(forged), "forged Expansion HP refuses")
		var hits: Array = []
		for frame: int in range(4, int(row.actions[0].warning_frames) + int(row.actions[0].active_frames) + 4):
			var result := live.advance_frame(frame, Fixtures.context(frame), false)
			suite.assert_equal(cold.advance_frame(frame, Fixtures.context(frame), false), result, "cold Expansion retains exact warning, generation and hits")
			hits.append_array(result.hit_facts)
		suite.assert_equal(hits.size(), row.actions[0].hit_schedule.size(), "Expansion executes each authored hit exactly once")
		if row.id == "prism_seer":
			suite.assert_true(hits.all(func(hit: Dictionary): return hit.geometry.size() == 1), "Prism sequence launches one independently locked lane at each step")
			for index: int in range(3):
				suite.assert_equal(hits[index].attack_generation, index + 7, "Prism sequence retains three independent lane generations")
		var fact := {"fact_id": "accepted_weapon", "runtime_frame": live.snapshot().runtime_frame, "target_source_id": identity.hostile_source_id, "amount": 12.0, "hp_after": float(row.max_hp) - 12.0}
		suite.assert_true(live.accept_damage_fact(fact).ok and not live.accept_damage_fact(fact).ok, "authenticated Expansion HP commits exactly once")
		suite.assert_true(live.cancel(&"room_exit").ok and cold.cancel(&"room_exit").ok, "Expansion lifecycle disposes action and control")
	var base := Registry.new()
	var base_report = base.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not base_report.has_blocking_errors(), "Base continues to load alone")
	var base_before := Snapshot.snapshot(base)
	var base_catalog := Catalog.new()
	suite.assert_true(base_catalog.configure(base).ok and not base_catalog.supports_expansion_enemies(), "Base keeps exactly its Launch catalog")
	var selected := Registry.new()
	var report = selected.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}, {"path": "res://data/content_packs/temporal_frontiers/pack.json", "required": true}], "0.4.0-dev", &"EXPANSION")
	suite.assert_true(not report.has_blocking_errors(), "complete optional Expansion package validates: " + str(report.blocking_errors))
	var catalog := Catalog.new()
	var configured := catalog.configure(selected)
	suite.assert_true(configured.ok and catalog.supports_expansion_enemies(), "optional assembly binds five native Expansion recipes: " + str(configured))
	if configured.ok:
		for index: int in range(5):
			var profile_id: String = "encounter_profile_" + ["ruins", "forest", "rift", "forge", "throne"][index] + "_adapter_v1"
			for revision: int in [1, 2]:
				suite.assert_equal(catalog.resolve_for_revision(profile_id, 42, "combat_1", "combat", "room_combat_open_field", revision), base_catalog.resolve_for_revision(profile_id, 42, "combat_1", "combat", "room_combat_open_field", revision), "optional package preserves historical selection revisions")
			var found := false
			for seed: int in range(1, 64):
				var recipe := catalog.resolve_for_revision(profile_id, seed, "combat_1", "combat", "room_combat_open_field", 3)
				found = found or not recipe.is_empty() and recipe.waves[0].spawns[0].enemy_id == Enemy.IDS[index]
			suite.assert_true(found, "new Expansion pool actually selects floor species " + Enemy.IDS[index])
	suite.assert_equal(Snapshot.snapshot(base), base_before, "optional assembly cannot mutate Base fingerprint")
	suite.assert_true(base_catalog.resolve_for_revision("encounter_profile_ruins_adapter_v1", 42, "combat_1", "combat", "room_combat_open_field", 3).is_empty(), "missing pack refuses revision-3 substitution")
	suite.finish(get_tree())
