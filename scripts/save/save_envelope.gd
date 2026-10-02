class_name SaveEnvelope
extends RefCounted

const SaveResultScript := preload("res://scripts/save/save_result.gd")
const SavePathPolicyScript := preload("res://scripts/save/save_path_policy.gd")
const ActiveItemRuntimeScript := preload("res://scripts/items/active_item_runtime.gd")
const ReplayRecorderScript := preload("res://scripts/replay/replay_recorder.gd")
const FloorPlanScript := preload("res://scripts/dungeon/floor_plan.gd")

const MAGIC := "PWSAVE"
const SCHEMA_VERSION := 3
const INTEGRITY_ALGORITHM := "sha256"
const VALID_DOCUMENT_KINDS: Array[String] = ["profile", "settings"]
const PROFILE_FIELDS: Array[String] = [
	"magic",
	"schema_version",
	"document_kind",
	"profile_id",
	"save_domain",
	"sequence",
	"game_version",
	"created_at_utc",
	"saved_at_utc",
	"content_snapshot",
	"payload",
	"integrity",
]
const SETTINGS_FIELDS: Array[String] = [
	"magic",
	"schema_version",
	"document_kind",
	"sequence",
	"game_version",
	"created_at_utc",
	"saved_at_utc",
	"payload",
	"integrity",
]
const CONTENT_SNAPSHOT_FIELDS: Array[String] = ["aggregate_sha256", "packs"]
const CONTENT_PACK_FIELDS: Array[String] = [
	"pack_id",
	"pack_version",
	"schema_version",
	"fingerprint_sha256",
]
const SETTINGS_PAYLOAD_FIELDS: Array[String] = [
	"locale",
	"master_volume",
	"master_muted",
	"music_volume",
	"sfx_volume",
	"dialogue_volume",
	"camera_shake_enabled",
	"hit_flash_enabled",
	"reduced_motion",
	"text_scale",
	"high_contrast_danger",
	"subtitles_enabled",
	"subtitle_scale",
	"ranged_charge_mode",
	"damage_received_multiplier",
	"enemy_telegraph_scale",
]
const LEGACY_SETTINGS_REQUIRED_FIELDS: Array[String] = [
	"locale",
	"master_volume",
	"master_muted",
	"camera_shake_enabled",
	"hit_flash_enabled",
	"reduced_motion",
]
const ACTIVE_RUN_FIELDS: Array[String] = [
	"schema_version", "run_id", "revision", "phase", "suspended", "run_seed",
	"current_floor", "current_room", "room_total", "run_time_ms", "resources",
	"stats", "events", "build", "open_offer", "consumed_offer_ids", "result",
	"config", "current_floor_index", "floor_plan", "completed_floor_ids",
	"run_economy", "seen_event_ids", "merchant_state", "floor_rule_state",
]
const FLOOR_IDS: Array[String] = [
	"floor_ruins_of_remnant",
	"floor_void_forest",
	"floor_time_rift",
	"floor_plane_forge",
	"floor_throne_of_void",
]
const FLOOR_PLAN_MILESTONES: Array[String] = ["LAUNCH", "EXPANSION"]


static func create_profile(
	profile_id: String,
	save_domain: String,
	sequence: int,
	game_version: String,
	created_at_utc: String,
	saved_at_utc: String,
	content_snapshot: Dictionary,
	payload: Dictionary
):
	var profile_validation = SavePathPolicyScript.validate_id(profile_id, &"profile_id")
	if not profile_validation.ok:
		return profile_validation
	var domain_validation = SavePathPolicyScript.validate_id(save_domain, &"save_domain")
	if not domain_validation.ok:
		return domain_validation
	var normalized_payload := payload.duplicate(true)
	if not normalized_payload.has("active_item_state"):
		normalized_payload["active_item_state"] = empty_active_item_state()
	if not normalized_payload.has("reward_effect_state"):
		normalized_payload["reward_effect_state"] = {}
	if not normalized_payload.has("active_run_state"):
		normalized_payload["active_run_state"] = {}
	normalized_payload = _normalize_profile_payload(normalized_payload, SCHEMA_VERSION)
	var common_error := _common_create_error(
		sequence,
		game_version,
		created_at_utc,
		saved_at_utc,
		normalized_payload
	)
	if not common_error.is_empty():
		return _invalid_create(str(common_error["field"]), str(common_error["reason"]), common_error.get("value"))
	var snapshot_error := _content_snapshot_error(content_snapshot)
	if not snapshot_error.is_empty():
		return _invalid_create(str(snapshot_error["field"]), str(snapshot_error["reason"]), snapshot_error.get("value"))

	var payload_error := _profile_payload_error(normalized_payload, SCHEMA_VERSION)
	if not payload_error.is_empty():
		return _invalid_create(
			str(payload_error["field"]),
			str(payload_error["reason"]),
			payload_error.get("value")
		)
	var document := {
		"magic": MAGIC,
		"schema_version": SCHEMA_VERSION,
		"document_kind": "profile",
		"profile_id": profile_id,
		"save_domain": save_domain,
		"sequence": sequence,
		"game_version": game_version,
		"created_at_utc": created_at_utc,
		"saved_at_utc": saved_at_utc,
		"content_snapshot": content_snapshot.duplicate(true),
		"payload": normalized_payload,
	}
	return _finish_create(document)


static func create_settings(
	sequence: int,
	game_version: String,
	created_at_utc: String,
	saved_at_utc: String,
	payload: Dictionary
):
	var common_error := _common_create_error(sequence, game_version, created_at_utc, saved_at_utc, payload)
	if not common_error.is_empty():
		return _invalid_create(str(common_error["field"]), str(common_error["reason"]), common_error.get("value"))
	var settings_error := _settings_payload_error(payload)
	if not settings_error.is_empty():
		return _invalid_create(str(settings_error["field"]), str(settings_error["reason"]), settings_error.get("value"))

	var document := {
		"magic": MAGIC,
		"schema_version": SCHEMA_VERSION,
		"document_kind": "settings",
		"sequence": sequence,
		"game_version": game_version,
		"created_at_utc": created_at_utc,
		"saved_at_utc": saved_at_utc,
		"payload": payload.duplicate(true),
	}
	return _finish_create(document)


