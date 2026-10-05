extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Content := preload("res://scripts/content/content_snapshot_provider.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const Recorder := preload("res://scripts/replay/replay_recorder.gd")
const Ops := preload("res://scripts/save/save_file_ops.gd")
const ARCHIVE_PATH := "res://scripts/replay/player_replay_archive.gd"

var _suite: RefCounted
var _registry: RefCounted
var _binding: Dictionary
var _root_path: String


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_suite = Suite.new()
	_suite.assert_true(ResourceLoader.exists(ARCHIVE_PATH), "validated physical player replay archive must exist")
	if not ResourceLoader.exists(ARCHIVE_PATH):
		_suite.finish(get_tree())
		return
	_registry = Registry.new()
	var report = _registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	_suite.assert_true(not report.has_blocking_errors(), "archive uses actual launch content")
	_binding = Content.snapshot(_registry)
	_root_path = ProjectSettings.globalize_path("res://build/test-data/player-replay-archive-%d" % Time.get_ticks_usec())
	var first := await _record("archive-first", 701)
	var second := await _record("archive-second", 702)
	await _test_physical_round_trip(first)
	_test_rejection(first)
	_test_faults_and_stale_writer(first, second)
	_test_capacity_and_deleted_duplicate(first)
	Ops.new().remove_tree(_root_path)
	_suite.finish(get_tree())


func _archive(scope: String, injector: Callable = Callable()) -> RefCounted:
	var archive: RefCounted = load(ARCHIVE_PATH).new()
	var configured: Dictionary = archive.configure(_root_path.path_join(scope), "0.4.0-dev", _binding, "slot_1", "base", injector)
	_suite.assert_true(configured.ok, "archive configures actual isolated storage: " + str(configured))
	return archive


func _test_physical_round_trip(replay: Dictionary) -> void:
	var archive := _archive("round-trip")
	var stored: Dictionary = archive.store(replay)
	_suite.assert_true(stored.ok, "actual player recording is physically archived: " + str(stored))
	if not stored.ok:
		return
	var id: String = stored.context.id
	var original: Dictionary = archive.snapshot()
	_suite.assert_equal(archive.load_replay(id).context.replay, replay, "safe codec preserves exact native Variant data")
	var read: Dictionary = archive.load_replay(id).context.replay
	read.frames.clear()
	_suite.assert_equal(archive.load_replay(id).context.replay, replay, "archive reads cannot mutate stored recording")
	_suite.assert_true(archive.store(replay).ok, "duplicate storage is idempotent")
	_suite.assert_equal(archive.snapshot(), original, "duplicate does not add entry/revision")
	var fresh := _archive("round-trip")
	_suite.assert_equal(fresh.snapshot(), original, "fresh archive physically reloads committed state")
	var exported: Dictionary = fresh.export_json(id)
	_suite.assert_true(exported.ok, "archive exports portable safe JSON package")
	var recipient := _archive("recipient")
	var imported: Dictionary = recipient.import_json(exported.context.json)
	_suite.assert_true(imported.ok, "fresh archive imports and validates entire recording")
	_suite.assert_equal(recipient.load_replay(id).context.replay, replay, "portable package round trip is exact")
	_suite.assert_true(recipient.remove(id).ok, "explicit removal persists")
	_suite.assert_equal(_archive("recipient").snapshot().entries.size(), 0, "fresh physical read sees removal")
	_suite.assert_true(not recipient.export_json("../../slot_1").ok, "package ID cannot address paths")


func _test_rejection(replay: Dictionary) -> void:
	var archive := _archive("rejection")
	var before: Dictionary = archive.snapshot()
	var forged := replay.duplicate(true)
	forged.frames[1].snapshot.player_state.position += Vector2(13, 0)
	_suite.assert_true(not archive.store(forged).ok, "unrehashed semantic changes are rejected")
	var future := replay.duplicate(true)
	future.schema_version = 999
	_suite.assert_true(not archive.store(future).ok, "unsupported replay version is rejected")
	var rehashed := replay.duplicate(true)
	rehashed.frames[1].frame_intents.movement = Vector2(99, 0)
	rehashed.frames[1].digest = Recorder.full_player_frame_digest(rehashed.frames[1])
	rehashed.terminal_digest = Recorder.full_player_terminal_digest(rehashed)
	_suite.assert_true(not archive.store(rehashed).ok, "recomputed hashes cannot admit invalid movement semantics")
	_suite.assert_true(not archive.import_json('{"payload":{"script":"res://scripts/main.gd"}}').ok, "unknown object-shaped package is rejected")
	_suite.assert_equal(archive.snapshot(), before, "failed imports never mutate archive")
	var stored: Dictionary = archive.store(replay)
	if not stored.ok:
		_suite.assert_true(false, "compatibility fixture stores")
		return
	var encoded: String = archive.export_json(stored.context.id).context.json
	var other: RefCounted = load(ARCHIVE_PATH).new()
	_suite.assert_true(other.configure(_root_path.path_join("other-domain"), "0.4.0-dev", _binding, "slot_1", "mod_fixture").ok, "other save domain configures")
	_suite.assert_true(not other.import_json(encoded).ok, "base replay cannot cross Mod isolation")
	var future_game: RefCounted = load(ARCHIVE_PATH).new()
	_suite.assert_true(future_game.configure(_root_path.path_join("other-game"), "0.5.0-dev", _binding, "slot_1", "base").ok, "other game version configures")
	_suite.assert_true(not future_game.import_json(encoded).ok, "unsupported game build refuses package")
	var other_binding := _binding.duplicate(true)
	other_binding.packs[0].pack_version = "999.0.0"
	other_binding.aggregate_sha256 = preload("res://scripts/save/save_envelope.gd").content_snapshot_digest(other_binding.packs)
	var other_content: RefCounted = load(ARCHIVE_PATH).new()
	_suite.assert_true(other_content.configure(_root_path.path_join("other-content"), "0.4.0-dev", other_binding, "slot_1", "base").ok, "other content snapshot configures isolated archive")
	_suite.assert_true(not other_content.import_json(encoded).ok, "other content snapshot refuses portable replay")


func _test_faults_and_stale_writer(first: Dictionary, second: Dictionary) -> void:
	var writer := _archive("stale")
	var stale := _archive("stale")
	_suite.assert_true(writer.store(first).ok, "first writer advances physical primary")
	_suite.assert_true(not stale.store(second).ok, "stale instance cannot overwrite newer physical primary")
	_suite.assert_equal(_archive("stale").snapshot(), writer.snapshot(), "stale refusal preserves newer recording")
	_suite.assert_true(stale.reload().ok and stale.store(second).ok, "explicit refresh permits non-destructive next write")
	var pending := _archive("pending", func(point: StringName): return point == &"before_primary_promote")
	var before: Dictionary = pending.snapshot()
	_suite.assert_true(not pending.store(first).ok, "pre-promotion write fault is reported")
	_suite.assert_equal(pending.snapshot(), before, "failed pending write preserves committed memory")
	pending.set_fault_injector(Callable())
	_suite.assert_true(pending.store(first).ok, "physical write can retry after a pending failure")
	_suite.assert_equal(_archive("pending").snapshot(), pending.snapshot(), "retried state is physically durable")
	var promoted := _archive("promoted", func(point: StringName): return point == &"after_primary_promote")
	var outcome: Dictionary = promoted.store(first)
	_suite.assert_true(outcome.ok and outcome.context.reconciled_committed_write, "post-promotion fault verifies actual committed candidate")
	_suite.assert_equal(_archive("promoted").snapshot(), promoted.snapshot(), "reconciled state physically reloads")
	var competitor := _archive("interleaved")
	var callback_state := [false, false]
	var interleaved := _archive("interleaved", func(point: StringName):
		if point == &"before_primary_promote" and not callback_state[0]:
			callback_state[0] = true
			callback_state[1] = competitor.store(second).ok
		return false)
	_suite.assert_true(not interleaved.store(first).ok and callback_state[1], "physical compare-exchange refuses an interleaved writer at promotion")
	_suite.assert_equal(_archive("interleaved").snapshot(), competitor.snapshot(), "interleaved refusal preserves actual winning primary")
	var recover := _archive("recovery")
	_suite.assert_true(recover.store(first).ok, "backup recovery fixture commits first recording")
	var backup: Dictionary = recover.snapshot()
	_suite.assert_true(recover.store(second).ok, "backup recovery fixture rotates previous recording")
	var primary_path := _root_path.path_join("recovery/profiles").path_join(str(recover.get("_save_id"))).path_join("local/primary.json")
	_suite.assert_true(Ops.new().write_utf8(primary_path, "{damaged-primary").ok, "test damages only its isolated primary file")
	_suite.assert_equal(_archive("recovery").snapshot(), backup, "fresh archive recovers verified prior recording from physical backup")


func _test_capacity_and_deleted_duplicate(replay: Dictionary) -> void:
	var archive := _archive("capacity")
	for index: int in range(20):
		var entry := replay.duplicate(true)
		entry.seed += index
		entry.terminal_digest = Recorder.full_player_terminal_digest(entry)
		_suite.assert_true(archive.store(entry).ok, "bounded archive retains recording %d" % index)
	var before: Dictionary = archive.snapshot()
	var overflow := replay.duplicate(true)
	overflow.seed += 21
	overflow.terminal_digest = Recorder.full_player_terminal_digest(overflow)
	_suite.assert_true(not archive.store(overflow).ok, "twenty-first recording is explicitly refused")
	_suite.assert_equal(archive.snapshot(), before, "capacity refusal never evicts a saved recording")
	var writer := _archive("duplicate-race")
	var stored: Dictionary = writer.store(replay)
	var stale := _archive("duplicate-race")
	_suite.assert_true(writer.remove(stored.context.id).ok, "another instance explicitly removes recording")
	_suite.assert_true(not stale.store(replay).ok, "stale duplicate cannot claim physically deleted recording exists")


func _record(run_id: String, seed_value: int) -> Dictionary:
	return await Fixture.record(self, _registry, _suite, run_id, seed_value)
