class_name PlaytestSerializer
extends RefCounted


static func to_json_line(value: Dictionary) -> String:
	return JSON.stringify(value, "", true, false).replace("\n", "")


static func from_json_line(line: String) -> Dictionary:
	if line.strip_edges().is_empty():
		return {"ok": false, "error": "JSONL line is blank"}
	var parser := JSON.new()
	var parse_error := parser.parse(line)
	if parse_error != OK:
		return {
			"ok": false,
			"error": parser.get_error_message(),
			"error_line": parser.get_error_line(),
		}
	if not parser.data is Dictionary:
		return {"ok": false, "error": "JSONL record must be an object"}
	return {"ok": true, "value": parser.data}


static func append_json_line(path: String, value: Dictionary) -> Dictionary:
	if path.strip_edges().is_empty():
		return {"ok": false, "error": "JSONL path is blank"}
	var directory_path := ProjectSettings.globalize_path(path).get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(directory_path)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "unable to create JSONL directory", "error_code": directory_error}
	var mode := FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	var file := FileAccess.open(path, mode)
	if file == null:
		return {"ok": false, "error": "unable to open JSONL path", "error_code": FileAccess.get_open_error()}
	if mode == FileAccess.READ_WRITE:
		file.seek_end()
	file.store_line(to_json_line(value))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return {"ok": false, "error": "unable to write JSONL record", "error_code": write_error}
	return {"ok": true}
