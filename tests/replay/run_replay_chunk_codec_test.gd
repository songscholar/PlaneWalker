extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Registry := preload("res://scripts/content/content_registry.gd")
const Fixture := preload("res://tests/support/player_replay_fixture.gd")
const CODEC_PATH := "res://scripts/replay/run_replay_chunk_codec.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(CODEC_PATH), "whole-run bounded chunk codec must exist")
	if not ResourceLoader.exists(CODEC_PATH):
		suite.finish(get_tree())
		return
	var codec: GDScript = load(CODEC_PATH)
	var registry := Registry.new()
	registry.load_packs([{"path": "res://data/content_packs/base/pack.json", "required": true}], "0.4.0-dev", &"LAUNCH")
	var replay := await Fixture.record(self, registry, suite, "chunk-codec", 507)
	var observations: Array[Dictionary] = []
	var index := 0
	for frame: Dictionary in replay.frames:
		observations.append({"sequence": 240 + index, "player": frame.snapshot.duplicate(true), "run": {"route": ["entry"], "economy": {"gold": 10}}, "native": {}})
		index += 1
	observations[1].run.economy.gold = 12
	observations[1].run.economy["new"] = Vector2(0.1, 1.5)
	observations[2].run.economy.erase("gold")
	observations[2].run.economy["new"] = Vector2i(1, 2)
	var typed_route: Array[String] = ["entry", "shop"]
	observations[3].run = {"route": typed_route, "economy": {}, "typed": &"name"}
	observations[4].run = {"route": PackedStringArray(["boss"]), "economy": {}, "typed": "name", "integer": 1, "float": 1.0}
	var typed_economy: Dictionary[String, int] = {"gold": 12}
	observations[3].run.economy = typed_economy
	observations[4].run.economy = {"gold": 12.0}
	var original := observations.duplicate(true)
	var encoded: Dictionary = codec.encode(observations)
	suite.assert_true(encoded.ok, "actual native snapshots compress into an admitted chunk")
	if encoded.ok:
		var decoded: Dictionary = codec.decode(encoded.context.chunk)
		suite.assert_true(decoded.ok and _exact(decoded.context.observations, original), "all actual native snapshots and Variant types round-trip bit-exactly")
		decoded.context.observations[0].run.economy.gold = 999
		suite.assert_true(_exact(codec.decode(encoded.context.chunk).context.observations, original), "decoded observations cannot mutate stored bytes")
		suite.assert_true(encoded.context.chunk.compressed_size < encoded.context.chunk.raw_size, "native repeated snapshots are materially compressed")
		var corrupt: Dictionary = encoded.context.chunk.duplicate(true)
		corrupt.bytes[0] ^= 255
		suite.assert_true(not codec.decode(corrupt).ok, "corrupted compressed bytes refuse")
		var oversized: Dictionary = encoded.context.chunk.duplicate(true)
		oversized.raw_size = 32 * 1024 * 1024 + 1
		suite.assert_true(not codec.decode(oversized).ok, "advertised decompression over budget refuses before decoding")
		var tampered: Dictionary = encoded.context.chunk.duplicate(true)
		var raw: PackedByteArray = tampered.bytes.decompress(tampered.raw_size, FileAccess.COMPRESSION_ZSTD)
		var payload: Dictionary = bytes_to_var(raw)
		payload.deltas[0].removed.append(["absent"])
		var malformed := var_to_bytes(payload)
		tampered.raw_size = malformed.size()
		tampered.raw_sha256 = codec.byte_digest(malformed)
		tampered.bytes = malformed.compress(FileAccess.COMPRESSION_ZSTD)
		tampered.compressed_size = tampered.bytes.size()
		tampered.compressed_sha256 = codec.byte_digest(tampered.bytes)
		suite.assert_true(not codec.decode(tampered).ok, "correctly rehashed nonexistent deletion still refuses")
		payload = bytes_to_var(raw)
		payload.deltas[0].set.append(payload.deltas[0].set[0].duplicate(true))
		suite.assert_true(not codec.decode(_repackage(codec, encoded.context.chunk, payload)).ok, "rehashed duplicate patch paths refuse")
		payload = bytes_to_var(raw)
		payload.deltas[0].set.append({"path": ["player"], "value": observations[1].player.duplicate(true)})
		suite.assert_true(not codec.decode(_repackage(codec, encoded.context.chunk, payload)).ok, "rehashed overlapping parent and child patches refuse")
		payload = bytes_to_var(raw)
		payload.deltas[0].sequence += 1
		suite.assert_true(not codec.decode(_repackage(codec, encoded.context.chunk, payload)).ok, "rehashed noncontiguous delta sequence refuses")
	var gap := original.duplicate(true)
	gap[2].sequence += 1
	suite.assert_true(not codec.encode(gap).ok, "sequence gaps refuse before compression")
	var invalid := original.duplicate(true)
	invalid[0].run["object"] = self
	suite.assert_true(not codec.encode(invalid).ok, "objects cannot enter an encoded replay chunk")
	invalid = original.duplicate(true)
	invalid[0].run["number"] = NAN
	suite.assert_true(not codec.encode(invalid).ok, "nonfinite replay values refuse")
	invalid = original.duplicate(true)
	invalid[0].run["vectors"] = PackedVector2Array([Vector2(NAN, 0)])
	suite.assert_true(not codec.encode(invalid).ok, "nonfinite packed vector values refuse")
	invalid = original.duplicate(true)
	var object_array: Array[Node] = []
	invalid[0].run["empty_object_array"] = object_array
	suite.assert_true(not codec.encode(invalid).ok, "empty object-typed arrays cannot introduce resource identities")
	var too_many: Array[Dictionary] = []
	for sequence: int in range(121):
		too_many.append({"sequence": sequence, "state": {}})
	suite.assert_true(not codec.encode(too_many).ok, "chunk cannot exceed 120 observations")
	suite.assert_true(_exact(observations, original), "encoding and malformed inputs preserve caller-owned snapshots")
	suite.finish(get_tree())


func _exact(left: Variant, right: Variant) -> bool:
	return var_to_bytes(left) == var_to_bytes(right)


func _repackage(codec: GDScript, source: Dictionary, payload: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	var raw := var_to_bytes(payload)
	result.raw_size = raw.size()
	result.raw_sha256 = codec.byte_digest(raw)
	result.bytes = raw.compress(FileAccess.COMPRESSION_ZSTD)
	result.compressed_size = result.bytes.size()
	result.compressed_sha256 = codec.byte_digest(result.bytes)
	return result
