extends Node

const MerchantRunStateScript := preload("res://scripts/economy/merchant_run_state.gd")
const TestSuiteScript := preload("res://tests/support/test_suite.gd")

const CONTENT_FINGERPRINT := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const OTHER_FINGERPRINT := "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
const ROOT_FIELDS: Array[String] = [
	"content_fingerprint", "nodes", "pending_transaction", "schema_id", "schema_version",
]
const NODE_FIELDS: Array[String] = [
	"floor_id", "floor_index", "inventory", "merchant_id", "node_id", "runtime",
	"service", "transactions", "visibility",
]
const TRANSACTION_FIELDS: Array[String] = [
	"amount", "cost_kind", "economy_revision", "inventory_revision", "kind", "offer_id",
	"reward_id", "sequence", "service_id", "transaction_id",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_configuration_and_canonical_snapshot(suite)
	_test_node_upsert_order_identity_and_copy_isolation(suite)
	_test_transaction_fact_sequence_and_global_identity(suite)
	_test_rejected_mutations_are_atomic(suite)
	_test_snapshot_restore_is_strict_and_atomic(suite)
	suite.finish(get_tree())


func _test_configuration_and_canonical_snapshot(suite) -> void:
	var state = MerchantRunStateScript.new()
	suite.assert_equal(state.snapshot(), {}, "unconfigured state has no serializable snapshot")
	var configured: Dictionary = state.configure(CONTENT_FINGERPRINT)
	suite.assert_true(bool(configured.get("ok", false)), "valid fingerprint configures merchant state")
	var expected := {
		"schema_id": "planewalker.merchant_state",
		"schema_version": 1,
		"content_fingerprint": CONTENT_FINGERPRINT,
		"nodes": [],
		"pending_transaction": {},
	}
	suite.assert_equal(state.snapshot(), expected, "configuration creates the canonical empty snapshot")
	_assert_exact_fields(suite, state.snapshot(), ROOT_FIELDS, "root snapshot")

	var before: Dictionary = state.snapshot()
	for invalid: Variant in ["", "ABCDEF" + CONTENT_FINGERPRINT.substr(6), CONTENT_FINGERPRINT.substr(1), 7]:
		var rejected: Dictionary = state.configure(invalid)
		suite.assert_true(not bool(rejected.get("ok", false)), "invalid fingerprint is rejected")
		suite.assert_equal(state.snapshot(), before, "failed configure preserves prior state")


func _test_node_upsert_order_identity_and_copy_isolation(suite) -> void:
	var state = _configured_state()
	var floor_two := _node("floor_void_forest", 1, "layer_03_b", "merchant_chronomancer")
	var floor_one_b := _node("floor_ruins_of_remnant", 0, "layer_04_b", "merchant_wayfarer")
	var floor_one_a := _node("floor_ruins_of_remnant", 0, "layer_04_a", "merchant_wayfarer")
	suite.assert_true(bool(state.upsert_node(floor_two).get("ok", false)), "later floor node inserts")
	suite.assert_true(bool(state.upsert_node(floor_one_b).get("ok", false)), "later node ID inserts")
	suite.assert_true(bool(state.upsert_node(floor_one_a).get("ok", false)), "earlier node ID inserts")

	var nodes := state.snapshot()["nodes"] as Array
	suite.assert_equal(nodes.size(), 3, "three unique nodes are stored")
	suite.assert_equal(
		_node_keys(nodes),
		[
			"floor_ruins_of_remnant:layer_04_a",
			"floor_ruins_of_remnant:layer_04_b",
			"floor_void_forest:layer_03_b",
		],
		"nodes sort by floor index then node ID"
	)
	for node_value: Variant in nodes:
		_assert_exact_fields(suite, node_value as Dictionary, NODE_FIELDS, "node snapshot")

	floor_one_a["inventory"]["revision"] = 999
	suite.assert_equal(
		state.node_state("floor_ruins_of_remnant:layer_04_a")["inventory"]["revision"],
		1,
		"upsert deep-copies caller state"
	)
	var exposed: Dictionary = state.node_state("floor_ruins_of_remnant:layer_04_a")
	exposed["visibility"]["revealed"] = false
	suite.assert_equal(
		state.node_state("floor_ruins_of_remnant:layer_04_a")["visibility"]["revealed"],
		true,
		"node_state returns a deep copy"
	)
	suite.assert_equal(state.node_state("floor_ruins_of_remnant-layer_04_a"), {}, "noncanonical key misses")

	var replacement := _node("floor_ruins_of_remnant", 0, "layer_04_a", "merchant_wayfarer")
	replacement["runtime"] = {"completed_transaction_ids": ["legacy"]}
	suite.assert_true(bool(state.upsert_node(replacement).get("ok", false)), "same node key replaces state")
	suite.assert_equal(state.snapshot()["nodes"].size(), 3, "upsert does not duplicate a node")
	suite.assert_equal(
		state.node_state("floor_ruins_of_remnant:layer_04_a")["runtime"],
		{"completed_transaction_ids": ["legacy"]},
		"replacement stores the new canonical domain state"
	)


func _test_transaction_fact_sequence_and_global_identity(suite) -> void:
	var state = _configured_state()
	suite.assert_true(bool(state.upsert_node(
		_node("floor_ruins_of_remnant", 0, "layer_04_a", "merchant_wayfarer")
	).get("ok", false)), "first transaction node inserts")
	suite.assert_true(bool(state.upsert_node(
		_node("floor_void_forest", 1, "layer_03_b", "merchant_chronomancer")
	).get("ok", false)), "second transaction node inserts")

	var purchase := _transaction(
		1,
		"tx_purchase_001",
		"purchase",
		"merchant_wayfarer:layer_04_a:r00:o00:item_compass",
		"item_compass",
		"",
		"gold",
		80,
		1,
		2
	)
	var recorded: Dictionary = state.record_transaction(
		"floor_ruins_of_remnant:layer_04_a", purchase
	)
	suite.assert_true(bool(recorded.get("ok", false)), "purchase fact records")
	_assert_exact_fields(
		suite,
		state.node_state("floor_ruins_of_remnant:layer_04_a")["transactions"][0],
		TRANSACTION_FIELDS,
		"purchase transaction"
	)

	var reroll := _transaction(
		2, "tx_reroll_001", "reroll", "", "", "", "gold", 30, 2, 3
	)
	suite.assert_true(bool(state.record_transaction(
		"floor_ruins_of_remnant:layer_04_a", reroll
	).get("ok", false)), "reroll fact records with the next global sequence")
	var service := _transaction(
		3, "tx_service_001", "service", "", "", "heal", "gold", 40, 3, 3
	)
	suite.assert_true(bool(state.record_transaction(
		"floor_void_forest:layer_03_b", service
	).get("ok", false)), "service fact records across another node")
	suite.assert_equal(
		state.node_state("floor_void_forest:layer_03_b")["transactions"][0]["sequence"],
		3,
		"transaction sequence is global across merchant nodes"
	)

	var duplicate := _transaction(
		4, "tx_purchase_001", "service", "", "", "route_reveal", "gold", 20, 4, 3
	)
	var before_duplicate: Dictionary = state.snapshot()
	var duplicate_result: Dictionary = state.record_transaction(
		"floor_void_forest:layer_03_b", duplicate
	)
	suite.assert_equal(duplicate_result.get("code"), &"DUPLICATE_TRANSACTION", "transaction ID is globally unique")
	suite.assert_equal(state.snapshot(), before_duplicate, "duplicate transaction rejection is atomic")

	var stale_sequence := _transaction(
		5, "tx_bad_sequence", "service", "", "", "heal", "gold", 20, 5, 3
	)
	var stale_result: Dictionary = state.record_transaction(
		"floor_void_forest:layer_03_b", stale_sequence
	)
	suite.assert_equal(stale_result.get("code"), &"SEQUENCE_INVALID", "sequence gaps fail closed")
	suite.assert_equal(state.snapshot(), before_duplicate, "sequence rejection is atomic")

	var erased_history: Dictionary = state.node_state("floor_ruins_of_remnant:layer_04_a")
	erased_history["transactions"] = []
	var erase_result: Dictionary = state.upsert_node(erased_history)
	suite.assert_equal(erase_result.get("code"), &"TRANSACTION_HISTORY_INVALID", "upsert cannot erase facts")
	suite.assert_equal(state.snapshot(), before_duplicate, "history erasure rejection is atomic")
	var rewritten_history: Dictionary = state.node_state("floor_ruins_of_remnant:layer_04_a")
	rewritten_history["transactions"][0]["amount"] = 1
	var rewrite_result: Dictionary = state.upsert_node(rewritten_history)
	suite.assert_equal(rewrite_result.get("code"), &"TRANSACTION_HISTORY_INVALID", "upsert cannot rewrite facts")
	suite.assert_equal(state.snapshot(), before_duplicate, "history rewrite rejection is atomic")


func _test_rejected_mutations_are_atomic(suite) -> void:
	var state = _configured_state()
	var valid := _node("floor_ruins_of_remnant", 0, "layer_04_a", "merchant_wayfarer")
	suite.assert_true(bool(state.upsert_node(valid).get("ok", false)), "atomic fixture node inserts")
	var before: Dictionary = state.snapshot()

	var cases: Array[Dictionary] = []
	var extra_field := valid.duplicate(true)
	extra_field["unexpected"] = true
	cases.append(extra_field)
	var mismatched_floor := valid.duplicate(true)
	mismatched_floor["floor_index"] = 4
	cases.append(mismatched_floor)
	var invalid_index := valid.duplicate(true)
	invalid_index["floor_index"] = 5
	cases.append(invalid_index)
	var pending := valid.duplicate(true)
	pending["runtime"] = []
	cases.append(pending)
	for candidate: Dictionary in cases:
		suite.assert_true(not bool(state.upsert_node(candidate).get("ok", false)), "invalid node is rejected")
		suite.assert_equal(state.snapshot(), before, "rejected node leaves state byte-identical")
	var merchant_drift := valid.duplicate(true)
	merchant_drift["merchant_id"] = "merchant_chronomancer"
	suite.assert_equal(
		state.upsert_node(merchant_drift).get("code"),
		&"NODE_IDENTITY_MISMATCH",
		"existing node cannot change merchant identity"
	)
	suite.assert_equal(state.snapshot(), before, "merchant identity rejection is atomic")
	var floor_alias := _node("floor_void_forest", 0, "layer_04_b", "merchant_chronomancer")
	suite.assert_true(not bool(state.upsert_node(floor_alias).get("ok", false)), "one floor index cannot name two floors")
	suite.assert_equal(state.snapshot(), before, "floor identity rejection is atomic")

	var invalid_facts: Array[Dictionary] = []
	var extra_transaction := _transaction(
		1, "tx_extra", "purchase", "offer_a", "item_a", "", "gold", 10, 1, 2
	)
	extra_transaction["unexpected"] = true
	invalid_facts.append(extra_transaction)
	invalid_facts.append(_transaction(
		1, "tx_purchase_missing_offer", "purchase", "", "item_a", "", "gold", 10, 1, 2
	))
	invalid_facts.append(_transaction(
		1, "tx_reroll_payload", "reroll", "offer_a", "", "", "gold", 10, 1, 2
	))
	invalid_facts.append(_transaction(
		1, "tx_service_missing", "service", "", "", "", "gold", 10, 1, 2
	))
	invalid_facts.append(_transaction(
		1, "tx_amount", "service", "", "", "heal", "gold", -1, 1, 2
	))
	for fact: Dictionary in invalid_facts:
		suite.assert_true(not bool(state.record_transaction(
			"floor_ruins_of_remnant:layer_04_a", fact
		).get("ok", false)), "invalid transaction fact is rejected")
		suite.assert_equal(state.snapshot(), before, "rejected transaction leaves state byte-identical")
	suite.assert_equal(
		state.record_transaction("floor_ruins_of_remnant:missing", _transaction(
			1, "tx_missing_node", "reroll", "", "", "", "gold", 1, 1, 1
		)).get("code"),
		&"NODE_NOT_FOUND",
		"unknown node cannot receive facts"
	)


func _test_snapshot_restore_is_strict_and_atomic(suite) -> void:
	var source = _configured_state()
	var second := _node("floor_void_forest", 1, "layer_03_b", "merchant_chronomancer")
	var first := _node("floor_ruins_of_remnant", 0, "layer_04_a", "merchant_wayfarer")
	suite.assert_true(bool(source.upsert_node(second).get("ok", false)), "restore source second node inserts")
	suite.assert_true(bool(source.upsert_node(first).get("ok", false)), "restore source first node inserts")
	suite.assert_true(bool(source.record_transaction(
		"floor_ruins_of_remnant:layer_04_a",
		_transaction(1, "tx_restore_purchase", "purchase", "offer_a", "item_a", "", "gold", 50, 1, 2)
	).get("ok", false)), "restore source transaction records")
	var saved: Dictionary = source.snapshot()

	var restored = _configured_state()
	suite.assert_true(restored.can_restore_snapshot(saved), "canonical snapshot validates")
	suite.assert_true(restored.restore_snapshot(saved), "canonical snapshot restores")
	suite.assert_equal(restored.snapshot(), saved, "restore round-trips byte-identically")

	var exposed: Dictionary = saved.duplicate(true)
	exposed["nodes"][0]["inventory"]["revision"] = 999
	suite.assert_true(restored.snapshot() != exposed, "restored state is isolated from caller mutation")
	var before: Dictionary = restored.snapshot()

	var corruptions: Array[Dictionary] = []
	var wrong_fingerprint := before.duplicate(true)
	wrong_fingerprint["content_fingerprint"] = OTHER_FINGERPRINT
	corruptions.append(wrong_fingerprint)
	var pending := before.duplicate(true)
	pending["pending_transaction"] = {"transaction_id": "tx_busy"}
	corruptions.append(pending)
	var reordered := before.duplicate(true)
	reordered["nodes"].reverse()
	corruptions.append(reordered)
	var duplicate_node := before.duplicate(true)
	duplicate_node["nodes"].append(duplicate_node["nodes"][0].duplicate(true))
	corruptions.append(duplicate_node)
	var sequence_gap := before.duplicate(true)
	sequence_gap["nodes"][0]["transactions"][0]["sequence"] = 2
	corruptions.append(sequence_gap)
	var unknown_root := before.duplicate(true)
	unknown_root["unknown"] = true
	corruptions.append(unknown_root)
	for corrupt: Dictionary in corruptions:
		suite.assert_true(not restored.can_restore_snapshot(corrupt), "corrupt snapshot fails validation")
		suite.assert_true(not restored.restore_snapshot(corrupt), "corrupt snapshot fails restore")
		suite.assert_equal(restored.snapshot(), before, "failed restore is atomic")

	var wrong_authority = MerchantRunStateScript.new()
	suite.assert_true(bool(wrong_authority.configure(OTHER_FINGERPRINT).get("ok", false)), "other authority configures")
	suite.assert_true(not wrong_authority.can_restore_snapshot(before), "content drift fails closed")


func _configured_state():
	var state = MerchantRunStateScript.new()
	var result: Dictionary = state.configure(CONTENT_FINGERPRINT)
	if not bool(result.get("ok", false)):
		push_error("MerchantRunState fixture failed: %s" % str(result))
	return state


func _node(floor_id: String, floor_index: int, node_id: String, merchant_id: String) -> Dictionary:
	return {
		"floor_id": floor_id,
		"floor_index": floor_index,
		"node_id": node_id,
		"merchant_id": merchant_id,
		"inventory": {"revision": 1, "offers": []},
		"runtime": {"completed_transaction_ids": []},
		"service": {"completed_transaction_ids": []},
		"visibility": {"revealed": true},
		"transactions": [],
	}


func _transaction(
	sequence: int,
	transaction_id: String,
	kind: String,
	offer_id: String,
	reward_id: String,
	service_id: String,
	cost_kind: String,
	amount: int,
	economy_revision: int,
	inventory_revision: int
) -> Dictionary:
	return {
		"sequence": sequence,
		"transaction_id": transaction_id,
		"kind": kind,
		"offer_id": offer_id,
		"reward_id": reward_id,
		"service_id": service_id,
		"cost_kind": cost_kind,
		"amount": amount,
		"economy_revision": economy_revision,
		"inventory_revision": inventory_revision,
	}


func _node_keys(nodes: Array) -> Array[String]:
	var keys: Array[String] = []
	for node_value: Variant in nodes:
		var node := node_value as Dictionary
		keys.append("%s:%s" % [node["floor_id"], node["node_id"]])
	return keys


func _assert_exact_fields(
	suite,
	value: Dictionary,
	expected_fields: Array[String],
	label: String
) -> void:
	var actual: Array[String] = []
	for key: Variant in value.keys():
		actual.append(str(key))
	actual.sort()
	var expected := expected_fields.duplicate()
	expected.sort()
	suite.assert_equal(actual, expected, "%s has exact fields" % label)
