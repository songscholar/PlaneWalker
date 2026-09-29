extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const SaveResultScript := preload("res://scripts/save/save_result.gd")
const SavePathPolicyScript := preload("res://scripts/save/save_path_policy.gd")
const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")
const PROFILE_FIXTURE_PATH := "res://tests/fixtures/save/profile_v1.json"
const SNAPSHOT_FIXTURE_PATH := "res://tests/fixtures/save/pack_snapshots/base_a.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_save_result_deep_copies(suite)
	_test_save_result_codes(suite)
	_test_id_policy(suite)
	_test_relative_path_policy(suite)
	_test_canonical_json_and_digest(suite)
	_test_profile_envelope_round_trip(suite)
	_test_settings_envelope_round_trip(suite)
	_test_envelope_rejects_tampering(suite)
	_test_envelope_rejects_invalid_documents(suite)
	suite.finish(get_tree())


func _test_save_result_deep_copies(suite) -> void:
	var source_payload := {"profile": {"unlocks": ["sword"]}}
	var source_metadata := {"source": {"slot": "slot_01"}}
	var source_diagnostics: Array[Dictionary] = [{"code": "test-diagnostic", "context": {"attempt": 1}}]
	var result = SaveResultScript.success(source_payload, source_metadata, source_diagnostics)

	source_payload["profile"]["unlocks"].append("bow")
	source_metadata["source"]["slot"] = "mutated"
	source_diagnostics[0]["context"]["attempt"] = 99

	suite.assert_equal(result.payload, {"profile": {"unlocks": ["sword"]}}, "save result deep-copies payload input")
	suite.assert_equal(result.metadata, {"source": {"slot": "slot_01"}}, "save result deep-copies metadata input")
	suite.assert_equal(result.diagnostics[0]["context"]["attempt"], 1, "save result deep-copies diagnostics input")

	var snapshot: Dictionary = result.to_dictionary()
	snapshot["payload"]["profile"]["unlocks"].append("staff")
	snapshot["metadata"]["source"]["slot"] = "snapshot"
	snapshot["diagnostics"][0]["context"]["attempt"] = 100
	suite.assert_equal(result.payload["profile"]["unlocks"], ["sword"], "save result dictionary export is isolated")
	suite.assert_equal(result.metadata["source"]["slot"], "slot_01", "save result metadata export is isolated")
	suite.assert_equal(result.diagnostics[0]["context"]["attempt"], 1, "save result diagnostics export is isolated")

	var failure_metadata := {"source": {"candidate": "primary"}}
	var failure_diagnostics: Array[Dictionary] = [{"code": "bad-integrity", "context": {"sequence": 12}}]
	var failure = SaveResultScript.failure(&"CORRUPT", failure_metadata, failure_diagnostics)
	failure_metadata["source"]["candidate"] = "mutated"
	failure_diagnostics[0]["context"]["sequence"] = 99
	suite.assert_equal(failure.metadata["source"]["candidate"], "primary", "failure result deep-copies metadata input")
	suite.assert_equal(failure.diagnostics[0]["context"]["sequence"], 12, "failure result deep-copies diagnostics input")


func _test_save_result_codes(suite) -> void:
	var recovered = SaveResultScript.success({}, {}, [], &"RECOVERED")
	suite.assert_true(recovered.ok, "recovered is a successful save result")
	suite.assert_equal(recovered.code, &"RECOVERED", "recovered code is preserved")
	suite.assert_true(recovered.player_notice_required, "recovered result always requires a player notice")

	var corrupt = SaveResultScript.failure(&"CORRUPT", {"source": "primary"})
	suite.assert_true(not corrupt.ok, "corrupt is a failed save result")
	suite.assert_equal(corrupt.code, &"CORRUPT", "standard failure code is preserved")

	var unknown = SaveResultScript.failure(&"UNDECLARED_CODE")
	suite.assert_equal(unknown.code, &"INVALID_ARGUMENT", "unknown failure code is normalized")
	suite.assert_equal(unknown.metadata.get("requested_code", ""), "UNDECLARED_CODE", "unknown code remains diagnosable")


func _test_id_policy(suite) -> void:
	for valid_id: String in ["a", "profile_01", "base-pack", "z2345678901234567890123456789012"]:
		suite.assert_true(SavePathPolicyScript.validate_id(valid_id).ok, "valid id is accepted: %s" % valid_id)

	for invalid_id: Variant in ["", "Profile", "-leading", "has.dot", "has/slash", "has\\slash", "has space", "z23456789012345678901234567890123", 7]:
		suite.assert_true(not SavePathPolicyScript.validate_id(invalid_id).ok, "invalid id is rejected: %s" % str(invalid_id))


