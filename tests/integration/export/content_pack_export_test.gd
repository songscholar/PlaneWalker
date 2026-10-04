extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Descriptor := preload("res://scripts/content/content_pack_descriptor.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Main := preload("res://scenes/main.tscn")
const PACK_PATH := "res://data/content_packs/base/pack.json"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var descriptor: Dictionary = Descriptor.load_path(PACK_PATH, true)
	suite.assert_true(descriptor.ok, "source or packed Base descriptor authenticates every declared original byte: " + str(descriptor.context))
	var registry := Registry.new()
	var report = registry.load_packs([{"path": PACK_PATH, "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "source or packed full Launch content activates: " + str(report.blocking_errors))
	var texture := load("res://data/content_packs/base/assets/enemies/launch/acid_pool.png") as Texture2D
	suite.assert_true(texture != null and texture.get_width() > 0, "original-byte preservation also retains native imported Texture2D loading")
	var scene := load("res://data/content_packs/base/assets/rooms/launch/room_boss_void_throne.tscn") as PackedScene
	suite.assert_true(scene != null, "original-byte preservation also retains compiled PackedScene loading")
	if descriptor.ok and not report.has_blocking_errors():
		var main := Main.instantiate()
		add_child(main)
		await get_tree().process_frame
		suite.assert_equal(main.get("_profile_error"), "", "actual Main boots a durable production Profile from authenticated content")
		var service: RefCounted = GameState.profile_runtime_service()
		suite.assert_true(service != null and not service.snapshot().is_empty(), "actual Main exposes the initialized production Profile")
		var hub: Node = main.get_node_or_null("HubFlowCoordinator")
		suite.assert_true(hub != null and hub.is_hub_visible(), "actual Main opens its playable Hub from exported resources")
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		suite.assert_true(FocusCoordinator.active_scope() == null, "exported Main retires all focus scopes without retaining presentation nodes")
	suite.finish(get_tree())
