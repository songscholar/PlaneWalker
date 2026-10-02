class_name MerchantRuntime
extends RefCounted

const SNAPSHOT_SCHEMA_ID := "planewalker.merchant_runtime"
const SNAPSHOT_SCHEMA_VERSION := 1
const SNAPSHOT_FIELDS: Array[String] = [
	"completed_transaction_ids", "schema_id", "schema_version",
]

const REQUIRED_ECONOMY_METHODS: Array[StringName] = [
	&"snapshot", &"prepare_transaction", &"commit_transaction", &"rollback_transaction",
]
const REQUIRED_INVENTORY_METHODS: Array[StringName] = [
	&"snapshot",
	&"prepare_purchase", &"commit_purchase", &"rollback_purchase",
	&"prepare_reroll", &"commit_reroll", &"rollback_reroll",
]
const REQUIRED_REWARD_METHODS: Array[StringName] = [
	&"prepare", &"commit", &"rollback",
]
const REQUIRED_PLAYER_METHODS: Array[StringName] = [
	&"reward_effect_snapshot",
	&"restore_reward_effect_snapshot",
	&"reward_effect_apply_operation",
	&"reward_effect_begin_publication",
	&"reward_effect_publication_can_commit",
	&"reward_effect_commit_publication",
	&"reward_effect_rollback_publication",
]
const REQUIRED_SERVICE_METHODS: Array[StringName] = [
	&"prepare_service", &"commit_service", &"rollback_service", &"snapshot",
]

var _economy: Object
var _inventory: Object
var _reward_runtime: Object
var _player: Object
var _service_authority: Object
var _state_sink: Callable
var _completed_transaction_ids: Dictionary = {}


func configure(
	economy: Object,
	inventory: Object,
	reward_runtime: Object,
	player: Object,
	service_authority: Object = null,
	state_sink: Callable = Callable()
) -> bool:
	if (
		not _has_methods(economy, REQUIRED_ECONOMY_METHODS)
		or not _has_methods(inventory, REQUIRED_INVENTORY_METHODS)
		or not _has_methods(reward_runtime, REQUIRED_REWARD_METHODS)
		or player == null
		or not is_instance_valid(player)
		or not _has_methods(player, REQUIRED_PLAYER_METHODS)
		or (
			service_authority != null
			and not _has_methods(service_authority, REQUIRED_SERVICE_METHODS)
		)
	):
		return false
	_economy = economy
	_inventory = inventory
	_reward_runtime = reward_runtime
	_player = player
	_service_authority = service_authority
	_state_sink = state_sink
	_completed_transaction_ids.clear()
	return true


