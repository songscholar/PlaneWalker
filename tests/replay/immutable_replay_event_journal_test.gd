extends Node

const Suite := preload("res://tests/support/test_suite.gd")
const Replay := preload("res://scripts/replay/replay_recorder.gd")
const JOURNAL_PATH := "res://scripts/replay/immutable_replay_event_journal.gd"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var suite := Suite.new()
	suite.assert_true(ResourceLoader.exists(JOURNAL_PATH), "owned immutable event journal exists")
	if not ResourceLoader.exists(JOURNAL_PATH):
		suite.finish(get_tree())
		return
	var journal_script: GDScript = load(JOURNAL_PATH)
	var journal: RefCounted = journal_script.new()
	var original_event := _event(1, {"nested": [{"value": 1}], "values": [1, 2]})
	var history: Array[Dictionary] = [original_event, _event(2, {"value": Vector2.ONE})]
	var original_bytes := var_to_bytes(history)
	_check(suite, journal, history, "initial certification")
	suite.assert_equal(var_to_bytes(history), original_bytes, "sealing preserves full typed bytes")
	suite.assert_true(not is_same(history[0], original_event), "owned event detaches caller aliases")
	suite.assert_true(_deep_read_only(history), "all event descendants are recursively immutable")
	original_event.payload.nested[0].value = 99
	suite.assert_equal(history[0].payload.nested[0].value, 1, "old caller alias cannot change certified event")
	var before: Dictionary = journal.snapshot()
	for _iteration: int in range(100):
		_check(suite, journal, history, "unchanged exact refs")
	suite.assert_equal(journal.snapshot().certifications, before.certifications, "unchanged refs require no new event certification")
	suite.assert_equal(journal.snapshot().root_builds, before.root_builds, "unchanged refs require no new canonical root")
	var public_copy: Array[Dictionary] = history.duplicate(true)
	suite.assert_true(not public_copy[0].is_read_only() and not public_copy[0].payload.nested.is_read_only(), "public deep copy restores mutable containers")
	public_copy[0].payload.nested[0].value = 20
	suite.assert_equal(history[0].payload.nested[0].value, 1, "public deep-copy mutation is detached")
	var preimage := history.duplicate(false)
	history[0] = _event(1, {"data": {"state_after": {"receipt": 2}}})
	_check(suite, journal, history, "same-count completed fact replacement")
	suite.assert_equal(preimage[0].payload.nested[0].value, 1, "shallow preimage preserves replaced slot")
	suite.assert_true(not journal.certifies(preimage), "stale same-count refs cannot certify current history")
	history = preimage
	_check(suite, journal, history, "historical rollback restore")
	history.append(_event(3, {"appended": true}))
	_check(suite, journal, history, "append")
	history.reverse()
	_check(suite, journal, history, "playback reorder")
	history.resize(2)
	_check(suite, journal, history, "truncate with missing capture-one")
	var null_history: Array[Dictionary] = [_event(1, {"value": null})]
	_check(suite, journal, null_history, "safe null certification")
	var node := Node.new()
	var freed: Variant = node
	node.free()
	var unsafe: Array[Dictionary] = [_event(1, {"value": freed})]
	suite.assert_equal(var_to_bytes(unsafe), var_to_bytes(null_history), "freed Object collides with safe-null bytes")
	var unsafe_bytes := var_to_bytes(unsafe)
	suite.assert_true(journal.refresh(unsafe).is_empty(), "freed Object cannot acquire an immutable certificate")
	suite.assert_equal(var_to_bytes(unsafe), unsafe_bytes, "failed certification leaves input untouched")
	suite.assert_true(not journal.certifies(null_history) and not journal.certifies(unsafe), "failed refresh invalidates shortcut eligibility")
	_check(suite, journal, null_history, "previous valid refs reauthenticate after failed refresh")
	var packed_history: Array[Dictionary] = [_event(1, {"packed": PackedByteArray([1, 2])})]
	var packed_bytes := var_to_bytes(packed_history)
	suite.assert_true(journal.refresh(packed_history).is_empty(), "mutable packed descendants retain cold fallback")
	suite.assert_true(not journal.certifies(packed_history), "packed descendants cannot acquire reference certificates")
	suite.assert_equal(var_to_bytes(packed_history), packed_bytes, "packed fallback preserves complete source bytes")
	var gap: Array[Dictionary] = [_event(1, {}), _event(3, {})]
	_check(suite, journal, gap, "pending capture gap")
	var duplicate: Array[Dictionary] = [_event(1, {}), _event(1, {}), _event(2, {})]
	suite.assert_true(journal.refresh(duplicate).is_empty(), "duplicate selected capture sequence cannot certify root")
	duplicate.resize(2)
	suite.assert_true(journal.refresh(duplicate).is_empty(), "unused duplicate capture suffix conservatively falls back")
	var foreign: RefCounted = journal_script.new()
	suite.assert_true(not foreign.certifies(null_history), "foreign readonly history is not trusted by another journal")
	_check(suite, foreign, null_history, "foreign history must authenticate independently")
	var empty: Array[Dictionary] = []
	_check(suite, journal, empty, "reset empty history")
	suite.assert_equal(journal.snapshot().retained_events, 0, "reset retires discarded certificate refs")
	suite.finish(get_tree())


func _check(suite: RefCounted, journal: RefCounted, history: Array[Dictionary], label: String) -> void:
	var count := _prefix_count(history)
	var expected := Replay.event_prefix_root(history, count)
	var result: Dictionary = journal.refresh(history)
	suite.assert_true(not result.is_empty(), label + " certifies")
	if result.is_empty():
		return
	suite.assert_equal(result.event_prefix_count, count, label + " count")
	suite.assert_equal(result.event_prefix_root, expected, label + " canonical root")
	suite.assert_true(journal.certifies(history), label + " current exact refs")


static func _event(sequence: int, payload: Dictionary) -> Dictionary:
	return {"schema_version": 3, "frame": sequence - 1, "capture_sequence": sequence, "event_type": "external_fact", "payload": payload}


static func _prefix_count(events: Array[Dictionary]) -> int:
	var captures: Dictionary = {}
	for event: Dictionary in events:
		if int(event.get("capture_sequence", 0)) > 0:
			captures[int(event.capture_sequence)] = true
	var count := 0
	while captures.has(count + 1):
		count += 1
	return count


static func _deep_read_only(events: Array[Dictionary]) -> bool:
	for event: Dictionary in events:
		if not _frozen(event):
			return false
	return true


static func _frozen(value: Variant) -> bool:
	if value is Dictionary:
		if not value.is_read_only():
			return false
		for child: Variant in value.values():
			if not _frozen(child):
				return false
	elif value is Array:
		if not value.is_read_only():
			return false
		for child: Variant in value:
			if not _frozen(child):
				return false
	return true
