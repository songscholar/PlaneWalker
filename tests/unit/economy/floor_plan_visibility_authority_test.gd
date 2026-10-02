extends Node

const FloorPlanGeneratorScript := preload("res://scripts/dungeon/floor_plan_generator.gd")
const FloorPlanVisibilityAuthorityScript := preload(
	"res://scripts/economy/floor_plan_visibility_authority.gd"
)
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const FLOORS_PATH := "res://data/content_packs/base/content/floors.json"
const TEMPLATES_PATH := "res://data/content_packs/base/content/room_templates.json"


func _ready() -> void:
	var suite = TestSuiteScript.new()
	var floors := _load_json_array(FLOORS_PATH)
	var templates := _load_json_array(TEMPLATES_PATH)
	suite.assert_equal(floors.size(), 5, "fixture exposes five launch floors")
	if floors.size() == 5 and not templates.is_empty():
		_test_five_floor_branch_reveals(suite, floors, templates)
		_test_no_hidden_target(suite, floors[0], templates)
		_test_tamper_and_stale_rejection(suite, floors[1], templates)
		_test_pending_and_committed_rollback(suite, floors[2], templates)
		_test_snapshot_restore_and_duplicate_transaction(suite, floors[3], templates)
	suite.finish(get_tree())


func _test_five_floor_branch_reveals(
	suite,
	floors: Array[Dictionary],
	templates: Array[Dictionary]
) -> void:
	for floor_index: int in range(floors.size()):
		var plan := _generated_plan(2026100200 + floor_index, floors[floor_index], templates)
		var expected_targets := _expected_reveal_targets(plan)
		suite.assert_true(
			not expected_targets.is_empty(),
			"floor %d fixture has a hidden layer beyond current candidates" % (floor_index + 1)
		)
		var authority = FloorPlanVisibilityAuthorityScript.new()
		var configured: Dictionary = authority.configure(plan)
		suite.assert_true(
			bool(configured.get("ok", false)),
			"floor %d visibility authority configures" % (floor_index + 1)
		)
		var prepared: Dictionary = authority.prepare_reveal(
			"route_reveal_floor_%d" % (floor_index + 1),
			plan
		)
		suite.assert_true(
			bool(prepared.get("ok", false)),
			"floor %d route reveal prepares" % (floor_index + 1)
		)
		if not bool(prepared.get("ok", false)):
			continue
		var ticket: Dictionary = prepared["ticket"]
		suite.assert_equal(
			ticket.get("target_node_ids"),
			expected_targets,
			"floor %d target IDs are stable and sorted" % (floor_index + 1)
		)
		var before: Dictionary = prepared["before"]
		var after: Dictionary = prepared["after"]
		suite.assert_equal(before, plan, "floor %d before snapshot is lossless" % (floor_index + 1))
		_assert_only_targets_revealed(
			suite,
			before,
			after,
			expected_targets,
			"floor %d" % (floor_index + 1)
		)
		suite.assert_equal(
			authority.floor_plan_snapshot(),
			plan,
			"floor %d prepare does not mutate authority" % (floor_index + 1)
		)
		var committed: Dictionary = authority.commit_reveal(ticket)
		suite.assert_true(
			bool(committed.get("ok", false)),
			"floor %d route reveal commits" % (floor_index + 1)
		)
		suite.assert_equal(
			authority.floor_plan_snapshot(),
			after,
			"floor %d commit installs the revealed plan" % (floor_index + 1)
		)


func _test_no_hidden_target(
	suite,
	floor: Dictionary,
	templates: Array[Dictionary]
) -> void:
	var plan := _generated_plan(77101, floor, templates)
	for target_id: String in _expected_reveal_targets(plan):
		_set_node_revealed(plan, target_id, true)
	var authority = FloorPlanVisibilityAuthorityScript.new()
	suite.assert_true(bool(authority.configure(plan).get("ok", false)), "visible fixture configures")
	var before: Dictionary = authority.snapshot()
	var rejected: Dictionary = authority.prepare_reveal("route_reveal_none", plan)
	suite.assert_equal(rejected.get("code"), &"NO_HIDDEN_TARGET", "fully visible target layer is rejected")
	suite.assert_equal(authority.snapshot(), before, "no-target rejection is atomic")


