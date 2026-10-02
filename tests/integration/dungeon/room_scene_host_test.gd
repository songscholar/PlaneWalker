extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const RoomSceneHostScript := preload("res://scripts/dungeon/room_scene_host.gd")

const TEMPLATE_PATH := "res://data/content_packs/base/content/room_templates.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var templates := _load_templates()
	if templates.size() < 2:
		suite.assert_true(false, "room host fixtures are available")
		suite.finish(get_tree())
		return
	var first := templates[0] as Dictionary
	var second := templates[1] as Dictionary
	var host := RoomSceneHostScript.new()
	add_child(host)
	_test_first_commit_can_compensate_to_empty(suite, host, first)
	_test_two_phase_commit_and_rollback(suite, host, first, second)
	_test_staged_failures_are_atomic(suite, host, first, second)
	_test_reset_disposes_pending(suite, host, first)
	host.reset()
	host.free()
	suite.finish(get_tree())


func _test_first_commit_can_compensate_to_empty(suite, host: Node, template: Dictionary) -> void:
	var prepared: Dictionary = host.call(
		"prepare_transition", _node(template, "initial-compensation"), template, _context(template, 0)
	)
	suite.assert_true(bool(prepared.get("ok", false)), "initial room stages without a prior scene")
	var ticket := prepared.get("ticket", {}) as Dictionary
	suite.assert_true(bool(host.call("commit_transition", ticket).get("ok", false)), "initial room enters committed state")
	suite.assert_true(bool(host.call("rollback_transition", ticket).get("ok", false)), "initial committed room compensates back to no scene")
	suite.assert_equal(host.call("active_snapshot").get("instance_id"), 0, "initial compensation restores the empty active scene")


func _test_two_phase_commit_and_rollback(suite, host: Node, first: Dictionary, second: Dictionary) -> void:
	var first_result: Dictionary = host.call("transition_to", _node(first, "first"), first, _context(first, 1))
	suite.assert_true(bool(first_result.get("ok", false)), "transition_to composes prepare and commit")
	var first_snapshot: Dictionary = host.call("active_snapshot")
	suite.assert_equal(first_snapshot.get("content_id"), str(first["id"]), "first room becomes active")

	var prepared: Dictionary = host.call("prepare_transition", _node(second, "second"), second, _context(second, 2))
	suite.assert_true(bool(prepared.get("ok", false)), "second room stages under a transition ticket")
	suite.assert_equal(host.call("active_snapshot"), first_snapshot, "prepare does not replace the active room")
	var busy: Dictionary = host.call("prepare_transition", _node(second, "busy"), second, _context(second, 3))
	suite.assert_true(not bool(busy.get("ok", true)), "one pending ticket excludes another prepare")
	var rolled_back: Dictionary = host.call("rollback_transition", prepared["ticket"])
	suite.assert_true(bool(rolled_back.get("ok", false)), "prepared room can be rolled back")
	suite.assert_equal(host.call("active_snapshot"), first_snapshot, "rollback preserves exact active-room authority")
	suite.assert_true((host.call("pending_transition_ticket") as Dictionary).is_empty(), "rollback clears the pending ticket")
	var duplicate_rollback: Dictionary = host.call("rollback_transition", prepared["ticket"])
	suite.assert_true(not bool(duplicate_rollback.get("ok", true)), "duplicate rollback fails closed")

	prepared = host.call("prepare_transition", _node(second, "second"), second, _context(second, 4))
	var ticket := prepared["ticket"] as Dictionary
	var original_generation := int(first_snapshot["instance_generation"])
	host.set("_active_generation", original_generation + 1)
	var stale: Dictionary = host.call("commit_transition", ticket)
	suite.assert_true(not bool(stale.get("ok", true)), "stale commit fails closed")
	suite.assert_true(not (host.call("pending_transition_ticket") as Dictionary).is_empty(), "stale commit leaves its staged ticket recoverable")
	suite.assert_true(bool(host.call("rollback_transition", ticket).get("ok", false)), "stale ticket remains rollback-capable")
	host.set("_active_generation", original_generation)

	prepared = host.call("prepare_transition", _node(second, "second"), second, _context(second, 5))
	ticket = prepared["ticket"] as Dictionary
	var committed: Dictionary = host.call("commit_transition", ticket)
	suite.assert_true(bool(committed.get("ok", false)), "valid ticket commits the staged room")
	suite.assert_equal(committed.get("receipt", {}).get("prior_content_id"), str(first["id"]), "receipt preserves prior identity")
	suite.assert_equal(committed.get("receipt", {}).get("target_content_id"), str(second["id"]), "receipt preserves target identity")
	suite.assert_true(not bool(host.call("commit_transition", ticket).get("ok", true)), "duplicate commit fails closed")
	suite.assert_true(not (host.call("pending_transition_ticket") as Dictionary).is_empty(), "committed room remains compensatable until confirmation")
	var compensated: Dictionary = host.call("rollback_transition", ticket)
	suite.assert_true(bool(compensated.get("ok", false)), "committed ticket can compensate before confirmation")
	suite.assert_equal(host.call("active_snapshot"), first_snapshot, "committed compensation restores the byte-identical active-room snapshot")

	prepared = host.call("prepare_transition", _node(second, "confirmed"), second, _context(second, 6))
	ticket = prepared["ticket"] as Dictionary
	committed = host.call("commit_transition", ticket)
	suite.assert_true(bool(committed.get("ok", false)), "confirmation fixture commits")
	var confirmed: Dictionary = host.call("confirm_transition", ticket)
	suite.assert_true(bool(confirmed.get("ok", false)), "confirmation retires the prior room")
	suite.assert_true((host.call("pending_transition_ticket") as Dictionary).is_empty(), "confirmation clears the compensation ticket")
	suite.assert_true(not bool(host.call("rollback_transition", ticket).get("ok", true)), "confirmed ticket cannot roll back")


