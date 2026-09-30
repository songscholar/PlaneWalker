class_name TimeActionTransaction
extends RefCounted

const TICKET_SCHEMA_VERSION := 1
const RUNTIME_SNAPSHOT_SCHEMA_VERSION := 1
const FINALIZED_TICKET_CACHE_LIMIT := 64

const CODE_OK := &"OK"
const CODE_INVALID_TICKET := &"INVALID_TICKET"
const CODE_INVALID_CALLBACK := &"INVALID_CALLBACK"
const CODE_ALREADY_COMMITTED := &"ALREADY_COMMITTED"
const CODE_STALE_TICKET := &"STALE_TICKET"
const CODE_COMMIT_ALREADY_ATTEMPTED := &"COMMIT_ALREADY_ATTEMPTED"
const CODE_COMMIT_CALLBACK_FAILED := &"COMMIT_CALLBACK_FAILED"
const CODE_COMMIT_FAILED_ROLLED_BACK := &"COMMIT_FAILED_ROLLED_BACK"
const CODE_COMMIT_REJECTED_UNMUTATED := &"COMMIT_REJECTED_UNMUTATED"
const CODE_RESTORE_CALLBACK_REQUIRED := &"RESTORE_CALLBACK_REQUIRED"
const CODE_ROLLED_BACK := &"ROLLED_BACK"
const CODE_ROLLBACK_FAILED := &"ROLLBACK_FAILED"

var _next_ticket_id: int = 1
var _active_transaction: Dictionary = {}
var _finalized_watermarks: Dictionary = {}
var _finalized_tickets: Dictionary = {}
var _finalized_ticket_order: Array[String] = []


func runtime_snapshot() -> Dictionary:
	return {
		"schema_version": RUNTIME_SNAPSHOT_SCHEMA_VERSION,
		"next_ticket_id": _next_ticket_id,
		"active_transaction": _active_transaction.duplicate(true),
		"finalized_watermarks": _finalized_watermarks.duplicate(true),
		"finalized_tickets": _finalized_tickets.duplicate(true),
		"finalized_ticket_order": _finalized_ticket_order.duplicate(),
	}


func restore_runtime_snapshot(value: Dictionary) -> bool:
	if not _valid_runtime_snapshot(value):
		return false
	_next_ticket_id = int(value["next_ticket_id"])
	_active_transaction = (value["active_transaction"] as Dictionary).duplicate(true)
	_finalized_watermarks = (value["finalized_watermarks"] as Dictionary).duplicate(true)
	_finalized_tickets = (value["finalized_tickets"] as Dictionary).duplicate(true)
	_finalized_ticket_order.clear()
	for fingerprint_value: Variant in value["finalized_ticket_order"] as Array:
		_finalized_ticket_order.append(str(fingerprint_value))
	return runtime_snapshot() == value


