class_name TestSuite
extends RefCounted

var failures: Array[String] = []


func assert_true(value: bool, label: String) -> void:
	if not value:
		_fail(label, "expected true")


func assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail(label, "expected %s, got %s" % [str(expected), str(actual)])


func assert_close(actual: float, expected: float, label: String, tolerance: float = 0.001) -> void:
	if not is_finite(actual) or not is_finite(expected) or absf(actual - expected) > tolerance:
		_fail(label, "expected %.4f, got %.4f" % [expected, actual])


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
