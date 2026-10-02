extends Node

const EventResourceAuthorityScript := preload(
	"res://scripts/events/event_resource_authority.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_commit_duplicate_stale_and_rollback(suite)
	_test_snapshot_restore_is_strict(suite)
	_test_gold_is_rejected(suite)
	suite.finish(get_tree())


func _test_commit_duplicate_stale_and_rollback(suite) -> void:
	var authority = EventResourceAuthorityScript.new()
	suite.assert_true(authority.configure({"time_shard": 2, "forge_essence": 1}), "resource authority configures")
	var before: Dictionary = authority.snapshot()
	var prepared: Dictionary = authority.prepare_delta(
		"event_resource_spend", &"time_shard", -1, int(before["revision"])
	)
	suite.assert_true(bool(prepared.get("ok", false)), "resource spend prepares")
	suite.assert_equal(authority.snapshot(), before, "prepare mutates no resource state")
	var forged_ticket := (prepared.get("ticket", {}) as Dictionary).duplicate(true)
	forged_ticket["after"] = (forged_ticket["before"] as Dictionary).duplicate(true)
	_resign(forged_ticket)
	suite.assert_true(not bool(authority.commit_delta(forged_ticket).get("ok", false)), "re-signed forged resource ticket rejects")
	var committed: Dictionary = authority.commit_delta(prepared.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "resource spend commits")
	suite.assert_equal((authority.snapshot()["resources"] as Dictionary)["time_shard"], 1, "resource spend applies once")
	suite.assert_equal(authority.snapshot()["revision"], 1, "resource revision advances once")
	var duplicate: Dictionary = authority.prepare_delta(
		"event_resource_spend", &"time_shard", -1, int(authority.snapshot()["revision"])
	)
	suite.assert_equal(duplicate.get("code"), &"ALREADY_CONSUMED", "duplicate transaction rejects")
	var stale: Dictionary = authority.prepare_delta(
		"event_resource_stale", &"time_shard", 1, 0
	)
	suite.assert_equal(stale.get("code"), &"STALE_REVISION", "stale revision rejects")
	var forged_receipt := (committed.get("receipt", {}) as Dictionary).duplicate(true)
	forged_receipt["before"] = (forged_receipt["after"] as Dictionary).duplicate(true)
	_resign(forged_receipt)
	suite.assert_true(not bool(authority.rollback_delta(forged_receipt).get("ok", false)), "re-signed forged resource receipt rejects")
	var rolled_back: Dictionary = authority.rollback_delta(committed.get("receipt", {}))
	suite.assert_true(bool(rolled_back.get("ok", false)), "committed resource transaction rolls back")
	suite.assert_equal(authority.snapshot(), before, "rollback restores byte-identical resource state")
	var insufficient: Dictionary = authority.prepare_delta(
		"event_resource_overdraw", &"forge_essence", -2, int(authority.snapshot()["revision"])
	)
	suite.assert_equal(insufficient.get("code"), &"INSUFFICIENT_RESOURCE", "resource balance cannot become negative")


func _test_snapshot_restore_is_strict(suite) -> void:
	var authority = EventResourceAuthorityScript.new()
	authority.configure({"time_shard": 3, "forge_essence": 0})
	var original: Dictionary = authority.snapshot()
	var prepared: Dictionary = authority.prepare_delta("event_resource_gain", &"forge_essence", 2, 0)
	suite.assert_true(authority.restore_snapshot(original), "same-state restore rotates resource capability")
	suite.assert_true(not bool(authority.commit_delta(prepared.get("ticket", {})).get("ok", false)), "pre-restore resource ticket is revoked")
	prepared = authority.prepare_delta("event_resource_gain", &"forge_essence", 2, 0)
	var committed: Dictionary = authority.commit_delta(prepared.get("ticket", {}))
	suite.assert_true(bool(committed.get("ok", false)), "resource gain commits")
	var saved: Dictionary = authority.snapshot()
	var restored = EventResourceAuthorityScript.new()
	restored.configure({"time_shard": 0, "forge_essence": 0})
	suite.assert_true(restored.restore_snapshot(saved), "strict resource snapshot restores")
	suite.assert_equal(restored.snapshot(), saved, "restored resource snapshot is byte-identical")
	var forged := saved.duplicate(true)
	(forged["resources"] as Dictionary)["gold"] = 999
	suite.assert_true(not restored.can_restore_snapshot(forged), "unknown resource fails closed")
	suite.assert_equal(restored.snapshot(), saved, "rejected restore mutates nothing")
	suite.assert_true(authority.restore_snapshot(original), "authority restores an earlier canonical snapshot")
	suite.assert_equal(authority.snapshot(), original, "canonical restore replaces completed transaction history")


func _test_gold_is_rejected(suite) -> void:
	var authority = EventResourceAuthorityScript.new()
	suite.assert_true(not authority.configure({"gold": 100, "time_shard": 2}), "gold cannot enter resource authority")


func _resign(value: Dictionary) -> void:
	var unsigned := value.duplicate(true)
	unsigned.erase("fingerprint")
	value["fingerprint"] = JSON.stringify(unsigned, "", true, true).sha256_text()
