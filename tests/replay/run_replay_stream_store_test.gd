extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Binding := preload("res://scripts/content/content_snapshot_provider.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const STORE_PATH := "res://scripts/replay/run_replay_stream_store.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(STORE_PATH), "physical streamed whole-run store must exist")
	if not ResourceLoader.exists(STORE_PATH):
		suite.finish(get_tree())
		return
	var store_script: GDScript = load(STORE_PATH)
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var binding := Binding.snapshot(registry)
	var root := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("stream_store")
	var store: RefCounted = store_script.new()
	suite.assert_true(store.configure(root, "0.4.0-dev", binding, "slot_1", "base").ok, "actual stream binds physical game/content/profile/domain")
	var player := await Fixture.spawn(self, registry, suite, "stream-storage", 509, true)
	var started: Dictionary = store.begin(player.full_player_replay_identity(), 509)
	suite.assert_true(started.ok, "native identity opens a durable incomplete stream")
	if not started.ok:
		player.get_parent().queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var id: String = started.context.id
	var orphan_path := str(store.storage_identity().chunk_directory).path_join("a".repeat(64) + ".zst")
	var orphan := FileAccess.open(orphan_path, FileAccess.WRITE)
	orphan.store_8(1)
	orphan.close()
	var stale: RefCounted = store_script.new()
	suite.assert_true(stale.configure(root, "0.4.0-dev", binding, "slot_1", "base").ok, "second instance reads the initial durable stream")
	var expected: Array[Dictionary] = []
	var chunk: Array[Dictionary] = []
	for sequence: int in range(245):
		if sequence > 0:
			suite.assert_true(player.advance_action_frame({"movement": Vector2.RIGHT if sequence % 2 == 0 else Vector2.ZERO, "aim": Vector2.RIGHT}), "actual storage fixture accepts native frame")
		var observation := {"sequence": sequence, "kind": "frame", "player": player.full_player_replay_snapshot(), "run": {"run_id": "stream-storage", "run_seed": 509, "phase": 3, "economy": {"gold": sequence}}, "native": {}}
		expected.append(observation.duplicate(true))
		chunk.append(observation)
		if chunk.size() == 120:
			suite.assert_true(store.append(id, chunk).ok, "accepted native observations persist as an immutable chunk")
			chunk.clear()
	suite.assert_true(store.append(id, chunk).ok, "last partial chunk persists without losing frames")
	suite.assert_true(FileAccess.file_exists(orphan_path), "continuous recording defers recovery-manifest reclamation to an explicit or terminal boundary")
	suite.assert_equal(store.rows()[0].observation_count, 245, "physical manifest retains every committed observation")
	suite.assert_true(not stale.finish(id, "INTERRUPTED").ok, "stale finalization cannot override a newer physical manifest")
	var fresh: RefCounted = store_script.new()
	suite.assert_true(fresh.configure(root, "0.4.0-dev", binding, "slot_1", "base").ok, "fresh store reloads all physical chunk references")
	for sequence: int in [0, 119, 120, 239, 244]:
		var read: Dictionary = fresh.read(id, sequence)
		suite.assert_true(read.ok and var_to_bytes(read.context.observation) == var_to_bytes(expected[sequence]), "random physical seek reconstructs exact actual snapshot %d" % sequence)
	var duplicate := chunk.duplicate(true)
	suite.assert_true(not fresh.append(id, duplicate).ok, "already committed sequence cannot append twice")
	var before: Dictionary = fresh.snapshot()
	fresh.set_fault_injector(func(operation: StringName): return operation == &"before_primary_promote")
	suite.assert_true(not fresh.finish(id, "INTERRUPTED").ok and fresh.snapshot() == before, "failed manifest promotion preserves committed memory")
	fresh.set_fault_injector(Callable())
	suite.assert_true(fresh.finish(id, "INTERRUPTED").ok, "interrupted recording is explicit and durably finalized")
	suite.assert_true(not FileAccess.file_exists(orphan_path), "terminal archive transaction reclaims unreferenced managed bytes")
	suite.assert_equal(fresh.rows()[0].status, "INTERRUPTED", "interrupted tape is never labeled complete")
	suite.assert_true(not fresh.append(id, []).ok, "closed stream cannot append")
	var domain: RefCounted = store_script.new()
	suite.assert_true(domain.configure(root, "0.4.0-dev", binding, "slot_1", "mod_fixture").ok and not domain.read(id, 0).ok, "different save domain cannot read a retained stream")
	var primary: Dictionary = fresh.storage_identity()
	var descriptor: Dictionary = fresh.snapshot().entries[0].chunks[0]
	var path := str(primary.chunk_directory).path_join(str(descriptor.compressed_sha256) + ".zst")
	var bytes := FileAccess.get_file_as_bytes(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	var corrupt := bytes.duplicate()
	corrupt[0] ^= 255
	file.store_buffer(corrupt)
	file.close()
	suite.assert_true(not fresh.read(id, 0).ok, "corrupt physical chunk refuses without publishing state")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	suite.assert_true(fresh.read(id, 0).ok, "restored authenticated physical bytes read normally")
	DirAccess.remove_absolute(path)
	suite.assert_true(not fresh.read(id, 0).ok, "missing committed immutable chunk refuses without fallback state")
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var changed: Dictionary = fresh.snapshot()
	changed.entries[0].chunks[0].first_sequence = 1
	suite.assert_true(not fresh._validate(changed).ok, "manifest validation refuses a sequence gap before publication")
	changed = fresh.snapshot()
	changed.entries[0].chunks[0].compressed_size = 8388609
	suite.assert_true(not fresh._validate(changed).ok, "manifest validation enforces decompression input budget")
	changed = fresh.snapshot()
	changed.entries[0].identity_base64 = "wrong"
	suite.assert_true(not fresh._validate(changed).ok, "manifest identity bytes cannot be replaced without their digest")
	changed = fresh.snapshot()
	changed.entries[0].observation_count = 164049
	suite.assert_true(not fresh._validate(changed).ok, "manifest validation enforces the complete run observation budget")
	changed = fresh.snapshot()
	changed.entries[0].compressed_bytes = 67108865
	suite.assert_true(not fresh._validate(changed).ok, "manifest validation enforces the retained run byte budget")
	var original: Dictionary = fresh.snapshot()
	changed.entries.clear()
	suite.assert_equal(fresh.snapshot(), original, "returned physical manifest is an independent projection")
	var wrong_profile: RefCounted = store_script.new()
	suite.assert_true(wrong_profile.configure(root, "0.4.0-dev", binding, "slot_2", "base").ok and not wrong_profile.read(id, 0).ok, "different physical Profile cannot read the stream")
	var wrong_version: RefCounted = store_script.new()
	suite.assert_true(wrong_version.configure(root, "0.5.0-dev", binding, "slot_1", "base").ok and not wrong_version.read(id, 0).ok, "different game version cannot read the stream")
	suite.assert_true(fresh.remove(id).ok and fresh.rows().is_empty(), "explicit removal commits the actual archive manifest")
	suite.assert_true(not store.finish(id, "INTERRUPTED").ok, "stale writer cannot resurrect a physically removed stream")
	var reload: RefCounted = store_script.new()
	suite.assert_true(reload.configure(root, "0.4.0-dev", binding, "slot_1", "base").ok and reload.rows().is_empty(), "fresh physical reload observes removal")
	var next: Dictionary = reload.begin(player.full_player_replay_identity(), 509)
	suite.assert_true(next.ok, "removed archive can retain a new independent recording")
	if next.ok:
		id = next.context.id
		suite.assert_true(not reload.finish(id, "COMPLETE").ok, "empty tape cannot claim completion")
		suite.assert_true(not reload.append(id, ["wrong-type"]).ok, "boundary rejects untyped malformed observations without a script error")
		reload.set_fault_injector(func(point: StringName): return point == &"before_primary_promote")
		before = reload.snapshot()
		suite.assert_true(not reload.append(id, [expected[0]]).ok and reload.snapshot() == before, "failed chunk reference promotion leaves previous manifest authoritative")
		reload.set_fault_injector(Callable())
		suite.assert_true(reload.append(id, [expected[0]]).ok, "authenticated orphan bytes can be reused after failed promotion")
		var saved_chunk: Dictionary = reload.snapshot().entries[0].chunks[0]
		var saved_path := str(reload.storage_identity().chunk_directory).path_join(str(saved_chunk.compressed_sha256) + ".zst")
		var saved_bytes := FileAccess.get_file_as_bytes(saved_path)
		DirAccess.remove_absolute(saved_path)
		before = reload.snapshot()
		suite.assert_true(not reload.finish(id, "COMPLETE").ok and reload.snapshot() == before, "missing physical bytes cannot become a complete recording")
		file = FileAccess.open(saved_path, FileAccess.WRITE)
		file.store_buffer(saved_bytes)
		file.close()
		reload.set_fault_injector(func(point: StringName): return point == &"after_primary_promote")
		var reconciled: Dictionary = reload.finish(id, "COMPLETE")
		suite.assert_true(reconciled.ok and reconciled.context.reconciled_committed_write, "post-promotion error reconciles only actual committed primary")
		reload.set_fault_injector(Callable())
		var complete: RefCounted = store_script.new()
		suite.assert_true(complete.configure(root, "0.4.0-dev", binding, "slot_1", "base").ok and complete.rows()[0].status == "COMPLETE" and complete.read(id, 0).ok, "fresh reload observes complete authenticated durable stream")
		var quota_path := str(reload.storage_identity().chunk_directory).path_join("quota-fixture.tmp")
		file = FileAccess.open(quota_path, FileAccess.WRITE)
		file.seek(store_script.MAX_PHYSICAL_BYTES)
		file.store_8(1)
		file.close()
		var quota: Dictionary = reload.begin(player.full_player_replay_identity(), 511)
		before = reload.snapshot()
		suite.assert_true(quota.ok and not reload.append(quota.context.id, [{"sequence": 0, "quota": "unique-bytes"}]).ok and reload.snapshot() == before, "physical quota includes removed, failed and temporary bytes rather than only manifest references")
		DirAccess.remove_absolute(quota_path)
	player.get_parent().queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())