static func validate(
	value: Variant,
	expected_document_kind: StringName = &"",
	expected_profile_id: String = "",
	expected_save_domain: String = ""
):
	if typeof(value) != TYPE_DICTIONARY:
		return _corrupt("document", "type")
	var document: Dictionary = (value as Dictionary).duplicate(true)
	if typeof(document.get("magic")) != TYPE_STRING or str(document.get("magic")) != MAGIC:
		return _corrupt("magic", "value")
	if not _is_integer_number(document.get("schema_version")):
		return _corrupt("schema_version", "type")
	var schema_version := int(document["schema_version"])
	if schema_version > SCHEMA_VERSION:
		return SaveResultScript.failure(
			&"FORWARD_VERSION",
			{"schema_version": schema_version, "supported_version": SCHEMA_VERSION}
		)
	if schema_version < 1:
		return _corrupt("schema_version", "value")
	if typeof(document.get("document_kind")) != TYPE_STRING:
		return _corrupt("document_kind", "type")

	var document_kind := str(document["document_kind"])
	if not VALID_DOCUMENT_KINDS.has(document_kind):
		return _corrupt("document_kind", "value")
	var expected_kind := str(expected_document_kind)
	if not expected_kind.is_empty() and not VALID_DOCUMENT_KINDS.has(expected_kind):
		return SaveResultScript.failure(
			&"INVALID_ARGUMENT",
			{"field": "expected_document_kind", "value": expected_kind}
		)
	if not expected_kind.is_empty() and document_kind != expected_kind:
		return _corrupt("document_kind", "unexpected", {"expected": expected_kind, "actual": document_kind})

	var expected_fields := PROFILE_FIELDS if document_kind == "profile" else SETTINGS_FIELDS
	if not _has_exact_fields(document, expected_fields):
		return _corrupt("document", "fields")
	var common_error := _common_document_error(document)
	if not common_error.is_empty():
		return _corrupt(str(common_error["field"]), str(common_error["reason"]), {"value": common_error.get("value")})

	if document_kind == "profile":
		var profile_error := _profile_document_error(document, expected_profile_id, expected_save_domain)
		if not profile_error.is_empty():
			return _corrupt(str(profile_error["field"]), str(profile_error["reason"]), {"value": profile_error.get("value")})
	else:
		if not expected_profile_id.is_empty() or not expected_save_domain.is_empty():
			return SaveResultScript.failure(
				&"INVALID_ARGUMENT",
				{"field": "expected_profile_scope", "reason": "settings-not-profile-scoped"}
			)
		var settings_error := _settings_payload_error(document["payload"])
		if not settings_error.is_empty():
			return _corrupt(str(settings_error["field"]), str(settings_error["reason"]), {"value": settings_error.get("value")})

	var integrity_error := _integrity_error(document)
	if not integrity_error.is_empty():
		return _corrupt(str(integrity_error["field"]), str(integrity_error["reason"]), {"value": integrity_error.get("value")})
	if document_kind == "profile":
		var normalized_payload := _normalize_profile_payload(document["payload"], schema_version)
		var payload_error := _profile_payload_error(normalized_payload, schema_version)
		if not payload_error.is_empty():
			return _corrupt(
				str(payload_error["field"]),
				str(payload_error["reason"]),
				{"value": payload_error.get("value")}
			)
		document["payload"] = normalized_payload
	return SaveResultScript.success(document)


static func reseal_current(document: Dictionary):
	if int(document.get("schema_version", -1)) != SCHEMA_VERSION:
		return SaveResultScript.failure(&"INVALID_ARGUMENT", {
			"field": "schema_version",
			"expected": SCHEMA_VERSION,
			"actual": document.get("schema_version"),
		})
	var unsigned := document.duplicate(true)
	unsigned.erase("integrity")
	return _finish_create(unsigned)


static func canonical_json(value: Variant) -> String:
	if not _is_json_compatible(value):
		return ""
	return JSON.stringify(value, "", true, true)


static func sha256_digest(value: Variant) -> String:
	var serialized := canonical_json(value)
	if serialized.is_empty():
		return ""
	return serialized.sha256_text()


static func content_snapshot_digest(packs_value: Variant) -> String:
	if typeof(packs_value) != TYPE_ARRAY:
		return ""
	var packs: Array = (packs_value as Array).duplicate(true)
	for pack_value: Variant in packs:
		if typeof(pack_value) != TYPE_DICTIONARY:
			return ""
	_sort_content_packs(packs)
	var normalized: Variant = _json_round_trip({"packs": packs})
	return sha256_digest(normalized)


static func _finish_create(document: Dictionary):
	var normalized_value: Variant = _json_round_trip(document)
	if typeof(normalized_value) != TYPE_DICTIONARY:
		return _invalid_create("document", "json-round-trip", null)
	var normalized_document: Dictionary = normalized_value
	var digest := sha256_digest(normalized_document)
	if digest.is_empty():
		return _invalid_create("integrity", "digest", null)
	normalized_document["integrity"] = {
		"algorithm": INTEGRITY_ALGORITHM,
		"digest": digest,
	}
	return SaveResultScript.success(normalized_document)


static func _common_create_error(
	sequence: int,
	game_version: String,
	created_at_utc: String,
	saved_at_utc: String,
	payload: Dictionary
) -> Dictionary:
	if sequence < 0:
		return {"field": "sequence", "reason": "minimum", "value": sequence}
	if game_version.is_empty():
		return {"field": "game_version", "reason": "empty", "value": game_version}
	if not _is_utc_timestamp(created_at_utc):
		return {"field": "created_at_utc", "reason": "format", "value": created_at_utc}
	if not _is_utc_timestamp(saved_at_utc):
		return {"field": "saved_at_utc", "reason": "format", "value": saved_at_utc}
	if created_at_utc > saved_at_utc:
		return {"field": "saved_at_utc", "reason": "before-created", "value": saved_at_utc}
	if not _is_json_compatible(payload):
		return {"field": "payload", "reason": "json-compatible"}
	return {}


