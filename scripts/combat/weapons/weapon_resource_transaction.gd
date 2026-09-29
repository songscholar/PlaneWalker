class_name WeaponResourceTransaction
extends RefCounted

const SNAPSHOT_SCHEMA_VERSION := 1

const CODE_OK := &"OK"
const CODE_ALREADY_COMMITTED := &"ALREADY_COMMITTED"
const CODE_NOT_CONFIGURED := &"NOT_CONFIGURED"
const CODE_INVALID_PLAN := &"INVALID_PLAN"
const CODE_INVALID_TICKET := &"INVALID_TICKET"
const CODE_TOKEN_REUSED := &"TOKEN_REUSED"
const CODE_COOLDOWN_ACTIVE := &"COOLDOWN_ACTIVE"
const CODE_RESOURCE_NOT_FOUND := &"RESOURCE_NOT_FOUND"
const CODE_INSUFFICIENT_RESOURCE := &"INSUFFICIENT_RESOURCE"
const CODE_RESOURCE_PROVIDER_INVALID := &"RESOURCE_PROVIDER_INVALID"
const CODE_MULTIPLE_EXTERNAL_RESOURCES := &"MULTIPLE_EXTERNAL_RESOURCES_UNSUPPORTED"
const CODE_RESOURCE_COMMIT_FAILED := &"RESOURCE_COMMIT_FAILED"

const REQUIRED_PROVIDER_METHODS: Array[StringName] = [
	&"resource_state",
	&"try_spend_resource",
]

var _configured: bool = false
var _weapon_id: StringName = &""
var _runtime_owned_resource_ids: Dictionary = {}
var _external_accounts: Dictionary = {}
var _cooldowns: Dictionary = {}
var _committed_tokens: Dictionary = {}


func configure(
	weapon_id: StringName,
	runtime_owned_resource_ids: PackedStringArray,
	external_accounts: Dictionary
) -> bool:
	if weapon_id == &"":
		return false
	var next_runtime_owned: Dictionary = {}
	for resource_value: String in runtime_owned_resource_ids:
		var resource_id := StringName(resource_value)
		if resource_id == &"" or next_runtime_owned.has(str(resource_id)):
			return false
		next_runtime_owned[str(resource_id)] = true

	var next_external: Dictionary = {}
	for resource_key: Variant in external_accounts.keys():
		if typeof(resource_key) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return false
		var resource_id := StringName(str(resource_key))
		if resource_id == &"" or next_runtime_owned.has(str(resource_id)):
			return false
		var provider_value: Variant = external_accounts[resource_key]
		if not provider_value is Object:
			return false
		var provider := provider_value as Object
		if not is_instance_valid(provider) or not _has_methods(provider, REQUIRED_PROVIDER_METHODS):
			return false
		next_external[str(resource_id)] = provider

	_weapon_id = weapon_id
	_runtime_owned_resource_ids = next_runtime_owned
	_external_accounts = next_external
	_cooldowns.clear()
	_committed_tokens.clear()
	_configured = true
	return true