func _test_tamper_and_stale_rejection(
	suite,
	floor: Dictionary,
	templates: Array[Dictionary]
) -> void:
	var plan := _generated_plan(77102, floor, templates)
	var authority = FloorPlanVisibilityAuthorityScript.new()
	suite.assert_true(bool(authority.configure(plan).get("ok", false)), "tamper fixture configures")
	var tampered_input := plan.duplicate(true)
	tampered_input["selected_edge_ids"] = ["forged_edge"]
	var rejected_input: Dictionary = authority.prepare_reveal("route_reveal_tampered", tampered_input)
	suite.assert_equal(rejected_input.get("code"), &"STALE_FLOOR_PLAN", "tampered input is rejected")

	var prepared: Dictionary = authority.prepare_reveal("route_reveal_stale", plan)
	suite.assert_true(bool(prepared.get("ok", false)), "stale fixture prepares")
	var forged_ticket: Dictionary = (prepared["ticket"] as Dictionary).duplicate(true)
	forged_ticket["after"]["current_node_id"] = "boss"
	var rejected_ticket: Dictionary = authority.commit_reveal(forged_ticket)
	suite.assert_equal(rejected_ticket.get("code"), &"TRANSACTION_STALE", "tampered ticket is rejected")
	suite.assert_equal(authority.floor_plan_snapshot(), plan, "tampered ticket preserves the plan")
	var committed: Dictionary = authority.commit_reveal(prepared["ticket"])
	suite.assert_true(bool(committed.get("ok", false)), "original ticket remains committable")
	suite.assert_equal(
		authority.commit_reveal(prepared["ticket"]).get("code"),
		&"TRANSACTION_NOT_FOUND",
		"stale replayed ticket is rejected"
	)


func _test_pending_and_committed_rollback(
	suite,
	floor: Dictionary,
	templates: Array[Dictionary]
) -> void:
	var plan := _generated_plan(77103, floor, templates)
	var authority = FloorPlanVisibilityAuthorityScript.new()
	suite.assert_true(bool(authority.configure(plan).get("ok", false)), "rollback fixture configures")
	var pending: Dictionary = authority.prepare_reveal("route_reveal_pending_rollback", plan)
	suite.assert_true(bool(pending.get("ok", false)), "pending rollback fixture prepares")
	var rolled_pending: Dictionary = authority.rollback_reveal(pending["ticket"])
	suite.assert_true(bool(rolled_pending.get("ok", false)), "pending reveal rolls back")
	suite.assert_equal(rolled_pending.get("rolled_back"), "pending", "pending rollback reports phase")
	suite.assert_equal(authority.floor_plan_snapshot(), plan, "pending rollback preserves before plan")

	var prepared: Dictionary = authority.prepare_reveal("route_reveal_committed_rollback", plan)
	var committed: Dictionary = authority.commit_reveal(prepared["ticket"])
	suite.assert_true(bool(committed.get("ok", false)), "committed rollback fixture commits")
	var receipt: Dictionary = committed["receipt"]
	suite.assert_equal(authority.floor_plan_snapshot(), receipt["after"], "commit installs receipt after plan")
	var rolled_committed: Dictionary = authority.rollback_reveal(receipt)
	suite.assert_true(bool(rolled_committed.get("ok", false)), "committed reveal rolls back")
	suite.assert_equal(rolled_committed.get("rolled_back"), "committed", "committed rollback reports phase")
	suite.assert_equal(authority.floor_plan_snapshot(), plan, "committed rollback restores exact before plan")


