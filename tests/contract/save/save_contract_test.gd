extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")

const CONTRACT_PATH := "res://docs/contracts/save-service-v2.md"
const PROFILE_SCHEMA_PATH := "res://data/schemas/save_profile_v2.schema.json"
const SETTINGS_SCHEMA_PATH := "res://data/schemas/save_settings_v2.schema.json"
const FIXTURE_ROOT := "res://tests/fixtures/save"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_contract_document(suite)
	_test_profile_schema(suite)
	_test_settings_schema(suite)
	_test_profile_fixtures(suite)
	_test_pack_fingerprint_fixtures(suite)
	suite.finish(get_tree())


func _test_contract_document(suite) -> void:
	var text := _read_text(CONTRACT_PATH, suite)
	if text.is_empty():
		return
	for required_term: String in [
		"temp write",
		"integrity verification",
		"backup rotation",
		"forward-version refusal",
		"ordered migration",
		"corruption recovery",
		"profile isolation",
		"content-pack fingerprint",
		"deterministic fixtures",
		"normative for the envelope",
		"opaque-but-runtime-validated",
	]:
		suite.assert_true(
			text.to_lower().contains(required_term),
			"save contract defines %s" % required_term
		)


func _test_profile_schema(suite) -> void:
	var schema := _read_json(PROFILE_SCHEMA_PATH, suite)
	if schema.is_empty():
		return
	suite.assert_equal(schema.get("$id"), "planewalker://schemas/save-profile/2.0.0", "profile schema id is stable")
	suite.assert_equal(schema.get("additionalProperties"), false, "profile envelope rejects unknown top-level fields")
	var properties: Dictionary = schema.get("properties", {})
	suite.assert_equal(properties.get("magic", {}).get("const"), "PWSAVE", "profile magic is fixed")
	suite.assert_equal(properties.get("schema_version", {}).get("const"), 2, "profile schema version is explicit")
	suite.assert_equal(properties.get("document_kind", {}).get("const"), "profile", "profile kind is fixed")
	suite.assert_equal(properties.get("profile_id", {}).get("pattern"), "^[a-z0-9][a-z0-9_-]{0,31}$", "profile id blocks path traversal")
	suite.assert_equal(properties.get("save_domain", {}).get("pattern"), "^[a-z0-9][a-z0-9_-]{0,31}$", "save domain blocks path traversal")
	suite.assert_equal(properties.get("integrity", {}).get("$ref"), "#/$defs/integrity", "profile integrity uses shared contract")
	suite.assert_equal(properties.get("content_snapshot", {}).get("$ref"), "#/$defs/content_snapshot", "profile records active content packs")
	_assert_required_fields(
		suite,
		schema,
		[
			"magic", "schema_version", "document_kind", "profile_id", "save_domain",
			"sequence", "game_version", "created_at_utc", "saved_at_utc",
			"content_snapshot", "payload", "integrity",
		],
		"profile schema"
	)
	var definitions: Dictionary = schema.get("$defs", {})
	var payload: Dictionary = properties.get("payload", {})
	suite.assert_true(
		(payload.get("required", []) as Array).has("active_item_state"),
		"profile v2 requires active-item runtime state"
	)
	suite.assert_true(
		(payload.get("required", []) as Array).has("reward_effect_state"),
		"profile v2 requires reward-effect runtime state"
	)
	var integrity: Dictionary = definitions.get("integrity", {})
	suite.assert_equal(integrity.get("additionalProperties"), false, "integrity object is closed")
	suite.assert_equal(integrity.get("properties", {}).get("algorithm", {}).get("const"), "sha256", "integrity algorithm is explicit")
	var snapshot: Dictionary = definitions.get("content_snapshot", {})
	suite.assert_equal(snapshot.get("additionalProperties"), false, "content snapshot is closed")
	suite.assert_equal(snapshot.get("properties", {}).get("packs", {}).get("type"), "array", "content snapshot carries ordered pack records")
	var pack: Dictionary = definitions.get("content_pack", {})
	_assert_required_fields(
		suite,
		pack,
		["pack_id", "pack_version", "schema_version", "fingerprint_sha256"],
		"content pack schema"
	)
	var reward_effect: Dictionary = definitions.get("reward_effect_state", {})
	var reward_properties: Dictionary = reward_effect.get("properties", {})
	for runtime_domain: String in ["stats", "health", "time", "weapon", "character"]:
		suite.assert_equal(
			reward_properties.get(runtime_domain),
			{"type": "object"},
			"profile JSON Schema intentionally treats nested %s runtime state as opaque"
			% runtime_domain
		)
	var runtime_mutation := _read_json(FIXTURE_ROOT.path_join("profile_v2.json"), suite)
	var reward_state := _closed_reward_effect_fixture()
	(runtime_mutation.get("payload", {}) as Dictionary)["reward_effect_state"] = reward_state
	(reward_state.get("stats", {}) as Dictionary)["unknown_runtime_field"] = 1.0
	_resign(runtime_mutation)
	suite.assert_equal(
		SaveEnvelopeScript.validate(
			runtime_mutation,
			&"profile",
			"slot_1",
			"base"
		).code,
		&"CORRUPT",
		"GDScript authority rejects an unknown field inside an opaque JSON runtime domain"
	)


