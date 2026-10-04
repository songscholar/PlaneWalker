extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/narrative/ending_evaluator.gd") as Script
	suite.assert_true(implementation != null, "content-driven ending evaluator exists")
	if implementation != null:
		_test_endings(implementation)
		_test_refusals(implementation)
	suite.finish(get_tree())


func _test_endings(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime: RefCounted = implementation.new()
	var configured: Dictionary = runtime.configure(_entries(), catalog)
	suite.assert_true(configured.ok, "all authoritative narrative content configures: " + str(configured))
	if not configured.ok:
		return
	var profile := _victory_profile(catalog)
	var facts := _facts()
	var view: Dictionary = runtime.evaluate(profile, facts)
	suite.assert_true(view.ok, "matching canonical terminal facts evaluate: " + str(view))
	if not view.ok:
		return
	suite.assert_equal(_eligible(view), ["shattered_freedom"], "victory has always-available authored fallback")
	suite.assert_equal(view.context.endings.size(), 5, "all choices remain visible with missing requirements")
	var baseline := profile.duplicate(true)
	profile.npc_affinity.elara = 80
	profile.narrative_state.heart_fragments = ["floor_plane_forge", "floor_ruins_of_remnant", "floor_throne_of_void", "floor_time_rift", "floor_void_forest"]
	suite.assert_true(_eligible(runtime.evaluate(profile, facts)).has("return_of_order"), "exact order prerequisites unlock")
	profile.npc_affinity.elara = 79
	suite.assert_true(not _eligible(runtime.evaluate(profile, facts)).has("return_of_order"), "order affinity boundary refuses")
	profile.npc_affinity.elara = 80
	for index: int in range(1, 6):
		profile.narrative_state.consumed_sources.append("dialogue:sibyl_depth_" + str(index))
	suite.assert_true(not _eligible(runtime.evaluate(profile, facts)).has("return_of_order"), "complete Sibyl depth excludes order")
	profile = baseline.duplicate(true)
	profile.npc_affinity.sibyl = 80
	profile.narrative_state.nemesis_choices = ["spare", "spare", "spare", "spare", "spare"]
	profile.narrative_state.flags = ["void_understood"]
	suite.assert_true(_eligible(runtime.evaluate(profile, facts)).has("embrace_of_void"), "five spared encounters plus understanding unlock void")
	profile.narrative_state.nemesis_choices[4] = "attack"
	suite.assert_true(not _eligible(runtime.evaluate(profile, facts)).has("embrace_of_void"), "one attack excludes void ending")
	profile = baseline.duplicate(true)
	profile.npc_affinity.elara = 60
	profile.npc_affinity.sibyl = 60
	profile.narrative_state.heart_fragments = ["floor_plane_forge", "floor_ruins_of_remnant", "floor_time_rift"]
	profile.narrative_state.flags = ["balance_choice_elara_forest", "balance_choice_nemesis_forge", "balance_choice_sibyl_rift"]
	profile.narrative_state.balance_choice_sources = ["dialogue:elara_floor_2", "dialogue:nemesis_floor_4", "dialogue:sibyl_floor_3"]
	profile.narrative_state.consumed_sources = profile.narrative_state.balance_choice_sources.duplicate()
	suite.assert_true(_eligible(runtime.evaluate(profile, facts)).has("balance_of_ashes"), "three distinct authored balance sources unlock coexist")
	profile.narrative_state.balance_choice_sources.pop_back()
	suite.assert_true(not _eligible(runtime.evaluate(profile, facts)).has("balance_of_ashes"), "two key choices cannot stand in for three")
	profile = _complete_profile(catalog)
	suite.assert_true(_eligible(runtime.evaluate(profile, facts)).has("echo_of_primordial"), "complete collections and eight affinities unlock hidden ending")
	for npc_id: String in profile.npc_affinity:
		profile.npc_affinity[npc_id] = 79
		suite.assert_true(not _eligible(runtime.evaluate(profile, facts)).has("echo_of_primordial"), "each NPC must independently reach eighty: " + npc_id)
		profile.npc_affinity[npc_id] = 80
	for field: String in ["artifacts", "environment_records"]:
		var saved: Array = profile.narrative_state[field].duplicate()
		profile.narrative_state[field].pop_back()
		suite.assert_true(not _eligible(runtime.evaluate(profile, facts)).has("echo_of_primordial"), "every authored collection item matters")
		profile.narrative_state[field] = saved
	for storyline: String in profile.narrative_state.hidden_steps:
		profile.narrative_state.hidden_steps[storyline] = 4
		suite.assert_true(not _eligible(runtime.evaluate(profile, facts)).has("echo_of_primordial"), "each hidden line requires all five steps")
		profile.narrative_state.hidden_steps[storyline] = 5
	profile.narrative_state.vera_conversations = 4
	suite.assert_true(not _eligible(runtime.evaluate(profile, facts)).has("echo_of_primordial"), "four Vera conversations exclude hidden ending")
	profile.narrative_state.vera_conversations = 5
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(profile))
	suite.assert_equal(runtime.evaluate(parsed, JSON.parse_string(JSON.stringify(facts))), runtime.evaluate(profile, facts), "physical JSON preserves ending predicates")
	var before := profile.duplicate(true)
	view = runtime.evaluate(profile, facts)
	view.context.endings.clear()
	suite.assert_equal(profile, before, "evaluation never mutates durable profile")
	suite.assert_equal(runtime.evaluate(profile, facts).context.endings.size(), 5, "ending views are detached")


