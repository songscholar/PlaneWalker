class_name TestSuite
extends RefCounted

var failures: Array[String] = []
var _expected_engine_error_count := 0


func assert_true(value: bool, label: String) -> void:
	if not value:
		_fail(label, "expected true")


func assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail(label, "expected %s, got %s" % [str(expected), str(actual)])


func assert_close(actual: float, expected: float, label: String, tolerance: float = 0.001) -> void:
	if not is_finite(actual) or not is_finite(expected) or absf(actual - expected) > tolerance:
		_fail(label, "expected %.4f, got %.4f" % [expected, actual])


func expect_engine_error(operation: Callable, message: String, label: String, count: int = 1) -> bool:
	if not operation.is_valid() or message.is_empty() or label.is_empty() or count < 1:
		_fail(label, "invalid exact expected-error operation")
		return false
	_expected_engine_error_count += 1
	var scope_id := "%d:%d" % [get_instance_id(), _expected_engine_error_count]
	print("PLANEWALKER_EXPECTED_ENGINE_ERROR_BEGIN ", JSON.stringify({"schema_version": 1, "scope_id": scope_id, "operation": label, "expected": [{"message": message, "count": count}]}))
	var result: Variant = operation.call()
	assert_true(result is bool and result == false, "expected-error operation actually refuses: " + label)
	print("PLANEWALKER_EXPECTED_ENGINE_ERROR_END ", JSON.stringify({"schema_version": 1, "scope_id": scope_id, "operation": label, "result": result}))
	return result == true


func expect_rejected_player_frame(player: Node, intents: Dictionary = {}, prefix: String = "Fixed-frame event buffer settlement rejected runtime frame") -> bool:
	var frame := int(player.priority_arbitration_snapshot().frame) + 1
	return expect_engine_error(Callable(player, "advance_action_frame").bind(intents), "%s %d" % [prefix, frame], "Player.advance_action_frame(frame=%d)" % frame)


func finish(tree: SceneTree) -> void:
	if failures.is_empty():
		print("PASS: all assertions succeeded")
		_quit_after_audio_drain(tree, 0)
		return
	for failure: String in failures:
		push_error(failure)
	_quit_after_audio_drain(tree, 1)


func _quit_after_audio_drain(tree: SceneTree, code: int) -> void:
	# Playback retirement is queued to Godot's mixer thread after node disposal.
	tree.create_timer(0.1, true, false, true).timeout.connect(tree.quit.bind(code), CONNECT_ONE_SHOT)


func _fail(label: String, detail: String) -> void:
	failures.append("%s: %s" % [label, detail])