func purchase_reward(
	transaction_id: String,
	offer_id: String,
	expected_inventory_revision: int,
	expected_economy_revision: int
) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if transaction_id.is_empty() or offer_id.is_empty():
		return _failure(&"INVALID_ARGUMENT")
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"ALREADY_CONSUMED", {"transaction_id": transaction_id})

	var inventory_before_value: Variant = _inventory.call("snapshot")
	if not inventory_before_value is Dictionary:
		return _failure(&"INVENTORY_SNAPSHOT_INVALID")
	var inventory_before := (inventory_before_value as Dictionary).duplicate(true)
	var inventory_prepared_value: Variant = _inventory.call(
		"prepare_purchase",
		transaction_id,
		inventory_before.duplicate(true),
		offer_id,
		expected_inventory_revision
	)
	var inventory_prepared := _dictionary(inventory_prepared_value)
	if not _result_ok(inventory_prepared):
		return _forward_failure(inventory_prepared, &"INVENTORY_PREPARE_FAILED")
	var inventory_ticket := _nested_dictionary(inventory_prepared, "ticket")
	var offer := _nested_dictionary(inventory_ticket, "offer")
	var definition := _nested_dictionary(offer, "definition")
	var price_value: Variant = offer.get("price")
	if (
		inventory_ticket.is_empty()
		or definition.is_empty()
		or typeof(price_value) != TYPE_INT
		or int(price_value) < 0
	):
		return _rollback_prepared_failure(
			&"INVENTORY_TICKET_INVALID", inventory_ticket, {}, {}
		)

	var economy_prepared_value: Variant = _economy.call(
		"prepare_transaction",
		transaction_id,
		-int(price_value),
		expected_economy_revision,
		{
			"operation": "gold_purchase",
			"offer_id": offer_id,
			"definition_id": str(definition.get("id", "")),
		}
	)
	var economy_prepared := _dictionary(economy_prepared_value)
	if not _result_ok(economy_prepared):
		var inventory_rollback := _rollback_inventory(inventory_ticket)
		if not inventory_rollback:
			return _integrity_failure("economy_prepare", {"inventory_rollback": false})
		return _forward_failure(economy_prepared, &"ECONOMY_PREPARE_FAILED")
	var economy_ticket := _nested_dictionary(economy_prepared, "ticket")

	var player_snapshot_value: Variant = _player.call("reward_effect_snapshot")
	if not player_snapshot_value is Dictionary or (player_snapshot_value as Dictionary).is_empty():
		return _rollback_prepared_failure(
			&"PLAYER_SNAPSHOT_INVALID", inventory_ticket, economy_ticket, {}
		)
	var reward_prepared := _dictionary(_reward_runtime.call(
		"prepare", definition.duplicate(true), (player_snapshot_value as Dictionary).duplicate(true)
	))
	if not _result_ok(reward_prepared):
		return _rollback_prepared_failure(
			&"REWARD_PREPARE_FAILED", inventory_ticket, economy_ticket, {}
		)
	var reward_plan := _nested_dictionary(reward_prepared, "plan")
	if not bool(_player.call("reward_effect_begin_publication")):
		return _rollback_prepared_failure(
			&"PUBLICATION_BEGIN_FAILED", inventory_ticket, economy_ticket, {}
		)
	var reward_committed := _dictionary(_reward_runtime.call(
		"commit", reward_plan.duplicate(true), _player
	))
	if not _result_ok(reward_committed):
		var publication_rollback_ok := _rollback_publication()
		var economy_rollback_ok := _rollback_economy(economy_ticket)
		var inventory_rollback_ok := _rollback_inventory(inventory_ticket)
		if str(reward_committed.get("code", "")) == "ROLLBACK_FAILED":
			return _integrity_failure("reward_commit", {
				"reward_rollback": false,
				"publication_rollback": publication_rollback_ok,
				"economy_rollback": economy_rollback_ok,
				"inventory_rollback": inventory_rollback_ok,
			})
		if not publication_rollback_ok or not economy_rollback_ok or not inventory_rollback_ok:
			return _integrity_failure("reward_commit", {
				"reward_rollback": true,
				"publication_rollback": publication_rollback_ok,
				"economy_rollback": economy_rollback_ok,
				"inventory_rollback": inventory_rollback_ok,
			})
		return _failure(&"REWARD_COMMIT_FAILED")
	var reward_receipt := _nested_dictionary(reward_committed, "receipt")

	var economy_committed := _dictionary(_economy.call(
		"commit_transaction", economy_ticket.duplicate(true)
	))
	if not _result_ok(economy_committed):
		var reward_rollback_ok := _rollback_reward(reward_receipt)
		var economy_rollback_ok := _rollback_economy(economy_ticket)
		var inventory_rollback_ok := _rollback_inventory(inventory_ticket)
		var publication_rollback_ok := _rollback_publication()
		if not reward_rollback_ok or not economy_rollback_ok or not inventory_rollback_ok or not publication_rollback_ok:
			return _integrity_failure("economy_commit", {
				"reward_rollback": reward_rollback_ok,
				"economy_rollback": economy_rollback_ok,
				"inventory_rollback": inventory_rollback_ok,
				"publication_rollback": publication_rollback_ok,
			})
		return _failure(&"ECONOMY_COMMIT_FAILED")
	var economy_receipt := _nested_dictionary(economy_committed, "receipt")

	var inventory_committed := _dictionary(_inventory.call(
		"commit_purchase", inventory_ticket.duplicate(true)
	))
	if not _result_ok(inventory_committed):
		var economy_rollback_ok := _rollback_economy(economy_receipt)
		var reward_rollback_ok := _rollback_reward(reward_receipt)
		var inventory_rollback_ok := _rollback_inventory(inventory_ticket)
		var publication_rollback_ok := _rollback_publication()
		if not economy_rollback_ok or not reward_rollback_ok or not inventory_rollback_ok or not publication_rollback_ok:
			return _integrity_failure("inventory_commit", {
				"economy_rollback": economy_rollback_ok,
				"reward_rollback": reward_rollback_ok,
				"inventory_rollback": inventory_rollback_ok,
				"publication_rollback": publication_rollback_ok,
			})
		return _failure(&"INVENTORY_COMMIT_FAILED")
	var inventory_receipt := _nested_dictionary(inventory_committed, "receipt")
	if not bool(_player.call("reward_effect_publication_can_commit")):
		return _rollback_purchase_after_commit(
			&"PUBLICATION_PREFLIGHT_FAILED",
			inventory_receipt,
			economy_receipt,
			reward_receipt
		)
	_completed_transaction_ids[transaction_id] = true
	var result := {
		"ok": true,
		"code": &"OK",
		"kind": "purchase",
		"transaction_id": transaction_id,
		"offer_id": offer_id,
		"price": int(price_value),
		"economy_receipt": economy_receipt.duplicate(true),
		"inventory_receipt": inventory_receipt.duplicate(true),
		"reward_receipt": reward_receipt.duplicate(true),
	}
	if not _commit_state_sink(result):
		_completed_transaction_ids.erase(transaction_id)
		return _rollback_purchase_after_commit(
			&"STATE_COMMIT_FAILED",
			inventory_receipt,
			economy_receipt,
			reward_receipt
		)
	if not bool(_player.call("reward_effect_commit_publication")):
		return _integrity_failure("publication_commit", {"publication_commit": false})
	return result