func _test_staged_failures_are_atomic(suite, host: Node, first: Dictionary, second: Dictionary) -> void:
	var baseline: Dictionary = host.call("active_snapshot")
	host.call("configure_loader", func(_path: String): return null)
	var load_failed: Dictionary = host.call("transition_to", _node(first, "load"), first, _context(first, 10))
	suite.assert_true(not bool(load_failed.get("ok", true)), "load failure is rejected")
	suite.assert_equal(host.call("active_snapshot"), baseline, "load failure preserves active room")
	host.call("clear_test_adapters")

	host.call("configure_instantiator", func(_resource: Variant): return null)
	var instantiate_failed: Dictionary = host.call("transition_to", _node(first, "instantiate"), first, _context(first, 11))
	suite.assert_true(not bool(instantiate_failed.get("ok", true)), "instantiate failure is rejected")
	suite.assert_equal(host.call("active_snapshot"), baseline, "instantiate failure preserves active room")
	host.call("clear_test_adapters")

	host.call("configure_contract_validator", func(_room: Node2D, _template: Dictionary): return false)
	var contract_failed: Dictionary = host.call("transition_to", _node(first, "contract"), first, _context(first, 12))
	suite.assert_true(not bool(contract_failed.get("ok", true)), "contract failure is rejected")
	suite.assert_equal(host.call("active_snapshot"), baseline, "contract failure preserves active room")
	host.call("clear_test_adapters")

	host.call("configure_binding_adapter", func(_room: Node2D, _node: Dictionary, _template: Dictionary, _context: Dictionary): return false)
	var bind_failed: Dictionary = host.call("transition_to", _node(first, "bind"), first, _context(first, 13))
	suite.assert_true(not bool(bind_failed.get("ok", true)), "bind failure is rejected")
	suite.assert_equal(host.call("active_snapshot"), baseline, "bind failure preserves active room")
	host.call("clear_test_adapters")

	host.call("configure_activation_adapter", func(_room: Node2D, preflight: bool): return true if preflight else false)
	var activation_failed: Dictionary = host.call("transition_to", _node(first, "activation"), first, _context(first, 14))
	suite.assert_true(not bool(activation_failed.get("ok", true)), "activation failure is rejected")
	suite.assert_equal(host.call("active_snapshot"), baseline, "activation failure preserves active room")
	host.call("clear_test_adapters")

	var wrong_authority := _node(second, "wrong")
	wrong_authority["template_id"] = str(first["id"])
	var authority_failed: Dictionary = host.call("transition_to", wrong_authority, second, _context(second, 15))
	suite.assert_true(not bool(authority_failed.get("ok", true)), "node/template authority drift is rejected before load")
	suite.assert_equal(host.call("active_snapshot"), baseline, "authority rejection preserves active room")


func _test_reset_disposes_pending(suite, host: Node, template: Dictionary) -> void:
	var prepared: Dictionary = host.call("prepare_transition", _node(template, "reset"), template, _context(template, 20))
	suite.assert_true(bool(prepared.get("ok", false)), "reset fixture stages a room")
	host.call("reset")
	suite.assert_true((host.call("pending_transition_ticket") as Dictionary).is_empty(), "reset clears the pending ticket")
	suite.assert_equal(host.call("active_snapshot").get("instance_id"), 0, "reset clears the active room")
	suite.assert_true(not bool(host.call("commit_transition", prepared["ticket"]).get("ok", true)), "reset invalidates the old ticket")


func _node(template: Dictionary, suffix: String) -> Dictionary:
	return {
		"id": "node-%s" % suffix,
		"template_id": str(template["id"]),
		"room_type": str(template["room_type"]),
	}


func _context(template: Dictionary, seed_offset: int) -> Dictionary:
	var floor_id := str((template["floor_ids"] as Array)[0])
	return {
		"floor_id": floor_id,
		"palette_id": "palette_ruins_of_remnant",
		"environment_rule_id": "rule_crumbling_ground",
		"room_seed": 20261002 + seed_offset,
		"reduced_motion": false,
		"hit_flash_enabled": true,
	}


func _load_templates() -> Array:
	var file := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if file == null:
		return []
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value as Array if value is Array else []
