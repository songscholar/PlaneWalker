class_name RunRewardReplaySeal
extends RefCounted

const ContentSnapshotProviderScript := preload(
	"res://scripts/content/content_snapshot_provider.gd"
)
const EffectHandlerCatalogScript := preload(
	"res://scripts/content/effects/effect_handler_catalog.gd"
)
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const ReplaySafeValueScript := preload("res://scripts/replay/replay_safe_value.gd")
const RunBuildStateScript := preload("res://scripts/progression/run_build_state.gd")

const SCHEMA_ID := "planewalker.run_reward_replay"
const SCHEMA_VERSION := 1
const PREFIX_SCHEMA_ID := "planewalker.run_reward_replay.prefix"
const PREFIX_SCHEMA_VERSION := 1
const LAUNCH_MILESTONES: Array[String] = ["LAUNCH", "EXPANSION"]
const SNAPSHOT_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"milestone",
	"content_snapshot",
	"build_state",
	"reward_facts",
	"reward_prefix",
	"snapshot_digest",
]
const FACT_FIELDS: Array[String] = [
	"id",
	"category",
	"archetype",
	"effects",
	"effect_digest",
]
const PREFIX_FIELDS: Array[String] = [
	"schema_id",
	"schema_version",
	"fact_count",
	"root_sha256",
	"digest_sha256",
]
const SHA256_PATTERN := "^[a-f0-9]{64}$"

var _effect_catalog: RefCounted


func _init(
	effect_catalog_path: String = EffectHandlerCatalogScript.DEFAULT_CATALOG_PATH
) -> void:
	_effect_catalog = EffectHandlerCatalogScript.new(effect_catalog_path)


func capture(registry: Variant, build_state_value: Dictionary) -> Dictionary:
	var milestone := str(build_state_value.get("milestone", ""))
	if not LAUNCH_MILESTONES.has(milestone):
		return {}
	var current_content := ContentSnapshotProviderScript.snapshot(registry)
	if current_content.is_empty() or not _build_state_is_valid(build_state_value, milestone):
		return {}
	var facts_result := _reward_facts_for_build(registry, build_state_value, milestone)
	if not bool(facts_result.get("ok", false)):
		return {}
	var facts := facts_result.get("facts", []) as Array
	var prefix := reward_prefix(facts)
	if prefix.is_empty():
		return {}
	var result := {
		"schema_id": SCHEMA_ID,
		"schema_version": SCHEMA_VERSION,
		"milestone": milestone,
		"content_snapshot": current_content.duplicate(true),
		"build_state": build_state_value.duplicate(true),
		"reward_facts": facts.duplicate(true),
		"reward_prefix": prefix,
	}
	result["snapshot_digest"] = snapshot_digest(result)
	return result if _is_sha256(result["snapshot_digest"]) else {}


func validate(
	value: Dictionary,
	registry: Variant,
	expected_milestone: String = ""
) -> Dictionary:
	if not _has_exact_fields(value, SNAPSHOT_FIELDS):
		return _failure(&"INVALID_FIELDS")
	if not ReplaySafeValueScript.is_supported(value):
		return _failure(&"UNSAFE_VALUE")
	if (
		typeof(value["schema_id"]) != TYPE_STRING
		or str(value["schema_id"]) != SCHEMA_ID
		or typeof(value["schema_version"]) != TYPE_INT
		or int(value["schema_version"]) != SCHEMA_VERSION
		or typeof(value["milestone"]) != TYPE_STRING
		or not LAUNCH_MILESTONES.has(str(value["milestone"]))
		or not value["content_snapshot"] is Dictionary
		or not value["build_state"] is Dictionary
		or not value["reward_facts"] is Array
		or not value["reward_prefix"] is Dictionary
		or not _is_sha256(value["snapshot_digest"])
	):
		return _failure(&"INVALID_SHAPE")
	var milestone := str(value["milestone"])
	if not expected_milestone.is_empty() and milestone != expected_milestone:
		return _failure(&"MILESTONE_MISMATCH")
	var current_content := ContentSnapshotProviderScript.snapshot(registry)
	if current_content.is_empty() or current_content != value["content_snapshot"]:
		return _failure(&"CONTENT_FINGERPRINT_MISMATCH")
	var build_state_value := value["build_state"] as Dictionary
	if not _build_state_is_valid(build_state_value, milestone):
		return _failure(&"INVALID_BUILD_STATE")
	var facts_result := _reward_facts_for_build(registry, build_state_value, milestone)
	if not bool(facts_result.get("ok", false)):
		return facts_result
	var current_facts := facts_result.get("facts", []) as Array
	if current_facts != value["reward_facts"]:
		return _failure(&"REWARD_FACT_DRIFT")
	var current_prefix := reward_prefix(current_facts)
	if current_prefix.is_empty() or current_prefix != value["reward_prefix"]:
		return _failure(&"REWARD_PREFIX_DRIFT")
	if str(value["snapshot_digest"]) != snapshot_digest(value):
		return _failure(&"SNAPSHOT_DIGEST_MISMATCH")
	return {
		"ok": true,
		"code": &"OK",
		"snapshot": value.duplicate(true),
	}