func _test_snapshot_restore_and_duplicate_transaction(
	suite,
	floor: Dictionary,
	templates: Array[Dictionary]
) -> void:
	var plan := _generated_plan(77104, floor, templates)
	var authority = FloorPlanVisibilityAuthorityScript.new()
	suite.assert_true(bool(authority.configure(plan).get("ok", false)), "restore fixture configures")
	var prepared: Dictionary = authority.prepare_reveal("route_reveal_persisted", plan)
	var committed: Dictionary = authority.commit_reveal(prepared["ticket"])
	suite.assert_true(bool(committed.get("ok", false)), "restore fixture commits")
	var saved: Dictionary = authority.snapshot()
	var exposed := saved.duplicate(true)
	exposed["floor_plan"]["nodes"][0]["id"] = "mutated"
	suite.assert_equal(authority.snapshot(), saved, "snapshot is immutable to callers")

	var restored = FloorPlanVisibilityAuthorityScript.new()
	suite.assert_true(bool(restored.configure(plan).get("ok", false)), "restore target configures")
	suite.assert_true(restored.can_restore_snapshot(saved), "saved authority snapshot validates")
	suite.assert_true(restored.restore_snapshot(saved), "saved authority snapshot restores")
	suite.assert_equal(restored.snapshot(), saved, "restore is lossless")
	suite.assert_equal(
		restored.prepare_reveal("route_reveal_persisted", restored.floor_plan_snapshot()).get("code"),
		&"DUPLICATE_TRANSACTION",
		"restored transaction IDs reject duplicate route reveal"
	)
	var tampered_saved := saved.duplicate(true)
	tampered_saved["floor_plan"]["generation_digest"] = "0".repeat(64)
	suite.assert_true(not restored.can_restore_snapshot(tampered_saved), "tampered saved plan is rejected")
	suite.assert_true(not restored.restore_snapshot(tampered_saved), "tampered restore stays atomic")
	suite.assert_equal(restored.snapshot(), saved, "failed restore preserves authority state")


func _assert_only_targets_revealed(
	suite,
	before: Dictionary,
	after: Dictionary,
	target_ids: Array[String],
	label: String
) -> void:
	for field: String in [
		"selected_edge_ids", "visited_node_ids", "abandoned_node_ids",
		"current_node_id", "generation_digest", "revision",
	]:
		suite.assert_equal(after[field], before[field], "%s preserves %s" % [label, field])
	suite.assert_equal(after["edges"], before["edges"], "%s preserves every edge" % label)
	for before_value: Variant in before["nodes"]:
		var before_node := before_value as Dictionary
		var after_node := _node_by_id(after, str(before_node["id"]))
		for field: String in before_node.keys():
			var expected: Variant = before_node[field]
			if field == "revealed" and target_ids.has(str(before_node["id"])):
				expected = true
			suite.assert_equal(
				after_node.get(field),
				expected,
				"%s node %s preserves %s" % [label, before_node["id"], field]
			)


func _expected_reveal_targets(plan: Dictionary) -> Array[String]:
	var current_id := str(plan["current_node_id"])
	var candidate_ids: Array[String] = []
	for edge_value: Variant in plan["edges"]:
		var edge := edge_value as Dictionary
		if str(edge["source_node_id"]) == current_id:
			candidate_ids.append(str(edge["destination_node_id"]))
	var target_ids: Array[String] = []
	for edge_value: Variant in plan["edges"]:
		var edge := edge_value as Dictionary
		var target_id := str(edge["destination_node_id"])
		if (
			candidate_ids.has(str(edge["source_node_id"]))
			and not (plan["visited_node_ids"] as Array).has(target_id)
			and not (plan["abandoned_node_ids"] as Array).has(target_id)
			and not bool(_node_by_id(plan, target_id).get("revealed", false))
			and not target_ids.has(target_id)
		):
			target_ids.append(target_id)
	target_ids.sort()
	return target_ids


func _generated_plan(seed: int, floor: Dictionary, templates: Array[Dictionary]) -> Dictionary:
	var generated: Dictionary = FloorPlanGeneratorScript.new().generate(seed, floor, templates)
	return (generated.get("plan", {}) as Dictionary).duplicate(true)


func _set_node_revealed(plan: Dictionary, node_id: String, revealed: bool) -> void:
	for node_value: Variant in plan["nodes"]:
		var node := node_value as Dictionary
		if str(node["id"]) == node_id:
			node["revealed"] = revealed
			return


func _node_by_id(plan: Dictionary, node_id: String) -> Dictionary:
	for node_value: Variant in plan["nodes"]:
		var node := node_value as Dictionary
		if str(node["id"]) == node_id:
			return node
	return {}


func _load_json_array(path: String) -> Array[Dictionary]:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var result: Array[Dictionary] = []
	if not parsed is Array:
		return result
	for value: Variant in parsed:
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result
