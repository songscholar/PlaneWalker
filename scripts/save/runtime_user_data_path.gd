extends RefCounted


static func resolve_default(default_path: String, suffix: String) -> String:
	var root := OS.get_environment("PLANEWALKER_USER_DATA_DIR").strip_edges()
	if root.is_empty():
		root = OS.get_environment("PLANEWALKER_TEST_DATA_DIR").strip_edges()
	if root.is_empty():
		return default_path
	if not root.is_absolute_path() or root.begins_with("user://") or root.begins_with("res://"):
		return ""
	return root.simplify_path().path_join(suffix)
