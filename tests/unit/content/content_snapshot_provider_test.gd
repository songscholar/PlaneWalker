extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const SaveEnvelopeScript := preload("res://scripts/save/save_envelope.gd")
const PROVIDER_PATH := "res://scripts/content/content_snapshot_provider.gd"


class FakeRegistry:
	extends RefCounted

	var _packs: Array[Dictionary] = []

	func _init(packs: Array[Dictionary]) -> void:
		_packs = packs.duplicate(true)

	func active_packs() -> Array[Dictionary]:
		return _packs.duplicate(true)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	suite.assert_true(FileAccess.file_exists(PROVIDER_PATH), "content snapshot provider exists")
	if not FileAccess.file_exists(PROVIDER_PATH):
		suite.finish(get_tree())
		return
	var provider_script: Variant = load(PROVIDER_PATH)
	suite.assert_true(provider_script != null, "content snapshot provider loads")
	if provider_script == null:
		suite.finish(get_tree())
		return
	_test_stable_snapshot(suite, provider_script)
	_test_changed_pack_changes_digest(suite, provider_script)
	_test_invalid_registry_is_rejected(suite, provider_script)
	suite.finish(get_tree())


func _test_stable_snapshot(suite, provider_script: Variant) -> void:
	var packs: Array[Dictionary] = [
		_pack("optional_mod", "1.2.0", "b".repeat(64)),
		_pack("base", "1.0.0", "a".repeat(64)),
	]
	var registry := FakeRegistry.new(packs)
	var first: Dictionary = provider_script.snapshot(registry)
	var second: Dictionary = provider_script.snapshot(registry)
	suite.assert_equal(first, second, "content snapshot is deterministic")
	suite.assert_equal(first.get("packs", [])[0].get("pack_id"), "base", "snapshot sorts packs by stable identity")
	suite.assert_equal(first.get("aggregate_sha256"), SaveEnvelopeScript.content_snapshot_digest(first.get("packs", [])), "snapshot aggregate matches SaveEnvelope contract")
	suite.assert_equal(str(first.get("aggregate_sha256", "")).length(), 64, "snapshot aggregate uses sha256")
	first["packs"][0]["pack_version"] = "mutated"
	suite.assert_equal(provider_script.snapshot(registry).get("packs", [])[0].get("pack_version"), "1.0.0", "snapshot output is isolated")


func _test_changed_pack_changes_digest(suite, provider_script: Variant) -> void:
	var original := FakeRegistry.new([_pack("base", "1.0.0", "a".repeat(64))])
	var changed := FakeRegistry.new([_pack("base", "1.0.0", "c".repeat(64))])
	var original_snapshot: Dictionary = provider_script.snapshot(original)
	var changed_snapshot: Dictionary = provider_script.snapshot(changed)
	suite.assert_true(original_snapshot.get("aggregate_sha256") != changed_snapshot.get("aggregate_sha256"), "pack fingerprint changes aggregate digest")


func _test_invalid_registry_is_rejected(suite, provider_script: Variant) -> void:
	suite.assert_true(provider_script.snapshot(null).is_empty(), "null registry is rejected")
	suite.assert_true(provider_script.snapshot(FakeRegistry.new([])).is_empty(), "empty active pack set is rejected")
	var duplicate := FakeRegistry.new([
		_pack("base", "1.0.0", "a".repeat(64)),
		_pack("base", "1.0.0", "a".repeat(64)),
	])
	suite.assert_true(provider_script.snapshot(duplicate).is_empty(), "duplicate pack records are rejected")
	var invalid_digest := FakeRegistry.new([_pack("base", "1.0.0", "not-a-digest")])
	suite.assert_true(provider_script.snapshot(invalid_digest).is_empty(), "invalid pack fingerprint is rejected")


func _pack(pack_id: String, pack_version: String, fingerprint: String) -> Dictionary:
	return {
		"pack_id": pack_id,
		"pack_version": pack_version,
		"schema_version": 2,
		"fingerprint_sha256": fingerprint,
	}
