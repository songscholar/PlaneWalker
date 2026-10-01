class_name PlayerRewardEffectRuntime
extends RefCounted

const EffectHandlerCatalogScript := preload(
	"res://scripts/content/effects/effect_handler_catalog.gd"
)

const PLAN_SCHEMA_VERSION := 1
const RECEIPT_SCHEMA_VERSION := 1

const CODE_OK := &"OK"
const CODE_INVALID_DEFINITION := &"INVALID_DEFINITION"
const CODE_INVALID_EFFECTS := &"INVALID_EFFECTS"
const CODE_CATALOG_UNAVAILABLE := &"CATALOG_UNAVAILABLE"
const CODE_MISSING_RUNTIME_DOMAIN := &"MISSING_RUNTIME_DOMAIN"
const CODE_INVALID_PLAYER_SNAPSHOT := &"INVALID_PLAYER_SNAPSHOT"
const CODE_INVALID_PLAN := &"INVALID_PLAN"
const CODE_INVALID_PLAYER := &"INVALID_PLAYER"
const CODE_STALE_PLAYER_SNAPSHOT := &"STALE_PLAYER_SNAPSHOT"
const CODE_OPERATION_FAILED := &"OPERATION_FAILED"
const CODE_COMMIT_FAILED_ROLLED_BACK := &"COMMIT_FAILED_ROLLED_BACK"
const CODE_ROLLBACK_FAILED := &"ROLLBACK_FAILED"
const CODE_INVALID_RECEIPT := &"INVALID_RECEIPT"
const CODE_ROLLED_BACK := &"ROLLED_BACK"

const CONTENT_CATEGORIES: Array[String] = ["blessing", "curse", "item", "talent"]
const DOMAIN_ORDER: Array[String] = [
	"stats",
	"health",
	"time",
	"weapon",
	"character",
	"trigger",
]
const REQUIRED_PLAYER_METHODS: Array[StringName] = [
	&"reward_effect_snapshot",
	&"restore_reward_effect_snapshot",
	&"reward_effect_apply_operation",
]
const PLAN_FIELDS: Array[String] = [
	"schema_version",
	"definition_id",
	"category",
	"effects",
	"player_snapshot",
	"player_snapshot_digest",
	"operations",
	"digest",
]
const OPERATION_FIELDS: Array[String] = [
	"effect_id",
	"runtime_domain",
	"value",
	"stack_rule",
	"weapon_capabilities",
]
const RECEIPT_FIELDS: Array[String] = [
	"schema_version",
	"plan_digest",
	"before_snapshot",
	"before_snapshot_digest",
	"after_snapshot",
	"after_snapshot_digest",
	"operation_count",
	"digest",
]

var _catalog: RefCounted


func _init(catalog_override: Variant = null) -> void:
	if catalog_override is RefCounted:
		_catalog = catalog_override as RefCounted
	else:
		_catalog = EffectHandlerCatalogScript.new()


