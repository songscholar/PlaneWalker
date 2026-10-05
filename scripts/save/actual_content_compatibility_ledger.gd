class_name ActualContentCompatibilityLedger
extends RefCounted

const Catalog := preload("res://scripts/progression/meta_progression_catalog.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Descriptor := preload("res://scripts/content/content_pack_descriptor.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const LEDGER_PATH := "res://data/save/compatibility/actual_content_ledger.json"
const LEDGER_SHA256 := "7bc5b63a802abb99750db5224ea45bf2e36bb029827082ca5c5e68473756c64e"
const LEGACY_REFERENCES_SHA256 := "0a82bbe5a66702aca98cdaffedf3c8673d752f685de9a134e0283efd6b60c71a"
const DESCRIPTOR_PATHS := ["res://data/save/compatibility/base_p16_actual_pre_hub.json", "res://data/save/compatibility/base_p16_hub_before_narrative.json", "res://data/save/compatibility/base_p16_narrative_before_training.json", "res://data/save/compatibility/base_p17_before_native_ambush.json", "res://data/save/compatibility/base_p19_before_corpse_tuning.json", "res://data/save/compatibility/base_p20_before_build_sharing.json", "res://data/save/compatibility/base_p23_before_cosmetics.json", "res://data/save/compatibility/base_p23_before_terminal_encounters.json", "res://data/content_packs/base/pack.json"]
const LOCALIZATION_PATH := "localization/translations.csv"
const AMBUSH_FILES := ["assets/rooms/launch/room_event_crossroads.tscn", "assets/rooms/launch/room_event_mirror_hall.tscn", "assets/rooms/launch/room_event_shrine.tscn", "content/enemies.json", "content/room_templates.json"]
const ENEMY_MECHANISM_FILES := ["content/enemies.json"]
const TERMINAL_ENCOUNTER_FILES := ["content/launch_encounter_extensions.json"]
const COSMETIC_FILES := [
	"assets/cosmetics/LICENSE.txt", "assets/cosmetics/contact_sheet.png", "assets/cosmetics/manifest.json",
	"assets/cosmetics/primordial_knight_default.png", "assets/cosmetics/primordial_knight_return.png", "assets/cosmetics/primordial_knight_victory.png",
	"assets/cosmetics/time_guardian_default.png", "assets/cosmetics/time_guardian_return.png", "assets/cosmetics/time_guardian_victory.png",
	"assets/cosmetics/time_lord_default.png", "assets/cosmetics/time_lord_return.png", "assets/cosmetics/time_lord_victory.png",
	"assets/cosmetics/void_walker_default.png", "assets/cosmetics/void_walker_return.png", "assets/cosmetics/void_walker_victory.png",
	"assets/cosmetics/wanderer_default.png", "assets/cosmetics/wanderer_return.png", "assets/cosmetics/wanderer_victory.png",
	"content/cosmetics.json", "localization/cosmetics.csv",
]


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
	if not Catalog.exact_fields(value, ["schema_id", "schema_version", "save_schema_version", "meta_catalog_fingerprint", "bindings", "transitions"]) or value.schema_id != "planewalker.actual_content_compatibility" or not Catalog.bounded_int(value.schema_version, 1, 1) or not Catalog.bounded_int(value.save_schema_version, Envelope.META_PROFILE_SCHEMA_VERSION, Envelope.META_PROFILE_SCHEMA_VERSION) or not Catalog.fingerprint_valid(value.meta_catalog_fingerprint) or not value.bindings is Array or value.bindings.size() != 9 or not value.transitions is Array or value.transitions.size() != 8:
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
		if not Catalog.exact_fields(edge, ["source_id", "target_id", "allowed_changed_files", "allowed_added_files", "reason"]) or not bindings.has(edge.source_id) or not bindings.has(edge.target_id) or edge.source_id == edge.target_id or edge.allowed_changed_files not in [[], [LOCALIZATION_PATH], ENEMY_MECHANISM_FILES, ENEMY_MECHANISM_FILES + [LOCALIZATION_PATH], AMBUSH_FILES, AMBUSH_FILES + [LOCALIZATION_PATH]] or edge.allowed_added_files not in [COSMETIC_FILES, COSMETIC_FILES + TERMINAL_ENCOUNTER_FILES, TERMINAL_ENCOUNTER_FILES] or not edge.reason is String or edge.reason.is_empty():
			return {}
		var id := str(edge.source_id) + ":" + str(edge.target_id)
		if edges.has(id) or bindings[edge.target_id].descriptor_path != "res://data/content_packs/base/pack.json" or not _reviewed_changes_only(descriptors[edge.source_id], descriptors[edge.target_id], edge.allowed_changed_files, edge.allowed_added_files):
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


static func _reviewed_changes_only(source: Dictionary, target: Dictionary, allowed: Array, added: Array = []) -> bool:
	if not source.get("integrity_hashes") is Dictionary or not target.get("integrity_hashes") is Dictionary or added not in [COSMETIC_FILES, COSMETIC_FILES + TERMINAL_ENCOUNTER_FILES, TERMINAL_ENCOUNTER_FILES]:
		return false
	var normalized := source.duplicate(true)
	for path: String in added:
		if source.integrity_hashes.has(path) or not target.integrity_hashes.has(path) or not Catalog.fingerprint_valid(target.integrity_hashes[path]):
			return false
		var manifest := "content_manifest" if path in ["content/cosmetics.json", "content/launch_encounter_extensions.json"] else "localization_sources" if path == "localization/cosmetics.csv" else "asset_manifest"
		if not normalized.get(manifest) is Array:
			return false
		normalized[manifest].append(path)
		normalized[manifest].sort()
		normalized.integrity_hashes[path] = target.integrity_hashes[path]
	for path: String in allowed:
		if not source.integrity_hashes.has(path) or not target.integrity_hashes.has(path) or source.integrity_hashes[path] == target.integrity_hashes[path]:
			return false
		normalized.integrity_hashes[path] = target.integrity_hashes[path]
	return normalized == target
