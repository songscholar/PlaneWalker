extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
var suite: RefCounted


func _ready() -> void:
	suite = Suite.new()
	var implementation := load("res://scripts/progression/weapon_proficiency_runtime.gd") as Script
	suite.assert_true(implementation != null, "authoritative WeaponProficiencyRuntime exists")
	if implementation != null:
		_test_thresholds_and_receipts(implementation)
		_test_bounded_history(implementation)
		_test_malformed_state(implementation)
	suite.finish(get_tree())


func _test_thresholds_and_receipts(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure(Fixtures.forge_entries(), catalog).ok, "authoritative proficiency thresholds configure")
	var state: Dictionary = runtime.snapshot()
	for weapon_id: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		for pair: Array in [[0, 1], [99, 1], [100, 2], [299, 2], [300, 3], [699, 3], [700, 4], [1499, 4], [1500, 5]]:
			state.experience[weapon_id] = pair[0]
			suite.assert_true(runtime.restore_snapshot(state), "valid migrated experience restores")
			var view: Dictionary = runtime.project(weapon_id)
			suite.assert_equal(view.level, pair[1], "exact proficiency threshold")
			suite.assert_equal(view.attack_bonus, 0.0, "proficiency never grants combat multiplier")
	state.experience.sword = 99
	suite.assert_true(runtime.restore_snapshot(state), "threshold transition baseline restores")
	var before: Dictionary = runtime.snapshot()
	var receipt := _receipt(1, 1)
	var result: Dictionary = runtime.prepare_observation(receipt, before.revision)
	suite.assert_true(result.ok, "trusted native action receipt prepares one experience")
	if not result.ok:
		return
	suite.assert_equal(runtime.snapshot(), before, "preparation cannot mint experience")
	var ticket: Dictionary = result.context.ticket
	var candidate: Dictionary = runtime.candidate_snapshot(ticket)
	suite.assert_equal(candidate.experience.sword, 100, "one accepted action reaches threshold")
	candidate.experience.sword = 50000
	suite.assert_equal(runtime.candidate_snapshot(ticket).experience.sword, 100, "candidate snapshots are detached")
	suite.assert_true(runtime.commit_candidate(ticket).ok, "accepted durable candidate commits")
	suite.assert_equal(runtime.project("sword").level, 2, "next drill detail unlocks")
	suite.assert_true(not runtime.commit_candidate(ticket).ok, "ticket cannot commit twice")
	suite.assert_true(not runtime.prepare_observation(receipt, runtime.snapshot().revision).ok, "old action cannot farm experience")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(runtime.snapshot()))
	var restored: RefCounted = implementation.new()
	suite.assert_true(restored.configure(Fixtures.forge_entries(), catalog, parsed).ok, "actual JSON restores bounded observation history")
	suite.assert_equal(restored.snapshot(), runtime.snapshot(), "physical JSON preserves experience and high-water marks")
	suite.assert_true(not restored.prepare_observation(receipt, parsed.revision).ok, "dedup survives JSON restoration")
	suite.assert_true(not restored.prepare_observation(_receipt(1, 2), before.revision).ok, "stale revision refuses a new observation")
	receipt.experience = 10000
	suite.assert_true(not restored.prepare_observation(receipt, parsed.revision).ok, "caller-supplied experience amount refuses")
	receipt.erase("experience")
	receipt.action_id = "invented-action"
	suite.assert_true(not restored.prepare_observation(receipt, parsed.revision).ok, "unknown action refuses")
	var other: RefCounted = implementation.new()
	suite.assert_true(other.configure(Fixtures.forge_entries(), catalog).ok, "other proficiency authority configures")
	var before_discard: Dictionary = restored.snapshot()
	result = restored.prepare_observation(_receipt(1, 2), restored.snapshot().revision)
	suite.assert_true(result.ok, "next ordered action prepares")
	if result.ok:
		suite.assert_true(not other.commit_candidate(result.context.ticket).ok, "tickets cannot cross authorities")
		var altered: Dictionary = result.context.ticket.duplicate(true)
		altered.candidate_digest = "0".repeat(64)
		suite.assert_true(not restored.commit_candidate(altered).ok, "forged candidate ticket refuses")
		suite.assert_true(restored.discard_candidate(result.context.ticket), "unpersisted candidate can be discarded")
		suite.assert_equal(restored.snapshot(), before_discard, "discard preserves committed state")


