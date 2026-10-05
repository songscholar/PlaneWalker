extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const BuildCodec := preload("res://scripts/progression/build_share_codec.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const Package := preload("res://scripts/replay/player_replay_package.gd")

class Adapter extends RefCounted:
	var answer: Variant = {"ok": false, "code": "OFFLINE", "context": {}}
	var seen: Dictionary = {}
	func perform(_operation: String, request: Dictionary) -> Variant:
		seen = request.duplicate(true)
		request.clear()
		return answer


func _ready() -> void:
	var suite := Suite.new()
	var offline_path := "res://scripts/platform/offline_platform_provider.gd"
	var composed_path := "res://scripts/platform/composed_platform_provider.gd"
	suite.assert_true(ResourceLoader.exists(offline_path) and ResourceLoader.exists(composed_path), "platform composition and offline capability service exist")
	if not ResourceLoader.exists(offline_path) or not ResourceLoader.exists(composed_path):
		suite.finish(get_tree())
		return
	var offline_script: Script = load(offline_path)
	var composed_script: Script = load(composed_path)
	var binding: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save/pack_snapshots/base_a.json"))
	var root := Paths.resolve_default("user://platform_composition", "platform_composition")
	var offline: RefCounted = offline_script.new()
	suite.assert_true(offline.configure(root, "test-p24", binding, "owner", "base").ok, "offline composition fixture configures")
	var composed: RefCounted = composed_script.new()
	suite.assert_true(composed.configure(offline).ok and composed.identity().status == "OFFLINE", "no optional provider needs no credentials")
	var adapter := Adapter.new()
	composed.configure(offline, adapter)
	var result: Dictionary = composed.unlock_achievement("adapter_failed")
	suite.assert_true(result.ok and result.status == "OFFLINE_FALLBACK" and result.context.inserted, "failed optional provider keeps durable local unlock")
	suite.assert_equal(composed.status().context.last_failure, "OFFLINE", "fallback clearly identifies structured provider failure")
	adapter.answer = {"ok": true, "code": "OK", "context": {"id": "bad identity", "display_name": "Remote"}}
	suite.assert_equal(composed.identity().status, "OFFLINE_FALLBACK", "malformed optional success fails back locally")
	adapter.answer = {"ok": true, "code": "OK", "context": {"id": "remote_owner", "display_name": "Remote"}}
	result = composed.identity()
	suite.assert_true(result.ok and result.status == "ONLINE" and result.context.display_name == "Remote", "validated optional identity is available")
	result.context.display_name = "Mutated"
	suite.assert_equal(adapter.answer.context.display_name, "Remote", "optional response cannot mutate adapter data")
	adapter.answer = {"ok": true, "code": "OK", "context": {"entries": [{"id": "friend_a", "display_name": "Friend", "activity": "hub"}]}}
	suite.assert_true(composed.friends().context.entries.size() == 1, "validated optional friends overlay the empty fallback")
	adapter.answer.context.entries[0].activity = "script://unsafe"
	suite.assert_true(composed.friends().status == "OFFLINE_FALLBACK" and composed.friends().context.entries.is_empty(), "invalid optional presence cannot reach presentation")
	var fixture := [{"pack_id": "expansion_one", "entitlement_tag": "free_one", "name_key": "PACK_ONE_NAME", "description_key": "PACK_ONE_DESC", "local_source_path": "res://tests/fixtures/content_packs/valid_base"}]
	suite.assert_true(offline.configure_local_content(["res://tests/fixtures/content_packs/valid_base", "res://tests/fixtures/content_packs/invalid_script"], fixture, ["free_one"]).ok, "local content discovery accepts safe configured sources")
	fixture[0].pack_id = "mutated"
	var owned: Dictionary = offline.entitlements()
	suite.assert_true(owned.ok and owned.context.entries[0].pack_id == "expansion_one" and owned.context.entries[0].owned and not owned.context.supports_purchase, "entitlement fixture is detached and never enables purchase")
	var discovered: Dictionary = offline.discover_content()
	suite.assert_true(discovered.ok and discovered.context.entries.size() == 1 and discovered.context.diagnostics.size() == 1, "data-only discovery excludes script-bearing pack and records diagnostic")
	suite.assert_true(not offline.configure_local_content(["res://../outside"], [], []).ok, "discovery rejects path traversal")
	var build := {"id": "share_fixture", "name": "Local Build", "character_id": "wanderer", "weapon_id": "sword", "time_abilities": ["stop", "rewind"]}
	var shared: Dictionary = offline.share_build(build)
	suite.assert_true(shared.ok and FileAccess.file_exists(shared.context.path), "build share produces a real local artifact")
	if shared.ok:
		var code := FileAccess.get_file_as_string(shared.context.path)
		suite.assert_true(BuildCodec.decode(code).ok, "exported share artifact is a validated build code")
		suite.assert_true(offline.share_build(build).context.duplicate, "content-addressed share retry is idempotent")
	var image := Image.create(32, 18, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.8, 0.2, 0.3))
	var captured: Dictionary = offline.capture_screenshot(image)
	suite.assert_true(captured.ok and FileAccess.file_exists(captured.context.path), "screenshot hook exports real PNG")
	if captured.ok:
		var decoded := Image.new()
		suite.assert_equal(decoded.load(captured.context.path), OK, "exported PNG is decodable")
		suite.assert_equal(decoded.get_size(), Vector2i(32, 18), "screenshot dimensions are retained")
	suite.assert_equal(offline.capture_screenshot(Image.new()).code, &"INVALID_ARGUMENT", "empty screenshot cannot enter artifacts")
	suite.assert_true(not offline.share_replay({"schema_id": "bad"}).ok, "malformed replay is refused before export")
	suite.assert_equal(composed.perform("cloud_write", {"key": "../escape", "value": {}}).code, &"INVALID_ARGUMENT", "bad request is refused before optional forwarding")
	var registry := Registry.new()
	var report = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not report.has_blocking_errors(), "share proof loads actual launch content")
	var actual_binding := Content.snapshot(registry)
	var replay := await Fixture.record(self, registry, suite, "platform-share", 807)
	var created := Package.create(replay, "0.4.0-dev", actual_binding, "base")
	suite.assert_true(created.ok, "share proof creates a verified actual Player replay package")
	if created.ok:
		var replay_provider: RefCounted = offline_script.new()
		replay_provider.configure(root.path_join("replay_platform"), "0.4.0-dev", actual_binding, "owner", "base")
		var exported: Dictionary = replay_provider.share_replay(created.context.package)
		suite.assert_true(exported.ok and FileAccess.file_exists(exported.context.path), "actual Player replay exports as a physical share artifact")
		if exported.ok:
			suite.assert_true(Package.decode(FileAccess.get_file_as_string(exported.context.path), "0.4.0-dev", actual_binding, "base").ok, "physical shared replay revalidates with authoritative package decoder")
		created.context.package.save_domain = "foreign"
		suite.assert_true(not replay_provider.share_replay(created.context.package).ok, "shared replay cannot escape its content/domain scope")
	suite.finish(get_tree())