func _valid_runtime_snapshot(value: Dictionary) -> bool:
	if (
		value.size() != 6
		or typeof(value.get("schema_version")) != TYPE_INT
		or int(value.get("schema_version", -1)) != RUNTIME_SNAPSHOT_SCHEMA_VERSION
		or typeof(value.get("next_ticket_id")) != TYPE_INT
		or int(value.get("next_ticket_id", 0)) <= 0
		or not value.get("active_transaction") is Dictionary
		or not (value.get("active_transaction") as Dictionary).is_empty()
		or not value.get("finalized_watermarks") is Dictionary
		or not value.get("finalized_tickets") is Dictionary
		or not value.get("finalized_ticket_order") is Array
	):
		return false
	var next_ticket_id := int(value["next_ticket_id"])
	var watermarks := value["finalized_watermarks"] as Dictionary
	for run_key_value: Variant in watermarks.keys():
		if typeof(run_key_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var watermark_value: Variant = watermarks[run_key_value]
		if not watermark_value is Dictionary:
			return false
		var watermark := watermark_value as Dictionary
		if (
			watermark.size() != 2
			or typeof(watermark.get("generation")) != TYPE_INT
			or int(watermark.get("generation", 0)) <= 0
			or typeof(watermark.get("token")) != TYPE_INT
			or int(watermark.get("token", 0)) <= 0
		):
			return false

	var finalized_tickets := value["finalized_tickets"] as Dictionary
	var order := value["finalized_ticket_order"] as Array
	if order.size() != finalized_tickets.size() or order.size() > FINALIZED_TICKET_CACHE_LIMIT:
		return false
	var seen: Dictionary = {}
	for fingerprint_value: Variant in order:
		if typeof(fingerprint_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var fingerprint := str(fingerprint_value)
		if fingerprint.is_empty() or seen.has(fingerprint) or not finalized_tickets.has(fingerprint):
			return false
		seen[fingerprint] = true
		var finalized_value: Variant = finalized_tickets[fingerprint]
		if not finalized_value is Dictionary:
			return false
		var finalized := finalized_value as Dictionary
		if (
			finalized.size() != 2
			or StringName(str(finalized.get("status", "")))
			not in [&"committed", &"rejected_unmutated", &"rolled_back"]
			or not finalized.get("public") is Dictionary
		):
			return false
		var public_ticket := finalized.get("public") as Dictionary
		if (
			typeof(public_ticket.get("ticket_id")) != TYPE_INT
			or int(public_ticket.get("ticket_id", 0)) <= 0
			or int(public_ticket.get("ticket_id", 0)) >= next_ticket_id
			or typeof(public_ticket.get("owner_instance_id")) != TYPE_INT
			or int(public_ticket.get("owner_instance_id", 0)) != get_instance_id()
			or typeof(public_ticket.get("fingerprint")) != TYPE_STRING
			or str(public_ticket.get("fingerprint", "")) != fingerprint
		):
			return false
		var unsigned_ticket := public_ticket.duplicate(true)
		unsigned_ticket.erase("fingerprint")
		if fingerprint != _fingerprint(unsigned_ticket):
			return false
	return true


func prepare(
	token: int,
	generation: int,
	frame: int,
	run_id: StringName,
	ability_id: StringName,
	context: Dictionary,
	prepared_snapshot: Dictionary
) -> Dictionary:
	if not _active_transaction.is_empty():
		return {}
	if not _valid_identity(token, generation, frame, run_id, ability_id):
		return {}
	if _identity_is_finalized_or_stale(run_id, token, generation):
		return {}

	var frozen_context := context.duplicate(true)
	var frozen_snapshot := prepared_snapshot.duplicate(true)
	var ticket_id := _next_ticket_id
	_next_ticket_id += 1
	var ticket := {
		"schema_version": TICKET_SCHEMA_VERSION,
		"ticket_id": ticket_id,
		"owner_instance_id": get_instance_id(),
		"token": token,
		"generation": generation,
		"frame": frame,
		"run_id": run_id,
		"ability_id": ability_id,
		"context": frozen_context,
		"prepared_snapshot": frozen_snapshot,
	}
	ticket["fingerprint"] = _fingerprint(ticket)
	_active_transaction = {
		"public": ticket.duplicate(true),
		"commit_attempted": false,
	}
	return ticket.duplicate(true)


func commit(
	ticket: Dictionary,
	commit_callback: Callable,
	restore_callback: Callable = Callable()
) -> Dictionary:
	if not _ticket_matches_active(ticket):
		return _inactive_ticket_failure(ticket, true)
	if bool(_active_transaction.get("commit_attempted", false)):
		return _failure(CODE_COMMIT_ALREADY_ATTEMPTED)
	if not commit_callback.is_valid():
		return _failure(CODE_INVALID_CALLBACK)

	_active_transaction["commit_attempted"] = true
	var authoritative := _active_public_ticket()
	var callback_value: Variant = commit_callback.call(authoritative.duplicate(true))
	var callback_result: Dictionary = (
		(callback_value as Dictionary).duplicate(true)
		if callback_value is Dictionary
		else {}
	)
	if bool(callback_result.get("ok", false)):
		_finish_active(&"committed")
		return {
			"ok": true,
			"code": CODE_OK,
			"ticket": authoritative.duplicate(true),
			"context": (authoritative["context"] as Dictionary).duplicate(true),
			"commit_result": callback_result,
		}

	var failure_code := StringName(str(callback_result.get("code", CODE_COMMIT_CALLBACK_FAILED)))
	if typeof(callback_result.get("mutated")) == TYPE_BOOL and not bool(callback_result["mutated"]):
		_finish_active(&"rejected_unmutated")
		return _failure(CODE_COMMIT_REJECTED_UNMUTATED, {
			"failure_code": failure_code,
			"commit_result": callback_result,
		})
	if not restore_callback.is_valid():
		return _failure(CODE_RESTORE_CALLBACK_REQUIRED, {
			"failure_code": failure_code,
			"commit_result": callback_result,
		})

	var restore_result := _restore_active(restore_callback)
	if not bool(restore_result.get("ok", false)):
		return _failure(CODE_ROLLBACK_FAILED, {
			"failure_code": failure_code,
			"commit_result": callback_result,
			"restore_result": restore_result,
		})
	var restored_snapshot := (restore_result["restored_snapshot"] as Dictionary).duplicate(true)
	_finish_active(&"rolled_back")
	return _failure(CODE_COMMIT_FAILED_ROLLED_BACK, {
		"failure_code": failure_code,
		"commit_result": callback_result,
		"restored_snapshot": restored_snapshot,
	})


func rollback(ticket: Dictionary, restore_callback: Callable) -> Dictionary:
	if not _ticket_matches_active(ticket):
		return _inactive_ticket_failure(ticket, false)
	if not restore_callback.is_valid():
		return _failure(CODE_INVALID_CALLBACK)
	var restore_result := _restore_active(restore_callback)
	if not bool(restore_result.get("ok", false)):
		return _failure(CODE_ROLLBACK_FAILED, {"restore_result": restore_result})
	var restored_snapshot := (restore_result["restored_snapshot"] as Dictionary).duplicate(true)
	_finish_active(&"rolled_back")
	return {
		"ok": true,
		"code": CODE_ROLLED_BACK,
		"restored_snapshot": restored_snapshot,
	}


func _valid_identity(
	token: int,
	generation: int,
	frame: int,
	run_id: StringName,
	ability_id: StringName
) -> bool:
	var run_text := str(run_id)
	var ability_text := str(ability_id)
	return (
		token > 0
		and generation > 0
		and frame >= 0
		and not run_text.is_empty()
		and run_text == run_text.strip_edges()
		and not run_text.contains(":")
		and not ability_text.is_empty()
		and ability_text == ability_text.strip_edges()
		and not ability_text.contains(":")
	)


func _identity_is_finalized_or_stale(run_id: StringName, token: int, generation: int) -> bool:
	var watermark_value: Variant = _finalized_watermarks.get(str(run_id))
	if not watermark_value is Dictionary:
		return false
	var watermark := watermark_value as Dictionary
	var finalized_generation := int(watermark.get("generation", 0))
	if generation != finalized_generation:
		return generation < finalized_generation
	return token <= int(watermark.get("token", 0))


func _fingerprint(ticket_without_fingerprint: Dictionary) -> String:
	return var_to_bytes(ticket_without_fingerprint).hex_encode().sha256_text()


func _ticket_matches_active(ticket: Dictionary) -> bool:
	if _active_transaction.is_empty() or not _active_transaction.get("public") is Dictionary:
		return false
	var authoritative := _active_transaction["public"] as Dictionary
	return (
		typeof(ticket.get("schema_version")) == TYPE_INT
		and int(ticket.get("schema_version", -1)) == TICKET_SCHEMA_VERSION
		and typeof(ticket.get("owner_instance_id")) == TYPE_INT
		and int(ticket.get("owner_instance_id", 0)) == get_instance_id()
		and ticket == authoritative
	)


func _inactive_ticket_failure(ticket: Dictionary, for_commit: bool) -> Dictionary:
	var fingerprint := str(ticket.get("fingerprint", ""))
	var finalized_value: Variant = _finalized_tickets.get(fingerprint)
	if finalized_value is Dictionary:
		var finalized := finalized_value as Dictionary
		if finalized.get("public") == ticket:
			if for_commit and StringName(str(finalized.get("status", ""))) == &"committed":
				return _failure(CODE_ALREADY_COMMITTED)
			return _failure(CODE_STALE_TICKET)
	if _ticket_is_owned_and_self_consistent(ticket):
		var run_id := StringName(str(ticket.get("run_id", "")))
		var token := int(ticket.get("token", 0))
		var generation := int(ticket.get("generation", 0))
		if _identity_is_finalized_or_stale(run_id, token, generation):
			return _failure(CODE_STALE_TICKET)
	return _failure(CODE_INVALID_TICKET)


func _ticket_is_owned_and_self_consistent(ticket: Dictionary) -> bool:
	if (
		typeof(ticket.get("schema_version")) != TYPE_INT
		or int(ticket.get("schema_version", -1)) != TICKET_SCHEMA_VERSION
		or typeof(ticket.get("ticket_id")) != TYPE_INT
		or int(ticket.get("ticket_id", 0)) <= 0
		or int(ticket.get("ticket_id", 0)) >= _next_ticket_id
		or typeof(ticket.get("owner_instance_id")) != TYPE_INT
		or int(ticket.get("owner_instance_id", 0)) != get_instance_id()
		or typeof(ticket.get("token")) != TYPE_INT
		or typeof(ticket.get("generation")) != TYPE_INT
		or typeof(ticket.get("frame")) != TYPE_INT
		or not ticket.get("context") is Dictionary
		or not ticket.get("prepared_snapshot") is Dictionary
	):
		return false
	var run_id := StringName(str(ticket.get("run_id", "")))
	var ability_id := StringName(str(ticket.get("ability_id", "")))
	if not _valid_identity(
		int(ticket.get("token", 0)),
		int(ticket.get("generation", 0)),
		int(ticket.get("frame", -1)),
		run_id,
		ability_id
	):
		return false
	var fingerprint := str(ticket.get("fingerprint", ""))
	if fingerprint.is_empty():
		return false
	var unsigned_ticket := ticket.duplicate(true)
	unsigned_ticket.erase("fingerprint")
	return fingerprint == _fingerprint(unsigned_ticket)


func _active_public_ticket() -> Dictionary:
	return (_active_transaction["public"] as Dictionary).duplicate(true)


func _restore_active(restore_callback: Callable) -> Dictionary:
	var authoritative := _active_public_ticket()
	var prepared_snapshot := (authoritative["prepared_snapshot"] as Dictionary).duplicate(true)
	var callback_value: Variant = restore_callback.call(prepared_snapshot.duplicate(true))
	if not callback_value is Dictionary:
		return _failure(CODE_ROLLBACK_FAILED)
	var callback_result := (callback_value as Dictionary).duplicate(true)
	var restored_value: Variant = callback_result.get("restored_snapshot")
	if (
		not bool(callback_result.get("ok", false))
		or not restored_value is Dictionary
		or restored_value != prepared_snapshot
	):
		return _failure(CODE_ROLLBACK_FAILED, {"callback_result": callback_result})
	return {
		"ok": true,
		"code": CODE_ROLLED_BACK,
		"restored_snapshot": prepared_snapshot,
	}


func _finish_active(status: StringName) -> void:
	var authoritative := _active_public_ticket()
	var fingerprint := str(authoritative["fingerprint"])
	_advance_finalized_watermark(
		StringName(str(authoritative["run_id"])),
		int(authoritative["token"]),
		int(authoritative["generation"])
	)
	_finalized_tickets[fingerprint] = {
		"status": status,
		"public": authoritative,
	}
	_finalized_ticket_order.append(fingerprint)
	while _finalized_ticket_order.size() > FINALIZED_TICKET_CACHE_LIMIT:
		var evicted_fingerprint: String = _finalized_ticket_order.pop_front()
		_finalized_tickets.erase(evicted_fingerprint)
	_active_transaction.clear()


func _advance_finalized_watermark(run_id: StringName, token: int, generation: int) -> void:
	var run_key := str(run_id)
	var watermark_value: Variant = _finalized_watermarks.get(run_key)
	if not watermark_value is Dictionary:
		_finalized_watermarks[run_key] = {
			"generation": generation,
			"token": token,
		}
		return
	var watermark := watermark_value as Dictionary
	var finalized_generation := int(watermark.get("generation", 0))
	if generation > finalized_generation:
		watermark["generation"] = generation
		watermark["token"] = token
	elif generation == finalized_generation:
		watermark["token"] = maxi(int(watermark.get("token", 0)), token)


func _failure(code: StringName, details: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": false,
		"code": code,
	}
	for key: Variant in details.keys():
		result[key] = details[key]
	return result