func _test_settings_schema(suite) -> void:
	var schema := _read_json(SETTINGS_SCHEMA_PATH, suite)
	if schema.is_empty():
		return
	suite.assert_equal(schema.get("$id"), "planewalker://schemas/save-settings/2.0.0", "settings schema id is stable")
	suite.assert_equal(schema.get("additionalProperties"), false, "settings envelope rejects unknown top-level fields")
	var properties: Dictionary = schema.get("properties", {})
	suite.assert_equal(properties.get("magic", {}).get("const"), "PWSAVE", "settings magic is fixed")
	suite.assert_equal(properties.get("schema_version", {}).get("const"), 2, "settings schema version is explicit")
	suite.assert_equal(properties.get("document_kind", {}).get("const"), "settings", "settings kind is fixed")
	suite.assert_true(not properties.has("profile_id"), "global settings are not tied to a profile")
	suite.assert_true(not properties.has("content_snapshot"), "global settings do not depend on gameplay content packs")
	_assert_required_fields(
		suite,
		schema,
		[
			"magic", "schema_version", "document_kind", "sequence", "game_version",
			"created_at_utc", "saved_at_utc", "payload", "integrity",
		],
		"settings schema"
	)
	var payload: Dictionary = properties.get("payload", {})
	suite.assert_equal(payload.get("additionalProperties"), false, "settings payload is closed")
	for setting_id: String in [
		"locale", "master_volume", "master_muted", "camera_shake_enabled",
		"hit_flash_enabled", "reduced_motion", "music_volume", "sfx_volume",
		"dialogue_volume", "text_scale", "high_contrast_danger", "subtitles_enabled",
		"subtitle_scale", "ranged_charge_mode", "damage_received_multiplier",
		"enemy_telegraph_scale",
	]:
		suite.assert_true(payload.get("properties", {}).has(setting_id), "settings schema includes %s" % setting_id)
	_assert_required_fields(
		suite,
		payload,
		[
			"locale", "master_volume", "master_muted", "camera_shake_enabled",
			"hit_flash_enabled", "reduced_motion",
		],
		"legacy settings compatibility"
	)


