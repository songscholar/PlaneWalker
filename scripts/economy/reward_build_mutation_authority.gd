class_name RewardBuildMutationAuthority
extends RefCounted

const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")
const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")

const SNAPSHOT_SCHEMA_ID := "planewalker.reward_build_mutation_authority"
const SNAPSHOT_SCHEMA_VERSION := 1
const TICKET_SCHEMA_ID := "reward_build_remove_ticket_v1"
const RECEIPT_SCHEMA_ID := "reward_build_remove_receipt_v1"
const TRANSACTION_ID_PATTERN := "^[a-z0-9][a-z0-9_:-]{0,95}$"
const REMOVABLE_CATEGORIES: Array[String] = ["item", "blessing", "curse"]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"run_start_player_baseline",
	"definition_ledger",
	"completed_transaction_ids",
]
const TICKET_FIELDS: Array[String] = [
	"schema_id",
	"owner_instance_id",
	"transaction_id",
	"reward_id",
	"category",
	"before_build_snapshot",
	"after_build_snapshot",
	"before_player_snapshot",
	"after_player_snapshot",
	"before_ledger",
	"after_ledger",
	"fingerprint",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_id",
	"owner_instance_id",
	"transaction_id",
	"ticket_fingerprint",
	"before_build_snapshot",
	"after_build_snapshot",
	"before_player_snapshot",
	"after_player_snapshot",
	"before_authority_snapshot",
	"after_authority_snapshot",
	"fingerprint",
]

var _configured: bool = false
var _run_start_player_baseline: Dictionary = {}
var _definition_ledger: Array[Dictionary] = []
var _current_build_snapshot: Dictionary = {}
var _current_player_snapshot: Dictionary = {}
var _build: Object
var _player: Object
var _reward_runtime: Object
var _completed_transaction_ids: Dictionary = {}
var _pending_tickets: Dictionary = {}


func configure(
	run_start_player_baseline: Dictionary,
	definition_ledger: Array[Dictionary],
	current_build_snapshot: Dictionary,
	build_participant: Object,
	player: Object,
	reward_runtime: Object
) -> Dictionary:
	if run_start_player_baseline.is_empty() or not ReplaySafeValueScript.is_supported(run_start_player_baseline):
		return _failure(&"BASELINE_INVALID")
	if not _valid_build_participant(build_participant):
		return _failure(&"BUILD_PARTICIPANT_INVALID")
	if not _valid_player(player):
		return _failure(&"PLAYER_INVALID")
	if not _valid_reward_runtime(reward_runtime):
		return _failure(&"REWARD_RUNTIME_INVALID")
	var ledger_result := _normalize_ledger(definition_ledger)
	if not bool(ledger_result.get("ok", false)):
		return ledger_result
	if (
		current_build_snapshot.is_empty()
		or not bool(build_participant.call(
			"can_restore_transaction_snapshot",
			current_build_snapshot.duplicate(true)
		))
	):
		return _failure(&"BUILD_SNAPSHOT_INVALID")
	var live_build_value: Variant = build_participant.call("transaction_snapshot")
	if not live_build_value is Dictionary or live_build_value != current_build_snapshot:
		return _failure(&"STALE_BUILD_SNAPSHOT")
	if not _ledger_matches_build(
		ledger_result.get("ledger", []) as Array[Dictionary],
		current_build_snapshot
	):
		return _failure(&"LEDGER_BUILD_MISMATCH")
	var live_player_value: Variant = player.call("reward_effect_snapshot")
	if not live_player_value is Dictionary or (live_player_value as Dictionary).is_empty():
		return _failure(&"PLAYER_SNAPSHOT_INVALID")

	_build = build_participant
	_player = player
	_reward_runtime = reward_runtime
	_run_start_player_baseline = run_start_player_baseline.duplicate(true)
	_definition_ledger = (ledger_result.get("ledger", []) as Array[Dictionary]).duplicate(true)
	_current_build_snapshot = current_build_snapshot.duplicate(true)
	_current_player_snapshot = (live_player_value as Dictionary).duplicate(true)
	_completed_transaction_ids.clear()
	_pending_tickets.clear()
	_configured = true

	var projected := _project_player_snapshot(_definition_ledger)
	if not bool(projected.get("ok", false)):
		_clear_configuration()
		return projected
	var overlaid: Variant = _apply_runtime_overlay(
		projected.get("snapshot", {}),
		_current_player_snapshot,
		projected.get("snapshot", {})
	)
	if not overlaid is Dictionary or (overlaid as Dictionary) != _current_player_snapshot:
		_clear_configuration()
		return _failure(&"LEDGER_PLAYER_MISMATCH")
	return _success({"snapshot": snapshot()})


