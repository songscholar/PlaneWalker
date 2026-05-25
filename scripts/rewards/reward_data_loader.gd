class_name RewardDataLoader
extends RefCounted


static func load_array(path: String, fallback: Array[Dictionary]) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		return fallback.duplicate(true)

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not open reward data file: %s" % path)
		return fallback.duplicate(true)

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		push_warning("Reward data file must contain an array: %s" % path)
		return fallback.duplicate(true)

	var loaded: Array[Dictionary] = []
	for entry: Variant in parsed:
		if typeof(entry) == TYPE_DICTIONARY and not str(entry.get("id", "")).is_empty():
			loaded.append((entry as Dictionary).duplicate(true))
	if loaded.is_empty():
		push_warning("Reward data file contains no valid entries: %s" % path)
		return fallback.duplicate(true)
	return loaded