static func _common_document_error(document: Dictionary) -> Dictionary:
	if not _is_integer_number(document["sequence"]) or int(document["sequence"]) < 0:
		return {"field": "sequence", "reason": "type-or-minimum", "value": document["sequence"]}
	if typeof(document["game_version"]) != TYPE_STRING or str(document["game_version"]).is_empty():
		return {"field": "game_version", "reason": "type-or-empty", "value": document["game_version"]}
	if typeof(document["created_at_utc"]) != TYPE_STRING or not _is_utc_timestamp(str(document["created_at_utc"])):
		return {"field": "created_at_utc", "reason": "format", "value": document["created_at_utc"]}
	if typeof(document["saved_at_utc"]) != TYPE_STRING or not _is_utc_timestamp(str(document["saved_at_utc"])):
		return {"field": "saved_at_utc", "reason": "format", "value": document["saved_at_utc"]}
	if str(document["created_at_utc"]) > str(document["saved_at_utc"]):
		return {"field": "saved_at_utc", "reason": "before-created", "value": document["saved_at_utc"]}
	if typeof(document["payload"]) != TYPE_DICTIONARY or not _is_json_compatible(document["payload"]):
		return {"field": "payload", "reason": "type-or-json-compatible"}
	return {}


static func _profile_document_error(
	document: Dictionary,
	expected_profile_id: String,
	expected_save_domain: String
) -> Dictionary:
	if not SavePathPolicyScript.validate_id(document["profile_id"], &"profile_id").ok:
		return {"field": "profile_id", "reason": "value", "value": document["profile_id"]}
	if not SavePathPolicyScript.validate_id(document["save_domain"], &"save_domain").ok:
		return {"field": "save_domain", "reason": "value", "value": document["save_domain"]}
	if not expected_profile_id.is_empty() and str(document["profile_id"]) != expected_profile_id:
		return {"field": "profile_id", "reason": "unexpected", "value": document["profile_id"]}
	if not expected_save_domain.is_empty() and str(document["save_domain"]) != expected_save_domain:
		return {"field": "save_domain", "reason": "unexpected", "value": document["save_domain"]}
	if typeof(document["content_snapshot"]) != TYPE_DICTIONARY:
		return {"field": "content_snapshot", "reason": "type", "value": typeof(document["content_snapshot"])}
	return _content_snapshot_error(document["content_snapshot"])


static func _profile_payload_error(payload: Dictionary, schema_version: int) -> Dictionary:
	if schema_version < 2:
		return {}
	if not payload.has("active_item_state"):
		return {"field": "payload.active_item_state", "reason": "missing"}
	if not payload["active_item_state"] is Dictionary:
		return {"field": "payload.active_item_state", "reason": "type"}
	if not bool(ActiveItemRuntimeScript.new().call(
		"can_restore_snapshot",
		(payload["active_item_state"] as Dictionary).duplicate(true)
	)):
		return {"field": "payload.active_item_state", "reason": "invalid"}
	if not payload.has("reward_effect_state"):
		return {"field": "payload.reward_effect_state", "reason": "missing"}
	if not payload["reward_effect_state"] is Dictionary:
		return {"field": "payload.reward_effect_state", "reason": "type"}
	var reward_state := payload["reward_effect_state"] as Dictionary
	if (
		not reward_state.is_empty()
		and not ReplayRecorderScript.validate_full_player_reward_effect_state(reward_state)
	):
		return {"field": "payload.reward_effect_state", "reason": "invalid"}
	if schema_version < 3:
		return {}
	if not payload.has("active_run_state"):
		return {"field": "payload.active_run_state", "reason": "missing"}
	var active_run_error := _active_run_state_error(payload["active_run_state"])
	if not active_run_error.is_empty():
		return active_run_error
	return {}


static func _normalize_profile_payload(payload: Dictionary, schema_version: int) -> Dictionary:
	var normalized := payload.duplicate(true)
	if schema_version < 2:
		return normalized
	var runtime_fields: Array[String] = ["active_item_state", "reward_effect_state"]
	if schema_version >= 3:
		runtime_fields.append("active_run_state")
	for field: String in runtime_fields:
		if normalized.get(field) is Dictionary:
			normalized[field] = _normalize_persisted_integer_fields(
				normalized[field],
				field
			)
	return normalized


static func _normalize_persisted_integer_fields(value: Variant, parent_field: String) -> Variant:
	const INTEGER_FIELDS: Array[String] = [
		"schema_version", "profile_version", "generation", "next_token",
		"current_frame", "cooldown_end_frame", "token", "runtime_frame",
		"activated_at_frame", "expires_at_frame", "resource_revision",
		"invulnerability_token",
		"duration_frames", "cooldown_frames", "charges", "max_charges",
		"combo_step", "launch_combo_step", "combo_timeout_remaining",
		"last_runtime_frame", "active_token", "combo_index", "ammo",
		"time_load_remaining_frames", "reload_frame", "combo_remaining_frames",
		"claimed_rewind_generation_floor", "chain_step", "combo_count",
		"combo_timeout_frames_remaining", "action_token_floor",
		"aura_source_generation", "source_token", "payload_generation",
		"remaining_frames", "capture_sequence", "sequence", "frame",
		"current_token", "revision", "next_sample_sequence",
		"cooldown_remaining_frames", "damage_attack_generation",
		"damage_action_token", "guard_generation", "guard_elapsed_frames",
		"next_fallback_attack_generation", "phase", "run_seed", "current_floor",
		"current_room", "room_total", "run_time_ms", "current_floor_index",
		"floor_index", "layer", "choice_order", "kills", "seed",
	]
	const INTEGER_ARRAY_FIELDS: Array[String] = [
		"reward_invulnerability_tokens", "claimed_rewind_generations",
		"reward_eligible_tokens", "reward_claimed_tokens",
	]
	const INTEGER_MAP_FIELDS: Array[String] = [
		"resource_regen_frame_accumulators",
		"reward_invulnerability_remaining",
		"archetypes",
	]
	if typeof(value) == TYPE_STRING_NAME and parent_field == "code":
		return str(value)
	if value is Array:
		var normalized_array: Array = []
		for child: Variant in value as Array:
			if INTEGER_ARRAY_FIELDS.has(parent_field) and _is_integer_number(child):
				normalized_array.append(int(child))
			else:
				normalized_array.append(
					_normalize_persisted_integer_fields(child, parent_field)
				)
		return normalized_array
	if not value is Dictionary:
		return value
	var normalized := {}
	for key_value: Variant in (value as Dictionary).keys():
		var key := str(key_value)
		var child: Variant = (value as Dictionary)[key_value]
		if (
			(INTEGER_FIELDS.has(key) or INTEGER_MAP_FIELDS.has(parent_field))
			and _is_integer_number(child)
		):
			normalized[key] = int(child)
		else:
			normalized[key] = _normalize_persisted_integer_fields(child, key)
	return normalized