func prepare_remove(
	transaction_id: String,
	reward_id: String,
	allowed_categories: Array
) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _valid_transaction_id(transaction_id):
		return _failure(&"TRANSACTION_INVALID")
	if _completed_transaction_ids.has(transaction_id) or _pending_tickets.has(transaction_id):
		return _failure(&"DUPLICATE_TRANSACTION")
	var live_state := _live_state_matches_current()
	if not bool(live_state.get("ok", false)):
		return live_state
	var allowlist_result := _normalize_allowed_categories(allowed_categories)
	if not bool(allowlist_result.get("ok", false)):
		return allowlist_result
	var target_index := _definition_index(reward_id)
	if target_index < 0:
		return _failure(&"REWARD_NOT_OWNED", {"reward_id": reward_id})
	var target := _definition_ledger[target_index]
	var category := str(target.get("category", ""))
	if category == "talent":
		return _failure(&"TALENT_UNSUPPORTED")
	if category == "item" and _is_active_item_definition(target):
		return _failure(&"ACTIVE_ITEM_UNSUPPORTED")
	if not (allowlist_result.get("categories", []) as Array).has(category):
		return _failure(&"CATEGORY_NOT_ALLOWED", {"category": category})
	if not REMOVABLE_CATEGORIES.has(category):
		return _failure(&"CATEGORY_UNSUPPORTED", {"category": category})

	var remaining := _definition_ledger.duplicate(true)
	remaining.remove_at(target_index)
	var build_result := _rebuild_build_snapshot(remaining, _current_build_snapshot)
	if not bool(build_result.get("ok", false)):
		return build_result
	var full_player_result := _project_player_snapshot(_definition_ledger)
	if not bool(full_player_result.get("ok", false)):
		return full_player_result
	var remaining_player_result := _project_player_snapshot(remaining)
	if not bool(remaining_player_result.get("ok", false)):
		return remaining_player_result
	var overlaid_player_value: Variant = _apply_runtime_overlay(
		full_player_result.get("snapshot", {}),
		_current_player_snapshot,
		remaining_player_result.get("snapshot", {})
	)
	if not overlaid_player_value is Dictionary:
		return _failure(&"PLAYER_PROJECTION_UNAVAILABLE")
	var overlaid_player := (overlaid_player_value as Dictionary).duplicate(true)
	_clamp_health_snapshots(overlaid_player)
	if (
		overlaid_player.is_empty()
		or (
			_player.has_method("can_restore_reward_effect_snapshot")
			and not bool(_player.call(
				"can_restore_reward_effect_snapshot", overlaid_player.duplicate(true)
			))
		)
	):
		return _failure(&"PLAYER_SNAPSHOT_INVALID")
	var unsigned_ticket := {
		"schema_id": TICKET_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"reward_id": reward_id,
		"category": category,
		"before_build_snapshot": _current_build_snapshot.duplicate(true),
		"after_build_snapshot": (build_result["snapshot"] as Dictionary).duplicate(true),
		"before_player_snapshot": _current_player_snapshot.duplicate(true),
		"after_player_snapshot": overlaid_player.duplicate(true),
		"before_ledger": _definition_ledger.duplicate(true),
		"after_ledger": remaining.duplicate(true),
	}
	var ticket := unsigned_ticket.duplicate(true)
	ticket["fingerprint"] = _digest(unsigned_ticket)
	_pending_tickets[transaction_id] = ticket.duplicate(true)
	return _success({"ticket": ticket.duplicate(true)})


