extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Paths := preload("res://scripts/save/runtime_user_data_path.gd")
const Save := preload("res://scripts/save/save_service.gd")


func _ready() -> void:
	var suite := Suite.new()
	var path := "res://scripts/platform/offline_platform_provider.gd"
	suite.assert_true(ResourceLoader.exists(path), "durable offline platform provider exists")
	if not ResourceLoader.exists(path):
		suite.finish(get_tree())
		return
	var script: Script = load(path)
	var binding: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/save/pack_snapshots/base_a.json"))
	var root := Paths.resolve_default("user://platform_test", "platform_test")
	var provider: RefCounted = script.new()
	suite.assert_true(provider.configure(root, "test-p24", binding, "owner", "base").ok, "offline provider configures real durable scope")
	var identity: Dictionary = provider.identity()
	suite.assert_true(identity.ok and identity.status == "OFFLINE" and identity.context.id.begins_with("local_"), "identity clearly reports offline status")
	suite.assert_true(provider.set_display_name("Walker").ok, "display name is durably writable")
	var unlocked: Dictionary = provider.unlock_achievement("first_run")
	suite.assert_true(unlocked.ok and unlocked.context.inserted, "first unlock commits")
	var duplicate: Dictionary = provider.unlock_achievement("first_run")
	suite.assert_true(duplicate.ok and duplicate.context.duplicate, "unlock is idempotent")
	var restarted: RefCounted = script.new()
	suite.assert_true(restarted.configure(root, "test-p24", binding, "owner", "base").ok, "restart loads durable platform state")
	suite.assert_equal(restarted.achievements().context.ids, ["first_run"], "restart retains achievement")
	suite.assert_equal(restarted.identity().context.display_name, "Walker", "restart retains display name")
	var copy: Dictionary = restarted.achievements()
	copy.context.ids.clear()
	suite.assert_equal(restarted.achievements().context.ids, ["first_run"], "public response is detached")
	for point: StringName in Save.FAULT_POINTS:
		var id := "fault_" + str(point)
		provider.set_fault_injector(func(at: StringName): return at == point)
		var result: Dictionary = provider.unlock_achievement(id)
		if point == &"after_primary_promote":
			suite.assert_true(result.ok and result.context.reconciled_committed_write, "committed primary reconciles ambiguous unlock")
		else:
			suite.assert_true(not result.ok and not provider.achievements().context.ids.has(id), "unpromoted fault retains prior state: " + str(point))
		provider.set_fault_injector(Callable())
		suite.assert_true(provider.unlock_achievement(id).ok, "retry completes faulted unlock: " + str(point))
	var cloud: Dictionary = provider.cloud_write("slot_backup", {"chapter": 2, "flags": ["first"]})
	suite.assert_true(cloud.ok and cloud.context.digest.length() == 64, "cloud cache writes canonical local JSON")
	var digest: String = cloud.context.digest
	var cloud_read: Dictionary = provider.cloud_read("slot_backup")
	suite.assert_true(cloud_read.ok, "cloud cache validates after JSON round trip: " + str(cloud_read))
	if cloud_read.ok:
		suite.assert_equal(cloud_read.context.value.chapter, 2, "cloud reads persisted local value")
	suite.assert_equal(provider.cloud_write("slot_backup", {"chapter": 3}, "a".repeat(64)).code, &"CLOUD_CONFLICT", "stale cloud write refuses replacement")
	suite.assert_true(provider.cloud_write("slot_backup", {"chapter": 3}, digest).ok, "current digest permits cloud replacement")
	suite.assert_equal(provider.cloud_write("../escape", {}).code, &"INVALID_ARGUMENT", "cloud path escape is rejected")
	suite.assert_equal(provider.cloud_write("too_big", {"text": "x".repeat(65537)}).code, &"INVALID_ARGUMENT", "cloud value byte limit is enforced")
	suite.assert_equal(provider.cloud_write("deep", {"object": self}).code, &"INVALID_ARGUMENT", "objects cannot enter persistent JSON")
	suite.assert_true(provider.cloud_list().context.entries.size() == 1, "cloud listing exposes only committed keys")
	suite.assert_true(provider.cloud_remove("slot_backup").ok, "cloud local removal commits")
	suite.assert_equal(provider.cloud_read("slot_backup").code, &"NOT_FOUND", "removed cloud key stays absent")
	suite.assert_true(provider.submit_score("daily", "run_a", 100, 5000).ok, "local leaderboard accepts bounded entry")
	suite.assert_true(provider.submit_score("daily", "run_b", 100, 2000).ok, "local leaderboard accepts second entry")
	suite.assert_true(provider.submit_score("daily", "run_a", 100, 5000).context.duplicate, "leaderboard entry id is consumed once")
	suite.assert_equal(provider.submit_score("daily", "run_a", 200, 5000).code, &"ENTRY_CONFLICT", "conflicting entry identity fails closed")
	var board: Dictionary = provider.leaderboard("daily")
	suite.assert_true(board.ok and not board.context.ranked and board.context.entries[0].id == "run_b", "local ranking is unranked with deterministic time tie break")
	suite.assert_true(provider.leaderboard("daily", "global").context.scope == "local", "global request has explicit local fallback")
	var isolated: RefCounted = script.new()
	isolated.configure(root, "test-p24", binding, "owner", "mod_test")
	suite.assert_true(isolated.achievements().context.ids.is_empty() and isolated.leaderboard("daily").context.entries.is_empty(), "Mod/domain platform state is isolated")
	var alternate := binding.duplicate(true)
	alternate.packs[0].fingerprint_sha256 = "b".repeat(64)
	alternate.aggregate_sha256 = preload("res://scripts/save/save_envelope.gd").content_snapshot_digest(alternate.packs)
	isolated = script.new()
	isolated.configure(root, "test-p24", alternate, "owner", "base")
	suite.assert_true(isolated.achievements().context.ids.is_empty(), "content bindings have separate platform state")
	suite.assert_equal(provider.friends().context.entries, [], "offline friends are empty")
	suite.assert_true(provider.set_presence("hub").ok and provider.presence().context.activity == "hub", "offline presence is useful locally")
	suite.assert_equal(provider.set_presence("arbitrary activity").code, &"INVALID_ARGUMENT", "presence vocabulary is bounded")
	suite.assert_equal(provider.set_display_name("\nBad").code, &"INVALID_ARGUMENT", "control characters cannot enter display name")
	suite.assert_equal(provider.perform("unlock_achievement", {"id": "valid", "unknown": true}).code, &"INVALID_ARGUMENT", "unknown request fields are rejected")
	suite.assert_equal(provider.perform("unknown", {}).code, &"UNSUPPORTED_OPERATION", "unknown operations fail structurally")
	var interleaved := {"done": false, "ok": false}
	provider.set_fault_injector(func(at: StringName):
		if at == &"before_primary_promote" and not interleaved.done:
			interleaved.done = true
			interleaved.ok = restarted.unlock_achievement("competing").ok
		return false)
	suite.assert_equal(provider.unlock_achievement("interleaved").code, &"STALE_PRIMARY", "competing writer cannot lose an achievement")
	suite.assert_true(interleaved.ok, "competing writer commits")
	provider.set_fault_injector(Callable())
	suite.assert_true(provider.unlock_achievement("interleaved").ok and provider.achievements().context.ids.has("competing"), "retry merges competing durable achievements")
	suite.finish(get_tree())
