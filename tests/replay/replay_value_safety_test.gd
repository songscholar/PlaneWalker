extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	var accepted: Array = [null, false, true, 42, 1.5, "text", &"name", Vector2(), Vector2i(), Rect2(), Rect2i(), Vector3(), Vector3i(), Transform2D(), Vector4(), Vector4i(), Plane(), Quaternion(), AABB(), Basis(), Transform3D(), Projection(), Color(), {}, [], PackedByteArray([1]), PackedInt32Array([1]), PackedInt64Array([1]), PackedFloat32Array([1.0]), PackedFloat64Array([1.0]), PackedStringArray(["text"]), PackedVector2Array([Vector2.ONE]), PackedVector3Array([Vector3.ONE]), PackedColorArray([Color.WHITE])]
	var refused: Array = [INF, -INF, NAN, NodePath("node"), RID(), RefCounted.new(), Callable(self, "_ready"), Signal(), PackedFloat32Array([NAN]), PackedFloat32Array([INF]), PackedFloat64Array([-INF]), PackedVector4Array([Vector4.ONE])]
	var covered_types := {}
	for value: Variant in accepted:
		covered_types[typeof(value)] = true
		_verdicts(suite, value, true)
	for value: Variant in refused:
		covered_types[typeof(value)] = true
		_verdicts(suite, value, false)
	for kind: int in range(TYPE_MAX):
		suite.assert_true(covered_types.has(kind), "every current Variant category has an explicit retained verdict: " + str(kind))
	for key: Variant in ["key", &"key", 7]:
		suite.assert_true(Replay.replay_value_is_safe({key: [1.0, true]}), "authored String/StringName/integer keys remain admitted")
	for key: Variant in [1.0, true, Vector2.ONE, NodePath("key"), null]:
		suite.assert_true(not Replay.replay_value_is_safe({key: 1}), "unpermitted Dictionary keys remain refused")
	_preserved_boundaries(suite)
	_mutation_and_null(suite)
	_workers(suite)
	suite.finish(get_tree())


func _verdicts(suite: RefCounted, value: Variant, expected: bool) -> void:
	var kind := typeof(value)
	suite.assert_equal(Replay.replay_value_is_safe(value), expected, "root Variant verdict retained for " + str(kind))
	suite.assert_equal(Replay.replay_value_is_safe([value]), expected, "Array leaf verdict retained for " + str(kind))
	suite.assert_equal(Replay.replay_value_is_safe({"leaf": value}), expected, "Dictionary leaf verdict retained for " + str(kind))
	suite.assert_equal(Replay.replay_value_is_safe({"outer": [value]}), expected, "mixed container verdict retained for " + str(kind))


func _preserved_boundaries(suite: RefCounted) -> void:
	var objects: Array[Object] = []
	var object_keys: Dictionary[Object, Variant] = {}
	var object_values: Dictionary[String, Object] = {}
	for value: Variant in [objects, object_keys, object_values]:
		_verdicts(suite, value, true)
	var nested: Variant = 1.0
	for index: int in range(48):
		nested = {"nested": nested} if index % 2 == 0 else [nested]
	suite.assert_true(Replay.replay_value_is_safe(nested), "generic safety retains its existing depth behavior; chunk depth remains separate")
	for value: Variant in [Vector2(INF, NAN), Vector3(NAN, 0, 0), Vector4(0, INF, 0, 0), Color(NAN, 0, 0), Rect2(Vector2(INF, 0), Vector2.ONE), Transform2D(0, Vector2(INF, 0)), PackedVector2Array([Vector2(INF, NAN)]), PackedVector3Array([Vector3(NAN, 0, 0)]), PackedColorArray([Color(NAN, 0, 0)])]:
		_verdicts(suite, value, true)


func _mutation_and_null(suite: RefCounted) -> void:
	var input := {"state": [{"value": 2.0, "ids": PackedInt32Array([1, 2])}]}
	var bytes := var_to_bytes(input)
	suite.assert_true(Replay.replay_value_is_safe(input), "valid mutable input is admitted")
	suite.assert_equal(var_to_bytes(input), bytes, "safety traversal preserves complete typed caller bytes")
	input.state[0].value = INF
	suite.assert_true(not Replay.replay_value_is_safe(input), "a mutable leaf change is rechecked on the next call")
	var floats := PackedFloat64Array([1.0])
	var owner := {"values": floats}
	owner.make_read_only()
	suite.assert_true(Replay.replay_value_is_safe(owner), "readonly owner does not change packed Float admission")
	floats[0] = NAN
	suite.assert_true(not Replay.replay_value_is_safe(owner), "readonly parent never certifies its mutable Packed alias")
	var node := Node.new()
	node.free()
	var missing := {"value": null}
	var freed := {"value": node}
	suite.assert_equal(var_to_bytes(missing), var_to_bytes(freed), "freed Object/null fixture has equal serialization")
	suite.assert_true(Replay.replay_value_is_safe(missing), "null remains accepted")
	suite.assert_true(not Replay.replay_value_is_safe(freed), "serialization equality never turns a freed Object into a safe leaf")


func _workers(suite: RefCounted) -> void:
	var safe := {"data": [1.0, Vector2.ONE, PackedFloat32Array([2.0])]}
	var unsafe := {"data": [1.0, PackedFloat32Array([INF])]}
	var first := Thread.new()
	var second := Thread.new()
	suite.assert_equal(first.start(func(): return Replay.replay_value_is_safe(safe)), OK, "safe worker starts")
	suite.assert_equal(second.start(func(): return Replay.replay_value_is_safe(unsafe)), OK, "unsafe worker starts")
	suite.assert_true(first.wait_to_finish(), "parallel safe call retains its verdict")
	suite.assert_true(not second.wait_to_finish(), "parallel unsafe call retains its verdict without shared validation state")
