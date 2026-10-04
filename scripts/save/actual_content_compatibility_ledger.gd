class_name ActualContentCompatibilityLedger
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Descriptor := preload("res://scripts/content/content_pack_descriptor.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const LEDGER_PATH := "res://data/save/compatibility/actual_content_ledger.json"
const LEDGER_SHA256 := "8c4cf7e701a0b1e67931d9900bbfd43b1e8b5fd63abe95fa4b9cc51b0853f187"
const LEGACY_REFERENCES_SHA256 := "0a82bbe5a66702aca98cdaffedf3c8673d752f685de9a134e0283efd6b60c71a"
const DESCRIPTOR_PATHS := ["res://data/save/compatibility/base_p16_actual_pre_hub.json", "res://data/save/compatibility/base_p16_hub_before_narrative.json", "res://data/save/compatibility/base_p16_narrative_before_training.json", "res://data/content_packs/base/pack.json"]
const LOCALIZATION_PATH := "localization/translations.csv"


static func trusted_sources(target_binding: Dictionary, catalog_fingerprint: String) -> Array[Dictionary]:
	var verified := _verified_ledger()
	var target := _normalize_binding(target_binding)
	var result: Array[Dictionary] = []
	if verified.is_empty() or target.is_empty() or catalog_fingerprint != verified.meta_catalog_fingerprint:
		return result
	var bindings: Dictionary = {}
	for row: Dictionary in verified.bindings:
		bindings[row.id] = row
	for edge: Dictionary in verified.transitions:
		if _normalize_binding(bindings[edge.target_id].snapshot) == target:
			result.append(_normalize_binding(bindings[edge.source_id].snapshot).duplicate(true))
	return result


static func audit_view() -> Dictionary:
	return _verified_ledger().duplicate(true)


static func _verified_ledger() -> Dictionary:
	if not FileAccess.file_exists(LEDGER_PATH) or FileAccess.get_sha256(LEDGER_PATH) != LEDGER_SHA256 or FileAccess.get_sha256(Factory.LEGACY_REFERENCES) != LEGACY_REFERENCES_SHA256:
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEDGER_PATH))
	if not Catalog.exact_fields(value, ["schema_id", "schema_version", "save_schema_version", "meta_catalog_fingerprint", "bindings", "transitions"]) or value.schema_id != "planewalker.actual_content_compatibility" or not Catalog.bounded_int(value.schema_version, 1, 1) or not Catalog.bounded_int(value.save_schema_version, Envelope.META_PROFILE_SCHEMA_VERSION, Envelope.META_PROFILE_SCHEMA_VERSION) or not Catalog.fingerprint_valid(value.meta_catalog_fingerprint) or not value.bindings is Array or value.bindings.size() != 4 or not value.transitions is Array or value.transitions.size() != 3:
		return {}
	var current := Factory.load_base()
	if not current.ok or current.context.catalog.fingerprint() != value.meta_catalog_fingerprint:
		return {}
	var bindings: Dictionary = {}
	var descriptors: Dictionary = {}
	var paths: Array = []
	var aggregates: Array = []
	for row: Variant in value.bindings:
		if not Catalog.exact_fields(row, ["id", "descriptor_path", "source_commits", "snapshot"]) or not Catalog.stable_id(row.id) or bindings.has(row.id) or row.descriptor_path not in DESCRIPTOR_PATHS or paths.has(row.descriptor_path) or not row.source_commits is Array or row.source_commits.is_empty():
			return {}
		for commit: Variant in row.source_commits:
			if not commit is String or commit.length() != 40 or not commit.is_valid_hex_number(false):
				return {}
		var binding := _normalize_binding(row.snapshot)
		var descriptor: Variant = JSON.parse_string(FileAccess.get_file_as_string(row.descriptor_path))
		if binding.is_empty() or aggregates.has(binding.aggregate_sha256) or not descriptor is Dictionary or Descriptor.canonical_digest(descriptor) != binding.packs[0].fingerprint_sha256 or descriptor.get("pack_id") != binding.packs[0].pack_id or descriptor.get("pack_version") != binding.packs[0].pack_version or descriptor.get("schema_version") != binding.packs[0].schema_version:
			return {}
		bindings[row.id] = row
		descriptors[row.id] = descriptor
		paths.append(row.descriptor_path)
		aggregates.append(binding.aggregate_sha256)
	var edges: Array = []
	for edge: Variant in value.transitions:
		if not Catalog.exact_fields(edge, ["source_id", "target_id", "allowed_changed_files", "reason"]) or not bindings.has(edge.source_id) or not bindings.has(edge.target_id) or edge.source_id == edge.target_id or edge.allowed_changed_files != [LOCALIZATION_PATH] or not edge.reason is String or edge.reason.is_empty():
			return {}
		var id := str(edge.source_id) + ":" + str(edge.target_id)
		if edges.has(id) or bindings[edge.target_id].descriptor_path != "res://data/content_packs/base/pack.json" or not _localization_only(descriptors[edge.source_id], descriptors[edge.target_id]):
			return {}
		edges.append(id)
	return value.duplicate(true)


static func _normalize_binding(value: Variant) -> Dictionary:
	if not Catalog.exact_fields(value, ["aggregate_sha256", "packs"]) or not Catalog.fingerprint_valid(value.aggregate_sha256) or not value.packs is Array or value.packs.size() != 1:
		return {}
	var pack: Variant = value.packs[0]
	if not Catalog.exact_fields(pack, ["pack_id", "pack_version", "schema_version", "fingerprint_sha256"]) or pack.pack_id != "base" or pack.pack_version != "0.4.0-dev" or not Catalog.bounded_int(pack.schema_version, 2, 2) or not Catalog.fingerprint_valid(pack.fingerprint_sha256) or Envelope.content_snapshot_digest(value.packs) != value.aggregate_sha256:
		return {}
	return {"aggregate_sha256": value.aggregate_sha256, "packs": [{"pack_id": pack.pack_id, "pack_version": pack.pack_version, "schema_version": int(pack.schema_version), "fingerprint_sha256": pack.fingerprint_sha256}]}


static func _localization_only(source: Dictionary, target: Dictionary) -> bool:
	if not source.get("integrity_hashes") is Dictionary or not target.get("integrity_hashes") is Dictionary or not source.integrity_hashes.has(LOCALIZATION_PATH) or not target.integrity_hashes.has(LOCALIZATION_PATH):
		return false
	var normalized := source.duplicate(true)
	normalized.integrity_hashes[LOCALIZATION_PATH] = target.integrity_hashes[LOCALIZATION_PATH]
	return normalized == target