func prepare(definition: Dictionary, player_snapshot: Dictionary) -> Dictionary:
	var definition_validation := _validate_definition(definition)
	if not bool(definition_validation.get("ok", false)):
		return definition_validation
	if player_snapshot.is_empty():
		return _failure(CODE_INVALID_PLAYER_SNAPSHOT, {"reason": "empty"})
	if not _catalog_supports_runtime_descriptors():
		return _failure(CODE_CATALOG_UNAVAILABLE)

	var effects := definition["effects"] as Dictionary
	var validation_value: Variant = _catalog.call(
		"validate_effects",
		effects.duplicate(true),
		{"category": str(definition["category"])}
	)
	if (
		not validation_value is Object
		or not (validation_value as Object).has_method("has_blocking_errors")
	):
		return _failure(CODE_CATALOG_UNAVAILABLE, {"reason": "validation_contract"})
	if bool((validation_value as Object).call("has_blocking_errors")):
		return _failure(CODE_INVALID_EFFECTS)

	var normalized_value: Variant = _catalog.call("normalize_effects", effects.duplicate(true))
	if not normalized_value is Dictionary:
		return _failure(CODE_INVALID_EFFECTS, {"reason": "normalization_contract"})
	var normalized := normalized_value as Dictionary
	if normalized.is_empty() or normalized.size() != effects.size():
		return _failure(CODE_INVALID_EFFECTS, {"reason": "normalization_failed"})

	var buckets: Dictionary = {}
	for runtime_domain: String in DOMAIN_ORDER:
		buckets[runtime_domain] = []
	var effect_ids: Array[String] = []
	for effect_id_value: Variant in normalized.keys():
		effect_ids.append(str(effect_id_value))
	effect_ids.sort()
	for effect_id: String in effect_ids:
		var descriptor_value: Variant = _catalog.call("effect_descriptor", StringName(effect_id))
		if not descriptor_value is Dictionary or (descriptor_value as Dictionary).is_empty():
			return _failure(CODE_INVALID_EFFECTS, {
				"effect_id": effect_id,
				"reason": "descriptor_missing",
			})
		var descriptor := descriptor_value as Dictionary
		var runtime_domain_value: Variant = descriptor.get("runtime_domain")
		if typeof(runtime_domain_value) != TYPE_STRING or str(runtime_domain_value).is_empty():
			return _failure(CODE_MISSING_RUNTIME_DOMAIN, {"effect_id": effect_id})
		var runtime_domain := str(runtime_domain_value)
		if not DOMAIN_ORDER.has(runtime_domain):
			return _failure(CODE_MISSING_RUNTIME_DOMAIN, {
				"effect_id": effect_id,
				"runtime_domain": runtime_domain,
			})
		if str(descriptor.get("effect_id", "")) != effect_id:
			return _failure(CODE_INVALID_EFFECTS, {
				"effect_id": effect_id,
				"reason": "descriptor_identity",
			})
		var weapon_capabilities_value: Variant = descriptor.get("weapon_capabilities", [])
		if not weapon_capabilities_value is Array:
			return _failure(CODE_INVALID_EFFECTS, {
				"effect_id": effect_id,
				"reason": "weapon_capabilities_type",
			})
		var operation := {
			"effect_id": effect_id,
			"runtime_domain": runtime_domain,
			"value": normalized[effect_id],
			"stack_rule": str(descriptor.get("stack_rule", "")),
			"weapon_capabilities": (weapon_capabilities_value as Array).duplicate(true),
		}
		(buckets[runtime_domain] as Array).append(operation)

	var operations: Array[Dictionary] = []
	for runtime_domain: String in DOMAIN_ORDER:
		for operation_value: Variant in buckets[runtime_domain] as Array:
			operations.append((operation_value as Dictionary).duplicate(true))
	var frozen_snapshot := player_snapshot.duplicate(true)
	var unsigned_plan := {
		"schema_version": PLAN_SCHEMA_VERSION,
		"definition_id": str(definition["id"]),
		"category": str(definition["category"]),
		"effects": normalized.duplicate(true),
		"player_snapshot": frozen_snapshot,
		"player_snapshot_digest": _digest(frozen_snapshot),
		"operations": operations.duplicate(true),
	}
	var plan := unsigned_plan.duplicate(true)
	plan["digest"] = _digest(unsigned_plan)
	return _success({"plan": plan.duplicate(true)})


func commit(plan: Dictionary, player: Object) -> Dictionary:
	if not _valid_plan(plan):
		return _failure(CODE_INVALID_PLAN)
	if not _valid_player(player):
		return _failure(CODE_INVALID_PLAYER)
	var before_value: Variant = player.call("reward_effect_snapshot")
	if not before_value is Dictionary or (before_value as Dictionary).is_empty():
		return _failure(CODE_INVALID_PLAYER_SNAPSHOT, {"reason": "live_snapshot"})
	var before := (before_value as Dictionary).duplicate(true)
	if (
		before != plan["player_snapshot"]
		or _digest(before) != str(plan["player_snapshot_digest"])
	):
		return _failure(CODE_STALE_PLAYER_SNAPSHOT)

	var operations := plan["operations"] as Array
	for operation_index: int in range(operations.size()):
		var operation := (operations[operation_index] as Dictionary).duplicate(true)
		var operation_result_value: Variant = player.call(
			"reward_effect_apply_operation",
			operation.duplicate(true)
		)
		var operation_result := (
			(operation_result_value as Dictionary).duplicate(true)
			if operation_result_value is Dictionary
			else {}
		)
		if not bool(operation_result.get("ok", false)):
			return _commit_failure_with_rollback(
				player,
				before,
				operation,
				operation_index,
				operation_result
			)

	var after_value: Variant = player.call("reward_effect_snapshot")
	if not after_value is Dictionary or (after_value as Dictionary).is_empty():
		return _commit_failure_with_rollback(
			player,
			before,
			{},
			operations.size(),
			{"ok": false, "code": CODE_INVALID_PLAYER_SNAPSHOT}
		)
	var after := (after_value as Dictionary).duplicate(true)
	var unsigned_receipt := {
		"schema_version": RECEIPT_SCHEMA_VERSION,
		"plan_digest": str(plan["digest"]),
		"before_snapshot": before.duplicate(true),
		"before_snapshot_digest": _digest(before),
		"after_snapshot": after.duplicate(true),
		"after_snapshot_digest": _digest(after),
		"operation_count": operations.size(),
	}
	var receipt := unsigned_receipt.duplicate(true)
	receipt["digest"] = _digest(unsigned_receipt)
	return _success({"receipt": receipt.duplicate(true)})


