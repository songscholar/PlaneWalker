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
		tree.quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	tree.quit(1)


func _fail(label: String, detail: String) -> void:
	failures.append("%s: %s" % [label, detail])