func _test_relative_path_policy(suite) -> void:
	for valid_path: String in ["profiles/profile_01/profile.json", "settings/settings.json", "backups/profile-01.1.json"]:
		suite.assert_true(SavePathPolicyScript.validate_relative_path(valid_path).ok, "valid relative path is accepted: %s" % valid_path)

	for invalid_path: Variant in [
		"",
		"/absolute/profile.json",
		"user://profile.json",
		"res://profile.json",
		"../profile.json",
		"profiles/../profile.json",
		"profiles/./profile.json",
		"profiles//profile.json",
		"profiles\\profile.json",
		"profiles/profile.json/",
		"profiles/Profile.json",
		7,
	]:
		suite.assert_true(not SavePathPolicyScript.validate_relative_path(invalid_path).ok, "unsafe relative path is rejected: %s" % str(invalid_path))


func _test_canonical_json_and_digest(suite) -> void:
	var first := {"z": [{"b": 2, "a": 1}], "a": true}
	var second := {"a": true, "z": [{"a": 1, "b": 2}]}
	var expected_json := "{\"a\":true,\"z\":[{\"a\":1,\"b\":2}]}"
	var expected_digest := "4f1cc1676b4591a84b76768886f93f659ac89c3c0ff933f4a0dccb6b2ceda86b"

	suite.assert_equal(SaveEnvelopeScript.canonical_json(first), expected_json, "canonical JSON recursively sorts dictionary keys")
	suite.assert_equal(SaveEnvelopeScript.canonical_json(second), expected_json, "canonical JSON ignores dictionary insertion order")
	suite.assert_equal(SaveEnvelopeScript.sha256_digest(first), expected_digest, "canonical SHA-256 digest is stable")


func _test_profile_envelope_round_trip(suite) -> void:
	var expected := _read_json(PROFILE_FIXTURE_PATH, suite)
	var content_snapshot: Dictionary = expected.get("content_snapshot", {}).duplicate(true)
	var payload: Dictionary = expected.get("payload", {}).duplicate(true)
	var created = SaveEnvelopeScript.create_profile(
		str(expected.get("profile_id", "")),
		str(expected.get("save_domain", "")),
		int(expected.get("sequence", -1)),
		str(expected.get("game_version", "")),
		str(expected.get("created_at_utc", "")),
		str(expected.get("saved_at_utc", "")),
		content_snapshot,
		payload
	)
	suite.assert_true(created.ok, "valid profile envelope is created: %s" % str(created.to_dictionary()))
	if not created.ok:
		return

	var envelope: Dictionary = created.payload
	suite.assert_equal(envelope, expected, "profile creation reproduces the frozen deterministic fixture")
	suite.assert_equal(envelope.get("magic"), "PWSAVE", "envelope uses the frozen magic value")
	suite.assert_equal(envelope.get("schema_version"), 1, "envelope uses schema version one")
	suite.assert_equal(envelope.get("document_kind"), "profile", "envelope records its document kind")
	suite.assert_equal(envelope.get("profile_id"), "slot_1", "profile envelope records its profile id")
	suite.assert_equal(envelope.get("save_domain"), "base", "profile envelope records its save domain")
	suite.assert_equal(envelope.get("sequence"), 12, "profile envelope records its non-negative sequence")
	suite.assert_equal(envelope.get("game_version"), "0.4.0-dev", "profile envelope records its game version")
	suite.assert_equal(envelope.get("created_at_utc"), "2026-09-28T08:00:00Z", "profile envelope records its creation timestamp")
	suite.assert_equal(envelope.get("saved_at_utc"), "2026-09-28T09:00:00Z", "profile envelope records its save timestamp")
	suite.assert_equal(envelope.get("integrity", {}).get("algorithm"), "sha256", "envelope declares SHA-256 integrity")
	suite.assert_equal(str(envelope.get("integrity", {}).get("digest", "")).length(), 64, "envelope digest is lowercase SHA-256 hex")

	payload["unlocked_weapons"].append("bow")
	content_snapshot["packs"][0]["pack_version"] = "mutated"
	suite.assert_equal(envelope["payload"]["unlocked_weapons"], ["sword"], "envelope creation deep-copies payload")
	suite.assert_equal(envelope["content_snapshot"]["packs"][0]["pack_version"], "0.4.0-dev", "envelope creation deep-copies content snapshot")

	var validated = SaveEnvelopeScript.validate(envelope, &"profile", "slot_1", "base")
	suite.assert_true(validated.ok, "created envelope validates")
	if validated.ok:
		var validated_envelope: Dictionary = validated.payload
		validated_envelope["payload"]["unlocked_weapons"].append("staff")
		suite.assert_equal(envelope["payload"]["unlocked_weapons"], ["sword"], "validated envelope result is a deep copy")

	var reordered := envelope.duplicate(true)
	var reordered_copy := {}
	var keys: Array = reordered.keys()
	keys.reverse()
	for key: Variant in keys:
		reordered_copy[key] = reordered[key]
	suite.assert_true(SaveEnvelopeScript.validate(reordered_copy, &"profile", "slot_1", "base").ok, "envelope validation is independent of dictionary insertion order")