func rollback(receipt: Dictionary, player: Object) -> Dictionary:
	if not _valid_receipt(receipt):
		return _failure(CODE_INVALID_RECEIPT)
	if not _valid_player(player):
		return _failure(CODE_INVALID_PLAYER)
	var current_value: Variant = player.call("reward_effect_snapshot")
	if not current_value is Dictionary or (current_value as Dictionary).is_empty():
		return _failure(CODE_INVALID_PLAYER_SNAPSHOT, {"reason": "live_snapshot"})
	var current := current_value as Dictionary
	if (
		current != receipt["after_snapshot"]
		or _digest(current) != str(receipt["after_snapshot_digest"])
	):
		return _failure(CODE_STALE_PLAYER_SNAPSHOT)
	var before := (receipt["before_snapshot"] as Dictionary).duplicate(true)
	var restore_result := _restore_and_verify(player, before)
	if not bool(restore_result.get("ok", false)):
		return _failure(CODE_ROLLBACK_FAILED, restore_result.get("context", {}))
	return {
		"ok": true,
		"code": CODE_ROLLED_BACK,
		"restored_snapshot": before.duplicate(true),
	}


func _commit_failure_with_rollback(
	player: Object,
	before: Dictionary,
	operation: Dictionary,
	operation_index: int,
	operation_result: Dictionary
) -> Dictionary:
	var restore_result := _restore_and_verify(player, before)
	var context := {
		"failure_code": StringName(str(operation_result.get("code", CODE_OPERATION_FAILED))),
		"operation_index": operation_index,
		"operation": operation.duplicate(true),
		"operation_result": operation_result.duplicate(true),
	}
	if not bool(restore_result.get("ok", false)):
		context["restore"] = restore_result.get("context", {}).duplicate(true)
		return _failure(CODE_ROLLBACK_FAILED, context)
	context["restored_snapshot"] = before.duplicate(true)
	return _failure(CODE_COMMIT_FAILED_ROLLED_BACK, context)


func _restore_and_verify(player: Object, target: Dictionary) -> Dictionary:
	var restore_value: Variant = player.call(
		"restore_reward_effect_snapshot",
		target.duplicate(true)
	)
	var current_value: Variant = player.call("reward_effect_snapshot")
	var current := (
		(current_value as Dictionary).duplicate(true)
		if current_value is Dictionary
		else {}
	)
	if typeof(restore_value) != TYPE_BOOL or not bool(restore_value):
		return {
			"ok": false,
			"context": {
				"reason": "restore_rejected",
				"snapshot_matches": current == target,
			},
		}
	if current != target or _digest(current) != _digest(target):
		return {
			"ok": false,
			"context": {"reason": "restore_verification"},
		}
	return {"ok": true, "context": {}}


func _validate_definition(definition: Dictionary) -> Dictionary:
	var id_value: Variant = definition.get("id")
	var category_value: Variant = definition.get("category")
	var effects_value: Variant = definition.get("effects")
	if (
		typeof(id_value) != TYPE_STRING
		or str(id_value).is_empty()
		or str(id_value) != str(id_value).strip_edges()
	):
		return _failure(CODE_INVALID_DEFINITION, {"field": "id"})
	if (
		typeof(category_value) != TYPE_STRING
		or not CONTENT_CATEGORIES.has(str(category_value))
	):
		return _failure(CODE_INVALID_DEFINITION, {"field": "category"})
	if not effects_value is Dictionary or (effects_value as Dictionary).is_empty():
		return _failure(CODE_INVALID_DEFINITION, {"field": "effects"})
	return {"ok": true, "code": CODE_OK, "context": {}}


func _catalog_supports_runtime_descriptors() -> bool:
	return (
		_catalog != null
		and _catalog.has_method("validate_effects")
		and _catalog.has_method("normalize_effects")
		and _catalog.has_method("effect_descriptor")
	)


func _valid_player(player: Object) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	for method_name: StringName in REQUIRED_PLAYER_METHODS:
		if not player.has_method(method_name):
			return false
	return true


