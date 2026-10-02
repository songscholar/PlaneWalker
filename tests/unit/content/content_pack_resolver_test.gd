extends Node

const TestSuiteScript := preload("res://tests/support/test_suite.gd")
const ContentPackDescriptorScript := preload("res://scripts/content/content_pack_descriptor.gd")
const ContentPackResolverScript := preload("res://scripts/content/content_pack_resolver.gd")
const ArchetypeProfileScript := preload("res://scripts/progression/archetype_profile.gd")

const VALID_PACK_PATH := "res://tests/fixtures/content_packs/valid_base/pack.json"
const BAD_DIGEST_PACK_PATH := "res://tests/fixtures/content_packs/bad_digest/pack.json"
const PROJECT_BASE_PACK_PATH := "res://data/content_packs/base/pack.json"
const CHAIN_ROOT := "res://tests/fixtures/content_packs/dependency_chain"
const CYCLE_ROOT := "res://tests/fixtures/content_packs/dependency_cycle"
const SPECIALIZED_CATEGORY_COUNTS := {
	"floor_definition": 5,
	"room_template": 30,
	"dungeon_event": 18,
	"merchant_definition": 5,
	"economy_profile": 1,
}
const P14_MANIFEST_PATHS: Array[String] = [
	"content/floors.json",
	"content/room_templates.json",
	"content/dungeon_events.json",
	"content/merchants.json",
	"content/economy_profiles.json",
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite = TestSuiteScript.new()
	_test_descriptor_load_and_digest(suite)
	_test_descriptor_integrity_failure(suite)
	_test_project_base_pack(suite)
	_test_fixture_graphs(suite)
	_test_stable_dependency_order(suite)
	_test_duplicate_pack_ids(suite)
	_test_missing_dependencies(suite)
	_test_dependency_versions(suite)
	_test_dependency_cycles(suite)
	_test_game_version_isolation(suite)
	suite.finish(get_tree())


func _test_descriptor_load_and_digest(suite) -> void:
	var first: Dictionary = ContentPackDescriptorScript.load_path(VALID_PACK_PATH, true)
	var second: Dictionary = ContentPackDescriptorScript.load_path(VALID_PACK_PATH, true)
	suite.assert_true(bool(first.get("ok", false)), "valid pack descriptor loads")
	suite.assert_true(bool(second.get("ok", false)), "valid pack descriptor loads repeatedly")
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		return
	var first_descriptor: Dictionary = first.get("descriptor", {})
	var second_descriptor: Dictionary = second.get("descriptor", {})
	suite.assert_equal(first_descriptor.get("pack_id"), "fixture_base", "descriptor preserves pack id")
	suite.assert_equal(first_descriptor.get("required_pack"), true, "descriptor preserves required scope")
	suite.assert_equal(first_descriptor.get("fingerprint_sha256"), second_descriptor.get("fingerprint_sha256"), "canonical digest is deterministic")
	suite.assert_equal(str(first_descriptor.get("fingerprint_sha256", "")).length(), 64, "canonical digest uses sha256")
	first_descriptor["dependencies"].append({"pack_id": "mutated"})
	suite.assert_true((second_descriptor.get("dependencies", []) as Array).is_empty(), "descriptor results are isolated")


func _test_descriptor_integrity_failure(suite) -> void:
	var loaded: Dictionary = ContentPackDescriptorScript.load_path(BAD_DIGEST_PACK_PATH, false)
	suite.assert_true(not bool(loaded.get("ok", false)), "bad content digest is rejected")
	suite.assert_equal(loaded.get("code"), &"INTEGRITY_MISMATCH", "bad digest has stable code")


func _test_project_base_pack(suite) -> void:
	var loaded: Dictionary = ContentPackDescriptorScript.load_path(PROJECT_BASE_PACK_PATH, true)
	suite.assert_true(bool(loaded.get("ok", false)), "project base pack passes descriptor and integrity validation")
	if not bool(loaded.get("ok", false)):
		return
	var descriptor: Dictionary = loaded.get("descriptor", {})
	suite.assert_equal(descriptor.get("pack_id"), "base", "project base pack has stable id")
	suite.assert_equal(descriptor.get("pack_version"), "0.4.0-dev", "project base pack version matches current M1 cohort")
	var content_manifest: Array = descriptor.get("content_manifest", [])
	suite.assert_equal(content_manifest.size(), 15, "project base pack owns fifteen generic and specialized content sources")
	for relative_path: String in P14_MANIFEST_PATHS:
		suite.assert_true(content_manifest.has(relative_path), "project base pack registers %s" % relative_path)
	suite.assert_equal((descriptor.get("localization_sources", []) as Array).size(), 1, "project base pack owns localization source")
	var asset_manifest := descriptor.get("asset_manifest", []) as Array
	suite.assert_equal(asset_manifest.size(), 31, "P14D registers the shared base and thirty Launch room scenes")
	suite.assert_true(
		asset_manifest.has("assets/rooms/launch/launch_room_base.tscn"),
		"P14D registers the shared Launch room base"
	)
	for asset_value: Variant in asset_manifest:
		var asset_path := str(asset_value)
		suite.assert_true(
			asset_path.begins_with("assets/rooms/launch/") and asset_path.ends_with(".tscn"),
			"P14D room asset stays inside the approved Launch scene boundary: %s" % asset_path
		)
	suite.assert_equal(
		(descriptor.get("integrity_hashes", {}) as Dictionary).size(),
		47,
		"Base Pack integrity closes all content, localization, and P14D room assets"
	)

	var entries: Array[Dictionary] = []
	for relative_path_value: Variant in descriptor.get("content_manifest", []):
		var file := FileAccess.open(str(descriptor.get("root_path", "")).path_join(str(relative_path_value)), FileAccess.READ)
		suite.assert_true(file != null, "project base content source opens: %s" % str(relative_path_value))
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		suite.assert_true(parsed is Array, "project base content source is an array: %s" % str(relative_path_value))
		if not parsed is Array:
			continue
		for entry_value: Variant in parsed:
			if entry_value is Dictionary:
				entries.append((entry_value as Dictionary).duplicate(true))
	var generic_entries: Array[Dictionary] = []
	var specialized_entries: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if SPECIALIZED_CATEGORY_COUNTS.has(str(entry.get("category", ""))):
			specialized_entries.append(entry)
		else:
			generic_entries.append(entry)
	suite.assert_equal(entries.size(), 211, "project base pack contains the exact Launch content authority")
	suite.assert_equal(generic_entries.size(), 152, "generic v2 authority remains frozen at 152 definitions")
	suite.assert_equal(specialized_entries.size(), 59, "P14 contributes exactly 59 specialized definitions")
	for category: String in SPECIALIZED_CATEGORY_COUNTS:
		var category_count := 0
		for entry: Dictionary in specialized_entries:
			if str(entry.get("category", "")) == category:
				category_count += 1
		suite.assert_equal(
			category_count,
			int(SPECIALIZED_CATEGORY_COUNTS[category]),
			"P14 specialized %s count is exact" % category
		)
	var allowed_archetypes: Array[String] = [
		"",
		"accelerated_combo",
		"echo_legion",
		"freeze_burst",
		"low_hp_void",
		"perfect_guard",
		"piercing_barrage",
		"rewind_echo",
		"rift_trap",
	]
	var archetype_profiles: Array[Dictionary] = []
	for entry: Dictionary in generic_entries:
		for required_field: String in [
			"id", "category", "availability", "name_key", "description_key",
			"tags", "compatibility", "effects",
		]:
			suite.assert_true(entry.has(required_field), "base entry %s has %s" % [entry.get("id", ""), required_field])
		if str(entry.get("category", "")) in ["item", "blessing", "curse", "talent"]:
			for reward_field: String in ["kind", "archetype", "role", "rarity", "icon_id"]:
				suite.assert_true(entry.has(reward_field), "reward entry %s has %s" % [entry.get("id", ""), reward_field])
		suite.assert_true(not entry.has("name") and not entry.has("description"), "base entry %s uses v2 localization fields" % entry.get("id", ""))
		suite.assert_true(allowed_archetypes.has(str(entry.get("archetype", ""))), "base entry %s uses authoritative archetype taxonomy" % entry.get("id", ""))
		if str(entry.get("category", "")) == "archetype_profile":
			archetype_profiles.append(entry.duplicate(true))
	suite.assert_equal(archetype_profiles.size(), 8, "project base pack contains exactly eight archetype profiles")
	var archetype_ids: Array[String] = []
	for profile: Dictionary in archetype_profiles:
		archetype_ids.append(str(profile.get("archetype_id", "")))
		suite.assert_true(
			bool(ArchetypeProfileScript.new().configure(profile).get("ok", false)),
			"base archetype profile %s is parser-ready" % profile.get("id", "")
		)
	suite.assert_equal(archetype_ids, ArchetypeProfileScript.ARCHETYPE_IDS, "base manifest preserves approved archetype order")


func _test_fixture_graphs(suite) -> void:
	var base_result: Dictionary = ContentPackDescriptorScript.load_path(CHAIN_ROOT.path_join("base/pack.json"), true)
	var update_result: Dictionary = ContentPackDescriptorScript.load_path(CHAIN_ROOT.path_join("update/pack.json"), false)
	var mod_result: Dictionary = ContentPackDescriptorScript.load_path(CHAIN_ROOT.path_join("mod/pack.json"), false)
	suite.assert_true(bool(base_result.get("ok", false)), "dependency-chain base fixture loads")
	suite.assert_true(bool(update_result.get("ok", false)), "dependency-chain update fixture loads")
	suite.assert_true(bool(mod_result.get("ok", false)), "dependency-chain mod fixture loads")
	if bool(base_result.get("ok", false)) and bool(update_result.get("ok", false)) and bool(mod_result.get("ok", false)):
		var chain_report = ContentPackResolverScript.new().resolve(
			[
				mod_result.get("descriptor", {}),
				base_result.get("descriptor", {}),
				update_result.get("descriptor", {}),
			],
			"0.5.0-dev"
		)
		suite.assert_equal(
			chain_report.get_meta("activation_order", []),
			["fixture_chain_base", "fixture_chain_update", "fixture_chain_mod"],
			"fixture dependency chain resolves in dependency order"
		)

	var cycle_a_result: Dictionary = ContentPackDescriptorScript.load_path(CYCLE_ROOT.path_join("mod_a/pack.json"), false)
	var cycle_b_result: Dictionary = ContentPackDescriptorScript.load_path(CYCLE_ROOT.path_join("mod_b/pack.json"), false)
	suite.assert_true(bool(cycle_a_result.get("ok", false)), "dependency-cycle A fixture loads")
	suite.assert_true(bool(cycle_b_result.get("ok", false)), "dependency-cycle B fixture loads")
	if bool(cycle_a_result.get("ok", false)) and bool(cycle_b_result.get("ok", false)):
		var cycle_report = ContentPackResolverScript.new().resolve(
			[
				cycle_a_result.get("descriptor", {}),
				cycle_b_result.get("descriptor", {}),
			],
			"0.5.0-dev"
		)
		suite.assert_true(not cycle_report.has_blocking_errors(), "optional fixture cycle is isolated")
		suite.assert_equal(cycle_report.get_meta("isolated_pack_ids", []), ["fixture_cycle_a", "fixture_cycle_b"], "fixture cycle ids are deterministic")


func _test_stable_dependency_order(suite) -> void:
	var resolver = ContentPackResolverScript.new()
	var base := _descriptor("base", "1.0.0", 50, [], true)
	var alpha := _descriptor("alpha", "1.0.0", 20, [_dependency("base", ">=1.0.0 <2.0.0")])
	var beta := _descriptor("beta", "1.0.0", 10, [_dependency("base", ">=1.0.0 <2.0.0")])
	var report = resolver.resolve([alpha, base, beta], "0.5.0-dev")
	suite.assert_true(not report.has_blocking_errors(), "valid dependency graph resolves")
	suite.assert_equal(report.get_meta("activation_order", []), ["base", "beta", "alpha"], "dependency order and load order are deterministic")
	var active: Array = report.get_meta("active_descriptors", [])
	active[0]["pack_id"] = "mutated"
	suite.assert_equal(report.get_meta("activation_order", [])[0], "base", "resolution metadata is isolated")


func _test_duplicate_pack_ids(suite) -> void:
	var resolver = ContentPackResolverScript.new()
	var first := _descriptor("base", "1.0.0", 0, [], true)
	var second := _descriptor("base", "1.1.0", 1, [], false)
	var report = resolver.resolve([first, second], "0.5.0-dev")
	suite.assert_true(report.has_blocking_errors(), "duplicate required pack id blocks activation")
	suite.assert_true(report.get_meta("activation_order", []).is_empty(), "duplicate id activates nothing")


func _test_missing_dependencies(suite) -> void:
	var resolver = ContentPackResolverScript.new()
	var optional := _descriptor("optional_mod", "1.0.0", 10, [_dependency("ghost", ">=1.0.0")], false)
	var optional_report = resolver.resolve([_descriptor("base", "1.0.0", 0, [], true), optional], "0.5.0-dev")
	suite.assert_true(not optional_report.has_blocking_errors(), "missing optional dependency is isolated")
	suite.assert_equal(optional_report.get_meta("isolated_pack_ids", []), ["optional_mod"], "optional dependant is identified")
	suite.assert_equal(optional_report.get_meta("activation_order", []), ["base"], "unrelated base remains active")

	var required := _descriptor("base", "1.0.0", 0, [_dependency("ghost", ">=1.0.0")], true)
	var required_report = resolver.resolve([required], "0.5.0-dev")
	suite.assert_true(required_report.has_blocking_errors(), "missing required dependency blocks activation")


func _test_dependency_versions(suite) -> void:
	var resolver = ContentPackResolverScript.new()
	var base := _descriptor("base", "1.0.0", 0, [], true)
	var optional := _descriptor("optional_mod", "1.0.0", 10, [_dependency("base", ">=2.0.0")], false)
	var report = resolver.resolve([base, optional], "0.5.0-dev")
	suite.assert_true(not report.has_blocking_errors(), "optional dependency version mismatch is isolated")
	suite.assert_equal(report.get_meta("isolated_pack_ids", []), ["optional_mod"], "version-mismatched dependant is isolated")


func _test_dependency_cycles(suite) -> void:
	var resolver = ContentPackResolverScript.new()
	var mod_a := _descriptor("mod_a", "1.0.0", 10, [_dependency("mod_b", ">=1.0.0")], false)
	var mod_b := _descriptor("mod_b", "1.0.0", 20, [_dependency("mod_a", ">=1.0.0")], false)
	var optional_report = resolver.resolve([_descriptor("base", "1.0.0", 0, [], true), mod_b, mod_a], "0.5.0-dev")
	suite.assert_true(not optional_report.has_blocking_errors(), "optional dependency cycle is isolated")
	suite.assert_equal(optional_report.get_meta("isolated_pack_ids", []), ["mod_a", "mod_b"], "cycle members are isolated deterministically")
	suite.assert_equal(optional_report.get_meta("activation_order", []), ["base"], "base activates outside optional cycle")

	var required_a := _descriptor("base", "1.0.0", 0, [_dependency("required_b", ">=1.0.0")], true)
	var required_b := _descriptor("required_b", "1.0.0", 1, [_dependency("base", ">=1.0.0")], true)
	var required_report = resolver.resolve([required_a, required_b], "0.5.0-dev")
	suite.assert_true(required_report.has_blocking_errors(), "required dependency cycle blocks activation")


func _test_game_version_isolation(suite) -> void:
	var resolver = ContentPackResolverScript.new()
	var base := _descriptor("base", "1.0.0", 0, [], true)
	var future := _descriptor("future_mod", "1.0.0", 10, [], false, ">=9.0.0")
	var optional_report = resolver.resolve([future, base], "0.5.0-dev")
	suite.assert_true(not optional_report.has_blocking_errors(), "future optional pack is isolated")
	suite.assert_equal(optional_report.get_meta("isolated_pack_ids", []), ["future_mod"], "future pack is reported")
	suite.assert_equal(optional_report.get_meta("activation_order", []), ["base"], "compatible base remains active")

	var incompatible_base := _descriptor("base", "1.0.0", 0, [], true, ">=9.0.0")
	var required_report = resolver.resolve([incompatible_base], "0.5.0-dev")
	suite.assert_true(required_report.has_blocking_errors(), "incompatible required pack blocks activation")


func _descriptor(
	pack_id: String,
	pack_version: String,
	load_order: int,
	dependencies: Array,
	required_pack: bool = false,
	game_version_range: String = ">=0.4.0-dev <1.0.0"
) -> Dictionary:
	return {
		"pack_id": pack_id,
		"pack_version": pack_version,
		"schema_version": 2,
		"game_version_range": game_version_range,
		"dependencies": dependencies.duplicate(true),
		"load_order": load_order,
		"content_manifest": [],
		"localization_sources": [],
		"asset_manifest": [],
		"integrity_hashes": {},
		"entitlement_tag": "",
		"required_pack": required_pack,
		"root_path": "res://tests/fixtures/content_packs",
		"fingerprint_sha256": "0".repeat(64),
	}


func _dependency(pack_id: String, version_range: String) -> Dictionary:
	return {
		"pack_id": pack_id,
		"version_range": version_range,
		"required": true,
	}
