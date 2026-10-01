extends Node

const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	var state = RunBuildStateScript.new()
	state.reset("LAUNCH")
	for definition: Dictionary in [
		_definition("item_a", "item", "freeze_burst", {"attack_multiplier": 1.1}),
		_definition("blessing_a", "blessing", "freeze_burst", {"heal": 10.0}),
		_definition("curse_a", "curse", "rewind_echo", {"rewind_heal": 5.0}),
		_definition("talent_a", "talent", "", {"talent_pair_window_frames": 420}),
	]:
		suite.assert_true(bool(state.apply_definition(definition).get("ok", false)), "fixture definition applies")

	var exact: Dictionary = state.transaction_snapshot()
	suite.assert_true(state.can_restore_transaction_snapshot(exact), "exact build transaction snapshot validates")
	suite.assert_true(state.restore_transaction_snapshot(exact), "exact build transaction snapshot restores")

	var legacy_state = RunBuildStateScript.new()
	legacy_state.reset("LAUNCH")
	var legacy_result: Dictionary = legacy_state.apply_definition({
		"id": &"legacy_item",
		"category": &"item",
	})
	suite.assert_true(bool(legacy_result.get("ok", false)), "legacy sparse definition remains accepted")
	var legacy_snapshot: Dictionary = legacy_state.transaction_snapshot()
	suite.assert_true(
		legacy_state.can_restore_transaction_snapshot(legacy_snapshot),
		"a snapshot emitted from an accepted legacy definition remains restorable"
	)
	suite.assert_true(
		legacy_state.restore_transaction_snapshot(legacy_snapshot),
		"accepted legacy definition round-trips through the transaction snapshot"
	)

	var mutations: Array[Dictionary] = []
	var missing_history := exact.duplicate(true)
	missing_history["reward_history"].pop_back()
	mutations.append({"label": "missing history", "snapshot": missing_history})
	var forged_history_id := exact.duplicate(true)
	forged_history_id["reward_history"][0]["id"] = "forged_item"
	mutations.append({"label": "history id drift", "snapshot": forged_history_id})
	var forged_category := exact.duplicate(true)
	forged_category["reward_history"][0]["category"] = "blessing"
	mutations.append({"label": "history category drift", "snapshot": forged_category})
	var forged_archetype := exact.duplicate(true)
	forged_archetype["reward_history"][0]["archetype"] = "rift_trap"
	mutations.append({"label": "history archetype drift", "snapshot": forged_archetype})
	var malformed_effects := exact.duplicate(true)
	malformed_effects["reward_history"][0]["effects"] = []
	mutations.append({"label": "history effects type", "snapshot": malformed_effects})
	var forged_score := exact.duplicate(true)
	forged_score["archetypes"]["freeze_burst"] = 99
	mutations.append({"label": "archetype score drift", "snapshot": forged_score})
	var forged_collection := exact.duplicate(true)
	forged_collection["items"][0] = "forged_item"
	mutations.append({"label": "typed collection drift", "snapshot": forged_collection})
	var duplicate_collection := exact.duplicate(true)
	duplicate_collection["items"].append("blessing_a")
	mutations.append({"label": "cross-category duplicate", "snapshot": duplicate_collection})
	var non_finite_effect := exact.duplicate(true)
	non_finite_effect["reward_history"][0]["effects"]["attack_multiplier"] = NAN
	mutations.append({"label": "non-finite reward effect", "snapshot": non_finite_effect})

	for mutation: Dictionary in mutations:
		suite.assert_true(
			not state.can_restore_transaction_snapshot(mutation["snapshot"] as Dictionary),
			"%s is rejected" % str(mutation["label"])
		)
		suite.assert_true(
			not state.restore_transaction_snapshot(mutation["snapshot"] as Dictionary),
			"%s cannot mutate live build state" % str(mutation["label"])
		)
		suite.assert_equal(state.transaction_snapshot(), exact, "%s rejection is atomic" % str(mutation["label"]))

	suite.finish(get_tree())


func _definition(
	content_id: String,
	category: String,
	archetype: String,
	effects: Dictionary
) -> Dictionary:
	return {
		"id": content_id,
		"category": category,
		"archetype": archetype,
		"effects": effects.duplicate(true),
	}