func _valid_plan(plan: Dictionary) -> bool:
	if not _has_exact_fields(plan, PLAN_FIELDS):
		return false
	if (
		typeof(plan["schema_version"]) != TYPE_INT
		or int(plan["schema_version"]) != PLAN_SCHEMA_VERSION
		or typeof(plan["definition_id"]) != TYPE_STRING
		or str(plan["definition_id"]).is_empty()
		or typeof(plan["category"]) != TYPE_STRING
		or not CONTENT_CATEGORIES.has(str(plan["category"]))
		or not plan["effects"] is Dictionary
		or (plan["effects"] as Dictionary).is_empty()
		or not plan["player_snapshot"] is Dictionary
		or (plan["player_snapshot"] as Dictionary).is_empty()
		or typeof(plan["player_snapshot_digest"]) != TYPE_STRING
		or str(plan["player_snapshot_digest"]).is_empty()
		or not plan["operations"] is Array
		or (plan["operations"] as Array).is_empty()
		or typeof(plan["digest"]) != TYPE_STRING
		or str(plan["digest"]).is_empty()
	):
		return false
	if str(plan["player_snapshot_digest"]) != _digest(plan["player_snapshot"]):
		return false
	var effects := plan["effects"] as Dictionary
	var operations := plan["operations"] as Array
	if effects.size() != operations.size():
		return false
	var seen: Dictionary = {}
	var prior_domain_index := -1
	var prior_effect_id := ""
	for operation_value: Variant in operations:
		if not operation_value is Dictionary:
			return false
		var operation := operation_value as Dictionary
		if not _has_exact_fields(operation, OPERATION_FIELDS):
			return false
		var effect_id_value: Variant = operation["effect_id"]
		var runtime_domain_value: Variant = operation["runtime_domain"]
		if (
			typeof(effect_id_value) != TYPE_STRING
			or str(effect_id_value).is_empty()
			or seen.has(str(effect_id_value))
			or not effects.has(str(effect_id_value))
			or effects[str(effect_id_value)] != operation["value"]
			or typeof(runtime_domain_value) != TYPE_STRING
			or not DOMAIN_ORDER.has(str(runtime_domain_value))
			or typeof(operation["stack_rule"]) != TYPE_STRING
			or str(operation["stack_rule"]).is_empty()
			or not operation["weapon_capabilities"] is Array
		):
			return false
		var effect_id := str(effect_id_value)
		var domain_index := DOMAIN_ORDER.find(str(runtime_domain_value))
		if domain_index < prior_domain_index:
			return false
		if domain_index == prior_domain_index and effect_id <= prior_effect_id:
			return false
		seen[effect_id] = true
		prior_domain_index = domain_index
		prior_effect_id = effect_id
	var unsigned_plan := plan.duplicate(true)
	unsigned_plan.erase("digest")
	return str(plan["digest"]) == _digest(unsigned_plan)


func _valid_receipt(receipt: Dictionary) -> bool:
	if not _has_exact_fields(receipt, RECEIPT_FIELDS):
		return false
	if (
		typeof(receipt["schema_version"]) != TYPE_INT
		or int(receipt["schema_version"]) != RECEIPT_SCHEMA_VERSION
		or typeof(receipt["plan_digest"]) != TYPE_STRING
		or str(receipt["plan_digest"]).is_empty()
		or not receipt["before_snapshot"] is Dictionary
		or (receipt["before_snapshot"] as Dictionary).is_empty()
		or typeof(receipt["before_snapshot_digest"]) != TYPE_STRING
		or str(receipt["before_snapshot_digest"]).is_empty()
		or not receipt["after_snapshot"] is Dictionary
		or (receipt["after_snapshot"] as Dictionary).is_empty()
		or typeof(receipt["after_snapshot_digest"]) != TYPE_STRING
		or str(receipt["after_snapshot_digest"]).is_empty()
		or typeof(receipt["operation_count"]) != TYPE_INT
		or int(receipt["operation_count"]) <= 0
		or typeof(receipt["digest"]) != TYPE_STRING
		or str(receipt["digest"]).is_empty()
	):
		return false
	if str(receipt["before_snapshot_digest"]) != _digest(receipt["before_snapshot"]):
		return false
	if str(receipt["after_snapshot_digest"]) != _digest(receipt["after_snapshot"]):
		return false
	var unsigned_receipt := receipt.duplicate(true)
	unsigned_receipt.erase("digest")
	return str(receipt["digest"]) == _digest(unsigned_receipt)


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


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
	var result := {
		"ok": true,
		"code": CODE_OK,
		"context": context.duplicate(true),
	}
	for key_value: Variant in context.keys():
		result[str(key_value)] = context[key_value].duplicate(true) if context[key_value] is Dictionary or context[key_value] is Array else context[key_value]
	return result


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"context": context.duplicate(true),
	}
