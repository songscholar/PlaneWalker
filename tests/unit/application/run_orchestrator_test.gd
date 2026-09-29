extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_legal_run_path(suite)
	_test_selection_writeback(suite)
	_test_invalid_selection_definitions(suite)
	_test_death_closes_active_selection(suite)
	_test_invalid_transitions(suite)
	_test_pause_overlay(suite)
	_test_authoritative_run_clock(suite)
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

	var revision_after_clear: int = orchestrator.revision()
	var duplicate_clear = orchestrator.room_cleared()
	suite.assert_equal(duplicate_clear.code, &"INVALID_PHASE", "repeated room clear is rejected")
	suite.assert_equal(orchestrator.revision(), revision_after_clear, "repeated room clear leaves revision unchanged")

	var first_offer_id := "run-legal:room-01:item:first"
	_assert_accepts_phase(suite, orchestrator.open_selection(_offer(orchestrator.revision(), first_offer_id)), orchestrator, RunPhaseScript.Value.SELECTION_ACTIVE, "selection opens")
	_assert_accepts_phase(suite, orchestrator.selection_resolved(), orchestrator, RunPhaseScript.Value.ROOM_TRANSITION, "selection resolves")
	suite.assert_true(orchestrator.has_consumed_offer(first_offer_id), "resolved selection records consumed offer")
	_assert_accepts_phase(suite, orchestrator.transition_completed(), orchestrator, RunPhaseScript.Value.ROOM_ENTERING, "transition enters next room")
	_assert_accepts_phase(suite, orchestrator.room_entered(false), orchestrator, RunPhaseScript.Value.COMBAT_ACTIVE, "next normal room enters combat")
	_assert_accepts_phase(suite, orchestrator.room_cleared(), orchestrator, RunPhaseScript.Value.ROOM_RESOLVING, "next combat resolves")
	var repeated_offer = orchestrator.open_selection(_offer(orchestrator.revision(), first_offer_id))
	suite.assert_equal(repeated_offer.code, &"ALREADY_CONSUMED", "consumed offer cannot reopen")
	suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.ROOM_RESOLVING, "rejected consumed offer leaves phase unchanged")
	_assert_accepts_phase(suite, orchestrator.open_selection(_offer(orchestrator.revision(), "run-legal:room-02:item:second")), orchestrator, RunPhaseScript.Value.SELECTION_ACTIVE, "new offer opens")
	_assert_accepts_phase(suite, orchestrator.selection_resolved(), orchestrator, RunPhaseScript.Value.ROOM_TRANSITION, "new offer resolves")
	_assert_accepts_phase(suite, orchestrator.transition_completed(), orchestrator, RunPhaseScript.Value.ROOM_ENTERING, "boss transition enters room")
	_assert_accepts_phase(suite, orchestrator.room_entered(true), orchestrator, RunPhaseScript.Value.BOSS_ACTIVE, "boss room enters boss phase")
	suite.assert_true(orchestrator.snapshot()["open_offer"].is_empty(), "boss starts without a selection")
	_assert_accepts_phase(suite, orchestrator.boss_defeated({"result": "victory"}), orchestrator, RunPhaseScript.Value.VICTORY, "boss defeat enters victory directly")
	suite.assert_equal(orchestrator.snapshot()["result"]["result"], "victory", "victory result is retained")

	var terminal_revision: int = orchestrator.revision()
	var late_death = orchestrator.player_died({"result": "death"})
	suite.assert_equal(late_death.code, &"TERMINAL_STATE", "late death is rejected after victory")
	suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.VICTORY, "terminal phase is immutable")
	suite.assert_equal(orchestrator.revision(), terminal_revision, "terminal rejection leaves revision unchanged")


func _test_invalid_transitions(suite) -> void:
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	var revision_before: int = orchestrator.revision()
	var invalid = orchestrator.room_cleared()
	suite.assert_equal(invalid.code, &"INVALID_PHASE", "room clear from hub is rejected")
	suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.HUB, "invalid command leaves phase unchanged")
	suite.assert_equal(orchestrator.revision(), revision_before, "invalid command leaves revision unchanged")