static func _active_run_state_error(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _run_error("", "type")
	var run := value as Dictionary
	if run.is_empty():
		return {}
	if not _has_exact_fields(run, ACTIVE_RUN_FIELDS):
		return _run_error("", "fields")
	if typeof(run["schema_version"]) != TYPE_INT or int(run["schema_version"]) != 1:
		return _run_error("schema_version", "value")
	if typeof(run["run_id"]) != TYPE_STRING or not _stable_identifier_is_valid(str(run["run_id"]), 96):
		return _run_error("run_id", "value")
	for field: String in ["revision", "run_seed", "current_floor", "current_room", "room_total", "run_time_ms"]:
		if typeof(run[field]) != TYPE_INT:
			return _run_error(field, "type")
	for field: String in ["revision", "current_room", "run_time_ms"]:
		if int(run[field]) < 0:
			return _run_error(field, "range")
	for field: String in ["current_floor", "room_total"]:
		if int(run[field]) < 1:
			return _run_error(field, "range")
	if typeof(run["phase"]) != TYPE_INT or int(run["phase"]) < 0 or int(run["phase"]) > 11:
		return _run_error("phase", "range")
	if typeof(run["suspended"]) != TYPE_BOOL:
		return _run_error("suspended", "type")
	for field: String in [
		"resources", "stats", "build", "open_offer", "result", "config",
		"floor_plan", "run_economy", "merchant_state", "floor_rule_state",
	]:
		if not run[field] is Dictionary:
			return _run_error(field, "type")
	if not run["events"] is Array:
		return _run_error("events", "type")
	var consumed_error := _offer_unique_string_array_error(
		run["consumed_offer_ids"], "consumed_offer_ids"
	)
	if not consumed_error.is_empty():
		return consumed_error
	if typeof(run["current_floor_index"]) != TYPE_INT:
		return _run_error("current_floor_index", "type")
	var completed_error := _stable_unique_string_array_error(
		run["completed_floor_ids"], "completed_floor_ids"
	)
	if not completed_error.is_empty():
		return completed_error
	var event_error := _stable_unique_string_array_error(run["seen_event_ids"], "seen_event_ids")
	if not event_error.is_empty():
		return event_error

	var config := run["config"] as Dictionary
	if typeof(config.get("milestone")) != TYPE_STRING:
		return _run_error("config.milestone", "type")
	var milestone := str(config["milestone"])
	if milestone not in ["M1", "CURRENT", "NEXT", "LAUNCH", "EXPANSION"]:
		return _run_error("config.milestone", "value")
	var floor_index := int(run["current_floor_index"])
	var floor_plan := run["floor_plan"] as Dictionary
	var completed: Array = run["completed_floor_ids"]
	if not FLOOR_PLAN_MILESTONES.has(milestone):
		if (
			floor_index != -1
			or not floor_plan.is_empty()
			or not completed.is_empty()
			or not (run["run_economy"] as Dictionary).is_empty()
			or not (run["seen_event_ids"] as Array).is_empty()
			or not (run["merchant_state"] as Dictionary).is_empty()
			or not (run["floor_rule_state"] as Dictionary).is_empty()
		):
			return _run_error("floor_plan", "non_launch_state")
		return {}

	if floor_plan.is_empty():
		if floor_index != -1:
			return _run_error("current_floor_index", "plan_missing")
		if not completed.is_empty():
			return _run_error("completed_floor_ids", "before_floor_prefix")
		if (
			not (run["run_economy"] as Dictionary).is_empty()
			or not (run["seen_event_ids"] as Array).is_empty()
			or not (run["merchant_state"] as Dictionary).is_empty()
			or not (run["floor_rule_state"] as Dictionary).is_empty()
		):
			return _run_error("floor_plan", "before_floor_state")
		return {}
	if floor_index < 0 or floor_index >= FLOOR_IDS.size():
		return _run_error("current_floor_index", "range")
	if typeof(floor_plan.get("floor_index")) != TYPE_INT or int(floor_plan["floor_index"]) != floor_index:
		return _run_error("current_floor_index", "plan_mismatch")
	if int(run["current_floor"]) != floor_index + 1:
		return _run_error("current_floor", "floor_index_mismatch")
	var prior_completed: Array[String] = []
	for index: int in range(floor_index):
		prior_completed.append(FLOOR_IDS[index])
	var current_completed := prior_completed.duplicate()
	current_completed.append(FLOOR_IDS[floor_index])
	if completed != prior_completed and completed != current_completed:
		return _run_error("completed_floor_ids", "prefix_mismatch")
	var floor_plan_error := _floor_plan_error(floor_plan, int(run["run_seed"]))
	if not floor_plan_error.is_empty():
		return floor_plan_error
	if str(floor_plan["floor_id"]) != FLOOR_IDS[floor_index]:
		return _run_error("floor_plan.floor_id", "index_mismatch")
	if int(run["current_room"]) != (floor_plan["selected_edge_ids"] as Array).size():
		return _run_error("current_room", "plan_mismatch")
	var boss_node := _plan_node(floor_plan, str(floor_plan["boss_node_id"]))
	if boss_node.is_empty() or int(run["room_total"]) != int(boss_node["layer"]):
		return _run_error("room_total", "plan_mismatch")
	if completed == current_completed and (
		str(floor_plan["current_node_id"]) != str(floor_plan["boss_node_id"])
		or not bool(boss_node["cleared"])
	):
		return _run_error("completed_floor_ids", "current_floor_not_complete")
	return {}


static func _floor_plan_error(plan: Dictionary, run_seed: int) -> Dictionary:
	if not _has_exact_fields(plan, FloorPlanScript.ROOT_FIELDS):
		return _run_error("floor_plan", "fields")
	if typeof(plan["schema_version"]) != TYPE_INT or int(plan["schema_version"]) != FloorPlanScript.SCHEMA_VERSION:
		return _run_error("floor_plan.schema_version", "value")
	if typeof(plan["generator_version"]) != TYPE_STRING or str(plan["generator_version"]) != FloorPlanScript.GENERATOR_VERSION:
		return _run_error("floor_plan.generator_version", "value")
	for field: String in ["run_seed", "floor_index", "revision"]:
		if typeof(plan[field]) != TYPE_INT:
			return _run_error("floor_plan.%s" % field, "type")
	if int(plan["run_seed"]) != run_seed:
		return _run_error("floor_plan.run_seed", "run_mismatch")
	if int(plan["floor_index"]) < 0 or int(plan["floor_index"]) >= FLOOR_IDS.size():
		return _run_error("floor_plan.floor_index", "range")
	if int(plan["revision"]) < 0:
		return _run_error("floor_plan.revision", "range")
	for field: String in ["floor_id", "entry_node_id", "boss_node_id", "current_node_id"]:
		if typeof(plan[field]) != TYPE_STRING or not _route_identifier_is_valid(str(plan[field])):
			return _run_error("floor_plan.%s" % field, "value")
	if str(plan["entry_node_id"]) != "entry" or str(plan["boss_node_id"]) != "boss":
		return _run_error("floor_plan.entry_node_id", "canonical_ids")
	for field: String in ["nodes", "edges", "selected_edge_ids", "visited_node_ids", "abandoned_node_ids"]:
		if not plan[field] is Array:
			return _run_error("floor_plan.%s" % field, "type")

	var nodes_by_id: Dictionary = {}
	for index: int in range((plan["nodes"] as Array).size()):
		var node_value: Variant = (plan["nodes"] as Array)[index]
		if not node_value is Dictionary:
			return _run_error("floor_plan.nodes[%d]" % index, "type")
		var node := node_value as Dictionary
		if not _has_exact_fields(node, FloorPlanScript.NODE_FIELDS):
			return _run_error("floor_plan.nodes[%d]" % index, "fields")
		for field: String in ["id", "room_type", "template_id", "encounter_id", "event_id", "merchant_id", "reward_policy_id", "seed_channel_suffix"]:
			if typeof(node[field]) != TYPE_STRING:
				return _run_error("floor_plan.nodes[%d].%s" % [index, field], "type")
		if not _route_identifier_is_valid(str(node["id"])) or nodes_by_id.has(str(node["id"])):
			return _run_error("floor_plan.nodes[%d].id" % index, "invalid_or_duplicate")
		if typeof(node["layer"]) != TYPE_INT or int(node["layer"]) < 0:
			return _run_error("floor_plan.nodes[%d].layer" % index, "type_or_range")
		for field: String in ["revealed", "visited", "cleared"]:
			if typeof(node[field]) != TYPE_BOOL:
				return _run_error("floor_plan.nodes[%d].%s" % [index, field], "type")
		nodes_by_id[str(node["id"])] = node
	if not nodes_by_id.has("entry") or not nodes_by_id.has("boss") or not nodes_by_id.has(str(plan["current_node_id"])):
		return _run_error("floor_plan.nodes", "required_node_missing")
	var entry_node := nodes_by_id["entry"] as Dictionary
	var boss_node := nodes_by_id["boss"] as Dictionary
	if int(entry_node["layer"]) != 0 or str(entry_node["room_type"]) != "entry":
		return _run_error("floor_plan.nodes", "entry_identity")
	if int(boss_node["layer"]) < 1 or str(boss_node["room_type"]) != "boss":
		return _run_error("floor_plan.nodes", "boss_identity")
	for node_id_value: Variant in nodes_by_id.keys():
		var node := nodes_by_id[node_id_value] as Dictionary
		if str(node_id_value) != "boss" and str(node["room_type"]) == "boss":
			return _run_error("floor_plan.nodes", "boss_identity")
		if int(node["layer"]) > int(boss_node["layer"]):
			return _run_error("floor_plan.nodes", "layer_range")

	var edges_by_id: Dictionary = {}
	var outgoing: Dictionary = {}
	var incoming: Dictionary = {}
	for node_id_value: Variant in nodes_by_id.keys():
		outgoing[str(node_id_value)] = []
		incoming[str(node_id_value)] = []
	for index: int in range((plan["edges"] as Array).size()):
		var edge_value: Variant = (plan["edges"] as Array)[index]
		if not edge_value is Dictionary:
			return _run_error("floor_plan.edges[%d]" % index, "type")
		var edge := edge_value as Dictionary
		if not _has_exact_fields(edge, FloorPlanScript.EDGE_FIELDS):
			return _run_error("floor_plan.edges[%d]" % index, "fields")
		for field: String in ["id", "source_node_id", "destination_node_id"]:
			if typeof(edge[field]) != TYPE_STRING or not _route_identifier_is_valid(str(edge[field])):
				return _run_error("floor_plan.edges[%d].%s" % [index, field], "value")
		var edge_id := str(edge["id"])
		var source_id := str(edge["source_node_id"])
		var destination_id := str(edge["destination_node_id"])
		if edges_by_id.has(edge_id):
			return _run_error("floor_plan.edges[%d].id" % index, "duplicate")
		if not nodes_by_id.has(source_id) or not nodes_by_id.has(destination_id):
			return _run_error("floor_plan.edges[%d]" % index, "unknown_node")
		if int((nodes_by_id[destination_id] as Dictionary)["layer"]) != int((nodes_by_id[source_id] as Dictionary)["layer"]) + 1:
			return _run_error("floor_plan.edges[%d]" % index, "layer_mismatch")
		if typeof(edge["choice_order"]) != TYPE_INT or int(edge["choice_order"]) < 0:
			return _run_error("floor_plan.edges[%d].choice_order" % index, "type_or_range")
		if typeof(edge["locked"]) != TYPE_BOOL:
			return _run_error("floor_plan.edges[%d].locked" % index, "type")
		if not edge["route_summary_facts"] is Dictionary:
			return _run_error("floor_plan.edges[%d].route_summary_facts" % index, "type")
		var facts := edge["route_summary_facts"] as Dictionary
		if not _has_exact_fields(facts, FloorPlanScript.ROUTE_SUMMARY_FIELDS):
			return _run_error("floor_plan.edges[%d].route_summary_facts" % index, "fields")
		var destination := nodes_by_id[destination_id] as Dictionary
		if str(facts.get("room_type", "")) != str(destination["room_type"]) or str(facts.get("template_id", "")) != str(destination["template_id"]):
			return _run_error("floor_plan.edges[%d].route_summary_facts" % index, "destination_mismatch")
		edges_by_id[edge_id] = edge
		(outgoing[source_id] as Array).append(edge)
		(incoming[destination_id] as Array).append(edge)
	if not (incoming["entry"] as Array).is_empty() or not (outgoing["boss"] as Array).is_empty():
		return _run_error("floor_plan.edges", "terminal_direction")
	for node_id_value: Variant in nodes_by_id.keys():
		var node_id := str(node_id_value)
		if node_id != "entry" and (incoming[node_id] as Array).is_empty():
			return _run_error("floor_plan.edges", "orphan_node")
		if node_id != "boss" and (outgoing[node_id] as Array).is_empty():
			return _run_error("floor_plan.edges", "dead_end_node")
		if (outgoing[node_id] as Array).size() > 3:
			return _run_error("floor_plan.edges", "too_many_choices")
		var choice_orders: Array[int] = []
		for edge_value: Variant in outgoing[node_id]:
			choice_orders.append(int((edge_value as Dictionary)["choice_order"]))
		choice_orders.sort()
		for order_index: int in range(choice_orders.size()):
			if choice_orders[order_index] != order_index:
				return _run_error("floor_plan.edges", "choice_order")
	if _reachable_ids("entry", outgoing, false).size() != nodes_by_id.size():
		return _run_error("floor_plan.edges", "unreachable_node")
	if _reachable_ids("boss", incoming, true).size() != nodes_by_id.size():
		return _run_error("floor_plan.edges", "boss_unreachable")

	for field: String in ["selected_edge_ids", "visited_node_ids", "abandoned_node_ids"]:
		var known := edges_by_id if field == "selected_edge_ids" else nodes_by_id
		var array_error := _known_unique_route_array_error(plan[field], known, "floor_plan.%s" % field)
		if not array_error.is_empty():
			return array_error
	var cursor := str(plan["entry_node_id"])
	var expected_visited: Array[String] = [cursor]
	for selected_id_value: Variant in plan["selected_edge_ids"]:
		var selected := edges_by_id[str(selected_id_value)] as Dictionary
		if bool(selected["locked"]) or str(selected["source_node_id"]) != cursor:
			return _run_error("floor_plan.selected_edge_ids", "route_prefix")
		cursor = str(selected["destination_node_id"])
		expected_visited.append(cursor)
	if cursor != str(plan["current_node_id"]) or (plan["visited_node_ids"] as Array) != expected_visited:
		return _run_error("floor_plan.visited_node_ids", "route_prefix")
	if int(plan["revision"]) != (plan["selected_edge_ids"] as Array).size():
		return _run_error("floor_plan.revision", "route_prefix")
	for node_id_value: Variant in nodes_by_id.keys():
		var node := nodes_by_id[node_id_value] as Dictionary
		var expected_visit := expected_visited.has(str(node_id_value))
		if bool(node["visited"]) != expected_visit or (expected_visit and not bool(node["revealed"])):
			return _run_error("floor_plan.nodes", "visit_flags")
	var reachable_from_current := _reachable_ids(str(plan["current_node_id"]), outgoing, false)
	var expected_abandoned: Array[String] = []
	for node_value: Variant in plan["nodes"]:
		var node_id := str((node_value as Dictionary)["id"])
		if not reachable_from_current.has(node_id) and not expected_visited.has(node_id):
			expected_abandoned.append(node_id)
	if (plan["abandoned_node_ids"] as Array) != expected_abandoned:
		return _run_error("floor_plan.abandoned_node_ids", "route_prefix")
	if typeof(plan["generation_digest"]) != TYPE_STRING or not _is_sha256_hex(str(plan["generation_digest"])):
		return _run_error("floor_plan.generation_digest", "format")
	if str(plan["generation_digest"]) != FloorPlanScript.compute_generation_digest(plan):
		return _run_error("floor_plan.generation_digest", "mismatch")
	return {}


static func _reachable_ids(start_id: String, adjacency: Dictionary, reverse: bool) -> Dictionary:
	var reached: Dictionary = {}
	var pending: Array[String] = [start_id]
	while not pending.is_empty():
		var node_id: String = pending.pop_front()
		if reached.has(node_id):
			continue
		reached[node_id] = true
		for edge_value: Variant in adjacency.get(node_id, []):
			var edge := edge_value as Dictionary
			var next_id := str(edge["source_node_id"] if reverse else edge["destination_node_id"])
			if not reached.has(next_id):
				pending.append(next_id)
	return reached


static func _plan_node(plan: Dictionary, node_id: String) -> Dictionary:
	for node_value: Variant in plan.get("nodes", []):
		if node_value is Dictionary and str((node_value as Dictionary).get("id", "")) == node_id:
			return (node_value as Dictionary).duplicate(true)
	return {}


static func _stable_unique_string_array_error(value: Variant, field: String) -> Dictionary:
	if not value is Array:
		return _run_error(field, "type")
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var item: Variant = (value as Array)[index]
		if typeof(item) != TYPE_STRING or not _stable_identifier_is_valid(str(item), 96):
			return _run_error("%s[%d]" % [field, index], "value")
		if seen.has(str(item)):
			return _run_error(field, "duplicate")
		seen[str(item)] = true
	return {}


static func _offer_unique_string_array_error(value: Variant, field: String) -> Dictionary:
	if not value is Array:
		return _run_error(field, "type")
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var item: Variant = (value as Array)[index]
		if typeof(item) != TYPE_STRING or not _offer_identifier_is_valid(str(item)):
			return _run_error("%s[%d]" % [field, index], "value")
		if seen.has(str(item)):
			return _run_error(field, "duplicate")
		seen[str(item)] = true
	return {}


static func _known_unique_route_array_error(
	value: Variant,
	known: Dictionary,
	field: String
) -> Dictionary:
	if not value is Array:
		return _run_error(field, "type")
	var seen: Dictionary = {}
	for index: int in range((value as Array).size()):
		var item: Variant = (value as Array)[index]
		if typeof(item) != TYPE_STRING or not _route_identifier_is_valid(str(item)):
			return _run_error("%s[%d]" % [field, index], "value")
		if seen.has(str(item)):
			return _run_error(field, "duplicate")
		if not known.has(str(item)):
			return _run_error("%s[%d]" % [field, index], "unknown")
		seen[str(item)] = true
	return {}


static func _run_error(field: String, reason: String) -> Dictionary:
	var suffix := "" if field.is_empty() else ".%s" % field
	return {"field": "payload.active_run_state%s" % suffix, "reason": reason}


static func empty_active_item_state() -> Dictionary:
	return {
		"schema_version": 1,
		"configured": false,
		"definition": {},
		"generation": 0,
		"next_token": 1,
		"current_frame": -1,
		"cooldown_end_frame": -1,
		"handler_state": {},
		"committed_receipts": {},
	}


static func _content_snapshot_error(snapshot: Dictionary) -> Dictionary:
	if not _has_exact_fields(snapshot, CONTENT_SNAPSHOT_FIELDS):
		return {"field": "content_snapshot", "reason": "fields"}
	if typeof(snapshot["aggregate_sha256"]) != TYPE_STRING or not _is_sha256_hex(str(snapshot["aggregate_sha256"])):
		return {"field": "content_snapshot.aggregate_sha256", "reason": "value", "value": snapshot["aggregate_sha256"]}
	if typeof(snapshot["packs"]) != TYPE_ARRAY or snapshot["packs"].is_empty():
		return {"field": "content_snapshot.packs", "reason": "type-or-empty"}

	var packs: Array = snapshot["packs"]
	var pack_records: Dictionary = {}
	for index: int in range(packs.size()):
		var pack_value: Variant = packs[index]
		if typeof(pack_value) != TYPE_DICTIONARY:
			return {"field": "content_snapshot.packs[%d]" % index, "reason": "type"}
		var pack: Dictionary = pack_value
		if not _has_exact_fields(pack, CONTENT_PACK_FIELDS):
			return {"field": "content_snapshot.packs[%d]" % index, "reason": "fields"}
		if not _identifier_is_valid(pack["pack_id"], 64):
			return {"field": "content_snapshot.packs[%d].pack_id" % index, "reason": "value", "value": pack["pack_id"]}
		if typeof(pack["pack_version"]) != TYPE_STRING or str(pack["pack_version"]).is_empty():
			return {"field": "content_snapshot.packs[%d].pack_version" % index, "reason": "type-or-empty"}
		if not _is_integer_number(pack["schema_version"]) or int(pack["schema_version"]) < 1:
			return {"field": "content_snapshot.packs[%d].schema_version" % index, "reason": "type-or-minimum"}
		if typeof(pack["fingerprint_sha256"]) != TYPE_STRING or not _is_sha256_hex(str(pack["fingerprint_sha256"])):
			return {"field": "content_snapshot.packs[%d].fingerprint_sha256" % index, "reason": "value"}
		var record_key := canonical_json(pack)
		if pack_records.has(record_key):
			return {"field": "content_snapshot.packs", "reason": "duplicate"}
		pack_records[record_key] = true

	var sorted_packs: Array = packs.duplicate(true)
	_sort_content_packs(sorted_packs)
	if packs != sorted_packs:
		return {"field": "content_snapshot.packs", "reason": "not-sorted"}
	var aggregate := content_snapshot_digest(packs)
	if aggregate != str(snapshot["aggregate_sha256"]):
		return {
			"field": "content_snapshot.aggregate_sha256",
			"reason": "mismatch",
			"value": snapshot["aggregate_sha256"],
		}
	return {}


static func _settings_payload_error(payload: Dictionary) -> Dictionary:
	if not _has_required_fields(payload, LEGACY_SETTINGS_REQUIRED_FIELDS):
		return {"field": "payload", "reason": "missing-required-fields"}
	if not _has_only_known_fields(payload, SETTINGS_PAYLOAD_FIELDS):
		return {"field": "payload", "reason": "unknown-fields"}
	if typeof(payload["locale"]) != TYPE_STRING or str(payload["locale"]) not in ["zh_CN", "en"]:
		return {"field": "payload.locale", "reason": "value", "value": payload["locale"]}
	for field: String in ["master_volume", "music_volume", "sfx_volume", "dialogue_volume"]:
		if not payload.has(field):
			continue
		var volume_error := _finite_range_error(payload[field], "payload.%s" % field, 0.0, 1.0)
		if not volume_error.is_empty():
			return volume_error
	for field: String in [
		"master_muted",
		"camera_shake_enabled",
		"hit_flash_enabled",
		"reduced_motion",
		"high_contrast_danger",
		"subtitles_enabled",
	]:
		if not payload.has(field):
			continue
		if typeof(payload[field]) != TYPE_BOOL:
			return {"field": "payload.%s" % field, "reason": "type", "value": payload[field]}
	for field: String in ["text_scale", "subtitle_scale"]:
		if payload.has(field) and not _number_is_one_of(payload[field], [1.0, 1.25, 1.5]):
			return {"field": "payload.%s" % field, "reason": "value", "value": payload[field]}
	if payload.has("ranged_charge_mode") and (
		typeof(payload["ranged_charge_mode"]) != TYPE_STRING
		or str(payload["ranged_charge_mode"]) not in ["hold", "toggle"]
	):
		return {"field": "payload.ranged_charge_mode", "reason": "value", "value": payload["ranged_charge_mode"]}
	if payload.has("damage_received_multiplier") and not _number_is_one_of(payload["damage_received_multiplier"], [1.0, 0.8, 0.6]):
		return {"field": "payload.damage_received_multiplier", "reason": "value", "value": payload["damage_received_multiplier"]}
	if payload.has("enemy_telegraph_scale") and not _number_is_one_of(payload["enemy_telegraph_scale"], [1.0, 1.25, 1.5]):
		return {"field": "payload.enemy_telegraph_scale", "reason": "value", "value": payload["enemy_telegraph_scale"]}
	return {}


static func _finite_range_error(value: Variant, field: String, minimum: float, maximum: float) -> Dictionary:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return {"field": field, "reason": "type", "value": value}
	var numeric := float(value)
	if not is_finite(numeric) or numeric < minimum or numeric > maximum:
		return {"field": field, "reason": "range", "value": value}
	return {}


static func _number_is_one_of(value: Variant, allowed: Array[float]) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric in allowed


static func _integrity_error(document: Dictionary) -> Dictionary:
	if typeof(document["integrity"]) != TYPE_DICTIONARY:
		return {"field": "integrity", "reason": "type"}
	var integrity: Dictionary = document["integrity"]
	if not _has_exact_fields(integrity, ["algorithm", "digest"]):
		return {"field": "integrity", "reason": "fields"}
	if typeof(integrity["algorithm"]) != TYPE_STRING or str(integrity["algorithm"]) != INTEGRITY_ALGORITHM:
		return {"field": "integrity.algorithm", "reason": "value", "value": integrity["algorithm"]}
	if typeof(integrity["digest"]) != TYPE_STRING or not _is_sha256_hex(str(integrity["digest"])):
		return {"field": "integrity.digest", "reason": "value", "value": integrity["digest"]}
	var unsigned_document := document.duplicate(true)
	unsigned_document.erase("integrity")
	var actual_digest := sha256_digest(unsigned_document)
	if actual_digest != str(integrity["digest"]):
		return {
			"field": "integrity.digest",
			"reason": "mismatch",
			"value": integrity["digest"],
			"actual": actual_digest,
		}
	return {}


static func _has_exact_fields(value: Dictionary, expected_fields: Array) -> bool:
	if value.size() != expected_fields.size():
		return false
	for field: Variant in expected_fields:
		if not value.has(field):
			return false
	return true


static func _has_required_fields(value: Dictionary, required_fields: Array) -> bool:
	for field: Variant in required_fields:
		if not value.has(field):
			return false
	return true


static func _has_only_known_fields(value: Dictionary, known_fields: Array) -> bool:
	for field: Variant in value.keys():
		if not known_fields.has(field):
			return false
	return true


static func _sort_content_packs(packs: Array) -> void:
	packs.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return _content_pack_sort_key(left) < _content_pack_sort_key(right)
	)