func _test_bounded_history(implementation: Script) -> void:
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure(Fixtures.forge_entries(), Fixtures.catalog()).ok, "long-play proficiency configures")
	var initial_size: int = JSON.stringify(runtime.snapshot()).length()
	for action_sequence: int in range(1, 4201):
		var result: Dictionary = runtime.prepare_observation(_receipt(1, action_sequence), runtime.snapshot().revision)
		if not result.ok:
			suite.assert_true(false, "more than 4096 real observations remain supported")
			break
		suite.assert_true(runtime.commit_candidate(result.context.ticket).ok, "ordered observation commits")
	suite.assert_equal(runtime.snapshot().experience.sword, 4200, "all observed actions contribute without permanent per-action markers")
	suite.assert_true(JSON.stringify(runtime.snapshot()).length() - initial_size < 32, "history remains fixed-size across thousands of actions")
	var result: Dictionary = runtime.prepare_observation(_receipt(2, 1), runtime.snapshot().revision)
	suite.assert_true(result.ok, "fresh trusted session starts a new high-water sequence")
	if result.ok:
		suite.assert_true(runtime.commit_candidate(result.context.ticket).ok, "new session candidate commits")
	suite.assert_true(not runtime.prepare_observation(_receipt(1, 5000), runtime.snapshot().revision).ok, "retired session cannot mint unseen old actions")
	var receipt := _receipt(1, 1)
	receipt.context_id = "normal_run"
	result = runtime.prepare_observation(receipt, runtime.snapshot().revision)
	suite.assert_true(result.ok, "native run and training counters are independent")
	if result.ok:
		suite.assert_true(runtime.commit_candidate(result.context.ticket).ok, "native context candidate commits")


func _test_malformed_state(implementation: Script) -> void:
	var catalog := Fixtures.catalog()
	var runtime: RefCounted = implementation.new()
	suite.assert_true(runtime.configure(Fixtures.forge_entries(), catalog).ok, "malformed-state runtime configures")
	var before: Dictionary = runtime.snapshot()
	for mutation: String in ["bool", "negative", "unknown", "context", "fraction", "highwater", "extra"]:
		var bad := before.duplicate(true)
		match mutation:
			"bool": bad.experience.sword = true
			"negative": bad.experience.bow = -1
			"unknown": bad.experience.dagger = 100
			"context": bad.high_water.sword.online = {"session_sequence": 1, "action_sequence": 1}
			"fraction": bad.high_water.sword.training_drill.action_sequence = 1.5
			"highwater": bad.high_water.sword.training_drill.action_sequence = 1
			"extra": bad.secret_damage = 5
		suite.assert_true(not runtime.restore_snapshot(bad), "malformed proficiency state refuses: " + mutation)
		suite.assert_equal(runtime.snapshot(), before, "failed restore is atomic")
	var maximum := before.duplicate(true)
	maximum.experience.sword = 2147483647
	suite.assert_true(runtime.restore_snapshot(maximum), "maximum bounded experience restores")
	suite.assert_true(not runtime.prepare_observation(_receipt(1, 1), runtime.snapshot().revision).ok, "experience overflow refuses")
	var definitions := Fixtures.forge_entries()
	definitions[0].proficiency_thresholds = [0, 5, 4, 3, 2]
	suite.assert_true(not runtime.configure(definitions, catalog).ok, "malformed thresholds refuse")
	suite.assert_equal(runtime.project("sword"), {}, "invalid configuration clears old content")


func _receipt(session_sequence: int, action_sequence: int) -> Dictionary:
	return {"session_sequence": session_sequence, "action_sequence": action_sequence, "weapon_id": "sword", "action_id": "weapon_primary", "context_id": "training_drill"}