func _test_profile_fixtures(suite) -> void:
	var legacy := _read_json(FIXTURE_ROOT.path_join("legacy_v0.json"), suite)
	suite.assert_true(not legacy.has("magic"), "legacy fixture exercises pre-envelope format")
	suite.assert_equal(legacy.get("version"), 1, "legacy fixture preserves historical version field")
	suite.assert_equal(legacy.get("persistent", {}).get("chronos_shards"), 17, "legacy fixture has deterministic progress")

	var legacy_v1 := _read_json(FIXTURE_ROOT.path_join("profile_v1.json"), suite)
	_assert_valid_fixture_integrity(suite, legacy_v1, "legacy v1 profile fixture")
	suite.assert_equal(legacy_v1.get("schema_version"), 1, "legacy profile fixture remains schema v1")

	var current := _read_json(FIXTURE_ROOT.path_join("profile_v2.json"), suite)
	_assert_valid_fixture_integrity(suite, current, "current profile fixture")
	suite.assert_equal(current.get("schema_version"), 2, "current fixture uses schema v2")
	suite.assert_equal(current.get("profile_id"), "slot_1", "current fixture targets slot one")
	suite.assert_true(current.get("payload", {}).has("active_item_state"), "current fixture seals active-item state")
	suite.assert_true(current.get("payload", {}).has("reward_effect_state"), "current fixture seals reward-effect state")

	var migrated := _read_json(FIXTURE_ROOT.path_join("migration_expected_v1.json"), suite)
	_assert_valid_fixture_integrity(suite, migrated, "migration expected fixture")
	suite.assert_equal(migrated.get("payload", {}).get("chronos_shards"), 17, "migration fixture preserves currency")
	suite.assert_true(not migrated.get("payload", {}).has("settings"), "profile migration separates global settings")

	var forward := _read_json(FIXTURE_ROOT.path_join("forward_v3.json"), suite)
	suite.assert_equal(forward.get("magic"), "PWSAVE", "forward fixture remains structurally recognizable")
	suite.assert_equal(forward.get("schema_version"), 3, "forward fixture requires refusal")

	var tampered := _read_json(FIXTURE_ROOT.path_join("corrupt_integrity.json"), suite)
	suite.assert_true(not tampered.is_empty(), "integrity-corrupt fixture remains valid JSON")
	suite.assert_true(
		str(tampered.get("integrity", {}).get("digest", "")) != _document_digest(tampered),
		"integrity-corrupt fixture has a reproducible digest mismatch"
	)

	var bad_header := _read_json(FIXTURE_ROOT.path_join("corrupt_header.json"), suite)
	suite.assert_true(not bad_header.is_empty(), "header-corrupt fixture remains valid JSON")
	suite.assert_true(str(bad_header.get("magic", "")) != "PWSAVE", "header-corrupt fixture has invalid magic")

	var truncated_path := FIXTURE_ROOT.path_join("corrupt_truncated.json")
	var truncated_text := _read_text(truncated_path, suite)
	if not truncated_text.is_empty():
		var parser := JSON.new()
		suite.assert_true(parser.parse(truncated_text) != OK, "truncated fixture is intentionally invalid JSON")


func _test_pack_fingerprint_fixtures(suite) -> void:
	var base_a := _read_json(FIXTURE_ROOT.path_join("pack_snapshots/base_a.json"), suite)
	var reordered := _read_json(FIXTURE_ROOT.path_join("pack_snapshots/base_a_reordered.json"), suite)
	var base_b := _read_json(FIXTURE_ROOT.path_join("pack_snapshots/base_b.json"), suite)
	if base_a.is_empty() or reordered.is_empty() or base_b.is_empty():
		return
	var digest_a := _pack_aggregate(base_a)
	var digest_reordered := _pack_aggregate(reordered)
	var digest_b := _pack_aggregate(base_b)
	suite.assert_equal(base_a.get("aggregate_sha256"), digest_a, "base A fixture records its aggregate fingerprint")
	suite.assert_equal(reordered.get("aggregate_sha256"), digest_reordered, "reordered fixture records its aggregate fingerprint")
	suite.assert_equal(base_b.get("aggregate_sha256"), digest_b, "base B fixture records its aggregate fingerprint")
	suite.assert_equal(digest_a, digest_reordered, "pack fingerprint is independent of input ordering")
	suite.assert_true(digest_a != digest_b, "pack content change alters aggregate fingerprint")


func _assert_valid_fixture_integrity(suite, document: Dictionary, label: String) -> void:
	if document.is_empty():
		return
	suite.assert_equal(document.get("magic"), "PWSAVE", "%s has valid magic" % label)
	suite.assert_equal(document.get("integrity", {}).get("algorithm"), "sha256", "%s declares sha256" % label)
	suite.assert_equal(
		document.get("integrity", {}).get("digest"),
		_document_digest(document),
		"%s digest matches canonical document" % label
	)


func _document_digest(document: Dictionary) -> String:
	var unsigned := document.duplicate(true)
	unsigned.erase("integrity")
	return JSON.stringify(unsigned, "", true, true).sha256_text()