func prepare(plan: Dictionary, token: int) -> Dictionary:
	if not _configured:
		return _failure(CODE_NOT_CONFIGURED)
	if token <= 0:
		return _failure(CODE_INVALID_PLAN, {"field": "token"})

	var normalized_result := _normalize_plan(plan)
	if not bool(normalized_result.get("ok", false)):
		return normalized_result
	var normalized: Dictionary = normalized_result["plan"]
	var fingerprint := _fingerprint(normalized)
	if _committed_tokens.has(token):
		var committed: Dictionary = _committed_tokens[token]
		if str(committed.get("fingerprint", "")) != fingerprint:
			return _failure(CODE_TOKEN_REUSED, {"token": token})
		return _success(
			CODE_ALREADY_COMMITTED,
			{"ticket": (committed.get("ticket", {}) as Dictionary).duplicate(true)}
		)

	var action_id := StringName(str(normalized["action_id"]))
	var cooldown_remaining := cooldown_remaining(action_id)
	if cooldown_remaining > 0:
		return _failure(CODE_COOLDOWN_ACTIVE, {
			"action_id": str(action_id),
			"remaining_frames": cooldown_remaining,
		})

	var external_debits: Array[Dictionary] = []
	for resource_value: Variant in (normalized["resource_costs"] as Dictionary).keys():
		var resource_id := StringName(str(resource_value))
		var amount := float(normalized["resource_costs"][resource_value])
		if _runtime_owned_resource_ids.has(str(resource_id)):
			continue
		if not _external_accounts.has(str(resource_id)):
			return _failure(CODE_RESOURCE_NOT_FOUND, {"resource_id": str(resource_id)})
		var provider := _external_accounts[str(resource_id)] as Object
		var state_value: Variant = provider.call("resource_state", resource_id)
		if not state_value is Dictionary:
			return _failure(CODE_RESOURCE_PROVIDER_INVALID, {"resource_id": str(resource_id)})
		var state := state_value as Dictionary
		if not bool(state.get("ok", false)) or not _valid_resource_state(state, resource_id):
			return _provider_failure(state, CODE_RESOURCE_PROVIDER_INVALID, resource_id)
		if float(state["current"]) < amount:
			return _failure(CODE_INSUFFICIENT_RESOURCE, {
				"resource_id": str(resource_id),
				"required": amount,
				"current": float(state["current"]),
			})
		if amount > 0.0:
			external_debits.append({
				"resource_id": str(resource_id),
				"amount": amount,
				"revision": int(state["revision"]),
			})
	if external_debits.size() > 1:
		return _failure(CODE_MULTIPLE_EXTERNAL_RESOURCES, {
			"count": external_debits.size(),
		})

	var ticket := {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"weapon_id": str(_weapon_id),
		"action_id": str(action_id),
		"token": token,
		"cooldown_frames": int(normalized["cooldown_frames"]),
		"resource_costs": (normalized["resource_costs"] as Dictionary).duplicate(true),
		"external_debits": external_debits.duplicate(true),
		"fingerprint": fingerprint,
	}
	return _success(CODE_OK, {"ticket": ticket})


func commit(ticket: Dictionary) -> Dictionary:
	if not _configured:
		return _failure(CODE_NOT_CONFIGURED)
	if not _valid_ticket(ticket):
		return _failure(CODE_INVALID_TICKET)
	var token := int(ticket["token"])
	var fingerprint := str(ticket["fingerprint"])
	if _committed_tokens.has(token):
		var committed: Dictionary = _committed_tokens[token]
		if str(committed.get("fingerprint", "")) != fingerprint:
			return _failure(CODE_TOKEN_REUSED, {"token": token})
		var stored_context: Dictionary = committed.get("context", {})
		return _success(CODE_ALREADY_COMMITTED, stored_context.duplicate(true))

	var action_id := StringName(str(ticket["action_id"]))
	var live_cooldown := cooldown_remaining(action_id)
	if live_cooldown > 0:
		return _failure(CODE_COOLDOWN_ACTIVE, {
			"action_id": str(action_id),
			"remaining_frames": live_cooldown,
		})

	var cooldown_key := str(action_id)
	var had_cooldown := _cooldowns.has(cooldown_key)
	var cooldown_before := int(_cooldowns.get(cooldown_key, 0))
	var cooldown_frames := int(ticket["cooldown_frames"])
	_cooldowns[cooldown_key] = cooldown_frames

	var external_results: Array[Dictionary] = []
	for debit_value: Variant in ticket["external_debits"] as Array:
		var debit := debit_value as Dictionary
		var resource_id := StringName(str(debit["resource_id"]))
		var provider := _external_accounts.get(str(resource_id)) as Object
		if provider == null or not is_instance_valid(provider):
			_restore_cooldown(cooldown_key, had_cooldown, cooldown_before)
			return _failure(CODE_RESOURCE_PROVIDER_INVALID, {"resource_id": str(resource_id)})
		var spend_value: Variant = provider.call(
			"try_spend_resource",
			resource_id,
			float(debit["amount"]),
			int(debit["revision"]),
			StringName("weapon:%s:%s:%d" % [str(_weapon_id), str(action_id), token])
		)
		if not spend_value is Dictionary or not bool((spend_value as Dictionary).get("ok", false)):
			_restore_cooldown(cooldown_key, had_cooldown, cooldown_before)
			if spend_value is Dictionary:
				return _provider_failure(spend_value as Dictionary, CODE_RESOURCE_COMMIT_FAILED, resource_id)
			return _failure(CODE_RESOURCE_COMMIT_FAILED, {"resource_id": str(resource_id)})
		external_results.append((spend_value as Dictionary).duplicate(true))

	var context := {
		"weapon_id": str(_weapon_id),
		"action_id": str(action_id),
		"token": token,
		"cooldown_frames": cooldown_frames,
		"resource_costs": (ticket["resource_costs"] as Dictionary).duplicate(true),
		"external_results": external_results.duplicate(true),
		"idempotent": false,
	}
	_committed_tokens[token] = {
		"fingerprint": fingerprint,
		"ticket": ticket.duplicate(true),
		"context": context.duplicate(true),
	}
	return _success(CODE_OK, context)