func commit_remove(ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if not _valid_ticket(ticket):
		return _failure(&"TICKET_INVALID")
	var transaction_id := str(ticket["transaction_id"])
	if _completed_transaction_ids.has(transaction_id):
		return _failure(&"DUPLICATE_TRANSACTION")
	if not _pending_tickets.has(transaction_id) or _pending_tickets[transaction_id] != ticket:
		return _failure(&"TICKET_STALE")
	var live_state := _live_state_matches_current()
	if not bool(live_state.get("ok", false)):
		return live_state

	var player_installed := _restore_player(ticket["after_player_snapshot"] as Dictionary)
	if not player_installed:
		var player_recovered := _restore_player(ticket["before_player_snapshot"] as Dictionary)
		return _failure(
			&"COMMIT_FAILED_ROLLED_BACK" if player_recovered else &"ROLLBACK_FAILED",
			{"participant": "player"}
		)
	var build_installed := _restore_build(ticket["after_build_snapshot"] as Dictionary)
	if not build_installed:
		var build_recovered := _restore_build(ticket["before_build_snapshot"] as Dictionary)
		var player_recovered := _restore_player(ticket["before_player_snapshot"] as Dictionary)
		return _failure(
			&"COMMIT_FAILED_ROLLED_BACK" if build_recovered and player_recovered else &"ROLLBACK_FAILED",
			{"participant": "build"}
		)

	var before_authority := snapshot()
	_definition_ledger = (ticket["after_ledger"] as Array).duplicate(true)
	_current_build_snapshot = (ticket["after_build_snapshot"] as Dictionary).duplicate(true)
	_current_player_snapshot = (ticket["after_player_snapshot"] as Dictionary).duplicate(true)
	_completed_transaction_ids[transaction_id] = true
	_pending_tickets.erase(transaction_id)
	var after_authority := snapshot()
	var unsigned_receipt := {
		"schema_id": RECEIPT_SCHEMA_ID,
		"owner_instance_id": get_instance_id(),
		"transaction_id": transaction_id,
		"ticket_fingerprint": str(ticket["fingerprint"]),
		"before_build_snapshot": (ticket["before_build_snapshot"] as Dictionary).duplicate(true),
		"after_build_snapshot": _current_build_snapshot.duplicate(true),
		"before_player_snapshot": (ticket["before_player_snapshot"] as Dictionary).duplicate(true),
		"after_player_snapshot": _current_player_snapshot.duplicate(true),
		"before_authority_snapshot": before_authority.duplicate(true),
		"after_authority_snapshot": after_authority.duplicate(true),
	}
	var receipt := unsigned_receipt.duplicate(true)
	receipt["fingerprint"] = _digest(unsigned_receipt)
	return _success({"receipt": receipt.duplicate(true)})


func rollback_remove(receipt_or_ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(&"NOT_CONFIGURED")
	if _valid_ticket(receipt_or_ticket):
		var pending_id := str(receipt_or_ticket["transaction_id"])
		if not _pending_tickets.has(pending_id) or _pending_tickets[pending_id] != receipt_or_ticket:
			return _failure(&"TICKET_STALE")
		_pending_tickets.erase(pending_id)
		return _success({"transaction_id": pending_id, "rolled_back": "pending"})
	if not _valid_receipt(receipt_or_ticket):
		return _failure(&"RECEIPT_INVALID")
	if (
		_build.call("transaction_snapshot") != receipt_or_ticket["after_build_snapshot"]
		or _player.call("reward_effect_snapshot") != receipt_or_ticket["after_player_snapshot"]
		or snapshot() != receipt_or_ticket["after_authority_snapshot"]
	):
		return _failure(&"RECEIPT_STALE")
	var build_restored := _restore_build(receipt_or_ticket["before_build_snapshot"] as Dictionary)
	var player_restored := _restore_player(receipt_or_ticket["before_player_snapshot"] as Dictionary)
	if not build_restored or not player_restored:
		return _failure(&"ROLLBACK_FAILED")
	if not _restore_authority_snapshot_unchecked(receipt_or_ticket["before_authority_snapshot"] as Dictionary):
		return _failure(&"ROLLBACK_FAILED", {"participant": "authority"})
	return _success({
		"transaction_id": str(receipt_or_ticket["transaction_id"]),
		"rolled_back": "committed",
	})


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	var completed_ids: Array[String] = []
	for transaction_id_value: Variant in _completed_transaction_ids.keys():
		completed_ids.append(str(transaction_id_value))
	completed_ids.sort()
	return {
		"schema_id": SNAPSHOT_SCHEMA_ID,
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"run_start_player_baseline": _run_start_player_baseline.duplicate(true),
		"definition_ledger": _definition_ledger.duplicate(true),
		"completed_transaction_ids": completed_ids,
	}


func can_restore_snapshot(value: Dictionary) -> bool:
	if not _configured or not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return false
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != SNAPSHOT_SCHEMA_ID
		or typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != SNAPSHOT_SCHEMA_VERSION
		or not value["run_start_player_baseline"] is Dictionary
		or (value["run_start_player_baseline"] as Dictionary).is_empty()
		or not value["definition_ledger"] is Array
		or not value["completed_transaction_ids"] is Array
		or not ReplaySafeValueScript.is_supported(value)
	):
		return false
	var ledger_result := _normalize_ledger(value["definition_ledger"] as Array)
	if not bool(ledger_result.get("ok", false)):
		return false
	var completed: Array[String] = []
	var seen: Dictionary = {}
	for id_value: Variant in value["completed_transaction_ids"] as Array:
		if typeof(id_value) != TYPE_STRING or not _valid_transaction_id(str(id_value)) or seen.has(str(id_value)):
			return false
		seen[str(id_value)] = true
		completed.append(str(id_value))
	var sorted := completed.duplicate()
	sorted.sort()
	return completed == sorted


func restore_snapshot(value: Dictionary) -> bool:
	if not can_restore_snapshot(value) or not _pending_tickets.is_empty():
		return false
	if value["run_start_player_baseline"] != _run_start_player_baseline:
		return false
	var normalized: Dictionary = _normalize_ledger(value["definition_ledger"])
	if not _ledger_matches_build(normalized["ledger"], _build.call("transaction_snapshot")):
		return false
	return _restore_authority_snapshot_unchecked(value)


func synchronize_live_state(
	definition_ledger: Array[Dictionary],
	current_build_snapshot: Dictionary
) -> Dictionary:
	if not _configured or not _pending_tickets.is_empty():
		return _failure(&"TRANSACTION_PENDING")
	var ledger_result := _normalize_ledger(definition_ledger)
	if not bool(ledger_result.get("ok", false)):
		return ledger_result
	var normalized_ledger := ledger_result.get("ledger", []) as Array[Dictionary]
	if (
		current_build_snapshot.is_empty()
		or not bool(_build.call(
			"can_restore_transaction_snapshot", current_build_snapshot.duplicate(true)
		))
		or _build.call("transaction_snapshot") != current_build_snapshot
		or not _ledger_matches_build(normalized_ledger, current_build_snapshot)
	):
		return _failure(&"BUILD_SNAPSHOT_INVALID")
	var player_value: Variant = _player.call("reward_effect_snapshot")
	if not player_value is Dictionary or (player_value as Dictionary).is_empty():
		return _failure(&"PLAYER_SNAPSHOT_INVALID")
	_definition_ledger = normalized_ledger.duplicate(true)
	_current_build_snapshot = current_build_snapshot.duplicate(true)
	_current_player_snapshot = (player_value as Dictionary).duplicate(true)
	return _success({"snapshot": snapshot()})


func _project_player_snapshot(ledger: Array[Dictionary]) -> Dictionary:
	var original_value: Variant = _player.call("reward_effect_snapshot")
	if not original_value is Dictionary or (original_value as Dictionary).is_empty():
		return _failure(&"PLAYER_SNAPSHOT_INVALID")
	var original := (original_value as Dictionary).duplicate(true)
	var publication_started := bool(_player.call("reward_effect_begin_publication"))
	if not publication_started:
		return _failure(&"PLAYER_PROJECTION_UNAVAILABLE")
	if not _restore_player(_run_start_player_baseline):
		_cancel_projection(publication_started, original)
		return _failure(&"BASELINE_RESTORE_FAILED")
	for definition: Dictionary in ledger:
		if definition.get("category") == "talent" or _is_active_item_definition(definition):
			continue
		var current_value: Variant = _player.call("reward_effect_snapshot")
		if not current_value is Dictionary:
			_cancel_projection(publication_started, original)
			return _failure(&"PLAYER_SNAPSHOT_INVALID")
		var prepared_value: Variant = _reward_runtime.call(
			"prepare",
			definition.duplicate(true),
			(current_value as Dictionary).duplicate(true)
		)
		if not prepared_value is Dictionary or not bool((prepared_value as Dictionary).get("ok", false)):
			_cancel_projection(publication_started, original)
			return _failure(&"REWARD_REPLAY_PREPARE_FAILED", {"reward_id": str(definition["id"])})
		var plan_value: Variant = (prepared_value as Dictionary).get("plan")
		if not plan_value is Dictionary:
			_cancel_projection(publication_started, original)
			return _failure(&"REWARD_REPLAY_PREPARE_FAILED", {"reward_id": str(definition["id"])})
		var committed_value: Variant = _reward_runtime.call("commit", (plan_value as Dictionary).duplicate(true), _player)
		if not committed_value is Dictionary or not bool((committed_value as Dictionary).get("ok", false)):
			_cancel_projection(publication_started, original)
			return _failure(&"REWARD_REPLAY_COMMIT_FAILED", {"reward_id": str(definition["id"])})
	var target_value: Variant = _player.call("reward_effect_snapshot")
	var target := (target_value as Dictionary).duplicate(true) if target_value is Dictionary else {}
	if target.is_empty() or not _restore_player(original):
		_cancel_projection(publication_started, original)
		return _failure(&"PLAYER_PROJECTION_ROLLBACK_FAILED")
	if publication_started and not bool(_player.call("reward_effect_rollback_publication")):
		return _failure(&"PLAYER_PROJECTION_ROLLBACK_FAILED")
	return _success({"snapshot": target})


func _apply_runtime_overlay(
	expected_value: Variant,
	live_value: Variant,
	target_value: Variant
) -> Variant:
	if typeof(expected_value) != typeof(live_value):
		return _duplicate_value(live_value)
	# Unchanged reward fields must retain the exact live value, including float bits.
	if typeof(expected_value) == typeof(target_value) and expected_value == target_value:
		return _duplicate_value(live_value)
	if (
		typeof(expected_value) in [TYPE_INT, TYPE_FLOAT]
		and typeof(target_value) in [TYPE_INT, TYPE_FLOAT]
	):
		var resolved := float(target_value) + float(live_value) - float(expected_value)
		return int(round(resolved)) if typeof(target_value) == TYPE_INT else resolved
	if expected_value is Dictionary and live_value is Dictionary and target_value is Dictionary:
		var expected := expected_value as Dictionary
		var live := live_value as Dictionary
		var target := (target_value as Dictionary).duplicate(true)
		for key_value: Variant in live.keys():
			if not expected.has(key_value):
				target[key_value] = _duplicate_value(live[key_value])
			elif target.has(key_value):
				target[key_value] = _apply_runtime_overlay(
					expected[key_value], live[key_value], target[key_value]
				)
			elif live[key_value] != expected[key_value]:
				target[key_value] = _duplicate_value(live[key_value])
		return target
	if expected_value is Array and live_value is Array and target_value is Array:
		var expected := expected_value as Array
		var live := live_value as Array
		var target := (target_value as Array).duplicate(true)
		if live.size() >= expected.size():
			var prefix_matches := true
			for index: int in range(expected.size()):
				if live[index] != expected[index]:
					prefix_matches = false
					break
			if prefix_matches:
				for index: int in range(expected.size(), live.size()):
					target.append(_duplicate_value(live[index]))
				return target
		return target if live == expected else live.duplicate(true)
	return _duplicate_value(target_value if live_value == expected_value else live_value)


func _clamp_health_snapshots(value: Variant) -> void:
	if value is Dictionary:
		var dictionary := value as Dictionary
		if (
			typeof(dictionary.get("current_hp")) in [TYPE_INT, TYPE_FLOAT]
			and typeof(dictionary.get("max_hp")) in [TYPE_INT, TYPE_FLOAT]
		):
			var maximum := maxf(0.0, float(dictionary["max_hp"]))
			var current := clampf(float(dictionary["current_hp"]), 0.0, maximum)
			dictionary["current_hp"] = (
				int(round(current))
				if typeof(dictionary["current_hp"]) == TYPE_INT
				else current
			)
		for child: Variant in dictionary.values():
			_clamp_health_snapshots(child)
	elif value is Array:
		for child: Variant in value as Array:
			_clamp_health_snapshots(child)


func _duplicate_value(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value


func _cancel_projection(publication_started: bool, original: Dictionary) -> void:
	_restore_player(original)
	if publication_started:
		_player.call("reward_effect_rollback_publication")


func _rebuild_build_snapshot(ledger: Array[Dictionary], source: Dictionary) -> Dictionary:
	var rebuilt = RunBuildStateScript.new()
	rebuilt.reset(str(source.get("milestone", "M1")))
	for definition: Dictionary in ledger:
		var result: Dictionary = rebuilt.apply_definition(definition.duplicate(true))
		if not bool(result.get("ok", false)):
			return _failure(&"BUILD_REPLAY_FAILED", {"reward_id": str(definition.get("id", ""))})
	var target: Dictionary = rebuilt.transaction_snapshot()
	if not bool(_build.call("can_restore_transaction_snapshot", target.duplicate(true))):
		return _failure(&"BUILD_SNAPSHOT_INVALID")
	return _success({"snapshot": target})


func _normalize_ledger(values: Array) -> Dictionary:
	var ledger: Array[Dictionary] = []
	var seen: Dictionary = {}
	for value: Variant in values:
		if not value is Dictionary:
			return _failure(&"LEDGER_INVALID")
		var definition := (value as Dictionary).duplicate(true)
		var content_id_value: Variant = definition.get("id")
		var category_value: Variant = definition.get("category")
		if (
			typeof(content_id_value) != TYPE_STRING
			or str(content_id_value).is_empty()
			or seen.has(str(content_id_value))
			or typeof(category_value) != TYPE_STRING
			or not ["item", "blessing", "curse", "talent"].has(str(category_value))
			or not definition.get("effects") is Dictionary
			or not ReplaySafeValueScript.is_supported(definition)
		):
			return _failure(&"LEDGER_INVALID")
		seen[str(content_id_value)] = true
		ledger.append(definition)
	return _success({"ledger": ledger})


func _normalize_allowed_categories(values: Array) -> Dictionary:
	var categories: Array[String] = []
	for value: Variant in values:
		if (
			typeof(value) != TYPE_STRING
			or not ["item", "blessing", "curse", "talent"].has(str(value))
			or categories.has(str(value))
		):
			return _failure(&"CATEGORY_ALLOWLIST_INVALID")
		categories.append(str(value))
	if categories.is_empty():
		return _failure(&"CATEGORY_ALLOWLIST_INVALID")
	return _success({"categories": categories})


func _ledger_matches_build(ledger: Array[Dictionary], build_snapshot: Dictionary) -> bool:
	var history_value: Variant = build_snapshot.get("reward_history")
	if not history_value is Array or (history_value as Array).size() != ledger.size():
		return false
	for index: int in range(ledger.size()):
		var expected := ledger[index]
		var actual_value: Variant = (history_value as Array)[index]
		if not actual_value is Dictionary:
			return false
		var actual := actual_value as Dictionary
		for field: String in ["id", "category", "archetype", "effects"]:
			if actual.get(field) != expected.get(field, "" if field == "archetype" else {}):
				return false
	return true


func _definition_index(reward_id: String) -> int:
	for index: int in range(_definition_ledger.size()):
		if str(_definition_ledger[index].get("id", "")) == reward_id:
			return index
	return -1


func _is_active_item_definition(definition: Dictionary) -> bool:
	if str(definition.get("item_mode", "passive")) == "active":
		return true
	if definition.has("active_handler_id"):
		return true
	var tags_value: Variant = definition.get("tags", [])
	return tags_value is Array and (tags_value as Array).has("active")


func _live_state_matches_current() -> Dictionary:
	if _build.call("transaction_snapshot") != _current_build_snapshot:
		return _failure(&"STALE_BUILD_SNAPSHOT")
	if _player.call("reward_effect_snapshot") != _current_player_snapshot:
		return _failure(&"STALE_PLAYER_SNAPSHOT")
	return _success()


func _restore_build(value: Dictionary) -> bool:
	return (
		bool(_build.call("can_restore_transaction_snapshot", value.duplicate(true)))
		and bool(_build.call("restore_transaction_snapshot", value.duplicate(true)))
		and _build.call("transaction_snapshot") == value
	)


func _restore_player(value: Dictionary) -> bool:
	var restored_value: Variant = _player.call("restore_reward_effect_snapshot", value.duplicate(true))
	return typeof(restored_value) == TYPE_BOOL and bool(restored_value) and _player.call("reward_effect_snapshot") == value


func _restore_authority_snapshot_unchecked(value: Dictionary) -> bool:
	_run_start_player_baseline = (value["run_start_player_baseline"] as Dictionary).duplicate(true)
	var normalized: Dictionary = _normalize_ledger(value["definition_ledger"])
	_definition_ledger = (normalized["ledger"] as Array[Dictionary]).duplicate(true)
	_completed_transaction_ids.clear()
	for id_value: Variant in value["completed_transaction_ids"] as Array:
		_completed_transaction_ids[str(id_value)] = true
	_pending_tickets.clear()
	_current_build_snapshot = (_build.call("transaction_snapshot") as Dictionary).duplicate(true)
	_current_player_snapshot = (_player.call("reward_effect_snapshot") as Dictionary).duplicate(true)
	return snapshot() == value


func _valid_ticket(ticket: Dictionary) -> bool:
	if not _has_exact_fields(ticket, TICKET_FIELDS):
		return false
	if (
		typeof(ticket["schema_id"]) != TYPE_STRING
		or str(ticket["schema_id"]) != TICKET_SCHEMA_ID
		or typeof(ticket["owner_instance_id"]) != TYPE_INT
		or int(ticket["owner_instance_id"]) != get_instance_id()
		or typeof(ticket["transaction_id"]) != TYPE_STRING
		or not _valid_transaction_id(str(ticket["transaction_id"]))
		or typeof(ticket["reward_id"]) != TYPE_STRING
		or str(ticket["reward_id"]).is_empty()
		or typeof(ticket["category"]) != TYPE_STRING
		or not REMOVABLE_CATEGORIES.has(str(ticket["category"]))
		or not ticket["before_build_snapshot"] is Dictionary
		or not ticket["after_build_snapshot"] is Dictionary
		or not ticket["before_player_snapshot"] is Dictionary
		or not ticket["after_player_snapshot"] is Dictionary
		or not ticket["before_ledger"] is Array
		or not ticket["after_ledger"] is Array
		or typeof(ticket["fingerprint"]) != TYPE_STRING
	):
		return false
	if (
		not bool(_build.call(
			"can_restore_transaction_snapshot",
			(ticket["before_build_snapshot"] as Dictionary).duplicate(true)
		))
		or not bool(_build.call(
			"can_restore_transaction_snapshot",
			(ticket["after_build_snapshot"] as Dictionary).duplicate(true)
		))
		or not bool(_normalize_ledger(ticket["before_ledger"] as Array).get("ok", false))
		or not bool(_normalize_ledger(ticket["after_ledger"] as Array).get("ok", false))
		or (ticket["after_ledger"] as Array).size() != (ticket["before_ledger"] as Array).size() - 1
		or not _ledger_matches_build(
			ticket["before_ledger"] as Array[Dictionary],
			ticket["before_build_snapshot"] as Dictionary
		)
		or not _ledger_matches_build(
			ticket["after_ledger"] as Array[Dictionary],
			ticket["after_build_snapshot"] as Dictionary
		)
	):
		return false
	var unsigned := ticket.duplicate(true)
	var fingerprint := str(unsigned["fingerprint"])
	unsigned.erase("fingerprint")
	return not fingerprint.is_empty() and fingerprint == _digest(unsigned)


func _valid_receipt(receipt: Dictionary) -> bool:
	if not _has_exact_fields(receipt, RECEIPT_FIELDS):
		return false
	if (
		typeof(receipt["schema_id"]) != TYPE_STRING
		or str(receipt["schema_id"]) != RECEIPT_SCHEMA_ID
		or typeof(receipt["owner_instance_id"]) != TYPE_INT
		or int(receipt["owner_instance_id"]) != get_instance_id()
		or typeof(receipt["transaction_id"]) != TYPE_STRING
		or not _valid_transaction_id(str(receipt["transaction_id"]))
		or typeof(receipt["ticket_fingerprint"]) != TYPE_STRING
		or str(receipt["ticket_fingerprint"]).is_empty()
		or not receipt["before_build_snapshot"] is Dictionary
		or not receipt["after_build_snapshot"] is Dictionary
		or not receipt["before_player_snapshot"] is Dictionary
		or not receipt["after_player_snapshot"] is Dictionary
		or not receipt["before_authority_snapshot"] is Dictionary
		or not receipt["after_authority_snapshot"] is Dictionary
		or not can_restore_snapshot(receipt["before_authority_snapshot"] as Dictionary)
		or not can_restore_snapshot(receipt["after_authority_snapshot"] as Dictionary)
		or typeof(receipt["fingerprint"]) != TYPE_STRING
	):
		return false
	var transaction_id := str(receipt["transaction_id"])
	if (
		(receipt["before_authority_snapshot"] as Dictionary)["completed_transaction_ids"].has(transaction_id)
		or not (receipt["after_authority_snapshot"] as Dictionary)["completed_transaction_ids"].has(transaction_id)
		or not _ledger_matches_build(
			(receipt["before_authority_snapshot"] as Dictionary)["definition_ledger"] as Array[Dictionary],
			receipt["before_build_snapshot"] as Dictionary
		)
		or not _ledger_matches_build(
			(receipt["after_authority_snapshot"] as Dictionary)["definition_ledger"] as Array[Dictionary],
			receipt["after_build_snapshot"] as Dictionary
		)
	):
		return false
	var unsigned := receipt.duplicate(true)
	var fingerprint := str(unsigned["fingerprint"])
	unsigned.erase("fingerprint")
	return not fingerprint.is_empty() and fingerprint == _digest(unsigned)


func _valid_build_participant(value: Object) -> bool:
	return (
		value != null
		and is_instance_valid(value)
		and value.has_method("transaction_snapshot")
		and value.has_method("can_restore_transaction_snapshot")
		and value.has_method("restore_transaction_snapshot")
	)


func _valid_player(value: Object) -> bool:
	return (
		value != null
		and is_instance_valid(value)
		and value.has_method("reward_effect_snapshot")
		and value.has_method("restore_reward_effect_snapshot")
		and value.has_method("reward_effect_apply_operation")
		and value.has_method("reward_effect_begin_publication")
		and value.has_method("reward_effect_rollback_publication")
	)


func _valid_reward_runtime(value: Object) -> bool:
	return (
		value != null
		and is_instance_valid(value)
		and value.has_method("prepare")
		and value.has_method("commit")
		and value.has_method("rollback")
	)


func _valid_transaction_id(value: String) -> bool:
	var expression := RegEx.new()
	return expression.compile(TRANSACTION_ID_PATTERN) == OK and expression.search(value) != null


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _clear_configuration() -> void:
	_configured = false
	_build = null
	_player = null
	_reward_runtime = null
	_run_start_player_baseline.clear()
	_definition_ledger.clear()
	_current_build_snapshot.clear()
	_current_player_snapshot.clear()
	_completed_transaction_ids.clear()
	_pending_tickets.clear()


func _digest(value: Variant) -> String:
	return var_to_bytes(_canonicalize(value)).hex_encode().sha256_text()


func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var source := value as Dictionary
		var keys: Array[String] = []
		var source_keys: Dictionary = {}
		for key_value: Variant in source.keys():
			var key := str(key_value)
			keys.append(key)
			source_keys[key] = key_value
		keys.sort()
		var normalized: Dictionary = {}
		for key: String in keys:
			normalized[key] = _canonicalize(source[source_keys[key]])
		return normalized
	if value is Array:
		var normalized_array: Array = []
		for entry: Variant in value as Array:
			normalized_array.append(_canonicalize(entry))
		return normalized_array
	if typeof(value) == TYPE_STRING_NAME:
		return str(value)
	return value


func _success(context: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "code": &"OK", "context": context.duplicate(true)}
	for key_value: Variant in context.keys():
		var value: Variant = context[key_value]
		result[str(key_value)] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