func _test_selection_writeback(suite) -> void:
	var cases: Array[Dictionary] = [
		{
			"category": "item",
			"id": "frozen_burst",
			"field": "items",
			"archetype": "time_stop_burst",
		},
		{
			"category": "blessing",
			"id": "bls_stop_weakpoint",
			"field": "blessings",
			"archetype": "time_stop_burst",
		},
		{
			"category": "curse",
			"id": "glass_tempo",
			"field": "curses",
			"archetype": "accelerated_combo",
		},
		{
			"category": "talent",
			"id": "tal_ruin_execute",
			"field": "talents",
			"archetype": "accelerated_combo",
		},
	]
	for case: Dictionary in cases:
		var offer_id := "run-writeback:%s" % str(case["category"])
		var orchestrator = _orchestrator_with_open_offer(offer_id)
		var definition := {
			"id": case["id"],
			"category": case["category"],
			"archetype": case["archetype"],
			"effects": {"test_effect": 1.0},
		}
		var result = orchestrator.selection_resolved(definition)
		suite.assert_true(result.ok, "%s definition resolves" % str(case["category"]))
		var build: Dictionary = orchestrator.snapshot()["build"]
		var recorded: Array = build[str(case["field"])]
		suite.assert_true(recorded.has(str(case["id"])), "%s writes to authoritative build" % str(case["category"]))
		suite.assert_equal(build["reward_history"].size(), 1, "%s records one build history entry" % str(case["category"]))
		if str(case["category"]) == "item":
			suite.assert_equal(build["dominant_archetype"], "time_stop_burst", "item updates dominant archetype")

	var decline = _orchestrator_with_open_offer("run-writeback:decline")
	var declined = decline.selection_resolved({
		"id": "decline_contract",
		"category": "contract",
		"effects": {},
	})
	suite.assert_true(declined.ok, "decline contract resolves")
	suite.assert_true(decline.snapshot()["build"]["curses"].is_empty(), "decline contract records no curse")
	suite.assert_true(decline.snapshot()["build"]["reward_history"].is_empty(), "decline contract records no build history")

	var compatibility = _orchestrator_with_open_offer("run-writeback:compatibility")
	var compatibility_result = compatibility.selection_resolved()
	suite.assert_true(compatibility_result.ok, "empty definition remains compatible")
	suite.assert_true(compatibility.snapshot()["build"]["reward_history"].is_empty(), "compatibility resolution does not invent build data")

	var duplicate = _orchestrator_with_open_offer("run-writeback:duplicate")
	var duplicate_definition := {
		"id": "frozen_burst",
		"category": "item",
		"archetype": "time_stop_burst",
		"effects": {},
	}
	suite.assert_true(duplicate.selection_resolved(duplicate_definition).ok, "first canonical selection resolves")
	duplicate.transition_completed()
	duplicate.room_entered(false)
	duplicate.room_cleared()
	var reopen = duplicate.open_selection(_offer(duplicate.revision(), "run-writeback:duplicate"))
	suite.assert_equal(reopen.code, &"ALREADY_CONSUMED", "consumed offer cannot resolve a second time")
	suite.assert_equal(duplicate.snapshot()["build"]["reward_history"].size(), 1, "duplicate resolution does not duplicate build history")


func _test_invalid_selection_definitions(suite) -> void:
	var invalid_definitions: Array[Dictionary] = [
		{
			"definition": {"category": "item", "effects": {}},
			"field": "definition.id",
			"label": "missing definition id",
		},
		{
			"definition": {"id": "unknown", "category": "mystery", "effects": {}},
			"field": "definition.category",
			"label": "unknown definition category",
		},
		{
			"definition": {"id": "risky_contract", "category": "contract", "effects": {}},
			"field": "definition.id",
			"label": "non-decline contract",
		},
	]
	for case: Dictionary in invalid_definitions:
		var offer_id := "run-invalid:%s" % str(case["label"]).replace(" ", "-")
		var orchestrator = _orchestrator_with_open_offer(offer_id)
		var before: Dictionary = orchestrator.snapshot()
		var phase_before: int = before["phase"]
		var revision_before: int = before["revision"]
		var offer_before: Dictionary = before["open_offer"]
		var build_before: Dictionary = before["build"]
		var result = orchestrator.selection_resolved(case["definition"])
		suite.assert_equal(result.code, &"INVALID_ARGUMENT", "%s is rejected" % str(case["label"]))
		suite.assert_equal(result.context.get("field", ""), case["field"], "%s reports the invalid field" % str(case["label"]))
		var after: Dictionary = orchestrator.snapshot()
		suite.assert_equal(after["phase"], phase_before, "%s leaves phase unchanged" % str(case["label"]))
		suite.assert_equal(after["revision"], revision_before, "%s leaves revision unchanged" % str(case["label"]))
		suite.assert_equal(after["open_offer"], offer_before, "%s leaves the offer open" % str(case["label"]))
		suite.assert_true(not orchestrator.has_consumed_offer(offer_id), "%s does not consume the offer" % str(case["label"]))
		suite.assert_equal(after["build"], build_before, "%s leaves build unchanged" % str(case["label"]))


