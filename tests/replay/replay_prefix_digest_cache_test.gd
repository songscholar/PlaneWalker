extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	Replay._capture_digest_cache.clear()
	Replay._prefix_digest_cache.clear()
	var event := _event(1, {"nested": {"value": 1}, "text": "[value];:"})
	var history: Array[Dictionary] = [event, _event(2, {"value": Vector2(0.1, 1.5)})]
	var original := var_to_bytes(history)
	_check(suite, history, -1, "cold full prefix")
	var hits_before: int = Replay._prefix_digest_cache.snapshot().hits
	_check(suite, history, -1, "warm full prefix")
	suite.assert_true(Replay._prefix_digest_cache.snapshot().hits > hits_before, "identical full typed history reuses certified root")
	suite.assert_equal(var_to_bytes(history), original, "digest calculation never mutates caller history")
	var baseline := Replay.event_prefix_root(history)
	history[0].payload.nested.value = 2
	_check(suite, history, -1, "same-count nested mutation")
	suite.assert_true(Replay.event_prefix_root(history) != baseline, "nested mutation cannot reuse stale digest")
	history[0] = _event(1, {"data": {"state_after": {"event_prefix_root": baseline, "receipt": 7}}})
	_check(suite, history, -1, "same-slot completed external fact replacement")
	history.reverse()
	_check(suite, history, 1, "capture order differs from playback order")
	history.append(_event(3, {"new": true}))
	_check(suite, history, -1, "appended event")
	history.resize(1)
	_check(suite, history, -1, "truncated history")
	history = bytes_to_var(original)
	_check(suite, history, -1, "restored historical source")
	for count: int in [-2, -1, 0, 1, 2, 3]:
		_check(suite, history, count, "prefix count %d" % count)
	var gap := history.duplicate(true)
	gap[1].capture_sequence = 3
	_check(suite, gap, -1, "capture sequence gap")
	gap[1].capture_sequence = 1
	_check(suite, gap, -1, "duplicate capture sequence")
	var wrong_type := history.duplicate(true)
	wrong_type[0].frame = 0.0
	_check(suite, wrong_type, -1, "warm valid integer replaced by canonical-equivalent float")
	var typed_names: Array[StringName] = [&"first", &"second"]
	var typed_values: Dictionary[StringName, Vector2] = {&"direction": Vector2.ONE}
	var object_array: Array[Node] = []
	for payload: Dictionary in [
		{"value": typed_names}, {"value": typed_values}, {"value": object_array},
		{"value": &"name"}, {"value": "name"}, {"value": 1}, {"value": 1.0},
		{"value": 0.0}, {"value": -0.0}, {"value": 1.000000000000001},
		{"value": Vector2(NAN, 0)}, {"value": PackedVector2Array([Vector2(NAN, 0)])},
		{"a": 1, "b": 2}, {"b": 2, "a": 1},
	]:
		_check(suite, [_event(1, payload)], -1, "safe typed payload cold")
		_check(suite, [_event(1, payload)], -1, "safe typed payload warm")
	for unsafe: Variant in [self, Callable(self, "_run"), get_tree().process_frame, NAN, INF, PackedFloat32Array([NAN]), PackedFloat64Array([INF])]:
		var invalid := _event(1, {"nested": {"unsafe": unsafe}})
		var entries_before: int = Replay._capture_digest_cache.snapshot().entries
		suite.assert_equal(Replay.capture_event_digest(invalid), "", "unsafe projected payload refuses without serialization")
		suite.assert_equal(Replay._capture_digest_cache.snapshot().entries, entries_before, "failed digest never enters positive cache")
		_check(suite, [invalid], 0, "unused unsafe suffix preserves empty-prefix acceptance")
	var null_event := _event(1, {"nested": {"value": null}})
	_check(suite, [null_event], 1, "safe null warms both caches")
	var manual_object := Node.new()
	var freed_reference: Variant = manual_object
	manual_object.free()
	var freed_event := _event(1, {"nested": {"value": freed_reference}})
	suite.assert_equal(var_to_bytes(freed_event), var_to_bytes(null_event), "native bytes alias a freed Object and safe null")
	suite.assert_equal(Replay.capture_event_digest(freed_event), "", "freed Object cannot reuse a safe-null positive digest")
	suite.assert_equal(Replay.event_prefix_root([freed_event], 1), "", "freed Object cannot reuse a safe-null prefix")
	_check(suite, [freed_event], 0, "unused freed Object preserves empty-prefix acceptance")
	var extra := _event(1, {"safe": true})
	extra.ignored = self
	suite.assert_equal(Replay.capture_event_digest(extra), _legacy_capture(extra), "ignored unsafe extra field retains capture acceptance")
	_check(suite, [extra], 1, "unsafe extra fields fall back without changing prefix")
	suite.assert_equal(Replay.event_prefix_root([17], 0), _legacy_prefix([], 0), "non-dictionary unused suffix retains empty prefix")
	suite.assert_equal(Replay.event_prefix_root([17], 1), "", "non-dictionary selected prefix refuses without indexing error")
	var threads: Array[Thread] = []
	for worker: int in range(4):
		var thread := Thread.new()
		thread.start(_concurrent.bind(worker))
		threads.append(thread)
	for thread: Thread in threads:
		suite.assert_true(thread.wait_to_finish(), "concurrent independent histories retain old canonical roots")
	suite.finish(get_tree())


