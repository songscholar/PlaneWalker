extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunStateScript := preload("res://scripts/application/run_state.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var state = RunStateScript.new()
	state.reset_domain(_config(123), "run-one")
	suite.assert_equal(state.run_id, "run-one", "reset stores run id")
	suite.assert_equal(state.run_seed, 123, "reset stores run seed")
	suite.assert_equal(state.current_floor, 1, "reset starts on floor one")
	suite.assert_equal(state.current_room, 0, "reset starts before the first room")
	suite.assert_equal(state.room_total, 5, "reset uses five M1 rooms")
	suite.assert_equal(state.resources, {}, "reset initializes run resources")
	suite.assert_equal(state.stats, {"kills": 0}, "reset initializes run statistics")
	suite.assert_equal(state.events, [], "reset initializes run events")

	state.build_state.record_item({"id": "frozen_burst", "archetype": "freeze_burst"})
	state.open_offer = {"offer_id": "offer-one", "options": [{"option_id": "frozen_burst"}]}
	state.result = {"result": "old"}
	state.suspended = true
	state.mark_offer_consumed("offer-one")
	var phase_before_reset: int = state.phase
	state.resources = {"chronos_shards": 3}
	state.stats = {"kills": 4}
	state.events = [{"id": "old"}]
	state.reset_domain(_config(456), "run-two")
	suite.assert_equal(state.run_id, "run-two", "reset replaces run id")
	suite.assert_equal(state.run_seed, 456, "reset replaces run seed")
	suite.assert_true(state.build_state.selected_ids().is_empty(), "reset clears build state")
	suite.assert_true(state.open_offer.is_empty(), "reset clears open offer")
	suite.assert_true(state.result.is_empty(), "reset clears result")
	suite.assert_true(not state.suspended, "reset clears suspended overlay")
	suite.assert_true(not state.has_consumed_offer("offer-one"), "reset clears consumed offers")
	suite.assert_equal(state.phase, phase_before_reset, "domain reset does not mutate phase")
	suite.assert_equal(state.resources, {}, "domain reset clears resources")
	suite.assert_equal(state.stats, {"kills": 0}, "domain reset clears statistics")
	suite.assert_equal(state.events, [], "domain reset clears events")

	suite.assert_equal(state.advance_revision(), 1, "revision advances once")
	suite.assert_equal(state.advance_revision(), 2, "revision advances monotonically")
	suite.assert_true(state.mark_offer_consumed("offer-two"), "new offer is consumed")
	suite.assert_true(not state.mark_offer_consumed("offer-two"), "consumed offer is idempotent")

	state.phase = RunPhaseScript.Value.COMBAT_ACTIVE
	state.suspended = true
	suite.assert_equal(state.phase, RunPhaseScript.Value.COMBAT_ACTIVE, "suspended state does not replace phase")
	suite.assert_true(not state.is_terminal(), "combat state is not terminal")
	state.phase = RunPhaseScript.Value.VICTORY
	suite.assert_true(state.is_terminal(), "victory state is terminal")
	state.phase = RunPhaseScript.Value.DEFEAT
	suite.assert_true(state.is_terminal(), "defeat state is terminal")

	state.phase = RunPhaseScript.Value.COMBAT_ACTIVE
	state.open_offer = {"offer_id": "copy-test", "options": [{"option_id": "original"}]}
	state.build_state.record_item({"id": "rewind_echo", "archetype": "rewind_echo"})
	state.resources = {"chronos_shards": 2}
	state.stats = {"kills": 1}
	state.events = [{"id": "room-cleared"}]
	var snapshot: Dictionary = state.snapshot()
	snapshot["open_offer"]["options"][0]["option_id"] = "changed"
	snapshot["build"]["items"].append("changed")
	snapshot["resources"]["chronos_shards"] = 999
	snapshot["stats"]["kills"] = 999
	snapshot["events"][0]["id"] = "changed"
	suite.assert_equal(state.open_offer["options"][0]["option_id"], "original", "snapshot offer is isolated")
	suite.assert_true(not state.build_state.items.has("changed"), "snapshot build is isolated")
	suite.assert_equal(state.resources["chronos_shards"], 2, "snapshot resources are isolated")
	suite.assert_equal(state.stats["kills"], 1, "snapshot statistics are isolated")
	suite.assert_equal(state.events[0]["id"], "room-cleared", "snapshot events are isolated")
	suite.finish(get_tree())


func _config(seed: int) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": seed,
	}