func reroll(
	transaction_id: String,
	expected_inventory_revision: int,
	expected_economy_revision: int
) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if transaction_id.is_empty():
		return _failure(&"INVALID_ARGUMENT")
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"ALREADY_CONSUMED", {"transaction_id": transaction_id})

	var inventory_before_value: Variant = _inventory.call("snapshot")
	if not inventory_before_value is Dictionary:
		return _failure(&"INVENTORY_SNAPSHOT_INVALID")
	var inventory_before := (inventory_before_value as Dictionary).duplicate(true)
	var inventory_prepared := _dictionary(_inventory.call(
		"prepare_reroll",
		transaction_id,
		inventory_before.duplicate(true),
		expected_inventory_revision
	))
	if not _result_ok(inventory_prepared):
		return _forward_failure(inventory_prepared, &"INVENTORY_PREPARE_FAILED")
	var inventory_ticket := _nested_dictionary(inventory_prepared, "ticket")
	var price_value: Variant = inventory_ticket.get("price")
	if inventory_ticket.is_empty() or typeof(price_value) != TYPE_INT or int(price_value) <= 0:
		var invalid_ticket_rollback := _rollback_inventory_reroll(inventory_ticket)
		if not invalid_ticket_rollback:
			return _integrity_failure("reroll_ticket", {"inventory_rollback": false})
		return _failure(&"INVENTORY_TICKET_INVALID")

	var economy_prepared := _dictionary(_economy.call(
		"prepare_transaction",
		transaction_id,
		-int(price_value),
		expected_economy_revision,
		{
			"operation": "gold_reroll",
			"merchant_id": str(inventory_before.get("merchant_id", "")),
			"node_id": str(inventory_before.get("node_id", "")),
			"reroll_count": int(inventory_before.get("reroll_count", 0)),
		}
	))
	if not _result_ok(economy_prepared):
		if not _rollback_inventory_reroll(inventory_ticket):
			return _integrity_failure("reroll_economy_prepare", {"inventory_rollback": false})
		return _forward_failure(economy_prepared, &"ECONOMY_PREPARE_FAILED")
	var economy_ticket := _nested_dictionary(economy_prepared, "ticket")

	var economy_committed := _dictionary(_economy.call(
		"commit_transaction", economy_ticket.duplicate(true)
	))
	if not _result_ok(economy_committed):
		var economy_rollback_ok := _rollback_economy(economy_ticket)
		var inventory_rollback_ok := _rollback_inventory_reroll(inventory_ticket)
		if not economy_rollback_ok or not inventory_rollback_ok:
			return _integrity_failure("reroll_economy_commit", {
				"economy_rollback": economy_rollback_ok,
				"inventory_rollback": inventory_rollback_ok,
			})
		return _failure(&"ECONOMY_COMMIT_FAILED")
	var economy_receipt := _nested_dictionary(economy_committed, "receipt")

	var inventory_committed := _dictionary(_inventory.call(
		"commit_reroll", inventory_ticket.duplicate(true)
	))
	if not _result_ok(inventory_committed):
		var economy_rollback_ok := _rollback_economy(economy_receipt)
		var inventory_rollback_ok := _rollback_inventory_reroll(inventory_ticket)
		if not economy_rollback_ok or not inventory_rollback_ok:
			return _integrity_failure("reroll_inventory_commit", {
				"economy_rollback": economy_rollback_ok,
				"inventory_rollback": inventory_rollback_ok,
			})
		return _failure(&"INVENTORY_COMMIT_FAILED")
	var inventory_receipt := _nested_dictionary(inventory_committed, "receipt")

	_completed_transaction_ids[transaction_id] = true
	var result := {
		"ok": true,
		"code": &"OK",
		"kind": "reroll",
		"transaction_id": transaction_id,
		"price": int(price_value),
		"economy_receipt": economy_receipt.duplicate(true),
		"inventory_receipt": inventory_receipt.duplicate(true),
	}
	if not _commit_state_sink(result):
		_completed_transaction_ids.erase(transaction_id)
		var inventory_rollback_ok := _rollback_inventory_reroll(inventory_receipt)
		var economy_rollback_ok := _rollback_economy(economy_receipt)
		if not inventory_rollback_ok or not economy_rollback_ok:
			return _integrity_failure("reroll_state_commit", {
				"inventory_rollback": inventory_rollback_ok,
				"economy_rollback": economy_rollback_ok,
			})
		return _failure(&"STATE_COMMIT_FAILED")
	return result