func _check(suite: RefCounted, events: Array, count: int, label: String) -> void:
	suite.assert_equal(Replay.event_prefix_root(events, count), _legacy_prefix(events, count), label)
	for event: Variant in events:
		if event is Dictionary:
			suite.assert_equal(Replay.capture_event_digest(event), _legacy_capture(event), label + " capture digest")


static func _event(sequence: int, payload: Dictionary) -> Dictionary:
	return {"schema_version": 3, "frame": sequence - 1, "capture_sequence": sequence, "event_type": "external_fact", "payload": payload}


static func _legacy_capture(event: Dictionary) -> String:
	for field: String in ["schema_version", "frame", "capture_sequence", "event_type", "payload"]:
		if not event.has(field):
			return ""
	if (
		typeof(event.schema_version) != TYPE_INT or event.schema_version != 3
		or typeof(event.frame) != TYPE_INT or event.frame < 0
		or typeof(event.capture_sequence) != TYPE_INT or event.capture_sequence <= 0
		or typeof(event.event_type) not in [TYPE_STRING, TYPE_STRING_NAME]
		or str(event.event_type) not in ["weapon_intent", "external_fact"]
		or not event.payload is Dictionary or not Replay.replay_value_is_safe(event.payload)
	):
		return ""
	return Replay.value_digest({"schema_version": event.schema_version, "frame": event.frame, "capture_sequence": event.capture_sequence, "event_type": event.event_type, "payload": event.payload})


static func _legacy_prefix(events: Array, count: int = -1) -> String:
	var prefix_count := events.size() if count < 0 else count
	if prefix_count < 0 or prefix_count > events.size():
		return ""
	var ordered: Array[Dictionary] = []
	for event: Variant in events:
		if not event is Dictionary:
			return ""
		ordered.append(event.duplicate(true))
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("capture_sequence", 0)) < int(right.get("capture_sequence", 0))
	)
	var digests: Array[String] = []
	for index: int in range(prefix_count):
		if int(ordered[index].get("capture_sequence", 0)) != index + 1:
			return ""
		var digest := _legacy_capture(ordered[index])
		if digest.length() != 64:
			return ""
		digests.append(digest)
	return Replay.value_digest({"schema_id": Replay.EVENT_PREFIX_SCHEMA_ID, "schema_version": 1, "event_count": prefix_count, "capture_event_digests": digests})


func _concurrent(worker: int) -> bool:
	for index: int in range(50):
		var history := [_event(1, {"worker": worker, "index": index}), _event(2, {"value": Vector2.ONE})]
		var expected := _legacy_prefix(history)
		if Replay.event_prefix_root(history) != expected or Replay.event_prefix_root(history) != expected:
			return false
	return true
