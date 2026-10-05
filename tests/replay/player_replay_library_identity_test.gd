extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Binding := preload("res://scripts/content/content_snapshot_provider.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const Recorder := preload("res://scripts/replay/replay_recorder.gd")
const Library := preload("res://scripts/replay/player_replay_library.gd")
const Factory := preload("res://scripts/progression/meta_catalog_factory.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const MetaProjection := preload("res://scripts/progression/meta_run_projection.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "identity tests use canonical content")
	var catalog: RefCounted = Factory.load_base().context.catalog
	var profile := Fixtures.profile(catalog)
	for weapon: String in ["sword", "bow", "gun", "staff", "gauntlets"]:
		profile.forge_state[weapon].level = 5
	var projection: Dictionary = MetaProjection.from_profile(profile, catalog).context.projection
	var library := Library.new()
	add_child(library)
	suite.assert_true(library.configure(OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("identity_library"), "0.4.0-dev", Binding.snapshot(registry), "slot_1", "base").ok, "identity archive configures")
	var characters := ["wanderer", "time_guardian", "void_walker", "primordial_knight", "time_lord"]
	var weapons := ["sword", "bow", "gun", "staff", "gauntlets"]
	for index: int in range(5):
		var source := await Fixture.spawn(self, registry, suite, "identity-recording-%d" % index, 777, true)
		var config := {"milestone": "LAUNCH", "character_id": characters[index], "weapon_id": weapons[index], "character_profile": registry.resolve_character_runtime_profile(StringName(characters[index]), &"LAUNCH"), "weapon_profile": registry.resolve_weapon_runtime_profile(StringName(weapons[index]), &"LAUNCH"), "enabled_time_skills": ["stop", "rewind"], "meta_run_projection": projection}
		for repeat: int in range(3):
			suite.assert_true(source.configure_loadout(config), "actual source builds non-default Meta generation")
		var recorder := Recorder.new()
		var identity: Dictionary = source.full_player_replay_identity()
		suite.assert_true(int(identity.owner_character_generation) > 2, "actual native generation exceeds default")
		suite.assert_true(recorder.start_full_player_recording(identity, 777).ok, "actual Meta identity records")
		var intents := {"dash": [], "time": [], "weapon": [], "character": [], "movement": Vector2.RIGHT, "aim": Vector2.RIGHT, "meta": {}}
		for frame: int in range(3):
			if frame > 0:
				suite.assert_true(source.advance_action_frame(intents), "actual Meta source advances")
			suite.assert_true(recorder.record_full_player_frame(source.full_player_replay_snapshot(), intents).ok, "actual Meta state records")
		var replay: Dictionary = recorder.finish_full_player_recording().replay
		var stored: Dictionary = library.store(replay)
		suite.assert_true(stored.ok, "Meta recording archives")
		if stored.ok:
			var selected: Dictionary = library.select(stored.context.id)
			suite.assert_true(selected.ok, "native viewer reconstructs Meta character/weapon/generation: %s %s" % [characters[index], str(selected)])
			if selected.ok:
				suite.assert_equal(library.current_player().full_player_replay_identity(), identity, "viewer restores exact recorded initial identity")
				suite.assert_true(library.seek(2).ok, "Meta timeline restores later state")
				suite.assert_equal(library.current_player().full_player_replay_snapshot(), replay.frames[2].snapshot, "Meta frame matches every participant")
		var live := await Fixture.spawn(self, registry, suite, "live-reconstruction-%d" % index, 777)
		var before: Dictionary = live.full_player_replay_snapshot()
		suite.assert_true(not live.configure_replay_view_identity(identity), "live Player cannot adopt imported identity")
		suite.assert_equal(live.full_player_replay_snapshot(), before, "rejected live reconstruction is atomic")
		live.queue_free()
		source.get_parent().queue_free()
		await get_tree().process_frame
	library.queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())