func _resign(document: Dictionary) -> void:
	var unsigned := document.duplicate(true)
	unsigned.erase("integrity")
	document["integrity"] = {
		"algorithm": "sha256",
		"digest": SaveEnvelopeScript.sha256_digest(unsigned),
	}


func _closed_reward_effect_fixture() -> Dictionary:
	return {
		"schema_version": 1,
		"stats": {
			"max_hp": 100.0,
			"attack": 10.0,
			"defense": 0.0,
			"move_speed": 200.0,
			"attack_speed": 1.0,
			"crit_chance": 0.05,
			"crit_multiplier": 1.5,
			"time_energy_max": 100.0,
			"time_energy_regen": 2.0,
		},
		"health": {
			"current_hp": 100.0,
			"max_hp": 100.0,
			"defense": 0.0,
			"healing_multiplier": 1.0,
			"dead": false,
			"invulnerable": false,
			"invulnerability_token": 0,
			"reward_invulnerability_tokens": [],
			"reward_invulnerability_remaining": {},
		},
		"time": {
			"energy": 100.0,
			"max_energy": 100.0,
			"resource_revision": 1,
			"time_stop_duration_bonus": 0.0,
			"time_stop_cost_multiplier": 1.0,
			"time_stop_weakpoint_damage_bonus": 0.0,
			"time_stop_weakpoint_duration": 0.0,
			"time_stop_self_damage": 0.0,
			"rewind_cost_multiplier": 1.0,
			"rewind_heal": 0.0,
			"rewind_echo_enabled": false,
			"rewind_path_hit_multiplier": 0.0,
			"rewind_self_damage": 0.0,
			"time_rift_cost_multiplier": 1.0,
			"time_rift_duration_bonus": 0.0,
			"time_rift_radius_bonus": 0.0,
			"time_rift_slow_bonus": 0.0,
			"time_accelerate_cost_multiplier": 1.0,
			"time_accelerate_duration_bonus": 0.0,
			"time_accelerate_multiplier_bonus": 0.0,
			"low_energy_regen_multiplier": 1.0,
			"low_energy_threshold": 30.0,
		},
		"weapon": {"modifiers": {}, "runtime": {}},
		"character": {"dash_invulnerable_bonus": 0.0},
	}


func _pack_aggregate(snapshot: Dictionary) -> String:
	var packs: Array = snapshot.get("packs", []).duplicate(true)
	packs.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_key := "%s\u001f%s\u001f%010d\u001f%s" % [
			str(left.get("pack_id", "")),
			str(left.get("pack_version", "")),
			int(left.get("schema_version", 0)),
			str(left.get("fingerprint_sha256", "")),
		]
		var right_key := "%s\u001f%s\u001f%010d\u001f%s" % [
			str(right.get("pack_id", "")),
			str(right.get("pack_version", "")),
			int(right.get("schema_version", 0)),
			str(right.get("fingerprint_sha256", "")),
		]
		return left_key < right_key
	)
	return JSON.stringify({"packs": packs}, "", true, true).sha256_text()


func _assert_required_fields(suite, schema: Dictionary, expected: Array[String], label: String) -> void:
	var actual: Array = schema.get("required", []).duplicate()
	actual.sort()
	var sorted_expected: Array = expected.duplicate()
	sorted_expected.sort()
	suite.assert_equal(actual, sorted_expected, "%s required fields are exact" % label)


func _read_json(path: String, suite) -> Dictionary:
	var text := _read_text(path, suite)
	if text.is_empty():
		return {}
	var parser := JSON.new()
	var error := parser.parse(text)
	suite.assert_equal(error, OK, "%s parses as JSON" % path)
	if error != OK:
		return {}
	suite.assert_true(typeof(parser.data) == TYPE_DICTIONARY, "%s root is an object" % path)
	return parser.data if typeof(parser.data) == TYPE_DICTIONARY else {}


func _read_text(path: String, suite) -> String:
	if not FileAccess.file_exists(path):
		suite.assert_true(false, "%s exists" % path)
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "%s is readable" % path)
	if file == null:
		return ""
	return file.get_as_text()