func reward_prefix(facts_value: Array) -> Dictionary:
	var fact_digests: Array[String] = []
	for fact_value: Variant in facts_value:
		if not fact_value is Dictionary:
			return {}
		var fact := fact_value as Dictionary
		if not _has_exact_fields(fact, FACT_FIELDS) or not _reward_fact_is_valid(fact):
			return {}
		fact_digests.append(ReplayRecorderScript.value_digest(fact))
	var root := ReplayRecorderScript.value_digest({
		"schema_id": PREFIX_SCHEMA_ID,
		"schema_version": PREFIX_SCHEMA_VERSION,
		"fact_count": facts_value.size(),
		"fact_digests": fact_digests,
	})
	if not _is_sha256(root):
		return {}
	var digest := ReplayRecorderScript.value_digest({
		"schema_id": PREFIX_SCHEMA_ID,
		"schema_version": PREFIX_SCHEMA_VERSION,
		"fact_count": facts_value.size(),
		"root_sha256": root,
	})
	if not _is_sha256(digest):
		return {}
	return {
		"schema_id": PREFIX_SCHEMA_ID,
		"schema_version": PREFIX_SCHEMA_VERSION,
		"fact_count": facts_value.size(),
		"root_sha256": root,
		"digest_sha256": digest,
	}


func prefix_matches(prefix_value: Dictionary, facts_value: Array) -> bool:
	if not _has_exact_fields(prefix_value, PREFIX_FIELDS):
		return false
	var count_value: Variant = prefix_value.get("fact_count")
	if typeof(count_value) != TYPE_INT:
		return false
	var count := int(count_value)
	if count < 0 or count > facts_value.size():
		return false
	var prefix_facts: Array = facts_value.slice(0, count)
	return prefix_value == reward_prefix(prefix_facts)


func snapshot_digest(value: Dictionary) -> String:
	var digest_source := {
		"schema_id": value.get("schema_id"),
		"schema_version": value.get("schema_version"),
		"milestone": value.get("milestone"),
		"content_snapshot": (
			(value.get("content_snapshot", {}) as Dictionary).duplicate(true)
			if value.get("content_snapshot", {}) is Dictionary
			else value.get("content_snapshot")
		),
		"build_state": (
			(value.get("build_state", {}) as Dictionary).duplicate(true)
			if value.get("build_state", {}) is Dictionary
			else value.get("build_state")
		),
		"reward_facts": (
			(value.get("reward_facts", []) as Array).duplicate(true)
			if value.get("reward_facts", []) is Array
			else value.get("reward_facts")
		),
		"reward_prefix": (
			(value.get("reward_prefix", {}) as Dictionary).duplicate(true)
			if value.get("reward_prefix", {}) is Dictionary
			else value.get("reward_prefix")
		),
	}
	return ReplayRecorderScript.value_digest(digest_source)