func advance_frame(frame_count: int = 1) -> void:
	if frame_count <= 0:
		return
	for action_value: Variant in _cooldowns.keys():
		var action_id := str(action_value)
		_cooldowns[action_id] = maxi(0, int(_cooldowns[action_id]) - frame_count)


func cooldown_remaining(action_id: StringName) -> int:
	if action_id == &"":
		return 0
	return maxi(0, int(_cooldowns.get(str(action_id), 0)))


func snapshot() -> Dictionary:
	return {
		"schema_version": SNAPSHOT_SCHEMA_VERSION,
		"configured": _configured,
		"weapon_id": str(_weapon_id),
		"cooldowns": _cooldowns.duplicate(true),
		"committed_tokens": _committed_tokens.duplicate(true),
	}


func rewind_safe_reset() -> void:
	# A rewind abandons transient action state elsewhere. Committed costs and cooldowns
	# remain authoritative and therefore require no mutation here.
	pass


func reset_runtime_state() -> void:
	_cooldowns.clear()
	_committed_tokens.clear()


func _normalize_plan(plan: Dictionary) -> Dictionary:
	if str(plan.get("weapon_id", "")) != str(_weapon_id):
		return _failure(CODE_INVALID_PLAN, {"field": "weapon_id"})
	var action_value: Variant = plan.get("action_id")
	if typeof(action_value) not in [TYPE_STRING, TYPE_STRING_NAME] or str(action_value).is_empty():
		return _failure(CODE_INVALID_PLAN, {"field": "action_id"})
	var cooldown_value: Variant = plan.get("cooldown_frames", 0)
	if (
		typeof(cooldown_value) != TYPE_INT
		or int(cooldown_value) < 0
	):
		return _failure(CODE_INVALID_PLAN, {"field": "cooldown_frames"})
	var costs_value: Variant = plan.get("resource_costs", {})
	if not costs_value is Dictionary:
		return _failure(CODE_INVALID_PLAN, {"field": "resource_costs"})

	var normalized_costs: Dictionary = {}
	var resource_ids: Array[String] = []
	for resource_value: Variant in (costs_value as Dictionary).keys():
		if typeof(resource_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
			return _failure(CODE_INVALID_PLAN, {"field": "resource_costs"})
		var resource_id := str(resource_value)
		if resource_id.is_empty() or resource_ids.has(resource_id):
			return _failure(CODE_INVALID_PLAN, {"field": "resource_costs.%s" % resource_id})
		var amount_value: Variant = (costs_value as Dictionary)[resource_value]
		if (
			typeof(amount_value) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(amount_value))
			or float(amount_value) < 0.0
		):
			return _failure(CODE_INVALID_PLAN, {"field": "resource_costs.%s" % resource_id})
		resource_ids.append(resource_id)
	resource_ids.sort()
	for resource_id: String in resource_ids:
		var amount_value: Variant = (costs_value as Dictionary).get(resource_id)
		if amount_value == null:
			amount_value = (costs_value as Dictionary).get(StringName(resource_id))
		normalized_costs[resource_id] = float(amount_value)

	return {
		"ok": true,
		"code": CODE_OK,
		"plan": {
			"weapon_id": str(_weapon_id),
			"action_id": str(action_value),
			"cooldown_frames": int(cooldown_value),
			"resource_costs": normalized_costs,
		},
		"context": {},
	}


