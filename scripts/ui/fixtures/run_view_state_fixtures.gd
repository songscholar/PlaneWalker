class_name RunViewStateFixtures
extends RefCounted

const RunViewStateScript := preload("res://scripts/ui/contracts/run_view_state.gd")


static func load_fixture(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("UI fixture does not exist: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("UI fixture could not be opened: %s" % path)
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("UI fixture JSON parse failed at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {}
	var value: Variant = json.data
	var validation = RunViewStateScript.validate(value)
	if not validation.ok:
		push_error("UI fixture validation failed: %s" % str(validation.context))
		return {}
	return RunViewStateScript.copy_of(value)
