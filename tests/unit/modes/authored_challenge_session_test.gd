extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Catalog := preload("res://scripts/modes/authored_challenge_catalog.gd")
const SOURCE := "res://scripts/modes/authored_challenge_session.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	if not ResourceLoader.exists(SOURCE):
		suite.assert_true(false, "authored session must validate native stage receipts objective metrics bounded history and continued practice")
		suite.finish(get_tree())
		return
	var rules = load(SOURCE)
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var catalog := Catalog.new()
	suite.assert_true(catalog.configure(registry), "actual authored catalog configures session authority")
	var empty: Dictionary = rules.empty(catalog.fingerprint())
	suite.assert_true(rules.valid(empty, catalog, "owner"), "empty independent authored history is canonical")
	for definition: Dictionary in catalog.entries():
		var stages := _stages(definition, rules)
		var elapsed := 300
		var damage := 0
		suite.assert_true(rules.objective_passed(definition, stages, elapsed, damage), "authored objective accepts actual in-bound native stage metrics: " + definition.id)
		match definition.objective.kind:
			"total_time":
				elapsed = int(definition.objective.limit)
				suite.assert_true(rules.objective_passed(definition, stages, elapsed, damage), "total frame objective includes its exact boundary")
				elapsed += 1
			"damage_events":
				damage = int(definition.objective.limit)
				suite.assert_true(rules.objective_passed(definition, stages, elapsed, damage), "damage objective includes its exact boundary")
				damage += 1
			"stage_time":
				stages[1].frames = int(definition.objective.limit)
				suite.assert_true(rules.objective_passed(definition, stages, elapsed, damage), "per-stage frame objective includes its exact boundary")
				stages[1].frames += 1
			"minimum_hp":
				stages[1].remaining_hp_milli = int(definition.objective.limit)
				suite.assert_true(rules.objective_passed(definition, stages, elapsed, damage), "HP objective includes its exact boundary")
				stages[1].remaining_hp_milli -= 1
			"no_damage": damage = 1
		suite.assert_true(not rules.objective_passed(definition, stages, elapsed, damage), "each distinct objective rejects its first invalid value: " + definition.id)
	var definition: Dictionary = catalog.entries()[0]
	var result := _result(definition, rules, 1)
	var state := empty.duplicate(true)
	state.sequence = 1
	state.history[definition.id] = [result]
	state.best[definition.id] = result.duplicate(true)
	suite.assert_true(rules.valid(state, catalog, "owner"), "three ordered authenticated receipts produce one retained fresh victory")
	for field: String in ["boss_id", "death_receipt", "run_id", "native_digest", "stage_index"]:
		var changed: Dictionary = state.duplicate(true)
		changed.history[definition.id][0].stages[0][field] = -1 if field == "stage_index" else "invented"
		suite.assert_true(not rules.valid(changed, catalog, "owner"), "forged native stage receipt refuses: " + field)
	var continued: Dictionary = _result(definition, rules, 2)
	continued.continued = true
	continued.elapsed_frames = 3
	for stage: Dictionary in continued.stages:
		stage.frames = 1
	state.sequence = 2
	state.history[definition.id].append(continued)
	suite.assert_true(rules.valid(state, catalog, "owner"), "practice victory remains durable without replacing slower fresh best")
	var wrong_best := state.duplicate(true)
	wrong_best.best[definition.id] = continued
	suite.assert_true(not rules.valid(wrong_best, catalog, "owner"), "continued victory cannot publish as a fresh best")
	state.history[definition.id] = [continued]
	suite.assert_true(rules.valid(state, catalog, "owner"), "retained lifetime fresh best survives bounded rolling history pruning")
	var excessive := state.duplicate(true)
	for sequence: int in range(3, 13):
		excessive.history[definition.id].append(_result(definition, rules, sequence))
	excessive.sequence = 12
	suite.assert_true(not rules.valid(excessive, catalog, "owner"), "history cannot grow beyond ten attempts per authored set")
	var payload: Dictionary = JSON.parse_string(JSON.stringify(state))
	suite.assert_true(rules.valid(payload, catalog, "owner"), "physical JSON numbers remain valid domain values")
	suite.assert_equal(typeof(rules.normalized(payload).sequence), TYPE_INT, "physical restore normalizes sequence to an integer")
	suite.finish(get_tree())


func _stages(definition: Dictionary, rules: Script, sequence: int = 1) -> Array:
	var result: Array = []
	var run: String = rules.run_id("owner", definition.id, sequence)
	for index: int in range(3):
		var stage_run: String = rules.stage_run_id(run, index)
		var source := "authored-" + stage_run.sha256_text().substr(0, 40)
		result.append({"stage_index": index, "boss_id": definition.boss_ids[index], "run_id": stage_run, "hostile_source_id": source, "death_receipt": "hostile_defeat:" + (stage_run + "|" + source).sha256_text().substr(0, 40), "frames": 100, "damage_events": 0, "remaining_hp_milli": 100000, "native_digest": "a".repeat(64)})
	return result


func _result(definition: Dictionary, rules: Script, sequence: int) -> Dictionary:
	return {"sequence": sequence, "set_id": definition.id, "run_id": rules.run_id("owner", definition.id, sequence), "status": "VICTORY", "elapsed_frames": 300, "damage_events": 0, "remaining_hp_milli": 100000, "continued": false, "stages": _stages(definition, rules, sequence), "terminal_digest": "a".repeat(64)}
