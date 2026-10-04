extends Node

const AuthorityScript := preload("res://scripts/events/event_modifier_authority.gd")
const SuiteScript := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = SuiteScript.new()
	var authority = AuthorityScript.new()
	suite.assert_true(authority.configure([], {}, []), "temporary effect authority configures")
	var first: Dictionary = authority.prepare_operations("tx_grace_old", [_operation(3, 1.15)], 0)
	suite.assert_true(first.get("ok", false), "first temporary source prepares")
	if first.get("ok", false):
		var committed: Dictionary = authority.commit_operations(first["ticket"])
		suite.assert_true(committed.get("ok", false), "first temporary source commits")
		var before: Dictionary = authority.snapshot()
		var refreshed: Dictionary = authority.prepare_operations("tx_grace_new", [_operation(2, 1.25)], 1)
		suite.assert_true(refreshed.get("ok", false), "a fresh transaction refreshes an existing modifier identity")
		if refreshed.get("ok", false):
			committed = authority.commit_operations(refreshed["ticket"])
			suite.assert_true(committed.get("ok", false), "new source commits without stacking")
			var modifiers: Array = authority.snapshot()["temporary_modifiers"]
			suite.assert_equal(modifiers.size(), 1, "one identity retains only its latest grant")
			suite.assert_equal(modifiers[0], {"modifier_id": "chronal_grace", "duration_rooms": 2, "magnitude": 1.25, "source_transaction_id": "tx_grace_new"}, "refresh replaces source and authored duration exactly")
			suite.assert_true(authority.rollback_operations(committed["receipt"]).get("ok", false), "refresh compensates atomically")
			suite.assert_equal(authority.snapshot(), before, "compensation reinstates the original source")
		suite.assert_equal(authority.prepare_operations("tx_grace_old", [_operation(3, 1.15)], 1).get("code"), &"ALREADY_CONSUMED", "consumed source cannot regrant")
		suite.assert_true(not authority.prepare_operations("tx_duplicate", [_operation(3, 1.15), _operation(2, 1.25)], 1).get("ok", false), "one transaction cannot ambiguously grant the same identity twice")
		suite.assert_equal(authority.snapshot(), before, "duplicate grant rejection preserves authority")
	suite.finish(get_tree())


func _operation(duration: int, magnitude: float) -> Dictionary:
	return {"operation": "temporary_modifier", "arguments": {"modifier_id": "chronal_grace", "duration_rooms": duration, "magnitude": magnitude}}
