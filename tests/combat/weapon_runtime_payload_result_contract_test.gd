extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const WeaponRuntimeScript := preload("res://scripts/combat/weapons/weapon_runtime.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var runtime = WeaponRuntimeScript.new()
	suite.assert_true(runtime.has_method("handle_payload_result"), "weapon runtime exposes the payload-result ingress contract")
	var result: Dictionary = runtime.handle_payload_result(
		7,
		2,
		{"outcome_id": "test", "terminal": true}
	)
	suite.assert_equal(bool(result.get("ok", true)), false, "base runtime rejects unsupported payload results")
	suite.assert_equal(StringName(str(result.get("code", ""))), &"UNSUPPORTED_PAYLOAD_RESULT", "base runtime fails closed with a stable code")
	suite.finish(get_tree())
