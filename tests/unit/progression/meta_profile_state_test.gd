extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Fixtures := preload("res://tests/support/p16_profile_fixtures.gd")
const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const State := preload("res://scripts/progression/meta_profile_state.gd")


class IncompleteCatalog:
	extends RefCounted
	func fingerprint() -> String:
		return "a".repeat(64)


func _ready() -> void:
	var suite = Suite.new()
	var catalog = Catalog.new()
	suite.assert_true(catalog.configure(Fixtures.meta_entries()).ok, "Meta content configures")
	var state = State.new()
	suite.assert_true(state.configure(catalog), "fresh profile configures")
	var initial: Dictionary = state.snapshot()
	suite.assert_true(not state.configure(IncompleteCatalog.new()), "incomplete catalog protocol refuses without script failure")
	suite.assert_equal(state.snapshot(), initial, "failed configuration preserves the prior profile")
	suite.assert_equal(initial.unlocked_characters, ["wanderer"], "fresh production character is Wanderer")
	suite.assert_equal(initial.unlocked_weapons, ["bow", "sword"], "fresh production weapons are Sword and Bow")
	initial.chronos_shards = 5
	suite.assert_true(state.restore_snapshot(initial), "fixture earned shards restore")
	var before: Dictionary = state.snapshot()
	for prefix: String in ["onboarding-progress:", "onboarding-watermark:"]:
		suite.assert_equal(state.prepare_command({"command_id": prefix + "forged", "kind": "meta_unlock", "node_id": "W-01"}, before.revision).code, &"COMMAND_INVALID", "public purchases cannot create trusted tutorial markers")
		suite.assert_equal(state.snapshot(), before, "reserved tutorial marker refusal preserves the full profile")
	var command := {"command_id": "buy-w01", "kind": "meta_unlock", "node_id": "W-01"}
	var prepared: Dictionary = state.prepare_command(command, before.revision)
	suite.assert_true(prepared.ok, "affordable authored unlock prepares")
	suite.assert_equal(state.snapshot(), before, "prepare never spends currency")
	var tampered: Dictionary = prepared.context.ticket.duplicate(true)
	tampered.candidate_digest = "0".repeat(64)
	suite.assert_true(not state.commit_candidate(tampered).ok, "modified tickets cannot commit")
	var other = State.new()
	suite.assert_true(other.configure(catalog, before), "second authority configures")
	suite.assert_true(not other.commit_candidate(prepared.context.ticket).ok, "tickets belong to their actual authority")
	suite.assert_true(state.commit_candidate(prepared.context.ticket).ok, "prepared candidate commits once")
	var after: Dictionary = state.snapshot()
	suite.assert_equal(after.chronos_shards, 0, "authored shard cost spends exactly once")
	suite.assert_equal(after.unlocked_nodes, ["W-01"], "unlock is a durable fact")
	suite.assert_equal(after.revision, before.revision + 1, "revision advances only on commit")
	suite.assert_true(not state.commit_candidate(prepared.context.ticket).ok, "duplicate candidate cannot spend twice")
	suite.assert_true(not state.prepare_command(command, after.revision).ok, "duplicate command refuses with the current revision")
	suite.assert_true(not state.prepare_command({"command_id": "other", "kind": "meta_unlock", "node_id": "W-02"}, before.revision).ok, "stale command refuses")
	suite.assert_true(not state.prepare_command({"command_id": "poor", "kind": "meta_unlock", "node_id": "W-02"}, after.revision).ok, "insufficient currency refuses")
	for mutation: String in ["negative", "bool", "fraction", "extra", "unknown_node", "prerequisite", "proficiency", "forge", "affinity", "unknown_record", "receipt", "duplicate"]:
		var bad := after.duplicate(true)
		match mutation:
			"negative": bad.existential_imprints = -1
			"bool": bad.chronos_shards = true
			"fraction": bad.revision = 0.5
			"extra": bad.minted_currency = 500
			"unknown_node": bad.unlocked_nodes = ["F-09"]
			"prerequisite": bad.unlocked_nodes = ["W-03"]
			"proficiency": bad.weapon_proficiency.sword = -1
			"forge": bad.forge_state.sword.level = 6
			"affinity": bad.npc_affinity.vera = 101
			"unknown_record": bad.narrative_state.environment_records = ["E99-9"]
			"receipt": bad.active_launch_receipt = {"sequence": 99}
			"duplicate": bad.unlocked_nodes = ["W-01", "W-01"]
		suite.assert_true(not state.can_restore_snapshot(bad), "malformed %s fails preflight" % mutation)
		suite.assert_true(not state.restore_snapshot(bad), "malformed %s restore refuses" % mutation)
		suite.assert_equal(state.snapshot(), after, "refused restore preserves complete profile")
	var detached: Dictionary = state.snapshot()
	detached.unlocked_nodes.clear()
	suite.assert_equal(state.snapshot(), after, "profile snapshot is not a writable state reference")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(after))
	suite.assert_true(other.restore_snapshot(parsed), "actual JSON profile restores")
	suite.assert_equal(other.snapshot(), after, "JSON restoration preserves the full semantic state")
	suite.assert_true(not other.prepare_command(command, after.revision).ok, "command deduplication persists across JSON restore")
	suite.finish(get_tree())