func execute_service(
	transaction_id: String,
	service_id: StringName,
	target_id: String,
	expected_economy_revision: int
) -> Dictionary:
	if not _is_configured() or not _has_methods(_service_authority, REQUIRED_SERVICE_METHODS):
		return _failure(&"SERVICE_AUTHORITY_NOT_CONFIGURED")
	if transaction_id.is_empty() or str(service_id).is_empty():
		return _failure(&"INVALID_ARGUMENT")
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"ALREADY_CONSUMED", {"transaction_id": transaction_id})
	var service_prepared := _dictionary(_service_authority.call(
		"prepare_service", transaction_id, service_id, target_id
	))
	if not _result_ok(service_prepared):
		return _forward_failure(service_prepared, &"SERVICE_PREPARE_FAILED")
	var service_ticket := _nested_dictionary(service_prepared, "ticket")
	var cost_kind := str(service_ticket.get("cost_kind", ""))
	var amount_value: Variant = service_ticket.get(
		"amount", service_ticket.get("price")
	)
	var economy_delta_value: Variant = service_ticket.get(
		"economy_delta",
		-int(amount_value) if typeof(amount_value) == TYPE_INT and cost_kind == "gold" else 0
	)
	if (
		service_ticket.is_empty()
		or cost_kind not in ["gold", "health", "reward"]
		or typeof(amount_value) != TYPE_INT
		or int(amount_value) <= 0
		or typeof(economy_delta_value) != TYPE_INT
		or (cost_kind == "gold" and int(economy_delta_value) != -int(amount_value))
		or (cost_kind == "health" and int(economy_delta_value) != 0)
		or (cost_kind == "reward" and int(economy_delta_value) != int(amount_value))
	):
		var service_rollback_ok := _rollback_service(service_ticket)
		if not service_rollback_ok:
			return _integrity_failure("service_ticket", {"service_rollback": false})
		return _failure(&"SERVICE_TICKET_INVALID")
	var amount := int(amount_value)
	var economy_delta := int(economy_delta_value)
	var economy_ticket: Dictionary = {}
	if economy_delta != 0:
		var economy_prepared := _dictionary(_economy.call(
			"prepare_transaction",
			transaction_id,
			economy_delta,
			expected_economy_revision,
			{
				"operation": "gold_delta" if economy_delta > 0 else "gold_service",
				"service_id": str(service_id),
				"target_id": target_id,
				"cost_kind": cost_kind,
			}
		))
		if not _result_ok(economy_prepared):
			if not _rollback_service(service_ticket):
				return _integrity_failure("service_economy_prepare", {"service_rollback": false})
			return _forward_failure(economy_prepared, &"ECONOMY_PREPARE_FAILED")
		economy_ticket = _nested_dictionary(economy_prepared, "ticket")
	if not bool(_player.call("reward_effect_begin_publication")):
		var economy_rollback_ok := economy_ticket.is_empty() or _rollback_economy(economy_ticket)
		var service_rollback_ok := _rollback_service(service_ticket)
		if not economy_rollback_ok or not service_rollback_ok:
			return _integrity_failure("service_publication_begin", {
				"economy_rollback": economy_rollback_ok,
				"service_rollback": service_rollback_ok,
			})
		return _failure(&"PUBLICATION_BEGIN_FAILED")
	var service_committed := _dictionary(_service_authority.call(
		"commit_service", service_ticket.duplicate(true)
	))
	if not _result_ok(service_committed):
		var economy_rollback_ok := economy_ticket.is_empty() or _rollback_economy(economy_ticket)
		var service_rollback_ok := _rollback_service(service_ticket)
		var publication_rollback_ok := _rollback_publication()
		if (
			str(service_committed.get("code", "")) in ["INTEGRITY_FAILURE", "REWARD_ROLLBACK_FAILED"]
			or not economy_rollback_ok
			or not service_rollback_ok
			or not publication_rollback_ok
		):
			return _integrity_failure("service_commit", {
				"economy_rollback": economy_rollback_ok,
				"service_rollback": service_rollback_ok,
				"publication_rollback": publication_rollback_ok,
				"failure_code": str(service_committed.get("code", "")),
			})
		return _failure(&"SERVICE_COMMIT_FAILED")
	var service_receipt := _nested_dictionary(service_committed, "receipt")
	var economy_receipt: Dictionary = {}
	if not economy_ticket.is_empty():
		var economy_committed := _dictionary(_economy.call(
			"commit_transaction", economy_ticket.duplicate(true)
		))
		if not _result_ok(economy_committed):
			var service_rollback_ok := _rollback_service(service_receipt)
			var economy_rollback_ok := _rollback_economy(economy_ticket)
			var publication_rollback_ok := _rollback_publication()
			if not service_rollback_ok or not economy_rollback_ok or not publication_rollback_ok:
				return _integrity_failure("service_economy_commit", {
					"service_rollback": service_rollback_ok,
					"economy_rollback": economy_rollback_ok,
					"publication_rollback": publication_rollback_ok,
				})
			return _failure(&"ECONOMY_COMMIT_FAILED")
		economy_receipt = _nested_dictionary(economy_committed, "receipt")
	if not bool(_player.call("reward_effect_publication_can_commit")):
		var economy_rollback_ok := economy_receipt.is_empty() or _rollback_economy(economy_receipt)
		var service_rollback_ok := _rollback_service(service_receipt)
		var publication_rollback_ok := _rollback_publication()
		if not economy_rollback_ok or not service_rollback_ok or not publication_rollback_ok:
			return _integrity_failure("service_publication_preflight", {
				"economy_rollback": economy_rollback_ok,
				"service_rollback": service_rollback_ok,
				"publication_rollback": publication_rollback_ok,
			})
		return _failure(&"PUBLICATION_PREFLIGHT_FAILED")
	_completed_transaction_ids[transaction_id] = true
	var result := {
		"ok": true,
		"code": &"OK",
		"kind": "service",
		"transaction_id": transaction_id,
		"service_id": str(service_id),
		"target_id": target_id,
		"cost_kind": cost_kind,
		"amount": amount,
		"price": amount,
		"economy_delta": economy_delta,
		"offer_id": str(service_ticket.get("offer_id", "")),
		"reward_id": str(service_ticket.get("reward_id", "")),
		"economy_receipt": economy_receipt.duplicate(true),
		"service_receipt": service_receipt.duplicate(true),
	}
	if not _commit_state_sink(result):
		_completed_transaction_ids.erase(transaction_id)
		var economy_rollback_ok := economy_receipt.is_empty() or _rollback_economy(economy_receipt)
		var service_rollback_ok := _rollback_service(service_receipt)
		var publication_rollback_ok := _rollback_publication()
		if not economy_rollback_ok or not service_rollback_ok or not publication_rollback_ok:
			return _integrity_failure("service_state_commit", {
				"economy_rollback": economy_rollback_ok,
				"service_rollback": service_rollback_ok,
				"publication_rollback": publication_rollback_ok,
			})
		return _failure(&"STATE_COMMIT_FAILED")
	if not bool(_player.call("reward_effect_commit_publication")):
		return _integrity_failure("service_publication_commit", {"publication_commit": false})
	return result