func _test_settings_envelope_round_trip(suite) -> void:
	var settings := {
		"locale": "zh_CN",
		"master_volume": 0.8,
		"master_muted": false,
		"camera_shake_enabled": true,
		"hit_flash_enabled": true,
		"reduced_motion": false,
	}
	var created = SaveEnvelopeScript.create_settings(
		4,
		"0.4.0-dev",
		"2026-09-28T08:00:00Z",
		"2026-09-28T09:00:00Z",
		settings
	)
	suite.assert_true(created.ok, "valid settings envelope is created")
	if not created.ok:
		return
	var envelope: Dictionary = created.payload
	suite.assert_equal(envelope.keys().size(), 9, "settings envelope has exactly its schema fields")
	suite.assert_true(not envelope.has("profile_id"), "settings envelope is not profile-scoped")
	suite.assert_true(not envelope.has("save_domain"), "settings envelope has no save domain")
	suite.assert_true(not envelope.has("content_snapshot"), "settings envelope is not content-bound")
	suite.assert_true(SaveEnvelopeScript.validate(envelope, &"settings").ok, "created settings envelope validates")

	settings["locale"] = "en"
	suite.assert_equal(envelope["payload"]["locale"], "zh_CN", "settings creation deep-copies payload")


func _test_envelope_rejects_tampering(suite) -> void:
	var created = SaveEnvelopeScript.create_settings(
		4,
		"0.4.0-dev",
		"2026-09-28T08:00:00Z",
		"2026-09-28T09:00:00Z",
		{
			"locale": "zh_CN",
			"master_volume": 0.8,
			"master_muted": false,
			"camera_shake_enabled": true,
			"hit_flash_enabled": true,
			"reduced_motion": false,
		}
	)
	var envelope: Dictionary = created.payload
	var tampered := envelope.duplicate(true)
	tampered["payload"]["master_volume"] = 1.0

	var result = SaveEnvelopeScript.validate(tampered, &"settings")
	suite.assert_true(not result.ok, "tampered payload is rejected")
	suite.assert_equal(result.code, &"CORRUPT", "tampered payload is classified as corrupt")
	suite.assert_equal(envelope["payload"]["master_volume"], 0.8, "tamper validation does not mutate its input")


