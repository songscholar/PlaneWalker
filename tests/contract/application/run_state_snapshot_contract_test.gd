extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")
const RunPhaseScript := preload("res://scripts/application/run_phase.gd")

const M1_ARCHETYPE_SCORES := {
	"freeze_burst": 0,
	"rewind_echo": 0,
	"accelerated_combo": 0,
}
const LAUNCH_ARCHETYPE_SCORES := {
	"freeze_burst": 0,
	"rewind_echo": 0,
	"rift_trap": 0,
	"accelerated_combo": 0,
	"low_hp_void": 0,
	"perfect_guard": 0,
	"piercing_barrage": 0,
	"echo_legion": 0,
}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_initialized_archetype_domains(suite)
	_test_definition_application_contract(suite)
	_test_dominant_archetype_order(suite)
	_test_unknown_archetype_fails_closed(suite)
	_test_snapshot_isolation(suite)
	suite.finish(get_tree())


func _test_snapshot_isolation(suite) -> void:
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run(_config("M1"), "authority-contract")
	var first: Dictionary = orchestrator.snapshot()
	first["phase"] = 999
	first["resources"]["chronos_shards"] = 999
	first["stats"]["kills"] = 999
	first["events"].append({"id": "forged"})
	first["build"]["items"].append("forged")
	var second: Dictionary = orchestrator.snapshot()
	suite.assert_true(not _has_property(orchestrator, "state"), "orchestrator exposes no mutable state property")
	suite.assert_true(second["phase"] != 999, "snapshot phase is isolated")
	suite.assert_equal(second["resources"], {}, "snapshot resources are isolated")
	suite.assert_equal(second["stats"], {"kills": 0}, "snapshot stats are isolated")
	suite.assert_equal(second["events"], [], "snapshot events are isolated")
	suite.assert_equal(second["build"]["items"], [], "snapshot build is isolated")


func _test_initialized_archetype_domains(suite) -> void:
	var m1 = _started_orchestrator("M1", "archetype-domain-m1")
	var m1_build: Dictionary = m1.snapshot()["build"]
	suite.assert_equal(
		m1_build["archetypes"],
		M1_ARCHETYPE_SCORES,
		"M1 snapshot initializes exactly the three frozen archetype scores"
	)
	suite.assert_equal(m1_build["dominant_archetype"], "", "zeroed M1 domain has no dominant archetype")

	var launch = _started_orchestrator("LAUNCH", "archetype-domain-launch")
	var launch_build: Dictionary = launch.snapshot()["build"]
	suite.assert_equal(
		launch_build["archetypes"],
		LAUNCH_ARCHETYPE_SCORES,
		"Launch snapshot initializes exactly the eight approved archetype scores"
	)
	suite.assert_equal(launch_build["dominant_archetype"], "", "zeroed Launch domain has no dominant archetype")


func _test_definition_application_contract(suite) -> void:
	var orchestrator = _started_orchestrator("LAUNCH", "archetype-application")
	var selected = _resolve_definition(orchestrator, {
		"id": "freeze_burst_starter_1",
		"category": "item",
		"archetype": "freeze_burst",
		"role": "starter",
		"effects": {},
	}, "archetype-application:freeze")
	suite.assert_true(selected.ok, "canonical definition resolves through authoritative build state")
	var after_item: Dictionary = orchestrator.snapshot()["build"]
	var expected_after_item := LAUNCH_ARCHETYPE_SCORES.duplicate(true)
	expected_after_item["freeze_burst"] = 1
	suite.assert_equal(
		after_item["archetypes"],
		expected_after_item,
		"applying a definition increments only its authoritative archetype once"
	)

	var utility = _resolve_definition(orchestrator, {
		"id": "launch_utility_guard",
		"category": "item",
		"archetype": "",
		"role": "utility",
		"effects": {},
	}, "archetype-application:utility")
	suite.assert_true(utility.ok, "explicit utility definition resolves without an archetype")
	suite.assert_equal(
		orchestrator.snapshot()["build"]["archetypes"],
		expected_after_item,
		"utility with an empty archetype adds no score"
	)

	var curse = _resolve_definition(orchestrator, {
		"id": "low_hp_void_risk_1",
		"category": "curse",
		"archetype": "low_hp_void",
		"role": "risk",
		"effects": {},
	}, "archetype-application:curse")
	suite.assert_true(curse.ok, "canonical risk curse resolves through the unified definition path")
	var expected_after_curse := expected_after_item.duplicate(true)
	expected_after_curse["low_hp_void"] = 1
	suite.assert_equal(
		orchestrator.snapshot()["build"]["archetypes"],
		expected_after_curse,
		"curse archetype contributes exactly once through the unified definition path"
	)


