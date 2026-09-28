extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_legal_run_path(suite)
	_test_invalid_transitions(suite)
	_test_pause_overlay(suite)
	suite.finish(get_tree())


func _test_legal_run_path(suite) -> void:
	var orchestrator = RunOrchestratorScript.new()
	var hub_result = orchestrator.enter_hub()
	_assert_accepts_phase(suite, hub_result, orchestrator, RunPhaseScript.Value.HUB, "boot enters hub")
	var start_result = orchestrator.start_run(_config(), "run-legal")
	_assert_accepts_phase(suite, start_result, orchestrator, RunPhaseScript.Value.RUN_PREPARING, "run starts preparing")
	suite.assert_true(start_result.new_revision > hub_result.new_revision, "successful commands advance revision monotonically")
	_assert_accepts_phase(suite, orchestrator.preparation_completed(), orchestrator, RunPhaseScript.Value.ROOM_ENTERING, "preparation enters room")
	_assert_accepts_phase(suite, orchestrator.room_entered(false), orchestrator, RunPhaseScript.Value.COMBAT_ACTIVE, "normal room enters combat")
	_assert_accepts_phase(suite, orchestrator.room_cleared(), orchestrator, RunPhaseScript.Value.ROOM_RESOLVING, "combat resolves")

	var revision_after_clear: int = orchestrator.state.revision
	var duplicate_clear = orchestrator.room_cleared()
	suite.assert_equal(duplicate_clear.code, &"INVALID_PHASE", "repeated room clear is rejected")
	suite.assert_equal(orchestrator.state.revision, revision_after_clear, "repeated room clear leaves revision unchanged")

	var first_offer_id := "run-legal:room-01:item:first"
	_assert_accepts_phase(suite, orchestrator.open_selection(_offer(orchestrator.state.revision, first_offer_id)), orchestrator, RunPhaseScript.Value.SELECTION_ACTIVE, "selection opens")
	_assert_accepts_phase(suite, orchestrator.selection_resolved(), orchestrator, RunPhaseScript.Value.ROOM_TRANSITION, "selection resolves")
	suite.assert_true(orchestrator.state.has_consumed_offer(first_offer_id), "resolved selection records consumed offer")
	_assert_accepts_phase(suite, orchestrator.transition_completed(), orchestrator, RunPhaseScript.Value.ROOM_ENTERING, "transition enters next room")
	_assert_accepts_phase(suite, orchestrator.room_entered(false), orchestrator, RunPhaseScript.Value.COMBAT_ACTIVE, "next normal room enters combat")
	_assert_accepts_phase(suite, orchestrator.room_cleared(), orchestrator, RunPhaseScript.Value.ROOM_RESOLVING, "next combat resolves")
	var repeated_offer = orchestrator.open_selection(_offer(orchestrator.state.revision, first_offer_id))
	suite.assert_equal(repeated_offer.code, &"ALREADY_CONSUMED", "consumed offer cannot reopen")
	suite.assert_equal(orchestrator.state.phase, RunPhaseScript.Value.ROOM_RESOLVING, "rejected consumed offer leaves phase unchanged")
	_assert_accepts_phase(suite, orchestrator.open_selection(_offer(orchestrator.state.revision, "run-legal:room-02:item:second")), orchestrator, RunPhaseScript.Value.SELECTION_ACTIVE, "new offer opens")
	_assert_accepts_phase(suite, orchestrator.selection_resolved(), orchestrator, RunPhaseScript.Value.ROOM_TRANSITION, "new offer resolves")
	_assert_accepts_phase(suite, orchestrator.transition_completed(), orchestrator, RunPhaseScript.Value.ROOM_ENTERING, "boss transition enters room")
	_assert_accepts_phase(suite, orchestrator.room_entered(true), orchestrator, RunPhaseScript.Value.BOSS_ACTIVE, "boss room enters boss phase")
	suite.assert_true(orchestrator.state.open_offer.is_empty(), "boss starts without a selection")
	_assert_accepts_phase(suite, orchestrator.boss_defeated({"result": "victory"}), orchestrator, RunPhaseScript.Value.VICTORY, "boss defeat enters victory directly")
	suite.assert_equal(orchestrator.state.result["result"], "victory", "victory result is retained")

	var terminal_revision: int = orchestrator.state.revision
	var late_death = orchestrator.player_died({"result": "death"})
	suite.assert_equal(late_death.code, &"TERMINAL_STATE", "late death is rejected after victory")
	suite.assert_equal(orchestrator.state.phase, RunPhaseScript.Value.VICTORY, "terminal phase is immutable")
	suite.assert_equal(orchestrator.state.revision, terminal_revision, "terminal rejection leaves revision unchanged")


func _test_invalid_transitions(suite) -> void:
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	var revision_before: int = orchestrator.state.revision
	var invalid = orchestrator.room_cleared()
	suite.assert_equal(invalid.code, &"INVALID_PHASE", "room clear from hub is rejected")
	suite.assert_equal(orchestrator.state.phase, RunPhaseScript.Value.HUB, "invalid command leaves phase unchanged")
	suite.assert_equal(orchestrator.state.revision, revision_before, "invalid command leaves revision unchanged")


func _test_pause_overlay(suite) -> void:
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run(_config(), "run-pause")
	orchestrator.preparation_completed()
	orchestrator.room_entered(false)
	var active_phase: int = orchestrator.state.phase
	var revision_before: int = orchestrator.state.revision
	var paused = orchestrator.pause_run()
	suite.assert_true(paused.ok, "pause is accepted during combat")
	suite.assert_true(orchestrator.state.suspended, "pause sets suspended overlay")
	suite.assert_equal(orchestrator.state.phase, active_phase, "pause preserves active phase")
	suite.assert_equal(orchestrator.state.revision, revision_before + 1, "pause advances revision once")

	var resumed = orchestrator.resume_run()
	suite.assert_true(resumed.ok, "resume is accepted")
	suite.assert_true(not orchestrator.state.suspended, "resume clears suspended overlay")
	suite.assert_equal(orchestrator.state.phase, active_phase, "resume preserves active phase")


func _assert_accepts_phase(suite, result, orchestrator, expected_phase: int, label: String) -> void:
	suite.assert_true(result.ok, "%s command succeeds" % label)
	suite.assert_equal(orchestrator.state.phase, expected_phase, label)
	suite.assert_equal(result.new_revision, orchestrator.state.revision, "%s returns current revision" % label)


func _config() -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": "M1",
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["time_stop", "time_rewind"],
		"difficulty": "normal",
		"seed": 123,
	}


func _offer(revision: int, offer_id: String = "") -> Dictionary:
	return {
		"schema_version": 1,
		"offer_id": offer_id if not offer_id.is_empty() else "run-legal:room-01:item:%d" % revision,
		"revision": revision,
		"category": "item",
		"title_key": "UI_CHOOSE_REWARD",
		"can_skip": false,
		"options": [{
			"option_id": "frozen_burst",
			"content_id": "frozen_burst",
			"name_key": "FROZEN_BURST_NAME",
			"description_key": "FROZEN_BURST_DESC",
			"archetype_key": "ARCHETYPE_TIME_STOP_BURST",
			"role_key": "ROLE_STARTER",
			"rarity": "common",
			"icon_id": "item_frozen_burst",
			"effect_summary_keys": ["EFFECT_TIME_STOP_DURATION"],
		}],
	}