func _valid_ticket(ticket: Dictionary) -> bool:
	if int(ticket.get("schema_version", -1)) != SNAPSHOT_SCHEMA_VERSION:
		return false
	if str(ticket.get("weapon_id", "")) != str(_weapon_id):
		return false
	if str(ticket.get("action_id", "")).is_empty() or int(ticket.get("token", 0)) <= 0:
		return false
	if typeof(ticket.get("cooldown_frames")) != TYPE_INT or int(ticket["cooldown_frames"]) < 0:
		return false
	if not ticket.get("resource_costs") is Dictionary or not ticket.get("external_debits") is Array:
		return false
	var external_debits := ticket["external_debits"] as Array
	if external_debits.size() > 1:
		return false
	var expected_external_costs: Dictionary = {}
	for resource_value: Variant in (ticket["resource_costs"] as Dictionary).keys():
		var resource_id := str(resource_value)
		var amount := float(ticket["resource_costs"][resource_value])
		if _runtime_owned_resource_ids.has(resource_id):
			continue
		if not _external_accounts.has(resource_id):
			return false
		if amount > 0.0:
			expected_external_costs[resource_id] = amount
	if external_debits.size() != expected_external_costs.size():
		return false
	var seen_external: Dictionary = {}
	for debit_value: Variant in external_debits:
		if not debit_value is Dictionary:
			return false
		var debit := debit_value as Dictionary
		var debit_resource_id := str(debit.get("resource_id", ""))
		if (
			debit_resource_id.is_empty()
			or seen_external.has(debit_resource_id)
			or not expected_external_costs.has(debit_resource_id)
			or typeof(debit.get("amount")) not in [TYPE_INT, TYPE_FLOAT]
			or not is_finite(float(debit["amount"]))
			or float(debit["amount"]) <= 0.0
			or float(debit["amount"]) != float(expected_external_costs[debit_resource_id])
			or typeof(debit.get("revision")) != TYPE_INT
			or int(debit["revision"]) <= 0
		):
			return false
		seen_external[debit_resource_id] = true
	var normalized_result := _normalize_plan({
		"weapon_id": ticket["weapon_id"],
		"action_id": ticket["action_id"],
		"cooldown_frames": ticket["cooldown_frames"],
		"resource_costs": (ticket["resource_costs"] as Dictionary).duplicate(true),
	})
	if not bool(normalized_result.get("ok", false)):
		return false
	return str(ticket.get("fingerprint", "")) == _fingerprint(normalized_result["plan"])


func _valid_resource_state(state: Dictionary, resource_id: StringName) -> bool:
	if str(state.get("resource_id", "")) != str(resource_id):
		return false
	for field: String in ["current", "minimum", "maximum"]:
		var value: Variant = state.get(field)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
			return false
	if float(state["minimum"]) > float(state["maximum"]):
		return false
	if float(state["current"]) < float(state["minimum"]) or float(state["current"]) > float(state["maximum"]):
		return false
	return typeof(state.get("revision")) == TYPE_INT and int(state["revision"]) > 0


func _fingerprint(plan: Dictionary) -> String:
	return JSON.stringify({
		"weapon_id": str(plan.get("weapon_id", "")),
		"action_id": str(plan.get("action_id", "")),
		"cooldown_frames": int(plan.get("cooldown_frames", 0)),
		"resource_costs": (plan.get("resource_costs", {}) as Dictionary).duplicate(true),
	})


func _restore_cooldown(action_id: String, had_value: bool, value: int) -> void:
	if had_value:
		_cooldowns[action_id] = value
	else:
		_cooldowns.erase(action_id)


func _provider_failure(
	provider_result: Dictionary,
	fallback_code: StringName,
	resource_id: StringName
) -> Dictionary:
	var code := StringName(str(provider_result.get("code", fallback_code)))
	if code == &"":
		code = fallback_code
	var context_value: Variant = provider_result.get("context", {})
	var context := (
		(context_value as Dictionary).duplicate(true)
		if context_value is Dictionary
		else {}
	)
	context["resource_id"] = str(resource_id)
	return _failure(code, context)


func _has_methods(provider: Object, methods: Array[StringName]) -> bool:
	for method_name: StringName in methods:
		if not provider.has_method(method_name):
			return false
	return true


func _success(code: StringName, context: Dictionary = {}) -> Dictionary:
	var result := {
		"ok": true,
		"code": code,
		"context": context.duplicate(true),
	}
	if context.has("ticket"):
		result["ticket"] = (context["ticket"] as Dictionary).duplicate(true)
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"context": context.duplicate(true),
	}