func _test_refusals(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure(_entries(), catalog).ok, "refusal evaluator configures")
	var profile := _complete_profile(catalog)
	for mutation: String in ["empty", "old", "run", "death", "boss", "extra", "fraction"]:
		var facts := _facts()
		match mutation:
			"empty": facts.clear()
			"old": facts.launch_sequence = 2
			"run": facts.run_id = "other-run"
			"death": facts.terminal_reason = "death"
			"boss": facts.boss_ids = ["ruin_king"]
			"extra": facts.unlock_all = true
			"fraction": facts.launch_sequence = 1.5
		var result: Dictionary = runtime.evaluate(profile, facts)
		suite.assert_true(not result.ok or _eligible(result).is_empty(), "noncanonical or unavailable victory cannot expose endings: " + mutation)
	suite.assert_true(not runtime.evaluate({}, _facts()).ok, "empty profile refuses")
	var malformed := profile.duplicate(true)
	malformed.narrative_state.flags.append("invented-flag")
	suite.assert_true(not runtime.evaluate(malformed, _facts()).ok, "unowned flag references refuse")
	var launched := profile.duplicate(true)
	launched.launch_sequence = 2
	launched.active_launch_receipt = {"schema_id": "meta_launch_receipt_v1", "sequence": 2, "run_id": "next-run", "difficulty": "normal", "seed": 10, "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["rewind", "stop"], "projection_digest": "b".repeat(64)}
	suite.assert_true(_eligible(runtime.evaluate(launched, _facts())).is_empty(), "prior victory cannot be reopened during a newer active run")
	var entries := _entries()
	entries[0].dialogue_nodes[0].choices[0].secret_damage = 100
	suite.assert_true(not runtime.configure(entries, catalog).ok, "unknown nested dialogue effect refuses")
	suite.assert_true(not runtime.evaluate(profile, _facts()).ok, "failed content configure clears evaluator")


func _victory_profile(catalog: RefCounted) -> Dictionary:
	var profile := Fixtures.profile(catalog)
	profile.launch_sequence = 1
	profile.last_settlement_receipt = {"schema_id": "meta_settlement_receipt_v1", "sequence": 1, "run_id": "ending-run", "terminal_reason": "victory", "shards": 0, "imprints": 0, "soul_reserve": 0, "digest": "a".repeat(64)}
	return profile


func _complete_profile(catalog: RefCounted) -> Dictionary:
	var profile := _victory_profile(catalog)
	for id: String in profile.npc_affinity:
		profile.npc_affinity[id] = 80
	for row: Dictionary in _entries():
		if row.definition_kind == "artifact":
			profile.narrative_state.artifacts.append(row.artifact_id)
		elif row.definition_kind == "environment_record":
			profile.narrative_state.environment_records.append(row.record_id)
	for id: String in profile.narrative_state.hidden_steps:
		profile.narrative_state.hidden_steps[id] = 5
	profile.narrative_state.artifacts.sort()
	profile.narrative_state.environment_records.sort()
	profile.narrative_state.vera_conversations = 5
	return profile


func _facts() -> Dictionary:
	return {"run_id": "ending-run", "launch_sequence": 1, "terminal_reason": "victory", "boss_ids": ["void_throne"]}


func _entries() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/content_packs/base/content/narrative_definitions.json"))


func _eligible(result: Dictionary) -> Array:
	var ids: Array = []
	if result.ok:
		for ending: Dictionary in result.context.endings:
			if ending.eligible:
				ids.append(ending.ending_id)
	return ids
