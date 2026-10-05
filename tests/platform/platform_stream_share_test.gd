extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const Fixtures := preload("res://tests/support/p16_progression_fixtures.gd")
const Stream := preload("res://scripts/replay/run_replay_stream_store.gd")
const Router := preload("res://scripts/replay/replay_library_router.gd")
const Coordinator := preload("res://scripts/platform/platform_service_coordinator.gd")
const Provider := preload("res://scripts/platform/offline_platform_provider.gd")
const Save := preload("res://scripts/save/save_service.gd")
const Service := preload("res://scripts/progression/profile_runtime_service.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var binding := Content.snapshot(registry)
	var root := Paths.resolve_default("user://platform_stream_share", "platform_stream_share")
	var storage := Stream.new()
	suite.assert_true(storage.configure(root.path_join("stream"), "0.4.0-dev", binding, "owner", "base").ok, "stream share uses actual authenticated store")
	var player := await Fixture.spawn(self, registry, suite, "platform-whole-run", 621, true)
	var started := storage.begin(player.full_player_replay_identity(), 621)
	suite.assert_true(started.ok, "native Player identity starts tape")
	var id: String = started.context.id
	var observations: Array[Dictionary] = [{"sequence": 0, "kind": "frame", "player": player.full_player_replay_snapshot(), "run": {"run_id": "platform-whole-run", "run_seed": 621}, "native": {}}]
	suite.assert_true(storage.append(id, observations).ok and storage.finish(id, "INTERRUPTED").ok, "real native snapshot becomes a storage-complete authenticated tape")
	var exported := storage.export_json(id)
	suite.assert_true(exported.ok, "authoritative stream export is available")
	var package: Dictionary = JSON.parse_string(exported.context.json)
	var provider := Provider.new()
	suite.assert_true(provider.configure(root.path_join("platform"), "0.4.0-dev", binding, "owner", "base").ok, "whole-run share provider configures")
	var shared := provider.share_replay(package)
	suite.assert_true(shared.ok, "platform accepts authenticated interrupted whole-run tape: " + str(shared.code))
	if shared.ok:
		var imported := Stream.new()
		imported.configure(root.path_join("verify"), "0.4.0-dev", binding, "owner", "base")
		suite.assert_true(imported.import_json(FileAccess.get_file_as_string(shared.context.path)).ok and imported.read(id, 0).ok, "physical platform export imports and reconstructs its native observation")
	var malformed := package.duplicate(true)
	malformed.chunks[0].base64 = "AAAA"
	suite.assert_true(not provider.share_replay(malformed).ok, "bad compressed chunk refuses before platform export")
	malformed = package.duplicate(true)
	malformed.compatibility.game_version = "0.5.0-dev"
	suite.assert_true(not provider.share_replay(malformed).ok, "incompatible whole-run share refuses")
	var router := Router.new()
	add_child(router)
	suite.assert_true(router.configure(root.path_join("library"), "0.4.0-dev", binding, "owner", "base").ok and router.attach_stream_store(storage, registry).ok, "production replay router attaches whole-run store")
	var catalog := Fixtures.catalog()
	var save := Save.new()
	save.configure(root.path_join("profile"), "0.4.0-dev", binding)
	var profile := Service.new()
	profile.configure(catalog, save, "owner", "base", {"meta_profile_state": Fixtures.profile(catalog)})
	var coordinator := Coordinator.new()
	suite.assert_true(coordinator.configure(provider, profile).ok and coordinator.attach_replay_library(router).ok and coordinator.refresh().ok, "native platform coordinator sees routed authenticated tapes")
	var result := coordinator.execute("share_replay", {"id": "run:" + id}, int(coordinator.snapshot().revision))
	suite.assert_true(result.ok and FileAccess.file_exists(result.context.path), "native platform command exports whole-run router package: " + str(result.code))
	router.queue_free()
	player.get_parent().queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())
