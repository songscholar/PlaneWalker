extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RunOrchestratorScript := preload("res://scripts/application/run_orchestrator.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var orchestrator = RunOrchestratorScript.new()
	orchestrator.enter_hub()
	orchestrator.start_run(_config(), "authority-contract")
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
	suite.finish(get_tree())


func _has_property(value: Object, property_name: String) -> bool:
	for property: Dictionary in value.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


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
