extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")
const Compatibility := preload("res://scripts/progression/meta_profile_compatibility.gd")
const Registry := preload("res://scripts/save/save_migration_registry.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Save := preload("res://scripts/save/save_service.gd")
const RuntimePaths := preload("res://scripts/save/runtime_user_data_path.gd")
const Run := preload("res://scripts/application/run_state.gd")


func _ready() -> void:
	var suite = Suite.new()
	var loaded: Dictionary = Factory.load_base()
	suite.assert_true(loaded.ok, "authoritative progression content loads for migration")
	if not loaded.ok:
		suite.finish(get_tree())
		return
	var catalog: RefCounted = loaded.context.catalog
	var v3: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save/profile_v3.json"))
	var source: Dictionary = v3.duplicate(true)
	var migrated = Registry.new().migrate(v3, 4, {"meta_catalog": catalog})
	suite.assert_true(migrated.ok, "declared v3-to-v4 step migrates authenticated legacy profile")
	if not migrated.ok:
		suite.finish(get_tree())
		return
	suite.assert_equal(v3, source, "migration never modifies source document or integrity")
	var profile: Dictionary = migrated.payload.payload.meta_profile_state
	suite.assert_equal(profile.chronos_shards, 21, "existing shard balance is retained")
	suite.assert_equal(profile.existential_imprints, 5, "existing imprints are retained without first-Boss fabrication")
	suite.assert_equal(profile.statistics.finished_runs, 6, "existing finished-run statistics are retained")
	suite.assert_equal(profile.statistics.victories, 2, "existing victories are retained")
	var sealed = Envelope.reseal_current(migrated.payload, catalog)
	suite.assert_true(sealed.ok and Envelope.validate(sealed.payload, &"profile", "slot_1", "base", catalog).ok, "migrated strict v4 profile reseals and validates")
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(sealed.payload))
	suite.assert_true(Envelope.validate(round_trip, &"profile", "slot_1", "base", catalog).ok, "actual JSON numeric normalization preserves v4 profile")
	var contradiction: Dictionary = sealed.payload.duplicate(true)
	contradiction.payload.chronos_shards += 1
	suite.assert_true(not Envelope.reseal_current(contradiction, catalog).ok, "contradictory mirror cannot be resealed as authoritative state")
	var forward: Dictionary = sealed.payload.duplicate(true)
	forward.schema_version = 5
	suite.assert_equal(Envelope.validate(forward, &"profile", "slot_1", "base", catalog).code, &"FORWARD_VERSION", "unknown newer profile schema fails closed")
	var tampered: Dictionary = v3.duplicate(true)
	tampered.payload.chronos_shards += 1
	suite.assert_true(not Registry.new().migrate(tampered, 4, {"meta_catalog": catalog}).ok, "authentication precedes v3 progression import")
	var bad: Dictionary = v3.duplicate(true)
	bad.payload.unlocked_nodes = ["F-09"]
	suite.assert_true(not Compatibility.from_legacy(bad.payload, catalog).ok, "nonexistent legacy unlock fails explicitly")
	for prior_version: int in [1, 2]:
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save/profile_v%d.json" % prior_version))
		var chained = Registry.new().migrate(previous, 4, {"meta_catalog": catalog})
		suite.assert_true(chained.ok, "authenticated schema-%d migrates through each declared step" % prior_version)
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save/legacy_v0.json"))
	var legacy_source := legacy.duplicate(true)
	var legacy_step = Registry.new().migrate(legacy, 3)
	suite.assert_true(legacy_step.ok, "legacy wrapper follows existing declared pre-envelope import path")
	var legacy_created = Envelope.create_profile("slot_legacy", "base", 1, "test-v4", "2026-10-04T00:00:00Z", "2026-10-04T00:00:00Z", v3.content_snapshot, legacy_step.payload.payload, catalog)
	suite.assert_true(legacy_created.ok, "full real legacy profile imports into v4 including achievement and default cosmetic: %s" % str(legacy_created.to_dictionary()))
	if legacy_created.ok:
		var owned: Dictionary = legacy_created.payload.payload.meta_profile_state
		suite.assert_equal(owned.unlocked_nodes, ["W-01"], "declared legacy node alias preserves its upgrade")
		suite.assert_equal(owned.unlocked_achievements, ["first_return"], "existing achievement survives import")
		suite.assert_equal(owned.cosmetics, ["wanderer.default"], "legacy cosmetic maps to explicit scoped identity")
		suite.assert_equal(owned.weapon_proficiency.sword, 4, "partial legacy proficiency merges into all five weapons")
		suite.assert_equal(owned.npc_affinity.odysseus, 2, "partial legacy affinity merges into all eight NPCs")
		suite.assert_true(Envelope.validate(legacy_created.payload, &"profile", "slot_legacy", "base", catalog).ok, "imported legacy state authenticates as strict v4")
	suite.assert_equal(legacy, legacy_source, "legacy import preserves exact original wrapper")
	var state = Run.new()
	state.reset_domain({"milestone": "M1", "seed": 4}, "legacy-active-run")
	var legacy_payload: Dictionary = v3.payload.duplicate(true)
	legacy_payload["unlocked_nodes"] = ["W-01"]
	legacy_payload.active_run_state = state.snapshot()
	var imported: Dictionary = Compatibility.from_legacy(legacy_payload, catalog)
	suite.assert_true(imported.ok, "legacy in-flight state and owned upgrade migrate together")
	if imported.ok:
		var frozen: Dictionary = imported.context.payload.active_run_state.resources.meta_run_projection
		suite.assert_true(MetaProjection.validate(frozen, catalog), "legacy run receives a valid frozen no-benefit projection")
		suite.assert_equal(frozen.stat_bonuses.max_hp, 0.0, "later profile unlock cannot improve an already active run")
		suite.assert_equal(imported.context.payload.meta_profile_state.unlocked_nodes, ["W-01"], "owned upgrade is preserved for later launches")
		var valid_active = Envelope.create_profile("slot_1", "base", 13, "test-v4", "2026-10-04T00:00:00Z", "2026-10-04T00:00:00Z", v3.content_snapshot, imported.context.payload, catalog)
		suite.assert_true(valid_active.ok, "positive control: unchanged no-benefit legacy active run can be saved: %s" % str(valid_active.to_dictionary()))
		var forged: Dictionary = imported.context.payload.duplicate(true)
		forged.active_run_state.resources.meta_run_projection = MetaProjection.from_profile(forged.meta_profile_state, catalog).context.projection
		var created = Envelope.create_profile("slot_1", "base", 13, "test-v4", "2026-10-04T00:00:00Z", "2026-10-04T00:00:00Z", v3.content_snapshot, forged, catalog)
		suite.assert_true(not created.ok, "legacy active run cannot replace no-benefit state with later purchased effects")
		suite.assert_equal(created.metadata.get("reason"), "profile_run_mismatch", "forged benefit refusal specifically comes from run/Profile matching")
	var root := RuntimePaths.resolve_default("user://p16-meta-migration", "p16-meta-migration")
	var save = Save.new()
	suite.assert_true(save.configure(root, "test-meta-v4", v3.content_snapshot).ok, "isolated physical Save service configures")
	suite.assert_true(save.enable_meta_profile(catalog).ok, "profile-v4 support enables without changing settings schema")
	var directory := root.path_join("profiles/slot_1/base")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory.path_join("primary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(v3))
	file.close()
	var restored = save.load_profile("slot_1", "base")
	suite.assert_true(restored.ok, "physical authenticated v3 primary loads via declared migration: %s" % str(restored.to_dictionary()))
	if restored.ok:
		suite.assert_equal(restored.payload.meta_profile_state.chronos_shards, 21, "physical migration preserves legacy balance")
		var original_backup := FileAccess.open(directory.path_join("backup_1.json"), FileAccess.READ)
		var original: Dictionary = JSON.parse_string(original_backup.get_as_text())
		original_backup.close()
		suite.assert_equal(original, v3, "raw authenticated source remains exactly recoverable after migration")
		suite.assert_true(save.save_profile("slot_1", "base", restored.payload).ok, "next durable write promotes strict schema-v4")
		suite.assert_equal(save.inspect_profile("slot_1", "base").payload.schema_version, 4, "new profile primary declares schema-v4")
		var backup := FileAccess.open(directory.path_join("backup_1.json"), FileAccess.READ)
		var retained: Dictionary = JSON.parse_string(backup.get_as_text())
		backup.close()
		suite.assert_true(Envelope.validate(retained, &"profile", "slot_1", "base", catalog).ok, "migration leaves a validated recoverable backup")
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save/settings_v3.json"))
	suite.assert_true(save.save_settings(settings.payload).ok, "settings continue writing independently")
	var settings_file := FileAccess.open(root.path_join("global/settings/primary.json"), FileAccess.READ)
	var persisted: Dictionary = JSON.parse_string(settings_file.get_as_text())
	settings_file.close()
	suite.assert_equal(persisted.schema_version, 3, "global settings version remains three")
	suite.finish(get_tree())