func rollback_committed_transaction(receipt: Dictionary) -> Dictionary:
	if not _is_configured():
		return _failure(&"NOT_CONFIGURED")
	if not bool(receipt.get("ok", false)):
		return _failure(&"INVALID_ARGUMENT", {"field": "receipt"})
	var transaction_id := str(receipt.get("transaction_id", ""))
	var kind := str(receipt.get("kind", ""))
	if transaction_id.is_empty() or not _completed_transaction_ids.has(transaction_id):
		return _failure(&"TRANSACTION_NOT_FOUND", {"transaction_id": transaction_id})
	var economy_receipt := _nested_dictionary(receipt, "economy_receipt")
	if economy_receipt.is_empty() and not (
		kind == "service"
		and str(receipt.get("cost_kind", "")) == "health"
		and int(receipt.get("economy_delta", -1)) == 0
	):
		return _failure(&"INVALID_ARGUMENT", {"field": "receipt"})
	var inventory_ok := true
	var reward_ok := true
	var service_ok := true
	match kind:
		"purchase":
			var inventory_receipt := _nested_dictionary(receipt, "inventory_receipt")
			if inventory_receipt.is_empty():
				return _failure(&"INVALID_ARGUMENT", {"field": "inventory_receipt"})
			inventory_ok = _rollback_inventory(inventory_receipt)
			var reward_receipt := _nested_dictionary(receipt, "reward_receipt")
			reward_ok = not reward_receipt.is_empty() and _rollback_reward(reward_receipt)
		"reroll":
			var inventory_receipt := _nested_dictionary(receipt, "inventory_receipt")
			if inventory_receipt.is_empty():
				return _failure(&"INVALID_ARGUMENT", {"field": "inventory_receipt"})
			inventory_ok = _rollback_inventory_reroll(inventory_receipt)
		"service":
			var service_receipt := _nested_dictionary(receipt, "service_receipt")
			if service_receipt.is_empty():
				return _failure(&"INVALID_ARGUMENT", {"field": "service_receipt"})
			service_ok = _rollback_service(service_receipt)
		_:
			return _failure(&"INVALID_ARGUMENT", {"field": "kind"})
	var economy_ok := economy_receipt.is_empty() or _rollback_economy(economy_receipt)
	if not inventory_ok or not economy_ok or not reward_ok or not service_ok:
		return _integrity_failure("composite_rollback", {
			"inventory_rollback": inventory_ok,
			"economy_rollback": economy_ok,
			"reward_rollback": reward_ok,
			"service_rollback": service_ok,
		})
	_completed_transaction_ids.erase(transaction_id)
	return {
		"ok": true,
		"code": &"ROLLED_BACK",
		"transaction_id": transaction_id,
		"kind": kind,
	}


