extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const State := preload("res://autoload/game_state.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Snapshots := preload("res://scripts/content/content_snapshot_provider.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Profile := preload("res://scripts/progression/meta_profile_state.gd")
const Envelope := preload("res://scripts/save/save_envelope.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "production boot consumes a validated actual Base pack")
	var target := Snapshots.snapshot(registry)
	var catalog: RefCounted = Factory.load_base().context.catalog
	var state := State.new()
	suite.assert_true(state.has_method("activate_profile_content"), "GameState needs explicit actual-content Profile activation before native launch")
	if not state.has_method("activate_profile_content"):
		state.free()
		suite.finish(get_tree())
		return
	var packs := [{"pack_id": "base", "pack_version": "0.4.0-dev", "schema_version": 1, "fingerprint_sha256": "1".repeat(64)}]
	var known_legacy := {"packs": packs, "aggregate_sha256": Envelope.content_snapshot_digest(packs)}
	for case_id: String in ["fresh", "actual_v4", "known_legacy", "unknown_content"]:
		var path := Paths.resolve_default("user://p16-profile-boot/" + case_id + "/legacy.json", "p16-profile-boot/" + case_id + "/legacy.json")
		var root := path.get_base_dir().path_join("plane_walker/save")
		var save := Save.new()
		var source := known_legacy if case_id == "known_legacy" else target
		if case_id == "unknown_content":
			source = target.duplicate(true)
			source.packs[0].fingerprint_sha256 = "2".repeat(64)
			source.aggregate_sha256 = Envelope.content_snapshot_digest(source.packs)
		suite.assert_true(save.configure(root, "0.4.0-dev", source).ok, "physical profile fixture configures")
		if case_id != "fresh":
			var payload := {"chronos_shards": 37, "sentinel": {"nested": ["preserved", 12]}}
			if case_id != "known_legacy":
				save.enable_meta_profile(catalog)
				var profile := Profile.new()
				profile.configure(catalog)
				payload["meta_profile_state"] = profile.snapshot()
				payload.meta_profile_state.chronos_shards = 37
			var seeded = save.save_profile("slot_1", "base", payload)
			suite.assert_true(seeded.ok, "fixture primary saves: " + case_id + " " + str(seeded.to_dictionary()))
		var primary_path := root.path_join("profiles/slot_1/base/primary.json")
		var before := FileAccess.get_file_as_string(primary_path) if case_id != "fresh" else ""
		state.save_path = path
		add_child(state)
		suite.assert_equal(FileAccess.get_file_as_string(primary_path) if case_id != "fresh" else "", before, "autoload settings boot never mutates a Profile before actual-content activation")
		var prior := state.persistent.duplicate(true)
		var result: Dictionary = state.activate_profile_content(registry)
		if case_id == "unknown_content":
			suite.assert_true(not result.ok and result.code == &"CONTENT_MISMATCH", "unknown content cannot self-authorize a new binding")
			suite.assert_equal(state.persistent, prior, "refused production boot preserves authoritative memory")
			suite.assert_equal(FileAccess.get_file_as_string(primary_path), before, "refused production boot preserves actual bytes")
			suite.assert_true(state.profile_runtime_service() == null, "refused content cannot expose a launch-capable Profile")
		else:
			suite.assert_true(result.ok, "production Profile activates: " + case_id + " " + str(result))
			var service: RefCounted = state.profile_runtime_service()
			suite.assert_true(service != null, "actual durable Profile service is available to Main")
			if service != null:
				var profile: Dictionary = service.snapshot()
				suite.assert_equal(profile.chronos_shards, 0 if case_id == "fresh" else 37, "production boot never mints currency")
				suite.assert_equal(profile.unlocked_characters, ["wanderer"], "fresh and migrated Profile own the real starter character")
				suite.assert_equal(profile.unlocked_weapons, ["bow", "sword"], "canonical starter weapons survive compatibility composition")
				suite.assert_equal(profile.launch_sequence, 0, "content activation cannot begin or settle a run")
				suite.assert_equal(state.persistent.meta_profile_state, profile, "GameState mirror comes from the authoritative Profile snapshot")
				var owned := state.persistent.duplicate(true)
				var owned_bytes := FileAccess.get_file_as_string(primary_path) if FileAccess.file_exists(primary_path) else ""
				suite.assert_true(not state.save_persistent(), "legacy blanket writes cannot replace an activated Profile")
				suite.assert_true(not state.record_run_summary({"result": "victory", "rooms_cleared": 99}), "legacy summaries cannot mint rewards or statistics")
				state.reset_persistent_data(false)
				state.reset_persistent_data(true)
				suite.assert_equal(state.persistent, owned, "legacy reset preserves the activated authoritative mirror")
				suite.assert_equal(service.snapshot(), profile, "legacy callers cannot retire, reset, or revive the live Profile")
				suite.assert_equal(FileAccess.get_file_as_string(primary_path) if FileAccess.file_exists(primary_path) else "", owned_bytes, "legacy reset and writes preserve actual primary bytes")
				if case_id != "fresh":
					var actual := Save.new()
					actual.configure(root, "0.4.0-dev", target)
					actual.enable_meta_profile(catalog)
					var inspected = actual.inspect_profile("slot_1", "base")
					suite.assert_true(inspected.ok and inspected.payload.get("schema_version") == 4, "physical primary is current schema and actual content: " + case_id + " " + str(inspected.to_dictionary()))
					if inspected.ok:
						suite.assert_equal(inspected.payload.payload.sentinel, {"nested": ["preserved", 12.0]}, "whole extension payload survives production rebinding")
					var bytes := FileAccess.get_file_as_string(primary_path)
					suite.assert_true(state.activate_profile_content(registry).ok, "same production binding is idempotent")
					suite.assert_equal(FileAccess.get_file_as_string(primary_path), bytes, "repeated activation cannot consume another save sequence")
		state.queue_free()
		await get_tree().process_frame
		state = State.new()
	state.free()
	suite.finish(get_tree())
