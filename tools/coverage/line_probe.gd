extends Node

static var _hits: Dictionary = {}
static var _enabled := not OS.get_environment("PLANEWALKER_COVERAGE_HITS_DIR").is_empty()


static func mark(path: String, line: int) -> bool:
	if _enabled:
		if not _hits.has(path):
			_hits[path] = {}
		_hits[path][line] = true
	return true


func _exit_tree() -> void:
	if not _enabled:
		return
	var directory := OS.get_environment("PLANEWALKER_COVERAGE_HITS_DIR")
	if not directory.is_absolute_path() or DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Runtime line coverage cannot create its isolated report directory")
		return
	var recorded: Dictionary = {}
	for path: String in _hits:
		var lines: Array = _hits[path].keys()
		lines.sort()
		recorded[path] = lines
	var scene_id := OS.get_environment("PLANEWALKER_COVERAGE_SCENE_ID")
	if not scene_id.is_empty() and (scene_id.contains("/") or scene_id.contains("\\") or scene_id.contains("..")):
		push_error("Runtime line coverage received an invalid scene report identity")
		return
	var filename := "pid-%d.json" % OS.get_process_id()
	if not scene_id.is_empty():
		filename = "scene-%s-%s" % [scene_id, filename]
	var file := FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
	if file == null:
		push_error("Runtime line coverage cannot persist its physical report")
		return
	file.store_string(JSON.stringify({"schema_version": 1, "manifest_sha256": OS.get_environment("PLANEWALKER_COVERAGE_MANIFEST_SHA256"), "hits": recorded}, "", true, true) + "\n")
	file.close()