func snapshot() -> Dictionary:
	if not _is_configured():
		return {}
	var completed_ids: Array[String] = []
	for transaction_id_value: Variant in _completed_transaction_ids.keys():
		completed_ids.append(str(transaction_id_value))
	completed_ids.sort()
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"completed_transaction_ids": completed_ids,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	return _is_configured() and not _normalize_snapshot(value).is_empty()


func restore_snapshot(value: Dictionary) -> bool:
	if not _is_configured():
		return false
	var normalized := _normalize_snapshot(value)
	if normalized.is_empty():
		return false
	var restored_ids: Dictionary = {}
	for transaction_id_value: Variant in normalized["completed_transaction_ids"]:
		restored_ids[str(transaction_id_value)] = true
	_completed_transaction_ids = restored_ids
	return snapshot() == normalized


func _rollback_prepared_failure(
	code: StringName,
	inventory_ticket: Dictionary,
	economy_ticket: Dictionary,
	reward_receipt: Dictionary
) -> Dictionary:
	var reward_ok := reward_receipt.is_empty() or _rollback_reward(reward_receipt)
	var economy_ok := economy_ticket.is_empty() or _rollback_economy(economy_ticket)
	var inventory_ok := inventory_ticket.is_empty() or _rollback_inventory(inventory_ticket)
	if not reward_ok or not economy_ok or not inventory_ok:
		return _integrity_failure("prepared_rollback", {
			"reward_rollback": reward_ok,
			"economy_rollback": economy_ok,
			"inventory_rollback": inventory_ok,
			"failure_code": str(code),
		})
	return _failure(code)