func _reward_facts_for_build(
	registry: Variant,
	build_state_value: Dictionary,
	milestone: String
) -> Dictionary:
	if (
		registry == null
		or not registry is Object
		or not registry.has_method("get_content")
	):
		return _failure(&"CONTENT_NOT_AVAILABLE")
	var load_report: Variant = _effect_catalog.call("load_report")
	if (
		load_report == null
		or not load_report is Object
		or not load_report.has_method("has_blocking_errors")
		or bool(load_report.call("has_blocking_errors"))
	):
		return _failure(&"EFFECT_CATALOG_INVALID")
	var facts: Array[Dictionary] = []
	for history_value: Variant in build_state_value.get("reward_history", []):
		if not history_value is Dictionary:
			return _failure(&"INVALID_BUILD_STATE")
		var history := history_value as Dictionary
		var content_id := str(history.get("id", ""))
		var category := str(history.get("category", ""))
		var archetype := str(history.get("archetype", ""))
		var definition_value: Variant = registry.call("get_content", StringName(content_id))
		if not definition_value is Dictionary or (definition_value as Dictionary).is_empty():
			return _failure(&"UNKNOWN_CONTENT_ID", {"content_id": content_id})
		var definition := definition_value as Dictionary
		if (
			str(definition.get("id", "")) != content_id
			or str(definition.get("category", "")) != category
			or str(definition.get("archetype", "")) != archetype
			or not definition.get("availability", []) is Array
			or not (definition.get("availability", []) as Array).has(milestone)
			or not definition.get("effects", {}) is Dictionary
			or not history.get("effects", {}) is Dictionary
		):
			return _failure(&"CONTENT_DEFINITION_DRIFT", {"content_id": content_id})
		var current_effects := definition.get("effects", {}) as Dictionary
		var history_effects := history.get("effects", {}) as Dictionary
		var current_report: Variant = _effect_catalog.call(
			"validate_effects", current_effects, {"category": category}
		)
		var history_report: Variant = _effect_catalog.call(
			"validate_effects", history_effects, {"category": category}
		)
		if (
			current_report == null
			or history_report == null
			or bool(current_report.call("has_blocking_errors"))
			or bool(history_report.call("has_blocking_errors"))
		):
			return _failure(&"EFFECT_VALIDATION_FAILED", {"content_id": content_id})
		var normalized_current: Dictionary = _effect_catalog.call(
			"normalize_effects", current_effects
		)
		var normalized_history: Dictionary = _effect_catalog.call(
			"normalize_effects", history_effects
		)
		if normalized_current != normalized_history:
			return _failure(&"CONTENT_EFFECT_DRIFT", {"content_id": content_id})
		var descriptors: Dictionary = {}
		var effect_ids: Array = normalized_current.keys()
		effect_ids.sort_custom(func(left: Variant, right: Variant) -> bool: return str(left) < str(right))
		for effect_id_value: Variant in effect_ids:
			var effect_id := str(effect_id_value)
			var descriptor: Dictionary = _effect_catalog.call(
				"effect_descriptor", StringName(effect_id)
			)
			if descriptor.is_empty():
				return _failure(&"UNKNOWN_EFFECT_ID", {"effect_id": effect_id})
			descriptors[effect_id] = descriptor.duplicate(true)
		var effect_digest := ReplayRecorderScript.value_digest({
			"id": content_id,
			"category": category,
			"archetype": archetype,
			"effects": normalized_current.duplicate(true),
			"effect_descriptors": descriptors,
		})
		if not _is_sha256(effect_digest):
			return _failure(&"EFFECT_DIGEST_FAILED", {"content_id": content_id})
		facts.append({
			"id": content_id,
			"category": category,
			"archetype": archetype,
			"effects": normalized_current.duplicate(true),
			"effect_digest": effect_digest,
		})
	return {"ok": true, "code": &"OK", "facts": facts}


func _build_state_is_valid(value: Dictionary, milestone: String) -> bool:
	if str(value.get("milestone", "")) != milestone:
		return false
	var validator = RunBuildStateScript.new()
	return validator.can_restore_transaction_snapshot(value)


func _reward_fact_is_valid(value: Dictionary) -> bool:
	return (
		typeof(value.get("id")) == TYPE_STRING
		and not str(value["id"]).is_empty()
		and typeof(value.get("category")) == TYPE_STRING
		and str(value["category"]) in ["item", "blessing", "curse", "talent"]
		and typeof(value.get("archetype")) == TYPE_STRING
		and value.get("effects") is Dictionary
		and _is_sha256(value.get("effect_digest"))
	)


func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.size() != fields.size():
		return false
	for field: String in fields:
		if not value.has(field):
			return false
	return true


func _is_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var regex := RegEx.new()
	return regex.compile(SHA256_PATTERN) == OK and regex.search(str(value)) != null


func _failure(code: StringName, context: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "context": context.duplicate(true)}