func _test_envelope_rejects_invalid_documents(suite) -> void:
	var profile := _read_json(PROFILE_FIXTURE_PATH, suite)

	var forward := profile.duplicate(true)
	forward["schema_version"] = 2
	suite.assert_equal(SaveEnvelopeScript.validate(forward).code, &"FORWARD_VERSION", "forward save schema is refused explicitly")

	var wrong_kind: RefCounted = SaveEnvelopeScript.validate(profile, &"settings")
	suite.assert_equal(wrong_kind.code, &"CORRUPT", "unexpected document kind is rejected")
	suite.assert_equal(SaveEnvelopeScript.validate(profile, &"profile", "slot_2", "base").code, &"CORRUPT", "unexpected profile id is rejected")
	suite.assert_equal(SaveEnvelopeScript.validate(profile, &"profile", "slot_1", "modded").code, &"CORRUPT", "unexpected save domain is rejected")

	var invalid_magic := profile.duplicate(true)
	invalid_magic["magic"] = "NOT_A_SAVE"
	suite.assert_equal(SaveEnvelopeScript.validate(invalid_magic).code, &"CORRUPT", "invalid magic is rejected")

	var extra_field := profile.duplicate(true)
	extra_field["unexpected"] = true
	_resign(extra_field)
	suite.assert_equal(SaveEnvelopeScript.validate(extra_field).code, &"CORRUPT", "unknown profile envelope field is rejected")

	var negative_sequence := profile.duplicate(true)
	negative_sequence["sequence"] = -1
	_resign(negative_sequence)
	suite.assert_equal(SaveEnvelopeScript.validate(negative_sequence).code, &"CORRUPT", "negative sequence is rejected")

	var invalid_timestamp := profile.duplicate(true)
	invalid_timestamp["saved_at_utc"] = "yesterday"
	_resign(invalid_timestamp)
	suite.assert_equal(SaveEnvelopeScript.validate(invalid_timestamp).code, &"CORRUPT", "invalid UTC timestamp is rejected")

	var invalid_snapshot := profile.duplicate(true)
	invalid_snapshot["content_snapshot"]["aggregate_sha256"] = "0".repeat(64)
	_resign(invalid_snapshot)
	suite.assert_equal(SaveEnvelopeScript.validate(invalid_snapshot).code, &"CORRUPT", "content aggregate mismatch is rejected")

	var duplicate_pack := profile.duplicate(true)
	duplicate_pack["content_snapshot"]["packs"].append(duplicate_pack["content_snapshot"]["packs"][0].duplicate(true))
	duplicate_pack["content_snapshot"]["aggregate_sha256"] = SaveEnvelopeScript.content_snapshot_digest(duplicate_pack["content_snapshot"]["packs"])
	_resign(duplicate_pack)
	suite.assert_equal(SaveEnvelopeScript.validate(duplicate_pack).code, &"CORRUPT", "duplicate content pack is rejected")

	var invalid_algorithm := profile.duplicate(true)
	invalid_algorithm["integrity"]["algorithm"] = "md5"
	suite.assert_equal(SaveEnvelopeScript.validate(invalid_algorithm).code, &"CORRUPT", "unsupported integrity algorithm is rejected")

	var malformed_digest := profile.duplicate(true)
	malformed_digest["integrity"]["digest"] = "ABC"
	suite.assert_equal(SaveEnvelopeScript.validate(malformed_digest).code, &"CORRUPT", "malformed integrity digest is rejected")

	var snapshot := _read_json(SNAPSHOT_FIXTURE_PATH, suite)
	suite.assert_true(
		not SaveEnvelopeScript.create_profile("../slot", "base", 0, "0.4.0-dev", "2026-09-28T08:00:00Z", "2026-09-28T08:00:00Z", snapshot, {}).ok,
		"unsafe profile id cannot be created"
	)
	suite.assert_true(
		not SaveEnvelopeScript.create_profile("slot_1", "base", -1, "0.4.0-dev", "2026-09-28T08:00:00Z", "2026-09-28T08:00:00Z", snapshot, {}).ok,
		"negative profile sequence cannot be created"
	)
	suite.assert_true(
		not SaveEnvelopeScript.create_profile("slot_1", "base", 0, "0.4.0-dev", "2026-09-28T08:00:00Z", "2026-09-28T08:00:00Z", snapshot, {"bad": INF}).ok,
		"non-finite profile payload cannot be created"
	)
	var invalid_settings := {
		"locale": "fr",
		"master_volume": 2.0,
		"master_muted": false,
		"camera_shake_enabled": true,
		"hit_flash_enabled": true,
		"reduced_motion": false,
	}
	suite.assert_true(
		not SaveEnvelopeScript.create_settings(0, "0.4.0-dev", "2026-09-28T08:00:00Z", "2026-09-28T08:00:00Z", invalid_settings).ok,
		"settings outside the frozen schema cannot be created"
	)
	suite.assert_true(not SaveEnvelopeScript.validate([]).ok, "non-dictionary envelope is rejected")


func _resign(document: Dictionary) -> void:
	var unsigned := document.duplicate(true)
	unsigned.erase("integrity")
	document["integrity"] = {
		"algorithm": "sha256",
		"digest": SaveEnvelopeScript.sha256_digest(unsigned),
	}


func _read_json(path: String, suite) -> Dictionary:
	if not FileAccess.file_exists(path):
		suite.assert_true(false, "%s exists" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	suite.assert_true(file != null, "%s is readable" % path)
	if file == null:
		return {}
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	suite.assert_equal(error, OK, "%s parses" % path)
	if error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return {}
	return (parser.data as Dictionary).duplicate(true)