static func _content_pack_sort_key(pack: Dictionary) -> String:
	return "%s\u001f%s\u001f%010d\u001f%s" % [
		str(pack.get("pack_id", "")),
		str(pack.get("pack_version", "")),
		int(pack.get("schema_version", 0)),
		str(pack.get("fingerprint_sha256", "")),
	]


static func _identifier_is_valid(value: Variant, max_length: int) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var identifier := str(value)
	if identifier.is_empty() or identifier.length() > max_length:
		return false
	if not _is_lower_ascii_alphanumeric(identifier.unicode_at(0)):
		return false
	for index: int in range(1, identifier.length()):
		var codepoint := identifier.unicode_at(index)
		if not _is_lower_ascii_alphanumeric(codepoint) and codepoint not in [45, 95]:
			return false
	return true


static func _stable_identifier_is_valid(value: Variant, max_length: int) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var identifier := str(value)
	if identifier.is_empty() or identifier.length() > max_length:
		return false
	if not _is_lower_ascii_alphanumeric(identifier.unicode_at(0)):
		return false
	for index: int in range(1, identifier.length()):
		var codepoint := identifier.unicode_at(index)
		if not _is_lower_ascii_alphanumeric(codepoint) and codepoint not in [45, 46, 95]:
			return false
	return true