func _rollback_purchase_after_commit(
	code: StringName,
	inventory_receipt: Dictionary,
	economy_receipt: Dictionary,
	reward_receipt: Dictionary
) -> Dictionary:
	var inventory_ok := _rollback_inventory(inventory_receipt)
	var economy_ok := _rollback_economy(economy_receipt)
	var reward_ok := _rollback_reward(reward_receipt)
	var publication_ok := _rollback_publication()
	if not inventory_ok or not economy_ok or not reward_ok or not publication_ok:
		return _integrity_failure("publication_preflight", {
			"inventory_rollback": inventory_ok,
			"economy_rollback": economy_ok,
			"reward_rollback": reward_ok,
			"publication_rollback": publication_ok,
		})
	return _failure(code)


func _normalize_snapshot(value: Dictionary) -> Dictionary:
	if _sorted_keys(value) != SNAPSHOT_FIELDS:
		return {}
	if (
		typeof(value.get("schema_id")) != TYPE_STRING
		or str(value["schema_id"]) != SNAPSHOT_SCHEMA_ID
		or typeof(value.get("schema_version")) != TYPE_INT
		or int(value["schema_version"]) != SNAPSHOT_SCHEMA_VERSION
		or not value.get("completed_transaction_ids") is Array
	):
		return {}
	var normalized_ids: Array[String] = []
	var seen: Dictionary = {}
	for transaction_id_value: Variant in value["completed_transaction_ids"]:
		if typeof(transaction_id_value) != TYPE_STRING:
			return {}
		var transaction_id := str(transaction_id_value)
		if transaction_id.is_empty() or seen.has(transaction_id):
			return {}
		seen[transaction_id] = true
		normalized_ids.append(transaction_id)
	var sorted_ids := normalized_ids.duplicate()
	sorted_ids.sort()
	if normalized_ids != sorted_ids:
		return {}
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"completed_transaction_ids": normalized_ids,
	}