func _test_death_closes_active_selection(suite) -> void:
	var orchestrator = _orchestrator_with_open_offer("run-selection-death")
	var result = orchestrator.player_died({"result": "death", "source": "selection"})
	suite.assert_true(result.ok, "selection-phase death enters terminal defeat")
	suite.assert_equal(orchestrator.phase(), RunPhaseScript.Value.DEFEAT, "selection-phase death sets defeat")
	suite.assert_true(orchestrator.snapshot()["open_offer"].is_empty(), "selection-phase death closes the active offer")
	suite.assert_true(not orchestrator.has_consumed_offer("run-selection-death"), "death does not consume the abandoned offer")


func _test_pause_overlay(suite) -> void:
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run(_config(), "run-pause")
	orchestrator.preparation_completed()
	orchestrator.room_entered(false)
	var active_phase: int = orchestrator.phase()
	var revision_before: int = orchestrator.revision()
	var paused = orchestrator.pause_run()
	suite.assert_true(paused.ok, "pause is accepted during combat")
	suite.assert_true(orchestrator.snapshot()["suspended"], "pause sets suspended overlay")
	suite.assert_equal(orchestrator.phase(), active_phase, "pause preserves active phase")
	suite.assert_equal(orchestrator.revision(), revision_before + 1, "pause advances revision once")

	var resumed = orchestrator.resume_run()
	suite.assert_true(resumed.ok, "resume is accepted")
	suite.assert_true(not orchestrator.snapshot()["suspended"], "resume clears suspended overlay")
	suite.assert_equal(orchestrator.phase(), active_phase, "resume preserves active phase")


func _test_authoritative_run_clock(suite) -> void:
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run(_config(), "run-clock")
	orchestrator.preparation_completed()
	orchestrator.room_entered(false)
	var revision_before: int = orchestrator.revision()

	var first = orchestrator.advance_time(0.016)
	suite.assert_true(first.ok, "active run accepts clock advancement")
	suite.assert_equal(orchestrator.snapshot()["run_time_ms"], 16, "clock records whole milliseconds")
	suite.assert_equal(orchestrator.revision(), revision_before, "clock ticks do not invalidate gameplay revisions")
	orchestrator.advance_time(0.0045)
	suite.assert_equal(orchestrator.snapshot()["run_time_ms"], 20, "clock retains fractional milliseconds without running fast")

	orchestrator.pause_run()
	var paused_time: int = orchestrator.snapshot()["run_time_ms"]
	suite.assert_true(orchestrator.advance_time(1.0).ok, "paused clock tick is an accepted no-op")
	suite.assert_equal(orchestrator.snapshot()["run_time_ms"], paused_time, "paused run time does not advance")
	orchestrator.resume_run()
	orchestrator.advance_time(0.125)
	suite.assert_equal(orchestrator.snapshot()["run_time_ms"], 145, "resumed run continues the authoritative clock")

	var before_invalid: int = orchestrator.snapshot()["run_time_ms"]
	var invalid = orchestrator.advance_time(-0.25)
	suite.assert_equal(invalid.code, &"INVALID_ARGUMENT", "negative clock deltas are rejected")
	suite.assert_equal(orchestrator.snapshot()["run_time_ms"], before_invalid, "rejected clock delta cannot mutate time")
	orchestrator.player_died({"result": "death"})
	suite.assert_true(orchestrator.advance_time(1.0).ok, "terminal clock tick is an accepted no-op")
	suite.assert_equal(orchestrator.snapshot()["run_time_ms"], before_invalid, "terminal run time remains frozen")


func _assert_accepts_phase(suite, result, orchestrator, expected_phase: int, label: String) -> void:
	suite.assert_true(result.ok, "%s command succeeds" % label)
	suite.assert_equal(orchestrator.phase(), expected_phase, label)
	suite.assert_equal(result.new_revision, orchestrator.revision(), "%s returns current revision" % label)


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


func _orchestrator_with_open_offer(offer_id: String):
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run(_config(), "run-selection")
	orchestrator.preparation_completed()
	orchestrator.room_entered(false)
	orchestrator.room_cleared()
	orchestrator.open_selection(_offer(orchestrator.revision(), offer_id))
	return orchestrator


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
