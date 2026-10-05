extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Codec := preload("res://scripts/replay/run_replay_chunk_codec.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var shared := _observations()
	var detached: Array[Dictionary] = shared.duplicate(true)
	var original := var_to_bytes(shared)
	var cold_usec := 9223372036854775807
	var warm_usec := 9223372036854775807
	for repeat: int in range(2):
		var started := Time.get_ticks_usec()
		var cold := Codec.encode(detached)
		cold_usec = mini(cold_usec, Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		var warm := Codec.encode(shared)
		warm_usec = mini(warm_usec, Time.get_ticks_usec() - started)
		suite.assert_true(cold.ok and warm.ok, "mutable and readonly observations remain admissible")
		if cold.ok and warm.ok:
			suite.assert_equal(var_to_bytes(warm.context.chunk), var_to_bytes(cold.context.chunk), "readonly sharing preserves every typed envelope field and compressed byte")
			var decoded := Codec.decode(warm.context.chunk)
			suite.assert_true(decoded.ok and var_to_bytes(decoded.context.observations) == original, "shared histories preserve exact typed cold readback")
	print("CODEC_IMMUTABLE_THROUGHPUT cold_usec=%d shared_usec=%d" % [cold_usec, warm_usec])
	suite.assert_true(warm_usec * 5 < cold_usec * 3, "120-frame shared immutable history encodes within 60 percent of detached history time")
	suite.assert_equal(var_to_bytes(shared), original, "encode never mutates immutable caller observations")
	_replacements(suite, shared)
	_depths(suite)
	_untrusted_aliases(suite)
	_typed_and_ordered(suite)
	_signed_values(suite)
	_workers(suite, shared)
	suite.finish(get_tree())


func _observations() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for index: int in range(40):
		var children: Array[Dictionary] = []
		for child: int in range(48):
			children.append({"id": &"receipt", "index": child, "amount": float(child), "position": Vector2(child, index), "tags": ["weapon", "accepted"]})
		events.append({"capture_sequence": index + 1, "data": children})
	_freeze(events)
	var observations: Array[Dictionary] = []
	for sequence: int in range(120):
		var history := events.duplicate(false)
		history.make_read_only()
		observations.append({"sequence": sequence, "player": {"frame": sequence, "weapon_replay_events": history}})
	return observations


func _replacements(suite: RefCounted, source: Array[Dictionary]) -> void:
	var before: Array = source[0].player.weapon_replay_events
	var replaced := before.duplicate(false)
	var event: Dictionary = before[7].duplicate(true)
	event.data[0].amount = 900.0
	_freeze(event)
	replaced[7] = event
	replaced.make_read_only()
	var appended := replaced.duplicate(false)
	var next := {"capture_sequence": 41, "data": []}
	_freeze(next)
	appended.append(next)
	appended.make_read_only()
	var observations: Array[Dictionary] = [{"sequence": 0, "history": before}, {"sequence": 1, "history": replaced}, {"sequence": 2, "history": appended}]
	var chunk := Codec.encode(observations)
	suite.assert_true(chunk.ok, "same-count slot replacement and append remain admissible")
	if chunk.ok:
		var decoded := Codec.decode(chunk.context.chunk)
		suite.assert_true(decoded.ok and var_to_bytes(decoded.context.observations) == var_to_bytes(observations), "replacement never reuses the earlier immutable slot's value")


func _depths(suite: RefCounted) -> void:
	var boundary: Variant = 1
	for index: int in range(31):
		boundary = {"next": boundary}
	_freeze(boundary)
	var valid: Array[Dictionary] = [{"sequence": 0, "shared": boundary}, {"sequence": 1, "shared": boundary}]
	suite.assert_true(Codec.encode(valid).ok, "first complete walk accepts the exact depth boundary")
	var too_deep: Array[Dictionary] = [{"sequence": 0, "shared": boundary}, {"sequence": 1, "shared": {"nested": boundary}}]
	suite.assert_true(not Codec.encode(too_deep).ok, "a reference certified shallower cannot bypass a deeper observation's depth limit")


func _untrusted_aliases(suite: RefCounted) -> void:
	var vectors := PackedVector2Array([Vector2.ONE])
	var packed_owner := {"vectors": vectors}
	packed_owner.make_read_only()
	var observations: Array[Dictionary] = [{"sequence": 0, "shared": packed_owner}, {"sequence": 1, "shared": packed_owner}]
	suite.assert_true(Codec.encode(observations).ok, "readonly containers with packed descendants retain the full cold path")
	vectors[0] = Vector2(NAN, 0)
	suite.assert_true(not Codec.encode(observations).ok, "a mutable packed alias cannot reuse an earlier safety certificate")
	var nullable := {"value": null}
	_freeze(nullable)
	observations = [{"sequence": 0, "shared": nullable}]
	suite.assert_true(Codec.encode(observations).ok, "a safe null representation warms independently")
	var node := Node.new()
	node.free()
	var invalid := {"value": node}
	invalid.make_read_only()
	suite.assert_equal(var_to_bytes(invalid), var_to_bytes(nullable), "freed Object collision is an exact typed serialization fixture")
	observations = [{"sequence": 0, "shared": invalid}]
	suite.assert_true(not Codec.encode(observations).ok, "a byte-identical freed Object never acquires an immutable safety certificate")
	var mutable := {"amount": 1.0}
	var readonly_parent := {"child": mutable}
	readonly_parent.make_read_only()
	observations = [{"sequence": 0, "shared": readonly_parent}]
	suite.assert_true(Codec.encode(observations).ok, "readonly parent with mutable child remains admitted through cold checks")
	mutable.amount = INF
	suite.assert_true(not Codec.encode(observations).ok, "mutable descendant cannot preserve a prior safety certificate")


func _typed_and_ordered(suite: RefCounted) -> void:
	var integers: Array[int] = []
	var floats: Array[float] = []
	integers.make_read_only()
	floats.make_read_only()
	var observations: Array[Dictionary] = [{"sequence": 0, "array": integers, "dictionary": {"a": 1, "b": &"x"}}, {"sequence": 1, "array": floats, "dictionary": {"b": "x", "a": 1.0}}]
	var encoded := Codec.encode(observations)
	suite.assert_true(encoded.ok, "typed empty arrays and reordered dictionaries encode")
	if encoded.ok:
		var decoded := Codec.decode(encoded.context.chunk)
		suite.assert_true(decoded.ok and var_to_bytes(decoded.context.observations) == var_to_bytes(observations), "type and insertion order remain bit-exact under immutable comparisons")
	var named_keys := {&"key": 1}
	var string_keys := {"key": 1}
	_freeze(named_keys)
	_freeze(string_keys)
	observations = [{"sequence": 0, "keys": named_keys}, {"sequence": 1, "keys": string_keys}]
	encoded = Codec.encode(observations)
	var decoded := Codec.decode(encoded.context.chunk)
	suite.assert_true(decoded.ok and var_to_bytes(decoded.context.observations) == var_to_bytes(observations), "Godot-equivalent StringName and String keys preserve exact key types")
	var typed_root: Dictionary[String, Variant] = {"sequence": 0, "state": 1}
	observations = [typed_root, {"sequence": 1, "state": 1}]
	encoded = Codec.encode(observations)
	decoded = Codec.decode(encoded.context.chunk)
	suite.assert_true(decoded.ok and var_to_bytes(decoded.context.observations) == var_to_bytes(observations), "typed root dictionary changes remain exact whole-root patches")
	var float_key := {1.0: "invalid"}
	_freeze(float_key)
	observations = [{"sequence": 0, "keys": named_keys}, {"sequence": 1, "keys": float_key}]
	suite.assert_true(not Codec.encode(observations).ok, "loose numeric key equivalence never bypasses unsafe float-key rejection")


func _signed_values(suite: RefCounted) -> void:
	var negative_zero := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	var positives: Array = [0.0, Vector2(0.0, 1.0), Vector3(0.0, 1.0, 2.0), Vector4(0.0, 1.0, 2.0, 3.0), Color(0.0, 1.0, 0.5, 1.0)]
	var negatives: Array = [negative_zero, Vector2(negative_zero, 1.0), Vector3(negative_zero, 1.0, 2.0), Vector4(negative_zero, 1.0, 2.0, 3.0), Color(negative_zero, 1.0, 0.5, 1.0)]
	positives.make_read_only()
	negatives.make_read_only()
	suite.assert_true(var_to_bytes(positives) != var_to_bytes(negatives), "signed-zero scalar/vector fixture contains different typed bytes")
	var observations: Array[Dictionary] = [{"sequence": 0, "array": positives}, {"sequence": 1, "array": negatives}]
	var encoded := Codec.encode(observations)
	var cold := Codec.encode(observations.duplicate(true))
	suite.assert_true(encoded.ok and cold.ok and var_to_bytes(encoded.context.chunk) == var_to_bytes(cold.context.chunk), "immutable scalar arrays retain signed zeros in exact compressed patches")
	if encoded.ok:
		var decoded := Codec.decode(encoded.context.chunk)
		suite.assert_true(decoded.ok and var_to_bytes(decoded.context.observations) == var_to_bytes(observations), "signed-zero observation digest survives physical cold reconstruction")


func _workers(suite: RefCounted, source: Array[Dictionary]) -> void:
	var first := Thread.new()
	var second := Thread.new()
	var observations: Array[Dictionary] = [source[0], source[1]]
	var expected := Codec.encode(observations)
	suite.assert_equal(first.start(func() -> Dictionary: return Codec.encode(observations)), OK, "first isolated writer starts")
	suite.assert_equal(second.start(func() -> Dictionary: return Codec.encode(observations)), OK, "second isolated writer starts")
	var one: Dictionary = first.wait_to_finish()
	var two: Dictionary = second.wait_to_finish()
	suite.assert_equal(var_to_bytes(one), var_to_bytes(expected), "first writer retains exact bytes with its private certificate state")
	suite.assert_equal(var_to_bytes(two), var_to_bytes(expected), "parallel writer cannot reuse another encode's certificates")


func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values():
			_freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value:
			_freeze(child)
		value.make_read_only()