func _rollback_economy(value: Dictionary) -> bool:
	return _result_ok(_dictionary(_economy.call(
		"rollback_transaction", value.duplicate(true)
	)))


func _rollback_inventory(value: Dictionary) -> bool:
	return _result_ok(_dictionary(_inventory.call(
		"rollback_purchase", value.duplicate(true)
	)))


func _rollback_inventory_reroll(value: Dictionary) -> bool:
	return _result_ok(_dictionary(_inventory.call(
		"rollback_reroll", value.duplicate(true)
	)))


func _rollback_reward(value: Dictionary) -> bool:
	return _result_ok(_dictionary(_reward_runtime.call(
		"rollback", value.duplicate(true), _player
	)))


func _rollback_service(value: Dictionary) -> bool:
	return _result_ok(_dictionary(_service_authority.call(
		"rollback_service", value.duplicate(true)
	)))


func _rollback_publication() -> bool:
	return bool(_player.call("reward_effect_rollback_publication"))


func _commit_state_sink(transaction_result: Dictionary) -> bool:
	if not _state_sink.is_valid():
		return true
	var payload := {
		"transaction": transaction_result.duplicate(true),
		"economy": _dictionary(_economy.call("snapshot")),
		"inventory": _dictionary(_inventory.call("snapshot")),
		"runtime": snapshot(),
		"service": (
			_dictionary(_service_authority.call("snapshot"))
			if _has_methods(_service_authority, REQUIRED_SERVICE_METHODS)
			else {}
		),
		"visibility": (
			_dictionary(_service_authority.call("visibility_snapshot"))
			if (
				_service_authority != null
				and is_instance_valid(_service_authority)
				and _service_authority.has_method("visibility_snapshot")
			)
			else {}
		),
	}
	return bool(_state_sink.call(payload))


func _is_configured() -> bool:
	return (
		_has_methods(_economy, REQUIRED_ECONOMY_METHODS)
		and _has_methods(_inventory, REQUIRED_INVENTORY_METHODS)
		and _has_methods(_reward_runtime, REQUIRED_REWARD_METHODS)
		and _player != null
		and is_instance_valid(_player)
		and _has_methods(_player, REQUIRED_PLAYER_METHODS)
	)


func _has_methods(value: Object, methods: Array[StringName]) -> bool:
	if value == null or not is_instance_valid(value):
		return false
	for method_name: StringName in methods:
		if not value.has_method(method_name):
			return false
	return true


func _dictionary(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _sorted_keys(value: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key_value: Variant in value.keys():
		keys.append(str(key_value))
	keys.sort()
	return keys


func _nested_dictionary(value: Dictionary, field: String) -> Dictionary:
	var nested: Variant = value.get(field, {})
	return (nested as Dictionary).duplicate(true) if nested is Dictionary else {}


func _result_ok(value: Dictionary) -> bool:
	return bool(value.get("ok", false))


func _forward_failure(value: Dictionary, fallback_code: StringName) -> Dictionary:
	var code_value: Variant = value.get("code")
	return _failure(
		StringName(str(code_value)) if code_value != null else fallback_code,
		_dictionary(value.get("context", {}))
	)


func _integrity_failure(stage: String, context: Dictionary) -> Dictionary:
	var merged := context.duplicate(true)
	merged["stage"] = stage
	return _failure(&"INTEGRITY_FAILURE", merged)


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