static func _route_identifier_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var identifier := str(value)
	if identifier.is_empty() or identifier.length() > 96:
		return false
	for index: int in range(identifier.length()):
		var codepoint := identifier.unicode_at(index)
		if not _is_lower_ascii_alphanumeric(codepoint) and codepoint not in [45, 46, 95]:
			return false
	return true


static func _offer_identifier_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var identifier := str(value)
	if identifier.is_empty() or identifier.length() > 192:
		return false
	if not _is_lower_ascii_alphanumeric(identifier.unicode_at(0)):
		return false
	for index: int in range(1, identifier.length()):
		var codepoint := identifier.unicode_at(index)
		if not _is_lower_ascii_alphanumeric(codepoint) and codepoint not in [45, 46, 58, 95]:
			return false
	return true


static func _is_utc_timestamp(value: String) -> bool:
	if value.length() != 20:
		return false
	if value.substr(4, 1) != "-" or value.substr(7, 1) != "-":
		return false
	if value.substr(10, 1) != "T" or value.substr(13, 1) != ":" or value.substr(16, 1) != ":" or value.substr(19, 1) != "Z":
		return false
	for index: int in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]:
		var codepoint := value.unicode_at(index)
		if codepoint < 48 or codepoint > 57:
			return false
	var year := int(value.substr(0, 4))
	var month := int(value.substr(5, 2))
	var day := int(value.substr(8, 2))
	var hour := int(value.substr(11, 2))
	var minute := int(value.substr(14, 2))
	var second := int(value.substr(17, 2))
	if year <= 0 or month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59:
		return false
	var month_days: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if month == 2 and _is_leap_year(year):
		month_days[1] = 29
	return day >= 1 and day <= month_days[month - 1]