func _test_dominant_archetype_order(suite) -> void:
	var orchestrator = _started_orchestrator("M1", "archetype-tie-order")
	_resolve_definition(orchestrator, {
		"id": "rewind_echo_starter_1",
		"category": "item",
		"archetype": "rewind_echo",
		"role": "starter",
		"effects": {},
	}, "archetype-tie-order:rewind")
	_resolve_definition(orchestrator, {
		"id": "freeze_burst_starter_2",
		"category": "item",
		"archetype": "freeze_burst",
		"role": "starter",
		"effects": {},
	}, "archetype-tie-order:freeze")
	var build: Dictionary = orchestrator.snapshot()["build"]
	suite.assert_equal(build["archetypes"].get("freeze_burst"), 1, "tie fixture records Freeze Burst once")
	suite.assert_equal(build["archetypes"].get("rewind_echo"), 1, "tie fixture records Rewind Echo once")
	suite.assert_equal(
		build["dominant_archetype"],
		"freeze_burst",
		"equal scores resolve by approved archetype order rather than insertion order"
	)


func _test_unknown_archetype_fails_closed(suite) -> void:
	var orchestrator = _started_orchestrator("LAUNCH", "archetype-unknown")
	_open_selection(orchestrator, "archetype-unknown:offer")
	var before: Dictionary = orchestrator.snapshot()
	var result = orchestrator.selection_resolved({
		"id": "itm_internal_mechanic",
		"category": "item",
		"archetype": "time_stop_burst",
		"role": "starter",
		"effects": {},
	})
	suite.assert_true(not result.ok, "unknown or internal-mechanic archetype fails closed")
	suite.assert_equal(result.code, &"INVALID_ARGUMENT", "unknown archetype reports a stable rejection")
	suite.assert_equal(
		result.context.get("field"),
		"definition.archetype",
		"unknown archetype identifies the rejected definition field"
	)
	suite.assert_equal(orchestrator.snapshot(), before, "rejected archetype cannot mutate or consume authoritative state")


func _has_property(value: Object, property_name: String) -> bool:
	for property: Dictionary in value.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _started_orchestrator(milestone: String, run_id: String) -> RefCounted:
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run(_config(milestone), run_id)
	return orchestrator


func _resolve_definition(orchestrator, definition: Dictionary, offer_id: String):
	_open_selection(orchestrator, offer_id)
	return orchestrator.selection_resolved(definition)


func _open_selection(orchestrator, offer_id: String) -> void:
	match orchestrator.phase():
		RunPhaseScript.Value.RUN_PREPARING:
			orchestrator.preparation_completed()
			orchestrator.room_entered(false)
		RunPhaseScript.Value.ROOM_TRANSITION:
			orchestrator.transition_completed()
			orchestrator.room_entered(false)
	orchestrator.room_cleared()
	orchestrator.open_selection(_offer(orchestrator.revision(), offer_id))


func _offer(revision: int, offer_id: String) -> Dictionary:
	return {
		"schema_version": 1,
		"offer_id": offer_id,
		"revision": revision,
		"category": "item",
		"title_key": "UI_CHOOSE_REWARD",
		"can_skip": false,
		"options": [{
			"option_id": "test-option",
			"content_id": "test-content",
			"name_key": "TEST_NAME",
			"description_key": "TEST_DESC",
			"archetype_key": "ARCHETYPE_FREEZE_BURST_NAME",
			"role_key": "ROLE_STARTER",
			"rarity": "common",
			"icon_id": "test-icon",
			"effect_summary_keys": [],
		}],
	}


func _config(milestone: String) -> Dictionary:
	return {
		"schema_version": 1,
		"milestone": milestone,
		"character_id": "wanderer",
		"weapon_id": "sword",
		"enabled_time_skills": ["stop", "rewind"],
		"difficulty": "normal",
		"seed": 123,
	}
