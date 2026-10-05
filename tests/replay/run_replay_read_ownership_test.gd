extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Binding := preload("res://scripts/content/content_snapshot_provider.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const Store := preload("res://scripts/replay/run_replay_stream_store.gd")
const Codec := preload("res://scripts/replay/run_replay_chunk_codec.gd")
var suite: RefCounted


class CountingStore extends "res://scripts/replay/run_replay_stream_store.gd":
	var read_calls := 0

	func _read_chunk(descriptor: Dictionary) -> Dictionary:
		read_calls += 1
		return super._read_chunk(descriptor)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	suite = Suite.new()
	var registry := Registry.new()
	var content_report: RefCounted = registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	suite.assert_true(not content_report.has_blocking_errors(), "ownership fixture activates actual launch content")
	var root := OS.get_environment("PLANEWALKER_TEST_DATA_DIR").path_join("replay_read_ownership")
	var store := CountingStore.new()
	var binding := Binding.snapshot(registry)
	suite.assert_true(store.configure(root, "0.4.0-dev", binding, "slot_1", "base").ok, "ownership fixture configures actual physical Store")
	var player := await Fixture.spawn(self, registry, suite, "read-ownership", 533, true)
	var begun: Dictionary = store.begin(player.full_player_replay_identity(), 533)
	suite.assert_true(begun.ok, "real admitted Player identity opens physical ownership recording")
	if not begun.ok:
		player.get_parent().queue_free()
		await get_tree().process_frame
		suite.finish(get_tree())
		return
	var id: String = begun.context.id
	var source := _observations(0, 120)
	var expected: Array[Dictionary] = source.duplicate(true)
	suite.assert_true(store.append(id, source).ok and store.append(id, _observations(120, 3)).ok, "actual Store persists full and partial independent chunks")
	var descriptor: Dictionary = store.snapshot().entries[0].chunks[0]
	var path := str(store.storage_identity().chunk_directory).path_join(str(descriptor.compressed_sha256) + ".zst")
	var physical := FileAccess.get_file_as_bytes(path)
	var physical_hash := Codec.byte_digest(physical)
	store.read_calls = 0
	var cold: Dictionary = store.call("_observations", descriptor)
	suite.assert_true(cold.ok and is_same(cold.context.observations, store.get("_cached_observations")), "cold owned Codec array transfers to the private cache without a second whole-chunk tree")
	var warm: Dictionary = store.call("_observations", descriptor)
	suite.assert_true(warm.ok and is_same(warm.context.observations, store.get("_cached_observations")), "warm private observations borrow the cache without duplicating all 120 frames")
	suite.assert_equal(store.read_calls, 2, "both cold and warm private observations physically reauthenticate bytes")
	suite.assert_equal(var_to_bytes(cold.context.observations), var_to_bytes(expected), "owned or borrowed arrays preserve exact typed observations")
	suite.assert_true(not is_same(cold.context.observations[0].data, cold.context.observations[1].data) and not is_same(cold.context.observations[0].data.rows, cold.context.observations[1].data.rows), "decoded neighboring frames keep independent mutable containers")
	for sequence: int in [0, 1, 60, 119, 0]:
		var before_reads := store.read_calls
		var exported: Dictionary = store.read(id, sequence)
		suite.assert_true(exported.ok and var_to_bytes(exported.context.observation) == var_to_bytes(expected[sequence]), "public random seek exports exact detached typed frame")
		suite.assert_equal(store.read_calls, before_reads + 1, "each public cached seek physically reauthenticates its chunk")
		_mutate(exported.context.observation)
		var repeated: Dictionary = store.read(id, sequence)
		suite.assert_true(repeated.ok and var_to_bytes(repeated.context.observation) == var_to_bytes(expected[sequence]), "public nested caller mutations cannot poison cached or later outputs")
		suite.assert_equal(var_to_bytes(store.get("_cached_observations")[sequence]), var_to_bytes(expected[sequence]), "public caller retains no mutable aliases into private cache")
	var transitions: Dictionary = store.transition_rows(id)
	suite.assert_true(transitions.ok and transitions.context.rows.size() == 2, "borrowed observations preserve transition-only public projection across both chunks")
	transitions.context.rows[0].room_id = "foreign"
	transitions.context.rows.clear()
	suite.assert_equal(store.transition_rows(id).context.rows.size(), 2, "public transition mutations cannot affect cached observations or later projections")
	suite.assert_true(store.read(id, 122).ok and store.read(id, 0).ok and var_to_bytes(store.read(id, 119).context.observation) == var_to_bytes(expected[119]), "cross-chunk replacement and prior seek remain exact")
	suite.assert_true(store.reload().ok and store.get("_cached_observations").is_empty() and store.get("_cached_digest") == "", "physical reload clears all private cached ownership")
	suite.assert_true(store.read(id, 0).ok, "independent physical reload reconstructs an authentic cold frame")
	var before: Dictionary = store.snapshot()
	var corrupt := physical.duplicate()
	corrupt[0] ^= 255
	_write(path, corrupt)
	var refused: Dictionary = store.read(id, 0)
	suite.assert_true(not refused.ok and refused.code == &"RUN_REPLAY_STORE_CHUNK_CORRUPT" and store.snapshot() == before, "warm private ownership cannot hide actual corrupt compressed bytes")
	_write(path, physical)
	suite.assert_true(store.read(id, 0).ok, "restored authentic bytes recover normal warm cache read")
	suite.assert_equal(DirAccess.remove_absolute(path), OK, "ownership fixture removes only its own exact physical chunk path")
	refused = store.read(id, 0)
	suite.assert_true(not refused.ok and refused.code == &"RUN_REPLAY_STORE_CHUNK_MISSING" and store.snapshot() == before, "warm private ownership cannot hide missing physical bytes")
	_write(path, physical)
	suite.assert_true(store.read(id, 0).ok and Codec.byte_digest(FileAccess.get_file_as_bytes(path)) == physical_hash, "exact restored physical hash and public frame remain original")
	var decoded_chunk: Dictionary = descriptor.duplicate(true)
	decoded_chunk.bytes = physical
	var decoded: Dictionary = Codec.decode(decoded_chunk)
	suite.assert_true(decoded.ok, "unchanged Codec exposes independently reconstructed public frame array")
	_mutate(decoded.context.observations[0])
	suite.assert_equal(var_to_bytes(decoded.context.observations[1]), var_to_bytes(expected[1]), "mutating one public decoded frame cannot change its neighboring frame")
	suite.assert_equal(var_to_bytes(Codec.decode(decoded_chunk).context.observations), var_to_bytes(expected), "mutable decoded output cannot change authentic bytes or a fresh decode")
	player.get_parent().queue_free()
	await get_tree().process_frame
	suite.finish(get_tree())


func _observations(first: int, count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for sequence: int in range(first, first + count):
		var labels: Array[String] = ["native", "accepted"]
		var counters: Dictionary[String, int] = {"claim": sequence}
		result.append({"sequence": sequence, "kind": "room_transition" if sequence % 120 == 0 else "frame", "scene": {"binding": {"floor_id": "floor_1", "node_id": "room_1"}}, "data": {"rows": [{&"amount": float(sequence), "labels": labels}], "counters": counters, "points": PackedVector2Array([Vector2(sequence, 1)]), "bytes": PackedByteArray([1, 2, 3]), "integer": sequence, "float": float(sequence)}})
	return result


func _mutate(value: Dictionary) -> void:
	value.sequence = -1
	value.data.rows[0][&"amount"] = 999.0
	value.data.rows[0].labels.append("changed")
	value.data.counters.claim = 999
	var points: PackedVector2Array = value.data.points
	points[0] = Vector2(99, 99)
	value.data.points = points
	var bytes: PackedByteArray = value.data.bytes
	bytes[0] = 99
	value.data.bytes = bytes
	value.data.erase("integer")


func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	suite.assert_true(file != null, "ownership fixture writes only its exact isolated chunk path")
	if file != null:
		file.store_buffer(bytes)
		file.close()