static func _is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)


static func _is_json_compatible(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for child: Variant in value:
				if not _is_json_compatible(child):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in (value as Dictionary).keys():
				if typeof(key) != TYPE_STRING or not _is_json_compatible((value as Dictionary)[key]):
					return false
			return true
		_:
			return false


static func _json_round_trip(value: Variant) -> Variant:
	var serialized := canonical_json(value)
	if serialized.is_empty():
		return null
	var parser := JSON.new()
	if parser.parse(serialized) != OK:
		return null
	return parser.data


static func _is_sha256_hex(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var codepoint := value.unicode_at(index)
		if not ((codepoint >= 48 and codepoint <= 57) or (codepoint >= 97 and codepoint <= 102)):
			return false
	return true


static func _is_integer_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == floorf(numeric)


static func _is_lower_ascii_alphanumeric(codepoint: int) -> bool:
	return (codepoint >= 97 and codepoint <= 122) or (codepoint >= 48 and codepoint <= 57)


static func _invalid_create(field: String, reason: String, value: Variant):
	return SaveResultScript.failure(
		&"INVALID_ARGUMENT",
		{"field": field, "reason": reason, "value": value}
	)


static func _corrupt(field: String, reason: String, context: Dictionary = {}):
	var metadata := context.duplicate(true)
	metadata["field"] = field
	metadata["reason"] = reason
	return SaveResultScript.failure(&"CORRUPT", metadata)
